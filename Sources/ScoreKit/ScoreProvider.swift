import Foundation

public enum ProviderError: Error, Sendable, Equatable {
    case transport(String)      // offline, DNS, timeout
    case badStatus(Int)         // e.g. the 400 the date-range syntax now returns
    case malformed(String)      // shape changed under us
}

/// Everything provider-specific lives behind this. The UI imports only ScoreKit
/// types, so replacing a failing feed never touches the interface.
public protocol ScoreProvider: Sendable {
    /// Games for one civil day, in the caller's time zone.
    func games(on day: CivilDay, league: League, zone: TimeZone) async throws -> [Game]
    /// Days within the window the provider claims have fixtures. Returning nil
    /// means "unknown, ask day by day" — MLB's calendar is not a complete index,
    /// so callers must treat this as an optimization only, never as truth.
    func fixtureDays(from: CivilDay, through: CivilDay, league: League, zone: TimeZone) async throws -> Set<CivilDay>?
}

/// A calendar date with no time zone attached. Using this instead of `Date`
/// for "which day" is what keeps midnight rollover and DST from corrupting
/// the day buckets.
public struct CivilDay: Hashable, Sendable, Comparable, Codable, CustomStringConvertible {
    public let year: Int, month: Int, day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year; self.month = month; self.day = day
    }

    public init(_ date: Date, in zone: TimeZone) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let c = cal.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    public static func today(in zone: TimeZone, now: Date = Date()) -> CivilDay {
        CivilDay(now, in: zone)
    }

    /// Start of this civil day as an absolute instant in `zone`.
    public func startOfDay(in zone: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        // `date(from:)` resolves DST gaps (e.g. a 00:00 that does not exist)
        // to the next valid instant rather than trapping.
        return cal.date(from: c) ?? Date.distantPast
    }

    public func adding(days: Int, in zone: TimeZone) -> CivilDay {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let base = startOfDay(in: zone)
        let moved = cal.date(byAdding: .day, value: days, to: base) ?? base
        return CivilDay(moved, in: zone)
    }

    /// yyyyMMdd — the only date form the ESPN scoreboard still accepts.
    public var compact: String { String(format: "%04d%02d%02d", year, month, day) }
    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    public static func < (l: CivilDay, r: CivilDay) -> Bool {
        (l.year, l.month, l.day) < (r.year, r.month, r.day)
    }
}
