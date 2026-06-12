# Feature: Manage Food Library — In-Place Add/Remove Toggle

## Overview

Rework the **Manage Food Library** flow so the user can add and remove foods to/from their personal library in a single visit, with a single tap, and an obvious visual state on each row. The "Manage Food Library" bottom CTA on the Nutrition screen is removed; entry is via an edit-pencil icon in the top-right of the Food Library card. The Daily Targets card is removed from the Nutrition screen. The library card itself becomes the canonical place to log/inspect/unlog consumed foods (no behavior change there).

This is a TRIVIAL-leaning change. The data layer (single-add enforcement, multiple-adds-per-visit, in-place remove, today's-log cleanup, frozen-past-snapshots) is already in place from prior iterations. The change is **purely presentation + state wiring**, with a small new state method to mirror the in-library check.

## Requirements

1. **Single-add enforcement** — the same catalog food cannot be added to the library twice. The Add button on an already-added row renders as the red Remove state (see #3); tapping it removes the food instead of re-adding.
2. **Multi-add per visit** — after tapping Add, the Manage Food Library screen **stays open** and the row's button switches to its Remove state. The user can keep adding/removing other rows. There is **no auto-pop**.
3. **Visual state** — each row's trailing action reflects whether the catalog food is already in the user's library:
   - **Not in library** → `FilledButton` with text "Add" using `theme.colorScheme.primary` background, `onPrimary` foreground.
   - **In library** → `FilledButton.icon` with `Icons.delete_outline` (white) and text "Remove", background `theme.colorScheme.error`, foreground `theme.colorScheme.onError`.
   - The two states occupy the same `SizedBox` width to prevent the row from reflowing when the state flips.
4. **Custom-food tab unaffected** — Tab 2 (+ New Item) continues to pop back to the nutrition page on save (one food at a time, single-shot). The "in-place toggle" pattern is catalog-specific.
5. **Today's log cleanup on remove** — if a food being removed is currently in today's consumed log (`NutritionState.isFoodLoggedToday(food.id) == true`), the remove also calls `NutritionState.unlogFoodToday(food.id)`. Past day-log snapshots are untouched (the `ConsumedFood` snapshot is frozen, so this is the correct semantic per the iteration 2 design).
6. **Entry point change on Nutrition screen** — the bottom "Manage Food Library" `FilledButton` (and its `bottomNavigationBar` wrapper) is removed. An `IconButton(icon: Icons.edit)` is added to the top-right of the "Food Library" `Card` header. The icon opens the same `AddFoodScreen`. A `Semantics(label: 'Manage food library')` label is applied for accessibility.
7. **Daily Targets card removed** — `NutritionSummaryCard` is no longer rendered on `NutritionScreen`. The Calorie Ring card already shows the consumed-vs-target read; the targets-summary card is now redundant. The `nutrition_target_screen.dart` route and `NutritionState` are unaffected (the summary is gone from the screen only, not from state).
8. **Navigation** — on `AddFoodScreen` `AppBar`, the existing default back button (provided by `Scaffold`) is the close affordance. The user simply taps the back arrow to return to the nutrition page; the library card reflects the new state via `FoodLibraryState.notifyListeners` from each add/remove. No new "Done" / "Close" button is added — the back button is enough.

## Scenarios

### S-001: Add a food from the catalog
- Trigger: User opens Manage Food Library → Library tab. Taps "Add" on a row that is not in the library.
- Precondition: Catalog has 1 food (`Chicken Breast`, `catalog-chicken-1`) not in the user's library.
- Flow: `_CatalogRow._onAdd` → `foodLibraryState.addCatalogFoodToLibrary(catalogId)`. Cache updates, listeners notify. The `ListenableBuilder` in `_FromCatalogTab` rebuilds the row with the in-library state.
- Expected outcome: The food appears in the library (cache + repo). The row's button now reads "Remove" with a red background and trash icon. The screen does **not** pop. The user can tap another row.
- Edge case of: none

### S-002: Add a second food on the same visit
- Trigger: After S-001, the user taps "Add" on a second row.
- Precondition: S-001 completed; first food is in the library; second food is not.
- Flow: Same as S-001.
- Expected outcome: Second food is added. Its row shows the red Remove state. First row remains in the Remove state. Screen still does not pop.
- Edge case of: S-001

### S-003: Remove a food added earlier in the same visit
- Trigger: User taps the red "Remove" button on a row that they just added.
- Precondition: Food is in the library; not in today's log.
- Flow: `_CatalogRow._onRemove` → `foodLibraryState.removeFood(libraryFoodId)`. Cache updates, listeners notify. The `ListenableBuilder` rebuilds the row to the Add state.
- Expected outcome: Food is removed from cache + repo. Row reverts to "Add" state with primary background. Screen stays open.
- Edge case of: S-001

### S-004: Remove a food that is logged today (unlogs too)
- Trigger: User taps the red "Remove" button on a row whose library food is currently in today's `consumedToday` (i.e. the user has ticked its checkbox on the nutrition page).
- Precondition: Food is in the library **and** `nutritionState.isFoodLoggedToday(food.id) == true`.
- Flow: `_CatalogRow._onRemove` → `nutritionState.unlogFoodToday(food.id)` → `foodLibraryState.removeFood(libraryFoodId)`. The nutrition state's `consumedToday` cache updates and the food's checkbox on the nutrition page will uncheck on the next `notifyListeners`.
- Expected outcome: Food is removed from the library. The food's `ConsumedFood` entry for today is deleted. Past day-log snapshots (any `ConsumedFood` with `dateMs < today's midnight`) are byte-identical (they are frozen at log time, never touched by `unlogFoodToday` or `removeFood`). Row reverts to Add state.
- Edge case of: S-003

### S-005: Catalog re-add is silently a no-op (defensive)
- Trigger: A row's catalog food's library id is somehow already present (shouldn't happen because `_CatalogRow` derives state from `foodLibraryState.foods.any((f) => f.id == _libraryIdFor(food.id))`, but the spec calls this out).
- Flow: The Add button is **not rendered** in this case (the row is in Remove state from the start). If it were somehow tapped, the state method `addCatalogFoodToLibrary` is still idempotent at the repository level (it always creates a fresh library row keyed by a new id). Per requirement #1, the UI must prevent the double-add visually.
- Expected outcome: There is no double-add row in the library; the Add button is never visible for an already-added catalog food.
- Edge case of: S-001

### S-006: Back arrow returns to the nutrition page
- Trigger: User taps the system / `AppBar` back button on `AddFoodScreen`.
- Flow: `Navigator.pop()`. The nutrition page's `ListenableBuilder` (already wired) picks up the `FoodLibraryState.notifyListeners` from the prior add/remove and re-renders the Food Library card.
- Expected outcome: The nutrition page shows the updated library without a manual refresh. No additional logic in `NutritionScreen._navigateToAddFood` `.then(...)` is needed.
- Edge case of: S-001

### S-007: Open the Manage Food Library flow from the new pencil icon
- Trigger: User taps the edit pencil icon in the top-right of the Food Library card.
- Flow: `_navigateToAddFood` (renamed to be pencil-driven; same body) → `OmniNavigator.push` → `AddFoodScreen`.
- Expected outcome: The AddFoodScreen opens identically to the old bottom-CTA flow.
- Edge case of: none

### S-008: Daily Targets card is no longer on the nutrition screen
- Trigger: User opens the nutrition screen.
- Flow: `NutritionScreen.build` no longer renders `NutritionSummaryCard`. The `nutrition_target_screen.dart` route still works (entry from the Calorie Ring's edit-targets icon).
- Expected outcome: The nutrition page renders Calorie Ring card + Food Library card. No "Daily Targets" card.
- Edge case of: none

## Iteration 1

### DB Changes
None. `addCatalogFoodToLibrary`, `removeFood`, `unlogFoodToday` are all existing methods on the existing repository and state layers. The `ConsumedFood` snapshot guarantee from iteration 2 already covers S-004's "past logs untouched" requirement.

### Backend Changes
1. [ ] **`FoodLibraryState.isInLibrary(String catalogFoodId)`** — new public predicate in [food_library_state.dart](lib/state/food_library_state.dart):
   - Returns `true` iff any cached `Food` has a `name` and `referenceAmount` / `referenceLabel` / `unitType` / `macros` matching the catalog source **and** is not archived. (Catalog foods are matched by name + reference + macros because `addCatalogFoodToLibrary` clones the row with a fresh id; there is no `catalogFoodId` foreign key today.)
   - Implementation approach (decision: keep it simple and robust):
     - Look up the catalog food in `_catalogFoods[catalogFoodId]`. If absent, return `false`.
     - For each `_foods` entry with `isCatalog == false` and `isArchived == false`, compare (case-insensitive `name` + `referenceAmount` + `referenceLabel` + `unitType` + `protein` + `carbs` + `fat` + `fiber` + `sodium`). If any entry matches, return `true`.
     - Rationale: this is the same identity the user perceives ("I already added this Chicken Breast"). It is O(n) over the user's library but libraries are small (tens to low hundreds of foods). No new index or persistence is required.
   - If the catalog cache is cold (never loaded), this returns `false` and the row shows the Add state — which is fine because `addCatalogFoodToLibrary` is itself idempotent (creates a new library row), and the user can dedupe manually if it ever shows up twice. This is a deliberate tradeoff: a quick O(n) scan is preferred over eagerly loading the catalog just to support a UI predicate.
2. [ ] **`FoodLibraryState.removeFood` doc** — keep as-is; it is already idempotent and non-throwing (from iteration 2).

### Frontend Changes
1. [ ] **Add a small helper** `_libraryIdFor(Food catalogFood, FoodLibraryState)` to [add_food_screen.dart](lib/features/nutrition/add_food_screen.dart) (top-level or in a private file-level function) that scans `foodLibraryState.foods` for the matching library row and returns its id, or `null` if not present. Uses the same identity rule as `FoodLibraryState.isInLibrary` (name + reference + macros). Co-locate the helper next to `_CatalogRow` for readability; the state method is the public contract, the row helper is its UI mirror.
2. [ ] **Rewrite `_CatalogRow`** in [add_food_screen.dart](lib/features/nutrition/add_food_screen.dart):
   - Hold the current "in library" / "library id" snapshot in the row state (so a tap does not race the rebuild). Use a `StatefulWidget` (`_CatalogRowState`) with `_isInLibrary` and `_libraryId` as instance fields, updated in `didChangeDependencies` (via the `ListenableBuilder`) and re-checked on each tap.
   - Trailing widget:
     - Not in library → `FilledButton(key: Key('add_catalog_food_${food.id}'), onPressed: _onAdd, child: Text('Add'))` with `styleFrom(backgroundColor: theme.colorScheme.primary, foregroundColor: theme.colorScheme.onPrimary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(OmniTheme.buttonUtilityRadius)))`.
     - In library → `FilledButton.icon(key: Key('remove_catalog_food_${food.id}'), onPressed: _onRemove, icon: Icon(Icons.delete_outline, color: theme.colorScheme.onError), label: Text('Remove'), style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error, foregroundColor: theme.colorScheme.onError, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(OmniTheme.buttonUtilityRadius))))`.
   - **Fixed trailing width** — wrap the trailing in a `SizedBox(width: 110)` (or measure once) so the row's text column does not reflow when the button label changes from "Add" to "Remove". Note: "Add" is 3 chars, "Remove" is 6 — without a fixed width the row shifts noticeably.
   - `_onAdd`: `await foodLibraryState.addCatalogFoodToLibrary(food.id)`. Catch → `ScaffoldMessenger.showSnackBar(...)`. On success → no pop; the `ListenableBuilder` (wrapping the whole `_FromCatalogTab.build`) picks up the new state and re-renders this row in Remove mode.
   - `_onRemove`: `final libraryId = _libraryId; if (libraryId == null) return; if (nutritionState.isFoodLoggedToday(libraryId)) { await nutritionState.unlogFoodToday(libraryId); } await foodLibraryState.removeFood(libraryId);`. Catch → SnackBar. No pop.
   - The `_CatalogRow` constructor needs `nutritionState` in addition to `foodLibraryState` (it must call `unlogFoodToday`). Update `_FromCatalogTab` to forward `nutritionState` (it lives in `app.dart` / `home_screen.dart`; thread it through the same way it is threaded into `LogFoodRow`).
3. [ ] **Pass `NutritionState` into `AddFoodScreen`** in [add_food_screen.dart](lib/features/nutrition/add_food_screen.dart) and [nutrition_screen.dart](lib/features/nutrition/nutrition_screen.dart):
   - `AddFoodScreen` adds a `final NutritionState nutritionState;` parameter.
   - `_FromCatalogTab` and `_CatalogRow` receive it.
   - `NutritionScreen._navigateToAddFood` passes `widget.nutritionState` into `AddFoodScreen`.
   - `HomeScreen` (and any test that constructs `AddFoodScreen` directly) forwards `nutritionState`.
4. [ ] **Rework `_FromCatalogTab`** so the `ListenableBuilder` listens to **both** `foodLibraryState` and `nutritionState` (use a small `Listenable.merge([foodLibraryState, nutritionState])`). This ensures the row's in-library state recomputes immediately after `unlogFoodToday` fires (the remove flow on a logged food). Rebuild is cheap; both are `ChangeNotifier`s.
5. [ ] **Remove the bottom CTA from `NutritionScreen`** in [nutrition_screen.dart](lib/features/nutrition/nutrition_screen.dart):
   - Delete the `bottomNavigationBar:` block and the `_navigateToAddFood` method's `SafeArea`/`Padding`/`SizedBox`/`FilledButton` chain.
   - Rename `_navigateToAddFood` to `_openManageLibrary` (clearer after the rename) — body is the same `OmniNavigator.push` to `AddFoodScreen`.
6. [ ] **Add a pencil icon to the Food Library card header** in [nutrition_screen.dart](lib/features/nutrition/nutrition_screen.dart):
   - Replace the current `Text('Food Library', style: titleLarge)` inside the `Card` with a `Row` containing the title (flex 1) and an `IconButton(icon: Icon(Icons.edit, color: theme.colorScheme.primary), tooltip: 'Manage food library', onPressed: _openManageLibrary)`.
   - Key on the icon: `Key('food_library_manage_pencil')` for testability.
7. [ ] **Remove the Daily Targets card from `NutritionScreen`** in [nutrition_screen.dart](lib/features/nutrition/nutrition_screen.dart):
   - Remove the `NutritionSummaryCard(...)` widget and its `SizedBox(height: 16)` spacer.
   - Remove the import of `widgets/nutrition_summary_card.dart`.
   - `NutritionTargetScreen` route is unaffected (still reachable from the Calorie Ring's edit-targets icon).
   - `nutrition_target_screen.dart` is **not** deleted; it is still a navigable destination.

### Implementation Steps (Developer)

1. Add `FoodLibraryState.isInLibrary(String catalogFoodId)` and its private matcher helper.
2. Add `_libraryIdFor(...)` helper to `add_food_screen.dart`.
3. Rewrite `_CatalogRow` as `StatefulWidget` with Add/Remove toggle, fixed trailing width, and the remove-then-maybe-unlog flow.
4. Wire `NutritionState` through `AddFoodScreen` → `_FromCatalogTab` → `_CatalogRow`.
5. Update `_FromCatalogTab`'s `ListenableBuilder` to listen to both `foodLibraryState` and `nutritionState`.
6. In `nutrition_screen.dart`: remove `bottomNavigationBar`, replace the card header with a `Row` containing the pencil `IconButton`, and delete the `NutritionSummaryCard` import + render.
7. Update `_navigateToAddFood` → `_openManageLibrary` (cosmetic rename) in `nutrition_screen.dart`.
8. Update all test files that construct `AddFoodScreen` / `HomeScreen` / `NutritionScreen` with the new `nutritionState` parameter (see "Files Affected" — 4-5 test files; mechanical change).
9. Add new widget tests in `test/nutrition_test.dart` under a new `group('ManageFoodLibrary – add/remove toggle', …)` covering S-001 → S-005, plus an update to the `FoodLibraryBrowse` group that asserts the pencil icon is present and that `NutritionSummaryCard` is not.
10. Run `dart analyze` + the targeted test file + the full `test/` suite.

### Acceptance Criteria

- [ ] `_CatalogRow` renders a red "Remove" button with a white trashcan icon (`Icons.delete_outline`) when the catalog food is already in the user's library.
- [ ] Tapping the red "Remove" button removes the food from the library; the row immediately reverts to the primary "Add" button.
- [ ] Tapping "Add" adds the food; the row immediately switches to the red "Remove" state.
- [ ] Tapping Add **does not** pop the screen. The user can add multiple foods in a single visit.
- [ ] If a food being removed is in today's `consumedToday`, it is unlogged from today (its checkbox on the nutrition page unchecks on next notify). Past day-log snapshots are byte-identical.
- [ ] The "Manage Food Library" `bottomNavigationBar` is removed from `NutritionScreen`.
- [ ] An edit pencil `IconButton` is in the top-right of the Food Library card header and opens `AddFoodScreen`.
- [ ] `NutritionSummaryCard` is no longer rendered on `NutritionScreen`. The Calorie Ring card's edit-targets icon still opens `NutritionTargetScreen`.
- [ ] `FoodLibraryState.isInLibrary(String catalogFoodId)` exists with a doc comment naming the identity rule (name + reference + macros).
- [ ] No double-add: a catalog food that is already in the library is never rendered with the "Add" state.
- [ ] Row width does not jump when the button state flips (fixed trailing width).
- [ ] All colors come from `OmniTheme.colors` / `ThemeData.colorScheme` (no hardcoded red).
- [ ] New widget tests in `test/nutrition_test.dart` cover S-001 → S-005 and the pencil-icon assertion; all pass.
- [ ] All previously passing tests still pass.

### Files Affected

- [lib/state/food_library_state.dart](lib/state/food_library_state.dart) — add `isInLibrary(String catalogFoodId)` + private matcher.
- [lib/features/nutrition/add_food_screen.dart](lib/features/nutrition/add_food_screen.dart) — accept `nutritionState`, rewrite `_CatalogRow` to a `StatefulWidget` with Add/Remove toggle, add `_libraryIdFor` helper, update `_FromCatalogTab` to listen to both states.
- [lib/features/nutrition/nutrition_screen.dart](lib/features/nutrition/nutrition_screen.dart) — remove `bottomNavigationBar`, add pencil `IconButton` to the Food Library card header, remove `NutritionSummaryCard` import + render.
- [lib/features/home/home_screen.dart](lib/features/home/home_screen.dart) — forward `nutritionState` to `AddFoodScreen` (mechanical).
- [test/nutrition_test.dart](test/nutrition_test.dart) — new `ManageFoodLibrary – add/remove toggle` group, plus pencil-icon assertion in `FoodLibraryBrowse`.
- [test/interaction_flow_test.dart](test/interaction_flow_test.dart) — add `nutritionState` to `AddFoodScreen` construction calls (mechanical).
- [test/app_theme_reactive_test.dart](test/app_theme_reactive_test.dart) — same mechanical update.
- [test/screen_widget_test.dart](test/screen_widget_test.dart) — same mechanical update (multiple `AddFoodScreen` constructions).
- [test/home_nutrition_strip_test.dart](test/home_nutrition_strip_test.dart) — same mechanical update.
- [test/profile_navigation_test.dart](test/profile_navigation_test.dart) — same mechanical update.
- [lib/features/nutrition/widgets/nutrition_summary_card.dart](lib/features/nutrition/widgets/nutrition_summary_card.dart) — **no change** (the file is no longer imported by `nutrition_screen.dart`; leave it in place in case other screens reference it; sweep for unused imports in the final pass).

### Unit Tests Required

In [test/nutrition_test.dart](test/nutrition_test.dart), new group `ManageFoodLibrary – add/remove toggle`:

- **`renders Add button on a fresh catalog row`**: seed 1 catalog food, no library foods. Open `AddFoodScreen`, switch to the Library tab. Assert `find.byKey(Key('add_catalog_food_<id>'))` finds one widget, `find.byIcon(Icons.delete_outline)` finds nothing, and the Add button background uses `theme.colorScheme.primary` (verify via `tester.getSize` + reading the `FilledButton` widget's resolved style — see existing tests for the pattern).
- **`tapping Add moves the food into the library and flips the row to Remove`**: after the Add tap, pump frames. Assert `state.foods` has 1 entry, the row now exposes `find.byKey(Key('remove_catalog_food_<id>'))` with `find.byIcon(Icons.delete_outline)`, the Add key is gone, **and the screen is still on the navigator stack** (assert `Navigator.canPop(context) == true` from the screen context, i.e. we did not pop).
- **`tapping Remove takes the food out of the library and flips the row back to Add`**: after the Remove tap, pump. Assert `state.foods` is empty, the Add key is back, the Remove key is gone, and the screen is still mounted.
- **`tapping Add twice does not create two library rows`**: tap Add, pump, tap the now-Remove (to bring it back to Add), tap Add again, pump. Assert `state.foods.length == 1` (each Add creates exactly one library row; the second cycle replaces the same one because the row is the only matching one). (This is the strongest direct check of the single-add invariant at the row level.)
- **`tapping Remove on a logged food unlogs it for today only`**: pre-log a food via `nutritionState.logConsumedFoodAt(libraryFood, 100.0)`. Open AddFoodScreen, switch to Library. Tap the red Remove. Pump. Assert `state.foods` is empty, `nutritionState.isFoodLoggedToday(libraryId) == false`. Separately (in a sibling unit test) confirm past-day `ConsumedFood` entries are unaffected by a different `state.removeFood` call — this is already covered by the iteration 2 test `removeFood leaves past day-log snapshots intact` in `test/food_library_test.dart`.

In the existing `FoodLibraryBrowse` group in `test/nutrition_test.dart`:
- **`renders the pencil icon and no Daily Targets card`**: pump `NutritionScreen` and assert `find.byKey(Key('food_library_manage_pencil'))` finds one widget, `find.text('Daily Targets')` finds nothing, and `find.text('Manage Food Library')` finds nothing on the screen (the bottom CTA is gone).

### Notes

- **Why O(n) scan for `isInLibrary` instead of caching a `Set<String> catalogFoodIds`?** Libraries are small (tens to low hundreds). The scan is O(n) per row, but `n` is the user's library size, not the catalog (107). The catalog size is constant. A `Set<String>` would force the state to keep a separate "added catalog ids" cache in sync with `_foods` (mutation on add, mutation on remove) — more code, more bug surface, no measurable win. The scan is the right tradeoff.
- **Why a fixed trailing width on `_CatalogRow`?** "Add" → "Remove" is a 3 → 6 character change. Without a fixed `SizedBox` the name column would reflow on every state flip, which is visually noisy and looks like a layout bug. 110px is enough for the icon + "Remove" label on the smallest supported device width; the developer should measure on the iPhone SE size during implementation and document the chosen value in the PR.
- **Why not use a `IconButton` for the Remove state instead of `FilledButton.icon`?** A `FilledButton.icon` is consistent with the Add state (also a `FilledButton`). The visual weight matches, and the state flip is a one-widget swap, not a layout reflow. The trash icon lives inside the button to keep its size constrained by the `SizedBox` width.
- **Why not auto-pop after a successful Add?** The user explicitly asked for a multi-add flow (#2) so they can batch-add several foods in one visit. Popping on every add would force the user to re-open the screen 5+ times.
- **Why does Custom-food (Tab 2) still pop?** Custom foods are one-at-a-time (form-driven), and there is no in-row Add/Remove state to flip. The existing behavior is correct as-is; only Tab 1 (catalog) gets the new toggle.
- **Why remove the Daily Targets card?** It duplicates what the Calorie Ring already shows (calories consumed vs target). Targets remain editable via the Calorie Ring's edit icon. The card is the third target-shaped element on the page; consolidating onto the ring is a clean-down that matches the app's "instrument panel" philosophy.
- **Why remove the bottom CTA and not just shrink it?** A bottom CTA on a screen that scrolls a long list of foods pushes the last foods off the visible area. The pencil-on-card keeps the screen in one scroll region. The user can still open the manage flow at any time; the affordance is now top-right of the food library itself.
- **Theme tokens only** — red comes from `theme.colorScheme.error`, on-red from `theme.colorScheme.onError`, white from `theme.colorScheme.onPrimary`. No hardcoded `Colors.red`. (Per `global_conventions.md`.)
- **Repository boundary** — `AddFoodScreen` and `NutritionScreen` continue to depend on `FoodLibraryState` and `NutritionState` only. No direct repository access is added in this iteration. (Per `global_conventions.md`.)
- **Snapshot guarantee is preserved** — the iteration 2 "removeFood leaves past day-log snapshots intact" test continues to pass; this iteration only adds a new unlog-today call in the *specific* S-004 path, and `unlogFoodToday` deletes today's `ConsumedFood` row only (it does not touch past days).
- **Mechanical test updates** are required in 5+ test files because `AddFoodScreen` gains a required `nutritionState` parameter. The updates are pure constructor wiring (add a `nutritionState: …` field to each construction site); no test logic changes.

## Progress

- [x] Add `FoodLibraryState.isInLibrary(String catalogFoodId)` + matcher.
- [x] Add `_libraryIdFor` helper in `add_food_screen.dart`.
- [x] Rewrite `_CatalogRow` as a `StatefulWidget` with Add/Remove toggle + fixed trailing width.
- [x] Wire `NutritionState` through `AddFoodScreen` → `_FromCatalogTab` → `_CatalogRow`.
- [x] `_FromCatalogTab` listens to both `foodLibraryState` and `nutritionState`.
- [x] Remove `bottomNavigationBar` from `NutritionScreen`.
- [x] Add pencil `IconButton` to the Food Library card header.
- [x] Remove `NutritionSummaryCard` import + render from `NutritionScreen`.
- [x] Mechanical test updates: the only mechanical change was in `test/nutrition_test.dart` (replacing `add_food_cta` taps with `food_library_manage_pencil` taps; the 5+ test files listed in the plan never constructed `AddFoodScreen` directly — only `NutritionScreen` does, and its `nutritionState` parameter was already in place). `test/home_nutrition_strip_test.dart` was updated to assert the pencil icon and the absent bottom CTA.
- [x] New `ManageFoodLibrary – add/remove toggle` group in `test/nutrition_test.dart` (S-001 → S-005).
- [x] Update `FoodLibraryBrowse` group: pencil-icon assertion, no Daily Targets card, no bottom CTA.
- [x] `dart analyze` clean (no new errors/warnings introduced; pre-existing infos unchanged).
- [x] `flutter test test/nutrition_test.dart` clean (33/33 pass).
- [x] `flutter test` (full suite) clean (1285 pass + 5 pre-existing skips, 0 failures).
- [x] Doc updates: `navigation_and_screens.md` (pencil entry point, removed bottom CTA + Daily Targets, expanded `AddFoodScreen` description), `state_management.md` (added `isInLibrary` row, fixed corrupted "Removal Semantics" paragraph, updated `AddFoodScreen` consumer note for From Catalog in-place toggle). `widget_catalog.md` needs no change — no new public widget was introduced.
- [x] **Code-review follow-up round 1**:
  - Replaced the UI-side `_libraryIdFor` helper with a new public `FoodLibraryState.libraryIdFor(catalogFoodId) -> String?`; `isInLibrary` is now a thin wrapper over it (`libraryIdFor(c) != null`). The identity rule lives in one place; the UI no longer reimplements it.
  - **Removed the "Remove" word from the Remove button** per user request — the button is now a 40×40 red square containing only `Icons.delete_outline` (no `FilledButton.icon` text label). Uses `OmniTheme.buttonIconRadius` for the rounded square. Sized at 40×40 to match the `CalorieRingCard` edit-targets icon for visual parity.
  - **Pinned the pencil `IconButton`** in the Food Library card header to 40×40 (matching the `CalorieRingCard` edit icon and the new trash button).
  - Updated `test/nutrition_test.dart` toggle-group header comment to reflect the trash-only design.
  - Fixed the doc drift flagged in review: `navigation_and_screens.md` now reads "Library" / "+ New Item" (matches the implemented tab labels) instead of the stale "From Catalog" / "Create Custom".
  - `state_management.md` `FoodLibraryState` methods table now has both `isInLibrary` and `libraryIdFor` rows; the `AddFoodScreen` consumer note now mentions `libraryIdFor` and the "Library tab" name.
  - Added a new `libraryIdFor` test group in `test/food_library_state_test.dart` (3 tests) covering: unknown catalog id → null, after `addCatalogFoodToLibrary` → matches the produced id, after `removeFood` → null.
