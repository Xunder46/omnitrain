# Plan 210 — Recent PRs covers every lift you have logged

Series: Stats pre-launch review group C (item 6, first half, of memory `stats-prelaunch-review-2026-11-12`; index `docs/plans/2026-11-13-157-stats-what-counts-series.md`, "Group C"). Owner decision 2026-11-15: "Recent PRs covers every lift (5 newest)". Phone only (`lib/core`), one builder run, then docs. Status: BUILT, verified, uncommitted.

## Goal and acceptance

Recent PRs on Records & Trends lists the five newest personal records, one per exercise. Today the scan only walks the lifts `computeProgressData` selects for the recent window and caps at the three most-trained (`kTopLiftCount = 3`, `stats_progress_service.dart:170`, `:307-327`). The cap is a cost limit, not a product rule: its own comment says "Not a display list", and nothing in `lib/` reads `StatsProgressData.topLifts` outside the service. So a record on a fourth lift, or on a lift you have not trained in the window, never shows, although the in-workout PR toast fires for every lift.

After this change every exercise with a logged set is scanned over its whole history. `recentPRs` is still the five newest records, newest first, one entry per exercise at its current best (the existing dedupe), and `topLifts` is unchanged: still the window's three most-trained lifts.

Acceptance: S-21101..S-21107 green on Mock and Hive, the ones marked "fails without" red at the base commit; the 299 tests of the nine reader files green (a trial of the exact production change already ran them: 299 passed); `flutter analyze` at the plan's baseline (181, 0 errors); the cost measurement below; full suite no new red.

## What the user sees

- Before: Recent PRs shows records for at most your three most-trained lifts; a record on any other lift is never listed.
- After: the five newest records across all your lifts, each lift once at its best. A lift you stopped training weeks ago can still appear if its record is among the five newest.
- To SEE it: log a first set on four or more different lifts over a few days, open Records & Trends: five entries (it showed three).
- Unchanged: the card's layout, the values (Est. 1RM or reps), the Stats screen, the in-workout toast, the wrist.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-1 | `computeProgressData` scans `scanIds` = the window's `topLiftIds` (in their ranked order) followed by every other exercise id that has a `set` effort in any completed session, sorted. The three full-history builders and `_repsAxisExercises` take `scanIds`. | `stats_progress_service.dart:307-327` |
| D-2 | `topLifts` keeps only the lifts in `topLiftIds` (`if (topLiftSet.contains(exerciseId))` around the `LiftProgress` add), so its length, order and content are exactly as today. | S-21103, `test/stats_progress_test.dart:401` |
| D-3 | A lift outside the top set gets its name from `_exerciseById` (the cache holds window lifts only); an id with no catalog row reads as the id, like today. | `stats_progress_service.dart:289-296` |
| D-4 | New private `_liftIdsInHistory(completed, {required Set<String> exclude})`: ids of `set` efforts with a non-null `exerciseId` over `completed`, minus `exclude`, sorted. | trial 2026-11-16 |
| D-5 | `kTopLiftCount`'s doc and `StatsProgressData.topLifts`'s doc say the cap decides only which lifts get a trend entry; the record scan covers every lift. No other wording change in the app. | scope |
| D-6 | The per-exercise axis rule, the Epley cap, the dedupe and the newest-first sort are untouched; PR detection per lift is unchanged code. | existing tests |
| D-7 | Cost is measured, not assumed: the lead runs a throwaway probe over a seeded history (417 sessions over two years, 40 lifts, 3 efforts of 4 sets per session) before and after, and reports both figures. Stop and report if `computeProgressData` after the change exceeds 1.5 s on the Mac, or makes it more than three times slower. Measured 2026-11-16 (3 runs each, median): Mock 10 ms to 31 ms, Hive 16 ms to 37 ms; the absolute figure is far under the ceiling, and the Mock ratio is about 3x (the Hive ratio 2.3x), judged immaterial at +20 ms and reported. | input-reality 5 |

## Scenarios

