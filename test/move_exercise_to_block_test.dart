// Plan 271 — "Move to Block" in the routine editor.
//
// Scenarios S-27101..S-27104 of
// `docs/plans/2026-11-19-271-move-exercise-to-block-plan/2026-11-19-271-move-exercise-to-block-plan.md`.
// Mock repository only; every state/repository write happens before the
// first pump and is awaited. Plain `test()` for the state scenarios,
// `testWidgets` only for the editor scenario. Harness copied from
// `test/empty_routine_cannot_cost_the_running_workout_test.dart`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/routine/routine_setup_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

Future<Exercise> _getExerciseById(MockWorkoutRepository repo, String id) async {
  final exercises = await repo.getExercises();
  return exercises.firstWhere((e) => e.id == id);
}

typedef _RoutineDeps = ({
  MockWorkoutRepository repo,
  WorkoutState workoutState,
  RoutineState routineState,
  SettingsState settingsState,
});

Future<_RoutineDeps> _buildDeps() async {
  final repo = await _freshRepo();
  final workoutState = WorkoutState(repo);
  final routineState = RoutineState(repo);
  routineState.setAutosaveEnabled(false);
  final settingsState = SettingsState(repo, fakePreferencesService());
  await settingsState.initialize();
  return (
    repo: repo,
    workoutState: workoutState,
    routineState: routineState,
    settingsState: settingsState,
  );
}

Widget _buildScreen(_RoutineDeps deps, {String? templateId}) {
  return MaterialApp(
    home: RoutineSetupScreen(
      routineState: deps.routineState,
      workoutState: deps.workoutState,
      settingsState: deps.settingsState,
      templateId: templateId,
    ),
  );
}

/// The block ids and effort ids of the S-27101 fixture: block A holds
/// exercises X and Y, block B holds exercise Z; all are set exercises.
typedef _Fixture = ({
  String aId,
  String bId,
  String xId,
  String yId,
  String zId,
});

Future<_Fixture> _seedTwoBlocks(_RoutineDeps deps) async {
  final state = deps.routineState;
  await state.createNewRoutine('Plan 271');
  final aId = state.currentSegments.first.id;
  await state.updateSegment(aId, name: 'Block A');
  final bId = await state.addSegment(name: 'Block B');

  final x = await _getExerciseById(deps.repo, 'exercise-barbell-squat');
  final setExercises = (await deps.repo.getExercises())
      .where(
        (e) =>
            e.capabilities.contains('sets') && e.id != 'exercise-barbell-squat',
      )
      .toList();
  final y = setExercises.first;
  final z = setExercises[1];

  final xId = await state.addExerciseToRoutine(x, 'set', segmentId: aId);
  final yId = await state.addExerciseToRoutine(y, 'set', segmentId: aId);
  final zId = await state.addExerciseToRoutine(z, 'set', segmentId: bId);
  return (aId: aId, bId: bId, xId: xId, yId: yId, zId: zId);
}

/// A comparable snapshot of a block's efforts: id, orderIndex and block.
List<(String, int, String)> _blockSnapshot(
  RoutineState state,
  String segmentId,
) {
  return state
      .getEffortsForSegment(segmentId)
      .map((e) => (e.id, e.orderIndex, e.templateSegmentId))
      .toList();
}

/// A comparable snapshot of an effort's targets.
List<(String, int?, String?, int?)> _targetSnapshot(
  RoutineState state,
  String effortId,
) {
  return state
      .getEffortTargets(effortId)
      .map((t) => (t.metricId, t.setIndex, t.unitId, t.targetInt))
      .toList();
}

