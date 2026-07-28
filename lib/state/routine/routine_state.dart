import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/constants/catalog_version.dart';
import '../../data/models/models.dart';
import '../../data/repositories/workout_repository.dart';
import '../../core/constants/effort_defaults.dart';
import '../../core/constants/workout_constants.dart';

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
  List<TemplateSegment> _currentSegments = [];
  final Map<String, List<TemplateEffort>> _segmentEfforts = {};
  List<TemplateTarget> _currentTargets = [];

  /// Cache of exercises keyed by exercise ID.
  /// Populated when an exercise is added to the routine, or when a routine is
  /// loaded for editing. Used to look up Exercise.defaultRoundDurationSecs so
  /// that the first set of a round-based effort starts with the sport-correct
  /// period/half/round length rather than the generic 3-min boxing default.
  final Map<String, Exercise> _exerciseCache = {};

  Timer? _autosaveTimer;
  bool _autosaveEnabled = true;

  bool _isLoading = false;
  String? _error;

  /// Immutable snapshot of the routine hierarchy at the moment the user
  /// opened the editor (or last saved). The unsaved-changes guard compares
  /// the working state against this snapshot; any divergence marks the
  /// routine as dirty.
  ///
  /// `originalTemplateId == null` indicates the snapshot was taken on a
  /// brand-new routine that has not yet been persisted; the first time we
  /// capture a baseline for a new routine we also persist the template so
  /// that `discardCurrentRoutine` can cleanly remove it from the
  /// repository.
  RoutineSnapshot? _baseline;

  /// True when the working routine has been opened as a new (unsaved)
  /// template — `discardCurrentRoutine` must remove the template from the
  /// repository because `_persistDraft` already writes it on the first
  /// edit.
  bool _isNewRoutine = false;

  RoutineState(this._repository);

  // ===== GETTERS =====

  List<WorkoutTemplate> get routines => List.unmodifiable(_routines);
  WorkoutTemplate? get currentTemplate => _currentTemplate;
  List<TemplateSegment> get currentSegments =>
      List.unmodifiable(_currentSegments);
  List<TemplateEffort> get currentEfforts =>
      List.unmodifiable(_flattenedEfforts());
  List<TemplateTarget> get currentTargets => List.unmodifiable(_currentTargets);
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// True when the working routine differs from the snapshot captured at
  /// editor entry (or last successful save). The UI uses this to gate the
  /// unsaved-changes confirmation dialog.
  bool get hasUnsavedChanges {
    if (_currentTemplate == null) return false;
    final baseline = _baseline;
    if (baseline == null) return false;
    return !_matchesBaseline(baseline);
  }

  /// Snapshot helpers exposed for the UI to orchestrate the
  /// unsaved-changes guard. The capture happens automatically inside
  /// [createNewRoutine], [loadRoutineForEditing], and
  /// [resetBaselineAfterSave]; callers rarely need to invoke these
  /// directly.
  void captureBaseline() {
    _baseline = RoutineSnapshot.fromState(
      _currentTemplate,
      _currentSegments,
      _segmentEfforts,
      _currentTargets,
    );
  }

  void resetBaselineAfterSave() {
    _isNewRoutine = false;
    captureBaseline();
  }

  void setAutosaveEnabled(bool enabled) {
    _autosaveEnabled = enabled;
    if (!enabled) {
      _autosaveTimer?.cancel();
    }
  }

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
      final defaultSegment = TemplateSegment(
        id: segmentId,
        templateId: templateId,
        orderIndex: 0,
        segmentType: 'main',
        name: 'Main Block',
        createdAtMs: now,
        updatedAtMs: now,
      );

      _currentSegments = [defaultSegment];
      _segmentEfforts.clear();
      _segmentEfforts[segmentId] = [];
      _currentTargets = [];
      _exerciseCache.clear();

      _isNewRoutine = true;
      captureBaseline();
      _scheduleAutosave();
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
      _scheduleAutosave();
      notifyListeners();
    } catch (e) {
      _setError('Failed to update routine name: $e');
    }
  }

  /// Update the current routine description
  Future<void> updateRoutineDescription(String description) async {
    if (_currentTemplate == null) return;

    _clearError();

    try {
      _currentTemplate = _currentTemplate!.copyWith(
        description: description,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      _scheduleAutosave();
      notifyListeners();
    } catch (e) {
      _setError('Failed to update routine description: $e');
    }
  }

  /// Update the routine focus modality
  Future<void> updateRoutineFocusModality(String? modality) async {
    if (_currentTemplate == null) return;

    _clearError();

    try {
      _currentTemplate = _currentTemplate!.copyWith(
        focusModality: modality,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      _scheduleAutosave();
      notifyListeners();
    } catch (e) {
      _setError('Failed to update routine focus: $e');
    }
  }

  /// Save the current routine to repository
  Future<void> saveRoutine() async {
    if (_currentTemplate == null || _currentSegments.isEmpty) return;

    _isLoading = true;
    _clearError();
    notifyListeners();

    try {
      // Save template
      await _repository.createTemplate(_currentTemplate!);

      // Save segments and efforts
      for (final segment in _currentSegments) {
        await _repository.createTemplateSegment(segment);
        final efforts = _segmentEfforts[segment.id] ?? [];
        for (final effort in efforts) {
          await _repository.createTemplateEffort(effort);
        }
      }

      // Save all targets
      for (final target in _currentTargets) {
        await _repository.createTemplateTarget(target);
      }

      // Add to local cache
      if (!_routines.any((r) => r.id == _currentTemplate!.id)) {
        _routines = [..._routines, _currentTemplate!];
      }

      // Successful save resets the dirty baseline so the next exit does
      // not re-prompt. The routine is now an "existing" routine.
      _isNewRoutine = false;
      captureBaseline();

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _setError('Failed to save routine: $e');
    }
  }

  /// Delete a routine
  ///
  /// When the deleted routine is a built-in demo, the routine-template
  /// tombstone is set on the repository so the next catalog refresh
  /// doesn't resurrect it (see `SeedEntryType.routineTemplate`).
  Future<void> deleteRoutine(String templateId) async {
    _clearError();

    try {
      final existing = await _repository.getTemplateById(templateId);
      final isDemo = existing?.isBuiltInDemo ?? false;

      // Cascade-delete: remove all planned sessions linked to this template.
      await _repository.deletePlannedSessionsByTemplateId(templateId);

      await _repository.deleteTemplate(templateId);
      if (isDemo) {
        // Persist the user's deletion choice across the next catalog bump.
        await _repository.markSeedEntryTouched(
          SeedEntryType.routineTemplate,
          templateId,
        );
      }
      _routines.removeWhere((r) => r.id == templateId);
      notifyListeners();
    } catch (e) {
      _setError('Failed to delete routine: $e');
    }
  }

  /// Count planned sessions linked to a template (for delete warning UI).
  Future<int> countPlannedSessionsForTemplate(String templateId) async {
    try {
      final sessions = await _repository.getPlannedSessionsByTemplateId(
        templateId,
      );
      return sessions.length;
    } catch (e) {
      return 0;
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
      _currentSegments = segments;
      _segmentEfforts.clear();
      _currentTargets = [];
      _exerciseCache.clear();

      for (final segment in segments) {
        final efforts = await _repository.getTemplateEfforts(segment.id);
        _segmentEfforts[segment.id] = efforts;

        for (final effort in efforts) {
          final targets = await _repository.getTemplateTargets(effort.id);
          _currentTargets.addAll(targets);

          // Pre-load the exercise into the cache so defaultRoundDurationSecs
          // is available when the user adds sets to round-based efforts.
          if (effort.exerciseId != null &&
              !_exerciseCache.containsKey(effort.exerciseId)) {
            final ex = await _repository.getExerciseById(effort.exerciseId!);
            if (ex != null) _exerciseCache[ex.id] = ex;
          }
        }
      }

      if (_currentSegments.isEmpty) {
        final now = DateTime.now().millisecondsSinceEpoch;
        _currentSegments = [
          TemplateSegment(
            id: 'tseg-$now',
            templateId: templateId,
            orderIndex: 0,
            segmentType: 'main',
            name: 'Main Block',
            createdAtMs: now,
            updatedAtMs: now,
          ),
        ];
        _segmentEfforts[_currentSegments.first.id] = [];
      }

      _isNewRoutine = false;
      captureBaseline();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _setError('Failed to load routine: $e');
    }
  }

  // ===== EXERCISE MANAGEMENT =====

  /// Get efforts for a specific segment
  List<TemplateEffort> getEffortsForSegment(String segmentId) {
    return List.unmodifiable(_segmentEfforts[segmentId] ?? []);
  }

  /// Get the segment that owns a specific effort
  TemplateSegment? getSegmentForEffort(String effortId) {
    for (final segment in _currentSegments) {
      final efforts = _segmentEfforts[segment.id] ?? [];
      if (efforts.any((e) => e.id == effortId)) return segment;
    }
    return null;
  }

  /// Add a new segment (block) to the routine
  Future<String> addSegment({String? name, String segmentType = 'main'}) async {
    if (_currentTemplate == null) return '';

    _clearError();

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final segmentId = 'tseg-$now';
      final segment = TemplateSegment(
        id: segmentId,
        templateId: _currentTemplate!.id,
        orderIndex: _currentSegments.length,
        segmentType: segmentType,
        name: name ?? 'Block ${_currentSegments.length + 1}',
        createdAtMs: now,
        updatedAtMs: now,
      );

      _currentSegments = [..._currentSegments, segment];
      _segmentEfforts[segmentId] = [];
      _scheduleAutosave();
      notifyListeners();
      return segmentId;
    } catch (e) {
      _setError('Failed to add block: $e');
      return '';
    }
  }

  /// Update segment metadata
  Future<void> updateSegment(
    String segmentId, {
    String? name,
    String? segmentType,
  }) async {
    _clearError();

    try {
      final index = _currentSegments.indexWhere((s) => s.id == segmentId);
      if (index == -1) return;

      final segment = _currentSegments[index];
      _currentSegments[index] = segment.copyWith(
        name: name ?? segment.name,
        segmentType: segmentType ?? segment.segmentType,
      );
      _scheduleAutosave();
      notifyListeners();
    } catch (e) {
      _setError('Failed to update block: $e');
    }
  }

  /// Remove a segment and its efforts
  Future<void> removeSegment(String segmentId) async {
    _clearError();

    try {
      if (_currentSegments.length <= 1) return;

      _currentSegments.removeWhere((s) => s.id == segmentId);
      final removedEfforts = _segmentEfforts.remove(segmentId) ?? [];
      for (final effort in removedEfforts) {
        _currentTargets.removeWhere((t) => t.templateEffortId == effort.id);
      }

      for (int i = 0; i < _currentSegments.length; i++) {
        _currentSegments[i] = _currentSegments[i].copyWith(orderIndex: i);
      }

      _scheduleAutosave();
      notifyListeners();
    } catch (e) {
      _setError('Failed to remove block: $e');
    }
  }

  /// Clone a segment (block) by appending a copy to the end with
  /// all efforts and targets deep-cloned under new IDs.
  Future<void> cloneSegment(String segmentId) async {
    _clearError();
    try {
      final sourceIndex = _currentSegments.indexWhere((s) => s.id == segmentId);
      if (sourceIndex == -1) return;
      final source = _currentSegments[sourceIndex];

      // Derive clone name: "Main" → "Main (2)", "Main (2)" → "Main (3)"
      final rawName = source.name ?? 'Block ${sourceIndex + 1}';
      final suffixMatch = RegExp(r'^(.*) \((\d+)\)$').firstMatch(rawName);
      final cloneName = suffixMatch != null
          ? '${suffixMatch.group(1)!} (${int.parse(suffixMatch.group(2)!) + 1})'
          : '$rawName (2)';

      final now = DateTime.now().millisecondsSinceEpoch;
      final newSegmentId = 'tseg-clone-$now';
      final clonedSegment = TemplateSegment(
        id: newSegmentId,
        templateId: source.templateId,
        orderIndex: sourceIndex + 1, // will be re-indexed below
        segmentType: source.segmentType,
        name: cloneName,
        createdAtMs: now,
        updatedAtMs: now,
      );

      // Append cloned segment to the end, then re-index all.
      final newSegments = [..._currentSegments];
      newSegments.add(clonedSegment);
      for (int i = 0; i < newSegments.length; i++) {
        newSegments[i] = newSegments[i].copyWith(orderIndex: i);
      }
      _currentSegments = newSegments;
      _segmentEfforts[newSegmentId] = [];

      // Deep-clone efforts and their targets.
      final sourceEfforts = _segmentEfforts[segmentId] ?? [];
      for (final effort in sourceEfforts) {
        final newEffortId = 'teff-clone-$now-${effort.id}';
        final clonedEffort = TemplateEffort(
          id: newEffortId,
          templateSegmentId: newSegmentId,
          orderIndex: effort.orderIndex,
          effortKind: effort.effortKind,
          modality: effort.modality,
          exerciseId: effort.exerciseId,
          note: effort.note,
          restSeconds: effort.restSeconds,
          restType: effort.restType,
          createdAtMs: now,
        );
        _segmentEfforts[newSegmentId]!.add(clonedEffort);

        // Clone all targets for this effort (values intact — template context).
        final sourceTargets = _currentTargets
            .where((t) => t.templateEffortId == effort.id)
            .toList();
        for (final target in sourceTargets) {
          final clonedTarget = TemplateTarget(
            id: 'ttgt-clone-$now-${target.id}',
            templateEffortId: newEffortId,
            metricId: target.metricId,
            setIndex: target.setIndex,
            unitId: target.unitId,
            targetMin: target.targetMin,
            targetMax: target.targetMax,
            targetInt: target.targetInt,
            targetText: target.targetText,
            createdAtMs: now,
            updatedAtMs: now,
          );
          _currentTargets.add(clonedTarget);
        }
      }

      _scheduleAutosave();
      notifyListeners();
    } catch (e) {
      _setError('Failed to clone block: $e');
    }
  }

  /// Reorder segments
  Future<void> reorderSegments(int oldIndex, int newIndex) async {
    _clearError();

    try {
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }

      final segment = _currentSegments.removeAt(oldIndex);
      _currentSegments.insert(newIndex, segment);

      for (int i = 0; i < _currentSegments.length; i++) {
        _currentSegments[i] = _currentSegments[i].copyWith(orderIndex: i);
      }

      _scheduleAutosave();
      notifyListeners();
    } catch (e) {
      _setError('Failed to reorder blocks: $e');
    }
  }

  /// Add an exercise to the current routine
  Future<String> addExerciseToRoutine(
    Exercise exercise,
    String effortKind, {
    String? segmentId,
  }) async {
    if (_currentSegments.isEmpty) return '';

    _clearError();

    try {
      final resolvedSegmentId = segmentId ?? _currentSegments.first.id;
      final segmentEfforts = _segmentEfforts[resolvedSegmentId] ?? [];
      final now = DateTime.now().millisecondsSinceEpoch;
      final effortId = 'teff-$now-${segmentEfforts.length}';
      final effort = TemplateEffort(
        id: effortId,
        templateSegmentId: resolvedSegmentId,
        orderIndex: segmentEfforts.length,
        effortKind: effortKind,
        modality: null,
        exerciseId: exercise.id,
        createdAtMs: now,
      );

      _segmentEfforts[resolvedSegmentId] = [...segmentEfforts, effort];

      // Cache the exercise so addSetForEffort can read defaultRoundDurationSecs.
      _exerciseCache[exercise.id] = exercise;

      _scheduleAutosave();
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
      for (final entry in _segmentEfforts.entries) {
        entry.value.removeWhere((e) => e.id == templateEffortId);
      }
      _currentTargets.removeWhere(
        (t) => t.templateEffortId == templateEffortId,
      );
      _scheduleAutosave();
      notifyListeners();
    } catch (e) {
      _setError('Failed to remove exercise: $e');
    }
  }

  /// Reorder exercises in the routine
  Future<void> reorderExercises(
    String segmentId,
    int oldIndex,
    int newIndex,
  ) async {
    _clearError();

    try {
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }

      final efforts = _segmentEfforts[segmentId] ?? [];
      if (oldIndex < 0 || oldIndex >= efforts.length) return;
      final effort = efforts.removeAt(oldIndex);
      efforts.insert(newIndex, effort);

      // Update orderIndex values
      for (int i = 0; i < efforts.length; i++) {
        efforts[i] = efforts[i].copyWith(orderIndex: i);
      }
      _segmentEfforts[segmentId] = efforts;

      _scheduleAutosave();
      notifyListeners();
    } catch (e) {
      _setError('Failed to reorder exercises: $e');
    }
  }

  /// Update tracking method for an effort
  Future<void> updateEffortKind(
    String templateEffortId,
    String effortKind,
  ) async {
    _clearError();

    try {
      bool updated = false;
      for (final entry in _segmentEfforts.entries) {
        final list = entry.value;
        final index = list.indexWhere((e) => e.id == templateEffortId);
        if (index == -1) continue;
        list[index] = list[index].copyWith(effortKind: effortKind);
        _segmentEfforts[entry.key] = list;
        updated = true;
        break;
      }

      if (!updated) return;

      _scheduleAutosave();
      notifyListeners();
    } catch (e) {
      _setError('Failed to update tracking: $e');
    }
  }

  /// Update rest configuration for an effort
  Future<void> updateEffortRest(
    String templateEffortId, {
    int? restSeconds,
    String? restType,
  }) async {
    _clearError();

    try {
      bool updated = false;
      for (final entry in _segmentEfforts.entries) {
        final list = entry.value;
        final index = list.indexWhere((e) => e.id == templateEffortId);
        if (index == -1) continue;
        list[index] = list[index].copyWith(
          restSeconds: restSeconds,
          restType: restType,
        );
        _segmentEfforts[entry.key] = list;
        updated = true;
        break;
      }

      if (!updated) return;
      _scheduleAutosave();
      notifyListeners();
    } catch (e) {
      _setError('Failed to update rest: $e');
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
          : _buildTargetId(templateEffortId, metricId, setIndex);

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
        updatedAtMs: now,
      );

      if (existingIndex >= 0) {
        _currentTargets[existingIndex] = target;
      } else {
        _currentTargets = [..._currentTargets, target];
      }

      _scheduleAutosave();
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
      final currentSetCount = targets.isEmpty
          ? 1
          : (_getMaxSetIndex(targets) + 1);
      if (currentSetCount >= WorkoutConstants.maxEntriesPerEffort) {
        return;
      }

      final lastSetIndex = currentSetCount - 1;
      final newSetIndex = currentSetCount;

      final previousTargets = lastSetIndex >= 0
          ? getEffortTargetsForSet(templateEffortId, lastSetIndex)
          : <TemplateTarget>[];

      // Look up the exercise-specific default round duration (sport period length)
      // so the first set of a round effort starts with the correct default rather
      // than the generic 3-min boxing fallback.
      final exerciseId = _findEffortById(templateEffortId)?.exerciseId;
      final exerciseDefault = exerciseId != null
          ? _exerciseCache[exerciseId]?.defaultRoundDurationSecs
          : null;

      final defaults = _defaultTargetsForEffortKind(
        effortKind,
        exerciseDefaultRoundDurationSecs: exerciseDefault,
      );

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
            updatedAtMs: 0,
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

      _scheduleAutosave();
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

      _scheduleAutosave();
      notifyListeners();
    } catch (e) {
      _setError('Failed to remove set: $e');
    }
  }

  // ===== HELPERS =====

  /// Flat-search _segmentEfforts for an effort with a given ID.
  TemplateEffort? _findEffortById(String templateEffortId) {
    for (final efforts in _segmentEfforts.values) {
      for (final e in efforts) {
        if (e.id == templateEffortId) return e;
      }
    }
    return null;
  }

  /// Get default targets for an effort kind.
  /// Pass [exerciseDefaultRoundDurationSecs] to override the global 3-min
  /// boxing default for sport exercises (e.g. 2700 s for a soccer half).
  Map<String, dynamic> _defaultTargetsForEffortKind(
    String effortKind, {
    int? exerciseDefaultRoundDurationSecs,
  }) {
    return EffortDefaults.getDefaultTargets(
      effortKind,
      exerciseDefaultRoundDurationSecs: exerciseDefaultRoundDurationSecs,
    );
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

  String _buildTargetId(
    String templateEffortId,
    String metricId,
    int? setIndex,
  ) {
    final micros = DateTime.now().microsecondsSinceEpoch;
    final safeMetric = metricId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final safeEffort = templateEffortId.replaceAll(
      RegExp(r'[^a-zA-Z0-9_-]'),
      '_',
    );
    return 'ttar-$safeEffort-$safeMetric-${setIndex ?? 0}-$micros';
  }

  dynamic _targetValueForMetric(TemplateTarget target) {
    switch (target.metricId) {
      case 'metric-weight':
      case 'metric-distance':
        return target.targetMin ??
            target.targetMax ??
            target.targetInt?.toDouble();
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

  List<TemplateEffort> _flattenedEfforts() {
    final orderedSegments = [..._currentSegments]
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    final result = List<TemplateEffort>.empty(growable: true);

    for (final segment in orderedSegments) {
      final efforts =
          [
              ...(_segmentEfforts[segment.id] ?? <TemplateEffort>[]),
            ].cast<TemplateEffort>()
            ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      result.addAll(efforts);
    }

    return result;
  }

  void _scheduleAutosave() {
    if (!_autosaveEnabled) return;
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 600), () async {
      await _persistDraft();
    });
  }

  Future<void> _persistDraft() async {
    if (_currentTemplate == null) return;

    try {
      // Persist top-level template (no-op on re-save because the
      // repository upserts by id).
      await _repository.createTemplate(_currentTemplate!);

      // User edits to a built-in demo must survive the next catalog
      // refresh. Setting the tombstone here is idempotent and only
      // applies to demos — user-created routines are untouched.
      if (_currentTemplate!.isBuiltInDemo) {
        await _repository.markSeedEntryTouched(
          SeedEntryType.routineTemplate,
          _currentTemplate!.id,
        );
      }

      final existingSegments = await _repository.getTemplateSegments(
        _currentTemplate!.id,
      );
      final currentSegmentIds = _currentSegments.map((s) => s.id).toSet();
      for (final segment in existingSegments) {
        if (!currentSegmentIds.contains(segment.id)) {
          await _repository.deleteTemplateSegment(segment.id);
        }
      }

      for (final segment in _currentSegments) {
        await _repository.createTemplateSegment(segment);
        final existingEfforts = await _repository.getTemplateEfforts(
          segment.id,
        );
        final currentEfforts = _segmentEfforts[segment.id] ?? [];
        final currentEffortIds = currentEfforts.map((e) => e.id).toSet();

        for (final effort in existingEfforts) {
          if (!currentEffortIds.contains(effort.id)) {
            await _repository.deleteTemplateEffort(effort.id);
          }
        }

        for (final effort in currentEfforts) {
          await _repository.createTemplateEffort(effort);

          final existingTargets = await _repository.getTemplateTargets(
            effort.id,
          );
          final currentTargets = getEffortTargets(effort.id);
          final currentTargetIds = currentTargets.map((t) => t.id).toSet();

          for (final target in existingTargets) {
            if (!currentTargetIds.contains(target.id)) {
              await _repository.deleteTemplateTarget(target.id);
            }
          }

          for (final target in currentTargets) {
            await _repository.createTemplateTarget(target);
          }
        }
      }
    } catch (_) {
      // Autosave failures should not block the UI.
    }
  }

  void _clearError() {
    _error = null;
  }

  /// Clear current routine being edited WITHOUT touching the repository.
  ///
  /// Use this when the user discards a brand-new routine so we drop the
  /// in-memory working state that has not yet been confirmed by an
  /// explicit save. The repository is left as-is (no autosave leak).
  void discardCurrentRoutine() => _clearInMemoryState();

  /// Clear current routine being edited.
  ///
  /// On save, downstream store operations already persisted the routine —
  /// the baseline is reset so the next exit does not re-prompt. This
  /// method exists for symmetry with the pre-PR-5 contract and is the
  /// routine called by the save and direct-pop flows.
  void clearCurrentRoutine() => _clearInMemoryState();

  /// Drop every piece of in-memory routine state and notify listeners.
  /// Shared by [discardCurrentRoutine] and [clearCurrentRoutine] (the
  /// discard path additionally removes the persisted draft via
  /// [discardCurrentRoutineAndClearDraft]). The repository is not
  /// touched here.
  void _clearInMemoryState() {
    _currentTemplate = null;
    _currentSegments = [];
    _segmentEfforts.clear();
    _currentTargets = [];
    _exerciseCache.clear();
    _autosaveTimer?.cancel();
    _baseline = null;
    _isNewRoutine = false;
    _clearError();
    notifyListeners();
  }

  /// Cancel any pending autosave draft so a quick back-out does not leak
  /// the in-flight draft onto disk. Idempotent.
  void cancelPendingAutosave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
  }

  // ===== DIRTY-STATE COMPARISON =====

  /// Persist a routine that was authored from scratch so that the
  /// repository has a record to delete on discard. The autosave pipeline
  /// already does this lazily, but the dirty guard runs before the timer
  /// has fired, so we explicitly mark the template as dirty and force a
  /// synchronous persist when the user discards a new routine.
  Future<void> _persistDraftForDiscard() async {
    if (_currentTemplate == null) return;
    try {
      await _repository.createTemplate(_currentTemplate!);
    } catch (_) {
      // Best-effort: missing draft is fine; the repository is the source
      // of truth and `deleteTemplate` is a no-op when the id is absent.
    }
  }

  /// Discard the working routine and remove any draft that was persisted
  /// for a brand-new routine. Existing routines are not touched — the
  /// autosave diff in [_persistDraft] has already restored them via
  /// `deleteTemplate*` for the changes the user subsequently reverted,
  /// so the repository state matches the baseline-by-construction.
  Future<void> discardCurrentRoutineAndClearDraft() async {
    cancelPendingAutosave();
    if (_isNewRoutine && _currentTemplate != null) {
      await _persistDraftForDiscard();
      try {
        await _repository.deleteTemplate(_currentTemplate!.id);
      } catch (_) {
        // Best-effort cleanup.
      }
    }
    discardCurrentRoutine();
  }

  bool _matchesBaseline(RoutineSnapshot baseline) {
    final template = _currentTemplate;
    if (template == null) return false;

    // ── Template-level fields ─────────────────────────────────────────────
    if (template.name != baseline.templateName) return false;
    if (template.description != baseline.templateDescription) return false;
    if (template.focusModality != baseline.templateFocusModality) return false;

    // ── Segments ─────────────────────────────────────────────────────────
    final currentSegments = [..._currentSegments]
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    final baselineSegments = baseline.segmentsSortedByOrder;
    if (currentSegments.length != baselineSegments.length) return false;
    for (var i = 0; i < currentSegments.length; i++) {
      final cur = currentSegments[i];
      final base = baselineSegments[i];
      if (cur.id != base.id) return false;
      if (cur.name != base.name) return false;
      if (cur.segmentType != base.segmentType) return false;
    }

    // ── Efforts per segment ───────────────────────────────────────────────
    for (final segment in currentSegments) {
      final currentEfforts = [...?_segmentEfforts[segment.id]]
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      final baselineEfforts = baseline.effortsBySegment[segment.id] ?? const [];
      if (currentEfforts.length != baselineEfforts.length) return false;
      for (var i = 0; i < currentEfforts.length; i++) {
        final cur = currentEfforts[i];
        final base = baselineEfforts[i];
        if (cur.id != base.id) return false;
        if (cur.effortKind != base.effortKind) return false;
        if (cur.exerciseId != base.exerciseId) return false;
        if (cur.restSeconds != base.restSeconds) return false;
        if (cur.restType != base.restType) return false;
      }
    }

    // ── Targets per effort ────────────────────────────────────────────────
    final currentTargetsByEffort = <String, List<TemplateTarget>>{};
    for (final target in _currentTargets) {
      currentTargetsByEffort
          .putIfAbsent(target.templateEffortId, () => [])
          .add(target);
    }
    for (final entry in currentTargetsByEffort.entries) {
      entry.value.sort((a, b) {
        final idx = (a.setIndex ?? 0).compareTo(b.setIndex ?? 0);
        if (idx != 0) return idx;
        return a.metricId.compareTo(b.metricId);
      });
    }

    if (currentTargetsByEffort.length != baseline.targetsByEffort.length) {
      return false;
    }
    for (final entry in currentTargetsByEffort.entries) {
      final base = baseline.targetsByEffort[entry.key] ?? const [];
      if (entry.value.length != base.length) return false;
      for (var i = 0; i < entry.value.length; i++) {
        final cur = entry.value[i];
        final bs = base[i];
        if ((cur.setIndex ?? 0) != (bs.setIndex ?? 0)) return false;
        if (cur.metricId != bs.metricId) return false;
        if (cur.unitId != bs.unitId) return false;
        if (cur.targetInt != bs.targetInt) return false;
        if (cur.targetMin != bs.targetMin) return false;
        if (cur.targetMax != bs.targetMax) return false;
        if (cur.targetText != bs.targetText) return false;
      }
    }

    return true;
  }
}

