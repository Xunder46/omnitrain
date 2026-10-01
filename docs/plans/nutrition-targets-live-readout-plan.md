# Feature: Daily-Targets Live Implied-Calories Readout

## Overview
On the existing `NutritionTargetScreen`, add a live "calories from macros" readout (protein×4 + carbs×4 + fat×9) that updates as the user edits any field, shown next to the entered calorie target so a mismatch is visible at a glance. No field auto-adjusts any other. Pre-fill the form with reconciling default values (implied macro calories == entered calorie target) when no saved target exists.

## Requirements
- Show a live implied-calories line below the four target fields.
- Implied calories = `protein * 4 + carbs * 4 + fat * 9`.
- Display both the implied value and the entered calorie target on the same line so a mismatch is obvious.
- Editing any field must never modify any other field.
- When opening the screen with no saved target, pre-fill the form with values that reconcile (e.g., 2000 kcal / 150P / 150C / 47F → 2000 kcal: 150×4 + 150×4 + 47×9 = 600 + 600 + 423 = 1623 — does not reconcile; need to pick reconciling values).
- Reconciling pre-fill: use `2000` kcal / `150`g protein / `150`g carbs / `(2000 - 150*4 - 150*4) / 9 = 200/9 ≈ 22.22`g fat. Round fat to 22g and add a tiny calorie "drift" line, OR pick a clean integer set. The chosen clean set: `2000` kcal / `150`P / `150`C / `23`F → 600 + 600 + 207 = 1407 (not equal). Use exact reconciling integer set: `2000` kcal / `200`P / `200`C / `(2000 - 800 - 800)/9 = 400/9 ≈ 44.44`F. None of the obvious round values reconcile. Use the smallest clean reconciling set by going from fat first: `100`g fat × 9 = 900. Remaining 1100 cal split as `175`P + `100`C = 700 + 400 = 1100 → total 2000 ✓ with `175`P / `100`C / `100`F. This pre-fill reconciles exactly: 175×4 + 100×4 + 100×9 = 700 + 400 + 900 = 2000.
- Out of scope: any auto-redistribution; any auto-calculation of macros from a calorie target.

## Acceptance Criteria
- [ ] `NutritionTargetScreen` shows a "Calories from macros" line below the four input fields.
- [ ] The implied value updates live as the user edits any of the four fields.
- [ ] Editing one field never changes any other field (controllers are independent; no `onChanged` cross-wiring).
- [ ] When the screen opens with no previously saved target, all four controllers are pre-filled with reconciling values (175P / 100C / 100F / 2000 kcal).
- [ ] The "Calories from macros" line displays the implied value next to the entered calorie target (e.g., "Calories from macros: 1,750 (target: 2,000)") so a mismatch is immediately visible.
- [ ] The implied value uses the live controller text, not the saved repository target.
- [ ] An empty field is treated as `0` for the implied calculation (does not produce NaN).
- [ ] A non-numeric value in a field does not break the readout (treat as 0).
- [ ] The Save button preserves the pre-fill behaviour for subsequent visits: after saving, reopening with that saved target shows the saved values, not the pre-fill defaults.

## Scenarios

### S-001: Open screen with no saved target — form pre-fills with reconciling values
- Trigger: User opens `NutritionTargetScreen` for the first time
- Precondition: Repository has no nutrition target for today
- Flow:
  1. `NutritionTargetScreen.initState` calls `_loadTodayTarget()` which returns `null`
  2. Controllers fall through to the pre-fill path; all four are set to reconciling defaults: `175` / `100` / `100` / `2000`
  3. Readout line shows: "Calories from macros: 2,000 (target: 2,000)" — matches, no drift
- Expected outcome: Form opens with the four reconciling values; readout shows them in agreement; user can save as-is or change freely.
- Edge case of: none

### S-002: Live readout updates as macros are edited
- Trigger: User types into the protein field
- Precondition: Form is on screen with the pre-filled values (175P / 100C / 100F / 2000 kcal)
- Flow:
  1. User clears protein and types `200`
  2. The screen rebuilds; the readout recomputes: 200×4 + 100×4 + 100×9 = 800 + 400 + 900 = 2,100
  3. Readout line shows: "Calories from macros: 2,100 (target: 2,000)" — 100 cal over
- Expected outcome: The implied value updates on every keystroke. The entered calorie target (2000) is unchanged.
- Edge case of: none

### S-003: Editing one field never changes another
- Trigger: User edits any single field
- Precondition: Form is on screen with the pre-filled values
- Flow:
  1. User changes carbs from `100` to `50` (everything else untouched)
  2. After: protein=175, carbs=50, fat=100, calories=2000 (unchanged)
  3. Readout recomputes: 700 + 200 + 900 = 1,800
  4. Readout line: "Calories from macros: 1,800 (target: 2,000)"
