/// The Fuel section's figures, as `StatsProgressService.computeFuelSummary()`
/// produces them.
///
/// Every average is a mean over **logged days only** — a day with at least one
/// `ConsumedFood` row — so a week with three logged days divides by three, not
/// by the length of the window. An average whose day-set is empty is `null`
/// rather than `0`, so a side with nothing logged reads as an absence instead
/// of a zero-calorie day.
///
/// Plain Dart: this is a value type, not a persisted record.
library;

class FuelSummary {
  /// Days in the window with at least one `ConsumedFood` row.
  final int loggedDays;

  /// Mean kcal per logged day across the window, or null when the window has
  /// no logged day.
  final double? caloriesAverage;

  /// Mean protein grams per logged day across the window, or null when the
  /// window has no logged day.
  final double? proteinAverage;

  /// Mean total-carbs grams per logged day across the window, or null when
  /// the window has no logged day.
  final double? carbsAverage;

  /// Mean fat grams per logged day across the window, or null when the
  /// window has no logged day.
  final double? fatAverage;

  /// Mean kcal per logged day across the previous window of the same length,
  /// or null when that window has no logged day.
  final double? previousCaloriesAverage;

  /// Mean protein grams per logged day across the previous window, or null
  /// when that window has no logged day.
  final double? previousProteinAverage;

  /// Mean total-carbs grams per logged day across the previous window, or
  /// null when that window has no logged day.
  final double? previousCarbsAverage;

  /// Mean fat grams per logged day across the previous window, or null
  /// when that window has no logged day.
  final double? previousFatAverage;

  /// Mean kcal per logged day on the window's training days, or null when the
  /// window logged nothing on a training day.
  final double? trainingCaloriesAverage;

  /// Mean protein grams per logged day on the window's training days, or null
  /// when the window logged nothing on a training day.
  final double? trainingProteinAverage;

  /// Mean kcal per logged day on the window's rest days, or null when the
  /// window logged nothing on a rest day.
  final double? restCaloriesAverage;

  /// Mean protein grams per logged day on the window's rest days, or null
  /// when the window logged nothing on a rest day.
  final double? restProteinAverage;

  /// The day's calorie target, or `0` when none is set.
  final double targetCalories;

  /// The day's protein target, or `0` when none is set.
  final double targetProtein;

  /// The day's carbs target in total grams, or `0` when none is set.
  final double targetCarbs;

  /// The day's fat target, or `0` when none is set.
  final double targetFat;

  const FuelSummary({
    required this.loggedDays,
    required this.caloriesAverage,
    required this.proteinAverage,
    required this.carbsAverage,
    required this.fatAverage,
    required this.previousCaloriesAverage,
    required this.previousProteinAverage,
    required this.previousCarbsAverage,
    required this.previousFatAverage,
    required this.trainingCaloriesAverage,
    required this.trainingProteinAverage,
    required this.restCaloriesAverage,
    required this.restProteinAverage,
    required this.targetCalories,
    required this.targetProtein,
    required this.targetCarbs,
    required this.targetFat,
  });

  /// Whether calories carry a target to compare against. A field with no
  /// target is compared against the previous window instead.
  bool get hasCalorieTarget => targetCalories > 0;

  /// Whether protein carries a target to compare against.
  bool get hasProteinTarget => targetProtein > 0;

  /// Whether carbs carry a target to compare against.
  bool get hasCarbsTarget => targetCarbs > 0;

  /// Whether fat carries a target to compare against.
  bool get hasFatTarget => targetFat > 0;
}
