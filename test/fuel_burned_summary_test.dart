// The Fuel summary's burned-per-session average (134b P1): the mean stored
// active kcal over the window's finished sessions that carry an energy row.
//
// Scenarios S-13430…S-13433, asserted on `StatsProgressService
// .computeFuelSummary()` directly, on both repositories, plain `test()`.
//
// The window is the same 7 finished days ending yesterday the card's other
// averages use (S-13430): the exclusion arms — today, d8, and an unfinished
// rolling session — must not contribute to the mean, the count or the
// estimate flag.
//
// The Mock harness opens with `SeedData.sampleConsumedFoods()` already
// written, so `setUp` clears the food log before each scenario seeds its own
// days. Days are named "days ago" from the real clock; sessions come from
// `seedSession` (completed, unended with `isRolling: true`).

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

import 'helpers/repository_harness.dart';

/// One logged `ConsumedFood` on the local day [daysAgo] days back.
///
/// Copied from `test/fuel_summary_window_test.dart`: with the defaults the
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
/// Copied from `test/fuel_summary_window_test.dart`.
Future<void> _clearConsumedFoods(WorkoutRepository repo) async {
  const farFutureMs = 4102444800000; // 2100-01-01
  for (final row in await repo.getConsumedFoodsInRange(0, farFutureMs)) {
    await repo.deleteConsumedFood(row.id);
  }
}

