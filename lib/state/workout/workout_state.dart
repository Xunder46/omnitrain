import 'package:flutter/foundation.dart';

import '../../core/constants/modality_config.dart';
import '../../core/models/routine_session_manifest.dart';
import '../../core/models/session_edit_snapshot.dart';
import '../../core/models/session_summary.dart';
import '../../data/models/models.dart';
import '../../data/repositories/workout_repository.dart';
import 'exercise_library.dart';
import 'session_core.dart';
import 'timer_manager.dart';

/// Thin facade over SessionCore, TimerManager, and ExerciseLibrary.
/// Preserves the full public surface of WorkoutState — no consumer changes needed.
class WorkoutState extends ChangeNotifier {
  final WorkoutRepository _repository;
  late final SessionCore _sessionCore;
  late final TimerManager _timerManager;
  late final ExerciseLibrary _exerciseLibrary;

  String? _error;

  WorkoutState(this._repository) {
    _timerManager = TimerManager(
      _repository,
      notify: notifyListeners,
      setError: _setError,
      clearError: _clearError,
    );
    _exerciseLibrary = ExerciseLibrary(
      _repository,
      notify: notifyListeners,
      setError: _setError,
      clearError: _clearError,
      getCurrentSessionModality: () => _sessionCore.currentSessionModality,
    );
    _sessionCore = SessionCore(
      _repository,
      notify: notifyListeners,
      setError: _setError,
      clearError: _clearError,
      timerManager: _timerManager,
      exerciseLibrary: _exerciseLibrary,
    );
    _timerManager.bindObservations(_sessionCore.observationsMap);
  }

  WorkoutRepository get repository => _repository;
  String? get error => _error;
  TrainingSession? get currentSession => _sessionCore.currentSession;
  ModalityConfig? get modalityConfig => _sessionCore.modalityConfig;
  List<SessionSegment> get segments => _sessionCore.segments;
  bool get isLoading => _sessionCore.isLoading;
  bool get hasSession => _sessionCore.hasSession;
  bool get hasActiveSession => _sessionCore.hasActiveSession;
  bool get isRollingSession => _sessionCore.isRollingSession;
  List<Exercise> get allExercises => _exerciseLibrary.allExercises;
  List<MuscleGroup> get muscleGroups => _exerciseLibrary.muscleGroups;
  List<Discipline> get disciplines => _exerciseLibrary.disciplines;
  bool get shouldShowExerciseNotesHint =>
      _exerciseLibrary.shouldShowExerciseNotesHint;
  bool get shouldShowExerciseInfoHint =>
      _exerciseLibrary.shouldShowExerciseInfoHint;

  List<SegmentEffort> getEffortsForSegment(String segmentId) =>
      _sessionCore.getEffortsForSegment(segmentId);
  List<EffortObservation> getObservationsForEffort(String effortId) =>
      _sessionCore.getObservationsForEffort(effortId);
  List<RoundInstance> getRoundsForEffort(String effortId) =>
      _timerManager.getRoundsForEffort(effortId);
  List<TimedInstance> getTimedInstancesForEffort(String effortId) =>
      _timerManager.getTimedInstancesForEffort(effortId);
  List<EntryRest> getEntryRests(String effortId) =>
      _timerManager.getEntryRests(effortId);
  Exercise? getExercise(String? exerciseId) =>
      _sessionCore.getExercise(exerciseId);
  List<SessionBlock> getSessionBlocks() => _sessionCore.getSessionBlocks();
  List<Map<String, dynamic>> getExercisesWithEntries() =>
      _sessionCore.getExercisesWithEntries();
  SessionSummary computeSessionSummary() =>
      _sessionCore.computeSessionSummary();
  List<SessionTemplateExercise> buildTemplateDraftExercises() =>
      _sessionCore.buildTemplateDraftExercises();
  Future<List<TrainingSession>> getAllSessions() =>
      _sessionCore.getAllSessions();
  Future<List<TrainingSession>> getSessionsByDateRange(int fromMs, int toMs) =>
      _sessionCore.getSessionsByDateRange(fromMs, toMs);
  SessionEditSnapshot? snapshotSessionState() =>
      _sessionCore.snapshotSessionState();

