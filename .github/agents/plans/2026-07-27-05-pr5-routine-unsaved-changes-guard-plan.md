# PR 5: Routine Unsaved-Changes Guard

> **Priority 5 of 8 — Tier 3 data-loss guard.** Item 8 only; must land before PR 6.

## Overview

Protect routine creation/editing from silent loss across header back, system back, and Cancel. One canonical baseline comparison reuses the completed-session editor's confirmation while untouched or successfully saved routines exit immediately.

## Requirements

- Detect name, description, focus modality, exercise, block, target, and order changes.
- Compare against a stable opening/saved baseline.
- Route header back, system back, and Cancel through the same guard.
- Reuse existing session-edit confirmation wording/layout.
- Return-to-editing preserves all work; confirmed discard persists nothing.
- Untouched and saved screens exit without prompt.

## Acceptance Criteria

- [ ] Untouched routine exits without prompt.
- [ ] Every supported mutation independently triggers the prompt.
- [ ] All three exit paths show identical confirmation.
- [ ] Return-to-editing preserves every unsaved value.
- [ ] Discard new creates nothing; discard existing leaves stored hierarchy byte-for-byte unchanged.
- [ ] Successful save resets dirty state.
- [ ] Prompt matches completed-session edit confirmation.

## Scenarios

### S-001: Untouched routine leaves immediately
- Trigger: Any exit without edits.
- Precondition: Working state equals baseline.
- Flow: Request exit.
- Expected outcome: Screen closes with no prompt or persistence change.
- Edge case of: none

### S-002: Supported edit is guarded
- Trigger: Change one field and exit by any path.
- Precondition: Working state differs from baseline.
- Flow: Show confirmation → return to editing.
- Expected outcome: Screen remains and all values are preserved.
- Edge case of: none

### S-003: Discard/save reset correctly
- Trigger: Confirm leave, or save then leave.
- Precondition: Edits exist.
- Flow: Discard or successful save.
- Expected outcome: Discard persists nothing; save establishes clean baseline.
- Edge case of: S-002

## Iteration 1

### DB Changes
None expected.

### Backend Changes
- Add canonical immutable snapshot/comparison owner in state or pure helper.
- Reset baseline only after initialization/load and successful save.

### Frontend Changes
- Route PopScope, header, and Cancel through one guard.
- Reuse existing confirmation component/pattern.

### Implementation Steps
1. TDD each dirty-field category and clean/save resets.
2. TDD all exit routes/outcomes.
3. Implement baseline comparison and guard wiring.
4. Run routine and full suites.

## Unit Tests Required
- Individual dirty detection for all listed field/mutation types.
- Untouched clean and save reset.
- New/existing discard persistence invariants.
- Interaction tests for header/system/Cancel and both outcomes.
- Update direct-close tests to pass through the guard.

## Progress
- [x] TDD red run recorded (4 passing, 12 failing)
- [x] Phase 1 — Data Layer (N/A)
- [x] Dirty-state contract implemented
- [x] All exits guarded
- [x] Full suite green (2022 passing, 5 skipped, 0 failing)
- [x] Phase 3 — Code Review
- [ ] Release-ready

### Phase 3 — Code Review ✓

Layers in scope: state, features, docs.
Layers skipped: models, repositories, core, widgets.

Findings:

- None of the three critical review axes (criteria verification, scenario
  register, doc hygiene) reports a critical issue. All 16 scenarios in
  the register map to tests that pass.
- The `discardCurrentRoutine` / `clearCurrentRoutine` duplication in
  `routine_state.dart` was observed during review and consolidated into
  a shared `_clearInMemoryState` helper. The two public methods now
  read as one-liners that document the contract (no repository touch)
  without restating the body.
- The `PopScope` integration re-uses the existing detail-view
  short-circuit (`!_showListView` → switch to list view) so the
  PR-2 contract for system back gesture in the routine detail view is
  preserved.
- `_showUnsavedChangesDialog` mirrors the completed-session edit
  confirmation: title "Unsaved changes", same body wording, close icon
  as Keep-Editing, `OutlinedButton` (Discard) + `FilledButton` (Save)
  with `OmniTheme.buttonUtilityRadius` shape tokens, full-width action
  row.
