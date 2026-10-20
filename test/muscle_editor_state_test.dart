// Plan 34, Phase A — the state API that carries roles.
//
// Scenario S-2 of
// `docs/plans/2026-10-14-34-muscle-editor-plan/2026-10-14-34-muscle-editor-plan.md`.
//
// `createCustomExercise`, `updateCustomExercise`, `ExerciseLibraryState.editCustom`
// and `ExerciseLibraryService.editCustom` take `List<ExerciseMuscleLink>` and
// persist it through `setExerciseMuscleLinks`; a secondary-only list is refused
// by the repository and surfaces as a null result with a state error.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/exercise_library_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/exercise/exercise_library_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

ExerciseMuscleLink _link(String id, [MuscleRole role = MuscleRole.primary]) =>
    ExerciseMuscleLink(muscleGroupId: id, role: role);

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

Exercise _customExercise(String id, String name) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return Exercise(
    id: id,
    ownerUserId: 'user-1',
    name: name,
    createdAtMs: now,
    updatedAtMs: now,
  );
}

/// A repository whose links read fails, so a caller can tell "no muscles" from
/// "could not read the muscles".
class _ThrowingLinksRepo extends MockWorkoutRepository {
  @override
  Future<List<ExerciseMuscleLink>> getExerciseMuscleLinks(
    String exerciseId,
  ) async {
    throw StateError('links read failed');
  }
}

void main() {
  group('S-2 state API', () {
    late MockWorkoutRepository repo;
    late WorkoutState workoutState;

    setUp(() async {
      repo = await _freshRepo();
      workoutState = WorkoutState(repo);
    });

    test('createCustomExercise stores the links normalised', () async {
      final created = await workoutState.createCustomExercise(
        name: 'X',
        modality: 'resistance_lifting',
        capabilities: const ['reps'],
        muscleLinks: [
          _link('muscle-triceps', MuscleRole.secondary),
          _link('muscle-chest'),
        ],
      );

      expect(created, isNotNull);
      expect(workoutState.error, isNull);
      expect(await repo.getExerciseMuscleLinks(created!.id), [
        _link('muscle-chest'),
        _link('muscle-triceps', MuscleRole.secondary),
      ]);
      final stateLinks = await workoutState.getExerciseMuscleLinks(created.id);
      expect(stateLinks, [
        _link('muscle-chest'),
        _link('muscle-triceps', MuscleRole.secondary),
      ]);
    });

    test('updateCustomExercise replaces the links', () async {
      final created = await workoutState.createCustomExercise(
        name: 'X',
        capabilities: const ['reps'],
        muscleLinks: [_link('muscle-chest')],
      );
      expect(created, isNotNull);

      final updated = await workoutState.updateCustomExercise(
        exercise: created!,
        capabilities: const ['reps'],
        muscleLinks: [_link('muscle-quads')],
      );

      expect(updated, isNotNull);
      expect(await repo.getExerciseMuscleLinks(created.id), [
        _link('muscle-quads'),
      ]);
    });

    test(
      'an assists-only list returns null and sets the state error',
      () async {
        final created = await workoutState.createCustomExercise(
          name: 'X',
          capabilities: const ['reps'],
          muscleLinks: [_link('muscle-chest')],
        );
        expect(created, isNotNull);

        final updated = await workoutState.updateCustomExercise(
          exercise: created!,
          capabilities: const ['reps'],
          muscleLinks: [_link('muscle-triceps', MuscleRole.secondary)],
        );

        expect(updated, isNull);
        expect(workoutState.error, isNotNull);
      },
    );

    test(
      'creating with an assists-only list returns null and errors',
      () async {
        final created = await workoutState.createCustomExercise(
          name: 'X',
          capabilities: const ['reps'],
          muscleLinks: [_link('muscle-triceps', MuscleRole.secondary)],
        );

        expect(created, isNull);
        expect(workoutState.error, isNotNull);
      },
    );

    test('an empty list creates an exercise with no links', () async {
      final created = await workoutState.createCustomExercise(
        name: 'No muscles',
        modality: 'resistance_lifting',
        capabilities: const ['reps'],
        muscleLinks: const [],
      );

      expect(created, isNotNull);
      expect(await repo.getExerciseMuscleLinks(created!.id), isEmpty);
      final stateLinks = await workoutState.getExerciseMuscleLinks(created.id);
      expect(stateLinks, isNotNull);
      expect(stateLinks, isEmpty);
    });

    test(
      'ExerciseLibraryService.editCustom persists the links it is given',
      () async {
        final exercise = _customExercise('ex-edit', 'Old name');
        await repo.createExercise(exercise);
        final service = ExerciseLibraryService(repo);

        final updated = await service.editCustom(
          exercise: exercise,
          name: 'New name',
          capabilities: const ['reps'],
          muscleLinks: [
            _link('muscle-chest'),
            _link('muscle-lats', MuscleRole.secondary),
          ],
        );

        expect(updated.name, 'New name');
        expect(await repo.getExerciseMuscleLinks('ex-edit'), [
          _link('muscle-chest'),
          _link('muscle-lats', MuscleRole.secondary),
        ]);
      },
    );

    test('ExerciseLibraryState.editCustom passes the links through', () async {
      final exercise = _customExercise('ex-edit-state', 'Old name');
      await repo.createExercise(exercise);
      final state = ExerciseLibraryState(
        service: ExerciseLibraryService(repo),
        workoutState: workoutState,
      );

      await state.editCustom(
        exercise: exercise,
        name: 'New name',
        capabilities: const ['reps'],
        muscleLinks: [_link('muscle-glutes')],
      );

      expect(await repo.getExerciseMuscleLinks('ex-edit-state'), [
        _link('muscle-glutes'),
      ]);
      expect(state.error, isNull);
    });

    test('a failing links read returns null and sets the state error', () async {
      final failing = _ThrowingLinksRepo();
      await failing.initialize();
      final state = WorkoutState(failing);
      await failing.createExercise(_customExercise('ex-throw', 'Throw'));

      expect(await state.getExerciseMuscleLinks('ex-throw'), isNull);
      expect(state.error, isNotNull);
    });
  });
}
