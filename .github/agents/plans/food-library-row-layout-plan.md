# Feature: Food Library Row Layout & Amount Behavior Update

## Overview

Update the `LogFoodRow` widget on the Nutrition details screen to improve layout and amount input behavior:
1. New layout: checkbox left, food title + macros in middle (expanded), amount textbox right with label beneath
2. Amount behavior: for grams/ml/etc. types = pure amount (not multiplier), for units = multiplier

## Requirements

### Layout
- Checkbox remains on the left side of each row
- Food title (max 1 line overflow) + macros grid in the middle, taking remaining horizontal space
- Amount textbox moves to the right side of the row
- Unit label (g/ml/units) displayed **beneath** the amount textbox, not beside it
- Total height accommodates the label beneath the textbox

### Amount Behavior
- For `FoodUnitType.grams`: the input is the **actual amount**, not a multiplier. Example: reference is 100g macros, user enters 50 → that's 50g consumed (not 50×100g)
- For `FoodUnitType.count`: the input acts as a **multiplier** (current behavior). Example: reference is 1 egg, user enters 0.5 → that's half the egg

### Validation
- Grams: any positive number is valid (including decimals)
- Count: any positive number is valid (including decimals for portions like 0.5 egg)

## Acceptance Criteria

- [ ] Checkbox positioned on the left
- [ ] Food title with max 1 line overflow + macros grid in middle (expanded)
- [ ] Amount textbox on the right side
- [ ] Unit label (g/ml/units) beneath the amount textbox
- [ ] For grams type: entering 50 when reference is 100g means 50g consumed
- [ ] For count type: entering 0.5 when reference is 1 egg means 0.5 eggs consumed (multiplier)
- [ ] Default amount is referenceAmount for grams (e.g., 100), 1 for count
- [ ] Pre-fill from existing log works correctly for both types

## Scenarios

### S-001: Grams type - pure amount input
- Trigger: User sees a grams-type food (per 100g) in the Food Library
- Precondition: Food has unitType = grams, referenceAmount = 100
- Flow: User types "50" in the amount field
- Expected outcome: Food is logged as 50g consumed (not 50×100g = 5000g)
- Edge case of: none

### S-002: Count type - multiplier input
- Trigger: User sees a count-type food (per 1 egg) in the Food Library
- Precondition: Food has unitType = count, referenceAmount = 1
- Flow: User types "0.5" in the amount field
- Expected outcome: Food is logged as 0.5 eggs consumed (half an egg)
- Edge case of: none

### S-003: Layout - right-aligned amount with label beneath
- Trigger: User views a food row in the Food Library
- Precondition: None
- Flow: User observes the row layout
- Expected outcome: Checkbox left, food name + macros middle (expanded), amount + label right-aligned
- Edge case of: none

## Iteration 1

### DB Changes
- N/A (no schema changes)

### Backend Changes
- N/A (no backend changes)

### Frontend Changes
- Update `LogFoodRow` layout in `lib/features/nutrition/widgets/log_food_row.dart`:
  - Restructure Row to have: checkbox | Expanded(food name + macros) | amount column
  - Move amount textbox to the right side
  - Add unit label beneath the textbox
  - Change maxLines for food title from 2 to 1
- Update amount calculation logic:
  - For grams: pass typed value directly as amountConsumed
  - For count: multiply by referenceAmount (current behavior)
- Update default values:
  - For grams: default = referenceAmount (e.g., 100)
  - For count: default = 1 (multiplier)

### Implementation Steps
1. Read and understand current LogFoodRow implementation
2. Restructure the build method layout
3. Update amount parsing logic based on unitType
4. Add unit label beneath textbox
5. Update tests to match new behavior

## Progress

- [x] Phase 0: Plan created
- [x] Phase 1: Data layer (N/A - no schema changes)
- [x] Phase 2: Implementation
- [x] Phase 3: Review

### Phase 0 Complete ✓

### Phase 1 Complete ✓ (N/A - no data layer changes)

### Phase 2 Complete ✓
- Updated LogFoodRow layout in `lib/features/nutrition/widgets/log_food_row.dart`
- Restructured Row to have: checkbox | Expanded(food name + macros) | Column(amount + label)
- Changed amount logic: grams = actual amount, count = multiplier
- Added unit label beneath the textbox
- Updated default values: grams = referenceAmount, count = 1
- Updated test in `test/nutrition_test.dart` to use actual amount for grams-type foods

### Phase 3 Complete ✓

## Feedback

