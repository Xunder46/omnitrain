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

/// Render the serving label for a food row, e.g. "100 g" or "1 tbsp".
///
/// Shows "{referenceAmount} {referenceLabel}" and handles legacy
/// labels like "per 100g" / "per 100 g" by extracting just the unit
/// part. Body moved verbatim from `LogFoodRow._unitLabel`
/// (plan 77a D-6) so the Library rows and the log rows render the
/// same string.
String foodServingLabel(Food food) {
  final amount = food.referenceAmount.toInt();
  var label = food.referenceLabel.trim();

  // Handle legacy labels that contain "per" (e.g., "per 100g", "per 100 g")
  if (label.toLowerCase().startsWith('per ')) {
    label = label.substring(4).trim();
    // If it still starts with a number, extract just the unit part
    final parts = label.split(' ');
    if (parts.isNotEmpty) {
      final firstPart = parts[0];
      if (double.tryParse(firstPart) != null) {
        // First part is a number, take the rest
        label = parts.length > 1 ? parts.sublist(1).join(' ') : '';
      }
    }
  }

  return '$amount $label';
}

/// The unit alone, for the caption under an amount box ("g", "ml", "medium").
///
/// Strips a legacy leading `per ` and a leading number ("100 g", "per 100g"
/// both give "g"), so the caption never repeats the reference amount. When
/// nothing is left it returns the trimmed original label.
String foodUnitCaption(Food food) {
  final original = food.referenceLabel.trim();
  var label = original;
  if (label.toLowerCase().startsWith('per ')) {
    label = label.substring(4).trim();
  }
  label = label.replaceFirst(RegExp(r'^\d+(\.\d+)?\s*'), '').trim();
  return label.isEmpty ? original : label;
}
