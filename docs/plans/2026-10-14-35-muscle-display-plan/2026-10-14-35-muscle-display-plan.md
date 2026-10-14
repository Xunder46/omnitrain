# Plan 35 — Muscle hierarchy, PR 3 of 3: how muscles are shown and filtered

Status: SEEDED by the lead. Base commit `7c89489` (PR 1 `fd57bf6`, PR 2 `0983075` + `7c89489`; plans 33 and 34 in `docs/plans/`).
Owner answers carried over: list rows show MAIN muscles only; ranking order is not touched; Chest and Neck are standalone; the picker's region order matches the editor (Chest and neck, Back, Shoulders, Arms, Core, Legs). The owner reviewed the PR 2 screenshots and asked for this PR's content in plain words: (1) the picker's Muscle filter grouped by region, (2) list rows with main muscles only, (3) the detail view with Primary and Secondary lists, (4) cleanup of the old muscle calls and the last doc edit.

## Goal and acceptance

- A1. Picker "Muscle" filter lists "All", then Chest, Neck (standalone, no indent), then Back, Shoulders, Arms, Core, Legs, each region followed by its muscles in taxonomy order, indented one step; the closed field shows the plain name.
- A2. Choosing a region returns exercises with a main link to the region or any of its muscles; choosing a muscle returns only exercises with a main link to exactly it (the data-layer rule from PR 1, now visible in the picker).
- A3. Rows in the picker and in the library list show only MAIN muscles (a region-only tag shows the region name, e.g. "Legs"); a row never shows a secondary-only muscle.
- A4. Exercise detail (read-only view and library detail) shows a "Primary" row and a "Secondary" row of muscle chips; an empty row is hidden; with no muscles the whole section is hidden (key `exercise_detail_muscles_section` stays on the section).
- A5. A bench press shows Chest under Primary and Triceps, Front delts under Secondary; a tennis match shows Legs, Shoulders, Core under Primary and no Secondary row.
- A6. The old muscle calls are gone: `getExerciseMuscleGroups`/`setExerciseMuscleGroups` no longer exist on `WorkoutRepository`, `MockWorkoutRepository`, `HiveWorkoutRepository`, `ExerciseLibrary`, `WorkoutState`; nothing in `lib/` or `test/` calls them.
- A7. `docs/future-work.md` no longer contains the muscle-group taxonomy entry (the file stays: it is a record file listed in `test/docs_indexing_contract_test.dart`); data-model, navigation, widget and state docs describe the new display; docs contract tests green.
- A8. Set logging, Stats, watch: untouched. `flutter analyze` not above 182 issues.

## Decision Ledger

