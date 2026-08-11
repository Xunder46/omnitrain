# DB Integration

## Overview

OmniTrain uses a repository-first persistence architecture:

- Runtime app persistence: `HiveWorkoutRepository` (web and current cross-platform runtime)
- SQL schema assets: maintained in `scripts/` for SQLite parity work
- Single abstraction contract: `WorkoutRepository`

This document explains how to validate DB assets and how profile-related persistence is represented in both Hive runtime and SQL assets.

---

## Key Files

- `lib/data/repositories/workout_repository.dart`
- `lib/data/repositories/hive_workout_repository.dart`
- `lib/data/repositories/mock_workout_repository.dart`
- `lib/data/datasources/food_catalog_loader.dart`
- `scripts/sqlite_schema.sql`
- `scripts/sqlite_seed.sql`
- `test/db_seed_test.dart`

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

### Catalog version + seed-entry tombstones (July 2026)

The bundled app-authored catalog (exercises + capability / muscle-group /
equipment relationships + the food catalog + seeded demo workout
templates) is versioned. At app start, `CatalogRefreshService`
(`lib/core/services/catalog_refresh_service.dart`) compares the device's
stored catalog version against the bundled constant
(`bundledCatalogVersion` in `lib/core/constants/catalog_version.dart`); if
the bundled version is newer, the refresh re-applies new / changed seed
entries to the device in place, never touching user-created entries and
never overwriting a seed entry the user has edited.

`SeedEntryType` enumerates the tombstone key spaces the refresh understands:

| Constant | Tombstone space | Notes |
|---|---|---|
| `SeedEntryType.exercise` | `seed_entry_touched_exercise_<exerciseId>` | Bundled exercises. |
| `SeedEntryType.foodCatalog` | `seed_entry_touched_food_catalog_<foodId>` | Bundled food-catalog rows. |
| `SeedEntryType.routineTemplate` | `seed_entry_touched_routine_template_<demoTemplateId>` | Bundled demo routines (the `Demo`-tagged routines delivered through the catalog refresh; version bumped to `3` to ship the initial set). |

The repository exposes four small methods used by the refresh orchestrator
and by the state layer:

| Method | Purpose |
|---|---|
| `getCatalogVersion({defaultValue})` | Reads the device's stored catalog version. Returns `0` for legacy installs (no prior refresh). |
| `setCatalogVersion(int)` | Persists the device's catalog version. Called once, at the end of a successful refresh. |
| `isSeedEntryTouched(type, id)` | Returns `true` if the user has ever mutated the seed entry at `(type, id)`. |
| `markSeedEntryTouched(type, id)` | Tombstone setter. Called by the state layer whenever the user edits / archives / deletes a seed entry. Idempotent. |

Storage shape:

- Hive: the meta box holds `catalog_version` (int) and a `bool` per
  tombstone under the key `seed_entry_touched_<type>_<id>`.
- Mock: in-memory `int _catalogVersion` (default `0`) and
  `Map<String, bool> _seedEntryTouched` keyed by `<type>_<id>`.
- SQLite parity: see the "CATALOG VERSION + SEED-ENTRY TOMBSTONES
  (July 2026)" block at the bottom of `scripts/sqlite_schema.sql`. The
  future `SqliteWorkoutRepository` is expected to use a single
  `app_meta` key/value table for both the version and the tombstones,
  keeping the orchestrator code identical across runtimes.

Idempotency + interruption safety:

- The refresh writes each entry individually (no clear-then-repopulate).
- On any error mid-refresh, the stored version is NOT advanced; the next
  launch retries from where it left off with the prior data still intact.
- Running the refresh twice yields identical state: the second pass is a
  no-op (stored version already at or above the bundled version).

### Data-migration version sequence (July 2026)

