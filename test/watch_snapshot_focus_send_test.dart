// The phone puts its session's modality into the `session_snapshot` it sends
// (plan 125d, S-12598 + S-12599): the projection carries the session's modality
// key verbatim only when the session has one, a validating receiver accepts the
// keyed frame whole, the auto-push costs no extra frame (baseline dedup), a
// converged-state frame still carries none, and a followed `session_end` that
// names a modality never rewrites the phone row's own value.
//
// Scenario mapping (plan `2026-11-05-125d-snapshot-focus-plan.md`):
//   S-12598 a followed end with a modality leaves the phone row's modality
//                                                       → `S-12598 ...`
//   S-12599 (a) a session with a modality rides its key   → `S-12599 (a) ...`
//   S-12599 (b) a session with none sends no key          → `S-12599 (b) ...`
//   S-12599 (c) the keyed projection validates whole      → `S-12599 (c) ...`
//   S-12599 (d) the key is the only difference            → `S-12599 (d) ...`
//   S-12599 (e) the session start pushes once             → `S-12599 (e) ...`
//   S-12599 (f) converged-state frames stay keyless       → `S-12599 (f) ...`
//
// Arms (a)-(d), (f) and the importer arm run on both stores (the parity
// invariant): the projection is a read, so what it reads must not depend on
// which store holds the rows. Arm (e) is Mock-only — the auto-push graph is
// Mock-only in its own suite (`watch_session_auto_push_test.dart`). Plain
// `test()`: no widget is involved, and a Hive write inside a widget test's
// fake-async zone never drains.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/platform/watch_delivery.dart';
import 'package:omnitrain/core/platform/watch_transport.dart';
import 'package:omnitrain/core/services/watch_session_importer.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart'
    show SyncProtocolValidator;
import 'package:omnitrain/core/sync_protocol/phone_envelope.dart';
import 'package:omnitrain/core/sync_protocol/wire_timestamps.dart' show utcIso;
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/watch/live_session_mirror_state.dart';
import 'package:omnitrain/state/watch/watch_session_adoption_bridge.dart';
import 'package:omnitrain/state/watch/watch_sync_wiring.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
// `seedExercise` writes capabilities through `setExerciseCapabilities`, which
// is the only way they reach a repository — `createExercise` ignores the
// inline list. The projection refuses a slot whose exercise carries none.
import 'helpers/repository_harness.dart'
    show harnessFactories, seedSession, fixtureStart;
import 'helpers/sync_protocol_harness.dart' show loadProtocolValidator;
import 'helpers/watch_capture_import_harness.dart' show seedExercise;

final DateTime _now = DateTime.utc(2026, 11, 6, 9);

/// Real time, but strictly increasing by at least a millisecond per read, so a
/// timer finished right after it started always ends after it began.
DateTime Function() _tickingClock() {
  var lastMs = 0;
  return () {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    lastMs = nowMs > lastMs ? nowMs : lastMs + 1;
    return DateTime.fromMillisecondsSinceEpoch(lastMs);
  };
}

Map<String, Object?> _asObject(Object? value) =>
    (value as Map).cast<String, Object?>();

List<Map<String, Object?>> _objects(Object? value) =>
    (value! as List).map(_asObject).toList(growable: false);

Map<String, Object?> _payload(Map<String, Object?> envelope) =>
    _asObject(envelope['payload']);

/// Lets the radio's dispatch settle before the next act.
Future<void> _settle() => pumpEventQueue();

/// One catalog exercise for the projection's single slot.
Future<Exercise> _seedBench(WorkoutRepository store) async {
  await seedExercise(
    store,
    id: 'ex-bench',
    name: 'Bench Press',
    capabilities: ['sets', 'reps', 'load'],
  );
  return (await store.getExerciseById('ex-bench'))!;
}

/// A projection's payload plus the id of the session it speaks for.
class _Projection {
  const _Projection(this.payload, this.sessionId);
  final Map<String, Object?> payload;
  final String sessionId;
}

