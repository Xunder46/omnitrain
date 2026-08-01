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

## Modality-First Form

The chosen modality drives everything else in the form: which disciplines are offered, which
capability chips are selectable, and whether muscle groups appear at all.

- Create mode may prefill the modality from `contextModality`; edit mode **locks** it once the
  exercise already has one, because changing it would invalidate the capabilities already saved
  against the exercise.
- Changing the modality clears capabilities that are not valid for the new one, and resets the
  selected discipline.
- Capability chips come from `ModalityConfig.formCapabilities` — never the full global capability
  list — and save is blocked until at least one of `ModalityConfig.formRequiredCapabilities` is
  selected. Both live in `lib/core/constants/modality_config.dart`; that file is the only place
  the per-modality sets are defined.
- Muscle groups appear only when `ModalityConfig.showMuscleGroupsInForm` is true.

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

## Save

Save routes through `WorkoutState.createCustomExercise` or `updateCustomExercise` and pops the
saved `Exercise` as the route result; the picker re-ranks its results on return. Capabilities and
muscle-group ids are sorted before persistence so stored order is deterministic. A persistence
failure leaves the form open with the error surfaced rather than discarding the user's input.

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
