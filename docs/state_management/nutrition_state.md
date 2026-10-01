# Nutrition State

> Part of [State Management & Services](../state_management.md). Return to the index for the full class list and dependency graph.

---

### `NutritionState`

**File**: `lib/state/nutrition_state.dart`
**Depends on**: `WorkoutRepository`

Manages the user's daily nutrition targets and the cached "today's
consumed foods" used by the calorie ring on the nutrition page. Targets
are keyed by date (start-of-day ms) and roll over from the most recent
ancestor day when no explicit entry exists. See
[Daily targets persistence](../db_integration.md#nutrition-targets-daily-rollover)
and [Consumed-Food State Cache](../data_models.md#consumed-food-state-cache-nutritionstate).

#### Key State Fields

| Field | Type | Purpose |
|---|---|---|
| `_nutritionTarget` | `NutritionTarget?` | The currently loaded (or rolled-over) target for the active day. |
| `_isLoading` | `bool` | Loading state for async target operations. |
| `_targetsByDate` | `Map<int, NutritionTarget?>` | Per-date cache of loaded targets. Avoids re-fetching the same day on subsequent navigation. |
| `_consumedToday` | `List<ConsumedFood>` | Cached list of today's consumed-food snapshots. Empty until first load. |

#### Key Methods

| Method | Purpose |
|---|---|
| `loadNutritionTargetForDate(int dateMs)` | Loads the target for [dateMs]. Repository walks backward to find the most recent ancestor if no entry exists for the requested day. Updates cache + `_nutritionTarget` and notifies listeners. |
| `saveNutritionTargetForDate(int dateMs, NutritionTarget target)` | Persists [target] for [dateMs]. The repository forward-propagates to future dates that still hold the old values; past dates are never modified. Updates cache + `_nutritionTarget` and notifies listeners. |
| `getTodayTarget()` | Convenience: loads today's target, returns it, updates the cache, and notifies listeners. |
| `rolloverToDate(int dateMs)` | Day-rollover safety net. Clears the in-memory `_consumedToday` cache, the per-date `_targetsByDate` cache, and the `_waterTodayMl` cache (so a long-running app cannot leak yesterday's totals or volume into today), then delegates to `loadNutritionTargetForDate(dateMs)` (backward-walk fallback for the new day) and `loadWaterForDate(dateMs)` (re-reads the new day's volume, typically 0 ml). Past `ConsumedFood` rows and prior dates' stored ml in the water log are unaffected — only the in-memory caches are cleared. |
| `getCachedTargetForDate(int dateMs)` | Returns the cached target for [dateMs] without re-fetching. `null` if not yet loaded. |
| `loadNutritionTarget()` | Legacy; delegates to `loadNutritionTargetForDate(todayMs)`. |
| `saveNutritionTarget(NutritionTarget target)` | Legacy; delegates to `saveNutritionTargetForDate(todayMs, target)`. |
| `consumedToday` | Unmodifiable view of today's cached consumed-food snapshots. Drives the calorie ring. |
| `todayConsumedCalories` | Derived sum of `ConsumedFood.caloriesConsumed` over `consumedToday`. Pure / derived; 0 when the cache is empty. |
| `todayConsumedProtein` | Derived sum of `protein * amountConsumed / referenceAmount` over `consumedToday`, accumulated as a `double` and rounded **once at the end**. Matches the `caloriesConsumed` rounding contract (which is also a single per-snapshot round) and avoids per-row rounding drift on fractional servings. |
| `todayConsumedCarbs` | Same shape as `todayConsumedProtein`, for carbs. |
| `todayConsumedFiber` | Same shape as `todayConsumedProtein`, for fiber. `ConsumedFood.fiber` is `int?`; `null` is treated as 0. |
| `todayConsumedFat` | Same shape as `todayConsumedProtein`, for fat. |
| `todayConsumedSodium` | Same shape as `todayConsumedFiber`, for sodium. D-7 freeze: `null` source sodium (or rows logged before the freeze) is treated as 0. Rendered as the corner chip `Na N mg` on the calorie-ring card. |
| `consumedTodaySorted` | `consumedToday` sorted by `loggedAtMs` ascending. New list; the cache stays in insertion order. |
| `loadConsumedToday()` | Reloads today's snapshots from the repository, replaces the cache, notifies listeners. Idempotent. |
| `getTodayConsumedFoods()` | Convenience wrapper around `loadConsumedToday()`; returns the resulting list. |
| `refreshConsumedToday()` | Sugar for `loadConsumedToday()` that returns the resulting list. |
| `logConsumedFood(Food, double amount)` | Builds a frozen `ConsumedFood` snapshot from the source food plus the cached daily target, persists it via the repository, and appends it to the cache so the ring updates immediately. The snapshot freezes: food name, unit type, reference amount/label, macros, the source food's `sodium` (D-7), and the daily target fields. After the `ConsumedFood` write succeeds, the source food's `lastAmountConsumed` is updated to `amount` via `updateFood(food.copyWith(lastAmountConsumed: amount))` (June 2026, `food-last-amount-plan.md`). The food-row write is best-effort — a transient `updateFood` failure does not roll back the `ConsumedFood` row or block returning the new id. Returns the new id, or `null` on invalid amount (≤ 0) or persistence failure. |
| `logConsumedFoodAt(Food, double amount)` | Day-uniqueness variant: if a row for `(sourceFoodId, today)` already exists, updates its `amountConsumed` in place; otherwise delegates to `logConsumedFood`. Used by the per-row checkbox + amount-input UI on the food library card. Same write-through to `lastAmountConsumed` as `logConsumedFood` on every successful save. Returns the row id, or `null` on invalid amount or persistence failure. |
| `unlogFoodToday(String foodId)` | Removes the day-log row for `foodId` (today). Returns `true` if a row was removed, `false` otherwise. Does NOT touch `lastAmountConsumed` on the source food — the remembered value persists across an unlog so the next log pre-fills with it. |
| `findLoggedTodayForFood(String foodId)` | Cache-only lookup of the day's row for `foodId`. Returns `null` when not logged today. |
| `isFoodLoggedToday(String foodId)` | True when a day-log row exists for `foodId`. Drives the row's checkbox `value:` binding. |
| `deleteConsumedFood(String id)` | Removes a consumed-food row via the repository and refreshes the cache. No-op (and returns `false`) if the id is not in the cache. |
| `clearConsumedToday()` | Empties the consumed-food cache and notifies listeners. Intended for day rollover. |
| `waterTodayMl` | Cached water volume in milliliters for the most recently loaded day. `0` until the first explicit load runs. Drives the bottom-right `WaterTrackerControl` on the calorie-ring card. The canonical unit is milliliters so the historical record stays unit-clean; the on-screen glass count is derived at the display boundary. |
| `waterTodayGlasses` | Derived from `waterTodayMl ~/ kWaterGlassMl` (250). The widget's display count; never stored. |
| `loadWaterForDate(int dateMs)` | Reloads the day's stored ml from the repository, replaces the cache, notifies listeners. Idempotent; safe to call repeatedly. |
| `loadWaterForToday()` | Convenience wrapper that delegates to `loadWaterForDate(todayMidnightMs)`. Called from `NutritionScreen.initState` alongside the target + consumed loads. |
| `incrementWaterForDate(int dateMs)` | Adds `kWaterGlassMl` (250 ml), persists via the repository, updates the cache, and notifies listeners. Always succeeds — `kWaterGlassMl` is positive and the repository clamps at 0. |
| `decrementWaterForDate(int dateMs)` | Subtracts `kWaterGlassMl` (floors at 0 ml), persists, updates the cache, notifies. A minus at 0 is a no-op (no write, no notification, no spurious row) — mirrors the disabled minus button in `WaterTrackerControl`. |

---

---

### `FoodLibraryState`

**File**: `lib/state/food_library_state.dart`
**Depends on**: `WorkoutRepository`

Manages the user's food library: food groups and food items with macronutrient metadata. Provides caching, CRUD operations, and search functionality. All operations route through the repository interface, enabling environment-agnostic persistence (Hive web, SQLite native).

#### Key State Fields

| Field | Type | Purpose |
|---|---|---|
| `_foodGroups` | `Map<String, FoodGroup>` | Cache of food groups keyed by id |
| `_foods` | `Map<String, Food>` | Cache of food items keyed by id |
| `_catalogFoods` | `Map<String, Food>` | Cache of bundled catalog foods (read-only); separate from `_foods` so catalog rows never leak into the library view |
| `_isLoadingGroups` | `bool` | Loading state for food groups |
| `_isLoadingFoods` | `bool` | Loading state for foods |
| `_isLoadingCatalog` | `bool` | Loading state for the catalog cache |

#### Key Methods (library + groups + search — unchanged surface in this iteration; see Catalog + Custom below for additions.)

| Method | Purpose |
|---|---|
| `loadFoodGroups({includeArchived})` | Loads all food groups from repository, updates cache, notifies listeners |
| `loadFoods({includeArchived})` | Loads all foods from repository, updates cache, notifies listeners |
| `createFoodGroup(String name, {String? color})` | Creates a new food group with optional color, persists, and notifies |
| `updateFoodGroup(FoodGroup group)` | Updates an existing food group and persists changes |
| `archiveFoodGroup(String id)` | Archives (soft-deletes) a food group by setting `isArchived = true` |
| `renameFoodGroup(String id, String newName)` | Renames a food group in place (preserves id / color / createdAtMs / isArchived). Used by the Groups tab's inline `TextField`. No-ops on empty / unchanged names; throws if the group is not in the cache. |
| `deleteFoodGroupReassigningFoods(String id, String? toGroupId)` | Archives the group while reassigning its non-archived, user-owned foods (library and user-created catalog foods) to `toGroupId` (or `null` for "Ungrouped"). Foods are never deleted. **Refuses the deletion** by throwing `FoodGroupHasBundledFoodsError` when at least one bundled catalog food still points at the group — rewriting a bundled food's `groupId` would silently revert on the next catalog refresh. See `test/food_library_state_delete_guard_test.dart` (S-006 / S-007). |
| `getFoodGroupById(String id)` | Retrieves a food group from cache or repository; returns null if not found |
| `createFood(Food food)` | Creates a new food item, persists, and notifies (forces `isCatalog = false`) |
| `updateFood(Food food)` | Updates an existing food and persists changes |
| `archiveFood(String id)` | Archives (soft-deletes) a food by setting `isArchived = true` |
| `removeFood(String id)` | Hard-deletes a food from the library; no-op for unknown ids; no-op for catalog foods; does not throw |
| `isInLibrary(String catalogFoodId)` | Returns `true` iff a non-archived, user-owned library row matches the catalog source by the durable `catalogId` linkage. Falls back to name + reference + macros identity only for legacy rows that pre-date the `catalogId` field. Thin wrapper over [libraryIdFor](#libraryidfor) — does the same lookup, returns a boolean. |
| `libraryIdFor(String catalogFoodId)` | Returns the matching library row's id (or `null`) using the durable `catalogId` linkage first, with a value-based (name + reference + macros) match as a legacy fallback only. UI callers that need to call `removeFood` / `unlogFoodToday` against the matching row use this; `isInLibrary` is the boolean wrapper. |
| `getFoodById(String id)` | Retrieves a food from cache or repository; returns null if not found |
| `searchFoods(String query, {includeArchived})` | Case-insensitive substring search; queries repository, does not cache results |

#### Caching Behavior

- Food groups and foods are cached in-memo, remove) immediately update the cache
- `removeFood()` only calls `notifyListeners()` when the food was in the cache (avoids spurious notifications for cold-cache no-ops)
- `getFoodGroupById()` and `getFoodById()` check cache first, then repository
- `searchFoods()` queries the repository directly without caching

#### Removal Semantics

The library supports two distinct deletion operations:
- `archiveFood(id)` — soft-delete: sets `isArchived = true`, row retained for history and recovery
- `removeFood(id)` — hard-delete: drops the row from storage. Past `ConsumedFood` snapshots are unaffected because they store a frozen copy of every food attribute at log time (`sourceFoodId` may become a dangling reference — this is expected and supported).

#### Catalog Operations (Add-from-Catalog flow)

The catalog is a bundled, read-only collection of common foods that
ships with the app. Catalog rows live in their own repository box and
are never returned by `WorkoutRepository.getFoods()`. The state
caches them in `_catalogFoods` and exposes them through a separate
getter so the Add-from-Catalog tab can re-render without a repository
hit per frame.

| Method | Purpose |
|---|---|
| `loadCatalogFoods({includeArchived})` | Loads the bundled catalog into `_catalogFoods`; idempotent. |
| `catalogFoods` | Unmodifiable list of cached catalog foods (empty until `loadCatalogFoods` resolves). |
| `isLoadingCatalogFoods` | Loading flag for the catalog cache. |
| `addCatalogFoodToLibrary(String catalogFoodId)` | Copies a catalog food into the library via `WorkoutRepository.addCatalogFoodToLibrary`, inserts the new library row into `_foods`, and notifies listeners so the browse card picks it up. The catalog itself is unchanged. |
| `searchCatalogFoods(String query)` | Pure local filter on `_catalogFoods` by case-insensitive substring on `name`; returns an alphabetical list. Empty query returns the full list. No network call. |
| `createCatalogFood(FoodDraft draft)` | Creates a new food in the **catalog** (the global managed library). Persists via `WorkoutRepository.createCatalogFood`, inserts the row into `_catalogFoods`, and notifies listeners. Returns the new id. The new row has `isCatalog = true`; it appears in the **Library** tab on `AddFoodScreen` and can be added to the personal library via the **Add** button on the row. This is the iteration-3 path the **+ New Item** tab uses. |
| `updateCatalogFood(Food existing, FoodDraft draft)` | Updates an existing **catalog** food. Persists via `WorkoutRepository.updateCatalogFood`, updates the in-memory catalog cache, and notifies listeners. Preserves the original `id` and `isCatalog = true`; only `updatedAtMs` advances. Throws `StateError` if `existing.isCatalog` is not `true`; throws if the id is not in the catalog cache. Past `ConsumedFood` snapshots for past days are NOT modified (the snapshot model freezes name, macros, and reference at log time and does not include the image). |

#### Custom-Food (Library) Edit / Create — kept for future use

The `createCustomFood` and `updateCustomFood` API on `FoodLibraryState`
is **kept** for any future code that wants to write to the personal
library directly. The iteration-3 UI redirects the create + edit
affordances to the catalog (above); the personal library still
receives catalog copies via the existing **Add** flow on the
catalog row. No screen currently calls `createCustomFood` /
`updateCustomFood`.

| Method | Purpose |
|---|---|
| `createCustomFood({name, groupId, unitType, referenceAmount, referenceLabel, protein, carbs, fiber, fat, sodium, notes, imagePath})` | Builds a `Food(isCatalog: false, ...)` with a fresh id assigned by the state, persists via the repository, inserts the row into `_foods`, and notifies listeners. Returns the new id. |
| `updateCustomFood({id, name, groupId, unitType, referenceAmount, referenceLabel, protein, carbs, fiber, fat, sodium, notes, imagePath})` | Updates an existing library food. Preserves the original `id`, `isCatalog = false`, and `createdAtMs`; only `updatedAtMs` advances. |

#### Consumed-Food Cache (in `NutritionState`, not `FoodLibraryState`)

Consumed-food logging lives on `NutritionState` (see the
`ConsumedFood State Cache` section of [Data Models](../data_models.md#consumed-food-state-cache-nutritionstate))
because it is day-scoped and powers the calorie ring on the nutrition
page. `FoodLibraryState` owns the library (groups + foods) but does not
own the day-log. The two states are independent: logging a consumed food
does not mutate the library, and editing a library food does not
retroactively change past day-log snapshots (the snapshots are frozen).

#### Current Consumers

- `NutritionScreen` (read-only browse card) — calls `loadFoodGroups()` and `loadFoods()` from `initState` and renders the cached data through `foodsIEatSections` (`lib/core/utils/foods_i_eat_order.dart`), which owns the grouping and the order for this card and for the watch's synced list alike. Each row is a `LogFoodRow` whose checkbox toggles the food in/out of today's log via `NutritionState`. The bottom "Manage Food Library" primary CTA and the `NutritionSummaryCard` were removed; the manage flow is reached via a pencil `IconButton` (key `food_library_manage_pencil`) in the Food Library card header.
- `NutritionScreen` (calorie ring header) — calls `NutritionState.loadConsumedToday()` and `NutritionState.loadWaterForToday()` from `initState` and on return from `NutritionTargetScreen`; renders the `Today` header via `CalorieRingCard`, which reads `nutritionState.nutritionTarget`, `nutritionState.todayConsumedCalories`, and `nutritionState.waterTodayMl` / `.waterTodayGlasses` through a single `ListenableBuilder`. The water tracker's increment / decrement buttons are wired to `nutritionState.incrementWaterForDate(todayMs)` / `.decrementWaterForDate(todayMs)`.
- `NutritionScreen` (Food Library card pencil) — pushes `AddFoodScreen`; the icon does not call any state methods directly, the new screen owns the catalog load and the add-from-catalog / create-custom invocations.
- `AddFoodScreen` (Library tab) — calls `loadCatalogFoods()` from a post-frame callback in `initState` and renders the cached catalog foods alphabetically. Each row's trailing action reflects whether the catalog food is in the user's library (via `libraryIdFor(catalogFoodId)` returning non-null — see [FoodLibraryState `libraryIdFor`](#libraryidfor)). Tapping Add calls `addCatalogFoodToLibrary(food.id)`; tapping the trash button (when the food is in the library) re-resolves the id via `libraryIdFor(food.id)` and calls `unlogFoodToday(libraryId)` (if logged today) then `removeFood(libraryId)`. Both actions stay on the screen — the user can add and remove multiple foods in one visit and only leaves via the system back arrow.
- `AddFoodScreen` (Library tab) — row tap (outside the trailing Add / Remove button) opens `EditFoodScreen` via `EditFoodScreen.push(context, food: catalogFood, foodLibraryState: state)`. `EditFoodScreen` calls `updateCatalogFood(food, draft)` on save. The Add / Remove buttons still go through `addCatalogFoodToLibrary(food.id)` and `removeFood(libraryId)` (with `unlogFoodToday` first if the food is logged today) — the row tap is the iteration-3 entry point to the edit affordance.
- `WatchNutritionLogBridge` — the wrist's half of the same day log: a food quick-logged on the watch is written here through `logConsumedFoodAt`, which is what makes redelivery idempotent. See [Services & Utilities](services_and_utils.md) and `test/watch_nutrition_quick_log_test.dart` (S-002).
- `AddFoodScreen` (+ New Item tab) — calls `createCatalogFood(draft)` from the Save handler. Iteration 3 redirects the create path to the catalog so every new food the user creates is browsable in the Library tab and can be added to the personal library via the Add button on the row. The form is purely local; no state reads until save time. Pops on success; surfaces a `SnackBar` on failure.

---

---

### `NutritionPrimerState`

**File**: `lib/state/nutrition/nutrition_primer_state.dart`
**Depends on**: `WorkoutRepository`

Tracks the once-per-install "primer seen" flag for the Daily Nutrition page primer sheet (see `docs/widget_catalog.md` → `NutritionPrimerSheet`). The primer auto-shows on the first-ever tap of the home nutrition strip and explains the "curate once / check daily / rollup" model in three short blocks. The seen-flag is persisted via `WorkoutRepository.setPreferenceBool` so it survives a full app close + relaunch.

| Field | Type | Purpose |
|-------|------|---------|
| `_seen` | `bool` | `true` once the user has dismissed the auto-shown primer (or the persisted flag is set on cold start). Defaults to `false` (safer than assuming "seen" on a missed hydration). |

| Method | Purpose |
|--------|--------|
| `init()` | `async` — reads `'primer_seen_nutrition'` from repository preferences on startup. Hydration failure falls back to `_seen = false` so the user sees the primer at least once. |
| `shouldShowPrimer` | Getter — returns `!_seen`. The home strip's tap handler consults this to decide whether to show the primer. |
| `hasSeen` | Getter — returns `_seen`. |
| `markSeen()` | Idempotent: sets `_seen = true`, persists via `repository.setPreferenceBool('primer_seen_nutrition', true)`, notifies listeners. The header "?" control on the nutrition page never calls this — it reopens the primer without mutating the seen state. |

Persisted — survives app restart via `WorkoutRepository.getPreferenceBool` / `setPreferenceBool` backed by the Hive `meta` box.

**Important**: the seen-flag is NOT modelled on `HomeState._maintenanceHintSeen` even though the patterns look similar. The maintenance hint is in-memory only; the nutrition primer MUST survive a relaunch, so the wrong-pattern guard test (`S-006` in `docs/plans/nutrition-page-primer-plan.md`) asserts on the persisted value to catch a regression that drops persistence.

---

> **Doc freshness** — Last reconciled against source: 2026-07-26. This page is one part of [State Management & Services](../state_management.md); see that index for the full class list. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree. If you find a claim here that disagrees with `lib/`, `lib/` wins.
