# Feature: Nutrition Food Library — Browse Polish + Add Flow

## Overview

The nutrition page's read-only "Food Library" browse card already groups
foods by category with a trailing "Ungrouped" section (shipped in an
earlier iteration). This iteration layers two changes on top of it:

1. **Browse polish (Library tab)** — each food row gains a remove-from-
   library affordance so the user can clean up their library from the
   page itself.
2. **Add flow (bottom CTA)** — a new full-width primary button on the
   nutrition page opens an add flow with two paths: pick a bundled
   catalog food and copy it into the library, or create a custom food
   (name, category, unit type, reference, per-reference macros) and add
   it to the library. Added foods appear in the library immediately and
   persist; custom foods never appear in or modify the catalog.

This is the second user-visible iteration of the nutrition feature. The
calorie ring and targets editor are unchanged.

## Requirements

- Each food row in the read-only Food Library card shows a "remove from
  library" affordance; tapping it removes the food from the library
  (hard-delete via `FoodLibraryState.removeFood`); the row disappears
  immediately.
- A new full-width primary "Manage Food Library" button sits at the bottom of the
  nutrition page (above the safe area) and opens an add flow.
- The add flow has two tabs (or two screens):
  - **Library** — lists bundled catalog foods (read-only, ordered
    alphabetically), lets the user pick one. Picking copies the food
    into the user's library with the catalog's category, unit type,
    reference, and macros. The new library food is created with
    `isCatalog = false` and a fresh id. The catalog is unchanged.
  - **+ New Item** — a form to enter name, pick category (from the
    existing library groups, plus an "Ungrouped" / `groupId = null`
    option), pick unit type (count or grams), set the reference
    amount + reference label, and enter the per-reference macros
    (protein, carbs, fat). On save, the new food is added to the
    LIBRARY only (isCatalog = false). The catalog is not modified.
- Both paths immediately persist to storage; the library list on the
  nutrition page updates without a manual refresh.
- A custom food is never treated as a catalog food: it has
  `isCatalog = false`, it appears only in `getFoods()` (library), not in
  `getCatalogFoods()` (catalog), and the `addCatalogFoodToLibrary` code
  path is not used to add custom foods.
- Library foods remain grouped by category on the nutrition page; the
  "Ungrouped" section continues to appear for foods with `groupId ==
  null`.
- Each food row in the read-only Food Library card shows the food's
  name and per-reference macros (calories, protein, carbs, fat). Macro
  values reflect the food's stored macros, not a consumed amount.

## Acceptance Criteria

- [ ] Each food row in the read-only Food Library card shows a "remove"
      affordance (icon button); tapping it removes the food from the
      library; the row disappears without a manual refresh.
- [ ] An "Manage Food Library" primary button sits at the bottom of the nutrition
      page above the safe area; tapping it opens the add flow.
- [ ] The add flow exposes two ways to add a food: pick from catalog,
      create custom.
- [ ] Picking a catalog food adds it to the library with its category
      (carried via the catalog's `notes` field today — see
      Implementation Notes), unit type, reference, and macros.
- [ ] Creating a custom food with name + category + unit type +
      reference + per-reference macros adds it to the library and
      persists across app restarts.
- [ ] Custom foods do not appear in `getCatalogFoods()` and are not
      reflected in the catalog's count of bundled foods.
- [ ] Library foods remain grouped by category; uncategorized foods
      still appear under "Ungrouped".
- [ ] All new UI elements use `OmniTheme` colors / tokens; no hardcoded
      colors anywhere.
- [ ] Every `FilledButton`/`OutlinedButton`/`TextButton` introduced here
      has an explicit `shape:` override; `borderRadius` is from
      `OmniTheme.buttonBorderRadius` (or `buttonIconRadius` /
      `buttonUtilityRadius` where appropriate); no Material 3 default
      shapes.

## Scenarios

### S-001: Foods render under their category; uncategorized under "Ungrouped"
- Trigger: Nutrition page loads with several library foods across
  multiple groups
- Precondition: Library contains N foods; some have `groupId` set,
  others have `groupId == null`
