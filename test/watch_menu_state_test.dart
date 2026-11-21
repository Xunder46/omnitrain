// The Wear wrist's session menu: the ladder as rows, the lock, and the three
// actions (plan 281, D-28105, D-28106).
//
// Scenario mapping:
//   S-28110  the ladder as rows, in order, with counts   → `S-28110 ...`
//   S-28110b a rest hung on a slot is not counted logged  → `S-28110b ...`
//   S-28111  non-effort entries are not work            → `S-28111 ...`
//   S-28112a-c a running elapsed / hold / round locks    → `S-28112a ...` etc.
//   S-28112d a running rest never locks                  → `S-28112d ...`
//   S-28112e a stopped work clock never locks            → `S-28112e ...`
//   S-28112f a paused work clock still locks             → `S-28112f ...`
//   S-28113  a jump is refused while the clock runs      → `S-28113 ...`
//   S-28114  a stale row's jump changes nothing          → `S-28114 ...`
//   S-28115  End with work finishes                      → `S-28115 ...`
//   S-28116  End without work is a discard               → `S-28116 ...`
//   S-28117  Discard keeps the logged entries            → `S-28117 ...`
//   S-28118a-c what End has to save                      → `S-28118a ...` etc.
//   S-28119  a finished session takes nothing            → `S-28119 ...`
//   S-28119b an entry the phone deleted is not work      → `S-28119b ...`
//
// The sessions are built through the start paths the way
// `test/watch_session_menu_engine_test.dart` (P1) builds them, the clock is
// fixed, and the capture is never cleared between act and assert — tests slice
// from a mark. Plain `test()` only: no widget is involved, and the store is the
// in-memory one.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/watch/logging/watch_menu_state.dart';
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
  final String sessionId = 'menu-p2-session-9';

  WatchSessionEngine newEngine() => WatchSessionEngine(
    store,
    onEmit: emitted.add,
    clock: _fixedClock,
    sessionIdFactory: () => sessionId,
  );

  WatchSessionStartPaths newPaths(WatchSessionEngine engine) =>
      WatchSessionStartPaths(engine: engine, store: store, clock: _fixedClock);

  /// Builds a session of [first, then others...] with the position on index 0.
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

  /// The `state` of every `session_lifecycle` announced since [mark].
  List<String> lifecyclesSince(int mark) => [
    for (final frame in framesSince(mark))
      if (frame['type'] == 'session_lifecycle')
        (frame['payload']! as Map)['state']! as String,
  ];
}

const WatchCatalogExercise _a = WatchCatalogExercise(
  exerciseId: 'p2-squat',
  name: 'Squat',
  capabilities: ['reps'],
);
const WatchCatalogExercise _b = WatchCatalogExercise(
  exerciseId: 'p2-hinge',
  name: 'Hinge',
  capabilities: ['reps'],
);
const WatchCatalogExercise _c = WatchCatalogExercise(
  exerciseId: 'p2-press',
  name: 'Press',
  capabilities: ['reps'],
);
const WatchCatalogExercise _d = WatchCatalogExercise(
  exerciseId: 'p2-pull',
  name: 'Pull',
  capabilities: ['reps'],
);

/// A set logged against [slotId], the shape the logging surfaces hand the
/// engine (`test/watch_session_engine_test.dart` `_setEvent`).
Map<String, Object?> _setEvent({
  required String entryId,
  required String slotId,
  String exerciseId = 'p2-squat',
}) => {
  'entryId': entryId,
  'eventId': entryId,
  'kind': WatchObservationKind.set,
  'loggedAt': utcIso(_fixedClock()),
  'sessionExerciseId': slotId,
  'exerciseId': exerciseId,
  'reps': 5,
  'loadKg': 80,
};

