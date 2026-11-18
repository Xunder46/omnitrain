# Series 157 — what counts in Stats (group A of the 2026-11-12 pre-launch review)

Source: items 1, 3 and 10 of the Stats pre-launch review (memory `stats-prelaunch-review-2026-11-12`). The owner accepted the recommendations on 2026-11-13 ("A: what counts"). Split by the scope budget (`.github/copilot/pr-scope-budget.md`): three PRs, planned one at a time against the code as it is by then.

| PR | Order | Scope | Tracks | Depends on |
|---|---|---|---|---|
| 157a | 1 (built, uncommitted) | Finish drops every `set` entry never logged and any set exercise left empty (review item 1). Plan: `2026-11-13-157a-stats-unlogged-sets-plan/`. | phone state | none |
| 157b | 2 (built, uncommitted) | Est. 1RM accuracy: the rep count in the estimate is capped at 12 everywhere the formula lives (phone `StatsProgressService.epley1RM`, and the wrist's Swift twin `WatchPersonalBests.estimateOneRepMax`, `watch/watchos/Sources/WatchSessionEngine/WatchPersonalBests.swift:216`, which must give the same number bit for bit); and an exercise sits on the reps axis only when zero-weight entries strictly outnumber weighted ones over its whole history, never because of one set (review items 3 and 10, first half). One decision function shared by `computeProgressData` (`repsDayMap.isNotEmpty`, line ~342) and `_repsAxisExercises` (+ `_hasBodyweightEntry`, line ~1473). | phone `lib/core`, wrist Swift twin | 157a (placeholders stop flipping the axis for new data) |
| 157c | 3 (built, uncommitted) | Sustained High Load: a week that holds sessions but no rated one is left out of the twelve-week baseline instead of counting as zero load (a truly empty week still counts as zero, D-1705). Needs `WeeklyLoad` to say whether the week held sessions (`lib/core/models/training_load.dart:76`, built in `StatsProgressService.weeklyLoads`, line ~603; baseline in `lib/core/models/sustained_high_load.dart:106`). Review item 10, second half. | phone `lib/core` | none (can run beside 157b only if scopes are disjoint: both touch `stats_progress_service.dart`, so serial) |
| 157d | after 157a (order open) | Prune planned sets of workouts the watch took part in, once the watch's rows have settled (the importer's side; D-11 of 157a skips them today). Needs a rule for "settled" and the late-entry path (`_placeAroundUserRows`, plan 03d). | phone state + importer | 157a |

## Shared decisions

- No migration: nothing stored before these changes is repaired (D-8 of 157a).
- Rep cap is 12 (the owner accepted "about 12"); the cap changes the displayed Est. 1RM and the in-session New PR toast together because they call one function.
- Axis rule on a tie goes to the weight axis (the example that motivated it: a lift with one stray zero-weight set).
- 157b changes a number the wrist compares for its own PR check: phone and wrist must change in the same PR, and the bests frame's fixtures and the Swift replay traces are readers to list in its seed.

## Owner decisions still open (none blocks 157a)

The Finish dialog's exercise count and a warning for a typed-but-unlogged set (157a Open items).

## Group B (review item 2) — plan 179

`docs/plans/2026-11-15-179-stats-mix-no-sets-plan/`: a session with timed work and no set shares its whole length across the timed modalities instead of giving the unmeasured minutes to Resistance (owner chose this 2026-11-15). Seeded and lint-clean, not built; waits for the owner's build go-ahead.

## Group C (review items 4 and 6) — plans 209, 210, 211

Owner decisions 2026-11-15: pace change reads better/worse (faster = green up); Recent PRs covers every lift (5 newest); "use my defaults" for the rest (Records & Trends best = best single session for cardio without distance and for rounds; a cardio trend line plots one measure only). Split by the scope budget into three small PRs, planned one at a time:

