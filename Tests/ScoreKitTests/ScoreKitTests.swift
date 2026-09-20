import XCTest
@testable import ScoreKit

private let epl = League(id: "eng.1", name: "Premier League", sport: "soccer")

private func team(_ id: String, _ abbr: String) -> Team {
    Team(id: id, name: abbr, abbreviation: abbr)
}

private func game(_ id: String, at iso: String, state: GameState = .scheduled,
                  h: Int? = nil, a: Int? = nil, detail: String = "") -> Game {
    Game(id: id, league: epl, start: ESPNProvider.date(from: iso)!, state: state,
         home: team("h\(id)", "HOM"), away: team("a\(id)", "AWY"),
         homeScore: h, awayScore: a, statusDetail: detail)
}

/// Serves canned days; can be told to start failing to simulate a dropped link.
private final class FakeProvider: ScoreProvider, @unchecked Sendable {
    var byDay: [CivilDay: [Game]] = [:]
    var failure: ProviderError?
    var calendar: Set<CivilDay>?

    func games(on day: CivilDay, league: League, zone: TimeZone) async throws -> [Game] {
        if let f = failure { throw f }
        return byDay[day] ?? []
    }
    func fixtureDays(from: CivilDay, through: CivilDay, league: League,
                     zone: TimeZone) async throws -> Set<CivilDay>? {
        if let f = failure { throw f }
        return calendar
    }
}

final class DateParsingTests: XCTestCase {
    func testParsesESPNTimestampWithoutSeconds() throws {
        let d = try XCTUnwrap(ESPNProvider.date(from: "2026-09-20T13:00Z"))
        XCTAssertEqual(d.timeIntervalSince1970, 1_789_909_200, accuracy: 1)
    }
    func testParsesTimestampWithSeconds() {
        XCTAssertNotNil(ESPNProvider.date(from: "2026-09-20T13:00:30Z"))
    }
    func testParsesNumericOffset() {
        let z = ESPNProvider.date(from: "2026-09-20T13:00Z")!
        let plusTwo = ESPNProvider.date(from: "2026-09-20T15:00+02:00")!
        XCTAssertEqual(z, plusTwo)
    }
    func testRejectsGarbage() {
        XCTAssertNil(ESPNProvider.date(from: "not a date"))
        XCTAssertNil(ESPNProvider.date(from: ""))
    }
}

final class StatusMappingTests: XCTestCase {
    func testPostponedIsNotTreatedAsFinal() {
        // ESPN reports postponed games with state "post", which a naive reader
        // shows as a 0–0 final. It must surface as postponed.
        let s = ESPNProvider.mapState(["state": "post", "name": "STATUS_POSTPONED"])
        XCTAssertEqual(s, .postponed)
    }
    func testAbandonedAndDelayedMapToPostponed() {
        XCTAssertEqual(ESPNProvider.mapState(["state": "in", "name": "STATUS_DELAYED"]), .postponed)
        XCTAssertEqual(ESPNProvider.mapState(["state": "post", "name": "STATUS_SUSPENDED"]), .postponed)
    }
    func testCanceledIsDistinct() {
        XCTAssertEqual(ESPNProvider.mapState(["state": "post", "name": "STATUS_CANCELED"]), .canceled)
    }
    func testNormalStates() {
        XCTAssertEqual(ESPNProvider.mapState(["state": "pre", "name": "STATUS_SCHEDULED"]), .scheduled)
        XCTAssertEqual(ESPNProvider.mapState(["state": "in", "name": "STATUS_IN_PROGRESS"]), .live)
        XCTAssertEqual(ESPNProvider.mapState(["state": "post", "name": "STATUS_FINAL"]), .final)
    }
    func testUnknownIsNotSilentlyScheduled() {
        XCTAssertEqual(ESPNProvider.mapState(["state": "weird", "name": "???"]), .unknown)
        XCTAssertEqual(ESPNProvider.mapState(nil), .unknown)
    }
}

