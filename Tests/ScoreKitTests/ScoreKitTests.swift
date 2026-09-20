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
    var teamsByLeague: [String: [Team]] = [:]
    func teams(in league: League) async throws -> [Team] {
        if let f = failure { throw f }
        return teamsByLeague[league.id] ?? []
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
        ScoreStore(provider: p,
                   preferences: Preferences(enabledLeagueIDs: ["eng.1"]),
                   zone: zone,
                   now: { now })
    }

    func testDayStripSpansPastAndFuture() {
        let now = ESPNProvider.date(from: "2026-09-20T18:00Z")!
        let store = makeStore(FakeProvider(), now: now)
        let strip = store.dayStrip
        XCTAssertEqual(strip.count, store.pastDays + store.futureDays + 1)
        XCTAssertTrue(strip.contains(store.today))
        XCTAssertEqual(store.label(for: strip.first!), "Fri 18 Sep")
    }

    func testRelativeDayLabels() {
        let now = ESPNProvider.date(from: "2026-09-20T18:00Z")!
        let store = makeStore(FakeProvider(), now: now)
        let t = store.today
        XCTAssertEqual(store.label(for: t), "Today")
        XCTAssertEqual(store.label(for: t.adding(days: -1, in: zone)), "Yesterday")
        XCTAssertEqual(store.label(for: t.adding(days: 1, in: zone)), "Tomorrow")
        XCTAssertEqual(store.label(for: t.adding(days: 2, in: zone)), "Tue 22 Sep")
    }

    func testSelectedDayDrivesSections() async {
        let now = ESPNProvider.date(from: "2026-09-20T18:00Z")!
        let p = FakeProvider()
        let store = makeStore(p, now: now)
        let t = store.today
        let tomorrow = t.adding(days: 1, in: zone)
        p.byDay[t] = [game("today", at: "2026-09-20T23:00Z", state: .scheduled)]
        p.byDay[tomorrow] = [game("tmrw", at: "2026-09-21T23:00Z", state: .scheduled)]

        await store.refresh()
        XCTAssertEqual(store.sections.flatMap { $0.games }.map(\.id), ["today"])

        store.selectedDay = tomorrow
        await store.load(days: [tomorrow])
        XCTAssertEqual(store.sections.flatMap { $0.games }.map(\.id), ["tmrw"])
    }

    func testYesterdayIsSelectableAndFetchable() async {
        let now = ESPNProvider.date(from: "2026-09-20T18:00Z")!
        let p = FakeProvider()
        let store = makeStore(p, now: now)
        let yesterday = store.today.adding(days: -1, in: zone)
        p.byDay[yesterday] = [game("y", at: "2026-09-19T23:00Z", state: .final, h: 2, a: 0)]

        store.selectedDay = yesterday
        await store.load(days: [yesterday])
        XCTAssertEqual(store.sections.flatMap { $0.games }.map(\.id), ["y"])
    }

    func testDefaultSelectionIsToday() {
        let now = ESPNProvider.date(from: "2026-09-20T18:00Z")!
        let store = makeStore(FakeProvider(), now: now)
        XCTAssertEqual(store.selectedDay, store.today)
    }

    func testSectionsShowSelectedDay() async {
        let now = ESPNProvider.date(from: "2026-09-20T18:00Z")!
        let p = FakeProvider()
        let store = makeStore(p, now: now)
        let t = store.today
        p.byDay[t] = [game("today", at: "2026-09-20T23:00Z", state: .scheduled)]
        p.byDay[t.adding(days: 1, in: zone)] = [game("tmrw", at: "2026-09-21T23:00Z", state: .scheduled)]

        await store.refresh()
        XCTAssertEqual(store.sections.flatMap { $0.games }.map(\.id), ["today"],
                       "the dropdown opens on today")
    }

    func testTomorrowIsFetchedButNotListedUntilSelected() async {
        // Tomorrow is cached so the menu bar can name the next fixture, but it
        // must not appear under today's sections until the tab is selected.
        let now = ESPNProvider.date(from: "2026-09-20T18:00Z")!
        let p = FakeProvider()
        let store = makeStore(p, now: now)
        let tomorrow = store.today.adding(days: 1, in: zone)
        p.byDay[tomorrow] = [game("tmrw", at: "2026-09-21T15:00Z", state: .scheduled)]

        await store.refresh()
        XCTAssertTrue(store.sections.isEmpty)
        XCTAssertEqual(store.games(on: tomorrow).map(\.id), ["tmrw"])
        XCTAssertEqual(store.pinned?.id, "tmrw")
    }

    func testSectionsGroupByLeagueInPreferenceOrder() async {
        let now = ESPNProvider.date(from: "2026-09-20T18:00Z")!
        let p = FakeProvider()
        let store = ScoreStore(provider: p,
                               preferences: Preferences(enabledLeagueIDs: ["eng.1", "esp.1"]),
                               zone: zone, now: { now })
        let t = store.today
        let esp = League.named("esp.1")!
        let spanish = Game(id: "es", league: esp,
                           start: ESPNProvider.date(from: "2026-09-20T19:00Z")!,
                           state: .live, home: team("h1", "GET"), away: team("a1", "MAL"),
                           homeScore: 1, awayScore: 0, statusDetail: "68'")
        p.byDay[t] = [spanish, game("en", at: "2026-09-20T20:00Z", state: .scheduled)]

        await store.refresh()
        XCTAssertEqual(store.sections.map { $0.league.id }, ["eng.1", "esp.1"],
                       "sections must follow the league list, not arrival order")
    }

    func testLiveGamesSortAboveScheduledWithinASection() async {
        let now = ESPNProvider.date(from: "2026-09-20T18:00Z")!
        let p = FakeProvider()
        let store = makeStore(p, now: now)
        p.byDay[store.today] = [
            game("early", at: "2026-09-20T12:00Z", state: .scheduled),
            game("live", at: "2026-09-20T17:00Z", state: .live, h: 1, a: 1, detail: "70'"),
        ]
        await store.refresh()
        XCTAssertEqual(store.sections.first?.games.map(\.id), ["live", "early"])
    }

    func testPinnedPrefersLiveGame() async {
        let now = ESPNProvider.date(from: "2026-09-20T18:00Z")!
        let p = FakeProvider()
        let store = makeStore(p, now: now)
        p.byDay[store.today] = [
            game("later", at: "2026-09-20T23:00Z", state: .scheduled),
            game("live", at: "2026-09-20T17:00Z", state: .live, h: 2, a: 2),
        ]
        await store.refresh()
        XCTAssertEqual(store.pinned?.id, "live")
    }

    func testPinnedFallsBackToTomorrowWhenTodayIsDone() async {
        let now = ESPNProvider.date(from: "2026-09-20T18:00Z")!
        let p = FakeProvider()
        let store = makeStore(p, now: now)
        p.byDay[store.today] = [game("done", at: "2026-09-20T12:00Z", state: .final, h: 1, a: 0)]
        p.byDay[store.today.adding(days: 1, in: zone)] =
            [game("next", at: "2026-09-21T15:00Z", state: .scheduled)]
        await store.refresh()
        XCTAssertEqual(store.pinned?.id, "next")
    }

    func testLostConnectionKeepsCacheAndFlagsFailure() async {
        let now = ESPNProvider.date(from: "2026-09-20T18:00Z")!
        let p = FakeProvider()
        let store = makeStore(p, now: now)
        p.byDay[store.today] = [game("g1", at: "2026-09-20T17:00Z", state: .live, h: 1, a: 0)]

        await store.refresh()
        XCTAssertEqual(store.games(on: store.today).count, 1)
        XCTAssertFalse(store.freshness.isFailing)

        p.failure = .transport("offline")
        await store.refresh()

        XCTAssertEqual(store.games(on: store.today).count, 1,
                       "cached games must survive a failed refresh")
        XCTAssertTrue(store.freshness.isFailing, "failure must be visible")
        XCTAssertNotNil(store.freshness.warning(now: now), "stale cache must carry a warning")
    }

    func testRecoveryClearsWarning() async {
        let now = ESPNProvider.date(from: "2026-09-20T18:00Z")!
        let p = FakeProvider()
        let store = makeStore(p, now: now)
        p.byDay[store.today] = [game("g1", at: "2026-09-20T17:00Z", state: .live)]
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
        let p = FakeProvider()
        let store = makeStore(p, now: now)
        p.byDay[store.today] = [game("ppd", at: "2026-09-20T17:00Z",
                                     state: .postponed, detail: "Postponed")]
        await store.refresh()
        XCTAssertTrue(store.live.isEmpty)
        XCTAssertEqual(store.sections.first?.games.map(\.id), ["ppd"])
    }

    func testDeduplicatesGamesSeenTwice() async {
        let now = ESPNProvider.date(from: "2026-09-20T18:00Z")!
        let dup = game("same", at: "2026-09-20T17:00Z", state: .live)
        let p = FakeProvider()
        let store = makeStore(p, now: now)
        p.byDay[store.today] = [dup, dup]
        await store.refresh()
        XCTAssertEqual(store.games(on: store.today).count, 1)
    }

    func testFavoritesOnlyFiltersOtherTeams() async {
        let now = ESPNProvider.date(from: "2026-09-20T18:00Z")!
        let p = FakeProvider()
        let store = makeStore(p, now: now)
        let keep = game("keep", at: "2026-09-20T17:00Z", state: .live)
        p.byDay[store.today] = [keep, game("drop", at: "2026-09-20T17:30Z", state: .live)]
        await store.refresh()
        store.preferences.favoriteTeamIDs = [keep.home.id]
        store.preferences.favoritesOnly = true
        XCTAssertEqual(store.live.map(\.id), ["keep"])
        XCTAssertEqual(store.games(on: store.today).count, 1,
                       "a favourites change must filter in place, not clear the cache")
    }

    func testNoLeaguesEnabledIsNotAnError() async {
        let now = Date()
        let store = ScoreStore(provider: FakeProvider(),
                               preferences: Preferences(enabledLeagueIDs: []),
                               zone: zone, now: { now })
        await store.refresh()
        XCTAssertTrue(store.sections.isEmpty)
        XCTAssertFalse(store.freshness.isFailing)
    }

    func testCollapseIsPerLeagueAndPersistsInPreferences() {
        var prefs = Preferences(enabledLeagueIDs: ["eng.1", "esp.1"])
        let eng = League.named("eng.1")!, esp = League.named("esp.1")!
        XCTAssertFalse(prefs.isCollapsed(eng))
        prefs.toggleCollapsed(eng)
        XCTAssertTrue(prefs.isCollapsed(eng))
        XCTAssertFalse(prefs.isCollapsed(esp), "collapsing one league must not affect another")
        prefs.toggleCollapsed(eng)
        XCTAssertFalse(prefs.isCollapsed(eng))
    }

    func testPreferencesDecodeWithoutCollapsedKey() throws {
        // Older saved prefs predate collapsedLeagueIDs and must still load.
        let json = #"{"enabledLeagueIDs":["eng.1"],"favoriteTeamIDs":[],"favoritesOnly":false}"#
        let p = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
        XCTAssertEqual(p.enabledLeagueIDs, ["eng.1"])
        XCTAssertTrue(p.collapsedLeagueIDs.isEmpty)
    }
}

