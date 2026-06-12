# DB Integration

## Overview

OmniTrain uses a repository-first persistence architecture:

- Runtime app persistence: `HiveWorkoutRepository` (web and current cross-platform runtime)
- SQL schema assets + migrations: maintained in `scripts/` and `lib/data/datasources/` for SQLite parity work
- Single abstraction contract: `WorkoutRepository`

This document explains how to validate DB assets and how profile-related persistence is represented in both Hive runtime and SQL assets.

---

## Key Files

- `lib/data/repositories/workout_repository.dart`
- `lib/data/repositories/hive_workout_repository.dart`
- `lib/data/repositories/mock_workout_repository.dart`
- `lib/data/datasources/database_provider.dart`
- `lib/data/datasources/migrations.dart`
- `scripts/sqlite_schema.sql`
- `scripts/sqlite_seed.sql`
- `test/db_seed_test.dart`

---

## Setup And Validation

1. Install dependencies.

```bash
flutter pub get
```

2. Validate schema + seed assets in deterministic test mode.

```bash
flutter test test/db_seed_test.dart
```

3. Validate profile repository behavior.

```bash
flutter test test/profile_data_layer_test.dart
```

---

## Repository Contract

`WorkoutRepository` now includes profile and measurement APIs:

- `getProfile()`
- `saveProfile(UserProfile profile)`
- `getMeasurementHistory(String measurementType)`
- `getLatestMeasurement(String measurementType)`
- `saveMeasurementEntry(BodyMeasurementEntry entry)`
- `deleteMeasurementEntry(String entryId)`
- `updateSessionFeeling(String sessionId, int feeling)`

Active session persistence API:

- `getInProgressSessions()`
  - Returns sessions where `endedAtMs == null`
  - Sorted by `startedAtMs` descending (most recent first)
  - Hive implementation skips malformed records with per-row try/catch (no throw)

Any repository implementation must satisfy this full contract and remain compile-safe.

Deterministic active-session ordering contract:

- Top-level sequence is persisted explicitly (not inferred from timestamps).
- `SessionBlock.topLevelOrderIndex` and `SegmentEffort.topLevelOrderIndex` are the canonical keys for mixed block + standalone ordering.
- `SegmentEffort.blockOrderIndex` is the canonical key for effort order inside a block.
- `assignEffortToBlock()` appends to block tail by `blockOrderIndex` without mutating unrelated top-level items.
- `cloneSessionBlock()` appends the cloned block to the end of top-level order and preserves source intra-block effort order exactly.

---

## Hive Runtime Persistence

`HiveWorkoutRepository` now opens profile-specific boxes during `initialize()`:

- `user_profile`
- `body_measurements`

Behavior:

- Profiles are saved by profile id.
- Measurement entries are saved by entry id.
- Measurement history is filtered by `measurementType` and sorted `recordedAtMs` descending.
- Latest measurement is derived from sorted history.

Session persistence behavior:

- `getInProgressSessions()` scans `sessions` box values.
- Parse failures for malformed rows are caught and skipped; valid rows still return.
- Returned list is sorted desc by `startedAtMs`.

Ordering persistence behavior:

- `createSessionBlock()` assigns `topLevelOrderIndex` when missing.
- `createEffort()` assigns canonical order metadata for standalone vs block effort placement.
- `getSessionBlocks()` and `getSegmentEfforts()` return deterministic order based on canonical order columns with stable tie-breakers.

### Hive Migration Keys

- `seed_units_migrated_v1`:
  - Backfills missing seed units (including `unit-cm` and `unit-pct`) for installs where seed bootstrap already ran.
- `exercise_round_defaults_migrated_v1`:
  - Existing migration for exercise round defaults.
- `session_feeling_fields_migrated_v1`:
  - Marker-only migration for newly nullable session feeling fields.
- `nutrition_targets_daily_migrated_v1`:
  - Converts any legacy single-row `app_nutrition_target` from nullable
    REAL columns to non-nullable `0.0` defaults. New `nutrition_targets_by_date`
    Hive box is created lazily on first read/write.
