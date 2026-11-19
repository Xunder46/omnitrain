# 116 — The catalog refresh delivers every piece of app-authored reference data (except equipment)

> Status: Iteration 1 ready. No owner question: the change is invisible plumbing (D-19113). Derived decisions D-19105 and D-19106 are vetoable before Phase 2.
> Next handoff: @dba (Phase 1), run by the crew as `crew-builder-data` (writes `lib/data/**`, `test/**`).
> Phase 2 writes `lib/core/**`: `crew-builder-app` (or the lead). Phase 3: `crew-builder-data`.
> Binding conventions: `docs/global_conventions.md`, `docs/db_integration.md` ("Catalog version + seed-entry tombstones"), `docs/data_models.md`
> Track: phone only (`lib/`, `scripts/`, `test/`, `docs/`). Never branch or commit.
> Precedent: plans 114 and 115b (`docs/plans/2026-11-04-114-tibialis-muscle-plan/`, `docs/plans/2026-11-04-115b-strength-catalog-gaps-plan/`). Their refresh tests (`test/tibialis_muscle_refresh_test.dart`, `test/strength_catalog_v15_refresh_test.dart`) are the shape to copy.

## Overview

Classification: **STANDARD** (new repository surface, new refresh legs, a contract test). One PR.

Today the catalog refresh (`CatalogRefreshService.refresh()`, `lib/core/services/catalog_refresh_service.dart:53-68`)
delivers exercises, capabilities, muscle groups, muscle links, the food catalog and demo routines. Six more kinds of
app-authored reference data are written **at first install only** (`HiveWorkoutRepository._seedData()`,
`lib/data/repositories/hive_workout_repository.dart:613-691`; mirrored by `MockWorkoutRepository.initialize()`,
`lib/data/repositories/mock_workout_repository.dart:144-260`): sport categories, disciplines, tags, units, metric
definitions and metric effort kinds. A future seed change to any of them (for example a new discipline for a
conditioning exercise) would never reach a phone that already has the app. This PR adds them to the refresh and adds a
contract test that fails whenever a new piece of seed data is neither delivered nor explicitly excluded with a reason.

What a user sees: nothing today. Every phone that ran a build from 2026-04-22 on already holds exactly the bundled
rows (D-19113). After this PR, a later seed change to a category, discipline, tag, unit or metric reaches existing
phones on the next launch, the way new exercises do.

## Resolved Decisions (Ledger)

- **D-19101 Delivered kinds.** The refresh delivers, by id upsert, `SeedData.sampleSportCategories`,
  `SeedData.sampleDisciplines`, `SeedData.sampleTags`, `SeedData.defaultUnits`, `SeedData.defaultMetrics` and the
  metric effort kinds built from `SeedData.metricApplicability`. Basis (lead audit, re-verified 2026-11-04 at
  `27a137bb`): no code outside the seed path creates or edits them. `grep -rnE "\b(Discipline|Tag|UnitModel|MetricDefinition|SportCategory)\(" lib`
  outside `seed_data.dart`/`models.dart` finds only display fallbacks (`exercise_picker_screen.dart:393`,
  `exercise_library_screen.dart:261`, `orElse:`; never persisted) and Mock's `getSportCategoryByKey` fallback
  (`mock_workout_repository.dart:945`). The only box writers are `_seedData` (`:614-686`), `_migrateSeedUnits`
  (`:701`), `_migrateTimedExtraWeight` (`:805, 811`) and `_migrateExerciseLibraryRefresh` (`:841, 846`). The interface
  has getters only (`workout_repository.dart:115-161`). These are app-owned rows with no user edit surface, like muscle
  groups: **no touched-entry check** in these legs.
- **D-19102 Matching rule.** Each leg iterates the **bundled ids only**. For each bundled row: read the stored row by
  id; write the bundled row when it is absent or when any compared field differs. A row whose id is not in the bundle
  (a user row, even one with a clashing name or key) is never read or written. Nothing is ever deleted. Compared fields
  (timestamps are **never** compared, because seed rows carry `DateTime.now()` from class load and would otherwise
  rewrite every row on every refresh):
  - `SportCategory`: `key`, `name`, `description`, `iconName`, `sortOrder`, `deletedAtMs`
  - `Discipline`: `categoryId`, `key`, `name`
  - `Tag`: `name`
  - `UnitModel`: `key`, `name`, `unitType`
  - `MetricDefinition`: `key`, `name`, `dataType`, `defaultUnitId`, `isCore`, `appliesToEffortKind`
  - Metric effort kinds (`metricId → List<String>`): differ when the stored list and the bundled list differ **as
    multisets** (same length, and equal after sorting), the rule `_listEqualsIgnoreOrder` already applies to
    capabilities (`catalog_refresh_service.dart:400-408`). An absent stored entry reads as `[]`.
- **D-19103 What a write writes.** The bundled object verbatim, through the new upsert methods (D-19107): its own
  `createdAtMs`/`updatedAtMs` included, as `upsertMuscleGroup` does. Effort kinds are written in bundled order. A row
  that is equal on the compared fields keeps its stored timestamps (S-19104 proves it).
