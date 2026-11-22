// Plan 303 — food categories never share a name, and devices that already have
// two "Dairy" categories are repaired.
//
// Scenarios S-30301..S-30312 of
// `docs/plans/2026-11-22-303-duplicate-food-categories-plan/2026-11-22-303-duplicate-food-categories-plan.md`.
//
// Step `mergeDuplicateFoodGroups` (version 21) folds every set of active
// same-name categories into the shipped one (or the oldest) and archives the
// rest; foods and logged entries are never removed. The store cases run over
// `harnessFactories` with plain `test()`: a Hive write inside a widget test's
// FakeAsync never completes, so the two widget cases use the Mock only.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:omnitrain/core/constants/data_version.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/hive_workout_repository.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/features/nutrition/add_food_screen.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';

import 'helpers/repository_harness.dart';

const int _atMs = 1700000000000;
const String _mergeStep = 'mergeDuplicateFoodGroups';
const String _shippedDairy = 'food-group-dairy';

/// Hides [hiddenIds] from the group reads until that id is created, the way a
/// device looks whose default seeding skipped a shipped category.
class _MissingShippedRepo extends MockWorkoutRepository {
  _MissingShippedRepo(this.hiddenIds);
  final Set<String> hiddenIds;

  @override
  Future<List<FoodGroup>> getFoodGroups({
    bool includeArchived = false,
  }) async => [
    for (final g in await super.getFoodGroups(includeArchived: includeArchived))
      if (!hiddenIds.contains(g.id)) g,
  ];

  @override
  Future<FoodGroup?> getFoodGroupById(String id) async =>
      hiddenIds.contains(id) ? null : super.getFoodGroupById(id);

  @override
  Future<String> createFoodGroup(FoodGroup group) async {
    hiddenIds.remove(group.id);
    return super.createFoodGroup(group);
  }
}

/// Throws on the first `archiveFoodGroup`, then behaves normally.
class _FailsOnceOnArchiveRepo extends MockWorkoutRepository {
  bool failing = true;

  @override
  Future<void> archiveFoodGroup(String id) async {
    if (failing) throw StateError('simulated');
    await super.archiveFoodGroup(id);
  }
}

List<DataMigrationStep> _steps(WorkoutRepository repo) =>
    repo is MockWorkoutRepository
    ? repo.dataMigrationStepsForTest()
    : (repo as HiveWorkoutRepository).dataMigrationStepsForTest();

DataMigrationStep _step(WorkoutRepository repo, String name) {
  final matches = _steps(repo).where((s) => s.name == name).toList();
  if (matches.length != 1) {
    throw StateError(
      'plan 303 not implemented: migration step "$name" is missing; the step '
      'list holds [${_steps(repo).map((s) => '${s.targetVersion}:${s.name}').join(', ')}]',
    );
  }
  return matches.single;
}

Future<void> _runMerge(WorkoutRepository repo) => _step(repo, _mergeStep).run();

FoodGroup _group(String id, String name, int createdAtMs) => FoodGroup(
  id: id,
  name: name,
  createdAtMs: createdAtMs,
  updatedAtMs: createdAtMs,
);

Food _libraryFood(
  String id,
  String name, {
  String? groupId,
  String? catalogId,
  bool archived = false,
}) => Food(
  id: id,
  name: name,
  groupId: groupId,
  catalogId: catalogId,
  isArchived: archived,
  unitType: FoodUnitType.grams,
  referenceAmount: 100,
  referenceLabel: 'g',
  protein: 4,
  carbs: 6,
  fat: 1,
  createdAtMs: _atMs,
  updatedAtMs: _atMs,
);

Future<List<FoodGroup>> _active(WorkoutRepository repo) => repo.getFoodGroups();

Future<List<String>> _activeNamed(WorkoutRepository repo, String name) async =>
    [
      for (final g in await _active(repo))
        if (g.name.trim().toLowerCase() == name.toLowerCase()) g.id,
    ];

