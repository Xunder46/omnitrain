// test/nutrition_search_screen_test.dart
//
// Plan 256: the Daily Nutrition search with "Add & log". These tests
// pin the screen behaviour of S-25601..S-25612: the search box above
// the list and above the empty state, the filtered Foods I Eat rows,
// the "From the catalog" section, and Add & log writing the food and
// its first portion onto the viewed day.
//
// Mock repository ONLY: a Hive write inside `testWidgets` never
// settles. Every fixture write happens before `pumpWidget`, awaited,
// outside any `Future.delayed`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/nutrition/nutrition_screen.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';

import 'helpers/test_nutrition_primer_state.dart';

final DateTime _now = DateTime(2026, 11, 18, 10);
final DateTime _today = DateTime(2026, 11, 18);
final DateTime _yesterday = DateTime(2026, 11, 17);

int _ms(DateTime d) => d.millisecondsSinceEpoch;

String _nn(int i) => i.toString().padLeft(2, '0');

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  // Wipe the seed consumed-foods so the day-log is empty.
  repo.clearConsumedFoodsForTest();
  return repo;
}

/// Rice: 100 g, 10P/10C/10F = 170 kcal per 100 g.
Food _rice() => Food(
  id: 'f-rice',
  name: 'Rice',
  unitType: FoodUnitType.grams,
  referenceAmount: 100,
  referenceLabel: 'g',
  protein: 10,
  carbs: 10,
  fat: 10,
  createdAtMs: 1000,
  updatedAtMs: 1000,
);

/// Egg: 1 egg, 6P/1C/5F = 73 kcal.
Food _egg() => Food(
  id: 'f-egg',
  name: 'Egg',
  unitType: FoodUnitType.count,
  referenceAmount: 1,
  referenceLabel: '1 egg',
  protein: 6,
  carbs: 1,
  fat: 5,
  createdAtMs: 1000,
  updatedAtMs: 1000,
);

/// A plan-247 consumed row: a logged food on [day], snapshot of the
/// food's values at log time (used for a food no longer in the library).
ConsumedFood _row(String id, Food food, double amount, DateTime day) =>
    ConsumedFood(
      id: id,
      loggedAtMs: _ms(day) + 3600000,
      dateMs: _ms(day),
      sourceFoodId: food.id,
      name: food.name,
      unitType: food.unitType,
      referenceAmount: food.referenceAmount,
      referenceLabel: food.referenceLabel,
      protein: food.protein,
      carbs: food.carbs,
      fat: food.fat,
      amountConsumed: amount,
      targetCalories: 2000,
      targetProtein: 0,
      targetCarbs: 0,
      targetFat: 0,
      createdAtMs: 1000,
      updatedAtMs: 1000,
    );

/// A plan-256 catalog fixture, written straight into the repository
/// BEFORE the screen loads the catalog.
Food _catalogFood(
  String id,
  String name, {
  required FoodUnitType unitType,
  required double referenceAmount,
  required String referenceLabel,
  required double protein,
  required double carbs,
  required double fat,
}) => Food(
  id: id,
  name: name,
  unitType: unitType,
  referenceAmount: referenceAmount,
  referenceLabel: referenceLabel,
  protein: protein,
  carbs: carbs,
  fat: fat,
  createdAtMs: 1000,
  updatedAtMs: 1000,
);

/// The catalog fixtures the scenarios search in. The Mock cannot clear
/// its bundled seed catalog (`initialize()` loads
/// `FoodCatalogSeed.sampleCatalogFoods`), so a query like `che` or
/// `egg` also matches seed names (`Cheddar cheese`, `Egg, large`, ...):
/// the tests below assert on these fixtures' keys and unique names,
/// not on row counts.
/// Seeds extra catalog fixtures (S-25611's 25 `Zed Food` rows,
/// S-25610b's `Bread slices`), written with `repo.createCatalogFood`
/// BEFORE the screen loads the catalog.
Future<void> _seedExtraCatalog(MockWorkoutRepository repo) async {
  await repo.createCatalogFood(
    _catalogFood(
      'c-bread',
      'Bread slices',
      unitType: FoodUnitType.count,
      referenceAmount: 2,
      referenceLabel: '2 slices',
      protein: 8,
      carbs: 40,
      fat: 2,
    ),
  );
  for (var i = 1; i <= 25; i++) {
    final nn = _nn(i);
    await repo.createCatalogFood(
      _catalogFood(
        'zed-food-$nn',
        'Zed Food $nn',
        unitType: FoodUnitType.grams,
        referenceAmount: 100,
        referenceLabel: 'g',
        protein: 10,
        carbs: 10,
        fat: 10,
      ),
    );
  }
}

