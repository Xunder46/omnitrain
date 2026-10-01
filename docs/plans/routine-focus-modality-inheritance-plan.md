# Feature: Routine Focus Modality Drives Add-Exercise Flow

## Overview
Today a routine's `Focus Modality` field is essentially decorative — it feeds a couple of display labels and nothing else. When you add an exercise, you're forced through a modality prompt every time, even though the routine already declared its focus. This fix makes `Focus Modality` behave the way a live session's modality already behaves: if the routine has a focus, new exercises inherit it silently and no prompt appears. The prompt only survives for "Mixed / Not set" routines, where there is genuinely nothing to inherit. The existing per-exercise override (`Change Tracking`) stays available for the occasional odd-exercise-out. Picker filtering is deliberately excluded — that's a separate, riskier change.

## Requirements
- When a routine's `Focus Modality` is set to a specific modality, adding an exercise must NOT show any modality-selection step. The exercise is added immediately with the modality's effort kind.
- When `Focus Modality` is "Mixed / Not set" (null), the modality picker is shown exactly as today.
- The per-exercise `Change Tracking` action must still open the modality picker and update only that exercise, regardless of focus.
- Changing `Focus Modality` after exercises exist must NOT retroactively alter already-added efforts' tracking. Only exercises added afterward inherit the new focus.
- The exercise picker must continue to show the full library regardless of focus modality (no filtering, no reordering, no sectioning).
- Cancelling the exercise picker must add no exercise and show no follow-up prompt, in both focus-set and Mixed routines.
- No new confirmation, toast, or interruption is introduced in place of the removed prompt.

## Acceptance Criteria
- [ ] Adding an exercise to a routine whose `Focus Modality` is set to a specific modality results in the exercise appearing in the routine with no modality prompt shown at any point.
- [ ] The tracking style and default targets of an exercise added under a set `Focus Modality` are identical to those produced when the same exercise is added to a live session of that same modality.
- [ ] Adding an exercise to a routine with `Focus Modality` = "Mixed / Not set" still shows the modality-selection step, unchanged from current behavior.
- [ ] The per-exercise `Change Tracking` action still opens the modality picker and updates only that exercise, in both focus-set and Mixed routines.
- [ ] Setting or changing a routine's `Focus Modality` after one or more exercises exist leaves every already-added exercise's tracking untouched; only exercises added afterward inherit the new focus.
- [ ] Cancelling the exercise picker adds no exercise and shows no follow-up prompt, in both focus-set and Mixed routines.
- [ ] The exercise picker shows the same full set of exercises regardless of `Focus Modality`.

## Scenarios

### S-001: Focus-set routine silently adopts modality for new exercise
- Trigger: User adds an exercise to a routine whose `Focus Modality` is set to a specific modality (e.g. `resistance_lifting`).
- Precondition: A routine exists in setup mode with `focusModality = 'resistance_lifting'`.
- Flow:
  1. User taps the block "+" icon (Add exercise to block).
  2. `ExercisePickerScreen` opens.
  3. User picks an exercise.
- Expected outcome:
  - The exercise is added immediately.
  - No `ModalityPickerDialog` is shown at any point.
  - The new effort's `effortKind` matches `ModalityConfig.forModality('resistance_lifting')!.effortKind` ('set').
- Edge case of: none

### S-002: Mixed / Not set routine still prompts for modality
- Trigger: User adds an exercise to a routine with `Focus Modality = null` (Mixed / Not set).
- Precondition: A routine exists in setup mode with `focusModality = null`.
- Flow:
  1. User taps the block "+" icon.
  2. `ExercisePickerScreen` opens.
  3. User picks an exercise.
  4. `ModalityPickerDialog` opens.
  5. User picks a modality (e.g. `sports`).
- Expected outcome:
  - The exercise is added with the picked modality's `effortKind` ('round' for `sports`).
  - The `ModalityPickerDialog` is shown between exercise pick and add, exactly as today.
- Edge case of: none

### S-003: Cancelling exercise picker does not show modality prompt
- Trigger: User opens the exercise picker and cancels (back / out).
- Precondition: A routine exists (either focus-set or Mixed).
- Flow:
  1. User taps the block "+" icon.
  2. `ExercisePickerScreen` opens.
  3. User dismisses the picker without selecting an exercise.
- Expected outcome:
  - No exercise is added.
  - No `ModalityPickerDialog` is shown.
  - The routine's exercise list is unchanged.
- Edge case of: S-001, S-002

