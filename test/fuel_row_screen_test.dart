// The Fuel row (Stats PR 4b3, Phase 2) — the logged-days-only averages, the
// training/rest split, the target comparison, the visibility rule and the
// entry point into the full-history nutrition trend.
//
// Scenarios S-1101…S-1108, S-1111, S-1112, and the entry-point half of S-1109
// (the toggle half lives in `nutrition_trend_screen_test.dart`, which pumps the
// screen directly).
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
import 'package:omnitrain/widgets/layout/omni_card_header.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/repository_harness.dart';

/// Tall enough that the Fuel row and every section below it are laid out, so an
/// assertion on a widget's absence is never just an off-screen miss.
const Size _kTallViewport = Size(400, 2400);

/// What a figure reads when there is nothing to show.
const String _kAbsent = '—';

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
/// Fat is zero and the consumed amount equals the reference, so the row's
/// calories are `4 × (protein + carbs)` and a fixture can name its days in
/// round kcal.
Future<void> _seedFood(
  WorkoutRepository repo, {
  required String id,
  required int daysAgo,
  required double protein,
  required double carbs,
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

/// A logged day of [calories] kcal and [protein] g, as the fixture's own macro
/// pair: `4 × (protein + carbs)` with no fat.
Future<void> _seedDay(
  WorkoutRepository repo, {
  required String id,
  required int daysAgo,
  required double protein,
  required double calories,
}) => _seedFood(
  repo,
  id: id,
  daysAgo: daysAgo,
  protein: protein,
  carbs: (calories / 4) - protein,
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

/// The day the row's target is saved on: today.
Future<void> _seedTarget(
  WorkoutRepository repo, {
  required double calories,
  required double protein,
}) async {
  final now = DateTime.now();
  await repo.saveNutritionTargetForDate(
    DateTime(now.year, now.month, now.day).millisecondsSinceEpoch,
    NutritionTarget(calories: calories, protein: protein),
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

/// S-1102's variant: every day of the row's window logged — today and the six
/// days before it — with day `k` days back carrying `100 × (k + 1)` kcal and
/// `10 × (k + 1)` g protein.
///
/// The only session is a month old, so the screen is not in its empty state
/// while the training/rest split stays out of the fixture's way.
Future<void> _seedEveryDayLogged(WorkoutRepository repo) async {
  await seedSession(repo, sessionId: 's-fuel', daysAgo: 30);
  for (var k = 0; k <= 6; k++) {
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
          await seedSession(repo, sessionId: 's-1', daysAgo: 1);
          await seedSession(repo, sessionId: 's-3', daysAgo: 3);
          // Still running: not a training day (D-522).
          await seedSession(
            repo,
            sessionId: 's-5',
            daysAgo: 5,
            isRolling: true,
          );
          model = await readModel();
        });

        testWidgets('the split covers every logged day exactly once, and a '
            'running session is not a training day', (tester) async {
          // The seven window days carry 100…700 kcal and 10…70 g.
          // Training days 1 and 3: (200 + 400) / 2 kcal, (20 + 40) / 2 g.
          expect(model.trainingCaloriesAverage, 300);
          expect(model.trainingProteinAverage, 30);
          // Every other day, day 5 included: (100 + 300 + 500 + 600 + 700) / 5.
          expect(model.restCaloriesAverage, 440);
          expect(model.restProteinAverage, 44);

          await pumpStats(tester);

          expect(_fuelText('fuel_split_training'), 'Training 300 kcal · 30 g');
          expect(_fuelText('fuel_split_rest'), 'Rest 440 kcal · 44 g');
        });
      });

      // ─── S-1106: a side with no logged days ───────────────────────────────

      group('S-1106', () {
        group('every logged day is a training day', () {
          setUp(() async {
            await seedSession(repo, sessionId: 's-1', daysAgo: 1);
            await seedSession(repo, sessionId: 's-3', daysAgo: 3);
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
            model = await readModel();
          });

          testWidgets('the rest side reads a dash', (tester) async {
            expect(model.restCaloriesAverage, isNull);
            expect(model.restProteinAverage, isNull);

            await pumpStats(tester);

            expect(
              _fuelText('fuel_split_training'),
              'Training 200 kcal · 20 g',
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
            model = await readModel();
          });

          testWidgets('the training side reads a dash', (tester) async {
            expect(model.trainingCaloriesAverage, isNull);
            expect(model.trainingProteinAverage, isNull);

            await pumpStats(tester);

            expect(_fuelText('fuel_split_training'), 'Training $_kAbsent');
            expect(_fuelText('fuel_split_rest'), 'Rest 200 kcal · 20 g');
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
            expect(_fuelText('fuel_calories'), _kAbsent);
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
              findsOneWidget,
            );
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
              findsOneWidget,
            );
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
          // The toggle is live on the screen the row opened.
          expect(find.text('Macros'), findsOneWidget);
          await tester.tap(find.text('Macros'));
          await tester.pumpAndSettle();
          expect(find.byType(NutritionTrendScreen), findsOneWidget);
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

        testWidgets('the row renders with an empty window, every figure a '
            'dash', (tester) async {
          expect(model, isNotNull);
          expect(model.loggedDays, 0);
          expect(model.caloriesAverage, isNull);
          expect(model.proteinAverage, isNull);
          expect(model.trainingCaloriesAverage, isNull);
          expect(model.restCaloriesAverage, isNull);

          await pumpStats(tester);

          expect(_fuelSection, findsOneWidget);
          expect(_fuelText('fuel_logged_days'), '0/7 days logged');
          expect(_fuelText('fuel_calories'), _kAbsent);
          expect(_fuelText('fuel_calories_change'), _kAbsent);
          expect(_fuelText('fuel_protein'), _kAbsent);
          expect(_fuelText('fuel_protein_change'), _kAbsent);
          expect(_fuelText('fuel_split_training'), 'Training $_kAbsent');
          expect(_fuelText('fuel_split_rest'), 'Rest $_kAbsent');
          expect(_fuelTexts(), isNot(contains('0 kcal')));
          expect(_fuelTexts(), isNot(contains('0 g')));
        });
      });

      // ─── S-1112: the Fuel header carries no window chip ───────────────────

      /// A resistance exercise with a logged set, so the Instruments list has a
      /// section — and therefore a window chip — of its own.
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

          testWidgets('the Fuel header carries no chip and the first chip '
              'belongs to the Instruments list', (tester) async {
            await pumpStats(tester);

            final chips = find.byKey(const Key('stats_window_chip'));
            expect(chips, findsNWidgets(5));
            final instrumentsHeader = find.ancestor(
              of: chips.first,
              matching: find.byType(OmniCardHeader),
            );
            expect(
              tester.widget<OmniCardHeader>(instrumentsHeader).title,
              'Resistance',
            );
            expect(
              find.descendant(
                of: _fuelSection,
                matching: find.byKey(const Key('stats_window_chip')),
              ),
              findsNothing,
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
    });
  }
}