- **D-19104 Excluded, with reasons (the contract test's EXCLUDED rows carry these strings in substance).**
  - `sampleEquipment`, `exerciseEquipmentRelationships`: owner decision (115a D-18909, 115b D-19004). No screen reads
    equipment (`grep -rn -i equipment lib/features lib/widgets lib/state` → 0). Equipment reaches new installs only.
    Existing equipment rows and links are never removed.
  - `defaultFoodGroups`: the user can rename, archive and delete food groups, and there is no touched-entry marker for
    them; delivering would bring back a group the user deleted. Needs an owner decision; follow-up (Notes).
  - `sampleTemplateSegments`, `sampleTemplateEfforts`, `sampleTemplateTargets`: orphan rows of a retired seed. They
    are written at first install (`hive_workout_repository.dart:650-663`, `mock_workout_repository.dart:188-201`) but
    belong to templates `template-upper-strength`, `template-easy-run`, `template-boxing-rounds` and
    `template-mobility`, which nothing creates (`grep -rn "template-upper-strength\|template-easy-run'\|template-boxing-rounds'\|template-mobility'" lib test scripts`
    outside `seed_data.dart` → 0; the near-names `demo-template-easy-run-30` and `demo-template-boxing-rounds` are the
    demo bundles). Not delivered, not deleted.
  - `samplePlannedSessions`, `sampleTrainingPeriods`: user-data types, empty lists, never seeded.
  - `sampleTrainingSessions`, `sampleSessionSegments`, `sampleSessionBlocks`, `sampleSegmentEfforts`: developer
    reference fixtures, never seeded on either store (comments at `hive_workout_repository.dart:688-690`,
    `mock_workout_repository.dart:245-247`).
  - `sampleConsumedFoods()`: a user food log. Mock seeds it for the web/QA build (`mock_workout_repository.dart:241`);
    Hive never does. User data is never delivered.
- **D-19105 (derived, vetoable) `deletedAtMs` on categories.** The bundle is authoritative: a stored category whose
  `deletedAtMs` differs from the bundled one (bundled is `null` for all five) is rewritten with the bundled value. Basis:
  no code writes or reads `deletedAtMs` (`grep -rn "deletedAtMs\|deleted_at_ms" lib` → only `models.dart:16-51`), so a
  non-null value can only be corruption, and categories are not shown anywhere (`getSportCategor*` has no caller
  outside the repositories).
- **D-19106 (derived, vetoable) Leg order.** `refresh()` runs: sport categories, disciplines, units, metrics, metric
  effort kinds, tags, then the existing six legs in their current order (exercises, capabilities, muscle groups, muscle
  links, food catalog, demo routines), then `setCatalogVersion`. Disciplines reference categories, metrics reference
  units, kinds reference metrics, and exercises and demo templates reference disciplines.
- **D-19107 Repository surface.** Add to `WorkoutRepository` and implement in **both** `HiveWorkoutRepository` and
  `MockWorkoutRepository`, modelled on `upsertMuscleGroup` (`hive_workout_repository.dart:1766-1768`,
  `mock_workout_repository.dart:986-988`):
  ```dart
  Future<void> upsertSportCategory(SportCategory category);
  Future<void> upsertDiscipline(Discipline discipline);
  Future<void> upsertTag(Tag tag);
  Future<void> upsertUnit(UnitModel unit);
  Future<void> upsertMetricDefinition(MetricDefinition metric);
  /// Stored effort kinds of [metricId], in stored order; `[]` when absent.
  Future<List<String>> getMetricEffortKinds(String metricId);
  /// Replaces the effort kinds of [metricId] with a copy of [effortKinds].
  Future<void> setMetricEffortKinds(String metricId, List<String> effortKinds);
  ```
  Hive: `put(x.id, x.toMap())` on `_sportCategoriesBox`, `_disciplinesBox`, `_tagsBox`, `_unitsBox`, `_metricsBox`;
  kinds read `_asStringList(_metricEffortKindsBox.get(metricId))` and write `List<String>.from(effortKinds)` to
  `_metricEffortKindsBox` (box `metric_effort_kinds`, `Box<List>`). Mock: assign into `_sportCategories`,
  `_disciplines`, `_tags`, `_units`, `_metrics`, `_metricEffortKinds` (copies, never the caller's list). Each method's
  doc comment says it exists for the catalog refresh; the reference data has no user editing surface. Existing
  getters cover the reads (`getSportCategoryById`, `getDisciplineById`, `getTags`, `getUnitById`, `getMetricById`).
- **D-19108 Mock test hook.** Mock cannot remove reference rows, so add, next to `putRawExerciseMuscleLinksForTest`:
  ```dart
  @visibleForTesting
  Future<void> deleteReferenceRowForTest(String boxName, String id)
  ```
  `boxName` is the Hive box name: `sport_categories`, `disciplines`, `tags`, `units`, `metrics` or
  `metric_effort_kinds`; it removes `id` from the matching map; any other name throws `ArgumentError`. Tests stage a
  missing row through one helper that calls this on Mock and `Hive.box<Map>(boxName).delete(id)` (or
  `Hive.box<List>` for `metric_effort_kinds`) on Hive, so both harnesses share one fixture.
- **D-19109 Catalog source.** `CatalogSource` (`lib/core/services/catalog_source.dart`) gains:
  ```dart
  List<SportCategory> get sportCategories;
  List<Discipline> get disciplines;
  List<Tag> get tags;
  List<UnitModel> get units;
  List<MetricDefinition> get metricDefinitions;
  /// `metricId → effort kinds`, in `SeedData.metricApplicability` order.
  Map<String, List<String>> get metricEffortKinds;
  ```
  `BundledCatalogSource` returns `SeedData.sampleSportCategories`, `.sampleDisciplines`, `.sampleTags`,
  `.defaultUnits`, `.defaultMetrics`, and builds `metricEffortKinds` from `SeedData.metricApplicability` with the same
  `putIfAbsent(...).add(...)` loop `_seedData` uses (`hive_workout_repository.dart:680-686`). The three test fakes
  (`test/catalog_refresh_test.dart:27` `_FakeCatalogSource`, `test/seeded_demos_test.dart:17` and
  `test/seeded_demos_state_test.dart:12` `_RoutinesFakeCatalogSource`) return empty lists and an empty map, so their
  existing tests run the new legs as no-ops.
- **D-19110 Version.** `bundledCatalogVersion` 15 → 16 (`lib/core/constants/catalog_version.dart:62`). The library doc
  comment's first paragraph (`:3-4`) changes "(exercises, capability and muscle-group relationships, and the food
  catalog)" to "(sport categories, disciplines, units, metrics and their effort kinds, tags, exercises, capability and
  muscle-group relationships, the food catalog and demo routines; equipment and food groups are written at first install
  only)". Append to the history: "When the refresh learned to deliver sport categories, disciplines, units, metric
  definitions, metric effort kinds and tags, we bumped to `16` so every existing install reconciles them once on next
  launch; equipment, equipment links and the default food groups are still written at first install only."
  `currentDataVersion` is unchanged.
- **D-19111 Contract test.** New `test/catalog_delivery_contract_test.dart`, plain `test()`, specified by S-19108. The
  classification table is the single place a new seed member is accounted for.
- **D-19112 Out of scope.** Equipment delivery; food-group delivery; deleting or migrating the orphan template rows or
  the stale pre-April category `category-martial-arts` (never in today's bundle, so never read); exercise tags (no seed
  rows exist); the Mock-only `sampleConsumedFoods` seeding; any change to `_seedData`, the migrations, the watch, the
  sync contract, any screen, or `scripts/sqlite_seed.sql`. `scripts/sqlite_schema.sql` changes in one comment only.
- **D-19113 No visible change today (audit).** Semantic diff (timestamps ignored) of the six lists across all 31
  commits of `lib/mock/seed_data.dart`: categories and disciplines are identical to HEAD since `74c71c78`
  (2026-04-22), units since `6f2d8a82` (2026-03-31), metrics and applicability since `6f2d8a82`, tags since the first
  commit. `_migrateExerciseLibraryRefresh` (introduced `459a53a3`, 2026-04-22) rewrote categories and disciplines once
  on every older install. `metric-extra-weight` kinds on a migrated install are `[drill, timed]` and bundled
  `[timed, drill]`: equal as multisets. So a phone that ran any build from 2026-04-22 on holds the bundled content and
  the refresh writes nothing it can see. Only a phone that ran exactly the 2026-04-22 builds `459a53a3`/`d446e5da` and
  nothing later could hold `discipline-boxing`, `-bjj`, `-muay-thai` under `category-martial-arts`; on that phone the
  refresh moves them to `category-sports`, so in the Sports picker those exercises gain the discipline bonus and appear
  in the editor's Sports discipline list. Treated as theoretical (same-day dev builds; the catalog version itself only
  exists since 2026-07-05).

