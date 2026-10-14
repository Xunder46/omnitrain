# Plan 34 — Muscle hierarchy, PR 2 of 3: the New / Edit Exercise screen

Status: SEEDED by the lead. Base commit `52ede35` (PR 1 = `fd57bf6`, plan `docs/plans/2026-10-14-33-muscle-hierarchy-data-plan/`).
Series: PR 3 = plan 35 (picker dropdown grouped by region, primary-only chips on list rows, detail view Primary/Secondary, removal of the legacy muscle calls and the future-work entry).
Owner decisions (2026-10-14, all four recommendations accepted): (1) muscle input is tap-to-cycle; (2) the cheap screen fixes ride along; (3) Library "Edit" opens this full form for custom exercises; (4) row order Chest and neck, Back, Shoulders, Arms, Core, Legs.
Design basis: the owner reviewed the mockup in chat and the simulator screenshots of the old screen (23 chips in one alphabetical pile).

## Goal and acceptance

The form where a user tags muscles shows regions with their muscles, lets each choice be a main muscle or one that assists, and cannot produce a state the data layer refuses. The screen's other rough edges from the review are fixed. Edit is reachable from the library.

- A1. Muscle section (resistance and isometric/stretching modalities only, as today): title "MUSCLES" (via `OmniCardHeader`); a one-line hint "Tap once for a main muscle, twice for one that assists, a third time to clear."; rows in this order: "Chest and neck" (chips Chest, Neck), Back (Lats, Traps, Lower back), Shoulders (Front delts, Side delts, Rear delts), Arms (Biceps, Triceps, Forearms), Core (Abs, Obliques), Legs (Quadriceps, Hamstrings, Glutes, Calves, Adductors). Each region row starts with a "Whole <region>" chip (e.g. "Whole legs").
- A2. Each chip cycles off → main → assists → off. Main reads as filled, assists as outlined with the words "· assists" in the label; both distinguishable without colour.
- A3. Choosing a muscle replaces its region's tag; a region chip whose muscles are chosen is inert (visually dimmed, tap does nothing), so a region and its own muscle can never both be selected.
- A4. A summary under the rows shows two lines, "Main: …" and "Assists: …", each "none" when empty.
- A5. Saving with only assists blocked with the visible message "Pick at least one main muscle." (inline in the section, and the screen scrolls to it). Saving with nothing chosen succeeds.
- A6. Roles persist and read back: create and edit both store the exact links; stored order is the normalised one.
- A7. Modality choices are four equal-width chips in a 2×2 grid (order: Cardio / Endurance, Resistance / Lifting, Sports, Isometric / Stretching).
- A8. Section titles use the shared header: "MODALITY", "CAPABILITIES", "MUSCLES" (the old "Muscle groups" text is gone).
- A9. After a failed Save the screen scrolls to the first field in error (order: modality, name, capabilities, muscles).
- A10. Leaving the form with unsaved edits asks first (`ConfirmationDialog.showUnsavedChanges`: keep editing / discard / save); leaving an untouched form, and leaving after a successful save, do not ask.
- A11. Library detail, custom exercise: "Edit" opens this form in edit mode (title "Edit Exercise", fields prefilled, muscles with their roles, modality locked as today); on save the library list shows the change. Built-in exercises still offer Copy only.
- A12. No new bottom sheet or raw `AlertDialog`; `test/ui_standards_contract_test.dart` and `test/docs_indexing_contract_test.dart` stay green; `flutter analyze` not above 182 issues.

## Decision Ledger

