# Feature: Daily Nutrition — Foods I Eat Empty State (Fix)

## Overview

Currently, the "Foods I Eat" card only shows an empty state when the user has **both** zero foods **and** zero food categories. Since the app ships with 9 default food categories preloaded on every install, a brand-new user never sees the empty state—they see a meaningless placeholder instead. This fix changes the logic to show the empty state whenever the user's personal foods list is empty, regardless of how many categories exist (0, 9, or custom). The empty-state message will be reworded to clearly tell the user their Foods I Eat list is empty and point them to the pencil control.

## Requirements

1. Empty state appears whenever `foods.isEmpty`, independent of category count
2. New message: tells user "Foods I Eat list is empty" and points to pencil control
3. Remove "No foods in library" string entirely (misleading)
4. Empty state uses existing muted/secondary text treatment (no new visual weight)
5. No CTA button/icon added inside empty state; pencil in header is the sole entry point
6. Add one food → empty state disappears, food renders in category group
7. Remove last food → empty state reappears immediately

## Acceptance Criteria

- [ ] On fresh install (default categories present, zero foods): card displays empty-state line
- [ ] Empty-state line reads "Your Foods I Eat list is empty. Tap the pencil to add foods." (exact wording discretionary, but references "Foods I Eat" and pencil)
- [ ] String `No foods in library` does not appear anywhere on Daily Nutrition screen
- [ ] Adding 1 food removes empty state; food renders under its category group on next state change
- [ ] Removing last food brings empty state back
- [ ] Empty state visible with 0, 9, or custom category counts (category count has zero effect)
- [ ] No new CTA button, floating action button, or tappable element in empty state
- [ ] Empty-state line uses existing muted/secondary text treatment (no new colors/weight)

## Scenarios

### S-001: Fresh Install, Default Categories + Empty Foods
- Trigger: App opens for first time; user taps "Daily Nutrition"
- Precondition: 9 default food categories present; zero foods in personal list
- Flow: 1) NutritionScreen mounts → 2) FoodLibraryState loads groups + foods → 3) _FoodLibraryBrowseSection renders → 4) Empty state appears
- Expected outcome: Card displays single muted line: "Your Foods I Eat list is empty. Tap the pencil to add foods." No category headers, no food rows, no loading spinner
- Edge case of: none

### S-002: Add First Food
- Trigger: User taps pencil → AddFoodScreen → selects food from catalog → taps Add
- Precondition: Empty Foods I Eat list with empty state visible
- Flow: 1) Food copied to library via `addCatalogFoodToLibrary` → 2) FoodLibraryState notifies → 3) _FoodLibraryBrowseSection rebuilds → 4) foods is no longer empty
- Expected outcome: Empty state disappears; one food row renders under its category group; no muted line visible
- Edge case of: none

### S-003: Remove Last Food
- Trigger: User opens Manage Library, removes the only food from their list
- Precondition: One food in Foods I Eat list; card renders the food row
- Flow: 1) Food deleted via `removeFood` → 2) FoodLibraryState notifies → 3) _FoodLibraryBrowseSection rebuilds → 4) foods is empty again
- Expected outcome: Card switches back to empty state immediately; muted line reappears; food row is gone
- Edge case of: none

### S-004: Category Count Independence
- Trigger: Same UI state (empty foods list) observed under varying category counts
- Precondition: Food library archive/create operations completed; foods list remains empty
- Flow: 1) Vary categories (archive 8 of 9, leaving 1; archive all → 0; create custom group) → 2) Revisit NutritionScreen each time
- Expected outcome: Empty state visible in every variant; category count has zero effect on its presence
- Edge case of: none

### S-005: String Regression Check
- Trigger: Search Daily Nutrition screen tree for "No foods in library" text
- Precondition: Fresh install; any food state (empty or populated)
- Flow: Assert text does not appear anywhere
- Expected outcome: String is not found; all previous occurrences replaced or removed
- Edge case of: none

## Iteration 1

### DB Changes
None — no schema changes.

### Backend Changes
- **FoodLibraryState**: No changes required; the state already exposes `foods` and `foodGroups` as needed.
- **WorkoutRepository interface**: No changes; existing methods suffice.

### Frontend Changes
- **lib/features/nutrition/nutrition_screen.dart** (`_FoodLibraryBrowseSection.build()`):
  - Change empty-state check from `if (groups.isEmpty && foods.isEmpty)` to `if (foods.isEmpty)`
  - Replace text "No foods in library" with "Your Foods I Eat list is empty. Tap the pencil to add foods."
  - Maintain existing muted text styling (no new colors/weight)
  - Keep `SizedBox(height: 48, ...)` sizing (no layout changes)
- **docs/widget_catalog.md**:
  - Update the `FoodLibraryBrowseSection` table entry to reflect new empty state condition: `foods.isEmpty` (instead of `foodGroups.isEmpty && foods.isEmpty`)
  - Update the Renders table to show the new message text
- **docs/navigation_and_screens.md**:
  - Update any reference to the "Foods I Eat" empty state if present

### Implementation Steps
1. Update `_FoodLibraryBrowseSection.build()` empty-state condition and message
2. Rewrite existing test: "shows muted "No foods in library" line when library is empty"
   - Remove the archive-all-groups loop; keep default groups active
   - Assert empty state appears with groups present
3. Add test: "empty state appears with default categories present"
4. Add test: "empty state disappears when food is added"
5. Add test: "empty state reappears when last food is removed"
6. Add test: "empty state visible regardless of category count"
7. Add regression test: "`No foods in library` string not present on screen"
8. Audit existing tests (food_library_test.dart, nutrition_test.dart, etc.) for tests that archive groups purely to force empty state and correct or remove them
9. Update widget_catalog.md and navigation_and_screens.md docs

## Progress

- [x] Phase 0: Plan
- [x] Phase 1: Data Layer (no changes required)
- [x] Phase 2: Logic & UI
  - [x] Rewrote empty state condition: `foods.isEmpty` (was `groups.isEmpty && foods.isEmpty`)
  - [x] Updated empty state message to "Your Foods I Eat list is empty. Tap the pencil to add foods."
  - [x] All 6 new/rewritten tests in FoodLibraryBrowse – empty group pass
  - [x] All existing FoodLibraryBrowse tests (10 total) pass
  - [x] All CalorieRingCard tests (17) pass
  - [x] Updated widget_catalog.md documentation
- [x] Phase 3: Code Review
  - [x] Layers in scope: features, tests, docs
  - [x] All acceptance criteria verified ✅
  - [x] Global conventions compliance verified ✅
  - [x] Test coverage verified ✅
  - [x] Doc hygiene verified ✅
  - [x] Review verdict: APPROVED

### Phase 3 Complete ✓

## Feedback

(none yet)
