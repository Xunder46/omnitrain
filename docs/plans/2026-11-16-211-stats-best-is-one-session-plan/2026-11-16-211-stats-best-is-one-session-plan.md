# Plan 211 — A "Best" is one session, not a running total

Series: Stats pre-launch review group C (item 6, second half, of memory `stats-prelaunch-review-2026-11-12`; index `docs/plans/2026-11-13-157-stats-what-counts-series.md`, "Group C"). Owner decision 2026-11-15 ("Yes, use them"): Records & Trends's all-time Best is the best single session for a cardio exercise with no distance and for rounds; the Instruments window rows keep their labelled totals. Phone only (`lib/core`, two screens), two builder runs, then docs. Status: BUILT, verified, uncommitted.

## Goal and acceptance

Records & Trends and Exercise Progress show a "Best" per exercise. For two kinds of exercise that figure is today a running total over all history, not a best:

- a cardio exercise with no distance anywhere in its history shows the sum of every finished timed entry ever logged (`_cardioValue`, `stats_progress_service.dart:1669`, the `totalDurationSecs` fallback): three rides of 20, 35 and 25 minutes read `1:20:00` as the Best;
- a rounds exercise shows every finished round ever (`_sportsValue`, `:1760`): sessions of 3, 5 and 2 rounds read `10 rounds` as the Best, with `22 min`.