- D-1 `MuscleSelection` (new, `lib/core/utils/muscle_selection.dart`): immutable value over `Map<String, MuscleRole>`. API: `roleOf(id)`, `isCovered(regionId)` (a region whose muscles carry a role), `cycle(id)` → new selection, `idsWith(role)`, `isEmpty`, `hasPrimary`, `hasOnlyAssists` (non-empty and no primary), `toLinks()` (= `MuscleTaxonomy.normalize` of the entries; throws when only assists, callers check `hasOnlyAssists` first), `MuscleSelection.fromLinks(links)` (drops a region next to its own muscle). `cycle`: if `id` is a covered region → returns `this`; role null → primary; primary → secondary; secondary → removed; when a MUSCLE gains a role from null its region's own entry is removed. Chest/Neck and unknown ids behave as plain muscles.
- D-2 State API switch (names and semantics): `ExerciseLibrary.createCustomExercise`/`updateCustomExercise`, `WorkoutState` delegates, `ExerciseLibraryState.editCustom`, `ExerciseLibraryService.editCustom` replace `List<String> muscleGroupIds` with `List<ExerciseMuscleLink> muscleLinks = const []` and persist with `setExerciseMuscleLinks`. New `ExerciseLibrary.getExerciseMuscleLinks(id)` and `WorkoutState.getExerciseMuscleLinks(id)`. The legacy `getExerciseMuscleGroups` stays (display screens, plan 35); the legacy `setExerciseMuscleGroups` loses its last `lib/` callers here and stays only for tests until plan 35. A repository `ArgumentError` (secondary-only) surfaces through the existing `_setError('Failed to …')`/null path; the editor never sends it.
- D-3 New widget `MusclePicker` (`lib/widgets/exercise/muscle_picker.dart`): presentation only. Inputs: `List<MuscleGroup> groups` (names by id, from `WorkoutState.muscleGroups`), `MuscleSelection selection`, `ValueChanged<String> onTap(id)`. Row layout and order are defined in the widget from `MuscleTaxonomy` (D-1 acceptance A1); a group id missing from `groups` is skipped. Chip keys `muscle_chip_<id>` (e.g. `muscle_chip_muscle-quads`), summary keys `muscle_summary_main` and `muscle_summary_assists`, hint key `muscle_picker_hint`. Each chip has a `Semantics` label: "<Name>, main muscle" / "<Name>, assists" / "<Name>, not selected"; a covered region chip adds "covered by chosen muscles". Chips are at least 40 dp tall (read `docs/design_system.md` "Accessibility and shape" and "Shape Rule"); colours from `OmniTheme`/`Theme`, never hard-coded. It is not a bottom sheet and does not call `showDialog`.
- D-4 The editor (`lib/features/exercise/exercise_editor_screen.dart`) holds a `MuscleSelection` instead of `Set<String> _selectedMuscleGroupIds`; edit mode loads it from `workoutState.getExerciseMuscleLinks`; changing to a modality that hides muscles clears it (as today); `_validateAndSave` adds a muscle error (`_muscleError`) when `hasOnlyAssists`.
- D-5 Section titles: `OmniCardHeader(title: 'MODALITY' | 'CAPABILITIES' | 'MUSCLES')` (case is part of the title string; see `docs/design_system.md` "Label case"), default padding.
- D-6 Modality grid: two `Expanded` chips per row in two rows with an 8 dp gap, each label single-line with ellipsis; selection and read-only behaviour as today (`ChoiceChip` or equivalent keeping `find.text` taps working).
- D-7 Scroll to first error: a `GlobalKey` per section (modality, name field, capabilities, muscles); after validation fails, `Scrollable.ensureVisible` on the first key whose error is non-null.
- D-8 Unsaved guard: follow `lib/features/period/create_period_screen.dart` (`PopScope(canPop: !_isDirty, onPopInvokedWithResult: …)`, `_attemptExit`, dialog keys `exercise_editor_unsaved_keep` / `_discard` / `_save`, title "Unsaved changes", body "You have unsaved edits. Save them or discard to return.") Dirty = any difference from the initial state (name, description, modality, discipline, capabilities, muscle selection); a successful save pops without asking.
- D-9 Library Edit (`lib/features/exercise/exercise_library_detail_screen.dart`, `_onEdit`): replaces the rename dialog with `OmniNavigator.push<Exercise>` of `ExerciseEditorScreen(workoutState: workoutState, initialExercise: exercise)`; on a non-null result call `await libraryState.reload()` then `Navigator.of(context).pop()` (back to the list, the same exit the rename used). `_RenameDialog` is deleted if unused afterwards; `renameCustom` in the service/state stays (tested, not UI).

## Readers of what this plan changes (each is a phase item)

- `muscleGroupIds` parameter of create/update/editCustom: `lib/state/workout/exercise_library.dart:163/208`, `workout_state.dart:370/387`, `exercise_library_state.dart:124`, `exercise_library_service.dart:291`, the editor `:220/:229`; tests: grep showed no test passes it (re-grep before editing).
- Editor tests that read texts/types this plan changes: `test/screen_widget_test.dart:3509-3560` (`find.text('Capabilities')` at ~3534 becomes `'CAPABILITIES'`), `test/interaction_flow_test.dart:979-1120` (taps `Resistance / Lifting`, `FilterChip` 'Reps', 'Save exercise', error texts), `test/header_standardization_test.dart:373`, `test/capitalization_defaults_test.dart:46/150/218`.
- Library edit/rename: `lib/features/exercise/exercise_library_detail_screen.dart` `_onEdit`, `_RenameDialog`; keys `exercise_library_edit_button`.
- `OmniNavigator.push` use in `exercise_picker_screen.dart:171` is the pattern.

## Core scenarios (exact fixtures; each fails today for the stated reason)