  Future<void> resetSessionTimerStart() =>
      _sessionCore.resetSessionTimerStart();

  Future<void> createNewSession({
    String? modality,
    String? title,
    String? intent,
    String? routineTemplateId,
    bool isRolling = false,
    bool includeDefaultSegment = true,
  }) => _sessionCore.createNewSession(
    modality: modality,
    title: title,
    intent: intent,
    routineTemplateId: routineTemplateId,
    isRolling: isRolling,
    includeDefaultSegment: includeDefaultSegment,
  );
  Future<void> loadHistoricalSession(String sessionId) =>
      _sessionCore.loadHistoricalSession(sessionId);
  Future<void> loadSessionData() => _sessionCore.loadSessionData();
  Future<void> populateSessionFromManifest(RoutineSessionManifest manifest) =>
      _sessionCore.populateSessionFromManifest(manifest);
  Future<void> endSession() => _sessionCore.endSession();
  Future<void> discardCurrentSession() => _sessionCore.discardCurrentSession();
  Future<void> updateSessionNote(String note) =>
      _sessionCore.updateSessionNote(note);
  Future<void> updateSessionEndTime(int durationSecs) =>
      _sessionCore.updateSessionEndTime(durationSecs);
  Future<void> updateSessionFeeling(String sessionId, int feeling) =>
      _sessionCore.updateSessionFeeling(sessionId, feeling);
  Future<void> updateSessionRpe(String sessionId, double rpe) =>
      _sessionCore.updateSessionRpe(sessionId, rpe);
  Future<void> restoreSessionSnapshot(SessionEditSnapshot snapshot) =>
      _sessionCore.restoreSessionSnapshot(snapshot);
  void clearSession() => _sessionCore.clearSession();

  Future<String> addExerciseToSession(
    Exercise exercise, {
    String? chosenMetric,
    String? effortKindOverride,
    String? segmentId,
  }) => _sessionCore.addExerciseToSession(
    exercise,
    chosenMetric: chosenMetric,
    effortKindOverride: effortKindOverride,
    segmentId: segmentId,
  );
  Future<void> addEntry(
    String effortId, {
    Map<String, dynamic>? previousValues,
  }) => _sessionCore.addEntry(effortId, previousValues: previousValues);
  Future<void> updateEntryValue(
    String effortId,
    int entryIndex,
    String metricKey,
    dynamic value,
  ) => _sessionCore.updateEntryValue(effortId, entryIndex, metricKey, value);
  Future<void> markSetSkipped(String effortId, int entryIndex) =>
      _sessionCore.markSetSkipped(effortId, entryIndex);
  Future<void> deleteEntry(String effortId, int entryIndex) =>
      _sessionCore.deleteEntry(effortId, entryIndex);
  Future<void> removeExerciseFromSession(String effortId) =>
      _sessionCore.removeExerciseFromSession(effortId);

  Future<String> addSessionBlock({String? name}) =>
      _sessionCore.addSessionBlock(name: name);
  Future<void> updateSessionBlock(SessionBlock block) =>
      _sessionCore.updateSessionBlock(block);
  Future<void> deleteSessionBlock(String blockId) =>
      _sessionCore.deleteSessionBlock(blockId);
  Future<void> reorderSessionBlocks(List<String> orderedIds) =>
      _sessionCore.reorderSessionBlocks(orderedIds);
  Future<String> cloneSessionBlock(String blockId) =>
      _sessionCore.cloneSessionBlock(blockId);
  Future<void> assignEffortToBlock(String effortId, String? blockId) =>
      _sessionCore.assignEffortToBlock(effortId, blockId);

