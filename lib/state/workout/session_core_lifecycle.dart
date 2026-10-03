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
      await _timerManager.persistOpenRests(now);
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
      return;
    }

    // Platform health write. Deliberately outside the persistence
    // try/catch above: the session is already saved and the service is
    // contract-bound never to throw, so nothing here can flip the
    // session into an error state.
    final completedSession = _currentSession;
    if (completedSession != null) {
      await _healthSync?.onSessionCompleted(completedSession);
    }
  }

  /// Resets the session start timestamp to now.
  ///
  /// Called once when the first exercise is added to a live session so that
  /// the global elapsed timer begins counting from the moment training actually
  /// starts, rather than from when the empty session was created.
  Future<void> resetSessionTimerStart() async {
    if (_currentSession == null) return;

    _clearError();

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final updatedSession = TrainingSession(
        id: _currentSession!.id,
        ownerUserId: _currentSession!.ownerUserId,
        routineTemplateId: _currentSession!.routineTemplateId,
        startedAtMs: now,
        endedAtMs: _currentSession!.endedAtMs,
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
      _setError('Failed to reset session timer start: $e');
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

  /// The `entryId` of every applied inbox row of the current session: the
  /// watermark an edit snapshot taken now would carry (D-801).
  ///
  /// Read before the session's rows are loaded, so the watermark can only be
  /// a subset of what the snapshot's rows reflect. An empty set when there is
  /// no current session.
  Future<Set<String>> appliedWatchEntryIds() async {
    final session = _currentSession;
    if (session == null) return <String>{};

    final rows = await _repository.getWatchInboxEntriesForSession(session.id);
    return {
      for (final row in rows)
        if (row.appliedAtMs != null) row.entryId,
    };
  }

  SessionEditSnapshot? snapshotSessionState({
    Set<String>? watchEntryIdsAppliedAtSnapshot,
  }) {
    if (_currentSession == null) return null;

    return SessionEditSnapshot(
      sessionId: _currentSession!.id,
      watchEntryIdsAppliedAtSnapshot: watchEntryIdsAppliedAtSnapshot,
      segments: List<SessionSegment>.from(_segments),
      efforts: {
        for (final entry in _efforts.entries)
          entry.key: List<SegmentEffort>.from(entry.value),
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
      sensorSummaries: List<SensorSummary>.from(_sensorSummaries),
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

      // D-131 deleted the summaries of every target the edit or the deletes
      // above removed; the targets are back, so put their summaries back.
      // Put-if-absent leaves every summary that survived untouched.
      for (final summary in snapshot.sensorSummaries) {
        await _repository.createSensorSummary(summary);
      }

      // A watch entry that arrived while the screen was open is not in the
      // snapshot's rows, so the loops above just deleted it. Un-mark it and
      // run one ordinary import pass to bring it back (D-802, D-804, D-805).
      // After the loops, so they cannot delete what the pass re-creates, and
      // before the reload, so the screen shows the recovered rows.
      final watermark = snapshot.watchEntryIdsAppliedAtSnapshot;
      final recovery = _lateEntryRecovery;
      if (watermark != null && recovery != null) {
        await recovery.recoverEntriesAppliedSince(snapshot.sessionId, watermark);
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
