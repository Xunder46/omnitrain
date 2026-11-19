// Plan 270: an exercise on the live list can move up or down one place, among
// the loose exercises and blocks, and inside a block.
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

/// A live workout with [count] set exercises added in order A, B, C...
Future<_Deps> _deps({int count = 3}) async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  final workoutState = WorkoutState(repo);
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
      .take(count)
      .toList();
  final efforts = <({String id, String name})>[];
  for (final e in exercises) {
    efforts.add((id: await workoutState.addExerciseToSession(e), name: e.name));
  }
  return (
    workoutState: workoutState,
    routineState: RoutineState(repo),
    settingsState: settingsState,
    repo: repo,
    efforts: efforts,
  );
}

List<SegmentEffort> _efforts(WorkoutState s) => [
  for (final segment in s.segments) ...s.getEffortsForSegment(segment.id),
];

SegmentEffort _effort(WorkoutState s, String id) =>
    _efforts(s).firstWhere((e) => e.id == id);

int _top(WorkoutState s, String id) {
  final e = _effort(s, id);
  return e.topLevelOrderIndex ?? e.orderIndex;
}

int _inBlock(WorkoutState s, String id) {
  final e = _effort(s, id);
  return e.blockOrderIndex ?? e.orderIndex;
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

Future<void> _openMenu(WidgetTester tester, String effortId) async {
  await tester.tap(find.byKey(Key('exercise_tile_menu_$effortId')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

double _y(WidgetTester tester, String name) =>
    tester.getTopLeft(find.text(name)).dy;

void main() {
  test('S-27001 a loose exercise moves up and down among the others', () async {
    final d = await _deps();
    final (a, b, c) = (d.efforts[0].id, d.efforts[1].id, d.efforts[2].id);
    expect(_top(d.workoutState, a) < _top(d.workoutState, b), isTrue);

    expect(await d.workoutState.moveExercise(b, -1), isTrue);
    expect(_top(d.workoutState, b) < _top(d.workoutState, a), isTrue);
    expect(_top(d.workoutState, a) < _top(d.workoutState, c), isTrue);

    expect(await d.workoutState.moveExercise(b, 1), isTrue);
    expect(_top(d.workoutState, a) < _top(d.workoutState, b), isTrue);
    expect(_top(d.workoutState, b) < _top(d.workoutState, c), isTrue);
  });

  test(
    'S-27002 the first cannot move up and the last cannot move down',
    () async {
      final d = await _deps();
      expect(
        await d.workoutState.moveExercise(d.efforts.first.id, -1),
        isFalse,
      );
      expect(await d.workoutState.moveExercise(d.efforts.last.id, 1), isFalse);
      expect(await d.workoutState.moveExercise('no-such-effort', 1), isFalse);
    },
  );

  test('S-27003 inside a block the exercises swap places', () async {
    final d = await _deps();
    final (a, b) = (d.efforts[0].id, d.efforts[1].id);
    final blockId = await d.workoutState.addSessionBlock(name: 'Superset');
    await d.workoutState.assignEffortToBlock(a, blockId);
    await d.workoutState.assignEffortToBlock(b, blockId);
    expect(_inBlock(d.workoutState, a) < _inBlock(d.workoutState, b), isTrue);

    expect(await d.workoutState.moveExercise(b, -1), isTrue);

    expect(_inBlock(d.workoutState, b) < _inBlock(d.workoutState, a), isTrue);
  });

  test('S-27004 a loose exercise can pass a block', () async {
    final d = await _deps();
    final (a, b, c) = (d.efforts[0].id, d.efforts[1].id, d.efforts[2].id);
    final blockId = await d.workoutState.addSessionBlock(name: 'Superset');
    await d.workoutState.assignEffortToBlock(b, blockId);
    int blockTop() {
      final block = d.workoutState.getSessionBlocks().firstWhere(
        (x) => x.id == blockId,
      );
      return block.topLevelOrderIndex ?? block.orderIndex;
    }

    // The new block is shown last: A, C, [block with B]. Move C down past it.
    expect(blockTop() > _top(d.workoutState, c), isTrue);
    expect(await d.workoutState.moveExercise(c, 1), isTrue);

    expect(blockTop() < _top(d.workoutState, c), isTrue);
    expect(_top(d.workoutState, a) < blockTop(), isTrue);
  });

  testWidgets('S-27005 the tile menu moves an exercise and disables the ends', (
    tester,
  ) async {
    final d = await _deps(count: 2);
    final (a, b) = (d.efforts[0], d.efforts[1]);
    await _pump(tester, d);
    expect(_y(tester, a.name) < _y(tester, b.name), isTrue);

    // The first exercise cannot move up.
    await _openMenu(tester, a.id);
    final up = tester.widget<PopupMenuItem<String>>(
      find.byKey(Key('exercise_tile_up_${a.id}')),
    );
    expect(up.enabled, isFalse);
    final down = tester.widget<PopupMenuItem<String>>(
      find.byKey(Key('exercise_tile_down_${a.id}')),
    );
    expect(down.enabled, isTrue);

    await tester.tap(find.byKey(Key('exercise_tile_down_${a.id}')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(_y(tester, b.name) < _y(tester, a.name), isTrue);
  });
}