/// A `rest` the phone could hear about, hung on an entry (the schema's shape).
Map<String, Object?> _restEvent({
  required String entryId,
  required String slotId,
  required String afterEntryId,
}) => {
  'entryId': entryId,
  'eventId': entryId,
  'kind': WatchObservationKind.rest,
  'loggedAt': utcIso(_fixedClock()),
  'sessionExerciseId': slotId,
  'exerciseId': 'p2-squat',
  'startedAt': utcIso(_fixedClock()),
  'endedAt': utcIso(_fixedClock()),
  'afterEntryId': afterEntryId,
};

/// A glass tap, the shape plan 94 pins (`glassChange`, no slot fields).
Map<String, Object?> _waterEvent(String entryId) => {
  'entryId': entryId,
  'eventId': entryId,
  'kind': WatchObservationKind.waterGlass,
  'loggedAt': utcIso(_fixedClock()),
  'glassChange': 'add',
};

/// A session end row, the shape the schema gives `session_end`.
Map<String, Object?> _sessionEndEvent(String entryId) => {
  'entryId': entryId,
  'eventId': entryId,
  'kind': WatchObservationKind.sessionEnd,
  'loggedAt': utcIso(_fixedClock()),
  'startedAt': utcIso(_fixedClock()),
  'endedAt': utcIso(_fixedClock()),
  'status': 'completed',
};

/// A `structure_change` from the phone, the shape
/// `test/watch_session_engine_test.dart` `_structureChange` builds.
Map<String, Object?> _structureChange({
  required String sessionId,
  required String changeId,
  required List<Map<String, Object?>> changes,
}) => {
  'protocolVersion': SyncProtocolValidator.protocolVersion,
  'messageId': 'msg-$changeId',
  'sessionId': sessionId,
  'type': 'structure_change',
  'origin': 'phone',
  'sentAt': utcIso(_fixedClock()),
  'payload': <String, Object?>{'changeId': changeId, 'changes': changes},
};

String _slotAt(WatchSessionEngine engine, int index) =>
    engine.session!.exercises[index]['sessionExerciseId']! as String;