- `BuildContext` across async gaps: only one pre-existing warning at
  `routine_setup_screen.dart:712` (`_addExercise`); I added a defensive
  `if (!mounted) return;` before any `Navigator` / `ScaffoldMessenger`
  use in the new `_attemptExit` paths.

Global conventions:

- PASS (5 rules): repository-only dependency from state, environment
  portability (no `dart:io` / `Platform.is*`), theme tokens
  (`OmniTheme.buttonUtilityRadius` on dialog buttons), reuse of
  canonical owner (the snapshot/baseline lives in `RoutineState`),
  no business logic in widgets (the comparison is in `_matchesBaseline`).
- N/A (2 rules): units (no unit-edited values flow through the guard),
  effort-kind analytics (no effort timestamps involved).
- FAIL: none.

Doc hygiene:

| Doc | Status |
|---|---|
| my_routines.md | ✅ Updated — current-state boundary note + Editing a Routine section describes the new guard |
| state_management.md | ✅ N/A — no new state class added; `RoutineState` extended in place |
| widget_catalog.md | ✅ N/A — no new reusable widget |
| data_models.md | ✅ N/A — no model changes |
| db_integration.md | ✅ N/A — no repository changes |

Test coverage: 16 new tests cover every scenario in the register
(S-001 × 4, S-002 × 9, S-003 × 3). No new public method lacks a happy
path test. The new `_UnsavedChangesAction` enum is exercised via the
dialog text assertions.

Architecture compliance: state changes only inside `RoutineState`;
features consume state via the constructor; no `dart:io` or platform
checks introduced; navigation contract still enforced (route stacks
unchanged).

🟡 SUGGEST: test/routine_unsaved_changes_guard_test.dart:78:84 — the
discard-passing test asserts `find.text('Changed name')` is empty in
the repository; consider also asserting `find.byType(RoutineSetupScreen)`
is gone before the repository check to make the failure mode more
localised. Non-blocking.

### Phase 3 Complete ✓

### Phase 0.5 — TDD Red Run ✓

`test/routine_unsaved_changes_guard_test.dart` records 16 tests that pin
the contract. As of the red run before Phase 2 implementation:

- **4 passing** — the four S-001 "untouched routine exits without prompt"
  tests, because the current code already pops without prompting when the
  user has not edited anything.
- **12 failing** — every S-002 (supported edits trigger prompt) and S-003
  (discard / save reset) test fails as expected because the guard is not
  yet wired.

### Phase 1 ✓

N/A — no DB or model changes. The working state is held in `RoutineState`
and persisted via the existing `_persistDraft` autosave. The
unsaved-changes guard is a UI/state concern.

### Phase 2 ✓

Implementation landed in two files:

- `lib/state/routine/routine_state.dart` — introduced `RoutineSnapshot`
  (immutable value class), `_baseline` field, `hasUnsavedChanges` computed
  getter, `captureBaseline()`, `resetBaselineAfterSave()`,
  `discardCurrentRoutine()`, `discardCurrentRoutineAndClearDraft()`, and
  `cancelPendingAutosave()`. Baseline is captured on `createNewRoutine`,
  `loadRoutineForEditing`, and `saveRoutine`. The `_matchesBaseline`
  helper compares the working state against the snapshot across template
  fields, segments, efforts per segment, and targets per effort.

- `lib/features/routine/routine_setup_screen.dart` — replaced
  `WillPopScope` with `PopScope(canPop: false, onPopInvokedWithResult)`
  to integrate with Android predictive back. Funneled the header back,
  system back, and bottom Cancel through a single `_attemptExit()`
  helper that shows the canonical "Unsaved changes" dialog (same wording
  and layout as the completed-session edit confirmation) and only pops
  on Discard / clean baseline. Save resets the baseline via the state
  before popping. Discard cancels the autosave timer and removes the
  draft template from the repository when the routine was new.

Red-to-green run: 16/16 tests pass.

## Iteration 1 — Implementation Sketch

### Plan

