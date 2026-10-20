import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/constants/workout_constants.dart';
import '../../core/utils/entry_rows.dart';
import '../../data/models/models.dart';
import '../../data/repositories/workout_repository.dart';

/// One in-progress work timer, in the shape the watch's `timer_state` frame
/// carries (43b3 D-1).
///
/// [wireKind] is `elapsed` (a `timed` effort), `hold` (a `drill` effort) or
/// `round`; [effortId] is the wire's `sessionExerciseId`.
class InProgressWorkTimer {
  final String effortId;
  final String wireKind;
  final int startedAtMs;
  final int? pausedAtMs;
  final int accumulatedPauseMs;
  final int? plannedDurationMs;

  const InProgressWorkTimer({
    required this.effortId,
    required this.wireKind,
    required this.startedAtMs,
    this.pausedAtMs,
    this.accumulatedPauseMs = 0,
    this.plannedDurationMs,
  });

  bool get paused => pausedAtMs != null;

  @override
  bool operator ==(Object other) =>
      other is InProgressWorkTimer &&
      other.effortId == effortId &&
      other.wireKind == wireKind &&
      other.startedAtMs == startedAtMs &&
      other.pausedAtMs == pausedAtMs &&
      other.accumulatedPauseMs == accumulatedPauseMs &&
      other.plannedDurationMs == plannedDurationMs;

  @override
  int get hashCode => Object.hash(
    effortId,
    wireKind,
    startedAtMs,
    pausedAtMs,
    accumulatedPauseMs,
    plannedDurationMs,
  );
}

/// A running work timer the watch sent, before it is written into an effort's
/// interval (43b2 D-2).
///
/// [wireKind] is `elapsed` (a `timed` effort), `hold` (a `drill` effort) or
/// `round`; [startedAtMs] is the watch's wall clock, so the phone counts from
/// the moment the work actually began.
class RemoteWorkTimer {
  final String wireKind;
  final int startedAtMs;
  final int? pausedAtMs;
  final int accumulatedPauseMs;
  final int? plannedDurationMs;

  const RemoteWorkTimer({
    required this.wireKind,
    required this.startedAtMs,
    this.pausedAtMs,
    this.accumulatedPauseMs = 0,
    this.plannedDurationMs,
  });

  bool get paused => pausedAtMs != null;

  @override
  bool operator ==(Object other) =>
      other is RemoteWorkTimer &&
      other.wireKind == wireKind &&
      other.startedAtMs == startedAtMs &&
      other.pausedAtMs == pausedAtMs &&
      other.accumulatedPauseMs == accumulatedPauseMs &&
      other.plannedDurationMs == plannedDurationMs;

  @override
  int get hashCode => Object.hash(
    wireKind,
    startedAtMs,
    pausedAtMs,
    accumulatedPauseMs,
    plannedDurationMs,
  );
}

class TimerManager {
  final WorkoutRepository _repository;
  final void Function() _notify;
  final void Function(String) _setErrorCallback;
  final void Function() _clearErrorCallback;
  Map<String, List<EffortObservation>>? _observations;

  /// The clock behind a new timed instance's id and stamps. A test that must
  /// repeat a millisecond — the collision D-338 guards against — passes one
  /// that stands still.
  final DateTime Function() _clock;

  final Map<String, List<RoundInstance>> _roundInstances = {};
  final Map<String, List<TimedInstance>> _timedInstances = {};
  final Map<String, List<EntryRest>> _entryRests = {};

  TimerManager(
    this._repository, {
    required void Function() notify,
    required void Function(String) setError,
    required void Function() clearError,
    DateTime Function()? clock,
  }) : _notify = notify,
       _setErrorCallback = setError,
       _clearErrorCallback = clearError,
       _clock = clock ?? DateTime.now;

  void bindObservations(Map<String, List<EffortObservation>> observations) {
    _observations = observations;
  }

  List<RoundInstance> getRoundsForEffort(String effortId) {
    return List.unmodifiable(_roundInstances[effortId] ?? []);
  }

  List<TimedInstance> getTimedInstancesForEffort(String effortId) {
    return List.unmodifiable(_timedInstances[effortId] ?? []);
  }

  List<EntryRest> getEntryRests(String effortId) {
    return List.unmodifiable(_entryRests[effortId] ?? []);
  }

  /// The in-progress work timers of [efforts], one per wire kind (43b3 D-1).
  ///
  /// A `timed` effort contributes its active or paused `TimedInstance`s as
  /// `elapsed`, a `drill` effort as `hold`, and a `round` effort its active or
  /// paused `RoundInstance`s as `round`. Not-started and finished instances,
  /// and a `set` effort, contribute nothing. When more than one instance is in
  /// progress for a kind the newest [InProgressWorkTimer.startedAtMs] is kept
  /// (ties: the later one in [efforts]); the result is ordered by wire kind.
  List<InProgressWorkTimer> inProgressWorkTimers(
    Iterable<SegmentEffort> efforts,
  ) {
    final byKind = <String, InProgressWorkTimer>{};

    for (final effort in efforts) {
      final wireKind = switch (effort.effortKind) {
        'timed' => 'elapsed',
        'drill' => 'hold',
        'round' => 'round',
        _ => null,
      };
      if (wireKind == null) continue;

      if (effort.effortKind == 'round') {
        for (final round in getRoundsForEffort(effort.id)) {
          if (round.state != RoundState.active &&
              round.state != RoundState.paused) {
            continue;
          }
          _keepNewestWorkTimer(
            byKind,
            InProgressWorkTimer(
              effortId: effort.id,
              wireKind: wireKind,
              startedAtMs: round.startedAtMs,
              pausedAtMs: round.state == RoundState.paused
                  ? round.pausedAtMs
                  : null,
              accumulatedPauseMs: round.totalPausedDurationMs,
              plannedDurationMs: round.plannedDurationSecs * 1000,
            ),
          );
        }
        continue;
      }

      for (final timed in getTimedInstancesForEffort(effort.id)) {
        if (timed.state != TimedState.active &&
            timed.state != TimedState.paused) {
          continue;
        }
        _keepNewestWorkTimer(
          byKind,
          InProgressWorkTimer(
            effortId: effort.id,
            wireKind: wireKind,
            startedAtMs: timed.startedAtMs,
            pausedAtMs: timed.state == TimedState.paused
                ? timed.pausedAtMs
                : null,
            accumulatedPauseMs: timed.totalPausedDurationMs,
          ),
        );
      }
    }

    final kinds = byKind.keys.toList()..sort();
    return [for (final kind in kinds) byKind[kind]!];
  }

