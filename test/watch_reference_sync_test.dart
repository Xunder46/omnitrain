// The phone's `routines_down` producer: what the wrist reads to start a routine.
//
// Plan: `docs/plans/2026-09-21-13-watch-integration-shipping.md`,
// Phases 3 and 4 (D-6, D-7).
// Scenario mapping:
//   S-003 the phone builds routines on request  → `S-003 ...`
//   S-004 the wrist reflects the declared kind  → `S-004 ...`
//   S-007 the fallback list covers every exercise → `S-007 ...`
//   S-3604 the phone sends its whole exercise list  → `S-3604 ...` (plan
//         2026-10-11-23c, D-3601/D-3603/D-3604; S-3605..S-3607 in the same group)
//   S-253 the preferences the wrist honours        → `S-253 ...`
//         (Stats PR 2, `docs/plans/2026-09-25-02-stats-pr2-watch-capture-plan.md`,
//         D-113; the request/answer half is in `test/watch_transport_test.dart`)
//   S-3720/S-3721 the accent the phone sends       → `S-3720 ...` / `S-3721 ...`
//         (plan 2026-10-11-23d, D-3702; the table those accents come from is
//         S-3722, in `test/watch_accent_contract_test.dart`)
//
// The message is judged the way the watch judges it: written into the shared
// schema validator, then read back through the wrist's own types. A payload
// this file likes and the schema rejects would be a payload the wrist refuses.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
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

