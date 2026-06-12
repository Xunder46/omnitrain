import '../../data/models/models.dart';

/// Calculate calories for a food based on macronutrients.
///
/// Formula: protein * 4 + carbs * 4 + fat * 9
/// All values in grams per serving.
int calculateCalories(Food food) {
  return food.protein * 4 + food.carbs * 4 + food.fat * 9;
}

/// Calculate net carbs for a food.
///
/// Formula: carbs - (fiber ?? 0)
/// All values in grams per serving.
int calculateNetCarbs(Food food) {
  return food.carbs - (food.fiber ?? 0);
}
