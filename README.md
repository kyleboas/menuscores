# MenuScores

A minimal macOS menu bar app for live scores and upcoming games.
Swift 6 + SwiftUI `MenuBarExtra`. Local build, no account, no analytics.

## Status

The data test passed against the live feed on 2026-09-20 for all six default
leagues, and the app runs. 37 unit tests pass.

## Run the data test first

The feed is the risky part, not the interface — so it has its own check:

    swift run scorefeed-probe            # all default leagues
    swift run scorefeed-probe nfl eng.1  # specific ones

It verifies, against the live API, that today's scoreboard responds, that each
of the next 7 days is retrievable, that day queries agree with the provider's
published calendar, and it renders the exact menu bar string end to end.
Re-run it whenever scores look wrong; it will tell you whether the feed or the
app is at fault.

## Seeing the interface without running it

    swift run render-preview out.png dark    # or: light

Renders the dropdown offscreen to a PNG with real data from the feed. Useful
for checking layout without screen-recording permission — it is what caught
long team names breaking mid-word.

Note that `ImageRenderer` does not lay out `ScrollView` contents, so the
preview composes `DayTabs` and `SectionList` directly and shows every section
expanded rather than scrolling, so the day strip runs off the edge there.

## Diagnosing a menu bar that looks empty

The app owns its `NSStatusItem` explicitly rather than using SwiftUI's
`MenuBarExtra`, so it can report what happened. Run the bundle from a terminal:

    ./build/MenuScores.app/Contents/MacOS/MenuScores

    [MenuScores] status item at x=0 y=0 w=99 visible=true screen=1440x932

and to drive it the way a click would, without clicking:

    MENUSCORES_SELFTEST=1 ./build/MenuScores.app/Contents/MacOS/MenuScores

    [MenuScores] title now: " VIL 2-1 LEV 84'"
    [MenuScores] popover shown after click: true

## Build and install

    ./build-app.sh                 # produces build/MenuScores.app
    open build/MenuScores.app

To keep it running, drag `build/MenuScores.app` to `/Applications` and add it
to Login Items. Updates are manual by design: rebuild and replace.

## What it does

- **Menu bar** — one pinned line: the live score while a game is on, otherwise
  the next matchup and its start time in your zone, on a 24-hour clock. Reads "Scores…" until the
  first fetch lands and "No games" when nothing is on, never a bare glyph, and
  is capped at 22 characters so it survives a notched display.
- **Dropdown** — a day strip (Yesterday / Today / Tomorrow, two days back and
  seven forward) over the selected day's games, grouped into collapsible
  league cards: badge, "England - Premier League", then a row per game as
  `[FT] Bournemouth (crest) 0 - 1 (crest) Liverpool`. A live game shows a green
  pill with the minute; a fixture that has not kicked off shows no pill and its
  start time instead of a score.
- **Favorites** — pick leagues; optionally hide everything but favorite teams.
- **Freshness** — "Updated 20 seconds ago" is always on screen, and a failed
  refresh shows an orange warning naming the cache age.
- **Refresh** — 30s while a game is live, 2min within an hour of kickoff,
  15min otherwise, with exponential backoff capped at 10min while failing.
  Days are cached individually: the fast live tick refetches only today, since
  that is the only day whose scores can change. Polling starts at launch (from
  the app delegate, not the dropdown) and restarts on wake from sleep.

Deliberately absent: notch handling, news, video, betting odds, cloud sync,
auto-update.

## What the feed actually supports

Probed 2026-09-20 against `site.api.espn.com`:

| Query | Result |
|---|---|
| `?dates=yyyyMMdd` | 200 — works for past and future days |
| `?dates=yyyyMM` | 200 — whole month |
| `?dates=yyyyMMdd-yyyyMMdd` | **400 — the range syntax is gone** |

The removed range syntax is what cost the original app its multi-day schedule.
This app never emits it: the 7-day view is built from single-day queries.

`leagues[0].calendar` lists real fixture days and is used to skip empty ones —
but only as an optimization. MLB publishes just 20 calendar entries, so it is
not a complete index, and today is never skipped on its say-so.

## Structure

Provider-specific code is isolated so a failing feed can be swapped without
touching the interface:

    Sources/ScoreKit/          # models, provider protocol, store — no UI
      ScoreProvider.swift      # the protocol + CivilDay
      ESPNProvider.swift       # the only file that knows about ESPN
      ScoreStore.swift         # caching, freshness, refresh cadence
      Freshness.swift          # age wording + refresh policy
      MenuBarTitle.swift       # pure string logic, unit tested
    Sources/MenuScoresUI/      # SwiftUI views, imports only ScoreKit types
    Sources/MenuScoresApp/     # NSStatusItem + NSPopover, app lifecycle
    Sources/scorefeed-probe/   # the data test
    Sources/render-preview/    # offscreen PNG render of the dropdown
    Tests/ScoreKitTests/

To add a provider, implement `ScoreProvider` and pass it to `ScoreStore`.

## Tested edge cases

`swift test` — 37 tests covering the failure modes that break score apps:

- Postponed/suspended/canceled games reported by ESPN as `state: "post"`,
  which a naive reader shows as a 0–0 final.
- Time zones: a 03:30Z kickoff is the 20th in New York, the 21st in London.
- Midnight rollover and DST: day arithmetic goes through `CivilDay`, so
  adding a day across 2026-11-01 lands on the 1st, not 23 hours later.
- Lost connection: cached games survive, but the failure is always surfaced
  with the cache age — the specific bug found in the original app.
- Recovery clearing the warning, de-duplication, favorites filtering,
  and a calendar that omits today never suppressing a live game.

## Known limits

- Unsigned local build. macOS may warn on first launch; ad-hoc signed so the
  network permission sticks.
- ESPN's endpoint is undocumented and can change again. That is what the probe
  is for.
- Favorites can be toggled off in Settings, but the click-to-favorite
  interaction in the game list is not implemented yet.
- No red-card markers. The scoreboard endpoint's per-team statistics do not
  include cards, so showing them would mean a second request per game.
- League badges are baked-in CDN URLs (the internal ids are not derivable from
  the slug), in both variants: ESPN's "-dark" asset is a white knockout, so the
  full-colour "500" asset is used in light mode. Crests come from the feed.
  Both are cached in memory only.
- Only the days on screen are fetched: the selected day, today, and tomorrow
  (so the menu bar can name the next fixture once today's games finish).
