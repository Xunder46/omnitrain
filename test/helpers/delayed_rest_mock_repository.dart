import 'dart:async';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';

/// Mock repository that adds configurable latency to rest-related persist operations.
/// Used to test race conditions between in-memory rest state and async repository persist.
///
/// For controlled testing, pass `gateUpdateEntryRest: true` and manage completion via
/// [completeNextUpdateEntryRest], [completePendingUpdateEntryRest], or [pendingUpdateFutures].
class DelayedRestMockRepository extends MockWorkoutRepository {
  final Duration updateEntryRestLatency;
  final Duration createEntryRestLatency;
  final bool gateUpdateEntryRest;
  final bool gateCreateEntryRest;

  DelayedRestMockRepository({
    this.updateEntryRestLatency = Duration.zero,
    this.createEntryRestLatency = Duration.zero,
    this.gateUpdateEntryRest = false,
    this.gateCreateEntryRest = false,
  });

  final List<Completer<void>> _pendingUpdateCompleters = [];
  final List<Completer<void>> _pendingCreateCompleters = [];

  /// All pending updateEntryRest Futures (when using gateUpdateEntryRest mode).
  List<Future<void>> get pendingUpdateFutures =>
      _pendingUpdateCompleters.map((c) => c.future).toList();

  /// All pending createEntryRest Futures (when using gateCreateEntryRest mode).
  List<Future<void>> get pendingCreateFutures =>
      _pendingCreateCompleters.map((c) => c.future).toList();

  /// Returns true if there are pending updateEntryRest operations in-flight.
  bool get hasPendingUpdateOperations => _pendingUpdateCompleters.isNotEmpty;

  /// Returns true if there are pending createEntryRest operations in-flight.
  bool get hasPendingCreateOperations => _pendingCreateCompleters.isNotEmpty;

  /// Returns true if there are ANY pending rest operations in-flight.
  bool get hasPendingOperations =>
      hasPendingUpdateOperations || hasPendingCreateOperations;

  /// Completes the next pending updateEntryRest operation. Throws if none pending.
  void completeNextUpdateEntryRest() {
    if (_pendingUpdateCompleters.isEmpty) {
      throw StateError('No pending updateEntryRest operations to complete');
    }
    _pendingUpdateCompleters.removeAt(0).complete();
  }

  /// Completes all pending updateEntryRest operations.
  void completePendingUpdateEntryRest() {
    final pending = List<Completer<void>>.from(_pendingUpdateCompleters);
    _pendingUpdateCompleters.clear();
    for (final completer in pending) {
      completer.complete();
    }
  }

  /// Completes the next pending createEntryRest operation. Throws if none pending.
  void completeNextCreateEntryRest() {
    if (_pendingCreateCompleters.isEmpty) {
      throw StateError('No pending createEntryRest operations to complete');
    }
    _pendingCreateCompleters.removeAt(0).complete();
  }

  /// Completes all pending createEntryRest operations.
  void completePendingCreateEntryRest() {
    final pending = List<Completer<void>>.from(_pendingCreateCompleters);
    _pendingCreateCompleters.clear();
    for (final completer in pending) {
      completer.complete();
    }
  }

  /// Completes all pending rest operations (both update and create).
  void completePending() {
    completePendingUpdateEntryRest();
    completePendingCreateEntryRest();
  }

  @override
  Future<void> updateEntryRest(EntryRest rest) async {
    if (gateUpdateEntryRest) {
      final completer = Completer<void>();
      _pendingUpdateCompleters.add(completer);
      await completer.future;
    } else if (updateEntryRestLatency > Duration.zero) {
      await Future.delayed(updateEntryRestLatency);
    }
    return super.updateEntryRest(rest);
  }

  @override
  Future<String> createEntryRest(EntryRest rest) async {
    if (gateCreateEntryRest) {
      final completer = Completer<void>();
      _pendingCreateCompleters.add(completer);
      await completer.future;
    } else if (createEntryRestLatency > Duration.zero) {
      await Future.delayed(createEntryRestLatency);
    }
    return super.createEntryRest(rest);
  }
}
