# Evidence: plan 35 muscle display

Folded from the builder reports in `.work/crew/2026-10-14-35-muscle-display/`
(A1, A2, B, C1, C2). Baselines and suite lines as each report recorded them.

## Baselines

- `gateway.sh lint`: **182 issues found**, 0 errors, exit 1 expected — identical
  in the A1, A2, B, C1 and C2 reports.
- Full suite before this plan (A1 report): `03:01 +4649 ~1: All tests passed!`
  exit 0.

## Red/green

| Phase | Red (as seen) | Green (as seen) |
|---|---|---|
| A1 | `gateway.sh test test/muscle_display_test.dart` first run: compile failure, `No such file or directory 'lib/core/utils/muscle_display.dart'` (red for the right reason) | `00:00 +7: All tests passed!`; `test/muscle_picker_test.dart` `00:00 +6`; combined with `muscle_editor_screen_test.dart` `00:03 +37`; full suite `03:01 +4649 ~1` exit 0 |
| A2 | none appeared (the predicted red in `exercise_row_density_test.dart` / `screen_widget_test.dart` did not) | `test/muscle_filter_picker_test.dart` `00:03 +14`; combined run with the two density/screen files + `pr8` + ui-standards `00:13 +320`; full suite `03:03 +4663 ~1` exit 0 |
| B | first run of the new S-4 file failed to compile: `A value of type 'Finder' can't be returned from a function with return type 'Matcher'` (helper return type, fixed before the green run) | combined run `02:02 +58: All tests passed!`; with ui-standards `00:39 +39`; full suite `02:58 +4673 ~1` exit 0 |
| C1 | none | `catalog_refresh` + `pr7` + `pr8` + `exercise_row_density` `00:02 +71`; muscle files + ui-standards `+61`; `muscle_editor_state_test.dart` alone `00:00 +8`. Full suite not run (the lead's) |
| C2 | none | `test/muscle_links_storage_test.dart` `00:00 +18`; migration/filter/referential combined `00:03 +72`; full suite `02:53 +4673 ~1` exit 0 |

## Prove-red verdicts

Not run by the builders (proof is not the builder's job); no prove-red verdict
is recorded in any of the five reports. B's INV-4 guard is covered by the
fourth body-level S-4 case the builder added beyond the brief's three
(primary empty, secondary present).

## Invariant checks (every phase)

`import .*hive_workout_repository` over `lib/state lib/features lib/widgets
lib/core` → no matches, in all five reports.

## C2 grep verdict

`getExerciseMuscleGroups|setExerciseMuscleGroups` over `lib` and `test`
(dart files) → **no matches** after C2. Remaining non-code mentions at C2
time: `docs/data_models.md:230` (Phase D item 2) and
`scripts/sqlite_schema.sql:855` (a comment; outside every phase's scope —
see Open questions).

## Phase D (docs keeper)

- `docs/future-work.md`: taxonomy entry deleted; title, intro and `---` kept;
  `Nothing is deferred at the moment.` added.
- `docs/data_models.md`: legacy-pair paragraph removed; `S-13` citation
  reworded to the C2 test name; display rules added with citations to
  `test/muscle_display_test.dart`, `test/muscle_filter_picker_test.dart`,
  `test/exercise_detail_muscle_groups_test.dart`.
- `docs/navigation_and_screens.md`: picker row (grouped filter, main-muscle
  chips) and the two detail rows (Primary/Secondary) updated with citations.
- `docs/widget_catalog/session_widgets.md`: `MusclePicker` row order now
  sourced from `lib/core/utils/muscle_display.dart`; `ExercisePickerScreen`
  entry updated. `ExerciseDetailViewBody` is not catalogued in this file
  (grep: no match) — nothing to update there.
- `docs/state_management/workout_state.md`: grep for
  `getExerciseMuscleGroups|setExerciseMuscleGroups` → no rows; no change.
- `docs/exercise_ranking.md`, `docs/db_integration.md`,
  `docs/constants_reference.md`, `docs/create_new_exercise.md`: grep for
  `getExerciseMuscleGroups|setExerciseMuscleGroups|muscleGroups:` → no stale
  mention; no change. (`exercise_ranking.md:20/:25` name the live
  `muscleGroupIds` filter parameter, which still exists on
  `searchExercises`/`getExercisesRankedForModality`.)
- Checks: `gateway.sh test test/docs_indexing_contract_test.dart` and
  `test/ui_standards_contract_test.dart` green; `gateway.sh lint` at baseline
  182 — see the phase D report for the pasted output.


## Lead verification (observed)

- Baseline at the base commit `7c89489`: full suite +4642 ~1; analyze 182 / 0 errors.
- Full suite after each phase (builder runs, re-run by the lead at A... C2 and the end): A1 +4649, A2 +4663, B +4673, C1/C2 +4673, after the comment fixes **+4674 ~1 all passed (3:05)**. `flutter analyze` 182 after every phase. `grep getExerciseMuscleGroups|setExerciseMuscleGroups` over `lib test scripts`: zero. Invariant grep (state/features/widgets/core import of the Hive repository): empty. Diff under `lib/features/stats lib/features/session lib/watch watch`: empty.
- Guard proof: the lead applied the prover's 25 mutations (plus one companion on the picker's 'All' label) by line with a script: all RED (display helper ×7, picker widget ×2, dropdown ×6, row chips ×2, detail ×8, library detail ×2, normalize region drop ×1); every file restored.
- Review: 0 blocker, 0 major, 2 minor (two stale comments) — fixed. The reviewer also confirmed all 12 acceptance criteria of the original brief across the three PRs.
- Look on a device (iPhone 17 Pro simulator): the Muscle filter opens as All / Chest / Neck / Back (bold) with Lats, Traps, Lower back indented / Shoulders … / Arms … / Core …; choosing Triceps gave 6 exercises (no bench press) and the closed field read "Triceps"; picker rows show only main muscles (Arnold Press: Front delts); the Dip detail shows Primary Triceps, Chest and Secondary Front delts.
