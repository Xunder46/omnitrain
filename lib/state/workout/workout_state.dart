import 'package:flutter/foundation.dart';
import '../../data/models/models.dart';
import '../../data/repositories/workout_repository.dart';
import '../../core/constants/modality_config.dart';
import '../../core/constants/metric_ids.dart';
import '../../core/constants/workout_constants.dart';
import '../../core/models/routine_session_manifest.dart';
import '../../core/models/session_edit_snapshot.dart';
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
  // Round instances keyed by effortId — used exclusively for 'round' effortKind.
  // Observation-based tracking is NOT used for round efforts.
  final Map<String, List<RoundInstance>> _roundInstances = {};
  // Timed instances keyed by effortId — used for 'timed' and 'drill' effortKinds.
  // Duration is tracked via wall-clock timestamps; companion observations
  // (distance for timed, extra weight for drill) remain as EffortObservation records.
  final Map<String, List<TimedInstance>> _timedInstances = {};
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

  /// Get round instances for an effort (round-based efforts only)
  List<RoundInstance> getRoundsForEffort(String effortId) {
    return List.unmodifiable(_roundInstances[effortId] ?? []);
  }

  /// Get timed instances for an effort (timed/drill efforts only)
  List<TimedInstance> getTimedInstancesForEffort(String effortId) {
    return List.unmodifiable(_timedInstances[effortId] ?? []);
  }

  /// Find a SegmentEffort by its ID across all segments
  SegmentEffort? _findEffort(String effortId) {
    for (final effortList in _efforts.values) {
      for (final effort in effortList) {
        if (effort.id == effortId) return effort;
      }
    }
    return null;
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

  /// Load a historical (past) session into the in-memory state for read-only
  /// viewing (e.g. from the Calendar screen).
  ///
  /// Does NOT create any new records. Clears current in-memory session state
  /// and replaces it with the loaded session and its child records.
  /// Should only be called when there is no active in-progress session.
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

      // Clear prior in-memory child data.
      _segments.clear();
      _efforts.clear();
      _observations.clear();
      _roundInstances.clear();
      _timedInstances.clear();

      // Load all child records for this session.
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
            _roundInstances[effort.id] = await _repository.getRoundInstances(
              effort.id,
            );
          }
          if (effort.effortKind == 'timed' || effort.effortKind == 'drill') {
            _timedInstances[effort.id] = await _repository.getTimedInstances(
              effort.id,
            );
          }

          if (effort.exerciseId != null) {
            final ex = await _repository.getExerciseById(effort.exerciseId!);
            if (ex != null) _exerciseCache[ex.id] = ex;
          }
        }
      }

      notifyListeners();
    } catch (e) {
      _setError('Failed to load historical session: $e');
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

          // Load round instances for round-kind efforts (these replace observations)
          if (effort.effortKind == 'round') {
            final rounds = await _repository.getRoundInstances(effort.id);
            _roundInstances[effort.id] = rounds;
          }

          // Load timed instances for timed/drill efforts (duration replaces observation)
          if (effort.effortKind == 'timed' || effort.effortKind == 'drill') {
            final timedList = await _repository.getTimedInstances(effort.id);
            _timedInstances[effort.id] = timedList;
          }

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
      final effort = _findEffort(effortId);
      if (effort == null) {
        _setError('Effort not found');
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final entryIndex =
          (_observations[effortId]?.length ?? 0) ~/
          2; // Rough index for grouping

      // Round efforts use RoundInstance records — not EffortObservation pairs.
      // Priority chain for planned duration (highest → lowest):
      //   1. Previous round in this session (user may have adjusted it mid-session)
      //   2. Caller-supplied previousValues hint (e.g. from template targets)
      //   3. Exercise-specific default (e.g. 2700 s for a 45-min soccer half)
      //   4. App-wide global default (180 s / 3-min boxing round)
      if (effort.effortKind == 'round') {
        final existingRounds = _roundInstances[effortId] ?? [];
        final exerciseDefault =
            _exerciseCache[effort.exerciseId]?.defaultRoundDurationSecs;
        final previousDuration = existingRounds.isNotEmpty
            ? existingRounds.last.plannedDurationSecs
            : (previousValues?['round-duration'] as int?) ??
                  exerciseDefault ??
                  WorkoutConstants.defaultRoundDurationSecs;
        await addRound(effortId, plannedDurationSecs: previousDuration);
        return;
      }

      // Timed and drill efforts use TimedInstance for duration tracking +
      // a companion EffortObservation for the secondary metric (distance / extra weight).
      if (effort.effortKind == 'timed' || effort.effortKind == 'drill') {
        final existing = _timedInstances[effortId] ?? [];
        final timedIndex = existing.length;
        final targetDuration = (previousValues?['duration'] as int?) ?? 0;

        await addTimedEntry(effortId, targetDurationSecs: targetDuration);

        // Create the companion observation (distance for timed, extra weight for drill)
        final EffortObservation companion;
        if (effort.effortKind == 'timed') {
          companion = EffortObservation(
            id: 'obs-$effortId-$timedIndex-distance',
            effortId: effortId,
            metricId: MetricIds.distance,
            unitId: MetricIds.unitMeters,
            valueReal: (previousValues?['distance'] as double?) ?? 0.0,
            createdAtMs: now,
            updatedAtMs: now,
          );
        } else {
          // drill
          companion = EffortObservation(
            id: 'obs-$effortId-$timedIndex-extra-weight',
            effortId: effortId,
            metricId: MetricIds.extraWeight,
            valueReal: (previousValues?['extra-weight'] as double?) ?? 0.0,
            createdAtMs: now,
            updatedAtMs: now,
          );
        }
        await _repository.createObservation(companion);
        _observations.putIfAbsent(effortId, () => []).add(companion);

        notifyListeners();
        return;
      }

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

        case 'timed': // Now handled by TimedInstance — should not reach here
          break;

        case 'round': // Now handled by RoundInstance — should not reach here
          break;

        case 'drill': // Now handled by TimedInstance — should not reach here
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
    _clearError();

    try {
      // Round efforts track 'round-duration' via RoundInstance, not observations
      if (metricKey == 'round-duration' &&
          _findEffort(effortId)?.effortKind == 'round') {
        await updateRoundPlannedDuration(effortId, entryIndex, value as int);
        return;
      }

      // Timed/drill efforts track 'duration' via TimedInstance, not observations
      final effortKind = _findEffort(effortId)?.effortKind;
      if (metricKey == 'duration' &&
          (effortKind == 'timed' || effortKind == 'drill')) {
        await updateTimedTargetDuration(effortId, entryIndex, value as int);
        return;
      }

      final observations = _observations[effortId];
      if (observations == null) return;

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
    _clearError();

    try {
      // Find the effort to determine metrics per entry
      final effort = _findEffort(effortId);
      if (effort == null) return;

      // Round efforts use RoundInstance — not observations
      if (effort.effortKind == 'round') {
        await deleteRound(effortId, entryIndex);
        return;
      }

      // Timed/drill efforts use TimedInstance for duration + companion observation
      if (effort.effortKind == 'timed' || effort.effortKind == 'drill') {
        await deleteTimedEntry(effortId, entryIndex);
        return;
      }

      final observations = _observations[effortId];
      if (observations == null) return;

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

  // ─────────────────────────────────────────────────────────────
  // Round Lifecycle Methods
  // These manage RoundInstance records exclusively for effortKind == 'round'.
  // Round efforts do NOT use EffortObservation for tracking.
  // ─────────────────────────────────────────────────────────────

  /// Validates that a round state transition is allowed.
  /// Enforces strict state machine rules:
  ///   notStarted → active
  ///   active     → paused | finished
  ///   paused     → active | finished
  ///   finished   → (none — terminal)
  bool _isValidRoundTransition(RoundState from, RoundState to) {
    switch (from) {
      case RoundState.notStarted:
        return to == RoundState.active;
      case RoundState.active:
        return to == RoundState.paused || to == RoundState.finished;
      case RoundState.paused:
        return to == RoundState.active || to == RoundState.finished;
      case RoundState.finished:
        return false; // Terminal state — no transitions allowed
    }
  }

  /// Add a new round to a round-kind effort (pending/not-started state).
  Future<void> addRound(
    String effortId, {
    int plannedDurationSecs = WorkoutConstants.defaultRoundDurationSecs,
  }) async {
    _clearError();
    try {
      final existing = _roundInstances[effortId] ?? [];
      final roundIndex = existing.length;
      final now = DateTime.now().millisecondsSinceEpoch;
      final instance = RoundInstance(
        id: 'round-$effortId-$roundIndex-$now',
        effortId: effortId,
        roundIndex: roundIndex,
        plannedDurationSecs: plannedDurationSecs,
        actualDurationSecs: 0,
        startedAtMs: 0,
        finishedAtMs: null,
        completed: false,
        state: RoundState.notStarted,
        pausedAtMs: null,
        totalPausedDurationMs: 0,
        createdAtMs: now,
        updatedAtMs: now,
      );
      await _repository.createRoundInstance(instance);
      _roundInstances.putIfAbsent(effortId, () => []).add(instance);
      notifyListeners();
    } catch (e) {
      _setError('Failed to add round: $e');
    }
  }

  /// Start a round — records wall-clock start timestamp and transitions to Active.
  /// Validates: notStarted → active
  Future<void> startRound(String effortId, int roundIndex) async {
    _clearError();
    try {
      final list = _roundInstances[effortId];
      if (list == null || roundIndex >= list.length) return;
      final old = list[roundIndex];

      if (!_isValidRoundTransition(old.state, RoundState.active)) {
        debugPrint('Invalid round transition: ${old.state} → active');
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final updated = old.copyWith(
        state: RoundState.active,
        startedAtMs: now,
        updatedAtMs: now,
      );
      await _repository.updateRoundInstance(updated);
      list[roundIndex] = updated;
      notifyListeners();
    } catch (e) {
      _setError('Failed to start round: $e');
    }
  }

  /// Pause a round — records wall-clock pause timestamp and transitions to Paused.
  /// Validates: active → paused
  Future<void> pauseRound(String effortId, int roundIndex) async {
    _clearError();
    try {
      final list = _roundInstances[effortId];
      if (list == null || roundIndex >= list.length) return;
      final old = list[roundIndex];

      if (!_isValidRoundTransition(old.state, RoundState.paused)) {
        debugPrint('Invalid round transition: ${old.state} → paused');
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final updated = old.copyWith(
        state: RoundState.paused,
        pausedAtMs: now,
        updatedAtMs: now,
      );
      await _repository.updateRoundInstance(updated);
      list[roundIndex] = updated;
      notifyListeners();
    } catch (e) {
      _setError('Failed to pause round: $e');
    }
  }

  /// Resume a round — folds pause duration into totalPausedDurationMs and transitions to Active.
  /// Validates: paused → active
  Future<void> resumeRound(String effortId, int roundIndex) async {
    _clearError();
    try {
      final list = _roundInstances[effortId];
      if (list == null || roundIndex >= list.length) return;
      final old = list[roundIndex];

      if (!_isValidRoundTransition(old.state, RoundState.active)) {
        debugPrint('Invalid round transition: ${old.state} → active');
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final pauseDuration = old.pausedAtMs != null
          ? (now - old.pausedAtMs!)
          : 0;

      final updated = old.copyWith(
        state: RoundState.active,
        totalPausedDurationMs: old.totalPausedDurationMs + pauseDuration,
        pausedAtMs: null, // Clear pause timestamp
        updatedAtMs: now,
      );
      await _repository.updateRoundInstance(updated);
      list[roundIndex] = updated;
      notifyListeners();
    } catch (e) {
      _setError('Failed to resume round: $e');
    }
  }

  /// Mark a round as naturally completed (countdown reached zero).
  /// Sets completed = true, actualDurationSecs = plannedDurationSecs.
  /// This is the ONLY path that sets completed = true.
  /// Validates: active → finished
  Future<void> completeRound(String effortId, int roundIndex) async {
    _clearError();
    try {
      final list = _roundInstances[effortId];
      if (list == null || roundIndex >= list.length) return;
      final old = list[roundIndex];

      if (!_isValidRoundTransition(old.state, RoundState.finished)) {
        debugPrint(
          'Invalid round transition: ${old.state} → finished (complete)',
        );
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      // Calculate exact finishedAtMs based on planned duration + accumulated pauses
      final finishedAtMs =
          old.startedAtMs +
          (old.plannedDurationSecs * 1000) +
          old.totalPausedDurationMs;

      final updated = old.copyWith(
        state: RoundState.finished,
        actualDurationSecs: old.plannedDurationSecs,
        finishedAtMs: finishedAtMs,
        completed: true, // Only this method sets completed = true
        pausedAtMs: null, // Clear any pause state
        updatedAtMs: now,
      );
      await _repository.updateRoundInstance(updated);
      list[roundIndex] = updated;
      notifyListeners();
    } catch (e) {
      _setError('Failed to complete round: $e');
    }
  }

  /// Mark a round as ended early (user logged before countdown finished or session closed).
  /// Sets completed = false. Derives actualDurationSecs from timestamps.
  /// If paused, folds the final pause duration before finishing.
  /// Validates: active → finished OR paused → finished
  Future<void> endRoundEarly(String effortId, int roundIndex) async {
    _clearError();
    try {
      final list = _roundInstances[effortId];
      if (list == null || roundIndex >= list.length) return;
      final old = list[roundIndex];

      if (!_isValidRoundTransition(old.state, RoundState.finished)) {
        debugPrint('Invalid round transition: ${old.state} → finished (early)');
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;

      // If paused, fold the final pause duration into totalPausedDurationMs
      final totalPausedMs =
          old.state == RoundState.paused && old.pausedAtMs != null
          ? old.totalPausedDurationMs + (now - old.pausedAtMs!)
          : old.totalPausedDurationMs;

      // Derive elapsed from timestamps: now - startedAtMs - totalPausedMs
      final elapsedMs = old.startedAtMs > 0
          ? (now - old.startedAtMs - totalPausedMs)
          : 0;
      final actualDurationSecs = (elapsedMs / 1000).round().clamp(
        0,
        old.plannedDurationSecs * WorkoutConstants.roundActualDurationCapFactor,
      );

      final updated = old.copyWith(
        state: RoundState.finished,
        actualDurationSecs: actualDurationSecs,
        finishedAtMs: now,
        completed: false, // Always false for early/manual end
        totalPausedDurationMs: totalPausedMs,
        pausedAtMs: null, // Clear pause state
        updatedAtMs: now,
      );
      await _repository.updateRoundInstance(updated);
      list[roundIndex] = updated;
      notifyListeners();
    } catch (e) {
      _setError('Failed to end round early: $e');
    }
  }

  /// Delete a round by index and re-index all subsequent rounds.
  /// No state restrictions — rounds can be deleted in any state.
  Future<void> deleteRound(String effortId, int roundIndex) async {
    _clearError();
    try {
      final list = _roundInstances[effortId];
      if (list == null || roundIndex >= list.length) return;
      await _repository.deleteRoundInstance(list[roundIndex].id);
      list.removeAt(roundIndex);
      // Re-index rounds that came after the deleted one
      final now = DateTime.now().millisecondsSinceEpoch;
      for (int i = roundIndex; i < list.length; i++) {
        final r = list[i];
        final reindexed = r.copyWith(roundIndex: i, updatedAtMs: now);
        list[i] = reindexed;
        await _repository.updateRoundInstance(reindexed);
      }
      notifyListeners();
    } catch (e) {
      _setError('Failed to delete round: $e');
    }
  }

  /// Update the planned duration for a round (e.g., user edits the timer target).
  /// Rejects if the round is already Finished (immutable).
  Future<void> updateRoundPlannedDuration(
    String effortId,
    int roundIndex,
    int newDurationSecs,
  ) async {
    _clearError();
    try {
      final list = _roundInstances[effortId];
      if (list == null || roundIndex >= list.length) return;
      final old = list[roundIndex];

      if (old.state == RoundState.finished) {
        debugPrint('Cannot update planned duration for finished round');
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final updated = old.copyWith(
        plannedDurationSecs: newDurationSecs,
        updatedAtMs: now,
      );
      await _repository.updateRoundInstance(updated);
      list[roundIndex] = updated;
      notifyListeners();
    } catch (e) {
      _setError('Failed to update round duration: $e');
    }
  }

  /// Safety net: persist any active or paused round instances before ending a session.
  /// Calls [endRoundEarly] for each round needing closure.
  /// Finished and notStarted rounds are skipped (already persisted / nothing to do).
  Future<void> _persistActiveRounds() async {
    for (final entry in _roundInstances.entries) {
      final effortId = entry.key;
      final rounds = entry.value;
      for (int i = 0; i < rounds.length; i++) {
        final round = rounds[i];
        if (round.state == RoundState.active ||
            round.state == RoundState.paused) {
          // End early — this will handle pause folding and state transition
          await endRoundEarly(effortId, i);
        }
        // Skip finished and notStarted rounds
      }
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Timed Instance Lifecycle Methods
  // These manage TimedInstance records for effortKind == 'timed' or 'drill'.
  // Duration is tracked via wall-clock timestamps (background-resilient).
  // Companion observations (distance / extra weight) remain as EffortObservation.
  // ─────────────────────────────────────────────────────────────

  /// Validates that a timed state transition is allowed.
  /// Enforces strict state machine rules (same as rounds):
  ///   notStarted → active
  ///   active     → paused | finished
  ///   paused     → active | finished
  ///   finished   → (none — terminal)
  bool _isValidTimedTransition(TimedState from, TimedState to) {
    switch (from) {
      case TimedState.notStarted:
        return to == TimedState.active;
      case TimedState.active:
        return to == TimedState.paused || to == TimedState.finished;
      case TimedState.paused:
        return to == TimedState.active || to == TimedState.finished;
      case TimedState.finished:
        return false; // Terminal state — no transitions allowed
    }
  }

  /// Add a new timed entry to a timed/drill effort (pending/not-started state).
  Future<void> addTimedEntry(
    String effortId, {
    int targetDurationSecs = 0,
  }) async {
    _clearError();
    try {
      final existing = _timedInstances[effortId] ?? [];
      final entryIndex = existing.length;
      final now = DateTime.now().millisecondsSinceEpoch;
      final instance = TimedInstance(
        id: 'timed-$effortId-$entryIndex-$now',
        effortId: effortId,
        entryIndex: entryIndex,
        targetDurationSecs: targetDurationSecs,
        actualDurationSecs: 0,
        startedAtMs: 0,
        finishedAtMs: null,
        state: TimedState.notStarted,
        pausedAtMs: null,
        totalPausedDurationMs: 0,
        createdAtMs: now,
        updatedAtMs: now,
      );
      await _repository.createTimedInstance(instance);
      _timedInstances.putIfAbsent(effortId, () => []).add(instance);
      notifyListeners();
    } catch (e) {
      _setError('Failed to add timed entry: $e');
    }
  }

  /// Start a timed entry — records wall-clock start timestamp and transitions to Active.
  /// Validates: notStarted → active
  Future<void> startTimedEntry(String effortId, int entryIndex) async {
    _clearError();
    try {
      final list = _timedInstances[effortId];
      if (list == null || entryIndex >= list.length) return;
      final old = list[entryIndex];

      if (!_isValidTimedTransition(old.state, TimedState.active)) {
        debugPrint('Invalid timed transition: ${old.state} → active');
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final offsetMs = old.targetDurationSecs > 0
          ? old.targetDurationSecs * 1000
          : 0;
      final updated = old.copyWith(
        state: TimedState.active,
        // A pre-start duration edit on timed/drill is treated as an initial
        // elapsed offset for open-ended count-up, not as a countdown target.
        // Back-date start so elapsed begins at that offset on first tick.
        startedAtMs: now - offsetMs,
        // Clear target after first start so timed/drill remain open-ended and
        // avoid expiry logic intended for countdown efforts.
        targetDurationSecs: 0,
        updatedAtMs: now,
      );
      await _repository.updateTimedInstance(updated);
      list[entryIndex] = updated;
      notifyListeners();
    } catch (e) {
      _setError('Failed to start timed entry: $e');
    }
  }

  /// Pause a timed entry — records wall-clock pause timestamp and transitions to Paused.
  /// Validates: active → paused
  Future<void> pauseTimedEntry(String effortId, int entryIndex) async {
    _clearError();
    try {
      final list = _timedInstances[effortId];
      if (list == null || entryIndex >= list.length) return;
      final old = list[entryIndex];

      if (!_isValidTimedTransition(old.state, TimedState.paused)) {
        debugPrint('Invalid timed transition: ${old.state} → paused');
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final updated = old.copyWith(
        state: TimedState.paused,
        pausedAtMs: now,
        updatedAtMs: now,
      );
      await _repository.updateTimedInstance(updated);
      list[entryIndex] = updated;
      notifyListeners();
    } catch (e) {
      _setError('Failed to pause timed entry: $e');
    }
  }

  /// Resume a timed entry — folds pause duration and transitions to Active.
  /// Validates: paused → active
  Future<void> resumeTimedEntry(String effortId, int entryIndex) async {
    _clearError();
    try {
      final list = _timedInstances[effortId];
      if (list == null || entryIndex >= list.length) return;
      final old = list[entryIndex];

      if (!_isValidTimedTransition(old.state, TimedState.active)) {
        debugPrint('Invalid timed transition: ${old.state} → active');
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final pauseDuration = old.pausedAtMs != null
          ? (now - old.pausedAtMs!)
          : 0;

      final updated = old.copyWith(
        state: TimedState.active,
        totalPausedDurationMs: old.totalPausedDurationMs + pauseDuration,
        pausedAtMs: null, // Clear pause timestamp
        updatedAtMs: now,
      );
      await _repository.updateTimedInstance(updated);
      list[entryIndex] = updated;
      notifyListeners();
    } catch (e) {
      _setError('Failed to resume timed entry: $e');
    }
  }

  /// Finish a timed entry — derives actualDurationSecs from timestamps.
  /// If paused, folds the final pause duration before finishing.
  /// Validates: active → finished OR paused → finished
  Future<void> finishTimedEntry(String effortId, int entryIndex) async {
    _clearError();
    try {
      final list = _timedInstances[effortId];
      if (list == null || entryIndex >= list.length) return;
      final old = list[entryIndex];

      if (!_isValidTimedTransition(old.state, TimedState.finished)) {
        debugPrint('Invalid timed transition: ${old.state} → finished');
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;

      // If paused, fold the final pause duration into totalPausedDurationMs
      final totalPausedMs =
          old.state == TimedState.paused && old.pausedAtMs != null
          ? old.totalPausedDurationMs + (now - old.pausedAtMs!)
          : old.totalPausedDurationMs;

      // Derive elapsed from timestamps: now - startedAtMs - totalPausedMs
      final elapsedMs = old.startedAtMs > 0
          ? (now - old.startedAtMs - totalPausedMs)
          : 0;
      final actualDurationSecs = (elapsedMs / 1000).round().clamp(0, 86400);

      final updated = old.copyWith(
        state: TimedState.finished,
        actualDurationSecs: actualDurationSecs,
        finishedAtMs: now,
        totalPausedDurationMs: totalPausedMs,
        pausedAtMs: null, // Clear pause state
        updatedAtMs: now,
      );
      await _repository.updateTimedInstance(updated);
      list[entryIndex] = updated;
      notifyListeners();
    } catch (e) {
      _setError('Failed to finish timed entry: $e');
    }
  }

  /// Delete a timed entry by index and re-index all subsequent entries.
  /// Also deletes the companion observation at the same index.
  Future<void> deleteTimedEntry(String effortId, int entryIndex) async {
    _clearError();
    try {
      final list = _timedInstances[effortId];
      if (list == null || entryIndex >= list.length) return;
      await _repository.deleteTimedInstance(list[entryIndex].id);
      list.removeAt(entryIndex);

      // Re-index entries that came after the deleted one
      final now = DateTime.now().millisecondsSinceEpoch;
      for (int i = entryIndex; i < list.length; i++) {
        final t = list[i];
        final reindexed = t.copyWith(entryIndex: i, updatedAtMs: now);
        list[i] = reindexed;
        await _repository.updateTimedInstance(reindexed);
      }

      // Delete the companion observation at the same index.
      // Timed/drill observations are 1-per-entry (distance or extra weight).
      final observations = _observations[effortId];
      if (observations != null && entryIndex < observations.length) {
        final obs = observations[entryIndex];
        await _repository.deleteObservation(obs.id);
        observations.removeAt(entryIndex);
      }

      notifyListeners();
    } catch (e) {
      _setError('Failed to delete timed entry: $e');
    }
  }

  /// Update the target duration for a timed entry (e.g., user scrolls the duration editor).
  /// Rejects if the entry is already Finished (immutable).
  Future<void> updateTimedTargetDuration(
    String effortId,
    int entryIndex,
    int newTargetSecs,
  ) async {
    _clearError();
    try {
      final list = _timedInstances[effortId];
      if (list == null || entryIndex >= list.length) return;
      final old = list[entryIndex];

      if (old.state == TimedState.finished) {
        debugPrint('Cannot update target duration for finished timed entry');
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final updated = old.copyWith(
        targetDurationSecs: newTargetSecs,
        updatedAtMs: now,
      );
      await _repository.updateTimedInstance(updated);
      list[entryIndex] = updated;
      notifyListeners();
    } catch (e) {
      _setError('Failed to update timed target duration: $e');
    }
  }

  /// Safety net: persist any active or paused timed instances before ending a session.
  /// Calls [finishTimedEntry] for each entry needing closure.
  /// Finished and notStarted entries are skipped.
  Future<void> _persistActiveTimedEntries() async {
    for (final entry in _timedInstances.entries) {
      final effortId = entry.key;
      final entries = entry.value;
      for (int i = 0; i < entries.length; i++) {
        final timedEntry = entries[i];
        if (timedEntry.state == TimedState.active ||
            timedEntry.state == TimedState.paused) {
          await finishTimedEntry(effortId, i);
        }
        // Skip finished and notStarted entries
      }
    }
  }

  /// Get the number of observations per entry for a given effort kind
  /// Used to calculate entry boundaries when deleting or updating entries.
  /// NOTE: Round efforts use RoundInstance records, not observations.
  /// NOTE: Timed/drill efforts use TimedInstance + 1 companion observation.
  /// This method is only called for 'set'-kind efforts that use pure observations.
  /// Round entries route through deleteRound; timed/drill through deleteTimedEntry.
  int _getMetricsPerEntry(String effortKind) {
    switch (effortKind) {
      case 'set': // reps + weight
        return 2;
      case 'timed': // companion only (distance); duration is in TimedInstance
        return 1;
      case 'round':
        // Round efforts use RoundInstance — not observations.
        // This case should never be reached (deleteEntry routes round to deleteRound).
        assert(
          false,
          '_getMetricsPerEntry must not be called for round efforts',
        );
        return 0;
      case 'drill': // companion only (extra-weight); duration is in TimedInstance
        return 1;
      default:
        return 2; // Fallback
    }
  }

  /// Remove an exercise (effort) from the session
  /// [effortId] - The effort to remove
  Future<void> removeExerciseFromSession(String effortId) async {
    _clearError();

    try {
      // Delete the effort (this also deletes all observations and round instances
      // via repository cascade — see deleteEffort implementation).
      await _repository.deleteEffort(effortId);

      // Remove from local caches
      _observations.remove(effortId);
      _roundInstances.remove(effortId); // Clear cached round instances too
      _timedInstances.remove(effortId); // Clear cached timed instances too
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
    if (_currentSession!.endedAtMs != null) return;

    _clearError();

    try {
      // Safety net: persist any round not yet closed by the UI timer layer.
      // The screen should have called endRoundEarly() with pause-adjusted elapsed
      // before navigating to the summary — this handles any that slipped through.
      await _persistActiveRounds();

      // Safety net: persist any timed/drill entries not yet closed by the UI.
      await _persistActiveTimedEntries();

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

  /// Discard the current session and delete persisted data
  Future<void> discardCurrentSession() async {
    if (_currentSession == null) return;

    _clearError();

    try {
      await _repository.deleteSession(_currentSession!.id);
      clearSession();
    } catch (e) {
      _setError('Failed to discard session: $e');
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

  /// Overwrite the session's end time using a corrected duration (edit mode).
  ///
  /// Computes `endedAtMs = startedAtMs + durationSecs * 1000`.
  /// Repository-agnostic: uses the same abstract `updateSession` path as
  /// [updateSessionNote], so it works identically on HiveWorkoutRepository
  /// (web/current) and the future SqliteWorkoutRepository.
  ///
  /// Ignored if [durationSecs] ≤ 0 or there is no current session.
  Future<void> updateSessionEndTime(int durationSecs) async {
    if (_currentSession == null) return;
    if (durationSecs <= 0) return;
    _clearError();
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final newEndedAtMs =
          _currentSession!.startedAtMs + (durationSecs * 1000);
      final updatedSession = TrainingSession(
        id: _currentSession!.id,
        ownerUserId: _currentSession!.ownerUserId,
        routineTemplateId: _currentSession!.routineTemplateId,
        startedAtMs: _currentSession!.startedAtMs,
        endedAtMs: newEndedAtMs,
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
      _setError('Failed to update session end time: $e');
    }
  }

  // ── Edit-mode snapshot / rollback ──────────────────────────────────────

  /// Captures the current in-memory session state as an immutable snapshot.
  ///
  /// Call this immediately before opening edit mode so that structural mutations
  /// (add/remove exercise, add/remove set) can be rolled back if the user exits
  /// edit mode without saving.
  ///
  /// Returns `null` when there is no active session.
  SessionEditSnapshot? snapshotSessionState() {
    if (_currentSession == null) return null;

    return SessionEditSnapshot(
      sessionId: _currentSession!.id,
      segments: List<SessionSegment>.from(_segments),
      efforts: {
        for (final entry in _efforts.entries)
          entry.key: List<SegmentEffort>.from(entry.value),
      },
      observations: {
        for (final entry in _observations.entries)
          entry.key: List<EffortObservation>.from(entry.value),
      },
      roundInstances: {
        for (final entry in _roundInstances.entries)
          entry.key: List<RoundInstance>.from(entry.value),
      },
      timedInstances: {
        for (final entry in _timedInstances.entries)
          entry.key: List<TimedInstance>.from(entry.value),
      },
      exerciseCache: Map<String, Exercise>.from(_exerciseCache),
    );
  }

  /// Restores the session to the given [snapshot], undoing all structural changes
  /// made during a cancelled edit session.
  ///
  /// **What is restored:**
  /// - Efforts added after the snapshot are deleted (cascade removes their children).
  /// - Efforts removed during editing are recreated along with their observations
  ///   and instances.
  /// - For efforts present in both states, observations / round instances / timed
  ///   instances are reset to their snapshot values (undoes add-set / delete-set).
  ///
  /// **Implementation note (both environments):**
  /// The restore is orchestrated entirely through existing abstract repository
  /// primitives (`deleteEffort`, `createEffort`, `createObservation`, etc.), so
  /// both [HiveWorkoutRepository] (web/current) and the future
  /// [SqliteWorkoutRepository] (production) work without any additional methods.
  ///
  /// After all writes, [loadSessionData] is called to sync in-memory state.
  Future<void> restoreSessionSnapshot(SessionEditSnapshot snapshot) async {
    _clearError();

    try {
      // Collect current and snapshot effort ID sets.
      final currentEffortIds = <String>{
        for (final effortList in _efforts.values)
          for (final effort in effortList) effort.id,
      };
      final snapshotEffortIds = <String>{
        for (final effortList in snapshot.efforts.values)
          for (final effort in effortList) effort.id,
      };

      // 1. Delete efforts that were ADDED during editing (not present in snapshot).
      //    deleteEffort() cascades to observations, round instances, and timed instances.
      for (final effortId in currentEffortIds) {
        if (!snapshotEffortIds.contains(effortId)) {
          await _repository.deleteEffort(effortId);
        }
      }

      // 2. Recreate efforts that were REMOVED during editing (in snapshot but missing now).
      for (final segmentId in snapshot.efforts.keys) {
        for (final effort in snapshot.efforts[segmentId]!) {
          if (!currentEffortIds.contains(effort.id)) {
            await _repository.createEffort(effort);
            for (final obs in snapshot.observations[effort.id] ?? []) {
              await _repository.createObservation(obs);
            }
            for (final ri in snapshot.roundInstances[effort.id] ?? []) {
              await _repository.createRoundInstance(ri);
            }
            for (final ti in snapshot.timedInstances[effort.id] ?? []) {
              await _repository.createTimedInstance(ti);
            }
          }
        }
      }

      // 3. For efforts present in BOTH states, restore their children to snapshot
      //    values to undo add-set / delete-set operations.
      for (final effortId in currentEffortIds) {
        if (!snapshotEffortIds.contains(effortId))
          continue; // already deleted above

        // Restore observations (set-based efforts).
        await _repository.deleteObservationsForEffort(effortId);
        for (final obs in snapshot.observations[effortId] ?? []) {
          await _repository.createObservation(obs);
        }

        // Restore round instances (round-based efforts).
        if (snapshot.roundInstances.containsKey(effortId)) {
          await _repository.deleteRoundInstancesForEffort(effortId);
          for (final ri in snapshot.roundInstances[effortId]!) {
            await _repository.createRoundInstance(ri);
          }
        }

        // Restore timed instances (timed/drill efforts).
        if (snapshot.timedInstances.containsKey(effortId)) {
          await _repository.deleteTimedInstancesForEffort(effortId);
          for (final ti in snapshot.timedInstances[effortId]!) {
            await _repository.createTimedInstance(ti);
          }
        }
      }

      // 4. Restore exercise cache so removed-then-restored efforts resolve correctly.
      _exerciseCache
        ..clear()
        ..addAll(snapshot.exerciseCache);

      // 5. Reload from repository to sync in-memory state.
      await loadSessionData();
    } catch (e) {
      _setError('Failed to restore session snapshot: $e');
      rethrow;
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
    int totalRounds = 0;
    int totalCardioDurationMs = 0;
    int totalDrillDurationMs = 0;
    int executionOrder = 0;
    final exerciseSummaries = <ExerciseSummary>[];

    for (final segment in _segments) {
      final segmentEfforts = _efforts[segment.id] ?? [];

      for (final effort in segmentEfforts) {
        final exerciseId = effort.exerciseId ?? 'unknown';
        final exerciseName =
            _exerciseCache[exerciseId]?.name ?? 'Unknown Exercise';
        final observations = _observations[effort.id] ?? [];
        final entries = _buildEntriesForEffort(effort.effortKind, observations);

        int setsCompleted = 0;
        double? bestWeight;
        int? effortDurationMs;
        int effortRounds = 0;

        if (effort.effortKind == 'set') {
          for (final entry in entries) {
            final reps = entry['reps'] as int?;
            final weight = entry['weight'] as double?;

            if (reps != null && weight != null) {
              totalVolume += reps * weight;
            }

            if (weight != null) {
              if (bestWeight == null || weight > bestWeight) {
                bestWeight = weight;
              }
            }
          }

          setsCompleted = entries.length;
          totalSets += entries.length;
        } else if (effort.effortKind == 'round') {
          // Round efforts use RoundInstance records; observations list is empty
          final rounds = _roundInstances[effort.id] ?? [];
          effortRounds = rounds.length;
          setsCompleted = effortRounds;
          totalRounds += effortRounds;
        } else if (effort.effortKind == 'timed') {
          // Timed efforts use TimedInstance records for wall-clock duration
          final timedInstances = _timedInstances[effort.id] ?? [];
          setsCompleted = timedInstances.length;
          totalCardioDurationMs += timedInstances.fold<int>(
            0,
            (sum, inst) => sum + inst.elapsedMs,
          );
          effortDurationMs = timedInstances.fold<int>(
            0,
            (sum, inst) => sum + inst.elapsedMs,
          );
        } else if (effort.effortKind == 'drill') {
          // Drill efforts use TimedInstance records for wall-clock duration
          final timedInstances = _timedInstances[effort.id] ?? [];
          setsCompleted = timedInstances.length;
          totalDrillDurationMs += timedInstances.fold<int>(
            0,
            (sum, inst) => sum + inst.elapsedMs,
          );
          effortDurationMs = timedInstances.fold<int>(
            0,
            (sum, inst) => sum + inst.elapsedMs,
          );
        } else {
          setsCompleted = entries.length;
        }

        exerciseSummaries.add(
          ExerciseSummary(
            exerciseId: exerciseId,
            name: exerciseName,
            effortKind: effort.effortKind,
            setsCompleted: setsCompleted,
            bestWeight: bestWeight,
            executionOrder: executionOrder,
            totalDurationMs: effortDurationMs,
            totalRounds: effortRounds,
          ),
        );
        executionOrder++;
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
      totalRounds: totalRounds,
      totalCardioDurationMs: totalCardioDurationMs,
      totalDrillDurationMs: totalDrillDurationMs,
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

        List<TemplateTargetDraft> targets;
        if (effort.effortKind == 'round') {
          // Build round template targets from RoundInstance data.
          // Use the first round's planned duration as the default target; fall back to 180s.
          final rounds = _roundInstances[effort.id] ?? [];
          final plannedDuration = rounds.isNotEmpty
              ? rounds.first.plannedDurationSecs
              : WorkoutConstants.defaultRoundDurationSecs;
          targets = [
            TemplateTargetDraft(
              metricId: MetricIds.rounds,
              setIndex: 0,
              unitId: MetricIds.unitRounds,
              valueInt: rounds.isNotEmpty ? rounds.length : 1,
              valueReal: null,
              valueText: null,
            ),
            TemplateTargetDraft(
              metricId: MetricIds.roundDuration,
              setIndex: 0,
              unitId: MetricIds.unitSeconds,
              valueInt: plannedDuration,
              valueReal: null,
              valueText: null,
            ),
          ];
        } else if (effort.effortKind == 'timed' ||
            effort.effortKind == 'drill') {
          // Build timed/drill template targets from TimedInstance data.
          // Use targetDurationSecs from first timed instance, or default to 300s (5 min).
          final timedInstances = _timedInstances[effort.id] ?? [];
          final targetDuration = timedInstances.isNotEmpty
              ? timedInstances.first.targetDurationSecs
              : 300;
          targets = [
            TemplateTargetDraft(
              metricId: MetricIds.duration,
              setIndex: 0,
              unitId: MetricIds.unitSeconds,
              valueInt: targetDuration,
              valueReal: null,
              valueText: null,
            ),
          ];

          // For drill efforts, also include the companion extra-weight target.
          if (effort.effortKind == 'drill') {
            final companionObs = _observations[effort.id] ?? [];
            final extraWeight = companionObs.isNotEmpty
                ? (companionObs.first.valueReal ?? 0.0)
                : 0.0;
            targets.add(
              TemplateTargetDraft(
                metricId: MetricIds.extraWeight,
                setIndex: 0,
                unitId: MetricIds.unitKg,
                valueReal: extraWeight,
                valueInt: null,
                valueText: null,
              ),
            );
          }
        } else {
          final observations = _observations[effort.id] ?? [];
          targets = _buildTemplateTargetsFromObservations(
            observations,
            effort.effortKind,
          );
        }

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

    final entries = _buildEntriesForEffort(effortKind, observations);
    final targets = <TemplateTargetDraft>[];

    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      for (final metricEntry in entry.entries) {
        final metricId = MetricIds.keyToMetricId[metricEntry.key];
        if (metricId == null) continue;

        final value = metricEntry.value;
        targets.add(
          TemplateTargetDraft(
            metricId: metricId,
            setIndex: i,
            unitId: _metricKeyToUnitId[metricEntry.key],
            valueReal: value is double ? value : null,
            valueInt: value is int ? value : null,
            valueText: value is String ? value : null,
          ),
        );
      }
    }

    return targets;
  }

  List<Map<String, dynamic>> _buildEntriesForEffort(
    String effortKind,
    List<EffortObservation> observations,
  ) {
    final sorted = List<EffortObservation>.from(observations)
      ..sort((a, b) {
        final createdCompare = a.createdAtMs.compareTo(b.createdAtMs);
        if (createdCompare != 0) return createdCompare;
        return _metricOrderForEffort(
          effortKind,
          a.metricId,
        ).compareTo(_metricOrderForEffort(effortKind, b.metricId));
      });

    return ObservationGrouper.groupByEffortKind(effortKind, sorted);
  }

  int _metricOrderForEffort(String effortKind, String metricId) {
    switch (effortKind) {
      case 'set':
        return metricId == MetricIds.reps ? 0 : 1;
      case 'timed':
        return metricId == MetricIds.duration ? 0 : 1;
      case 'round':
        return metricId == MetricIds.rounds ? 0 : 1;
      case 'drill':
        return metricId == MetricIds.duration ? 0 : 1;
      default:
        return 0;
    }
  }

  static const Map<String, String> _metricKeyToUnitId = {
    'reps': MetricIds.unitReps,
    'weight': MetricIds.unitKg,
    'duration': MetricIds.unitSeconds,
    'distance': MetricIds.unitMeters,
    'rounds': MetricIds.unitRounds,
    'round-duration': MetricIds.unitSeconds,
    'extra-weight': MetricIds.unitKg,
  };

  /// Get exercises with their entries for display (modality-aware)
  List<Map<String, dynamic>> getExercisesWithEntries() {
    final result = <Map<String, dynamic>>[];

    for (final segment in _segments) {
      final segmentEfforts = _efforts[segment.id] ?? [];

      for (final effort in segmentEfforts) {
        final exercise = _exerciseCache[effort.exerciseId];
        final exerciseName = exercise?.name ?? 'Unknown Exercise';

        // Build entry list: round efforts use RoundInstance,
        // timed/drill use TimedInstance + companion observation,
        // set uses observation pairs.
        final List<Map<String, dynamic>> entries;
        if (effort.effortKind == 'round') {
          final rounds = _roundInstances[effort.id] ?? [];
          entries = rounds
              .map(
                (r) => <String, dynamic>{
                  'rounds': r.roundIndex + 1, // 1-based display
                  'round-duration': r.plannedDurationSecs,
                  'actualDuration': r.actualDurationSecs,
                  'startedAt': r.startedAtMs,
                  'finishedAt': r.finishedAtMs,
                  'completed': r.completed,
                },
              )
              .toList();
        } else if (effort.effortKind == 'timed' ||
            effort.effortKind == 'drill') {
          // Build entries from TimedInstance (duration) + companion observations
          final timedList = _timedInstances[effort.id] ?? [];
          final companionObs = _observations[effort.id] ?? [];
          entries = <Map<String, dynamic>>[];
          for (int i = 0; i < timedList.length; i++) {
            final t = timedList[i];
            // elapsedSecs: actual duration — actualDurationSecs when finished, else live elapsed.
            final elapsedSecs = t.state == TimedState.finished
                ? t.actualDurationSecs
                : (t.elapsedMs / 1000).round();
            final entryMap = <String, dynamic>{
              // 'duration' ALWAYS holds the user's preset target so that
              // _updateMetricValue → updateTimedTargetDuration works correctly.
              'duration': t.targetDurationSecs,
              // 'elapsedSecs' carries the actual elapsed / completed duration for
              // display in previous-set stats and the exercise subtitle.
              'elapsedSecs': elapsedSecs,
              // 'timedState' exposes the lifecycle phase so UI widgets can render
              // target-preset vs countdown vs count-up vs completed without
              // re-fetching the TimedInstance.
              'timedState': t.state.name,
            };
            // Attach companion metric from the paired observation
            if (i < companionObs.length) {
              final obs = companionObs[i];
              if (effort.effortKind == 'timed') {
                entryMap['distance'] = obs.valueReal ?? 0.0;
              } else {
                entryMap['extra-weight'] = obs.valueReal ?? 0.0;
              }
            } else {
              // Missing companion — use default
              if (effort.effortKind == 'timed') {
                entryMap['distance'] = 0.0;
              } else {
                entryMap['extra-weight'] = 0.0;
              }
            }
            entries.add(entryMap);
          }
        } else {
          final effortObservations = _observations[effort.id] ?? [];
          entries = ObservationGrouper.groupByEffortKind(
            effort.effortKind,
            effortObservations,
          );
        }

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
    _roundInstances.clear();
    _timedInstances.clear();
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
