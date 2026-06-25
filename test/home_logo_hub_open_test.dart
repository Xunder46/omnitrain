import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/features/home/home_screen.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/state/home/home_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';
import 'package:omnitrain/state/period/period_state.dart';
import 'package:omnitrain/state/profile/profile_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/core/services/routine_session_service.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/core/utils/timer_alert_service.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/core/services/preferences_service.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/widgets/cards/energy_tile.dart';
import 'package:omnitrain/widgets/common/home_logo_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/test_nutrition_primer_state.dart';

class FakeTimerAlertService extends TimerAlertService {
  // No-op stubs for test injection. The base class does not declare these
  // methods directly (they are exercised through other service contracts), so
  // they are intentionally not marked `@override`.
  void scheduleTimerAlert(int seconds, String message) {}
  void cancelTimerAlert(String id) {}
}

class FakePreferencesService implements PreferencesService {
  int _hubOpenCount = 0;

  @override
  Future<void> init() async {}

  @override
  int getHubOpenCount() => _hubOpenCount;

  @override
  Future<void> incrementHubOpenCount() async {
    _hubOpenCount += 1;
  }
}

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
  final preferencesService = FakePreferencesService();
  await preferencesService.init();
  final settingsState = SettingsState(repo, preferencesService);
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

void main() {
  group('HomeScreen Hub Sheet Opening', () {
    late MockWorkoutRepository repo;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      repo = MockWorkoutRepository();
    });

    testWidgets('tapping the logo opens the Hub sheet', (
      WidgetTester tester,
    ) async {
      final screen = await buildHomeScreen(repo);

      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pumpAndSettle();

      // Find the logo in the AppBar
      final logoFinder = find.byType(Image);
      expect(logoFinder, findsOneWidget);

      // Sheet is at rest: HUB label inside the sheet is not yet visible.
      expect(find.text('HUB'), findsNothing);

      // Tap the logo to open the Hub.
      await tester.tap(logoFinder);
      await tester.pumpAndSettle();

      // Hub sheet is now open: the HUB label inside the sheet is visible.
      expect(find.text('HUB'), findsOneWidget);
    });

    testWidgets('peek handle still works after logo tap', (
      WidgetTester tester,
    ) async {
      final screen = await buildHomeScreen(repo);

      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pumpAndSettle();

      // The handle lives inside the sheet. With the sheet at rest
      // (minChildSize: 0.0), the handle is off-screen and not findable.
      final handleFinder = find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.constraints != null &&
            widget.constraints!.maxWidth == 50 &&
            widget.constraints!.maxHeight == 6,
      );
      expect(handleFinder, findsNothing);

      // The logo should still be present and tappable.
      final logoFinder = find.byType(Image);
      expect(logoFinder, findsOneWidget);
      await tester.tap(logoFinder);
      await tester.pumpAndSettle();

      // Sheet is now open: the 50x6 handle pill at the top of the sheet
      // is visible, signaling the swipe-down-to-close affordance.
      expect(handleFinder, findsOneWidget);
    });

    testWidgets(
      'home screen at rest shows no Hub peek handle or visible sheet sliver',
      (WidgetTester tester,
    ) async {
        final screen = await buildHomeScreen(repo);

        await tester.pumpWidget(MaterialApp(home: screen));
        await tester.pumpAndSettle();

        // The handle lives inside the sheet. With the sheet at rest
        // (minChildSize: 0.0), the handle is off-screen.
        final handleFinder = find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.constraints != null &&
              widget.constraints!.maxWidth == 50 &&
              widget.constraints!.maxHeight == 6,
        );
        expect(handleFinder, findsNothing);

        // The HUB label is also inside the sheet content and must not be
        // visible while the sheet is at rest.
        expect(find.text('HUB'), findsNothing);
      },
    );

    testWidgets(
      'tapping the logo opens the Hub (handle is part of the sheet)',
      (WidgetTester tester,
    ) async {
        final screen = await buildHomeScreen(repo);

        await tester.pumpWidget(MaterialApp(home: screen));
        await tester.pumpAndSettle();

        // Confirm the sheet is at rest (no HUB label visible, no handle).
        expect(find.text('HUB'), findsNothing);

        // Tap the logo to open the Hub.
        final logoFinder = find.byType(Image);
        expect(logoFinder, findsOneWidget);
        await tester.tap(logoFinder);
        await tester.pumpAndSettle();

        // The HUB label should now be visible inside the expanded sheet.
        expect(find.text('HUB'), findsOneWidget);
      },
    );

    testWidgets('tapping logo when sheet is already open', (
      WidgetTester tester,
    ) async {
      final screen = await buildHomeScreen(repo);

      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pumpAndSettle();

      // Find the logo in the AppBar
      final logoFinder = find.byType(Image);
      expect(logoFinder, findsOneWidget);

      // Tap the logo twice to ensure it works when already open
      await tester.tap(logoFinder);
      await tester.pumpAndSettle();
      await tester.tap(logoFinder);
      await tester.pumpAndSettle();

      // Verify the tap doesn't crash
      expect(true, isTrue);
    });

    testWidgets('logo tile is not in the training grid', (
      WidgetTester tester,
    ) async {
      final screen = await buildHomeScreen(repo);

      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pumpAndSettle();

      // The home-screen training grid is a non-scrolling layout: a
      // `Column` of three `Row`s, each row holding two `Expanded`
      // `EnergyTile`s. The grid is NOT a `SliverGrid` / `GridView`
      // / `CustomScrollView` (the Train screen never scrolls).
      // The logo tile must NOT be a descendant of any of those
      // `Row`s — it lives in the AppBar header.
      final gridRows = find
          .descendant(
            of: find.byType(Column),
            matching: find.byType(Row),
          )
          .evaluate()
          .where((element) {
            // Filter to rows that contain at least one
            // EnergyTile — those are the grid rows.
            return find
                .descendant(
                  of: find.byWidget(element.widget),
                  matching: find.byType(EnergyTile),
                )
                .evaluate()
                .isNotEmpty;
          })
          .map((e) => find.byWidget(e.widget));

      for (final gridRow in gridRows) {
        expect(
          find.descendant(of: gridRow, matching: find.byType(HomeLogoButton)),
          findsNothing,
          reason: 'The HomeLogoButton must not live inside any '
              'training-tile row.',
        );
      }

      // The logo tile IS present in the tree, exactly once, hosted in the
      // AppBar header — not in the training grid.
      expect(find.byType(HomeLogoButton), findsOneWidget);

      // All six training tiles are mounted in the body.
      expect(find.byType(EnergyTile), findsNWidgets(6));
    });

    testWidgets('logo tile has margin from the AppBar edges', (
      WidgetTester tester,
    ) async {
      final screen = await buildHomeScreen(repo);

      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pumpAndSettle();

      // The widget's bounding box must be larger than the visible 50×50 tile
      // — the internal Padding insets the visible tile from the AppBar's
      // left edge and the status bar, and reserves room for the softer
      // shadow's blur. Asserting the bounding box is at least 60×55
      // confirms the padding is present (8px horizontal + ~4px vertical).
      final size = tester.getSize(find.byType(HomeLogoButton));
      expect(size.width, greaterThanOrEqualTo(60.0));
      expect(size.height, greaterThanOrEqualTo(55.0));
    });
  });
}
