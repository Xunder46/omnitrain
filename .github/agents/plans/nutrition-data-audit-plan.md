# Feature: Nutrition Data Layer Audit & Alignment

## Overview

Audit the nutrition feature's data layer against the contract below, report per-point compliance, and align the data structures where they fall short. **No catalog data is loaded, no screens are built, no logging behaviour is added** in this step. This is data-layer audit + alignment only.

The contract:

1. Three independent collections: **CATALOG** (read-only bundled), **LIBRARY** (user-owned, starts empty), **DAY LOG** (foods consumed per day).
2. Every food (catalog or library) carries: name, category, **unit type** (count | grams, never both), **reference amount + label** (e.g. "per 100 g" or "per 1 egg"), and macros (calories, protein, carbs, fat) per that reference.
3. A logged day stores a **frozen snapshot** of the food's name, macros, and unit as they were at log time, the consumed amount, and the daily target values in effect that day. A logged day must NOT read live from the library or current targets. Editing/removing a library food or changing targets must not change past days.
4. A custom food the user creates is added to the **LIBRARY**, not the catalog.
5. Foods carry a **category** for grouping. The user can create, rename, and delete groups and reassign foods. Foods with no group fall under "Ungrouped".
6. **Daily targets** are standing values that carry over day to day until changed.

## Current State (Audit Findings)

The data layer today:

- Has **LIB (library only)** for food — `FoodGroup` + `Food` in `lib/data/models/models.dart:1682, 1725`. `Food` is the single shape for *all* foods; there is no `isCatalog` / origin flag.
- Has `FoodGroup` (name, color, isArchived, timestamps) and `Food.groupId` (nullable). This already covers the "category with Ungrouped fallback" requirement at query time (filter for `groupId == null` → trailing Ungrouped section).
- `Food.servingSize: int` + `Food.servingUnit: String` (free-form text like "g", "egg", "tbsp"). **No `unitType` enum; no separate `referenceAmount`/`referenceLabel`.** Macros are per the `servingSize/servingUnit` pair, which conflates "reference" with "unit text".
- Has **NutritionTarget** with date-keyed backward walkback + forward propagation. Daily targets carry over and past targets are preserved. ✅ Contract #6 already satisfied.
- **No CATALOG collection** (no flag, no separate box, no seed). Concept is absent.
- **No DAY LOG collection** (no model, no repository methods, no Hive box, no SQLite table, no seed for the day-log table).
- `MockWorkoutRepository` and `HiveWorkoutRepository` both implement the same food + food-group interface and do **not** expose catalog or day-log operations. `seed_data.dart` does **not** seed any food catalog entries (no `sampleFoods` / `sampleFoodGroups`).
- `FoodLibraryState` (`lib/state/food_library_state.dart`) is a state wrapper over library + groups, not a screen. It already routes through the repository. Acceptable.

### Compliance matrix

| # | Requirement | Status | Note |
|---|---|---|---|
| 1a | CATALOG collection | ❌ missing | No model field, no box, no schema table, no interface method |
| 1b | LIBRARY collection | ✅ partial | `Food` + `FoodGroup` exist, but no origin flag (everything is "library" by default) |
| 1c | DAY LOG collection | ❌ missing | No model, no methods, no box, no schema |
| 2  | unit type (count\|grams) + reference amount/label + macros per reference | ⚠️ partial | `servingSize` + `servingUnit` exist but no enum, no separate reference, no enforced contract that unit type is exactly one of {count, grams} |
| 3  | Frozen snapshot in day log | ❌ missing | No day-log model at all |
| 4  | Custom foods go to LIBRARY | ✅ partial | Trivially true today (no catalog), but the contract becomes load-bearing once the catalog lands; needs an explicit `origin` / `isCatalog` flag on the model |
| 5  | Category + Ungrouped | ✅ done | `FoodGroup` + nullable `groupId` + `isArchived`; Ungrouped is a query-time filter, not a stored row |
| 6  | Daily targets carry over | ✅ done | `NutritionTarget` + date-keyed walkback + forward propagation; both repos and `NutritionState` already implement it |

## Plan

### Phase 1 — Data Layer (@dba) — align to contract

The shape changes below touch both the Hive and Mock implementations plus the SQLite schema. No food catalog data is loaded, no screens or logging behaviour are built, and no state methods are added beyond the repository surface.

