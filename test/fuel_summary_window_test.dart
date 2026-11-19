// The Fuel summary's window (99c P1): the [kFuelWindowDays] finished days
// ending yesterday, the previous range the same length before it, and the
// visibility rule over the last [kFuelVisibilityDays] days, today included.
//
// Scenarios S-17201…S-17204, asserted on `StatsProgressService
// .computeFuelSummary()` directly, on both repositories.
//
// The Mock harness opens with `SeedData.sampleConsumedFoods()` already
// written, so `setUp` clears the food log before each scenario seeds its own
// days. Days are named "days ago" from the real clock.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

import 'helpers/repository_harness.dart';

/// One logged `ConsumedFood` on the local day [daysAgo] days back.
///
/// Copied from `test/fuel_row_screen_test.dart`: with the defaults the day's
/// calories are `4 × (protein + carbs)`, so a fixture names its days in round
/// kcal.
Future<void> _seedFood(
  WorkoutRepository repo, {
  required String id,
  required int daysAgo,
  required double protein,
  required double carbs,
  double fat = 0,
  double fiber = 0,
}) async {
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day - daysAgo);
  final dateMs = day.millisecondsSinceEpoch;
  await repo.createConsumedFood(
    ConsumedFood(
      id: id,
      loggedAtMs: dateMs + (12 * 60 * 60 * 1000),
      dateMs: dateMs,
      sourceFoodId: id,
      name: id,
      unitType: FoodUnitType.grams,
      referenceAmount: 100,
      referenceLabel: '100 g',
      protein: protein,
      carbs: carbs,
      fiber: fiber,
      fat: fat,
      sodium: null,
      amountConsumed: 100,
      groupIdSnapshot: 'food-group-proteins',
      groupNameSnapshot: 'Proteins',
      targetCalories: 0,
      targetProtein: 0,
      targetCarbs: 0,
      targetFat: 0,
      createdAtMs: dateMs,
      updatedAtMs: dateMs,
    ),
  );
}

/// A logged day of [calories] kcal and [protein] g, as the fixture's own macro
/// pair: `4 × (protein + carbs)` with no fat.
Future<void> _seedDay(
  WorkoutRepository repo, {
  required String id,
  required int daysAgo,
  required double protein,
  required double calories,
  double? carbs,
  double fat = 0,
  double fiber = 0,
}) => _seedFood(
  repo,
  id: id,
  daysAgo: daysAgo,
  protein: protein,
  carbs: carbs ?? (calories / 4) - protein,
  fat: fat,
  fiber: fiber,
);

