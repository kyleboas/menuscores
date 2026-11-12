import Foundation
import Observation

/// Owns the per-day game cache, the freshness state and the refresh cadence.
/// Keeps the last good data on failure — but never without exposing
/// `freshness`, so the UI cannot render stale data as current.
@Observable
@MainActor
public final class ScoreStore {
    /// Games keyed by the civil day they fall on in `zone`.
    public private(set) var gamesByDay: [CivilDay: [Game]] = [:]
    public private(set) var freshness = Freshness()
    public private(set) var isRefreshing = false

    /// Which day the dropdown is showing.
    public var selectedDay: CivilDay {
        didSet {
            guard selectedDay != oldValue else { return }
            Task { await self.load(days: [selectedDay]) }
        }
    }

    public var preferences: Preferences {
        didSet {
            guard preferences != oldValue else { return }
            preferences.save()
            if preferences.favoriteTeamIDs != oldValue.favoriteTeamIDs {
                // A newly starred team's other competitions are unknown until
                // its schedule is in; fetch that, then the days it plays.
                Task {
                    await self.loadSchedules()
                    await self.refresh()
                }
            }
            // Only a change to the league set invalidates what we have cached.
            // Favourites and collapse state are pure display filters, so they
            // must re-render instantly rather than blanking the list while a
            // refetch runs.
            guard preferences.enabledLeagueIDs != oldValue.enabledLeagueIDs else { return }
            gamesByDay.removeAll()
            Task { await refresh() }
        }
    }

    /// How far the day strip reaches either side of today.
    public let pastDays = 2
    public let futureDays = 7
    public var zone: TimeZone = .current

    private let provider: ScoreProvider
    private var consecutiveFailures = 0
    private var timer: Task<Void, Never>?
    private let now: @Sendable () -> Date

    public init(provider: ScoreProvider = ESPNProvider(),
                preferences: Preferences = .load(),
                zone: TimeZone = .current,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.provider = provider
        self.preferences = preferences
        self.zone = zone
        self.now = now
        let t = CivilDay.today(in: zone, now: now())
        self.today = t
        self.selectedDay = t
    }

    // MARK: - Day strip

    /// The civil day the store believes it is. Stored rather than derived from
    /// the clock so the UI observes it: a computed value never invalidated the
    /// views, which left a long-running app stuck on its launch day.
    public private(set) var today: CivilDay

    /// Moves the store onto the clock's day once midnight has passed. Returns
    /// whether the day changed. A rollover reselects today, so the dropdown
    /// never keeps showing a day that has become history.
    @discardableResult
    public func syncDay() -> Bool {
        let t = CivilDay.today(in: zone, now: now())
        guard t != today else { return false }
        today = t
        selectedDay = t
        return true
    }

    public var dayStrip: [CivilDay] {
        let t = today
        return (-pastDays...futureDays).map { t.adding(days: $0, in: zone) }
    }

    /// "Yesterday" / "Today" / "Tomorrow", else a weekday + date.
    public func label(for day: CivilDay) -> String {
        let t = today
        if day == t { return "Today" }
        if day == t.adding(days: -1, in: zone) { return "Yesterday" }
        if day == t.adding(days: 1, in: zone) { return "Tomorrow" }
        let f = DateFormatter()
        f.timeZone = zone
        f.dateFormat = "EEE d MMM"
        return f.string(from: day.startOfDay(in: zone))
    }

    // MARK: - Derived views

    /// A game from an enabled league, or one a followed team plays in any
    /// other competition — a cup tie shows up without enabling the cup.
    public func games(on day: CivilDay) -> [Game] {
        let enabled = preferences.enabledLeagueIDs
        let favs = preferences.favoriteTeamIDs
        return (gamesByDay[day] ?? []).filter {
            (enabled.contains($0.league.id) || !$0.involves.isDisjoint(with: favs))
                && preferences.matches($0)
        }
    }

    /// The selected day's games grouped into league sections, ordered by the
    /// league list so the sections do not reshuffle between refreshes.
    public var sections: [(league: League, games: [Game])] {
        let games = games(on: selectedDay)
        let order = preferences.leagues.map(\.id)
        return Dictionary(grouping: games) { $0.league }
            .map { (league: $0.key, games: $0.value.sorted(by: Self.rowOrder)) }
            .sorted {
                let a = order.firstIndex(of: $0.league.id) ?? .max
                let b = order.firstIndex(of: $1.league.id) ?? .max
                return a == b ? $0.league.name < $1.league.name : a < b
            }
    }

    /// Live games first, then by kickoff.
    private static func rowOrder(_ a: Game, _ b: Game) -> Bool {
        if a.isLive != b.isLive { return a.isLive }
        if a.start != b.start { return a.start < b.start }
        return a.id < b.id
    }

    public var live: [Game] {
        games(on: today).filter(\.isLive).sorted(by: Self.rowOrder)
    }

