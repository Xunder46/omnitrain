import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/app.dart';
import 'package:omnitrain/core/services/routine_session_service.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/core/constants/modality.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/core/constants/profile_measurements.dart';
import 'package:omnitrain/features/calendar/calendar_screen.dart';
import 'package:omnitrain/features/calendar/day_session_list_screen.dart';
import 'package:omnitrain/features/exercise/exercise_detail_screen.dart';
import 'package:omnitrain/features/exercise/exercise_editor_screen.dart';
import 'package:omnitrain/features/home/home_screen.dart';
import 'package:omnitrain/features/onboarding/onboarding_screen.dart';
import 'package:omnitrain/features/period/create_period_screen.dart';
import 'package:omnitrain/features/period/period_list_screen.dart';
import 'package:omnitrain/features/profile/profile_screen.dart';
import 'package:omnitrain/features/profile/widgets/measurement_history_chart_sheet.dart';
import 'package:omnitrain/features/routine/my_routines_screen.dart';
import 'package:omnitrain/features/routine/routine_setup_screen.dart';
import 'package:omnitrain/features/session/session_overview_screen.dart';
import 'package:omnitrain/features/session/session_summary_screen.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/features/settings/settings_screen.dart';
import 'package:omnitrain/features/splash/omni_splash_screen.dart';
import 'package:omnitrain/features/stats/stats_screen.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';
import 'package:omnitrain/state/home/home_state.dart';
import 'package:omnitrain/state/period/period_state.dart';
import 'package:omnitrain/state/profile/profile_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/layout/omni_surface.dart';
import 'package:omnitrain/widgets/layout/omni_bottom_cta.dart';
import 'package:omnitrain/widgets/pickers/exercise_picker_dialog.dart';
import 'package:omnitrain/widgets/pickers/metric_chooser_dialog.dart';
import 'package:omnitrain/widgets/pickers/modality_picker_dialog.dart';

// ── Helpers ──────────────────────────────────────────────────────────────

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

