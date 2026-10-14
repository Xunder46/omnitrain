# Evidence: plan 34 muscle editor (skeleton — builders write here)

## Phase E — docs keeper (2026-10-14)

Docs changed:

- `docs/create_new_exercise.md` — muscle section (tap-to-cycle, region replacement/inert region
  chip, assists-only block, nothing-chosen valid), validation list (muscle rule + scroll to first
  error), unsaved-changes guard, modality 2×2 grid, `MODALITY`/`CAPABILITIES`/`MUSCLES` headers,
  library-detail Edit entry point; the two stale claims corrected ("muscle-group ids are sorted
  before persistence" and "the new muscle-group set" → links with roles, normalised order).
- `docs/navigation_and_screens.md` — screen-graph edge `ExerciseLibraryDetailScreen →
  ExerciseEditorScreen (Edit, custom exercises)`; `ExerciseEditorScreen` row gains the two entry
  points; `ExerciseLibraryDetailScreen` row names the editor push.
- `docs/widget_catalog.md` + `docs/widget_catalog/session_widgets.md` — `MusclePicker` entry
  (file, props, presentation-only) in the Session, Picker & Presentation part; lookup-table row;
  `exercise/` added to the directory-structure block.
- `docs/state_management/workout_state.md` — both method tables: `createCustomExercise` /
  `updateCustomExercise` take `List<ExerciseMuscleLink>`; new `getExerciseMuscleLinks` row.
- `docs/design_system.md` — header table row for the exercise editor (`MODALITY`, `CAPABILITIES`,
  `MUSCLES`); "Unsaved work" gains the exercise editor. Nothing else changed in that file.

Tests cited (all read from the test files this run):

- `test/muscle_selection_test.dart` — group `S-1 selection model`: `an empty selection cycles a
  muscle off → main → assists → off`, `a region whose muscles carry a role is covered and inert`,
  `hasPrimary and hasOnlyAssists`.
- `test/muscle_picker_test.dart` — `S-3 chest cycles main, then assists, then none`,
  `S-3 whole legs then quadriceps leaves the legs chip covered`, groups `S-3`/`S-12`.
- `test/muscle_editor_screen_test.dart` — group `S-4 editor save rules`
  (`an assists-only selection is blocked and creates nothing`,
  `saving with nothing chosen succeeds with no links`,
  `Sports hides the picker and a round trip clears the selection`), group `S-5 edit mode`,
  group `S-6 modality grid and headers` (`the four chips fill two equal-width rows at 390 and 320`,
  `the section headers are OmniCardHeader, the old title gone`), group `S-7 scroll to the first
  error` (`a failed save brings the name error into the viewport`), group `S-8 unsaved guard`,
  group `S-13 back to the initial text is not an edit`.
- `test/muscle_editor_state_test.dart` — group `S-2 state API`
  (`createCustomExercise stores the links normalised`, `updateCustomExercise replaces the links`).
- `test/pr8_exercise_library_test.dart` — group `ExerciseLibraryDetailScreen` ·
  `S-9: Edit opens the full editor and saves through it`.

Checks run (gateway):

- `gateway.sh test test/docs_indexing_contract_test.dart` — 13 tests, all passed
  ("All tests passed!").
- `gateway.sh test test/ui_standards_contract_test.dart` — 29 tests, all passed
  ("All tests passed!").
- `gateway.sh lint` — 182 issues found (all pre-existing info notices; matches the plan's A12
  baseline of 182). Log: `.work/gateway/lint-20261014-144544-80528.log`.
## Lead verification (observed)

- Baseline at the base commit `52ede35`: full suite +4588 ~1 passed; `flutter analyze` 182 issues, 0 errors.
- Full suite after each phase: A +4609 ~1; B (widget + editor) +4619 ~1; C +4629 ~1; D +4630 ~1; after the review fix round +4640 ~1; **final +4641 ~1 all passed (3:02)**. `flutter analyze` 182 after every phase. Invariant grep (state/features/widgets/core import of the Hive repository): empty. Diff under `lib/data lib/mock lib/watch watch scripts`: empty.
- Guard proof: the lead applied the prover's 36 mutations by line with a script (apply, run the guarding test, restore, `cmp`): all RED (selection model ×9, picker ×4, editor ×14 incl. each dirty term, scroll to error, back wiring, grid width, three headers, state persistence ×4, library Edit ×3); one picker line (`onSelected: covered ? null : …`) is redundant defence, reported as such. Fix-round guards: exit-while-saving, nullable muscle read (state and screen), and the `canPop` saving term were each proven red by mutation.
- Review: 0 blocker, 0 major, 6 minor, all fixed (2 in docs, 4 in code/tests); plus the `canPop` term guard added after the lead found it unproven.
- Not verified by test: editing a legacy custom exercise with no modality (works by reading the code); `_onEdit` when the editor returns null (covered incidentally).
