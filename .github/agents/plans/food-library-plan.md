# Food Library Feature Plan

## Overview

The food library is a foundational data/state layer for managing user-created foods and food groups. It serves as the backend for the nutrition feature to log consumed foods and track macronutrient intake. The library is purely backend-focused (UI will come later) and must support both Hive-backed web and SQLite-backed native production environments.

---

## Clarifying Questions & Answers

1. **Food Library UI**: Purely a data/state layer for later consumption by the nutrition feature.
   
2. **Group Management**: Users can add their own groups (no restriction to predefined groups).

3. **Food Uniqueness**: Duplication is allowed (no uniqueness constraint).

4. **Macro Values**: 
   - Store as integers (grams)
   - Required fields: protein, carbs (with fiber tracked separately), fat, sodium — all optional/can be 0
   - Don't store calories separately; calculate on-demand when an item is marked as consumed (calories = protein×4 + carbs×4 + fat×9)

5. **Seed Data Scope**: Leave the seed empty with a placeholder structure. User will manually add data themselves.

6. **Removal Behavior** (updated in iteration 2): Two operations are supported.
   - **Archive** (`archiveFood`): soft-delete — set `isArchived = true` and keep the row. Used when the user wants to hide a food from pickers but may re-enable it later.
   - **Remove** (`removeFood`, added in iteration 2): hard-delete — drop the row from the library. The day-log snapshot from iteration 1 (`ConsumedFood`) already freezes name, macros, group, and targets, and `sourceFoodId` is nullable, so past days remain complete and unchanged. This is the operation the nutrition page uses to clear a food from "my library".

7. **Persistence Strategy**: Both Hive (web) and SQLite (native production).

8. **Relationship to Nutrition Feature**: Yes, the food library is a building block for the nutrition screen and state. They will work together.

---

## Architecture & Data Model

### Models

#### FoodGroup
A grouping category created by the user (e.g., "Proteins", "Vegetables", "Pantry").

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | UUID |
| `name` | `String` | Group name (e.g., "Proteins") |
| `color` | `String?` | Optional hex color for UI display (future use) |
| `isArchived` | `bool` | Soft-delete flag; archived groups are hidden from new food selection but retained for history |
| `createdAtMs` | `int` | Timestamp |
| `updatedAtMs` | `int` | Timestamp |

#### Food
A food item with macronutrient metadata. Calories are not stored; calculated on-demand.

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | UUID |
| `name` | `String` | Food name (e.g., "Chicken Breast") |
| `groupId` | `String?` | FK to FoodGroup; nullable for ungrouped foods |
| `unitType` | `FoodUnitType` | `count` (discrete items) or `grams` (weight) |
| `referenceAmount` | `double` | Quantity the macros are expressed per (e.g. 100.0 for "per 100 g", 1.0 for "per 1 egg") |
| `referenceLabel` | `String` | Display label for the reference (e.g. "g", "egg", "slice") |
| `isCatalog` | `bool` | True for bundled read-only catalog foods; false for user-owned library foods |
| `protein` | `int` | Protein in grams (per reference) |
| `carbs` | `int` | Carbohydrates in grams (per reference) |
| `fiber` | `int?` | Dietary fiber in grams (per reference, optional) |
| `fat` | `int` | Fat in grams (per reference) |
| `sodium` | `int?` | Sodium in milligrams (per reference, optional) |
| `isArchived` | `bool` | Soft-delete flag; archived foods don't appear in pickers but remain in historical logs |
| `notes` | `String?` | Optional user notes (catalog uses this to carry the category label) |
| `createdAtMs` | `int` | Timestamp |
| `updatedAtMs` | `int` | Timestamp |

`Food` also exposes two legacy getters (`servingSize` → `referenceAmount.round()`, `servingUnit` → `referenceLabel`) for backward-compatible row decoding.

**Computed fields** (not stored):
- `calories`: `protein * 4 + carbs * 4 + fat * 9` (calculated on-demand)
- `netCarbs`: `carbs - (fiber ?? 0)` (calculated on-demand, optional helper)

### Repository Interface Extension

The interface is split across four concerns:

