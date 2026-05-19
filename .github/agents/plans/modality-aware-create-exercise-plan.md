# Feature: Modality-Aware Create New Exercise

## Overview
The Create New Exercise form currently shows all seven capabilities, all disciplines, and all muscle groups regardless of the exercise being created. This feature makes the form modality-first: the user picks a modality at the top of the form, and capabilities, disciplines, and the muscle group section are filtered to what belongs to that modality. A session's modality pre-fills the selector. The modality is persisted on the exercise for use by ranking and the picker.

## Requirements
- Modality selector at the top of the form (above Exercise Name), chip-row or segmented control
- Four selectable modalities: Cardio / Endurance, Resistance / Lifting, Sports, Isometric / Stretching
- Modality is required — form cannot be saved without one
- Capability chips filtered to the selected modality (primary + secondary capabilities only)
- At least one form-required capability must be selected before save
- Discipline dropdown filtered to the selected modality's category
- Muscle groups hidden for Cardio and Sports; shown for Resistance and Isometric
- Session modality pre-fills selector when opened from a session; empty when opened from Free Training / My Routines
- Modality persisted on the Exercise model
- Edit mode: modality shown read-only; legacy (out-of-modality) capabilities shown as already-checked, visually distinct, can be deselected but not re-selected, with inline "Legacy capability" label
- Mid-edit modality change: drops non-matching capabilities, clears discipline, preserves matching capabilities and muscle groups if new modality shows them

## Acceptance Criteria
- [ ] New exercise cannot be saved without a modality selected
- [ ] New exercise cannot be saved without at least one form-required capability (per modality)
- [ ] Capability chips shown are exactly primary + secondary for the selected modality — no others
- [ ] Discipline dropdown shows only disciplines whose categoryId matches the modality's categoryId, plus None
- [ ] Muscle group section hidden for cardio_endurance and sports; shown for resistance_lifting and isometric_stretching
- [ ] Created exercise has its modality field set and retrievable on reload
- [ ] Opening editor from a session with a modality pre-fills that modality
- [ ] Opening editor from Free Training / My Routines (null modality) leaves selector empty
- [ ] User can override a pre-filled modality before saving
- [ ] Editing exercise shows modality as read-only label with no interactive affordance
- [ ] Legacy capabilities in edit mode: shown checked, visually distinct, can be deselected, cannot be re-selected, "Legacy capability" label visible when any are present
- [ ] Changing modality during creation drops non-matching capabilities, clears discipline, preserves matching capabilities, adjusts muscle group visibility
- [ ] No confirmation dialog on mid-edit modality change
- [ ] Validation messages appear inline adjacent to the field (not in a top-level banner)
- [ ] Validation messages name the specific expected input (e.g. "Select at least one of: Reps, Load")
- [ ] "New Exercise" entry point from exercise picker continues to work
- [ ] After save, picker refreshes and pre-fills search with the new exercise's name
- [ ] Existing custom exercises (no modality) continue to appear in the library and open for editing per Section 4.1 rules

## Configuration Gap Inventory (Phase 1 Output)

### ModalityConfig already provides (no changes needed):
- `primaryCapabilities` — used for ranking; also doubles as the top-tier form capabilities
- `secondaryCapabilities` — used for ranking; also the secondary form capabilities
- `antiCapabilities` — used for ranking; not needed in form layer
- `categoryId` — used for discipline affinity in ranking; also used to filter disciplines in the form

### What the form needs that ModalityConfig does NOT yet have:
| Field | Purpose | Values |
|---|---|---|
| `formRequiredCapabilities` | At least one must be selected to enable Save | cardio: [time, distance]; resistance: [reps, load]; isometric: [hold]; sports: [time, rounds] |
| `showMuscleGroupsInForm` | Whether to render the muscle group section | resistance: true; isometric: true; cardio: false; sports: false; null: false |

