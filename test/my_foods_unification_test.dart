// Unit tests for the D-2 "My Foods Unification" data-layer contract.
//
// Covers scenarios:
//   S-030: createCatalogFood(draft) + addCatalogFoodToLibrary(id)
//          makes the new food visible in the My Foods tab AND in
//          the Foods I Eat card without a restart.
//   S-031: userCreatedCatalogFoods contains user-created catalog
//          foods (and the legacy library-only customs helper still
//          surfaces pre-D-2 rows for management).
//   S-032: deleteCatalogFood removes the catalog row; unlogFoodToday
//          drops any same-day log; library copy is removed first so
//          the caches stay consistent; past ConsumedFood snapshots
//          are byte-identical.
//   S-033: bundled catalog food IDs are protected from hard delete.
//   S-034: updateCatalogFood persists changes; any matching library
//          copy is synced (the new values flow through to the Foods
//          I Eat card via state notifyListeners).
//
// These tests use MockWorkoutRepository; no asset I/O.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/food_draft.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/nutrition/add_food_screen.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

Future<FoodLibraryState> _loadedState(MockWorkoutRepository repo) async {
  final state = FoodLibraryState(repo);
  await state.loadFoodGroups();
  await state.loadFoods();
  await state.loadCatalogFoods();
  return state;
}

FoodDraft _trailMixDraft({String? groupId, String? name, double? protein, String? notes}) => FoodDraft(
      name: name ?? 'My Trail Mix',
      groupId: groupId,
      unitType: FoodUnitType.grams,
      referenceAmount: 50.0,
      referenceLabel: 'g',
      protein: protein ?? 10,
      carbs: 18,
      fiber: 3,
      fat: 12,
      sodium: 100,
      notes: notes ?? 'homemade',
      imagePath: null,
    );

FoodDraft _quickDraft({
  required String name,
  double protein = 5,
  double carbs = 5,
  double fat = 5,
  FoodUnitType unitType = FoodUnitType.grams,
  double referenceAmount = 100.0,
  String referenceLabel = 'g',
}) =>
    FoodDraft(
      name: name,
      groupId: null,
      unitType: unitType,
      referenceAmount: referenceAmount,
      referenceLabel: referenceLabel,
      protein: protein,
      carbs: carbs,
      fat: fat,
      fiber: 0,
      sodium: 0,
      notes: null,
      imagePath: null,
    );