- S-1 Selection model (`test/muscle_selection_test.dart`, new): empty → `cycle('muscle-quads')` = {quads: primary}; again = {quads: secondary}; again = empty. `{legs: primary}.cycle('muscle-quads')` = {quads: primary} (legs removed). `{quads: primary}.cycle('muscle-legs')` returns an equal selection and `isCovered('muscle-legs')` is true. `{legs: secondary}.cycle('muscle-glutes')` = {glutes: primary}. Chest and Neck cycle independently of each other and of any region. `fromLinks([legs primary, quads primary])` = {quads: primary}. `fromLinks([chest p, triceps s, front-delts s]).toLinks()` = `[chest p, triceps s, front-delts s]`. `{triceps: secondary}`: `hasOnlyAssists` true, `hasPrimary` false; empty: both false; `{chest p, triceps s}`: `hasPrimary` true. Fails today: type does not exist.
- S-2 State API (`test/muscle_editor_state_test.dart`, new, Mock): `WorkoutState.createCustomExercise(name: 'X', modality: 'resistance_lifting', capabilities: ['reps'], muscleLinks: [triceps s, chest p])` → repo links `[chest p, triceps s]`; `updateCustomExercise` with `[quads p]` replaces them; `[triceps s]` alone returns null and `workoutState.error` is non-null; `[]` creates with `[]`; `WorkoutState.getExerciseMuscleLinks(id)` returns them; `ExerciseLibraryService.editCustom(... muscleLinks: [chest p, lats s])` persists exactly that. Fails today: parameter does not exist.
- S-3 Picker (`test/muscle_picker_test.dart`, new, `testWidgets`, Mock-first): chips by key; tap `muscle_chip_muscle-chest` → `muscle_summary_main` text 'Main: Chest' and `muscle_summary_assists` 'Assists: none'; tap again → 'Main: none' / 'Assists: Chest'; third tap → both 'none'. Row order: the six row labels appear top to bottom as in A1 (compare `tester.getTopLeft` y values). 'Whole legs' then 'Quadriceps': after choosing Whole legs and then Quadriceps the summary is 'Main: Quadriceps' and the legs chip semantic label contains 'covered by chosen muscles'; tapping it changes nothing. Semantics labels as D-3. Hint text present. Fails today: widget does not exist.
- S-4 Editor save rules (`test/muscle_editor_screen_test.dart`, new, Mock-first `testWidgets`, surface 600×1400): Resistance, name 'Power Clean', 'Reps' → Triceps tapped twice (assists only) → Save → text 'Pick at least one main muscle.' visible and `repo.getExercises()` count unchanged; add Chest (main) → Save → stored links `[chest p, triceps s]` and the screen popped with the exercise; nothing chosen → Save succeeds with `[]`; Sports modality shows no `muscle_picker_hint`; selecting Chest then switching modality to Sports then back shows an empty selection.
- S-5 Edit mode: `ExerciseEditorScreen(initialExercise: custom with links [chest p, triceps s])` shows 'Main: Chest' and 'Assists: Triceps', title 'Edit Exercise', modality chips disabled; tapping Triceps once more (assists → off) and Save stores `[chest p]`. Fails today: edit mode loads ids only.
- S-6 Modality grid + headers: at width 390 the four modality chips have identical width (`tester.getSize`) and sit two per row (y of first two equal, y of last two equal and greater); at width 320 no overflow exception (`tester.takeException` null); header texts 'MODALITY', 'CAPABILITIES', 'MUSCLES' present as `OmniCardHeader` (count 3 on Resistance, 2 on Sports) and no text 'Muscle groups'. Fails today: wrap layout and raw titles.
- S-7 Scroll to error: surface 390×700, Resistance chosen, scroll to the bottom, tap Save with empty name → after `pumpAndSettle` the 'Exercise name required.' text rect lies inside the viewport. Fails today: stays scrolled to the bottom.
- S-8 Unsaved guard (same file): untouched form + back → pops, no dialog; type a name + back → dialog (key `exercise_editor_unsaved_keep`) appears; keep editing → still on the form; discard → popped; save (valid form) → saved and popped; after a successful Save tap no dialog. Fails today: no guard.
- S-9 Library Edit (`test/pr8_exercise_library_test.dart`, new test): custom exercise → library detail → `exercise_library_edit_button` → editor titled 'Edit Exercise' with the name prefilled → change name → Save → the library list shows the new name and not the old; built-in detail has no edit button (existing test stays). Fails today: Edit opens a rename dialog.
- S-10 Existing editor tests keep passing, with the one predicted text change ('Capabilities' → 'CAPABILITIES' at `screen_widget_test.dart:~3534`).

## Phase outline (all serial; owner, scope)

- Phase A — `crew-builder-app`; `lib/core/**,lib/state/**,test/**`: D-1, D-2 and tests S-1, S-2. Expected red: none.
- Phase B — `crew-builder-app`; `lib/widgets/**,lib/features/exercise/**,test/**`: D-3, D-4, D-5 (the three headers) and tests S-3, S-4, S-5, plus the predicted S-10 text change. Expected red: only the one predicted test (`'Capabilities'`).
- Phase C — `crew-builder-app`; `lib/features/exercise/**,test/**`: D-6, D-7, D-8 and tests S-6, S-7, S-8.
- Phase D — `crew-builder-app`; `lib/features/exercise/exercise_library_detail_screen.dart,test/**`: D-9 and S-9.
- Phase E — `crew-docs-keeper`; `docs/**`: `docs/create_new_exercise.md`, `docs/navigation_and_screens.md` (library Edit entry), the widget catalog part that lists `lib/widgets` pieces (find it via `docs/widget_catalog.md`), `docs/state_management/workout_state.md` (the create/update/getExerciseMuscleLinks rows).
- After E: prover brief for mutations only; the lead applies them; reviewer.

## Code pointers (current lines)