Numbers re-derived with a throwaway script of the Epley rule `w * (1 + reps / 30)` (reps 5 here, below the 12-rep cap). All through `StatsProgressService(repo).computeProgressData()`, Mock and Hive. Day offsets are days before today; a record's `date` is that day at local midnight.

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-21101 | Six lifts L1..L6, one session each, one set of 5 reps: L1 60 kg on day -6, L2 70 on -5, L3 80 on -4, L4 90 on -3, L5 100 on -2, L6 110 on -1. | `recentPRs` has 5 entries, newest first: L6 128.333, L5 116.667, L4 105.0, L3 93.333, L2 81.667 (all `closeTo(.., 0.01)`), dated -1..-5; L1 is absent. | only three lifts are scanned, so three entries |
| S-21102 | Lift "Old Lift" 100 kg x 3 on day -45 (outside the window), lift "Row" 50 kg x 5 on day 0. | `recentPRs` is [Row 58.333 on day 0, Old Lift 110.0 on day -45]. | Old Lift is not selected for the window, so only Row |
| S-21103 | The S-21101 fixture. | `topLifts` has exactly 3 entries. | passes with and without the change on purpose: the cap now decides only `topLifts` (mutation: leave `topLifts` uncapped, 6 entries) |
| S-21104 | Bodyweight lift "Push-up": three sets of 20, 15, 12 reps at 0 kg on day -50, plus "Row" 50 kg x 5 on day 0. | `recentPRs` is [Row, Push-up]; the Push-up entry has `reps == 20`, `e1Rm == null`, dated day -50. | Push-up is outside the window, so only Row |
| S-21105 | One lift with three improving days: 60 x 5 on day -9, 70 x 5 on day -5, 80 x 5 on day -2. | one entry, e1Rm 93.333, dated day -2. | passes with and without the change on purpose: the per-exercise dedupe still applies to every lift (mutation: skip the dedupe, three entries) |
| S-21106 | No set effort anywhere: one cardio session with a timed effort only. | `recentPRs` and `topLifts` are empty. | passes with and without the change on purpose: the id walk finds no lift (it guards the mutant that keeps non-`set` ids, which the mutation pass ruled equivalent: the builders read only `set` efforts, so nothing changes) |
| S-21108 | Fourteen training days of "Row" 50 kg x 5 (days 0..13) fill the recent-days window; "Old Lift" 100 x 3 on day 45. | `recentPRs` is [Row, Old Lift]; the Old Lift entry reads its catalog name and e1Rm 110.0. | Old Lift is not scanned (one entry); with the name lookup dropped it would read `ex-old` (added after the mutation pass: S-21102's Old Lift sits inside the 14-training-day window and so is name-cached) |
| S-21107 | The S-21101 fixture plus one more lift "Name Only" whose effort row names an exercise id with no catalog row, 40 kg x 5 on day 0. | `recentPRs` has 5 entries and the first is the unknown id's record, its `exerciseName` equal to the raw id, e1Rm 46.667. | the lift is not scanned at all |

## Input-reality checklist

1. Writers and units: sets are written by the logging screen, routines, the importer and the watch; weight is stored in kg, reps as integers; the PR value is the Epley estimate (capped at 12 reps) or the reps count on the reps axis, unchanged.
2. Lifecycle: only completed sessions are scanned, as today. A lift whose every set is unusable (zero weight and zero reps) yields no trend and no record (existing behaviour, `test/stats_progress_test.dart:281`).
3. Settings: none read; the preferred weight unit converts only at display.
4. Time: a record's date is its training day at local midnight; the newest-first sort is by that date, then by name, as today.
5. Cost: the scan now walks every lift. The three walks (`_liftIdsInHistory`, `_buildFullSetsForExercises`, `_buildFullRepsForExercises`) each go once over the history index; `_repsAxisExercises` and one `_exerciseById` run per scanned lift. D-7 measures it.
6. Words: no new on-screen wording; docs in the Docs delta.
7. Slot competition: Records & Trends is the only reader of `recentPRs` (`records_and_trends_screen.dart:108`); the Stats screen has no PR card; `topLifts` has no UI reader.

## Phases

1. **P1 builder-app, scope `lib/core/services/stats_progress_service.dart`, `lib/core/models/stats_progress.dart`, `test/stats_recent_prs_every_lift_test.dart` (new):** (1) the exact production code below; (2) the doc comments of `kTopLiftCount` and `StatsProgressData.topLifts` per D-5; (3) new test file with S-21101..S-21107 over `harnessFactories` (Mock and Hive), seeding helpers copied from `test/stats_progress_test.dart` (`_seedSession`, `_addSetEffort`) generalised to `WorkoutRepository`. Report FIRST as a skeleton. Done: the new file and the nine reader files green; no full suite.
2. **P2 lead:** docs (below), cost probe (D-7), mutation pass, `crew-reviewer`, full suite.

Exact production code (P1) is the diff of the trial run, in `.work/crew/2026-11-16-210/brief-builder-app-p1.md`.

## Readers (existing tests that pin the old rule)

Trial of the exact production change on the nine files that read `recentPRs`, `computeProgressData` or `kTopLiftCount` (`stats_progress_test`, `est_1rm_cap_and_axis_test`, `services_test`, `in_session_pr_toast_test`, `modality_mix_shift_test`, `interference_test`, `fuel_row_screen_test`, `protein_consistency_test`, `fuel_vs_load_test`): 299 passed, 0 red. A red anywhere else is reported, not edited.

## Mutation list (lead)

(a) `scanIds` = `topLiftIds` only; (b) the `topLifts` guard removed (all scanned lifts added); (c) `_liftIdsInHistory` keeps non-`set` efforts; (d) `_liftIdsInHistory` skips the `exclude` test (a lift twice); (e) the name lookup dropped (non-top lifts read as the id; killed only by S-21108); (f) `_repsAxisExercises` still called with `topLiftIds.toSet()`.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/records_and_trends.md` | MODIFIED | nothing. The PR list Records & Trends renders is the service's own `recentPRs`. | the five newest records, one per exercise, over every exercise | S-21101, S-21102 |
| `docs/records_and_trends.md` | ADDED | - | `test/stats_recent_prs_every_lift_test.dart` | S-21101 |

Stale-term sweep (`grep -rIniE "recentPRs|kTopLiftCount|topLifts|PR scan|top lifts" docs`, minus plans/history/releases): `records_and_trends.md:22` (the row above), `stats_screen.md:137` ("Recent PRs ... live in Records & Trends", still true), `stats_best_load_investigation.md` (an investigation snapshot, not edited).

## Open items

1. The other half of review item 6 (all-time Best as a running total for cardio without distance and for rounds) is plan 211.
2. A lift trained only long ago can appear in Recent PRs under "Recent"; the card's title is unchanged (owner chose "every lift").
3. (review finding 2, owner please note) A set that was never logged but is stored with a carried or zero weight counts as done in the record scan, as it already did for the three window lifts: a pre-157a placeholder (0 kg x 10 reps) puts a "10 reps" record on a lift never trained, and a watch-linked session keeps its planned sets until 157d. Plan 157a stops new placeholders at Finish, and the app is not released yet (owner, 2026-11-16) and the stats redesign shipped with no legacy-data handling (owner, earlier), so no scenario pins the bad case; after this plan it can reach every lift, not only three. Not fixed here: the right fix is 157d (what counts as done for wrist-linked sessions) plus the owner's call on old data.

## Predicted files

`stats_progress_service.dart` (+40, 6 call-site edits), `stats_progress.dart` (doc only), new `test/stats_recent_prs_every_lift_test.dart`, `docs/records_and_trends.md`.

## Progress

- [x] Seeded: scan read, `topLifts` readers checked (none in UI), trial run of the exact change over nine reader files (299 green)
- [x] P1 build (4.9 min; 313 tests green)
- [x] Docs, cost probe (D-7), mutation pass (6 mutants: 5 killed, 1 equivalent; S-21108 added to kill the name-lookup mutant)
- [x] Review: APPROVE WITH FIXES (blocker: a stale function dartdoc, fixed; major: placeholder exposure, now Open item 3; minor: S-21106 wording, fixed)
- [x] Full suite (+7739, 0 failures)
- [ ] (owner) See five PRs on Records & Trends after a first set on four lifts

## Assumption Log

- 2026-11-16: base commit `9ce80fd5` on `claude_develop`; the tree holds other sessions' watch work and `test/stats_gallery_render_test.dart`, none in this plan's scopes.
- 2026-11-16: scenario ids S-211xx chosen after grep over `test`, `docs`, `lib`, `watch` found no S-211xx.
- 2026-11-16: "Old Lift" on day -45 is outside the window by the same fixture `test/stats_progress_test.dart` S-006 uses (45 days).

## Feedback

(none yet)