/// Three logged days d1, d2, d3, so `computeFuelSummary()` returns a summary
/// for the session-driven scenarios.
Future<void> _seedFoodDays(WorkoutRepository repo) async {
  await _seedDay(repo, id: 'food-d1', daysAgo: 1, protein: 0, calories: 1000);
  await _seedDay(repo, id: 'food-d2', daysAgo: 2, protein: 0, calories: 1000);
  await _seedDay(repo, id: 'food-d3', daysAgo: 3, protein: 0, calories: 1000);
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

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('Fuel summary burned average — ${harness.name}', () {
      late WorkoutRepository repo;

      setUp(() async {
        repo = await harness.open();
        await _clearConsumedFoods(repo);
        await _seedFoodDays(repo);
      });

      tearDown(() async {
        await harness.close();
      });

      test(
        'S-13430 window sessions only: today, d8 and rolling excluded',
        () async {
          await _seedEnergy(
            repo,
            sessionId: 's-d1',
            activeKcal: 300.0,
            estimated: true,
          );
          await _seedEnergy(
            repo,
            sessionId: 's-d3',
            activeKcal: 400.0,
            estimated: false,
          );
          await _seedEnergy(
            repo,
            sessionId: 's-d6',
            activeKcal: 500.0,
            estimated: true,
          );
          await seedSession(repo, sessionId: 's-d1', daysAgo: 1);
          await seedSession(repo, sessionId: 's-d3', daysAgo: 3);
          await seedSession(repo, sessionId: 's-d6', daysAgo: 6);
          await seedSession(
            repo,
            sessionId: 's-d2-rolling',
            daysAgo: 2,
            isRolling: true,
          );
          await _seedEnergy(
            repo,
            sessionId: 's-d2-rolling',
            activeKcal: 8000.0,
            estimated: true,
          );
          await seedSession(repo, sessionId: 's-d0', daysAgo: 0);
          await _seedEnergy(
            repo,
            sessionId: 's-d0',
            activeKcal: 9000.0,
            estimated: true,
          );
          await seedSession(repo, sessionId: 's-d8', daysAgo: 8);
          await _seedEnergy(
            repo,
            sessionId: 's-d8',
            activeKcal: 7000.0,
            estimated: true,
          );

          final summary = await StatsProgressService(repo).computeFuelSummary();

          expect(summary, isNotNull);
          // (300 + 400 + 500) / 3 — d0, d8 and the rolling session contribute
          // to neither the mean nor the count.
          expect(summary!.burnedKcalAverage, 400.0);
          expect(summary.burnedSessionCount, 3);
          // Two estimated rows are inside.
          expect(summary.burnedIsEstimate, isTrue);
        },
      );

      test(
        'S-13431 estimate flag: measured-only false, one estimate true',
        () async {
          // Arm (a): both rows measured.
          await _seedEnergy(
            repo,
            sessionId: 's-d1',
            activeKcal: 250.0,
            estimated: false,
          );
          await _seedEnergy(
            repo,
            sessionId: 's-d2',
            activeKcal: 350.0,
            estimated: false,
          );
          await seedSession(repo, sessionId: 's-d1', daysAgo: 1);
          await seedSession(repo, sessionId: 's-d2', daysAgo: 2);

          final measured = await StatsProgressService(
            repo,
          ).computeFuelSummary();

          expect(measured, isNotNull);
          expect(measured!.burnedKcalAverage, 300.0);
          expect(measured.burnedSessionCount, 2);
          expect(measured.burnedIsEstimate, isFalse);
        },
      );

      test('S-13431 one estimate among measured rows sets the flag', () async {
        // Arm (b): d1 measured, d2 estimated.
        await _seedEnergy(
          repo,
          sessionId: 's-d1',
          activeKcal: 250.0,
          estimated: false,
        );
        await _seedEnergy(
          repo,
          sessionId: 's-d2',
          activeKcal: 350.0,
          estimated: true,
        );
        await seedSession(repo, sessionId: 's-d1', daysAgo: 1);
        await seedSession(repo, sessionId: 's-d2', daysAgo: 2);

        final mixed = await StatsProgressService(repo).computeFuelSummary();

        expect(mixed, isNotNull);
        expect(mixed!.burnedKcalAverage, 300.0);
        expect(mixed.burnedSessionCount, 2);
        expect(mixed.burnedIsEstimate, isTrue);
      });

      test('S-13432 row-less session: mean and count exclude it', () async {
        // d2 has no row; d1 and d3 do. d2's session itself is completed and
        // in the window — it is simply skipped from both.
        await _seedEnergy(
          repo,
          sessionId: 's-d1',
          activeKcal: 300.0,
          estimated: false,
        );
        await _seedEnergy(
          repo,
          sessionId: 's-d3',
          activeKcal: 500.0,
          estimated: false,
        );
        await seedSession(repo, sessionId: 's-d1', daysAgo: 1);
        await seedSession(repo, sessionId: 's-d2', daysAgo: 2);
        await seedSession(repo, sessionId: 's-d3', daysAgo: 3);

        final withRowless = await StatsProgressService(
          repo,
        ).computeFuelSummary();

        expect(withRowless, isNotNull);
        // (300 + 500) / 2 — the row-less session is in neither the sum nor
        // the count.
        expect(withRowless!.burnedKcalAverage, 400.0);
        expect(withRowless.burnedSessionCount, 2);
        expect(withRowless.burnedIsEstimate, isFalse);
      });

      test(
        'S-13432 no rows at all: null average, zero count, no estimate',
        () async {
          await seedSession(repo, sessionId: 's-d1', daysAgo: 1);
          await seedSession(repo, sessionId: 's-d2', daysAgo: 2);

          final noRows = await StatsProgressService(repo).computeFuelSummary();

          expect(noRows, isNotNull);
          expect(noRows!.burnedKcalAverage, isNull);
          expect(noRows.burnedSessionCount, 0);
          expect(noRows.burnedIsEstimate, isFalse);
        },
      );

      test('S-13433 day edges: d7 counts, d8 does not, d1 counts', () async {
        // d8 is estimated so its row would also poison the estimate flag if
        // it sneaked in; d1 and d7 are measured.
        await _seedEnergy(
          repo,
          sessionId: 's-d7',
          activeKcal: 100.0,
          estimated: false,
        );
        await seedSession(repo, sessionId: 's-d7', daysAgo: 7);
        await _seedEnergy(
          repo,
          sessionId: 's-d8',
          activeKcal: 900.0,
          estimated: true,
        );
        await seedSession(repo, sessionId: 's-d8', daysAgo: 8);
        await _seedEnergy(
          repo,
          sessionId: 's-d1',
          activeKcal: 300.0,
          estimated: false,
        );
        await seedSession(repo, sessionId: 's-d1', daysAgo: 1);

        final summary = await StatsProgressService(repo).computeFuelSummary();

        expect(summary, isNotNull);
        // (100 + 300) / 2 — the window's first day is d7, so d8 is out.
        expect(summary!.burnedKcalAverage, 200.0);
        expect(summary.burnedSessionCount, 2);
        expect(summary.burnedIsEstimate, isFalse);
      });
    });
  }
}
