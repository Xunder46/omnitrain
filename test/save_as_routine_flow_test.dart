// Plan 279 P3b — the new Save as Routine flow, driven from the session
// summary screen (scenarios S-27910, S-27913, S-27914 and the focus-modality
// half of S-27907 of
// `docs/plans/2026-11-19-279-save-as-routine-opens-editor-plan/...`).
// Mock repository only, `testWidgets` only; everything is seeded BEFORE the
// first pump (no Hive, no real `Future.delayed`). Harness blocks copied from
// the retired sheet test: the pushed-route host (so Done has a first route to
// pop to), the overflow-menu helper, the editor name-field finder and the
// header back-arrow finder from `test/routine_setup_from_session_test.dart`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/modality_display.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/routine/routine_setup_screen.dart';
import 'package:omnitrain/features/session/session_summary_screen.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

typedef _Deps = ({
  MockWorkoutRepository repo,
  WorkoutState workoutState,
  RoutineState routineState,
  SettingsState settingsState,
});

Future<_Deps> _buildDeps() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  final routineState = RoutineState(repo)..setAutosaveEnabled(false);
  final workoutState = WorkoutState(repo);
  final settingsState = SettingsState(repo, fakePreferencesService());
  await settingsState.setShowFeelingSurvey(false);
  return (
    repo: repo,
    workoutState: workoutState,
    routineState: routineState,
    settingsState: settingsState,
  );
}

/// The two seed exercises that can carry reps over sets, by the capability
/// predicate the brief names.
Future<(Exercise, Exercise)> _pickSetExercises(
  MockWorkoutRepository repo,
) async {
  final candidates = (await repo.getExercises())
      .where(
        (e) =>
            e.capabilities.contains('reps') && e.capabilities.contains('sets'),
      )
      .toList();
  expect(
    candidates.length,
    greaterThanOrEqualTo(2),
    reason: 'the seed catalog must hold two set-capable exercises',
  );
  return (candidates[0], candidates[1]);
}

/// A fresh resistance session with block `Upper` holding the first set
/// exercise and block `Cardio` holding the second. The feeling is set so the
/// automatic rating sheet never opens over the summary.
Future<(_Deps, Exercise, Exercise, String)> _seedSessionWithBlocks() async {
  final deps = await _buildDeps();
  await deps.workoutState.createNewSession(modality: 'resistance_lifting');
  final (first, second) = await _pickSetExercises(deps.repo);
  final firstEffort = await deps.workoutState.addExerciseToSession(first);
  final secondEffort = await deps.workoutState.addExerciseToSession(second);
  final upper = await deps.workoutState.addSessionBlock(name: 'Upper');
  await deps.workoutState.assignEffortToBlock(firstEffort, upper);
  final cardio = await deps.workoutState.addSessionBlock(name: 'Cardio');
  await deps.workoutState.assignEffortToBlock(secondEffort, cardio);
  await deps.workoutState.updateSessionFeeling(
    deps.workoutState.currentSession!.id,
    3,
  );
  return (deps, first, second, deps.workoutState.currentSession!.id);
}

/// A fresh session with no exercise at all (feeling set, so no sheet).
Future<_Deps> _seedSessionWithoutExercise() async {
  final deps = await _buildDeps();
  await deps.workoutState.createNewSession(modality: 'resistance_lifting');
  await deps.workoutState.updateSessionFeeling(
    deps.workoutState.currentSession!.id,
    3,
  );
  return deps;
}

/// A finished resistance session with the Upper/Cardio blocks, stored once
/// and then loaded the way the calendar loads it.
Future<
  (
    MockWorkoutRepository,
    WorkoutState,
    RoutineState,
    SettingsState,
    CalendarState,
  )
>
_seedHistoricalSessionWithBlocks() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  final live = WorkoutState(repo);
  await live.createNewSession(modality: 'resistance_lifting');
  final sessionId = live.currentSession!.id;
  final (first, second) = await _pickSetExercises(repo);
  final firstEffort = await live.addExerciseToSession(first);
  final secondEffort = await live.addExerciseToSession(second);
  final upper = await live.addSessionBlock(name: 'Upper');
  await live.assignEffortToBlock(firstEffort, upper);
  final cardio = await live.addSessionBlock(name: 'Cardio');
  await live.assignEffortToBlock(secondEffort, cardio);
  await live.endSession(writeToHealth: false);

  final workoutState = WorkoutState(repo);
  await workoutState.loadHistoricalSession(sessionId);
  final routineState = RoutineState(repo)..setAutosaveEnabled(false);
  final settingsState = SettingsState(repo, fakePreferencesService());
  await settingsState.setShowFeelingSurvey(false);
  final calendarState = CalendarState(repo);
  await calendarState.init();
  return (repo, workoutState, routineState, settingsState, calendarState);
}

