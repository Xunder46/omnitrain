// Wear exercise menu — the engine jump and the Add Exercise path
// (plan 281, D-28104).
//
// Scenario mapping:
//   S-28101 selectExercise moves to the named slot and announces it once
//   S-28102 selectExercise on a slot the ladder does not hold changes nothing
//   S-28103 addExerciseToEnd appends at the end and keeps the position
//   S-28104 addExerciseToEnd on an empty session lands on the new slot
//   S-28105 a second add of one exercise gets its own slot id
//   S-28105b the second slot id carries the -2 suffix and the session token
//
// The sessions are built through the start paths rather than hand-written slot
// maps, ids are read back from `engine.session`, and the clock is fixed, so
// nothing here reads the real time.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';
import 'package:omnitrain/watch/start/watch_routine_catalog.dart';
import 'package:omnitrain/watch/start/watch_session_start_paths.dart';

DateTime _fixedClock() => DateTime.utc(2026, 11, 21, 12);

class _Harness {
  _Harness() : store = InMemoryWatchSessionStore();

  final InMemoryWatchSessionStore store;

  /// Every frame the engine announces, kept whole: tests slice from a mark
  /// instead of clearing the capture.
  final List<Map<String, Object?>> emitted = [];

  /// A session id of our own, so the slot ids are not some UUID's prefix.
  final String sessionId = 'menu-session-1';

  WatchSessionEngine newEngine() => WatchSessionEngine(
    store,
    onEmit: emitted.add,
    clock: _fixedClock,
    sessionIdFactory: () => sessionId,
  );

  WatchSessionStartPaths newPaths(WatchSessionEngine engine) =>
      WatchSessionStartPaths(engine: engine, store: store, clock: _fixedClock);

  /// Builds a session of [first, then others...] with the position on index 0:
  /// the first exercise is appended last with `atIndex: 0`, so no hand-written
  /// slot map is involved.
  Future<void> startLadder(
    WatchSessionStartPaths paths,
    WatchCatalogExercise anchor,
    List<WatchCatalogExercise> others,
  ) async {
    await paths.startFreeWorkout();
    await paths.addExerciseToSession(anchor);
    for (final exercise in others) {
      await paths.addExerciseToSession(exercise, atIndex: 0);
    }
  }

  List<Map<String, Object?>> framesSince(int mark) =>
      emitted.skip(mark).toList(growable: false);
}

const WatchCatalogExercise _a = WatchCatalogExercise(
  exerciseId: 'menu-deadlift',
  name: 'Deadlift',
  capabilities: ['reps'],
);
const WatchCatalogExercise _b = WatchCatalogExercise(
  exerciseId: 'menu-row',
  name: 'Row',
  capabilities: ['reps'],
);
const WatchCatalogExercise _c = WatchCatalogExercise(
  exerciseId: 'menu-press',
  name: 'Press',
  capabilities: ['reps'],
);

void main() {
  test('S-28101 selectExercise moves to the named slot and announces it once', () async {
    final harness = _Harness();
    final engine = harness.newEngine();
    final paths = harness.newPaths(engine);

    await harness.startLadder(paths, _c, [_b, _a]);
    final session = engine.session!;
    expect(session.exercises, hasLength(3));
    expect(session.currentExerciseIndex, 0);
    final slotCId = session.exercises[2]['sessionExerciseId']! as String;

    final mark = harness.emitted.length;
    final moved = await engine.selectExercise(slotCId);

    expect(moved!.currentExerciseIndex, 2);
    final lifecycles = harness
        .framesSince(mark)
        .where((frame) => frame['type'] == 'session_lifecycle')
        .toList();
    expect(lifecycles, hasLength(1));
    final lifecycle =
        (lifecycles.single['payload'] as Map<String, Object?>)['state'];
    expect(lifecycle, WatchLifecycleState.exerciseAdvanced);
    final exerciseIndex =
        (lifecycles.single['payload'] as Map<String, Object?>)['exerciseIndex'];
    expect(exerciseIndex, 2);
  });

  test('S-28102 selectExercise on an unknown slot changes nothing', () async {
    final harness = _Harness();
    final engine = harness.newEngine();
    final paths = harness.newPaths(engine);

    await harness.startLadder(paths, _c, [_b, _a]);
    expect(engine.session!.currentExerciseIndex, 0);

    final mark = harness.emitted.length;
    final moved = await engine.selectExercise('gone');

    expect(moved, isNull);
    expect(engine.session!.currentExerciseIndex, 0);
    expect(harness.emitted.length, mark);
  });

  test('S-28103 addExerciseToEnd appends last and keeps the position', () async {
    final harness = _Harness();
    final engine = harness.newEngine();
    final paths = harness.newPaths(engine);

    await harness.startLadder(paths, _b, [_a]);
    final before = engine.session!;
    expect(before.exercises, hasLength(2));
    expect(before.currentExerciseIndex, 0);

    final mark = harness.emitted.length;
    final after = await paths.addExerciseToEnd(_c);

    expect(after.exercises, hasLength(3));
    expect(after.exercises.last['exerciseId'], 'menu-press');
    expect(after.currentExerciseIndex, 0);
    final snapshots = harness
        .framesSince(mark)
        .where((frame) => frame['type'] == 'session_snapshot')
        .toList();
    expect(snapshots, hasLength(1));
    final revision =
        (snapshots.single['payload'] as Map<String, Object?>)['revision'];
    expect(revision, before.revision + 1);
  });

  test('S-28104 an empty free workout lands on the added slot', () async {
    final harness = _Harness();
    final engine = harness.newEngine();
    final paths = harness.newPaths(engine);

    await paths.startFreeWorkout();
    expect(engine.session!.exercises, isEmpty);

    final after = await paths.addExerciseToEnd(_a);

    expect(after.exercises, hasLength(1));
    expect(after.currentExerciseIndex, 0);
  });

  test('S-28105 a second add of one exercise gets its own slot id', () async {
    final harness = _Harness();
    final engine = harness.newEngine();
    final paths = harness.newPaths(engine);

    await paths.startFreeWorkout();
    await paths.addExerciseToSession(_a);
    final firstId = engine.session!.exercises.single['sessionExerciseId'];

    final after = await paths.addExerciseToEnd(_a);

    final ids = after.exercises
        .map((row) => row['sessionExerciseId'])
        .toList(growable: false);
    expect(ids, hasLength(2));
    expect(ids.first, firstId);
    expect(ids.toSet(), hasLength(2));
  });

  test('S-28105b the second slot id carries the -2 suffix and the session token', () async {
    final harness = _Harness();
    final engine = harness.newEngine();
    final paths = harness.newPaths(engine);

    await paths.startFreeWorkout();
    await paths.addExerciseToSession(_a);

    final after = await paths.addExerciseToEnd(_a);

    final ids = after.exercises
        .map((row) => row['sessionExerciseId'])
        .toList(growable: false);
    expect(ids[0], 'sx-menu-deadlift~menu-ses');
    expect(ids[1], 'sx-menu-deadlift-2~menu-ses');
  });
}