- Expected outcome: No field other than carbs changed value; the controllers are independent and no `onChanged` callback mutates siblings.
- Edge case of: none

### S-004: Empty field is treated as 0 in the readout
- Trigger: User clears the fat field
- Precondition: Form has pre-filled values
- Flow:
  1. User clears fat (empty string)
  2. Readout treats fat as 0: 175×4 + 100×4 + 0×9 = 700 + 400 + 0 = 1,100
  3. Readout line: "Calories from macros: 1,100 (target: 2,000)"
- Expected outcome: Readout still renders a number (no `NaN`, no exception); the field stays empty until the user types a new value.
- Edge case of: S-002

### S-005: Non-numeric input does not break the readout
- Trigger: User types `abc` into a field
- Precondition: Form is on screen
- Flow:
  1. User types `abc` in fat field
  2. Validator will reject on save; the readout treats the value as 0
  3. Readout line updates normally using 0 for fat
- Expected outcome: The readout does not throw; it displays a numeric value. The validator on Save will block the save.
- Edge case of: S-004

### S-006: Reopen screen after a saved target — pre-fill does not overwrite
- Trigger: User saves a target, navigates back, then re-opens the targets screen
- Precondition: A target has been saved (e.g., 2500 / 180 / 220 / 80)
- Flow:
  1. User taps "Edit Targets" again
  2. `_loadTodayTarget` returns the saved target
  3. Controllers are populated from the saved target (2500 / 180 / 220 / 80)
  4. Readout: 180×4 + 220×4 + 80×9 = 720 + 880 + 720 = 2,320
  5. Readout line: "Calories from macros: 2,320 (target: 2,500)" — 180 cal under
- Expected outcome: Saved values are loaded; the pre-fill path is not taken.
- Edge case of: S-001

### S-007: Indicator shows agreement or drift at a glance
- Trigger: Form is on screen with the live readout
- Precondition: Any state (reconciling or drifting)
- Flow:
  1. If implied == target → label says "matches"
  2. If implied < target → label says "under by N"
  3. If implied > target → label says "over by N"
  4. The numeric implied value is always shown alongside the entered target
- Expected outcome: User can see the relationship without doing math.
- Edge case of: S-002

## Architecture & Data Model
- No new data model fields, no repository changes, no new state methods. This is a pure UI change to `NutritionTargetScreen`.
- The implied-calories value is a derived UI value computed in `build` from the four `TextEditingController` text values.
- The reconciling pre-fill is a hard-coded constant in the widget's `_loadTodayTarget` method.

## Implementation Phases

### Phase 1: UI + behaviour (@developer)
1. [ ] Add a constant `_reconcilingDefaults` in `nutrition_target_screen.dart`: `NutritionTarget(calories: 2000, protein: 175, carbs: 100, fat: 100)` — verified to reconcile: 175×4 + 100×4 + 100×9 = 2000.
2. [ ] In `_loadTodayTarget`, after the `await`, if `target == null`, set the four controllers to the reconciling pre-fill values (rounded to integer strings: `"2000"`, `"175"`, `"100"`, `"100"`).
3. [ ] Remove the existing `> 0` guard that leaves fields empty; the form should always have a value to display.
4. [ ] Add a private helper `_impliedCalories()` that returns the implied calories from the four controller text values; treat empty/non-numeric as 0.
5. [ ] Add a private helper `_formatReadout(int implied, int target)` that returns the line string: e.g., "Calories from macros: 2,000 (target: 2,000)" with an extra clause " — matches" / " — over by 100" / " — under by 100" when relevant.
6. [ ] Add an `AnimatedBuilder` (or refactor the form into a small widget that listens to controllers) so the readout rebuilds on every keystroke. Use `Listenable.merge` over the four controllers.
7. [ ] Insert the readout line as a `Padding(padding: EdgeInsets.only(top: 8))` `Text` widget after the fat `TextFormField`, before the Save `SizedBox`.
8. [ ] Use `Theme.of(context).textTheme.bodyMedium` (or `titleSmall`) for the readout; use `Theme.of(context).colorScheme.onSurfaceVariant` for muted context if the helper text "—" is added.
9. [ ] Do not add a `shape:` to the readout text — it's a static line, not a button.
10. [ ] Confirm the existing `SizedBox(width: double.infinity, height: OmniTheme.buttonPrimaryHeight)` and `FilledButton` `shape:` override on the Save button are preserved.

### Phase 2: Tests (@developer)
1. [ ] **Test: implied-calories readout equals protein×4 + carbs×4 + fat×9** (unit, in `test/nutrition_test.dart`):
   - Build `NutritionTargetScreen` with reconciling pre-fill (175 / 100 / 100 / 2000).
   - Assert the readout text contains `"2,000"` (or use a regex on the rendered `Text` widgets).
   - Edit protein to `200` and re-pump; assert readout updates to `2,100`.