OmniTrain consolidates thirteen previously-independent one-time migration
steps (`seed_loaded`, `seed_units_migrated_v1`, …) into a single ordered
update sequence tracked by the device's `data_version` integer (see
[`lib/core/constants/data_version.dart`](../../../lib/core/constants/data_version.dart)
and [`DataMigrationService`](../../../lib/core/services/data_migration_service.dart)).
On startup, `HiveWorkoutRepository.initialize()` runs the service:

1. Reads the device's `data_version` (default `1`).
2. **Back-compat shim** — when `data_version == 1` AND any legacy one-shot
   marker is present, the shim maps the highest legacy marker to a
   starting version and writes it back. Existing installs land at the
   correct starting point in one launch; already-applied steps are not
   re-run.
3. Runs every pending step in ascending `targetVersion` order. After each
   step succeeds, `data_version` is advanced to the step's target. A
   failing step does NOT advance past itself; the next launch retries
   from that step.
4. Records the most recent `from → to` transition in the meta box for
   diagnostics.

The shim maps the highest legacy marker present to its implied version, because the legacy code
always ran the steps in order. The mapping lives in
[`lib/core/constants/data_version.dart`](../../../lib/core/constants/data_version.dart).

Repository methods used by the service:

| Method | Purpose |
|---|---|
| `getDataVersion({defaultValue})` | Reads the device's stored version. |
| `setDataVersion(int)` | Persists the device's version after each step. |
| `getLegacyAppliedDataVersion()` | Back-compat shim: returns the highest version implied by any legacy marker (`1` if none). |
| `getLastDataVersionTransition()` | Diagnostic: most recent `(from, to)` transition, or `null`. |
| `setLastDataVersionTransition(int from, int to)` | Diagnostic: records a transition. |

Storage shape (Hive runtime; SQL parity noted for the future importer):

| Hive meta-box key | Type | Semantics |
|---|---|---|
| `data_version` | int | Current data-migration version; `1` on legacy installs not yet mapped by the shim. |
| `data_version_last_from` | int | Starting version of the most recent migration run (diagnostic). |
| `data_version_last_to` | int | Ending version of the most recent migration run (diagnostic). |

Adding a new step: append a row to `HiveWorkoutRepository._dataMigrationSteps()`
and bump `currentDataVersion` in
[`lib/core/constants/data_version.dart`](../../../lib/core/constants/data_version.dart).
The next launch runs the new step exactly once per device. No new meta-box
key is required for the step itself.

Idempotency: every consolidated step preserves its existing effect — same
box writes, same upsert semantics, same idempotency — only the gating
changes (legacy `bool` marker → version check). The legacy `bool` markers
are still read by the shim for back-compat but are otherwise inert.

Catalog content versioning (`catalog_version`, `seed_entry_touched_*`) is
a separate always-on mechanism and is unaffected by `data_version`.

Tests: see `test/data_migration_test.dart` for the ordered-sequence,
back-compat shim, retry-on-failure, idempotency, and orthogonality cases.

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

## Daily Water Log

`WorkoutRepository` exposes date-aware water-log APIs alongside the
nutrition-target methods:

| Method | Behaviour |
|---|---|
| `getWaterVolumeForDate(int dateMs)` | Returns the stored milliliter value for [dateMs]. Returns `0` when no row exists — the absence of a row is the same as a 0 ml day, callers never see `null`. |
| `saveWaterVolumeForDate(int dateMs, int volumeMl)` | Upserts the row for [dateMs]. `volumeMl` is clamped to `>= 0` as a last line of defense against bad inputs. Past dates other than [dateMs] are never touched. |

The row id is deterministic (`'water-<dateMs>'`) so the same day always
maps to the same storage key in both implementations. The per-glass
amount is canonical at `kWaterGlassMl = 250` (see
`lib/core/constants/water_constants.dart`); the on-screen glass count
is derived at the display boundary (`volumeMl ~/ kWaterGlassMl`),
never stored. Water has no goal — like macros and sodium, it is
tracked and stored for the historical record only.

