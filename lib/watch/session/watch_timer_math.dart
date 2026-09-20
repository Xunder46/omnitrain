/// Timer derivation.
///
/// A watch timer is nothing but persisted timestamps and pause bookkeeping; the
/// values the user sees are computed from the record and the current instant
/// (PROTOCOL.md, "Timer state (normative)"). That is what keeps a timer correct
/// across suspension, reboot, and a clock that kept running while the app did
/// not — no countdown is ever stored, so none can be stale.
library;

import 'watch_records.dart';

/// How long [timer] has actually been counting, as of [now].
///
/// A paused or stopped timer stops moving: its elapsed time is measured to the
/// pause or stop instant instead of to [now].
int activeElapsedMs(WatchTimerRecord timer, DateTime now) {
  final countedUntil = timer.stoppedAt ?? timer.pausedAt ?? now;
  final elapsed =
      countedUntil.difference(timer.startedAt).inMilliseconds -
      timer.accumulatedPauseMs;
  return elapsed < 0 ? 0 : elapsed;
}

/// What is left of a countdown timer at [now], or null when the timer has no
/// planned duration (an elapsed timer counts up, it never counts down).
int? remainingMs(WatchTimerRecord timer, DateTime now) {
  final planned = timer.plannedDurationMs;
  if (planned == null) return null;

  final remaining = planned - activeElapsedMs(timer, now);
  return remaining < 0 ? 0 : remaining;
}
