# Feature: Replace Legacy Tracking Dialog in Routine Creation with Standard Modality Picker

## Overview
The create routine flow uses `MetricChooserDialog` (raw capability list) when asking the user how to track an exercise. Everywhere else (e.g. the Free Training session overview) uses `ModalityPickerDialog` (four-modality tile picker: Cardio, Resistance, Sports, Isometric). This plan replaces the former with the latter in the routine flow for consistency.

## Requirements
- The create routine flow must surface `ModalityPickerDialog` when selecting how to track an exercise
- The legacy `MetricChooserDialog` usage inside `routine_setup_screen.dart` must be removed
- `MetricChooserDialog` itself must NOT be deleted (it still has a caller in `session_summary_screen.dart`)
- Downstream state wiring (effortKind → `addExerciseToRoutine` / `updateEffortKind`) must remain correct

## Acceptance Criteria
- [ ] `ModalityPickerDialog` is shown in both `_addExercise` and `_changeTracking` within `routine_setup_screen.dart`
- [ ] `metric_chooser_dialog.dart` import is removed from `routine_setup_screen.dart`
- [ ] `_deduplicateCapabilities` helper and its call sites removed from `routine_setup_screen.dart` (it was only used to gate the old dialog)
- [ ] Effort kind conversion uses `ModalityConfig.forModality(pickedModality)?.effortKind ?? 'set'` (matching session_overview_screen pattern)
- [ ] A new widget test in `screen_widget_test.dart` asserts that tapping the tracking button in `RoutineSetupScreen` shows `ModalityPickerDialog`
- [ ] `MetricChooserDialog` dialog-widget tests are untouched (the dialog still exists and is used in `session_summary_screen.dart`)

## Scenarios
N/A – UI-only consistency fix, no schema changes, no new state methods.

## Iteration 1

### DB Changes
None.

### Backend / State Changes
None. The effortKind derivation path changes from:
```
capability → ModalityConfig.effortKindFromMetric(metric)
```
to:
```
modality  → ModalityConfig.forModality(modality)?.effortKind ?? 'set'
```
Both paths resolve to the same `String effortKind` consumed by `addExerciseToRoutine` and `updateEffortKind`. No state interface changes.

### Frontend Changes

#### `lib/features/routine/routine_setup_screen.dart`

1. **Imports** — replace:
   ```dart
   import '../../widgets/pickers/metric_chooser_dialog.dart';
   ```
   with:
   ```dart
   import '../../widgets/pickers/modality_picker_dialog.dart';
   ```

2. **`_addExercise`** — remove the `_deduplicateCapabilities` guard and `MetricChooserDialog` call; replace with `ModalityPickerDialog`:
   ```dart
   // Step 2: Pick modality (standard picker)
   final modalityResult = await showDialog<(bool, String?)>(
     context: context,
     builder: (_) => const ModalityPickerDialog(),
   );
   if (modalityResult == null) return;
   final (_, pickedModality) = modalityResult;
   final effortKind = ModalityConfig.forModality(pickedModality)?.effortKind ?? 'set';
   ```

3. **`_changeTracking`** — same replacement pattern.

4. **`_deduplicateCapabilities` function** (line ~1757) — delete entirely; it is no longer referenced.

#### `test/screen_widget_test.dart`

Add a new test inside the `RoutineSetupScreen` group (or in a sub-group) titled
`"tracking selection shows ModalityPickerDialog"`. The test:
- Creates a `RoutineState` with a routine and one exercise already added
- Pumps `RoutineSetupScreen`
- Navigates to the detail view for that exercise
- Taps the "Change Tracking" / tracking button to trigger `_changeTracking`
- Asserts `find.byType(ModalityPickerDialog)` (or `find.text('Select Exercise Modality')`) findsOneWidget

### Implementation Steps
1. [ ] Edit `routine_setup_screen.dart`: swap import, rewrite `_addExercise` step 2
2. [ ] Edit `routine_setup_screen.dart`: rewrite `_changeTracking`
3. [ ] Edit `routine_setup_screen.dart`: delete `_deduplicateCapabilities` definition
4. [ ] Add new widget test to `screen_widget_test.dart`
5. [ ] Run `flutter test` to confirm green

## Progress
- [x] Edit `_addExercise` in `routine_setup_screen.dart`
- [x] Edit `_changeTracking` in `routine_setup_screen.dart`
- [x] Remove `_deduplicateCapabilities` from `routine_setup_screen.dart`
- [x] Swap import in `routine_setup_screen.dart`
- [x] Add tracking-selection test to `screen_widget_test.dart`
- [x] Confirm all tests pass

### Phase 2 Complete ✓
Implementation done. Focused and file-wide widget tests passed.

## Feedback
<!-- Leave empty until a specialist or reviewer adds notes -->
