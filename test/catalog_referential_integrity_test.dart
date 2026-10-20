import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/catalog_version.dart';
import 'package:omnitrain/core/services/bundled_catalog_source.dart';
import 'package:omnitrain/core/services/catalog_refresh_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/models/muscle_taxonomy.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/mock/seed_data.dart';

/// Referential integrity of the bundled catalog.
///
/// These guard the failure mode that let `muscle-arms` and `muscle-legs` sit
/// in the shipped catalog as dangling references: an exercise pointing at a
/// muscle group that was never defined. Nothing crashed — the group simply
/// resolved to nothing and the exercise quietly vanished from any
/// muscle-based query. A rule a machine checks is the only thing that catches
/// that; reading the seed file does not.
void main() {
  final muscleGroupIds = SeedData.sampleMuscleGroups.map((g) => g.id).toSet();
  final exerciseIds = SeedData.sampleExercises.map((e) => e.id).toSet();
  final equipmentIds = SeedData.sampleEquipment.map((e) => e.id).toSet();

  group('Bundled catalog — referential integrity', () {
    test('R-001: every referenced muscle group is defined', () {
      final dangling = <String>{};

      for (final entry in SeedData.exerciseMuscleLinks.entries) {
        for (final link in entry.value) {
          if (!muscleGroupIds.contains(link.muscleGroupId)) {
            dangling.add('${entry.key} -> ${link.muscleGroupId}');
          }
        }
      }

      expect(
        dangling,
        isEmpty,
        reason:
            'these exercises point at muscle groups that do not exist in '
            'SeedData.sampleMuscleGroups: ${dangling.join(", ")}',
      );
    });

    test('R-002: every referenced equipment id is defined', () {
      final dangling = <String>{};

      for (final entry in SeedData.exerciseEquipmentRelationships.entries) {
        for (final equipId in entry.value) {
          if (!equipmentIds.contains(equipId)) {
            dangling.add('${entry.key} -> $equipId');
          }
        }
      }

      expect(
        dangling,
        isEmpty,
        reason:
            'these exercises point at equipment that does not exist in '
            'SeedData.sampleEquipment: ${dangling.join(", ")}',
      );
    });

    test('R-003: relationship maps are keyed by real exercises', () {
      final unknown = <String>{};

      void check(String label, Iterable<String> keys) {
        for (final id in keys) {
          if (!exerciseIds.contains(id)) unknown.add('$label: $id');
        }
      }

      check('muscleGroups', SeedData.exerciseMuscleLinks.keys);
      check('equipment', SeedData.exerciseEquipmentRelationships.keys);
      check('capabilities', SeedData.exerciseCapabilityRelationships.keys);

      expect(
        unknown,
        isEmpty,
        reason:
            'these relationship entries are keyed by exercise ids that are '
            'not in the catalog: ${unknown.join(", ")}',
      );
    });

    test('R-004: muscle groups are the taxonomy entries, with no duplicate ids', () {
      final ids = SeedData.sampleMuscleGroups.map((g) => g.id).toList();
      expect(ids.length, muscleGroupIds.length, reason: 'duplicate ids: $ids');
      expect(
        ids,
        equals(MuscleTaxonomy.entries.map((entry) => entry.id).toList()),
        reason:
            'SeedData.sampleMuscleGroups must carry exactly the 23 taxonomy '
            'ids, in taxonomy order',
      );
    });
  });

  // Plan 33 (S-3): `SeedData.exerciseMuscleLinks` is the tagging the bundled
  // catalog ships, and R-001/R-003/R-004/R-005 above read it too.
  group('Bundled catalog — muscle link map (S-3)', () {
    /// The ids one role holds on [exerciseId].
    Set<String> rolesIn(String exerciseId, MuscleRole role) => {
      for (final link in SeedData.exerciseMuscleLinks[exerciseId]!)
        if (link.role == role) link.muscleGroupId,
    };

    test('S-3: the map is keyed by real exercises', () {
      final unknown = {
        for (final key in SeedData.exerciseMuscleLinks.keys)
          if (!exerciseIds.contains(key)) key,
      };

      expect(
        unknown,
        isEmpty,
        reason:
            'these muscle-link entries are keyed by exercise ids that are '
            'not in the catalog: ${unknown.join(", ")}',
      );
    });

    test('S-3: every linked muscle group is defined', () {
      final dangling = <String>{};

      for (final entry in SeedData.exerciseMuscleLinks.entries) {
        for (final link in entry.value) {
          if (!muscleGroupIds.contains(link.muscleGroupId)) {
            dangling.add('${entry.key} -> ${link.muscleGroupId}');
          }
        }
      }

      expect(
        dangling,
        isEmpty,
        reason:
            'these exercises point at muscle groups that do not exist in '
            'SeedData.sampleMuscleGroups: ${dangling.join(", ")}',
      );
    });

    test('S-3: every entry carries at least one primary link', () {
      final withoutPrimary = {
        for (final entry in SeedData.exerciseMuscleLinks.entries)
          if (!entry.value.any((link) => link.role == MuscleRole.primary))
            entry.key,
      };

      expect(
        withoutPrimary,
        isEmpty,
        reason:
            'a filter matches on primary links only, so these exercises '
            'would be unreachable by muscle: ${withoutPrimary.join(", ")}',
      );
    });

    test('S-3: no id appears twice and none carries both roles', () {
      final repeated = <String>{};
      final bothRoles = <String>{};

      for (final entry in SeedData.exerciseMuscleLinks.entries) {
        final ids = [for (final link in entry.value) link.muscleGroupId];
        if (ids.toSet().length != ids.length) repeated.add(entry.key);

        final primary = rolesIn(entry.key, MuscleRole.primary);
        final secondary = rolesIn(entry.key, MuscleRole.secondary);
        if (primary.intersection(secondary).isNotEmpty) {
          bothRoles.add(entry.key);
        }
      }

      expect(repeated, isEmpty, reason: 'duplicate ids in ${repeated.join(", ")}');
      expect(
        bothRoles,
        isEmpty,
        reason: 'an id in both roles on ${bothRoles.join(", ")}',
      );
    });

    test('S-3: no entry links a region next to one of its own muscles', () {
      final offending = <String>{};

      for (final entry in SeedData.exerciseMuscleLinks.entries) {
        final linked = {for (final link in entry.value) link.muscleGroupId};
        for (final id in linked) {
          if (MuscleTaxonomy.isRegion(id) &&
              MuscleTaxonomy.musclesOf(id).any(linked.contains)) {
            offending.add('${entry.key} -> $id');
          }
        }
      }

      expect(
        offending,
        isEmpty,
        reason:
            'a region is redundant next to one of its own muscles: '
            '${offending.join(", ")}',
      );
    });

    test('S-3: the map holds one entry per tagged exercise', () {
      expect(SeedData.exerciseMuscleLinks, hasLength(178));
    });

    test('S-3: only the twelve region-tagged exercises carry a region', () {
      final regionTagged = {
        for (final entry in SeedData.exerciseMuscleLinks.entries)
          if (entry.value.any(
            (link) => MuscleTaxonomy.isRegion(link.muscleGroupId),
          ))
            entry.key,
      };

      expect(regionTagged, {
        'exercise-tennis-match',
        'exercise-tennis-drill',
        'exercise-volleyball-match',
        'exercise-volleyball-drill',
        'exercise-badminton-match',
        'exercise-table-tennis-match',
        'exercise-cricket-match',
        'exercise-ice-hockey-match',
        'exercise-baseball-game',
        'exercise-american-football-game',
        'exercise-rugby-match',
        'exercise-lacrosse-game',
      });
    });

    test('S-3: the approved rows, each role compared as a set', () {
      expect(rolesIn('exercise-bench-press', MuscleRole.primary), {
        'muscle-chest',
      });
      expect(rolesIn('exercise-bench-press', MuscleRole.secondary), {
        'muscle-triceps',
        'muscle-front-delts',
      });

      expect(rolesIn('exercise-barbell-squat', MuscleRole.primary), {
        'muscle-quads',
      });
      expect(rolesIn('exercise-barbell-squat', MuscleRole.secondary), {
        'muscle-glutes',
        'muscle-hamstrings',
      });

      expect(rolesIn('exercise-tennis-match', MuscleRole.primary), {
        'muscle-legs',
        'muscle-shoulders',
        'muscle-core',
      });
      expect(rolesIn('exercise-tennis-match', MuscleRole.secondary), isEmpty);

      expect(rolesIn('exercise-deadlift', MuscleRole.primary), {
        'muscle-glutes',
        'muscle-hamstrings',
        'muscle-lower-back',
      });
    });
  });

  group('Bundled catalog — muscle group refresh', () {
    test(
      'R-005: groups added after first launch still reach the device',
      () async {
        final repo = MockWorkoutRepository();
        await repo.initialize();

        // Simulate a device seeded before the taxonomy was completed: drop the
        // groups added in catalog version 9 and rewind the stored version.
        const addedInV9 = [
          'muscle-arms',
          'muscle-legs',
          'muscle-traps',
          'muscle-forearms',
          'muscle-adductors',
          'muscle-calves',
          'muscle-neck',
          // Plan 33: the seven groups the hierarchy adds.
          'muscle-lats',
          'muscle-lower-back',
          'muscle-front-delts',
          'muscle-side-delts',
          'muscle-rear-delts',
          'muscle-abs',
          'muscle-obliques',
        ];
        await repo.setCatalogVersion(bundledCatalogVersion - 1);

        final before = (await repo.getMuscleGroups()).map((g) => g.id).toSet();
        expect(
          before,
          containsAll(addedInV9),
          reason:
              'fixture assumption: a freshly seeded repo already carries the '
              'full group list, so the refresh below is what must re-supply '
              'them on an older device',
        );

        await CatalogRefreshService(
          repo,
          const BundledCatalogSource(),
        ).refresh();

        final after = (await repo.getMuscleGroups()).map((g) => g.id).toSet();
        for (final id in addedInV9) {
          expect(
            after,
            contains(id),
            reason: '$id must survive / be restored by the catalog refresh',
          );
        }

        // The rename travels with the same refresh.
        final byId = {
          for (final group in await repo.getMuscleGroups()) group.id: group,
        };
        expect(
          byId['muscle-traps']!.name,
          equals('Traps'),
          reason: 'the refresh renames Trapezius to Traps',
        );

        // Every muscle carries its taxonomy parent after the refresh.
        for (final entry in MuscleTaxonomy.entries) {
          if (entry.parentId == null) continue;
          expect(
            byId[entry.id]!.parentId,
            equals(entry.parentId),
            reason: '${entry.id} must carry its taxonomy parent',
          );
        }

        // Every mapping must still resolve after the refresh.
        for (final entry in SeedData.exerciseMuscleLinks.entries) {
          for (final link in entry.value) {
            expect(
              after,
              contains(link.muscleGroupId),
              reason:
                  '${entry.key} points at ${link.muscleGroupId}, '
                  'absent post-refresh',
            );
          }
        }
      },
    );
  });
}
