part of 'session_core.dart';

extension SessionCoreIOMethods on SessionCore {
  Future<void> createNewSession({
    String? modality,
    String? title,
    String? intent,
    String? routineTemplateId,
    bool isRolling = false,
    bool includeDefaultSegment = true,
  }) async {
    _setLoading(true);
    _clearError();

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final sessionId = 'session-$now';

      final session = TrainingSession(
        id: sessionId,
        ownerUserId: LoggedEntryRows.ownerUserId,
        routineTemplateId: routineTemplateId,
        startedAtMs: now,
        title: title,
        modality: modality,
        intent: intent,
        isRolling: isRolling,
        createdAtMs: now,
        updatedAtMs: now,
      );

      await _repository.createSession(session);
      _currentSession = session;
      _currentModalityConfig = ModalityConfig.forModality(modality);
      _sensorSummaries.clear();

      if (includeDefaultSegment) {
        final segment = LoggedEntryRows.defaultSegment(
          id: 'segment-$now',
          sessionId: sessionId,
          atMs: now,
        );

        await _repository.createSegment(segment);
        _segments.add(segment);
      }

      _notify();
    } catch (e) {
      _setError('Failed to create session: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> loadHistoricalSession(String sessionId) async {
    _setLoading(true);
    _clearError();

    try {
      final session = await _repository.getSession(sessionId);
      if (session == null) {
        _setError('Session not found.');
        return;
      }

      _currentSession = session;
      _currentModalityConfig = ModalityConfig.forModality(session.modality);

      _segments.clear();
      _efforts.clear();
      _observations.clear();
      _sensorSummaries.clear();
      _timerManager.clearAll();
      _blockManager.clearAll();

      final segments = await _repository.getSessionSegments(sessionId);
      _segments.addAll(segments);

      for (final segment in _segments) {
        final efforts = await _repository.getSegmentEfforts(segment.id);
        _efforts[segment.id] = efforts;

        for (final effort in efforts) {
          _observations[effort.id] = await _repository.getEffortObservations(
            effort.id,
          );

          if (effort.effortKind == 'round') {
            _timerManager.setRoundInstances(
              effort.id,
              await _repository.getRoundInstances(effort.id),
            );
          }
          if (effort.effortKind == 'timed' || effort.effortKind == 'drill') {
            _timerManager.setTimedInstances(
              effort.id,
              await _repository.getTimedInstances(effort.id),
            );
          }

          _timerManager.setEntryRests(
            effort.id,
            await _repository.getEntryRests(effort.id),
          );

          if (effort.exerciseId != null) {
            final ex = await _repository.getExerciseById(effort.exerciseId!);
            if (ex != null) _exerciseCache[ex.id] = ex;
          }
        }
      }

      final blocks = await _repository.getSessionBlocks(sessionId);
      _blockManager.setSessionBlocks(sessionId, blocks);

      if (session.endedAtMs != null) {
        _sensorSummaries.addAll(
          await _repository.getSensorSummariesForSession(sessionId),
        );
      }

      _notify();
    } catch (e) {
      _setError('Failed to load historical session: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> loadSessionData() async {
    if (_currentSession == null) {
      await createNewSession();
      return;
    }

    _setLoading(true);
    _clearError();

    try {
      final segments = await _repository.getSessionSegments(
        _currentSession!.id,
      );
      _segments
        ..clear()
        ..addAll(segments);
      _timerManager.clearAll();
      _blockManager.clearAll();

      for (final segment in _segments) {
        final efforts = await _repository.getSegmentEfforts(segment.id);
        _efforts[segment.id] = efforts;

        for (final effort in efforts) {
          _observations[effort.id] = await _repository.getEffortObservations(
            effort.id,
          );

          if (effort.effortKind == 'round') {
            _timerManager.setRoundInstances(
              effort.id,
              await _repository.getRoundInstances(effort.id),
            );
          }

          if (effort.effortKind == 'timed' || effort.effortKind == 'drill') {
            _timerManager.setTimedInstances(
              effort.id,
              await _repository.getTimedInstances(effort.id),
            );
          }

          _timerManager.setEntryRests(
            effort.id,
            await _repository.getEntryRests(effort.id),
          );

          if (effort.exerciseId != null &&
              !_exerciseCache.containsKey(effort.exerciseId)) {
            final exercise = await _repository.getExerciseById(
              effort.exerciseId!,
            );
            if (exercise != null) {
              _exerciseCache[effort.exerciseId!] = exercise;
            }
          }
        }
      }

      final sessionBlocks = await _repository.getSessionBlocks(
        _currentSession!.id,
      );
      _blockManager.setSessionBlocks(_currentSession!.id, sessionBlocks);

      final session = _currentSession!;
      final sensorSummaries = session.endedAtMs == null
          ? const <SensorSummary>[]
          : await _repository.getSensorSummariesForSession(session.id);
      _sensorSummaries
        ..clear()
        ..addAll(sensorSummaries);

      _notify();
    } catch (e) {
      _setError('Failed to load session data: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Re-reads the named efforts into the live session state, then notifies
  /// once — the refresh a merge of wrist rows runs so the regular session
  /// screen shows them at once (D-17).
  ///
  /// Unlike [loadSessionData] this re-reads only the named efforts and clears
  /// nothing: an effort it does not name, and every timer already running, is
  /// left exactly as it was, so a rest or exercise timer survives the refresh.
  Future<void> refreshEfforts(Iterable<String> effortIds) async {
    _clearError();

    try {
      for (final effortId in effortIds) {
        final effort = _findEffort(effortId);

        _observations[effortId] = await _repository.getEffortObservations(
          effortId,
        );

        if (effort == null) continue;

        if (effort.effortKind == 'round') {
          _timerManager.setRoundInstances(
            effortId,
            await _repository.getRoundInstances(effortId),
          );
        }

        if (effort.effortKind == 'timed' || effort.effortKind == 'drill') {
          _timerManager.setTimedInstances(
            effortId,
            await _repository.getTimedInstances(effortId),
          );
        }

        _timerManager.setEntryRests(
          effortId,
          await _repository.getEntryRests(effortId),
        );

        if (effort.exerciseId != null) {
          final exercise = await _repository.getExerciseById(
            effort.exerciseId!,
          );
          if (exercise != null) _exerciseCache[exercise.id] = exercise;
        }
      }

      _notify();
    } catch (e) {
      _setError('Failed to refresh efforts: $e');
    }
  }

  Future<void> populateSessionFromManifest(
    RoutineSessionManifest manifest,
  ) async {
    if (_currentSession == null) {
      throw Exception('No active session to populate');
    }

    _clearError();

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      var segmentCounter = 0;

      for (final segmentEntry in manifest.segments) {
        final templateSegment = segmentEntry.segment;
        final segmentId = 'segment-${_currentSession!.id}-$segmentCounter-$now';
        segmentCounter += 1;

        final sessionSegment = SessionSegment(
          id: segmentId,
          sessionId: _currentSession!.id,
          orderIndex: templateSegment.orderIndex,
          segmentType: templateSegment.segmentType,
          disciplineId: templateSegment.disciplineId,
          name: templateSegment.name,
          note: templateSegment.note,
          createdAtMs: now,
          updatedAtMs: now,
        );

        await _repository.createSegment(sessionSegment);
        _segments.add(sessionSegment);
        _efforts.putIfAbsent(segmentId, () => []);

        String? blockId;
        if (segmentEntry.exercises.isNotEmpty) {
          blockId = await addSessionBlock(
            name: templateSegment.name ?? 'Block $segmentCounter',
          );
        }

        for (final entry in segmentEntry.exercises) {
          final effortId = await addExerciseToSession(
            entry.exercise,
            effortKindOverride: entry.effortKind,
            segmentId: segmentId,
          );

          if (effortId.isEmpty) continue;

          if (blockId != null) {
            await assignEffortToBlock(effortId, blockId);
          }

          for (int i = 1; i < entry.setCount; i++) {
            await addEntry(effortId);
          }

          for (final target in entry.targets) {
            final entryIndex = target.setIndex ?? 0;
            final metricKey =
                MetricIds.metricIdToKey[target.metricId] ?? target.metricId;

            dynamic value;
            if (target.targetInt != null) {
              value = target.targetInt;
            } else if (target.targetMin != null) {
              value = target.targetMin;
            } else if (target.targetMax != null) {
              value = target.targetMax;
            } else if (target.targetText != null) {
              value = target.targetText;
            }

            if (value == null) continue;

            if (metricKey == 'reps' ||
                metricKey == 'rounds' ||
                metricKey == 'duration') {
              value = value is int ? value : (value as double).toInt();
            } else {
              value = value is double ? value : (value as int).toDouble();
            }

            try {
              await updateEntryValue(effortId, entryIndex, metricKey, value);
            } catch (_) {
              // Ignore invalid metric for effort.
            }
          }
        }
      }

      _notify();
    } catch (e) {
      _setError('Failed to populate session from manifest: $e');
      rethrow;
    }
  }
}
