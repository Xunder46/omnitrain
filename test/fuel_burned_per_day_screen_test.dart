// The Stats screen's Fuel card wiring for `Burned per day` (plan 208,
// Phase 3c2): the reader `StatsScreen._loadData` passes comes from
// `SettingsState.readDailyActiveEnergy`, which gates on the
// `Read active energy` switch before the platform source is touched.
//
// Scenarios S-20840 (switch on shows the line, switch off leaves the card
// exactly as it renders without a source at all), S-20841 (a burn-only card
// is not tappable), S-20842 (nothing to show hides the card), S-20848 (no
// food, Health burn only) and S-20849 (the empty state keeps no Fuel card,
// new id, this file only).
//
// The file is copied from `test/fuel_row_screen_test.dart`: the harness,
// viewport, seeding helpers and readers are the same; the scenarios run on
// both repositories. The fake `HealthActiveEnergySource` answers permission
// true and returns a fixed map keyed by day-start epoch ms immediately (no
// delay), counting how many times it was read.
//
// Everything is seeded and switched in `setUp`, never inside a `testWidgets`
// body: a widget test body runs under `FakeAsync`, where Hive's real file
// I/O never settles and the test hangs forever.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/fuel_summary.dart';
import 'package:omnitrain/core/services/health_platform_service.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/features/nutrition/nutrition_trend_screen.dart';
import 'package:omnitrain/features/stats/stats_screen.dart';
import 'package:omnitrain/features/stats/widgets/fuel_section.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/repository_harness.dart';

/// Tall enough that the Fuel card and every section below it are laid out, so
/// an assertion on a widget's absence is never just an off-screen miss.
const Size _kTallViewport = Size(400, 2400);

/// The fake `HealthActiveEnergySource` behind `SettingsState` (plan 208
/// D-12/D-13): permission always granted, a settable map answered immediately,
/// and a count of the reads that reached it.
class _FakeActiveEnergySource implements HealthActiveEnergySource {
  _FakeActiveEnergySource(this.dayEnergy);

  Map<int, double> dayEnergy;

  int readCalls = 0;

  @override
  Future<bool> requestActiveEnergyReadPermission() => Future.value(true);

  @override
  Future<Map<int, double>> readDailyActiveEnergy(List<DateTime> dayStarts) {
    readCalls++;
    return Future.value(dayEnergy);
  }
}

/// S-20830's seven window days: d1 520 … d7 550, keyed the way the service
/// keys its average — the day-start epoch ms of the day k days back. The mean
/// is 3640 / 7 = 520.
Map<int, double> _dayEnergy() {
  final now = DateTime.now();
  const kcalByDaysAgo = <int, double>{
    1: 520,
    2: 480,
    3: 610,
    4: 450,
    5: 530,
    6: 500,
    7: 550,
  };
  return {
    for (final entry in kcalByDaysAgo.entries)
      DateTime(now.year, now.month, now.day - entry.key)
          .millisecondsSinceEpoch: entry.value,
  };
}

/// S-20842(b)'s two days only — below [kFuelMinActiveEnergyDays], so the
/// average stays null and the card has nothing to show.
Map<int, double> _twoDayEnergy() {
  final now = DateTime.now();
  return {
    DateTime(now.year, now.month, now.day - 1).millisecondsSinceEpoch: 600,
    DateTime(now.year, now.month, now.day - 2).millisecondsSinceEpoch: 400,
  };
}

/// A completed session seeded at local noon of the day [daysAgo] back.
///
/// Copied from `test/fuel_row_screen_test.dart`: the shared `seedSession`
/// subtracts whole 24-hour blocks from a fixture start, so across a DST
/// transition a session can land on the neighbouring local day. The food
/// fixtures use calendar-midnight arithmetic; the scenarios that align
/// sessions with logged days must use the same calendar arithmetic.
Future<void> _seedSessionOnDay(
  WorkoutRepository repo, {
  required String sessionId,
  required int daysAgo,
  bool isRolling = false,
}) async {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day - daysAgo, 12)
      .millisecondsSinceEpoch;
  await repo.createSession(
    TrainingSession(
      id: sessionId,
      ownerUserId: 'user-1',
      startedAtMs: start,
      endedAtMs: isRolling ? null : start + 3600000,
      modality: null,
      isRolling: isRolling,
      createdAtMs: start,
      updatedAtMs: start,
    ),
  );
  await repo.createSegment(
    SessionSegment(
      id: 'seg-$sessionId',
      sessionId: sessionId,
      orderIndex: 0,
      segmentType: 'workout',
      name: 'Main Workout',
      createdAtMs: start,
      updatedAtMs: start,
    ),
  );
}

