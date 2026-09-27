part of 'session_core.dart';

extension SessionCoreEntryMethods on SessionCore {
  Future<String> addExerciseToSession(
    Exercise exercise, {
    String? chosenMetric,
    String? effortKindOverride,
    String? segmentId,
  }) async {
    if (_segments.isEmpty) return '';

    _clearError();

    try {
      final segment = segmentId != null
          ? _segments.firstWhere(
              (s) => s.id == segmentId,
              orElse: () => _segments.first,
            )
          : _segments.first;
      final now = DateTime.now().millisecondsSinceEpoch;

      String effortKind;
      if (effortKindOverride != null) {
        effortKind = effortKindOverride;
      } else if (_currentModalityConfig != null &&
          _currentSession?.modality != null) {
        effortKind = _currentModalityConfig!.effortKind;
      } else if (chosenMetric != null) {
        effortKind = ModalityConfig.effortKindFromMetric(chosenMetric);
      } else {
        effortKind = 'set';
      }

      // Hydrate through the repository so the cached exercise carries the
      // canonical capabilities (matches how the exercise browser presents
      // them). The caller's Exercise is used as a fallback if the id is not
      // yet known to the repository.
      final hydrated =
          (await _repository.getExerciseById(exercise.id)) ?? exercise;
      _exerciseCache[exercise.id] = hydrated;

      final currentEfforts = _efforts[segment.id] ?? [];
      final effortId = 'effort-$now-${currentEfforts.length}';
      final effort = SegmentEffort(
        id: effortId,
        segmentId: segment.id,
        orderIndex: currentEfforts.length,
        effortKind: effortKind,
        exerciseId: exercise.id,
        createdAtMs: now,
        updatedAtMs: now,
      );

      await _repository.createEffort(effort);
      _efforts.putIfAbsent(segment.id, () => []).add(effort);

      await addEntry(effortId);

      _notify();
      return effortId;
    } catch (e) {
      _setError('Failed to add exercise: $e');
      return '';
    }
  }

