# Plan: Edit Food must not crash when its category is gone; deletion must not strand foods

## Overview

Opening the Edit Food screen for a food whose `groupId` points at a
category that is no longer in the active list crashes the app with a
full-page error because the form's `DropdownButtonFormField` for the
category declares `initialValue: _groupId` but no matching
`DropdownMenuItem` exists. This is reachable in two normal user paths:
the user deletes a category the food filed under (catalog foods
filed under that category are stranded because no path exists to
rehome them); or, on first launch, a default category was skipped
because the user had already created their own with the same name,
while the bundled foods were still filed under the skipped default.

Two fixes are needed. (1) The Edit Food form must render without
crashing regardless of category state, must show the food's actual
category as the selected value, must visually distinguish missing
or archived categories from active ones, and must not silently
rewrite the category on open or on save-without-changes. (2) The
category-deletion path must no longer leave bundled foods stranded.
We refuse the deletion when any bundled catalog food still points
at the category (the catalog refresh would undo any reassignment
we made, so writing over it would silently revert). Non-bundled
catalog foods (user-created via **+ New Item**) and library foods
filed under the category are reassigned as today.

## Requirements

- **R-1** Edit Food screen renders without a full-page error when
  the food's `groupId` is `null` (Ungrouped), points at an active
  category, points at an archived category, or points at a category
  whose row no longer exists at all.
- **R-2** When the food's category is missing or archived, the
  category dropdown must still show that category as the selected
  value, visually distinguished from the active categories (e.g.
  with an "(archived)" or "(no longer available)" suffix and a
  muted style), so the user can see what the food was filed under
  and choose to keep it or move it.
- **R-3** Saving the form without touching the category dropdown
  must persist the food's stored `groupId` byte-identical to what
  it was on open. No silent defaulting to "Ungrouped".
- **R-4** The category dropdown must not crash when a stale
  `groupId` is supplied as `initialValue`. The fix is the source
  of the regression.
- **R-5** Deleting a category that has at least one bundled catalog
  food filed under it must be refused with a clear explanation.
  Deletion of a category that only has non-bundled catalog foods
  and/or library foods must reassign those rows to the user's
  destination (or `null` for Ungrouped) and archive the category,
  exactly as today.
- **R-6** Library screen renders without error while a food with a
  missing category exists.
- **R-7** No bundled catalog food's `groupId` differs from the
  bundled catalog's value after a category-deletion attempt
  followed by a launch that runs the catalog refresh.

## Acceptance Criteria

- [ ] **AC-1** Opening the Edit Food screen for a food whose
      `groupId` is missing from the active list renders the form
      without a crash or error page.
- [ ] **AC-2** Opening the Edit Food screen for a food whose
      `groupId` corresponds to an archived category renders the
      form without a crash or error page.
- [ ] **AC-3** In both AC-1 and AC-2 the food's original category
      is the selected value of the dropdown, and is visually
      distinguished from active categories.
- [ ] **AC-4** Saving without touching the category leaves the
      food's stored `groupId` byte-identical.
- [ ] **AC-5** Selecting a valid category and saving persists the
      new `groupId`; the food appears under the new category in
      the Library.
- [ ] **AC-6** Opening the editor and immediately backing out
      produces no change to the food's stored data.
- [ ] **AC-7** Deleting a category that has at least one bundled
      catalog food filed under it throws a typed error that the UI
      catches and surfaces as a snackbar. No food's `groupId` is
      mutated and the category itself is not archived.
- [ ] **AC-8** Deleting a category that contains only
      non-bundled catalog foods and/or library foods reassigns
      those rows to the user's destination (or `null`) and archives
      the category, exactly as today.
- [ ] **AC-9** Library screen renders without error while a food
      with a missing category exists.
- [ ] **AC-10** A second launch after a refused deletion
      produces no `groupId` change on any bundled catalog food
      (the catalog refresh would otherwise pull the original
      values back).

## Scenarios

### S-001: Edit Food opens without crash for a missing category
- Trigger: user opens a food whose `groupId` does not appear in
  the active group list (e.g. `food-group-dairy` was archived or
  never created because the user pre-created their own "Dairy").
- Precondition: the food is loaded into
  `FoodLibraryState._catalogFoods` (or `_foods`); the active group
  list is missing the food's `groupId`.
- Flow: open the **Edit Food** screen.
- Expected outcome: the form renders without throwing; the
  category dropdown shows the missing category as the selected
  value with a "(no longer available)" suffix and a muted style;
  the food's other fields pre-fill normally.
