import 'dart:math' as math;

import '../../core/constants/metric_ids.dart';
import '../../core/constants/modality_config.dart';
import '../../core/constants/workout_constants.dart';
import '../../core/models/routine_session_manifest.dart';
import '../../core/models/session_edit_snapshot.dart';
import '../../core/models/session_summary.dart';
import '../../core/services/health_sync_service.dart';
import '../../core/utils/entry_rows.dart';
import '../../core/utils/logged_entry_rows.dart';
import '../../data/models/models.dart';
import '../../data/repositories/workout_repository.dart';
import '../watch/watch_session_inbox.dart';
import 'exercise_library.dart';
import 'session_block_manager.dart';
import 'session_summary_builder.dart';
import 'timer_manager.dart';

part 'session_core_io.dart';
part 'session_core_entry.dart';
part 'session_core_lifecycle.dart';

/// SessionCore manages the session lifecycle, segment/effort/observation CRUD operations, and state snapshots.
///
/// **Sync Seam Integration (Forward-Looking):**
/// The sync seam belongs to SessionCore. Cloud sync must intercept after successful writes to the
/// local repository: session create/end/update, effort create/delete, observation create/update/delete.
///
/// **Future Pattern:**
/// ```
/// // SyncService will be injected into SessionCore at construction time:
/// // SessionCore(_repository, syncService: SyncService?, notify: ..., ...)
/// //
/// // After each repository write, queue the change for sync:
/// // await _repository.createSession(session);
/// // syncService?.queueCreate(SyncEntity.session, session);
/// ```
///
/// **Affected Methods:**
/// - Session lifecycle: `createNewSession`, `endSession`, `discardCurrentSession`, `updateSessionNote`,
///   `updateSessionEndTime`, `updateSessionFeeling`, `updateSessionRpe`
/// - Effort/entry CRUD: `addExerciseToSession`, `removeExerciseFromSession`, `addEntry`, `deleteEntry`,
///   `updateEntryValue`, `markSetSkipped`
/// - Session blocks (delegated to SessionBlockManager): `addSessionBlock`, `updateSessionBlock`,
///   `deleteSessionBlock`, `reorderSessionBlocks`, `cloneSessionBlock`, `assignEffortToBlock`
///
/// When sync is implemented, each method will call `syncService?.queue(...)` after its repository write,
/// without affecting public signatures or consumer screens.
class SessionCore {
  final WorkoutRepository _repository;
  final void Function() _notify;
  final void Function(String) _setErrorCallback;
  final void Function() _clearErrorCallback;
  final TimerManager _timerManager;
  final ExerciseLibrary _exerciseLibrary;

  /// Optional platform-health write pipeline. Null in tests and in
  /// builds without a health integration; the lifecycle calls it only
  /// after a session has been persisted.
  final HealthSyncService? _healthSync;

  /// Optional recovery of watch entries that arrived while an Edit Session
  /// was open. Null in tests and in builds without a watch; the restore then
  /// behaves exactly as it did before the recovery existed (D-803, D-811).
  final WatchLateEntryRecovery? _lateEntryRecovery;

  late final SessionBlockManager _blockManager;
  late final SessionSummaryBuilder _summaryBuilder;

  TrainingSession? _currentSession;
  ModalityConfig? _currentModalityConfig;
  final List<SessionSegment> _segments = [];
  final Map<String, List<SegmentEffort>> _efforts = {};
  final Map<String, List<EffortObservation>> _observations = {};
  final Map<String, Exercise> _exerciseCache = {};

  /// The current session's sensor summaries, loaded with the session so an
  /// edit snapshot can carry them without a repository read (F-1).
  ///
  /// Loaded only once the session has ended: summaries are imported with the
  /// wrist's session end, so a session in progress has none, and reloading
  /// one costs nothing extra.
  final List<SensorSummary> _sensorSummaries = [];

  bool _isLoading = false;

  SessionCore(
    this._repository, {
    required void Function() notify,
    required void Function(String) setError,
    required void Function() clearError,
    required TimerManager timerManager,
    required ExerciseLibrary exerciseLibrary,
    HealthSyncService? healthSync,
    WatchLateEntryRecovery? lateEntryRecovery,
  }) : _notify = notify,
       _setErrorCallback = setError,
       _clearErrorCallback = clearError,
       _timerManager = timerManager,
       _exerciseLibrary = exerciseLibrary,
       _healthSync = healthSync,
       _lateEntryRecovery = lateEntryRecovery {
    _blockManager = SessionBlockManager(
      _repository,
      notify: _notify,
      setError: _setErrorCallback,
      clearError: _clearErrorCallback,
      timerManager: _timerManager,
      getEfforts: () => _efforts,
      getObservations: () => _observations,
      getCurrentSessionId: () => _currentSession?.id,
    );

    _summaryBuilder = SessionSummaryBuilder(
      timerManager: _timerManager,
      observations: _observations,
      efforts: _efforts,
      segments: _segments,
      exerciseCache: _exerciseCache,
    );
  }

