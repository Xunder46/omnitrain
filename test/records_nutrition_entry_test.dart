// Records & Trends carries the way back to old nutrition history: the Stats
// screen's Fuel row hides once food has not been logged for a while, so this
// screen's Nutrition entry is how a long-idle user reaches the full history.
//
// The harness is opened and seeded in `setUp`, never inside a `testWidgets`
// body (FakeAsync would hang Hive's real file I/O).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/features/nutrition/nutrition_trend_screen.dart';
import 'package:omnitrain/features/stats/records_and_trends_screen.dart';
import 'package:omnitrain/features/stats/widgets/fuel_section.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/repository_harness.dart';

const Size _kTallViewport = Size(400, 2400);

/// One logged `ConsumedFood` on the local day [daysAgo] days back.
Future<void> _seedFood(
  WorkoutRepository repo, {
  required String id,
  required int daysAgo,
}) async {
  final now = DateTime.now();
  final dateMs = DateTime(
    now.year,
    now.month,
    now.day - daysAgo,
  ).millisecondsSinceEpoch;
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
      protein: 30,
      carbs: 50,
      fiber: 0,
      fat: 0,
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

/// The Mock harness opens with a now-relative demo food log; the Hive harness
/// opens empty. Start both from an empty log.
Future<void> _clearConsumedFoods(WorkoutRepository repo) async {
  const farFutureMs = 4102444800000; // 2100-01-01
  for (final row in await repo.getConsumedFoodsInRange(0, farFutureMs)) {
    await repo.deleteConsumedFood(row.id);
  }
}

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    // `seedOldFood` is applied in `setUp`, never in a test body.
    for (final seedOldFood in [true, false]) {
      group(
        'Records & Trends nutrition entry — ${harness.name}, '
        '${seedOldFood ? 'food logged 60 days ago' : 'no food ever logged'}',
        () {
          late WorkoutRepository repo;
          late WorkoutState workoutState;
          late SettingsState settingsState;

          setUp(() async {
            repo = await harness.open();
            await _clearConsumedFoods(repo);
            if (seedOldFood) await _seedFood(repo, id: 'old-food', daysAgo: 60);
            workoutState = WorkoutState(repo);
            settingsState = SettingsState(repo, fakePreferencesService());
            await settingsState.initialize();
          });

          tearDown(() async {
            await harness.close();
          });

          Future<void> pumpRecords(WidgetTester tester) async {
            await tester.binding.setSurfaceSize(_kTallViewport);
            addTearDown(() => tester.binding.setSurfaceSize(null));
            await tester.pumpWidget(
              MaterialApp(
                home: RecordsAndTrendsScreen(
                  workoutState: workoutState,
                  settingsState: settingsState,
                ),
              ),
            );
            await tester.pumpAndSettle();
          }

          if (seedOldFood) {
            testWidgets('old history still offers the full nutrition view', (
              tester,
            ) async {
              await pumpRecords(tester);

              // The Stats screen's own Fuel window would hide this history.
              expect(find.byType(FuelSection), findsNothing);
              final entry = find.byKey(const Key('records_nutrition_entry'));
              expect(entry, findsOneWidget);

              await tester.tap(entry);
              await tester.pumpAndSettle();

              expect(find.byType(NutritionTrendScreen), findsOneWidget);
            });
          } else {
            testWidgets('no nutrition entry when nothing was ever logged', (
              tester,
            ) async {
              await pumpRecords(tester);

              expect(
                find.byKey(const Key('records_nutrition_entry')),
                findsNothing,
              );
            });
          }
        },
      );
    }
  }
}
