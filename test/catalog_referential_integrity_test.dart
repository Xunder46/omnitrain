import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/catalog_version.dart';
import 'package:omnitrain/core/services/bundled_catalog_source.dart';
import 'package:omnitrain/core/services/catalog_refresh_service.dart';
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

      for (final entry in SeedData.exerciseMuscleGroupRelationships.entries) {
        for (final groupId in entry.value) {
          if (!muscleGroupIds.contains(groupId)) {
            dangling.add('${entry.key} -> $groupId');
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

      check('muscleGroups', SeedData.exerciseMuscleGroupRelationships.keys);
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

    test('R-004: no duplicate muscle group ids', () {
      final ids = SeedData.sampleMuscleGroups.map((g) => g.id).toList();
      expect(ids.length, muscleGroupIds.length, reason: 'duplicate ids: $ids');
    });
  });

  group('Bundled catalog — muscle group refresh', () {
    test('R-005: groups added after first launch still reach the device', () async {
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

      await CatalogRefreshService(repo, const BundledCatalogSource()).refresh();

      final after = (await repo.getMuscleGroups()).map((g) => g.id).toSet();
      for (final id in addedInV9) {
        expect(
          after,
          contains(id),
          reason: '$id must survive / be restored by the catalog refresh',
        );
      }

      // Every mapping must still resolve after the refresh.
      for (final entry in SeedData.exerciseMuscleGroupRelationships.entries) {
        for (final groupId in entry.value) {
          expect(
            after,
            contains(groupId),
            reason: '${entry.key} points at $groupId, absent post-refresh',
          );
        }
      }
    });
  });
}