Future<Map<String, int>> _stamps(WorkoutRepository repo) async => {
  for (final f in await repo.getFoods(includeArchived: true))
    'food:${f.id}': f.updatedAtMs,
  for (final f in await repo.getCatalogFoods(includeArchived: true))
    'catalog:${f.id}': f.updatedAtMs,
  for (final g in await repo.getFoodGroups(includeArchived: true))
    'group:${g.id}': g.updatedAtMs,
};

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — duplicate food categories (plan 303)', () {
      late WorkoutRepository repo;

      setUp(() async {
        repo = await harness.open();
      });
      tearDown(() => harness.close());

      test('S-30301 a custom "Dairy" is folded into the shipped one; the '
          'default food Cottage cheese and every copy come back', () async {
        await repo.createFoodGroup(_group('group-303-dairy', 'Dairy', _atMs));
        final cottage = (await repo.getCatalogFoodById('cottage_cheese'))!;
        expect(cottage.groupId, _shippedDairy, reason: 'fixture premise');
        await repo.updateCatalogFood(
          cottage.copyWith(groupId: 'group-303-dairy'),
        );
        await repo.createFood(
          _libraryFood(
            'lib-cottage',
            'Cottage cheese, low-fat',
            groupId: 'group-303-dairy',
            catalogId: 'cottage_cheese',
          ),
        );
        await repo.createFood(
          _libraryFood('lib-mine', 'My kefir', groupId: 'group-303-dairy'),
        );
        await repo.createFood(
          _libraryFood(
            'lib-old',
            'Old yoghurt',
            groupId: 'group-303-dairy',
            archived: true,
          ),
        );
        expect(await _activeNamed(repo, 'Dairy'), hasLength(2));
        final libraryBefore = (await repo.getFoods(
          includeArchived: true,
        )).map((f) => f.id).toSet();
        final catalogBefore = (await repo.getCatalogFoods(
          includeArchived: true,
        )).map((f) => f.id).toSet();

        await _runMerge(repo);

        expect(await _activeNamed(repo, 'Dairy'), [_shippedDairy]);
        final custom = (await repo.getFoodGroupById('group-303-dairy'))!;
        expect(custom.isArchived, isTrue, reason: 'archived, never deleted');
        expect(
          (await repo.getCatalogFoodById('cottage_cheese'))!.groupId,
          _shippedDairy,
        );
        for (final id in ['lib-cottage', 'lib-mine', 'lib-old']) {
          expect(
            (await repo.getFoodById(id))!.groupId,
            _shippedDairy,
            reason: id,
          );
        }
        expect(
          (await repo.getFoods(includeArchived: true)).map((f) => f.id).toSet(),
          libraryBefore,
        );
        expect(
          (await repo.getCatalogFoods(
            includeArchived: true,
          )).map((f) => f.id).toSet(),
          catalogBefore,
        );

        // A second run finds nothing to do and writes nothing.
        final stamps = await _stamps(repo);
        await _runMerge(repo);
        expect(await _stamps(repo), stamps);
      });

      test('S-30302 the plan 137 path: shipped Dairy archived, own Dairy made, '
          'step 19 un-archives, step 21 merges', () async {
        await repo.archiveFoodGroup(_shippedDairy);
        await repo.createFoodGroup(_group('group-303-own', 'Dairy', _atMs));
        final cottage = (await repo.getCatalogFoodById('cottage_cheese'))!;
        await repo.updateCatalogFood(
          cottage.copyWith(groupId: 'group-303-own'),
        );

        await _step(repo, 'restoreShippedFoodGroups').run();
        expect(
          await _activeNamed(repo, 'Dairy'),
          hasLength(2),
          reason: 'fixture premise: step 19 leaves two active Dairy rows',
        );

        await _runMerge(repo);

        expect(await _activeNamed(repo, 'Dairy'), [_shippedDairy]);
        expect(
          (await repo.getCatalogFoodById('cottage_cheese'))!.groupId,
          _shippedDairy,
        );
      });

      test('S-30303 two custom categories that differ only by case and spaces '
          'merge into the oldest; different names stay apart', () async {
        await repo.createFoodGroup(_group('group-a', 'Kitchen Staples', 1000));
        await repo.createFoodGroup(
          _group('group-b', ' kitchen staples ', 2000),
        );
        await repo.createFoodGroup(
          _group('group-c', 'Kitchen Staples Extra', 3000),
        );
        await repo.createFood(_libraryFood('f-a', 'Rice', groupId: 'group-a'));
        await repo.createFood(_libraryFood('f-b', 'Oats', groupId: 'group-b'));
        await repo.createFood(_libraryFood('f-c', 'Salt', groupId: 'group-c'));

        await _runMerge(repo);

        expect((await repo.getFoodGroupById('group-a'))!.isArchived, isFalse);
        expect((await repo.getFoodGroupById('group-b'))!.isArchived, isTrue);
        expect((await repo.getFoodGroupById('group-c'))!.isArchived, isFalse);
        expect((await repo.getFoodById('f-a'))!.groupId, 'group-a');
        expect((await repo.getFoodById('f-b'))!.groupId, 'group-a');
        expect((await repo.getFoodById('f-c'))!.groupId, 'group-c');
      });

      test('S-30304 shipped Dairy found archived beside an active "Dairy" is '
          'brought back and wins', () async {
        await repo.archiveFoodGroup(_shippedDairy);
        await repo.createFoodGroup(_group('group-303-own', 'Dairy', _atMs));
        await repo.createFood(
          _libraryFood('lib-mine', 'My kefir', groupId: 'group-303-own'),
        );

        await _runMerge(repo);

        expect(await _activeNamed(repo, 'Dairy'), [_shippedDairy]);
        expect((await repo.getFoodById('lib-mine'))!.groupId, _shippedDairy);
      });

      test('S-30305 two shipped categories sharing a name are both kept '
          '(a shipped category is never archived)', () async {
        final fruits = (await repo.getFoodGroupById('food-group-fruits'))!;
        await repo.updateFoodGroup(
          FoodGroup(
            id: fruits.id,
            name: 'Dairy',
            createdAtMs: fruits.createdAtMs,
            updatedAtMs: _atMs,
          ),
        );

        await _runMerge(repo);

        expect(
          await _activeNamed(repo, 'Dairy'),
          unorderedEquals([_shippedDairy, 'food-group-fruits']),
        );
      });

      test('S-30306 a fresh install is untouched by the step', () async {
        final stamps = await _stamps(repo);
        await _runMerge(repo);
        expect(await _stamps(repo), stamps);
        expect(await _active(repo), hasLength(9));
      });
    });
  }

  group('Mock — merge resilience (plan 303)', () {
    test('S-30307 a shipped category missing from storage while an active '
        '"Dairy" stands in is re-created and wins the merge', () async {
      final repo = _MissingShippedRepo({_shippedDairy});
      await repo.initialize();
      await repo.createFoodGroup(_group('group-303-own', 'Dairy', _atMs));
      await repo.createFood(
        _libraryFood('lib-mine', 'My kefir', groupId: 'group-303-own'),
      );
      expect(
        await repo.getFoodGroupById(_shippedDairy),
        isNull,
        reason: 'fixture premise: the shipped row is not there',
      );

      await _runMerge(repo);

      expect(await _activeNamed(repo, 'Dairy'), [_shippedDairy]);
      expect((await repo.getFoodGroupById(_shippedDairy))!.name, 'Dairy');
      expect((await repo.getFoodById('lib-mine'))!.groupId, _shippedDairy);
      expect(
        (await repo.getFoodGroupById('group-303-own'))!.isArchived,
        isTrue,
      );
    });

    test('S-30308 a missing shipped category with no same-name stand-in is '
        'not invented', () async {
      final repo = _MissingShippedRepo({_shippedDairy});
      await repo.initialize();

      await _runMerge(repo);

      expect(await repo.getFoodGroupById(_shippedDairy), isNull);
    });

    test('S-30309 a failure after the foods moved leaves a state the next '
        'run finishes', () async {
      final repo = _FailsOnceOnArchiveRepo();
      await repo.initialize();
      await repo.createFoodGroup(_group('group-303-own', 'Dairy', _atMs));
      await repo.createFood(
        _libraryFood('lib-mine', 'My kefir', groupId: 'group-303-own'),
      );

      await expectLater(_runMerge(repo), throwsA(isA<StateError>()));
      expect((await repo.getFoodById('lib-mine'))!.groupId, _shippedDairy);
      expect(await _activeNamed(repo, 'Dairy'), hasLength(2));

      repo.failing = false;
      await _runMerge(repo);
      expect(await _activeNamed(repo, 'Dairy'), [_shippedDairy]);
    });

    test('S-30310 the step is appended as 21 in both stores and the data '
        'version is 21', () {
      final mock = MockWorkoutRepository().dataMigrationStepsForTest();
      final hive = HiveWorkoutRepository().dataMigrationStepsForTest();
      expect(mock.last.targetVersion, 21);
      expect(mock.last.name, _mergeStep);
      expect(hive.last.targetVersion, 21);
      expect(hive.last.name, _mergeStep);
    });
  });

  group('FoodLibraryState — same-name categories are refused (plan 303)', () {
    late MockWorkoutRepository repo;
    late FoodLibraryState state;

    setUp(() async {
      repo = MockWorkoutRepository();
      await repo.initialize();
      state = FoodLibraryState(repo);
    });

    test('S-30311 create refuses an active name, any case, any padding; '
        'nothing is written', () async {
      final before = (await repo.getFoodGroups(includeArchived: true)).length;
      for (final name in ['Dairy', 'dairy', '  DAIRY ']) {
        await expectLater(
          state.createFoodGroup(name),
          throwsA(isA<DuplicateFoodGroupNameError>()),
          reason: name,
        );
      }
      expect((await repo.getFoodGroups(includeArchived: true)).length, before);
    });

    test('S-30312 rename refuses another category\'s name, allows its own '
        'name in a new case, and an archived name is free', () async {
      await state.loadFoodGroups(includeArchived: true);
      final id = await state.createFoodGroup('Snacks 2');

      await expectLater(
        state.renameFoodGroup(id, ' dairy '),
        throwsA(isA<DuplicateFoodGroupNameError>()),
      );
      expect(
        (await repo.getFoodGroupById(id))!.name,
        'Snacks 2',
        reason: 'a refused rename changes nothing',
      );

      await state.renameFoodGroup(id, 'SNACKS 2');
      expect((await repo.getFoodGroupById(id))!.name, 'SNACKS 2');

      await state.archiveFoodGroup(id);
      final again = await state.createFoodGroup('snacks 2');
      expect(again, isNot(id), reason: 'an archived name can be used again');
    });

    test('S-30313 freeGroupName numbers a taken name', () async {
      await state.loadFoodGroups();
      expect(state.freeGroupName('New Category'), 'New Category');
      await state.createFoodGroup('New Category');
      expect(state.freeGroupName('New Category'), 'New Category 2');
      await state.createFoodGroup('New Category 2');
      expect(state.freeGroupName('New Category'), 'New Category 3');
    });
  });

  group('Hive — seeding beside an existing same-name category (plan 303)', () {
    test('S-30314 a device whose box already holds a custom "Dairy" ends up '
        'with the shipped Dairy as the only one', () async {
      final dir = await Directory.systemTemp.createTemp('dup_groups_seed_');
      PathProviderChannel.install(dir);
      Hive.init(dir.path);
      try {
        final box = await Hive.openBox<Map>('food_groups');
        await box.put(
          'group-303-own',
          _group('group-303-own', 'Dairy', _atMs).toMap(),
        );
        await box.close();

        final repo = HiveWorkoutRepository();
        await repo.initialize();

        expect(await _activeNamed(repo, 'Dairy'), [_shippedDairy]);
        final catalog = await repo.getCatalogFoods();
        expect(
          catalog.where((f) => f.groupId == _shippedDairy),
          isNotEmpty,
          reason: 'bundled dairy foods sit under a category that exists',
        );
      } finally {
        await Hive.deleteFromDisk();
        await dir.delete(recursive: true);
      }
    });
  });

  group('Categories tab — same-name categories (plan 303)', () {
    Future<(MockWorkoutRepository, FoodLibraryState)> open(
      WidgetTester tester,
    ) async {
      final repo = MockWorkoutRepository();
      await repo.initialize();
      repo.clearConsumedFoodsForTest();
      final foodLib = FoodLibraryState(repo);
      final nutrition = NutritionState(repo);
      await foodLib.loadFoodGroups();
      await tester.pumpWidget(
        MaterialApp(
          home: AddFoodScreen(
            foodLibraryState: foodLib,
            nutritionState: nutrition,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Categories'));
      await tester.pumpAndSettle();
      return (repo, foodLib);
    }

    testWidgets('S-30315 renaming a category to a name another one has shows '
        'why and puts the old name back', (tester) async {
      final (repo, foodLib) = await open(tester);

      final field = find.byKey(const Key('group_name_food-group-fruits'));
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, 'Dairy');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.textContaining('already exists'), findsOneWidget);
      expect(
        (await repo.getFoodGroupById('food-group-fruits'))!.name,
        'Fruits',
      );
      expect(tester.widget<TextField>(field).controller!.text, 'Fruits');
      expect(
        foodLib.activeFoodGroups.where((g) => g.name == 'Dairy'),
        hasLength(1),
      );
    });

    testWidgets('S-30316 pressing + twice makes "New Category" and '
        '"New Category 2"', (tester) async {
      final (_, foodLib) = await open(tester);

      await tester.tap(find.byKey(const Key('new_group_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('new_group_button')));
      await tester.pumpAndSettle();

      final names = foodLib.activeFoodGroups.map((g) => g.name).toSet();
      expect(names, containsAll(['New Category', 'New Category 2']));
    });
  });
}
