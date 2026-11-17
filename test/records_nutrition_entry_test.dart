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
import 'package:omnitrain/features/stats/widgets/recent_pr_list.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/repository_harness.dart';

const Size _kTallViewport = Size(400, 2400);

/// The viewport of the plan-222 order scenarios: tall enough that the ALL TIME
/// card, the PR list, the Nutrition entry and the search field are all laid
/// out at once, so their positions can be compared without scrolling.
const Size _kOrderViewport = Size(400, 1200);

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

  // Plan 222: the entry's position relative to the Recent PRs. Widget tests,
  // so Mock only: the loop above runs this file on the Hive harness too, and
  // a Hive-backed widget test body hangs under FakeAsync.
  group('plan 222 — order', () {
    late WorkoutRepository repo;
    late WorkoutState workoutState;
    late SettingsState settingsState;

    setUp(() async {
      repo = await MockRepositoryHarness().open();
      await _clearConsumedFoods(repo);
      workoutState = WorkoutState(repo);
      settingsState = SettingsState(repo, fakePreferencesService());
      await settingsState.initialize();
    });

    Future<void> pumpRecords(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(_kOrderViewport);
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

    testWidgets('S-22201 with a recent PR and old food logged, the entry '
        'sits below the PR list and above the search field', (tester) async {
      await seedSession(repo, sessionId: 's-lift', daysAgo: 2);
      await seedSetEffort(
        repo,
        segmentId: 'seg-s-lift',
        effortId: 'eff-s-lift',
        exerciseId: 'ex-bench',
        entryCount: 1,
        hasExtraWeight: false,
        weightFactor: 100,
        repsBase: 5,
      );
      await _seedFood(repo, id: 'old-food', daysAgo: 60);
      await pumpRecords(tester);

      final entry = find.byKey(const Key('records_nutrition_entry'));
      final prList = find.byType(RecentPRList);
      final search = find.byKey(
        const Key('records_and_trends_search_field'),
      );
      expect(entry, findsOneWidget);
      expect(prList, findsOneWidget);
      expect(
        tester.getTopLeft(entry).dy,
        greaterThan(tester.getBottomLeft(prList).dy),
      );
      expect(
        tester.getBottomLeft(entry).dy,
        lessThan(tester.getTopLeft(search).dy),
      );
    });

    testWidgets('S-22202 with food logged and no PR available, the entry '
        'stays between the ALL TIME card and the search field', (tester) async {
      // A history whose only exercise is cardio with no distance: a timed
      // effort with finished instances and no observations. It yields a
      // summary (cardio reads as duration without distance) but no recent PR
      // — the PR scan covers only lifts with a logged set.
      await seedExercise(repo, id: 'ex-ride', name: 'Easy Ride');
      await seedSession(repo, sessionId: 's-ride', daysAgo: 3);
      await seedHoldEffort(
        repo,
        segmentId: 'seg-s-ride',
        effortId: 'eff-s-ride',
        exerciseId: 'ex-ride',
        entryCount: 4,
        effortKind: 'timed',
      );
      await _seedFood(repo, id: 'old-food', daysAgo: 60);
      await pumpRecords(tester);

      final entry = find.byKey(const Key('records_nutrition_entry'));
      expect(entry, findsOneWidget);
      expect(find.byType(RecentPRList), findsNothing);
      final search = find.byKey(
        const Key('records_and_trends_search_field'),
      );
      final allTime = find.text('ALL TIME');
      expect(allTime, findsOneWidget);
      expect(
        tester.getTopLeft(entry).dy,
        greaterThan(tester.getBottomLeft(allTime).dy),
      );
      expect(
        tester.getBottomLeft(entry).dy,
        lessThan(tester.getTopLeft(search).dy),
      );
    });

    testWidgets('S-22203 with a recent PR and no food logged, the entry is '
        'absent', (tester) async {
      await seedSession(repo, sessionId: 's-lift', daysAgo: 2);
      await seedSetEffort(
        repo,
        segmentId: 'seg-s-lift',
        effortId: 'eff-s-lift',
        exerciseId: 'ex-bench',
        entryCount: 1,
        hasExtraWeight: false,
        weightFactor: 100,
        repsBase: 5,
      );
      await pumpRecords(tester);

      expect(
        find.byKey(const Key('records_nutrition_entry')),
        findsNothing,
      );
      expect(find.byType(RecentPRList), findsOneWidget);
      expect(
        find.byKey(const Key('records_and_trends_search_field')),
        findsOneWidget,
      );
    });
  });
}
