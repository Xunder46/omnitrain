// The phone's `routines_down` producer: what the wrist reads to start a routine.
//
// Plan: `docs/plans/2026-09-21-13-watch-integration-shipping.md`,
// Phases 3 and 4 (D-6, D-7).
// Scenario mapping:
//   S-003 the phone builds routines on request  → `S-003 ...`
//   S-004 the wrist reflects the declared kind  → `S-004 ...`
//   S-007 the fallback list covers every exercise → `S-007 ...`
//   S-3840..S-3846 the phone sends the list in batches → `S-3840 ...`,
//         `S-3843 ...`, `S-3844 ...` (plan 2026-10-11-23e2, D-3830/D-3831/
//         D-3832; they replace the 23c group S-3604..S-3607)
//   S-3858 the real seeded catalog fits the frame budget → `S-3858 ...`
//         (the 23c S-3607 budget guard, restored over the seeded catalog)
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
import 'package:omnitrain/core/constants/modality.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/core/sync_protocol/wire_timestamps.dart';
import 'package:omnitrain/core/utils/foods_i_eat_order.dart';
import 'package:omnitrain/core/utils/logged_entry_rows.dart';
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

import 'helpers/yoga_catalog_rows.dart';

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

      final message = await WatchReferenceSync.buildRoutinesDown(
        repository: repository,
        generatedAt: _generatedAt,
      );

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
        reason: 'S-003 the fallback list is the exercises the routines '
            'themselves use (D-3830)',
      );
    });

    test('S-003 the wrist deserializes it into routines it can start', () async {
      await seedThreeRoutines();

      final message = await WatchReferenceSync.buildRoutinesDown(
        repository: repository,
        generatedAt: _generatedAt,
      );
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
      // carry the routine's declared kind as well as the capabilities. The id
      // shown is the plain base; the session's token is appended at start
      // (plan 81 D-1).
      final yoga = synced.routines.last;
      expect(yoga.slotsFor('testtoken').single['sessionExerciseId'],
          'sx-eff-plank~testtoken');
      expect(yoga.slotsFor('testtoken').single['capabilities'],
          ['hold', 'time', 'sets']);
      expect(yoga.slotsFor('testtoken').single['effortKind'], 'timed');
    });

    test('S-003 a phone with no routines still answers, with both lists empty',
        () async {
      final message = await WatchReferenceSync.buildRoutinesDown(
        repository: repository,
        generatedAt: _generatedAt,
      );

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
        isEmpty,
        reason: 'S-003 the fallback list holds the exercises the routines use '
            'and nothing else, and this phone has no routine (D-3830); the '
            'whole catalog travels as `exercises_down` instead (D-3831)',
      );
    });
  });

  // Plan 2026-10-11-23e2, Phase P1 (D-3830, D-3831): the routines message
  // carries the routines and the exercises they use, and the whole catalog
  // travels as the `exercises_down` batches the wrist assembles itself.
  group('S-3840..S-3843, S-3845, S-3846 the phone sends the list in batches', () {
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

    test('S-3840 no templates: a message with both lists empty', () async {
      await holdOnly([
        ('exercise-zebra', 'Zebra Press', ['reps', 'sets']),
        ('exercise-custom', 'Custom Move', const []),
        ('exercise-apple', 'apple squat', ['reps', 'sets', 'load']),
      ]);

      final message = await WatchReferenceSync.buildRoutinesDown(
        repository: repository,
        generatedAt: _generatedAt,
      );

      expect(
        _rejections(message),
        isEmpty,
        reason: 'S-3840 an empty fallback list is a message the wrist accepts',
      );
      final payload = _asObject(message['payload']);
      expect(payload['routines'], isEmpty);
      expect(
        payload['fallbackExercises'],
        isEmpty,
        reason: 'S-3840 nothing references the three exercises, so none of '
            'them is fallback material (D-3830)',
      );

      final synced = WatchRoutinesDown.fromEnvelope(message);
      expect(synced.routines, isEmpty);
      expect(
        synced.fallbackExercises,
        isEmpty,
        reason: 'S-3840 the wrist reads both empty lists, not a rejection',
      );
    });

    test('S-3841 the fallback list is the exercises the routines use',
        () async {
      await holdOnly([
        ('exercise-a', 'Alpha Press', ['reps', 'sets']),
        ('exercise-b', 'Beta Row', ['reps', 'sets']),
        ('exercise-c', 'Gamma Run', ['time', 'distance']),
      ]);
      await _addTemplate(
        repository,
        id: 'routine-a',
        name: 'A',
        segmentIds: ['seg-a'],
      );
      await _addEffort(
        repository,
        id: 'eff-a',
        segmentId: 'seg-a',
        orderIndex: 0,
        effortKind: 'set',
        exerciseId: 'exercise-a',
      );

      final message = await WatchReferenceSync.buildRoutinesDown(
        repository: repository,
        generatedAt: _generatedAt,
      );

      expect(_rejections(message), isEmpty);
      expect(
        _objects(_asObject(message['payload'])['fallbackExercises']).map(
          (exercise) => exercise['exerciseId'],
        ),
        ['exercise-a'],
        reason: 'S-3841 B and C exist but no routine uses them, so they are '
            'not in the fallback list (D-3830)',
      );
    });

    test('S-3842 a phone with no exercises at all still answers', () async {
      repository.clear();

      final message = await WatchReferenceSync.buildRoutinesDown(
        repository: repository,
        generatedAt: _generatedAt,
      );

      expect(_rejections(message), isEmpty);
      final payload = _asObject(message['payload']);
      expect(payload['routines'], isEmpty);
      expect(payload['fallbackExercises'], isEmpty);
      expect(
        message['type'],
        'routines_down',
        reason: 'S-3842 a phone with nothing still tells the wrist so, rather '
            'than leaving it holding the routines the user deleted (D-3830)',
      );
    });

    test('S-3843 250 exercises arrive as three batches in name order', () async {
      // Two of the names carry the number 100 in opposite cases, so the
      // phone's case-insensitive order ties them (broken by id) and puts the
      // lowercase one among the `Exercise …` names, while Dart's code-unit
      // sort would put it after every one of them.
      final rows = <(String, String)>[
        for (var index = 0; index < 250; index++)
          (
            'ex-${index.toString().padLeft(3, '0')}',
            index == 100
                ? 'exercise 100'
                : 'Exercise ${(249 - index).toString().padLeft(3, '0')}',
          ),
      ];
      await holdOnly([
        for (final (id, name) in rows) (id, name, const ['reps', 'sets']),
      ]);

      final batches = await WatchReferenceSync.buildExercisesDown(
        repository: repository,
        generatedAt: _generatedAt,
      );

      expect(
        batches,
        hasLength(3),
        reason: 'S-3843 250 exercises are three batches of at most 100',
      );

      final versions = <String>{};
      for (var index = 0; index < batches.length; index++) {
        final batch = batches[index];
        expect(
          _rejections(batch),
          isEmpty,
          reason: 'S-3843 batch $index is one the wrist accepts',
        );

        final payload = _asObject(batch['payload']);
        expect(payload['batchIndex'], index);
        expect(payload['batchCount'], 3);
        expect(payload['totalCount'], 250);
        versions.add(payload['catalogVersion']! as String);

        final bytes = utf8.encode(jsonEncode(batch)).length;
        // ignore: avoid_print
        print('S-3843 batch $index: $bytes bytes');
        expect(
          bytes,
          lessThan(16000),
          reason: 'S-3843 a batch stays well under the frame budget',
        );
      }

      expect(
        versions,
        hasLength(1),
        reason: 'S-3843 the batches are one list, so they share one version',
      );

      expect(
        [
          for (final batch in batches)
            _objects(_asObject(batch['payload'])['exercises']).length,
        ],
        [100, 100, 50],
        reason: 'S-3843 the last batch carries the remainder',
      );

      final names = [
        for (final batch in batches)
          for (final exercise
              in _objects(_asObject(batch['payload'])['exercises']))
            exercise['name']! as String,
      ];
      final expectedNames = [
        for (final row in [...rows]..sort((left, right) {
          final byName = compareFoodNames(left.$2, right.$2);
          return byName != 0 ? byName : left.$1.compareTo(right.$1);
        }))
          row.$2,
      ];
      expect(
        names,
        orderedEquals(expectedNames),
        reason: 'S-3843 the batches continue the phone\'s name order across '
            'the batch boundaries',
      );
      expect(
        names.first,
        'Exercise 000',
        reason: 'S-3843 the rows were inserted in reverse name order, so the '
            'order is the phone\'s name order, not the insertion order',
      );
    });

    test('S-3845 no capable exercise is no batch at all', () async {
      await holdOnly([
        ('exercise-custom', 'Custom Move', const []),
        ('exercise-other', 'Other Move', const []),
      ]);

      final batches = await WatchReferenceSync.buildExercisesDown(
        repository: repository,
        generatedAt: _generatedAt,
      );

      expect(
        batches,
        isEmpty,
        reason: 'S-3845 a phone with nothing the wrist could log sends no '
            'batch, not an empty one (D-3831)',
      );
    });

    test('S-3846 a batch size outside 1..100 is refused', () async {
      await holdOnly([('exercise-a', 'Alpha', const ['reps'])]);

      Future<List<Map<String, Object?>>> send(int batchSize) =>
          WatchReferenceSync.buildExercisesDown(
            repository: repository,
            generatedAt: _generatedAt,
            batchSize: batchSize,
          );

      await expectLater(
        send(0),
        throwsArgumentError,
        reason: 'S-3846 a batch of nothing is not a batch',
      );
      await expectLater(
        send(101),
        throwsArgumentError,
        reason: 'S-3846 101 exercises is more than a batch may carry',
      );
    });

    test('S-3858 the first batch of the seeded catalog stays under the frame '
        'budget', () async {
      final batches = await WatchReferenceSync.buildExercisesDown(
        repository: repository,
        generatedAt: _generatedAt,
      );

      expect(
        batches,
        hasLength(4),
        reason: 'S-3858 the seeded catalog is more than three batches',
      );
      for (var index = 0; index < batches.length; index++) {
        final bytes = utf8.encode(jsonEncode(batches[index])).length;
        // ignore: avoid_print
        print('S-3858 batch $index: $bytes bytes');
        expect(
          bytes,
          lessThan(16000),
          reason: 'S-3858 batch $index of the real catalog fits the frame '
              'budget',
        );
      }
    });

    // Plan 2026-11-05-119 (S-19306): the 22 yoga poses and the two rows the
    // catalog moves to Yoga (Pigeon Pose, Child's Pose) ride the same batches
    // the wrist already knows — once each, as holds, with no Health kind of
    // their own, because a hold on the wrist stays a Flexibility workout.
    test('S-19306 every yoga pose reaches the wrist once, as a hold', () async {
      final batches = await WatchReferenceSync.buildExercisesDown(
        repository: repository,
        generatedAt: _generatedAt,
      );

      expect(
        batches,
        hasLength(4),
        reason: 'S-19306 the seeded catalog of more than 300 holds is four '
            'batches of at most 100',
      );

      final yogaIds = {
        for (final row in yogaCatalogRows) 'exercise-${row.suffix}',
        'exercise-pigeon-pose',
        'exercise-childs-pose',
      };
      final seen = <String, int>{};

      for (var index = 0; index < batches.length; index++) {
        final batch = batches[index];
        expect(
          _rejections(batch),
          isEmpty,
          reason: 'S-19306 batch $index is one the wrist accepts',
        );

        for (final exercise
            in _objects(_asObject(batch['payload'])['exercises'])) {
          final id = exercise['exerciseId']! as String;
          if (!yogaIds.contains(id)) continue;

          seen[id] = (seen[id] ?? 0) + 1;
          expect(
            exercise['capabilities'],
            ['hold', 'time', 'sets'],
            reason: 'S-19306 $id arrives as a hold',
          );
          expect(
            exercise.containsKey('healthActivity'),
            isFalse,
            reason: 'S-19306 $id carries no Health kind of its own',
          );
        }

        final bytes = utf8.encode(jsonEncode(batch)).length;
        // ignore: avoid_print
        print('S-19306 batch $index: $bytes bytes');
        expect(
          bytes,
          lessThan(16000),
          reason: 'S-19306 batch $index stays under the frame budget',
        );
      }

      expect(
        seen.keys.toSet(),
        yogaIds,
        reason: 'S-19306 every yoga row and the two moved rows arrive',
      );
      expect(
        seen,
        {for (final id in yogaIds) id: 1},
        reason: 'S-19306 each yoga id appears exactly once across the batches',
      );

      expect(
        WatchReferenceSync.healthActivityOf(
          disciplineId: 'discipline-yoga',
          exerciseId: 'exercise-tree-pose',
          capabilities: ['hold', 'time', 'sets'],
        ),
        isNull,
        reason: 'S-19306 the wrist records a hold as it always has',
      );
    });
  });

  // Plan 2026-10-11-23e2, Phase P1 (D-3832): the phone names the version of the
  // list it built, so the wrist can say "I already hold that one".
  group('S-3844 the exercise list version', () {
    /// The two exercises of the D-3832 vector, exactly as the wire carries them.
    final vector = <Map<String, Object?>>[
      {'exerciseId': 'a', 'name': 'Apple', 'capabilities': ['sets', 'reps']},
      {
        'exerciseId': 'b',
        'name': 'Bike',
        'capabilities': ['time', 'distance'],
        'roundDurationSecs': 600,
      },
    ];

    /// The vector's two exercises as repository rows. [reversed] inserts them in
    /// the other order, which the version must not notice.
    Future<void> holdVector({bool reversed = false}) async {
      final rows = [
        ('a', 'Apple', ['sets', 'reps'], null),
        ('b', 'Bike', ['time', 'distance'], 600),
      ];
      repository.clear();
      for (final (id, name, capabilities, roundDurationSecs)
          in reversed ? rows.reversed : rows) {
        await repository.createExercise(
          Exercise(
            id: id,
            name: name,
            defaultRoundDurationSecs: roundDurationSecs,
            createdAtMs: _now.millisecondsSinceEpoch,
            updatedAtMs: _now.millisecondsSinceEpoch,
          ),
        );
        await repository.setExerciseCapabilities(id, capabilities);
      }
    }

    test('S-3844 the vector, over the wire objects themselves', () {
      expect(
        WatchReferenceSync.exercisesVersionOf(vector),
        'v1-2-004dbda823a1b308',
        reason: 'S-3844 the version of the D-3832 vector',
      );
      expect(
        WatchReferenceSync.exercisesVersionOf([
          vector[0],
          {...vector[1], 'name': 'Bike!'},
        ]),
        'v1-2-6a71268979e6d5bd',
        reason: 'S-3844 the same vector with Bike! as the second name',
      );
    });

    test('S-3844 the vector through the batches it builds', () async {
      await holdVector();

      final batches = await WatchReferenceSync.buildExercisesDown(
        repository: repository,
        generatedAt: _generatedAt,
      );

      expect(batches, hasLength(1));
      expect(
        _asObject(batches.single['payload'])['catalogVersion'],
        'v1-2-004dbda823a1b308',
        reason: 'S-3844 the sender derives the same version the function does, '
            'from the rows it read',
      );
    });

    test('S-3844 the same content in another insertion order is one version',
        () async {
      await holdVector();
      final first = await WatchReferenceSync.buildExercisesDown(
        repository: repository,
        generatedAt: _generatedAt,
      );

      await holdVector(reversed: true);
      final second = await WatchReferenceSync.buildExercisesDown(
        repository: repository,
        generatedAt: _generatedAt,
      );

      expect(
        _asObject(second.single['payload'])['catalogVersion'],
        _asObject(first.single['payload'])['catalogVersion'],
        reason: 'S-3844 the version is content only, and the sender sorts, so '
            'the order the rows were inserted in never reaches it (D-3832)',
      );
    });

    test('S-3844 a name, a capability, a period length or a removal is another '
        'version', () {
      final base = WatchReferenceSync.exercisesVersionOf(vector);

      expect(
        WatchReferenceSync.exercisesVersionOf([
          {...vector[0], 'name': 'Apple!'},
          vector[1],
        ]),
        isNot(base),
        reason: 'S-3844 a rename is another version',
      );
      expect(
        WatchReferenceSync.exercisesVersionOf([
          {...vector[0], 'capabilities': ['sets', 'reps', 'load']},
          vector[1],
        ]),
        isNot(base),
        reason: 'S-3844 a changed capability is another version',
      );
      expect(
        WatchReferenceSync.exercisesVersionOf([
          vector[0],
          {...vector[1], 'roundDurationSecs': 601},
        ]),
        isNot(base),
        reason: 'S-3844 a changed period length is another version',
      );
      expect(
        WatchReferenceSync.exercisesVersionOf([vector[0]]),
        isNot(base),
        reason: 'S-3844 one exercise fewer is another version',
      );
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

      return WatchReferenceSync.buildRoutinesDown(
        repository: repository,
        generatedAt: _generatedAt,
      );
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
        ))['payload'],
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

      final message = await WatchReferenceSync.buildRoutinesDown(
        repository: repository,
        generatedAt: _generatedAt,
      );

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

      final message = await WatchReferenceSync.buildRoutinesDown(
        repository: repository,
        generatedAt: _generatedAt,
      );

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

      final message = await WatchReferenceSync.buildRoutinesDown(
        repository: repository,
        generatedAt: _generatedAt,
      );

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

      final message = await WatchReferenceSync.buildRoutinesDown(
        repository: repository,
        generatedAt: _generatedAt,
      );

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

        final message = await WatchReferenceSync.buildRoutinesDown(
          repository: repository,
          generatedAt: _generatedAt,
        );

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

  // Plan 129 (P1b, D-8961/D-8962): the phone's plans travel as their own
  // `planned_down` frame — not a field on `routines_down` (D-8960) — carrying
  // the name the calendar row shows and nothing a started plan would still
  // claim. The graphs that send it and link it back are in
  // `test/watch_session_import_test.dart`.
  //
  // Every date here derives at run time from 2026-11-05 local; nothing pins an
  // epoch to the machine's timezone.
  group('S-8960…S-8962 the plans the wrist can start', () {
    final today = DateTime(2026, 11, 5);
    final todayMs = today.millisecondsSinceEpoch;
    final generatedAt = DateTime(2026, 11, 5, 12);

    Future<void> addPlan(
      String id,
      int scheduledDateMs, {
      String? title,
      String? modality,
      String? routineTemplateId,
      bool completed = false,
      String? linkedSessionId,
    }) => repository.createPlannedSession(
      PlannedSession(
        id: id,
        ownerUserId: LoggedEntryRows.ownerUserId,
        scheduledDateMs: scheduledDateMs,
        modality: modality,
        title: title,
        note: null,
        isCompleted: completed,
        linkedSessionId: linkedSessionId,
        routineTemplateId: routineTemplateId,
        createdAtMs: _now.millisecondsSinceEpoch,
        updatedAtMs: _now.millisecondsSinceEpoch,
      ),
    );

    setUp(() async {
      await _addTemplate(
        repository,
        id: 'tpl-push',
        name: 'Push',
        segmentIds: ['seg-push'],
      );
      await _addTemplate(
        repository,
        id: 'tpl-legs',
        name: 'Legs',
        segmentIds: ['seg-legs'],
      );
    });

    test('S-8960 the window and the sort: three startable plans, in date order',
        () async {
      await addPlan('p-today', todayMs, routineTemplateId: 'tpl-push');
      await addPlan(
        'p-tomorrow',
        DateTime(2026, 11, 6).millisecondsSinceEpoch,
        routineTemplateId: 'tpl-legs',
      );
      await addPlan(
        'p-late',
        DateTime(2026, 11, 18).millisecondsSinceEpoch,
        routineTemplateId: 'tpl-legs',
      );
      // Not startable, or outside the window:
      await addPlan(
        'p-linked',
        todayMs,
        routineTemplateId: 'tpl-push',
        linkedSessionId: 's-x',
      );
      await addPlan('p-done', todayMs, routineTemplateId: 'tpl-push',
          completed: true);
      await addPlan('p-old', DateTime(2026, 10, 31).millisecondsSinceEpoch,
          routineTemplateId: 'tpl-push');
      // Inside the window (yesterday, today + 13) but completed every way a
      // started plan can be, whatever its date:
      await addPlan(
        'p-linked-late',
        DateTime(2026, 11, 13).millisecondsSinceEpoch,
        linkedSessionId: 's-x',
      );
      await addPlan(
        'p-done-old',
        DateTime(2026, 11, 3).millisecondsSinceEpoch,
        completed: true,
      );

      final message = await WatchReferenceSync.buildPlannedDown(
        repository: repository,
        generatedAt: generatedAt,
      );

      expect(message['type'], 'planned_down');
      expect(message['origin'], 'phone');
      expect(
        message['messageId'],
        'msg-planned-${generatedAt.toUtc().millisecondsSinceEpoch}',
      );
      expect(message.containsKey('sessionId'), isFalse);
      expect(
        _asObject(message['payload']),
        {
          'generatedAt': utcIso(generatedAt),
          'plans': [
            {
              'plannedSessionId': 'p-today',
              'name': 'Push',
              'scheduledDateMs': todayMs,
              'routineTemplateId': 'tpl-push',
              'createdAtMs': _now.millisecondsSinceEpoch,
              'updatedAtMs': _now.millisecondsSinceEpoch,
            },
            {
              'plannedSessionId': 'p-tomorrow',
              'name': 'Legs',
              'scheduledDateMs': DateTime(2026, 11, 6).millisecondsSinceEpoch,
              'routineTemplateId': 'tpl-legs',
              'createdAtMs': _now.millisecondsSinceEpoch,
              'updatedAtMs': _now.millisecondsSinceEpoch,
            },
            {
              'plannedSessionId': 'p-late',
              'name': 'Legs',
              'scheduledDateMs': DateTime(2026, 11, 18).millisecondsSinceEpoch,
              'routineTemplateId': 'tpl-legs',
              'createdAtMs': _now.millisecondsSinceEpoch,
              'updatedAtMs': _now.millisecondsSinceEpoch,
            },
          ],
        },
        reason:
            'S-8960 only the unstarted plans of today − 1 day … today + 13 '
            'inclusive travel, started ones never; the payload is the stamp '
            'and the plans alone, every date read at run time',
      );
    });

    test('S-8960 the window edges: yesterday and today + 13 in, the rest out',
        () async {
      await addPlan('p-out-before', DateTime(2026, 11, 3).millisecondsSinceEpoch,
          modality: Modality.sports);
      await addPlan(
        'p-edge-before',
        DateTime(2026, 11, 4).millisecondsSinceEpoch,
        modality: Modality.sports,
      );
      await addPlan(
        'p-latest-ok',
        DateTime(2026, 11, 18).millisecondsSinceEpoch,
        modality: Modality.sports,
      );
      await addPlan('p-out-after', DateTime(2026, 11, 19).millisecondsSinceEpoch,
          modality: Modality.sports);

      final message = await WatchReferenceSync.buildPlannedDown(
        repository: repository,
        generatedAt: generatedAt,
      );

      expect(
        [
          for (final p in _objects(_asObject(message['payload'])['plans']))
            p['plannedSessionId'],
        ],
        ['p-edge-before', 'p-latest-ok'],
        reason: 'S-8960 the half-open window is today − 1 day … today + 14',
      );
    });

    test('S-8961 the name cascade in every case the calendar row can be',
        () async {
      await addPlan('p-titled', todayMs, title: 'Hill sprints');
      await addPlan('p-routine', todayMs, routineTemplateId: 'tpl-push');
      await addPlan('p-free', todayMs, modality: Modality.sports);
      await addPlan('p-bare', todayMs);

      final message = await WatchReferenceSync.buildPlannedDown(
        repository: repository,
        generatedAt: generatedAt,
      );

      expect(
        {
          for (final p
              in _objects(_asObject(message['payload'])['plans']))
            p['plannedSessionId']! as String: p['name'],
        },
        {
          'p-titled': 'Hill sprints',
          'p-routine': 'Push',
          'p-free': 'Sports',
          'p-bare': 'Free Training',
        },
        reason: 'S-8961 the plan\'s own title, the template\'s name, the '
            'phone\'s modality label, then "Free Training", ties by id',
      );
    });

    test('S-8961 a nullable field is absent, never null', () async {
      await addPlan('p-bare', todayMs);

      final message = await WatchReferenceSync.buildPlannedDown(
        repository: repository,
        generatedAt: generatedAt,
      );

      expect(
        _objects(_asObject(message['payload'])['plans']).single.keys.toList(),
        ['plannedSessionId', 'name', 'scheduledDateMs', 'createdAtMs',
         'updatedAtMs'],
        reason: 'S-8961 no nullable key is sent as null',
      );
    });

    test('S-8962 a plan on a routine the wrist is not set up for still names '
        'that routine', () async {
      await repository.createExercise(
        Exercise(
          id: 'exercise-empty',
          name: 'Its exercise holds no capability',
          createdAtMs: _now.millisecondsSinceEpoch,
          updatedAtMs: _now.millisecondsSinceEpoch,
        ),
      );
      await _addTemplate(
        repository,
        id: 'tpl-empty',
        name: 'Empty routine',
        segmentIds: ['seg-empty'],
      );
      await _addEffort(
        repository,
        id: 'eff-empty',
        segmentId: 'seg-empty',
        orderIndex: 0,
        effortKind: 'set',
        exerciseId: 'exercise-empty',
      );
      expect(
        _objects(
          _asObject(
            (await WatchReferenceSync.buildRoutinesDown(
              repository: repository,
              generatedAt: generatedAt,
            ))['payload'],
          )['routines'],
        ),
        isEmpty,
        reason: 'S-8962 guard: the routine really is omitted from '
            '`routines_down`',
      );
      await addPlan('p-empty', todayMs, routineTemplateId: 'tpl-empty');

      final message = await WatchReferenceSync.buildPlannedDown(
        repository: repository,
        generatedAt: generatedAt,
      );

      final plan = _objects(_asObject(message['payload'])['plans']).single;
      expect(plan['plannedSessionId'], 'p-empty');
      expect(
        plan['routineTemplateId'],
        'tpl-empty',
        reason: 'S-8962 the plan row carries the routine id; the wrist does '
            'not need the routine to exist to know the run is one',
      );
      expect(plan['name'], 'Empty routine');
    });

    test('S-8960 a phone with no plans sends the empty frame', () async {
      final message = await WatchReferenceSync.buildPlannedDown(
        repository: repository,
        generatedAt: generatedAt,
      );

      expect(
        _asObject(message['payload']),
        {'generatedAt': utcIso(generatedAt), 'plans': <Object?>[]},
        reason: 'S-8960 the frame says the list is empty instead of saying '
            'nothing',
      );
    });
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