  static void _keepNewestWorkTimer(
    Map<String, InProgressWorkTimer> byKind,
    InProgressWorkTimer candidate,
  ) {
    final held = byKind[candidate.wireKind];
    if (held == null || candidate.startedAtMs >= held.startedAtMs) {
      byKind[candidate.wireKind] = candidate;
    }
  }

  /// Adopts a running timer the watch sent into [effortId]'s target interval
  /// (43b2 D-1, D-2). Returns whether anything was written.
  ///
  /// [effortKind] is the effort's own kind; only `timed`↔`elapsed`,
  /// `drill`↔`hold` and `round`↔`round` pair, and any other pairing is
  /// ignored. The target is the effort's in-progress interval when it has one,
  /// else its first not-finished one; an effort with neither is ignored. A
  /// not-started target takes the remote's start and pause bookkeeping; an
  /// in-progress target is replaced only when the remote started earlier (the
  /// earlier start wins). The effort's open rests are closed in memory and
  /// persisted as [startTimedEntry] does. No notification is sent here: the
  /// session core bumps the refresh revision and notifies once.
  Future<bool> adoptRemoteTimer(
    String effortId,
    String effortKind,
    RemoteWorkTimer remote,
  ) async {
    _clearError();

    try {
      final wireKind = switch (effortKind) {
        'timed' => 'elapsed',
        'drill' => 'hold',
        'round' => 'round',
        _ => null,
      };
      if (wireKind == null || wireKind != remote.wireKind) return false;

      return effortKind == 'round'
          ? await _adoptRemoteRound(effortId, remote)
          : await _adoptRemoteTimed(effortId, remote);
    } catch (e) {
      _setError('Failed to adopt the remote timer: $e');
      return false;
    }
  }

  /// How far apart two starts may be and still be one interval's start: the
  /// watch's start crosses the wire as an ISO string.
  static const int _sameStartToleranceMs = 1000;

  /// Whether [remote] is an interval the effort does not hold yet: the effort
  /// has no unfinished interval to take it, and no finished one began with it.
  ///
  /// A watch that starts a second interval has no phone interval waiting for
  /// it, so the session core adds one first. A finished interval that started
  /// with the same instant means the phone already logged this timer, so it is
  /// not news again.
  bool needsIntervalFor(
    String effortId,
    String effortKind,
    RemoteWorkTimer remote,
  ) {
    final wireKind = switch (effortKind) {
      'timed' => 'elapsed',
      'drill' => 'hold',
      'round' => 'round',
      _ => null,
    };
    if (wireKind == null || wireKind != remote.wireKind) return false;

    final bool anyUnfinished;
    final Iterable<int> finishedStarts;
    if (effortKind == 'round') {
      final rounds = getRoundsForEffort(effortId);
      anyUnfinished = rounds.any((r) => r.state != RoundState.finished);
      finishedStarts = [
        for (final r in rounds)
          if (r.state == RoundState.finished) r.startedAtMs,
      ];
    } else {
      final timed = getTimedInstancesForEffort(effortId);
      anyUnfinished = timed.any((t) => t.state != TimedState.finished);
      finishedStarts = [
        for (final t in timed)
          if (t.state == TimedState.finished) t.startedAtMs,
      ];
    }
    if (anyUnfinished) return false;
    return !finishedStarts.any(
      (start) => (start - remote.startedAtMs).abs() <= _sameStartToleranceMs,
    );
  }

  Future<bool> _adoptRemoteTimed(
    String effortId,
    RemoteWorkTimer remote,
  ) async {
    final list = _timedInstances[effortId];
    if (list == null) return false;

    final index = _targetIndex(
      list,
      inProgress: (i) =>
          i.state == TimedState.active || i.state == TimedState.paused,
      finished: (i) => i.state == TimedState.finished,
    );
    if (index < 0) return false;

    final old = list[index];
    if (old.state != TimedState.notStarted &&
        remote.startedAtMs >= old.startedAtMs) {
      return false;
    }

    final closedRests = closeAllOpenRestsInMemory(effortId);
    final updated = old.copyWith(
      state: remote.pausedAtMs != null ? TimedState.paused : TimedState.active,
      startedAtMs: remote.startedAtMs,
      pausedAtMs: remote.pausedAtMs,
      totalPausedDurationMs: remote.accumulatedPauseMs,
      targetDurationSecs: 0,
      updatedAtMs: _clock().millisecondsSinceEpoch,
    );
    await _repository.updateTimedInstance(updated);
    list[index] = updated;
    _persistClosedRests(closedRests);
    return true;
  }

  Future<bool> _adoptRemoteRound(
    String effortId,
    RemoteWorkTimer remote,
  ) async {
    final list = _roundInstances[effortId];
    if (list == null) return false;

    final index = _targetIndex(
      list,
      inProgress: (i) =>
          i.state == RoundState.active || i.state == RoundState.paused,
      finished: (i) => i.state == RoundState.finished,
    );
    if (index < 0) return false;

    final old = list[index];
    if (old.state != RoundState.notStarted &&
        remote.startedAtMs >= old.startedAtMs) {
      return false;
    }

    final plannedMs = remote.plannedDurationMs;
    final closedRests = closeAllOpenRestsInMemory(effortId);
    final updated = old.copyWith(
      state: remote.pausedAtMs != null ? RoundState.paused : RoundState.active,
      startedAtMs: remote.startedAtMs,
      pausedAtMs: remote.pausedAtMs,
      totalPausedDurationMs: remote.accumulatedPauseMs,
      plannedDurationSecs: plannedMs != null && plannedMs > 0
          ? plannedMs ~/ 1000
          : null,
      updatedAtMs: _clock().millisecondsSinceEpoch,
    );
    await _repository.updateRoundInstance(updated);
    list[index] = updated;
    _persistClosedRests(closedRests);
    return true;
  }

