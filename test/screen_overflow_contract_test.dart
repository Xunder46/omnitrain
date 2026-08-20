import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/modality.dart';
import 'package:omnitrain/core/models/app_version_info.dart';
import 'package:omnitrain/core/services/exercise_library_service.dart';
import 'package:omnitrain/core/services/routine_session_service.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/calendar/calendar_screen.dart';
import 'package:omnitrain/features/home/home_screen.dart';
import 'package:omnitrain/features/nutrition/nutrition_screen.dart';
import 'package:omnitrain/features/profile/profile_screen.dart';
import 'package:omnitrain/features/routine/my_routines_screen.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/features/settings/settings_screen.dart';
import 'package:omnitrain/features/stats/stats_screen.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';
import 'package:omnitrain/state/exercise/exercise_library_state.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/home/home_state.dart';
import 'package:omnitrain/state/nutrition/nutrition_primer_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/period/period_state.dart';
import 'package:omnitrain/state/profile/profile_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';
import 'helpers/test_nutrition_primer_state.dart';

/// Layout-overflow contract for the app's primary screens.
///
/// A screen that overflows drops content off the bottom of the display, and it
/// happens silently in release builds — the yellow-and-black stripes only show
/// in debug. This suite renders each screen across the real iPhone range and
/// fails on any overflow, so the class of bug is caught here rather than by
/// someone noticing stripes on a device.
///
/// **This app ships to phones only.** The viewports below are deliberately
/// real device sizes; a desktop window resized shorter than any phone will
/// overflow layouts that are perfectly correct, so testing at such sizes
/// produces false alarms. Add a viewport here only if it is a device the app
/// actually ships to.
///
/// **Vertical overflow only, deliberately.** `flutter test` renders with a
/// placeholder font whose glyphs are far wider than any real typeface, so
/// horizontal overflow here is routinely fictional: the stats screen reports a
/// 5.4pt right overflow at 375x667/1.3x under the test font and none at all
/// once a real font is loaded. Heights are close enough to reality to trust,
/// and every overflow actually observed on a device has been vertical. Adding
/// horizontal assertions would make this suite cry wolf, which ends with it
/// being ignored. Horizontal fit needs checking on a device or against a real
/// font, not here.
void main() {
  /// Shortest and tallest iPhones in current use, plus the mainstream middle.
  /// Short catches "content does not fit"; tall catches "content stretches to
  /// fill" — the calendar grid regressed in the second way.
  const viewports = <String, Size>{
    'iPhone SE 375x667': Size(375, 667),
    'iPhone 14 390x844': Size(390, 844),
    'iPhone Pro Max 440x956': Size(440, 956),
  };

  /// 1.0 is the default; 1.3 is roughly the largest of iOS's non-accessibility
  /// text sizes, which users reach through Settings without thinking of it as
  /// an accessibility feature.
  const textScales = <double>[1.0, 1.3];

  /// Gives screens something to render. Empty states are usually the shortest
  /// case, so content is what puts pressure on a layout.
  Future<void> seed(MockWorkoutRepository repo) async {
    final now = DateTime.now();
    const modalities = [
      Modality.resistanceLifting,
      Modality.cardioEndurance,
      Modality.sports,
    ];
    for (var i = 0; i < modalities.length; i++) {
      final start = DateTime(now.year, now.month, i + 1, 9);
      await repo.createSession(
        TrainingSession(
          id: 'overflow-seed-$i',
          ownerUserId: 'u-test',
          startedAtMs: start.millisecondsSinceEpoch,
          endedAtMs: start
              .add(const Duration(hours: 1, minutes: 23))
              .millisecondsSinceEpoch,
          title: 'Seeded session $i',
          modality: modalities[i],
          createdAtMs: start.millisecondsSinceEpoch,
          updatedAtMs: start.millisecondsSinceEpoch,
        ),
      );
    }
  }

  Future<SettingsState> settings(MockWorkoutRepository repo) async {
    final state = SettingsState(repo, fakePreferencesService());
    await state.initialize();
    return state;
  }

  // ── Screen builders ───────────────────────────────────────────────────────
  // Each builder owns its repository so a screen's seeding cannot leak into
  // another's expectations.

  Future<Widget> buildHome(MockWorkoutRepository repo) async {
    final workoutState = WorkoutState(repo);
    final homeState = HomeState(repo);
    await homeState.init();
    final calendarState = CalendarState(repo);
    await calendarState.init();
    final profileState = ProfileState(repo);
    await profileState.loadProfile();
    return HomeScreen(
      workoutState: workoutState,
      homeState: homeState,
      routineState: RoutineState(repo),
      routineSessionService: RoutineSessionService(repo),
      sessionSummaryService: SessionSummaryService(repo),
      calendarState: calendarState,
      periodState: PeriodState(repo),
      profileState: profileState,
      settingsState: await settings(repo),
      timerAlertService: FakeTimerAlertService(),
      nutritionState: NutritionState(repo),
      foodLibraryState: FoodLibraryState(repo),
      nutritionPrimerState: await buildNutritionPrimerState(repo),
      exerciseLibraryState: ExerciseLibraryState(
        service: ExerciseLibraryService(repo),
        workoutState: workoutState,
      ),
    );
  }

  Future<Widget> buildCalendar(MockWorkoutRepository repo) async {
    final calendarState = CalendarState(repo);
    await calendarState.init();
    return CalendarScreen(
      calendarState: calendarState,
      periodState: PeriodState(repo),
      workoutState: WorkoutState(repo),
      routineState: RoutineState(repo),
      routineSessionService: RoutineSessionService(repo),
      sessionSummaryService: SessionSummaryService(repo),
      settingsState: await settings(repo),
      timerAlertService: FakeTimerAlertService(),
    );
  }

  Future<Widget> buildSession(MockWorkoutRepository repo) async {
    final workoutState = WorkoutState(repo);
    await workoutState.createNewSession(isRolling: false);
    return WorkoutSessionScreen(
      workoutState: workoutState,
      routineState: RoutineState(repo),
      sessionSummaryService: SessionSummaryService(repo),
      timerAlertService: FakeTimerAlertService(),
      settingsState: await settings(repo),
    );
  }

  Future<Widget> buildStats(MockWorkoutRepository repo) async {
    return StatsScreen(
      workoutState: WorkoutState(repo),
      settingsState: await settings(repo),
    );
  }

  Future<Widget> buildProfile(MockWorkoutRepository repo) async {
    final profileState = ProfileState(repo);
    await profileState.loadProfile();
    return ProfileScreen(
      profileState: profileState,
      settingsState: await settings(repo),
    );
  }

  Future<Widget> buildSettings(MockWorkoutRepository repo) async {
    return SettingsScreen(
      settingsState: await settings(repo),
      timerAlertService: FakeTimerAlertService(),
      appVersionInfo: const AppVersionInfo(version: '1.0.0', build: '1'),
    );
  }

  Future<Widget> buildRoutines(MockWorkoutRepository repo) async {
    return MyRoutinesScreen(
      routineState: RoutineState(repo),
      routineSessionService: RoutineSessionService(repo),
      sessionSummaryService: SessionSummaryService(repo),
      settingsState: await settings(repo),
      timerAlertService: FakeTimerAlertService(),
    );
  }

  Future<Widget> buildNutrition(MockWorkoutRepository repo) async {
    final primerState = NutritionPrimerState(repo);
    await primerState.init();
    return NutritionScreen(
      nutritionState: NutritionState(repo),
      foodLibraryState: FoodLibraryState(repo),
      nutritionPrimerState: primerState,
    );
  }

  final screens = <String, Future<Widget> Function(MockWorkoutRepository)>{
    'Home': buildHome,
    'Calendar': buildCalendar,
    'Session': buildSession,
    'Stats': buildStats,
    'Profile': buildProfile,
    'Settings': buildSettings,
    'My Routines': buildRoutines,
    'Nutrition': buildNutrition,
  };

  screens.forEach((screenName, build) {
    group(screenName, () {
      viewports.forEach((viewportName, size) {
        for (final scale in textScales) {
          testWidgets('$viewportName at ${scale}x text', (tester) async {
            final overflows = <String>[];
            final previous = FlutterError.onError;
            FlutterError.onError = (details) {
              final text = details.exceptionAsString();
              final isVerticalOverflow =
                  text.contains('overflowed') &&
                  (text.contains('on the bottom') || text.contains('on the top'));
              if (isVerticalOverflow) {
                overflows.add(text.split('\n').first);
              } else if (text.contains('overflowed')) {
                // Horizontal: unreliable under the test font. See the note at
                // the top of this file.
              } else {
                // Anything else is a real failure and must still surface.
                previous?.call(details);
              }
            };

            try {
              final repo = MockWorkoutRepository();
              await repo.initialize();
              await seed(repo);

              await tester.binding.setSurfaceSize(size);
              addTearDown(() => tester.binding.setSurfaceSize(null));

              final screen = await build(repo);
              await tester.pumpWidget(
                MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: MaterialApp(home: screen),
                ),
              );
              // A short timeout so a screen that never settles fails here
              // instead of hanging the whole suite.
              await tester.pumpAndSettle(
                const Duration(milliseconds: 100),
                EnginePhase.sendSemanticsUpdate,
                const Duration(seconds: 20),
              );
            } finally {
              FlutterError.onError = previous;
            }

            expect(
              overflows.toSet(),
              isEmpty,
              reason:
                  '$screenName overflows at $viewportName / ${scale}x text. '
                  'Content is being pushed off the display on a real device: '
                  '${overflows.toSet().join(" | ")}',
            );
          });
        }
      });
    });
  });
}
