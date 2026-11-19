// Plan 115b, Phase 3 — the v15 strength catalog refresh, on both
// implementations.
//
// Scenarios S-19006 (a v14 install refreshes to v15), S-19007 (a renamed
// touched row and near-twins keep their own) and S-19008 (equipment on a new
// install, and a link to a missing equipment row) of
// `docs/plans/2026-11-04-115b-strength-catalog-gaps-plan/2026-11-04-115b-strength-catalog-gaps-plan.md`.
//
// A v14 device has none of the 20 new exercises and no Trap Bar or Sled
// equipment row. The refresh must add the 20 rows — with their capabilities
// and muscle links — and deliver no equipment; the equipment links exist on a
// new install only. Rows the user owns — a custom with a new row's name, a user
// copy, a renamed touched bundled row — stay exactly as they were. Both stores
// must agree, so the shared cases run over `harnessFactories` with plain
// `test()`: a Hive write inside a widget test's FakeAsync never completes.

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:omnitrain/core/constants/catalog_version.dart';
import 'package:omnitrain/core/services/bundled_catalog_source.dart';
import 'package:omnitrain/core/services/catalog_refresh_service.dart';
import 'package:omnitrain/core/services/exercise_library_service.dart';
import 'package:omnitrain/core/utils/exercise_helpers.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/mock/seed_data.dart';

import 'helpers/repository_harness.dart';

/// The production catalog source, so the refresh runs the same legs it runs on
/// a device (muscle groups, links, foods and demo routines).
const BundledCatalogSource _source = BundledCatalogSource();

/// A fixed timestamp: the fixtures take no clock reading.
const int _atMs = 1700000000000;

/// The 20 exercises plan 115b adds, by id.
const List<String> _newExerciseIds = [
  'exercise-sit-up',
  'exercise-crunch',
  'exercise-reverse-crunch',
  'exercise-bicycle-crunch',
  'exercise-russian-twist',
  'exercise-hanging-knee-raise',
  'exercise-dead-bug',
  'exercise-bird-dog',
  'exercise-cable-side-bend',
  'exercise-push-press',
  'exercise-trap-bar-deadlift',
  'exercise-rack-pull',
  'exercise-lateral-lunge',
  'exercise-curtsy-lunge',
  'exercise-single-leg-hip-thrust',
  'exercise-donkey-calf-raise',
  'exercise-leg-press-calf-raise',
  'exercise-reverse-hyperextension',
  'exercise-sled-push',
  'exercise-sled-drag',
];

/// The user's own near-twin of `exercise-sit-up` in this file.
const List<ExerciseMuscleLink> _absAndObliques = [
  ExerciseMuscleLink(muscleGroupId: 'muscle-abs', role: MuscleRole.primary),
  ExerciseMuscleLink(
    muscleGroupId: 'muscle-obliques',
    role: MuscleRole.secondary,
  ),
];

List<String> _ids(List<Exercise> exercises) => [
  for (final exercise in exercises) exercise.id,
];

List<String> _equipmentNames(List<Equipment> equipment) => [
  for (final item in equipment) item.name,
];

final Map<String, Exercise> _bundledById = {
  for (final exercise in SeedData.sampleExercises) exercise.id: exercise,
};

/// S-19006 step 1: a v14 device carries none of the 20 new exercises.
///
/// The refresh delivers no equipment either, so on Hive the staged device has
/// no equipment link for them. Mock has no equipment-delete path — documented
/// as the one allowed divergence between the two stores — so that step is
/// skipped there and the rest of the scenario is asserted unchanged.
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
    final equipmentBox = Hive.box<List>('exercise_equipment');
    for (final id in _newExerciseIds) {
      await equipmentBox.delete(id);
    }
  }
}