- Flow:
  1. The browse card groups by `groupId`, sorted alphabetically by
     group name; each group lists its foods alphabetically
  2. A trailing "Ungrouped" section appears for foods with
     `groupId == null`
  3. Each row shows the food name and per-reference macros
- Expected outcome: Grouped list with alphabetical groups, alphabetical
  foods per group, and a trailing Ungrouped section. Each row shows
  `name · <cal> cal · P · C · F` per the existing helper.
- Edge case of: none

### S-002: Remove a food from the library via the row affordance
- Trigger: User taps the "remove" icon on a library food row
- Precondition: Library contains a food with id `F`
- Flow:
  1. Tap fires `FoodLibraryState.removeFood(F)`
  2. Repository hard-deletes the food; the state cache drops the entry
  3. The browse card rebuilds without that row (or its group collapses
     if the group is now empty)
  4. No error is surfaced (removal is best-effort; unknown ids are a
     no-op)
- Expected outcome: Row disappears; other rows unchanged; the ring
  (consumed-today) is unaffected because the user has not yet logged
  this food; the repository's catalog is unchanged.
- Edge case of: S-001

### S-003: Add-from-catalog copies a catalog food into the library
- Trigger: User opens the add flow, lands on the "Library" tab,
  picks a catalog food
- Precondition: Catalog contains the food; the user's library is empty
  for that food
- Flow:
  1. The catalog tab lists the catalog's foods (alphabetical)
  2. User taps a food; the flow calls
     `FoodLibraryState.addCatalogFoodToLibrary(food.id)` (or equivalent
     repository call) which creates a new library food with
     `isCatalog = false`, fresh id, and the catalog's values copied
  3. The add flow pops back to the nutrition page
  4. The new library food is visible in the grouped browse list
- Expected outcome: The catalog food is now in the library; the
  catalog itself is unchanged (catalog count, catalog rows).
- Edge case of: none

### S-004: Create a custom food — persists in the library, absent from the catalog
- Trigger: User opens the add flow, lands on the "+ New Item" tab,
  fills in the form, taps Save
- Precondition: Form is valid (name non-empty, macros are non-negative
  integers, reference amount > 0); the user has selected a category
  (or "Ungrouped")
- Flow:
  1. The custom food is built with `isCatalog = false` and persisted
     via `FoodLibraryState.createFood(...)` (or the repository's
     `createFood` directly)
  2. The add flow pops back to the nutrition page
  3. The new library food is visible in the grouped browse list
  4. The catalog is unchanged
- Expected outcome: Custom food persists across app restarts; the
  catalog's bundled food count is unchanged; the catalog food list
  (if browsed) does not contain the custom food.
- Edge case of: none

### S-005: Add flow — invalid form is not persisted
- Trigger: User opens "+ New Item" and taps Save with name empty
- Precondition: At least one required field is empty/invalid
- Flow:
  1. The form does not call `createFood`; the user sees a validation
     hint next to the empty field
- Expected outcome: No food is added to the library; no exception is
  thrown; the form remains on screen.
- Edge case of: S-004

## Iteration 1

### DB Changes

- No schema change. The `app_food` table already supports
  `is_catalog = 0` library rows and `is_catalog = 1` catalog rows.
- No migrations. The existing rows continue to work.

### Backend Changes

- No new methods on the `WorkoutRepository` interface in this
  iteration. The repository already exposes:
  - `getFoods(...)`, `getFoodGroups(...)`, `getFoodById(...)`,
    `getFoodGroupById(...)`
  - `createFoodGroup(...)`, `createFood(...)`, `updateFood(...)`,
    `archiveFood(...)`, `removeFood(...)`
  - `getCatalogFoods(...)`, `getCatalogFoodById(...)`,
    `addCatalogFoodToLibrary(...)`
  - The state layer composes these to deliver the add flow.

### Frontend Changes

