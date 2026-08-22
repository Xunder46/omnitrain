// Tests for PR 2: Launch Quality Hotfix.
//
// Scenarios in
// `.github/agents/plans/2026-07-27-02-pr2-launch-quality-hotfix-plan.md`
// map 1:1 to the tests below:
//
//   S-001 — Healthy startup remains non-failure throughout
//   S-002 — Genuine startup failure retries safely
//   S-003 — Gesture removal preserves explicit interaction
//
// S-001 / S-002 exercise the StartupRoot state split. The fix is
// required because the current implementation renders the failure
// surface during preparation as well as on genuine failure (see
// `lib/app/startup_root.dart` and
// `.github/agents/docs/navigation_and_screens.md` line 57: "current
// implementation does not model preparation separately from
// failure"). These tests assert the new contract: while the runner
// is in flight, the failure surface must NOT render, and the
// failure screen must only appear once a real failure has been
// observed.
//
// S-003 exercises the gesture removal on the workout detail and
// routine-setup detail screens. The current implementation wires
// HorizontalDragEnd / VerticalDragEnd handlers directly on the
// body GestureDetector; PR 2 deletes those handlers. The tests
// below fail until the handlers are removed.
//
// Note: Pre-existing swipe-related tests in
// `test/session_toolbar_rework_test.dart` are DELETED per the
// plan — "delete, rather than adapt, tests whose expected
// behavior is swipe navigation".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/app/startup_root.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/routine/routine_setup_screen.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/features/startup/startup_failure_screen.dart';
import 'package:omnitrain/features/startup/startup_preparing_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/session/inline_metric_editor.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

Future<void> _noopPersist(Object _, StackTrace __) async {}

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  await repo.setPreferenceBool('hint_seen_exercise_info', true);
  await repo.setPreferenceBool('hint_seen_exercise_notes', true);
  return repo;
}

Future<Exercise> _getExerciseById(
  MockWorkoutRepository repo,
  String id,
) async {
  final exercises = await repo.getExercises();
  return exercises.firstWhere((e) => e.id == id);
}

typedef _SessionDeps = ({
  WorkoutState workoutState,
  RoutineState routineState,
  SessionSummaryService sessionSummaryService,
  SettingsState settingsState,
});

Future<_SessionDeps> _buildSessionDeps({String? modality}) async {
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

Widget _buildSessionScreen(_SessionDeps deps) {
  return MaterialApp(
    home: WorkoutSessionScreen(
      workoutState: deps.workoutState,
      routineState: deps.routineState,
      sessionSummaryService: deps.sessionSummaryService,
      timerAlertService: FakeTimerAlertService(),
      settingsState: deps.settingsState,
    ),
  );
}

Future<void> _openDetailView(WidgetTester tester, String exerciseName) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text(exerciseName));
  await tester.pumpAndSettle();
}

