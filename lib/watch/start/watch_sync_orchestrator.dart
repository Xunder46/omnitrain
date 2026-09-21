/// Proactive routine sync: what keeps the wrist's routines and fallback list
/// current without the user asking.
///
/// Plan: `.github/agents/plans/2026-07-13-08-b-watch-session-start-paths-plan.md`.
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
}

class WatchSyncOrchestrator {
  WatchSyncOrchestrator({
    required WatchSyncTransport transport,
    required WatchSessionStartPaths paths,
    required WatchSessionEngine engine,
  }) : _transport = transport,
       _paths = paths,
       _engine = engine;

  final WatchSyncTransport _transport;
  final WatchSessionStartPaths _paths;
  final WatchSessionEngine _engine;

  /// Pulls the routines: everything on a first connect, what changed after one.
  ///
  /// Call on connect and on reconnect. It is safe to call at any time and it
  /// never throws: a watch that cannot reach the phone keeps the routines it
  /// has, which is the whole point of syncing proactively.
  Future<void> sync({bool reconnect = false}) async {
    _paths.phoneReachable = _transport.isPhoneReachable;
    await _transport.requestRoutines(since: reconnect ? _paths.syncedAt : null);
  }

  /// Routes an arriving message to whoever owns it.
  ///
  /// Returns what the message changed, or false when the watch has no use for
  /// it — a conformant message for another item's surface, say. A message the
  /// watch cannot read throws, and nothing is applied: a peer speaking another
  /// protocol version must not half-edit a live session.
  Future<bool> receive(Map<String, Object?> envelope) async {
    switch (envelope['type']) {
      case 'routines_down':
        final result = await _paths.applyRoutinesDown(envelope);
        return result.applied;
      case 'exercise_push':
        await _engine.applyExercisePush(envelope);
        return true;
      default:
        return false;
    }
  }
}