Implementation requirements (both `HiveWorkoutRepository` and `MockWorkoutRepository`):
- **Storage shape**:
  - Hive: a dedicated box `water_log` keyed by `dateMs.toString()`
    with a `Map<String, dynamic>` value matching `WaterLogEntry.toMap()`.
  - Mock: an in-memory `Map<int, int>` keyed by `dateMs` (just the ml value).
  - SQLite: the `app_water_log` table is keyed by `date_ms` (`INTEGER
    UNIQUE`) with `volume_ml INTEGER NOT NULL CHECK (volume_ml >= 0)`;
    see `scripts/sqlite_schema.sql` for the schema narrative.
- **Past dates are immutable**: the repository never walks forward and
  modifies dates earlier than the explicitly-written [dateMs].
- **Day-rollover semantics**: `NutritionState.rolloverToDate(newDateMs)`
  clears the in-memory water cache for the new day and reloads it via
  `getWaterVolumeForDate(newDateMs)`; the prior date's stored ml is
  untouched.

Tests: see `test/state_test.dart` (`NutritionState daily water log`
group) for the per-day volume contract — increment / decrement,
floor at 0, immediate persistence round-trip, date isolation, and the
extended day-rollover test (the existing `rolloverToDate` test now
also asserts water behavior).

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
`food_category_groupid_migrated_v1` backfills the `group_id` FK and clears `notes`. The
equivalent SQL block for the future `SqliteWorkoutRepository`
importer is documented in `scripts/sqlite_schema.sql` under
"FOOD CATEGORY → GROUP_ID MIGRATION (June 2026)".

### Macro columns: `INTEGER` → `REAL` widening (v1.5)

The bundled v1 schema declared `protein` / `carbs` / `fiber` /
`fat` / `sodium` as `INTEGER` on the `app_food`, `app_food_catalog`,
and `app_consumed_food` tables. The v1.5 form lets the user type
fractional grams (e.g. `0.5` g of fat), so the corresponding
columns in `scripts/sqlite_schema.sql` are now `REAL` (nullable
columns stay nullable). The change is back-compatible at read
time:

- `Food.fromMap` and `ConsumedFood.fromMap` use the
  `((m['k'] as num?) ?? 0.0).toDouble()` pattern, which accepts
  both legacy `INTEGER` rows and new `REAL` rows.
- No row migration is required; the existing rows continue to
  read back with the same value (now as `double`).
- See [food-form-decimals-and-autofocus-plan.md](../plans/food-form-decimals-and-autofocus-plan.md)
  for the full rationale and the back-compat pattern.

### `last_amount_consumed` column on `app_food` (June 2026)

The `app_food` table gained a nullable `last_amount_consumed REAL`
column to back the `LogFoodRow` amount pre-fill
(`food-last-amount-plan.md`). The column:

- Stores the remembered "last amount" the user logged for the
  food, in the food's own unit (grams for `grams`-type foods,
  count-multiplier for `count`-type foods).
- Is `NULL` when the food has never been logged. Legacy rows
  (pre-feature) deserialize to `null` via `Food.fromMap`'s
  `(m['last_amount_consumed'] as num?)?.toDouble()` pattern.
- Is overwritten by `NutritionState` on every successful
  `logConsumedFoodAt` / `logConsumedFood` call. The state
  write-through uses `updateFood(food.copyWith(lastAmountConsumed:
  amount, updatedAtMs: now))` — no new repository methods.
- Survives remove-then-re-add of a catalog copy because the
  `catalogId` linkage (per `food-durable-identity-plan.md`)
  reuses the existing library food row instead of creating a new
  one.
- Is never mutated by an unsaved UI edit on `LogFoodRow` —
  typing in the amount input on an unlogged row updates the
  in-memory `TextEditingController` only; the food row is
  written only when the user explicitly commits (tapping the
  thumb, debounced auto-commit, etc.).

