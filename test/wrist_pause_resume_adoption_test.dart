// Pausing or resuming a shared timer on the watch reaches the phone
// (126 P0a, red tests), through the phone's state rule alone.
//
// Plan: `docs/plans/2026-11-05-126-wrist-pause-resume-reaches-phone-plan/
// 2026-11-05-126-wrist-pause-resume-reaches-phone-plan.md`, the Decision
// Ledger D-1..D-7 and the first scenario table (S-12601..S-12615).
// Scenario mapping (fixtures use P, PS = P+30000, A0 = 0, A1 = 4000):
//   S-12601 a wrist pause of the running interval reaches it  → `S-12601 ...`
//   S-12602 a wrist resume reaches it                         → `S-12602 ...`
//   S-12603 a round's pause (a) and resume (b)                → `S-12603 pause`,
//     `S-12603 resume`
//   S-12604 a drill hold's pause then resume                  → `S-12604 ...`
//   S-12605 pause frames with starts inside the tolerance     →
//     `S-12605a ...` .. `S-12605d ...` (+400, -400, +1000, -1000; the ±1000
//     edges are inclusive)
//   S-12606 the stale pre-pause copies change nothing         →
//     `S-12606a running against an older paused copy ...`,
//     `S-12606b a pre-pause running copy ...`, `S-12606c an older running
//     copy ...`
//   S-12607 a second pause in the other direction loses the tie (D-5) →
//     `S-12607 ...`
//   S-12608 a resume of a timer that never paused here (a), the identical
//     copy (b)                                                → `S-12608a ...`,
//     `S-12608b ...`
//   S-12609 a restart-shaped pause later than the phone's     → `S-12609 ...`
//   S-12610 the pause adopts and other efforts' rests stay open (D-4) →
//     `S-12610 ...`
//   S-12611 the same pause frame twice is one write           → `S-12611 ...`
//   S-12612 a resume of a logged interval starts nothing (121b) → `S-12612 ...`
//   S-12613 a paused copy of a logged interval (121b, paused variant) →
//     `S-12613 ...`
//   S-12614 far starts keep today's behaviour: a far-later pause is refused,
//     a far-earlier pause overwrites (S-6102b / O-3)          → `S-12614a ...`,
//     `S-12614b ...`
//   S-12615 an earlier running start still wins (121b S-12159) → `S-12615 ...`
//
// Both groups run the same fixtures through the same state: after every
// scenario the stored repository rows must equal the memory rows (plan
// invariant "Mock and Hive hold identical rows"). Plain `test()`: a Hive
// write inside a widget test's fake-async zone never drains.

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

/// The phone interval's start (the plan's P).
final int _p = DateTime.utc(2026, 11, 5, 12, 0, 0).millisecondsSinceEpoch;

/// A pause stamp thirty seconds after P.
final int _ps = _p + 30000;

/// The plan's accumulated-pause values: none (A0) and one pause cycle (A1).
const int _a0 = 0;
const int _a1 = 4000;

/// The logged interval's start in the 121b fixtures (the plan's S0), far from
/// P so the logged-timer refusal cannot see P's intervals.
final int _s0 = DateTime.utc(2026, 11, 5, 9, 0, 0).millisecondsSinceEpoch;

/// A round plan unlike every default (`WorkoutConstants` uses seconds), so a
/// clobbered plan cannot pass the "rounds keep their planned length" asserts.
const int _roundOtherPlanMs = 75000;

const String _exerciseId = 'ex-run';

/// A row's identity for the "nothing changed" comparison: state, start, pause
/// stamp, accumulated pause and the planned/target length.
typedef _RowShape = (Object, int, int?, int, int?);

/// Stand-in for the path_provider platform channel, which has no
/// implementation under `flutter_test` (`HiveWorkoutRepository.initialize()`
/// calls `Hive.initFlutter()`). Same pattern as
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
/// [x], through the store, and re-reads it (the 121b "finished at X").
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

/// Rewrites the timed instance at [index] to [state_] with the pause
/// bookkeeping, through the store, and re-reads it.
Future<void> _setTimed(
  WorkoutState state,
  String effortId,
  int index, {
  required TimedState state_,
  required int startedAtMs,
  int? pausedAtMs,
  int totalPausedDurationMs = _a0,
}) async {
  final instance = state.getTimedInstancesForEffort(effortId)[index];
  await state.repository.updateTimedInstance(
    instance.copyWith(
      state: state_,
      startedAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
      pausedAtMs: pausedAtMs,
      totalPausedDurationMs: totalPausedDurationMs,
    ),
  );
  await state.refreshEfforts([effortId]);
}

/// Rewrites the round at [index] to [state_] with the pause bookkeeping,
/// through the store, and re-reads it.
Future<void> _setRound(
  WorkoutState state,
  String effortId,
  int index, {
  required RoundState state_,
  required int startedAtMs,
  int? pausedAtMs,
  int totalPausedDurationMs = _a0,
}) async {
  final round = state.getRoundsForEffort(effortId)[index];
  await state.repository.updateRoundInstance(
    round.copyWith(
      state: state_,
      startedAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
      pausedAtMs: pausedAtMs,
      totalPausedDurationMs: totalPausedDurationMs,
    ),
  );
  await state.refreshEfforts([effortId]);
}

