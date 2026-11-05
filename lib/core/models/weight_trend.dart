// The weight line on Stats (plan 104): where the body weight stands and how it
// moved over the last four weeks. Pure Dart — no repository, no clock of its
// own: `now` is a parameter.

import '../../data/models/models.dart';
import '../constants/metric_ids.dart';

/// The span the line reads: the 28 local days ending today (D-17701).
const int kWeightTrendWindowDays = 28;

/// The fewest whole calendar days between the first and the last weigh-in
/// (D-17701): closer readings are noise, not a trend.
const int kWeightTrendMinSpanDays = 7;

/// The latest weigh-in in the window and the change since the earliest.
class WeightTrend {
  const WeightTrend({required this.latestKg, required this.changeKg});

  final double latestKg;

  /// Latest minus earliest, in kilograms.
  final double changeKg;
}

/// The weight trend of [entries] at [now], or null when the window holds fewer
/// than two usable weigh-ins or they are closer than [kWeightTrendMinSpanDays]
/// calendar days (D-17701).
WeightTrend? weightTrend({
  required List<BodyMeasurementEntry> entries,
  required DateTime now,
}) {
  final fromMs = DateTime(
    now.year,
    now.month,
    now.day - (kWeightTrendWindowDays - 1),
  ).millisecondsSinceEpoch;
  final endMs = DateTime(now.year, now.month, now.day + 1).millisecondsSinceEpoch;

  final usable = entries
      .where(
        (e) =>
            e.measurementType == 'bodyweight' &&
            e.unitId == MetricIds.unitKg &&
            e.value > 0 &&
            e.recordedAtMs >= fromMs &&
            e.recordedAtMs < endMs,
      )
      .toList()
    ..sort((a, b) => a.recordedAtMs.compareTo(b.recordedAtMs));
  if (usable.length < 2) return null;

  final first = usable.first;
  final last = usable.last;
  final firstDay = DateTime.fromMillisecondsSinceEpoch(first.recordedAtMs);
  final lastDay = DateTime.fromMillisecondsSinceEpoch(last.recordedAtMs);
  // Calendar days apart on the dates re-read as UTC, so a clock change inside
  // the window never turns a true week into 6 days and 23 hours.
  final apart = DateTime.utc(lastDay.year, lastDay.month, lastDay.day)
      .difference(DateTime.utc(firstDay.year, firstDay.month, firstDay.day))
      .inDays;
  if (apart < kWeightTrendMinSpanDays) return null;

  return WeightTrend(
    latestKg: last.value,
    changeKg: last.value - first.value,
  );
}

/// The line the Weight block reads (D-17702), in the figures [latest] and
/// [change] already converted to [unitLabel]'s unit.
String weightTrendLine({
  required double latest,
  required double change,
  required String unitLabel,
}) {
  final magnitude = double.parse(change.abs().toStringAsFixed(1));
  final changeText = magnitude == 0
      ? 'no change'
      : '${change < 0 ? '−' : '+'}${magnitude.toStringAsFixed(1)} $unitLabel';
  return '${latest.toStringAsFixed(1)} $unitLabel, $changeText over '
      '${kWeightTrendWindowDays ~/ 7} weeks';
}
