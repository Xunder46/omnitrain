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

Create flow leaves `initialExercise` null. `contextModality` is passed only by the
picker's empty-state create button (the session's modality prefills the form); the
Exercise Library's header `+` passes none — the user picks the modality in the form.

---

## Entry Points

- `ExerciseLibraryScreen` header `+` (`exercise_library_new_button`, tooltip
  `New Exercise`) → `ExerciseEditorScreen(workoutState)` with no
  `contextModality`; on a created exercise the library clears that exercise's
  cached muscle links, puts its name in the search field, reloads and warms the
  cache. Verified by `test/pr8_exercise_library_test.dart` (group
  `ExerciseLibraryScreen` · `S-4102: header carries the create action`,
  `S-4103: the action opens the editor in create mode`,
  `S-4106: the editor is opened without a session modality`,
  `S-4105: backing out of the editor changes nothing`,
  `S-4104: a saved exercise lands in the search field and list`).
- `ExercisePickerScreen` empty state (`No exercises found`) → outlined
  `New Exercise` button (`exercise_picker_new_button` in `OmniEmptyState.action`)
  → `ExerciseEditorScreen(workoutState, contextModality: sessionModality)`; on a
  created exercise the picker puts its name in the search field and re-searches.
  Shown only when the filtered list is empty. Verified by
  `test/screen_widget_test.dart` (group `ExercisePickerScreen` ·
  `S-4108: empty results offer New Exercise; a populated list does not`,
  `S-4109: the button opens the editor with the session modality`,
  `S-4110: a saved exercise lands in the picker search field and list`); the
  picker itself no longer carries a top create button
  (`S-4101: no New Exercise button; search field comes first`).
- `ExerciseLibraryDetailScreen` → `Edit` (custom exercises only; built-in rows offer Copy). Verified by `test/pr8_exercise_library_test.dart` (group `ExerciseLibraryDetailScreen` · `S-9: Edit opens the full editor and saves through it`).
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
- The four modality choices are equal-width chips laid out two per row (a 2×2 grid), each label
  single-line with ellipsis. Verified by `test/muscle_editor_screen_test.dart` (group
  `S-6 modality grid and headers` · `the four chips fill two equal-width rows at 390 and 320`).
- Capability chips come from `ModalityConfig.formCapabilities` — never the full global capability
  list — and save is blocked until at least one of `ModalityConfig.formRequiredCapabilities` is
  selected. Both live in `lib/core/constants/modality_config.dart`; that file is the only place
  the per-modality sets are defined.
- Muscle groups appear only when `ModalityConfig.showMuscleGroupsInForm` is true.

The three sections carry the shared `OmniCardHeader` titles `MODALITY`, `CAPABILITIES` and
`MUSCLES` (the old `Muscle groups` text is gone). Verified by `test/muscle_editor_screen_test.dart`
(group `S-6 modality grid and headers` · `the section headers are OmniCardHeader, the old title gone`).

## Muscle Section

When the modality shows muscles, the section is `MusclePicker`
(`lib/widgets/exercise/muscle_picker.dart`): the fixed taxonomy rows of chips — each region row
starting with a `Whole <region>` chip — plus a two-line summary (`Main: …` / `Assists: …`).

- The screen owns a `MuscleSelection` (`lib/core/utils/muscle_selection.dart`); a tap on a chip
  cycles that id off → main → assists → off. Verified by `test/muscle_picker_test.dart`
  (`S-3 chest cycles main, then assists, then none`) and `test/muscle_selection_test.dart`
  (group `S-1 selection model` · `an empty selection cycles a muscle off → main → assists → off`).
- A region chip whose own muscles carry a role is inert: tapping it changes nothing, so a region
  and one of its own muscles can never both be chosen. Verified by `test/muscle_selection_test.dart`
  (group `S-1 selection model` · `a region whose muscles carry a role is covered and inert`) and
  `test/muscle_picker_test.dart` (`S-3 whole legs then quadriceps leaves the legs chip covered`).
- Switching to a modality that hides the section clears the selection.
  Verified by `test/muscle_editor_screen_test.dart` (group `S-4 editor save rules` ·
  `Sports hides the picker and a round trip clears the selection`).

## Validation Rules

The form validates before save:

- modality must be selected
- exercise name must be non-empty after trim
- at least one required capability for the chosen modality must be selected
- the muscle selection must not be assists-only: `Pick at least one main muscle.` blocks Save.
  Nothing chosen is valid. Verified by `test/muscle_editor_screen_test.dart` (group
  `S-4 editor save rules` · `an assists-only selection is blocked and creates nothing` and
  `saving with nothing chosen succeeds with no links`); the underlying rule is
  `MuscleSelection.hasOnlyAssists`, verified by `test/muscle_selection_test.dart` (group
  `S-1 selection model` · `hasPrimary and hasOnlyAssists`).

Validation messages are stored locally in `_modalityError`, `_nameError`, `_capabilityError` and
`_muscleError` and rendered inline. After a failed save the screen scrolls the first field in
error into view, in the order the form reads its sections (modality, name, capabilities, muscles).
Verified by `test/muscle_editor_screen_test.dart` (group `S-7 scroll to the first error` ·
`a failed save brings the name error into the viewport`).

## Unsaved Changes

Leaving the form with unsaved edits asks first through
`ConfirmationDialog.showUnsavedChanges` (keep editing / discard); an untouched form leaves
without asking, and a successful save pops without asking. Dirty covers name, description,
modality, discipline, capabilities and the muscle selection. Verified by
`test/muscle_editor_screen_test.dart` (group `S-8 unsaved guard`, and group
`S-13 back to the initial text is not an edit`).

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
saved `Exercise` as the route result; the picker re-ranks its results on return. Capabilities are
sorted before persistence; the muscle selection reaches persistence as `ExerciseMuscleLink`s
(muscle-group id + role) in the normalised order `MuscleTaxonomy.normalize` produces. Verified by
`test/muscle_editor_state_test.dart` (group `S-2 state API` · `createCustomExercise stores the
links normalised`). A persistence failure leaves the form open with the error surfaced rather than
discarding the user's input. Verified by `test/interaction_flow_test.dart`
(group `ExerciseEditorScreen interactions` · `a failed save shows plain copy,
never the exception text`).

## Persistence Notes

Create mode persists:

- a new `Exercise`
- capability links
- muscle links (id + role)

Edit mode persists:

- the updated `Exercise` fields (`name`, `description`, `disciplineId`, `modality`, `updatedAtMs`)
- the new capability set
- the new muscle links (id + role), replacing the stored set

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

> **Doc freshness** — Last reconciled against source: 2026-10-15. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree as it exists on the reconciliation date. If you find a claim here that disagrees with `lib/`, `lib/` wins — please flag the drift in a fresh chat with the Coordinator agent.
