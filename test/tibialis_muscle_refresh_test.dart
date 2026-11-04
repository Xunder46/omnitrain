// Plan 114, Phase 1b — the Shins catalog refresh, on both implementations.
//
// Scenarios S-18805 (a v12 install refreshes to v13), S-18806 (a user-edited
// Tibialis Raise keeps its muscles) and S-18807 (a legacy-shape link row is
// upgraded) of
// `docs/plans/2026-11-04-114-tibialis-muscle-plan/2026-11-04-114-tibialis-muscle-plan.md`.
//
// A v12 device holds the bundled Tibialis Raise on Calves and has never heard
// of `muscle-tibialis`. The refresh must add the group and move the bundled
// row to it, while leaving every row the user owns — a custom exercise, a user
// copy, a touched bundled row — exactly as it was. Both stores must agree, so
// the shared cases run over `harnessFactories` with plain `test()`: a Hive
// write inside a widget test's FakeAsync never completes.

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:omnitrain/core/constants/catalog_version.dart';
import 'package:omnitrain/core/services/bundled_catalog_source.dart';
import 'package:omnitrain/core/services/catalog_refresh_service.dart';
import 'package:omnitrain/core/services/exercise_library_service.dart';
import 'package:omnitrain/core/utils/muscle_display.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

import 'helpers/repository_harness.dart';

/// The production catalog source, so the refresh runs the same legs it runs on
/// a device (muscle groups, links, foods and demo routines).
const BundledCatalogSource _source = BundledCatalogSource();

/// A fixed timestamp: the fixtures take no clock reading.
const int _atMs = 1700000000000;

/// The v12 bundled tagging of `exercise-tibialis-raise`, and the tagging of
/// every other Calves exercise in this file.
const List<ExerciseMuscleLink> _calvesPrimary = [
  ExerciseMuscleLink(muscleGroupId: 'muscle-calves', role: MuscleRole.primary),
];

/// The v13 bundled tagging: Shins, main, and nothing else.
const List<ExerciseMuscleLink> _tibialisPrimary = [
  ExerciseMuscleLink(
    muscleGroupId: 'muscle-tibialis',
    role: MuscleRole.primary,
  ),
];

List<String> _ids(List<Exercise> exercises) => [
  for (final exercise in exercises) exercise.id,
];

