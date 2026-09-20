import Foundation

/// Adapter for ESPN's public scoreboard endpoint.
///
/// Verified behaviour (probe, 2026-09-20):
///   * `?dates=yyyyMMdd`       -> 200, works for past AND future days.
///   * `?dates=yyyyMM`         -> 200, whole month.
///   * `?dates=yyyyMMdd-yyyyMMdd` -> 400. The multi-day range syntax is GONE.
///     This is the regression that cost the original app its schedule view;
///     we never emit it.
public struct ESPNProvider: ScoreProvider {
    private let session: URLSession
    private let base = "https://site.api.espn.com/apis/site/v2/sports"

    public init(session: URLSession = .shared) { self.session = session }

    private func path(for league: League) -> String {
        "\(base)/\(league.sport)/\(league.id)/scoreboard"
    }

    private func fetch(_ url: URL) async throws -> [String: Any] {
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw ProviderError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.malformed("no HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ProviderError.badStatus(http.statusCode)
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.malformed("not a JSON object")
        }
        return obj
    }

    public func games(on day: CivilDay, league: League, zone: TimeZone) async throws -> [Game] {
        guard let url = URL(string: "\(path(for: league))?dates=\(day.compact)") else {
            throw ProviderError.malformed("bad URL")
        }
        let json = try await fetch(url)
        let events = json["events"] as? [[String: Any]] ?? []
        // ESPN keys the query by US-Eastern-ish day, so a yyyyMMdd query can
        // return events that fall on the neighbouring civil day in the user's
        // zone. Re-bucket by the user's own zone and drop what is not ours.
        return events.compactMap { parse($0, league: league) }
                     .filter { CivilDay($0.start, in: zone) == day }
    }

    public func fixtureDays(from: CivilDay, through: CivilDay, league: League,
                            zone: TimeZone) async throws -> Set<CivilDay>? {
        guard let url = URL(string: path(for: league)) else { return nil }
        let json = try await fetch(url)
        guard let leagues = json["leagues"] as? [[String: Any]],
              let first = leagues.first,
              (first["calendarType"] as? String) == "day",
              let cal = first["calendar"] as? [String] else {
            // calendarType "list" (NFL/UCL) is week-shaped, not day-shaped;
            // report unknown and let the caller fall back to per-day fetches.
            return nil
        }
        let days = cal.compactMap { Self.date(from: $0) }
                      .map { CivilDay($0, in: zone) }
                      .filter { $0 >= from && $0 <= through }
        return Set(days)
    }

    // MARK: - Parsing

    /// ESPN emits "2026-09-20T13:00Z" (no seconds) and occasionally
    /// "...T13:00:00Z". Parsed by hand: ISO8601DateFormatter is not Sendable,
    /// and a shared instance would be a data race under strict concurrency.
    static func date(from s: String) -> Date? {
        let pattern = #"^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?(Z|[+-]\d{2}:?\d{2})$"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s))
        else { return nil }

        func field(_ i: Int) -> Int? {
            guard let r = Range(m.range(at: i), in: s) else { return nil }
            return Int(s[r])
        }
        guard let y = field(1), let mo = field(2), let d = field(3),
              let h = field(4), let mi = field(5) else { return nil }
        let sec = field(6) ?? 0

        var offset = 0
        if let r = Range(m.range(at: 7), in: s) {
            let tz = String(s[r])
            if tz != "Z" {
                let sign = tz.hasPrefix("-") ? -1 : 1
                let digits = tz.dropFirst().replacingOccurrences(of: ":", with: "")
                if digits.count == 4,
                   let hh = Int(digits.prefix(2)), let mm = Int(digits.suffix(2)) {
                    offset = sign * (hh * 3600 + mm * 60)
                }
            }
        }

        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d
        c.hour = h; c.minute = mi; c.second = sec
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal.date(from: c)?.addingTimeInterval(-Double(offset))
    }

    private func parse(_ event: [String: Any], league: League) -> Game? {
        guard let id = event["id"] as? String,
              let dateStr = event["date"] as? String,
              let start = Self.date(from: dateStr),
              let comps = event["competitions"] as? [[String: Any]],
              let comp = comps.first,
              let competitors = comp["competitors"] as? [[String: Any]],
              competitors.count >= 2 else { return nil }

        func side(_ which: String) -> ([String: Any])? {
            competitors.first { ($0["homeAway"] as? String) == which }
        }
        guard let h = side("home"), let a = side("away"),
              let homeTeam = team(from: h), let awayTeam = team(from: a) else { return nil }

        let statusObj = (comp["status"] ?? event["status"]) as? [String: Any]
        let type = statusObj?["type"] as? [String: Any]
        let state = Self.mapState(type)
        let detail = (type?["shortDetail"] as? String)
            ?? (type?["detail"] as? String)
            ?? (type?["description"] as? String) ?? ""

        return Game(id: id, league: league, start: start, state: state,
                    home: homeTeam, away: awayTeam,
                    homeScore: Self.score(h), awayScore: Self.score(a),
                    statusDetail: detail)
    }

    private func team(from c: [String: Any]) -> Team? {
        guard let t = c["team"] as? [String: Any] else { return nil }
        let id = (t["id"] as? String) ?? ""
        let name = (t["displayName"] as? String) ?? (t["name"] as? String) ?? "—"
        let abbr = (t["abbreviation"] as? String)
            ?? (t["shortDisplayName"] as? String)
            ?? String(name.prefix(3)).uppercased()
        return Team(id: id, name: name, abbreviation: abbr)
    }

    private static func score(_ c: [String: Any]) -> Int? {
        if let s = c["score"] as? String { return Int(s) }
        if let n = c["score"] as? Int { return n }
        if let d = c["score"] as? Double { return Int(d) }
        return nil
    }

    /// ESPN's `state` is pre/in/post; `post` covers finals AND abandonments,
    /// so the specific status name has to be consulted before trusting it.
    static func mapState(_ type: [String: Any]?) -> GameState {
        let name = ((type?["name"] as? String) ?? "").uppercased()
        if name.contains("POSTPONED") { return .postponed }
        if name.contains("CANCEL") { return .canceled }
        if name.contains("SUSPEND") || name.contains("DELAY") { return .postponed }
        switch (type?["state"] as? String)?.lowercased() {
        case "pre":  return .scheduled
        case "in":   return .live
        case "post": return .final
        default:     return .unknown
        }
    }
}
