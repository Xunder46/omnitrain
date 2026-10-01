# Feature: Food Library — Browse View (Read-only)

## Overview

Add a read-only, scrollable, **grouped** view of the food library to the nutrition feature. Foods are displayed under their `FoodGroup` (with `groupId == null` foods in a trailing **Ungrouped** section), showing each food's name and per-serving calories / protein / carbs / fat. Display only — no add, edit, or log controls in this step. This is the browse view users will log from in a future iteration.

Sits **inline on `NutritionScreen`** (per product decision), directly below the existing "Consumed Today" card, above the daily targets summary. No new route, no new bottom CTA. Foods without a group render in a single trailing "Ungrouped" section.

## Requirements

- Render the library grouped by `FoodGroup` on `NutritionScreen`.
- Within each group, render each `Food` showing: name, calories (computed), protein (g), carbs (g), fat (g).
- Foods with `groupId == null` appear in a trailing **Ungrouped** section after all named groups.
- Groups are sorted alphabetically by `name` (case-insensitive) for stable display.
- Foods within a group are sorted alphabetically by `name` (case-insensitive).
- Empty state: a single muted line "No foods in library" centered in the section when there are no active groups and no active foods.
- Loading state: a `CircularProgressIndicator` centered in the section while the initial load is in flight.
- **Display only** — no FAB, no edit/log/add controls, no taps wired up.
- Excludes archived groups and archived foods (default `includeArchived: false` on both repository calls).
- Show seeded and any user-added foods alike (no special-casing).

## Acceptance Criteria

- [ ] `NutritionScreen` shows a "Food Library" card with a scrollable grouped list of all active foods, grouped by their `FoodGroup`.
- [ ] Each food row visibly shows: food name, calories (integer), protein (g), carbs (g), fat (g).
- [ ] Groups appear in alphabetical order (case-insensitive); foods within a group also alphabetical (case-insensitive).
- [ ] Foods with `groupId == null` appear in a trailing "Ungrouped" section.
- [ ] Archived groups and archived foods are **not** rendered.
- [ ] Empty library → a single muted line "No foods in library".
- [ ] No add / edit / log / FAB / button controls are present in this view.
- [ ] State is loaded via the existing `FoodLibraryState` (no direct repository access from the screen).
- [ ] Works on web (Hive) and remains compatible with the future SQLite repository — no platform-specific code in the new widget.
- [ ] New unit test: `test/nutrition_test.dart` (existing file) gains a `FoodLibraryBrowse` group with at least one widget test that seeds multiple groups + foods (including one ungrouped) and asserts every group header, every food name, and the four macro values are visible in the rendered tree.

## Scenarios

### S-001: Initial load renders all groups and foods
- Trigger: User opens `NutritionScreen` (from the home strip or hub).
- Precondition: Repository contains 2 groups ("Proteins", "Vegetables"), with 3 foods total (2 in Proteins, 1 in Vegetables), plus 1 food with `groupId == null`.
- Flow: `NutritionScreen.initState` (or a focused `StatefulWidget` inside it) calls `FoodLibraryState.loadFoodGroups()` and `loadFoods()` in parallel. Once both complete, the new "Food Library" card is rendered.
- Expected outcome: The card shows two group headers ("Proteins", "Vegetables") in alphabetical order, a trailing "Ungrouped" header, every food name visible, and each food row's calories/protein/carbs/fat are all findable as text.
- Edge case of: none

### S-002: Empty library
- Trigger: User opens `NutritionScreen` for the first time (no foods, no groups ever created).
- Precondition: `getFoods()` returns `[]` and `getFoodGroups()` returns `[]`.
- Flow: Same as S-001; both load calls resolve to empty lists.
- Expected outcome: A single muted line "No foods in library" appears inside the "Food Library" card. No group headers, no food rows.
- Edge case of: S-001

### S-003: Loading state
- Trigger: User opens `NutritionScreen` and the initial load is in flight.
- Precondition: `loadFoodGroups()` and `loadFoods()` have not yet resolved.
- Flow: `ListenableBuilder` reads `FoodLibraryState.isLoadingGroups || isLoadingFoods` and renders a `CircularProgressIndicator` centered in the card.
- Expected outcome: A single `CircularProgressIndicator` is visible; the list/empty line is not.
- Edge case of: S-001

