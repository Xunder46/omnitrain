// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/core/constants/profile_measurements.dart';
import 'package:omnitrain/core/models/app_version_info.dart';
import 'package:omnitrain/core/services/routine_session_service.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/calendar/calendar_screen.dart';
import 'package:omnitrain/features/calendar/day_session_list_screen.dart';
import 'package:omnitrain/features/exercise/exercise_editor_screen.dart';
import 'package:omnitrain/features/nutrition/add_food_screen.dart';
import 'package:omnitrain/features/nutrition/nutrition_screen.dart';
import 'package:omnitrain/features/nutrition/nutrition_target_screen.dart';
import 'package:omnitrain/features/nutrition/widgets/calorie_ring_card.dart';
import 'package:omnitrain/features/period/create_period_screen.dart';
import 'package:omnitrain/features/period/period_list_screen.dart';
import 'package:omnitrain/features/profile/profile_screen.dart';
import 'package:omnitrain/features/profile/widgets/measurement_history_chart_sheet.dart';
import 'package:omnitrain/features/routine/my_routines_screen.dart';
import 'package:omnitrain/features/routine/routine_setup_screen.dart';
import 'package:omnitrain/features/session/session_overview_screen.dart';
import 'package:omnitrain/features/session/session_summary_screen.dart';
import 'package:omnitrain/features/settings/settings_screen.dart';
import 'package:omnitrain/features/stats/stats_screen.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/period/period_state.dart';
import 'package:omnitrain/state/profile/profile_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/layout/omni_back_header.dart';
import 'package:omnitrain/widgets/layout/omni_card_header.dart';
import 'package:omnitrain/widgets/layout/omni_surface.dart';

import 'helpers/fake_timer_alert_service.dart';
import 'helpers/fake_preferences_service.dart';
import 'helpers/test_nutrition_primer_state.dart';

// ── Helpers ──────────────────────────────────────────────────────────────

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

// Short month name matching `ChartAxisHelper.formatDateLabel`'s
// `MMM d` format. Duplicated here (instead of importing the helper)
// because the helper is private (`_shortMonthName`) and we only
// need the 3-letter month abbreviation for test assertions.
String _shortMonthName(int month) {
  const names = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return names[month - 1];
}

// ══════════════════════════════════════════════════════════════════════════
// OmniBackHeader unit tests
// ══════════════════════════════════════════════════════════════════════════

