// A timer started on the watch is adopted by the phone's interval (43b2 P1).
//
// Plan: `docs/plans/2026-10-20-43b2-shared-timer-phone-receives-plan/
// 2026-10-20-43b2-shared-timer-phone-receives-plan.md`, D-1 (the target
// interval), D-2 (how the adoption writes), scenarios S-6101..S-6106.
// Scenario mapping:
//   S-6101 a notStarted interval adopts the remote start        → `S-6101 ...`,
//     `S-6101 adopting ...`, `S-6101 adopting a round ...`
//   S-6102 the earlier start wins                               → `S-6102a ...`,
//     `S-6102b ...`, `S-6102c ...`, `S-6102 round: ...`
//   S-6103 kind pairing and an unknown effort                    → `S-6103a ...`,
//     `S-6103b ...`, `S-6103c ...`, `S-6103d ...`
//   S-6104 a paused remote                                      → `S-6104a ...`,
//     `S-6104b ...`, `S-6104 a round ...`
//   S-6105 every interval finished                              → `S-6105 ...`
//   S-6106 the in-progress interval is the target               → `S-6106 ...`
//
// Both groups run the same fixtures through the same state: the adoption must
// write the same rows under `HiveWorkoutRepository` and
// `MockWorkoutRepository`. Plain `test()`: a Hive write inside a widget test's
// fake-async zone never drains.

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

/// The remote timer's start, unlike every default and earlier than the phone's
/// own (S-6102 writes the phone's at [_phoneStartedMs]).
final int _tMs = DateTime.utc(2026, 10, 5, 10, 17, 23).millisecondsSinceEpoch;

/// The fixture's pause bookkeeping: unlike 0, so a hard-coded value fails.
const int _accumulatedPauseMs = 7000;

/// A pause twelve seconds after [_tMs] — logically after the start, and later
/// than the phone's own start so an adopting write keeps a sane order.
final int _pausedAtMs = _tMs + 12000;

/// The phone's own start, ten seconds after the watch's.
final int _phoneStartedMs = _tMs + 10000;

/// A round plan unlike every default (`WorkoutConstants` uses seconds, not
/// this), 75 s on the wire.
const int _roundPlanMs = 75000;
const int _roundPlanSecs = 75;

const String _exerciseId = 'ex-run';

/// Stand-in for the path_provider platform channel, which has no
/// implementation under `flutter_test` (`HiveWorkoutRepository.initialize()`
/// calls `Hive.initFlutter()`). Same pattern as `test/watch_timed_fill_test.dart`.
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

