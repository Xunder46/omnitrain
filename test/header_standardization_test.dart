// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/core/services/routine_session_service.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/calendar/calendar_screen.dart';
import 'package:omnitrain/features/calendar/day_session_list_screen.dart';
import 'package:omnitrain/features/exercise/exercise_editor_screen.dart';
import 'package:omnitrain/features/period/create_period_screen.dart';
import 'package:omnitrain/features/period/period_list_screen.dart';
import 'package:omnitrain/features/profile/profile_screen.dart';
import 'package:omnitrain/features/routine/my_routines_screen.dart';
import 'package:omnitrain/features/routine/routine_setup_screen.dart';
import 'package:omnitrain/features/session/session_overview_screen.dart';
import 'package:omnitrain/features/session/session_summary_screen.dart';
import 'package:omnitrain/features/settings/settings_screen.dart';
import 'package:omnitrain/features/stats/stats_screen.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';
import 'package:omnitrain/state/period/period_state.dart';
import 'package:omnitrain/state/profile/profile_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/layout/omni_back_header.dart';

import 'helpers/fake_timer_alert_service.dart';

// ── Helpers ──────────────────────────────────────────────────────────────

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

// ══════════════════════════════════════════════════════════════════════════
// OmniBackHeader unit tests
// ══════════════════════════════════════════════════════════════════════════

