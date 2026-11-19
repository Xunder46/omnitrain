// Plan 115a, Phase 3 — the strength catalog refresh, on both implementations.
//
// Scenarios S-18906 (a v13 install refreshes to v14) and S-18907 (a
// user-edited row keeps its muscles) of
// `docs/plans/2026-11-04-115a-strength-catalog-gaps-plan/2026-11-04-115a-strength-catalog-gaps-plan.md`.
//
// A v13 device has never heard of Brachialis, Rotator cuff or Abductors, still
// carries the pre-change tags on the three re-tagged rows, and has none of the
// 28 new exercises. The refresh must add the groups and the rows, move the
// untouched re-tagged rows to their new muscles, and leave every row the user
// owns — a custom exercise, a user copy, a touched bundled row — exactly as it
// was. Both stores must agree, so the shared cases run over `harnessFactories`
// with plain `test()`: a Hive write inside a widget test's FakeAsync never
// completes.

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:omnitrain/core/constants/catalog_version.dart';
import 'package:omnitrain/core/services/bundled_catalog_source.dart';
import 'package:omnitrain/core/services/catalog_refresh_service.dart';
import 'package:omnitrain/core/services/exercise_library_service.dart';
import 'package:omnitrain/core/utils/exercise_helpers.dart';
import 'package:omnitrain/core/utils/muscle_display.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/mock/seed_data.dart';

import 'helpers/repository_harness.dart';

/// The production catalog source, so the refresh runs the same legs it runs on
/// a device (muscle groups, links, foods and demo routines).
const BundledCatalogSource _source = BundledCatalogSource();

/// A fixed timestamp: the fixtures take no clock reading.
const int _atMs = 1700000000000;

/// The three groups plan 115a adds; their names and parents are D-18901.
const List<(String, String, String)> _newGroups = [
  ('muscle-brachialis', 'Brachialis', 'muscle-arms'),
  ('muscle-rotator-cuff', 'Rotator cuff', 'muscle-shoulders'),
  ('muscle-abductors', 'Abductors', 'muscle-legs'),
];

/// The 28 exercises plan 115a adds, by id.
const List<String> _newExerciseIds = [
  'exercise-side-lying-external-rotation',
  'exercise-cable-internal-rotation',
  'exercise-band-pull-apart',
  'exercise-machine-hip-abduction',
  'exercise-banded-clamshell',
  'exercise-banded-lateral-walk',
  'exercise-incline-dumbbell-curl',
  'exercise-cable-curl',
  'exercise-concentration-curl',
  'exercise-reverse-curl',
  'exercise-zottman-curl',
  'exercise-cross-body-hammer-curl',
  'exercise-close-grip-bench-press',
  'exercise-triceps-kickback',
  'exercise-diamond-push-up',
  'exercise-bench-dip',
  'exercise-leg-extension',
  'exercise-lying-leg-curl',
  'exercise-seated-leg-curl',
  'exercise-dumbbell-fly',
  'exercise-incline-dumbbell-fly',
  'exercise-cable-crossover',
  'exercise-low-to-high-cable-fly',
  'exercise-pec-deck-fly',
  'exercise-machine-shoulder-press',
  'exercise-cable-rear-delt-fly',
  'exercise-reverse-pec-deck',
  'exercise-dumbbell-shrug',
];

/// The v13 tagging of `exercise-cable-hip-abduction`, and the tagging of the
/// custom row and the user copy in this file.
const List<ExerciseMuscleLink> _glutesPrimary = [
  ExerciseMuscleLink(muscleGroupId: 'muscle-glutes', role: MuscleRole.primary),
];

/// The v13 tagging of `exercise-hammer-curl`.
const List<ExerciseMuscleLink> _bicepsAndForearms = [
  ExerciseMuscleLink(muscleGroupId: 'muscle-biceps', role: MuscleRole.primary),
  ExerciseMuscleLink(
    muscleGroupId: 'muscle-forearms',
    role: MuscleRole.secondary,
  ),
];

/// The v13 tagging of `exercise-machine-hip-adduction`, which the refresh must
/// leave alone.
const List<ExerciseMuscleLink> _adductorsPrimary = [
  ExerciseMuscleLink(
    muscleGroupId: 'muscle-adductors',
    role: MuscleRole.primary,
  ),
];

