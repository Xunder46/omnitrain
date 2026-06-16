/// Plain Dart value types for Stats screen progress views.
/// No Flutter imports — safe to use in pure unit tests.
library;

/// A single chronological data point in a trend series.
class TrendPoint {
  final DateTime date;
  final double value;

  const TrendPoint({required this.date, required this.value});
}

/// A single chronological data point in a cardio trend series.
class CardioTrendPoint {
  final DateTime date;
  final int durationSecs;

  /// Total distance in metres for the training day. Null if no distance was logged.
  final double? distanceM;

  /// Pace in seconds per kilometre. Null if no distance was logged or distanceM == 0.
  final double? paceSecPerKm;

  const CardioTrendPoint({
    required this.date,
    required this.durationSecs,
    this.distanceM,
    this.paceSecPerKm,
  });
}

/// Strength progress for one exercise (e1RM and volume trends).
class LiftProgress {
  final String exerciseName;

  /// Max e1RM per training day, sorted chronologically.
  final List<TrendPoint> e1RmTrend;

  /// Total volume (reps × weight) per training day, sorted chronologically.
  final List<TrendPoint> volumeTrend;

  const LiftProgress({
    required this.exerciseName,
    required this.e1RmTrend,
    required this.volumeTrend,
  });
}

/// Cardio progress for one exercise.
class CardioProgress {
  final String exerciseName;

  /// Aggregated cardio data per training day, sorted chronologically.
  final List<CardioTrendPoint> trend;

  const CardioProgress({required this.exerciseName, required this.trend});
}

/// A personal record event (new all-time e1RM high for an exercise).
class StatsPR {
  final String exerciseName;
  final double e1Rm;
  final DateTime date;

  const StatsPR({
    required this.exerciseName,
    required this.e1Rm,
    required this.date,
  });
}

/// A single chronological data point in the Stats-screen nutrition
/// trend (NUTRITION card).
///
/// Sums the same day's [ConsumedFood] rows: calories from each
/// row's pre-rounded [ConsumedFood.caloriesConsumed], macro grams
/// from `macro × amountConsumed / referenceAmount` accumulated as
/// a double and rounded **once** per day. Days with no logged food
/// are skipped, not zero-filled.
class NutritionTrendPoint {
  /// Local-midnight `DateTime` for the day this point represents.
  final DateTime date;

  /// Σ [ConsumedFood.caloriesConsumed] for the day (kcal).
  final int calories;

  /// Σ `(protein × amountConsumed / referenceAmount)` for the day,
  /// accumulated as double and rounded once.
  final int protein;

  /// Σ `(carbs × amountConsumed / referenceAmount)` for the day,
  /// accumulated as double and rounded once. Uses **total** carbs
  /// grams (not net carbs) so the line colour slot — which is
  /// `macroChart.netCarbs` because the donut reuses it — still
  /// matches the home strip's "total carbs for blue" semantics.
  final int carbs;

  /// Σ `(fat × amountConsumed / referenceAmount)` for the day,
  /// accumulated as double and rounded once.
  final int fat;

  const NutritionTrendPoint({
    required this.date,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
  });
}

/// Top-level container returned by [StatsProgressService].
class StatsProgressData {
  /// Up to [StatsProgressService.kTopLiftCount] lifts, sorted by training frequency.
  final List<LiftProgress> topLifts;

  /// Up to [StatsProgressService.kTopCardioCount] activities, sorted by training frequency.
  final List<CardioProgress> topCardio;

  /// Most-recent personal records across all tracked lifts (newest first).
  final List<StatsPR> recentPRs;

  /// Per-day nutrition trend for the NUTRITION card on the Stats
  /// screen, sorted ascending by date. Days with no logged food are
  /// skipped (not zero-filled). Empty list = no food logged in the
  /// window; the card hides itself in that case.
  final List<NutritionTrendPoint> nutritionTrend;

  const StatsProgressData({
    required this.topLifts,
    required this.topCardio,
    required this.recentPRs,
    this.nutritionTrend = const [],
  });

  static const StatsProgressData empty = StatsProgressData(
    topLifts: [],
    topCardio: [],
    recentPRs: [],
  );
}
