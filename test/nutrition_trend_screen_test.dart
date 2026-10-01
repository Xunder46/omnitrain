// The full-history nutrition trend screen and the NUTRITION card it shares
// with the Stats screen — Stats PR 4b3, Phase 1.
//
// Scenarios S-1109 (the Calories / Macros toggle swaps the plotted datasets)
// and S-1110(a) (the extracted screen's figures equal the Stats NUTRITION
// card's for the same repository — the move, not a rewrite), plus S-1110(b)
// (the zero-session empty state wins over the Fuel row) and the empty-chart
// path.
//
// Plan: `docs/plans/2026-10-01-04b3-stats-pr4b3-fuel-row-plan/`.
//
// The harness is opened and seeded in `setUp` and never inside a `testWidgets`
// body: a widget test body runs under `FakeAsync`, where Hive's real file I/O
// never settles and the test hangs.
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/fuel_summary.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/features/nutrition/nutrition_trend_screen.dart';
import 'package:omnitrain/features/stats/stats_screen.dart';
import 'package:omnitrain/features/stats/widgets/scrollable_trend_chart.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/repository_harness.dart';

/// Tall enough that the NUTRITION card, which sits below every legacy section,
/// is laid out — an assertion on a chart is then never just an off-screen miss.
const Size _kTallViewport = Size(400, 3000);

// ─── finders and readers ────────────────────────────────────────────────────

Finder _scrollable(String unitLabel) => find.byWidgetPredicate(
  (widget) => widget is ScrollableTrendChart && widget.unitLabel == unitLabel,
);

/// The `LineChartData` of the one scrollable chart labelled [unitLabel].
///
/// The NUTRITION calories chart is the only `'kcal'` chart on either screen,
/// and the trend screen renders only that card, so the label identifies it.
LineChartData _chartData(WidgetTester tester, String unitLabel) {
  final finder = _scrollable(unitLabel);
  expect(finder, findsOneWidget);
  return tester
      .widget<LineChart>(
        find.descendant(of: finder, matching: find.byType(LineChart)),
      )
      .data;
}

/// The plotted actuals — the last series, since the dashed target line is
/// drawn first — as `(x, y)` pairs.
List<(double, double)> _actuals(LineChartData data) =>
    data.lineBarsData.last.spots.map((spot) => (spot.x, spot.y)).toList();

// ─── fixtures ───────────────────────────────────────────────────────────────