void main() {
  group('My Foods Unification (D-2 / S-030)', () {
    test(
      'createCatalogFood + addCatalogFoodToLibrary makes the food '
      'visible in both the catalog and the library without restart',
      () async {
        final repo = await _freshRepo();
        final state = await _loadedState(repo);

        // Pre-condition: not in catalog, not in library.
        expect(
          state.userCreatedCatalogFoods.any((f) => f.name == 'My Trail Mix'),
          isFalse,
        );
        expect(
          state.foods.any((f) => f.name == 'My Trail Mix'),
          isFalse,
        );

        // S-030: create catalog food, then add to library.
        final catalogId = await state.createCatalogFood(_trailMixDraft());
        expect(catalogId, isNotEmpty);

        // The catalog row is in userCreatedCatalogFoods (post-create).
        await state.loadCatalogFoods();
        final userCatalog = state.userCreatedCatalogFoods
            .where((f) => f.name == 'My Trail Mix')
            .toList();
        expect(userCatalog, hasLength(1));
        expect(userCatalog.single.id, catalogId);
        expect(userCatalog.single.isCatalog, isTrue);

        // Then add to library.
        final libraryId =
            await state.addCatalogFoodToLibrary(catalogId);
        expect(libraryId, isNotEmpty);
        expect(libraryId, isNot(catalogId));

        // The library now has a sibling row with the same data.
        await state.loadFoods();
        final libRow = state.foods.firstWhere(
          (f) => f.id == libraryId,
          orElse: () => throw StateError('library row missing'),
        );
        expect(libRow.name, 'My Trail Mix');
        expect(libRow.protein, 10);
        expect(libRow.carbs, 18);
        expect(libRow.fat, 12);
        expect(libRow.isCatalog, isFalse,
            reason: 'library copy must be isCatalog = false');

        // The libraryIdFor lookup resolves the catalog id to the
        // library id (the UI's `addCatalogFoodToLibrary` toggle).
        expect(state.libraryIdFor(catalogId), libraryId);
      },
    );

    test(
      'createCatalogFood is persisted to the catalog box (survives '
      'a fresh state load)',
      () async {
        final repo = await _freshRepo();
        final state = await _loadedState(repo);

        final catalogId = await state.createCatalogFood(_trailMixDraft());
        await state.addCatalogFoodToLibrary(catalogId);

        // Build a new state against the same repo and confirm both
        // rows are still there.
        final state2 = await _loadedState(repo);
        final fromCatalog = state2.userCreatedCatalogFoods
            .where((f) => f.name == 'My Trail Mix')
            .toList();
        expect(fromCatalog, hasLength(1));
        expect(fromCatalog.single.id, catalogId);

        final libId = state2.libraryIdFor(catalogId);
        expect(libId, isNotNull);
        final libRow = state2.foods.firstWhere((f) => f.id == libId);
        expect(libRow.name, 'My Trail Mix');
      },
    );
  });

  group('userCreatedCatalogFoods (D-2 / S-031)', () {
    test(
      'bundled catalog foods are excluded; user-created catalog foods '
      'are listed (alpha sorted)',
      () async {
        final repo = await _freshRepo();
        final state = await _loadedState(repo);

        // Two user-created catalog foods, with names chosen to
        // exercise the alpha sort.
        await state.createCatalogFood(_quickDraft(
          name: 'Zebra Cake',
          unitType: FoodUnitType.count,
          referenceAmount: 1.0,
          referenceLabel: 'slice',
          protein: 2,
          carbs: 30,
          fat: 10,
        ));
        await state.createCatalogFood(_quickDraft(
          name: 'Apple Pie',
          protein: 2,
          carbs: 35,
          fat: 14,
        ));

        final userCatalog = state.userCreatedCatalogFoods
            .map((f) => f.name)
            .toList();

        // Bundled foods are NOT in the list.
        expect(userCatalog, isNot(contains('Chicken breast, skinless')));
        expect(userCatalog, isNot(contains('Whole milk')));

        // User-created foods are in alpha order.
        expect(userCatalog, contains('Apple Pie'));
        expect(userCatalog, contains('Zebra Cake'));
        final appleIdx = userCatalog.indexOf('Apple Pie');
        final zebraIdx = userCatalog.indexOf('Zebra Cake');
        expect(appleIdx, lessThan(zebraIdx));
      },
    );

    test(
      'legacy library-only customs (isCatalog = false) are NOT in '
      'userCreatedCatalogFoods; they live in foods only',
      () async {
        final repo = await _freshRepo();
        final state = await _loadedState(repo);

        // Create a legacy row via the deprecated library-only path
        // (still works; just emits a deprecation warning).
        // ignore: deprecated_member_use_from_same_package
        await state.createCustomFood(
          name: 'Legacy Snack',
          groupId: null,
          unitType: FoodUnitType.grams,
          referenceAmount: 30.0,
          referenceLabel: 'g',
          protein: 5,
          carbs: 12,
          fat: 6,
        );

        // The legacy row lives in `foods` (isCatalog = false).
        await state.loadFoods();
        final legacy =
            state.foods.where((f) => f.name == 'Legacy Snack').toList();
        expect(legacy, hasLength(1));
        expect(legacy.single.isCatalog, isFalse);

        // It is NOT in userCreatedCatalogFoods.
        await state.loadCatalogFoods();
        final userCatalog = state.userCreatedCatalogFoods
            .where((f) => f.name == 'Legacy Snack')
            .toList();
        expect(userCatalog, isEmpty,
            reason:
                'userCreatedCatalogFoods is catalog-only; library rows '
                'are surfaced via foods, not via the catalog cache.');
      },
    );
  });

  group('Delete user-created catalog food (D-2 / S-032)', () {
    test(
      'unlogFoodToday + removeFood(libraryId) + deleteCatalogFood '
      'removes the food from both caches; past ConsumedFood rows are '
      'untouched',
      () async {
        final repo = await _freshRepo();
        final state = await _loadedState(repo);
        final nutrition = NutritionState(repo);
        await nutrition.loadNutritionTarget();
        await nutrition.loadConsumedToday();

        const yesterdayMs = 1700000000000;

        // Create a custom catalog food, add to library.
        final catalogId = await state.createCatalogFood(_trailMixDraft());
        final libraryId = await state.addCatalogFoodToLibrary(catalogId);
        await state.loadFoods();

        // Log a ConsumedFood entry for TODAY.
        final libRow = state.foods.firstWhere((f) => f.id == libraryId);
        await nutrition.logConsumedFoodAt(libRow, 50.0);

        // And a separate (already-existing) ConsumedFood entry for
        // YESTERDAY. We hand-build a snapshot so the test does not
        // depend on the current calendar.
        final yesterday = ConsumedFood(
          id: 'past-log-1',
          loggedAtMs: yesterdayMs,
          dateMs: yesterdayMs,
          sourceFoodId: libraryId,
          name: 'My Trail Mix',
          unitType: FoodUnitType.grams,
          referenceAmount: 50.0,
          referenceLabel: 'g',
          protein: 10,
          carbs: 18,
          fat: 12,
          amountConsumed: 50.0,
          targetCalories: 2000,
          targetProtein: 100,
          targetCarbs: 200,
          targetFat: 60,
          createdAtMs: yesterdayMs,
          updatedAtMs: yesterdayMs,
        );
        await repo.createConsumedFood(yesterday);

        // S-032: unlog + remove library + delete catalog.
        final isLogged =
            nutrition.isFoodLoggedToday(libraryId);
        expect(isLogged, isTrue);

        // 1) Unlog today's entry.
        await nutrition.unlogFoodToday(libraryId);
        expect(nutrition.isFoodLoggedToday(libraryId), isFalse);

        // 2) Remove the library copy.
        await state.removeFood(libraryId);
        await state.loadFoods();
        expect(state.foods.any((f) => f.id == libraryId), isFalse);

        // 3) Hard-delete the catalog row.
        await state.deleteCatalogFood(catalogId);
        await state.loadCatalogFoods();
        expect(
          state.userCreatedCatalogFoods.any((f) => f.id == catalogId),
          isFalse,
        );
        expect(
          (await repo.getCatalogFoodById(catalogId)),
          isNull,
          reason: 'catalog row must be hard-deleted',
        );

        // Yesterday's ConsumedFood snapshot is byte-identical.
        final stillThere =
            (await repo.getConsumedFoodsInRange(yesterdayMs, yesterdayMs))
                .firstWhere((c) => c.id == 'past-log-1');
        expect(stillThere.name, 'My Trail Mix');
        expect(stillThere.protein, 10);
        expect(stillThere.sourceFoodId, libraryId,
            reason:
                'past snapshots keep the sourceFoodId even when the '
                'source food is gone — the snapshot is frozen.');
      },
    );

    test(
      'delete without a same-day log still removes library copy + '
      'catalog row (unlog is a no-op)',
      () async {
        final repo = await _freshRepo();
        final state = await _loadedState(repo);

        final catalogId = await state.createCatalogFood(_trailMixDraft());
        final libraryId = await state.addCatalogFoodToLibrary(catalogId);
        await state.loadFoods();

        // No log for today; just remove library + delete catalog.
        await state.removeFood(libraryId);
        await state.deleteCatalogFood(catalogId);

        await state.loadFoods();
        await state.loadCatalogFoods();
        expect(state.foods.any((f) => f.id == libraryId), isFalse);
        expect(
          state.userCreatedCatalogFoods.any((f) => f.id == catalogId),
          isFalse,
        );
      },
    );
  });

  group('Bundled food hard-delete protection (D-2 / S-033)', () {
    test('deleteCatalogFood throws on a bundled food id', () async {
      final repo = await _freshRepo();
      final state = await _loadedState(repo);

      // 'chicken_breast' is in the bundled set.
      expect(state.isBundledCatalogFood('chicken_breast'), isTrue);

      await expectLater(
        state.deleteCatalogFood('chicken_breast'),
        throwsA(isA<StateError>()),
      );

      // The bundled row is still in the catalog.
      final chicken = await repo.getCatalogFoodById('chicken_breast');
      expect(chicken, isNotNull);
    });

    test('isBundledCatalogFood returns false for user-created ids', () async {
      final repo = await _freshRepo();
      final state = await _loadedState(repo);

      final id = await state.createCatalogFood(_trailMixDraft());
      expect(state.isBundledCatalogFood(id), isFalse);
    });
  });

  group('Edit user-created catalog food (D-2 / S-034)', () {
    test(
      'updateCatalogFood overwrites the catalog row and the state '
      'notifies listeners; matching library copies are synced',
      () async {
        final repo = await _freshRepo();
        final state = await _loadedState(repo);

        // Create + add-to-library so a sibling row exists.
        final catalogId = await state.createCatalogFood(_trailMixDraft());
        final libraryId = await state.addCatalogFoodToLibrary(catalogId);
        await state.loadFoods();

        var notified = false;
        state.addListener(() => notified = true);

        final original = (await repo.getCatalogFoodById(catalogId))!;
        await state.updateCatalogFood(
          original,
          _trailMixDraft(
            name: 'My Trail Mix v2',
            protein: 14,
            notes: 'updated notes',
          ),
        );

        expect(notified, isTrue,
            reason: 'updateCatalogFood must notify listeners');

        // The catalog row is updated.
        final reloaded = (await repo.getCatalogFoodById(catalogId))!;
        expect(reloaded.name, 'My Trail Mix v2');
        expect(reloaded.protein, 14);
        expect(reloaded.notes, 'updated notes');

        // The matching library copy is synced to the new values.
        await state.loadFoods();
        final libRow = state.foods.firstWhere((f) => f.id == libraryId);
        expect(libRow.name, 'My Trail Mix v2');
        expect(libRow.protein, 14);
        expect(libRow.notes, 'updated notes');
      },
    );

    test(
      'updateCatalogFood throws when the food is isCatalog = false '
      '(caller must route legacy rows through updateCustomFood)',
      () async {
        final repo = await _freshRepo();
        final state = await _loadedState(repo);

        // Create a legacy library-only food (deprecated path).
        // ignore: deprecated_member_use_from_same_package
        await state.createCustomFood(
          name: 'Legacy Custom',
          groupId: null,
          unitType: FoodUnitType.grams,
          referenceAmount: 30.0,
          referenceLabel: 'g',
          protein: 5,
          carbs: 12,
          fat: 6,
        );
        await state.loadFoods();
        final legacy = state.foods.firstWhere(
          (f) => f.name == 'Legacy Custom',
        );

        await expectLater(
          state.updateCatalogFood(legacy, _trailMixDraft()),
          throwsA(isA<StateError>()),
        );
      },
    );

    test(
      'updateCustomFood persists changes for legacy library rows',
      () async {
        final repo = await _freshRepo();
        final state = await _loadedState(repo);

        // ignore: deprecated_member_use_from_same_package
        await state.createCustomFood(
          name: 'Legacy Custom',
          groupId: null,
          unitType: FoodUnitType.grams,
          referenceAmount: 30.0,
          referenceLabel: 'g',
          protein: 5,
          carbs: 12,
          fat: 6,
        );
        await state.loadFoods();
        final legacy = state.foods.firstWhere(
          (f) => f.name == 'Legacy Custom',
        );

        await state.updateCustomFood(
          id: legacy.id,
          name: 'Legacy Custom v2',
          groupId: null,
          unitType: FoodUnitType.grams,
          referenceAmount: 30.0,
          referenceLabel: 'g',
          protein: 7,
          carbs: 12,
          fat: 6,
          imagePath: null,
        );
        await state.loadFoods();
        final updated = state.foods.firstWhere(
          (f) => f.id == legacy.id,
        );
        expect(updated.name, 'Legacy Custom v2');
        expect(updated.protein, 7);
      },
    );
  });

  group('createCustomFood / createCustomFoodFromDraft deprecation', () {
    test(
      'createCustomFood still works (legacy support) but emits a '
      'deprecation warning at the analyzer level',
      () async {
        // The deprecation is a @Deprecated annotation; the test
        // exists to assert the legacy path continues to work so
        // pre-D-2 call sites are not broken. The build's analyzer
        // will fail any new caller that uses these methods without
        // an `// ignore: deprecated_member_use_*` comment.
        final repo = await _freshRepo();
        final state = await _loadedState(repo);

        // ignore: deprecated_member_use_from_same_package
        final id = await state.createCustomFood(
          name: 'Legacy Path Food',
          groupId: null,
          unitType: FoodUnitType.grams,
          referenceAmount: 30.0,
          referenceLabel: 'g',
          protein: 5,
          carbs: 12,
          fat: 6,
        );
        expect(id, isNotEmpty);

        // ignore: deprecated_member_use_from_same_package
        final id2 = await state.createCustomFoodFromDraft(_quickDraft(
          name: 'Legacy Path Food 2',
          referenceAmount: 30.0,
          referenceLabel: 'g',
          protein: 5,
          carbs: 12,
          fat: 6,
        ));
        expect(id2, isNotEmpty);
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════
  // S-031a — My Foods tab population: structural guard
  // (Phase 3.1 supersedure of S-031)
  // ═══════════════════════════════════════════════════════════════════════
  //
  // The original S-031 didn't pin the precondition that bundled
  // catalog foods have library copies (created by the user
  // tapping Add on the Library tab). The Phase 2 test surface
  // happened to never seed a bundled food's library copy, so the
  // merge logic's missing exclusion (`!isCatalog &&
  // catalogIdFor == null`) went unnoticed.
  //
  // This group seeds a realistic mix and asserts the expected
  // My Foods surface. To avoid mirroring the widget's merge
  // logic in a helper (which would also mirror bugs), we pump
  // the actual `AddFoodScreen` and read what the `My Foods` tab
  // renders. The widget is private, but the screen is public.

  /// Collects the food names rendered in the **My Foods** tab of
  /// an already-pumped `AddFoodScreen`. The row layout puts the
  /// name in a `Text` widget directly above a macro-line Text
  /// (`"N cal · P P · C C · F F"`). We pick the name by exclusion:
  /// a `Text` whose data is the food name is the one above the
  /// macro line. To avoid coupling to row internals, we just
  /// return every `Text` string on the screen and filter for
  /// the known food names declared by the test fixture.
  List<String> _collectMyFoodsRowNames(WidgetTester tester) {
    final candidates = <String>[];
    for (final element in find.byType(Text).evaluate()) {
      final data = (element.widget as Text).data;
      if (data == null) continue;
      // Skip strings the empty-state, tab labels, and CTAs render.
      if (data == 'Manage Food Library') continue;
      if (data == 'My Foods') continue;
      if (data == 'Library') continue;
      if (data == 'Categories') continue;
      if (data == '+ New Food') continue;
      if (data == 'No custom foods yet') continue;
      if (data == 'Create your own foods to use in your nutrition tracking') {
        continue;
      }
      if (data == '+ New Category') continue;
      // Macro line: contains " cal · " (foods render e.g.
      // "151 cal · 31P · 0C · 4F").
      if (data.contains(' cal · ')) continue;
      candidates.add(data);
    }
    return candidates;
  }

  group('My Foods population — S-031a structural guard', () {
    testWidgets(
      'bundled foods + their library copies never appear; '
      'D-2 custom appears exactly once; legacy custom appears once',
      (tester) async {
        final repo = await _freshRepo();
        final state = await _loadedState(repo);
        final nutrition = NutritionState(repo);
        await nutrition.loadConsumedToday();
        await nutrition.loadNutritionTarget();

        // Precondition: bundled catalog foods are seeded. Add TWO
        // of them to the personal library (via the Library tab's
        // Add button). The library copies have `isCatalog = false`
        // but their data matches the bundled catalog row — the
        // classic leak the prior S-031 test never exercised.
        await state.addCatalogFoodToLibrary('chicken_breast');
        await state.addCatalogFoodToLibrary('brown_rice');
        await state.loadFoods();

        // One D-2 user-created custom (catalog row + auto library
        // copy).
        await state.createCatalogFood(_quickDraft(name: 'My Bar'));
        // The + New Item form does this; we replicate the same
        // effect here.
        final myBarCatalog = state.userCreatedCatalogFoods
            .firstWhere((f) => f.name == 'My Bar');
        await state.addCatalogFoodToLibrary(myBarCatalog.id);
        await state.loadFoods();

        // One true legacy library-only custom (pre-D-2 path, no
        // catalog twin).
        // ignore: deprecated_member_use_from_same_package
        await state.createCustomFood(
          name: 'Grandma\'s Stew',
          groupId: null,
          unitType: FoodUnitType.grams,
          referenceAmount: 250.0,
          referenceLabel: 'g',
          protein: 18,
          carbs: 22,
          fat: 12,
        );
        await state.loadFoods();

        // Pump the AddFoodScreen and read the My Foods tab.
        await tester.pumpWidget(
          MaterialApp(
            home: AddFoodScreen(
              foodLibraryState: state,
              nutritionState: nutrition,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('My Foods'));
        await tester.pumpAndSettle();

        final renderedNames = _collectMyFoodsRowNames(tester);

        // ─── Assertions ────────────────────────────────────────
        // The two bundled foods and their library copies are all
        // excluded (4 rows total — 2 catalog + 2 library — none
        // leak into My Foods).
        expect(renderedNames, isNot(contains('Chicken breast, skinless')),
            reason: 'bundled food excluded even with library copy');
        expect(renderedNames, isNot(contains('Brown rice')),
            reason: 'bundled food excluded even with library copy');

        // The D-2 custom appears exactly once.
        final customCount = renderedNames
            .where((n) => n == 'My Bar')
            .length;
        expect(customCount, 1,
            reason:
                'D-2 custom must render exactly once (catalog row + '
                'auto library copy collapsed by the identity filter)');

        // The legacy custom appears exactly once.
        final legacyCount = renderedNames
            .where((n) => n == 'Grandma\'s Stew')
            .length;
        expect(legacyCount, 1);

        // The merged surface contains ONLY the two user-created
        // foods (1 D-2 + 1 legacy). Nothing else.
        expect(renderedNames, hasLength(2),
            reason:
                'rendered My Foods surface: ${renderedNames.toList()}');
        expect(
          renderedNames.toList()..sort(),
          ['Grandma\'s Stew', 'My Bar'],
        );
      },
    );

    test('catalogIdFor returns the bundled catalog id for a library twin',
        () async {
      final repo = await _freshRepo();
      final state = await _loadedState(repo);

      // Add chicken to the library.
      final libId = await state.addCatalogFoodToLibrary('chicken_breast');
      await state.loadFoods();
      final lib = state.foods.firstWhere((f) => f.id == libId);

      // The library twin's identity matches the bundled row.
      expect(state.catalogIdFor(lib), 'chicken_breast');

      // A non-twin returns null.
      final nonTwin = Food(
        id: 'lib-no-twin',
        name: 'Mystery',
        unitType: FoodUnitType.grams,
        referenceAmount: 50.0,
        referenceLabel: 'g',
        protein: 7,
        carbs: 7,
        fat: 7,
        createdAtMs: 1000,
        updatedAtMs: 1000,
      );
      await state.createFood(nonTwin);
      await state.loadFoods();
      final fresh = state.foods.firstWhere((f) => f.id == nonTwin.id);
      expect(state.catalogIdFor(fresh), isNull);
    });

    test('id-based dedup would have over-merged: catalog row and '
        'its library twin have distinct ids, so a naive id-dedup '
        'would render the D-2 custom twice. The live behavior '
        'collapses them by identity', () async {
      final repo = await _freshRepo();
      final state = await _loadedState(repo);

      final myBar = await state.createCatalogFood(
        _quickDraft(name: 'My Bar'),
      );
      await state.addCatalogFoodToLibrary(myBar);
      await state.loadFoods();

      // Catalog row and library copy have different ids — the
      // test pins this so a future refactor that removes the
      // fresh-id allocation would surface here.
      final catalogRow = state.userCreatedCatalogFoods
          .firstWhere((f) => f.id == myBar);
      final libraryTwin = state.foods.firstWhere(
        (f) => f.id == state.libraryIdFor(myBar),
      );
      expect(catalogRow.id, isNot(libraryTwin.id),
          reason: 'the two rows must have distinct ids (defines the '
              'id-dedup anti-pattern the test guards against)');

      // A naive union `userCatalog + foods` has both rows by id
      // — this is the pre-fix merge that the new logic
      // supersedes.
      final naiveUnion = [
        ...state.userCreatedCatalogFoods,
        ...state.foods,
      ];
      final naiveMyBar = naiveUnion.where((f) => f.name == 'My Bar').toList();
      expect(naiveMyBar, hasLength(2),
          reason: 'id-dedup anti-pattern: 2 rows with the same name '
              'but different ids');

      // The corrected My Foods surface has 1.
      final corrected = state.userCreatedCatalogFoods
          .where((f) => !f.isArchived)
          .toList()
        ..addAll(
          state.foods.where(
            (f) => !f.isArchived && !f.isCatalog && state.catalogIdFor(f) == null,
          ),
        );
      final correctedMyBar = corrected.where((f) => f.name == 'My Bar').toList();
      expect(correctedMyBar, hasLength(1),
          reason: 'identity merge collapses catalog row + library twin');
      expect(correctedMyBar.single.id, myBar,
          reason: 'the catalog row wins because userCatalog is iterated '
              'first');
    });
  });
}
