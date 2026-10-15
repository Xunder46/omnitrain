// The phone's `routines_down` producer: what the wrist reads to start a routine.
//
// Plan: `docs/plans/2026-09-21-13-watch-integration-shipping.md`,
// Phases 3 and 4 (D-6, D-7).
// Scenario mapping:
//   S-003 the phone builds routines on request  → `S-003 ...`
//   S-004 the wrist reflects the declared kind  → `S-004 ...`
//   S-007 the fallback list covers every exercise → `S-007 ...`
//   S-253 the preferences the wrist honours        → `S-253 ...`
//         (Stats PR 2, `docs/plans/2026-09-25-02-stats-pr2-watch-capture-plan.md`,
//         D-113; the request/answer half is in `test/watch_transport_test.dart`)
//
// The message is judged the way the watch judges it: written into the shared
// schema validator, then read back through the wrist's own types. A payload
// this file likes and the schema rejects would be a payload the wrist refuses.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/core/utils/watch_reference_sync.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/watch/logging/watch_logging_state.dart';
import 'package:omnitrain/watch/logging/watch_metric_stepping.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';
import 'package:omnitrain/watch/start/watch_routine_catalog.dart';
import 'package:omnitrain/watch/start/watch_session_start_paths.dart';
import 'package:omnitrain/watch/start/watch_sync_orchestrator.dart';

const String _protocolRoot = 'watch/sync_protocol';

final DateTime _now = DateTime.utc(2026, 9, 21, 12);
final DateTime _generatedAt = DateTime.utc(2026, 9, 21, 12, 30);

Map<String, Object?> _asObject(Object? value) =>
    (value as Map).cast<String, Object?>();

List<Map<String, Object?>> _objects(Object? value) =>
    (value! as List).map(_asObject).toList(growable: false);

/// The shared schemas, keyed the way `$ref` addresses them.
SyncProtocolValidator _validator() {
  final root = Directory('${Directory.current.path}/$_protocolRoot/schemas');
  return SyncProtocolValidator({
    for (final file in root.listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('.json'))
        file.path.substring(root.path.length + 1): jsonDecode(
          file.readAsStringSync(),
        ),
  });
}

/// What the schema says about a message — empty means the wrist would accept it.
List<SyncProtocolRejection> _rejections(Map<String, Object?> message) =>
    _validator().validateEnvelope(message);

/// One planned effort, with the values a real routine carries.
Future<void> _addEffort(
  MockWorkoutRepository repository, {
  required String id,
  required String segmentId,
  required int orderIndex,
  required String effortKind,
  required String exerciseId,
  List<Map<String, Object?>> targets = const [],
  String segmentType = 'strength_sets',
}) async {
  await repository.createTemplateEffort(
    TemplateEffort(
      id: id,
      templateSegmentId: segmentId,
      orderIndex: orderIndex,
      effortKind: effortKind,
      modality: null,
      exerciseId: exerciseId,
      note: null,
      restSeconds: null,
      restType: null,
      createdAtMs: _now.millisecondsSinceEpoch,
    ),
  );

  for (final target in targets) {
    await repository.createTemplateTarget(
      TemplateTarget(
        id: '$id-${target['metric']}',
        templateEffortId: id,
        metricId: target['metric']! as String,
        setIndex: target['setIndex'] as int?,
        unitId: null,
        targetMin: (target['min'] as num?)?.toDouble(),
        targetMax: (target['max'] as num?)?.toDouble(),
        targetInt: target['int'] as int?,
        targetText: null,
        createdAtMs: _now.millisecondsSinceEpoch,
        updatedAtMs: _now.millisecondsSinceEpoch,
      ),
    );
  }
  // The segment's type is only read by the routine editor; the wire takes the
  // effort kind, so nothing here depends on it.
  expect(segmentType, isNotEmpty);
}

