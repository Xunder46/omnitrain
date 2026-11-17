# Plan 220 — Finish with nothing logged discards the workout

Series: second Stats review (Fable, 2026-11-17) open item 1, after plans 157a and 217. Owner answer 2026-11-17: "Discard it". Phone only (`lib/state/workout`, `lib/features/session`), one builder run, then docs. Status: BUILT, reviewed (APPROVE WITH FIXES, fixed), verified, COMMITTED.

## Goal and acceptance

Since plan 157a Finish drops every set nobody logged. A workout where sets were typed but never logged is therefore saved as an empty completed workout: it counts in the session total and the Consistency signal, and the dialog read "0 exercises". After this change, Finish on a workout with nothing done tells the user the workout won't be saved and, on confirm, discards it like an empty one.

Acceptance: S-22001..S-22003 green, the ones marked "fails without" red at the base commit; the finish readers (`finish_drops_unlogged_sets_screen_test`, `finish_completed_exercise_count_screen_test`, `session_finish_timers_test`, `watch_session_finish_test`, `finish_drops_unlogged_sets_test`) green and unchanged; `flutter analyze` at baseline (181, 0 errors); full suite no new red.

## What the user sees

- Finish Workout with at least one thing done (a logged set, a started timed or round exercise): the dialog is unchanged.
- Finish Workout with nothing done and the watch not involved: a dialog `Discard Workout?` with `Nothing was logged, so this workout won't be saved.` and the buttons Cancel / Discard (Discard is the red destructive one). Discard deletes the workout and leaves the screen, exactly as the empty-workout case already does; Cancel keeps the workout open.
- A workout the watch took part in (the wrist runs it, or a wrist row is staged) never takes this path: its caches may not hold the wrist's sets yet, so it keeps the normal dialog and the normal save.
- To SEE it: start a free workout, add a lift, type reps and weight without tapping Log Set, tap Finish Workout.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-1 | `SessionCore.finishWouldSaveNothing()` (extension `SessionCoreLifecycleMethods`, after `completedExerciseCount`), forwarded by `WorkoutState`: `Future<bool>`, true when `completedExerciseCount() == 0`, the injected `wristRunsSession` does not report the session, and the repository holds no staged wrist row for it (the same two checks `endSession` makes, `session_core_lifecycle.dart:15-34`). | plan 217 D-1, 157a D-11 |
| D-2 | `_showFinishSessionDialog` (`workout_session_finish.dart:10`): after the existing empty-session branch and before the Finish dialog, `if (await widget.workoutState.finishWouldSaveNothing())` show `ConfirmationDialog.showTwoChoice` (title `Discard Workout?`, body `Nothing was logged, so this workout won't be saved.`, dismiss `Cancel`, confirm `Discard`, `isDestructive: true`, keys `session-finish-nothing-cancel` / `session-finish-nothing-confirm`); on confirm do what the empty branch does (`_leaving = true; await discardCurrentSession(); pop`). | `workout_session_finish.dart:10-20` |
| D-3 | The Finish dialog's own text is unchanged. | plan 217 |
| D-4 | The wording is the lead's default; the choice to discard is the owner's. | scope |

## Scenarios

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-22001 | State test (Mock and Hive): a live session with a typed-but-unlogged set; then with one logged set; then with a started timed exercise; then the same unlogged session on a `WorkoutState` built with `wristRunsSession: (_) => true`; then with a staged wrist row (`createWatchInboxEntry` as `finish_drops_unlogged_sets_test` S-15712). | `finishWouldSaveNothing()` is true, false, false, false, false. | the method does not exist |
| S-22002 | Screen (Mock only): a session with one typed-but-unlogged set; tap Finish Workout. | the dialog titled `Discard Workout?` with the body above; Cancel closes it and the session is still in the repository; opening it again and tapping Discard leaves the screen, `getAllSessions()` is empty, no `SessionSummaryScreen`. | the base shows `Finish Workout?` and saves an empty workout |
| S-22003 | Screen (Mock only): a session with one logged set (rest at position + 1) and one typed-but-unlogged set; tap Finish Workout. | the normal `Finish Workout?` dialog with `• 1 exercise`; no `Discard Workout?`. | passes with and without the change on purpose: pins that a workout with something done is never discarded (mutation: the check ignores the count) |