  Future<void> addRound(String effortId, {int plannedDurationSecs = 180}) =>
      _timerManager.addRound(
        effortId,
        plannedDurationSecs: plannedDurationSecs,
      );
  Future<void> startRound(String effortId, int roundIndex) =>
      _timerManager.startRound(effortId, roundIndex);
  Future<void> pauseRound(String effortId, int roundIndex) =>
      _timerManager.pauseRound(effortId, roundIndex);
  Future<void> resumeRound(String effortId, int roundIndex) =>
      _timerManager.resumeRound(effortId, roundIndex);
  Future<void> completeRound(String effortId, int roundIndex) =>
      _timerManager.completeRound(effortId, roundIndex);
  Future<void> endRoundEarly(String effortId, int roundIndex) =>
      _timerManager.endRoundEarly(effortId, roundIndex);
  Future<void> deleteRound(String effortId, int roundIndex) =>
      _timerManager.deleteRound(effortId, roundIndex);
  Future<void> updateRoundPlannedDuration(
    String effortId,
    int roundIndex,
    int newDurationSecs,
  ) => _timerManager.updateRoundPlannedDuration(
    effortId,
    roundIndex,
    newDurationSecs,
  );

  Future<void> addTimedEntry(String effortId, {int targetDurationSecs = 0}) =>
      _timerManager.addTimedEntry(
        effortId,
        targetDurationSecs: targetDurationSecs,
      );
  Future<void> startTimedEntry(String effortId, int entryIndex) =>
      _timerManager.startTimedEntry(effortId, entryIndex);
  Future<void> pauseTimedEntry(String effortId, int entryIndex) =>
      _timerManager.pauseTimedEntry(effortId, entryIndex);
  Future<void> resumeTimedEntry(String effortId, int entryIndex) =>
      _timerManager.resumeTimedEntry(effortId, entryIndex);
  Future<void> finishTimedEntry(String effortId, int entryIndex) =>
      _timerManager.finishTimedEntry(effortId, entryIndex);
  Future<void> deleteTimedEntry(String effortId, int entryIndex) =>
      _timerManager.deleteTimedEntry(effortId, entryIndex);
  Future<void> updateTimedTargetDuration(
    String effortId,
    int entryIndex,
    int newTargetSecs,
  ) => _timerManager.updateTimedTargetDuration(
    effortId,
    entryIndex,
    newTargetSecs,
  );

  // ── Retrospective edit methods (edit mode only) ──────────────────────────

  /// Sets a timed/drill entry to finished with the given duration.
  /// Intended only for retrospective edits; bypasses live-timer state guards.
  Future<void> setTimedEntryDuration(
    String effortId,
    int entryIndex,
    int durationSecs,
  ) => _timerManager.setTimedInstanceFinished(
    effortId,
    entryIndex,
    durationSecs,
  );

  /// Sets a round instance to finished with the given actual duration.
  /// Intended only for retrospective edits; bypasses live-timer state guards.
  Future<void> setRoundDuration(
    String effortId,
    int roundIndex,
    int durationSecs,
  ) => _timerManager.setRoundFinished(effortId, roundIndex, durationSecs);

  /// Normalises every non-finished round in the current session to `finished`.
  /// Called at the end of edit-mode save to ensure no stale round states remain.
  Future<void> normalizeRoundsToFinished() =>
      _timerManager.normalizeAllRoundsToFinished();

  Future<void> recordRestStart(String effortId, int entryIndex) =>
      _timerManager.recordRestStart(effortId, entryIndex);
  Future<void> recordRestEnd(String effortId, int entryIndex) =>
      _timerManager.recordRestEnd(effortId, entryIndex);
  /// Pauses an open rest record. The wall-clock pause time is captured
  /// on the record so the elapsed display freezes at the pause instant
  /// and reloads correctly across backgrounding. The rest is not
  /// closed — only the counted time stops. See
  /// `TimerManager.pauseRest` for the no-op guards.
  Future<void> pauseRest(String effortId, int entryIndex) =>
      _timerManager.pauseRest(effortId, entryIndex);

  /// Resumes a previously-paused rest. The duration spent paused is
  /// added to the record's accumulated pause time so the recorded
  /// rest duration excludes any stopped interval. See
  /// `TimerManager.resumeRest` for the no-op guards.
  Future<void> resumeRest(String effortId, int entryIndex) =>
      _timerManager.resumeRest(effortId, entryIndex);
  Future<void> closeAllOpenRests(String effortId) =>
      _timerManager.closeAllOpenRests(effortId);
  int getRestElapsedSeconds(String effortId, int entryIndex) =>
      _timerManager.getRestElapsedSeconds(effortId, entryIndex);
  /// Whether the rest record is currently in the paused state. Drives
  /// the rest-tile visual differentiation and the icon swap between
  /// play (tap to resume) and pause (tap to resume is the same).
  bool isRestPaused(String effortId, int entryIndex) =>
      _timerManager.isRestPaused(effortId, entryIndex);
  bool hasRestRecord(String effortId, int entryIndex) =>
      _timerManager.hasRestRecord(effortId, entryIndex);

