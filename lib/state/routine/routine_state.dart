import 'package:flutter/foundation.dart';
import '../../data/models/models.dart';
import '../../data/repositories/workout_repository.dart';
import '../workout/workout_state.dart';


/// State management for routine (workout template) creation and management.
/// 
/// Extends ChangeNotifier to provide reactive updates to UI.
/// All data operations go through the injected WorkoutRepository,
/// making this code work with both MockWorkoutRepository (web) and future
/// SqliteWorkoutRepository (native).
class RoutineState extends ChangeNotifier {
  final WorkoutRepository _repository;

  List<WorkoutTemplate> _routines = [];
  WorkoutTemplate? _currentTemplate;
  TemplateSegment? _currentSegment;
  List<TemplateEffort> _currentEfforts = [];
  List<TemplateTarget> _currentTargets = [];

  bool _isLoading = false;
  String? _error;

  RoutineState(this._repository);

  // ===== GETTERS =====

  List<WorkoutTemplate> get routines => List.unmodifiable(_routines);
  WorkoutTemplate? get currentTemplate => _currentTemplate;
  TemplateSegment? get currentSegment => _currentSegment;
  List<TemplateEffort> get currentEfforts => List.unmodifiable(_currentEfforts);
  List<TemplateTarget> get currentTargets => List.unmodifiable(_currentTargets);
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasUnsavedChanges => _currentTemplate != null;

  // ===== ROUTINE MANAGEMENT =====

  /// Load all saved routines from repository
  Future<void> loadRoutines() async {
    _isLoading = true;
    _clearError();
    notifyListeners();

    try {
      _routines = await _repository.getTemplates();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _setError('Failed to load routines: $e');
    }
  }

  /// Create a new blank routine for editing
  Future<void> createNewRoutine(String name) async {
    _clearError();

    try {
      final templateId = 'template-${DateTime.now().millisecondsSinceEpoch}';
      final now = DateTime.now().millisecondsSinceEpoch;

      _currentTemplate = WorkoutTemplate(
        id: templateId,
        name: name,
        createdAtMs: now,
        updatedAtMs: now,
      );

      // Create default segment
      final segmentId = 'tseg-${DateTime.now().millisecondsSinceEpoch}';
      _currentSegment = TemplateSegment(
        id: segmentId,
        templateId: templateId,
        orderIndex: 0,
        segmentType: 'mixed',
        name: 'Exercises',
        createdAtMs: now,
      );

      _currentEfforts = [];
      _currentTargets = [];

      notifyListeners();
    } catch (e) {
      _setError('Failed to create routine: $e');
    }
  }