/// Starts a session the way a screen does — a [modality] is what
/// `my_routines_screen` passes a routine's Focus through and what a Home tile
/// passes for its own — and gives the session one slot, then projects it with a
/// fresh bridge.
///
/// A fresh [WorkoutState] per projection keeps the ladder the one this helper
/// built: a state reused across arms would carry the segments of every session
/// an earlier arm started, and the projection would read them all. A fresh
/// bridge per projection keeps the revision deterministic: the same one-slot
/// ladder is counted once, so the two projections of arm (d) differ only where
/// they legitimately may.
Future<_Projection> _projectedSession(
  WorkoutRepository store,
  String? modality, {
  String? intent,
  String? title,
}) async {
  final state = WorkoutState(store);
  await state.createNewSession(
    modality: modality,
    intent: intent,
    title: title,
  );
  await state.addExerciseToSession((await store.getExerciseById('ex-bench'))!);
  await _settle();
  final bridge = WatchSessionAdoptionBridge(repository: store);
  bridge.bindWorkoutState(state);
  final payload = await bridge.projectSession(null);
  return _Projection(payload!, state.currentSession!.id);
}

Map<String, Object?> _withoutKeys(
  Map<String, Object?> payload,
  Set<String> keys,
) => {
  for (final entry in payload.entries)
    if (!keys.contains(entry.key)) entry.key: entry.value,
};

Map<String, Object?> _slotWithoutId(Map<String, Object?> slot) =>
    _withoutKeys(slot, {'sessionExerciseId'});

