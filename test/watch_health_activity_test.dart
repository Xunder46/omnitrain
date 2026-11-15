// Plan 75, Phase 2 (phone): the Health workout kind an exercise records as on
// the wrist, derived from its discipline (D-3); widened to every discipline by
// plan 170 (D-17001/D-17002).
//
// Scenario mapping:
//   S-10511 `healthActivityOf`, one test per arm → `S-10511 ...`
//   S-17001 the discipline table covers every seeded discipline → `S-17001 ...`
//   S-17002 the kind does not depend on capabilities → `S-17002 ...`
//   S-10512 the catalog builder carries the kind → `S-10512 ...`
//   S-10513 the session slot carries it and the envelope validates → `S-10513 ...`
//   S-10514 the `routines_down` fallback list and efforts carry it → `S-10514 ...`

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/capability.dart';
import 'package:omnitrain/core/utils/watch_reference_sync.dart';
import 'package:omnitrain/core/platform/watch_delivery.dart';
import 'package:omnitrain/core/platform/watch_transport.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/mock/seed_data.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/watch/watch_sync_wiring.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/sync_protocol_harness.dart';
import 'helpers/fake_preferences_service.dart';

final DateTime _now = DateTime.utc(2026, 10, 24, 9);
final DateTime _generatedAt = DateTime.utc(2026, 10, 24, 9, 30);

Map<String, Object?> _asObject(Object? value) =>
    (value as Map).cast<String, Object?>();

List<Map<String, Object?>> _objects(Object? value) =>
    (value! as List).map(_asObject).toList(growable: false);

