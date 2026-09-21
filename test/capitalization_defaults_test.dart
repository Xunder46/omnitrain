import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/exercise/exercise_editor_screen.dart';
import 'package:omnitrain/features/period/create_period_screen.dart';
import 'package:omnitrain/features/profile/profile_screen.dart';
import 'package:omnitrain/features/routine/routine_setup_screen.dart';
import 'package:omnitrain/features/session/session_summary_screen.dart';
import 'package:omnitrain/state/period/period_state.dart';
import 'package:omnitrain/state/profile/profile_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/inputs/numeric_field_with_done_bar.dart';
import 'package:omnitrain/features/exercise/exercise_picker_screen.dart';
import 'helpers/fake_timer_alert_service.dart';
import 'helpers/fake_preferences_service.dart';

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

// Finds a TextField whose InputDecoration.labelText matches [label].
Finder _fieldByLabel(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);

// Finds a TextField whose InputDecoration.hintText matches [hint].
Finder _fieldByHint(String hint) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.hintText == hint,
);

void main() {
  group('Capitalization defaults — word-case fields', () {
    testWidgets(
      'exercise name field is configured for word-case capitalization',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);

        await tester.pumpWidget(
          MaterialApp(home: ExerciseEditorScreen(workoutState: workoutState)),
        );
        await tester.pumpAndSettle();

        final tf = tester.widget<TextField>(_fieldByLabel('Exercise name'));
        expect(tf.textCapitalization, TextCapitalization.words);
      },
    );

    testWidgets(
      'period name field is configured for word-case capitalization',
      (tester) async {
        final repo = await _freshRepo();
        final periodState = PeriodState(repo);

        await tester.pumpWidget(
          MaterialApp(home: CreatePeriodScreen(periodState: periodState)),
        );
        await tester.pumpAndSettle();

        final tf = tester.widget<TextField>(_fieldByLabel('Period Name *'));
        expect(tf.textCapitalization, TextCapitalization.words);
      },
    );

    testWidgets(
      'routine name field is configured for word-case capitalization',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final repo = await _freshRepo();
        final routineState = RoutineState(repo);
        routineState.setAutosaveEnabled(false);

        await tester.pumpWidget(
          MaterialApp(home: RoutineSetupScreen(routineState: routineState)),
        );
        await tester.pumpAndSettle();

        final tf = tester.widget<TextField>(_fieldByLabel('Routine Name'));
        expect(tf.textCapitalization, TextCapitalization.words);
      },
    );

    testWidgets(
      'profile display name dialog field is configured for word-case capitalization',
      (tester) async {
        final repo = await _freshRepo();
        final profileState = ProfileState(repo);
        final settingsState = SettingsState(repo, fakePreferencesService());
        await settingsState.initialize();

        await tester.pumpWidget(
          MaterialApp(
            home: ProfileScreen(
              profileState: profileState,
              settingsState: settingsState,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Open the display name dialog by tapping the name area
        await tester.tap(find.byType(InkWell).first);
        await tester.pumpAndSettle();

        // The AlertDialog should now be showing
        expect(find.text('Edit Name'), findsOneWidget);
        final tf = tester.widget<TextField>(
          find.byWidgetPredicate(
            (w) =>
                w is TextField &&
                w.decoration?.hintText == 'Enter your display name',
          ),
        );
        expect(tf.textCapitalization, TextCapitalization.words);
      },
    );
  });

  group('Capitalization defaults — sentence-case fields', () {
    testWidgets(
      'period notes field is configured for sentence-case capitalization',
      (tester) async {
        final repo = await _freshRepo();
        final periodState = PeriodState(repo);

        await tester.pumpWidget(
          MaterialApp(home: CreatePeriodScreen(periodState: periodState)),
        );
        await tester.pumpAndSettle();

        final tf = tester.widget<TextField>(_fieldByLabel('Notes (optional)'));
        expect(tf.textCapitalization, TextCapitalization.sentences);
      },
    );

    testWidgets(
      'exercise description field is configured for sentence-case capitalization',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);

        await tester.pumpWidget(
          MaterialApp(home: ExerciseEditorScreen(workoutState: workoutState)),
        );
        await tester.pumpAndSettle();

        final tf = tester.widget<TextField>(
          _fieldByLabel('Description (optional)'),
        );
        expect(tf.textCapitalization, TextCapitalization.sentences);
      },
    );
  });

  group('Capitalization defaults — no-capitalization fields', () {
    testWidgets('numeric set-logging field has no auto-capitalization', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NumericFieldWithDoneBar(
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Reps'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final tf = tester.widget<TextField>(_fieldByLabel('Reps'));
      expect(tf.textCapitalization, TextCapitalization.none);
    });

    testWidgets('exercise search field has no auto-capitalization', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1000));
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);

      // Show the exercise picker screen directly
      await tester.pumpWidget(
        MaterialApp(home: ExercisePickerScreen(workoutState: workoutState)),
      );
      await tester.pumpAndSettle();

      final tf = tester.widget<TextField>(_fieldByHint('Search exercises...'));
      expect(tf.textCapitalization, TextCapitalization.none);

      await tester.tap(_fieldByHint('Search exercises...'));
      await tester.pump();
      await tester.enterText(_fieldByHint('Search exercises...'), 'abc');
      await tester.pump();
      final updatedTf = tester.widget<TextField>(
        _fieldByHint('Search exercises...'),
      );
      expect(updatedTf.controller?.text, 'abc');
    });
  });

  group('Capitalization defaults — manual override preserved', () {
    testWidgets(
      'exercise name field allows lowercase manual override without forced reversion',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);

        await tester.pumpWidget(
          MaterialApp(home: ExerciseEditorScreen(workoutState: workoutState)),
        );
        await tester.pumpAndSettle();

        final nameField = _fieldByLabel('Exercise name');
        await tester.tap(nameField);
        await tester.pump();

        await tester.enterText(nameField, 'hello world');
        await tester.pump();

        final tf = tester.widget<TextField>(nameField);
        expect(tf.readOnly, isFalse);
        expect(tf.controller?.text, 'hello world');
      },
    );
  });

  // ---------------------------------------------------------------------------
  // SessionSummaryScreen helpers
  // ---------------------------------------------------------------------------

  Future<void> pumpSessionSummaryScreenWithoutFeelingModal(
    WidgetTester tester, {
    required MockWorkoutRepository repo,
    required WorkoutState workoutState,
  }) async {
    final sessionId = workoutState.currentSession!.id;
    await workoutState.updateSessionFeeling(sessionId, 3);

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

  group('Capitalization defaults — SessionSummaryScreen fields', () {
    testWidgets(
      '"Save as Routine" bottom sheet routine name field is configured for word-case capitalization',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        await workoutState.createNewSession();

        await pumpSessionSummaryScreenWithoutFeelingModal(
          tester,
          repo: repo,
          workoutState: workoutState,
        );

        // Open the overflow menu and tap "Save as Routine"
        await tester.tap(find.byType(PopupMenuButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save as Routine'));
        await tester.pumpAndSettle();

        final tf = tester.widget<TextField>(_fieldByLabel('Routine name'));
        expect(tf.textCapitalization, TextCapitalization.words);
      },
    );

    testWidgets(
      'session note field is configured for sentence-case capitalization',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        await workoutState.createNewSession();

        await pumpSessionSummaryScreenWithoutFeelingModal(
          tester,
          repo: repo,
          workoutState: workoutState,
        );

        final tf = tester.widget<TextField>(
          _fieldByHint('Leave a note about today\'s session'),
        );
        expect(tf.textCapitalization, TextCapitalization.sentences);
      },
    );
  });
}