- D-1 One display helper, `lib/core/utils/muscle_display.dart` (pure): `kMuscleStandaloneIds = ['muscle-chest','muscle-neck']` and `kMuscleRegionOrder = ['muscle-back','muscle-shoulders','muscle-arms','muscle-core','muscle-legs']` (the one source of the display order; `MusclePicker` is changed to read these instead of its own literal order); `class MuscleFilterEntry { final MuscleGroup group; final int depth; }`; `List<MuscleFilterEntry> muscleFilterEntries(List<MuscleGroup> groups)` (standalone ids first, then each region followed by `MuscleTaxonomy.musclesOf(region)`; depth 0 for standalone and regions, 1 for muscles; ids missing from `groups` are skipped); `List<MuscleGroup> musclesWithRole(List<ExerciseMuscleLink> links, List<MuscleGroup> groups, MuscleRole role)` (links of that role in link order, mapped to the group, a link whose group is missing is skipped); `List<String> muscleNamesWithRole(...)` = the names of the above.
- D-2 Picker dropdown (`lib/features/exercise/exercise_picker_screen.dart` ~lines 328-390): items built from `muscleFilterEntries(_muscleGroups)`: `DropdownMenuItem(value: id, child: Padding(padding: EdgeInsets.only(left: 16.0 * depth), child: Text(name, ... style as today, region/standalone rows `fontWeight: FontWeight.w600`)))`; `selectedItemBuilder` returns the plain name `Text` (no indent) for every item including the "All" item; the filter semantics (`muscleGroupIds: [id]`) are the PR 1 data-layer ones: nothing changes in the repositories.
- D-3 Row chips: the picker's `_exerciseMuscleGroupsCache` (`Map<String, List<MuscleGroup>>`) becomes `_exerciseMuscleLinksCache` (`Map<String, List<ExerciseMuscleLink>>`) filled through `workoutState.getExerciseMuscleLinks` (nullable result → treated as empty); the chips are `muscleNamesWithRole(links, _muscleGroups, MuscleRole.primary)`; the same in `exercise_library_screen.dart` (`_exerciseMuscleGroupsCache`, `_warmCache`, the `_TagChip` row ~line 276).
- D-4 Detail: `ExerciseDetailViewBody` (in `lib/features/exercise/exercise_detail_view_screen.dart`) replaces the parameter `List<MuscleGroup> muscleGroups` with `List<MuscleGroup> primaryMuscles` and `List<MuscleGroup> secondaryMuscles` (both required); it renders, inside the existing `exercise_detail_muscles_section` key (a `Column` that exists only when at least one list is non-empty), a `_DetailRow(label: 'Primary', key: Key('exercise_detail_primary_muscles'))` and, if non-empty, `_DetailRow(label: 'Secondary', key: Key('exercise_detail_secondary_muscles'))`. Both callers (`ExerciseDetailViewScreen._loadReference` and `ExerciseLibraryDetailScreen._loadReference`) load `getExerciseMuscleLinks` (nullable → empty) and pass `musclesWithRole` for each role.
- D-5 Removal of the old calls: phase C1 removes `ExerciseLibrary.getExerciseMuscleGroups` and `WorkoutState.getExerciseMuscleGroups` and migrates the non-data tests that call the repository's old pair; phase C2 removes `getExerciseMuscleGroups`/`setExerciseMuscleGroups` from `WorkoutRepository`, `MockWorkoutRepository`, `HiveWorkoutRepository` (and the stale "removed by plan 34" doc comment) and rewrites the legacy-wrapper tests in `test/muscle_links_storage_test.dart` onto `setExerciseMuscleLinks`/`getExerciseMuscleLinks`. The behaviour "a link whose group row is missing is skipped" moves to the display helper (S-1) and a screen test (S-3).
- D-6 `docs/future-work.md`: delete the whole "Muscle-group taxonomy: flat list → region/muscle hierarchy" entry; keep the file title, the intro sentences and add one line "Nothing is deferred at the moment."

## Readers of what this plan changes

- `getExerciseMuscleGroups` callers in `lib/`: `exercise_library_detail_screen.dart:76`, `exercise_picker_screen.dart:120`, `exercise_detail_view_screen.dart:82`, `exercise_library_screen.dart:302`, state wrappers `exercise_library.dart:318`, `workout_state.dart:361`; repositories (`workout_repository.dart:149/153`, `mock_workout_repository.dart:1018/1027`, `hive_workout_repository.dart:1742/1751`).
- Tests that call the old pair (13 hits in 5 files): `test/catalog_refresh_test.dart`, `test/muscle_links_storage_test.dart`, `test/pr8_exercise_library_test.dart`, `test/pr7_exercise_details_view_test.dart`, `test/exercise_row_density_test.dart` (re-grep before editing).
- `ExerciseDetailViewBody(... muscleGroups: …)`: `exercise_library_detail_screen.dart:~170`, `exercise_detail_view_screen.dart:~118`, `test/exercise_details_capability_grouping_test.dart:71-74`.
- Detail tests that assert the old single row: `test/pr7_exercise_details_view_test.dart` (~309-406: section key `exercise_detail_muscles_section`), `test/pr8_exercise_library_test.dart` (detail screens).
- `exercise_row_density_test.dart` (chip counts 3 and 5 on picker/library rows, fixtures seeded as all-primary) and `screen_widget_test.dart:~7411/~7577` (picker chip styling and the 'All' dropdown text).
- Docs: `docs/data_models.md` (MuscleGroup section names the legacy pair and PR-2 UI state), `docs/navigation_and_screens.md`, `docs/widget_catalog/session_widgets.md`, `docs/state_management/workout_state.md`, `docs/future-work.md`, `docs/exercise_ranking.md` (mentions the filter only: check).

## Core scenarios (exact fixtures)