void main() {
  group('Plan 271 — state: moveExerciseToSegment', () {
    test(
      'S-27101 moving X from block A to block B appends it and renumbers both blocks',
      () async {
        final deps = await _buildDeps();
        final state = deps.routineState;
        final ids = await _seedTwoBlocks(deps);

        final moved = await state.moveExerciseToSegment(ids.xId, ids.bId);
        expect(moved, isTrue);

        final bEfforts = state.getEffortsForSegment(ids.bId);
        expect(bEfforts.map((e) => e.id), [ids.zId, ids.xId]);
        expect(bEfforts[0].orderIndex, 0);
        expect(bEfforts[1].orderIndex, 1);
        expect(bEfforts[1].templateSegmentId, ids.bId);

        final aEfforts = state.getEffortsForSegment(ids.aId);
        expect(aEfforts.map((e) => e.id), [ids.yId]);
        expect(aEfforts.first.orderIndex, 0);
      },
    );

    test('S-27102 X\'s targets travel with it unchanged', () async {
      final deps = await _buildDeps();
      final state = deps.routineState;
      final ids = await _seedTwoBlocks(deps);

      await state.setTargetValue(
        ids.xId,
        'metric-reps',
        'unit-reps',
        setIndex: 0,
        targetInt: 10,
      );
      await state.setTargetValue(
        ids.xId,
        'metric-reps',
        'unit-reps',
        setIndex: 1,
        targetInt: 12,
      );
      final before = _targetSnapshot(state, ids.xId);
      expect(before, hasLength(2));

      await state.moveExerciseToSegment(ids.xId, ids.bId);

      expect(_targetSnapshot(state, ids.xId), before);
    });

    test(
      'S-27103 same block, unknown block and unknown effort return false and change nothing',
      () async {
        final deps = await _buildDeps();
        final state = deps.routineState;
        final ids = await _seedTwoBlocks(deps);
        final aBefore = _blockSnapshot(state, ids.aId);
        final bBefore = _blockSnapshot(state, ids.bId);

        expect(await state.moveExerciseToSegment(ids.xId, ids.aId), isFalse);
        expect(
          await state.moveExerciseToSegment(ids.xId, 'block-does-not-exist'),
          isFalse,
        );
        expect(
          await state.moveExerciseToSegment('effort-does-not-exist', ids.bId),
          isFalse,
        );

        expect(_blockSnapshot(state, ids.aId), aBefore);
        expect(_blockSnapshot(state, ids.bId), bBefore);
      },
    );

    test(
      'S-27103b after saveRoutine the repository holds X under block B only',
      () async {
        final deps = await _buildDeps();
        final state = deps.routineState;
        final ids = await _seedTwoBlocks(deps);

        expect(await state.moveExerciseToSegment(ids.xId, ids.bId), isTrue);
        expect(await state.saveRoutine(), isTrue);

        final bEfforts = await deps.repo.getTemplateEfforts(ids.bId);
        expect(bEfforts.map((e) => e.id), contains(ids.xId));
        final aEfforts = await deps.repo.getTemplateEfforts(ids.aId);
        expect(aEfforts.map((e) => e.id), isNot(contains(ids.xId)));
      },
    );
  });

  group('Plan 271 — editor: Move to Block menu item', () {
    testWidgets('S-27104 choosing Move to Block B moves X under B', (
      tester,
    ) async {
      final deps = await _buildDeps();
      final state = deps.routineState;
      final ids = await _seedTwoBlocks(deps);
      expect(await state.saveRoutine(), isTrue);
      final templateId = state.currentTemplate!.id;
      state.clearCurrentRoutine();

      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_buildScreen(deps, templateId: templateId));
      await tester.pumpAndSettle();

      // Open the menu of X's card.
      final xCard = find.byKey(ValueKey(ids.xId));
      expect(xCard, findsOneWidget);
      await tester.tap(
        find.descendant(of: xCard, matching: find.byType(PopupMenuButton)),
      );
      await tester.pumpAndSettle();
      // One item per OTHER block: B is offered, X's own block A is not.
      expect(find.byKey(Key('move_to_block_${ids.bId}')), findsOneWidget);
      expect(find.text('Move to Block A'), findsNothing);
      await tester.tap(find.text('Move to Block B'));
      await tester.pumpAndSettle();

      // X is now listed under block B: it appears after Z in vertical order.
      final movedXCard = find.byKey(ValueKey(ids.xId));
      final zCard = find.byKey(ValueKey(ids.zId));
      expect(movedXCard, findsOneWidget);
      expect(zCard, findsOneWidget);
      await tester.ensureVisible(movedXCard);
      await tester.pumpAndSettle();
      await tester.ensureVisible(zCard);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(movedXCard).dy,
        greaterThan(tester.getTopLeft(zCard).dy),
      );
      expect(state.getEffortsForSegment(ids.bId).map((e) => e.id), [
        ids.zId,
        ids.xId,
      ]);
      expect(state.getEffortsForSegment(ids.aId).map((e) => e.id), [ids.yId]);
    });

    testWidgets('S-27104 a one-block routine shows no Move to item', (
      tester,
    ) async {
      final deps = await _buildDeps();
      final state = deps.routineState;
      await state.createNewRoutine('Plan 271 single block');
      final x = await _getExerciseById(deps.repo, 'exercise-barbell-squat');
      final xId = await state.addExerciseToRoutine(x, 'set');
      expect(await state.saveRoutine(), isTrue);
      final templateId = state.currentTemplate!.id;
      state.clearCurrentRoutine();

      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_buildScreen(deps, templateId: templateId));
      await tester.pumpAndSettle();

      final xCard = find.byKey(ValueKey(xId));
      expect(xCard, findsOneWidget);
      await tester.tap(
        find.descendant(of: xCard, matching: find.byType(PopupMenuButton)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Move to '), findsNothing);
      expect(find.text('Change Tracking'), findsOneWidget);
    });
  });
}
