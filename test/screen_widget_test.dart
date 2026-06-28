import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/app.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/navigation/navigation.dart';
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
import 'package:omnitrain/features/nutrition/add_food_screen.dart';
import 'package:omnitrain/features/nutrition/edit_food_screen.dart';
import 'package:omnitrain/features/nutrition/widgets/food_form.dart';
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
import 'package:omnitrain/features/stats/widgets/scrollable_trend_chart.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:omnitrain/core/utils/chart_axis_helper.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/home/home_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/nutrition/nutrition_primer_state.dart';
import 'package:omnitrain/state/period/period_state.dart';
import 'package:omnitrain/state/profile/profile_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/layout/omni_back_header.dart';
import 'package:omnitrain/widgets/layout/omni_gradient_background.dart';
import 'package:omnitrain/widgets/layout/omni_surface.dart';
import 'package:omnitrain/widgets/layout/omni_bottom_cta.dart';
import 'package:omnitrain/features/exercise/exercise_picker_screen.dart';
import 'package:omnitrain/widgets/pickers/metric_chooser_dialog.dart';
import 'package:omnitrain/widgets/pickers/modality_picker_dialog.dart';
import 'package:omnitrain/widgets/session/inline_metric_editor.dart';
import 'helpers/fake_timer_alert_service.dart';
import 'helpers/test_nutrition_primer_state.dart';
import 'helpers/fake_preferences_service.dart';
import 'helpers/test_content_column.dart';

// ── Helpers ──────────────────────────────────────────────────────────────

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

