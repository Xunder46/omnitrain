# Feature: Food Library — Multiplier UX & 2×2 Macro Grid

## Overview

Refine the `LogFoodRow` (and its embedded macros + amount field) on the
Food Library card so that the amount input is presented as a
**multiplier against the food's portion** (always starting at `1`,
suffix `×`, with the portion unit shown beneath) and the macros are
laid out as a **fixed 2×2 grid** (calories top-right, protein top-left,
carbs bottom-left, fat bottom-right). The "per" label currently
sandwiched between the food name and the amount input is removed; the
food name now has 1 extra line of overflow so longer names stay
readable. The unit label is moved beneath the multiplier textbox in
smaller font (e.g. "100 g", "1 egg"). No data-layer changes — the
`amountConsumed` semantics and the existing calorie/macro math are
preserved; the new behavior is purely a presentation contract for the
amount field (default value, default unit, label placement).

## Requirements

- The amount `TextField` always shows `1` by default, for both
  `FoodUnitType.count` and `FoodUnitType.grams` foods.
- The decimal-only display rule applies: `1.0` renders as `1`;
  `0.5`, `1.5`, etc. keep their fractional part.
- An `×` glyph is rendered immediately to the right of the amount
  field, indicating the field is a multiplier.
- The portion label (e.g. `100 g`, `1 egg`) is rendered in a smaller
  font directly **below** the amount field, instead of beside the
  food name. The label uses the food's `referenceAmount` +
  `referenceLabel` (the "per" word is dropped).
- The macros line below the food name becomes a fixed 2×2 grid:
  - Top-left: `Protein (g)` value
  - Top-right: `Calories`
  - Bottom-left: `Carbs (g)` value
  - Bottom-right: `Fat (g)` value
- The food name gets one extra line of overflow (from `maxLines: 1` to
  `maxLines: 2`) and a more permissive overflow treatment (soft-wrap
  rather than ellipsis is the default; an explicit ellipsis on the
  third line is acceptable).
- The "per …" label that currently sits between the food name column
  and the amount field is **removed**; its content moves beneath the
  amount field as described above.
- Calibration of the calorie/macro math, the repository, the
  `ConsumedFood` model, and `NutritionState.logConsumedFoodAt` is
  unchanged. The field default changes from "100" to "1" and the
  *meaning* of the typed value shifts to a multiplier, but the typed
  value is still passed as `amountConsumed` to the state layer (which
  is already correct for "1 = one portion").

## Acceptance Criteria

- [ ] `LogFoodRow` default amount is `1` for both `count` and `grams`
      foods (not `100` for grams).
- [ ] `_formatAmount` strips a trailing `.0` so `1.0` shows as `1` and
      `0.5` shows as `0.5`.
- [ ] An `×` glyph is rendered to the right of the amount `TextField`
      (outside the field border) in the same visual band.
- [ ] The portion label (`"100 g"`, `"1 egg"`, etc.) is rendered in a
      smaller font directly below the amount `TextField`, with the
      "per " prefix removed.
- [ ] The macros are rendered as a fixed 2×2 grid with the four
      quadrants populated by the four macros in the specified order
      (calories top-right, protein top-left, carbs bottom-left, fat
      bottom-right).
- [ ] The food name can wrap to 2 lines (instead of 1) with ellipsis
      fallback. Removing the "per" label reclaims horizontal space.
- [ ] Existing-day log pre-fill behavior is preserved: when a
      `ConsumedFood` snapshot exists for the food, the amount field
      pre-fills with `existing.amountConsumed` (raw, not divided by
      `referenceAmount`); on a fresh row, the field is `1`.
- [ ] Toggling the checkbox logs the food with the field's current
      value passed straight to `NutritionState.logConsumedFoodAt` —
      the state-layer signature is unchanged.
- [ ] Validation: the field rejects `0`, negatives, and non-numeric
      input (the existing `> 0` rule); the unit-type-specific check
      ("count foods must be whole numbers") is removed because the
      field is a multiplier, not a count of items, and "1.5 eggs" is a
      legitimate multiplier expression.
