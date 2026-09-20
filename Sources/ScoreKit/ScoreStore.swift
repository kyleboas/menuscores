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

    public var preferences: Preferences {
        didSet {
            guard preferences != oldValue else { return }
            preferences.save()
            // Only a change to the league set invalidates what we have cached.
            // Favourites and collapse state are pure display filters, so they
            // must re-render instantly rather than blanking the list while a
            // refetch runs.
            guard preferences.enabledLeagueIDs != oldValue.enabledLeagueIDs else { return }
            gamesByDay.removeAll()
            Task { await refresh() }
        }
    }

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
    }

    public var today: CivilDay { CivilDay.today(in: zone, now: now()) }

    // MARK: - Derived views

    public func games(on day: CivilDay) -> [Game] {
        (gamesByDay[day] ?? []).filter { preferences.matches($0) }
    }

    /// Today's games grouped into league sections, ordered by the league list
    /// so the sections do not reshuffle between refreshes.
    public var sections: [(league: League, games: [Game])] {
        let games = games(on: today)
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

    // MARK: - Refresh

    public func start() {
        timer?.cancel()
        timer = Task { [weak self] in
            var firstPass = true
            while !Task.isCancelled {
                guard let self else { return }
                // Full sweep on the first pass and on slow ticks; while games
                // are live the fast tick only refetches today, because that is
                // the only day whose scores can change.
                let fast = await MainActor.run { !self.live.isEmpty } && !firstPass
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

    /// Today, plus tomorrow so the menu bar can name the next fixture once
    /// today's games are done.
    private var workingSet: [CivilDay] {
        let t = today
        return [t, t.adding(days: 1, in: zone)]
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
        guard !leagues.isEmpty, !days.isEmpty else {
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
            for league in leagues {
                do {
                    dayGames += try await provider.games(on: day, league: league, zone: zone)
                    anySuccess = true
                } catch let e as ProviderError {
                    if firstError == nil { firstError = e }
                } catch {
                    if firstError == nil { firstError = .transport(error.localizedDescription) }
                }
            }
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
