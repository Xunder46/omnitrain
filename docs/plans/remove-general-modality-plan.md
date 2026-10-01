# Feature: Remove "General" from ModalityPickerDialog and MetricChooser fallback

## Overview
The ModalityPickerDialog currently offers five options including "General" (null modality). Selecting "General" triggers a redundant third dialog (MetricChooserDialog). This plan removes the "General" option entirely and collapses the two-branch flow into a single straight path: pick modality → derive effortKind → add exercise.

## Requirements
- Remove the `(null, 'General', Icons.star_outline)` option from ModalityPickerDialog.
- Remove the MetricChooserDialog fallback branch in both WorkoutSessionScreen and SessionOverviewScreen.
- Cancellation behavior must be unchanged.
- Do NOT remove MetricChooserDialog from the codebase.
- Do NOT touch any other screen that references ModalityPickerDialog.

## Acceptance Criteria
- [ ] ModalityPickerDialog shows exactly 4 options: Cardio/Endurance, Resistance/Lifting, Sports, Isometric/Stretching
- [ ] Every option in the dialog maps to a non-null modality constant
- [ ] Confirming a modality calls `addExerciseToSession` immediately with the derived `effortKindOverride` — no further dialogs
- [ ] Dismissing the dialog (Cancel or back) cancels the exercise addition with no records created
- [ ] `MetricChooserDialog` is NOT deleted from the codebase
- [ ] No compile errors

## Scenarios
N/A — pure removal / simplification, no new behavior.

## Iteration 1

### DB Changes
None.

### Backend Changes
None.

### Frontend Changes

#### Phase 1: ModalityPickerDialog (@developer)
File: `lib/widgets/pickers/modality_picker_dialog.dart`

1. [ ] Remove the `(null, 'General', Icons.star_outline)` entry from the `modalities` list in `_buildModalityOptions`.
2. [ ] Remove the `default:` case from `_getModalityDescription` (it exists only to describe the null/General option; removing keeps the switch clean).
3. [ ] Update the class-level doc comment to reflect that null is no longer returned.

#### Phase 2: WorkoutSessionScreen exercise addition flow (@developer)
File: `lib/features/session/workout_session_screen.dart`

4. [ ] In `_addExercise`, inside the `if (modality == null)` block, remove the `else` branch that calls `_deduplicateCapabilities` and shows `MetricChooserDialog`.
5. [ ] Simplify: replace `if (pickedModality != null) { effortKindOverride = ... }` with an unconditional assignment: `effortKindOverride = ModalityConfig.forModality(pickedModality)?.effortKind ?? 'set';` (the `?? 'set'` guard is kept as a safety fallback since `pickedModality` is typed `String?`).
6. [ ] Remove the `String? chosenMetric;` variable declaration (now always null and unused).
7. [ ] Remove the `chosenMetric: chosenMetric,` named argument from the `addExerciseToSession` call (or keep passing `null` explicitly — either way, it must not reference a removed variable).
8. [ ] Remove `import '../../widgets/pickers/metric_chooser_dialog.dart';` from the top of the file (no longer used here).
9. [ ] Remove the `_deduplicateCapabilities` top-level helper function at the bottom of the file — it is now dead code (only called from the removed branch).

#### Phase 3: SessionOverviewScreen exercise addition flow (@developer)
File: `lib/features/session/session_overview_screen.dart`

10. [ ] Same removals as steps 4–9, mirrored for `_addExercise` in `SessionOverviewScreen`.
11. [ ] Remove `import '../../widgets/pickers/metric_chooser_dialog.dart';`.
12. [ ] Remove the `_deduplicateCapabilities` top-level helper function (dead code).

### Implementation Steps
1. Edit `modality_picker_dialog.dart` — remove null/General entry and clean up description switch.
2. Edit `workout_session_screen.dart` — simplify `_addExercise`, remove dead imports and helper.
3. Edit `session_overview_screen.dart` — same simplification.
4. Run `flutter analyze` to confirm no compile errors.

## Progress
- [x] Remove General option from ModalityPickerDialog
- [x] Simplify _addExercise in WorkoutSessionScreen
- [x] Simplify _addExercise in SessionOverviewScreen
- [x] Verify no compile errors — flutter analyze: 0 errors, 0 warnings (188 pre-existing info lints unchanged)

## Feedback

---

> **Fast-track eligible**: This change has no new user-facing behavior, no schema changes, and no new state methods — the user may skip the Conductor and open the **Developer** directly.

**STOP — wait for explicit user approval before sending this handoff.**

Once approved:

@developer — Please proceed with all three phases above (ModalityPickerDialog → WorkoutSessionScreen → SessionOverviewScreen).