- Editor: `lib/features/exercise/exercise_editor_screen.dart`: state `:26-44` (`_selectedMuscleGroupIds`), `_loadReferenceData :82` (`getExerciseMuscleGroups` at `:99`), `_onModalityChanged :131` (`_selectedMuscleGroupIds.clear()` at `:144`), `_validateAndSave :164`, save calls `:211-230` (`muscleGroupIds: _selectedMuscleGroupIds.toList()..sort()`), `build :250` (modality `Wrap` of `ChoiceChip` at `:283-298`, titles as `Text(…, style: theme.textTheme.titleMedium)` at `:283`, `:362`, `:426`, muscle `FilterChip`s at `:424-450`), `_modalityOptions` list at `:463`.
- State: `lib/state/workout/exercise_library.dart` `createCustomExercise :160` (`await _repository.setExerciseMuscleGroups(exerciseId, muscleGroupIds);` `:189`), `updateCustomExercise :205` (`:228`); `workout_state.dart:361` `getExerciseMuscleGroups`, `:366-395` create/update; `exercise_library_state.dart:118` `editCustom`; service `exercise_library_service.dart:285-310` `editCustom` (`setExerciseMuscleGroups(updated.id, muscleGroupIds)` `:305`).
- Library detail: `exercise_library_detail_screen.dart` `_onEdit :104-135` (rename dialog), `_RenameDialog` further down.
- Guard pattern: `lib/features/period/create_period_screen.dart:287-330`.
- Header: `lib/widgets/layout/omni_card_header.dart`; dialog: `lib/widgets/dialogs/confirmation_dialog.dart:68`.
- Data layer from PR 1: `lib/data/models/muscle_taxonomy.dart`, `ExerciseMuscleLink`/`MuscleRole` in `lib/data/models/models.dart`.

## Progress / Assumption Log / Feedback / Open questions

(empty — architect fills the progress table; builders write the Assumption Log and Feedback.)

---

# Architect expansion (2026-10-14; everything above is the seed, kept verbatim)

## Feature invariants

- `MuscleSelection` is immutable: every `cycle` returns a new value; the editor never mutates a selection in place (D-1).
- The editor never sends a link list `MuscleTaxonomy.normalize` refuses: it checks `hasOnlyAssists` before `toLinks()` (D-1, A5).
- A region and one of its own muscles can never both carry a role: `cycle` removes the region when a muscle gains a role, `fromLinks` drops the region (A3, D-1).
- `MusclePicker` is presentation only: no state or repository access, no `showDialog`, no `showModalBottomSheet` (D-3; the S-3001 ratchets must not move).
- Section headers route through `OmniCardHeader`; no raw `Text` above a card, no raw `Card` (global conventions; `test/ui_standards_contract_test.dart` S-2603).
- Chip colours come from `OmniTheme`/`Theme` only; every chip is at least 40 dp tall; every chip carries a `Semantics` label (docs/design_system.md "Accessibility and shape", "Shape Rule").
- The unsaved guard covers every exit path because `OmniBackHeader`'s back button pops through `Navigator` (D-8, quote below).
- Widget tests are Mock-first: no Hive harness opened inside `testWidgets`, no real `Future.delayed` awaited (repo test-hang rule).
- Docs under `docs/` stay below 52 KB per file; every behaviour sentence names an existing test.

## Existing-functionality impact (all quotes read on disk this run)

