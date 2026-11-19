import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/core/services/screen_awake_port.dart';
import 'package:omnitrain/state/workout/timer_manager.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_screen_awake_port.dart';

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

typedef _Fixture = (MockWorkoutRepository, WorkoutState, FakeScreenAwakePort);

Future<_Fixture> _fixture() async {
  final repo = await _freshRepo();
  final port = FakeScreenAwakePort();
  final state = WorkoutState(repo, screenAwake: port);
  return (repo, state, port);
}

Future<(MockWorkoutRepository, WorkoutState)> _fixtureWithPort(
  ScreenAwakePort port,
) async {
  final repo = await _freshRepo();
  final state = WorkoutState(repo, screenAwake: port);
  return (repo, state);
}

Future<String> _timedEffort(
  MockWorkoutRepository repo,
  WorkoutState state, {
  String modality = 'cardio_endurance',
}) async {
  await state.createNewSession(modality: modality);
  return state.addExerciseToSession(await _exerciseWith(repo, 'time'));
}

Future<String> _roundEffort(
  MockWorkoutRepository repo,
  WorkoutState state,
) async {
  await state.createNewSession(modality: 'sports');
  return state.addExerciseToSession(await _exerciseWith(repo, 'rounds'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SessionScreenAwake (Mock)', () {
    test('S-19501 a running timed interval keeps awake', () async {
      final (repo, state, port) = await _fixture();
      final effortId = await _timedEffort(repo, state);
      state.screenAwake.attach();

      await state.startTimedEntry(effortId, 0);

      expect(port.calls, [false, true]);
      expect(state.screenAwake.isKeepingAwake, isTrue);
    });

    test('S-19502 paused keeps awake, resume sends nothing', () async {
      final (repo, state, port) = await _fixture();
      final effortId = await _timedEffort(repo, state);
      state.screenAwake.attach();
      await state.startTimedEntry(effortId, 0);
      expect(port.calls, [false, true]);

      await state.pauseTimedEntry(effortId, 0);
      expect(port.calls, [false, true]);

      await state.resumeTimedEntry(effortId, 0);
      expect(port.calls, [false, true]);

      await state.pauseTimedEntry(effortId, 0);
      expect(port.calls, [false, true]);
    });

    test('S-19503 expiry / finish releases (hold and round)', () async {
      // (a) a drill hold finished the way expiry finishes it.
      final (repo, state, port) = await _fixture();
      final drillId = await _timedEffort(
        repo,
        state,
        modality: 'isometric_stretching',
      );
      final drillEffort = state
          .getEffortsForSegment(state.segments.first.id)
          .single;
      expect(drillEffort.effortKind, 'drill');
      state.screenAwake.attach();
      await state.startTimedEntry(drillId, 0);
      expect(port.calls, [false, true]);

      await state.finishTimedEntry(drillId, 0);
      expect(port.calls, [false, true, false]);

      await state.recordRestStart(drillId, 1);
      expect(port.calls, [false, true, false]);

      // (b) a separate state with a round completed.
      final (repo2, state2, port2) = await _fixture();
      final roundId = await _roundEffort(repo2, state2);
      final roundEffort = state2
          .getEffortsForSegment(state2.segments.first.id)
          .single;
      expect(roundEffort.effortKind, 'round');
      state2.screenAwake.attach();
      await state2.startRound(roundId, 0);
      expect(port2.calls, [false, true]);

      await state2.completeRound(roundId, 0);
      expect(port2.calls, [false, true, false]);
    });

    test('S-19504 a paused round ended early releases', () async {
      final (repo, state, port) = await _fixture();
      final effortId = await _roundEffort(repo, state);
      state.screenAwake.attach();
      await state.startRound(effortId, 0);
      await state.pauseRound(effortId, 0);
      expect(port.calls, [false, true]);

      await state.endRoundEarly(effortId, 0);
      expect(port.calls, [false, true, false]);
    });

    test('S-19505 two timers at once', () async {
      final (repo, state, port) = await _fixture();
      await state.createNewSession(modality: 'sports');
      final exercise = await _exerciseWith(repo, 'rounds');
      final roundId = await state.addExerciseToSession(exercise);
      final timedId = await state.addExerciseToSession(
        exercise,
        effortKindOverride: 'timed',
      );
      state.screenAwake.attach();

      await state.startRound(roundId, 0);
      await state.startTimedEntry(timedId, 0);
      expect(port.calls, [false, true]);

      await state.completeRound(roundId, 0);
      expect(port.calls, [false, true]);

      await state.finishTimedEntry(timedId, 0);
      expect(port.calls, [false, true, false]);
    });

    test('S-19506 a watch-started timer adopted keeps awake', () async {
      final (repo, state, port) = await _fixture();
      final effortId = await _timedEffort(repo, state);
      state.screenAwake.attach();
      final now = DateTime.now().millisecondsSinceEpoch;

      final adopted = await state.adoptRemoteWorkTimer(
        effortId,
        RemoteWorkTimer(wireKind: 'elapsed', startedAtMs: now - 5000),
      );
      expect(adopted, isTrue);
      expect(port.calls, [false, true]);

      await state.finishTimedEntry(effortId, 0);
      expect(port.calls, [false, true, false]);
    });

    test('S-19507 screen disposed while running', () async {
      final (repo, state, port) = await _fixture();
      final effortId = await _timedEffort(repo, state);
      await state.startTimedEntry(effortId, 0);
      state.screenAwake.attach();
      expect(port.calls, [false, true]);

      state.screenAwake.detach();
      expect(port.calls, [false, true, false]);
      expect(state.inProgressWorkTimers(), hasLength(1));

      state.screenAwake.attach();
      expect(port.calls, [false, true, false, true]);
    });

    test('S-19508 a discarded session releases', () async {
      final (repo, state, port) = await _fixture();
      final effortId = await _timedEffort(repo, state);
      await state.startTimedEntry(effortId, 0);
      state.screenAwake.attach();
      expect(port.calls, [false, true]);

      await state.discardCurrentSession();
      expect(port.calls, [false, true, false]);
      expect(state.currentSession, isNull);
    });

    test('S-19509 a session ended while running releases', () async {
      final (repo, state, port) = await _fixture();
      final effortId = await _timedEffort(repo, state);
      await state.startTimedEntry(effortId, 0);
      state.screenAwake.attach();
      expect(port.calls, [false, true]);

      await state.endSession();
      expect(port.calls, [false, true, false]);

      // A second state with a paused round ends the same way.
      final (repo2, state2, port2) = await _fixture();
      final roundId = await _roundEffort(repo2, state2);
      await state2.startRound(roundId, 0);
      await state2.pauseRound(roundId, 0);
      state2.screenAwake.attach();
      expect(port2.calls, [false, true]);

      await state2.endSession();
      expect(port2.calls, [false, true, false]);
    });

    test('S-19510 backgrounded and back', () async {
      final (repo, state, port) = await _fixture();
      final effortId = await _timedEffort(repo, state);
      await state.startTimedEntry(effortId, 0);
      state.screenAwake.attach();
      expect(port.calls, [false, true]);

      state.screenAwake.didChangeAppLifecycleState(AppLifecycleState.inactive);
      expect(port.calls, [false, true]);

      state.screenAwake.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(port.calls, [false, true, false]);

      state.screenAwake.didChangeAppLifecycleState(AppLifecycleState.hidden);
      expect(port.calls, [false, true, false]);

      state.screenAwake.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(port.calls, [false, true, false, true]);
    });

    test('S-19511 not attached means never awake', () async {
      final (repo, state, port) = await _fixture();
      final effortId = await _timedEffort(repo, state);

      await state.startTimedEntry(effortId, 0);
      expect(port.calls, [false]);

      // The remote started earlier, so it replaces the in-progress interval.
      final startedAt = state
          .getTimedInstancesForEffort(effortId)
          .first
          .startedAtMs;
      final adopted = await state.adoptRemoteWorkTimer(
        effortId,
        RemoteWorkTimer(wireKind: 'elapsed', startedAtMs: startedAt - 5000),
      );
      expect(adopted, isTrue);
      expect(port.calls, [false]);
    });

    test('S-19512 presence is counted, never negative', () async {
      final (repo, state, port) = await _fixture();
      final effortId = await _timedEffort(repo, state);

      state.screenAwake.attach();
      state.screenAwake.attach();
      expect(state.screenAwake.attachedCount, 2);

      await state.startTimedEntry(effortId, 0);
      expect(port.calls, [false, true]);

      state.screenAwake.detach();
      expect(port.calls, [false, true]);
      expect(state.screenAwake.attachedCount, 1);

      state.screenAwake.detach();
      expect(port.calls, [false, true, false]);
      expect(state.screenAwake.attachedCount, 0);

      state.screenAwake.detach();
      expect(port.calls, [false, true, false]);
      expect(state.screenAwake.attachedCount, 0);

      state.screenAwake.attach();
      expect(port.calls, [false, true, false, true]);
      expect(state.screenAwake.attachedCount, 1);
    });

    test('S-19513 rest and sets never count', () async {
      final (repo, state, port) = await _fixture();
      await state.createNewSession();
      final effortId = await state.addExerciseToSession(
        (await repo.getExercises()).first,
      );
      final effort = state.getEffortsForSegment(state.segments.first.id).single;
      expect(effort.effortKind, 'set');

      await state.addEntry(effortId);
      await state.recordRestStart(effortId, 1);

      expect(state.inProgressRest(), isNotNull);
      expect(port.calls, [false]);
    });

    test('S-19514 a running set deleted releases', () async {
      final (repo, state, port) = await _fixture();
      final effortId = await _timedEffort(repo, state);
      await state.addEntry(effortId);
      await state.startTimedEntry(effortId, 0);
      state.screenAwake.attach();
      expect(port.calls, [false, true]);

      await state.deleteTimedEntry(effortId, 0);
      expect(port.calls, [false, true, false]);
      expect(state.inProgressWorkTimers(), isEmpty);
    });

    test('S-19516 dedupe on a hot path, startup reset once', () async {
      final (repo, state, port) = await _fixture();
      final effortId = await _timedEffort(repo, state);
      await state.startTimedEntry(effortId, 0);
      state.screenAwake.attach();
      expect(port.calls, [false, true]);

      for (var i = 0; i < 20; i++) {
        await state.updateSessionNote('n$i');
      }
      for (var i = 0; i < 3; i++) {
        await state.pauseTimedEntry(effortId, 0);
        await state.resumeTimedEntry(effortId, 0);
      }
      expect(port.calls, [false, true]);

      final freshRepo = await _freshRepo();
      expect(() => WorkoutState(freshRepo), returnsNormally);
    });

    test('S-19517 a port that throws does not break state', () async {
      final (repo, state) = await _fixtureWithPort(ThrowingScreenAwakePort());
      final effortId = await _timedEffort(repo, state);
      state.screenAwake.attach();

      await state.startTimedEntry(effortId, 0);
      expect(state.error, isNull);

      await state.pauseTimedEntry(effortId, 0);
      expect(state.error, isNull);

      await state.finishTimedEntry(effortId, 0);
      expect(state.error, isNull);
      expect(
        state.getTimedInstancesForEffort(effortId).single.state,
        TimedState.finished,
      );
    });
  });
}