void main() {
  group('OmniBackHeader – unit', () {
    testWidgets('renders back arrow and title', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OmniBackHeader(title: 'Test Title'),
          ),
        ),
      );

      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(find.text('Test Title'), findsOneWidget);
    });

    testWidgets('renders subtitle when provided', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OmniBackHeader(title: 'Main', subtitle: 'Sub'),
          ),
        ),
      );

      expect(find.text('Main'), findsOneWidget);
      expect(find.text('Sub'), findsOneWidget);
    });

    testWidgets('does not render subtitle column when subtitle is null', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: OmniBackHeader(title: 'Only Title')),
        ),
      );

      // Column widget exists inside AppBar leading area, but no subtitle text.
      expect(find.text('Only Title'), findsOneWidget);
      // No extra text node beyond the title.
      expect(
        find.descendant(
          of: find.byType(OmniBackHeader),
          matching: find.byType(Column),
        ),
        findsNothing,
      );
    });

    testWidgets('custom onBack is called when back arrow tapped', (
      WidgetTester tester,
    ) async {
      bool called = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OmniBackHeader(
              title: 'Back Test',
              onBack: () => called = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pump();

      expect(called, isTrue);
    });

    testWidgets('default onBack pops navigator when no callback provided', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Navigator(
            onGenerateRoute: (settings) => MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: const OmniBackHeader(title: 'Page 1'),
                body: Builder(
                  builder: (context) => TextButton(
                    child: const Text('Push'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const Scaffold(
                          appBar: OmniBackHeader(title: 'Page 2'),
                          body: SizedBox(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Push'));
      await tester.pumpAndSettle();

      expect(find.text('Page 2'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.text('Page 1'), findsOneWidget);
      expect(find.text('Page 2'), findsNothing);
    });

    testWidgets('title uses w600 weight and correct letter spacing', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: const OmniBackHeader(title: 'Style Check'),
            body: const SizedBox(),
          ),
        ),
      );

      // Find the Text that exactly says 'Style Check' inside the AppBar.
      final textWidget = tester.widget<Text>(
        find
            .descendant(
              of: find.byType(OmniBackHeader),
              matching: find.text('Style Check'),
            )
            .first,
      );

      // titleTextStyle is set on AppBar and inherited by the Text. The Text
      // itself carries no explicit style — the inherited style applies.
      // We verify via the AppBar's titleTextStyle instead.
      final appBar = tester.widget<AppBar>(
        find.descendant(
          of: find.byType(OmniBackHeader),
          matching: find.byType(AppBar),
        ),
      );

      final style = appBar.titleTextStyle!;
      expect(style.fontWeight, FontWeight.w600);
      expect(style.letterSpacing, OmniTheme.titleLetterSpacing);
      expect(style.color, OmniTheme.colors.textDominant);
      expect(textWidget, isNotNull);
    });

    testWidgets('back arrow icon color is OmniTheme.colors.textDominant', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: const OmniBackHeader(title: 'Arrow Color'),
            body: const SizedBox(),
          ),
        ),
      );

      final iconButton = tester.widget<IconButton>(
        find.descendant(
          of: find.byType(OmniBackHeader),
          matching: find.byType(IconButton),
        ),
      );
      expect(iconButton.color, OmniTheme.colors.textDominant);
    });

    testWidgets('actions are forwarded to AppBar', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: OmniBackHeader(
              title: 'With Actions',
              actions: [
                TextButton(onPressed: () {}, child: const Text('Action!')),
              ],
            ),
            body: const SizedBox(),
          ),
        ),
      );

      expect(find.text('Action!'), findsOneWidget);
    });

    testWidgets('preferredSize equals kToolbarHeight', (
      WidgetTester tester,
    ) async {
      const header = OmniBackHeader(title: 'Size Test');
      expect(header.preferredSize.height, kToolbarHeight);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Per-screen OmniBackHeader presence tests
  // ══════════════════════════════════════════════════════════════════════════

  group('OmniBackHeader presence – CalendarScreen', () {
    testWidgets('uses OmniBackHeader', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      final repo = await _freshRepo();
      final calendarState = CalendarState(repo);
      await calendarState.init();

      await tester.pumpWidget(
        MaterialApp(
          home: CalendarScreen(
            calendarState: calendarState,
            periodState: PeriodState(repo),
            workoutState: WorkoutState(repo),
            routineState: RoutineState(repo),
            routineSessionService: RoutineSessionService(repo),
            sessionSummaryService: SessionSummaryService(repo),
            settingsState: SettingsState(repo),
            timerAlertService: FakeTimerAlertService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OmniBackHeader), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('Periods (+) button is present in header actions', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      final repo = await _freshRepo();
      final calendarState = CalendarState(repo);
      await calendarState.init();

      await tester.pumpWidget(
        MaterialApp(
          home: CalendarScreen(
            calendarState: calendarState,
            periodState: PeriodState(repo),
            workoutState: WorkoutState(repo),
            routineState: RoutineState(repo),
            routineSessionService: RoutineSessionService(repo),
            sessionSummaryService: SessionSummaryService(repo),
            settingsState: SettingsState(repo),
            timerAlertService: FakeTimerAlertService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The '+' FilledButton must be a descendant of OmniBackHeader.
      expect(
        find.descendant(
          of: find.byType(OmniBackHeader),
          matching: find.widgetWithText(FilledButton, '+'),
        ),
        findsOneWidget,
      );
    });
  });

  group('OmniBackHeader presence – DaySessionListScreen', () {
    testWidgets('uses OmniBackHeader', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      final repo = await _freshRepo();
      final calendarState = CalendarState(repo);
      await calendarState.init();

      await tester.pumpWidget(
        MaterialApp(
          home: DaySessionListScreen(
            date: DateTime(2020, 6, 15),
            calendarState: calendarState,
            routineState: RoutineState(repo),
            workoutState: WorkoutState(repo),
            routineSessionService: RoutineSessionService(repo),
            sessionSummaryService: SessionSummaryService(repo),
            settingsState: SettingsState(repo),
            timerAlertService: FakeTimerAlertService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OmniBackHeader), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });
  });

  group('OmniBackHeader presence – ExerciseEditorScreen', () {
    testWidgets('uses OmniBackHeader for new exercise', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final repo = await _freshRepo();

      await tester.pumpWidget(
        MaterialApp(
          home: ExerciseEditorScreen(workoutState: WorkoutState(repo)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OmniBackHeader), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(find.text('New Exercise'), findsOneWidget);
    });
  });

  group('OmniBackHeader presence – CreatePeriodScreen', () {
    testWidgets('uses OmniBackHeader in create mode', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();

      await tester.pumpWidget(
        MaterialApp(
          home: CreatePeriodScreen(periodState: PeriodState(repo)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OmniBackHeader), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });
  });

  group('OmniBackHeader presence – PeriodListScreen', () {
    testWidgets('uses OmniBackHeader', (WidgetTester tester) async {
      final repo = await _freshRepo();

      await tester.pumpWidget(
        MaterialApp(home: PeriodListScreen(periodState: PeriodState(repo))),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OmniBackHeader), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });
  });

  group('OmniBackHeader presence – ProfileScreen', () {
    testWidgets('uses OmniBackHeader', (WidgetTester tester) async {
      final repo = await _freshRepo();
      final profileState = ProfileState(repo);
      await profileState.loadProfile();

      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(
            profileState: profileState,
            settingsState: SettingsState(repo),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OmniBackHeader), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });
  });

  group('OmniBackHeader presence – MyRoutinesScreen', () {
    testWidgets('uses OmniBackHeader', (WidgetTester tester) async {
      final repo = await _freshRepo();

      await tester.pumpWidget(
        MaterialApp(
          home: MyRoutinesScreen(
            routineState: RoutineState(repo),
            routineSessionService: RoutineSessionService(repo),
            sessionSummaryService: SessionSummaryService(repo),
            settingsState: SettingsState(repo),
            timerAlertService: FakeTimerAlertService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OmniBackHeader), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });
  });

  group('OmniBackHeader presence – RoutineSetupScreen (list view)', () {
    testWidgets('uses OmniBackHeader', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final repo = await _freshRepo();
      final routineState = RoutineState(repo);
      routineState.setAutosaveEnabled(false);

      await tester.pumpWidget(
        MaterialApp(home: RoutineSetupScreen(routineState: routineState)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OmniBackHeader), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('list view subtitle shows exercise count', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final repo = await _freshRepo();
      final routineState = RoutineState(repo);
      routineState.setAutosaveEnabled(false);
      await routineState.createNewRoutine('Count Test');
      final exercises = await repo.getExercises();
      await routineState.addExerciseToRoutine(exercises.first, 'set');
      await routineState.saveRoutine();
      final templateId = routineState.currentTemplate!.id;

      await tester.pumpWidget(
        MaterialApp(
          home: RoutineSetupScreen(
            routineState: routineState,
            templateId: templateId,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 exercise'), findsOneWidget);
    });
  });

  group('OmniBackHeader presence – RoutineSetupScreen (detail view)', () {
    testWidgets('uses OmniBackHeader in detail view', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final routineState = RoutineState(repo);
      routineState.setAutosaveEnabled(false);

      final exercises = await repo.getExercises();
      await routineState.createNewRoutine('Detail Header Test');
      await routineState.addExerciseToRoutine(exercises.first, 'set');
      await routineState.saveRoutine();
      final templateId = routineState.currentTemplate!.id;

      await tester.pumpWidget(
        MaterialApp(
          home: RoutineSetupScreen(
            routineState: routineState,
            workoutState: workoutState,
            templateId: templateId,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap exercise card to enter detail view.
      await tester.tap(find.text(exercises.first.name));
      await tester.pumpAndSettle();

      expect(find.byType(OmniBackHeader), findsOneWidget);
      // In detail view, back arrow may also appear in body nav — allow multiple.
      expect(find.byIcon(Icons.arrow_back), findsWidgets);
    });
  });

  group('OmniBackHeader presence – SettingsScreen', () {
    testWidgets('uses OmniBackHeader', (WidgetTester tester) async {
      final repo = await _freshRepo();
      final settingsState = SettingsState(repo);
      await settingsState.initialize();

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            settingsState: settingsState,
            timerAlertService: FakeTimerAlertService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OmniBackHeader), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });
  });

  group('OmniBackHeader presence – StatsScreen', () {
    testWidgets('uses OmniBackHeader', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      final repo = await _freshRepo();
      final settingsState = SettingsState(repo);
      await settingsState.initialize();

      await tester.pumpWidget(
        MaterialApp(
          home: StatsScreen(
            workoutState: WorkoutState(repo),
            settingsState: settingsState,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OmniBackHeader), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });
  });

  group('OmniBackHeader presence – SessionOverviewScreen', () {
    testWidgets('uses OmniBackHeader with subtitle', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final settingsState = SettingsState(repo);
      await settingsState.initialize();

      await tester.pumpWidget(
        MaterialApp(
          home: SessionOverviewScreen(
            workoutState: workoutState,
            routineState: RoutineState(repo),
            sessionSummaryService: SessionSummaryService(repo),
            settingsState: settingsState,
            timerAlertService: FakeTimerAlertService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OmniBackHeader), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(find.text('Workout Session'), findsOneWidget);
    });
  });

  group('OmniBackHeader presence – SessionSummaryScreen', () {
    testWidgets('uses OmniBackHeader', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      await workoutState.createNewSession();

      await tester.pumpWidget(
        MaterialApp(
          home: SessionSummaryScreen(
            workoutState: workoutState,
            routineState: RoutineState(repo),
            sessionSummaryService: SessionSummaryService(repo),
            settingsState: SettingsState(repo),
            timerAlertService: FakeTimerAlertService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OmniBackHeader), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('PopupMenuButton is present inside OmniBackHeader', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      await workoutState.createNewSession();

      await tester.pumpWidget(
        MaterialApp(
          home: SessionSummaryScreen(
            workoutState: workoutState,
            routineState: RoutineState(repo),
            sessionSummaryService: SessionSummaryService(repo),
            settingsState: SettingsState(repo),
            timerAlertService: FakeTimerAlertService(),
          ),
        ),
      );
      // Dismiss the feeling modal first.
      await tester.pumpAndSettle();
      if (find.text('How did it feel?').evaluate().isNotEmpty) {
        final sheet = find.byType(BottomSheet);
        await tester.tap(
          find.descendant(of: sheet, matching: find.text('1')).first,
        );
        await tester.pumpAndSettle();
      }

      expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    });

    testWidgets('overflow menu items are accessible after tapping menu', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      await workoutState.createNewSession();

      await tester.pumpWidget(
        MaterialApp(
          home: SessionSummaryScreen(
            workoutState: workoutState,
            routineState: RoutineState(repo),
            sessionSummaryService: SessionSummaryService(repo),
            settingsState: SettingsState(repo),
            timerAlertService: FakeTimerAlertService(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Dismiss feeling modal.
      if (find.text('How did it feel?').evaluate().isNotEmpty) {
        final sheet = find.byType(BottomSheet);
        await tester.tap(
          find.descendant(of: sheet, matching: find.text('1')).first,
        );
        await tester.pumpAndSettle();
      }

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      expect(find.text('Edit Session'), findsOneWidget);
      expect(find.text('Save as Routine'), findsOneWidget);
      expect(find.text('Discard'), findsOneWidget);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Back navigation (generic)
  // ══════════════════════════════════════════════════════════════════════════

  group('OmniBackHeader back navigation', () {
    testWidgets('tapping back arrow pops the screen', (
      WidgetTester tester,
    ) async {
      bool popped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute(
              builder: (_) => Scaffold(
                body: Builder(
                  builder: (context) => ElevatedButton(
                    child: const Text('Push'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PopScope(
                          onPopInvokedWithResult: (didPop, _) {
                            if (didPop) popped = true;
                          },
                          child: const Scaffold(
                            appBar: OmniBackHeader(title: 'Second Screen'),
                            body: SizedBox(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Push'));
      await tester.pumpAndSettle();
      expect(find.text('Second Screen'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(popped, isTrue);
      expect(find.text('Second Screen'), findsNothing);
    });
  });
}
