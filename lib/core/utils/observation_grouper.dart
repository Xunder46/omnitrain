/// Utility for grouping observations into entries by effort kind
/// Handles the mapping between raw observations and UI-ready entry maps
class ObservationGrouper {
  /// Group observations into entries based on effort kind
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
        return _groupRoundObservations(observations);
      case 'drill':
        return _groupDrillObservations(observations);
      default:
        return _groupSetObservations(observations); // Fallback
    }
  }

  /// Group reps + weight pairs for set-based exercises
  static List<Map<String, dynamic>> _groupSetObservations(
    List<dynamic> observations,
  ) {
    final entries = <Map<String, dynamic>>[];
    for (int i = 0; i < observations.length; i += 2) {
      if (i + 1 < observations.length) {
        final repsObs = observations[i];
        final weightObs = observations[i + 1];
        entries.add({
          'reps': repsObs.valueInt ?? 0,
          'weight': weightObs.valueReal ?? 0.0,
        });
      }
    }
    return entries;
  }

  /// Group duration + distance pairs for timed/cardio exercises
  static List<Map<String, dynamic>> _groupTimedObservations(
    List<dynamic> observations,
  ) {
    final entries = <Map<String, dynamic>>[];
    for (int i = 0; i < observations.length; i += 2) {
      if (i + 1 < observations.length) {
        final durationObs = observations[i];
        final distanceObs = observations[i + 1];
        entries.add({
          'duration': durationObs.valueInt ?? 0,
          'distance': distanceObs.valueReal ?? 0.0,
        });
      }
    }
    return entries;
  }

  /// Group rounds + round-duration pairs for round-based exercises
  static List<Map<String, dynamic>> _groupRoundObservations(
    List<dynamic> observations,
  ) {
    final entries = <Map<String, dynamic>>[];
    for (int i = 0; i < observations.length; i += 2) {
      if (i + 1 < observations.length) {
        final roundsObs = observations[i];
        final durationObs = observations[i + 1];
        entries.add({
          'rounds': roundsObs.valueInt ?? 1,
          'round-duration': durationObs.valueInt ?? 180,
        });
      }
    }
    return entries;
  }

  /// Group duration + rpe pairs for isometric/hold exercises
  static List<Map<String, dynamic>> _groupDrillObservations(
    List<dynamic> observations,
  ) {
    final entries = <Map<String, dynamic>>[];
    for (int i = 0; i < observations.length; i += 2) {
      if (i + 1 < observations.length) {
        final durationObs = observations[i];
        final rpeObs = observations[i + 1];
        entries.add({
          'duration': durationObs.valueInt ?? 0,
          'rpe': rpeObs.valueInt ?? 5,
        });
      }
    }
    return entries;
  }
}