No new Hive box, no new repository method, no new index. The
existing `IX_food_*` indexes (on `is_archived`, `group_id`,
`is_catalog`, `catalog_id`) already cover every query path
that touches `last_amount_consumed` (which is none — the field
is read via the `getFoodById` primary-key path, written via
the existing `updateFood`).

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
| `addCatalogFoodToLibrary(catalogFoodId)` | Copies a catalog food to the library with a new ID and `isCatalog = false`. The original catalog food remains unchanged. || `reassignFoodsToGroup(foodIds, targetGroupId)` | Moves a list of library foods to a new group (or `null` for "Ungrouped") in place. Used by the Groups tab when deleting a non-empty group; foods are never deleted. Catalog foods are excluded. Empty list is a no-op. |
| `reassignCatalogFoodsToGroup(catalogFoodIds, targetGroupId)` | Parallel to `reassignFoodsToGroup` but targets the catalog box. Used by `FoodLibraryState.deleteFoodGroupReassigningFoods` so user-created catalog foods (those created via **+ New Item**) are moved off a deleted category. Bundled catalog foods are never passed here — the bundled-food guard at the state layer rejects them. Empty list is a no-op. || `getConsumedFoodsForDate(dateMs)` | Returns consumed food entries for a specific day (matching `dateMs`). |
| `createConsumedFood(entry)` | Creates a new consumed food log entry. |
| `updateConsumedFood(entry)` | Updates an existing consumed food entry by `id`. Throws `StateError` if the id is not present. Used by the day-uniqueness update path in `NutritionState.logConsumedFoodAt`. |
| `getConsumedFoodById(id)` | Returns a single consumed food entry by id, or `null` if not found. Used as a cache-miss fallback by `NutritionState.findLoggedTodayForFood`. |
| `deleteConsumedFood(id)` | Deletes a consumed food entry. |
| `getConsumedFoodsInRange(fromMs, toMs)` | Returns consumed foods in a date range (inclusive). |

### Image Storage (managed directory)

Profile avatars and food photos are stored as files in a managed
directory, not as BLOBs in the database. This ensures native platform
compatibility and proper memory handling for large images.

**Managed directory**: `<applicationDocumentsDirectory>/omni_images/`

**Filename shape**: `<uuid-v4>.<ext>` where `<ext>` is preserved from
the picked image (with fallback chain: name → path → `.jpg`)

**Storage contract**:
- The image file is stored in the file system under the managed directory
- The string stored in `avatar_path` (UserProfile) or `image_path`
  (Food) is the **basename** (e.g. `e8b3…0123.jpg`) — not an
  absolute path. The reference is location-independent and survives
  OS-driven relocations of the app's documents directory.
- The repository never reads or writes the image file directly
- This is the same contract documented in `docs/profile_and_measurements.md`
  — "Avatar Persistence"

**Why not SQL BLOB**: The file system is the native platform's native
persistence for large binary assets. Storing images as BLOBs would
require base64 encoding, which increases storage size by ~33% and
complicates memory management when loading images for display. The
managed directory approach keeps the SQL schema unchanged and leverages
platform-native file caching.

**Resolve + re-link on load**: `ImageStorageService.resolveOrRelink(reference)`
resolves a stored reference back to a reachable file. The service
searches the current managed directory first, then the literal
reference path (legacy absolute paths), then bounded candidate
directories (picker temp cache, application support directory). If
a matching file is reachable anywhere, the service re-links it into
the current managed directory (one-time copy) and returns the
basename. The state persists the normalized basename back to the
record on first load after the fix.

**Self-heal only on truly-absent files**: The state writes `null`
back to the record **only when the file is verifiably absent** from
every candidate location. This prevents the launch-blocker regression
where a photo whose file is still on the device (but whose absolute
path is stale) becomes unrecoverable. Pre-fix records with legacy
absolute paths are migrated to the basename on first load after the
fix; the reference is never nulled while the file is reachable.

