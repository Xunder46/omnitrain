// Widget-level tests for the Library category headings (plan 77b2,
// scenarios S-12820..S-12824): with an empty search box the Library
// list shows category headings in the fixed first-run order (plan 78
// D-1); a query shows the flat list; Uncategorized is last; archived
// categories disappear.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/food_draft.dart';
import 'package:omnitrain/core/utils/foods_i_eat_order.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/nutrition/add_food_screen.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';

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

/// The Library heading order the screen must print (plan 78 D-1): the
/// fixed first-run order filtered to the categories that have foods,
/// then the remaining categories alphabetically, Uncategorized last.
List<String> _expectedLibraryHeadings(FoodLibraryState foodLib) {
  const fixedOrder = [
    'Proteins',
    'Dairy',
    'Grains & Starches',
    'Fruits',
    'Vegetables',
    'Nuts, Seeds & Fats',
    'Snacks & Prepared',
    'Drinks',
    'Condiments',
  ];
  final titled = foodsIEatSections(
    foods: foodLib.catalogFoods,
    groups: foodLib.activeFoodGroups,
  ).map((s) => s.title).toList();
  final listed = [
    for (final name in fixedOrder)
      if (titled.contains(name)) name,
  ];
  final rest =
      titled
          .where(
            (t) => t != foodsIEatUncategorisedTitle && !fixedOrder.contains(t),
          )
          .toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  final uncategorised = titled
      .where((t) => t == foodsIEatUncategorisedTitle)
      .toList();
  return [...listed, ...rest, ...uncategorised];
}

