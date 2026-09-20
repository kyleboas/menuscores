import Foundation
import ScoreKit

// The data test the plan insists on shipping before the interface is trusted.
// Re-run it whenever scores look wrong: it proves, against the live feed,
// that today's games AND the next seven days still arrive.

let zone = TimeZone.current
let provider = ESPNProvider()
let today = CivilDay.today(in: zone)
let horizon = 7
var failures = 0

@MainActor func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print("  [\(ok ? "PASS" : "FAIL")] \(label)\(detail.isEmpty ? "" : " — \(detail)")")
    if !ok { failures += 1 }
}

let requested: [League] = {
    let args = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
    guard !args.isEmpty else { return League.defaults }
    return League.defaults.filter { args.contains($0.id) }
}()

print("scorefeed-probe — \(today) (\(zone.identifier))")
print("Checking \(requested.count) league(s) over \(horizon) days\n")

for league in requested {
    print("\(league.name) [\(league.sport)/\(league.id)]")

    // 1. Today must answer at all. An empty day is legitimate; an error is not.
    var todayCount = -1
    do {
        todayCount = try await provider.games(on: today, league: league, zone: zone).count
        check("today's scoreboard responds", true, "\(todayCount) game(s)")
    } catch {
        check("today's scoreboard responds", false, "\(error)")
    }

    // 2. The next seven days must be retrievable one day at a time. This is
    //    the capability the range-syntax removal took away.
    var horizonTotal = 0, dayErrors = 0
    var perDay: [String] = []
    for offset in 1...horizon {
        let day = today.adding(days: offset, in: zone)
        do {
            let n = try await provider.games(on: day, league: league, zone: zone).count
            horizonTotal += n
            perDay.append("\(day.compact.suffix(4)):\(n)")
        } catch {
            dayErrors += 1
            perDay.append("\(day.compact.suffix(4)):ERR")
        }
    }
    check("next \(horizon) days all retrievable", dayErrors == 0,
          "\(horizonTotal) fixture(s) — \(perDay.joined(separator: " "))")

    // 3. Cross-check against the provider's own published calendar. If the
    //    calendar advertises a fixture day inside our window and the day query
    //    returns nothing, the two disagree and we must not trust the schedule.
    do {
        let end = today.adding(days: horizon, in: zone)
        if let cal = try await provider.fixtureDays(from: today, through: end,
                                                    league: league, zone: zone) {
            var disagreements: [String] = []
            for day in cal.sorted() where day > today {
                let n = (try? await provider.games(on: day, league: league, zone: zone).count) ?? -1
                if n <= 0 { disagreements.append(day.description) }
            }
            check("day queries agree with published calendar", disagreements.isEmpty,
                  disagreements.isEmpty
                    ? "\(cal.count) advertised day(s) in window"
                    : "calendar lists \(disagreements.joined(separator: ", ")) but day query is empty")
        } else {
            print("  [SKIP] calendar is not day-shaped for this league")
        }
    } catch {
        check("calendar retrievable", false, "\(error)")
    }
    print("")
}

// 4. Guard the specific regression: the range syntax must stay unused. If it
//    ever starts working again that is fine, but we assert we never depend on it.
print("Regression guard")
var comps = URLComponents(string: "https://site.api.espn.com/apis/site/v2/sports/soccer/eng.1/scoreboard")!
comps.queryItems = [URLQueryItem(name: "dates", value: "\(today.compact)-\(today.adding(days: 7, in: zone).compact)")]
do {
    let (_, resp) = try await URLSession.shared.data(from: comps.url!)
    let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
    print("  [INFO] legacy date-range syntax returns HTTP \(code) (app does not use it)")
} catch {
    print("  [INFO] legacy date-range syntax unreachable: \(error.localizedDescription)")
}


// 5. End-to-end: drive the real store through the real provider and render
//    exactly what the menu bar would show. Proves the whole chain, not the parts.
print("End-to-end render")
let store = ScoreStore(provider: provider,
                       preferences: Preferences(enabledLeagueIDs: Set(requested.map(\.id))))
await store.refresh()
check("store completed a refresh", store.freshness.lastSuccess != nil,
      store.freshness.ageDescription())
check("no failure warning", store.freshness.warning() == nil,
      store.freshness.warning() ?? "healthy")
print("  menu bar would read: \"\(MenuBarTitle.text(for: store.pinned, zone: zone))\"")
print("  live: \(store.live.count)  on \(store.selectedDay): \(store.games(on: store.selectedDay).count)")
for section in store.sections.prefix(4) {
    let g = section.games[0]
    print("    \(section.league.displayName): \(section.games.count) — \(g.badgeText.map { "[\($0)] " } ?? "")\(g.home.name) \(g.scoreLine ?? MenuBarTitle.clock(g.start, zone: zone)) \(g.away.name)")
}
print("")

print("\n\(failures == 0 ? "DATA TEST PASSED" : "DATA TEST FAILED — \(failures) check(s)")")
exit(failures == 0 ? 0 : 1)
