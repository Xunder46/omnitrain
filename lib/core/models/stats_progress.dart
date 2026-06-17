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

  /// The "current window" that decided which exercises were eligible
  /// for [topLifts] and [topCardio]. The window is a date range plus
  /// a human-readable label so the UI can explain its selection.
  /// The trend charts for selected exercises and the Recent PRs
  /// list are NOT restricted by this window — they use full
  /// history.
  final StatsWindow window;

  const StatsProgressData({
    required this.topLifts,
    required this.topCardio,
    required this.recentPRs,
    this.nutritionTrend = const [],
    required this.window,
  });

  static final StatsProgressData empty = StatsProgressData(
    topLifts: const [],
    topCardio: const [],
    recentPRs: const [],
    window: StatsWindow.empty,
  );
}

/// The "current window" used to select which exercises appear in the
/// Stats screen's Strength and Cardio sections. Resolved once per
/// `StatsProgressService.computeProgressData()` call from either:
///   - the user-defined training period that covers today and contains
///     at least one qualifying completed session, or
///   - the most recent N "training days" (calendar days with at
///     least one completed session) when no period qualifies, where
///     N is `StatsProgressService.kRecentTrainingDaysWindow`.
///
/// Only the exercise **selection** is restricted to this window;
/// trend charts for the selected exercises and the Recent PRs list
/// continue to use full history (progression lives there, and a
/// PR's whole point is being a lifetime high).
class StatsWindow {
  /// Local-midnight `DateTime` for the start of the window. When
  /// the window has no qualifying days (zero training days), this
  /// is start-of-today so the filter cleanly yields zero sessions.
  final DateTime fromMs;

  /// End-of-day `DateTime` for the end of the window (today by
  /// default; the period's end-day when period-scoped).
  final DateTime toMs;

  /// Human-readable label for the on-screen window chip.
  /// e.g. `"Off-Season Strength Block"` or `"Last 14 training days"`.
  final String label;

  /// True when the window was resolved from a `TrainingPeriod`;
  /// false when it was resolved from recent training days.
  final bool isPeriodScoped;

  /// Period id when [isPeriodScoped]; null otherwise.
  final String? periodId;

  /// Period name when [isPeriodScoped]; null otherwise. Mirrors
  /// [label] for period-scoped windows but kept separate so the
  /// UI can map back to the period row if it wants to highlight
  /// the period's color.
  final String? periodName;

  /// N (number of training days) when `!isPeriodScoped`; null
  /// otherwise. The size of the window in calendar-day slots,
  /// measured by "training days" (distinct days with ≥1 completed
  /// session) — not calendar days, so rest days do not shrink
  /// the data.
  final int? recentDays;

  const StatsWindow({
    required this.fromMs,
    required this.toMs,
    required this.label,
    required this.isPeriodScoped,
    this.periodId,
    this.periodName,
    this.recentDays,
  });

  /// True when this window was resolved to a real, non-empty set of
  /// sessions. A recent-days window with zero training days returns
  /// false (and the Stats screen renders its existing empty states
  /// for both sections).
  bool get hasData => !isPeriodScoped
      ? (recentDays != null && recentDays! > 0)
      : true;

  /// Sentinel empty window used by [StatsProgressData.empty].
  /// Not user-visible; the screen never reaches this state because
  /// `computeProgressData` always resolves a real window from
  /// periods or recent days.
  static final StatsWindow empty = StatsWindow(
    fromMs: DateTime.fromMillisecondsSinceEpoch(0),
    toMs: DateTime.fromMillisecondsSinceEpoch(0),
    label: 'No data',
    isPeriodScoped: false,
    recentDays: 0,
  );
}