| # | Surface | What reads it (verified this run) | Effect | Guard |
|---|---|---|---|---|
| I-1 | `muscleGroupIds` param of create/update/editCustom | `lib/state/workout/exercise_library.dart:163/:208` (defs), `lib/state/workout/workout_state.dart:370/:387` (delegates), `lib/state/exercise/exercise_library_state.dart:124`, `lib/core/services/exercise_library_service.dart:291`, editor `exercise_editor_screen.dart:220/:229`. Tests: grep over `test/` found `state_test.dart:1541/1546` (`createCustomExercise`, does NOT pass `muscleGroupIds`) and `pr8_exercise_library_test.dart:79/85` (`editCustom`, does not pass it) — no test passes the param, so both call sites compile unchanged after the rename | Param becomes `List<ExerciseMuscleLink> muscleLinks = const []`; persistence via `setExerciseMuscleLinks` | S-2 |
| I-2 | Editor tests reading changed texts/types | `test/screen_widget_test.dart:3509-3560` (`find.text('Capabilities')` at `:3534` → `'CAPABILITIES'`); `test/interaction_flow_test.dart:979-1120` (taps `Resistance / Lifting` text, `find.widgetWithText(FilterChip, 'Reps')`, `'Save exercise'`, error texts `'Exercise name required.'`/`'Select a modality.'`); `test/header_standardization_test.dart:373-386` (`OmniBackHeader` + `'New Exercise'`); `test/capitalization_defaults_test.dart:46/150/218` (TextField capitalization) | Only the one predicted text change; D-6 keeps `find.text` taps working, D-5 keeps the header test green | S-10, S-6 |
| I-3 | `find.byType(Chip)`/`FilterChip` searches | `interaction_flow_test.dart` (editor, `FilterChip` 'Reps' — kept); `exercise_row_density_test.dart:204/:241` and `screen_widget_test.dart:7432` use `find.byType(Chip)` on library rows, not the editor — unaffected | None beyond I-2 | S-10 |
| I-4 | Library Edit / rename | `exercise_library_detail_screen.dart` `_onEdit :104-135` (rename dialog), `_RenameDialog` class at file end; tests `pr8_exercise_library_test.dart:599` (built-in has no Edit), `:631` (custom shows Edit + Remove), `:793` (finds the Edit button) | `_onEdit` becomes an editor push (D-9); `:599`/`:631` stay green; `:793`'s test updated by S-9 | S-9 |
| I-5 | `OmniBackHeader` back button | `lib/widgets/layout/omni_back_header.dart:57`: `onPressed: onBack ?? () => Navigator.of(context).pop(),` | Pops through `Navigator`, so `PopScope.onPopInvokedWithResult` sees header back exactly like system back — no extra `onBack` wiring needed | S-8 |
| I-6 | `OmniNavigator.push` | `lib/core/navigation/omni_navigator.dart:12-19`: `static Future<T?> push<T>(BuildContext context, WidgetBuilder builder, {bool fullscreenDialog = false, RouteSettings? settings})` | Signature matches D-9's use; pattern call at `exercise_picker_screen.dart:171-177` | S-9 |
| I-7 | Editor double-save | `exercise_editor_screen.dart:168` `if (_isSaving) return;` and the CTA's `onPressed: _isSaving ? null : _validateAndSave` | Already guards a double tap; S-14 pins it | S-14 |
| I-8 | Which modalities show muscles | `lib/core/constants/modality_config.dart`: `showMuscleGroupsInForm: true` only at `:85` (resistance_lifting) and `:103` (isometric_stretching) | A1's "resistance and isometric/stretching modalities only, as today" holds unchanged | S-4 |
| I-9 | `ExerciseLibraryState.reload` | `lib/state/exercise/exercise_library_state.dart:59` `Future<void> reload() => _reload();` | Exists; D-9's post-save reload uses it | S-9 |
| I-10 | Repo links API | `workout_repository.dart:136/:141` (`getExerciseMuscleLinks`/`setExerciseMuscleLinks`), implemented in both repos; `WorkoutState` has NO links delegate yet (grep: only `getExerciseMuscleGroups` at `workout_state.dart:361`) | D-2 adds the state-level delegates only | S-2 |

## Edge scenarios (continue after S-10)

- S-11 Legacy-shape edit (`test/muscle_editor_screen_test.dart`): a custom exercise whose stored links are the legacy all-primary shape (Hive: `List<String>` row; Mock: staged via `putRawExerciseMuscleLinksForTest` as ids) opens in edit mode showing them as main muscles ('Main: …' lists them), and Save re-stores them normalised. Fails today: edit mode loads ids via `getExerciseMuscleGroups` and cannot round-trip roles; guards `MuscleSelection.fromLinks` + the repo's legacy-shape reader (plan 33 S-4).
- S-12 Missing group id (`test/muscle_picker_test.dart`): pass `groups` without e.g. `muscle-obliques` while the selection contains it → the chip is skipped, the summary still lists it by taxonomy name via `MuscleTaxonomy`, no exception (`tester.takeException` null). Fails today: widget does not exist; guards D-3's "a group id missing from `groups` is skipped".
- S-13 Dirty-then-undone (`test/muscle_editor_screen_test.dart`): type a name, delete it back to the original text, tap back → no dialog (dirty compares against the initial state, not against "ever touched"). Fails today: no guard exists; guards D-8's "any difference from the initial state".
- S-14 Double Save (`test/muscle_editor_screen_test.dart`): tap 'Save exercise' twice without pumping between → exactly one exercise created (`repo.getExercises()` count +1). Fails today: unguarded in test only — the `_isSaving` guard exists (`:168`); the test pins it against regression.
- S-15 Text scale 1.3 at 320 dp (`test/muscle_editor_screen_test.dart`): `textScaleFactor` 1.3, surface 320-wide, Resistance modality → `tester.takeException` null (modality labels ellipsize per D-6, chips wrap). Fails today: the `Wrap` + long labels can overflow at 320 dp with scale 1.3.

## Phases (expanded from the seeded outline; all serial — B, C and D share `exercise_editor_screen.dart` / `test/` files, and A's state switch must land before B's editor rework compiles)

### Phase A — state API + selection model · `crew-builder-app` · `--scope lib/core/**,lib/state/**,lib/core/services/exercise_library_service.dart,lib/features/exercise/exercise_editor_screen.dart,test/**`

