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
/// The same request is how the phone's settings reach the wrist: the three
/// reference frames — the preferences, the foods, the routines — travel
/// together, stamped alike, and only when the wrist's `since` is older than
/// the bundle's stamp; the routines frame goes last, and only after the other
/// two were carried (Stats PR 2, D-113, D-115; scenario S-253).
library;

import 'dart:convert';

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

  /// The reference bundle the phone last saw, as the text of its preferences
  /// and of its routines and foods, the stamp the three frames carry, and the
  /// repository revision the routines and foods were read at (null when the
  /// repository cannot tell, or the read failed). A phone that relaunched
  /// holds none, and re-sends once at the wrist's next request (S-9212).
  ({String preferencesText, String referenceText, DateTime stamp, int? revision})?
  _held;

  /// The exercise-list version this phone last computed, and the repository
  /// revision it was computed at: a wrist naming that version while the
  /// revision stands still is sent nothing and nothing is read (plan 74, D-6).
  ({String version, int revision})? _exercisesHeld;

  /// Answers [request], and reports whether it had an answer to give.
  ///
  /// [exercisesVersion] is the version of the exercise list the wrist holds,
  /// as it named it in the request frame; a wrist holding nothing — or naming
  /// nothing readable — is sent the whole list (D-3834).
  ///
  /// False is not a failure: a phone holding no session has nothing to send
  /// and says nothing — the wrist's own copy is what it keeps. A request for
  /// routines is answered with the three reference frames when the wrist's
  /// `since` is older than the bundle's stamp, and with none of them when it
  /// is not; the exercise list (unless the wrist already holds it) travels
  /// with every answer.
  Future<bool> handle(String request, {String? exercisesVersion, DateTime? since}) {
    switch (request) {
      case WatchTransportRequest.routines:
        return _sendRoutines(exercisesVersion: exercisesVersion, since: since);
      case WatchTransportRequest.snapshot:
        return _sendSnapshot();
      default:
        return Future<bool>.value(false);
    }
  }

  /// The answer to the wrist's "sync routines": the three reference frames —
  /// the preferences, then the foods (when the phone has any), then the
  /// routines — sent together, stamped alike, and only when the wrist's
  /// `since` is older than the bundle's stamp. The routines frame is the
  /// bundle's commit marker: it goes last, and only after the preferences and
  /// the foods were carried, so a wrist that names a stamp holds everything
  /// up to it (plan 62, D-4).
  ///
  /// The stamp is the bundle's own: it changes only when the content of the
  /// three frames changes, so an unchanged phone answers a wrist that holds
  /// the current bundle with none of the three. A phone that relaunched holds
  /// no stamp in memory and re-sends once (S-9212).
  ///
  /// The foods are read back from storage on every request that needs them,
  /// and not at all while the repository's `referenceRevision` stands still
  /// (plan 74): nothing on the phone loads them for this answer, and
  /// `NutritionState`'s write-through updates the repository row only, so a
  /// cache loaded once goes stale after every log (D-7). A failed read is not
  /// a reason to withhold the rest: the cache as it stands is what the wrist
  /// gets.
  ///
  /// While the repository's revision stands still the foods, routines and
  /// exercises are not read again (plan 74).
  ///
  /// Then the phone's exercise list as [WatchReferenceSync.buildExercisesDown]
  /// batches, unless the wrist already holds the version it named (D-3834) —
  /// independent of the bundle: a skipped bundle still checks the version, and
  /// a sent bundle still skips the batches the wrist holds.
  ///
  /// The batches go one at a time, in index order, and stop at the first the
  /// radio did not carry: the wrist assembles a complete list or keeps the one
  /// it has, so a half-arrived list is worse than none and the next sync sends
  /// the whole list again (PROTOCOL.md, "Idempotency and reconciliation").
  ///
  /// The settings are `SettingsState`'s own — the one owner of them (D-115) —
  /// so nothing here reads or parses a stored preference; the accent is read
  /// the same way, from the theme that state holds rather than from a copy.
  Future<bool> _sendRoutines({String? exercisesVersion, DateTime? since}) async {
    // Read once, before anything else: a write that lands while this request
    // runs leaves the stored number older than the data, so the next request
    // reads again (plan 74, D-4).
    final revision = _repository.referenceRevision;
    final held = _held;
    final storageUnchanged =
        revision != null && held != null && held.revision == revision;

    var readFailed = false;
    if (!storageUnchanged) {
      readFailed = !await _reloadFoods();
    }

    final preferencesText = jsonEncode(_preferencesFrame(DateTime.utc(1970)));
    final referenceText = storageUnchanged
        ? held.referenceText
        : jsonEncode([
            await WatchReferenceSync.buildRoutinesDown(
              repository: _repository,
              generatedAt: DateTime.utc(1970),
            ),
            _foodsFrame(DateTime.utc(1970)),
          ]);
    final DateTime stamp;
    if (held != null &&
        held.preferencesText == preferencesText &&
        held.referenceText == referenceText) {
      stamp = held.stamp;
    } else {
      final now = _clock().toUtc();
      stamp = DateTime.fromMillisecondsSinceEpoch(
        now.millisecondsSinceEpoch,
        isUtc: true,
      );
    }
    _held = (
      preferencesText: preferencesText,
      referenceText: referenceText,
      stamp: stamp,
      revision: readFailed ? null : revision,
    );

    if (since == null || since.isBefore(stamp)) {
      // The wrist lacks this bundle: read the library afresh, as every request
      // did before plan 74, so what is sent is what storage holds now.
      if (storageUnchanged) await _reloadFoods();
      final bundle = await _bundle(stamp);
      final preferences = await _transport.send(bundle.preferences);
      var carried = preferences != WatchDelivery.undelivered;
      final foods = bundle.foods;
      if (foods != null &&
          await _transport.send(foods) == WatchDelivery.undelivered) {
        carried = false;
      }
      // The routines frame is the bundle's commit marker: the wrist names its
      // stamp as `since`, so it is only sent once the other two were carried.
      if (carried) await _transport.send(bundle.routines);
    }

    final heldExercises = _exercisesHeld;
    if (exercisesVersion != null &&
        revision != null &&
        heldExercises != null &&
        heldExercises.revision == revision &&
        heldExercises.version == exercisesVersion) {
      return true;
    }

    final batches = await WatchReferenceSync.buildExercisesDown(
      repository: _repository,
      generatedAt: _clock(),
    );
    if (batches.isEmpty) return true;

    final version = (batches.first['payload']! as Map)['catalogVersion'];
    _exercisesHeld = revision != null && version is String
        ? (version: version, revision: revision)
        : null;
    if (exercisesVersion == version) return true;

    for (final batch in batches) {
      if (await _transport.send(batch) == WatchDelivery.undelivered) break;
    }
    return true;
  }

  /// Reloads the food groups and foods from storage; false when a read threw
  /// (the cache as it stands is what the wrist then gets, as before).
  Future<bool> _reloadFoods() async {
    try {
      await _foodLibrary.loadFoodGroups(includeArchived: true);
      await _foodLibrary.loadFoods();
      return true;
    } catch (_) {
      // Deliberately swallowed — a failed read is no reason to withhold the rest.
      return false;
    }
  }

  /// The three reference frames, stamped [at]; the foods frame is null for a
  /// phone with no foods.
  Future<
    ({Map<String, Object?> preferences, Map<String, Object?> routines, Map<String, Object?>? foods})
  >
  _bundle(DateTime at) async {
    return (
      preferences: _preferencesFrame(at),
      routines: await WatchReferenceSync.buildRoutinesDown(
        repository: _repository,
        generatedAt: at,
      ),
      foods: _foodsFrame(at),
    );
  }

  Map<String, Object?> _preferencesFrame(DateTime at) =>
      WatchReferenceSync.buildPreferencesDown(
        effortRatingPrompt: _settings.showFeelingSurvey,
        restPingSeconds: _settings.restPingInterval,
        accentColorHex: WatchReferenceSync.accentHexOf(
          OmniTheme.colorsForTheme(_settings.appTheme).primary,
        ),
        weightUnit: _settings.preferredWeightUnit,
        distanceUnit: _settings.preferredDistanceUnit,
        generatedAt: at,
      );

  Map<String, Object?>? _foodsFrame(DateTime at) => _foodLibrary.foods.isEmpty
      ? null
      : WatchReferenceSync.buildFoodsDown(
          foods: _foodLibrary.foods,
          groups: _foodLibrary.foodGroups,
          generatedAt: at,
        );

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
