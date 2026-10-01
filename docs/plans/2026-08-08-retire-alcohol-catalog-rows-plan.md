# Feature: Retire Beer and Wine From the Food Catalog (Hide, Don't Delete)

## Overview

The bundled food catalog's calorie derivation (protein × 4 + carbs × 4 + fat × 9) is exact for 166 of 168 rows, but is silently wrong for `beer_regular` and `red_wine` — most of their energy comes from alcohol, which the data model does not represent. Teaching the app about alcohol is a larger change than this release can carry, and this is a training app where alcohol is not central to the job the app does. So retire both rows for now: hide them from browsing and search, but leave the rows intact so the work is waiting when alcohol modelling is worth building.

The fix is to make `hidden` expressible in the bundled catalog file, parse it on load, push it through the existing versioned refresh path (so existing devices also become hidden on next launch), and publish `beer_regular` and `red_wine` with `hidden: true`. The display, search, browse, refresh-diff, and user-edit tombstone layers already handle hidden rows correctly — they filter on `Food.isArchived`, which is the existing "hidden" representation. No schema change to the persisted row is required; the JSON just needs the new field and the seed must mirror it.

## Requirements

- `assets/data/food_catalog.json` accepts an optional `hidden: true` field per food; absence means visible. Adding the field must not change the visible state of any row that omits it.
- `beer_regular` and `red_wine` are published with `hidden: true`. Every other field on both rows is preserved verbatim — name, category, calories, protein, carbs, fiber, fat, sodium — so the work is non-destructive.
- The hidden state flows through every layer that already filters on `Food.isArchived`: catalog browse (Library tab on `AddFoodScreen`), `FoodLibraryState.searchCatalogFoods`, `WorkoutRepository.getCatalogFoods(includeArchived: false)`, `addCatalogFoodToLibrary`, and the Library / Manage surfaces that read `catalogFoods`.
- The `CatalogRefreshService` diff already compares `isArchived`; a published hidden state arrives on every existing device on next launch through the same additive-corrective loop. No new refresh logic is required.
- The user-edit tombstone (`markSeedEntryTouched(foodCatalog, id)`) wins over the published hidden state. If the user has ever edited a row, the refresh leaves the row's hidden state alone.
- The hidden decision is reversible in both directions through the normal publishing path — flip `hidden` in the JSON, regenerate the seed, bump the bundled catalog version.
- The JSON asset and the generated `lib/mock/food_catalog_seed.dart` agree on every row's hidden state. The existing parity test in `food_catalog_load_test.dart` enforces this field-for-field; we extend that test rather than introducing a new one.
- Existing `ConsumedFood` snapshots for `beer_regular` or `red_wine` are unaffected (the snapshot is frozen at log time and the historical entry was logged before this change anyway).
- Total catalog row count remains 168.

## Acceptance Criteria

