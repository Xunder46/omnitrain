import '../models/models.dart';
import '../../mock/seed_data.dart';
import 'workout_repository.dart';

/// In-memory mock implementation of WorkoutRepository for development/testing.
/// Uses in-memory data and loads from mock/seed_data.dart.
/// Web-compatible (no SQLite / platform APIs).
class MockWorkoutRepository implements WorkoutRepository {
  final Map<String, Exercise> _exercises = {};
  final Map<String, TrainingSession> _sessions = {};
  final Map<String, SessionSegment> _segments = {};
  final Map<String, SegmentEffort> _efforts = {};
  final Map<String, EffortObservation> _observations = {};
  final Map<String, UnitModel> _units = {};
  final Map<String, MetricDefinition> _metrics = {};

  bool _initialized = false;

  /// Initializes the repository with seed data from mock/seed_data.dart
  Future<void> initialize() async {
    if (_initialized) return;

    // Load seed exercises
    for (final exercise in SeedData.sampleExercises) {
      _exercises[exercise.id] = exercise;
    }

    // Load seed units
    for (final unit in SeedData.defaultUnits) {
      _units[unit.id] = unit;
    }

    // Load seed metrics
    for (final metric in SeedData.defaultMetrics) {
      _metrics[metric.id] = metric;
    }

    _initialized = true;
  }

  /// Gets default units
  Future<List<UnitModel>> getUnits() async {
    return _units.values.toList();
  }

  /// Gets default metrics
  Future<List<MetricDefinition>> getMetrics() async {
    return _metrics.values.toList();
  }

  @override
  Future<List<Exercise>> getExercises() async {
    return _exercises.values.where((e) => !e.isArchived).toList();
  }

  @override
  Future<Exercise?> getExerciseById(String id) async {
    return _exercises[id];
  }

  @override
  Future<String> createExercise(Exercise exercise) async {
    _exercises[exercise.id] = exercise;
    return exercise.id;
  }

  @override
  Future<void> updateExercise(Exercise exercise) async {
    _exercises[exercise.id] = exercise;
  }

  @override
  Future<void> deleteExercise(String id) async {
    _exercises.remove(id);
  }

  @override
  Future<TrainingSession?> getSession(String id) async {
    return _sessions[id];
  }

  @override
  Future<String> createSession(TrainingSession session) async {
    _sessions[session.id] = session;
    return session.id;
  }

  @override
  Future<void> updateSession(TrainingSession session) async {
    _sessions[session.id] = session;
  }

  @override
  Future<List<SessionSegment>> getSessionSegments(String sessionId) async {
    return _segments.values
        .where((s) => s.sessionId == sessionId)
        .toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
  }

  @override
  Future<String> createSegment(SessionSegment segment) async {
    _segments[segment.id] = segment;
    return segment.id;
  }

  @override
  Future<List<SegmentEffort>> getSegmentEfforts(String segmentId) async {
    return _efforts.values
        .where((e) => e.segmentId == segmentId)
        .toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
  }

  @override
  Future<String> createEffort(SegmentEffort effort) async {
    _efforts[effort.id] = effort;
    return effort.id;
  }

  @override
  Future<List<EffortObservation>> getEffortObservations(String effortId) async {
    return _observations.values
        .where((o) => o.effortId == effortId)
        .toList()
      ..sort((a, b) => a.createdAtMs.compareTo(b.createdAtMs));
  }

  @override
  Future<String> createObservation(EffortObservation observation) async {
    _observations[observation.id] = observation;
    return observation.id;
  }

  @override
  Future<void> updateObservation(EffortObservation observation) async {
    _observations[observation.id] = observation;
  }

  /// Clears all data (useful for testing)
  void clear() {
    _exercises.clear();
    _sessions.clear();
    _segments.clear();
    _efforts.clear();
    _observations.clear();
    _units.clear();
    _metrics.clear();
    _initialized = false;
  }

  /// Resets to seed data only
  Future<void> reset() async {
    clear();
    await initialize();
  }
}
