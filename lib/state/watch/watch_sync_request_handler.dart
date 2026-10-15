/// Where a message that arrived from a wrist goes on the phone.
///
/// Plan: `docs/plans/2026-09-21-13-watch-integration-shipping.md`,
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
///
/// The same request is how the phone's settings reach the wrist: the phone
/// never pushes, so every sync is answered with `preferences_down` first —
/// even by a phone with no routines — and the setting changed since the last
/// one lands at the wrist's next sync (Stats PR 2, D-113, D-115; scenario
/// S-253).
library;

import '../../core/platform/watch_transport.dart';
import '../../core/utils/watch_reference_sync.dart';
import '../../data/repositories/workout_repository.dart';
import '../settings/settings_state.dart';
import 'live_session_mirror_state.dart';

/// Handles the frames that are requests rather than protocol messages.
class WatchSyncRequestHandler {
  WatchSyncRequestHandler({
    required LiveSessionMirrorState mirror,
    required WatchMirrorTransport transport,
    required WorkoutRepository repository,
    required SettingsState settings,
    DateTime Function()? clock,
  }) : _mirror = mirror,
       _transport = transport,
       _repository = repository,
       _settings = settings,
       _clock = clock ?? _utcNow;

  static DateTime _utcNow() => DateTime.now().toUtc();

  final LiveSessionMirrorState _mirror;
  final WatchMirrorTransport _transport;
  final WorkoutRepository _repository;
  final SettingsState _settings;
  final DateTime Function() _clock;

  /// Answers [request], and reports whether it had an answer to give.
  ///
  /// False is not a failure: a phone holding no session has nothing to send
  /// and says nothing — the wrist's own copy is what it keeps. A request for
  /// routines is always answered, because the preferences travel with it.
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

  /// The answer to the wrist's "sync routines": the preferences, always and
  /// first, then the routines when the phone holds any.
  ///
  /// The settings are `SettingsState`'s own — the one owner of them (D-115) —
  /// so nothing here reads or parses a stored preference.
  Future<bool> _sendRoutines() async {
    await _transport.send(
      WatchReferenceSync.buildPreferencesDown(
        effortRatingPrompt: _settings.showFeelingSurvey,
        restPingSeconds: _settings.restPingInterval,
        generatedAt: _clock(),
      ),
    );

    final message = await WatchReferenceSync.buildRoutinesDown(
      repository: _repository,
      generatedAt: _clock(),
    );
    if (message != null) await _transport.send(message);
    return true;
  }

  /// The answer to the wrist's "give me your session".
  ///
  /// The phone's own session comes first when it has one: the wrist is asking
  /// what the phone is working through, and this mirror's copy is the wrist's
  /// reflection of it, not the phone's state (D-11). Only a phone with no
  /// session of its own — or whose session is not the one the wrist named
  /// (D-10) — falls back to what it converged with the wrist.
  ///
  /// A phone with no ladder at all says nothing rather than sending an empty
  /// one: an empty session is not a state, and the snapshot would replace the
  /// ladder the wrist is actually working through (PROTOCOL.md, "Idempotency
  /// and reconciliation").
  Future<bool> _sendSnapshot() async {
    final projection = await _mirror.projectedSession();
    if (projection != null) {
      await _mirror.sendState(projection);
      return true;
    }

    if (_mirror.exercises.isEmpty) return false;

    await _mirror.sendSnapshot();
    return true;
  }
}
