// Plan 137, Phase P2b — the one-time repair of shipped food categories,
// scenarios S-13706..S-13709 of
// `docs/plans/2026-11-09-137-shipped-food-categories-locked-plan/2026-11-09-137-shipped-food-categories-locked-plan.md`.
//
// Step `restoreShippedFoodGroups` (version 19, D-5) un-archives every
// shipped category (D-6) and puts an uncategorized library copy back under
// the shipped category its catalog row names (D-7); a second run writes
// nothing and a failing write leaves `data_version` at 18 for the retry
// (D-8). Both stores must agree, so the shared cases run over
// `harnessFactories` with plain `test()`: a Hive write inside a widget
// test's FakeAsync never completes.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/data_version.dart';
import 'package:omnitrain/core/services/data_migration_service.dart';
import 'package:omnitrain/core/services/shipped_food_groups_repair.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/hive_workout_repository.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/food_library_state.dart';

import 'helpers/repository_harness.dart';

/// A fixed timestamp: the fixtures take no clock reading.
const int _atMs = 1700000000000;

const String _stepName = 'restoreShippedFoodGroups';

/// Throws on every `updateFoodGroup` while [failing], then behaves normally.
class _FailingFoodGroupUpdateRepo extends MockWorkoutRepository {
  bool failing = true;

  @override
  Future<void> updateFoodGroup(FoodGroup group) async {
    if (failing) throw StateError('simulated');
    await super.updateFoodGroup(group);
  }
}

/// The ordered migration steps of whichever store [repo] is.
List<DataMigrationStep> _steps(WorkoutRepository repo) =>
    repo is MockWorkoutRepository
    ? repo.dataMigrationStepsForTest()
    : (repo as HiveWorkoutRepository).dataMigrationStepsForTest();

/// The repair step itself, or a StateError that says plainly what is
/// missing — so a RED run reports the right reason, not a bare "No element".
DataMigrationStep _repairStep(WorkoutRepository repo) {
  final steps = _steps(repo);
  final matches = steps.where((step) => step.name == _stepName).toList();
  if (matches.length != 1) {
    throw StateError(
      'plan 137 Phase P2b not implemented: the migration step '
      '"$_stepName" does not exist yet — the step list holds '
      '[${steps.map((step) => '${step.targetVersion}:${step.name}').join(', ')}]',
    );
  }
  return matches.single;
}

/// Runs the repair step alone, as the migration service would.
Future<void> _runStep(WorkoutRepository repo) => _repairStep(repo).run();

Food _catalogFood(String id, String name, {required String? groupId}) => Food(
  id: id,
  name: name,
  groupId: groupId,
  unitType: FoodUnitType.grams,
  referenceAmount: 100,
  referenceLabel: 'g',
  isCatalog: true,
  protein: 3,
  carbs: 5,
  fat: 2,
  createdAtMs: _atMs,
  updatedAtMs: _atMs,
);

Food _libraryFood(
  String id,
  String name, {
  String? groupId,
  String? catalogId,
}) => Food(
  id: id,
  name: name,
  groupId: groupId,
  catalogId: catalogId,
  unitType: FoodUnitType.grams,
  referenceAmount: 100,
  referenceLabel: 'g',
  protein: 4,
  carbs: 6,
  fat: 1,
  createdAtMs: _atMs,
  updatedAtMs: _atMs,
);

/// Every food's and group's `updatedAtMs`, keyed by id.
Future<Map<String, int>> _foodStamps(WorkoutRepository repo) async => {
  for (final food in await repo.getFoods(includeArchived: true))
    food.id: food.updatedAtMs,
};

