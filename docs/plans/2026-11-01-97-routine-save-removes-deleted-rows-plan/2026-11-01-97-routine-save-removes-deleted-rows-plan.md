# Plan 97 — Saving a routine removes what the user deleted

Status: seeded, S size, one phase. Base commit: see `.work/2026-11-01-97-routine-save/base.txt`.

## Goal and acceptance

Owner report: delete an exercise from a routine, save, see "Routine saved successfully"; reopen the routine and the
exercise is back.

Acceptance (what the user sees):

- A: after deleting an exercise and saving, reopening the routine shows it without that exercise.
- B: deleting a whole block (segment) and saving removes the block and its exercises.
- C: nothing else about saving changes (new routines, added exercises, edited targets save as before; autosave drafts
  for other screens behave as before).

## Root cause (observed)

`RoutineSetupScreen` turns autosave off (`routine_setup_screen.dart:88`), so `RoutineState.saveRoutine()`
(`routine_state.dart:219`) is the only write. It upserts the template, every current segment, effort and target
(`createTemplate*`) but never deletes rows that are in the repository and no longer in memory.
`_persistDraft()` (`routine_state.dart:1006`) already has the pruning loops (segments, efforts, targets) and so
deletes correctly, but it only runs from the autosave timer, which is disabled in the editor.

Repro (lead, on the old code): `test/routine_save_removes_deleted_rows_test.dart`, S-R1, S-R2, S-R3, all red:
S-R1 effort list still has 2 ids, S-R2 `getTemplateTargets(dropId)` has 1, S-R3 `getTemplateEfforts(extraId)` has 1.

## Decision Ledger

- D-1: one shared private method `_syncRowsToRepository()` in `routine_state.dart` holds the segment/effort/target
  sync with pruning (the body of `_persistDraft` from `final existingSegments = ...` to the end of the loops). Both
  `_persistDraft` and `saveRoutine` call it, so the two cannot drift again. The helper does not catch; each caller
  keeps its own try/catch (`saveRoutine` sets `_setError`, `_persistDraft` swallows).
- D-2: `saveRoutine` keeps its early return (`_currentTemplate == null || _currentSegments.isEmpty`), its
  `createTemplate` call, its local-cache add, `captureBaseline()` and loading flags unchanged. Only the segment /
  effort / target writes are replaced by the helper call.
- D-3: `getEffortTargets(effort.id)` reads `_currentTargets` filtered by effort id, which is the same set the old
  `saveRoutine` loop wrote, so replacing its "save all targets" loop loses nothing.
- D-4: no change to the repository interface, `HiveWorkoutRepository`, `MockWorkoutRepository`, the screen or the
  message text.

## Scenarios

| Id | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-R1 | routine with 2 efforts saved; reopen; remove one; save; reopen | 1 effort left | saveRoutine never deletes the effort row |
| S-R2 | removed effort had a reps target | `getTemplateTargets(removed)` empty | targets are not deleted |
| S-R3 | routine with an extra block holding one effort; remove the block; save; reopen | only the main block; `getTemplateEfforts(extraId)` empty | segment and its efforts are not deleted |

Existing readers of `saveRoutine` (must stay green): `test/state_test.dart`, `test/edge_case_test.dart`,
`test/routine_unsaved_changes_guard_test.dart`, `test/routine_detail_screen_test.dart`,
`test/data_tracking_fixes_test.dart`, `test/watch_routine_adoption_test.dart`, `test/watch_routine_round_trip_test.dart`.

## Phases

P1 — owner agent `crew-builder-app`, serial, one run.
Write scope: `lib/state/routine/routine_state.dart`, `docs/my_routines.md`.
Items: (1) extract `_syncRowsToRepository()`; (2) call it from `_persistDraft` and `saveRoutine`; (3) one docs sentence
in `docs/my_routines.md` near the CRUD row: saving removes rows the user deleted from the stored routine.
The test file already exists (lead-written, do not edit).

## Progress

- Repro written and red on the old code (lead).
