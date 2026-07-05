# Feature: Content-Version Catalog Refresh

## Overview
App-authored catalog data (exercises, capabilities, muscle-group and equipment relationships, and the food catalog) currently reaches a user's device only on first install or via one-shot migrations that have already run on existing installs. As a result, any catalog change shipped in a later app version never reaches existing users — the bilateral logging note is blank for everyone already on the app even though the source data is correct. This introduces a content-version check that runs at app start; when the app's built-in catalog is newer than the device's, the device's catalog is refreshed in place. The refresh is additive and corrective: it updates and adds app-authored entries, never deletes or overwrites user-created entries, never overwrites a seed entry the user has edited, never leaves the catalog empty or partial even if interrupted, and is fully idempotent. The data source is abstracted so a server-provided catalog can replace the bundled one without changing the check.

## Requirements
- Carry a catalog version on both the bundled catalog (compile-time constant) and the device's stored catalog.
- At app start, compare the two; if the bundled version is newer, run the refresh.
- The refresh writes to existing rows in place (no clear-then-repopulate).
- The refresh adds new app-authored entries when they are missing on the device.
- The refresh updates untouched app-authored entries when their bundled content differs.
- The refresh never touches a user-created entry.
- The refresh never overwrites a seed entry that the user has edited (tombstone marker).
- The refresh never deletes or removes any entry.
- The refresh is interruption-safe: it reads each seed entry and writes it individually; no batch-delete-then-repopulate. On startup with a stored version older than the bundled version, even a failed pass leaves prior data intact.
- The refresh is idempotent: running it twice (or running it when there is nothing to do) yields the same state.
- Bumping the bundled catalog version is sufficient — no other code change — for a catalog change to reach existing users.
- The data source for the bundled catalog is abstracted behind an interface so a future server-provided catalog can be swapped in without changing the version check.

## Acceptance Criteria
- [ ] A device whose stored catalog predates a catalog change receives that change after the app updates and launches (verifiable: bilateral capability appears on Dumbbell Curl on an install that previously showed it blank).
- [ ] After a refresh, the device's stored catalog version matches the bundled catalog version, and a subsequent launch performs no further refresh work.
- [ ] A user-created exercise or food is unchanged by a refresh.
- [ ] A seed-authored entry the user has edited is not overwritten by a refresh.
- [ ] At no point during a refresh is the catalog empty or missing entries; an interrupted refresh leaves prior data intact.
- [ ] Running the refresh twice yields the same result as running it once (no duplicates, no drift).
- [ ] Changing a catalog entry and bumping the catalog version is sufficient, with no other code changes, for the change to reach existing users.
- [ ] The data source backing the bundled catalog is reachable through a single interface; switching to a server-provided implementation does not require touching the refresh orchestrator.
- [ ] The bundled catalog version constant lives in one place that both the constant and the orchestrator reference.

## Scenarios

### S-001: Version gating — no refresh when versions match
- Trigger: App launches on a device whose stored catalog version equals the bundled catalog version.
- Precondition: Repo state seeded with `bilateral` on `exercise-dumbbell-curl`; stored version = bundled version.
- Flow: App startup → orchestrator compares versions → equal.
- Expected outcome: No repository write occurs; orchestrator returns immediately. Stored version is unchanged.
- Edge case of: none

### S-002: Catalog change reaches existing install (bilateral arrives)
- Trigger: App launches on a device whose stored catalog version is older than the bundled catalog version.
- Precondition: Repo state seeded WITHOUT the `bilateral` capability on `exercise-dumbbell-curl` (simulating a previous app version). Stored version = N-1.
- Flow: App startup → orchestrator compares versions → bundled > stored → runs refresh → for each seed entry: `bilateral` is in bundled capability map but missing on device → adds it; other seed entries unchanged.
- Expected outcome: After refresh, `getExerciseCapabilities('exercise-dumbbell-curl')` includes `'bilateral'`. Stored version now equals bundled version. Capability list is a superset of the previous state (only added, nothing removed).
- Edge case of: none