final class RowPresentationTests: XCTestCase {
    func testLiveBadgeStripsTheApostrophe() {
        let g = game("l", at: "2026-09-20T13:00Z", state: .live, h: 0, a: 1, detail: "68'")
        XCTAssertEqual(g.badgeText, "68")
    }

    func testStoppageTimeBadgeIsCompact() {
        // The feed sends "45'+1'". Stripping only the trailing mark left
        // "45'+1", which stranded an apostrophe mid-badge and overflowed it.
        let g = game("l", at: "2026-09-20T13:00Z", state: .live, h: 2, a: 0, detail: "45'+1'")
        XCTAssertEqual(g.badgeText, "45+1")
        XCTAssertLessThanOrEqual(g.badgeText!.count, 4,
                                 "badge must fit its column at the worst case")
    }

    func testSecondHalfStoppageBadge() {
        let g = game("l", at: "2026-09-20T13:00Z", state: .live, h: 2, a: 0, detail: "90'+5'")
        XCTAssertEqual(g.badgeText, "90+5")
    }

    func testHalfTimeBadgeIsKeptAsIs() {
        let g = game("l", at: "2026-09-20T13:00Z", state: .live, h: 0, a: 0, detail: "HT")
        XCTAssertEqual(g.badgeText, "HT")
    }