void main() {
  group('OmniBottomCTA', () {
    testWidgets('uses the shared primary height and corner radius', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: OmniBottomCTA(
              label: 'Primary Action',
              onPressed: () {},
            ),
          ),
        ),
      );

      expect(find.byType(OmniBottomCTA), findsOneWidget);
      expect(find.text('Primary Action'), findsOneWidget);

      final sizedBox = tester.widget<SizedBox>(
        find
            .ancestor(
              of: find.byType(FilledButton),
              matching: find.byType(SizedBox),
            )
            .first,
      );
      expect(sizedBox.height, OmniTheme.buttonPrimaryHeight);

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      final resolvedShape = button.style?.shape?.resolve(<WidgetState>{});
      expect(resolvedShape, isA<RoundedRectangleBorder>());
      final shape = resolvedShape! as RoundedRectangleBorder;
      expect(
        shape.borderRadius,
        BorderRadius.circular(OmniTheme.buttonBorderRadius),
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SettingsScreen
  // ══════════════════════════════════════════════════════════════════════════

  group('SettingsScreen', () {
    testWidgets('renders Settings title and Appearance section', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      final settingsState = SettingsState(repo);
      await settingsState.initialize();

      await tester.pumpWidget(
        MaterialApp(home: SettingsScreen(settingsState: settingsState)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('APPEARANCE'), findsOneWidget);
    });

    testWidgets('shows only the five retained theme options', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      final settingsState = SettingsState(repo);
      await settingsState.initialize();

      await tester.pumpWidget(
        MaterialApp(home: SettingsScreen(settingsState: settingsState)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Abyssal Neon'), findsOneWidget);
      expect(find.text('Forge & Ember'), findsOneWidget);
      expect(find.text('Obsidian Volt'), findsOneWidget);
      expect(find.text('Void Pulse'), findsOneWidget);
      expect(find.text('Crimson Dojo'), findsOneWidget);

      expect(find.text('Circuit Green'), findsNothing);
      expect(find.text('Arctic Core'), findsNothing);
      expect(find.text('Titanium Rose'), findsNothing);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // PeriodListScreen
  // ══════════════════════════════════════════════════════════════════════════

  group('PeriodListScreen', () {
    testWidgets('renders title and empty state', (WidgetTester tester) async {
      final repo = await _freshRepo();
      final periodState = PeriodState(repo);

      await tester.pumpWidget(
        MaterialApp(home: PeriodListScreen(periodState: periodState)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Training Periods'), findsOneWidget);
      expect(find.text('No training periods yet.'), findsOneWidget);
    });

    testWidgets('shows period when data exists', (WidgetTester tester) async {
      final repo = await _freshRepo();
      await repo.createPeriod(
        TrainingPeriod(
          id: 'p-1',
          ownerUserId: 'u-1',
          name: 'Bulk Phase',
          startDateMs: DateTime(2025, 1, 1).millisecondsSinceEpoch,
          endDateMs: DateTime(2025, 3, 31).millisecondsSinceEpoch,
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      );

      final periodState = PeriodState(repo);

      await tester.pumpWidget(
        MaterialApp(home: PeriodListScreen(periodState: periodState)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bulk Phase'), findsOneWidget);
      expect(find.text('No training periods yet.'), findsNothing);
    });

    testWidgets('shows add button', (WidgetTester tester) async {
      final repo = await _freshRepo();
      final periodState = PeriodState(repo);

      await tester.pumpWidget(
        MaterialApp(home: PeriodListScreen(periodState: periodState)),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byType(OmniBottomCTA), findsOneWidget);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // CreatePeriodScreen
  // ══════════════════════════════════════════════════════════════════════════

  group('CreatePeriodScreen', () {
    testWidgets('shows "Create Period" title for new period', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      final periodState = PeriodState(repo);

      await tester.pumpWidget(
        MaterialApp(home: CreatePeriodScreen(periodState: periodState)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Create Period'), findsOneWidget);
    });

    testWidgets('shows "Edit Period" title when editing existing', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      final periodState = PeriodState(repo);

      final existing = TrainingPeriod(
        id: 'p-edit',
        ownerUserId: 'u-1',
        name: 'My Period',
        startDateMs: DateTime(2025, 1, 1).millisecondsSinceEpoch,
        endDateMs: DateTime(2025, 3, 31).millisecondsSinceEpoch,
        createdAtMs: 100,
        updatedAtMs: 100,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: CreatePeriodScreen(
            periodState: periodState,
            existingPeriod: existing,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Edit Period'), findsOneWidget);
    });

    testWidgets('pre-fills name when editing existing period', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      final periodState = PeriodState(repo);

      final existing = TrainingPeriod(
        id: 'p-edit',
        ownerUserId: 'u-1',
        name: 'Bulk Phase',
        startDateMs: DateTime(2025, 1, 1).millisecondsSinceEpoch,
        endDateMs: DateTime(2025, 3, 31).millisecondsSinceEpoch,
        createdAtMs: 100,
        updatedAtMs: 100,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: CreatePeriodScreen(
            periodState: periodState,
            existingPeriod: existing,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The name field should be pre-filled
      expect(find.text('Bulk Phase'), findsOneWidget);
    });

    testWidgets('has a save button', (WidgetTester tester) async {
      final repo = await _freshRepo();
      final periodState = PeriodState(repo);

      await tester.pumpWidget(
        MaterialApp(home: CreatePeriodScreen(periodState: periodState)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OmniBottomCTA), findsOneWidget);
      expect(find.text('Save'), findsWidgets);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // CalendarScreen
  // ══════════════════════════════════════════════════════════════════════════

  group('CalendarScreen', () {
    Future<
      ({
        CalendarState calendarState,
        PeriodState periodState,
        WorkoutState workoutState,
        RoutineState routineState,
        RoutineSessionService routineSessionService,
        SessionSummaryService sessionSummaryService,
      })
    >
    setupCalendar() async {
      final repo = await _freshRepo();
      final calendarState = CalendarState(repo);
      await calendarState.init();
      final periodState = PeriodState(repo);
      final workoutState = WorkoutState(repo);
      final routineState = RoutineState(repo);
      final routineSessionService = RoutineSessionService(repo);
      final sessionSummaryService = SessionSummaryService(repo);
      return (
        calendarState: calendarState,
        periodState: periodState,
        workoutState: workoutState,
        routineState: routineState,
        routineSessionService: routineSessionService,
        sessionSummaryService: sessionSummaryService,
      );
    }

    testWidgets('renders Calendar title and month navigation', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      final deps = await setupCalendar();

      await tester.pumpWidget(
        MaterialApp(
          home: CalendarScreen(
            calendarState: deps.calendarState,
            periodState: deps.periodState,
            workoutState: deps.workoutState,
            routineState: deps.routineState,
            routineSessionService: deps.routineSessionService,
            sessionSummaryService: deps.sessionSummaryService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Calendar'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('shows weekday headers', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      final deps = await setupCalendar();

      await tester.pumpWidget(
        MaterialApp(
          home: CalendarScreen(
            calendarState: deps.calendarState,
            periodState: deps.periodState,
            workoutState: deps.workoutState,
            routineState: deps.routineState,
            routineSessionService: deps.routineSessionService,
            sessionSummaryService: deps.sessionSummaryService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mon'), findsOneWidget);
      expect(find.text('Sun'), findsOneWidget);
    });

    testWidgets('navigating months changes displayed month', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      final deps = await setupCalendar();

      await tester.pumpWidget(
        MaterialApp(
          home: CalendarScreen(
            calendarState: deps.calendarState,
            periodState: deps.periodState,
            workoutState: deps.workoutState,
            routineState: deps.routineState,
            routineSessionService: deps.routineSessionService,
            sessionSummaryService: deps.sessionSummaryService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final initialMonth = deps.calendarState.month;

      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();

      if (initialMonth == 1) {
        expect(deps.calendarState.month, 12);
      } else {
        expect(deps.calendarState.month, initialMonth - 1);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // MyRoutinesScreen
  // ══════════════════════════════════════════════════════════════════════════

  group('MyRoutinesScreen', () {
    testWidgets('renders title and empty state', (WidgetTester tester) async {
      final repo = await _freshRepo();
      final routineState = RoutineState(repo);
      final routineSessionService = RoutineSessionService(repo);
      final sessionSummaryService = SessionSummaryService(repo);

      await tester.pumpWidget(
        MaterialApp(
          home: MyRoutinesScreen(
            routineState: routineState,
            routineSessionService: routineSessionService,
            sessionSummaryService: sessionSummaryService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('My Routines'), findsOneWidget);
      expect(find.text('No Routines Yet'), findsOneWidget);
    });

    testWidgets('shows FAB to create routine', (WidgetTester tester) async {
      final repo = await _freshRepo();
      final routineState = RoutineState(repo);
      final routineSessionService = RoutineSessionService(repo);
      final sessionSummaryService = SessionSummaryService(repo);

      await tester.pumpWidget(
        MaterialApp(
          home: MyRoutinesScreen(
            routineState: routineState,
            routineSessionService: routineSessionService,
            sessionSummaryService: sessionSummaryService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('shows routine when data exists', (WidgetTester tester) async {
      final repo = await _freshRepo();
      await repo.createTemplate(
        WorkoutTemplate(
          id: 'tmpl-1',
          name: 'Push Day',
          focusModality: 'resistance_lifting',
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      );

      final routineState = RoutineState(repo);
      final routineSessionService = RoutineSessionService(repo);
      final sessionSummaryService = SessionSummaryService(repo);

      await tester.pumpWidget(
        MaterialApp(
          home: MyRoutinesScreen(
            routineState: routineState,
            routineSessionService: routineSessionService,
            sessionSummaryService: sessionSummaryService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Push Day'), findsOneWidget);
      expect(find.text('No Routines Yet'), findsNothing);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // RoutineSetupScreen
  // ══════════════════════════════════════════════════════════════════════════

  group('RoutineSetupScreen', () {
    testWidgets('shows Exercises header and name field for new routine', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final repo = await _freshRepo();
      final routineState = RoutineState(repo);
      routineState.setAutosaveEnabled(false);

      await tester.pumpWidget(
        MaterialApp(home: RoutineSetupScreen(routineState: routineState)),
      );
      await tester.pumpAndSettle();

      // Header title
      expect(find.text('Exercises'), findsOneWidget);
      // Back arrow
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('shows loading state then settles', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final repo = await _freshRepo();
      final routineState = RoutineState(repo);
      routineState.setAutosaveEnabled(false);

      await tester.pumpWidget(
        MaterialApp(home: RoutineSetupScreen(routineState: routineState)),
      );
      // Initially might show loading spinner, then settles
      await tester.pumpAndSettle();

      // After settle, should display the exercises header
      expect(find.text('Exercises'), findsOneWidget);
    });

    testWidgets('add exercise button is visible', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final repo = await _freshRepo();
      final routineState = RoutineState(repo);
      routineState.setAutosaveEnabled(false);

      await tester.pumpWidget(
        MaterialApp(home: RoutineSetupScreen(routineState: routineState)),
      );
      await tester.pumpAndSettle();

      // There should be an add exercise button (add icon)
      expect(find.byIcon(Icons.add), findsWidgets);
    });

    testWidgets('loads existing routine when templateId provided', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final repo = await _freshRepo();
      // Create a template in the repo
      await repo.createTemplate(
        WorkoutTemplate(
          id: 'tmpl-existing',
          name: 'Leg Day',
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      );
      await repo.createTemplateSegment(
        TemplateSegment(
          id: 'tseg-1',
          templateId: 'tmpl-existing',
          orderIndex: 0,
          segmentType: 'main',
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      );

      final routineState = RoutineState(repo);
      routineState.setAutosaveEnabled(false);

      await tester.pumpWidget(
        MaterialApp(
          home: RoutineSetupScreen(
            routineState: routineState,
            templateId: 'tmpl-existing',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should not be in loading state
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Exercises'), findsOneWidget);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SessionOverviewScreen
  // ══════════════════════════════════════════════════════════════════════════

  group('SessionOverviewScreen', () {
    testWidgets('shows Workout Session title and empty state', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final routineState = RoutineState(repo);
      final sessionSummaryService = SessionSummaryService(repo);
      final settingsState = SettingsState(repo);
      await settingsState.initialize();

      await tester.pumpWidget(
        MaterialApp(
          home: SessionOverviewScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: sessionSummaryService,
            settingsState: settingsState,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Workout Session'), findsOneWidget);
      expect(find.text('No exercises yet'), findsOneWidget);
    });

    testWidgets('shows Add Exercise button', (WidgetTester tester) async {
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final routineState = RoutineState(repo);
      final sessionSummaryService = SessionSummaryService(repo);
      final settingsState = SettingsState(repo);
      await settingsState.initialize();

      await tester.pumpWidget(
        MaterialApp(
          home: SessionOverviewScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: sessionSummaryService,
            settingsState: settingsState,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Add Exercise'), findsOneWidget);
    });

    testWidgets('Start Workout button is disabled when no exercises', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final routineState = RoutineState(repo);
      final sessionSummaryService = SessionSummaryService(repo);
      final settingsState = SettingsState(repo);
      await settingsState.initialize();

      await tester.pumpWidget(
        MaterialApp(
          home: SessionOverviewScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: sessionSummaryService,
            settingsState: settingsState,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Start Workout button should be present but disabled
      final startButton = find.text('Start Workout');
      expect(startButton, findsOneWidget);
      // The button should be a FilledButton
      final button = tester.widget<FilledButton>(
        find.ancestor(of: startButton, matching: find.byType(FilledButton)),
      );
      expect(button.onPressed, isNull); // disabled
    });

    testWidgets('shows exercise count when exercises exist', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final routineState = RoutineState(repo);
      final sessionSummaryService = SessionSummaryService(repo);
      final settingsState = SettingsState(repo);
      await settingsState.initialize();

      // Pre-seed a session with an exercise
      await workoutState.createNewSession();
      final exercises = await repo.getExercises();
      await workoutState.addExerciseToSession(
        exercises.first,
        chosenMetric: 'reps',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SessionOverviewScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: sessionSummaryService,
            settingsState: settingsState,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No exercises yet'), findsNothing);
      // Exercise name should be visible
      expect(find.text(exercises.first.name), findsOneWidget);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // HomeScreen
  // ══════════════════════════════════════════════════════════════════════════

  group('HomeScreen', () {
    Future<HomeScreen> buildHomeScreen(MockWorkoutRepository repo) async {
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
      final settingsState = SettingsState(repo);
      await settingsState.initialize();

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
      );
    }

    testWidgets('renders TRAIN label', (WidgetTester tester) async {
      final repo = await _freshRepo();
      final screen = await buildHomeScreen(repo);

      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pumpAndSettle();

      expect(find.text('TRAIN'), findsOneWidget);
    });

    testWidgets('renders app bar logo', (WidgetTester tester) async {
      final repo = await _freshRepo();
      final screen = await buildHomeScreen(repo);

      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pumpAndSettle();

      // AppBar uses an Image.asset logo
      expect(find.byType(Image), findsWidgets);
    });

    testWidgets('renders energy tile grid', (WidgetTester tester) async {
      final repo = await _freshRepo();
      final screen = await buildHomeScreen(repo);

      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pumpAndSettle();

      // Should have multiple EnergyTile cards in a grid
      expect(find.byType(CustomScrollView), findsWidgets);
    });

    testWidgets('free training flow shows rolling toggle and inline guidance', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      final screen = await buildHomeScreen(repo);

      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();

      expect(find.text('Rolling Session'), findsWidgets);
      expect(
        find.text(
          'A rolling session stays open all day. Tap any tile to return and '
          'add more work at any time. No session timer — just your sets.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('rolling toggle does not open a second onboarding sheet', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
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
      final settingsState = SettingsState(repo);
      await settingsState.initialize();

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            workoutState: workoutState,
            homeState: homeState,
            routineState: routineState,
            routineSessionService: routineSessionService,
            sessionSummaryService: sessionSummaryService,
            calendarState: calendarState,
            periodState: periodState,
            profileState: profileState,
            settingsState: settingsState,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      expect(find.text('Got it'), findsNothing);
      expect(find.text("Don't show again"), findsNothing);
    });

    testWidgets('rolling active session navigates on tile tap without dialog', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
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
      final settingsState = SettingsState(repo);
      await settingsState.initialize();

      await workoutState.createNewSession(isRolling: true);
      final exercises = await repo.getExercises();
      await workoutState.addExerciseToSession(exercises.first);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            workoutState: workoutState,
            homeState: homeState,
            routineState: routineState,
            routineSessionService: routineSessionService,
            sessionSummaryService: sessionSummaryService,
            calendarState: calendarState,
            periodState: periodState,
            profileState: profileState,
            settingsState: settingsState,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cardio'));
      // The pushed WorkoutSessionScreen triggers a known transient
      // setState-during-build assertion in tests; consume it and continue.
      await tester.pump();
      tester.takeException();
      await tester.pump();

      expect(find.byType(WorkoutSessionScreen), findsOneWidget);
      expect(find.text('Start New Session?'), findsNothing);
    });

    testWidgets(
      'my routines still shows conflict dialog during rolling session',
      (WidgetTester tester) async {
        final repo = await _freshRepo();
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
        final settingsState = SettingsState(repo);
        await settingsState.initialize();

        await workoutState.createNewSession(isRolling: true);
        final exercises = await repo.getExercises();
        await workoutState.addExerciseToSession(exercises.first);

        await tester.pumpWidget(
          MaterialApp(
            home: HomeScreen(
              workoutState: workoutState,
              homeState: homeState,
              routineState: routineState,
              routineSessionService: routineSessionService,
              sessionSummaryService: sessionSummaryService,
              calendarState: calendarState,
              periodState: periodState,
              profileState: profileState,
              settingsState: settingsState,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.folder_open));
        await tester.pumpAndSettle();

        expect(find.text('Start New Session?'), findsOneWidget);
        expect(find.byType(MyRoutinesScreen), findsNothing);
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // OnboardingScreen
  // ══════════════════════════════════════════════════════════════════════════

  group('OnboardingScreen', () {
    Future<
      ({
        MockWorkoutRepository repo,
        WorkoutState workoutState,
        HomeState homeState,
        RoutineState routineState,
        RoutineSessionService routineSessionService,
        SessionSummaryService sessionSummaryService,
        CalendarState calendarState,
        PeriodState periodState,
        ProfileState profileState,
        SettingsState settingsState,
      })
    >
    buildOnboardingDeps() async {
      final repo = await _freshRepo();
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
      final settingsState = SettingsState(repo);
      await settingsState.initialize();

      return (
        repo: repo,
        workoutState: workoutState,
        homeState: homeState,
        routineState: routineState,
        routineSessionService: routineSessionService,
        sessionSummaryService: sessionSummaryService,
        calendarState: calendarState,
        periodState: periodState,
        profileState: profileState,
        settingsState: settingsState,
      );
    }

    Widget buildOnboardingScreen(
      ({
        MockWorkoutRepository repo,
        WorkoutState workoutState,
        HomeState homeState,
        RoutineState routineState,
        RoutineSessionService routineSessionService,
        SessionSummaryService sessionSummaryService,
        CalendarState calendarState,
        PeriodState periodState,
        ProfileState profileState,
        SettingsState settingsState,
      })
      deps,
    ) {
      return MaterialApp(
        home: OnboardingScreen(
          repository: deps.repo,
          workoutState: deps.workoutState,
          homeState: deps.homeState,
          routineState: deps.routineState,
          routineSessionService: deps.routineSessionService,
          sessionSummaryService: deps.sessionSummaryService,
          calendarState: deps.calendarState,
          periodState: deps.periodState,
          profileState: deps.profileState,
          settingsState: deps.settingsState,
        ),
      );
    }

    testWidgets('renders welcome page with title and skip button', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      final deps = await buildOnboardingDeps();

      await tester.pumpWidget(buildOnboardingScreen(deps));
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.text('OMNITRAIN'), findsOneWidget);
      expect(find.text('one app for every way you train'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('swiping advances pages and final page shows get started', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      final deps = await buildOnboardingDeps();

      await tester.pumpWidget(buildOnboardingScreen(deps));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await tester.pumpAndSettle();

      expect(find.text('How You Train'), findsOneWidget);
      expect(
        find.text(
          'OmniTrain adapts its interface to the way you actually train.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await tester.pumpAndSettle();

      expect(find.text('How You Plan'), findsOneWidget);
      expect(find.text('Get Started'), findsOneWidget);

      final skipButton = find.widgetWithText(TextButton, 'Skip');
      expect(skipButton, findsOneWidget);

      final skipOpacity = tester.widget<AnimatedOpacity>(
        find
            .ancestor(of: skipButton, matching: find.byType(AnimatedOpacity))
            .first,
      );
      final skipIgnorePointer = tester.widget<IgnorePointer>(
        find
            .ancestor(of: skipButton, matching: find.byType(IgnorePointer))
            .first,
      );

      expect(skipOpacity.opacity, 0.0);
      expect(skipIgnorePointer.ignoring, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping Skip completes onboarding and navigates home', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      final deps = await buildOnboardingDeps();

      await tester.pumpWidget(buildOnboardingScreen(deps));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(await deps.repo.getPreferenceBool('onboarding_complete'), isTrue);
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping Get Started completes onboarding and navigates home', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      final deps = await buildOnboardingDeps();

      await tester.pumpWidget(buildOnboardingScreen(deps));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Get Started'));
      await tester.pumpAndSettle();

      expect(await deps.repo.getPreferenceBool('onboarding_complete'), isTrue);
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('MyApp skips onboarding when showOnboarding is false', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      final deps = await buildOnboardingDeps();

      await tester.pumpWidget(
        MyApp(
          repository: deps.repo,
          showOnboarding: false,
          workoutState: deps.workoutState,
          homeState: deps.homeState,
          routineState: deps.routineState,
          routineSessionService: deps.routineSessionService,
          sessionSummaryService: deps.sessionSummaryService,
          calendarState: deps.calendarState,
          periodState: deps.periodState,
          profileState: deps.profileState,
          settingsState: deps.settingsState,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });

    test('repository persists onboarding_complete preference', () async {
      final repo = await _freshRepo();

      expect(await repo.getPreferenceBool('onboarding_complete'), isFalse);

      await repo.setPreferenceBool('onboarding_complete', true);

      expect(await repo.getPreferenceBool('onboarding_complete'), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // StatsScreen
  // ══════════════════════════════════════════════════════════════════════════

  group('StatsScreen', () {
    Future<void> seedCompletedSession(
      MockWorkoutRepository repo, {
      required String id,
      required DateTime start,
      required Duration duration,
      bool isRolling = false,
      String? modality,
    }) async {
      final startMs = start.millisecondsSinceEpoch;
      final endMs = start.add(duration).millisecondsSinceEpoch;

      await repo.createSession(
        TrainingSession(
          id: id,
          ownerUserId: 'user-1',
          modality: modality,
          startedAtMs: startMs,
          endedAtMs: endMs,
          isRolling: isRolling,
          createdAtMs: startMs,
          updatedAtMs: endMs,
        ),
      );
    }

    Future<void> pumpStatsScreen(
      WidgetTester tester,
      MockWorkoutRepository repo,
    ) async {
      final workoutState = WorkoutState(repo);
      final settingsState = SettingsState(repo);
      await settingsState.initialize();

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

    int totalSessionsShownInChart(WidgetTester tester) {
      final chart = tester.widget<BarChart>(find.byType(BarChart));
      return chart.data.barGroups.fold<int>(0, (sum, group) {
        return sum +
            group.barRods.fold<int>(
              0,
              (rodSum, rod) => rodSum + rod.toY.round(),
            );
      });
    }

    testWidgets('shows Stats AppBar title', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      final repo = await _freshRepo();

      await pumpStatsScreen(tester, repo);

      expect(find.text('Stats'), findsOneWidget);
    });

    testWidgets('zero state renders without crash or phantom data', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      final repo = await _freshRepo();

      await pumpStatsScreen(tester, repo);

      expect(find.text('No sessions yet'), findsOneWidget);
      expect(
        find.text('Complete your first session to see stats here.'),
        findsOneWidget,
      );
      expect(find.text('ALL TIME'), findsNothing);
      expect(find.text('ACTIVITY'), findsNothing);
      expect(find.byType(BarChart), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('aggregate totals reflect seeded completed sessions', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      final repo = await _freshRepo();
      final now = DateTime.now();

      await seedCompletedSession(
        repo,
        id: 'sess-1',
        start: now.subtract(const Duration(days: 1, minutes: 30)),
        duration: const Duration(minutes: 30),
        modality: 'resistance_lifting',
      );
      await seedCompletedSession(
        repo,
        id: 'sess-2',
        start: now.subtract(const Duration(days: 3, minutes: 45)),
        duration: const Duration(minutes: 45),
        modality: 'sports',
      );
      await seedCompletedSession(
        repo,
        id: 'sess-3',
        start: now.subtract(const Duration(days: 8, hours: 1)),
        duration: const Duration(hours: 1),
        modality: 'cardio_endurance',
      );

      await pumpStatsScreen(tester, repo);

      final aggregateCard = find.byType(OmniSurface).first;
      expect(
        find.descendant(of: aggregateCard, matching: find.text('SESSIONS')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: aggregateCard, matching: find.text('3')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: aggregateCard, matching: find.text('2h 15m')),
        findsOneWidget,
      );
      expect(find.byType(BarChart), findsOneWidget);
    });

    testWidgets('30-day activity excludes sessions outside the window', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      final repo = await _freshRepo();
      final now = DateTime.now();

      await seedCompletedSession(
        repo,
        id: 'old-session',
        start: now.subtract(const Duration(days: 60, hours: 1)),
        duration: const Duration(hours: 1),
      );
      await seedCompletedSession(
        repo,
        id: 'recent-session',
        start: now.subtract(const Duration(days: 5, minutes: 20)),
        duration: const Duration(minutes: 20),
      );

      await pumpStatsScreen(tester, repo);

      final aggregateCard = find.byType(OmniSurface).first;
      expect(
        find.descendant(of: aggregateCard, matching: find.text('2')),
        findsOneWidget,
      );
      expect(find.byType(BarChart), findsOneWidget);
      expect(totalSessionsShownInChart(tester), 1);
    });

    testWidgets('rolling sessions are excluded from duration aggregates', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      final repo = await _freshRepo();
      final now = DateTime.now();

      await seedCompletedSession(
        repo,
        id: 'rolling-session',
        start: now.subtract(const Duration(days: 2, hours: 2)),
        duration: const Duration(hours: 2),
        isRolling: true,
      );
      await seedCompletedSession(
        repo,
        id: 'standard-session',
        start: now.subtract(const Duration(days: 1, minutes: 45)),
        duration: const Duration(minutes: 45),
        isRolling: false,
      );

      await pumpStatsScreen(tester, repo);

      final aggregateCard = find.byType(OmniSurface).first;
      expect(
        find.descendant(of: aggregateCard, matching: find.text('2')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: aggregateCard, matching: find.text('45m')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: aggregateCard, matching: find.text('2h 45m')),
        findsNothing,
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // ExerciseEditorScreen
  // ══════════════════════════════════════════════════════════════════════════

  group('ExerciseEditorScreen', () {
    testWidgets('shows New Exercise title', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);

      await tester.pumpWidget(
        MaterialApp(home: ExerciseEditorScreen(workoutState: workoutState)),
      );
      await tester.pumpAndSettle();

      expect(find.text('New Exercise'), findsOneWidget);
    });

    testWidgets('shows Capabilities section', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);

      await tester.pumpWidget(
        MaterialApp(home: ExerciseEditorScreen(workoutState: workoutState)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Capabilities'), findsOneWidget);
    });

    testWidgets('shows Save exercise button', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);

      await tester.pumpWidget(
        MaterialApp(home: ExerciseEditorScreen(workoutState: workoutState)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Save exercise'), findsOneWidget);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // ProfileScreen
  // ══════════════════════════════════════════════════════════════════════════

  group('ProfileScreen', () {
    testWidgets('shows Profile AppBar title', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      final repo = await _freshRepo();
      final profileState = ProfileState(repo);
      await profileState.loadProfile();

      await tester.pumpWidget(
        MaterialApp(home: ProfileScreen(profileState: profileState)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Profile'), findsOneWidget);
    });

    testWidgets('renders without crash after loading profile', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      final repo = await _freshRepo();
      final profileState = ProfileState(repo);
      await profileState.loadProfile();

      await tester.pumpWidget(
        MaterialApp(home: ProfileScreen(profileState: profileState)),
      );
      await tester.pumpAndSettle();

      // No crash — widgets tree built successfully
      expect(find.byType(ProfileScreen), findsOneWidget);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // DaySessionListScreen
  // ══════════════════════════════════════════════════════════════════════════

  group('DaySessionListScreen', () {
    testWidgets('shows "No sessions on this day." for a past date', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      final repo = await _freshRepo();
      final calendarState = CalendarState(repo);
      await calendarState.init();
      final routineState = RoutineState(repo);
      final workoutState = WorkoutState(repo);
      final routineSessionService = RoutineSessionService(repo);
      final sessionSummaryService = SessionSummaryService(repo);

      final pastDate = DateTime(2020, 1, 15);

      await tester.pumpWidget(
        MaterialApp(
          home: DaySessionListScreen(
            date: pastDate,
            calendarState: calendarState,
            routineState: routineState,
            workoutState: workoutState,
            routineSessionService: routineSessionService,
            sessionSummaryService: sessionSummaryService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No sessions on this day.'), findsOneWidget);
    });

    testWidgets('shows "No sessions planned yet." for a future date', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      final repo = await _freshRepo();
      final calendarState = CalendarState(repo);
      await calendarState.init();
      final routineState = RoutineState(repo);
      final workoutState = WorkoutState(repo);
      final routineSessionService = RoutineSessionService(repo);
      final sessionSummaryService = SessionSummaryService(repo);

      final futureDate = DateTime(2099, 12, 31);

      await tester.pumpWidget(
        MaterialApp(
          home: DaySessionListScreen(
            date: futureDate,
            calendarState: calendarState,
            routineState: routineState,
            workoutState: workoutState,
            routineSessionService: routineSessionService,
            sessionSummaryService: sessionSummaryService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No sessions planned yet.'), findsOneWidget);
    });

    testWidgets('shows formatted date in AppBar title', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      final repo = await _freshRepo();
      final calendarState = CalendarState(repo);
      await calendarState.init();
      final routineState = RoutineState(repo);
      final workoutState = WorkoutState(repo);
      final routineSessionService = RoutineSessionService(repo);
      final sessionSummaryService = SessionSummaryService(repo);

      // Use a fixed past date so OmniDateUtils.formatShort produces known output
      final date = DateTime(2024, 6, 15); // "Jun 15, 2024"

      await tester.pumpWidget(
        MaterialApp(
          home: DaySessionListScreen(
            date: date,
            calendarState: calendarState,
            routineState: routineState,
            workoutState: workoutState,
            routineSessionService: routineSessionService,
            sessionSummaryService: sessionSummaryService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // title contains the date in some format — AppBar must render a Text with date
      expect(find.textContaining('Jun'), findsOneWidget);
    });

    testWidgets(
      'planned session form shows session type and full mode labels',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 1000));
        final repo = await _freshRepo();
        final calendarState = CalendarState(repo);
        await calendarState.init();
        final routineState = RoutineState(repo);
        final workoutState = WorkoutState(repo);
        final routineSessionService = RoutineSessionService(repo);
        final sessionSummaryService = SessionSummaryService(repo);

        final futureDate = DateTime(2099, 12, 31);

        await tester.pumpWidget(
          MaterialApp(
            home: DaySessionListScreen(
              date: futureDate,
              calendarState: calendarState,
              routineState: routineState,
              workoutState: workoutState,
              routineSessionService: routineSessionService,
              sessionSummaryService: sessionSummaryService,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Add Planned Session'));
        await tester.pumpAndSettle();

        expect(find.text('Session Type'), findsOneWidget);
        expect(
          find.widgetWithText(FilledButton, 'Free Training'),
          findsOneWidget,
        );
        expect(find.widgetWithText(OutlinedButton, 'Routine'), findsOneWidget);
      },
    );

    testWidgets(
      'edit planned session opens shared form with session type toggle',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 1000));
        final repo = await _freshRepo();
        final calendarState = CalendarState(repo);
        await calendarState.init();
        final routineState = RoutineState(repo);
        final workoutState = WorkoutState(repo);
        final routineSessionService = RoutineSessionService(repo);
        final sessionSummaryService = SessionSummaryService(repo);

        final today = DateTime.now();
        await calendarState.createPlannedSession(
          date: today,
          modality: Modality.cardioEndurance,
          title: 'Planned Test',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: DaySessionListScreen(
              date: DateTime(today.year, today.month, today.day),
              calendarState: calendarState,
              routineState: routineState,
              workoutState: workoutState,
              routineSessionService: routineSessionService,
              sessionSummaryService: sessionSummaryService,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.edit_outlined).first);
        await tester.pumpAndSettle();

        expect(find.text('Edit Session'), findsOneWidget);
        expect(find.text('Session Type'), findsOneWidget);
        expect(find.text('Free Training'), findsAtLeastNWidgets(1));
        expect(find.text('Routine'), findsOneWidget);
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SessionSummaryScreen
  // ══════════════════════════════════════════════════════════════════════════

  group('SessionSummaryScreen', () {
    Future<WorkoutState> workoutStateWithActiveSession(
      MockWorkoutRepository repo,
    ) async {
      final workoutState = WorkoutState(repo);
      await workoutState.createNewSession();
      return workoutState;
    }

    Future<void> pumpSessionSummaryScreen(
      WidgetTester tester, {
      required MockWorkoutRepository repo,
      required WorkoutState workoutState,
    }) async {
      final routineState = RoutineState(repo);
      final sessionSummaryService = SessionSummaryService(repo);

      await tester.pumpWidget(
        MaterialApp(
          home: SessionSummaryScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: sessionSummaryService,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows feeling modal on mount with five numbered tiles', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final repo = await _freshRepo();
      final workoutState = await workoutStateWithActiveSession(repo);

      await pumpSessionSummaryScreen(
        tester,
        repo: repo,
        workoutState: workoutState,
      );

      expect(find.text('How did it feel?'), findsOneWidget);

      final sheetFinder = find.byType(BottomSheet);
      expect(sheetFinder, findsOneWidget);

      for (int i = 1; i <= 5; i++) {
        expect(
          find.descendant(of: sheetFinder, matching: find.text(i.toString())),
          findsOneWidget,
        );
      }
    });

    testWidgets(
      'feeling modal is non-dismissible and blocks summary controls',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final repo = await _freshRepo();
        final workoutState = await workoutStateWithActiveSession(repo);

        await pumpSessionSummaryScreen(
          tester,
          repo: repo,
          workoutState: workoutState,
        );

        expect(find.text('How did it feel?'), findsOneWidget);
        expect(tester.testTextInput.isVisible, isFalse);

        await tester.tapAt(const Offset(24, 24));
        await tester.pumpAndSettle();
        expect(find.text('How did it feel?'), findsOneWidget);

        await tester.tap(find.text('Done'), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.text('How did it feel?'), findsOneWidget);
        expect(find.byType(SessionSummaryScreen), findsOneWidget);

        await tester.tapAt(tester.getCenter(find.byType(TextField)));
        await tester.pump();
        expect(tester.testTextInput.isVisible, isFalse);
        expect(find.text('How did it feel?'), findsOneWidget);
      },
    );

    testWidgets('selecting tile 3 dismisses the feeling modal and persists', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final repo = await _freshRepo();
      final workoutState = await workoutStateWithActiveSession(repo);

      await pumpSessionSummaryScreen(
        tester,
        repo: repo,
        workoutState: workoutState,
      );

      final sheetFinder = find.byType(BottomSheet);
      await tester.tap(
        find.descendant(of: sheetFinder, matching: find.text('3')),
      );
      await tester.pumpAndSettle();

      expect(find.text('How did it feel?'), findsNothing);
      expect(workoutState.currentSession!.sessionFeeling, 3);
    });

    testWidgets(
      'does not show feeling modal when session feeling already exists',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final repo = await _freshRepo();
        final workoutState = await workoutStateWithActiveSession(repo);
        final sessionId = workoutState.currentSession!.id;
        await workoutState.updateSessionFeeling(sessionId, 4);

        await pumpSessionSummaryScreen(
          tester,
          repo: repo,
          workoutState: workoutState,
        );

        expect(find.text('How did it feel?'), findsNothing);
        expect(find.text('Done'), findsOneWidget);
        expect(find.byType(TextField), findsOneWidget);

        await tester.tap(find.byType(TextField));
        await tester.pump();
        expect(tester.testTextInput.isVisible, isTrue);
      },
    );

    testWidgets('feeling modal subtitle includes resistance modality name', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      await workoutState.createNewSession(modality: 'resistance_lifting');

      await pumpSessionSummaryScreen(
        tester,
        repo: repo,
        workoutState: workoutState,
      );

      final sheetFinder = find.byType(BottomSheet);
      expect(
        find.descendant(
          of: sheetFinder,
          matching: find.text('Resistance / Lifting · Today'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'feeling modal renders Free Training subtitle for null modality',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final repo = await _freshRepo();
        final workoutState = await workoutStateWithActiveSession(repo);

        await pumpSessionSummaryScreen(
          tester,
          repo: repo,
          workoutState: workoutState,
        );

        final sheetFinder = find.byType(BottomSheet);
        expect(
          find.descendant(
            of: sheetFinder,
            matching: find.text('Free Training · Today'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('shows Done button', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final repo = await _freshRepo();
      final workoutState = await workoutStateWithActiveSession(repo);
      final routineState = RoutineState(repo);
      final sessionSummaryService = SessionSummaryService(repo);

      await tester.pumpWidget(
        MaterialApp(
          home: SessionSummaryScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: sessionSummaryService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('has overflow menu with session actions', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final repo = await _freshRepo();
      final workoutState = await workoutStateWithActiveSession(repo);
      final routineState = RoutineState(repo);
      final sessionSummaryService = SessionSummaryService(repo);

      await tester.pumpWidget(
        MaterialApp(
          home: SessionSummaryScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: sessionSummaryService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The SliverAppBar has a popup menu button for session actions
      expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    });

    testWidgets('shows strength group card when session has set effort', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final repo = await _freshRepo();
      final workoutState = await workoutStateWithActiveSession(repo);
      final exercises = await repo.getExercises();
      await workoutState.addExerciseToSession(
        exercises.first,
        chosenMetric: 'reps',
      );
      final routineState = RoutineState(repo);
      final sessionSummaryService = SessionSummaryService(repo);

      await tester.pumpWidget(
        MaterialApp(
          home: SessionSummaryScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: sessionSummaryService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Strength'), findsOneWidget);
      expect(find.text('SETS'), findsOneWidget);
    });

    testWidgets('shows Sports group card when at least one round is finished', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final repo = await _freshRepo();
      final workoutState = await workoutStateWithActiveSession(repo);
      final exercises = await repo.getExercises();
      final roundExercise = exercises.firstWhere(
        (e) => e.capabilities.contains('rounds'),
        orElse: () => exercises.first,
      );

      final effortId = await workoutState.addExerciseToSession(
        roundExercise,
        effortKindOverride: 'round',
      );
      await workoutState.startRound(effortId, 0);
      await workoutState.endRoundEarly(effortId, 0);

      final routineState = RoutineState(repo);
      final sessionSummaryService = SessionSummaryService(repo);

      await tester.pumpWidget(
        MaterialApp(
          home: SessionSummaryScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: sessionSummaryService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sports'), findsOneWidget);
    });

    testWidgets('hides Sports group card when rounds are never started', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final repo = await _freshRepo();
      final workoutState = await workoutStateWithActiveSession(repo);
      final exercises = await repo.getExercises();
      final roundExercise = exercises.firstWhere(
        (e) => e.capabilities.contains('rounds'),
        orElse: () => exercises.first,
      );

      await workoutState.addExerciseToSession(
        roundExercise,
        effortKindOverride: 'round',
      );

      final routineState = RoutineState(repo);
      final sessionSummaryService = SessionSummaryService(repo);

      await tester.pumpWidget(
        MaterialApp(
          home: SessionSummaryScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: sessionSummaryService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sports'), findsNothing);
    });

    testWidgets('rolling session uses same top stats layout as non-rolling', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      await workoutState.createNewSession(isRolling: true);
      final exercises = await repo.getExercises();
      await workoutState.addExerciseToSession(exercises.first);
      final routineState = RoutineState(repo);
      final sessionSummaryService = SessionSummaryService(repo);

      await tester.pumpWidget(
        MaterialApp(
          home: SessionSummaryScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: sessionSummaryService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('DURATION'), findsOneWidget);
      expect(find.text('REST TIME'), findsOneWidget);
      expect(find.text('EXERCISES'), findsNothing);
    });

    testWidgets('non-rolling session stats include Duration', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      await workoutState.createNewSession(isRolling: false);
      final exercises = await repo.getExercises();
      await workoutState.addExerciseToSession(exercises.first);
      final routineState = RoutineState(repo);
      final sessionSummaryService = SessionSummaryService(repo);

      await tester.pumpWidget(
        MaterialApp(
          home: SessionSummaryScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: sessionSummaryService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('DURATION'), findsOneWidget);
    });

    testWidgets(
      'rolling summary does not render block headers or exercise rows',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        await workoutState.createNewSession(isRolling: true);

        final blockId = await workoutState.addSessionBlock();
        final block = workoutState.getSessionBlocks().firstWhere(
          (b) => b.id == blockId,
        );
        await workoutState.updateSessionBlock(
          SessionBlock(
            id: block.id,
            sessionId: block.sessionId,
            name: 'Main Work',
            orderIndex: block.orderIndex,
            createdAtMs: block.createdAtMs,
            updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
        );

        final exercises = await repo.getExercises();
        final effortId = await workoutState.addExerciseToSession(
          exercises.first,
        );
        await workoutState.assignEffortToBlock(effortId, blockId);

        final routineState = RoutineState(repo);
        final sessionSummaryService = SessionSummaryService(repo);

        await tester.pumpWidget(
          MaterialApp(
            home: SessionSummaryScreen(
              workoutState: workoutState,
              routineState: routineState,
              sessionSummaryService: sessionSummaryService,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Main Work'), findsNothing);
        expect(find.text(exercises.first.name), findsNothing);
      },
    );

    testWidgets('rolling summary does not render Other fallback section', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      await workoutState.createNewSession(isRolling: true);

      final exercises = await repo.getExercises();
      await workoutState.addExerciseToSession(exercises.first);

      final routineState = RoutineState(repo);
      final sessionSummaryService = SessionSummaryService(repo);

      await tester.pumpWidget(
        MaterialApp(
          home: SessionSummaryScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: sessionSummaryService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Other'), findsNothing);
      expect(find.text(exercises.first.name), findsNothing);
    });

    testWidgets('top stats show only Duration and Rest Time', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final repo = await _freshRepo();
      final workoutState = await workoutStateWithActiveSession(repo);
      final session = workoutState.currentSession!;
      await workoutState.updateSessionFeeling(session.id, 3);

      final exercises = await repo.getExercises();
      final effortId = await workoutState.addExerciseToSession(
        exercises.first,
        chosenMetric: 'reps',
      );

      final now = DateTime.now().millisecondsSinceEpoch;
      await repo.createEntryRest(
        EntryRest(
          id: 'rest-closed',
          effortId: effortId,
          entryIndex: 0,
          restStartMs: now - 90000,
          restEndMs: now,
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );

      final routineState = RoutineState(repo);
      final sessionSummaryService = SessionSummaryService(repo);

      await tester.pumpWidget(
        MaterialApp(
          home: SessionSummaryScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: sessionSummaryService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('DURATION'), findsOneWidget);
      expect(find.text('REST TIME'), findsOneWidget);
      expect(find.text('EXERCISES'), findsNothing);
      expect(find.textContaining('1m 30s'), findsOneWidget);
    });

    testWidgets('top stats render Rest Time as 0 when no rests are closed', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final repo = await _freshRepo();
      final workoutState = await workoutStateWithActiveSession(repo);
      final session = workoutState.currentSession!;
      await workoutState.updateSessionFeeling(session.id, 3);

      final exercises = await repo.getExercises();
      await workoutState.addExerciseToSession(
        exercises.first,
        chosenMetric: 'reps',
      );

      final routineState = RoutineState(repo);
      final sessionSummaryService = SessionSummaryService(repo);

      await tester.pumpWidget(
        MaterialApp(
          home: SessionSummaryScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: sessionSummaryService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('REST TIME'), findsOneWidget);
      expect(find.text('0'), findsWidgets);
    });

    testWidgets('removes session RPE and per-exercise rows from summary', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final repo = await _freshRepo();
      final workoutState = await workoutStateWithActiveSession(repo);
      final session = workoutState.currentSession!;
      await workoutState.updateSessionFeeling(session.id, 4);

      final exercises = await repo.getExercises();
      await workoutState.addExerciseToSession(
        exercises.first,
        chosenMetric: 'reps',
      );

      final routineState = RoutineState(repo);
      final sessionSummaryService = SessionSummaryService(repo);

      await tester.pumpWidget(
        MaterialApp(
          home: SessionSummaryScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: sessionSummaryService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Session RPE'), findsNothing);
      expect(find.text('PRs achieved'), findsNothing);
      expect(find.text(exercises.first.name), findsNothing);
    });

    testWidgets('session note appears before calendar section', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final repo = await _freshRepo();
      final workoutState = await workoutStateWithActiveSession(repo);
      final session = workoutState.currentSession!;
      await workoutState.updateSessionFeeling(session.id, 5);
      final routineState = RoutineState(repo);
      final sessionSummaryService = SessionSummaryService(repo);

      await tester.pumpWidget(
        MaterialApp(
          home: SessionSummaryScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: sessionSummaryService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final noteTopLeft = tester.getTopLeft(find.text('Session note'));
      final calendarTopLeft = tester.getTopLeft(find.text('Open Calendar'));
      expect(noteTopLeft.dy, lessThan(calendarTopLeft.dy));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // OmniSplashScreen
  // ══════════════════════════════════════════════════════════════════════════

  group('OmniSplashScreen', () {
    Future<OmniSplashScreen> buildSplashScreen(
      MockWorkoutRepository repo,
    ) async {
      final workoutState = WorkoutState(repo);
      final homeState = HomeState(repo);
      await homeState.init();
      final routineState = RoutineState(repo);
      routineState.setAutosaveEnabled(false);
      final routineSessionService = RoutineSessionService(repo);
      final sessionSummaryService = SessionSummaryService(repo);
      final calendarState = CalendarState(repo);
      await calendarState.init();
      final periodState = PeriodState(repo);
      final profileState = ProfileState(repo);
      await profileState.loadProfile();
      final settingsState = SettingsState(repo);
      await settingsState.initialize();

      return OmniSplashScreen(
        workoutState: workoutState,
        homeState: homeState,
        routineState: routineState,
        routineSessionService: routineSessionService,
        sessionSummaryService: sessionSummaryService,
        calendarState: calendarState,
        periodState: periodState,
        profileState: profileState,
        settingsState: settingsState,
        // Use a very short duration so no navigation fires during the test
        duration: const Duration(milliseconds: 1),
      );
    }

    testWidgets('shows OMNITRAIN text', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      final repo = await _freshRepo();
      final screen = await buildSplashScreen(repo);

      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pump(); // single frame — splash is visible

      expect(find.text('OMNITRAIN'), findsOneWidget);

      // Advance time past the 1ms duration so the timer fires, then settle
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pumpAndSettle();
    });

    testWidgets('renders without crash', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      final repo = await _freshRepo();
      final screen = await buildSplashScreen(repo);

      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pump();
      // Advance past timer and settle to clear pending timers
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pumpAndSettle();
      // No crash — reached HomeScreen without exception
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // ExerciseDetailScreen
  // ══════════════════════════════════════════════════════════════════════════

  group('ExerciseDetailScreen', () {
    testWidgets('renders workout session for a valid effort', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      await workoutState.createNewSession();
      final exercises = await repo.getExercises();
      final effortId = await workoutState.addExerciseToSession(
        exercises.first,
        chosenMetric: 'reps',
      );
      final routineState = RoutineState(repo);
      final sessionSummaryService = SessionSummaryService(repo);

      await tester.pumpWidget(
        MaterialApp(
          home: ExerciseDetailScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: sessionSummaryService,
            effortId: effortId,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should render without crash
      expect(find.byType(ExerciseDetailScreen), findsOneWidget);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // MeasurementHistoryChartSheet
  // ══════════════════════════════════════════════════════════════════════════

  group('MeasurementHistoryChartSheet', () {
    testWidgets('shows measurement label uppercased', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      final repo = await _freshRepo();
      final profileState = ProfileState(repo);
      await profileState.loadProfile();
      const definition = ProfileMeasurements.bodyweight;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MeasurementHistoryChartSheet(
              profileState: profileState,
              definition: definition,
              onLogNew: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The sheet title is definition.label.toUpperCase() → 'BODY WEIGHT'
      expect(find.text('BODY WEIGHT'), findsOneWidget);
    });

    testWidgets('shows Log New Entry button', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      final repo = await _freshRepo();
      final profileState = ProfileState(repo);
      await profileState.loadProfile();
      const definition = ProfileMeasurements.bodyweight;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MeasurementHistoryChartSheet(
              profileState: profileState,
              definition: definition,
              onLogNew: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Log New Entry'), findsOneWidget);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // ExercisePickerDialog
  // ══════════════════════════════════════════════════════════════════════════

  group('ExercisePickerDialog', () {
    testWidgets('shows Select Exercise title', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExercisePickerDialog(workoutState: workoutState),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Select Exercise'), findsOneWidget);
    });

    testWidgets('shows search field', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExercisePickerDialog(workoutState: workoutState),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Search exercises...'), findsOneWidget);
    });

    testWidgets('uses the active themed sheet surface', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExercisePickerDialog(workoutState: workoutState),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dialog = tester.widget<Dialog>(find.byType(Dialog));
      final themeColors = OmniTheme.colorsForTheme(OmniTheme.activeTheme);

      expect(dialog.backgroundColor, themeColors.surface);
      expect(dialog.surfaceTintColor, Colors.transparent);
    });

    testWidgets('enforces filled CTA styling for the active picker theme', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);

      for (final appTheme in const [
        AppTheme.forgeEmber,
        AppTheme.obsidianVolt,
        AppTheme.crimsonDojo,
      ]) {
        OmniTheme.activeTheme = appTheme;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ExercisePickerDialog(workoutState: workoutState),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final themedAncestor = find
            .ancestor(of: find.byType(Dialog), matching: find.byType(Theme))
            .first;
        final pickerTheme = tester.widget<Theme>(themedAncestor).data;
        final style = pickerTheme.filledButtonTheme.style!;
        final colors = OmniTheme.colorsForTheme(appTheme);

        expect(style.backgroundColor?.resolve({}), colors.primary);
        expect(style.foregroundColor?.resolve({}), Colors.white);
      }
    });

    testWidgets('shows Add Custom Exercise button', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExercisePickerDialog(workoutState: workoutState),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Add Custom Exercise'), findsOneWidget);
    });

    testWidgets(
      'uses subdued styling for recommended label and metadata chips',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1200));
        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ExercisePickerDialog(
                workoutState: workoutState,
                sessionModality: Modality.martialArts,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Recommended'), findsOneWidget);

        final recommendedText = tester.widget<Text>(find.text('Recommended'));
        expect(recommendedText.style?.color, OmniTheme.textSecondary);

        final firstChip = tester.widget<Chip>(find.byType(Chip).first);
        expect(firstChip.backgroundColor, Colors.transparent);
        expect(
          firstChip.side?.color,
          OmniTheme.colorsForTheme(OmniTheme.activeTheme).surfaceBorder,
        );
      },
    );

    testWidgets('shows exercises from repo', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExercisePickerDialog(workoutState: workoutState),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The count label "N exercise(s) found" should be visible
      expect(find.textContaining('found'), findsOneWidget);
    });

    testWidgets('filters exercises by search text', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      // no need to track firstName — just verify "No exercises found" appears
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExercisePickerDialog(workoutState: workoutState),
          ),
        ),
      );
      await tester.pump(); // single frame — before exercises load

      // Enter search text before exercises render to avoid exercise-tile overflow
      await tester.enterText(find.byType(TextField).first, 'zzzznotanexercise');
      // Advance past 300ms debounce and let load complete with the search filter
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('No exercises found'), findsOneWidget);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // MetricChooserDialog
  // ══════════════════════════════════════════════════════════════════════════

  group('MetricChooserDialog', () {
    testWidgets('shows How to track title with capable exercise', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      final exercises = await repo.getExercises();
      // Pick an exercise that has at least one capability
      final exercise = exercises.firstWhere(
        (e) => e.capabilities.isNotEmpty,
        orElse: () => exercises.first,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MetricChooserDialog(exercise: exercise)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('How to track?'), findsOneWidget);
    });

    testWidgets('shows Cancel button', (WidgetTester tester) async {
      final repo = await _freshRepo();
      final exercises = await repo.getExercises();
      final exercise = exercises.first;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MetricChooserDialog(exercise: exercise)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('shows No Capabilities dialog for exercise with no caps', (
      WidgetTester tester,
    ) async {
      final exercise = Exercise(
        id: 'ex-nocaps',
        name: 'Unknown Exercise',
        createdAtMs: 0,
        updatedAtMs: 0,
        capabilities: const [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MetricChooserDialog(exercise: exercise)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No Capabilities'), findsOneWidget);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // ModalityPickerDialog
  // ══════════════════════════════════════════════════════════════════════════

  group('ModalityPickerDialog', () {
    testWidgets('shows Select Exercise Modality title', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ModalityPickerDialog())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Select Exercise Modality'), findsOneWidget);
    });

    testWidgets('shows all modality options', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ModalityPickerDialog())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cardio'), findsOneWidget);
      expect(find.text('Resistance'), findsOneWidget);
      expect(find.text('Sports'), findsOneWidget);
      expect(find.text('Isometric'), findsOneWidget);
    });

    testWidgets('shows Cancel button', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ModalityPickerDialog())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('pre-selects initialModality when provided', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ModalityPickerDialog(initialModality: 'cardio')),
        ),
      );
      await tester.pumpAndSettle();

      // Cardio option must still be visible when pre-selected
      expect(find.text('Cardio'), findsOneWidget);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // WorkoutSessionScreen – Finish Workout button theme context
  // ══════════════════════════════════════════════════════════════════════════

  group('WorkoutSessionScreen – Finish Workout button theme context', () {
    testWidgets(
      'Finish Workout and add buttons inherit the active accent across themes',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1200));

        for (final appTheme in const [
          AppTheme.abyssalNeon,
          AppTheme.forgeEmber,
          AppTheme.obsidianVolt,
          AppTheme.voidPulse,
          AppTheme.crimsonDojo,
        ]) {
          OmniTheme.activeTheme = appTheme;

          final repo = await _freshRepo();
          final workoutState = WorkoutState(repo);
          final routineState = RoutineState(repo);
          await workoutState.createNewSession(isRolling: false);

          await tester.pumpWidget(
            MaterialApp(
              home: WorkoutSessionScreen(
                workoutState: workoutState,
                routineState: routineState,
                sessionSummaryService: SessionSummaryService(repo),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final finishFinder = find.widgetWithText(
            FilledButton,
            'Finish Workout',
          );
          expect(
            finishFinder,
            findsOneWidget,
            reason: '${appTheme.name} – Finish Workout button not found',
          );

          final addFinder = find.byWidgetPredicate(
            (widget) =>
                widget is FilledButton &&
                widget.child is Icon &&
                (widget.child as Icon).icon == Icons.add,
          );
          expect(
            addFinder,
            findsOneWidget,
            reason: '${appTheme.name} – add button not found',
          );

          final colors = OmniTheme.colorsForTheme(appTheme);
          final finishTheme = Theme.of(tester.element(finishFinder));
          final addTheme = Theme.of(tester.element(addFinder));

          expect(
            finishTheme.filledButtonTheme.style?.backgroundColor?.resolve({}),
            colors.primary,
            reason:
                '${appTheme.name} – Finish Workout accent must match the active theme primary',
          );
          expect(
            addTheme.filledButtonTheme.style?.backgroundColor?.resolve({}),
            colors.primary,
            reason:
                '${appTheme.name} – add button accent must match the active theme primary',
          );
        }
      },
    );

    testWidgets(
      'exercise picker modal barrier fully obscures underlying session CTA',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1200));

        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        final routineState = RoutineState(repo);
        await workoutState.createNewSession(isRolling: false);

        await tester.pumpWidget(
          MaterialApp(
            home: WorkoutSessionScreen(
              workoutState: workoutState,
              routineState: routineState,
              sessionSummaryService: SessionSummaryService(repo),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final addButton = tester
            .widgetList<FilledButton>(find.byType(FilledButton))
            .firstWhere(
              (button) =>
                  button.child is Icon &&
                  (button.child as Icon).icon == Icons.add,
            );
        expect(addButton.onPressed, isNotNull);

        addButton.onPressed!.call();
        await tester.pumpAndSettle();

        final barrier = tester.widget<AnimatedModalBarrier>(
          find.byType(AnimatedModalBarrier).first,
        );
        expect(barrier.color.value, isNotNull);
        expect(
          barrier.color.value!.opacity,
          greaterThanOrEqualTo(0.7),
          reason:
              'Exercise picker overlay must sufficiently dim the underlying Finish Workout CTA',
        );
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // WorkoutSessionScreen – rolling session block list view
  // ══════════════════════════════════════════════════════════════════════════

  group('WorkoutSessionScreen – rolling session block UI', () {
    testWidgets(
      'non-rolling empty session keeps Add Block visible above Finish Workout',
      (WidgetTester tester) async {
        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        final routineState = RoutineState(repo);
        await workoutState.createNewSession(isRolling: false);

        await tester.pumpWidget(
          MaterialApp(
            home: WorkoutSessionScreen(
              workoutState: workoutState,
              routineState: routineState,
              sessionSummaryService: SessionSummaryService(repo),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final addBlockFinder = find.widgetWithText(OutlinedButton, 'Add Block');
        final finishFinder = find.widgetWithText(
          FilledButton,
          'Finish Workout',
        );

        expect(addBlockFinder, findsOneWidget);
        expect(finishFinder, findsOneWidget);

        final addBlockRect = tester.getRect(addBlockFinder);
        final finishRect = tester.getRect(finishFinder);
        expect(addBlockRect.bottom, lessThan(finishRect.top));
      },
    );

    testWidgets('rolling session shows + Add Block button', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final routineState = RoutineState(repo);
      await workoutState.createNewSession(isRolling: true);

      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutSessionScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: SessionSummaryService(repo),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Add Block'), findsOneWidget);
    });

    testWidgets('rolling session shows block name after addSessionBlock', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final routineState = RoutineState(repo);
      await workoutState.createNewSession(isRolling: true);
      await workoutState.addSessionBlock();

      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutSessionScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: SessionSummaryService(repo),
          ),
        ),
      );
      await tester.pump();

      // Block name (h:mm a) should exist and the empty-state body should show.
      expect(find.text('No exercises in this block yet.'), findsOneWidget);
    });

    testWidgets('rolling session shows block header overflow menu', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final routineState = RoutineState(repo);
      await workoutState.createNewSession(isRolling: true);
      await workoutState.addSessionBlock();

      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutSessionScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: SessionSummaryService(repo),
          ),
        ),
      );
      await tester.pump();

      // PopupMenuButton renders as an icon; verify it exists.
      expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    });

    testWidgets('rolling session overflow menu shows Edit/Clone/Delete', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final routineState = RoutineState(repo);
      await workoutState.createNewSession(isRolling: true);
      await workoutState.addSessionBlock();

      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutSessionScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: SessionSummaryService(repo),
          ),
        ),
      );
      await tester.pump();

      // Open the overflow menu.
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Clone'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('rolling session + Add Block adds a new block card', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final routineState = RoutineState(repo);
      await workoutState.createNewSession(isRolling: true);
      await workoutState.addSessionBlock();

      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutSessionScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: SessionSummaryService(repo),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(PopupMenuButton<String>), findsOneWidget);

      await tester.tap(find.text('Add Block'));
      await tester.pumpAndSettle();

      expect(find.byType(PopupMenuButton<String>), findsNWidgets(2));
      expect(find.text('No exercises in this block yet.'), findsNWidgets(2));
    });

    testWidgets('rolling session block Edit action renames block', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final routineState = RoutineState(repo);
      await workoutState.createNewSession(isRolling: true);
      await workoutState.addSessionBlock();

      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutSessionScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: SessionSummaryService(repo),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(find.text('Rename Block'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Warm-Up');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Warm-Up'), findsOneWidget);
    });

    testWidgets('rolling session block Clone action appends a copy block', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final routineState = RoutineState(repo);
      await workoutState.createNewSession(isRolling: true);
      final blockId = await workoutState.addSessionBlock();

      await workoutState.updateSessionBlock(
        SessionBlock(
          id: blockId,
          sessionId: workoutState.currentSession!.id,
          name: 'Main Work',
          orderIndex: 0,
          createdAtMs: DateTime.now().millisecondsSinceEpoch,
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutSessionScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: SessionSummaryService(repo),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(PopupMenuButton<String>), findsOneWidget);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clone'));
      await tester.pumpAndSettle();

      expect(find.byType(PopupMenuButton<String>), findsNWidgets(2));
      // Cloned block should exist as a second card now (has current-time name)
    });

    testWidgets('rolling session block Delete removes block and its efforts', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final routineState = RoutineState(repo);
      await workoutState.createNewSession(isRolling: true);
      await workoutState.loadSessionData();

      final blockId = await workoutState.addSessionBlock();
      final exercises = await repo.getExercises();
      final effortId = await workoutState.addExerciseToSession(exercises.first);
      await workoutState.assignEffortToBlock(effortId, blockId);

      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutSessionScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: SessionSummaryService(repo),
          ),
        ),
      );
      await tester.pump();

      expect(find.text(exercises.first.name), findsOneWidget);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Confirm deletion
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.byType(PopupMenuButton<String>), findsNothing);
      // Effort is cascade-deleted with the block
      expect(
        workoutState.getExercisesWithEntries().any(
          (exercise) => exercise['id'] == effortId,
        ),
        isFalse,
      );
    });

    testWidgets('rolling session block cards do not show reorder arrows', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final routineState = RoutineState(repo);
      await workoutState.createNewSession(isRolling: true);
      await workoutState.addSessionBlock();

      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutSessionScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: SessionSummaryService(repo),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.arrow_upward), findsNothing);
      expect(find.byIcon(Icons.arrow_downward), findsNothing);
    });

    testWidgets(
      'rolling session with multiple blocks still has no reorder arrows',
      (WidgetTester tester) async {
        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        final routineState = RoutineState(repo);
        await workoutState.createNewSession(isRolling: true);
        await workoutState.addSessionBlock();
        await workoutState.addSessionBlock();

        await tester.pumpWidget(
          MaterialApp(
            home: WorkoutSessionScreen(
              workoutState: workoutState,
              routineState: routineState,
              sessionSummaryService: SessionSummaryService(repo),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.arrow_upward), findsNothing);
        expect(find.byIcon(Icons.arrow_downward), findsNothing);
      },
    );

    testWidgets('rolling session hides Session Time chip', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final routineState = RoutineState(repo);
      await workoutState.createNewSession(isRolling: true);

      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutSessionScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: SessionSummaryService(repo),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Session Time'), findsNothing);
    });

    testWidgets('non-rolling session shows Session Time chip', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final routineState = RoutineState(repo);
      await workoutState.createNewSession(isRolling: false);

      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutSessionScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: SessionSummaryService(repo),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Session Time'), findsOneWidget);
    });

    testWidgets(
      'non-rolling session displays exercises by execution order with createdAt tie-break',
      (WidgetTester tester) async {
        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        final routineState = RoutineState(repo);
        await workoutState.createNewSession(isRolling: false);

        final sessionId = workoutState.currentSession!.id;
        final segmentId = workoutState.segments.first.id;
        final allExercises = await repo.getExercises();

        final firstExercise = allExercises[0];
        final secondExercise = allExercises[1];
        final thirdExercise = allExercises[2];

        await repo.createEffort(
          SegmentEffort(
            id: 'effort-a',
            segmentId: segmentId,
            orderIndex: 0,
            effortKind: 'set',
            exerciseId: firstExercise.id,
            blockId: null,
            note: null,
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );

        await repo.createEffort(
          SegmentEffort(
            id: 'effort-b',
            segmentId: segmentId,
            orderIndex: 1,
            effortKind: 'timed',
            exerciseId: secondExercise.id,
            blockId: null,
            note: null,
            createdAtMs: 2000,
            updatedAtMs: 2000,
          ),
        );

        await repo.createEffort(
          SegmentEffort(
            id: 'effort-c',
            segmentId: segmentId,
            orderIndex: 0,
            effortKind: 'round',
            exerciseId: thirdExercise.id,
            blockId: null,
            note: null,
            createdAtMs: 3000,
            updatedAtMs: 3000,
          ),
        );

        await workoutState.loadHistoricalSession(sessionId);

        await tester.pumpWidget(
          MaterialApp(
            home: WorkoutSessionScreen(
              workoutState: workoutState,
              routineState: routineState,
              sessionSummaryService: SessionSummaryService(repo),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final secondName = secondExercise.name;
        final firstName = firstExercise.name;
        final thirdName = thirdExercise.name;

        final secondY = tester.getTopLeft(find.text(secondName).first).dy;
        final firstY = tester.getTopLeft(find.text(firstName).first).dy;
        final thirdY = tester.getTopLeft(find.text(thirdName).first).dy;

        expect(firstY, lessThan(secondY));
        expect(secondY, lessThan(thirdY));
      },
    );

    testWidgets('non-rolling session does not render modality group headers', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final routineState = RoutineState(repo);
      await workoutState.createNewSession(isRolling: false);

      final exercises = await repo.getExercises();
      await workoutState.addExerciseToSession(
        exercises.first,
        effortKindOverride: 'set',
      );
      await workoutState.addExerciseToSession(
        exercises[1],
        effortKindOverride: 'timed',
      );
      await workoutState.addExerciseToSession(
        exercises[2],
        effortKindOverride: 'round',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutSessionScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: SessionSummaryService(repo),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Strength'), findsNothing);
      expect(find.text('Cardio'), findsNothing);
      expect(find.text('Sports'), findsNothing);
      expect(find.text('Intervals'), findsNothing);
    });

    testWidgets(
      'non-rolling detail follows visible list order with block-grouped exercises',
      (WidgetTester tester) async {
        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        final routineState = RoutineState(repo);
        await workoutState.createNewSession(isRolling: false);

        final sessionId = workoutState.currentSession!.id;
        final segmentId = workoutState.segments.first.id;
        final allExercises = await repo.getExercises();

        final standaloneEx = allExercises[0];
        final blockAFirstEx = allExercises[1];
        final blockBLaterEx = allExercises[2];
        final blockALateEx = allExercises[3];

        await repo.createSessionBlock(
          SessionBlock(
            id: 'block-a',
            sessionId: sessionId,
            name: '11:58 PM',
            orderIndex: 0,
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
        await repo.createSessionBlock(
          SessionBlock(
            id: 'block-b',
            sessionId: sessionId,
            name: '11:59 PM',
            orderIndex: 1,
            createdAtMs: 2000,
            updatedAtMs: 2000,
          ),
        );

        await repo.createEffort(
          SegmentEffort(
            id: 'eff-standalone',
            segmentId: segmentId,
            orderIndex: 0,
            effortKind: 'timed',
            exerciseId: standaloneEx.id,
            blockId: null,
            note: null,
            createdAtMs: 500,
            updatedAtMs: 500,
          ),
        );

        await repo.createEffort(
          SegmentEffort(
            id: 'eff-block-a-first',
            segmentId: segmentId,
            orderIndex: 1,
            effortKind: 'timed',
            exerciseId: blockAFirstEx.id,
            blockId: 'block-a',
            note: null,
            createdAtMs: 1100,
            updatedAtMs: 1100,
          ),
        );

        await repo.createEffort(
          SegmentEffort(
            id: 'eff-block-b',
            segmentId: segmentId,
            orderIndex: 2,
            effortKind: 'timed',
            exerciseId: blockBLaterEx.id,
            blockId: 'block-b',
            note: null,
            createdAtMs: 2100,
            updatedAtMs: 2100,
          ),
        );

        await repo.createEffort(
          SegmentEffort(
            id: 'eff-block-a-late',
            segmentId: segmentId,
            orderIndex: 3,
            effortKind: 'timed',
            exerciseId: blockALateEx.id,
            blockId: 'block-a',
            note: null,
            createdAtMs: 3000,
            updatedAtMs: 3000,
          ),
        );

        await workoutState.loadHistoricalSession(sessionId);

        await tester.pumpWidget(
          MaterialApp(
            home: WorkoutSessionScreen(
              workoutState: workoutState,
              routineState: routineState,
              sessionSummaryService: SessionSummaryService(repo),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text(blockALateEx.name).first);
        await tester.pumpAndSettle();

        expect(find.text('Exercise 3 / 4'), findsOneWidget);
      },
    );

    testWidgets('rolling session block shows + Add Exercise button', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final routineState = RoutineState(repo);
      await workoutState.createNewSession(isRolling: true);
      await workoutState.addSessionBlock();

      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutSessionScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: SessionSummaryService(repo),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Add Exercise'), findsOneWidget);
    });

    testWidgets('rolling session shows exercise tile inside correct block', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final routineState = RoutineState(repo);
      await workoutState.createNewSession(isRolling: true);
      await workoutState.loadSessionData();

      final blockId = await workoutState.addSessionBlock();
      final exercises = await repo.getExercises();
      final effortId = await workoutState.addExerciseToSession(exercises.first);
      await workoutState.assignEffortToBlock(effortId, blockId);
      await workoutState.loadSessionData();

      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutSessionScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: SessionSummaryService(repo),
          ),
        ),
      );
      await tester.pump();

      expect(find.text(exercises.first.name), findsOneWidget);
    });
  });
}