  /// Update the current routine name
  Future<void> updateRoutineName(String name) async {
    if (_currentTemplate == null) return;

    _clearError();

    try {
      _currentTemplate = _currentTemplate!.copyWith(
        name: name,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      notifyListeners();
    } catch (e) {
      _setError('Failed to update routine name: $e');
    }
  }

  /// Save the current routine to repository
  Future<void> saveRoutine() async {
    if (_currentTemplate == null || _currentSegment == null) return;

    _isLoading = true;
    _clearError();
    notifyListeners();

    try {
      // Save template
      await _repository.createTemplate(_currentTemplate!);

      // Save segment
      await _repository.createTemplateSegment(_currentSegment!);

      // Save all efforts
      for (final effort in _currentEfforts) {
        await _repository.createTemplateEffort(effort);
      }

      // Save all targets
      for (final target in _currentTargets) {
        await _repository.createTemplateTarget(target);
      }

      // Add to local cache
      if (!_routines.any((r) => r.id == _currentTemplate!.id)) {
        _routines = [..._routines, _currentTemplate!];
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _setError('Failed to save routine: $e');
    }
  }

  /// Delete a routine
  Future<void> deleteRoutine(String templateId) async {
    _clearError();

    try {
      await _repository.deleteTemplate(templateId);
      _routines.removeWhere((r) => r.id == templateId);
      notifyListeners();
    } catch (e) {
      _setError('Failed to delete routine: $e');
    }
  }

  /// Load a routine for editing
  Future<void> loadRoutineForEditing(String templateId) async {
    _isLoading = true;
    _clearError();
    notifyListeners();

    try {
      _currentTemplate = await _repository.getTemplateById(templateId);

      if (_currentTemplate == null) {
        _setError('Routine not found');
        return;
      }

      final segments = await _repository.getTemplateSegments(templateId);
      if (segments.isNotEmpty) {
        _currentSegment = segments.first;
        _currentEfforts = await _repository.getTemplateEfforts(segments.first.id);

        _currentTargets = [];
        for (final effort in _currentEfforts) {
          final targets = await _repository.getTemplateTargets(effort.id);
          _currentTargets.addAll(targets);
        }
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _setError('Failed to load routine: $e');
    }
  }

  // ===== EXERCISE MANAGEMENT =====

  /// Add an exercise to the current routine
  Future<String> addExerciseToRoutine(
    Exercise exercise,
    String effortKind,
  ) async {
    if (_currentSegment == null) return '';

    _clearError();

    try {
      final effortId = 'teff-${DateTime.now().millisecondsSinceEpoch}';
      final now = DateTime.now().millisecondsSinceEpoch;

      final effort = TemplateEffort(
        id: effortId,
        templateSegmentId: _currentSegment!.id,
        orderIndex: _currentEfforts.length,
        effortKind: effortKind,
        modality: null,
        exerciseId: exercise.id,
        createdAtMs: now,
      );

      _currentEfforts = [..._currentEfforts, effort];
      notifyListeners();

      return effortId;
    } catch (e) {
      _setError('Failed to add exercise: $e');
      return '';
    }
  }

  /// Remove an exercise from the current routine
  Future<void> removeExerciseFromRoutine(String templateEffortId) async {
    _clearError();

    try {
      _currentEfforts.removeWhere((e) => e.id == templateEffortId);
      _currentTargets.removeWhere((t) => t.templateEffortId == templateEffortId);
      notifyListeners();
    } catch (e) {
      _setError('Failed to remove exercise: $e');
    }
  }

  /// Reorder exercises in the routine
  Future<void> reorderExercises(int oldIndex, int newIndex) async {
    _clearError();

    try {
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }

      final effort = _currentEfforts.removeAt(oldIndex);
      _currentEfforts.insert(newIndex, effort);

      // Update orderIndex values
      for (int i = 0; i < _currentEfforts.length; i++) {
        _currentEfforts[i] = _currentEfforts[i].copyWith(orderIndex: i);
      }

      notifyListeners();
    } catch (e) {
      _setError('Failed to reorder exercises: $e');
    }
  }

  /// Update tracking method for an effort
  Future<void> updateEffortKind(String templateEffortId, String effortKind) async {
    _clearError();

    try {
      final index = _currentEfforts.indexWhere((e) => e.id == templateEffortId);
      if (index == -1) return;

      _currentEfforts[index] = _currentEfforts[index].copyWith(
        effortKind: effortKind,
      );

      notifyListeners();
    } catch (e) {
      _setError('Failed to update tracking: $e');
    }
  }

  // ===== TARGET MANAGEMENT =====

  /// Set or update a target value for an exercise metric
  Future<void> setTargetValue(
    String templateEffortId,
    String metricId,
    String? unitId, {
    int? setIndex,
    int? targetInt,
    double? targetMin,
    double? targetMax,
    String? targetText,
  }) async {
    _clearError();

    try {
      // Check if target already exists
      final existingIndex = _currentTargets.indexWhere(
        (t) =>
            t.templateEffortId == templateEffortId &&
            t.metricId == metricId &&
            t.setIndex == setIndex,
      );

      final now = DateTime.now().millisecondsSinceEpoch;
      final targetId = existingIndex >= 0
          ? _currentTargets[existingIndex].id
          : 'ttar-$now';

      final target = TemplateTarget(
        id: targetId,
        templateEffortId: templateEffortId,
        metricId: metricId,
        setIndex: setIndex,
        unitId: unitId,
        targetInt: targetInt,
        targetMin: targetMin,
        targetMax: targetMax,
        targetText: targetText,
        createdAtMs: existingIndex >= 0
            ? _currentTargets[existingIndex].createdAtMs
            : now,
      );

      if (existingIndex >= 0) {
        _currentTargets[existingIndex] = target;
      } else {
        _currentTargets = [..._currentTargets, target];
      }

      notifyListeners();
    } catch (e) {
      _setError('Failed to set target: $e');
    }
  }

  /// Get targets for a specific effort
  List<TemplateTarget> getEffortTargets(String templateEffortId) {
    return _currentTargets
        .where((t) => t.templateEffortId == templateEffortId)
        .toList();
  }

  /// Get targets for a specific effort and set index
  List<TemplateTarget> getEffortTargetsForSet(
    String templateEffortId,
    int setIndex,
  ) {
    return _currentTargets
        .where(
          (t) =>
              t.templateEffortId == templateEffortId &&
              (t.setIndex ?? 0) == setIndex,
        )
        .toList();
  }

  /// Add a new set for an effort, copying prior values when possible
  Future<void> addSetForEffort(
    String templateEffortId,
    String effortKind,
  ) async {
    _clearError();

    try {
      final targets = getEffortTargets(templateEffortId);
      final lastSetIndex = _getMaxSetIndex(targets);
      final newSetIndex = lastSetIndex + 1;

      final previousTargets = lastSetIndex >= 0
          ? getEffortTargetsForSet(templateEffortId, lastSetIndex)
          : <TemplateTarget>[];

      final defaults = _defaultTargetsForEffortKind(effortKind);

      for (final entry in defaults.entries) {
        final metricId = entry.key;
        final fallbackValue = entry.value;

        final previous = previousTargets.firstWhere(
          (t) => t.metricId == metricId,
          orElse: () => TemplateTarget(
            id: '',
            templateEffortId: templateEffortId,
            metricId: metricId,
            createdAtMs: 0,
          ),
        );

        final value = _targetValueOrDefault(previous, fallbackValue);
        await _setTargetValueInternal(
          templateEffortId,
          metricId,
          newSetIndex,
          value,
        );
      }
    } catch (e) {
      _setError('Failed to add set: $e');
    }
  }

  /// Remove the last set for an effort
  Future<void> removeLastSetForEffort(String templateEffortId) async {
    _clearError();

    try {
      final targets = getEffortTargets(templateEffortId);
      final lastSetIndex = _getMaxSetIndex(targets);
      if (lastSetIndex <= 0) return;

      _currentTargets.removeWhere(
        (t) =>
            t.templateEffortId == templateEffortId &&
            (t.setIndex ?? 0) == lastSetIndex,
      );

      notifyListeners();
    } catch (e) {
      _setError('Failed to remove set: $e');
    }
  }

  // ===== SESSION CREATION =====

  /// Start a routine as a new workout session
  /// This pre-loads exercises, modalities, and targets into a new session
  /// The modality is kept as null (mixed) to show all exercises together
  Future<void> startRoutineAsSession(
    WorkoutState workoutState,
    String templateId,
  ) async {
    _clearError();

    try {
      // Load routine data
      await loadRoutineForEditing(templateId);

      if (_currentTemplate == null || _currentSegment == null) {
        _setError('Failed to load routine');
        return;
      }

      // Create new session with mixed modality (null) and routine intent
      await workoutState.createNewSession(
        modality: null,
        title: _currentTemplate!.name,
        intent: 'routine',
      );
      await workoutState.loadSessionData();

      // Get all exercises and their metadata
      Map<String, Exercise> exerciseCache = {};
      final allExercises = await _repository.getExercises();
      for (final exercise in allExercises) {
        exerciseCache[exercise.id] = exercise;
      }

      // Add each exercise to the session
      for (final effort in _currentEfforts) {
        if (effort.exerciseId != null && exerciseCache.containsKey(effort.exerciseId!)) {
          final exercise = exerciseCache[effort.exerciseId!]!;
          
          final effortId = await workoutState.addExerciseToSession(
            exercise,
            effortKindOverride: effort.effortKind,
          );

          if (effortId.isNotEmpty) {
            final targets = getEffortTargets(effort.id);
            final setCount = _getMaxSetIndex(targets) + 1;

            for (int i = 1; i < setCount; i++) {
              await workoutState.addEntry(effortId);
            }

            for (final target in targets) {
              final entryIndex = target.setIndex ?? 0;
              final metricKey = _metricIdToKey(target.metricId);
              final value = _targetValueForMetric(target);
              if (value == null) continue;

              try {
                await workoutState.updateEntryValue(
                  effortId,
                  entryIndex,
                  metricKey,
                  value,
                );
              } catch (e) {
                // Silently skip if metric doesn't exist for this effort
              }
            }
          }
        }
      }

      notifyListeners();
    } catch (e) {
      _setError('Failed to start routine: $e');
    }
  }

  // ===== HELPERS =====

  /// Map metric ID to the key used in updateEntryValue
  String _metricIdToKey(String metricId) {
    final map = {
      'metric-reps': 'reps',
      'metric-weight': 'weight',
      'metric-duration': 'duration',
      'metric-distance': 'distance',
      'metric-rounds': 'rounds',
      'metric-round-duration': 'round-duration',
      'metric-rpe': 'rpe',
    };
    return map[metricId] ?? metricId;
  }

  Map<String, dynamic> _defaultTargetsForEffortKind(String effortKind) {
    switch (effortKind) {
      case 'set':
        return {
          'metric-reps': 10,
          'metric-weight': 0.0,
        };
      case 'timed':
        return {
          'metric-duration': 0,
        };
      case 'round':
        return {
          'metric-rounds': 1,
          'metric-round-duration': 180,
        };
      case 'drill':
        return {
          'metric-duration': 0,
          'metric-rpe': 5,
        };
      default:
        return {
          'metric-reps': 10,
          'metric-weight': 0.0,
        };
    }
  }

  int _getMaxSetIndex(List<TemplateTarget> targets) {
    if (targets.isEmpty) return 0;
    int maxIndex = 0;
    for (final target in targets) {
      final index = target.setIndex ?? 0;
      if (index > maxIndex) maxIndex = index;
    }
    return maxIndex;
  }

  dynamic _targetValueForMetric(TemplateTarget target) {
    switch (target.metricId) {
      case 'metric-weight':
      case 'metric-distance':
        return target.targetMin ?? target.targetMax ?? target.targetInt?.toDouble();
      default:
        return target.targetInt ?? target.targetMin?.round();
    }
  }

  dynamic _targetValueOrDefault(TemplateTarget target, dynamic fallbackValue) {
    final value = _targetValueForMetric(target);
    return value ?? fallbackValue;
  }

  Future<void> _setTargetValueInternal(
    String templateEffortId,
    String metricId,
    int setIndex,
    dynamic value,
  ) async {
    if (value is double) {
      await setTargetValue(
        templateEffortId,
        metricId,
        null,
        setIndex: setIndex,
        targetMin: value,
      );
      return;
    }

    if (value is int) {
      await setTargetValue(
        templateEffortId,
        metricId,
        null,
        setIndex: setIndex,
        targetInt: value,
      );
    }
  }

  void _setError(String message) {
    _error = message;
    _isLoading = false;
  }

  void _clearError() {
    _error = null;
  }

  /// Clear current routine being edited
  void clearCurrentRoutine() {
    _currentTemplate = null;
    _currentSegment = null;
    _currentEfforts = [];
    _currentTargets = [];
    _clearError();
    notifyListeners();
  }
}

extension on WorkoutTemplate {
  WorkoutTemplate copyWith({
    String? name,
    String? primaryDisciplineId,
    String? note,
    int? updatedAtMs,
  }) {
    return WorkoutTemplate(
      id: id,
      ownerUserId: ownerUserId,
      name: name ?? this.name,
      primaryDisciplineId: primaryDisciplineId ?? this.primaryDisciplineId,
      note: note ?? this.note,
      createdAtMs: createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }
}

extension on TemplateEffort {
  TemplateEffort copyWith({
    int? orderIndex,
    String? effortKind,
    String? modality,
  }) {
    return TemplateEffort(
      id: id,
      templateSegmentId: templateSegmentId,
      orderIndex: orderIndex ?? this.orderIndex,
      effortKind: effortKind ?? this.effortKind,
      modality: modality ?? this.modality,
      exerciseId: exerciseId,
      note: note,
      createdAtMs: createdAtMs,
    );
  }
}