- `default_food_groups_seeded_v1`:
  - One-shot migration that backfills 9 default `FoodGroup` records
    (`food-group-proteins`, `food-group-dairy`,
    `food-group-grains-starches`, `food-group-fruits`,
    `food-group-vegetables`, `food-group-nuts-seeds-fats`,
    `food-group-snacks-prepared`, `food-group-drinks`,
    `food-group-condiments`) on existing installs. Names match the
    catalog categories in `assets/data/food_catalog.json`.
  - Idempotency:
    - Skip a default if its stable id is already present in the box.
    - Skip a default if any existing row has the same name
      (case-insensitive) — the user's row wins.
  - Idempotent on subsequent launches: guarded by the meta key, so the
    migration is a no-op once the marker is set.
- `food_category_groupid_migrated_v1`:
  - One-shot migration that backfills `group_id` on catalog rows whose
    category was previously stored in `notes` (legacy storage
    `"Proteins"` / `"Dairy"` / …) and clears `notes` once resolved.
  - Runs over BOTH `_foodsBox` (library rows that originated from
    the catalog) and `_foodCatalogBox` (the bundled catalog).
  - Lookup is built from the *live* `food_groups` box (not the seed),
    so user renames of default groups are honoured: a renamed group
    that no longer matches the catalog's `notes` simply yields a
    no-match and the catalog row stays as `group_id = NULL`
    (Ungrouped).
  - Library-box heuristic: only rows whose `notes` value matches
    one of the 9 default category names (case-insensitive) are
    backfilled, so user-typed notes are never stomped.
  - Idempotent on subsequent launches: guarded by the meta key, so
    the migration is a no-op once the marker is set. The same
    semantics are documented in `scripts/sqlite_schema.sql` for the
    future SQLite importer.

---

## Nutrition Targets (Daily Rollover)

`WorkoutRepository` exposes date-aware nutrition-target APIs in addition
to the legacy single-row methods:

| Method | Behaviour |
|---|---|
| `getNutritionTargetForDate(int dateMs)` | Returns the target stored for [dateMs]. If no explicit entry exists, walks backward one day at a time (24 h) until it finds the most recent ancestor and returns a copy rolled forward to [dateMs]. Returns `null` when no ancestor exists. |
| `saveNutritionTargetForDate(int dateMs, NutritionTarget target)` | Persists [target] for [dateMs]. Fetches the old target (if any) and forward-propagates the new values to any future dates that still hold the old values. Past dates are never modified. |
| `getNutritionTarget()` | Legacy convenience; delegates to `getNutritionTargetForDate(todayMs)`. |
| `saveNutritionTarget(NutritionTarget target)` | Legacy convenience; delegates to `saveNutritionTargetForDate(todayMs, target)`. |

Implementation requirements (both `HiveWorkoutRepository` and `MockWorkoutRepository`):

- **Backward-walk fallback**: `getNutritionTargetForDate(dateMs)` must check the requested date, then decrement by 24 h until an entry is found or the search space is exhausted. Returning `null` is the correct "no goals ever set" answer.
- **Forward-propagation rule**: When `saveNutritionTargetForDate(dateMs, new)` is called, the implementation must compare the **old** target at [dateMs] (if any) to all future dates. Any future date whose stored target is *identical* to the old target is replaced with [new]. Future dates that already differed from the old target are left untouched (they were explicit user edits).
- **Past dates are immutable**: The implementation must never walk forward and modify dates earlier than [dateMs].
- **Backward compat**: Legacy `getNutritionTarget()` / `saveNutritionTarget()` continue to work and target today's date. This is how the rest of the app stays unchanged during the migration.