    /// Whether any refresh has completed, so the menu bar can tell
    /// "starting up" apart from "nothing on today".
    public var hasLoaded: Bool { freshness.lastSuccess != nil }

    /// Menu bar line: a live game if there is one, else today's next kickoff,
    /// else tomorrow's first.
    public var pinned: Game? {
        if let l = live.first { return l }
        let t = today
        if let next = games(on: t).first(where: { $0.state == .scheduled && $0.start >= now() }) {
            return next
        }
        return games(on: t.adding(days: 1, in: zone))
            .filter { $0.state == .scheduled }
            .min { $0.start < $1.start }
    }

    // MARK: - Followed teams, across every competition

    /// Each followed team's season, keyed by team id. Drives which extra
    /// competitions get fetched on a given day, and the head-to-head list.
    public private(set) var schedules: [String: [Game]] = [:]
    public private(set) var loadingSchedules = false
    private var schedulesLoadedAt: Date?
    /// Fixtures move (TV picks, cup draws), but not by the minute.
    static let scheduleLifetime: TimeInterval = 6 * 3600

    /// Fetches schedules for followed teams that do not have one yet, and
    /// all of them once they are older than `scheduleLifetime`.
    public func loadSchedules() async {
        guard !loadingSchedules else { return }
        loadingSchedules = true
        defer { loadingSchedules = false }

        let ids = preferences.favoriteTeamIDs.filter { $0.contains(":") }
        let stale = schedulesLoadedAt.map { now().timeIntervalSince($0) > Self.scheduleLifetime } ?? true
        let wanted = stale ? ids : ids.subtracting(schedules.keys)
        schedules = schedules.filter { ids.contains($0.key) }
        guard !wanted.isEmpty else { return }

        let provider = self.provider
        let results = await withTaskGroup(of: (String, [Game]?).self) { group in
            for id in wanted {
                group.addTask { (id, try? await provider.schedule(for: id)) }
            }
            var out: [(String, [Game]?)] = []
            for await r in group { out.append(r) }
            return out
        }
        var anyOK = false
        for (id, games) in results {
            // A failed fetch keeps the old schedule rather than forgetting it.
            if let games { schedules[id] = games; anyOK = true }
        }
        if stale && anyOK { schedulesLoadedAt = now() }
    }

    /// Every followed team's games, once each.
    private var followedGames: [Game] {
        var seen = Set<String>()
        return schedules.values.joined().filter { seen.insert($0.id).inserted }
    }

    /// Followed teams by name, for the settings list. Taken from their own
    /// schedules where possible, so a team stays listed after its league is
    /// switched off.
    public var followedTeams: [Team] {
        var byID: [String: Team] = [:]
        for t in teamsByLeague.values.joined() where isFavorite(t) { byID[t.id] = t }
        for g in followedGames {
            for t in [g.home, g.away] where isFavorite(t) && byID[t.id] == nil { byID[t.id] = t }
        }
        return byID.values.sorted { $0.name < $1.name }
    }

    /// Games where both sides are followed teams: recent results and every
    /// fixture still to come this season. Today's games are taken from the
    /// scoreboard cache so a live score is current.
    public var headToHead: (recent: [Game], upcoming: [Game]) {
        let favs = preferences.favoriteTeamIDs
        let live = Dictionary(gamesByDay.values.joined().map { ($0.id, $0) },
                              uniquingKeysWith: { a, _ in a })
        let games = followedGames
            .filter { favs.contains($0.home.id) && favs.contains($0.away.id) }
            .map { live[$0.id] ?? $0 }
        let cutoff = now().addingTimeInterval(-3 * 3600)
        let recent = games.filter { $0.state == .final || ($0.start < cutoff && !$0.isLive) }
            .sorted { $0.start > $1.start }
        let upcoming = games.filter { !recent.contains($0) }
            .sorted { $0.start < $1.start }
        return (Array(recent.prefix(5)), upcoming)
    }

    /// Which competitions each day needs beyond the enabled ones, from the
    /// followed teams' schedules.
    private func extraLeagues(on day: CivilDay) -> [League] {
        let enabled = preferences.enabledLeagueIDs
        var seen = Set<String>()
        return followedGames
            .filter { CivilDay($0.start, in: zone) == day }
            .map(\.league)
            .filter { !enabled.contains($0.id) && $0.id != "all" && seen.insert($0.id).inserted }
    }

    // MARK: - Teams, for picking favourites

    /// Team rosters per league, loaded on demand by the settings window.
    public private(set) var teamsByLeague: [String: [Team]] = [:]
    public private(set) var loadingTeams = false

    public func loadTeams() async {
        guard !loadingTeams else { return }
        loadingTeams = true
        defer { loadingTeams = false }
        for league in preferences.leagues where teamsByLeague[league.id] == nil {
            if let teams = try? await provider.teams(in: league) {
                teamsByLeague[league.id] = teams
            }
        }
        migrateLegacyFavorites()
    }

