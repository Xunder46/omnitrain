import 'models.dart';

class WorkoutSessionService {
  TrainingSession? _currentSession;
  final List<SessionSegment> _segments = [];
  final Map<String, List<SegmentEffort>> _efforts = {};
  final Map<String, List<EffortObservation>> _observations = {};
  final Map<String, String> _exerciseNames = {};

  TrainingSession? get currentSession => _currentSession;
  List<SessionSegment> get segments => _segments;
  Map<String, List<SegmentEffort>> get efforts => _efforts;
  Map<String, List<EffortObservation>> get observations => _observations;

  Future<void> initialize() async {
    // Skip database initialization for now
  }

  Future<void> createNewSession() async {
    // Create mock session
    final now = DateTime.now().millisecondsSinceEpoch;
    final sessionId = 'mock-session-1';
    _currentSession = TrainingSession(
      id: sessionId,
      ownerUserId: 'user-1',
      startedAtMs: now,
      createdAtMs: now,
      updatedAtMs: now,
    );
    _createDefaultSegment();
  }

  void _createDefaultSegment() {
    if (_currentSession == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final segmentId = 'mock-segment-1';

    final segment = SessionSegment(
      id: segmentId,
      sessionId: _currentSession!.id,
      orderIndex: 0,
      segmentType: 'workout',
      name: 'Main Workout',
      createdAtMs: now,
      updatedAtMs: now,
    );

    _segments.add(segment);
  }

  Future<String> addExercise(String exerciseName) async {
    if (_segments.isEmpty) return '';

    final segment = _segments.first;
    final now = DateTime.now().millisecondsSinceEpoch;
    final effortId = 'mock-effort-${_efforts[segment.id]?.length ?? 0}';

    // Use the exercise name as the ID for simplicity
    final exerciseId = exerciseName;
    _exerciseNames[exerciseId] = exerciseName;

    final effort = SegmentEffort(
      id: effortId,
      segmentId: segment.id,
      orderIndex: _efforts[segment.id]?.length ?? 0,
      effortKind: 'strength',
      exerciseId: exerciseId,
      createdAtMs: now,
      updatedAtMs: now,
    );

    _efforts.putIfAbsent(segment.id, () => []).add(effort);

    // Add an initial empty set
    await addSet(effortId);

    return effortId;
  }

  Future<void> addSet(String effortId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final setIndex = _observations[effortId]?.length ?? 0;
    final observationId = 'mock-obs-$effortId-$setIndex';

    // Add reps observation
    final repsObs = EffortObservation(
      id: '$observationId-reps',
      effortId: effortId,
      metricId: 'metric-reps',
      unitId: 'unit-reps',
      valueInt: 10, // Default reps
      createdAtMs: now,
      updatedAtMs: now,
    );

    // Add weight observation
    final weightObs = EffortObservation(
      id: '$observationId-weight',
      effortId: effortId,
      metricId: 'metric-weight',
      unitId: 'unit-kg',
      valueReal: 0.0, // Default weight
      createdAtMs: now,
      updatedAtMs: now,
    );

    _observations.putIfAbsent(effortId, () => []).addAll([repsObs, weightObs]);
  }

  Future<void> updateSetValue(String effortId, String metricKey, dynamic value) async {
    final observations = _observations[effortId];
    if (observations == null) return;

    final metricId = metricKey == 'reps' ? 'metric-reps' : 'metric-weight';
    final obsIndex = observations.indexWhere((o) => o.metricId == metricId);

    if (obsIndex != -1) {
      final oldObs = observations[obsIndex];
      final newObs = EffortObservation(
        id: oldObs.id,
        effortId: oldObs.effortId,
        metricId: oldObs.metricId,
        unitId: oldObs.unitId,
        valueInt: metricKey == 'reps' ? value as int : oldObs.valueInt,
        valueReal: metricKey == 'weight' ? value as double : oldObs.valueReal,
        valueText: oldObs.valueText,
        valueBool: oldObs.valueBool,
        createdAtMs: oldObs.createdAtMs,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      observations[obsIndex] = newObs;
    }
  }

  Future<void> loadSessionData() async {
    // Mock data loading
    if (_currentSession == null) {
      await createNewSession();
    }
  }

  List<Map<String, dynamic>> getExercisesWithSets() {
    final result = <Map<String, dynamic>>[];

    for (final segment in _segments) {
      final segmentEfforts = _efforts[segment.id] ?? [];

      for (final effort in segmentEfforts) {
        final exerciseName = _exerciseNames[effort.exerciseId] ?? 'Unknown Exercise';
        final effortObservations = _observations[effort.id] ?? [];

        // Group observations by set (they're created in pairs)
        final sets = <Map<String, dynamic>>[];
        for (int i = 0; i < effortObservations.length; i += 2) {
          if (i + 1 < effortObservations.length) {
            final repsObs = effortObservations[i];
            final weightObs = effortObservations[i + 1];

            sets.add({
              'reps': repsObs.valueInt ?? 0,
              'weight': weightObs.valueReal ?? 0.0,
            });
          }
        }

        result.add({
          'id': effort.id,
          'name': exerciseName,
          'sets': sets,
        });
      }
    }

    return result;
  }
}