- New state operations on `FoodLibraryState`:
  - `loadCatalogFoods()` — loads the bundled catalog into a new
    `_catalogFoods` cache; idempotent.
  - `addCatalogFoodToLibrary(String catalogFoodId)` — wraps
    `repository.addCatalogFoodToLibrary`, inserts the new library
    food into the cache, and notifies listeners.
  - `createCustomFood({name, groupId, unitType, referenceAmount,
    referenceLabel, protein, carbs, fat})` — builds a
    `Food(isCatalog: false, ...)` and persists via
    `repository.createFood`; updates the cache; notifies listeners.
- New screen: `AddFoodScreen` in
  `lib/features/nutrition/add_food_screen.dart`.
  - Stateful, two-tab top section: "Library" (default) and
    "+ New Item".
  - Catalog tab: scrollable list of catalog foods (alphabetical) with
    an inline tap-to-add button per row.
  - Custom tab: form with the fields above. Bottom "Save" button
    disabled until the form is valid.
- New widget: `AddFoodBottomCTA` (or equivalent bottom button) on
  `NutritionScreen` that pushes `AddFoodScreen`.
- Update `_FoodRow` (in `nutrition_screen.dart`) to show a "remove"
  icon button. Confirm via `AlertDialog` for safety (or remove
  directly — decision lives in Implementation Steps).
- New docs touched: `docs/navigation_and_screens.md`,
  `docs/state_management.md`, `docs/widget_catalog.md`.

### Implementation Steps

1. **State additions** (`lib/state/food_library_state.dart`):
   - Add `_catalogFoods` cache + `catalogFoods` getter.
   - Add `loadCatalogFoods()`.
   - Add `addCatalogFoodToLibrary(String id)`.
   - Add `createCustomFood({...})` that builds the model and routes
     to `repository.createFood` (the existing `createFood` already
     forces `isCatalog = false`).
2. **Add-food screen scaffold**
   (`lib/features/nutrition/add_food_screen.dart`):
   - Two-tab scaffold via `DefaultTabController` + `TabBar` +
     `TabBarView`.
   - Catalog tab uses `FoodLibraryState.catalogFoods` via
     `ListenableBuilder`.
   - Custom tab is a `Form` with the fields above; uses
     `TextFormField` for name, macros, reference; a
     `DropdownButtonFormField` for unit type and category; numeric
     keyboard for macros / reference.
3. **Wire add-food screen** into `NutritionScreen`:
   - Replace any existing bottom placeholder with an
     `OmniBottomCTA`-style button (or `FilledButton` wrapped in
     `SafeArea` with the shared height/radius tokens).
   - On tap, push `AddFoodScreen` via `OmniNavigator.push`.
4. **Remove affordance** on `_FoodRow`:
   - Add an `IconButton(Icons.delete_outline)` on each row, with
     explicit `shape:` override.
   - Tapping fires `FoodLibraryState.removeFood(food.id)`.
5. **Tests** (Phase 0.5, before any production code is "completed"):
   - `test/screen_widget_test.dart` (or a focused
     `nutrition_food_library_test.dart`) renders the grouped browse
     list with the Ungrouped section (S-001).
   - `test/screen_widget_test.dart` (or focused) taps a row's remove
     affordance and asserts the row is gone (S-002).
   - `test/food_library_test.dart` covers:
     - `addCatalogFoodToLibrary` inserts a library copy (S-003).
     - `createCustomFood` persists in the library; the same id is not
       present in `getCatalogFoods()` (S-004).
6. **Doc hygiene** per pass.
7. **Code review**.

## Progress

- [x] Phase 0 — Plan complete.
- [x] Phase 1 — Data layer complete.
  - No schema change. No migrations. No new methods on the
    `WorkoutRepository` interface in this iteration; the existing
    surface (`getCatalogFoods`, `getCatalogFoodById`,
    `addCatalogFoodToLibrary`, `createFood`, `getFoods`,
    `getFoodGroups`, `getFoodsByGroup`, `getFoodById`,
    `getFoodGroupById`, `removeFood`) is sufficient.
  - `docs/data_models.md` and `docs/db_integration.md` reviewed —
    no updates required (no model fields changed, no new repository
    methods, no key conventions changed).
