# DB Integration — nutrition storage (part page)

Part of [DB Integration](db_integration.md): the water log and the food library / catalog storage sections, split out to keep each page under the indexing ceiling. Section order and wording are unchanged.

## Daily Water Log

`WorkoutRepository` exposes date-aware water-log APIs alongside the
nutrition-target methods:

| Method | Behaviour |
|---|---|
| `getWaterVolumeForDate(int dateMs)` | Returns the stored milliliter value for [dateMs]. Returns `0` when no row exists — the absence of a row is the same as a 0 ml day, callers never see `null`. |
| `saveWaterVolumeForDate(int dateMs, int volumeMl)` | Upserts the row for [dateMs]. `volumeMl` is clamped to `>= 0` as a last line of defense against bad inputs. Past dates other than [dateMs] are never touched. The day's applied-tap ledger is kept as it is. |
| `applyWaterTap({dateMs, tapId, deltaMl})` | Applies one watch tap (`deltaMl` = ± the current step, `waterStepMlFor`) at most once: a new `tapId` changes the volume (floored at 0 ml) and is appended to the day's ledger in one write, and returns `true`; a remove at 0 ml still records the id. A known id, or a ledger already holding `kWatchWaterTapsPerDay` ids, changes nothing and returns `false` (plan 94 D-3, D-5). |
| `getAppliedWaterTapIds(int dateMs)` | The day's applied tap ids in append order; `[]` with no row or a row written before the ledger. |

The row id is deterministic (`'water-<dateMs>'`) so the same day always
maps to the same storage key in both implementations; the tap step is `waterStepMlFor`, 250 ml or 237 ml with fl oz
(see `lib/core/constants/water_constants.dart`) — the on-screen total
is shown in the user's volume unit at the display boundary, never
stored — verified by `test/state_test.dart` (group `NutritionState
volume unit`: `S-13205 the fl oz unit steps 237 ml through plus,
minus and watch taps; the ml unit still steps 250`) and
`test/nutrition_test.dart` (group `WaterTrackerControl — total in the
volume unit (S-13207, S-13210, S-13214)`: `S-13208 the card follows a
weight-unit change with no other call`). Water has no goal — like macros and sodium, it is
tracked and stored for the historical record only.

Implementation requirements (both `HiveWorkoutRepository` and `MockWorkoutRepository`):
- **Storage shape**:
  - Hive: a dedicated box `water_log` keyed by `dateMs.toString()`
    with a `Map<String, dynamic>` value holding `WaterLogEntry.toMap()`'s
    keys, except that `applied_tap_ids` is a `List<String>` (absent, and read
    as `[]`, on a row written before the ledger existed or created by the
    phone's own +, until the row's next write), so volume and ledger change
    in one `put`.
  - Mock: an in-memory `Map<int, int>` keyed by `dateMs` (just the ml value)
    and a `Map<int, List<String>>` ledger beside it.
  - SQL contract: the `app_water_log` table is keyed by `date_ms` (`INTEGER
    UNIQUE`) with `volume_ml INTEGER NOT NULL CHECK (volume_ml >= 0)` and
    `applied_tap_ids TEXT NOT NULL DEFAULT '[]'` (a JSON array);
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
also asserts water behavior). The tap ledger — math, a remove at 0,
duplicates across a relaunch, a save keeping the ledger, the 500 cap,
day independence — runs on both implementations in
`test/water_tap_ledger_test.dart` (S-94a-3..S-94a-8).

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
- See [food-form-decimals-and-autofocus-plan.md](plans/food-form-decimals-and-autofocus-plan.md)
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
| `reassignCatalogFoodsToGroup(catalogFoodIds, targetGroupId)` | Parallel to `reassignFoodsToGroup` but targets the catalog box. Used by `FoodLibraryState.deleteFoodGroupReassigningFoods` so user-created catalog foods (those created via the header **+ New Food**) are moved off a deleted category. Bundled catalog foods are never passed here — the state layer filters them out before the call. Empty list is a no-op. || `getConsumedFoodsForDate(dateMs)` | Returns consumed food entries for a specific day (matching `dateMs`). |
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
