part of 'session_core.dart';

extension SessionCoreLifecycleMethods on SessionCore {
  Future<void> endSession() async {
    if (_currentSession == null) return;
    if (_currentSession!.endedAtMs != null) return;

    _clearError();

    try {
      await _timerManager.persistActiveRounds();
      await _timerManager.persistActiveTimedEntries();

      final now = DateTime.now().millisecondsSinceEpoch;
      final updatedSession = TrainingSession(
        id: _currentSession!.id,
        ownerUserId: _currentSession!.ownerUserId,
        routineTemplateId: _currentSession!.routineTemplateId,
        startedAtMs: _currentSession!.startedAtMs,
        endedAtMs: now,
        title: _currentSession!.title,
        note: _currentSession!.note,
        locationText: _currentSession!.locationText,
        modality: _currentSession!.modality,
        intent: _currentSession!.intent,
        perceivedSessionRpe: _currentSession!.perceivedSessionRpe,
        sessionFeeling: _currentSession!.sessionFeeling,
        qualityRating: _currentSession!.qualityRating,
        isRolling: _currentSession!.isRolling,
        createdAtMs: _currentSession!.createdAtMs,
        updatedAtMs: now,
      );

      await _repository.updateSession(updatedSession);
      _currentSession = updatedSession;

      _notify();
    } catch (e) {
      _setError('Failed to end session: $e');
    }
  }

  Future<void> discardCurrentSession() async {
    if (_currentSession == null) return;

    _clearError();

    try {
      await _repository.deleteSession(_currentSession!.id);
      clearSession();
    } catch (e) {
      _setError('Failed to discard session: $e');
    }
  }

