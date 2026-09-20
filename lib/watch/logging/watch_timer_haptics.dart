/// When the wrist is owed a haptic, derived from the timer's own timestamps.
///
/// Plan: `.github/agents/plans/2026-07-13-07-a2-watch-wrist-logging-surfaces-plan.md`,
/// scenarios S-003 and S-005.
///
/// Nothing here counts down. A countdown's end is a property of the timer
/// record and the current instant, so the case where the screen was off is not
/// a special case: the surface polls on every tick, on every touch, and on
/// resume, and the first poll after the instant fires once and reports the
/// instant it was due (`watch_logging_timers_test.dart`).
library;

import '../session/watch_records.dart';
import '../session/watch_session_engine.dart';
import '../session/watch_timer_math.dart';

/// A countdown that reached zero, and the wall-clock moment it did.
class WatchTimerMilestone {
  const WatchTimerMilestone({required this.kind, required this.at});

  /// One of [WatchTimerKind].
  final String kind;

  /// `startedAt + plannedDurationMs + accumulatedPauseMs`: when the countdown
  /// reached zero, whatever instant it is being noticed at.
  final DateTime at;

  @override
  bool operator ==(Object other) =>
      other is WatchTimerMilestone && other.kind == kind && other.at == at;

  @override
  int get hashCode => Object.hash(kind, at);

  @override
  String toString() => 'WatchTimerMilestone($kind at ${at.toIso8601String()})';
}

/// Decides which countdowns the user is owed a haptic for.
class WatchTimerHaptics {
  WatchTimerHaptics(this._engine);

  final WatchSessionEngine _engine;

  /// Timer rows already announced. Keyed on the record rather than the kind, so
  /// the next round's countdown — a new row — is owed its own haptic.
  final Set<String> _announced = {};

  /// The countdowns that reached zero as of [now] and have not been announced.
  ///
  /// A timer with no planned duration never reaches zero; one that was ended
  /// before its instant never got there; one that was ended afterwards did.
  List<WatchTimerMilestone> poll(DateTime now) {
    final milestones = <WatchTimerMilestone>[];

    for (final kind in WatchTimerKind.all) {
      final timer = _engine.timerFor(kind);
      if (timer == null) continue;
      if (remainingMs(timer, now) != 0) continue;
      if (!_announced.add(timer.recordId)) continue;

      milestones.add(
        WatchTimerMilestone(kind: kind, at: completionInstant(timer) ?? now),
      );
    }

    return milestones;
  }
}