void main() {
  test(
    'S-28110 rows are the ladder in order, with the position and the counts',
    () async {
      final harness = _Harness();
      final engine = harness.newEngine();
      final paths = harness.newPaths(engine);
      final menu = WatchMenuState(engine: engine, paths: paths);

      // Ladder [a, b, c], position moved onto the middle slot, two sets on b.
      await harness.startLadder(paths, _c, [_b, _a]);
      final slotB = _slotAt(engine, 1);
      await engine.selectExercise(slotB);
      await engine.appendObservation(
        _setEvent(entryId: 'p2-set-1', slotId: slotB, exerciseId: 'p2-hinge'),
      );
      await engine.appendObservation(
        _setEvent(entryId: 'p2-set-2', slotId: slotB, exerciseId: 'p2-hinge'),
      );

      final rows = menu.rows;

      expect(rows, hasLength(3));
      expect(
        [for (final row in rows) row.name],
        ['Squat', 'Hinge', 'Press'],
        reason: 'the ladder order, not a count order',
      );
      expect(rows[1].isCurrent, isTrue);
      expect(rows[0].isCurrent, isFalse);
      expect(rows[2].isCurrent, isFalse);
      expect(rows[0].loggedCount, 0);
      expect(rows[1].loggedCount, 2);
      expect(rows[2].loggedCount, 0);
      expect(rows[1].countLabel, '2 logged');
      expect(rows[0].countLabel, isNull, reason: 'never `0 logged`');
      expect(rows[2].countLabel, isNull);
    },
  );

  test('S-28110b a rest hung on a slot is never counted as logged', () async {
    final harness = _Harness();
    final engine = harness.newEngine();
    final paths = harness.newPaths(engine);
    final menu = WatchMenuState(engine: engine, paths: paths);

    await harness.startLadder(paths, _a, []);
    final slotA = _slotAt(engine, 0);
    await engine.appendObservation(
      _setEvent(entryId: 'p2-set-1', slotId: slotA),
    );
    await engine.appendObservation(
      _setEvent(entryId: 'p2-set-2', slotId: slotA),
    );
    await engine.appendObservation(
      _restEvent(
        entryId: 'p2-rest-1',
        slotId: slotA,
        afterEntryId: 'p2-set-2',
      ),
    );

    final row = menu.rows.single;
    expect(row.slotId, slotA);
    expect(row.loggedCount, 2, reason: 'a rest is not an effort');
    expect(row.countLabel, '2 logged');
  });

  test('S-28111 rest, water, quick-log and end are not work', () async {
    final harness = _Harness();
    final engine = harness.newEngine();
    final paths = harness.newPaths(engine);
    final menu = WatchMenuState(engine: engine, paths: paths);

    await harness.startLadder(paths, _a, []);
    final slotA = _slotAt(engine, 0);
    await engine.appendObservation(
      _restEvent(
        entryId: 'p2-rest-1',
        slotId: slotA,
        afterEntryId: 'p2-anchor-1',
      ),
    );
    await engine.appendObservation(_waterEvent('p2-glass-1'));
    await engine.logNutrition(foodId: 'p2-oats', servings: 1.5);
    await engine.appendObservation(_sessionEndEvent('p2-end-1'));

    expect(menu.hasLoggedEfforts, isFalse);
  });

  test('S-28112a a running elapsed clock locks the menu', () async {
    final harness = _Harness();
    final engine = harness.newEngine();
    final paths = harness.newPaths(engine);
    final menu = WatchMenuState(engine: engine, paths: paths);

    await harness.startLadder(paths, _a, []);
    await engine.startTimer(WatchTimerKind.elapsed);

    expect(menu.isLocked, isTrue);
  });

  test('S-28112b a running hold locks the menu', () async {
    final harness = _Harness();
    final engine = harness.newEngine();
    final paths = harness.newPaths(engine);
    final menu = WatchMenuState(engine: engine, paths: paths);

    await harness.startLadder(paths, _a, []);
    await engine.startTimer(
      WatchTimerKind.hold,
      sessionExerciseId: _slotAt(engine, 0),
    );

    expect(menu.isLocked, isTrue);
  });

  test('S-28112c a running round locks the menu', () async {
    final harness = _Harness();
    final engine = harness.newEngine();
    final paths = harness.newPaths(engine);
    final menu = WatchMenuState(engine: engine, paths: paths);

    await harness.startLadder(paths, _a, []);
    await engine.startTimer(
      WatchTimerKind.round,
      sessionExerciseId: _slotAt(engine, 0),
    );

    expect(menu.isLocked, isTrue);
  });

  test('S-28112d a running rest never locks the menu', () async {
    final harness = _Harness();
    final engine = harness.newEngine();
    final paths = harness.newPaths(engine);
    final menu = WatchMenuState(engine: engine, paths: paths);

    await harness.startLadder(paths, _a, []);
    await engine.startTimer(WatchTimerKind.rest);

    expect(menu.isLocked, isFalse);
  });

  test('S-28112e a stopped work clock never locks the menu', () async {
    final harness = _Harness();
    final engine = harness.newEngine();
    final paths = harness.newPaths(engine);
    final menu = WatchMenuState(engine: engine, paths: paths);

    await harness.startLadder(paths, _a, []);
    for (final kind in const [
      WatchTimerKind.elapsed,
      WatchTimerKind.hold,
      WatchTimerKind.round,
    ]) {
      await engine.startTimer(kind, sessionExerciseId: _slotAt(engine, 0));
      expect(menu.isLocked, isTrue, reason: '$kind running locks');
      await engine.stopTimer(kind: kind);
      expect(menu.isLocked, isFalse, reason: '$kind stopped does not lock');
    }
  });

  test('S-28112f a paused work clock still locks the menu', () async {
    final harness = _Harness();
    final engine = harness.newEngine();
    final paths = harness.newPaths(engine);
    final menu = WatchMenuState(engine: engine, paths: paths);

    await harness.startLadder(paths, _c, [_b, _a]);
    await engine.startTimer(
      WatchTimerKind.hold,
      sessionExerciseId: _slotAt(engine, 0),
    );
    await engine.pauseTimer(kind: WatchTimerKind.hold);

    expect(
      engine.timerFor(WatchTimerKind.hold)!.state,
      WatchTimerState.paused,
      reason: 'the premise: the hold is paused, not running',
    );
    expect(menu.isLocked, isTrue);

    final slotC = _slotAt(engine, 2);
    final locked = await menu.jump(slotC);

    expect(locked, isFalse);
    expect(engine.session!.currentExerciseIndex, 0);

    await engine.resumeTimer(kind: WatchTimerKind.hold);
    await engine.stopTimer(kind: WatchTimerKind.hold);
    expect(menu.isLocked, isFalse);
  });

  test('S-28113 a jump waits for the work clock to stop', () async {
    final harness = _Harness();
    final engine = harness.newEngine();
    final paths = harness.newPaths(engine);
    final menu = WatchMenuState(engine: engine, paths: paths);

    await harness.startLadder(paths, _c, [_b, _a]);
    await engine.startTimer(
      WatchTimerKind.hold,
      sessionExerciseId: _slotAt(engine, 0),
    );
    final slotC = _slotAt(engine, 2);

    final locked = await menu.jump(slotC);

    expect(locked, isFalse);
    expect(engine.session!.currentExerciseIndex, 0);

    await engine.stopTimer(kind: WatchTimerKind.hold);
    final moved = await menu.jump(slotC);

    expect(moved, isTrue);
    expect(engine.session!.currentExerciseIndex, 2);
  });

  test('S-28114 a jump to a gone slot changes nothing', () async {
    final harness = _Harness();
    final engine = harness.newEngine();
    final paths = harness.newPaths(engine);
    final menu = WatchMenuState(engine: engine, paths: paths);

    await harness.startLadder(paths, _c, [_b, _a]);
    final mark = harness.emitted.length;
    final revision = engine.session!.revision;

    final moved = await menu.jump('gone');

    expect(moved, isFalse);
    expect(engine.session!.currentExerciseIndex, 0);
    expect(engine.session!.revision, revision);
    expect(harness.emitted.length, mark, reason: 'no frame is announced');
  });

  test('S-28115 End with a logged effort finishes the session', () async {
    final harness = _Harness();
    final engine = harness.newEngine();
    final paths = harness.newPaths(engine);
    final menu = WatchMenuState(engine: engine, paths: paths);

    await harness.startLadder(paths, _a, []);
    await engine.appendObservation(
      _setEvent(entryId: 'p2-set-1', slotId: _slotAt(engine, 0)),
    );
    final mark = harness.emitted.length;

    await menu.finish();

    expect(engine.session!.status, WatchSessionStatus.completed);
    expect(
      harness.lifecyclesSince(mark),
      [WatchLifecycleState.completed],
      reason: 'exactly one lifecycle frame, and it says completed',
    );
  });

  test('S-28116 End with nothing to save is a discard', () async {
    final harness = _Harness();
    final engine = harness.newEngine();
    final paths = harness.newPaths(engine);
    final menu = WatchMenuState(engine: engine, paths: paths);

    await harness.startLadder(paths, _a, []);
    final mark = harness.emitted.length;

    await menu.finish();

    expect(engine.session!.status, WatchSessionStatus.abandoned);
    expect(
      harness.lifecyclesSince(mark),
      [WatchLifecycleState.abandoned],
      reason: 'exactly one lifecycle frame, and it says abandoned',
    );
  });

  test('S-28117 Discard abandons the session and keeps the entries', () async {
    final harness = _Harness();
    final engine = harness.newEngine();
    final paths = harness.newPaths(engine);
    final menu = WatchMenuState(engine: engine, paths: paths);

    await harness.startLadder(paths, _a, []);
    await engine.appendObservation(
      _setEvent(entryId: 'p2-set-1', slotId: _slotAt(engine, 0)),
    );
    await engine.appendObservation(
      _setEvent(entryId: 'p2-set-2', slotId: _slotAt(engine, 0)),
    );

    await menu.discard();

    expect(engine.session!.status, WatchSessionStatus.abandoned);
    expect(
      [
        for (final entry in engine.entries)
          if (entry.kind == WatchObservationKind.set) entry.entryId,
      ],
      unorderedEquals(['p2-set-1', 'p2-set-2']),
      reason: 'the logged sets stay in history',
    );
  });

  test('S-28118a one logged effort gives End something to save', () async {
    final harness = _Harness();
    final engine = harness.newEngine();
    final paths = harness.newPaths(engine);
    final menu = WatchMenuState(engine: engine, paths: paths);

    await harness.startLadder(paths, _a, []);
    await engine.appendObservation(
      _setEvent(entryId: 'p2-set-1', slotId: _slotAt(engine, 0)),
    );

    expect(menu.hasWorkToSave, isTrue);
  });

  test('S-28118b a running work clock gives End something to save', () async {
    final harness = _Harness();
    final engine = harness.newEngine();
    final paths = harness.newPaths(engine);
    final menu = WatchMenuState(engine: engine, paths: paths);

    await harness.startLadder(paths, _a, []);
    await engine.startTimer(
      WatchTimerKind.hold,
      sessionExerciseId: _slotAt(engine, 0),
    );
    expect(menu.hasWorkToSave, isTrue);

    await menu.finish();

    expect(
      engine.session!.status,
      WatchSessionStatus.completed,
      reason: 'the phone\'s clock is saved, not discarded',
    );
  });

  test('S-28118c an untouched session has nothing to save', () async {
    final harness = _Harness();
    final engine = harness.newEngine();
    final paths = harness.newPaths(engine);
    final menu = WatchMenuState(engine: engine, paths: paths);

    await harness.startLadder(paths, _a, []);

    expect(menu.hasWorkToSave, isFalse);
  });

  test('S-28119 a finished session takes nothing from the menu', () async {
    final harness = _Harness();
    final engine = harness.newEngine();
    final paths = harness.newPaths(engine);
    final menu = WatchMenuState(engine: engine, paths: paths);

    await harness.startLadder(paths, _c, [_b, _a]);
    await engine.finishSession();
    final slots = [
      for (final slot in engine.session!.exercises) slot['sessionExerciseId'],
    ];

    final added = await menu.addExercise(_d);

    expect(added, isFalse);
    expect(
      [for (final slot in engine.session!.exercises) slot['sessionExerciseId']],
      slots,
      reason: 'the closed ladder is unchanged',
    );

    final moved = await menu.jump(_slotAt(engine, 1));
    final discarded = await menu.discard();

    expect(moved, isFalse);
    expect(discarded, isNull);
    expect(engine.session!.status, WatchSessionStatus.completed);
    expect(engine.session!.currentExerciseIndex, 0);
  });

  test('S-28119b an entry the phone deleted is not work', () async {
    final harness = _Harness();
    final engine = harness.newEngine();
    final paths = harness.newPaths(engine);
    final menu = WatchMenuState(engine: engine, paths: paths);

    await harness.startLadder(paths, _a, []);
    final slotA = _slotAt(engine, 0);
    await engine.appendObservation(
      _setEvent(entryId: 'p2-set-only', slotId: slotA),
    );
    expect(menu.hasLoggedEfforts, isTrue, reason: 'the fixture: one effort');

    await engine.applyMessage(
      _structureChange(
        sessionId: engine.session!.sessionId,
        changeId: 'chg-p2-delete-1',
        changes: [
          {'kind': 'delete_entry', 'entryId': 'p2-set-only'},
        ],
      ),
    );

    expect(menu.hasLoggedEfforts, isFalse);
    expect(menu.rows, hasLength(1));
    expect(menu.rows.single.loggedCount, 0);
    expect(menu.rows.single.countLabel, isNull);
  });
}