- S-1 Helper (`test/muscle_display_test.dart`, new): groups = all 23 `MuscleTaxonomy.entries` as `MuscleGroup`s. `muscleFilterEntries` ids in order: chest, neck, back, lats, traps, lower-back, shoulders, front-delts, side-delts, rear-delts, arms, biceps, triceps, forearms, core, abs, obliques, legs, quads, hamstrings, glutes, calves, adductors (ids with `muscle-` prefix) with depths 0 for chest, neck and the five regions and 1 for the 16 muscles; without `muscle-obliques` in `groups` the entry is absent and nothing else changes. Links of bench-press `[chest p, triceps s, front-delts s]`: `muscleNamesWithRole(.., primary)` = ['Chest'], `secondary` = ['Triceps','Front delts']; tennis-match `[legs p, shoulders p, core p]` primary = ['Legs','Shoulders','Core'], secondary = []; a link to an id with no group is skipped; empty links → [].
- S-2 Picker filter (`test/muscle_filter_picker_test.dart`, new, Mock-first `testWidgets`; pattern: `screen_widget_test.dart` group 'ExercisePickerScreen'): open the Muscle dropdown: item texts top to bottom are 'All', 'Chest', 'Neck', 'Back', 'Lats', 'Traps', 'Lower back', 'Shoulders', 'Front delts', 'Side delts', 'Rear delts', 'Arms', 'Biceps', 'Triceps', 'Forearms', 'Core', 'Abs', 'Obliques', 'Legs', 'Quadriceps', 'Hamstrings', 'Glutes', 'Calves', 'Adductors'; 'Quadriceps' sits further right (`getTopLeft().dx`) than 'Legs', 'Legs' and 'Chest' at the same x. With the search text narrowed (e.g. 'Squat', 'Tennis', 'Bench Press', 'Pressdown') choose Legs → 'Barbell Back Squat' and 'Tennis Match' each found; choose Quadriceps → squat found, Tennis Match absent; choose Triceps with search 'Press' → 'Triceps Pressdown' present, 'Barbell Bench Press' absent. After a selection the closed field shows the plain name ('Quadriceps', no indent).
- S-3 Row chips (same file or `test/exercise_row_density_test.dart`): picker row for 'Barbell Bench Press' has a chip 'Chest' and no chip 'Triceps' and none 'Front delts'; 'Arnold Press' has 'Front delts' and no 'Triceps', 'Side delts', 'Rear delts'; 'Tennis Match' has 'Legs', 'Shoulders', 'Core'; the library list row for 'Barbell Bench Press' likewise. A custom exercise with `[chest p, lats s]` shows 'Chest' only. A link whose group is missing from `workoutState.muscleGroups` shows no chip and does not throw.
- S-4 Detail (`test/exercise_detail_muscle_groups_test.dart`, new, plus updates to pr7/pr8 tests): `ExerciseDetailViewBody` with primary [Chest], secondary [Triceps, Front delts] → key `exercise_detail_primary_muscles` holds chips Chest; `exercise_detail_secondary_muscles` holds Triceps and Front delts; with secondary empty the secondary row is absent; with both empty the section key is absent. Through the screens: bench press (Mock repo seed) and tennis match (`exercise_detail_secondary_muscles` absent, primary chips Legs, Shoulders, Core) via `ExerciseDetailViewScreen` and `ExerciseLibraryDetailScreen`; an exercise with no muscles (Easy Run) has no section.
- S-5 Legacy removal: the tree compiles with the methods deleted; `test/muscle_links_storage_test.dart` keeps its links-API tests (S-4, S-10, S-13 rewritten as "setExerciseMuscleLinks drops a region next to its muscle" etc.); "missing group skipped" now lives in S-1/S-3; `grep -rn "getExerciseMuscleGroups\|setExerciseMuscleGroups" lib test` returns nothing.
- S-6 Docs: `docs/future-work.md` has no `Muscle-group taxonomy` heading (a text check by the reviewer); `test/docs_indexing_contract_test.dart` green.

## Phase outline (serial)

- Phase A1 — `crew-builder-app`; `lib/core/utils/**,lib/widgets/exercise/**,test/**`: D-1 (helper, `MusclePicker` reads the shared order) + S-1.
- Phase A2 — `crew-builder-app`; `lib/features/exercise/exercise_picker_screen.dart,lib/features/exercise/exercise_library_screen.dart,test/**`: D-2, D-3 + S-2, S-3 (picker and library rows); update `screen_widget_test.dart`/`exercise_row_density_test.dart` only if a predicted red appears.
- Phase B — `crew-builder-app`; `lib/features/exercise/exercise_detail_view_screen.dart,lib/features/exercise/exercise_library_detail_screen.dart,test/**`: D-4 + S-4 and the pr7/pr8/capability-grouping test updates.
- Phase C1 — `crew-builder-app`; `lib/state/**,test/**`: remove the two state wrappers; migrate non-data tests (`catalog_refresh_test`, `pr7_exercise_details_view_test`, `pr8_exercise_library_test`, `exercise_row_density_test`) off the old pair.
- Phase C2 — `crew-builder-data`; `lib/data/**,test/**`: remove the old pair from the interface and both repositories; rewrite `test/muscle_links_storage_test.dart`'s legacy tests; fix the stale comment.
- Phase D — `crew-docs-keeper`; `docs/**`: D-6 and the doc updates under "Readers".
- After D: prover brief for mutations, the lead applies them, reviewer, and the lead looks at the screens on the simulator (picker dropdown, rows, both detail screens) before reporting.