final class CivilDayTests: XCTestCase {
    func testMidnightRolloverUsesLocalZone() {
        // 2026-09-20T23:30 in New York is already the 21st in London.
        let ny = TimeZone(identifier: "America/New_York")!
        let london = TimeZone(identifier: "Europe/London")!
        let instant = ESPNProvider.date(from: "2026-09-21T03:30Z")!
        XCTAssertEqual(CivilDay(instant, in: ny), CivilDay(year: 2026, month: 9, day: 20))
        XCTAssertEqual(CivilDay(instant, in: london), CivilDay(year: 2026, month: 9, day: 21))
    }

    func testAddingDaysCrossesDSTBoundary() {
        // US DST ends 2026-11-01. Adding a day must land on the 1st, not
        // 23 hours later on the 31st.
        let ny = TimeZone(identifier: "America/New_York")!
        let oct31 = CivilDay(year: 2026, month: 10, day: 31)
        XCTAssertEqual(oct31.adding(days: 1, in: ny), CivilDay(year: 2026, month: 11, day: 1))
        XCTAssertEqual(oct31.adding(days: 2, in: ny), CivilDay(year: 2026, month: 11, day: 2))
    }

    func testAddingDaysCrossesMonthAndYear() {
        let utc = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(CivilDay(year: 2026, month: 12, day: 31).adding(days: 1, in: utc),
                       CivilDay(year: 2027, month: 1, day: 1))
    }

    func testCompactFormatIsZeroPadded() {
        XCTAssertEqual(CivilDay(year: 2026, month: 1, day: 5).compact, "20260105")
    }

    func testOrdering() {
        XCTAssertLessThan(CivilDay(year: 2026, month: 9, day: 9),
                          CivilDay(year: 2026, month: 9, day: 10))
    }
}

final class FreshnessTests: XCTestCase {
    func testNeverUpdatedIsStated() {
        XCTAssertEqual(Freshness().ageDescription(), "Never updated")
    }

    func testAgeWording() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let f = Freshness(lastSuccess: t0)
        XCTAssertEqual(f.ageDescription(now: t0.addingTimeInterval(20)), "Updated 20 seconds ago")
        XCTAssertEqual(f.ageDescription(now: t0.addingTimeInterval(65)), "Updated 1 minute ago")
        XCTAssertEqual(f.ageDescription(now: t0.addingTimeInterval(600)), "Updated 10 minutes ago")
    }

    func testFailureAfterSuccessStillReportsCacheAge() {
        // The specific bug called out in the plan: old results retained after a
        // failed request must never be shown without their age.
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let f = Freshness(lastSuccess: t0, lastFailure: (at: t0.addingTimeInterval(30), reason: "no connection"))
        let w = f.warning(now: t0.addingTimeInterval(120))
        XCTAssertNotNil(w)
        XCTAssertTrue(w!.contains("no connection"))
        XCTAssertTrue(w!.contains("2 minutes ago"), "warning must carry the cache age, got: \(w!)")
    }

    func testHealthyStateHasNoWarning() {
        XCTAssertNil(Freshness(lastSuccess: Date()).warning())
    }
}

final class RefreshPolicyTests: XCTestCase {
    func testLiveGamesPollFast() {
        XCTAssertEqual(RefreshPolicy.interval(hasLive: true, nextStart: nil, failures: 0), 30)
    }
    func testIdlePollsSlowly() {
        XCTAssertEqual(RefreshPolicy.interval(hasLive: false, nextStart: nil, failures: 0), 900)
    }
    func testTightensBeforeKickoff() {
        let now = Date()
        XCTAssertEqual(RefreshPolicy.interval(hasLive: false,
                                              nextStart: now.addingTimeInterval(1800),
                                              failures: 0, now: now), 120)
    }
    func testBacksOffWhileFailingAndIsCapped() {
        let a = RefreshPolicy.interval(hasLive: true, nextStart: nil, failures: 1)
        let b = RefreshPolicy.interval(hasLive: true, nextStart: nil, failures: 3)
        XCTAssertGreaterThan(a, 30)
        XCTAssertGreaterThan(b, a)
        XCTAssertLessThanOrEqual(RefreshPolicy.interval(hasLive: true, nextStart: nil, failures: 99), 600)
    }
}

