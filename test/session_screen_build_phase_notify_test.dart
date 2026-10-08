// Phase 1 (18a) — the build-phase notification trap.
//
// The session screen's first load notifies `WorkoutState` before it yields: the
// `initState` that used to call it ran `_loadExercises` ->
// `createNewSession()`/`loadSessionData()` -> `_setLoading(true)` ->
// `notifyListeners()` (`session_core_io.dart:137`). Every listener mounted above
// the screen is then asked to rebuild while the framework is still building,
// which the framework reports as `setState() or markNeedsBuild() called during
// build` — the error the owner saw. D-150 defers the load to the frame that
// mounts the screen; the structural half of the guard is
// `test/initstate_notify_contract_test.dart`.
//
// Each case mounts the real screen under a real ancestor listener — the
// production hierarchy — and asserts the scheduler phase the state notified in
// as well as `tester.takeException()`: a phase other than `postFrameCallbacks`
// is the defect itself, the reported exception its symptom. The overview screen
// is pumped in the same frame as the session screen, so both sites of the
// defect class are covered by one harness (S-152).
//
// `_MountedBelowTheListener` keeps one component element between the listener
// and the screens. Mounted as the listener's own child the defect cannot show:
// the framework lets an element mark itself dirty while it is the one building,
// so the mounting element has to be a descendant of the listener. The plan's
// evidence file, "Phase 1", records the harness the scenario text prescribed
// first and why it cannot reproduce.

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/session_overview_screen.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_rest_notification_service.dart';
import 'helpers/fake_timer_alert_service.dart';

/// The screens of one frame, mounted one component element below the ancestor
/// that listens to the same state.
class _MountedBelowTheListener extends StatelessWidget {
  const _MountedBelowTheListener({required this.screens});

  final List<Widget> screens;

  @override
  Widget build(BuildContext context) => screens.length == 1
      ? screens.single
      : Column(
          children: [for (final screen in screens) Expanded(child: screen)],
        );
}

/// The screen tree under an ancestor that listens to [workoutState].
Widget _harness(WorkoutState workoutState, List<Widget> screens) => MaterialApp(
  home: ListenableBuilder(
    listenable: workoutState,
    builder: (_, _) => _MountedBelowTheListener(screens: screens),
  ),
);

/// A repository whose watch-inbox read fails, so the session screen's first
/// load reaches its `catch` (`workout_session_screen.dart:512`) instead of
/// completing.
class _RefusingInboxRepository extends MockWorkoutRepository {
  @override
  Future<List<WatchInboxEntry>> getWatchInboxEntriesForSession(
    String watchSessionId,
  ) async {
    throw StateError('the inbox read refused: $watchSessionId');
  }
}

/// One phone: the repository, the real states the screens are handed, and the
/// scheduler phase recorded at every notification the state sends after
/// [recordNotificationPhases] is called.
class _Phone {
  _Phone({
    required this.repository,
    required this.workoutState,
    required this.routineState,
    required this.summaryService,
    required this.settingsState,
  });

  final MockWorkoutRepository repository;
  final WorkoutState workoutState;
  final RoutineState routineState;
  final SessionSummaryService summaryService;
  final SettingsState settingsState;

  final List<SchedulerPhase> notificationPhases = [];

  void recordNotificationPhases() {
    workoutState.addListener(
      () => notificationPhases.add(SchedulerBinding.instance.schedulerPhase),
    );
  }
}

/// A phone with one in-progress session holding one logged set, unless
/// [withSession] is false.
Future<_Phone> _phone({
  MockWorkoutRepository? repository,
  bool withSession = true,
}) async {
  final repo = repository ?? MockWorkoutRepository();
  await repo.initialize();
  // Pre-seed the coach mark flags so no overlay opens over the tree.
  await repo.setPreferenceBool('hint_seen_exercise_info', true);
  await repo.setPreferenceBool('hint_seen_exercise_notes', true);

  final settingsState = SettingsState(repo, fakePreferencesService());
  await settingsState.initialize();
  final phone = _Phone(
    repository: repo,
    workoutState: WorkoutState(repo),
    routineState: RoutineState(repo),
    summaryService: SessionSummaryService(repo),
    settingsState: settingsState,
  );

  if (withSession) {
    await phone.workoutState.createNewSession();
    final exercises = await repo.getExercises();
    final exercise = exercises.firstWhere(
      (e) => e.capabilities.contains('reps'),
      orElse: () => exercises.first,
    );
    final effortId = await phone.workoutState.addExerciseToSession(
      exercise,
      chosenMetric: 'reps',
    );
    await phone.workoutState.updateEntryValue(effortId, 0, 'reps', 8);
  }
  return phone;
}

WorkoutSessionScreen _sessionScreen(_Phone phone, {bool editMode = false}) =>
    WorkoutSessionScreen(
      workoutState: phone.workoutState,
      routineState: phone.routineState,
      sessionSummaryService: phone.summaryService,
      settingsState: phone.settingsState,
      timerAlertService: FakeTimerAlertService(),
      restNotificationService: FakeRestNotificationService(),
      editMode: editMode,
    );

