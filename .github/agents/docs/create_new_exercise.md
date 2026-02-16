# Create New Exercise — UX + Technical Notes

## Purpose

Add a lightweight path for users to define an exercise that does not exist in the library, without leaving the exercise picker flow.

## Entry Points

- Exercise picker dialog button: "Add Custom Exercise".
- Opens the `ExerciseEditorScreen` via `Navigator.push`.

## UI Surface (ExerciseEditorScreen)

### Form Fields

- **Exercise name** (required)
- **Description** (optional)
- **Discipline** (dropdown, optional)
- **Capabilities** (multi-select chips)
- **Muscle groups** (multi-select chips)

### States

- **Loading**: loads disciplines + muscle groups before showing the form.
- **Saving**: disables the Save button while persisting.
- **Error**: shows a SnackBar when creation fails.

### Validation

- Name is required; empty or whitespace-only names are rejected.

## Create Flow (Picker -> Editor -> Picker)

1. User taps "Add Custom Exercise" in the exercise picker.
2. `ExerciseEditorScreen` opens and loads reference data (disciplines + muscle groups).
3. User completes form and taps "Save exercise".
4. `WorkoutState.createCustomExercise(...)` persists:
   - New `Exercise` with id `exercise-<timestamp>`
   - Capabilities
   - Muscle group links
5. Editor closes with the created `Exercise` as the route result.
6. Picker refreshes:
   - Updates search text to the new exercise name
   - Re-runs the ranked search to show the newly created entry

## Data Model + Persistence

### `WorkoutState.createCustomExercise`

- Generates a timestamp id and constructs `Exercise`.
- Persists:
  - `createExercise(exercise)`
  - `setExerciseCapabilities(exerciseId, capabilities)`
  - `setExerciseMuscleGroups(exerciseId, muscleGroupIds)`
- Updates `_exerciseCache` and `_allExercises` in memory.
- Returns the created exercise or `null` on error.

## Notes

- The editor accepts an optional `initialExercise`, but the create flow does not pass one.
- The picker maintains ranked ordering for the active modality after creation.

## Related Files

- [lib/features/exercise/exercise_editor_screen.dart](lib/features/exercise/exercise_editor_screen.dart)
- [lib/widgets/pickers/exercise_picker_dialog.dart](lib/widgets/pickers/exercise_picker_dialog.dart)
- [lib/state/workout/workout_state.dart](lib/state/workout/workout_state.dart)
