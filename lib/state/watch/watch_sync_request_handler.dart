/// Where a message that arrived from a wrist goes on the phone.
///
/// Plan: `.github/agents/plans/2026-09-21-13-watch-integration-shipping.md`,
/// Phase 2 (D-2). Scenario S-006.
///
/// Two kinds of frame arrive over the one radio, and they are answered by
/// different owners: a protocol message belongs to the session mirror or the day
/// log (see [WatchIncomingRouter]), while a request is the wrist asking for
/// something. Keeping the request branch here rather than inside the router is
/// what stops a transport detail from becoming a protocol one — PROTOCOL.md is
/// explicit that a request "is a transport concern and carries no message of its
/// own".
///
/// The routines are built here, on demand, and nowhere else: nothing on the
/// phone answers a request the wrist has not made (D-7).
library;

import '../../core/platform/watch_transport.dart';
import '../../core/utils/watch_reference_sync.dart';
import '../../data/repositories/workout_repository.dart';
import 'live_session_mirror_state.dart';

/// Handles the frames that are requests rather than protocol messages.
class WatchSyncRequestHandler {
  WatchSyncRequestHandler({
    required LiveSessionMirrorState mirror,
    required WatchMirrorTransport transport,
    required WorkoutRepository repository,
    DateTime Function()? clock,
  }) : _mirror = mirror,
       _transport = transport,
       _repository = repository,
       _clock = clock ?? _utcNow;

  static DateTime _utcNow() => DateTime.now().toUtc();

  final LiveSessionMirrorState _mirror;
  final WatchMirrorTransport _transport;
  final WorkoutRepository _repository;
  final DateTime Function() _clock;

  /// Answers [request], and reports whether it had an answer to give.
  ///
  /// False is not a failure: a phone holding no routines, or no session, has
  /// nothing to send and says nothing — the wrist's own copy is what it keeps.
  Future<bool> handle(String request) {
    switch (request) {
      case WatchTransportRequest.routines:
        return _sendRoutines();
      case WatchTransportRequest.snapshot:
        return _sendSnapshot();
      default:
        return Future<bool>.value(false);
    }
  }

  /// The answer to the wrist's "sync routines".
  Future<bool> _sendRoutines() async {
    final message = await WatchReferenceSync.buildRoutinesDown(
      repository: _repository,
      generatedAt: _clock(),
    );
    if (message == null) return false;

    await _transport.send(message);
    return true;
  }

  /// The answer to the wrist's "give me your session".
  ///
  /// A phone with no ladder says nothing rather than sending an empty one: an
  /// empty session is not a state, and the snapshot would replace the ladder the
  /// wrist is actually working through (PROTOCOL.md, "Idempotency and
  /// reconciliation").
  Future<bool> _sendSnapshot() async {
    if (_mirror.exercises.isEmpty) return false;

    await _mirror.sendSnapshot();
    return true;
  }
}