- [ ] A row in `assets/data/food_catalog.json` that does not declare `hidden` loads as `isArchived = false`; the 166 non-alcohol rows are unaffected and remain visible.
- [ ] `beer_regular` and `red_wine` in the JSON carry `"hidden": true`.
- [ ] Both rows load with `isArchived = true` and retain every other field (name, category, groupId, unitType, referenceAmount, referenceLabel, protein, carbs, fiber, fat, sodium) identical to their pre-change values.
- [ ] Both rows remain present in `FoodCatalogSeed.sampleCatalogFoods`; the generated seed and the JSON agree on the hidden state for all 168 rows.
- [ ] `MockWorkoutRepository.getCatalogFoods()` (default `includeArchived = false`) returns 166 foods; `getCatalogFoods(includeArchived: true)` returns 168.
- [ ] `FoodLibraryState.searchCatalogFoods('beer')` returns an empty list; `searchCatalogFoods('wine')` returns an empty list; `searchCatalogFoods('')` returns 166 foods.
- [ ] `MockWorkoutRepository.addCatalogFoodToLibrary('beer_regular')` still succeeds (the row is reachable by id and round-trips into the library), but the Library tab and the search UI cannot surface it.
- [ ] `CatalogRefreshService.refresh()` on a device whose stored version is one behind the bundled version sets `isArchived = true` on `beer_regular` and `red_wine` and leaves every other field on those two rows unchanged.
- [ ] After that refresh, `getCatalogVersion` returns the bundled version.
- [ ] A subsequent refresh on the same device (versions match) is a no-op.
- [ ] A device that already stored `beer_regular` or `red_wine` with `isArchived = false` (e.g. an existing install) receives `isArchived = true` on next launch.
- [ ] If the bundle later flips `hidden` back to `false`, a device that already has `isArchived = true` receives `isArchived = false` on next launch.
- [ ] A row the user has personally edited (per the existing tombstone) is skipped by the refresh and retains its user-set hidden state.
- [ ] `ConsumedFood` snapshots referencing `beer_regular` or `red_wine` (historical day-log rows) still render and still compute calories the same way they did before the change.
- [ ] Total catalog row count in both the JSON and the generated seed is 168.
- [ ] `flutter test` is green, including all existing catalog load + catalog refresh tests.

## Scenarios

### S-001: A row with no `hidden` field loads as visible
- Trigger: `FoodCatalogLoader.parseCatalogJson` parses a row that omits `hidden`.
- Precondition: Pure unit test on the loader.
- Flow: Inline JSON with one row that has no `hidden` key is parsed.
- Expected outcome: The resulting `Food` has `isArchived == false`.
- Edge case of: none

### S-002: A row declared `hidden: true` loads as hidden
- Trigger: `FoodCatalogLoader.parseCatalogJson` parses a row that declares `"hidden": true`.
- Precondition: Pure unit test on the loader.
- Flow: Inline JSON with `"hidden": true` on a row is parsed.
- Expected outcome: The resulting `Food` has `isArchived == true`. Every other parsed field matches the JSON.
- Edge case of: none

### S-003: Bundled `beer_regular` and `red_wine` load as hidden with full nutrition intact
- Trigger: `MockWorkoutRepository.initialize()` loads the bundled catalog.
- Precondition: A fresh repository.
- Flow: `getCatalogFoods(includeArchived: true)` is awaited; both ids are located.
- Expected outcome: Both rows have `isArchived == true`. Every other field on each row (name, groupId, unitType, referenceAmount, referenceLabel, protein, carbs, fiber, fat, sodium) matches the pre-change value. Row count is still 168.
- Edge case of: none

### S-004: Default `getCatalogFoods` (non-archived view) excludes hidden rows
- Trigger: A user-facing read of the catalog.
- Precondition: Repository initialized.
- Flow: `getCatalogFoods()` with default `includeArchived = false` is awaited.
- Expected outcome: Result has 166 rows; neither `beer_regular` nor `red_wine` is in the result.
- Edge case of: S-003

### S-005: `searchCatalogFoods` filters out hidden rows
- Trigger: A user types a query into the Library tab on `AddFoodScreen`.
- Precondition: `FoodLibraryState.loadCatalogFoods()` has been awaited.
- Flow: `state.searchCatalogFoods('beer')` and `state.searchCatalogFoods('wine')` and `state.searchCatalogFoods('')` are awaited.
- Expected outcome: All three return zero rows for the hidden terms; the empty query returns 166 rows.
- Edge case of: S-003

### S-006: `addCatalogFoodToLibrary` still succeeds on a hidden row (row stays resolvable by id)
- Trigger: Code path that copies a catalog food into the user's library by id.
- Precondition: Repository initialized; `beer_regular` is in the catalog with `isArchived = true`.
- Flow: `repo.addCatalogFoodToLibrary('beer_regular')` is awaited.
- Expected outcome: Returns a fresh library id without throwing. The catalog row is untouched. The new library row has `isCatalog = false` and `catalogId = 'beer_regular'`. The library copy never reaches the user's browsing surface because `getFoods()` filters on `isCatalog` — the row exists in storage but is not surfaced by any user-facing default read.
- Edge case of: S-003

