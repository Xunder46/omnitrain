// Plan 212, scenarios S-21303 and S-21304 — a signal whose evaluation throws,
// or a food read that fails, leaves that one piece out of the Stats screen
// while the rest still loads. The totals, the Instruments list and the Mix
// layer stay the screen's core: a failure there still shows the failure view
// (`test/stats_load_failure_test.dart` pins that half).
//
// S-21303: one throwing signal, one healthy one — the throwing one is left
// out, the healthy one still speaks.
// S-21304: the nutrition read behind `computeFuelSummary` throws — the Fuel
// row is left out, the screen still loads.
//
// Plan: `docs/plans/2026-11-16-212-stats-one-failure-keeps-the-screen-plan/`.
//
// Mock-only: a widget test body runs under `FakeAsync`, where a Hive read
// never settles, so the store under test is the in-memory
// `MockWorkoutRepository`. The setup copies `test/stats_load_failure_test.dart`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/signals.dart';
import 'package:omnitrain/core/services/signals/signal.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/stats/stats_screen.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/repository_harness.dart';

/// A signal whose evaluation always throws, as a stored row in a shape the
/// signal did not expect would.
class _ThrowingSignal implements Signal {
  @override
  final String id = 't-1';

  @override
  final SignalKind kind = SignalKind.positive;

  @override
  final int priority = 10;

  @override
  final bool needsRatedWeeks = false;

  @override
  Future<SignalCard?> evaluate(SignalContext context) async {
    throw StateError('the signal cannot read its data');
  }

  @override
  Future<String?> waitingFor(SignalContext context) async => null;
}

/// A signal that evaluates fine and returns a visible card.
class _HealthySignal implements Signal {
  @override
  final String id = 'ok-1';

  @override
  final SignalKind kind = SignalKind.positive;

  @override
  final int priority = 10;

  @override
  final bool needsRatedWeeks = false;

  @override
  Future<SignalCard?> evaluate(SignalContext context) async {
    return SignalCard(
      id: id,
      kind: kind,
      priority: priority,
      title: 'Still here',
      observation: 'the others speak',
    );
  }

  @override
  Future<String?> waitingFor(SignalContext context) async => null;
}

/// A repository whose nutrition read throws while [failing] is on, so the
/// Fuel summary cannot be computed while every other read is healthy.
class _FoodReadFailsRepository extends MockWorkoutRepository {
  bool failing = false;

  @override
  Future<List<ConsumedFood>> getConsumedFoodsInRange(int fromMs, int toMs) async {
    if (failing) throw StateError('the food log cannot be read');
    return super.getConsumedFoodsInRange(fromMs, toMs);
  }
}

/// Tall enough that the Fuel row, below the Mix layer, the Signals layer and
/// the Instruments list, is laid out, so an assertion on a widget's absence is
/// never just an off-screen miss (`test/fuel_row_screen_test.dart` uses the
/// same size for the same reason).
const Size _kViewport = Size(400, 2400);

/// Local midnight of the day [daysAgo] days back.
DateTime _day(int daysAgo) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day - daysAgo);
}

/// One logged `ConsumedFood` on the local day [daysAgo] days back, so the Fuel
/// row renders below the Instruments list.
Future<void> _seedFood(
  MockWorkoutRepository repo, {
  required String id,
  required int daysAgo,
}) async {
  final dateMs = _day(daysAgo).millisecondsSinceEpoch;
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

/// The repository's food log, emptied: the Mock repository initializes with
/// `SeedData.sampleConsumedFoods()` already written.
Future<void> _clearConsumedFoods(MockWorkoutRepository repo) async {
  const farFutureMs = 4102444800000; // 2100-01-01
  for (final row in await repo.getConsumedFoodsInRange(0, farFutureMs)) {
    await repo.deleteConsumedFood(row.id);
  }
}

void main() {
  group('S-21303: a signal that throws does not blank the screen', () {
    late MockWorkoutRepository repo;
    late WorkoutState workoutState;
    late SettingsState settingsState;

    setUp(() async {
      repo = MockWorkoutRepository();
      await repo.initialize();
      // One completed session with one set effort, so the healthy load has
      // real content and the signals are evaluated at all.
      await seedSession(repo, sessionId: 'sess-1', daysAgo: 1);
      await seedExercise(
        repo,
        id: 'ex-row',
        name: 'Row',
        capabilities: ['load'],
      );
      await seedSetEffort(
        repo,
        segmentId: 'seg-sess-1',
        effortId: 'eff-1',
        exerciseId: 'ex-row',
        entryCount: 2,
        hasExtraWeight: false,
      );
      workoutState = WorkoutState(repo);
      settingsState = SettingsState(repo, fakePreferencesService());
      await settingsState.initialize();
    });

    Future<void> pump(WidgetTester tester, List<Signal> signals) async {
      await tester.binding.setSurfaceSize(_kViewport);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: StatsScreen(
            workoutState: workoutState,
            settingsState: settingsState,
            signals: signals,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('S-21303 a signal that throws does not blank the screen', (
      tester,
    ) async {
      await pump(tester, [_ThrowingSignal(), _HealthySignal()]);

      expect(find.text('Could not load your stats.'), findsNothing);
      expect(find.byKey(const Key('instrument_caption')), findsOneWidget);
      // The card renders its observation as its body text (the title is not
      // laid out), and the card carries the signal's id as its widget key.
      expect(find.byKey(const Key('signal_card_ok-1')), findsOneWidget);
      expect(find.text('the others speak'), findsOneWidget);
      expect(find.byKey(const Key('signal_card_t-1')), findsNothing);
    });
  });

  group('S-21304: a food read that fails leaves the Fuel row out', () {
    late _FoodReadFailsRepository repo;
    late WorkoutState workoutState;
    late SettingsState settingsState;

    setUp(() async {
      repo = _FoodReadFailsRepository();
      await repo.initialize();
      await seedSession(repo, sessionId: 'sess-1', daysAgo: 1);
      await seedExercise(
        repo,
        id: 'ex-row',
        name: 'Row',
        capabilities: ['load'],
      );
      await seedSetEffort(
        repo,
        segmentId: 'seg-sess-1',
        effortId: 'eff-1',
        exerciseId: 'ex-row',
        entryCount: 2,
        hasExtraWeight: false,
      );
      // Food logged on days 1 and 2 ago: inside the row's visibility window,
      // so the healthy load shows the Fuel row.
      await _clearConsumedFoods(repo);
      await _seedFood(repo, id: 'food-1', daysAgo: 1);
      await _seedFood(repo, id: 'food-2', daysAgo: 2);
      workoutState = WorkoutState(repo);
      settingsState = SettingsState(repo, fakePreferencesService());
      await settingsState.initialize();
    });

    Future<void> pump(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(_kViewport);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: StatsScreen(
            workoutState: workoutState,
            settingsState: settingsState,
            // Only the Fuel read can throw here.
            signals: const <Signal>[],
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('S-21304 the control: with the food log readable the row shows', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text('Could not load your stats.'), findsNothing);
      expect(find.byKey(const Key('instrument_caption')), findsOneWidget);
      expect(find.byKey(const Key('fuel_row')), findsOneWidget);
    });

    testWidgets('S-21304 a food read that throws leaves the row out, not the screen', (
      tester,
    ) async {
      repo.failing = true;
      await pump(tester);

      expect(find.text('Could not load your stats.'), findsNothing);
      expect(find.byKey(const Key('instrument_caption')), findsOneWidget);
      expect(find.byKey(const Key('fuel_row')), findsNothing);
    });
  });
}
