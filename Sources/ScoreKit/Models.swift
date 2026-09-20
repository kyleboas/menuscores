import Foundation

/// A league we can ask a provider about. `path` is provider-agnostic here only
/// in the sense that providers map it themselves; ScoreKit never builds URLs.
public struct League: Hashable, Sendable, Codable, Identifiable {
    public let id: String          // stable key, e.g. "eng.1"
    public let name: String        // "Premier League"
    public let sport: String       // "soccer"

    public init(id: String, name: String, sport: String) {
        self.id = id; self.name = name; self.sport = sport
    }

    public static let defaults: [League] = [
        League(id: "eng.1",           name: "Premier League",  sport: "soccer"),
        League(id: "uefa.champions",  name: "Champions League", sport: "soccer"),
        League(id: "nfl",             name: "NFL",             sport: "football"),
        League(id: "nba",             name: "NBA",             sport: "basketball"),
        League(id: "nhl",             name: "NHL",             sport: "hockey"),
        League(id: "mlb",             name: "MLB",             sport: "baseball"),
    ]
}

public struct Team: Hashable, Sendable, Codable {
    public let id: String
    public let name: String        // full: "Manchester United"
    public let abbreviation: String // "MUN"
    public init(id: String, name: String, abbreviation: String) {
        self.id = id; self.name = name; self.abbreviation = abbreviation
    }
}

/// Deliberately models the states that break naive score apps.
public enum GameState: String, Sendable, Codable {
    case scheduled
    case live
    case final
    case postponed
    case canceled
    /// Provider reported something we do not understand. We show it rather
    /// than silently coercing it to `scheduled`.
    case unknown
}

public struct Game: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let league: League
    public let start: Date          // always absolute UTC instant
    public let state: GameState
    public let home: Team
    public let away: Team
    public let homeScore: Int?
    public let awayScore: Int?
    /// Short provider status text, e.g. "67'", "HALF", "Postponed", "FT".
    public let statusDetail: String

    public init(id: String, league: League, start: Date, state: GameState,
                home: Team, away: Team, homeScore: Int?, awayScore: Int?,
                statusDetail: String) {
        self.id = id; self.league = league; self.start = start; self.state = state
        self.home = home; self.away = away
        self.homeScore = homeScore; self.awayScore = awayScore
        self.statusDetail = statusDetail
    }

    public var isLive: Bool { state == .live }
    public var involves: Set<String> { [home.id, away.id] }

    /// "MUN 2–1 FUL" for played games, "MUN v FUL" before kickoff.
    public var compactLine: String {
        if let h = homeScore, let a = awayScore, state != .scheduled {
            return "\(home.abbreviation) \(h)–\(a) \(away.abbreviation)"
        }
        return "\(home.abbreviation) v \(away.abbreviation)"
    }
}
