# Feature: Consolidated Data-Migration Version Sequence

## Overview
OmniTrain currently applies data updates through thirteen independent one-time steps, each tracked by its own on/off marker in the meta box (`seed_loaded`, `seed_units_migrated_v1`, `exercise_round_defaults_migrated_v1`, `session_feeling_fields_migrated_v1`, `calendar_data_seeded_v1`, `calendar_seed_purged_v1`, `exercise_content_fields_migrated_v1`, `timed_extra_weight_migrated_v1`, `exercise_library_refreshed_v5`, `nutrition_targets_daily_migrated_v1`, `food_catalog_seeded_v1`, `default_food_groups_seeded_v1`, `food_category_groupid_migrated_v1`). This is fragile — every shipped change needs a new marker wired in by hand, and forgetting to do so silently strands the change on existing devices (this is how the bilateral gap slipped through). This consolidates the thirteen steps into one ordered update sequence tracked by a single `data_version` integer for the device. On launch, the repository reads the device's `data_version`, applies any pending steps in order, and advances the version only after each step succeeds. Existing installs that already completed the legacy steps are mapped to the current version via a one-shot back-compat shim so the steps are not re-run; installs that completed only some steps apply only the remaining ones. The thirteen consolidated steps preserve the exact current effect of the legacy steps they replace — this is a behavior-preserving refactor of working machinery, not a change to what the updates do. The catalog content-refresh mechanism (`catalog_version`, `seed_entry_touched_*`) is a separate, always-checked mechanism and stays untouched.

## Requirements
- A single `data_version` integer is the device's record of "what data-migration step the device has reached".
- The app carries a `currentDataVersion` constant (the latest version, after all steps).
- The thirteen existing one-time steps are wrapped in a single ordered sequence, in the same order they currently run inside `HiveWorkoutRepository.initialize()`.
- Each step has a `targetVersion` (the version the device lands at after running it) and a `name` (for diagnostics).
- On launch, the repository reads the device's `data_version`. If it is unset or at the legacy default, the back-compat shim maps legacy markers to a starting version. Then, the repository runs every pending step in order; after each step succeeds, it advances `data_version`. If any step throws, `data_version` does NOT advance past the failing step, and the exception re-raises so `main.dart` handles it (the next launch retries from the failing step).
- Running the sequence when `data_version == currentDataVersion` is a no-op.
- A failing step is retried on the next launch with prior data intact.
- Each step preserves its existing effect — same box writes, same upsert semantics, same idempotency — only the gating changes (legacy `bool` marker → version check).
- The most recent `from → to` transition is recorded in the meta box (`data_version_last_from`, `data_version_last_to`) so support / debugging tools can see what migration the device just ran.
- Catalog content versioning (`catalog_version`, `seed_entry_touched_*`) stays untouched; it is a separate always-on check.
- Mock + Hive both implement the new methods and run the migration sequence.

