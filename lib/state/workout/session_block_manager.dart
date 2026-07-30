import '../../data/models/models.dart';
import '../../data/repositories/workout_repository.dart';
import 'timer_manager.dart';

class SessionBlockManager {
  final WorkoutRepository _repository;
  final void Function() _notify;
  final void Function(String) _setErrorCallback;
  final void Function() _clearErrorCallback;
  final TimerManager _timerManager;

  /// Reference to the session's effort map: {segmentId: [efforts]}
  /// Used to find efforts with blockId and remove them
  final Map<String, List<SegmentEffort>> Function() _getEfforts;

  /// Reference to the session's observations map: {effortId: [observations]}
  /// Used to clean up observations when blocks/efforts are deleted
  final Map<String, List<EffortObservation>> Function() _getObservations;

  /// Reference to the current session ID getter
  final String? Function() _getCurrentSessionId;

  final Map<String, List<SessionBlock>> _sessionBlocks = {};

  SessionBlockManager(
    this._repository, {
    required void Function() notify,
    required void Function(String) setError,
    required void Function() clearError,
    required TimerManager timerManager,
    required Map<String, List<SegmentEffort>> Function() getEfforts,
    required Map<String, List<EffortObservation>> Function() getObservations,
    required String? Function() getCurrentSessionId,
  }) : _notify = notify,
       _setErrorCallback = setError,
       _clearErrorCallback = clearError,
       _timerManager = timerManager,
       _getEfforts = getEfforts,
       _getObservations = getObservations,
       _getCurrentSessionId = getCurrentSessionId;

  List<SessionBlock> getSessionBlocks() {
    final currentSessionId = _getCurrentSessionId();
    if (currentSessionId == null) return [];
    final blocks = _sessionBlocks[currentSessionId] ?? [];
    return List<SessionBlock>.from(blocks)
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
  }

  Future<String> addSessionBlock({String? name}) async {
    final currentSessionId = _getCurrentSessionId();
    if (currentSessionId == null) return '';

    _clearError();

    try {
      final now = DateTime.now();
      final nowMs = now.millisecondsSinceEpoch;
      final nowUs = now.microsecondsSinceEpoch;
      final blockName =
          name ??
          () {
            final hour12 = now.hour % 12 == 0 ? 12 : now.hour % 12;
            final minute = now.minute.toString().padLeft(2, '0');
            final period = now.hour < 12 ? 'AM' : 'PM';
            return '$hour12:$minute $period';
          }();

      final blocks = _sessionBlocks[currentSessionId] ?? [];
      final maxOrder = blocks.fold<int>(
        -1,
        (currentMax, block) =>
            block.orderIndex > currentMax ? block.orderIndex : currentMax,
      );

      final block = SessionBlock(
        id: 'block-$nowUs-${maxOrder + 1}',
        sessionId: currentSessionId,
        name: blockName,
        orderIndex: maxOrder + 1,
        createdAtMs: nowMs,
        updatedAtMs: nowMs,
      );

      final blockId = await _repository.createSessionBlock(block);
      _sessionBlocks[currentSessionId] = await _repository.getSessionBlocks(
        currentSessionId,
      );
      _notify();
      return blockId;
    } catch (e) {
      _setError('Failed to add session block: $e');
      return '';
    }
  }

  Future<void> updateSessionBlock(SessionBlock block) async {
    _clearError();

    try {
      await _repository.updateSessionBlock(block);
      final blocks = _sessionBlocks[block.sessionId];
      if (blocks != null) {
        final index = blocks.indexWhere((b) => b.id == block.id);
        if (index != -1) {
          blocks[index] = block;
        }
      }
      _notify();
    } catch (e) {
      _setError('Failed to update session block: $e');
    }
  }

  Future<void> deleteSessionBlock(String blockId) async {
    _clearError();

    try {
      await _repository.deleteSessionBlock(blockId);

      for (final blocks in _sessionBlocks.values) {
        blocks.removeWhere((block) => block.id == blockId);
      }

      final efforts = _getEfforts();
      final observations = _getObservations();
      for (final effortList in efforts.values) {
        final toRemove = effortList
            .where((e) => e.blockId == blockId)
            .map((e) => e.id)
            .toList();
        effortList.removeWhere((e) => e.blockId == blockId);
        for (final effortId in toRemove) {
          observations.remove(effortId);
          _timerManager.removeEffort(effortId);
        }
      }

      _notify();
    } catch (e) {
      _setError('Failed to delete session block: $e');
    }
  }

  Future<void> reorderSessionBlocks(List<String> orderedIds) async {
    final currentSessionId = _getCurrentSessionId();
    if (currentSessionId == null) return;

    _clearError();

    try {
      await _repository.reorderSessionBlocks(currentSessionId, orderedIds);
      _sessionBlocks[currentSessionId] = await _repository.getSessionBlocks(
        currentSessionId,
      );
      _notify();
    } catch (e) {
      _setError('Failed to reorder session blocks: $e');
    }
  }

  Future<String> cloneSessionBlock(String blockId) async {
    final currentSessionId = _getCurrentSessionId();
    if (currentSessionId == null) return '';

    _clearError();

    try {
      final newBlockId = await _repository.cloneSessionBlock(blockId);
      _sessionBlocks[currentSessionId] = await _repository.getSessionBlocks(
        currentSessionId,
      );
      _notify();
      return newBlockId;
    } catch (e) {
      _setError('Failed to clone session block: $e');
      return '';
    }
  }

  Future<void> assignEffortToBlock(String effortId, String? blockId) async {
    _clearError();

    try {
      await _repository.assignEffortToBlock(effortId, blockId);

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final efforts = _getEfforts();
      for (final effortList in efforts.values) {
        final index = effortList.indexWhere((effort) => effort.id == effortId);
        if (index == -1) continue;

        final effort = effortList[index];
        effortList[index] = SegmentEffort(
          id: effort.id,
          segmentId: effort.segmentId,
          orderIndex: effort.orderIndex,
          effortKind: effort.effortKind,
          exerciseId: effort.exerciseId,
          note: effort.note,
          blockId: blockId,
          createdAtMs: effort.createdAtMs,
          updatedAtMs: nowMs,
        );
        break;
      }

      _notify();
    } catch (e) {
      _setError('Failed to assign effort to block: $e');
    }
  }

  void setSessionBlocks(String sessionId, List<SessionBlock> blocks) {
    _sessionBlocks[sessionId] = blocks;
  }

  Map<String, List<SessionBlock>> get sessionBlocksSnapshot =>
      Map.unmodifiable(_sessionBlocks);

  void clearAll() {
    _sessionBlocks.clear();
  }

  void _setError(String message) => _setErrorCallback(message);

  void _clearError() => _clearErrorCallback();
}
