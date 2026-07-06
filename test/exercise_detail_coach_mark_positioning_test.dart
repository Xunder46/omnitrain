import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

/// The coach-mark glow overlay that appears on first-open of the exercise
/// detail header is a centred pulse around the targeted icon. Historically
/// the glow anchored on the wrapping `SizedBox` containing the `IconButton`,
/// which is offset from the visible icon glyph because the `IconButton`
/// inserts its own `Padding` + `SizedBox(30×30)` chain around the icon.
///
/// These tests assert that the glow centre sits within ~2 px of the icon
/// glyph centre for both the info and notes header icons.

const _kInfoHintKey = 'hint_seen_exercise_info';
const _kNotesHintKey = 'hint_seen_exercise_notes';

Future<void> _pumpSessionScreen(
  WidgetTester tester, {
  required WorkoutState workoutState,
  required RoutineState routineState,
  required SessionSummaryService sessionSummaryService,
  required MockWorkoutRepository repository,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: WorkoutSessionScreen(
        workoutState: workoutState,
        routineState: routineState,
        sessionSummaryService: sessionSummaryService,
        timerAlertService: FakeTimerAlertService(),
        settingsState: SettingsState(repository, fakePreferencesService()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Returns the centre of the next coach-mark glow Container. The glow is
/// the only rendered circle Container in the screen that has a non-null
/// `Border` plus a partially-transparent primary tint (notes-indicator dot,
/// set-progress pips and bilateral helper buttons have no border).
Offset _glowCenter(WidgetTester tester) {
  Finder match = find.byWidgetPredicate((widget) {
    if (widget is! Container) return false;
    final box = widget.decoration;
    if (box is! BoxDecoration) return false;
    if (box.shape != BoxShape.circle) return false;
    if (box.border == null) return false;
    return true;
  });
  final elements = match.evaluate();
  if (elements.isEmpty) {
    throw StateError(
      'Expected a bordered circular Container in the coach-mark overlay, '
      'but none was found.',
    );
  }
  if (elements.length > 1) {
    throw StateError(
      'Expected exactly one bordered circular Container in the coach-mark '
      'overlay, but found ${elements.length}.',
    );
  }
  final element = elements.single;
  return tester.getCenter(
    find.byElementPredicate(
      (e) => identical(e, element),
      description: 'coach-mark glow circle',
    ),
  );
}

void main() {
  testWidgets(
    'S-001: info-icon coach mark glow centres on the info icon glyph',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = MockWorkoutRepository();
      await repository.initialize();
      // Notes hint already seen so that the info hint is the first to fire.
      await repository.setPreferenceBool(_kNotesHintKey, true);
      await repository.setPreferenceBool(_kInfoHintKey, false);

      final workoutState = WorkoutState(repository);
      final routineState = RoutineState(repository);
      final sessionSummaryService = SessionSummaryService(repository);
      await workoutState.createNewSession(modality: 'resistance_lifting');
      final exercises = await repository.getExercises();
      final exercise = exercises.first;
      await workoutState.addExerciseToSession(exercise, chosenMetric: 'reps');

      await _pumpSessionScreen(
        tester,
        workoutState: workoutState,
        routineState: routineState,
        sessionSummaryService: sessionSummaryService,
        repository: repository,
      );

      // Enter detail mode by tapping the exercise tile.
      await tester.tap(find.text(exercise.name).first);
      await tester.pumpAndSettle();

      // Glow + label both present confirms the coach mark fired.
      expect(find.text('View exercise info'), findsOneWidget);

      final glowCenter = _glowCenter(tester);
      final iconCenter = tester.getCenter(
        find.descendant(
          of: find.byKey(const Key('exercise-info-button')),
          matching: find.byIcon(Icons.info_outline),
        ),
      );

      expect(
        (glowCenter.dx - iconCenter.dx).abs(),
        lessThan(2.0),
        reason:
            'Coach-mark glow must centre on the info icon glyph, not the '
            'wrapping IconButton box.',
      );
      expect(
        (glowCenter.dy - iconCenter.dy).abs(),
        lessThan(2.0),
      );
    },
  );

  testWidgets(
    'S-002: notes-icon coach mark glow centres on the notes icon glyph',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = MockWorkoutRepository();
      await repository.initialize();
      // Info hint already seen so the notes hint is the first to fire.
      await repository.setPreferenceBool(_kInfoHintKey, true);
      await repository.setPreferenceBool(_kNotesHintKey, false);

      final workoutState = WorkoutState(repository);
      final routineState = RoutineState(repository);
      final sessionSummaryService = SessionSummaryService(repository);
      await workoutState.createNewSession(modality: 'resistance_lifting');
      final exercises = await repository.getExercises();
      final exercise = exercises.first;
      await workoutState.addExerciseToSession(exercise, chosenMetric: 'reps');

      await _pumpSessionScreen(
        tester,
        workoutState: workoutState,
        routineState: routineState,
        sessionSummaryService: sessionSummaryService,
        repository: repository,
      );

      await tester.tap(find.text(exercise.name).first);
      await tester.pumpAndSettle();

      expect(find.text('Add notes for this exercise'), findsOneWidget);

      final glowCenter = _glowCenter(tester);
      final iconCenter = tester.getCenter(
        find.descendant(
          of: find.byKey(const Key('exercise-note-button')),
          matching: find.byIcon(Icons.edit_note),
        ),
      );

      expect(
        (glowCenter.dx - iconCenter.dx).abs(),
        lessThan(2.0),
        reason:
            'Coach-mark glow must centre on the notes icon glyph, not the '
            'wrapping IconButton box.',
      );
      expect(
        (glowCenter.dy - iconCenter.dy).abs(),
        lessThan(2.0),
      );
    },
  );
}
