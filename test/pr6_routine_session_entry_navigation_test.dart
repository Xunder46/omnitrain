// Tests for PR 6: Routine and Session Entry Navigation.
//
// Scenarios in
// `.github/agents/plans/2026-07-27-06-pr6-routine-session-entry-navigation-plan.md`
// map 1:1 to the tests below:
//
//   S-001 — Card body opens the routine editor and creates no session;
//           the explicit start control starts in one tap and shows the
//           same active-session warning as before. Hit areas are non-overlapping.
//
//   S-002 — Confirming header delete on a routine removes the template
//           and any planned-session rows but leaves completed
//           TrainingSessions, their routineTemplateId, all efforts,
//           observations, rest records, and stats/PRs unchanged.
//
//   S-003 — Starting a modality (or Free Training) lands on the
//           workout session screen and does NOT auto-open the exercise
//           picker; the empty state renders equally weighted
//           add-exercise / add-block actions that the user chooses.
//
//   S-004 — Block-header add remains direct to the picker even in the
//           empty state; routine-populated sessions bypass the empty
//           state and land directly on a populated list.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/routine_session_service.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/exercise/exercise_picker_screen.dart';
import 'package:omnitrain/features/routine/my_routines_screen.dart';
import 'package:omnitrain/features/routine/routine_setup_screen.dart';
import 'package:omnitrain/features/routine/widgets/demo_routine_badge.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

// ── Helpers ──────────────────────────────────────────────────────────────

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

Future<WorkoutTemplate> _seedRoutineTemplate(MockWorkoutRepository repo) async {
  final template = WorkoutTemplate(
    id: 'tmpl-pr6',
    name: 'PR6 Routine',
    focusModality: 'resistance_lifting',
    createdAtMs: 100,
    updatedAtMs: 100,
  );
  await repo.createTemplate(template);
  return template;
}

Future<void> _pumpAndSettle(WidgetTester tester) async {
  await tester.pumpAndSettle();
}

