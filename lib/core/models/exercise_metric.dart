/// Plain Dart value types for one exercise's native value.
///
/// An exercise's **section** is the effort kind it was logged under, and its
/// **native value** is the single number that section is read by: an estimated
/// one-rep max or a rep count, a pace or a duration, a hold, a round count.
/// The section decides which metric the value carries, so a screen can chart
/// one exercise's history without asking what kind of effort produced it.
///
/// No Flutter imports and no persistence: nothing here is stored.
library;

/// The four sections an exercise can sit in, in display order.
enum ExerciseSection { resistance, cardio, isometric, sports }

extension ExerciseSectionLabel on ExerciseSection {
  /// The name a user reads.
  String get label {
    switch (this) {
      case ExerciseSection.resistance:
        return 'Resistance';
      case ExerciseSection.cardio:
        return 'Cardio';
      case ExerciseSection.isometric:
        return 'Isometric';
      case ExerciseSection.sports:
        return 'Sports';
    }
  }
}

/// The metric a [NativeValue] carries.
///
/// [pace] is seconds per kilometre, so a *lower* value is the better one; every
/// other metric is higher-is-better. [duration] and [hold] are seconds,
/// [roundMinutes] is minutes.
enum NativeMetric {
  estimatedOneRepMax,
  reps,
  pace,
  duration,
  hold,
  rounds,
  roundMinutes,
}

/// One exercise's value on its native metric.
class NativeValue {
  final NativeMetric metric;
  final double value;

  /// A second figure shown beside [value] — a hold's total time, a round
  /// count's total minutes. Null when the metric carries no second figure.
  final NativeMetric? secondaryMetric;
  final double? secondaryValue;

  /// True when a distance behind the value is an estimate rather than a
  /// measurement or someone's entry.
  final bool estimated;

  /// Added weight in kg carried by the effort the value came from, when it is
  /// greater than zero. Annotation only: it never decides the metric.
  final double? addedWeightKg;

  const NativeValue({
    required this.metric,
    required this.value,
    this.secondaryMetric,
    this.secondaryValue,
    this.estimated = false,
    this.addedWeightKg,
  });
}

/// One training day of an exercise's native-value series.
class ExerciseMetricPoint {
  /// Midnight, local time, of the day the session started.
  final int dayMs;

  final NativeValue value;

  const ExerciseMetricPoint({required this.dayMs, required this.value});
}

/// Everything one exercise's history yields, over the requested range.
class ExerciseMetricSummary {
  final String exerciseId;

  /// The catalog name, or the raw id when the catalog row is gone.
  final String name;

  final ExerciseSection section;

  /// The best value over the range, never null: an exercise with no usable data
  /// reports a zero on the metric its section uses.
  final NativeValue best;

  /// One point per training day, oldest first. A day that yields no value for
  /// the exercise's metric contributes no point.
  final List<ExerciseMetricPoint> points;

  /// The start of the most recent completed session, in range, that logged the
  /// exercise.
  final int lastTrainedMs;

  /// How many completed sessions in range logged the exercise.
  final int sessionCount;

  const ExerciseMetricSummary({
    required this.exerciseId,
    required this.name,
    required this.section,
    required this.best,
    required this.points,
    required this.lastTrainedMs,
    required this.sessionCount,
  });
}

/// The all-time totals the Stats screen and Records & Trends share.
class StatsTotals {
  /// Sessions with an end time. A rolling session counts here.
  final int completedSessions;

  /// The summed length of every completed session that is not rolling.
  final int durationMs;

  const StatsTotals({
    required this.completedSessions,
    required this.durationMs,
  });
}