### S-004: Archived items hidden
- Trigger: User opens `NutritionScreen`.
- Precondition: Repository contains 1 active group, 1 archived group, foods belonging to each (active and archived). `loadFoodGroups()` and `loadFoods()` are called with `includeArchived: false` (default).
- Flow: Default filters drop archived items.
- Expected outcome: Only the active group's header and its active foods render. No "Ungrouped" or archived foods visible.
- Edge case of: S-001

### S-005: User-added foods appear
- Trigger: User opens `NutritionScreen` after adding a food through any future UI.
- Precondition: Repository contains a single seeded group with seeded foods plus one user-added food in the same group.
- Flow: Initial load picks up both via the repository.
- Expected outcome: All foods (seeded + user-added) appear under their group, sorted alphabetically.
- Edge case of: S-001

## Iteration 1

### DB Changes
None — uses existing `app_food_group` and `app_food` tables and the already-implemented `getFoodGroups` / `getFoods` repository methods.

### Backend Changes
None — `WorkoutRepository`, `HiveWorkoutRepository`, `MockWorkoutRepository`, and `FoodLibraryState` are all already in place from the prior iteration. This iteration is UI-only.

### Frontend Changes
1. [ ] **Wire `FoodLibraryState` into `NutritionScreen` constructor** in [nutrition_screen.dart](lib/features/nutrition/nutrition_screen.dart).
   - Add `final FoodLibraryState foodLibraryState;` parameter.
   - Pass it through from `home_screen.dart` (the only caller) and from `app.dart` if needed (state is already constructed in `main.dart`).
2. [ ] **Trigger initial loads** in `initState` (parallel):
   - `await Future.wait([foodLibraryState.loadFoodGroups(), foodLibraryState.loadFoods()])`.
   - Keep `_loadTodayTarget` (existing) running in parallel; today and the library are independent.
3. [ ] **Create `FoodLibraryBrowseSection` widget** at [nutrition_screen.dart](lib/features/nutrition/nutrition_screen.dart) (private `_FoodLibraryBrowseSection` is fine, or extract to [widgets/](lib/features/nutrition/widgets/food_library_browse_section.dart) — see Notes).
   - Wrapped in `ListenableBuilder(listenable: foodLibraryState, …)`.
   - Branch on `isLoadingGroups || isLoadingFoods` → `Centered(CircularProgressIndicator)`.
   - Branch on empty (`groups.isEmpty && foods.isEmpty`) → `Centered(Text('No foods in library', style: textMuted))`.
   - Otherwise build a `Column` of `_GroupBlock` widgets, plus a trailing `_GroupBlock` for ungrouped foods (only if any exist).
4. [ ] **`_GroupBlock` private widget** (or top-level helper) renders a group header + per-food rows:
   - Header: group name in `theme.textTheme.titleMedium` with `OmniTheme.titleLetterSpacing` and `textDominant` color.
   - Each food row: `Row` with name (flex), then `cal · P · C · F` (small, `textSecondary`). Use compact layout — e.g. `'185 cal · 31P · 0C · 3F'` in a single trailing text widget, or four small columns; pick the more readable option during implementation and document the choice in PR.
   - Compute calories with `calculateCalories(food)` from `lib/core/utils/food_helpers.dart` (already exists; do **not** store calories on the model).
   - Show `0 g` rather than hiding zero macros (consistency with the eventual logging view).
5. [ ] **Add the section to the existing card list** in `NutritionScreen.build`:
   - Insert a new `Card` titled "Food Library" between the "Consumed Today" card and the `NutritionSummaryCard`.
   - Padding, border-radius, and shadow use the same `Card` / `Theme` defaults the screen already uses.
6. [ ] **Sort logic** (pure, easy to test):
   - Sort groups by `name.toLowerCase()`.
   - Sort foods by `name.toLowerCase()`.
   - Ungrouped foods are gathered into a synthetic "Ungrouped" section after the named groups.