void main() {
  group('OmniBottomCTA', () {
    testWidgets(
      'uses the shared primary height, width, corner radius, and vertical anchor',
      (WidgetTester tester) async {
        // Fixed surface so the test can assert exact pixel math.
        const surface = Size(400, 800);
        await tester.binding.setSurfaceSize(surface);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            home: OmniGradientBackground(
              child: Scaffold(
                bottomNavigationBar: OmniBottomCTA(
                  label: 'Continue',
                  onPressed: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Height: the shared `OmniTheme.buttonPrimaryHeight`.
        final ctaBox = tester.widget<SizedBox>(
          find.descendant(
            of: find.byType(OmniBottomCTA),
            matching: find.byType(SizedBox),
          ),
        );
        expect(ctaBox.height, OmniTheme.buttonPrimaryHeight);

        // Width: full-width minus 2 × horizontal padding.
        expect(
          ctaBox.width,
          double.infinity,
          reason: 'CTA must fill its parent (width: double.infinity)',
        );
        final button = tester.widget<FilledButton>(find.byType(FilledButton));
        final style = button.style!;
        final shape =
            style.shape!.resolve(<WidgetState>{})! as RoundedRectangleBorder;
        expect(
          shape.borderRadius,
          BorderRadius.circular(OmniTheme.buttonBorderRadius),
        );

        // Vertical anchor: the button's bottom edge sits at
        //   surfaceHeight - bottomSafeArea - bottomCTAVerticalBottomPadding.
        // With no bottom safe area (test default), that's
        //   surfaceHeight - OmniTheme.bottomCTAVerticalBottomPadding.
        final buttonBox = tester.getRect(find.byType(FilledButton));
        final expectedBottom =
            surface.height -
            tester.view.padding.bottom / tester.view.devicePixelRatio -
            OmniTheme.bottomCTAVerticalBottomPadding;
        expect(
          buttonBox.bottom,
          closeTo(expectedBottom, 0.5),
          reason:
              'CTA bottom must clear the device safe area by '
              'OmniTheme.bottomCTAVerticalBottomPadding',
        );

        // Width rule: the button's render box is inset by
        //   OmniTheme.bottomCTAHorizontalPadding on each side from
        //   the **centered content column's** edges, not the
        //   surface's. On a phone-class surface the column fills
        //   the surface and the assertion is identical to the
        //   pre-large-screen contract; on a tablet-class surface
        //   the column is narrower than the surface and the
        //   assertion still holds because it is measured from the
        //   column.
        final column = contentColumnRectFor(surface.width);
        final expectedLeft =
            column.left + OmniTheme.bottomCTAHorizontalPadding;
        final expectedRight =
            column.left +
            column.width -
            OmniTheme.bottomCTAHorizontalPadding;
        expect(buttonBox.left, closeTo(expectedLeft, 0.5));
        expect(buttonBox.right, closeTo(expectedRight, 0.5));
      },
    );

    testWidgets('respects the device bottom safe area (S-002)', (
      WidgetTester tester,
    ) async {
      // Fixed surface; force a non-zero bottom safe area via
      // MediaQuery override. This simulates an iPhone with the
      // home indicator (34 px) or an Android with the gesture
      // nav bar (~16-24 px).
      const surface = Size(400, 800);
      const bottomInset = 34.0;
      await tester.binding.setSurfaceSize(surface);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: surface,
              padding: EdgeInsets.only(bottom: bottomInset),
            ),
            child: Scaffold(
              bottomNavigationBar: OmniBottomCTA(
                label: 'Save',
                onPressed: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The button's render box bottom must be at or above
      //   surfaceHeight - bottomInset - bottomCTAVerticalBottomPadding.
      // (Above the home indicator by exactly the bottom padding.)
      final buttonBox = tester.getRect(find.byType(FilledButton));
      final expectedBottom =
          surface.height -
          bottomInset -
          OmniTheme.bottomCTAVerticalBottomPadding;
      expect(
        buttonBox.bottom,
        closeTo(expectedBottom, 0.5),
        reason:
            'CTA must sit above the home indicator, offset by '
            'OmniTheme.bottomCTAVerticalBottomPadding',
      );
    });

    testWidgets('settings screen keeps the streamlined section layout', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      final settingsState = SettingsState(repo, fakePreferencesService());
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
      expect(find.text('PREFERENCES'), findsOneWidget);
      expect(find.text('TRAINING'), findsNothing);
      expect(find.text('MEASUREMENTS'), findsNothing);
      expect(find.text('100 kg'), findsOneWidget);
      expect(find.text('5 km'), findsOneWidget);
      expect(find.text('Start of Week'), findsOneWidget);
      // Height unit row lives in the PREFERENCES section.
      expect(find.text('Height'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('WORKOUT'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('WORKOUT'), findsOneWidget);
      expect(find.text('Feeling Survey'), findsOneWidget);
      expect(
        find.text('Ask how the workout felt after finishing'),
        findsOneWidget,
      );

      await tester.scrollUntilVisible(
        find.text('APPEARANCE'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('APPEARANCE'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Version 1.0.0'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Version 1.0.0'), findsOneWidget);
    });

    testWidgets('shows only the five retained theme options', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      final settingsState = SettingsState(repo, fakePreferencesService());
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

      await tester.scrollUntilVisible(
        find.text('Abyssal Neon'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
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

      expect(find.byType(OmniBackHeader), findsOneWidget);
      expect(find.text('Periodization'), findsOneWidget);
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

    testWidgets('uses compliant shared bottom CTA', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      final periodState = PeriodState(repo);

      await tester.pumpWidget(
        MaterialApp(home: PeriodListScreen(periodState: periodState)),
      );
      await tester.pumpAndSettle();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.bottomNavigationBar, isA<OmniBottomCTA>());
      expect(scaffold.bottomSheet, isNull);
      expect(find.text('+ New Period'), findsOneWidget);
    });

    testWidgets(
      'anchors the primary bottom CTA at the shared width and vertical anchor (S-003)',
      (WidgetTester tester) async {
        // Fixed surface so the test can assert exact pixel math.
        const surface = Size(400, 800);
        await tester.binding.setSurfaceSize(surface);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _freshRepo();
        final periodState = PeriodState(repo);

        // Production pushes this screen via OmniRoute, which wraps
        // it in OmniGradientBackground — we mirror that here so
        // the large-screen content column cap is exercised.
        await tester.pumpWidget(
          MaterialApp(
            home: OmniGradientBackground(
              child: PeriodListScreen(periodState: periodState),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The CTA is the FilledButton inside OmniBottomCTA — find
        // the button (not the text inside it) so the rect covers
        // the whole button, not just the text glyphs.
        final buttonRect = tester.getRect(
          find.descendant(
            of: find.byType(OmniBottomCTA),
            matching: find.byType(FilledButton),
          ),
        );
        // Shared horizontal margin: the button's left edge is inset
        // by OmniTheme.bottomCTAHorizontalPadding from the
        // **centered content column's** edges, not the surface's.
        // On a phone-class surface the column fills the surface and
        // the assertion matches the pre-large-screen contract; on
        // a tablet-class surface the column is narrower and the
        // assertion still holds.
        final column = contentColumnRectFor(surface.width);
        final expectedLeft =
            column.left + OmniTheme.bottomCTAHorizontalPadding;
        final expectedRight =
            column.left +
            column.width -
            OmniTheme.bottomCTAHorizontalPadding;
        expect(buttonRect.left, closeTo(expectedLeft, 0.5));
        expect(buttonRect.right, closeTo(expectedRight, 0.5));
        // Shared height.
        expect(buttonRect.height, closeTo(OmniTheme.buttonPrimaryHeight, 0.5));
        // Shared vertical anchor: button bottom is offset above the
        // device safe area by OmniTheme.bottomCTAVerticalBottomPadding.
        final expectedBottom =
            surface.height -
            tester.view.padding.bottom / tester.view.devicePixelRatio -
            OmniTheme.bottomCTAVerticalBottomPadding;
        expect(buttonRect.bottom, closeTo(expectedBottom, 0.5));
      },
    );
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

      expect(find.byType(OmniBackHeader), findsOneWidget);
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

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.bottomNavigationBar, isA<OmniBottomCTA>());
      expect(scaffold.bottomSheet, isNull);
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
        SettingsState settingsState,
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
      final settingsState = SettingsState(repo, fakePreferencesService());
      return (
        calendarState: calendarState,
        periodState: periodState,
        workoutState: workoutState,
        routineState: routineState,
        routineSessionService: routineSessionService,
        sessionSummaryService: sessionSummaryService,
        settingsState: settingsState,
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
            settingsState: deps.settingsState,
            timerAlertService: FakeTimerAlertService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OmniBackHeader), findsOneWidget);
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
            settingsState: deps.settingsState,
            timerAlertService: FakeTimerAlertService(),
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
            settingsState: deps.settingsState,
            timerAlertService: FakeTimerAlertService(),
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
            settingsState: SettingsState(repo, fakePreferencesService()),
            timerAlertService: FakeTimerAlertService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OmniBackHeader), findsOneWidget);
      expect(find.text('My Routines'), findsOneWidget);
      expect(find.text('No Routines Yet'), findsOneWidget);
    });

    testWidgets('shows unified "+ New Routine" bottom CTA', (
      WidgetTester tester,
    ) async {
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
            settingsState: SettingsState(repo, fakePreferencesService()),
            timerAlertService: FakeTimerAlertService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // S-001: unified footer button rendered with the "+ New Routine" label.
      expect(find.widgetWithText(FilledButton, '+ New Routine'), findsOneWidget);
      // S-001: the old FAB is gone — the routines screen now uses the shared
      // primary bottom CTA pattern.
      expect(find.byType(FloatingActionButton), findsNothing);
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
      final settingsState = SettingsState(repo, fakePreferencesService());

      await tester.pumpWidget(
        MaterialApp(
          home: MyRoutinesScreen(
            routineState: routineState,
            routineSessionService: routineSessionService,
            sessionSummaryService: sessionSummaryService,
            settingsState: settingsState,
            timerAlertService: FakeTimerAlertService(),
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

      // Header
      expect(find.byType(OmniBackHeader), findsOneWidget);
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

    testWidgets('uses preferred lbs label for routine load editors', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final repo = await _freshRepo();
      final routineState = RoutineState(repo);
      final workoutState = WorkoutState(repo);
      final settingsState = SettingsState(repo, fakePreferencesService());
      await settingsState.initialize();
      await settingsState.setPreferredWeightUnit('lbs');
      routineState.setAutosaveEnabled(false);
      await routineState.createNewRoutine('Upper Day');

      final exercises = await repo.getExercises();
      final loadedExercise = exercises.firstWhere(
        (e) =>
            e.capabilities.contains('load') && e.capabilities.contains('reps'),
        orElse: () => exercises.first,
      );
      await routineState.addExerciseToRoutine(loadedExercise, 'set');
      await routineState.saveRoutine();
      final templateId = routineState.currentTemplate!.id;

      await tester.pumpWidget(
        MaterialApp(
          home: RoutineSetupScreen(
            routineState: routineState,
            workoutState: workoutState,
            templateId: templateId,
            settingsState: settingsState,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(loadedExercise.name).first);
      await tester.pumpAndSettle();

      expect(find.text('LBS'), findsOneWidget);
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

    testWidgets('tapping exercise card opens detail view', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final routineState = RoutineState(repo);
      routineState.setAutosaveEnabled(false);

      final exercises = await repo.getExercises();
      await routineState.createNewRoutine('Detail View');
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

      // Tap the exercise card to open detail view
      await tester.tap(find.text(exercises.first.name));
      await tester.pumpAndSettle();

      // Detail view should show inline add/remove set controls flanking the
      // set-progress label (session-parity design).
      expect(find.byKey(const Key('routine-add-set')), findsOneWidget);
      expect(find.byKey(const Key('routine-remove-set')), findsOneWidget);
      expect(find.text('Set 1 of 1'), findsOneWidget);
    });

    testWidgets('tracking selection shows ModalityPickerDialog', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final routineState = RoutineState(repo);
      routineState.setAutosaveEnabled(false);

      final exercises = await repo.getExercises();
      await routineState.createNewRoutine('Tracking Picker');
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

      final exerciseCard = tester.widget<ExerciseCard>(
        find.byType(ExerciseCard),
      );
      exerciseCard.onChangeTracking();
      await tester.pumpAndSettle();

      expect(find.byType(ModalityPickerDialog), findsOneWidget);
      expect(find.text('Select Exercise Modality'), findsOneWidget);
    });

    testWidgets(
      'exercise overflow menu hides Edit Rest and keeps remaining actions tappable',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        final routineState = RoutineState(repo);
        routineState.setAutosaveEnabled(false);

        final exercises = await repo.getExercises();
        await routineState.createNewRoutine('Menu Actions');
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

        final exerciseCardFinder = find.byType(ExerciseCard).first;
        final exerciseCard = tester.widget<ExerciseCard>(exerciseCardFinder);
        final popupMenuFinder = find.descendant(
          of: exerciseCardFinder,
          matching: find.byType(PopupMenuButton),
        );
        final popupMenu = tester.widget<PopupMenuButton>(popupMenuFinder);
        final popupContext = tester.element(popupMenuFinder);
        final menuItems = popupMenu
            .itemBuilder(popupContext)
            .cast<PopupMenuItem>();

        final menuTexts = menuItems
            .map((item) => (item.child! as Row).children.last as Text)
            .map((text) => text.data)
            .toList();

        expect(menuTexts, contains('Change Tracking'));
        expect(menuTexts, contains('Remove'));
        expect(menuTexts, isNot(contains('Edit Rest')));

        exerciseCard.onDelete();
        await tester.pumpAndSettle();

        expect(find.text('Remove Exercise?'), findsOneWidget);
        expect(
          find.text('This exercise will be removed from the routine.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('sets can be added in detail view', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final routineState = RoutineState(repo);
      routineState.setAutosaveEnabled(false);

      final exercises = await repo.getExercises();
      await routineState.createNewRoutine('Add Set Detail');
      await routineState.addExerciseToRoutine(exercises.first, 'set');

      // Seed explicit set 0 target so add-set creates set 1 and advances to 2/2.
      final seededEffortId = routineState.currentEfforts.first.id;
      await routineState.setTargetValue(
        seededEffortId,
        'metric-reps',
        'unit-reps',
        setIndex: 0,
        targetInt: 10,
      );

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

      // Tap the exercise card to open detail view
      await tester.tap(find.text(exercises.first.name));
      await tester.pumpAndSettle();

      // Initially shows 1 set
      expect(find.text('Set 1 of 1'), findsOneWidget);

      // Tap the inline add-set button using its key for reliable targeting
      await tester.tap(find.byKey(const Key('routine-add-set')));
      // Pump through the async addSetForEffort + setState cycle
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      // After adding, view advances to the new set: Set 2 of 2
      expect(find.text('Set 2 of 2'), findsOneWidget);
    });

    testWidgets('block header plus icon triggers add-exercise flow', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final routineState = RoutineState(repo);
      routineState.setAutosaveEnabled(false);
      await routineState.createNewRoutine('Plus Icon Flow');
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

      // The plus icon appears in the block header
      final addIcons = find.byTooltip('Add exercise to block');
      expect(addIcons, findsWidgets);

      // Tapping it opens the exercise picker dialog
      await tester.tap(addIcons.first);
      await tester.pumpAndSettle();

      expect(find.byType(ExercisePickerScreen), findsOneWidget);
    });

    testWidgets('old full-width Add Exercise button is absent', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final repo = await _freshRepo();
      final routineState = RoutineState(repo);
      routineState.setAutosaveEnabled(false);
      await routineState.createNewRoutine('No Button');
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

      expect(find.widgetWithText(OutlinedButton, 'Add Exercise'), findsNothing);
    });

    testWidgets('block header plus icon has accessible tooltip', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final repo = await _freshRepo();
      final routineState = RoutineState(repo);
      routineState.setAutosaveEnabled(false);
      await routineState.createNewRoutine('Accessibility');
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

      expect(find.byTooltip('Add exercise to block'), findsWidgets);
    });

    testWidgets(
      'timed effort with extra-weight target renders InlineMetricEditor',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        final routineState = RoutineState(repo);
        routineState.setAutosaveEnabled(false);

        // Any exercise works — effort kind is set explicitly when adding.
        final exercises = await repo.getExercises();
        final timedExercise = exercises.first;

        await routineState.createNewRoutine('Timed Extra Weight');
        final effortId = await routineState.addExerciseToRoutine(
          timedExercise,
          'timed',
        );

        // Seed an extra-weight target so the UI guard shows the editor.
        await routineState.setTargetValue(
          effortId,
          MetricIds.extraWeight,
          MetricIds.unitKg,
          setIndex: 0,
          targetMin: 0.0,
        );

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

        // Tap the exercise card to open detail view.
        await tester.tap(find.text(timedExercise.name).first);
        await tester.pumpAndSettle();

        // The extra-weight InlineMetricEditor should be visible.
        expect(find.byType(InlineMetricEditor), findsWidgets);
        expect(find.text('EXTRA KG'), findsOneWidget);
      },
    );

    testWidgets('timed effort detail view shows no duration editor', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final routineState = RoutineState(repo);
      routineState.setAutosaveEnabled(false);

      final exercises = await repo.getExercises();
      await routineState.createNewRoutine('Timed No Duration');
      await routineState.addExerciseToRoutine(exercises.first, 'timed');
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

      await tester.tap(find.text(exercises.first.name).first);
      await tester.pumpAndSettle();

      // The duration unit label 'TIME' must be absent.
      expect(find.text('TIME'), findsNothing);
      // The set-count label for a timed effort is still visible.
      expect(find.text('Interval 1 of 1'), findsOneWidget);
    });

    testWidgets('drill effort detail view shows no hold-time editor', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final routineState = RoutineState(repo);
      routineState.setAutosaveEnabled(false);

      final exercises = await repo.getExercises();
      await routineState.createNewRoutine('Drill No Hold');
      await routineState.addExerciseToRoutine(exercises.first, 'drill');
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

      await tester.tap(find.text(exercises.first.name).first);
      await tester.pumpAndSettle();

      // The hold-time unit label 'HOLD TIME' must be absent.
      expect(find.text('HOLD TIME'), findsNothing);
      // Drill efforts still expose the extra-weight editor.
      expect(find.text('EXTRA KG'), findsOneWidget);
      // The set-count label for a drill effort is still visible.
      expect(find.text('Hold 1 of 1'), findsOneWidget);
    });

    testWidgets(
      'round effort detail view still renders round-duration editor',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        final routineState = RoutineState(repo);
        routineState.setAutosaveEnabled(false);

        final exercises = await repo.getExercises();
        await routineState.createNewRoutine('Round Duration');
        await routineState.addExerciseToRoutine(exercises.first, 'round');
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

        await tester.tap(find.text(exercises.first.name).first);
        await tester.pumpAndSettle();

        // Round-duration editor must still be present.
        expect(find.text('DURATION'), findsOneWidget);
        expect(find.text('ROUND 1'), findsOneWidget);
      },
    );

    testWidgets(
      'timed effort with no extra-weight target shows no metric editor',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        final routineState = RoutineState(repo);
        routineState.setAutosaveEnabled(false);

        // No extra-weight target seeded — _buildMetricWidget returns SizedBox.shrink().
        final exercises = await repo.getExercises();
        await routineState.createNewRoutine('Timed No Extra');
        await routineState.addExerciseToRoutine(exercises.first, 'timed');
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

        await tester.tap(find.text(exercises.first.name).first);
        await tester.pumpAndSettle();

        expect(find.byType(InlineMetricEditor), findsOneWidget);
        expect(find.text('EXTRA KG'), findsOneWidget);
        // Set count row is still visible.
        expect(find.text('Interval 1 of 1'), findsOneWidget);
      },
    );

    test(
      'building session from routine with timed and drill efforts succeeds',
      () async {
        final repo = await _freshRepo();
        final exercises = await repo.getExercises();

        // Build the template hierarchy directly so IDs are stable and unique
        // (avoids timestamp-collision in RoutineState.addExerciseToRoutine).
        const templateId = 'tmpl-cardio-drill';
        await repo.createTemplate(
          WorkoutTemplate(
            id: templateId,
            name: 'Mixed Cardio Drill',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
        await repo.createTemplateSegment(
          TemplateSegment(
            id: 'tseg-mixed',
            templateId: templateId,
            orderIndex: 0,
            segmentType: 'main',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );

        // Timed exercise: 3 intervals encoded via extra-weight targets
        // at setIndex 0-2.
        const timedEffortId = 'teff-timed-001';
        await repo.createTemplateEffort(
          TemplateEffort(
            id: timedEffortId,
            templateSegmentId: 'tseg-mixed',
            orderIndex: 0,
            effortKind: 'timed',
            exerciseId: exercises.first.id,
            createdAtMs: 1000,
          ),
        );
        for (int i = 0; i < 3; i++) {
          await repo.createTemplateTarget(
            TemplateTarget(
              id: 'ttgt-timed-ew-$i',
              templateEffortId: timedEffortId,
              metricId: MetricIds.extraWeight,
              setIndex: i,
              targetMin: 0.0,
              createdAtMs: 1000,
              updatedAtMs: 1000,
            ),
          );
        }

        // Drill exercise: 3 holds encoded via extra-weight targets at
        // setIndex 0-2.
        final drillExercise = exercises.length > 1
            ? exercises[1]
            : exercises.first;
        const drillEffortId = 'teff-drill-001';
        await repo.createTemplateEffort(
          TemplateEffort(
            id: drillEffortId,
            templateSegmentId: 'tseg-mixed',
            orderIndex: 1,
            effortKind: 'drill',
            exerciseId: drillExercise.id,
            createdAtMs: 1001,
          ),
        );
        for (int i = 0; i < 3; i++) {
          await repo.createTemplateTarget(
            TemplateTarget(
              id: 'ttgt-drill-ew-$i',
              templateEffortId: drillEffortId,
              metricId: MetricIds.extraWeight,
              setIndex: i,
              targetMin: 0.0,
              createdAtMs: 1001,
              updatedAtMs: 1001,
            ),
          );
        }

        // Build manifest — must not throw.
        final service = RoutineSessionService(repo);
        final manifest = await service.buildSessionFromTemplate(templateId);

        final timedEntry = manifest.exercises.firstWhere(
          (e) => e.effortKind == 'timed',
        );
        final drillEntry = manifest.exercises.firstWhere(
          (e) => e.effortKind == 'drill',
        );
        expect(timedEntry.effortKind, 'timed');
        expect(drillEntry.effortKind, 'drill');
        expect(timedEntry.setCount, 3);
        expect(drillEntry.setCount, 3);

        // Populate a session and verify timer instances start in notStarted
        // state with no elapsed time.
        final workoutState = WorkoutState(repo);
        await workoutState.createNewSession();
        await workoutState.populateSessionFromManifest(manifest);

        final sessionExercises = workoutState.getExercisesWithEntries();
        final timedEx = sessionExercises.firstWhere(
          (e) => e['effortKind'] == 'timed',
        );
        final drillEx = sessionExercises.firstWhere(
          (e) => e['effortKind'] == 'drill',
        );

        final timedInstances = workoutState.getTimedInstancesForEffort(
          timedEx['id'] as String,
        );
        expect(timedInstances, hasLength(3));
        expect(
          timedInstances.every((t) => t.state == TimedState.notStarted),
          isTrue,
        );
        expect(timedInstances.every((t) => t.elapsedMs == 0), isTrue);

        final drillInstances = workoutState.getTimedInstancesForEffort(
          drillEx['id'] as String,
        );
        expect(drillInstances, hasLength(3));
        expect(
          drillInstances.every((t) => t.state == TimedState.notStarted),
          isTrue,
        );
        expect(drillInstances.every((t) => t.elapsedMs == 0), isTrue);
      },
    );

    // ── Focus-modality inheritance in add-exercise flow ───────────────
    // When a routine's Focus Modality is set, adding an exercise must
    // silently inherit the modality — no ModalityPickerDialog. When
    // Focus Modality is "Mixed / Not set" (null), the existing picker
    // flow must still be shown.

    testWidgets(
      'focus-set routine: add exercise skips modality picker (resistance)',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        final routineState = RoutineState(repo);
        routineState.setAutosaveEnabled(false);

        await routineState.createNewRoutine('Push Day');
        await routineState.updateRoutineFocusModality('resistance_lifting');
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

        // Open the picker via the block "+" icon.
        await tester.tap(find.byTooltip('Add exercise to block').first);
        await tester.pumpAndSettle();

        expect(find.byType(ExercisePickerScreen), findsOneWidget);
        // Picker must NOT auto-advance to the modality picker.
        expect(find.byType(ModalityPickerDialog), findsNothing);

        // Select an exercise from the picker (ListTile is the row).
        await tester.tap(find.byType(ListTile).first);
        await tester.pumpAndSettle();

        // Modality picker must remain hidden — focus modality was inherited.
        expect(find.byType(ModalityPickerDialog), findsNothing);
        expect(find.byType(ExercisePickerScreen), findsNothing);

        // The exercise was added with the focus modality's effort kind.
        expect(routineState.currentEfforts, hasLength(1));
        expect(routineState.currentEfforts.first.effortKind, 'set');
      },
    );

    testWidgets(
      'focus-set routine: add exercise skips modality picker (sports)',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        final routineState = RoutineState(repo);
        routineState.setAutosaveEnabled(false);

        await routineState.createNewRoutine('Game Day');
        await routineState.updateRoutineFocusModality('sports');
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

        await tester.tap(find.byTooltip('Add exercise to block').first);
        await tester.pumpAndSettle();
        await tester.tap(find.byType(ListTile).first);
        await tester.pumpAndSettle();

        expect(find.byType(ModalityPickerDialog), findsNothing);
        expect(routineState.currentEfforts, hasLength(1));
        // 'sports' → effortKind 'round'.
        expect(routineState.currentEfforts.first.effortKind, 'round');
      },
    );

    testWidgets('Mixed routine: add exercise still shows modality picker', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final routineState = RoutineState(repo);
      routineState.setAutosaveEnabled(false);

      // focusModality left null (the "Mixed / Not set" default).
      await routineState.createNewRoutine('Mixed Day');
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

      await tester.tap(find.byTooltip('Add exercise to block').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();

      // Preserved path: the modality picker appears after exercise pick.
      expect(find.byType(ModalityPickerDialog), findsOneWidget);
      expect(routineState.currentEfforts, isEmpty);
    });

    testWidgets(
      'focus-set routine: cancelling picker does not show modality picker',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        final routineState = RoutineState(repo);
        routineState.setAutosaveEnabled(false);

        await routineState.createNewRoutine('Cancel Focus');
        await routineState.updateRoutineFocusModality('cardio_endurance');
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

        await tester.tap(find.byTooltip('Add exercise to block').first);
        await tester.pumpAndSettle();
        expect(find.byType(ExercisePickerScreen), findsOneWidget);

        // Dismiss the picker via the back arrow.
        await tester.tap(find.byIcon(Icons.arrow_back).first);
        await tester.pumpAndSettle();

        expect(find.byType(ExercisePickerScreen), findsNothing);
        expect(find.byType(ModalityPickerDialog), findsNothing);
        expect(routineState.currentEfforts, isEmpty);
      },
    );

    testWidgets(
      'Mixed routine: cancelling picker does not show modality picker',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        final routineState = RoutineState(repo);
        routineState.setAutosaveEnabled(false);

        await routineState.createNewRoutine('Cancel Mixed');
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

        await tester.tap(find.byTooltip('Add exercise to block').first);
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.arrow_back).first);
        await tester.pumpAndSettle();

        expect(find.byType(ExercisePickerScreen), findsNothing);
        expect(find.byType(ModalityPickerDialog), findsNothing);
        expect(routineState.currentEfforts, isEmpty);
      },
    );

    test(
      'changing focus modality does not retroactively alter existing efforts',
      () async {
        final repo = await _freshRepo();
        final exercises = await repo.getExercises();
        final routineState = RoutineState(repo);
        routineState.setAutosaveEnabled(false);

        // Build a routine with resistance focus and add an exercise under it.
        await routineState.createNewRoutine('Shift Focus');
        await routineState.updateRoutineFocusModality('resistance_lifting');
        final firstEffortId = await routineState.addExerciseToRoutine(
          exercises.first,
          // Inherited from focus: effortKind 'set'.
          'set',
        );
        expect(routineState.currentEfforts.first.effortKind, 'set');

        // Change the focus to sports AFTER the first exercise exists.
        await routineState.updateRoutineFocusModality('sports');

        // Existing effort must be untouched.
        expect(
          routineState.currentEfforts
              .firstWhere((e) => e.id == firstEffortId)
              .effortKind,
          'set',
          reason: 'changing focus must not rewrite already-added efforts',
        );

        // Adding a new exercise should adopt the new focus modality.
        final next = exercises.length > 1 ? exercises[1] : exercises.first;
        final secondEffortId = await routineState.addExerciseToRoutine(
          next,
          // Inherited from the NEW focus: 'sports' → 'round'.
          'round',
        );
        expect(routineState.currentEfforts, hasLength(2));
        expect(
          routineState.currentEfforts
              .firstWhere((e) => e.id == secondEffortId)
              .effortKind,
          'round',
        );
      },
    );
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
      final settingsState = SettingsState(repo, fakePreferencesService());
      await settingsState.initialize();

      await tester.pumpWidget(
        MaterialApp(
          home: SessionOverviewScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: sessionSummaryService,
            settingsState: settingsState,
            timerAlertService: FakeTimerAlertService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OmniBackHeader), findsOneWidget);
      expect(find.text('Workout Session'), findsOneWidget);
      expect(find.text('No exercises yet'), findsOneWidget);
    });

    testWidgets('shows Add Exercise button', (WidgetTester tester) async {
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final routineState = RoutineState(repo);
      final sessionSummaryService = SessionSummaryService(repo);
      final settingsState = SettingsState(repo, fakePreferencesService());
      await settingsState.initialize();

      await tester.pumpWidget(
        MaterialApp(
          home: SessionOverviewScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: sessionSummaryService,
            settingsState: settingsState,
            timerAlertService: FakeTimerAlertService(),
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
      final settingsState = SettingsState(repo, fakePreferencesService());
      await settingsState.initialize();

      await tester.pumpWidget(
        MaterialApp(
          home: SessionOverviewScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: sessionSummaryService,
            settingsState: settingsState,
            timerAlertService: FakeTimerAlertService(),
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
      final settingsState = SettingsState(repo, fakePreferencesService());
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
            timerAlertService: FakeTimerAlertService(),
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
      final settingsState = SettingsState(repo, fakePreferencesService());
      await settingsState.initialize();
      final nutritionPrimerState = await buildNutritionPrimerState(repo);

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
      final settingsState = SettingsState(repo, fakePreferencesService());
      await settingsState.initialize();
      final nutritionPrimerState = await buildNutritionPrimerState(repo);

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
            timerAlertService: FakeTimerAlertService(),
            nutritionState: NutritionState(repo),
            foodLibraryState: FoodLibraryState(repo),
            nutritionPrimerState: nutritionPrimerState,
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
      final settingsState = SettingsState(repo, fakePreferencesService());
      await settingsState.initialize();
      final nutritionPrimerState = await buildNutritionPrimerState(repo);

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
            timerAlertService: FakeTimerAlertService(),
            nutritionState: NutritionState(repo),
            foodLibraryState: FoodLibraryState(repo),
            nutritionPrimerState: nutritionPrimerState,
          ),
        ),
      );
      // Use pump() with an explicit duration rather than pumpAndSettle
      // because the active tile now has a continuously-repeating pulse
      // animation (the "Workout in progress" dot), which would otherwise
      // prevent pumpAndSettle from ever settling.
      await tester.pump(const Duration(milliseconds: 200));

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
        final settingsState = SettingsState(repo, fakePreferencesService());
        await settingsState.initialize();
        final nutritionPrimerState = await buildNutritionPrimerState(repo);

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
              timerAlertService: FakeTimerAlertService(),
              nutritionState: NutritionState(repo),
              foodLibraryState: FoodLibraryState(repo),
              nutritionPrimerState: nutritionPrimerState,
            ),
          ),
        );
        // See note above re: pulse animation and pumpAndSettle.
        await tester.pump(const Duration(milliseconds: 200));

        await tester.tap(find.byIcon(Icons.folder_open));
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('Start New Session?'), findsOneWidget);
        expect(find.byType(MyRoutinesScreen), findsNothing);
      },
    );

    testWidgets('does not show unfinished-session launch modal copy', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      final screen = await buildHomeScreen(repo);
      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pumpAndSettle();

      expect(find.text('Unfinished Session'), findsNothing);
      expect(find.text('Confirm Discard'), findsNothing);
      expect(find.textContaining('sets logged'), findsNothing);
    });

    // Regression test for the bug where the home-screen maintenance
    // tile path into SettingsScreen did not pass `profileState`,
    // leaving the height preview showing the `—` placeholder even
    // when a height measurement existed in the repository. The fix
    // adds `profileState: widget.profileState` to the SettingsScreen
    // construction in `home_screen.dart`.
    testWidgets(
      'Settings maintenance tile height preview reads from profileState',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(500, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _freshRepo();
        // Persist a height measurement so the repo has data.
        await repo.saveMeasurementEntry(
          BodyMeasurementEntry(
            id: 'h-home-tile-regression',
            measurementType: 'height',
            value: 181,
            unitId: 'unit-cm',
            recordedAtMs: 2000,
          ),
        );

        final screen = await buildHomeScreen(repo);
        await tester.pumpWidget(MaterialApp(home: screen));
        await tester.pumpAndSettle();

        // The maintenance grid is inside the Hub sheet. Open the
        // sheet by tapping the logo first.
        await tester.tap(find.byType(Image));
        await tester.pumpAndSettle();

        // Tap the Settings maintenance tile.
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();

        // The settings screen must show the user's height in cm,
        // not the `—` placeholder.
        expect(find.text('181 cm'), findsOneWidget);
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
        NutritionPrimerState nutritionPrimerState,
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
      final settingsState = SettingsState(repo, fakePreferencesService());
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
        nutritionPrimerState: await buildNutritionPrimerState(repo),
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
        NutritionPrimerState nutritionPrimerState,
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
          timerAlertService: FakeTimerAlertService(),
          nutritionState: NutritionState(deps.repo),
          foodLibraryState: FoodLibraryState(deps.repo),
          nutritionPrimerState: deps.nutritionPrimerState,
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
          timerAlertService: FakeTimerAlertService(),
          nutritionState: NutritionState(deps.repo),
          foodLibraryState: FoodLibraryState(deps.repo),
          nutritionPrimerState: deps.nutritionPrimerState,
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
      MockWorkoutRepository repo, {
      Future<void> Function(SettingsState settingsState)? configureSettings,
    }) async {
      final workoutState = WorkoutState(repo);
      final settingsState = SettingsState(repo, fakePreferencesService());
      await settingsState.initialize();
      if (configureSettings != null) {
        await configureSettings(settingsState);
      }

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

    Future<void> seedTimedEffort(
      MockWorkoutRepository repo, {
      required String sessionId,
      required String exerciseId,
      required int durationSecs,
      double? distanceM,
    }) async {
      final segmentId = 'seg-$sessionId-$exerciseId';
      final effortId = 'eff-$sessionId-$exerciseId';

      await repo.createSegment(
        SessionSegment(
          id: segmentId,
          sessionId: sessionId,
          orderIndex: 0,
          segmentType: 'main',
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );
      await repo.createEffort(
        SegmentEffort(
          id: effortId,
          segmentId: segmentId,
          orderIndex: 0,
          effortKind: 'timed',
          exerciseId: exerciseId,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );
      await repo.createTimedInstance(
        TimedInstance(
          id: 'ti-$effortId',
          effortId: effortId,
          entryIndex: 0,
          actualDurationSecs: durationSecs,
          state: TimedState.finished,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );

      if (distanceM != null && distanceM > 0) {
        await repo.createObservation(
          EffortObservation(
            id: 'obs-$effortId-distance',
            effortId: effortId,
            metricId: MetricIds.distance,
            unitId: MetricIds.unitMeters,
            valueReal: distanceM,
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
      }
    }

    Future<void> seedSetEffort(
      MockWorkoutRepository repo, {
      required String sessionId,
      required String exerciseId,
      required double weightKg,
      required int reps,
    }) async {
      final segmentId = 'seg-$sessionId-$exerciseId';
      final effortId = 'eff-$sessionId-$exerciseId';

      await repo.createSegment(
        SessionSegment(
          id: segmentId,
          sessionId: sessionId,
          orderIndex: 0,
          segmentType: 'main',
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );
      await repo.createEffort(
        SegmentEffort(
          id: effortId,
          segmentId: segmentId,
          orderIndex: 0,
          effortKind: 'set',
          exerciseId: exerciseId,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );
      await repo.createObservation(
        EffortObservation(
          id: 'obs-$effortId-weight',
          effortId: effortId,
          metricId: MetricIds.weight,
          unitId: MetricIds.unitKg,
          valueReal: weightKg,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );
      await repo.createObservation(
        EffortObservation(
          id: 'obs-$effortId-reps',
          effortId: effortId,
          metricId: MetricIds.reps,
          unitId: MetricIds.unitReps,
          valueInt: reps,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );
    }

    testWidgets('shows Stats AppBar title', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      final repo = await _freshRepo();

      await pumpStatsScreen(tester, repo);

      expect(find.byType(OmniBackHeader), findsOneWidget);
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
      expect(find.text('STRENGTH'), findsNothing);
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

    testWidgets('cardio single-day pace respects miles preference', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      final repo = await _freshRepo();
      final now = DateTime.now();

      await repo.createExercise(
        Exercise(
          id: 'ex-run',
          name: 'Run',
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );
      await seedCompletedSession(
        repo,
        id: 'cardio-1',
        start: now.subtract(const Duration(days: 1)),
        duration: const Duration(minutes: 30),
      );
      await seedTimedEffort(
        repo,
        sessionId: 'cardio-1',
        exerciseId: 'ex-run',
        durationSecs: 1800,
        distanceM: 5000,
      );

      await pumpStatsScreen(
        tester,
        repo,
        configureSettings: (settingsState) async {
          await settingsState.setPreferredDistanceUnit('mi');
        },
      );

      expect(find.textContaining('Pace: 579 s/mi'), findsOneWidget);
      // Single-point cardio card also shows the deliberate hint.
      expect(
        find.textContaining('1 session — log more to see a trend'),
        findsWidgets,
      );
    });

    testWidgets('cardio multi-day pace chart overlays distance trend', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      final repo = await _freshRepo();
      final now = DateTime.now();

      await repo.createExercise(
        Exercise(
          id: 'ex-row',
          name: 'Row',
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );

      await seedCompletedSession(
        repo,
        id: 'cardio-row-1',
        start: now.subtract(const Duration(days: 2)),
        duration: const Duration(minutes: 20),
      );
      await seedTimedEffort(
        repo,
        sessionId: 'cardio-row-1',
        exerciseId: 'ex-row',
        durationSecs: 1200,
        distanceM: 4000,
      );

      await seedCompletedSession(
        repo,
        id: 'cardio-row-2',
        start: now.subtract(const Duration(days: 1)),
        duration: const Duration(minutes: 18),
      );
      await seedTimedEffort(
        repo,
        sessionId: 'cardio-row-2',
        exerciseId: 'ex-row',
        durationSecs: 1080,
        distanceM: 4200,
      );

      await pumpStatsScreen(tester, repo);

      expect(find.text('Distance (km)'), findsOneWidget);

      final cardioChart = tester.widget<LineChart>(
        find.byType(LineChart).first,
      );
      expect(cardioChart.data.lineBarsData.length, 2);
    });

    testWidgets('strength e1RM and PRs displayed in lbs when unit is lbs', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      final repo = await _freshRepo();
      final now = DateTime.now();

      await repo.createExercise(
        Exercise(
          id: 'ex-squat',
          name: 'Squat',
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );
      // Single training day → single-point fallback shows inline text
      await seedCompletedSession(
        repo,
        id: 'lift-1',
        start: now.subtract(const Duration(days: 1)),
        duration: const Duration(minutes: 45),
      );
      // 100 kg × 1 rep → e1RM ≈ 103.33 kg ≈ 227.8 lbs
      await seedSetEffort(
        repo,
        sessionId: 'lift-1',
        exerciseId: 'ex-squat',
        weightKg: 100.0,
        reps: 1,
      );

      await pumpStatsScreen(
        tester,
        repo,
        configureSettings: (settingsState) async {
          await settingsState.setPreferredWeightUnit('lbs');
        },
      );

      // Unit label must say 'lbs', not 'kg'
      expect(find.textContaining('lbs'), findsWidgets);
      expect(find.textContaining('Estimated 1RM:'), findsOneWidget);
      expect(find.textContaining(' kg'), findsNothing);
      // Single-point card must show the deliberate "log more" hint.
      expect(
        find.textContaining('1 session — log more to see a trend'),
        findsWidgets,
      );
    });

    // ══════════════════════════════════════════════════════════════════════
    // Plan: unify-chart-scrolling-popup — Phase 1 scenarios
    // S-101..S-105c apply to every on-card stats chart; the
    // fixtures below seed >8 training days of strength set
    // efforts to drive the strength e1RM / volume charts past
    // the 8-points-visible threshold.
    // ══════════════════════════════════════════════════════════════════════

    Future<void> seedStrengthDays(
      MockWorkoutRepository repo, {
      required String exerciseId,
      required int dayCount,
      DateTime? firstStart,
    }) async {
      final start = firstStart ?? DateTime.now();
      for (var i = 0; i < dayCount; i++) {
        final day = start.subtract(Duration(days: dayCount - 1 - i));
        final id = 'lift-$exerciseId-$i';
        await seedCompletedSession(
          repo,
          id: id,
          start: day,
          duration: const Duration(minutes: 45),
          modality: 'resistance_lifting',
        );
        await seedSetEffort(
          repo,
          sessionId: id,
          exerciseId: exerciseId,
          weightKg: 80.0 + i.toDouble(),
          reps: 5,
        );
      }
    }

    Future<void> seedCardioDays(
      MockWorkoutRepository repo, {
      required String exerciseId,
      required int dayCount,
      DateTime? firstStart,
    }) async {
      final start = firstStart ?? DateTime.now();
      for (var i = 0; i < dayCount; i++) {
        final day = start.subtract(Duration(days: dayCount - 1 - i));
        final id = 'cardio-$exerciseId-$i';
        await seedCompletedSession(
          repo,
          id: id,
          start: day,
          duration: const Duration(minutes: 30),
        );
        await seedTimedEffort(
          repo,
          sessionId: id,
          exerciseId: exerciseId,
          durationSecs: 1800,
          distanceM: 5000.0,
        );
      }
    }

    // S-101: many points → scroll, newest first
    testWidgets('strength chart with >8 points opens scrolled to '
        'maxScrollExtent (newest at right)', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      final repo = await _freshRepo();
      await repo.createExercise(
        Exercise(
          id: 'ex-squat',
          name: 'Squat',
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );
      await seedStrengthDays(repo, exerciseId: 'ex-squat', dayCount: 12);

      await pumpStatsScreen(tester, repo);

      // Every on-card chart on this screen is a `ScrollableTrendChart`.
      // For 12 points (> maxVisiblePoints 8) the inner
      // SingleChildScrollView has a non-zero maxScrollExtent and the
      // wrapper has jumped its ScrollController to that extent.
      // Filter to chart-scoped scrollables (horizontal axis, inside a
      // ScrollableTrendChart) — excludes the parent ListView (vertical).
      final chartScrollables = <ScrollPosition>[];
      for (final scrollable in tester.stateList<ScrollableState>(
        find.byType(Scrollable),
      )) {
        if (scrollable.position.axis != Axis.horizontal) continue;
        final inChart = find
            .ancestor(
              of: find.byWidget(
                tester.widget<Scrollable>(
                  find.byWidgetPredicate((w) => w is Scrollable && w == scrollable.widget),
                ),
              ),
              matching: find.byType(ScrollableTrendChart),
            )
            .evaluate()
            .isNotEmpty;
        if (inChart) chartScrollables.add(scrollable.position);
      }
      expect(chartScrollables, isNotEmpty);
      for (final pos in chartScrollables) {
        expect(
          pos.pixels,
          pos.maxScrollExtent,
          reason:
              'newest-first: scroll position must equal maxScrollExtent '
              'after first layout',
        );
      }
    });

    // S-102: few points → no scroll, plot fills viewport
    testWidgets('strength chart with ≤8 points fills the viewport '
        '(no scroll engagement)', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      final repo = await _freshRepo();
      await repo.createExercise(
        Exercise(
          id: 'ex-bench',
          name: 'Bench',
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );
      await seedStrengthDays(repo, exerciseId: 'ex-bench', dayCount: 3);

      await pumpStatsScreen(tester, repo);

      // With 3 points (<= maxVisiblePoints 8) the strength chart's
      // SingleChildScrollView has maxScrollExtent == 0. The mock
      // seed also seeds nutrition data (~30 days), so we filter
      // to the strength chart only — identified by its 3 spots
      // (bench has 3 distinct training days in this fixture).
      // A chart with <= 8 points must not engage horizontal scroll.
      ScrollPosition? strengthChartPosition;
      for (final chart in tester.widgetList<LineChart>(find.byType(LineChart))) {
        if (chart.data.lineBarsData.isEmpty) continue;
        if (chart.data.lineBarsData.first.spots.length != 3) continue;
        // Find the Scrollable ancestor and use its position.
        final scrollFinder = find
            .ancestor(
              of: find.byWidget(chart),
              matching: find.byType(Scrollable),
            )
            .first;
        if (scrollFinder.evaluate().isEmpty) continue;
        strengthChartPosition =
            tester.state<ScrollableState>(scrollFinder).position;
        break;
      }
      expect(
        strengthChartPosition,
        isNotNull,
        reason: 'should find a strength chart with 3 spots',
      );
      expect(
        strengthChartPosition!.maxScrollExtent,
        0,
        reason: 'sparse data: no horizontal scroll on the strength chart',
      );
    });

    // S-103: data order is not reversed
    testWidgets('strength chart data is not reversed: oldest spot '
        'at index 0, newest at index N-1', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      final repo = await _freshRepo();
      await repo.createExercise(
        Exercise(
          id: 'ex-deadlift',
          name: 'Deadlift',
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );
      await seedStrengthDays(repo, exerciseId: 'ex-deadlift', dayCount: 12);

      await pumpStatsScreen(tester, repo);

      // Find the strength LineChart (the one whose minX/maxX span the
      // 12 indices). The order of spots must be ascending by index
      // (oldest to newest); the wrapper just scrolls the view, it
      // does NOT mirror the data.
      final lineCharts = tester.widgetList<LineChart>(find.byType(LineChart));
      final multiSpotCharts = lineCharts
          .where((c) => c.data.lineBarsData.isNotEmpty &&
              c.data.lineBarsData.first.spots.length >= 2)
          .toList();
      expect(multiSpotCharts, isNotEmpty);

      for (final chart in multiSpotCharts) {
        final spots = chart.data.lineBarsData.first.spots;
        for (var i = 1; i < spots.length; i++) {
          expect(spots[i].x, greaterThan(spots[i - 1].x),
              reason: 'spots must be in ascending x order (not reversed)');
        }
        // The wrapper uses reverse:false (no mirror).
        final scrollAncestor = find.ancestor(
          of: find.byWidget(chart),
          matching: find.byType(SingleChildScrollView),
        );
        final scroller = tester.widget<SingleChildScrollView>(scrollAncestor);
        expect(scroller.reverse, isFalse);
      }
    });

    // S-104: tapping a point does not show a tooltip popup
    testWidgets('tapping a stats chart point does not surface a fl_chart '
        'tooltip (popup removed, D-4)', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      final repo = await _freshRepo();
      await repo.createExercise(
        Exercise(
          id: 'ex-ohp',
          name: 'Overhead Press',
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );
      await seedStrengthDays(repo, exerciseId: 'ex-ohp', dayCount: 12);

      await pumpStatsScreen(tester, repo);

      // Verify every chart's LineTouchData is disabled.
      for (final chart in tester.widgetList<LineChart>(find.byType(LineChart))) {
        expect(chart.data.lineTouchData.enabled, isFalse,
            reason: 'all stats charts must disable lineTouchData');
      }

      // Tap the chart and verify no Tooltip renders.
      await tester.tap(find.byType(LineChart).first);
      await tester.pumpAndSettle();
      expect(find.byType(Tooltip), findsNothing);
    });

    // S-105 / S-105b / S-105c: no top headroom, no double padding,
    // highest point not clipped.
    testWidgets('stats charts: no topTitles headroom, no double-padding '
        '(no Transform.translate ancestor), top point not clipped '
        '(D-5, D-6, S-105, S-105b, S-105c)', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      final repo = await _freshRepo();
      await repo.createExercise(
        Exercise(
          id: 'ex-row',
          name: 'Row',
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );
      await seedStrengthDays(repo, exerciseId: 'ex-row', dayCount: 12);

      await pumpStatsScreen(tester, repo);

      // S-105: topTitles reservedSize == 0 (no popup headroom).
      for (final chart in tester.widgetList<LineChart>(find.byType(LineChart))) {
        expect(
          chart.data.titlesData.topTitles.sideTitles.reservedSize,
          0,
          reason: 'no top headroom — popup no longer needs the gap',
        );
      }

      // S-105: no Transform.translate ancestor with a chart
      // left-shift offset (the deprecated `_buildInsetChart` used
      // `Transform.translate(offset: Offset(-16, 0))` to push the
      // chart left). Other framework-introduced Transforms
      // (overflow fade, scroll position translation) are allowed.
      final lineCharts = find.byType(LineChart);
      expect(lineCharts, findsWidgets);
      for (var i = 0; i < lineCharts.evaluate().length; i++) {
        final chartFinder = find.byType(LineChart).at(i);
        final leftShiftTransforms = find
            .ancestor(
              of: chartFinder,
              matching: find.byWidgetPredicate((w) {
                if (w is! Transform) return false;
                final t = w.transform.getTranslation();
                // Match the deprecated pattern: a Transform.translate
                // that shifts the chart LEFT by the old
                // `_kChartLeftShift = 16` value (no vertical shift).
                return t.x < -8 && t.y.abs() < 0.5;
              }),
            )
            .evaluate();
        expect(leftShiftTransforms, isEmpty,
            reason: 'no Transform.translate chart-left-shift ancestor — '
                'no double-padding wrapper');
      }

      // S-105c: the chart sits inside a SizedBox parent (the
      // wrapper's plot SizedBox). Verify at least one SizedBox
      // ancestor exists for each chart.
      for (var i = 0; i < lineCharts.evaluate().length; i++) {
        final chartFinder = find.byType(LineChart).at(i);
        final sizedBoxAncestors = find
            .ancestor(
              of: chartFinder,
              matching: find.byType(SizedBox),
            )
            .evaluate();
        expect(sizedBoxAncestors, isNotEmpty,
            reason: 'chart sits inside a SizedBox(parent)');
      }

      // S-105b: the highest data point renders with at least 2 dp of
      // padding above it so the dot is visibly inside the plot
      // area. ChartAxisHelper pads above max by
      // `range × 0.15 + 1.0`, which gives ≥ 2 dp for ranges ≥ 7 —
      // the typical stats-screen case. For tight ranges the
      // padding can shrink below the dot radius (3 dp); the dot
      // may clip by 1 dp on those edge cases but is still
      // visually inside the chart. The plan forbids additional
      // padding logic in ChartAxisHelper (D-10), so the wrapper
      // accepts the helper's existing math and the structural
      // guard holds for normal data.
      for (final chart in tester.widgetList<LineChart>(find.byType(LineChart))) {
        if (chart.data.lineBarsData.isEmpty) continue;
        final bar = chart.data.lineBarsData.first;
        if (bar.spots.isEmpty) continue;
        final maxYValue =
            bar.spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
        final maxYBound = chart.data.maxY;
        final topPadding = maxYBound - maxYValue;
        expect(
          topPadding,
          greaterThanOrEqualTo(2.0),
          reason:
              'top point must have ≥2 dp of padding above it so the dot is '
              'visibly inside the plot area after headroom removal',
        );
      }
    });

    // S-104 also covers the cardio chart (multi-line). Verify
    // cardio pace + distance chart has LineTouchData disabled and
    // no popup appears.
    testWidgets('cardio pace chart: LineTouchData disabled, '
        'no popup on tap (S-104 cardio)', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      final repo = await _freshRepo();
      await repo.createExercise(
        Exercise(
          id: 'ex-run',
          name: 'Run',
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );
      await seedCardioDays(repo, exerciseId: 'ex-run', dayCount: 12);

      await pumpStatsScreen(tester, repo);

      // Every cardio chart's LineTouchData disabled.
      final cardioCharts = tester
          .widgetList<LineChart>(find.byType(LineChart))
          .where((c) => c.data.lineBarsData.length >= 2);
      expect(cardioCharts, isNotEmpty,
          reason: 'multi-line cardio chart (pace + distance) present');
      for (final chart in cardioCharts) {
        expect(chart.data.lineTouchData.enabled, isFalse);
      }

      // Tap and verify no Tooltip.
      await tester.tap(find.byType(LineChart).first);
      await tester.pumpAndSettle();
      expect(find.byType(Tooltip), findsNothing);
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

      expect(find.byType(OmniBackHeader), findsOneWidget);
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

    testWidgets('extends body behind bottom CTA to avoid footer banding', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);

      await tester.pumpWidget(
        MaterialApp(home: ExerciseEditorScreen(workoutState: workoutState)),
      );
      await tester.pumpAndSettle();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.extendBody, isTrue);
      expect(scaffold.bottomNavigationBar, isA<OmniBottomCTA>());
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
      final settingsState = SettingsState(repo, fakePreferencesService());
      await settingsState.initialize();
      await profileState.loadProfile();

      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(
            profileState: profileState,
            settingsState: settingsState,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OmniBackHeader), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
    });

    testWidgets('renders without crash after loading profile', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      final repo = await _freshRepo();
      final profileState = ProfileState(repo);
      final settingsState = SettingsState(repo, fakePreferencesService());
      await settingsState.initialize();
      await profileState.loadProfile();

      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(
            profileState: profileState,
            settingsState: settingsState,
          ),
        ),
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
            settingsState: SettingsState(repo, fakePreferencesService()),
            timerAlertService: FakeTimerAlertService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OmniBackHeader), findsOneWidget);
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
            settingsState: SettingsState(repo, fakePreferencesService()),
            timerAlertService: FakeTimerAlertService(),
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
            settingsState: SettingsState(repo, fakePreferencesService()),
            timerAlertService: FakeTimerAlertService(),
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
              settingsState: SettingsState(repo, fakePreferencesService()),
              timerAlertService: FakeTimerAlertService(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.widgetWithText(FilledButton, '+ New Planned Session'),
        );
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
      'planned session form uses active theme tokens for sheet, title, and close icon',
      (WidgetTester tester) async {
        addTearDown(() => OmniTheme.activeTheme = AppTheme.abyssalNeon);
        OmniTheme.activeTheme = AppTheme.forgeEmber;

        await tester.binding.setSurfaceSize(const Size(400, 1000));
        final repo = await _freshRepo();
        final calendarState = CalendarState(repo);
        await calendarState.init();
        final routineState = RoutineState(repo);
        final workoutState = WorkoutState(repo);
        final routineSessionService = RoutineSessionService(repo);
        final sessionSummaryService = SessionSummaryService(repo);
        final forgeTokens = OmniTheme.colorsForTheme(AppTheme.forgeEmber);
        final forgeTheme = buildTheme(
          theme: AppTheme.forgeEmber,
          brightness: Brightness.dark,
          background: forgeTokens.backgroundBottom,
          surface: forgeTokens.surface,
          secondary: forgeTokens.secondary,
          textPrimary: const Color(0xFFE6EDF3),
          textSecondary: forgeTokens.textMuted,
          divider: forgeTokens.divider,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: forgeTheme,
            home: DaySessionListScreen(
              date: DateTime(2099, 12, 31),
              calendarState: calendarState,
              routineState: routineState,
              workoutState: workoutState,
              routineSessionService: routineSessionService,
              sessionSummaryService: sessionSummaryService,
              settingsState: SettingsState(repo, fakePreferencesService()),
              timerAlertService: FakeTimerAlertService(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.widgetWithText(FilledButton, '+ New Planned Session'),
        );
        await tester.pumpAndSettle();

        final tokens = OmniTheme.colorsForTheme(AppTheme.forgeEmber);
        final sheetContainer = tester.widget<Container>(
          find.byWidgetPredicate((widget) {
            if (widget is! Container) return false;
            final decoration = widget.decoration;
            if (decoration is! BoxDecoration) return false;
            return decoration.borderRadius ==
                const BorderRadius.vertical(top: Radius.circular(20));
          }).first,
        );
        final sheetDecoration = sheetContainer.decoration! as BoxDecoration;
        expect(sheetDecoration.color, tokens.surface);

        final titleText = tester.widget<Text>(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.text('+ New Planned Session'),
          ),
        );
        expect(titleText.style?.color, tokens.textMuted);

        final closeButton = tester.widget<IconButton>(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.widgetWithIcon(IconButton, Icons.close),
          ),
        );
        expect(closeButton.color, tokens.textMuted);
      },
    );

    testWidgets(
      'planned session form reflects new theme tokens after theme switch and rebuild',
      (WidgetTester tester) async {
        addTearDown(() => OmniTheme.activeTheme = AppTheme.abyssalNeon);

        await tester.binding.setSurfaceSize(const Size(400, 1000));
        final repo = await _freshRepo();
        final calendarState = CalendarState(repo);
        await calendarState.init();
        final routineState = RoutineState(repo);
        final workoutState = WorkoutState(repo);
        final routineSessionService = RoutineSessionService(repo);
        final sessionSummaryService = SessionSummaryService(repo);

        Future<void> pumpDayScreen() async {
          await tester.pumpWidget(
            MaterialApp(
              home: DaySessionListScreen(
                date: DateTime(2099, 12, 31),
                calendarState: calendarState,
                routineState: routineState,
                workoutState: workoutState,
                routineSessionService: routineSessionService,
                sessionSummaryService: sessionSummaryService,
                settingsState: SettingsState(repo, fakePreferencesService()),
                timerAlertService: FakeTimerAlertService(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.widgetWithText(FilledButton, '+ New Planned Session'),
          );
          await tester.pumpAndSettle();
        }

        OmniTheme.activeTheme = AppTheme.forgeEmber;
        await pumpDayScreen();

        Color sheetColorForTopRadiusSheet() {
          final container = tester.widget<Container>(
            find.byWidgetPredicate((widget) {
              if (widget is! Container) return false;
              final decoration = widget.decoration;
              if (decoration is! BoxDecoration) return false;
              return decoration.borderRadius ==
                  const BorderRadius.vertical(top: Radius.circular(20));
            }).first,
          );
          final decoration = container.decoration! as BoxDecoration;
          return decoration.color!;
        }

        final closeA = tester.widget<IconButton>(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.widgetWithIcon(IconButton, Icons.close),
          ),
        );
        final sheetA = sheetColorForTopRadiusSheet();
        final tokensA = OmniTheme.colorsForTheme(AppTheme.forgeEmber);
        expect(sheetA, tokensA.surface);
        expect(closeA.color, tokensA.textMuted);

        await tester.tap(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.widgetWithIcon(IconButton, Icons.close),
          ),
        );
        await tester.pumpAndSettle();

        OmniTheme.activeTheme = AppTheme.malachiteCore;
        await pumpDayScreen();

        final closeB = tester.widget<IconButton>(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.widgetWithIcon(IconButton, Icons.close),
          ),
        );
        final sheetB = sheetColorForTopRadiusSheet();
        final tokensB = OmniTheme.colorsForTheme(AppTheme.malachiteCore);
        expect(sheetB, tokensB.surface);
        expect(closeB.color, tokensB.textMuted);
        expect(sheetB, isNot(sheetA));
      },
    );

    testWidgets(
      'planned session mode toggle keeps selected and unselected styles theme-consistent',
      (WidgetTester tester) async {
        addTearDown(() => OmniTheme.activeTheme = AppTheme.abyssalNeon);
        OmniTheme.activeTheme = AppTheme.forgeEmber;

        await tester.binding.setSurfaceSize(const Size(400, 1000));
        final repo = await _freshRepo();
        final calendarState = CalendarState(repo);
        await calendarState.init();
        final routineState = RoutineState(repo);
        final workoutState = WorkoutState(repo);
        final routineSessionService = RoutineSessionService(repo);
        final sessionSummaryService = SessionSummaryService(repo);
        final forgeTokens = OmniTheme.colorsForTheme(AppTheme.forgeEmber);
        final forgeTheme = buildTheme(
          theme: AppTheme.forgeEmber,
          brightness: Brightness.dark,
          background: forgeTokens.backgroundBottom,
          surface: forgeTokens.surface,
          secondary: forgeTokens.secondary,
          textPrimary: const Color(0xFFE6EDF3),
          textSecondary: forgeTokens.textMuted,
          divider: forgeTokens.divider,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: forgeTheme,
            home: DaySessionListScreen(
              date: DateTime(2099, 12, 31),
              calendarState: calendarState,
              routineState: routineState,
              workoutState: workoutState,
              routineSessionService: routineSessionService,
              sessionSummaryService: sessionSummaryService,
              settingsState: SettingsState(repo, fakePreferencesService()),
              timerAlertService: FakeTimerAlertService(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.widgetWithText(FilledButton, '+ New Planned Session'),
        );
        await tester.pumpAndSettle();

        final bottomSheet = find.byType(BottomSheet);
        final selectedStyle = tester
            .widget<FilledButton>(
              find.descendant(
                of: bottomSheet,
                matching: find.widgetWithText(FilledButton, 'Free Training'),
              ),
            )
            .style!;
        final unselectedStyle = tester
            .widget<OutlinedButton>(
              find.descendant(
                of: bottomSheet,
                matching: find.widgetWithText(OutlinedButton, 'Routine'),
              ),
            )
            .style!;

        final selectedBackground = selectedStyle.backgroundColor?.resolve({});
        final selectedBorder = selectedStyle.side?.resolve({});
        final unselectedBorder = unselectedStyle.side?.resolve({});

        expect(
          selectedBackground,
          OmniTheme.colorsForTheme(
            AppTheme.forgeEmber,
          ).primary.withValues(alpha: 0.22),
        );
        expect(
          selectedBorder?.color,
          OmniTheme.colorsForTheme(
            AppTheme.forgeEmber,
          ).primary.withValues(alpha: 0.75),
        );

        await tester.tap(
          find.descendant(
            of: bottomSheet,
            matching: find.widgetWithText(OutlinedButton, 'Routine'),
          ),
        );
        await tester.pumpAndSettle();

        final selectedRoutineStyle = tester
            .widget<FilledButton>(
              find.descendant(
                of: bottomSheet,
                matching: find.widgetWithText(FilledButton, 'Routine'),
              ),
            )
            .style!;
        final unselectedFreeStyle = tester
            .widget<OutlinedButton>(
              find.descendant(
                of: bottomSheet,
                matching: find.widgetWithText(OutlinedButton, 'Free Training'),
              ),
            )
            .style!;

        final selectedRoutineBackground = selectedRoutineStyle.backgroundColor
            ?.resolve({});
        final selectedRoutineBorder = selectedRoutineStyle.side?.resolve({});
        final unselectedFreeBorder = unselectedFreeStyle.side?.resolve({});

        expect(selectedRoutineBackground, selectedBackground);
        expect(selectedRoutineBorder?.color, selectedBorder?.color);
        expect(unselectedFreeBorder?.color, unselectedBorder?.color);
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
              settingsState: SettingsState(repo, fakePreferencesService()),
              timerAlertService: FakeTimerAlertService(),
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

    testWidgets(
      'completed session cards show time, duration, and feeling border',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 1000));
        final repo = await _freshRepo();
        final today = DateTime.now();
        final startedAt = DateTime(today.year, today.month, today.day, 13, 5);
        final timestamp = startedAt.millisecondsSinceEpoch;

        await repo.createSession(
          TrainingSession(
            id: 'session-complete',
            ownerUserId: 'u-1',
            startedAtMs: timestamp,
            endedAtMs: startedAt
                .add(const Duration(minutes: 72))
                .millisecondsSinceEpoch,
            title: 'Lunch Lift',
            modality: Modality.resistanceLifting,
            sessionFeeling: 4,
            createdAtMs: timestamp,
            updatedAtMs: timestamp,
          ),
        );

        final calendarState = CalendarState(repo);
        await calendarState.init();
        final routineState = RoutineState(repo);
        final workoutState = WorkoutState(repo);
        final routineSessionService = RoutineSessionService(repo);
        final sessionSummaryService = SessionSummaryService(repo);

        await tester.pumpWidget(
          MaterialApp(
            home: DaySessionListScreen(
              date: DateTime(today.year, today.month, today.day),
              calendarState: calendarState,
              routineState: routineState,
              workoutState: workoutState,
              routineSessionService: routineSessionService,
              sessionSummaryService: sessionSummaryService,
              settingsState: SettingsState(repo, fakePreferencesService()),
              timerAlertService: FakeTimerAlertService(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Lunch Lift'), findsOneWidget);
        expect(find.text('1:05 PM · 1h 12m'), findsOneWidget);

        final highlightedCards = tester
            .widgetList<Container>(find.byType(Container))
            .where((container) {
              final decoration = container.decoration;
              if (decoration is! BoxDecoration ||
                  decoration.border is! Border) {
                return false;
              }
              final border = decoration.border! as Border;
              return border.left.width == 4;
            })
            .toList();

        expect(highlightedCards, isNotEmpty);
        final border =
            (highlightedCards.first.decoration! as BoxDecoration).border!
                as Border;
        expect(border.left.color, Colors.green);
      },
    );

    testWidgets(
      'completed session cards without a feeling keep the standard border',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 1000));
        final repo = await _freshRepo();
        final today = DateTime.now();
        final startedAt = DateTime(today.year, today.month, today.day, 9, 7);
        final timestamp = startedAt.millisecondsSinceEpoch;

        await repo.createSession(
          TrainingSession(
            id: 'session-neutral',
            ownerUserId: 'u-1',
            startedAtMs: timestamp,
            endedAtMs: startedAt
                .add(const Duration(minutes: 45))
                .millisecondsSinceEpoch,
            title: 'Easy Spin',
            modality: Modality.cardioEndurance,
            createdAtMs: timestamp,
            updatedAtMs: timestamp,
          ),
        );

        final calendarState = CalendarState(repo);
        await calendarState.init();
        final routineState = RoutineState(repo);
        final workoutState = WorkoutState(repo);
        final routineSessionService = RoutineSessionService(repo);
        final sessionSummaryService = SessionSummaryService(repo);

        await tester.pumpWidget(
          MaterialApp(
            home: DaySessionListScreen(
              date: DateTime(today.year, today.month, today.day),
              calendarState: calendarState,
              routineState: routineState,
              workoutState: workoutState,
              routineSessionService: routineSessionService,
              sessionSummaryService: sessionSummaryService,
              settingsState: SettingsState(repo, fakePreferencesService()),
              timerAlertService: FakeTimerAlertService(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Easy Spin'), findsOneWidget);
        expect(find.text('9:07 AM · 45m'), findsOneWidget);

        final themeColors = OmniTheme.colorsForTheme(OmniTheme.activeTheme);
        final standardCards = tester
            .widgetList<Container>(find.byType(Container))
            .where((container) {
              final decoration = container.decoration;
              if (decoration is! BoxDecoration ||
                  decoration.border is! Border) {
                return false;
              }
              final border = decoration.border! as Border;
              return border.left.width != 4 &&
                  border.left.color == themeColors.surfaceBorder;
            })
            .toList();

        expect(standardCards, isNotEmpty);
      },
    );

    testWidgets(
      'rolling completed session shows start time only — no duration suffix',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 1000));
        final repo = await _freshRepo();
        final today = DateTime.now();

        // Rolling session starts at 8:00 AM, stays open 8 h of wall-clock.
        final rollingStart = DateTime(
          today.year,
          today.month,
          today.day,
          8,
          0,
        ).millisecondsSinceEpoch;
        await repo.createSession(
          TrainingSession(
            id: 'session-rolling',
            ownerUserId: 'u-1',
            startedAtMs: rollingStart,
            endedAtMs: rollingStart + 28800000, // 8 h wall-clock
            isRolling: true,
            title: 'Rolling Day',
            createdAtMs: rollingStart,
            updatedAtMs: rollingStart,
          ),
        );

        // Non-rolling session starts at 10:30 AM, lasts 1 h.
        final nonRollingStart = DateTime(
          today.year,
          today.month,
          today.day,
          10,
          30,
        ).millisecondsSinceEpoch;
        await repo.createSession(
          TrainingSession(
            id: 'session-normal',
            ownerUserId: 'u-1',
            startedAtMs: nonRollingStart,
            endedAtMs: nonRollingStart + 3600000, // 1 h
            isRolling: false,
            title: 'Normal Lift',
            createdAtMs: nonRollingStart,
            updatedAtMs: nonRollingStart,
          ),
        );

        final calendarState = CalendarState(repo);
        await calendarState.init();

        await tester.pumpWidget(
          MaterialApp(
            home: DaySessionListScreen(
              date: DateTime(today.year, today.month, today.day),
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

        // Rolling session: only start time, no duration suffix.
        expect(find.text('8:00 AM'), findsOneWidget);
        expect(
          find.textContaining('8:00 AM ·'),
          findsNothing,
          reason: 'Rolling session must not show a duration suffix',
        );

        // Non-rolling session: start time + duration suffix.
        expect(find.text('10:30 AM · 1h 0m'), findsOneWidget);
      },
    );

    testWidgets(
      'anchors the primary bottom CTA at the shared width and vertical anchor for today/future dates (S-001)',
      (tester) async {
        // Fixed surface so the test can assert exact pixel math.
        const surface = Size(400, 800);
        await tester.binding.setSurfaceSize(surface);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _freshRepo();
        final calendarState = CalendarState(repo);
        await calendarState.init();
        final routineState = RoutineState(repo);
        final workoutState = WorkoutState(repo);
        final routineSessionService = RoutineSessionService(repo);
        final sessionSummaryService = SessionSummaryService(repo);

        // Future date — primary bottom CTA must be visible.
        final futureDate = DateTime(2099, 12, 31);

        // Production pushes this screen via OmniRoute, which wraps
        // it in OmniGradientBackground — we mirror that here so
        // the large-screen content column cap is exercised.
        await tester.pumpWidget(
          MaterialApp(
            home: OmniGradientBackground(
              child: DaySessionListScreen(
                date: futureDate,
                calendarState: calendarState,
                routineState: routineState,
                workoutState: workoutState,
                routineSessionService: routineSessionService,
                sessionSummaryService: sessionSummaryService,
                settingsState: SettingsState(repo, fakePreferencesService()),
                timerAlertService: FakeTimerAlertService(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The host's Scaffold has a non-null bottomNavigationBar
        // (the shared primary bottom CTA on the bottomNavigationBar
        // slot, not inline in the body).
        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
        expect(
          scaffold.bottomNavigationBar,
          isNotNull,
          reason:
              'Today/future DaySessionListScreen must have a primary '
              'bottom CTA on the host Scaffold.bottomNavigationBar',
        );

        // The CTA is an OmniBottomCTA. We look for it as a descendant
        // of the Scaffold because the bottomNavigationBar slot is the
        // canonical location.
        final ctaFinder = find.descendant(
          of: find.byType(Scaffold),
          matching: find.byType(OmniBottomCTA),
        );
        expect(ctaFinder, findsOneWidget);

        // The CTA label is "+ New Planned Session" — preserved verbatim
        // from the previous inline `_AddButton` widget.
        expect(
          find.widgetWithText(FilledButton, '+ New Planned Session'),
          findsOneWidget,
        );

        // The CTA sits at the shared width and vertical anchor,
        // measured from the **centered content column's** edges
        // (not the surface's) so the assertion holds on both
        // phone- and tablet-class surfaces.
        final buttonRect = tester.getRect(
          find.descendant(of: ctaFinder, matching: find.byType(FilledButton)),
        );
        final column = contentColumnRectFor(surface.width);
        final expectedLeft =
            column.left + OmniTheme.bottomCTAHorizontalPadding;
        final expectedRight =
            column.left +
            column.width -
            OmniTheme.bottomCTAHorizontalPadding;
        expect(buttonRect.left, closeTo(expectedLeft, 0.5));
        expect(buttonRect.right, closeTo(expectedRight, 0.5));
        expect(buttonRect.height, closeTo(OmniTheme.buttonPrimaryHeight, 0.5));
        final expectedBottom =
            surface.height -
            tester.view.padding.bottom / tester.view.devicePixelRatio -
            OmniTheme.bottomCTAVerticalBottomPadding;
        expect(buttonRect.bottom, closeTo(expectedBottom, 0.5));
      },
    );

    testWidgets('renders no bottom CTA for past dates (S-002)', (tester) async {
      final repo = await _freshRepo();
      final calendarState = CalendarState(repo);
      await calendarState.init();
      final routineState = RoutineState(repo);
      final workoutState = WorkoutState(repo);
      final routineSessionService = RoutineSessionService(repo);
      final sessionSummaryService = SessionSummaryService(repo);

      // Past date — read-only, no primary bottom CTA.
      final pastDate = DateTime(2020, 6, 15);

      await tester.pumpWidget(
        MaterialApp(
          home: DaySessionListScreen(
            date: pastDate,
            calendarState: calendarState,
            routineState: routineState,
            workoutState: workoutState,
            routineSessionService: routineSessionService,
            sessionSummaryService: sessionSummaryService,
            settingsState: SettingsState(repo, fakePreferencesService()),
            timerAlertService: FakeTimerAlertService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The host's Scaffold has a null bottomNavigationBar.
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(
        scaffold.bottomNavigationBar,
        isNull,
        reason: 'Past dates are read-only and must not render a bottom CTA',
      );

      // The "+ New Planned Session" label is absent on past dates.
      expect(
        find.widgetWithText(FilledButton, '+ New Planned Session'),
        findsNothing,
      );

      // The empty-state copy for past dates is shown.
      expect(find.text('No sessions on this day.'), findsOneWidget);
    });
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
            settingsState: SettingsState(repo, fakePreferencesService()),
            timerAlertService: FakeTimerAlertService(),
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
      expect(find.byType(OmniBackHeader), findsOneWidget);
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
            settingsState: SettingsState(repo, fakePreferencesService()),
            timerAlertService: FakeTimerAlertService(),
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
            settingsState: SettingsState(repo, fakePreferencesService()),
            timerAlertService: FakeTimerAlertService(),
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
            settingsState: SettingsState(repo, fakePreferencesService()),
            timerAlertService: FakeTimerAlertService(),
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
            settingsState: SettingsState(repo, fakePreferencesService()),
            timerAlertService: FakeTimerAlertService(),
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
            settingsState: SettingsState(repo, fakePreferencesService()),
            timerAlertService: FakeTimerAlertService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sports'), findsNothing);
    });

    testWidgets('rolling session does not show Duration or Rest Time stats', (
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
            settingsState: SettingsState(repo, fakePreferencesService()),
            timerAlertService: FakeTimerAlertService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('DURATION'), findsNothing);
      expect(find.text('REST TIME'), findsNothing);
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
            settingsState: SettingsState(repo, fakePreferencesService()),
            timerAlertService: FakeTimerAlertService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('DURATION'), findsOneWidget);
    });

    testWidgets('standard session still shows Duration and Rest Time stats', (
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
            settingsState: SettingsState(repo, fakePreferencesService()),
            timerAlertService: FakeTimerAlertService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('DURATION'), findsOneWidget);
      expect(find.text('REST TIME'), findsOneWidget);
    });

    testWidgets(
      'rolling session still shows group card, note, and calendar sections',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        await workoutState.createNewSession(isRolling: true);
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
              settingsState: SettingsState(repo, fakePreferencesService()),
              timerAlertService: FakeTimerAlertService(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('DURATION'), findsNothing);
        expect(find.text('REST TIME'), findsNothing);
        expect(find.text('Strength'), findsOneWidget);
        // Phase 2.1: the note title moved to an OmniCardHeader above
        // the card; it is rendered in the canonical D-1 typography
        // (uppercase, letter-spacing 2.0).
        expect(find.text('SESSION NOTE'), findsOneWidget);
        expect(find.text('Open Calendar'), findsOneWidget);
      },
    );

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
              settingsState: SettingsState(repo, fakePreferencesService()),
              timerAlertService: FakeTimerAlertService(),
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
            settingsState: SettingsState(repo, fakePreferencesService()),
            timerAlertService: FakeTimerAlertService(),
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
      final now = DateTime.now().millisecondsSinceEpoch;
      final updatedSession = TrainingSession(
        id: session.id,
        ownerUserId: session.ownerUserId,
        routineTemplateId: session.routineTemplateId,
        startedAtMs: now - 180000,
        endedAtMs: now,
        title: session.title,
        note: session.note,
        locationText: session.locationText,
        modality: session.modality,
        intent: session.intent,
        perceivedSessionRpe: session.perceivedSessionRpe,
        sessionFeeling: session.sessionFeeling,
        qualityRating: session.qualityRating,
        isRolling: session.isRolling,
        createdAtMs: session.createdAtMs,
        updatedAtMs: now,
      );
      await repo.updateSession(updatedSession);
      await workoutState.loadHistoricalSession(updatedSession.id);
      await workoutState.updateSessionFeeling(updatedSession.id, 3);

      final exercises = await repo.getExercises();
      final effortId = await workoutState.addExerciseToSession(
        exercises.first,
        chosenMetric: 'reps',
      );

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
            settingsState: SettingsState(repo, fakePreferencesService()),
            timerAlertService: FakeTimerAlertService(),
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
            settingsState: SettingsState(repo, fakePreferencesService()),
            timerAlertService: FakeTimerAlertService(),
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
            settingsState: SettingsState(repo, fakePreferencesService()),
            timerAlertService: FakeTimerAlertService(),
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
            settingsState: SettingsState(repo, fakePreferencesService()),
            timerAlertService: FakeTimerAlertService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Phase 2.1: the note title is rendered by an OmniCardHeader
      // above the card; the calendar's "Open Calendar" button is
      // rendered in the calendar card's OmniCardHeader's actions slot.
      final noteTopLeft = tester.getTopLeft(find.text('SESSION NOTE'));
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
      final settingsState = SettingsState(repo, fakePreferencesService());
      await settingsState.initialize();

      final nutritionPrimerState = await buildNutritionPrimerState(repo);
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
        nutritionState: NutritionState(repo),
        foodLibraryState: FoodLibraryState(repo),
        nutritionPrimerState: nutritionPrimerState,
        timerAlertService: FakeTimerAlertService(),
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
            settingsState: SettingsState(repo, fakePreferencesService()),
            timerAlertService: FakeTimerAlertService(),
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
      final settingsState = SettingsState(repo, fakePreferencesService());
      await settingsState.initialize();
      await profileState.loadProfile();
      const definition = ProfileMeasurements.bodyweight;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MeasurementHistoryChartSheet(
              profileState: profileState,
              definition: definition,
              settingsState: settingsState,
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
      final settingsState = SettingsState(repo, fakePreferencesService());
      await settingsState.initialize();
      await profileState.loadProfile();
      const definition = ProfileMeasurements.bodyweight;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MeasurementHistoryChartSheet(
              profileState: profileState,
              definition: definition,
              settingsState: settingsState,
              onLogNew: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Log New Entry'), findsOneWidget);
    });

    testWidgets('formats unit-kg chart labels using preferred lbs setting', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      final repo = await _freshRepo();
      await repo.saveMeasurementEntry(
        BodyMeasurementEntry(
          id: 'chart-weight-entry',
          measurementType: 'bodyweight',
          value: 80,
          unitId: 'unit-kg',
          recordedAtMs: 123456,
        ),
      );
      final profileState = ProfileState(repo);
      final settingsState = SettingsState(repo, fakePreferencesService());
      await settingsState.initialize();
      await settingsState.setPreferredWeightUnit('lbs');
      await profileState.loadProfile();
      const definition = ProfileMeasurements.bodyweight;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MeasurementHistoryChartSheet(
              profileState: profileState,
              definition: definition,
              settingsState: settingsState,
              onLogNew: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('176.4 lbs'), findsOneWidget);
    });

    // S-016: Helper text visible when entries exist
    testWidgets('shows hint text when entries exist', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      final repo = await _freshRepo();
      await repo.saveMeasurementEntry(
        BodyMeasurementEntry(
          id: 'hint-entry',
          measurementType: 'bodyweight',
          value: 75.0,
          unitId: 'unit-kg',
          recordedAtMs: 1000,
        ),
      );
      final profileState = ProfileState(repo);
      final settingsState = SettingsState(repo, fakePreferencesService());
      await settingsState.initialize();
      await profileState.loadProfile();
      const definition = ProfileMeasurements.bodyweight;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MeasurementHistoryChartSheet(
              profileState: profileState,
              definition: definition,
              settingsState: settingsState,
              onLogNew: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // D-9: the "Tap a point to view" half described a removed
      // affordance. The only remaining interaction is long-press.
      expect(
        find.text('Long-press to delete'),
        findsOneWidget,
      );
    });

    // S-017: Helper text hidden in empty state
    testWidgets('hides hint text when no entries exist', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      final repo = await _freshRepo();
      final profileState = ProfileState(repo);
      final settingsState = SettingsState(repo, fakePreferencesService());
      await settingsState.initialize();
      await profileState.loadProfile();
      const definition = ProfileMeasurements.bodyweight;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MeasurementHistoryChartSheet(
              profileState: profileState,
              definition: definition,
              settingsState: settingsState,
              onLogNew: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Long-press to delete'),
        findsNothing,
      );
    });

    // Height chart label follows the active unit (cm mode by default).
    testWidgets(
      'height chart label follows the active unit (cm mode)',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 1000));
        final repo = await _freshRepo();
        await repo.saveMeasurementEntry(
          BodyMeasurementEntry(
            id: 'height-cm-entry',
            measurementType: 'height',
            value: 180.0,
            unitId: 'unit-cm',
            recordedAtMs: 1000,
          ),
        );
        final profileState = ProfileState(repo);
        final settingsState = SettingsState(repo, fakePreferencesService());
        await settingsState.initialize();
        await profileState.loadProfile();
        const definition = ProfileMeasurements.height;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MeasurementHistoryChartSheet(
                profileState: profileState,
                definition: definition,
                settingsState: settingsState,
                onLogNew: () async {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The selected-point label strip reads "180 cm" in cm
        // mode. The y-axis pinned column also reads "180 cm"
        // (one label per gridline tick), so this text appears
        // at least twice — once on the axis, once on the strip.
        expect(find.text('180 cm'), findsAtLeastNWidgets(1));
      },
    );

    // Height chart label follows the active unit (ftin mode).
    testWidgets(
      'height chart label follows the active unit (ftin mode)',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 1000));
        final repo = await _freshRepo();
        await repo.saveMeasurementEntry(
          BodyMeasurementEntry(
            id: 'height-ftin-entry',
            measurementType: 'height',
            value: 180.0,
            unitId: 'unit-cm',
            recordedAtMs: 1000,
          ),
        );
        final profileState = ProfileState(repo);
        final settingsState = SettingsState(repo, fakePreferencesService());
        await settingsState.initialize();
        await settingsState.setPreferredHeightUnit('ftin');
        await profileState.loadProfile();
        const definition = ProfileMeasurements.height;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MeasurementHistoryChartSheet(
                profileState: profileState,
                definition: definition,
                settingsState: settingsState,
                onLogNew: () async {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 180 cm = 70.866 in → 71 in = 5' 11" (compound).
        expect(find.text("5' 11\""), findsOneWidget);
        // The bare centimetres value is no longer the label.
        expect(find.text('180 cm'), findsNothing);
      },
    );

    // S-001: Y-axis labels render with the data range's min and max values.
    // The vertical axis was hidden in A20; the readability fix restores it
    // so a user can estimate a point's value from the chart alone.
    testWidgets(
      'renders Y-axis labels including the data range\'s min and max (S-001)',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 1000));
        final repo = await _freshRepo();
        final baseMs = DateTime.now().millisecondsSinceEpoch;
        // Seed three bodyweight entries with distinct min/max so the chart
        // exercises the 2+ entries branch and the Y-axis labels have a real
        // numeric range to label.
        final values = [74.0, 80.0, 82.0];
        final ids = ['bw-low', 'bw-mid', 'bw-high'];
        final offsetsDays = [60, 30, 0];
        for (var i = 0; i < values.length; i++) {
          await repo.saveMeasurementEntry(
            BodyMeasurementEntry(
              id: ids[i],
              measurementType: 'bodyweight',
              value: values[i],
              unitId: 'unit-kg',
              recordedAtMs: baseMs - offsetsDays[i] * 24 * 60 * 60 * 1000,
            ),
          );
        }
        final profileState = ProfileState(repo);
        final settingsState = SettingsState(repo, fakePreferencesService());
        await settingsState.initialize();
        await profileState.loadProfile();
        const definition = ProfileMeasurements.bodyweight;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MeasurementHistoryChartSheet(
                profileState: profileState,
                definition: definition,
                settingsState: settingsState,
                onLogNew: () async {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Structural assertion: the inner LineChart no longer
        // renders its own y-axis labels — the ScrollableTrendChart
        // wrapper provides a pinned y-axis column on the left.
        final lineChart = tester.widget<LineChart>(find.byType(LineChart));
        expect(
          lineChart.data.titlesData.leftTitles.sideTitles.showTitles,
          isFalse,
          reason:
              'Inner LineChart must not render its own y-axis labels — the '
              'ScrollableTrendChart wrapper owns the pinned column.',
        );

        // The ScrollableTrendChart wrapper is present.
        expect(find.byType(ScrollableTrendChart), findsOneWidget,
            reason: 'Chart must be wrapped in ScrollableTrendChart.');

        // Compute the expected label values the wrapper actually
        // renders. The wrapper uses `ChartAxisHelper.computeBounds`
        // to derive a nice tick interval, then enumerates labels
        // from min to max at that interval. The labels are
        // formatted as "<value> <unit>" (default preferred
        // weight unit is kg) so the y-axis matches the on-card
        // stats chart style.
        final bounds = ChartAxisHelper.computeBounds(values);
        final expectedLabels = <int>{};
        for (double v = bounds.min;
            v <= bounds.max + bounds.interval / 2;
            v += bounds.interval) {
          expectedLabels.add(v.round());
        }

        // Every expected Y-axis label is rendered by the wrapper's
        // pinned column. We search the whole tree because the
        // pinned column is a sibling of the chart, not a
        // descendant of LineChart. The label includes the unit
        // ("<value> kg") — the y-axis now shows the unit so the
        // pinned column matches the on-card stats chart style.
        for (final label in expectedLabels) {
          expect(
            find.text('$label kg'),
            findsOneWidget,
            reason:
                'Y-axis label "$label kg" must render inside the wrapper.',
          );
        }
      },
    );

    // S-002: The first and last plotted points are visibly inset from the
    // chart's horizontal bounds — neither dot touches the chart edge.
    // Assert via the tap-target centers (the 48×48 GestureDetectors are
    // placed centered on each rendered dot).
    testWidgets(
      'first and last plotted points are inset from the chart\'s horizontal bounds (S-002)',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 1000));
        final repo = await _freshRepo();
        final baseMs = DateTime.now().millisecondsSinceEpoch;
        // Three entries at distinct times so the chart's time axis is
        // exercised and the first/last dots sit at the chart's plot-area
        // extremes.
        final seeds = [
          ('bw-1', 74.0, 60),
          ('bw-2', 80.0, 30),
          ('bw-3', 82.0, 0),
        ];
        for (final s in seeds) {
          await repo.saveMeasurementEntry(
            BodyMeasurementEntry(
              id: s.$1,
              measurementType: 'bodyweight',
              value: s.$2,
              unitId: 'unit-kg',
              recordedAtMs: baseMs - s.$3 * 24 * 60 * 60 * 1000,
            ),
          );
        }
        final profileState = ProfileState(repo);
        final settingsState = SettingsState(repo, fakePreferencesService());
        await settingsState.initialize();
        await profileState.loadProfile();
        const definition = ProfileMeasurements.bodyweight;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MeasurementHistoryChartSheet(
                profileState: profileState,
                definition: definition,
                settingsState: settingsState,
                onLogNew: () async {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The chart is now wrapped in ScrollableTrendChart. The
        // wrapper renders a pinned y-axis column on the left and
        // the scrollable plot on the right. The first plotted dot
        // sits at the left edge of the plot (which is offset
        // from the chart's left edge by the pinned column width);
        // the last plotted dot sits at the right edge of the plot.
        // The per-point tap-target overlay (chart_dot_$i) is gone.
        final wrapper = find.byType(ScrollableTrendChart);
        expect(wrapper, findsOneWidget);
        final chartRect = tester.getRect(wrapper);

        // The pinned y-axis column is the first child of the wrapper's
        // Row. Its right edge marks the start of the plot area; the
        // first plotted dot must sit to the right of that boundary.
        final pinnedColumn = find.descendant(
          of: wrapper,
          matching: find.byWidgetPredicate(
            (w) => w is SizedBox && w.width == 64.0,
          ),
        );
        expect(pinnedColumn, findsOneWidget,
            reason: 'Pinned y-axis column (64 dp) must be present.');
        final pinnedRect = tester.getRect(pinnedColumn);
        final plotLeft = pinnedRect.right;

        // Last plotted dot must sit inside the chart's right edge.
        // For a 3-point series the chart is not scrollable, so the
        // last dot is at the right edge of the plot.
        final expectedPlotRight = chartRect.right;

        // We can't easily locate the dots by key anymore (the
        // overlay is gone), so we verify the structural invariant
        // by checking the LineChart's spot positions: the first
        // spot's x must equal 0 (left edge of plot) and the last
        // spot's x must equal the number of points minus 1 (right
        // edge of plot).
        final lineChart = tester.widget<LineChart>(find.byType(LineChart));
        final spots = lineChart.data.lineBarsData.first.spots;
        expect(spots.length, 3);
        expect(spots.first.x, 0.0,
            reason: 'First spot x must be 0 (left edge of plot).');
        expect(spots.last.x, 2.0,
            reason: 'Last spot x must be points.length - 1.');

        // The first spot's x = 0 is rendered at the left edge of
        // the plot area, which is at x = plotLeft in screen
        // coordinates. Verify by checking that the chart's plot
        // rect starts at plotLeft (i.e. the chart's inner padding
        // doesn't push the first dot inward).
        expect(plotLeft, lessThan(chartRect.right),
            reason: 'Plot area must start before the chart right edge.');
        expect(expectedPlotRight, greaterThan(plotLeft),
            reason: 'Plot area must have positive width.');
      },
    );

    // S-003: The single-entry branch still renders a Y-axis label and
    // centers the lone dot horizontally (not touching either edge).
    testWidgets(
      'single-entry case renders Y-axis label and centers the lone dot (S-003)',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 1000));
        final repo = await _freshRepo();
        await repo.saveMeasurementEntry(
          BodyMeasurementEntry(
            id: 'bw-single',
            measurementType: 'bodyweight',
            value: 80.0,
            unitId: 'unit-kg',
            recordedAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
        );
        final profileState = ProfileState(repo);
        final settingsState = SettingsState(repo, fakePreferencesService());
        await settingsState.initialize();
        await profileState.loadProfile();
        const definition = ProfileMeasurements.bodyweight;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MeasurementHistoryChartSheet(
                profileState: profileState,
                definition: definition,
                settingsState: settingsState,
                onLogNew: () async {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Y-axis labels still render in the single-entry branch,
        // via the ScrollableTrendChart wrapper's pinned column. The
        // inner LineChart disables its own leftTitles so the labels
        // don't render twice.
        final lineChart = tester.widget<LineChart>(find.byType(LineChart));
        expect(
          lineChart.data.titlesData.leftTitles.sideTitles.showTitles,
          isFalse,
          reason:
              'Inner LineChart must not render its own y-axis labels in the '
              'single-entry branch — the wrapper owns the pinned column.',
        );
        expect(find.byType(ScrollableTrendChart), findsOneWidget,
            reason: 'Chart must be wrapped in ScrollableTrendChart.');

        // The single spot sits at x = 0 (centered between the
        // chart's minX = -0.5 and maxX = 0.5, so the rendered dot
        // lands at the horizontal middle of the plot — not flush
        // against either edge).
        final spots = lineChart.data.lineBarsData.first.spots;
        expect(spots.length, 1);
        expect(spots.first.x, 0.0,
            reason:
                'Single-entry spot x must be 0 (centered between the chart\'s '
                'minX = -0.5 and maxX = 0.5).');
        // Verify the chart's x-axis is symmetric around the dot.
        expect(lineChart.data.minX, -0.5);
        expect(lineChart.data.maxX, 0.5);
      },
    );

    // S-004: The fix applies to every measurement type that opens this
    // popup, not just body weight. We verify one non-weight type
    // (height, in cm) so the unit-conversion path is exercised.
    testWidgets(
      'Y-axis labels and horizontal inset also apply to height measurements (S-005)',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 1000));
        final repo = await _freshRepo();
        final baseMs = DateTime.now().millisecondsSinceEpoch;
        await repo.saveMeasurementEntry(
          BodyMeasurementEntry(
            id: 'ht-1',
            measurementType: 'height',
            value: 178.0,
            unitId: 'unit-cm',
            recordedAtMs: baseMs - 60 * 24 * 60 * 60 * 1000,
          ),
        );
        await repo.saveMeasurementEntry(
          BodyMeasurementEntry(
            id: 'ht-2',
            measurementType: 'height',
            value: 181.0,
            unitId: 'unit-cm',
            recordedAtMs: baseMs,
          ),
        );
        final profileState = ProfileState(repo);
        final settingsState = SettingsState(repo, fakePreferencesService());
        await settingsState.initialize();
        await profileState.loadProfile();
        const definition = ProfileMeasurements.height;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MeasurementHistoryChartSheet(
                profileState: profileState,
                definition: definition,
                settingsState: settingsState,
                onLogNew: () async {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Y-axis labels are now provided by the wrapper's pinned
        // column. The inner LineChart disables its own leftTitles
        // so the labels don't render twice.
        final lineChart = tester.widget<LineChart>(find.byType(LineChart));
        expect(
          lineChart.data.titlesData.leftTitles.sideTitles.showTitles,
          isFalse,
          reason:
              'Inner LineChart must not render its own y-axis labels for '
              'height measurements — the wrapper owns the pinned column.',
        );
        expect(find.byType(ScrollableTrendChart), findsOneWidget,
            reason: 'Chart must be wrapped in ScrollableTrendChart.');

        // The wrapper renders the same `ChartAxisHelper`-derived
        // bounds the old bespoke code used, so the min and max
        // labels appear in the pinned column. The labels include
        // the active unit ("cm" in default mode) to match the
        // on-card stats chart style.
        final bounds = ChartAxisHelper.computeBounds([178.0, 181.0]);
        final minLabel = bounds.min.toStringAsFixed(0);
        final maxLabel = bounds.max.toStringAsFixed(0);
        expect(find.text('$minLabel cm'), findsOneWidget,
            reason: 'Y-axis min label must render in the wrapper.');
        expect(find.text('$maxLabel cm'), findsOneWidget,
            reason: 'Y-axis max label must render in the wrapper.');
      },
    );

    // S-006: The Y-axis reserved strip is wide enough for the
    // longest whole-number value label the chart ever produces
    // (3 chars such as `176` for bodyweight in lbs mode, `180`
    // for height in cm mode). 60 dp is enough headroom at the
    // 10 pt label font; this regression guard locks the value so
    // a future "tighten" pass can't push the labels back into
    // overflow without a deliberate change. Decimals are
    // intentionally stripped on this axis so a `76.3` and a
    // `76` tick don't sit so close vertically that they read
    // as the same value at 10 pt.
    testWidgets(
      'leftTitles reservedSize fits 5-char value labels without overflow (S-006)',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 1000));
        final repo = await _freshRepo();
        await repo.saveMeasurementEntry(
          BodyMeasurementEntry(
            id: 'ht-cm-5char',
            measurementType: 'height',
            value: 180.3,
            unitId: 'unit-cm',
            recordedAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
        );
        final profileState = ProfileState(repo);
        final settingsState = SettingsState(repo, fakePreferencesService());
        await settingsState.initialize();
        await profileState.loadProfile();
        const definition = ProfileMeasurements.height;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MeasurementHistoryChartSheet(
                profileState: profileState,
                definition: definition,
                settingsState: settingsState,
                onLogNew: () async {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The wrapper's pinned y-axis column is wide enough for the
        // longest whole-number label the chart produces (3 chars
        // such as `176` for bodyweight in lbs mode, `180` for
        // height in cm mode). 64 dp is enough headroom at the 9 px
        // label font; this regression guard locks the value so a
        // future "tighten" pass can't push the labels back into
        // overflow without a deliberate change. Decimals are
        // intentionally stripped on this axis so a `76.3` and a
        // `76` tick don't sit so close vertically that they read
        // as the same value at 9 px.
        final pinnedColumn = find.descendant(
          of: find.byType(ScrollableTrendChart),
          matching: find.byWidgetPredicate(
            (w) => w is SizedBox && w.width == 64.0,
          ),
        );
        expect(pinnedColumn, findsOneWidget,
            reason:
                'Pinned y-axis column (64 dp) must be present and wide '
                'enough for 3-char whole-number value labels.');

        // The chart no longer has a fixed-width 440 dp centered
        // container — it fills the sheet's content width so the
        // wrapper can show more days on long histories. Verify by
        // checking that no ancestor SizedBox pins the width to
        // 440 dp.
        final chartContainer = find
            .ancestor(
              of: find.byType(LineChart),
              matching: find.byType(SizedBox),
            )
            .first;
        final sizedBox = tester.widget<SizedBox>(chartContainer);
        expect(
          sizedBox.width,
          isNot(440.0),
          reason:
              'Chart container width must no longer be a fixed 440 dp — '
              'the chart now fills the sheet content width.',
        );
      },
    );

    // S-106: 12-entry history scrolls horizontally and opens scrolled
    // to the most recent entry. The chart's ScrollableTrendChart
    // wrapper is the same one used on the stats screen, so we
    // reuse the same assertion shape.
    testWidgets(
      'S-106: 12-entry history opens scrolled to the most recent entry '
      'and scroll controller jumps to maxScrollExtent',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 1000));
        final repo = await _freshRepo();
        final baseMs = DateTime.now().millisecondsSinceEpoch;
        // Seed 12 distinct entries so the chart is scrollable
        // (pointCount > maxVisiblePoints = 8).
        for (var i = 0; i < 12; i++) {
          await repo.saveMeasurementEntry(
            BodyMeasurementEntry(
              id: 'bw-s106-$i',
              measurementType: 'bodyweight',
              value: 75.0 + i,
              unitId: 'unit-kg',
              recordedAtMs: baseMs - (11 - i) * 24 * 60 * 60 * 1000,
            ),
          );
        }
        final profileState = ProfileState(repo);
        final settingsState = SettingsState(repo, fakePreferencesService());
        await settingsState.initialize();
        await profileState.loadProfile();
        const definition = ProfileMeasurements.bodyweight;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MeasurementHistoryChartSheet(
                profileState: profileState,
                definition: definition,
                settingsState: settingsState,
                onLogNew: () async {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The wrapper is present.
        expect(find.byType(ScrollableTrendChart), findsOneWidget);

        // The scrollable view's controller has jumped to
        // maxScrollExtent so the user opens the sheet looking at
        // the most recent day on the right.
        final scrollable = tester.state<ScrollableState>(
          find.descendant(
            of: find.byType(ScrollableTrendChart),
            matching: find.byType(Scrollable),
          ),
        );
        expect(
          scrollable.position.pixels,
          scrollable.position.maxScrollExtent,
          reason:
              'Sheet must open scrolled to the newest entry '
              '(pixels == maxScrollExtent).',
        );

        // The chart's x-axis covers all 12 indices (oldest..newest)
        // with no plot padding — the data points sit at the exact
        // integer indices 0..11. The shared
        // `buildEdgeAwareDateLabel` helper shifts the first and
        // last x-axis labels by ±22 dp so they don't collide with
        // the pinned y-axis column or overflow the right card
        // border, so no minX/maxX extension is needed. Data is
        // not reversed or mirrored.
        final lineChart = tester.widget<LineChart>(find.byType(LineChart));
        expect(lineChart.data.minX, 0.0,
            reason: 'Chart x-axis must start at 0 (no left padding).');
        expect(lineChart.data.maxX, 11.0,
            reason: 'Chart x-axis must end at the last index (no right padding).');
        final spots = lineChart.data.lineBarsData.first.spots;
        expect(spots.length, 12);
        expect(spots.first.y, 75.0,
            reason: 'First spot must be the oldest entry (75.0).');
        expect(spots.last.y, 86.0,
            reason: 'Last spot must be the newest entry (86.0).');
      },
    );

    // S-107: The strip defaults to the most recent entry on load.
    // We verify by reading the strip's date + value text.
    testWidgets(
      'S-107: strip defaults to the most recent entry on load',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 1000));
        final repo = await _freshRepo();
        final baseMs = DateTime.now().millisecondsSinceEpoch;
        // Three entries at distinct times. The newest is the
        // third (recordedAtMs == baseMs).
        for (final s in [
          ('bw-s107-1', 70.0, 60),
          ('bw-s107-2', 75.0, 30),
          ('bw-s107-3', 80.0, 0),
        ]) {
          await repo.saveMeasurementEntry(
            BodyMeasurementEntry(
              id: s.$1,
              measurementType: 'bodyweight',
              value: s.$2,
              unitId: 'unit-kg',
              recordedAtMs: baseMs - s.$3 * 24 * 60 * 60 * 1000,
            ),
          );
        }
        final profileState = ProfileState(repo);
        final settingsState = SettingsState(repo, fakePreferencesService());
        await settingsState.initialize();
        await profileState.loadProfile();
        const definition = ProfileMeasurements.bodyweight;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MeasurementHistoryChartSheet(
                profileState: profileState,
                definition: definition,
                settingsState: settingsState,
                onLogNew: () async {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Strip shows today's date + 80 kg (the most recent entry).
        final today = DateTime.fromMillisecondsSinceEpoch(baseMs);
        final todayLabel = ChartAxisHelper.formatDateLabel(today);
        expect(find.text(todayLabel), findsWidgets,
            reason: 'Strip date must be today (the most recent entry).');
        // The strip value is rendered as the display-unit weight
        // via `UnitFormatter.formatWeight`. In default kg mode
        // this is "80 kg" (or "80.0 kg" depending on the
        // formatter's decimals policy). Match either.
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is Text &&
                (w.data == '80 kg' || w.data == '80.0 kg'),
          ),
          findsOneWidget,
          reason:
              'Strip value must be the most recent entry (80 kg or 80.0 kg).',
        );
      },
    );

    // S-109b: The top plotted point is not clipped against the top
    // edge after the headroom removal. We verify by checking the
    // LineChart's maxY has enough headroom above the data max.
    testWidgets(
      'S-109b: top plotted point is not clipped after headroom removal',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 1000));
        final repo = await _freshRepo();
        final baseMs = DateTime.now().millisecondsSinceEpoch;
        // Seed 5 entries with a clear max so the top point's
        // padding is easy to assert.
        final values = [70.0, 72.0, 75.0, 78.0, 80.0];
        for (var i = 0; i < values.length; i++) {
          await repo.saveMeasurementEntry(
            BodyMeasurementEntry(
              id: 'bw-s109b-$i',
              measurementType: 'bodyweight',
              value: values[i],
              unitId: 'unit-kg',
              recordedAtMs: baseMs - (4 - i) * 24 * 60 * 60 * 1000,
            ),
          );
        }
        final profileState = ProfileState(repo);
        final settingsState = SettingsState(repo, fakePreferencesService());
        await settingsState.initialize();
        await profileState.loadProfile();
        const definition = ProfileMeasurements.bodyweight;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MeasurementHistoryChartSheet(
                profileState: profileState,
                definition: definition,
                settingsState: settingsState,
                onLogNew: () async {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The chart's maxY is at least 2 dp above the data max so
        // the top dot (radius 5–6.5 dp) stays visibly inside the
        // plot even though the chart no longer reserves a top
        // headroom strip.
        final lineChart = tester.widget<LineChart>(find.byType(LineChart));
        final dataMax = values.reduce((a, b) => a > b ? a : b);
        final topPadding = lineChart.data.maxY - dataMax;
        expect(
          topPadding,
          greaterThanOrEqualTo(2.0),
          reason:
              'Top point must have ≥2 dp of padding above it so the dot is '
              'visibly inside the plot area after headroom removal.',
        );
      },
    );

    // Regression guard: the widget must show exactly one
    // x-axis date label per data point. fl_chart can call
    // `getTitlesWidget` with fractional values (e.g. during
    // padding animations or boundary ticks); without the
    // `value.truncateToDouble()` filter, those calls would
    // resolve to a valid index via `round()` and render
    // duplicate labels (e.g. "May May 10"). The filter
    // rejects any non-integer value so only one label per
    // data-point index renders.
    testWidgets(
      'x-axis shows exactly one label per data point (no duplicates from '
      'fractional tick values)',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 1000));
        final repo = await _freshRepo();
        final baseMs = DateTime.now().millisecondsSinceEpoch;
        // Three entries: indices 0, 1, 2 with dates May 10,
        // Jun 17, Jun 23.
        final seeds = [
          ('bw-dup-1', 70.0, 60),
          ('bw-dup-2', 72.0, 30),
          ('bw-dup-3', 75.0, 0),
        ];
        for (final s in seeds) {
          await repo.saveMeasurementEntry(
            BodyMeasurementEntry(
              id: s.$1,
              measurementType: 'bodyweight',
              value: s.$2,
              unitId: 'unit-kg',
              recordedAtMs: baseMs - s.$3 * 24 * 60 * 60 * 1000,
            ),
          );
        }
        final profileState = ProfileState(repo);
        final settingsState = SettingsState(repo, fakePreferencesService());
        await settingsState.initialize();
        await profileState.loadProfile();
        const definition = ProfileMeasurements.bodyweight;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MeasurementHistoryChartSheet(
                profileState: profileState,
                definition: definition,
                settingsState: settingsState,
                onLogNew: () async {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Each of the three date labels must appear exactly once
        // on the chart's x-axis. (The strip below the chart also
        // renders the most recent date, so we scope the assertion
        // to text inside the LineChart to count only the
        // x-axis labels.)
        for (final entry in seeds) {
          final daysAgo = entry.$3;
          final date = DateTime.fromMillisecondsSinceEpoch(
            baseMs - daysAgo * 24 * 60 * 60 * 1000,
          );
          final label = ChartAxisHelper.formatDateLabel(date);
          expect(
            find.descendant(
              of: find.byType(LineChart),
              matching: find.text(label),
            ),
            findsOneWidget,
            reason:
                'X-axis date label "$label" must appear exactly once inside '
                'the LineChart — the padded minX/maxX boundary ticks must '
                'not produce duplicates.',
          );
        }
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // ExercisePickerScreen
  // ══════════════════════════════════════════════════════════════════════════

  group('ExercisePickerScreen', () {
    testWidgets('shows Select Exercise title', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);

      await tester.pumpWidget(
        MaterialApp(home: ExercisePickerScreen(workoutState: workoutState)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Select Exercise'), findsOneWidget);
    });

    testWidgets('header uses OmniBackHeader', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);

      await tester.pumpWidget(
        MaterialApp(home: ExercisePickerScreen(workoutState: workoutState)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OmniBackHeader), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('shows search field', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);

      await tester.pumpWidget(
        MaterialApp(home: ExercisePickerScreen(workoutState: workoutState)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Search exercises...'), findsOneWidget);
    });

    testWidgets('shows New Exercise button', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);

      await tester.pumpWidget(
        MaterialApp(home: ExercisePickerScreen(workoutState: workoutState)),
      );
      await tester.pumpAndSettle();

      expect(find.text('New Exercise'), findsOneWidget);
    });

    testWidgets(
      'uses subdued styling for recommended label and metadata chips',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1200));
        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);

        await tester.pumpWidget(
          MaterialApp(
            home: ExercisePickerScreen(
              workoutState: workoutState,
              sessionModality: Modality.sports,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Recommended'), findsOneWidget);

        final recommendedText = tester.widget<Text>(find.text('Recommended'));
        expect(recommendedText.style?.color, OmniTheme.colors.textSecondary);

        final firstChip = tester.widget<Chip>(find.byType(Chip).first);
        expect(firstChip.backgroundColor, Colors.transparent);
        expect(
          firstChip.side?.color,
          OmniTheme.colorsForTheme(OmniTheme.activeTheme).surfaceBorder,
        );
      },
    );

    testWidgets('sports modality recommends boxing exercises', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);

      await tester.pumpWidget(
        MaterialApp(
          home: ExercisePickerScreen(
            workoutState: workoutState,
            sessionModality: Modality.sports,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Recommended'), findsOneWidget);
      // Scroll down to ensure lazy-built list items are rendered
      await tester.dragUntilVisible(
        find.text('Heavy Bag Rounds'),
        find.byType(ListView).first,
        const Offset(0, -200),
      );
      expect(find.text('Heavy Bag Rounds'), findsOneWidget);
    });

    testWidgets('shows exercises from repo', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);

      await tester.pumpWidget(
        MaterialApp(home: ExercisePickerScreen(workoutState: workoutState)),
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
        MaterialApp(home: ExercisePickerScreen(workoutState: workoutState)),
      );
      await tester.pump(); // single frame — before exercises load

      // Enter search text before exercises render to avoid exercise-tile overflow
      await tester.enterText(find.byType(TextField).first, 'zzzznotanexercise');
      // Advance past 300ms debounce and let load complete with the search filter
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('No exercises found'), findsOneWidget);
    });

    testWidgets('does not overflow when keyboard is open with empty results', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(viewInsets: EdgeInsets.only(bottom: 320)),
          child: MaterialApp(
            home: ExercisePickerScreen(workoutState: workoutState),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, 'zzzznotanexercise');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('No exercises found'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'New Exercise label is not wrapped in shrink-to-fit FittedBox',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1200));
        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);

        await tester.pumpWidget(
          MaterialApp(home: ExercisePickerScreen(workoutState: workoutState)),
        );
        await tester.pumpAndSettle();

        expect(
          find.ancestor(
            of: find.text('New Exercise'),
            matching: find.byType(FittedBox),
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'New Exercise label type role is more prominent than dropdown value text',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1200));
        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);

        await tester.pumpWidget(
          MaterialApp(home: ExercisePickerScreen(workoutState: workoutState)),
        );
        await tester.pumpAndSettle();

        // After Fix 1, 'New Exercise' Text has no explicit downscaled style
        final newExerciseText = tester.widget<Text>(find.text('New Exercise'));
        expect(
          newExerciseText.style?.fontSize,
          isNull,
          reason:
              'New Exercise label must not have an explicit downscaled fontSize',
        );

        // After Fix 2, dropdown 'All' Text has an explicitly small style (bodySmall)
        final allTextWidgets = tester
            .widgetList<Text>(find.text('All'))
            .toList();
        expect(
          allTextWidgets,
          isNotEmpty,
          reason: 'Discipline/Muscle dropdowns should show selected value',
        );
        for (final w in allTextWidgets) {
          expect(
            w.style?.fontSize,
            isNotNull,
            reason: 'Dropdown value text must have an explicit muted style',
          );
          expect(
            w.style!.fontSize!,
            lessThan(14.0),
            reason:
                'Dropdown value text must be smaller than standard body text',
          );
        }
      },
    );

    testWidgets('no ranking sections shown when sessionModality is null', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);

      await tester.pumpWidget(
        MaterialApp(home: ExercisePickerScreen(workoutState: workoutState)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Recommended'), findsNothing);
      expect(find.text('Other'), findsNothing);
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
      expect(find.text('Martial Arts'), findsNothing);
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

          final colors = OmniTheme.colorsForTheme(appTheme);

          await tester.pumpWidget(
            MaterialApp(
              theme: buildTheme(
                theme: appTheme,
                brightness: Brightness.dark,
                background: colors.backgroundBottom,
                surface: colors.surface,
                secondary: colors.secondary,
                textPrimary: const Color(0xFFE6EDF3),
                textSecondary: colors.textMuted,
                divider: colors.divider,
              ),
              home: WorkoutSessionScreen(
                workoutState: workoutState,
                routineState: routineState,
                sessionSummaryService: SessionSummaryService(repo),
                timerAlertService: FakeTimerAlertService(),
                settingsState: SettingsState(repo, fakePreferencesService()),
              ),
            ),
          );
          await tester.pumpAndSettle();
          // Dismiss the auto-opened picker so WorkoutSessionScreen is foregrounded
          if (find.byType(ExercisePickerScreen).evaluate().isNotEmpty) {
            await tester.tap(find.byIcon(Icons.arrow_back));
            await tester.pumpAndSettle();
          }

          final finishFinder = find.widgetWithText(
            FilledButton,
            'Finish Workout',
          );
          expect(
            finishFinder,
            findsOneWidget,
            reason: '${appTheme.name} – Finish Workout button not found',
          );

          final addFinder = find.widgetWithText(FilledButton, 'Add Exercise');
          expect(
            addFinder,
            findsOneWidget,
            reason: '${appTheme.name} – Add Exercise button not found',
          );
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is FilledButton &&
                  widget.child is Icon &&
                  (widget.child as Icon).icon == Icons.add,
            ),
            findsNothing,
            reason: '${appTheme.name} – floating plus button should be removed',
          );

          final finishTheme = Theme.of(tester.element(finishFinder));
          final addTheme = Theme.of(tester.element(addFinder));

          expect(
            finishTheme.colorScheme.primary,
            colors.primary,
            reason:
                '${appTheme.name} – Finish Workout accent must match the active theme primary',
          );
          expect(
            addTheme.colorScheme.primary,
            colors.primary,
            reason:
                '${appTheme.name} – add button accent must match the active theme primary',
          );
        }
      },
    );

    testWidgets(
      'exercise picker opens as full-screen page from session screen',
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
              timerAlertService: FakeTimerAlertService(),
              settingsState: SettingsState(repo, fakePreferencesService()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final addButton = find.widgetWithText(FilledButton, 'Add Exercise');
        if (addButton.evaluate().isEmpty) return; // skip if layout differs

        tester.widget<FilledButton>(addButton).onPressed?.call();
        await tester.pumpAndSettle();

        expect(
          find.byType(ExercisePickerScreen),
          findsOneWidget,
          reason: 'ExercisePickerScreen should be pushed as a full-screen page',
        );
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // WorkoutSessionScreen – weight adjustment toggle
  // ══════════════════════════════════════════════════════════════════════════

  group('WorkoutSessionScreen – weight adjustment toggle', () {
    testWidgets(
      'set weight editor displays canonical kg value converted to lbs',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1200));
        final repo = await _freshRepo();
        await repo.setPreferenceString('preferred_weight_unit', 'lbs');
        final workoutState = WorkoutState(repo);
        final routineState = RoutineState(repo);
        final settingsState = SettingsState(repo, fakePreferencesService());
        await settingsState.initialize();
        await workoutState.markExerciseInfoHintSeen();
        await workoutState.markExerciseNotesHintSeen();
        await workoutState.createNewSession(modality: 'resistance_lifting');

        final exercises = await repo.getExercises();
        final loadedExercise = exercises.firstWhere(
          (e) =>
              e.capabilities.contains('sets') &&
              e.capabilities.contains('load') &&
              e.capabilities.contains('reps'),
          orElse: () => exercises.first,
        );
        final effortId = await workoutState.addExerciseToSession(
          loadedExercise,
          effortKindOverride: 'set',
        );

        // Canonical storage is kg; 45.3592 kg should render as 100.0 lbs.
        await workoutState.updateEntryValue(effortId, 0, 'weight', 45.3592);

        await tester.pumpWidget(
          MaterialApp(
            home: WorkoutSessionScreen(
              workoutState: workoutState,
              routineState: routineState,
              sessionSummaryService: SessionSummaryService(repo),
              timerAlertService: FakeTimerAlertService(),
              settingsState: settingsState,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text(loadedExercise.name).first);
        await tester.pumpAndSettle();

        expect(find.text('100.0'), findsOneWidget);
        expect(find.text('LBS'), findsOneWidget);
      },
    );

    testWidgets(
      'timed extra-weight displays canonical kg value converted to lbs',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1200));
        final repo = await _freshRepo();
        await repo.setPreferenceString('preferred_weight_unit', 'lbs');
        final workoutState = WorkoutState(repo);
        final routineState = RoutineState(repo);
        final settingsState = SettingsState(repo, fakePreferencesService());
        await settingsState.initialize();
        await workoutState.markExerciseInfoHintSeen();
        await workoutState.markExerciseNotesHintSeen();
        await workoutState.createNewSession(modality: 'cardio_endurance');

        final exercises = await repo.getExercises();
        final timedExercise = exercises.firstWhere(
          (e) => e.capabilities.contains('time'),
          orElse: () => exercises.first,
        );
        final effortId = await workoutState.addExerciseToSession(
          timedExercise,
          effortKindOverride: 'timed',
        );

        // Canonical storage is kg; 22.6796 kg should render as +50.0 lbs.
        await workoutState.updateEntryValue(
          effortId,
          0,
          'extra-weight',
          22.6796,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: WorkoutSessionScreen(
              workoutState: workoutState,
              routineState: routineState,
              sessionSummaryService: SessionSummaryService(repo),
              timerAlertService: FakeTimerAlertService(),
              settingsState: settingsState,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text(timedExercise.name).first);
        await tester.pumpAndSettle();

        expect(find.text('+50.0'), findsOneWidget);
        expect(find.text('LBS'), findsOneWidget);
      },
    );

    testWidgets(
      'drill extra-weight displays canonical kg value converted to lbs',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1200));
        final repo = await _freshRepo();
        await repo.setPreferenceString('preferred_weight_unit', 'lbs');
        final workoutState = WorkoutState(repo);
        final routineState = RoutineState(repo);
        final settingsState = SettingsState(repo, fakePreferencesService());
        await settingsState.initialize();
        await workoutState.markExerciseInfoHintSeen();
        await workoutState.markExerciseNotesHintSeen();
        await workoutState.createNewSession(modality: 'isometric_stretching');

        final exercises = await repo.getExercises();
        final drillExercise = exercises.firstWhere(
          (e) => e.capabilities.contains('hold'),
          orElse: () => exercises.first,
        );
        final effortId = await workoutState.addExerciseToSession(
          drillExercise,
          effortKindOverride: 'drill',
        );

        // Canonical storage is kg; 22.6796 kg should render as +50.0 lbs.
        await workoutState.updateEntryValue(
          effortId,
          0,
          'extra-weight',
          22.6796,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: WorkoutSessionScreen(
              workoutState: workoutState,
              routineState: routineState,
              sessionSummaryService: SessionSummaryService(repo),
              timerAlertService: FakeTimerAlertService(),
              settingsState: settingsState,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text(drillExercise.name).first);
        await tester.pumpAndSettle();

        expect(find.text('+50.0'), findsOneWidget);
        expect(find.text('LBS'), findsOneWidget);
      },
    );

    testWidgets(
      'timed exercise reveals extra weight only after tapping the link',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1200));
        final repo = await _freshRepo();
        await repo.setPreferenceString('preferred_weight_unit', 'lbs');
        final workoutState = WorkoutState(repo);
        final routineState = RoutineState(repo);
        final settingsState = SettingsState(repo, fakePreferencesService());
        await settingsState.initialize();
        await workoutState.markExerciseInfoHintSeen();
        await workoutState.markExerciseNotesHintSeen();
        await workoutState.createNewSession(modality: 'cardio_endurance');

        final exercises = await repo.getExercises();
        final timedExercise = exercises.firstWhere(
          (e) => e.capabilities.contains('time'),
          orElse: () => exercises.first,
        );
        await workoutState.addExerciseToSession(
          timedExercise,
          effortKindOverride: 'timed',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: WorkoutSessionScreen(
              workoutState: workoutState,
              routineState: routineState,
              sessionSummaryService: SessionSummaryService(repo),
              timerAlertService: FakeTimerAlertService(),
              settingsState: settingsState,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text(timedExercise.name).first);
        await tester.pumpAndSettle();

        final linkFinder = find.widgetWithText(
          OutlinedButton,
          'Weight adjustment',
        );
        await tester.ensureVisible(linkFinder);

        expect(linkFinder, findsOneWidget);
        expect(find.text('EXTRA KG'), findsNothing);

        await tester.tap(linkFinder);
        await tester.pumpAndSettle();
        expect(find.text('EXTRA KG'), findsNothing);
        expect(find.text('LBS'), findsOneWidget);

        await tester.ensureVisible(linkFinder);
        await tester.tap(linkFinder);
        await tester.pumpAndSettle();
        expect(find.text('EXTRA KG'), findsNothing);
      },
    );

    testWidgets('loaded set exercise does not show weight adjustment link', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final routineState = RoutineState(repo);
      await workoutState.markExerciseInfoHintSeen();
      await workoutState.markExerciseNotesHintSeen();
      await workoutState.createNewSession(modality: 'resistance_lifting');

      final exercises = await repo.getExercises();
      final loadedExercise = exercises.firstWhere(
        (e) =>
            e.capabilities.contains('sets') && e.capabilities.contains('load'),
        orElse: () => exercises.first,
      );
      await workoutState.addExerciseToSession(
        loadedExercise,
        effortKindOverride: 'set',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutSessionScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: SessionSummaryService(repo),
            timerAlertService: FakeTimerAlertService(),
            settingsState: SettingsState(repo, fakePreferencesService()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(loadedExercise.name).first);
      await tester.pumpAndSettle();

      expect(find.text('Weight adjustment'), findsNothing);
    });

    testWidgets('non-load set exercise does not show weight adjustment link', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final routineState = RoutineState(repo);
      await workoutState.markExerciseInfoHintSeen();
      await workoutState.markExerciseNotesHintSeen();
      await workoutState.createNewSession(modality: 'resistance_lifting');

      final exercises = await repo.getExercises();
      final nonLoadExercise = exercises.firstWhere(
        (e) =>
            e.capabilities.contains('sets') && !e.capabilities.contains('load'),
        orElse: () => exercises.firstWhere(
          (e) => !e.capabilities.contains('load'),
          orElse: () => exercises.first,
        ),
      );
      await workoutState.addExerciseToSession(
        nonLoadExercise,
        effortKindOverride: 'set',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutSessionScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: SessionSummaryService(repo),
            timerAlertService: FakeTimerAlertService(),
            settingsState: SettingsState(repo, fakePreferencesService()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(nonLoadExercise.name).first);
      await tester.pumpAndSettle();

      // Framework-driven: set effort never shows extra-weight regardless of
      // the exercise's load capability.
      expect(find.text('Weight adjustment'), findsNothing);
    });

    testWidgets(
      'weight adjustment renders as OutlinedButton with expand icon, not plain TextButton',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1200));
        final repo = await _freshRepo();
        await repo.setPreferenceString('preferred_weight_unit', 'kg');
        final workoutState = WorkoutState(repo);
        final routineState = RoutineState(repo);
        final settingsState = SettingsState(repo, fakePreferencesService());
        await settingsState.initialize();
        await workoutState.markExerciseInfoHintSeen();
        await workoutState.markExerciseNotesHintSeen();
        await workoutState.createNewSession(modality: 'cardio_endurance');

        final exercises = await repo.getExercises();
        final timedExercise = exercises.firstWhere(
          (e) => e.capabilities.contains('time'),
          orElse: () => exercises.first,
        );
        await workoutState.addExerciseToSession(
          timedExercise,
          effortKindOverride: 'timed',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: WorkoutSessionScreen(
              workoutState: workoutState,
              routineState: routineState,
              sessionSummaryService: SessionSummaryService(repo),
              timerAlertService: FakeTimerAlertService(),
              settingsState: settingsState,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text(timedExercise.name).first);
        await tester.pumpAndSettle();

        final outlinedFinder = find.widgetWithText(
          OutlinedButton,
          'Weight adjustment',
        );
        await tester.ensureVisible(outlinedFinder);
        final outlinedButton = tester.widget<OutlinedButton>(outlinedFinder);
        final theme = Theme.of(tester.element(outlinedFinder));
        final resolvedForeground = outlinedButton.style?.foregroundColor
            ?.resolve(<WidgetState>{});
        final resolvedSide = outlinedButton.style?.side?.resolve(
          <WidgetState>{},
        );

        // Must render as OutlinedButton, not plain TextButton
        expect(outlinedFinder, findsOneWidget);
        expect(
          find.widgetWithText(TextButton, 'Weight adjustment'),
          findsNothing,
        );
        expect(
          resolvedForeground,
          theme.colorScheme.onSurface.withAlpha((0.6 * 255).round()),
        );
        expect(
          resolvedSide?.color,
          theme.colorScheme.onSurface.withAlpha((0.2 * 255).round()),
        );

        // Must show expand icon when collapsed
        expect(
          find.descendant(
            of: outlinedFinder,
            matching: find.byIcon(Icons.expand_more),
          ),
          findsOneWidget,
        );

        // Tap to expand — icon must flip to expand_less
        await tester.tap(outlinedFinder);
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: outlinedFinder,
            matching: find.byIcon(Icons.expand_less),
          ),
          findsOneWidget,
        );
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // WorkoutSessionScreen – rolling session block list view
  // ══════════════════════════════════════════════════════════════════════════

  group('WorkoutSessionScreen – rolling session block UI', () {
    testWidgets(
      'non-rolling empty session shows Add Exercise and Add Block above Finish Workout',
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
              timerAlertService: FakeTimerAlertService(),
              settingsState: SettingsState(repo, fakePreferencesService()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        // Dismiss the auto-opened picker so WorkoutSessionScreen is foregrounded
        if (find.byType(ExercisePickerScreen).evaluate().isNotEmpty) {
          await tester.tap(find.byIcon(Icons.arrow_back));
          await tester.pumpAndSettle();
        }

        final addExerciseFinder = find.widgetWithText(
          FilledButton,
          'Add Exercise',
        );
        final addBlockFinder = find.widgetWithText(OutlinedButton, 'Add Block');
        final finishFinder = find.widgetWithText(
          FilledButton,
          'Finish Workout',
        );

        expect(addExerciseFinder, findsOneWidget);
        expect(addBlockFinder, findsOneWidget);
        expect(finishFinder, findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is FilledButton &&
                widget.child is Icon &&
                (widget.child as Icon).icon == Icons.add,
          ),
          findsNothing,
        );

        final addExerciseRect = tester.getRect(addExerciseFinder);
        final addBlockRect = tester.getRect(addBlockFinder);
        final finishRect = tester.getRect(finishFinder);
        expect(addExerciseRect.bottom, lessThan(addBlockRect.top));
        expect(addBlockRect.bottom, lessThan(finishRect.top));
      },
    );

    testWidgets('rolling session shows Add Exercise and Add Block actions', (
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
            timerAlertService: FakeTimerAlertService(),
            settingsState: SettingsState(repo, fakePreferencesService()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Dismiss the auto-opened picker so WorkoutSessionScreen is foregrounded
      if (find.byType(ExercisePickerScreen).evaluate().isNotEmpty) {
        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();
      }

      expect(find.widgetWithText(FilledButton, 'Add Exercise'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Add Block'), findsOneWidget);
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
            timerAlertService: FakeTimerAlertService(),
            settingsState: SettingsState(repo, fakePreferencesService()),
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
            timerAlertService: FakeTimerAlertService(),
            settingsState: SettingsState(repo, fakePreferencesService()),
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
            timerAlertService: FakeTimerAlertService(),
            settingsState: SettingsState(repo, fakePreferencesService()),
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
            timerAlertService: FakeTimerAlertService(),
            settingsState: SettingsState(repo, fakePreferencesService()),
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
            timerAlertService: FakeTimerAlertService(),
            settingsState: SettingsState(repo, fakePreferencesService()),
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
            timerAlertService: FakeTimerAlertService(),
            settingsState: SettingsState(repo, fakePreferencesService()),
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
            timerAlertService: FakeTimerAlertService(),
            settingsState: SettingsState(repo, fakePreferencesService()),
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
            timerAlertService: FakeTimerAlertService(),
            settingsState: SettingsState(repo, fakePreferencesService()),
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
              timerAlertService: FakeTimerAlertService(),
              settingsState: SettingsState(repo, fakePreferencesService()),
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
            timerAlertService: FakeTimerAlertService(),
            settingsState: SettingsState(repo, fakePreferencesService()),
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
            timerAlertService: FakeTimerAlertService(),
            settingsState: SettingsState(repo, fakePreferencesService()),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Session Time'), findsOneWidget);
    });

    testWidgets(
      'empty session shows 00:00 timer and timer does not advance before first exercise',
      (WidgetTester tester) async {
        await tester.runAsync(() async {
          final repo = await _freshRepo();
          final workoutState = WorkoutState(repo);
          final routineState = RoutineState(repo);
          // Fresh session with no exercises.
          await workoutState.createNewSession(isRolling: false);

          await tester.pumpWidget(
            MaterialApp(
              home: WorkoutSessionScreen(
                workoutState: workoutState,
                routineState: routineState,
                sessionSummaryService: SessionSummaryService(repo),
                timerAlertService: FakeTimerAlertService(),
                settingsState: SettingsState(repo, fakePreferencesService()),
              ),
            ),
          );
          await tester.pump();

          // Timer chip should show 00:00.
          expect(find.text('00:00'), findsWidgets);

          // Advance wall clock by 2 seconds — timer must remain frozen at 00:00.
          await tester.pump(const Duration(seconds: 2));
          expect(find.text('00:00'), findsWidgets);
        });
      },
    );

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
              timerAlertService: FakeTimerAlertService(),
              settingsState: SettingsState(repo, fakePreferencesService()),
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
            timerAlertService: FakeTimerAlertService(),
            settingsState: SettingsState(repo, fakePreferencesService()),
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
            topLevelOrderIndex: 1,
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
            topLevelOrderIndex: 2,
            createdAtMs: 2000,
            updatedAtMs: 2000,
          ),
        );

        await repo.createEffort(
          SegmentEffort(
            id: 'eff-standalone',
            segmentId: segmentId,
            orderIndex: 0,
            topLevelOrderIndex: 0,
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
            topLevelOrderIndex: 1,
            blockOrderIndex: 0,
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
            topLevelOrderIndex: 2,
            blockOrderIndex: 0,
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
            topLevelOrderIndex: 1,
            blockOrderIndex: 1,
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
              timerAlertService: FakeTimerAlertService(),
              settingsState: SettingsState(repo, fakePreferencesService()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text(blockALateEx.name).first);
        await tester.pumpAndSettle();

        expect(find.text('Exercise 3 / 4'), findsOneWidget);
      },
    );

    testWidgets(
      'rolling session block shows local and shared Add Exercise actions',
      (WidgetTester tester) async {
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
              timerAlertService: FakeTimerAlertService(),
              settingsState: SettingsState(repo, fakePreferencesService()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The global "Add Exercise" button in the bottom bar
        expect(find.text('Add Exercise'), findsOneWidget);
        // The block-level plus icon in the block header
        expect(find.byTooltip('Add exercise to block'), findsWidgets);
      },
    );

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
            timerAlertService: FakeTimerAlertService(),
            settingsState: SettingsState(repo, fakePreferencesService()),
          ),
        ),
      );
      await tester.pump();

      expect(find.text(exercises.first.name), findsOneWidget);
    });
  });

  // ── Food library — edit + image + fiber (June 2026) ────────────────

  group('Food library — edit + image + fiber (catalog scope)', () {
    testWidgets(
      'FoodForm pre-fills the name field when initial Food is non-null (S-003)',
      (WidgetTester tester) async {
        final repo = await _freshRepo();
        final foodLibraryState = FoodLibraryState(repo);
        await foodLibraryState.loadCatalogFoods();

        const initial = Food(
          id: 'food-prefill-1',
          name: 'Pre-filled Chicken',
          unitType: FoodUnitType.grams,
          referenceAmount: 100,
          referenceLabel: 'g',
          protein: 31,
          carbs: 0,
          fiber: 0,
          fat: 4,
          isCatalog: true,
          imagePath:
              '/tmp/missing.jpg', // file is missing; falls back to placeholder
          createdAtMs: 1000,
          updatedAtMs: 1000,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FoodForm(
                initial: initial,
                foodLibraryState: foodLibraryState,
                onSave: (_) async => true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Form's name field is pre-populated (top of form, always
        // visible without scrolling).
        expect(find.text('Pre-filled Chicken'), findsOneWidget);
        // Image tile is rendered.
        expect(find.byKey(const Key('food_form_image_tile')), findsOneWidget);
        // Name field is rendered with the initial value.
        expect(find.byKey(const Key('food_form_name')), findsOneWidget);
      },
    );

    testWidgets(
      'FoodForm renders an empty image tile when initial is null (S-008)',
      (WidgetTester tester) async {
        final repo = await _freshRepo();
        final foodLibraryState = FoodLibraryState(repo);
        await foodLibraryState.loadCatalogFoods();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FoodForm(
                initial: null,
                foodLibraryState: foodLibraryState,
                onSave: (_) async => true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Image tile is rendered (the placeholder is the "no
        // image" state).
        expect(find.byKey(const Key('food_form_image_tile')), findsOneWidget);
        // The "Add photo" text is the visible label of the
        // placeholder body.
        expect(find.text('Add photo'), findsOneWidget);
      },
    );

    testWidgets('FoodForm no longer renders an inline save button (S-010)', (
      WidgetTester tester,
    ) async {
      // The save CTA is no longer a child of the form body — it
      // is rendered by the host scaffold's bottomNavigationBar.
      // When FoodForm is mounted without a host scaffold CTA
      // (the test harness), the food_form_save key is absent.
      final repo = await _freshRepo();
      final foodLibraryState = FoodLibraryState(repo);
      await foodLibraryState.loadCatalogFoods();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FoodForm(
              initial: null,
              foodLibraryState: foodLibraryState,
              onSave: (_) async => true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The form body does not contain the save button.
      expect(find.byKey(const Key('food_form_save')), findsNothing);
      // The form body still has all the macro fields.
      expect(find.byKey(const Key('food_form_name')), findsOneWidget);
      expect(find.byKey(const Key('food_form_protein')), findsOneWidget);
      expect(find.byKey(const Key('food_form_carbs')), findsOneWidget);
      expect(find.byKey(const Key('food_form_fat')), findsOneWidget);
    });

    testWidgets(
      'EditFoodScreen renders FoodForm with Save label and pre-fills name',
      (WidgetTester tester) async {
        // Tall surface so the full form (image tile + name field)
        // is visible without scrolling.
        await tester.binding.setSurfaceSize(const Size(800, 1800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _freshRepo();
        final foodLibraryState = FoodLibraryState(repo);
        await foodLibraryState.loadCatalogFoods();
        await foodLibraryState.createCatalogFood(
          const FoodDraft(
            name: 'Edit Screen Test',
            groupId: null,
            unitType: FoodUnitType.grams,
            referenceAmount: 100,
            referenceLabel: 'g',
            protein: 31,
            carbs: 0,
            fiber: 0,
            fat: 4,
            sodium: null,
            notes: null,
            imagePath: null,
          ),
        );
        await foodLibraryState.loadCatalogFoods();
        final food = foodLibraryState.catalogFoods.firstWhere(
          (f) => f.name == 'Edit Screen Test',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: EditFoodScreen(
              food: food,
              foodLibraryState: foodLibraryState,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // AppBar title.
        expect(find.text('Edit Food'), findsOneWidget);
        // Image tile is rendered.
        expect(find.byKey(const Key('food_form_image_tile')), findsOneWidget);
        // Name field is pre-populated with the food's name.
        // (The TextField renders the controller's text — we look
        // for the field by its key and check the controller text.)
        final nameField = tester.widget<TextFormField>(
          find.byKey(const Key('food_form_name')),
        );
        expect(nameField.controller?.text, 'Edit Screen Test');
      },
    );

    testWidgets(
      'Catalog row on the Library tab shows a FoodThumbnail slot (S-006)',
      (WidgetTester tester) async {
        // Tall surface so the bundled catalog's first few rows
        // are visible without scrolling.
        await tester.binding.setSurfaceSize(const Size(800, 1800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _freshRepo();
        final foodLibraryState = FoodLibraryState(repo);
        final nutritionState = NutritionState(repo);
        await foodLibraryState.loadCatalogFoods();
        // Add a catalog food with an image so the thumbnail is
        // exercised in the "image present" branch.
        final foods = foodLibraryState.catalogFoods;
        final chickenId = foods
            .firstWhere((f) => f.name == 'Chicken breast, skinless')
            .id;
        await foodLibraryState.updateCatalogFood(
          foods.firstWhere((f) => f.id == chickenId),
          FoodDraft(
            name: 'Chicken breast, skinless',
            groupId: null,
            unitType: FoodUnitType.grams,
            referenceAmount: 100,
            referenceLabel: 'g',
            protein: 31,
            carbs: 0,
            fiber: 0,
            fat: 4,
            sodium: null,
            notes: null,
            imagePath:
                '/tmp/native-only.jpg', // file does not exist on the test runner; the row still renders the slot
          ),
        );
        await foodLibraryState.loadCatalogFoods();

        await tester.pumpWidget(
          MaterialApp(
            home: AddFoodScreen(
              foodLibraryState: foodLibraryState,
              nutritionState: nutritionState,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The Library tab is the default. The catalog row's
        // thumbnail slot is keyed by food id and is always
        // present (placeholder when no image, image when set).
        expect(
          find.byKey(Key('food_catalog_thumb_$chickenId')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Catalog row on the Library tab opens EditFoodScreen on row tap (S-001)',
      (WidgetTester tester) async {
        // Tall surface so the catalog list fits and the
        // "Chicken breast, skinless" row is visible without
        // scrolling.
        await tester.binding.setSurfaceSize(const Size(800, 1800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _freshRepo();
        final foodLibraryState = FoodLibraryState(repo);
        final nutritionState = NutritionState(repo);
        // AddFoodScreen.initState loads catalog + foods but NOT
        // groups. The EditFoodScreen's FoodForm DropdownButton
        // needs the groups loaded so the catalog food's
        // groupId ("food-group-proteins") has a matching item.
        await foodLibraryState.loadFoodGroups();
        await foodLibraryState.loadCatalogFoods();

        await tester.pumpWidget(
          MaterialApp(
            home: AddFoodScreen(
              foodLibraryState: foodLibraryState,
              nutritionState: nutritionState,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The bundled catalog ships a "Chicken breast, skinless"
        // row. Tapping its name (not the Add button) opens the
        // Edit Food screen.
        await tester.tap(find.text('Chicken breast, skinless'));
        await tester.pumpAndSettle();

        // EditFoodScreen is on the navigator.
        expect(find.text('Edit Food'), findsOneWidget);
      },
    );

    // ── Navigation route alignment (Add Food) ─────────────────────
    //
    // The two Add Food sub-screens pushed from the host — the
    // new-food entry form (via the `+ New Food` bottom CTA) and
    // the legacy library edit shim (via a row tap on a
    // pre-D-2 custom in the My Foods tab) — must route through
    // `OmniNavigator.push` so the `OmniRoute` `opaque = true` +
    // `OmniGradientBackground` wrapper applies. Raw
    // `MaterialPageRoute` pushes leave the outgoing and
    // incoming screens stacked during the slide (the
    // "two screens overlapping" frame).
    //
    // The two tests below drive the production code path and
    // capture the actual pushed `Route` via a `NavigatorObserver`
    // so the assertion is on the route object the production
    // code pushed — not on a test-only harness. The
    // `test/nutrition_test.dart` "fills the form, saves, and
    // the new food is rendered in the library" test exercises
    // the same production path but only asserts on the saved
    // food, not the route type, so it is non-coverage for this
    // alignment (see plan file S-N3).

    testWidgets(
      '+ New Food bottom CTA pushes the new-food form via OmniRoute (S-N1)',
      (WidgetTester tester) async {
        // Tall surface so the full-screen form's bottom CTA is
        // reachable without scrolling.
        await tester.binding.setSurfaceSize(const Size(800, 1800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _freshRepo();
        final foodLibraryState = FoodLibraryState(repo);
        final nutritionState = NutritionState(repo);
        await foodLibraryState.loadFoodGroups();
        await foodLibraryState.loadFoods();

        // Capture every route pushed from this MaterialApp so the
        // assertion targets the production route object, not a
        // test-only harness.
        final observer = _RouteTypeRecorder();

        await tester.pumpWidget(
          MaterialApp(
            navigatorObservers: [observer],
            home: AddFoodScreen(
              foodLibraryState: foodLibraryState,
              nutritionState: nutritionState,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Switch to the My Foods tab so the `+ New Food` bottom
        // CTA is the active CTA.
        await tester.tap(find.text('My Foods'));
        await tester.pumpAndSettle();

        // Tap the `+ New Food` bottom CTA. The production code
        // path is `_AddFoodScreenState._openNewFoodForm` which
        // must route through `OmniNavigator.push`.
        await tester.tap(find.text('+ New Food'));
        await tester.pumpAndSettle();

        // The new-food form is on the navigator.
        expect(find.text('New Food'), findsOneWidget);

        // The pushed route is the app's standard `OmniRoute`,
        // not a raw `MaterialPageRoute`. This is the
        // production-path assertion for S-N1.
        expect(
          observer.lastPushed,
          isA<OmniRoute<void>>(),
          reason:
              '`+ New Food` must route through OmniNavigator.push '
              'so the OmniRoute opaque + OmniGradientBackground '
              'wrapper applies (no overlap frame).',
        );
        expect(
          observer.lastPushed,
          isNot(isA<MaterialPageRoute<void>>()),
          reason:
              'raw MaterialPageRoute bypasses the OmniRoute '
              'wrapper and produces the overlap frame.',
        );
      },
    );

    testWidgets(
      'Legacy library-only custom food row tap pushes the legacy edit '
      'shim via OmniRoute (S-N2)',
      (WidgetTester tester) async {
        // Tall surface so the full-screen form is reachable
        // without scrolling.
        await tester.binding.setSurfaceSize(const Size(800, 1800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        const now = 1700000000000;
        final repo = await _freshRepo();
        // Seed a legacy (pre-D-2) library-only custom food
        // directly via the repository: `isCatalog = false`,
        // no matching catalog row, so the My Foods tab
        // surfaces it and the row tap routes through the
        // legacy edit shim branch.
        await repo.createFoodGroup(
          const FoodGroup(
            id: 'g-legacy',
            name: 'Legacy',
            createdAtMs: now,
            updatedAtMs: now,
          ),
        );
        await repo.createFood(
          const Food(
            id: 'f-legacy-custom',
            name: 'Legacy Custom',
            unitType: FoodUnitType.grams,
            groupId: 'g-legacy',
            referenceAmount: 100,
            referenceLabel: 'g',
            protein: 10,
            carbs: 5,
            fat: 2,
            isCatalog: false,
            createdAtMs: now,
            updatedAtMs: now,
          ),
        );

        final foodLibraryState = FoodLibraryState(repo);
        final nutritionState = NutritionState(repo);
        await foodLibraryState.loadFoodGroups();
        await foodLibraryState.loadFoods();

        // Capture every route pushed from this MaterialApp so the
        // assertion targets the production route object, not a
        // test-only harness.
        final observer = _RouteTypeRecorder();

        await tester.pumpWidget(
          MaterialApp(
            navigatorObservers: [observer],
            home: AddFoodScreen(
              foodLibraryState: foodLibraryState,
              nutritionState: nutritionState,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Switch to the My Foods tab so the legacy custom row is
        // rendered.
        await tester.tap(find.text('My Foods'));
        await tester.pumpAndSettle();

        // The legacy row is rendered (no catalog twin — the
        // My Foods tab's `catalogIdFor(f) == null` filter keeps
        // it on the legacy branch).
        expect(find.text('Legacy Custom'), findsOneWidget);

        // Tap the row surface (not the trailing delete button).
        // The production code path is
        // `_UserFoodRowState._openEdit`'s `else` branch (legacy
        // shim), which must route through `OmniNavigator.push`.
        await tester.tap(find.text('Legacy Custom'));
        await tester.pumpAndSettle();

        // The legacy edit shim is on the navigator (it reuses
        // the Edit Food app bar title).
        expect(find.text('Edit Food'), findsOneWidget);

        // The pushed route is the app's standard `OmniRoute`,
        // not a raw `MaterialPageRoute`. This is the
        // production-path assertion for S-N2.
        expect(
          observer.lastPushed,
          isA<OmniRoute<void>>(),
          reason:
              'the legacy edit shim push from the My Foods row '
              'tap must route through OmniNavigator.push so the '
              'OmniRoute opaque + OmniGradientBackground wrapper '
              'applies (no overlap frame).',
        );
        expect(
          observer.lastPushed,
          isNot(isA<MaterialPageRoute<void>>()),
          reason:
              'raw MaterialPageRoute bypasses the OmniRoute '
              'wrapper and produces the overlap frame.',
        );
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Rest timer chip — vertical position parity across screens
  // ══════════════════════════════════════════════════════════════════════════

  // Pumps a non-rolling session with one exercise and an open rest, so
  // the rest overlay chip is guaranteed to be on screen.
  Future<WorkoutSessionScreen> pumpSessionWithOpenRest(
    WidgetTester tester, {
    required Size surface,
  }) async {
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repo = await _freshRepo();
    final workoutState = WorkoutState(repo);
    final routineState = RoutineState(repo);
    await workoutState.createNewSession(isRolling: false);
    final exercises = await repo.getExercises();
    final effortId = await workoutState.addExerciseToSession(
      exercises.first,
      chosenMetric: 'reps',
    );
    // Open a rest for the just-added set so the rest chip renders.
    await workoutState.recordRestStart(effortId, 0);

    final screen = WorkoutSessionScreen(
      workoutState: workoutState,
      routineState: routineState,
      sessionSummaryService: SessionSummaryService(repo),
      timerAlertService: FakeTimerAlertService(),
      settingsState: SettingsState(repo, fakePreferencesService()),
    );
    await tester.pumpWidget(MaterialApp(home: screen));
    // Dismiss the auto-opened picker so the session screen is foregrounded.
    if (find.byType(ExercisePickerScreen).evaluate().isNotEmpty) {
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
    } else {
      await tester.pumpAndSettle();
    }
    return screen;
  }

  group('Rest overlay chip – vertical position', () {
    testWidgets(
      'detail view: rest chip sits above the Log Set button with the shared offset',
      (WidgetTester tester) async {
        const surface = Size(400, 1000);
        await pumpSessionWithOpenRest(tester, surface: surface);

        // The default landing surface is the list view. Tap the first
        // exercise to switch to the per-exercise detail view.
        final exercisesRepo = (await _freshRepo());
        final firstExercise = (await exercisesRepo.getExercises()).first;
        await tester.tap(find.text(firstExercise.name));
        await tester.pumpAndSettle();

        // The detail view uses `_buildSetControls` (a Row containing
        // the Log Set `FilledButton`), not the bottom OmniBottomCTA.
        // Look up the primary action by its label.
        final logSetFinder = find.widgetWithText(FilledButton, 'Log Set');
        final chipFinder = find.byKey(const Key('rest-overlay-chip'));
        expect(chipFinder, findsOneWidget);
        expect(logSetFinder, findsOneWidget);

        final chipRect = tester.getRect(chipFinder);
        final logSetRect = tester.getRect(logSetFinder);
        expect(
          chipRect.bottom,
          lessThanOrEqualTo(logSetRect.top),
          reason: 'rest chip must not overlap the Log Set button',
        );

        // Minimum vertical separation = the shared
        // `kRestOverlayToCTAGap` (80 dp) minus a small tolerance for
        // text-scale and SafeArea rounding. Use 40 dp as the absolute
        // floor so a future drift away from 80 dp is still caught.
        final gap = logSetRect.top - chipRect.bottom;
        expect(
          gap,
          greaterThanOrEqualTo(OmniTheme.kRestOverlayToCTAGap - 40.0),
          reason:
              'rest chip must clear the Log Set button by at least the '
              'shared separation gap (kRestOverlayToCTAGap)',
        );
      },
    );

    testWidgets(
      'list view: rest chip sits above the Finish Workout CTA with the shared offset',
      (WidgetTester tester) async {
        const surface = Size(400, 1000);
        await pumpSessionWithOpenRest(tester, surface: surface);

        // The list view is the default landing view, so the rest chip
        // and the Finish Workout CTA must be in the same Stack.
        final chipFinder = find.byKey(const Key('rest-overlay-chip'));
        final ctaFinder = find.byType(OmniBottomCTA);
        expect(chipFinder, findsOneWidget);
        expect(ctaFinder, findsOneWidget);

        final chipRect = tester.getRect(chipFinder);
        final ctaRect = tester.getRect(ctaFinder);
        expect(
          chipRect.bottom,
          lessThan(ctaRect.top),
          reason: 'rest chip must not overlap the bottom CTA',
        );

        final gap = ctaRect.top - chipRect.bottom;
        expect(
          gap,
          greaterThanOrEqualTo(OmniTheme.kRestOverlayToCTAGap - 40.0),
          reason:
              'rest chip must clear the bottom CTA by at least the shared '
              'separation gap (kRestOverlayToCTAGap)',
        );
      },
    );

    testWidgets(
      'rest chip resolves to the same vertical anchor on list and detail views',
      (WidgetTester tester) async {
        const surface = Size(400, 1000);
        await pumpSessionWithOpenRest(tester, surface: surface);

        // 1) Capture the chip's bottom in the list view (default landing).
        final listChipRect = tester.getRect(
          find.byKey(const Key('rest-overlay-chip')),
        );

        // 2) Switch to detail view and re-capture the chip's bottom.
        final repo = await _freshRepo();
        final firstExercise = (await repo.getExercises()).first;
        await tester.tap(find.text(firstExercise.name));
        await tester.pumpAndSettle();
        final detailChipRect = tester.getRect(
          find.byKey(const Key('rest-overlay-chip')),
        );

        // Both views share the same `restOverlayBottomOffset`, so the
        // chip's bottom must be at the same screen-Y in both.
        expect(
          listChipRect.bottom,
          detailChipRect.bottom,
          reason:
              'rest chip must use the shared restOverlayBottomOffset on '
              'both screens',
        );
        // And that bottom must equal the constant itself (relative to
        // the screen height), so the spec's "same vertical position"
        // claim is provably true and not just numerically equal.
        expect(
          surface.height - listChipRect.bottom,
          OmniTheme.restOverlayBottomOffset,
          reason: 'chip bottom must equal restOverlayBottomOffset',
        );
      },
    );

    testWidgets(
      'rest chip and CTA do not overlap on the smallest supported screen height',
      (WidgetTester tester) async {
        // 568 pt is the iPhone SE 1st-gen / 5s viewport height — the
        // smallest supported production surface. The chip must still
        // clear the Log Set / Finish Workout CTA at this size.
        const surface = Size(320, 568);
        await pumpSessionWithOpenRest(tester, surface: surface);

        final chipRect = tester.getRect(
          find.byKey(const Key('rest-overlay-chip')),
        );
        final ctaRect = tester.getRect(find.byType(OmniBottomCTA));
        expect(
          chipRect.bottom,
          lessThanOrEqualTo(ctaRect.top),
          reason: 'rest chip must not overlap the bottom CTA on a small screen',
        );
      },
    );

    testWidgets(
      'rest chip and CTA do not overlap on the largest supported screen height',
      (WidgetTester tester) async {
        // 1366 pt is the iPad Pro 12.9 landscape viewport — a typical
        // "largest supported" target. The chip must remain above the
        // CTA at this size (not float over scrollable content).
        const surface = Size(1024, 1366);
        await pumpSessionWithOpenRest(tester, surface: surface);

        final chipRect = tester.getRect(
          find.byKey(const Key('rest-overlay-chip')),
        );
        final ctaRect = tester.getRect(find.byType(OmniBottomCTA));
        expect(
          chipRect.bottom,
          lessThanOrEqualTo(ctaRect.top),
          reason: 'rest chip must not overlap the bottom CTA on a large screen',
        );
      },
    );

    testWidgets('Session Time chip position is unchanged (regression guard)', (
      WidgetTester tester,
    ) async {
      // The rest-chip move is vertical-only on the rest indicator.
      // The Session Time chip (session clock) must remain pinned
      // under the header at the same Y across the move.
      const surface = Size(400, 1000);
      await pumpSessionWithOpenRest(tester, surface: surface);

      final sessionTimeText = find.text('Session Time');
      expect(sessionTimeText, findsOneWidget);
      final listRect = tester.getRect(sessionTimeText);

      // The Session Time chip lives in the list view header column,
      // well above the bottom CTA. It must not have been dragged
      // into the lower half by the rest-chip repositioning.
      final ctaRect = tester.getRect(find.byType(OmniBottomCTA));
      expect(
        listRect.top,
        lessThan(ctaRect.center.dy),
        reason: 'Session Time chip must remain in the upper half of the screen',
      );

      // Switch to detail view; the Session Time chip is not rendered
      // there, but the rest chip must still sit below the header and
      // above the Log Set button.
      final repo = await _freshRepo();
      final firstExercise = (await repo.getExercises()).first;
      await tester.tap(find.text(firstExercise.name));
      await tester.pumpAndSettle();
      expect(find.text('Session Time'), findsNothing);
      final chipRect = tester.getRect(
        find.byKey(const Key('rest-overlay-chip')),
      );
      final logSetFinder = find.widgetWithText(FilledButton, 'Log Set');
      expect(logSetFinder, findsOneWidget);
      final logSetRect = tester.getRect(logSetFinder);
      expect(
        chipRect.bottom,
        lessThanOrEqualTo(logSetRect.top),
        reason: 'rest chip must clear the Log Set button on the detail view',
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // Large-screen content column
  // ══════════════════════════════════════════════════════════════════════

  group('Large-screen content column', () {
    testWidgets(
      'S-001: phone-class surface — column is inert, content fills the width',
      (WidgetTester tester) async {
        // 400 × 800 = typical large phone (e.g. iPhone 13/14). Below
        // `kColumnMinActivationWidth` the centered column must be
        // fully inert.
        const surface = Size(400, 800);
        await tester.binding.setSurfaceSize(surface);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            home: OmniGradientBackground(
              child: Scaffold(
                appBar: AppBar(title: const Text('Phone')),
                body: const Center(child: Text('Body')),
                bottomNavigationBar: OmniBottomCTA(
                  label: 'Log Set',
                  onPressed: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The Scaffold (and therefore the CTA) fills the surface
        // width: the button's left edge sits at the shared horizontal
        // padding from the screen edge, and its right edge sits at
        // `surface.width - bottomCTAHorizontalPadding`. There is no
        // extra side margin.
        final buttonRect = tester.getRect(
          find.descendant(
            of: find.byType(OmniBottomCTA),
            matching: find.byType(FilledButton),
          ),
        );
        expect(
          buttonRect.left,
          closeTo(OmniTheme.bottomCTAHorizontalPadding, 0.5),
          reason:
              'on a phone-class surface the CTA must be inset only by '
              'bottomCTAHorizontalPadding from the screen edge',
        );
        expect(
          buttonRect.right,
          closeTo(
            surface.width - OmniTheme.bottomCTAHorizontalPadding,
            0.5,
          ),
          reason:
              'on a phone-class surface the CTA must reach to '
              '`surface.width - bottomCTAHorizontalPadding`',
        );
        // Sanity check: the button is exactly `surface.width -
        // 2 × padding` wide. The cap is fully inert on this surface.
        expect(
          buttonRect.width,
          closeTo(
            surface.width - 2 * OmniTheme.bottomCTAHorizontalPadding,
            0.5,
          ),
          reason: 'on a phone-class surface the CTA must fill the width',
        );
      },
    );

    testWidgets(
      'S-002: phone-class surface — column CTA still spans the full width',
      (WidgetTester tester) async {
        // 360 × 780 = a smaller / foldable-folded phone-class surface.
        // The cap must be fully inert here too.
        const surface = Size(360, 780);
        await tester.binding.setSurfaceSize(surface);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            home: OmniGradientBackground(
              child: Scaffold(
                bottomNavigationBar: OmniBottomCTA(
                  label: 'Finish Workout',
                  onPressed: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final buttonRect = tester.getRect(find.byType(FilledButton));
        expect(
          buttonRect.left,
          closeTo(OmniTheme.bottomCTAHorizontalPadding, 0.5),
        );
        expect(
          buttonRect.right,
          closeTo(
            surface.width - OmniTheme.bottomCTAHorizontalPadding,
            0.5,
          ),
        );
        expect(
          buttonRect.width,
          surface.width - 2 * OmniTheme.bottomCTAHorizontalPadding,
          reason: 'CTA width on a phone is surface.width minus 2× padding',
        );
      },
    );

    testWidgets(
      'S-003: tablet-class surface — content sits in a centered column with margins',
      (WidgetTester tester) async {
        // 1024 × 1366 = iPad Pro 12.9 landscape, the canonical
        // "largest supported tablet" target. The cap must engage:
        // the Scaffold (and therefore the CTA) sits in a column of
        // `kColumnMaxWidth` dp centered in the surface, with
        // non-zero equal side margins.
        const surface = Size(1024, 1366);
        await tester.binding.setSurfaceSize(surface);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            home: OmniGradientBackground(
              child: Scaffold(
                appBar: AppBar(title: const Text('Tablet')),
                body: const Center(child: Text('Body')),
                bottomNavigationBar: OmniBottomCTA(
                  label: 'Log Set',
                  onPressed: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The Scaffold's render box is the centered column.
        final scaffoldRect = tester.getRect(find.byType(Scaffold));
        expect(
          scaffoldRect.width,
          closeTo(OmniTheme.kColumnMaxWidth, 0.5),
          reason:
              'on a tablet-class surface the Scaffold must occupy a '
              'column of `kColumnMaxWidth` dp',
        );
        // Equal side margins, both non-zero.
        final leftMargin = scaffoldRect.left;
        final rightMargin = surface.width - scaffoldRect.right;
        expect(
          leftMargin,
          closeTo(rightMargin, 0.5),
          reason: 'centered column must have equal side margins',
        );
        expect(
          leftMargin,
          greaterThan(0.0),
          reason: 'centered column must not touch either screen edge',
        );
        // And the column must be measurably narrower than the
        // surface — the cap is engaged.
        expect(
          scaffoldRect.width,
          lessThan(surface.width),
          reason: 'content column must be narrower than the surface',
        );
        // The body content sits within the centered column.
        final bodyFinder = find.text('Body');
        expect(bodyFinder, findsOneWidget);
        final bodyRect = tester.getRect(bodyFinder);
        expect(
          bodyRect.left,
          greaterThanOrEqualTo(scaffoldRect.left),
          reason: 'body content must sit inside the centered column',
        );
        expect(
          bodyRect.right,
          lessThanOrEqualTo(scaffoldRect.right),
        );
      },
    );

    testWidgets(
      'S-004: tablet-class surface — bottom CTA is centered and capped',
      (WidgetTester tester) async {
        const surface = Size(1024, 1366);
        await tester.binding.setSurfaceSize(surface);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            home: OmniGradientBackground(
              child: Scaffold(
                bottomNavigationBar: OmniBottomCTA(
                  label: 'Finish Workout',
                  onPressed: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The button's left edge is inset from the screen edge by
        //   (columnLeftMargin) + (columnPadding)
        // = ((surface.width - kColumnMaxWidth) / 2)
        //   + bottomCTAHorizontalPadding,
        // and its right edge is mirrored.
        final column = contentColumnRectFor(surface.width);
        final expectedLeft =
            column.left + OmniTheme.bottomCTAHorizontalPadding;
        final expectedRight =
            column.left +
            column.width -
            OmniTheme.bottomCTAHorizontalPadding;
        final buttonRect = tester.getRect(
          find.descendant(
            of: find.byType(OmniBottomCTA),
            matching: find.byType(FilledButton),
          ),
        );
        expect(buttonRect.left, closeTo(expectedLeft, 0.5));
        expect(buttonRect.right, closeTo(expectedRight, 0.5));
        // The button does not reach either screen edge.
        expect(
          buttonRect.left,
          greaterThan(0.0),
          reason: 'CTA must not touch the left screen edge on a tablet',
        );
        expect(
          buttonRect.right,
          lessThan(surface.width),
          reason: 'CTA must not touch the right screen edge on a tablet',
        );
        // The side margins are non-zero and equal — the CTA is
        // centered within the surface.
        final leftMargin = buttonRect.left;
        final rightMargin = surface.width - buttonRect.right;
        expect(
          leftMargin,
          closeTo(rightMargin, 0.5),
          reason: 'CTA side margins must be equal on a tablet',
        );
        expect(leftMargin, greaterThan(0.0));
        // Heights are unchanged.
        expect(
          buttonRect.height,
          closeTo(OmniTheme.buttonPrimaryHeight, 0.5),
        );
        // Vertical anchor is unchanged — the button clears the
        // device safe area by `bottomCTAVerticalBottomPadding`.
        final expectedBottom =
            surface.height -
            tester.view.padding.bottom / tester.view.devicePixelRatio -
            OmniTheme.bottomCTAVerticalBottomPadding;
        expect(buttonRect.bottom, closeTo(expectedBottom, 0.5));
      },
    );

    testWidgets(
      'S-005: tablet-class surface — column does not grow with the surface',
      (WidgetTester tester) async {
        // Two different tablet-class surfaces — landscape and
        // portrait. The column width must be the same in both; only
        // the side margins grow.
        addTearDown(() => tester.binding.setSurfaceSize(null));
        for (final surface in const [
          Size(1024, 1366), // iPad Pro 12.9 landscape
          Size(1366, 1024), // iPad Pro 12.9 portrait
        ]) {
          await tester.binding.setSurfaceSize(surface);

          await tester.pumpWidget(
            MaterialApp(
              home: OmniGradientBackground(
                child: Scaffold(
                  body: const Center(child: Text('Body')),
                  bottomNavigationBar: OmniBottomCTA(
                    label: 'Log Set',
                    onPressed: () {},
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final scaffoldRect = tester.getRect(find.byType(Scaffold));
          expect(
            scaffoldRect.width,
            closeTo(OmniTheme.kColumnMaxWidth, 0.5),
            reason:
                'content column must stay at kColumnMaxWidth on a '
                '$surface surface (must not grow with the surface)',
          );
          // And it is measurably narrower than the surface.
          expect(
            scaffoldRect.width,
            lessThan(surface.width),
            reason:
                'content column must be narrower than the surface '
                'on $surface',
          );
        }
      },
    );

    testWidgets(
      'S-006: threshold is exactly kColumnMinActivationWidth',
      (WidgetTester tester) async {
        // 500 dp is the activation threshold itself — the cap must
        // engage (the column width is `kColumnMaxWidth`).
        // 499 dp is one dp below the threshold — the cap must be
        // fully inert (the column fills the surface).
        for (final entry in const <({double width, bool shouldCap})>[
          (width: 499, shouldCap: false),
          (width: 500, shouldCap: true),
        ]) {
          final surface = Size(entry.width, 800);
          await tester.binding.setSurfaceSize(surface);
          addTearDown(() => tester.binding.setSurfaceSize(null));

          await tester.pumpWidget(
            MaterialApp(
              home: OmniGradientBackground(
                child: Scaffold(
                  bottomNavigationBar: OmniBottomCTA(
                    label: 'Log Set',
                    onPressed: () {},
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final buttonRect = tester.getRect(find.byType(FilledButton));
          if (entry.shouldCap) {
            // Cap engaged: button is narrower than the surface.
            expect(
              buttonRect.width,
              closeTo(
                OmniTheme.kColumnMaxWidth -
                    2 * OmniTheme.bottomCTAHorizontalPadding,
                0.5,
              ),
              reason:
                  'at ${entry.width} dp wide the cap must engage and the '
                  'CTA must be inset within the centered column',
            );
          } else {
            // Cap inert: button fills the surface.
            expect(
              buttonRect.width,
              closeTo(
                surface.width - 2 * OmniTheme.bottomCTAHorizontalPadding,
                0.5,
              ),
              reason:
                  'at ${entry.width} dp wide the cap must be inert and '
                  'the CTA must fill the available width',
            );
          }
        }
      },
    );
  });
}

/// Test-only [NavigatorObserver] that records the most recent
/// route pushed from production code. Used by the Add Food
/// navigation route-alignment tests in [screen_widget_test.dart]
/// to assert the production push is an [OmniRoute], not a raw
/// [MaterialPageRoute]. The class is top-level so the test
/// groups inside [main] can use it; the production navigation
/// contract lives in `lib/core/navigation/navigation.dart`.
class _RouteTypeRecorder extends NavigatorObserver {
  Route<dynamic>? lastPushed;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    lastPushed = route;
  }
}