## Feature Invariants

- Additive and idempotent: no leg deletes a row; a row whose id is not bundled is never read or written (D-19102).
- Interruption-safe: the stored version advances only after every leg returns (`catalog_refresh_service.dart:66`).
- Mock and Hive return the same rows, kinds and refresh outcomes for every S-191xx fixture run on both. The one
  Mock-only case is the injected failure (S-19106) and the write counter (S-19105, S-19107), which need a subclass;
  the orchestrator is store-agnostic, so this is the 115a/115b precedent.
- Diff boundary: no file under `lib/features/`, `lib/widgets/`, `lib/state/`, `lib/watch/`, `watch/`, `lib/mock/`,
  `lib/data/models/`, and neither `lib/core/constants/data_version.dart` nor `scripts/sqlite_seed.sql` changes.

## Requirements and Acceptance Criteria

| Id | Acceptance (what a phone does) | Scenarios |
|---|---|---|
| A1 | A phone at version 15 missing a category, discipline, tag, unit, metric or effort-kind entry gets it back on next launch; exercises naming the discipline resolve it | S-19102 |
| A2 | Rows the user could own (different id, same name or key) are untouched and never duplicated | S-19103 |
| A3 | A bundled-id row that drifted from the bundle is corrected; a timestamp-only or order-only difference is not a difference | S-19104 |
| A4 | A second refresh writes nothing; a fresh install's refresh writes nothing in the new legs | S-19105, S-19107 |
| A5 | A failed refresh leaves the version at 15 and the next launch finishes the job | S-19106 |
| A6 | Every public `SeedData` member is delivered or excluded with a reason, and the table cannot rot | S-19108 |
| A7 | Repository methods round-trip on both stores and survive a Hive restart | S-19101 |

## Existing-Functionality Impact (greps run 2026-11-04 on `claude_develop` at `27a137bb`)

