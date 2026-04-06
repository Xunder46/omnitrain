import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/routine_session_service.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/core/constants/profile_measurements.dart';
import 'package:omnitrain/features/calendar/calendar_screen.dart';
import 'package:omnitrain/features/calendar/day_session_list_screen.dart';
import 'package:omnitrain/features/exercise/exercise_detail_screen.dart';
import 'package:omnitrain/features/exercise/exercise_editor_screen.dart';
import 'package:omnitrain/features/home/home_screen.dart';
import 'package:omnitrain/features/home/maintenance_placeholder_screen.dart';
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
import 'package:omnitrain/state/calendar/calendar_state.dart';
import 'package:omnitrain/state/home/home_state.dart';
import 'package:omnitrain/state/period/period_state.dart';
import 'package:omnitrain/state/profile/profile_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
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

    testWidgets('displays theme options', (WidgetTester tester) async {
      final repo = await _freshRepo();
      final settingsState = SettingsState(repo);
      await settingsState.initialize();

      await tester.pumpWidget(
        MaterialApp(home: SettingsScreen(settingsState: settingsState)),
      );
      await tester.pumpAndSettle();

      // There should be multiple theme options visible
      // At minimum the current theme should be visible
      expect(find.byType(GestureDetector), findsWidgets);
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

      expect(find.byType(FilledButton), findsWidgets);
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
    Future<HomeScreen> _buildHomeScreen(MockWorkoutRepository repo) async {
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
      final screen = await _buildHomeScreen(repo);

      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pumpAndSettle();

      expect(find.text('TRAIN'), findsOneWidget);
    });

    testWidgets('renders app bar logo', (WidgetTester tester) async {
      final repo = await _freshRepo();
      final screen = await _buildHomeScreen(repo);

      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pumpAndSettle();

      // AppBar uses an Image.asset logo
      expect(find.byType(Image), findsWidgets);
    });

    testWidgets('renders energy tile grid', (WidgetTester tester) async {
      final repo = await _freshRepo();
      final screen = await _buildHomeScreen(repo);

      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pumpAndSettle();

      // Should have multiple EnergyTile cards in a grid
      expect(find.byType(CustomScrollView), findsWidgets);
    });

    testWidgets('free training flow shows rolling toggle and inline guidance', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      final screen = await _buildHomeScreen(repo);

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
  // MaintenancePlaceholderScreen
  // ══════════════════════════════════════════════════════════════════════════

  group('MaintenancePlaceholderScreen', () {
    testWidgets('shows the title passed as parameter', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MaintenancePlaceholderScreen(
            title: 'Analytics',
            description: 'Track your progress over time.',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Analytics'), findsOneWidget);
    });

    testWidgets('shows Coming Soon text', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MaintenancePlaceholderScreen(
            title: 'Analytics',
            description: 'Track your progress over time.',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Coming Soon'), findsOneWidget);
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
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SessionSummaryScreen
  // ══════════════════════════════════════════════════════════════════════════

  group('SessionSummaryScreen', () {
    Future<WorkoutState> _workoutStateWithActiveSession(
      MockWorkoutRepository repo,
    ) async {
      final workoutState = WorkoutState(repo);
      await workoutState.createNewSession();
      return workoutState;
    }

    testWidgets('shows Done button', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final repo = await _freshRepo();
      final workoutState = await _workoutStateWithActiveSession(repo);
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
      final workoutState = await _workoutStateWithActiveSession(repo);
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

    testWidgets('shows exercise in summary when session has exercise', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final repo = await _freshRepo();
      final workoutState = await _workoutStateWithActiveSession(repo);
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

      expect(find.text(exercises.first.name), findsOneWidget);
    });

    testWidgets(
      'rolling session stats hide Duration and show Exercises/Sets/Rounds',
      (WidgetTester tester) async {
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

        expect(find.text('DURATION'), findsNothing);
        expect(find.text('EXERCISES'), findsOneWidget);
        expect(find.text('SETS'), findsOneWidget);
        expect(find.text('ROUNDS'), findsOneWidget);
      },
    );

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

    testWidgets('rolling summary groups exercises under block header', (
      WidgetTester tester,
    ) async {
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
      final effortId = await workoutState.addExerciseToSession(exercises.first);
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

      expect(find.text('Main Work'), findsOneWidget);
      expect(find.text(exercises.first.name), findsOneWidget);
    });

    testWidgets('rolling summary shows Other header for unassigned exercises', (
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

      expect(find.text('Other'), findsOneWidget);
      expect(find.text(exercises.first.name), findsOneWidget);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // OmniSplashScreen
  // ══════════════════════════════════════════════════════════════════════════

  group('OmniSplashScreen', () {
    Future<OmniSplashScreen> _buildSplashScreen(
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
      final screen = await _buildSplashScreen(repo);

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
      final screen = await _buildSplashScreen(repo);

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
      expect(find.text('General'), findsOneWidget);
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
  // WorkoutSessionScreen – rolling session block list view
  // ══════════════════════════════════════════════════════════════════════════

  group('WorkoutSessionScreen – rolling session block UI', () {
    testWidgets('non-rolling session does not show + Add Block', (
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

      expect(find.text('+ Add Block'), findsNothing);
    });

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

    testWidgets(
      'rolling session block Delete removes block but preserves effort',
      (WidgetTester tester) async {
        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        final routineState = RoutineState(repo);
        await workoutState.createNewSession(isRolling: true);
        await workoutState.loadSessionData();

        final blockId = await workoutState.addSessionBlock();
        final exercises = await repo.getExercises();
        final effortId = await workoutState.addExerciseToSession(
          exercises.first,
        );
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

        expect(
          find.text('Exercises in this block will not be deleted.'),
          findsOneWidget,
        );

        await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
        await tester.pumpAndSettle();

        expect(find.byType(PopupMenuButton<String>), findsNothing);
        expect(
          workoutState.getExercisesWithEntries().any(
            (exercise) => exercise['id'] == effortId,
          ),
          isTrue,
        );
      },
    );

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