**Delete gate**: `ImageStorageService.isManaged(path)` is the gate
for absolute-path deletes (legacy migration only). For the modern
basename contract, the service deletes `<managedDir>/<basename>`
unconditionally — basenames are by convention managed (they can only
have been produced by `persistPickedImage` or
`persistImageBytes`). The service still protects against deleting
files outside its scope: a non-managed absolute path passed to
`deleteIfManaged` is a no-op.

**Bytes-shaped input for the avatar crop step**:
`ImageStorageService.persistImageBytes(Uint8List bytes, {String
extension = '.png'})` writes an already-decoded byte buffer to the
managed directory and returns the basename. Used by the avatar
crop step, which captures the framed region via
`RepaintBoundary.toImage(pixelRatio: 3.0, format:
ImageByteFormat.png)` and ends up with a `Uint8List` rather than a
path on disk. Mirrors the persistence contract of
`persistPickedImage(XFile)` (basename + managed-dir copy + D-6
cleanup of partial files on write failure). The web stub throws
`UnsupportedError` like the other methods — the call site already
early-returns on `kIsWeb` with the user-facing snackbar.

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

## SQLite Schema Versioning

> **Corrected 2026-07-26 (docs audit).** This section described a live
> `DatabaseProvider.open(..., version: 7)` runtime and a `migrations.dart`
> holding incremental SQL migrations. **Neither file exists any more.** The
> SQLite *runtime* was retired (see
> `.github/agents/plans/retire-sqlite-runtime-plan.md`):
> `lib/data/datasources/database_provider.dart`, `db_helper.dart`, and
> `migrations.dart` were deleted, `sqflite` was dropped from `dependencies`
> (only `sqflite_common_ffi` remains, under `dev_dependencies`, for the
> validation test), and the SQL files are no longer bundled as Flutter
> assets. The app persists exclusively through `HiveWorkoutRepository` on
> every platform.

What remains is the **schema documentation**, and it is still authoritative
for the data model:

- `scripts/sqlite_schema.sql` and `scripts/sqlite_seed.sql` are maintained in
  the repository as the pipeline's canonical data-model contract.
- Schema evolution is expressed as `ALTER TABLE` / `CREATE TABLE IF NOT
  EXISTS` statements appended to `sqlite_schema.sql` itself, not as separate
  numbered migration files.
- The historical migration steps the retired provider applied are listed
  below for reference. They are **history**, not a live upgrade path:
  - v2: `modality`, `intent` fields on `app_training_session`
  - v3: `session_feeling`, `quality_rating`, `rpe_rating`, `rest_duration_ms`
  - v4: `app_entry_rest` table
  - v5: exercise content and `app_exercise_note`
  - v6: rolling sessions, `app_session_block`, and `block_id`
  - v7: canonical ordering fields (`top_level_order_index`,
    `block_order_index`) and indexes for deterministic active-session ordering

Runtime **data** migrations (the ones that actually execute today) are a
separate mechanism keyed on `currentDataVersion` — see
[Constants Reference](constants_reference.md#data_versiondart).

---

## Practical Notes

- The schema/seed SQL are read from disk with `File` by
  `test/db_seed_test.dart`, which executes them against an in-memory
  `sqflite_common_ffi` database to prove they remain valid, executable SQL.
  They are **not** loaded via `rootBundle` and are no longer shipped as app
  assets.
- Runtime persistence is Hive on every platform. The SQL files are
  maintained as the data-model contract so the documented schema cannot
  drift from the models.

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

---

**Document Version**: 1.5
**Last Updated**: May 31, 2026


---

> **Doc freshness** — Last reconciled against source: 2026-07-26. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree as it exists on the reconciliation date. If you find a claim here that disagrees with `lib/`, `lib/` wins — please flag the drift in a fresh chat with the Coordinator agent.
