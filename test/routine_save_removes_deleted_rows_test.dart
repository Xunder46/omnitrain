import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/routine/routine_state.dart';

// Plan 97: the routine editor turns autosave off, so saveRoutine() is the only
// write. It must delete the rows the user removed, not only write the ones that
// are left (S-R1..S-R3).

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

/// A new state over the same repository, as the editor builds when the routine
/// is opened again.
Future<RoutineState> _reopen(
  MockWorkoutRepository repo,
  String templateId,
) async {
  final state = RoutineState(repo);
  state.setAutosaveEnabled(false);
  await state.loadRoutineForEditing(templateId);
  return state;
}

void main() {
  group('RoutineState.saveRoutine removes rows the user deleted', () {
    test('S-R1: a removed exercise is gone after save and reopen', () async {
      final repo = await _freshRepo();
      final exercises = await repo.getExercises();
      final state = RoutineState(repo);
      state.setAutosaveEnabled(false);

      await state.createNewRoutine('Push Day');
      final keepId = await state.addExerciseToRoutine(exercises[0], 'set');
      final dropId = await state.addExerciseToRoutine(exercises[1], 'set');
      await state.saveRoutine();
      final templateId = state.currentTemplate!.id;

      final editing = await _reopen(repo, templateId);
      expect(editing.currentEfforts.map((e) => e.id), [keepId, dropId]);
      await editing.removeExerciseFromRoutine(dropId);
      await editing.saveRoutine();

      final again = await _reopen(repo, templateId);
      expect(again.currentEfforts.map((e) => e.id), [keepId]);
    });

    test('S-R2: the removed exercise targets are deleted too', () async {
      final repo = await _freshRepo();
      final exercises = await repo.getExercises();
      final state = RoutineState(repo);
      state.setAutosaveEnabled(false);

      await state.createNewRoutine('Pull Day');
      final dropId = await state.addExerciseToRoutine(exercises[0], 'set');
      await state.addExerciseToRoutine(exercises[1], 'set');
      await state.setTargetValue(
        dropId,
        'metric-reps',
        'unit-reps',
        setIndex: 1,
        targetInt: 8,
      );
      await state.saveRoutine();
      final templateId = state.currentTemplate!.id;
      expect(await repo.getTemplateTargets(dropId), hasLength(1));

      final editing = await _reopen(repo, templateId);
      await editing.removeExerciseFromRoutine(dropId);
      await editing.saveRoutine();

      expect(await repo.getTemplateTargets(dropId), isEmpty);
    });

    test('S-R3: a removed block and its exercises are gone after save', () async {
      final repo = await _freshRepo();
      final exercises = await repo.getExercises();
      final state = RoutineState(repo);
      state.setAutosaveEnabled(false);

      await state.createNewRoutine('Leg Day');
      final mainId = state.currentSegments.first.id;
      final extraId = await state.addSegment(segmentType: 'accessory');
      await state.addExerciseToRoutine(
        exercises[0],
        'set',
        segmentId: extraId,
      );
      await state.saveRoutine();
      final templateId = state.currentTemplate!.id;

      final editing = await _reopen(repo, templateId);
      await editing.removeSegment(extraId);
      await editing.saveRoutine();

      final again = await _reopen(repo, templateId);
      expect(again.currentSegments.map((s) => s.id), [mainId]);
      expect(await repo.getTemplateEfforts(extraId), isEmpty);
    });
  });

  // The ids used to be built from the clock alone, so two rows made in the
  // same millisecond shared an id and the second overwrote the first. That
  // made S-R3 pass or fail by timing. Building many rows in a tight loop makes
  // a repeat near-certain without the fix.
  group('RoutineState ids never repeat inside one routine', () {
    test('S-R4: blocks added back to back all get their own id', () async {
      final repo = await _freshRepo();
      final state = RoutineState(repo);
      state.setAutosaveEnabled(false);

      await state.createNewRoutine('Many Blocks');
      for (var i = 0; i < 40; i++) {
        await state.addSegment(segmentType: 'accessory');
      }

      final ids = state.currentSegments.map((s) => s.id).toList();
      expect(ids, hasLength(41));
      expect(ids.toSet(), hasLength(41));
    });

    test('S-R5: exercises and cloned blocks added back to back stay apart',
        () async {
      final repo = await _freshRepo();
      final exercises = await repo.getExercises();
      final state = RoutineState(repo);
      state.setAutosaveEnabled(false);

      await state.createNewRoutine('Clones');
      final mainId = state.currentSegments.first.id;
      for (var i = 0; i < 20; i++) {
        await state.addExerciseToRoutine(exercises[0], 'set');
      }
      for (var i = 0; i < 10; i++) {
        await state.cloneSegment(mainId);
      }

      final segmentIds = state.currentSegments.map((s) => s.id).toList();
      expect(segmentIds.toSet(), hasLength(segmentIds.length));
      final effortIds = state.currentEfforts.map((e) => e.id).toList();
      expect(effortIds, hasLength(20 * 11));
      expect(effortIds.toSet(), hasLength(effortIds.length));
    });
  });
}