  /// D-1: the in-progress instance when the effort has one, else the first
  /// that is not finished; -1 when there is none.
  static int _targetIndex<T>(
    List<T> list, {
    required bool Function(T) inProgress,
    required bool Function(T) finished,
  }) {
    for (var i = 0; i < list.length; i++) {
      if (inProgress(list[i])) return i;
    }
    for (var i = 0; i < list.length; i++) {
      if (!finished(list[i])) return i;
    }
    return -1;
  }

  void _persistClosedRests(Iterable<EntryRest> rests) {
    for (final rest in rests) {
      unawaited(
        _repository.updateEntryRest(rest).catchError((e) {
          _setError('Failed to persist closed rest: $e');
        }),
      );
    }
  }

  Map<String, List<RoundInstance>> get roundInstancesSnapshot =>
      Map.unmodifiable(_roundInstances);

  Map<String, List<EntryRest>> get entryRestsSnapshot =>
      Map.unmodifiable(_entryRests);

  Map<String, List<TimedInstance>> get timedInstancesSnapshot =>
      Map.unmodifiable(_timedInstances);

  void setRoundInstances(String effortId, List<RoundInstance> rounds) {
    _roundInstances[effortId] = rounds;
  }

  void setTimedInstances(String effortId, List<TimedInstance> timed) {
    _timedInstances[effortId] = timed;
  }

  void setEntryRests(String effortId, List<EntryRest> rests) {
    _entryRests[effortId] = rests;
  }

  void clearAll() {
    _roundInstances.clear();
    _timedInstances.clear();
    _entryRests.clear();
  }

  void removeEffort(String effortId) {
    _roundInstances.remove(effortId);
    _timedInstances.remove(effortId);
    _entryRests.remove(effortId);
  }

  bool _isValidRoundTransition(RoundState from, RoundState to) {
    switch (from) {
      case RoundState.notStarted:
        return to == RoundState.active;
      case RoundState.active:
        return to == RoundState.paused || to == RoundState.finished;
      case RoundState.paused:
        return to == RoundState.active || to == RoundState.finished;
      case RoundState.finished:
        return false;
    }
  }

  Future<void> addRound(
    String effortId, {
    int plannedDurationSecs = WorkoutConstants.defaultRoundDurationSecs,
  }) async {
    _clearError();
    try {
      final existing = _roundInstances[effortId] ?? [];
      final roundIndex = existing.length;
      final now = DateTime.now().millisecondsSinceEpoch;
      final instance = RoundInstance(
        id: 'round-$effortId-$roundIndex-$now',
        effortId: effortId,
        roundIndex: roundIndex,
        plannedDurationSecs: plannedDurationSecs,
        actualDurationSecs: 0,
        startedAtMs: 0,
        finishedAtMs: null,
        completed: false,
        state: RoundState.notStarted,
        pausedAtMs: null,
        totalPausedDurationMs: 0,
        createdAtMs: now,
        updatedAtMs: now,
      );
      await _repository.createRoundInstance(instance);
      _roundInstances.putIfAbsent(effortId, () => []).add(instance);
      _notify();
    } catch (e) {
      _setError('Failed to add round: $e');
    }
  }

