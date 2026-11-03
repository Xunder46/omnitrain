// The Fuel card's period words (Stats PR 100, Phase P2b).
//
// The card always opens with its horizon line — `Last 7 days`, built from
// `StatsProgressService.kFuelWindowDays` — whether the window's averages are
// drawn or the row says in words that too few days are logged (D-17204), and
// the logged-days caption reads its `N/7 days logged` text in both.
//
// Scenarios S-17310 (the horizon in both states) and S-17311 (the number is
// the window constant, not a literal).
//
// Both scenarios run on both repositories. The harness is opened and seeded
// in `setUp` and never inside a `testWidgets` body: a widget test body runs
// under `FakeAsync`, where Hive's real file I/O never settles and the test
// hangs forever.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/features/stats/stats_screen.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/repository_harness.dart';

/// Tall enough that the Fuel row and every section below it are laid out, so an
/// assertion on a widget's absence is never just an off-screen miss.
const Size _kTallViewport = Size(400, 2400);

// ─── readers ────────────────────────────────────────────────────────────────

/// Every `Text` under [scope], in document order. A keyed `Text` counts as its
/// own match, so a finder on a figure reads that figure's own label.
List<String> _textsUnder(Finder scope) {
  final texts = <String>[];
  for (final element
      in find
          .descendant(of: scope, matching: find.byType(Text), matchRoot: true)
          .evaluate()) {
    final data = (element.widget as Text).data;
    if (data != null) texts.add(data);
  }
  return texts;
}

/// The label the Fuel figure keyed [key] reads.
String _fuelText(String key) => _textsUnder(find.byKey(Key(key))).single;

// ─── fixtures ───────────────────────────────────────────────────────────────

/// One logged `ConsumedFood` on the local day [daysAgo] days back.
///
/// Fat and fibre default to zero and the consumed amount equals the
/// reference, so with the defaults the row's calories are
/// `4 × (protein + carbs)` and a fixture can name its days in round kcal.
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
/// Every scenario here is asserted on both, so each one starts from a cleared
/// log and seeds its own days.
Future<void> _clearConsumedFoods(WorkoutRepository repo) async {
  const farFutureMs = 4102444800000; // 2100-01-01
  for (final row in await repo.getConsumedFoodsInRange(0, farFutureMs)) {
    await repo.deleteConsumedFood(row.id);
  }
}

/// S-17310's averages fixture: 1000 / 2000 / 2500 kcal and 50 / 100 / 125 g
/// protein on days 1, 3 and 5 — three logged days, so the averages are shown.
/// One completed session on day 2 so the screen is not in its empty state.
Future<void> _seedLoggedDaysOnly(WorkoutRepository repo) async {
  await seedSession(repo, sessionId: 's-fuel', daysAgo: 2);
  await _seedDay(repo, id: 'food-1', daysAgo: 1, protein: 50, calories: 1000);
  await _seedDay(repo, id: 'food-3', daysAgo: 3, protein: 100, calories: 2000);
  await _seedDay(repo, id: 'food-5', daysAgo: 5, protein: 125, calories: 2500);
}

/// S-17310's twin: one completed session and a single logged food day — fewer
/// than `kFuelMinLoggedDays`, so the row says so in words instead of drawing
/// averages, while the horizon line is unchanged.
Future<void> _seedOneLoggedDay(WorkoutRepository repo) async {
  await seedSession(repo, sessionId: 's-fuel', daysAgo: 2);
  await _seedDay(repo, id: 'food-1', daysAgo: 1, protein: 50, calories: 1000);
}

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('Fuel horizon — ${harness.name}', () {
      late WorkoutRepository repo;
      late WorkoutState workoutState;
      late SettingsState settingsState;

      setUp(() async {
        repo = await harness.open();
        await _clearConsumedFoods(repo);
        workoutState = WorkoutState(repo);
        settingsState = SettingsState(repo, fakePreferencesService());
        await settingsState.initialize();
      });

      tearDown(() async {
        await harness.close();
      });

      Future<void> pumpStats(WidgetTester tester) async {
        await tester.binding.setSurfaceSize(_kTallViewport);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: StatsScreen(
              workoutState: workoutState,
              settingsState: settingsState,
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      // ─── S-17310: the horizon in both states ──────────────────────────────

      group('S-17310 averages shown', () {
        setUp(() async {
          await _seedLoggedDaysOnly(repo);
        });

        testWidgets('S-17310 the Fuel card opens with its horizon', (
          tester,
        ) async {
          await pumpStats(tester);

          expect(_fuelText('fuel_horizon'), 'Last 7 days');
          expect(_fuelText('fuel_logged_days'), '3/7 days logged');
          expect(tester.takeException(), isNull);
        });
      });

      group('S-17310 too few logged days', () {
        setUp(() async {
          await _seedOneLoggedDay(repo);
        });

        testWidgets('S-17310 the Fuel card opens with its horizon', (
          tester,
        ) async {
          await pumpStats(tester);

          expect(find.byKey(const Key('fuel_not_enough_days')), findsOneWidget);
          expect(_fuelText('fuel_horizon'), 'Last 7 days');
          expect(_fuelText('fuel_logged_days'), '1/7 days logged');
          expect(tester.takeException(), isNull);
        });
      });

      // ─── S-17311: the number is the window constant ───────────────────────

      group('S-17311', () {
        setUp(() async {
          await _seedLoggedDaysOnly(repo);
        });

        testWidgets('S-17311 the horizon is built from the window constant', (
          tester,
        ) async {
          await pumpStats(tester);

          expect(
            _fuelText('fuel_horizon'),
            'Last ${StatsProgressService.kFuelWindowDays} days',
          );
          expect(StatsProgressService.kFuelWindowDays, 7);
          expect(tester.takeException(), isNull);
        });
      });
    });
  }
}