  Future<void> loadAllExercises() => _exerciseLibrary.loadAllExercises();
  Future<void> loadMuscleGroups() => _exerciseLibrary.loadMuscleGroups();
  Future<void> loadDisciplines() => _exerciseLibrary.loadDisciplines();
  Future<List<Exercise>> searchExercises({
    String? searchText,
    String? disciplineId,
    List<String>? muscleGroupIds,
  }) => _exerciseLibrary.searchExercises(
    searchText: searchText,
    disciplineId: disciplineId,
    muscleGroupIds: muscleGroupIds,
  );
  Future<List<Exercise>> getExercisesRankedForModality({
    String? modality,
    String? searchText,
    String? disciplineId,
    List<String>? muscleGroupIds,
  }) => _exerciseLibrary.getExercisesRankedForModality(
    modality: modality,
    searchText: searchText,
    disciplineId: disciplineId,
    muscleGroupIds: muscleGroupIds,
  );
  Future<List<MuscleGroup>> getExerciseMuscleGroups(String exerciseId) =>
      _exerciseLibrary.getExerciseMuscleGroups(exerciseId);

  Future<Exercise?> createCustomExercise({
    required String name,
    String? modality,
    String? description,
    String? disciplineId,
    List<String> capabilities = const [],
    List<String> muscleGroupIds = const [],
  }) async {
    final exercise = await _exerciseLibrary.createCustomExercise(
      name: name,
      modality: modality,
      description: description,
      disciplineId: disciplineId,
      capabilities: capabilities,
      muscleGroupIds: muscleGroupIds,
    );
    if (exercise != null) _sessionCore.cacheExercise(exercise);
    return exercise;
  }

  Future<Exercise?> updateCustomExercise({
    required Exercise exercise,
    List<String> capabilities = const [],
    List<String> muscleGroupIds = const [],
  }) async {
    final updated = await _exerciseLibrary.updateCustomExercise(
      exercise: exercise,
      capabilities: capabilities,
      muscleGroupIds: muscleGroupIds,
    );
    if (updated != null) _sessionCore.cacheExercise(updated);
    return updated;
  }

  Future<void> loadExerciseNote(String exerciseId) =>
      _exerciseLibrary.loadExerciseNote(exerciseId);
  Future<void> saveExerciseNote(
    String exerciseId,
    String text, {
    String? sessionId,
  }) =>
      _exerciseLibrary.saveExerciseNote(exerciseId, text, sessionId: sessionId);
  ExerciseNote? getExerciseNote(String exerciseId) =>
      _exerciseLibrary.getExerciseNote(exerciseId);
  bool hasExerciseNote(String exerciseId) =>
      _exerciseLibrary.hasExerciseNote(exerciseId);
  Future<void> initExerciseHints() => _exerciseLibrary.initExerciseHints();
  Future<void> markExerciseNotesHintSeen() =>
      _exerciseLibrary.markExerciseNotesHintSeen();
  Future<void> markExerciseInfoHintSeen() =>
      _exerciseLibrary.markExerciseInfoHintSeen();
  Future<void> resetExerciseHintsForTesting() =>
      _exerciseLibrary.resetExerciseHintsForTesting();

  Future<TrainingSession?> checkForInProgressSession() async {
    try {
      final sessions = await _repository.getInProgressSessions();
      if (sessions.isEmpty) return null;

      // Delete older dangling sessions
      for (var i = 1; i < sessions.length; i++) {
        await _repository.deleteSession(sessions[i].id);
      }

      return sessions.first;
    } catch (e) {
      debugPrint('Error checking for in-progress sessions: $e');
      return null;
    }
  }

  void _setError(String message) {
    _error = message;
    notifyListeners();
  }

  void _clearError() => _error = null;
}
