import Foundation

/// The menu bar string. Pure function of a game so it can be tested without
/// standing up SwiftUI: one pinned score during a game, the next matchup and
/// start time otherwise.
public enum MenuBarTitle {
    public static func text(for game: Game?, zone: TimeZone = .current) -> String {
        guard let g = game else { return "—" }
        switch g.state {
        case .live:
            let d = g.statusDetail.trimmingCharacters(in: .whitespaces)
            return d.isEmpty ? g.compactLine : "\(g.compactLine) \(d)"
        case .postponed:
            return "\(g.compactLine) PPD"
        case .canceled:
            return "\(g.compactLine) CANC"
        case .final:
            return "\(g.compactLine) FT"
        case .scheduled, .unknown:
            return "\(g.compactLine) \(clock(g.start, zone: zone))"
        }
    }

    public static func clock(_ d: Date, zone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.timeZone = zone
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: d)
    }
}