/// S-19006 step 2: a v14 device has neither the Trap Bar nor the Sled
/// equipment row (D-19004: the refresh writes neither).
///
/// Mock cannot remove an equipment row, so the step is skipped there.
Future<void> _removeNewEquipment(RepositoryHarness harness) async {
  if (harness.name != 'Hive') return;

  final box = Hive.box<Map>('equipment');
  for (final id in ['equipment-trap-bar', 'equipment-sled']) {
    await box.delete(id);
  }
  for (final id in ['equipment-trap-bar', 'equipment-sled']) {
    expect(
      box.keys,
      isNot(contains(id)),
      reason: 'the staged v14 device has no $id row',
    );
  }
}

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — strength catalog refresh from a v14 install', () {
      late WorkoutRepository repo;

      setUp(() async => repo = await harness.open());
      tearDown(() async => await harness.close());

      test('S-19006 a v14 install refreshes to v15', () async {
        await _removeNewExercises(harness, repo);
        await _removeNewEquipment(harness);

        // Step 3: the user's own "Sit-Up", the same name as a row arriving.
        final customSitUp = Exercise(
          id: 'ex-custom-sit-up',
          ownerUserId: 'user-1',
          name: 'Sit-Up',
          createdAtMs: _atMs,
          updatedAtMs: _atMs,
        );
        await repo.createExercise(customSitUp);
        await repo.setExerciseMuscleLinks(customSitUp.id, _absAndObliques);

        // Step 4: a copy of a bundled row the change does not touch.
        final copy = await ExerciseLibraryService(repo).copyAsCustom(
          (await repo.getExerciseById('exercise-hanging-leg-raise'))!,
        );
        final copyLinks = await repo.getExerciseMuscleLinks(copy.id);

        // Step 5: a row the change does not touch.
        expect(
          (await repo.getExerciseCapabilities(
            'exercise-farmers-carry',
          )).toSet(),
          equals({'time', 'distance', 'load'}),
          reason: "Farmer's Carry carries capability set C before the refresh",
        );

        // Step 6: the literal version a v14 device holds.
        await repo.setCatalogVersion(14);

        expect(
          await CatalogRefreshService(repo, _source).refresh(),
          isTrue,
          reason: 'a v14 device is behind the bundled version',
        );

        expect(await repo.getCatalogVersion(), equals(bundledCatalogVersion));
        expect(
          bundledCatalogVersion,
          greaterThanOrEqualTo(15),
          reason: 'plan 115b ships catalog version 15',
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

        // The user's own rows are never rewritten (D-19009, D-18910).
        final keptSitUp = await repo.getExerciseById(customSitUp.id);
        expect(keptSitUp, isNotNull, reason: 'the custom row survives');
        expect(keptSitUp!.name, equals('Sit-Up'));
        expect(
          await repo.getExerciseMuscleLinks(customSitUp.id),
          equals(_absAndObliques),
          reason: 'a same-name custom keeps its tagging',
        );
        final sitUpSearch = _ids(
          await repo.searchExercises(searchText: 'Sit-Up'),
        );
        expect(sitUpSearch, contains(customSitUp.id));
        expect(sitUpSearch, contains('exercise-sit-up'));
        expect(
          await repo.getExerciseMuscleLinks(copy.id),
          equals(copyLinks),
          reason: 'a user copy keeps the links it was made from',
        );

        // A row the change does not reach is untouched.
        expect(
          (await repo.getExerciseCapabilities(
            'exercise-farmers-carry',
          )).toSet(),
          equals({'time', 'distance', 'load'}),
        );

        if (harness.name == 'Hive') {
          // D-19004: the refresh delivers no equipment. An equipment-delivery
          // PR must change these assertions on purpose.
          for (final id in [
            'exercise-trap-bar-deadlift',
            'exercise-sled-push',
            'exercise-cable-side-bend',
          ]) {
            expect(
              await repo.getExerciseEquipment(id),
              isEmpty,
              reason: 'the refresh does not deliver equipment for $id',
            );
          }
          final equipmentNames = _equipmentNames(await repo.getEquipment());
          expect(equipmentNames, isNot(contains('Trap Bar')));
          expect(equipmentNames, isNot(contains('Sled')));
        }

        // A second run is a no-op and changes none of the rows above.
        final watchedIds = [customSitUp.id, copy.id, ..._newExerciseIds];
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
      });

      test(
        'S-19007 a renamed touched row and near-twins keep their own',
        () async {
          // Step 1: the v14 device has no Hanging Knee Raise row.
          await repo.deleteExercise('exercise-hanging-knee-raise');
          await repo.setExerciseCapabilities(
            'exercise-hanging-knee-raise',
            const [],
          );
          await repo.setExerciseMuscleLinks(
            'exercise-hanging-knee-raise',
            const [],
          );
          if (harness.name == 'Hive') {
            await Hive.box<List>(
              'exercise_equipment',
            ).delete('exercise-hanging-knee-raise');
          }

          // Step 2: the user renamed the existing Hanging Leg Raise to the new
          // row's name, and the touched marker keeps their row as it is.
          final legRaise = (await repo.getExerciseById(
            'exercise-hanging-leg-raise',
          ))!;
          await repo.updateExercise(
            legRaise.copyWith(name: 'Hanging Knee Raise'),
          );
          await repo
              .setExerciseMuscleLinks('exercise-hanging-leg-raise', const [
                ExerciseMuscleLink(
                  muscleGroupId: 'muscle-abs',
                  role: MuscleRole.primary,
                ),
                ExerciseMuscleLink(
                  muscleGroupId: 'muscle-forearms',
                  role: MuscleRole.secondary,
                ),
              ]);
          await repo.markSeedEntryTouched(
            SeedEntryType.exercise,
            'exercise-hanging-leg-raise',
          );

          // Step 3: two custom near-twins of the new name.
          for (final (id, name) in [
            ('ex-custom-situp', 'Situp'),
            ('ex-custom-sit-up-lower', 'sit-up '),
          ]) {
            await repo.createExercise(
              Exercise(
                id: id,
                ownerUserId: 'user-1',
                name: name,
                createdAtMs: _atMs,
                updatedAtMs: _atMs,
              ),
            );
            await repo.setExerciseMuscleLinks(id, const [
              ExerciseMuscleLink(
                muscleGroupId: 'muscle-abs',
                role: MuscleRole.primary,
              ),
            ]);
          }

          // Step 4: the literal version a v14 device holds.
          await repo.setCatalogVersion(14);

          expect(
            await CatalogRefreshService(repo, _source).refresh(),
            isTrue,
            reason: 'a v14 device is behind the bundled version',
          );

          final keptLegRaise = await repo.getExerciseById(
            'exercise-hanging-leg-raise',
          );
          expect(keptLegRaise, isNotNull);
          expect(
            keptLegRaise!.name,
            equals('Hanging Knee Raise'),
            reason: 'the user renamed this row, so their name wins',
          );
          expect(
            await repo.getExerciseMuscleLinks('exercise-hanging-leg-raise'),
            equals(const [
              ExerciseMuscleLink(
                muscleGroupId: 'muscle-abs',
                role: MuscleRole.primary,
              ),
              ExerciseMuscleLink(
                muscleGroupId: 'muscle-forearms',
                role: MuscleRole.secondary,
              ),
            ]),
            reason: 'the user edited this row, so their muscles win',
          );

          final kneeRaise = await repo.getExerciseById(
            'exercise-hanging-knee-raise',
          );
          expect(
            kneeRaise,
            isNotNull,
            reason: 'the refresh adds the new row beside the renamed one',
          );
          expect(
            kneeRaise!.name,
            equals(_bundledById['exercise-hanging-knee-raise']!.name),
          );
          final bundledLinks =
              SeedData.exerciseMuscleLinks['exercise-hanging-knee-raise']!;
          final links = await repo.getExerciseMuscleLinks(
            'exercise-hanging-knee-raise',
          );
          expect(links.toSet(), equals(bundledLinks.toSet()));
          expect(links, hasLength(bundledLinks.length));

          final search = _ids(
            await repo.searchExercises(searchText: 'Hanging Knee Raise'),
          );
          expect(search, contains('exercise-hanging-leg-raise'));
          expect(search, contains('exercise-hanging-knee-raise'));

          for (final (id, name) in [
            ('ex-custom-situp', 'Situp'),
            ('ex-custom-sit-up-lower', 'sit-up '),
          ]) {
            final custom = await repo.getExerciseById(id);
            expect(custom, isNotNull, reason: 'the custom $id survives');
            expect(custom!.name, equals(name));
            expect(
              await repo.getExerciseMuscleLinks(id),
              equals(const [
                ExerciseMuscleLink(
                  muscleGroupId: 'muscle-abs',
                  role: MuscleRole.primary,
                ),
              ]),
            );
          }

          final abs = _ids(
            await repo.searchExercises(muscleGroupIds: ['muscle-abs']),
          );
          for (final id in [
            'exercise-hanging-knee-raise',
            'ex-custom-situp',
            'ex-custom-sit-up-lower',
          ]) {
            expect(abs.where((other) => other == id), hasLength(1), reason: id);
          }

          expect(await repo.getCatalogVersion(), equals(bundledCatalogVersion));
        },
      );

      test('S-19008 a new install knows the equipment', () async {
        expect(
          _equipmentNames(
            await repo.getExerciseEquipment('exercise-trap-bar-deadlift'),
          ),
          equals(['Trap Bar']),
        );
        for (final id in ['exercise-sled-push', 'exercise-sled-drag']) {
          expect(
            _equipmentNames(await repo.getExerciseEquipment(id)),
            equals(['Sled']),
            reason: id,
          );
        }
        expect(
          _equipmentNames(
            await repo.getExerciseEquipment('exercise-cable-side-bend'),
          ),
          equals(['Cable Machine']),
        );
        expect(
          _equipmentNames(
            await repo.getExerciseEquipment('exercise-hanging-knee-raise'),
          ),
          equals(['Pull-up Bar']),
        );

        final equipment = await repo.getEquipment();
        expect({
          for (final item in equipment) item.name,
        }, equals({for (final item in SeedData.sampleEquipment) item.name}));
        expect(equipment, hasLength(12));
      });

      test('S-19008(b) a link to a missing equipment row is skipped', () async {
        // Mock has no equipment write path — documented as the one allowed
        // divergence between the two stores — so this case is Hive only.
        if (harness.name != 'Hive') return;

        final equipmentBox = Hive.box<Map>('equipment');
        final linksBox = Hive.box<List>('exercise_equipment');
        await linksBox.put('exercise-trap-bar-deadlift', [
          'equipment-barbell',
          'equipment-trap-bar',
        ]);
        await linksBox.put('exercise-sled-push', ['equipment-sled']);
        await equipmentBox.delete('equipment-trap-bar');
        await equipmentBox.delete('equipment-sled');

        expect(
          _equipmentNames(
            await repo.getExerciseEquipment('exercise-trap-bar-deadlift'),
          ),
          equals(['Barbell']),
          reason: 'the link to the missing Trap Bar row is skipped',
        );
        expect(
          _equipmentNames(
            await repo.getExerciseEquipment('exercise-sled-push'),
          ),
          isEmpty,
          reason: 'the only link points at a missing row',
        );
      });
    });
  }
}
