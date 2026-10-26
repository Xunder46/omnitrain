/// Default macro targets and the calories they add up to.
///
/// The Daily Targets screen prefills protein, carbs and fat from the calorie
/// target with a fixed split, and moves the calorie target when a macro is
/// edited by hand. Grams are whole numbers; carbs are TOTAL carbs.
library;

/// Share of calories given to protein by the default split.
const int kDefaultProteinPercent = 30;

/// Share of calories given to carbs by the default split.
const int kDefaultCarbsPercent = 40;

/// Share of calories given to fat by the default split.
const int kDefaultFatPercent = 30;

/// Protein, carbs and fat targets in whole grams.
class MacroTargets {
  final int protein;
  final int carbs;
  final int fat;

  const MacroTargets({
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  @override
  bool operator ==(Object other) =>
      other is MacroTargets &&
      other.protein == protein &&
      other.carbs == carbs &&
      other.fat == fat;

  @override
  int get hashCode => Object.hash(protein, carbs, fat);

  @override
  String toString() => 'MacroTargets($protein, $carbs, $fat)';
}

/// The default split of [calories]: 4 kcal per gram of protein and carbs,
/// 9 kcal per gram of fat. Zero or negative calories give all zeros.
MacroTargets defaultMacroTargets(double calories) {
  if (calories <= 0) {
    return const MacroTargets(protein: 0, carbs: 0, fat: 0);
  }
  return MacroTargets(
    protein: (calories * kDefaultProteinPercent / 400).round(),
    carbs: (calories * kDefaultCarbsPercent / 400).round(),
    fat: (calories * kDefaultFatPercent / 900).round(),
  );
}

/// The calories that [protein], [carbs] and [fat] grams add up to.
int impliedCalories({
  double protein = 0,
  double carbs = 0,
  double fat = 0,
}) => (protein * 4 + carbs * 4 + fat * 9).round();
