// Widget-level tests for the picker polish (plan 78, scenarios
// S-13110..S-13118): the fixed Library heading order, the count line
// under the search field, the + New Food CTA, the remove prompt
// title, the empty-ring hint, the primer copy, the Library tab
// keeping its place and search across tab switches, and typing an
// amount on an unlogged row logging it on Done.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/food_draft.dart';
import 'package:omnitrain/core/utils/foods_i_eat_order.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/nutrition/add_food_screen.dart';
import 'package:omnitrain/features/nutrition/nutrition_screen.dart';
import 'package:omnitrain/features/nutrition/widgets/log_food_row.dart';
import 'package:omnitrain/features/nutrition/widgets/nutrition_primer_sheet.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';

import 'helpers/test_nutrition_primer_state.dart';

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  repo.clearConsumedFoodsForTest();
  return repo;
}

/// The vertically-scrolling list on a screen.
///
/// The screen carries other scrollables above its content; match on
/// axis instead of position.
final Finder _verticalScrollable = find.byWidgetPredicate(
  (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
);

/// The titles of the category headings currently built, in tree order.
List<String> _builtHeadingTitles(WidgetTester tester) {
  return tester
      .widgetList(
        find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key as ValueKey<String>).value.startsWith('library_section_'),
        ),
      )
      .map(
        (w) => (w.key as ValueKey<String>).value.substring(
          'library_section_'.length,
        ),
      )
      .toList();
}

/// Drag the vertical list until no new heading keys appear.
Future<void> _scrollToBottom(WidgetTester tester) async {
  var previous = <String>[];
  for (var i = 0; i < 60; i++) {
    await tester.drag(_verticalScrollable, const Offset(0, -2000));
    await tester.pumpAndSettle();
    final titles = _builtHeadingTitles(tester);
    if (titles.length == previous.length &&
        titles.isEmpty == previous.isEmpty) {
      // A page with no new content: the list has stopped growing.
      if (titles.isNotEmpty && titles.last == previous.last) break;
    }
    previous = titles;
  }
}