### S-003: User-created entry is preserved
- Trigger: Refresh runs.
- Precondition: Repo state has a user-created exercise with id `exercise-user-12345` (id is not in any seed list) and a stored catalog version older than the bundled version.
- Flow: Orchestrator iterates seed entries; user id is not in seed list → not touched.
- Expected outcome: User-created exercise still exists with original name, capabilities, and timestamps after the refresh.
- Edge case of: S-002

### S-004: User-edited seed entry is not overwritten
- Trigger: Refresh runs.
- Precondition: Seed exercise `exercise-dumbbell-curl` is on device with `name = "DB Curl"` (user renamed from "Dumbbell Curl"). The seed data has `name = "Dumbbell Curl"`. Bundled version is newer than stored.
- Flow: Orchestrator detects the entry id is in the seed list → checks tombstone marker → marker is set → skip update for that entry.
- Expected outcome: Device row keeps `name = "DB Curl"`. Other seed entries that the user did not touch are still updated.
- Edge case of: S-002

### S-005: Idempotency — refresh twice yields identical state
- Trigger: Refresh runs twice in a row without any user mutation in between.
- Precondition: Repo state has a stored version N-1 and bundled version N.
- Flow: First refresh runs → state at version N. Second refresh runs → versions match → early return.
- Expected outcome: State is identical after the second pass: same row count per entity type, same row ids, same content. No duplicates. No drift.
- Edge case of: S-002

### S-006: Interruption safety — partial failure leaves prior data intact
- Trigger: Mid-refresh, a write to one entity throws (simulated).
- Precondition: Stored version N-1, bundled version N, device has prior data.
- Flow: Orchestrator iterates seed entries; on entry 3, the repository throws → orchestrator surfaces the error but does NOT advance the stored version.
- Expected outcome: Prior data on device is fully intact (entries 1–2 may have been written, entry 3+ are unchanged, no rows were deleted). Stored version remains N-1. Next launch retries the refresh from where it left off.
- Edge case of: S-002

### S-007: Real catalog-loading path delivers the change (masking test)
- Trigger: App starts on a device whose stored catalog lacks the bilateral flag on Dumbbell Curl.
- Precondition: Seed state set up without `bilateral` on `exercise-dumbbell-curl`. Stored catalog version = bundled version - 1.
- Flow: App startup calls `CatalogRefreshService.refresh()` → version bump detected → seed entry updated → `WorkoutState.getExercisesRankedForModality(modality: 'resistance_lifting')` is invoked → first bilateral-capable exercise is fetched and added to session → info sheet opens.
- Expected outcome: `'LOGGING NOTE'` text is visible on the info sheet (same assertion as the existing bilateral test, but reached through the real catalog refresh path instead of through a pre-baked Mock that already had the flag).
- Edge case of: S-002

## Iteration 1

### DB Changes
- No new tables or columns. The catalog refresh uses existing tables (`exercises`, `exercise_capabilities`, `exercise_muscle_groups`, `exercise_equipment`, `foods_catalog`, `food_groups`) and the existing `meta` box for new marker keys.
- New SQLite sidecar file (or section in `scripts/sqlite_schema.sql`) documenting the new meta-box keys: `catalog_version`, `catalog_refresh_in_progress_v1`, and `seed_entry_touched_*`.

### Backend Changes
- New constants file `lib/core/constants/catalog_version.dart`:
  - `bundledCatalogVersion` — `int` (start at `2` to ensure a one-time refresh on existing installs that ran at v1).
- New repository interface methods on `WorkoutRepository` (`lib/data/repositories/workout_repository.dart`):
  - `Future<int> getCatalogVersion({int defaultValue = 0})` — reads the stored version from the meta box.
  - `Future<void> setCatalogVersion(int version)` — writes the stored version.
  - `Future<bool> isSeedEntryTouched(String entityType, String id)` — reads a per-entry tombstone marker.
  - `Future<void> markSeedEntryTouched(String entityType, String id)` — sets a per-entry tombstone marker.
