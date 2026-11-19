/// Proactive routine sync: what keeps the wrist's routines and fallback list
/// current without the user asking.
///
/// Plan: `docs/plans/2026-07-13-08-b-watch-session-start-paths-plan.md`.
/// Carrying the messages is a separate item; this is the orchestrator that
/// decides *when* they are asked for and where an arriving one goes.
///
/// Two rules shape it:
///
/// 1. **Sync happens in the background, not at session start.** A user who taps
///    "Start" is never waiting on a radio, and a phone that is out of reach
///    cannot make a routine unstartable.
/// 2. **Incremental where the protocol allows it.** The first request asks for
///    everything; later ones say what the watch already has, so the phone can
///    send what changed rather than the whole set.
library;

import '../nutrition/watch_nutrition_state.dart';
import '../session/watch_session_engine.dart';
import 'watch_session_start_paths.dart';

/// What the orchestrator needs from whatever carries messages between the two
/// devices (WatchConnectivity, the Wear OS data layer, or a test double).
abstract interface class WatchSyncTransport {
  /// Whether the phone can be reached right now.
  bool get isPhoneReachable;

  /// Asks the phone for `routines_down`, optionally for everything newer than
  /// [since]. The reply arrives through [WatchSyncOrchestrator.receive] — this
  /// call carries no payload of its own.
  Future<void> requestRoutines({DateTime? since});

  /// Asks the phone for a `session_snapshot`. The reply arrives through
  /// [WatchSyncOrchestrator.receive], exactly as a `routines_down` reply does.
  Future<void> requestSnapshot();

  /// Hands the phone one message the watch owes it — an observation, a timer,
  /// a lifecycle change, or the watch's own session snapshot.
  Future<void> send(Map<String, Object?> envelope);
}

class WatchSyncOrchestrator {
  WatchSyncOrchestrator({
    required WatchSyncTransport transport,
    required WatchSessionStartPaths paths,
    required WatchSessionEngine engine,
    WatchNutritionState? nutrition,
  }) : _transport = transport,
       _paths = paths,
       _engine = engine,
       _nutrition = nutrition;

  final WatchSyncTransport _transport;
  final WatchSessionStartPaths _paths;
  final WatchSessionEngine _engine;

  /// The quick-log surface's synced food list, when the app hosts one. A watch
  /// without the surface has nothing to do with a `foods_down`.
  final WatchNutritionState? _nutrition;

  /// Whether a catch-up is already running: a trigger that arrives while one
  /// does is dropped, never queued (D-183).
  bool _catchUpRunning = false;

  /// D-183: catches the watch up when the app becomes active and the phone is
  /// reachable; a trigger while one runs is dropped.
  Future<void> catchUp({required bool reachable}) async {
    if (!reachable || _catchUpRunning) return;
    _catchUpRunning = true;
    try {
      await sync(reconnect: _paths.syncedAt != null);
    } finally {
      _catchUpRunning = false;
    }
  }

  /// Brings the watch up to date with the phone: the routines, and then the
  /// session state the two devices do not share yet.
  ///
  /// Call on connect and on reconnect. It is safe to call at any time and it
  /// never throws: a watch that cannot reach the phone keeps the routines it
  /// has, which is the whole point of syncing proactively.
  ///
  /// The watch re-sends every observation the phone has not acknowledged —
  /// rebuilt from storage rather than from a queue, so a relaunch re-sends the
  /// same identifiers and the phone deduplicates them (S-003). It asks for a
  /// snapshot when it has no session to converge on (joining a phone session),
  /// and hands over its own when it has one, which is the exchange the protocol
  /// asks of both devices on connect.
  Future<void> sync({bool reconnect = false}) async {
    _paths.phoneReachable = _transport.isPhoneReachable;
    await _transport.requestRoutines(since: reconnect ? _paths.syncedAt : null);
    await _sendOwedObservations();
    // D-199: the rating observation above must reach the phone before the
    // replay, so the copy ends with the wrist's rating already in it.
    if (_paths.phoneReachable) _engine.replaySessionEnd();
    await _exchangeSessionState();
  }

  /// Answers a snapshot request from the phone with the watch's live session.
  ///
  /// A watch with nothing logged has nothing authoritative to report, so the
  /// request goes unanswered rather than answered with an empty session.
  /// Verified by `test/live_mirroring_test.dart` (`S-009 a sessionless watch
  /// answers a snapshot request with nothing`) and by watchOS
  /// `WatchLiveMirroringTests.testASessionlessWatchAnswersNothing`.
  Future<void> answerSnapshotRequest() async {
    final snapshot = _engine.sessionSnapshot();
    if (snapshot == null) return;
    await _transport.send(snapshot);
  }

  /// Replays what the phone has not acknowledged, from storage.
  Future<void> _sendOwedObservations() async {
    for (final message in _engine.pendingObservations()) {
      await _transport.send(message);
    }
  }

  /// The connect handshake: a watch with a session reports it, and asks for the
  /// phone's only when it has nothing of its own to converge on.
  Future<void> _exchangeSessionState() async {
    if (_engine.session == null) {
      await _transport.requestSnapshot();
      return;
    }
    await answerSnapshotRequest();
  }

  /// Routes an arriving message to whoever owns it.
  ///
  /// Returns what the message changed, or false when the watch has no use for
  /// it — a conformant message for another item's surface, say, or reference
  /// data already older than the cached catalog. A message the watch cannot
  /// read is refused whole, nothing is applied, and the phone is answered with
  /// the watch's snapshot so it converges from what the wrist actually holds
  /// (PROTOCOL.md, "Versioning policy"). The refusal is still reported, because
  /// a caller needs to know its session was not advanced.
  Future<bool> receive(Map<String, Object?> envelope) async {
    switch (envelope['type']) {
      case 'routines_down':
        final result = await _paths.applyRoutinesDown(envelope);
        return result.applied;
      case 'foods_down':
        final nutrition = _nutrition;
        if (nutrition == null) return false;
        final result = await nutrition.applyFoodsDown(envelope);
        return result.applied;
      case 'exercise_push':
      case 'session_snapshot':
      case 'structure_change':
      case 'session_lifecycle':
      case 'timer_state':
      case 'receipt':
      case 'observations_up':
        try {
          return await _engine.applyMessage(envelope);
        } on WatchEmissionRejected {
          await answerSnapshotRequest();
          rethrow;
        }
      default:
        return false;
    }
  }
}