| Touched surface | Readers (grep) | Effect | Guard |
|---|---|---|---|
| `WorkoutRepository` (7 new members) | `grep -rln "implements WorkoutRepository\|extends WorkoutRepository" lib test` → the two repositories only; test doubles all `extends MockWorkoutRepository` (26 files) | Both implement; subclasses inherit | Phase 1 analyze + S-19101 |
| `CatalogSource` (6 new getters) | `grep -rn "implements CatalogSource" lib test` → `bundled_catalog_source.dart:15` and the three fakes (D-19109) | Fakes get empty overrides; compile otherwise breaks those 3 files | Phase 2 suites |
| Refresh leg order | `CatalogRefreshService` users: `lib/main.dart:269-274` (after `repository.initialize()` `:255`, before any state is built `:312+`) | New legs run before screens load disciplines (`exercise_library.dart:274`) | S-19102 |
| Disciplines on screen | `getDisciplines()` → `ExerciseLibrary` (`lib/state/workout/exercise_library.dart:274`) → editor, picker, library, detail screens; `ModalityConfig.disciplinesForModality` (`modality_config.dart:166-174`) filters by `categoryId`; ranking reads `discipline.categoryId` (`mock_workout_repository.dart:1166-1169`, `hive_workout_repository.dart:1982`) | Unchanged for realistic phones (D-19113) | S-19102 (exercise resolves its discipline) |
| Units, metrics, kinds, tags, categories on screen | `grep -rn "getSportCategor\|getTags()\|getExerciseTags\|getUnits()\|getUnitById\|getMetricDefinitions\|getMetricsForEffortKind\|getMetricById" lib` outside `lib/data/repositories/` → 0 | No reader outside the repositories | grep (re-run in review) |
| `metric_effort_kinds` box | `_migrateTimedExtraWeight` (`hive_workout_repository.dart:797-817`), `getMetricsForEffortKind` (`:1871-1887`; Mock `:1067-1078`) | Refresh corrects a drifted entry to the bundled multiset | S-19104 |
| Catalog version literals | `grep -rn "equals(15)" test` → `data_migration_test.dart:554,559` (`targetVersion`, the **data** version, unrelated); refresh tests stage with literals `setCatalogVersion(12/13/14)` and compare with `bundledCatalogVersion` | Bump to 16 turns nothing red | Phase 2 suites |
| Existing refresh tests over `BundledCatalogSource` | `catalog_referential_integrity_test.dart:442`, `strength_catalog_refresh_test.dart`, `strength_catalog_v15_refresh_test.dart`, `tibialis_muscle_refresh_test.dart`, `seeded_demos_*`, `food_orphan_category_integration_test.dart` | New legs find equal rows on a fresh install: no writes | Phase 2 suites |
| Docs that list what the refresh delivers | `docs/db_integration.md:108-112`, `docs/constants_reference.md:575, 579-582`, `docs/state_management/services_and_utils.md:204-215`, `scripts/sqlite_schema.sql:1631-1633`, `catalog_version.dart:3-4` | Each says categories/disciplines are first-install only; becomes stale | Phase 3 items + residue sweep |
| SQL contract | `grep -n "metric_effort\|applies_to_effort_kind" scripts/sqlite_schema.sql` → tables exist (`:344-352`); no DDL change | none | `db_seed_test.dart` green |

## UI Standards Impact

None. No UI file changes.

## Scenarios

Shared fixture notes. Mock+Hive scenarios run over `harnessFactories` (`test/helpers/repository_harness.dart:117`)
with plain `test()`, never `testWidgets`, with `const BundledCatalogSource()` and `const int _atMs = 1700000000000`.
"Stage missing" means the D-19108 helper. "Version 15" means `setCatalogVersion(15)` with the literal. Equality of a
row means `toMap()` equality (both stores).

### S-19101: Repository upsert and effort-kind round-trip (`test/reference_data_upsert_test.dart`, new, both harnesses)
- Fixture: fresh install (no staging), plus:
  - C `SportCategory(id: 'category-test', key: 'test_cat', name: 'Test', sortOrder: 99, createdAtMs: _atMs, updatedAtMs: _atMs)`
  - D `Discipline(id: 'discipline-test', categoryId: 'category-test', key: 'test_disc', name: 'Test Discipline', createdAtMs: _atMs, updatedAtMs: _atMs)`
  - T `Tag(id: 'tag-test', name: 'Test Tag', createdAtMs: _atMs)`
  - U `UnitModel(id: 'unit-test', key: 'tst', name: 'Testunits', unitType: 'count', createdAtMs: _atMs)`
  - M `MetricDefinition(id: 'metric-test', key: 'test', name: 'Test Metric', dataType: 'int', defaultUnitId: 'unit-test', createdAtMs: _atMs)`
- Trigger/flow: upsert C, D, T, U, M; read back; upsert each again with `name` + `' 2'`; read back;
  `setMetricEffortKinds('metric-test', ['set', 'timed'])`; on Hive `harness.restart()` and read everything again.
- Expected:
  - Each getter (`getSportCategoryById`, `getDisciplineById`, `getTags` by id, `getUnitById`, `getMetricById`) returns the
    upserted row (`toMap()` equal), then the renamed one; `getDisciplines()` holds `discipline-test` exactly once.
  - `getMetricEffortKinds('metric-pace')` == `['interval']` on a fresh install; `getMetricEffortKinds('metric-none')` == `[]`.
  - `getMetricEffortKinds('metric-test')` == `['set', 'timed']` (order kept); `getMetricsForEffortKind('timed')` ids contain `metric-test`.
  - Mutating the list passed to `setMetricEffortKinds` afterwards does not change the stored value.
  - Hive after restart: every value above unchanged.
  - Mock only: `deleteReferenceRowForTest('disciplines', 'discipline-test')` → `getDisciplineById` null; `deleteReferenceRowForTest('equipment', 'x')` throws `ArgumentError`.
- Red today: the methods do not exist (compile failure counts as red). Edge case of: none

### S-19102: A v15 phone missing reference rows refreshes to v16 (`test/catalog_reference_refresh_test.dart`, new, both harnesses)
- Fixture (after `harness.open()`):
  1. Stage missing: `sport_categories/category-recovery`, `disciplines/discipline-climbing`, `tags/tag-core`,
     `units/unit-cm`, `metrics/metric-pace`, `metric_effort_kinds/metric-pace`.
  2. Assert each is absent before the refresh (`getSportCategoryById` etc. return null; kinds `[]`).
  3. `exercise-climbing-session` exists with `disciplineId == 'discipline-climbing'` (bundled, untouched).
  4. Version 15.
