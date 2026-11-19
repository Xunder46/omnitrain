/// The Fuel section's figures, as `StatsProgressService.computeFuelSummary()`
/// produces them.
///
/// The window is the `StatsProgressService.kFuelWindowDays` finished days
/// ending yesterday; today is in neither the window nor the previous range.
///
/// Every average is a mean over **logged days only** — a day with at least one
/// `ConsumedFood` row — so a week with three logged days divides by three, not
/// by the length of the window. An average whose day-set is empty is `null`
/// rather than `0`, so a side with nothing logged reads as an absence instead
/// of a zero-calorie day.
///
/// Plain Dart: this is a value type, not a persisted record.
library;

/// Logged days the Fuel row needs before it shows averages.
const int kFuelMinLoggedDays = 3;

/// Logged days each side of the training/rest split needs before the Fuel row
/// draws the split.
const int kFuelMinSplitDays = 2;

/// Days with Health active-energy data the Fuel row needs before it shows
/// Burned per day.
const int kFuelMinActiveEnergyDays = 3;

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

  /// Logged days in the window that fall on a training day.
  final int trainingLoggedDays;

  /// Mean kcal per logged day on the window's rest days, or null when the
  /// window logged nothing on a rest day.
  final double? restCaloriesAverage;

  /// Logged days in the window that fall on a rest day.
  final int restLoggedDays;

  /// Mean stored active kcal over the window's finished sessions that carry
  /// an energy row — the burned-per-session average — or null when no such
  /// session has one.
  final double? burnedKcalAverage;

  /// How many window sessions contributed to [burnedKcalAverage].
  final int burnedSessionCount;

  /// Whether at least one row feeding [burnedKcalAverage] is an estimate, so
  /// the average carries a `~` on screen.
  final bool burnedIsEstimate;

  /// Mean daily active kcal from the platform health store over the window's
  /// days that have data (at least [kFuelMinActiveEnergyDays] of them), or null.
  final double? burnedPerDayAverage;

  /// Whether food was logged in the last `kFuelVisibilityDays` days. False
  /// means the card is in burn-only mode: no intake part, no tap (plan 208 D-19);
  /// `loggedDays` is 0 and every intake average is null then.
  final bool hasRecentFood;

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
    required this.trainingLoggedDays,
    required this.restCaloriesAverage,
    required this.restLoggedDays,
    this.burnedKcalAverage,
    this.burnedSessionCount = 0,
    this.burnedIsEstimate = false,
    this.burnedPerDayAverage,
    this.hasRecentFood = true,
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

  /// Whether the window holds enough logged days for its averages to be shown.
  /// Below [kFuelMinLoggedDays] the row says so in words instead (D-17204); the
  /// figures are still carried so the model stays complete.
  bool get showsAverages => loggedDays >= kFuelMinLoggedDays;

  /// Whether the Training/Rest split is drawn: the window shows averages and
  /// BOTH sides hold at least [kFuelMinSplitDays] logged days. Otherwise the
  /// split is absent, never a dash line.
  bool get showsSplit =>
      showsAverages &&
      trainingCaloriesAverage != null &&
      restCaloriesAverage != null &&
      trainingLoggedDays >= kFuelMinSplitDays &&
      restLoggedDays >= kFuelMinSplitDays;

  /// Whether the Burned-per-day line draws. The [kFuelMinActiveEnergyDays]
  /// floor is applied where the average is made, so a present value is always
  /// showable.
  bool get showsBurnedPerDay => burnedPerDayAverage != null;
}
