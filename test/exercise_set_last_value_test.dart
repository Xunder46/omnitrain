// Widget-level integration tests for the exercise-set-last-value feature
// (June 2026, exercise-set-last-value-plan.md).
//
// Verifies that when the user taps "+ Add Set" in the session detail view,
// the new entry's `previousValues` carry forward from the previous entry.
//
// Storage-layer round-trip is pinned separately in `test/state_test.dart`
// (group: "exercise previousValues carry-forward"); this file drives the
// full screen path so a regression in `_addSet`'s `previousValues` builder
// is caught.
//
// The integration test reads the entry summary view directly
// (`workoutState.getExercisesWithEntries()`) after the screen rebuilds —
// not the `InlineMetricEditor`'s `currentValue` — because the screen
// body only refreshes its in-memory `_exercises` cache when an
// explicit `_loadExercises` call fires (e.g. after `addEntry`,
// `deleteEntry`, `_updateMetricValue`). This mirrors the production
// flow: when the user opens the popup, edits, and closes, the
// underlying `_updateMetricValue` → `updateEntryValue` → `_loadExercises`
// chain refreshes `_exercises`; in this test we drive the same end
// state by calling `addEntry` directly and pumping.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/routine_session_service.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

SettingsState _buildSettings(MockWorkoutRepository repo) {
  return SettingsState(repo, FakePreferencesService());
}

Future<({
  WorkoutState workoutState,
  RoutineState routineState,
  SessionSummaryService sessionSummaryService,
  SettingsState settingsState,
  String exerciseName,
})> _buildSessionDeps({
  required String effortKind,
}) async {
  final repo = await _freshRepo();
  final workoutState = WorkoutState(repo);
  final routineState = RoutineState(repo);
  final sessionSummaryService = SessionSummaryService(repo);
  final settingsState = _buildSettings(repo);
  await settingsState.initialize();

  await workoutState.createNewSession(modality: 'resistance_lifting');
  final exercises = await repo.getExercises();
  final exercise = exercises.firstWhere(
    (e) =>
        e.capabilities.contains('sets') &&
        e.capabilities.contains('load') &&
        e.capabilities.contains('reps'),
    orElse: () => exercises.first,
  );
  await workoutState.addExerciseToSession(
    exercise,
    effortKindOverride: effortKind,
  );
  return (
    workoutState: workoutState,
    routineState: routineState,
    sessionSummaryService: sessionSummaryService,
    settingsState: settingsState,
    exerciseName: exercise.name,
  );
}

Future<void> _openSessionDetail(
  WidgetTester tester,
  String exerciseName,
) async {
  await tester.pumpAndSettle();
  final labelFinder = find.text(exerciseName).first;
  await tester.ensureVisible(labelFinder);
  final rowInkWell = tester.widget<InkWell>(
    find.ancestor(of: labelFinder, matching: find.byType(InkWell)).first,
  );
  expect(rowInkWell.onTap, isNotNull);
  rowInkWell.onTap!.call();
  await tester.pumpAndSettle();
}

Future<void> _tapAddSet(WidgetTester tester) async {
  // The `Icon(Icons.add)` button to the right of the "Set N of M"
  // label is the "+ Add Set" affordance. The underlying `InkWell.onTap`
  // invokes `_addSet`. We tap the InkWell directly via the tooltip
  // finder; `find.byTooltip` returns the Tooltip widget itself, so
  // we look up its child InkWell and call `onTap` directly to avoid
  // hit-test issues at small surface sizes.
  final tooltipFinder = find.byTooltip('Add set');
  expect(tooltipFinder, findsOneWidget);
  await tester.ensureVisible(tooltipFinder);
  await tester.pumpAndSettle();
  final inkWellFinder = find.descendant(
    of: tooltipFinder,
    matching: find.byType(InkWell),
  );
  expect(inkWellFinder, findsOneWidget);
  final inkWell = tester.widget<InkWell>(inkWellFinder);
  expect(inkWell.onTap, isNotNull,
      reason: 'Add-set InkWell must have an onTap');
  inkWell.onTap!.call();
  await tester.pumpAndSettle();
}