Storage shape:
- Hive: a dedicated box `nutrition_targets_by_date` keys each entry by `dateMs.toString()` with a `Map<String, dynamic>` value matching `NutritionTarget.toMap()`.
- Mock: an in-memory `Map<int, NutritionTarget>` keyed by `dateMs`.
- SQLite: the `app_nutrition_target` table is keyed by `date_ms` (`INTEGER UNIQUE`); see `scripts/sqlite_schema.sql` for the schema narrative.

Tests: see `test/edge_case_test.dart` (`NutritionTarget (date-keyed) edge cases` group) for the boundary conditions — backward-walk, nearest-ancestor preference, forward-propagation across matching and non-matching future dates, and legacy delegation.

## Food Library & Catalog

The nutrition feature supports three independent collections:
- **Catalog**: read-only bundled foods shipped with the app
- **Library**: user-owned foods (editable)
- **Day Log**: consumed foods per day (frozen snapshots)

### Default food group categories

The library is seeded with 9 default `FoodGroup` records whose names
match the 9 `category` values in `assets/data/food_catalog.json`
(Proteins, Dairy, Grains & Starches, Fruits, Vegetables, Nuts/Seeds & Fats,
Snacks & Prepared, Drinks, Condiments).

- Source: `SeedData.defaultFoodGroups` in `lib/mock/seed_data.dart`
- Stable ids: `food-group-proteins`, `food-group-dairy`,
  `food-group-grains-starches`, `food-group-fruits`,
  `food-group-vegetables`, `food-group-nuts-seeds-fats`,
  `food-group-snacks-prepared`, `food-group-drinks`,
  `food-group-condiments`.
- Both `MockWorkoutRepository.initialize()` and
  `HiveWorkoutRepository.initialize()` populate the same 9 rows.
- The user can rename, archive, or delete any default. The mutator
  paths are provenance-agnostic — default status is a seed-time
  concept, not a runtime flag.

### Catalog `category` → `groupId` mapping

Catalog foods are loaded from `assets/data/food_catalog.json`. The
JSON carries a human-readable `category` string per row; the data
layer resolves it to a `groupId` FK at load time.

