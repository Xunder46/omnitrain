// Plan 235 P1 — food, water and daily targets stay on their calendar day across
// a time-zone change.
//
// The stored day key is the calendar date itself as UTC midnight
// (`OmniDateUtils.dayKeyMs`), so it is the same number in every zone; the app
// above the repository keeps passing local-midnight instants. The conversion
// lives in the models' `toMap`/`fromMap` and in the Hive repository's two
// per-day boxes (targets and water).
//
// Scenarios S-23501..S-23508 of
// `docs/plans/2026-11-18-235-day-keys-survive-a-time-zone-change-plan/2026-11-18-235-day-keys-survive-a-time-zone-change-plan.md`.
// Plain `test()` throughout: a Hive write inside `testWidgets` never completes
// (FakeAsync never advances real time).

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:omnitrain/core/utils/date_utils.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/nutrition_state.dart';

import 'helpers/repository_harness.dart';

// The app's currency: local midnights of the calendar days under test.
final int d5 = DateTime(2026, 6, 5).millisecondsSinceEpoch;
final int d10 = DateTime(2026, 6, 10).millisecondsSinceEpoch;
final int d14 = DateTime(2026, 6, 14).millisecondsSinceEpoch;
final int d15 = DateTime(2026, 6, 15).millisecondsSinceEpoch;
final int d16 = DateTime(2026, 6, 16).millisecondsSinceEpoch;
final int d20 = DateTime(2026, 6, 20).millisecondsSinceEpoch;

// The stored keys: each day's UTC midnight, the same number in every zone.
const int key14 = 1781395200000;
const int key15 = 1781481600000;
const int key16 = 1781568000000;

NutritionTarget _target({double calories = 2200, double protein = 140}) =>
    NutritionTarget(calories: calories, protein: protein, carbs: 250, fat: 70);

/// A consumed-food row on [dateMs], the shape both stores take from the
/// nutrition state.
ConsumedFood _consumedFood(String id, int dateMs) => ConsumedFood(
  id: id,
  loggedAtMs: dateMs + 12 * 60 * 60 * 1000,
  dateMs: dateMs,
  sourceFoodId: 'food-$id',
  name: 'Food $id',
  unitType: FoodUnitType.grams,
  referenceAmount: 100,
  referenceLabel: '100 g',
  protein: 20,
  carbs: 30,
  fiber: 0,
  fat: 10,
  sodium: null,
  amountConsumed: 100,
  groupIdSnapshot: 'food-group-proteins',
  groupNameSnapshot: 'Proteins',
  targetCalories: 2000,
  targetProtein: 100,
  targetCarbs: 250,
  targetFat: 70,
  createdAtMs: dateMs,
  updatedAtMs: dateMs,
);

Food _food(String id) => Food(
  id: id,
  name: 'Food $id',
  unitType: FoodUnitType.grams,
  referenceAmount: 100,
  referenceLabel: 'g',
  protein: 20,
  carbs: 30,
  fat: 10,
  createdAtMs: 0,
  updatedAtMs: 0,
);

