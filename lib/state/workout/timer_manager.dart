import 'package:flutter/foundation.dart';

import '../../core/constants/workout_constants.dart';
import '../../data/models/models.dart';
import '../../data/repositories/workout_repository.dart';

class TimerManager {
  final WorkoutRepository _repository;
  final void Function() _notify;
  final void Function(String) _setErrorCallback;
  final void Function() _clearErrorCallback;
  Map<String, List<EffortObservation>>? _observations;

  final Map<String, List<RoundInstance>> _roundInstances = {};
  final Map<String, List<TimedInstance>> _timedInstances = {};
  final Map<String, List<EntryRest>> _entryRests = {};

  TimerManager(
    this._repository, {
    required void Function() notify,
    required void Function(String) setError,
    required void Function() clearError,
  }) : _notify = notify,
       _setErrorCallback = setError,
       _clearErrorCallback = clearError;

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

  Map<String, List<RoundInstance>> get roundInstancesSnapshot =>
      Map.unmodifiable(_roundInstances);

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

  Future<void> deleteRound(String effortId, int roundIndex) async {
    _clearError();
    try {
      final list = _roundInstances[effortId];
      if (list == null || roundIndex >= list.length) return;
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
    } catch (e) {
      _setError('Failed to delete round: $e');
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

  Future<void> addTimedEntry(
    String effortId, {
    int targetDurationSecs = 0,
  }) async {
    _clearError();
    try {
      final existing = _timedInstances[effortId] ?? [];
      final entryIndex = existing.length;
      final now = DateTime.now().millisecondsSinceEpoch;
      final instance = TimedInstance(
        id: 'timed-$effortId-$entryIndex-$now',
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

  Future<void> deleteTimedEntry(String effortId, int entryIndex) async {
    _clearError();
    try {
      final list = _timedInstances[effortId];
      if (list == null || entryIndex >= list.length) return;
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
        final idPrefix = 'obs-$effortId-$entryIndex-';
        final toDelete = observations
            .where((o) => o.id.startsWith(idPrefix))
            .toList();
        for (final obs in toDelete) {
          await _repository.deleteObservation(obs.id);
        }
        observations.removeWhere((o) => o.id.startsWith(idPrefix));
      }

      _notify();
    } catch (e) {
      _setError('Failed to delete timed entry: $e');
    }
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
    return list.any((r) => r.entryIndex == entryIndex);
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

  /// Closes every open [EntryRest] record for [effortId], regardless of
  /// entryIndex. Called when an interval timer starts so that a rest window
  /// opened for a previously-skipped interval does not keep ticking.
  /// Paused rests are closed at their pause time so the recorded
  /// duration excludes the stopped interval.
  Future<void> closeAllOpenRests(String effortId) async {
    _clearError();
    try {
      final list = _entryRests[effortId];
      if (list == null) return;
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
