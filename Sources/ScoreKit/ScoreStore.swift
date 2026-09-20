import Foundation
import Observation

/// Owns the cached games, the freshness state and the refresh cadence.
/// Deliberately keeps the last good data on failure — but never without
/// also exposing `freshness`, so the UI cannot render it as current.
@Observable
@MainActor
public final class ScoreStore {
    public private(set) var games: [Game] = []
    public private(set) var freshness = Freshness()
    public private(set) var isRefreshing = false

    public var preferences: Preferences {
        didSet {
            guard preferences != oldValue else { return }
            preferences.save()
            Task { await refresh() }
        }
    }

    /// Days ahead to show in the schedule section.
    public let horizon = 7
    public var zone: TimeZone = .current

    private let provider: ScoreProvider
    private var consecutiveFailures = 0
    private var timer: Task<Void, Never>?
    private let now: @Sendable () -> Date

    public init(provider: ScoreProvider = ESPNProvider(),
                preferences: Preferences = .load(),
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.provider = provider
        self.preferences = preferences
        self.now = now
    }

    // MARK: - Derived views used by the UI

    public var live: [Game] {
        games.filter { $0.isLive && preferences.matches($0) }
             .sorted { $0.start < $1.start }
    }

    public var today: [Game] {
        let t = CivilDay.today(in: zone, now: now())
        return games.filter {
            !$0.isLive && preferences.matches($0) && CivilDay($0.start, in: zone) == t
        }.sorted { $0.start < $1.start }
    }

    /// Tomorrow through the end of the horizon, grouped by civil day.
    public var upcoming: [(day: CivilDay, games: [Game])] {
        let t = CivilDay.today(in: zone, now: now())
        let end = t.adding(days: horizon, in: zone)
        let filtered = games.filter {
            guard preferences.matches($0) else { return false }
            let d = CivilDay($0.start, in: zone)
            return d > t && d <= end
        }
        return Dictionary(grouping: filtered) { CivilDay($0.start, in: zone) }
            .map { (day: $0.key, games: $0.value.sorted { $0.start < $1.start }) }
            .sorted { $0.day < $1.day }
    }

    /// What the menu bar itself shows: a live favourite first, else the next game.
    public var pinned: Game? {
        live.first ?? today.first { $0.state == .scheduled }
            ?? upcoming.first?.games.first
    }

    // MARK: - Refresh

    public func start() {
        timer?.cancel()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                guard let self else { return }
                let delay = await MainActor.run {
                    RefreshPolicy.interval(
                        hasLive: !self.live.isEmpty,
                        nextStart: self.pinned?.start,
                        failures: self.consecutiveFailures,
                        now: self.now())
                }
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    public func stop() { timer?.cancel(); timer = nil }

    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let leagues = preferences.leagues
        guard !leagues.isEmpty else {
            games = []
            freshness.lastSuccess = now()
            freshness.lastFailure = nil
            return
        }

        let today = CivilDay.today(in: zone, now: now())
        let end = today.adding(days: horizon, in: zone)
        let zone = self.zone
        let provider = self.provider

        var collected: [Game] = []
        var firstError: ProviderError?

        for league in leagues {
            // Optimisation only: when the provider publishes a day-shaped
            // calendar we skip empty days. When it does not (or the shape is
            // unreliable, as with MLB) we just ask for every day.
            var daysToFetch: [CivilDay] = (0...horizon).map { today.adding(days: $0, in: zone) }
            if let known = try? await provider.fixtureDays(from: today, through: end,
                                                           league: league, zone: zone),
               !known.isEmpty {
                // Always keep today: a live game must never be skipped because
                // the calendar disagrees.
                daysToFetch = daysToFetch.filter { known.contains($0) || $0 == today }
            }

            for day in daysToFetch {
                do {
                    collected += try await provider.games(on: day, league: league, zone: zone)
                } catch let e as ProviderError {
                    if firstError == nil { firstError = e }
                } catch {
                    if firstError == nil { firstError = .transport(error.localizedDescription) }
                }
            }
        }

        if let e = firstError, collected.isEmpty {
            // Total failure: keep whatever we had, and mark it.
            consecutiveFailures += 1
            freshness.lastFailure = (at: now(), reason: Self.describe(e))
            return
        }

        // De-duplicate: a game can surface from both a neighbouring day query
        // and its own, and leagues can overlap on cup weekends.
        var seen = Set<String>()
        games = collected.filter { seen.insert($0.id).inserted }
                         .sorted { $0.start < $1.start }
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
