import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/workout/timer_manager.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

Future<Exercise> _exerciseWith(
  MockWorkoutRepository repo,
  String capability,
) async {
  final exercises = await repo.getExercises();
  return exercises.firstWhere(
    (e) => e.capabilities.contains(capability),
    orElse: () => exercises.first,
  );
}

void main() {
  group('WorkoutState.inProgressWorkTimers (Mock)', () {
    test('S-6201 an active timed interval lists one elapsed timer', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession(modality: 'cardio_endurance');
      final effortId = await state.addExerciseToSession(
        await _exerciseWith(repo, 'time'),
      );
      // Interval 1 is the second interval; interval 0 stays notStarted.
      await state.addEntry(effortId);
      await state.startTimedEntry(effortId, 1);

      final instances = state.getTimedInstancesForEffort(effortId);
      expect(instances, hasLength(2));
      final started = instances[1];
      expect(started.state, TimedState.active);

      final timers = state.inProgressWorkTimers();
      expect(timers, hasLength(1));
      final timer = timers.single;
      expect(timer.wireKind, 'elapsed');
      expect(timer.effortId, effortId);
      expect(timer.startedAtMs, started.startedAtMs);
      expect(timer.pausedAtMs, isNull);
      expect(timer.paused, isFalse);
      expect(timer.accumulatedPauseMs, 0);
      expect(timer.plannedDurationMs, isNull);
      expect(
        timer,
        InProgressWorkTimer(
          effortId: effortId,
          wireKind: 'elapsed',
          startedAtMs: started.startedAtMs,
        ),
      );
    });

    test(
      'a paused interval carries pausedAtMs and a resume its pause',
      () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession(modality: 'cardio_endurance');
        final effortId = await state.addExerciseToSession(
          await _exerciseWith(repo, 'time'),
        );
        await state.startTimedEntry(effortId, 0);
        await state.pauseTimedEntry(effortId, 0);

        final paused = state.getTimedInstancesForEffort(effortId).single;
        expect(paused.state, TimedState.paused);
        var timers = state.inProgressWorkTimers();
        expect(timers, hasLength(1));
        expect(timers.single.paused, isTrue);
        expect(timers.single.pausedAtMs, paused.pausedAtMs);
        expect(timers.single.pausedAtMs, isNotNull);

        await Future<void>.delayed(const Duration(milliseconds: 5));
        await state.resumeTimedEntry(effortId, 0);

        final resumed = state.getTimedInstancesForEffort(effortId).single;
        expect(resumed.state, TimedState.active);
        timers = state.inProgressWorkTimers();
        expect(timers, hasLength(1));
        expect(timers.single.paused, isFalse);
        expect(timers.single.pausedAtMs, isNull);
        expect(timers.single.accumulatedPauseMs, resumed.totalPausedDurationMs);
        expect(timers.single.accumulatedPauseMs, greaterThan(0));
      },
    );

    test('notStarted and finished intervals list nothing', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession(modality: 'cardio_endurance');
      final effortId = await state.addExerciseToSession(
        await _exerciseWith(repo, 'time'),
      );

      expect(state.inProgressWorkTimers(), isEmpty);

      await state.startTimedEntry(effortId, 0);
      expect(state.inProgressWorkTimers(), hasLength(1));

      await state.finishTimedEntry(effortId, 0);
      expect(state.inProgressWorkTimers(), isEmpty);

      // The entry added after the finished one is notStarted.
      await state.addEntry(effortId);
      expect(state.inProgressWorkTimers(), isEmpty);
    });

    test('a drill effort lists a hold timer', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession(modality: 'isometric_stretching');
      final effortId = await state.addExerciseToSession(
        await _exerciseWith(repo, 'time'),
      );
      final effort = state.getEffortsForSegment(state.segments.first.id).single;
      expect(effort.effortKind, 'drill');

      await state.startTimedEntry(effortId, 0);
      final instance = state.getTimedInstancesForEffort(effortId).single;

      final timers = state.inProgressWorkTimers();
      expect(timers, hasLength(1));
      expect(timers.single.wireKind, 'hold');
      expect(timers.single.effortId, effortId);
      expect(timers.single.startedAtMs, instance.startedAtMs);
      expect(timers.single.pausedAtMs, isNull);
      expect(timers.single.plannedDurationMs, isNull);
    });

    test(
      'a round lists a round timer with its planned duration in ms',
      () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession(modality: 'sports');
        final effortId = await state.addExerciseToSession(
          await _exerciseWith(repo, 'rounds'),
        );
        // 75 s is unlike every default, so a hard-coded plan fails.
        await state.updateRoundPlannedDuration(effortId, 0, 75);
        await state.startRound(effortId, 0);

        final round = state.getRoundsForEffort(effortId).single;
        expect(round.plannedDurationSecs, 75);
        expect(round.state, RoundState.active);

        var timers = state.inProgressWorkTimers();
        expect(timers, hasLength(1));
        var timer = timers.single;
        expect(timer.wireKind, 'round');
        expect(timer.effortId, effortId);
        expect(timer.startedAtMs, round.startedAtMs);
        expect(timer.pausedAtMs, isNull);
        expect(timer.plannedDurationMs, round.plannedDurationSecs * 1000);
        expect(timer.plannedDurationMs, 75000);

        await state.pauseRound(effortId, 0);
        final pausedRound = state.getRoundsForEffort(effortId).single;
        timers = state.inProgressWorkTimers();
        timer = timers.single;
        expect(timer.paused, isTrue);
        expect(timer.pausedAtMs, pausedRound.pausedAtMs);
        expect(timer.plannedDurationMs, 75000);
      },
    );

    test('two timed efforts in progress list only the newer start', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession(modality: 'cardio_endurance');
      final exercise = await _exerciseWith(repo, 'time');
      final firstId = await state.addExerciseToSession(exercise);
      final secondId = await state.addExerciseToSession(exercise);

      await state.startTimedEntry(firstId, 0);
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await state.startTimedEntry(secondId, 0);

      final first = state.getTimedInstancesForEffort(firstId).single;
      final second = state.getTimedInstancesForEffort(secondId).single;
      expect(second.startedAtMs, greaterThan(first.startedAtMs));

      final timers = state.inProgressWorkTimers();
      expect(timers, hasLength(1));
      expect(timers.single.effortId, secondId);
      expect(timers.single.startedAtMs, second.startedAtMs);
    });

    test('kinds are ordered by wire kind name', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession(modality: 'sports');
      final exercise = await _exerciseWith(repo, 'rounds');
      final roundId = await state.addExerciseToSession(exercise);
      final timedId = await state.addExerciseToSession(
        exercise,
        effortKindOverride: 'timed',
      );

      await state.startRound(roundId, 0);
      await state.startTimedEntry(timedId, 0);

      final timers = state.inProgressWorkTimers();
      expect(timers.map((t) => t.wireKind), ['elapsed', 'round']);
      expect(timers.map((t) => t.effortId), [timedId, roundId]);
    });

    test('a set effort lists nothing', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession();
      final effortId = await state.addExerciseToSession(
        (await repo.getExercises()).first,
      );

      final effort = state.getEffortsForSegment(state.segments.first.id).single;
      expect(effort.id, effortId);
      expect(effort.effortKind, 'set');
      expect(state.inProgressWorkTimers(), isEmpty);
    });

    test('a session that is not active lists nothing', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession(modality: 'cardio_endurance');
      final effortId = await state.addExerciseToSession(
        await _exerciseWith(repo, 'time'),
      );
      await state.startTimedEntry(effortId, 0);

      expect(state.hasActiveSession, isTrue);
      expect(state.inProgressWorkTimers(), hasLength(1));

      await state.endSession();

      expect(state.hasActiveSession, isFalse);
      expect(state.inProgressWorkTimers(), isEmpty);
    });
  });
}
