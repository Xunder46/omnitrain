// test/nutrition_day_view_state_test.dart
//
// Plan 247: the Nutrition screen can show an earlier day. These tests pin the
// viewed-day cache of NutritionState: it reads and edits that day only and
// never touches the today caches Home and the watch read.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/nutrition/nutrition_day_totals.dart';
import 'package:omnitrain/state/nutrition_state.dart';

import 'helpers/repository_harness.dart';

final DateTime _now = DateTime(2026, 11, 18, 10);
final DateTime _today = DateTime(2026, 11, 18);
final DateTime _yesterday = DateTime(2026, 11, 17);
final DateTime _dayBefore = DateTime(2026, 11, 16);

int _ms(DateTime d) => d.millisecondsSinceEpoch;

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

/// The shared fixture of the plan: yesterday c-y1 (Rice 200 g, 340 kcal) and
/// 750 ml and a 2000 kcal target; today c-t1 (Egg x2, 146 kcal) and 250 ml and
/// a 2200 kcal target. [withLibrary] false leaves Rice and Egg out of the
/// library (a removed food).
Future<void> _seed(WorkoutRepository repo, {bool withLibrary = true}) async {
  if (repo is MockWorkoutRepository) repo.clearConsumedFoodsForTest();
  if (withLibrary) {
    await repo.createFood(_rice());
    await repo.createFood(_egg());
  }
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

/// A state over [repo] with the today caches loaded, as the screen loads them.
Future<NutritionState> _stateOn(WorkoutRepository repo) async {
  final state = NutritionState(repo, clock: () => _now);
  await state.loadConsumedToday();
  await state.loadWaterForToday();
  await state.loadNutritionTarget();
  return state;
}

/// A Mock repository that holds back the rows read of one day until [gate]
/// completes (for the latest-request-wins and loading scenarios), and a water
/// read of [heldWaterDayMs] until [waterHold] completes (for the write races).
class _GatedRepo extends MockWorkoutRepository {
  Completer<void>? gate;
  int? gatedDayMs;

  @override
  Future<List<ConsumedFood>> getConsumedFoodsForDate(int dateMs) async {
    if (gate != null && dateMs == gatedDayMs) await gate!.future;
    return super.getConsumedFoodsForDate(dateMs);
  }

  /// When set, the next `getWaterVolumeForDate(heldWaterDayMs)` reads its value,
  /// clears the hold, then waits for [waterHold] before returning the value it
  /// already read (a read that returns stale data after a later write).
  Completer<void>? waterHold;
  int? heldWaterDayMs;

  @override
  Future<int> getWaterVolumeForDate(int dateMs) async {
    final value = await super.getWaterVolumeForDate(dateMs);
    final hold = waterHold;
    if (hold != null && dateMs == heldWaterDayMs) {
      waterHold = null;
      await hold.future;
    }
    return value;
  }
}

void main() {
  for (final make in harnessFactories) {
    final name = make().name;
    group('$name: viewed day', () {
      late RepositoryHarness harness;
      setUp(() => harness = make());
      tearDown(() => harness.close());

      test('S-24701 viewing yesterday shows its rows, water and target and '
          'leaves today alone', () async {
        final repo = await harness.open();
        await _seed(repo);
        final state = await _stateOn(repo);
        await state.viewDay(_yesterday);
        expect(state.isViewingToday, false);
        expect(state.viewedDayMs, _ms(_yesterday));
        expect([for (final c in state.viewedConsumed) c.id], ['c-y1']);
        expect(state.viewedTotals.calories, 340);
        expect(state.viewedTotals.protein, 20);
        expect(state.viewedTotals.carbs, 20);
        expect(state.viewedTotals.fat, 20);
        expect(state.viewedTotals.fiber, 0);
        expect(state.viewedTotals.sodium, 0);
        expect(state.viewedWaterMl, 750);
        expect(state.viewedTarget!.calories, 2000);
        expect([for (final c in state.consumedToday) c.id], ['c-t1']);
        expect(state.todayConsumedCalories, 146);
        expect(state.waterTodayMl, 250);
        expect(state.nutritionTarget!.calories, 2200);
      });

      test('S-24702 shifting back two days shows D-2 empty and forward three '
          'lands on today and stays', () async {
        final repo = await harness.open();
        await _seed(repo);
        final state = await _stateOn(repo);
        await state.shiftViewedDay(-1);
        await state.shiftViewedDay(-1);
        expect(state.viewedDayMs, _ms(_dayBefore));
        expect([for (final c in state.viewedConsumed) c.id], <String>[]);
        expect(state.viewedWaterMl, 0);
        expect(
          state.viewedTarget,
          await repo.getNutritionTargetForDate(_ms(_dayBefore)),
        );
        await state.shiftViewedDay(1);
        await state.shiftViewedDay(1);
        expect(state.isViewingToday, true);
        await state.shiftViewedDay(1);
        expect(state.isViewingToday, true);
        expect(state.canViewNextDay, false);
      });

      test(
        'S-24703 the shift crosses a clock-change day by calendar days',
        () async {
          final repo = await harness.open();
          final state = NutritionState(
            repo,
            clock: () => DateTime(2026, 3, 9, 10),
          );
          await state.shiftViewedDay(-1);
          await state.shiftViewedDay(-1);
          expect(
            state.viewedDayMs,
            DateTime(2026, 3, 7).millisecondsSinceEpoch,
          );
        },
      );

      test(
        'S-24705 resetDayView returns to today without notifying a listener',
        () async {
          final repo = await harness.open();
          await _seed(repo);
          final state = await _stateOn(repo);
          await state.viewDay(_yesterday);
          var calls = 0;
          state.addListener(() => calls++);
          state.resetDayView();
          expect(state.isViewingToday, true);
          expect([for (final c in state.viewedConsumed) c.id], ['c-t1']);
          expect(calls, 0);
        },
      );

      test('S-24706 logging the egg on yesterday writes it on that day with '
          'that day\'s target and today stays alone', () async {
        final repo = await harness.open();
        await _seed(repo);
        final state = await _stateOn(repo);
        await state.viewDay(_yesterday);
        final id = await state.logConsumedFoodViewed(_egg(), 2);
        expect(id, isNotNull);
        final yesterdayRows = await repo.getConsumedFoodsForDate(
          _ms(_yesterday),
        );
        expect(yesterdayRows.any((c) => c.id == 'c-y1'), true);
        final eggRows = yesterdayRows
            .where((c) => c.sourceFoodId == 'f-egg')
            .toList();
        expect(eggRows, hasLength(1));
        expect(eggRows.single.targetCalories, 2000);
        expect(state.viewedConsumed, hasLength(2));
        expect([for (final c in state.consumedToday) c.id], ['c-t1']);
      });

      test(
        'S-24707 logging rice again on yesterday keeps ONE row at 300 g',
        () async {
          final repo = await harness.open();
          await _seed(repo);
          final state = await _stateOn(repo);
          await state.viewDay(_yesterday);
          await state.logConsumedFoodViewed(_rice(), 300);
          final yesterdayRows = await repo.getConsumedFoodsForDate(
            _ms(_yesterday),
          );
          final riceRows = yesterdayRows
              .where((c) => c.sourceFoodId == 'f-rice')
              .toList();
          expect(riceRows, hasLength(1));
          expect(riceRows.single.id, 'c-y1');
          expect(riceRows.single.amountConsumed, 300);
          expect(state.viewedTotals.calories, 510);
        },
      );

      test('S-24708 unticking rice on yesterday deletes the row and the second '
          'call is false', () async {
        final repo = await harness.open();
        await _seed(repo);
        final state = await _stateOn(repo);
        await state.viewDay(_yesterday);
        expect(await state.unlogFoodViewed('f-rice'), true);
        expect(await repo.getConsumedFoodsForDate(_ms(_yesterday)), isEmpty);
        expect(state.viewedConsumed, isEmpty);
        expect([for (final c in state.consumedToday) c.id], ['c-t1']);
        expect(await state.unlogFoodViewed('f-rice'), false);
      });

      test('S-24709 editing a removed-food row on yesterday never writes a '
          'library food', () async {
        final repo = await harness.open();
        await _seed(repo, withLibrary: false);
        final state = await _stateOn(repo);
        await state.viewDay(_yesterday);
        final row = state.viewedConsumed.singleWhere((c) => c.id == 'c-y1');
        expect(await state.setLoggedAmountViewed(row, 100), true);
        final yesterdayRows = await repo.getConsumedFoodsForDate(
          _ms(_yesterday),
        );
        expect(
          yesterdayRows.singleWhere((c) => c.id == 'c-y1').amountConsumed,
          100,
        );
        expect(state.viewedTotals.calories, 170);
        expect((await repo.getFoods()).any((f) => f.id == 'f-rice'), false);
      });

      test('S-24710 deleting the yesterday row by id is true then false for an '
          'unknown id', () async {
        final repo = await harness.open();
        await _seed(repo);
        final state = await _stateOn(repo);
        await state.viewDay(_yesterday);
        expect(await state.deleteConsumedFoodViewed('c-y1'), true);
        expect(await repo.getConsumedFoodsForDate(_ms(_yesterday)), isEmpty);
        expect(await state.deleteConsumedFoodViewed('c-y1'), false);
      });

      test('S-24711 the water step writes the viewed day only and a minus at '
          'zero is a no-op', () async {
        final repo = await harness.open();
        await _seed(repo);
        final state = await _stateOn(repo);
        await state.viewDay(_yesterday);
        await state.incrementWaterViewed();
        expect(await repo.getWaterVolumeForDate(_ms(_yesterday)), 1000);
        expect(state.viewedWaterMl, 1000);
        expect(state.waterTodayMl, 250);
        await state.viewDay(_dayBefore);
        await state.decrementWaterViewed();
        expect(await repo.getWaterVolumeForDate(_ms(_dayBefore)), 0);
        expect(state.viewedWaterMl, 0);
      });

      test(
        'S-24712 on today the viewed methods delegate to the today methods',
        () async {
          final repo = await harness.open();
          await _seed(repo);
          final state = await _stateOn(repo);
          expect(
            state.consumedToday
                .singleWhere((c) => c.id == 'c-t1')
                .amountConsumed,
            2,
          );
          await state.logConsumedFoodViewed(_egg(), 3);
          expect(state.todayConsumedCalories, 219);
          expect(state.consumedToday, hasLength(1));
          await state.incrementWaterViewed();
          expect(state.waterTodayMl, 500);
          expect(state.viewedWaterMl, 500);
          expect(await state.unlogFoodViewed('f-egg'), true);
          expect(state.consumedToday, isEmpty);
        },
      );

      test('S-24713 a late wrist log on the viewed day appears in the viewed '
          'cache', () async {
        final repo = await harness.open();
        await _seed(repo);
        final state = await _stateOn(repo);
        await state.viewDay(_yesterday);
        await state.logConsumedFoodOnDay(
          _egg(),
          1,
          loggedAt: DateTime(2026, 11, 17, 20),
        );
        expect(state.viewedConsumed, hasLength(2));
      });

      test('S-24714 a wrist water tap on the viewed day refreshes the viewed '
          'water only', () async {
        final repo = await harness.open();
        await _seed(repo);
        final state = await _stateOn(repo);
        await state.viewDay(_yesterday);
        expect(
          await state.applyWatchWaterTap(
            dateMs: _ms(_yesterday),
            tapId: 't1',
            add: true,
          ),
          true,
        );
        expect(state.viewedWaterMl, 1000);
        expect(state.waterTodayMl, 250);
      });

      test('S-24715 viewing today or a future day shows today', () async {
        final repo = await harness.open();
        await _seed(repo);
        final state = await _stateOn(repo);
        await state.viewDay(_yesterday);
        await state.viewDay(DateTime(2026, 11, 18));
        expect(state.isViewingToday, true);
        expect([for (final c in state.viewedConsumed) c.id], ['c-t1']);
        await state.viewDay(DateTime(2026, 11, 19));
        expect(state.isViewingToday, true);
        expect([for (final c in state.viewedConsumed) c.id], ['c-t1']);
      });

      test('S-24718 a viewed day that is no longer before today counts as '
          'today (the clock moved back)', () async {
        final repo = await harness.open();
        await _seed(repo);
        var now = _now;
        final state = NutritionState(repo, clock: () => now);
        await state.loadConsumedToday();
        await state.loadWaterForToday();
        await state.loadNutritionTarget();
        await state.viewDay(_yesterday);
        expect(state.isViewingToday, isFalse);
        now = DateTime(2026, 11, 16, 10);
        expect(state.isViewingToday, isTrue);
        expect(state.viewedDayMs, _ms(DateTime(2026, 11, 16)));
        expect(state.canViewNextDay, isFalse);
        expect([for (final c in state.viewedConsumed) c.id], ['c-t1']);
      });

      test('S-24719 a minus at zero on an earlier day changes nothing and '
          'tells nobody', () async {
        final repo = await harness.open();
        await _seed(repo);
        final state = await _stateOn(repo);
        await state.viewDay(_dayBefore);
        var calls = 0;
        state.addListener(() => calls++);
        await state.decrementWaterViewed();
        expect(calls, 0);
        expect(state.viewedWaterMl, 0);
        expect(await repo.getWaterVolumeForDate(_ms(_dayBefore)), 0);
      });

      test('S-24716 fractional grams round once, not per row', () async {
        final repo = await harness.open();
        if (repo is MockWorkoutRepository) repo.clearConsumedFoodsForTest();
        ConsumedFood proteinRow(String id) => ConsumedFood(
          id: id,
          loggedAtMs: _ms(_today) + 3600000,
          dateMs: _ms(_today),
          sourceFoodId: 'f-egg',
          name: 'Egg',
          unitType: FoodUnitType.count,
          referenceAmount: 100,
          referenceLabel: 'g',
          protein: 30,
          carbs: 0,
          fat: 0,
          amountConsumed: 1.5,
          targetCalories: 2000,
          targetProtein: 0,
          targetCarbs: 0,
          targetFat: 0,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        );
        final rows = [proteinRow('c-p1'), proteinRow('c-p2')];
        for (final row in rows) {
          await repo.createConsumedFood(row);
        }
        expect(NutritionDayTotals.of(rows).protein, 1);
        final state = NutritionState(repo, clock: () => _now);
        await state.loadConsumedToday();
        expect(state.todayConsumedProtein, 1);
        expect(state.viewedTotals.protein, 1);
      });
    });
  }

  group('Mock: gated reads', () {
    test(
      'S-24704 a late first view is dropped when a newer viewDay wins',
      () async {
        final repo = _GatedRepo();
        await repo.initialize();
        await _seed(repo);
        final state = await _stateOn(repo);
        repo.gatedDayMs = _ms(_yesterday);
        repo.gate = Completer<void>();
        final first = state.viewDay(_yesterday);
        await state.viewDay(_dayBefore);
        repo.gate!.complete();
        await first;
        expect(state.viewedDayMs, _ms(_dayBefore));
        expect(state.viewedConsumed, isEmpty);
      },
    );

    test(
      'S-24717 isViewedDayLoaded is false while the reads are in flight',
      () async {
        final repo = _GatedRepo();
        await repo.initialize();
        await _seed(repo);
        final state = await _stateOn(repo);
        expect(state.isViewedDayLoaded, true);
        repo.gatedDayMs = _ms(_yesterday);
        repo.gate = Completer<void>();
        final f = state.viewDay(_yesterday);
        expect(state.isViewedDayLoaded, false);
        repo.gate!.complete();
        await f;
        expect(state.isViewedDayLoaded, true);
      },
    );

    test('S-24733 a wrist water tap read that finishes after the view moved '
        'on does not change the new day', () async {
      final repo = _GatedRepo();
      await repo.initialize();
      await _seed(repo);
      final state = await _stateOn(repo);
      await state.viewDay(_yesterday);
      final hold = Completer<void>();
      repo.heldWaterDayMs = _ms(_yesterday);
      repo.waterHold = hold;
      final tap = state.applyWatchWaterTap(
        dateMs: _ms(_yesterday),
        tapId: 't1',
        add: true,
      );
      await pumpEventQueue();
      await state.viewDay(_dayBefore);
      hold.complete();
      await tap;
      expect(state.viewedDayMs, _ms(_dayBefore));
      expect(state.viewedWaterMl, 0);
    });

    test('S-24734 a write that lands while a day\'s reads are in flight is '
        'not lost', () async {
      final repo = _GatedRepo();
      await repo.initialize();
      await _seed(repo);
      final state = await _stateOn(repo);
      final hold = Completer<void>();
      repo.heldWaterDayMs = _ms(_yesterday);
      repo.waterHold = hold;
      final view = state.viewDay(_yesterday);
      await pumpEventQueue();
      await state.applyWatchWaterTap(
        dateMs: _ms(_yesterday),
        tapId: 't1',
        add: true,
      );
      hold.complete();
      await view;
      expect(state.viewedWaterMl, 1000);
      expect(await repo.getWaterVolumeForDate(_ms(_yesterday)), 1000);
    });
  });
}
