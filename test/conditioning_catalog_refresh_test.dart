// Plan 118, Phase 3 — the conditioning catalog on both implementations.
//
// Scenarios S-19205 (a fresh install ranks the 17 rows 70/80, filters them by
// discipline, muscle and name, and carries the discipline and the equipment),
// S-19206 (a v17 install refreshes: the discipline and the 17 rows land and the
// user's own rows stay untouched) and S-19207 (an exercise whose discipline is
// missing ranks without the discipline points and with them after the refresh)
// of
// `docs/plans/2026-11-05-118-conditioning-catalog-plan/2026-11-05-118-conditioning-catalog-plan.md`.
//
// A v17 device holds neither `discipline-conditioning` nor the 17 rows. The
// refresh delivers the discipline before the exercises (D-19203), so the rows
// rank with the 40 discipline points from the first launch after the update.
// Rows the user owns — a custom with a row's name, a copy, a renamed touched
// row — keep their map, capabilities and links (D-19206, D-18910).
//
// Mock cannot delete an equipment link — the one documented divergence — so
// the "no equipment link for the refreshed Thruster" check is Hive-only, as in
// `test/yoga_catalog_refresh_test.dart`. Both stores must agree, so the shared
// cases run over `harnessFactories` with plain `test()`: a Hive write inside a
// widget test's FakeAsync never completes.

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:omnitrain/core/constants/catalog_version.dart';
import 'package:omnitrain/core/services/bundled_catalog_source.dart';
import 'package:omnitrain/core/services/catalog_refresh_service.dart';
import 'package:omnitrain/core/services/exercise_library_service.dart';
import 'package:omnitrain/core/utils/exercise_helpers.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/mock/seed_data.dart';

import 'helpers/conditioning_catalog_rows.dart';
import 'helpers/repository_harness.dart';

/// The production catalog source, so the refresh runs the same legs it runs on
/// a device.
const BundledCatalogSource _source = BundledCatalogSource();

/// A fixed timestamp: the fixtures take no clock reading.
const int _atMs = 1700000000000;

/// The catalog version a v17 device holds before this plan's bump.
const int _version17 = 17;

/// D-19202's bodyweight capability set, carried by the three customs.
const List<String> _bodyweightCaps = ['reps', 'sets', 'time'];

/// The 17 exercises plan 118 adds, by id.
final List<String> _conditioningIds = [
  for (final row in conditioningCatalogRows) 'exercise-${row.suffix}',
];

/// The fourteen rows without `load` — they score 70 in the Strength picker.
final List<String> _bodyweightIds = [
  for (final row in conditioningCatalogRows)
    if (!row.caps.contains('load')) 'exercise-${row.suffix}',
];

/// The three rows with `load` — they score 80 in the Strength picker.
final List<String> _loadedIds = [
  for (final row in conditioningCatalogRows)
    if (row.caps.contains('load')) 'exercise-${row.suffix}',
];

final Map<String, Exercise> _bundledById = {
  for (final exercise in SeedData.sampleExercises) exercise.id: exercise,
};

/// The bundle's Conditioning discipline, or null when the seed lacks it — so a
/// missing row fails an expectation instead of the file load.
final Discipline? _bundledDiscipline = () {
  for (final discipline in _source.disciplines) {
    if (discipline.id == 'discipline-conditioning') return discipline;
  }
  return null;
}();

const List<ExerciseMuscleLink> _chestPrimary = [
  ExerciseMuscleLink(muscleGroupId: 'muscle-chest', role: MuscleRole.primary),
];

const List<ExerciseMuscleLink> _quadsPrimary = [
  ExerciseMuscleLink(muscleGroupId: 'muscle-quads', role: MuscleRole.primary),
];

const List<ExerciseMuscleLink> _pushUpLinks = [
  ExerciseMuscleLink(muscleGroupId: 'muscle-chest', role: MuscleRole.primary),
  ExerciseMuscleLink(
    muscleGroupId: 'muscle-triceps',
    role: MuscleRole.secondary,
  ),
];

List<String> _ids(List<Exercise> exercises) => [
  for (final exercise in exercises) exercise.id,
];

List<String> _equipmentNames(List<Equipment> equipment) => [
  for (final item in equipment) item.name,
];

/// The relevance score of every ranked row, by exercise id.
Map<String, double> _scoreById(List<Exercise> ranked) => {
  for (final exercise in ranked)
    if (exercise.relevanceScore != null) exercise.id: exercise.relevanceScore!,
};

