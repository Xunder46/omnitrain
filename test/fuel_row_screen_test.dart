// The Fuel row (Stats PR 4b3, Phase 2) — the logged-days-only averages, the
// training/rest split, the target comparison, the visibility rule and the
// entry point into the full-history nutrition trend.
//
// The row's window is the seven days ending yesterday (days 1..7 ago; today
// is in neither it nor the previous range, D-17201), and with fewer than
// three logged days it draws a sentence instead of figures (D-17205).
//
// Scenarios S-1101…S-1108, S-1111, S-1112, the entry-point half of S-1109
// (the stacked-charts half lives in `nutrition_trend_screen_test.dart`, which
// pumps the screen directly), and S-1259/S-1260/S-1261 (narrow width, large text, the
// accessibility label).
//
// Every scenario runs on both repositories: the Mock harness opens with
// `SeedData.sampleConsumedFoods()` already written, so each one clears the food
// log first and seeds its own days.
//
// The harness is opened and seeded in `setUp` and never inside a `testWidgets`
// body: a widget test body runs under `FakeAsync`, where Hive's real file I/O
// never settles and the test hangs forever.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/fuel_summary.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/features/nutrition/nutrition_trend_screen.dart';
import 'package:omnitrain/features/stats/stats_screen.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/repository_harness.dart';

/// Tall enough that the Fuel row and every section below it are laid out, so an
/// assertion on a widget's absence is never just an off-screen miss.
const Size _kTallViewport = Size(400, 2400);

/// What a figure reads when there is nothing to show.
const String _kAbsent = '—';

/// A completed session seeded at local noon of the day [daysAgo] back.
///
/// The shared `seedSession` subtracts whole 24-hour blocks from a fixture
/// start, so across a DST transition a session can land on the neighbouring
/// local day. The food fixtures use calendar-midnight arithmetic; the
/// scenarios that align sessions with logged days must use the same calendar
/// arithmetic.
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

/// The Fuel row's own texts, in document order.
List<String> _fuelTexts() => _textsUnder(find.byKey(const Key('fuel_row')));

Finder get _fuelSection => find.byKey(const Key('fuel_section'));

// ─── fixtures ───────────────────────────────────────────────────────────────

/// One logged `ConsumedFood` on the local day [daysAgo] days back.
///
/// Fat and fibre default to zero and the consumed amount equals the
/// reference, so with the defaults the row's calories are
/// `4 × (protein + carbs)` and a fixture can name its days in round kcal.
/// A scenario that needs the row's fat or carbs figures names them (and
/// [fiber]) explicitly.
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
/// pair: `4 × (protein + carbs)` with no fat. A scenario that needs the row's
/// carbs or fat figures passes [carbs]/[fat]/[fiber] explicitly — an explicit
/// [carbs] replaces the derived pair, and [calories] then only documents the
/// day's kcal (it is unused).
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

/// The day the row's target is saved on: today. Carbs and fat default to
/// zero — no target for either, the pre-plan-80 shape.
Future<void> _seedTarget(
  WorkoutRepository repo, {
  required double calories,
  required double protein,
  double carbs = 0,
  double fat = 0,
}) async {
  final now = DateTime.now();
  await repo.saveNutritionTargetForDate(
    DateTime(now.year, now.month, now.day).millisecondsSinceEpoch,
    NutritionTarget(
      calories: calories,
      protein: protein,
      carbs: carbs,
      fat: fat,
    ),
  );
}

/// S-1101's population: 1000 / 2000 / 2500 kcal and 50 / 100 / 125 g protein on
/// days 1, 3 and 5, and nothing on the other four days of the window. One
/// completed session on day 2 so the screen is not in its empty state.
///
/// Neither total divides by the number of logged days, so the row's figures
/// only read as they do if the mean is taken over the logged days and rounded
/// once: 5500 / 3 = 1833.33 kcal and 275 / 3 = 91.67 g.
Future<void> _seedLoggedDaysOnly(WorkoutRepository repo) async {
  await seedSession(repo, sessionId: 's-fuel', daysAgo: 2);
  await _seedDay(repo, id: 'food-1', daysAgo: 1, protein: 50, calories: 1000);
  await _seedDay(repo, id: 'food-3', daysAgo: 3, protein: 100, calories: 2000);
  await _seedDay(repo, id: 'food-5', daysAgo: 5, protein: 125, calories: 2500);
}

