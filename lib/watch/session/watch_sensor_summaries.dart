/// What the wrist reports about a session from the sensor samples it stored.
///
/// Plan: `docs/plans/2026-11-22-305-wear-calories-dart-plan/2026-11-22-305-wear-calories-dart-plan.md`
/// (D-30503). The Dart twin of the Apple client's `WatchSensorSummaries`, for
/// the part the Wear wrist sends: the session's active energy.
library;

import 'dart:math' as math;

import 'watch_records.dart';

/// One heart-rate pair over a window: what the wire carries as
/// `avgHeartRateBpm` and `maxHeartRateBpm`. The two always travel together.
final class WatchHeartRateSummary {
  const WatchHeartRateSummary({
    required this.averageBpm,
    required this.maximumBpm,
  });

  /// The arithmetic mean of the qualifying readings, unrounded.
  final double averageBpm;

  /// The largest qualifying reading.
  final double maximumBpm;

  /// The pair in the protocol's field names.
  Map<String, Object?> get fields => {
    'avgHeartRateBpm': averageBpm,
    'maxHeartRateBpm': maximumBpm,
  };
}

/// A set block: every set of one session logged for one slot and exercise,
/// and the span its heart rate is summarised over (plan 310, D-31003).
final class WatchSetBlockSpan {
  const WatchSetBlockSpan({
    required this.sessionExerciseId,
    required this.exerciseId,
    required this.startedAt,
    required this.endedAt,
  });

  final String sessionExerciseId;
  final String exerciseId;

  /// The `loggedAt` of the latest effort entry logged strictly before the
  /// block's first set, or the session's start when there is none.
  final DateTime startedAt;

  /// The block's last set's `loggedAt`.
  final DateTime endedAt;
}

