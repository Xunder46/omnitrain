// The Weight block on Stats and its Settings switch (plan 104), scenarios
// S-17705 and S-17706 of `docs/plans/2026-11-03-104-weight-line-plan/`.
//
// The Stats screen reads the device clock, so every fixture counts back from
// today. Seeds and settings writes happen in `setUp`: a Hive write started
// inside a `testWidgets` body never settles under fake async.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/models/app_version_info.dart';
import 'package:omnitrain/core/models/signals.dart';
import 'package:omnitrain/core/services/signals/signal.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/features/settings/settings_screen.dart';
import 'package:omnitrain/features/stats/stats_screen.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';
import 'helpers/repository_harness.dart';

/// Tall enough that every block is laid out.
const Size _kTallViewport = Size(400, 2400);

/// S-18307: a signal that needs no rated weeks, so it speaks while the gate is
/// unmet (card, then the locked hint), and names something it waits for.
class _StackSignal implements Signal {
  @override
  final String id = 'stack-1';

  @override
  final SignalKind kind = SignalKind.positive;

  @override
  final int priority = 10;

  @override
  final bool needsRatedWeeks = false;

  @override
  Future<SignalCard?> evaluate(SignalContext context) async => SignalCard(
    id: id,
    kind: kind,
    priority: priority,
    title: 'Stack',
    observation: 'Last week you logged 4 sessions, above your usual 2.5 a week '
        'over the last 8 weeks.',
  );

  @override
  Future<String?> waitingFor(SignalContext context) async =>
      'Protein Consistency: log food on 9 more days of the last 14.';
}

DateTime _noon(int daysAgo) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day - daysAgo, 12);
}

/// One completed session, so the screen leaves its empty state.
Future<void> _seedSession(WorkoutRepository repo) async {
  final start = _noon(3).millisecondsSinceEpoch;
  await repo.createSession(
    TrainingSession(
      id: 's-1',
      ownerUserId: 'user-1',
      startedAtMs: start,
      endedAtMs: start + 3600000,
      createdAtMs: start,
      updatedAtMs: start,
    ),
  );
}

Future<void> _seedWeight(
  WorkoutRepository repo,
  String id,
  double kg,
  int daysAgo,
) => repo.saveMeasurementEntry(
  BodyMeasurementEntry(
    id: id,
    measurementType: 'bodyweight',
    value: kg,
    unitId: MetricIds.unitKg,
    recordedAtMs: _noon(daysAgo).millisecondsSinceEpoch,
  ),
);

/// The repository's weigh-ins, emptied: the Mock harness may open with samples.
Future<void> _clearWeights(WorkoutRepository repo) async {
  for (final entry in await repo.getMeasurementHistory('bodyweight')) {
    await repo.deleteMeasurementEntry(entry.id);
  }
}

/// The repository's food log, emptied (the Mock harness opens with samples).
Future<void> _clearConsumedFoods(WorkoutRepository repo) async {
  const farFutureMs = 4102444800000; // 2100-01-01
  for (final row in await repo.getConsumedFoodsInRange(0, farFutureMs)) {
    await repo.deleteConsumedFood(row.id);
  }
}

