# Food Last Amount Plan

## Overview

Logging a food the user eats often currently requires re-entering the portion every time, even when it rarely changes. The current pre-fill in `LogFoodRow` already restores the amount from today's `ConsumedFood` row when the food is logged on the same day, but falls back to the food's reference serving size when the food has not been logged today. That fallback forces the user to re-type the same number every day for every regular food.

This plan adds a single remembered "last amount" per food that is overwritten each time the user successfully logs the food. The next time the user goes to log the same food, the amount input is pre-filled with that remembered value so the common case becomes confirm-and-go. When a food has never been logged (no remembered amount), the input falls back to the food's defined reference serving size. The pre-filled value is always editable; an unsaved edit in an unlogged row never mutates the stored value, and the auto-commit on a logged row updates it only when the user actually commits.

Depends on the food-identity fix (`food-durable-identity-plan.md`); `catalogId` linkage means a remove-then-re-add preserves the food id and therefore the `lastAmountConsumed` field.

## Requirements

- Add a `lastAmountConsumed` field to the `Food` model. It stores the amount, in the food's own unit (grams for grams-type, count-multiplier for count-type), that the user last successfully logged. Null when the food has never been logged.
- Update `NutritionState.logConsumedFood` / `logConsumedFoodAt` to write the new amount to the food's `lastAmountConsumed` on every successful save.
- Update `LogFoodRow._defaultAmount` to prefer `food.lastAmountConsumed` over the hardcoded serving-size default. The existing today-log pre-fill still wins over both (so an explicit edit on the same day stays sticky).
- Round-trip the field through `Food.fromMap` / `toMap` / `copyWith` for both Hive and SQLite.
- Keep the frozen-snapshot contract on `ConsumedFood` intact — `lastAmountConsumed` is on the `Food` row, not on the `ConsumedFood` snapshot.

## Acceptance Criteria

- [ ] Logging a food a second time (on a later day) pre-fills the amount from the most recent prior log of that food.
- [ ] Logging a food for the first time (no prior amount) pre-fills the food's defined serving size.
- [ ] The pre-filled amount is editable; editing it in an unlogged row does not alter the stored `lastAmountConsumed` until that log is saved.
- [ ] After saving a log with a changed amount, the next log of that food pre-fills the newly changed amount.
- [ ] The `Food` row's `lastAmountConsumed` survives a remove-then-re-add of a catalog copy (catalogId linkage).

## Scenarios

### S-001: Second log defaults to the first log's amount
- Trigger: User has previously logged Chicken Breast at 150 g (loggedAtMs in the past). User taps log on Chicken Breast in Foods I Eat.
- Precondition: `food.lastAmountConsumed == 150.0`; the food is not logged today.
- Flow: Open Foods I Eat → see Chicken Breast row → amount field shows 150.
- Expected outcome: Amount input is pre-filled with 150.0 (the remembered last amount).
- Edge case of: none.

### S-002: First-ever log defaults to the food's serving size
- Trigger: User has just added Chicken Breast to library from the catalog and never logged it.
- Precondition: `food.lastAmountConsumed == null`; the food is not logged today.
- Flow: Open Foods I Eat → see Chicken Breast row → amount field shows the reference amount (100 for grams-type, 1.0 for count-type).
- Expected outcome: Amount input is pre-filled with the food's defined serving size.

### S-003: Saving with a changed amount updates the remembered value
- Trigger: User has `food.lastAmountConsumed == 150`. User logs 200 and saves. User then unlogs (or moves to next day) and re-opens Foods I Eat.
- Precondition: First save commits 200.
- Flow: Save at 200 → next visit sees amount = 200.
- Expected outcome: `food.lastAmountConsumed` is now 200.0. The next log pre-fills with 200.

### S-004: Editing the pre-filled value in an unlogged row does not alter the stored value
- Trigger: `food.lastAmountConsumed == 150`. User opens the row and types 300 in the amount input but does NOT log (does not tap the thumb toggle to commit).
- Precondition: The food is unlogged today (no ConsumedFood row exists for today).
- Flow: Type 300 → close the screen without committing → reopen Foods I Eat.
- Expected outcome: `food.lastAmountConsumed` is still 150.0. The amount input still pre-fills with 150.