void main() {
  group('S-10511 healthActivityOf, one arm at a time', () {
    Object? of(String? disciplineId, String exerciseId) =>
        WatchReferenceSync.healthActivityOf(
          disciplineId: disciplineId,
          exerciseId: exerciseId,
        );

    test('S-10511 the running discipline records as running', () {
      expect(of('discipline-running', 'exercise-easy-run'), 'running');
    });

    test('S-10511 the cycling discipline records as cycling', () {
      expect(of('discipline-cycling', 'exercise-zone-2-ride'), 'cycling');
    });

    test('S-10511 the rowing discipline records as rowing', () {
      expect(of('discipline-rowing', 'exercise-row-500m'), 'rowing');
    });

    test('S-10511 a walking exercise records as walking', () {
      expect(
        of('discipline-walking', 'exercise-brisk-walk'),
        'walking',
      );
    });

    test('S-10511 the built-in Hike records as hiking', () {
      expect(of('discipline-walking', 'exercise-hike'), 'hiking');
    });

    test('S-10511 Rucking records as hiking', () {
      expect(of('discipline-walking', 'exercise-rucking'), 'hiking');
    });

    test('S-10511 a custom walking exercise records as walking', () {
      expect(of('discipline-walking', 'custom-trek'), 'walking');
    });

    test('S-10511 the swimming discipline records as swimming', () {
      expect(of('discipline-swimming', 'exercise-pool-swim'), 'swimming');
    });

    test('S-10511 machine cardio records as mixed cardio', () {
      expect(
        of('discipline-machine-cardio', 'exercise-elliptical'),
        'mixedCardio',
      );
    });

    test('S-10511 no discipline records as nothing', () {
      expect(of(null, 'custom-trek'), isNull);
    });

    test('S-10511 cycling without distance still records as cycling', () {
      expect(
        of('discipline-cycling', 'exercise-zone-2-ride'),
        'cycling',
        reason: 'a capability shed after the fact never takes the kind away',
      );
    });
  });

  group('S-17001 the discipline table covers every seeded discipline', () {
    test('S-17001 every seeded discipline names a kind, and only padel does '
        'not', () {
      final seeded = {
        for (final discipline in SeedData.sampleDisciplines) discipline.id,
      };
      expect(
        seeded,
        hasLength(37),
        reason: 'the seeded catalog is the table\'s key set',
      );
      expect(
        seeded.difference(
          WatchReferenceSync.healthActivityByDiscipline.keys.toSet(),
        ),
        {'discipline-padel'},
        reason: 'S-17001 a discipline added to the seed must decide its kind; '
            'HealthKit has no padel type, so padel stays unmapped',
      );
      for (final id in seeded.difference({'discipline-padel'})) {
        expect(
          WatchReferenceSync.healthActivityOf(
            disciplineId: id,
            exerciseId: 'custom-anything',
          ),
          isNotNull,
          reason: 'S-17001 $id names its own Health kind',
        );
      }
    });

    test('S-17001 the mapped kinds are the disciplines\' own', () {
      for (final (id, kind) in [
        ('discipline-swimming', 'swimming'),
        ('discipline-machine-cardio', 'mixedCardio'),
        ('discipline-conditioning', 'conditioning'),
        ('discipline-isometric-holds', 'isometricHolds'),
        ('discipline-calisthenics', 'calisthenics'),
        ('discipline-powerlifting', 'traditionalStrengthTraining'),
        ('discipline-muay-thai', 'kickboxing'),
        ('discipline-bjj', 'martialArts'),
        ('discipline-yoga', 'yoga'),
        ('discipline-soccer', 'soccer'),
        ('discipline-climbing', 'climbing'),
      ]) {
        expect(
          WatchReferenceSync.healthActivityOf(
            disciplineId: id,
            exerciseId: 'custom-anything',
          ),
          kind,
          reason: 'S-17001 $id',
        );
      }
    });

    test('S-17001 an unmapped, unknown or absent discipline names nothing', () {
      expect(
        WatchReferenceSync.healthActivityOf(
          disciplineId: 'discipline-padel',
          exerciseId: 'custom-padel',
        ),
        isNull,
        reason: 'S-17001 the sports modality keeps its Other',
      );
      expect(
        WatchReferenceSync.healthActivityOf(
          disciplineId: 'discipline-retired',
          exerciseId: 'custom-anything',
        ),
        isNull,
      );
      expect(
        WatchReferenceSync.healthActivityOf(
          disciplineId: null,
          exerciseId: 'custom-anything',
        ),
        isNull,
      );
    });
  });

  group('S-17002 the kind does not depend on capabilities', () {
    test('S-17002 a hold, a timed and a conditioning exercise each name '
        'their kind', () {
      for (final (disciplineId, capabilities, kind) in [
        (
          'discipline-yoga',
          [ExerciseCapability.hold, ExerciseCapability.time],
          'yoga',
        ),
        (
          'discipline-active-recovery',
          [ExerciseCapability.time],
          'preparationAndRecovery',
        ),
        (
          'discipline-conditioning',
          [ExerciseCapability.time, ExerciseCapability.reps],
          'conditioning',
        ),
        (
          'discipline-stretching',
          [ExerciseCapability.hold, ExerciseCapability.time],
          'flexibility',
        ),
      ]) {
        expect(
          capabilities.contains(ExerciseCapability.distance),
          isFalse,
          reason: 'S-17002 the fixture is a non-distance exercise',
        );
        expect(
          WatchReferenceSync.healthActivityOf(
            disciplineId: disciplineId,
            exerciseId: 'custom-anything',
          ),
          kind,
          reason: 'S-17002 $disciplineId names its kind with no distance',
        );
      }
    });

    test('S-17002 the wire carries a yoga kind with no distance', () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();
      repository.clear();
      const at = 1788000000000;
      await repository.createExercise(
        Exercise(
          id: 'custom-yoga',
          name: 'Custom Yoga',
          disciplineId: 'discipline-yoga',
          createdAtMs: at,
          updatedAtMs: at,
        ),
      );
      await repository.setExerciseCapabilities('custom-yoga', [
        ExerciseCapability.hold,
        ExerciseCapability.time,
        ExerciseCapability.sets,
      ]);

      final batches = await WatchReferenceSync.buildExercisesDown(
        repository: repository,
        generatedAt: _generatedAt,
      );

      final exercises = _objects(
        _asObject(batches.single['payload'])['exercises'],
      );
      expect(
        exercises.single['healthActivity'],
        'yoga',
        reason: 'S-17002 the kind travels even though the exercise cannot '
            'cover distance',
      );
      expect(loadProtocolValidator().validateEnvelope(batches.single), isEmpty);
    });
  });

  group('S-10512 the catalog builder', () {
    late MockWorkoutRepository repository;

    setUp(() async {
      repository = MockWorkoutRepository();
      await repository.initialize();
    });

    Future<void> seedRideAndLift() async {
      repository.clear();
      const at = 1788000000000;
      await repository.createExercise(
        Exercise(
          id: 'exercise-zone-2-ride',
          name: 'Zone 2 Ride',
          disciplineId: 'discipline-cycling',
          createdAtMs: at,
          updatedAtMs: at,
        ),
      );
      await repository.setExerciseCapabilities('exercise-zone-2-ride', [
        ExerciseCapability.time,
        ExerciseCapability.distance,
      ]);
      await repository.createExercise(
        Exercise(
          id: 'exercise-goblet-squat',
          name: 'Goblet Squat',
          createdAtMs: at,
          updatedAtMs: at,
        ),
      );
      await repository.setExerciseCapabilities('exercise-goblet-squat', [
        ExerciseCapability.sets,
        ExerciseCapability.reps,
      ]);
    }

    test('S-10512 the ride carries its kind, the lift does not', () async {
      await seedRideAndLift();

      final batches = await WatchReferenceSync.buildExercisesDown(
        repository: repository,
        generatedAt: _generatedAt,
      );

      expect(batches, hasLength(1));
      final exercises = _objects(
        _asObject(batches.single['payload'])['exercises'],
      );
      final ride = exercises.singleWhere(
        (exercise) => exercise['exerciseId'] == 'exercise-zone-2-ride',
      );
      final lift = exercises.singleWhere(
        (exercise) => exercise['exerciseId'] == 'exercise-goblet-squat',
      );
      expect(
        ride,
        {
          'exerciseId': 'exercise-zone-2-ride',
          'name': 'Zone 2 Ride',
          'capabilities': ['time', 'distance'],
          'healthActivity': 'cycling',
        },
        reason: 'S-10512 the ride is a distance exercise of the cycling '
            'discipline, so the wire names its Health kind',
      );
      expect(
        lift.containsKey('healthActivity'),
        isFalse,
        reason: 'S-10512 a lifting exercise records as the wrist always has',
      );
    });

    test('S-10512 the envelope the ride rides in validates', () async {
      await seedRideAndLift();

      final batches = await WatchReferenceSync.buildExercisesDown(
        repository: repository,
        generatedAt: _generatedAt,
      );

      expect(loadProtocolValidator().validateEnvelope(batches.single), isEmpty);
    });
  });

  group('S-10514 the routines_down fallback list and efforts', () {
    late MockWorkoutRepository repository;

    setUp(() async {
      repository = MockWorkoutRepository();
      await repository.initialize();
    });

    Future<void> seedRoutine() async {
      repository.clear();
      const at = 1788000000000;
      Future<void> exercise(
        String id,
        String name,
        String? disciplineId,
        List<String> capabilities,
      ) async {
        await repository.createExercise(
          Exercise(
            id: id,
            name: name,
            disciplineId: disciplineId,
            createdAtMs: at,
            updatedAtMs: at,
          ),
        );
        await repository.setExerciseCapabilities(id, capabilities);
      }

      await exercise('exercise-zone-2-ride', 'Zone 2 Ride',
          'discipline-cycling', [ExerciseCapability.time, ExerciseCapability.distance]);
      await exercise('exercise-goblet-squat', 'Goblet Squat', null, [
        ExerciseCapability.sets,
        ExerciseCapability.reps,
      ]);

      await repository.createTemplate(
        WorkoutTemplate(
          id: 'routine-mixed',
          ownerUserId: null,
          name: 'Ride then Lift',
          description: null,
          focusModality: null,
          primaryDisciplineId: null,
          note: null,
          isBuiltInDemo: false,
          createdAtMs: at,
          updatedAtMs: at,
        ),
      );
      await repository.createTemplateSegment(
        TemplateSegment(
          id: 'seg-mixed',
          templateId: 'routine-mixed',
          orderIndex: 0,
          segmentType: 'strength_sets',
          disciplineId: null,
          name: 'Segment 1',
          note: null,
          createdAtMs: at,
          updatedAtMs: at,
        ),
      );
      for (final (index, entry) in [
        ('eff-ride', 'exercise-zone-2-ride', 'interval'),
        ('eff-lift', 'exercise-goblet-squat', 'set'),
      ].indexed) {
        await repository.createTemplateEffort(
          TemplateEffort(
            id: entry.$1,
            templateSegmentId: 'seg-mixed',
            orderIndex: index,
            effortKind: entry.$3,
            modality: null,
            exerciseId: entry.$2,
            note: null,
            restSeconds: null,
            restType: null,
            createdAtMs: at,
          ),
        );
      }
    }

    test('S-10514 the fallback exercise and the effort carry the kind',
        () async {
      await seedRoutine();

      final message = await WatchReferenceSync.buildRoutinesDown(
        repository: repository,
        generatedAt: _generatedAt,
      );

      final payload = _asObject(message['payload']);
      final fallback = _objects(payload['fallbackExercises']);
      final ride = fallback.singleWhere(
        (exercise) => exercise['exerciseId'] == 'exercise-zone-2-ride',
      );
      final lift = fallback.singleWhere(
        (exercise) => exercise['exerciseId'] == 'exercise-goblet-squat',
      );
      expect(ride['healthActivity'], 'cycling');
      expect(lift.containsKey('healthActivity'), isFalse);

      final segments = _objects(
        _objects(payload['routines']).single['segments'],
      );
      final efforts = _objects(segments.single['efforts']);
      final rideEffort = efforts.singleWhere(
        (effort) => effort['exerciseId'] == 'exercise-zone-2-ride',
      );
      final liftEffort = efforts.singleWhere(
        (effort) => effort['exerciseId'] == 'exercise-goblet-squat',
      );
      expect(rideEffort['healthActivity'], 'cycling');
      expect(liftEffort.containsKey('healthActivity'), isFalse);
    });

    test('S-10514 the routine message validates', () async {
      await seedRoutine();

      final message = await WatchReferenceSync.buildRoutinesDown(
        repository: repository,
        generatedAt: _generatedAt,
      );

      expect(loadProtocolValidator().validateEnvelope(message), isEmpty);
    });
  });

  group('S-10513 the session slot', () {
    late MockWorkoutRepository repository;
    late WorkoutState phoneState;
    late _PhoneRadio radio;

    setUp(() async {
      repository = MockWorkoutRepository();
      await repository.initialize();
      repository.clear();

      const at = 1788000000000;
      await repository.createExercise(
        Exercise(
          id: 'ex-ride',
          name: 'Zone 2 Ride',
          disciplineId: 'discipline-cycling',
          createdAtMs: at,
          updatedAtMs: at,
        ),
      );
      await repository.setExerciseCapabilities('ex-ride', [
        ExerciseCapability.time,
        ExerciseCapability.distance,
      ]);
      await repository.createExercise(
        Exercise(
          id: 'ex-bench',
          name: 'Bench Press',
          createdAtMs: at,
          updatedAtMs: at,
        ),
      );
      await repository.setExerciseCapabilities('ex-bench', [
        ExerciseCapability.sets,
        ExerciseCapability.reps,
        ExerciseCapability.load,
      ]);
      await repository.createExercise(
        Exercise(
          id: 'ex-yoga',
          name: 'Tree Pose',
          disciplineId: 'discipline-yoga',
          createdAtMs: at,
          updatedAtMs: at,
        ),
      );
      await repository.setExerciseCapabilities('ex-yoga', [
        ExerciseCapability.hold,
        ExerciseCapability.time,
        ExerciseCapability.sets,
      ]);

      phoneState = WorkoutState(repository);
      final settings = SettingsState(repository, fakePreferencesService());
      await settings.initialize();
      radio = _PhoneRadio();
      final created = (await createWatchSync(
        repository: repository,
        nutritionState: NutritionState(repository),
        foodLibraryState: FoodLibraryState(repository),
        settingsState: settings,
        transport: radio,
        clock: () => _now,
      ))!;
      created.adoption.bindWorkoutState(phoneState);
    });

    test('S-10513 the ride slot carries the kind, the lift slot does not',
        () async {
      await phoneState.createNewSession(modality: null);
      await phoneState.addExerciseToSession(
        (await repository.getExerciseById('ex-ride'))!,
      );
      await phoneState.addExerciseToSession(
        (await repository.getExerciseById('ex-bench'))!,
      );

      await radio.fromWrist(WatchTransportRequest.snapshotFrame());
      await pumpEventQueue();

      final answer = radio.lastOfType('session_snapshot');
      final payload = _asObject(answer['payload']);
      final slots = _objects(payload['exercises']);
      final ride = slots.singleWhere(
        (slot) => slot['exerciseId'] == 'ex-ride',
      );
      final lift = slots.singleWhere(
        (slot) => slot['exerciseId'] == 'ex-bench',
      );
      expect(ride['healthActivity'], 'cycling');
      expect(lift.containsKey('healthActivity'), isFalse);

      expect(
        loadProtocolValidator().validateEnvelope(answer),
        isEmpty,
        reason: 'S-10513 the slot the wrist would read is one the schema '
            'accepts',
      );
    });

    test('S-10513 a hold-only yoga slot carries its own kind', () async {
      await phoneState.createNewSession(modality: null);
      await phoneState.addExerciseToSession(
        (await repository.getExerciseById('ex-yoga'))!,
      );

      await radio.fromWrist(WatchTransportRequest.snapshotFrame());
      await pumpEventQueue();

      final answer = radio.lastOfType('session_snapshot');
      final slots = _objects(_asObject(answer['payload'])['exercises']);
      expect(
        slots.single['healthActivity'],
        'yoga',
        reason: 'S-10513 the slot names yoga without covering distance',
      );
      expect(loadProtocolValidator().validateEnvelope(answer), isEmpty);
    });
  });
}

/// A transport that records what the phone sent and carries nothing.
class _PhoneRadio implements WatchTransport {
  final List<Map<String, Object?>> sent = [];

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
    sent.add(envelope);
    return WatchDelivery.delivered;
  }

  Future<void> fromWrist(Map<String, Object?> frame) async {
    final handler = _handler;
    if (handler == null) {
      throw StateError('the phone graph never bound its inbound handler');
    }
    await handler(frame);
  }

  Map<String, Object?> lastOfType(String type) => sent.lastWhere(
    (envelope) => envelope['type'] == type,
  );
}
