/// The phone-side watch graph, built in one place.
///
/// Plan: `.github/agents/plans/2026-09-21-13-watch-integration-shipping.md`,
/// Phase 2 (D-2). Scenario S-006.
///
/// Before this, the mirror, the router, and the nutrition bridge existed only in
/// debug harnesses: `MyApp.liveSession` was always null, so the home panel and
/// the live session screen were dead in the shipping app. What this file adds is
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
import '../food_library_state.dart';
import '../nutrition_state.dart';
import '../settings/settings_state.dart';
import 'live_session_mirror_state.dart';
import 'watch_incoming_router.dart';
import 'watch_nutrition_log_bridge.dart';
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
  'sessionId': 's-phone-unjoined',
  'status': 'abandoned',
  'revision': 0,
  'currentExerciseIndex': 0,
  'exercises': <Object?>[],
  'entries': <Object?>[],
  'timers': <String, Object?>{},
};

/// What the app holds on to of the watch graph [createWatchSync] built.
class WatchSyncGraph {
  const WatchSyncGraph({required this.mirror, required this.ratings});

  /// The session running on the wrist, as the phone mirrors it — what the
  /// home panel and the Watch Session screen show.
  final LiveSessionMirrorState mirror;

  /// Where the phone records its own effort rating for a wrist session: the
  /// graph's [WatchSessionInbox], behind the one capability a screen needs
  /// (D-139).
  final WatchSessionRatings ratings;
}

/// Builds the phone's watch graph and answers the handles the app keeps on it,
/// or null when this platform has no watch.
///
/// Every outgoing and incoming path is wired here: the transport hands arriving
/// frames to the router (protocol messages) or the request handler (requests),
/// and the request handler answers from storage and from [settingsState], the
/// owner of the settings the wrist honours. A platform without a watch, or a
/// transport that cannot be set up, answers null and the app carries on
/// without a wrist — see `createPlatformWatchTransport`.
///
/// [clock] is the phone's wall clock for everything the graph stamps; tests
/// pin it. [onHistoryChanged] runs once whenever a wrist session changes the
/// phone's history — the calendar's refresh in the shipping app (D-142).
Future<WatchSyncGraph?> createWatchSync({
  required WorkoutRepository repository,
  required NutritionState nutritionState,
  required FoodLibraryState foodLibraryState,
  required SettingsState settingsState,
  WatchTransport? transport,
  DateTime Function()? clock,
  Future<void> Function()? onHistoryChanged,
  void Function(Object error, StackTrace stack)? onFailure,
}) async {
  final resolved =
      transport ??
      await createPlatformWatchTransport(onFailure: onFailure);
  if (resolved == null || resolved is NoWatchTransport) return null;

  final inbox = WatchSessionInbox(
    repository: repository,
    transport: resolved,
    clock: clock,
    onHistoryChanged: onHistoryChanged,
  );
  final mirror = LiveSessionMirrorState(
    transport: WatchInboxStagingTransport(inner: resolved, inbox: inbox),
    snapshot: watchSessionPlaceholder,
  );
  final router = WatchIncomingRouter(
    inbox: inbox,
    mirror: mirror,
    nutrition: WatchNutritionLogBridge(
      nutrition: nutritionState,
      library: foodLibraryState,
      transport: resolved,
    ),
  );
  final requests = WatchSyncRequestHandler(
    mirror: mirror,
    transport: resolved,
    repository: repository,
    settings: settingsState,
    clock: clock,
  );

  resolved.onIncoming((frame) async {
    final request = WatchTransportRequest.nameOf(frame);
    if (request != null) {
      await requests.handle(request);
      return;
    }
    await router.receive(frame);
  });

  await inbox.resume();
  return WatchSyncGraph(mirror: mirror, ratings: inbox);
}