### S-004: Changing Focus Modality does not retroactively alter existing efforts
- Trigger: User changes the routine's `Focus Modality` after one or more exercises are already added.
- Precondition:
  - A routine exists with `focusModality = 'resistance_lifting'`.
  - At least one exercise has been added under that focus and its `effortKind = 'set'`.
- Flow:
  1. User changes the `Focus Modality` dropdown to `sports`.
  2. User adds a new exercise (without changing the existing one).
- Expected outcome:
  - Existing efforts' `effortKind` is still `'set'`.
  - The newly added effort's `effortKind` is `'round'` (from `sports`).
  - The existing per-exercise `Change Tracking` action is still functional.
- Edge case of: S-001

### S-005: Per-exercise Change Tracking still works after focus inheritance
- Trigger: User taps `Change Tracking` on an exercise that was added under a focus modality.
- Precondition: A routine has `focusModality = 'resistance_lifting'` and an exercise with `effortKind = 'set'`.
- Flow:
  1. User taps the `Change Tracking` overflow action on the exercise card.
  2. `ModalityPickerDialog` opens.
  3. User picks a different modality (e.g. `isometric_stretching`).
- Expected outcome:
  - The exercise's `effortKind` updates to `'drill'` (from `isometric_stretching`).
  - The routine's `focusModality` is unchanged.
  - Other exercises in the routine are unchanged.
- Edge case of: S-001

### S-006: Exercise picker shows the full library regardless of focus
- Trigger: User opens the exercise picker from inside a focus-set routine.
- Precondition: A routine has `focusModality = 'sports'`.
- Flow:
  1. User taps the block "+" icon.
  2. `ExercisePickerScreen` opens.
- Expected outcome:
  - The full set of exercises is shown (no filtering, no reordering, no modality-specific sectioning).
  - The picker is identical to the one shown for a Mixed / Not set routine.
- Edge case of: none

## Iteration 1

### DB Changes
None. The `WorkoutTemplate.focusModality` field already exists, the in-memory `_currentTemplate` and persistence layer already round-trip it, and the UI's `Focus Modality` dropdown already writes to it. No new schema, no new models, no repository interface changes.

### Backend / State Changes
None. `RoutineState.addExerciseToRoutine(exercise, effortKind, segmentId: ...)` already accepts an explicit `effortKind` — we just need the caller (`routine_setup_screen.dart::_addExercise`) to compute it from `currentTemplate.focusModality` when set, instead of always running the picker flow. No state interface changes.

### Frontend Changes

#### `lib/features/routine/routine_setup_screen.dart`

The single behavioural change is inside `_addExercise` (currently lines ~691–727).

**Before** (current flow, always prompts):
```dart
void _addExercise(BuildContext context, String segmentId) async {
  if (widget.workoutState == null) return;

  // Step 1: Pick exercise
  final exercise = await OmniNavigator.push<Exercise>(
    context,
    (_) => ExercisePickerScreen(workoutState: widget.workoutState!),
  );

  if (exercise == null) return;

  _exerciseCache[exercise.id] = exercise;

  // Step 2: Pick modality using the shared picker.
  final modalityResult = await showDialog<(bool, String?)>(
    context: context,
    builder: (_) => const ModalityPickerDialog(),
  );

  if (modalityResult == null) return;

  final (_, pickedModality) = modalityResult;
  if (pickedModality == null) return;

  final effortKind =
      ModalityConfig.forModality(pickedModality)?.effortKind ?? 'set';

  await widget.routineState.addExerciseToRoutine(
    exercise,
    effortKind,
    segmentId: segmentId,
  );
  // ...
}
```

**After** (skip Step 2 when routine has a focus modality):
```dart
void _addExercise(BuildContext context, String segmentId) async {
  if (widget.workoutState == null) return;

  // Step 1: Pick exercise (picker shows full library regardless of focus)
  final exercise = await OmniNavigator.push<Exercise>(
    context,
    (_) => ExercisePickerScreen(workoutState: widget.workoutState!),
  );

  if (exercise == null) return;

  _exerciseCache[exercise.id] = exercise;

  // Step 2: Inherit the routine's focus modality if set, else prompt.
  final focusModality = widget.routineState.currentTemplate?.focusModality;
  String? effortKind;
  if (focusModality != null) {
    effortKind =
        ModalityConfig.forModality(focusModality)?.effortKind ?? 'set';
  } else {
    final modalityResult = await showDialog<(bool, String?)>(
      context: context,
      builder: (_) => const ModalityPickerDialog(),
    );
    if (modalityResult == null) return;
    final (_, pickedModality) = modalityResult;
    if (pickedModality == null) return;
    effortKind =
        ModalityConfig.forModality(pickedModality)?.effortKind ?? 'set';
  }

  await widget.routineState.addExerciseToRoutine(
    exercise,
    effortKind,
    segmentId: segmentId,
  );
  // ...
}
```