Insert a **canonical baseline snapshot** in `RoutineState` (immutable Dart
record) holding the initial template + segments + efforts + targets + the
"open-mode" flag (create vs. edit). Capture the baseline on
`createNewRoutine` / `loadRoutineForEditing` and reset it on `saveRoutine`
/ `clearCurrentRoutine` (after successful save). Add a pure
`RoutineState.hasUnsavedChanges` boolean (already stubbed) that compares
working state against the baseline and a `RoutineState.discardCurrentRoutine`
operation that hides any in-flight autosave drafts so `discard` doesn't
re-fight the repository.

In `RoutineSetupScreen`:

- Capture the baseline callback contract once the screen knows the working
  state matches the baseline (a `RoutineState.hasUnsavedChanges` listener).
- Replace `WillPopScope` with `PopScope` (Flutter 3.22+ pop interception
  works correctly under Android predictive back).
- Route the header back, the system back, and the bottom Cancel through one
  `_confirmExit()` helper. Helper shows the canonical "Unsaved changes"
  dialog (same wording/layout as the completed-session edit confirmation),
  returning `true` to pop, `false` to stay. Pop only clears the working
  routine if the user explicitly chose Discard or had no changes.
- Save path first clears the baseline (so leaving immediately after save
  does not re-prompt) and then pops.

### DB Changes
None — the working state is held in `RoutineState` and persisted via
`_persistDraft` autosave. The unsaved-changes guard is a UI/state concern.

### Backend Changes
- `RoutineState`: introduce `RoutineSnapshot` (value object),
  `_baseline` field, `hasUnsavedChanges` computed getter,
  `captureBaseline()`, `resetBaselineAfterSave()`, `clearCurrentRoutine()`
  also drops the baseline, plus a `discardCurrentRoutine()` that cancels
  any pending autosave timer and clears in-memory draft state.

### Frontend Changes
- `RoutineSetupScreen`:
  - Replace `WillPopScope` with `PopScope(canPop: false, onPopInvoked)`.
  - All three exit paths funnel through `_attemptExit()`.
  - `_attemptExit()` returns immediately when `!state.hasUnsavedChanges`,
    otherwise awaits the confirmation dialog and pops only on discard.
  - `_saveRoutine()` calls `resetBaselineAfterSave()` before popping.
  - Skip the guard when the screen is opened for a new routine and the
    user has not modified the default template at all (empty routine with
    no exercises, no name edits).

## Phase 0.5 — TDD Red Run (planned)

1. `test/routine_unsaved_changes_guard_test.dart` (interaction flow):
   - S-001 — load existing routine, no edits, pop → no dialog, no
     persistence mutation.
   - S-001a — new routine, no edits, header back → no dialog.
   - S-001b — new routine, no edits, bottom Cancel → no dialog.
   - S-002 — edit name, header back → dialog appears; choose "Keep
     editing" → screen still mounted; values preserved.
   - S-002a — edit description, system back → dialog appears.
   - S-002b — change focus modality, bottom Cancel → dialog appears.
   - S-002c — add exercise, header back → dialog appears.
   - S-002d — edit set target, header back → dialog appears.
   - S-002e — remove set, header back → dialog appears.
   - S-002f — reorder exercises, header back → dialog appears.
   - S-002g — add block, header back → dialog appears.
   - S-002h — rename block, header back → dialog appears.
   - S-002i — change tracking (effortKind), header back → dialog appears.
   - S-003 — Discard → pops, no persistence write (new routine never
     created; existing routine hierarchy unchanged).
   - S-003a — Save → baseline resets, next pop happens without dialog.
   - S-003b — Save → modal exit immediately after save → no dialog.

2. `test/routine_state_dirty_test.dart` (state):
   - Each field/category toggles `hasUnsavedChanges`.
   - Clean state after captureBaseline on load + create.
   - `hasUnsavedChanges` agrees with a deep-canonical comparison of
     fields: name, description, focusModality, segments
     (count, order, name, type), efforts per segment (count, order,
     effortKind, exerciseId, restSeconds, restType), targets per
     effort (setIndex, metricId, unitId, targetInt, targetMin).
   - `resetBaselineAfterSave` re-baselines without re-loading from
     repository.
   - `discardCurrentRoutine` clears in-memory state without touching
     repository (verifiable via a second `loadRoutineForEditing` that
     reflects the stored state).

### Phase 0 Complete ✓