@MainActor
final class ScoreStoreTests: XCTestCase {
    private let zone = TimeZone(identifier: "America/New_York")!

    private func makeStore(_ p: FakeProvider, now: Date) -> ScoreStore {
        let store = ScoreStore(provider: p,
                               preferences: Preferences(enabledLeagueIDs: ["eng.1"]),
                               now: { now })
        store.zone = zone
        return store
    }

    func testBucketsLiveTodayAndUpcoming() async {
        let now = ESPNProvider.date(from: "2026-09-20T18:00Z")!  // 2pm NY
        let today = CivilDay(now, in: zone)
        let p = FakeProvider()
        p.byDay[today] = [
            game("live", at: "2026-09-20T17:00Z", state: .live, h: 1, a: 0, detail: "62'"),
            game("later", at: "2026-09-20T23:00Z", state: .scheduled),
        ]
        p.byDay[today.adding(days: 2, in: zone)] = [game("future", at: "2026-09-22T18:00Z")]

        let store = makeStore(p, now: now)
        await store.refresh()

        XCTAssertEqual(store.live.map(\.id), ["live"])
        XCTAssertEqual(store.today.map(\.id), ["later"])
        XCTAssertEqual(store.upcoming.count, 1)
        XCTAssertEqual(store.upcoming.first?.games.map(\.id), ["future"])
        XCTAssertFalse(store.freshness.isFailing)
    }

    func testPinnedPrefersLiveGame() async {
        let now = ESPNProvider.date(from: "2026-09-20T18:00Z")!
        let today = CivilDay(now, in: zone)
        let p = FakeProvider()
        p.byDay[today] = [
            game("later", at: "2026-09-20T23:00Z", state: .scheduled),
            game("live", at: "2026-09-20T17:00Z", state: .live, h: 2, a: 2),
        ]
        let store = makeStore(p, now: now)
        await store.refresh()
        XCTAssertEqual(store.pinned?.id, "live")
    }

    func testLostConnectionKeepsCacheAndFlagsFailure() async {
        let now = ESPNProvider.date(from: "2026-09-20T18:00Z")!
        let today = CivilDay(now, in: zone)
        let p = FakeProvider()
        p.byDay[today] = [game("g1", at: "2026-09-20T17:00Z", state: .live, h: 1, a: 0)]

        let store = makeStore(p, now: now)
        await store.refresh()
        XCTAssertEqual(store.games.count, 1)
        XCTAssertFalse(store.freshness.isFailing)

        p.failure = .transport("offline")
        await store.refresh()

        XCTAssertEqual(store.games.count, 1, "cached games must survive a failed refresh")
        XCTAssertTrue(store.freshness.isFailing, "failure must be visible")
        XCTAssertNotNil(store.freshness.warning(now: now), "stale cache must carry a warning")
    }

    func testRecoveryClearsWarning() async {
        let now = ESPNProvider.date(from: "2026-09-20T18:00Z")!
        let today = CivilDay(now, in: zone)
        let p = FakeProvider()
        p.byDay[today] = [game("g1", at: "2026-09-20T17:00Z", state: .live)]
        let store = makeStore(p, now: now)
        p.failure = .badStatus(400)
        await store.refresh()
        XCTAssertTrue(store.freshness.isFailing)

        p.failure = nil
        await store.refresh()
        XCTAssertFalse(store.freshness.isFailing)
        XCTAssertNil(store.freshness.warning(now: now))
    }

    func testPostponedGameIsNotShownAsLive() async {
        let now = ESPNProvider.date(from: "2026-09-20T18:00Z")!
        let today = CivilDay(now, in: zone)
        let p = FakeProvider()
        p.byDay[today] = [game("ppd", at: "2026-09-20T17:00Z", state: .postponed, detail: "Postponed")]
        let store = makeStore(p, now: now)
        await store.refresh()
        XCTAssertTrue(store.live.isEmpty)
        XCTAssertEqual(store.today.map(\.id), ["ppd"])
    }

