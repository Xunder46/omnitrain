# Plan 240 — An empty routine cannot be saved, and a routine that cannot start never costs the running workout

Series: nutrition/calendar/summary pre-launch review (2026-11-16), item "empty routine can be saved and then never starts". Phone only (`lib/features/routine/routine_setup_screen.dart`, `lib/features/routine/my_routines_screen.dart`, `lib/features/calendar/day_session_list_screen.dart`). The production edits are small and exact (lead applies them), one builder run writes the tests and adapts one reader, then docs. Status: COMMITTED (built, mutation-checked (5 of 5 killed), docs applied; full suite +7971 ~4 green.

## Goal and acceptance

Two defects in one chain:

1. The routine editor's Save accepts a routine with a name and NO exercise (`_saveRoutine` checks only the name, `routine_setup_screen.dart:956`). Such a routine can never start: `RoutineSessionService.buildSessionFromTemplate` throws "Template has no segments/exercises" (`routine_session_service.dart:33,88`) and the user only sees "Could not start the routine. Try again."
2. Worse, both start paths (My Routines Start, and a planned session on the day list) DISCARD the running workout first (plan 230) and build the manifest afterwards. Starting an empty routine over a running workout therefore confirms "Start New", deletes the running workout, then fails: the user loses the workout and gets nothing.

After this change an empty routine is not saved ("Add at least one exercise before saving"), and both start paths build the manifest BEFORE discarding, so any routine that cannot start (an empty one saved earlier, a deleted exercise) leaves the running workout untouched.

Behaviour call (stated, not asked): refusing to save a routine with no exercise is the conservative reading of "a routine is a list of exercises"; a half-built routine is still kept by the editor's own draft autosave and the unsaved-changes guard.

Acceptance: S-24001..S-24005 green, those marked "fails without" red at the base commit; readers green or adapted/reported; `flutter analyze` at baseline (181, 0 errors); full suite no new red.

## What the user sees

- Tap Save on a routine with a name but no exercise: a message "Add at least one exercise before saving"; the editor stays open and nothing is saved.
- Start a routine (from My Routines, or a planned session from the calendar) while a workout is running and confirm "Start New": if the routine cannot start, the running workout is still there, with the same "Could not start the routine. Try again." message. Today the workout is gone.
- Everything else is unchanged.
- To SEE it: with a workout running, plan an old empty routine (or use one saved before this change) and press Start: the running workout survives.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-1 | `_saveRoutine` (after the name check, before `saveRoutine()`): `if (widget.routineState.currentEfforts.isEmpty) { OmniMessage.show(context, 'Add at least one exercise before saving'); return; }`. | `routine_setup_screen.dart:956-962` |
| D-2 | `MyRoutinesScreen._startRoutine`: the `try` now starts with `buildSessionFromTemplate`, and `discardUnfinishedSession()` follows it inside the `try` (a failure of the build is caught by the existing `catch`, which shows the existing error message). | `my_routines_screen.dart:167-198` |
| D-3 | `DaySessionListScreen._tapPlanned`: inside the `try`, `final manifest = ps.routineTemplateId == null ? null : await widget.routineSessionService.buildSessionFromTemplate(ps.routineTemplateId!);` first, then `discardUnfinishedSession()`, then `if (manifest != null) { routine start } else { createNewSession(modality: ps.modality) }`. | `day_session_list_screen.dart:274-292` |
| D-4 | The Home Free/Routines/modality tiles start no routine manifest (a modality or free start cannot fail this way): unchanged. | `home_screen.dart:642,729,865` |
| D-5 | `buildSessionFromTemplate` keeps throwing for an empty template; the message text of the start error is unchanged. | `routine_session_service.dart` |

## Scenarios

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-24001 | Screen test, Mock (the harness of `test/start_new_really_discards_screen_test.dart`, S-23009): a running workout, plus a template that has NO segments (`repo.createTemplate` only). `MyRoutinesScreen`; tap the routine's Start (`routine-card-start`), confirm (`routine-start-new-confirm`). | the running workout is still stored (`repo.getSession(runningId)` not null) and still current (`workoutState.currentSession?.id == runningId`); the text `Could not start the routine. Try again.` is shown. | the base discards first, then fails |
| S-24002 | The same on the day list (the harness of S-23004..S-23005 in that file, `DaySessionListScreen`): a planned session for today whose `routineTemplateId` names a template with no segments; tap it, confirm (`day-session-new-start-confirm`). | the running workout is still stored and current; an error message shown (the one the screen already shows). | the base discards first |
| S-24003 | Screen test, Mock: `RoutineSetupScreen` for a new routine (the harness of `test/routine_unsaved_changes_guard_test.dart`: `_buildDeps`, `_buildScreen`, `_tapSaveButton`); enter the name `Empty`; tap Save. | the text `Add at least one exercise before saving` is shown; `find.byType(RoutineSetupScreen)` is still there; `repo.getTemplates()` has no template named `Empty`. | the base saves it and pops |
| S-24004 | Control (passes both ways on purpose): the S-23009 scenario with a VALID routine (copy `seedPlannedSessionToday`'s template with a segment and an effort): running workout + confirm Start New. | the old session row is gone, a new current session exists. | passes both ways (mutation: the manifest build placed after a discard that throws elsewhere) |
| S-24005 | Control (passes both ways on purpose): the routine editor with ONE exercise added (use the adder the existing unsaved-changes tests use) and a name; tap Save. | `Routine saved successfully` is shown and the editor pops; the template exists. | passes both ways (mutation: the guard rejects every save) |

## Input-reality checklist

1. Writers and units: `RoutineState.saveRoutine` is the only writer of a template; the guard counts `currentEfforts`, the same list the editor renders. No stored data changes; routines saved before this change may be empty and are covered by D-2/D-3.
2. Lifecycle: an editor reopened on an empty routine can add an exercise and save; the autosave draft (plan on drafts) is unaffected by the guard (it does not call `_saveRoutine`).
3. Settings changing while open: none.
4. Time: none.
5. Cost: the manifest is built once, as before, just earlier.
6. Words: one new message, `Add at least one exercise before saving`, in the editor's existing message style (sentence case, no full stop, like `Please enter a routine name`).
7. Slot competition: with a running workout and a failed routine start, the shared slot is untouched (the discard never runs), so the Home resume tile and a later Back-to-workout still work.

## Phases

1. **P1 lead**: the three production edits (already applied) and one doc edit.
2. **P2 builder-app**, scope `test/empty_routine_cannot_cost_the_running_workout_test.dart` (new), `test/routine_unsaved_changes_guard_test.dart` (reader: the one test that saves a name-only routine now adds an exercise first). No full suite.
3. **P3 lead**: mutation pass, docs, full suite.

## Readers

`test/routine_unsaved_changes_guard_test.dart` 'save resets baseline so immediate exit does not prompt' saves a routine with only a name (premise: empty save allowed); it must add an exercise before the Save tap (use the existing helper or `RoutineState` call other tests in that file use to add an effort). Every file of `grep -rlE "RoutineSetupScreen|MyRoutinesScreen|DaySessionListScreen" test` (25 files) otherwise green, as run by the lead before the build.

## Mutation list (lead)

(a) the save guard removed (S-24003); (b) the My Routines discard moved back before the build (S-24001); (c) the day-list discard moved back before the build (S-24002); (d) the guard rejects every save (S-24005); (e) the day-list manifest build skipped for routines (a routine plan starts a plain session: S-24004 control).

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/my_routines.md` | ADDED | - | The start paths build the manifest before discarding a running workout, and the editor refuses to save a routine with no exercise (plan 240) | S-24001, S-24003 |
| `docs/modality_based_exercise_ui.md` | ADDED | - | A routine that cannot start (an empty one) leaves the running workout untouched | S-24001, S-24002 |

Stale-term sweep: `grep -rIn "has no exercises\|Start New" docs` outside plans/history/releases: the two rows above; no other claim contradicts.

## Open items

1. (owner) With a workout running, press Start on a routine that cannot start: the workout is still there.
2. Routines saved empty before this change stay in the list; a clean-up (delete or mark) is a product call, not in this plan.

## Predicted files

`routine_setup_screen.dart` (+6), `my_routines_screen.dart` (+6 -3), `day_session_list_screen.dart` (+8 -4), one new test file (~230), one reader test, two docs.

## Progress

- [x] Seeded
- [x] Production edits (lead)
- [x] P2 tests
- [x] Mutation pass, docs
- [x] Full suite (+7971 ~4 green, analyze 181)

## Assumption Log

- 2026-11-18: base commit in `.work/crew/2026-11-18-240/base.txt` (4b91336b); another session's files (stats gallery test, plan 208) are outside this plan.
- 2026-11-18: ids S-240xx: none found.
- 2026-11-18: before the build the lead ran the 25 routine/day-list screen test files: 675 green, 1 red (the reader above).

## Feedback

(none yet)
