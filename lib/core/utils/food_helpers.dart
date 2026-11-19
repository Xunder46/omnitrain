import '../../data/models/models.dart';
import 'macro_energy.dart';

/// Calories from raw macro grams — the single calorie formula.
///
/// Formula: protein * 4 + carbs * 4 + fat * 9
/// All values in grams per serving; `.round()` is half away from
/// zero (0.5 g of fat alone gives 4.5 → 5). Fiber is **not**
/// subtracted: a food's calories count its total carbohydrate, and
/// only [calculateNetCarbs] applies the fiber adjustment. The food
/// form's live calories line calls this directly, so the line and
/// every stored food WITHOUT a calories override render the same number
/// (plan 253: an override replaces the sum on the food and its logged rows).
int caloriesFromMacros({
  required double protein,
  required double carbs,
  required double fat,
}) => macroKcal(protein: protein, carbs: carbs, fat: fat).round();

/// Calculate calories for a food (what the UI and the watch show).
///
/// Reads [Food.calories]: the macro sum (protein * 4 + carbs * 4 + fat * 9,
/// rounded to whole kcal, see [caloriesFromMacros]) unless the food carries its
/// own calories number, which replaces it (plan 253).
int calculateCalories(Food food) {
  return food.calories;
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

/// A display [Food] built from a logged row's own frozen name and numbers, for
/// a food that is no longer in the library (plan 247). Its id is the ROW's id,
/// not a library id, so it can never be mistaken for a library food.
Food foodFromConsumedSnapshot(ConsumedFood c) => Food(
  id: c.id,
  name: c.name,
  groupId: c.groupIdSnapshot,
  unitType: c.unitType,
  referenceAmount: c.referenceAmount,
  referenceLabel: c.referenceLabel,
  protein: c.protein,
  carbs: c.carbs,
  fiber: c.fiber,
  fat: c.fat,
  sodium: c.sodium,
  caloriesOverride: c.caloriesOverride,
  createdAtMs: c.createdAtMs,
  updatedAtMs: c.updatedAtMs,
);