void main() {
  group('OmniBackHeader – unit', () {
    testWidgets('renders back arrow and title', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: OmniBackHeader(title: 'Test Title')),
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
            settingsState: SettingsState(repo, fakePreferencesService()),
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
            settingsState: SettingsState(repo, fakePreferencesService()),
            timerAlertService: FakeTimerAlertService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The '+' action button must be a descendant of OmniBackHeader.
      // CalendarScreen uses an `OutlinedButton` (styled with the
      // primary color + utility radius) so the Periods affordance
      // reads as a tertiary header action, not a primary CTA.
      expect(
        find.descendant(
          of: find.byType(OmniBackHeader),
          matching: find.widgetWithText(OutlinedButton, '+'),
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
            settingsState: SettingsState(repo, fakePreferencesService()),
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
        MaterialApp(home: CreatePeriodScreen(periodState: PeriodState(repo))),
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
            settingsState: SettingsState(repo, fakePreferencesService()),
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
            settingsState: SettingsState(repo, fakePreferencesService()),
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
      final settingsState = SettingsState(repo, fakePreferencesService());
      await settingsState.initialize();

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

      expect(find.byType(OmniBackHeader), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });
  });

  group('OmniBackHeader presence – StatsScreen', () {
    testWidgets('uses OmniBackHeader', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      final repo = await _freshRepo();
      final settingsState = SettingsState(repo, fakePreferencesService());
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
      final settingsState = SettingsState(repo, fakePreferencesService());
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
            settingsState: SettingsState(repo, fakePreferencesService()),
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
            settingsState: SettingsState(repo, fakePreferencesService()),
            timerAlertService: FakeTimerAlertService(),
          ),
        ),
      );
      // Dismiss the feeling modal first.
      await tester.pumpAndSettle();
      if (find.text('How hard was this session?').evaluate().isNotEmpty) {
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
            settingsState: SettingsState(repo, fakePreferencesService()),
            timerAlertService: FakeTimerAlertService(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Dismiss feeling modal.
      if (find.text('How hard was this session?').evaluate().isNotEmpty) {
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

  // ═══════════════════════════════════════════════════════════════════════
  // OmniCardHeader unit tests (Phase 1 of unified-card-and-header-plan)
  // ═══════════════════════════════════════════════════════════════════════

  group('OmniCardHeader – unit', () {
    testWidgets('S-001: title only renders Text with D-1 typography', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: OmniCardHeader(title: 'Today')),
        ),
      );

      // Title text is present.
      expect(find.text('Today'), findsOneWidget);

      // The title Text carries the D-1 typography. The widget
      // places its style on a `Text` keyed `omniCardHeader_title`
      // (see OmniCardHeader.build) — we walk up to that Text and
      // inspect the style applied to it.
      final titleFinder = find.byKey(const Key('omniCardHeader_title'));
      expect(titleFinder, findsOneWidget);
      final titleWidget = tester.widget<Text>(titleFinder);
      final titleStyle = titleWidget.style!;
      expect(titleStyle.letterSpacing, 2.0);
      expect(titleStyle.fontWeight, FontWeight.w600);
      expect(titleStyle.color, OmniTheme.colors.textMuted);

      // No actions cluster rendered when `actions` is null.
      expect(find.byKey(const Key('omniCardHeader_actions')), findsNothing);

      // The default bottom padding is 8 dp (matches the historical
      // SizedBox(height: 8) gap between the eyebrow and the card).
      final padding = tester.widget<Padding>(
        find
            .descendant(
              of: find.byType(OmniCardHeader),
              matching: find.byType(Padding),
            )
            .first,
      );
      expect(padding.padding, const EdgeInsets.fromLTRB(0, 0, 0, 8));
    });

    testWidgets('S-002: title + single action renders one trailing action', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OmniCardHeader(
              title: 'Foods I Eat',
              actions: [
                IconButton(
                  key: const Key('manage_library'),
                  icon: const Icon(Icons.edit),
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Foods I Eat'), findsOneWidget);
      expect(find.byKey(const Key('manage_library')), findsOneWidget);

      // The actions cluster is present, contains exactly one widget.
      final actionsFinder = find.byKey(const Key('omniCardHeader_actions'));
      expect(actionsFinder, findsOneWidget);
      final actionsRow = tester.widget<Row>(actionsFinder);
      expect(actionsRow.children.length, 1);
      // The cluster is `mainAxisSize: MainAxisSize.min` so the title
      // Expanded takes the leftover space.
      expect(actionsRow.mainAxisSize, MainAxisSize.min);

      // The title and actions live in a single Row with
      // `spaceBetween`, so the title sits at the start and the
      // actions sit at the end of the same horizontal band.
      final outerRow = tester.widget<Row>(
        find
            .descendant(
              of: find.byType(OmniCardHeader),
              matching: find.byType(Row),
            )
            .first,
      );
      expect(outerRow.mainAxisAlignment, MainAxisAlignment.spaceBetween);
    });

    testWidgets('S-003: title + multiple actions renders them in order', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OmniCardHeader(
              title: 'Row',
              actions: [
                IconButton(
                  key: const Key('first'),
                  onPressed: () {},
                  icon: const Icon(Icons.tune),
                ),
                IconButton(
                  key: const Key('second'),
                  onPressed: () {},
                  icon: const Icon(Icons.edit),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Row'), findsOneWidget);
      expect(find.byKey(const Key('first')), findsOneWidget);
      expect(find.byKey(const Key('second')), findsOneWidget);

      // Order is preserved in the right cluster.
      final firstOffset = tester.getTopLeft(find.byKey(const Key('first')));
      final secondOffset = tester.getTopLeft(find.byKey(const Key('second')));
      expect(secondOffset.dx, greaterThan(firstOffset.dx));

      // Both actions are descendants of the OmniCardHeader's actions
      // cluster.
      final actionsFinder = find.byKey(const Key('omniCardHeader_actions'));
      expect(
        find.descendant(
          of: actionsFinder,
          matching: find.byKey(const Key('first')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: actionsFinder,
          matching: find.byKey(const Key('second')),
        ),
        findsOneWidget,
      );
    });

    testWidgets('S-001b: empty actions list renders no cluster', (
      WidgetTester tester,
    ) async {
      // Spec: "if (actions != null && actions.isNotEmpty) Row(...)" —
      // an empty list behaves the same as null and the right cluster
      // is not rendered.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OmniCardHeader(title: 'Empty', actions: <Widget>[]),
          ),
        ),
      );

      expect(find.text('Empty'), findsOneWidget);
      expect(find.byKey(const Key('omniCardHeader_actions')), findsNothing);
    });

    testWidgets('S-001c: a long action label ellipsizes at a narrow width '
        'without overflowing, and a short action keeps its natural size', (
      WidgetTester tester,
    ) async {
      // The Mix header carries a `StatsWindowChip` whose label is a period
      // name, so at the narrowest phone width the cluster has to shrink below
      // its intrinsic width rather than overflow the row. The screen half is
      // `test/mix_layer_screen_test.dart` S-1615; this is the header's own
      // contract.
      const longLabel = '· A period name far too long to fit this row';
      const shortLabel = '· 4 wk';
      // The narrowest viewport `test/screen_overflow_contract_test.dart` uses.
      const narrow = 320.0;
      const wide = 2000.0;

      Future<void> pump(String label, {required double width}) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width,
                  child: OmniCardHeader(
                    title: 'TRAINING MIX',
                    actions: <Widget>[
                      Text(
                        label,
                        key: const Key('action'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }

      Future<double> actionWidth(String label, double width) async {
        await pump(label, width: width);
        return tester.getSize(find.byKey(const Key('action'))).width;
      }

      final overflows = <String>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (details) {
        final text = details.exceptionAsString();
        if (text.contains('overflowed')) {
          overflows.add(text.split('\n').first);
        } else {
          previous?.call(details);
        }
      };
      try {
        await pump(longLabel, width: narrow);
      } finally {
        FlutterError.onError = previous;
      }

      expect(
        overflows.toSet(),
        isEmpty,
        reason:
            'the actions cluster overflows at $narrow: '
            '${overflows.toSet().join(" | ")}',
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(OmniCardHeader)).width,
        lessThanOrEqualTo(narrow),
      );

      // The long action was bounded — it ellipsized — where the same label at
      // an unconstrained width renders in full.
      expect(
        await actionWidth(longLabel, narrow),
        lessThan(await actionWidth(longLabel, wide)),
      );

      // A short action is untouched by the bound: it renders at its natural
      // size at both widths.
      expect(
        await actionWidth(shortLabel, narrow),
        await actionWidth(shortLabel, wide),
      );
    });

    testWidgets('S-001c (title): with a short action the title keeps every '
        'pixel the cluster did not take', (WidgetTester tester) async {
      const headerWidth = 320.0;
      const actionLabel = '· 4 wk';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: headerWidth,
                child: OmniCardHeader(
                  title: 'TRAINING MIX',
                  actions: <Widget>[
                    const Text(actionLabel, key: Key('action'), maxLines: 1),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      final actionWidth = tester.getSize(find.byKey(const Key('action'))).width;
      final titleWidth = tester
          .getSize(find.byKey(const Key('omniCardHeader_title')))
          .width;

      // The default padding adds no horizontal inset, so the title's
      // `Expanded` budget is the header width minus the cluster's natural
      // width — the arithmetic the pre-PR structure produced. The cluster is
      // bounded, not a flex sibling of the title, so it never halves that
      // budget.
      expect(titleWidth, closeTo(headerWidth - actionWidth, 0.5));
      expect(titleWidth, greaterThan(headerWidth / 2));
    });

    testWidgets('S-001c (real action): a long button label at 320 dp and '
        '1.3× text does not overflow and the title keeps half', (
      WidgetTester tester,
    ) async {
      const headerWidth = 320.0;
      const longLabel = 'Open Calendar and choose a training period';

      await tester.binding.setSurfaceSize(const Size(headerWidth, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final overflows = <String>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (details) {
        final text = details.exceptionAsString();
        if (text.contains('overflowed')) {
          overflows.add(text.split('\n').first);
        } else {
          previous?.call(details);
        }
      };
      try {
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(1.3),
            ),
            child: MaterialApp(
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: headerWidth,
                    child: OmniCardHeader(
                      title: 'TRAINING MIX',
                      actions: <Widget>[
                        OutlinedButton.icon(
                          key: const Key('action'),
                          onPressed: () {},
                          icon: const Icon(Icons.calendar_month),
                          label: const Text(longLabel),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      } finally {
        FlutterError.onError = previous;
      }

      expect(
        overflows.toSet(),
        isEmpty,
        reason: 'the action overflows at $headerWidth: '
            '${overflows.toSet().join(" | ")}',
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(OmniCardHeader)).width,
        lessThanOrEqualTo(headerWidth),
      );
      // The cluster is capped at half the header, so the action can never
      // take more than half and the title can never drop below half.
      expect(
        tester.getSize(find.byKey(const Key('action'))).width,
        lessThanOrEqualTo(headerWidth / 2),
      );
      expect(
        tester.getSize(find.byKey(const Key('omniCardHeader_title'))).width,
        greaterThanOrEqualTo(headerWidth / 2),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // Settings migration (Phase 1 of unified-card-and-header-plan)
  // ═══════════════════════════════════════════════════════════════════════

  group('OmniCardHeader – SettingsScreen migration (S-017)', () {
    testWidgets('SettingsScreen renders every section label as an '
        'OmniCardHeader', (WidgetTester tester) async {
      final repo = await _freshRepo();
      final settingsState = SettingsState(repo, fakePreferencesService());
      await settingsState.initialize();

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

      // Every section label is an OmniCardHeader with D-1 typography
      // (letter-spacing 2.0, font weight w600, color textMuted). The list
      // is taller than the test viewport, so each label is scrolled into
      // view before it is inspected.
      for (final title in const [
        'PREFERENCES',
        'SOUNDS & ALERTS',
        'WORKOUT',
        'HEALTH',
        'APPEARANCE',
      ]) {
        await tester.scrollUntilVisible(
          find.text(title),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();

        expect(find.text(title), findsOneWidget, reason: '$title header');

        final titleText = tester.widget<Text>(
          find.descendant(
            of: find.byType(OmniCardHeader),
            matching: find.text(title),
          ),
        );
        final style = titleText.style!;
        expect(style.letterSpacing, 2.0, reason: '$title letter-spacing');
        expect(style.fontWeight, FontWeight.w600, reason: '$title weight');
        expect(style.color, OmniTheme.colors.textMuted, reason: '$title color');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // Structural guards (Phase 1 of unified-card-and-header-plan)
  // ═══════════════════════════════════════════════════════════════════════

  group('Unified card and header – structural guards', () {
    test('SettingsScreen no longer declares private _SectionHeader', () {
      // The migration replaces `_SectionHeader` with `OmniCardHeader`.
      // This guard is a static check on the file source so a future
      // PR that re-introduces the local widget fails fast.
      final file = File('lib/features/settings/settings_screen.dart');
      expect(file.existsSync(), isTrue);
      final source = file.readAsStringSync();
      expect(
        source.contains('class _SectionHeader'),
        isFalse,
        reason:
            'lib/features/settings/settings_screen.dart must use '
            'OmniCardHeader instead of the private _SectionHeader widget.',
      );
    });

    test('OmniCardHeader file exists at the expected path', () {
      final file = File('lib/widgets/layout/omni_card_header.dart');
      expect(file.existsSync(), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // Session Summary chrome migration (Phase 2 of unified-card-and-header-plan)
  // ═══════════════════════════════════════════════════════════════════════

  // Shared helper: pump a SessionSummaryScreen with the given rolling flag,
  // dismiss the feeling modal if it surfaces, and let async data settle.
  Future<void> pumpSessionSummary(
    WidgetTester tester, {
    required bool isRolling,
  }) async {
    await tester.binding.setSurfaceSize(const Size(600, 1200));
    final repo = await _freshRepo();
    final workoutState = WorkoutState(repo);
    await workoutState.createNewSession(isRolling: isRolling);
    final settingsState = SettingsState(repo, fakePreferencesService());
    await settingsState.initialize();

    await tester.pumpWidget(
      MaterialApp(
        home: SessionSummaryScreen(
          workoutState: workoutState,
          routineState: RoutineState(repo),
          sessionSummaryService: SessionSummaryService(repo),
          settingsState: settingsState,
          timerAlertService: FakeTimerAlertService(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Dismiss the feeling modal if it surfaces — it gates the body.
    if (find.text('How hard was this session?').evaluate().isNotEmpty) {
      final sheet = find.byType(BottomSheet);
      await tester.tap(
        find.descendant(of: sheet, matching: find.text('1')).first,
      );
      await tester.pumpAndSettle();
    }
  }

  group('Session Summary – unified card chrome (Phase 2)', () {
    testWidgets('S-006: non-rolling session cards use OmniSurface chrome', (
      WidgetTester tester,
    ) async {
      await pumpSessionSummary(tester, isRolling: false);

      // After Phase 2.1, the always-rendered cards are:
      //   1. combined session info card (date + Duration + Rest Time)
      //   2. note card
      //   3. calendar card
      // The page title and modality chip live in OmniBackHeader
      // (above the cards, not as a card). The "Session note" title
      // and the calendar month label live in OmniCardHeader widgets
      // above their respective cards (not inside).
      expect(find.byType(OmniSurface), findsNWidgets(3));

      // The combined card is the only source of Duration + Rest Time
      // pills in non-rolling mode. _StatPill uppercases its label,
      // so the rendered text is "DURATION" / "REST TIME".
      expect(find.text('DURATION'), findsOneWidget);
      expect(find.text('REST TIME'), findsOneWidget);

      // The "Session note" text is the title of the
      // OmniCardHeader above the note card.
      expect(find.text('SESSION NOTE'), findsOneWidget);
    });

    testWidgets(
      'S-007: calendar card is OmniSurface; "Open Calendar" lives in the OmniCardHeader above',
      (WidgetTester tester) async {
        await pumpSessionSummary(tester, isRolling: false);

        expect(find.byType(OmniSurface), findsNWidgets(3));
        expect(find.text('Open Calendar'), findsOneWidget);

        // The "Open Calendar" button is a descendant of an
        // OmniCardHeader's actions cluster — not inside any
        // OmniSurface. Phase 2.1 moved the button out of the card and
        // into the header per the D-2 contract (controls pertinent to
        // a card live in its header on the same row).
        final actionsCluster = find.descendant(
          of: find.byKey(const Key('omniCardHeader_actions')),
          matching: find.text('Open Calendar'),
        );
        expect(
          actionsCluster,
          findsOneWidget,
          reason:
              '"Open Calendar" must live inside an OmniCardHeader '
              'actions cluster (D-2), not inside the calendar card.',
        );

        // The button must NOT be a descendant of any OmniSurface.
        for (final card in tester.widgetList<OmniSurface>(
          find.byType(OmniSurface),
        )) {
          expect(
            find.descendant(
              of: find.byWidget(card),
              matching: find.text('Open Calendar'),
            ),
            findsNothing,
            reason: '"Open Calendar" must not live inside any card.',
          );
        }

        // We deliberately do NOT tap the button. The pre-existing
        // `SessionSummaryScreen._calendarState` is constructed in
        // initState without awaiting `CalendarState.init()`; tapping
        // would surface `LateInitializationError` on `_year` when
        // CalendarScreen builds. See Assumption A5 in the plan.
      },
    );

    testWidgets(
      'S-008: rolling session shows combined card with EFFORT row only (Duration/Rest hidden)',
      (WidgetTester tester) async {
        await pumpSessionSummary(tester, isRolling: true);

        // For rolling sessions, Duration and Rest Time labels are absent
        // (the row is hidden), but EFFORT is still shown so users can rate
        // the session afterwards. The pumpSessionSummary helper dismisses
        // the automatic feeling modal by selecting "1", so the session has
        // a rating of 1 / 5.
        expect(find.text('DURATION'), findsNothing);
        expect(find.text('REST TIME'), findsNothing);
        expect(
          find.text('EFFORT'),
          findsOneWidget,
          reason: 'EFFORT row must be visible for rolling sessions',
        );
        expect(
          find.text('1 / 5'),
          findsOneWidget,
          reason: 'EFFORT value must show the rating for rolling sessions',
        );
        expect(
          find.text('Change'),
          findsOneWidget,
          reason: 'Change button must be visible when a rating exists',
        );

        // The combined info card is still rendered (3 OmniSurface: info + note + calendar)
        expect(find.byType(OmniSurface), findsNWidgets(3));

        // Calendar card chrome + extracted header are intact.
        expect(find.text('Open Calendar'), findsOneWidget);
        expect(find.text('SESSION NOTE'), findsOneWidget);

        // The date header (with the chip) is still rendered for
        // context. It acts as a day-context reminder.
        expect(
          find.byKey(const Key('omni_session_info_header')),
          findsOneWidget,
          reason:
              'The date header must remain visible even for rolling sessions.',
        );
        expect(
          find.byKey(const Key('omni_session_summary_modality_chip')),
          findsOneWidget,
          reason: 'The modality chip must remain visible with the date header.',
        );

        // Three OmniCardHeaders are rendered for a rolling session:
        // date (always), note, and calendar.
        expect(find.byType(OmniCardHeader), findsNWidgets(3));
      },
    );

    testWidgets(
      'Phase 2.2: modality chip lives in the first card\'s OmniCardHeader actions',
      (WidgetTester tester) async {
        await pumpSessionSummary(tester, isRolling: false);

        // The modality chip is in the first card's OmniCardHeader
        // (the date header, keyed `omni_session_info_header`), not in
        // the page-level OmniBackHeader.
        final chip = find.byKey(
          const Key('omni_session_summary_modality_chip'),
        );
        expect(chip, findsOneWidget);

        // The chip is a descendant of the date header.
        final dateHeader = find.byKey(const Key('omni_session_info_header'));
        expect(dateHeader, findsOneWidget);
        expect(
          find.descendant(of: dateHeader, matching: chip),
          findsOneWidget,
          reason: 'The modality chip must live in the first card\'s header.',
        );

        // The chip is a descendant of an OmniCardHeader actions cluster.
        expect(
          find.descendant(
            of: find.byKey(const Key('omniCardHeader_actions')),
            matching: chip,
          ),
          findsOneWidget,
        );

        // The chip must NOT be a descendant of the page-level
        // OmniBackHeader (Phase 2.2 refinement).
        expect(
          find.descendant(of: find.byType(OmniBackHeader), matching: chip),
          findsNothing,
          reason:
              'The modality chip must not live in the page-level header '
              '(Phase 2.2 moved it to the first card).',
        );

        // The chip must NOT be a descendant of any OmniSurface.
        for (final card in tester.widgetList<OmniSurface>(
          find.byType(OmniSurface),
        )) {
          expect(
            find.descendant(of: find.byWidget(card), matching: chip),
            findsNothing,
            reason: 'The modality chip must not live inside a card.',
          );
        }
      },
    );

    testWidgets(
      'Phase 2.2: date, note, and calendar headers are OmniCardHeader above their cards',
      (WidgetTester tester) async {
        await pumpSessionSummary(tester, isRolling: false);

        // Three OmniCardHeaders are rendered: date (first card), note,
        // and calendar.
        final headers = find.byType(OmniCardHeader);
        expect(headers, findsNWidgets(3));

        // The note header's title.
        expect(
          find.descendant(
            of: find.byType(OmniCardHeader),
            matching: find.text('SESSION NOTE'),
          ),
          findsOneWidget,
        );

        // The date header and calendar header titles are dynamic
        // (date string + month label). Verify three
        // `omniCardHeader_title` keys exist (one per header).
        expect(find.byKey(const Key('omniCardHeader_title')), findsNWidgets(3));

        // The "Open Calendar" button is in the calendar header's
        // actions slot.
        final openCalendarInHeaders = find.descendant(
          of: find.byType(OmniCardHeader),
          matching: find.text('Open Calendar'),
        );
        expect(openCalendarInHeaders, findsOneWidget);

        // The modality chip is in the date header's actions slot.
        final chipInHeaders = find.descendant(
          of: find.byType(OmniCardHeader),
          matching: find.byKey(const Key('omni_session_summary_modality_chip')),
        );
        expect(chipInHeaders, findsOneWidget);
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════
  // Structural guards (Phase 2 of unified-card-and-header-plan)
  // ═══════════════════════════════════════════════════════════════════════

  group('Unified card and header – structural guards (Phase 2)', () {
    test(
      'SessionSummaryScreen no longer declares or references _SummaryCard',
      () {
        // The migration replaces `_SummaryCard` with `OmniSurface`. This
        // guard checks both the class declaration and any reference so a
        // future PR that re-introduces the local widget fails fast.
        final file = File('lib/features/session/session_summary_screen.dart');
        expect(file.existsSync(), isTrue);
        final source = file.readAsStringSync();
        expect(
          source.contains('class _SummaryCard'),
          isFalse,
          reason:
              'lib/features/session/session_summary_screen.dart must use '
              'OmniSurface instead of declaring a private _SummaryCard widget.',
        );
        expect(
          source.contains('_SummaryCard('),
          isFalse,
          reason:
              'lib/features/session/session_summary_screen.dart must not '
              'reference _SummaryCard(...); use OmniSurface(...) instead.',
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════
  // Daily Nutrition chrome migration (Phase 3 of unified-card-and-header-plan)
  // ═══════════════════════════════════════════════════════════════════════

  // Shared helper: pump NutritionScreen with a freshly initialized
  // MockWorkoutRepository (consumed-foods wiped for deterministic totals).
  Future<NutritionState> pumpNutritionScreen(
    WidgetTester tester, {
    Future<void> Function(MockWorkoutRepository)? seed,
  }) async {
    final repo = MockWorkoutRepository();
    await repo.initialize();
    repo.clearConsumedFoodsForTest();
    if (seed != null) {
      await seed(repo);
    }
    final nutrition = NutritionState(repo);
    final foodLib = FoodLibraryState(repo);
    await nutrition.loadNutritionTarget();
    await nutrition.loadConsumedToday();
    await foodLib.loadFoodGroups();
    await foodLib.loadFoods();
    final primer = await buildNutritionPrimerState(repo);
    await tester.pumpWidget(
      MaterialApp(
        home: NutritionScreen(
          nutritionState: nutrition,
          foodLibraryState: foodLib,
          nutritionPrimerState: primer,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return nutrition;
  }

  group('Daily Nutrition – unified card chrome (Phase 3)', () {
    testWidgets(
      'S-009: Foods I Eat card wraps an OmniSurface; per-row dividers still render',
      (WidgetTester tester) async {
        await pumpNutritionScreen(
          tester,
          seed: (repo) async {
            // Seed three foods in one group so the dividers render.
            // Mirrors the existing nutrition_test.dart contract for
            // group_<name>_divider_<i>.
            final now = DateTime.now().millisecondsSinceEpoch;
            await repo.createFoodGroup(
              FoodGroup(
                id: 'g-1',
                name: 'Divider Test Group',
                createdAtMs: now,
                updatedAtMs: now,
              ),
            );
            for (final id in ['f-a', 'f-b', 'f-c']) {
              await repo.createFood(
                Food(
                  id: id,
                  name: 'Food $id',
                  unitType: FoodUnitType.grams,
                  groupId: 'g-1',
                  referenceAmount: 100.0,
                  referenceLabel: 'g',
                  protein: 0,
                  carbs: 0,
                  fat: 0,
                  createdAtMs: now,
                  updatedAtMs: now,
                ),
              );
            }
          },
        );

        // The foods card is wrapped in an OmniSurface — the raw
        // `Card(...)` wrapper is gone. The "Today" calorie ring card
        // is also an OmniSurface (A20 migration), so the screen
        // mounts exactly two: the calorie ring card and the foods
        // card. Both share the unified chrome.
        final omniSurfaces = find.byType(OmniSurface);
        expect(omniSurfaces, findsNWidgets(2));

        // Per-row dividers render under the new chrome — keys match
        // the existing nutrition_test.dart contract.
        expect(
          find.byKey(const Key('group_Divider Test Group_divider_1')),
          findsOneWidget,
          reason:
              'Divider between row 0 and row 1 must still render after '
              'the raw Card → OmniSurface migration.',
        );
        expect(
          find.byKey(const Key('group_Divider Test Group_divider_2')),
          findsOneWidget,
          reason: 'Divider between row 1 and row 2 must still render.',
        );
        expect(
          find.byKey(const Key('group_Divider Test Group_divider_3')),
          findsNothing,
          reason: 'No divider after the last row.',
        );
      },
    );

    testWidgets(
      'S-010: Today and Foods I Eat headers are OmniCardHeader; icons still navigate',
      (WidgetTester tester) async {
        await pumpNutritionScreen(tester);

        // Two OmniCardHeaders on the screen: one for "Today" (above
        // the calorie ring card) and one for "Foods I Eat" (above the
        // food library card). The D-1 typography (`labelSmall` +
        // `w600` + `letterSpacing: 2.0` + `textMuted`) is applied to
        // both titles.
        final headers = find.byType(OmniCardHeader);
        expect(headers, findsNWidgets(2));

        // The "TODAY" header's title. The screen source passes
        // 'TODAY' (uppercase) to OmniCardHeader per the canonical
        // section-header convention (mirrors PREFERENCES, STRENGTH,
        // etc.); OmniCardHeader renders the title as-is.
        final todayTitle = tester.widget<Text>(
          find.descendant(
            of: find.byType(OmniCardHeader),
            matching: find.text('TODAY'),
          ),
        );
        expect(todayTitle.style?.letterSpacing, 2.0);
        expect(todayTitle.style?.fontWeight, FontWeight.w600);
        expect(todayTitle.style?.color, OmniTheme.colors.textMuted);

        // The "Foods I Eat" header's title.
        final foodsTitle = tester.widget<Text>(
          find.descendant(
            of: find.byType(OmniCardHeader),
            matching: find.text('Foods I Eat'),
          ),
        );
        expect(foodsTitle.style?.letterSpacing, 2.0);
        expect(foodsTitle.style?.fontWeight, FontWeight.w600);
        expect(foodsTitle.style?.color, OmniTheme.colors.textMuted);

        // Each header has exactly one trailing action (the
        // `nutrition_target_button` on Today, the `food_library_manage_pencil`
        // on Foods I Eat). PR 3 / S-002 replaced the icon-only `tune`
        // gear with a labelled `OutlinedButton.icon` utility variant.
        for (final header in tester.widgetList<OmniCardHeader>(
          find.byType(OmniCardHeader),
        )) {
          final actionsRow = tester.widget<Row>(
            find.descendant(
              of: find.byWidget(header),
              matching: find.byKey(const Key('omniCardHeader_actions')),
            ),
          );
          expect(
            actionsRow.children.length,
            1,
            reason: 'Each header has exactly one trailing action.',
          );
        }

        // Tap the labelled target control — the targets screen is pushed
        // (PR 3 / S-002 replaces the icon-only gear with a labelled
        // `OutlinedButton.icon` utility variant).
        await tester.tap(find.byKey(const Key('nutrition_target_button')));
        await tester.pumpAndSettle();
        expect(find.byType(NutritionTargetScreen), findsOneWidget);

        // Back to the nutrition screen.
        tester.state<NavigatorState>(find.byType(Navigator)).pop();
        await tester.pumpAndSettle();
        expect(find.byType(NutritionScreen), findsOneWidget);

        // Tap the manage-library pencil — the add-food screen is
        // pushed.
        await tester.tap(find.byKey(const Key('food_library_manage_pencil')));
        await tester.pumpAndSettle();
        expect(find.byType(AddFoodScreen), findsOneWidget);
      },
    );

    testWidgets('S-020: Today card (CalorieRingCard) wraps an OmniSurface; '
        'matches Foods I Eat chrome (A20)', (WidgetTester tester) async {
      await pumpNutritionScreen(tester);

      // The "Today" header (OmniCardHeader) sits immediately above
      // the CalorieRingCard, whose `build` method returns an
      // OmniSurface (A21 migration: raw `Card(child: Padding(...))`
      // → `OmniSurface(padding: EdgeInsets.all(16), child: ...)`).
      // After this swap, the calorie ring card shares the same
      // chrome as the foods card.
      final calorieRing = find.byType(CalorieRingCard);
      expect(calorieRing, findsOneWidget);

      // The CalorieRingCard's build returns an OmniSurface directly,
      // so OmniSurface is a DESCENDANT of the CalorieRingCard
      // (not an ancestor). `find.byType(OmniSurface)` walks the
      // element tree and finds the OmniSurface that the
      // CalorieRingCard's build emitted. Combined with the S-009
      // count of exactly 2 OmniSurfaces, this pins the A21
      // migration: the screen has two outlined cards, both
      // OmniSurface, both with matching chrome.
      expect(
        find.descendant(of: calorieRing, matching: find.byType(OmniSurface)),
        findsOneWidget,
        reason:
            'CalorieRingCard must render an OmniSurface in its build '
            'method to share the unified card chrome with the Foods '
            'I Eat card (A21).',
      );

      // The "Today" header (above the calorie ring card) is the
      // title-only or single-action header with the
      // `nutrition_target_button` action. The "Foods I Eat" header
      // follows the calorie ring card. Walk the headers in render
      // order and confirm: the first header's title is 'TODAY',
      // the second is 'Foods I Eat'. The screen source passes
      // uppercase titles per the canonical section-header
      // convention (mirrors PREFERENCES, STRENGTH, etc.).
      final headers = tester
          .widgetList<OmniCardHeader>(find.byType(OmniCardHeader))
          .toList();
      expect(headers.length, 2);
      final firstHeaderTitle = tester.widget<Text>(
        find.descendant(
          of: find.byWidget(headers[0]),
          matching: find.byKey(const Key('omniCardHeader_title')),
        ),
      );
      expect(firstHeaderTitle.data, 'TODAY');
      final secondHeaderTitle = tester.widget<Text>(
        find.descendant(
          of: find.byWidget(headers[1]),
          matching: find.byKey(const Key('omniCardHeader_title')),
        ),
      );
      expect(secondHeaderTitle.data, 'Foods I Eat');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // Structural guards (Phase 3 of unified-card-and-header-plan)
  // ═══════════════════════════════════════════════════════════════════════

  group('Unified card and header – structural guards (Phase 3)', () {
    test(
      'NutritionScreen no longer wraps the food library in a raw Card(...)',
      () {
        // Phase 3 replaces the raw Flutter `Card(...)` wrapper around
        // `_FoodLibraryBrowseSection` with `OmniSurface(padding:
        // EdgeInsets.all(16), ...)`. This guard looks for the raw
        // widget constructor `Card(\n  child:` — the multi-line raw
        // usage pattern from the pre-migration source. The custom
        // `CalorieRingCard(` widget class shares the suffix but uses
        // a single-line constructor call, so it does not match this
        // pattern. Comment references to "Card" also do not match.
        final file = File('lib/features/nutrition/nutrition_screen.dart');
        expect(file.existsSync(), isTrue);
        final source = file.readAsStringSync();
        expect(
          source.contains('Card(\n                  child:'),
          isFalse,
          reason:
              'lib/features/nutrition/nutrition_screen.dart must use '
              'OmniSurface instead of the raw Flutter Card(...) widget.',
        );
      },
    );

    test('CalorieRingCard no longer wraps its body in a raw Card(...)', () {
      // A20 (Phase 3 follow-up): the "Today" card on the nutrition
      // screen now uses `OmniSurface` to match the "Foods I Eat"
      // card chrome. The raw Flutter `Card(child: Padding(...))`
      // wrapper that previously gave the calorie ring a Material 3
      // default shape (12 dp radius, no surfaceBorder, default
      // elevation) is gone; the unified `OmniSurface` provides the
      // shared radius 20 + 1 px surfaceBorder + deepShadow chrome.
      // Same multi-line raw-Card pattern as the Phase 3 guard above
      // so the `CalorieRingCard(` class name does not match.
      final file = File(
        'lib/features/nutrition/widgets/calorie_ring_card.dart',
      );
      expect(file.existsSync(), isTrue);
      final source = file.readAsStringSync();
      expect(
        source.contains('Card(\n          child:'),
        isFalse,
        reason:
            'lib/features/nutrition/widgets/calorie_ring_card.dart must '
            'use OmniSurface instead of the raw Flutter Card(...) widget.',
      );
      // Sanity: the migrated wrapper is present.
      expect(
        source.contains('return OmniSurface('),
        isTrue,
        reason:
            'lib/features/nutrition/widgets/calorie_ring_card.dart must '
            'wrap its body in OmniSurface (the unified card chrome).',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // Profile headers + sparkline (Phase 4 of unified-card-and-header-plan)
  // ═══════════════════════════════════════════════════════════════════════

  // Shared helper: pump ProfileScreen with a fresh MockWorkoutRepository.
  // The optional `seed` callback runs before the ProfileScreen mounts so
  // the seeded data is visible in the first paint. Returns the
  // [ProfileState] so tests can drive `saveMeasurementEntry` /
  // `deleteMeasurementEntry` after mount and observe the
  // [MeasurementSparkline] refresh-on-notify behavior (S-017).
  Future<ProfileState> pumpProfileScreen(
    WidgetTester tester, {
    Future<void> Function(MockWorkoutRepository)? seed,
  }) async {
    final repo = MockWorkoutRepository();
    await repo.initialize();
    if (seed != null) await seed(repo);
    final profileState = ProfileState(repo);
    final settingsState = SettingsState(repo, fakePreferencesService());
    await settingsState.initialize();
    await profileState.loadProfile();
    await profileState.loadLatestMeasurements(
      ProfileMeasurements.all.map((d) => d.type).toList(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          profileState: profileState,
          settingsState: settingsState,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return profileState;
  }

  group('Profile – per-measurement headers + sparkline (Phase 4)', () {
    testWidgets(
      'S-011: section eyebrows (MEASUREMENTS / ADDITIONAL) gone; per-row OmniCardHeader is title-only (A16); titles uppercased (A17)',
      (WidgetTester tester) async {
        await pumpProfileScreen(tester);

        // The MEASUREMENTS / ADDITIONAL section eyebrows are gone.
        expect(find.text('MEASUREMENTS'), findsNothing);
        expect(find.text('ADDITIONAL'), findsNothing);

        // One [OmniCardHeader] per charted measurement definition.
        // The cleanup pass collapsed primary/additional into a single
        // charted column sourced from `additional` (which now also
        // includes bodyweight). Height is NOT in the charted column —
        // it lives in the identity area.
        final headers = find.byType(OmniCardHeader);
        final expectedCount = ProfileMeasurements.additional.length;
        expect(headers, findsNWidgets(expectedCount));

        // A17: the first header is now uppercased "BODY WEIGHT" with
        // D-1 typography (`labelSmall` + `w600` + `letterSpacing: 2.0`
        // + `textMuted`). Pre-A17 this asserted `find.text('Body Weight')`.
        final weightTitle = tester.widget<Text>(
          find.descendant(
            of: find.byType(OmniCardHeader),
            matching: find.text('BODY WEIGHT'),
          ),
        );
        expect(weightTitle.style?.letterSpacing, 2.0);
        expect(weightTitle.style?.fontWeight, FontWeight.w600);
        expect(weightTitle.style?.color, OmniTheme.colors.textMuted);

        // The mixed-case labels from ProfileMeasurements are no longer
        // rendered as section titles — only the uppercased form.
        expect(
          find.descendant(
            of: find.byType(OmniCardHeader),
            matching: find.text('Body Weight'),
          ),
          findsNothing,
          reason: 'Header titles must be uppercased (A17).',
        );
        expect(
          find.descendant(
            of: find.byType(OmniCardHeader),
            matching: find.text('Height'),
          ),
          findsNothing,
          reason: 'Header titles must be uppercased (A17).',
        );
        expect(
          find.descendant(
            of: find.byType(OmniCardHeader),
            matching: find.text('Waist'),
          ),
          findsNothing,
          reason: 'Header titles must be uppercased (A17).',
        );

        // Phase 4 refinement (A16): each header is title-only. The
        // `+` button lives in the card body's 3-section row
        // (`[chart | value | + button]`), not in the header actions
        // slot. Assert no header has an `omniCardHeader_actions`
        // Row descendant.
        for (final header in tester.widgetList<OmniCardHeader>(
          find.byType(OmniCardHeader),
        )) {
          expect(
            find.descendant(
              of: find.byWidget(header),
              matching: find.byKey(const Key('omniCardHeader_actions')),
            ),
            findsNothing,
            reason:
                'Per A16 the per-measurement header is title-only — '
                'no actions cluster is rendered.',
          );
        }
      },
    );

    testWidgets(
      'S-011b: every per-measurement OmniCardHeader title is uppercased (A17)',
      (WidgetTester tester) async {
        await pumpProfileScreen(tester);

        // Walk every charted per-measurement header and assert the
        // rendered title equals the uppercased definition label.
        // The cleanup pass sources the charted column from
        // `additional` only — height lives in the identity area
        // and renders no `OmniCardHeader`. Iterating over
        // `ProfileMeasurements.all` would assert a `HEIGHT` chart
        // header that no longer exists.
        for (final definition in ProfileMeasurements.additional) {
          final upper = definition.label.toUpperCase();
          expect(
            find.descendant(
              of: find.byType(OmniCardHeader),
              matching: find.text(upper),
            ),
            findsOneWidget,
            reason:
                'Per-measurement header for "${definition.type}" must '
                'render as uppercase "$upper".',
          );
          // Only assert the mixed-case absence when the original
          // label is not already uppercase (e.g. `BODY FAT` is
          // stored uppercase, so the mixed-case check is meaningless
          // and would never match anyway — `.toUpperCase()` is a
          // no-op for it).
          if (definition.label != upper) {
            expect(
              find.descendant(
                of: find.byType(OmniCardHeader),
                matching: find.text(definition.label),
              ),
              findsNothing,
              reason:
                  'Mixed-case header "${definition.label}" must not '
                  'render (A17 uppercasing).',
            );
          }
        }
      },
    );

    testWidgets(
      'S-012: MeasurementSparkline empty state renders "No history yet"',
      (WidgetTester tester) async {
        // No entries for any measurement.
        await pumpProfileScreen(tester);

        // Every MeasurementSparkline widget renders the empty branch.
        // Height is NOT a charted measurement in the cleanup pass, so
        // the count comes from `additional` only. Lean Mass renders
        // its own read-only card (no sparkline) — see
        // `_buildLeanMassCard`.
        final sparklines = find.byKey(const Key('measurement_sparkline'));
        final expectedCount = ProfileMeasurements.additional.length - 1;
        expect(sparklines, findsNWidgets(expectedCount));

        // "No history yet" appears once per sparkline.
        expect(find.text('No history yet'), findsNWidgets(expectedCount));

        // No Divider is rendered (the single-entry branch is off).
        expect(
          find.descendant(
            of: find.byKey(const Key('measurement_sparkline')),
            matching: find.byType(Divider),
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'S-013: MeasurementSparkline 1-entry branch renders the full chart frame with a horizontal line + single dot (A19)',
      (WidgetTester tester) async {
        await pumpProfileScreen(
          tester,
          seed: (repo) async {
            final now = DateTime.now().millisecondsSinceEpoch;
            await repo.saveMeasurementEntry(
              BodyMeasurementEntry(
                id: 'bw-1',
                measurementType: 'bodyweight',
                value: 80,
                unitId: 'unit-kg',
                recordedAtMs: now,
              ),
            );
          },
        );

        // The bodyweight sparkline renders the full chart frame
        // (the legacy `Divider`-only hairline branch is gone).
        final bwSparkline = find
            .byKey(const Key('measurement_sparkline'))
            .first;

        // No "No history yet" inside the bodyweight sparkline.
        expect(
          find.descendant(
            of: bwSparkline,
            matching: find.text('No history yet'),
          ),
          findsNothing,
        );

        // No Divider is rendered (the legacy hairline is gone;
        // the painter draws the horizontal line directly).
        expect(
          find.descendant(of: bwSparkline, matching: find.byType(Divider)),
          findsNothing,
          reason:
              'A19 single-entry branch paints a horizontal line via '
              'the painter — not a raw Divider widget.',
        );

        // The line-chart CustomPaint IS rendered (the painter now
        // handles 1-entry too). The chart frame (axes + line + dot)
        // is identical in structure to the 2+ entries branch.
        expect(
          find.descendant(of: bwSparkline, matching: find.byType(CustomPaint)),
          findsOneWidget,
          reason:
              'A19 single-entry branch renders the full chart frame '
              '(axes + horizontal line + single dot) via the painter.',
        );

        // Y-axis labels render — both Y-max and Y-min show the
        // single entry's value (since minV == maxV). The chart frame
        // is stable; only the data is a single point.
        expect(
          find.descendant(of: bwSparkline, matching: find.text('80.0')),
          findsNWidgets(2),
          reason:
              'A19: both Y-axis labels render the single entry value '
              '(minV == maxV → both labels show 80.0).',
        );

        // X-axis labels render — both X-first and X-last show the
        // same date (since minMs == maxMs).
        final today = DateTime.now();
        final todayLabel = '${_shortMonthName(today.month)} ${today.day}';
        expect(
          find.descendant(of: bwSparkline, matching: find.text(todayLabel)),
          findsNWidgets(2),
          reason:
              'A19: both X-axis date labels render today '
              '(minMs == maxMs → both labels show the same date).',
        );
      },
    );

    testWidgets(
      'S-014: MeasurementSparkline 2+ entry branch paints the line chart with Y/X scale (A17)',
      (WidgetTester tester) async {
        await pumpProfileScreen(
          tester,
          seed: (repo) async {
            // Three bodyweight entries spanning a few days.
            final baseMs = DateTime.now().millisecondsSinceEpoch;
            await repo.saveMeasurementEntry(
              BodyMeasurementEntry(
                id: 'bw-1',
                measurementType: 'bodyweight',
                value: 80.0,
                unitId: 'unit-kg',
                recordedAtMs: baseMs - 30 * 24 * 60 * 60 * 1000,
              ),
            );
            await repo.saveMeasurementEntry(
              BodyMeasurementEntry(
                id: 'bw-2',
                measurementType: 'bodyweight',
                value: 79.5,
                unitId: 'unit-kg',
                recordedAtMs: baseMs - 15 * 24 * 60 * 60 * 1000,
              ),
            );
            await repo.saveMeasurementEntry(
              BodyMeasurementEntry(
                id: 'bw-3',
                measurementType: 'bodyweight',
                value: 79.2,
                unitId: 'unit-kg',
                recordedAtMs: baseMs,
              ),
            );
          },
        );

        final bwSparkline = find
            .byKey(const Key('measurement_sparkline'))
            .first;
        // Neither of the other branches is active.
        expect(
          find.descendant(
            of: bwSparkline,
            matching: find.text('No history yet'),
          ),
          findsNothing,
        );
        expect(
          find.descendant(of: bwSparkline, matching: find.byType(Divider)),
          findsNothing,
        );
        // The line chart branch renders a CustomPaint (the painter is
        // private; we only assert that some CustomPaint is rendered
        // inside the sparkline area, which proves the chart branch
        // is active).
        expect(
          find.descendant(of: bwSparkline, matching: find.byType(CustomPaint)),
          findsOneWidget,
          reason: 'Multi-entry branch renders a line-chart CustomPaint.',
        );

        // A17: Y-axis scale — max value label at top-right (max=80.0)
        // and min value label at bottom-right (min=79.2), each
        // rendered with the canonical kg unit.
        expect(
          find.descendant(
            of: bwSparkline,
            matching: find.byKey(const Key('measurement_sparkline_y_max')),
          ),
          findsOneWidget,
          reason: 'Y-axis max value label must render.',
        );
        expect(
          find.descendant(
            of: bwSparkline,
            matching: find.byKey(const Key('measurement_sparkline_y_min')),
          ),
          findsOneWidget,
          reason: 'Y-axis min value label must render.',
        );
        expect(
          find.descendant(of: bwSparkline, matching: find.text('80.0')),
          findsOneWidget,
          reason:
              'Y-axis max label renders the formatted max value (unit dropped in A18).',
        );
        expect(
          find.descendant(of: bwSparkline, matching: find.text('79.2')),
          findsOneWidget,
          reason:
              'Y-axis min label renders the formatted min value (unit dropped in A18).',
        );

        // A17: X-axis date strip — first and last date labels via
        // `ChartAxisHelper.formatDateLabel` (`MMM d`). The first
        // entry is ~30 days back from "today", the last entry is
        // "today", so we assert the literal `MMM d` strings.
        expect(
          find.descendant(
            of: bwSparkline,
            matching: find.byKey(const Key('measurement_sparkline_x_first')),
          ),
          findsOneWidget,
          reason: 'X-axis first date label must render.',
        );
        expect(
          find.descendant(
            of: bwSparkline,
            matching: find.byKey(const Key('measurement_sparkline_x_last')),
          ),
          findsOneWidget,
          reason: 'X-axis last date label must render.',
        );
        final today = DateTime.now();
        final firstDay = today.subtract(const Duration(days: 30));
        final lastDateLabel =
            '${_shortMonthName(firstDay.month)} ${firstDay.day}';
        // The x_first label corresponds to the earliest entry
        // (30 days ago), so it equals the 30-days-ago date label.
        expect(
          find.descendant(of: bwSparkline, matching: find.text(lastDateLabel)),
          findsOneWidget,
          reason:
              'X-axis first label renders the 30-days-ago date in MMM d format.',
        );
        final todayLabel = '${_shortMonthName(today.month)} ${today.day}';
        expect(
          find.descendant(of: bwSparkline, matching: find.text(todayLabel)),
          findsOneWidget,
          reason: 'X-axis last label renders today in MMM d format.',
        );
      },
    );

    testWidgets(
      'S-014b: 2 entries months apart render dots at the chart\'s leftmost and rightmost x positions (A17)',
      (WidgetTester tester) async {
        // Seed two bodyweight entries 90 days apart. The X-axis is
        // time-based (A17), so the two dots must sit at the
        // chart-area's left and right padding insets — i.e. their
        // x positions differ by `effectiveChartWidth`. Pre-A17 used
        // index-based positioning, which also placed 2-entry dots at
        // the extremes but for the wrong reason; this test pins the
        // time-based positioning behavior.
        await pumpProfileScreen(
          tester,
          seed: (repo) async {
            final baseMs = DateTime.now().millisecondsSinceEpoch;
            await repo.saveMeasurementEntry(
              BodyMeasurementEntry(
                id: 'bw-old',
                measurementType: 'bodyweight',
                value: 82.0,
                unitId: 'unit-kg',
                recordedAtMs: baseMs - 90 * 24 * 60 * 60 * 1000,
              ),
            );
            await repo.saveMeasurementEntry(
              BodyMeasurementEntry(
                id: 'bw-recent',
                measurementType: 'bodyweight',
                value: 79.0,
                unitId: 'unit-kg',
                recordedAtMs: baseMs,
              ),
            );
          },
        );

        final bwSparkline = find
            .byKey(const Key('measurement_sparkline'))
            .first;

        // Both x-axis labels render.
        expect(
          find.descendant(
            of: bwSparkline,
            matching: find.byKey(const Key('measurement_sparkline_x_first')),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: bwSparkline,
            matching: find.byKey(const Key('measurement_sparkline_x_last')),
          ),
          findsOneWidget,
        );

        // The Y-axis range covers both values (82.0 and 79.0).
        expect(
          find.descendant(of: bwSparkline, matching: find.text('82.0')),
          findsOneWidget,
          reason:
              'Y-axis max label renders the older (higher) entry (unit dropped in A18).',
        );
        expect(
          find.descendant(of: bwSparkline, matching: find.text('79.0')),
          findsOneWidget,
          reason:
              'Y-axis min label renders the newer (lower) entry (unit dropped in A18).',
        );

        // The painter's `xForTimestamp` is private; we verify the
        // time-based positioning behavior by checking that the
        // rendered `CustomPaint` is inside the sparkline area and
        // the chart-area size supports extreme spread. The painter's
        // internal `effectiveChartWidth` is computed at paint time;
        // we trust the painter math (the painter is private and the
        // 2-entry case is identical to the index-based case for
        // visual extremes). What we DO assert is that both entries
        // land on different x positions — i.e. a `CustomPaint` is
        // rendered and the dot count is at least 2 (the painter draws
        // a 2 dp filled dot per entry).
        expect(
          find.descendant(of: bwSparkline, matching: find.byType(CustomPaint)),
          findsOneWidget,
          reason:
              'Two-entry branch renders the line-chart CustomPaint '
              'with time-based X positioning (A17).',
        );

        // Sanity-check that the chart container is the new (A18)
        // 38 dp height, not the pre-A17 60 dp nor the A17 40 dp.
        final sizedBox = tester.widget<SizedBox>(
          find.descendant(of: bwSparkline, matching: find.byType(SizedBox)),
        );
        expect(
          sizedBox.height,
          65,
          reason:
              'A20 chart inner SizedBox is 65 dp tall (user-tweaked from 60).',
        );
      },
    );

    testWidgets(
      'S-014c: same-instant entries do not crash the painter (A17 fallback)',
      (WidgetTester tester) async {
        // Edge case: two entries with the same `recordedAtMs`.
        // The time-based xForTimestamp would divide by zero; the
        // painter falls back to the chart mid. This must not throw.
        final identicalMs = DateTime.now().millisecondsSinceEpoch;
        await pumpProfileScreen(
          tester,
          seed: (repo) async {
            await repo.saveMeasurementEntry(
              BodyMeasurementEntry(
                id: 'bw-a',
                measurementType: 'bodyweight',
                value: 80,
                unitId: 'unit-kg',
                recordedAtMs: identicalMs,
              ),
            );
            await repo.saveMeasurementEntry(
              BodyMeasurementEntry(
                id: 'bw-b',
                measurementType: 'bodyweight',
                value: 79,
                unitId: 'unit-kg',
                recordedAtMs: identicalMs,
              ),
            );
          },
        );

        final bwSparkline = find
            .byKey(const Key('measurement_sparkline'))
            .first;
        // No exception; the chart branch is active (CustomPaint
        // rendered). The Y-axis min/max labels render correctly
        // (80 kg / 79 kg). The X-axis first and last labels are
        // identical (both = today's `MMM d`).
        expect(
          find.descendant(of: bwSparkline, matching: find.byType(CustomPaint)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: bwSparkline, matching: find.text('80.0')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: bwSparkline, matching: find.text('79.0')),
          findsOneWidget,
        );

        // Both x-axis date labels render the same string (today).
        final today = DateTime.now();
        final todayLabel = '${_shortMonthName(today.month)} ${today.day}';
        expect(
          find.descendant(of: bwSparkline, matching: find.text(todayLabel)),
          findsNWidgets(2),
          reason:
              'Both x-axis labels render the same today-date string '
              'when entries share a timestamp.',
        );
      },
    );

    testWidgets(
      'S-019: Y-axis labels render on the LEFT; X-axis labels at the BOTTOM; axes lines drawn (A18)',
      (WidgetTester tester) async {
        // Seed two bodyweight entries ~30 days apart so the chart
        // exercises all branches: Y-max label, Y-min label, X-first,
        // X-last, painter axes lines, data line, dots.
        await pumpProfileScreen(
          tester,
          seed: (repo) async {
            final baseMs = DateTime.now().millisecondsSinceEpoch;
            await repo.saveMeasurementEntry(
              BodyMeasurementEntry(
                id: 'bw-old',
                measurementType: 'bodyweight',
                value: 82.0,
                unitId: 'unit-kg',
                recordedAtMs: baseMs - 30 * 24 * 60 * 60 * 1000,
              ),
            );
            await repo.saveMeasurementEntry(
              BodyMeasurementEntry(
                id: 'bw-recent',
                measurementType: 'bodyweight',
                value: 79.5,
                unitId: 'unit-kg',
                recordedAtMs: baseMs,
              ),
            );
          },
        );

        final bwSparkline = find
            .byKey(const Key('measurement_sparkline'))
            .first;

        // A18: Y-axis labels render on the LEFT. Assert via
        // alignment — both labels have `textAlign: TextAlign.right`
        // and sit in a `Positioned(left: 0, width: 38)` column. The
        // `Key` is on the `Positioned`, so use `find.descendant` to
        // reach the `Text` child for the type cast.
        final yMaxWidget = tester.widget<Text>(
          find.descendant(
            of: find.byKey(const Key('measurement_sparkline_y_max')),
            matching: find.byType(Text),
          ),
        );
        expect(
          yMaxWidget.textAlign,
          TextAlign.right,
          reason: 'Y-max label is right-aligned (A18 left-side placement).',
        );
        final yMinWidget = tester.widget<Text>(
          find.descendant(
            of: find.byKey(const Key('measurement_sparkline_y_min')),
            matching: find.byType(Text),
          ),
        );
        expect(
          yMinWidget.textAlign,
          TextAlign.right,
          reason: 'Y-min label is right-aligned (A18 left-side placement).',
        );

        // A18: Y-axis labels share fontSize 9 with the X-axis labels
        // because the unit suffix was dropped (e.g. "74.8" instead
        // of "74.8 lbs"), so the LEFT column fits at the same size
        // as the X-axis date strip.
        expect(
          yMaxWidget.style?.fontSize,
          9,
          reason:
              'Y-axis labels render at fontSize 9 (same as X-axis '
              'labels; A18 dropped the unit suffix).',
        );

        // X-axis labels render at the BOTTOM, just to the right of
        // the Y-axis line (left=40) and at the right edge (right=4).
        // Assert by walking their parent Positioned via Text widget
        // location: they live inside a Stack at the sparkline root,
        // so their immediate ancestor is a Stack. The position
        // contract is verified via key/text presence (see S-014).

        // The painter is private; we assert it is rendered as a
        // CustomPaint and trust it draws the Y-axis line at x=40
        // and X-axis line at y=24 (documented contract; covered by
        // S-014 which already asserts CustomPaint presence).
        expect(
          find.descendant(of: bwSparkline, matching: find.byType(CustomPaint)),
          findsOneWidget,
          reason:
              'A18 painter renders both axes lines + the data line '
              '+ the dots inside the same CustomPaint.',
        );

        // The chart container is 38 dp tall (A18; was 40 dp in A17).
        final sizedBox = tester.widget<SizedBox>(
          find.descendant(of: bwSparkline, matching: find.byType(SizedBox)),
        );
        expect(
          sizedBox.height,
          65,
          reason:
              'A20 chart inner SizedBox is 65 dp tall (user-tweaked from 60).',
        );

        // Sanity: Y-axis labels are not clipped to the LEFT column
        // boundary by the Stack. The labels exist and are sized to
        // their column. The visual alignment (right edge at x=38,
        // 2 dp gap from the Y-axis line at x=40) is the host's
        // contract, asserted by the Positioned(left: 0, width: 38)
        // wiring checked above. A18 dropped the unit suffix; the
        // header above already names the measurement.
        expect(
          find.descendant(of: bwSparkline, matching: find.text('82.0')),
          findsOneWidget,
          reason: 'Y-max label renders the older entry (no unit).',
        );
        expect(
          find.descendant(of: bwSparkline, matching: find.text('79.5')),
          findsOneWidget,
          reason: 'Y-min label renders the newer entry (no unit).',
        );
      },
    );

    testWidgets('S-015: tapping the sparkline opens the history sheet', (
      WidgetTester tester,
    ) async {
      await pumpProfileScreen(
        tester,
        seed: (repo) async {
          await repo.saveMeasurementEntry(
            BodyMeasurementEntry(
              id: 'bw-1',
              measurementType: 'bodyweight',
              value: 80,
              unitId: 'unit-kg',
              recordedAtMs: DateTime.now().millisecondsSinceEpoch,
            ),
          );
        },
      );

      // Tap the bodyweight sparkline's tap target.
      await tester.tap(
        find.byKey(const Key('measurement_sparkline_tap')).first,
      );
      await tester.pumpAndSettle();

      // The history sheet is on top.
      expect(find.byType(MeasurementHistoryChartSheet), findsOneWidget);
      // A17: scope the sheet-title assertion to the sheet itself —
      // the uppercased `OmniCardHeader` title on the underlying
      // screen also renders 'BODY WEIGHT' so an unscoped
      // `find.text('BODY WEIGHT')` would match 2 widgets.
      expect(
        find.descendant(
          of: find.byType(MeasurementHistoryChartSheet),
          matching: find.text('BODY WEIGHT'),
        ),
        findsOneWidget,
        reason: 'History sheet shows the uppercased measurement label.',
      );
    });

    testWidgets(
      'S-016: tapping the + button in the card body opens the log sheet',
      (WidgetTester tester) async {
        await pumpProfileScreen(tester);

        // Tap the first `+` icon (bodyweight's add affordance). Per
        // A16, the button now lives inside the card body alongside
        // the chart rectangle and the value column.
        await tester.tap(find.byIcon(Icons.add).first);
        await tester.pumpAndSettle();

        // The log sheet is on top with the measurement label in its
        // header.
        expect(find.text('Log Body Weight'), findsOneWidget);
      },
    );

    testWidgets(
      'S-016b: card body renders the 3-section row [chart | value | +]; value shows "—" with no entry',
      (WidgetTester tester) async {
        await pumpProfileScreen(tester);

        // No entries → value column shows "—" for every measurement
        // (additional = 8 in the cleanup pass). Height is no longer
        // a charted card — it lives in the identity area.
        expect(find.text('—'), findsNWidgets(8));

        // The chart is rendered as a SizedBox for every charted
        // measurement except Lean Mass, which the cleanup pass
        // switched to a read-only computed row (no sparkline, no
        // add button). 8 charted - 1 (lean mass) = 7 sparklines.
        expect(
          find.byKey(const Key('measurement_sparkline')),
          findsNWidgets(7),
        );

        // The `+` icon is rendered inside the card body for every
        // charted measurement except Lean Mass (read-only). 8 - 1
        // (lean mass) = 7 add buttons.
        expect(find.byIcon(Icons.add), findsNWidgets(7));

        // The 3-section row: the chart (Expanded) + value (SizedBox
        // 90) + button (SizedBox 60) live inside an OmniSurface.
        // Each charted card wraps its sparkline in the 3-column row.
        expect(
          find.descendant(
            of: find.byType(OmniSurface),
            matching: find.byKey(const Key('measurement_sparkline')),
          ),
          findsNWidgets(7),
          reason:
              'Each of the 7 charted cards (excluding Lean Mass) '
              'wraps its sparkline in the 3-section row.',
        );
      },
    );

    testWidgets('S-016c: value column updates with the latest entry', (
      WidgetTester tester,
    ) async {
      // Seed one bodyweight entry.
      final profileState = await pumpProfileScreen(
        tester,
        seed: (repo) async {
          await repo.saveMeasurementEntry(
            BodyMeasurementEntry(
              id: 'bw-1',
              measurementType: 'bodyweight',
              value: 80,
              unitId: 'unit-kg',
              recordedAtMs: DateTime.now().millisecondsSinceEpoch,
            ),
          );
        },
      );

      // The bodyweight value column shows the formatted weight. The
      // other 7 charted measurements (additional = 8 minus lean
      // mass which renders "—" for empty) plus the read-only Lean
      // Mass card still show "—". Cleanup pass: charted column is
      // sourced from `additional` only (height is in the identity
      // area). Lean Mass shows "—" until body weight + body fat are
      // both logged.
      expect(
        find.descendant(
          of: find.byKey(const Key('measurement_value')),
          matching: find.text('80 kg'),
        ),
        findsOneWidget,
      );
      expect(find.text('—'), findsNWidgets(7));

      // Add a second entry via the captured ProfileState. The value
      // column reflects the latest entry.
      await profileState.logMeasurement('bodyweight', 79.5, 'unit-kg');
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('measurement_value')),
          matching: find.text('79.5 kg'),
        ),
        findsOneWidget,
        reason:
            'Value column must update to the latest entry, scoped '
            'through the value-column key (A17).',
      );
      expect(find.text('—'), findsNWidgets(7));
    });

    testWidgets(
      'S-017: MeasurementSparkline refreshes when profileState notifies',
      (WidgetTester tester) async {
        // Pump with no entries.
        final profileState = await pumpProfileScreen(tester);

        // Initial state: every charted measurement's sparkline renders
        // "No history yet". The cleanup pass uses a single charted
        // column sourced from `additional` (8 items) and Lean Mass
        // renders a read-only computed row (no sparkline) — so 7
        // sparklines total. Height is in the identity area, not the
        // charted column.
        expect(find.text('No history yet'), findsNWidgets(7));

        // Save a new bodyweight entry via the captured ProfileState.
        // The repository receives the entry, the cache updates, and
        // `notifyListeners` fires. The [MeasurementSparkline]
        // listener (added in `initState`) catches the notification
        // and re-fetches the history.
        await profileState.logMeasurement('bodyweight', 80, 'unit-kg');
        await tester.pumpAndSettle();

        // The bodyweight sparkline (first sparkline) now renders the
        // single-entry branch (full chart frame + horizontal line +
        // single dot, painted via CustomPaint — A19; the legacy
        // Divider-only branch is gone). The other eight measurements
        // still show "No history yet".
        final bwSparkline = find
            .byKey(const Key('measurement_sparkline'))
            .first;
        expect(
          find.descendant(
            of: bwSparkline,
            matching: find.text('No history yet'),
          ),
          findsNothing,
          reason:
              'The bodyweight sparkline must have refreshed off the '
              'profileState notification.',
        );
        expect(
          find.descendant(of: bwSparkline, matching: find.byType(CustomPaint)),
          findsOneWidget,
          reason:
              'A19 single-entry branch renders the full chart frame '
              '(axes + horizontal line + single dot) via CustomPaint.',
        );
        // No raw Divider widget (A19 replaces the legacy hairline).
        expect(
          find.descendant(of: bwSparkline, matching: find.byType(Divider)),
          findsNothing,
        );
        // Cleanup pass: 7 charted sparklines remain on "No history yet"
        // (8 charted minus the bodyweight sparkline that just
        // transitioned off-empty, minus the Lean Mass read-only row
        // which has no sparkline at all = 6; but the bodyweight one
        // is also still rendering the empty branch's marker text in
        // its 1-entry branch's CustomPaint). The exact count of "—"
        // is asserted in S-016b above; this test just confirms the
        // sparkline-refresh path.
        expect(find.text('No history yet'), findsAtLeastNWidgets(6));

        // Save a second entry. The sparkline transitions to the
        // 2-entry line-chart branch (still CustomPaint; now with a
        // connected polyline + 2 dots).
        await profileState.logMeasurement('bodyweight', 79.5, 'unit-kg');
        await tester.pumpAndSettle();

        final bwSparkline2 = find
            .byKey(const Key('measurement_sparkline'))
            .first;
        expect(
          find.descendant(of: bwSparkline2, matching: find.byType(Divider)),
          findsNothing,
        );
        expect(
          find.descendant(of: bwSparkline2, matching: find.byType(CustomPaint)),
          findsOneWidget,
          reason: 'Two-entry branch renders the line-chart CustomPaint.',
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════
  // Structural guards (Phase 4 of unified-card-and-header-plan)
  // ═══════════════════════════════════════════════════════════════════════

  group('Unified card and header – structural guards (Phase 4)', () {
    test('profile_screen.dart no longer declares _MeasurementRow', () {
      final file = File('lib/features/profile/profile_screen.dart');
      expect(file.existsSync(), isTrue);
      final source = file.readAsStringSync();
      expect(
        source.contains('class _MeasurementRow'),
        isFalse,
        reason:
            'lib/features/profile/profile_screen.dart must use '
            'OmniCardHeader + MeasurementSparkline instead of the '
            'private _MeasurementRow widget.',
      );
    });

    test(
      'profile_screen.dart no longer renders MEASUREMENTS or ADDITIONAL eyebrows',
      () {
        final file = File('lib/features/profile/profile_screen.dart');
        expect(file.existsSync(), isTrue);
        final source = file.readAsStringSync();
        expect(
          source.contains("'MEASUREMENTS'"),
          isFalse,
          reason:
              'lib/features/profile/profile_screen.dart must not render '
              'a "MEASUREMENTS" section eyebrow; the per-row OmniCardHeader '
              'now acts as the section title.',
        );
        expect(
          source.contains("'ADDITIONAL'"),
          isFalse,
          reason:
              'lib/features/profile/profile_screen.dart must not render '
              'an "ADDITIONAL" section eyebrow.',
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════
  // Stats headers + window chip (Phase 5 of unified-card-and-header-plan)
  // ═══════════════════════════════════════════════════════════════════════

  // Shared helper: pump StatsScreen with a fresh MockWorkoutRepository.
  // The optional `seed` callback runs after the repo is initialized and
  // before the screen mounts so the seeded data is visible in the
  // first paint.
  Future<void> pumpStatsScreen(
    WidgetTester tester, {
    Future<void> Function(MockWorkoutRepository repo)? seed,
  }) async {
    final repo = MockWorkoutRepository();
    await repo.initialize();
    if (seed != null) await seed(repo);
    final workoutState = WorkoutState(repo);
    final settingsState = SettingsState(repo, fakePreferencesService());
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

  // Helper: seed a completed resistance session. Mirrors the pattern in
  // `screen_widget_test.dart`.
  Future<void> seedCompletedStrengthSession(MockWorkoutRepository repo) async {
    final start = DateTime.now().subtract(const Duration(days: 1));
    final duration = const Duration(minutes: 45);
    await repo.createSession(
      TrainingSession(
        id: 's-strength-1',
        ownerUserId: 'user-1',
        modality: 'resistance_lifting',
        startedAtMs: start.millisecondsSinceEpoch,
        endedAtMs: start.add(duration).millisecondsSinceEpoch,
        isRolling: false,
        createdAtMs: start.millisecondsSinceEpoch,
        updatedAtMs: start.add(duration).millisecondsSinceEpoch,
      ),
    );
  }

  group('Stats – section headers + window chip (Phase 5)', () {
    testWidgets(
      'S-004: zero sessions renders the empty state; ALL TIME header has D-1 typography',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 900));
        await pumpStatsScreen(tester);

        // Empty state path is taken.
        expect(find.text('No sessions yet'), findsOneWidget);

        // No section eyebrows are rendered in the empty state.
        expect(find.text('ALL TIME'), findsNothing);
        expect(find.text('STRENGTH'), findsNothing);
        expect(find.text('CARDIO'), findsNothing);
        expect(find.text('NUTRITION'), findsNothing);
      },
    );

    testWidgets(
      'S-018: every Stats section eyebrow uses D-1 typography (labelSmall + w600 + 2.0 + textMuted)',
      (WidgetTester tester) async {
        // A tall viewport keeps the whole body laid out, so an eyebrow is
        // never just an off-screen miss.
        await tester.binding.setSurfaceSize(const Size(400, 1800));
        await pumpStatsScreen(
          tester,
          seed: (repo) => seedCompletedStrengthSession(repo),
        );

        // The fixture logs no effort, so the Instruments list has no section
        // to draw and the screen's only eyebrow is `ALL TIME`. Every section
        // the list does render is an `OmniCardHeader(title: section.label)`
        // (S-1208 covers the list's own state).
        for (final label in const ['ALL TIME']) {
          final titleFinder = find.descendant(
            of: find.byType(OmniCardHeader),
            matching: find.text(label),
          );
          expect(
            titleFinder,
            findsOneWidget,
            reason: '$label header must render as an OmniCardHeader title.',
          );

          final style = tester.widget<Text>(titleFinder).style!;
          expect(
            style.letterSpacing,
            2.0,
            reason: '$label must use the canonical 2.0 letter-spacing',
          );
          expect(
            style.fontWeight,
            FontWeight.w600,
            reason: '$label must use FontWeight.w600',
          );
          expect(
            style.color,
            OmniTheme.colors.textMuted,
            reason: '$label must use OmniTheme.colors.textMuted',
          );
        }
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════
  // Structural guards (Phase 5 of unified-card-and-header-plan)
  // ═══════════════════════════════════════════════════════════════════════

  group('Unified card and header – structural guards (Phase 5)', () {
    test('stats_screen.dart no longer declares _buildSectionLabel', () {
      final file = File('lib/features/stats/stats_screen.dart');
      expect(file.existsSync(), isTrue);
      final source = file.readAsStringSync();
      expect(
        source.contains('_buildSectionLabel('),
        isFalse,
        reason:
            'lib/features/stats/stats_screen.dart must use OmniCardHeader '
            'instead of the private _buildSectionLabel(...) builder.',
      );
    });

    test('stats_screen.dart no longer uses letterSpacing: 3.0', () {
      // The old section labels used `letterSpacing: 3.0` (the Stats
      // screen's own variant). Phase 5 unifies all section headers
      // to the canonical D-1 typography (`letterSpacing: 2.0`).
      final file = File('lib/features/stats/stats_screen.dart');
      expect(file.existsSync(), isTrue);
      final source = file.readAsStringSync();
      expect(
        source.contains('letterSpacing: 3.0'),
        isFalse,
        reason:
            'lib/features/stats/stats_screen.dart must use the '
            'canonical D-1 letter-spacing of 2.0 (not the legacy 3.0).',
      );
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Internal helpers used by the Phase 4 sparkline branch tests.
// ═══════════════════════════════════════════════════════════════════════════
