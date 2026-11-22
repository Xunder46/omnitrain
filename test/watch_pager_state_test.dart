// The Wear wrist's exercise pager rule (plan 287, D-28701, D-28702).
//
// Scenario mapping:
//   S-28701  the page, the count and the `n/N` label              → `S-28701 ...`
//   S-28702  one exercise: no pager, no label                     → `S-28702 ...`
//   S-28703  a work clock locks, a rest does not                  → `S-28703 ...`
//   S-28704  the neighbour page, no wrap                          → `S-28704 ...`
//   S-28705  a settled swipe is the menu's jump                   → `S-28705 ...`
//   S-28706  landing on the current page moves nothing            → `S-28706 ...`
//   S-28707  a locked swipe refuses and starts the notice         → `S-28707 ...`
//   S-28708  a page off the ladder changes nothing                → `S-28708 ...`
//   S-28709  the rows are read fresh, never cached                → `S-28709 ...`
//
// The sessions are built through the start paths the way
// `test/watch_menu_state_test.dart` builds them, the clock is fixed, and the
// capture is never cleared between act and assert: tests slice from a mark.
// Plain `test()` only; the store is the in-memory one.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/watch/logging/watch_menu_state.dart';
import 'package:omnitrain/watch/logging/watch_pager_state.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';
import 'package:omnitrain/watch/start/watch_routine_catalog.dart';
import 'package:omnitrain/watch/start/watch_session_start_paths.dart';

DateTime _fixedClock() => DateTime.utc(2026, 11, 21, 12);

const WatchCatalogExercise _a = WatchCatalogExercise(
  exerciseId: 'p287-squat',
  name: 'Squat',
  capabilities: ['reps'],
);
const WatchCatalogExercise _b = WatchCatalogExercise(
  exerciseId: 'p287-hinge',
  name: 'Hinge',
  capabilities: ['reps'],
);
const WatchCatalogExercise _c = WatchCatalogExercise(
  exerciseId: 'p287-press',
  name: 'Press',
  capabilities: ['reps'],
);
const WatchCatalogExercise _d = WatchCatalogExercise(
  exerciseId: 'p287-pull',
  name: 'Pull',
  capabilities: ['reps'],
);

class _Rig {
  _Rig._(this.engine, this.paths, this.menu, this.pager, this.emitted);

  final WatchSessionEngine engine;
  final WatchSessionStartPaths paths;
  final WatchMenuState menu;
  final WatchPagerState pager;

  /// Every frame the engine announces, kept whole.
  final List<Map<String, Object?>> emitted;

  /// A session of [count] exercises (1 or 3), the position on index 0. With
  /// three the ladder reads Squat, Hinge, Press.
  static Future<_Rig> start({
    required int count,
    DateTime Function()? pagerClock,
  }) async {
    final emitted = <Map<String, Object?>>[];
    final store = InMemoryWatchSessionStore();
    final engine = WatchSessionEngine(
      store,
      onEmit: emitted.add,
      clock: _fixedClock,
      sessionIdFactory: () => 'p287-session-1',
    );
    final paths = WatchSessionStartPaths(
      engine: engine,
      store: store,
      clock: _fixedClock,
    );
    await paths.startFreeWorkout();
    if (count == 1) {
      await paths.addExerciseToSession(_a);
    } else {
      await paths.addExerciseToSession(_c);
      await paths.addExerciseToSession(_b, atIndex: 0);
      await paths.addExerciseToSession(_a, atIndex: 0);
    }
    final menu = WatchMenuState(engine: engine, paths: paths);
    final pager = WatchPagerState(menu: menu, clock: pagerClock);
    return _Rig._(engine, paths, menu, pager, emitted);
  }

  String slotAt(int index) =>
      engine.session!.exercises[index]['sessionExerciseId']! as String;

  /// The `state` of every `session_lifecycle` announced since [mark].
  List<String> lifecyclesSince(int mark) => [
    for (final frame in emitted.skip(mark))
      if (frame['type'] == 'session_lifecycle')
        (frame['payload']! as Map)['state']! as String,
  ];

  /// The `exerciseIndex` of every `session_lifecycle` announced since [mark].
  List<int> indexesSince(int mark) => [
    for (final frame in emitted.skip(mark))
      if (frame['type'] == 'session_lifecycle')
        (frame['payload']! as Map)['exerciseIndex']! as int,
  ];
}

