// The day's water on the Wear wrist, as state (plan 290, D-29003..D-29006).
//
// Scenario mapping:
//   S-29020  nothing held, nothing tapped
//   S-29021  the phone's frame is the base
//   S-29022  a press shows at once
//   S-29023  a tap the frame lists is not counted twice
//   S-29024  a receipt does not take a tap out of the count
//   S-29025  taps fold in time order, never below zero
//   S-29026  a frame for another day is not today's count
//   S-29027  local midnight moves the count to the new day
//   S-29028  the cap of 500 taps a day
//   S-29029  minus at zero stores nothing
//   S-29030  taps of other days and malformed taps are ignored
//   S-29031  the frame rules
//   S-29032  the schema validator is consulted
//   S-29033  a relaunch restores the frame
//   S-29034  two frames, or two presses, at once
//
// Plain `test()` throughout: the state layer, the in-memory store, a clock the
// test moves. The clock is built from LOCAL dates (the count is the wrist's
// local day), so every scenario holds in any zone the suite runs in.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/watch/nutrition/watch_water_state.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';

const String _protocolRoot = 'watch/sync_protocol';

SyncProtocolValidator _validator() {
  final root = Directory('${Directory.current.path}/$_protocolRoot/schemas');
  return SyncProtocolValidator({
    for (final file in root.listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('.json'))
        file.path.substring(root.path.length + 1).replaceAll(r'\', '/'):
            jsonDecode(file.readAsStringSync()),
  });
}

class _Clock {
  /// Noon, local time, on a fixed day.
  DateTime local = DateTime(2026, 11, 22, 12);

  DateTime call() => local.toUtc();

  void advance(Duration delta) => local = local.add(delta);
}

String _dayOf(DateTime local) =>
    '${local.year.toString().padLeft(4, '0')}-'
    '${local.month.toString().padLeft(2, '0')}-'
    '${local.day.toString().padLeft(2, '0')}';

String _utcIso(DateTime instant) =>
    instant.toUtc().toIso8601String().replaceFirst('.000Z', 'Z');

/// A `water_down` envelope in the shape the valid fixtures carry
/// (`watch/sync_protocol/fixtures/valid/water_down.json`).
Map<String, Object?> _frame({
  String messageId = 'msg-water',
  Object? generatedAt,
  Object? day,
  Object? glasses = 0,
  Object? appliedTapIds = const <Object?>[],
}) => {
  'protocolVersion': 1,
  'messageId': messageId,
  'type': 'water_down',
  'origin': 'phone',
  'sentAt': '2026-11-22T08:00:00Z',
  'payload': {
    'generatedAt': ?generatedAt,
    'day': ?day,
    'glasses': ?glasses,
    'appliedTapIds': ?appliedTapIds,
  },
};

class _Rig {
  _Rig._(this.store, this.engine, this.clock, this.water);

  final InMemoryWatchSessionStore store;
  final WatchSessionEngine engine;
  final _Clock clock;
  final WatchWaterState water;
  int changes = 0;

  static _Rig start({
    InMemoryWatchSessionStore? store,
    SyncProtocolValidator? validator,
    _Clock? clock,
  }) {
    final c = clock ?? _Clock();
    final s = store ?? InMemoryWatchSessionStore();
    final engine = WatchSessionEngine(s, clock: c.call);
    final water = WatchWaterState(
      engine: engine,
      store: s,
      validator: validator,
      clock: c.call,
    );
    final rig = _Rig._(s, engine, c, water);
    water.onWaterChanged = () => rig.changes++;
    return rig;
  }

  /// A frame for the wrist's local today, stamped now.
  Map<String, Object?> todayFrame({
    String messageId = 'msg-water',
    int glasses = 3,
    List<String> tapIds = const [],
    DateTime? at,
  }) => _frame(
    messageId: messageId,
    generatedAt: _utcIso(at ?? clock.call()),
    day: _dayOf(clock.local),
    glasses: glasses,
    appliedTapIds: tapIds,
  );

  /// A tap logged straight through the engine at a chosen local instant.
  Future<WatchObservationRecord> tap(String change, {DateTime? at}) =>
      engine.logWaterGlass(change, loggedAt: (at ?? clock.local).toUtc());

  Future<List<String>> waterRowIds() async => [
    for (final row in (await store.readAll()).water) row.recordId,
  ];
}

void main() {
  test('S-29020 nothing held and nothing tapped reads zero', () {
    final rig = _Rig.start();

    final snapshot = rig.water.snapshot;

    expect(snapshot.glasses, 0);
    expect(snapshot.canAdd, isTrue);
    expect(snapshot.canRemove, isFalse);
    expect(snapshot.spokenCount, '0 glasses');
  });

  test('S-29021 the phone\'s frame is the base', () async {
    final rig = _Rig.start();

    expect(await rig.water.applyWaterDown(rig.todayFrame(glasses: 3)), isTrue);
    expect(rig.water.snapshot.glasses, 3);
    expect(rig.water.snapshot.spokenCount, '3 glasses');
    expect(rig.water.snapshot.canRemove, isTrue);

    await rig.water.applyWaterDown(
      rig.todayFrame(
        messageId: 'msg-water-2',
        glasses: 1,
        at: rig.clock.call().add(const Duration(minutes: 1)),
      ),
    );
    expect(rig.water.snapshot.spokenCount, '1 glass');
  });

  test('S-29022 a press shows at once', () async {
    final rig = _Rig.start();
    await rig.water.applyWaterDown(rig.todayFrame(glasses: 3));
    rig.changes = 0;

    final stored = await rig.water.press(WatchGlassChange.add);

    expect(stored, isTrue);
    expect(rig.water.snapshot.glasses, 4);
    expect(rig.changes, 1);
    expect(rig.engine.waterLog, hasLength(1));
  });

  test('S-29023 a tap the frame lists is not counted twice', () async {
    final rig = _Rig.start();
    final a = await rig.tap(WatchGlassChange.add);
    await rig.tap(
      WatchGlassChange.add,
      at: rig.clock.local.add(const Duration(seconds: 1)),
    );
    await rig.water.applyWaterDown(
      rig.todayFrame(glasses: 3, tapIds: [a.payload['entryId']! as String]),
    );

    expect(
      rig.water.snapshot.glasses,
      4,
      reason: 'the frame\'s 3 already includes `a`; the unlisted `b` adds one',
    );
  });

  test('S-29024 a receipt does not take a tap out of the count', () async {
    final rig = _Rig.start();
    await rig.water.applyWaterDown(rig.todayFrame(glasses: 3));
    final tap = await rig.tap(WatchGlassChange.add);
    expect(rig.water.snapshot.glasses, 4, reason: 'the premise');

    await rig.engine.confirmObservations([tap.recordId]);

    expect(
      rig.water.snapshot.glasses,
      4,
      reason: 'only the frame\'s list takes a tap out',
    );
  });

  test('S-29025 taps fold in time order and never below zero', () async {
    final rig = _Rig.start();
    await rig.water.applyWaterDown(rig.todayFrame(glasses: 1));
    final noon = rig.clock.local;
    // Stored out of time order: the later add first.
    await rig.tap(
      WatchGlassChange.add,
      at: noon.add(const Duration(minutes: 3)),
    );
    await rig.tap(
      WatchGlassChange.remove,
      at: noon.add(const Duration(minutes: 1)),
    );
    await rig.tap(
      WatchGlassChange.remove,
      at: noon.add(const Duration(minutes: 2)),
    );

    expect(
      rig.water.snapshot.glasses,
      1,
      reason: 'by time: 1 -> 0 -> 0 (floor) -> 1; by store order it would be 0',
    );
  });

  test('S-29026 a frame for another day is not today\'s count', () async {
    final rig = _Rig.start();
    final yesterday = rig.clock.local.subtract(const Duration(days: 1));
    await rig.water.applyWaterDown(
      _frame(
        generatedAt: _utcIso(rig.clock.call()),
        day: _dayOf(yesterday),
        glasses: 7,
      ),
    );
    expect(rig.water.snapshot.glasses, 0, reason: 'a stale day');

    await rig.tap(WatchGlassChange.add);
    await rig.tap(
      WatchGlassChange.add,
      at: rig.clock.local.subtract(const Duration(days: 2)),
    );
    await rig.tap(
      WatchGlassChange.add,
      at: DateTime(
        rig.clock.local.year,
        rig.clock.local.month,
        rig.clock.local.day,
      ).subtract(const Duration(minutes: 30)),
    );

    expect(
      rig.water.snapshot.glasses,
      1,
      reason:
          'only the tap of local today (not 2 days ago, not 23:30 last night)',
    );
  });

  test('S-29027 local midnight moves the count to the new day', () async {
    final rig = _Rig.start();
    await rig.water.applyWaterDown(rig.todayFrame(glasses: 3));
    await rig.tap(WatchGlassChange.add);
    expect(rig.water.snapshot.glasses, 4, reason: 'the premise');

    rig.clock.advance(const Duration(hours: 13));

    expect(rig.water.snapshot.glasses, 0);
    await rig.water.press(WatchGlassChange.add);
    expect(rig.water.snapshot.glasses, 1, reason: 'the new day starts fresh');
  });

  test('S-29028 the cap of 500 taps a day', () async {
    final rig = _Rig.start();
    for (var i = 0; i < WatchWaterLimits.tapsPerDay - 1; i++) {
      await rig.tap(WatchGlassChange.add);
    }
    expect(rig.water.snapshot.canAdd, isTrue, reason: '499 taps: one more');
    expect(await rig.water.press(WatchGlassChange.add), isTrue);

    final atCap = rig.water.snapshot;
    expect(atCap.canAdd, isFalse);
    expect(atCap.canRemove, isFalse);
    final before = rig.engine.waterLog.length;
    expect(await rig.water.press(WatchGlassChange.add), isFalse);
    expect(await rig.water.press(WatchGlassChange.remove), isFalse);
    expect(rig.engine.waterLog.length, before, reason: 'nothing stored');
    expect(WatchWaterLimits.tapsPerDay, 500);
  });

  test('S-29029 minus at zero stores nothing', () async {
    final rig = _Rig.start();

    expect(await rig.water.press(WatchGlassChange.remove), isFalse);

    expect(rig.engine.waterLog, isEmpty);
    expect(rig.changes, 0);
    expect(await rig.water.press('stir'), isFalse, reason: 'not a change');
  });

  test('S-29030 taps of other days and malformed taps are ignored', () async {
    final rig = _Rig.start();
    final nutritionId = WatchNutritionSession.idFor(rig.clock.call());
    for (final payload in <Map<String, Object?>>[
      {
        'entryId': 'x1',
        'eventId': 'x1',
        'kind': 'water_glass',
        'loggedAt': _utcIso(rig.clock.call()),
      },
      {
        'entryId': 'x2',
        'eventId': 'x2',
        'kind': 'water_glass',
        'loggedAt': _utcIso(rig.clock.call()),
        'glassChange': 'stir',
      },
      {
        'entryId': 'x3',
        'eventId': 'x3',
        'kind': 'water_glass',
        'loggedAt': 'yesterday',
        'glassChange': 'add',
      },
      {
        'entryId': 'x4',
        'eventId': 'x4',
        'kind': 'water_glass',
        'loggedAt': 7,
        'glassChange': 'add',
      },
      // Stored under today's session id but logged two days ago: the session
      // id alone is not the day.
      {
        'entryId': 'x5',
        'eventId': 'x5',
        'kind': 'water_glass',
        'loggedAt': _utcIso(rig.clock.call().subtract(const Duration(days: 2))),
        'glassChange': 'add',
      },
      // The same day of the month a month and a year earlier.
      {
        'entryId': 'x6',
        'eventId': 'x6',
        'kind': 'water_glass',
        'loggedAt': _utcIso(DateTime(2026, 10, 22, 12)),
        'glassChange': 'add',
      },
      {
        'entryId': 'x7',
        'eventId': 'x7',
        'kind': 'water_glass',
        'loggedAt': _utcIso(DateTime(2025, 11, 22, 12)),
        'glassChange': 'add',
      },
    ]) {
      await rig.store.append(
        WatchObservationRecord(
          recordId: payload['entryId']! as String,
          sessionId: nutritionId,
          recordedAt: rig.clock.call(),
          kind: 'water_glass',
          payload: payload,
        ),
      );
    }
    await rig.engine.restore();
    await rig.tap(
      WatchGlassChange.add,
      at: rig.clock.local.subtract(const Duration(days: 3)),
    );
    expect(rig.engine.waterLog, hasLength(8), reason: 'the premise');

    expect(rig.water.snapshot.glasses, 0, reason: 'none of them is today\'s');
    await rig.tap(WatchGlassChange.add);
    expect(rig.water.snapshot.glasses, 1);
  });

  test('S-29031 the frame rules', () async {
    final rig = _Rig.start();
    final t0 = rig.clock.call();
    DateTime at(int minutes) => t0.add(Duration(minutes: minutes));
    final today = _dayOf(rig.clock.local);

    expect(
      await rig.water.applyWaterDown(
        rig.todayFrame(messageId: 'm1', glasses: 3, at: at(10)),
      ),
      isTrue,
    );
    expect(rig.changes, 1);

    // Older: dropped.
    expect(
      await rig.water.applyWaterDown(
        rig.todayFrame(messageId: 'm0', glasses: 9, at: at(5)),
      ),
      isFalse,
    );
    expect(rig.water.snapshot.glasses, 3);

    // The same content, later: nothing written, the stamp advances in memory.
    expect(
      await rig.water.applyWaterDown(
        rig.todayFrame(messageId: 'm2', glasses: 3, at: at(20)),
      ),
      isFalse,
    );
    expect(await rig.waterRowIds(), ['water-m1']);
    expect(
      await rig.water.applyWaterDown(
        rig.todayFrame(messageId: 'm3', glasses: 5, at: at(15)),
      ),
      isFalse,
      reason: 'older than the stamp the repeat advanced to',
    );
    expect(rig.water.snapshot.glasses, 3);

    // A tie with different content: applies, one row remains.
    expect(
      await rig.water.applyWaterDown(
        rig.todayFrame(messageId: 'm4', glasses: 6, at: at(20)),
      ),
      isTrue,
    );
    expect(rig.water.snapshot.glasses, 6);
    expect(await rig.waterRowIds(), ['water-m4']);

    // Same numbers with a different id list: a change.
    expect(
      await rig.water.applyWaterDown(
        rig.todayFrame(messageId: 'm5', glasses: 6, tapIds: ['t1'], at: at(30)),
      ),
      isTrue,
    );
    expect(await rig.waterRowIds(), ['water-m5']);

    final stored = rig.changes;
    for (final bad in <Map<String, Object?>>[
      _frame(
        generatedAt: _utcIso(at(60)),
        glasses: 2,
        appliedTapIds: const <Object?>[],
      ),
      _frame(generatedAt: _utcIso(at(60)), day: today, glasses: -1),
      _frame(generatedAt: _utcIso(at(60)), day: today, glasses: 2.0),
      _frame(generatedAt: _utcIso(at(60)), day: today, glasses: 'two'),
      _frame(
        generatedAt: _utcIso(at(60)),
        day: today,
        glasses: 2,
        appliedTapIds: const <Object?>[1],
      ),
      _frame(
        generatedAt: _utcIso(at(60)),
        day: today,
        glasses: 2,
        appliedTapIds: 'none',
      ),
      _frame(generatedAt: 'later', day: today, glasses: 2),
      _frame(generatedAt: _utcIso(at(60)), day: 20261122, glasses: 2),
    ]) {
      expect(await rig.water.applyWaterDown(bad), isFalse, reason: '$bad');
    }
    expect(await rig.waterRowIds(), ['water-m5'], reason: 'nothing stored');
    expect(rig.water.snapshot.glasses, 6);
    expect(rig.changes, stored, reason: 'refused frames announce nothing');

    final wrongType = rig.todayFrame(messageId: 'm6', glasses: 1, at: at(90))
      ..['type'] = 'bests_down';
    expect(await rig.water.applyWaterDown(wrongType), isFalse);
  });

  test('S-29032 the schema validator is consulted', () async {
    final validator = _validator();
    for (final name in ['water_down', 'water_down_empty_day']) {
      final fixture =
          jsonDecode(
                File(
                  '$_protocolRoot/fixtures/valid/$name.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      final rig = _Rig.start(validator: validator);

      expect(await rig.water.applyWaterDown(fixture), isTrue, reason: name);
      expect(await rig.waterRowIds(), hasLength(1), reason: name);
    }

    final rig = _Rig.start(validator: validator);
    final extra = rig.todayFrame(glasses: 2);
    (extra['payload']! as Map<String, Object?>)['unexpected'] = 1;

    expect(
      await rig.water.applyWaterDown(extra),
      isFalse,
      reason: 'closed schema',
    );
    expect(await rig.waterRowIds(), isEmpty);
    expect(rig.water.snapshot.glasses, 0);
  });

  test('S-29033 a relaunch restores the frame', () async {
    final first = _Rig.start();
    await first.water.applyWaterDown(first.todayFrame(glasses: 3));
    await first.tap(WatchGlassChange.add);

    final fresh = _Rig.start(store: first.store, clock: first.clock);
    expect(
      fresh.water.snapshot.glasses,
      0,
      reason: 'the premise: nothing restored',
    );
    await fresh.engine.restore();
    await fresh.water.restore();

    expect(fresh.water.snapshot.glasses, 4);
    expect(fresh.changes, 1, reason: 'restore announces');
  });

  test('S-29034 two frames, or two presses, at once', () async {
    for (final newerFirst in [true, false]) {
      final rig = _Rig.start();
      final t0 = rig.clock.call();
      final older = rig.todayFrame(messageId: 'm-old', glasses: 2, at: t0);
      final newer = rig.todayFrame(
        messageId: 'm-new',
        glasses: 5,
        at: t0.add(const Duration(minutes: 1)),
      );

      await Future.wait([
        for (final frame in newerFirst ? [newer, older] : [older, newer])
          rig.water.applyWaterDown(frame),
      ]);

      expect(rig.water.snapshot.glasses, 5, reason: 'newerFirst=$newerFirst');
      expect(await rig.waterRowIds(), [
        'water-m-new',
      ], reason: 'newerFirst=$newerFirst');
    }

    final rig = _Rig.start();
    for (var i = 0; i < WatchWaterLimits.tapsPerDay - 1; i++) {
      await rig.tap(WatchGlassChange.add);
    }
    final results = await Future.wait([
      rig.water.press(WatchGlassChange.add),
      rig.water.press(WatchGlassChange.add),
    ]);
    expect(results.where((stored) => stored), hasLength(1));
    expect(rig.engine.waterLog, hasLength(WatchWaterLimits.tapsPerDay));
  });

  test('S-29035 a restore over two stored frames reads the newest', () async {
    // A kill between a frame's append and its prune leaves two rows.
    final clock = _Clock();
    final store = InMemoryWatchSessionStore();
    final today = _dayOf(clock.local);
    WatchWaterRecord row(String id, DateTime at, int glasses) =>
        WatchWaterRecord(
          recordId: id,
          recordedAt: at,
          generatedAt: at,
          day: today,
          glasses: glasses,
        );
    final noon = clock.call();
    await store.append(row('w-new', noon.add(const Duration(hours: 1)), 5));
    await store.append(row('w-old', noon, 2));
    final byTime = _Rig.start(store: store, clock: clock);
    await byTime.water.restore();
    expect(byTime.water.snapshot.glasses, 5, reason: 'the newer generatedAt');

    final tieStore = InMemoryWatchSessionStore();
    await tieStore.append(row('w-1', noon, 4));
    await tieStore.append(row('w-2', noon, 7));
    final tie = _Rig.start(store: tieStore, clock: clock);
    await tie.water.restore();
    expect(tie.water.snapshot.glasses, 7, reason: 'a tie: the later appended');
  });
}