### Derived without a new field (computed at runtime):
- **Form capabilities shown** = `primaryCapabilities + secondaryCapabilities` — matches spec exactly for all four modalities:
  - cardio: [time, distance] + [rounds] = [time, distance, rounds] ✓
  - resistance: [reps, sets, load] + [time] = [reps, sets, load, time] ✓
  - isometric: [hold, time] + [sets] = [hold, time, sets] ✓
  - sports: [time, rounds] + [distance] = [time, rounds, distance] ✓
- **Filtered disciplines** = `allDisciplines.where(d => d.categoryId == modalityConfig.categoryId)` — no new field needed

### Exercise model gap:
- `Exercise` has no `modality` field. It must be added.

## Scenarios
[Populated by Developer agent during Phase 0]

---

## Iteration 1

### Analysis
Three phases of work, clearly sequenced by data-layer-first discipline. Phase 1 is pure configuration — no user-visible changes. Phase 2 is model + state — no user-visible changes. Phase 3 is UI. Phases can be merged by a single developer but their deliverables are independently testable.

---

### Phase 1: Configuration and Validation Layer (@dba)

**Goal:** Extend `ModalityConfig` with the two form-specific fields, confirm no gaps exist, and define the validation rules the UI layer will enforce. No user-visible changes.

#### DB Changes
None. No schema changes — `Exercise.modality` is added in Phase 2 at the model layer. Hive and Mock repositories store and retrieve it automatically via `toMap`/`fromMap`.

#### Backend / Config Changes

1. [ ] **Extend `ModalityConfig`** in `lib/core/constants/modality_config.dart`:
   - Add `final List<String> formRequiredCapabilities` field to the class (const-compatible)
   - Add `final bool showMuscleGroupsInForm` field to the class (const-compatible)
   - Update the `const ModalityConfig(...)` constructor to include both fields with defaults:
     - `formRequiredCapabilities = const []`
     - `showMuscleGroupsInForm = false`
   - Update each modality's config entry in the `configs` map:

   | Modality key | `formRequiredCapabilities` | `showMuscleGroupsInForm` |
   |---|---|---|
   | `cardio_endurance` | `['time', 'distance']` | `false` |
   | `resistance_lifting` | `['reps', 'load']` | `true` |
   | `isometric_stretching` | `['hold']` | `true` |
   | `sports` | `['time', 'rounds']` | `false` |
   | `null` (Free Training) | `[]` | `false` |

2. [ ] **Add helper getters/methods** to `ModalityConfig`:
   - `List<String> get formCapabilities => [...primaryCapabilities, ...secondaryCapabilities]`
     Returns the full set of capabilities shown in the creation form (primary + secondary). Pure getter, no new stored data.
   - `static List<Discipline> disciplinesForModality(String? modality, List<Discipline> all)` → returns `all.where(d => d.categoryId == ModalityConfig.forModality(modality)?.categoryId).toList()`, or `all` if modality is null.
   - `static String formRequiredCapabilitiesLabel(String? modality)` → returns a human-readable label for the validation message, e.g. `"Select at least one of: Reps, Load"`. Maps capability IDs to display names.

3. [ ] **Add a modality display name helper** (for use by the modality chip row in Phase 3):
   - `static String modalityDisplayName(String? modality)` → returns `"Cardio / Endurance"`, `"Resistance / Lifting"`, `"Isometric / Stretching"`, `"Sports"`, or `"Free Training"` for null.

4. [ ] **Verify existing tests still pass** after adding the new fields with defaults. No ranking test should be affected since formRequiredCapabilities and showMuscleGroupsInForm are only read by the form.

#### Deliverable / Testable
- Unit test: for each modality, verify `formCapabilities` returns the correct capability list per the spec table.
- Unit test: `formRequiredCapabilities` returns the correct list per the spec table.
- Unit test: `showMuscleGroupsInForm` is `true` for resistance and isometric, `false` for cardio and sports.
- Unit test: `disciplinesForModality` returns only disciplines whose `categoryId` matches the modality's `categoryId`.
- Unit test: `formRequiredCapabilitiesLabel` produces expected strings for all modalities.
- All existing tests must continue to pass.

---

### Phase 2: Model, State, and Logic (@dba)

**Goal:** Add `modality` to the `Exercise` model, update `createCustomExercise` to accept and persist it, ensure edit-mode round-trips work, and implement legacy-capability logic. No user-visible changes.

