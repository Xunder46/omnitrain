// A watch clock whose start the phone already logged never starts the next
// interval (121b P0, red tests).
//
// Plan: `docs/plans/2026-11-05-121b-stale-watch-timer-adopted-into-next-interval-plan/
// 2026-11-05-121b-stale-watch-timer-adopted-into-next-interval-plan.md`,
// D-1 (the logged-timer rule), scenarios S-12151..S-12164.
// Scenario mapping:
//   S-12151 a stale running copy, next interval not started  → `S-12151 ...`
//   S-12152 a stale paused copy                              → `S-12152 ...`
//   S-12153 near twins (tolerance edge, fresh fixture each)  → `S-12153a ...`
//     .. `S-12153e ...`
//   S-12154 three intervals, the middle one finished         → `S-12154a ...`,
//     `S-12154b ...`
//   S-12155 round kind                                       → `S-12155a ...`,
//     `S-12155b ...`
//   S-12156 hold kind                                        → `S-12156 ...`
//   S-12157 the phone already started the next interval      → `S-12157 ...`
//   S-12158 the rest after the logged interval keeps counting → `S-12158 ...`
//   S-12159 earlier start wins on an in-progress interval    → `S-12159 ...`
//   S-12160 same start on another slot                       → `S-12160 ...`
//   S-12161 deleted / re-indexed interval                    → `S-12161a ...`,
//     `S-12161b ...`
//   S-12162 redelivery of the same stale timer               → `S-12162 ...`
//   S-12163 every interval finished, round (no growth)       → `S-12163 ...`
//   S-12164 growth just outside the tolerance                → `S-12164 ...`
//
// Both groups run the same fixtures through the same state: the refusal must
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

/// The logged interval's start (the plan's S0).
final int _s0 = DateTime.utc(2026, 11, 5, 9, 0, 0).millisecondsSinceEpoch;

/// The phone's own next start (the plan's P), three minutes after S0.
final int _p = _s0 + 180000;

const String _exerciseId = 'ex-run';

/// A row's identity for the "nothing changed" comparison: state, start and
/// pause stamp.
typedef _RowShape = (Object, int, int?);

/// Stand-in for the path_provider platform channel, which has no
/// implementation under `flutter_test` (`HiveWorkoutRepository.initialize()`
/// calls `Hive.initFlutter()`). Copied from
/// `test/remote_work_timer_state_test.dart`.
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

