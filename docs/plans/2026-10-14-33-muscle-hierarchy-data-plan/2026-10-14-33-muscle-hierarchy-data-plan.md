# Plan 33 — Muscle hierarchy and roles, PR 1 of 3: data layer, seed, refresh, migration, filter

Status: EXPANDED by the architect 2026-10-14 (seed sections kept verbatim; architect additions sit below the Code pointers). Base commit `1ca3b41`. Owner approved the Phase 1 proposal
(`.work/2026-10-14-33-muscle-hierarchy/proposal-phase-1.md`) with the default answer to all five questions.
Series: this is PR 1; PR 2 = plan 34 (custom exercise editor: roles, region replacement, secondary-only block, state/service paths take roles);
PR 3 = plan 35 (picker dropdown grouped by region, primary-only chips on list rows, detail view Primary/Secondary, docs `create_new_exercise.md`,
`future-work.md` entry removal, remaining doc edits). Not in this PR: any UI file under `lib/features/` or `lib/widgets/`.

## Goal and acceptance

After this PR the data layer knows the hierarchy and the roles, the bundled catalog carries the approved tagging, existing installs receive it,
and every muscle filter answers by the new rules. UI looks as before (flat chips and a flat dropdown, now with 23 entries).

Acceptance (checked by tests on Mock AND Hive unless noted):
- A1. 23 muscle entries: 5 regions (Arms, Legs, Back, Shoulders, Core), 16 muscles, 2 standalone (Chest, Neck). Each muscle has exactly one region; no third level.
- A2. Filter by Legs returns Barbell Back Squat (Quadriceps primary) and Tennis Match (Legs primary). Filter by Quadriceps returns the squat, not Tennis Match.
- A3. Filter by Triceps does not return Barbell Bench Press (Triceps secondary only) but returns Triceps Pressdown.
- A4. Bench Press is Chest primary; Triceps, Front delts secondary. Tennis Match is Legs, Shoulders, Core primary (region-level).
- A5. No seeded exercise carries a region and one of its own muscles; every tagged seeded exercise has a primary; none has an id in both roles.
- A6. Catalog refresh from version 10 gives untouched catalog exercises the new tagging and roles, adds the 7 new groups and parent links, renames Trapezius to Traps;
  leaves a user-copied exercise, a custom exercise and a touched catalog exercise unchanged.
- A7. One-time cleanup (data version 15 → 16): every existing link on custom and touched exercises becomes primary; a region tag next to one of its own muscles is removed; nothing else changes. Idempotent.
- A8. `copyAsCustom` carries ids and roles exactly.
- A9. Set logging, Stats, watch app: no file touched. `flutter analyze` issue count not above baseline.

## Decision Ledger

- D-1 Types live in `lib/data/models/models.dart`: `enum MuscleRole { primary, secondary }` (persisted as `'primary'`/`'secondary'`), `class ExerciseMuscleLink { final String muscleGroupId; final MuscleRole role; const; toMap/fromMap (keys `muscle_group_id`, `role`); ==/hashCode }`, and `MuscleGroup.parentId` (`String?`, map key `parent_id`, absent/null for regions and standalone entries; `fromMap` tolerant of a missing key).
- D-2 The hierarchy has one code source: `lib/data/models/muscle_taxonomy.dart` (`MuscleTaxonomy`). `entries` is a const ordered list of `(id, name, parentId?)`; `SeedData.sampleMuscleGroups` is built from it. Order: Arms, Biceps, Triceps, Forearms, Legs, Quadriceps, Hamstrings, Glutes, Calves, Adductors, Back, Lats, Traps, Lower back, Shoulders, Front delts, Side delts, Rear delts, Core, Abs, Obliques, Chest, Neck.
  Ids (existing kept): `muscle-arms`, `muscle-biceps`, `muscle-triceps`, `muscle-forearms`, `muscle-legs`, `muscle-quads` (name "Quadriceps"), `muscle-hamstrings`, `muscle-glutes`, `muscle-calves`, `muscle-adductors`, `muscle-back`, `muscle-traps` (name changes "Trapezius" → "Traps"), `muscle-shoulders`, `muscle-core`, `muscle-chest`, `muscle-neck`. New: `muscle-lats` "Lats", `muscle-lower-back` "Lower back", `muscle-front-delts` "Front delts", `muscle-side-delts` "Side delts", `muscle-rear-delts` "Rear delts", `muscle-abs` "Abs", `muscle-obliques` "Obliques".
- D-3 `MuscleTaxonomy` API (pure, static): `isRegion(id)` (has children), `regionOf(id)` (parentId or null), `musclesOf(regionId)`, `orderIndex(id)`,
  `matches(selectedId, links)` and `normalize(links)`.
  `matches`: only `primary` links count; selected region → true if any primary link id == region or `regionOf(linkId) == region`; selected muscle/standalone/unknown id → true only on exact id. A region-only link never matches a muscle.
  `normalize`: de-duplicates identical links; drops a region link when any link (either role) targets one of that region's muscles; sorts primary first then secondary, inside a role by `orderIndex` (unknown ids last, by id); throws `ArgumentError` when one id appears in both roles, or when the result is non-empty and has no primary. Empty list is valid.
