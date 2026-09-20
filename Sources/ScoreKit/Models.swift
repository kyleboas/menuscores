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

    /// Whether a score should be rendered at all.
    ///
    /// A postponed or cancelled game still carries 0/0 from the feed, and
    /// showing that renders as a real "0 - 0" result. Only games that were
    /// actually played have a score.
    public var hasScore: Bool {
        guard homeScore != nil, awayScore != nil else { return false }
        switch state {
        case .live, .final:                        return true
        case .scheduled, .postponed, .canceled, .unknown: return false
        }
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
        case .live:      return StatusBadgeText.compact(statusDetail, sport: league.sport)
        case .final:     return league.sport == "soccer" ? "FT" : "FIN"
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


/// Squeezes a provider's live-status text into the few characters the pill can
/// show. The feed's wording differs per sport — "69'", "Top 4th", "1:07 - 2nd",
/// "Halftime" — and simply stripping spaces produced "Bot1st" and "1:07-2nd",
/// which overflowed the pill and truncated to "Bot…".
public enum StatusBadgeText {
    public static func compact(_ detail: String, sport: String) -> String {
        let d = detail.trimmingCharacters(in: .whitespaces)
        guard !d.isEmpty else { return "LIVE" }
        let lower = d.lowercased()

        // A delay can be prefixed onto any status, e.g. "Rain Delay, Top 1st".
        if lower.contains("delay") { return "DLY" }
        if lower.hasPrefix("half") { return "HT" }
        if lower.contains("shootout") { return "SO" }
        if lower == "end" { return "END" }

        switch sport {
        case "soccer":
            // "69'" -> "69"; stoppage "45'+1'" -> "45+1"; "HT" stays.
            let stripped = d.replacingOccurrences(of: "'", with: "")
                            .replacingOccurrences(of: " ", with: "")
            return String(stripped.prefix(5))

        case "baseball":
            // "Top 4th" -> "▲4", "Bot 1st" -> "▼1", "End 4th" -> "E4".
            if let inning = firstNumber(in: d) {
                if lower.hasPrefix("top") { return "▲\(inning)" }
                if lower.hasPrefix("bot") { return "▼\(inning)" }
                if lower.hasPrefix("mid") { return "M\(inning)" }
                if lower.hasPrefix("end") { return "E\(inning)" }
                return "\(inning)"
            }
            return String(d.prefix(3))

        default:
            // Clock-and-period sports: "1:07 - 2nd" -> "Q2" (football,
            // basketball) or "P2" (hockey). The clock does not fit; the period
            // is the part worth keeping.
            if lower.contains("ot") && !lower.contains("bot") { return "OT" }
            let mark = (sport == "hockey") ? "P" : "Q"
            // Take the period from the ordinal, not from the clock.
            if let period = ordinalNumber(in: d) { return "\(mark)\(period)" }
            if let n = firstNumber(in: d) { return "\(mark)\(n)" }
            return String(d.prefix(3))
        }
    }

    /// The number attached to an ordinal suffix, so "1:07 - 2nd" yields 2
    /// rather than 1.
    static func ordinalNumber(in s: String) -> Int? {
        let pattern = #"(\d{1,2})\s*(st|nd|rd|th)"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return Int(s[r])
    }

    static func firstNumber(in s: String) -> Int? {
        let digits = s.drop { !$0.isNumber }.prefix { $0.isNumber }
        return Int(digits)
    }
}