/// The description `exercise-rear-delt-fly` carried before Reverse Pec Deck
/// became a row of its own (D-18911 names the bundled replacement).
const String _oldRearDeltFlyDescription =
    'A reverse fly performed with dumbbells or a reverse pec-deck, isolating '
    'the rear delts and upper back.';

const String _bundledRearDeltFlyDescription =
    'A reverse fly performed with dumbbells, isolating the rear delts and '
    'upper back.';

List<String> _ids(List<Exercise> exercises) => [
  for (final exercise in exercises) exercise.id,
];

final Map<String, Exercise> _bundledById = {
  for (final exercise in SeedData.sampleExercises) exercise.id: exercise,
};

/// S-18906 step 1: stage a device that has never been given the new muscles.
///
/// Mock has no group-delete API — the plan documents this as the one allowed
/// divergence between the two stores — so the step is skipped there and the
/// rest of the scenario is asserted unchanged.
Future<void> _removeNewGroups(RepositoryHarness harness) async {
  if (harness.name != 'Hive') return;

  final box = Hive.box<Map>('muscle_groups');
  for (final (id, _, _) in _newGroups) {
    await box.delete(id);
  }
  for (final (id, _, _) in _newGroups) {
    expect(
      box.keys,
      isNot(contains(id)),
      reason: 'the staged v13 device has no $id row',
    );
  }
}

/// S-18906 step 2: a v13 device carries none of the 28 new exercises.
Future<void> _removeNewExercises(
  RepositoryHarness harness,
  WorkoutRepository repo,
) async {
  for (final id in _newExerciseIds) {
    await repo.deleteExercise(id);
    await repo.setExerciseCapabilities(id, const []);
    await repo.setExerciseMuscleLinks(id, const []);
  }
  if (harness.name == 'Hive') {
    // The refresh does not deliver equipment, so a v13 device has none of it
    // for these ids either (D-18909).
    final equipmentBox = Hive.box<List>('exercise_equipment');
    for (final id in _newExerciseIds) {
      await equipmentBox.delete(id);
    }
  }
}