- Trigger: `CatalogRefreshService(repo, const BundledCatalogSource()).refresh()`.
- Expected: returns `true`; `getCatalogVersion() == 16` and `bundledCatalogVersion == 16` (literal). Each staged row
  equals the bundled row on the D-19102 fields: `category-recovery` (`recovery_rehab`, "Recovery / Rehab", sortOrder
  10), `discipline-climbing` (`category-sports`, `climbing`, "Climbing"), `tag-core` ("Core"), `unit-cm` (`cm`,
  "Centimeters", `length`), `metric-pace` (`pace`, "Pace (min/km)", `real`, no default unit, core); kinds of
  `metric-pace` == `['interval']`. `getDisciplineById(exercise-climbing-session.disciplineId)` is non-null and named
  "Climbing". `getMetricsForEffortKind('interval')` ids contain `metric-pace`.
- Red today: stored 15 equals bundled 15, so the refresh returns false and nothing comes back. Edge case of: none

### S-19103: User rows that share a name or key stay byte-identical (same file, both harnesses)
- Fixture: S-19102 steps 1 and 4, plus user rows written through the D-19107 upserts:
  - `SportCategory(id: 'category-user-recovery', key: 'recovery_rehab', name: 'Recovery / Rehab', sortOrder: 10, createdAtMs: _atMs, updatedAtMs: _atMs)`
  - `Discipline(id: 'discipline-user-climbing', categoryId: 'category-sports', key: 'climbing', name: 'Climbing', createdAtMs: _atMs, updatedAtMs: _atMs)`
  - `Tag(id: 'tag-user-core', name: 'Core', createdAtMs: _atMs)`
  - `UnitModel(id: 'unit-user-cm', key: 'cm', name: 'centimeters', unitType: 'length', createdAtMs: _atMs)` (lower case: a near-twin)
  - `MetricDefinition(id: 'metric-user-pace', key: 'pace', name: 'Pace (min/km)', dataType: 'real', createdAtMs: _atMs)` and `setMetricEffortKinds('metric-user-pace', ['interval', 'set'])`
  - Record each user row's `toMap()` and its kinds.
- Expected after `refresh()`: each user row's `toMap()` and kinds are identical to the recorded ones. The bundled
  twins are back (S-19102 checks). Counts: `getSportCategories()` with key `recovery_rehab` → 2; `getDisciplines()`
  with key `climbing` → 2; `getTags()` named "Core" → 2; `getUnits()` with key `cm` → 2; `getMetricDefinitions()`
  with key `pace` → 2. No third row of any.
- Red today: the version gate skips the refresh, so the bundled twins stay absent (counts 1). Edge case of: S-19102

### S-19104: App-owned drift is corrected; timestamp-only and order-only differences are not (same file, both harnesses)
- Fixture (fresh install, then upserts with bundled ids; "bundled" = the `SeedData` row with the same id):
  - Drifted: `discipline-climbing` renamed "Bouldering"; `unit-kg` renamed "Kilos"; `category-sports` with `sortOrder: 99`;
    `category-recovery` with `deletedAtMs: _atMs` (D-19105); `tag-push` renamed "Pushing"; `metric-rpe` with
    `name: 'RPE'`; `setMetricEffortKinds('metric-extra-weight', ['drill'])` (missing `timed`).
  - Timestamp-only: `discipline-running`, `unit-lbs`, `tag-legs`, `category-cardio`, `metric-reps` rewritten with every
    compared field equal to the bundled row and `createdAtMs` (and `updatedAtMs` where the model has it) = `_atMs`.
  - Order-only: `setMetricEffortKinds('metric-rpe', ['amrap', 'round', 'timed', 'set'])` (bundled order is `set, timed, round, amrap`).
  - Not bundled: `Discipline(id: 'discipline-user-x', categoryId: 'category-sports', key: 'bouldering', name: 'Bouldering', …_atMs)`; record its `toMap()`.
  - Version 15.
- Expected after `refresh()`: every drifted row equals the bundled row on the D-19102 fields (`category-recovery`
  `deletedAtMs` is null again; `metric-extra-weight` kinds equal `{drill, timed}` as a multiset). Every
  timestamp-only row still has `createdAtMs == _atMs` (not rewritten). `metric-rpe` kinds are still exactly
  `['amrap', 'round', 'timed', 'set']` in that order (not rewritten). `discipline-user-x` is identical to its recording.
  A comment in the test states these rows have no user edit surface, so the bundle owns them (D-19101).
- Red today: the gate skips the refresh, so the drift stays. Edge case of: S-19102

### S-19105: The refresh is idempotent (same file)
- Fixture (a) both harnesses: S-19102's fixture, `refresh()` once (true), then record `toMap()` of every bundled-id row
  of the six kinds and every bundled metric's kinds.
- Expected (a): a second `refresh()` returns `false`; version stays 16; recordings unchanged.
- Fixture (b) Mock only: a `_CountingReferenceRepo extends MockWorkoutRepository` that records `'<method>:<id>'` for
  every call to the six D-19107 writers and then calls `super`. `initialize()`, version 15, `refresh()` → true; clear
  the record; version 15 again; `refresh()`.
- Expected (b): the second run returns `true` (the version was behind) and the record is empty: no reference write.
- Red today: (b) fails to compile (no writers). Edge case of: S-19102

### S-19106: An interrupted refresh keeps version 15 and the next launch finishes (same file, Mock only)
- Fixture: `_FailingDisciplineRepo extends MockWorkoutRepository` with `bool failing = true` and a call counter; while
  `failing`, its `upsertDiscipline` throws `StateError('simulated mid-refresh failure')` on the **2nd** call and calls
  `super` otherwise. `initialize()`; stage missing (via the D-19108 hook) `category-recovery`, `discipline-golf`,
  `discipline-climbing` (bundled order: golf before climbing, `seed_data.dart:296, 304`), `unit-cm`; `deleteExercise('exercise-sit-up')`; version 15.