  Future<void> addEntry(
    String effortId, {
    Map<String, dynamic>? previousValues,
  }) async {
    _clearError();

    try {
      final effort = _findEffort(effortId);
      if (effort == null) {
        _setError('Effort not found');
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final existingObservations =
          _observations[effortId] ?? <EffortObservation>[];
      final entryIndex = effort.effortKind == 'set'
          ? _nextSetEntryIndex(existingObservations)
          : existingObservations.length ~/ 2;

      final existingEntryCount = effort.effortKind == 'round'
          ? _timerManager.getRoundsForEffort(effortId).length
          : ((effort.effortKind == 'timed' || effort.effortKind == 'drill')
                ? _timerManager.getTimedInstancesForEffort(effortId).length
                : existingObservations
                      .where((o) => o.metricId == MetricIds.reps)
                      .length);
      if (existingEntryCount >= WorkoutConstants.maxEntriesPerEffort) {
        return;
      }

      if (effort.effortKind == 'round') {
        final existingRounds = _timerManager.getRoundsForEffort(effortId);
        final exerciseDefault =
            _exerciseCache[effort.exerciseId]?.defaultRoundDurationSecs;
        final previousDuration = existingRounds.isNotEmpty
            ? existingRounds.last.plannedDurationSecs
            : (previousValues?['round-duration'] as int?) ??
                  exerciseDefault ??
                  WorkoutConstants.defaultRoundDurationSecs;
        await _timerManager.addRound(
          effortId,
          plannedDurationSecs: previousDuration,
        );
        return;
      }

      if (effort.effortKind == 'timed' || effort.effortKind == 'drill') {
        final existing = _timerManager.getTimedInstancesForEffort(effortId);
        final timedIndex = existing.length;
        final targetDuration = (previousValues?['duration'] as int?) ?? 0;

        await _timerManager.addTimedEntry(
          effortId,
          targetDurationSecs: targetDuration,
        );

        final extraWeightKg =
            (previousValues?['extra-weight'] as double?) ?? 0.0;
        final obsToCreate = effort.effortKind == 'timed'
            ? LoggedEntryRows.timedObservations(
                effortId: effortId,
                entryIndex: timedIndex,
                distanceMeters: (previousValues?['distance'] as double?) ?? 0.0,
                extraWeightKg: extraWeightKg,
                atMs: now,
              )
            : LoggedEntryRows.drillObservations(
                effortId: effortId,
                entryIndex: timedIndex,
                extraWeightKg: extraWeightKg,
                atMs: now,
              );
        for (final obs in obsToCreate) {
          await _repository.createObservation(obs);
        }
        _observations.putIfAbsent(effortId, () => []).addAll(obsToCreate);

        _notify();
        return;
      }

      final observations = <EffortObservation>[];

      switch (effort.effortKind) {
        case 'set':
          final hasLoad =
              _exerciseCache[effort.exerciseId]?.capabilities.contains(
                'load',
              ) ??
              false;
          observations.addAll(
            LoggedEntryRows.setObservations(
              effortId: effortId,
              entryIndex: entryIndex,
              reps: (previousValues?['reps'] as int?) ?? 10,
              weightKg: (previousValues?['weight'] as double?) ?? 0.0,
              exerciseHasLoad: hasLoad,
              extraWeightKg:
                  (previousValues?['extra-weight'] as double?) ?? 0.0,
              atMs: now,
            ),
          );
          break;
        default:
          observations.add(
            EffortObservation(
              id: 'obs-$effortId-$entryIndex-reps',
              effortId: effortId,
              metricId: MetricIds.reps,
              unitId: MetricIds.unitReps,
              valueInt: 10,
              createdAtMs: now,
              updatedAtMs: now,
            ),
          );
      }

      for (final obs in observations) {
        await _repository.createObservation(obs);
      }

      _observations.putIfAbsent(effortId, () => []).addAll(observations);

      _notify();
    } catch (e) {
      _setError('Failed to add entry: $e');
    }
  }

  Future<void> updateEntryValue(
    String effortId,
    int entryIndex,
    String metricKey,
    dynamic value,
  ) async {
    _clearError();

    try {
      if (metricKey == 'round-duration' &&
          _findEffort(effortId)?.effortKind == 'round') {
        await _timerManager.updateRoundPlannedDuration(
          effortId,
          entryIndex,
          value as int,
        );
        return;
      }

      final effortKind = _findEffort(effortId)?.effortKind;
      if (metricKey == 'duration' &&
          (effortKind == 'timed' || effortKind == 'drill')) {
        await _timerManager.updateTimedTargetDuration(
          effortId,
          entryIndex,
          value as int,
        );
        return;
      }

      final observations = _observations[effortId];
      if (observations == null) return;

      final metricId = MetricIds.keyToMetricId[metricKey];
      if (metricId == null) return;

      final matchingObservations = observations
          .asMap()
          .entries
          .where((entry) => entry.value.metricId == metricId)
          .toList();

      if (entryIndex < matchingObservations.length) {
        final obsIndex = matchingObservations[entryIndex].key;
        final oldObs = observations[obsIndex];
        final shouldClearSkipMarker =
            metricKey == 'reps' && value is int && value > 0;
        final newObs = EffortObservation(
          id: oldObs.id,
          effortId: oldObs.effortId,
          metricId: oldObs.metricId,
          unitId: oldObs.unitId,
          valueInt: (value is int) ? value : oldObs.valueInt,
          valueReal: (value is double) ? value : oldObs.valueReal,
          valueText: (value is String) ? value : oldObs.valueText,
          valueBool: shouldClearSkipMarker
              ? false
              : ((value is bool) ? value : oldObs.valueBool),
          valueSource: oldObs.valueSource,
          rpeRating: oldObs.rpeRating,
          restDurationMs: oldObs.restDurationMs,
          createdAtMs: oldObs.createdAtMs,
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        );

        await _repository.updateObservation(newObs);
        observations[obsIndex] = newObs;

        _notify();
      } else if (metricKey == 'extra-weight') {
        final now = DateTime.now().millisecondsSinceEpoch;
        final newObservation = EffortObservation(
          id: 'obs-$effortId-$entryIndex-extra-weight',
          effortId: effortId,
          metricId: metricId,
          unitId: MetricIds.metricKeyToUnitId[metricKey],
          valueReal: value is double ? value : (value as num).toDouble(),
          createdAtMs: now,
          updatedAtMs: now,
        );

        await _repository.createObservation(newObservation);
        observations.add(newObservation);
        _notify();
      }
    } catch (e) {
      _setError('Failed to update entry: $e');
    }
  }

  /// Writes the distance of one entry, in metres (D-307, D-313).
  ///
  /// A value greater than zero is stored as given, with source `entered`; zero
  /// stores 0.0 with no source, which is how a distance is removed. An
  /// existing row keeps its id and `createdAtMs` and gets a new `updatedAtMs`.
  ///
  /// [entryIndex] is the entry's position among the effort's entries: its
  /// timed instances, or — on an effort that is not timed — its distance rows,
  /// which are the data-safety rows of D-319.
  Future<void> setEntryDistance(
    String effortId,
    int entryIndex,
    double metres,
  ) async {
    _clearError();

    try {
      await _writeEntryDistance(effortId, entryIndex, metres);
    } catch (e) {
      _setError('Failed to set distance: $e');
    }
  }

  /// Records the distance an entry already holds as entered, keeping the
  /// stored metres exactly (D-307). Confirming the value the dialog pre-filled
  /// is what turns an estimate into a confirmed entry; an entry with no
  /// distance has nothing to confirm and is left alone.
  Future<void> confirmEntryDistance(String effortId, int entryIndex) async {
    _clearError();

    try {
      final paired = DistancePairing.forEntries(
        distanceRows: _observations[effortId] ?? const <EffortObservation>[],
        entryCount: _distanceEntryCount(effortId),
      );
      if (entryIndex < 0 || entryIndex >= paired.length) return;

      final stored = paired[entryIndex];
      if (stored == null) return;

      await _writeEntryDistance(effortId, entryIndex, stored.valueReal ?? 0.0);
    } catch (e) {
      _setError('Failed to set distance: $e');
    }
  }

  Future<void> _writeEntryDistance(
    String effortId,
    int entryIndex,
    double metres,
  ) async {
    final observations = _observations[effortId];
    if (observations == null) return;

    final entryCount = _distanceEntryCount(effortId);
    if (entryIndex < 0 || entryIndex >= entryCount) return;

    final paired = DistancePairing.forEntries(
      distanceRows: observations,
      entryCount: entryCount,
    );
    final now = DateTime.now().millisecondsSinceEpoch;

    // Every entry before the edited one that has no row yet gets a
    // zero-valued row with no source, so that the pairing the next write reads
    // stays positional (D-313).
    for (var i = 0; i < entryIndex; i++) {
      if (paired[i] != null) continue;
      final filled = _newDistanceRow(
        effortId: effortId,
        entryIndex: i,
        observations: observations,
        atMs: now,
      );
      await _repository.createObservation(filled);
      observations.add(filled);
    }

    final hasDistance = metres > 0;
    final stored = paired[entryIndex];
    if (stored == null) {
      final created = _newDistanceRow(
        effortId: effortId,
        entryIndex: entryIndex,
        observations: observations,
        atMs: now,
        metres: hasDistance ? metres : 0.0,
        source: hasDistance ? EffortObservation.sourceEntered : null,
      );
      await _repository.createObservation(created);
      observations.add(created);
    } else {
      final updated = EffortObservation(
        id: stored.id,
        effortId: stored.effortId,
        metricId: stored.metricId,
        unitId: stored.unitId,
        valueInt: stored.valueInt,
        valueReal: hasDistance ? metres : 0.0,
        valueText: stored.valueText,
        valueBool: stored.valueBool,
        valueSource: hasDistance ? EffortObservation.sourceEntered : null,
        rpeRating: stored.rpeRating,
        restDurationMs: stored.restDurationMs,
        createdAtMs: stored.createdAtMs,
        updatedAtMs: now,
      );
      await _repository.updateObservation(updated);
      final index = observations.indexWhere((o) => o.id == stored.id);
      if (index >= 0) observations[index] = updated;
    }

    _notify();
  }

  /// How many entries [effortId] holds for distance purposes (D-312, D-319):
  /// its timed instances, or — on an effort that is not timed — its distance
  /// rows themselves, because the data-safety rows have no instance behind
  /// them.
  int _distanceEntryCount(String effortId) {
    if (_findEffort(effortId)?.effortKind == 'timed') {
      return _timerManager.getTimedInstancesForEffort(effortId).length;
    }
    return (_observations[effortId] ?? const <EffortObservation>[])
        .where((row) => row.metricId == MetricIds.distance)
        .length;
  }

  /// A distance row named as every writer names one
  /// (`obs-<effortId>-<n>-distance`), with the writing timestamp appended when
  /// that id is already taken (D-313).
  EffortObservation _newDistanceRow({
    required String effortId,
    required int entryIndex,
    required List<EffortObservation> observations,
    required int atMs,
    double metres = 0.0,
    String? source,
  }) {
    final plainId = LoggedEntryRows.observationId(
      effortId,
      entryIndex,
      'distance',
    );
    return EffortObservation(
      id: observations.any((row) => row.id == plainId)
          ? '$plainId-$atMs'
          : plainId,
      effortId: effortId,
      metricId: MetricIds.distance,
      unitId: MetricIds.unitMeters,
      valueReal: metres,
      valueSource: source,
      createdAtMs: atMs,
      updatedAtMs: atMs,
    );
  }

  Future<void> markSetSkipped(String effortId, int entryIndex) async {
    _clearError();
    try {
      final observations = _observations[effortId];
      if (observations == null) return;
      final metricId = MetricIds.keyToMetricId['reps'];
      if (metricId == null) return;
      final matchingObservations = observations
          .asMap()
          .entries
          .where((e) => e.value.metricId == metricId)
          .toList();
      if (entryIndex < matchingObservations.length) {
        final obsIndex = matchingObservations[entryIndex].key;
        final oldObs = observations[obsIndex];
        final newObs = EffortObservation(
          id: oldObs.id,
          effortId: oldObs.effortId,
          metricId: oldObs.metricId,
          unitId: oldObs.unitId,
          valueInt: 0,
          valueReal: oldObs.valueReal,
          valueText: oldObs.valueText,
          valueBool: true,
          valueSource: oldObs.valueSource,
          rpeRating: oldObs.rpeRating,
          restDurationMs: oldObs.restDurationMs,
          createdAtMs: oldObs.createdAtMs,
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        );
        await _repository.updateObservation(newObs);
        observations[obsIndex] = newObs;
        _notify();
      }
    } catch (e) {
      _setError('Failed to mark set as skipped: $e');
    }
  }

  /// Returns the next available index for a new 'set' entry by finding the
  /// maximum index already encoded in the observation IDs and adding 1.
  /// This is necessary because deleting a middle set leaves a gap in the
  /// index sequence — using count-of-reps-obs instead would produce a
  /// duplicate index, silently overwriting the last set rather than adding
  /// a new one.
  int _nextSetEntryIndex(List<EffortObservation> observations) {
    final pattern = RegExp(r'obs-.+-(\d+)-[^-]+$');
    var maxIndex = -1;
    for (final obs in observations) {
      final match = pattern.firstMatch(obs.id);
      final idx = int.tryParse(match?.group(1) ?? '');
      if (idx != null && idx > maxIndex) maxIndex = idx;
    }
    return maxIndex + 1;
  }

  Future<void> deleteEntry(String effortId, int entryIndex) async {
    _clearError();

    try {
      final effort = _findEffort(effortId);
      if (effort == null) return;

      if (effort.effortKind == 'round') {
        await _timerManager.deleteRound(effortId, entryIndex);
        return;
      }

      if (effort.effortKind == 'timed' || effort.effortKind == 'drill') {
        await _timerManager.deleteTimedEntry(effortId, entryIndex);
        return;
      }

      final observations = _observations[effortId];
      if (observations == null) return;

      final idPrefix = 'obs-$effortId-$entryIndex-';
      final obsToDelete = observations
          .where((o) => o.id.startsWith(idPrefix))
          .toList();

      if (obsToDelete.isNotEmpty) {
        for (final obs in obsToDelete) {
          await _repository.deleteObservation(obs.id);
        }
        observations.removeWhere((o) => o.id.startsWith(idPrefix));
      } else {
        final metricsPerEntry = _getMetricsPerEntry(effort.effortKind);
        final startIndex = entryIndex * metricsPerEntry;
        final endIndex = startIndex + metricsPerEntry;

        if (startIndex >= observations.length) return;

        final fallbackDelete = observations.sublist(
          startIndex,
          endIndex.clamp(0, observations.length),
        );

        for (final obs in fallbackDelete) {
          await _repository.deleteObservation(obs.id);
        }

        observations.removeRange(
          startIndex,
          endIndex.clamp(0, observations.length),
        );
      }

      _notify();
    } catch (e) {
      _setError('Failed to delete entry: $e');
    }
  }

  Future<void> removeExerciseFromSession(String effortId) async {
    _clearError();

    try {
      await _repository.deleteEffort(effortId);

      _observations.remove(effortId);
      _timerManager.removeEffort(effortId);
      for (final effortList in _efforts.values) {
        effortList.removeWhere((e) => e.id == effortId);
      }

      _notify();
    } catch (e) {
      _setError('Failed to remove exercise: $e');
    }
  }
}
