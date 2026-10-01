# Feature: Load Food Catalog Data

## Overview

Load the user-provided catalog data file (~107 common foods) as a fixed, read-only collection bundled with the app. The catalog is the reference users pull from — it is never shown as the user's foods and never edited by the user. The catalog must load successfully and be available to browse/search, but no UI for browsing or searching is built in this step.

## Requirements

- Load the catalog from a bundled JSON asset (107 foods).
- Each food: name, category, unit type ("count" | "grams"), reference amount + label, per-reference macros (calories, protein, carbs, fat; optional sodium).
- The catalog is read-only — the user cannot edit or delete catalog foods.
- The catalog is NOT the user's personal library and must not be displayed as the user's foods.
- No browse/search UI built in this step.

## Acceptance Criteria

- [ ] The catalog loads from the provided data file with all foods and their category, unit type, reference, and macros intact.
- [ ] The catalog is available to the app but is not shown as the user's library.
- [ ] No code path lets the user edit or delete a catalog food.

## Scenarios

### S-001: Catalog loads on app start
- Trigger: App initialization (main.dart -> repository.initialize()).
- Precondition: Fresh install or existing install.
- Flow:
  1. HiveWorkoutRepository.initialize() runs.
  2. Catalog asset is parsed.
  3. All 107 catalog foods are stored in the `foods_catalog` Hive box with `isCatalog = true`.
  4. MockWorkoutRepository.initialize() runs.
  5. All 107 catalog foods are loaded into `_catalogFoods` map.
- Expected outcome: After initialize(), `getCatalogFoods()` returns 107 foods.

### S-002: Catalog is read-only — no edit path exists
- Trigger: Attempt to modify catalog data via the repository interface.
- Precondition: Catalog has been loaded.
- Flow:
  1. App code attempts to call `updateFood()` on a catalog food (id starts with "cat-").
  2. HiveWorkoutRepository: throws because no `updateFood` call path can target the catalog box — updateFood writes to `_foodsBox`, not `_foodCatalogBox`.
  3. MockWorkoutRepository: same — updateFood writes to `_foods` map, not `_catalogFoods`.
  4. App code attempts to call `archiveFood()` on a catalog food.
  5. Same: archiveFood writes to `_foods` / `_foodsBox`, not catalog storage.
  6. No `updateCatalogFood`, `deleteCatalogFood`, or `archiveCatalogFood` methods exist on the interface.
- Expected outcome: Catalog data is immutable from any user-action code path.

### S-003: Catalog is independent from user's library
- Trigger: User adds a custom food to their library.
- Precondition: Catalog loaded, library empty.
- Flow:
  1. App code calls `createFood(customFood)` with `isCatalog = false`.
  2. Food is stored in `_foods` / `_foodsBox` (library store).
  3. Catalog store is unchanged.
  4. `getFoods()` returns only the library food.
  5. `getCatalogFoods()` returns all 107 catalog foods.
- Expected outcome: Library and catalog remain separate. Library shows 1 food; catalog still shows 107.

## Data Asset

The catalog data is provided as JSON in the task. It contains 107 foods across 8 categories: Proteins, Dairy, Grains & Starches, Fruits, Vegetables, Nuts/Seeds/Fats, Snacks & Prepared, Drinks, Condiments.

The data is bundled at `assets/data/food_catalog.json` (new) and listed in `pubspec.yaml` assets.

## Plan

### Phase 1: Data Layer (@dba)

1. **Add catalog asset file**: `assets/data/food_catalog.json` containing the 107 foods.
2. **Add asset to pubspec.yaml**: register the JSON file under `assets:`.
3. **Add seed data parser**: `lib/data/datasources/food_catalog_loader.dart` that:
   - Loads the JSON asset via `rootBundle.loadString('assets/data/food_catalog.json')`.
   - Parses each food entry into a `Food` model with `isCatalog = true`.
   - Returns a `List<Food>`.