1. [ ] Create `MuscleSelection` per D-1 (all API members, `fromLinks`, `toLinks` via `MuscleTaxonomy.normalize`) — `lib/core/utils/muscle_selection.dart` · `MuscleSelection`
2. [ ] Write S-1 — `test/muscle_selection_test.dart` · new
3. [ ] Switch `createCustomExercise`/`updateCustomExercise` to `muscleLinks` + `setExerciseMuscleLinks`; add `getExerciseMuscleLinks` — `lib/state/workout/exercise_library.dart:157/:205` · `createCustomExercise`/`updateCustomExercise`
4. [ ] Switch the two delegates; add `getExerciseMuscleLinks` — `lib/state/workout/workout_state.dart:364/:384` · `createCustomExercise`/`updateCustomExercise`
5. [ ] Switch `editCustom` — `lib/state/exercise/exercise_library_state.dart:118` · `editCustom`
6. [ ] Switch `editCustom` to `setExerciseMuscleLinks` — `lib/core/services/exercise_library_service.dart:284` · `editCustom`
7. [ ] Mechanically switch the editor's two call sites to `muscleLinks:` (each selected id as a primary link) so the tree compiles; the full `MuscleSelection` rework is phase B — `lib/features/exercise/exercise_editor_screen.dart:211-230` · `_validateAndSave`
8. [ ] Write S-2 — `test/muscle_editor_state_test.dart` · new

**Done Criteria A:** `.github/copilot/scripts/macos/gateway.sh lint` (issue count not above baseline) and `gateway.sh test` green for `test/muscle_selection_test.dart`, `test/muscle_editor_state_test.dart`, `test/state_test.dart`, `test/pr8_exercise_library_test.dart`. Expected red: none.
**Predicted Files A:** `lib/core/utils/muscle_selection.dart`, `lib/state/workout/exercise_library.dart`, `lib/state/workout/workout_state.dart`, `lib/state/exercise/exercise_library_state.dart`, `lib/core/services/exercise_library_service.dart`, `lib/features/exercise/exercise_editor_screen.dart`, `test/muscle_selection_test.dart`, `test/muscle_editor_state_test.dart`.

### Phase B — picker + editor rework · `crew-builder-app` · `--scope lib/widgets/**,lib/features/exercise/**,test/**`

1. [ ] Create `MusclePicker` per D-3 (rows/order from `MuscleTaxonomy`, keys, Semantics, ≥40 dp chips) — `lib/widgets/exercise/muscle_picker.dart` · `MusclePicker`
2. [ ] Write S-3 — `test/muscle_picker_test.dart` · new
3. [ ] Editor holds `MuscleSelection`; edit mode loads via `getExerciseMuscleLinks`; modality switch clears it; `_muscleError` on `hasOnlyAssists` — `lib/features/exercise/exercise_editor_screen.dart` · `_ExerciseEditorScreenState`
4. [ ] Replace the three raw titles with `OmniCardHeader('MODALITY' | 'CAPABILITIES' | 'MUSCLES')` and host `MusclePicker` — same file · `build`
5. [ ] Write S-4 and S-5 — `test/muscle_editor_screen_test.dart` · new
6. [ ] Apply the one predicted S-10 text change — `test/screen_widget_test.dart:3534` · `'Capabilities'` → `'CAPABILITIES'`
7. [ ] Run the four existing editor test groups and fix any text fallout beyond the one predicted change (report anything else) — `test/screen_widget_test.dart`, `test/interaction_flow_test.dart`, `test/header_standardization_test.dart`, `test/capitalization_defaults_test.dart`

**Done Criteria B:** `gateway.sh lint` (not above baseline) and `gateway.sh test` green for `test/muscle_picker_test.dart`, `test/muscle_editor_screen_test.dart`, `test/screen_widget_test.dart`, `test/interaction_flow_test.dart`, `test/header_standardization_test.dart`, `test/capitalization_defaults_test.dart`, `test/ui_standards_contract_test.dart`. Expected red before this phase: only the predicted `'Capabilities'` test.
**Predicted Files B:** `lib/widgets/exercise/muscle_picker.dart`, `lib/features/exercise/exercise_editor_screen.dart`, `test/muscle_picker_test.dart`, `test/muscle_editor_screen_test.dart`, `test/screen_widget_test.dart`.

### Phase C — grid, scroll-to-error, unsaved guard · `crew-builder-app` · `--scope lib/features/exercise/**,test/**`

1. [ ] Modality 2×2 grid per D-6 (two `Expanded` chips per row, 8 dp gap, ellipsis) — `lib/features/exercise/exercise_editor_screen.dart` · `build` modality section
2. [ ] Section `GlobalKey`s + `Scrollable.ensureVisible` on the first error (order modality, name, capabilities, muscles) per D-7 — same file · `_validateAndSave`
3. [ ] `PopScope(canPop: !_isDirty)` + `_attemptExit` per D-8, following `create_period_screen.dart:287-330` — same file · `_attemptExit` (new)
4. [ ] Write S-6 — `test/muscle_editor_screen_test.dart`
5. [ ] Write S-7 — same file
6. [ ] Write S-8, S-13, S-14, S-15 — same file

**Done Criteria C:** `gateway.sh lint` (not above baseline) and `gateway.sh test` green for `test/muscle_editor_screen_test.dart`, `test/interaction_flow_test.dart`, `test/screen_widget_test.dart`, `test/ui_standards_contract_test.dart`, `test/docs_indexing_contract_test.dart`. Expected red: none after the phase's own items land (S-6/7/8 fail at the base commit by design — write each test against its item in the same run).
**Predicted Files C:** `lib/features/exercise/exercise_editor_screen.dart`, `test/muscle_editor_screen_test.dart`.

