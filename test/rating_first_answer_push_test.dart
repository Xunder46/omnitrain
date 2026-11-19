// The phone answers the effort question first, and tells the wrist (plan 42b).
//
// Plan: `docs/plans/2026-10-19-42b-rating-phone-answers-first-plan/`
// (D-1, D-3, D-4).
// Scenario mapping:
//   S-4306 the phone's answer travels as one snapshot carrying the wrist's own
//          rating id, and the wrist holds it          → `S-4306 ...`
//   S-4307 nothing more after that, and the wrist's own answer is never echoed
//                                                     → `S-4307 ...` (×2)
//   S-4308 an undelivered rating frame is re-offered  → `S-4308 ...`
//   S-4309 the negatives: active, unrated, other session → `S-4309 ...` (×3)
//
// The phone side is the graph `createWatchSync` builds — the shipping wiring,
// including the push it returns — over a fake radio; the wrist side is the real
// engine over an in-memory store, so the rating frame is applied the way the
// watch app applies one. Every window is closed by `flush()` rather than by
// waiting, and the tests are plain `test()` on a pinned clock: no `testWidgets`,
// no real-clock threshold.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/platform/watch_delivery.dart';
import 'package:omnitrain/core/platform/watch_transport.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/watch/watch_sync_wiring.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/sync_protocol_harness.dart' show loadProtocolValidator;
// `seedExercise` writes capabilities through `setExerciseCapabilities`, which is
// the only way they reach a repository: the projection refuses a slot whose
// exercise carries none, so this is load-bearing.
import 'helpers/watch_capture_import_harness.dart' show seedExercise;

final DateTime _now = DateTime.utc(2026, 10, 19, 9);

/// The session both devices know, and the id the phone answers for.
const String _sessionId = 's-w1';

/// The rating entry's id, shared with the wrist: the id a wrist-logged rating
/// carries, which the phone reuses so the wrist's open question closes
/// (plan 42b D-1).
const String _ratingId = 'rating-$_sessionId';

/// The slot the fixtures put in the ladder.
const String _firstSlot = 'sx-1';

Map<String, Object?> _asObject(Object? value) =>
    (value as Map).cast<String, Object?>();

List<Map<String, Object?>> _objects(Object? value) =>
    (value! as List).map(_asObject).toList(growable: false);

Map<String, Object?> _payload(Map<String, Object?> envelope) =>
    _asObject(envelope['payload']);

/// One ladder slot as the protocol spells it.
Map<String, Object?> _slot(
  String id,
  String exerciseId,
  String name,
  List<String> capabilities,
) => <String, Object?>{
  'sessionExerciseId': id,
  'exerciseId': exerciseId,
  'name': name,
  'effortKind': 'set',
  'capabilities': capabilities,
};

/// Lets the radio's dispatch settle before the next frame is handed over.
Future<void> _settle() => pumpEventQueue();

/// A catalog the phone can open a session from.
Future<void> _seedCatalog(WorkoutRepository repository) async {
  await seedExercise(
    repository,
    id: 'ex-squat',
    name: 'Squat',
    capabilities: ['sets', 'reps', 'load'],
  );
}

/// The phone's radio: records what the phone sent, hands the phone one frame
/// from the wrist the way the platform channel does, and reports what it cannot
/// carry the way the platform channel does — never by throwing (D-83).
class _PhoneRadio implements WatchTransport {
  _PhoneRadio(this.onFailure);

  final void Function(Object error) onFailure;

  final List<Map<String, Object?>> sent = [];

  /// Every frame handed to `send`, including the ones it then failed: the
  /// rating S-4308's first pass offered is only visible here.
  final List<Map<String, Object?>> attempted = [];

  /// True while the wrist is out of range: `send` carries nothing and answers
  /// `undelivered` without a failure (D-201's quiet half).
  bool unreachable = false;

  WatchInboundHandler? _handler;

  @override
  bool get isPhoneReachable => true;

  @override
  void onIncoming(WatchInboundHandler handler) => _handler = handler;

  @override
  Future<void> refreshReachability() async {}

  @override
  Future<void> requestRoutines({DateTime? since}) async =>
      send(WatchTransportRequest.routinesFrame(since: since));