Future<void> _seedCatalog(MockWorkoutRepository repo) async {
  await repo.createCatalogFood(
    _catalogFood(
      'c-cheddar',
      'Cheddar',
      unitType: FoodUnitType.grams,
      referenceAmount: 100,
      referenceLabel: 'g',
      protein: 25,
      carbs: 1,
      fat: 33,
    ),
  );
  await repo.createCatalogFood(
    _catalogFood(
      'c-cream',
      'Cream cheese',
      unitType: FoodUnitType.grams,
      referenceAmount: 100,
      referenceLabel: 'g',
      protein: 6,
      carbs: 4,
      fat: 34,
    ),
  );
  await repo.createCatalogFood(
    _catalogFood(
      'c-noodle',
      'Egg noodles',
      unitType: FoodUnitType.grams,
      referenceAmount: 100,
      referenceLabel: 'g',
      protein: 14,
      carbs: 71,
      fat: 4,
    ),
  );
  await repo.createCatalogFood(
    _catalogFood(
      'c-egg2',
      'Egg roll',
      unitType: FoodUnitType.count,
      referenceAmount: 1,
      referenceLabel: '1 roll',
      protein: 8,
      carbs: 20,
      fat: 9,
    ),
  );
  // The catalog twin of the library egg: the same identity, so the
  // value-based fallback also sees it as already in the library.
  await repo.createCatalogFood(
    _catalogFood(
      'c-egg',
      'Egg',
      unitType: FoodUnitType.count,
      referenceAmount: 1,
      referenceLabel: '1 egg',
      protein: 6,
      carbs: 1,
      fat: 5,
    ),
  );
}

/// Builds the two states the screen needs and pumps `NutritionScreen`
/// (600x1200 by default; pass [surface] for a taller one, e.g. the
/// 600x4000 S-25611 uses so all capped catalog rows are laid out).
/// [library] `both` puts Rice and the catalog-linked Egg into Foods I
/// Eat, `egg` only the Egg (S-25612), `none` leaves the library empty
/// (S-25608). [seedExtra] runs
/// after `_seedCatalog` and before `loadCatalogFoods()`.
Future<FoodLibraryState> _pumpNutritionScreen(
  WidgetTester tester, {
  required MockWorkoutRepository repo,
  String library = 'both',
  Size surface = const Size(600, 1200),
  Future<void> Function(MockWorkoutRepository repo)? seedExtra,
}) async {
  final foodLibraryState = FoodLibraryState(repo);
  if (library == 'both') {
    await foodLibraryState.createFood(_rice());
    // `FoodLibraryState.createFood` does not carry `catalogId` through,
    // so the linked library egg goes through the repository write and a
    // reload; `isInLibrary('c-egg')` then matches on the durable link.
    await repo.createFood(_egg().copyWith(catalogId: 'c-egg'));
    await foodLibraryState.loadFoods();
  } else if (library == 'egg') {
    await foodLibraryState.createFood(_egg());
    await foodLibraryState.loadFoods();
  }
  await _seedCatalog(repo);
  if (seedExtra != null) {
    await seedExtra(repo);
  }
  await foodLibraryState.loadCatalogFoods();

  final nutritionState = NutritionState(repo, clock: () => _now);
  await nutritionState.loadConsumedToday();
  await nutritionState.loadWaterForToday();
  await nutritionState.loadNutritionTarget();

  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final primer = await buildNutritionPrimerState(repo, seen: true);
  await tester.pumpWidget(
    MaterialApp(
      home: NutritionScreen(
        nutritionState: nutritionState,
        foodLibraryState: foodLibraryState,
        nutritionPrimerState: primer,
      ),
    ),
  );
  // Allow initState's loads (target + consumed + water + library) to settle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return foodLibraryState;
}