#### 1.1 — `Food` model: add `unitType` + `reference` + `origin`

In [models.dart](lib/data/models/models.dart) (~line 1725):

- Add `enum FoodUnitType { count, grams }`.
- Add `final FoodUnitType unitType;` (required, default `grams`).
- Add `final double referenceAmount;` (required, e.g. `100.0` for "per 100 g", `1.0` for "per 1 egg").
- Add `final String referenceLabel;` (required, e.g. `"g"`, `"egg"`, `"tbsp"`). This is the **display** label of one reference unit; macros are always per `referenceAmount` of `referenceLabel`.
- Add `final bool isCatalog;` (default `false`). Catalog foods (`isCatalog == true`) are bundled read-only rows; library foods (`isCatalog == false`) are user-owned.
- Deprecate/keep-or-rename `servingSize` + `servingUnit` to keep code compiling. Cleanest path: keep the names, redefine semantics:
  - `servingSize` = `referenceAmount` (round on read for backward compat).
  - `servingUnit` = `referenceLabel`.
  - Add a `// DEPRECATED — use referenceAmount/referenceLabel` comment for now. Future iteration may rename.
- Update `Food.fromMap` / `Food.toMap` to read/write:
  - `unit_type` → `FoodUnitType` (parse `"count"` or `"grams"`; default `grams` if missing for legacy rows).
  - `reference_amount` → `double` (fall back to `serving_size` if missing for legacy rows).
  - `reference_label` → `String` (fall back to `serving_unit` if missing for legacy rows).
  - `is_catalog` → `bool` (default `false` if missing).
- Update `Food.copyWith` (if present in `models.dart`; if not, add it) so all new fields propagate.
- Add helper getters `bool get isCatalogFood => isCatalog;` and `bool get isLibraryFood => !isCatalog;` for clarity.

Why deprecated-and-keep rather than rename now: the deprecation keeps the existing browse-view test, browse section, and food-library state tests compiling. The new fields are the contract; old fields become legacy compatibility fields that mirror the new ones. A follow-up iteration can rename and drop them.

#### 1.2 — `ConsumedFood` model: new frozen-snapshot day-log row

New class in [models.dart](lib/data/models/models.dart) (after `Food`):

```dart
class ConsumedFood {
  final String id;            // unique per log row
  final int loggedAtMs;       // when the user logged this
  final int dateMs;           // day key (local midnight ms) this row counts toward
  final String? sourceFoodId; // Food.id at log time; null if origin was a custom row since deleted
  final String name;          // FROZEN
  final FoodUnitType unitType;        // FROZEN
  final double referenceAmount;       // FROZEN
  final String referenceLabel;        // FROZEN
  final int protein;          // FROZEN — grams per reference
  final int carbs;            // FROZEN
  final int? fiber;           // FROZEN (nullable)
  final int fat;              // FROZEN
  final int? sodium;          // FROZEN (nullable)
  final double amountConsumed;        // consumed amount in the food's reference unit
  final String? groupIdSnapshot;       // FROZEN group id at log time
  final String? groupNameSnapshot;    // FROZEN group name at log time (so logs read correctly even if the group is renamed/deleted later)
  // Daily targets in effect that day — FROZEN, so changing targets later does not rewrite history.
  final double targetCalories;
  final double targetProtein;
  final double targetCarbs;
  final double targetFat;
  final int createdAtMs;
  final int updatedAtMs;
}
```

Includes `fromMap` / `toMap` and `copyWith`. Macros are stored as ints per the existing `Food` convention. The day-log row **never reads** from the live library or live targets; everything is copied at log time.

#### 1.3 — `WorkoutRepository` interface additions

In [workout_repository.dart](lib/data/repositories/workout_repository.dart) (after the existing food-library section):

- `Future<List<Food>> getCatalogFoods({bool includeArchived = false});`
- `Future<Food?> getCatalogFoodById(String id);`
- `Future<List<Food>> getLibraryFoods({bool includeArchived = false});` (re-aliased; or keep `getFoods` as the library reader and add a separate `getCatalogFoods` for symmetry)
- `Future<Food> addCatalogFoodToLibrary(String catalogFoodId);` — copy a catalog food into the library as a new row with `isCatalog = false` (used when the user picks a catalog food to log or to add)
- `Future<List<ConsumedFood>> getConsumedFoodsForDate(int dateMs);`
- `Future<String> createConsumedFood(ConsumedFood entry);`
- `Future<void> deleteConsumedFood(String id);`
- `Future<List<ConsumedFood>> getConsumedFoodsInRange(int fromMs, int toMs);`