    func testFinishedGameShowsFT() {
        let g = game("f", at: "2026-09-20T13:00Z", state: .final, h: 0, a: 1, detail: "FT")
        XCTAssertEqual(g.badgeText, "FT")
        XCTAssertEqual(g.scoreLine, "0 - 1")
    }

    func testScheduledGameHasNoBadgeAndNoScore() {
        let g = game("s", at: "2026-09-20T13:00Z", state: .scheduled)
        XCTAssertNil(g.badgeText, "a fixture that has not kicked off shows no pill")
        XCTAssertNil(g.scoreLine, "and shows its start time instead of 0 - 0")
    }

    func testScheduledGameWithStrayScoresStillShowsNoScore() {
        // ESPN sends 0/0 for some unplayed fixtures; that must not render as 0 - 0.
        let g = game("s", at: "2026-09-20T13:00Z", state: .scheduled, h: 0, a: 0)
        XCTAssertNil(g.scoreLine)
    }

    func testPostponedBadge() {
        let g = game("p", at: "2026-09-20T13:00Z", state: .postponed, detail: "Postponed")
        XCTAssertEqual(g.badgeText, "PPD")
    }
}

final class LeagueDisplayTests: XCTestCase {
    func testSoccerLeaguesShowCountryPrefix() {
        XCTAssertEqual(League.named("eng.1")?.displayName, "England - Premier League")
        XCTAssertEqual(League.named("esp.1")?.displayName, "Spain - LaLiga")
        XCTAssertEqual(League.named("fra.1")?.displayName, "France - Ligue 1")
    }

