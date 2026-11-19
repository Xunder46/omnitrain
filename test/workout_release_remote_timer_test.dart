// A hold the wrist stopped never keeps counting on the phone: the state-level
// release (244 P2a, red tests).
//
// Plan: `docs/plans/2026-11-19-244-watch-hold-timer-never-outlives-its-stop-plan/
// 2026-11-19-244-watch-hold-timer-never-outlives-its-stop-plan.md`,
// D-24401, scenarios S-24401..S-24408.
// Scenario mapping:
//   S-24401 a timed interval the wire took is given back              → `S-24401 ...`
//   S-24402 a paused copy is given back with its pause bookkeeping    → `S-24402 ...`
//   S-24403 a finished interval is never touched                      → `S-24403 ...`
//   S-24404 the 1000 ms tolerance, both arms, fresh fixture each      → `S-24404a ...`,
//     `S-24404b ...`
//   S-24405 a round is given back like a timed interval               → `S-24405 ...`
//   S-24406 the release names one effort and touches no other         → `S-24406 ...`
//   S-24407 an unknown effort id changes nothing                      → `S-24407 ...`
//   S-24408 the release matches by start, not by effort alone         → `S-24408 ...`
//
// Both groups run the same fixtures through the same state: the release must
// leave the same rows under `HiveWorkoutRepository` and
// `MockWorkoutRepository` (memory AND stored). Plain `test()`: a Hive write
// inside a widget test's fake-async zone never drains.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:omnitrain/core/constants/capability.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/hive_workout_repository.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/workout/timer_manager.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/watch_capture_import_harness.dart' show seedExercise;

/// The start the watch gave the timer (the plan's S0).
final int _s0 = DateTime.utc(2026, 11, 5, 9, 0, 0).millisecondsSinceEpoch;

const String _exerciseId = 'ex-run';

/// Stand-in for the path_provider platform channel, which has no
/// implementation under `flutter_test` (`HiveWorkoutRepository.initialize()`
/// calls `Hive.initFlutter()`). Copied from
/// `test/stale_watch_timer_adoption_test.dart`.
class _PathProviderChannel {
  static const MethodChannel _channel = MethodChannel(
    'plugins.flutter.io/path_provider',
  );
  static late Directory _root;

  static void install(Directory root) {
    _root = root;
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, _handle);
  }

  static Future<dynamic> _handle(MethodCall call) async {
    switch (call.method) {
      case 'getApplicationDocumentsDirectory':
      case 'getApplicationSupportDirectory':
      case 'getTemporaryDirectory':
        return _root.path;
      default:
        return null;
    }
  }
}

/// A session holding one seeded exercise as an effort of [modality]'s kind.
Future<(WorkoutState, String)> _session(
  WorkoutRepository repository,
  String modality,
) async {
  final state = WorkoutState(repository);
  await state.createNewSession(modality: modality);
  final exercise = (await repository.getExercises()).firstWhere(
    (e) => e.id == _exerciseId,
  );
  final effortId = await state.addExerciseToSession(exercise);
  return (state, effortId);
}

/// Rewrites the timed instance at [index] to a finished interval that began at
/// [x], through the store, and re-reads it (the plan's "finished at X").
Future<void> _finishTimedAt(
  WorkoutState state,
  String effortId,
  int index,
  int x,
) async {
  final instance = state.getTimedInstancesForEffort(effortId)[index];
  await state.repository.updateTimedInstance(
    instance.copyWith(
      state: TimedState.finished,
      startedAtMs: x,
      finishedAtMs: x + 120000,
      actualDurationSecs: 120,
      updatedAtMs: x + 120000,
    ),
  );
  await state.refreshEfforts([effortId]);
}

/// The S-24401..S-24404, S-24407, S-24408 fixture: a timed effort, with
/// [entries] extra intervals added, whose interval 0 the wire runs at S0.
Future<(WorkoutState, String)> _wireRunsIntervalZero(
  WorkoutRepository repository, {
  int entries = 0,
  RemoteWorkTimer? remote,
}) async {
  final (state, effortId) = await _session(repository, 'cardio_endurance');
  for (var i = 0; i < entries; i++) {
    await state.addEntry(effortId);
  }
  await state.adoptRemoteWorkTimer(
    effortId,
    remote ?? RemoteWorkTimer(wireKind: 'elapsed', startedAtMs: _s0),
  );
  return (state, effortId);
}

