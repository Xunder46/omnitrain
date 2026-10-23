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
/// The routines, the food list and the exercise list are built here, on
/// demand, and nowhere else: nothing on the phone answers a request the wrist
/// has not made (D-7).
///
/// The same request is how the phone's settings reach the wrist: the phone
/// never pushes, so every sync is answered with `preferences_down` first —
/// even by a phone with no routines — and the setting changed since the last
/// one lands at the wrist's next sync (Stats PR 2, D-113, D-115; scenario
/// S-253).
library;

import '../../core/constants/omni_theme.dart';
import '../../core/platform/watch_delivery.dart';
import '../../core/platform/watch_transport.dart';
import '../../core/utils/watch_reference_sync.dart';
import '../../data/repositories/workout_repository.dart';
import '../food_library_state.dart';
import '../settings/settings_state.dart';
import 'live_session_mirror_state.dart';

/// Handles the frames that are requests rather than protocol messages.
class WatchSyncRequestHandler {
  WatchSyncRequestHandler({
    required LiveSessionMirrorState mirror,
    required WatchMirrorTransport transport,
    required WorkoutRepository repository,
    required SettingsState settings,
    required FoodLibraryState foodLibrary,
    DateTime Function()? clock,
  }) : _mirror = mirror,
       _transport = transport,
       _repository = repository,
       _settings = settings,
       _foodLibrary = foodLibrary,
       _clock = clock ?? _utcNow;

  static DateTime _utcNow() => DateTime.now().toUtc();

  final LiveSessionMirrorState _mirror;
  final WatchMirrorTransport _transport;
  final WorkoutRepository _repository;
  final SettingsState _settings;
  final FoodLibraryState _foodLibrary;
  final DateTime Function() _clock;

  /// Answers [request], and reports whether it had an answer to give.
  ///
  /// [exercisesVersion] is the version of the exercise list the wrist holds,
  /// as it named it in the request frame; a wrist holding nothing — or naming
  /// nothing readable — is sent the whole list (D-3834).
  ///
  /// False is not a failure: a phone holding no session has nothing to send
  /// and says nothing — the wrist's own copy is what it keeps. A request for
  /// routines is always answered: the preferences, the routines and the
  /// exercise list (unless the wrist already holds it) travel with it.
  Future<bool> handle(String request, {String? exercisesVersion}) {
    switch (request) {
      case WatchTransportRequest.routines:
        return _sendRoutines(exercisesVersion: exercisesVersion);
      case WatchTransportRequest.snapshot:
        return _sendSnapshot();
      default:
        return Future<bool>.value(false);
    }
  }

  /// The answer to the wrist's "sync routines", in this order: the
  /// preferences, always and first — the settings the wrist honours and the
  /// accent of the theme the phone is wearing — then the routines, then the
  /// food list, then the phone's exercise list as
  /// [WatchReferenceSync.buildExercisesDown] batches, unless the wrist already
  /// holds the version it named (D-3834).
  ///
  /// The foods travel before the version check, so a wrist that holds the
  /// exercise list still receives them; a phone with no foods sends no food
  /// frame at all, and a refused one does not stop the batches (49a, D-1,
  /// D-2).
  ///
  /// The batches go one at a time, in index order, and stop at the first the
  /// radio did not carry: the wrist assembles a complete list or keeps the one
  /// it has, so a half-arrived list is worse than none and the next sync sends
  /// the whole list again (PROTOCOL.md, "Idempotency and reconciliation").
  ///
  /// The settings are `SettingsState`'s own — the one owner of them (D-115) —
  /// so nothing here reads or parses a stored preference; the accent is read
  /// the same way, from the theme that state holds rather than from a copy.
  Future<bool> _sendRoutines({String? exercisesVersion}) async {
    await _transport.send(
      WatchReferenceSync.buildPreferencesDown(
        effortRatingPrompt: _settings.showFeelingSurvey,
        restPingSeconds: _settings.restPingInterval,
        accentColorHex: WatchReferenceSync.accentHexOf(
          OmniTheme.colorsForTheme(_settings.appTheme).primary,
        ),
        weightUnit: _settings.preferredWeightUnit,
        distanceUnit: _settings.preferredDistanceUnit,
        generatedAt: _clock(),
      ),
    );

    await _transport.send(
      await WatchReferenceSync.buildRoutinesDown(
        repository: _repository,
        generatedAt: _clock(),
      ),
    );

    // The foods are read back from storage on every request: nothing on the
    // phone loads them for this answer, and `NutritionState`'s write-through
    // updates the repository row only, so a cache loaded once goes stale after
    // every log (D-7). A failed read is not a reason to withhold the rest: the
    // cache as it stands is what the wrist gets.
    try {
      await _foodLibrary.loadFoodGroups(includeArchived: true);
      await _foodLibrary.loadFoods();
    } catch (_) {
      // Deliberately swallowed — see above.
    }

    if (_foodLibrary.foods.isNotEmpty) {
      await _transport.send(
        WatchReferenceSync.buildFoodsDown(
          foods: _foodLibrary.foods,
          groups: _foodLibrary.foodGroups,
          generatedAt: _clock(),
        ),
      );
    }

    final batches = await WatchReferenceSync.buildExercisesDown(
      repository: _repository,
      generatedAt: _clock(),
    );
    if (batches.isEmpty) return true;

    final version = (batches.first['payload']! as Map)['catalogVersion'];
    if (exercisesVersion == version) return true;

    for (final batch in batches) {
      if (await _transport.send(batch) == WatchDelivery.undelivered) break;
    }
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
