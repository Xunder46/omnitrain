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
      // Every kind of new entry is numbered above every number the effort
      // holds (D-325), so an add after a delete can never land on a stored
      // row the way a count-based index did (F-5).
      final entryNumber = EntryRows.nextNumber(existingObservations);

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
                entryIndex: entryNumber,
                distanceMeters: (previousValues?['distance'] as double?) ?? 0.0,
                extraWeightKg: extraWeightKg,
                atMs: now,
              )
            : LoggedEntryRows.drillObservations(
                effortId: effortId,
                entryIndex: entryNumber,
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
              entryIndex: entryNumber,
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
              id: LoggedEntryRows.observationId(effortId, entryNumber, 'reps'),
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
      final effort = _findEffort(effortId);
      if (effort == null) return;

      if (metricKey == 'round-duration' && effort.effortKind == 'round') {
        await _timerManager.updateRoundPlannedDuration(
          effortId,
          entryIndex,
          value as int,
        );
        return;
      }

      if (metricKey == 'duration' &&
          (effort.effortKind == 'timed' || effort.effortKind == 'drill')) {
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

      final obsIndex = _rowIndexEntryOwns(
        effort,
        observations,
        metricId,
        entryIndex,
      );

      if (obsIndex >= 0) {
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
        final number = effort.effortKind == 'set'
            // A set's row joins the set it was entered for, by that set's own
            // number (D-325), so a gap left by an old delete cannot move it to
            // another set.
            ? _setNumberAt(observations, entryIndex) ??
                  EntryRows.nextNumber(observations)
            // A hold's or a timed entry's row is the k-th of its metric, so its
            // missing predecessors are filled first and it is numbered past
            // every stored row — never onto one (F-4).
            : await _fillEntriesBefore(
                paired: EntryRows.companions(
                  rows: observations,
                  metricId: metricId,
                  entryCount: _timerManager
                      .getTimedInstancesForEffort(effortId)
                      .length,
                ),
                entryIndex: entryIndex,
                observations: observations,
                buildRow: (position) => _newExtraWeightRow(
                  effortId: effortId,
                  number: position,
                  value: 0.0,
                  atMs: now,
                ),
              );

        final newObservation = _newExtraWeightRow(
          effortId: effortId,
          number: number,
          value: value is double ? value : (value as num).toDouble(),
          atMs: now,
        );

        await _repository.createObservation(newObservation);
        observations.add(newObservation);
        _notify();
      }
    } catch (e) {
      _setError('Failed to update entry: $e');
    }
  }

  /// Added load in kilograms, named for [number] as every writer names it.
  EffortObservation _newExtraWeightRow({
    required String effortId,
    required int number,
    required double value,
    required int atMs,
  }) => EffortObservation(
    id: LoggedEntryRows.observationId(effortId, number, 'extra-weight'),
    effortId: effortId,
    metricId: MetricIds.extraWeight,
    unitId: MetricIds.unitKg,
    valueReal: value,
    createdAtMs: atMs,
    updatedAtMs: atMs,
  );

  /// Gives every entry before [entryIndex] that holds no row of its own a
  /// zero-valued one, numbered upward, and returns the number the caller's own
  /// row takes (D-313's filling, D-325's numbering).
  ///
  /// [paired] is the entry-to-row pairing of the metric being written; a run of
  /// rows is what makes the caller's row the k-th of that metric, so a value
  /// typed on a later entry cannot land on an earlier one.
  Future<int> _fillEntriesBefore({
    required List<EffortObservation?> paired,
    required int entryIndex,
    required List<EffortObservation> observations,
    required EffortObservation Function(int number) buildRow,
  }) async {
    var number = EntryRows.nextNumber(observations);
    for (var i = 0; i < entryIndex && i < paired.length; i++) {
      if (paired[i] != null) continue;
      final filled = buildRow(number);
      number++;
      await _repository.createObservation(filled);
      observations.add(filled);
    }
    return number;
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

  /// An effort's distance entries, each with its own row or none (D-328).
  ///
  /// The Summary builds its DISTANCE rows from this, and every distance write
  /// addresses the same list, so a row on screen and the row an edit lands on
  /// are the same entry.
  List<DistanceEntry> getEffortDistanceEntries(String effortId) {
    final effort = _findEffort(effortId);
    if (effort == null) return const [];
    return EntryRows.distanceEntries(
      rows: _observations[effortId] ?? const <EffortObservation>[],
      timed: effort.effortKind == 'timed',
      instanceCount: _timerManager.getTimedInstancesForEffort(effortId).length,
    );
  }

  /// Records the distance an entry already holds as entered, keeping the
  /// stored metres exactly (D-307). Confirming the value the dialog pre-filled
  /// is what turns an estimate into a confirmed entry; an entry with no
  /// distance has nothing to confirm and is left alone.
  Future<void> confirmEntryDistance(String effortId, int entryIndex) async {
    _clearError();

    try {
      final entries = getEffortDistanceEntries(effortId);
      if (entryIndex < 0 || entryIndex >= entries.length) return;

      final stored = entries[entryIndex].row;
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

    final entries = getEffortDistanceEntries(effortId);
    if (entryIndex < 0 || entryIndex >= entries.length) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final hasDistance = metres > 0;

    // Every entry before the edited one that has no row yet gets a
    // zero-valued row with no source, so the row the edit writes is the k-th
    // and lands on the entry the user chose (D-313).
    final number = await _fillEntriesBefore(
      paired: [for (final entry in entries) entry.row],
      entryIndex: entryIndex,
      observations: observations,
      buildRow: (position) =>
          _newDistanceRow(effortId: effortId, number: position, atMs: now),
    );

    final stored = entries[entryIndex].row;
    if (stored == null) {
      final created = _newDistanceRow(
        effortId: effortId,
        number: number,
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

  /// A distance row named as every writer names one
  /// (`obs-<effortId>-<n>-distance`). [number] comes from the effort's own
  /// rows (D-325), so a new row never takes an id a stored row holds and no
  /// suffix is ever minted.
  EffortObservation _newDistanceRow({
    required String effortId,
    required int number,
    required int atMs,
    double metres = 0.0,
    String? source,
  }) => EffortObservation(
    id: LoggedEntryRows.observationId(effortId, number, 'distance'),
    effortId: effortId,
    metricId: MetricIds.distance,
    unitId: MetricIds.unitMeters,
    valueReal: metres,
    valueSource: source,
    createdAtMs: atMs,
    updatedAtMs: atMs,
  );

  Future<void> markSetSkipped(String effortId, int entryIndex) async {
    _clearError();
    try {
      final observations = _observations[effortId];
      final effort = _findEffort(effortId);
      if (observations == null || effort == null) return;

      final repsId = MetricIds.keyToMetricId['reps'];
      if (repsId == null) return;

      final obsIndex = _rowIndexEntryOwns(
        effort,
        observations,
        repsId,
        entryIndex,
      );
      if (obsIndex < 0) return;

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
    } catch (e) {
      _setError('Failed to mark set as skipped: $e');
    }
  }

  /// The index in [rows] of the row entry [entryIndex] owns for [metricId]
  /// (D-324), or -1 when the entry holds none.
  ///
  /// D-324's legacy clause leaves an effort that stores a row without a number
  /// unaddressable by the rule, so the caller falls back to the row's own
  /// position on the list — which is all that reading ever had.
  int _rowIndexEntryOwns(
    SegmentEffort effort,
    List<EffortObservation> rows,
    String metricId,
    int entryIndex,
  ) {
    EffortObservation? owned;
    if (!_entriesAreNumbered(effort, rows)) {
      final matching = rows.where((row) => row.metricId == metricId).toList();
      owned = entryIndex < matching.length ? matching[entryIndex] : null;
    } else if (effort.effortKind == 'timed' || effort.effortKind == 'drill') {
      final paired = EntryRows.companions(
        rows: rows,
        metricId: metricId,
        entryCount: _timerManager.getTimedInstancesForEffort(effort.id).length,
      );
      owned = entryIndex < paired.length ? paired[entryIndex] : null;
    } else {
      owned = _setRowsAt(rows, entryIndex)?.rowFor(metricId);
    }

    final row = owned;
    if (row == null) return -1;
    return rows.indexWhere((candidate) => candidate.id == row.id);
  }

  /// True when every row of the effort carries an entry number, so the rule
  /// can address one entry at a time. A run effort's entries are its timed
  /// instances whatever its rows are named, so it is always addressable.
  bool _entriesAreNumbered(SegmentEffort effort, List<EffortObservation> rows) {
    if (effort.effortKind == 'timed' || effort.effortKind == 'drill') {
      return true;
    }
    if (effort.effortKind == 'round') return false;
    return rows.every((row) => EntryRows.numberInId(row.id) != null);
  }

  /// Set entry [entryIndex] (D-324), or null when the effort holds none.
  SetRows? _setRowsAt(List<EffortObservation> rows, int entryIndex) {
    final groups = EntryRows.setGroups(rows);
    if (entryIndex < 0 || entryIndex >= groups.length) return null;
    return groups[entryIndex];
  }

  /// The number set entry [entryIndex] carries (D-324), or null when the
  /// effort has no such entry or cannot be read that way.
  int? _setNumberAt(List<EffortObservation> rows, int entryIndex) =>
      _setRowsAt(rows, entryIndex)?.number;

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

      // D-326: exactly the rows of the set the caller chose — the k-th group,
      // not the rows whose id happens to start with the display position.
      final group = _setRowsAt(observations, entryIndex);
      if (_entriesAreNumbered(effort, observations) && group != null) {
        final doomed = {for (final row in group.rows) row.id};
        for (final id in doomed) {
          await _repository.deleteObservation(id);
        }
        observations.removeWhere((row) => doomed.contains(row.id));
        _notify();
        return;
      }

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
