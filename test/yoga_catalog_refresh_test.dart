// Plan 119, Phase 3A — the yoga catalog refresh, on both implementations.
//
// Scenarios S-19304 (a version-P install refreshes: the 22 poses, the Yoga
// discipline and the two discipline moves land), S-19305 (a renamed touched
// row and near-twins keep their own) and S-19307 (equipment on a new install)
// of
// `docs/plans/2026-11-05-119-yoga-catalog-plan/2026-11-05-119-yoga-catalog-plan.md`.
//
// A version-P device has none of the 22 poses and has lost the Yoga discipline.
// The refresh must add the 22 rows — with their capabilities and muscle links —
// deliver the discipline, and move Pigeon Pose and Child's Pose from Stretching
// to Yoga (D-19312). Rows the user owns — a custom with a pose's name, a user
// copy, an edited pose with its tombstone, a renamed touched row — stay exactly
// as they were. The equipment links exist on a new install only (D-19304).
// Mock cannot delete an equipment link — the one documented divergence — so the
// "no equipment link after the refresh" check is Hive-only, as in
// `test/strength_catalog_v15_refresh_test.dart`. Both stores must agree, so the
// shared cases run over `harnessFactories` with plain `test()`: a Hive write
// inside a widget test's FakeAsync never completes.

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

import 'helpers/repository_harness.dart';
import 'helpers/yoga_catalog_rows.dart';

/// The production catalog source, so the refresh runs the same legs it runs on
/// a device.
const BundledCatalogSource _source = BundledCatalogSource();

/// A fixed timestamp: the fixtures take no clock reading.
const int _atMs = 1700000000000;

/// D-19307's P: the catalog version a device holds before this plan's bump.
const int _versionP = 16;

/// The 22 exercises plan 119 adds, by id.
final List<String> _yogaIds = [
  for (final row in yogaCatalogRows) 'exercise-${row.suffix}',
];

final Map<String, Exercise> _bundledById = {
  for (final exercise in SeedData.sampleExercises) exercise.id: exercise,
};

const List<ExerciseMuscleLink> _hamstrings = [
  ExerciseMuscleLink(muscleGroupId: 'muscle-hamstrings', role: MuscleRole.primary),
];

const List<ExerciseMuscleLink> _quads = [
  ExerciseMuscleLink(muscleGroupId: 'muscle-quads', role: MuscleRole.primary),
];

List<String> _ids(List<Exercise> exercises) => [
  for (final exercise in exercises) exercise.id,
];

List<String> _equipmentNames(List<Equipment> equipment) => [
  for (final item in equipment) item.name,
];

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