After this change both screens show the best one session: `35:00` for the rides, `5 rounds` (and that session's `10 min`) for the rounds. A cardio exercise with a distance keeps its fastest pace, a hold keeps its longest hold, a lift keeps its e1RM, all as today. The Instruments rows on the Stats screen keep their totals (`Total time`, `N rounds` with `Total time`), because that row is a window readout.

Acceptance: S-21201..S-21209 green on Mock and Hive, the ones marked "fails without" red at the base commit; the existing metric and instrument tests unchanged and green; `flutter analyze` at the plan's baseline (181, 0 errors); full suite no new red.

## What the user sees

- Before: an exercise with no distance (a bike, an elliptical, a class) shows an ever-growing time as its Best; a martial-arts exercise shows an ever-growing round count. After a year the "Best" is just how long you have used the app.
- After: the longest single session on Records & Trends and on the exercise's page. It only grows when you beat it.
- To SEE it: log three sessions of the same cardio exercise with no distance (20, 35, 25 minutes), open Records & Trends: `35:00`. Open Stats: that exercise's Instruments row still shows the window's total.
- Unchanged: pace, hold, lift values; the trend line and the recent-sessions list (they show one figure per training day, a day's own total); the Instruments rows; the Stats totals.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-1 | `computeExerciseMetrics` gets a named parameter `bool bestSingleSession = false`. With it, an exercise whose all-history value is a `duration` or `rounds` reading is re-read per session and the largest session value wins. Default off keeps every other caller (the Instruments rows read it with a window range) exactly as today. | `stats_progress_service.dart:1083`, `:1280-1287` |
| D-2 | The two all-time screens opt in: `records_and_trends_screen.dart:97` and `exercise_progress_screen.dart:68` call `computeExerciseMetrics(bestSingleSession: true)`. They already share one value, so they cannot disagree. | `docs/records_and_trends.md` Overview |
| D-3 | "Session" means a completed session (the same `session.id`), not a calendar day, as the owner said. Two sessions on one day give the larger one, not their sum. The per-day trend points are unchanged, so on a day with two sessions the chart's peak can exceed the Best; accepted, a rare case, disclosed. | owner words; plan 209's `points` rule |
| D-4 | The winner is read by the section's own rule over that session's logs of the exercise (`_nativeValueFor`), so a round's secondary figure is that session's round minutes and the finished-entry and finished-round predicates are the existing ones. Ties keep the earlier session. | `_cardioValue`, `_sportsValue` |
| D-5 | Only a `duration` or `rounds` result is re-read. A `pace`, `hold`, `estimatedOneRepMax` or `reps` result, and the zero fallback, is returned as it was. A cardio exercise with any distance entry stays on pace. | `_cardioValue` pace branch |
| D-6 | No on-screen wording change: the figure keeps the `Best` label on Exercise Progress and no label on the Records entry. The Instruments rows keep `nativePrimaryLabel`'s `Total time`. | `native_value_format.dart:96-110` |

## Scenarios

Fixtures use the helpers of `test/exercise_metric_service_test.dart` (`seedSession(daysAgo:)`, `addTimedEffort`, `seedTimedEntry`, `seedRoundEffort`, `roundInstance`) over `harnessFactories` (Mock and Hive). One timed entry per session unless said; durations in seconds.

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-21201 | Cardio "Elliptical", no distance row anywhere, three sessions on days -3, -2, -1: 1200 s, 2100 s, 1500 s. `computeExerciseMetrics(bestSingleSession: true)`. | `best.metric == duration`, `best.value == 2100`. | the value is the 4800 s total |
| S-21202 | Rounds "BJJ", three sessions: 3 finished rounds of 180 s (9 min), 5 of 120 s (10 min), 2 of 90 s (3 min). Same flag. | `best.metric == rounds`, `value == 5`, `secondaryValue == 10` (minutes, closeTo 0.01). | the value is 10 rounds and 22 minutes |
| S-21203 | Cardio "Run": session A one entry 1500 s over 5000 m (300 s/km), session B one entry 3600 s with no distance. Same flag. | `best.metric == pace`, `value == 300`, equal to the default call. | passes with and without the change on purpose: pace is never re-read (mutation: re-read every metric per session, the result becomes duration 3600) |
| S-21204 | The S-21201 and S-21202 fixtures. Default call `computeExerciseMetrics()` and `computeInstrumentSections(window: windowOfDays(...))` covering all three sessions. | the default call and the Instruments rows still read the totals: Elliptical duration 4800, BJJ rounds 10 with 22 minutes. | passes with and without the change on purpose: it pins that the default stays on totals (mutation: the flag default `true`) |
| S-21205 | Records & Trends screen over the S-21201 fixture (`RecordsAndTrendsScreen`). | the Elliptical entry reads `35:00`, not `1:20:00`. | the entry reads the total |
| S-21206 | Exercise Progress screen over the S-21202 fixture. | the Best pill reads `5 rounds`, the `Total time` pill `10 min`, Sessions `3`. | the pills read `10 rounds` and `22 min` |
| S-21207 | Cardio "Bike", no distance: two sessions on the same day (day -1), 1200 s each, one on day -3 of 1500 s. Same flag. | `best.value == 1500` (the larger single session; the day's two sessions are not summed to 2400). | passes the same under a per-day rule only if the day is largest, so the fixture makes the day total (2400) the largest and the session (1500) the best: a per-day implementation reads 2400 |
| S-21208 | Cardio "Walk", no distance, one session whose only entry is unfinished, plus an exercise with no timed instance at all. Same flag. | the zero value on `duration` (`value == 0`), the exercise still listed. | passes with and without the change on purpose: the zero fallback is returned as it was (mutation: the winner is taken without the `> 0` guard, same result, equivalent) |
| S-21209 | Rounds "Sparring", two sessions of 2 finished rounds each: the earlier one with rounds of 100 s, the later with rounds of 300 s. Flag on. | `best.value == 2`, `secondaryValue` closeTo(3.333, 0.01) (the earlier session's minutes, not 10). | passes the same as S-21202's rule on the count; it pins D-4's tie rule (mutation: `>=` takes the later session, 10 minutes). Added after the mutation pass showed the tie rule unguarded |

## Input-reality checklist

1. Writers and units: timed entries and rounds are written by the logging screen, the importer and the watch; durations are seconds, round minutes are minutes, as today; no new unit.
2. Lifecycle: only completed sessions (`endedAtMs != null`) are read, as today; an unfinished timed entry and an unfinished round count for nothing, as today.
3. Settings: none read; the display unit only affects pace, which is not re-read.
4. Time: a session that crosses midnight is one session (grouped by `session.id`, not by day).
5. Cost: only exercises whose value is a duration or rounds are re-read, once per session of that exercise, over the history index the service already holds; no extra repository read. The Stats screen load does not pass the flag.
6. Words: no new wording (D-6); the doc rows in the Docs delta.
7. Slot competition: the two all-time screens and the Instruments rows are the only readers of `computeExerciseMetrics` (`grep -rn computeExerciseMetrics lib`); the interference walk reads `_nativeValueFor` per session directly and is untouched.

## Phases

1. **P1 builder-app, scope `lib/core/services/stats_progress_service.dart`, `lib/core/models/exercise_metric.dart`, `lib/features/stats/records_and_trends_screen.dart`, `lib/features/stats/exercise_progress_screen.dart`, `test/stats_best_single_session_test.dart` (new):** the exact production code in the brief, the doc comments, the two call sites, and the service tests S-21201..S-21204, S-21207, S-21208. Report FIRST as a skeleton. Done: new file green on both stores, existing metric/instrument/records tests green, no full suite.
2. **P2 builder-app, scope `test/stats_best_single_session_screen_test.dart` (new):** S-21205 and S-21206, copying the screen harness of `test/stats_pace_reads_honestly_test.dart` (S-21009 is the Exercise Progress one). Separate run because a screen-test file has design latitude.
3. **P3 lead:** docs (below), mutation pass, `crew-reviewer`, full suite.

## Readers (existing tests that pin the old rule)

`test/exercise_metric_service_test.dart` (S-906 cardio, S-908 rounds: one session each, so the same under both rules), `test/records_and_trends_screen_test.dart`, `test/instrument_list_service_test.dart`, `test/instrument_list_screen_test.dart`, `test/stats_pace_reads_honestly_test.dart`. A red anywhere is reported, not edited.

## Mutation list (lead)

(a) the all-time screens do not pass the flag; (b) the flag defaults to `true`; (c) the re-read is applied to every metric; (d) the winner is the smallest, not the largest; (e) sessions grouped by day, not by `session.id`; (f) the winner is taken without the `> 0` guard (expected equivalent); (g) the secondary figure is the total, not the winning session's; (h) the Instruments caller passes the flag; (i) a tie takes the later session (`>=`). Run 2026-11-16: (a) and the Exercise Progress twin, (b), (c), (d), (e), (g), (h) killed; (f) SURVIVED and is equivalent (a zero winner equals the total's own zero); (i) first SURVIVED, killed once S-21209 was added; (c) needed S-21203 to carry a second, slower distance run (a re-read that took the largest value per session returns 360 instead of 300).

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/records_and_trends.md` | MODIFIED | Pace, or total duration when no distance qualifies | Pace, or the longest single session's duration when no distance qualifies | S-21201, S-21203 |
| `docs/records_and_trends.md` | ADDED | - | Rounds completed in the best session | S-21202, S-21206 |
| `docs/records_and_trends.md` | MODIFIED | Total round minutes | That session's round minutes | S-21202, S-21206 |
| `docs/records_and_trends.md` | ADDED | - | `the Instruments rows keep` | S-21204 |
| `docs/records_and_trends.md` | ADDED | - | `test/stats_best_single_session_test.dart` | S-21201 |

Stale-term sweep (`grep -rIniE "total duration|summed duration|rounds completed|Total round minutes" docs`, minus plans/history/releases): `records_and_trends.md:109` and `:111` (the rows above); `stats_screen.md:323` (`Total time` on the Instruments row, still true).

## Open items

1. On a day with two sessions of one exercise the trend chart's peak (the day's total) can exceed the Best (one session). Accepted.
2. A cardio exercise that mixes sessions with and without distance reads pace; its sessions without distance are ignored for the Best, as before.
3. (owner) A device check: three sessions of a cardio exercise with no distance (20, 35, 25 minutes): Records & Trends reads `35:00`.

## Predicted files

`stats_progress_service.dart` (+35), `exercise_metric.dart` (doc), two screens (one line each), new `test/stats_best_single_session_test.dart` and `test/stats_best_single_session_screen_test.dart`, `docs/records_and_trends.md`, the series index status.

## Progress

- [x] Seeded (scout of `_cardioValue`, `_sportsValue`, the two screens and the Instruments caller)
- [x] P1 build (6.0 min)
- [x] P2 screen tests (6.4 min)
- [x] Docs, mutation pass (10 mutants, 9 killed, 1 equivalent; S-21209 added, S-21203 strengthened)
- [x] Review: APPROVE (2 minors fixed)
- [x] Full suite (+7757, 0 failures)
- [ ] (owner) See `35:00` on Records & Trends

## Assumption Log

- 2026-11-16: base commit `ac1c9b33` on `claude_develop`; the tree holds other sessions' `docs/plans/2026-11-15-208-fuel-burned-per-day-plan/` and `test/stats_gallery_render_test.dart`, none in this plan's scopes.
- 2026-11-16: scenario ids S-212xx; grep over `test`, `docs`, `lib`, `watch` found no S-212xx.
- 2026-11-16: "session" read as the owner said (not day); see D-3.

## Feedback

(none yet)