/// The S-24405, S-24409a, S-24409b fixture: a round the wire took, active at
/// S0.
Future<(WorkoutState, String)> _roundAdoptedAtS0(
  WorkoutRepository repository,
) async {
  final (state, effortId) = await _session(repository, 'sports');
  await state.addRound(effortId);
  await state.adoptRemoteWorkTimer(
    effortId,
    RemoteWorkTimer(
      wireKind: 'round',
      startedAtMs: _s0,
      plannedDurationMs: 60000,
    ),
  );
  return (state, effortId);
}

void main() {
  group('Mock', () => _releaseTests(open: _openMock, close: () async {}));
  group('Hive', () => _releaseTests(open: _openHive, close: _closeHive));
}

Future<WorkoutRepository> _openMock() async {
  final repository = MockWorkoutRepository();
  await repository.initialize();
  await _seed(repository);
  return repository;
}

Directory? _hiveDir;

Future<WorkoutRepository> _openHive() async {
  final dir = await Directory.systemTemp.createTemp('workout_release_remote_');
  _hiveDir = dir;
  _PathProviderChannel.install(dir);
  Hive.init(dir.path);
  final repository = HiveWorkoutRepository();
  await repository.initialize();
  await _seed(repository);
  return repository;
}

Future<void> _closeHive() async {
  await Hive.deleteFromDisk();
  final dir = _hiveDir;
  if (dir != null && await dir.exists()) await dir.delete(recursive: true);
  _hiveDir = null;
}

/// The one exercise every modality's effort points at, with the capabilities
/// each kind needs.
Future<void> _seed(WorkoutRepository repository) async {
  await seedExercise(
    repository,
    id: _exerciseId,
    name: 'Trail Run',
    capabilities: [
      ExerciseCapability.time,
      ExerciseCapability.distance,
      ExerciseCapability.hold,
      ExerciseCapability.rounds,
    ],
  );
}