/// The default timed fixture: one cardio interval the phone is running at P.
Future<(WorkoutState, String)> _timedRunning(
  WorkoutRepository repository,
) async {
  final (state, effortId) = await _session(repository, 'cardio_endurance');
  await state.startTimedEntry(effortId, 0);
  await _startAt(state, effortId, 0, _p);
  return (state, effortId);
}

/// The same interval paused at PS with [totalPausedDurationMs] accumulated.
Future<(WorkoutState, String)> _timedPaused(
  WorkoutRepository repository, {
  required int totalPausedDurationMs,
}) async {
  final (state, effortId) = await _timedRunning(repository);
  await _setTimed(
    state,
    effortId,
    0,
    state_: TimedState.paused,
    startedAtMs: _p,
    pausedAtMs: _ps,
    totalPausedDurationMs: totalPausedDurationMs,
  );
  return (state, effortId);
}

/// The default round fixture: one sports round the phone is running at P.
Future<(WorkoutState, String, int)> _roundRunning(
  WorkoutRepository repository,
) async {
  final (state, effortId) = await _session(repository, 'sports');
  await state.startRound(effortId, 0);
  final round = state.getRoundsForEffort(effortId).single;
  await state.repository.updateRoundInstance(
    round.copyWith(startedAtMs: _p, updatedAtMs: _p),
  );
  await state.refreshEfforts([effortId]);
  return (state, effortId, round.plannedDurationSecs);
}

/// The same round paused at PS with [totalPausedDurationMs] accumulated.
Future<(WorkoutState, String, int)> _roundPaused(
  WorkoutRepository repository, {
  required int totalPausedDurationMs,
}) async {
  final (state, effortId, planned) = await _roundRunning(repository);
  await _setRound(
    state,
    effortId,
    0,
    state_: RoundState.paused,
    startedAtMs: _p,
    pausedAtMs: _ps,
    totalPausedDurationMs: totalPausedDurationMs,
  );
  return (state, effortId, planned);
}

/// The default hold fixture: one drill hold the phone is running at P.
Future<(WorkoutState, String)> _holdRunning(
  WorkoutRepository repository,
) async {
  final (state, effortId) = await _session(repository, 'isometric_stretching');
  await state.startTimedEntry(effortId, 0);
  await _startAt(state, effortId, 0, _p);
  return (state, effortId);
}

/// The 121b fixture: two intervals, idx0 finished at S0, idx1 notStarted.
Future<(WorkoutState, String)> _loggedThenUnstarted(
  WorkoutRepository repository,
) async {
  final (state, effortId) = await _session(repository, 'cardio_endurance');
  await state.addEntry(effortId);
  await _finishTimedAt(state, effortId, 0, _s0);
  return (state, effortId);
}

/// The S-12610 fixture: two cardio efforts, B runs the phone's interval at P
/// (started before the rest exists: a start closes the session's rests), and
/// A holds one open rest behind its second entry.
Future<(WorkoutState, String, String)> _restOnAnotherEffort(
  WorkoutRepository repository,
) async {
  final state = WorkoutState(repository);
  await state.createNewSession(modality: 'cardio_endurance');
  final exercise = (await repository.getExercises()).firstWhere(
    (e) => e.id == _exerciseId,
  );
  final effortA = await state.addExerciseToSession(exercise);
  final effortB = await state.addExerciseToSession(exercise);
  await state.startTimedEntry(effortB, 0);
  await _startAt(state, effortB, 0, _p);
  await state.addEntry(effortA);
  await state.recordRestStart(effortA, 1);
  return (state, effortA, effortB);
}

List<_RowShape> _timedShape(Iterable<TimedInstance> rows) => [
  for (final r in rows)
    (
      r.state,
      r.startedAtMs,
      r.pausedAtMs,
      r.totalPausedDurationMs,
      r.targetDurationSecs,
    ),
];

List<_RowShape> _roundShape(Iterable<RoundInstance> rows) => [
  for (final r in rows)
    (
      r.state,
      r.startedAtMs,
      r.pausedAtMs,
      r.totalPausedDurationMs,
      r.plannedDurationSecs,
    ),
];

/// Asserts a refused adoption: `changed == false`, the memory and stored rows
/// still equal the fixture (state, startedAtMs, pausedAtMs), no revision bump,
/// no notification.
Future<void> _expectNothingChangedTimed(
  WorkoutState state,
  String effortId, {
  required bool changed,
  required List<_RowShape> memoryBefore,
  required List<_RowShape> storedBefore,
  required int revisionBefore,
  required int notifications,
  required String id,
}) async {
  expect(changed, isFalse, reason: '$id nothing changed');
  expect(
    _timedShape(state.getTimedInstancesForEffort(effortId)),
    memoryBefore,
    reason: '$id the memory rows still equal the fixture',
  );
  expect(
    _timedShape(await state.repository.getTimedInstances(effortId)),
    storedBefore,
    reason: '$id the stored rows still equal the fixture',
  );
  expect(
    state.watchRefreshRevision,
    revisionBefore,
    reason: '$id no revision bump for a no-op',
  );
  expect(notifications, 0, reason: '$id and no notification');
}