/// S-1102's variant: every day of the row's window logged — the seven days
/// ending yesterday (days 1..7 ago; today is in neither range, D-17201) —
/// with day `k` days back carrying `100 × (k + 1)` kcal and `10 × (k + 1)` g
/// protein, so the window holds 200…800 kcal and 20…80 g.
///
/// The only session is a month old, so the screen is not in its empty state
/// while the training/rest split stays out of the fixture's way.
Future<void> _seedEveryDayLogged(WorkoutRepository repo) async {
  await seedSession(repo, sessionId: 's-fuel', daysAgo: 30);
  for (var k = 1; k <= 7; k++) {
    await _seedDay(
      repo,
      id: 'food-$k',
      daysAgo: k,
      protein: 10.0 * (k + 1),
      calories: 100.0 * (k + 1),
    );
  }
}

/// Five logged days of 2000 kcal / 100 g protein, and five logged days a week
/// earlier of 1600 kcal / 80 g — so a comparison against the target and one
/// against the previous window read differently.
Future<void> _seedWindowAndPrevious(WorkoutRepository repo) async {
  await seedSession(repo, sessionId: 's-fuel', daysAgo: 2);
  for (var k = 1; k <= 5; k++) {
    await _seedDay(
      repo,
      id: 'food-w$k',
      daysAgo: k,
      protein: 100,
      calories: 2000,
    );
  }
  for (var k = 9; k <= 13; k++) {
    await _seedDay(
      repo,
      id: 'food-p$k',
      daysAgo: k,
      protein: 80,
      calories: 1600,
    );
  }
}

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('Fuel row — ${harness.name}', () {
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

      /// The row's own figures, read from the service over the same repository
      /// the screen reads. Never null: a scenario whose fixture is meant to
      /// produce no row reads [readAbsentModel] instead.
      Future<FuelSummary> readModel() async {
        final summary = await StatsProgressService(repo).computeFuelSummary();
        expect(
          summary,
          isNotNull,
          reason: 'the fixture must produce a Fuel row',
        );
        return summary!;
      }

      /// The same read for the scenarios that assert the row is absent.
      Future<FuelSummary?> readAbsentModel() =>
          StatsProgressService(repo).computeFuelSummary();

      /// The model behind the scenario's fixture, read in `setUp` for the same
      /// reason the fixture is seeded there: a widget test body runs under
      /// `FakeAsync`.
      late FuelSummary model;

      /// The model for the scenarios whose fixture must produce no row.
      late FuelSummary? absentModel;

      // ─── S-1101: logged-days-only averaging ───────────────────────────────

      group('S-1101', () {
        setUp(() async {
          await _seedLoggedDaysOnly(repo);
          model = await readModel();
        });

        testWidgets('the averages are the mean of the logged days, not of the '
            'window', (tester) async {
          expect(model.loggedDays, 3);
          expect(model.caloriesAverage, closeTo(5500 / 3, 0.001));
          expect(model.proteinAverage, closeTo(275 / 3, 0.001));

          await pumpStats(tester);

          expect(_fuelText('fuel_calories'), '1833 kcal');
          expect(_fuelText('fuel_protein'), '92 g');
          // The window mean would be ~786 kcal / ~39 g; neither may appear.
          expect(_fuelTexts(), isNot(contains('786 kcal')));
          expect(_fuelTexts(), isNot(contains('39 g')));
        });
      });

      // ─── S-1102: the logged-days indicator ────────────────────────────────

      group('S-1102', () {
        group('three of seven days logged', () {
          setUp(() => _seedLoggedDaysOnly(repo));

          testWidgets('reads 3/7', (tester) async {
            await pumpStats(tester);

            expect(_fuelText('fuel_logged_days'), '3/7 days logged');
          });
        });

        group('seven of seven days logged', () {
          setUp(() => _seedEveryDayLogged(repo));

          testWidgets('reads 7/7', (tester) async {
            await pumpStats(tester);

            expect(_fuelText('fuel_logged_days'), '7/7 days logged');
          });
        });
      });

      // ─── S-1103: a target on some fields only ─────────────────────────────

      group('S-1103', () {
        group('a calorie target only', () {
          setUp(() async {
            await _seedWindowAndPrevious(repo);
            await _seedTarget(repo, calories: 2200, protein: 0);
            model = await readModel();
          });

          testWidgets('calories compare with the target, protein with the '
              'previous week', (tester) async {
            expect(model.hasCalorieTarget, isTrue);
            expect(model.hasProteinTarget, isFalse);
            expect(model.previousCaloriesAverage, 1600);
            expect(model.previousProteinAverage, 80);

            await pumpStats(tester);

            expect(_fuelText('fuel_calories'), '2000 kcal');
            expect(_fuelText('fuel_calories_target'), 'of 2200 kcal target');
            expect(_fuelText('fuel_calories_change'), '↓ -200 kcal');
            expect(_fuelText('fuel_protein'), '100 g');
            expect(find.byKey(const Key('fuel_protein_target')), findsNothing);
            expect(_fuelText('fuel_protein_change'), '↑ +20 g');
          });
        });

        group('an all-zero target', () {
          setUp(() async {
            await _seedWindowAndPrevious(repo);
            await _seedTarget(repo, calories: 0, protein: 0);
            model = await readModel();
          });

          testWidgets('is no target at all', (tester) async {
            expect(model.hasCalorieTarget, isFalse);
            expect(model.hasProteinTarget, isFalse);

            await pumpStats(tester);

            expect(find.byKey(const Key('fuel_calories_target')), findsNothing);
            expect(find.byKey(const Key('fuel_protein_target')), findsNothing);
            expect(_fuelText('fuel_calories_change'), '↑ +400 kcal');
            expect(_fuelText('fuel_protein_change'), '↑ +20 g');
          });
        });
      });

      // ─── S-1104: no target, previous week only ────────────────────────────

      group('S-1104', () {
        setUp(() async {
          await _seedWindowAndPrevious(repo);
          model = await readModel();
        });

        testWidgets('both fields compare with the previous week and neither '
            'shows a target', (tester) async {
          expect(model.previousCaloriesAverage, 1600);
          expect(model.previousProteinAverage, 80);
          expect(model.targetCalories, 0);
          expect(model.targetProtein, 0);

          await pumpStats(tester);

          expect(_fuelText('fuel_calories_change'), '↑ +400 kcal');
          expect(_fuelText('fuel_protein_change'), '↑ +20 g');
          expect(find.byKey(const Key('fuel_calories_target')), findsNothing);
          expect(find.byKey(const Key('fuel_protein_target')), findsNothing);
        });
      });

      // ─── S-1105: the training-day / rest-day split ────────────────────────

      group('S-1105', () {
        setUp(() async {
          await _seedEveryDayLogged(repo);
          await _seedSessionOnDay(repo, sessionId: 's-1', daysAgo: 1);
          await _seedSessionOnDay(repo, sessionId: 's-3', daysAgo: 3);
          // Still running: not a training day (D-522).
          await _seedSessionOnDay(
            repo,
            sessionId: 's-5',
            daysAgo: 5,
            isRolling: true,
          );
          model = await readModel();
        });

        testWidgets('the split covers every logged day exactly once, and a '
            'running session is not a training day', (tester) async {
          // The seven window days carry 200…800 kcal and 20…80 g.
          // Training days 1 and 3: (200 + 400) / 2 = 300 kcal,
          // (20 + 40) / 2 = 30 g.
          expect(model.trainingCaloriesAverage, 300);
          expect(model.trainingProteinAverage, 30);
          // Every other day, the running day 5 included:
          // (300 + 500 + 600 + 700 + 800) / 5 = 580 kcal,
          // (30 + 50 + 60 + 70 + 80) / 5 = 58 g.
          expect(model.restCaloriesAverage, 580);
          expect(model.restProteinAverage, 58);

          await pumpStats(tester);

          expect(_fuelText('fuel_split_training'), 'Training 300 kcal · 30 g');
          expect(_fuelText('fuel_split_rest'), 'Rest 580 kcal · 58 g');
        });
      });

      // ─── S-1106: a side with no logged days ───────────────────────────────

      group('S-1106', () {
        group('every logged day is a training day', () {
          setUp(() async {
            // Three logged days, all of them training days, so the split
            // draws (D-17204): a window with fewer than three logged days
            // draws no figures and no split.
            await _seedSessionOnDay(repo, sessionId: 's-1', daysAgo: 1);
            await _seedSessionOnDay(repo, sessionId: 's-3', daysAgo: 3);
            await _seedSessionOnDay(repo, sessionId: 's-5', daysAgo: 5);
            await _seedDay(
              repo,
              id: 'food-1',
              daysAgo: 1,
              protein: 10,
              calories: 100,
            );
            await _seedDay(
              repo,
              id: 'food-3',
              daysAgo: 3,
              protein: 30,
              calories: 300,
            );
            await _seedDay(
              repo,
              id: 'food-5',
              daysAgo: 5,
              protein: 50,
              calories: 500,
            );
            model = await readModel();
          });

          testWidgets('the rest side reads a dash', (tester) async {
            // Training days 1, 3 and 5: (100 + 300 + 500) / 3 = 300 kcal,
            // (10 + 30 + 50) / 3 = 30 g.
            expect(model.trainingCaloriesAverage, 300);
            expect(model.trainingProteinAverage, 30);
            expect(model.restCaloriesAverage, isNull);
            expect(model.restProteinAverage, isNull);

            await pumpStats(tester);

            expect(
              _fuelText('fuel_split_training'),
              'Training 300 kcal · 30 g',
            );
            expect(_fuelText('fuel_split_rest'), 'Rest $_kAbsent');
          });
        });

        group('no training day at all', () {
          setUp(() async {
            // The only session is outside the window, so the window holds no
            // training day — while the screen still has a session, and so is
            // not in its empty state.
            await seedSession(repo, sessionId: 's-old', daysAgo: 30);
            // Three logged days so the split draws (D-17204), none of them a
            // training day.
            await _seedDay(
              repo,
              id: 'food-1',
              daysAgo: 1,
              protein: 10,
              calories: 100,
            );
            await _seedDay(
              repo,
              id: 'food-3',
              daysAgo: 3,
              protein: 30,
              calories: 300,
            );
            await _seedDay(
              repo,
              id: 'food-5',
              daysAgo: 5,
              protein: 50,
              calories: 500,
            );
            model = await readModel();
          });

          testWidgets('the training side reads a dash', (tester) async {
            expect(model.trainingCaloriesAverage, isNull);
            expect(model.trainingProteinAverage, isNull);

            await pumpStats(tester);

            expect(_fuelText('fuel_split_training'), 'Training $_kAbsent');
            // Rest days 1, 3 and 5: (100 + 300 + 500) / 3 = 300 kcal,
            // (10 + 30 + 50) / 3 = 30 g.
            expect(_fuelText('fuel_split_rest'), 'Rest 300 kcal · 30 g');
          });
        });
      });

      // ─── S-1107: hidden after 14 days without logs ────────────────────────

      group('S-1107', () {
        Future<void> seedNewestFood(int daysAgo) async {
          await seedSession(repo, sessionId: 's-fuel', daysAgo: 2);
          await _seedDay(
            repo,
            id: 'food-$daysAgo',
            daysAgo: daysAgo,
            protein: 10,
            calories: 100,
          );
        }

        group('13 days old', () {
          setUp(() async {
            await seedNewestFood(13);
            model = await readModel();
          });

          testWidgets('renders', (tester) async {
            expect(model.loggedDays, 0);

            await pumpStats(tester);

            expect(_fuelSection, findsOneWidget);
            expect(_fuelText('fuel_logged_days'), '0/7 days logged');
            // Fewer than three logged days: the sentence instead of the
            // figures (D-17205).
            expect(
              _fuelText('fuel_not_enough_days'),
              'Log food on 3 days to see a weekly average',
            );
            expect(find.byKey(const Key('fuel_calories')), findsNothing);
            expect(find.byKey(const Key('fuel_protein')), findsNothing);
            expect(find.byKey(const Key('fuel_carbs')), findsNothing);
            expect(find.byKey(const Key('fuel_fat')), findsNothing);
            expect(find.byKey(const Key('fuel_calories_change')), findsNothing);
            expect(find.byKey(const Key('fuel_protein_change')), findsNothing);
            expect(find.byKey(const Key('fuel_carbs_change')), findsNothing);
            expect(find.byKey(const Key('fuel_fat_change')), findsNothing);
            expect(find.byKey(const Key('fuel_split_training')), findsNothing);
            expect(find.byKey(const Key('fuel_split_rest')), findsNothing);
          });
        });

        group('14 days old', () {
          setUp(() async {
            await seedNewestFood(14);
            absentModel = await readAbsentModel();
          });

          testWidgets('is hidden', (tester) async {
            expect(absentModel, isNull);

            await pumpStats(tester);

            expect(_fuelSection, findsNothing);
            // The screen is not empty: it is the row that is absent.
            expect(
              find.byKey(const Key('stats_legacy_sections')),
              findsNothing,
            );
            expect(find.byKey(const Key('mix_layer')), findsOneWidget);
          });
        });

        group('15 days old', () {
          setUp(() async {
            await seedNewestFood(15);
            absentModel = await readAbsentModel();
          });

          testWidgets('is hidden', (tester) async {
            expect(absentModel, isNull);

            await pumpStats(tester);

            expect(_fuelSection, findsNothing);
            expect(
              find.byKey(const Key('stats_legacy_sections')),
              findsNothing,
            );
            expect(find.byKey(const Key('mix_layer')), findsOneWidget);
          });
        });
      });

      // ─── S-1108: the previous week with no food ───────────────────────────

      group('S-1108', () {
        setUp(() async {
          await seedSession(repo, sessionId: 's-fuel', daysAgo: 2);
          for (var k = 1; k <= 5; k++) {
            await _seedDay(
              repo,
              id: 'food-$k',
              daysAgo: k,
              protein: 100,
              calories: 2000,
            );
          }
          model = await readModel();
        });

        testWidgets('nothing to compare against reads a dash, never zero', (
          tester,
        ) async {
          expect(model.previousCaloriesAverage, isNull);
          expect(model.previousProteinAverage, isNull);

          await pumpStats(tester);

          expect(_fuelText('fuel_calories'), '2000 kcal');
          expect(_fuelText('fuel_calories_change'), _kAbsent);
          expect(_fuelText('fuel_protein'), '100 g');
          expect(_fuelText('fuel_protein_change'), _kAbsent);
        });
      });

      // ─── S-1109: tapping the Fuel row ─────────────────────────────────────

      group('S-1109', () {
        setUp(() async {
          await seedSession(repo, sessionId: 's-fuel', daysAgo: 1);
          // Twenty-six logged days spanning at least two months, so the trend
          // screen has more to draw than one screenful.
          for (var k = 0; k < 20; k++) {
            await _seedDay(
              repo,
              id: 'food-$k',
              daysAgo: k,
              protein: 100,
              calories: 2000,
            );
          }
          for (var k = 45; k < 51; k++) {
            await _seedDay(
              repo,
              id: 'food-$k',
              daysAgo: k,
              protein: 100,
              calories: 2000,
            );
          }
        });

        testWidgets('the row opens the full-history nutrition trend', (
          tester,
        ) async {
          await pumpStats(tester);
          expect(_fuelSection, findsOneWidget);

          await tester.ensureVisible(find.byKey(const Key('fuel_row')));
          await tester.tap(find.byKey(const Key('fuel_row')));
          await tester.pumpAndSettle();

          expect(find.byType(NutritionTrendScreen), findsOneWidget);
          // Both stacked cards are on the screen the row opened.
          expect(find.text('CALORIES'), findsOneWidget);
          expect(find.text('MACROS'), findsOneWidget);
        });
      });

      // ─── S-1111: food inside the visibility range, none inside the window ──

      group('S-1111', () {
        setUp(() async {
          await seedSession(repo, sessionId: 's-1', daysAgo: 1);
          await seedSession(repo, sessionId: 's-3', daysAgo: 3);
          await _seedDay(
            repo,
            id: 'food-10',
            daysAgo: 10,
            protein: 10,
            calories: 100,
          );
          model = await readModel();
        });

        testWidgets('the row renders with an empty window and no figures', (
          tester,
        ) async {
          expect(model, isNotNull);
          expect(model.loggedDays, 0);
          expect(model.caloriesAverage, isNull);
          expect(model.proteinAverage, isNull);
          expect(model.trainingCaloriesAverage, isNull);
          expect(model.restCaloriesAverage, isNull);

          await pumpStats(tester);

          expect(_fuelSection, findsOneWidget);
          expect(_fuelText('fuel_logged_days'), '0/7 days logged');
          // Fewer than three logged days: the sentence instead of the
          // figures (D-17205).
          expect(
            _fuelText('fuel_not_enough_days'),
            'Log food on 3 days to see a weekly average',
          );
          expect(find.byKey(const Key('fuel_calories')), findsNothing);
          expect(find.byKey(const Key('fuel_protein')), findsNothing);
          expect(find.byKey(const Key('fuel_carbs')), findsNothing);
          expect(find.byKey(const Key('fuel_fat')), findsNothing);
          expect(find.byKey(const Key('fuel_calories_change')), findsNothing);
          expect(find.byKey(const Key('fuel_protein_change')), findsNothing);
          expect(find.byKey(const Key('fuel_carbs_change')), findsNothing);
          expect(find.byKey(const Key('fuel_fat_change')), findsNothing);
          expect(find.byKey(const Key('fuel_split_training')), findsNothing);
          expect(find.byKey(const Key('fuel_split_rest')), findsNothing);
          expect(_fuelTexts(), isNot(contains('0 kcal')));
          expect(_fuelTexts(), isNot(contains('0 g')));
        });
      });

      // ─── S-1112: the Fuel card carries no window chip ─────────────────────

      /// A resistance exercise with a logged set, so the Instruments list has
      /// a section — and therefore a caption — of its own.
      Future<void> seedInstrumentSection() async {
        await seedExercise(
          repo,
          id: 'ex-fuel',
          name: 'Back Squat',
          capabilities: const ['load', 'reps'],
        );
        await seedSession(repo, sessionId: 's-in', daysAgo: 3);
        await seedSetEffort(
          repo,
          segmentId: 'seg-s-in',
          effortId: 'eff-s-in',
          exerciseId: 'ex-fuel',
          entryCount: 1,
          hasExtraWeight: false,
          weightFactor: 100,
          repsBase: 5,
        );
      }

      Future<void> seedPeriod() async {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        await repo.createPeriod(
          TrainingPeriod(
            id: 'p-fuel',
            name: 'Block A',
            startDateMs: today
                .subtract(const Duration(days: 7))
                .millisecondsSinceEpoch,
            endDateMs:
                today.add(const Duration(days: 1)).millisecondsSinceEpoch - 1,
            focusModalities: const [],
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
      }

      group('S-1112', () {
        Future<void> seedFuelAndInstruments() async {
          await _seedLoggedDaysOnly(repo);
          await seedInstrumentSection();
        }

        group('with a training period in force', () {
          setUp(() async {
            await seedFuelAndInstruments();
            await seedPeriod();
          });

          testWidgets('the Fuel card has no window chip and its first line '
              'reads Last 7 days, with the window named in words', (tester) async {
            await pumpStats(tester);

            // No chip renders anywhere: the window is named in words (the Mix
            // explainer and the Instruments caption), and the Fuel card's own
            // first line is the seven-day horizon.
            expect(find.byKey(const Key('stats_window_chip')), findsNothing);
            expect(_fuelText('fuel_horizon'), 'Last 7 days');
            expect(
              _textsUnder(find.byKey(const Key('instrument_caption'))).single,
              startsWith('Last 4 weeks. '),
            );
          });

          testWidgets('the figures are the same under the period window', (
            tester,
          ) async {
            final periodWindow = (await StatsProgressService(
              repo,
            ).computeProgressData()).window;
            expect(periodWindow.label, 'Block A');
            await pumpStats(tester);

            expect(_fuelText('fuel_calories'), '1833 kcal');
            expect(_fuelText('fuel_protein'), '92 g');
            expect(_fuelText('fuel_logged_days'), '3/7 days logged');
          });
        });

        group('with no training period', () {
          setUp(seedFuelAndInstruments);

          testWidgets('a different window leaves the figures alone', (
            tester,
          ) async {
            final openWindow = (await StatsProgressService(
              repo,
            ).computeProgressData()).window;
            expect(openWindow.label, isNot('Block A'));
            await pumpStats(tester);

            expect(_fuelText('fuel_calories'), '1833 kcal');
            expect(_fuelText('fuel_protein'), '92 g');
            expect(_fuelText('fuel_logged_days'), '3/7 days logged');
          });
        });
      });

      // ─── S-1259/S-1260/S-1261: narrow width, large text, the label ────────

      group('S-1259/S-1260/S-1261', () {

        /// Pumps the Stats screen at [size] dp with [scale] text, then brings
        /// the Fuel row into the viewport — the list builds its children
        /// lazily, so the row is only laid out once it is scrolled to.
        Future<void> pumpAt(
          WidgetTester tester,
          Size size,
          double scale,
        ) async {
          await tester.binding.setSurfaceSize(size);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: MaterialApp(
                home: StatsScreen(
                  workoutState: workoutState,
                  settingsState: settingsState,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.byKey(const Key('fuel_row')),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.ensureVisible(find.byKey(const Key('fuel_row')));
          await tester.pumpAndSettle();
        }

        group('a row with three logged days', () {
          setUp(() async {
            await seedSession(repo, sessionId: 's-fuel', daysAgo: 2);
            // Three logged days inside the window (days 1..7 ago), so the row
            // draws its figures (D-17204). Every day is 2000 kcal / 100 g
            // protein, so each average is the day value itself.
            await _seedDay(
              repo,
              id: 'food-1',
              daysAgo: 1,
              protein: 100,
              calories: 2000,
            );
            await _seedDay(
              repo,
              id: 'food-2',
              daysAgo: 2,
              protein: 100,
              calories: 2000,
            );
            await _seedDay(
              repo,
              id: 'food-3',
              daysAgo: 3,
              protein: 100,
              calories: 2000,
            );
            await _seedTarget(repo, calories: 2000, protein: 100);
          });

          testWidgets('renders at 320x568 dp without overflowing', (
            tester,
          ) async {
            await pumpAt(tester, const Size(320, 568), 1.0);

            expect(tester.takeException(), isNull);
            expect(_fuelSection, findsOneWidget);
            expect(_fuelText('fuel_calories'), '2000 kcal');
            expect(_fuelText('fuel_protein'), '100 g');
            expect(_fuelText('fuel_logged_days'), '3/7 days logged');
            expect(
              find.byWidgetPredicate(
                (w) =>
                    w is Semantics && w.properties.label == 'Nutrition trend',
              ),
              findsOneWidget,
            );
          });

          testWidgets('renders at 390x844 dp and 2.0 text scale without '
              'overflowing', (tester) async {
            await pumpAt(tester, const Size(390, 844), 2.0);

            expect(tester.takeException(), isNull);
            expect(_fuelSection, findsOneWidget);
            expect(_fuelText('fuel_calories'), '2000 kcal');
            expect(_fuelText('fuel_protein'), '100 g');
            expect(
              tester.getSize(find.byKey(const Key('fuel_row'))).height,
              greaterThanOrEqualTo(44),
              reason: 'the row must stay a tappable target at large text',
            );
          });

          testWidgets('exposes its label and still opens the trend screen', (
            tester,
          ) async {
            await pumpAt(tester, const Size(320, 568), 1.0);

            final label = find.byWidgetPredicate(
              (w) => w is Semantics && w.properties.label == 'Nutrition trend',
            );
            expect(label, findsOneWidget);
            expect(tester.widget<Semantics>(label).properties.button, isTrue);

            await tester.tap(find.byKey(const Key('fuel_row')));
            await tester.pumpAndSettle();

            expect(find.byType(NutritionTrendScreen), findsOneWidget);
          });
        });

        group('a row with fewer than three logged days', () {
          setUp(() async {
            await seedSession(repo, sessionId: 's-fuel', daysAgo: 2);
            // One logged day: the row draws the not-enough-days sentence
            // instead of the figures (D-17205).
            await _seedDay(
              repo,
              id: 'food-1',
              daysAgo: 1,
              protein: 100,
              calories: 2000,
            );
          });

          testWidgets('the sentence renders at 320x568 dp and 2.0 text scale '
              'without overflowing', (tester) async {
            await pumpAt(tester, const Size(320, 568), 2.0);

            expect(tester.takeException(), isNull);
            expect(_fuelSection, findsOneWidget);
            expect(
              _fuelText('fuel_not_enough_days'),
              'Log food on 3 days to see a weekly average',
            );
            expect(_fuelText('fuel_logged_days'), '1/7 days logged');
            expect(find.byKey(const Key('fuel_calories')), findsNothing);
          });

          testWidgets('the sentence renders at 390x844 dp and 2.0 text scale '
              'without overflowing', (tester) async {
            await pumpAt(tester, const Size(390, 844), 2.0);

            expect(tester.takeException(), isNull);
            expect(_fuelSection, findsOneWidget);
            expect(
              _fuelText('fuel_not_enough_days'),
              'Log food on 3 days to see a weekly average',
            );
            expect(_fuelText('fuel_logged_days'), '1/7 days logged');
          });
        });
      });

      // ─── Fuel row — carbs and fat (plan 80): S-14040, S-14041 ─────────────

      /// S-14040's fixture: three logged days whose carbs and fat the tests
      /// name outright. Day 1's food carries fibre 10 g beside carbs 50 g —
      /// TOTAL carbs, so the day counts all 50 and the fibre is not
      /// subtracted (D-1). The `calories` arguments document each day's kcal
      /// (`4 × (protein + carbs) + 9 × fat`); with carbs explicit they are
      /// not used to derive anything. The third day carries carbs 60 g and
      /// fat 35 g so the three-day means stay the figures the assertions
      /// name: (50 + 70 + 60) / 3 = 60 and (40 + 30 + 35) / 3 = 35.
      Future<void> seedCarbFatDays() async {
        await seedSession(repo, sessionId: 's-fuel', daysAgo: 3);
        await _seedDay(
          repo,
          id: 'food-c1',
          daysAgo: 1,
          protein: 100,
          calories: 960,
          carbs: 50,
          fat: 40,
          fiber: 10,
        );
        await _seedDay(
          repo,
          id: 'food-c2',
          daysAgo: 2,
          protein: 50,
          calories: 750,
          carbs: 70,
          fat: 30,
        );
        await _seedDay(
          repo,
          id: 'food-c3',
          daysAgo: 3,
          protein: 50,
          calories: 755,
          carbs: 60,
          fat: 35,
        );
      }

      group('Fuel row — carbs and fat (plan 80)', () {
        group('S-14040', () {
          setUp(() async {
            await seedCarbFatDays();
            await _seedTarget(
              repo,
              calories: 2200,
              protein: 150,
              carbs: 250,
              fat: 70,
            );
            model = await readModel();
          });

          testWidgets('the averages are means of TOTAL carbs and fat over '
              'the logged days, against the saved targets', (tester) async {
            // Day 1 counts all 50 g of carbs (fibre 10 g included, D-1);
            // days 2 and 3 carry 70 g and 60 g. Mean over the three logged
            // days: (50 + 70 + 60) / 3 = 60.
            expect(model.carbsAverage, closeTo(60, 0.001));
            // Fat: (40 + 30 + 35) / 3 = 35.
            expect(model.fatAverage, closeTo(35, 0.001));
            expect(model.targetCarbs, 250);
            expect(model.targetFat, 70);
            expect(model.hasCarbsTarget, isTrue);
            expect(model.hasFatTarget, isTrue);
          });
        });

        group('S-14043', () {
          setUp(() async {
            await seedCarbFatDays();
            await _seedTarget(
              repo,
              calories: 2200,
              protein: 150,
              carbs: 250,
              fat: 70,
            );
            model = await readModel();
          });

          testWidgets('the four figures are labelled', (tester) async {
            await pumpStats(tester);

            expect(_fuelText('fuel_calories_label'), 'Calories');
            expect(_fuelText('fuel_protein_label'), 'Protein');
            expect(_fuelText('fuel_carbs_label'), 'Carbs');
            expect(_fuelText('fuel_fat_label'), 'Fat');
          });
        });

        group('S-14041', () {
          group('with a carbs and a fat target', () {
            setUp(() async {
              await seedCarbFatDays();
              await _seedTarget(
                repo,
                calories: 2200,
                protein: 150,
                carbs: 250,
                fat: 70,
              );
              model = await readModel();
            });

            testWidgets('the second row reads the carbs and fat figures '
                'against their targets', (tester) async {
              await pumpStats(tester);

              // (50 + 70 + 60) / 3 = 60.
              expect(_fuelText('fuel_carbs'), '60 g');
              expect(_fuelText('fuel_carbs_target'), 'of 250 g target');
              // (40 + 30 + 35) / 3 = 35.
              expect(_fuelText('fuel_fat'), '35 g');
              expect(_fuelText('fuel_fat_target'), 'of 70 g target');
            });
          });

          group('with no carbs or fat target', () {
            setUp(() async {
              await seedSession(repo, sessionId: 's-fuel', daysAgo: 2);
              // Three logged days in the window, each carbs 100 g / fat 40 g,
              // so the window means stay 100 g and 40 g. Previous window:
              // carbs 50 g, fat 20 g — so a comparison against the previous
              // window reads differently from a dash.
              await _seedDay(
                repo,
                id: 'food-w1',
                daysAgo: 1,
                protein: 100,
                calories: 2000,
                carbs: 100,
                fat: 40,
              );
              await _seedDay(
                repo,
                id: 'food-w2',
                daysAgo: 2,
                protein: 100,
                calories: 2000,
                carbs: 100,
                fat: 40,
              );
              await _seedDay(
                repo,
                id: 'food-w3',
                daysAgo: 3,
                protein: 100,
                calories: 2000,
                carbs: 100,
                fat: 40,
              );
              await _seedDay(
                repo,
                id: 'food-p1',
                daysAgo: 9,
                protein: 100,
                calories: 2000,
                carbs: 50,
                fat: 20,
              );
              await _seedTarget(repo, calories: 2200, protein: 150);
              model = await readModel();
            });

            testWidgets('the target lines are absent and the changes compare '
                'with the previous window', (tester) async {
              expect(model.hasCarbsTarget, isFalse);
              expect(model.hasFatTarget, isFalse);

              await pumpStats(tester);

              expect(find.byKey(const Key('fuel_carbs_target')), findsNothing);
              expect(find.byKey(const Key('fuel_fat_target')), findsNothing);
              // Window carbs 100 against the previous window's 50.
              expect(_fuelText('fuel_carbs_change'), '↑ +50 g');
              // Fat 40 against 20 — the protein pattern without a target.
              expect(_fuelText('fuel_fat_change'), '↑ +20 g');
            });
          });
        });
      });
    });
  }
}
