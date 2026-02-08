import 'package:flutter/foundation.dart';
import '../../data/models/models.dart';
import '../../data/repositories/workout_repository.dart';
import '../../core/constants/modality_config.dart';
import '../../core/constants/metric_ids.dart';
import '../../core/utils/observation_grouper.dart';

/// State holder for workout session data.
/// Uses ChangeNotifier pattern and talks ONLY to repositories.
/// No UI widgets or direct storage access here.
class WorkoutState extends ChangeNotifier {
  final WorkoutRepository _repository;

  WorkoutState(this._repository);

  // Current session state
  TrainingSession? _currentSession;
  ModalityConfig? _currentModalityConfig;
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
  ModalityConfig? get modalityConfig => _currentModalityConfig;
  List<SessionSegment> get segments => List.unmodifiable(_segments);
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasSession => _currentSession != null;
  bool get hasActiveSession => _currentSession != null && _efforts.values.any((list) => list.isNotEmpty);
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
  /// [modality] - Optional training modality (e.g., 'cardio_endurance', 'resistance_lifting').
  ///              If null, creates a 'Free Training' session with no modality preset.
  Future<void> createNewSession({String? modality}) async {
    _setLoading(true);
    _clearError();

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final sessionId = 'session-${now}';

      final session = TrainingSession(
        id: sessionId,
        ownerUserId: 'user-1',
        startedAtMs: now,
        modality: modality,
        createdAtMs: now,
        updatedAtMs: now,
      );

      await _repository.createSession(session);
      _currentSession = session;
      _currentModalityConfig = ModalityConfig.forModality(modality);

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
  /// [exercise] - The exercise from the library to add
  /// [chosenMetric] - Optional metric chosen by user (for Free Training only)
  Future<String> addExerciseToSession(Exercise exercise, {String? chosenMetric}) async {
    if (_segments.isEmpty) return '';

    _clearError();

    try {
      final segment = _segments.first;
      final now = DateTime.now().millisecondsSinceEpoch;

      // Determine effort kind from modality or chosen metric
      String effortKind;
      if (_currentModalityConfig != null && _currentSession?.modality != null) {
        // Use modality config
        effortKind = _currentModalityConfig!.effortKind;
      } else if (chosenMetric != null) {
        // Free Training - derive from chosen metric
        effortKind = ModalityConfig.effortKindFromMetric(chosenMetric);
      } else {
        // Fallback to set-based
        effortKind = 'set';
      }

      // Cache the exercise
      _exerciseCache[exercise.id] = exercise;

      // Create effort
      final effortId = 'effort-${now}';
      final currentEfforts = _efforts[segment.id] ?? [];
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

      // Add initial entry based on effort kind
      await addEntry(effortId);

      notifyListeners();
      return effortId;
    } catch (e) {
      _setError('Failed to add exercise: $e');
      return '';
    }
  }

  /// Add an entry (set/round/hold/etc.) to an effort
  /// Creates appropriate observations based on effort kind
  Future<void> addEntry(String effortId) async {
    _clearError();

    try {
      // Find the effort to get its kind
      SegmentEffort? effort;
      for (final effortList in _efforts.values) {
        effort = effortList.firstWhere((e) => e.id == effortId, orElse: () => effortList.first);
        if (effort.id == effortId) break;
      }
      if (effort == null) {
        _setError('Effort not found');
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final entryIndex = (_observations[effortId]?.length ?? 0) ~/ 2; // Rough index for grouping

      final observations = <EffortObservation>[];

      // Create observations based on effort kind
      switch (effort.effortKind) {
        case 'set': // Resistance training
          observations.add(EffortObservation(
            id: 'obs-$effortId-$entryIndex-reps',
            effortId: effortId,
            metricId: MetricIds.reps,
            unitId: MetricIds.unitReps,
            valueInt: 10,
            createdAtMs: now,
            updatedAtMs: now,
          ));
          observations.add(EffortObservation(
            id: 'obs-$effortId-$entryIndex-weight',
            effortId: effortId,
            metricId: MetricIds.weight,
            unitId: MetricIds.unitKg,
            valueReal: 0.0,
            createdAtMs: now,
            updatedAtMs: now,
          ));
          break;

        case 'timed': // Cardio/endurance
          observations.add(EffortObservation(
            id: 'obs-$effortId-$entryIndex-duration',
            effortId: effortId,
            metricId: MetricIds.duration,
            unitId: MetricIds.unitSeconds,
            valueInt: 0,
            createdAtMs: now,
            updatedAtMs: now,
          ));
          // Optional distance
          observations.add(EffortObservation(
            id: 'obs-$effortId-$entryIndex-distance',
            effortId: effortId,
            metricId: MetricIds.distance,
            unitId: MetricIds.unitMeters,
            valueReal: 0.0,
            createdAtMs: now,
            updatedAtMs: now,
          ));
          break;

        case 'round': // Martial arts / Sports
          observations.add(EffortObservation(
            id: 'obs-$effortId-$entryIndex-rounds',
            effortId: effortId,
            metricId: MetricIds.rounds,
            unitId: MetricIds.unitRounds,
            valueInt: 1,
            createdAtMs: now,
            updatedAtMs: now,
          ));
          observations.add(EffortObservation(
            id: 'obs-$effortId-$entryIndex-round-duration',
            effortId: effortId,
            metricId: MetricIds.roundDuration,
            unitId: MetricIds.unitSeconds,
            valueInt: 180, // 3 minutes default
            createdAtMs: now,
            updatedAtMs: now,
          ));
          break;

        case 'drill': // Isometric / holds
          observations.add(EffortObservation(
            id: 'obs-$effortId-$entryIndex-duration',
            effortId: effortId,
            metricId: MetricIds.duration,
            unitId: MetricIds.unitSeconds,
            valueInt: 0, // Hold time
            createdAtMs: now,
            updatedAtMs: now,
          ));
          // Optional RPE
          observations.add(EffortObservation(
            id: 'obs-$effortId-$entryIndex-rpe',
            effortId: effortId,
            metricId: MetricIds.rpe,
            valueInt: 5,
            createdAtMs: now,
            updatedAtMs: now,
          ));
          break;

        default:
          // Fallback to set-based
          observations.add(EffortObservation(
            id: 'obs-$effortId-$entryIndex-reps',
            effortId: effortId,
            metricId: MetricIds.reps,
            unitId: MetricIds.unitReps,
            valueInt: 10,
            createdAtMs: now,
            updatedAtMs: now,
          ));
      }

      // Save all observations
      for (final obs in observations) {
        await _repository.createObservation(obs);
      }

      _observations.putIfAbsent(effortId, () => []).addAll(observations);

      notifyListeners();
    } catch (e) {
      _setError('Failed to add entry: $e');
    }
  }

  /// Update an entry value for any metric
  Future<void> updateEntryValue(String effortId, String metricKey, dynamic value) async {
    final observations = _observations[effortId];
    if (observations == null) return;

    _clearError();

    try {
      // Map metric keys to metric IDs
      final metricIdMap = {
        'reps': 'metric-reps',
        'weight': 'metric-weight',
        'duration': 'metric-duration',
        'distance': 'metric-distance',
        'rounds': 'metric-rounds',
        'round-duration': 'metric-round-duration',
        'rpe': 'metric-rpe',
      };

      final metricId = metricIdMap[metricKey];
      if (metricId == null) return;

      final obsIndex = observations.indexWhere((o) => o.metricId == metricId);

      if (obsIndex != -1) {
        final oldObs = observations[obsIndex];
        final newObs = EffortObservation(
          id: oldObs.id,
          effortId: oldObs.effortId,
          metricId: oldObs.metricId,
          unitId: oldObs.unitId,
          valueInt: (value is int) ? value : oldObs.valueInt,
          valueReal: (value is double) ? value : oldObs.valueReal,
          valueText: (value is String) ? value : oldObs.valueText,
          valueBool: (value is bool) ? value : oldObs.valueBool,
          createdAtMs: oldObs.createdAtMs,
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        );

        await _repository.updateObservation(newObs);
        observations[obsIndex] = newObs;

        notifyListeners();
      }
    } catch (e) {
      _setError('Failed to update entry: $e');
    }
  }

  /// Get exercises with their entries for display (modality-aware)
  List<Map<String, dynamic>> getExercisesWithEntries() {
    final result = <Map<String, dynamic>>[];

    for (final segment in _segments) {
      final segmentEfforts = _efforts[segment.id] ?? [];

      for (final effort in segmentEfforts) {
        final exercise = _exerciseCache[effort.exerciseId];
        final exerciseName = exercise?.name ?? 'Unknown Exercise';
        final effortObservations = _observations[effort.id] ?? [];

        // Group observations by entry type based on effort kind
        final entries = ObservationGrouper.groupByEffortKind(
          effort.effortKind,
          effortObservations,
        );

        result.add({
          'id': effort.id,
          'name': exerciseName,
          'effortKind': effort.effortKind,
          'entries': entries,
        });
      }
    }

    return result;
  }

  /// Clear session data
  void clearSession() {
    _currentSession = null;
    _currentModalityConfig = null;
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

  /// Get exercises ranked by modality compatibility
  /// Pass modality explicitly rather than relying on currentSession
  Future<List<Exercise>> getExercisesRankedForModality({
    String? modality,
    String? searchText,
    String? disciplineId,
    List<String>? muscleGroupIds,
  }) async {
    try {
      // Use the provided modality, or fall back to current session's modality
      final modalityToUse = modality ?? _currentSession?.modality;
      return await _repository.getExercisesRankedForModality(
        modalityToUse,
        searchText: searchText,
        disciplineId: disciplineId,
        muscleGroupIds: muscleGroupIds,
      );
    } catch (e) {
      _setError('Failed to get ranked exercises: $e');
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
