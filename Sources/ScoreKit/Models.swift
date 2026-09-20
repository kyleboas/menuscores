import Foundation

public struct League: Hashable, Sendable, Codable, Identifiable {
    public let id: String          // ESPN slug, e.g. "eng.1"
    public let name: String        // "Premier League"
    public let sport: String       // "soccer"
    /// Shown before the name in the section header, as "England - Premier League".
    public let country: String?
    /// Badge art. Baked in rather than fetched: these are stable CDN assets and
    /// the internal ids they use are not derivable from the slug.
    public let badge: URL?

    public init(id: String, name: String, sport: String,
                country: String? = nil, badge: String? = nil) {
        self.id = id; self.name = name; self.sport = sport
        self.country = country
        self.badge = badge.flatMap(URL.init(string:))
    }

    public var displayName: String {
        guard let c = country else { return name }
        return "\(c) - \(name)"
    }

    private static let soccer = "https://a.espncdn.com/i/leaguelogos/soccer/500-dark"
    private static let us = "https://a.espncdn.com/i/teamlogos/leagues/500-dark"

    public static let defaults: [League] = [
        League(id: "eng.1", name: "Premier League", sport: "soccer",
               country: "England", badge: "\(soccer)/23.png"),
        League(id: "esp.1", name: "LaLiga", sport: "soccer",
               country: "Spain", badge: "\(soccer)/15.png"),
        League(id: "ger.1", name: "Bundesliga", sport: "soccer",
               country: "Germany", badge: "\(soccer)/10.png"),
        League(id: "ita.1", name: "Serie A", sport: "soccer",
               country: "Italy", badge: "\(soccer)/12.png"),
        League(id: "fra.1", name: "Ligue 1", sport: "soccer",
               country: "France", badge: "\(soccer)/9.png"),
        League(id: "uefa.champions", name: "Champions League", sport: "soccer",
               country: "Europe", badge: "\(soccer)/2.png"),
        League(id: "usa.1", name: "MLS", sport: "soccer",
               country: "USA", badge: "\(soccer)/19.png"),
        League(id: "nfl", name: "NFL", sport: "football", badge: "\(us)/nfl.png"),
        League(id: "nba", name: "NBA", sport: "basketball", badge: "\(us)/nba.png"),
        League(id: "nhl", name: "NHL", sport: "hockey", badge: "\(us)/nhl.png"),
        League(id: "mlb", name: "MLB", sport: "baseball", badge: "\(us)/mlb.png"),
    ]

    public static func named(_ id: String) -> League? {
        defaults.first { $0.id == id }
    }
}

public struct Team: Hashable, Sendable, Codable {
    public let id: String
    /// Short form — "Bournemouth", not "AFC Bournemouth". This is what fits a
    /// menu bar dropdown row.
    public let name: String
    public let abbreviation: String
    public let crest: URL?

    public init(id: String, name: String, abbreviation: String, crest: URL? = nil) {
        self.id = id; self.name = name; self.abbreviation = abbreviation; self.crest = crest
    }
}

public enum GameState: String, Sendable, Codable {
    case scheduled, live, final, postponed, canceled, unknown
}

public struct Game: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let league: League
    public let start: Date
    public let state: GameState
    public let home: Team
    public let away: Team
    public let homeScore: Int?
    public let awayScore: Int?
    /// Provider's short status: "FT", "69'", "HT", "Postponed".
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

    /// Whether a score should be rendered at all, or the kickoff time instead.
    public var hasScore: Bool {
        homeScore != nil && awayScore != nil && state != .scheduled
    }

    /// Centre column: "0 - 1" once there is a score, otherwise nothing
    /// (the view falls back to the start time).
    public var scoreLine: String? {
        guard hasScore, let h = homeScore, let a = awayScore else { return nil }
        return "\(h) - \(a)"
    }

    /// Left-hand pill. nil for a scheduled game, which shows no badge.
    public var badgeText: String? {
        switch state {
        case .live:
            // "69'" -> "69"; keep "HT" and similar as-is.
            let d = statusDetail.trimmingCharacters(in: .whitespaces)
            let stripped = d.hasSuffix("'") ? String(d.dropLast()) : d
            return stripped.isEmpty ? "LIVE" : stripped
        case .final:     return statusDetail.isEmpty ? "FT" : statusDetail
        case .postponed: return "PPD"
        case .canceled:  return "CANC"
        case .unknown:   return "?"
        case .scheduled: return nil
        }
    }

    public var compactLine: String {
        if let s = scoreLine {
            return "\(home.abbreviation) \(s.replacingOccurrences(of: " - ", with: "–")) \(away.abbreviation)"
        }
        return "\(home.abbreviation) v \(away.abbreviation)"
    }
}
