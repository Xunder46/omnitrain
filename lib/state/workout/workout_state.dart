import 'package:flutter/foundation.dart';
import '../../data/models/models.dart';
import '../../data/repositories/workout_repository.dart';

/// State holder for workout session data.
/// Uses ChangeNotifier pattern and talks ONLY to repositories.
/// No UI widgets or direct storage access here.
class WorkoutState extends ChangeNotifier {
  final WorkoutRepository _repository;

  WorkoutState(this._repository);

  // Current session state
  TrainingSession? _currentSession;
  final List<SessionSegment> _segments = [];
  final Map<String, List<SegmentEffort>> _efforts = {};
  final Map<String, List<EffortObservation>> _observations = {};
  final Map<String, Exercise> _exerciseCache = {};

  // Exercise library data
  List<Exercise> _allExercises = [];
  List<MuscleGroup> _muscleGroups = [];
  List<Discipline> _disciplines = [];

  bool _isLoading = false;
  String? _error;

  // Getters
  TrainingSession? get currentSession => _currentSession;
  List<SessionSegment> get segments => List.unmodifiable(_segments);
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasSession => _currentSession != null;
  List<Exercise> get allExercises => List.unmodifiable(_allExercises);
  List<MuscleGroup> get muscleGroups => List.unmodifiable(_muscleGroups);
  List<Discipline> get disciplines => List.unmodifiable(_disciplines);

  /// Get efforts for a segment
  List<SegmentEffort> getEffortsForSegment(String segmentId) {
    return List.unmodifiable(_efforts[segmentId] ?? []);
  }

  /// Get observations for an effort
  List<EffortObservation> getObservationsForEffort(String effortId) {
    return List.unmodifiable(_observations[effortId] ?? []);
  }

  /// Get exercise by ID (cached)
  Exercise? getExercise(String? exerciseId) {
    if (exerciseId == null) return null;
    return _exerciseCache[exerciseId];
  }

