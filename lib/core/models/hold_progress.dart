// The Hold Progress signal's rule (plan 106): an isometric exercise whose
// longest hold in the Stats window beat its longest hold in the window before
// by enough to mean something. Pure Dart: the rule reads the Instruments rows
// the screen already shows.

import 'exercise_metric.dart';
import 'instrument_list.dart';

/// The fewest completed sessions the exercise has in the window (D-17902).
const int kHoldProgressMinSessions = 3;

/// The smallest gain in seconds (D-17902), inclusive.
const int kHoldProgressMinGainSecs = 10;

/// The smallest gain as a percentage of the earlier longest hold (D-17902),
/// inclusive.
const int kHoldProgressMinGainPercent = 10;

/// Hold Progress ranks below Consistency among the positives.
const int kHoldProgressPriority = 40;

/// The exercise whose longest hold improved the most.
class HoldProgressResult {
  const HoldProgressResult({
    required this.name,
    required this.exerciseId,
    required this.recentSecs,
    required this.previousSecs,
  });

  final String name;
  final String exerciseId;

  /// The longest hold in the window, whole seconds.
  final int recentSecs;

  /// The longest hold in the window before it, whole seconds.
  final int previousSecs;

  int get gainSecs => recentSecs - previousSecs;
}

/// The Hold Progress result for [sections], or null (D-17902).
HoldProgressResult? holdProgress(List<InstrumentSectionData> sections) {
  HoldProgressResult? best;
  for (final section in sections) {
    if (section.section != ExerciseSection.isometric) continue;
    for (final row in section.rows) {
      final previous = row.previousValue;
      if (previous == null) continue;
      if (row.summary.best.metric != NativeMetric.hold ||
          previous.metric != NativeMetric.hold) {
        continue;
      }
      if (row.summary.sessionCount < kHoldProgressMinSessions) continue;

      final recentSecs = row.summary.best.value.round();
      final previousSecs = previous.value.round();
      if (previousSecs <= 0) continue;
      final gain = recentSecs - previousSecs;
      if (gain < kHoldProgressMinGainSecs) continue;
      if (100 * gain < kHoldProgressMinGainPercent * previousSecs) continue;

      final candidate = HoldProgressResult(
        name: row.summary.name,
        exerciseId: row.summary.exerciseId,
        recentSecs: recentSecs,
        previousSecs: previousSecs,
      );
      if (best == null || _beats(candidate, best)) best = candidate;
    }
  }
  return best;
}

bool _beats(HoldProgressResult a, HoldProgressResult b) {
  if (a.gainSecs != b.gainSecs) return a.gainSecs > b.gainSecs;
  final byName = a.name.compareTo(b.name);
  if (byName != 0) return byName < 0;
  return a.exerciseId.compareTo(b.exerciseId) < 0;
}

/// The observation on the Hold Progress card (D-17903).
String holdProgressObservation(
  HoldProgressResult result, {
  required int weeks,
}) =>
    'Your longest hold on ${result.name} is up ${result.gainSecs} s over the '
    'last $weeks weeks, now ${result.recentSecs} s.';
