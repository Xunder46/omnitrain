// Plan 237 P1 — the nutrition day follows the clock.
//
// `NutritionState` notices when its clock's day is no longer the day the
// today-caches were loaded for, and `rolloverIfDayChanged()` rolls over to
// the new day (empty day, new day's target and water). Home runs it on app
// resume, and the log paths run it before touching today's list.
//
// Scenarios S-23701..S-23708 of
// `docs/plans/2026-11-18-237-nutrition-day-follows-the-clock-plan/2026-11-18-237-nutrition-day-follows-the-clock-plan.md`.
// Plain `test()` throughout; both stores via `harnessFactories`.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/nutrition_state.dart';

import 'helpers/repository_harness.dart';

// Local midnights of the calendar days under test.
final int d15 = DateTime(2026, 6, 15).millisecondsSinceEpoch;
final int d16 = DateTime(2026, 6, 16).millisecondsSinceEpoch;

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

void _clearMockSeeds(WorkoutRepository repo) {
  if (repo is MockWorkoutRepository) {
    // The Mock seeds now-relative consumed-food rows for the Stats trend
    // card; these scenarios need a clean day-log.
    repo.clearConsumedFoodsForTest();
  }
}

/// A state whose clock reads [now], seeded for 15 June: a saved target
/// (2200 kcal), one logged food, one water step, today's consumed cache
/// loaded — the shape every scenario below starts from.
Future<NutritionState> _seedDay15(
  WorkoutRepository repo,
  DateTime Function() clock,
) async {
  final state = NutritionState(repo, clock: clock);
  await state.saveNutritionTargetForDate(
    d15,
    NutritionTarget(calories: 2200, protein: 140, carbs: 250, fat: 70),
  );
  final id = await state.logConsumedFood(_food('food-15a'), 100);
  expect(id, isNotNull, reason: 'the food is persisted');
  await state.incrementWaterForDate(d15);
  await state.loadConsumedToday();
  return state;
}

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — the day follows the clock (plan 237)', () {
      late WorkoutRepository repo;

      setUp(() async {
        repo = await harness.open();
        _clearMockSeeds(repo);
      });
      tearDown(() async => await harness.close());

      // ─── S-23701: the rollover lands on the new day ────────────────────
      test(
        'S-23701 a resume after midnight rolls to an empty new day',
        () async {
          var now = DateTime(2026, 6, 15, 10);
          final state = await _seedDay15(repo, () => now);
          expect(state.consumedToday, hasLength(1));

          now = DateTime(2026, 6, 16, 8);
          final rolled = await state.rolloverIfDayChanged();

          expect(rolled, isTrue);
          expect(state.consumedToday, isEmpty);
          expect(state.todayConsumedCalories, 0);
          expect(state.waterTodayMl, 0);
          expect(state.nutritionTarget, isNotNull);
          expect(
            state.nutritionTarget!.calories,
            2200,
            reason: 'the new day inherits 15 June\'s target',
          );
          final day15Rows = await repo.getConsumedFoodsForDate(d15);
          expect(
            day15Rows,
            hasLength(1),
            reason: 'yesterday\'s row stays in the store',
          );
        },
      );

      // ─── S-23702: the same day never rolls ─────────────────────────────
      test('S-23702 the same day returns false and notifies nobody', () async {
        var now = DateTime(2026, 6, 15, 10);
        final state = await _seedDay15(repo, () => now);

        now = DateTime(2026, 6, 15, 20);
        var calls = 0;
        state.addListener(() => calls++);
        final rolled = await state.rolloverIfDayChanged();

        expect(rolled, isFalse);
        expect(calls, 0, reason: 'a same-day check is silent');
        expect(state.consumedToday, hasLength(1));
      });

      // ─── S-23703: a log after midnight lands on the new day ────────────
      test(
        'S-23703 a log after midnight never appends to yesterday\'s list',
        () async {
          var now = DateTime(2026, 6, 15, 10);
          final state = await _seedDay15(repo, () => now);

          now = DateTime(2026, 6, 16, 8);
          final id = await state.logConsumedFoodAt(_food('food-16a'), 50);

          expect(id, isNotNull);
          expect(state.consumedToday, hasLength(1));
          expect(state.consumedToday.single.sourceFoodId, 'food-16a');
          expect(state.consumedToday.single.dateMs, d16);
          expect(await repo.getConsumedFoodsForDate(d15), hasLength(1));
          expect(await repo.getConsumedFoodsForDate(d16), hasLength(1));
        },
      );

      // ─── S-23704: concurrent rollovers share one run ───────────────────
      test('S-23704 concurrent calls share one rollover', () async {
        // Reference run: one rollover on an identical state, counted.
        var now = DateTime(2026, 6, 15, 10);
        final reference = await _seedDay15(repo, () => now);
        var refCalls = 0;
        reference.addListener(() => refCalls++);
        now = DateTime(2026, 6, 16, 8);
        expect(await reference.rolloverIfDayChanged(), isTrue);
        expect(refCalls, greaterThan(0));

        // The concurrent pair: same seed, same day move.
        _clearMockSeeds(repo);
        now = DateTime(2026, 6, 15, 10);
        final state = await _seedDay15(repo, () => now);
        var calls = 0;
        state.addListener(() => calls++);
        now = DateTime(2026, 6, 16, 8);
        final results = await Future.wait([
          state.rolloverIfDayChanged(),
          state.rolloverIfDayChanged(),
        ]);

        expect(
          results.where((r) => r),
          hasLength(1),
          reason: 'exactly one caller runs the rollover',
        );
        expect(results.where((r) => !r), hasLength(1));
        expect(state.consumedToday, isEmpty);
        expect(
          calls,
          refCalls,
          reason:
              'the in-flight future is shared, so the pair '
              'notifies like a single rollover',
        );
        expect(
          await state.rolloverIfDayChanged(),
          isFalse,
          reason: 'the caches now belong to the new day',
        );
      });

      // ─── S-23707: a log that arrives mid-rollover waits for it ─────────
      test('S-23707 a food logged while the rollover runs freezes the new '
          "day's target", () async {
        var now = DateTime(2026, 6, 15, 10);
        final state = await _seedDay15(repo, () => now);
        now = DateTime(2026, 6, 16, 8);

        // The rollover starts first; the log arrives while it is still
        // reading the new day's target. The log must wait for it, not
        // snapshot the cleared (null, so all-zero) target.
        final rollover = state.rolloverIfDayChanged();
        final id = await state.logConsumedFood(_food('food-16a'), 100);
        await rollover;

        expect(id, isNotNull);
        final row = state.consumedToday.single;
        expect(row.dateMs, d16);
        expect(
          row.targetCalories,
          2200,
          reason: "the row freezes the new day's inherited target",
        );
      });

      // ─── S-23708: a direct rollover marks the day it rolled to ─────────
      test(
        'S-23708 after rolloverToDate the day is not rolled again',
        () async {
          var now = DateTime(2026, 6, 15, 10);
          final state = await _seedDay15(repo, () => now);
          now = DateTime(2026, 6, 16, 8);

          await state.rolloverToDate(d16);

          expect(
            await state.rolloverIfDayChanged(),
            isFalse,
            reason: 'the caches already belong to 16 June',
          );
        },
      );

      // ─── S-23705: nothing loaded means nothing to roll ─────────────────
      test('S-23705 a fresh state never rolls and reads nothing', () async {
        var now = DateTime(2026, 6, 16, 8);
        final state = NutritionState(repo, clock: () => now);

        final rolled = await state.rolloverIfDayChanged();

        expect(rolled, isFalse);
        expect(state.consumedToday, isEmpty);
        expect(
          state.nutritionTarget,
          isNull,
          reason: 'no repository read ran for the fresh state',
        );
      });
    });
  }
}
