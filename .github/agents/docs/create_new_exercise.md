# Create New Exercise — UX + Technical Notes

## Purpose

Add and edit custom exercises without leaving the picker flow, while keeping the form aligned with OmniTrain's modality system.

The current editor is **modality-first**: the chosen modality drives which disciplines, capability chips, and muscle-group controls are shown.

---

## Screen API

**File**: `lib/features/exercise/exercise_editor_screen.dart`

`ExerciseEditorScreen` accepts three inputs:

| Parameter | Purpose |
|-----------|---------|
| `workoutState` | Repository-backed state object used to load reference data and save |
| `initialExercise` | Optional exercise for edit mode |
| `contextModality` | Optional prefill from the calling flow |

Create flow typically passes `contextModality` and leaves `initialExercise` null.

---

## Entry Points

- `ExercisePickerScreen` → `New Exercise`
- Any edit flow that pushes `ExerciseEditorScreen(initialExercise: exercise)`

---

## Form Structure

### 1. Modality (required)

The form starts with four modality chips:

- `Cardio / Endurance`
- `Resistance / Lifting`
- `Sports`
- `Isometric / Stretching`

Behavior:

- create mode can prefill the modality from `contextModality`
- edit mode locks the modality if the existing exercise already has a non-null modality
- changing modality clears capabilities that are no longer valid for the new modality
- changing modality resets the selected discipline and may hide muscle groups

### 2. Name and Description

- `Exercise name` is required and uses `TextCapitalization.words`
- `Description` is optional and uses `TextCapitalization.sentences`

### 3. Discipline

The discipline dropdown is filtered by the selected modality's category affinity through `ModalityConfig.disciplinesForModality(...)`.

If no modality is selected yet, the dropdown is disabled.

### 4. Capabilities

Capabilities are rendered from `ModalityConfig.formCapabilities`, not from the full global capability list.

| Modality | Capability Chips | Save Requires One Of | Muscle Groups | Discipline Scope |
|----------|------------------|----------------------|---------------|------------------|
| `cardio_endurance` | `time`, `distance`, `rounds` | `time`, `distance` | Hidden | `category-cardio` |
| `resistance_lifting` | `reps`, `sets`, `load`, `time` | `reps`, `load` | Shown | `category-resistance` |
| `sports` | `time`, `rounds`, `distance` | `time`, `rounds` | Hidden | `category-sports` |
| `isometric_stretching` | `hold`, `time`, `sets` | `hold` | Shown | `category-isometric` |

### 5. Muscle Groups

Muscle-group chips are only shown when `ModalityConfig.showMuscleGroupsInForm` is true.

That currently means:

- `resistance_lifting`
- `isometric_stretching`

---

## Validation Rules

The form validates before save:

- modality must be selected
- exercise name must be non-empty after trim
- at least one required capability for the chosen modality must be selected

Validation messages are stored locally in `_modalityError`, `_nameError`, and `_capabilityError` and rendered inline.

---

## Legacy Capability Handling

Edit mode preserves compatibility with older exercises whose saved capabilities no longer belong to the current modality form.

Behavior:

- unsupported saved capabilities are surfaced as `(Legacy)` chips
- legacy chips are visible only in edit mode
- they cannot be newly added from the current form
- they can be removed from the saved exercise

This behavior is driven by `ModalityConfig.legacyCapabilitiesForEdit(...)`.

---

## Save Flow

1. The editor loads disciplines and muscle groups through `WorkoutState`.
2. The user fills the form and taps `Save exercise`.
3. The screen validates modality, name, and required capabilities.
4. On success, the screen calls one of:
   - `WorkoutState.createCustomExercise(...)`
   - `WorkoutState.updateCustomExercise(...)`
5. Capabilities and muscle-group ids are sorted before persistence.
6. The saved `Exercise` is popped as the route result.

If persistence fails, the screen shows a `SnackBar` with the `WorkoutState.error` message or a fallback error string.

---

## Persistence Notes

Create mode persists:

- a new `Exercise`
- capability links
- muscle-group links

Edit mode persists:

- the updated `Exercise` fields (`name`, `description`, `disciplineId`, `modality`, `updatedAtMs`)
- the new capability set
- the new muscle-group set

The picker flow refreshes and re-ranks results after the editor returns.

---

## Related Files

- [modality_tracking.md](modality_tracking.md)
- [constants_reference.md](constants_reference.md)
- [navigation_and_screens.md](navigation_and_screens.md)

---

**Document Version**: 2.0
**Last Updated**: May 17, 2026


---

> **Doc freshness** — Last reconciled against source: 2026-07-26. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree as it exists on the reconciliation date. If you find a claim here that disagrees with `lib/`, `lib/` wins — please flag the drift in a fresh chat with the Coordinator agent.
