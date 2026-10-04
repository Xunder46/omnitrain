// filepath: test/stats_primer_home_test.dart
//
// The Stats primer's Home-level hosting: the one-shot auto-open on the
// first Stats tap from Home, and the compatibility contract when Home
// holds no primer state (see
// `docs/plans/2026-10-04-10b-stats-pr10b-primer-sheet-plan/`).
//
// Mock-only: these are widget tests, so the repository is the in-memory
// `MockWorkoutRepository`. A Hive write inside a widget test's fake-async
// zone never drains, and the primer state persists its flag on markSeen.
//
// The harness mirrors `test/nutrition_primer_test.dart` / `test/home_logo_hub_open_test.dart`:
// open the hub by tapping the logo `Image`, then tap the `MaintenanceTile`
// whose title is `'Stats'`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/exercise_library_service.dart';
import 'package:omnitrain/core/services/routine_session_service.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/home/home_screen.dart';
import 'package:omnitrain/features/stats/stats_screen.dart';
import 'package:omnitrain/features/stats/widgets/stats_primer_sheet.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';
import 'package:omnitrain/state/exercise/exercise_library_state.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/home/home_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/period/period_state.dart';
import 'package:omnitrain/state/profile/profile_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/stats/stats_primer_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/cards/maintenance_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';
import 'helpers/test_nutrition_primer_state.dart';
import 'helpers/test_stats_primer_state.dart';

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

/// Build a `HomeScreen` for the Stats-tile tests. [statsPrimerState] is
/// optional and nullable, exactly as in production (D-2020): the nine
/// existing HomeScreen-constructing test files omit it and nothing changes.
Future<HomeScreen> _buildHome(
  MockWorkoutRepository repo, {
  StatsPrimerState? statsPrimerState,
}) async {
  final workoutState = WorkoutState(repo);
  final homeState = HomeState(repo);
  await homeState.init();
  final routineState = RoutineState(repo);
  final routineSessionService = RoutineSessionService(repo);
  final sessionSummaryService = SessionSummaryService(repo);
  final calendarState = CalendarState(repo);
  await calendarState.init();
  final periodState = PeriodState(repo);
  final profileState = ProfileState(repo);
  await profileState.loadProfile();
  final preferencesService = fakePreferencesService();
  await preferencesService.init();
  final settingsState = SettingsState(repo, preferencesService);
  await settingsState.initialize();
  final nutritionPrimerState = await buildNutritionPrimerState(repo);
  final exerciseLibraryState = ExerciseLibraryState(
    service: ExerciseLibraryService(repo),
    workoutState: workoutState,
  );

  return HomeScreen(
    workoutState: workoutState,
    homeState: homeState,
    routineState: routineState,
    routineSessionService: routineSessionService,
    sessionSummaryService: sessionSummaryService,
    calendarState: calendarState,
    periodState: periodState,
    profileState: profileState,
    settingsState: settingsState,
    timerAlertService: FakeTimerAlertService(),
    nutritionState: NutritionState(repo),
    foodLibraryState: FoodLibraryState(repo),
    nutritionPrimerState: nutritionPrimerState,
    exerciseLibraryState: exerciseLibraryState,
    statsPrimerState: statsPrimerState,
  );
}

/// Open the hub (tap the logo) and tap the 'Stats' tile.
Future<void> _tapStatsTile(WidgetTester tester) async {
  await tester.tap(find.byType(Image));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(MaintenanceTile, 'Stats'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('S-2701: the first Stats tap from Home shows the primer once', () {
    testWidgets(
      'an unseen state shows the sheet on the first tap and marks it seen when the sheet closes',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repo = await _freshRepo();
        final state = await buildStatsPrimerState(repo);
        expect(state.shouldShowPrimer, isTrue);

        await tester.pumpWidget(
          MaterialApp(home: await _buildHome(repo, statsPrimerState: state)),
        );
        await tester.pumpAndSettle();

        await _tapStatsTile(tester);

        // The sheet is up with the three blocks and the CTA.
        expect(find.byType(StatsPrimerSheet), findsOneWidget);
        expect(
          find.byKey(const Key('stats_primer_block_page')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('stats_primer_block_signals')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('stats_primer_block_records')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('stats_primer_dismiss')), findsOneWidget);
        // The host marks seen when the sheet's future completes, not while
        // it is open (D-2022).
        expect(state.hasSeen, isFalse);

        await tester.tap(find.byKey(const Key('stats_primer_dismiss')));
        await tester.pumpAndSettle();

        expect(find.byType(StatsPrimerSheet), findsNothing);
        expect(find.byType(StatsScreen), findsOneWidget);
        expect(state.hasSeen, isTrue);
        expect(state.shouldShowPrimer, isFalse);
      },
    );
  });

  group('S-2716: a second Stats tap pushes Stats directly', () {
    testWidgets('a seen state pushes Stats with no sheet', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = await _freshRepo();
      await repo.setPreferenceBool(StatsPrimerState.preferenceKey, true);
      final state = await buildStatsPrimerState(repo);
      expect(state.shouldShowPrimer, isFalse);

      await tester.pumpWidget(
        MaterialApp(home: await _buildHome(repo, statsPrimerState: state)),
      );
      await tester.pumpAndSettle();

      await _tapStatsTile(tester);

      expect(find.byType(StatsPrimerSheet), findsNothing);
      expect(find.byType(StatsScreen), findsOneWidget);
      // The state is injected, so the pushed screen carries the "?".
      expect(find.byKey(const Key('stats_primer_help')), findsOneWidget);
    });
  });

  group(
    'S-2717: a Home with no state pushes Stats directly and Stats has no "?"',
    () {
      testWidgets('a null state pushes Stats with showPrimerHelp false', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(400, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repo = await _freshRepo();

        await tester.pumpWidget(MaterialApp(home: await _buildHome(repo)));
        await tester.pumpAndSettle();

        await _tapStatsTile(tester);

        expect(find.byType(StatsPrimerSheet), findsNothing);
        expect(find.byType(StatsScreen), findsOneWidget);
        expect(find.byKey(const Key('stats_primer_help')), findsNothing);
      });
    },
  );

  group(
    'S-2718: dismissing the auto-shown sheet by an outside tap still marks it seen',
    () {
      testWidgets(
        'the flag is false while the sheet shows and true after an outside tap',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(400, 900));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final repo = await _freshRepo();
          final state = await buildStatsPrimerState(repo);

          await tester.pumpWidget(
            MaterialApp(home: await _buildHome(repo, statsPrimerState: state)),
          );
          await tester.pumpAndSettle();

          await _tapStatsTile(tester);

          expect(find.byType(StatsPrimerSheet), findsOneWidget);
          expect(state.hasSeen, isFalse);

          // Tap the modal barrier, not the CTA — any close counts as seen.
          await tester.tapAt(const Offset(10, 10));
          await tester.pumpAndSettle();

          expect(find.byType(StatsPrimerSheet), findsNothing);
          expect(state.hasSeen, isTrue);
          expect(state.shouldShowPrimer, isFalse);
          expect(find.byType(StatsScreen), findsOneWidget);
        },
      );
    },
  );
}
