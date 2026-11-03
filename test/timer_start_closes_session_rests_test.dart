// Starting a work timer on any exercise ends every open rest of the session (98 P1).
//
// Plan: `docs/plans/2026-11-02-98-phone-watch-live-sync-audit-plan/
// 2026-11-02-98-phone-watch-live-sync-audit-plan.md`, D-1, scenarios
// S-9921..S-9923.
// Scenario mapping:
//   S-9921  `startTimedEntry` on B closes A's open rest (memory + repository)
//     → `S-9921 ...`
//   S-9921b an already-closed rest on A is left untouched → `S-9921b ...`
//   S-9921c the rest on B itself still closes → `S-9921c ...`
//   S-9922  the same for `startRound` on B → `S-9922 ...`
//   S-9923  the same for a wrist timer adopted into B → `S-9923 ...`
//   S-9923b the same for a wrist timer adopted into a round B
//     → `S-9923b ...`
//
// Both groups run the same fixtures through the same state: the close must
// write the same rows under `HiveWorkoutRepository` and
// `MockWorkoutRepository`. Plain `test()`: a Hive write inside a widget test's
// fake-async zone never drains.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:omnitrain/core/constants/capability.dart';
import 'package:omnitrain/data/repositories/hive_workout_repository.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/workout/timer_manager.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/watch_capture_import_harness.dart' show seedExercise;

/// The adopted timer's start, unlike every default.
final int _tMs = DateTime.utc(2026, 10, 5, 10, 17, 23).millisecondsSinceEpoch;

const String _exerciseAId = 'ex-press';
const String _exerciseBId = 'ex-interval';

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

/// A session holding two efforts: A, a `set` exercise (the modality's own
/// kind), and B, an exercise of [effortBKind] (`timed`, or `round` for
/// S-9922). Each effort holds one entry from the add; the caller adds more.
Future<(WorkoutState, String, String)> _twoEffortSession(
  WorkoutRepository repository, {
  String effortBKind = 'timed',
}) async {
  final state = WorkoutState(repository);
  await state.createNewSession(modality: 'resistance_lifting');
  final exercises = await repository.getExercises();
  final exerciseA = exercises.firstWhere((e) => e.id == _exerciseAId);
  final exerciseB = exercises.firstWhere((e) => e.id == _exerciseBId);
  final effortA = await state.addExerciseToSession(exerciseA);
  final effortB = await state.addExerciseToSession(
    exerciseB,
    effortKindOverride: effortBKind,
  );
  return (state, effortA, effortB);
}

void main() {
  group('Mock', () => _sessionRestTests(open: _openMock, close: () async {}));
  group('Hive', () => _sessionRestTests(open: _openHive, close: _closeHive));
}

Future<WorkoutRepository> _openMock() async {
  final repository = MockWorkoutRepository();
  await repository.initialize();
  await _seed(repository);
  return repository;
}

Directory? _hiveDir;

