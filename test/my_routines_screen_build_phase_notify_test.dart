// Phase 1 (18a) — the audit's third site (R-2, D-150/D-151).
//
// `MyRoutinesScreen.initState` called `RoutineState.loadRoutines()`, whose first
// statements set `_isLoading` and notify (`routine_state.dart:108`) before it
// reads anything — the same trap as the session screen's load: a listener
// mounted above the screen cannot be marked dirty while the frame that mounts it
// is building (`setState() or markNeedsBuild() called during build`). The load
// now waits for that frame, and the frame that mounts the screen is still the
// empty state.
//
// The harness is the session screen's (`S-150`): a real ancestor listener, the
// screen mounted one component element below it, and the scheduler phase the
// state notified in asserted next to `tester.takeException()`.

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/core/services/routine_session_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/routine/my_routines_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

/// The screen, mounted one component element below the ancestor that listens to
/// the same state.
class _MountedBelowTheListener extends StatelessWidget {
  const _MountedBelowTheListener({required this.screen});

  final Widget screen;

  @override
  Widget build(BuildContext context) => screen;
}

Widget _harness(RoutineState routineState, Widget screen) => MaterialApp(
  home: ListenableBuilder(
    listenable: routineState,
    builder: (_, _) => _MountedBelowTheListener(screen: screen),
  ),
);

Widget _screen(MockWorkoutRepository repository, RoutineState routineState) =>
    MyRoutinesScreen(
      routineState: routineState,
      routineSessionService: RoutineSessionService(repository),
      sessionSummaryService: SessionSummaryService(repository),
      settingsState: SettingsState(repository, fakePreferencesService()),
      timerAlertService: FakeTimerAlertService(),
    );

void main() {
  testWidgets('R-2 the routines screen notifies nobody while the frame builds', (
    WidgetTester tester,
  ) async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    await repository.createTemplate(
      WorkoutTemplate(
        id: 'tmpl-1',
        name: 'Push Day',
        focusModality: 'resistance_lifting',
        createdAtMs: 100,
        updatedAtMs: 100,
      ),
    );
    final routineState = RoutineState(repository);
    final phases = <SchedulerPhase>[];
    routineState.addListener(
      () => phases.add(SchedulerBinding.instance.schedulerPhase),
    );

    await tester.pumpWidget(
      _harness(routineState, _screen(repository, routineState)),
    );
    final exception = tester.takeException();

    expect(
      phases.take(1).toList(),
      [SchedulerPhase.postFrameCallbacks],
      reason:
          'D-150/D-151 the first `loadRoutines` runs in the frame\'s post-frame callback: its '
          'first statements notify `RoutineState` (`routine_state.dart:108`) and a listener above '
          'the screen cannot be marked dirty while the frame is building',
    );
    expect(
      exception,
      isNull,
      reason:
          'the ancestor `ListenableBuilder` was marked dirty during the build, which the framework '
          'reports as `setState() or markNeedsBuild() called during build`',
    );
    expect(
      find.text('No Routines Yet'),
      findsOneWidget,
      reason:
          'the frame that mounts the screen is still the empty state: the load has not run yet',
    );

    await tester.pump();
    expect(
      find.text('Push Day'),
      findsOneWidget,
      reason: 'the deferred load still ran: the saved routine is listed',
    );
  });
}