void main() {
  // ─── S-23501: the two helpers ─────────────────────────────────────────
  test('S-23501 dayKeyMs is the calendar date\'s UTC midnight in any zone', () {
    for (final d in [
      DateTime(2026, 6, 15),
      DateTime(2026, 6, 15, 13, 45),
      DateTime(2026, 6, 15, 23, 59, 59),
    ]) {
      expect(OmniDateUtils.dayKeyMs(d), key15, reason: '$d');
      expect(
        OmniDateUtils.localMidnightOfDayKeyMs(OmniDateUtils.dayKeyMs(d)),
        OmniDateUtils.startOfDayMs(d),
        reason: 'the round trip returns the day\'s local midnight ($d)',
      );
    }
    expect(
      OmniDateUtils.localMidnightOfDayKeyMs(key15),
      DateTime(2026, 6, 15).millisecondsSinceEpoch,
    );
  });

  // ─── S-23502: the models convert at their map boundary ────────────────
  test('S-23502 models store the day key and read back the local midnight', () {
    final consumed = _consumedFood('cf-model', d15);
    final consumedMap = consumed.toMap();
    expect(consumedMap['date_ms'], key15);
    expect(ConsumedFood.fromMap(consumedMap).dateMs, d15);

    final target = _target().copyWith(dateMs: d15);
    final targetMap = target.toMap();
    expect(targetMap['date_ms'], key15);
    expect(NutritionTarget.fromMap(targetMap).dateMs, d15);

    final nullTarget = NutritionTarget(calories: 2100);
    final nullMap = nullTarget.toMap();
    expect(nullMap['date_ms'], isNull);
    final nullBack = NutritionTarget.fromMap(nullMap);
    expect(nullBack.dateMs, isNull);
    expect(nullBack.isUnset, isFalse);
    expect(NutritionTarget().isUnset, isTrue);
  });

  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — day keys survive a zone change (plan 235)', () {
      late WorkoutRepository repo;

      setUp(() async => repo = await harness.open());
      tearDown(() async => await harness.close());

      test('S-23503 water is stored under the day key', () async {
        await repo.saveWaterVolumeForDate(d15, 750);
        expect(await repo.getWaterVolumeForDate(d15), 750);

        if (harness.name == 'Hive') {
          final box = Hive.box<Map>('water_log');
          expect(box.keys.toList(), ['1781481600000']);
          final row = box.get('1781481600000')!;
          expect(row['date_ms'], key15);
          expect(row['id'], 'water-1781481600000');
          expect(row['volume_ml'], 750);
        }
      });

      test('S-23504 food rows are stored under their day key', () async {
        await repo.createConsumedFood(_consumedFood('cf-14', d14));
        await repo.createConsumedFood(_consumedFood('cf-15', d15));
        await repo.createConsumedFood(_consumedFood('cf-16', d16));

        final oneDay = await repo.getConsumedFoodsForDate(d15);
        expect(oneDay, hasLength(1));
        expect(oneDay.single.sourceFoodId, 'food-cf-15');
        expect(oneDay.single.dateMs, d15);

        final ranges = await repo.getConsumedFoodsInRange(d15, d15);
        expect(ranges, hasLength(1));
        expect(ranges.single.dateMs, d15);

        final three = await repo.getConsumedFoodsInRange(d14, d16);
        expect(three, hasLength(3));
        expect(
          {for (final row in three) row.id: row.dateMs},
          {'cf-14': d14, 'cf-15': d15, 'cf-16': d16},
        );

        if (harness.name == 'Hive') {
          final row = Hive.box<Map>('consumed_foods').get('cf-15')!;
          expect(row['date_ms'], key15);
        }
      });

      test('S-23505 a later day inherits the most recent earlier target',
          () async {
        await repo.saveNutritionTargetForDate(d10, _target(protein: 150));

        final inherited = await repo.getNutritionTargetForDate(d15);
        expect(inherited, isNotNull);
        expect(inherited!.protein, 150);
        expect(inherited.calories, 2200);
        expect(inherited.dateMs, d15);
      });

      test('S-23509 the day right before a read day is the first one the '
          'walk looks at', () async {
        // Guards the first step of the ancestor walk: a target on the day
        // before is found, not skipped (lead's mutation: a local-instant
        // first step skipped exactly that day).
        await repo.saveNutritionTargetForDate(d14, _target(protein: 133));

        final inherited = await repo.getNutritionTargetForDate(d15);
        expect(inherited, isNotNull);
        expect(inherited!.protein, 133);
        expect(inherited.dateMs, d15);
      });

      test('S-23506 a saved target propagates forward to identical days',
          () async {
        final a = _target(calories: 2000, protein: 100);
        await repo.saveNutritionTargetForDate(d10, a);
        await repo.saveNutritionTargetForDate(d20, a);

        await repo.saveNutritionTargetForDate(
          d10,
          _target(calories: 2400, protein: 160),
        );

        final future = await repo.getNutritionTargetForDate(d20);
        expect(future, isNotNull);
        expect(future!.calories, 2400, reason: 'the identical future row moved');
        expect(future.dateMs, d20);

        expect(
          await repo.getNutritionTargetForDate(d5),
          isNull,
          reason: 'nothing before the first target',
        );

        final today = await repo.getNutritionTargetForDate(d10);
        expect(today!.calories, 2400);
        expect(today.dateMs, d10);
      });

      test('S-23508 a fresh state reads back the day it wrote', () async {
        final todayMs = OmniDateUtils.todayMidnightMs();
        final food = _food('food-23508');
        final repoForState = repo;
        if (repoForState is MockWorkoutRepository) {
          // The Mock seeds now-relative consumed-food rows for the Stats
          // trend card; this scenario needs a clean day-log.
          repoForState.clearConsumedFoodsForTest();
        }
        final state = NutritionState(repoForState);
        await state.loadConsumedToday();

        await state.logConsumedFoodAt(food, 150);
        await state.incrementWaterForDate(todayMs);
        await state.saveNutritionTargetForDate(
          todayMs,
          NutritionTarget(calories: 2100, protein: 150, carbs: 250, fat: 70),
        );

        repo = await harness.restart();
        final fresh = NutritionState(repo);
        await fresh.loadConsumedToday();
        await fresh.loadWaterForDate(todayMs);
        await fresh.loadNutritionTargetForDate(todayMs);

        expect(fresh.consumedToday, hasLength(1));
        expect(fresh.consumedToday.single.sourceFoodId, food.id);
        expect(fresh.consumedToday.single.dateMs, todayMs);
        expect(fresh.waterTodayMl, state.waterStepMl);
        expect(fresh.nutritionTarget, isNotNull);
        expect(fresh.nutritionTarget!.calories, 2100);
        expect(fresh.nutritionTarget!.dateMs, todayMs);
      });
    });
  }

  // ─── S-23507: the water tap ledger keeps keying by the day key ────────
  group('Hive — water tap ledger keys the day (plan 235)', () {
    final harness = HiveRepositoryHarness();
    late WorkoutRepository repo;

    setUp(() async => repo = await harness.open());
    tearDown(() async => await harness.close());

    test('S-23507 a redelivered tap stays refused across a restart', () async {
      const delta = 250;
      expect(
        await repo.applyWaterTap(dateMs: d15, tapId: 't1', deltaMl: delta),
        isTrue,
      );
      expect(await repo.getWaterVolumeForDate(d15), delta);

      repo = await harness.restart();

      expect(
        await repo.applyWaterTap(dateMs: d15, tapId: 't1', deltaMl: delta),
        isFalse,
      );
      expect(await repo.getAppliedWaterTapIds(d15), ['t1']);
      expect(await repo.getWaterVolumeForDate(d15), delta);
      expect(Hive.box<Map>('water_log').containsKey('1781481600000'), isTrue);
    });
  });
}