## Code pointers (current lines)

- Picker: `exercise_picker_screen.dart`: `_exerciseMuscleGroupsCache :42`, `_searchExercises :105-130` (cache fill at `:118-125`), dropdown `:328-390` (items `:366-380`), row chips `:504` (`final muscleGroups = _exerciseMuscleGroupsCache[exercise.id] ?? [];`) and `:607-620` (`...muscleGroups.map((mg) => Chip(...))`).
- Library list: `exercise_library_screen.dart`: cache `:46`, `_buildRow :201-` (`final muscleGroups = _exerciseMuscleGroupsCache[exercise.id] ?? const [];`), chips `:262-280`, `_warmCache :299-309`.
- Detail: `exercise_detail_view_screen.dart`: state `:60-90`, body fields `:160-175`, `hasMuscles :192`, muscles section `:302-315`; library detail `exercise_library_detail_screen.dart` state `:50-80`, body call `:168-175`.
- State: `exercise_library.dart:318-327` (old getter), `:327-337` (links getter), `workout_state.dart:361-366`.
- Repos: `workout_repository.dart:140-160`; Hive `:1740-1760`; Mock `:1015-1035`.
- Editor picker widget: `lib/widgets/exercise/muscle_picker.dart` (the row literal order near the top; `MusclePicker` keys unchanged).
- Docs: `docs/future-work.md` (the only entry), `docs/data_models.md` MuscleGroup section, `docs/navigation_and_screens.md` picker/detail rows.

## Progress / Assumption Log / Feedback / Open questions

(empty — architect fills the progress table; builders write the Assumption Log and Feedback.)

---

# Architect expansion (2026-10-14; everything above is the seed, kept verbatim)

## Feature invariants

- INV-1 `lib/core/utils/muscle_display.dart` is pure: it imports only the models and `muscle_taxonomy.dart` (sibling precedent `lib/core/utils/muscle_selection.dart`); no Flutter imports.
- INV-2 The display order has one source: `kMuscleStandaloneIds`/`kMuscleRegionOrder` in the helper. `MusclePicker`'s `_rows`/`_standaloneIds` literals (`lib/widgets/exercise/muscle_picker.dart:44-55`) become reads of them; no second literal may appear anywhere.
- INV-3 A row chip is rendered only from a `primary` link (`muscleNamesWithRole(..., MuscleRole.primary)`); a secondary-only muscle never appears on a row (A3).
- INV-4 The detail muscles section exists only when at least one of primary/secondary is non-empty; the section key `exercise_detail_muscles_section` is unchanged (A4).
- INV-5 Widget tests are Mock-first; Hive is seeded in `setUp`, never opened inside `testWidgets` (a widget test that opens the Hive harness hangs at ~0% CPU).
- INV-6 Theme tokens only — no local colour/size overrides on new chips or dropdown rows. The closed-field 'All' Text keeps an explicit small style: `test/screen_widget_test.dart:7600` iterates every `find.text('All')` widget and asserts fontSize < 14.
- INV-7 Docs: every behaviour sentence names an existing test; files stay under the 64 KiB ceiling enforced by `test/docs_indexing_contract_test.dart` (`_maxDocBytes`, :52).
- INV-8 `flutter analyze` stays at the 182-issue baseline (A8; measured this run: "182 issues found. (ran in 4.2s)", all info notices, exit 1 expected).

## Impact table (existing functionality this plan touches)