## Acceptance Criteria
- [ ] A fresh install applies all thirteen steps in order and lands at `currentDataVersion`.
- [ ] An install that had applied all thirteen legacy markers starts at `currentDataVersion` and runs no steps (one-time shim ran, then short-circuit).
- [ ] An install that had applied only some of the legacy markers starts at the correct intermediate version and applies exactly the remaining steps, in order.
- [ ] A step that throws leaves `data_version` unchanged and is retried on the next launch (no partial state for that step persists; subsequent steps do not run; the device's other data is intact).
- [ ] Running the sequence at `currentDataVersion` performs no work and leaves the version unchanged.
- [ ] Each consolidated step produces the same end state as the legacy one-time step it replaced (no behavioral regression).
- [ ] The most recent `from → to` transition is recorded.
- [ ] Catalog content versioning (`catalog_version` / `seed_entry_touched_*`) is untouched and still runs every launch.

## Scenarios

### S-001: Fresh install runs all thirteen steps in order, lands at current version
- Trigger: A fresh install (no meta-box keys present) launches.
- Precondition: Mock repo with no `data_version`, no legacy markers.
- Flow: `initialize()` → `_runDataMigrations()` → shim finds no legacy markers → starting version = 1 → step list runs in order → device lands at `currentDataVersion`.
- Expected outcome: `getDataVersion() == currentDataVersion`; every step's effect is visible in the repo state (seed units present, exercise round defaults present, food catalog present, etc.); `getLastDataVersionTransition() == (from: 1, to: currentDataVersion)`.
- Edge case of: none

### S-002: Legacy install with all legacy markers is mapped to current version, no steps run
- Trigger: An existing install on the old code path with all thirteen legacy markers present upgrades to the new code and launches.
- Precondition: Mock repo with `_seedLoadedKey`, `_seedUnitsMigrationKey`, `_exerciseRoundDefaultsMigrationKey`, `_sessionFeelingFieldsMigrationKey`, `_calendarDataMigrationKey`, `_calendarSeedPurgeMigrationKey`, `_exerciseContentFieldsMigrationKey`, `_timedExtraWeightMigrationKey`, `_exerciseLibraryRefreshMigrationKey`, `_nutritionTargetsDailyMigrationKey`, `_foodCatalogSeededKey`, `_defaultFoodGroupsSeededKey`, `_foodCategoryGroupIdMigratedKey` all set to `true`. `data_version` is unset.
- Flow: `initialize()` → shim finds all legacy markers → starting version = `currentDataVersion` → step loop sees no pending steps → short-circuit.
- Expected outcome: `getDataVersion() == currentDataVersion`; no step's `run()` was invoked; the transition is recorded as `(from: currentDataVersion, to: currentDataVersion)` to mark the upgrade path; existing data is untouched.
- Edge case of: S-001

### S-003: Partial legacy install applies only the remaining steps
- Trigger: An existing install on the old code path that completed only the first five legacy steps upgrades and launches.
- Precondition: Mock repo with `_seedLoadedKey`, `_seedUnitsMigrationKey`, `_exerciseRoundDefaultsMigrationKey`, `_sessionFeelingFieldsMigrationKey`, `_calendarSeedPurgeMigrationKey` set to `true`; later legacy markers unset.
- Flow: `initialize()` → shim finds the highest legacy marker = `_calendarSeedPurgeMigrationKey` (the 6th step's marker, since step 5's purge marker is what really represents step 5's completion) → starting version = 7 → steps 7–13 run in order → device lands at `currentDataVersion`.
- Expected outcome: `getDataVersion() == currentDataVersion`; only steps 7–13's effects are visible in the repo state; transition recorded as `(from: 7, to: currentDataVersion)`.
- Edge case of: S-001

### S-004: A failing step leaves the version unchanged and is retried
- Trigger: One step in the sequence throws partway through the device's startup.
- Precondition: Mock repo with no `data_version`; one step in the test step list is rigged to throw on first invocation.
- Flow: `initialize()` → shim → steps run in order → failing step throws → `data_version` is NOT advanced past the failing step → exception re-raised.
- Expected outcome: `getDataVersion()` equals the failing step's predecessor's target version (one less than the failing step's target); previous steps' effects are present; the failing step's effects are NOT present; on a subsequent launch (with the thrower fixed), the failing step runs and `data_version` advances to `currentDataVersion`.
- Edge case of: S-001

### S-005: Running the sequence at current version is a no-op
- Trigger: A device whose `data_version` already equals `currentDataVersion` launches.
- Precondition: Mock repo with `data_version = currentDataVersion`.
- Flow: `initialize()` → shim sees shim-detected starting version = `currentDataVersion` → step loop short-circuits.
- Expected outcome: No step's `run()` is invoked; `getDataVersion()` unchanged; `getLastDataVersionTransition()` unchanged.
- Edge case of: S-001

### S-006: Behavioral parity — each step's effect matches its legacy counterpart
- Trigger: For each consolidated step, an integration test that drives the step on a clean state and compares the resulting repo state against the same setup driven by the legacy method body.
- Precondition: A helper that runs the legacy method body and the new step against the same starting state and snapshots both outcomes.
- Flow: For each step in the sequence, run the snapshot comparison.
- Expected outcome: For every step, the snapshot of `getExercises()`, `getExerciseCapabilities(...)`, `getExerciseMuscleGroups(...)`, `getUnits()`, `getCatalogFoods()`, `getFoodGroups()`, etc. matches between the legacy and new paths.
- Edge case of: S-001

### S-007: Catalog versioning still runs every launch (orthogonality)
- Trigger: After the data-migration refactor, the device's catalog refresh still runs at `currentDataVersion`.
- Precondition: Repo at `data_version = currentDataVersion`; bundled catalog version ahead.
- Flow: `main.dart` runs `CatalogRefreshService.refresh()` after `repository.initialize()`.
- Expected outcome: Catalog refresh still works as before — `getCatalogVersion()` advances and missing seed entries are written. This scenario is a sanity check that the refactor did not break the catalog-refresh wiring.
- Edge case of: S-005

## Iteration 1

### DB Changes
- New meta-box keys:
  - `data_version` (int) — current data-version sequence position.
  - `data_version_last_from` (int) — last migration starting version (for diagnostics).
  - `data_version_last_to` (int) — last migration ending version (for diagnostics).
- No new tables, no new columns, no schema migrations outside the meta box.
- SQLite parity: see "DATA-MIGRATION VERSION SEQUENCE (July 2026)" appended to `scripts/sqlite_schema.sql` documenting the new meta-box keys and the upcoming `app_meta` table mapping.

### Backend Changes
- New repository interface methods on `WorkoutRepository` (`lib/data/repositories/workout_repository.dart`):
  - `Future<int> getDataVersion({int defaultValue = 1})`
  - `Future<void> setDataVersion(int version)`
  - `Future<int> getLegacyAppliedDataVersion()` — for the back-compat shim only; returns the highest version implied by any legacy marker (1 if none).
  - `Future<({int from, int to})?> getLastDataVersionTransition()` — diagnostic.
  - `Future<void> setLastDataVersionTransition(int from, int to)` — diagnostic.
- Implement those five methods in `HiveWorkoutRepository` (via `_metaBox`) and in `MockWorkoutRepository` (via in-memory fields).
- New `lib/core/constants/data_version.dart`:
  - `currentDataVersion = 13` (the version after all thirteen consolidated steps).
  - A typed `DataMigrationStep` interface — `int get targetVersion`, `String get name`, `Future<void> run()`.
- New `lib/core/services/data_migration_service.dart`:
  - Constructor: `(WorkoutRepository, int targetVersion, List<DataMigrationStep> steps)`.
  - `Future<DataMigrationResult> run()`:
    1. Read `data_version` from repo (default 1).
    2. If `data_version == 1`, call `repo.getLegacyAppliedDataVersion()` and use the higher of the two as the effective starting version. Write back via `setDataVersion` so the shim runs once.
    3. If effective starting >= target, record `(from: starting, to: starting)` transition and return early.
    4. For each pending step (in order), await `step.run()`. On success, `setDataVersion(step.targetVersion)`. On throw, re-raise (no version advance).
    5. After the loop, `setLastDataVersionTransition(starting, target)`. Return `DataMigrationResult(from, to, appliedSteps)`.
  - `DataMigrationResult` is a record-like class exposing `from`, `to`, `appliedSteps` for diagnostics / logging.
- Refactor `HiveWorkoutRepository.initialize()`:
  - Remove all thirteen `await _migrateX()` / `await _seedY()` calls and the `if (!seedLoaded)` gate.
  - Add a single `await _runDataMigrations()` that constructs the `DataMigrationService` with the steps in current order and awaits `run()`.
  - Each step's `run()` is a closure that calls the existing private method body (e.g. `(repo) => _migrateSeedUnitsBody()`). This keeps the behavior identical — only the gating changes from `bool marker` to `version check`.
  - Add `MockWorkoutRepository.initialize()` mirror: in-memory `currentDataVersion` advancement, same step list, same order.
- Backwards-compat shim mapping (highest legacy marker wins):
  | Legacy marker | Implied version |
  |---|---|
  | (none) | 1 |
  | `_seedLoadedKey = true` | 2 |
  | `_seedUnitsMigrationKey = true` | 3 |
  | `_exerciseRoundDefaultsMigrationKey = true` | 4 |
  | `_sessionFeelingFieldsMigrationKey = true` | 5 |
  | `_calendarDataMigrationKey = true` (or `_calendarSeedPurgeMigrationKey = true` — they were always paired in practice) | 6 |
  | `_calendarSeedPurgeMigrationKey = true` | 7 |
  | `_exerciseContentFieldsMigrationKey = true` | 8 |
  | `_timedExtraWeightMigrationKey = true` | 9 |
  | `_exerciseLibraryRefreshMigrationKey = true` | 10 |
  | `_nutritionTargetsDailyMigrationKey = true` | 11 |
  | `_foodCatalogSeededKey = true` | 12 |
  | `_defaultFoodGroupsSeededKey = true` | 13 |
  | `_foodCategoryGroupIdMigratedKey = true` | 14 (current) |

  The thirteen consolidated steps land at versions 2 through 14. `currentDataVersion = 14`.

### Frontend Changes
- No new screen, widget, or route.
- `lib/main.dart`: the data-migration service runs inside `repository.initialize()`; nothing changes at the call site beyond `initialize()` doing more work.

### Implementation Steps
1. Add `lib/core/constants/data_version.dart` with `currentDataVersion = 14` and the `DataMigrationStep` interface.
2. Add the five new repository interface methods to `WorkoutRepository`.
3. Implement those methods in `HiveWorkoutRepository` and `MockWorkoutRepository`.
4. Write `lib/core/services/data_migration_service.dart` (orchestrator + back-compat shim + transition recorder).
5. Refactor `HiveWorkoutRepository.initialize()` to call the migration service instead of the thirteen individual gates; each step's `run` delegates to the existing private method body.
6. Mirror in `MockWorkoutRepository.initialize()`.
7. Update `scripts/sqlite_schema.sql` with the new meta-box keys block.
8. Update `docs/db_integration.md` to replace the "Hive Migration Keys" section with the new "Data-migration version sequence" section.

## Progress
- [x] Phase 0: Plan complete
- [x] Phase 1: Data layer changes complete
- [x] Phase 2: DataMigrationService + refactored initialize() + TDD tests green
- [x] Phase 3: Code review complete

### Phase 0 Complete ✓
### Phase 1 Complete ✓
### Phase 2 Complete ✓
### Phase 3 Complete ✓

## Feedback
<!-- Leave empty — specialists add notes here -->