## Input-reality checklist

1. Writers and units: no stored value; one repository delete through the existing discard.
2. Lifecycle: decided when Finish is tapped; the dialog is modal.
3. Settings: none.
4. Time: none.
5. Cost: one pass over caches and one inbox read.
6. Words: two plain sentences; `Discard` is the red button like the other discard dialogs.
7. Concurrency: a wrist set arriving while the dialog is open is the one gap, which is why a watch-linked workout never takes this path.

## Phases

1. **P1 builder-app**, scope `lib/state/workout/session_core_lifecycle.dart`, `lib/state/workout/workout_state.dart`, `lib/features/session/workout_session_finish.dart`, `test/finish_nothing_logged_discards_test.dart` (new, S-22001), `test/finish_nothing_logged_discards_screen_test.dart` (new, S-22002/S-22003): exact code in the brief. No full suite.
2. **P2 lead**: docs, mutation pass, review, full suite.

## Readers

`test/finish_drops_unlogged_sets_screen_test.dart` (S-15709), `test/finish_completed_exercise_count_screen_test.dart` (S-21704), `test/session_finish_timers_test.dart`, `test/watch_session_finish_test.dart`, `test/finish_drops_unlogged_sets_test.dart`, `test/screen_widget_test.dart` finish cases. A reader whose session has nothing logged and expects the old Finish dialog is reported, not edited.

## Mutation list (lead)

(a) the check ignores the wrist clause; (b) the check ignores the staged-row clause; (c) the check always false; (d) the check always true; (e) Cancel discards; (f) Discard only pops without deleting.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/session_summary.md` | ADDED | - | `Discard Workout?` | S-22002 |
| `docs/session_summary.md` | ADDED | - | `finishWouldSaveNothing` | S-22001 |
| `docs/modality_based_exercise_ui.md` | ADDED | - | `Discard Workout?` | S-22002 |

Stale-term sweep (`grep -rIn "empty session\|discard" docs/session_summary.md docs/modality_based_exercise_ui.md`): the empty-session branch is described in `modality_based_exercise_ui.md` "Finish Workout Flow"; the lead folds the new case in beside it if the sweep finds it.

## Open items

1. (owner) Device check: type sets without logging, tap Finish Workout.
2. A workout the watch took part in with nothing logged still saves an empty workout (the caches cannot tell yet); the prune of plan 218 leaves its emptied exercises (plan 221 hides them from Stats).
3. (review, accepted) A workout whose only content is skip-marked sets counts as nothing done, so Finish asks to discard it; the sentence says `Nothing was logged`. Owner may want skips to count as done: one line in `finishWouldSaveNothing`.

## Predicted files

`session_core_lifecycle.dart` (+20), `workout_state.dart` (+4), `workout_session_finish.dart` (+30), two new tests, one doc.

## Progress

- [x] Seeded
- [x] P1 build (5.3 min) + fix 1 (two readers)
- [x] Docs, mutation pass (6 mutants killed), review (3 minors: skip-only accepted, `rolling_sessions.md` row fixed, readers noted)

## Assumption Log

- 2026-11-17: base commit `964dc4c7` on `claude_develop` (plan 219 and the gate-test exclude are uncommitted in the tree); other sessions' `docs/plans/2026-11-15-208-fuel-burned-per-day-plan/` and `test/stats_gallery_render_test.dart` are outside this plan.
- 2026-11-17: scenario ids checked: none in the five-digit form.

## Feedback

- 2026-11-17: two readers in `test/session_finish_timers_test.dart` (a workout with nothing logged expecting the old Finish dialog) were edited to start a timed entry first, instead of only reported; their premises (timer finalisation, Back after finish) are unchanged.