/// The repository's food log, emptied.
///
/// The Mock harness opens with `SeedData.sampleConsumedFoods()` already
/// written — a now-relative demo log — while the Hive harness opens empty.
/// Copied from `test/fuel_row_screen_test.dart`.
Future<void> _clearConsumedFoods(WorkoutRepository repo) async {
  const farFutureMs = 4102444800000; // 2100-01-01
  for (final row in await repo.getConsumedFoodsInRange(0, farFutureMs)) {
    await repo.deleteConsumedFood(row.id);
  }
}

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('Fuel summary window — ${harness.name}', () {
      late WorkoutRepository repo;

      setUp(() async {
        repo = await harness.open();
        await _clearConsumedFoods(repo);
      });

      tearDown(() async {
        await harness.close();
      });

      test('S-17201 window is the 7 finished days ending yesterday', () async {
        await _seedDay(repo, id: 'food-d0', daysAgo: 0, protein: 0, calories: 4000);
        await _seedDay(repo, id: 'food-d1', daysAgo: 1, protein: 0, calories: 1000);
        await _seedDay(repo, id: 'food-d7', daysAgo: 7, protein: 0, calories: 3000);
        await _seedDay(repo, id: 'food-d8', daysAgo: 8, protein: 0, calories: 5000);

        final summary = await StatsProgressService(repo).computeFuelSummary();

        expect(summary, isNotNull);
        // d1 and d7 are in; today (d0) and d8 are out of the window.
        expect(summary!.loggedDays, 2);
        expect(summary.caloriesAverage, 2000); // (1000 + 3000) / 2
        // The previous range d8..d14 holds only d8.
        expect(summary.previousCaloriesAverage, 5000);
      });

      test('S-17202 three logged days show averages, two do not', () async {
        await _seedDay(repo, id: 'food-d1', daysAgo: 1, protein: 0, calories: 1000);
        await _seedDay(repo, id: 'food-d2', daysAgo: 2, protein: 0, calories: 1000);
        await _seedDay(repo, id: 'food-d3', daysAgo: 3, protein: 0, calories: 1000);

        final three = await StatsProgressService(repo).computeFuelSummary();

        expect(three, isNotNull);
        expect(three!.loggedDays, 3);
        expect(three.showsAverages, isTrue);

        await _clearConsumedFoods(repo);
        await _seedDay(repo, id: 'food-d1', daysAgo: 1, protein: 0, calories: 1000);
        await _seedDay(repo, id: 'food-d2', daysAgo: 2, protein: 0, calories: 1000);

        final two = await StatsProgressService(repo).computeFuelSummary();

        expect(two, isNotNull);
        expect(two!.loggedDays, 2);
        expect(two.showsAverages, isFalse);
      });

      test('S-17203 a session started today does not make a training day', () async {
        await _seedDay(repo, id: 'food-d0', daysAgo: 0, protein: 0, calories: 4000);
        await _seedDay(repo, id: 'food-d1', daysAgo: 1, protein: 0, calories: 1000);
        // Completed, but it started today — outside the window, which ends
        // yesterday.
        await seedSession(repo, sessionId: 's-fuel', daysAgo: 0);

        final summary = await StatsProgressService(repo).computeFuelSummary();

        expect(summary, isNotNull);
        expect(summary!.loggedDays, 1); // d1 only; today is out
        expect(summary.trainingCaloriesAverage, isNull);
        expect(summary.restCaloriesAverage, 1000);
      });

      test('S-17204 visibility: today alone shows, d14 hides, d13 is previous', () async {
        // Food only today: the row appears, but the window holds nothing.
        await _seedDay(repo, id: 'food-d0', daysAgo: 0, protein: 0, calories: 4000);

        final todayOnly = await StatsProgressService(repo).computeFuelSummary();

        expect(todayOnly, isNotNull);
        expect(todayOnly!.loggedDays, 0);
        expect(todayOnly.caloriesAverage, isNull);

        // Food only 14 days back: outside the visibility span, the row hides.
        await _clearConsumedFoods(repo);
        await _seedDay(repo, id: 'food-d14', daysAgo: 14, protein: 0, calories: 2500);

        final d14Only = await StatsProgressService(repo).computeFuelSummary();

        expect(d14Only, isNull);

        // Food only 13 days back: still visible, and it lands in the previous
        // range d8..d14.
        await _clearConsumedFoods(repo);
        await _seedDay(repo, id: 'food-d13', daysAgo: 13, protein: 0, calories: 2500);

        final d13Only = await StatsProgressService(repo).computeFuelSummary();

        expect(d13Only, isNotNull);
        expect(d13Only!.loggedDays, 0);
        expect(d13Only.previousCaloriesAverage, 2500);
      });

      // Twin of S-17201 guarding the previous range's oldest day: the range
      // is days 8..14 ago (windowStart = day 7, previousStart = day 14), so
      // d8 and d14 are in it, d15 is before it and d1 is in the window.
      test('S-17201 twin previous range keeps its oldest day, d14', () async {
        await _seedDay(repo, id: 'food-d1', daysAgo: 1, protein: 0, calories: 1000);
        await _seedDay(repo, id: 'food-d8', daysAgo: 8, protein: 0, calories: 4000);
        await _seedDay(repo, id: 'food-d14', daysAgo: 14, protein: 0, calories: 2000);
        await _seedDay(repo, id: 'food-d15', daysAgo: 15, protein: 0, calories: 9000);

        final summary = await StatsProgressService(repo).computeFuelSummary();

        expect(summary, isNotNull);
        // d1 is the window's only logged day; d15 is outside the previous
        // range d8..d14.
        expect(summary!.loggedDays, 1);
        expect(summary.caloriesAverage, 1000);
        // (4000 + 2000) / 2 — d14 must count, d15 must not.
        expect(summary.previousCaloriesAverage, 3000);
      });
    });
  }
}
