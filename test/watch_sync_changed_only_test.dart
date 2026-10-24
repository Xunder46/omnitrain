// The phone sends the three reference frames only when the wrist's `since` is
// older than the bundle's stamp (plan 62, D-1..D-4).
//
// Scenario mapping:
//   S-9201 the first request sends the three, stamped alike
//          → `S-9201 ...`
//   S-9202 a wrist holding the current bundle is sent nothing → `S-9202 ...`
//   S-9203 the stamp boundary, one test per arm → `S-9203 ...`
//   S-9204 one changed input re-sends the three, stamped anew, one test per
//          arm → `S-9204 ...`
//   S-9205 equal content is an equal signature → `S-9205 ...`
//   S-9206 a frame the radio refused withholds the commit marker, one test
//          per arm → `S-9206 ...`
//   S-9207 a `since` the phone cannot read is no `since` → `S-9207 ...`
//   S-9209 the exercise list stays independent of the bundle → `S-9209 ...`
//   S-9210 a phone with no foods, then its first food → `S-9210 ...`
//   S-9211 two requests interleaved share one stamp → `S-9211 ...`
//   S-9212 a phone that relaunched re-sends once → `S-9212 ...`
// (S-9208, the `sinceOf` table, lives in `test/watch_transport_test.dart`.)
//
// The harness is the one from `test/watch_sync_request_handler_test.dart`,
// extended with a transport that can refuse a chosen frame type and suspend a
// send, and a clock the test moves.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/block_types.dart';
import 'package:omnitrain/core/platform/watch_delivery.dart';
import 'package:omnitrain/core/platform/watch_transport.dart';
import 'package:omnitrain/core/sync_protocol/wire_timestamps.dart';
import 'package:omnitrain/core/utils/watch_reference_sync.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/watch/live_session_mirror_state.dart';
import 'package:omnitrain/state/watch/watch_sync_request_handler.dart';
import 'package:omnitrain/state/watch/watch_sync_wiring.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/sync_protocol_harness.dart';

/// The three reference frames, in the order the phone sends them.
const List<String> _referenceFrames = [
  'preferences_down',
  'foods_down',
  'routines_down',
];

/// The stamp the first request carries: the test clock truncated to whole
/// milliseconds. The clock starts with a non-zero microsecond part, so a test
/// that sees this stamp has seen the truncation.
final DateTime _firstStamp = DateTime.utc(2026, 10, 23, 12, 0, 0, 123);

/// A transport that keeps what it was handed, can answer [undelivered] for
/// chosen frame types, and can suspend a send until a test releases it
/// (S-9211).
class _RecordingTransport implements WatchMirrorTransport {
  final List<Map<String, Object?>> sent = [];

  /// The frame types the radio refuses, or empty when it carries every frame.
  Set<String> undeliveredTypes = {};

  /// When set, every send suspends until it completes.
  Completer<void>? gate;

  /// How many sends have arrived at an open gate, so a test can tell that a
  /// request reached its first send.
  int waitingAtGate = 0;

  @override
  Future<WatchDelivery> send(Map<String, Object?> envelope) async {
    final gate = this.gate;
    if (gate != null) {
      waitingAtGate++;
      await gate.future;
    }
    sent.add(envelope);
    if (undeliveredTypes.contains(envelope['type'])) {
      return WatchDelivery.undelivered;
    }
    return WatchDelivery.delivered;
  }

  @override
  Future<void> requestSnapshot() async {}

  /// The types the transport was handed, in send order.
  List<String> get types => [
    for (final frame in sent) frame['type']! as String,
  ];

  /// Every frame of [type], in send order.
  List<Map<String, Object?>> ofType(String type) => [
    for (final frame in sent)
      if (frame['type'] == type) frame,
  ];

  /// The batch indices of the `exercises_down` frames it was handed, in order.
  List<Object?> get batchIndices => [
    for (final batch in ofType('exercises_down'))
      asObject(batch['payload'])['batchIndex'],
  ];
}

