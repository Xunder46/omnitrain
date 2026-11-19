// test/nutrition_day_switcher_screen_test.dart
//
// Plan 247: the Nutrition screen's day switcher. These tests pin the
// screen behaviour of S-24721..S-24731: the header arrows, the day
// title, the viewed day's ring and ticks, edits that write to the
// viewed day only, and the "No longer in Foods I Eat" section.
//
// Mock repository ONLY: a Hive write inside `testWidgets` never
// settles. Every fixture write happens before `pumpWidget`, awaited,
// outside any `Future.delayed`.

import 'dart:async';
import 'dart:ui' show CheckedState;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/nutrition/nutrition_screen.dart';
import 'package:omnitrain/features/nutrition/widgets/calorie_ring.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/widgets/layout/omni_card_header.dart';

import 'helpers/test_nutrition_primer_state.dart';

final DateTime _now = DateTime(2026, 11, 18, 10);
final DateTime _today = DateTime(2026, 11, 18);
final DateTime _yesterday = DateTime(2026, 11, 17);

int _ms(DateTime d) => d.millisecondsSinceEpoch;

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  // Wipe the seed consumed-foods so the day-log is empty.
  repo.clearConsumedFoodsForTest();
  return repo;
}

/// A Mock repository that holds back one day's rows until [gate] completes
/// (so the screen's foods block can be watched while a day's reads are
/// in flight).
class _GatedRepo extends MockWorkoutRepository {
  Completer<void>? gate;
  int? gatedDayMs;

  @override
  Future<List<ConsumedFood>> getConsumedFoodsForDate(int dateMs) async {
    if (gate != null && dateMs == gatedDayMs) await gate!.future;
    return super.getConsumedFoodsForDate(dateMs);
  }
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

/// The plan's fixture: yesterday c-y1 (Rice 200 g, 340 kcal), 750 ml and a
/// 2000 kcal target; today c-t1 (Egg x2, 146 kcal), 250 ml and a 2200 kcal
/// target. [library] `both` holds Rice and Egg, `egg` only Egg (so
/// yesterday's Rice is a removed food), `none` an empty library.
Future<void> _seed(
  MockWorkoutRepository repo,
  FoodLibraryState foodLibraryState, {
  String library = 'both',
}) async {
  if (library == 'both') await foodLibraryState.createFood(_rice());
  if (library != 'none') await foodLibraryState.createFood(_egg());
  await repo.createConsumedFood(_row('c-y1', _rice(), 200, _yesterday));
  await repo.createConsumedFood(_row('c-t1', _egg(), 2, _today));
  await repo.saveWaterVolumeForDate(_ms(_yesterday), 750);
  await repo.saveWaterVolumeForDate(_ms(_today), 250);
  await repo.saveNutritionTargetForDate(
    _ms(_today),
    NutritionTarget(calories: 2200),
  );
  await repo.saveNutritionTargetForDate(
    _ms(_yesterday),
    NutritionTarget(calories: 2000),
  );
}

Future<void> _pumpNutritionScreen(
  WidgetTester tester, {
  required MockWorkoutRepository repo,
  required NutritionState nutritionState,
  required FoodLibraryState foodLibraryState,
}) async {
  await tester.binding.setSurfaceSize(const Size(600, 1200));
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
}

/// The first card header's title (the day title).
String _dayTitle(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const Key('omniCardHeader_title')).first)
    .data!;

bool _isChecked(WidgetTester tester, String foodId) {
  final handle = tester.ensureSemantics();
  try {
    final node = tester.getSemantics(find.byKey(Key('log_food_thumb_$foodId')));
    return node.getSemanticsData().flagsCollection.isChecked ==
        CheckedState.isTrue;
  } finally {
    handle.dispose();
  }
}