```dart
// FoodGroup (user-created groups)
Future<List<FoodGroup>> getFoodGroups({bool includeArchived = false});
Future<FoodGroup?> getFoodGroupById(String id);
Future<String> createFoodGroup(FoodGroup group);
Future<void> updateFoodGroup(FoodGroup group);
Future<void> archiveFoodGroup(String id); // Soft-delete

// Food (user-owned library)
Future<List<Food>> getFoods({bool includeArchived = false});
Future<List<Food>> getFoodsByGroup(String groupId, {bool includeArchived = false});
Future<Food?> getFoodById(String id);
Future<List<Food>> searchFoods(String query, {bool includeArchived = false});
Future<String> createFood(Food food);
Future<void> updateFood(Food food);
Future<void> archiveFood(String id); // Soft-delete (sets isArchived = true)
Future<void> removeFood(String id); // Added in iteration 2 — hard-delete; day logs are unaffected

// Food Catalog (read-only bundled foods)
Future<List<Food>> getCatalogFoods({bool includeArchived = false});
Future<Food?> getCatalogFoodById(String id);
Future<String> addCatalogFoodToLibrary(String catalogFoodId);

// Day Nutrition Log (frozen snapshots)
Future<List<ConsumedFood>> getConsumedFoodsForDate(int dateMs);
Future<String> createConsumedFood(ConsumedFood entry);
Future<void> deleteConsumedFood(String id);
Future<List<ConsumedFood>> getConsumedFoodsInRange(int fromMs, int toMs);
```

`removeFood` is safe precisely because `ConsumedFood` snapshots are frozen: a library food can disappear without disturbing any past day. `sourceFoodId` becoming a dangling reference is expected and supported.

### Hive Schema

Three food-related Hive boxes (all opened during `HiveWorkoutRepository.initialize()`):
- `foods`: Maps<String, Food> keyed by id — user-owned library
- `foods_catalog`: Maps<String, Food> keyed by id — read-only bundled catalog
- `consumed_foods`: Maps<String, ConsumedFood> keyed by id — day-log snapshots

Plus `food_groups`: Maps<String, FoodGroup> keyed by id.

Seed data: `food_groups`, `foods`, and `consumed_foods` start empty. `foods_catalog` is seeded once on first run (guarded by `_foodCatalogSeededKey` meta) and is never modified thereafter. The catalog contains 107 foods.

### SQLite Schema

Tables: `app_food_group`, `app_food`, `app_food_catalog`, `app_consumed_food`. Established in iteration 1. The `removeFood` operation maps to `DELETE FROM app_food WHERE id = ?` — no schema change.

---

## Implementation Phases

### Phase 1: Data Layer (@dba) — iteration 1 ✅

1. [x] Add `FoodGroup`, `Food`, `ConsumedFood` classes to `lib/data/models/models.dart`
   - `fromMap()` and `toMap()` factory constructors
   - Computed `calories` getter for `Food`
2. [x] Extend `WorkoutRepository` interface in `lib/data/repositories/workout_repository.dart` with FoodGroup CRUD + archive, Food CRUD + archive + search, Food catalog read, Catalog-to-library copy, and Day-log ConsumedFood CRUD.
3. [x] Implement all food/group/catalog/consumed methods in `HiveWorkoutRepository` (boxes: `food_groups`, `foods`, `foods_catalog`, `consumed_foods`).
4. [x] Implement all food/group/catalog/consumed methods in `MockWorkoutRepository` (in-memory `Map`s; catalog seeded from `FoodCatalogSeed`).
5. [x] Update `scripts/sqlite_schema.sql` with `app_food_group`, `app_food`, `app_food_catalog`, `app_consumed_food` (plus indexes).
6. [x] Update `scripts/sqlite_seed.sql` — empty seed for user-owned tables; the catalog uses an in-repo hardcoded list rather than SQL seed (the asset is the source of truth).

### Phase 2: Logic & State (@developer) — iteration 1 ✅

1. [x] Create `FoodLibraryState` in `lib/state/food_library_state.dart` with `loadFoodGroups`, `loadFoods`, `getFoodGroupById`, `getFoodById`, `createFoodGroup`, `updateFoodGroup`, `archiveFoodGroup`, `createFood`, `updateFood`, `archiveFood`, `searchFoods`.
2. [x] Add `calculateCalories(Food)` and `calculateNetCarbs(Food)` to `lib/core/utils/food_helpers.dart`.
3. [x] Wire `FoodLibraryState` into app DI in `lib/main.dart`.
4. [x] Add `logConsumedFood` / `getTodayConsumedFoods` stubs to `NutritionState` for future integration.

### Phase 3: Testing — iteration 1 ✅

1. [x] `test/food_library_state_test.dart` — state caching, CRUD, archive, search, listener notifications.
2. [x] `test/food_catalog_load_test.dart` — catalog loads 107 foods, all required fields, catalog immutability through every user action (update, archive, create, copy-to-library).

