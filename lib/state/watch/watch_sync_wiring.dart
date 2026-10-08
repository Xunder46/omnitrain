/// The phone-side watch graph, built in one place.
///
/// Plan: `docs/plans/2026-09-21-13-watch-integration-shipping.md`,
/// Phase 2 (D-2). Scenario S-006.
///
/// Before this, the mirror, the router, and the nutrition bridge existed only in
/// debug harnesses: the shipping app never built them. What this file adds is
/// the production construction — transport, mirror, router, request handler —
/// behind one function that answers null on a platform with no watch.
///
/// The mirror starts from a placeholder snapshot rather than from a session: a
/// phone with nothing running has no structure to assert, and the first real
/// structure arrives from the wrist, when a session started there reports
/// itself. The placeholder is `abandoned` on purpose: the home panel shows a
/// live session only while one is active, and a phone with no session must not
/// offer a panel that leads nowhere.
///
/// The watch session inbox (Stats PR 2, D-132) is built here too: the router
/// hands it every message first, the mirror's own corrections and deletions of
/// wrist entries are staged in it before they leave, and it resumes any import
/// the phone had not run when it last stopped.
library;

import '../../core/platform/no_watch_transport.dart';
import '../../core/platform/watch_transport.dart';
import '../../core/utils/platform_watch_transport_factory.dart';
import '../../data/repositories/workout_repository.dart';
import '../../watch/session/watch_records.dart' show WatchLifecycleState;
import '../food_library_state.dart';
import '../nutrition_state.dart';
import '../settings/settings_state.dart';
import 'live_session_mirror_state.dart';
import 'watch_incoming_router.dart';
import 'watch_nutrition_log_bridge.dart';
import 'watch_session_adoption_bridge.dart';
import 'watch_session_auto_push.dart';
import 'watch_session_inbox.dart';
import 'watch_sync_request_handler.dart';

/// A phone with no session running: no ladder, nothing logged, nobody waiting.
///
/// The id is valid but names no session — nothing on the wrist carries it, so
/// every session-scoped message the wrist sends is ignored here until a real
/// snapshot is adopted, which is exactly the rule the mirror applies to a
/// session it is not holding. It is a valid id rather than an empty string
/// because every envelope the phone builds carries it, and the protocol requires
/// a non-empty `sessionId`.
///
/// The status is `abandoned` so nothing offers this not-a-session as live: the
/// home panel appears only while a session is active.
const Map<String, Object?> watchSessionPlaceholder = {
  'sessionId': watchSessionPlaceholderId,
  'status': 'abandoned',
  'revision': 0,
  'currentExerciseIndex': 0,
  'exercises': <Object?>[],
  'entries': <Object?>[],
  'timers': <String, Object?>{},
};

/// What the app holds on to of the watch graph [createWatchSync] built.
class WatchSyncGraph {
  const WatchSyncGraph({
    required this.mirror,
    required this.ratings,
    required this.lateEntryRecovery,
    required this.adoption,
    required this.autoPush,
  });

  /// The session running on the wrist, as the phone mirrors it.
  final LiveSessionMirrorState mirror;

  /// Where the phone records its own effort rating for a wrist session: the
  /// graph's [WatchSessionInbox], behind the one capability a screen needs
  /// (D-139).
  final WatchSessionRatings ratings;

  /// Where an Edit Session Discard recovers the entries that arrived while
  /// the screen was open: the same [WatchSessionInbox], behind the one
  /// capability the restore needs (D-811).
  final WatchLateEntryRecovery lateEntryRecovery;

  /// Where the session the wrist is running becomes the phone's own: the app
  /// binds its `WorkoutState` to this once it has built it (D-2).
  final WatchSessionAdoptionBridge adoption;

  /// The one object that pushes the phone's own session to the watch: the app
  /// binds the same `WorkoutState` to it (D-75).
  final WatchSessionAutoPush autoPush;

  /// Asks the wrist for its session once — the phone's half of catching up
  /// after being out of reach (D-96).
  ///
  /// The frame it sends is the phone's **own** session, composed on the spot
  /// from the projection (D-11), and none at all when the phone holds no
  /// session: the mirror's own copy is what this phone converged with the
  /// wrist, not what it is working through, and a phone with nothing running
  /// must not assert the placeholder. The request follows either way.
  ///
  /// When the mirror still holds a *different* wrist session `W`, that session
  /// is ended by name before this phone's own is asserted (D-176): the wrist
  /// holds W actively, so it would refuse a foreign snapshot, and W's unsynced
  /// work is discarded rather than rescued. The wrist's answer to the request
  /// below is what moves the mirror onto the phone's session.
  ///
  /// Verified by `test/watch_session_projection_test.dart` (`S-109 case A one
  /// resume is one catch-up: the phone's OWN session and then the request for
  /// the wrist's, once per resume`, `S-109 case B a phone holding no session
  /// sends no snapshot at all`, `S-109 case C the phone asserts its own session,
  /// never the wrist's copy`).
  Future<void> sync() async {
    final composed = await mirror.projectedSession();
    if (composed != null) {
      if (mirror.owesResetFor(composed['sessionId'] as String?)) {
        await mirror.reportLifecycleFor(
          mirror.sessionId!,
          WatchLifecycleState.abandoned,
        );
      }
      await mirror.sendState(composed);
    }
    await mirror.requestSnapshot();
  }
}