7. [ ] **No add / edit / log controls** — confirm the section renders no `IconButton`, `FilledButton`, `FloatingActionButton`, `InkWell`, or `onTap` wiring.

### Implementation Steps (Developer)

1. Wire `FoodLibraryState` into `NutritionScreen` and its only caller (`HomeScreen`).
2. Build the `FoodLibraryBrowseSection` widget (and the private `_GroupBlock` / `_FoodRow` helpers).
3. Insert the new `Card` into the existing column on `NutritionScreen`.
4. Add a widget test in `test/nutrition_test.dart` under a new `group('FoodLibraryBrowse', …)`.
5. Run the targeted test file, then the full `test/` suite to ensure no regressions.

## Unit Tests Required

- **New** (in `test/nutrition_test.dart`, new group `FoodLibraryBrowse`):
  - `testWidgets('renders all groups and foods with macros visible', …)`:
    - Build a `MockWorkoutRepository`, seed 2 groups ("Proteins", "Vegetables") and 4 foods (2 in Proteins, 1 in Vegetables, 1 with `groupId == null`).
    - Construct `FoodLibraryState(repo)`, call `loadFoodGroups()` and `loadFoods()`.
    - Pump `NutritionScreen(nutritionState: NutritionState(repo), foodLibraryState: state)`.
    - Assert:
      - `find.text('Proteins')` finds one widget
      - `find.text('Vegetables')` finds one widget
      - `find.text('Ungrouped')` finds one widget
      - Each of the 4 food names finds one widget
      - At least one calorie integer (computed value of one of the foods) finds one widget — confirms macro column is rendered
    - Assert that there is no `IconButton` (other than the back arrow if present — but the section lives inline on `NutritionScreen` which has no back button) and no `FloatingActionButton` inside the new card. Practically: assert `find.byIcon(Icons.add)` finds nothing and `find.text('Log')` finds nothing.

## Files Affected

- [lib/features/nutrition/nutrition_screen.dart](lib/features/nutrition/nutrition_screen.dart) — add `FoodLibraryState` param, add inline section widget, insert new `Card`.
- [lib/features/home/home_screen.dart](lib/features/home/home_screen.dart) — accept and forward `FoodLibraryState` to `NutritionScreen`.
- [lib/app.dart](lib/app.dart) — verify `MyApp` already forwards `foodLibraryState`; if not, add the param and forward it to `HomeScreen`.
- [test/nutrition_test.dart](test/nutrition_test.dart) — add the `FoodLibraryBrowse` test group.

## Notes

- **Why inline on `NutritionScreen`?** Per product decision: keeps the data layer where users will reach it from the daily summary, avoids premature screen-count growth, and lets the future "log" interaction (next iteration) land naturally inside the same card.
- **Why no new widget file?** The browse section is small (~one card) and tightly coupled to `NutritionScreen`. If a second consumer appears (e.g. a "Browse Library" entry point), extract to `lib/features/nutrition/widgets/food_library_browse_section.dart` then. Premature extraction would conflict with the codebase's pattern of keeping feature-private widgets inside `features/<feature>/`.
- **Calories are computed, not stored** — use `calculateCalories(food)` from `lib/core/utils/food_helpers.dart` to match the rest of the app. Never read or store a `calories` field on `Food` directly (the model only exposes the getter).
- **Display-only** — no `onTap`, no `IconButton`, no FAB. The acceptance criteria explicitly exclude logging/adding/editing; the test asserts there is no `Icons.add` and no "Log" text in the tree.
- **Theme tokens only** — colors and text styles must come from `OmniTheme.colors` and the active `ThemeData`; do not hardcode any color. (Per `global_conventions.md`.)
- **Repository boundary** — `NutritionScreen` and the new section must depend on `FoodLibraryState` only, never on a concrete repository. (Per `global_conventions.md` and the original food-library plan.)
- **Empty state copy** is intentionally minimal ("No foods in library") per UX decision; do not add an icon or CTA.
- **Sort stability** — `List<FoodGroup>` and `List<Food>` are returned from the repository in insertion order; sorting here is necessary so seeded and user-added items intermix predictably.
- **Test environment** — `MockWorkoutRepository` is web-compatible and is what the existing `nutrition_test.dart` already uses. The new test follows the same `_freshRepo()` helper pattern for consistency.
- **Dual-environment** — the section reads only from `FoodLibraryState`, which talks to the `WorkoutRepository` interface. The same code works on web (Hive) and the future native build (SQLite) without changes.