/// S-18906 steps 3–7: the v13 rows, the user's own rows, and the copy.
Future<({Exercise customGlute, Exercise customLegExtension, Exercise copy})>
_stageV13Rows(WorkoutRepository repo) async {
  // Step 3: the three rows whose bundled tags change, and the old text of
  // Rear Delt Fly.
  await repo.setExerciseMuscleLinks(
    'exercise-cable-hip-abduction',
    _glutesPrimary,
  );
  await repo.setExerciseMuscleLinks('exercise-cable-external-rotation', const [
    ExerciseMuscleLink(
      muscleGroupId: 'muscle-rear-delts',
      role: MuscleRole.primary,
    ),
  ]);
  await repo.setExerciseMuscleLinks('exercise-hammer-curl', _bicepsAndForearms);
  final rearDeltFly = await repo.getExerciseById('exercise-rear-delt-fly');
  expect(rearDeltFly, isNotNull, reason: 'the bundled row is on the device');
  await repo.updateExercise(
    rearDeltFly!.copyWith(description: _oldRearDeltFlyDescription),
  );

  // Step 4: the user's own exercise, tagged Glutes before the change.
  final customGlute = Exercise(
    id: 'ex-custom-glute-side-raise',
    ownerUserId: 'user-1',
    name: 'Glute Side Raise',
    createdAtMs: _atMs,
    updatedAtMs: _atMs,
  );
  await repo.createExercise(customGlute);
  await repo.setExerciseMuscleLinks(customGlute.id, _glutesPrimary);

  // Step 5: a custom whose name matches a row about to arrive.
  final customLegExtension = Exercise(
    id: 'ex-custom-leg-extension',
    ownerUserId: 'user-1',
    name: 'Leg Extension',
    createdAtMs: _atMs,
    updatedAtMs: _atMs,
  );
  await repo.createExercise(customLegExtension);
  await repo.setExerciseMuscleLinks(customLegExtension.id, const [
    ExerciseMuscleLink(muscleGroupId: 'muscle-quads', role: MuscleRole.primary),
  ]);

  // Step 6: a copy of the re-tagged row, taken after step 3.
  final copy = await ExerciseLibraryService(
    repo,
  ).copyAsCustom((await repo.getExerciseById('exercise-cable-hip-abduction'))!);
  expect(
    copy.id,
    isNot(equals('exercise-cable-hip-abduction')),
    reason: 'a copy is a new custom row',
  );

  // Step 7: another bundled row the change does not touch.
  expect(
    await repo.getExerciseMuscleLinks('exercise-machine-hip-adduction'),
    equals(_adductorsPrimary),
    reason: 'the adduction row is on Adductors before the refresh',
  );

  return (
    customGlute: customGlute,
    customLegExtension: customLegExtension,
    copy: copy,
  );
}

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — strength catalog refresh from a v13 install', () {
      late WorkoutRepository repo;

      setUp(() async => repo = await harness.open());
      tearDown(() async => await harness.close());

      test('S-18906 a v13 install refreshes to v14', () async {
        await _removeNewGroups(harness);
        await _removeNewExercises(harness, repo);
        final staged = await _stageV13Rows(repo);

        // Step 8: the literal version a v13 device holds.
        await repo.setCatalogVersion(13);

        expect(
          await CatalogRefreshService(repo, _source).refresh(),
          isTrue,
          reason: 'a v13 device is behind the bundled version',
        );

        expect(await repo.getCatalogVersion(), equals(bundledCatalogVersion));
        expect(
          bundledCatalogVersion,
          greaterThanOrEqualTo(14),
          reason: 'plan 115a ships catalog version 14',
        );

        final groups = {
          for (final group in await repo.getMuscleGroups()) group.id: group,
        };
        for (final (id, name, parentId) in _newGroups) {
          expect(groups[id], isNotNull, reason: 'the refresh adds $id');
          expect(groups[id]!.name, equals(name));
          expect(groups[id]!.parentId, equals(parentId));
        }

        // The three re-tags, exactly as D-18902 writes them.
        expect(
          await repo.getExerciseMuscleLinks('exercise-cable-hip-abduction'),
          equals(const [
            ExerciseMuscleLink(
              muscleGroupId: 'muscle-abductors',
              role: MuscleRole.primary,
            ),
            ExerciseMuscleLink(
              muscleGroupId: 'muscle-glutes',
              role: MuscleRole.secondary,
            ),
          ]),
        );
        expect(
          await repo.getExerciseMuscleLinks('exercise-cable-external-rotation'),
          equals(const [
            ExerciseMuscleLink(
              muscleGroupId: 'muscle-rotator-cuff',
              role: MuscleRole.primary,
            ),
            ExerciseMuscleLink(
              muscleGroupId: 'muscle-rear-delts',
              role: MuscleRole.secondary,
            ),
          ]),
        );
        expect(
          await repo.getExerciseMuscleLinks('exercise-hammer-curl'),
          equals(const [
            ExerciseMuscleLink(
              muscleGroupId: 'muscle-biceps',
              role: MuscleRole.primary,
            ),
            ExerciseMuscleLink(
              muscleGroupId: 'muscle-brachialis',
              role: MuscleRole.primary,
            ),
            ExerciseMuscleLink(
              muscleGroupId: 'muscle-forearms',
              role: MuscleRole.secondary,
            ),
          ]),
        );

        // Every new row, with the name the bundle gives it and the bundled
        // capabilities and links.
        for (final id in _newExerciseIds) {
          final exercise = await repo.getExerciseById(id);
          expect(exercise, isNotNull, reason: 'the refresh adds $id');
          expect(
            exercise!.name,
            equals(_bundledById[id]!.name),
            reason: 'the bundled name of $id',
          );

          final bundledCapabilities =
              SeedData.exerciseCapabilityRelationships[id]!;
          final capabilities = await repo.getExerciseCapabilities(id);
          expect(
            capabilities.toSet(),
            equals(bundledCapabilities.toSet()),
            reason: 'the bundled capabilities of $id',
          );
          expect(capabilities, hasLength(bundledCapabilities.length));

          final bundledLinks = SeedData.exerciseMuscleLinks[id]!;
          final links = await repo.getExerciseMuscleLinks(id);
          expect(
            links.toSet(),
            equals(bundledLinks.toSet()),
            reason: 'the bundled muscle links of $id',
          );
          expect(links, hasLength(bundledLinks.length));
        }

        // Rows the user owns are never rewritten (D-18910).
        expect(
          await repo.getExerciseMuscleLinks(staged.customGlute.id),
          equals(_glutesPrimary),
          reason: 'a user-owned exercise keeps its muscles',
        );
        expect(
          await repo.getExerciseMuscleLinks(staged.copy.id),
          equals(_glutesPrimary),
          reason: 'a user copy keeps the muscles it was made from',
        );
        final keptCustom = await repo.getExerciseById(
          staged.customLegExtension.id,
        );
        expect(keptCustom, isNotNull, reason: 'the custom row survives');
        expect(keptCustom!.name, equals('Leg Extension'));
        expect(
          await repo.getExerciseMuscleLinks(staged.customLegExtension.id),
          equals(const [
            ExerciseMuscleLink(
              muscleGroupId: 'muscle-quads',
              role: MuscleRole.primary,
            ),
          ]),
          reason: 'a custom whose name matches a new row is never rewritten',
        );
        final legExtensions = _ids(
          await repo.searchExercises(searchText: 'Leg Extension'),
        );
        expect(legExtensions, contains(staged.customLegExtension.id));
        expect(legExtensions, contains('exercise-leg-extension'));

        // A row the change does not reach is untouched.
        expect(
          await repo.getExerciseMuscleLinks('exercise-machine-hip-adduction'),
          equals(_adductorsPrimary),
        );

        final rearDeltFly = await repo.getExerciseById(
          'exercise-rear-delt-fly',
        );
        expect(
          rearDeltFly!.description,
          equals(_bundledRearDeltFlyDescription),
          reason: 'the untouched row receives the bundled text',
        );

        // The dropdown order, not the box order: a refreshed Hive device
        // appends the new groups to the end of the box, and the display
        // reorders.
        final filterIds = [
          for (final entry in muscleFilterEntries(await repo.getMuscleGroups()))
            entry.group.id,
        ];
        final armsAt = filterIds.indexOf('muscle-arms');
        expect(armsAt, isNot(equals(-1)), reason: 'Arms is in the filter');
        expect(
          filterIds.sublist(armsAt, armsAt + 5),
          equals([
            'muscle-arms',
            'muscle-biceps',
            'muscle-triceps',
            'muscle-forearms',
            'muscle-brachialis',
          ]),
          reason: 'Brachialis ends the Arms block',
        );
        final shouldersAt = filterIds.indexOf('muscle-shoulders');
        expect(
          shouldersAt,
          isNot(equals(-1)),
          reason: 'Shoulders is in the filter',
        );
        expect(
          filterIds.sublist(shouldersAt, shouldersAt + 5),
          equals([
            'muscle-shoulders',
            'muscle-front-delts',
            'muscle-side-delts',
            'muscle-rear-delts',
            'muscle-rotator-cuff',
          ]),
          reason: 'Rotator cuff ends the Shoulders block',
        );
        final legsAt = filterIds.indexOf('muscle-legs');
        expect(legsAt, isNot(equals(-1)), reason: 'Legs is in the filter');
        expect(
          filterIds.sublist(legsAt + 6, legsAt + 8),
          equals(['muscle-adductors', 'muscle-abductors']),
          reason: 'Abductors ends the Legs block',
        );

        if (harness.name == 'Hive') {
          // D-18909: the refresh delivers no equipment. An equipment-delivery
          // PR must change this assertion on purpose.
          expect(
            await repo.getExerciseEquipment('exercise-leg-extension'),
            isEmpty,
            reason: 'the refresh does not deliver equipment',
          );
        }

        // A second run is a no-op and changes none of the rows above.
        final watchedIds = [
          'exercise-cable-hip-abduction',
          'exercise-cable-external-rotation',
          'exercise-hammer-curl',
          staged.customGlute.id,
          staged.copy.id,
          staged.customLegExtension.id,
          'exercise-machine-hip-adduction',
          'exercise-reverse-curl',
        ];
        final linksAfterFirst = {
          for (final id in watchedIds)
            id: await repo.getExerciseMuscleLinks(id),
        };
        expect(
          await CatalogRefreshService(repo, _source).refresh(),
          isFalse,
          reason: 'the device is at the bundled version now',
        );
        expect(await repo.getCatalogVersion(), equals(bundledCatalogVersion));
        for (final entry in linksAfterFirst.entries) {
          expect(
            await repo.getExerciseMuscleLinks(entry.key),
            equals(entry.value),
            reason: '${entry.key} is unchanged by the second run',
          );
        }
        expect(
          (await repo.getExerciseById('exercise-rear-delt-fly'))!.description,
          equals(_bundledRearDeltFlyDescription),
        );
      });

      test('S-18907 a user-edited row keeps its muscles', () async {
        // S-18906 steps 1 and 8.
        await _removeNewGroups(harness);
        await repo.setCatalogVersion(13);

        const editedAbduction = [
          ExerciseMuscleLink(
            muscleGroupId: 'muscle-glutes',
            role: MuscleRole.primary,
          ),
          ExerciseMuscleLink(
            muscleGroupId: 'muscle-hamstrings',
            role: MuscleRole.secondary,
          ),
        ];
        await repo.setExerciseMuscleLinks(
          'exercise-cable-hip-abduction',
          editedAbduction,
        );
        await repo.markSeedEntryTouched(
          SeedEntryType.exercise,
          'exercise-cable-hip-abduction',
        );

        final hammerCurl = (await repo.getExerciseById(
          'exercise-hammer-curl',
        ))!;
        await repo.updateExercise(hammerCurl.copyWith(name: 'My Hammer Curl'));
        await repo.setExerciseMuscleLinks('exercise-hammer-curl', const [
          ExerciseMuscleLink(
            muscleGroupId: 'muscle-biceps',
            role: MuscleRole.primary,
          ),
        ]);
        await repo.markSeedEntryTouched(
          SeedEntryType.exercise,
          'exercise-hammer-curl',
        );

        expect(
          await CatalogRefreshService(repo, _source).refresh(),
          isTrue,
          reason: 'a v13 device is behind the bundled version',
        );

        final keptHammerCurl = await repo.getExerciseById(
          'exercise-hammer-curl',
        );
        expect(keptHammerCurl, isNotNull);
        expect(
          keptHammerCurl!.name,
          equals('My Hammer Curl'),
          reason: 'the user renamed this row, so their name wins',
        );
        expect(
          await repo.getExerciseMuscleLinks('exercise-hammer-curl'),
          equals(const [
            ExerciseMuscleLink(
              muscleGroupId: 'muscle-biceps',
              role: MuscleRole.primary,
            ),
          ]),
          reason: 'the user edited this row, so their muscles win',
        );
        expect(
          await repo.getExerciseMuscleLinks('exercise-cable-hip-abduction'),
          equals(editedAbduction),
          reason: 'the user edited this row, so their muscles win',
        );

        final abduction = _ids(
          await repo.searchExercises(muscleGroupIds: ['muscle-abductors']),
        );
        expect(
          abduction,
          isNot(contains('exercise-cable-hip-abduction')),
          reason: 'the touched row keeps its own tags',
        );
        final brachialis = _ids(
          await repo.searchExercises(muscleGroupIds: ['muscle-brachialis']),
        );
        expect(
          brachialis,
          isNot(contains('exercise-hammer-curl')),
          reason: 'the touched row keeps its own tags',
        );

        final groups = {
          for (final group in await repo.getMuscleGroups()) group.id: group,
        };
        for (final (id, name, parentId) in _newGroups) {
          expect(groups[id], isNotNull);
          expect(groups[id]!.name, equals(name));
          expect(groups[id]!.parentId, equals(parentId));
        }

        expect(await repo.getCatalogVersion(), equals(bundledCatalogVersion));
        expect(bundledCatalogVersion, greaterThanOrEqualTo(14));
      });
    });
  }
}