/// `<date>` exactly as `_formatDate` in `session_summary_screen.dart`
/// produces it from the session's `startedAtMs` day.
String _summaryDateLabel(int startedAtMs) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final date = DateTime.fromMillisecondsSinceEpoch(startedAtMs);
  return '${months[date.month - 1]} ${date.day}';
}

/// The name the summary hands the editor: `<Modality> - <date>`.
String _expectedDraftName(WorkoutState workoutState) {
  final session = workoutState.currentSession!;
  return '${ModalityDisplay.getName(session.modality)}'
      ' - ${_summaryDateLabel(session.startedAtMs)}';
}

/// Opens the summary as a pushed route so Done has a first route to pop to.
Future<void> _pumpSummary(
  WidgetTester tester,
  MockWorkoutRepository repo,
  WorkoutState workoutState,
  RoutineState routineState,
  SettingsState settingsState, {
  bool openedFromCalendar = false,
  CalendarState? calendarState,
}) async {
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
                    workoutState: workoutState,
                    routineState: routineState,
                    sessionSummaryService: SessionSummaryService(repo),
                    settingsState: settingsState,
                    timerAlertService: FakeTimerAlertService(),
                    openedFromCalendar: openedFromCalendar,
                    originatingCalendarState: calendarState,
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

Future<void> _pumpDeps(WidgetTester tester, _Deps deps) => _pumpSummary(
  tester,
  deps.repo,
  deps.workoutState,
  deps.routineState,
  deps.settingsState,
);

Future<void> _openSaveAsRoutine(WidgetTester tester) async {
  await tester.tap(find.byType(PopupMenuButton<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Save as Routine'));
  await tester.pumpAndSettle();
}

/// Finds the editor's name TextField by its labelText (the label is not a
/// descendant Text of the field, so `widgetWithText` is not reliable for it).
Finder _nameField() => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == 'Routine Name',
);

/// The OmniBackHeader back arrow of the EDITOR — scoped to the
/// RoutineSetupScreen so the summary's own back arrow under it is never hit.
Finder _editorBackArrow() => find.descendant(
  of: find.byType(RoutineSetupScreen),
  matching: find.byWidgetPredicate(
    (w) =>
        w is IconButton &&
        w.icon is Icon &&
        (w.icon as Icon).icon == Icons.arrow_back,
  ),
);

void main() {
  testWidgets(
    'S-27910 save-as-routine opens the editor and Save returns to the '
    'summary with the routine stored',
    (tester) async {
      final (deps, _, _, _) = await _seedSessionWithBlocks();
      final beforeIds = (await deps.repo.getTemplates())
          .map((t) => t.id)
          .toList();
      final expectedName = _expectedDraftName(deps.workoutState);

      await _pumpDeps(tester, deps);
      await _openSaveAsRoutine(tester);

      expect(
        find.text('Create Routine'),
        findsOneWidget,
        reason: 'S-27910 the editor is showing',
      );
      expect(
        tester.widget<TextField>(_nameField()).controller!.text,
        expectedName,
        reason: 'S-27910 the name field holds `<Modality> - <date>`',
      );
      expect(
        find.text('Upper'),
        findsAtLeastNWidgets(1),
        reason: 'S-27910 the first block name is on screen',
      );
      expect(
        find.text('Cardio'),
        findsAtLeastNWidgets(1),
        reason: 'S-27910 the second block name is on screen',
      );
      final afterOpen = await deps.repo.getTemplates();
      expect(
        afterOpen.length,
        beforeIds.length,
        reason: 'S-27910 opening stores no template',
      );
      expect(
        afterOpen.map((t) => t.id),
        unorderedEquals(beforeIds),
        reason: 'S-27910 the stored template ids are unchanged',
      );

      await tester.tap(find.text('Save'));
      await tester.pump();
      // During the pop the message renders twice (editor route + summary
      // route); at least one copy guards it.
      expect(
        find.text('Routine saved successfully'),
        findsWidgets,
        reason: 'S-27910 the editor showed its save message',
      );
      await tester.pumpAndSettle();

      expect(
        find.byType(RoutineSetupScreen),
        findsNothing,
        reason: 'S-27910 the editor is gone after the save',
      );
      expect(
        find.text('Create Routine'),
        findsNothing,
        reason: 'S-27910 the editor title is absent after the save',
      );
      expect(
        find.text('Save as Routine'),
        findsNothing,
        reason: 'S-27910 the overflow menu is closed again',
      );
      expect(
        find.byType(PopupMenuButton<String>),
        findsOneWidget,
        reason: 'S-27910 the SUMMARY is showing again',
      );

      final templates = await deps.repo.getTemplates();
      expect(
        templates.length,
        beforeIds.length + 1,
        reason: 'S-27910 exactly one new routine was stored',
      );
      final template = templates.single;
      expect(
        template.name,
        expectedName,
        reason: 'S-27910 the stored routine carries the draft name',
      );
      final segments = await deps.repo.getTemplateSegments(template.id);
      expect(
        segments.map((s) => s.name).toList(),
        ['Upper', 'Cardio'],
        reason: 'S-27910 one segment per block, in block order',
      );
      expect(
        segments.map((s) => s.orderIndex).toList(),
        [0, 1],
        reason: 'S-27910 the segments are ordered 0, 1',
      );
    },
  );

  testWidgets('S-27910b Done still ends the workout after saving a routine', (
    tester,
  ) async {
    final (deps, _, _, sessionId) = await _seedSessionWithBlocks();
    await _pumpDeps(tester, deps);
    await _openSaveAsRoutine(tester);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // The save message's SnackBar sits over the bottom CTA until its
    // duration runs out; expire it before tapping Done.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(
      find.byType(PopupMenuButton<String>),
      findsOneWidget,
      reason: 'S-27910b the summary is showing again after the save',
    );

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(
      find.text('Open summary'),
      findsOneWidget,
      reason: 'S-27910b the summary popped to the host',
    );
    final stored = await deps.repo.getSession(sessionId);
    expect(
      stored!.endedAtMs,
      isNotNull,
      reason: 'S-27910b Done still ended the workout',
    );
  });

  testWidgets(
    'S-27910c back without edits returns to the summary; with edits it asks '
    'first and Discard stores nothing',
    (tester) async {
      final deps = await _buildDeps();
      await deps.workoutState.createNewSession(modality: 'resistance_lifting');
      final (first, _) = await _pickSetExercises(deps.repo);
      await deps.workoutState.addExerciseToSession(first);
      await deps.workoutState.updateSessionFeeling(
        deps.workoutState.currentSession!.id,
        3,
      );
      await _pumpDeps(tester, deps);

      // Clean exit: no edits, no dialog, nothing stored.
      await _openSaveAsRoutine(tester);
      expect(
        find.text('Create Routine'),
        findsOneWidget,
        reason: 'S-27910c the editor is open',
      );
      await tester.tap(_editorBackArrow());
      await tester.pumpAndSettle();

      expect(
        find.byType(RoutineSetupScreen),
        findsNothing,
        reason: 'S-27910c the editor popped',
      );
      expect(
        find.byType(PopupMenuButton<String>),
        findsOneWidget,
        reason: 'S-27910c the summary is showing again',
      );
      expect(
        find.byType(AlertDialog),
        findsNothing,
        reason: 'S-27910c no dialog without an edit',
      );
      expect(
        await deps.repo.getTemplates(),
        isEmpty,
        reason: 'S-27910c backing out stored nothing',
      );

      // Guarded exit: after a rename the dialog names the summary.
      await _openSaveAsRoutine(tester);
      await tester.enterText(_nameField(), 'Renamed draft');
      await tester.pumpAndSettle();
      await tester.tap(_editorBackArrow());
      await tester.pumpAndSettle();

      expect(
        find.text('Unsaved changes'),
        findsOneWidget,
        reason: 'S-27910c the unsaved-changes dialog shows after an edit',
      );
      expect(
        find.textContaining('return to the summary'),
        findsOneWidget,
        reason: 'S-27910c the dialog names the summary',
      );

      await tester.tap(find.byKey(const Key('routine-edit-unsaved-discard')));
      await tester.pumpAndSettle();

      expect(
        find.byType(RoutineSetupScreen),
        findsNothing,
        reason: 'S-27910c Discard popped the editor',
      );
      expect(
        find.byType(PopupMenuButton<String>),
        findsOneWidget,
        reason: 'S-27910c the summary is showing again',
      );
      expect(
        await deps.repo.getTemplates(),
        isEmpty,
        reason: 'S-27910c Discard stored nothing',
      );
    },
  );

  testWidgets(
    'S-27914 a session with no exercise shows a message and opens no editor',
    (tester) async {
      final deps = await _seedSessionWithoutExercise();
      await _pumpDeps(tester, deps);

      await _openSaveAsRoutine(tester);

      expect(
        find.text('This workout has no exercises to save'),
        findsOneWidget,
        reason: 'S-27914 the no-exercises message is shown',
      );
      expect(
        find.text('Create Routine'),
        findsNothing,
        reason: 'S-27914 the editor did not open',
      );
      expect(
        await deps.repo.getTemplates(),
        isEmpty,
        reason: 'S-27914 nothing was stored',
      );
    },
  );

  testWidgets('S-27913 a historical summary opens the editor with its blocks', (
    tester,
  ) async {
    final (repo, workoutState, routineState, settingsState, calendarState) =
        await _seedHistoricalSessionWithBlocks();

    await _pumpSummary(
      tester,
      repo,
      workoutState,
      routineState,
      settingsState,
      openedFromCalendar: true,
      calendarState: calendarState,
    );
    await _openSaveAsRoutine(tester);

    expect(
      find.text('Create Routine'),
      findsOneWidget,
      reason: 'S-27913 the editor opened from the historical summary',
    );
    expect(
      find.text('Upper'),
      findsAtLeastNWidgets(1),
      reason: 'S-27913 the first block name is on screen',
    );
    expect(
      find.text('Cardio'),
      findsAtLeastNWidgets(1),
      reason: 'S-27913 the second block name is on screen',
    );
  });

  testWidgets(
    'S-27907c a resistance session shows its modality in Focus Modality',
    (tester) async {
      final (deps, _, _, _) = await _seedSessionWithBlocks();
      await _pumpDeps(tester, deps);
      await _openSaveAsRoutine(tester);

      final dropdown = tester.widget<DropdownButtonFormField<String?>>(
        find.byType(DropdownButtonFormField<String?>),
      );
      expect(
        dropdown.initialValue,
        'resistance_lifting',
        reason: 'S-27907c the dropdown value is the session modality',
      );
      expect(
        find.text('Resistance / Lifting'),
        findsOneWidget,
        reason:
            'S-27907c the displayed label is the app label for '
            'resistance_lifting',
      );
    },
  );

  testWidgets(
    'S-27907c a free session shows the not-set label in Focus Modality',
    (tester) async {
      final deps = await _buildDeps();
      await deps.workoutState.createNewSession();
      final exercises = await deps.repo.getExercises();
      await deps.workoutState.addExerciseToSession(exercises.first);
      await deps.workoutState.updateSessionFeeling(
        deps.workoutState.currentSession!.id,
        3,
      );
      await _pumpDeps(tester, deps);
      await _openSaveAsRoutine(tester);

      expect(
        find.text('Create Routine'),
        findsOneWidget,
        reason: 'S-27907c the editor opened for the free session',
      );
      final dropdown = tester.widget<DropdownButtonFormField<String?>>(
        find.byType(DropdownButtonFormField<String?>),
      );
      expect(
        dropdown.initialValue,
        isNull,
        reason: 'S-27907c the free session has no focus modality',
      );
      expect(
        find.text('Mixed / Not set'),
        findsOneWidget,
        reason: 'S-27907c the none label is displayed',
      );
      expect(
        tester.widget<TextField>(_nameField()).controller!.text,
        'Free Training - ${_summaryDateLabel(deps.workoutState.currentSession!.startedAtMs)}',
        reason: 'S-27907c the name names the Free Training modality',
      );
    },
  );
}
