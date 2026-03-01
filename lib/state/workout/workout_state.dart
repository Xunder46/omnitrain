import 'package:flutter/foundation.dart';
import '../../data/models/models.dart';
import '../../data/repositories/workout_repository.dart';
import '../../core/constants/modality_config.dart';
import '../../core/constants/metric_ids.dart';
import '../../core/models/routine_session_manifest.dart';
import '../../core/models/session_summary.dart';
import '../../core/constants/effort_defaults.dart';
import '../../core/utils/observation_grouper.dart';
import '../../core/utils/exercise_helpers.dart';

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
  bool get hasActiveSession =>
      _currentSession != null &&
      _currentSession!.endedAtMs == null &&
      _efforts.values.any((list) => list.isNotEmpty);
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
  /// [title] - Optional session title (used for routine sessions).
  /// [intent] - Optional session intent (e.g., 'routine').
  /// [routineTemplateId] - Optional routine template reference for lineage.
  Future<void> createNewSession({
    String? modality,
    String? title,
    String? intent,
    String? routineTemplateId,
    bool includeDefaultSegment = true,
  }) async {
    _setLoading(true);
    _clearError();

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final sessionId = 'session-$now';

      final session = TrainingSession(
        id: sessionId,
        ownerUserId: 'user-1',
        routineTemplateId: routineTemplateId,
        startedAtMs: now,
        title: title,
        modality: modality,
        intent: intent,
        createdAtMs: now,
        updatedAtMs: now,
      );

      await _repository.createSession(session);
      _currentSession = session;
      _currentModalityConfig = ModalityConfig.forModality(modality);

      if (includeDefaultSegment) {
        // Create default segment
        final segmentId = 'segment-$now';
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
      }

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
      final segments = await _repository.getSessionSegments(
        _currentSession!.id,
      );
      _segments.clear();
      _segments.addAll(segments);

      // Load efforts for each segment
      for (final segment in _segments) {
        final efforts = await _repository.getSegmentEfforts(segment.id);
        _efforts[segment.id] = efforts;

        // Load observations for each effort
        for (final effort in efforts) {
          final observations = await _repository.getEffortObservations(
            effort.id,
          );
          _observations[effort.id] = observations;

          // Cache exercise if present
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

      notifyListeners();
    } catch (e) {
      _setError('Failed to load session data: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Populate the current session from a routine session manifest
  /// This method consumes a RoutineSessionManifest (returned by RoutineSessionService)
  /// and populates the current session with all exercises, targets, and rest timers.
  ///
  /// Prerequisites: Must have an active session (call createNewSession first).
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

        for (final entry in segmentEntry.exercises) {
          final exercise = entry.exercise;
          final effortKind = entry.effortKind;
          final setCount = entry.setCount;
          final targets = entry.targets;

          final effortId = await addExerciseToSession(
            exercise,
            effortKindOverride: effortKind,
            segmentId: segmentId,
          );

          if (effortId.isEmpty) continue;

          // Add additional entries (sets) beyond the first
          for (int i = 1; i < setCount; i++) {
            await addEntry(effortId);
          }

          // Apply targets from template
          for (final target in targets) {
            final entryIndex = target.setIndex ?? 0;
            final metricKey =
                MetricIds.metricIdToKey[target.metricId] ?? target.metricId;

            // Get value from target
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

            // Convert to appropriate type
            if (metricKey == 'reps' ||
                metricKey == 'rounds' ||
                metricKey == 'duration') {
              value = value is int ? value : (value as double).toInt();
            } else {
              value = value is double ? value : (value as int).toDouble();
            }

            try {
              await updateEntryValue(effortId, entryIndex, metricKey, value);
            } catch (e) {
              // Silently skip if metric doesn't exist for this effort
            }
          }
        }
      }

      notifyListeners();
    } catch (e) {
      _setError('Failed to populate session from manifest: $e');
      rethrow;
    }
  }

  /// Add an exercise to the current session
  /// [exercise] - The exercise from the library to add
  /// [chosenMetric] - Optional metric chosen by user (for Free Training only)
  /// [effortKindOverride] - Optional explicit effort kind (used for routines)
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

      // Determine effort kind from override, modality, or chosen metric
      String effortKind;
      if (effortKindOverride != null) {
        effortKind = effortKindOverride;
      } else if (_currentModalityConfig != null &&
          _currentSession?.modality != null) {
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
      final effortId = 'effort-$now';
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
  /// [previousValues] - Optional map of metric values to pre-fill from previous entry
  Future<void> addEntry(
    String effortId, {
    Map<String, dynamic>? previousValues,
  }) async {
    _clearError();

    try {
      // Find the effort to get its kind
      SegmentEffort? effort;
      for (final effortList in _efforts.values) {
        effort = effortList.firstWhere(
          (e) => e.id == effortId,
          orElse: () => effortList.first,
        );
        if (effort.id == effortId) break;
      }
      if (effort == null) {
        _setError('Effort not found');
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final entryIndex =
          (_observations[effortId]?.length ?? 0) ~/
          2; // Rough index for grouping

      final observations = <EffortObservation>[];

      // Create observations based on effort kind
      switch (effort.effortKind) {
        case 'set': // Resistance training
          observations.add(
            EffortObservation(
              id: 'obs-$effortId-$entryIndex-reps',
              effortId: effortId,
              metricId: MetricIds.reps,
              unitId: MetricIds.unitReps,
              valueInt: (previousValues?['reps'] as int?) ?? 10,
              createdAtMs: now,
              updatedAtMs: now,
            ),
          );
          observations.add(
            EffortObservation(
              id: 'obs-$effortId-$entryIndex-weight',
              effortId: effortId,
              metricId: MetricIds.weight,
              unitId: MetricIds.unitKg,
              valueReal: (previousValues?['weight'] as double?) ?? 0.0,
              createdAtMs: now,
              updatedAtMs: now,
            ),
          );
          break;

        case 'timed': // Cardio/endurance
          observations.add(
            EffortObservation(
              id: 'obs-$effortId-$entryIndex-duration',
              effortId: effortId,
              metricId: MetricIds.duration,
              unitId: MetricIds.unitSeconds,
              valueInt: (previousValues?['duration'] as int?) ?? 0,
              createdAtMs: now,
              updatedAtMs: now,
            ),
          );
          // Optional distance
          observations.add(
            EffortObservation(
              id: 'obs-$effortId-$entryIndex-distance',
              effortId: effortId,
              metricId: MetricIds.distance,
              unitId: MetricIds.unitMeters,
              valueReal: (previousValues?['distance'] as double?) ?? 0.0,
              createdAtMs: now,
              updatedAtMs: now,
            ),
          );
          break;

        case 'round': // Martial arts / Sports
          observations.add(
            EffortObservation(
              id: 'obs-$effortId-$entryIndex-rounds',
              effortId: effortId,
              metricId: MetricIds.rounds,
              unitId: MetricIds.unitRounds,
              valueInt: (previousValues?['rounds'] as int?) ?? 1,
              createdAtMs: now,
              updatedAtMs: now,
            ),
          );
          observations.add(
            EffortObservation(
              id: 'obs-$effortId-$entryIndex-round-duration',
              effortId: effortId,
              metricId: MetricIds.roundDuration,
              unitId: MetricIds.unitSeconds,
              valueInt: (previousValues?['round-duration'] as int?) ?? 180,
              createdAtMs: now,
              updatedAtMs: now,
            ),
          );
          break;

        case 'drill': // Isometric / holds
          observations.add(
            EffortObservation(
              id: 'obs-$effortId-$entryIndex-duration',
              effortId: effortId,
              metricId: MetricIds.duration,
              unitId: MetricIds.unitSeconds,
              valueInt: (previousValues?['duration'] as int?) ?? 0,
              createdAtMs: now,
              updatedAtMs: now,
            ),
          );
          // Optional RPE
          observations.add(
            EffortObservation(
              id: 'obs-$effortId-$entryIndex-rpe',
              effortId: effortId,
              metricId: MetricIds.rpe,
              valueInt: (previousValues?['rpe'] as int?) ?? 5,
              createdAtMs: now,
              updatedAtMs: now,
            ),
          );
          break;

        default:
          // Fallback to set-based
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
  /// [effortId] - The effort containing the entry
  /// [entryIndex] - The 0-based index of the entry (set/round/hold number)
  /// [metricKey] - The metric to update ('reps', 'weight', 'duration', etc.)
  /// [value] - The new value to set
  Future<void> updateEntryValue(
    String effortId,
    int entryIndex,
    String metricKey,
    dynamic value,
  ) async {
    final observations = _observations[effortId];
    if (observations == null) return;

    _clearError();

    try {
      // Use centralized MetricIds.keyToMetricId mapping for consistency
      final metricId = MetricIds.keyToMetricId[metricKey];
      if (metricId == null) return;

      // Find the observation for this entry index and metric
      // Observations are grouped in pairs (e.g., reps+weight, duration+distance)
      // For entryIndex N, observations start at index N*2
      final matchingObservations = observations
          .asMap()
          .entries
          .where((entry) => entry.value.metricId == metricId)
          .toList();

      if (entryIndex < matchingObservations.length) {
        final obsIndex = matchingObservations[entryIndex].key;
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

  /// Delete a specific entry (set/round/hold) from an effort
  /// [effortId] - The effort containing the entry
  /// [entryIndex] - The 0-based index of the entry to delete
  Future<void> deleteEntry(String effortId, int entryIndex) async {
    final observations = _observations[effortId];
    if (observations == null) return;

    _clearError();

    try {
      // Find the effort to determine metrics per entry
      SegmentEffort? effort;
      for (final effortList in _efforts.values) {
        effort = effortList.firstWhere(
          (e) => e.id == effortId,
          orElse: () => SegmentEffort(
            id: '',
            segmentId: '',
            orderIndex: 0,
            effortKind: '',
            createdAtMs: 0,
            updatedAtMs: 0,
          ),
        );
        if (effort.id == effortId) break;
      }
      if (effort == null) return;

      // Get observations for this entry based on effort kind
      final metricsPerEntry = _getMetricsPerEntry(effort.effortKind);
      final startIndex = entryIndex * metricsPerEntry;
      final endIndex = startIndex + metricsPerEntry;

      if (startIndex >= observations.length) return;

      // Delete the observations in reverse order to maintain indices
      final obsToDelete = observations.sublist(
        startIndex,
        endIndex.clamp(0, observations.length),
      );

      for (final obs in obsToDelete) {
        await _repository.deleteObservation(obs.id);
      }

      // Remove from local cache
      observations.removeRange(
        startIndex,
        endIndex.clamp(0, observations.length),
      );

      notifyListeners();
    } catch (e) {
      _setError('Failed to delete entry: $e');
    }
  }

  /// Get the number of observations per entry for a given effort kind
  /// Used to calculate entry boundaries when deleting or updating entries
  int _getMetricsPerEntry(String effortKind) {
    switch (effortKind) {
      case 'set': // reps + weight
        return 2;
      case 'timed': // duration + distance
        return 2;
      case 'round': // rounds + round-duration
        return 2;
      case 'drill': // duration + rpe
        return 2;
      default:
        return 2; // Fallback
    }
  }

  /// Remove an exercise (effort) from the session
  /// [effortId] - The effort to remove
  Future<void> removeExerciseFromSession(String effortId) async {
    _clearError();

    try {
      // Delete the effort (this also deletes all its observations via repository)
      await _repository.deleteEffort(effortId);

      // Remove from local caches
      _observations.remove(effortId);
      for (final effortList in _efforts.values) {
        effortList.removeWhere((e) => e.id == effortId);
      }

      // Note: We don't remove from _exerciseCache as the exercise itself still exists
      // Only the effort (instance of exercise in this session) is removed

      notifyListeners();
    } catch (e) {
      _setError('Failed to remove exercise: $e');
    }
  }

  /// End the current session
  /// Sets the session end timestamp and persists to repository
  Future<void> endSession() async {
    if (_currentSession == null) return;

    _clearError();

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
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
        createdAtMs: _currentSession!.createdAtMs,
        updatedAtMs: now,
      );

      await _repository.updateSession(updatedSession);
      _currentSession = updatedSession;

      notifyListeners();
    } catch (e) {
      _setError('Failed to end session: $e');
    }
  }

  /// Update the current session note and persist immediately
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
        createdAtMs: _currentSession!.createdAtMs,
        updatedAtMs: now,
      );

      await _repository.updateSession(updatedSession);
      _currentSession = updatedSession;
      notifyListeners();
    } catch (e) {
      _setError('Failed to update session note: $e');
    }
  }

  /// Compute summary metrics from the current session state
  SessionSummary computeSessionSummary() {
    if (_currentSession == null) {
      throw Exception('No active session to summarize');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final endedAt = _currentSession!.endedAtMs ?? now;
    final durationMs = endedAt - _currentSession!.startedAtMs;

    double totalVolume = 0;
    int totalSets = 0;
    final exerciseSummaries = <ExerciseSummary>[];

    for (final segment in _segments) {
      final segmentEfforts = _efforts[segment.id] ?? [];

      for (final effort in segmentEfforts) {
        final exerciseId = effort.exerciseId ?? 'unknown';
        final exerciseName =
            _exerciseCache[exerciseId]?.name ?? 'Unknown Exercise';
        final observations = _observations[effort.id] ?? [];
        final grouped = _groupObservationsByEntry(observations);

        int setsCompleted = 0;
        double? bestWeight;

        if (effort.effortKind == 'set') {
          for (final entry in grouped.values) {
            final repsObs = entry.firstWhere(
              (o) => o.metricId == MetricIds.reps,
              orElse: () => EffortObservation(
                id: '',
                effortId: '',
                metricId: MetricIds.reps,
                createdAtMs: 0,
                updatedAtMs: 0,
              ),
            );
            final weightObs = entry.firstWhere(
              (o) => o.metricId == MetricIds.weight,
              orElse: () => EffortObservation(
                id: '',
                effortId: '',
                metricId: MetricIds.weight,
                createdAtMs: 0,
                updatedAtMs: 0,
              ),
            );

            final reps = repsObs.id.isEmpty
                ? null
                : (repsObs.valueInt ?? repsObs.valueReal?.toInt());
            final weight = weightObs.id.isEmpty
                ? null
                : (weightObs.valueReal ?? weightObs.valueInt?.toDouble());

            if (reps != null) {
              setsCompleted += 1;
            }

            if (reps != null && weight != null) {
              totalVolume += reps * weight;
            }

            if (weight != null) {
              if (bestWeight == null || weight > bestWeight) {
                bestWeight = weight;
              }
            }
          }

          totalSets += setsCompleted;
        } else {
          setsCompleted = grouped.length;
        }

        exerciseSummaries.add(
          ExerciseSummary(
            exerciseId: exerciseId,
            name: exerciseName,
            effortKind: effort.effortKind,
            setsCompleted: setsCompleted,
            bestWeight: bestWeight,
          ),
        );
      }
    }

    final title =
        _currentSession!.title ??
        (_currentSession!.modality == null
            ? 'Free Training'
            : _currentSession!.modality!);

    return SessionSummary(
      sessionId: _currentSession!.id,
      title: title,
      startedAtMs: _currentSession!.startedAtMs,
      endedAtMs: _currentSession!.endedAtMs,
      totalDurationMs: durationMs,
      totalVolume: totalVolume,
      totalSets: totalSets,
      exercises: exerciseSummaries,
    );
  }

  /// Build a routine draft from the current session exercises
  List<SessionTemplateExercise> buildTemplateDraftExercises() {
    final drafts = <SessionTemplateExercise>[];

    for (final segment in _segments) {
      final segmentEfforts = _efforts[segment.id] ?? [];

      for (final effort in segmentEfforts) {
        final exerciseId = effort.exerciseId ?? 'unknown';
        final exerciseName =
            _exerciseCache[exerciseId]?.name ?? 'Unknown Exercise';
        final observations = _observations[effort.id] ?? [];

        final targets = _buildTemplateTargetsFromObservations(
          observations,
          effort.effortKind,
        );

        drafts.add(
          SessionTemplateExercise(
            exerciseId: exerciseId,
            name: exerciseName,
            effortKind: effort.effortKind,
            targets: targets,
          ),
        );
      }
    }

    return drafts;
  }

  Future<List<TrainingSession>> getSessionsByDateRange(
    int fromMs,
    int toMs,
  ) async {
    return _repository.getSessionsByDateRange(fromMs, toMs);
  }

  List<TemplateTargetDraft> _buildTemplateTargetsFromObservations(
    List<EffortObservation> observations,
    String effortKind,
  ) {
    if (observations.isEmpty) {
      final defaults = EffortDefaults.getDefaultTargets(effortKind);
      return defaults.entries
          .map(
            (entry) => TemplateTargetDraft(
              metricId: entry.key,
              setIndex: 0,
              unitId: null,
              valueReal: entry.value is double ? entry.value as double : null,
              valueInt: entry.value is int ? entry.value as int : null,
              valueText: entry.value is String ? entry.value as String : null,
            ),
          )
          .toList();
    }

    final grouped = _groupObservationsByEntry(observations);
    final targets = <TemplateTargetDraft>[];

    for (final entry in grouped.entries) {
      for (final observation in entry.value) {
        targets.add(
          TemplateTargetDraft(
            metricId: observation.metricId,
            setIndex: entry.key,
            unitId: observation.unitId,
            valueReal: observation.valueReal,
            valueInt: observation.valueInt,
            valueText: observation.valueText,
          ),
        );
      }
    }

    return targets;
  }

  Map<int, List<EffortObservation>> _groupObservationsByEntry(
    List<EffortObservation> observations,
  ) {
    final grouped = <int, List<EffortObservation>>{};
    for (final observation in observations) {
      final entryIndex = _parseEntryIndex(observation.id) ?? 0;
      grouped.putIfAbsent(entryIndex, () => []).add(observation);
    }
    return grouped;
  }

  int? _parseEntryIndex(String observationId) {
    final parts = observationId.split('-');
    if (parts.length < 3) return null;
    return int.tryParse(parts[parts.length - 2]);
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
          'segmentId': segment.id,
          'segmentName': segment.name ?? 'Block ${segment.orderIndex + 1}',
          'segmentType': segment.segmentType,
          'segmentOrder': segment.orderIndex,
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

  /// Create a custom exercise in the library
  Future<Exercise?> createCustomExercise({
    required String name,
    String? description,
    String? disciplineId,
    List<String> capabilities = const [],
    List<String> muscleGroupIds = const [],
  }) async {
    _clearError();

    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      _setError('Exercise name is required');
      return null;
    }

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final exerciseId = 'exercise-$now';
      final exercise = Exercise(
        id: exerciseId,
        ownerUserId: 'user-1',
        disciplineId: disciplineId,
        name: trimmedName,
        description: description?.trim().isEmpty == true ? null : description,
        createdAtMs: now,
        updatedAtMs: now,
      );

      await _repository.createExercise(exercise);
      await _repository.setExerciseCapabilities(exerciseId, capabilities);
      await _repository.setExerciseMuscleGroups(exerciseId, muscleGroupIds);

      final exerciseWithCaps = exercise.copyWith(capabilities: capabilities);
      _exerciseCache[exerciseId] = exerciseWithCaps;
      _allExercises = [
        ..._allExercises.where((e) => e.id != exerciseId),
        exerciseWithCaps,
      ];

      notifyListeners();
      return exerciseWithCaps;
    } catch (e) {
      _setError('Failed to create exercise: $e');
      return null;
    }
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
