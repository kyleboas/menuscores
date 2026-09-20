import Foundation

/// Local only. No account, no analytics, no network writes.
public struct Preferences: Codable, Sendable, Equatable {
    public var enabledLeagueIDs: Set<String>
    public var favoriteTeamIDs: Set<String>
    /// When true, only favourite teams' games are shown.
    public var favoritesOnly: Bool
    /// League sections the user has folded shut.
    public var collapsedLeagueIDs: Set<String>

    public init(enabledLeagueIDs: Set<String> = ["eng.1", "esp.1", "ger.1",
                                                 "ita.1", "fra.1", "uefa.champions"],
                favoriteTeamIDs: Set<String> = [],
                favoritesOnly: Bool = false,
                collapsedLeagueIDs: Set<String> = []) {
        self.enabledLeagueIDs = enabledLeagueIDs
        self.favoriteTeamIDs = favoriteTeamIDs
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
        case enabledLeagueIDs, favoriteTeamIDs, favoritesOnly, collapsedLeagueIDs
    }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        enabledLeagueIDs = try c.decode(Set<String>.self, forKey: .enabledLeagueIDs)
        favoriteTeamIDs = try c.decode(Set<String>.self, forKey: .favoriteTeamIDs)
        favoritesOnly = try c.decode(Bool.self, forKey: .favoritesOnly)
        collapsedLeagueIDs = try c.decodeIfPresent(Set<String>.self, forKey: .collapsedLeagueIDs) ?? []
    }

    public func matches(_ g: Game) -> Bool {
        guard favoritesOnly, !favoriteTeamIDs.isEmpty else { return true }
        return !g.involves.isDisjoint(with: favoriteTeamIDs)
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