SessionOverviewScreen _overviewScreen(_Phone phone) => SessionOverviewScreen(
  workoutState: phone.workoutState,
  routineState: phone.routineState,
  sessionSummaryService: phone.summaryService,
  settingsState: phone.settingsState,
  timerAlertService: FakeTimerAlertService(),
  restNotificationService: FakeRestNotificationService(),
);

void main() {
  testWidgets('S-150 the session screen notifies nobody while the frame builds', (
    WidgetTester tester,
  ) async {
    final phone = await _phone();
    final exerciseName =
        phone.workoutState.getExercisesWithEntries().first['name'] as String;
    phone.recordNotificationPhases();

    await tester.pumpWidget(
      _harness(phone.workoutState, [_sessionScreen(phone)]),
    );
    final exception = tester.takeException();

    expect(
      phone.notificationPhases.take(1).toList(),
      [SchedulerPhase.postFrameCallbacks],
      reason:
          'D-150 the first load runs in the frame\'s post-frame callback, not while `initState` '
          'is building: `loadSessionData` notifies `WorkoutState` before its first `await` '
          '(session_core_io.dart:137), and a listener mounted above the screen cannot be marked '
          'dirty while the frame that mounts it is building',
    );
    expect(
      exception,
      isNull,
      reason:
          'a listener above the screen was marked dirty during the build, which the framework '
          'reports as `setState() or markNeedsBuild() called during build`',
    );

    await tester.pump();
    expect(
      find.text(exerciseName),
      findsOneWidget,
      reason:
          'S-150 the deferred load still ran: the seeded set is on screen after the post-frame pump',
    );
  });

  testWidgets('S-151 the spinner is the first frame and the seeded set follows', (
    WidgetTester tester,
  ) async {
    final phone = await _phone();
    final exerciseName =
        phone.workoutState.getExercisesWithEntries().first['name'] as String;

    await tester.pumpWidget(
      _harness(phone.workoutState, [_sessionScreen(phone)]),
    );
    final exception = tester.takeException();

    expect(
      find.byType(CircularProgressIndicator),
      findsOneWidget,
      reason:
          'S-151(a) the first frame is the spinner (`_isLoading = true`, '
          'workout_session_screen.dart:109): the load has not run yet',
    );

    await tester.pump();
    expect(
      find.byType(CircularProgressIndicator),
      findsNothing,
      reason: 'S-151(a) the post-frame pump replaces the spinner with the session',
    );
    expect(
      find.text(exerciseName),
      findsOneWidget,
      reason: 'S-151(a) the seeded set is on screen',
    );
    expect(exception, isNull, reason: 'S-151(a) nothing escapes the frame');
  });

  testWidgets('S-151 a first load that fails reports on screen and throws nothing', (
    WidgetTester tester,
  ) async {
    final phone = await _phone(repository: _RefusingInboxRepository());

    await tester.pumpWidget(
      _harness(phone.workoutState, [_sessionScreen(phone, editMode: true)]),
    );
    final exception = tester.takeException();

    await tester.pump();
    expect(
      find.text('Error Loading Session'),
      findsOneWidget,
      reason:
          'S-151(b) the failing load is caught (`workout_session_screen.dart:512`) and surfaced, '
          'not swallowed',
    );
    expect(
      find.text('Retry'),
      findsOneWidget,
      reason: 'S-151(b) the error state keeps its retry control',
    );
    expect(
      find.byType(CircularProgressIndicator),
      findsNothing,
      reason: 'S-151(b) a failed load does not leave the spinner up',
    );
    expect(
      exception,
      isNull,
      reason: 'S-151(b) the failure is reported on screen, not thrown out of the frame',
    );
  });

  testWidgets('S-152 the overview screen pumped in the same frame notifies nobody', (
    WidgetTester tester,
  ) async {
    // Two screens share the frame; the default 800x600 surface leaves the
    // overview less height than its body needs.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final phone = await _phone(withSession: false);
    phone.recordNotificationPhases();

    await tester.pumpWidget(
      _harness(phone.workoutState, [
        _sessionScreen(phone),
        _overviewScreen(phone),
      ]),
    );
    final exception = tester.takeException();

    expect(
      phone.notificationPhases.take(1).toList(),
      [SchedulerPhase.postFrameCallbacks],
      reason:
          'S-152 `createNewSession` and `loadSessionData` notify `WorkoutState` before they yield, '
          'so the same deferral as the session screen (D-150) has to hold for the overview screen',
    );
    expect(
      exception,
      isNull,
      reason: 'S-152 the ancestor listener is not asked to rebuild while the frame is building',
    );

    await tester.pump();
    expect(
      find.byType(SessionOverviewScreen),
      findsOneWidget,
      reason: 'S-152 the same frame mounted both screens',
    );
    expect(
      find.text('0 exercises planned'),
      findsOneWidget,
      reason: 'S-152 the deferred load ran: the overview shows the session body',
    );
    expect(
      find.descendant(
        of: find.byType(SessionOverviewScreen),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
      reason: 'S-152 the overview finished its first load (spinner `:41` off)',
    );
  });
}