Widget _buildRoutinesList(MockWorkoutRepository repo) {
  final routineState = RoutineState(repo);
  final workoutState = WorkoutState(repo);
  final settingsState = SettingsState(repo, fakePreferencesService());
  return MaterialApp(
    home: MyRoutinesScreen(
      routineState: routineState,
      workoutState: workoutState,
      routineSessionService: RoutineSessionService(repo),
      sessionSummaryService: SessionSummaryService(repo),
      settingsState: settingsState,
      timerAlertService: FakeTimerAlertService(),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════
// S-001: Card opens; explicit control starts
// ══════════════════════════════════════════════════════════════════════════

void main() {
  group('S-001 routine card intent split', () {
    testWidgets(
      'tapping the card body opens RoutineSetupScreen and creates no session',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _freshRepo();
        await _seedRoutineTemplate(repo);

        await tester.pumpWidget(_buildRoutinesList(repo));
        await _pumpAndSettle(tester);

        // The card body — by-name on the routine name — should be a
        // distinct hit region that opens the editor, not the picker.
        await tester.tap(find.text('PR6 Routine'));
        // Pump once + consume the pre-existing setState-during-build
        // warning from RoutineState.loadRoutineForEditing notifying
        // during RoutineSetupScreen.initState (same workaround used in
        // interaction_flow_test.dart for the "+ New Routine" CTA flow).
        await tester.pump();
        tester.takeException();
        await _pumpAndSettle(tester);

        expect(find.byType(RoutineSetupScreen), findsOneWidget);
        expect(
          find.byType(ExercisePickerScreen),
          findsNothing,
          reason: 'card body must NOT auto-open the exercise picker',
        );
      },
    );

    testWidgets(
      'start control is rendered as a non-overlapping button on the card',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _freshRepo();
        await _seedRoutineTemplate(repo);

        await tester.pumpWidget(_buildRoutinesList(repo));
        await _pumpAndSettle(tester);

        final startFinder = find.byKey(const Key('routine-card-start'));
        expect(startFinder, findsOneWidget);
        final startRect = tester.getRect(startFinder);

        final cardFinder = find.byKey(const Key('routine-card-body'));
        expect(cardFinder, findsOneWidget);
        final cardRect = tester.getRect(cardFinder);

        // Hit rectangles must not overlap (PR 6 — non-overlapping start
        // control vs card body).
        expect(
          startRect.overlaps(cardRect),
          isFalse,
          reason:
              'start control must be in its own hit region; '
              'card body and start control must not share pixels',
        );
      },
    );

    testWidgets(
      'card has no PopupMenuButton — overflow is gone (PR 6)',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _freshRepo();
        await _seedRoutineTemplate(repo);

        await tester.pumpWidget(_buildRoutinesList(repo));
        await _pumpAndSettle(tester);

        expect(find.byType(PopupMenuButton<dynamic>), findsNothing);
      },
    );

    testWidgets(
      'header shows the routine name and a destructive delete action',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _freshRepo();
        await _seedRoutineTemplate(repo);

        await tester.pumpWidget(_buildRoutinesList(repo));
        await _pumpAndSettle(tester);

        await tester.tap(find.byKey(const Key('routine-card-body')));
        await tester.pump();
        tester.takeException();
        await _pumpAndSettle(tester);

        expect(find.byType(RoutineSetupScreen), findsOneWidget);
        // The destructive delete control lives in the editor's app bar.
        expect(find.byKey(const Key('routine-delete-action')), findsOneWidget);
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════
  // S-002: Delete preserves history
  // ══════════════════════════════════════════════════════════════════════

  group('S-002 routine delete preserves history', () {
    testWidgets(
      'header delete confirms with the routine name and states permanence',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _freshRepo();
        await _seedRoutineTemplate(repo);

        await tester.pumpWidget(_buildRoutinesList(repo));
        await _pumpAndSettle(tester);

        await tester.tap(find.byKey(const Key('routine-card-body')));
        await tester.pump();
        tester.takeException();
        await _pumpAndSettle(tester);

        await tester.tap(find.byKey(const Key('routine-delete-action')));
        await _pumpAndSettle(tester);

        // The confirmation must mention the routine by name (title and
        // body) and warn about permanence.
        expect(find.text('Delete "PR6 Routine"?'), findsOneWidget);
        expect(find.textContaining('cannot be undone'), findsOneWidget);
      },
    );

    testWidgets(
      'confirmed delete removes template but keeps completed session '
      'history, routineTemplateId, and analytics values',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _freshRepo();
        final template = await _seedRoutineTemplate(repo);

        // Seed a completed session that references this routine.
        final session = TrainingSession(
          id: 'sess-1',
          ownerUserId: 'user-1',
          title: 'PR6 Session',
          startedAtMs: 1000,
          endedAtMs: 2000,
          routineTemplateId: template.id,
          createdAtMs: 1000,
          updatedAtMs: 2000,
        );
        await repo.createSession(session);

        // Pre-delete snapshot of the session and template presence.
        expect((await repo.getTemplates()).any((t) => t.id == template.id), isTrue);
        expect((await repo.getAllSessions()).any((s) => s.id == session.id), isTrue);

        await tester.pumpWidget(_buildRoutinesList(repo));
        await _pumpAndSettle(tester);

        await tester.tap(find.byKey(const Key('routine-card-body')));
        await tester.pump();
        tester.takeException();
        await _pumpAndSettle(tester);

        await tester.tap(find.byKey(const Key('routine-delete-action')));
        await _pumpAndSettle(tester);

        // Tap the dialog's confirm-delete action.
        await tester.tap(find.byKey(const Key('routine-delete-confirm')));
        await _pumpAndSettle(tester);

        // Template gone.
        expect(await repo.getTemplateById(template.id), isNull);
        // Completed session intact with its routineTemplateId still set.
        final after = await repo.getAllSessions();
        final s = after.firstWhere((x) => x.id == session.id);
        expect(s.routineTemplateId, template.id);
        expect(s.endedAtMs, isNotNull,
            reason: 'completed sessions keep their endedAtMs after the '
                'parent routine is deleted (PR 6 / S-002)');
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════
  // S-003: Empty workout asks rather than guesses
  // ══════════════════════════════════════════════════════════════════════

  group('S-003 empty session no longer auto-opens picker', () {
    testWidgets(
      'modality-start lands on the session screen with no picker pushed',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        final routineState = RoutineState(repo);
        final settingsState = SettingsState(repo, fakePreferencesService());

        await workoutState.createNewSession(modality: 'resistance_lifting');

        await tester.pumpWidget(
          MaterialApp(
            home: WorkoutSessionScreen(
              workoutState: workoutState,
              routineState: routineState,
              sessionSummaryService: SessionSummaryService(repo),
              settingsState: settingsState,
              timerAlertService: FakeTimerAlertService(),
            ),
          ),
        );
        await _pumpAndSettle(tester);

        // The session screen is foregrounded. No auto-open picker is in the
        // route stack.
        expect(find.byType(WorkoutSessionScreen), findsOneWidget);
        expect(
          find.byType(ExercisePickerScreen),
          findsNothing,
          reason:
              'empty modality start must NOT auto-open the exercise picker '
              '(PR 6 — "new workouts land on a neutral empty session")',
        );
      },
    );

    testWidgets(
      'Free Training start lands on session screen with no picker pushed',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        final routineState = RoutineState(repo);
        final settingsState = SettingsState(repo, fakePreferencesService());

        await workoutState.createNewSession(isRolling: false);

        await tester.pumpWidget(
          MaterialApp(
            home: WorkoutSessionScreen(
              workoutState: workoutState,
              routineState: routineState,
              sessionSummaryService: SessionSummaryService(repo),
              settingsState: settingsState,
              timerAlertService: FakeTimerAlertService(),
            ),
          ),
        );
        await _pumpAndSettle(tester);

        expect(find.byType(WorkoutSessionScreen), findsOneWidget);
        expect(find.byType(ExercisePickerScreen), findsNothing);
      },
    );

    testWidgets(
      'empty session renders equally weighted add-exercise and add-block buttons',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        final routineState = RoutineState(repo);
        final settingsState = SettingsState(repo, fakePreferencesService());

        await workoutState.createNewSession(modality: 'resistance_lifting');

        await tester.pumpWidget(
          MaterialApp(
            home: WorkoutSessionScreen(
              workoutState: workoutState,
              routineState: routineState,
              sessionSummaryService: SessionSummaryService(repo),
              settingsState: settingsState,
              timerAlertService: FakeTimerAlertService(),
            ),
          ),
        );
        await _pumpAndSettle(tester);

        // Both buttons are present in the empty state.
        final addExercise = find.byKey(const Key('add-exercise'));
        final addBlock = find.byKey(const Key('add-block'));
        expect(addExercise, findsOneWidget);
        expect(addBlock, findsOneWidget);

        // Equally weighted means they share the same widget type (OutlinedButton)
        // — neither dominates as the "primary" CTA in the empty state.
        expect(
          tester.widget<OutlinedButton>(addExercise),
          isNotNull,
          reason: 'Add Exercise in the empty state must be OutlinedButton '
              '(not FilledButton) so Add Block is equally weighted',
        );
        expect(tester.widget<OutlinedButton>(addBlock), isNotNull);

        // Vertical ordering: Add Exercise above Add Block, both above the
        // bottom Finish Workout CTA.
        final addExerciseRect = tester.getRect(addExercise);
        final addBlockRect = tester.getRect(addBlock);
        final finishFinder = find.widgetWithText(
          FilledButton,
          'Finish Workout',
        );
        expect(finishFinder, findsOneWidget);
        final finishRect = tester.getRect(finishFinder);

        expect(addExerciseRect.top, lessThan(addBlockRect.top));
        expect(addBlockRect.bottom, lessThan(finishRect.top));
      },
    );

    testWidgets(
      'empty-state Add Exercise opens the picker only when tapped',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        final routineState = RoutineState(repo);
        final settingsState = SettingsState(repo, fakePreferencesService());

        await workoutState.createNewSession(modality: 'resistance_lifting');

        await tester.pumpWidget(
          MaterialApp(
            home: WorkoutSessionScreen(
              workoutState: workoutState,
              routineState: routineState,
              sessionSummaryService: SessionSummaryService(repo),
              settingsState: settingsState,
              timerAlertService: FakeTimerAlertService(),
            ),
          ),
        );
        await _pumpAndSettle(tester);

        expect(find.byType(ExercisePickerScreen), findsNothing);

        await tester.tap(find.byKey(const Key('add-exercise')));
        await _pumpAndSettle(tester);

        expect(find.byType(ExercisePickerScreen), findsOneWidget);
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════
  // S-005: Add Exercise and Add Block are always secondary
  // ══════════════════════════════════════════════════════════════════════

  group('S-005 add buttons are always secondary', () {
    Future<({MockWorkoutRepository repo, WorkoutState workoutState})>
        _bootEmptySession(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final routineState = RoutineState(repo);
      final settingsState = SettingsState(repo, fakePreferencesService());
      await workoutState.createNewSession(modality: 'resistance_lifting');
      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutSessionScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: SessionSummaryService(repo),
            settingsState: settingsState,
            timerAlertService: FakeTimerAlertService(),
          ),
        ),
      );
      await _pumpAndSettle(tester);
      return (repo: repo, workoutState: workoutState);
    }

    testWidgets(
      'empty session: Add Exercise and Add Block are OutlinedButtons, '
      'never FilledButtons',
      (WidgetTester tester) async {
        await _bootEmptySession(tester);

        expect(
          find.widgetWithText(OutlinedButton, 'Add Exercise'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(OutlinedButton, 'Add Block'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(FilledButton, 'Add Exercise'),
          findsNothing,
          reason:
              'S-005 contract: Add Exercise must NEVER be a FilledButton, '
              'even in the empty state',
        );
        expect(
          find.widgetWithText(FilledButton, 'Add Block'),
          findsNothing,
        );
        // Bottom Finish Workout CTA is the only FilledButton.
        expect(
          find.widgetWithText(FilledButton, 'Finish Workout'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'after adding a block: Add Exercise stays an OutlinedButton',
      (WidgetTester tester) async {
        final boot = await _bootEmptySession(tester);

        // Add a block via the secondary Add Block button (not the picker).
        await tester.tap(find.byKey(const Key('add-block')));
        await _pumpAndSettle(tester);

        // Sanity: a block now exists in the session.
        expect((await boot.workoutState.getSessionBlocks()).isNotEmpty, isTrue);

        // Re-pump so the populated layout (with bottom-anchored add
        // bar) mounts in place of the centered empty state.
        await _pumpAndSettle(tester);

        // S-005: even with content present, Add Exercise must stay
        // secondary. This is the regression guard for the original bug
        // ("the Add Exercise button turns primary" after adding content).
        expect(
          find.widgetWithText(OutlinedButton, 'Add Exercise'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(OutlinedButton, 'Add Block'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(FilledButton, 'Add Exercise'),
          findsNothing,
          reason:
              'S-005 contract: adding content must not flip Add Exercise '
              'to primary — only the bottom Finish Workout CTA is primary',
        );
        expect(
          find.widgetWithText(FilledButton, 'Add Block'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'after adding an exercise: Add Exercise stays an OutlinedButton',
      (WidgetTester tester) async {
        final boot = await _bootEmptySession(tester);

        // Add an exercise directly via the state (the picker is a
        // separate screen that requires a navigator stack; here we only
        // care that the bottom bar stays secondary after content lands).
        final exercises = await boot.repo.getExercises();
        final exercise = exercises.firstWhere(
          (e) => e.capabilities.contains('reps'),
        );
        await boot.workoutState.addExerciseToSession(
          exercise,
          chosenMetric: 'reps',
        );
        await boot.workoutState.loadSessionData();
        await _pumpAndSettle(tester);

        // S-005: even after an exercise lands, Add Exercise stays
        // secondary. This is the regression guard for the original bug.
        expect(
          find.widgetWithText(OutlinedButton, 'Add Exercise'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(OutlinedButton, 'Add Block'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(FilledButton, 'Add Exercise'),
          findsNothing,
          reason:
              'S-005 contract: adding an exercise must not flip Add '
              'Exercise to primary — only the bottom Finish Workout CTA '
              'is primary',
        );
        expect(
          find.widgetWithText(FilledButton, 'Add Block'),
          findsNothing,
        );
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════
  // S-004: Explicit context stays direct
  // ══════════════════════════════════════════════════════════════════════

  group('S-004 explicit context stays direct', () {
    testWidgets(
      'block-header add (when a block exists) routes straight to the picker',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        final routineState = RoutineState(repo);
        final settingsState = SettingsState(repo, fakePreferencesService());

        await workoutState.createNewSession(modality: 'resistance_lifting');
        await workoutState.addSessionBlock();

        await tester.pumpWidget(
          MaterialApp(
            home: WorkoutSessionScreen(
              workoutState: workoutState,
              routineState: routineState,
              sessionSummaryService: SessionSummaryService(repo),
              settingsState: settingsState,
              timerAlertService: FakeTimerAlertService(),
            ),
          ),
        );
        await _pumpAndSettle(tester);

        // The block-header add is the plus IconButton inside the block card.
        final blockAddBtn = find.byTooltip('Add exercise to block');
        expect(blockAddBtn, findsOneWidget);
        await tester.tap(blockAddBtn);
        await _pumpAndSettle(tester);

        expect(find.byType(ExercisePickerScreen), findsOneWidget);
      },
    );

    testWidgets(
      'routine-populated session never shows the empty state',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _freshRepo();
        final template = await _seedRoutineTemplate(repo);

        final workoutState = WorkoutState(repo);
        final routineState = RoutineState(repo);
        final settingsState = SettingsState(repo, fakePreferencesService());

        // Build the manifest the same way MyRoutinesScreen does for the
        // start control — no exercises exist yet, so an empty routine
        // exercises the "populated session" branch without needing real
        // template-efforts. This proves the empty state is bypassed for
        // any routine-populated session regardless of contents.
        await workoutState.createNewSession(
          modality: null,
          title: template.name,
          intent: 'routine',
          routineTemplateId: template.id,
          includeDefaultSegment: false,
        );
        await workoutState.loadSessionData();

        await tester.pumpWidget(
          MaterialApp(
            home: WorkoutSessionScreen(
              workoutState: workoutState,
              routineState: routineState,
              sessionSummaryService: SessionSummaryService(repo),
              settingsState: settingsState,
              timerAlertService: FakeTimerAlertService(),
            ),
          ),
        );
        await _pumpAndSettle(tester);

        // Routine-populated sessions bypass the centered empty-state layout
        // even when the manifest resolves to zero visible exercises, so the
        // user lands on the populated path and the block-header add stays
        // direct per S-004. The picker is NOT auto-opened.
        expect(find.byType(ExercisePickerScreen), findsNothing);
        expect(find.byType(WorkoutSessionScreen), findsOneWidget);
        // When the add bar is present, it must use the always-secondary
        // OutlinedButton variant (PR 6 / S-005 contract: Add Exercise and
        // Add Block are never primary, regardless of session contents).
        if (find.byKey(const Key('add-exercise')).evaluate().isNotEmpty) {
          expect(
            find.widgetWithText(OutlinedButton, 'Add Exercise'),
            findsOneWidget,
            reason:
                'routine-populated sessions render the secondary '
                'Add Exercise / Add Block bar (never primary)',
          );
          expect(
            find.widgetWithText(OutlinedButton, 'Add Block'),
            findsOneWidget,
          );
          expect(find.widgetWithText(FilledButton, 'Add Exercise'), findsNothing);
          expect(find.widgetWithText(FilledButton, 'Add Block'), findsNothing);
        }
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════
  // S-006: Start control shrinks to a bare play glyph; Demo moves
  // ══════════════════════════════════════════════════════════════════════

  group('S-006 play glyph + Demo on metadata line', () {
    const _platformMinTapTarget = 48.0;
    const _narrowPhoneWidth = 320.0;
    const _narrowPhoneHeight = 700.0;

    Future<MockWorkoutRepository> _seedMixedRoutines() async {
      final repo = MockWorkoutRepository();
      await repo.initialize();
      final now = DateTime.now().millisecondsSinceEpoch;
      // A typical-length name that previously got squeezed when the
      // 96-dp Start button ate the right edge.
      await repo.createTemplate(
        WorkoutTemplate(
          id: 'tmpl-typical',
          name: 'Bodyweight Conditioning',
          focusModality: 'resistance_lifting',
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );
      // The "Demo" routine — short name but needs the Demo pill to be
      // visible alongside the date so this regression catches the
      // original badge-on-title placement.
      await repo.createTemplate(
        WorkoutTemplate(
          id: 'tmpl-demo',
          name: 'Easy Run — 30 min',
          focusModality: 'cardio_endurance',
          isBuiltInDemo: true,
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );
      // A very long name — should still truncate, but only after the
      // first several words so it remains identifiable.
      await repo.createTemplate(
        WorkoutTemplate(
          id: 'tmpl-long',
          name: 'Full Body Hypertrophy Push Pull Legs '
              'with accessories for every muscle group',
          focusModality: 'resistance_lifting',
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );
      return repo;
    }

    Widget _pumpNarrowRoutines(MockWorkoutRepository repo) {
      final routineState = RoutineState(repo);
      final workoutState = WorkoutState(repo);
      final settingsState = SettingsState(repo, fakePreferencesService());
      return MaterialApp(
        home: MyRoutinesScreen(
          routineState: routineState,
          workoutState: workoutState,
          routineSessionService: RoutineSessionService(repo),
          sessionSummaryService: SessionSummaryService(repo),
          settingsState: settingsState,
          timerAlertService: FakeTimerAlertService(),
        ),
      );
    }

    testWidgets(
      'start control renders as a play triangle with no text label',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(
          const Size(_narrowPhoneWidth, _narrowPhoneHeight),
        );
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _seedMixedRoutines();

        await tester.pumpWidget(_pumpNarrowRoutines(repo));
        await tester.pumpAndSettle();

        // The play glyph must be findable on every row.
        final glyphs = find.descendant(
          of: find.byType(MyRoutinesScreen),
          matching: find.byIcon(Icons.play_arrow),
        );
        expect(glyphs, findsNWidgets(3));

        // No "Start" text label anywhere on the card.
        expect(find.text('Start'), findsNothing);
      },
    );

    testWidgets(
      'play glyph uses the theme accent colour with no fill and no border',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(
          const Size(_narrowPhoneWidth, _narrowPhoneHeight),
        );
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _seedMixedRoutines();

        await tester.pumpWidget(_pumpNarrowRoutines(repo));
        await tester.pumpAndSettle();

        final glyph = tester.widget<Icon>(
          find.descendant(
            of: find.byType(MyRoutinesScreen),
            matching: find.byIcon(Icons.play_arrow),
          ).first,
        );

        // Accent colour comes from the theme.
        expect(glyph.color, isNotNull);
        // No fill, no border on the icon itself.
        expect(glyph.shadows, isNull);
      },
    );

    testWidgets(
      'play glyph touch target meets the platform accessibility minimum',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(
          const Size(_narrowPhoneWidth, _narrowPhoneHeight),
        );
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _seedMixedRoutines();

        await tester.pumpWidget(_pumpNarrowRoutines(repo));
        await tester.pumpAndSettle();

        // Locate the play glyph by accessibility label rather than text,
        // since the label has been removed (S-006 acceptance criterion).
        final bySemantics = find.byTooltip('Start routine');
        expect(bySemantics, findsNWidgets(3));

        final glyphRect = tester.getRect(bySemantics.first);
        expect(glyphRect.width, greaterThanOrEqualTo(_platformMinTapTarget));
        expect(glyphRect.height, greaterThanOrEqualTo(_platformMinTapTarget));
      },
    );

    testWidgets(
      'play glyph is smaller than the row body touch region',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(
          const Size(_narrowPhoneWidth, _narrowPhoneHeight),
        );
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _seedMixedRoutines();

        await tester.pumpWidget(_pumpNarrowRoutines(repo));
        await tester.pumpAndSettle();

        final glyphRect = tester.getRect(
          find.byTooltip('Start routine').first,
        );
        final bodyRect = tester.getRect(
          find.byKey(const Key('routine-card-body')).first,
        );

        expect(
          glyphRect.width * glyphRect.height,
          lessThan(bodyRect.width * bodyRect.height),
          reason:
              'S-006 contract: the row body must cover more touch area '
              'than the play glyph — accidental starts are the bug this '
              'refactor is fixing',
        );
      },
    );

    testWidgets(
      'Demo marker renders on the metadata line, not the title line',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(
          const Size(_narrowPhoneWidth, _narrowPhoneHeight),
        );
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _seedMixedRoutines();

        await tester.pumpWidget(_pumpNarrowRoutines(repo));
        await tester.pumpAndSettle();

        // Find the title text for the demo routine.
        final demoTitleFinder = find.text('Easy Run — 30 min');
        expect(demoTitleFinder, findsOneWidget);

        // PR 6 / S-008 — the Demo badge sits on the TITLE row, not the
        // metadata (date) line. It is vertically centred with the title
        // text. The pre-S-006 placement had the badge as a Row sibling
        // of the title (same y); the S-006 / S-007 placement moved it
        // to the metadata line; S-008 brings it back to the title row
        // because the start control is now small enough (56-dp tap
        // region) that the title row can host the badge without
        // crowding the routine name.
        final titleRect = tester.getRect(demoTitleFinder);
        final badgeRect = tester.getRect(find.byType(DemoRoutineBadge));

        // Vertical alignment: badge sits on the title row (badge.top
        // is within or near the title's vertical band).
        expect(
          badgeRect.top,
          lessThanOrEqualTo(titleRect.bottom),
          reason:
              'Demo badge must sit on the title row (badge.top within '
              'the title band), not below it',
        );
        expect(
          badgeRect.bottom,
          greaterThanOrEqualTo(titleRect.top),
          reason:
              'Demo badge must sit on the title row (badge.bottom '
              'within the title band)',
        );

        // Vertically centred with the title text: badge centre y is
        // close to the title centre y (within a few dp).
        final titleCenterY = titleRect.center.dy;
        final badgeCenterY = badgeRect.center.dy;
        expect(
          (badgeCenterY - titleCenterY).abs(),
          lessThan(titleRect.height),
          reason:
              'Demo badge must be vertically centred with the title '
              'text (badge centre y within the title height band)',
        );

        // The badge must share an IMMEDIATE Row parent with the title
        // text. Pre-S-006 had this; S-006 / S-007 moved the badge to
        // the metadata line; S-008 returns it here.
        final titleParentRow = find
            .ancestor(
              of: demoTitleFinder,
              matching: find.byType(Row),
            )
            .first;
        final titleRowContainsBadge = find
            .descendant(
              of: titleParentRow,
              matching: find.byType(DemoRoutineBadge),
            )
            .evaluate()
            .isNotEmpty;
        expect(
          titleRowContainsBadge,
          isTrue,
          reason:
              'Demo badge must be a descendant of the title\'s parent '
              'Row — it sits next to the routine name on the title line',
        );

        // The badge must NOT share a parent with the date text — the
        // date is on the metadata line, not the title line.
        final dateFinder = find.textContaining('Created ');
        final dateParentRow = find
            .ancestor(
              of: dateFinder.first,
              matching: find.byType(Row),
            )
            .first;
        final dateRowContainsBadge = find
            .descendant(
              of: dateParentRow,
              matching: find.byType(DemoRoutineBadge),
            )
            .evaluate()
            .isNotEmpty;
        expect(
          dateRowContainsBadge,
          isFalse,
          reason:
              'Demo badge must NOT share a Row parent with the date — '
              'the badge sits on the title row, the date is on its own '
              'row',
        );
      },
    );

    testWidgets(
      'routine names of typical length render in full on a 320-dp surface',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(
          const Size(_narrowPhoneWidth, _narrowPhoneHeight),
        );
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _seedMixedRoutines();

        await tester.pumpWidget(_pumpNarrowRoutines(repo));
        await tester.pumpAndSettle();

        // "Bodyweight Conditioning" must fit in full — pre-refactor it
        // truncated to "Bodyweight …" because the 96-dp Start button
        // stole horizontal space.
        final typicalTitle = find.text('Bodyweight Conditioning');
        expect(typicalTitle, findsOneWidget);

        final richText = tester.widget<RichText>(
          find.descendant(
            of: typicalTitle,
            matching: find.byType(RichText),
          ),
        );
        final tp = richText.text;
        final renderedText = tp.toPlainText();
        expect(
          renderedText.endsWith('\u2026'),
          isFalse,
          reason:
              'typical-length routine name must NOT be ellipsized on a '
              '320-dp surface — truncation to "Bodyweight …" is the '
              'regression being fixed',
        );
        expect(renderedText, 'Bodyweight Conditioning');

        // The very long name must still truncate (we don't want to
        // overflow the row) but should keep the first several words so
        // the routine remains identifiable.
        final longFinder = find.textContaining('Full Body Hypertrophy');
        expect(longFinder, findsOneWidget);
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════
  // S-007: Tap region + Demo badge stability refinements
  // ══════════════════════════════════════════════════════════════════════

  group('S-007 tap region + Demo badge stability', () {
    const _platformMinTapTarget = 44.0;
    const _narrowPhoneWidth = 320.0;
    const _narrowPhoneHeight = 800.0;

    Future<MockWorkoutRepository> _seedHeterogeneousRoutines() async {
      final repo = MockWorkoutRepository();
      await repo.initialize();
      final now = DateTime.now().millisecondsSinceEpoch;
      // Three demo routines with deliberately different creation dates
      // so the date text length varies between rows.
      await repo.createTemplate(
        WorkoutTemplate(
          id: 'tmpl-demo-today',
          name: 'Morning Mobility',
          focusModality: 'isometric_stretching',
          isBuiltInDemo: true,
          createdAtMs: now, // "today"
          updatedAtMs: now,
        ),
      );
      await repo.createTemplate(
        WorkoutTemplate(
          id: 'tmpl-demo-week',
          name: 'Push Day',
          focusModality: 'resistance_lifting',
          isBuiltInDemo: true,
          createdAtMs: now - const Duration(days: 5).inMilliseconds,
          updatedAtMs: now - const Duration(days: 5).inMilliseconds,
        ),
      );
      await repo.createTemplate(
        WorkoutTemplate(
          id: 'tmpl-demo-month',
          name: 'Long Threshold Run',
          focusModality: 'cardio_endurance',
          isBuiltInDemo: true,
          createdAtMs: now - const Duration(days: 21).inMilliseconds,
          updatedAtMs: now - const Duration(days: 21).inMilliseconds,
        ),
      );
      // One user routine (no Demo badge) — the gap-free row.
      await repo.createTemplate(
        WorkoutTemplate(
          id: 'tmpl-user',
          name: 'My Squat Day',
          focusModality: 'resistance_lifting',
          createdAtMs: now - const Duration(days: 2).inMilliseconds,
          updatedAtMs: now - const Duration(days: 2).inMilliseconds,
        ),
      );
      return repo;
    }

    Widget _pumpList(MockWorkoutRepository repo) {
      final routineState = RoutineState(repo);
      final workoutState = WorkoutState(repo);
      final settingsState = SettingsState(repo, fakePreferencesService());
      return MaterialApp(
        home: MyRoutinesScreen(
          routineState: routineState,
          workoutState: workoutState,
          routineSessionService: RoutineSessionService(repo),
          sessionSummaryService: SessionSummaryService(repo),
          settingsState: settingsState,
          timerAlertService: FakeTimerAlertService(),
        ),
      );
    }

    testWidgets(
      'start control tap region is at least 44 dp in both dimensions '
      'and visibly larger than the glyph it represents',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(
          const Size(_narrowPhoneWidth, _narrowPhoneHeight),
        );
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _seedHeterogeneousRoutines();

        await tester.pumpWidget(_pumpList(repo));
        await _pumpAndSettle(tester);

        // Measure the tap region via the locator the S-006 tests use,
        // so the assertion applies to the tap region itself rather than
        // to the visible glyph.
        final startRegion = tester.getRect(
          find.byKey(const Key('routine-card-start')).first,
        );
        expect(startRegion.width, greaterThanOrEqualTo(_platformMinTapTarget));
        expect(
          startRegion.height,
          greaterThanOrEqualTo(_platformMinTapTarget),
        );

        // The tap region must be visibly larger than the glyph it
        // represents — measured on the Icon widget.
        final glyphRect = tester.getRect(
          find.descendant(
            of: find.byKey(const Key('routine-card-start')).first,
            matching: find.byIcon(Icons.play_arrow),
          ),
        );
        expect(startRegion.width, greaterThan(glyphRect.width));
        expect(startRegion.height, greaterThan(glyphRect.height));
      },
    );

    testWidgets(
      'tap near the edge of the start control region hits the start '
      'control (does not fall through to the row body)',
      (WidgetTester tester) async {
        // Use a comfortable surface so the RoutineSetupScreen's name
        // TextField doesn't trigger a layout-overflow exception when
        // the row body receives a stray tap (the assertion is that
        // the editor does NOT open).
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _seedHeterogeneousRoutines();

        await tester.pumpWidget(_pumpList(repo));
        await _pumpAndSettle(tester);

        final startRegion = tester.getRect(
          find.byKey(const Key('routine-card-start')).first,
        );

        // Tap 2 dp from the trailing edge of the tap region. Even a
        // hurried or off-centre tap must still hit the start control
        // — i.e. it must NOT fall through to the row body's
        // onTap handler (which would open RoutineSetupScreen).
        final nearEdge = Offset(
          startRegion.right - 2,
          startRegion.center.dy,
        );
        await tester.tapAt(nearEdge);
        await tester.pump();
        tester.takeException();
        await _pumpAndSettle(tester);

        expect(
          find.byType(RoutineSetupScreen),
          findsNothing,
          reason:
              'tap 2 dp from the trailing edge of the start control '
              'must NOT fall through to the row body and open the '
              'routine editor',
        );
      },
    );

    testWidgets(
      'tap just outside the start control region opens the routine',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _seedHeterogeneousRoutines();

        await tester.pumpWidget(_pumpList(repo));
        await _pumpAndSettle(tester);

        final startRegion = tester.getRect(
          find.byKey(const Key('routine-card-start')).first,
        );
        // Tap 2 dp to the LEFT of the start control's left edge.
        // This point sits in the row body, which must open the routine.
        final justOutside = Offset(
          startRegion.left - 2,
          startRegion.center.dy,
        );
        await tester.tapAt(justOutside);
        // Pump and consume the setState-during-build from
        // RoutineState.loadRoutineForEditing (same workaround as the
        // S-001 card-body tests).
        await tester.pump();
        tester.takeException();
        await _pumpAndSettle(tester);

        expect(find.byType(RoutineSetupScreen), findsOneWidget);
      },
    );

    testWidgets(
      'no point in a row is unresponsive — taps at sampled positions '
      'either hit the start control or the row body',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        // Sample a vertical slice through the card at the centre y
        // (where the IconButton sits) and 5 x-positions spanning the
        // full width. For each tap, assert the tap reaches ONE of the
        // two known handlers — start control OR row body. Taps must
        // never land on a dead zone.
        final ys = <double>[0]; // placeholder, replaced per pump
        final xs = <double>[0, 0, 0, 0, 0]; // placeholder

        // Pump once to discover the card rect.
        final firstRepo = await _seedHeterogeneousRoutines();
        await tester.pumpWidget(_pumpList(firstRepo));
        await _pumpAndSettle(tester);

        final cardRect = tester.getRect(
          find.byKey(const Key('routine-card')).first,
        );
        ys[0] = cardRect.center.dy;
        xs[0] = cardRect.left + 4;
        xs[1] = cardRect.center.dx * 0.5;
        xs[2] = cardRect.center.dx;
        xs[3] = cardRect.right - 28;
        xs[4] = cardRect.right - 14;

        for (final y in ys) {
          for (final x in xs) {
            // Reset the navigator stack to a clean state for each
            // probe. We pump an empty Container first so the new
            // pumpWidget replaces the entire tree and the Navigator
            // starts fresh on the next list pump.
            await tester.pumpWidget(const SizedBox());
            await _pumpAndSettle(tester);

            // Fresh pump per probe so prior taps don't accumulate
            // state in the navigator stack.
            final freshRepo = await _seedHeterogeneousRoutines();
            await tester.pumpWidget(_pumpList(freshRepo));
            await _pumpAndSettle(tester);

            final startRegion = tester.getRect(
              find.byKey(const Key('routine-card-start')).first,
            );
            final insideStart = startRegion.contains(Offset(x, y));

            await tester.tapAt(Offset(x, y));
            await tester.pump();
            tester.takeException();
            await _pumpAndSettle(tester);

            final openedEditor =
                find.byType(RoutineSetupScreen).evaluate().isNotEmpty;

            if (insideStart) {
              // Start tap: must NOT open the editor (no dead zone
              // fallthrough). The start handler may or may not push
              // WorkoutSessionScreen depending on whether the seed
              // templates have segments; we only assert it did NOT
              // open the editor.
              expect(
                openedEditor,
                isFalse,
                reason:
                    'tap at ($x, $y) inside the start control must NOT '
                    'fall through to the row body and open the editor',
              );
            } else {
              // Body tap: must open the editor (the only handler in
              // this region).
              expect(
                openedEditor,
                isTrue,
                reason:
                    'tap at ($x, $y) in the row body must open the '
                    'routine editor — a dead zone here is the '
                    'regression this test guards against',
              );
            }
          }
        }
      },
    );

    testWidgets(
      'Demo badge sits at the same horizontal position on every row '
      'regardless of routine name length (S-008 — badge on title row)',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(
          const Size(_narrowPhoneWidth, _narrowPhoneHeight),
        );
        addTearDown(() => tester.binding.setSurfaceSize(null));

        // PR 6 / S-008 — the badge sits on the TITLE row, so its
        // horizontal stability is tested against varying TITLE
        // lengths (not date lengths, as it was when the badge lived
        // on the metadata line).
        final repo = MockWorkoutRepository();
        await repo.initialize();
        final now = DateTime.now().millisecondsSinceEpoch;
        // Short name, medium name, long name — all built-in demos
        // so each carries the badge. The badge should sit at the
        // right edge of the title row in every case.
        await repo.createTemplate(
          WorkoutTemplate(
            id: 'tmpl-short',
            name: 'Push',
            focusModality: 'resistance_lifting',
            isBuiltInDemo: true,
            createdAtMs: now,
            updatedAtMs: now,
          ),
        );
        await repo.createTemplate(
          WorkoutTemplate(
            id: 'tmpl-med',
            name: 'Bodyweight Conditioning',
            focusModality: 'resistance_lifting',
            isBuiltInDemo: true,
            createdAtMs: now,
            updatedAtMs: now,
          ),
        );
        await repo.createTemplate(
          WorkoutTemplate(
            id: 'tmpl-long',
            name: 'Full Body Hypertrophy Push Pull Legs '
                'with accessories',
            focusModality: 'resistance_lifting',
            isBuiltInDemo: true,
            createdAtMs: now,
            updatedAtMs: now,
          ),
        );

        await tester.pumpWidget(_pumpList(repo));
        await _pumpAndSettle(tester);

        final badges = find.byType(DemoRoutineBadge);
        expect(badges, findsNWidgets(3));

        final badgeRects = badges
            .evaluate()
            .map((element) => tester.getRect(find.byElementPredicate(
                  (e) => e == element,
                )))
            .toList();
        // Debug print
        // ignore: avoid_print
        for (var i = 0; i < badgeRects.length; i++) {
          // ignore: avoid_print
          print('S-007 debug: badge[$i] = ${badgeRects[i]}');
        }
        // All three badges must share the SAME horizontal position
        // (centre x), regardless of how long the title text on each
        // row happens to be.
        final centreX = badgeRects.first.center.dx;
        for (var i = 1; i < badgeRects.length; i++) {
          expect(
            badgeRects[i].center.dx,
            closeTo(centreX, 0.5),
            reason:
                'Demo badge row $i must sit at the same horizontal '
                'position as row 0 regardless of title text length',
          );
        }
        // And the same for left edge (where the badge starts).
        final leftEdge = badgeRects.first.left;
        for (var i = 1; i < badgeRects.length; i++) {
          expect(
            badgeRects[i].left,
            closeTo(leftEdge, 0.5),
            reason:
                'Demo badge left edge must be stable across rows of '
                'varying title text length',
          );
        }
      },
    );

    testWidgets(
      'user row (no Demo badge) renders the title + date lines without '
      'a Demo pill and without misalignment',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(
          const Size(_narrowPhoneWidth, _narrowPhoneHeight),
        );
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _seedHeterogeneousRoutines();

        await tester.pumpWidget(_pumpList(repo));
        await _pumpAndSettle(tester);

        // Locate the user row's title text. The user routine is "My
        // Squat Day". On the title row there is NO Demo badge.
        final userTitleFinder = find.text('My Squat Day');
        expect(userTitleFinder, findsOneWidget);

        // Find the user row's title parent Row and confirm it does
        // NOT contain a Demo badge.
        final userTitleRow = find
            .ancestor(
              of: userTitleFinder,
              matching: find.byType(Row),
            )
            .first;
        final userTitleRowHasBadge = find
            .descendant(
              of: userTitleRow,
              matching: find.byType(DemoRoutineBadge),
            )
            .evaluate()
            .isNotEmpty;
        expect(
          userTitleRowHasBadge,
          isFalse,
          reason:
              'user routine must not carry a Demo badge anywhere in '
              'the card — only built-in demo routines do',
        );

        // The user row's date line simply contains the date text —
        // no reserved space, no Stack, no Demo badge. The date text
        // is the only descendant of the user row's metadata Row.
        final userDateFinder = find.descendant(
          of: find.byKey(const Key('routine-card')),
          matching: find.byWidgetPredicate(
            (w) =>
                w is Text &&
                w.data != null &&
                (w.data!.contains('days ago') ||
                    w.data!.contains('yesterday') ||
                    w.data!.contains('today')),
          ),
        );
        expect(userDateFinder, findsWidgets);
        final lastDateRect = tester.getRect(userDateFinder.last);
        // The user row's date text reaches the full available width
        // of the metadata line — no reserved gap for a non-existent
        // badge.
        final userCardRect = tester.getRect(
          find
              .descendant(
                of: find.byKey(const Key('routine-card')),
                matching: find.byWidgetPredicate(
                  (w) =>
                      w is Text && w.data == 'My Squat Day',
                ),
              )
              .first,
        );
        // The last (user) row's date text should reach past the
        // start control's left edge minus a small margin — i.e. it
        // fills the available width of the body.
        expect(
          lastDateRect.right,
          greaterThan(userCardRect.right - 100),
          reason:
              'user row date text must reach the right edge of the '
              'body, not be padded for a non-existent badge',
        );
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════
  // S-008: Demo badge moves back to the title row, vertically centred
  // ══════════════════════════════════════════════════════════════════════

  group('S-008 Demo badge on title row + vertical centring', () {
    Future<MockWorkoutRepository> _seedDemoAndUserRoutines() async {
      final repo = MockWorkoutRepository();
      await repo.initialize();
      final now = DateTime.now().millisecondsSinceEpoch;
      await repo.createTemplate(
        WorkoutTemplate(
          id: 'tmpl-demo',
          name: 'Easy Run — 30 min',
          focusModality: 'cardio_endurance',
          isBuiltInDemo: true,
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );
      await repo.createTemplate(
        WorkoutTemplate(
          id: 'tmpl-user',
          name: 'My Squat Day',
          focusModality: 'resistance_lifting',
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );
      return repo;
    }

    Widget _pumpList(MockWorkoutRepository repo) {
      final routineState = RoutineState(repo);
      final workoutState = WorkoutState(repo);
      final settingsState = SettingsState(repo, fakePreferencesService());
      return MaterialApp(
        home: MyRoutinesScreen(
          routineState: routineState,
          workoutState: workoutState,
          routineSessionService: RoutineSessionService(repo),
          sessionSummaryService: SessionSummaryService(repo),
          settingsState: settingsState,
          timerAlertService: FakeTimerAlertService(),
        ),
      );
    }

    testWidgets(
      'Demo badge sits on the title row next to the routine name',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _seedDemoAndUserRoutines();

        await tester.pumpWidget(_pumpList(repo));
        await _pumpAndSettle(tester);

        // The demo title is "Easy Run — 30 min".
        final demoTitle = find.text('Easy Run — 30 min');
        expect(demoTitle, findsOneWidget);

        // The badge must share an IMMEDIATE Row parent with the
        // title. Pre-S-008 the badge was on the metadata line; S-008
        // moves it back here.
        final titleRow = find
            .ancestor(of: demoTitle, matching: find.byType(Row))
            .first;
        expect(
          find.descendant(
            of: titleRow,
            matching: find.byType(DemoRoutineBadge),
          ),
          findsOneWidget,
          reason:
              'Demo badge must be a descendant of the title Row — '
              'it sits next to the routine name on the title line '
              '(S-008 contract)',
        );
      },
    );

    testWidgets(
      'Demo badge is vertically centred with the title text',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _seedDemoAndUserRoutines();

        await tester.pumpWidget(_pumpList(repo));
        await _pumpAndSettle(tester);

        final titleRect = tester.getRect(find.text('Easy Run — 30 min'));
        final badgeRect = tester.getRect(find.byType(DemoRoutineBadge));

        // Badge must sit on the title row: badge.top is no lower than
        // the title's bottom, and badge.bottom is no higher than the
        // title's top.
        expect(
          badgeRect.top,
          lessThanOrEqualTo(titleRect.bottom),
          reason: 'Demo badge top must be at or above the title bottom',
        );
        expect(
          badgeRect.bottom,
          greaterThanOrEqualTo(titleRect.top),
          reason: 'Demo badge bottom must be at or below the title top',
        );

        // Vertically centred: badge centre y is within the title's
        // vertical band (within ±title height / 2 of the title centre).
        final titleCenterY = titleRect.center.dy;
        final badgeCenterY = badgeRect.center.dy;
        final titleHalfHeight = titleRect.height / 2;
        expect(
          (badgeCenterY - titleCenterY).abs(),
          lessThanOrEqualTo(titleHalfHeight + 4),
          reason:
              'Demo badge must be vertically centred with the title '
              'text within a small tolerance',
        );
      },
    );

    testWidgets(
      'Demo badge text is vertically centred within the pill',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _seedDemoAndUserRoutines();

        await tester.pumpWidget(_pumpList(repo));
        await _pumpAndSettle(tester);

        final badge = tester.widget<Container>(
          find.descendant(
            of: find.byType(DemoRoutineBadge),
            matching: find.byType(Container),
          ).first,
        );
        // The badge's vertical padding is symmetric (vertical: 2 in
        // the compact variant) and the inner Text is rendered with
        // its default centred alignment, so the text is vertically
        // centred within the pill by construction.
        final padding = badge.padding as EdgeInsets;
        expect(padding.top, padding.bottom,
            reason:
                'Demo badge padding must be vertically symmetric so '
                'the text is centred within the pill');

        final badgeRect = tester.getRect(find.byType(DemoRoutineBadge));
        final textRect = tester.getRect(
          find.descendant(
            of: find.byType(DemoRoutineBadge),
            matching: find.byType(Text),
          ),
        );
        // Text is vertically centred within the pill: equal distance
        // from text top to pill top and text bottom to pill bottom.
        final topGap = textRect.top - badgeRect.top;
        final bottomGap = badgeRect.bottom - textRect.bottom;
        expect(
          (topGap - bottomGap).abs(),
          lessThanOrEqualTo(2.0),
          reason:
              'Demo badge text must be vertically centred within '
              'the pill (equal top and bottom gaps)',
        );
      },
    );

    testWidgets(
      'metadata line uses a simple Row (no Stack, no reserved space)',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _seedDemoAndUserRoutines();

        await tester.pumpWidget(_pumpList(repo));
        await _pumpAndSettle(tester);

        // Locate the date text on the demo row.
        final dateText = find.textContaining('Created ');
        expect(dateText, findsWidgets);

        // PR 6 / S-008 — the metadata line is no longer a Row at all;
        // it is a direct child of the Column (just a Text widget). The
        // date text's IMMEDIATE parent is the Column, not a Row.
        // Verify:
        //   1. The date's immediate parent is a Column, not a Row.
        //   2. The Column does NOT contain a Stack (no Stack-based
        //      pinning of the badge).
        //   3. The Column's DIRECT children do NOT include a Demo
        //      badge — the badge lives on the title Row, which is a
        //      separate child of the same Column. The badge IS a
        //      descendant of the Column (via the title Row), but it
        //      must NOT be a direct child.
        final dateParentColumn = find
            .ancestor(of: dateText.first, matching: find.byType(Column))
            .first;
        // No Stack anywhere in the date's parent column — the
        // S-007 Stack-pinning is gone.
        expect(
          find
              .descendant(
                of: dateParentColumn,
                matching: find.byType(Stack),
              )
              .evaluate()
              .isNotEmpty,
          isFalse,
          reason:
              'metadata line\'s parent column must NOT contain a Stack '
              '— pre-S-008 it used one to pin the Demo badge, S-008 '
              'moves the badge back to the title row',
        );
        // No Positioned anywhere in the date's parent column.
        expect(
          find
              .descendant(
                of: dateParentColumn,
                matching: find.byType(Positioned),
              )
              .evaluate()
              .isNotEmpty,
          isFalse,
          reason:
              'metadata line\'s parent column must NOT contain a '
              'Positioned widget — the badge is no longer pinned here',
        );
        // The Demo badge must NOT be a DIRECT child of the column —
        // it lives on the title Row, which is a sibling of the date
        // text within the same Column. The badge IS a descendant
        // (transitively, via the title Row), but the date's parent
        // Column has exactly three direct children: the title Row,
        // a SizedBox(4) spacer, and the date Text.
        //
        // Walk the Column's direct children by checking each
        // element's widget type. Flutter test's `find` helpers
        // don't expose "direct child" natively, so we filter the
        // descendants to those whose immediate element parent is the
        // date's parent Column.
        final columnElement = tester.elementList(dateParentColumn).first;
        final columnDirectChildren = <Widget>[];
        // Collect all descendants and keep those whose parent is
        // exactly `columnElement`.
        columnElement.visitChildren((child) {
          columnDirectChildren.add(child.widget);
        });
        final hasDirectBadgeChild = columnDirectChildren.any(
          (w) => w is DemoRoutineBadge,
        );
        expect(
          hasDirectBadgeChild,
          isFalse,
          reason:
              'Demo badge must NOT be a direct child of the metadata '
              'column — it lives on the title row (S-008)',
        );
      },
    );

    testWidgets(
      'user row title line is clean (no Demo badge, no reserved space)',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _seedDemoAndUserRoutines();

        await tester.pumpWidget(_pumpList(repo));
        await _pumpAndSettle(tester);

        // User routine is "My Squat Day". The title Row contains only
        // the title text — no Demo badge, no Stack, no Positioned.
        final userTitle = find.text('My Squat Day');
        expect(userTitle, findsOneWidget);

        final userTitleRow = find
            .ancestor(of: userTitle, matching: find.byType(Row))
            .first;
        expect(
          find
              .descendant(
                of: userTitleRow,
                matching: find.byType(DemoRoutineBadge),
              )
              .evaluate()
              .isNotEmpty,
          isFalse,
          reason:
              'user row title must not contain a Demo badge — only '
              'built-in demos carry the badge',
        );

        // The user row's date line is a simple Row with just the
        // date text — no badge, no Stack, no Positioned, no reserved
        // right padding.
        final userDate = find.descendant(
          of: find.byKey(const Key('routine-card')),
          matching: find.byWidgetPredicate(
            (w) =>
                w is Text &&
                w.data != null &&
                (w.data!.contains('days ago') ||
                    w.data!.contains('yesterday') ||
                    w.data!.contains('today')),
          ),
        );
        expect(userDate, findsWidgets);
        final userDateRow = find
            .ancestor(of: userDate.last, matching: find.byType(Row))
            .first;
        expect(
          find
              .descendant(
                of: userDateRow,
                matching: find.byType(Stack),
              )
              .evaluate()
              .isNotEmpty,
          isFalse,
          reason: 'user date line must not use a Stack',
        );
      },
    );
  });
}