/// A stretch of a window the wrist's timer was paused for: `[start, end)`,
/// half-open, so the instant a timer resumes counts again (plan 311, D-31101).
final class WatchPauseInterval {
  const WatchPauseInterval({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}

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

  /// The lowest reading that is a heart rate: the protocol's own minimum for
  /// the heart-rate fields, so a pair built from qualifying readings is always
  /// sendable.
  static const double lowestHeartRateBpm = 1;

  /// The heart-rate pair over `[start, end]`, both ends inclusive, or null when
  /// no reading qualifies. Absence is the answer to "nothing was measured",
  /// never zero.
  ///
  /// A reading inside any of [excluding]'s `[start, end)` intervals — the
  /// stretches of the window the timer was paused for (plan 311, D-31101) — is
  /// left out: the instant a timer resumes counts again.
  static WatchHeartRateSummary? heartRate(
    Iterable<WatchSensorSampleRecord> samples,
    DateTime start,
    DateTime end, {
    List<WatchPauseInterval> excluding = const [],
  }) {
    final first = start.toUtc().millisecondsSinceEpoch;
    final last = end.toUtc().millisecondsSinceEpoch;
    final paused = [
      for (final pause in excluding)
        (
          pause.start.toUtc().millisecondsSinceEpoch,
          pause.end.toUtc().millisecondsSinceEpoch,
        ),
    ];

    final readings = <double>[];
    for (final sample in samples) {
      if (sample.kind != WatchSensorKind.heartRate) continue;
      if (!sample.value.isFinite || sample.value < lowestHeartRateBpm) continue;
      final at = _ms(sample);
      if (at < first || at > last) continue;
      if (paused.any((pause) => at >= pause.$1 && at < pause.$2)) continue;
      readings.add(sample.value);
    }
    if (readings.isEmpty) return null;

    var lowest = readings.first;
    var highest = readings.first;
    var sum = 0.0;
    for (final reading in readings) {
      if (reading < lowest) lowest = reading;
      if (reading > highest) highest = reading;
      sum += reading;
    }
    // The mean lies between the extremes; the clamp only removes the
    // floating-point noise that could nudge an average of equal readings past
    // its own maximum.
    final mean = sum / readings.length;
    return WatchHeartRateSummary(
      averageBpm: mean < lowest ? lowest : (mean > highest ? highest : mean),
      maximumBpm: highest,
    );
  }

  /// The pauses of the timer that started at [startedAt], read from its stored
  /// rows (plan 311, D-31102).
  ///
  /// A pause begins at a row's `pausedAt`. It ends where that timer next ran
  /// again (the first later row without a `pausedAt`: that row's `recordedAt`)
  /// or, when it never did, where the row itself stopped, or else at
  /// [windowEnd]. [rows] are one timer kind of one session; the rows of the
  /// timer that timed the entry are the ones that share its start.
  static List<WatchPauseInterval> pauses(
    Iterable<WatchTimerRecord> rows,
    DateTime startedAt,
    DateTime windowEnd,
  ) {
    final started = startedAt.toUtc().millisecondsSinceEpoch;
    final timer = [
      for (final row in rows)
        if (row.startedAt.toUtc().millisecondsSinceEpoch == started) row,
    ]..sort((a, b) => a.sequence.compareTo(b.sequence));

    final intervals = <WatchPauseInterval>[];
    for (var index = 0; index < timer.length; index++) {
      final pausedAt = timer[index].pausedAt;
      if (pausedAt == null) continue;
      DateTime? resumedAt;
      for (var next = index + 1; next < timer.length; next++) {
        if (timer[next].pausedAt == null) {
          resumedAt = timer[next].recordedAt;
          break;
        }
      }
      intervals.add(
        WatchPauseInterval(
          start: pausedAt,
          end: resumedAt ?? timer[index].stoppedAt ?? windowEnd,
        ),
      );
    }
    return intervals;
  }

  /// A round's pause as the wire carries it: the countdown's accumulated pause
  /// plus any pause still open, counted up to the window's end, and never
  /// longer than the window, which is the protocol's own rule for the field.
  static int pausedMs(
    WatchTimerRecord countdown,
    DateTime windowStart,
    DateTime windowEnd,
  ) {
    int ms(DateTime instant) => instant.toUtc().millisecondsSinceEpoch;
    final windowMs = math.max(0, ms(windowEnd) - ms(windowStart));

    var paused = math.max(0, countdown.accumulatedPauseMs);
    final pausedAt = countdown.pausedAt;
    if (pausedAt != null) {
      final pauseEnd = math.min(
        ms(countdown.stoppedAt ?? windowEnd),
        ms(windowEnd),
      );
      paused += math.max(0, pauseEnd - ms(pausedAt));
    }
    return math.min(paused, windowMs);
  }

  /// The session's set blocks and their spans, in the order the blocks began.
  ///
  /// [entries] are the session's entries as the wrist shows them, in the
  /// protocol's event shape. A set block is every `set` entry with the same
  /// `sessionExerciseId` and `exerciseId`; interleaved blocks (a superset) may
  /// overlap, and each is summarised over its own span. Efforts are ordered by
  /// `loggedAt`, then `entryId`. A rest, a rating, an entry whose `loggedAt`
  /// does not parse, or one with no slot or exercise id never makes a block.
  static List<WatchSetBlockSpan> blockSpans(
    Iterable<Map<String, Object?>> entries,
    DateTime sessionStartedAt,
  ) {
    final efforts = <_LoggedEffort>[];
    for (final entry in entries) {
      final effort = _LoggedEffort.tryParse(entry);
      if (effort != null) efforts.add(effort);
    }
    efforts.sort((a, b) {
      final byTime = a.loggedMs.compareTo(b.loggedMs);
      return byTime != 0 ? byTime : a.entryId.compareTo(b.entryId);
    });

    final order = <String>[];
    final sets = <String, List<_LoggedEffort>>{};
    for (final effort in efforts) {
      if (effort.kind != WatchObservationKind.set) continue;
      final key = effort.blockKey;
      if (key == null) continue;
      final block = sets[key];
      if (block == null) {
        order.add(key);
        sets[key] = [effort];
      } else {
        block.add(effort);
      }
    }

    final spans = <WatchSetBlockSpan>[];
    for (final key in order) {
      final block = sets[key]!;
      final firstSet = block.first;
      final lastSet = block.last;
      _LoggedEffort? leadIn;
      for (final effort in efforts) {
        if (effort.loggedMs < firstSet.loggedMs) leadIn = effort;
      }
      spans.add(
        WatchSetBlockSpan(
          sessionExerciseId: firstSet.sessionExerciseId!,
          exerciseId: firstSet.exerciseId!,
          startedAt: leadIn?.loggedAt ?? sessionStartedAt,
          endedAt: lastSet.loggedAt,
        ),
      );
    }
    return spans;
  }

  /// [instant] at the resolution the wire writes it: what a phone reading the
  /// event's timestamp gets back. Windows are normalised through here before
  /// anything is summarised over them.
  static DateTime wireInstant(DateTime instant) {
    try {
      return parseUtcIso(utcIso(instant));
    } on FormatException {
      return instant;
    }
  }

  static int _ms(WatchSensorSampleRecord sample) =>
      sample.recordedAt.toUtc().millisecondsSinceEpoch;

  static int _byTime(WatchSensorSampleRecord a, WatchSensorSampleRecord b) {
    final byTime = _ms(a).compareTo(_ms(b));
    return byTime != 0 ? byTime : a.sequence.compareTo(b.sequence);
  }
}

/// An effort entry, reduced to what a set block's span needs.
final class _LoggedEffort {
  const _LoggedEffort._({
    required this.entryId,
    required this.kind,
    required this.loggedAt,
    required this.sessionExerciseId,
    required this.exerciseId,
  });

  final String entryId;
  final String kind;
  final DateTime loggedAt;
  final String? sessionExerciseId;
  final String? exerciseId;

  int get loggedMs => loggedAt.toUtc().millisecondsSinceEpoch;

  /// The block this effort belongs to, or null when it names no slot and
  /// exercise.
  String? get blockKey => sessionExerciseId != null && exerciseId != null
      ? '$sessionExerciseId\u0000$exerciseId'
      : null;

  static _LoggedEffort? tryParse(Map<String, Object?> entry) {
    final kind = entry['kind'];
    if (kind is! String || !WatchObservationKind.efforts.contains(kind)) {
      return null;
    }
    final DateTime loggedAt;
    try {
      loggedAt = parseUtcIso(entry['loggedAt']);
    } on Object {
      return null;
    }
    final slot = entry['sessionExerciseId'];
    final exercise = entry['exerciseId'];
    return _LoggedEffort._(
      entryId: entry['entryId'] is String ? entry['entryId']! as String : '',
      kind: kind,
      loggedAt: loggedAt,
      sessionExerciseId: slot is String && exercise is String ? slot : null,
      exerciseId: slot is String && exercise is String ? exercise : null,
    );
  }
}