/// One logged food [daysAgo] days back, so the Fuel row shows above the Weight block.
Future<void> _seedFood(WorkoutRepository repo, int daysAgo) async {
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day - daysAgo);
  final dateMs = day.millisecondsSinceEpoch;
  await repo.createConsumedFood(
    ConsumedFood(
      id: 'food-$daysAgo',
      loggedAtMs: dateMs + (12 * 60 * 60 * 1000),
      dateMs: dateMs,
      sourceFoodId: 'food-$daysAgo',
      name: 'food-$daysAgo',
      unitType: FoodUnitType.grams,
      referenceAmount: 100,
      referenceLabel: '100 g',
      protein: 100,
      carbs: 400,
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

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('S-17705 the Weight block — ${harness.name}', () {
      late WorkoutRepository repo;
      late WorkoutState workoutState;
      late SettingsState settingsState;

      setUp(() async {
        repo = await harness.open();
        workoutState = WorkoutState(repo);
        settingsState = SettingsState(repo, fakePreferencesService());
        await settingsState.initialize();
        await _clearWeights(repo);
        await _clearConsumedFoods(repo);
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
              signals: const [],
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      String lineText(WidgetTester tester) =>
          tester.widget<Text>(find.byKey(const Key('weight_trend_line'))).data!;

      group('two weigh-ins 27 days apart', () {
        setUp(() async {
          await _seedSession(repo);
          await _seedWeight(repo, 'w1', 80.8, 27);
          await _seedWeight(repo, 'w2', 80.2, 0);
          await _seedFood(repo, 1);
        });

        testWidgets('the line reads in kilograms and sits below the Fuel row', (
          tester,
        ) async {
          await pumpStats(tester);

          expect(find.byKey(const Key('weight_trend')), findsOneWidget);
          expect(lineText(tester), '80.2 kg, −0.6 kg over 4 weeks');
          expect(find.byKey(const Key('fuel_section')), findsOneWidget);
          expect(
            tester.getTopLeft(find.byKey(const Key('weight_trend'))).dy,
            greaterThan(tester.getTopLeft(find.byKey(const Key('fuel_section'))).dy),
          );
          // The block is its own title and sits one block gap (24 dp) below
          // the Fuel row, like every other pair on the screen.
          expect(
            find.descendant(
              of: find.byKey(const Key('weight_trend')),
              matching: find.text('WEIGHT'),
            ),
            findsOneWidget,
          );
          expect(
            tester.getTopLeft(find.byKey(const Key('weight_trend'))).dy -
                tester.getBottomLeft(find.byKey(const Key('fuel_section'))).dy,
            24,
          );
          expect(tester.takeException(), isNull);
        });
      });

      group('the unit is pounds', () {
        setUp(() async {
          await _seedSession(repo);
          await _seedWeight(repo, 'w1', 80.8, 27);
          await _seedWeight(repo, 'w2', 80.2, 0);
          await settingsState.setPreferredWeightUnit('lbs');
        });

        testWidgets('the same two figures read in pounds', (tester) async {
          await pumpStats(tester);

          expect(lineText(tester), '176.8 lbs, −1.3 lbs over 4 weeks');
        });
      });

      group('the switch is off', () {
        setUp(() async {
          await _seedSession(repo);
          await _seedWeight(repo, 'w1', 80.8, 27);
          await _seedWeight(repo, 'w2', 80.2, 0);
          await settingsState.setShowWeightTrend(false);
        });

        testWidgets('no Weight block shows', (tester) async {
          await pumpStats(tester);

          expect(find.byKey(const Key('weight_trend')), findsNothing);
        });
      });

      group('one weigh-in', () {
        setUp(() async {
          await _seedSession(repo);
          await _seedWeight(repo, 'w2', 80.2, 0);
        });

        testWidgets('no Weight block shows', (tester) async {
          await pumpStats(tester);

          expect(find.byKey(const Key('weight_trend')), findsNothing);
        });
      });

      group('two weigh-ins 6 days apart', () {
        setUp(() async {
          await _seedSession(repo);
          await _seedWeight(repo, 'w1', 80.8, 6);
          await _seedWeight(repo, 'w2', 80.2, 0);
        });

        testWidgets('no Weight block shows', (tester) async {
          await pumpStats(tester);

          expect(find.byKey(const Key('weight_trend')), findsNothing);
        });
      });

      group('weigh-ins but no completed session', () {
        setUp(() async {
          await _seedWeight(repo, 'w1', 80.8, 27);
          await _seedWeight(repo, 'w2', 80.2, 0);
        });

        testWidgets('the empty state shows alone', (tester) async {
          await pumpStats(tester);

          expect(find.text('No sessions yet'), findsOneWidget);
          expect(find.byKey(const Key('weight_trend')), findsNothing);
        });
      });
    });

    group(
      'S-18307 the Weight block under the Signals lines at a phone width — '
      '${harness.name}',
      () {
        late WorkoutRepository repo;
        late WorkoutState workoutState;
        late SettingsState settingsState;

        setUp(() async {
          repo = await harness.open();
          workoutState = WorkoutState(repo);
          settingsState = SettingsState(repo, fakePreferencesService());
          await settingsState.initialize();
          await _clearWeights(repo);
          await _clearConsumedFoods(repo);
          await _seedSession(repo);
          await _seedWeight(repo, 'w1', 80.8, 27);
          await _seedWeight(repo, 'w2', 80.2, 0);
          await _seedFood(repo, 1);
        });

        tearDown(() async {
          await harness.close();
        });

        testWidgets(
          'S-18307 the Signals hint, the waiting lines and the Weight block '
          'fit 390x844 at 1.3x text',
          (tester) async {
            await tester.binding.setSurfaceSize(const Size(390, 844));
            addTearDown(() => tester.binding.setSurfaceSize(null));
            await tester.pumpWidget(
              MediaQuery(
                data: const MediaQueryData(
                  textScaler: TextScaler.linear(1.3),
                ),
                child: MaterialApp(
                  home: StatsScreen(
                    workoutState: workoutState,
                    settingsState: settingsState,
                    signals: [_StackSignal()],
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();

            expect(tester.takeException(), isNull);
            expect(find.byKey(const Key('signal_card_stack-1')), findsOneWidget);
            expect(find.byKey(const Key('signals_layer')), findsOneWidget);
            expect(
              find.byKey(const Key('signals_locked_hint')),
              findsOneWidget,
            );
            expect(find.byKey(const Key('signals_waiting_0')), findsOneWidget);

            await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
            await tester.pumpAndSettle();
            expect(find.byKey(const Key('weight_trend')), findsOneWidget);
            expect(
              tester
                  .widget<Text>(find.byKey(const Key('weight_trend_line')))
                  .data!,
              '80.2 kg, −0.6 kg over 4 weeks',
            );
            expect(
              tester.getBottomLeft(find.byKey(const Key('weight_trend'))).dy,
              lessThanOrEqualTo(844),
            );
            expect(tester.takeException(), isNull);
          },
        );
      },
    );
  }

  // Mock-only: the tap writes a preference, and a Hive write started inside a
  // widget test's fake-async zone never settles.
  group('S-17706 the Weight on Stats switch — Mock', () {
    late MockWorkoutRepository repo;
    late SettingsState settingsState;

    setUp(() async {
      repo = MockWorkoutRepository();
      await repo.initialize();
      settingsState = SettingsState(repo, fakePreferencesService());
      await settingsState.initialize();
    });

    testWidgets('the row sits after Effort Rating and flips only its own setting', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            settingsState: settingsState,
            timerAlertService: FakeTimerAlertService(),
            appVersionInfo: const AppVersionInfo(version: '0.0.0', build: '0'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Weight on Stats'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('STATS'), findsOneWidget);
      expect(
        find.text('Show your weight change over the last 4 weeks'),
        findsOneWidget,
      );
      expect(settingsState.showWeightTrend, isTrue);

      // Effort Rating's Switch is still the first one on the screen; the
      // Weight on Stats Switch is the second.
      await tester.tap(find.byType(Switch).at(1));
      await tester.pumpAndSettle();

      expect(settingsState.showWeightTrend, isFalse);
      expect(settingsState.showFeelingSurvey, isTrue);
    });
  });
}