    func testCalendarNeverSkipsToday() async {
        // A calendar that omits today must not stop us fetching today's live games.
        let now = ESPNProvider.date(from: "2026-09-20T18:00Z")!
        let today = CivilDay(now, in: zone)
        let p = FakeProvider()
        p.calendar = [today.adding(days: 3, in: zone)]
        p.byDay[today] = [game("live", at: "2026-09-20T17:00Z", state: .live)]
        let store = makeStore(p, now: now)
        await store.refresh()
        XCTAssertEqual(store.live.map(\.id), ["live"])
    }

    func testDeduplicatesGamesSeenTwice() async {
        let now = ESPNProvider.date(from: "2026-09-20T18:00Z")!
        let today = CivilDay(now, in: zone)
        let dup = game("same", at: "2026-09-20T17:00Z", state: .live)
        let p = FakeProvider()
        p.byDay[today] = [dup, dup]
        let store = makeStore(p, now: now)
        await store.refresh()
        XCTAssertEqual(store.games.count, 1)
    }

    func testFavoritesOnlyFiltersOtherTeams() async {
        let now = ESPNProvider.date(from: "2026-09-20T18:00Z")!
        let today = CivilDay(now, in: zone)
        let p = FakeProvider()
        let keep = game("keep", at: "2026-09-20T17:00Z", state: .live)
        p.byDay[today] = [keep, game("drop", at: "2026-09-20T17:30Z", state: .live)]
        let store = makeStore(p, now: now)
        await store.refresh()
        store.preferences.favoriteTeamIDs = [keep.home.id]
        store.preferences.favoritesOnly = true
        XCTAssertEqual(store.live.map(\.id), ["keep"])
    }

    func testNoLeaguesEnabledIsNotAnError() async {
        let now = Date()
        let p = FakeProvider()
        let store = ScoreStore(provider: p, preferences: Preferences(enabledLeagueIDs: []), now: { now })
        await store.refresh()
        XCTAssertTrue(store.games.isEmpty)
        XCTAssertFalse(store.freshness.isFailing)
    }
}

final class MenuBarTitleTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!

    /// macOS formats times with a narrow no-break space (U+202F) before AM/PM.
    /// That is correct output; normalise it so assertions stay readable.
    private func norm(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{202F}", with: " ")
         .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    func testNoGameShowsPlaceholder() {
        XCTAssertEqual(MenuBarTitle.text(for: nil), "—")
    }

    func testLiveGameShowsScoreAndClock() {
        let g = game("l", at: "2026-09-20T13:00Z", state: .live, h: 2, a: 1, detail: "67'")
        XCTAssertEqual(MenuBarTitle.text(for: g, zone: utc), "HOM 2–1 AWY 67'")
    }

    func testScheduledGameShowsMatchupAndStartTime() {
        let g = game("s", at: "2026-09-20T13:00Z", state: .scheduled)
        XCTAssertEqual(norm(MenuBarTitle.text(for: g, zone: utc)), "HOM v AWY 1:00 PM")
    }

    func testStartTimeIsRenderedInTheUsersZone() {
        let g = game("s", at: "2026-09-20T13:00Z", state: .scheduled)
        let ny = norm(MenuBarTitle.text(for: g, zone: TimeZone(identifier: "America/New_York")!))
        XCTAssertTrue(ny.contains("9:00 AM"), "expected local kickoff time, got \(ny)")
    }

    func testPostponedGameIsMarkedNotScored() {
        let g = game("p", at: "2026-09-20T13:00Z", state: .postponed, h: 0, a: 0)
        XCTAssertEqual(MenuBarTitle.text(for: g, zone: utc), "HOM 0–0 AWY PPD")
    }

    func testLiveGameWithoutDetailDoesNotGainTrailingSpace() {
        let g = game("l", at: "2026-09-20T13:00Z", state: .live, h: 0, a: 0, detail: "")
        XCTAssertEqual(MenuBarTitle.text(for: g, zone: utc), "HOM 0–0 AWY")
    }
}