### Phase D — library Edit · `crew-builder-app` · `--scope lib/features/exercise/exercise_library_detail_screen.dart,test/**`

1. [ ] `_onEdit` → `OmniNavigator.push<Exercise>` of `ExerciseEditorScreen(workoutState: workoutState, initialExercise: exercise)`; on non-null result `await libraryState.reload()` then `Navigator.of(context).pop()` — `lib/features/exercise/exercise_library_detail_screen.dart:104` · `_onEdit`
2. [ ] Delete `_RenameDialog` (unused afterwards; `renameCustom` in service/state stays) — same file · `_RenameDialog`
3. [ ] Write S-9 — `test/pr8_exercise_library_test.dart` · new test

**Done Criteria D:** `gateway.sh test` green for `test/pr8_exercise_library_test.dart` (whole file). Expected red: none.
**Predicted Files D:** `lib/features/exercise/exercise_library_detail_screen.dart`, `test/pr8_exercise_library_test.dart`.

### Phase E — docs · `crew-docs-keeper` · `--scope docs/**`

1. [ ] Muscle section: tap-to-cycle, roles, region replacement, secondary-only block, summary — `docs/create_new_exercise.md`
2. [ ] Library "Edit" opens the full editor for custom exercises — `docs/navigation_and_screens.md`
3. [ ] `MusclePicker` entry in the widget-catalog part that lists `lib/widgets` pieces (locate via `docs/widget_catalog.md`) — `docs/widget_catalog.md`
4. [ ] `createCustomExercise`/`updateCustomExercise`/`getExerciseMuscleLinks` rows — `docs/state_management/workout_state.md`

**Done Criteria E:** docs below 52 KB per file; every behaviour sentence names an existing test; `gateway.sh lint` issue count not above baseline (docs-only change, no test run required).
**Predicted Files E:** `docs/create_new_exercise.md`, `docs/navigation_and_screens.md`, `docs/widget_catalog.md`, `docs/state_management/workout_state.md`.

After E: prover brief for mutations only; the lead applies them; reviewer.

## Progress

| Item | Result |
|---|---|
| A1 MuscleSelection | done |
| A2 S-1 tests | done |
| A3 ExerciseLibrary create/update switch | done |
| A4 WorkoutState delegates | done |
| A5 ExerciseLibraryState.editCustom | done |
| A6 Service editCustom | done |
| A7 Editor call-site mechanical switch | done |
| A8 S-2 tests | done |
| B1 MusclePicker | pending |
| B2 S-3 tests | pending |
| B3 Editor MuscleSelection rework | done |
| B4 OmniCardHeader titles | done |
| B5 S-4/S-5 tests | done |
| B6 predicted 'CAPABILITIES' change | done |
| B7 existing editor groups re-run | done |
| C1 modality grid | done |
| C2 scroll-to-error | done |
| C3 unsaved guard | done |
| C4 S-6 test | done |
| C5 S-7 test | done |
| C6 S-8/S-13/S-14/S-15 tests | done |
| D1 _onEdit editor push | done |
| D2 _RenameDialog deleted | done |
| D3 S-9 test | done |
| E1 create_new_exercise.md | done |
| E2 navigation_and_screens.md | done |
| E3 widget_catalog.md | done |
| E4 workout_state.md | done |

## Assumption Log

(crew-builder-app, phase A)

1. `MuscleSelection`'s constructor is `MuscleSelection([Map<String, MuscleRole> roles = const {}])` —
   non-`const`. The brief's `const` spelling is impossible next to "storing an unmodifiable copy"
   (`Map.unmodifiable` is not a const operation, and a const generative constructor cannot share its
   name with the `fromLinks` factory). The behaviour asked for (immutable, defensive copy) is what
   shipped.
2. `idsWith` sorts by `MuscleTaxonomy.orderIndex` and then by id, so unknown ids (index 23) come last
   and two unknown ids have a stable order; same comparator shape as `MuscleTaxonomy._compare`.
3. `hashCode` XORs `Object.hash(id, role)` per entry, so it is order-independent like `==`.
4. `getExerciseMuscleLinks` on the state uses the error copy `'Failed to load exercise muscle links: …'`
   (the existing style of `getExerciseMuscleGroups`, which says "muscle groups").
5. S-2 also covers the `createCustomExercise` secondary-only path (null + non-null
   `workoutState.error`) and `ExerciseLibraryState.editCustom`, which the plan's S-2 fixture text names
   indirectly; both are one extra `test` each.

(crew-builder-app, phase C)

1. Pre-existing overflow found by S-6/S-15, fixed in the editor: the discipline
   `DropdownButtonFormField` lays out every item, so long discipline names overflowed the
   decorator's row by 37 px at 390 dp and 208 px at 320 dp / text scale 1.3. `isExpanded: true`
   plus `maxLines: 1, overflow: TextOverflow.ellipsis` on the item labels (5 changed lines) makes
   both briefed scenarios clean. Outside the briefed edits; reported as a finding.