/// Types into the search box and lets the rebuild land.
Future<void> _search(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('nutrition_search_field')), text);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// Taps an Add & log button and lets the async write land (never
/// `pumpAndSettle`: the snack bar's dismiss timer would run to the end
/// and take the message away before it can be asserted).
Future<void> _tapAdd(WidgetTester tester, Key key) async {
  await tester.tap(find.byKey(key));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

String _searchText(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const Key('nutrition_search_field')))
    .controller!
    .text;

/// Any widget keyed like an Add & log button (`nutrition_search_add_*`).
Finder get _addAndLogButtons => find.byWidgetPredicate(
  (w) =>
      w.key is ValueKey<String> &&
      (w.key as ValueKey<String>).value.startsWith('nutrition_search_add_'),
);

void main() {
  group('plan 256: nutrition search screen', () {
    testWidgets(
      'S-25601: no query — the screen is as before, no catalog section',
      (tester) async {
        final repo = await _freshRepo();
        await _pumpNutritionScreen(tester, repo: repo);

        expect(find.byKey(const Key('nutrition_search_field')), findsOneWidget);
        expect(find.text('From the catalog'), findsNothing);
        expect(find.text('Rice'), findsOneWidget);
        expect(find.text('Egg'), findsOneWidget);
      },
    );

    testWidgets('S-25602: `ric` filters Foods I Eat to Rice', (tester) async {
      final repo = await _freshRepo();
      await _pumpNutritionScreen(tester, repo: repo);

      await _search(tester, 'ric');

      expect(find.text('Rice'), findsOneWidget);
      expect(find.text('Egg'), findsNothing);
      // Deviation from the plan table (the brief allows it): the bundled
      // seed catalog carries `White rice, cooked` and `Brown rice,
      // cooked`, so a `From the catalog` section does show for `ric`.
      // The catalog side is asserted on our fixtures' keys instead.
      expect(find.text('From the catalog'), findsOneWidget);
      expect(
        find.byKey(const Key('nutrition_search_add_c-cheddar')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('nutrition_search_add_c-cream')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('nutrition_search_add_c-noodle')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('nutrition_search_add_c-egg2')),
        findsNothing,
      );
      expect(find.byKey(const Key('nutrition_search_add_c-egg')), findsNothing);
    });

    testWidgets(
      'S-25603: `  CHE ` matches the catalog, trimmed, alphabetical',
      (tester) async {
        final repo = await _freshRepo();
        await _pumpNutritionScreen(tester, repo: repo);

        await _search(tester, '  CHE ');

        expect(
          find.byKey(const Key('nutrition_search_catalog_heading')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('nutrition_search_add_c-cheddar')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('nutrition_search_add_c-cream')),
          findsOneWidget,
        );

        // Cheddar sorts before Cream cheese (the seed's `Cheddar cheese`
        // row sorts between them and does not collide with our name).
        final cheddarTop = tester.getTopLeft(find.text('Cheddar')).dy;
        final creamTop = tester
            .getTopLeft(find.byKey(const Key('nutrition_search_add_c-cream')))
            .dy;
        expect(cheddarTop, lessThan(creamTop));

        // No library row shows: neither Egg nor Rice contains `che`.
        expect(find.text('Egg'), findsNothing);
        expect(find.text('Rice'), findsNothing);
      },
    );

    testWidgets(
      'S-25604: `egg` — the library Egg once, no second Egg offered',
      (tester) async {
        final repo = await _freshRepo();
        await _pumpNutritionScreen(tester, repo: repo);

        await _search(tester, 'egg');

        expect(find.text('Egg'), findsOneWidget);
        expect(find.text('Egg noodles'), findsOneWidget);
        expect(find.text('Egg roll'), findsOneWidget);
        expect(
          find.byKey(const Key('nutrition_search_add_c-egg')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'S-25605: `zzz` — the no-match empty state, no Add & log buttons',
      (tester) async {
        final repo = await _freshRepo();
        await _pumpNutritionScreen(tester, repo: repo);

        await _search(tester, 'zzz');

        expect(find.text('No foods match "zzz"'), findsOneWidget);
        expect(_addAndLogButtons, findsNothing);
        expect(find.text('Rice'), findsNothing);
        expect(find.text('Egg'), findsNothing);
      },
    );

    testWidgets(
      'S-25606: Add & log on Cheddar adds it, logs 100 g today, clears',
      (tester) async {
        final repo = await _freshRepo();
        final foodLibraryState = await _pumpNutritionScreen(tester, repo: repo);

        await _search(tester, 'che');
        await _tapAdd(tester, const Key('nutrition_search_add_c-cheddar'));

        expect(
          foodLibraryState.foods.where(
            (f) => f.name == 'Cheddar' && f.catalogId == 'c-cheddar',
          ),
          isNotEmpty,
        );
        final today = await repo.getConsumedFoodsForDate(_ms(_today));
        final cheddar = today.singleWhere((r) => r.name == 'Cheddar');
        expect(cheddar.amountConsumed, 100);
        expect(_searchText(tester), '');
        expect(find.text('Added to Foods I Eat and logged'), findsOneWidget);
      },
    );

    testWidgets('S-25607: Add & log on yesterday logs the viewed day', (
      tester,
    ) async {
      final repo = await _freshRepo();
      await _pumpNutritionScreen(tester, repo: repo);

      await tester.tap(find.byKey(const Key('nutrition_day_prev')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await _search(tester, 'che');
      await _tapAdd(tester, const Key('nutrition_search_add_c-cheddar'));

      final yesterday = await repo.getConsumedFoodsForDate(_ms(_yesterday));
      expect(yesterday.where((r) => r.name == 'Cheddar'), isNotEmpty);
      final today = await repo.getConsumedFoodsForDate(_ms(_today));
      expect(today.where((r) => r.name == 'Cheddar'), isEmpty);
    });

    testWidgets(
      'S-25608: an empty library can search, Add & log fills the list',
      (tester) async {
        final repo = await _freshRepo();
        final foodLibraryState = await _pumpNutritionScreen(
          tester,
          repo: repo,
          library: 'none',
        );

        // The box sits above the "Pick the foods you eat" prompt.
        expect(find.byKey(const Key('nutrition_search_field')), findsOneWidget);
        expect(find.text('Pick the foods you eat'), findsOneWidget);
        final fieldTop = tester
            .getTopLeft(find.byKey(const Key('nutrition_search_field')))
            .dy;
        final promptTop = tester
            .getTopLeft(find.text('Pick the foods you eat'))
            .dy;
        expect(fieldTop, lessThan(promptTop));
        expect(foodLibraryState.foods, isEmpty);

        await _search(tester, 'che');
        await _tapAdd(tester, const Key('nutrition_search_add_c-cheddar'));

        expect(find.text('Pick the foods you eat'), findsNothing);
        expect(find.text('Cheddar'), findsOneWidget);
      },
    );

    testWidgets('S-25609: the clear button restores the full list', (
      tester,
    ) async {
      final repo = await _freshRepo();
      await _pumpNutritionScreen(tester, repo: repo);

      await _search(tester, 'che');
      expect(find.byKey(const Key('nutrition_search_clear')), findsOneWidget);

      await tester.tap(find.byKey(const Key('nutrition_search_clear')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(_searchText(tester), '');
      expect(find.text('Rice'), findsOneWidget);
      expect(find.text('Egg'), findsOneWidget);
    });

    testWidgets('S-25610: a count food logs 1, not its reference amount', (
      tester,
    ) async {
      final repo = await _freshRepo();
      await _pumpNutritionScreen(tester, repo: repo);

      await _search(tester, 'egg roll');
      await _tapAdd(tester, const Key('nutrition_search_add_c-egg2'));

      final today = await repo.getConsumedFoodsForDate(_ms(_today));
      final roll = today.singleWhere((r) => r.name == 'Egg roll');
      expect(roll.amountConsumed, 1.0);
      expect(roll.unitType, FoodUnitType.count);
    });

    testWidgets(
      'S-25610b: a count food with reference amount 2 logs 1 serving',
      (tester) async {
        final repo = await _freshRepo();
        await _pumpNutritionScreen(
          tester,
          repo: repo,
          seedExtra: _seedExtraCatalog,
        );

        // `bread slices` matches only our fixture: the seed's bread
        // rows (`White bread`, `Whole wheat bread`, `Pita bread`,
        // `Sourdough bread`) do not contain the phrase.
        await _search(tester, 'bread slices');
        await _tapAdd(tester, const Key('nutrition_search_add_c-bread'));

        final today = await repo.getConsumedFoodsForDate(_ms(_today));
        final bread = today.singleWhere((r) => r.name == 'Bread slices');
        expect(bread.amountConsumed, 1.0);
        expect(bread.unitType, FoodUnitType.count);
      },
    );

    testWidgets(
      'S-25611: the catalog section caps at 20 rows, first 20 alphabetically',
      (tester) async {
        final repo = await _freshRepo();
        await _pumpNutritionScreen(
          tester,
          repo: repo,
          // Tall enough that every capped row is laid out in the
          // viewport, so the button finders see them all.
          surface: const Size(600, 4000),
          seedExtra: _seedExtraCatalog,
        );

        // `zed food` matches nothing in Foods I Eat (Rice, Egg) and
        // nothing in the bundled seed catalog: only our 25 Zed rows.
        await _search(tester, 'zed food');

        expect(
          find.byKey(const Key('nutrition_search_catalog_heading')),
          findsOneWidget,
        );
        // Exactly the 20-row cap is on screen.
        expect(_addAndLogButtons, findsNWidgets(20));
        // They are the first 20 alphabetically: Zed Food 01..20.
        for (var i = 1; i <= 20; i++) {
          expect(
            find.byKey(Key('nutrition_search_add_zed-food-${_nn(i)}')),
            findsOneWidget,
            reason: 'Zed Food ${_nn(i)} must be shown (first 20 alphabetically)',
          );
        }
        // The cap hides rows 21..25.
        for (var i = 21; i <= 25; i++) {
          expect(
            find.byKey(Key('nutrition_search_add_zed-food-${_nn(i)}')),
            findsNothing,
            reason: 'Zed Food ${_nn(i)} must be beyond the 20-row cap',
          );
        }
      },
    );

    testWidgets(
      'S-25612: removed-food rows are not shown while a search is typed',
      (tester) async {
        final repo = await _freshRepo();
        await _pumpNutritionScreen(
          tester,
          repo: repo,
          // Library holds Egg only: today's Rice row is a removed food.
          library: 'egg',
          seedExtra:
              (repo) async =>
                  repo.createConsumedFood(_row('c-rm', _rice(), 200, _today)),
        );

        // No query: the plan-247 removed-foods section shows for the
        // logged Rice whose library food is gone.
        expect(find.text('No longer in Foods I Eat'), findsOneWidget);
        expect(find.text('Rice'), findsOneWidget);
        expect(find.text('Egg'), findsOneWidget);

        await _search(tester, 'egg');

        // The removed-foods block is hidden while a query is typed.
        expect(find.text('No longer in Foods I Eat'), findsNothing);
        expect(find.text('Rice'), findsNothing);
        // The library egg still matches.
        expect(find.text('Egg'), findsOneWidget);

        // Clearing brings the section back.
        await tester.tap(find.byKey(const Key('nutrition_search_clear')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('No longer in Foods I Eat'), findsOneWidget);
        expect(find.text('Rice'), findsOneWidget);
      },
    );
  });
}