void main() {
  // The (a)-(d), (f) arms and the importer half of S-12598: the same
  // projection on both stores.
  for (final harnessFactory in harnessFactories) {
    final harness = harnessFactory();
    group('${harness.name} — S-12599 the phone names its session\'s modality', () {
      late WorkoutRepository store;
      late WorkoutState phoneState;

      setUp(() async {
        store = await harness.open();
        phoneState = WorkoutState(store);
        await _seedBench(store);
      });

      tearDown(harness.close);

      test(
        'S-12599 (a) a session with a modality rides its key, verbatim',
        () async {
          // A routine started the way `my_routines_screen` starts one: through
          // `createNewSession` with the routine's Focus as the modality. The
          // manifest-to-slots half of that screen is template infrastructure —
          // the wire rule this plan pins is the `modality:` route into the
          // session row, which the projection reads from `session.modality`.
          final routine = await _projectedSession(
            store,
            'isometric_stretching',
            intent: 'routine',
            title: 'Morning Mobility',
          );
          final routineSession = routine.payload;
          expect(
            routineSession['sessionId'],
            routine.sessionId,
            reason: 'the fixture: the projected session is the running one',
          );
          expect(
            routineSession['modality'],
            'isometric_stretching',
            reason:
                'S-12599 (a) a session started with a Focus sends its modality '
                'key as the row holds it, verbatim',
          );

          // A Home tile starts a session with its own modality the same way.
          final tileSession = (await _projectedSession(
            store,
            'cardio_endurance',
          )).payload;
          expect(tileSession['modality'], 'cardio_endurance');
        },
      );

      test('S-12599 (b) a session with no modality sends no key', () async {
        final freeSession = (await _projectedSession(store, null)).payload;
        expect(
          freeSession.containsKey('modality'),
          isFalse,
          reason:
              'S-12599 (b) omitted, never a null: a validating wrist refuses '
              'a null modality',
        );

        // The empty-string modality is buildable through the same public
        // route (`createNewSession(modality: '')`), the repository stores it
        // as it was given, and the projection still sends no key — never `""`
        // (an empty string would be refused whole by the schema's
        // `minLength: 1`).
        await phoneState.createNewSession(modality: '');
        final blankSessionId = phoneState.currentSession!.id;
        expect(
          (await store.getSession(blankSessionId))!.modality,
          '',
          reason: 'the fixture: the row carries the empty string',
        );
        await phoneState.addExerciseToSession(
          (await store.getExerciseById('ex-bench'))!,
        );
        final blankBridge = WatchSessionAdoptionBridge(repository: store)
          ..bindWorkoutState(phoneState);
        final blankSession = (await blankBridge.projectSession(null))!;
        expect(
          blankSession.containsKey('modality'),
          isFalse,
          reason:
              'S-12599 (b) an empty key is as good as none: the isNotEmpty '
              'guard keeps `""` off the wire',
        );
      });

      test(
        'S-12599 (c) the keyed projection validates as a whole frame',
        () async {
          final routineSession = (await _projectedSession(
            store,
            'isometric_stretching',
          )).payload;
          final validator = loadProtocolValidator();
          final envelope = phoneEnvelope(
            type: 'session_snapshot',
            messageId: 'msg-s12599-c',
            sentAt: _now,
            sessionId: routineSession['sessionId']! as String,
            payload: routineSession,
          );

          expect(
            validator.validateEnvelope(envelope),
            isEmpty,
            reason:
                'S-12599 (c) the keyed snapshot is the schema\'s `modality` '
                'property working: a zero-rejection frame reaches a validating '
                'receiver whole',
          );
        },
      );

      test(
        'S-12599 (d) the key is the only difference the modality makes',
        () async {
          // A keyed fixture whose modality is configured like no modality at
          // all (`resistance_lifting` is a `set` modality, so its session's slot
          // is built exactly as a hand-made session's is): the only difference
          // the two fixtures may carry is the key the change adds.
          final keyed = (await _projectedSession(
            store,
            'resistance_lifting',
          )).payload;
          final plain = (await _projectedSession(store, null)).payload;

          expect(keyed.containsKey('modality'), isTrue);
          expect(plain.containsKey('modality'), isFalse);

          // Every key is the same except the one the change adds, and every
          // value is the same except the two that have to differ: `sessionId`
          // names the session it speaks for, and each slot id is the effort the
          // session path minted for it (its id carries the wall-clock stamp of
          // its own creation). Both projections used a fresh bridge, so the
          // revision is the same.
          expect(
            _withoutKeys(keyed, {'modality'}).keys,
            unorderedEquals(plain.keys),
            reason: 'S-12599 (d) the keyed projection gains exactly one key',
          );

          final keyedExercises = _objects(keyed['exercises']);
          final plainExercises = _objects(plain['exercises']);
          expect(keyedExercises, hasLength(plainExercises.length));
          for (var i = 0; i < keyedExercises.length; i++) {
            expect(
              _slotWithoutId(keyedExercises[i]),
              _slotWithoutId(plainExercises[i]),
              reason:
                  'S-12599 (d) the slot bodies are identical once the '
                  'session-local slot ids are out of the way',
            );
          }

          final keyedBody = _withoutKeys(keyed, {
            'modality',
            'sessionId',
            'exercises',
          });
          final plainBody = _withoutKeys(plain, {'sessionId', 'exercises'});
          expect(
            keyedBody,
            plainBody,
            reason:
                'S-12599 (d) the keyed projection minus `modality` equals the '
                'keyless one for the same shape of session — same status, same '
                'revision count for the same ladder, same index, entries, timers',
          );
        },
      );

      test(
        'S-12599 (f) a converged-state frame still carries no modality',
        () async {
          // The wrist reports the very session this phone holds: its snapshot
          // is applied and the mirror converges with it. The fixture hands the
          // mirror the phone's own keyed projection as that wrist snapshot —
          // whatever key rides it, the reconciler's converged state has fixed
          // keys, so the converged frames below must still carry none.
          final keyed = (await _projectedSession(
            store,
            'isometric_stretching',
          )).payload;
          final sent = <Map<String, Object?>>[];
          final mirror = LiveSessionMirrorState(
            transport: _CollectingTransport(sent),
            snapshot: watchSessionPlaceholder,
            validator: loadProtocolValidator(),
            clock: _tickingClock(),
            idFactory: () => 'msg-s12599-f',
            projection: (_) async => keyed,
          );
          await mirror.receive(_wristSnapshot(keyed));
          await _settle();

          sent.clear();
          await mirror.sendSnapshot();
          expect(sent, hasLength(1), reason: 'the fixture: one keyless frame');
          final pushed = _payload(sent.single);
          expect(
            pushed.containsKey('modality'),
            isFalse,
            reason:
                'S-12599 (f) a converged-state frame composes fixed keys; a '
                'modality can never ride one even when the phone\'s own session '
                'has one',
          );
          expect(
            loadProtocolValidator().validateEnvelope(sent.single),
            isEmpty,
            reason: 'S-12599 (f) the keyless frame is still a valid frame',
          );

          sent.clear();
          await mirror.sendRatingFor(keyed['sessionId']! as String, 5);
          final ratingFrame = sent.single;
          expect(
            _payload(ratingFrame).containsKey('modality'),
            isFalse,
            reason: 'S-12599 (f) the rating answer rides the same rule',
          );
          expect(
            loadProtocolValidator().validateEnvelope(ratingFrame),
            isEmpty,
          );
        },
      );
    });

    group('${harness.name} — S-12598 the followed end leaves the row\'s '
        'modality alone', () {
      late WorkoutRepository store;

      setUp(() async => store = await harness.open());
      tearDown(harness.close);

      test('S-12598 (importer half) a followed end naming a modality stores '
          'only the heart rate', () async {
        await seedSession(
          store,
          sessionId: 'phone-s12598',
          modality: 'resistance_lifting',
        );
        await store.stageWatchInboxEntry(
          _followedEnd('phone-s12598', endModality: 'isometric_stretching'),
        );

        final result = await WatchSessionImporter(
          repository: store,
        ).apply('phone-s12598');

        final row = (await store.getSession('phone-s12598'))!;
        expect(
          row.modality,
          'resistance_lifting',
          reason:
              'S-12598 the importer\'s followed branch reads the end\'s heart '
              'rate and nothing else: the wrist\'s Focus never overwrites the '
              'phone row\'s own modality',
        );
        expect(
          row.endedAtMs,
          isNotNull,
          reason: 'the fixture: the phone row was already history',
        );
        final summaries = [
          for (final summary in await store.getSensorSummariesForSession(
            'phone-s12598',
          ))
            if (summary.scope == SensorSummary.scopeSession) summary,
        ];
        expect(summaries, hasLength(1), reason: 'exactly one summary attached');
        expect(
          summaries.single.avgHeartRateBpm,
          _followedAvg,
          reason: 'the followed end stored the heart rate only',
        );
        expect(summaries.single.maxHeartRateBpm, _followedMax);
        expect(result.appliedEntryIds, [
          'end-phone-s12598',
        ], reason: 'the receipt names the end only');
        expect(result.sensorSummaryAttached, isTrue);
      });
    });
  }

  // Arm (e) alone: the auto-push path, Mock-only like its own suite.
  group('S-12599 (e) the session start is one frame, then none (Mock)', () {
    late MockWorkoutRepository repository;
    late WorkoutState phoneState;
    late SettingsState phoneSettings;
    late _PhoneRadio radio;
    late WatchSyncGraph graph;
    late List<Object> failures;

    setUp(() async {
      failures = [];
      repository = MockWorkoutRepository();
      await repository.initialize();
      await seedExercise(
        repository,
        id: 'ex-bench',
        name: 'Bench Press',
        capabilities: ['sets', 'reps', 'load'],
      );

      phoneState = WorkoutState(repository, clock: _tickingClock());
      phoneSettings = SettingsState(repository, fakePreferencesService());
      await phoneSettings.initialize();

      radio = _PhoneRadio(failures.add);
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
      graph = created;
    });

    test('S-12599 (e) a session start pushes exactly one snapshot', () async {
      graph.autoPush.bindWorkoutState(phoneState);

      await phoneState.createNewSession(modality: 'cardio_endurance');
      await phoneState.addExerciseToSession(
        (await repository.getExerciseById('ex-bench'))!,
      );
      await graph.autoPush.flush();
      final pushes = radio.ofType('session_snapshot');
      expect(pushes, hasLength(1), reason: 'one change, one frame');
      expect(
        loadProtocolValidator().validateEnvelope(pushes.single),
        isEmpty,
        reason: 'the pushed frame is a valid frame',
      );
      expect(
        _payload(pushes.single)['sessionId'],
        phoneState.currentSession!.id,
      );

      // A second pass over an unchanged state is the baseline dedup: the
      // payload the phone already sent composes identically, so the wrist
      // hears nothing again — the modality key buys no churn (D-76).
      await graph.autoPush.flush();
      expect(
        radio.ofType('session_snapshot'),
        hasLength(1),
        reason: 'S-12599 (e) a second identical push sends none',
      );
      expect(failures, isEmpty);
    });
  });
}