- Implement those four methods in `HiveWorkoutRepository` (use the existing `_metaBox`) and in `MockWorkoutRepository` (use in-memory maps).
- New `CatalogSource` interface in `lib/core/services/catalog_source.dart`:
  - `int get version` — version of the bundled catalog this source represents.
  - `List<Exercise> get bundledExercises`
  - `Map<String, List<String>> get bundledExerciseCapabilities`
  - `Map<String, List<String>> get bundledExerciseMuscleGroups`
  - `Map<String, List<String>> get bundledExerciseEquipment`
  - `List<Food> get bundledFoodCatalog`
- `BundledCatalogSource` implementation reads from `SeedData` (exercises + relationship maps) and `FoodCatalogSeed.sampleCatalogFoods` (catalog foods).
- New `CatalogRefreshService` in `lib/core/services/catalog_refresh_service.dart`:
  - Constructor takes a `WorkoutRepository` and a `CatalogSource`.
  - `Future<bool> refresh()` returns `true` if a refresh ran, `false` if no refresh was needed.
  - Logic: read stored version; if `stored >= source.version`, return `false`. Otherwise, for each entity type, for each seed entry: read current → if missing, add; if present and not tombstoned and content differs, update; if present and tombstoned, skip. After all entity types complete, write `source.version` to stored version.
  - The service writes entries one at a time (no clear-then-repopulate, no bulk overwrites). Failure mid-loop surfaces the error without advancing the stored version.
- Hook state mutations that touch seed entries to call `markSeedEntryTouched`:
  - `FoodLibraryState.updateCatalogFood` → `markSeedEntryTouched('food_catalog', id)`.
  - `FoodLibraryState.deleteCatalogFood` → `markSeedEntryTouched('food_catalog', id)` (so the next refresh does not re-create the entry the user removed).
  - `ExerciseLibrary.createCustomExercise` is for new entries — no marker needed (new id is never in the seed list).
  - `ExerciseLibrary.updateCustomExercise` → if the exercise id is in the seed list, `markSeedEntryTouched('exercise', id)`; also for capability / muscle-group / equipment relationship edits on a seed id.
- Wire `CatalogRefreshService` into `lib/main.dart` after `repository.initialize()` and before state construction:
  - `await catalogRefresh.refresh()` is awaited inside the existing try/catch. A failure logs and continues (do not block app startup on a refresh failure).
- `mock/seed_data.dart`: no structural change; the bundled catalog still ships as it does today. The `bilateral` capability flag remains on the bilateral seed exercises (already present).

### Frontend Changes
- No new screen, no new widget, no new route. The orchestrator runs at startup.
- `lib/main.dart` calls `await catalogRefresh.refresh()` once during init.

### Implementation Steps
1. Add `catalog_version.dart` constants file with `bundledCatalogVersion = 2`.
2. Add the four new repository interface methods.
3. Implement those methods in `HiveWorkoutRepository` (via `_metaBox`) and `MockWorkoutRepository` (via in-memory maps).
4. Define `CatalogSource` interface + `BundledCatalogSource` implementation.
5. Write `CatalogRefreshService.refresh()` with the per-entry additive-corrective loop.
6. Add tombstone calls in `FoodLibraryState.updateCatalogFood`, `deleteCatalogFood`, and the relevant `ExerciseLibrary` paths.
7. Wire the service into `lib/main.dart`.
8. Update doc hygiene (see below).

## Progress
- [x] Phase 0: Plan complete
- [x] Phase 1: Data layer changes complete
- [x] Phase 2: CatalogRefreshService + state hooks + main.dart wiring complete
- [x] Phase 2: TDD tests written and green
- [x] Phase 3: Code review complete

### Phase 0 Complete ✓
### Phase 1 Complete ✓
### Phase 2 Complete ✓
### Phase 3 Complete ✓

## Feedback
<!-- Leave empty — specialists add notes here -->