#### DB Changes (Model Layer Only)
No SQL schema changes. This app uses Hive + Mock repositories which store via `toMap`/`fromMap`.

1. [ ] **Add `modality` field to `Exercise` model** in `lib/data/models/models.dart`:
   - Add `final String? modality;` to the field list
   - Add `this.modality,` to the constructor
   - Add `modality: m['modality'] as String?,` to `Exercise.fromMap`
   - Add `'modality': modality,` to `Exercise.toMap`

2. [ ] **Update `Exercise.copyWith`** in `lib/core/utils/exercise_helpers.dart`:
   - Add `String? modality` as a nullable named parameter (no sentinel needed — null means "keep existing" is ambiguous, but since modality is nullable and fixed after creation, using a sentinel is the safe approach)
   - Use the same `_exerciseCopyWithUnset` sentinel pattern already used for `howToSteps` and `imageAssetPath`:
     ```dart
     Object? modality = _exerciseCopyWithUnset,
     ```
   - In the `return Exercise(...)` block:
     ```dart
     modality: modality == _exerciseCopyWithUnset ? this.modality : modality as String?,
     ```

3. [ ] **Update `WorkoutState.createCustomExercise`** in `lib/state/workout/workout_state.dart`:
   - Add `String? modality` named parameter
   - Pass it to the `Exercise(...)` constructor: `modality: modality,`
   - No other changes — the repository's `createExercise(exercise)` stores the full map already

