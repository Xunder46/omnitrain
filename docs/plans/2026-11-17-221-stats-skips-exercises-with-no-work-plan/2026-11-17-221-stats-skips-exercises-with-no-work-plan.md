# Plan 221 — Stats leaves out an exercise that has no work in it

Series: second Stats review (Fable, 2026-11-17) open items 2 and 3, after plans 157a and 218. Phone only (`lib/core/services/stats_progress_service.dart`), one builder run, then docs. Status: BUILT, reviewed (APPROVE WITH FIXES, fixed), verified, COMMITTED.

## Goal and acceptance

An exercise that was added to a workout but never done still shows on Stats: a run never started reads as a row at `0:00` with one session and no trend point, and the emptied lift that plan 218 keeps in a watch-linked workout reads as trained at `0.0 kg`. Both are probed on the current code (best 0.0, 0 points). After this change an exercise whose logs hold no readable value on any day is left out of the Instruments rows, the Records & Trends list and every other reader of the per-exercise summaries.

Acceptance: S-22101..S-22104 green, the ones marked "fails without" red at the base commit; the Stats service readers (`instrument_list_service_test`, `stats_progress_service_test`, `exercise_metric_service_test`, `records_and_trends_screen_test`, `stats_best_single_session_screen_test`, `stats_one_failure_service_test`) green and unchanged; `flutter analyze` at baseline (181, 0 errors); full suite no new red.

## What the user sees

- A run added and never started no longer appears on Stats or in Records & Trends. A lift emptied by the end of a watch-linked workout no longer appears as trained at 0.0 kg.
- An exercise with any real value on any day (a logged set, a started timed exercise with a duration) is unchanged.
- Not changed here: the Training Mix of a workout whose only work is never-started rounds (open item 1).
- To SEE it: add a run to a workout, never start it, finish; open Stats.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-1 | In `StatsProgressService.computeExerciseMetrics` (`stats_progress_service.dart:1089`), after the `points` loop, `if (points.isEmpty) continue;` (with a one-line comment): an exercise with no readable value on any day contributes no summary. The one function is the source of the Instruments rows (`_buildInstrumentSections` calls it for the current and previous window), Records & Trends and Exercise Progress, so every reader follows. | `stats_progress_service.dart:1124-1182`, `:1290-1294` |
| D-2 | No change to `_nativeValueFor`, the zero fallback or the totals: a completed session still counts in the session total (open item 2 of plan 220 is the other half). | scope |
| D-3 | Wording unchanged; this removes a row. | scope |

## Scenarios

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-22101 | Mock service test: one completed session whose only exercise is a timed `Easy Run` added and never started (the probe fixture: `createNewSession(modality: 'cardio_endurance')`, `addExerciseToSession`, `endSession`). | `computeExerciseMetrics()` is empty and `computeInstrumentSections(window: statsWindow())` has no rows. | the base returns a row with best 0.0 and no points |
| S-22102 | A live session with a lift added and nothing logged, ended with `endSession(writeToHealth: false)` (the wrist-linked end that keeps the emptied exercise). | no summary for the lift; no instrument row. | the base shows the lift trained at 0.0 kg |
| S-22103 | A lift with one logged set (100 x 3, rest at 1) plus a second lift with nothing logged, `endSession(writeToHealth: false)`. | exactly one summary (the logged lift). | passes with and without the change in part: pins that a real exercise is never dropped (mutation: the guard skips every exercise) |
| S-22104 | A timed exercise started and finished (`startTimedEntry`, `finishTimedEntry`) in a completed session. | a summary with one point. | guards the other side: a real timed exercise stays (mutation: the guard skips every timed exercise) |
| S-22105 | Screen (Mock only): Records & Trends over S-22101's history. | no `records_entry_*` row for the run and the list shows its empty state. | the run's row is listed |

## Input-reality checklist

1. Writers and units: none; a read-side filter.
2. Lifecycle: applies on every load.
3. Settings: none.
4. Time: none.
5. Cost: one `isEmpty` per exercise.
6. Words: none.
7. Readers: every consumer of `computeExerciseMetrics` (listed below).

## Phases

1. **P1 builder-app**, scope `lib/core/services/stats_progress_service.dart`, `test/stats_skips_exercises_with_no_work_test.dart` (new, S-22101..S-22105): the one-line production change and the tests. No full suite.
2. **P2 lead**: docs, mutation pass, review, full suite.

## Readers

`lib/core/services/stats_progress_service.dart` callers of `computeExerciseMetrics` (`_buildInstrumentSections`, Records & Trends, Exercise Progress, `recentPRs` if it reads it); tests `instrument_list_service_test`, `stats_progress_service_test`, `exercise_metric_service_test`, `records_and_trends_screen_test`, `stats_best_single_session_screen_test`, `stats_one_failure_service_test`, `stats_four_week_window_screen_test`, `instrument_list_screen_test`. A test that seeds an exercise with no readable value and expects a row is reported (file, name, premise), not edited.

## Mutation list (lead)

(a) the guard skips every exercise; (b) the guard is `points.length < 2`; (c) the guard is removed; (d) the guard skips timed exercises.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/stats_screen.md` | ADDED | - | `no readable value on any day` | S-22101, S-22102 |
| `docs/state_management/services_and_utils.md` | MODIFIED | trained inside the range, | that holds a readable value on at least one day | S-22101 |

Stale-term sweep (`grep -rIn "computeExerciseMetrics" docs`): read each hit; a sentence that says every exercise of a session appears gets MODIFIED.

## Open items

1. The Training Mix of a workout whose only work is never-started rounds still reads 100% Resistance (the Fable review's item 2, second half). Needs its own look at the Mix rule (plan 179).
2. Plan 220 open item 2: a watch-linked workout with nothing logged still counts as a completed workout in the total.
3. (review, accepted) A lift on the weight axis whose window holds only bodyweight days (weight 0, reps > 0) reads zero on those days and now leaves Stats; before it drew a misleading 0.0 point. Narrow edge: the axis rule keeps such a lift on the weight axis only when loaded sets outnumber bodyweight ones over its whole history.
4. The builder found the brief's guard alone never fires (the section helpers return a zero fallback, never null), so the change is the guard plus a skip of any day whose value reads zero (`if (value.value <= 0) continue;`). Review also removed the now-dead zero-value branch in `_buildInstrumentSections` and the stale doc claim.

## Predicted files

`stats_progress_service.dart` (+3), one new test file, one doc.

## Progress

- [x] Seeded and probed (best 0.0, 0 points for both cases)
- [x] P1 build (19 min) + fix 1 (two readers)
- [x] Docs, mutation pass (3 mutants killed), review (1 major: dead branch and comment, fixed; 2 minor)

## Assumption Log

- 2026-11-17: base commit `964dc4c7` on `claude_develop` (plan 219 and the gate-test exclude are uncommitted in the tree); other sessions' `docs/plans/2026-11-15-208-fuel-burned-per-day-plan/` and `test/stats_gallery_render_test.dart` are outside this plan.
- 2026-11-17: scenario ids checked: none in the five-digit form.

## Feedback

- 2026-11-17: S-1010 (`instrument_list_service_test`) and S-1017 (`instrument_list_screen_test`) pinned a zero-valued row; they were rewritten (the row is absent; the sparkline case uses a one-day row) instead of only reported. The owner's review called these rows wrong.
