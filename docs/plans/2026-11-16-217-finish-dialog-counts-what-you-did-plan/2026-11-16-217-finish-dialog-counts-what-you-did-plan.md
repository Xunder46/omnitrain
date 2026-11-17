# Plan 217 — The Finish dialog counts the exercises you did

Series: Stats pre-launch review, 157a Open item 1 (index `docs/plans/2026-11-13-157-stats-what-counts-series.md`, "Owner decisions still open"). Phone only (`lib/state/workout`, `lib/features/session`), one builder run for production plus state tests, one for the screen test, then docs. Status: BUILT, reviewed (APPROVE WITH FIXES: two minors, recorded below), verified, COMMITTED.

## Goal and acceptance

Finish drops every planned set nobody logged (plan 157a), and a set exercise left with no set disappears. The confirmation still says `You have completed: • N exercises` with N counting every exercise in the session, including ones where nothing was logged. So a user who did one of four planned lifts reads "4 exercises", then lands on a summary that shows one. After this change N counts only the exercises the user did.

Acceptance: S-21701..S-21704 green, the ones marked "fails without" red at the base commit; the readers listed below green and unchanged; `flutter analyze` at baseline (181, 0 errors); full suite no new red.

## What the user sees

- The Finish dialog's first bullet counts exercises done: a lift with at least one set the user logged, or a timed, drill or round exercise that was started. An exercise with only planned sets, or only a set marked skipped, does not count. The word is the same (`exercise` / `exercises`).
- If nothing was done the bullet reads `• 0 exercises` (the dialog still shows; Finish then saves the session as today).
- Unchanged: the title, `Elapsed time`, the Finish and Cancel buttons, what Finish stores, the summary.
- To SEE it: a routine session with three lifts, log one set of one lift, tap Finish Workout.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-1 | The count comes from the state, not the screen, so the rule lives beside the drop it must agree with: a new `SessionCore.completedExerciseCount()` (extension `SessionCoreLifecycleMethods`, directly after `_dropUnloggedSets`), forwarded by `WorkoutState`. It reads the in-memory caches (`_efforts`, `_observations`, `_timerManager`), the same data the screen shows; the store re-read of the drop (D-9 of 157a) is not repeated for a label. | `session_core_lifecycle.dart:98-143` |
| D-2 | A `set` effort counts when at least one of its set groups has a rest at position + 1 (the screen's own "logged" rule, 157a D-2). A skip-marked set does not make the exercise count: it is kept for the record (157a D-3) but nothing was done. The one-line rule `marked.contains(position + 1)` is shared with the drop by a private helper `_setIsLogged(Set<int> marked, int position)` so the two cannot drift; `_dropUnloggedSets` keeps its skip clause beside it. | 157a D-2, D-3 |
| D-3 | A `timed`, `drill` or `round` effort counts when any of its instances is not `notStarted` (running, paused or finished). A never-started interval or round does not. (Finish persists a running timed entry on purpose, so started work counts.) | `TimedState`, `RoundState` (`models.dart:1077,1278`), `endSession` `persistActiveTimedEntries` |
| D-4 | The dialog line uses `widget.workoutState.completedExerciseCount()` instead of `_exercises.length` (`workout_session_finish.dart:40`). The `hasExercises` empty-session check above it is unchanged. | `workout_session_finish.dart:10-17,40` |
| D-5 | Not done here (owner call, Open item 1): a warning line for planned sets that Finish will drop. | 157a Open item 2 |
| D-6 | A session the watch had a part in keeps its planned sets (157a D-11) but the dialog still counts only done exercises: the word is "completed". | 157a D-11 |

## Scenarios

Fixtures follow `test/finish_drops_unlogged_sets_test.dart` (`harnessFactories`, `openLiveSession`, `seedAndAdd`, `fillSet`, `logSet`) for the state tests; the screen test copies the harness of `test/finish_drops_unlogged_sets_screen_test.dart` (Mock only).

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-21701 | Live session, exercise X with 3 sets (set 0 filled and logged, 2 placeholders), exercise Y with 3 untouched placeholders. `state.completedExerciseCount()`. Then `logSet` on Y's set 1 → 2. | 1, then 2. Mock and Hive. | there is no method (compile failure) |
| S-21702 | One exercise whose only set is skip-marked (`markSetSkipped`), no rest. A second exercise with one logged set. | 1 (the skipped-only exercise does not count). Mock and Hive. | the method does not exist; kills the mutation that counts a skip-marked set |
| S-21703 | A `timed` exercise never started and a `round` exercise never started: 0. `startTimedEntry(timedId, 0)` → 1. `startRound(roundId, 0)` → 2. | 0, 1, 2. Mock and Hive. | the method does not exist; kills the mutation that counts every non-set effort |
| S-21704 | Screen (Mock only), a live session with exercise X (one logged set, plus one planned set) and exercise Y (planned sets only). Tap `Finish Workout`. | the dialog shows `• 1 exercise`; cancel, log a set of Y, tap Finish Workout again: `• 2 exercises`. Never `• 2 exercise` at the first open. | the dialog counts `_exercises.length` and reads `• 2 exercises` at the first open |

## Input-reality checklist

1. Writers and units: no stored value; the count is derived from the caches at the moment the dialog opens.
2. Lifecycle: computed when Finish is tapped; the dialog is modal so the data does not move while it is open (a wrist rest arriving then is the one gap: the screen would count it a moment later, same as every other label).
3. Settings: none read.
4. Time: none.
5. Cost: one pass over the session's efforts, no store read.
6. Words: unchanged wording; only the number changes. `0 exercises` is plain.
7. Slot competition: n/a.

## Phases

1. **P1 builder-app**, scope `lib/state/workout/session_core_lifecycle.dart`, `lib/state/workout/session_core.dart`, `lib/state/workout/workout_state.dart`, `test/finish_completed_exercise_count_test.dart` (new): the exact production code in the brief and S-21701..S-21703 (Mock and Hive). No full suite.
2. **P2 builder-app**, scope `lib/features/session/workout_session_finish.dart`, `test/finish_completed_exercise_count_screen_test.dart` (new): the one-line screen change and S-21704. Separate run (playbook (z)).
3. **P3 lead**: docs, mutation pass, `crew-reviewer`, full suite.

## Readers (existing tests that touch the drop or the dialog)

`test/finish_drops_unlogged_sets_test.dart`, `test/finish_drops_unlogged_sets_screen_test.dart`, `test/session_finish_timers_test.dart`, `test/watch_session_finish_test.dart`, `test/session_message_test.dart` (the `_dropUnloggedSets` helper is touched by the shared rule). A test that reads the dialog's count text: none found (`grep "exercises'" test` over the dialog), `test/widgets/confirmation_dialog_test.dart:420,447` builds its own copy of the body.

## Mutation list (lead)

(a) the count ignores `_setIsLogged` and counts every set effort; (b) the count also counts a skip-marked set; (c) timed/round efforts always count; (d) the rule's position is off by one (`marked.contains(position)`), which the existing drop tests also kill; (e) the dialog still reads `_exercises.length`; (f) the plural rule is inverted.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/rest_tracking.md` | ADDED | - | `completedExerciseCount` | S-21701, S-21702, S-21703 |
| `docs/session_summary.md` | ADDED | - | counts only the exercises the user did | S-21704 |

Stale-term sweep (`grep -rIniE "You have completed|Finish confirmation|finish dialog" docs`, minus plans/history/releases): no doc describes the dialog's count today; `rest_tracking.md:126` and `session_summary.md:19` are the two paragraphs the new sentences follow.

## Open items

1. (owner) A warning in the dialog for planned sets Finish will drop (157a Open item 2). Needs a product call: every routine session with skipped sets would show it. Not done.
2. The count is read from the caches, so a wrist-logged set whose rest has not reached them yet is counted a moment late (the drop itself re-reads the store).
3. (owner) A device check: a routine session with three lifts, log one set of one lift, tap Finish Workout; the dialog says `1 exercise`, the summary shows one.

4. (review minor, not fixed) `createNewSession` does not clear the previous session's efforts; the Finish count (like the drop and the screen) could read a finished-but-not-cleared session's exercises if a routine session starts without `clearSession()` after the wrist's own end (`my_routines_screen.dart:196`). Existing exposure; needs its own look.
5. (review minor, not fixed) A kind other than `set`/`round` is read as timed; no writer produces any other (`interval`, `amrap`, `note` exist only as block types).

## Predicted files

`session_core_lifecycle.dart` (+30), `session_core.dart` (+3), `workout_state.dart` (+3), `workout_session_finish.dart` (+3), two new test files, two docs.

## Progress

- [x] Seeded (scout: the dialog, the drop, the logged rule, the timed/round states)
- [x] P1 state + tests (2.2 min)
- [x] P2 screen + test (1.7 min)
- [x] Docs, mutation pass (7 mutants: all killed), review (APPROVE WITH FIXES, 0 major), full suite (+7797 ~4: All tests passed!)

## Assumption Log

- 2026-11-16: base commit `7811658c` on `claude_develop`; other sessions' `docs/plans/2026-11-15-208-fuel-burned-per-day-plan/` and `test/stats_gallery_render_test.dart` are outside this plan.
- 2026-11-16: scenario ids S-217xx; grep over `test`, `docs`, `lib`, `watch` found none in the five-digit form.
- 2026-11-16: the count rule (a skip-marked-only exercise does not count; a started timed or round does) and not adding a warning are the lead's defaults (the owner said to proceed and explain defaults).

## Feedback

(none yet)