/// Taps [key] and lets the screen's loads land (never `pumpAndSettle`:
/// spinners and the debounce timers must not be waited out by it).
Future<void> _tap(WidgetTester tester, Key key) async {
  await tester.tap(find.byKey(key));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _enterAmount(WidgetTester tester, Key key, String text) async {
  await tester.enterText(find.byKey(key), text);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

void main() {
  group('plan 247: nutrition day switcher screen', () {
    testWidgets('S-24721: opens on today with prev enabled and next disabled', (
      tester,
    ) async {
      final repo = await _freshRepo();
      final foodLibraryState = FoodLibraryState(repo);
      await _seed(repo, foodLibraryState);
      final nutritionState = NutritionState(repo, clock: () => _now);
      await nutritionState.loadConsumedToday();
      await nutritionState.loadWaterForToday();
      await nutritionState.loadNutritionTarget();

      await _pumpNutritionScreen(
        tester,
        repo: repo,
        nutritionState: nutritionState,
        foodLibraryState: foodLibraryState,
      );

      expect(_dayTitle(tester), 'TODAY');
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('nutrition_day_prev')))
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('nutrition_day_next')))
            .onPressed,
        isNull,
      );
    });

    testWidgets('S-24722: prev shows yesterday then D-2, next walks back', (
      tester,
    ) async {
      final repo = await _freshRepo();
      final foodLibraryState = FoodLibraryState(repo);
      await _seed(repo, foodLibraryState);
      final nutritionState = NutritionState(repo, clock: () => _now);
      await nutritionState.loadConsumedToday();
      await nutritionState.loadWaterForToday();
      await nutritionState.loadNutritionTarget();

      await _pumpNutritionScreen(
        tester,
        repo: repo,
        nutritionState: nutritionState,
        foodLibraryState: foodLibraryState,
      );

      await _tap(tester, const Key('nutrition_day_prev'));
      expect(_dayTitle(tester), 'YESTERDAY');
      expect(
        tester.widget<CalorieRing>(find.byType(CalorieRing)).consumed,
        closeTo(340, 0.01),
      );
      expect(_isChecked(tester, 'f-rice'), isTrue);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('log_food_amount_f-rice')))
            .controller!
            .text,
        '200',
      );
      expect(_isChecked(tester, 'f-egg'), isFalse);

      await _tap(tester, const Key('nutrition_day_prev'));
      expect(_dayTitle(tester), 'NOV 16');
      expect(_isChecked(tester, 'f-rice'), isFalse);
      expect(_isChecked(tester, 'f-egg'), isFalse);

      await _tap(tester, const Key('nutrition_day_next'));
      await _tap(tester, const Key('nutrition_day_next'));
      expect(_dayTitle(tester), 'TODAY');
      expect(_isChecked(tester, 'f-egg'), isTrue);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('log_food_amount_f-egg')))
            .controller!
            .text,
        '2',
      );
    });

    testWidgets('S-24723: the target button shows on today only', (
      tester,
    ) async {
      final repo = await _freshRepo();
      final foodLibraryState = FoodLibraryState(repo);
      await _seed(repo, foodLibraryState);
      final nutritionState = NutritionState(repo, clock: () => _now);
      await nutritionState.loadConsumedToday();
      await nutritionState.loadWaterForToday();
      await nutritionState.loadNutritionTarget();

      await _pumpNutritionScreen(
        tester,
        repo: repo,
        nutritionState: nutritionState,
        foodLibraryState: foodLibraryState,
      );

      expect(find.byKey(const Key('nutrition_target_button')), findsOneWidget);

      await _tap(tester, const Key('nutrition_day_prev'));
      expect(find.byKey(const Key('nutrition_target_button')), findsNothing);

      await _tap(tester, const Key('nutrition_day_next'));
      expect(find.byKey(const Key('nutrition_target_button')), findsOneWidget);
    });

    testWidgets('S-24724: ticking a food on yesterday writes that day only', (
      tester,
    ) async {
      final repo = await _freshRepo();
      final foodLibraryState = FoodLibraryState(repo);
      await _seed(repo, foodLibraryState);
      final nutritionState = NutritionState(repo, clock: () => _now);
      await nutritionState.loadConsumedToday();
      await nutritionState.loadWaterForToday();
      await nutritionState.loadNutritionTarget();

      await _pumpNutritionScreen(
        tester,
        repo: repo,
        nutritionState: nutritionState,
        foodLibraryState: foodLibraryState,
      );

      await _tap(tester, const Key('nutrition_day_prev'));
      await _tap(tester, const Key('log_food_thumb_f-egg'));

      final yesterdayRows = await repo.getConsumedFoodsForDate(_ms(_yesterday));
      expect(yesterdayRows.length, 2);
      expect(yesterdayRows.any((c) => c.sourceFoodId == 'f-egg'), isTrue);
      final todayRows = await repo.getConsumedFoodsForDate(_ms(_today));
      expect([for (final c in todayRows) c.id], ['c-t1']);
      expect(
        tester.widget<CalorieRing>(find.byType(CalorieRing)).consumed,
        closeTo(413, 0.01),
      );
    });

    testWidgets('S-24725: water on yesterday speaks that day and not today', (
      tester,
    ) async {
      final repo = await _freshRepo();
      final foodLibraryState = FoodLibraryState(repo);
      await _seed(repo, foodLibraryState);
      final nutritionState = NutritionState(repo, clock: () => _now);
      await nutritionState.loadConsumedToday();
      await nutritionState.loadWaterForToday();
      await nutritionState.loadNutritionTarget();

      await _pumpNutritionScreen(
        tester,
        repo: repo,
        nutritionState: nutritionState,
        foodLibraryState: foodLibraryState,
      );

      final handle = tester.ensureSemantics();
      try {
        expect(find.bySemanticsLabel(RegExp(r'^Water today')), findsOneWidget);

        await _tap(tester, const Key('nutrition_day_prev'));
        await _tap(tester, const Key('water_tracker_plus'));

        expect(nutritionState.viewedWaterMl, 1000);
        expect(nutritionState.waterTodayMl, 250);
        expect(
          find.bySemanticsLabel(RegExp(r'^Water on Nov 17')),
          findsOneWidget,
        );
      } finally {
        handle.dispose();
      }
    });

    testWidgets('S-24726: an amount change on yesterday edits that row only', (
      tester,
    ) async {
      final repo = await _freshRepo();
      final foodLibraryState = FoodLibraryState(repo);
      await _seed(repo, foodLibraryState);
      final nutritionState = NutritionState(repo, clock: () => _now);
      await nutritionState.loadConsumedToday();
      await nutritionState.loadWaterForToday();
      await nutritionState.loadNutritionTarget();

      await _pumpNutritionScreen(
        tester,
        repo: repo,
        nutritionState: nutritionState,
        foodLibraryState: foodLibraryState,
      );

      await _tap(tester, const Key('nutrition_day_prev'));
      await _enterAmount(tester, const Key('log_food_amount_f-rice'), '300');

      final yesterdayRows = await repo.getConsumedFoodsForDate(_ms(_yesterday));
      final riceRows = [
        for (final c in yesterdayRows)
          if (c.sourceFoodId == 'f-rice') c,
      ];
      expect(riceRows.length, 1);
      expect(riceRows.single.amountConsumed, 300);
      final todayRows = await repo.getConsumedFoodsForDate(_ms(_today));
      expect(todayRows.single.amountConsumed, 2);
    });

    testWidgets('S-24727: a removed food keeps its own editable row', (
      tester,
    ) async {
      final repo = await _freshRepo();
      final foodLibraryState = FoodLibraryState(repo);
      // Library holds Egg only: yesterday's Rice row is a removed food.
      await _seed(repo, foodLibraryState, library: 'egg');
      final nutritionState = NutritionState(repo, clock: () => _now);
      await nutritionState.loadConsumedToday();
      await nutritionState.loadWaterForToday();
      await nutritionState.loadNutritionTarget();

      await _pumpNutritionScreen(
        tester,
        repo: repo,
        nutritionState: nutritionState,
        foodLibraryState: foodLibraryState,
      );

      await _tap(tester, const Key('nutrition_day_prev'));

      expect(find.text('No longer in Foods I Eat'), findsOneWidget);
      expect(find.text('Rice'), findsOneWidget);
      expect(_isChecked(tester, 'c-y1'), isTrue);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('log_food_amount_c-y1')))
            .controller!
            .text,
        '200',
      );
      expect(
        tester.widget<CalorieRing>(find.byType(CalorieRing)).consumed,
        closeTo(340, 0.01),
      );

      await _enterAmount(tester, const Key('log_food_amount_c-y1'), '300');

      final yesterdayRows = await repo.getConsumedFoodsForDate(_ms(_yesterday));
      expect(yesterdayRows.single.amountConsumed, 300);
      final foods = await repo.getFoods();
      expect(foods.any((f) => f.id == 'f-rice'), isFalse);

      await _tap(tester, const Key('log_food_thumb_c-y1'));
      expect(find.text('No longer in Foods I Eat'), findsNothing);
      expect(await repo.getConsumedFoodsForDate(_ms(_yesterday)), isEmpty);

      // On today the section is absent.
      await _tap(tester, const Key('nutrition_day_next'));
      expect(find.text('No longer in Foods I Eat'), findsNothing);
    });

    testWidgets('S-24728: reopening the screen starts on today', (
      tester,
    ) async {
      final repo = await _freshRepo();
      final foodLibraryState = FoodLibraryState(repo);
      await _seed(repo, foodLibraryState);
      final nutritionState = NutritionState(repo, clock: () => _now);
      await nutritionState.loadConsumedToday();
      await nutritionState.loadWaterForToday();
      await nutritionState.loadNutritionTarget();

      await _pumpNutritionScreen(
        tester,
        repo: repo,
        nutritionState: nutritionState,
        foodLibraryState: foodLibraryState,
      );

      await _tap(tester, const Key('nutrition_day_prev'));
      expect(_dayTitle(tester), 'YESTERDAY');

      await tester.pumpWidget(const SizedBox());
      await _pumpNutritionScreen(
        tester,
        repo: repo,
        nutritionState: nutritionState,
        foodLibraryState: foodLibraryState,
      );
      expect(_dayTitle(tester), 'TODAY');
    });

    testWidgets('S-24729: each day starts its rows from that day', (
      tester,
    ) async {
      final repo = await _freshRepo();
      final foodLibraryState = FoodLibraryState(repo);
      await _seed(repo, foodLibraryState);
      final nutritionState = NutritionState(repo, clock: () => _now);
      await nutritionState.loadConsumedToday();
      await nutritionState.loadWaterForToday();
      await nutritionState.loadNutritionTarget();

      await _pumpNutritionScreen(
        tester,
        repo: repo,
        nutritionState: nutritionState,
        foodLibraryState: foodLibraryState,
      );

      expect(
        tester
            .widget<TextField>(find.byKey(const Key('log_food_amount_f-egg')))
            .controller!
            .text,
        '2',
      );

      await _tap(tester, const Key('nutrition_day_prev'));
      expect(_isChecked(tester, 'f-egg'), isFalse);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('log_food_amount_f-egg')))
            .controller!
            .text,
        '1',
      );

      await _tap(tester, const Key('nutrition_day_next'));
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('log_food_amount_f-egg')))
            .controller!
            .text,
        '2',
      );
    });

    testWidgets('S-24730: a logged row shows even with an empty library', (
      tester,
    ) async {
      final repo = await _freshRepo();
      final foodLibraryState = FoodLibraryState(repo);
      // No foods in the library (do not call createFood); yesterday
      // still holds c-y1.
      await _seed(repo, foodLibraryState, library: 'none');
      final nutritionState = NutritionState(repo, clock: () => _now);
      await nutritionState.loadConsumedToday();
      await nutritionState.loadWaterForToday();
      await nutritionState.loadNutritionTarget();

      await _pumpNutritionScreen(
        tester,
        repo: repo,
        nutritionState: nutritionState,
        foodLibraryState: foodLibraryState,
      );

      await _tap(tester, const Key('nutrition_day_prev'));
      expect(find.text('Pick the foods you eat'), findsNothing);
      expect(find.text('No longer in Foods I Eat'), findsOneWidget);
    });

    testWidgets('S-24731: the header flanks and keeps its title key', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OmniCardHeader(
              leading: Icon(Icons.chevron_left, key: const Key('a')),
              trailing: Icon(Icons.chevron_right, key: const Key('b')),
              title: 'X',
            ),
          ),
        ),
      );

      final a = tester.getCenter(find.byKey(const Key('a')));
      final b = tester.getCenter(find.byKey(const Key('b')));
      final title = tester.getCenter(
        find.byKey(const Key('omniCardHeader_title')),
      );
      expect(a.dx < title.dx, isTrue, reason: 'leading sits left of the title');
      expect(
        title.dx < b.dx,
        isTrue,
        reason: 'trailing sits right of the title',
      );

      // With neither flank the header is unchanged.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: OmniCardHeader(title: 'X')),
        ),
      );
      expect(find.byKey(const Key('omniCardHeader_title')), findsOneWidget);
      expect(find.text('X'), findsOneWidget);
    });

    testWidgets(
      'S-24732: the foods block waits for an earlier day\'s reads, then '
      'shows that day\'s amounts',
      (tester) async {
        final repo = _GatedRepo();
        await repo.initialize();
        repo.clearConsumedFoodsForTest();
        final foodLibraryState = FoodLibraryState(repo);
        await _seed(repo, foodLibraryState);
        final nutritionState = NutritionState(repo, clock: () => _now);
        await nutritionState.loadConsumedToday();
        await nutritionState.loadWaterForToday();
        await nutritionState.loadNutritionTarget();

        await _pumpNutritionScreen(
          tester,
          repo: repo,
          nutritionState: nutritionState,
          foodLibraryState: foodLibraryState,
        );

        repo.gatedDayMs = _ms(_yesterday);
        repo.gate = Completer<void>();

        await _tap(tester, const Key('nutrition_day_prev'));
        expect(find.byKey(const Key('log_food_amount_f-rice')), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsWidgets);
        expect(_dayTitle(tester), 'YESTERDAY');

        repo.gate!.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          tester
              .widget<TextField>(
                find.byKey(const Key('log_food_amount_f-rice')),
              )
              .controller!
              .text,
          '200',
        );
        expect(_isChecked(tester, 'f-rice'), isTrue);
      },
    );

    testWidgets('S-24735: a day in another year reads with its year', (
      tester,
    ) async {
      final repo = await _freshRepo();
      final foodLibraryState = FoodLibraryState(repo);
      await _seed(repo, foodLibraryState);
      final nutritionState = NutritionState(repo, clock: () => _now);
      await nutritionState.loadConsumedToday();
      await nutritionState.loadWaterForToday();
      await nutritionState.loadNutritionTarget();

      await _pumpNutritionScreen(
        tester,
        repo: repo,
        nutritionState: nutritionState,
        foodLibraryState: foodLibraryState,
      );

      await nutritionState.viewDay(DateTime(2025, 11, 16));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_dayTitle(tester), 'NOV 16, 2025');

      await nutritionState.viewDay(DateTime(2026, 11, 16));
      await tester.pump();
      expect(_dayTitle(tester), 'NOV 16');
    });
  });
}