- Resolution site: `FoodCatalogLoader._categoryToGroupId` in
  `lib/data/datasources/food_catalog_loader.dart` (case-insensitive
  lookup keyed by the catalog's `category`).
- Unknown categories fall through to `groupId = null` (Ungrouped).
- The same map is mirrored by `scripts/generate_food_catalog_seed.dart`
  so the hard-coded `FoodCatalogSeed.sampleCatalogFoods` list stays
  in lockstep with the JSON.
- `notes` is **not** used to carry the category anymore — it is
  reserved for free-form user notes ("Info"). Catalog rows are
  seeded with `notes = null`.
- `addCatalogFoodToLibrary()` carries `groupId` across via
  `Food.copyWith` (which preserves it by default), so a catalog row's
  resolved category propagates to the user's library copy.

### Backwards compatibility for legacy installs

Pre-existing installs may have catalog rows where `notes` carries the
category label and `group_id` is `NULL`. The Hive one-shot migration
`food_category_groupid_migrated_v1` (see the Hive Migration Keys
section above) backfills the `group_id` FK and clears `notes`. The
equivalent SQL block for the future `SqliteWorkoutRepository`
importer is documented in `scripts/sqlite_schema.sql` under
"FOOD CATEGORY → GROUP_ID MIGRATION (June 2026)".

### Repository APIs

| Method | Description |
|---|---|
| `getFoods({includeArchived})` | Returns only library foods (`isCatalog == false`). |
| `getFoodById(id)` | Returns a library food by ID, or `null` if not found or if it's a catalog food. |
| `createFood(food)` | Creates a new library food. |
| `updateFood(food)` | Updates an existing library food. |
| `archiveFood(id)` | Soft-deletes a library food (sets `isArchived = true`). |
| `getCatalogFoods({includeArchived})` | Returns catalog foods (`isCatalog == true`). |
| `getCatalogFoodById(id)` | Returns a catalog food by ID. |
| `addCatalogFoodToLibrary(catalogFoodId)` | Copies a catalog food to the library with a new ID and `isCatalog = false`. The original catalog food remains unchanged. || `reassignFoodsToGroup(foodIds, targetGroupId)` | Moves a list of foods to a new group (or `null` for "Ungrouped") in place. Used by the Categories tab when deleting a non-empty group; foods are never deleted. Catalog foods are excluded. Empty list is a no-op. || `getConsumedFoodsForDate(dateMs)` | Returns consumed food entries for a specific day (matching `dateMs`). |
| `createConsumedFood(entry)` | Creates a new consumed food log entry. |
| `updateConsumedFood(entry)` | Updates an existing consumed food entry by `id`. Throws `StateError` if the id is not present. Used by the day-uniqueness update path in `NutritionState.logConsumedFoodAt`. |
| `getConsumedFoodById(id)` | Returns a single consumed food entry by id, or `null` if not found. Used as a cache-miss fallback by `NutritionState.findLoggedTodayForFood`. |
| `deleteConsumedFood(id)` | Deletes a consumed food entry. |
| `getConsumedFoodsInRange(fromMs, toMs)` | Returns consumed foods in a date range (inclusive). |

### Storage Shape

**Library foods (Hive)**:
- Box: `foods` — key = `Food.id`, value = `Food.toMap()`

**Catalog foods (Hive)**:
- Box: `foods_catalog` — key = `Food.id`, value = `Food.toMap()`

**Consumed foods (Hive)**:
- Box: `consumed_foods` — key = `ConsumedFood.id`, value = `ConsumedFood.toMap()`

**Mock (in-memory)**:
- `_foods`: `Map<String, Food>` for library
- `_catalogFoods`: `Map<String, Food>` for catalog
- `_consumedFoods`: `Map<String, ConsumedFood>` for day log

**SQLite**:
- `app_food`: library foods (including copies from catalog, marked with `is_catalog = 0`)
- `app_food_catalog`: read-only catalog foods (see `scripts/sqlite_schema.sql` for schema)
- `app_consumed_food`: frozen snapshot of logged foods (see `scripts/sqlite_schema.sql` for schema)

### Frozen Snapshot Contract

When a food is logged via `createConsumedFood`, the entry stores a complete snapshot:
- Food name, unit type, reference amount/label, macros
- Group ID and name at log time
- Daily nutrition targets in effect

This ensures historical accuracy: editing or deleting a library food, or changing targets, does not affect past day logs.

### Consumed-Food Query Path (Calorie Ring)

`NutritionState.loadConsumedToday()` / `getTodayConsumedFoods()` read
today's snapshots via the abstract `WorkoutRepository.getConsumedFoodsForDate(dateMs)`.
Both `HiveWorkoutRepository` and `MockWorkoutRepository` already implement
this method (Hive: scan `consumed_foods` box and filter on `dateMs`;
Mock: in-memory `Map<String, ConsumedFood>` filtered on `dateMs`). The
future `SqliteWorkoutRepository` is expected to use the
`IX_consumed_food_date` index on `app_consumed_food(date_ms DESC)` for an
O(log n) lookup. No new repository methods, no new boxes, and no schema
change are required for the calorie-ring feature.

---

---

## SQLite Assets (Parity And Future Runtime)

`scripts/sqlite_schema.sql` now includes profile structures:

- `app_user_profile`
- `app_body_measurement_entry`
- Indexes for measurement history queries by type/user + recorded time desc

It also includes session/observation extensions:

- `app_training_session.session_feeling`
- `app_training_session.quality_rating`
- `app_effort_observation.rpe_rating`
- `app_effort_observation.rest_duration_ms`

And exercise modality persistence for custom exercise parity:

- `app_exercise.modality` (nullable for legacy rows)

`scripts/sqlite_seed.sql` now seeds stable unit IDs and metric IDs, including:

- `unit-cm`
- `unit-pct`
- canonical `metric-*` rows aligned with constant IDs

Active-session ordering parity columns for future `SqliteWorkoutRepository`:

- `app_session_block.top_level_order_index`
- `app_segment_effort.top_level_order_index`
- `app_segment_effort.block_order_index`

Recommended SQL ordering for retrieval parity:

- Blocks: `ORDER BY top_level_order_index, order_index, created_at_ms, id`
- Efforts: `ORDER BY top_level_order_index, block_order_index, order_index, created_at_ms, id`

---

## SQLite Datasource Versioning

- `DatabaseProvider.open(..., version: 7)` is now the default.
- `migrations.dart` contains incremental SQL migrations for:
  - v2: `modality`, `intent` fields on `app_training_session`
  - v3: `session_feeling`, `quality_rating`, `rpe_rating`, `rest_duration_ms`
  - v4: `app_entry_rest` table
  - v5: exercise content and `app_exercise_note`
  - v6: rolling sessions, `app_session_block`, and `block_id`
  - v7: canonical ordering fields (`top_level_order_index`, `block_order_index`) and indexes for deterministic active-session ordering

---

## Practical Notes

- DB schema/seed SQL are loaded from assets via `rootBundle`.
- `DatabaseProvider` supports `inMemory` mode for deterministic tests.
- Current runtime behavior is Hive-first; SQL assets are still maintained to preserve repository parity and avoid drift.

---

## Session Block Semantics (Iteration 5 change)

`deleteSessionBlock(blockId)` now **cascade-deletes** all linked `SegmentEffort` records and their sub-records (observations, round instances, timed instances, entry rests). This changed from the Iteration 1 design which only nulled `blockId` on linked efforts.

- Both `HiveWorkoutRepository` and `MockWorkoutRepository` implement the cascade.
- `WorkoutState.deleteSessionBlock` mirrors the cascade in its in-memory caches.
- The SQLite schema remains `ON DELETE SET NULL` on `app_segment_effort.block_id`; the app layer performs the cascade before any FK action fires.

`cloneSessionBlock(blockId)` names clones using the current wall-clock time label (`"h:mm AM/PM"`) across all session modalities/intents.

`addSessionBlock({String? name})` now accepts an optional `name` parameter. When `name` is omitted, the current time in `"h:mm AM/PM"` format is used.

---

## Sub-Holder Architecture and Repository Access

After the `workout-state-and-screen-refactor`, `WorkoutState` is a thin `ChangeNotifier` facade that constructs three sub-holders. Each sub-holder independently holds a `WorkoutRepository` reference — they do **not** share a single repository reference through the facade.

```
WorkoutRepository (injected into WorkoutState)
   │
   ├─► TimerManager(_repository, notify: ...)
   │     Owns: RoundInstance, TimedInstance, EntryRest writes
   │
   ├─► ExerciseLibrary(_repository, notify: ...)
   │     Owns: Exercise, ExerciseNote reads/writes
   │
   └─► SessionCore(_repository, notify: ..., timerManager, exerciseLibrary)
         Owns: TrainingSession, SessionSegment, SegmentEffort, EffortObservation
         Delegates timer creation to TimerManager
         Delegates note cache clearing to ExerciseLibrary
```

All repository reads and writes go through the same `WorkoutRepository` interface. The concrete implementation (`HiveWorkoutRepository` or future `SqliteWorkoutRepository`) is injected once at app startup and passed to each sub-holder.

### SyncService Integration Surface (forward-looking)

When cloud sync is added, `SyncService` will be injected alongside `WorkoutRepository` at each sub-holder construction. The pattern is:

```dart
// After each successful repository write in SessionCore:
await _repository.createSession(session);
_syncService?.queueCreate(SyncEntity.session, session);
```

The same seam applies in `TimerManager` (for round/timed instance writes) and `ExerciseLibrary` (for exercise and note writes). No repository interface changes are required — `SyncService` is an additive injection.

---

**Document Version**: 1.5
**Last Updated**: May 31, 2026
