import Foundation

/// Local only. No account, no analytics, no network writes.
public struct Preferences: Codable, Sendable, Equatable {
    public var enabledLeagueIDs: Set<String>
    public var favoriteTeamIDs: Set<String>
    /// When true, only favourite teams' games are shown.
    public var favoritesOnly: Bool

    public init(enabledLeagueIDs: Set<String> = ["eng.1", "nfl"],
                favoriteTeamIDs: Set<String> = [],
                favoritesOnly: Bool = false) {
        self.enabledLeagueIDs = enabledLeagueIDs
        self.favoriteTeamIDs = favoriteTeamIDs
        self.favoritesOnly = favoritesOnly
    }

    public var leagues: [League] {
        League.defaults.filter { enabledLeagueIDs.contains($0.id) }
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