/// The heart rates unlike any fixture default, as plan 71's followed-end test
/// spells them.
const double _followedAvg = 133;
const double _followedMax = 171;

String _iso(int ms) =>
    DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();

WatchInboxEntry _followedEnd(
  String session, {
  required String endModality,
  String status = 'completed',
}) {
  final start = fixtureStart;
  final end = start + 3600000;
  return WatchInboxEntry(
    entryId: 'end-$session',
    watchSessionId: session,
    kind: WatchInboxEntry.kindSessionEnd,
    origin: WatchInboxEntry.originWatch,
    payload: {
      'eventId': 'end-$session',
      'entryId': 'end-$session',
      'kind': WatchInboxEntry.kindSessionEnd,
      'loggedAt': _iso(end),
      'startedAt': _iso(start),
      'endedAt': _iso(end),
      'status': status,
      'followed': true,
      // The wrist stamps the modality of the session it ran, from its row; the
      // phone's own row keeps its own value whatever this says.
      'modality': endModality,
      'avgHeartRateBpm': _followedAvg,
      'maxHeartRateBpm': _followedMax,
    },
    receivedAtMs: fixtureStart + 7200000,
  );
}

/// A wrist snapshot envelope for [payload], as the engine's snapshot builder
/// spells one.
Map<String, Object?> _wristSnapshot(Map<String, Object?> payload) => {
  'protocolVersion': SyncProtocolValidator.protocolVersion,
  'messageId': 'w-snap',
  'sessionId': payload['sessionId'],
  'type': 'session_snapshot',
  'origin': 'watch',
  'sentAt': utcIso(DateTime.now().toUtc()),
  'payload': payload,
};