  TrainingSession? get currentSession => _currentSession;
  ModalityConfig? get modalityConfig => _currentModalityConfig;
  List<SessionSegment> get segments => List.unmodifiable(_segments);
  bool get isLoading => _isLoading;
  bool get hasSession => _currentSession != null;
  bool get hasActiveSession =>
      _currentSession != null &&
      _currentSession!.endedAtMs == null &&
      _efforts.values.any((list) => list.isNotEmpty);
  bool get isRollingSession => _currentSession?.isRolling ?? false;
  String? get currentSessionModality => _currentSession?.modality;

  Map<String, List<EffortObservation>> get observationsMap => _observations;

  // ── Getters ────────────────────────────────────────────────────────────
  List<SegmentEffort> getEffortsForSegment(String segmentId) =>
      List.unmodifiable(_efforts[segmentId] ?? []);

  List<EffortObservation> getObservationsForEffort(String effortId) =>
      List.unmodifiable(_observations[effortId] ?? []);

  Exercise? getExercise(String? exerciseId) {
    if (exerciseId == null) return null;
    return _exerciseCache[exerciseId];
  }

  void cacheExercise(Exercise exercise) =>
      _exerciseCache[exercise.id] = exercise;

  // ── Block management (delegated to SessionBlockManager) ────────────────
  List<SessionBlock> getSessionBlocks() => _blockManager.getSessionBlocks();
  Future<String> addSessionBlock({String? name}) =>
      _blockManager.addSessionBlock(name: name);
  Future<void> updateSessionBlock(SessionBlock block) =>
      _blockManager.updateSessionBlock(block);
  Future<void> deleteSessionBlock(String blockId) =>
      _blockManager.deleteSessionBlock(blockId);
  Future<void> reorderSessionBlocks(List<String> orderedIds) =>
      _blockManager.reorderSessionBlocks(orderedIds);
  Future<String> cloneSessionBlock(String blockId) =>
      _blockManager.cloneSessionBlock(blockId);
  Future<void> assignEffortToBlock(String effortId, String? blockId) =>
      _blockManager.assignEffortToBlock(effortId, blockId);

  // ── Summary / query (delegated to SessionSummaryBuilder) ───────────────
  SessionSummary computeSessionSummary() {
    if (_currentSession == null) {
      throw Exception('No active session to summarize');
    }
    return _summaryBuilder.buildSessionSummary(_currentSession!);
  }

  List<SessionTemplateExercise> buildTemplateDraftExercises() =>
      _summaryBuilder.buildTemplateDraftExercises();

  List<Map<String, dynamic>> getExercisesWithEntries() =>
      _summaryBuilder.buildExercisesWithEntries();

  // ── Session query (repository pass-through) ────────────────────────────
  Future<List<TrainingSession>> getAllSessions() =>
      _repository.getAllSessions();

  Future<List<TrainingSession>> getSessionsByDateRange(int fromMs, int toMs) =>
      _repository.getSessionsByDateRange(fromMs, toMs);

  // ── Session reset ───────────────────────────────────────────────────────
  void clearSession() {
    _currentSession = null;
    _currentModalityConfig = null;
    _segments.clear();
    _efforts.clear();
    _observations.clear();
    _sensorSummaries.clear();
    _timerManager.clearAll();
    _blockManager.clearAll();
    _exerciseCache.clear();
    _exerciseLibrary.clearNoteCache();
    _clearError();
    _notify();
  }

  // ── Private helpers ─────────────────────────────────────────────────────
  SegmentEffort? _findEffort(String effortId) {
    for (final effortList in _efforts.values) {
      for (final effort in effortList) {
        if (effort.id == effortId) return effort;
      }
    }
    return null;
  }

  void _setLoading(bool value) {
    _isLoading = value;
    _notify();
  }

  void _setError(String message) => _setErrorCallback(message);
  void _clearError() => _clearErrorCallback();
}