/// S-18805 step 1: stage a device that has never been given Shins.
///
/// Mock has no group-delete API — the plan documents this as the one allowed
/// divergence between the two stores — so the step is skipped there and the
/// rest of the scenario is asserted unchanged.
Future<void> _removeShinsGroup(RepositoryHarness harness) async {
  if (harness.name != 'Hive') return;

  await Hive.box<Map>('muscle_groups').delete('muscle-tibialis');
  expect(
    Hive.box<Map>('muscle_groups').keys,
    isNot(contains('muscle-tibialis')),
    reason: 'the staged v12 device has no Shins group row',
  );
}

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — Shins refresh from a v12 install', () {
      late WorkoutRepository repo;

      setUp(() async => repo = await harness.open());
      tearDown(() async => await harness.close());

      test('S-18805 a v12 install refreshes to v13', () async {
        await _removeShinsGroup(harness);
        final stagedGroupIds = [
          for (final group in await repo.getMuscleGroups()) group.id,
        ];
        if (harness.name == 'Hive') {
          expect(
            stagedGroupIds,
            isNot(contains('muscle-tibialis')),
            reason: 'the staged v12 device has no Shins group',
          );
        } else {
          expect(
            stagedGroupIds,
            contains('muscle-tibialis'),
            reason: 'Mock cannot remove a group, so the step is skipped',
          );
        }

        // Step 2: the v12 bundled row, which still sits on Calves.
        await repo.setExerciseMuscleLinks(
          'exercise-tibialis-raise',
          _calvesPrimary,
        );

        // Step 3: the user's own exercise, tagged Calves.
        final custom = Exercise(
          id: 'ex-custom-shin-raise',
          ownerUserId: 'user-1',
          name: 'My Shin Raise',
          createdAtMs: _atMs,
          updatedAtMs: _atMs,
        );
        await repo.createExercise(custom);
        await repo.setExerciseMuscleLinks(custom.id, _calvesPrimary);

        // Step 4: a copy the user made from the row, taken after step 2.
        final copySource = (await repo.getExerciseById(
          'exercise-tibialis-raise',
        ))!;
        final copy = await ExerciseLibraryService(
          repo,
        ).copyAsCustom(copySource);
        expect(
          copy.id,
          isNot(equals('exercise-tibialis-raise')),
          reason: 'a copy is a new custom row',
        );
        expect(
          await repo.getExerciseMuscleLinks(copy.id),
          equals(_calvesPrimary),
          reason: 'the copy carries the links it was made from',
        );

        // Step 5: another bundled Calves row, untouched.
        expect(
          await repo.getExerciseMuscleLinks('exercise-seated-calf-raise'),
          equals(_calvesPrimary),
          reason: 'the bundled row is on Calves before the refresh',
        );

        // Step 6: the literal version a v12 device holds.
        await repo.setCatalogVersion(12);

        final refreshed = await CatalogRefreshService(repo, _source).refresh();
        expect(refreshed, isTrue, reason: 'a v12 device is behind v13');

        expect(await repo.getCatalogVersion(), equals(13));

        final groups = {
          for (final group in await repo.getMuscleGroups()) group.id: group,
        };
        expect(groups['muscle-tibialis'], isNotNull);
        expect(groups['muscle-tibialis']!.name, equals('Shins'));
        expect(groups['muscle-tibialis']!.parentId, equals('muscle-legs'));

        expect(
          await repo.getExerciseMuscleLinks('exercise-tibialis-raise'),
          equals(_tibialisPrimary),
          reason: 'the untouched bundled row moves to Shins',
        );
        expect(
          await repo.getExerciseMuscleLinks(custom.id),
          equals(_calvesPrimary),
          reason: 'a user-owned exercise is never rewritten',
        );
        expect(
          await repo.getExerciseMuscleLinks(copy.id),
          equals(_calvesPrimary),
          reason: 'a user copy is never rewritten',
        );
        expect(
          await repo.getExerciseMuscleLinks('exercise-seated-calf-raise'),
          equals(_calvesPrimary),
          reason: 'the other bundled Calves row is untouched',
        );

        // The dropdown order, not the box order: a refreshed Hive device
        // appends Shins to the end of the box, and the display reorders.
        final filterEntries = muscleFilterEntries(await repo.getMuscleGroups());
        final filterIds = [for (final entry in filterEntries) entry.group.id];
        final legsAt = filterIds.indexOf('muscle-legs');
        expect(legsAt, isNot(equals(-1)), reason: 'Legs is in the filter');
        expect(
          filterIds.sublist(legsAt, legsAt + 7),
          equals([
            'muscle-legs',
            'muscle-quads',
            'muscle-hamstrings',
            'muscle-glutes',
            'muscle-calves',
            'muscle-tibialis',
            'muscle-adductors',
          ]),
          reason: 'Shins sits between Calves and Adductors under Legs',
        );
        expect(
          filterEntries
              .firstWhere((entry) => entry.group.id == 'muscle-tibialis')
              .depth,
          equals(1),
          reason: 'Shins is indented as a Legs muscle',
        );

        final shins = _ids(
          await repo.searchExercises(muscleGroupIds: ['muscle-tibialis']),
        );
        expect(shins, contains('exercise-tibialis-raise'));
        expect(shins, isNot(contains(custom.id)));
        expect(shins, isNot(contains(copy.id)));

        // A second run is a no-op and changes none of the rows above.
        final linksAfterFirst = {
          'exercise-tibialis-raise': await repo.getExerciseMuscleLinks(
            'exercise-tibialis-raise',
          ),
          custom.id: await repo.getExerciseMuscleLinks(custom.id),
          copy.id: await repo.getExerciseMuscleLinks(copy.id),
          'exercise-seated-calf-raise': await repo.getExerciseMuscleLinks(
            'exercise-seated-calf-raise',
          ),
        };
        expect(
          await CatalogRefreshService(repo, _source).refresh(),
          isFalse,
          reason: 'the device is at the bundled version now',
        );
        expect(await repo.getCatalogVersion(), equals(13));
        for (final entry in linksAfterFirst.entries) {
          expect(
            await repo.getExerciseMuscleLinks(entry.key),
            equals(entry.value),
            reason: '${entry.key} is unchanged by the second run',
          );
        }
        expect(
          linksAfterFirst['exercise-tibialis-raise'],
          equals(_tibialisPrimary),
        );
      });

      test('S-18806 a user-edited Tibialis Raise keeps its muscles', () async {
        await _removeShinsGroup(harness);

        const edited = [
          ExerciseMuscleLink(
            muscleGroupId: 'muscle-calves',
            role: MuscleRole.primary,
          ),
          ExerciseMuscleLink(
            muscleGroupId: 'muscle-quads',
            role: MuscleRole.secondary,
          ),
        ];
        await repo.setExerciseMuscleLinks('exercise-tibialis-raise', edited);
        await repo.markSeedEntryTouched(
          SeedEntryType.exercise,
          'exercise-tibialis-raise',
        );

        await repo.setCatalogVersion(12);
        expect(
          await CatalogRefreshService(repo, _source).refresh(),
          isTrue,
          reason: 'a v12 device is behind v13',
        );

        expect(
          await repo.getExerciseMuscleLinks('exercise-tibialis-raise'),
          equals(edited),
          reason: 'the user edited this row, so their muscles win',
        );

        final groups = {
          for (final group in await repo.getMuscleGroups()) group.id: group,
        };
        expect(groups['muscle-tibialis'], isNotNull);
        expect(groups['muscle-tibialis']!.name, equals('Shins'));
        expect(groups['muscle-tibialis']!.parentId, equals('muscle-legs'));

        final shins = _ids(
          await repo.searchExercises(muscleGroupIds: ['muscle-tibialis']),
        );
        expect(shins, isNot(contains('exercise-tibialis-raise')));

        expect(await repo.getCatalogVersion(), equals(13));
      });
    });

    if (harness is HiveRepositoryHarness) {
      group('${harness.name} — Shins legacy link row', () {
        late WorkoutRepository repo;

        setUp(() async => repo = await harness.open());
        tearDown(() async => await harness.close());

        test('S-18807 a legacy-shape row is upgraded by the refresh', () async {
          await _removeShinsGroup(harness);

          // The pre-plan-33 shape: plain group ids, all primary.
          await Hive.box<List>(
            'exercise_muscle_groups',
          ).put('exercise-tibialis-raise', <String>['muscle-calves']);
          expect(
            await repo.getExerciseMuscleLinks('exercise-tibialis-raise'),
            equals(_calvesPrimary),
            reason: 'the reader accepts the legacy shape as primary links',
          );

          await repo.setCatalogVersion(12);
          expect(
            await CatalogRefreshService(repo, _source).refresh(),
            isTrue,
            reason: 'a v12 device is behind v13',
          );

          expect(
            await repo.getExerciseMuscleLinks('exercise-tibialis-raise'),
            equals(_tibialisPrimary),
          );
          final raw = Hive.box<List>(
            'exercise_muscle_groups',
          ).get('exercise-tibialis-raise');
          expect(raw, isNotNull);
          expect(
            raw!.first,
            isA<Map>(),
            reason: 'the row is rewritten in the current map shape',
          );
        });
      });
    }
  }
}
