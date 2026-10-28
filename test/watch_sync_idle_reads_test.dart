// The phone skips its unchanged reference reads (plan 74, S-10405..S-10411).
//
// The harness is the one from `test/watch_sync_changed_only_test.dart`, with a
// repository subclass that answers a settable `referenceRevision` and counts
// the reference reads.

import 'dart:io';

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
import 'helpers/revisioned_repository.dart';
import 'helpers/sync_protocol_harness.dart';

/// The three reference frames, in the order the phone sends them.
const List<String> _referenceFrames = [
  'preferences_down',
  'foods_down',
  'routines_down',
];

/// A transport that keeps what it was handed.
class _RecordingTransport implements WatchMirrorTransport {
  final List<Map<String, Object?>> sent = [];

  @override
  Future<WatchDelivery> send(Map<String, Object?> envelope) async {
    sent.add(envelope);
    return WatchDelivery.delivered;
  }

  @override
  Future<void> requestSnapshot() async {}

  List<String> get types => [
    for (final frame in sent) frame['type']! as String,
  ];

  Map<String, Object?> singleOfType(String type) =>
      sent.singleWhere((frame) => frame['type'] == type);
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

/// One routine with one segment and one effort, so the routines frame has
/// content.
Future<void> _seedRoutine(MockWorkoutRepository repository) async {
  await repository.createExercise(
    Exercise(
      id: 'ex-idle-reads',
      name: 'Idle Reads Move',
      createdAtMs: clock.now.millisecondsSinceEpoch,
      updatedAtMs: clock.now.millisecondsSinceEpoch,
    ),
  );
  await repository.setExerciseCapabilities('ex-idle-reads', const [
    'reps',
    'sets',
  ]);
  await repository.createTemplate(
    WorkoutTemplate(
      id: 'template-idle-reads',
      ownerUserId: null,
      name: 'Idle Reads Routine',
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
      id: 'template-idle-reads-seg',
      templateId: 'template-idle-reads',
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
      id: 'template-idle-reads-eff',
      templateSegmentId: 'template-idle-reads-seg',
      orderIndex: 0,
      effortKind: BlockTypes.set,
      modality: null,
      exerciseId: 'ex-idle-reads',
      note: null,
      restSeconds: null,
      restType: null,
      createdAtMs: clock.now.millisecondsSinceEpoch,
    ),
  );
}

/// The test's clock.
final TestClock clock = TestClock(DateTime.utc(2026, 10, 23, 12, 0, 0, 123, 456));

void main() {
  late RevisionedRepository repository;
  late SettingsState settings;
  late _RecordingTransport transport;
  late WatchSyncRequestHandler handler;

  setUp(() async {
    repository = RevisionedRepository();
    await repository.initialize();
    settings = SettingsState(repository, fakePreferencesService());
    transport = _RecordingTransport();
    clock.now = DateTime.utc(2026, 10, 23, 12, 0, 0, 123, 456);
    handler = WatchSyncRequestHandler(
      mirror: LiveSessionMirrorState(
        transport: transport,
        snapshot: watchSessionPlaceholder,
      ),
      transport: transport,
      repository: repository,
      settings: settings,
      foodLibrary: FoodLibraryState(repository),
      clock: clock.call,
    );
  });

  /// A phone with 2 foods, 1 routine, 2 exercises, seeded and read once.
  Future<void> seedPhone() async {
    await repository.createFood(_food('idle-food-1', 'Idle Barley', 'group-a'));
    await repository.createFood(
      _food('idle-food-2', 'Idle Lentils', 'group-a'),
    );
    await repository.createExercise(
      Exercise(
        id: 'ex-idle-a',
        name: 'Idle Alpha',
        createdAtMs: clock.now.millisecondsSinceEpoch,
        updatedAtMs: clock.now.millisecondsSinceEpoch,
      ),
    );
    await repository.createExercise(
      Exercise(
        id: 'ex-idle-b',
        name: 'Idle Beta',
        createdAtMs: clock.now.millisecondsSinceEpoch,
        updatedAtMs: clock.now.millisecondsSinceEpoch,
      ),
    );
    await _seedRoutine(repository);
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

  /// The `generatedAt` of the one `routines_down` frame sent so far.
  DateTime sentStamp() => parseUtcIso(
    asObject(transport.singleOfType('routines_down')['payload'])['generatedAt'],
  );

  group('S-10405 the idle raise reads nothing', () {
    test('S-10405 a second request naming the stamp and version reads nothing '
        'and sends only the bests', () async {
      await seedPhone();
      expect(await handler.handle(WatchTransportRequest.routines), isTrue);
      final stamp = sentStamp();
      final version = await currentVersion();
      transport.sent.clear();
      repository.resetCounts();
      clock.advance(const Duration(seconds: 10));

      expect(
        await handler.handle(
          WatchTransportRequest.routines,
          since: stamp,
          exercisesVersion: version,
        ),
        isTrue,
      );

      expect(
        transport.types,
        ['bests_down'],
        reason: 'S-10405 an idle raise sends no reference frame, but the bests '
            'travel on every request (87a, D-4)',
      );
      expect(repository.foodReads, 0);
      expect(repository.groupReads, 0);
      expect(repository.templateReads, 0);
      expect(repository.segmentReads, 0);
      expect(repository.exerciseReads, 0);
      expect(repository.capabilityReads, 0);
    });
  });

  group('S-87c-17 a wrist holding the bests is sent none while they stand '
      'still', () {
    test('S-87c-17 a second idle raise sends no bests_down and reads no '
        'history', () async {
      await seedPhone();
      repository.history = 5;
      expect(
        await handler.handle(
          WatchTransportRequest.routines,
          holdsBests: true,
        ),
        isTrue,
      );
      final stamp = sentStamp();
      final version = await currentVersion();
      expect(
        transport.singleOfType('bests_down'),
        isNotNull,
        reason: 'S-87c-17 a wrist that holds nothing is sent the bests',
      );
      expect(
        repository.sessionReads,
        greaterThan(0),
        reason: 'S-87c-17 the first answer walks the history once',
      );

      transport.sent.clear();
      repository.resetCounts();
      clock.advance(const Duration(seconds: 10));

      expect(
        await handler.handle(
          WatchTransportRequest.routines,
          since: stamp,
          exercisesVersion: version,
          holdsBests: true,
        ),
        isTrue,
      );

      expect(
        transport.types,
        isEmpty,
        reason:
            'S-87c-17 the wrist holds the bests and the revision stands '
            'still, so no bests_down travels; the bundle and the list are '
            'held too, so nothing travels at all',
      );
      expect(
        repository.sessionReads,
        0,
        reason:
            'S-87c-17 the skip reads no history: no StatsProgressService is '
            'even created',
      );
    });
  });

  group('S-10406 a changed revision re-reads once and re-sends', () {
    test('S-10406 a new food and a bumped revision re-read the foods once and '
        're-send the three with a new stamp', () async {
      await seedPhone();
      expect(await handler.handle(WatchTransportRequest.routines), isTrue);
      final oldStamp = sentStamp();
      final version = await currentVersion();
      transport.sent.clear();
      repository.resetCounts();
      clock.advance(const Duration(seconds: 10));

      await repository.createFood(
        _food('idle-food-3', 'Idle Farro', 'group-a'),
      );
      repository.revision = repository.revision! + 1;

      expect(
        await handler.handle(
          WatchTransportRequest.routines,
          since: oldStamp,
          exercisesVersion: version,
        ),
        isTrue,
      );

      expect(transport.types.take(3), _referenceFrames);
      final newStamp = sentStamp();
      expect(newStamp.isAfter(oldStamp), isTrue);
      expect(repository.foodReads, 1);
      expect(repository.groupReads, 1);
      expect(
        transport.sent
            .where((frame) => frame['type'] == 'exercises_down')
            .toList(),
        isEmpty,
        reason: 'S-10406 the version is unchanged, so no exercise batch travels',
      );
    });
  });

  group('S-10407 a settings change with the revision standing still still '
      're-sends', () {
    test('S-10407 a rest-ping change re-sends the three with a new stamp and '
        'reads nothing', () async {
      await seedPhone();
      expect(await handler.handle(WatchTransportRequest.routines), isTrue);
      final oldStamp = sentStamp();
      transport.sent.clear();
      repository.resetCounts();
      clock.advance(const Duration(seconds: 10));

      await settings.setRestPingInterval(90);

      expect(
        await handler.handle(
          WatchTransportRequest.routines,
          since: oldStamp,
        ),
        isTrue,
      );

      expect(transport.types.take(3), _referenceFrames);
      expect(sentStamp().isAfter(oldStamp), isTrue);
      // The bundle is sent, so the library is read afresh for it (the send
      // block's own reload); the probe rebuild is what plan 74 skips.
      expect(repository.foodReads, 1);
      expect(repository.groupReads, 1);
    });
  });

  group('S-10409 a failed food read does not freeze the cache', () {
    test('S-10409 the second request reads again after a read threw', () async {
      await seedPhone();
      repository.throwOnceOnFoods = true;
      expect(await handler.handle(WatchTransportRequest.routines), isTrue);
      final stamp = sentStamp();
      final version = await currentVersion();
      transport.sent.clear();
      repository.resetCounts();
      clock.advance(const Duration(seconds: 10));

      expect(
        await handler.handle(
          WatchTransportRequest.routines,
          since: stamp,
          exercisesVersion: version,
        ),
        isTrue,
      );

      expect(repository.foodReads, 1);
      expect(repository.groupReads, 1);
    });
  });

  group('S-10410 an exercise change moves the list', () {
    test('S-10410 a changed exercise and a bumped revision rebuild the list '
        'and send it', () async {
      await seedPhone();
      expect(await handler.handle(WatchTransportRequest.routines), isTrue);
      final stamp = sentStamp();
      final oldVersion = await currentVersion();
      transport.sent.clear();
      repository.resetCounts();
      clock.advance(const Duration(seconds: 10));

      final exercises = await repository.getExercises();
      final target = exercises.firstWhere((e) => e.id == 'ex-idle-reads');
      await repository.updateExercise(
        Exercise(
          id: target.id,
          ownerUserId: target.ownerUserId,
          modality: target.modality,
          disciplineId: target.disciplineId,
          name: 'Idle Reads Move Renamed',
          description: target.description,
          movementPattern: target.movementPattern,
          isArchived: target.isArchived,
          createdAtMs: target.createdAtMs,
          updatedAtMs: clock.now.millisecondsSinceEpoch,
          capabilities: target.capabilities,
        ),
      );
      repository.revision = repository.revision! + 1;

      expect(
        await handler.handle(
          WatchTransportRequest.routines,
          since: stamp,
          exercisesVersion: oldVersion,
        ),
        isTrue,
      );

      final batches = transport.sent
          .where((frame) => frame['type'] == 'exercises_down')
          .toList();
      expect(batches, isNotEmpty);
      final newVersion =
          asObject(batches.first['payload'])['catalogVersion']! as String;
      expect(newVersion, isNot(oldVersion));
    });
  });

  group('S-10410 arms: a wrist whose list differs is sent it again', () {
    test('S-10410a a wrist naming another version is sent the list while the '
        'revision stands still', () async {
      await seedPhone();
      expect(await handler.handle(WatchTransportRequest.routines), isTrue);
      final stamp = sentStamp();
      final realVersion = await currentVersion();
      transport.sent.clear();
      repository.resetCounts();
      clock.advance(const Duration(seconds: 10));

      expect(
        await handler.handle(
          WatchTransportRequest.routines,
          since: stamp,
          exercisesVersion: 'v1-0-stale',
        ),
        isTrue,
      );

      final batches = transport.sent
          .where((frame) => frame['type'] == 'exercises_down')
          .toList();
      expect(batches, isNotEmpty);
      expect(
        asObject(batches.first['payload'])['catalogVersion'],
        realVersion,
      );
      expect(repository.exerciseReads, greaterThan(0));
    });

    test('S-10410b a wrist holding no list is sent it again while the '
        'revision stands still', () async {
      await seedPhone();
      expect(await handler.handle(WatchTransportRequest.routines), isTrue);
      final stamp = sentStamp();
      transport.sent.clear();
      repository.resetCounts();
      clock.advance(const Duration(seconds: 10));

      expect(
        await handler.handle(
          WatchTransportRequest.routines,
          since: stamp,
        ),
        isTrue,
      );

      final batches = transport.sent
          .where((frame) => frame['type'] == 'exercises_down')
          .toList();
      expect(batches, isNotEmpty);
      expect(repository.exerciseReads, greaterThan(0));
    });
  });

  group('S-10411 the revision is read once per request and before any read', () {
    test('S-10411 the revision statement precedes the reload in the source', () {
      final source = File('lib/state/watch/watch_sync_request_handler.dart')
          .readAsStringSync()
          .replaceAll(RegExp(r'//.*'), '');
      final revisionIndex = source.indexOf(
        'final revision = _repository.referenceRevision;',
      );
      final methodIndex = source.indexOf(
        'Future<bool> _sendRoutines({',
      );
      final reloadIndex = source.indexOf(
        'readFailed = !await _reloadFoods();',
      );
      expect(revisionIndex, greaterThanOrEqualTo(0));
      expect(methodIndex, greaterThanOrEqualTo(0));
      expect(reloadIndex, greaterThanOrEqualTo(0));
      expect(revisionIndex, greaterThan(methodIndex));
      expect(revisionIndex, lessThan(reloadIndex));
    });
  });
}