void main() {
  group(
    'WorkoutSessionScreen — exercise set last value (S-001 / S-002 / S-003)',
    () {
      testWidgets(
        'S-001: + Add Set in resistance detail pre-fills reps + weight '
        'from the previous set',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(400, 1200));
          addTearDown(() => tester.binding.setSurfaceSize(null));

          final deps = await _buildSessionDeps(effortKind: 'set');

          await tester.pumpWidget(
            MaterialApp(
              home: WorkoutSessionScreen(
                workoutState: deps.workoutState,
                routineState: deps.routineState,
                sessionSummaryService: deps.sessionSummaryService,
                timerAlertService: FakeTimerAlertService(),
                settingsState: deps.settingsState,
              ),
            ),
          );
          await _openSessionDetail(tester, deps.exerciseName);

          // Set 1: simulate the user changing values via the popup
          // (which calls _updateMetricValue → updateEntryValue).
          // In this test we call `updateEntryValue` directly and
          // then pump the screen.
          final effortId =
              deps.workoutState.getExercisesWithEntries().first['id'] as String;
          await deps.workoutState.updateEntryValue(effortId, 0, 'reps', 8);
          await deps.workoutState.updateEntryValue(effortId, 0, 'weight', 80.0);
          await tester.pumpAndSettle();

          // Sanity: entry 0's stored values are reflected in the
          // summary view (the source of truth for the
          // carry-forward builder).
          final entriesBefore =
              deps.workoutState.getExercisesWithEntries().first['entries']
                  as List;
          expect((entriesBefore[0] as Map)['reps'], 8);
          expect((entriesBefore[0] as Map)['weight'], 80.0);

          // Tap + Add Set. The screen calls _addSet, which reads
          // entries.last from the cached _exercises summary,
          // builds previousValues, and calls
          // workoutState.addEntry(effortId, previousValues: ...).
          // The new entry's stored values reflect the
          // carry-forward.
          await _tapAddSet(tester);

          // After addSet, the cached _exercises list has 2
          // entries. The carry-forward contract requires entry[1]
          // to mirror entry[0]'s stored values (8 / 80.0).
          final entriesAfter =
              deps.workoutState.getExercisesWithEntries().first['entries']
                  as List;
          expect(entriesAfter, hasLength(2));
          final entry1 = entriesAfter[1] as Map<String, dynamic>;
          expect(entry1['reps'], 8,
              reason:
                  'S-001: second set reps must carry forward from set 1');
          expect(entry1['weight'], 80.0,
              reason:
                  'S-001: second set weight must carry forward from set 1');
        },
      );

      testWidgets(
        'S-003: editing the pre-filled values for an unsaved set does '
        'NOT mutate the prior set\'s stored values',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(400, 1200));
          addTearDown(() => tester.binding.setSurfaceSize(null));

          final deps = await _buildSessionDeps(effortKind: 'set');
          final effortId =
              deps.workoutState.getExercisesWithEntries().first['id'] as String;

          await tester.pumpWidget(
            MaterialApp(
              home: WorkoutSessionScreen(
                workoutState: deps.workoutState,
                routineState: deps.routineState,
                sessionSummaryService: deps.sessionSummaryService,
                timerAlertService: FakeTimerAlertService(),
                settingsState: deps.settingsState,
              ),
            ),
          );
          await _openSessionDetail(tester, deps.exerciseName);

          // Set 1: 10 reps × 60 kg.
          await deps.workoutState.updateEntryValue(effortId, 0, 'reps', 10);
          await deps.workoutState.updateEntryValue(effortId, 0, 'weight', 60.0);
          await tester.pumpAndSettle();

          // Add set 2 (carries forward 10 / 60.0 via the
          // _addSet → addEntry(previousValues) path).
          await _tapAddSet(tester);

          // Verify carry-forward happened (S-001's corollary).
          final entriesAfterAdd =
              deps.workoutState.getExercisesWithEntries().first['entries']
                  as List;
          expect(entriesAfterAdd, hasLength(2));
          final entry1 = entriesAfterAdd[1] as Map<String, dynamic>;
          expect(entry1['reps'], 10);
          expect(entry1['weight'], 60.0);

          // Now: simulate the user editing set 2 in the popup to
          // 8 / 80.0 BEFORE logging (an unsaved edit). The
          // carry-forward contract says the prior set's stored
          // values (entry[0]) must NOT change.
          await deps.workoutState.updateEntryValue(effortId, 1, 'reps', 8);
          await deps.workoutState.updateEntryValue(effortId, 1, 'weight', 80.0);
          await tester.pumpAndSettle();

          // Re-read the entries.
          final entriesAfterEdit =
              deps.workoutState.getExercisesWithEntries().first['entries']
                  as List;
          final entry0AfterEdit =
              entriesAfterEdit[0] as Map<String, dynamic>;
          expect(entry0AfterEdit['reps'], 10,
              reason: 'S-003: prior set\'s reps must not change on unsaved edit');
          expect(entry0AfterEdit['weight'], 60.0,
              reason:
                  'S-003: prior set\'s weight must not change on unsaved edit');
          // And entry 1 reflects the unsaved edit.
          final entry1AfterEdit =
              entriesAfterEdit[1] as Map<String, dynamic>;
          expect(entry1AfterEdit['reps'], 8);
          expect(entry1AfterEdit['weight'], 80.0);
        },
      );
    },
  );
}