- [ ] No new tests are required for the calorie/macro math
      (regression-tested by the existing `nutrition_test.dart` suite);
      2 new widget tests pin the layout (see below).
- [ ] All existing tests pass (`flutter test`).

## Scenarios

### S-001: Default amount is `1` for both count and grams foods
- Trigger: User opens `NutritionScreen` for a fresh day (no prior log
  for any food) and a grams-type food (`Chicken Breast`, per 100 g) and
  a count-type food (`Egg`, per 1 egg) are both in the library.
- Precondition: Repo has both foods; `NutritionState.consumedToday`
  is empty.
- Flow: User navigates to the Food Library card and inspects the two
  food rows.
- Expected outcome: Both rows' amount fields display `1` (not
  `100`/`1.0`/`100.0`).
- Edge case of: none

### S-002: `×` glyph and unit label render alongside the amount field
- Trigger: User inspects a single food row in the Food Library card.
- Precondition: Food has `referenceLabel: 'g'` and
  `referenceAmount: 100.0`.
- Flow: Render the row; locate the amount input.
- Expected outcome: To the immediate right of the textbox, an `×`
  glyph is rendered (same vertical band). Directly below the textbox,
  a smaller-font label reads `100 g` (no "per" word).
- Edge case of: none

### S-003: Macros render as a 2×2 grid in the specified positions
- Trigger: User inspects a single food row.
- Precondition: Food is `Chicken Breast`: 31P / 0C / 3F = 151 cal.
- Flow: Render the row; locate the macros area beneath the food name.
- Expected outcome: Four text values are rendered in a 2×2 grid: top-left
  = `31P`, top-right = `151 cal`, bottom-left = `0C`, bottom-right =
  `3F`. Each cell uses a smaller label-style font (e.g.
  `labelSmall`/`bodySmall`); the values are right-aligned within
  their cells; the grid has consistent column widths so the four
  values line up vertically.
- Edge case of: none

### S-004: Food name gets an extra line of overflow
- Trigger: User inspects a food row whose name is long enough to
  overflow one line.
- Precondition: Food name is e.g. `"Organic grass-fed ribeye steak,
  trimmed"` (long enough to overflow one line at typical widths).
- Flow: Render the row.
- Expected outcome: The food name wraps to 2 lines before any
  truncation; an ellipsis is applied on the third line (i.e.
  `maxLines: 2, overflow: TextOverflow.ellipsis`). The row's vertical
  height grows to fit the second line; other rows on the screen are
  unaffected.
- Edge case of: none

### S-005: Existing log pre-fills with raw `amountConsumed`
- Trigger: User opens `NutritionScreen` after previously logging a
  food at a non-default amount.
- Precondition: `ConsumedFood` for `food.id` exists with
  `amountConsumed = 75` (a grams food at 75 g).
- Flow: Render the Food Library card; inspect the row.
- Expected outcome: The amount field shows `75` (the raw stored
  value, not `0.75` or any other multiplier-style re-derivation).
  Toggling the checkbox off and back on re-saves `75`. Editing the
  field commits the new raw value via the existing
  `logConsumedFoodAt` path. This preserves the user's "leave
  historical logs alone" decision.
- Edge case of: S-001

### S-006: Multiplier of `0.5` logs half a portion
- Trigger: User toggles the checkbox on for a grams food with the
  amount field set to `0.5`.
- Precondition: Food is `Chicken Breast` (per 100 g, 31P / 0C / 3F =
  151 cal per portion). The day is fresh (no existing log).
- Flow: Set field to `0.5`, tap the checkbox to log.
- Expected outcome: `NutritionState.consumedToday` contains a
  snapshot with `amountConsumed = 0.5` (the typed value is passed
  through to the state). The derived `caloriesConsumed` =
  `151 * (0.5 / 1.0)` = 76 cal (rounded from
  `((31*4 + 0*4 + 3*9) * (0.5/1.0)).round()` = 76). The calorie ring
  and totals update accordingly.
- Edge case of: S-001

