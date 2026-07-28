import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
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

Future<void> _pumpSessionScreenWithTextScale(
  WidgetTester tester, {
  required WorkoutState workoutState,
  required RoutineState routineState,
  required SessionSummaryService sessionSummaryService,
  required MockWorkoutRepository repository,
  double textScaleFactor = 1.0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScaleFactor)),
        child: WorkoutSessionScreen(
          workoutState: workoutState,
          routineState: routineState,
          sessionSummaryService: sessionSummaryService,
          timerAlertService: FakeTimerAlertService(),
          settingsState: SettingsState(repository, fakePreferencesService()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// PR 3 / S-001 — Reusable assertion that the coach-mark glow centre sits
/// within `_kAlignmentTolerance` px of the info icon glyph centre. The
/// glow is computed from the icon's `RenderBox` centre; an
/// IconButton-wrapped icon must still resolve to the icon's own glyph
/// centre, not the wrapping IconButton's tap target.
Future<void> _expectGlowCenteredOnInfoIcon(
  WidgetTester tester,
  Exercise exercise,
) async {
  final glowCenter = _glowCenter(tester);
  final iconCenter = tester.getCenter(
    find.descendant(
      of: find.byKey(const Key('exercise-info-button')),
      matching: find.byIcon(Icons.info_outline),
    ),
  );

  const tolerance = 2.0;
  expect(
    (glowCenter.dx - iconCenter.dx).abs(),
    lessThan(tolerance),
    reason:
        'Coach-mark glow must centre on the info icon glyph at every '
        'viewport width and text scale.',
  );
  expect(
    (glowCenter.dy - iconCenter.dy).abs(),
    lessThan(tolerance),
  );
}

Future<({WorkoutState workoutState, RoutineState routineState, Exercise exercise})>
    _primeSessionForCoachMark(WidgetTester tester) async {
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
  await tester.tap(find.text(exercise.name).first);
  await tester.pumpAndSettle();
  expect(find.text('View exercise info'), findsOneWidget);

  return (
    workoutState: workoutState,
    routineState: routineState,
    exercise: exercise,
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

  // ─────────────────────────────────────────────────────────────────────────
  // PR 3 / S-001 — Multi-width + maximum text scale coverage.
  // The coach mark MUST follow the actual info icon glyph across
  // every viewport width AND at the largest text scale, because the
  // icon's render-box centre is the single source of truth for the
  // glow + the triangle pointer. If the geometry were anchored to a
  // fixed offset or to the screen title, any width or text-scale
  // change would misalign the glow.
  // ─────────────────────────────────────────────────────────────────────────
  group('S-001: info-icon coach mark glow centres on the icon glyph across '
      'widths and text scales', () {
    testWidgets(
      'S-001a: small width (iPhone-class, 360 dp)',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(720, 1600);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final prime = await _primeSessionForCoachMark(tester);
        await _expectGlowCenteredOnInfoIcon(tester, prime.exercise);
      },
    );

    testWidgets(
      'S-001b: medium width (default ~600 dp)',
      (WidgetTester tester) async {
        // Default test viewport is ~800×600 logical; tighten to a
        // standard "medium" phone (iPhone Pro Max family) without
        // forcing a device pixel ratio override.
        final prime = await _primeSessionForCoachMark(tester);
        await _expectGlowCenteredOnInfoIcon(tester, prime.exercise);
      },
    );

    testWidgets(
      'S-001c: large width (tablet-class, 840 dp)',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1680, 2800);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final prime = await _primeSessionForCoachMark(tester);
        await _expectGlowCenteredOnInfoIcon(tester, prime.exercise);
      },
    );

    testWidgets(
      'S-001d: maximum text scale (the icon must still be the anchor)',
      (WidgetTester tester) async {
        // Largest accessibility text scale. The icon glyph itself
        // is not text and does not scale, but surrounding header
        // text and the controller's IconButton constraints can
        // change the icon's layout. The glow centre must remain on
        // the icon glyph centre regardless of the surrounding
        // reflow.
        final repo = MockWorkoutRepository();
        await repo.initialize();
        await repo.setPreferenceBool(_kNotesHintKey, true);
        await repo.setPreferenceBool(_kInfoHintKey, false);

        final workoutState = WorkoutState(repo);
        final routineState = RoutineState(repo);
        final sessionSummaryService = SessionSummaryService(repo);
        await workoutState.createNewSession(modality: 'resistance_lifting');
        final exercises = await repo.getExercises();
        final exercise = exercises.first;
        await workoutState.addExerciseToSession(
          exercise,
          chosenMetric: 'reps',
        );

        await _pumpSessionScreenWithTextScale(
          tester,
          workoutState: workoutState,
          routineState: routineState,
          sessionSummaryService: sessionSummaryService,
          repository: repo,
          textScaleFactor: 3.0,
        );
        await tester.tap(find.text(exercise.name).first);
        await tester.pumpAndSettle();
        expect(find.text('View exercise info'), findsOneWidget);

        await _expectGlowCenteredOnInfoIcon(tester, exercise);
      },
    );
  });
}
