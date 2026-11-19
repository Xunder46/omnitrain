// The Fuel card's burned-per-day average (plan 208 P3): the mean of the
// platform health store's daily active energy over the same 7 finished days
// d7..d1 the card's other averages use, plus the service half of the
// burn-only card (D-19/D-20).
//
// Scenarios S-20830…S-20837, S-20841…S-20845, S-20848 and the added
// S-20833b/S-20833c, asserted on `StatsProgressService` directly, on both
// repositories, plain `test()` — no `testWidgets`.
//
// Rules under test (plan D-6/D-11/D-19/D-20): a day counts when its value is
// finite and > 0; the average needs `kFuelMinActiveEnergyDays` = 3 such days;
// values keyed outside d7..d1 are ignored; a reader that throws or overruns
// the timeout only hides this line; the summary is `null` only when there is
// neither recent food nor any burn figure.
//
// The Mock harness opens with `SeedData.sampleConsumedFoods()` already
// written, so `setUp` clears the food log before each scenario seeds its own
// days. Every test takes `now` once and keys its reader's map through its own
// `dayKey`, so a midnight crossing cannot split a fixture across two days.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/fuel_summary.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

import 'helpers/repository_harness.dart';

/// One logged `ConsumedFood` on the local day [daysAgo] days back.
///
/// Copied from `test/fuel_burned_summary_test.dart`: with the defaults the
/// day's calories are `4 × (protein + carbs)`, so a fixture names its days in
/// round kcal.
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
/// Copied from `test/fuel_burned_summary_test.dart`.
Future<void> _clearConsumedFoods(WorkoutRepository repo) async {
  const farFutureMs = 4102444800000; // 2100-01-01
  for (final row in await repo.getConsumedFoodsInRange(0, farFutureMs)) {
    await repo.deleteConsumedFood(row.id);
  }
}

/// Three logged days d1, d2, d3 of 2000 kcal each, so the summary is not in
/// burn-only mode.
Future<void> _seedFoodDays(WorkoutRepository repo) async {
  await _seedDay(repo, id: 'food-d1', daysAgo: 1, protein: 0, calories: 2000);
  await _seedDay(repo, id: 'food-d2', daysAgo: 2, protein: 0, calories: 2000);
  await _seedDay(repo, id: 'food-d3', daysAgo: 3, protein: 0, calories: 2000);
}