**Behavioural guarantees**:
- If `focusModality == null` → behaves exactly as today (S-002, S-003).
- If `focusModality` is a specific modality → Step 2 is skipped, exercise is added with the modality's `effortKind` (S-001, S-003).
- The picker still receives `widget.workoutState!` only (no `sessionModality`), preserving the full-library listing (S-006).
- `_changeTracking` is untouched, so per-exercise override still works (S-005).
- `Focus Modality` is read at the moment of add, so changing it after exercises exist only affects subsequent adds (S-004).

### Test Plan

Add the following tests to `test/screen_widget_test.dart` in the `RoutineSetupScreen` group:

1. **`'add exercise under focus modality skips modality picker (resistance)'`** (covers S-001)
   - Setup: routine with `focusModality = 'resistance_lifting'`, save, reload via `templateId`.
   - Action: tap block "+" icon, pick an exercise from the picker, confirm.
   - Assert: `find.byType(ModalityPickerDialog)` findsNothing, `routineState.currentEfforts.first.effortKind == 'set'`.

2. **`'add exercise under focus modality skips modality picker (sports)'`** (covers S-001 + S-002)
   - Same flow with `focusModality = 'sports'`.
   - Assert: `find.byType(ModalityPickerDialog)` findsNothing, `effortKind == 'round'`.

3. **`'add exercise to Mixed routine still shows modality picker'`** (covers S-002)
   - Setup: routine with `focusModality = null` (default), save, reload.
   - Action: tap block "+", pick an exercise.
   - Assert: `find.byType(ModalityPickerDialog)` findsOneWidget.

4. **`'cancelling exercise picker does not show modality picker in focus routine'`** (covers S-003)
   - Setup: routine with `focusModality = 'resistance_lifting'`.
   - Action: tap block "+", dismiss the picker without selecting.
   - Assert: no exercise added, `find.byType(ModalityPickerDialog)` findsNothing.

5. **`'cancelling exercise picker does not show modality picker in Mixed routine'`** (covers S-003)
   - Same as above with `focusModality = null`.

6. **`'changing focus modality does not retroactively change existing efforts'`** (covers S-004)
   - Setup: routine with `focusModality = 'resistance_lifting'`, add one exercise, save.
   - Action: change focus to `sports`, add a new exercise.
   - Assert: existing effort `effortKind == 'set'`, new effort `effortKind == 'round'`.

7. **Confirm/keep green** — `'tracking selection shows ModalityPickerDialog'` (already in `RoutineSetupScreen` group): drives `onChangeTracking` (override path), not add-exercise. Should still pass untouched.

8. **Audit `'block header plus icon triggers add-exercise flow'`** — currently asserts the picker opens, nothing more. Leave as-is; the new tests above provide the actual coverage of the modality step.

9. **Regression guard** — confirm `'uses focusModality override when provided'` in `test/services_test.dart` (line 909) still passes, since inherited modality now flows from routine building into started sessions.

## Progress
- [x] Phase 0 — write this plan
- [x] Phase 1 — verified no DB/model/repo changes needed
- [x] Phase 2.1 — write 6 new failing tests (red phase confirmed: 2 S-001 tests failed, 4 preserved-path tests passed)
- [x] Phase 2.2 — implement focus-modality inheritance in `_addExercise`
- [x] Phase 2.3 — run all 6 new tests + 2 audit regressions to green (6/6 + 4/4 audit + 1/1 services = green)
- [x] Phase 2.4 — run full `flutter test` to confirm no regressions (1510 passed, 5 skipped, 0 failed)
- [x] Phase 2.7 — doc hygiene (`my_routines.md` workflow, `widget_catalog.md` ModalityPickerDialog scope)
- [x] Phase 3 — code review

### Phase 0 Complete ✓
### Phase 1 Complete ✓ (no schema/model/repo changes required)
### Phase 2 Complete ✓
### Phase 3 Complete ✓

### Phase 0 Complete ✓
### Phase 1 Complete ✓ (no schema/model/repo changes required)
- [ ] Phase 2.2 — implement focus-modality inheritance in `_addExercise`
- [ ] Phase 2.3 — run all 6 new tests + 2 audit regressions to green
- [ ] Phase 2.4 — run full `flutter test` to confirm no regressions
- [ ] Phase 2.7 — doc hygiene (navigation_and_screens.md, state_management.md)
- [ ] Phase 3 — code review

## Feedback
