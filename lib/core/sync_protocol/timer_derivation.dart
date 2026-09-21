/// Timer derivation, shared by every sync-protocol client on this side.
///
/// Timers travel as wall-clock timestamps plus pause bookkeeping and never as a
/// countdown (PROTOCOL.md, "Timer state (normative)"): what the user sees is
/// derived from the payload and the reader's own clock, which is what keeps a
/// timer correct across backgrounding, reconnect, and clock drift between
/// devices.
///
/// The arithmetic lives here once. A reader holding a decoded `timer` object
/// builds [TimerInstants.fromJson]; a reader holding a stored watch record
/// builds the same [TimerInstants] from the record's fields (see
/// `lib/watch/session/watch_timer_math.dart`). Both then agree by construction
/// rather than by two implementations happening to match — which is why a rest
/// timer started on the wrist ends at the same moment on the phone (S-005).
library;

/// The timestamps and bookkeeping a timer carries, however it is stored.
///
/// Pause accounting is a field rather than something derived, because a
/// finished pause leaves no other trace: `pausedAt` clears on resume, and the
/// time the pause consumed survives only in [accumulatedPauseMs].
class TimerInstants {
  const TimerInstants({
    required this.startedAt,
    this.pausedAt,
    this.stoppedAt,
    this.accumulatedPauseMs = 0,
    this.plannedDurationMs,
  });

  /// The protocol's `timer` object.
  factory TimerInstants.fromJson(Map<String, Object?> timer) => TimerInstants(
    startedAt: DateTime.parse(timer['startedAt']! as String),
    pausedAt: _instant(timer['pausedAt']),
    stoppedAt: _instant(timer['stoppedAt']),
    accumulatedPauseMs: (timer['accumulatedPauseMs'] as int?) ?? 0,
    plannedDurationMs: timer['plannedDurationMs'] as int?,
  );

  final DateTime startedAt;

  /// When the current pause began, or null while the timer runs.
  final DateTime? pausedAt;

  final DateTime? stoppedAt;

  /// Total length of every pause that has already ended.
  final int accumulatedPauseMs;

  /// Planned length, when the timer counts down. Null for elapsed timers.
  final int? plannedDurationMs;

  /// How long the timer has actually been counting, as of [now].
  ///
  /// A paused or stopped timer stops moving: its elapsed time is measured to
  /// the pause or stop instant instead of to [now].
  int elapsedMs(DateTime now) {
    final countedUntil = stoppedAt ?? pausedAt ?? now;
    final elapsed =
        countedUntil.difference(startedAt).inMilliseconds - accumulatedPauseMs;
    return elapsed < 0 ? 0 : elapsed;
  }

  /// What is left of a countdown at [now], or null when the timer has no
  /// planned duration — an elapsed timer counts up, it never counts down.
  int? remainingMs(DateTime now) {
    final planned = plannedDurationMs;
    if (planned == null) return null;

    final remaining = planned - elapsedMs(now);
    return remaining < 0 ? 0 : remaining;
  }

  /// The wall-clock instant the countdown reaches zero, or null when the timer
  /// has no planned duration.
  ///
  /// A pause postpones the instant, and the postponement is exactly
  /// [accumulatedPauseMs]. Whether the countdown got there is [remainingMs]'s
  /// answer, not this one: a timer paused before its instant has one in the
  /// past and still has time left.
  DateTime? completionInstant() {
    final planned = plannedDurationMs;
    if (planned == null) return null;

    return startedAt.add(Duration(milliseconds: planned + accumulatedPauseMs));
  }
}

/// How long the timer in [timer] has been counting, as of [now].
int timerActiveElapsedMs(Map<String, Object?> timer, DateTime now) =>
    TimerInstants.fromJson(timer).elapsedMs(now);

/// What is left of the timer in [timer] at [now], or null when it has no
/// planned duration.
int? timerRemainingMs(Map<String, Object?> timer, DateTime now) =>
    TimerInstants.fromJson(timer).remainingMs(now);

/// The wall-clock instant the timer in [timer] reaches zero, or null when it
/// has no planned duration.
DateTime? timerCompletionInstant(Map<String, Object?> timer) =>
    TimerInstants.fromJson(timer).completionInstant();

DateTime? _instant(Object? value) =>
    value is String ? DateTime.parse(value) : null;