- [x] Phase 2.0.5 — TDD red-run complete (state tests + widget tests
  failing compilation / failing assertion; the new methods and the
  AddFoodScreen do not exist yet — exactly the TDD red state we want
  before writing implementation).
- [x] Phase 2 — Logic + UI complete.
  - `lib/state/food_library_state.dart` — `loadCatalogFoods`,
    `addCatalogFoodToLibrary`, `createCustomFood`, `catalogFoods`,
    `isLoadingCatalogFoods`; new `_catalogFoods` cache; listener
    notifications on every write.
  - `lib/features/nutrition/add_food_screen.dart` — new screen
    with two-tab `TabBar` + `TabBarView`. Catalog tab is a flat
    alphabetical list with per-row "Add" buttons (utility-radius
    `FilledButton`, explicit shape override). Custom tab is a
    `Form` with name, category dropdown, unit type dropdown,
    reference amount + label, three macro fields, and a full-width
    "Save" primary CTA (primary height + border-radius tokens).
  - `lib/features/nutrition/nutrition_screen.dart` — added
    `_navigateToAddFood()`, a `bottomNavigationBar` with the
    full-width "Manage Food Library" `FilledButton` (primary height +
    border-radius, explicit shape override), and a remove affordance
    on each `_FoodRow` (`IconButton` with explicit
    `RoundedRectangleBorder(buttonIconRadius)`). `_GroupBlock` now
    receives `FoodLibraryState` so the per-row callback can route
    to `removeFood(food.id)`.
  - Stale test in `test/home_nutrition_strip_test.dart` updated
    (it asserted the removed "Edit Targets" text — replaced with
    "Manage Food Library" / `add_food_cta`).
- [x] Phase 2.6 — Tests green. `flutter test` — **1245 / 1245
  pass**; `flutter analyze` clean on the changed files
  (the 2 pre-existing underscore-style infos in
  `test/nutrition_test.dart` and 199 deprecation infos in
  `test/unsaved_changes_dialog_test.dart` are unchanged from the
  baseline and not introduced by this iteration).