/// A food as the phone's library holds it, with values unlike the defaults.
Food _food(String id, String name, String groupId) => Food(
  id: id,
  name: name,
  groupId: groupId,
  unitType: FoodUnitType.grams,
  referenceAmount: 120,
  referenceLabel: 'g',
  protein: 25,
  carbs: 7,
  fat: 3,
  createdAtMs: clock.now.millisecondsSinceEpoch,
  updatedAtMs: clock.now.millisecondsSinceEpoch,
);

/// One routine with one segment and one effort, the way a phone would hold
/// one, so adding it changes the routines frame.
Future<void> _seedRoutine(MockWorkoutRepository repository) async {
  await repository.createExercise(
    Exercise(
      id: 'ex-changed-only',
      name: 'Changed Only Move',
      createdAtMs: clock.now.millisecondsSinceEpoch,
      updatedAtMs: clock.now.millisecondsSinceEpoch,
    ),
  );
  await repository.setExerciseCapabilities('ex-changed-only', const [
    'reps',
    'sets',
  ]);
  await repository.createTemplate(
    WorkoutTemplate(
      id: 'template-changed-only',
      ownerUserId: null,
      name: 'Changed Only Routine',
      description: null,
      focusModality: null,
      primaryDisciplineId: null,
      note: null,
      isBuiltInDemo: false,
      createdAtMs: clock.now.millisecondsSinceEpoch,
      updatedAtMs: clock.now.millisecondsSinceEpoch,
    ),
  );
  await repository.createTemplateSegment(
    TemplateSegment(
      id: 'template-changed-only-seg',
      templateId: 'template-changed-only',
      orderIndex: 0,
      segmentType: BlockTypes.strengthSets,
      disciplineId: null,
      name: 'Main',
      note: null,
      createdAtMs: clock.now.millisecondsSinceEpoch,
      updatedAtMs: clock.now.millisecondsSinceEpoch,
    ),
  );
  await repository.createTemplateEffort(
    TemplateEffort(
      id: 'template-changed-only-eff',
      templateSegmentId: 'template-changed-only-seg',
      orderIndex: 0,
      effortKind: BlockTypes.set,
      modality: null,
      exerciseId: 'ex-changed-only',
      note: null,
      restSeconds: null,
      restType: null,
      createdAtMs: clock.now.millisecondsSinceEpoch,
    ),
  );
}