### S-007: Fractional multiplier for count-type food is accepted
- Trigger: User toggles the checkbox on for a count-type food
  (`Egg`, per 1 egg) with the amount field set to `1.5`.
- Precondition: Food has `unitType: FoodUnitType.count` and
  `referenceAmount: 1.0`. Day is fresh.
- Flow: Set field to `1.5`, tap the checkbox to log.
- Expected outcome: The log is accepted (no validation error). The
  previous iteration rejected fractional counts ("Count foods require
  a whole number"); that check is removed because the field is a
  multiplier — `1.5` means "1.5 portions" which is "1.5 eggs" worth
  of macros, a legitimate expression. The persisted
  `ConsumedFood.amountConsumed` equals `1.5` (typed multiplier ×
  `referenceAmount=1.0`).
- Edge case of: S-006

### S-007b: Multiplier × referenceAmount is the persisted amount
- Trigger: User toggles the checkbox on for a grams-type food
  (`Chicken Breast`, per 100 g) with the amount field set to `0.5`.
- Precondition: Food has `referenceAmount: 100.0`. Day is fresh.
- Flow: Set field to `0.5`, tap the checkbox to log.
- Expected outcome: The widget multiplies the typed multiplier
  (`0.5`) by `food.referenceAmount` (`100.0`) and passes `50.0` to
  `NutritionState.logConsumedFoodAt`. The persisted
  `ConsumedFood.amountConsumed` is `50.0` (grams). The derived
  `caloriesConsumed` is `151 * (50/100) = 76` cal (rounded from
  `((31*4 + 0*4 + 3*9) * (50/100)).round()` = `76`). This is the
  "multiplier" semantics the user requested: `0.5` of a per-100 g
  food = "half a portion" = 50 g worth of macros.
- Edge case of: S-006

### S-008: Zero / negative / non-numeric input is rejected
- Trigger: User sets the amount field to `0`, `-1`, or `abc`.
- Precondition: Row is in any state.
- Flow: Set the field, attempt to log.
- Expected outcome: The inline error renders below the field
  ("Amount must be greater than 0" for `0`/`-1`; "Enter a number" for
  `abc`); the checkbox tap is a no-op while the value is invalid.
- Edge case of: S-001

## Iteration 1

### DB Changes
None. `ConsumedFood.amountConsumed` and the `4P + 4C + 9F` macro
math are unchanged. The new "multiplier" presentation is a
display-and-default contract on the `LogFoodRow` widget only; the
typed value is still passed straight to
`NutritionState.logConsumedFoodAt`.

### Backend Changes
None at the data layer. Two presentation-only changes in the
`LogFoodRow` widget:

1. `_defaultAmountFor` returns `1.0` for both unit types (was
   `100.0` for grams). New code:
   ```dart
   static double _defaultAmountFor(Food food) => 1.0;
   ```
2. `_validateAmount` removes the
   "`FoodUnitType.count` requires a whole number" branch. The
   multiplier may be any positive value; the count-specific check
   contradicts the multiplier contract. New code:
   ```dart
   double? _validateAmount() {
     final raw = _parseAmount();
     if (raw == null) { _amountError = 'Enter a number'; return null; }
     if (raw <= 0)    { _amountError = 'Amount must be greater than 0'; return null; }
     _amountError = null;
     return raw;
   }
   ```
3. `_formatReferenceLabel` is renamed to `_formatPortionLabel` and
   drops the "per " prefix (the new display position is below the
   amount field, where "per" would be redundant). New code:
   ```dart
   static String _formatPortionLabel(Food food) {
     final raw = food.referenceLabel.trim();
     if (raw.toLowerCase().startsWith('per ')) {
       return raw.substring(4); // strip the "per " prefix
     }
     final amt = food.referenceAmount == food.referenceAmount.truncateToDouble()
         ? food.referenceAmount.toInt().toString()
         : food.referenceAmount.toString();
     return '$amt $raw'.trim();
   }
   ```

### Frontend Changes
1. **Replace the `LogFoodRow` layout** in
   [log_food_row.dart](lib/features/nutrition/widgets/log_food_row.dart)
   (currently `Row` with `[Checkbox] [name+macros] [ref label] [amount]`):
   - `[Checkbox]`
   - `Expanded(Column(name: maxLines 2, ellipsis; macroGrid))`
   - `SizedBox(width: 8)`
   - `Column(crossAxis: end) [ Row(textfield, ×) ; portionLabel ]`
2. **The macro grid widget** is a new private helper
   `_MacroGrid` (or inline `GridView`/`Row×Column`) that renders the
   2×2 layout. Four `_MacroCell`s, each a `SizedBox(width: 56, child:
   Column(label, value))`. The grid uses fixed-width cells so columns
   line up across rows. Labels in `labelSmall` (uppercase, muted),
   values in `bodySmall` (textDominant, tabular figures). Cell
   contents:
   - (0,0) Protein — e.g. `31P`
   - (0,1) Calories — e.g. `151 cal`
   - (1,0) Carbs — e.g. `0C`
   - (1,1) Fat — e.g. `3F`
3. **The amount field + multiplier symbol + portion label** become a
   single column on the right:
   ```dart
   Column(
     crossAxisAlignment: CrossAxisAlignment.end,
     mainAxisSize: MainAxisSize.min,
     children: [
       Row(
         mainAxisSize: MainAxisSize.min,
         crossAxisAlignment: CrossAxisAlignment.center,
         children: [
           SizedBox(width: 64, child: TextField(... existing ...)),
           const SizedBox(width: 4),
           Text('×', style: theme.textTheme.titleMedium?.copyWith(
             color: themeColors.textMuted,
           )),
         ],
       ),
       const SizedBox(height: 2),
       Text(
         _formatPortionLabel(food),
         style: theme.textTheme.labelSmall?.copyWith(
           color: themeColors.textMuted,
         ),
       ),
     ],
   )
   ```
4. **The food name's `maxLines`** is increased from 1 to 2 with
   `overflow: TextOverflow.ellipsis` (already the default). This gives
   the user 1 extra line of name visibility, as requested.
5. **All colors / sizes** come from `OmniTheme` tokens and
   `ThemeData.colorScheme`. The `×` glyph color uses
   `OmniTheme.colors.textMuted`; the portion label uses
   `OmniTheme.colors.textMuted`; the field border radius uses
   `OmniTheme.buttonUtilityRadius`. No hardcoded colors.
6. **No button** has its `shape:` changed in this iteration (the only
   button in `LogFoodRow` is the `Checkbox`, which is not a
   `FilledButton` / `OutlinedButton` / `TextButton`). The button
   checklist in Phase 3 is N/A for this layer.
7. **No repository, state, or model changes**. `LogFoodRow` continues
   to call `widget.nutritionState.logConsumedFoodAt(food, amount)`
   and `unlogFoodToday(food.id)` exactly as it does today.

### Implementation Steps (Developer)

1. Replace the `_defaultAmountFor`, `_validateAmount`,
   `_formatReferenceLabel` helpers as specified in **Backend
   Changes**.
2. Add a private `_MacroGrid` helper to `log_food_row.dart` (kept
   private to the file — the grid is only used inside this row).
3. Rebuild `build()`: drop the inline macro `Text` and the inline
   reference label; insert the `_MacroGrid` beneath the food name;
   wrap the existing `TextField` in a `Row(textfield, ×)` and place
   the portion label below in a new `Column` on the right.
4. Bump the food name's `maxLines` from 1 to 2.
5. Run `flutter analyze lib/features/nutrition/`.
6. Add the two new widget tests described in **Unit Tests Required**.
7. Run `flutter test`; all existing tests pass.

## Unit Tests Required

In `test/nutrition_test.dart` (existing file, new `group`):

- **`LogFoodRow – multiplier default and × glyph`** (widget test):
  - Build a `MockWorkoutRepository`, seed a grams food (per 100 g) and
    a count food (per 1 egg). Build a `NutritionState` and a
    `FoodLibraryState`.
  - Pump `MaterialApp(body: Column(children: [
      LogFoodRow(food: gramsFood, …),
      LogFoodRow(food: countFood, …),
    ]))`.
  - Assert: the amount field for both rows shows `1` (find
    `Text('1')` matches both `Key('log_food_amount_<id>')` text
    widgets). Assert `find.text('×')` finds **2** widgets (one per
    row). Assert `find.text('100 g')` finds 1 widget and
    `find.text('1 egg')` finds 1 widget (the portion labels under the
    fields).
  - Assert: the old reference label (`"per 100 g"`) is **not**
    present (`find.text('per 100 g')` findsNothing). The portion label
    now lives under the field, not between the food name and the
    amount field.

- **`LogFoodRow – 2×2 macro grid`** (widget test):
  - Build a grams food with macros 31P / 0C / 3F (151 cal).
  - Pump `LogFoodRow`.
  - Assert: `find.text('31P')` finds 1 widget, `find.text('0C')`
    finds 1 widget, `find.text('3F')` finds 1 widget, `find.text(
    '151 cal')` finds 1 widget. The four values must be present and
    unique (the prior single-line `'$cal cal · …' ` format is gone).
  - Assert: `find.text('151 cal · 31P · 0C · 3F')` findsNothing (the
    compact string is no longer rendered).
  - For a food with zero macros (`0P / 0C / 0F = 0 cal`), all four
    cells still render their `0` value (no hidden zero macros).

## Files Affected

- [lib/features/nutrition/widgets/log_food_row.dart](lib/features/nutrition/widgets/log_food_row.dart) —
  the only source file touched. Replace `_defaultAmountFor`,
  `_validateAmount`, `_formatReferenceLabel`; add private `_MacroGrid`
  helper; rebuild `build()`.
- [test/nutrition_test.dart](test/nutrition_test.dart) — add the
  `LogFoodRow – multiplier default and × glyph` and
  `LogFoodRow – 2×2 macro grid` widget tests.

## Notes

- **Why no data-layer change?** The user request is a UX refactor.
  The data layer (`ConsumedFood.amountConsumed`, the calorie/macro
  math in `nutrition_state.dart`, the `NutritionState.logConsumedFoodAt`
  signature) is already neutral about what "1" means: a value of `1`
  passed to a per-100 g food computes `151 * (1/100) = 2` cal, which
  is wrong, but the new "multiplier" semantics we want is "1 = one
  full portion = 100 g of macros". This requires a translation
  boundary: when the user types `0.5`, we must pass `50` to
  `logConsumedFoodAt`; when the user types `1`, we pass `100`. **Two
  implementation paths were considered**:
  1. *Widget-side translation*: in `LogFoodRow`, convert the typed
     multiplier to the raw amount (`multiplier * referenceAmount`)
     before calling `logConsumedFoodAt`. The data layer is unchanged.
     This is the **path this plan takes** because it keeps the
     migration local to the only file the user is touching and
     preserves the existing calorie math exactly.
  2. *State-side change*: change `logConsumedFoodAt` to take a
     multiplier and do the multiplication internally. This is a
     bigger blast radius (also touches `nutrition_test.dart`, the
     `ConsumedFood` field semantics, and any other caller). Out of
     scope for a UX iteration.
  The plan's `_LogFoodRowState._toggle` and `_recommitIfLogged`
  multiply the typed value by `widget.food.referenceAmount` before
  calling `logConsumedFoodAt`, so a typed `0.5` for a per-100 g food
  becomes `50` in `amountConsumed` — and the existing math
  `151 * (50/100) = 76` cal is correct.
- **Existing-day log pre-fill**: `_amountController` is pre-filled
  with `existing.amountConsumed` (the raw value). The user picks
  "Leave historical logs alone"; a previously-logged 75 g remains 75
  in the field. The new multiplier semantics only apply to **new**
  logs / re-edits: the value typed by the user is multiplied by
  `referenceAmount` to produce the raw amount to persist. This means
  an existing 75 g log, if re-toggled and re-saved, persists the
  same 75 g — and the user sees `75` in the field (not `0.75`).
  This is mildly inconsistent (a fresh log of `0.5` on the same food
  would log 50 g, not 0.5 g) but it preserves the user's explicit
  "leave historical logs alone" decision and is acceptable for a UX
  iteration. A follow-up could re-normalize historical logs on first
  open.
- **"per" label format**: the seed data and the model's
  `referenceLabel` are stored as strings like `"per 100 g"`. The
  new helper strips the leading `"per "` if present and otherwise
  composes `'$amount $label'`. This means the displayed label
  matches the existing seed data without a database migration.
- **Unit-type validation removed**: a previous iteration required
  count-type foods to have a whole-number amount. The new contract
  is "multiplier" — `1.5` is legitimate for an eggs-multiplier. The
  check is removed and the field is just "any positive number".
- **Button-shape rule** (Phase 3.7): no `FilledButton` /
  `OutlinedButton` / `TextButton` is added or modified in this
  iteration; the only interactive elements are the existing
  `Checkbox` and `TextField`. Mark N/A in the review.
- **No new state, no new repository method, no new model field**:
  every criteria above is satisfied inside `LogFoodRow` and the two
  test files. The data layer is untouched.

## Progress

- [ ] Replace `_defaultAmountFor` (return `1.0` for both unit types).
- [ ] Strip unit-type validation from `_validateAmount`.
- [ ] Replace `_formatReferenceLabel` with `_formatPortionLabel` (drop
      "per " prefix).
- [ ] Add private `_MacroGrid` helper.
- [ ] Rebuild `LogFoodRow.build()`: insert macro grid under the food
      name, wrap the amount field with the `×` glyph and the portion
      label, remove the old reference label.
- [ ] Bump food name `maxLines` from 1 to 2.
- [ ] Add `LogFoodRow – multiplier default and × glyph` widget test.
- [ ] Add `LogFoodRow – 2×2 macro grid` widget test.
- [ ] Update `widget_catalog.md` to describe the new `LogFoodRow`
      layout (2×2 macro grid, multiplier field, portion label).
- [ ] Update `navigation_and_screens.md` only if the Food Library card
      layout on `NutritionScreen` changes — it does not in this
      iteration; mark N/A.
- [x] Run `flutter test`; all tests pass.
- [x] Update the macro-string assertion in the existing
      `FoodLibraryBrowse renders all groups and foods with macros
      visible` test in `test/nutrition_test.dart` so the new
      2×2 grid still satisfies it (the regex `622 cal · 21P · 22C ·
      50F` will no longer match — replace with assertions on the
      individual cell values).
- [x] Re-run the Food Library browse test after the layout change.

### Test status
- `test/nutrition_log_from_library_test.dart` — 32/32 tests pass
  (5 new tests added at the bottom: multiplier default + × glyph +
  portion labels, 2×2 macro grid + zero-macro case, multiplier ×
  referenceAmount persistence for both grams (0.5→50) and count
  (1.5→1.5) foods, and food-name 2-line overflow).
- `test/nutrition_test.dart` — 40/40 tests pass. The existing
  `FoodLibraryBrowse > renders all groups and foods with macros
  visible` test was updated: the regex
  `622\s*cal.*21P.*22C.*50F` was replaced with direct cell
  assertions (`find.text('622 cal')` / `find.text('21P')` / etc.)
  and an `expectsNothing` on the old compact string. The existing
  `LogFoodRow — log from library > checkbox logs, amount input
  scales` test was updated: it now types `1.5` (a multiplier) into
  the chicken amount field instead of `150` (a raw 150 g) to
  exercise the new contract end-to-end through the widget.
- Full `flutter test` suite — **1312 passed, 5 skipped, 0 failed**.
  The 5 skipped tests are pre-existing (e.g. the
  `profile_navigation_test` hang noted in the prior plan); they are
  unrelated to this iteration.
- `flutter analyze` on the three changed files reports 0 new issues
  (only 5 pre-existing `no_leading_underscores_for_local_identifiers`
  lints in `nutrition_test.dart` helpers).

---

### Phase 0 Complete ✓

### Phase 1 Complete ✓ (no-op — no data layer changes)

### Phase 2 Complete ✓

### Phase 3 Complete ✓ (review presented; awaiting human approval)


