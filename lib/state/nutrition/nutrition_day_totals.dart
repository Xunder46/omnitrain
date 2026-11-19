import '../../data/models/models.dart';

/// The six totals the Nutrition screen shows for one day, folded from that
/// day's logged rows (plan 247). Doubles are summed and rounded ONCE at the
/// end, so a row that adds 0.45 g is not erased by per-row rounding; the
/// expressions are the ones `NutritionState`'s `todayConsumed*` getters always
/// used, and those getters now read this class.
class NutritionDayTotals {
  final int calories;
  final int protein;
  final int carbs;
  final int fiber;
  final int fat;
  final int sodium;

  const NutritionDayTotals({
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fiber,
    required this.fat,
    required this.sodium,
  });

  factory NutritionDayTotals.of(List<ConsumedFood> rows) {
    final calories = rows.fold<int>(0, (sum, c) => sum + c.caloriesConsumed);
    int grams(double Function(ConsumedFood c) of) => rows
        .fold<double>(
          0,
          (sum, c) => sum + of(c) * c.amountConsumed / c.referenceAmount,
        )
        .round();
    return NutritionDayTotals(
      calories: calories,
      protein: grams((c) => c.protein),
      carbs: grams((c) => c.carbs),
      fiber: grams((c) => c.fiber ?? 0),
      fat: grams((c) => c.fat),
      sodium: grams((c) => c.sodium ?? 0),
    );
  }
}
