// Plan 269: the live workout's exercise list has a Remove exercise action on
// each tile, so a whole exercise goes without deleting its sets one by one.
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

typedef _Deps = ({
  WorkoutState workoutState,
  RoutineState routineState,
  SettingsState settingsState,
  MockWorkoutRepository repo,
  List<({String id, String name})> efforts,
});

/// A live workout holding two set exercises, the first with 3 sets.
Future<_Deps> _deps() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  final workoutState = WorkoutState(repo);
  final routineState = RoutineState(repo);
  final settingsState = SettingsState(repo, FakePreferencesService());
  await settingsState.initialize();
  await workoutState.createNewSession(modality: 'resistance_lifting');
  final exercises = (await repo.getExercises())
      .where(
        (e) =>
            e.capabilities.contains('sets') &&
            e.capabilities.contains('load') &&
            e.capabilities.contains('reps'),
      )
      .take(2)
      .toList();
  final efforts = <({String id, String name})>[];
  for (final e in exercises) {
    final id = await workoutState.addExerciseToSession(e);
    efforts.add((id: id, name: e.name));
  }
  await workoutState.addEntry(efforts.first.id);
  await workoutState.addEntry(efforts.first.id);
  return (
    workoutState: workoutState,
    routineState: routineState,
    settingsState: settingsState,
    repo: repo,
    efforts: efforts,
  );
}

Future<void> _pump(WidgetTester tester, _Deps d) async {
  await tester.binding.setSurfaceSize(const Size(400, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: WorkoutSessionScreen(
        workoutState: d.workoutState,
        routineState: d.routineState,
        sessionSummaryService: SessionSummaryService(d.repo),
        timerAlertService: FakeTimerAlertService(),
        settingsState: d.settingsState,
      ),
    ),
  );
  for (var i = 0; i < 10; i++) {
    await tester.pump();
    if (find.text(d.efforts.first.name).evaluate().isNotEmpty) return;
  }
  fail('the exercise list did not render');
}

List<SegmentEffort> _efforts(_Deps d) => [
  for (final segment in d.workoutState.segments)
    ...d.workoutState.getEffortsForSegment(segment.id),
];

Future<void> _openRemove(WidgetTester tester, String effortId) async {
  await tester.tap(find.byKey(Key('exercise_tile_menu_$effortId')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.byKey(Key('exercise_tile_remove_$effortId')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('S-26901 Remove exercise asks first, and Cancel keeps it', (
    tester,
  ) async {
    final d = await _deps();
    await _pump(tester, d);
    final first = d.efforts.first;

    await _openRemove(tester, first.id);
    expect(find.text('Remove Exercise?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('exercise-tile-remove-cancel')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(first.name), findsOneWidget);
    expect(_efforts(d).any((e) => e.id == first.id), isTrue);
  });

  testWidgets('S-26902 confirming removes the whole exercise with its sets', (
    tester,
  ) async {
    final d = await _deps();
    await _pump(tester, d);
    final first = d.efforts.first;
    final second = d.efforts.last;
    expect(d.workoutState.getObservationsForEffort(first.id), isNotEmpty);

    await _openRemove(tester, first.id);
    await tester.tap(find.byKey(const Key('exercise-tile-remove-confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(first.name), findsNothing);
    expect(find.text(second.name), findsOneWidget);
    expect(_efforts(d).any((e) => e.id == first.id), isFalse);
    expect(d.workoutState.getObservationsForEffort(first.id), isEmpty);
    expect(_efforts(d).any((e) => e.id == second.id), isTrue);
  });
}