    func testUSLeaguesHaveNoCountryPrefix() {
        XCTAssertEqual(League.named("nfl")?.displayName, "NFL")
    }

    func testEveryLeagueHasBothBadgeVariants() {
        for l in League.defaults {
            XCTAssertNotNil(l.badge(dark: true), "\(l.id) is missing its dark badge")
            XCTAssertNotNil(l.badge(dark: false), "\(l.id) is missing its light badge")
        }
    }

    func testBadgeVariantsDiffer() {
        // The dark asset is a white knockout; reusing it on a light background
        // made the Premier League badge invisible.
        for l in League.defaults {
            XCTAssertNotEqual(l.badge(dark: true), l.badge(dark: false), "\(l.id)")
        }
        XCTAssertEqual(League.named("eng.1")?.badge(dark: false)?.absoluteString,
                       "https://a.espncdn.com/i/leaguelogos/soccer/500/23.png")
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

    func testNoGameShowsAReadableFallbackNotAGlyph() {
        // Covered in depth by MenuBarFallbackTests; pinned here so the menu bar
        // can never regress to a bare dash.
        XCTAssertEqual(MenuBarTitle.text(for: nil), MenuBarTitle.idle)
        XCTAssertGreaterThan(MenuBarTitle.text(for: nil).count, 1)
    }

    func testLiveGameShowsScoreAndClock() {
        let g = game("l", at: "2026-09-20T13:00Z", state: .live, h: 2, a: 1, detail: "67'")
        XCTAssertEqual(MenuBarTitle.text(for: g, zone: utc), "HOM 2–1 AWY 67'")
    }

    func testScheduledGameShowsMatchupAndStartTime() {
        let g = game("s", at: "2026-09-20T13:00Z", state: .scheduled)
        XCTAssertEqual(norm(MenuBarTitle.text(for: g, zone: utc)), "HOM v AWY 13:00")
    }

    func testStartTimeIsRenderedInTheUsersZone() {
        let g = game("s", at: "2026-09-20T13:00Z", state: .scheduled)
        let ny = norm(MenuBarTitle.text(for: g, zone: TimeZone(identifier: "America/New_York")!))
        XCTAssertTrue(ny.contains("09:00"), "expected local kickoff time, got \(ny)")
    }

    func testClockIs24HourWithNoMeridiem() {
        let utc = TimeZone(secondsFromGMT: 0)!
        let afternoon = ESPNProvider.date(from: "2026-09-20T15:00Z")!
        let morning = ESPNProvider.date(from: "2026-09-20T09:05Z")!
        let midnight = ESPNProvider.date(from: "2026-09-20T00:30Z")!
        XCTAssertEqual(MenuBarTitle.clock(afternoon, zone: utc), "15:00")
        XCTAssertEqual(MenuBarTitle.clock(morning, zone: utc), "09:05",
                       "morning times stay zero-padded")
        XCTAssertEqual(MenuBarTitle.clock(midnight, zone: utc), "00:30",
                       "midnight is 00:xx, not 12:xx")
        for t in [afternoon, morning, midnight] {
            let s = MenuBarTitle.clock(t, zone: utc).uppercased()
            XCTAssertFalse(s.contains("AM") || s.contains("PM"), "got \(s)")
        }
    }

    func testClockIgnoresA12HourLocale() {
        // en_US is a 12-hour region; the format must not pick that up.
        let utc = TimeZone(secondsFromGMT: 0)!
        let d = ESPNProvider.date(from: "2026-09-20T20:45Z")!
        XCTAssertEqual(MenuBarTitle.clock(d, zone: utc), "20:45")
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

final class MenuBarFallbackTests: XCTestCase {
    func testBeforeFirstFetchSaysLoadingNotABareDash() {
        // A lone glyph in the menu bar reads as a broken item.
        XCTAssertEqual(MenuBarTitle.text(for: nil, hasLoaded: false), "Scores…")
    }

    func testAfterFetchWithNoGamesSaysSo() {
        XCTAssertEqual(MenuBarTitle.text(for: nil, hasLoaded: true), "No games")
    }

    func testLongLineIsTruncatedAtAWordBoundary() {
        let t = MenuBarTitle.truncate("VILLARREAL 2–1 LEVANTE 90'+5'")
        XCTAssertLessThanOrEqual(t.count, MenuBarTitle.maxLength)
        XCTAssertFalse(t.hasSuffix(" "))
    }

    func testShortLineIsLeftAlone() {
        XCTAssertEqual(MenuBarTitle.truncate("VIL 2–1 LEV"), "VIL 2–1 LEV")
    }

    func testTruncationKeepsTheScoreRatherThanTheClock() {
        let g = game("l", at: "2026-09-20T13:00Z", state: .live, h: 2, a: 1, detail: "90'+5'")
        let t = MenuBarTitle.text(for: g, zone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertTrue(t.contains("2–1"), "the score must survive truncation, got \(t)")
        XCTAssertLessThanOrEqual(t.count, MenuBarTitle.maxLength)
    }
}

@MainActor
final class FavoritesTests: XCTestCase {
    private let zone = TimeZone(identifier: "America/New_York")!

    private func store(_ p: FakeProvider) -> ScoreStore {
        ScoreStore(provider: p,
                   preferences: Preferences(enabledLeagueIDs: ["eng.1"]),
                   zone: zone,
                   now: { ESPNProvider.date(from: "2026-09-20T18:00Z")! })
    }

    func testLoadsTeamsForEnabledLeagues() async {
        let p = FakeProvider()
        p.teamsByLeague["eng.1"] = [team("1", "ARS"), team("2", "LIV")]
        let s = store(p)
        await s.loadTeams()
        XCTAssertEqual(s.teamsByLeague["eng.1"]?.count, 2)
    }

    func testTogglingAFavouriteIsReflectedAndPersists() async {
        let p = FakeProvider()
        let arsenal = team("1", "ARS")
        p.teamsByLeague["eng.1"] = [arsenal]
        let s = store(p)
        await s.loadTeams()

        XCTAssertFalse(s.isFavorite(arsenal))
        s.toggleFavorite(arsenal)
        XCTAssertTrue(s.isFavorite(arsenal))
        XCTAssertTrue(s.preferences.favoriteTeamIDs.contains(arsenal.id))
        s.toggleFavorite(arsenal)
        XCTAssertFalse(s.isFavorite(arsenal))
    }

    func testFavouritesOnlyHidesOtherGamesImmediately() async {
        let p = FakeProvider()
        let s = store(p)
        let keep = game("keep", at: "2026-09-20T17:00Z", state: .live)
        p.byDay[s.today] = [keep, game("drop", at: "2026-09-20T17:30Z", state: .live)]
        await s.refresh()
        XCTAssertEqual(s.sections.first?.games.count, 2)

        s.toggleFavorite(keep.home)
        s.preferences.favoritesOnly = true
        XCTAssertEqual(s.sections.first?.games.map(\.id), ["keep"],
                       "filtering must apply without waiting for a refetch")
    }

    func testTeamsAreOnlyFetchedOncePerLeague() async {
        let p = FakeProvider()
        p.teamsByLeague["eng.1"] = [team("1", "ARS")]
        let s = store(p)
        await s.loadTeams()
        p.teamsByLeague["eng.1"] = []      // a second fetch would blank it
        await s.loadTeams()
        XCTAssertEqual(s.teamsByLeague["eng.1"]?.count, 1)
    }
}