- Edge case of: none.

### S-002: Edit Food opens without crash for an archived category
- Trigger: user opens a food whose `groupId` corresponds to a
  `FoodGroup` with `isArchived = true` (group was archived, not
  deleted).
- Precondition: the food is loaded; the group is loaded with
  `includeArchived = true`; the active list filters it out.
- Flow: open the **Edit Food** screen.
- Expected outcome: the form renders without throwing; the
  category dropdown shows the archived category as the selected
  value with an "(archived)" suffix and a muted style.
- Edge case of: none.

### S-003: Saving without touching the category leaves groupId unchanged
- Trigger: user opens a food whose category is missing or
  archived, changes nothing, taps **Save**.
- Precondition: the form's category dropdown still has the
  missing/archived category selected (AC-3).
- Flow: open the editor, do not touch the dropdown, tap Save.
- Expected outcome: the persisted food's `groupId` is byte-
  identical to what it was before the editor opened. The food
  is not moved to Ungrouped. The food is not removed from its
  current category.
- Edge case of: S-001 / S-002.

### S-004: Selecting a valid category and saving persists the new groupId
- Trigger: user opens a food whose category is missing, picks an
  active category from the dropdown, taps Save.
- Precondition: same as S-001.
- Flow: open editor, change category dropdown to an active
  group, tap Save.
- Expected outcome: the persisted food's `groupId` is the chosen
  active group's id; the food appears under that group in the
  Library tab.
- Edge case of: none.

### S-005: Opening and immediately backing out produces no change
- Trigger: user opens the editor for any food and presses the
  system back gesture / Navigator.pop without tapping Save.
- Precondition: any food in the catalog cache.
- Flow: open editor, back out without saving.
- Expected outcome: the persisted food's row is byte-identical
  to what it was before opening (name, groupId, macros,
  referenceAmount, referenceLabel, etc. all unchanged).
- Edge case of: none.

### S-006: Deleting a category with bundled foods is refused
- Trigger: user opens the Library's Groups tab, taps the delete
  affordance on a category that has at least one bundled catalog
  food filed under it (e.g. delete **Dairy** while **Milk** /
  **Cheese** / **Yogurt** are catalog foods in that group).
- Precondition: `isBundledCatalogFood(id)` is true for at least
  one food whose `groupId` matches the category being deleted.
- Flow: confirm the delete dialog (Ungrouped or any destination).
- Expected outcome: a typed error is thrown from
  `deleteFoodGroupReassigningFoods`. The UI catches it and shows
  a snackbar explaining that the category cannot be deleted
  because it has catalog foods that would be stranded. The
  category is not archived. No food's `groupId` is mutated.
- Edge case of: none.

### S-007: Deleting a category with only non-bundled foods succeeds
- Trigger: user opens the Groups tab, deletes a category that
  contains only library foods and/or user-created catalog foods.
- Precondition: every food in the category has
  `isBundledCatalogFood(id) == false`.
- Flow: confirm the delete dialog (pick Ungrouped or another
  destination).
- Expected outcome: every affected food's `groupId` is the
  destination; the category is archived; the cache and
  repository are in sync. Behaviour matches the existing
  `deleteFoodGroupReassigningFoods` semantics for the
  non-bundled case.
- Edge case of: none.

### S-008: Library screen renders without error with a missing-category food present
- Trigger: a food exists with a `groupId` that no longer
  corresponds to an active category (post-deletion or skipped
  default seeding).
- Precondition: food is loaded.
- Flow: navigate to the Library tab.
- Expected outcome: the food row renders without throwing. No
  full-page error.
- Edge case of: S-001.

### S-009: Catalog refresh leaves bundled food categories untouched after a refused deletion
- Trigger: a refused deletion is followed by an app relaunch.
- Precondition: no food was mutated by the refused deletion.
- Flow: relaunch the app; `CatalogRefreshService.refresh()` runs.
- Expected outcome: no bundled food's `groupId` differs from the
  bundled catalog's value (the refresh is a no-op for those
  foods since no mutation happened).
- Edge case of: S-006.

### S-010: Default category seeding is skipped on name collision, and no food is left pointing at the skipped category
- Trigger: user pre-creates a category named "Dairy" before the
  default-seeding pass runs.
- Precondition: Hive's `_defaultFoodGroupsSeededKey` is `false`
  on first install; the user-created row exists at the time the
  default-seeding pass runs.