## Progress

- [x] Wire `FoodLibraryState` into `NutritionScreen` constructor and its single caller.
- [x] Add `loadFoodGroups` + `loadFoods` calls in `NutritionScreen.initState`.
- [x] Build inline `FoodLibraryBrowseSection` (loading / empty / grouped / ungrouped states).
- [x] Add `_GroupBlock` and `_FoodRow` helpers with macro display and computed calories.
- [x] Add the new `Card` to the `NutritionScreen` build column.
- [x] Forward `foodLibraryState` through `MyApp` → `HomeScreen` → `NutritionScreen` (and `HubSheet`).
- [x] Add `FoodLibraryBrowse` widget test in `test/nutrition_test.dart`.
- [x] Run the new test, then the full suite.

### Test status

- `test/nutrition_test.dart` — 11/11 tests pass.
  - S-001 happy path: 1 widget test (`FoodLibraryBrowse renders all groups and foods with macros visible`) — seeds 2 groups + 4 foods (one ungrouped) and asserts every group header, every food name, and macro strings visible; macro assertion is a `RegExp` so format tweaks don't silently break it; plus the absence of `Icons.add`, "Log", "Add", "Edit", and any `FloatingActionButton`.
  - S-002 empty: 1 widget test (`shows muted "No foods in library" line when library is empty`) — drives a fresh `FoodLibraryState` against an empty repo and asserts the muted text + no "Ungrouped" header.
  - S-003 loading (state contract): 2 unit tests (`loadFoodGroups toggles isLoadingGroups true → false`, `loadFoods toggles isLoadingFoods true → false`) — captures both `notifyListeners()` observations to verify the section's loading branch is wired correctly. The visible loading state is unobservable in widget tests against the synchronous mock.
  - S-004 archived: 1 widget test (`hides archived groups and foods from the rendered tree`) — seeds an active group + archived group with foods, asserts the active group/food render and the archived group/food do not.
  - S-005 user-added: covered transitively by S-001 (the seed uses `createFood` which exercises the same code path as user-added foods).
- Three pre-existing tests in the working tree that called `HomeScreen(...)` without the new `foodLibraryState` parameter were updated to pass `FoodLibraryState(repository)` and now compile: `home_nutrition_strip_test.dart`, `interaction_flow_test.dart`, `profile_navigation_test.dart`.
- The remaining 27 failing tests in the working tree are pre-existing (unrelated to this iteration): 24 fail to compile because `SettingsState` now requires a `PreferencesService` (a prior uncommitted change), 2 miss `nutritionState` on `HomeScreen` (pre-existing, from the iteration that added `nutritionState`), and 1 (`profile_navigation_test`) is a known-hanging test tracked in the `nutrition-targets-daily` plan. None of these were introduced by this work.

### Code Review follow-up (this round)

Code Reviewer flagged 4 warnings and 2 suggestions; all addressed in this round:
- ✅ **W1 (S-003 coverage)**: replaced with 2 state-level contract tests that capture both `notifyListeners()` observations.
- ✅ **W2 (S-002 coverage)**: added widget test for empty state.
- ✅ **W3 (S-004 coverage)**: added widget test for archived filter at the screen level.
- ✅ **W4 (macro assertion brittleness)**: replaced 4 brittle `contains` checks with 1 `RegExp` that tolerates whitespace and segment reordering.
- ✅ **S1 (sort helper duplication)**: extracted generic `_sortedByName<T>` helper; `_sortedGroups` and `_sortedFoods` now delegate to it.
- ⏸️ **S2 (outer ListenableBuilder scope)**: accepted as-is — no behavioral issue today, deferred per code reviewer note.

## Feedback
[Leave empty until a specialist or reviewer adds notes]