| # | Touched surface | What already reads it (search run this session) | Effect | Guarded by |
|---|---|---|---|---|
| I-1 | `MusclePicker._rows`/`_standaloneIds` (`lib/widgets/exercise/muscle_picker.dart:44-55`) | `test/muscle_picker_test.dart` groups S-3/S-12 (row order :84-105, missing-group :186-198) | Same order, now sourced from the helper constants; no test change expected | S-1, D-1 |
| I-2 | Picker dropdown items (`exercise_picker_screen.dart:366-380`) | `test/screen_widget_test.dart:7600` ('All' fontSize), `:7411` (chip styling) | Items become the indented region/muscle list; closed field via `selectedItemBuilder` stays plain | S-2, D-2 |
| I-3 | Picker row chips (`exercise_picker_screen.dart:504, :607-620`) | `test/exercise_row_density_test.dart:63` (fixtures all-primary; chip counts 3 and 5) | Chips come from primary links; all-primary fixtures keep their counts | S-3, D-3 |
| I-4 | Library row chips (`exercise_library_screen.dart:262-280`, `_warmCache :299-309`) | same density test (library row) | Same as I-3 | S-3, D-3 |
| I-5 | `ExerciseDetailViewBody.muscleGroups` + section (`exercise_detail_view_screen.dart:160-175, :192, :302-315`) | `test/pr7_exercise_details_view_test.dart:354/:404` (section key), `test/exercise_details_capability_grouping_test.dart:71-74` (`muscleGroups: const []`) | Param replaced by `primaryMuscles`/`secondaryMuscles`; grouping test updated in phase B | S-4, D-4 |
| I-6 | `ExerciseLibraryDetailScreen._loadReference`/body call (`:68-78, :168-175`) | `test/pr8_exercise_library_test.dart` detail group | Loads links, passes the two role lists | S-4, D-4 |
| I-7 | State wrappers `ExerciseLibrary.getExerciseMuscleGroups` (`exercise_library.dart:318-325`), `WorkoutState.getExerciseMuscleGroups` (`workout_state.dart:361-364`) | the screens in I-2..I-6 (migrated first) | Removed in C1 after the screens stop calling it | S-5, D-5 |
| I-8 | Repo pair (`workout_repository.dart:149/:153`, mock `:1018-1033`, hive `:1742-1757`) | 13 test hits in 5 files (grep this session: `catalog_refresh_test.dart:149/216/232/242`, `muscle_links_storage_test.dart:124/139/150/161/177`, `pr8_exercise_library_test.dart:938`, `pr7_exercise_details_view_test.dart:379`, `exercise_row_density_test.dart:63`) | Removed in C2 after C1 migrates the tests | S-5, D-5 |

CHECK-in-code (framework claims, quoted from files read this run):

- `selectedItemBuilder` is unused today: grep over `lib/` and `test/` → no matches. D-2 introduces it; no existing test can go red from its arrival.
- Open-menu dropdown items are text-findable: `test/food_form_orphan_category_test.dart:412` `find.text(proteins.name).last` after tapping the dropdown by key; `test/muscle_editor_screen_test.dart:800` `find.text('Running').last` after `find.byType(DropdownButtonFormField<String?>)`. S-2 uses the same pattern (`.last` because the closed field also shows the text).
- The 'All' fontSize guard: `test/screen_widget_test.dart:7600` `.widgetList<Text>(find.text('All'))` — D-2's `selectedItemBuilder` Text must keep an explicit small style (expected-green constraint on I-2).
- Geometry precedent: `test/muscle_editor_screen_test.dart:437` `final lefts = [for (final tile in tiles) tester.getTopLeft(tile).dx];` — S-2's indent assertion (`Quadriceps` dx > `Legs` dx) follows it.

## Edge scenarios (appended after the seeded S-1..S-6)