The existing `getFoods` stays as the library reader (returns only `isCatalog == false`). `getCatalogFoods` is the new reader for `isCatalog == true`. The two are independent.

#### 1.4 — `HiveWorkoutRepository` (web + native persistent)

In [hive_workout_repository.dart](lib/data/repositories/hive_workout_repository.dart):

- Open a new box `'foods_catalog'` for catalog rows (separate Hive box from `'foods'`).
- Add `'consumed_foods'` box.
- Add `is_catalog` filter to the existing `getFoods` so it returns library rows only.
- Implement `getCatalogFoods` / `getCatalogFoodById` against the new box.
- Implement `addCatalogFoodToLibrary`: read the catalog row from `'foods_catalog'`, build a clone with a new `id` and `isCatalog = false`, `put` it into `'foods'`.
- Implement day-log CRUD against `'consumed_foods'` (key = id, value = `ConsumedFood.toMap()`).
- The day-log methods do **not** touch the `'foods'` or `'foods_catalog'` boxes, and do **not** read the nutrition-targets box. They read/write only `'consumed_foods'`.

#### 1.5 — `MockWorkoutRepository` (in-memory)

In [mock_workout_repository.dart](lib/data/repositories/mock_workout_repository.dart):

- Add `final Map<String, Food> _catalogFoods = {};` (separate from `_foods`).
- Add `final Map<String, ConsumedFood> _consumedFoods = {};`.
- Filter `getFoods` to return only `_foods` rows where `!isCatalog`.
- Implement the new interface methods against the in-memory maps.
- `addCatalogFoodToLibrary`: deep-clone the catalog row with a new id and `isCatalog = false` into `_foods`.
- Day-log methods only read/write `_consumedFoods`; never touch `_foods` / `_catalogFoods` / `_nutritionTargetsByDate`.
- Extend `clear()` / `reset()` to wipe the new maps.

#### 1.6 — SQLite schema (future native)

In [scripts/sqlite_schema.sql](scripts/sqlite_schema.sql):

- Add a new section after `app_food`:
  ```sql
  -- CATALOG: read-only bundled food set (shipped with the app, never user-edited).
  CREATE TABLE app_food_catalog (
    id TEXT NOT NULL PRIMARY KEY,
    name TEXT NOT NULL,
    group_id TEXT,                       -- optional, points to a separate app_food_catalog_group or a sentinel "Ungrouped"
    unit_type TEXT NOT NULL CHECK (unit_type IN ('count','grams')),
    reference_amount REAL NOT NULL,
    reference_label TEXT NOT NULL,
    protein INTEGER NOT NULL,
    carbs INTEGER NOT NULL,
    fiber INTEGER,
    fat INTEGER NOT NULL,
    sodium INTEGER,
    is_archived INTEGER NOT NULL DEFAULT 0,
    notes TEXT,
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL
  );
  ```
- Add `is_catalog` column to `app_food` (`INTEGER NOT NULL DEFAULT 0`) with a CHECK / default and an index. Catalog rows in `app_food` would be unusual; the separate `app_food_catalog` table is the cleanest separation.
- New `app_consumed_food` table:
  ```sql
  CREATE TABLE app_consumed_food (
    id TEXT NOT NULL PRIMARY KEY,
    logged_at_ms INTEGER NOT NULL,
    date_ms INTEGER NOT NULL,                 -- day key
    source_food_id TEXT,                       -- nullable: id of the Food or Catalog Food the user logged
    name TEXT NOT NULL,                        -- FROZEN
    unit_type TEXT NOT NULL CHECK (unit_type IN ('count','grams')),
    reference_amount REAL NOT NULL,            -- FROZEN
    reference_label TEXT NOT NULL,             -- FROZEN
    protein INTEGER NOT NULL,                  -- FROZEN
    carbs INTEGER NOT NULL,                    -- FROZEN
    fiber INTEGER,                              -- FROZEN
    fat INTEGER NOT NULL,                      -- FROZEN
    sodium INTEGER,                             -- FROZEN
    amount_consumed REAL NOT NULL,
    group_id_snapshot TEXT,                    -- FROZEN
    group_name_snapshot TEXT,                  -- FROZEN
    target_calories REAL NOT NULL,             -- FROZEN
    target_protein REAL NOT NULL,              -- FROZEN
    target_carbs REAL NOT NULL,                -- FROZEN
    target_fat REAL NOT NULL,                  -- FROZEN
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL
  );
  CREATE INDEX IX_consumed_food_date ON app_consumed_food(date_ms DESC);
  ```