    /// Whether favourites saved before team ids carried their sport are
    /// still waiting to be resolved against the team lists.
    public var hasLegacyFavorites: Bool {
        preferences.favoriteTeamIDs.contains { !$0.contains(":") }
    }

    /// Rewrites bare favourite ids saved by older builds. An id that names
    /// exactly one team across the enabled leagues is kept under its sport;
    /// one shared by several sports cannot be told apart and is dropped, so
    /// it has to be starred again. Waits until every league's teams are in,
    /// so a failed fetch cannot make an ambiguous id look unique.
    func migrateLegacyFavorites() {
        guard hasLegacyFavorites,
              preferences.leagues.allSatisfy({ teamsByLeague[$0.id] != nil }) else { return }
        let known = Set(teamsByLeague.values.joined().map(\.id))
        var ids = preferences.favoriteTeamIDs.filter { $0.contains(":") }
        for bare in preferences.favoriteTeamIDs where !bare.contains(":") {
            let matches = known.filter { $0.hasSuffix(":" + bare) }
            if matches.count == 1 { ids.formUnion(matches) }
        }
        preferences.favoriteTeamIDs = ids
    }

    public func isFavorite(_ team: Team) -> Bool {
        preferences.favoriteTeamIDs.contains(team.id)
    }

    public func toggleFavorite(_ team: Team) {
        if preferences.favoriteTeamIDs.contains(team.id) {
            preferences.favoriteTeamIDs.remove(team.id)
        } else {
            preferences.favoriteTeamIDs.insert(team.id)
        }
    }

    // MARK: - Refresh

    public func start() {
        if hasLegacyFavorites { Task { await loadTeams() } }
        timer?.cancel()
        timer = Task { [weak self] in
            var firstPass = true
            while !Task.isCancelled {
                guard let self else { return }
                let rolledOver = await MainActor.run { self.syncDay() }
                await self.loadSchedules()
                // Full sweep on the first pass and on slow ticks; while games
                // are live the fast tick only refetches today, because that is
                // the only day whose scores can change.
                let fast = await MainActor.run { !self.live.isEmpty } && !firstPass && !rolledOver
                if fast {
                    await self.load(days: [self.today])
                } else {
                    await self.refresh()
                }
                firstPass = false
                let delay = await MainActor.run {
                    RefreshPolicy.interval(hasLive: !self.live.isEmpty,
                                           nextStart: self.pinned?.start,
                                           failures: self.consecutiveFailures,
                                           now: self.now())
                }
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    public func stop() { timer?.cancel(); timer = nil }

    /// What is on screen, plus the days the menu bar line is drawn from.
    private var workingSet: [CivilDay] {
        let t = today
        let days = [t, selectedDay, t.adding(days: 1, in: zone)]
        var seen = Set<CivilDay>()
        return days.filter { seen.insert($0).inserted }
    }

    public func refresh() async {
        await load(days: workingSet)
    }

    /// Fetches the given days for every enabled league.
    public func load(days: [CivilDay]) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let leagues = preferences.leagues
        let following = !schedules.isEmpty
        guard !leagues.isEmpty || following, !days.isEmpty else {
            if leagues.isEmpty { gamesByDay.removeAll() }
            freshness.lastSuccess = now()
            freshness.lastFailure = nil
            return
        }

        let zone = self.zone
        var fetched: [CivilDay: [Game]] = [:]
        var firstError: ProviderError?
        var anySuccess = false

        for day in days {
            var dayGames: [Game] = []
            let toFetch = leagues + extraLeagues(on: day)
            // Nothing to ask the feed for (only followed teams, none playing
            // in a fetchable competition) is not a failure.
            if toFetch.isEmpty { anySuccess = true }
            for league in toFetch {
                do {
                    dayGames += try await provider.games(on: day, league: league, zone: zone)
                    anySuccess = true
                } catch let e as ProviderError {
                    if firstError == nil { firstError = e }
                } catch {
                    if firstError == nil { firstError = .transport(error.localizedDescription) }
                }
            }
            // A followed team's game the scoreboards did not return (a
            // competition with no day scoreboard) still shows, from its
            // schedule entry.
            dayGames += followedGames.filter { CivilDay($0.start, in: zone) == day }
            var seen = Set<String>()
            fetched[day] = dayGames.filter { seen.insert($0.id).inserted }
        }

        guard anySuccess else {
            // Nothing came back: keep the cache and mark it stale.
            consecutiveFailures += 1
            freshness.lastFailure = (at: now(), reason: Self.describe(firstError ?? .transport("no connection")))
            return
        }

        for (day, games) in fetched { gamesByDay[day] = games }
        consecutiveFailures = 0
        freshness.lastSuccess = now()
        freshness.lastFailure = firstError.map { (at: now(), reason: Self.describe($0)) }
    }

    static func describe(_ e: ProviderError) -> String {
        switch e {
        case .transport(let m): return m.isEmpty ? "no connection" : m
        case .badStatus(let c): return "feed returned \(c)"
        case .malformed(let m): return "unexpected data (\(m))"
        }
    }
}