/// Lets the pending futures run, until [done] holds or a generous bound
/// passes. Everything the handler awaits here completes without a real timer,
/// so a few turns of the event loop are enough.
Future<void> _pumpUntil(bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// The test's clock: a variable the handler's `clock:` reads, so a test moves
/// time. It starts with a non-zero microsecond part, which the handler's stamp
/// must truncate away.
final TestClock clock = TestClock(DateTime.utc(2026, 10, 23, 12, 0, 0, 123, 456));

void main() {
  late MockWorkoutRepository repository;
  late SettingsState settings;
  late _RecordingTransport transport;
  late WatchSyncRequestHandler handler;

  WatchSyncRequestHandler handlerFor(FoodLibraryState library) =>
      WatchSyncRequestHandler(
        mirror: LiveSessionMirrorState(
          transport: transport,
          snapshot: watchSessionPlaceholder,
        ),
        transport: transport,
        repository: repository,
        settings: settings,
        foodLibrary: library,
        clock: clock.call,
      );

  setUp(() async {
    repository = MockWorkoutRepository();
    await repository.initialize();
    settings = SettingsState(repository, fakePreferencesService());
    transport = _RecordingTransport();
    clock.now = DateTime.utc(2026, 10, 23, 12, 0, 0, 123, 456);
    handler = handlerFor(FoodLibraryState(repository));
  });

  /// A library holding four foods in two seeded categories, created out of
  /// order so the Foods-I-Eat order is not the insertion order.
  Future<FoodLibraryState> libraryWithFoods() async {
    await repository.createFood(
      _food('food-protein-lamb', 'Lamb Loin', 'food-group-proteins'),
    );
    await repository.createFood(
      _food('food-veg-broccoli', 'Broccoli Crowns', 'food-group-vegetables'),
    );
    await repository.createFood(
      _food('food-protein-beef', 'Beef Tenderloin', 'food-group-proteins'),
    );
    await repository.createFood(
      _food('food-veg-asparagus', 'Asparagus Spears', 'food-group-vegetables'),
    );

    final library = FoodLibraryState(repository);
    await library.loadFoods();
    await library.loadFoodGroups();
    return library;
  }

  /// The version the phone would name for the exercise list it holds right
  /// now.
  Future<String> currentVersion() async {
    final batches = await WatchReferenceSync.buildExercisesDown(
      repository: repository,
      generatedAt: clock.now,
    );
    return asObject(batches.first['payload'])['catalogVersion']! as String;
  }

  /// The `generatedAt` of the one `routines_down` frame sent so far — the
  /// stamp the wrist names back as its `since`.
  DateTime sentStamp() => parseUtcIso(
    asObject(transport.ofType('routines_down').single['payload'])['generatedAt'],
  );

  group('S-9201 the first request sends the three, stamped alike', () {
    test('S-9201 the frames travel in the order preferences, foods, routines, '
        'with one stamp truncated to whole milliseconds', () async {
      final answer = handlerFor(await libraryWithFoods());

      expect(await answer.handle(WatchTransportRequest.routines), isTrue);

      expect(
        transport.types.take(3),
        _referenceFrames,
        reason:
            'S-9201 the preferences lead, then the foods, then the routines '
            'as the bundle\'s commit marker',
      );
      expect(
        transport.batchIndices,
        [0, 1, 2],
        reason: 'S-9201 the exercise batches follow the three frames',
      );
      for (final type in _referenceFrames) {
        expect(
          asObject(transport.ofType(type).single['payload'])['generatedAt'],
          utcIso(_firstStamp),
          reason:
              'S-9201 $type carries the bundle stamp, the clock truncated to '
              'whole milliseconds',
        );
      }
    });
  });

  group('S-9202 a wrist holding the current bundle is sent nothing', () {
    test('S-9202 a second request naming the stamp, with nothing changed, '
        'sends zero frames', () async {
      final answer = handlerFor(await libraryWithFoods());
      await answer.handle(WatchTransportRequest.routines);
      final stamp = sentStamp();

      transport.sent.clear();
      clock.advance(const Duration(seconds: 10));

      expect(
        await answer.handle(
          WatchTransportRequest.routines,
          since: stamp,
          exercisesVersion: await currentVersion(),
        ),
        isTrue,
      );

      expect(
        transport.sent,
        isEmpty,
        reason:
            'S-9202 the wrist\'s since is the bundle\'s stamp, so none of the '
            'three frames and no exercise batch travels',
      );
    });
  });

  group('S-9203 the stamp boundary, one test per arm', () {
    test('S-9203 a since one millisecond before the stamp re-sends the three, '
        'with the same stamp', () async {
      final answer = handlerFor(await libraryWithFoods());
      await answer.handle(WatchTransportRequest.routines);
      final stamp = sentStamp();

      transport.sent.clear();
      clock.advance(const Duration(seconds: 7));

      expect(
        await answer.handle(
          WatchTransportRequest.routines,
          since: stamp.subtract(const Duration(milliseconds: 1)),
        ),
        isTrue,
      );

      expect(
        transport.types.take(3),
        _referenceFrames,
        reason: 'S-9203 a wrist one millisecond behind is older than the '
            'bundle',
      );
      for (final type in _referenceFrames) {
        expect(
          asObject(transport.ofType(type).single['payload'])['generatedAt'],
          utcIso(_firstStamp),
          reason:
              'S-9203 the stamp is stable: unchanged content keeps the stamp '
              'it already had',
        );
      }
    });

    test('S-9203 a since equal to the stamp sends none of the three', () async {
      final answer = handlerFor(await libraryWithFoods());
      await answer.handle(WatchTransportRequest.routines);
      final stamp = sentStamp();

      transport.sent.clear();
      clock.advance(const Duration(seconds: 7));

      expect(
        await answer.handle(WatchTransportRequest.routines, since: stamp),
        isTrue,
      );

      for (final type in _referenceFrames) {
        expect(
          transport.ofType(type),
          isEmpty,
          reason: 'S-9203 the wrist holds the current bundle, so $type stays '
              'put',
        );
      }
    });

    test('S-9203 a since one millisecond after the stamp sends none of the '
        'three either', () async {
      final answer = handlerFor(await libraryWithFoods());
      await answer.handle(WatchTransportRequest.routines);
      final stamp = sentStamp();

      transport.sent.clear();
      clock.advance(const Duration(seconds: 7));

      expect(
        await answer.handle(
          WatchTransportRequest.routines,
          since: stamp.add(const Duration(milliseconds: 1)),
        ),
        isTrue,
      );

      for (final type in _referenceFrames) {
        expect(
          transport.ofType(type),
          isEmpty,
          reason: 'S-9203 the wrist is never older than itself, so $type '
              'stays put',
        );
      }
    });
  });

  group('S-9204 one changed input re-sends the three, stamped anew', () {
    test('S-9204a a rest ping changed from 30 to 45 re-sends the three, and '
        'the preferences carry 45', () async {
      await settings.setRestPingInterval(30);
      final answer = handlerFor(await libraryWithFoods());
      await answer.handle(WatchTransportRequest.routines);
      final oldStamp = sentStamp();

      await settings.setRestPingInterval(45);
      clock.advance(const Duration(seconds: 7));
      transport.sent.clear();

      expect(
        await answer.handle(WatchTransportRequest.routines, since: oldStamp),
        isTrue,
      );

      expect(
        transport.types.take(3),
        _referenceFrames,
        reason: 'S-9204a the three travel together when the content changed',
      );
      expect(
        sentStamp().isAfter(oldStamp),
        isTrue,
        reason: 'S-9204a the changed bundle is stamped anew',
      );
      expect(
        asObject(
          transport.ofType('preferences_down').single['payload'],
        )['restPingSeconds'],
        45,
        reason: 'S-9204a the preferences carry the interval the phone holds '
            'now',
      );
    });

    test('S-9204b a food added re-sends the three with a new stamp', () async {
      final answer = handlerFor(await libraryWithFoods());
      await answer.handle(WatchTransportRequest.routines);
      final oldStamp = sentStamp();

      await repository.createFood(
        _food('food-extra', 'Extra Food', 'food-group-proteins'),
      );
      clock.advance(const Duration(seconds: 7));
      transport.sent.clear();

      expect(
        await answer.handle(WatchTransportRequest.routines, since: oldStamp),
        isTrue,
      );

      expect(
        transport.types.take(3),
        _referenceFrames,
        reason: 'S-9204b the three travel together when the content changed',
      );
      expect(
        sentStamp().isAfter(oldStamp),
        isTrue,
        reason: 'S-9204b the changed bundle is stamped anew',
      );
      final rows = objectsOf(
        asObject(transport.ofType('foods_down').single['payload'])['foods'],
      );
      expect(
        [for (final row in rows) row['foodId']],
        contains('food-extra'),
        reason: 'S-9204b the foods frame carries the food the phone gained',
      );
    });

    test('S-9204c a routine added re-sends the three with a new stamp', () async {
      final answer = handlerFor(await libraryWithFoods());
      await answer.handle(WatchTransportRequest.routines);
      final oldStamp = sentStamp();

      await _seedRoutine(repository);
      clock.advance(const Duration(seconds: 7));
      transport.sent.clear();

      expect(
        await answer.handle(WatchTransportRequest.routines, since: oldStamp),
        isTrue,
      );

      expect(
        transport.types.take(3),
        _referenceFrames,
        reason: 'S-9204c the three travel together when the content changed',
      );
      expect(
        sentStamp().isAfter(oldStamp),
        isTrue,
        reason: 'S-9204c the changed bundle is stamped anew',
      );
      final routines = objectsOf(
        asObject(transport.ofType('routines_down').single['payload'])['routines'],
      );
      expect(
        [for (final routine in routines) routine['routineId']],
        contains('template-changed-only'),
        reason: 'S-9204c the routines frame carries the routine the phone '
            'gained',
      );
    });

    test('S-9204 re-requesting with unchanged data yields the same stamp', () async {
      final answer = handlerFor(await libraryWithFoods());
      await answer.handle(WatchTransportRequest.routines);
      final stamp = sentStamp();

      clock.advance(const Duration(seconds: 7));
      transport.sent.clear();
      await answer.handle(
        WatchTransportRequest.routines,
        since: stamp.subtract(const Duration(milliseconds: 1)),
      );

      expect(
        sentStamp(),
        stamp,
        reason: 'S-9204 unchanged content keeps its stamp even as the clock '
            'moves',
      );
    });
  });

  group('S-9205 equal content is an equal signature', () {
    test('S-9205 two requests over unchanged content send identical frames '
        'with the same stamp', () async {
      final answer = handlerFor(await libraryWithFoods());
      await answer.handle(WatchTransportRequest.routines);
      final first = [
        for (final type in _referenceFrames) transport.ofType(type).single,
      ];

      clock.advance(const Duration(seconds: 7));
      transport.sent.clear();
      await answer.handle(WatchTransportRequest.routines);
      final second = [
        for (final type in _referenceFrames) transport.ofType(type).single,
      ];

      for (var i = 0; i < _referenceFrames.length; i++) {
        expect(
          jsonEncode(second[i]),
          jsonEncode(first[i]),
          reason:
              'S-9205 ${_referenceFrames[i]} over the same content is the '
              'same message, stamp and all, though the clock moved',
        );
      }
    });
  });

  group('S-9206 a frame the radio refused withholds the commit marker', () {
    test('S-9206a a preferences frame the radio refused means no routines '
        'frame, and the next request re-sends all three', () async {
      final answer = handlerFor(await libraryWithFoods());
      await answer.handle(WatchTransportRequest.routines);
      final oldStamp = sentStamp();

      // The phone's content changes, so the wrist's since is now genuinely
      // older than the bundle's stamp.
      await settings.setRestPingInterval(45);
      clock.advance(const Duration(seconds: 7));

      transport.sent.clear();
      transport.undeliveredTypes = {'preferences_down'};
      await answer.handle(WatchTransportRequest.routines, since: oldStamp);

      expect(
        transport.ofType('preferences_down'),
        hasLength(1),
        reason: 'S-9206a the preferences were attempted',
      );
      expect(
        transport.ofType('foods_down'),
        hasLength(1),
        reason:
            'S-9206a the foods still travel after a refused preferences '
            'frame',
      );
      expect(
        transport.ofType('routines_down'),
        isEmpty,
        reason: 'S-9206a the commit marker is withheld, so the wrist\'s since '
            'stays old',
      );

      transport.sent.clear();
      transport.undeliveredTypes = {};
      await answer.handle(WatchTransportRequest.routines, since: oldStamp);

      expect(
        transport.types.take(3),
        _referenceFrames,
        reason:
            'S-9206a the wrist\'s since is still old, so the next request '
            'sends all three',
      );
    });

    test('S-9206b a foods frame the radio refused means no routines frame, '
        'and the next request re-sends all three', () async {
      final answer = handlerFor(await libraryWithFoods());
      await answer.handle(WatchTransportRequest.routines);
      final oldStamp = sentStamp();

      await settings.setRestPingInterval(45);
      clock.advance(const Duration(seconds: 7));

      transport.sent.clear();
      transport.undeliveredTypes = {'foods_down'};
      await answer.handle(WatchTransportRequest.routines, since: oldStamp);

      expect(
        transport.ofType('preferences_down'),
        hasLength(1),
        reason: 'S-9206b the preferences were carried',
      );
      expect(
        transport.ofType('foods_down'),
        hasLength(1),
        reason: 'S-9206b the foods were attempted',
      );
      expect(
        transport.ofType('routines_down'),
        isEmpty,
        reason: 'S-9206b the commit marker is withheld, so the wrist\'s since '
            'stays old',
      );

      transport.sent.clear();
      transport.undeliveredTypes = {};
      await answer.handle(WatchTransportRequest.routines, since: oldStamp);

      expect(
        transport.types.take(3),
        _referenceFrames,
        reason:
            'S-9206b the wrist\'s since is still old, so the next request '
            'sends all three',
      );
    });

    test('S-9206c a routines frame the radio refused changes nothing about '
        'the next request', () async {
      final answer = handlerFor(await libraryWithFoods());
      await answer.handle(WatchTransportRequest.routines);
      final oldStamp = sentStamp();

      await settings.setRestPingInterval(45);
      clock.advance(const Duration(seconds: 7));

      transport.sent.clear();
      transport.undeliveredTypes = {'routines_down'};
      await answer.handle(WatchTransportRequest.routines, since: oldStamp);

      expect(
        transport.types.take(3),
        _referenceFrames,
        reason: 'S-9206c the commit marker itself was attempted',
      );

      transport.sent.clear();
      transport.undeliveredTypes = {};
      await answer.handle(WatchTransportRequest.routines, since: oldStamp);

      expect(
        transport.types.take(3),
        _referenceFrames,
        reason:
            'S-9206c the wrist\'s since is still old, so the next request '
            'sends all three again',
      );
    });
  });

  group('S-9207 a since the phone cannot read is no since', () {
    test('S-9207 absent, empty, non-string and unparseable since values are '
        'answered with everything', () async {
      final answer = handlerFor(await libraryWithFoods());
      await answer.handle(WatchTransportRequest.routines);

      for (final garbage in [null, '', 42, 'not a date']) {
        final frame = {
          'request': WatchTransportRequest.routines,
          'since': garbage,
        };
        expect(
          WatchTransportRequest.sinceOf(frame),
          isNull,
          reason: 'S-9207 $garbage names no stamp the phone can act on',
        );

        transport.sent.clear();
        await answer.handle(
          WatchTransportRequest.routines,
          since: WatchTransportRequest.sinceOf(frame),
        );
        expect(
          transport.types.take(3),
          _referenceFrames,
          reason: 'S-9207 an unreadable since is answered with everything',
        );
      }
    });
  });

  group('S-9209 the exercise list stays independent of the bundle', () {
    test('S-9209 a skipped bundle with a version the phone no longer holds '
        'still sends the batches', () async {
      final answer = handlerFor(await libraryWithFoods());
      await answer.handle(WatchTransportRequest.routines);
      final stamp = sentStamp();

      transport.sent.clear();
      clock.advance(const Duration(seconds: 7));

      expect(
        await answer.handle(
          WatchTransportRequest.routines,
          since: stamp,
          exercisesVersion: 'v1-0-nothing-here',
        ),
        isTrue,
      );

      for (final type in _referenceFrames) {
        expect(
          transport.ofType(type),
          isEmpty,
          reason: 'S-9209 the bundle was skipped, so $type stays put',
        );
      }
      expect(
        transport.batchIndices,
        [0, 1, 2],
        reason: 'S-9209 the version differs, so the whole list travels even '
            'though the bundle was skipped',
      );
    });

    test('S-9209 a sent bundle with the version the wrist holds sends no '
        'batch', () async {
      final answer = handlerFor(await libraryWithFoods());
      await answer.handle(WatchTransportRequest.routines);
      final oldStamp = sentStamp();
      final version = await currentVersion();

      await settings.setRestPingInterval(45);
      clock.advance(const Duration(seconds: 7));
      transport.sent.clear();

      expect(
        await answer.handle(
          WatchTransportRequest.routines,
          since: oldStamp,
          exercisesVersion: version,
        ),
        isTrue,
      );

      expect(
        transport.types.take(3),
        _referenceFrames,
        reason: 'S-9209 the changed bundle travels',
      );
      expect(
        transport.ofType('exercises_down'),
        isEmpty,
        reason: 'S-9209 the wrist holds the version the phone named, so no '
            'batch travels',
      );
    });
  });

  group('S-9210 a phone with no foods, then its first food', () {
    test('S-9210 the bundle is two frames, and the first food changes the '
        'signature', () async {
      await handler.handle(WatchTransportRequest.routines);

      expect(
        transport.types.take(2),
        ['preferences_down', 'routines_down'],
        reason: 'S-9210 no foods is no foods frame; the bundle is two frames',
      );
      expect(
        transport.ofType('foods_down'),
        isEmpty,
        reason: 'S-9210 a phone with no foods sends no foods frame',
      );
      final oldStamp = sentStamp();

      await repository.createFood(
        _food('food-first', 'First Food', 'food-group-proteins'),
      );
      clock.advance(const Duration(seconds: 7));
      transport.sent.clear();

      expect(
        await handler.handle(WatchTransportRequest.routines, since: oldStamp),
        isTrue,
      );

      expect(
        transport.types.take(3),
        _referenceFrames,
        reason: 'S-9210 the first food changes the bundle, so all three '
            'travel',
      );
      expect(
        sentStamp().isAfter(oldStamp),
        isTrue,
        reason: 'S-9210 the bundle with the food is stamped anew',
      );
    });
  });

  group('S-9211 two requests interleaved share one stamp', () {
    test('S-9211 two requests started without awaiting the first are both '
        'answered, and every frame of both carries the same stamp', () async {
      final answer = handlerFor(await libraryWithFoods());
      transport.gate = Completer<void>();

      final first = answer.handle(WatchTransportRequest.routines);
      await _pumpUntil(() => transport.waitingAtGate > 0);
      final second = answer.handle(WatchTransportRequest.routines);
      await _pumpUntil(() => transport.waitingAtGate > 1);

      transport.gate!.complete();
      expect(await first, isTrue, reason: 'S-9211 the first request is '
          'answered');
      expect(await second, isTrue, reason: 'S-9211 the second request is '
          'answered');

      final stamps = {
        for (final frame in transport.sent)
          if (_referenceFrames.contains(frame['type']))
            asObject(frame['payload'])['generatedAt'],
      };
      expect(
        stamps,
        {utcIso(_firstStamp)},
        reason: 'S-9211 every frame of both requests carries the one stamp '
            'the first of them derived',
      );
    });
  });

  group('S-9212 a phone that relaunched re-sends once', () {
    test('S-9212 a new handler over the same data sends all three at the '
        'wrist\'s old since', () async {
      final library = await libraryWithFoods();
      final answer = handlerFor(library);
      await answer.handle(WatchTransportRequest.routines);
      final stamp = sentStamp();

      clock.advance(const Duration(seconds: 7));
      final relaunched = handlerFor(library);
      transport.sent.clear();

      expect(
        await relaunched.handle(WatchTransportRequest.routines, since: stamp),
        isTrue,
      );

      expect(
        transport.types.take(3),
        _referenceFrames,
        reason: 'S-9212 the new handler holds no stamp in memory, so the '
            'wrist\'s old since is older than whatever it derives, and the '
            'three travel once',
      );
      expect(
        sentStamp().isAfter(stamp),
        isTrue,
        reason: 'S-9212 the new handler\'s stamp is its own clock',
      );
    });
  });
}