---

## Iteration 2 — Library persistence and removal

### Analysis

Iteration 1 shipped a library with the data, state, and snapshot layers fully in place. Iteration 2 establishes the three properties the nutrition page will depend on:

1. A fresh user has an empty library.
2. A food present in the library persists across restart.
3. Removing a food from the library does not change or delete anything in past logged days.

No new model, no new screen, no new state class. The change is:
- one new repository method (`removeFood`) on the interface and both implementations;
- one new state method (`removeFood`) on `FoodLibraryState` that delegates to the repository and updates the cache;
- two new unit tests that prove properties 2 and 3 directly.

Property 1 is already true: neither `MockWorkoutRepository.initialize()` nor `HiveWorkoutRepository.initialize()` writes anything to the `foods` box. The existing `FoodLibraryState` "initial state has empty caches" test plus the new persistence test's "before adding any food" assertion cover it.

### Scenarios

#### S-001: Fresh user has an empty library
- Trigger: First app launch (no user action yet).
- Precondition: Repository has been `initialize()`-ed but no `createFood` call has ever been made.
- Flow: `state.loadFoods()` returns `[]`.
- Expected outcome: `state.foods` is empty. `repo.getFoods()` returns `[]`. No `Food` rows exist in the Hive `foods` box.
- Coverage: existing `FoodLibraryState` test (`initial state has empty caches and not loading`); also asserted up-front in S-002.

#### S-002: A food present in the library persists across restart
- Trigger: User adds a food via `state.createFood(...)`, then the app process is restarted.
- Precondition: A `HiveWorkoutRepository` initialized against a fresh temp directory receives one `createFood` call. The repository is then closed.
- Flow: A new `HiveWorkoutRepository` is constructed against the same temp directory and `initialize()`-d. `state.loadFoods()` is called.
- Expected outcome: The previously created food is present (same `id`, `name`, `protein`/`carbs`/`fat`, `isCatalog == false`, `isArchived == false`).
- Coverage: new test `library persists across restart` in `test/food_library_persistence_test.dart` (new file).

#### S-003: Removing a library food leaves past day-log snapshots intact
- Trigger: User removes a food from the library via `state.removeFood(id)`.
- Precondition: Repository contains one `Food` and one `ConsumedFood` row that references it (via `sourceFoodId`) for a past day, with a frozen `name`, `protein`, `carbs`, `fat`, `groupNameSnapshot`, and target values.
- Flow: `await state.removeFood(id)`. Then `repo.getFoodById(id)` returns null. Then `repo.getConsumedFoodsForDate(pastDateMs)` returns the same `ConsumedFood` row with all frozen fields unchanged.
- Expected outcome: Library no longer contains the food. Past day's `ConsumedFood` row is byte-identical (same `sourceFoodId`, same frozen fields, same `caloriesConsumed`). The new `sourceFoodId` is a dangling reference — this is expected and supported.
- Coverage: new test `removeFood leaves past day-log snapshots intact` in `test/food_library_test.dart` (new file).

### Iteration 2 — DB Changes

None. `removeFood` maps to `_foodsBox.delete(id)` in Hive and `_foods.remove(id)` in the Mock. The `consumed_foods` box is untouched.

### Iteration 2 — Backend Changes

1. [x] Add `Future<void> removeFood(String id);` to `WorkoutRepository` interface in `lib/data/repositories/workout_repository.dart`. Document the snapshot guarantee and that `sourceFoodId` becoming a dangling reference is expected.
2. [x] Implement `removeFood` in `MockWorkoutRepository` in `lib/data/repositories/mock_workout_repository.dart`:
   - Remove from `_foods` if present.
   - No-op if `id` is not in the library (do not touch catalog).
3. [x] Implement `removeFood` in `HiveWorkoutRepository` in `lib/data/repositories/hive_workout_repository.dart`:
   - `await _foodsBox.delete(id);` (no-op on missing key).
   - No-op against `_foodCatalogBox` (catalog is read-only).

### Iteration 2 — Frontend Changes

1. [ ] Add `Future<void> removeFood(String id)` to `FoodLibraryState` in `lib/state/food_library_state.dart`:
   - If the food is in the cache, delegate to `_repository.removeFood(id)`, then drop it from `_foods`, then `notifyListeners()`.
   - If the food is not in the cache, delegate to `_repository.removeFood(id)` (handles the case where the cache is cold but the row exists on disk). No notification needed in that case — no UI state to invalidate.
   - Do **not** throw when the id is absent (the repository is also non-throwing).