/// Moves a running timed instance's start to [startedAtMs] through the store
/// and re-reads it, so the state holds a fixture the phone itself wrote.
Future<void> _startAt(
  WorkoutState state,
  String effortId,
  int entryIndex,
  int startedAtMs,
) async {
  final instance = state.getTimedInstancesForEffort(effortId)[entryIndex];
  await state.repository.updateTimedInstance(
    instance.copyWith(startedAtMs: startedAtMs, updatedAtMs: startedAtMs),
  );
  await state.refreshEfforts([effortId]);
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

/// Rewrites the round at [index] to a finished round that began at [x],
/// through the store, and re-reads it (the plan's "finished at X" for rounds).
Future<void> _finishRoundAt(
  WorkoutState state,
  String effortId,
  int index,
  int x,
) async {
  final round = state.getRoundsForEffort(effortId)[index];
  await state.repository.updateRoundInstance(
    round.copyWith(
      state: RoundState.finished,
      startedAtMs: x,
      finishedAtMs: x + 60000,
      plannedDurationSecs: 60,
      actualDurationSecs: 60,
      completed: true,
    ),
  );
  await state.refreshEfforts([effortId]);
}

List<_RowShape> _timedShape(Iterable<TimedInstance> rows) => [
  for (final r in rows) (r.state, r.startedAtMs, r.pausedAtMs),
];

List<_RowShape> _roundShape(Iterable<RoundInstance> rows) => [
  for (final r in rows) (r.state, r.startedAtMs, r.pausedAtMs),
];

/// The S-12151 fixture: two intervals, idx0 finished at S0, idx1 notStarted.
Future<(WorkoutState, String)> _loggedThenUnstarted(
  WorkoutRepository repository,
) async {
  final (state, effortId) = await _session(repository, 'cardio_endurance');
  await state.addEntry(effortId);
  await _finishTimedAt(state, effortId, 0, _s0);
  return (state, effortId);
}

/// The S-12154 fixture: three intervals, the middle one finished at S0.
Future<(WorkoutState, String)> _middleLogged(
  WorkoutRepository repository,
) async {
  final (state, effortId) = await _session(repository, 'cardio_endurance');
  await state.addEntry(effortId);
  await state.addEntry(effortId);
  await _finishTimedAt(state, effortId, 1, _s0);
  return (state, effortId);
}

/// The S-12155 fixture: two rounds, r0 finished at S0, r1 notStarted.
Future<(WorkoutState, String)> _roundLoggedThenUnstarted(
  WorkoutRepository repository,
) async {
  final (state, effortId) = await _session(repository, 'sports');
  await state.addRound(effortId);
  await _finishRoundAt(state, effortId, 0, _s0);
  return (state, effortId);
}

/// Asserts the effort's timed rows equal [expected] states and starts.
void _expectTimedFixture(
  WorkoutState state,
  String effortId,
  List<(TimedState, int)> expected,
  String id,
) {
  final rows = state.getTimedInstancesForEffort(effortId);
  expect(
    rows.map((r) => r.state),
    expected.map((e) => e.$1),
    reason: '$id the fixture states',
  );
  expect(
    rows.map((r) => r.startedAtMs),
    expected.map((e) => e.$2),
    reason: '$id the fixture starts',
  );
}

/// Asserts the effort's round rows equal [expected] states and starts.
void _expectRoundFixture(
  WorkoutState state,
  String effortId,
  List<(RoundState, int)> expected,
  String id,
) {
  final rows = state.getRoundsForEffort(effortId);
  expect(
    rows.map((r) => r.state),
    expected.map((e) => e.$1),
    reason: '$id the fixture states',
  );
  expect(
    rows.map((r) => r.startedAtMs),
    expected.map((e) => e.$2),
    reason: '$id the fixture starts',
  );
}

/// Asserts a refused adoption: `changed == false`, the memory and stored rows
/// still equal the fixture (state, startedAtMs, pausedAtMs), no revision bump,
/// no notification.
Future<void> _expectRefusedTimed(
  WorkoutState state,
  String effortId, {
  required bool changed,
  required List<_RowShape> memoryBefore,
  required List<_RowShape> storedBefore,
  required int revisionBefore,
  required int notifications,
}) async {
  expect(changed, isFalse, reason: 'the phone already logged this start');
  expect(
    _timedShape(state.getTimedInstancesForEffort(effortId)),
    memoryBefore,
    reason: 'the memory rows still equal the fixture',
  );
  expect(
    _timedShape(await state.repository.getTimedInstances(effortId)),
    storedBefore,
    reason: 'the stored rows still equal the fixture',
  );
  expect(
    state.watchRefreshRevision,
    revisionBefore,
    reason: 'a refusal does not bump the revision',
  );
  expect(notifications, 0, reason: 'a refusal does not notify');
}

/// The round counterpart of [_expectRefusedTimed].
Future<void> _expectRefusedRound(
  WorkoutState state,
  String effortId, {
  required bool changed,
  required List<_RowShape> memoryBefore,
  required List<_RowShape> storedBefore,
  required int revisionBefore,
  required int notifications,
}) async {
  expect(changed, isFalse, reason: 'the phone already logged this start');
  expect(
    _roundShape(state.getRoundsForEffort(effortId)),
    memoryBefore,
    reason: 'the memory rows still equal the fixture',
  );
  expect(
    _roundShape(await state.repository.getRoundInstances(effortId)),
    storedBefore,
    reason: 'the stored rows still equal the fixture',
  );
  expect(
    state.watchRefreshRevision,
    revisionBefore,
    reason: 'a refusal does not bump the revision',
  );
  expect(notifications, 0, reason: 'a refusal does not notify');
}

void main() {
  group('Mock', () => _adoptionTests(open: _openMock, close: () async {}));
  group('Hive', () => _adoptionTests(open: _openHive, close: _closeHive));
}

Future<WorkoutRepository> _openMock() async {
  final repository = MockWorkoutRepository();
  await repository.initialize();
  await _seed(repository);
  return repository;
}

Directory? _hiveDir;

Future<WorkoutRepository> _openHive() async {
  final dir = await Directory.systemTemp.createTemp('stale_watch_timer_');
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

void _adoptionTests({
  required Future<WorkoutRepository> Function() open,
  required Future<void> Function() close,
}) {
  late WorkoutRepository repository;

  setUp(() async => repository = await open());
  tearDown(close);

  test(
    'S-12151 a stale running copy of a logged interval starts nothing',
    () async {
      final (state, effortId) = await _loggedThenUnstarted(repository);
      _expectTimedFixture(state, effortId, [
        (TimedState.finished, _s0),
        (TimedState.notStarted, 0),
      ], 'S-12151');

      final memoryBefore = _timedShape(
        state.getTimedInstancesForEffort(effortId),
      );
      final storedBefore = _timedShape(
        await repository.getTimedInstances(effortId),
      );
      var notifications = 0;
      state.addListener(() => notifications++);
      final revisionBefore = state.watchRefreshRevision;

      final changed = await state.adoptRemoteWorkTimer(
        effortId,
        RemoteWorkTimer(wireKind: 'elapsed', startedAtMs: _s0),
      );

      await _expectRefusedTimed(
        state,
        effortId,
        changed: changed,
        memoryBefore: memoryBefore,
        storedBefore: storedBefore,
        revisionBefore: revisionBefore,
        notifications: notifications,
      );
      final after = state.getTimedInstancesForEffort(effortId);
      expect(after, hasLength(2), reason: 'S-12151 no interval is added');
      expect(
        after[1].state,
        TimedState.notStarted,
        reason: 'S-12151 the next interval is still unstarted',
      );
      expect(
        after[1].startedAtMs,
        0,
        reason: 'S-12151 with no start of its own',
      );
    },
  );

  test(
    'S-12152 a stale paused copy of a logged interval starts nothing',
    () async {
      final (state, effortId) = await _loggedThenUnstarted(repository);
      _expectTimedFixture(state, effortId, [
        (TimedState.finished, _s0),
        (TimedState.notStarted, 0),
      ], 'S-12152');

      final memoryBefore = _timedShape(
        state.getTimedInstancesForEffort(effortId),
      );
      final storedBefore = _timedShape(
        await repository.getTimedInstances(effortId),
      );
      var notifications = 0;
      state.addListener(() => notifications++);
      final revisionBefore = state.watchRefreshRevision;

      final changed = await state.adoptRemoteWorkTimer(
        effortId,
        RemoteWorkTimer(
          wireKind: 'elapsed',
          startedAtMs: _s0,
          pausedAtMs: _s0 + 30000,
          accumulatedPauseMs: 0,
        ),
      );

      await _expectRefusedTimed(
        state,
        effortId,
        changed: changed,
        memoryBefore: memoryBefore,
        storedBefore: storedBefore,
        revisionBefore: revisionBefore,
        notifications: notifications,
      );
      final after = state.getTimedInstancesForEffort(effortId);
      expect(
        after[1].state,
        TimedState.notStarted,
        reason: 'S-12152 the next interval is still unstarted',
      );
      expect(after[1].startedAtMs, 0, reason: 'S-12152 with no start');
      expect(after[1].pausedAtMs, isNull, reason: 'S-12152 and not paused');
    },
  );

  test(
    'S-12153a a start 400 ms after the logged one is within the tolerance',
    () async {
      final (state, effortId) = await _loggedThenUnstarted(repository);
      _expectTimedFixture(state, effortId, [
        (TimedState.finished, _s0),
        (TimedState.notStarted, 0),
      ], 'S-12153a');

      final memoryBefore = _timedShape(
        state.getTimedInstancesForEffort(effortId),
      );
      final storedBefore = _timedShape(
        await repository.getTimedInstances(effortId),
      );
      var notifications = 0;
      state.addListener(() => notifications++);
      final revisionBefore = state.watchRefreshRevision;

      final changed = await state.adoptRemoteWorkTimer(
        effortId,
        RemoteWorkTimer(wireKind: 'elapsed', startedAtMs: _s0 + 400),
      );

      await _expectRefusedTimed(
        state,
        effortId,
        changed: changed,
        memoryBefore: memoryBefore,
        storedBefore: storedBefore,
        revisionBefore: revisionBefore,
        notifications: notifications,
      );
    },
  );

  test(
    'S-12153b a start 400 ms before the logged one is within the tolerance',
    () async {
      final (state, effortId) = await _loggedThenUnstarted(repository);
      _expectTimedFixture(state, effortId, [
        (TimedState.finished, _s0),
        (TimedState.notStarted, 0),
      ], 'S-12153b');

      final memoryBefore = _timedShape(
        state.getTimedInstancesForEffort(effortId),
      );
      final storedBefore = _timedShape(
        await repository.getTimedInstances(effortId),
      );
      var notifications = 0;
      state.addListener(() => notifications++);
      final revisionBefore = state.watchRefreshRevision;

      final changed = await state.adoptRemoteWorkTimer(
        effortId,
        RemoteWorkTimer(wireKind: 'elapsed', startedAtMs: _s0 - 400),
      );

      await _expectRefusedTimed(
        state,
        effortId,
        changed: changed,
        memoryBefore: memoryBefore,
        storedBefore: storedBefore,
        revisionBefore: revisionBefore,
        notifications: notifications,
      );
    },
  );

  test('S-12153c a start 1000 ms after the logged one is still within the '
      'tolerance', () async {
    final (state, effortId) = await _loggedThenUnstarted(repository);
    _expectTimedFixture(state, effortId, [
      (TimedState.finished, _s0),
      (TimedState.notStarted, 0),
    ], 'S-12153c');

    final memoryBefore = _timedShape(
      state.getTimedInstancesForEffort(effortId),
    );
    final storedBefore = _timedShape(
      await repository.getTimedInstances(effortId),
    );
    var notifications = 0;
    state.addListener(() => notifications++);
    final revisionBefore = state.watchRefreshRevision;

    final changed = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(wireKind: 'elapsed', startedAtMs: _s0 + 1000),
    );

    await _expectRefusedTimed(
      state,
      effortId,
      changed: changed,
      memoryBefore: memoryBefore,
      storedBefore: storedBefore,
      revisionBefore: revisionBefore,
      notifications: notifications,
    );
  });

  test(
    'S-12153d a start 1001 ms after the logged one adopts the next interval',
    () async {
      final (state, effortId) = await _loggedThenUnstarted(repository);
      _expectTimedFixture(state, effortId, [
        (TimedState.finished, _s0),
        (TimedState.notStarted, 0),
      ], 'S-12153d');

      final revisionBefore = state.watchRefreshRevision;

      final changed = await state.adoptRemoteWorkTimer(
        effortId,
        RemoteWorkTimer(wireKind: 'elapsed', startedAtMs: _s0 + 1001),
      );

      final after = state.getTimedInstancesForEffort(effortId);
      expect(
        changed,
        isTrue,
        reason: 'S-12153d 1001 ms is outside the tolerance',
      );
      expect(
        after[1].state,
        TimedState.active,
        reason: 'S-12153d the next interval runs',
      );
      expect(
        after[1].startedAtMs,
        _s0 + 1001,
        reason: 'S-12153d on the remote start',
      );
      expect(after[1].pausedAtMs, isNull, reason: 'S-12153d a running remote');
      expect(
        after[0].state,
        TimedState.finished,
        reason: 'S-12153d the logged interval is untouched',
      );
      expect(after[0].startedAtMs, _s0);
      expect(
        _timedShape(await repository.getTimedInstances(effortId)),
        _timedShape(after),
        reason: 'S-12153d the stored rows match the memory rows',
      );
      expect(
        state.watchRefreshRevision,
        revisionBefore + 1,
        reason: 'S-12153d the adoption bumps the revision once',
      );
    },
  );

  test(
    'S-12153e a start 5000 ms after the logged one adopts the next interval',
    () async {
      final (state, effortId) = await _loggedThenUnstarted(repository);
      _expectTimedFixture(state, effortId, [
        (TimedState.finished, _s0),
        (TimedState.notStarted, 0),
      ], 'S-12153e');

      final changed = await state.adoptRemoteWorkTimer(
        effortId,
        RemoteWorkTimer(wireKind: 'elapsed', startedAtMs: _s0 + 5000),
      );

      final after = state.getTimedInstancesForEffort(effortId);
      expect(changed, isTrue, reason: 'S-12153e a plainly later start adopts');
      expect(after[1].state, TimedState.active, reason: 'S-12153e it runs');
      expect(
        after[1].startedAtMs,
        _s0 + 5000,
        reason: 'S-12153e on the remote start',
      );
      expect(
        _timedShape(await repository.getTimedInstances(effortId)),
        _timedShape(after),
        reason: 'S-12153e the stored rows match the memory rows',
      );
    },
  );

  test(
    'S-12154a a remote start matching the middle interval starts nothing',
    () async {
      final (state, effortId) = await _middleLogged(repository);
      _expectTimedFixture(state, effortId, [
        (TimedState.notStarted, 0),
        (TimedState.finished, _s0),
        (TimedState.notStarted, 0),
      ], 'S-12154a');

      final memoryBefore = _timedShape(
        state.getTimedInstancesForEffort(effortId),
      );
      final storedBefore = _timedShape(
        await repository.getTimedInstances(effortId),
      );
      var notifications = 0;
      state.addListener(() => notifications++);
      final revisionBefore = state.watchRefreshRevision;

      final changed = await state.adoptRemoteWorkTimer(
        effortId,
        RemoteWorkTimer(wireKind: 'elapsed', startedAtMs: _s0),
      );

      await _expectRefusedTimed(
        state,
        effortId,
        changed: changed,
        memoryBefore: memoryBefore,
        storedBefore: storedBefore,
        revisionBefore: revisionBefore,
        notifications: notifications,
      );
      final after = state.getTimedInstancesForEffort(effortId);
      expect(
        after[0].state,
        TimedState.notStarted,
        reason: 'S-12154a the first interval is still unstarted',
      );
      expect(
        after[2].state,
        TimedState.notStarted,
        reason: 'S-12154a so is the last',
      );
    },
  );

  test('S-12154b a new start adopts the first not-finished interval', () async {
    final (state, effortId) = await _middleLogged(repository);
    _expectTimedFixture(state, effortId, [
      (TimedState.notStarted, 0),
      (TimedState.finished, _s0),
      (TimedState.notStarted, 0),
    ], 'S-12154b');

    final changed = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(wireKind: 'elapsed', startedAtMs: _s0 + 5000),
    );

    final after = state.getTimedInstancesForEffort(effortId);
    expect(changed, isTrue, reason: 'S-12154b a new start adopts');
    expect(
      after[0].state,
      TimedState.active,
      reason: 'S-12154b the first not-finished interval is the target',
    );
    expect(
      after[0].startedAtMs,
      _s0 + 5000,
      reason: 'S-12154b on the remote start',
    );
    expect(
      after[2].state,
      TimedState.notStarted,
      reason: 'S-12154b the last interval is untouched',
    );
    expect(
      _timedShape(await repository.getTimedInstances(effortId)),
      _timedShape(after),
      reason: 'S-12154b the stored rows match the memory rows',
    );
  });

  test(
    'S-12155a a stale round copy of a logged round starts nothing',
    () async {
      final (state, effortId) = await _roundLoggedThenUnstarted(repository);
      _expectRoundFixture(state, effortId, [
        (RoundState.finished, _s0),
        (RoundState.notStarted, 0),
      ], 'S-12155a');

      final memoryBefore = _roundShape(state.getRoundsForEffort(effortId));
      final storedBefore = _roundShape(
        await repository.getRoundInstances(effortId),
      );
      var notifications = 0;
      state.addListener(() => notifications++);
      final revisionBefore = state.watchRefreshRevision;

      final changed = await state.adoptRemoteWorkTimer(
        effortId,
        RemoteWorkTimer(
          wireKind: 'round',
          startedAtMs: _s0,
          plannedDurationMs: 60000,
        ),
      );

      await _expectRefusedRound(
        state,
        effortId,
        changed: changed,
        memoryBefore: memoryBefore,
        storedBefore: storedBefore,
        revisionBefore: revisionBefore,
        notifications: notifications,
      );
      final after = state.getRoundsForEffort(effortId);
      expect(
        after[1].state,
        RoundState.notStarted,
        reason: 'S-12155a the next round is still unstarted',
      );
      expect(after[1].startedAtMs, 0, reason: 'S-12155a with no start');
    },
  );

  test('S-12155b a new round start adopts the unstarted round', () async {
    final (state, effortId) = await _roundLoggedThenUnstarted(repository);
    _expectRoundFixture(state, effortId, [
      (RoundState.finished, _s0),
      (RoundState.notStarted, 0),
    ], 'S-12155b');

    final changed = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(
        wireKind: 'round',
        startedAtMs: _s0 + 5000,
        plannedDurationMs: 60000,
      ),
    );

    final after = state.getRoundsForEffort(effortId);
    expect(changed, isTrue, reason: 'S-12155b a new start adopts');
    expect(
      after[1].state,
      RoundState.active,
      reason: 'S-12155b the round runs',
    );
    expect(
      after[1].startedAtMs,
      _s0 + 5000,
      reason: 'S-12155b on the remote start',
    );
    expect(
      after[1].plannedDurationSecs,
      60,
      reason: 'S-12155b the remote plan is carried over in seconds',
    );
    expect(
      _roundShape(await repository.getRoundInstances(effortId)),
      _roundShape(after),
      reason: 'S-12155b the stored rows match the memory rows',
    );
  });

  test('S-12156 a stale hold copy of a logged drill starts nothing', () async {
    final (state, effortId) = await _session(
      repository,
      'isometric_stretching',
    );
    await state.addEntry(effortId);
    await _finishTimedAt(state, effortId, 0, _s0);
    _expectTimedFixture(state, effortId, [
      (TimedState.finished, _s0),
      (TimedState.notStarted, 0),
    ], 'S-12156');

    final memoryBefore = _timedShape(
      state.getTimedInstancesForEffort(effortId),
    );
    final storedBefore = _timedShape(
      await repository.getTimedInstances(effortId),
    );
    var notifications = 0;
    state.addListener(() => notifications++);
    final revisionBefore = state.watchRefreshRevision;

    final changed = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(wireKind: 'hold', startedAtMs: _s0),
    );

    await _expectRefusedTimed(
      state,
      effortId,
      changed: changed,
      memoryBefore: memoryBefore,
      storedBefore: storedBefore,
      revisionBefore: revisionBefore,
      notifications: notifications,
    );
    final after = state.getTimedInstancesForEffort(effortId);
    expect(
      after[1].state,
      TimedState.notStarted,
      reason: 'S-12156 the next hold is still unstarted',
    );
    expect(after[1].startedAtMs, 0, reason: 'S-12156 with no start');
  });

  test('S-12157 a stale copy does not rewind the interval the phone started '
      'itself', () async {
    final (state, effortId) = await _loggedThenUnstarted(repository);
    await state.startTimedEntry(effortId, 1);
    await _startAt(state, effortId, 1, _p);
    _expectTimedFixture(state, effortId, [
      (TimedState.finished, _s0),
      (TimedState.active, _p),
    ], 'S-12157');

    final memoryBefore = _timedShape(
      state.getTimedInstancesForEffort(effortId),
    );
    final storedBefore = _timedShape(
      await repository.getTimedInstances(effortId),
    );
    var notifications = 0;
    state.addListener(() => notifications++);
    final revisionBefore = state.watchRefreshRevision;

    final changed = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(wireKind: 'elapsed', startedAtMs: _s0),
    );

    await _expectRefusedTimed(
      state,
      effortId,
      changed: changed,
      memoryBefore: memoryBefore,
      storedBefore: storedBefore,
      revisionBefore: revisionBefore,
      notifications: notifications,
    );
    final after = state.getTimedInstancesForEffort(effortId);
    expect(
      after[1].state,
      TimedState.active,
      reason: 'S-12157 the phone\'s own interval still runs',
    );
    expect(
      after[1].startedAtMs,
      _p,
      reason: 'S-12157 on its own start, not the stale one',
    );
  });

  test('S-12158 the rest after the logged interval keeps counting', () async {
    final (state, effortId) = await _loggedThenUnstarted(repository);
    await state.recordRestStart(effortId, 1);
    _expectTimedFixture(state, effortId, [
      (TimedState.finished, _s0),
      (TimedState.notStarted, 0),
    ], 'S-12158');
    expect(
      state.getEntryRests(effortId).single.restEndMs,
      isNull,
      reason: 'S-12158 the fixture is an open rest',
    );
    expect(
      (await repository.getEntryRests(effortId)).single.restEndMs,
      isNull,
      reason: 'S-12158 open in the store too',
    );

    final memoryBefore = _timedShape(
      state.getTimedInstancesForEffort(effortId),
    );
    final storedBefore = _timedShape(
      await repository.getTimedInstances(effortId),
    );
    var notifications = 0;
    state.addListener(() => notifications++);
    final revisionBefore = state.watchRefreshRevision;

    final changed = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(wireKind: 'elapsed', startedAtMs: _s0),
    );

    await _expectRefusedTimed(
      state,
      effortId,
      changed: changed,
      memoryBefore: memoryBefore,
      storedBefore: storedBefore,
      revisionBefore: revisionBefore,
      notifications: notifications,
    );
    expect(
      state.getEntryRests(effortId).single.restEndMs,
      isNull,
      reason: 'S-12158 the rest is still open in memory',
    );
    // `_persistClosedRests` does not await its write.
    await pumpEventQueue();
    expect(
      (await repository.getEntryRests(effortId)).single.restEndMs,
      isNull,
      reason: 'S-12158 the rest is still open in the store',
    );
  });

  test('S-12159 an earlier start wins on an in-progress interval within the '
      'tolerance', () async {
    final (state, effortId) = await _session(repository, 'cardio_endurance');
    await state.startTimedEntry(effortId, 0);
    await _startAt(state, effortId, 0, _p);
    _expectTimedFixture(state, effortId, [(TimedState.active, _p)], 'S-12159');

    final changed = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(wireKind: 'elapsed', startedAtMs: _p - 500),
    );

    final after = state.getTimedInstancesForEffort(effortId);
    expect(
      changed,
      isTrue,
      reason: 'S-12159 the earlier-start rule looks at in-progress intervals',
    );
    expect(after.single.state, TimedState.active, reason: 'S-12159 still runs');
    expect(
      after.single.startedAtMs,
      _p - 500,
      reason: 'S-12159 on the earlier remote start',
    );
    expect(
      _timedShape(await repository.getTimedInstances(effortId)),
      _timedShape(after),
      reason: 'S-12159 the stored rows match the memory rows',
    );
  });

  test(
    'S-12160 the same start on another effort\'s slot adopts that slot',
    () async {
      final state = WorkoutState(repository);
      await state.createNewSession(modality: 'cardio_endurance');
      final exercise = (await repository.getExercises()).firstWhere(
        (e) => e.id == _exerciseId,
      );
      final effortA = await state.addExerciseToSession(exercise);
      final effortB = await state.addExerciseToSession(exercise);
      await _finishTimedAt(state, effortA, 0, _s0);
      _expectTimedFixture(state, effortA, [
        (TimedState.finished, _s0),
      ], 'S-12160 (A)');
      _expectTimedFixture(state, effortB, [
        (TimedState.notStarted, 0),
      ], 'S-12160 (B)');

      final aMemoryBefore = _timedShape(
        state.getTimedInstancesForEffort(effortA),
      );
      final aStoredBefore = _timedShape(
        await repository.getTimedInstances(effortA),
      );

      final changed = await state.adoptRemoteWorkTimer(
        effortB,
        RemoteWorkTimer(wireKind: 'elapsed', startedAtMs: _s0),
      );

      final afterB = state.getTimedInstancesForEffort(effortB);
      expect(
        changed,
        isTrue,
        reason: 'S-12160 another effort\'s log does not block this slot',
      );
      expect(
        afterB.single.state,
        TimedState.active,
        reason: 'S-12160 B\'s interval runs',
      );
      expect(
        afterB.single.startedAtMs,
        _s0,
        reason: 'S-12160 on the remote start',
      );
      expect(
        _timedShape(await repository.getTimedInstances(effortB)),
        _timedShape(afterB),
        reason: 'S-12160 the stored rows match the memory rows',
      );
      expect(
        _timedShape(state.getTimedInstancesForEffort(effortA)),
        aMemoryBefore,
        reason: 'S-12160 A\'s memory rows are untouched',
      );
      expect(
        _timedShape(await repository.getTimedInstances(effortA)),
        aStoredBefore,
        reason: 'S-12160 A\'s stored rows are untouched',
      );
    },
  );

  test('S-12161a a start matching the re-indexed logged interval starts '
      'nothing', () async {
    final (state, effortId) = await _middleLogged(repository);
    await state.deleteTimedEntry(effortId, 0);
    _expectTimedFixture(state, effortId, [
      (TimedState.finished, _s0),
      (TimedState.notStarted, 0),
    ], 'S-12161a');

    final memoryBefore = _timedShape(
      state.getTimedInstancesForEffort(effortId),
    );
    final storedBefore = _timedShape(
      await repository.getTimedInstances(effortId),
    );
    var notifications = 0;
    state.addListener(() => notifications++);
    final revisionBefore = state.watchRefreshRevision;

    final changed = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(wireKind: 'elapsed', startedAtMs: _s0),
    );

    await _expectRefusedTimed(
      state,
      effortId,
      changed: changed,
      memoryBefore: memoryBefore,
      storedBefore: storedBefore,
      revisionBefore: revisionBefore,
      notifications: notifications,
    );
    final after = state.getTimedInstancesForEffort(effortId);
    expect(
      after[1].state,
      TimedState.notStarted,
      reason: 'S-12161a the interval after the re-indexed log is unstarted',
    );
    expect(after[1].startedAtMs, 0, reason: 'S-12161a with no start');
  });

  test('S-12161b a start whose logged interval was deleted adopts', () async {
    final (state, effortId) = await _loggedThenUnstarted(repository);
    await state.deleteTimedEntry(effortId, 0);
    _expectTimedFixture(state, effortId, [
      (TimedState.notStarted, 0),
    ], 'S-12161b');

    final changed = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(wireKind: 'elapsed', startedAtMs: _s0),
    );

    final after = state.getTimedInstancesForEffort(effortId);
    expect(
      changed,
      isTrue,
      reason: 'S-12161b a deleted log is not remembered (D-3)',
    );
    expect(after.single.state, TimedState.active, reason: 'S-12161b it runs');
    expect(
      after.single.startedAtMs,
      _s0,
      reason: 'S-12161b on the remote start',
    );
    expect(
      _timedShape(await repository.getTimedInstances(effortId)),
      _timedShape(after),
      reason: 'S-12161b the stored rows match the memory rows',
    );
  });

  test('S-12162 a redelivered stale timer is refused again', () async {
    final (state, effortId) = await _loggedThenUnstarted(repository);
    _expectTimedFixture(state, effortId, [
      (TimedState.finished, _s0),
      (TimedState.notStarted, 0),
    ], 'S-12162');

    final memoryBefore = _timedShape(
      state.getTimedInstancesForEffort(effortId),
    );
    final storedBefore = _timedShape(
      await repository.getTimedInstances(effortId),
    );
    var notifications = 0;
    state.addListener(() => notifications++);
    final revisionBefore = state.watchRefreshRevision;

    final first = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(wireKind: 'elapsed', startedAtMs: _s0),
    );
    await _expectRefusedTimed(
      state,
      effortId,
      changed: first,
      memoryBefore: memoryBefore,
      storedBefore: storedBefore,
      revisionBefore: revisionBefore,
      notifications: notifications,
    );

    final second = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(wireKind: 'elapsed', startedAtMs: _s0),
    );
    await _expectRefusedTimed(
      state,
      effortId,
      changed: second,
      memoryBefore: memoryBefore,
      storedBefore: storedBefore,
      revisionBefore: revisionBefore,
      notifications: notifications,
    );
  });

  test(
    'S-12163 every round finished: a matching remote grows nothing',
    () async {
      final (state, effortId) = await _session(repository, 'sports');
      await _finishRoundAt(state, effortId, 0, _s0);
      _expectRoundFixture(state, effortId, [
        (RoundState.finished, _s0),
      ], 'S-12163');

      final memoryBefore = _roundShape(state.getRoundsForEffort(effortId));
      final storedBefore = _roundShape(
        await repository.getRoundInstances(effortId),
      );
      var notifications = 0;
      state.addListener(() => notifications++);
      final revisionBefore = state.watchRefreshRevision;

      final changed = await state.adoptRemoteWorkTimer(
        effortId,
        RemoteWorkTimer(wireKind: 'round', startedAtMs: _s0),
      );

      await _expectRefusedRound(
        state,
        effortId,
        changed: changed,
        memoryBefore: memoryBefore,
        storedBefore: storedBefore,
        revisionBefore: revisionBefore,
        notifications: notifications,
      );
      expect(
        state.getRoundsForEffort(effortId),
        hasLength(1),
        reason: 'S-12163 no round is added',
      );
    },
  );

  test('S-12164 a start just outside the tolerance grows the effort', () async {
    final (state, effortId) = await _session(repository, 'cardio_endurance');
    await _finishTimedAt(state, effortId, 0, _s0);
    _expectTimedFixture(state, effortId, [
      (TimedState.finished, _s0),
    ], 'S-12164');

    final revisionBefore = state.watchRefreshRevision;

    final changed = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(wireKind: 'elapsed', startedAtMs: _s0 + 1001),
    );

    final after = state.getTimedInstancesForEffort(effortId);
    expect(
      changed,
      isTrue,
      reason: 'S-12164 1001 ms is outside the tolerance, so the effort grows',
    );
    expect(after, hasLength(2), reason: 'S-12164 one interval is added');
    expect(
      after[1].state,
      TimedState.active,
      reason: 'S-12164 the new interval runs',
    );
    expect(
      after[1].startedAtMs,
      _s0 + 1001,
      reason: 'S-12164 on the remote start',
    );
    expect(
      _timedShape(await repository.getTimedInstances(effortId)),
      _timedShape(after),
      reason: 'S-12164 the stored rows match the memory rows',
    );
    expect(
      state.watchRefreshRevision,
      revisionBefore + 1,
      reason: 'S-12164 the grow bumps the revision once',
    );
  });
}