/// The user's own row [id], carrying [links].
Future<void> _custom(
  WorkoutRepository repo,
  String id,
  String name, {
  String? disciplineId,
  required List<ExerciseMuscleLink> links,
}) async {
  await repo.createExercise(
    Exercise(
      id: id,
      ownerUserId: 'user-1',
      name: name,
      disciplineId: disciplineId,
      createdAtMs: _atMs,
      updatedAtMs: _atMs,
    ),
  );
  await repo.setExerciseMuscleLinks(id, links);
}

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — yoga catalog refresh from a version-P install', () {
      late WorkoutRepository repo;

      setUp(() async => repo = await harness.open());
      tearDown(() async => await harness.close());

      test('S-19304 a version-P install refreshes', () async {
        // Step 1: a version-P device carries none of the 22 poses.
        for (final id in _yogaIds) {
          await _removeExercise(harness, repo, id);
          expect(
            await repo.getExerciseById(id),
            isNull,
            reason: 'a version-P device has no $id',
          );
        }

        // Step 2: nor the Yoga discipline.
        await _stageMissing(harness, repo, 'disciplines', 'discipline-yoga');
        expect(await repo.getDisciplineById('discipline-yoga'), isNull);

        // Step 3: the user's own "Downward-Facing Dog", under Yoga.
        await _custom(
          repo,
          'ex-custom-downward-facing-dog',
          'Downward-Facing Dog',
          disciplineId: 'discipline-yoga',
          links: const [
            ExerciseMuscleLink(
              muscleGroupId: 'muscle-hamstrings',
              role: MuscleRole.primary,
            ),
            ExerciseMuscleLink(
              muscleGroupId: 'muscle-calves',
              role: MuscleRole.secondary,
            ),
          ],
        );
        final customBefore = (await repo.getExerciseById(
          'ex-custom-downward-facing-dog',
        ))!.toMap();
        final customLinksBefore = await repo.getExerciseMuscleLinks(
          'ex-custom-downward-facing-dog',
        );

        // Step 4: a user copy of Pigeon Pose.
        final copy = await ExerciseLibraryService(repo).copyAsCustom(
          _bundledById['exercise-pigeon-pose']!,
        );
        final copyBefore = (await repo.getExerciseById(copy.id))!.toMap();
        final copyLinksBefore = await repo.getExerciseMuscleLinks(copy.id);

        // Step 5: Child's Pose edited while it was a Stretching row, and marked
        // touched — the tombstone keeps the user's row (D-18910).
        final childs = (await repo.getExerciseById('exercise-childs-pose'))!;
        await repo.updateExercise(
          childs.copyWith(
            description: 'My own cue',
            disciplineId: 'discipline-stretching',
          ),
        );
        await repo.markSeedEntryTouched(
          SeedEntryType.exercise,
          'exercise-childs-pose',
        );

        // Step 6: Pigeon Pose the user never touched, and never marked.
        expect(
          await repo.isSeedEntryTouched(
            SeedEntryType.exercise,
            'exercise-pigeon-pose',
          ),
          isFalse,
          reason: 'Pigeon Pose carries no tombstone',
        );
        final pigeonBefore = (await repo.getExerciseById(
          'exercise-pigeon-pose',
        ))!;
        final pigeonCapsBefore = await repo.getExerciseCapabilities(
          'exercise-pigeon-pose',
        );
        final pigeonLinksBefore = await repo.getExerciseMuscleLinks(
          'exercise-pigeon-pose',
        );
        final pigeonEquipmentBefore = _equipmentNames(
          await repo.getExerciseEquipment('exercise-pigeon-pose'),
        );

        // Step 7: the literal version a version-P device holds.
        await repo.setCatalogVersion(_versionP);

        expect(
          await CatalogRefreshService(repo, _source).refresh(),
          isTrue,
          reason: 'a version-P device is behind the bundled version',
        );

        expect(await repo.getCatalogVersion(), equals(bundledCatalogVersion));
        expect(
          bundledCatalogVersion,
          greaterThan(_versionP),
          reason: 'plan 119 ships catalog version P + 1',
        );

        // The discipline comes back first, so the rows resolve.
        final discipline = await repo.getDisciplineById('discipline-yoga');
        expect(discipline, isNotNull, reason: 'the refresh restores the row');
        expect(discipline!.name, equals('Yoga'));
        expect(discipline.categoryId, equals('category-isometric'));

        // Every pose lands with its bundled name, discipline, capabilities and
        // links.
        for (final id in _yogaIds) {
          final exercise = await repo.getExerciseById(id);
          expect(exercise, isNotNull, reason: 'the refresh adds $id');
          expect(
            exercise!.name,
            equals(_bundledById[id]!.name),
            reason: 'the bundled name of $id',
          );
          expect(
            exercise.disciplineId,
            equals('discipline-yoga'),
            reason: '$id belongs to Yoga',
          );

          final bundledCapabilities =
              SeedData.exerciseCapabilityRelationships[id]!;
          final capabilities = await repo.getExerciseCapabilities(id);
          expect(
            capabilities.toSet(),
            equals(bundledCapabilities.toSet()),
            reason: 'the bundled capabilities of $id',
          );
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

        // D-19312: the untouched Pigeon Pose carries the bundled discipline and
        // changes in no other field.
        final pigeon = (await repo.getExerciseById('exercise-pigeon-pose'))!;
        expect(pigeon.name, equals(pigeonBefore.name));
        expect(pigeon.description, equals(pigeonBefore.description));
        expect(pigeon.movementPattern, equals(pigeonBefore.movementPattern));
        expect(pigeon.ownerUserId, equals(pigeonBefore.ownerUserId));
        expect(pigeon.modality, equals(pigeonBefore.modality));
        expect(
          pigeon.disciplineId,
          equals('discipline-yoga'),
          reason: 'the refresh moves Pigeon Pose to Yoga',
        );
        expect(
          (await repo.getExerciseCapabilities('exercise-pigeon-pose')).toSet(),
          equals(pigeonCapsBefore.toSet()),
        );
        expect(
          (await repo.getExerciseMuscleLinks('exercise-pigeon-pose')).toSet(),
          equals(pigeonLinksBefore.toSet()),
        );
        expect(
          _equipmentNames(
            await repo.getExerciseEquipment('exercise-pigeon-pose'),
          ),
          equals(pigeonEquipmentBefore),
        );

        // The user's own rows are never rewritten (D-18910, D-19009).
        expect(
          (await repo.getExerciseById('ex-custom-downward-facing-dog'))!.toMap(),
          equals(customBefore),
          reason: 'the custom row is untouched',
        );
        expect(
          await repo.getExerciseMuscleLinks('ex-custom-downward-facing-dog'),
          equals(customLinksBefore),
        );
        expect(
          (await repo.getExerciseById(copy.id))!.toMap(),
          equals(copyBefore),
          reason: 'the user copy is untouched',
        );
        expect(
          await repo.getExerciseMuscleLinks(copy.id),
          equals(copyLinksBefore),
        );

        final search = _ids(
          await repo.searchExercises(searchText: 'Downward-Facing Dog'),
        );
        expect(search, contains('ex-custom-downward-facing-dog'));
        expect(search, contains('exercise-downward-facing-dog'));

        // D-19312: the Yoga filter holds the 22 poses, the moved Pigeon Pose,
        // the custom and the copy. Child's Pose is absent: its tombstone keeps
        // the user's row, whose stored discipline is Stretching.
        final yoga = _ids(
          await repo.searchExercises(disciplineId: 'discipline-yoga'),
        );
        expect(
          yoga.toSet(),
          equals({
            ..._yogaIds,
            'exercise-pigeon-pose',
            'ex-custom-downward-facing-dog',
            copy.id,
          }),
          reason: 'the Yoga filter after the refresh',
        );

        final childsAfter = (await repo.getExerciseById(
          'exercise-childs-pose',
        ))!;
        expect(
          childsAfter.description,
          equals('My own cue'),
          reason: 'a touched row is never rewritten',
        );
        expect(
          childsAfter.disciplineId,
          equals('discipline-stretching'),
          reason: 'the user edit that predates the move keeps its discipline',
        );

        final stretching = _ids(
          await repo.searchExercises(disciplineId: 'discipline-stretching'),
        );
        expect(
          stretching,
          isNot(contains('exercise-pigeon-pose')),
          reason: 'Pigeon Pose left Stretching',
        );
        for (final id in _yogaIds) {
          expect(stretching, isNot(contains(id)), reason: '$id is not a stretch');
        }

        if (harness.name == 'Hive') {
          // D-19304: the refresh delivers no equipment link.
          for (final id in ['exercise-tree-pose', 'exercise-savasana']) {
            expect(
              await repo.getExerciseEquipment(id),
              isEmpty,
              reason: 'the refresh delivers no equipment for $id',
            );
          }
        }

        // A second run is a no-op and changes none of the rows above.
        final watchedIds = [
          'ex-custom-downward-facing-dog',
          copy.id,
          'exercise-pigeon-pose',
          ..._yogaIds,
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
      });

      test(
        'S-19305 a renamed touched row and near-twins keep their own',
        () async {
          // Step 1: the version-P device has no Low Lunge row.
          await _removeExercise(harness, repo, 'exercise-low-lunge');

          // Step 2: the user renamed the existing hip-flexor stretch to the new
          // row's name, and the tombstone keeps their row as it is.
          final hipFlexor = (await repo.getExerciseById(
            'exercise-kneeling-hip-flexor-stretch',
          ))!;
          await repo.updateExercise(hipFlexor.copyWith(name: 'Low Lunge'));
          await repo.setExerciseMuscleLinks(
            'exercise-kneeling-hip-flexor-stretch',
            _quads,
          );
          await repo.markSeedEntryTouched(
            SeedEntryType.exercise,
            'exercise-kneeling-hip-flexor-stretch',
          );

          // Step 3: two custom near-twins of the new name.
          await _custom(
            repo,
            'ex-custom-downward-dog',
            'Downward Dog',
            links: _hamstrings,
          );
          await _custom(
            repo,
            'ex-custom-downward-facing-dog-lower',
            'downward-facing dog ',
            links: _hamstrings,
          );

          // Step 4: the literal version a version-P device holds.
          await repo.setCatalogVersion(_versionP);

          expect(
            await CatalogRefreshService(repo, _source).refresh(),
            isTrue,
            reason: 'a version-P device is behind the bundled version',
          );

          final kept = await repo.getExerciseById(
            'exercise-kneeling-hip-flexor-stretch',
          );
          expect(kept, isNotNull);
          expect(
            kept!.name,
            equals('Low Lunge'),
            reason: 'the user renamed this row, so their name wins',
          );
          expect(
            kept.disciplineId,
            equals('discipline-stretching'),
            reason: 'the user edited this row, so their discipline wins',
          );
          expect(
            await repo.getExerciseMuscleLinks(
              'exercise-kneeling-hip-flexor-stretch',
            ),
            equals(_quads),
            reason: 'the user tagged this row, so their links win',
          );

          final added = await repo.getExerciseById('exercise-low-lunge');
          expect(
            added,
            isNotNull,
            reason: 'the refresh adds the new row beside the renamed one',
          );
          expect(added!.name, equals('Low Lunge'));
          expect(
            added.disciplineId,
            equals('discipline-yoga'),
            reason: 'the new row is a pose',
          );
          final addedLinks = await repo.getExerciseMuscleLinks(
            'exercise-low-lunge',
          );
          final bundledLinks = SeedData.exerciseMuscleLinks['exercise-low-lunge']!;
          expect(addedLinks.toSet(), equals(bundledLinks.toSet()));
          expect(addedLinks, hasLength(bundledLinks.length));

          final search = _ids(
            await repo.searchExercises(searchText: 'Low Lunge'),
          );
          expect(search, contains('exercise-kneeling-hip-flexor-stretch'));
          expect(search, contains('exercise-low-lunge'));

          for (final (id, name) in [
            ('ex-custom-downward-dog', 'Downward Dog'),
            ('ex-custom-downward-facing-dog-lower', 'downward-facing dog '),
          ]) {
            final row = await repo.getExerciseById(id);
            expect(row, isNotNull, reason: '$id survives');
            expect(row!.name, equals(name), reason: 'the user owns $id');
            expect(
              await repo.getExerciseMuscleLinks(id),
              equals(_hamstrings),
              reason: 'the user tagged $id',
            );
          }

          final hamstrings = _ids(
            await repo.searchExercises(muscleGroupIds: ['muscle-hamstrings']),
          );
          for (final id in [
            'exercise-downward-facing-dog',
            'ex-custom-downward-dog',
            'ex-custom-downward-facing-dog-lower',
          ]) {
            expect(
              hamstrings.where((each) => each == id),
              hasLength(1),
              reason: '$id matches once',
            );
          }
        },
      );

      test('S-19307 equipment on a new install', () async {
        for (final id in [
          'exercise-downward-facing-dog',
          'exercise-savasana',
          'exercise-bridge-pose',
        ]) {
          expect(
            _equipmentNames(await repo.getExerciseEquipment(id)),
            equals(['Body Weight']),
            reason: '$id carries the bundled equipment link',
          );
        }
        expect(
          await repo.getEquipment(),
          hasLength(12),
          reason: 'no equipment row is added',
        );
      });
    });
  }
}