2. [ ] No DI changes. No screen changes. No new state class. No new constants.

### Iteration 2 — Implementation Steps (Developer)

1. Add `removeFood` to the repository interface and both implementations.
2. Add `removeFood` to `FoodLibraryState`.
3. Add `test/food_library_persistence_test.dart` (new):
   - Helper: `Future<HiveWorkoutRepository> _newHiveRepo(Directory dir)` that calls `Hive.init(dir.path)`, constructs and `initialize()`-s the repo.
   - Test `library persists across restart`:
     - With a fresh temp dir, create a repo, add a `Food` (id `'food-persist-1'`, name `'Persistence Chicken'`, protein 31, carbs 0, fat 3, `isCatalog: false`).
     - Close the repo.
     - Construct a new `HiveWorkoutRepository` against the same dir, `initialize()`, load via `state.loadFoods()`.
     - Assert the food is present with identical fields.
     - Tear down: `await repo.clear()` and `dir.delete(recursive: true)` in `tearDown`.
4. Add `test/food_library_test.dart` (new) with a `Library removal` group:
   - Test `removeFood leaves past day-log snapshots intact`:
     - Seed one `Food` (id `'food-snap-1'`) and one `ConsumedFood` (dateMs = past midnight, `sourceFoodId = 'food-snap-1'`, name `'Snapshot Chicken'`, protein 30, carbs 0, fat 4, groupNameSnapshot `'Proteins'`, targetCalories 2000, amountConsumed 1.0).
     - Build a `FoodLibraryState`, call `loadFoods()`.
     - Capture a "before" deep copy of the `ConsumedFood` (e.g. JSON encode it).
     - `await state.removeFood('food-snap-1')`.
     - Assert `state.foods` does not contain `'food-snap-1'`.
     - Assert `repo.getFoodById('food-snap-1')` is null.
     - Assert `repo.getConsumedFoodsForDate(pastDateMs)` returns the same `ConsumedFood` (compare JSON encode round-trip to "before").
     - Assert the orphaned `sourceFoodId` is still the original id (no rewrite).
5. Run the new test files plus the existing `food_library_state_test.dart`, `food_catalog_load_test.dart`, and `db_seed_test.dart` to ensure no regressions.

### Iteration 2 — Acceptance Criteria

- [ ] `WorkoutRepository.removeFood(String id)` exists with a doc comment naming the snapshot guarantee.
- [ ] `MockWorkoutRepository.removeFood` removes from `_foods` and is a no-op for unknown ids.
- [ ] `HiveWorkoutRepository.removeFood` calls `_foodsBox.delete(id)` and never touches `_foodCatalogBox`.
- [ ] `FoodLibraryState.removeFood(String id)` updates the cache and notifies listeners; no-throw on unknown id.
- [ ] `test/food_library_persistence_test.dart` contains `library persists across restart` and passes.
- [ ] `test/food_library_test.dart` contains `removeFood leaves past day-log snapshots intact` and passes.
- [ ] All previously passing tests still pass.

### Iteration 2 — Files Affected

- `lib/data/repositories/workout_repository.dart` — add `removeFood` to interface
- `lib/data/repositories/mock_workout_repository.dart` — implement `removeFood`
- `lib/data/repositories/hive_workout_repository.dart` — implement `removeFood`
- `lib/state/food_library_state.dart` — add `removeFood` method
- `test/food_library_persistence_test.dart` — **new** (persistence-across-restart test)
- `test/food_library_test.dart` — **new** (data-layer tests including the new "removal leaves snapshots intact" test)
- `scripts/sqlite_schema.sql` — no change
- `scripts/sqlite_seed.sql` — no change

### Iteration 2 — Notes

- **Why true remove is safe now**: `ConsumedFood` from iteration 1 already freezes `name`, `unitType`, `referenceAmount`, `referenceLabel`, `protein`, `carbs`, `fiber`, `fat`, `sodium`, `groupIdSnapshot`, `groupNameSnapshot`, and target values. `sourceFoodId` is nullable. A food disappearing from the library leaves day logs completely intact. The catalog (read-only bundled foods) is unaffected by `removeFood`.
- **Why not just `archiveFood`**: Archive keeps the row hidden but recoverable in pickers. The nutrition page needs a true removal operation so the library can shrink over time without zombie rows. Both operations coexist: archive for "I might want this back," remove for "I'm done with this."
- **Catalog foods cannot be removed**: `removeFood` only touches the library box. Removing a catalog id is a no-op (consistent with the existing `archiveFood` behavior in the catalog-immutability test in `test/food_catalog_load_test.dart`).
- **No new SQL**: The native SQLite `SqliteWorkoutRepository` (future) maps `removeFood` to `DELETE FROM app_food WHERE id = ?`. No schema change, no migration.
- **No UI**: This iteration is purely data-layer + state + tests. The "trash" affordance on the library card comes in a later iteration.