void _releaseTests({
  required Future<WorkoutRepository> Function() open,
  required Future<void> Function() close,
}) {
  late WorkoutRepository repository;

  setUp(() async => repository = await open());
  tearDown(close);

  test(
    'S-24401 a timed interval the wire took is given back to not started',
    () async {
      final (state, effortId) = await _wireRunsIntervalZero(
        repository,
        entries: 2,
      );
      final fixture = state.getTimedInstancesForEffort(effortId);
      expect(fixture, hasLength(3), reason: 'S-24401 the fixture is 3 rows');
      expect(
        fixture[0].state,
        TimedState.active,
        reason: 'S-24401 the wire runs interval 0',
      );
      expect(fixture[0].startedAtMs, _s0, reason: 'S-24401 on the wire start');

      var notifications = 0;
      state.addListener(() => notifications++);
      final revisionBefore = state.watchRefreshRevision;

      final changed = await state.releaseRemoteWorkTimer(effortId, _s0);

      expect(changed, isTrue, reason: 'S-24401 the release reset a row');
      final memory = state.getTimedInstancesForEffort(effortId);
      expect(
        memory[0].state,
        TimedState.notStarted,
        reason: 'S-24401 interval 0 is not started again',
      );
      expect(
        memory[0].startedAtMs,
        0,
        reason: 'S-24401 with no start of its own',
      );
      expect(memory[0].pausedAtMs, isNull, reason: 'S-24401 and not paused');
      expect(
        memory[1].state,
        TimedState.notStarted,
        reason: 'S-24401 interval 1 is untouched',
      );
      expect(memory[1].startedAtMs, 0, reason: 'S-24401 still unstarted');
      expect(
        memory[2].state,
        TimedState.notStarted,
        reason: 'S-24401 interval 2 is untouched',
      );
      expect(memory[2].startedAtMs, 0, reason: 'S-24401 still unstarted');
      final stored = await repository.getTimedInstances(effortId);
      expect(
        stored[0].state,
        TimedState.notStarted,
        reason: 'S-24401 the stored interval 0 is not started too',
      );
      expect(
        stored[0].startedAtMs,
        0,
        reason: 'S-24401 the store keeps no start',
      );
      expect(
        stored[0].pausedAtMs,
        isNull,
        reason: 'S-24401 the store keeps no pause',
      );
      expect(
        stored[1].state,
        TimedState.notStarted,
        reason: 'S-24401 the stored interval 1 is untouched',
      );
      expect(
        stored[2].state,
        TimedState.notStarted,
        reason: 'S-24401 the stored interval 2 is untouched',
      );
      expect(notifications, 1, reason: 'S-24401 one notification');
      expect(
        state.watchRefreshRevision,
        revisionBefore + 1,
        reason: 'S-24401 the revision is bumped once',
      );
    },
  );

  test(
    'S-24402 a paused copy is given back with its pause bookkeeping',
    () async {
      final (state, effortId) = await _wireRunsIntervalZero(
        repository,
        remote: RemoteWorkTimer(
          wireKind: 'elapsed',
          startedAtMs: _s0,
          pausedAtMs: _s0 + 12000,
          accumulatedPauseMs: 5000,
        ),
      );
      final fixture = state.getTimedInstancesForEffort(effortId);
      expect(
        fixture[0].state,
        TimedState.paused,
        reason: 'S-24402 the wire left the interval paused',
      );
      expect(fixture[0].startedAtMs, _s0, reason: 'S-24402 on the wire start');
      expect(
        fixture[0].pausedAtMs,
        _s0 + 12000,
        reason: 'S-24402 paused at the wire pause',
      );
      expect(
        fixture[0].totalPausedDurationMs,
        5000,
        reason: 'S-24402 with the wire pause total',
      );

      var notifications = 0;
      state.addListener(() => notifications++);
      final revisionBefore = state.watchRefreshRevision;

      final changed = await state.releaseRemoteWorkTimer(effortId, _s0);

      expect(changed, isTrue, reason: 'S-24402 the release reset a row');
      final memory = state.getTimedInstancesForEffort(effortId);
      expect(
        memory[0].state,
        TimedState.notStarted,
        reason: 'S-24402 interval 0 is not started again',
      );
      expect(memory[0].startedAtMs, 0, reason: 'S-24402 with no start');
      expect(memory[0].pausedAtMs, isNull, reason: 'S-24402 with no pause');
      expect(
        memory[0].totalPausedDurationMs,
        0,
        reason: 'S-24402 the pause total is dropped too',
      );
      final stored = await repository.getTimedInstances(effortId);
      expect(
        stored[0].state,
        TimedState.notStarted,
        reason: 'S-24402 the stored interval 0 is not started too',
      );
      expect(
        stored[0].startedAtMs,
        0,
        reason: 'S-24402 the store keeps no start',
      );
      expect(
        stored[0].pausedAtMs,
        isNull,
        reason: 'S-24402 the store keeps no pause',
      );
      expect(
        stored[0].totalPausedDurationMs,
        0,
        reason: 'S-24402 the store drops the pause total too',
      );
      expect(notifications, 1, reason: 'S-24402 one notification');
      expect(
        state.watchRefreshRevision,
        revisionBefore + 1,
        reason: 'S-24402 the revision is bumped once',
      );
    },
  );

  test('S-24403 a finished interval is never touched by the release', () async {
    final (state, effortId) = await _session(repository, 'cardio_endurance');
    await _finishTimedAt(state, effortId, 0, _s0);
    final fixture = state.getTimedInstancesForEffort(effortId);
    expect(
      fixture[0].state,
      TimedState.finished,
      reason: 'S-24403 the phone already logged interval 0',
    );
    expect(fixture[0].startedAtMs, _s0, reason: 'S-24403 at S0');
    expect(
      fixture[0].actualDurationSecs,
      120,
      reason: 'S-24403 with the phone total',
    );

    var notifications = 0;
    state.addListener(() => notifications++);
    final revisionBefore = state.watchRefreshRevision;

    final changed = await state.releaseRemoteWorkTimer(effortId, _s0);

    expect(
      changed,
      isFalse,
      reason: 'S-24403 a finished interval is not the wire timer',
    );
    final memory = state.getTimedInstancesForEffort(effortId);
    expect(
      memory[0].state,
      TimedState.finished,
      reason: 'S-24403 interval 0 is still finished',
    );
    expect(memory[0].startedAtMs, _s0, reason: 'S-24403 at its own start');
    expect(
      memory[0].actualDurationSecs,
      120,
      reason: 'S-24403 with its phone total',
    );
    final stored = await repository.getTimedInstances(effortId);
    expect(
      stored[0].state,
      TimedState.finished,
      reason: 'S-24403 the stored interval 0 is still finished',
    );
    expect(
      stored[0].startedAtMs,
      _s0,
      reason: 'S-24403 at its own start in the store',
    );
    expect(
      stored[0].actualDurationSecs,
      120,
      reason: 'S-24403 with its phone total in the store',
    );
    expect(notifications, 0, reason: 'S-24403 no notification');
    expect(
      state.watchRefreshRevision,
      revisionBefore,
      reason: 'S-24403 no revision bump',
    );
  });

  test(
    'S-24404a a release 1000 ms after the start is within the tolerance',
    () async {
      final (state, effortId) = await _wireRunsIntervalZero(repository);
      final fixture = state.getTimedInstancesForEffort(effortId);
      expect(
        fixture[0].state,
        TimedState.active,
        reason: 'S-24404a the wire runs interval 0',
      );
      expect(fixture[0].startedAtMs, _s0, reason: 'S-24404a on the wire start');

      final changed = await state.releaseRemoteWorkTimer(effortId, _s0 + 1000);

      expect(changed, isTrue, reason: 'S-24404a 1000 ms is within tolerance');
      final memory = state.getTimedInstancesForEffort(effortId);
      expect(
        memory[0].state,
        TimedState.notStarted,
        reason: 'S-24404a interval 0 is not started again',
      );
      expect(memory[0].startedAtMs, 0, reason: 'S-24404a with no start');
      final stored = await repository.getTimedInstances(effortId);
      expect(
        stored[0].state,
        TimedState.notStarted,
        reason: 'S-24404a the stored interval 0 is not started too',
      );
      expect(
        stored[0].startedAtMs,
        0,
        reason: 'S-24404a the store keeps no start',
      );
    },
  );

  test(
    'S-24404b a release 1001 ms after the start is outside the tolerance',
    () async {
      final (state, effortId) = await _wireRunsIntervalZero(repository);
      final fixture = state.getTimedInstancesForEffort(effortId);
      expect(
        fixture[0].state,
        TimedState.active,
        reason: 'S-24404b the wire runs interval 0',
      );
      expect(fixture[0].startedAtMs, _s0, reason: 'S-24404b on the wire start');

      var notifications = 0;
      state.addListener(() => notifications++);
      final revisionBefore = state.watchRefreshRevision;

      final changed = await state.releaseRemoteWorkTimer(effortId, _s0 + 1001);

      expect(changed, isFalse, reason: 'S-24404b 1001 ms is another start');
      final memory = state.getTimedInstancesForEffort(effortId);
      expect(
        memory[0].state,
        TimedState.active,
        reason: 'S-24404b interval 0 is still active',
      );
      expect(
        memory[0].startedAtMs,
        _s0,
        reason: 'S-24404b on the wire start, untouched',
      );
      final stored = await repository.getTimedInstances(effortId);
      expect(
        stored[0].state,
        TimedState.active,
        reason: 'S-24404b the stored interval 0 is still active',
      );
      expect(
        stored[0].startedAtMs,
        _s0,
        reason: 'S-24404b on the wire start in the store',
      );
      expect(notifications, 0, reason: 'S-24404b no notification');
      expect(
        state.watchRefreshRevision,
        revisionBefore,
        reason: 'S-24404b no revision bump',
      );
    },
  );

  test(
    'S-24405 a round the wire took is given back like a timed interval',
    () async {
      final (state, effortId) = await _session(repository, 'sports');
      await state.addRound(effortId);
      await state.adoptRemoteWorkTimer(
        effortId,
        RemoteWorkTimer(
          wireKind: 'round',
          startedAtMs: _s0,
          plannedDurationMs: 60000,
        ),
      );
      final fixture = state.getRoundsForEffort(effortId);
      expect(
        fixture[0].state,
        RoundState.active,
        reason: 'S-24405 the wire runs the round',
      );
      expect(fixture[0].startedAtMs, _s0, reason: 'S-24405 on the wire start');

      var notifications = 0;
      state.addListener(() => notifications++);
      final revisionBefore = state.watchRefreshRevision;

      final changed = await state.releaseRemoteWorkTimer(effortId, _s0);

      expect(changed, isTrue, reason: 'S-24405 the release reset the round');
      final memory = state.getRoundsForEffort(effortId);
      expect(
        memory[0].state,
        RoundState.notStarted,
        reason: 'S-24405 the round is not started again',
      );
      expect(memory[0].startedAtMs, 0, reason: 'S-24405 with no start');
      final stored = await repository.getRoundInstances(effortId);
      expect(
        stored[0].state,
        RoundState.notStarted,
        reason: 'S-24405 the stored round is not started too',
      );
      expect(
        stored[0].startedAtMs,
        0,
        reason: 'S-24405 the store keeps no start',
      );
      expect(notifications, 1, reason: 'S-24405 one notification');
      expect(
        state.watchRefreshRevision,
        revisionBefore + 1,
        reason: 'S-24405 the revision is bumped once',
      );
    },
  );

  test(
    'S-24409a a round release 1000 ms after the start is within the tolerance',
    () async {
      final (state, effortId) = await _roundAdoptedAtS0(repository);
      final fixture = state.getRoundsForEffort(effortId);
      expect(
        fixture[0].state,
        RoundState.active,
        reason: 'S-24409a the wire runs the round',
      );
      expect(fixture[0].startedAtMs, _s0, reason: 'S-24409a on the wire start');

      var notifications = 0;
      state.addListener(() => notifications++);

      final changed = await state.releaseRemoteWorkTimer(effortId, _s0 + 1000);

      expect(changed, isTrue, reason: 'S-24409a 1000 ms is within tolerance');
      final memory = state.getRoundsForEffort(effortId);
      expect(
        memory[0].state,
        RoundState.notStarted,
        reason: 'S-24409a the round is not started again',
      );
      expect(memory[0].startedAtMs, 0, reason: 'S-24409a with no start');
      final stored = await repository.getRoundInstances(effortId);
      expect(
        stored[0].state,
        RoundState.notStarted,
        reason: 'S-24409a the stored round is not started too',
      );
      expect(
        stored[0].startedAtMs,
        0,
        reason: 'S-24409a the store keeps no start',
      );
      expect(notifications, 1, reason: 'S-24409a one notification');
    },
  );

  test(
    'S-24409b a round release 1001 ms after the start is outside the tolerance',
    () async {
      final (state, effortId) = await _roundAdoptedAtS0(repository);
      final fixture = state.getRoundsForEffort(effortId);
      expect(
        fixture[0].state,
        RoundState.active,
        reason: 'S-24409b the wire runs the round',
      );
      expect(fixture[0].startedAtMs, _s0, reason: 'S-24409b on the wire start');

      var notifications = 0;
      state.addListener(() => notifications++);
      final revisionBefore = state.watchRefreshRevision;

      final changed = await state.releaseRemoteWorkTimer(effortId, _s0 + 1001);

      expect(changed, isFalse, reason: 'S-24409b 1001 ms is another start');
      final memory = state.getRoundsForEffort(effortId);
      expect(
        memory[0].state,
        RoundState.active,
        reason: 'S-24409b the round is still active',
      );
      expect(
        memory[0].startedAtMs,
        _s0,
        reason: 'S-24409b on the wire start, untouched',
      );
      final stored = await repository.getRoundInstances(effortId);
      expect(
        stored[0].state,
        RoundState.active,
        reason: 'S-24409b the stored round is still active',
      );
      expect(
        stored[0].startedAtMs,
        _s0,
        reason: 'S-24409b on the wire start in the store',
      );
      expect(notifications, 0, reason: 'S-24409b no notification');
      expect(
        state.watchRefreshRevision,
        revisionBefore,
        reason: 'S-24409b no revision bump',
      );
    },
  );

  test('S-24406 the release names one effort and touches no other', () async {
    final (state, firstEffortId) = await _session(
      repository,
      'cardio_endurance',
    );
    final exercise = (await repository.getExercises()).firstWhere(
      (e) => e.id == _exerciseId,
    );
    final secondEffortId = await state.addExerciseToSession(exercise);
    await state.adoptRemoteWorkTimer(
      firstEffortId,
      RemoteWorkTimer(wireKind: 'elapsed', startedAtMs: _s0),
    );
    await state.adoptRemoteWorkTimer(
      secondEffortId,
      RemoteWorkTimer(wireKind: 'elapsed', startedAtMs: _s0),
    );
    final fixture = state.getTimedInstancesForEffort(firstEffortId);
    expect(
      fixture[0].state,
      TimedState.active,
      reason: 'S-24406 the wire runs the first effort',
    );
    expect(
      state.getTimedInstancesForEffort(secondEffortId)[0].state,
      TimedState.active,
      reason: 'S-24406 and the second one',
    );

    var notifications = 0;
    state.addListener(() => notifications++);
    final revisionBefore = state.watchRefreshRevision;

    final changed = await state.releaseRemoteWorkTimer(firstEffortId, _s0);

    expect(changed, isTrue, reason: 'S-24406 the first effort is released');
    final firstMemory = state.getTimedInstancesForEffort(firstEffortId);
    expect(
      firstMemory[0].state,
      TimedState.notStarted,
      reason: 'S-24406 the first effort is not started again',
    );
    expect(firstMemory[0].startedAtMs, 0, reason: 'S-24406 with no start');
    final secondMemory = state.getTimedInstancesForEffort(secondEffortId);
    expect(
      secondMemory[0].state,
      TimedState.active,
      reason: 'S-24406 the second effort is untouched',
    );
    expect(
      secondMemory[0].startedAtMs,
      _s0,
      reason: 'S-24406 on the wire start',
    );
    final secondStored = await repository.getTimedInstances(secondEffortId);
    expect(
      secondStored[0].state,
      TimedState.active,
      reason: 'S-24406 the stored second effort is untouched',
    );
    expect(
      secondStored[0].startedAtMs,
      _s0,
      reason: 'S-24406 on the wire start in the store',
    );
    expect(notifications, 1, reason: 'S-24406 one notification');
    expect(
      state.watchRefreshRevision,
      revisionBefore + 1,
      reason: 'S-24406 the revision is bumped once',
    );
  });

  test(
    'S-24407 an unknown effort id changes nothing and throws nothing',
    () async {
      final (state, effortId) = await _wireRunsIntervalZero(repository);
      expect(
        state.getTimedInstancesForEffort(effortId)[0].state,
        TimedState.active,
        reason: 'S-24407 the fixture is an active interval',
      );

      var notifications = 0;
      state.addListener(() => notifications++);
      final revisionBefore = state.watchRefreshRevision;

      final changed = await state.releaseRemoteWorkTimer('no-such-effort', _s0);

      expect(changed, isFalse, reason: 'S-24407 no such effort');
      expect(
        state.getTimedInstancesForEffort(effortId)[0].state,
        TimedState.active,
        reason: 'S-24407 the held interval is untouched',
      );
      expect(notifications, 0, reason: 'S-24407 no notification');
      expect(
        state.watchRefreshRevision,
        revisionBefore,
        reason: 'S-24407 no revision bump',
      );
    },
  );

  test('S-24408 the release matches by start, not by effort alone', () async {
    final (state, effortId) = await _wireRunsIntervalZero(repository);
    await state.addEntry(effortId);
    final instance = state.getTimedInstancesForEffort(effortId)[1];
    await state.repository.updateTimedInstance(
      instance.copyWith(
        state: TimedState.active,
        startedAtMs: _s0 + 60000,
        updatedAtMs: _s0 + 60000,
      ),
    );
    await state.refreshEfforts([effortId]);
    final fixture = state.getTimedInstancesForEffort(effortId);
    expect(
      fixture[0].state,
      TimedState.active,
      reason: 'S-24408 the wire runs interval 0',
    );
    expect(fixture[0].startedAtMs, _s0, reason: 'S-24408 at S0');
    expect(
      fixture[1].state,
      TimedState.active,
      reason: 'S-24408 the phone itself runs interval 1',
    );
    expect(
      fixture[1].startedAtMs,
      _s0 + 60000,
      reason: 'S-24408 a minute later',
    );

    var notifications = 0;
    state.addListener(() => notifications++);
    final revisionBefore = state.watchRefreshRevision;

    final changed = await state.releaseRemoteWorkTimer(effortId, _s0);

    expect(changed, isTrue, reason: 'S-24408 interval 0 is released');
    final memory = state.getTimedInstancesForEffort(effortId);
    expect(
      memory[0].state,
      TimedState.notStarted,
      reason: 'S-24408 interval 0 is not started again',
    );
    expect(memory[0].startedAtMs, 0, reason: 'S-24408 with no start');
    expect(
      memory[1].state,
      TimedState.active,
      reason: 'S-24408 interval 1 is untouched',
    );
    expect(
      memory[1].startedAtMs,
      _s0 + 60000,
      reason: 'S-24408 on its own start',
    );
    final stored = await repository.getTimedInstances(effortId);
    expect(
      stored[0].state,
      TimedState.notStarted,
      reason: 'S-24408 the stored interval 0 is not started too',
    );
    expect(
      stored[0].startedAtMs,
      0,
      reason: 'S-24408 the store keeps no start',
    );
    expect(
      stored[1].state,
      TimedState.active,
      reason: 'S-24408 the stored interval 1 is untouched',
    );
    expect(
      stored[1].startedAtMs,
      _s0 + 60000,
      reason: 'S-24408 on its own start in the store',
    );
    expect(notifications, 1, reason: 'S-24408 one notification');
    expect(
      state.watchRefreshRevision,
      revisionBefore + 1,
      reason: 'S-24408 the revision is bumped once',
    );
  });
}
