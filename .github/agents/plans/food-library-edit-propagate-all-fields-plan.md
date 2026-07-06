# Food Library Edit — Propagate All Editable Fields (including group)

## Overview

When the user edits a catalog food via the **Manage Food Library → Library tab** (or the My Foods tab for a user-created catalog food), `FoodLibraryState.updateCatalogFood` already propagates the new values to any linked library copy via `_propagateCatalogEditToLinkedFoods`. The propagation covers name, unit type, reference, macros, notes, and image — but two fields are mishandled today:

1. **`groupId`** — the propagation deliberately preserves the library copy's existing `groupId` (`groupId: libFood.groupId` in `copyWith`), so changing the catalog food's group does **not** appear in the linked library food / Foods I Eat row. The user expects every editable field — including the food's group — to propagate.
2. **`lastAmountConsumed`** — the per-user remembered portion from `NutritionState` (food-last-amount plan). The propagation does not pass `lastAmountConsumed`, so the `copyWith` falls through to `updatedCatalogFood.lastAmountConsumed`, which is always `null` on catalog rows. The library copy's remembered amount is silently wiped.

The fix is a surgical edit to `_propagateCatalogEditToLinkedFoods`: drop the `groupId` override so the new value from `updatedCatalogFood` flows through, and explicitly preserve `lastAmountConsumed` from the library copy.

## Requirements

- `groupId` changes on a catalog food must propagate to every linked library copy.
- `lastAmountConsumed` on the linked library copy must be preserved across catalog edits (catalog rows are always `null` for this field, so the propagation must explicitly carry the library value forward).
- All other currently-propagated fields (name, unit type, reference, macros, notes, image) continue to propagate. No regression in the existing `food_library_edit_test.dart` sync test.
- Catalog rows are still `isCatalog = true`; the library copy still gets `isCatalog = false` and `catalogId` preserved.
- Frozen `ConsumedFood` snapshots for past days remain untouched (no regression — they read the snapshot, not the live food row).

## Acceptance Criteria

- [ ] Updating a catalog food's `groupId` propagates the new `groupId` to linked library copies (both durable `catalogId` links and legacy identity-matched copies).
- [ ] Updating a catalog food's `groupId` to a different group (or to `null`) is reflected on the next read of the linked library row.
- [ ] Updating a catalog food does **not** clobber the linked library copy's `lastAmountConsumed`.
- [ ] All previously-passing tests (`food_library_edit_test.dart`, `my_foods_unification_test.dart`, `food_library_state_test.dart`, `food_catalog_load_test.dart`, `db_seed_test.dart`) still pass.

## Scenarios