  /// Create a new workout session
  Future<void> createNewSession() async {
    _setLoading(true);
    _clearError();

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final sessionId = 'session-${now}';

      final session = TrainingSession(
        id: sessionId,
        ownerUserId: 'user-1',
        startedAtMs: now,
        createdAtMs: now,
        updatedAtMs: now,
      );

      await _repository.createSession(session);
      _currentSession = session;

      // Create default segment
      final segmentId = 'segment-${now}';
      final segment = SessionSegment(
        id: segmentId,
        sessionId: sessionId,
        orderIndex: 0,
        segmentType: 'workout',
        name: 'Main Workout',
        createdAtMs: now,
        updatedAtMs: now,
      );

      await _repository.createSegment(segment);
      _segments.add(segment);

      notifyListeners();
    } catch (e) {
      _setError('Failed to create session: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Load session data from repository
  Future<void> loadSessionData() async {
    if (_currentSession == null) {
      await createNewSession();
      return;
    }

    _setLoading(true);
    _clearError();

    try {
      // Load segments
      final segments = await _repository.getSessionSegments(_currentSession!.id);
      _segments.clear();
      _segments.addAll(segments);

      // Load efforts for each segment
      for (final segment in _segments) {
        final efforts = await _repository.getSegmentEfforts(segment.id);
        _efforts[segment.id] = efforts;

        // Load observations for each effort
        for (final effort in efforts) {
          final observations = await _repository.getEffortObservations(effort.id);
          _observations[effort.id] = observations;

          // Cache exercise if present
          if (effort.exerciseId != null && !_exerciseCache.containsKey(effort.exerciseId)) {
            final exercise = await _repository.getExerciseById(effort.exerciseId!);
            if (exercise != null) {
              _exerciseCache[effort.exerciseId!] = exercise;
            }
          }
        }
      }

      notifyListeners();
    } catch (e) {
      _setError('Failed to load session data: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Add an exercise to the current session
  Future<String> addExercise(String exerciseName) async {
    if (_segments.isEmpty) return '';

    _clearError();

    try {
      final segment = _segments.first;
      final now = DateTime.now().millisecondsSinceEpoch;

      // Create or get exercise
      final exerciseId = 'exercise-${now}';
      final exercise = Exercise(
        id: exerciseId,
        name: exerciseName,
        createdAtMs: now,
        updatedAtMs: now,
      );

      await _repository.createExercise(exercise);
      _exerciseCache[exerciseId] = exercise;

      // Create effort
      final effortId = 'effort-${now}';
      final currentEfforts = _efforts[segment.id] ?? [];
      final effort = SegmentEffort(
        id: effortId,
        segmentId: segment.id,
        orderIndex: currentEfforts.length,
        effortKind: 'strength',
        exerciseId: exerciseId,
        createdAtMs: now,
        updatedAtMs: now,
      );

      await _repository.createEffort(effort);
      _efforts.putIfAbsent(segment.id, () => []).add(effort);

      // Add initial set
      await addSet(effortId);

      notifyListeners();
      return effortId;
    } catch (e) {
      _setError('Failed to add exercise: $e');
      return '';
    }
  }

  /// Add a set to an effort
  Future<void> addSet(String effortId) async {
    _clearError();

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final setIndex = _observations[effortId]?.length ?? 0;

      // Add reps observation
      final repsObs = EffortObservation(
        id: 'obs-$effortId-$setIndex-reps',
        effortId: effortId,
        metricId: 'metric-reps',
        unitId: 'unit-reps',
        valueInt: 10,
        createdAtMs: now,
        updatedAtMs: now,
      );

      // Add weight observation
      final weightObs = EffortObservation(
        id: 'obs-$effortId-$setIndex-weight',
        effortId: effortId,
        metricId: 'metric-weight',
        unitId: 'unit-kg',
        valueReal: 0.0,
        createdAtMs: now,
        updatedAtMs: now,
      );

      await _repository.createObservation(repsObs);
      await _repository.createObservation(weightObs);

      _observations.putIfAbsent(effortId, () => []).addAll([repsObs, weightObs]);

      notifyListeners();
    } catch (e) {
      _setError('Failed to add set: $e');
    }
  }

  /// Update a set value
  Future<void> updateSetValue(String effortId, String metricKey, dynamic value) async {
    final observations = _observations[effortId];
    if (observations == null) return;

    _clearError();

    try {
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

        await _repository.updateObservation(newObs);
        observations[obsIndex] = newObs;

        notifyListeners();
      }
    } catch (e) {
      _setError('Failed to update set: $e');
    }
  }

  /// Get exercises with their sets for display
  List<Map<String, dynamic>> getExercisesWithSets() {
    final result = <Map<String, dynamic>>[];

    for (final segment in _segments) {
      final segmentEfforts = _efforts[segment.id] ?? [];

      for (final effort in segmentEfforts) {
        final exercise = _exerciseCache[effort.exerciseId];
        final exerciseName = exercise?.name ?? 'Unknown Exercise';
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

  /// Clear session data
  void clearSession() {
    _currentSession = null;
    _segments.clear();
    _efforts.clear();
    _observations.clear();
    _exerciseCache.clear();
    _clearError();
    notifyListeners();
  }

  /// Load all exercises from repository
  Future<void> loadAllExercises() async {
    try {
      _allExercises = await _repository.getExercises();
      notifyListeners();
    } catch (e) {
      _setError('Failed to load exercises: $e');
    }
  }

  /// Load muscle groups from repository
  Future<void> loadMuscleGroups() async {
    try {
      _muscleGroups = await _repository.getMuscleGroups();
      notifyListeners();
    } catch (e) {
      _setError('Failed to load muscle groups: $e');
    }
  }

  /// Load disciplines from repository
  Future<void> loadDisciplines() async {
    try {
      _disciplines = await _repository.getDisciplines();
      notifyListeners();
    } catch (e) {
      _setError('Failed to load disciplines: $e');
    }
  }

  /// Search exercises with filters
  Future<List<Exercise>> searchExercises({
    String? searchText,
    String? disciplineId,
    List<String>? muscleGroupIds,
  }) async {
    try {
      return await _repository.searchExercises(
        searchText: searchText,
        disciplineId: disciplineId,
        muscleGroupIds: muscleGroupIds,
      );
    } catch (e) {
      _setError('Failed to search exercises: $e');
      return [];
    }
  }

  /// Get muscle groups for a specific exercise
  Future<List<MuscleGroup>> getExerciseMuscleGroups(String exerciseId) async {
    try {
      return await _repository.getExerciseMuscleGroups(exerciseId);
    } catch (e) {
      _setError('Failed to load exercise muscle groups: $e');
      return [];
    }
  }

  // Private helpers
  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setError(String message) {
    _error = message;
    notifyListeners();
  }

  void _clearError() {
    _error = null;
  }
}