/// The mirror's transport: records what the phone sent, carries all of it.
class _CollectingTransport implements WatchMirrorTransport {
  _CollectingTransport(this.sent);

  final List<Map<String, Object?>> sent;

  @override
  Future<WatchDelivery> send(Map<String, Object?> envelope) async {
    sent.add(envelope);
    return WatchDelivery.delivered;
  }

  @override
  Future<void> requestSnapshot() async {}
}

/// The phone's radio, copied from `watch_session_auto_push_test.dart`: records
/// what the phone sent, hands the phone one frame from the wrist the way the
/// platform channel does, and reports what it cannot carry the way the platform
/// channel does — never by throwing (D-83).
class _PhoneRadio implements WatchTransport {
  _PhoneRadio(this.onFailure);

  final void Function(Object error) onFailure;

  final List<Map<String, Object?>> sent = [];

  /// Every frame handed to `send`, including the ones it then failed: what a
  /// pass tried to announce is not visible in [sent] alone (F7).
  final List<Map<String, Object?>> attempted = [];

  /// True while the wrist is out of range: `send` reports and carries nothing.
  bool failing = false;

  @override
  bool get isPhoneReachable => true;

  @override
  void onIncoming(WatchInboundHandler handler) {}

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
    if (failing) {
      onFailure(StateError('the wrist is out of range'));
      return WatchDelivery.undelivered;
    }
    sent.add(envelope);
    return WatchDelivery.delivered;
  }

  /// Everything the phone sent of one type, in order.
  List<Map<String, Object?>> ofType(String type) => [
    for (final envelope in sent)
      if (envelope['type'] == type) envelope,
  ];
}
