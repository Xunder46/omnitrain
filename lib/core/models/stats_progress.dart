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

/// Top-level container returned by [StatsProgressService].
class StatsProgressData {
  /// Up to [StatsProgressService.kTopLiftCount] lifts, sorted by training frequency.
  final List<LiftProgress> topLifts;

  /// Up to [StatsProgressService.kTopCardioCount] activities, sorted by training frequency.
  final List<CardioProgress> topCardio;

  /// Most-recent personal records across all tracked lifts (newest first).
  final List<StatsPR> recentPRs;

  const StatsProgressData({
    required this.topLifts,
    required this.topCardio,
    required this.recentPRs,
  });

  static const StatsProgressData empty = StatsProgressData(
    topLifts: [],
    topCardio: [],
    recentPRs: [],
  );
}