  @override
  Future<void> requestSnapshot() async =>
      send(WatchTransportRequest.snapshotFrame());

  @override
  Future<WatchDelivery> send(Map<String, Object?> envelope) async {
    attempted.add(envelope);
    if (unreachable) return WatchDelivery.undelivered;
    sent.add(envelope);
    return WatchDelivery.delivered;
  }

  /// One frame from the wrist, the way the radio delivers one.
  Future<void> fromWrist(Map<String, Object?> frame) async {
    final handler = _handler;
    if (handler == null) {
      throw StateError('the phone graph never bound its inbound handler');
    }
    await handler(frame);
  }

  /// Everything the phone sent of one type, in order.
  List<Map<String, Object?>> ofType(String type) => [
    for (final envelope in sent)
      if (envelope['type'] == type) envelope,
  ];
}

void main() {
  late MockWorkoutRepository repository;
  late WorkoutState phoneState;
  late SettingsState phoneSettings;
  late _PhoneRadio radio;
  late WatchSyncGraph graph;
  late WatchSessionEngine engine;
  late InMemoryWatchSessionStore wristStore;
  late List<Map<String, Object?>> wristFrames;
  late List<Object> failures;

  /// The phone graph a fresh app start builds, over [radio]. The app binds its
  /// own `WorkoutState` to the adoption and to the push in `lib/main.dart`; the
  /// scenarios bind the push themselves, once their fixture has settled.
  Future<WatchSyncGraph> startGraph() async {
    final created = (await createWatchSync(
      repository: repository,
      nutritionState: NutritionState(repository),
      foodLibraryState: FoodLibraryState(repository),
      settingsState: phoneSettings,
      transport: radio,
      clock: () => _now,
      onFailure: (error, stack) => failures.add(error),
    ))!;
    created.adoption.bindWorkoutState(phoneState);
    return created;
  }

  /// The wrist starts [_sessionId] with one slot, and the phone adopts it: the
  /// fixture S-4306..S-4309 start from.
  Future<void> wristStartsSession() async {
    await engine.createSession(
      modality: null,
      exercises: [
        _slot(_firstSlot, 'ex-squat', 'Squat', ['sets', 'reps', 'load']),
      ],
    );
    await radio.fromWrist(engine.sessionSnapshot()!);
    await _settle();

    expect(
      phoneState.currentSession?.id,
      _sessionId,
      reason: "the fixture: the phone's own session is the wrist's",
    );
    expect(graph.mirror.sessionId, _sessionId);
  }

  /// The wrist ends its own session and says so: the phone's copy ends with it,
  /// through the router, with no rating of its own yet.
  Future<void> wristEndsSession() async {
    await engine.finishSession();
    final lifecycle = wristFrames.last;
    expect(
      lifecycle['type'],
      'session_lifecycle',
      reason: 'the fixture: the wrist announces its own end',
    );
    await radio.fromWrist(lifecycle);
    await _settle();
    expect(graph.mirror.status, WatchSessionStatus.completed);
    expect(phoneState.currentSession?.endedAtMs, isNotNull);
  }

  /// Every snapshot the phone sent that carries an effort rating entry — what
  /// this plan must produce once per answered session and never otherwise.
  List<Map<String, Object?>> ratingFrames() => [
    for (final envelope in radio.sent)
      if (envelope['type'] == 'session_snapshot' &&
          _objects(_payload(envelope)['entries']).any(
            (entry) => entry['kind'] == WatchInboxEntry.kindEffortRating,
          ))
        envelope,
  ];

  /// The rating entry of [envelope], which S-4306 inspects field by field.
  Map<String, Object?> ratingEntry(Map<String, Object?> envelope) =>
      _objects(_payload(envelope)['entries']).singleWhere(
        (entry) => entry['kind'] == WatchInboxEntry.kindEffortRating,
      );

  setUp(() async {
    failures = [];
    repository = MockWorkoutRepository();
    await repository.initialize();
    await _seedCatalog(repository);

    phoneState = WorkoutState(repository);
    phoneSettings = SettingsState(repository, fakePreferencesService());
    await phoneSettings.initialize();

    radio = _PhoneRadio(failures.add);
    graph = await startGraph();

    wristFrames = [];
    wristStore = InMemoryWatchSessionStore();
    engine = WatchSessionEngine(
      wristStore,
      clock: () => _now,
      sessionIdFactory: () => _sessionId,
      onEmit: wristFrames.add,
    );
  });

  group("S-4306 the phone's answer travels to the wrist as one snapshot", () {
    test(
      "S-4306 the answered session sends one snapshot carrying rating-s-w1, "
      'which validates and which the wrist stores under that id',
      () async {
        await wristStartsSession();
        graph.autoPush.bindWorkoutState(phoneState);
        await wristEndsSession();
        expect(
          phoneState.currentSession?.sessionFeeling,
          isNull,
          reason: 'the fixture: nobody has answered the effort question yet',
        );
        radio.sent.clear();

        // 4, not the wrist fixtures' 3: the frame's entry must carry the
        // phone's own answer, not the rating a fixture happens to use.
        await phoneState.updateSessionFeeling(_sessionId, 4);
        await graph.autoPush.flush();

        final frames = ratingFrames();
        expect(
          frames,
          hasLength(1),
          reason: 'S-4306 exactly one rating frame is sent',
        );
        final entry = ratingEntry(frames.single);
        expect(entry['entryId'], _ratingId);
        expect(entry['eventId'], _ratingId);
        expect(entry['kind'], WatchInboxEntry.kindEffortRating);
        expect(
          entry['rating'],
          4,
          reason: "S-4306 the entry carries the phone's own answer",
        );
        expect(
          entry['loggedAt'],
          isA<String>(),
          reason: 'S-4306 the entry carries the wall-clock instant it was made',
        );

        expect(
          loadProtocolValidator().validateEnvelope(frames.single),
          isEmpty,
          reason: 'S-4306 the envelope passes the Dart validator',
        );

        expect(
          await engine.applyMessage(frames.single),
          isTrue,
          reason: 'S-4306 the wrist applies the frame the way the watch app does',
        );
        final stored = engine.entries.singleWhere(
          (row) => row.recordId == _ratingId,
        );
        expect(stored.kind, WatchInboxEntry.kindEffortRating);
        expect(
          stored.payload['rating'],
          4,
          reason: "S-4306 the wrist stores the phone's own answer",
        );
        expect(failures, isEmpty);
      },
    );
  });

  group('S-4307 the first answer stands and nothing is echoed', () {
    test(
      'S-4307 a rated session already told to the wrist sends nothing more on '
      'the next trigger',
      () async {
        await wristStartsSession();
        graph.autoPush.bindWorkoutState(phoneState);
        await wristEndsSession();
        radio.sent.clear();

        await phoneState.updateSessionFeeling(_sessionId, 3);
        await graph.autoPush.flush();
        expect(ratingFrames(), hasLength(1), reason: 'the fixture: one frame');

        await phoneState.updateSessionFeeling(_sessionId, 3);
        await graph.autoPush.flush();
        expect(
          ratingFrames(),
          hasLength(1),
          reason: 'S-4307 a second notification sends no second rating frame',
        );
        expect(failures, isEmpty);
      },
    );

    test(
      "S-4307 a mirror that already holds the wrist's own rating sends nothing, "
      'even when the phone row is rated too',
      () async {
        await wristStartsSession();
        graph.autoPush.bindWorkoutState(phoneState);

        // The wrist answered first: its rating travel is an observation the
        // mirror folds into the converged entries.
        await engine.appendObservation(<String, Object?>{
          'entryId': _ratingId,
          'eventId': _ratingId,
          'kind': WatchInboxEntry.kindEffortRating,
          'loggedAt': _now.toIso8601String(),
          'rating': 3,
        });
        await radio.fromWrist(wristFrames.last);
        await _settle();
        expect(
          graph.mirror.holdsEffortRating,
          isTrue,
          reason: "the fixture: the mirror holds the wrist's own answer",
        );

        // Cleared before the end, not after: routing the wrist's end carries
        // the row's rating into the phone's copy, so the phone's session first
        // has a rating while it is ending — a frame sent at that moment must
        // still be counted below.
        radio.sent.clear();
        await wristEndsSession();
        await phoneState.updateSessionFeeling(_sessionId, 3);
        await graph.autoPush.flush();

        expect(
          ratingFrames(),
          isEmpty,
          reason:
              "S-4307 the wrist's own answer is never echoed back: the phone "
              'sends no rating entry for a session the mirror already holds one '
              'for',
        );
        expect(failures, isEmpty);
      },
    );
  });

  group('S-4308 a rating frame the radio did not carry is re-offered', () {
    test(
      'S-4308 the first send answers not-delivered, the next trigger sends '
      'again, and once delivered it stops',
      () async {
        await wristStartsSession();
        graph.autoPush.bindWorkoutState(phoneState);
        await wristEndsSession();
        radio.sent.clear();
        radio.attempted.clear();

        await phoneState.updateSessionFeeling(_sessionId, 3);

        radio.unreachable = true;
        await graph.autoPush.flush();
        expect(
          [
            for (final envelope in radio.attempted)
              if (envelope['type'] == 'session_snapshot' &&
                  _objects(_payload(envelope)['entries']).any(
                    (entry) =>
                        entry['kind'] == WatchInboxEntry.kindEffortRating,
                  ))
                envelope,
          ],
          hasLength(1),
          reason: 'S-4308 the first attempt was made and carried nothing',
        );
        expect(ratingFrames(), isEmpty);

        radio.unreachable = false;
        await phoneState.updateSessionFeeling(_sessionId, 3);
        await graph.autoPush.flush();
        expect(
          ratingFrames(),
          hasLength(1),
          reason: 'S-4308 the next trigger offers the owed rating again',
        );

        await phoneState.updateSessionFeeling(_sessionId, 3);
        await graph.autoPush.flush();
        expect(
          ratingFrames(),
          hasLength(1),
          reason: 'S-4308 once delivered, it stops',
        );
        expect(failures, isEmpty);
      },
    );
  });

  group('S-4309 the negative guards', () {
    test(
      'S-4309 a session still active with a rating sends no rating frame',
      () async {
        await wristStartsSession();
        graph.autoPush.bindWorkoutState(phoneState);
        radio.sent.clear();

        await phoneState.updateSessionFeeling(_sessionId, 3);
        await graph.autoPush.flush();

        expect(phoneState.currentSession?.endedAtMs, isNull);
        expect(
          ratingFrames(),
          isEmpty,
          reason:
              'S-4309 the wrist asks nothing for a session that is still '
              'running, so the phone must not answer it',
        );
        expect(failures, isEmpty);
      },
    );

    test('S-4309 an ended session with no rating sends no rating frame',
        () async {
      await wristStartsSession();
      graph.autoPush.bindWorkoutState(phoneState);
      radio.sent.clear();

      await wristEndsSession();
      await graph.autoPush.flush();

      expect(
        ratingFrames(),
        isEmpty,
        reason: 'S-4309 there is no answer to send',
      );
      expect(failures, isEmpty);
    });

    test(
      'S-4309 a mirror holding another session than the phone\'s current one '
      'sends no rating frame',
      () async {
        await wristStartsSession();
        graph.autoPush.bindWorkoutState(phoneState);

        // The phone moves on to a session of its own: the mirror still holds
        // the wrist's, and that session is not the one the rating answers for.
        await phoneState.createNewSession();
        final other = phoneState.currentSession!.id;
        final exercise = (await repository.getExerciseById('ex-squat'))!;
        await phoneState.addExerciseToSession(exercise);
        await phoneState.endSession();
        radio.sent.clear();

        await phoneState.updateSessionFeeling(other, 3);
        await graph.autoPush.flush();

        expect(other, isNot(_sessionId));
        expect(
          graph.mirror.sessionId,
          _sessionId,
          reason: "the fixture: the mirror still holds the wrist's session",
        );
        expect(
          ratingFrames(),
          isEmpty,
          reason:
              'S-4309 a frame for a session the wrist is not asking about is '
              'not sent',
        );
        expect(failures, isEmpty);
      },
    );
  });
}
