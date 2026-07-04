# Feature: Nutrition Day Isolation + Food Groups (Groups) + Catalog Search

## Overview

Three related nutrition follow-ups, planned together because they share
the same data layer (`FoodLibraryState`, `NutritionState`,
`WorkoutRepository`) and the same screen surface (`AddFoodScreen`,
`NutritionScreen`):

1. **Day Isolation** — past days keep their logged foods, amounts, and
   the daily targets that applied then. A new calendar day starts with
   an empty day log. Editing today's targets must not alter any past
   day. (Fast-track — the contract is already enforced by frozen
   snapshots and date-keyed targets; this iteration adds explicit
   coverage and one safety net.)
2. **Food Groups (Groups tab)** — let the user manage the groups
   used to organize their library. Add a new `Groups` tab to the
   Manage Food Library screen with create / rename / delete for
   groups and an "Ungrouped" view for foods with no group. Deleting
   a group with foods must reassign those foods to "Ungrouped" (or a
   chosen destination) — never silently drop them.
3. **Catalog search field** — add a search input to the Library tab
   of the Manage Food Library flow that filters the bundled catalog
   by food name. Pure local filter; no network, no barcode.

## Requirements

### R-1 Day Isolation (TRIVIAL fast-track)

- A new calendar day starts with an empty `consumedToday` log; the
  daily targets roll over unchanged from the most recent prior day.
- Past days' `ConsumedFood` snapshots (name, unit, reference, macros,
  group snapshot, frozen targets) are immutable.
- Editing current targets must not change any past day's totals or
  target snapshot.
- `NutritionState.clearConsumedToday` and `rolloverToDate` already
  exist; the behaviour is enforced. This iteration adds a regression
  net (tests) and a single safety net:
  - `NutritionState.refreshConsumedToday` already exists; we add a
    `Future<void> rolloverToDate(int dateMs)` that clears
    `_consumedToday` and the per-date target cache, then reloads
    today's target — so the in-memory state cannot leak yesterday's
    totals into today after a long-running app.

### R-2 Food Groups (Groups tab) (STANDARD)

- New `Groups` tab added to the `TabBar` in `AddFoodScreen`
  (becomes 3 tabs: Library / + New Item / Groups).
- Groups tab shows a list of existing `FoodGroup`s + an
  "Ungrouped" row at the bottom.