  Future<void> startRound(String effortId, int roundIndex) async {
    _clearError();
    try {
      // Close all open rests for this effort in-memory BEFORE starting the round.
      // This ensures hasRestRecord() and getRestElapsedSeconds() return the closed
      // state immediately, even if the async repository persist is still in-flight.
      final closedRests = closeAllOpenRestsInMemory(effortId);

      final list = _roundInstances[effortId];
      if (list == null || roundIndex >= list.length) return;
      final old = list[roundIndex];

      if (!_isValidRoundTransition(old.state, RoundState.active)) {
        debugPrint('Invalid round transition: ${old.state} -> active');
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final updated = old.copyWith(
        state: RoundState.active,
        startedAtMs: now,
        updatedAtMs: now,
      );
      await _repository.updateRoundInstance(updated);
      list[roundIndex] = updated;

      // Persist the closed rests asynchronously in the background.
      // Catch errors so failures don't leave the database out of sync with memory.
      for (var rest in closedRests) {
        unawaited(
          _repository.updateEntryRest(rest).catchError((e) {
            _setError('Failed to persist closed rest: $e');
          }),
        );
      }

      _notify();
    } catch (e) {
      _setError('Failed to start round: $e');
    }
  }

  Future<void> pauseRound(String effortId, int roundIndex) async {
    _clearError();
    try {
      final list = _roundInstances[effortId];
      if (list == null || roundIndex >= list.length) return;
      final old = list[roundIndex];

      if (!_isValidRoundTransition(old.state, RoundState.paused)) {
        debugPrint('Invalid round transition: ${old.state} -> paused');
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final updated = old.copyWith(
        state: RoundState.paused,
        pausedAtMs: now,
        updatedAtMs: now,
      );
      await _repository.updateRoundInstance(updated);
      list[roundIndex] = updated;
      _notify();
    } catch (e) {
      _setError('Failed to pause round: $e');
    }
  }

  Future<void> resumeRound(String effortId, int roundIndex) async {
    _clearError();
    try {
      final list = _roundInstances[effortId];
      if (list == null || roundIndex >= list.length) return;
      final old = list[roundIndex];

      if (!_isValidRoundTransition(old.state, RoundState.active)) {
        debugPrint('Invalid round transition: ${old.state} -> active');
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final pauseDuration = old.pausedAtMs != null
          ? (now - old.pausedAtMs!)
          : 0;

      final updated = old.copyWith(
        state: RoundState.active,
        totalPausedDurationMs: old.totalPausedDurationMs + pauseDuration,
        pausedAtMs: null,
        updatedAtMs: now,
      );
      await _repository.updateRoundInstance(updated);
      list[roundIndex] = updated;
      _notify();
    } catch (e) {
      _setError('Failed to resume round: $e');
    }
  }

  Future<void> completeRound(String effortId, int roundIndex) async {
    _clearError();
    try {
      final list = _roundInstances[effortId];
      if (list == null || roundIndex >= list.length) return;
      final old = list[roundIndex];

      if (!_isValidRoundTransition(old.state, RoundState.finished)) {
        debugPrint(
          'Invalid round transition: ${old.state} -> finished (complete)',
        );
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final finishedAtMs =
          old.startedAtMs +
          (old.plannedDurationSecs * 1000) +
          old.totalPausedDurationMs;

      final updated = old.copyWith(
        state: RoundState.finished,
        actualDurationSecs: old.plannedDurationSecs,
        finishedAtMs: finishedAtMs,
        completed: true,
        pausedAtMs: null,
        updatedAtMs: now,
      );
      await _repository.updateRoundInstance(updated);
      list[roundIndex] = updated;
      _notify();
    } catch (e) {
      _setError('Failed to complete round: $e');
    }
  }

  Future<void> endRoundEarly(String effortId, int roundIndex) async {
    _clearError();
    try {
      final list = _roundInstances[effortId];
      if (list == null || roundIndex >= list.length) return;
      final old = list[roundIndex];

      if (!_isValidRoundTransition(old.state, RoundState.finished)) {
        debugPrint(
          'Invalid round transition: ${old.state} -> finished (early)',
        );
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final totalPausedMs =
          old.state == RoundState.paused && old.pausedAtMs != null
          ? old.totalPausedDurationMs + (now - old.pausedAtMs!)
          : old.totalPausedDurationMs;

      final elapsedMs = old.startedAtMs > 0
          ? (now - old.startedAtMs - totalPausedMs)
          : 0;
      final actualDurationSecs = (elapsedMs / 1000).round().clamp(
        0,
        old.plannedDurationSecs * WorkoutConstants.roundActualDurationCapFactor,
      );

      final updated = old.copyWith(
        state: RoundState.finished,
        actualDurationSecs: actualDurationSecs,
        finishedAtMs: now,
        completed: false,
        totalPausedDurationMs: totalPausedMs,
        pausedAtMs: null,
        updatedAtMs: now,
      );
      await _repository.updateRoundInstance(updated);
      list[roundIndex] = updated;
      _notify();
    } catch (e) {
      _setError('Failed to end round early: $e');
    }
  }

  /// Deletes the round at [roundIndex]. Returns `false` when the effort holds
  /// no such round — nothing was deleted.
  Future<bool> deleteRound(String effortId, int roundIndex) async {
    _clearError();
    try {
      final list = _roundInstances[effortId];
      if (list == null || roundIndex >= list.length) return false;
      await _repository.deleteRoundInstance(list[roundIndex].id);
      list.removeAt(roundIndex);
      final now = DateTime.now().millisecondsSinceEpoch;
      for (int i = roundIndex; i < list.length; i++) {
        final r = list[i];
        final reindexed = r.copyWith(roundIndex: i, updatedAtMs: now);
        list[i] = reindexed;
        await _repository.updateRoundInstance(reindexed);
      }
      _notify();
      return true;
    } catch (e) {
      _setError('Failed to delete round: $e');
      return false;
    }
  }

  Future<void> updateRoundPlannedDuration(
    String effortId,
    int roundIndex,
    int newDurationSecs,
  ) async {
    _clearError();
    try {
      final list = _roundInstances[effortId];
      if (list == null || roundIndex >= list.length) return;
      final old = list[roundIndex];

      if (old.state == RoundState.finished) {
        debugPrint('Cannot update planned duration for finished round');
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final updated = old.copyWith(
        plannedDurationSecs: newDurationSecs,
        updatedAtMs: now,
      );
      await _repository.updateRoundInstance(updated);
      list[roundIndex] = updated;
      _notify();
    } catch (e) {
      _setError('Failed to update round duration: $e');
    }
  }

  /// Applies [newDurationSecs] to the round at [fromIndex] and to every later
  /// round that has not started yet — a length change before Start moves the
  /// whole remaining set (O-6).
  ///
  /// The round at [fromIndex] is written unless it is already finished. Every
  /// LATER round is written only when it has not started; a later round that is
  /// running, paused or finished keeps its length. Each touched round is
  /// written to the cache before its `updateRoundInstance` (rows below read the
  /// same list). Returns the written indexes, ascending.
  Future<List<int>> updatePlannedDurationFrom(
    String effortId,
    int fromIndex,
    int newDurationSecs,
  ) async {
    _clearError();
    try {
      final list = _roundInstances[effortId];
      if (list == null || fromIndex < 0 || fromIndex >= list.length) {
        return <int>[];
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final touched = <int>[];
      for (int i = fromIndex; i < list.length; i++) {
        final old = list[i];
        if (i == fromIndex) {
          if (old.state == RoundState.finished) {
            debugPrint('Cannot update planned duration for finished round');
            continue;
          }
        } else if (old.state != RoundState.notStarted) {
          continue;
        }

        final updated = old.copyWith(
          plannedDurationSecs: newDurationSecs,
          updatedAtMs: now,
        );
        list[i] = updated;
        await _repository.updateRoundInstance(updated);
        touched.add(i);
      }

      _notify();
      return touched;
    } catch (e) {
      _setError('Failed to update round duration: $e');
      return <int>[];
    }
  }

  Future<void> persistActiveRounds() async {
    for (final entry in _roundInstances.entries) {
      final effortId = entry.key;
      final rounds = entry.value;
      for (int i = 0; i < rounds.length; i++) {
        final round = rounds[i];
        if (round.state == RoundState.active ||
            round.state == RoundState.paused) {
          await endRoundEarly(effortId, i);
        }
      }
    }
  }

  bool _isValidTimedTransition(TimedState from, TimedState to) {
    switch (from) {
      case TimedState.notStarted:
        return to == TimedState.active;
      case TimedState.active:
        return to == TimedState.paused || to == TimedState.finished;
      case TimedState.paused:
        return to == TimedState.active || to == TimedState.finished;
      case TimedState.finished:
        return false;
    }
  }

  /// A timed instance's id, unique among [existingIds] (D-338).
  ///
  /// The shape `timed-<effortId>-<entryIndex>-<ms>` is kept, so an add after
  /// a delete in the same millisecond does not name an instance that is
  /// already held: the ms part is raised until the id is free. Imported
  /// instances (`timed-<sessionId>-<entryId>`) are never passed here.
  static String uniqueTimedInstanceId({
    required Iterable<String> existingIds,
    required String effortId,
    required int entryIndex,
    required int nowMs,
  }) {
    final held = existingIds.toSet();
    var uniqueMs = nowMs;
    var id = 'timed-$effortId-$entryIndex-$uniqueMs';
    while (held.contains(id)) {
      uniqueMs++;
      id = 'timed-$effortId-$entryIndex-$uniqueMs';
    }
    return id;
  }

  Future<void> addTimedEntry(
    String effortId, {
    int targetDurationSecs = 0,
  }) async {
    _clearError();
    try {
      final existing = _timedInstances[effortId] ?? [];
      final entryIndex = existing.length;
      final now = _clock().millisecondsSinceEpoch;
      final instance = TimedInstance(
        id: uniqueTimedInstanceId(
          existingIds: [for (final held in existing) held.id],
          effortId: effortId,
          entryIndex: entryIndex,
          nowMs: now,
        ),
        effortId: effortId,
        entryIndex: entryIndex,
        targetDurationSecs: targetDurationSecs,
        actualDurationSecs: 0,
        startedAtMs: 0,
        finishedAtMs: null,
        state: TimedState.notStarted,
        pausedAtMs: null,
        totalPausedDurationMs: 0,
        createdAtMs: now,
        updatedAtMs: now,
      );
      await _repository.createTimedInstance(instance);
      _timedInstances.putIfAbsent(effortId, () => []).add(instance);
      _notify();
    } catch (e) {
      _setError('Failed to add timed entry: $e');
    }
  }

  Future<void> startTimedEntry(String effortId, int entryIndex) async {
    _clearError();
    try {
      // Close all open rests for this effort in-memory BEFORE starting the timer.
      // This ensures hasRestRecord() and getRestElapsedSeconds() return the closed
      // state immediately, even if the async repository persist is still in-flight.
      final closedRests = closeAllOpenRestsInMemory(effortId);

      final list = _timedInstances[effortId];
      if (list == null || entryIndex >= list.length) return;
      final old = list[entryIndex];

      if (!_isValidTimedTransition(old.state, TimedState.active)) {
        debugPrint('Invalid timed transition: ${old.state} -> active');
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final offsetMs = old.targetDurationSecs > 0
          ? old.targetDurationSecs * 1000
          : 0;
      final updated = old.copyWith(
        state: TimedState.active,
        startedAtMs: now - offsetMs,
        targetDurationSecs: 0,
        updatedAtMs: now,
      );
      await _repository.updateTimedInstance(updated);
      list[entryIndex] = updated;

      // Persist the closed rests asynchronously in the background.
      // Catch errors so failures don't leave the database out of sync with memory.
      for (var rest in closedRests) {
        unawaited(
          _repository.updateEntryRest(rest).catchError((e) {
            _setError('Failed to persist closed rest: $e');
          }),
        );
      }

      _notify();
    } catch (e) {
      _setError('Failed to start timed entry: $e');
    }
  }

  Future<void> pauseTimedEntry(String effortId, int entryIndex) async {
    _clearError();
    try {
      final list = _timedInstances[effortId];
      if (list == null || entryIndex >= list.length) return;
      final old = list[entryIndex];

      if (!_isValidTimedTransition(old.state, TimedState.paused)) {
        debugPrint('Invalid timed transition: ${old.state} -> paused');
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final updated = old.copyWith(
        state: TimedState.paused,
        pausedAtMs: now,
        updatedAtMs: now,
      );
      await _repository.updateTimedInstance(updated);
      list[entryIndex] = updated;
      _notify();
    } catch (e) {
      _setError('Failed to pause timed entry: $e');
    }
  }

  Future<void> resumeTimedEntry(String effortId, int entryIndex) async {
    _clearError();
    try {
      final list = _timedInstances[effortId];
      if (list == null || entryIndex >= list.length) return;
      final old = list[entryIndex];

      if (!_isValidTimedTransition(old.state, TimedState.active)) {
        debugPrint('Invalid timed transition: ${old.state} -> active');
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final pauseDuration = old.pausedAtMs != null
          ? (now - old.pausedAtMs!)
          : 0;

      final updated = old.copyWith(
        state: TimedState.active,
        totalPausedDurationMs: old.totalPausedDurationMs + pauseDuration,
        pausedAtMs: null,
        updatedAtMs: now,
      );
      await _repository.updateTimedInstance(updated);
      list[entryIndex] = updated;
      _notify();
    } catch (e) {
      _setError('Failed to resume timed entry: $e');
    }
  }

  Future<void> finishTimedEntry(String effortId, int entryIndex) async {
    _clearError();
    try {
      final list = _timedInstances[effortId];
      if (list == null || entryIndex >= list.length) return;
      final old = list[entryIndex];

      if (!_isValidTimedTransition(old.state, TimedState.finished)) {
        debugPrint('Invalid timed transition: ${old.state} -> finished');
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final totalPausedMs =
          old.state == TimedState.paused && old.pausedAtMs != null
          ? old.totalPausedDurationMs + (now - old.pausedAtMs!)
          : old.totalPausedDurationMs;

      final elapsedMs = old.startedAtMs > 0
          ? (now - old.startedAtMs - totalPausedMs)
          : 0;
      final actualDurationSecs = (elapsedMs / 1000).round().clamp(0, 86400);

      final updated = old.copyWith(
        state: TimedState.finished,
        actualDurationSecs: actualDurationSecs,
        finishedAtMs: now,
        totalPausedDurationMs: totalPausedMs,
        pausedAtMs: null,
        updatedAtMs: now,
      );
      await _repository.updateTimedInstance(updated);
      list[entryIndex] = updated;
      _notify();
    } catch (e) {
      _setError('Failed to finish timed entry: $e');
    }
  }

  /// Deletes the timed entry at [entryIndex] and its rows. Returns `false`
  /// when the effort holds no such entry — nothing was deleted.
  Future<bool> deleteTimedEntry(String effortId, int entryIndex) async {
    _clearError();
    try {
      final list = _timedInstances[effortId];
      if (list == null || entryIndex < 0 || entryIndex >= list.length) return false;
      // D-326: the entry's own rows are found before the instance goes, since
      // the rule pairs them against the positions the instances hold now.
      final doomed = _rowsOfTimedEntry(effortId, entryIndex, list.length);

      await _repository.deleteTimedInstance(list[entryIndex].id);
      list.removeAt(entryIndex);

      final now = DateTime.now().millisecondsSinceEpoch;
      for (int i = entryIndex; i < list.length; i++) {
        final t = list[i];
        final reindexed = t.copyWith(entryIndex: i, updatedAtMs: now);
        list[i] = reindexed;
        await _repository.updateTimedInstance(reindexed);
      }

      final observations = _observations?[effortId];
      if (observations != null) {
        for (final id in doomed) {
          await _repository.deleteObservation(id);
        }
        observations.removeWhere((row) => doomed.contains(row.id));
      }

      _notify();
      return true;
    } catch (e) {
      _setError('Failed to delete timed entry: $e');
      return false;
    }
  }

  /// Moves every rest of [effortId] down with the entries a delete kept (D-1).
  ///
  /// A `set` entry counts as logged exactly when a rest sits at its index + 1,
  /// so the rest at `deletedIndex + 1` — the mark of the entry that just went —
  /// is removed, every rest above it is re-keyed one down (same stamps, same
  /// open/paused state, id `rest-<effortId>-<newIndex>`) and every rest at
  /// [deletedIndex] or below stays. The in-memory cache is replaced first, then
  /// the store: Hive keys rests by id, so a re-key is a delete-and-re-create
  /// rather than an update.
  ///
  /// No-op when no rest sits at or above the deleted entry's mark. Never
  /// notifies — the caller's own delete already does.
  Future<void> rekeyEntryRestsAfterDelete(
    String effortId,
    int deletedIndex,
  ) async {
    _clearError();

    try {
      final list = _entryRests[effortId];
      if (list == null || list.isEmpty) return;
      final kept = EntryRows.restsAfterDelete(list, effortId, deletedIndex);
      if (kept == null) return;

      _entryRests[effortId] = kept;

      await _repository.deleteEntryRestsForEffort(effortId);
      for (final rest in kept) {
        await _repository.createEntryRest(rest);
      }
    } catch (e) {
      _setError('Failed to delete entry rests: $e');
    }
  }

  /// The ids of the rows entry [entryIndex] owns among [entryCount] instances
  /// (D-324): its own row of every companion metric the effort holds.
  Set<String> _rowsOfTimedEntry(
    String effortId,
    int entryIndex,
    int entryCount,
  ) {
    final rows = _observations?[effortId];
    if (rows == null) return const {};

    final doomed = <String>{};
    for (final metricId in {for (final row in rows) row.metricId}) {
      final paired = EntryRows.companions(
        rows: rows,
        metricId: metricId,
        entryCount: entryCount,
      );
      final row = entryIndex < paired.length ? paired[entryIndex] : null;
      if (row != null) doomed.add(row.id);
    }
    return doomed;
  }

  Future<void> updateTimedTargetDuration(
    String effortId,
    int entryIndex,
    int newTargetSecs,
  ) async {
    _clearError();
    try {
      final list = _timedInstances[effortId];
      if (list == null || entryIndex >= list.length) return;
      final old = list[entryIndex];

      if (old.state == TimedState.finished) {
        debugPrint('Cannot update target duration for finished timed entry');
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final updated = old.copyWith(
        targetDurationSecs: newTargetSecs,
        updatedAtMs: now,
      );
      await _repository.updateTimedInstance(updated);
      list[entryIndex] = updated;
      _notify();
    } catch (e) {
      _setError('Failed to update timed target duration: $e');
    }
  }

  Future<void> persistActiveTimedEntries() async {
    for (final entry in _timedInstances.entries) {
      final effortId = entry.key;
      final entries = entry.value;
      for (int i = 0; i < entries.length; i++) {
        final timedEntry = entries[i];
        if (timedEntry.state == TimedState.active ||
            timedEntry.state == TimedState.paused) {
          await finishTimedEntry(effortId, i);
        }
      }
    }
  }

  /// Returns the wall-clock [nowMs]-based effective end of an open
  /// [EntryRest]. When the rest is paused, the effective end is the
  /// pause time (frozen display) — never `nowMs` — so the recorded
  /// duration never includes time the user spent paused. When running,
  /// the effective end is simply `nowMs`.
  int _effectiveRestEndMs(EntryRest rest, int nowMs) =>
      rest.restIsPaused ? (rest.restPausedAtMs ?? nowMs) : nowMs;

  Future<void> recordRestStart(String effortId, int entryIndex) async {
    _clearError();

    try {
      final list = _entryRests.putIfAbsent(effortId, () => []);
      if (list.any((r) => r.entryIndex == entryIndex)) {
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;

      for (var i = 0; i < list.length; i++) {
        final rest = list[i];
        if (rest.restEndMs != null) continue;
        final effectiveEnd = _effectiveRestEndMs(rest, now);
        final closed = rest.copyWith(
          restEndMs: effectiveEnd,
          restIsPaused: false,
          restPausedAtMs: null,
          updatedAtMs: now,
        );
        await _repository.updateEntryRest(closed);
        list[i] = closed;
      }

      final rest = EntryRest(
        id: 'rest-$effortId-$entryIndex',
        effortId: effortId,
        entryIndex: entryIndex,
        restStartMs: now,
        restEndMs: null,
        createdAtMs: now,
        updatedAtMs: now,
      );

      await _repository.createEntryRest(rest);
      list.add(rest);
      _notify();
    } catch (e) {
      _setError('Failed to record rest start: $e');
    }
  }

  Future<void> recordRestEnd(String effortId, int entryIndex) async {
    _clearError();

    try {
      final list = _entryRests[effortId];
      if (list == null) return;

      final idx = list.indexWhere((r) => r.entryIndex == entryIndex);
      if (idx == -1) return;

      final now = DateTime.now().millisecondsSinceEpoch;
      final rest = list[idx];
      final effectiveEnd = _effectiveRestEndMs(rest, now);
      final updated = rest.copyWith(
        restEndMs: effectiveEnd,
        restIsPaused: false,
        restPausedAtMs: null,
        updatedAtMs: now,
      );

      await _repository.updateEntryRest(updated);
      list[idx] = updated;
      _notify();
    } catch (e) {
      _setError('Failed to record rest end: $e');
    }
  }

  /// Pauses an open rest record. The wall-clock pause time is captured
  /// as [EntryRest.restPausedAtMs] so the elapsed display freezes at
  /// the pause instant. Persisted to the repository so a reload
  /// during the paused window restores the same state.
  ///
  /// No-op when:
  /// - the rest is already closed ([EntryRest.restEndMs] != null), or
  /// - the rest is already paused ([EntryRest.restIsPaused] is true).
  Future<void> pauseRest(String effortId, int entryIndex) async {
    _clearError();
    try {
      final list = _entryRests[effortId];
      if (list == null) return;
      final idx = list.indexWhere((r) => r.entryIndex == entryIndex);
      if (idx == -1) return;
      final rest = list[idx];
      if (rest.restEndMs != null) return; // already closed
      if (rest.restIsPaused) return; // already paused
      final now = DateTime.now().millisecondsSinceEpoch;
      final updated = rest.copyWith(
        restIsPaused: true,
        restPausedAtMs: now,
        updatedAtMs: now,
      );
      await _repository.updateEntryRest(updated);
      list[idx] = updated;
      _notify();
    } catch (e) {
      _setError('Failed to pause rest: $e');
    }
  }

  /// Resumes a paused rest record. The duration spent paused
  /// (`now - restPausedAtMs`) is added to
  /// [EntryRest.restPausedDurationMs] so the recorded rest duration
  /// excludes the stopped interval. Persisted to the repository so
  /// the accumulated pause time survives a reload.
  ///
  /// No-op when:
  /// - the rest is already closed, or
  /// - the rest is already running (not paused).
  Future<void> resumeRest(String effortId, int entryIndex) async {
    _clearError();
    try {
      final list = _entryRests[effortId];
      if (list == null) return;
      final idx = list.indexWhere((r) => r.entryIndex == entryIndex);
      if (idx == -1) return;
      final rest = list[idx];
      if (rest.restEndMs != null) return; // already closed
      if (!rest.restIsPaused) return; // already running
      final now = DateTime.now().millisecondsSinceEpoch;
      final pauseStart = rest.restPausedAtMs ?? now;
      final additionalPauseMs = now - pauseStart;
      final updated = rest.copyWith(
        restIsPaused: false,
        restPausedAtMs: null,
        restPausedDurationMs: rest.restPausedDurationMs + additionalPauseMs,
        updatedAtMs: now,
      );
      await _repository.updateEntryRest(updated);
      list[idx] = updated;
      _notify();
    } catch (e) {
      _setError('Failed to resume rest: $e');
    }
  }

  int getRestElapsedSeconds(String effortId, int entryIndex) {
    final list = _entryRests[effortId];
    if (list == null) return 0;

    try {
      final rest = list.firstWhere((r) => r.entryIndex == entryIndex);
      // Only return elapsed time for OPEN rests (restEndMs == null).
      // Closed rests return 0 since they are no longer accumulating.
      if (rest.restEndMs != null) return 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      return rest.elapsedSeconds(now);
    } catch (_) {
      return 0;
    }
  }

  /// Whether the rest record for the given effort/entry is currently
  /// in the **paused** state (i.e. tap is needed to resume the counted
  /// time). Returns `false` for closed, running, or missing rests.
  bool isRestPaused(String effortId, int entryIndex) {
    final list = _entryRests[effortId];
    if (list == null) return false;
    for (final r in list) {
      if (r.entryIndex == entryIndex) {
        return r.restIsPaused;
      }
    }
    return false;
  }

  bool hasRestRecord(String effortId, int entryIndex) {
    final list = _entryRests[effortId];
    if (list == null) return false;
    return list.any((r) => r.entryIndex == entryIndex && r.restEndMs == null);
  }

  /// Closes every open [EntryRest] across **all** efforts at [closeAtMs].
  /// Called from [endSession] so the last rest window is captured
  /// rather than discarded. When a rest is paused, the effective end
  /// is the pause time (not [closeAtMs]) so the recorded rest
  /// duration excludes the stopped interval.
  Future<void> persistOpenRests(int closeAtMs) async {
    for (final effortId in List<String>.from(_entryRests.keys)) {
      final list = _entryRests[effortId];
      if (list == null) continue;
      for (var i = 0; i < list.length; i++) {
        final rest = list[i];
        if (rest.restEndMs != null) continue;
        // Paused rests: preserve the pause time as the end so the
        // recorded duration doesn't include paused time. The session
        // end timestamp is the wall-clock "now" but the rest's effective
        // end is the last active-counted moment.
        final effectiveEnd = _effectiveRestEndMs(rest, closeAtMs);
        final closed = rest.copyWith(
          restEndMs: effectiveEnd,
          restIsPaused: false,
          restPausedAtMs: null,
          updatedAtMs: closeAtMs,
        );
        try {
          await _repository.updateEntryRest(closed);
        } catch (_) {
          // best-effort; do not block session end
        }
        list[i] = closed;
      }
    }
  }

  /// Synchronously closes all open [EntryRest] records for [effortId] in the
  /// in-memory cache. Paused rests are closed at their pause time so the
  /// recorded duration excludes the stopped interval.
  ///
  /// This method updates the [_entryRests] cache immediately without calling
  /// Closes all open [EntryRest] records for [effortId] in the in-memory cache.
  /// Returns the list of rests that were actually closed (those with `restEndMs == null`).
  ///
  /// Does NOT call [_notify] or persist to the repository. Use [closeAllOpenRests] to
  /// also persist the changes asynchronously.
  ///
  /// Call this method BEFORE starting an effort timer to ensure the rest
  /// visibility and elapsed-time queries return the closed state immediately,
  /// even if the async repository persist is still in-flight.
  List<EntryRest> closeAllOpenRestsInMemory(String effortId) {
    final closedRests = <EntryRest>[];
    final list = _entryRests[effortId];
    if (list == null) return closedRests;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < list.length; i++) {
      final rest = list[i];
      if (rest.restEndMs != null) continue;
      final effectiveEnd = _effectiveRestEndMs(rest, now);
      final closed = rest.copyWith(
        restEndMs: effectiveEnd,
        restIsPaused: false,
        restPausedAtMs: null,
        updatedAtMs: now,
      );
      list[i] = closed;
      closedRests.add(closed);
    }
    return closedRests;
  }

  /// Closes every open [EntryRest] record for [effortId], regardless of
  /// entryIndex. Called when an interval timer starts so that a rest window
  /// opened for a previously-skipped interval does not keep ticking.
  /// Paused rests are closed at their pause time so the recorded
  /// duration excludes the stopped interval.
  ///
  /// The in-memory close happens synchronously via [closeAllOpenRestsInMemory].
  /// The repository persist happens asynchronously. If you need the in-memory
  /// close to happen before UI rendering, call [closeAllOpenRestsInMemory]
  /// first, then call this method for the async persist.
  ///
  /// Only persists the rests that were actually closed (not already-closed rests),
  /// preventing write-amplification on repeated timer starts.
  Future<void> closeAllOpenRests(String effortId) async {
    _clearError();
    try {
      // Close in-memory and get the rests that were actually closed
      final closedRests = closeAllOpenRestsInMemory(effortId);

      // Then persist asynchronously — only those that were just closed
      for (var rest in closedRests) {
        await _repository.updateEntryRest(rest);
      }
      _notify();
    } catch (e) {
      _setError('Failed to close all open rests: $e');
    }
  }

  // ── Retrospective edit methods (edit mode only) ────────────────────────

  /// Sets a [TimedInstance] to `finished` with a caller-specified duration,
  /// bypassing the normal state-machine transition guards.
  ///
  /// Intended exclusively for retrospective (edit-mode) corrections where the
  /// user is changing a logged duration after the session has ended.  Do NOT
  /// use in the live-workout timer flow — that path calls [finishTimedEntry].
  Future<void> setTimedInstanceFinished(
    String effortId,
    int entryIndex,
    int durationSecs,
  ) async {
    _clearError();
    try {
      final list = _timedInstances[effortId];
      if (list == null || entryIndex >= list.length) return;
      final old = list[entryIndex];
      final now = DateTime.now().millisecondsSinceEpoch;
      // Synthesise timestamps so elapsedMs == durationSecs * 1000.
      final startedAtMs = old.startedAtMs > 0
          ? old.startedAtMs
          : now - (durationSecs * 1000);
      final finishedAtMs = startedAtMs + (durationSecs * 1000);
      final updated = old.copyWith(
        state: TimedState.finished,
        actualDurationSecs: durationSecs,
        startedAtMs: startedAtMs,
        finishedAtMs: finishedAtMs,
        totalPausedDurationMs: 0,
        pausedAtMs: null,
        updatedAtMs: now,
      );
      await _repository.updateTimedInstance(updated);
      list[entryIndex] = updated;
      _notify();
    } catch (e) {
      _setError('Failed to set timed entry duration: $e');
    }
  }

  /// Sets a [RoundInstance] to `finished` with a caller-specified duration,
  /// bypassing the normal state-machine transition guards.
  ///
  /// Intended exclusively for retrospective (edit-mode) corrections.
  Future<void> setRoundFinished(
    String effortId,
    int roundIndex,
    int durationSecs,
  ) async {
    _clearError();
    try {
      final list = _roundInstances[effortId];
      if (list == null || roundIndex >= list.length) return;
      final old = list[roundIndex];
      final now = DateTime.now().millisecondsSinceEpoch;
      final startedAtMs = old.startedAtMs > 0
          ? old.startedAtMs
          : now - (durationSecs * 1000);
      final finishedAtMs = startedAtMs + (durationSecs * 1000);
      final plannedDurationSecs = old.plannedDurationSecs > 0
          ? old.plannedDurationSecs
          : durationSecs;
      final updated = old.copyWith(
        state: RoundState.finished,
        actualDurationSecs: durationSecs,
        plannedDurationSecs: plannedDurationSecs,
        startedAtMs: startedAtMs,
        finishedAtMs: finishedAtMs,
        completed: true,
        totalPausedDurationMs: 0,
        pausedAtMs: null,
        updatedAtMs: now,
      );
      await _repository.updateRoundInstance(updated);
      list[roundIndex] = updated;
      _notify();
    } catch (e) {
      _setError('Failed to set round duration: $e');
    }
  }

  /// Normalises every non-finished round in the session to `finished`, using
  /// its [plannedDurationSecs] as the actual duration.
  ///
  /// Called at the end of [_saveEditChanges] so that a historical session never
  /// contains rounds in notStarted / active / paused states after the user saves.
  Future<void> normalizeAllRoundsToFinished() async {
    for (final entry in _roundInstances.entries) {
      final effortId = entry.key;
      final rounds = entry.value;
      for (int i = 0; i < rounds.length; i++) {
        final round = rounds[i];
        if (round.state != RoundState.finished) {
          final durationSecs = round.plannedDurationSecs > 0
              ? round.plannedDurationSecs
              : 0;
          await setRoundFinished(effortId, i, durationSecs);
        }
      }
    }
  }

  void _setError(String message) => _setErrorCallback(message);

  void _clearError() => _clearErrorCallback();
}