Future<WorkoutRepository> _openHive() async {
  final dir = await Directory.systemTemp.createTemp('timer_session_rest_');
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

/// The two exercises the fixture points at, with the capabilities each kind
/// needs.
Future<void> _seed(WorkoutRepository repository) async {
  await seedExercise(
    repository,
    id: _exerciseAId,
    name: 'Bench Press',
    capabilities: [
      ExerciseCapability.reps,
      ExerciseCapability.sets,
      ExerciseCapability.load,
    ],
  );
  await seedExercise(
    repository,
    id: _exerciseBId,
    name: 'Row Interval',
    capabilities: [ExerciseCapability.time, ExerciseCapability.rounds],
  );
}

void _sessionRestTests({
  required Future<WorkoutRepository> Function() open,
  required Future<void> Function() close,
}) {
  late WorkoutRepository repository;

  setUp(() async => repository = await open());
  tearDown(close);

  test('S-9921 startTimedEntry on B closes the open rest on A', () async {
    final (state, effortA, effortB) = await _twoEffortSession(repository);
    await state.addEntry(effortA);
    await state.recordRestStart(effortA, 1);

    expect(
      state.getEntryRests(effortA).single.restEndMs,
      isNull,
      reason: 'S-9921 the fixture holds one open rest on A',
    );

    await state.startTimedEntry(effortB, 0);

    final inMemory = state.getEntryRests(effortA);
    expect(inMemory, hasLength(1), reason: 'S-9921 A keeps its rest row');
    expect(
      inMemory.single.restEndMs,
      isNotNull,
      reason: 'S-9921 the rest on A is closed in memory',
    );
    expect(
      inMemory.single.entryIndex,
      1,
      reason: 'S-9921 the closed rest keeps its entryIndex',
    );

    // `TimerManager._persistClosedRests` does not await its write.
    await pumpEventQueue();

    final stored = await repository.getEntryRests(effortA);
    expect(
      stored.single.restEndMs,
      isNotNull,
      reason: 'S-9921 the closed rest is stored, not only closed in memory',
    );
  });

  test('S-9921b an already-closed rest on A is left untouched', () async {
    final (state, effortA, effortB) = await _twoEffortSession(repository);
    await state.recordRestStart(effortA, 0);
    await state.recordRestEnd(effortA, 0);
    final closedBefore = state.getEntryRests(effortA).single;
    expect(closedBefore.restEndMs, isNotNull);

    await state.addEntry(effortA);
    await state.recordRestStart(effortA, 1);

    await state.startTimedEntry(effortB, 0);

    final untouched = state
        .getEntryRests(effortA)
        .singleWhere((r) => r.entryIndex == 0);
    expect(
      untouched.restEndMs,
      closedBefore.restEndMs,
      reason: 'S-9921b the closed rest keeps its end',
    );
    expect(
      untouched.updatedAtMs,
      closedBefore.updatedAtMs,
      reason: 'S-9921b the closed rest is not rewritten',
    );
  });

  test('S-9921c the rest on B itself still closes', () async {
    final (state, effortA, effortB) = await _twoEffortSession(repository);
    await state.addEntry(effortA);
    await state.recordRestStart(effortA, 1);
    await state.recordRestStart(effortB, 0);

    await state.startTimedEntry(effortB, 0);

    expect(
      state.getEntryRests(effortB).single.restEndMs,
      isNotNull,
      reason: 'S-9921c the timer\'s own effort still closes its rest',
    );
    expect(
      state.getEntryRests(effortA).single.restEndMs,
      isNotNull,
      reason: 'S-9921c the other effort\'s rest closes with it',
    );
  });

  test('S-9922 startRound on B closes the open rest on A', () async {
    final (state, effortA, effortB) = await _twoEffortSession(
      repository,
      effortBKind: 'round',
    );
    await state.addEntry(effortA);
    await state.recordRestStart(effortA, 1);

    expect(
      state.getEntryRests(effortA).single.restEndMs,
      isNull,
      reason: 'S-9922 the fixture holds one open rest on A',
    );

    await state.startRound(effortB, 0);

    final inMemory = state.getEntryRests(effortA);
    expect(
      inMemory.single.restEndMs,
      isNotNull,
      reason: 'S-9922 the rest on A is closed in memory',
    );
    expect(
      inMemory.single.entryIndex,
      1,
      reason: 'S-9922 the closed rest keeps its entryIndex',
    );

    // `TimerManager._persistClosedRests` does not await its write.
    await pumpEventQueue();

    final stored = await repository.getEntryRests(effortA);
    expect(
      stored.single.restEndMs,
      isNotNull,
      reason: 'S-9922 the closed rest is stored, not only closed in memory',
    );
  });

  test(
    'S-9923 a wrist timer adopted into B closes the open rest on A',
    () async {
      final (state, effortA, effortB) = await _twoEffortSession(repository);
      await state.addEntry(effortA);
      await state.recordRestStart(effortA, 1);

      expect(
        state.getEntryRests(effortA).single.restEndMs,
        isNull,
        reason: 'S-9923 the fixture holds one open rest on A',
      );

      final changed = await state.adoptRemoteWorkTimer(
        effortB,
        RemoteWorkTimer(wireKind: 'elapsed', startedAtMs: _tMs),
      );
      expect(changed, isTrue, reason: 'S-9923 the adoption wrote an interval');

      final inMemory = state.getEntryRests(effortA);
      expect(
        inMemory.single.restEndMs,
        isNotNull,
        reason: 'S-9923 the rest on A is closed in memory',
      );
      expect(
        inMemory.single.entryIndex,
        1,
        reason: 'S-9923 the closed rest keeps its entryIndex',
      );

      // `TimerManager._persistClosedRests` does not await its write.
      await pumpEventQueue();

      final stored = await repository.getEntryRests(effortA);
      expect(
        stored.single.restEndMs,
        isNotNull,
        reason: 'S-9923 the closed rest is stored, not only closed in memory',
      );
    },
  );

  test(
    'S-9923b a wrist timer adopted into a round B closes the open rest on A',
    () async {
      final (state, effortA, effortB) = await _twoEffortSession(
        repository,
        effortBKind: 'round',
      );
      await state.addEntry(effortA);
      await state.recordRestStart(effortA, 1);

      expect(
        state.getEntryRests(effortA).single.restEndMs,
        isNull,
        reason: 'S-9923b the fixture holds one open rest on A',
      );

      final changed = await state.adoptRemoteWorkTimer(
        effortB,
        RemoteWorkTimer(
          wireKind: 'round',
          startedAtMs: _tMs,
          plannedDurationMs: 75000,
        ),
      );
      expect(changed, isTrue, reason: 'S-9923b the adoption wrote a round');

      final inMemory = state.getEntryRests(effortA);
      expect(
        inMemory.single.restEndMs,
        isNotNull,
        reason: 'S-9923b the rest on A is closed in memory',
      );
      expect(
        inMemory.single.entryIndex,
        1,
        reason: 'S-9923b the closed rest keeps its entryIndex',
      );

      // `TimerManager._persistClosedRests` does not await its write.
      await pumpEventQueue();

      final stored = await repository.getEntryRests(effortA);
      expect(
        stored.single.restEndMs,
        isNotNull,
        reason: 'S-9923b the closed rest is stored, not only closed in memory',
      );
    },
  );
}