4. **Update `SeedData`**: add `static Future<List<Food>> loadCatalogFoods()` that wraps the asset loader. For `MockWorkoutRepository` (which can't easily await rootBundle in unit tests), provide a synchronous fallback that reads from a hardcoded `List<Food>` generated at startup.
5. **Update `HiveWorkoutRepository.initialize()`**: after opening the food catalog box, call `await _seedCatalogFoods()` which loads from asset and populates `_foodCatalogBox` (only on first install — guarded by a meta key like `catalog_seeded_v1`).
6. **Update `MockWorkoutRepository.initialize()`**: synchronously populate `_catalogFoods` from the hardcoded `SeedData.sampleCatalogFoods` list.
7. **No new repository methods**: the existing `getCatalogFoods()` is the only reader; no mutator methods are added.

### Phase 2: Unit Tests (@developer)

1. **Test**: catalog loads with expected number of foods and required fields.
   - File: `test/food_catalog_load_test.dart` (new)
   - Use `MockWorkoutRepository` to avoid asset I/O in tests.
   - Assert: `getCatalogFoods()` returns 107 foods.
   - Assert: each food has name, category, unitType, referenceAmount, referenceLabel, protein, carbs, fat.
   - Assert: at least one food from each expected category is present.
   - Assert: all foods have `isCatalog = true`.
2. **Test**: catalog foods are immutable through any user action.
   - For each mutator method that exists on `WorkoutRepository`, attempt to mutate a catalog food:
     - `updateFood(catalogFoodWithModifiedFields)` — should either fail (not find the food in library) or only affect the library store, leaving the catalog unchanged.
     - `archiveFood(catalogFoodId)` — should only archive in the library store (or not find it), leaving the catalog unchanged.
   - Assert: `getCatalogFoods()` returns the same foods with original values after each attempt.

## Files Affected

- `assets/data/food_catalog.json` (new) — the bundled catalog data
- `pubspec.yaml` — register the asset
- `lib/data/datasources/food_catalog_loader.dart` (new) — JSON → List<Food> parser
- `lib/mock/seed_data.dart` — add `sampleCatalogFoods` (hardcoded for tests/mock) and `loadCatalogFoods()` (asset-based for production)
- `lib/data/repositories/hive_workout_repository.dart` — seed catalog from asset on first install
- `lib/data/repositories/mock_workout_repository.dart` — populate `_catalogFoods` from `SeedData.sampleCatalogFoods`
- `test/food_catalog_load_test.dart` (new) — catalog load + immutability tests

## Implementation Strategy

Since `MockWorkoutRepository` is the in-memory implementation used in tests and runs in web (where rootBundle works), and `HiveWorkoutRepository` also uses `rootBundle` for asset loading, the cleanest approach is:

- **Hardcode the catalog in `SeedData.sampleCatalogFoods`** as a `List<Food>` so `MockWorkoutRepository` can load it synchronously without asset I/O.
- **Add `loadCatalogFoods()` in `SeedData`** that reads from `rootBundle` for production (used by `HiveWorkoutRepository`).
- Both code paths produce the same `List<Food>`.

This approach:
- Keeps tests fast and dependency-free (no asset bundle in unit tests).
- Matches the existing pattern where `SeedData.sampleExercises` is the hardcoded list used by `MockWorkoutRepository`, while `HiveWorkoutRepository` has its own seeding logic.

For the hardcoded list, we need to transform the 107 JSON entries into 107 `Food` model instances in Dart code. This is verbose but matches the existing pattern. We'll write a script to generate the Dart code from the JSON, or include the full list directly.

## Progress

- [x] Phase 1 Data Layer (@dba) — asset added, parser created, seed data, repository seeding
- [x] Phase 2 Tests (@developer) — 15 catalog load + immutability tests pass
- [x] Full test suite green (103 tests pass)

## Feedback
[Leave empty until a specialist or reviewer adds notes]