// ─── finders and readers ────────────────────────────────────────────────────

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

Finder get _fuelSection => find.byKey(const Key('fuel_section'));

// ─── fixtures ───────────────────────────────────────────────────────────────

/// One logged `ConsumedFood` on the local day [daysAgo] days back.
///
/// Copied from `test/fuel_row_screen_test.dart`: fat and fibre default to
/// zero and the consumed amount equals the reference, so with the defaults
/// the row's calories are `4 × (protein + carbs)` and a fixture can name its
/// days in round kcal.
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
/// pair: `4 × (protein + carbs)` with no fat. Copied from
/// `test/fuel_row_screen_test.dart`.
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

/// One logged day of [calories] kcal on each of the [daysAgo] days, so a
/// scenario names its days in round kcal. Copied from
/// `test/fuel_row_screen_test.dart`.
Future<void> _seedFoodOnDays(
  WorkoutRepository repo, {
  required List<int> daysAgo,
  required double calories,
}) async {
  for (final day in daysAgo) {
    await _seedDay(
      repo,
      id: 'food-$day',
      daysAgo: day,
      protein: calories / 4,
      calories: calories,
    );
  }
}

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

/// An energy row for session [sessionId]: [activeKcal] kcal, measured or
/// estimated. Copied in shape from `test/fuel_burned_summary_test.dart`; an
/// estimated row carries the 80 kg body weight the model requires.
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

    group('Fuel burned per day, screen — ${harness.name}', () {
      late WorkoutRepository repo;
      late WorkoutState workoutState;
      late _FakeActiveEnergySource fakeSource;
      late SettingsState settingsState;

      setUp(() async {
        repo = await harness.open();
        await _clearConsumedFoods(repo);
        workoutState = WorkoutState(repo);
        fakeSource = _FakeActiveEnergySource(_dayEnergy());
        settingsState = SettingsState(
          repo,
          fakePreferencesService(),
          activeEnergySource: fakeSource,
        );
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

      /// The model behind the scenario's fixture, read from the service over
      /// the same repository the screen reads, in `setUp` for the same reason
      /// the fixture is seeded there: a widget test body runs under
      /// `FakeAsync`. No reader is passed — the scenarios that need Health
      /// data assert on the screen, not on this read.
      late FuelSummary model;

      // ─── S-20840: the screen wiring of the burned-per-day line ────────────

      group('S-20840 wiring', () {
        setUp(() async {
          await _seedFoodOnDays(
            repo,
            daysAgo: const [1, 2, 3],
            calories: 2000,
          );
          await _seedSessionOnDay(repo, sessionId: 's-20840', daysAgo: 1);
        });

        group('switch on', () {
          setUp(() async {
            await settingsState.setHealthReadActiveEnergyEnabled(true);
          });

          testWidgets('the card reads Burned per day from the source', (
            tester,
          ) async {
            await pumpStats(tester);

            expect(
              _fuelText('fuel_burned_day'),
              'Burned per day: 520 kcal · active, all movement',
            );
            // The screen passed the reader on and the service read it once.
            expect(fakeSource.readCalls, 1);
          });
        });

        group('switch off', () {
          setUp(() async {
            model = (await StatsProgressService(repo).computeFuelSummary())!;
          });

          testWidgets('no burned-per-day line, the source never read, and the '
              'card is exactly the no-source card', (tester) async {
            await pumpStats(tester);

            expect(fakeSource.readCalls, 0);
            expect(find.byKey(const Key('fuel_burned_day')), findsNothing);

            // Every `Text` under the card, in document order, built from the
            // summary the service computes over the same fixture: the header,
            // the window line, each metric's label, figure and comparison, the
            // logged-days line, and the burn-per-session dash (the fixture
            // carries no energy row). No target and no previous-window food is
            // seeded, so every comparison reads `kFuelAbsent`.
            expect(model.loggedDays, 3);
            expect(model.burnedKcalAverage, isNull);
            expect(
              _textsUnder(_fuelSection),
              <String>[
                'FUEL',
                'Last ${StatsProgressService.kFuelWindowDays} days',
                'Calories',
                '${model.caloriesAverage!.round()} kcal',
                kFuelAbsent,
                'Protein',
                '${model.proteinAverage!.round()} g',
                kFuelAbsent,
                'Carbs',
                '${model.carbsAverage!.round()} g',
                kFuelAbsent,
                'Fat',
                '${model.fatAverage!.round()} g',
                kFuelAbsent,
                '${model.loggedDays}/'
                    '${StatsProgressService.kFuelWindowDays} days logged',
                'Burned per session: $kFuelAbsent',
              ],
            );
          });
        });
      });

      // ─── S-20841: a burn-only card is not tappable ─────────────────────────

      group('S-20841 burn-only is not tappable', () {
        setUp(() async {
          await _seedSessionOnDay(repo, sessionId: 's-20841-d2', daysAgo: 2);
          await _seedEnergy(
            repo,
            sessionId: 's-20841-d2',
            activeKcal: 300,
            estimated: false,
          );
          await _seedSessionOnDay(repo, sessionId: 's-20841-d4', daysAgo: 4);
          await _seedEnergy(
            repo,
            sessionId: 's-20841-d4',
            activeKcal: 500,
            estimated: true,
          );
          model = (await StatsProgressService(repo).computeFuelSummary())!;
        });

        testWidgets('the card shows the burn line only and the tap pushes no '
            'route', (tester) async {
          expect(model.hasRecentFood, isFalse);
          expect(model.burnedKcalAverage, 400.0);
          expect(model.burnedSessionCount, 2);

          await pumpStats(tester);

          expect(_fuelSection, findsOneWidget);
          expect(
            _fuelText('fuel_burned'),
            'Burned per session: ~400 kcal · 2 sessions',
          );
          // Burn-only mode: no figures, no logged-days line, no split, no
          // burned-per-day line and no dash, and no `fuel_row` InkWell.
          expect(find.byKey(const Key('fuel_calories')), findsNothing);
          expect(find.byKey(const Key('fuel_logged_days')), findsNothing);
          expect(find.byKey(const Key('fuel_split')), findsNothing);
          expect(find.byKey(const Key('fuel_burned_day')), findsNothing);
          expect(_textsUnder(_fuelSection), isNot(contains(kFuelAbsent)));
          expect(find.byKey(const Key('fuel_row')), findsNothing);

          await tester.tap(_fuelSection);
          await tester.pumpAndSettle();

          expect(find.byType(StatsScreen), findsOneWidget);
          expect(find.byType(NutritionTrendScreen), findsNothing);
        });
      });

      // ─── S-20842: nothing to show hides the card ──────────────────────────

      group('S-20842 nothing to show hides the card', () {
        setUp(() async {
          await _seedSessionOnDay(repo, sessionId: 's-20842', daysAgo: 3);
        });

        group('switch off, the source holds data', () {
          testWidgets('the gate keeps the source out and hides the card', (
            tester,
          ) async {
            await pumpStats(tester);

            expect(_fuelSection, findsNothing);
            expect(fakeSource.readCalls, 0);
          });
        });

        group('switch on, two days only', () {
          setUp(() async {
            fakeSource.dayEnergy = _twoDayEnergy();
            await settingsState.setHealthReadActiveEnergyEnabled(true);
          });

          testWidgets('below the three-day floor the card stays hidden', (
            tester,
          ) async {
            await pumpStats(tester);

            expect(_fuelSection, findsNothing);
          });
        });
      });

      // ─── S-20848: no food, Health burn only ───────────────────────────────

      group('S-20848 no food, Health only', () {
        setUp(() async {
          await _seedSessionOnDay(repo, sessionId: 's-20848', daysAgo: 3);
          await settingsState.setHealthReadActiveEnergyEnabled(true);
        });

        testWidgets('the card is the burned-per-day line alone', (
          tester,
        ) async {
          await pumpStats(tester);

          expect(_fuelSection, findsOneWidget);
          expect(_fuelText('fuel_horizon'), 'Last 7 days');
          expect(
            _fuelText('fuel_burned_day'),
            'Burned per day: 520 kcal · active, all movement',
          );
          expect(find.byKey(const Key('fuel_burned')), findsNothing);
          expect(find.byKey(const Key('fuel_logged_days')), findsNothing);
          expect(find.byKey(const Key('fuel_calories')), findsNothing);
          expect(_textsUnder(_fuelSection), isNot(contains(kFuelAbsent)));
          expect(find.byKey(const Key('fuel_row')), findsNothing);
        });
      });

      // ─── S-20849: the empty state keeps no Fuel card ──────────────────────

      group('S-20849 the empty state keeps no Fuel card', () {
        setUp(() async {
          await _seedFoodOnDays(
            repo,
            daysAgo: const [1, 2, 3],
            calories: 2000,
          );
          await settingsState.setHealthReadActiveEnergyEnabled(true);
        });

        testWidgets('no completed session ever, so no card', (tester) async {
          await pumpStats(tester);

          expect(_fuelSection, findsNothing);
        });
      });
    });
  }
}
