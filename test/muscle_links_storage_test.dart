// Plan 33, Phase A part 2 — muscle links storage, on both implementations.
//
// Scenarios S-4 (storage on Mock and Hive, the legacy shape included), S-10
// (Hive restart round-trip), S-11 (a link whose group row is missing is stored
// and read back unchanged) and S-13 (set drops a region next to its muscle) of
// `docs/plans/2026-10-14-33-muscle-hierarchy-data-plan/2026-10-14-33-muscle-hierarchy-data-plan.md`.
//
// Plan 35, Phase C2 removed the legacy id-based pair, so the three tests that
// read it now guard the same storage behaviour through the links API;
// "a link whose group row is missing is skipped" lives in the display helper
// and the screen tests (`docs/plans/2026-10-14-35-muscle-display-plan/`).
//
// Every implementation of `WorkoutRepository` must give the same observable
// output, so the shared cases run over `harnessFactories` with plain `test()`
// (a Hive write inside a widget test's FakeAsync never completes).

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

import 'helpers/repository_harness.dart';

/// A fixed timestamp: the fixtures take no clock reading.
const int _atMs = 1700000000000;

ExerciseMuscleLink _link(String id, [MuscleRole role = MuscleRole.primary]) =>
    ExerciseMuscleLink(muscleGroupId: id, role: role);

Exercise _custom(String id) => Exercise(
  id: id,
  ownerUserId: 'user-1',
  name: 'Link Fixture',
  createdAtMs: _atMs,
  updatedAtMs: _atMs,
);

/// The stored links as `id:role` strings, so one expectation covers the ids and
/// their roles in stored order.
List<String> _shape(List<ExerciseMuscleLink> links) => [
  for (final link in links) '${link.muscleGroupId}:${link.role.name}',
];

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — muscle links storage', () {
      late WorkoutRepository repo;

      setUp(() async => repo = await harness.open());
      tearDown(() async => await harness.close());

      test('S-4 set stores the normalised order (primary first)', () async {
        await repo.createExercise(_custom('ex-links-order'));

        await repo.setExerciseMuscleLinks('ex-links-order', [
          _link('muscle-triceps', MuscleRole.secondary),
          _link('muscle-chest'),
        ]);

        expect(_shape(await repo.getExerciseMuscleLinks('ex-links-order')), [
          'muscle-chest:primary',
          'muscle-triceps:secondary',
        ]);
      });

      test('S-4 set drops a region that sits next to its own muscle', () async {
        await repo.createExercise(_custom('ex-links-region'));

        await repo.setExerciseMuscleLinks('ex-links-region', [
          _link('muscle-legs'),
          _link('muscle-quads'),
        ]);

        expect(_shape(await repo.getExerciseMuscleLinks('ex-links-region')), [
          'muscle-quads:primary',
        ]);
      });

      test('S-4 set throws when the list carries no primary', () async {
        await repo.createExercise(_custom('ex-links-no-primary'));

        await expectLater(
          repo.setExerciseMuscleLinks('ex-links-no-primary', [
            _link('muscle-triceps', MuscleRole.secondary),
          ]),
          throwsA(isA<ArgumentError>()),
        );
        expect(
          await repo.getExerciseMuscleLinks('ex-links-no-primary'),
          isEmpty,
        );
      });

      test('S-4 set with an empty list clears the links', () async {
        await repo.createExercise(_custom('ex-links-empty'));

        await repo.setExerciseMuscleLinks('ex-links-empty', [
          _link('muscle-chest'),
        ]);
        await repo.setExerciseMuscleLinks('ex-links-empty', const []);

        expect(await repo.getExerciseMuscleLinks('ex-links-empty'), isEmpty);
      });

      test('S-4 a reopened repository returns the same links', () async {
        await repo.createExercise(_custom('ex-links-reopen'));
        await repo.setExerciseMuscleLinks('ex-links-reopen', [
          _link('muscle-triceps', MuscleRole.secondary),
          _link('muscle-chest'),
        ]);

        repo = await harness.restart();

        expect(_shape(await repo.getExerciseMuscleLinks('ex-links-reopen')), [
          'muscle-chest:primary',
          'muscle-triceps:secondary',
        ]);
      });

      test('S-4 primary links alone keep the whole list, in taxonomy order',
          () async {
        await repo.createExercise(_custom('ex-links-primary-order'));

        await repo.setExerciseMuscleLinks('ex-links-primary-order', [
          _link('muscle-chest'),
          _link('muscle-triceps'),
        ]);

        expect(
          _shape(await repo.getExerciseMuscleLinks('ex-links-primary-order')),
          ['muscle-triceps:primary', 'muscle-chest:primary'],
          reason: 'every id stays primary; taxonomy order puts Triceps first',
        );
      });

      test('S-13 set drops a region next to its muscle and keeps the rest',
          () async {
        await repo.createExercise(_custom('ex-links-region-arms'));

        await repo.setExerciseMuscleLinks('ex-links-region-arms', [
          _link('muscle-arms'),
          _link('muscle-biceps'),
          _link('muscle-chest'),
        ]);

        expect(
          _shape(await repo.getExerciseMuscleLinks('ex-links-region-arms')),
          ['muscle-biceps:primary', 'muscle-chest:primary'],
          reason: 'Arms goes with Biceps; Chest has no muscle next to it',
        );
      });

      test(
        'S-11 a link to a group with no group row is stored and read back '
        'unchanged',
        () async {
          await repo.createExercise(_custom('ex-links-missing-group'));

          await repo.setExerciseMuscleLinks('ex-links-missing-group', [
            _link('muscle-does-not-exist'),
            _link('muscle-chest'),
          ]);

          expect(
            _shape(
              await repo.getExerciseMuscleLinks('ex-links-missing-group'),
            ),
            ['muscle-chest:primary', 'muscle-does-not-exist:primary'],
            reason:
                'the repository stores links, never resolves groups: the '
                'unresolved link is kept, and the skip lives in the display '
                'helper',
          );
        },
      );
    });

    if (harness is HiveRepositoryHarness) {
      group('Hive — muscle links storage', () {
        late WorkoutRepository repo;

        setUp(() async => repo = await harness.open());
        tearDown(() async => await harness.close());

        test('S-4 reads the legacy shape straight out of the box as primary '
            'links', () async {
          await repo.createExercise(_custom('ex-links-old-shape'));

          await Hive.box<List>(
            'exercise_muscle_groups',
          ).put('ex-links-old-shape', ['muscle-legs', 'muscle-quads']);

          expect(
            _shape(await repo.getExerciseMuscleLinks('ex-links-old-shape')),
            ['muscle-legs:primary', 'muscle-quads:primary'],
            reason: 'the reader accepts the old shape and normalises nothing',
          );
        });

        test('S-10 roles survive closing and reopening the store', () async {
          await repo.createExercise(_custom('ex-links-restart'));
          await repo.setExerciseMuscleLinks('ex-links-restart', [
            _link('muscle-triceps', MuscleRole.secondary),
            _link('muscle-chest'),
          ]);

          await Hive.close();
          repo = await harness.restart();

          expect(
            _shape(await repo.getExerciseMuscleLinks('ex-links-restart')),
            ['muscle-chest:primary', 'muscle-triceps:secondary'],
          );
        });
      });
    }
  }
}