2. `setEquals` needs `import 'package:flutter/foundation.dart';` — `material.dart` does not
   re-export it (same import as `create_period_screen.dart:1`).
3. S-14 is stronger than briefed. With `MockWorkoutRepository` the first save resolves between the
   two `tester.tap` calls, the route pops, and the second tap misses the CTA (the run logged a
   hit-test miss at `Offset(300.0, 1356.0)`), so "one exercise" passed vacuously. The test now
   gates the write on a `Completer` (`_HangingCreateExerciseRepo.createCount`), asserts
   `createCount == 1` while the first write is still blocked, then releases and checks one new
   exercise plus the pop. The `_validateAndSave` `if (_isSaving) return;` guard is what makes it 1.
4. `PopScope` wraps the main `Scaffold` through a local `editor` (the loading branch keeps its own
   bare `Scaffold`), so no re-indentation of the 180-line body. `canPop: !_isDirty || _isSaving`.
5. `_isDirty` compares raw controller text, not trimmed: whitespace typed into the name or
   description counts as an edit and asks before leaving (S-13's "back to the initial text" case).
6. The four keys sit on a `Column` per section (modality, capabilities, muscles) and on the name
   `TextField`; `_scrollToFirstError` runs in a post-frame callback and uses
   `Scrollable.ensureVisible(..., alignment: 0.1)`. The muscles `Column` includes its error text so
   the whole section scrolls in together.
7. `dart format` could not be run on the editor (the gateway `format` check is `new-files-only`), so
   the new blocks were hand-formatted to the formatter's shape and verified by reading the diff.

## Feedback

- F1 (exit during a save, editor) — fixed: `_attemptExit` returns immediately when `_isSaving` (no dialog, no pop) and `PopScope.canPop` is `!_isDirty && !_isSaving`, so header back and system back both leave the form alone while a write is in flight; guard `test/muscle_editor_screen_test.dart` · S-8 · 'a save in flight blocks both ways out and asks nothing'.
- F2 (failed read of the stored muscles) — fixed: `ExerciseLibrary.getExerciseMuscleLinks` and the `WorkoutState` delegate return `Future<List<ExerciseMuscleLink>?>` (`null` on failure, error on the channel); the editor's `_loadReferenceData` shows `OmniMessage.error(context, 'Could not load this exercise. Try again.')` in a post-frame callback and pops instead of opening an empty picker; guards `test/muscle_editor_state_test.dart` · S-2 · 'a failing links read returns null and sets the state error' and `test/muscle_editor_screen_test.dart` · S-5 · 'a failing links read shows the failure and leaves'.
- F3 (S-6 grid label order) — fixed: the S-6 grid test asserts each row reads left to right in `_modalityOptions` order (Cardio / Endurance left of Resistance / Lifting, Sports left of Isometric / Stretching, second row below the first).
- F4 (chip height) — fixed on the test side: `test/muscle_picker_test.dart` · S-3 · 'every rendered chip is at least 40 dp tall' asserts every rendered `FilterChip` is ≥40 dp; the assertion passes, so no production change was made.
- F5, F6 (docs citations) — this round's `crew-docs-keeper` work, not this brief.
- F7 (the `!_isSaving` term of the editor's `canPop` had no guard) — guarded on the test side, production untouched: `test/muscle_editor_screen_test.dart` · S-8 · 'a save in flight on an unchanged form is not interrupted by the system back' opens edit mode on a custom `resistance_lifting` exercise with capabilities `['reps']` and stored `[chest primary]` links, changes nothing (`_isDirty` is false), starts a save on a `Completer`-gated `updateExercise`, drives `tester.binding.handlePopRoute()` and asserts the editor is still shown and the route has not popped, then releases and asserts the pop carries the saved exercise. Led by the prover mutation 28 (`canPop: true`) leaving the `!_isDirty`-only variant (`canPop: !_isDirty`) unguarded: with the mutation this test must go red (title gone, `host.hasPopped` true), and dropping the `!_isSaving` term is the mutation the lead applies.

## Open questions

1. Phase A's seeded scope (`lib/core/**,lib/state/**,test/**`) omits the editor's two call sites (`exercise_editor_screen.dart:220/:229` pass `muscleGroupIds:`), which do not compile after the state switch. I extended phase A's `--scope` by that one file with a mechanical ids-as-primary change (item A7), replaced by the full rework in phase B. The seeded phase outline text is kept verbatim above.
2. Skeleton naming: the brief says create `.evidence.md`/`.review.md`; the scope budget doc says `<plan-name>.evidence.md`. I followed the brief (dot files in the plan folder).
3. Seed code pointer "save calls `:211-230`" verified: update call starts `:211` (`muscleGroupIds:` at `:220`), create call starts `:223` (`muscleGroupIds:` at `:229`). No discrepancy.
4. Seed claim "tests: grep showed no test passes it" re-verified this run: `state_test.dart:1546` and `pr8_exercise_library_test.dart:85` call create/edit without the muscle parameter. Correct.
5. S-15 (text scale) is a new guard for a rule the design doc marks *unguarded* ("Text size is unguarded — the text-scale audit was never finished"); the prover should treat its red proof accordingly.