void main() {
  test('S-28701 the page, the count and the n/N label', () async {
    final rig = await _Rig.start(count: 3);
    await rig.engine.selectExercise(rig.slotAt(1));

    expect(rig.pager.pageCount, 3);
    expect(rig.pager.currentIndex, 1);
    expect(rig.pager.currentSlotId, rig.slotAt(1));
    expect(rig.pager.pageLabel, '2/3');
    expect(rig.pager.showsPager, isTrue);
  });

  test('S-28702 one exercise shows no pager and no label', () async {
    final rig = await _Rig.start(count: 1);

    expect(rig.pager.pageCount, 1);
    expect(rig.pager.showsPager, isFalse);
    expect(rig.pager.pageLabel, isNull);
    expect(rig.pager.neighbourIndex(0, towardsNext: true), isNull);
    expect(rig.pager.neighbourIndex(0, towardsNext: false), isNull);
  });

  test(
    'S-28703 a work clock locks the pager, a running rest does not',
    () async {
      final rig = await _Rig.start(count: 3);

      await rig.engine.startTimer(WatchTimerKind.rest);
      expect(rig.pager.isLocked, isFalse, reason: 'a rest is not work');
      expect(rig.pager.showsPager, isTrue);
      expect(rig.pager.neighbourIndex(0, towardsNext: true), 1);
      await rig.engine.stopTimer(kind: WatchTimerKind.rest);

      await rig.engine.startTimer(WatchTimerKind.elapsed);
      expect(rig.pager.isLocked, isTrue);
      expect(rig.pager.showsPager, isFalse);
      expect(rig.pager.neighbourIndex(0, towardsNext: true), isNull);
      expect(
        rig.pager.pageLabel,
        '1/3',
        reason: 'the counter still shows while locked (Apple passes it too)',
      );
    },
  );

  test('S-28704 the neighbour page: next, previous, and no wrap', () async {
    final rig = await _Rig.start(count: 3);

    expect(rig.pager.neighbourIndex(0, towardsNext: false), isNull);
    expect(rig.pager.neighbourIndex(2, towardsNext: true), isNull);
    expect(rig.pager.neighbourIndex(1, towardsNext: true), 2);
    expect(rig.pager.neighbourIndex(1, towardsNext: false), 0);
  });

  test('S-28705 a settled swipe moves the session through the jump', () async {
    final rig = await _Rig.start(count: 3);
    final mark = rig.emitted.length;

    final moved = await rig.pager.land(2);

    expect(moved, isTrue);
    expect(rig.engine.session!.currentExerciseIndex, 2);
    expect(rig.lifecyclesSince(mark), [WatchLifecycleState.exerciseAdvanced]);
    expect(rig.indexesSince(mark), [2]);
  });

  test('S-28706 landing on the current page moves nothing', () async {
    final rig = await _Rig.start(count: 3);
    await rig.engine.selectExercise(rig.slotAt(1));
    final mark = rig.emitted.length;

    final moved = await rig.pager.land(1);

    expect(moved, isTrue, reason: 'it already is the current exercise');
    expect(rig.engine.session!.currentExerciseIndex, 1);
    expect(rig.emitted.length, mark, reason: 'no frame is announced');
  });

  test('S-28707 a locked swipe refuses and starts the notice', () async {
    final start = DateTime.utc(2026, 11, 21, 12);
    final rig = await _Rig.start(count: 3, pagerClock: () => start);
    await rig.engine.startTimer(WatchTimerKind.elapsed);
    final mark = rig.emitted.length;
    expect(
      rig.pager.noticeVisible(start),
      isFalse,
      reason: 'the premise: no notice before a swipe',
    );

    final moved = await rig.pager.land(1);

    expect(moved, isFalse);
    expect(rig.engine.session!.currentExerciseIndex, 0);
    expect(rig.lifecyclesSince(mark), isEmpty);
    expect(
      rig.pager.noticeVisible(start.add(const Duration(milliseconds: 1499))),
      isTrue,
    );
    expect(
      rig.pager.noticeVisible(start.add(const Duration(milliseconds: 1500))),
      isFalse,
      reason: 'the notice ends 1.5 s after the swipe, not before or after',
    );
  });

  test('S-28708 a page off the ladder changes nothing', () async {
    final rig = await _Rig.start(count: 3);
    final mark = rig.emitted.length;

    expect(await rig.pager.land(9), isFalse);
    expect(await rig.pager.land(-1), isFalse);

    expect(rig.engine.session!.currentExerciseIndex, 0);
    expect(rig.emitted.length, mark);
  });

  test('S-28709 the rows are read fresh, never cached', () async {
    final rig = await _Rig.start(count: 3);
    expect(rig.pager.pageCount, 3, reason: 'the premise: three pages');

    await rig.paths.addExerciseToEnd(_d);

    expect(rig.pager.pageCount, 4);
    expect(rig.pager.pageLabel, '1/4');
  });
}