- Document the read-only nature of `app_food_catalog` and the frozen-snapshot contract of `app_consumed_food` in the header comment.

#### 1.7 — `FoodLibraryState` (no new behaviour)

[food_library_state.dart](lib/state/food_library_state.dart) stays as the library + groups state. No new methods are added in this iteration. The new day-log surface lives behind `WorkoutRepository` only for this audit. The new catalog surface likewise. (A future iteration will add a `CatalogState` if and when the catalog is exposed in UI.)

#### 1.8 — Out of scope for this iteration

- Loading any seed catalog rows (`sampleCatalogFoods` etc.) — that comes in the next iteration when the catalog UI is built. The schema and interface are now ready for it.
- Logging UI (`ConsumedFood` creation flow, "Log Food" sheet, etc.).
- `NutritionState` changes (no day-log reads there).
- `getCachedTargetForDate` (already exists on `NutritionState`; the snapshot stores targets at log time so the day log is decoupled from live targets).

### Phase 2 — Unit Tests (@developer)

All in `test/` (or a new `test/nutrition_data_audit_test.dart` to keep it isolated from the existing browse/target tests).

- **New**: A logged day's stored values do not change when the source library food is later edited or deleted.
  - Create a library `Food`. Create a `ConsumedFood` snapshot at `dateMs = T`. Update the library food (change name, macros, group). Delete the library food. Re-read `getConsumedFoodsForDate(T)` and assert every snapshot field is unchanged.
  - Run against `MockWorkoutRepository` (the audit-friendly in-memory implementation).
- **New**: A logged day's target values do not change when current targets are later edited.
  - Set a `NutritionTarget` for `dateMs = T` (e.g. calories = 2000, protein = 100). Create a `ConsumedFood` snapshot that includes those targets. Update today's target to something different (2500, 150). Re-read the snapshot and assert the original target values are intact.
- **New**: A food round-trips with its unit type and reference preserved.
  - Build a `Food` with `unitType: FoodUnitType.count`, `referenceAmount: 1.0`, `referenceLabel: 'egg'`, plus macros. `toMap` → `fromMap` round-trip; assert the new fields survive.
  - Build a `Food` with `unitType: FoodUnitType.grams`, `referenceAmount: 100.0`, `referenceLabel: 'g'`. Round-trip; assert.
  - `FoodUnitType` serialises as `"count"` and `"grams"` in `toMap`.
- **New**: Catalog is not mutated by adding/editing/removing library or custom foods.
  - Seed a catalog row. Call `addCatalogFoodToLibrary(id)` to clone it. Edit the library copy. Remove the library copy. Re-read `getCatalogFoods()` and assert the original catalog row is byte-for-byte unchanged.

Plus a small set of supporting unit tests:
- `Food.fromMap` legacy-row fallback: a map missing `unit_type` / `reference_amount` / `reference_label` / `is_catalog` deserialises without throwing, defaulting sensibly (`unitType: grams`, references inferred from legacy `serving_size`/`serving_unit`, `isCatalog: false`).
- `ConsumedFood.fromMap`/`toMap` round-trip.
- `MockWorkoutRepository.getConsumedFoodsForDate` returns only rows with matching `dateMs`.
- `MockWorkoutRepository.addCatalogFoodToLibrary` returns a row with a new id and `isCatalog: false`, and the original catalog row is unchanged.

### Files Affected

