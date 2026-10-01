/// Plain Dart value types for the Instruments list.
///
/// The Instruments list is a "where did my training go" list: one section per
/// kind of work the window holds, ordered by how many days that kind was
/// trained on, and one row per exercise inside it. A row carries the exercise's
/// native value (4a's [ExerciseMetricSummary]), the same exercise's value over
/// the immediately preceding range so a change can be shown, and the sensor
/// figures the row's section reads.
///
/// No Flutter imports and no persistence: nothing here is stored.
library;

import 'exercise_metric.dart';

/// One exercise's line in an Instruments section.
class InstrumentRow {
  /// The exercise's window value, its per-day series and its session count.
  /// [ExerciseMetricSummary.best] is the figure the row shows and
  /// [ExerciseMetricSummary.points] is its sparkline.
  final ExerciseMetricSummary summary;

  /// The same exercise's value over the immediately preceding range of the
  /// same calendar length, or null when there is nothing comparable to show —
  /// no summary in that range, or one whose metric differs from the window's.
  final NativeValue? previousValue;

  /// Steps per minute over the exercise's timed instances in the window that
  /// carry a step count. Cardio rows only, and null when none does.
  final int? cadenceStepsPerMin;

  /// The mean heart rate over the exercise's timed (Cardio) or round (Sports)
  /// instance summaries in the window. Null on Resistance and Isometric rows,
  /// and when no summary carries a reading.
  final int? averageHeartRateBpm;

  const InstrumentRow({
    required this.summary,
    this.previousValue,
    this.cadenceStepsPerMin,
    this.averageHeartRateBpm,
  });
}

/// One section of the Instruments list: the kind of work, its rows in display
/// order, and the rank that decided where the section sits.
class InstrumentSectionData {
  final ExerciseSection section;

  /// The section's rows, most-frequently-trained first.
  final List<InstrumentRow> rows;

  /// The number of distinct days in the window on which an effort of this
  /// kind was logged — the section's ordering rank.
  final int trainingDayCount;

  const InstrumentSectionData({
    required this.section,
    required this.rows,
    required this.trainingDayCount,
  });
}