- S-7 Long muscle list wraps in a row (in `test/muscle_filter_picker_test.dart`, picker row): fixture 'Volleyball Match' (seed `lib/mock/seed_data.dart:4582`, primary shoulders, arms, core, legs) — the row shows four primary chips plus its discipline chip; the chip row is a `Wrap`, so the fifth chip wraps to the next line instead of overflowing. Expected: all four muscle chips present, `tester.takeException()` null, chips on two lines. Why it can fail: if the chips were a `Row` the fifth chip overflows. Prover mutation: change the `Wrap` at `exercise_picker_screen.dart:607-620` to a `Row` → overflow exception, test red.
- S-8 Custom exercise with only a region tag shows the region name (S-3's file): fixture custom exercise with links `[legs primary]` written through `setExerciseMuscleLinks` → the picker row shows chip 'Legs' (the region's own name), no crash. Why it can fail: a helper that skipped region ids would drop the chip. Prover mutation: make `muscleNamesWithRole` skip region ids → chip disappears, test red.
- S-9 Exercise with two regions (S-3's file): fixture 'Barbell Deadlift' (seed `:4481`, primary glutes, hamstrings, lower-back) → chips 'Glutes', 'Hamstrings', 'Lower back' in link order, all primary, no secondary chip. Prover mutation: order chips by taxonomy instead of link order → 'Lower back' first, test red.
- S-10 Dropdown 'All' resets the filter (`test/muscle_filter_picker_test.dart`): choose 'Quadriceps' (list narrows to the squat), then choose 'All' → the full list returns and the closed field shows 'All'. Why it can fail: the grouped items change the value space; a broken 'All' mapping keeps the list narrowed. Prover mutation: drop the 'All' item or map it to a non-null sentinel → test red.
- S-11 Clearing filters resets the dropdown (same file): choose 'Quadriceps', tap the screen's Clear Filters action (`_clearFilters`, `exercise_picker_screen.dart:139-148`) → the closed field shows 'All' again and the list is unfiltered. Prover mutation: `_clearFilters` stops resetting `_selectedMuscleGroupId` → field keeps 'Quadriceps', test red.

Acceptance coverage: A1→S-2, A2→S-2/S-10, A3→S-3/S-7/S-8/S-9, A4→S-4, A5→S-4, A6→S-5, A7→S-6, A8→INV-8.

## Phases

Serial chain: A1 → A2 → B → C1 → C2 → D; no two phases run in parallel. A2 and B both consume A1's helper (`muscleNamesWithRole`); C1 removes the state wrappers only after A2/B migrated every screen off `getExerciseMuscleGroups`; C2 removes the repository pair only after C1 migrated the tests; D documents the finished code. A2 and B have disjoint `lib/` write scopes but overlap in `test/**`, so they still run one after the other.

### Phase A1 — display helper + MusclePicker source (crew-builder-app)

1. [ ] Create the pure helper with the D-1 API — `lib/core/utils/muscle_display.dart` · `muscleFilterEntries`, `musclesWithRole`, `muscleNamesWithRole`, `kMuscleStandaloneIds`, `kMuscleRegionOrder`, `MuscleFilterEntry`
2. [ ] Write S-1 red-first (helper absent → compile error is the red) — `test/muscle_display_test.dart` · all S-1 fixtures
3. [ ] Replace the literal row order with reads of the shared constants — `lib/widgets/exercise/muscle_picker.dart` · `_rows` (:44-52), `_standaloneIds` (:54-55)
4. [ ] Run the picker widget tests to prove the order is unchanged — `test/muscle_picker_test.dart` · S-3/S-12 groups

Done criteria: gateway `test -- test/muscle_display_test.dart test/muscle_picker_test.dart` green; `prove-red` for S-1 at the base commit.
Predicted files: `lib/core/utils/muscle_display.dart`, `lib/widgets/exercise/muscle_picker.dart`, `test/muscle_display_test.dart`.
Write scope: `lib/core/utils/**,lib/widgets/exercise/**,test/**`.

### Phase A2 — picker + library dropdown and rows (crew-builder-app)

1. [x] Build dropdown items from `muscleFilterEntries` with depth indent and w600 region/standalone rows — `lib/features/exercise/exercise_picker_screen.dart` · dropdown items (:366-380)
2. [x] Add `selectedItemBuilder` returning the plain-name Text (incl. 'All') with the current small style — same file · dropdown (:328-390)
3. [x] Swap the cache to links and render primary-name chips — same file · `_exerciseMuscleGroupsCache` (:42), fill (:118-125), row chips (:504, :607-620)
4. [x] Same cache/chip swap in the library list — `lib/features/exercise/exercise_library_screen.dart` · cache (:46), `_buildRow` (:201), chips (:262-280), `_warmCache` (:299-309)
5. [x] Write S-2 red-first (items are flat today) — `test/muscle_filter_picker_test.dart` · S-2 group
6. [x] Write S-3, S-7, S-8, S-9 red-first (chips show secondary today) — same file · S-3/S-7/S-8/S-9
7. [x] Write S-10, S-11 green (prover supplies the mutations) — same file · S-10/S-11
8. [x] Update `exercise_row_density_test.dart` only if a predicted red appears (fixtures all-primary → counts 3/5 expected green) — no predicted red appeared, file unchanged

Done criteria: gateway `test -- test/muscle_filter_picker_test.dart test/exercise_row_density_test.dart test/screen_widget_test.dart` green; `prove-red` for S-2/S-3 at the pre-A2 commit; lint ≤ 182.
Predicted files: the two screens, `test/muscle_filter_picker_test.dart`, possibly `test/exercise_row_density_test.dart`.
Write scope: `lib/features/exercise/exercise_picker_screen.dart,lib/features/exercise/exercise_library_screen.dart,test/**`.

### Phase B — detail Primary/Secondary rows (crew-builder-app)

1. [x] Replace `muscleGroups` with `primaryMuscles`/`secondaryMuscles` (both required) and render the two `_DetailRow`s inside the section key — `lib/features/exercise/exercise_detail_view_screen.dart` · `ExerciseDetailViewBody` fields (:160-175), `hasMuscles` (:192), section (:302-315)
2. [x] Load links and pass `musclesWithRole` per role — same file · `_loadReference` (:75-90)
3. [x] Same load + two-list call — `lib/features/exercise/exercise_library_detail_screen.dart` · `_loadReference` (:68-78), body call (:168-175)
4. [x] Write S-4 red-first (single row today) — `test/exercise_detail_muscle_groups_test.dart` · S-4
5. [x] Update the pr7 assertions to the two-row keys — no change needed: pr7 asserts only the unchanged section key (`exercise_detail_muscles_section`), green as is
6. [x] Update `muscleGroups: const []` to the two empty lists — `test/exercise_details_capability_grouping_test.dart` · :71-74
7. [x] Update pr8 detail assertions if red — no change needed: the pr8 detail group stayed green

Done criteria: gateway `test -- test/exercise_detail_muscle_groups_test.dart test/pr7_exercise_details_view_test.dart test/exercise_details_capability_grouping_test.dart test/pr8_exercise_library_test.dart` green; `prove-red` for S-4 at the pre-B commit.
Predicted files: the two detail files, `test/exercise_detail_muscle_groups_test.dart`, `test/pr7_exercise_details_view_test.dart`, `test/exercise_details_capability_grouping_test.dart`, possibly `test/pr8_exercise_library_test.dart`.
Write scope: `lib/features/exercise/exercise_detail_view_screen.dart,lib/features/exercise/exercise_library_detail_screen.dart,test/**`.

### Phase C1 — remove the state wrappers, migrate non-data tests (crew-builder-app)

1. [x] Migrate the old-pair reads to `getExerciseMuscleLinks` — `test/catalog_refresh_test.dart` · :149/:216/:232/:242
2. [x] Migrate the old-pair call — `test/pr7_exercise_details_view_test.dart` · :379
3. [x] Migrate the old-pair call and fix the stale comment at :162 (names `setExerciseMuscleGroups`, test uses links) — `test/pr8_exercise_library_test.dart` · :938, :162
4. [x] Migrate the fixture seeding — `test/exercise_row_density_test.dart` · :63
5. [x] Delete `ExerciseLibrary.getExerciseMuscleGroups` — `lib/state/workout/exercise_library.dart` · :318-325
6. [x] Delete `WorkoutState.getExerciseMuscleGroups` — `lib/state/workout/workout_state.dart` · :361-364
7. [x] Grep clean: `getExerciseMuscleGroups` absent from `lib/state/**` and the four test files (file tools)

Done criteria: gateway `test -- test/catalog_refresh_test.dart test/pr7_exercise_details_view_test.dart test/pr8_exercise_library_test.dart test/exercise_row_density_test.dart` green; grep zero hits in scope.
Predicted files: the four test files, the two state files.
Write scope: `lib/state/**,test/**`.

### Phase C2 — remove the repository pair (crew-builder-data)

1. [x] Delete both methods and the stale "removed by plan 34" doc comment — `lib/data/repositories/workout_repository.dart` · :140-160
2. [x] Delete the mock implementations — `lib/data/repositories/mock_workout_repository.dart` · :1015-1035
3. [x] Delete the Hive implementations — `lib/data/repositories/hive_workout_repository.dart` · :1740-1760
4. [x] Rewrite the legacy-wrapper tests onto the links API (S-4/S-13 keep their meaning; "missing group skipped" now lives in S-1/S-3) — `test/muscle_links_storage_test.dart` · :122-180
5. [x] Prove the removal: grep `getExerciseMuscleGroups|setExerciseMuscleGroups` over `lib` and `test` → zero hits (file tools)

Done criteria: gateway `test -- test/muscle_links_storage_test.dart test/data_migration_test.dart` green (`data_migration_test.dart` uses `putRawExerciseMuscleLinksForTest`, untouched); gateway `build` green; grep zero hits.
Predicted files: the three repository files, `test/muscle_links_storage_test.dart`.
Write scope: `lib/data/**,test/**`.

### Phase D — docs (crew-docs-keeper)

1. [x] Delete the taxonomy entry, keep title + intro, add "Nothing is deferred at the moment." — `docs/future-work.md` · the single entry (D-6)
2. [x] Update the MuscleGroup section: drop the legacy-pair sentence (:230), describe the display helper and the Primary/Secondary detail rows — `docs/data_models.md`
3. [x] Update the picker row (grouped filter, main-muscle chips) and the detail rows — `docs/navigation_and_screens.md` · :191/:194
4. [x] Update the `MusclePicker` entry (order now sourced from `lib/core/utils/muscle_display.dart`) and the `ExercisePickerScreen` entry — `docs/widget_catalog/session_widgets.md` · :192-237
5. [x] Verify the state tables name only the links API — `docs/state_management/workout_state.md` (no `getExerciseMuscleGroups` row exists today — grep found none; verify on the day)
6. [x] Check the filter mention still matches the data-layer rule — `docs/exercise_ranking.md` · :20/:25
7. [x] Run the docs contract test — `test/docs_indexing_contract_test.dart`

Done criteria: gateway `test -- test/docs_indexing_contract_test.dart` green; every behaviour sentence names an existing test.
Predicted files: the six docs files.
Write scope: `docs/**`.

## Progress

| Item | Status |
|---|---|
| A1 helper + MusclePicker source | done (see `.work/crew/2026-10-14-35-muscle-display/report-builder-app-a1.md`) |
| A2 picker/library dropdown + chips | pending |
| B detail Primary/Secondary | done (see `.work/crew/2026-10-14-35-muscle-display/report-builder-app-b.md`) |
| C1 state wrappers removed, tests migrated | done (see `.work/crew/2026-10-14-35-muscle-display/report-builder-app-c1.md`) |
| C2 repository pair removed | done (see `.work/crew/2026-10-14-35-muscle-display/report-builder-data-c2.md`) |
| D docs | done (see `.work/crew/2026-10-14-35-muscle-display/report-docs-keeper-d.md` and the plan's evidence file) |

## Assumption Log

- B (crew-builder-app): both detail screens import the helper package-style (`package:omnitrain/core/utils/muscle_display.dart`) rather than the brief's relative spelling, to match every other import in those files.
- B: the muscles section is a `Column` splitting the previous 12pt row separators between Primary and Secondary; the section itself stays the last block, so only the inter-row gap was added.
- B: `_DetailRow`s keep the exercise's `muscle-*` link order (through `musclesWithRole`), not taxonomy order.

## Feedback

- Fix 1 (crew-builder-data): reworded the `scripts/sqlite_schema.sql` comment after `app_exercise_muscle_group` to name `setExerciseMuscleLinks(exerciseId, links)` (comment only; statements untouched).
- Fix 2 (crew-builder-app): reworded the doc comment on `getExerciseMuscleLinks` in `lib/state/workout/exercise_library.dart` to describe the deliberate display degradation (`null` → picker/library rows lose their chips, detail section collapses) and the editor's strict reading (a failed read shows the error and leaves without writing); it now points at the guarding tests `test/muscle_filter_picker_test.dart` 'a failing links read leaves rows chip-less, not crashed' and `test/muscle_editor_screen_test.dart` 'a failing links read shows the failure and leaves'. Comment only, no behaviour change.

## Open questions

- OQ-1 `docs/state_management/workout_state.md` has no `getExerciseMuscleGroups` row today (grep over the file found none this session), so phase D item 5 is a verification only; nothing to delete there unless the day's file differs.
- OQ-2 S-2 asserts 24 open-menu item texts in order. Plan 34's evidence records that the dropdown lays out every item at the 800×1200 surface, so no scrolling is expected; if the menu scroll-clips, the builder switches that assertion to `scrollUntilVisible` and notes it in the Assumption Log.
- OQ-3 Flutter SDK `dropdown.dart` internals were not read (outside the write scope); the framework claims above rest on repo test evidence only.
- OQ-4 `test/pr8_exercise_library_test.dart:162` comment names `setExerciseMuscleGroups` while the test calls the links API — stale wording, fixed in C1 item 3.
- OQ-5 `screen_widget_test.dart:7600` iterates every `find.text('All')` widget; D-2's `selectedItemBuilder` must keep an explicit small style on the closed-field 'All' Text or that test goes red (expected-green constraint, not a new test).