/// The accent `watch/contract/watch_accent_contract.json` names for [theme]:
/// the six accents both stacks agree on (plan 2026-10-11-23d, D-3705).
String _tableAccent(AppTheme theme) => _objects(
  _asObject(
    jsonDecode(
      File(
        '${Directory.current.path}/watch/contract/'
        'watch_accent_contract.json',
      ).readAsStringSync(),
    ),
  )['themes'],
).firstWhere((row) => row['theme'] == theme.name)['hex']! as String;

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
        containsAll([
          'exercise-goblet-squat',
          'exercise-easy-run',
          'exercise-plank-hold',
        ]),
        reason: 'S-003 the routine exercises are a subset of the whole list',
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
      expect(
        synced.fallbackExercises.map((exercise) => exercise.exerciseId),
        containsAll([
          'exercise-goblet-squat',
          'exercise-easy-run',
          'exercise-plank-hold',
        ]),
      );

      // The yoga routine's slots are what the wrist will log against, and they
      // carry the routine's declared kind as well as the capabilities.
      final yoga = synced.routines.last;
      expect(yoga.slots.single['sessionExerciseId'], 'sx-eff-plank');
      expect(yoga.slots.single['capabilities'], ['hold', 'time', 'sets']);
      expect(yoga.slots.single['effortKind'], 'timed');
    });

    test('S-003 a phone with no routines still answers with its exercise list',
        () async {
      final message = (await WatchReferenceSync.buildRoutinesDown(
        repository: repository,
        generatedAt: _generatedAt,
      ))!;

      expect(_rejections(message), isEmpty);
      final payload = _asObject(message['payload']);
      expect(
        payload['routines'],
        isEmpty,
        reason: 'S-003 an empty routines list is a valid list now, not a '
            'reason to stay silent (D-3601)',
      );
      expect(
        _objects(payload['fallbackExercises']),
        isNotEmpty,
        reason: 'S-003 the exercise list is what a routineless phone sends',
      );
    });
  });

  // Plan 2026-10-11-23c, Phase C2 (D-3601, D-3603, D-3604): the phone sends its
  // whole exercise list, so a wrist can add an exercise no routine mentions —
  // and it sends one even when it holds no routine at all.
  group('S-3604 the phone sends its whole exercise list', () {
    /// A phone holding only [exercises] — no seed catalog, no templates.
    Future<void> holdOnly(
      List<(String id, String name, List<String> capabilities)> exercises,
    ) async {
      repository.clear();
      for (final (id, name, capabilities) in exercises) {
        await repository.createExercise(
          Exercise(
            id: id,
            name: name,
            createdAtMs: _now.millisecondsSinceEpoch,
            updatedAtMs: _now.millisecondsSinceEpoch,
          ),
        );
        await repository.setExerciseCapabilities(id, capabilities);
      }
    }

    test('S-3604 no routines, three exercises: the two capable ones, sorted',
        () async {
      await holdOnly([
        ('exercise-zebra', 'Zebra Press', ['reps', 'sets']),
        ('exercise-custom', 'Custom Move', const []),
        ('exercise-apple', 'apple squat', ['reps', 'sets', 'load']),
      ]);

      final message = (await WatchReferenceSync.buildRoutinesDown(
        repository: repository,
        generatedAt: _generatedAt,
      ))!;

      expect(
        _rejections(message),
        isEmpty,
        reason: 'S-3604 a catalog-only message is one the wrist accepts',
      );
      final payload = _asObject(message['payload']);
      expect(payload['routines'], isEmpty);
      expect(
        _objects(payload['fallbackExercises']).map(
          (exercise) => exercise['exerciseId'],
        ),
        ['exercise-apple', 'exercise-zebra'],
        reason: 'S-3604 the two capable exercises, case-insensitively by name',
      );
    });

    test(
        'S-3605 one routine plus extras: both, no duplicates, name order',
        () async {
      await _addTemplate(
        repository,
        id: 'routine-mix',
        name: 'Mix',
        segmentIds: ['seg-mix'],
      );
      await _addEffort(
        repository,
        id: 'eff-mix',
        segmentId: 'seg-mix',
        orderIndex: 0,
        effortKind: 'set',
        exerciseId: 'exercise-goblet-squat',
      );

      final message = (await WatchReferenceSync.buildRoutinesDown(
        repository: repository,
        generatedAt: _generatedAt,
      ))!;
      final entries = _objects(
        _asObject(message['payload'])['fallbackExercises'],
      );
      final ids = [
        for (final entry in entries) entry['exerciseId']! as String,
      ];

      expect(ids, contains('exercise-goblet-squat'));
      expect(
        ids,
        contains('exercise-easy-run'),
        reason: 'S-3605 an exercise no routine mentions still travels',
      );
      expect(
        ids.toSet(),
        hasLength(ids.length),
        reason: 'S-3605 the routine exercise is not listed twice',
      );
      final names = [
        for (final entry in entries) (entry['name']! as String).toLowerCase(),
      ];
      expect(
        names,
        orderedEquals([...names]..sort()),
        reason: 'S-3605 the list is in the phone\'s name order',
      );
    });

    test('S-3606 a phone with no exercises answers nothing', () async {
      repository.clear();

      final message = await WatchReferenceSync.buildRoutinesDown(
        repository: repository,
        generatedAt: _generatedAt,
      );

      expect(
        message,
        isNull,
        reason: 'S-3606 nothing the wrist could log is nothing to send',
      );
    });

    test('S-3607 the seeded catalog fits well under the frame budget',
        () async {
      final message = (await WatchReferenceSync.buildRoutinesDown(
        repository: repository,
        generatedAt: _generatedAt,
      ))!;

      final bytes = utf8.encode(jsonEncode(message)).length;
      // ignore: avoid_print
      print('S-3607 routines_down for the seeded catalog: $bytes bytes');

      expect(_rejections(message), isEmpty);
      expect(bytes, lessThan(200000));
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

      final fallbackIds = _objects(payload['fallbackExercises'])
          .map((exercise) => exercise['exerciseId'])
          .toList();

      expect(
        fallbackIds,
        contains('exercise-goblet-squat'),
        reason: 'S-007 the routine exercise is in the catalog list',
      );
      expect(
        fallbackIds.toSet(),
        hasLength(fallbackIds.length),
        reason: 'S-007 an exercise used twice is listed once',
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

      final message = (await WatchReferenceSync.buildRoutinesDown(
        repository: repository,
        generatedAt: _generatedAt,
      ))!;

      final payload = _asObject(message['payload']);
      expect(
        payload['routines'],
        isEmpty,
        reason: 'S-007 a routine whose only effort cannot be rendered is '
            'dropped whole',
      );
      expect(
        _objects(payload['fallbackExercises']).map(
          (exercise) => exercise['exerciseId'],
        ),
        isNot(contains('exercise-goblet-squat')),
        reason: 'S-007 an exercise with no capabilities is not sent',
      );
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

  // Plan 2026-10-11-23d (D-3702, D-3705): the preferences carry the accent of
  // the theme the phone is wearing, so the wrist can wear the same one instead
  // of its default. S-3722 (the table those accents come from) and S-3723 (the
  // handler sends the current theme) are in `test/watch_accent_contract_test.dart`.
  group('S-3720 the accent the phone sends', () {
    test('S-3720 every theme travels as the accent the shared table names', () {
      for (final theme in AppTheme.values) {
        final message = WatchReferenceSync.buildPreferencesDown(
          effortRatingPrompt: false,
          restPingSeconds: 90,
          generatedAt: _generatedAt,
          accentColorHex: WatchReferenceSync.accentHexOf(
            OmniTheme.colorsForTheme(theme).primary,
          ),
        );

        expect(
          _rejections(message),
          isEmpty,
          reason:
              'S-3720 the wrist must be able to accept the accent of '
              '${theme.name}',
        );
        expect(
          _asObject(message['payload'])['accentColorHex'],
          _tableAccent(theme),
          reason: 'S-3720 ${theme.name} travels as the accent the wrist wears',
        );
      }
    });

    test('S-3720 a phone with no accent sends none rather than claiming one',
        () {
      final message = WatchReferenceSync.buildPreferencesDown(
        effortRatingPrompt: false,
        restPingSeconds: 90,
        generatedAt: _generatedAt,
      );

      expect(
        _rejections(message),
        isEmpty,
        reason: 'S-3720 the field is optional, so the wrist accepts its absence',
      );
      expect(
        _asObject(message['payload']).containsKey('accentColorHex'),
        isFalse,
        reason:
            'S-3720 an omitted accent reads at the wrist as no accent — the '
            'default look — while a sent one is a claim about the phone',
      );
    });

    test('S-3721 two accents stamped in one millisecond are two messages, and '
        'a rebuild is one', () {
      Map<String, Object?> built(AppTheme theme) =>
          WatchReferenceSync.buildPreferencesDown(
            effortRatingPrompt: false,
            restPingSeconds: 90,
            generatedAt: _generatedAt,
            accentColorHex: WatchReferenceSync.accentHexOf(
              OmniTheme.colorsForTheme(theme).primary,
            ),
          );

      final neon = built(AppTheme.abyssalNeon);

      expect(
        neon['messageId'],
        isNot(built(AppTheme.crimsonDojo)['messageId']),
        reason:
            'S-3721 a tie on generatedAt goes to the later-received copy, so a '
            'theme change must not be dropped as a redelivery',
      );
      expect(
        built(AppTheme.abyssalNeon)['messageId'],
        neon['messageId'],
        reason: 'S-3721 a rebuild of the same accent is the same message',
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