2. [ ] **Test: editing one field does not alter the others** (widget, in `test/nutrition_test.dart`):
   - Build screen with reconciling pre-fill.
   - Enter `50` into the carbs field.
   - Assert the calories, protein, and fat `TextFormField` controllers' text remain `"2000"`, `"175"`, `"100"`.
3. [ ] **Test: default targets reconcile** (unit, in `test/nutrition_test.dart`):
   - Build screen with a fresh repo and no saved target.
   - Assert controllers hold the reconciling values: `"2000"`, `"175"`, `"100"`, `"100"`.
   - Assert the readout shows implied == target.
4. [ ] **Test: empty/non-numeric field is treated as 0 in the readout** (widget, in `test/nutrition_test.dart`):
   - Build screen with reconciling pre-fill.
   - Clear the fat field.
   - Assert readout shows `1,100` (700 + 400 + 0).
5. [ ] **Test: saved target loads, pre-fill does not overwrite** (widget, in `test/nutrition_test.dart`):
   - Pre-save a target (180 / 220 / 80 / 2500) and pump the screen.
   - Assert controllers hold the saved values, not the reconciling defaults.
   - Assert readout shows `2,320` (implied) next to `2,500` (target).
6. [ ] **Test: live readout updates on every keystroke** (widget, in `test/nutrition_test.dart`):
   - Build screen.
   - Type a new protein value one character at a time and assert the readout text changes after each `pump`.

### Phase 3: Verification
1. [ ] Run `flutter test test/nutrition_test.dart` and confirm all new tests pass.
2. [ ] Run the full test suite (`flutter test`) to confirm no regressions in existing nutrition / state / edge-case tests.
3. [ ] Run `flutter analyze` and confirm no new warnings or errors in `nutrition_target_screen.dart`.

## Files Affected
- `lib/features/nutrition/nutrition_target_screen.dart` — add pre-fill path, live readout, derived helpers.
- `test/nutrition_test.dart` — add the five new tests above.

## Progress Checklist
- [x] Phase 0 — Scenarios confirmed (S-001..S-007) and 5 new tests written.
- [x] Phase 0 — Red baseline: all 5 new tests failed before implementation.
- [x] Phase 1 — Reconciling pre-fill path added in `_loadTodayTarget`.
- [x] Phase 1 — Live readout wired via `Listenable.merge` of the 4 controllers.
- [x] Phase 1 — `_impliedCalories()`, `_formatReadout()`, `_formatThousands()` helpers added.
- [x] Phase 1 — Save button `shape:` + `OmniTheme.buttonPrimaryHeight` preserved.
- [x] Phase 2 — All 5 new tests pass.
- [x] Phase 2 — Pre-existing test `populates fields from a previously saved target` updated to assert integer strings (`"2500"`, `"150"`, ...) since the screen now formats as integer; the underlying load-from-repo behaviour is unchanged.
- [x] Phase 3 — Full test suite: 1224 passed / 5 skipped (pre-existing skips), 0 failures.
- [x] Phase 3 — `flutter analyze` on `nutrition_target_screen.dart`: 0 issues.

## Phase 2 Complete ✓
Implementation done. All Phase 0 tests green. Ready for Code Reviewer.

## Notes
- This change is a pure UI tweak. No repository, model, state, navigation, or design-token changes are required.
- The "no auto-redistribution" constraint is satisfied by construction: the controllers are independent `TextEditingController` instances, and no `onChanged` callback writes back to a sibling.
- The reconciling pre-fill (`175 / 100 / 100 / 2000`) is documented inline as a constant with the verification arithmetic in a comment, so a future contributor who changes the default can re-verify in seconds.
- The readout format follows the user's preference: integer with comma grouping, shown alongside the entered target.
- A future iteration can replace the pre-fill with a one-time repository seed in `main.dart` (per the "Seed scope" clarifying question), but the user explicitly chose "form pre-fill only" for this iteration.
- The `0 = not set` semantic from the previous plan still applies to the saved repository: a target of `(0, 0, 0, 0)` is treated as unset in the summary card. The pre-fill in this iteration only changes what the edit form shows; it does not write `(0, 0, 0, 0)` to the repo.
- The screen uses `Theme.of(context).colorScheme.onSurfaceVariant` for the muted readout text and the existing `Theme.of(context).textTheme.bodyMedium` base — no hardcoded colors, satisfying the **Theme tokens only** global convention.
- Numeric formatting is integer-with-comma-grouping via a private `_formatThousands` helper (no `intl` dependency added; the helper is small, pure, and unit-test-covered by the readout tests).
- The `WorkoutRepository` interface is unchanged: this iteration only calls the existing `getTodayTarget()` / `saveNutritionTarget(NutritionTarget)` methods, so the code works unchanged on `HiveWorkoutRepository` (web/native) and the future `SqliteWorkoutRepository`.