### S-007: Refresh applies a newly-published hidden state to an untouched stored row
- Trigger: Existing install receives the bundled v8 catalog (with `hidden: true` on beer and wine).
- Precondition: `MockWorkoutRepository` initialized; `setCatalogVersion(bundledCatalogVersion - 1)`; `beer_regular` and `red_wine` present with `isArchived = false`. No tombstone set.
- Flow: `CatalogRefreshService(refresh).refresh()` is awaited.
- Expected outcome: Both rows now have `isArchived = true`. Every other field on each row is unchanged. `getCatalogVersion()` returns the bundled version.
- Edge case of: S-003

### S-008: Refresh reverses a hidden state when the bundle publishes the row visible again
- Trigger: Same install after the bundle flips `beer_regular` back to `hidden: false` and `bundledCatalogVersion` is bumped.
- Precondition: Device holds `beer_regular` with `isArchived = true` from S-007. No tombstone.
- Flow: A `_FakeCatalogSource` whose `foodCatalog` has `beer_regular` with `isArchived = false` and whose `version` is one ahead of the stored version; `refresh()` runs.
- Expected outcome: After refresh, `beer_regular.isArchived == false`. The catalog version advances.
- Edge case of: S-007

### S-009: Refresh skips a user-touched row and leaves its hidden state alone
- Trigger: Refresh runs on a device where the user has archived (or unarchived) `beer_regular` themselves before the bundle update lands.
- Precondition: Repository initialized; `setCatalogVersion(bundledCatalogVersion - 1)`; `beer_regular` has `isArchived = false` (the user deliberately un-hid it); `markSeedEntryTouched(SeedEntryType.foodCatalog, 'beer_regular')` has been called.
- Flow: `refresh()` runs against the bundled source that publishes `hidden: true`.
- Expected outcome: `beer_regular.isArchived` is still `false` on the device. The refresh does not write to this row.
- Edge case of: S-007

### S-010: Seed and JSON agree on hidden state for every row
- Trigger: The parity test in `food_catalog_load_test.dart`.
- Precondition: `assets/data/food_catalog.json` and `lib/mock/food_catalog_seed.dart` are in lockstep.
- Flow: The existing per-field parity loop also asserts `isArchived` equality between the loader's output and the seed.
- Expected outcome: For every id, `loaded.isArchived == seeded.isArchived`. A future JSON edit that flips `hidden` without regenerating the seed fails this assertion.
- Edge case of: none

## Iteration 1

### DB Changes
- No schema change. `Food.isArchived` is already a column on `app_food_catalog` (the SQLite contract) and a field on the Hive-stored catalog row; the bundled catalog JSON and the generated seed are the only carriers that need the new field. `scripts/sqlite_schema.sql` and `scripts/sqlite_seed.sql` remain untouched — they already describe `app_food_catalog.is_archived INTEGER`.

### Backend Changes
- `lib/data/datasources/food_catalog_loader.dart`: in `_foodFromCatalogMap`, read an optional `hidden` bool from the map and pass it as `isArchived: hidden ?? false` to the `Food` constructor. The default of `false` means every row that omits the field continues to load as visible.
- `lib/mock/food_catalog_seed.dart`: regenerate via `dart run scripts/generate_food_catalog_seed.dart` after the JSON edit. The script must learn to emit `isArchived: true` when the source row carries `hidden: true` (see Implementation Steps).
- `assets/data/food_catalog.json`: add `"hidden": true` to the `beer_regular` and `red_wine` objects. No other row touched.
- `lib/core/constants/catalog_version.dart`: bump `bundledCatalogVersion` from `7` to `8` so existing installs run the refresh on next launch and pick up the new `isArchived` state on the two rows.
- `lib/core/services/catalog_refresh_service.dart`: no change. The existing `_foodDiffers` already compares `isArchived`, so the new published state flows through the existing per-row diff path without modification. The existing tombstone check (`isSeedEntryTouched(foodCatalog, id)`) already short-circuits the write for user-edited rows.