- Expected: `refresh()` throws `StateError`; version is still 15; `category-recovery` and `discipline-golf` exist
  (legs ran up to the failure); `discipline-climbing`, `unit-cm` and `exercise-sit-up` are still absent (no later leg
  ran). Then `failing = false`; `refresh()` returns true; version 16; all five exist.
- Red today: no discipline leg, so nothing throws. Edge case of: S-19102

### S-19107: A fresh install is unaffected (same file)
- Fixture (a) both harnesses: fresh install, no staging; record `toMap()` of every bundled-id row of the six kinds,
  their kinds, `getEquipment()` names and `getFoodGroups(includeArchived: true)` ids; version 15.
- Expected (a): `refresh()` returns true; every recording unchanged; equipment names and food-group ids unchanged.
- Fixture (b) Mock only: `_CountingReferenceRepo` (S-19105), fresh, version 15.
- Expected (b): the record is empty after `refresh()`.
- Edge case of: none

### S-19108: Every seed member is delivered or excluded (`test/catalog_delivery_contract_test.dart`, new, pure + empty Mock)
- Fixture:
  - Text of `lib/mock/seed_data.dart` from `class SeedData {` to the first line that is exactly `}` after it. Public
    members = every line matching `^  static ` whose declared name (the identifier before ` =` or `(`) does not start
    with `_`. Today that is 24 names: the 11 COVERED and 13 EXCLUDED below. Sanity: the parsed set contains
    `sampleExercises` (a field) and `sampleConsumedFoods` (a method), so a broken regex cannot pass vacuously.
  - Every `SeedData.<name>` in `lib/data/repositories/hive_workout_repository.dart` and `mock_workout_repository.dart`.
  - The table (a `Map<String, …>` in the test):

  | Member | Class | CatalogSource getter / reason |
  |---|---|---|
  | `sampleSportCategories` | COVERED | `sportCategories` |
  | `sampleDisciplines` | COVERED | `disciplines` |
  | `sampleTags` | COVERED | `tags` |
  | `defaultUnits` | COVERED | `units` |
  | `defaultMetrics` | COVERED | `metricDefinitions` |
  | `metricApplicability` | COVERED | `metricEffortKinds` |
  | `sampleExercises` | COVERED | `exercises` |
  | `exerciseCapabilityRelationships` | COVERED | `exerciseCapabilities` |
  | `sampleMuscleGroups` | COVERED | `muscleGroups` |
  | `exerciseMuscleLinks` | COVERED | `exerciseMuscleGroups` |
  | `sampleDemoRoutineBundles` | COVERED | `routineTemplates` |
  | `sampleEquipment`, `exerciseEquipmentRelationships` | EXCLUDED | D-19104 equipment reason |
  | `defaultFoodGroups` | EXCLUDED | D-19104 food-group reason |
  | `sampleTemplateSegments`, `sampleTemplateEfforts`, `sampleTemplateTargets` | EXCLUDED | D-19104 orphan reason |
  | `samplePlannedSessions`, `sampleTrainingPeriods` | EXCLUDED | user data, never seeded |
  | `sampleTrainingSessions`, `sampleSessionSegments`, `sampleSessionBlocks`, `sampleSegmentEfforts` | EXCLUDED | dev fixtures, never seeded |
  | `sampleConsumedFoods` | EXCLUDED | user log; Mock-only QA seed |

  (11 COVERED rows + 13 EXCLUDED names = 24. The food catalog lives in `FoodCatalogSeed`, outside `SeedData`, and is
  covered by `foodCatalog`; the test states this in a comment.)
- Expected (each its own `test()`):
  1. Every parsed member and every repository-referenced name is a table key. Failure message names the member.
  2. Every table key is a parsed member (a stale row fails).
  3. Every EXCLUDED reason is non-empty after trimming.
  4. For every COVERED row: `lib/core/services/bundled_catalog_source.dart` text contains `get <getter>` and
     `SeedData.<member>`; and the ids the getter returns on `const BundledCatalogSource()` equal, as a non-empty set,
     the ids of the seed member (for maps: the keys; for `metricApplicability`: the distinct `metricId`s; for demo
     bundles: `template.id`).
  5. Delivery: a `MockWorkoutRepository()` on which `initialize()` is **not** called (empty store, catalog version 0).
     For every COVERED row, assert first that none of its ids is stored, then run `CatalogRefreshService(repo, const BundledCatalogSource()).refresh()` once,
     then assert every id is stored (exercises `getExerciseById`; capabilities, muscle links and effort kinds equal the
     bundled lists as multisets; muscle groups `getMuscleGroups`; demo routines `getTemplateById`; the six reference
     kinds by their getters). Also: `getEquipment()` is empty and `getFoodGroups(includeArchived: true)` is empty
     afterwards (the EXCLUDED rows really are not delivered).
- Red today: the six reference rows fail check 4 (no getter) and check 5 (not delivered). Mutations the lead will run:
  a dummy `static final List<Tag> dummyList = [];` in `SeedData` fails check 1; deleting the `_refreshDisciplines`
  call from `refresh()` fails check 5 for `sampleDisciplines`.
- Edge case of: none

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/db_integration.md | MODIFIED | disciplines and categories are written at first | also delivers sport categories | S-19102 |
| docs/db_integration.md | ADDED | - | catalog_delivery_contract_test.dart | S-19108 |
| docs/constants_reference.md | MODIFIED | demo routines; equipment links, disciplines and categories | demo routines; equipment, equipment links and the default food groups | D-19110 |
| docs/constants_reference.md | MODIFIED | disciplines and categories are not delivered by the refresh | default food groups are not delivered | D-19104 |
| docs/state_management/services_and_utils.md | ADDED | - | catalog_delivery_contract_test.dart | S-19108 |

## Iteration 1

