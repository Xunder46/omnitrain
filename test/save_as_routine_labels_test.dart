// Plan 258: the summary's Save as Routine sheet names how each exercise is
// tracked in plain words, and saving keeps the summary open.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/modality_display.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/session_summary_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/layout/omni_bottom_cta.dart';
import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

typedef _Deps = ({
  MockWorkoutRepository repo,
  WorkoutState workoutState,
  RoutineState routineState,
});

Future<Exercise> _exercise(MockWorkoutRepository repo, String id) async {
  final exercises = await repo.getExercises();
  return exercises.firstWhere((e) => e.id == id);
}

/// A free session holding one exercise of each tracking kind.
Future<_Deps> _buildDeps() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  final workoutState = WorkoutState(repo);
  await workoutState.createNewSession();

  final all = await repo.getExercises();
  final setExercise = all.firstWhere(
    (e) => e.capabilities.contains('reps') && e.capabilities.contains('sets'),
  );
  final roundExercise = all.firstWhere(
    (e) => e.capabilities.contains('rounds'),
  );

  await workoutState.addExerciseToSession(setExercise);
  await workoutState.addExerciseToSession(
    await _exercise(repo, 'exercise-plank-hold'),
    effortKindOverride: 'drill',
  );
  await workoutState.addExerciseToSession(
    await _exercise(repo, 'exercise-easy-run'),
    effortKindOverride: 'timed',
  );
  await workoutState.addExerciseToSession(
    roundExercise,
    effortKindOverride: 'round',
  );

  await workoutState.updateSessionFeeling(workoutState.currentSession!.id, 3);
  return (
    repo: repo,
    workoutState: workoutState,
    routineState: RoutineState(repo),
  );
}

/// Opens the summary as a pushed route so Done has a first route to pop to.
Future<void> _pumpSummary(WidgetTester tester, _Deps deps) async {
  await tester.binding.setSurfaceSize(const Size(600, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SessionSummaryScreen(
                    workoutState: deps.workoutState,
                    routineState: deps.routineState,
                    sessionSummaryService: SessionSummaryService(deps.repo),
                    settingsState: SettingsState(
                      deps.repo,
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
    ),
  );
  await tester.tap(find.text('Open summary'));
  await tester.pumpAndSettle();
}

Future<void> _openSaveAsRoutine(WidgetTester tester) async {
  await tester.tap(find.byType(PopupMenuButton<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Save as Routine'));
  await tester.pumpAndSettle();
}

Finder _inSheet(Finder matching) =>
    find.descendant(of: find.byType(BottomSheet), matching: matching);

void main() {
  group('Save as Routine: plain labels and staying on the summary', () {
    testWidgets('S-25801 each exercise line reads how it is tracked in words', (
      tester,
    ) async {
      final deps = await _buildDeps();
      await _pumpSummary(tester, deps);
      await _openSaveAsRoutine(tester);

      expect(_inSheet(find.text('Reps & Sets')), findsOneWidget);
      expect(_inSheet(find.text('Hold Time')), findsOneWidget);
      expect(_inSheet(find.text('Time')), findsOneWidget);
      expect(_inSheet(find.text('Rounds')), findsOneWidget);
      for (final raw in ['set', 'drill', 'timed', 'round']) {
        expect(_inSheet(find.text(raw)), findsNothing, reason: raw);
      }
    });

    testWidgets('Save is the shared primary button and the sheet has no gap '
        'under it', (tester) async {
      final deps = await _buildDeps();
      await _pumpSummary(tester, deps);
      await _openSaveAsRoutine(tester);

      // The shared primary bottom action, not a hand-built FilledButton.
      expect(_inSheet(find.byType(OmniBottomCTA)), findsOneWidget);
      expect(
        tester.getSize(find.widgetWithText(FilledButton, 'Save').last).height,
        OmniTheme.buttonPrimaryHeight,
      );

      // The sheet surface reaches the bottom edge of the screen.
      final screenBottom = tester.getSize(find.byType(MaterialApp)).height;
      final sheetBottom = tester.getBottomLeft(find.byType(BottomSheet)).dy;
      expect(sheetBottom, closeTo(screenBottom, 0.5));
      final surfaceBottom = tester
          .getBottomLeft(
            find
                .descendant(
                  of: find.byType(BottomSheet),
                  matching: find.byType(Container),
                )
                .first,
          )
          .dy;
      expect(surfaceBottom, closeTo(screenBottom, 0.5));
    });

    test('S-25802 effortKindLabel maps the four kinds and leaves others', () {
      expect(ModalityDisplay.effortKindLabel('set'), 'Reps & Sets');
      expect(ModalityDisplay.effortKindLabel('timed'), 'Time');
      expect(ModalityDisplay.effortKindLabel('drill'), 'Hold Time');
      expect(ModalityDisplay.effortKindLabel('round'), 'Rounds');
      expect(ModalityDisplay.effortKindLabel('mystery'), 'mystery');
    });

    testWidgets('S-25803 Save keeps the summary open with a message', (
      tester,
    ) async {
      final deps = await _buildDeps();
      await _pumpSummary(tester, deps);
      await _openSaveAsRoutine(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Routine name'),
        'Plan 258 routine',
      );
      await tester.tap(_inSheet(find.text('Save')));
      await tester.pumpAndSettle();

      await deps.routineState.loadRoutines();
      expect(
        deps.routineState.routines.map((r) => r.name),
        contains('Plan 258 routine'),
      );
      expect(find.text('Routine saved'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(SessionSummaryScreen), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(deps.workoutState.currentSession, isNotNull);
    });

    testWidgets('S-25804 Done still finishes the workout and leaves', (
      tester,
    ) async {
      final deps = await _buildDeps();
      await _pumpSummary(tester, deps);
      await _openSaveAsRoutine(tester);
      await tester.tap(_inSheet(find.text('Save')));
      await tester.pumpAndSettle();

      // The short message sits over the bottom of the screen: let it clear.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.byType(SessionSummaryScreen), findsNothing);
      expect(deps.workoutState.currentSession, isNull);
    });
  });
}
