// The phone's bests frame as a stored record, and the one prune that keeps only
// the newest (plan 288, D-28801, D-28802).
//
// Scenario mapping:
//   S-28801  a bests row round-trips through readAll; the same id is one row
//   S-28802  pruneBests keeps the named row and touches no other record type
//   S-28803  pruneBests with an id that is not stored drops nothing
//   S-28804  a bests row written through Hive survives a reopen (Hive only)
//
// Plain `test()` throughout (no widgets). S-28801..S-28803 run under the
// in-memory store and under Hive in a temp directory: a stored row is read
// back differently by each, so one passing is no proof of the other.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:omnitrain/watch/session/hive_watch_session_store.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_store.dart';

final DateTime _t = DateTime.utc(2026, 11, 22, 9);

WatchBestsRecord _bests(String id, {int minutes = 0}) => WatchBestsRecord(
  recordId: id,
  recordedAt: _t,
  generatedAt: _t.add(Duration(minutes: minutes)),
  entries: const [
    {'exerciseId': 'ex-bench', 'e1rmKg': 116.66666666666667},
    {'exerciseId': 'ex-push-up', 'repsBest': 12},
  ],
);

void _scenarios(WatchSessionStore Function() newStore) {
  test('S-28801 a bests row round-trips and the same id is one row', () async {
    final store = newStore();
    final first = await store.append(_bests('b1', minutes: 5));
    final again = await store.append(_bests('b1', minutes: 9));
    final contents = await store.readAll();

    expect(contents.bests, hasLength(1));
    final row = contents.bests.single;
    expect(row.recordId, 'b1');
    expect(row.generatedAt, _t.add(const Duration(minutes: 5)));
    expect(row.entries, [
      {'exerciseId': 'ex-bench', 'e1rmKg': 116.66666666666667},
      {'exerciseId': 'ex-push-up', 'repsBest': 12},
    ]);
    expect(row.sessionId, isEmpty);
    expect(row.sequence, first.sequence);
    expect(again.generatedAt, first.generatedAt, reason: 'the stored row wins');
    expect(contents.isEmpty, isFalse);
  });

  test(
    'S-28802 pruneBests keeps the named row and no other type is touched',
    () async {
      final store = newStore();
      await store.append(_bests('b1'));
      await store.append(_bests('b2', minutes: 1));
      await store.append(_bests('b3', minutes: 2));
      await store.append(
        WatchSessionRecord(
          recordId: 's-1',
          sessionId: 's-1',
          recordedAt: _t,
          startedAt: _t,
          modality: null,
          source: 'watch',
          status: WatchSessionStatus.active,
          currentExerciseIndex: 0,
          exercises: const [],
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

      final dropped = await store.pruneBests(keepingRecordId: 'b3');
      final contents = await store.readAll();

      expect(dropped, unorderedEquals(['b1', 'b2']));
      expect([for (final row in contents.bests) row.recordId], ['b3']);
      expect(contents.sessions, hasLength(1));
      expect(contents.preferences, hasLength(1));
      expect(await store.pruneBests(keepingRecordId: 'b3'), isEmpty);
    },
  );

  test(
    'S-28803 pruneBests with an id that is not stored drops nothing',
    () async {
      final store = newStore();
      await store.append(_bests('b1'));
      await store.append(_bests('b2', minutes: 1));

      final dropped = await store.pruneBests(keepingRecordId: 'not-stored');

      expect(dropped, isEmpty);
      expect([
        for (final row in (await store.readAll()).bests) row.recordId,
      ], unorderedEquals(['b1', 'b2']));
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
      tempDir = await Directory.systemTemp.createTemp('watch_bests_');
      Hive.init(tempDir.path);
    });

    tearDown(() async {
      await Hive.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    _scenarios(HiveWatchSessionStore.new);

    test(
      'S-28804 a bests row written through Hive survives a reopen',
      () async {
        await HiveWatchSessionStore().append(_bests('b1', minutes: 3));
        await Hive.close();
        Hive.init(tempDir.path);

        final reopened = await HiveWatchSessionStore().readAll();

        expect(reopened.bests, hasLength(1));
        expect(reopened.bests.single.recordId, 'b1');
        expect(
          reopened.bests.single.generatedAt,
          _t.add(const Duration(minutes: 3)),
        );
        expect(reopened.bests.single.entries.first['exerciseId'], 'ex-bench');
      },
    );
  });
}
