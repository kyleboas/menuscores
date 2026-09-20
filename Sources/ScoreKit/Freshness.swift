import Foundation

/// What the UI needs to never show a stale score as if it were current.
public struct Freshness: Sendable, Equatable {
    /// When the newest *successful* refresh completed. nil = never succeeded.
    public var lastSuccess: Date?
    /// Set when the most recent attempt failed; cleared on success.
    public var lastFailure: (at: Date, reason: String)?

    public init(lastSuccess: Date? = nil, lastFailure: (at: Date, reason: String)? = nil) {
        self.lastSuccess = lastSuccess
        self.lastFailure = lastFailure
    }

    public static func == (l: Freshness, r: Freshness) -> Bool {
        l.lastSuccess == r.lastSuccess
            && l.lastFailure?.at == r.lastFailure?.at
            && l.lastFailure?.reason == r.lastFailure?.reason
    }

    public var isFailing: Bool { lastFailure != nil }

    public func age(now: Date = Date()) -> TimeInterval? {
        lastSuccess.map { now.timeIntervalSince($0) }
    }

    /// "Updated 20 seconds ago" — always rendered, never omitted, so a cached
    /// score can never be mistaken for a live one.
    public func ageDescription(now: Date = Date()) -> String {
        guard let age = age(now: now) else { return "Never updated" }
        let s = Int(max(0, age.rounded()))
        switch s {
        case 0..<5:      return "Updated just now"
        case 5..<60:     return "Updated \(s) seconds ago"
        case 60..<120:   return "Updated 1 minute ago"
        case 120..<3600: return "Updated \(s / 60) minutes ago"
        case 3600..<7200: return "Updated 1 hour ago"
        default:         return "Updated \(s / 3600) hours ago"
        }
    }

    /// The warning line shown when refreshes are failing. nil when healthy.
    public func warning(now: Date = Date()) -> String? {
        guard let f = lastFailure else { return nil }
        if lastSuccess == nil { return "Can't reach scores — \(f.reason)" }
        return "Not updating (\(f.reason)) — showing \(ageDescription(now: now).lowercased())"
    }
}

/// Poll fast while something is live, slowly otherwise, and back off when the
/// provider is failing so we do not hammer it.
public enum RefreshPolicy {
    public static let live: TimeInterval = 30
    public static let idle: TimeInterval = 900      // 15 min
    public static let soon: TimeInterval = 120      // a game starts within the hour

    public static func interval(hasLive: Bool, nextStart: Date?, failures: Int,
                                now: Date = Date()) -> TimeInterval {
        var base: TimeInterval = idle
        if hasLive {
            base = live
        } else if let n = nextStart, n.timeIntervalSince(now) < 3600, n > now {
            base = soon
        }
        guard failures > 0 else { return base }
        // Exponential backoff, capped, so a dead feed settles at 10 min.
        let backed = base * pow(2, Double(min(failures, 5)))
        return min(backed, 600)
    }
}
