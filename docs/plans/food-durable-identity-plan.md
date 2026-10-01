# Food Durable Identity Plan

## Overview

The food database links saved "Foods I Eat" entries to their catalog source by comparing names and nutrition values, instead of using a durable identifier. This causes:
1. Edits to library foods don't propagate to "Foods I Eat"
2. Removing and re-adding creates duplicates instead of reattaching
3. Food images don't update in "Foods I Eat" after library changes

The fix adds a `catalogId` field to track the durable link between user library foods and their catalog source.

## Requirements

- Add `catalogId` field to Food model to store the linked catalog food's ID
- Update `addCatalogFoodToLibrary` to set this field when creating a library copy
- Replace value-based matching in `libraryIdFor` with `catalogId` lookup
- Ensure edits to catalog foods propagate to linked library foods
- Prevent duplicate records when adding an already-linked food
- Keep consumed-log entries frozen at their logged-time values (regression guard)
- Update UI to show current library food image (not cached copy)

## Acceptance Criteria

- [x] Editing a library food's calories/macros updates values in "Foods I Eat"
- [x] Renaming a library food updates name in "Foods I Eat" without breaking link
- [x] Consumed-log entries created before an edit retain original values
- [x] Adding a food already in library does not create duplicate
- [x] Remove-then-re-add reuses existing food record
- [x] "Foods I Eat" displays current library food image

## Scenarios

### S-001: Edit propagates to Foods I Eat
- Trigger: User edits a catalog food's calories/macros/name
- Precondition: Food is linked to "Foods I Eat"
- Flow: Edit the food → the linked entry reflects new values
- Expected outcome: Library food changes automatically appear in "Foods I Eat"

### S-002: No duplicate on re-add
- Trigger: User adds a food already in their library
- Precondition: Food already linked to "Foods I Eat"
- Flow: Attempt to add the same food again
- Expected outcome: No new record created; existing record reused

### S-003: Remove and re-add reconnects
- Trigger: User removes linked food, then re-adds same catalog food
- Precondition: Food was linked, then removed
- Flow: Remove → Re-add same catalog food
- Expected outcome: Reattaches to existing library food, not new copy

### S-004: Image updates in Foods I Eat
- Trigger: User adds/changes image on a catalog food
- Precondition: Food has image, linked to "Foods I Eat"
- Flow: Add image to catalog food → check "Foods I Eat"
- Expected outcome: "Foods I Eat" shows the new image

### S-005: History stays frozen
- Trigger: User logs food → catalog food is edited → view past log
- Precondition: Consumed log entry exists before edit
- Flow: Log food → Edit source food → View historical log
- Expected outcome: Historical log shows original values, not edited values

## Iteration 1

### DB Changes

Add `catalog_id` column to foods table:
```sql
-- In scripts/sqlite_schema.sql
ALTER TABLE foods ADD COLUMN catalog_id TEXT REFERENCES foods(id);
```

### Backend Changes

1. **Food Model** (`lib/data/models/models.dart`):
   - Add `catalogId` field (String?, only for non-catalog foods)
   - Update `fromMap`/`toMap` to handle the new field
   - Add to `copyWith`

2. **FoodLibraryState** (`lib/state/food_library_state.dart`):
   - Modify `addCatalogFoodToLibrary` to set `catalogId` when creating library copy
   - Replace `_matchesIdentity` logic in `libraryIdFor` with `catalogId` lookup
   - Update `catalogIdFor` to return the stored `catalogId` value
   - Add method to propagate catalog edits to linked library foods

### Frontend Changes

1. **Food Form/Edit Screen**: Display current image from library food's `imagePath` (already works if we propagate correctly)

### Implementation Steps

1. Add `catalogId` field to Food model
2. Update fromMap/toMap serialization
3. Update MockWorkoutRepository seed data handling
4. Update addCatalogFoodToLibrary to set catalogId
5. Replace value-matching with catalogId lookup in libraryIdFor
6. Add catalog edit propagation to linked library foods
7. Update tests to verify durable linkage
8. Verify frozen history (existing consumed logs unchanged)

## Progress

- [x] Create plan file
- [x] Add catalogId field to Food model
- [x] Update serialization (fromMap/toMap)
- [x] Update repository interface if needed
- [x] Update mock repository
- [x] Update addCatalogFoodToLibrary to set catalogId
- [x] Replace _matchesIdentity with catalogId lookup
- [x] Add catalog edit propagation
- [x] Run tests and fix issues
- [x] Verify frozen history
- [x] Fix legacy library food upgrade (catalogId set on add)
- [x] Fix legacy library food propagation via identity match
- [x] Add tests for new behavior

### Phase 0 Complete ✓
### Phase 1 Complete ✓
### Phase 2 Complete ✓

## Feedback