- Each row has an editable `TextField` (the group's name) and a trash
  `IconButton` on the right. Editing the field and pressing
  IME-action / unfocusing persists the rename. The trash opens a
  confirmation dialog with a destination-group dropdown: "Ungrouped"
  (`groupId = null`) plus every other active group, with "Ungrouped"
  selected by default. On confirm, the group is deleted and its foods
  are reassigned to the chosen destination.
- The "Ungrouped" row is informational (count + open read-only) and
  cannot be renamed or deleted.
- A small "+ New Group" affordance at the bottom of the list
  creates a new group with a default name and focuses the new
  row's `TextField` for immediate rename.
- A Group with foods can be deleted; deletion never deletes foods
  — it reassigns their `groupId` to `null`.
- Deleting an already-empty Group is a no-op (no confirmation
  needed); only non-empty deletions ask for confirmation.
- New repository-level method
  `Future<void> reassignFoodsToGroup(List<String> foodIds, String? targetGroupId)`
  on `WorkoutRepository` (default impl: iterate the foods, call
  `updateFood` with the new `groupId`).
- New state methods on `FoodLibraryState`:
  - `Future<void> renameFoodGroup(String id, String newName)` —
    thin wrapper that calls `updateFoodGroup` with the new name.
  - `Future<void> deleteFoodGroupReassigningFoods(String id, String? toGroupId)` —
    finds the foods in that group, calls the new repo method
    (passing `toGroupId`: `null` for "Ungrouped", or the picked
    group's id), then archives the source group; updates both
    caches and notifies.
- "Ungrouped" foods appear in the existing nutrition screen's
  browse card under the "Ungrouped" section — that behaviour
  already exists and is unchanged.

### R-3 Catalog Search Field (STANDARD)

- A `TextField` at the top of the Library tab in `AddFoodScreen`
  filters the catalog list by food name as the user types.
- Search is local (no network). Pure `String.toLowerCase().contains`
  on the cached catalog; the state method delegates to
  `repository.searchFoods` for foods or filters `catalogFoods`
  in-memory.
- Clearing the field restores the full alphabetical list.
- Empty query shows the full list; the input does not produce
  errors.
- The list still re-renders on `addCatalogFoodToLibrary` /
  `removeFood` (so the "in library" badge stays in sync with the
  filter).
- New state method on `FoodLibraryState`:
  `Future<List<Food>> searchCatalogFoods(String query)` —
  in-memory filter of `_catalogFoods` by case-insensitive
  substring on `name`. Returns alphabetical order.

## Acceptance Criteria

### R-1

- [ ] A new day's `consumedToday` is empty after a rollover; the
      loaded target matches the most recent ancestor or `null`.
- [ ] Editing today's targets leaves every prior `ConsumedFood`
      row's frozen `targetCalories/Protein/Carbs/Fat` byte-identical.
- [ ] The repository returns the same `getConsumedFoodsForDate`
      result for a past date before and after a target edit on a
      later date.

### R-2

- [ ] The Manage Food Library screen has three tabs: Library /
      + New Item / Groups.
- [ ] The Groups tab lists all active groups alphabetically;
      the "Ungrouped" row sits at the bottom and is non-editable.
- [ ] Each group row has a `TextField` (name) and a trash
      `IconButton`; editing the field and unfocusing persists the
      rename.
- [ ] A "+ New Group" affordance adds a new group and focuses
      the new row's name field.
- [ ] Deleting a non-empty group opens a confirmation dialog with
      a destination dropdown ("Ungrouped" + every other active
      group, "Ungrouped" default); confirming reassigns the
      group's foods to the chosen destination and archives the
      group.
- [ ] Deleting an empty group is a silent no-op (no confirmation).
- [ ] The custom-food form's Group dropdown continues to show
      the new groups and the "Ungrouped" option.
- [ ] Foods with `groupId = null` still appear under "Ungrouped"
      on `NutritionScreen`.

### R-3

- [ ] The Library tab has a `TextField` at the top labeled
      "Search".
- [ ] Typing filters the list by case-insensitive name substring
      in alphabetical order; clearing the field restores the full
      list.
- [ ] No HTTP / network call is made on keystroke; the filter is
      pure local.

## Scenarios

### R-1 — Day Isolation (TRIVIAL)

#### S-001: New day, empty log, targets rolled over

- Trigger: User opens the app on day 2 after logging foods on day 1.
- Precondition: Day 1 has 3 logged foods and a target of
  cal=2500 / P=150 / C=300 / F=80; day 2 has no foods and no
  explicit target.
- Flow:
  1. `NutritionState.rolloverToDate(day2Ms)` runs (or the user
     navigates into the page on day 2).
  2. `consumedToday` is empty.
  3. Today's target = the rolled-over target from day 1.
- Expected outcome: `consumedToday.length == 0`;
  `nutritionTarget` equals the day-1 target copy.
- Edge case of: none

#### S-002: Edit today; past day's totals + target snapshot are stable

- Trigger: User edits today's target from 2500/150/300/80 to
  2700/170/320/85.
- Precondition: Day 1 has 2 logged `ConsumedFood` rows, each with
  frozen `targetCalories=2500` etc.
- Flow:
  1. `saveNutritionTargetForDate(todayMs, newTarget)`.
  2. Re-read past day's `getConsumedFoodsForDate(day1Ms)`.
  3. Re-read today's `getNutritionTargetForDate(todayMs)`.
- Expected outcome: Past rows' `targetCalories == 2500`,
  `targetProtein == 150`, etc., byte-identical. Today's target
  equals the new target. `ConsumedFood.caloriesConsumed` for each
  past row is unchanged.
- Edge case of: none

### R-2 — Food Groups (Groups tab) (STANDARD)

#### S-101: Render Groups list with Ungrouped at the bottom

- Trigger: User opens the Groups tab in Manage Food Library.
- Precondition: 2 groups exist ("Proteins", "Vegetables"); 1
  library food has `groupId == null`; 1 has groupId = "Proteins".
- Flow: The tab builds the list.
- Expected outcome: Rows in order: "Proteins" (editable), then
  "Vegetables" (editable), then "Ungrouped" (1 food, non-editable,
  trash icon hidden). All alphabetical.
- Edge case of: none

#### S-102: Rename a Group

- Trigger: User edits the "Proteins" row's name field to "Lean
  Proteins" and unfocuses.
- Precondition: Group "Proteins" exists.
- Flow: `FoodLibraryState.renameFoodGroup(id, 'Lean Proteins')`.
  Cache updates; listeners notify.
- Expected outcome: Row shows "Lean Proteins". Repository's
  `getFoodGroupById(id).name == 'Lean Proteins'`. The food row on
  the nutrition screen (which displays `groupNameSnapshot` from
  past logs) is unaffected (snapshot is frozen).
- Edge case of: none

#### S-103: Create a new Group

- Trigger: User taps "+ New Group" at the bottom of the
  Groups tab.
- Precondition: 2 groups exist.
- Flow:
  1. `FoodLibraryState.createFoodGroup('New Group')` runs.
  2. The new row's `TextField` is focused.
  3. User renames it to "Snacks" and unfocuses; persistence
     happens via `renameFoodGroup`.
- Expected outcome: A new group "Snacks" is persisted; the
  custom-food form's Group dropdown includes it.
- Edge case of: none

#### S-104: Delete a non-empty Group (reassign)

- Trigger: User taps the trash icon next to "Proteins".
- Precondition: "Proteins" has 3 library foods; "Vegetables" is
  empty; "Snacks" is also active.
- Flow:
  1. Confirmation dialog appears: "Delete Group 'Proteins'?
     Move 3 foods to: [dropdown: Ungrouped / Snacks]"
     (default: "Ungrouped").
  2. User picks "Snacks" and confirms.
  3. `FoodLibraryState.deleteFoodGroupReassigningFoods(id, toGroupId)`
     calls `repository.reassignFoodsToGroup(foodIds, 'snacks-id')`,
     then `archiveFoodGroup(id)`.
- Expected outcome: "Proteins" is archived (no longer in active
  list); the 3 foods have `groupId == 'snacks-id'`; the nutrition
  screen now shows those 3 foods under "Snacks". No food is
  deleted. The repository's `getFoods()` returns the same total
  count.
- Edge case of: none

#### S-105: Delete an empty Group (no confirm)

- Trigger: User taps the trash icon next to "Vegetables".
- Precondition: "Vegetables" has 0 library foods.
- Flow: Tap → archive immediately (no dialog).
- Expected outcome: "Vegetables" disappears from the active list.
  No confirmation dialog shown.
- Edge case of: S-104

#### S-106: Ungrouped row is read-only

- Trigger: User tries to rename or delete the Ungrouped row.
- Precondition: There is at least one food with `groupId == null`.
- Flow: Long-press / tap on the Ungrouped row.
- Expected outcome: No rename field, no trash icon. The row shows
  the food count and is purely informational.
- Edge case of: none

### R-3 — Catalog Search Field (STANDARD)

#### S-201: Typing filters the catalog

- Trigger: User types "chick" in the search field of the Library
  tab.
- Precondition: Catalog has "Chicken breast, skinless", "Chicken
  thigh, skinless", "Salmon, cooked", "Cod, cooked".
- Flow: On every keystroke, `FoodLibraryState.searchCatalogFoods('chick')`
  filters in-memory.
- Expected outcome: Only "Chicken breast, skinless" and "Chicken
  thigh, skinless" are visible, in alphabetical order. "Salmon"
  and "Cod" are not visible.
- Edge case of: none

#### S-202: Empty / cleared query shows the full list

- Trigger: User clears the search field.
- Precondition: The previous query was "chick".
- Flow: Empty string is passed to the filter.
- Expected outcome: All catalog rows are visible, alphabetical.
- Edge case of: S-201

#### S-203: Search is local (no network)

- Trigger: Search filter runs.
- Precondition: App is online; network is available.
- Flow: Test asserts no HTTP client is invoked.
- Expected outcome: `verifyNever(() => httpClient.get(any()))`
  passes; the filter resolves synchronously.
- Edge case of: none

## Iteration 1

### DB Changes

- New repository method
  `Future<void> reassignFoodsToGroup(List<String> foodIds, String? targetGroupId)`
  on `WorkoutRepository`.
- Mock implementation: iterate food ids, call `updateFood` with
  new `groupId` for each.
- Hive implementation: same — iterate the foods box and write each
  updated row.
- SQLite parity: a single `UPDATE app_food SET group_id = ?
  WHERE id IN (...)` statement; documented in
  `scripts/sqlite_schema.sql` (note: no schema change required; the
  table already supports `group_id`).

### Backend Changes

- New state method `Future<void> renameFoodGroup(String id, String newName)`
  on `FoodLibraryState` — thin wrapper that calls
  `updateFoodGroup(...)` with the renamed group.
- New state method
  `Future<void> deleteFoodGroupReassigningFoods(String id)` on
  `FoodLibraryState` — finds the foods in that group, calls
  `repository.reassignFoodsToGroup(foodIds, null)`, then
  `archiveFoodGroup(id)`. Updates both caches and notifies.
- New state method
  `Future<List<Food>> searchCatalogFoods(String query)` on
  `FoodLibraryState` — pure local filter on `_catalogFoods`,
  case-insensitive substring on `name`, sorted alphabetically.
- `NutritionState.rolloverToDate(int dateMs)` — already exists as
  a forward to `loadNutritionTargetForDate`. This iteration
  extends it to also call `clearConsumedToday` so a long-running
  app's in-memory state cannot leak yesterday's totals into today.

### Frontend Changes

#### R-1
- `NutritionState.rolloverToDate` extended to clear
  `_consumedToday` and the per-date target cache, then reload
  today's target.

#### R-2
- `AddFoodScreen`'s `TabController` length becomes 3; new tab
  `Groups` is added.
- New widget `GroupsTab` in `add_food_screen.dart` renders
  the Groups list.
- New private widget `_GroupRow`:
  - `TextField` (controller) for the group name; on
    `onSubmitted` / `onEditingComplete` calls
    `foodLibraryState.renameFoodGroup`.
  - `IconButton(Icons.delete_outline)` for the trash; on tap,
    if the group has foods, show `AlertDialog` confirmation;
    on confirm call
    `deleteFoodGroupReassigningFoods`.
  - For the "Ungrouped" synthetic row, render a `Text` count
    and no edit / delete controls.
- `+ New Group` button at the bottom of the list:
  - Calls `foodLibraryState.createFoodGroup('New Group')`
    with a stable default name; focuses the new row's
    `TextField`.

#### R-3
- `AddFoodScreen`'s Library tab gains a `TextField` at the top
  with a `TextEditingController`; on every change, the
  `ListenableBuilder` rebuilds with a filtered list via
  `searchCatalogFoods`.

### Implementation Steps (Developer)

1. Add `WorkoutRepository.reassignFoodsToGroup` to the interface;
   implement in Mock and Hive.
2. Add `FoodLibraryState.renameFoodGroup`,
   `deleteFoodGroupReassigningFoods`,
   `searchCatalogFoods`.
3. Extend `NutritionState.rolloverToDate` to also clear
   `_consumedToday`.
4. Wire the Groups tab + `_GroupRow` in
   `add_food_screen.dart`; update the `TabController` length to 3.
5. Add the search `TextField` to the Library tab.
6. Update seed data / docs as needed.

## Unit Tests Required

### R-1 (TRIVIAL — fast-track)

- `test/nutrition_test.dart`, new group `Nutrition day isolation`:
  - `past day's ConsumedFood rows keep frozen targets and totals
    after a later-day target edit` (state-level + repo-level).
  - `rolloverToDate clears today's consumed cache and reloads
    the rolled-over target`.

### R-2 (STANDARD)

- `test/food_library_test.dart`, new group
  `Food groups (Groups tab)`:
  - `renameFoodGroup persists the rename and notifies listeners`.
  - `deleteFoodGroupReassigningFoods moves foods to Ungrouped
    and archives the group`.
  - `reassignFoodsToGroup leaves total food count unchanged`.

### R-3 (STANDARD)

- `test/food_library_test.dart`, new group
  `Catalog search`:
  - `searchCatalogFoods filters by case-insensitive name
    substring`.
  - `searchCatalogFoods returns full list for empty query`.

## Files Affected

- [lib/data/repositories/workout_repository.dart](lib/data/repositories/workout_repository.dart) — add `reassignFoodsToGroup` to the interface.
- [lib/data/repositories/mock_workout_repository.dart](lib/data/repositories/mock_workout_repository.dart) — implement `reassignFoodsToGroup`.
- [lib/data/repositories/hive_workout_repository.dart](lib/data/repositories/hive_workout_repository.dart) — implement `reassignFoodsToGroup`.
- [lib/state/food_library_state.dart](lib/state/food_library_state.dart) — add `renameFoodGroup`, `deleteFoodGroupReassigningFoods`, `searchCatalogFoods`.
- [lib/state/nutrition_state.dart](lib/state/nutrition_state.dart) — extend `rolloverToDate` to also clear `consumedToday`.
- [lib/features/nutrition/add_food_screen.dart](lib/features/nutrition/add_food_screen.dart) — add Groups tab + search field; update `TabController` length to 3.
- [scripts/sqlite_schema.sql](scripts/sqlite_schema.sql) — note that `reassignFoodsToGroup` is a single `UPDATE` against the existing `app_food.group_id` column.
- [test/food_library_test.dart](test/food_library_test.dart) — new test groups.
- [test/nutrition_test.dart](test/nutrition_test.dart) — new day-isolation test group.
- [.github/agents/docs/data_models.md](.github/agents/docs/data_models.md) — note no new models.
- [.github/agents/docs/db_integration.md](.github/agents/docs/db_integration.md) — add the new repo method.
- [.github/agents/docs/state_management.md](.github/agents/docs/state_management.md) — add the new state methods.
- [.github/agents/docs/navigation_and_screens.md](.github/agents/docs/navigation_and_screens.md) — note the new Groups tab.
- [.github/agents/docs/widget_catalog.md](.github/agents/docs/widget_catalog.md) — note the new `_GroupRow` and search field.

## Progress

- [x] Phase 0 — plan complete
- [x] Phase 1 — data layer (repo + state methods)
- [x] Phase 2.0 — TDD red tests for R-1, R-2, R-3
- [x] Phase 2.1 — R-1 implementation (TRIVIAL)
- [x] Phase 2.2 — R-2 implementation (Groups tab)
- [x] Phase 2.3 — R-3 implementation (Catalog search)
- [x] Phase 2.6 — `flutter test` green
- [x] Phase 2.7 — doc hygiene
- [x] Phase 3 — code review (human checkpoint)

### Phase 3 Complete ✓

Review findings presented to the user. Plan is locked.

### Phase 1 Complete ✓

- `WorkoutRepository.reassignFoodsToGroup(foodIds, targetGroupId)`
  added to the interface and implemented in both `MockWorkoutRepository`
  and `HiveWorkoutRepository` (catalog rows are excluded by the Hive
  path; mock is library-only so the check is implicit there).
- `scripts/sqlite_schema.sql` documents the future `UPDATE app_food
  SET group_id = ? WHERE id IN (...)` statement.
- `FoodLibraryState` gains `renameFoodGroup`,
  `deleteFoodGroupReassigningFoods(id, toGroupId)`, and
  `searchCatalogFoods(query)`. The delete path reassigns foods first,
  then archives the source group, then refreshes the food cache.
- `NutritionState.rolloverToDate` now clears `_consumedToday` and the
  per-date target cache before reloading, so a long-running app
  cannot leak yesterday's totals into today.
- `data_models.md` — no new model fields (FoodGroup already had
  everything needed; `ConsumedFood` frozen-snapshot contract is
  unchanged).
- `db_integration.md` — `reassignFoodsToGroup` row added.
- `state_management.md` — three new `FoodLibraryState` methods and
  the extended `NutritionState.rolloverToDate` documented.

### Phase 2 Complete ✓

- **R-1 tests** (2): `test/nutrition_test.dart` — past-day snapshot
  stability after a later-day target edit; `rolloverToDate` clears
  the in-memory consumed cache.
- **R-2 tests** (8): `test/food_library_test.dart` — group rename,
  rename no-ops, rename throws on unknown id, delete + reassign to
  Ungrouped, delete + reassign to a chosen group,
  `reassignFoodsToGroup` total count preserved, empty list no-op,
  unknown ids silently skipped. Plus 3 widget tests in
  `test/nutrition_test.dart` — Groups tab renders the
  groups + Ungrouped + button, "+ New Group" creates a row and
  the state gains a group, trash on a non-empty group shows the
  confirm dialog and reassigns to Ungrouped.
- **R-3 tests** (3 state + 2 widget): `test/food_library_test.dart` —
  search filters by case-insensitive name substring, empty query
  returns the full list, alphabetical order. `test/nutrition_test.dart`
  — search field is present on the Library tab, typing filters the
  catalog by name.
- **Implementation**: 3-tab `AddFoodScreen` (Library / + New Item /
  Groups), `_GroupRow` with inline rename + trash,
  `_UngroupedRow`, `_DeleteGroupDialog` with destination dropdown,
  `+ New Group` button. `_FromCatalogTab` converted to
  `StatefulWidget` with a `TextField` for the search filter. The
  search filter is pure-local (no network), driven by
  `FoodLibraryState.searchCatalogFoods`. The dialog's cancel vs
  Ungrouped (both `null`) ambiguity is resolved with a private
  `_cancelledSentinel` const.
- **Bug fix found during TDD**: `Food.copyWith(groupId: null)` was a
  no-op because `groupId ?? this.groupId` cannot distinguish
  "omitted" from "explicitly null". Fixed with a private
  `_foodCopyWithUnset` sentinel mirroring the existing pattern in
  `ExerciseNote.copyWith`. Documented in `data_models.md`.
- **State getter refactor**: `FoodLibraryState.foodGroups` was
  re-introduced as the full-cache getter (preserving the
  pre-existing `archiveFoodGroup` test contract); a new
  `activeFoodGroups` getter returns the filtered list. The
  Groups tab and the custom-food form's Group dropdown both
  consume `activeFoodGroups`.
- **Test status**: 1306 pass, 5 pre-existing skipped, 0 failures.
- **Doc hygiene**:
  - `data_models.md` — note on `Food.copyWith` sentinel.
  - `db_integration.md` — `reassignFoodsToGroup` row.
  - `state_management.md` — three new `FoodLibraryState` methods,
    `activeFoodGroups` getter, `searchCatalogFoods`,
    `rolloverToDate` extension.
  - `navigation_and_screens.md` — `AddFoodScreen` now described as
    a 3-tab flow with the new `Groups` tab and the search field.
  - `widget_catalog.md` — `_GroupsTab`, `_GroupRow`,
    `_UngroupedRow`, `_DeleteGroupDialog` entries.

Next: Phase 3 — code review (human checkpoint).

### Phase 1 Complete ✓

- `WorkoutRepository.reassignFoodsToGroup(foodIds, targetGroupId)`
  added to the interface and implemented in both `MockWorkoutRepository`
  and `HiveWorkoutRepository` (catalog rows are excluded by the Hive
  path; mock is library-only so the check is implicit there).
- `scripts/sqlite_schema.sql` documents the future `UPDATE app_food
  SET group_id = ? WHERE id IN (...)` statement.
- `FoodLibraryState` gains `renameFoodGroup`,
  `deleteFoodGroupReassigningFoods(id, toGroupId)`, and
  `searchCatalogFoods(query)`. The delete path reassigns foods first,
  then archives the source group, then refreshes the food cache.
- `NutritionState.rolloverToDate` now clears `_consumedToday` and the
  per-date target cache before reloading, so a long-running app
  cannot leak yesterday's totals into today.
- `data_models.md` — no new model fields (FoodGroup already had
  everything needed; `ConsumedFood` frozen-snapshot contract is
  unchanged).
- `db_integration.md` — `reassignFoodsToGroup` row added.
- `state_management.md` — three new `FoodLibraryState` methods and
  the extended `NutritionState.rolloverToDate` documented.

Next: Phase 2.0 — write the red tests.

### Phase 0 Complete ✓

Plan authored at
`.github/agents/plans/nutrition-day-isolation-groups-search-plan.md`.
Scenarios locked in via Q&A:

- Group delete UX: confirmation dialog with destination dropdown
  (Ungrouped + every other active group, Ungrouped default).
- Empty delete: silent (no confirmation).
- Catalog search: name-only substring.
- Day rollover safety net: explicit `rolloverToDate` extension
  only (no midnight observer).

Next: Phase 1 — Data Layer.

## Feedback

[Leave empty until a specialist or reviewer adds notes]