4. [ ] **Update `HiveWorkoutRepository.updateExercise`** (and any `updateSession`-style partial-update helpers in `hive_workout_repository.dart` that construct Exercise from `existing` fields explicitly):
   - Check line ~592 where `existing.modality` is referenced in a `TrainingSession` partial update — this is `TrainingSession.modality`, not `Exercise.modality`, so it is unaffected
   - Confirm no explicit per-field Exercise reconstruction exists in HiveWorkoutRepository (updateExercise at line 447 does `_exercisesBox.put(exercise.id, exercise.toMap())` — stores the full object, so it's already correct once the model has the field)
   - Same confirmation for `MockWorkoutRepository.updateExercise`

5. [ ] **Implement legacy-capability identification logic** — add a static helper to `ModalityConfig` (or a function in a new `lib/core/utils/exercise_form_helpers.dart`):
   - `static List<String> legacyCapabilitiesForEdit(String? modality, List<String> exerciseCapabilities)` → returns capabilities that the exercise has but that do NOT appear in `formCapabilities` for the given modality. These are the legacy chips.
   - If modality is null (exercise created before feature), returns empty list (the edit form will require modality selection first per Section 4.1 — no legacy treatment until modality is known).

#### Deliverable / Testable
- Unit test: `Exercise.fromMap(toMap())` round-trips correctly with a modality value.
- Unit test: `Exercise.copyWith(modality: 'resistance_lifting')` produces correct result.
- Unit test: `copyWith()` without modality preserves existing modality.
- Unit test: `createCustomExercise(modality: 'cardio_endurance', ...)` returns an exercise with `modality == 'cardio_endurance'`.
- Unit test: loading that exercise back (via repository) returns the same modality.
- Unit test: `legacyCapabilitiesForEdit('resistance_lifting', ['reps', 'load', 'hold'])` returns `['hold']` (hold is not in resistance form capabilities).
- Unit test: `legacyCapabilitiesForEdit('resistance_lifting', ['reps', 'load'])` returns `[]`.
- Unit test: `legacyCapabilitiesForEdit(null, ['reps'])` returns `[]`.

---

### Phase 3: UI (@developer)

**Goal:** Replace the existing `ExerciseEditorScreen` with the modality-aware version, wire all entry points, implement legacy edit treatment, and validate inline.

#### Frontend Changes

1. [ ] **Add `contextModality` parameter to `ExerciseEditorScreen`**:
   - Add `final String? contextModality` to the widget constructor
   - Initialize `_selectedModality` in `initState`:
     - If `widget.initialExercise != null`: set to `widget.initialExercise!.modality` (read-only)
     - Else: set to `widget.contextModality` (pre-fill from session, may be null)

2. [ ] **Update `ExercisePickerDialog._openCreateExercise`** in `lib/widgets/pickers/exercise_picker_dialog.dart`:
   - Pass `contextModality: widget.sessionModality` to `ExerciseEditorScreen`
   - No other changes to the picker

3. [ ] **Add modality state to `_ExerciseEditorScreenState`**:
   - `String? _selectedModality` — selected modality key
   - `bool _isEditMode` — `widget.initialExercise != null`
   - `List<String> _legacyCapabilities` — capabilities on the exercise that do not belong to the modality (only relevant in edit mode, computed once)
   - Validation error strings: `String? _modalityError`, `String? _capabilityError`, `String? _nameError`

4. [ ] **Modality change handler `_onModalityChanged(String? newModality)`**:
   - If `_isEditMode`, do nothing (modality is read-only)
   - Compute `newFormCaps = ModalityConfig.forModality(newModality)?.formCapabilities ?? []`
   - Drop `_selectedCapabilities` entries not in `newFormCaps`
   - Clear `_selectedDisciplineId`
   - If `ModalityConfig.forModality(newModality)?.showMuscleGroupsInForm != true`, clear `_selectedMuscleGroupIds`
   - Set `_selectedModality = newModality`
   - Call `setState`

5. [ ] **Filtered discipline list**: computed inline in `build`:
   ```dart
   final filteredDisciplines = ModalityConfig.disciplinesForModality(_selectedModality, _disciplines);
   ```

6. [ ] **Validation method `_validateAndSave()`**:
   - Replaces `_save()` or calls it after inline validation
   - Name empty → set `_nameError = 'Exercise name required.'`
   - Modality null → set `_modalityError = 'Select a modality.'`
   - No form-required capability selected → set `_capabilityError = ModalityConfig.formRequiredCapabilitiesLabel(_selectedModality)`
   - If any errors, `setState` and return without saving
   - On success, call existing save logic, passing `modality: _selectedModality`

7. [ ] **Build the modality selector widget** (inline in screen or extracted as private method):
   - A `Wrap` of `ChoiceChip` widgets, one per non-null modality key: `['cardio_endurance', 'resistance_lifting', 'isometric_stretching', 'sports']`
   - Selected chip uses the modality's accent color from `OmniTheme` / `ModalityConfig`
   - In edit mode: replace with a read-only `Text` or `Chip` showing `ModalityConfig.modalityDisplayName(exercise.modality)` with no `onSelected` callback
   - Inline error: if `_modalityError != null`, show it below the selector in error style

8. [ ] **Capability chips section** (replaces current static `_capabilityOptions` list):
   - Derive `allowedCaps = ModalityConfig.forModality(_selectedModality)?.formCapabilities ?? []`
   - For edit mode, also derive `legacyCaps` from `_legacyCapabilities`
   - Regular chips: `allowedCaps` — standard `FilterChip` behavior
   - Legacy chips: shown after regular chips; use a visually distinct style (outlined, greyed text, no fill); can be deselected via `onSelected: (v) { if (!v) setState(() => _selectedCapabilities.remove(id)); }` — re-selection blocked (chip becomes unselectable once deselected: `onSelected: null` after deselection, or track `_deselectedLegacyCapabilities` set)
   - When any legacy capability is present (initially, before any are deselected): show `Text('Legacy capability', style: errorStyle)` inline below the chips; hide when all have been deselected
   - Inline error: if `_capabilityError != null`, show it below the chip wrap

9. [ ] **Discipline dropdown** (replaces current):
   - Use `filteredDisciplines` computed above
   - Reset `_selectedDisciplineId = null` if it no longer exists in `filteredDisciplines` (handle after modality change)
   - If modality is null (not yet selected), render the dropdown as disabled or hidden

10. [ ] **Muscle groups section**:
    - Show only if `ModalityConfig.forModality(_selectedModality)?.showMuscleGroupsInForm == true`
    - Unchanged chip behavior when shown

11. [ ] **Form section ordering** (top to bottom):
    1. Modality selector (with inline error)
    2. Exercise Name field (with inline error)
    3. Description field
    4. Discipline dropdown
    5. Capabilities section (with inline error)
    6. Muscle Groups section (conditional)

12. [ ] **AppBar title**: update to show "New Exercise" for create mode and "Edit Exercise" for edit mode (if not already done)

13. [ ] **Update `_save` call-site** in `_ExerciseEditorScreenState` to pass `modality: _selectedModality` to `widget.workoutState.createCustomExercise`

14. [ ] **Edit mode for exercises without modality** (Section 4.1 — pre-feature exercises):
    - `widget.initialExercise.modality` is null → `_selectedModality` is null → modality selector is shown in interactive mode (not read-only) until the user picks one
    - Once modality is selected, it becomes read-only for the rest of the session (same as new exercises)
    - Implementation: `_isEditMode && widget.initialExercise!.modality != null` → modality is read-only; `_isEditMode && widget.initialExercise!.modality == null` → modality is interactive until first selection

#### Files Affected (Phase 3)
- `lib/features/exercise/exercise_editor_screen.dart` — full rework
- `lib/widgets/pickers/exercise_picker_dialog.dart` — pass `contextModality` to editor (one-line change)

---

### Implementation Steps (combined sequence for a single developer)

1. [ ] Phase 1: Extend `ModalityConfig` with `formRequiredCapabilities`, `showMuscleGroupsInForm`, `formCapabilities` getter, `disciplinesForModality`, `formRequiredCapabilitiesLabel`, `modalityDisplayName`
2. [ ] Phase 1: Write unit tests for all new ModalityConfig helpers
3. [ ] Phase 2: Add `modality` field to `Exercise` model (`models.dart`)
4. [ ] Phase 2: Add `modality` to `Exercise.copyWith` in `exercise_helpers.dart`
5. [ ] Phase 2: Add `modality` param to `WorkoutState.createCustomExercise`
6. [ ] Phase 2: Implement `legacyCapabilitiesForEdit` helper
7. [ ] Phase 2: Write unit tests for model round-trips and legacy capability helper
8. [ ] Phase 3: Add `contextModality` to `ExerciseEditorScreen` constructor
9. [ ] Phase 3: Wire `ExercisePickerDialog` to pass `sessionModality`
10. [ ] Phase 3: Rework `_ExerciseEditorScreenState` — modality state, `_onModalityChanged`, modality selector widget, filtered caps, filtered disciplines, conditional muscle groups
11. [ ] Phase 3: Implement `_validateAndSave` with inline validation messages
12. [ ] Phase 3: Handle legacy capabilities in edit mode (visually distinct chips, deselect-only, label)
13. [ ] Phase 3: Handle null-modality edit mode (Section 4.1 — interactive selector until first pick)
14. [ ] Phase 3: Manual QA — all four modalities × create + edit, both entry points, legacy exercise edit, validation messages, mid-edit modality change

---

## Progress
- [x] Phase 1: Extend ModalityConfig (formRequiredCapabilities, showMuscleGroupsInForm, helpers)
- [x] Phase 1: Unit tests for ModalityConfig helpers
- [x] Phase 2: Add modality to Exercise model
- [x] Phase 2: Update Exercise.copyWith
- [x] Phase 2: Update WorkoutState.createCustomExercise
- [x] Phase 2: legacyCapabilitiesForEdit helper + tests
- [x] Phase 3: ExerciseEditorScreen rework
- [x] Phase 3: ExercisePickerDialog wiring
- [ ] Phase 3: Manual QA

### Phase 1 Status: Complete
Configuration and validation lookup layer implemented in a storage-agnostic way; ready for Hive workflow now and future SqliteWorkoutRepository consumption.

### Phase 2 Status: Complete
Data-layer modality persistence and legacy capability logic implemented and test-validated for current repositories, with SQLite schema parity updated for future production repository implementation.

### Phase 3 Status: In Progress
Exercise editor and picker wiring are implemented and test-validated; manual QA across modalities and entry-point combinations remains.

## Feedback

