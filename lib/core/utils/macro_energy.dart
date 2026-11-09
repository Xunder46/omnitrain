/// Unrounded calories from raw macro grams — the one place the 4/4/9
/// factors live.
///
/// Formula: protein * 4 + carbs * 4 + fat * 9. Fiber is not subtracted.
/// This file imports nothing so the models can use it without a cycle;
/// callers round at their own boundary ([caloriesFromMacros] in
/// `food_helpers.dart` is the whole-number form the UI shows).
double macroKcal({
  required double protein,
  required double carbs,
  required double fat,
}) => protein * 4 + carbs * 4 + fat * 9;