- Flow: launch the app; `_seedDefaultFoodGroups` runs.
- Expected outcome: `food-group-dairy` is not inserted (the
  user's "Dairy" wins on name match). The marker is set after
  the pass so the work is not retried. The bundled catalog
  foods that point at `food-group-dairy` are exactly the
  pre-existing set on the device (no new food is left
  referencing a missing category *as a result of this seeding
  pass* — the foods were already pointing at it because the
  catalog was loaded with that `groupId`).
- Edge case of: none.

> Note: S-010 is the second root cause (the seeding pass). The
> fix for AC-1 + AC-9 (don't crash in the editor / on the
> Library) handles the *consequence* of the collision at the UI
> layer. S-010 pins the seeding behaviour so a regression in the
> collision-skip logic is caught.

## Iteration 1

### DB Changes
None. No schema change. The fix lives in the form's category
dropdown (presentation + state wiring) and the deletion guard
in `FoodLibraryState.deleteFoodGroupReassigningFoods` (state
layer). The category collision-skip logic in
`HiveWorkoutRepository._seedDefaultFoodGroups` and
`MockWorkoutRepository.initialize` is already correct and is
covered by S-010.

### Backend Changes
- **`lib/state/food_library_state.dart`**
  - `deleteFoodGroupReassigningFoods` must throw a typed error
    when at least one bundled catalog food (`isBundledCatalogFood
    (id) == true`) has `groupId == id` for the group being
    deleted. The non-bundled reassignment path stays as-is.
  - Add a small public read-only helper that exposes whether a
    food's `groupId` is present in `activeFoodGroups` AND is
    not archived (for the form's "missing category" detection).
    The simplest API is to read `activeFoodGroups` + `foodGroups`
    (already cached) and resolve on the call site, but we also
    need a way to resolve the *display name* for a `groupId`
    that is no longer active (the form has no source for it). The
    form will resolve names by inspecting both
    `activeFoodGroups` (active name) and the full
    `foodGroups` cache (archived name) and falling back to a
    placeholder if both miss.
  - The form needs the **full** group list (including archived)
    on demand, so the form's `ListenableBuilder` will read
    `foodLibraryState.foodGroups` (the full cache) plus the
    already-known `activeFoodGroups` and derive the union.
- **`lib/features/nutrition/widgets/food_form.dart`**
  - In `_FoodFormState.build`, when computing the dropdown's
    `items`, build the active list as today, then look up the
    food's `groupId` (if non-null). If that id is not in the
    active list, append a synthetic "missing" item with the
    `groupId` as its value, labelled "(no longer available)" or
    similar, and rendered with `TextStyle(color:
    OmniTheme.colors.textMuted)`. If the id IS in the full
    group list but archived, append the actual archived group
    row labelled "(archived)" with the muted style. The
    synthetic-or-archived item is prepended (so it sits at the
    top of the items list with the selected value visible).
  - The dropdown's `initialValue` continues to be `_groupId`;
    because we always synthesise an item with that value when
    it is missing, `DropdownButtonFormField` no longer throws.
  - The existing `setState(() => _groupId = v)` `onChanged` is
    unchanged — selecting an item still updates the local
    `_groupId`, and saving still routes the new value through
    the existing `_onSave` pipeline. No silent defaulting.
- **`lib/features/nutrition/add_food_screen.dart`**
  - The delete confirmation flow catches the new typed error
    from `deleteFoodGroupReassigningFoods` and surfaces a
    snackbar with a clear "category has catalog foods that would
    be stranded" message. The user can re-pick a destination
    and retry, or cancel.

### Frontend Changes
- **Editor crash fix** (the bug): see above. Render-only.
- **Deletable-category guard**: see above. Snackbar copy lives
  in `add_food_screen.dart`; the typed error lives in
  `food_library_state.dart`.
- **Visual distinction for missing/archived categories**: a
  muted `Text` style for the synthetic-or-archived item. No new
  design tokens; reuse `OmniTheme.colors.textMuted` /
  `textSecondary`.
- **Library tab**: no code change. The Library renders foods
  through the cached group list, which already tolerates an
  unknown `groupId` (group header rendering reads `_groupId` and
  only groups foods by id when the group exists). The fix to
  the editor does not need a Library-tab change. AC-9 falls out
  of AC-1 + the existing rendering logic, but is pinned by S-008
  in case the rendering logic ever changes.

### Implementation Steps
1. **Phase 0** — write this plan.
2. **Phase 1** — no model/repo changes. Confirm via reading
   `lib/data/models/models.dart`, `workout_repository.dart`,
   `mock_workout_repository.dart`, and
   `hive_workout_repository.dart` that no DB-layer change is
   needed.
3. **Phase 2.1 (TDD, RED)** — write the failing tests below in
   `test/food_form_orphan_category_test.dart` and
   `test/food_library_state_delete_guard_test.dart`. Run
   `flutter test test/food_form_orphan_category_test.dart
   test/food_library_state_delete_guard_test.dart`. Confirm
   the new tests fail (the form-build test fails on a
   `FlutterError` from `DropdownButtonFormField`; the delete
   guard test fails because the current implementation does not
   refuse the deletion).
4. **Phase 2.2 (state)** — add the bundled-food check to
   `deleteFoodGroupReassigningFoods` and define the typed error
   (a `FoodGroupHasBundledFoodsError extends StateError`).
5. **Phase 2.3 (features)** — wire the catch in
   `add_food_screen.dart` so the user sees a snackbar.
6. **Phase 2.4 (widgets)** — patch the dropdown's items list
   in `food_form.dart` so a missing/archived `groupId` is
   synthesised as a selectable item.
7. **Phase 2.5 (buttons)** — no new buttons touched.
8. **Phase 2.6 (green)** — re-run the two new test files; run
   the broader food test suite:
   `flutter test test/food_form_orphan_category_test.dart
   test/food_library_state_delete_guard_test.dart
   test/food_form_decimals_and_autofocus_test.dart
   test/food_form_pick_saves_test.dart
   test/food_library_edit_test.dart
   test/food_library_persistence_test.dart
   test/food_library_state_test.dart
   test/food_library_test.dart
   test/food_category_groupid_migration_test.dart
   test/food_catalog_load_test.dart
   test/catalog_refresh_test.dart`.
9. **Phase 2.7 (doc hygiene)** — update `.github/agents/docs/`
   only where the change altered a claimed behaviour, structure,
   or invariant. The deletion-guard is a behaviour change;
   `widget_catalog/nutrition_widgets.md` documents the `FoodForm`
   widget, and a stale claim about "active groups + an
   Ungrouped `null` entry" needs to acknowledge the synthetic
   missing-category item. No other doc changes.

## Progress

### Phase 0
- [x] Plan written

### Phase 1
- [x] Confirm no DB-layer change is required (read models +
      repo files)
- [x] Confirm `defaultFoodGroups` collision-skip behaviour is
      covered by an existing test, or add one (S-010 — covered
      by `food_orphan_category_integration_test.dart`)

### Phase 2
- [x] TDD: failing tests for S-001..S-008 in
      `test/food_form_orphan_category_test.dart` and
      `test/food_library_state_delete_guard_test.dart` (RED
      confirmed)
- [x] State: add bundled-food guard in
      `FoodLibraryState.deleteFoodGroupReassigningFoods` +
      `FoodGroupHasBundledFoodsError` + new
      `reassignCatalogFoodsToGroup` repo method
- [x] Features: snackbar handling in
      `lib/features/nutrition/add_food_screen.dart`
- [x] Widgets: synthetic missing/archived dropdown item in
      `lib/features/nutrition/widgets/food_form.dart`
- [x] All tests green; `flutter analyze` clean on touched files
- [x] Doc hygiene pass: `widget_catalog/nutrition_widgets.md`,
      `state_management/nutrition_state.md`,
      `db_integration.md` updated

### Phase 3
- [x] Layer scoping stated (state, repositories, features, widgets)
- [x] AC verification (AC-1..AC-10 all met)
- [x] Scenario register cross-check (S-001..S-010 all have passing tests)
- [x] Doc falsification (Step 3.4 — no false claims)
- [x] Doc standard (Step 3.4b — no prohibited content added)
- [x] Global conventions verification (PASS)
- [x] Architecture compliance (PASS for in-scope layers)
- [x] Buttons (no new buttons touched → N/A)
- [x] Dead code (error class is used at throw + 2 catch sites + 1 helper)
- [x] Test coverage (every changed file mapped to a test)
- [x] Environment safety (no `dart:io`, no `Platform.*`, repository-only via interface)
- [x] DRY + clean code lens (helpers local to widget, snackbar copy localised)
- [x] Review verdict (✅ APPROVED)

## Feedback

(empty)

---

### Phase 0 Complete ✓
### Phase 1 Complete ✓
### Phase 2 Complete ✓
### Phase 3 Complete ✓
