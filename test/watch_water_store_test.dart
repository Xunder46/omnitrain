// The phone's water frame as a stored record, and the prune that keeps only the
// newest (plan 290, D-29001).
//
// Scenario mapping:
//   S-29001  a water row round-trips through readAll; the same id is one row
//   S-29002  pruneWater keeps the named row and touches no other record type
//   S-29003  pruneWater with an id that is not stored drops nothing
//   S-29004  a water row written through Hive survives a reopen (Hive only)
//
// Plain `test()` throughout. S-29001..S-29003 run under the in-memory store and
// under Hive in a temp directory: a stored row is read back differently by each.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:omnitrain/watch/session/hive_watch_session_store.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_store.dart';

final DateTime _t = DateTime.utc(2026, 11, 22, 9);

WatchWaterRecord _water(String id, {int minutes = 0, int glasses = 3}) =>
    WatchWaterRecord(
      recordId: id,
      recordedAt: _t,
      generatedAt: _t.add(Duration(minutes: minutes)),
      day: '2026-11-22',
      glasses: glasses,
      appliedTapIds: const ['w-2', 'w-1'],
    );

void _scenarios(WatchSessionStore Function() newStore) {
  test('S-29001 a water row round-trips and the same id is one row', () async {
    final store = newStore();
    final first = await store.append(_water('w1', minutes: 5));
    final again = await store.append(_water('w1', minutes: 9, glasses: 8));
    final contents = await store.readAll();

    expect(contents.water, hasLength(1));
    final row = contents.water.single;
    expect(row.recordId, 'w1');
    expect(row.generatedAt, _t.add(const Duration(minutes: 5)));
    expect(row.day, '2026-11-22');
    expect(row.glasses, 3);
    expect(row.appliedTapIds, ['w-2', 'w-1'], reason: 'the order is kept');
    expect(row.sessionId, isEmpty);
    expect(row.sequence, first.sequence);
    expect(again.glasses, 3, reason: 'the stored row wins');
    expect(contents.isEmpty, isFalse);
  });

  test(
    'S-29002 pruneWater keeps the named row and no other type is touched',
    () async {
      final store = newStore();
      await store.append(_water('w1'));
      await store.append(_water('w2', minutes: 1));
      await store.append(_water('w3', minutes: 2));
      await store.append(
        WatchBestsRecord(
          recordId: 'b1',
          recordedAt: _t,
          generatedAt: _t,
          entries: const [],
        ),
      );
      await store.append(
        WatchPreferencesRecord(
          recordId: 'p-1',
          recordedAt: _t,
          generatedAt: _t,
          effortRatingPrompt: false,
          restPingSeconds: 0,
        ),
      );

      final dropped = await store.pruneWater(keepingRecordId: 'w3');
      final contents = await store.readAll();

      expect(dropped, unorderedEquals(['w1', 'w2']));
      expect([for (final row in contents.water) row.recordId], ['w3']);
      expect(contents.bests, hasLength(1));
      expect(contents.preferences, hasLength(1));
      expect(await store.pruneWater(keepingRecordId: 'w3'), isEmpty);
    },
  );

  test(
    'S-29003 pruneWater with an id that is not stored drops nothing',
    () async {
      final store = newStore();
      await store.append(_water('w1'));
      await store.append(_water('w2', minutes: 1));

      final dropped = await store.pruneWater(keepingRecordId: 'not-stored');

      expect(dropped, isEmpty);
      expect([
        for (final row in (await store.readAll()).water) row.recordId,
      ], unorderedEquals(['w1', 'w2']));
    },
  );
}

void main() {
  group('Mock', () {
    _scenarios(InMemoryWatchSessionStore.new);
  });

  group('Hive', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('watch_water_');
      Hive.init(tempDir.path);
    });

    tearDown(() async {
      await Hive.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    _scenarios(HiveWatchSessionStore.new);

    test(
      'S-29004 a water row written through Hive survives a reopen',
      () async {
        await HiveWatchSessionStore().append(_water('w1', minutes: 3));
        await Hive.close();
        Hive.init(tempDir.path);

        final reopened = await HiveWatchSessionStore().readAll();

        expect(reopened.water, hasLength(1));
        expect(reopened.water.single.recordId, 'w1');
        expect(
          reopened.water.single.generatedAt,
          _t.add(const Duration(minutes: 3)),
        );
        expect(reopened.water.single.appliedTapIds, ['w-2', 'w-1']);
        expect(reopened.water.single.glasses, 3);
      },
    );
  });
}