---

## Critical Decisions

### 1. Archive and Remove Coexist (updated in iteration 2)
- **Rationale (archive)**: Some users want to hide a food from pickers without losing it forever. Archiving preserves recoverability while hiding the row.
- **Rationale (remove)**: Other times a user is simply done with a food and wants their library to shrink. Hard-delete is safe because the `ConsumedFood` snapshot freezes everything a past log needs and `sourceFoodId` is nullable. The day log never needs the live food row.
- **Implementation**: `archiveFood()` sets `isArchived = true` and keeps the row. `removeFood()` (added in iteration 2) drops the row. Both default to non-throwing on missing ids. UI filters archived foods by passing `includeArchived: false` (default) on reads.
- **Catalog is never affected** — `removeFood` and `archiveFood` only touch the user-owned library box.

### 2. Calorie Calculation On-Demand
- **Rationale**: Calories are a derived field that changes if protein/carbs/fat values change. Storing them separately creates consistency issues. Calculating them on-demand keeps the single source of truth in the macros.
- **Implementation**: `Food` model includes computed getter `int get calories => protein * 4 + carbs * 4 + fat * 9`. Helper function in `food_helpers.dart` for state and features to call.

### 3. All Macro Fields Optional in Storage
- **Rationale**: A food might only track one or two macros (e.g., pure protein source). Storing all as nullable allows flexibility. UI can default unmeasured macros to 0 or inform the user.
- **Implementation**: In `Food` model, `protein`, `carbs`, and `fat` are `int` (not nullable) but UI and business logic treat 0 as "unset"; `fiber` and `sodium` are `int?` as true optionals.

### 4. User-Created Groups Only (No Predefined)
- **Rationale**: Simplicity and user control. Predefined groups would require maintenance and localization. Users define what makes sense for their kitchen.
- **Implementation**: `FoodGroup` has no seed data; all groups are created by user.

### 5. Repository Interface Over Direct Storage
- **Rationale**: Maintains environment abstraction (Hive vs SQLite). State classes depend on the interface, not concrete implementations.
- **Implementation**: All food/group operations route through `WorkoutRepository` interface; `FoodLibraryState` never touches Hive boxes or SQLite directly.

---

## Files Affected (cumulative)

### Data Layer (iteration 1)
- `lib/data/models/models.dart` — Add `FoodGroup`, `Food`, `ConsumedFood` classes
- `lib/data/repositories/workout_repository.dart` — Add FoodGroup/Food/Catalog/ConsumedFood methods
- `lib/data/repositories/hive_workout_repository.dart` — Implement all food methods (boxes: `food_groups`, `foods`, `foods_catalog`, `consumed_foods`)
- `lib/data/repositories/mock_workout_repository.dart` — Implement all food methods for parity
- `lib/data/datasources/food_catalog_loader.dart` — JSON catalog parser
- `lib/mock/food_catalog_seed.dart` — 107 hardcoded catalog entries for tests / non-asset environments
- `scripts/sqlite_schema.sql` — `app_food_group`, `app_food`, `app_food_catalog`, `app_consumed_food` tables

### State & Logic (iteration 1)
- `lib/state/food_library_state.dart` — New ChangeNotifier for food library state
- `lib/core/utils/food_helpers.dart` — `calculateCalories`, `calculateNetCarbs`
- `lib/main.dart` — Add `FoodLibraryState` to DI wiring
- `lib/state/nutrition_state.dart` — Stub methods for future consumed-food logging

### Iteration 2 — Data Layer & State
- `lib/data/repositories/workout_repository.dart` — Add `removeFood(String id)` to the interface
- `lib/data/repositories/mock_workout_repository.dart` — Implement `removeFood`
- `lib/data/repositories/hive_workout_repository.dart` — Implement `removeFood`
- `lib/state/food_library_state.dart` — Add `removeFood(String id)` method

### Tests
- `test/food_library_state_test.dart` — Iteration 1 state tests (caching, CRUD, archive, search)
- `test/food_catalog_load_test.dart` — Iteration 1 catalog load + immutability tests
- `test/food_library_persistence_test.dart` — **New** (iteration 2: persistence-across-restart)
- `test/food_library_test.dart` — **New** (iteration 2: data-layer tests including "removal leaves snapshots intact")