  Future<void> updateSessionNote(String note) async {
    if (_currentSession == null) return;

    _clearError();

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final updatedSession = TrainingSession(
        id: _currentSession!.id,
        ownerUserId: _currentSession!.ownerUserId,
        routineTemplateId: _currentSession!.routineTemplateId,
        startedAtMs: _currentSession!.startedAtMs,
        endedAtMs: _currentSession!.endedAtMs,
        title: _currentSession!.title,
        note: note,
        locationText: _currentSession!.locationText,
        modality: _currentSession!.modality,
        intent: _currentSession!.intent,
        perceivedSessionRpe: _currentSession!.perceivedSessionRpe,
        sessionFeeling: _currentSession!.sessionFeeling,
        qualityRating: _currentSession!.qualityRating,
        isRolling: _currentSession!.isRolling,
        createdAtMs: _currentSession!.createdAtMs,
        updatedAtMs: now,
      );

      await _repository.updateSession(updatedSession);
      _currentSession = updatedSession;
      _notify();
    } catch (e) {
      _setError('Failed to update session note: $e');
    }
  }

  Future<void> updateSessionEndTime(int durationSecs) async {
    if (_currentSession == null) return;
    if (durationSecs <= 0) return;
    _clearError();
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final newEndedAtMs = _currentSession!.startedAtMs + (durationSecs * 1000);
      final updatedSession = TrainingSession(
        id: _currentSession!.id,
        ownerUserId: _currentSession!.ownerUserId,
        routineTemplateId: _currentSession!.routineTemplateId,
        startedAtMs: _currentSession!.startedAtMs,
        endedAtMs: newEndedAtMs,
        title: _currentSession!.title,
        note: _currentSession!.note,
        locationText: _currentSession!.locationText,
        modality: _currentSession!.modality,
        intent: _currentSession!.intent,
        perceivedSessionRpe: _currentSession!.perceivedSessionRpe,
        sessionFeeling: _currentSession!.sessionFeeling,
        qualityRating: _currentSession!.qualityRating,
        isRolling: _currentSession!.isRolling,
        createdAtMs: _currentSession!.createdAtMs,
        updatedAtMs: now,
      );
      await _repository.updateSession(updatedSession);
      _currentSession = updatedSession;
      _notify();
    } catch (e) {
      _setError('Failed to update session end time: $e');
    }
  }

  Future<void> updateSessionFeeling(String sessionId, int feeling) async {
    if (feeling < 1 || feeling > 5) return;

    _clearError();

    try {
      await _repository.updateSessionFeeling(sessionId, feeling);

      if (_currentSession?.id == sessionId) {
        final now = DateTime.now().millisecondsSinceEpoch;
        _currentSession = TrainingSession(
          id: _currentSession!.id,
          ownerUserId: _currentSession!.ownerUserId,
          routineTemplateId: _currentSession!.routineTemplateId,
          startedAtMs: _currentSession!.startedAtMs,
          endedAtMs: _currentSession!.endedAtMs,
          title: _currentSession!.title,
          note: _currentSession!.note,
          locationText: _currentSession!.locationText,
          modality: _currentSession!.modality,
          intent: _currentSession!.intent,
          perceivedSessionRpe: _currentSession!.perceivedSessionRpe,
          sessionFeeling: feeling,
          qualityRating: _currentSession!.qualityRating,
          isRolling: _currentSession!.isRolling,
          createdAtMs: _currentSession!.createdAtMs,
          updatedAtMs: now,
        );
      }

      _notify();
    } catch (e) {
      _setError('Failed to update session feeling: $e');
    }
  }

  Future<void> updateSessionRpe(String sessionId, double rpe) async {
    if (rpe < 1.0 || rpe > 10.0) return;

    _clearError();

    try {
      if (_currentSession?.id == sessionId) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final updatedSession = TrainingSession(
          id: _currentSession!.id,
          ownerUserId: _currentSession!.ownerUserId,
          routineTemplateId: _currentSession!.routineTemplateId,
          startedAtMs: _currentSession!.startedAtMs,
          endedAtMs: _currentSession!.endedAtMs,
          title: _currentSession!.title,
          note: _currentSession!.note,
          locationText: _currentSession!.locationText,
          modality: _currentSession!.modality,
          intent: _currentSession!.intent,
          perceivedSessionRpe: rpe,
          sessionFeeling: _currentSession!.sessionFeeling,
          qualityRating: _currentSession!.qualityRating,
          isRolling: _currentSession!.isRolling,
          createdAtMs: _currentSession!.createdAtMs,
          updatedAtMs: now,
        );

        await _repository.updateSession(updatedSession);
        _currentSession = updatedSession;
      }

      _notify();
    } catch (e) {
      _setError('Failed to update session RPE: $e');
    }
  }

  SessionEditSnapshot? snapshotSessionState() {
    if (_currentSession == null) return null;

    return SessionEditSnapshot(
      sessionId: _currentSession!.id,
      segments: List<SessionSegment>.from(_segments),
      efforts: {
        for (final entry in _efforts.entries) entry.key: List<SegmentEffort>.from(entry.value),
      },
      observations: {
        for (final entry in _observations.entries)
          entry.key: List<EffortObservation>.from(entry.value),
      },
      roundInstances: {
        for (final entry in _timerManager.roundInstancesSnapshot.entries)
          entry.key: List<RoundInstance>.from(entry.value),
      },
      timedInstances: {
        for (final entry in _timerManager.timedInstancesSnapshot.entries)
          entry.key: List<TimedInstance>.from(entry.value),
      },
      exerciseCache: Map<String, Exercise>.from(_exerciseCache),
    );
  }

  Future<void> restoreSessionSnapshot(SessionEditSnapshot snapshot) async {
    _clearError();

    try {
      final currentEffortIds = <String>{
        for (final effortList in _efforts.values)
          for (final effort in effortList) effort.id,
      };
      final snapshotEffortIds = <String>{
        for (final effortList in snapshot.efforts.values)
          for (final effort in effortList) effort.id,
      };

      for (final effortId in currentEffortIds) {
        if (!snapshotEffortIds.contains(effortId)) {
          await _repository.deleteEffort(effortId);
        }
      }

      for (final segmentId in snapshot.efforts.keys) {
        for (final effort in snapshot.efforts[segmentId]!) {
          if (!currentEffortIds.contains(effort.id)) {
            await _repository.createEffort(effort);
            for (final obs in snapshot.observations[effort.id] ?? []) {
              await _repository.createObservation(obs);
            }
            for (final ri in snapshot.roundInstances[effort.id] ?? []) {
              await _repository.createRoundInstance(ri);
            }
            for (final ti in snapshot.timedInstances[effort.id] ?? []) {
              await _repository.createTimedInstance(ti);
            }
          }
        }
      }

      for (final effortId in currentEffortIds) {
        if (!snapshotEffortIds.contains(effortId)) {
          continue;
        }

        await _repository.deleteObservationsForEffort(effortId);
        for (final obs in snapshot.observations[effortId] ?? []) {
          await _repository.createObservation(obs);
        }

        if (snapshot.roundInstances.containsKey(effortId)) {
          await _repository.deleteRoundInstancesForEffort(effortId);
          for (final ri in snapshot.roundInstances[effortId]!) {
            await _repository.createRoundInstance(ri);
          }
        }

        if (snapshot.timedInstances.containsKey(effortId)) {
          await _repository.deleteTimedInstancesForEffort(effortId);
          for (final ti in snapshot.timedInstances[effortId]!) {
            await _repository.createTimedInstance(ti);
          }
        }
      }

      _exerciseCache
        ..clear()
        ..addAll(snapshot.exerciseCache);

      await loadSessionData();
    } catch (e) {
      _setError('Failed to restore session snapshot: $e');
      rethrow;
    }
  }
}