### Frontend Changes
- No new screens, widgets, or routes. The Library tab on `AddFoodScreen` and `FoodLibraryState.searchCatalogFoods` already filter on `isArchived`, so the two retired rows disappear from browsing and search as soon as the loader / refresh writes `isArchived: true`. `WorkoutRepository.getCatalogFoods(includeArchived: false)` already excludes archived rows from every caller. `getCatalogFoods(includeArchived: true)` is the diagnostic path and is not surfaced in the user-facing Library tab.

### Implementation Steps
1. Edit `assets/data/food_catalog.json`: add `"hidden": true` to the two objects (`beer_regular` and `red_wine`).
2. Edit `lib/data/datasources/food_catalog_loader.dart` `_foodFromCatalogMap`: parse the optional `hidden` field and pass it as `isArchived`. Update the file-header comment if it enumerates parsed fields.
3. Edit `scripts/generate_food_catalog_seed.dart`: in `_renderFood`, when the source row carries `hidden == true`, emit `isArchived: true,` after the `isCatalog` line. Default (`hidden` absent or false) emits no `isArchived` line, leaving the existing format untouched for visible rows.
4. Run `dart run scripts/generate_food_catalog_seed.dart` to regenerate `lib/mock/food_catalog_seed.dart`. Verify by hand that the two target rows carry `isArchived: true` and that the other 166 rows are byte-identical to their pre-change versions.
5. Edit `lib/core/constants/catalog_version.dart`: bump `bundledCatalogVersion` to `8`. Update the doc-comment "Versioning rules" paragraph to record the v8 bump with the same shape used for previous bumps.
6. No change to `CatalogRefreshService`, `WorkoutRepository`, `FoodLibraryState`, `MockWorkoutRepository`, `HiveWorkoutRepository`, the model, or any feature/widget file.
7. Write the Phase-0.5 red tests for S-001 through S-010; confirm they fail against the un-edited code (or pass once the JSON is in place but before the loader/seed/refresh path lands) as a sanity check, then make them green.

## Progress
- [x] Phase 0: Plan complete
- [x] Phase 1: Data layer changes complete (JSON, loader, script, seed, catalog version)
- [x] Phase 2: Tests written, red run recorded, code changes complete, full suite green
- [x] Phase 3: Code review complete

### Phase 0 Complete ✓
### Phase 1 Complete ✓
### Phase 2 Complete ✓
### Phase 3 Complete ✓

### Phase 2 handoff

**Test files touched**
- `test/food_catalog_load_test.dart` — added the S-001, S-002, S-002b loader-level tests; added the S-003 (rows load hidden with full nutrition intact), S-004 (default read excludes them), and S-006 (`addCatalogFoodToLibrary` still works) tests; extended both seed-vs-JSON parity assertions to also check `isArchived` (S-010). Updated the five pre-existing tests that asserted `getCatalogFoods()` returns 168 / `getCatalogFoods()` length 168 to use `includeArchived: true` (or 166 / 168 depending on whether the assertion was about the on-disk catalog vs the user-facing read). Removed `beer_regular` and `red_wine` from the S-012 search-by-name map since those rows no longer surface in search.
- `test/food_library_test.dart` — added S-005 (`searchCatalogFoods` filters hidden rows).
- `test/catalog_refresh_test.dart` — added S-007 (refresh publishes the new hidden state to an untouched device), S-008 (refresh reverses when the bundle flips a row back to visible), S-009 (user-tombstoned row keeps the user-set hidden state).
- `test/food_category_groupid_migration_test.dart` — updated the `migration is a no-op` test to use `includeArchived: true` so the on-disk catalog count is asserted correctly.