void main() {
  group('Library category headings (plan 77b2 S-12820..S-12824)', () {
    /// Pump the AddFoodScreen for the Library tab with the categories
    /// loaded (as the nutrition screen does in the app).
    Future<({NutritionState nutrition, FoodLibraryState foodLib})>
    pumpCatalogTab(WidgetTester tester, {MockWorkoutRepository? repo}) async {
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

    testWidgets('S-12820: real catalog, empty search — headings follow the '
        'fixed Library order and the first food sits below its heading', (
      tester,
    ) async {
      final repo = await _freshRepo();
      final states = await pumpCatalogTab(tester, repo: repo);
      final foodLib = states.foodLib;

      final built = _builtHeadingTitles(tester);
      expect(built.length, greaterThanOrEqualTo(2));
      expect(built, _expectedLibraryHeadings(foodLib).take(built.length));

      // Headings are vertically ordered.
      for (var i = 1; i < built.length; i++) {
        final prev = tester.getTopLeft(
          find.byKey(Key('library_section_${built[i - 1]}')),
        );
        final curr = tester.getTopLeft(
          find.byKey(Key('library_section_${built[i]}')),
        );
        expect(curr.dy, greaterThan(prev.dy));
      }

      // The first food of the first heading sits below its heading.
      final sections = foodsIEatSections(
        foods: foodLib.catalogFoods,
        groups: foodLib.activeFoodGroups,
      );
      expect(sections, isNotEmpty);
      final firstTitle = built.first;
      final firstSection = sections.firstWhere((s) => s.title == firstTitle);
      expect(firstSection.foods, isNotEmpty);
      final headingDy = tester
          .getTopLeft(find.byKey(Key('library_section_$firstTitle')))
          .dy;
      final foodDy = tester
          .getTopLeft(find.text(firstSection.foods.first.name))
          .dy;
      expect(foodDy, greaterThan(headingDy));
    });

    testWidgets(
      'S-12821: a query shows zero headings; clearing restores them',
      (tester) async {
        final repo = await _freshRepo();
        await pumpCatalogTab(tester, repo: repo);

        await tester.enterText(
          find.byKey(const Key('catalog_search_field')),
          'Chicken',
        );
        await tester.pumpAndSettle();
        expect(_builtHeadingTitles(tester), isEmpty);

        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
        expect(_builtHeadingTitles(tester).length, greaterThanOrEqualTo(2));
      },
    );

    testWidgets(
      'S-12822: a null-group catalog food and a legacy custom sit under '
      'the Uncategorized heading, which is the last one built',
      (tester) async {
        final repo = await _freshRepo();
        final states = await pumpCatalogTab(tester, repo: repo);
        final foodLib = states.foodLib;

        await foodLib.createCatalogFood(
          const FoodDraft(
            name: 'Mine 77 group',
            groupId: null,
            unitType: FoodUnitType.grams,
            referenceAmount: 100,
            referenceLabel: 'g',
            protein: 10,
            carbs: 5,
            fiber: null,
            fat: 2,
            sodium: null,
            notes: null,
            imagePath: null,
          ),
        );
        // ignore: deprecated_member_use_from_same_package
        await foodLib.createCustomFood(
          name: 'Legacy 77 group',
          groupId: null,
          unitType: FoodUnitType.grams,
          referenceAmount: 250,
          referenceLabel: 'g',
          protein: 18,
          carbs: 20,
          fat: 5,
        );
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(
          find.byKey(const Key('library_section_Uncategorized')),
          400,
          scrollable: _verticalScrollable,
        );
        await tester.pumpAndSettle();

        final headingDy = tester
            .getTopLeft(find.byKey(const Key('library_section_Uncategorized')))
            .dy;
        expect(
          tester.getTopLeft(find.text('Mine 77 group')).dy,
          greaterThan(headingDy),
        );
        expect(
          tester.getTopLeft(find.text('Legacy 77 group')).dy,
          greaterThan(headingDy),
        );

        // Scrolled to the bottom: Uncategorized is the LAST heading.
        await _scrollToBottom(tester);
        final titles = _builtHeadingTitles(tester);
        expect(titles, isNotEmpty);
        expect(titles.last, 'Uncategorized');
      },
    );

    testWidgets(
      'S-12823: archiving a category removes its heading and moves its '
      'food under Uncategorized',
      (tester) async {
        final repo = await _freshRepo();
        final states = await pumpCatalogTab(tester, repo: repo);
        final foodLib = states.foodLib;

        final groupId = await foodLib.createFoodGroup('Temp 77');
        await foodLib.createCatalogFood(
          const FoodDraft(
            name: 'Temp 77 food',
            groupId: null,
            unitType: FoodUnitType.grams,
            referenceAmount: 100,
            referenceLabel: 'g',
            protein: 1,
            carbs: 1,
            fiber: null,
            fat: 1,
            sodium: null,
            notes: null,
            imagePath: null,
          ),
        );
        // File the created food into the new category.
        final catalogFood = foodLib.catalogFoods.firstWhere(
          (f) => f.name == 'Temp 77 food',
        );
        await foodLib.updateCatalogFood(
          catalogFood,
          FoodDraft(
            name: catalogFood.name,
            groupId: groupId,
            unitType: catalogFood.unitType,
            referenceAmount: catalogFood.referenceAmount,
            referenceLabel: catalogFood.referenceLabel,
            protein: catalogFood.protein,
            carbs: catalogFood.carbs,
            fiber: catalogFood.fiber,
            fat: catalogFood.fat,
            sodium: catalogFood.sodium,
            notes: catalogFood.notes,
            imagePath: catalogFood.imagePath,
          ),
        );
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(
          find.byKey(const Key('library_section_Temp 77')),
          400,
          scrollable: _verticalScrollable,
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('library_section_Temp 77')),
          findsOneWidget,
        );

        await foodLib.archiveFoodGroup(groupId);
        await foodLib.loadFoodGroups();
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('library_section_Temp 77')), findsNothing);
        // The food is below the Uncategorized heading.
        await tester.scrollUntilVisible(
          find.text('Temp 77 food'),
          400,
          scrollable: _verticalScrollable,
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('library_section_Uncategorized')),
          findsOneWidget,
        );
        expect(
          tester.getTopLeft(find.text('Temp 77 food')).dy,
          greaterThan(
            tester
                .getTopLeft(
                  find.byKey(const Key('library_section_Uncategorized')),
                )
                .dy,
          ),
        );
      },
    );

    testWidgets(
      'S-12825: a heading prints the category name as is and has no divider '
      'between it and its first food',
      (tester) async {
        final states = await pumpCatalogTab(tester);
        final sections = foodsIEatSections(
          foods: states.foodLib.catalogFoods,
          groups: states.foodLib.activeFoodGroups,
        );
        // The first BUILT heading (plan 78: the fixed Library order,
        // not the alphabetical sections order).
        final built = _builtHeadingTitles(tester);
        expect(built, isNotEmpty);
        final title = built.first;
        final section = sections.firstWhere((s) => s.title == title);
        final heading = find.byKey(Key('library_section_$title'));
        expect(
          find.descendant(of: heading, matching: find.text(title)),
          findsOneWidget,
        );

        final headingBottom = tester.getBottomLeft(heading).dy;
        final firstFoodDy = tester
            .getTopLeft(find.text(section.foods.first.name))
            .dy;
        final dividers = find.byType(Divider);
        final count = dividers.evaluate().length;
        expect(count, greaterThan(0));
        for (var i = 0; i < count; i++) {
          final dy = tester.getTopLeft(dividers.at(i)).dy;
          expect(
            dy >= headingBottom - 0.5 && dy < firstFoodDy,
            isFalse,
            reason: 'no divider between a heading and its first food',
          );
        }
      },
    );

    test('S-12824: source guard on add_food_screen.dart', () {
      final source = File(
        'lib/features/nutrition/add_food_screen.dart',
      ).readAsStringSync();
      expect(source, contains('foodsIEatSections('));
      expect(source, contains('groups: state.activeFoodGroups,'));
      expect(source, isNot(contains('loadFoodGroups(')));
    });
  });
}