### S-001: Group change on catalog food propagates to Foods I Eat library copy
- Trigger: User opens a catalog food via the **Library** tab in Manage Food Library → Edit Food screen → changes `groupId` from `group-A` to `group-B` → Save.
- Precondition: The catalog food has been added to the user's library (linked via `catalogId`).
- Flow: `FoodLibraryState.updateCatalogFood` runs → `_propagateCatalogEditToLinkedFoods` builds the linked library copy.
- Expected outcome: The linked library row's `groupId` is `group-B`. The row re-renders in **Foods I Eat** under the `group-B` group header on the next `notifyListeners()` cycle.
- Edge case of: none (TRIVIAL feature — directly satisfies the user's stated requirement).

### S-002: Group change to `null` (Ungrouped) propagates
- Trigger: Same as S-001, but the new `groupId` is `null`.
- Expected outcome: The linked library row's `groupId` is `null`; Foods I Eat renders the row under the synthetic **Ungrouped** section.

### S-003: `lastAmountConsumed` is preserved across a catalog edit
- Trigger: User logs a linked library food once → its `lastAmountConsumed` is set to `100.0` via `NutritionState` → user then edits the catalog food.
- Precondition: Linked library row has a non-null `lastAmountConsumed`.
- Flow: `updateCatalogFood` runs → propagation rebuilds the linked library row.
- Expected outcome: The linked library row's `lastAmountConsumed` is still `100.0`. The next `LogFoodRow` pre-fill still uses `100.0`.

### S-004: Legacy identity-matched copy gets the new group too
- Trigger: A legacy library food (no `catalogId`) was matched to the catalog food by identity. User edits the catalog food's `groupId`.
- Precondition: The library copy has been upgraded to use `catalogId` after this edit (existing behavior).
- Expected outcome: The upgraded library copy's `groupId` is the new catalog value.

## Iteration 1

### DB Changes

None. The `app_food` schema already supports `group_id` and `last_amount_consumed`; both fields are written by the corrected propagation path with no migration.

### Backend Changes

1. **`lib/state/food_library_state.dart` — `_propagateCatalogEditToLinkedFoods`**:
   - For each linked library row (durable `catalogId` match and legacy identity match):
     - Build `updatedLibFood` via `updatedCatalogFood.copyWith(...)`.
     - Drop the `groupId: libFood.groupId` override so the catalog's new `groupId` flows through.
     - Add `lastAmountConsumed: libFood.lastAmountConsumed` to preserve the per-user remembered portion.
     - Keep `id`, `catalogId`, `isCatalog = false`, `createdAtMs`, `updatedAtMs` overrides as today.
   - Update the doc comment on the method to call out the two-field invariant.

### Frontend Changes

None. The screens (`AddFoodScreen`, `NutritionScreen`, `EditFoodScreen`) already react to `notifyListeners()` and re-render group sections, so the corrected propagation is visible automatically.

### Implementation Steps

1. Add failing tests in `test/food_library_edit_test.dart`:
   - `propagates groupId change to linked library copy` (durable-link path).
   - `propagates groupId change to legacy identity-matched library copy`.
   - `propagates null groupId (Ungrouped) to linked library copy`.
   - `preserves lastAmountConsumed on the linked library copy across a catalog edit`.
2. Run `flutter test test/food_library_edit_test.dart` and confirm the new tests fail (red).
3. Apply the two-line surgical edit in `_propagateCatalogEditToLinkedFoods`.
4. Re-run the test file. All four new tests pass; the existing sync test still passes.
5. Run the broader food-related test suites to confirm no regressions:
   - `test/food_library_state_test.dart`
   - `test/my_foods_unification_test.dart`
   - `test/food_catalog_load_test.dart`
   - `test/db_seed_test.dart`
   - `test/state_test.dart` (covers `lastAmountConsumed` write-through).
6. Update the doc comment on `_propagateCatalogEditToLinkedFoods` to document the two-field invariant (group flows through; `lastAmountConsumed` is preserved).

## Progress

- [x] Create plan file
- [x] Add failing tests for group + lastAmountConsumed propagation
- [x] Confirm tests fail (red)
- [x] Apply surgical fix in `_propagateCatalogEditToLinkedFoods`
- [x] Confirm tests pass (green)
- [x] Run broader food-related test suites for regression (full suite 1892 passed, 5 skipped)
- [x] Update doc comment on the method
- [x] Mark Phase 0 Complete ✓
- [x] Mark Phase 2 Complete ✓

### Phase 0 Complete ✓
### Phase 2 Complete ✓

## Code Review: ✅ Approved

Layers in scope: state
Layers skipped: models, repositories, core, widgets, docs

PASS (5 rules): timestamps-source-data, reuse-canonical-owner, env-safety (N/A), N/A (5: units, theme-tokens, omni-surface, effort-kind, button-shape — no UI changes)
Critical: 0 | Warnings: 0 | Suggestions: 1

💡 SUGGEST | lib/state/food_library_state.dart:687,711 | `isArchived` also flows through from `updatedCatalogFood` to the linked library row in both branches (catalog edit affects library archive state). | The catalog UI does not expose archive today, so this is latent, but worth keeping in mind if archive becomes editable. If you want to be conservative, add `isArchived: libFood.isArchived` (and the legacy variant) to the two `copyWith` calls so the library row's archive state stays independent of the catalog's. | @developer (non-blocking)

### Phase 3 Complete ✓