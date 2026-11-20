# Evidence — plan 279: Save as Routine opens the routine editor

One section per phase. Test counts are the lead's stated suite lines; mutation proof is the
lead's, not re-run here.

## P1a — draft block model + builder + Mock group

Files changed:

- `lib/core/models/session_summary.dart` — `SessionTemplateBlock`; `SessionTemplateDraft.blocks`
  (required list; the exercises-only shorthand wraps one `Main Block`)
- `lib/state/workout/session_summary_builder.dart` — `_targetsForEffort` extracted;
  `buildTemplateDraftBlocks(session, blocks)`: blocks and loose efforts in displayed top-level
  order, efforts inside a block by `blockOrderIndex`, loose runs named `Main Block` /
  `Main Block 2`, empty session blocks left out, an orphan `blockId` counts as loose (S-27916,
  synthetic fixture — no live writer produces one, D-27909)

Test files:

- `test/save_as_routine_blocks_test.dart` — 31 tests total across the file
  (`Mock — save-as-routine draft blocks` and `Hive — save-as-routine draft blocks`:
  S-27901..S-27906, S-27915..S-27917 plus lettered variants) — green

## P1b — state plumbing + RoutineState + Hive group

Files changed:

- `lib/state/workout/session_core.dart` — `buildTemplateDraftBlocks` passthrough
- `lib/state/workout/workout_state.dart` — `buildTemplateDraftBlocks()` passthrough;
  `buildTemplateDraftExercises()` stays byte-equal (flat view)
- `lib/state/routine/routine_state.dart` — `createRoutineFromSessionDraft(SessionTemplateDraft)`:
  one `TemplateSegment` per draft block, efforts/targets via `_newId`, then `captureBaseline()`;
  writes nothing (the editor's Save writes)

Test files:

- `test/save_as_routine_blocks_test.dart` — Hive group read-back (`S-27901h the saved fixture
  reads back through loadHistoricalSession with the same shape`) and
  `S-27902b the flat exercises getter stays the blocks flattened, and the exercises-only
  shorthand makes one Main Block` — green

## P2a — editor opened from a session draft

Files changed:

- `lib/features/routine/routine_setup_screen.dart` — optional `fromSessionDraft`;
  `_loadRoutine` third branch calls `createRoutineFromSessionDraft` and fills name + focus
  modality; `_showUnsavedChangesDialog` body names the summary
  (`You have unsaved edits. Discard them to return to the summary.`) when the draft is set

## P2b — editor-from-session tests

Test files:

- `test/routine_setup_from_session_test.dart` — 7 tests (group
  `Plan 279 — the editor opened from a session draft`: S-27907, S-27908, S-27909, S-27911,
  S-27912, S-27910 x2) — green

## P3a — summary screen pushes the editor; dead path removed

Files changed:

- `lib/features/session/session_summary_screen.dart` — `case 'save'` pushes `RoutineSetupScreen`
  with the draft built at tap time (`_openRoutineEditorFromSession`);
  `_openSaveAsRoutineSheet` and `_draftExercises` deleted
- `lib/core/services/session_summary_service.dart` — `saveRoutineFromDraft` deleted
- `test/services_test.dart` — `saveRoutineFromDraft` test group deleted
- the 3 sheet test files deleted/rewritten (`test/save_as_routine_labels_test.dart` keeps
  `S-25802 effortKindLabel maps the four kinds and leaves others`)

## P3b — summary flow tests

Test files:

- `test/save_as_routine_flow_test.dart` — 7 tests (S-27910, S-27910b, S-27910c, S-27907c x2,
  S-27913, S-27914) — green
- regressions: `test/state_test.dart` (S-1311..S-1315 flat-draft group) and the summary test
  files — green

## Mutation proof (by the lead)

40 one-line mutants, all killed except two named equivalent ones:

1. `topOf` ordering by `orderIndex` alone — equivalent: `createEffort` normalizes `orderIndex`
   to `topLevelOrderIndex` for loose efforts, so no writer can make the two differ.
2. one cosmetic spacing line.

## Review notes (lead)

- `test/header_standardization_test.dart:755` (the "overflow menu items are accessible" case) stays: it only checks the three menu labels and never opens the removed sheet.
- `_openRoutineEditorFromSession` tests `blocks.isEmpty` rather than the plan's `draft.exercises.isEmpty`; equivalent because the builder never emits an empty block (S-27914 pins the branch).