Future<void> _addTemplate(
  MockWorkoutRepository repository, {
  required String id,
  required String name,
  required List<String> segmentIds,
}) async {
  await repository.createTemplate(
    WorkoutTemplate(
      id: id,
      ownerUserId: null,
      name: name,
      description: null,
      focusModality: null,
      primaryDisciplineId: null,
      note: null,
      isBuiltInDemo: false,
      createdAtMs: _now.millisecondsSinceEpoch,
      updatedAtMs: _now.millisecondsSinceEpoch,
    ),
  );

  for (final (index, segmentId) in segmentIds.indexed) {
    await repository.createTemplateSegment(
      TemplateSegment(
        id: segmentId,
        templateId: id,
        orderIndex: index,
        segmentType: 'strength_sets',
        disciplineId: null,
        name: 'Segment ${index + 1}',
        note: null,
        createdAtMs: _now.millisecondsSinceEpoch,
        updatedAtMs: _now.millisecondsSinceEpoch,
      ),
    );
  }
}

void main() {
  late MockWorkoutRepository repository;

  setUp(() async {
    repository = MockWorkoutRepository();
    await repository.initialize();
  });

  /// The phone's three routines: a strength day, a conditioning day, and a
  /// mobility day whose Plank is declared `timed` — the case D-6 is about.
  Future<void> seedThreeRoutines() async {
    await _addTemplate(
      repository,
      id: 'routine-push',
      name: 'Chest + Back',
      segmentIds: ['seg-push'],
    );
    await _addEffort(
      repository,
      id: 'eff-goblet',
      segmentId: 'seg-push',
      orderIndex: 0,
      effortKind: 'set',
      exerciseId: 'exercise-goblet-squat',
      targets: [
        {'metric': 'metric-sets', 'int': 3},
        {'metric': 'metric-reps', 'int': 5},
        {'metric': 'metric-weight', 'min': 80},
      ],
    );

    await _addTemplate(
      repository,
      id: 'routine-cardio',
      name: 'Cardio',
      segmentIds: ['seg-cardio'],
    );
    await _addEffort(
      repository,
      id: 'eff-run',
      segmentId: 'seg-cardio',
      orderIndex: 0,
      effortKind: 'interval',
      exerciseId: 'exercise-easy-run',
      targets: [
        {'metric': 'metric-duration', 'int': 1200},
        {'metric': 'metric-distance', 'min': 5000},
      ],
    );

    await _addTemplate(
      repository,
      id: 'routine-mobility',
      name: 'Yoga',
      segmentIds: ['seg-mobility'],
    );
    await _addEffort(
      repository,
      id: 'eff-plank',
      segmentId: 'seg-mobility',
      orderIndex: 0,
      effortKind: 'timed',
      exerciseId: 'exercise-plank-hold',
      targets: [
        {'metric': 'metric-duration', 'int': 60},
      ],
    );
  }

  group('S-003 the payload the wrist reads', () {
    test('S-003 the message is schema-conformant and carries every routine',
        () async {
      await seedThreeRoutines();

      final message = (await WatchReferenceSync.buildRoutinesDown(
        repository: repository,
        generatedAt: _generatedAt,
      ))!;

      expect(_rejections(message), isEmpty);
      expect(message['type'], 'routines_down');
      expect(message['origin'], 'phone');

      final payload = _asObject(message['payload']);
      expect(payload['generatedAt'], '2026-09-21T12:30:00.000Z');
      expect(
        _objects(payload['routines']).map((routine) => routine['name']),
        ['Chest + Back', 'Cardio', 'Yoga'],
      );
      expect(
        _objects(payload['fallbackExercises']).map(
          (exercise) => exercise['exerciseId'],
        ),
        ['exercise-goblet-squat', 'exercise-easy-run', 'exercise-plank-hold'],
      );
    });

    test('S-003 the wrist deserializes it into routines it can start', () async {
      await seedThreeRoutines();

      final message = (await WatchReferenceSync.buildRoutinesDown(
        repository: repository,
        generatedAt: _generatedAt,
      ))!;
      final synced = WatchRoutinesDown.fromEnvelope(message);

      expect(synced.generatedAt, _generatedAt);
      expect(synced.routines.map((routine) => routine.name), [
        'Chest + Back',
        'Cardio',
        'Yoga',
      ]);
      expect(synced.fallbackExercises, hasLength(3));

      // The yoga routine's slots are what the wrist will log against, and they
      // carry the routine's declared kind as well as the capabilities.
      final yoga = synced.routines.last;
      expect(yoga.slots.single['sessionExerciseId'], 'sx-eff-plank');
      expect(yoga.slots.single['capabilities'], ['hold', 'time', 'sets']);
      expect(yoga.slots.single['effortKind'], 'timed');
    });

    test('S-003 an empty phone answers nothing rather than an empty list',
        () async {
      final message = await WatchReferenceSync.buildRoutinesDown(
        repository: repository,
        generatedAt: _generatedAt,
      );

      expect(message, isNull);
    });
  });

  group('S-66 an assisted routine reaches the wrist', () {
    /// One routine whose only planned effort benches 3×5 at [weightKg].
    Future<Map<String, Object?>> assistedMessage(num weightKg) async {
      await _addTemplate(
        repository,
        id: 'routine-assist',
        name: 'Assisted Bench',
        segmentIds: ['seg-assist'],
      );
      await _addEffort(
        repository,
        id: 'eff-assist',
        segmentId: 'seg-assist',
        orderIndex: 0,
        effortKind: 'set',
        exerciseId: 'exercise-goblet-squat',
        targets: [
          {'metric': 'metric-sets', 'int': 3},
          {'metric': 'metric-reps', 'int': 5},
          {'metric': 'metric-weight', 'min': weightKg},
        ],
      );

      return (await WatchReferenceSync.buildRoutinesDown(
        repository: repository,
        generatedAt: _generatedAt,
      ))!;
    }

    /// The one effort's planned targets, as the wrist read them back.
    Map<String, Object?> plannedTargets(Map<String, Object?> message) =>
        WatchRoutinesDown.fromEnvelope(
          message,
        ).routines.single.efforts.single.targets;

    test('S-66 a −20 kg plan validates and lands on the wrist as −20', () async {
      final message = await assistedMessage(-20);

      expect(
        _rejections(message),
        isEmpty,
        reason: 'S-66 an assisted plan is a plan, not a message to reject',
      );
      expect(
        plannedTargets(message)['loadKg'],
        -20,
        reason: 'S-66 the assist is not zeroed on the way out',
      );
    });

    test('S-66 a −200 kg plan validates and lands as the floor', () async {
      final message = await assistedMessage(-200);

      expect(_rejections(message), isEmpty, reason: 'S-66 the floor is legal');
      expect(
        plannedTargets(message)['loadKg'],
        -200,
        reason: 'S-66 the floor travels as itself',
      );
    });

    test('S-66 a −240 kg plan is refused on the targets gate', () async {
      final message = await assistedMessage(-240);
      final rejections = _rejections(message);

      expect(
        rejections.map((rejection) => rejection.code).toSet(),
        contains('constraint_violation'),
        reason: 'S-66 below the floor is refused, never clamped',
      );
      expect(
        rejections.map((rejection) => rejection.path).toList(),
        contains(contains('loadKg')),
        reason: 'S-66 the refusal names the planned load',
      );
    });
  });

  group('S-007 the fallback list covers what the routines reference', () {
    test('S-007 an exercise used twice is listed once', () async {
      await _addTemplate(
        repository,
        id: 'routine-a',
        name: 'Push A',
        segmentIds: ['seg-a'],
      );
      await _addEffort(
        repository,
        id: 'eff-a',
        segmentId: 'seg-a',
        orderIndex: 0,
        effortKind: 'set',
        exerciseId: 'exercise-goblet-squat',
      );

      await _addTemplate(
        repository,
        id: 'routine-b',
        name: 'Push B',
        segmentIds: ['seg-b'],
      );
      await _addEffort(
        repository,
        id: 'eff-b',
        segmentId: 'seg-b',
        orderIndex: 0,
        effortKind: 'set',
        exerciseId: 'exercise-goblet-squat',
      );

      final payload = _asObject(
        (await WatchReferenceSync.buildRoutinesDown(
          repository: repository,
          generatedAt: _generatedAt,
        ))!['payload'],
      );

      expect(
        _objects(payload['fallbackExercises']).map(
          (exercise) => exercise['exerciseId'],
        ),
        ['exercise-goblet-squat'],
      );
    });

    test('S-007 an exercise with no capabilities is not sent', () async {
      await _addTemplate(
        repository,
        id: 'routine-a',
        name: 'Push A',
        segmentIds: ['seg-a'],
      );
      // The catalog holds the exercise; nothing says what it can log. The wrist
      // could not render an effort for it, and an effort it cannot render is a
      // message it must reject whole.
      await repository.setExerciseCapabilities('exercise-goblet-squat', []);
      await _addEffort(
        repository,
        id: 'eff-a',
        segmentId: 'seg-a',
        orderIndex: 0,
        effortKind: 'set',
        exerciseId: 'exercise-goblet-squat',
      );

      final message = await WatchReferenceSync.buildRoutinesDown(
        repository: repository,
        generatedAt: _generatedAt,
      );

      expect(message, isNull);
    });

    test('S-007 the fallback list ends up in the wrist start paths', () async {
      await seedThreeRoutines();

      final message = (await WatchReferenceSync.buildRoutinesDown(
        repository: repository,
        generatedAt: _generatedAt,
      ))!;

      final engine = WatchSessionEngine(InMemoryWatchSessionStore());
      final paths = WatchSessionStartPaths(
        engine: engine,
        store: InMemoryWatchSessionStore(),
      );
      final orchestrator = WatchSyncOrchestrator(
        transport: _RecordingTransport(),
        paths: paths,
        engine: engine,
      );

      expect(await orchestrator.receive(message), isTrue);
      expect(paths.routines.map((routine) => routine.name), [
        'Chest + Back',
        'Cardio',
        'Yoga',
      ]);
      expect(
        paths.fallbackExercises.map((exercise) => exercise.exerciseId),
        containsAll([
          'exercise-goblet-squat',
          'exercise-easy-run',
          'exercise-plank-hold',
        ]),
      );
    });
  });

  group('S-004 the wrist reflects the routine\'s declared effort kind', () {
    test('S-004 a Plank declared timed renders as a timed effort', () async {
      await seedThreeRoutines();

      final message = (await WatchReferenceSync.buildRoutinesDown(
        repository: repository,
        generatedAt: _generatedAt,
      ))!;

      final engine = WatchSessionEngine(
        InMemoryWatchSessionStore(),
        clock: () => _now,
      );
      final paths = WatchSessionStartPaths(
        engine: engine,
        store: InMemoryWatchSessionStore(),
      );
      await WatchSyncOrchestrator(
        transport: _RecordingTransport(),
        paths: paths,
        engine: engine,
      ).receive(message);

      await paths.startFromRoutine('routine-mobility');
      final surface = WatchLoggingState(engine: engine, clock: () => _now);

      // Plank carries `time` and `hold`, which the capability rule reads as a
      // hold. The routine declared `timed`, and the routine is what the user set
      // up: the wrist shows the duration the plan asks for, not a hold timer.
      expect(surface.effortKind, WatchEffortKind.timed);
      expect(
        surface.fields.map((field) => field.metricKey),
        contains(WatchMetricKey.duration),
      );
    });

    test('S-004 a strength effort keeps the kind the routine declared',
        () async {
      await seedThreeRoutines();

      final message = (await WatchReferenceSync.buildRoutinesDown(
        repository: repository,
        generatedAt: _generatedAt,
      ))!;

      final engine = WatchSessionEngine(
        InMemoryWatchSessionStore(),
        clock: () => _now,
      );
      final paths = WatchSessionStartPaths(
        engine: engine,
        store: InMemoryWatchSessionStore(),
      );
      await WatchSyncOrchestrator(
        transport: _RecordingTransport(),
        paths: paths,
        engine: engine,
      ).receive(message);

      await paths.startFromRoutine('routine-push');
      final surface = WatchLoggingState(engine: engine, clock: () => _now);

      expect(surface.effortKind, WatchEffortKind.set);
      expect(
        surface.fields.map((field) => field.metricKey),
        contains(WatchMetricKey.weight),
      );
    });
  });

  group('S-253 the preferences the wrist honours', () {
    test('S-253 preferences_down conforms and carries the setting as given',
        () {
      for (final prompt in [true, false]) {
        final message = WatchReferenceSync.buildPreferencesDown(
          effortRatingPrompt: prompt,
          restPingSeconds: 90,
          generatedAt: _generatedAt,
        );

        expect(
          _rejections(message),
          isEmpty,
          reason: 'S-253 the wrist must be able to accept it ($prompt)',
        );
        expect(message['type'], 'preferences_down');
        expect(message['origin'], 'phone');
        expect(message['sentAt'], '2026-09-21T12:30:00.000Z');
        expect(
          message.containsKey('sessionId'),
          isFalse,
          reason: 'S-253 the setting describes the user, not a session',
        );
        expect(
          _asObject(message['payload']),
          {
            'generatedAt': '2026-09-21T12:30:00.000Z',
            'effortRatingPrompt': prompt,
            'restPingSeconds': 90,
          },
          reason: 'S-253 the payload is exactly the setting and its stamp',
        );
      }
    });

    test('S-253 a copy with other content is another message', () {
      final on = WatchReferenceSync.buildPreferencesDown(
        effortRatingPrompt: true,
        restPingSeconds: 90,
        generatedAt: _generatedAt,
      );
      final off = WatchReferenceSync.buildPreferencesDown(
        effortRatingPrompt: false,
        restPingSeconds: 90,
        generatedAt: _generatedAt,
      );
      final rebuilt = WatchReferenceSync.buildPreferencesDown(
        effortRatingPrompt: true,
        restPingSeconds: 90,
        generatedAt: _generatedAt,
      );

      expect(
        on['messageId'],
        isNot(off['messageId']),
        reason: 'S-253 a tie on generatedAt goes to the later-received copy, '
            'so two different settings must not share a delivery key',
      );
      expect(
        rebuilt['messageId'],
        on['messageId'],
        reason: 'S-253 a rebuild of the same setting is the same message',
      );
    });
  });

  // Plan 2026-10-09-21b, Phase 2 (D-1404, D-1411): the free-workout catalog
  // carries the exercise's own period length, so a wrist picking it can count
  // the period down from the phone's number.
  group('S-1406 the catalog carries the exercise\'s length', () {
    test(
      'S-1406 a round exercise\'s default travels, a set exercise\'s does not',
      () async {
        await repository.createExercise(
          Exercise(
            id: 'exercise-soccer',
            name: 'Soccer',
            defaultRoundDurationSecs: 2400,
            createdAtMs: _now.millisecondsSinceEpoch,
            updatedAtMs: _now.millisecondsSinceEpoch,
          ),
        );
        await repository.setExerciseCapabilities('exercise-soccer', const [
          'time',
          'rounds',
        ]);

        await _addTemplate(
          repository,
          id: 'routine-periods',
          name: 'Periods',
          segmentIds: ['seg-periods'],
        );
        await _addEffort(
          repository,
          id: 'eff-soccer-half',
          segmentId: 'seg-periods',
          orderIndex: 0,
          effortKind: 'round',
          exerciseId: 'exercise-soccer',
          targets: [
            {'metric': 'metric-rounds', 'int': 2},
            {'metric': 'metric-round-duration', 'int': 600},
          ],
        );
        await _addEffort(
          repository,
          id: 'eff-goblet',
          segmentId: 'seg-periods',
          orderIndex: 1,
          effortKind: 'set',
          exerciseId: 'exercise-goblet-squat',
          targets: [
            {'metric': 'metric-sets', 'int': 3},
            {'metric': 'metric-reps', 'int': 5},
          ],
        );

        final message = (await WatchReferenceSync.buildRoutinesDown(
          repository: repository,
          generatedAt: _generatedAt,
        ))!;

        expect(
          _rejections(message),
          isEmpty,
          reason:
              'S-1406 the catalog entry carries a field the wire declares, so '
              'the whole message stays one the wrist accepts',
        );

        final fallback = {
          for (final exercise
              in _objects(_asObject(message['payload'])['fallbackExercises']))
            exercise['exerciseId']! as String: exercise,
        };
        expect(
          fallback['exercise-soccer']!['roundDurationSecs'],
          2400,
          reason:
              'S-1406 the free-workout pick reads the exercise\'s own period '
              'length off the catalog entry',
        );
        expect(
          fallback['exercise-goblet-squat']!.containsKey('roundDurationSecs'),
          isFalse,
          reason: 'S-1406 a set exercise has no period length to send',
        );
      },
    );
  });
}

/// A transport that never invents a reply: the reply arrives through `receive`.
class _RecordingTransport implements WatchSyncTransport {
  final List<Map<String, Object?>> sent = [];

  @override
  bool get isPhoneReachable => false;

  @override
  Future<void> requestRoutines({DateTime? since}) async {}

  @override
  Future<void> requestSnapshot() async {}

  @override
  Future<void> send(Map<String, Object?> envelope) async => sent.add(envelope);
}