### Phase 1: Repository surface (@dba · `crew-builder-data`)
1. [ ] Record baselines in the evidence file: `flutter analyze` issue count (plan 114/115b: 181) and pass/fail counts of the Phase 2 suite list — `2026-11-04-116-catalog-delivery-plan.evidence.md`
2. [ ] Write S-19101 in new `test/reference_data_upsert_test.dart`; run it and paste the red (compile failure)
3. [ ] Add the seven D-19107 members with doc comments, after `getMetricById` in the Metrics section (kinds) and beside each kind's getters (upserts) — `lib/data/repositories/workout_repository.dart:115-161`
4. [ ] Implement them in Hive, in the SPORT CATEGORIES / DISCIPLINES / TAGS / UNITS / METRICS sections — `lib/data/repositories/hive_workout_repository.dart:1705-1894`
5. [ ] Implement them in Mock, same sections, plus `deleteReferenceRowForTest` (D-19108) next to `putRawExerciseMuscleLinksForTest` — `lib/data/repositories/mock_workout_repository.dart:930-1080` (hook beside `:1011`)
6. [ ] S-19101 green on both harnesses; paste counts; update Progress and the Assumption Log

**Done Criteria** (Claude agents wrap in `bash .claude/scripts/macos/with-timeout.sh`; Copilot agents use the gateway):
- `flutter analyze`: issue count ≤ the item-1 baseline
- `flutter test test/reference_data_upsert_test.dart test/catalog_refresh_test.dart test/data_migration_test.dart test/catalog_referential_integrity_test.dart`
- `flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart`
- `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` prints nothing

**Predicted Files**: `lib/data/repositories/workout_repository.dart`, `hive_workout_repository.dart`, `mock_workout_repository.dart`, `test/reference_data_upsert_test.dart` (new), evidence file. Production diff: about 125 lines.

### Phase 2: Source getters, refresh legs, version 16 (@developer · `crew-builder-app`, writes `lib/core/**`)
1. [ ] Add the six D-19109 getters with doc comments — `lib/core/services/catalog_source.dart` · `CatalogSource`
2. [ ] Implement them — `lib/core/services/bundled_catalog_source.dart` · `BundledCatalogSource`
3. [ ] Add empty overrides to the three fakes — `test/catalog_refresh_test.dart:27`, `test/seeded_demos_test.dart:17`, `test/seeded_demos_state_test.dart:12`
4. [ ] Write S-19102 to S-19107 in new `test/catalog_reference_refresh_test.dart` (copy the shape of `test/strength_catalog_v15_refresh_test.dart`: header comment naming this plan and the S-ids, `harnessFactories`, Hive staging in the test body); run and paste the red
5. [ ] Add six private legs (`_refreshSportCategories`, `_refreshDisciplines`, `_refreshUnits`, `_refreshMetricDefinitions`, `_refreshMetricEffortKinds`, `_refreshTags`) with one `…Differs` helper per model implementing D-19102, called in D-19106 order; extend the class doc ("app-authored reference data has no touched-entry check") — `lib/core/services/catalog_refresh_service.dart:53-68` · `refresh()`
6. [ ] Set `bundledCatalogVersion = 16` and make both D-19110 comment edits — `lib/core/constants/catalog_version.dart:3-4, 58-62`
7. [ ] Show red→green: revert items 5–6 → S-19102..S-19107 red (S-19107(a) may stay green: say so); restore → green. Record the table in the evidence file; update Progress and the Assumption Log

**Done Criteria**:
- `flutter analyze` ≤ baseline
- `flutter test test/catalog_reference_refresh_test.dart test/reference_data_upsert_test.dart test/catalog_refresh_test.dart test/seeded_demos_test.dart test/seeded_demos_state_test.dart test/catalog_referential_integrity_test.dart test/strength_catalog_refresh_test.dart test/strength_catalog_v15_refresh_test.dart test/tibialis_muscle_refresh_test.dart test/food_orphan_category_integration_test.dart test/data_migration_test.dart`
- `flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart`
- `grep -n "bundledCatalogVersion = 16" lib/core/constants/catalog_version.dart` → 1 line; the AGENTS.md hive-import grep prints nothing

**Predicted Files**: `lib/core/services/catalog_source.dart`, `lib/core/services/bundled_catalog_source.dart`, `lib/core/services/catalog_refresh_service.dart`, `lib/core/constants/catalog_version.dart`, `test/catalog_reference_refresh_test.dart` (new), `test/catalog_refresh_test.dart`, `test/seeded_demos_test.dart`, `test/seeded_demos_state_test.dart`, evidence file. Production diff: about 190 lines.