/// Pump the AddFoodScreen for the Library tab with the categories
/// loaded (as the nutrition screen does in the app).
Future<({NutritionState nutrition, FoodLibraryState foodLib})>
_pumpCatalogTab(WidgetTester tester, {MockWorkoutRepository? repo}) async {
  final r = repo ?? await _freshRepo();
  final nutrition = NutritionState(r);
  final foodLib = FoodLibraryState(r);
  await tester.binding.setSurfaceSize(const Size(800, 6000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await foodLib.loadFoodGroups();
  await foodLib.loadFoods();
  await foodLib.loadCatalogFoods();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AddFoodScreen(
          nutritionState: nutrition,
          foodLibraryState: foodLib,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (nutrition: nutrition, foodLib: foodLib);
}

/// Pump the NutritionScreen with the primer already seen (as
/// `test/first_run_path_test.dart` does).
Future<({NutritionState nutrition, FoodLibraryState foodLib})>
_pumpNutritionScreen(WidgetTester tester, MockWorkoutRepository repo) async {
  final primer = await buildNutritionPrimerState(repo, seen: true);
  final nutritionState = NutritionState(repo);
  final foodLibraryState = FoodLibraryState(repo);
  await foodLibraryState.loadFoodGroups();
  await foodLibraryState.loadFoods();

  await tester.pumpWidget(
    MaterialApp(
      home: NutritionScreen(
        nutritionState: nutritionState,
        foodLibraryState: foodLibraryState,
        nutritionPrimerState: primer,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (nutrition: nutritionState, foodLib: foodLibraryState);
}

/// Pump a single [LogFoodRow] the way
/// `test/row_caption_and_primer_test.dart` does.
Future<NutritionState> _pumpLogFoodRow(
  WidgetTester tester,
  MockWorkoutRepository repo,
  Food food,
) async {
  final nutrition = NutritionState(repo);
  final foodLib = FoodLibraryState(repo);
  await nutrition.loadConsumedToday();
  await foodLib.loadFoodGroups();
  await foodLib.loadFoods();

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            LogFoodRow(
              food: food,
              nutritionState: nutrition,
              foodLibraryState: foodLib,
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return nutrition;
}

/// A 100 g food with values unlike every default; the amount box
/// shows its default 100.
Future<Food> _seedGramFood(MockWorkoutRepository repo) async {
  const now = 1700000000000;
  await repo.createFoodGroup(
    const FoodGroup(
      id: 'g-typing-13118',
      name: 'Typing 13118',
      createdAtMs: now,
      updatedAtMs: now,
    ),
  );
  await repo.createFood(
    const Food(
      id: 'f-typing-13118',
      name: 'Typing Food (13118)',
      unitType: FoodUnitType.grams,
      groupId: 'g-typing-13118',
      referenceAmount: 100.0,
      referenceLabel: 'g',
      protein: 23,
      carbs: 7,
      fat: 3,
      createdAtMs: now,
      updatedAtMs: now,
    ),
  );
  return (await repo.getFoodById('f-typing-13118'))!;
}

void main() {
  group('Picker polish (plan 78 S-13110..S-13118)', () {
    testWidgets('S-13110: real catalog, empty search — the fixed heading '
        'order leads, a created category sorts after the listed ones and '
        'before Uncategorized', (tester) async {
      final repo = await _freshRepo();
      final states = await _pumpCatalogTab(tester, repo: repo);
      final foodLib = states.foodLib;

      expect(
        _builtHeadingTitles(tester).take(4),
        ['Proteins', 'Dairy', 'Grains & Starches', 'Fruits'],
      );

      // A user-created category with a created food in it.
      final groupId = await foodLib.createFoodGroup('Aaa 78');
      await foodLib.createCatalogFood(
        FoodDraft(
          name: 'Aaa 78 food',
          groupId: groupId,
          unitType: FoodUnitType.grams,
          referenceAmount: 100,
          referenceLabel: 'g',
          protein: 23,
          carbs: 7,
          fiber: null,
          fat: 3,
          sodium: null,
          notes: null,
          imagePath: null,
        ),
      );
      await tester.pumpAndSettle();

      await _scrollToBottom(tester);
      final titles = _builtHeadingTitles(tester);
      expect(titles, contains('Aaa 78'));
      // After every listed category (Condiments is the last listed).
      expect(
        titles.indexOf('Aaa 78'),
        greaterThan(titles.indexOf('Condiments')),
      );
      // Uncategorized (when present) is still last.
      if (titles.contains('Uncategorized')) {
        expect(
          titles.indexOf('Uncategorized'),
          greaterThan(titles.indexOf('Aaa 78')),
        );
      }
    });

    testWidgets('S-13111: foodsIEatSections stays alphabetical', (
      tester,
    ) async {
      final repo = await _freshRepo();
      final states = await _pumpCatalogTab(tester, repo: repo);
      final foodLib = states.foodLib;

      final sections = foodsIEatSections(
        foods: foodLib.catalogFoods,
        groups: foodLib.activeFoodGroups,
      );
      final names = foodLib.activeFoodGroups.map((g) => g.name).toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      expect(sections, isNotEmpty);
      expect(sections.first.title, names.first);
    });

    testWidgets('S-13112: the count line under the search field follows '
        'the library size', (tester) async {
      final repo = await _freshRepo();
      final states = await _pumpCatalogTab(tester, repo: repo);
      final foodLib = states.foodLib;

      expect(find.byKey(const Key('library_count_line')), findsOneWidget);
      expect(find.text('No foods in your list yet'), findsOneWidget);

      await foodLib.addCatalogFoodToLibrary('chicken_breast');
      await tester.pumpAndSettle();
      expect(find.text('1 food in your list'), findsOneWidget);

      await foodLib.addCatalogFoodToLibrary('white_rice');
      await foodLib.addCatalogFoodToLibrary('banana');
      await tester.pumpAndSettle();
      expect(find.text('3 foods in your list'), findsOneWidget);

      final libId = foodLib.libraryIdFor('chicken_breast');
      expect(libId, isNotNull);
      await foodLib.removeFood(libId!);
      await tester.pumpAndSettle();
      expect(find.text('2 foods in your list'), findsOneWidget);
    });

    testWidgets('S-13113: the Library CTA reads + New Food', (tester) async {
      await _pumpCatalogTab(tester);

      expect(find.text('+ New Food'), findsOneWidget);
      expect(find.text('+ Create new food'), findsNothing);
    });

    testWidgets('S-13114: the remove prompt names Foods I Eat', (
      tester,
    ) async {
      await _pumpCatalogTab(tester);

      await tester.enterText(
        find.byKey(const Key('catalog_search_field')),
        'Chicken breast',
      );
      await tester.pumpAndSettle();
      expect(find.text('Chicken breast, skinless'), findsOneWidget);

      // Add by row tap, then tap again: the remove dialog names the
      // food.
      await tester.tap(find.text('Chicken breast, skinless'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chicken breast, skinless'));
      await tester.pumpAndSettle();

      expect(
        find.text('Remove Chicken breast, skinless from Foods I Eat?'),
        findsOneWidget,
      );
    });

    testWidgets('S-13115: the empty ring hints to pick foods until the '
        'list has one', (tester) async {
      final repo = await _freshRepo();
      final states = await _pumpNutritionScreen(tester, repo);
      final foodLib = states.foodLib;

      expect(find.text('Pick your foods to get started'), findsOneWidget);
      expect(find.text('Log a food to start filling'), findsNothing);

      await foodLib.addCatalogFoodToLibrary('chicken_breast');
      await tester.pumpAndSettle();

      expect(find.text('Log a food to start filling'), findsOneWidget);
      expect(find.text('Pick your foods to get started'), findsNothing);
    });

    testWidgets('S-13116: the primer copy speaks in user terms', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: NutritionPrimerSheet())),
      );

      expect(find.textContaining('Choose foods'), findsOneWidget);
      expect(find.text('TAP TO LOG, SET THE AMOUNT'), findsOneWidget);
      expect(find.textContaining('edit control'), findsNothing);
      expect(find.textContaining('check off'), findsNothing);
    });

    testWidgets('S-13117: the Library tab keeps its place and its search '
        'across tab switches', (tester) async {
      await _pumpCatalogTab(tester);

      // Scroll to the bottom and note where we are.
      await _scrollToBottom(tester);
      final lastBefore = _builtHeadingTitles(tester).last;

      // Round trip to Categories and back.
      await tester.tap(find.text('Categories'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();

      final titlesAfter = _builtHeadingTitles(tester);
      expect(titlesAfter, isNotEmpty);
      // Still scrolled down: the first built heading is not the top
      // of the list, and the heading we scrolled to is still built.
      expect(titlesAfter.first, isNot('Proteins'));
      expect(titlesAfter, contains(lastBefore));

      // A search typed before a round trip survives it.
      await tester.enterText(
        find.byKey(const Key('catalog_search_field')),
        'Chicken',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Categories'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
        find.byKey(const Key('catalog_search_field')),
      );
      expect(field.controller!.text, 'Chicken');
    });

    testWidgets('S-13118a: typing a new amount and pressing Done logs the '
        'unlogged food with that amount', (tester) async {
      final repo = await _freshRepo();
      final food = await _seedGramFood(repo);
      final nutrition = await _pumpLogFoodRow(tester, repo, food);

      expect(nutrition.isFoodLoggedToday(food.id), isFalse);
      expect(find.text('100'), findsOneWidget);

      await tester.enterText(
        find.byKey(Key('log_food_amount_${food.id}')),
        '250',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(nutrition.isFoodLoggedToday(food.id), isTrue);
      expect(nutrition.findLoggedTodayForFood(food.id)!.amountConsumed, 250);
    });

    testWidgets('S-13118b: Done on an untouched amount logs nothing', (
      tester,
    ) async {
      final repo = await _freshRepo();
      final food = await _seedGramFood(repo);
      final nutrition = await _pumpLogFoodRow(tester, repo, food);

      await tester.tap(find.byKey(Key('log_food_amount_${food.id}')));
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(nutrition.isFoodLoggedToday(food.id), isFalse);
    });

    testWidgets('S-13118c: typing the shown value back and pressing Done '
        'logs nothing', (tester) async {
      final repo = await _freshRepo();
      final food = await _seedGramFood(repo);
      final nutrition = await _pumpLogFoodRow(tester, repo, food);

      await tester.enterText(
        find.byKey(Key('log_food_amount_${food.id}')),
        '250',
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(Key('log_food_amount_${food.id}')),
        '100',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(nutrition.isFoodLoggedToday(food.id), isFalse);
    });

    testWidgets('S-13118d: Done on 0 logs nothing and shows the error', (
      tester,
    ) async {
      final repo = await _freshRepo();
      final food = await _seedGramFood(repo);
      final nutrition = await _pumpLogFoodRow(tester, repo, food);

      await tester.enterText(
        find.byKey(Key('log_food_amount_${food.id}')),
        '0',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(nutrition.isFoodLoggedToday(food.id), isFalse);
      expect(find.text('Amount must be greater than 0'), findsOneWidget);
    });
  });
}