// WorkoutTemplate.copyWith is provided by the model itself
// (`lib/data/models/models.dart`).

extension on TemplateSegment {
  TemplateSegment copyWith({
    int? orderIndex,
    String? segmentType,
    String? name,
  }) {
    return TemplateSegment(
      id: id,
      templateId: templateId,
      orderIndex: orderIndex ?? this.orderIndex,
      segmentType: segmentType ?? this.segmentType,
      disciplineId: disciplineId,
      name: name ?? this.name,
      note: note,
      createdAtMs: createdAtMs,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }
}

extension on TemplateEffort {
  TemplateEffort copyWith({
    int? orderIndex,
    String? effortKind,
    String? modality,
    int? restSeconds,
    String? restType,
  }) {
    return TemplateEffort(
      id: id,
      templateSegmentId: templateSegmentId,
      orderIndex: orderIndex ?? this.orderIndex,
      effortKind: effortKind ?? this.effortKind,
      modality: modality ?? this.modality,
      exerciseId: exerciseId,
      note: note,
      restSeconds: restSeconds ?? this.restSeconds,
      restType: restType ?? this.restType,
      createdAtMs: createdAtMs,
    );
  }
}

/// Immutable baseline snapshot of a routine hierarchy. The
/// unsaved-changes guard compares the live working state against an
/// instance of this class to decide whether the user has touched
/// anything that warrants a confirmation prompt.
///
/// The snapshot captures the user-visible, semantically-relevant fields
/// of the template, segments, efforts, and targets. Server-side fields
/// like `ownerUserId`, `createdAtMs`, or `updatedAtMs` are intentionally
/// not captured — those are managed by the model layer and are not what
/// the user is editing.
@immutable
class RoutineSnapshot {
  final String? templateName;
  final String? templateDescription;
  final String? templateFocusModality;
  final List<TemplateSegment> _segments;
  final Map<String, List<TemplateEffort>> _effortsBySegment;
  final Map<String, List<TemplateTarget>> _targetsByEffort;