/// Builds the phone's watch graph and answers the handles the app keeps on it,
/// or null when this platform has no watch.
///
/// Every outgoing and incoming path is wired here: the transport hands arriving
/// frames to the router (protocol messages) or the request handler (requests),
/// and the request handler answers from storage and from [settingsState], the
/// owner of the settings the wrist honours. The router drives the adoption
/// bridge after the mirror, so a snapshot the mirror applies becomes the phone's
/// own session (D-2). A platform without a watch, or a
/// transport that cannot be set up, answers null and the app carries on
/// without a wrist — see `createPlatformWatchTransport`.
///
/// [clock] is the phone's wall clock for everything the graph stamps; tests
/// pin it. [onHistoryChanged] runs once whenever a wrist session changes the
/// phone's history — the calendar's refresh in the shipping app (D-142).
/// [onSkipped] observes a refused adoption (D-10) — the phone kept the session
/// it was already running — which is not a failure: left out, the bridge logs
/// it once in debug.
Future<WatchSyncGraph?> createWatchSync({
  required WorkoutRepository repository,
  required NutritionState nutritionState,
  required FoodLibraryState foodLibraryState,
  required SettingsState settingsState,
  WatchTransport? transport,
  DateTime Function()? clock,
  Future<void> Function()? onHistoryChanged,
  void Function(Object error, StackTrace stack)? onFailure,
  void Function(String heldSessionId, String offeredSessionId)? onSkipped,
}) async {
  final resolved =
      transport ??
      await createPlatformWatchTransport(onFailure: onFailure);
  if (resolved == null || resolved is NoWatchTransport) return null;

  // Built first: the inbox asks the bridge whether a session is the phone's own
  // (G3), and the bridge answers from the `WorkoutState` the app binds once it
  // has built it.
  final adoption = WatchSessionAdoptionBridge(
    repository: repository,
    clock: clock,
    onFailure: onFailure,
    onSkipped: onSkipped,
  );
  final inbox = WatchSessionInbox(
    repository: repository,
    transport: resolved,
    clock: clock,
    onHistoryChanged: onHistoryChanged,
    // A session the mirror adopted is the phone's own (D-2), so an import pass
    // over it never materialises the wrist's effort entries: the phone holds
    // those rows already (G3).
    phoneOwnsSession: adoption.holdsSession,
    // A merge into a held session refreshes the efforts it wrote, on the live
    // session state, so the session screen shows the set without reloading the
    // session — a running timer survives (D-17).
    onSessionRowsChanged: adoption.refreshHeldEfforts,
  );
  final mirror = LiveSessionMirrorState(
    transport: WatchInboxStagingTransport(inner: resolved, inbox: inbox),
    snapshot: watchSessionPlaceholder,
    // Every ladder this phone asserts — a request answered or a wrist snapshot
    // re-asserted — is composed from the phone's own session, never from the
    // copy this mirror converged with the wrist (D-11).
    projection: adoption.projectSession,
  );
  final router = WatchIncomingRouter(
    inbox: inbox,
    mirror: mirror,
    nutrition: WatchNutritionLogBridge(
      nutrition: nutritionState,
      library: foodLibraryState,
      transport: resolved,
    ),
    adoption: adoption,
  );
  final requests = WatchSyncRequestHandler(
    mirror: mirror,
    transport: resolved,
    repository: repository,
    settings: settingsState,
    clock: clock,
  );
  // Built after the mirror, from the same repository the graph already holds:
  // the push reads the mirrored session's own row — never the current-session
  // pointer — to decide whether that session has ended (D-75, D-81). The
  // graph's failure hook is the push's too: a pass it cannot make, or one that
  // times out, is reported rather than swallowed (D-98, D-99).
  final push = WatchSessionAutoPush(
    mirror: mirror,
    getSession: repository.getSession,
    // The wrist's own imported ids come from the bridge, which owns the claim
    // rule in one place (D-112). Nothing of the phone's own needs it: those ids
    // travel inside the composed payload this push already has.
    heldWristEntryIds: adoption.heldWristEntryIds,
    // The graph's clock stamps a deletion frame's change id (F2), so tests pin
    // it the way they pin every other stamp this graph makes.
    clock: clock,
    onFailure: onFailure,
  );

  resolved.onIncoming((frame) async {
    final request = WatchTransportRequest.nameOf(frame);
    if (request != null) {
      await requests.handle(request);
    } else {
      await router.receive(frame);
    }
    // A frame the phone applied from the wrist is not news to push back (D-82):
    // the rows it just brought in become the baseline rather than a send.
    await push.rebaseline();
  });

  await inbox.resume();
  return WatchSyncGraph(
    mirror: mirror,
    ratings: inbox,
    lateEntryRecovery: inbox,
    adoption: adoption,
    autoPush: push,
  );
}
