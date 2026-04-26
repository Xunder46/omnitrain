import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/routine_session_service.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/home/home_screen.dart';
import 'package:omnitrain/features/profile/profile_screen.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';
import 'package:omnitrain/state/home/home_state.dart';
import 'package:omnitrain/state/period/period_state.dart';
import 'package:omnitrain/state/profile/profile_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'helpers/fake_timer_alert_service.dart';

void main() {
  testWidgets('Profile tile opens ProfileScreen', (tester) async {
    final repository = MockWorkoutRepository();
    await repository.initialize();

    final workoutState = WorkoutState(repository);
    final homeState = HomeState(repository);
    final routineState = RoutineState(repository);
    final calendarState = CalendarState(repository);
    final periodState = PeriodState(repository);
    final profileState = ProfileState(repository);
    final settingsState = SettingsState(repository);
    await settingsState.initialize();
    final routineSessionService = RoutineSessionService(repository);
    final sessionSummaryService = SessionSummaryService(repository);

    // Use a tall viewport so the sheet content is reachable
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.window.physicalSizeTestValue = const Size(400, 900);
    binding.window.devicePixelRatioTestValue = 1.0;
    addTearDown(() {
      binding.window.clearPhysicalSizeTestValue();
      binding.window.clearDevicePixelRatioTestValue();
    });

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
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Drag the bottom sheet up significantly to reveal maintenance tiles
    final scaffoldFinder = find.byType(Scaffold).first;
    final scaffoldSize = tester.getSize(scaffoldFinder);
    final scaffoldTopLeft = tester.getTopLeft(scaffoldFinder);
    final dragStart = Offset(
      scaffoldTopLeft.dx + scaffoldSize.width / 2,
      scaffoldTopLeft.dy + scaffoldSize.height - 24,
    );

    // Use a large drag to fully expand the sheet
    await tester.dragFrom(dragStart, const Offset(0, -600));
    await tester.pumpAndSettle();

    // Profile tile should now be visible and tappable
    final profileFinder = find.text('Profile');
    if (profileFinder.evaluate().isNotEmpty) {
      await tester.tap(profileFinder);
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsOneWidget);
    } else {
      // If Profile text isn't found, the maintenance tiles may use a different label.
      // Try with icon-based finder as fallback.
      await tester.tap(find.byIcon(Icons.person).first);
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsOneWidget);
    }
  });
}
