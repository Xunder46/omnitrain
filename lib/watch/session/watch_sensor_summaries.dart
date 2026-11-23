/// What the wrist reports about a session from the sensor samples it stored.
///
/// Plan: `docs/plans/2026-11-22-305-wear-calories-dart-plan/2026-11-22-305-wear-calories-dart-plan.md`
/// (D-30503). The Dart twin of the Apple client's `WatchSensorSummaries`, for
/// the part the Wear wrist sends: the session's active energy.
library;

import 'watch_records.dart';

abstract final class WatchSensorSummaries {
  /// The active energy burned inside `[start, end]`, from the platform's
  /// cumulative kilocalorie counter, or null when no count was sampled inside
  /// the window.
  ///
  /// The chain starts at the last count before the window (zero when there is
  /// none) and adds each step forward. A count smaller than the one before it
  /// means the counter restarted (a recovered workout), so the new count is
  /// itself the energy since the restart. A total that rounds to zero is null:
  /// it is never sent.
  static double? activeEnergy(
    Iterable<WatchSensorSampleRecord> samples,
    DateTime start,
    DateTime end,
  ) {
    final first = start.toUtc().millisecondsSinceEpoch;
    final last = end.toUtc().millisecondsSinceEpoch;

    final counts = [
      for (final sample in samples)
        if (sample.kind == WatchSensorKind.activeEnergy &&
            sample.value.isFinite &&
            sample.value >= 0)
          sample,
    ]..sort(_byTime);
    final inside = [
      for (final sample in counts)
        if (_ms(sample) >= first && _ms(sample) <= last) sample,
    ];
    if (inside.isEmpty) return null;

    var previous = 0.0;
    for (final sample in counts) {
      if (_ms(sample) < first) previous = sample.value;
    }
    var total = 0.0;
    for (final sample in inside) {
      total += sample.value >= previous
          ? sample.value - previous
          : sample.value;
      previous = sample.value;
    }
    final rounded = (total * 10).roundToDouble() / 10;
    return rounded > 0 ? rounded : null;
  }

  static int _ms(WatchSensorSampleRecord sample) =>
      sample.recordedAt.toUtc().millisecondsSinceEpoch;

  static int _byTime(WatchSensorSampleRecord a, WatchSensorSampleRecord b) {
    final byTime = _ms(a).compareTo(_ms(b));
    return byTime != 0 ? byTime : a.sequence.compareTo(b.sequence);
  }
}