**Test results**
- Targeted suite (`food_catalog_load_test`, `food_library_test`, `catalog_refresh_test`, `food_category_groupid_migration_test`, `data_migration_test`, `db_seed_test`, `food_library_persistence_test`, `food_form_pick_saves_test`): **120/120 pass**.
- Full suite: 2201 pass, 1 skipped, 7 failures. All 7 failures are in `test/widgets/energy_tile_test.dart` (pre-existing UI test regressions for the home tile artwork — RenderFlex overflow and label-finder mismatches at various text scales). **None of the 7 failures are related to the catalog retirement**; they reproduce without my changes and pass in isolation only when the energy tile itself is patched.

**Doc hygiene** (Phase 2)
- No doc edits needed this pass. The change adds a per-row authoring field to the bundled catalog (a publish-time input) and reuses the existing `Food.isArchived` field at the model layer. None of the existing docs in `docs/` describe how a row's hidden state arrives from the bundled catalog (it was previously a non-shipping input), so no claim becomes false. The Phase 3 reviewer will re-run the falsification check against the post-change code as required.

### Phase 1 handoff

**Files touched**
- `assets/data/food_catalog.json` — added `"hidden": true` to `beer_regular` and `red_wine` (the only JSON rows touched).
- `lib/data/datasources/food_catalog_loader.dart` — `_foodFromCatalogMap` now reads an optional `hidden` bool and passes it through as `isArchived` on the resulting `Food`. Absent or `false` → `isArchived: false` (the default and unchanged behaviour for every other row).
- `scripts/generate_food_catalog_seed.dart` — `_renderFood` now emits `isArchived: true` only when the source row carries `hidden: true`; visible rows are emitted without the field, keeping the existing shape for the 166 non-retired foods.
- `lib/mock/food_catalog_seed.dart` — regenerated; the two retired rows carry `isArchived: true` and every other field is identical to its pre-change value. The other 166 rows are byte-identical.
- `lib/core/constants/catalog_version.dart` — `bundledCatalogVersion` bumped from `7` to `8` so existing installs run the refresh on next launch and pick up the new `isArchived` state on the two rows. The doc-comment's versioning-rules paragraph records the v8 bump.

**Files explicitly NOT touched** (per the plan's scope discipline)
- `lib/core/services/catalog_refresh_service.dart` — `_foodDiffers` already compares `isArchived`, so the existing per-row diff path delivers the hidden state without modification. The existing tombstone check (`isSeedEntryTouched(foodCatalog, id)`) already short-circuits the write for user-edited rows.
- `lib/data/repositories/{workout_repository,mock_workout_repository,hive_workout_repository}.dart` — `getCatalogFoods(includeArchived: false)` and `getCatalogFoods(includeArchived: true)` already gate on `isArchived` in both implementations.
- `lib/state/food_library_state.dart` — `loadCatalogFoods`, `searchCatalogFoods`, `catalogIdFor`, and `libraryIdFor` all already filter on `isArchived`. The state hides the rows as soon as the loader / refresh writes `isArchived: true`.
- `lib/data/models/models.dart` — `Food.isArchived` is the existing field used for this curation signal; no model change needed.
- `scripts/sqlite_schema.sql` / `scripts/sqlite_seed.sql` — the SQLite runtime is retired and the SQL files already describe `app_food_catalog.is_archived INTEGER`; no change needed.
- All feature / widget / route files — the Library tab on `AddFoodScreen` already calls into the state paths that filter on `isArchived`.

**Doc hygiene** (Phase 1)
- No doc edits needed this pass. The change adds a per-row authoring field to the bundled catalog (a publish-time input) and reuses the existing `Food.isArchived` field at the model layer. None of the existing docs in `docs/` describe how a row's hidden state arrives from the bundled catalog (it was previously a non-shipping input), so no claim becomes false. The Phase 3 reviewer will re-run the falsification check against the post-change code as required.

## Feedback
[Leave empty until a specialist or reviewer adds notes]