---

## Acceptance Criteria (cumulative)

### Iteration 1
- [x] `FoodGroup`, `Food`, `ConsumedFood` classes exist in `models.dart` with `fromMap`/`toMap`.
- [x] `WorkoutRepository` includes all food/group/catalog/consumed methods.
- [x] `HiveWorkoutRepository` and `MockWorkoutRepository` implement all methods with full parity.
- [x] Archive behavior works: archived foods/groups remain in storage, excluded from active lists.
- [x] Calorie calculation is correct: protein×4 + carbs×4 + fat×9.
- [x] Search works: case-insensitive substring match.
- [x] `FoodLibraryState` is injected at app startup alongside `NutritionState`.
- [x] SQLite schema is prepared (`app_food_group`, `app_food`, `app_food_catalog`, `app_consumed_food`).

### Iteration 2
- [x] `WorkoutRepository.removeFood(String id)` exists with a doc comment naming the snapshot guarantee.
- [x] `MockWorkoutRepository.removeFood` removes from `_foods` and is a no-op for unknown ids.
- [x] `HiveWorkoutRepository.removeFood` calls `_foodsBox.delete(id)` and never touches `_foodCatalogBox`.
- [x] `FoodLibraryState.removeFood(String id)` updates the cache and notifies listeners; no-throw on unknown id.
- [ ] `test/food_library_persistence_test.dart` contains `library persists across restart` and passes.
- [ ] `test/food_library_test.dart` contains `removeFood leaves past day-log snapshots intact` and passes.
- [ ] All previously passing tests still pass.

---

## Progress Checklist

- [x] Iteration 1 Phase 1 Data Layer (@dba) — **Complete**. Models, repository interface, Hive, Mock, SQLite schema all implemented.
- [x] Iteration 1 Phase 2 State & Logic (@developer) — **Complete**. `FoodLibraryState`, food helpers, DI wiring, `NutritionState` stubs implemented.
- [x] Iteration 1 Phase 3 Testing — **Complete**. State tests, catalog load + immutability tests, db seed test.
- [x] Iteration 2 — **Complete**. Added `removeFood` to interface + both repos + state; created persistence and removal tests.

---

## Notes for Next Iteration

- **No UI**: This feature is purely backend. The nutrition feature will later consume `FoodLibraryState` and build screens for group/food management, including a "trash" affordance that calls `removeFood`.
- **Calories are computed**: Never store calories in the `Food` model; always derive from macros.
- **Archive and remove coexist**: `archiveFood` for "hide but keep" and `removeFood` for "drop". The catalog is never affected by either.
- **SQLite parity**: Maintain `scripts/sqlite_schema.sql` and prepare migrations (to come in future iteration). `removeFood` does not require a schema change.
- **DI pattern**: Both `FoodLibraryState` and `NutritionState` are injected at app startup, not lazily or inline. This ensures consistent repository references.

---

## Feedback
**Iteration 2 — post-review polish (by @developer):**
- W1: `state_management.md` `FoodLibraryState` methods table now lists `removeFood(String id)` and includes a new "Removal Semantics" section explaining the archive vs remove distinction and the day-log snapshot guarantee.
- W2: Persistence test `tearDown` now uses `Hive.deleteFromDisk()` to guarantee a clean Hive registry between tests.
- W3: The vacuous catalog-removal test was rewritten to actually exercise the guard — it seeds a `Food` with `isCatalog = true` via `repo.seedCatalogFood`, calls `state.removeFood(catalogId)`, and asserts the catalog row is untouched.
- S1: `FoodLibraryState.removeFood` now uses the `Map.remove` return value (`_foods.remove(id) != null`) instead of a `containsKey` + conditional `remove` pair.
- All fixes verified clean by `dart analyze`. (Test execution still blocked by the pre-existing Flutter SDK environment issue documented in earlier turns.)

---

## Next Recommended Handoff

**@code-reviewer** — Re-review please.

### Files Changed in This Polish Pass
- `.github/agents/docs/state_management.md` — `removeFood` row + new "Removal Semantics" section
- `lib/state/food_library_state.dart` — S1 style refactor (Map.remove return value)
- `test/food_library_persistence_test.dart` — W2 `Hive.deleteFromDisk()` in tearDown
- `test/food_library_test.dart` — W3 rewrote catalog-removal test to actually exercise the guard
