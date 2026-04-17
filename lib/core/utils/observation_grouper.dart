/// Utility for grouping observations into entries by effort kind
/// Handles the mapping between raw observations and UI-ready entry maps
class ObservationGrouper {
  /// Group observations into entries based on effort kind
  ///
  /// **DEPRECATION NOTE (Phase 2 Complete)**:
  /// The 'round' case below is now dead code. After Phase 2 implementation,
  /// WorkoutState.getExercisesWithEntries() builds round entries directly from
  /// RoundInstance records instead of calling this method for round efforts.
  ///
  /// However, the 'round' branch is intentionally retained for **backward compatibility
  /// with legacy observation-pair data** that may have been persisted before this refactor.
  ///
  /// **Action Required Before Removing** (Product/DevOps decision):
  /// 1. Audit production database for any persisted round efforts with observation pairs
  /// 2. If found: Run migration to convert observations → RoundInstance records
  /// 3. If none found: Remove the 'round' branch and [_groupRoundObservations] method
  ///
  /// For development/test environments (greenfield setup), the 'round' branch can be
  /// safely deleted immediately since no legacy data exists.
  static List<Map<String, dynamic>> groupByEffortKind(
    String effortKind,
    List<dynamic> observations,
  ) {
    switch (effortKind) {
      case 'set':
        return _groupSetObservations(observations);
      case 'timed':
        return _groupTimedObservations(observations);
      case 'round':
        // DEPRECATED: round entries are now stored as RoundInstance records,
        // not as observation pairs. This path handles legacy data only and
        // will be removed in Phase 2 when WorkoutState is updated.
        // See: lib/data/models/models.dart (RoundInstance)
        //      lib/data/repositories/workout_repository.dart (getRoundInstances)
        return _groupRoundObservations(observations);
      case 'drill':
        return _groupDrillObservations(observations);
      default:
        return _groupSetObservations(observations); // Fallback
    }
  }

  /// Group set observations by entry index when encoded in the observation ID.
  /// Falls back to sequential grouping for legacy/tests that only provide metric pairs.
  static List<Map<String, dynamic>> _groupSetObservations(
    List<dynamic> observations,
  ) {
    final entryPattern = RegExp(r'obs-.+-(\d+)-[^-]+$');
    final hasIndexedIds = observations.every(
      (obs) => obs.id is String && entryPattern.hasMatch(obs.id as String),
    );

    if (hasIndexedIds) {
      final entriesByIndex = <int, Map<String, dynamic>>{};

      for (final obs in observations) {
        final match = entryPattern.firstMatch(obs.id as String);
        final entryIndex = int.tryParse(match?.group(1) ?? '') ?? 0;
        final entry = entriesByIndex.putIfAbsent(entryIndex, () {
          return {'reps': 0, 'weight': 0.0, 'skipped': false};
        });

        switch (obs.metricId) {
          case 'metric-reps':
            entry['reps'] = obs.valueInt ?? 0;
            entry['skipped'] = (obs.valueBool as bool?) ?? false;
            break;
          case 'metric-weight':
            entry['weight'] = obs.valueReal ?? 0.0;
            break;
          case 'metric-extra-weight':
            entry['extra-weight'] = obs.valueReal ?? 0.0;
            break;
        }
      }

      final sortedIndices = entriesByIndex.keys.toList()..sort();
      return sortedIndices.map((index) => entriesByIndex[index]!).toList();
    }

    final entries = <Map<String, dynamic>>[];
    var current = <String, dynamic>{'reps': 0, 'weight': 0.0, 'skipped': false};
    final seenMetrics = <String>{};

    void flushCurrent() {
      if (seenMetrics.isEmpty) return;
      if (seenMetrics.contains('metric-reps') &&
          seenMetrics.contains('metric-weight')) {
        entries.add(Map<String, dynamic>.from(current));
      }
      current = {'reps': 0, 'weight': 0.0, 'skipped': false};
      seenMetrics.clear();
    }

    for (final obs in observations) {
      final metricId = obs.metricId as String;
      if (seenMetrics.contains(metricId)) {
        flushCurrent();
      }
      seenMetrics.add(metricId);

      switch (metricId) {
        case 'metric-reps':
          current['reps'] = obs.valueInt ?? 0;
          current['skipped'] = (obs.valueBool as bool?) ?? false;
          break;
        case 'metric-weight':
          current['weight'] = obs.valueReal ?? 0.0;
          break;
        case 'metric-extra-weight':
          current['extra-weight'] = obs.valueReal ?? 0.0;
          break;
      }
    }

    flushCurrent();
    return entries;
  }

  /// Group duration + distance pairs for timed/cardio exercises
  static List<Map<String, dynamic>> _groupTimedObservations(
    List<dynamic> observations,
  ) {
    final entries = <Map<String, dynamic>>[];
    for (int i = 0; i < observations.length; i += 2) {
      if (i + 1 < observations.length) {
        final obs1 = observations[i];
        final obs2 = observations[i + 1];

        // Explicitly check metricIds to avoid position-based assumptions
        final durationValue = obs1.metricId == 'metric-duration'
            ? (obs1.valueInt ?? 0)
            : (obs2.valueInt ?? 0);
        final distanceValue = obs1.metricId == 'metric-distance'
            ? (obs1.valueReal ?? 0.0)
            : (obs2.valueReal ?? 0.0);

        entries.add({'duration': durationValue, 'distance': distanceValue});
      }
    }
    return entries;
  }

  /// Group rounds + round-duration pairs for round-based exercises.
  ///
  /// DEPRECATED (Phase 1): Round exercises now use [RoundInstance] records
  /// for all new data.  This method exists solely to group any legacy
  /// metric-rounds / metric-round-duration observation pairs that may have
  /// been persisted before the Phase 2 WorkoutState migration.
  /// It will be removed once Phase 2 is complete.
  static List<Map<String, dynamic>> _groupRoundObservations(
    List<dynamic> observations,
  ) {
    final entries = <Map<String, dynamic>>[];
    for (int i = 0; i < observations.length; i += 2) {
      if (i + 1 < observations.length) {
        final obs1 = observations[i];
        final obs2 = observations[i + 1];

        // Explicitly check metricIds to avoid position-based assumptions
        final roundsValue = obs1.metricId == 'metric-rounds'
            ? (obs1.valueInt ?? 1)
            : (obs2.valueInt ?? 1);
        final durationValue = obs1.metricId == 'metric-round-duration'
            ? (obs1.valueInt ?? 180)
            : (obs2.valueInt ?? 180);

        entries.add({'rounds': roundsValue, 'round-duration': durationValue});
      }
    }
    return entries;
  }

  /// Group duration + extra-weight pairs for isometric/hold exercises
  static List<Map<String, dynamic>> _groupDrillObservations(
    List<dynamic> observations,
  ) {
    final entries = <Map<String, dynamic>>[];
    for (int i = 0; i < observations.length; i += 2) {
      if (i + 1 < observations.length) {
        final obs1 = observations[i];
        final obs2 = observations[i + 1];

        // Explicitly check metricIds to avoid position-based assumptions
        final durationValue = obs1.metricId == 'metric-duration'
            ? (obs1.valueInt ?? 0)
            : (obs2.valueInt ?? 0);
        final extraWeightValue = obs1.metricId == 'metric-extra-weight'
            ? (obs1.valueReal ?? 0.0)
            : (obs2.valueReal ?? 0.0);

        entries.add({
          'duration': durationValue,
          'extra-weight': extraWeightValue,
        });
      }
    }
    return entries;
  }
}
