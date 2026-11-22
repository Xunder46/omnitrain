/// The Wear wrist's end-of-workout summary: what a finished workout shows (time,
/// efforts, average heart rate) and the state that owes it to a workout this
/// process saw end.
///
/// Plan: `docs/plans/2026-11-22-292-wear-workout-summary-plan/2026-11-22-292-wear-workout-summary-plan.md`
/// (D-29201, D-29202). The Dart twin of the Apple client's
/// `WatchWorkoutSummary.swift` (plan 66a). Everything here is state and
/// arithmetic; the screen only binds to it.
library;

import 'dart:math' as math;

import '../session/watch_records.dart';
import '../session/watch_session_engine.dart';

/// The words on the summary (plan 66a D-1). Wrist-only copy, not part of the
/// shared contract.
abstract final class WatchWorkoutSummaryCopy {
  static const String title = 'Workout done';
  static const String time = 'Time';
  static const String sets = 'Sets';
  static const String efforts = 'Efforts';
  static const String avgHeartRate = 'Avg HR';
  static const String done = 'Done';
  static const String bpm = 'bpm';
}

class WatchSummaryRow {
  const WatchSummaryRow({required this.label, required this.value});

  final String label;
  final String value;
}

/// What a finished workout shows on the wrist: how long, how many efforts, and
/// the average heart rate when the watch recorded one.
class WatchWorkoutSummary {
  const WatchWorkoutSummary({
    required this.sessionId,
    required this.startedAt,
    required this.endedAt,
    required this.effortCount,
    required this.allSets,
    required this.averageBpm,
  });

  final String sessionId;
  final DateTime startedAt;
  final DateTime endedAt;
  final int effortCount;

  /// Whether every effort was a set: the count is then labelled `Sets`, else
  /// `Efforts`.
  final bool allSets;

  /// The average heart rate in whole beats per minute, or null with no readings.
  final int? averageBpm;

  List<WatchSummaryRow> get rows => [
    WatchSummaryRow(
      label: WatchWorkoutSummaryCopy.time,
      value: durationText(
        (endedAt.difference(startedAt).inMilliseconds / 1000).round(),
      ),
    ),
    WatchSummaryRow(
      label: allSets
          ? WatchWorkoutSummaryCopy.sets
          : WatchWorkoutSummaryCopy.efforts,
      value: '$effortCount',
    ),
    if (averageBpm != null)
      WatchSummaryRow(
        label: WatchWorkoutSummaryCopy.avgHeartRate,
        value: '$averageBpm ${WatchWorkoutSummaryCopy.bpm}',
      ),
  ];

  /// `m:ss` under an hour, `h:mm:ss` from an hour; a negative length reads 0:00.
  static String durationText(int seconds) {
    final total = math.max(0, seconds);
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final secs = total % 60;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = secs.toString().padLeft(2, '0');
    if (hours > 0) return '$hours:$mm:$ss';
    return '$minutes:$ss';
  }
}

/// The summary the wrist owes a workout it saw end. The shell calls [note] with
/// the engine's session on every build; a workout makes one summary, and only
/// when this process saw it active (a relaunch after the end shows nothing).
class WatchWorkoutSummaryState {
  WatchWorkoutSummaryState({required WatchSessionEngine engine})
    : _engine = engine;

  final WatchSessionEngine _engine;
  String? _activeSeenId;
  WatchWorkoutSummary? _pending;

  /// The summary waiting to be shown, or null.
  WatchWorkoutSummary? get pending => _pending;

  void note(WatchSessionRecord? session) {
    if (session == null) return;
    if (session.status == WatchSessionStatus.active) {
      _activeSeenId = session.sessionId;
      final held = _pending;
      if (held != null && held.sessionId != session.sessionId) _pending = null;
      return;
    }
    if (session.status != WatchSessionStatus.completed ||
        session.sessionId != _activeSeenId ||
        _engine.session?.sessionId != session.sessionId ||
        _pending?.sessionId == session.sessionId) {
      return;
    }
    _activeSeenId = null;
    // An end the phone made closes the workout without a summary; only an end
    // the wrist made owes one.
    if (_engine.endedByPhone(session)) return;

    final efforts = [
      for (final entry in _engine.entries)
        if (WatchObservationKind.efforts.contains(entry.kind)) entry,
    ];
    if (efforts.isEmpty) return;

    final beats = [
      for (final sample in _engine.sensorSamples)
        if (sample.kind == WatchSensorKind.heartRate &&
            !sample.recordedAt.isBefore(session.startedAt) &&
            !sample.recordedAt.isAfter(session.recordedAt))
          sample.value,
    ];
    final average = beats.isEmpty
        ? null
        : (beats.reduce((a, b) => a + b) / beats.length).round();

    _pending = WatchWorkoutSummary(
      sessionId: session.sessionId,
      startedAt: session.startedAt,
      endedAt: session.recordedAt,
      effortCount: efforts.length,
      allSets: efforts.every((entry) => entry.kind == WatchObservationKind.set),
      averageBpm: average,
    );
  }

  void dismissPending() {
    _pending = null;
  }
}