| Plan | Review item | What | Status |
|---|---|---|---|
| 209 | 4 and 6 (trend half) | `docs/plans/2026-11-15-209-stats-pace-reads-honestly-plan/`: pace change reads `↑ 0:10 /km` green when faster; an Instruments row's trend line plots only days in the row's own metric. | committed 9ce80fd5 |
| 210 | 6 (PR half) | Recent PRs from every lift in history, 5 newest; the three trend charts stay on the three most-trained lifts. Load cost to measure first (one Stats load is ~235 ms on 417 sessions). | committed ac1c9b33 (plan `docs/plans/2026-11-16-210-stats-recent-prs-every-lift-plan/`) |
| 211 | 6 (Best half) | Records & Trends shows the best single session for a cardio exercise with no distance and for rounds, not a running total; the Instruments window rows keep their labelled totals. | committed (plan `docs/plans/2026-11-16-211-stats-best-is-one-session-plan/`) |

## Group D (review item 8) — plans 212, 213

| Plan | What | Status |
|---|---|---|
| 212 | `docs/plans/2026-11-16-212-stats-one-failure-keeps-the-screen-plan/`: one failing signal or Fuel read no longer fails the whole Stats load; totals, Instruments and Mix stay core. | committed |
| 213 | Stats reloads silently when new data arrives while it is open (deferred item 2 of the 2026-11-04 input sweep). | dropped for good by the owner 2026-11-16 ("we don't need to reload stats while open ever"); never plan it again |

## Group E (review items 5, 7, 9)

| Plan | What | Status |
|---|---|---|
| 214 | `docs/plans/2026-11-16-214-stats-says-when-effort-rating-is-off-plan/`: the locked Signals line, the hint under a card and the Mix note say when Effort Rating is the reason (item 7, first half). | committed da111335 |
| 213 | `docs/plans/2026-11-16-213-stats-dismissed-signal-can-be-brought-back-plan/`: a dismissed signal shows `Signal hidden for 14 days.` with Undo (item 9, dismiss undo). | committed |
| 215 | `docs/plans/2026-11-16-215-stats-plain-words-for-two-labels-plan/`: the Mix legend says `Recent`, the Progression card says what its percentage is (item 9, jargon half). | committed |
| 216 | `docs/plans/2026-11-16-216-stats-first-month-says-nothing-to-compare-plan/`: a first-month Instruments list says `Nothing to compare yet` while every row reads `new` (item 7, thin first month). | committed |
| 217 | `docs/plans/2026-11-16-217-finish-dialog-counts-what-you-did-plan/`: the Finish dialog counts only the exercises the user did (157a Open item 1). | committed |
| 218 | `docs/plans/2026-11-16-218-wrist-linked-workouts-drop-planned-sets-plan/`: workouts the watch took part in drop their planned sets at the end too (plan 157d), never deleting an exercise. | committed |
| 219 | `docs/plans/2026-11-16-219-stats-visible-records-link-plan/`: Records & Trends is a labelled row at the end of Stats; the header chart icon is gone (item 9, findability). | committed |
| 220 | `docs/plans/2026-11-17-220-finish-with-nothing-logged-discards-plan/`: Finish with nothing logged asks `Discard Workout?` and discards (second review item 1). | committed |
| 221 | `docs/plans/2026-11-17-221-stats-skips-exercises-with-no-work-plan/`: an exercise added and never done leaves Stats (second review items 2 and 3). | committed |
| 222 | `docs/plans/2026-11-17-222-nutrition-entry-below-recent-prs-plan/`: the Nutrition entry on Records & Trends sits below Recent PRs (owner request). | committed |
| 224 | `docs/plans/2026-11-17-224-mix-ignores-a-session-with-nothing-done-plan/`: a workout that holds exercises but nothing done adds no time to the Training Mix (second review item 2, Mix half). | committed |
| 226 | `docs/plans/2026-11-17-226-pace-trend-line-rises-when-faster-plan/`: a faster pace rises on the Exercise Progress chart and the Instruments sparkline, agreeing with the change arrow (second review small item 5). | committed |