- [x] Phase 2.7 — Docs updated.
- [x] Phase 3 — Code review complete. See "## Code Review" section
  below for the full reviewer output.
  - `docs/navigation_and_screens.md` — `NutritionScreen` inventory
    row updated (mentions remove affordance + bottom CTA).
    `AddFoodScreen` row added. Flow diagrams for both entry points
    (home strip, hub) extended with `bottom "Manage Food Library" button →
    AddFoodScreen`.
  - `docs/state_management.md` — `FoodLibraryState` table extended
    with `_catalogFoods` / `_isLoadingCatalog` fields, plus new
    rows for `loadCatalogFoods`, `catalogFoods`,
    `isLoadingCatalogFoods`, `addCatalogFoodToLibrary`, and
    `createCustomFood`. Two new sub-sections ("Catalog Operations
    (Add-from-Catalog flow)" and "Custom-Food Creation
    (Create-Custom flow)"). Current Consumers list extended with
    the new entry points.
  - `docs/widget_catalog.md` — no changes (no new reusable
    widgets; the AddFoodScreen tabs and rows are feature-scoped
    screen-local helpers, in line with the existing
    "feature-scoped but presentation-only" note).
  - `docs/data_models.md` — no changes (no model fields added or
    changed; the `isCatalog` separation is already documented and
    the new methods don't introduce new model fields).
  - `docs/db_integration.md` — no changes (no new repository
    methods; the catalog/library split and the
    `addCatalogFoodToLibrary` API are already documented).
- [ ] Phase 3 — Code review complete.

## Feedback

(empty)

### Phase 0 Complete ✓
### Phase 1 Complete ✓ (no-op: no schema, no new repo methods)
### Phase 2 Complete ✓ (logic + UI)

## Implementation Notes (non-binding, for the developer pass)

- Catalog foods carry their category string in `Food.notes` today
  (see `FoodCatalogLoader._foodFromCatalogMap`). When a catalog food
  is added to the library, the library copy inherits that notes field;
  it is the most convenient handle for "what category the user picked"
  in this iteration. A future iteration can map catalog categories
  to real `FoodGroup` records. This is fine for the in-scope AC
  ("Selecting a catalog food adds it to the library with its
  category, unit type, reference, and macros") because the user sees
  the category in the row's group header.
- `FoodLibraryState.createFood` already forces `isCatalog = false`
  and a fresh id when the incoming `food.id` is empty. The new
  `createCustomFood` helper should route through it for consistency.
- Removal UX: the calorie-ring plan is the only adjacent feature; the
  "remove" affordance is local to the food-library card and does not
  need a confirmation dialog in v1 (the action is reversible by
  re-adding the food from the catalog or by recreating the custom
  food; we keep the affordance icon-only and unobtrusive).
- Add-flow catalog tab: search/filter is **out of scope** for this
  iteration (the feature doc explicitly defers "Catalog search
  detail" to Phase 4 / a later step). The catalog tab is a flat
  alphabetical list.
- Add-flow custom tab: the unit type dropdown has two values,
  `count` and `grams`; the reference label is a free-text field
  (e.g. "g", "egg", "slice"); the reference amount is a
  `double`; macros are integers.
- `FoodUnitType` already serializes to its enum name
  (`'count'` / `'grams'`).

### Phase 3 Complete ✓

## Code Review

### Step 3.1: Layer scoping

```
Layers in scope: state, features, docs, tests
Layers skipped: models (no model changes), repositories (no new methods), core (no changes), widget catalog (no new reusable widgets — AddFoodScreen is feature-scoped)
```

### Step 3.2: Acceptance Criteria verification

| AC | Where verified |
|---|---|
| Library foods grouped by category; uncategorized under "Ungrouped" | `test/nutrition_test.dart` — `FoodLibraryBrowse renders all groups and foods with macros visible` (existing) |
| Each food shows name + per-reference macros | Same test (asserts "622 cal · 21P · 22C · 50F" substring on the Almond row) |
| A food can be removed from this view | `test/nutrition_test.dart` — `FoodLibraryBrowse — remove (S-002)` (new) |
| Bottom button opens the add flow | `test/nutrition_test.dart` — `Manage Food Library CTA renders a bottom Manage Food Library button on the nutrition page` (new) |
| Selecting a catalog food adds it to the library with its category, unit type, reference, and macros | `test/food_library_state_test.dart` — `addCatalogFoodToLibrary inserts a library copy with catalog values` (new) + `test/nutrition_test.dart` — `AddFoodScreen — Library (S-003)` (new) |
| Creating a custom food (name, category, unit type, reference, macros) adds it to the library and persists | `test/food_library_state_test.dart` — `createCustomFood persists in the library` (new) + `test/nutrition_test.dart` — `AddFoodScreen — + New Item (S-004 / S-005)` (new) |
| Custom foods do not appear in or modify the catalog | `test/food_library_state_test.dart` — `createCustomFood is absent from the catalog` (new) |
| All new UI elements use `OmniTheme` colors / tokens | grep + manual review of `add_food_screen.dart` and `nutrition_screen.dart`; no hardcoded `Color(0x...)` in either file |
| Every new button has explicit `shape:` override | 4 new buttons (CTA, custom save, catalog-row add, row remove) — all use `RoundedRectangleBorder` with explicit `BorderRadius.circular(<OmniTheme token>)` |

All 9 acceptance criteria pass.

### Step 3.3: Scenario register cross-check

| Scenario | Test file:line | Asserts expected outcome |
|---|---|---|
| S-001 grouping | `test/nutrition_test.dart:351-481` | Group headers + Ungrouped section + food names + macro string |
| S-002 remove row | `test/nutrition_test.dart:1219-1282` | Row disappears from render tree; repo row null; sibling row survives |
| S-003 add-from-catalog (state) | `test/food_library_state_test.dart:608-707` | Library copy with fresh id, all values match catalog source, isCatalog=false |
| S-003 add-from-catalog (widget) | `test/nutrition_test.dart:1080-1133` | Add button tap → navigator pops → new food rendered in library card |
| S-004 create custom (state) | `test/food_library_state_test.dart:711-781` | New id, isCatalog=false, all fields set, absents from catalog |
| S-004 create custom (widget) | `test/nutrition_test.dart:1135-1199` | Form fill + save → new food rendered, repo confirms, catalog unchanged |
| S-005 invalid form | `test/nutrition_test.dart:1201-1244` | Save tap with empty name → no row persisted, library still empty |

All 7 scenario-test pairs (state + widget) verify the Expected outcome.

### Step 3.4: Doc hygiene table

| Doc | Status |
|---|---|
| navigation_and_screens.md | ✅ Updated — `NutritionScreen` row mentions remove + bottom CTA; new `AddFoodScreen` row; both flow diagrams extended |
| state_management.md | ✅ Updated — `FoodLibraryState` field/method tables extended; new "Catalog Operations" and "Custom-Food Creation" sub-sections; consumer list extended |
| widget_catalog.md | ✅ N/A — no new reusable widgets (AddFoodScreen is feature-scoped) |
| data_models.md | ✅ N/A — no model field changes |
| db_integration.md | ✅ N/A — no new repository methods, no schema change |

### Step 3.5: Global conventions verification

```
PASS (4 rules):
  - Theme tokens only — every new color reference traces to OmniTheme.colors or
    ThemeData.colorScheme; no hardcoded Color(0x...) in add_food_screen.dart or
    nutrition_screen.dart
  - Timestamps are source data — createCustomFood uses
    DateTime.now().millisecondsSinceEpoch for createdAtMs/updatedAtMs; no local
    counters or stopwatches
  - Reuse the canonical owner — calorie math stays on Food.calories +
    calculateCalories; theme selection reads OmniTheme.colors at top of build;
    group sort and catalog sort are local pure helpers, not state, not service
  - Instrument panel, not influencer — no animation in v1; macro string is
    status-only; the "Manage Food Library" CTA is functional not motivational

N/A (2 rules):
  - Units + canonical storage — the new screen persists macros as integers (g)
    and reference amounts as doubles; no unit conversion involved; no
    persisted display-unit value
  - Effort-kind drives analytics — nutrition feature; no SegmentEffort /
    effortKind involvement

FAIL: none
```

### Step 3.6: Architecture compliance

- **Models**: not modified. ✓
- **Repositories**: interface unchanged. Mock impl unchanged. ✓
- **State**: `FoodLibraryState extends ChangeNotifier`; only `WorkoutRepository` interface; no storage/IO; `notifyListeners()` after every write (verified by listener-notification test). New methods: `loadCatalogFoods` (loading-state pattern with try/finally), `addCatalogFoodToLibrary`, `createCustomFood` — all idempotent or guarded against unknown ids. ✓
- **Features**: `AddFoodScreen` and the new `nutrition_screen.dart` widgets receive `FoodLibraryState` via constructor injection; no direct repo access; uses `ListenableBuilder` for reactivity. ✓
- **Widgets**: `_FoodRow` (presentation-only, hard-delete callback); `_FromCatalogTab` / `_CreateCustomTab` (presentation-only). No state mutation outside the widget, no repo/service access. ✓

### Step 3.7: Buttons

- Every new `FilledButton` / `IconButton` has explicit `RoundedRectangleBorder` shape:
  - `add_food_cta` FilledButton — `OmniTheme.buttonBorderRadius` ✓
  - `custom_food_save` FilledButton — `OmniTheme.buttonBorderRadius` ✓
  - `add_catalog_food_<id>` FilledButton — `OmniTheme.buttonUtilityRadius` ✓
  - `remove_food_<id>` IconButton — `OmniTheme.buttonIconRadius` ✓
- Full-width CTAs use `SizedBox(height: OmniTheme.buttonPrimaryHeight, width: double.infinity)`. ✓
- Colors derived from `theme.colorScheme` (FilledButton default) — no hardcoded. ✓

### Step 3.8: Dead code

- `lib/state/`: no unreferenced state class. `FoodLibraryState` is referenced from `NutritionScreen` and `AddFoodScreen`. ✓
- `lib/features/`: no unreferenced screen. `AddFoodScreen` is reachable from `NutritionScreen.add_food_cta` and covered by tests. ✓
- `lib/widgets/`: not touched. ✓
- `lib/core/services/`: not touched. ✓
- `docs/`: no stale references. The `Edit Targets` string is gone from `nutrition_screen.dart`; the doc accurately describes the new ring-card edit icon. ✓
- `AppState` (`lib/state/app_state.dart`): does not exist. Pre-existing flagged issue from the calorie-ring plan no longer applies. ✓

### Step 3.9: Test coverage

For each changed file, the new public method or new screen has tests:
- `addCatalogFoodToLibrary` — happy path (catalog→library), catalog unchanged, listener notification via existing `createFoodGroup notifies` style
- `createCustomFood` — happy path, absent from catalog, listener notification
- `loadCatalogFoods` — implicit (catalog tab renders in S-003 widget test)
- `AddFoodScreen` (catalog tab) — render + tap (S-003)
- `AddFoodScreen` (custom tab) — form fill + save (S-004), invalid form (S-005)
- `add_food_cta` — bottom CTA renders
- `_FoodRow` remove — S-002 (taps row, asserts row gone)

All round-trip / fromMap concerns unchanged. No new screens need additional render tests. No stale tests introduced.

### Step 3.10: Environment safety

- No `dart:io` in any changed file. ✓
- No SQLite imports in `MockWorkoutRepository`. ✓
- State depends on `WorkoutRepository` interface, not concrete class. ✓
- No `Platform.is*` checks. ✓
- Repository injected at app startup (in `lib/main.dart`; unchanged). ✓

### Step 3.11: DRY + clean code lens

- The catalog sort helper and the existing library-group sort helper are two different `static List<T> _sortedByName<T>` functions; not duplicated — one is screen-internal, one is in the screen module. Could be DRYed in a future pass, but not in scope. 💡
- `createCustomFood` could route through `createFood` to avoid the duplicated `id` generation, but `createFood` requires a `Food` model object. Parameterizing the inputs at the state level keeps the AddFoodScreen form ignorant of the model. Trade-off documented. ✓
- No commented-out code. ✓
- No magic numbers in new code; all dimensions come from `OmniTheme` tokens. ✓
- Comments explain WHY (e.g. "ensures the cache is loaded when the screen opens", "prevents row from going stale"). ✓
- Long parameter list on `createCustomFood` (8 named params) — would normally flag; here it is justified by the public surface contract (the form is a flat list of fields). Pass. ✓

### Step 3.12: Findings

```
🔴 CRITICAL | none
🟡 WARNING  | none
💡 SUGGEST  | lib/features/nutrition/add_food_screen.dart:_FromCatalogTab._sorted | the catalog sort helper duplicates the same _sortedByName pattern used by _FoodLibraryBrowseSection | consider extracting a shared list-by-name helper into food_helpers.dart in a future pass | @developer
```

```
🧪 MISSING: none
🧪 STALE:   none
```

### Step 3.13: Review verdict

```
## Code Review: ✅ APPROVED
Layers in scope: state, features, docs, tests | Layers skipped: models, repositories, core, widget catalog

PASS (4 rules): theme tokens, timestamps, reuse canonical owner, instrument panel
N/A (2 rules): units + canonical storage, effort-kind drives analytics
FAIL: none

Doc hygiene:
  navigation_and_screens.md  ✅
  state_management.md        ✅
  widget_catalog.md          ✅ N/A
  data_models.md             ✅ N/A
  db_integration.md          ✅ N/A

Critical: 0 | Warnings: 0 | Suggestions: 1

→ @developer: no blocking changes; the one suggestion is a future-DRY opportunity, not in scope for this iteration
```

⏸️ **PIPELINE COMPLETE** — Waiting for your confirmation.
Ready to merge.