### Phase 3: Contract test, docs, residue sweep (@dba · `crew-builder-data`)
1. [ ] Write S-19108 in new `test/catalog_delivery_contract_test.dart`. Prove it bites: add `static final List<Tag> dummyList = [];` to `SeedData` → check 1 red; comment out the `_refreshDisciplines` call → check 5 red; restore both (the seed and service edits are temporary and must not remain). Paste all three runs
2. [ ] Replace "Equipment links, disciplines and categories are written at first install only; the refresh does not deliver them" with: the refresh also delivers sport categories, disciplines, units, metric definitions, metric effort kinds and tags (version `16`, cite `test/catalog_reference_refresh_test.dart` `S-19102`, `S-19103`, `S-19106`); equipment, equipment links and the default food groups are written at first install only (cite `test/catalog_delivery_contract_test.dart`); add the S-19108 sentence that every `SeedData` member is classified — `docs/db_integration.md:108-112` (42,715 B; stay under 53,248)
3. [ ] Table row `15` → `16` and the Notes text to the D-19110 list; replace "Equipment links, disciplines and categories are not delivered by the refresh." with "Equipment, equipment links and the default food groups are not delivered by the refresh." — `docs/constants_reference.md:575, 579-582` (27,482 B)
4. [ ] One sentence after the `BundledCatalogSource` description listing the reference getters and pointing at the contract test — `docs/state_management/services_and_utils.md:204-215` (36,128 B)
5. [ ] Comment only: "(exercises + capability / muscle-group relationships + the food catalog; equipment is written at first install only)" → "(sport categories, disciplines, units, metrics and their effort kinds, tags, exercises + capability / muscle-group relationships + the food catalog; equipment and food groups are written at first install only)" — `scripts/sqlite_schema.sql:1631-1633`
6. [ ] Residue sweep, pasted into the evidence file: `grep -rn "disciplines and categories\|first install only" docs lib scripts | grep -v "docs/plans\|docs/history\|docs/releases"` prints only lines naming equipment / food groups; `grep -n "bundledCatalogVersion" docs/constants_reference.md` shows `16`; `wc -c docs/db_integration.md docs/constants_reference.md docs/state_management/services_and_utils.md` each < 53,248
7. [ ] Full suite `flutter test` (900 s, output to a file); paste the totals; update Progress

**Done Criteria**: `flutter test test/catalog_delivery_contract_test.dart test/catalog_reference_refresh_test.dart test/db_seed_test.dart test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart`; full `flutter test` with 0 failures; `flutter analyze` ≤ baseline; hive-import grep prints nothing; `git diff -- scripts/sqlite_schema.sql` touches comment lines only.
**Predicted Files**: `test/catalog_delivery_contract_test.dart` (new), `docs/db_integration.md`, `docs/constants_reference.md`, `docs/state_management/services_and_utils.md`, `scripts/sqlite_schema.sql`, evidence file. Production diff: 3 comment lines.

### Phase 4: Review (@code-reviewer)
Diff versus every phase's Predicted Files and the Diff-boundary invariant:
`git diff --stat -- lib/features lib/widgets lib/state lib/watch watch lib/mock lib/data/models lib/core/constants/data_version.dart scripts/sqlite_seed.sql`
prints nothing. Re-run every Impact grep. Check D-19102's field lists against each `…Differs` helper line by line, and
that no leg reads an id outside the bundle. Parity: each of the seven methods behaves the same in both repositories
(S-19101 runs on both). Mutations, each of which must turn the named tests red:
- M1: compare `createdAtMs` in the discipline differ → S-19104 (timestamp-only row rewritten), S-19105(b), S-19107(b)
- M2: order-sensitive kinds compare → S-19104 (order-only), S-19105(b), S-19107(b)
- M3: move `_refreshDisciplines` after `_refreshExercises` → S-19106 (`exercise-sit-up` present after the failure)
- M4: version left at 15 → S-19102..S-19105
- M5: `upsertUnit` in Mock left as a no-op → S-19101, S-19102
- M6: drop `sampleTags` from the contract table → S-19108 check 1
- M7: `_refreshTags` iterates stored tags and rewrites by name → S-19103 (`tag-user-core` changed or duplicated)

Findings go in `2026-11-04-116-catalog-delivery-plan.review.md`.

## Files Affected

Production: `workout_repository.dart`, `hive_workout_repository.dart`, `mock_workout_repository.dart`,
`catalog_source.dart`, `bundled_catalog_source.dart`, `catalog_refresh_service.dart`, `catalog_version.dart`,
`sqlite_schema.sql` (comment). About 320 lines.
Read-only dependents, guarded by tests: `lib/main.dart` (refresh call), `ExerciseLibrary` and the exercise screens
(discipline lists), `ModalityConfig.disciplinesForModality`, both repositories' ranking, `getMetricsForEffortKind`.

## Notes

- **Scope budget (measured at planning):** 3 implementation phases + review, one track, 13 decisions, 8 scenarios,
  about 320 predicted production lines, no missing prerequisite. No soft signal fires: no split.
- **Dependency graph:** 1 → 2 → 3 → 4. Phase 2 needs Phase 1's interface; Phase 3's contract check 5 needs Phase 2's
  legs. Running Phase 3 item 1 before Phase 2 would only show it red.
- **Intermediate states:** after Phase 1 the methods exist but nothing calls them (shippable, invisible). After Phase 2
  the version is 16 and docs are stale until Phase 3: do not ship that state.
- **Why the uninitialized Mock in S-19108:** it is the only store that is empty of every COVERED member without new
  wipe hooks; its catalog version starts at 0 (`mock_workout_repository.dart:106`). If the refresh throws on it, log
  it in the Assumption Log, and fall back to an initialized Mock with each COVERED member's ids removed through the
  existing deletes (`deleteExercise`, `setExerciseCapabilities(id, [])`, `setExerciseMuscleLinks(id, [])`) plus the D-19108 hook.
- **Follow-ups (priced, NOT in this PR):**
  - *Food-group delivery*: needs an owner call on whether a deleted default group may come back, and a touched-entry
    marker for food groups. One @dba PR, about 80 lines.
  - *Equipment delivery*: carried from 115a/115b, about 100–150 lines.
  - *Orphan template rows*: a data migration could remove `tseg-*`/`teff-*`/`ttar-*` rows of the four retired
    template ids from existing phones and stop seeding them; invisible today.
  - *Docs drift seen, not fixed*: `docs/data_models.md:412` says the bundled food seed "is loaded once on first install
    and stays at its shipped values"; the refresh updates untouched bundled foods (`_refreshFoodCatalog`).

## Progress
- [x] Phase 1 · [x] Phase 2 · [x] Phase 3 · [x] Phase 4 review (APPROVE WITH FIXES; fixes applied)

## Assumption Log

## Feedback
