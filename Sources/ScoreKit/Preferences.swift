import Foundation

/// Local only. No account, no analytics, no network writes.
public struct Preferences: Codable, Sendable, Equatable {
    public var enabledLeagueIDs: Set<String>
    /// Following: every game these teams play, whoever the opponent.
    /// (Stored under its original name so existing settings carry over.)
    public var favoriteTeamIDs: Set<String>
    /// Watching: a game only when the opponent is also followed or watched.
    public var watchingTeamIDs: Set<String>
    /// When true, only favourite teams' games are shown.
    public var favoritesOnly: Bool
    /// League sections the user has folded shut.
    public var collapsedLeagueIDs: Set<String>

    public init(enabledLeagueIDs: Set<String> = ["eng.1", "esp.1", "ger.1",
                                                 "ita.1", "fra.1", "uefa.champions",
                                                 "fifa.world", "fifa.worldq.uefa",
                                                 "uefa.nations", "uefa.euro"],
                favoriteTeamIDs: Set<String> = [],
                watchingTeamIDs: Set<String> = [],
                favoritesOnly: Bool = false,
                collapsedLeagueIDs: Set<String> = []) {
        self.enabledLeagueIDs = enabledLeagueIDs
        self.favoriteTeamIDs = favoriteTeamIDs
        self.watchingTeamIDs = watchingTeamIDs.subtracting(favoriteTeamIDs)
        self.favoritesOnly = favoritesOnly
        self.collapsedLeagueIDs = collapsedLeagueIDs
    }

    public func isCollapsed(_ league: League) -> Bool {
        collapsedLeagueIDs.contains(league.id)
    }

    public mutating func toggleCollapsed(_ league: League) {
        if collapsedLeagueIDs.contains(league.id) {
            collapsedLeagueIDs.remove(league.id)
        } else {
            collapsedLeagueIDs.insert(league.id)
        }
    }

    public var leagues: [League] {
        League.defaults.filter { enabledLeagueIDs.contains($0.id) }
    }

    enum CodingKeys: String, CodingKey {
        case enabledLeagueIDs, favoriteTeamIDs, watchingTeamIDs, favoritesOnly, collapsedLeagueIDs
    }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        enabledLeagueIDs = try c.decode(Set<String>.self, forKey: .enabledLeagueIDs)
        favoriteTeamIDs = try c.decode(Set<String>.self, forKey: .favoriteTeamIDs)
        watchingTeamIDs = try c.decodeIfPresent(Set<String>.self, forKey: .watchingTeamIDs) ?? []
        favoritesOnly = try c.decode(Bool.self, forKey: .favoritesOnly)
        collapsedLeagueIDs = try c.decodeIfPresent(Set<String>.self, forKey: .collapsedLeagueIDs) ?? []
    }

    /// Every team on either list.
    public var trackedTeamIDs: Set<String> { favoriteTeamIDs.union(watchingTeamIDs) }

    /// A followed team plays, or two tracked teams meet. A watched team
    /// against anyone else is not of interest.
    public func isOfInterest(_ g: Game) -> Bool {
        if !g.involves.isDisjoint(with: favoriteTeamIDs) { return true }
        let tracked = trackedTeamIDs
        return tracked.contains(g.home.id) && tracked.contains(g.away.id)
    }

    public func matches(_ g: Game) -> Bool {
        guard favoritesOnly, !trackedTeamIDs.isEmpty else { return true }
        return isOfInterest(g)
    }

    // MARK: - Persistence

    private static let key = "MenuScores.preferences"

    public static func load(from d: UserDefaults = .standard) -> Preferences {
        guard let data = d.data(forKey: key),
              let p = try? JSONDecoder().decode(Preferences.self, from: data) else {
            return Preferences()
        }
        return p
    }

    public func save(to d: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            d.set(data, forKey: Self.key)
        }
    }
}