void main() {
  // ── S-001 / S-002 — StartupRoot preparing/distinct states ─────────────

  /// The preparing screen's only themed foreground element.
  Color? _preparingSpinnerColor(WidgetTester tester) {
    final indicator = tester.widget<CircularProgressIndicator>(
      find.descendant(
        of: find.byType(StartupPreparingScreen),
        matching: find.byType(CircularProgressIndicator),
      ),
    );
    return indicator.valueColor?.value;
  }

  group('StartupRoot — preparing state (S-001)', () {
    testWidgets(
      'preparing renders a non-failure surface and never shows the failure screen on a healthy launch',
      (WidgetTester tester) async {
        final calls = <String>[];

        Future<Widget> succeedAfterTicks() async {
          // Yield a few microtasks so the preparing state is observable
          // before the runner completes.
          for (var i = 0; i < 3; i++) {
            await Future<void>.delayed(Duration.zero);
          }
          calls.add('succeeded');
          return const MaterialApp(
            home: Scaffold(body: Text('APP-SURFACE-MARKER')),
          );
        }

        await tester.pumpWidget(
          StartupRoot(
            startupRunner: succeedAfterTicks,
            onStartupFailurePersisted: _noopPersist,
          ),
        );

        // Pump but do NOT settle: the runner is still in flight.
        await tester.pump();

        // After the first frame, the failure screen MUST NOT be in the
        // tree even though the startup runner has not completed yet.
        expect(
          find.byType(StartupFailureScreen),
          findsNothing,
          reason:
              'S-001: preparation must render a neutral surface, not the failure screen.',
        );

        // Let the runner resolve.
        await tester.pumpAndSettle();

        // After completion, the running app mounts and the failure
        // screen is still absent.
        expect(find.byType(StartupFailureScreen), findsNothing);
        expect(find.text('APP-SURFACE-MARKER'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'preparing screen adopts a theme change while mounted instead of holding the default',
      (WidgetTester tester) async {
        addTearDown(() => OmniTheme.activeTheme = AppTheme.abyssalNeon);
        OmniTheme.activeTheme = AppTheme.abyssalNeon;

        // The screen is mounted before startup knows the user's theme, so
        // reading the token once at build time would pin it to the default
        // for the whole run. This pins that it tracks the change instead.
        await tester.pumpWidget(
          const MaterialApp(home: StartupPreparingScreen()),
        );
        await tester.pump();

        expect(
          _preparingSpinnerColor(tester),
          OmniTheme.colorsForTheme(AppTheme.abyssalNeon).primary,
        );

        // Startup resolves the saved theme part-way through the run.
        OmniTheme.activeTheme = AppTheme.crimsonDojo;
        await tester.pump();

        expect(find.byType(StartupPreparingScreen), findsOneWidget);
        expect(
          _preparingSpinnerColor(tester),
          OmniTheme.colorsForTheme(AppTheme.crimsonDojo).primary,
          reason:
              'The preparing screen must listen for the theme adoption rather '
              'than read it once — otherwise it flashes the default palette '
              'for the length of startup.',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'preparing transitions to the failure screen only after a real failure',
      (WidgetTester tester) async {
        Future<Widget> throwAfterTicks() async {
          for (var i = 0; i < 2; i++) {
            await Future<void>.delayed(Duration.zero);
          }
          throw StateError('startup blew up');
        }

        await tester.pumpWidget(
          StartupRoot(
            startupRunner: throwAfterTicks,
            onStartupFailurePersisted: _noopPersist,
          ),
        );
        await tester.pump();

        // Still in flight — failure screen is not yet mounted.
        expect(find.byType(StartupFailureScreen), findsNothing);

        // Let the throw propagate and the failure surface mount.
        await tester.pumpAndSettle();

        expect(find.byType(StartupFailureScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('StartupRoot — retry cycle (S-002)', () {
    testWidgets(
      'fail→success: Retry enters preparing, then mounts the app without a blank frame',
      (WidgetTester tester) async {
        var attempt = 0;

        Future<Widget> recoverOnRetry() async {
          attempt += 1;
          if (attempt == 1) {
            throw StateError('transient');
          }
          // Two yields so the intermediate "preparing" frame is
          // observable by the test.
          await Future<void>.delayed(Duration.zero);
          await Future<void>.delayed(Duration.zero);
          return const MaterialApp(
            home: Scaffold(body: Text('RECOVERED-SURFACE')),
          );
        }

        await tester.pumpWidget(
          StartupRoot(
            startupRunner: recoverOnRetry,
            onStartupFailurePersisted: _noopPersist,
          ),
        );
        await tester.pumpAndSettle();

        // First attempt landed on the failure screen.
        expect(find.byType(StartupFailureScreen), findsOneWidget);

        // Tap Retry. After the first pump the failure screen must be
        // gone (we are in preparing), and the recovered surface must
        // not be in the tree yet.
        await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
        await tester.pump();

        expect(
          find.byType(StartupFailureScreen),
          findsNothing,
          reason:
              'S-002: entering preparing must remove the failure screen.',
        );
        expect(find.text('RECOVERED-SURFACE'), findsNothing);

        // Pump through the awaited yields and the recovery.
        await tester.pumpAndSettle();

        expect(find.byType(StartupFailureScreen), findsNothing);
        expect(find.text('RECOVERED-SURFACE'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'fail→fail: Retry enters preparing, then returns to the failure screen',
      (WidgetTester tester) async {
        var attempt = 0;

        Future<Widget> persistentFailure() async {
          attempt += 1;
          await Future<void>.delayed(Duration.zero);
          throw StateError('never recovers (attempt $attempt)');
        }

        await tester.pumpWidget(
          StartupRoot(
            startupRunner: persistentFailure,
            onStartupFailurePersisted: _noopPersist,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(StartupFailureScreen), findsOneWidget);

        await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
        await tester.pump();

        // Preparing interval: failure screen must be gone.
        expect(find.byType(StartupFailureScreen), findsNothing);

        // Let the second failure propagate.
        await tester.pumpAndSettle();

        expect(find.byType(StartupFailureScreen), findsOneWidget);
        expect(attempt, 2);
        expect(tester.takeException(), isNull);
      },
    );
  });

  // ── S-003 — Detail-screen swipe removal ────────────────────────────────

  group('WorkoutSessionScreen detail view — swipe removal (S-003)', () {
    testWidgets(
      'S-003a: no GestureDetector on the detail body has swipe-navigation handlers',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final deps = await _buildSessionDeps(modality: 'resistance_lifting');
        final repo = await _freshRepo();
        final exercise = await _getExerciseById(repo, 'exercise-barbell-squat');
        final effortId = await deps.workoutState.addExerciseToSession(
          exercise,
          chosenMetric: 'reps',
        );
        await deps.workoutState.addEntry(effortId);
        await deps.workoutState.addEntry(effortId);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, 'Barbell Back Squat');
        expect(find.text('Set 1 of 3'), findsOneWidget);

        // After PR 2, no GestureDetector anywhere in the detail body
        // may register onHorizontalDragEnd or onVerticalDragEnd.
        final swipingGestureDetectors = find.byWidgetPredicate(
          (widget) =>
              widget is GestureDetector &&
              (widget.onHorizontalDragEnd != null ||
                  widget.onVerticalDragEnd != null),
        );
        expect(
          swipingGestureDetectors,
          findsNothing,
          reason:
              'S-003: PR 2 must remove swipe navigation handlers from the workout detail view.',
        );
      },
    );

    testWidgets(
      'S-003b: vertical fling does not change exercise',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final deps = await _buildSessionDeps(modality: 'resistance_lifting');
        final repo = await _freshRepo();
        final squat = await _getExerciseById(repo, 'exercise-barbell-squat');
        final rounds = await _getExerciseById(
          repo,
          'exercise-heavy-bag-rounds',
        );

        await deps.workoutState.addExerciseToSession(squat, chosenMetric: 'reps');
        await deps.workoutState.addExerciseToSession(
          rounds,
          effortKindOverride: 'round',
        );

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, 'Barbell Back Squat');
        expect(find.text('Barbell Back Squat'), findsOneWidget);

        // Fling upward — must NOT advance to the next exercise.
        await tester.fling(find.byType(Scaffold).first, const Offset(0, -500), 1200);
        await tester.pumpAndSettle();

        expect(
          find.text('Barbell Back Squat'),
          findsOneWidget,
          reason: 'S-003: vertical swipe must not advance the exercise.',
        );
        expect(find.text('Heavy Bag Rounds'), findsNothing);
      },
    );

    testWidgets(
      'S-003c: horizontal fling does not change set',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final deps = await _buildSessionDeps(modality: 'resistance_lifting');
        final repo = await _freshRepo();
        final exercise = await _getExerciseById(repo, 'exercise-barbell-squat');
        final effortId = await deps.workoutState.addExerciseToSession(
          exercise,
          chosenMetric: 'reps',
        );
        await deps.workoutState.addEntry(effortId);
        await deps.workoutState.addEntry(effortId);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, 'Barbell Back Squat');
        expect(find.text('Set 1 of 3'), findsOneWidget);

        // Fling left — must NOT advance to set 2.
        await tester.fling(
          find.byType(Scaffold).first,
          const Offset(-500, 0),
          1200,
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Set 1 of 3'),
          findsOneWidget,
          reason: 'S-003: horizontal swipe must not advance the set.',
        );
        expect(find.text('Set 2 of 3'), findsNothing);
      },
    );

    testWidgets(
      'S-003d: explicit Previous/Next arrows still navigate between sets',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final deps = await _buildSessionDeps(modality: 'resistance_lifting');
        final repo = await _freshRepo();
        final exercise = await _getExerciseById(repo, 'exercise-barbell-squat');
        final effortId = await deps.workoutState.addExerciseToSession(
          exercise,
          chosenMetric: 'reps',
        );
        await deps.workoutState.addEntry(effortId);
        await deps.workoutState.addEntry(effortId);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, 'Barbell Back Squat');
        expect(find.text('Set 1 of 3'), findsOneWidget);

        // Forward arrow advances the set.
        await tester.tap(find.byIcon(Icons.arrow_forward).last);
        await tester.pumpAndSettle();
        expect(find.text('Set 2 of 3'), findsOneWidget);

        // Back arrow returns to set 1.
        await tester.tap(find.byIcon(Icons.arrow_back).last);
        await tester.pumpAndSettle();
        expect(find.text('Set 1 of 3'), findsOneWidget);

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'S-003e: InlineMetricEditor (number scroller) tap-to-edit still updates the value',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final deps = await _buildSessionDeps(modality: 'resistance_lifting');
        final repo = await _freshRepo();
        final exercise = await _getExerciseById(repo, 'exercise-barbell-squat');
        final effortId = await deps.workoutState.addExerciseToSession(
          exercise,
          chosenMetric: 'reps',
        );
        await deps.workoutState.addEntry(effortId);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, 'Barbell Back Squat');
        expect(find.text('Set 1 of 2'), findsOneWidget);

        final beforeReps =
            tester
                .widget<InlineMetricEditor>(find.byType(InlineMetricEditor).first)
                .currentValue as int;

        await tester.tap(find.byType(InlineMetricEditor).first);
        await tester.pumpAndSettle();

        if (find.byType(AlertDialog).evaluate().isNotEmpty) {
          final newReps = beforeReps + 5;
          await tester.enterText(find.byType(TextField), '$newReps');
          await tester.tap(find.text('Ok'));
          await tester.pumpAndSettle();
        }

        final afterReps =
            tester
                .widget<InlineMetricEditor>(find.byType(InlineMetricEditor).first)
                .currentValue as int;

        expect(
          afterReps,
          greaterThan(beforeReps),
          reason: 'S-003: number scroller must remain interactive.',
        );
        expect(find.text('Set 1 of 2'), findsOneWidget);
        expect(find.text('Set 2 of 2'), findsNothing);
      },
    );
  });

  group('RoutineSetupScreen detail view — swipe removal (S-003)', () {
    testWidgets(
      'S-003f: no GestureDetector on the routine detail body has swipe-navigation handlers',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        final routineState = RoutineState(repo);
        routineState.setAutosaveEnabled(false);

        final exercise = await _getExerciseById(repo, 'exercise-barbell-squat');
        await routineState.createNewRoutine('Test routine');
        final effortId = await routineState.addExerciseToRoutine(
          exercise,
          'set',
        );
        await routineState.addSetForEffort(effortId, 'set');
        await routineState.addSetForEffort(effortId, 'set');
        await routineState.saveRoutine();
        final templateId = routineState.currentTemplate!.id;

        await tester.pumpWidget(
          MaterialApp(
            home: RoutineSetupScreen(
              routineState: routineState,
              workoutState: workoutState,
              templateId: templateId,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Open the detail view by tapping the exercise row.
        await tester.tap(find.text('Barbell Back Squat'));
        await tester.pumpAndSettle();

        // Sanity check: detail view is showing the set indicator.
        expect(find.text('Set 1 of 3'), findsOneWidget);

        // After PR 2, no GestureDetector on the routine detail body
        // may register onHorizontalDragEnd or onVerticalDragEnd.
        final swipingGestureDetectors = find.byWidgetPredicate(
          (widget) =>
              widget is GestureDetector &&
              (widget.onHorizontalDragEnd != null ||
                  widget.onVerticalDragEnd != null),
        );
        expect(
          swipingGestureDetectors,
          findsNothing,
          reason:
              'S-003: PR 2 must remove swipe navigation handlers from the routine detail view.',
        );
      },
    );

    testWidgets(
      'S-003g: explicit Previous/Next arrows still navigate between sets',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        final routineState = RoutineState(repo);
        routineState.setAutosaveEnabled(false);

        final exercise = await _getExerciseById(repo, 'exercise-barbell-squat');
        await routineState.createNewRoutine('Test routine');
        final effortId = await routineState.addExerciseToRoutine(
          exercise,
          'set',
        );
        // Seed explicit set 0 target so we can add a second set after
        // opening the detail view (mirrors the existing screen_widget
        // test pattern).
        await routineState.setTargetValue(
          effortId,
          'metric-reps',
          'unit-reps',
          setIndex: 0,
          targetInt: 10,
        );
        await routineState.saveRoutine();
        final templateId = routineState.currentTemplate!.id;

        await tester.pumpWidget(
          MaterialApp(
            home: RoutineSetupScreen(
              routineState: routineState,
              workoutState: workoutState,
              templateId: templateId,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Open the detail view.
        await tester.tap(find.text('Barbell Back Squat'));
        await tester.pumpAndSettle();
        expect(find.text('Set 1 of 1'), findsOneWidget);

        // Add a second set via the additive button so the routine
        // ends up with two sets to navigate between.
        await tester.tap(find.byKey(const Key('routine-add-set')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();
        expect(find.text('Set 2 of 2'), findsOneWidget);

        // The Previous/Next tooltips uniquely identify the set
        // navigation arrows (the app bar's back arrow has a
        // different tooltip / role).
        final nextArrow = find.byTooltip('Next Set');
        final prevArrow = find.byTooltip('Previous Set');
        expect(nextArrow, findsOneWidget);
        expect(prevArrow, findsOneWidget);

        // Back arrow moves to set 1.
        await tester.tap(prevArrow);
        await tester.pumpAndSettle();
        expect(find.text('Set 1 of 2'), findsOneWidget);

        // Forward arrow advances to set 2.
        await tester.tap(nextArrow);
        await tester.pumpAndSettle();
        expect(find.text('Set 2 of 2'), findsOneWidget);

        expect(tester.takeException(), isNull);
      },
    );
  });
}
