import Foundation

public struct League: Hashable, Sendable, Codable, Identifiable {
    public let id: String          // ESPN slug, e.g. "eng.1"
    public let name: String        // "Premier League"
    public let sport: String       // "soccer"
    /// Shown before the name in the section header, as "England - Premier League".
    public let country: String?
    /// Badge art, baked in rather than fetched: these are stable CDN assets
    /// and the internal ids they use are not derivable from the slug.
    ///
    /// Two variants, because ESPN's "-dark" asset is a white knockout logo.
    /// Using it on a light background made the Premier League badge invisible.
    public let badgeLight: URL?   // full colour, for light backgrounds
    public let badgeDark: URL?    // white knockout, for dark backgrounds

    public init(id: String, name: String, sport: String,
                country: String? = nil, badgeLight: String? = nil,
                badgeDark: String? = nil) {
        self.id = id; self.name = name; self.sport = sport
        self.country = country
        self.badgeLight = badgeLight.flatMap(URL.init(string:))
        self.badgeDark = badgeDark.flatMap(URL.init(string:))
    }

    public func badge(dark: Bool) -> URL? { dark ? badgeDark : badgeLight }

    public var displayName: String {
        guard let c = country else { return name }
        return "\(c) - \(name)"
    }

    private static func soccer(_ id: String) -> (String, String) {
        ("https://a.espncdn.com/i/leaguelogos/soccer/500/\(id).png",
         "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/\(id).png")
    }
    private static func us(_ slug: String) -> (String, String) {
        ("https://a.espncdn.com/i/teamlogos/leagues/500/\(slug).png",
         "https://a.espncdn.com/i/teamlogos/leagues/500-dark/\(slug).png")
    }

    public static let defaults: [League] = [
        League(id: "eng.1", name: "Premier League", sport: "soccer",
               country: "England", badgeLight: soccer("23").0, badgeDark: soccer("23").1),
        League(id: "esp.1", name: "LaLiga", sport: "soccer",
               country: "Spain", badgeLight: soccer("15").0, badgeDark: soccer("15").1),
        League(id: "ger.1", name: "Bundesliga", sport: "soccer",
               country: "Germany", badgeLight: soccer("10").0, badgeDark: soccer("10").1),
        League(id: "ita.1", name: "Serie A", sport: "soccer",
               country: "Italy", badgeLight: soccer("12").0, badgeDark: soccer("12").1),
        League(id: "fra.1", name: "Ligue 1", sport: "soccer",
               country: "France", badgeLight: soccer("9").0, badgeDark: soccer("9").1),
        League(id: "uefa.champions", name: "Champions League", sport: "soccer",
               country: "Europe", badgeLight: soccer("2").0, badgeDark: soccer("2").1),
        League(id: "usa.1", name: "MLS", sport: "soccer",
               country: "USA", badgeLight: soccer("19").0, badgeDark: soccer("19").1),
        League(id: "nfl", name: "NFL", sport: "football",
               badgeLight: us("nfl").0, badgeDark: us("nfl").1),
        League(id: "nba", name: "NBA", sport: "basketball",
               badgeLight: us("nba").0, badgeDark: us("nba").1),
        League(id: "nhl", name: "NHL", sport: "hockey",
               badgeLight: us("nhl").0, badgeDark: us("nhl").1),
        League(id: "mlb", name: "MLB", sport: "baseball",
               badgeLight: us("mlb").0, badgeDark: us("mlb").1),
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
            // "69'" -> "69", and stoppage time "45'+1'" -> "45+1". Stripping
            // only the trailing mark left an apostrophe stranded mid-badge.
            let d = statusDetail
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "'", with: "")
                .replacingOccurrences(of: " ", with: "")
            return d.isEmpty ? "LIVE" : d
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
