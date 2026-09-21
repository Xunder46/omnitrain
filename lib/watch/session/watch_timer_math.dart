/// Timer derivation for watch timer records.
///
/// A watch timer is nothing but persisted timestamps and pause bookkeeping; the
/// values the user sees are computed from the record and the current instant
/// (PROTOCOL.md, "Timer state (normative)"). That is what keeps a timer correct
/// across suspension, reboot, and a clock that kept running while the app did
/// not — no countdown is ever stored, so none can be stale.
///
/// The arithmetic is not here: it is [TimerInstants] in
/// `lib/core/sync_protocol/timer_derivation.dart`, which the phone reads from a
/// decoded `timer` object. These functions are the record-shaped face of it, so
/// the wrist and the phone derive the same answer from the same instant rather
/// than from two copies of the same formula.
library;

import '../../core/sync_protocol/timer_derivation.dart';
import 'watch_records.dart';

/// How long [timer] has actually been counting, as of [now].
///
/// A paused or stopped timer stops moving: its elapsed time is measured to the
/// pause or stop instant instead of to [now].
int activeElapsedMs(WatchTimerRecord timer, DateTime now) =>
    _instantsOf(timer).elapsedMs(now);

/// What is left of a countdown timer at [now], or null when the timer has no
/// planned duration (an elapsed timer counts up, it never counts down).
int? remainingMs(WatchTimerRecord timer, DateTime now) =>
    _instantsOf(timer).remainingMs(now);

/// The wall-clock instant [timer] reaches zero, or null when it has no planned
/// duration.
///
/// A pause postpones the instant, and the postponement is exactly the pause
/// bookkeeping the record carries. Whether the countdown got there is
/// [remainingMs]'s answer, not this one: a timer paused before its instant has
/// one in the past and still has time left.
DateTime? completionInstant(WatchTimerRecord timer) =>
    _instantsOf(timer).completionInstant();

TimerInstants _instantsOf(WatchTimerRecord timer) => TimerInstants(
  startedAt: timer.startedAt,
  pausedAt: timer.pausedAt,
  stoppedAt: timer.stoppedAt,
  accumulatedPauseMs: timer.accumulatedPauseMs,
  plannedDurationMs: timer.plannedDurationMs,
);
