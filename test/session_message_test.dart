// Plan 27 phase 3 — the session area's small messages go through `OmniMessage`.
//
// `workout_session_finish.dart` used to print the exception it caught
// (`Failed to finish workout: $e`); it now shows the plain copy of D-27.2 and
// the shared failure look. The in-progress lock message of
// `workout_session_timer_mixin.dart` keeps its copy verbatim, on the shared
// look (no error icon).
//
// Scenarios: S-2702, S-2703 of
// `docs/plans/2026-10-13-27-ui-messages-plan/`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/core/utils/rest_notification_service.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_rest_notification_service.dart';
import 'helpers/fake_timer_alert_service.dart';

/// A rest-notification service whose first cancel throws, so the finish flow
/// takes its `catch` branch — the only reachable path to that failure message.
///
/// Later cancels (the screen's `dispose`) are no-ops: the point is the failed
/// finish, not a widget that cannot be torn down.
class _ThrowingRestService extends FakeRestNotificationService {
  bool _threw = false;

  @override
  Future<void> cancelRestNotifications() async {
    if (_threw) return super.cancelRestNotifications();
    _threw = true;
    throw StateError('no notification channel');
  }
}

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  // Suppress first-run coach-mark sheets that interfere with finder assertions.
  await repo.setPreferenceBool('hint_seen_exercise_info', true);
  await repo.setPreferenceBool('hint_seen_exercise_notes', true);
  return repo;
}

typedef _Deps = ({
  WorkoutState workoutState,
  RoutineState routineState,
  SessionSummaryService sessionSummaryService,
  SettingsState settingsState,
});

Future<_Deps> _buildDeps({String? modality}) async {
  final repo = await _freshRepo();
  final workoutState = WorkoutState(repo);
  final routineState = RoutineState(repo);
  final sessionSummaryService = SessionSummaryService(repo);
  final settingsState = SettingsState(repo, fakePreferencesService());
  await settingsState.initialize();
  await workoutState.createNewSession(modality: modality);
  return (
    workoutState: workoutState,
    routineState: routineState,
    sessionSummaryService: sessionSummaryService,
    settingsState: settingsState,
  );
}

Widget _buildSessionScreen(_Deps deps, {RestNotificationService? rest}) {
  return MaterialApp(
    home: WorkoutSessionScreen(
      workoutState: deps.workoutState,
      routineState: deps.routineState,
      sessionSummaryService: deps.sessionSummaryService,
      timerAlertService: FakeTimerAlertService(),
      settingsState: deps.settingsState,
      restNotificationService: rest,
    ),
  );
}

/// The `SnackBar` currently on screen.
SnackBar _snackBar(WidgetTester tester) =>
    tester.widget<SnackBar>(find.byType(SnackBar));

void main() {
  testWidgets('S-2703: a failed finish shows plain copy, not the exception', (
    tester,
  ) async {
    final deps = await _buildDeps(modality: 'cardio_endurance');
    final repo = await _freshRepo();
    final exercises = await repo.getExercises();
    await deps.workoutState.addExerciseToSession(exercises.first);

    await tester.pumpWidget(
      _buildSessionScreen(deps, rest: _ThrowingRestService()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Finish Workout'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Finish').last);
    await tester.pumpAndSettle();

    expect(
      find.text('Could not finish the workout. Try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('Failed to finish workout'), findsNothing);

    // The failure look: an error icon and the theme's surface colour.
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    final context = tester.element(find.byType(SnackBar));
    expect(
      _snackBar(tester).backgroundColor,
      Theme.of(context).colorScheme.surface,
    );
    expect(_snackBar(tester).shape, isA<RoundedRectangleBorder>());
  });

  testWidgets(
    'S-2702: the in-progress lock message keeps its copy on the shared look',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'cardio_endurance');
      final repo = await _freshRepo();
      final exercises = await repo.getExercises();
      final ex1 = exercises.firstWhere((e) => e.id == 'exercise-easy-run');
      final ex2 = exercises.firstWhere(
        (e) => e.id == 'exercise-heavy-bag-rounds',
      );

      final effortId1 = await deps.workoutState.addExerciseToSession(
        ex1,
        effortKindOverride: 'timed',
      );
      await deps.workoutState.addExerciseToSession(
        ex2,
        effortKindOverride: 'timed',
      );

      await tester.pumpWidget(_buildSessionScreen(deps));
      await tester.pumpAndSettle();
      await tester.tap(find.text(ex1.name));
      await tester.pumpAndSettle();

      // A second set to navigate to while the first one's timer runs.
      await deps.workoutState.addEntry(effortId1);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Start'));
      await tester.pump();

      final forwardBtn = find.byIcon(Icons.arrow_forward);
      expect(forwardBtn, findsOneWidget);
      await tester.tap(forwardBtn.first);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Start').first);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Another set is still in progress'),
        findsOneWidget,
      );
      // Info copy: the shared look without the failure icon.
      expect(find.byIcon(Icons.error_outline), findsNothing);
      final context = tester.element(find.byType(SnackBar));
      expect(
        _snackBar(tester).backgroundColor,
        Theme.of(context).colorScheme.surface,
      );
      expect(_snackBar(tester).shape, isA<RoundedRectangleBorder>());
    },
  );
}
