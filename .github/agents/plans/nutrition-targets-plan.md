# Feature: Daily Nutrition Targets

## Overview
Build a daily-targets configuration surface for the nutrition feature, in the Hub setup area alongside the app's other system-configuration screens. The user sets four numbers: a daily calorie target, and daily protein, carbs, and fat targets in grams. These are standing goals: editable any time, persistent across restarts and across days — not per-day entries. They are consumed by the rest of the feature as the "goal" side of every progress readout. Treat unset/blank targets as a valid state, not an error: the feature must stay usable when a user has logged food but never set a target.

## Requirements
- A new surface in the Hub setup area for nutrition targets.
- Four editable numeric fields: calories, protein, carbs, and fat.
- Values must persist across app restarts.
- The feature must handle unset/blank targets gracefully.
- Editing a target should immediately update all relevant UI components.
- No automatic target calculation is needed.

## Acceptance Criteria
- [ ] The setup area exposes exactly four editable numeric fields: calories, protein, carbs, fat.
- [ ] Entered values persist across app close/reopen.
- [ ] Values persist unchanged when the displayed day rolls over.
- [ ] A blank target produces no division artifact, "NaN", or crash anywhere; affected readouts fall back to consumed-only.
- [ ] Editing a target updates every progress readout's goal side immediately.

## Scenarios

### S-001: User sets targets for the first time
- Trigger: User navigates to the nutrition setup screen for the first time.
- Precondition: No nutrition targets are set.
- Flow:
    1. User opens the nutrition setup screen.
    2. The fields for calories, protein, carbs, and fat are empty.
    3. User enters values in all four fields.
    4. User saves the targets.
- Expected outcome: The entered values are saved and reflected in the UI.

### S-002: User edits existing targets
- Trigger: User navigates to the nutrition setup screen to change existing targets.
- Precondition: Nutrition targets are already set.
- Flow:
    1. User opens the nutrition setup screen.
    2. The fields display the currently saved target values.
    3. User modifies one or more of the target values.
    4. User saves the changes.
- Expected outcome: The new values are saved and the UI updates immediately.

### S-003: User clears a target value
- Trigger: User wants to remove a target value.
- Precondition: A value is set for a target.
- Flow:
    1. User opens the nutrition setup screen.
    2. User clears the value in one of the fields.
    3. User saves the changes.
- Expected outcome: The target is now considered "unset" and the UI adapts to show consumed-only values where that target was used.

### S-004: User logs food without setting targets
- Trigger: User logs a food item before setting any nutrition targets.
- Precondition: No nutrition targets are set.
- Flow:
    1. User logs a food item.
    2. User views a progress readout.
- Expected outcome: The progress readout displays the consumed nutrition values without showing any goal or progress percentage. No errors occur.

## Iteration 1

### DB Changes
1. [x] Create a new model `NutritionTarget` with fields: `calories`, `protein`, `carbs`, `fat`. These should be nullable doubles or integers.
2. [x] Add a method to `WorkoutRepository` to get and save `NutritionTarget`.
3. [x] Implement the new repository methods in `HiveWorkoutRepository` and `MockWorkoutRepository`.

### Backend Changes
1. [x] Create a `NutritionState` ChangeNotifier.
2. [x] `NutritionState` should load the `NutritionTarget` from the `WorkoutRepository`.
3. [x] `NutritionState` should provide a method to save the `NutritionTarget`.
4. [x] `NutritionState` should notify listeners when targets change.

### Frontend Changes
1. [x] Create a new screen `NutritionTargetScreen` in `lib/features/nutrition/`.
2. [x] Add navigation to `NutritionTargetScreen` from a setup area in the Hub.
3. [x] The `NutritionTargetScreen` will contain four `TextFormField` widgets for calories, protein, carbs, and fat.
4. [x] The screen will use the `NutritionState` to display and save the targets.
5. [x] Update existing UI components that show nutrition progress to consume the targets from `NutritionState` and handle the "no target" case gracefully.

### Implementation Steps
1. [x] **DBA:** Implement the `NutritionTarget` model and repository changes.
2. [x] **Developer:** Implement the `NutritionState` ChangeNotifier.
3. [x] **Developer:** Implement the `NutritionTargetScreen`.
4. [x] **Developer:** Wire up navigation to the new screen.
5. [x] **Developer:** Update UI components to use the new state and handle unset targets.
6. [x] **QA:** Write and run unit tests for persistence, blank/unset state, and data integrity.

## Progress
- [x] Plan created.
- [x] **DBA:** `NutritionTarget` model and repository methods implemented.
- [x] **Developer:** `NutritionState` and `NutritionTargetScreen` implemented and wired up.
- [x] **Developer:** `NutritionSummaryCard` created and integrated into `HomeScreen`.
- [x] **QA:** Unit and widget tests for the nutrition feature have been added.
- [x] **Docs:** Documentation for `NutritionTarget`, `NutritionState`, `NutritionTargetScreen`, and `NutritionSummaryCard` has been updated.

## Feedback
[Leave empty]