### S-005: Today-log pre-fill still wins over the remembered value
- Trigger: User logged Chicken Breast at 200 g earlier today, but the food's `lastAmountConsumed` was 150 (yesterday's value).
- Precondition: A `ConsumedFood` row exists for today with `amountConsumed == 200`.
- Flow: Open Foods I Eat → see Chicken Breast row.
- Expected outcome: Amount input pre-fills with 200 (today's value), not 150 (yesterday's remembered value). Toggling off and re-on again restores 200, not 150.

### S-006: Remove-then-re-add preserves the remembered amount
- Trigger: User logged Chicken Breast at 175 g. User removes it from library, then re-adds it from the catalog.
- Precondition: `catalogId` linkage means re-add returns the existing library food id, so the same `Food` row is preserved (per `food-durable-identity-plan.md`).
- Flow: Log → remove → re-add → open Foods I Eat.
- Expected outcome: Amount pre-fills with 175 (the same library food's `lastAmountConsumed` survived).

## Iteration 1

### DB Changes

Add `last_amount_consumed` column to foods table:

```sql
-- In scripts/sqlite_schema.sql
ALTER TABLE foods ADD COLUMN last_amount_consumed REAL;
```

- Nullable: NULL when the food has never been logged.
- Stored in the food's own unit (REAL so it accepts fractional grams).
- No index required; lookup is by primary key.

### Backend Changes

1. **Food Model** (`lib/data/models/models.dart`):
   - Add `lastAmountConsumed` field (double?, nullable).
   - Update `fromMap` / `toMap` to handle the new field (read `m['last_amount_consumed']` and write `'last_amount_consumed': lastAmountConsumed`). Missing key → null.
   - Add a `_foodCopyWithUnset`-style sentinel for nullable `double?` and wire it through `copyWith` so callers can clear the field.
   - Add the field to the constructor.

2. **`WorkoutRepository` interface** (`lib/data/repositories/workout_repository.dart`):
   - No new methods. `lastAmountConsumed` is read via `getFoodById(foodId)` and written via `updateFood(food.copyWith(lastAmountConsumed: amount))`. Keeps the interface small.

3. **`MockWorkoutRepository`** (`lib/data/repositories/mock_workout_repository.dart`):
   - No new methods. The existing `updateFood` already persists any field on the food. Seed data does not need to set `lastAmountConsumed`; it stays null on every seeded food.

4. **`HiveWorkoutRepository`** (`lib/data/repositories/hive_workout_repository.dart`):
   - No new methods. The existing `updateFood` writes the full `toMap()`, which now includes `last_amount_consumed`.

5. **`SeedData`** (`lib/mock/seed_data.dart`):
   - No changes needed. The field defaults to null on every seeded food, matching the "never logged" contract.

6. **State layer — `NutritionState`** (`lib/state/nutrition_state.dart`):
   - In `logConsumedFood` and `logConsumedFoodAt`: after a successful `createConsumedFood` / `updateConsumedFood` write, also update the food's `lastAmountConsumed` via `repo.updateFood(food.copyWith(lastAmountConsumed: amount, updatedAtMs: now))`. The food row is owned by the repository — a write-through keeps it in sync.
   - On update failure: leave `lastAmountConsumed` untouched (the `ConsumedFood` row is already not written; the prior behavior is to no-op).
   - On create failure: same — no-op.
   - On success: do not throw if the food row update fails (the `ConsumedFood` row is the source of truth for today's log; `lastAmountConsumed` is best-effort and a transient repo failure here should not block logging). Log to debug print only.
   - The state does NOT need a separate `lastAmountForFood(Food food)` getter — callers can read `food.lastAmountConsumed` directly off the food instance they already hold.

### Frontend Changes

1. **`LogFoodRow`** (`lib/features/nutrition/widgets/log_food_row.dart`):
   - Update `_defaultAmount` to consult `widget.food.lastAmountConsumed` first; fall back to `referenceAmount` (grams) or `1.0` (count) when null.
   - The `initState` pre-fill logic stays: today's `ConsumedFood` row still wins over both.
   - `didUpdateWidget` already resets to `_defaultAmount` on a food-id change; that path now naturally picks up the remembered amount when a row rebuilds with a different library food.
   - No new widgets.

2. **No changes to `AddFoodScreen` / `EditFoodScreen`**: the form is for editing the food's nutrition metadata, not the remembered amount.

### Implementation Steps

1. Add `lastAmountConsumed` to Food model (`models.dart`).
2. Update `fromMap` / `toMap` / `copyWith` to round-trip the field.
3. Update `NutritionState.logConsumedFood` and `logConsumedFoodAt` to write through to the food's `lastAmountConsumed` after a successful ConsumedFood write.
4. Update `LogFoodRow._defaultAmount` to prefer `food.lastAmountConsumed`.
5. Add SQL column to `scripts/sqlite_schema.sql`.
6. Add tests in `test/state_test.dart` (NutritionState group) for S-001 .. S-006.
7. Add a round-trip test in `test/models_test.dart` for the new Food field.
8. Add an interaction-flow test in `test/interaction_flow_test.dart` for the `LogFoodRow` pre-fill behavior.
9. Run `flutter test` and `flutter analyze`.

## Progress

- [x] Phase 0 — Plan authored
- [x] Phase 0.5 — Red tests written (model round-trip + state write-through + LogFoodRow pre-fill)
- [x] Red run confirmed: `flutter analyze` reports `lastAmountConsumed` undefined in `test/models_test.dart`, `test/state_test.dart`, `test/nutrition_test.dart`
- [x] Phase 1 — Data layer
  - [x] Add `lastAmountConsumed` to Food model (field + constructor)
  - [x] Update `Food.fromMap` / `toMap` / `copyWith`
  - [x] Update SQL schema with `last_amount_consumed` column
  - [x] Add Food round-trip test (null + value + missing-key + copyWith) in `test/models_test.dart`
  - [x] Doc hygiene: update `data_models.md` and `db_integration.md`
- [x] Phase 2 — Logic & UI
  - [x] Wire `logConsumedFood` and `logConsumedFoodAt` to write through to the food's `lastAmountConsumed` (private `_writeThroughLastAmount` helper)
  - [x] Update `LogFoodRow._defaultAmount` to prefer `food.lastAmountConsumed`
  - [x] Add state tests for S-001 .. S-006 in `test/state_test.dart` (NutritionState group)
  - [x] Add `LogFoodRow` pre-fill interaction tests (S-001 / S-002 / S-004 / S-005) in `test/nutrition_test.dart`
  - [x] Run `flutter test` — all green (84 models, 211 state, 56 nutrition, 148 food-library tests)
  - [x] Doc hygiene: update `state_management.md` and `widget_catalog.md`
- [x] Phase 3 — Code review
  - [x] Layer scoping: models, state, features (widgets), docs in scope; repositories, core, mock skipped
  - [x] Acceptance criteria verified (5/5, with AC-5 scoped to state-layer re-add no-op)
  - [x] Scenario register cross-checked (S-001..S-006 all have ≥1 test)
  - [x] Doc hygiene table reviewed (data_models, db_integration, state_management, widget_catalog updated)
  - [x] Global conventions verified (PASS / N/A; no `dart:io`, `Platform.is*`, hardcoded colors, or button shape regressions)
  - [x] Architecture compliance verified (models pure Dart; state only repo interface; widgets no repo access; no business logic in widgets)
  - [x] Buttons N/A (no buttons added)
  - [x] Dead code: none (state-layer `addCatalogFoodToLibrary` still referenced, no orphaned helpers)
  - [x] Test coverage: 5 model + 7 state + 4 widget interaction tests; total 16 new tests, all green
  - [x] Environment safety: confirmed no `dart:io`, no `Platform.is*`, repo interface used throughout
  - [x] DRY + clean code: `_writeThroughLastAmount` private helper; preference order documented in `_defaultAmount`; no magic numbers; no duplicated logic

### Phase 0 Complete ✓
### Phase 1 Complete ✓
### Phase 2 Complete ✓
### Phase 3 Complete ✓