Future<Map<String, int>> _groupStamps(WorkoutRepository repo) async => {
  for (final group in await repo.getFoodGroups(includeArchived: true))
    group.id: group.updatedAtMs,
};

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — shipped food groups repair (plan 137)', () {
      late WorkoutRepository repo;

      setUp(() async {
        repo = await harness.open();
      });
      tearDown(() => harness.close());

      test(
        'S-13706 an archived shipped category is restored, a custom one stays '
        'archived',
        () async {
          await repo.archiveFoodGroup('food-group-dairy');
          final archived = (await repo.getFoodGroupById('food-group-dairy'))!;
          expect(archived.isArchived, isTrue, reason: 'fixture premise');

          const oldId = 'group-137-old';
          await repo.createFoodGroup(
            const FoodGroup(
              id: oldId,
              name: 'Old',
              color: '#654321',
              createdAtMs: _atMs,
              updatedAtMs: _atMs,
            ),
          );
          await repo.archiveFoodGroup(oldId);

          await _runStep(repo);

          final dairy = (await repo.getFoodGroupById('food-group-dairy'))!;
          expect(dairy.isArchived, isFalse);
          expect(dairy.name, 'Dairy');
          expect(dairy.color, archived.color);
          expect(dairy.createdAtMs, archived.createdAtMs);
          expect(
            (await repo.getFoodGroupById(oldId))!.isArchived,
            isTrue,
            reason: 'an archived custom group is not a shipped category',
          );

          final state = FoodLibraryState(repo);
          await state.loadFoodGroups();
          final activeIds = state.activeFoodGroups.map((g) => g.id).toList();
          expect(activeIds, contains('food-group-dairy'));
          expect(activeIds, isNot(contains(oldId)));
        },
      );

      test(
        'S-13707 an uncategorized library copy follows its catalog row\'s '
        'shipped category',
        () async {
          await repo.createCatalogFood(
            _catalogFood('whole_milk', 'Whole milk', groupId: 'food-group-dairy'),
          );
          await repo.createCatalogFood(
            _catalogFood('apple', 'Apple', groupId: 'food-group-fruits'),
          );
          await repo.createCatalogFood(
            _catalogFood('cat-mine', 'My trail mix', groupId: null),
          );
          final mineId = await repo.createFoodGroup(
            const FoodGroup(
              id: 'group-137-mine',
              name: 'Mine',
              color: '#123456',
              createdAtMs: _atMs,
              updatedAtMs: _atMs,
            ),
          );
          await repo.createCatalogFood(
            _catalogFood('cat-custom', 'Custom bar', groupId: mineId),
          );

          await repo.createFood(
            _libraryFood('lib-a', 'Milk A', catalogId: 'whole_milk'),
          );
          await repo.createFood(
            _libraryFood(
              'lib-b',
              'Milk B',
              groupId: 'food-group-snacks-prepared',
              catalogId: 'whole_milk',
            ),
          );
          await repo.createFood(_libraryFood('lib-c', 'Home brew'));
          await repo.createFood(
            _libraryFood('lib-d', 'Trail mix copy', catalogId: 'cat-mine'),
          );
          await repo.createFood(
            _libraryFood('lib-e', 'Apple copy', catalogId: 'apple'),
          );
          await repo.createFood(
            _libraryFood('lib-f', 'Custom bar copy', catalogId: 'cat-custom'),
          );

          await _runStep(repo);

          expect((await repo.getFoodById('lib-a'))!.groupId, 'food-group-dairy');
          expect(
            (await repo.getFoodById('lib-e'))!.groupId,
            'food-group-fruits',
          );
          expect(
            (await repo.getFoodById('lib-b'))!.groupId,
            'food-group-snacks-prepared',
            reason: 'a copy that already has a category is untouched',
          );
          expect((await repo.getFoodById('lib-c'))!.groupId, isNull);
          expect(
            (await repo.getFoodById('lib-d'))!.groupId,
            isNull,
            reason: 'a user-created catalog row names no shipped category',
          );
          expect(
            (await repo.getFoodById('lib-f'))!.groupId,
            isNull,
            reason: 'a catalog row in a category the user made is not '
                'a shipped category',
          );
        },
      );

      test('S-13708 a second run writes nothing; the version is 19', () async {
        expect(currentDataVersion, 19);

        final steps = _steps(repo);
        expect(steps.last.targetVersion, 19);
        expect(steps.last.name, _stepName);

        // A freshly opened store is already migrated, with no archived
        // shipped category.
        expect(await repo.getDataVersion(), currentDataVersion);
        expect(
          (await repo.getFoodGroupById('food-group-dairy'))!.isArchived,
          isFalse,
        );

        await repo.archiveFoodGroup('food-group-dairy');
        await repo.createCatalogFood(
          _catalogFood('whole_milk', 'Whole milk', groupId: 'food-group-dairy'),
        );
        await repo.createFood(
          _libraryFood('lib-a', 'Milk A', catalogId: 'whole_milk'),
        );

        await _runStep(repo);
        final foodsBefore = await _foodStamps(repo);
        final groupsBefore = await _groupStamps(repo);

        await _runStep(repo);

        expect(await _foodStamps(repo), foodsBefore);
        expect(await _groupStamps(repo), groupsBefore);
      });

      test(
        'S-13709 a failing group write propagates and the next run completes',
        () async {
          final failing = _FailingFoodGroupUpdateRepo();
          await failing.initialize();
          await failing.archiveFoodGroup('food-group-dairy');

          await expectLater(
            ShippedFoodGroupsRepair(failing).run(),
            throwsA(isA<StateError>()),
          );

          await failing.setDataVersion(18);
          await expectLater(
            DataMigrationService(
              repository: failing,
              targetVersion: currentDataVersion,
              steps: failing.dataMigrationStepsForTest(),
            ).run(),
            throwsA(isA<StateError>()),
          );
          expect(await failing.getDataVersion(), 18);

          failing.failing = false;
          await DataMigrationService(
            repository: failing,
            targetVersion: currentDataVersion,
            steps: failing.dataMigrationStepsForTest(),
          ).run();

          expect(await failing.getDataVersion(), currentDataVersion);
          expect(
            (await failing.getFoodGroupById('food-group-dairy'))!.isArchived,
            isFalse,
            reason: 'the retry after the failure clears completes the repair',
          );
        },
      );
    });
  }
}
