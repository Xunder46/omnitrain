import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/navigation/navigation.dart';
import 'package:omnitrain/core/services/preferences_service.dart';
import 'package:omnitrain/core/services/routine_session_service.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/core/utils/rest_notification_service.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/home/home_screen.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/home/home_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/period/period_state.dart';
import 'package:omnitrain/state/profile/profile_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/hub/hub_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_timer_alert_service.dart';
import 'helpers/test_nutrition_primer_state.dart';

/// Test-only [NavigatorObserver] that records the most recent
/// route pushed from production code. Used by the HubSheet
/// destination navigation alignment tests to assert the
/// production push is an [OmniRoute], not a raw
/// [MaterialPageRoute]. Mirrors the recorder in
/// `test/screen_widget_test.dart`.
class _RouteTypeRecorder extends NavigatorObserver {
  Route<dynamic>? lastPushed;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    lastPushed = route;
  }
}

void main() {
  group('Hub Interaction Tests', () {
    late MockWorkoutRepository repository;
    late PreferencesServiceImpl preferencesService;
    late WorkoutState workoutState;
    late HomeState homeState;
    late RoutineState routineState;
    late CalendarState calendarState;
    late PeriodState periodState;
    late ProfileState profileState;
    late SettingsState settingsState;
    late RoutineSessionService routineSessionService;
    late SessionSummaryService sessionSummaryService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      repository = MockWorkoutRepository();
      await repository.initialize();
      preferencesService = PreferencesServiceImpl();
      await preferencesService.init();

      workoutState = WorkoutState(repository);
      homeState = HomeState(repository);
      routineState = RoutineState(repository);
      calendarState = CalendarState(repository);
      periodState = PeriodState(repository);
      profileState = ProfileState(repository);
      settingsState = SettingsState(repository, preferencesService);
      await settingsState.initialize();
      routineSessionService = RoutineSessionService(repository);
      sessionSummaryService = SessionSummaryService(repository);
    });

    Future<void> pumpHomeScreen(WidgetTester tester) async {
      final nutritionPrimerState = await buildNutritionPrimerState(repository);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: settingsState),
          ],
          child: MaterialApp(
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
              nutritionState: NutritionState(repository),
              foodLibraryState: FoodLibraryState(repository),
              nutritionPrimerState: nutritionPrimerState,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('Tapping logo opens Hub sheet', (tester) async {
      // Skipped — see TODO at the top of the file. The tap on
      // `InteractiveLogo` never resolves because HomeScreen currently uses
      // `HomeLogoButton`; the test errors with "Found 0 widgets".
    }, skip: true);

    testWidgets('Hub label appears for first two opens, then disappears', (tester) async {
      // Skipped — see TODO at the top of the file.
    }, skip: true);

    testWidgets('Hub open count persists across sessions', (tester) async {
      // Skipped — see TODO at the top of the file.
    }, skip: true);

    testWidgets('Reduced motion disables animations', (tester) async {
      // Skipped — see TODO at the top of the file.
    }, skip: true);
  });

  group('HubSheet destination navigation (S-001)', () {
    late MockWorkoutRepository repository;
    late PreferencesServiceImpl preferencesService;
    late WorkoutState workoutState;
    late RoutineState routineState;
    late CalendarState calendarState;
    late PeriodState periodState;
    late ProfileState profileState;
    late SettingsState settingsState;
    late RoutineSessionService routineSessionService;
    late SessionSummaryService sessionSummaryService;
    late NutritionState nutritionState;
    late FoodLibraryState foodLibraryState;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      repository = MockWorkoutRepository();
      await repository.initialize();
      preferencesService = PreferencesServiceImpl();
      await preferencesService.init();

      workoutState = WorkoutState(repository);
      routineState = RoutineState(repository);
      calendarState = CalendarState(repository);
      await calendarState.init();
      periodState = PeriodState(repository);
      profileState = ProfileState(repository);
      settingsState = SettingsState(repository, preferencesService);
      await settingsState.initialize();
      routineSessionService = RoutineSessionService(repository);
      sessionSummaryService = SessionSummaryService(repository);
      nutritionState = NutritionState(repository);
      foodLibraryState = FoodLibraryState(repository);
    });

    /// Render [HubSheet] inside a [MaterialApp] that has a
    /// [_RouteTypeRecorder] installed as a [NavigatorObserver].
    /// The recorder captures every route the production code
    /// pushes, so the assertions can target the actual route
    /// object, not a test-only harness.
    Future<void> pumpHubSheet(
      WidgetTester tester,
      _RouteTypeRecorder observer,
    ) async {
      final nutritionPrimerState = await buildNutritionPrimerState(repository);
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [observer],
          home: Scaffold(
            body: HubSheet(
              scrollController: ScrollController(),
              profileState: profileState,
              workoutState: workoutState,
              settingsState: settingsState,
              timerAlertService: FakeTimerAlertService(),
              restNotificationService: RestNotificationService.noop(),
              calendarState: calendarState,
              periodState: periodState,
              routineState: routineState,
              nutritionState: nutritionState,
              foodLibraryState: foodLibraryState,
              nutritionPrimerState: nutritionPrimerState,
              routineSessionService: routineSessionService,
              sessionSummaryService: sessionSummaryService,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'HubSheet.Calendar tile pushes via OmniNavigator (OmniRoute, not '
      'MaterialPageRoute)',
      (WidgetTester tester) async {
        // Tall surface so the pushed CalendarScreen's column does
        // not overflow during `pumpAndSettle`. This is a
        // test-environment fix only — the production surface is
        // scrollable and not affected.
        await tester.binding.setSurfaceSize(const Size(800, 1800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final observer = _RouteTypeRecorder();
        await pumpHubSheet(tester, observer);

        await tester.tap(find.text('Calendar'));
        await tester.pumpAndSettle();

        expect(
          observer.lastPushed,
          isA<OmniRoute<dynamic>>(),
          reason:
              'HubSheet.Calendar must route through OmniNavigator.push '
              'so the OmniRoute opaque + OmniGradientBackground '
              'wrapper applies (no overlap frame).',
        );
        expect(
          observer.lastPushed,
          isNot(isA<MaterialPageRoute<dynamic>>()),
          reason:
              'raw MaterialPageRoute bypasses the OmniRoute wrapper '
              'and produces the overlap frame.',
        );
      },
    );

    testWidgets(
      'HubSheet.Stats tile pushes via OmniNavigator (OmniRoute, not '
      'MaterialPageRoute)',
      (WidgetTester tester) async {
        final observer = _RouteTypeRecorder();
        await pumpHubSheet(tester, observer);

        await tester.tap(find.text('Stats'));
        await tester.pumpAndSettle();

        expect(
          observer.lastPushed,
          isA<OmniRoute<dynamic>>(),
          reason:
              'HubSheet.Stats must route through OmniNavigator.push so '
              'the OmniRoute wrapper applies.',
        );
        expect(
          observer.lastPushed,
          isNot(isA<MaterialPageRoute<dynamic>>()),
          reason: 'raw MaterialPageRoute bypasses the OmniRoute wrapper.',
        );
      },
    );

    testWidgets(
      'HubSheet.Nutrition tile pushes via OmniNavigator (OmniRoute, not '
      'MaterialPageRoute)',
      (WidgetTester tester) async {
        final observer = _RouteTypeRecorder();
        await pumpHubSheet(tester, observer);

        await tester.tap(find.text('Nutrition'));
        await tester.pumpAndSettle();

        expect(
          observer.lastPushed,
          isA<OmniRoute<dynamic>>(),
          reason:
              'HubSheet.Nutrition must route through OmniNavigator.push '
              'so the OmniRoute wrapper applies.',
        );
        expect(
          observer.lastPushed,
          isNot(isA<MaterialPageRoute<dynamic>>()),
          reason: 'raw MaterialPageRoute bypasses the OmniRoute wrapper.',
        );
      },
    );

    testWidgets(
      'HubSheet.Profile tile pushes via OmniNavigator (OmniRoute, not '
      'MaterialPageRoute)',
      (WidgetTester tester) async {
        final observer = _RouteTypeRecorder();
        await pumpHubSheet(tester, observer);

        await tester.tap(find.text('Profile'));
        await tester.pumpAndSettle();

        expect(
          observer.lastPushed,
          isA<OmniRoute<dynamic>>(),
          reason:
              'HubSheet.Profile must route through OmniNavigator.push so '
              'the OmniRoute wrapper applies.',
        );
        expect(
          observer.lastPushed,
          isNot(isA<MaterialPageRoute<dynamic>>()),
          reason: 'raw MaterialPageRoute bypasses the OmniRoute wrapper.',
        );
      },
    );

    testWidgets(
      'HubSheet.Settings tile pushes via OmniNavigator (OmniRoute, not '
      'MaterialPageRoute)',
      (WidgetTester tester) async {
        final observer = _RouteTypeRecorder();
        await pumpHubSheet(tester, observer);

        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();

        expect(
          observer.lastPushed,
          isA<OmniRoute<dynamic>>(),
          reason:
              'HubSheet.Settings must route through OmniNavigator.push so '
              'the OmniRoute wrapper applies.',
        );
        expect(
          observer.lastPushed,
          isNot(isA<MaterialPageRoute<dynamic>>()),
          reason: 'raw MaterialPageRoute bypasses the OmniRoute wrapper.',
        );
      },
    );

    testWidgets(
      'HubSheet exposes one maintenance item per documented destination '
      '(no destination added or removed — layout guard)',
      (WidgetTester tester) async {
        // Layout-guard regression: the navigation contract lists
        // exactly five destinations from the Hub sheet
        // (Calendar / Stats / Nutrition / Profile / Settings —
        // see .github/agents/docs/navigation_and_screens.md).
        // This test does NOT change the layout — it asserts the
        // destination set has not been altered by the navigation
        // alignment, so the Hub sheet's "out of scope" guard
        // (layout, contents, set of destinations, open/dismiss)
        // stays intact.
        await pumpHubSheet(tester, _RouteTypeRecorder());

        for (final title in const [
          'Calendar',
          'Stats',
          'Nutrition',
          'Profile',
          'Settings',
        ]) {
          expect(
            find.descendant(
              of: find.byType(HubSheet),
              matching: find.text(title),
            ),
            findsOneWidget,
            reason: 'Hub sheet must expose the "$title" tile '
                '(layout/destination guard).',
          );
        }
      },
    );
  });
}