/// An energy row for session [sessionId]: [activeKcal] kcal, estimated with
/// body weight 80 kg, or measured with no body weight (the model enforces
/// both).
Future<void> _seedEnergy(
  WorkoutRepository repo, {
  required String sessionId,
  required double activeKcal,
  required bool estimated,
}) async {
  await repo.putSessionEnergy(
    SessionEnergy(
      sessionId: sessionId,
      activeKcal: activeKcal,
      source: estimated
          ? SessionEnergy.sourceEstimated
          : SessionEnergy.sourceMeasured,
      bodyWeightKg: estimated ? 80.0 : null,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
  );
}

/// S-20841's two completed sessions: d2 carries a measured 300 kcal row, d4
/// an estimated 500 kcal row.
Future<void> _seedBurnSessions(WorkoutRepository repo) async {
  await _seedEnergy(
    repo,
    sessionId: 'burn-d2',
    activeKcal: 300.0,
    estimated: false,
  );
  await _seedEnergy(
    repo,
    sessionId: 'burn-d4',
    activeKcal: 500.0,
    estimated: true,
  );
  await seedSession(repo, sessionId: 'burn-d2', daysAgo: 2);
  await seedSession(repo, sessionId: 'burn-d4', daysAgo: 4);
}

/// Local midnight of the day after the first DST change in 2026, or null when
/// the zone has none. Copied from `test/stats_dst_day_arithmetic_test.dart`.
DateTime? _dayAfterFirstDstChange() {
  for (
    var d = DateTime(2026, 1, 1);
    d.year == 2026;
    d = DateTime(d.year, d.month, d.day + 1)
  ) {
    final next = DateTime(d.year, d.month, d.day + 1);
    if (next.difference(d) != const Duration(hours: 24)) return next;
  }
  return null;
}

/// S-20830's seven window days: d1 520 … d7 550.
const Map<int, int> _s20830ByDaysAgo = {
  1: 520,
  2: 480,
  3: 610,
  4: 450,
  5: 530,
  6: 500,
  7: 550,
};

/// The `readDailyActiveEnergy` a scenario passes: answers with the given
/// map (keyed by day-start epoch ms) and records each `dayStarts` list.
typedef _DailyRead = Future<Map<int, double>> Function(List<DateTime>);

_DailyRead _reader(Map<int, double> values, {List<List<DateTime>>? calls}) =>
    (dayStarts) async {
      calls?.add(List.of(dayStarts));
      return values;
    };

/// A fixture given as "dN value" pairs, keyed the way the service keys its
/// averages: the day-start epoch ms of the day [daysAgo] days back.
Map<int, double> _keyed(
  int Function(int daysAgo) dayKey,
  Map<int, num> pairs,
) => {for (final e in pairs.entries) dayKey(e.key): e.value.toDouble()};

/// Every `FuelSummary` field except `burnedPerDayAverage`, so S-20837 can pin
/// that a failed health read hides only that line.
void _expectSameExceptBurnedPerDay(FuelSummary withReader, FuelSummary base) {
  expect(withReader.loggedDays, base.loggedDays);
  expect(withReader.caloriesAverage, base.caloriesAverage);
  expect(withReader.proteinAverage, base.proteinAverage);
  expect(withReader.carbsAverage, base.carbsAverage);
  expect(withReader.fatAverage, base.fatAverage);
  expect(withReader.previousCaloriesAverage, base.previousCaloriesAverage);
  expect(withReader.previousProteinAverage, base.previousProteinAverage);
  expect(withReader.previousCarbsAverage, base.previousCarbsAverage);
  expect(withReader.previousFatAverage, base.previousFatAverage);
  expect(withReader.trainingCaloriesAverage, base.trainingCaloriesAverage);
  expect(withReader.trainingLoggedDays, base.trainingLoggedDays);
  expect(withReader.restCaloriesAverage, base.restCaloriesAverage);
  expect(withReader.restLoggedDays, base.restLoggedDays);
  expect(withReader.burnedKcalAverage, base.burnedKcalAverage);
  expect(withReader.burnedSessionCount, base.burnedSessionCount);
  expect(withReader.burnedIsEstimate, base.burnedIsEstimate);
  expect(withReader.hasRecentFood, base.hasRecentFood);
  expect(withReader.targetCalories, base.targetCalories);
  expect(withReader.targetProtein, base.targetProtein);
  expect(withReader.targetCarbs, base.targetCarbs);
  expect(withReader.targetFat, base.targetFat);
}

void main() {
  final dstToday = _dayAfterFirstDstChange();
  const noDstSkip = 'time zone without DST';

  test('S-20833c averageActiveEnergy ignores a key outside the day list', () {
    final now = DateTime.now();
    int dayKey(int daysAgo) =>
        DateTime(now.year, now.month, now.day - daysAgo).millisecondsSinceEpoch;
    final today = DateTime(now.year, now.month, now.day);

    final average = StatsProgressService.averageActiveEnergy(
      // d40 has no day in the window, so its 9000 must not reach the mean.
      {dayKey(1): 600, dayKey(2): 400, dayKey(3): 500, dayKey(40): 9000},
      StatsProgressService.fuelWindowDayStarts(today),
    );

    // (600 + 400 + 500) / 3 — counting d40's 9000 would read 3500.
    expect(average, 500.0);
  });

  test(
    'S-20835 DST window: fuelWindowDayStarts stays on local midnight across '
    'the first 2026 DST change',
    skip: dstToday == null ? noDstSkip : false,
    () {
      final today = DateTime(dstToday!.year, dstToday.month, dstToday.day + 3);

      final days = StatsProgressService.fuelWindowDayStarts(today);

      expect(days.length, 7);
      for (final d in days) {
        expect(d.hour, 0);
        expect(d.minute, 0);
      }
      // Consecutive calendar days — a 24 h step across the DST change drifts
      // to 23:00 or 01:00 and would fail the hour check above.
      for (var i = 1; i < days.length; i++) {
        expect(
          days[i],
          DateTime(days[i - 1].year, days[i - 1].month, days[i - 1].day + 1),
        );
      }
      expect(days.last, DateTime(today.year, today.month, today.day - 1));
    },
  );

  test('S-20835 ordinary date: 7 local midnights, oldest first', () {
    final days = StatsProgressService.fuelWindowDayStarts(
      DateTime(2026, 7, 15),
    );

    expect(days, [for (var k = 7; k >= 1; k--) DateTime(2026, 7, 15 - k)]);
  });

  for (final factory in harnessFactories) {
    final harness = factory();

    group('Fuel burned per day — ${harness.name}', () {
      late WorkoutRepository repo;

      setUp(() async {
        repo = await harness.open();
        await _clearConsumedFoods(repo);
      });

      tearDown(() async {
        await harness.close();
      });

      test('S-20830 seven days of active energy average to the mean', () async {
        final now = DateTime.now();
        int dayKey(int daysAgo) => DateTime(
          now.year,
          now.month,
          now.day - daysAgo,
        ).millisecondsSinceEpoch;
        await _seedFoodDays(repo);

        final summary = await StatsProgressService(repo).computeFuelSummary(
          readDailyActiveEnergy: _reader(_keyed(dayKey, _s20830ByDaysAgo)),
        );

        expect(summary, isNotNull);
        // (520 + 480 + 610 + 450 + 530 + 500 + 550) / 7 = 3640 / 7.
        expect(summary!.burnedPerDayAverage, 520.0);
      });

      test('S-20831 exactly 3 days is enough for the average', () async {
        final now = DateTime.now();
        int dayKey(int daysAgo) => DateTime(
          now.year,
          now.month,
          now.day - daysAgo,
        ).millisecondsSinceEpoch;
        await _seedFoodDays(repo);

        final summary = await StatsProgressService(repo).computeFuelSummary(
          readDailyActiveEnergy: _reader(
            _keyed(dayKey, {1: 600, 3: 400, 5: 500}),
          ),
        );

        expect(summary, isNotNull);
        // (600 + 400 + 500) / 3 — the floor is exactly 3 counted days.
        expect(summary!.burnedPerDayAverage, 500.0);
      });

      test(
        'S-20832 exactly 2 days stays below the floor, summary still returned',
        () async {
          final now = DateTime.now();
          int dayKey(int daysAgo) => DateTime(
            now.year,
            now.month,
            now.day - daysAgo,
          ).millisecondsSinceEpoch;
          await _seedFoodDays(repo);

          final summary = await StatsProgressService(repo).computeFuelSummary(
            readDailyActiveEnergy: _reader(_keyed(dayKey, {1: 600, 2: 400})),
          );

          // Recent food keeps the card alive even without a burn line.
          expect(summary, isNotNull);
          expect(summary!.burnedPerDayAverage, isNull);
        },
      );

      test('S-20833 zero, NaN and negative days are no data', () async {
        final now = DateTime.now();
        int dayKey(int daysAgo) => DateTime(
          now.year,
          now.month,
          now.day - daysAgo,
        ).millisecondsSinceEpoch;
        await _seedFoodDays(repo);

        final summary = await StatsProgressService(repo).computeFuelSummary(
          readDailyActiveEnergy: _reader(
            _keyed(dayKey, {
              1: 600,
              2: 0,
              3: 400,
              4: 500,
              5: double.nan,
              6: -10,
            }),
          ),
        );

        expect(summary, isNotNull);
        // (600 + 400 + 500) / 3 — counting the 0 would read 375.
        expect(summary!.burnedPerDayAverage, 500.0);
      });

      test('S-20833b an infinite day is no data too', () async {
        final now = DateTime.now();
        int dayKey(int daysAgo) => DateTime(
          now.year,
          now.month,
          now.day - daysAgo,
        ).millisecondsSinceEpoch;
        await _seedFoodDays(repo);

        final summary = await StatsProgressService(repo).computeFuelSummary(
          readDailyActiveEnergy: _reader(
            _keyed(dayKey, {1: 600, 2: 400, 3: 500, 4: double.infinity}),
          ),
        );

        expect(summary, isNotNull);
        // (600 + 400 + 500) / 3 — the infinite day is dropped, not summed.
        expect(summary!.burnedPerDayAverage, 500.0);
      });

      test(
        'S-20834 the reader gets exactly d7..d1 and is called once',
        () async {
          final now = DateTime.now();
          int dayKey(int daysAgo) => DateTime(
            now.year,
            now.month,
            now.day - daysAgo,
          ).millisecondsSinceEpoch;
          final calls = <List<DateTime>>[];
          await _seedFoodDays(repo);

          final summary = await StatsProgressService(repo).computeFuelSummary(
            readDailyActiveEnergy: _reader(
              _keyed(dayKey, {0: 999, 8: 999, 1: 300, 4: 450, 7: 600}),
              calls: calls,
            ),
          );

          expect(summary, isNotNull);
          // (300 + 450 + 600) / 3 — d0 and d8 fall outside d7..d1.
          expect(summary!.burnedPerDayAverage, 450.0);
          expect(calls, hasLength(1));
          expect(calls.single, [
            for (var k = 7; k >= 1; k--)
              DateTime(now.year, now.month, now.day - k),
          ]);
        },
      );

      test(
        'S-20836 the burn line is independent of the food-days gate',
        () async {
          final now = DateTime.now();
          int dayKey(int daysAgo) => DateTime(
            now.year,
            now.month,
            now.day - daysAgo,
          ).millisecondsSinceEpoch;
          // Only d1 and d2 logged — below the 3-day food floor.
          await _seedDay(
            repo,
            id: 'food-d1',
            daysAgo: 1,
            protein: 0,
            calories: 2000,
          );
          await _seedDay(
            repo,
            id: 'food-d2',
            daysAgo: 2,
            protein: 0,
            calories: 2000,
          );

          final summary = await StatsProgressService(repo).computeFuelSummary(
            readDailyActiveEnergy: _reader(_keyed(dayKey, _s20830ByDaysAgo)),
          );

          expect(summary, isNotNull);
          expect(summary!.loggedDays, 2);
          expect(summary.showsAverages, isFalse);
          expect(summary.burnedPerDayAverage, 520.0);
        },
      );

      test(
        'S-20837 a throwing reader hides only the burned-per-day line',
        () async {
          final now = DateTime.now();
          int dayKey(int daysAgo) => DateTime(
            now.year,
            now.month,
            now.day - daysAgo,
          ).millisecondsSinceEpoch;
          await _seedFoodDays(repo);
          final base = await StatsProgressService(repo).computeFuelSummary();
          expect(base, isNotNull);
          expect(base!.burnedPerDayAverage, isNull);

          final summary = await StatsProgressService(repo).computeFuelSummary(
            readDailyActiveEnergy: _reader(_keyed(dayKey, _s20830ByDaysAgo)),
          );
          expect(summary, isNotNull);

          final failed = await StatsProgressService(repo).computeFuelSummary(
            readDailyActiveEnergy: (_) =>
                Future.error(StateError('health down')),
          );

          expect(failed, isNotNull);
          expect(failed!.burnedPerDayAverage, isNull);
          _expectSameExceptBurnedPerDay(failed, base);
        },
      );

      test(
        'S-20837 a reader that never completes times out to the same result',
        () async {
          await _seedFoodDays(repo);
          final base = await StatsProgressService(repo).computeFuelSummary();
          expect(base, isNotNull);
          expect(base!.burnedPerDayAverage, isNull);

          final failed = await StatsProgressService(repo).computeFuelSummary(
            readDailyActiveEnergy: (_) => Completer<Map<int, double>>().future,
            activeEnergyTimeout: const Duration(milliseconds: 50),
          );

          expect(failed, isNotNull);
          expect(failed!.burnedPerDayAverage, isNull);
          _expectSameExceptBurnedPerDay(failed, base);
        },
      );

      test('S-20841 session burn alone keeps a burn-only summary', () async {
        await _seedBurnSessions(repo);

        final summary = await StatsProgressService(repo).computeFuelSummary();

        expect(summary, isNotNull);
        expect(summary!.hasRecentFood, isFalse);
        expect(summary.loggedDays, 0);
        expect(summary.caloriesAverage, isNull);
        // (300 + 500) / 2 sessions, one estimated.
        expect(summary.burnedKcalAverage, 400.0);
        expect(summary.burnedSessionCount, 2);
        expect(summary.burnedIsEstimate, isTrue);
        expect(summary.burnedPerDayAverage, isNull);
      });

      test(
        'S-20842 no food and no counted burn day: nothing to show',
        () async {
          final now = DateTime.now();
          int dayKey(int daysAgo) => DateTime(
            now.year,
            now.month,
            now.day - daysAgo,
          ).millisecondsSinceEpoch;
          // A completed session without an energy row is no burn figure.
          await seedSession(repo, sessionId: 'rowless-d3', daysAgo: 3);

          // (a) Two counted days are below the floor.
          final twoDays = await StatsProgressService(repo).computeFuelSummary(
            readDailyActiveEnergy: _reader(_keyed(dayKey, {1: 600, 2: 400})),
          );
          expect(twoDays, isNull);

          // (b) No counted day at all.
          final empty = await StatsProgressService(
            repo,
          ).computeFuelSummary(readDailyActiveEnergy: _reader({}));
          expect(empty, isNull);
        },
      );

      test('S-20843 food alone: today\'s card without a burn line', () async {
        await _seedFoodDays(repo);

        final summary = await StatsProgressService(
          repo,
        ).computeFuelSummary(readDailyActiveEnergy: _reader({}));

        expect(summary, isNotNull);
        expect(summary!.hasRecentFood, isTrue);
        expect(summary.loggedDays, 3);
        expect(summary.burnedKcalAverage, isNull);
        expect(summary.burnedPerDayAverage, isNull);
      });

      test('S-20844 burn-only mode can carry both burn lines', () async {
        final now = DateTime.now();
        int dayKey(int daysAgo) => DateTime(
          now.year,
          now.month,
          now.day - daysAgo,
        ).millisecondsSinceEpoch;
        await _seedBurnSessions(repo);

        final summary = await StatsProgressService(repo).computeFuelSummary(
          readDailyActiveEnergy: _reader(_keyed(dayKey, _s20830ByDaysAgo)),
        );

        expect(summary, isNotNull);
        expect(summary!.burnedPerDayAverage, 520.0);
        // (300 + 500) / 2.
        expect(summary.burnedKcalAverage, 400.0);
      });

      test('S-20845 food on d13 counts as recent, d14 does not', () async {
        // (a) d13 is the last visible day.
        await _seedDay(
          repo,
          id: 'food-d13',
          daysAgo: 13,
          protein: 0,
          calories: 2000,
        );

        final visible = await StatsProgressService(
          repo,
        ).computeFuelSummary(readDailyActiveEnergy: _reader({}));

        expect(visible, isNotNull);
        expect(visible!.hasRecentFood, isTrue);
        // d13 is outside the d7..d1 averages window.
        expect(visible.loggedDays, 0);

        // (b) d14 is already out of the visibility window.
        await _clearConsumedFoods(repo);
        await _seedDay(
          repo,
          id: 'food-d14',
          daysAgo: 14,
          protein: 0,
          calories: 2000,
        );

        final hidden = await StatsProgressService(
          repo,
        ).computeFuelSummary(readDailyActiveEnergy: _reader({}));

        expect(hidden, isNull);
      });

      test('S-20848 health burn alone makes a burn-only summary', () async {
        final now = DateTime.now();
        int dayKey(int daysAgo) => DateTime(
          now.year,
          now.month,
          now.day - daysAgo,
        ).millisecondsSinceEpoch;

        final summary = await StatsProgressService(repo).computeFuelSummary(
          readDailyActiveEnergy: _reader(_keyed(dayKey, _s20830ByDaysAgo)),
        );

        expect(summary, isNotNull);
        expect(summary!.hasRecentFood, isFalse);
        expect(summary.burnedPerDayAverage, 520.0);
        expect(summary.burnedKcalAverage, isNull);
      });
    });
  }
}
