// Plan 259: the summary waits for its figures, titles the rounds card by the
// session's type, reads a zero as `0s` and follows the phone's clock setting.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/session_summary_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

/// A service whose rest-time read waits for [gate], so a test can look at the
/// screen while its figures are still loading.
class _GatedService extends SessionSummaryService {
  _GatedService(super.repository, this.gate);
  final Completer<void> gate;

  @override
  Future<int> computeSessionRestTimeMs(String sessionId) async {
    await gate.future;
    return super.computeSessionRestTimeMs(sessionId);
  }
}

typedef _Deps = ({MockWorkoutRepository repo, WorkoutState workoutState});

Future<_Deps> _deps({
  String? modality,
  bool withRound = false,
  bool withSet = false,
}) async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  final workoutState = WorkoutState(repo);
  await workoutState.createNewSession(modality: modality);
  final all = await repo.getExercises();
  if (withSet) {
    final e = all.firstWhere(
      (e) => e.capabilities.contains('reps') && e.capabilities.contains('sets'),
    );
    await workoutState.addExerciseToSession(e);
  }
  if (withRound) {
    final Exercise e = all.firstWhere((e) => e.capabilities.contains('rounds'));
    final effortId = await workoutState.addExerciseToSession(
      e,
      effortKindOverride: 'round',
    );
    await workoutState.updateRoundPlannedDuration(effortId, 0, 180);
    await workoutState.startRound(effortId, 0);
    await workoutState.completeRound(effortId, 0);
  }
  await workoutState.updateSessionFeeling(workoutState.currentSession!.id, 3);
  return (repo: repo, workoutState: workoutState);
}

Future<void> _pump(
  WidgetTester tester,
  _Deps d, {
  bool settle = true,
  bool use24Hour = false,
  Completer<void>? gate,
}) async {
  await tester.binding.setSurfaceSize(const Size(600, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: use24Hour),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SessionSummaryScreen(
                  workoutState: d.workoutState,
                  routineState: RoutineState(d.repo),
                  sessionSummaryService: gate == null
                      ? SessionSummaryService(d.repo)
                      : _GatedService(d.repo, gate),
                  settingsState: SettingsState(
                    d.repo,
                    fakePreferencesService(),
                  ),
                  timerAlertService: FakeTimerAlertService(),
                ),
              ),
            ),
            child: const Text('Open summary'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open summary'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void main() {
  group('Summary polish (plan 259)', () {
    testWidgets(
      'S-25901 the screen holds its cards until the figures are ready',
      (tester) async {
        final d = await _deps(modality: 'resistance_lifting', withSet: true);
        final gate = Completer<void>();
        await _pump(tester, d, settle: false, gate: gate);
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('DURATION'), findsNothing);
        expect(find.text('Strength'), findsNothing);

        gate.complete();
        await tester.pumpAndSettle();
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('DURATION'), findsOneWidget);
        expect(find.text('Strength'), findsOneWidget);
      },
    );

    testWidgets('S-25902 a Sports session titles the rounds card Sports', (
      tester,
    ) async {
      final d = await _deps(modality: 'sports', withRound: true);
      await _pump(tester, d);
      // The modality chip and the rounds card title both read Sports.
      expect(find.text('Sports'), findsAtLeastNWidgets(2));
      expect(find.text('Rounds'), findsNothing);
    });

    testWidgets('S-25902b any other session titles the rounds card Rounds', (
      tester,
    ) async {
      final d = await _deps(withRound: true);
      await _pump(tester, d);
      expect(find.text('Rounds'), findsWidgets);
      expect(find.text('Sports'), findsNothing);
    });

    testWidgets('S-25903 a zero rest reads 0s', (tester) async {
      final d = await _deps(modality: 'resistance_lifting', withSet: true);
      await _pump(tester, d);
      expect(find.text('0s'), findsWidgets);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('S-25904 a 12-hour phone shows AM or PM', (tester) async {
      final d = await _deps(modality: 'resistance_lifting', withSet: true);
      await _pump(tester, d);
      expect(
        find.textContaining(RegExp(r' at \d{1,2}:\d{2} [AP]M')),
        findsOneWidget,
      );
    });

    testWidgets('S-25905 a 24-hour phone shows HH:mm with no AM or PM', (
      tester,
    ) async {
      final d = await _deps(modality: 'resistance_lifting', withSet: true);
      await _pump(tester, d, use24Hour: true);
      expect(find.textContaining(RegExp(r' at \d{2}:\d{2}$')), findsOneWidget);
      expect(find.textContaining(RegExp(r'[AP]M')), findsNothing);
    });
  });
}