/// Stage a device that never received [id]: removes the row from the store
/// [box] names (the Hive box name). Mock goes through the D-19108 hook, Hive
/// through the box.
Future<void> _stageMissing(
  RepositoryHarness harness,
  WorkoutRepository repo,
  String box,
  String id,
) async {
  if (harness.name == 'Mock') {
    await (repo as MockWorkoutRepository).deleteReferenceRowForTest(box, id);
  } else if (box == 'metric_effort_kinds') {
    await Hive.box<List>(box).delete(id);
  } else {
    await Hive.box<Map>(box).delete(id);
  }
}

/// The plan's "remove id" shape: the row, its capabilities, its links and — on
/// Hive — its equipment link.
Future<void> _removeExercise(
  RepositoryHarness harness,
  WorkoutRepository repo,
  String id,
) async {
  await repo.deleteExercise(id);
  await repo.setExerciseCapabilities(id, const []);
  await repo.setExerciseMuscleLinks(id, const []);
  if (harness.name == 'Hive') {
    await Hive.box<List>('exercise_equipment').delete(id);
  }
}

/// The user's own row [id], carrying [links] and the bodyweight capabilities.
Future<void> _custom(
  WorkoutRepository repo,
  String id,
  String name, {
  required List<ExerciseMuscleLink> links,
}) async {
  await repo.createExercise(
    Exercise(
      id: id,
      ownerUserId: 'user-1',
      name: name,
      createdAtMs: _atMs,
      updatedAtMs: _atMs,
    ),
  );
  await repo.setExerciseCapabilities(id, _bodyweightCaps);
  await repo.setExerciseMuscleLinks(id, links);
}

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — conditioning catalog, ranking and refresh', () {
      late WorkoutRepository repo;

      setUp(() async => repo = await harness.open());
      tearDown(() async => await harness.close());

      test('S-19205 a fresh install ranks and filters the 17', () async {
        // The three customs of the fixture: U carries a bundled row's name, T1
        // the same name lower-cased with a trailing space, T2 a plural.
        await _custom(repo, 'ex-custom-burpee', 'Burpee', links: _quadsPrimary);
        await _custom(
          repo,
          'ex-custom-burpee-lower',
          'burpee ',
          links: _quadsPrimary,
        );
        await _custom(
          repo,
          'ex-custom-burpees',
          'Burpees',
          links: _chestPrimary,
        );

        // The discipline is there on a new install, under Resistance.
        final discipline = await repo.getDisciplineById(
          'discipline-conditioning',
        );
        expect(discipline, isNotNull, reason: 'the bundle carries the row');
        expect(discipline!.name, equals('Conditioning'));
        expect(discipline.categoryId, equals('category-resistance'));
        expect(discipline.key, equals('conditioning'));

        // D-19203: the fourteen bodyweight rows score 70 and the three loaded
        // rows score 80 in the Strength picker.
        expect(_bodyweightIds, hasLength(14));
        expect(_loadedIds, hasLength(3));

        final strength = await repo.getExercisesRankedForModality(
          'resistance_lifting',
        );
        final scores = _scoreById(strength);
        for (final id in _bodyweightIds) {
          expect(scores[id], equals(70.0), reason: '$id is a 70 in Strength');
        }
        for (final id in _loadedIds) {
          expect(scores[id], equals(80.0), reason: '$id is an 80 in Strength');
        }

        // Every Conditioning row precedes every row outside the recommended
        // band, and a 70 tie breaks by name.
        final position = {
          for (var i = 0; i < strength.length; i++) strength[i].id: i,
        };
        final belowFifty = [
          for (final exercise in strength)
            if ((exercise.relevanceScore ?? 0) < 50.0) exercise.id,
        ];
        expect(belowFifty, isNotEmpty, reason: 'the catalog has other rows');
        final lastConditioning = _conditioningIds
            .map((id) => position[id]!)
            .reduce((a, b) => a > b ? a : b);
        final firstBelowFifty = belowFifty
            .map((id) => position[id]!)
            .reduce((a, b) => a < b ? a : b);
        expect(
          lastConditioning,
          lessThan(firstBelowFifty),
          reason: 'every Conditioning row precedes every row below 50',
        );
        expect(
          position['exercise-bear-crawl']!,
          lessThan(position['exercise-box-jump']!),
          reason: 'the 70 tie breaks alphabetically',
        );

        // A1: the discipline filter lists exactly the 17, and no custom.
        final conditioning = _ids(
          await repo.getExercisesRankedForModality(
            'resistance_lifting',
            disciplineId: 'discipline-conditioning',
          ),
        );
        expect(
          conditioning.toSet(),
          equals(_conditioningIds.toSet()),
          reason: 'the Conditioning filter holds the 17 rows',
        );
        for (final id in [
          'ex-custom-burpee',
          'ex-custom-burpee-lower',
          'ex-custom-burpees',
        ]) {
          expect(
            conditioning,
            isNot(contains(id)),
            reason: '$id belongs to no discipline',
          );
        }

        // D-19203 in the Cardio picker: Burpee 15, Thruster 5.
        final cardio = _scoreById(
          await repo.getExercisesRankedForModality('cardio_endurance'),
        );
        expect(cardio['exercise-burpee'], equals(15.0));
        expect(cardio['exercise-thruster'], equals(5.0));

        // A4: the muscle filters read main muscles only.
        final chest = _ids(
          await repo.searchExercises(muscleGroupIds: ['muscle-chest']),
        );
        for (final id in ['exercise-burpee', 'exercise-plyo-push-up']) {
          expect(chest, contains(id), reason: '$id has a main Chest link');
        }
        expect(
          chest,
          contains('ex-custom-burpees'),
          reason: 'T2 has a main Chest link',
        );

        // The library's Core filter maps to the abs muscle, and the plan names
        // the region; both must hold.
        for (final group in ['muscle-core', 'muscle-abs']) {
          final core = _ids(
            await repo.searchExercises(muscleGroupIds: [group]),
          );
          for (final id in [
            'exercise-mountain-climber',
            'exercise-bear-crawl',
            'exercise-squat-thrust',
            'exercise-medicine-ball-slam',
          ]) {
            expect(
              core.where((each) => each == id),
              hasLength(1),
              reason: '$id matches the $group filter once',
            );
          }
        }

        final calves = _ids(
          await repo.searchExercises(muscleGroupIds: ['muscle-calves']),
        );
        expect(calves, contains('exercise-jumping-jack'));
        for (final id in ['exercise-box-jump', 'exercise-high-knees']) {
          expect(
            calves,
            isNot(contains(id)),
            reason: '$id carries Calves as an assisting muscle only',
          );
        }

        final lats = _ids(
          await repo.searchExercises(muscleGroupIds: ['muscle-lats']),
        );
        expect(lats, contains('exercise-medicine-ball-slam'));

        final shoulders = _ids(
          await repo.searchExercises(muscleGroupIds: ['muscle-shoulders']),
        );
        for (final id in ['exercise-thruster', 'exercise-battle-ropes']) {
          expect(
            shoulders.where((each) => each == id),
            hasLength(1),
            reason: '$id matches the Shoulders filter once',
          );
        }

        // D-18907's search: the bundled row and all three near-twins.
        final search = _ids(await repo.searchExercises(searchText: 'Burpee'));
        expect(
          search.where((each) => each == 'exercise-burpee'),
          hasLength(1),
          reason: 'the bundled Burpee matches once',
        );
        for (final id in [
          'ex-custom-burpee',
          'ex-custom-burpee-lower',
          'ex-custom-burpees',
        ]) {
          expect(search, contains(id), reason: '$id matches "Burpee"');
        }

        // D-19206: the equipment the rows carry.
        expect(
          _equipmentNames(await repo.getExerciseEquipment('exercise-thruster')),
          equals(['Barbell']),
          reason: 'Thruster carries a barbell',
        );
        expect(
          await repo.getExerciseEquipment('exercise-box-jump'),
          isEmpty,
          reason: 'Box Jump carries no equipment row',
        );
      });

      test('S-19206 a v17 install refreshes', () async {
        // Step 1: a v17 device has lost the Conditioning discipline.
        await _stageMissing(
          harness,
          repo,
          'disciplines',
          'discipline-conditioning',
        );
        expect(await repo.getDisciplineById('discipline-conditioning'), isNull);

        // Step 2: and none of the 17 rows.
        for (final id in _conditioningIds) {
          await _removeExercise(harness, repo, id);
          expect(
            await repo.getExerciseById(id),
            isNull,
            reason: 'a v17 device has no $id',
          );
        }

        // Step 3: the user's own rows, recorded as they are.
        await _custom(repo, 'ex-custom-burpee', 'Burpee', links: _quadsPrimary);
        await _custom(
          repo,
          'ex-custom-burpee-lower',
          'burpee ',
          links: _quadsPrimary,
        );
        await _custom(
          repo,
          'ex-custom-burpees',
          'Burpees',
          links: _chestPrimary,
        );
        final customIds = [
          'ex-custom-burpee',
          'ex-custom-burpee-lower',
          'ex-custom-burpees',
        ];
        final customBefore = {
          for (final id in customIds)
            id: (await repo.getExerciseById(id))!.toMap(),
        };
        final customCapsBefore = {
          for (final id in customIds)
            id: await repo.getExerciseCapabilities(id),
        };
        final customLinksBefore = {
          for (final id in customIds) id: await repo.getExerciseMuscleLinks(id),
        };

        // Step 4: a user-edited bundled row, marked touched (D-18910).
        final pushUp = (await repo.getExerciseById('exercise-push-up'))!;
        await repo.updateExercise(pushUp.copyWith(name: 'Plyo Push-Up'));
        await repo.setExerciseMuscleLinks('exercise-push-up', _pushUpLinks);
        await repo.markSeedEntryTouched(
          SeedEntryType.exercise,
          'exercise-push-up',
        );
        expect(
          await repo.isSeedEntryTouched(
            SeedEntryType.exercise,
            'exercise-push-up',
          ),
          isTrue,
          reason: 'the row carries a tombstone',
        );

        // Step 5: a user copy of Kettlebell Swing.
        final copy = await ExerciseLibraryService(
          repo,
        ).copyAsCustom(_bundledById['exercise-kettlebell-swing']!);
        final copyBefore = (await repo.getExerciseById(copy.id))!.toMap();
        final copyCapsBefore = await repo.getExerciseCapabilities(copy.id);
        final copyLinksBefore = await repo.getExerciseMuscleLinks(copy.id);

        // Step 6: the literal version a v17 device holds.
        await repo.setCatalogVersion(_version17);

        expect(
          await CatalogRefreshService(repo, _source).refresh(),
          isTrue,
          reason: 'a v17 device is behind the bundled version',
        );
        expect(await repo.getCatalogVersion(), equals(bundledCatalogVersion));
        expect(
          bundledCatalogVersion,
          greaterThanOrEqualTo(18),
          reason: 'plan 118 ships catalog version 18',
        );

        // The discipline comes back first, so the rows resolve.
        final discipline = await repo.getDisciplineById(
          'discipline-conditioning',
        );
        expect(discipline, isNotNull, reason: 'the refresh restores the row');
        expect(
          _bundledDiscipline,
          isNotNull,
          reason: 'the bundle carries the row',
        );
        expect(discipline!.name, equals(_bundledDiscipline!.name));
        expect(discipline.categoryId, equals(_bundledDiscipline!.categoryId));
        expect(discipline.key, equals(_bundledDiscipline!.key));

        // Every row lands with its bundled name, discipline, capabilities and
        // links.
        for (final id in _conditioningIds) {
          final exercise = await repo.getExerciseById(id);
          expect(exercise, isNotNull, reason: 'the refresh adds $id');
          expect(
            exercise!.name,
            equals(_bundledById[id]!.name),
            reason: 'the bundled name of $id',
          );
          expect(
            exercise.disciplineId,
            equals('discipline-conditioning'),
            reason: '$id belongs to Conditioning',
          );

          final bundledCaps = SeedData.exerciseCapabilityRelationships[id]!;
          final capabilities = await repo.getExerciseCapabilities(id);
          expect(
            capabilities.toSet(),
            equals(bundledCaps.toSet()),
            reason: 'the bundled capabilities of $id',
          );
          expect(capabilities, hasLength(bundledCaps.length));

          final bundledLinks =
              SeedData.exerciseMuscleLinks[id] ?? const <ExerciseMuscleLink>[];
          final links = await repo.getExerciseMuscleLinks(id);
          expect(
            links.toSet(),
            equals(bundledLinks.toSet()),
            reason: 'the bundled links of $id',
          );
          expect(links, hasLength(bundledLinks.length));
        }

        // The touched row keeps the user's name and links.
        final pushUpAfter = (await repo.getExerciseById('exercise-push-up'))!;
        expect(
          pushUpAfter.name,
          equals('Plyo Push-Up'),
          reason: 'a touched row is never rewritten',
        );
        expect(
          (await repo.getExerciseMuscleLinks('exercise-push-up')).toSet(),
          equals(_pushUpLinks.toSet()),
          reason: 'the user tagged this row, so their links win',
        );
        final plyoSearch = _ids(
          await repo.searchExercises(searchText: 'Plyo Push-Up'),
        );
        expect(plyoSearch, contains('exercise-push-up'));
        expect(plyoSearch, contains('exercise-plyo-push-up'));

        // The ranked list now carries the discipline points.
        expect(
          _scoreById(
            await repo.getExercisesRankedForModality('resistance_lifting'),
          )['exercise-burpee'],
          equals(70.0),
          reason: 'the refreshed row ranks as a bodyweight Conditioning move',
        );

        // D-19206: the refresh delivers no equipment link on Hive.
        if (harness.name == 'Hive') {
          expect(
            await repo.getExerciseEquipment('exercise-thruster'),
            isEmpty,
            reason: 'the refresh delivers no equipment',
          );
        }

        // The user's own rows are never rewritten (D-18910, D-19009).
        for (final id in customIds) {
          expect(
            (await repo.getExerciseById(id))!.toMap(),
            equals(customBefore[id]),
            reason: 'the custom row $id is untouched',
          );
          expect(
            await repo.getExerciseCapabilities(id),
            equals(customCapsBefore[id]),
            reason: 'the capabilities of $id are untouched',
          );
          expect(
            await repo.getExerciseMuscleLinks(id),
            equals(customLinksBefore[id]),
            reason: 'the links of $id are untouched',
          );
        }
        expect(
          (await repo.getExerciseById(copy.id))!.toMap(),
          equals(copyBefore),
          reason: 'the user copy is untouched',
        );
        expect(
          await repo.getExerciseCapabilities(copy.id),
          equals(copyCapsBefore),
        );
        expect(
          await repo.getExerciseMuscleLinks(copy.id),
          equals(copyLinksBefore),
        );

        // A second run is a no-op and changes none of the rows above.
        final watchedIds = [
          ...customIds,
          copy.id,
          'exercise-push-up',
          ..._conditioningIds,
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
        for (final entry in linksAfterFirst.entries) {
          expect(
            await repo.getExerciseMuscleLinks(entry.key),
            equals(entry.value),
            reason: '${entry.key} is unchanged by the second run',
          );
        }
        for (final id in customIds) {
          expect(
            (await repo.getExerciseById(id))!.toMap(),
            equals(customBefore[id]),
            reason: 'the custom row $id is unchanged by the second run',
          );
          expect(
            await repo.getExerciseCapabilities(id),
            equals(customCapsBefore[id]),
            reason: 'the capabilities of $id are unchanged by the second run',
          );
        }
        expect(
          (await repo.getExerciseById(copy.id))!.toMap(),
          equals(copyBefore),
          reason: 'the user copy is unchanged by the second run',
        );
        expect(
          (await repo.getExerciseById('exercise-push-up'))!.name,
          equals('Plyo Push-Up'),
          reason: 'the renamed touched row keeps its name after the second run',
        );
      });

      test('S-19207 an exercise whose discipline is missing', () async {
        // A fresh install that never received the discipline row: the 17 rows
        // stay and still point at it.
        await _stageMissing(
          harness,
          repo,
          'disciplines',
          'discipline-conditioning',
        );
        expect(await repo.getDisciplineById('discipline-conditioning'), isNull);
        final burpee = (await repo.getExerciseById('exercise-burpee'))!;
        expect(burpee.disciplineId, equals('discipline-conditioning'));
        await repo.setCatalogVersion(_version17);

        // Without the stored row the ranking cannot resolve the category, so
        // the two rows lose their 40 discipline points and stay under the
        // recommended threshold — and neither throws.
        final before = _scoreById(
          await repo.getExercisesRankedForModality('resistance_lifting'),
        );
        expect(before['exercise-burpee'], equals(30.0));
        expect(before['exercise-thruster'], equals(40.0));
        expect(before['exercise-burpee']!, lessThan(50.0));
        expect(before['exercise-thruster']!, lessThan(50.0));

        // The discipline filter still lists the 17: it reads the exercise's id.
        expect(
          _ids(
            await repo.searchExercises(disciplineId: 'discipline-conditioning'),
          ).toSet(),
          equals(_conditioningIds.toSet()),
          reason: 'the filter matches on the stored discipline id',
        );

        expect(
          await CatalogRefreshService(repo, _source).refresh(),
          isTrue,
          reason: 'a v17 device is behind the bundled version',
        );
        expect(
          (await repo.getDisciplineById('discipline-conditioning'))!.name,
          equals('Conditioning'),
          reason: 'the refresh restores the discipline row',
        );
        final after = _scoreById(
          await repo.getExercisesRankedForModality('resistance_lifting'),
        );
        expect(after['exercise-burpee'], equals(70.0));
        expect(after['exercise-thruster'], equals(80.0));
      });
    });
  }
}
