// Plan 169 S-16901: the session core's persisted stamps come from the
// injected clock, not from the wall clock.

import 'package:test/test.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

const _fixedMs = 1794301200000;

DateTime Function() _fixedClock() =>
    () => DateTime.fromMillisecondsSinceEpoch(_fixedMs);

void main() {
  test(
    'S-16901 with a fixed injected clock every persisted session stamp carries it',
    () async {
      final repo = MockWorkoutRepository();
      await repo.initialize();
      final state = WorkoutState(repo, clock: _fixedClock());

      await state.createNewSession();
      final sessionId = state.currentSession!.id;
      expect(sessionId, 'session-$_fixedMs');

      final exercises = await repo.getExercises();
      final exercise = exercises.firstWhere(
        (e) => e.capabilities.contains('reps'),
      );
      final effortId = await state.addExerciseToSession(exercise);
      await state.addEntry(effortId);
      // A rest at position + 1 marks set 0 logged; the wrist's own end (below)
      // drops every set no rest marks, so the effort must hold a logged one.
      await state.recordRestStart(effortId, 1);
      await state.endSession(writeToHealth: false);

      final session = (await repo.getSession(sessionId))!;
      expect(session.startedAtMs, _fixedMs, reason: 'session startedAtMs');
      expect(session.createdAtMs, _fixedMs, reason: 'session createdAtMs');
      expect(session.updatedAtMs, _fixedMs, reason: 'session updatedAtMs');
      expect(session.endedAtMs, _fixedMs, reason: 'session endedAtMs');

      final segmentId = state.segments.first.id;
      final efforts = await repo.getSegmentEfforts(segmentId);
      final effort = efforts.firstWhere((e) => e.id == effortId);
      expect(effort.createdAtMs, _fixedMs, reason: 'effort createdAtMs');
      expect(effort.updatedAtMs, _fixedMs, reason: 'effort updatedAtMs');

      final observations = await repo.getEffortObservations(effortId);
      expect(observations, isNotEmpty, reason: 'the effort holds rows');
      for (final row in observations) {
        expect(row.createdAtMs, _fixedMs, reason: '${row.id} createdAtMs');
        expect(row.updatedAtMs, _fixedMs, reason: '${row.id} updatedAtMs');
      }

      final rests = await repo.getEntryRests(effortId);
      expect(rests, isNotEmpty, reason: 'the rest row was written');
      for (final rest in rests) {
        expect(rest.restStartMs, _fixedMs, reason: '${rest.id} restStartMs');
        expect(rest.createdAtMs, _fixedMs, reason: '${rest.id} createdAtMs');
        expect(rest.updatedAtMs, _fixedMs, reason: '${rest.id} updatedAtMs');
      }
    },
  );
}