/// Starts interval 1 and moves its start to [_phoneStartedMs]: the
/// phone's own timer, earlier than nothing but the watch's (S-6102).
Future<(WorkoutState, String)> _sessionWithPhoneTimer(
  WorkoutRepository repository,
) async {
  final (state, effortId) = await _session(repository, 'cardio_endurance');
  await state.addEntry(effortId);
  await state.startTimedEntry(effortId, 1);
  await _startAt(state, effortId, 1, _phoneStartedMs);
  return (state, effortId);
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
  final dir = await Directory.systemTemp.createTemp('remote_work_timer_');
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

  test('S-6101 a notStarted interval adopts the remote start', () async {
    final (state, effortId) = await _session(repository, 'cardio_endurance');
    await state.addEntry(effortId);
    await state.startTimedEntry(effortId, 0);
    await state.finishTimedEntry(effortId, 0);

    final before = state.getTimedInstancesForEffort(effortId);
    expect(
      before.map((i) => i.state),
      [TimedState.finished, TimedState.notStarted],
      reason: 'S-6101 the fixture is one finished interval and one unstarted',
    );

    var notifications = 0;
    state.addListener(() => notifications++);
    final revisionBefore = state.watchRefreshRevision;

    final changed = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(wireKind: 'elapsed', startedAtMs: _tMs),
    );

    final after = state.getTimedInstancesForEffort(effortId);
    expect(
      state.currentSession,
      isNotNull,
      reason: 'S-6101 the phone holds the session the timer names',
    );
    expect(changed, isTrue, reason: 'S-6101 the adoption wrote an interval');
    expect(
      after[1].state,
      TimedState.active,
      reason: 'S-6101 the unstarted interval is now running',
    );
    expect(
      after[1].startedAtMs,
      _tMs,
      reason: 'S-6101 on the watch\'s clock, not the phone\'s',
    );
    expect(
      after[1].targetDurationSecs,
      0,
      reason: 'S-6101 open-ended, as `startTimedEntry` writes it',
    );
    expect(
      after[1].pausedAtMs,
      isNull,
      reason: 'S-6101 a running remote leaves no pause stamp',
    );
    expect(
      after[0].id,
      before[0].id,
      reason: 'S-6101 the finished interval is untouched',
    );
    expect(after[0].state, TimedState.finished, reason: 'S-6101 and finished');
    expect(
      after[0].startedAtMs,
      before[0].startedAtMs,
      reason: 'S-6101 with its own start',
    );
    expect(
      state.watchRefreshRevision,
      revisionBefore + 1,
      reason: 'S-6101 the open screen resyncs',
    );
    expect(
      notifications,
      1,
      reason: 'S-6101 exactly one notification, not one per write',
    );
  });

  test('S-6101 adopting closes the effort\'s open rest and stores it '
      'closed', () async {
    final (state, effortId) = await _session(repository, 'cardio_endurance');
    await state.addEntry(effortId);
    await state.recordRestStart(effortId, 1);

    final open = await repository.getEntryRests(effortId);
    expect(
      open.single.restEndMs,
      isNull,
      reason: 'S-6101 the fixture is an open rest',
    );

    final changed = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(wireKind: 'elapsed', startedAtMs: _tMs),
    );
    expect(changed, isTrue, reason: 'S-6101 the adoption wrote an interval');

    // `TimerManager._persistClosedRests` does not await its write.
    await pumpEventQueue();

    final stored = await repository.getEntryRests(effortId);
    expect(
      stored.single.restEndMs,
      isNotNull,
      reason: 'S-6101 the closed rest is stored, not only closed in memory',
    );
  });

  test('S-6101 adopting a round closes the effort\'s open rest and stores it '
      'closed', () async {
    final (state, effortId) = await _session(repository, 'sports');
    expect(
      state.getRoundsForEffort(effortId),
      hasLength(1),
      reason: 'S-6101 the fixture has one round to adopt into',
    );
    await state.recordRestStart(effortId, 1);

    final open = await repository.getEntryRests(effortId);
    expect(
      open.single.restEndMs,
      isNull,
      reason: 'S-6101 the fixture is an open rest',
    );

    final changed = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(
        wireKind: 'round',
        startedAtMs: _tMs,
        plannedDurationMs: _roundPlanMs,
      ),
    );
    expect(changed, isTrue, reason: 'S-6101 the adoption wrote a round');

    // `TimerManager._persistClosedRests` does not await its write.
    await pumpEventQueue();

    final stored = await repository.getEntryRests(effortId);
    expect(
      stored.single.restEndMs,
      isNotNull,
      reason: 'S-6101 the closed rest is stored, not only closed in memory',
    );
  });

  test('S-6102a an earlier remote start replaces the phone\'s', () async {
    final (state, effortId) = await _sessionWithPhoneTimer(repository);
    final before = state.getTimedInstancesForEffort(effortId);
    expect(
      before[1].startedAtMs,
      _phoneStartedMs,
      reason: 'S-6102a the phone\'s own timer started ten seconds after T',
    );
    expect(before[1].state, TimedState.active);

    var notifications = 0;
    state.addListener(() => notifications++);
    final revisionBefore = state.watchRefreshRevision;

    final changed = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(
        wireKind: 'elapsed',
        startedAtMs: _tMs,
        pausedAtMs: _pausedAtMs,
        accumulatedPauseMs: _accumulatedPauseMs,
      ),
    );

    final after = state.getTimedInstancesForEffort(effortId);
    expect(changed, isTrue, reason: 'S-6102a the earlier start wins');
    expect(
      after[1].startedAtMs,
      _tMs,
      reason: 'S-6102a the watch\'s earlier start replaces the phone\'s',
    );
    expect(
      after[1].state,
      TimedState.paused,
      reason: 'S-6102a the remote carries a pause, so the interval is paused',
    );
    expect(
      after[1].pausedAtMs,
      _pausedAtMs,
      reason: 'S-6102a with the remote\'s pause stamp',
    );
    expect(
      after[1].totalPausedDurationMs,
      _accumulatedPauseMs,
      reason: 'S-6102a and the remote\'s accumulated pause',
    );
    expect(after[0].state, TimedState.notStarted, reason: 'S-6102a untouched');
    expect(state.watchRefreshRevision, revisionBefore + 1);
    expect(notifications, 1);
  });

  test('S-6102b a later remote start changes nothing', () async {
    final (state, effortId) = await _sessionWithPhoneTimer(repository);
    final before = state.getTimedInstancesForEffort(effortId);

    var notifications = 0;
    state.addListener(() => notifications++);
    final revisionBefore = state.watchRefreshRevision;

    final changed = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(wireKind: 'elapsed', startedAtMs: _tMs + 20000),
    );

    final after = state.getTimedInstancesForEffort(effortId);
    expect(
      changed,
      isFalse,
      reason: 'S-6102b the phone\'s own earlier start stands',
    );
    expect(
      after[1].startedAtMs,
      _phoneStartedMs,
      reason: 'S-6102b the start is unchanged',
    );
    expect(after[1].state, TimedState.active, reason: 'S-6102b still running');
    expect(
      after[1].pausedAtMs,
      isNull,
      reason: 'S-6102b no pause bookkeeping arrived',
    );
    expect(after[1].id, before[1].id, reason: 'S-6102b the same instance');
    expect(
      state.watchRefreshRevision,
      revisionBefore,
      reason: 'S-6102b no revision bump for a no-op',
    );
    expect(notifications, 0, reason: 'S-6102b and no notification');
  });

  test('S-6102c an equal remote start changes nothing', () async {
    final (state, effortId) = await _sessionWithPhoneTimer(repository);

    var notifications = 0;
    state.addListener(() => notifications++);
    final revisionBefore = state.watchRefreshRevision;

    final changed = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(wireKind: 'elapsed', startedAtMs: _phoneStartedMs),
    );

    final after = state.getTimedInstancesForEffort(effortId);
    expect(changed, isFalse, reason: 'S-6102c an equal start is not earlier');
    expect(after[1].startedAtMs, _phoneStartedMs);
    expect(after[1].state, TimedState.active);
    expect(state.watchRefreshRevision, revisionBefore);
    expect(notifications, 0);
  });

  test('S-6102 round: a remote start equal to the in-progress round\'s start '
      'changes nothing', () async {
    final (state, effortId) = await _session(repository, 'sports');
    await state.startRound(effortId, 0);
    final running = state.getRoundsForEffort(effortId).single;
    await repository.updateRoundInstance(
      running.copyWith(
        startedAtMs: _phoneStartedMs,
        updatedAtMs: _phoneStartedMs,
      ),
    );
    await state.refreshEfforts([effortId]);

    final before = state.getRoundsForEffort(effortId).single;
    expect(before.state, RoundState.active);
    expect(
      before.startedAtMs,
      _phoneStartedMs,
      reason: 'S-6102 round: the phone\'s own round start',
    );

    var notifications = 0;
    state.addListener(() => notifications++);
    final revisionBefore = state.watchRefreshRevision;

    final changed = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(wireKind: 'round', startedAtMs: _phoneStartedMs),
    );

    final after = state.getRoundsForEffort(effortId).single;
    expect(
      changed,
      isFalse,
      reason: 'S-6102 round: an equal start is not earlier',
    );
    expect(after.startedAtMs, _phoneStartedMs);
    expect(after.state, RoundState.active, reason: 'S-6102 round: still active');
    expect(
      state.watchRefreshRevision,
      revisionBefore,
      reason: 'S-6102 round: no revision bump for a no-op',
    );
    expect(notifications, 0, reason: 'S-6102 round: and no notification');
  });

  test('S-6103a a drill effort adopts a hold timer', () async {
    final (state, effortId) = await _session(
      repository,
      'isometric_stretching',
    );
    final effort = state.getEffortsForSegment(state.segments.first.id).single;
    expect(
      effort.effortKind,
      'drill',
      reason: 'S-6103a the modality makes the effort a drill',
    );

    final changed = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(wireKind: 'hold', startedAtMs: _tMs),
    );

    final after = state.getTimedInstancesForEffort(effortId);
    expect(changed, isTrue, reason: 'S-6103a the hold pairs with the drill');
    expect(after.single.state, TimedState.active);
    expect(after.single.startedAtMs, _tMs);
  });

  test('S-6103b a round effort adopts a round timer and its plan', () async {
    final (state, effortId) = await _session(repository, 'sports');
    final effort = state.getEffortsForSegment(state.segments.first.id).single;
    expect(
      effort.effortKind,
      'round',
      reason: 'S-6103b the modality makes the effort a round',
    );

    final changed = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(
        wireKind: 'round',
        startedAtMs: _tMs,
        plannedDurationMs: _roundPlanMs,
      ),
    );

    final after = state.getRoundsForEffort(effortId);
    expect(changed, isTrue, reason: 'S-6103b round pairs with round');
    expect(after.single.state, RoundState.active);
    expect(after.single.startedAtMs, _tMs);
    expect(
      after.single.plannedDurationSecs,
      _roundPlanSecs,
      reason: 'S-6103b the remote plan is carried over in seconds',
    );
  });

  test('S-6103c a round timer does not pair with a timed effort', () async {
    final (state, effortId) = await _session(repository, 'cardio_endurance');
    final before = state.getTimedInstancesForEffort(effortId);

    final changed = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(wireKind: 'round', startedAtMs: _tMs),
    );

    final after = state.getTimedInstancesForEffort(effortId);
    expect(changed, isFalse, reason: 'S-6103c the wrong kind is ignored');
    expect(after.single.state, TimedState.notStarted);
    expect(after.single.startedAtMs, before.single.startedAtMs);
  });

  test('S-6103d an unknown effort id is ignored', () async {
    final (state, _) = await _session(repository, 'cardio_endurance');

    final changed = await state.adoptRemoteWorkTimer(
      'effort-does-not-exist',
      RemoteWorkTimer(wireKind: 'elapsed', startedAtMs: _tMs),
    );

    expect(changed, isFalse, reason: 'S-6103d the phone holds no such effort');
  });

  test('S-6104a a paused remote adopts as paused', () async {
    final (state, effortId) = await _session(repository, 'cardio_endurance');

    final changed = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(
        wireKind: 'elapsed',
        startedAtMs: _tMs,
        pausedAtMs: _pausedAtMs,
        accumulatedPauseMs: _accumulatedPauseMs,
      ),
    );

    final after = state.getTimedInstancesForEffort(effortId);
    expect(changed, isTrue);
    expect(
      after.single.state,
      TimedState.paused,
      reason: 'S-6104a a paused remote leaves the interval paused',
    );
    expect(after.single.startedAtMs, _tMs);
    expect(after.single.pausedAtMs, _pausedAtMs);
    expect(after.single.totalPausedDurationMs, _accumulatedPauseMs);
    expect(after.single.targetDurationSecs, 0);
  });

  test('S-6104b a paused remote replaces a later-started target', () async {
    final (state, effortId) = await _sessionWithPhoneTimer(repository);

    final changed = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(
        wireKind: 'elapsed',
        startedAtMs: _tMs,
        pausedAtMs: _pausedAtMs,
        accumulatedPauseMs: _accumulatedPauseMs,
      ),
    );

    final after = state.getTimedInstancesForEffort(effortId);
    expect(changed, isTrue, reason: 'S-6104b the earlier start wins');
    expect(after[1].state, TimedState.paused);
    expect(after[1].startedAtMs, _tMs);
    expect(after[1].pausedAtMs, _pausedAtMs);
    expect(after[1].totalPausedDurationMs, _accumulatedPauseMs);
  });

  test(
    'S-6104 a round adopts paused with the remote pause bookkeeping',
    () async {
      final (state, effortId) = await _session(repository, 'sports');
      final before = state.getRoundsForEffort(effortId).single;
      expect(
        before.state,
        RoundState.notStarted,
        reason: 'S-6104 the fixture round has not started',
      );

      final changed = await state.adoptRemoteWorkTimer(
        effortId,
        RemoteWorkTimer(
          wireKind: 'round',
          startedAtMs: _tMs,
          pausedAtMs: _pausedAtMs,
          accumulatedPauseMs: _accumulatedPauseMs,
        ),
      );

      final after = state.getRoundsForEffort(effortId).single;
      expect(changed, isTrue);
      expect(
        after.state,
        RoundState.paused,
        reason: 'S-6104 a paused remote leaves the round paused',
      );
      expect(after.startedAtMs, _tMs, reason: 'S-6104 on the remote\'s start');
      expect(
        after.pausedAtMs,
        _pausedAtMs,
        reason: 'S-6104 with the remote\'s pause stamp',
      );
      expect(
        after.totalPausedDurationMs,
        _accumulatedPauseMs,
        reason: 'S-6104 and the remote\'s accumulated pause',
      );
    },
  );

  test('S-6105 every interval finished: ignored', () async {
    final (state, effortId) = await _session(repository, 'cardio_endurance');
    await state.startTimedEntry(effortId, 0);
    await state.finishTimedEntry(effortId, 0);
    await state.addEntry(effortId);
    await state.startTimedEntry(effortId, 1);
    await state.finishTimedEntry(effortId, 1);

    var notifications = 0;
    state.addListener(() => notifications++);
    final revisionBefore = state.watchRefreshRevision;

    final changed = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(wireKind: 'elapsed', startedAtMs: _tMs),
    );

    final after = state.getTimedInstancesForEffort(effortId);
    expect(
      changed,
      isFalse,
      reason: 'S-6105 there is no unfinished interval to adopt into',
    );
    expect(after.map((i) => i.state), [
      TimedState.finished,
      TimedState.finished,
    ]);
    expect(state.watchRefreshRevision, revisionBefore);
    expect(notifications, 0);
  });

  test('S-6106 the in-progress interval is the target', () async {
    final (state, effortId) = await _session(repository, 'cardio_endurance');
    await state.addEntry(effortId);
    await state.addEntry(effortId);
    await state.startTimedEntry(effortId, 2);
    await _startAt(state, effortId, 2, _phoneStartedMs);
    final before = state.getTimedInstancesForEffort(effortId);
    expect(
      before.map((i) => i.state),
      [TimedState.notStarted, TimedState.notStarted, TimedState.active],
      reason: 'S-6106 interval 1 is notStarted while interval 2 runs',
    );

    final changed = await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(wireKind: 'elapsed', startedAtMs: _tMs),
    );

    final after = state.getTimedInstancesForEffort(effortId);
    expect(changed, isTrue);
    expect(
      after[2].startedAtMs,
      _tMs,
      reason: 'S-6106 the in-progress interval took the watch\'s start',
    );
    expect(after[2].state, TimedState.active);
    expect(
      after[1].state,
      TimedState.notStarted,
      reason: 'S-6106 the earlier unstarted interval stays unstarted',
    );
    expect(after[0].state, TimedState.notStarted);
  });

  test('the adopted interval survives a reload', () async {
    final (state, effortId) = await _session(repository, 'cardio_endurance');
    await state.adoptRemoteWorkTimer(
      effortId,
      RemoteWorkTimer(
        wireKind: 'elapsed',
        startedAtMs: _tMs,
        pausedAtMs: _pausedAtMs,
        accumulatedPauseMs: _accumulatedPauseMs,
      ),
    );

    await state.loadSessionData();

    final reloaded = state.getTimedInstancesForEffort(effortId).single;
    expect(reloaded.state, TimedState.paused);
    expect(reloaded.startedAtMs, _tMs);
    expect(reloaded.pausedAtMs, _pausedAtMs);
    expect(reloaded.totalPausedDurationMs, _accumulatedPauseMs);
  });
}