/// Asserts an adopted write reached the store: the stored rows equal the
/// memory rows the state now holds.
Future<void> _expectStoredMatchesMemoryTimed(
  WorkoutState state,
  String effortId, {
  required String id,
}) async {
  expect(
    _timedShape(await state.repository.getTimedInstances(effortId)),
    _timedShape(state.getTimedInstancesForEffort(effortId)),
    reason: '$id the stored rows match the memory rows',
  );
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
  final dir = await Directory.systemTemp.createTemp('wrist_pause_resume_');
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

  test('S-12601 a wrist pause of the running interval reaches it', () async {
    final (state, effortId) = await _timedRunning(repository);
    final before = state.getTimedInstancesForEffort(effortId).single;
    expect(before.state, TimedState.active, reason: 'S-12601 the fixture runs');
    expect(before.startedAtMs, _p, reason: 'S-12601 at P');
    expect(before.totalPausedDurationMs, _a0, reason: 'S-12601 with no pause');

    var notifications = 0;
    state.addListener(() => notifications++);
    final revisionBefore = state.watchRefreshRevision;

    final changed = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(
        wireKind: 'elapsed',
        startedAtMs: _p,
        pausedAtMs: _ps,
        accumulatedPauseMs: _a0,
      ),
    );

    final after = state.getTimedInstancesForEffort(effortId);
    expect(
      changed,
      isTrue,
      reason: 'S-12601 a same-start pause is the interval\'s own update',
    );
    expect(
      after.single.state,
      TimedState.paused,
      reason: 'S-12601 the wrist paused the interval',
    );
    expect(
      after.single.pausedAtMs,
      _ps,
      reason: 'S-12601 with the wrist\'s pause stamp',
    );
    expect(
      after.single.totalPausedDurationMs,
      _a0,
      reason: 'S-12601 and the wrist\'s accumulated pause',
    );
    expect(
      after.single.startedAtMs,
      _p,
      reason: 'S-12601 the phone keeps its own start (D-3)',
    );
    await _expectStoredMatchesMemoryTimed(state, effortId, id: 'S-12601');
    expect(state.watchRefreshRevision, revisionBefore + 1);
    expect(notifications, 1);
  });

  test('S-12602 a wrist resume of the paused interval reaches it', () async {
    final (state, effortId) = await _timedPaused(
      repository,
      totalPausedDurationMs: _a0,
    );
    final before = state.getTimedInstancesForEffort(effortId).single;
    expect(
      before.state,
      TimedState.paused,
      reason: 'S-12602 the fixture is paused at PS',
    );
    expect(before.pausedAtMs, _ps);

    var notifications = 0;
    state.addListener(() => notifications++);
    final revisionBefore = state.watchRefreshRevision;

    final changed = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(
        wireKind: 'elapsed',
        startedAtMs: _p,
        accumulatedPauseMs: _a1,
      ),
    );

    final after = state.getTimedInstancesForEffort(effortId);
    expect(
      changed,
      isTrue,
      reason: 'S-12602 a resume is newer than the phone\'s pause (D-2b)',
    );
    expect(
      after.single.state,
      TimedState.active,
      reason: 'S-12602 the wrist resumed the interval',
    );
    expect(
      after.single.pausedAtMs,
      isNull,
      reason: 'S-12602 a running remote leaves no pause stamp',
    );
    expect(
      after.single.totalPausedDurationMs,
      _a1,
      reason: 'S-12602 with the wrist\'s accumulated pause',
    );
    expect(
      after.single.startedAtMs,
      _p,
      reason: 'S-12602 the phone keeps its own start',
    );
    await _expectStoredMatchesMemoryTimed(state, effortId, id: 'S-12602');
    expect(state.watchRefreshRevision, revisionBefore + 1);
    expect(notifications, 1);
  });

  test('S-12603 pause: a wrist pause of the running round reaches it with the '
      'plan kept', () async {
    final (state, effortId, plannedBefore) = await _roundRunning(repository);
    final before = state.getRoundsForEffort(effortId).single;
    expect(before.state, RoundState.active, reason: 'S-12603 the fixture runs');

    var notifications = 0;
    state.addListener(() => notifications++);
    final revisionBefore = state.watchRefreshRevision;

    final changed = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(
        wireKind: 'round',
        startedAtMs: _p,
        pausedAtMs: _ps,
        accumulatedPauseMs: _a0,
        plannedDurationMs: _roundOtherPlanMs,
      ),
    );

    final after = state.getRoundsForEffort(effortId);
    expect(changed, isTrue, reason: 'S-12603 the same-start pause is news');
    expect(
      after.single.state,
      RoundState.paused,
      reason: 'S-12603 the wrist paused the round',
    );
    expect(after.single.pausedAtMs, _ps, reason: 'S-12603 the wrist\'s stamp');
    expect(
      after.single.totalPausedDurationMs,
      _a0,
      reason: 'S-12603 the wrist\'s accumulated pause',
    );
    expect(
      after.single.startedAtMs,
      _p,
      reason: 'S-12603 the phone keeps its own start',
    );
    expect(
      after.single.plannedDurationSecs,
      plannedBefore,
      reason: 'S-12603 rounds keep their planned length (D-3)',
    );
    expect(
      _roundShape(await state.repository.getRoundInstances(effortId)),
      _roundShape(after),
      reason: 'S-12603 the stored rows match the memory rows',
    );
    expect(state.watchRefreshRevision, revisionBefore + 1);
    expect(notifications, 1);
  });

  test('S-12603 resume: a wrist resume of the paused round reaches it with '
      'the plan kept', () async {
    final (state, effortId, plannedBefore) = await _roundPaused(
      repository,
      totalPausedDurationMs: _a0,
    );
    final before = state.getRoundsForEffort(effortId).single;
    expect(
      before.state,
      RoundState.paused,
      reason: 'S-12603 the fixture is paused at PS',
    );

    var notifications = 0;
    state.addListener(() => notifications++);
    final revisionBefore = state.watchRefreshRevision;

    final changed = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(
        wireKind: 'round',
        startedAtMs: _p,
        accumulatedPauseMs: _a1,
        plannedDurationMs: _roundOtherPlanMs,
      ),
    );

    final after = state.getRoundsForEffort(effortId);
    expect(changed, isTrue, reason: 'S-12603 the resume is newer');
    expect(
      after.single.state,
      RoundState.active,
      reason: 'S-12603 the wrist resumed the round',
    );
    expect(
      after.single.pausedAtMs,
      isNull,
      reason: 'S-12603 a running remote leaves no pause stamp',
    );
    expect(
      after.single.totalPausedDurationMs,
      _a1,
      reason: 'S-12603 the wrist\'s accumulated pause',
    );
    expect(
      after.single.plannedDurationSecs,
      plannedBefore,
      reason: 'S-12603 rounds keep their planned length (D-3)',
    );
    expect(
      _roundShape(await state.repository.getRoundInstances(effortId)),
      _roundShape(after),
      reason: 'S-12603 the stored rows match the memory rows',
    );
    expect(state.watchRefreshRevision, revisionBefore + 1);
    expect(notifications, 1);
  });

  test(
    'S-12604 a drill hold takes the wrist\'s pause and then its resume',
    () async {
      final (state, effortId) = await _holdRunning(repository);
      final before = state.getTimedInstancesForEffort(effortId).single;
      expect(
        before.state,
        TimedState.active,
        reason: 'S-12604 the fixture runs',
      );

      final pauseChanged = await state.adoptRemoteWorkTimer(
        effortId,
        RemoteWorkTimer(
          wireKind: 'hold',
          startedAtMs: _p,
          pausedAtMs: _ps,
          accumulatedPauseMs: _a0,
        ),
      );
      final paused = state.getTimedInstancesForEffort(effortId).single;
      expect(
        pauseChanged,
        isTrue,
        reason: 'S-12604 the same-start hold pause is news',
      );
      expect(
        paused.state,
        TimedState.paused,
        reason: 'S-12604 the wrist paused the hold',
      );
      expect(paused.pausedAtMs, _ps, reason: 'S-12604 the wrist\'s stamp');
      expect(
        paused.totalPausedDurationMs,
        _a0,
        reason: 'S-12604 the wrist\'s accumulated pause',
      );
      await _expectStoredMatchesMemoryTimed(state, effortId, id: 'S-12604');

      final resumeChanged = await state.adoptRemoteWorkTimer(
        effortId,
        RemoteWorkTimer(
          wireKind: 'hold',
          startedAtMs: _p,
          accumulatedPauseMs: _a1,
        ),
      );
      final resumed = state.getTimedInstancesForEffort(effortId).single;
      expect(resumeChanged, isTrue, reason: 'S-12604 the resume is newer');
      expect(
        resumed.state,
        TimedState.active,
        reason: 'S-12604 the wrist resumed the hold',
      );
      expect(
        resumed.pausedAtMs,
        isNull,
        reason: 'S-12604 a running remote leaves no pause stamp',
      );
      expect(
        resumed.totalPausedDurationMs,
        _a1,
        reason: 'S-12604 the wrist\'s accumulated pause',
      );
      await _expectStoredMatchesMemoryTimed(state, effortId, id: 'S-12604');
    },
  );

  test('S-12605a a pause frame P+400 after the start stays on the phone\'s '
      'own start', () async {
    final (state, effortId) = await _timedRunning(repository);

    var notifications = 0;
    state.addListener(() => notifications++);
    final revisionBefore = state.watchRefreshRevision;

    final changed = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(
        wireKind: 'elapsed',
        startedAtMs: _p + 400,
        pausedAtMs: _ps,
        accumulatedPauseMs: _a0,
      ),
    );

    final after = state.getTimedInstancesForEffort(effortId);
    expect(changed, isTrue, reason: 'S-12605a the tolerance edge is inclusive');
    expect(after.single.state, TimedState.paused, reason: 'S-12605a paused');
    expect(
      after.single.startedAtMs,
      _p,
      reason: 'S-12605a the phone keeps its own start (D-3)',
    );
    expect(after.single.pausedAtMs, _ps, reason: 'S-12605a the wrist\'s stamp');
    expect(
      after.single.totalPausedDurationMs,
      _a0,
      reason: 'S-12605a the wrist\'s accumulated pause',
    );
    await _expectStoredMatchesMemoryTimed(state, effortId, id: 'S-12605a');
    expect(state.watchRefreshRevision, revisionBefore + 1);
    expect(notifications, 1);
  });

  test('S-12605b a pause frame P-400 before the start wins on its earlier '
      'start', () async {
    final (state, effortId) = await _timedRunning(repository);

    var notifications = 0;
    state.addListener(() => notifications++);
    final revisionBefore = state.watchRefreshRevision;

    final changed = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(
        wireKind: 'elapsed',
        startedAtMs: _p - 400,
        pausedAtMs: _ps,
        accumulatedPauseMs: _a0,
      ),
    );

    final after = state.getTimedInstancesForEffort(effortId);
    expect(changed, isTrue, reason: 'S-12605b an earlier start wins');
    expect(after.single.state, TimedState.paused, reason: 'S-12605b paused');
    expect(
      after.single.startedAtMs,
      _p - 400,
      reason: 'S-12605b the remote\'s earlier start',
    );
    expect(after.single.pausedAtMs, _ps, reason: 'S-12605b the wrist\'s stamp');
    await _expectStoredMatchesMemoryTimed(state, effortId, id: 'S-12605b');
    expect(state.watchRefreshRevision, revisionBefore + 1);
    expect(notifications, 1);
  });

  test('S-12605c a pause frame P+1000 after the start is inside the '
      'inclusive tolerance', () async {
    final (state, effortId) = await _timedRunning(repository);

    var notifications = 0;
    state.addListener(() => notifications++);
    final revisionBefore = state.watchRefreshRevision;

    final changed = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(
        wireKind: 'elapsed',
        startedAtMs: _p + 1000,
        pausedAtMs: _ps,
        accumulatedPauseMs: _a0,
      ),
    );

    final after = state.getTimedInstancesForEffort(effortId);
    expect(changed, isTrue, reason: 'S-12605c the tolerance edge is inclusive');
    expect(after.single.state, TimedState.paused, reason: 'S-12605c paused');
    expect(
      after.single.startedAtMs,
      _p,
      reason: 'S-12605c the phone keeps its own start',
    );
    expect(
      after.single.totalPausedDurationMs,
      _a0,
      reason: 'S-12605c the wrist\'s accumulated pause',
    );
    await _expectStoredMatchesMemoryTimed(state, effortId, id: 'S-12605c');
    expect(state.watchRefreshRevision, revisionBefore + 1);
    expect(notifications, 1);
  });

  test('S-12605d a pause frame P-1000 before the start is inside the '
      'inclusive tolerance and wins on its earlier start', () async {
    final (state, effortId) = await _timedRunning(repository);

    var notifications = 0;
    state.addListener(() => notifications++);
    final revisionBefore = state.watchRefreshRevision;

    final changed = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(
        wireKind: 'elapsed',
        startedAtMs: _p - 1000,
        pausedAtMs: _ps,
        accumulatedPauseMs: _a0,
      ),
    );

    final after = state.getTimedInstancesForEffort(effortId);
    expect(changed, isTrue, reason: 'S-12605d the tolerance edge is inclusive');
    expect(after.single.state, TimedState.paused, reason: 'S-12605d paused');
    expect(
      after.single.startedAtMs,
      _p - 1000,
      reason: 'S-12605d the remote\'s earlier start',
    );
    await _expectStoredMatchesMemoryTimed(state, effortId, id: 'S-12605d');
    expect(state.watchRefreshRevision, revisionBefore + 1);
    expect(notifications, 1);
  });

  test('S-12606a a running interval against an older paused copy: nothing '
      'changed', () async {
    final (state, effortId) = await _timedRunning(repository);
    await _setTimed(
      state,
      effortId,
      0,
      state_: TimedState.active,
      startedAtMs: _p,
      totalPausedDurationMs: _a1,
    );
    final fixture = state.getTimedInstancesForEffort(effortId).single;
    expect(
      fixture.state,
      TimedState.active,
      reason: 'S-12606a the copied-over fixture runs with A1 accumulated',
    );
    expect(fixture.totalPausedDurationMs, _a1);

    final memoryBefore = _timedShape(
      state.getTimedInstancesForEffort(effortId),
    );
    final storedBefore = _timedShape(
      await state.repository.getTimedInstances(effortId),
    );
    var notifications = 0;
    state.addListener(() => notifications++);
    final revisionBefore = state.watchRefreshRevision;

    final changed = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(
        wireKind: 'elapsed',
        startedAtMs: _p,
        pausedAtMs: _ps,
        accumulatedPauseMs: _a0,
      ),
    );

    await _expectNothingChangedTimed(
      state,
      effortId,
      changed: changed,
      memoryBefore: memoryBefore,
      storedBefore: storedBefore,
      revisionBefore: revisionBefore,
      notifications: notifications,
      id: 'S-12606a',
    );
  });

  test('S-12606b a pre-pause running copy: nothing changed', () async {
    final (state, effortId) = await _timedPaused(
      repository,
      totalPausedDurationMs: _a1,
    );
    final fixture = state.getTimedInstancesForEffort(effortId).single;
    expect(
      fixture.state,
      TimedState.paused,
      reason: 'S-12606b the fixture is paused at PS with A1',
    );
    expect(fixture.totalPausedDurationMs, _a1);

    final memoryBefore = _timedShape(
      state.getTimedInstancesForEffort(effortId),
    );
    final storedBefore = _timedShape(
      await state.repository.getTimedInstances(effortId),
    );
    var notifications = 0;
    state.addListener(() => notifications++);
    final revisionBefore = state.watchRefreshRevision;

    final changed = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(
        wireKind: 'elapsed',
        startedAtMs: _p,
        accumulatedPauseMs: _a1,
      ),
    );

    await _expectNothingChangedTimed(
      state,
      effortId,
      changed: changed,
      memoryBefore: memoryBefore,
      storedBefore: storedBefore,
      revisionBefore: revisionBefore,
      notifications: notifications,
      id: 'S-12606b',
    );
  });

  test('S-12606c an older running copy: nothing changed', () async {
    final (state, effortId) = await _timedPaused(
      repository,
      totalPausedDurationMs: _a1,
    );

    final memoryBefore = _timedShape(
      state.getTimedInstancesForEffort(effortId),
    );
    final storedBefore = _timedShape(
      await state.repository.getTimedInstances(effortId),
    );
    var notifications = 0;
    state.addListener(() => notifications++);
    final revisionBefore = state.watchRefreshRevision;

    final changed = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(
        wireKind: 'elapsed',
        startedAtMs: _p,
        accumulatedPauseMs: 1000,
      ),
    );

    await _expectNothingChangedTimed(
      state,
      effortId,
      changed: changed,
      memoryBefore: memoryBefore,
      storedBefore: storedBefore,
      revisionBefore: revisionBefore,
      notifications: notifications,
      id: 'S-12606c',
    );
  });

  test('S-12607 a second pause on either side of the phone\'s stamp loses the '
      'tie (D-5)', () async {
    final (state, effortId) = await _timedPaused(
      repository,
      totalPausedDurationMs: _a0,
    );

    final memoryBefore = _timedShape(
      state.getTimedInstancesForEffort(effortId),
    );
    final storedBefore = _timedShape(
      await state.repository.getTimedInstances(effortId),
    );
    var notifications = 0;
    state.addListener(() => notifications++);
    final revisionBefore = state.watchRefreshRevision;

    final first = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(
        wireKind: 'elapsed',
        startedAtMs: _p,
        pausedAtMs: _ps - 5000,
        accumulatedPauseMs: _a0,
      ),
    );
    await _expectNothingChangedTimed(
      state,
      effortId,
      changed: first,
      memoryBefore: memoryBefore,
      storedBefore: storedBefore,
      revisionBefore: revisionBefore,
      notifications: notifications,
      id: 'S-12607 (earlier stamp)',
    );
    expect(
      state.getTimedInstancesForEffort(effortId).single.pausedAtMs,
      _ps,
      reason: 'S-12607 the phone\'s own pause stamp stays',
    );

    final second = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(
        wireKind: 'elapsed',
        startedAtMs: _p,
        pausedAtMs: _ps + 5000,
        accumulatedPauseMs: _a0,
      ),
    );
    await _expectNothingChangedTimed(
      state,
      effortId,
      changed: second,
      memoryBefore: memoryBefore,
      storedBefore: storedBefore,
      revisionBefore: revisionBefore,
      notifications: notifications,
      id: 'S-12607 (later stamp)',
    );
    expect(
      state.getTimedInstancesForEffort(effortId).single.pausedAtMs,
      _ps,
      reason: 'S-12607 the phone\'s own pause stamp still stays',
    );
  });

  test('S-12608a a running remote with a larger accumulated pause is a missed '
      'whole cycle and is accepted', () async {
    final (state, effortId) = await _timedRunning(repository);

    var notifications = 0;
    state.addListener(() => notifications++);
    final revisionBefore = state.watchRefreshRevision;

    final changed = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(
        wireKind: 'elapsed',
        startedAtMs: _p,
        accumulatedPauseMs: _a1,
      ),
    );

    final after = state.getTimedInstancesForEffort(effortId);
    expect(
      changed,
      isTrue,
      reason: 'S-12608a the larger accumulated pause is newer (D-2a)',
    );
    expect(
      after.single.state,
      TimedState.active,
      reason: 'S-12608a still runs',
    );
    expect(
      after.single.pausedAtMs,
      isNull,
      reason: 'S-12608a the remote runs again',
    );
    expect(
      after.single.totalPausedDurationMs,
      _a1,
      reason: 'S-12608a with the remote\'s accumulated pause',
    );
    expect(
      after.single.startedAtMs,
      _p,
      reason: 'S-12608a the phone keeps its own start',
    );
    await _expectStoredMatchesMemoryTimed(state, effortId, id: 'S-12608a');
    expect(state.watchRefreshRevision, revisionBefore + 1);
    expect(notifications, 1);
  });

  test('S-12608b a running remote with the same accumulated pause is the '
      'identical copy (S-6102c)', () async {
    final (state, effortId) = await _timedRunning(repository);

    final memoryBefore = _timedShape(
      state.getTimedInstancesForEffort(effortId),
    );
    final storedBefore = _timedShape(
      await state.repository.getTimedInstances(effortId),
    );
    var notifications = 0;
    state.addListener(() => notifications++);
    final revisionBefore = state.watchRefreshRevision;

    final changed = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(
        wireKind: 'elapsed',
        startedAtMs: _p,
        accumulatedPauseMs: _a0,
      ),
    );

    await _expectNothingChangedTimed(
      state,
      effortId,
      changed: changed,
      memoryBefore: memoryBefore,
      storedBefore: storedBefore,
      revisionBefore: revisionBefore,
      notifications: notifications,
      id: 'S-12608b',
    );
  });

  test('S-12609 a restart-shaped pause later than the phone\'s takes the '
      'wrist\'s bookkeeping', () async {
    final (state, effortId) = await _timedPaused(
      repository,
      totalPausedDurationMs: _a0,
    );

    var notifications = 0;
    state.addListener(() => notifications++);
    final revisionBefore = state.watchRefreshRevision;

    final changed = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(
        wireKind: 'elapsed',
        startedAtMs: _p,
        pausedAtMs: _ps + 60000,
        accumulatedPauseMs: _a1,
      ),
    );

    final after = state.getTimedInstancesForEffort(effortId);
    expect(
      changed,
      isTrue,
      reason: 'S-12609 the resume adding to the accumulated pause is newer',
    );
    expect(after.single.state, TimedState.paused, reason: 'S-12609 paused');
    expect(
      after.single.pausedAtMs,
      _ps + 60000,
      reason: 'S-12609 on the wrist\'s pause stamp',
    );
    expect(
      after.single.totalPausedDurationMs,
      _a1,
      reason: 'S-12609 with the wrist\'s accumulated pause',
    );
    expect(
      after.single.startedAtMs,
      _p,
      reason: 'S-12609 the phone keeps its own start',
    );
    await _expectStoredMatchesMemoryTimed(state, effortId, id: 'S-12609');
    expect(state.watchRefreshRevision, revisionBefore + 1);
    expect(notifications, 1);
  });

  test(
    'S-12610 the pause adopts and another effort\'s open rest stays open',
    () async {
      final (state, effortA, effortB) = await _restOnAnotherEffort(repository);
      expect(
        state.getTimedInstancesForEffort(effortB).single.startedAtMs,
        _p,
        reason: 'S-12610 the fixture runs on B',
      );
      expect(
        state.getEntryRests(effortA).single.restEndMs,
        isNull,
        reason: 'S-12610 the fixture is an open rest on A',
      );
      expect(
        (await repository.getEntryRests(effortA)).single.restEndMs,
        isNull,
        reason: 'S-12610 open in the store too',
      );

      var notifications = 0;
      state.addListener(() => notifications++);
      final revisionBefore = state.watchRefreshRevision;

      final changed = await state.adoptRemoteWorkTimer(
        effortB,
        RemoteWorkTimer(
          wireKind: 'elapsed',
          startedAtMs: _p,
          pausedAtMs: _ps,
          accumulatedPauseMs: _a0,
        ),
      );

      final bAfter = state.getTimedInstancesForEffort(effortB);
      expect(changed, isTrue, reason: 'S-12610 the pause is adopted');
      expect(
        bAfter.single.state,
        TimedState.paused,
        reason: 'S-12610 B is paused',
      );
      expect(bAfter.single.pausedAtMs, _ps);
      expect(bAfter.single.totalPausedDurationMs, _a0);
      await _expectStoredMatchesMemoryTimed(state, effortB, id: 'S-12610');

      // The pause is not a start: no rest of the session is touched (D-4).
      await pumpEventQueue();
      expect(
        state.getEntryRests(effortA).single.restEndMs,
        isNull,
        reason: 'S-12610 the rest on A stays open in memory',
      );
      expect(
        (await repository.getEntryRests(effortA)).single.restEndMs,
        isNull,
        reason: 'S-12610 and it stays open in the store',
      );
      expect(state.watchRefreshRevision, revisionBefore + 1);
      expect(notifications, 1);
    },
  );

  test('S-12611 the same wrist pause frame twice is one write', () async {
    final (state, effortId) = await _timedRunning(repository);

    var notifications = 0;
    state.addListener(() => notifications++);
    final revisionBefore = state.watchRefreshRevision;

    final pause = RemoteWorkTimer(
      wireKind: 'elapsed',
      startedAtMs: _p,
      pausedAtMs: _ps,
      accumulatedPauseMs: _a0,
    );

    final first = await state.adoptRemoteWorkTimer(effortId, pause);
    expect(first, isTrue, reason: 'S-12611 the first delivery writes');

    final second = await state.adoptRemoteWorkTimer(effortId, pause);
    expect(
      second,
      isFalse,
      reason: 'S-12611 the second delivery is the same state',
    );

    final after = state.getTimedInstancesForEffort(effortId).single;
    expect(after.state, TimedState.paused, reason: 'S-12611 paused once');
    expect(after.pausedAtMs, _ps);
    expect(after.totalPausedDurationMs, _a0);
    await _expectStoredMatchesMemoryTimed(state, effortId, id: 'S-12611');
    expect(
      state.watchRefreshRevision,
      revisionBefore + 1,
      reason: 'S-12611 one revision bump, not two',
    );
    expect(notifications, 1, reason: 'S-12611 one notification, not two');
  });

  test('S-12612 a resume of an interval the phone already logged starts '
      'nothing (121b)', () async {
    final (state, effortId) = await _loggedThenUnstarted(repository);
    _expectTimedFixture(state, effortId, [
      (TimedState.finished, _s0),
      (TimedState.notStarted, 0),
    ], 'S-12612');

    final memoryBefore = _timedShape(
      state.getTimedInstancesForEffort(effortId),
    );
    final storedBefore = _timedShape(
      await state.repository.getTimedInstances(effortId),
    );
    var notifications = 0;
    state.addListener(() => notifications++);
    final revisionBefore = state.watchRefreshRevision;

    final changed = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(
        wireKind: 'elapsed',
        startedAtMs: _s0,
        accumulatedPauseMs: _a1,
      ),
    );

    await _expectNothingChangedTimed(
      state,
      effortId,
      changed: changed,
      memoryBefore: memoryBefore,
      storedBefore: storedBefore,
      revisionBefore: revisionBefore,
      notifications: notifications,
      id: 'S-12612',
    );
    final after = state.getTimedInstancesForEffort(effortId);
    expect(after, hasLength(2), reason: 'S-12612 no interval is added');
    expect(
      after[1].state,
      TimedState.notStarted,
      reason: 'S-12612 the next interval is still unstarted',
    );
  });

  test('S-12613 a paused copy of an interval the phone already logged changes '
      'nothing (121b, paused variant)', () async {
    final (state, effortId) = await _loggedThenUnstarted(repository);
    await state.startTimedEntry(effortId, 1);
    await _startAt(state, effortId, 1, _p);
    _expectTimedFixture(state, effortId, [
      (TimedState.finished, _s0),
      (TimedState.active, _p),
    ], 'S-12613');

    final memoryBefore = _timedShape(
      state.getTimedInstancesForEffort(effortId),
    );
    final storedBefore = _timedShape(
      await state.repository.getTimedInstances(effortId),
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
        accumulatedPauseMs: _a0,
      ),
    );

    await _expectNothingChangedTimed(
      state,
      effortId,
      changed: changed,
      memoryBefore: memoryBefore,
      storedBefore: storedBefore,
      revisionBefore: revisionBefore,
      notifications: notifications,
      id: 'S-12613',
    );
    final after = state.getTimedInstancesForEffort(effortId);
    expect(
      after[1].state,
      TimedState.active,
      reason: 'S-12613 the phone\'s own interval still runs',
    );
    expect(
      after[1].startedAtMs,
      _p,
      reason: 'S-12613 on the phone\'s own start',
    );
  });

  test('S-12614a a far-later pause changes nothing (S-6102b)', () async {
    final (state, effortId) = await _timedRunning(repository);

    final memoryBefore = _timedShape(
      state.getTimedInstancesForEffort(effortId),
    );
    final storedBefore = _timedShape(
      await state.repository.getTimedInstances(effortId),
    );
    var notifications = 0;
    state.addListener(() => notifications++);
    final revisionBefore = state.watchRefreshRevision;

    final changed = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(
        wireKind: 'elapsed',
        startedAtMs: _p + 20000,
        pausedAtMs: _p + 25000,
        accumulatedPauseMs: _a0,
      ),
    );

    await _expectNothingChangedTimed(
      state,
      effortId,
      changed: changed,
      memoryBefore: memoryBefore,
      storedBefore: storedBefore,
      revisionBefore: revisionBefore,
      notifications: notifications,
      id: 'S-12614a',
    );
  });

  test('S-12614b a far-earlier pause overwrites paused (O-3)', () async {
    final (state, effortId) = await _timedRunning(repository);

    var notifications = 0;
    state.addListener(() => notifications++);
    final revisionBefore = state.watchRefreshRevision;

    final changed = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(
        wireKind: 'elapsed',
        startedAtMs: _p - 20000,
        pausedAtMs: _p - 10000,
        accumulatedPauseMs: _a0,
      ),
    );

    final after = state.getTimedInstancesForEffort(effortId);
    expect(
      changed,
      isTrue,
      reason: 'S-12614b the far-earlier start wins as today',
    );
    expect(
      after.single.state,
      TimedState.paused,
      reason: 'S-12614b overwritten paused',
    );
    expect(
      after.single.startedAtMs,
      _p - 20000,
      reason: 'S-12614b on the remote\'s earlier start',
    );
    expect(
      after.single.pausedAtMs,
      _p - 10000,
      reason: 'S-12614b with the remote\'s pause stamp',
    );
    await _expectStoredMatchesMemoryTimed(state, effortId, id: 'S-12614b');
    expect(state.watchRefreshRevision, revisionBefore + 1);
    expect(notifications, 1);
  });

  test(
    'S-12615 an earlier running remote start still wins (121b S-12159)',
    () async {
      final (state, effortId) = await _timedRunning(repository);

      var notifications = 0;
      state.addListener(() => notifications++);
      final revisionBefore = state.watchRefreshRevision;

      final changed = await state.adoptRemoteWorkTimer(
        effortId,
        RemoteWorkTimer(
          wireKind: 'elapsed',
          startedAtMs: _p - 500,
          accumulatedPauseMs: _a0,
        ),
      );

      final after = state.getTimedInstancesForEffort(effortId);
      expect(
        changed,
        isTrue,
        reason: 'S-12615 the earlier start wins as today',
      );
      expect(
        after.single.startedAtMs,
        _p - 500,
        reason: 'S-12615 on the earlier remote start',
      );
      expect(
        after.single.state,
        TimedState.active,
        reason: 'S-12615 still runs',
      );
      await _expectStoredMatchesMemoryTimed(state, effortId, id: 'S-12615');
      expect(state.watchRefreshRevision, revisionBefore + 1);
      expect(notifications, 1);
    },
  );
}

/// Asserts the effort's timed rows equal [expected] states and starts (the
/// 121b fixture check, copied).
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
