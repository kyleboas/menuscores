import Foundation

/// The menu bar string. Pure function of a game so it can be tested without
/// standing up SwiftUI: one pinned score during a game, the next matchup and
/// start time otherwise.
public enum MenuBarTitle {
    /// Shown before the first fetch lands. Not a bare dash: on a notched
    /// display an ambiguous glyph is indistinguishable from a broken item.
    public static let loading = "Scores…"
    /// Shown when the fetch succeeded but no enabled league has a game.
    public static let idle = "No games"

    /// Menu bar width is scarce on a notched Mac, so the line is kept short.
    public static let maxLength = 22

    /// - Parameter hasLoaded: whether a refresh has completed. Distinguishes
    ///   "still starting up" from "nothing on today".
    public static func text(for game: Game?, zone: TimeZone = .current,
                            hasLoaded: Bool = true) -> String {
        guard let g = game else { return hasLoaded ? idle : loading }
        return truncate(line(for: g, zone: zone))
    }

    private static func line(for g: Game, zone: TimeZone) -> String {
        switch g.state {
        case .live:
            let d = g.statusDetail.trimmingCharacters(in: .whitespaces)
            return d.isEmpty ? g.compactLine : "\(g.compactLine) \(d)"
        case .postponed: return "\(g.compactLine) PPD"
        case .canceled:  return "\(g.compactLine) CANC"
        case .final:     return "\(g.compactLine) FT"
        case .scheduled, .unknown:
            return "\(g.compactLine) \(clock(g.start, zone: zone))"
        }
    }

    /// Drops the trailing status rather than cutting mid-score, so the line
    /// degrades to "VIL 2–1 LEV" instead of "VIL 2–1 LEV 90'+…".
    static func truncate(_ s: String) -> String {
        guard s.count > maxLength else { return s }
        if let lastSpace = s.range(of: " ", options: .backwards) {
            let trimmed = String(s[s.startIndex..<lastSpace.lowerBound])
            if trimmed.count <= maxLength { return trimmed }
            return String(trimmed.prefix(maxLength - 1)) + "…"
        }
        return String(s.prefix(maxLength - 1)) + "…"
    }

    /// 24-hour, always. A fixed format needs the POSIX locale: with the
    /// user's own locale a 12-hour region can still force an AM/PM suffix.
    public static func clock(_ d: Date, zone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}
