// Plan 33, Phase A part 2 — the muscle filter answers by the hierarchy, on
// both implementations.
//
// Scenario S-5 of
// `docs/plans/2026-10-14-33-muscle-hierarchy-data-plan/2026-10-14-33-muscle-hierarchy-data-plan.md`.
//
// Only a primary link matches: selecting a region matches the primary links to
// the region and to its muscles, selecting a muscle matches that id only, and a
// secondary-only link to the selected muscle excludes the exercise. The ranked
// query keeps its own ordering but filters identically. Both stores must
// answer the same, so every case runs over `harnessFactories` with plain
// `test()`.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

import 'helpers/repository_harness.dart';

/// A fixed timestamp: the fixtures take no clock reading.
const int _atMs = 1700000000000;

ExerciseMuscleLink _link(String id, [MuscleRole role = MuscleRole.primary]) =>
    ExerciseMuscleLink(muscleGroupId: id, role: role);

List<String> _ids(List<Exercise> exercises) => [
  for (final exercise in exercises) exercise.id,
];

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — muscle filter', () {
      late WorkoutRepository repo;

      setUp(() async => repo = await harness.open());
      tearDown(() async => await harness.close());

      test('S-5 Legs returns the squat and Tennis Match, each once', () async {
        final ids = _ids(
          await repo.searchExercises(muscleGroupIds: ['muscle-legs']),
        );

        expect(ids.where((id) => id == 'exercise-barbell-squat'), hasLength(1));
        expect(ids.where((id) => id == 'exercise-tennis-match'), hasLength(1));
        expect(
          ids,
          isNot(contains('exercise-bench-press')),
          reason: 'the bench press carries no primary leg link',
        );
      });

      test('S-5 Quadriceps returns the squat, not Tennis Match', () async {
        final ids = _ids(
          await repo.searchExercises(muscleGroupIds: ['muscle-quads']),
        );

        expect(ids, contains('exercise-barbell-squat'));
        expect(ids, isNot(contains('exercise-tennis-match')));
      });

      test('S-5 Triceps returns the pressdown, not the bench press', () async {
        final ids = _ids(
          await repo.searchExercises(muscleGroupIds: ['muscle-triceps']),
        );

        expect(ids, contains('exercise-triceps-pressdown'));
        expect(ids, isNot(contains('exercise-bench-press')));
      });

      test('S-5 Chest returns the bench press', () async {
        final ids = _ids(
          await repo.searchExercises(muscleGroupIds: ['muscle-chest']),
        );

        expect(ids, contains('exercise-bench-press'));
        expect(
          ids,
          isNot(contains('exercise-triceps-pressdown')),
          reason: 'the pressdown is tagged triceps primary, never chest',
        );
      });

      test('S-5 Arms returns the pressdown and Volleyball Match', () async {
        final ids = _ids(
          await repo.searchExercises(muscleGroupIds: ['muscle-arms']),
        );

        expect(ids, contains('exercise-triceps-pressdown'));
        expect(ids, contains('exercise-volleyball-match'));
        expect(
          ids,
          isNot(contains('exercise-bench-press')),
          reason: 'the bench press loads the triceps only as a secondary',
        );
      });

      test('S-5 two selections of the same lift return it once', () async {
        final ids = _ids(
          await repo.searchExercises(
            muscleGroupIds: ['muscle-quads', 'muscle-legs'],
          ),
        );

        expect(ids.where((id) => id == 'exercise-barbell-squat'), hasLength(1));
      });

      test('S-5 the ranked query filters the same way', () async {
        Future<List<String>> ranked(List<String> selected) async => _ids(
          await repo.getExercisesRankedForModality(
            'resistance_lifting',
            muscleGroupIds: selected,
          ),
        );

        final legs = await ranked(['muscle-legs']);
        expect(
          legs.where((id) => id == 'exercise-barbell-squat'),
          hasLength(1),
        );
        expect(legs.where((id) => id == 'exercise-tennis-match'), hasLength(1));

        final quads = await ranked(['muscle-quads']);
        expect(quads, contains('exercise-barbell-squat'));
        expect(quads, isNot(contains('exercise-tennis-match')));

        final triceps = await ranked(['muscle-triceps']);
        expect(triceps, contains('exercise-triceps-pressdown'));
        expect(triceps, isNot(contains('exercise-bench-press')));

        final chest = await ranked(['muscle-chest']);
        expect(chest, contains('exercise-bench-press'));
      });

      test('S-5 a secondary-only link excludes the exercise', () async {
        await repo.createExercise(
          Exercise(
            id: 'ex-secondary-only',
            ownerUserId: 'user-1',
            name: 'Secondary Only Fixture',
            createdAtMs: _atMs,
            updatedAtMs: _atMs,
          ),
        );
        await repo.setExerciseMuscleLinks('ex-secondary-only', [
          _link('muscle-chest'),
          _link('muscle-lats', MuscleRole.secondary),
        ]);

        final lats = _ids(
          await repo.searchExercises(muscleGroupIds: ['muscle-lats']),
        );
        expect(lats, isNot(contains('ex-secondary-only')));

        final back = _ids(
          await repo.searchExercises(muscleGroupIds: ['muscle-back']),
        );
        expect(back, isNot(contains('ex-secondary-only')));

        final chest = _ids(
          await repo.searchExercises(muscleGroupIds: ['muscle-chest']),
        );
        expect(chest, contains('ex-secondary-only'));
      });

      // Plan 114, S-18804 — Shins (`muscle-tibialis`) is a Legs muscle of its
      // own: the bundled Tibialis Raise matches Shins only, an exercise
      // carrying Calves *and* Shins matches both, a secondary-only Shins link
      // matches nothing, and a Legs selection still reaches every leg muscle.
      group('S-18804 Shins filtering on a fresh install', () {
        Future<void> custom(
          String id,
          String name,
          List<ExerciseMuscleLink> links,
        ) async {
          await repo.createExercise(
            Exercise(
              id: id,
              ownerUserId: 'user-1',
              name: name,
              createdAtMs: _atMs,
              updatedAtMs: _atMs,
            ),
          );
          await repo.setExerciseMuscleLinks(id, links);
        }

        test('S-18804 Shins, Calves and Legs by hierarchy', () async {
          // X: two primary leg muscles, one of them the new one.
          await custom('ex-shin-box-hop', 'Shin Box Hop', [
            _link('muscle-calves'),
            _link('muscle-tibialis'),
          ]);
          // Y: Shins as an assist only.
          await custom('ex-step-down', 'Step-Down', [
            _link('muscle-quads'),
            _link('muscle-tibialis', MuscleRole.secondary),
          ]);
          // Z: the region itself, primary.
          await custom('ex-hill-walk', 'Hill Walk', [_link('muscle-legs')]);
          // E: tagged with nothing.
          await custom('ex-mobility-flow', 'Mobility Flow', const []);
          // W: the user's own near-twin of the bundled row — same name,
          // different id, still on Calves.
          await custom('ex-custom-tibialis-raise', 'Tibialis Raise', [
            _link('muscle-calves'),
          ]);

          final shins = _ids(
            await repo.searchExercises(muscleGroupIds: ['muscle-tibialis']),
          );
          expect(
            shins.toSet(),
            equals({'exercise-tibialis-raise', 'ex-shin-box-hop'}),
            reason: 'Shins matches a primary Shins link and nothing else',
          );
          expect(shins, hasLength(2), reason: 'each match appears once');
          expect(
            shins.where((id) => id == 'exercise-tibialis-raise'),
            hasLength(1),
          );
          expect(shins.where((id) => id == 'ex-shin-box-hop'), hasLength(1));
          expect(shins, isNot(contains('ex-step-down')));
          expect(shins, isNot(contains('ex-hill-walk')));
          expect(shins, isNot(contains('ex-custom-tibialis-raise')));
          expect(shins, isNot(contains('ex-mobility-flow')));

          final calves = _ids(
            await repo.searchExercises(muscleGroupIds: ['muscle-calves']),
          );
          expect(calves, contains('ex-shin-box-hop'));
          expect(calves, contains('ex-custom-tibialis-raise'));
          expect(calves, contains('exercise-standing-calf-raise'));
          expect(calves, isNot(contains('exercise-tibialis-raise')));
          expect(calves, isNot(contains('exercise-nordic-curl')));
          expect(calves, isNot(contains('ex-step-down')));

          final legs = _ids(
            await repo.searchExercises(muscleGroupIds: ['muscle-legs']),
          );
          for (final id in [
            'exercise-tibialis-raise',
            'ex-shin-box-hop',
            'ex-step-down',
            'ex-hill-walk',
            'ex-custom-tibialis-raise',
          ]) {
            expect(legs.where((other) => other == id), hasLength(1), reason: id);
          }
          expect(legs, isNot(contains('ex-mobility-flow')));

          final both = _ids(
            await repo.searchExercises(
              muscleGroupIds: ['muscle-tibialis', 'muscle-legs'],
            ),
          );
          expect(
            both.where((id) => id == 'exercise-tibialis-raise'),
            hasLength(1),
            reason: 'two selections of the same lift return it once',
          );

          final unfiltered = _ids(
            await repo.getExercisesRankedForModality('resistance_lifting'),
          );
          final ranked = _ids(
            await repo.getExercisesRankedForModality(
              'resistance_lifting',
              muscleGroupIds: ['muscle-tibialis'],
            ),
          );
          expect(
            ranked,
            equals([
              for (final id in unfiltered)
                if (id == 'exercise-tibialis-raise' || id == 'ex-shin-box-hop')
                  id,
            ]),
            reason: 'the ranked query keeps its order and filters the same way',
          );
          expect(ranked, contains('exercise-tibialis-raise'));
          expect(ranked, contains('ex-shin-box-hop'));
          expect(ranked, isNot(contains('ex-step-down')));
        });
      });
    });
  }
}