  const RoutineSnapshot._({
    required this.templateName,
    required this.templateDescription,
    required this.templateFocusModality,
    required List<TemplateSegment> segments,
    required Map<String, List<TemplateEffort>> effortsBySegment,
    required Map<String, List<TemplateTarget>> targetsByEffort,
  })  : _segments = segments,
        _effortsBySegment = effortsBySegment,
        _targetsByEffort = targetsByEffort;

  factory RoutineSnapshot.fromState(
    WorkoutTemplate? template,
    List<TemplateSegment> segments,
    Map<String, List<TemplateEffort>> effortsBySegment,
    List<TemplateTarget> targets,
  ) {
    if (template == null) {
      return const RoutineSnapshot._(
        templateName: null,
        templateDescription: null,
        templateFocusModality: null,
        segments: <TemplateSegment>[],
        effortsBySegment: <String, List<TemplateEffort>>{},
        targetsByEffort: <String, List<TemplateTarget>>{},
      );
    }

    final sortedSegments = [...segments]
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

    final efforts = <String, List<TemplateEffort>>{};
    for (final segment in sortedSegments) {
      final source = effortsBySegment[segment.id] ?? const <TemplateEffort>[];
      final list = <TemplateEffort>[...source]
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      efforts[segment.id] = list;
    }

    final targetsByEffort = <String, List<TemplateTarget>>{};
    for (final target in targets) {
      targetsByEffort
          .putIfAbsent(target.templateEffortId, () => [])
          .add(target);
    }
    for (final entry in targetsByEffort.entries) {
      entry.value.sort((a, b) {
        final idx = (a.setIndex ?? 0).compareTo(b.setIndex ?? 0);
        if (idx != 0) return idx;
        return a.metricId.compareTo(b.metricId);
      });
    }

    return RoutineSnapshot._(
      templateName: template.name,
      templateDescription: template.description,
      templateFocusModality: template.focusModality,
      segments: sortedSegments,
      effortsBySegment: efforts,
      targetsByEffort: targetsByEffort,
    );
  }

  List<TemplateSegment> get segmentsSortedByOrder =>
      List.unmodifiable(_segments);

  Map<String, List<TemplateEffort>> get effortsBySegment =>
      Map.unmodifiable(_effortsBySegment);

  Map<String, List<TemplateTarget>> get targetsByEffort =>
      Map.unmodifiable(_targetsByEffort);
}