/// One logged `ConsumedFood` on the local day [daysAgo] days back.
Future<void> _seedFood(
  WorkoutRepository repo, {
  required String id,
  required int daysAgo,
  required double protein,
  required double carbs,
  required double fat,
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
      fiber: 0,
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

/// The repository's food log, emptied.
///
/// The Mock harness opens with `SeedData.sampleConsumedFoods()` already
/// written — a now-relative 23-day demo log — while the Hive harness opens
/// empty. Every scenario here is asserted on both, so each one starts from a
/// cleared log and seeds its own days.
Future<void> _clearConsumedFoods(WorkoutRepository repo) async {
  const farFutureMs = 4102444800000; // 2100-01-01
  for (final row in await repo.getConsumedFoodsInRange(0, farFutureMs)) {
    await repo.deleteConsumedFood(row.id);
  }
}

/// Three logged days, and a target saved before the earliest of them so
/// `computeNutritionAdherence` anchors a target step to the actuals' x-axis.
Future<void> _seedNutrition(WorkoutRepository repo) async {
  await seedSession(repo, sessionId: 's-1', daysAgo: 1);
  await _seedFood(
    repo,
    id: 'food-1',
    daysAgo: 3,
    protein: 100,
    carbs: 200,
    fat: 50,
  );
  await _seedFood(
    repo,
    id: 'food-2',
    daysAgo: 2,
    protein: 150,
    carbs: 250,
    fat: 60,
  );
  await _seedFood(
    repo,
    id: 'food-3',
    daysAgo: 1,
    protein: 120,
    carbs: 220,
    fat: 55,
  );
  await repo.saveNutritionTargetForDate(
    DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day - 5,
    ).millisecondsSinceEpoch,
    NutritionTarget(calories: 2200, protein: 150, carbs: 250, fat: 70),
  );
}

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('Nutrition trend — ${harness.name}', () {
      late WorkoutRepository repo;
      late WorkoutState workoutState;
      late SettingsState settingsState;

      setUp(() async {
        repo = await harness.open();
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

      Future<void> pumpTrend(WidgetTester tester) async {
        await tester.binding.setSurfaceSize(_kTallViewport);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: NutritionTrendScreen(
              workoutState: workoutState,
              settingsState: settingsState,
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      // ─── S-1110(a): the move, not a rewrite ───────────────────────────────

      group('S-1110(a)', () {
        setUp(() async {
          await _clearConsumedFoods(repo);
          await _seedNutrition(repo);
        });

        testWidgets('the trend screen plots the same calories actuals as the '
            'Stats NUTRITION card', (tester) async {
          await pumpStats(tester);
          final statsActuals = _actuals(_chartData(tester, 'kcal'));

          await pumpTrend(tester);
          final trendActuals = _actuals(_chartData(tester, 'kcal'));

          expect(trendActuals, isNotEmpty);
          expect(trendActuals, statsActuals);
        });

        testWidgets('both hosts draw the target line over the same actuals', (
          tester,
        ) async {
          await pumpStats(tester);
          final statsData = _chartData(tester, 'kcal');
          expect(statsData.lineBarsData, hasLength(2));
          expect(find.text('Target (kcal)'), findsOneWidget);

          await pumpTrend(tester);
          final trendData = _chartData(tester, 'kcal');
          expect(trendData.lineBarsData, hasLength(2));
          expect(_actuals(trendData), _actuals(statsData));
        });
      });

      // ─── S-1110(b): the zero-session empty state wins over the Fuel row ───

      group('S-1110(b)', () {
        late FuelSummary? fuelSummary;

        setUp(() async {
          await _clearConsumedFoods(repo);
          // No session at all, so the screen is in its zero-session empty
          // state — while the food log still holds today, which is the food
          // the Fuel row would render from.
          for (final session in await repo.getAllSessions()) {
            await repo.deleteSession(session.id);
          }
          await _seedFood(
            repo,
            id: 'food-today',
            daysAgo: 0,
            protein: 100,
            carbs: 200,
            fat: 50,
          );
          fuelSummary = await StatsProgressService(repo).computeFuelSummary();
        });

        testWidgets('the empty state renders and no Fuel row is in the tree', (
          tester,
        ) async {
          expect(
            fuelSummary,
            isNotNull,
            reason: 'the fixture must produce a Fuel row',
          );

          await pumpStats(tester);

          expect(find.text('No sessions yet'), findsOneWidget);
          expect(find.byKey(const Key('fuel_section')), findsNothing);
        });
      });

      // ─── S-1109: the Calories / Macros toggle ─────────────────────────────

      group('S-1109', () {
        setUp(() async {
          await _clearConsumedFoods(repo);
          await _seedNutrition(repo);
        });

        testWidgets(
          'the toggle swaps the calories dataset for the macros one',
          (tester) async {
            await pumpTrend(tester);

            // Calories view: the kcal chart and its legend.
            expect(_scrollable('kcal'), findsOneWidget);
            expect(_scrollable('g'), findsNothing);
            expect(find.text('Calories (kcal)'), findsOneWidget);

            await tester.tap(find.text('Macros'));
            await tester.pumpAndSettle();

            // Macros view: the grams chart and its three-macro legend.
            expect(_scrollable('kcal'), findsNothing);
            expect(_scrollable('g'), findsOneWidget);
            expect(find.text('Protein (g)'), findsOneWidget);
            expect(find.text('Carbs (g)'), findsOneWidget);
            expect(find.text('Fat (g)'), findsOneWidget);
          },
        );
      });

      // ─── the empty-chart path ─────────────────────────────────────────────

      group('no food logged', () {
        setUp(() => _clearConsumedFoods(repo));

        testWidgets('renders the empty chart, not an error', (tester) async {
          await pumpTrend(tester);

          final data = _chartData(tester, '');
          expect(data.lineBarsData, hasLength(1));
          expect(data.lineBarsData.single.spots, hasLength(7));
          expect(
            data.lineBarsData.single.spots.every((spot) => spot.y == 0),
            isTrue,
          );
          expect(tester.takeException(), isNull);
        });
      });

      // ─── full history, not the soft window ────────────────────────────────

      group('one day logged 30 days back', () {
        // 50P / 50C / 10F = 490 kcal. 30 days is past `kNutritionTrendDays`,
        // so a windowed read would show nothing and the full-history read the
        // single-point fallback.
        setUp(() async {
          await _clearConsumedFoods(repo);
          await _seedFood(
            repo,
            id: 'food-old',
            daysAgo: 30,
            protein: 50,
            carbs: 50,
            fat: 10,
          );
        });

        testWidgets('is still plotted, as the single-point card', (
          tester,
        ) async {
          await pumpTrend(tester);

          expect(find.text('Calories: 490 kcal'), findsOneWidget);
        });
      });
    });
  }
}