- D-4 Storage: `WorkoutRepository` gains `getExerciseMuscleLinks(exerciseId) → List<ExerciseMuscleLink>` (stored order) and `setExerciseMuscleLinks(exerciseId, links)` (calls `MuscleTaxonomy.normalize`, so storage order is deterministic). Hive keeps box `exercise_muscle_groups` but values become `List<Map>` of `ExerciseMuscleLink.toMap()`; the reader also accepts the OLD shape (`List<String>` of ids) and returns those as `primary` links. Mock keeps a `Map<String, List<ExerciseMuscleLink>>`.
- D-5 Legacy calls stay until PR 2: `getExerciseMuscleGroups(exerciseId)` returns the `MuscleGroup`s of all links in stored order (primary first); `setExerciseMuscleGroups(exerciseId, ids)` stores every id as primary through `setExerciseMuscleLinks`. Both are marked in a doc comment as legacy, removed by plan 34.
- D-6 Filter: the `muscleGroupIds` parameter of `searchExercises` and `getExercisesRankedForModality` (Hive ×2, Mock ×2 = 4 sites) keeps its type; an exercise passes when `MuscleTaxonomy.matches(id, links)` is true for ANY selected id. The ranking score is NOT changed (ranking never reads muscles; owner answer: leave ordering alone).
- D-7 Seed: new `SeedData.exerciseMuscleLinks` (`Map<String, List<ExerciseMuscleLink>>`, 178 entries, written through a private `_muscles({primary, secondary})` helper) replaces `exerciseMuscleGroupRelationships`. The exact block is the lead's file `.work/2026-10-14-33-muscle-hierarchy/relationships.dart.txt`; the builder copies it unchanged; `.work/2026-10-14-33-muscle-hierarchy/expected-tagging.json` is what the lead diffs the result against. The old map is kept in phase A (so `lib/core` still compiles) and deleted in phase C. `_muscles` returns `MuscleTaxonomy.normalize(...)`, so seed rows are stored normalised (primary first, taxonomy order) and a violating row throws at load. The 74 untagged exercises stay absent from the map.
- D-8 Catalog refresh (`lib/core/services/catalog_refresh_service.dart`): `CatalogSource.exerciseMuscleGroups` becomes `Map<String, List<ExerciseMuscleLink>>` fed by `SeedData.exerciseMuscleLinks`; `_refreshMuscleGroups` also patches when `parentId` differs; `_refreshExerciseMuscleGroups` compares links including roles (order-insensitive) and writes via `setExerciseMuscleLinks`; touched-exercise skip unchanged (owner answer: touched stay the user's). `bundledCatalogVersion` 10 → 11 with a history sentence in the file's doc comment.
- D-9 Cleanup migration: a new `DataMigrationStep` named `muscleLinkRoles`, `targetVersion` 16, in `HiveWorkoutRepository._dataMigrationSteps` and a body-bearing mirror in `MockWorkoutRepository._dataMigrationSteps` (the Mock steps before 16 are no-op markers; this one runs the same body). Body: for every key in the link store, read links (legacy shape → primary), `normalize` them (drops the redundant region), write back in the new shape; skip nothing (untouched catalog rows are rewritten identically by the next refresh). `currentDataVersion` 15 → 16 in `lib/core/constants/data_version.dart` (phase D).
- D-10 Legacy seeding paths in Hive (`_seedData` ~line 573 and `_migrateExerciseLibraryRefresh` ~line 764) and Mock (line ~202) write from `SeedData.exerciseMuscleLinks` in the new shape.
- D-11 SQL contract: `scripts/sqlite_schema.sql` `app_muscle_group` gains `parent_id TEXT REFERENCES app_muscle_group(id)`; `app_exercise_muscle_group.is_primary` is documented as 1 = primary, 0 = secondary; `scripts/sqlite_seed.sql` muscle inserts become the 23 entries (parents set by name subselect, parents inserted first) and the existing link inserts (lines ~2484-2540) use only names that still exist and the right `is_primary`; no region+own-muscle pair. `test/db_seed_test.dart` must stay green.
- D-12 `copyAsCustom` (`lib/core/services/exercise_library_service.dart` ~line 255) uses `getExerciseMuscleLinks`/`setExerciseMuscleLinks`.

## Readers of the shared fixtures this PR changes (each is a phase item)

- `SeedData.exerciseMuscleGroupRelationships`: `mock_workout_repository.dart:202`, `hive_workout_repository.dart:574` and `:765`, `core/services/bundled_catalog_source.dart:33`; tests `catalog_refresh_test.dart:70` and `:881`, `seeded_demos_test.dart:54`, `seeded_demos_state_test.dart:49`, `catalog_referential_integrity_test.dart:25`, `:71`, `:135`.
- `SeedData.sampleMuscleGroups`: `mock:162`, `hive:538`, `bundled_catalog_source.dart:29`; tests `catalog_refresh_test.dart:53`, `seeded_demos_test.dart:37`, `seeded_demos_state_test.dart:32`, `catalog_referential_integrity_test.dart:17`, `:85`.
- `CatalogSource.exerciseMuscleGroups`: `catalog_refresh_service.dart:128`, `bundled_catalog_source.dart:32`; fakes in `catalog_refresh_test.dart:30/56/881`, `seeded_demos_test.dart:22`, `seeded_demos_state_test.dart:17`.
- `getExerciseMuscleGroups` / `setExerciseMuscleGroups` callers (kept working by D-5): `lib/state/workout/exercise_library.dart` (create/update/get), `lib/core/services/exercise_library_service.dart` (copy, `editCustom`), the picker, library, detail and editor screens, tests `pr8_exercise_library_test.dart:145/787`, `pr7_exercise_details_view_test.dart:379`, `exercise_row_density_test.dart:63`.
- `currentDataVersion` readers: `test/data_migration_test.dart` (lines 428-630; line 497 asserts `15`).

## Core scenarios (fixtures are exact; each fails today for the reason given)

- S-1 Taxonomy integrity (`test/muscle_taxonomy_test.dart`, new): `MuscleTaxonomy.entries.length == 23`; regions == {muscle-arms, muscle-legs, muscle-back, muscle-shoulders, muscle-core}; `musclesOf('muscle-legs')` == {quads, hamstrings, glutes, calves, adductors} (ids with prefix); `musclesOf('muscle-back')` == {lats, traps, lower-back}; `muscle-chest` and `muscle-neck` have `parentId == null` and no children; no entry's parent is itself a child; the 16 pre-existing ids all present; `SeedData.sampleMuscleGroups` ids/names/parentIds equal the taxonomy; name of `muscle-traps` is `Traps`. Fails today: no `MuscleTaxonomy`.
- S-2 Interpretation (same file): links `[quads primary, glutes primary]` → `matches('muscle-legs')` true, `matches('muscle-quads')` true, `matches('muscle-hamstrings')` false; links `[legs primary]` → `matches('muscle-legs')` true, `matches('muscle-quads')` false; links `[chest primary, triceps secondary]` → `matches('muscle-triceps')` false, `matches('muscle-chest')` true, `matches('muscle-arms')` false; `normalize([legs primary, quads primary])` == `[quads primary]`; `normalize([chest primary, triceps primary])` unchanged; `normalize([triceps secondary])` throws; `normalize([quads primary, quads secondary])` throws; `normalize([])` == `[]`; `normalize([glutes secondary, quads primary, chest primary])` == `[quads primary, chest primary, glutes secondary]` (primary first; within primary, D-2 order puts Quadriceps before Chest). Fails today: none of this exists.
- S-3 Seed integrity (`test/catalog_referential_integrity_test.dart`, rewritten R-001/R-004/R-005 plus new): every key is a real exercise; every id exists; every entry has ≥1 primary; no region+own muscle; no id twice; `exerciseMuscleLinks.length == 178`; regions appear only on exactly these 12 ids: tennis-match, tennis-drill, volleyball-match, volleyball-drill, badminton-match, table-tennis-match, cricket-match, ice-hockey-match, baseball-game, american-football-game, rugby-match, lacrosse-game; exact rows (compare each role as a SET; stored order is the normalised one): bench-press = primary [chest], secondary [triceps, front-delts]; barbell-squat = primary [quads], secondary [glutes, hamstrings]; tennis-match = primary [legs, shoulders, core], no secondary; deadlift = primary [glutes, hamstrings, lower-back].
- S-4 Storage on Mock and Hive via `test/helpers/repository_harness.dart` (new `test/muscle_links_storage_test.dart`): set `[triceps secondary, chest primary]` on a custom exercise → get returns `[chest primary, triceps secondary]`; set `[legs primary, quads primary]` → `[quads primary]`; set `[triceps secondary]` → throws `ArgumentError`; set `[]` → get returns `[]`; reopened repository (`restart()`) returns the same; Hive only: write the OLD shape `['muscle-legs','muscle-quads']` straight into box `exercise_muscle_groups` then `getExerciseMuscleLinks` returns `[legs primary, quads primary]` (reader does not normalise on read); `setExerciseMuscleGroups(id, ['muscle-chest','muscle-triceps'])` → both primary; `getExerciseMuscleGroups` returns the two groups, primary first.
- S-5 Filter on Mock and Hive (`test/muscle_filter_test.dart`, new): `searchExercises(muscleGroupIds: ['muscle-legs'])` contains `exercise-barbell-squat` and `exercise-tennis-match`, each exactly once; `['muscle-quads']` contains the squat, not tennis-match; `['muscle-triceps']` contains `exercise-triceps-pressdown`, not `exercise-bench-press`; `['muscle-chest']` contains bench-press; `['muscle-arms']` contains triceps-pressdown and `exercise-volleyball-match`; `['muscle-quads','muscle-legs']` returns the squat once; the same four assertions through `getExercisesRankedForModality('resistance_lifting', muscleGroupIds: …)` for the squat/bench/triceps cases; an exercise with a secondary-only link to the selected muscle is excluded (custom exercise: `[chest primary, lats secondary]` → `['muscle-lats']` excludes it, `['muscle-back']` excludes it). Fails today: Legs misses the squat (no link to `muscle-legs`), Triceps wrongly returns the bench press, Arms misses the pressdown.
- S-6 Refresh (`test/catalog_refresh_test.dart`, new scenario `S-MH-1`): Mock repo seeded with the OLD state — groups: the 16 old names (Trapezius), no parents; bench-press links `[muscle-chest, muscle-triceps, muscle-shoulders]` as legacy primary links; version 10 — run `CatalogRefreshService.refresh()` with the bundled source: `getMuscleGroups()` has 23 ids, `muscle-traps` named `Traps`, `muscle-quads` parent == `muscle-legs`; bench-press links == `[chest primary, triceps secondary, front-delts secondary]`; stored version 11. Same run: a custom exercise with `[legs primary]`, a user copy made by `copyAsCustom`, and a touched bundled exercise (`markSeedEntryTouched`) with `[muscle-back primary]` keep their links exactly. Second refresh is a no-op.
- S-7 Copy (`test/pr8_exercise_library_test.dart`, strengthened copy test): source has `[chest primary, triceps secondary, front-delts secondary]`; `copyAsCustom` result's links equal the source's, roles included.
- S-8 Migration (`test/data_migration_test.dart` additions, Mock and Hive): old-shape fixtures `A=['muscle-legs','muscle-quads']`, `B=['muscle-chest','muscle-triceps']`, `C=['muscle-back','muscle-traps']`, `D=['muscle-back']`, `E=[]` on custom exercises → after the step: A `[quads primary]`, B `[chest primary, triceps primary]`, C `[traps primary]`, D `[back primary]`, E `[]`; a touched bundled exercise with A is cleaned the same; second run changes nothing; step list contains `muscleLinkRoles` with targetVersion 16 on both repos; `currentDataVersion == 16`.
- S-9 SQL contract: `test/db_seed_test.dart` stays green; a new assertion that `app_muscle_group` has a `parent_id` column and that after seeding exactly 23 groups exist and `Quadriceps.parent_id` is the id of `Legs`.

## Phase outline (all serial: they share `lib/data` and `test/`; owner agent, write scope)

- Phase A — `crew-builder-data`; scope `lib/data/**,lib/mock/**,scripts/sqlite_*.sql,test/**`: types (D-1), taxonomy (D-2, D-3), repo interface + Mock + Hive links storage and legacy wrappers (D-4, D-5), filter at the 4 sites (D-6), `SeedData.sampleMuscleGroups` from the taxonomy and new `SeedData.exerciseMuscleLinks` (D-7, old map kept), repos seed from the new map (D-10), SQL (D-11); tests S-1, S-2, S-3 (new-map part), S-4, S-5, S-9. Expected red: none. (The old map and `lib/core` untouched, so everything compiles.)
- Phase B — `crew-builder-app`; scope `lib/core/**,test/**`: `CatalogSource`/`BundledCatalogSource` type switch, refresh (D-8), `bundledCatalogVersion` 11, `copyAsCustom` (D-12); update the four fakes and `catalog_refresh_test`/`seeded_demos*` readers; tests S-6, S-7. Expected red until phase C: none.
- Phase C — `crew-builder-data`; scope `lib/data/**,lib/mock/**,test/**`: delete `SeedData.exerciseMuscleGroupRelationships` and fix the last readers (`catalog_referential_integrity_test.dart`); migration step (D-9) in both repos; tests S-8 (step list and bodies). Predicted red until phase D: `data_migration_test.dart` assertions on `currentDataVersion`/final data version (the step lands the repo on 16 while the constant is 15).
- Phase D — `crew-builder-app`; scope `lib/core/constants/data_version.dart,test/data_migration_test.dart`: `currentDataVersion` 16 and the `15` assertion and wording in that test.
- Phase E — `crew-docs-keeper`; scope `docs/**`: `docs/data_models.md` MuscleGroup section (hierarchy, interpretation rules, roles; remove the `bodyRegion` correction note), `docs/db_integration.md` (schema columns, catalog version 11, data version 16), `docs/constants_reference.md` (`bundledCatalogVersion` value, `currentDataVersion`).
- After E: `crew-prover` on S-3, S-4, S-5, S-6, S-8 guards; lead applies every `NOT PROVEN` mutation by hand; `crew-reviewer`.

## Code pointers (current lines, as of base)

- `lib/data/models/models.dart:924` class `MuscleGroup { id, name, createdAtMs }` with `fromMap`/`toMap` (keys `id`, `name`, `created_at_ms`).
- `lib/data/repositories/workout_repository.dart:125-137` `getMuscleGroups`, `upsertMuscleGroup`, `getExerciseMuscleGroups`, `setExerciseMuscleGroups`; filters documented at `:316`.
- Hive: box `_exerciseMuscleGroupsBox` (`Box<List>`, opened `:227`); `_asStringList :816`; `getExerciseMuscleGroups :1675`, `setExerciseMuscleGroups :1688`; filters `:870-878` (searchExercises) and `:1824-1832` (ranked), both: `return exerciseMuscles.any((id) => muscleGroupIds.contains(id));`; seeding `:537`, `:573-576`, `:764-767`; step list `:272-325`, `_MethodStep :20`.
- Mock: `_exerciseMuscleGroups :69`; seeding `:162`, `:202-204`; filters `:383-387`, `:1073-1077` (`final exerciseMuscles = _exerciseMuscleGroups[e.id] ?? [];`); get/set `:963-977`; steps `:272-299` (`_MockMigrationStep`).
- Seed: `lib/mock/seed_data.dart:364-448` `sampleMuscleGroups`; `:4528-~4940` `exerciseMuscleGroupRelationships` (body between `= {` and `};`).
- Refresh: `lib/core/services/catalog_refresh_service.dart:114-145`; `catalog_source.dart:25-32`; `bundled_catalog_source.dart:29-33`.
- Copy: `lib/core/services/exercise_library_service.dart:230-262` (`copyAsCustom`; links copied at `:255-259`).
- `lib/core/constants/catalog_version.dart:46` `const int bundledCatalogVersion = 10;`; `lib/core/constants/data_version.dart:~38` `const int currentDataVersion = 15;`.
- SQL: `scripts/sqlite_schema.sql:840-854`; `scripts/sqlite_seed.sql:366-375` (muscle inserts), `:2484-~2540` (links).

## Feature invariants (architect)

- `MuscleTaxonomy` is the single code source of the hierarchy; `SeedData.sampleMuscleGroups` is derived from it and never hand-edited (D-2).
- Only `primary` links match a filter; a region selection matches primary links to the region or any of its muscles; a muscle/standalone selection is exact-id (D-3).
- Storage order is deterministic: `setExerciseMuscleLinks` normalises (primary first, taxonomy order, unknown ids last); readers return stored order and never re-sort or re-normalise on read (D-3, D-4).
- Box `exercise_muscle_groups` keeps its name; values are `List<Map>` of `ExerciseMuscleLink.toMap()`; a `List<String>` value is legacy and reads as all-primary (D-4).
- Hive trap: `_asStringList` (`hive_workout_repository.dart:816-820`) `toString()`-maps every element, so the link reader must branch on element type and must NOT reuse `_asStringList` for this box.
- Legacy `getExerciseMuscleGroups`/`setExerciseMuscleGroups` stay until plan 34 and route through the links API; both repos' existing skip of a link whose group row is absent (`mock:966-968` `.whereType<MuscleGroup>()`, `hive:1681-1683` `.whereType<Map>()`) survives the rewrite (D-5).
- The ranking score never reads muscles; only the pre-filter becomes hierarchy-aware (D-6, owner answer).
- The refresh never rewrites custom or touched exercises' links; the `muscleLinkRoles` migration is the only writer that touches them (D-8, D-9).
- `currentDataVersion` (data migration) and `bundledCatalogVersion` (catalog refresh) stay independent gates (S-156 orthogonality test).
- No file under `lib/features/` or `lib/widgets/` changes in this PR; docs under `docs/` stay below 52 KB per file and every behaviour sentence names an existing test.

## Existing-functionality impact (architect; all quotes read on disk this run)

| # | Surface | What it reads (verified) | Search run | Effect | Guard |
|---|---|---|---|---|---|
| I-1 | `SeedData.exerciseMuscleGroupRelationships` | `mock_workout_repository.dart:202-204` (`_exerciseMuscleGroups[entry.key] = List.from(entry.value)`), `hive_workout_repository.dart:573-576` and `:764-767` (`List<String>.from(entry.value)` into the box), `bundled_catalog_source.dart:33`; tests `catalog_refresh_test.dart:70/:881`, `seeded_demos_test.dart:54`, `seeded_demos_state_test.dart:49`, `catalog_referential_integrity_test.dart:25/:71/:135` | grep over `lib/` + `test/` (sheet A Q2, sheet E: 12 test files thread it, none asserts link structure) | Replaced by `exerciseMuscleLinks` (D-7); old map kept in phase A, deleted in phase C; last test readers fixed in C | S-3, S-6, S-8 |
| I-2 | `SeedData.sampleMuscleGroups` | `mock:162`, `hive:538`, `bundled_catalog_source.dart:29`; tests `catalog_refresh_test.dart:53`, `seeded_demos_test.dart:37`, `seeded_demos_state_test.dart:32`, `catalog_referential_integrity_test.dart:17/:85` | same greps | Rebuilt from the taxonomy: 23 entries, `parentId`, `muscle-traps` renamed `Traps`; the three fake copies flow through unchanged | S-1, S-6, S-9 |
| I-3 | `CatalogSource.exerciseMuscleGroups` | `catalog_refresh_service.dart:128`, `bundled_catalog_source.dart:32`; fakes `catalog_refresh_test.dart:30/56/881`, `seeded_demos_test.dart:22`, `seeded_demos_state_test.dart:17` | grep `exerciseMuscleGroups` over `lib/core` | Type switch to `Map<String, List<ExerciseMuscleLink>>` (D-8) | S-6 |
| I-4 | `get/setExerciseMuscleGroups` callers | `exercise_library.dart:189/:228/:318-322`; `exercise_library_service.dart:255-259` (copy), `:305` (`editCustom`); picker `:107-123/:370/:607`; library screen `:276/:301-307`; detail view `:79-88/:311`; library detail `:68-78/:180`; editor `:86-102/:220/:424-443`; tests `pr8:145/787`, `pr7:379`, `density:63` | grep `muscleGroup|MuscleGroup` over `lib/features/exercise` → 65 matches in 5 files; `exercise_detail_screen.dart`: 0 matches (unaffected) | Kept working by the D-5 wrappers; no UI file changes | S-4, S-7, S-13 |
| I-5 | `currentDataVersion` readers | `test/data_migration_test.dart:497` `expect(currentDataVersion, equals(15));` (S-156); S-006 asserts `getDataVersion() == currentDataVersion`; S-156 also asserts the Mock and Hive step lists are equal | grep `currentDataVersion` over `lib/` + `test/` | 15 → 16 in phase D; the `15` literal and S-156 wording updated with it | S-8 |
| I-6 | `lib/state/workout/exercise_library.dart` | `setExerciseMuscleGroups` (create `:189`, update `:228`), `getExerciseMuscleGroups` (`:318-322`), `getMuscleGroups` (`:263-268`), filter pass-through (`:284-310`) | full file read | No change: wrappers keep their signatures | S-4, S-13 |
| I-7 | `HiveWorkoutRepository._seedData` / `_migrateExerciseLibraryRefresh` | Both write `List<String>.from(entry.value)` into box `exercise_muscle_groups` (`:573-576`, `:764-767`) | file read | Rewritten to the new shape from `SeedData.exerciseMuscleLinks` (D-10) | S-4, S-8 |
| I-8 | `edge_case_test.dart:109-117` | `MuscleGroup.fromMap` round-trip with a map lacking `parent_id` | sheet E | Stays green: D-1's `fromMap` is tolerant of a missing key | S-1 |

**D-9 check (DataMigrationService / `_MockMigrationStep`), quoted from disk:**

- `data_migration_service.dart:102-112`: steps are sorted `..sort((a, b) => a.targetVersion.compareTo(b.targetVersion))`, then `if (step.targetVersion <= effectiveFrom) { continue; } await step.run(); await _repository.setDataVersion(step.targetVersion);` — an appended step with `targetVersion` 16 runs exactly once on every device below 16; idempotency comes from the version gate, so the step body itself only needs to be re-run-safe.
- `mock_workout_repository.dart:27`: `_MockMigrationStep(this.targetVersion, this.name, [this._body]);` and `:41`: `await _body?.call();` — the class already accepts an optional body, and step 15 already uses one (`:291-293` `_MockMigrationStep(15, 'clampInvertedSessionWindows', () => repo._clampInvertedSessionWindows())`).
- **Conclusion: D-9's "body-bearing mirror" needs NO new class.** `_MockMigrationStep(16, 'muscleLinkRoles', () => repo._migrateMuscleLinkRoles())` is the exact pattern step 15 already uses.

## Edge scenarios (architect; continue after S-9)

- S-10 Hive restart round-trip (`test/muscle_links_storage_test.dart`, Hive only): set `[triceps secondary, chest primary]` on a custom exercise, `close()`, `restart()` → `getExerciseMuscleLinks` returns `[chest primary, triceps secondary]` — roles survive `ExerciseMuscleLink.toMap/fromMap` through the box. Fails without the change: the box holds `List<String>` today and no links API exists.
- S-11 Missing group skipped (same file, both repos): put a link whose `muscleGroupId` has no `MuscleGroup` row (Hive: write a map with an unknown id straight into the box; Mock: seed the map directly), then `getExerciseMuscleGroups` returns only the resolvable groups. Guards the `.whereType` skip (`mock:966-968`, `hive:1681-1683`) surviving the links rewrite; fails without it because a naive links-based rewrite could return nulls or throw.
- S-12 Refresh no-op at stored version 11 (`test/catalog_refresh_test.dart`): Mock repo at `setCatalogVersion(bundledCatalogVersion)` → `refresh()` returns false, no writes, stored links unchanged. Guards the version bump against re-running on already-upgraded devices (the existing S-001 pattern, now at 11).
- S-13 Legacy wrapper drops a region next to its muscle (`test/muscle_links_storage_test.dart`, both repos): `setExerciseMuscleGroups(id, ['muscle-legs','muscle-quads'])` → stored links `[quads primary]`; `getExerciseMuscleGroups` returns `[Quadriceps]` only. Fails without the change: today's wrapper stores the raw list (`mock:972-976`, `hive:1686-1693`).
- S-14 Migration cleans an archived custom exercise (`test/data_migration_test.dart`, both repos): an archived custom exercise (`isArchived = true`) holding fixture A `['muscle-legs','muscle-quads']` → after the step `[quads primary]`. The migration iterates the link store's keys, not the exercise list, so archived rows are cleaned; fails without the change because nothing else ever rewrites an archived row's links.

## Phases (expanded from the outline; all serial — they share `lib/data`, `lib/mock` and `test/`, and D's test asserts the step C appends, so no phase runs in parallel)

### Phase A part 1 — code · `crew-builder-data` · `--scope lib/data/**,lib/mock/**,scripts/sqlite_*.sql`

1. [ ] Add `MuscleRole`, `ExerciseMuscleLink` (toMap/fromMap keys `muscle_group_id`/`role`, ==/hashCode) and `MuscleGroup.parentId` (key `parent_id`, `fromMap` tolerant of a missing key) — `lib/data/models/models.dart` · `MuscleRole`/`ExerciseMuscleLink`/`MuscleGroup`
2. [ ] Add `MuscleTaxonomy`: `entries` (23 ordered `(id, name, parentId?)` per D-2), `isRegion`, `regionOf`, `musclesOf`, `orderIndex`, `matches`, `normalize` per D-3 — `lib/data/models/muscle_taxonomy.dart` · `MuscleTaxonomy`
3. [ ] Rebuild `sampleMuscleGroups` from the taxonomy (23 entries, `muscle-traps` named `Traps`, parents set) — `lib/mock/seed_data.dart:364-448` · `sampleMuscleGroups`
4. [ ] Add `exerciseMuscleLinks` (178 entries) via private `_muscles({primary, secondary})` returning `MuscleTaxonomy.normalize(...)`; copy the lead's block `.work/2026-10-14-33-muscle-hierarchy/relationships.dart.txt` unchanged; keep `exerciseMuscleGroupRelationships` — `lib/mock/seed_data.dart` · `exerciseMuscleLinks`/`_muscles`
5. [ ] Add `getExerciseMuscleLinks`/`setExerciseMuscleLinks` to the interface; doc-comment the legacy pair as removed by plan 34 — `lib/data/repositories/workout_repository.dart:125-137` · `WorkoutRepository`
6. [ ] Mock: links map `Map<String, List<ExerciseMuscleLink>>`, get/set links (set normalises), legacy get/set through links, both filters via `MuscleTaxonomy.matches`, seeding from the new map — `lib/data/repositories/mock_workout_repository.dart` · `_exerciseMuscleGroups`/`getExerciseMuscleLinks`/`setExerciseMuscleLinks`/`searchExercises`/`getExercisesRankedForModality`
7. [ ] Hive: same storage on box `exercise_muscle_groups`; reader branches on element type (String → legacy primary; Map → `ExerciseMuscleLink.fromMap`; never `_asStringList`); both filters via `matches`; `_seedData` `:573-576` and `_migrateExerciseLibraryRefresh` `:764-767` write the new shape — `lib/data/repositories/hive_workout_repository.dart` · `getExerciseMuscleLinks`/`setExerciseMuscleLinks`/`searchExercises`/`getExercisesRankedForModality`/`_seedData`/`_migrateExerciseLibraryRefresh`
8. [ ] SQL: `app_muscle_group` gains `parent_id TEXT REFERENCES app_muscle_group(id)`; document `app_exercise_muscle_group.is_primary` (1 = primary, 0 = secondary); muscle inserts become the 23 entries (parents inserted first, parents set by name subselect) — `scripts/sqlite_schema.sql:840-853`, `scripts/sqlite_seed.sql:366-375` · `app_muscle_group`

### Phase A part 2 — tests · `crew-builder-data` · `--scope test/**`

1. [ ] Write S-1 + S-2 — `test/muscle_taxonomy_test.dart` · new
2. [ ] Write S-3 new-map part (keys real, ids exist, ≥1 primary, no region+own muscle, no dual id, length 178, the 12 region ids, exact rows) — `test/catalog_referential_integrity_test.dart` · new tests beside R-001/R-004/R-005 (fully rewritten in phase C)
3. [ ] Write S-4 (both harnesses; legacy-shape read; wrappers) — `test/muscle_links_storage_test.dart` · new (uses the existing `test/helpers/repository_harness.dart:51` `RepositoryHarness.restart()`)
4. [ ] Write S-5 (both repos, `searchExercises` + `getExercisesRankedForModality`) — `test/muscle_filter_test.dart` · new
5. [ ] Write S-9 (parent_id column, 23 groups after seeding, `Quadriceps.parent_id` == Legs' id) — `test/db_seed_test.dart` · new test in group `Pipeline schema documentation`

**Done Criteria A:** `.github/copilot/scripts/macos/gateway.sh lint` (issue count not above baseline) and `gateway.sh test` green for `test/muscle_taxonomy_test.dart`, `test/muscle_links_storage_test.dart`, `test/muscle_filter_test.dart`, `test/catalog_referential_integrity_test.dart`, `test/db_seed_test.dart`. Expected red: none (old map and `lib/core` untouched, so everything compiles).
**Predicted Files A:** `lib/data/models/models.dart`, `lib/data/models/muscle_taxonomy.dart`, `lib/mock/seed_data.dart`, `lib/data/repositories/workout_repository.dart`, `lib/data/repositories/mock_workout_repository.dart`, `lib/data/repositories/hive_workout_repository.dart`, `scripts/sqlite_schema.sql`, `scripts/sqlite_seed.sql`, `test/muscle_taxonomy_test.dart`, `test/muscle_links_storage_test.dart`, `test/muscle_filter_test.dart`, `test/catalog_referential_integrity_test.dart`, `test/db_seed_test.dart`.

### Phase B · `crew-builder-app` · `--scope lib/core/**,test/**`

1. [ ] Switch `CatalogSource.exerciseMuscleGroups` to `Map<String, List<ExerciseMuscleLink>>` — `lib/core/services/catalog_source.dart:31-33` · `CatalogSource`
2. [ ] Feed `BundledCatalogSource` from `SeedData.exerciseMuscleLinks` — `lib/core/services/bundled_catalog_source.dart:29-33` · `BundledCatalogSource`
3. [ ] `_refreshMuscleGroups` also upserts when `parentId` differs — `lib/core/services/catalog_refresh_service.dart:114-124` · `_refreshMuscleGroups`
4. [ ] `_refreshExerciseMuscleGroups` compares links including roles (order-insensitive) and writes via `setExerciseMuscleLinks`; touched-exercise skip unchanged — `lib/core/services/catalog_refresh_service.dart:127-145` · `_refreshExerciseMuscleGroups`
5. [ ] `bundledCatalogVersion` 10 → 11 with a history sentence in the doc comment — `lib/core/constants/catalog_version.dart:46` · `bundledCatalogVersion`
6. [ ] `copyAsCustom` uses `getExerciseMuscleLinks`/`setExerciseMuscleLinks` — `lib/core/services/exercise_library_service.dart:255-259` · `copyAsCustom`
7. [ ] Update the four fakes' `exerciseMuscleGroups` threading — `test/catalog_refresh_test.dart:30/56/881`, `test/seeded_demos_test.dart:22/54`, `test/seeded_demos_state_test.dart:17/49` · `_FakeCatalogSource`/`_RoutinesFakeCatalogSource`
8. [ ] Write S-6 (scenario `S-MH-1`) and strengthen the copy test to S-7 — `test/catalog_refresh_test.dart`, `test/pr8_exercise_library_test.dart:139` · `S-MH-1`/copy test

**Done Criteria B:** `gateway.sh lint` (not above baseline) and `gateway.sh test` green for `test/catalog_refresh_test.dart`, `test/seeded_demos_test.dart`, `test/seeded_demos_state_test.dart`, `test/pr8_exercise_library_test.dart`. Expected red: none.
**Predicted Files B:** `lib/core/services/catalog_source.dart`, `lib/core/services/bundled_catalog_source.dart`, `lib/core/services/catalog_refresh_service.dart`, `lib/core/services/exercise_library_service.dart`, `lib/core/constants/catalog_version.dart`, `test/catalog_refresh_test.dart`, `test/seeded_demos_test.dart`, `test/seeded_demos_state_test.dart`, `test/pr8_exercise_library_test.dart`.

### Phase C · `crew-builder-data` · `--scope lib/data/**,lib/mock/**,test/**`

1. [ ] Delete `SeedData.exerciseMuscleGroupRelationships` — `lib/mock/seed_data.dart:4528-4940` · `exerciseMuscleGroupRelationships`
2. [ ] Rewrite R-001/R-004/R-005 onto the new map and taxonomy (S-3 full) — `test/catalog_referential_integrity_test.dart:22/:84/:96` · `R-001`/`R-004`/`R-005`
3. [ ] Add the migration body `_migrateMuscleLinkRoles`: for every key in the link store, read links (legacy shape → primary), `normalize`, write back in the new shape; skip nothing — `lib/data/repositories/hive_workout_repository.dart` · `_migrateMuscleLinkRoles` (new)
4. [ ] Append `_MethodStep(16, 'muscleLinkRoles', ...)` — `lib/data/repositories/hive_workout_repository.dart:272-325` · `_dataMigrationSteps`
5. [ ] Mock mirror `_MockMigrationStep(16, 'muscleLinkRoles', () => repo._migrateMuscleLinkRoles())` (existing class takes a body — see impact table I-8 note) — `lib/data/repositories/mock_workout_repository.dart:274-299` · `_dataMigrationSteps`
6. [ ] Write S-8 (fixtures A–E, touched row, idempotence, step list on both repos) — `test/data_migration_test.dart` · new tests

**Done Criteria C:** `gateway.sh lint` (not above baseline) and `gateway.sh test` green for `test/catalog_referential_integrity_test.dart` and the new S-8 tests. Expected red until phase D: `test/data_migration_test.dart:497` `expect(currentDataVersion, equals(15))`, the S-006 `getDataVersion() == currentDataVersion` assertions (the repo lands at 16 while the constant is 15), and S-156's `mockSteps.last.targetVersion == 15` / `hiveSteps.last == 15` (the shared step-list registry gains an entry, so its existing assertions go red by design).
**Predicted Files C:** `lib/mock/seed_data.dart`, `lib/data/repositories/hive_workout_repository.dart`, `lib/data/repositories/mock_workout_repository.dart`, `test/catalog_referential_integrity_test.dart`, `test/data_migration_test.dart`.

### Phase D · `crew-builder-app` · `--scope lib/core/constants/data_version.dart,test/data_migration_test.dart`

1. [ ] `currentDataVersion` 15 → 16 — `lib/core/constants/data_version.dart:36` · `currentDataVersion`
2. [ ] Update the `15` literal and S-156 wording — `test/data_migration_test.dart:497` · `S-156`

**Done Criteria D:** `gateway.sh test` green for `test/data_migration_test.dart` (whole file). Expected red: none after this phase.
**Predicted Files D:** `lib/core/constants/data_version.dart`, `test/data_migration_test.dart`.

### Phase E · `crew-docs-keeper` · `--scope docs/**`

1. [ ] Rewrite the MuscleGroup section: hierarchy, interpretation rules, roles; remove the `bodyRegion` correction note — `docs/data_models.md:193` · MuscleGroup section
2. [ ] Schema columns (`parent_id`, `is_primary` meaning), catalog version 11, data version 16 — `docs/db_integration.md:113/:201` · refresh/migration sections
3. [ ] `bundledCatalogVersion` value (the table carries the stale literal `3` at `:525`) and `currentDataVersion` (`:544`) — `docs/constants_reference.md` · constant table

**Done Criteria E:** docs stay below 52 KB per file; every behaviour sentence names an existing test; `gateway.sh lint` issue count not above baseline (docs-only change, no test run required).
**Predicted Files E:** `docs/data_models.md`, `docs/db_integration.md`, `docs/constants_reference.md`.

After E: `crew-prover` on S-3, S-4, S-5, S-6, S-8 guards; lead applies every `NOT PROVEN` mutation by hand; `crew-reviewer`.

## Progress

| Item | Result |
|---|---|
| A1 types | pending |
| A2 taxonomy | pending |
| A3 sampleMuscleGroups from taxonomy | pending |
| A4 exerciseMuscleLinks seed | pending |
| A5 repo interface | pending |
| A6 Mock storage + filters | pending |
| A7 Hive storage + filters + seeding | pending |
| A8 SQL schema + muscle inserts | pending |
| A9 S-1/S-2 taxonomy tests | done (14 tests, `test/muscle_taxonomy_test.dart`) |
| A10 S-3 new-map tests | done (8 new tests in `test/catalog_referential_integrity_test.dart`) |
| A11 S-4 storage tests | done (18 tests incl. S-10/S-11/S-13, `test/muscle_links_storage_test.dart`) |
| A12 S-5 filter tests | done (16 tests, `test/muscle_filter_test.dart`) |
| A13 S-9 SQL tests | done (1 new test in `test/db_seed_test.dart`) |
| B1 CatalogSource type switch | done |
| B2 BundledCatalogSource feed | done |
| B3 _refreshMuscleGroups parentId | done |
| B4 _refreshExerciseMuscleGroups links | done |
| B5 bundledCatalogVersion 11 | done |
| B6 copyAsCustom links | done |
| B7 four fakes updated | done |
| B8 S-6/S-7 tests | done |
| C1 delete old map | done (no `exerciseMuscleGroupRelationships` reader left in `lib/` or `test/`) |
| C2 R-001/R-004/R-005 rewrite | done (`test/catalog_referential_integrity_test.dart` green, 12 tests) |
| C3 _migrateMuscleLinkRoles body | done (both repos; iterate the link store's keys, poisoned row skipped) |
| C4 Hive step 16 | done (`_MethodStep(16, 'muscleLinkRoles', ...)`) |
| C5 Mock step 16 | done (`_MockMigrationStep(16, 'muscleLinkRoles', ...)`) |
| C6 S-8 tests | done (9 new tests in `test/data_migration_test.dart`, all green) |
| D1 currentDataVersion 16 | done (`lib/core/constants/data_version.dart`, doc comment unchanged — it names no version) |
| D2 S-156 literal update | done (list test + two re-run lists in `test/data_migration_test.dart`; whole file 20/20 green) |
| E1 data_models.md | done (MuscleGroup section rewritten: hierarchy table, link storage, interpretation + storage rules, each claim test-cited; `bodyRegion` correction note removed) |
| E2 db_integration.md | done (refresh carries parents + roles, catalog version 11; `muscleLinkRoles` step 16 in both migration passages; `app_muscle_group.parent_id` / `is_primary` SQL contract) |
| E3 constants_reference.md | done (`bundledCatalogVersion` 3 → 11, `currentDataVersion` 15 → 16; no catalog-entity list exists in the file, so no muscle ids added) |

## Assumption Log

- Phase B: the S-MH-1 test stages the "old install" by upserting the 16 pre-existing groups with
  `parentId: null` (and `muscle-traps` named `Trapezius`). The Mock repository has no API to remove a
  group, so the 7 new groups are already present after `initialize()` and the "adds 7 new groups" half
  of A6 is not shown on Mock (as the brief instructed). The parent-link, rename and role parts are
  asserted directly.
- Phase B: the copy in S-MH-1 is taken from `exercise-barbell-squat` (an untouched bundled row) and its
  post-refresh links are compared with that row's bundled links; the custom and touched rows are
  compared against their exact stored link lists.

## Feedback

- Finding 1 fixed (builder-data-fix-1): `_migrateMuscleLinkRoles` now reads and normalises a row inside one `try` and skips any unreadable/poisoned row; test `S-8: a corrupt row is left as it is and does not stop the step` added to `test/data_migration_test.dart`.

## Open questions (architect)

1. `scripts/sqlite_seed.sql:2484-2540` link rows already satisfy D-11 as written — every name still exists (Chest, Triceps, Shoulders, Quadriceps, Glutes, Hamstrings, Back, Biceps), `is_primary` is already used, and no row is a region+own-muscle pair (Pull-up's `Back` + `Biceps`: Biceps is under Arms, not Back). The SQL fixture's Deadlift is "Back primary" while the Dart seed's `exercise-deadlift` is glutes/hamstrings/lower-back primary; the SQL fixture is name-keyed and separate, and D-11 does not ask to re-tag it — so phase A item 8 touches only the schema and the muscle inserts. If the lead wants the SQL link rows re-tagged to match the Dart seed, that is new scope beyond D-11.
2. `MuscleGroup` has no `==`/`hashCode` override (`models.dart:924-943`) and the refresh compares groups by `name` only (`catalog_refresh_service.dart:121`); D-8's parentId patch needs no equality change. Noted so nobody "fixes" it in passing.
3. The seed's S-4 phrase "via `test/helpers/repository_harness.dart` (new `test/muscle_links_storage_test.dart`)" — the harness already exists (`test/helpers/repository_harness.dart:51`, `restart()` at `:56`); only the test file is new. Read as such.
4. `docs-audit:2026-07-26.md:120` also lists the `bodyRegion` claim; it is an audit snapshot, not a living doc, so it is outside phase E's scope. Say if it should be annotated.
