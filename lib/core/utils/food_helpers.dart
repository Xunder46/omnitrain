import '../../data/models/models.dart';

/// Calculate calories for a food based on macronutrients.
///
/// Formula: protein * 4 + carbs * 4 + fat * 9
/// All values in grams per serving. Macros are stored as `double`
/// (S-001 — see
/// `docs/plans/food-form-decimals-and-autofocus-plan.md`);
/// the helper rounds to `int` at the boundary because calorie
/// displays are always whole numbers.
int calculateCalories(Food food) {
  return (food.protein * 4 + food.carbs * 4 + food.fat * 9).round();
}

/// Calculate net carbs for a food.
///
/// Formula: carbs - (fiber ?? 0)
/// All values in grams per serving. Macros are `double`; the
/// helper rounds to `int` to match the donut chart's int-gram
/// display math.
int calculateNetCarbs(Food food) {
  return (food.carbs - (food.fiber ?? 0)).round();
}

/// Format a macro gram value for display.
///
/// Macros are stored as `double` (so the form can persist
/// fractional grams like `0.5`), but a whole number renders with
/// an unnecessary `.0` suffix when string-interpolated as
/// `'$valueP'`. This helper strips the `.0` for whole numbers and
/// keeps the decimal when it's non-zero:
///
///   * `21.0` -> `"21"`
///   * `21.5` -> `"21.5"`
///   * `0.0`  -> `"0"`
///
/// Used by the food row single-line macro render and the
/// `+ New Item` / `Edit Food` catalog rows that show
/// `"<cal> cal · <P>P · <C>C · <F>F"`. The single-line format
/// was originally defined for `int` macros, and the test
/// `expect(find.text('622 cal · 21P · 22C · 50F'))` pins the
/// no-suffix display — this helper preserves that contract for
/// whole-number macros while still allowing fractional values to
/// render with a decimal.
String formatGrams(double value) {
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  return value.toString();
}