- [lib/data/models/models.dart](lib/data/models/models.dart) — add `FoodUnitType` enum, extend `Food` (unitType, referenceAmount, referenceLabel, isCatalog, deprecation note for serving fields), add `ConsumedFood`.
- [lib/data/repositories/workout_repository.dart](lib/data/repositories/workout_repository.dart) — add catalog + day-log interface methods.
- [lib/data/repositories/hive_workout_repository.dart](lib/data/repositories/hive_workout_repository.dart) — open new boxes, implement new methods, filter `getFoods` to library only.
- [lib/data/repositories/mock_workout_repository.dart](lib/data/repositories/mock_workout_repository.dart) — add `_catalogFoods` / `_consumedFoods` maps, filter `getFoods`, implement new methods, update `clear()`/`reset()`.
- [scripts/sqlite_schema.sql](scripts/sqlite_schema.sql) — add `app_food_catalog`, add `app_consumed_food`, add `is_catalog` to `app_food`, document contracts.
- `test/nutrition_data_audit_test.dart` (new) — contract tests.

### Acceptance Criteria

- [ ] `Food` carries `unitType` (`FoodUnitType` enum), `referenceAmount`, `referenceLabel`, `isCatalog`. The enum serialises as `"count"` / `"grams"`.
- [ ] `ConsumedFood` exists with all frozen-snapshot fields and the four target fields.
- [ ] `WorkoutRepository` exposes the catalog and day-log methods; both `MockWorkoutRepository` and `HiveWorkoutRepository` implement them.
- [ ] `MockWorkoutRepository.getFoods()` returns only library rows (`isCatalog == false`); `getCatalogFoods()` returns only catalog rows. The two are independent collections.
- [ ] `addCatalogFoodToLibrary` returns a library clone with a new id and `isCatalog = false`; the original catalog row is untouched.
- [ ] `getConsumedFoodsForDate(dateMs)` returns only rows whose `dateMs` matches; reads/writes never touch the library or catalog maps.
- [ ] `scripts/sqlite_schema.sql` includes `app_food_catalog` and `app_consumed_food` with CHECK constraints on `unit_type` and indexes on `date_ms`.
- [ ] All four required unit tests pass against `MockWorkoutRepository`. (A run against `HiveWorkoutRepository` is out of scope for this audit — Mock is the in-memory web-compatible implementation and the existing test suite uses it.)
- [ ] Existing `test/food_library_state_test.dart`, `test/nutrition_test.dart`, and `test/models_test.dart` continue to compile and pass after the `Food` shape change (legacy-row fallback in `Food.fromMap` covers existing seed data).

## Iteration 1

### DB Changes
1. [ ] Add `FoodUnitType` enum and the four new fields on `Food` (`unitType`, `referenceAmount`, `referenceLabel`, `isCatalog`). `fromMap` falls back to legacy fields so existing rows still load.
2. [ ] Add `ConsumedFood` model with frozen-snapshot fields and four target fields.
3. [ ] Extend `WorkoutRepository` interface with catalog + day-log methods.
4. [ ] Implement in `MockWorkoutRepository` (in-memory, web-compatible). Filter `getFoods` to library-only.
5. [ ] Implement in `HiveWorkoutRepository` (new `'foods_catalog'` and `'consumed_foods'` boxes).
6. [ ] Add `app_food_catalog`, `app_consumed_food` tables, plus `is_catalog` column on `app_food` in `scripts/sqlite_schema.sql`. Document the contracts in the header comment.

### Backend Changes
None beyond the repository surface. `FoodLibraryState` and `NutritionState` are not modified. No screens are built, no catalog data is loaded, no logging behaviour is added.

### Frontend Changes
None.

### Implementation Steps
1. DBA: extend `Food` model + add `FoodUnitType` enum + add `ConsumedFood`.
2. DBA: add interface methods to `WorkoutRepository`.
3. DBA: implement in `MockWorkoutRepository` (in-memory, audit-friendly) and `HiveWorkoutRepository` (new boxes).
4. DBA: add SQLite tables and contract comments.
5. Developer: add the four required unit tests in a new `test/nutrition_data_audit_test.dart` plus the supporting unit tests listed above.
6. Run the targeted test file, then the full `test/` suite to confirm no regressions.

## Progress
- [x] Iteration 1 DBA steps 1-6
- [x] Iteration 1 Developer step 5 (unit tests) — 15 tests pass
- [x] Full `test/` suite green (88 tests pass across models_test.dart, food_library_state_test.dart, nutrition_test.dart, nutrition_data_audit_test.dart)
- [x] Phase 1 Complete — data layer aligned to contract

## Feedback
[Leave empty until a specialist or reviewer adds notes]
