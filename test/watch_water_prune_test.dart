// The launch prune of old confirmed water taps (plan 302, D-30201..D-30203).
//
// Scenario mapping:
//   S-30201  the receipt and the age decide: what goes and what stays
//   S-30202  a prune that finds nothing drops and writes nothing
//   S-30203  the engine's memory follows the store
//   S-30204  WatchWaterState.restore prunes; the count does not change
//   S-30205  the retention outlasts the longest local day by a day
//   S-30206  only restore prunes, never the radio or the tap path
//
// Plain `test()` throughout. S-30201..S-30203 run under the in-memory store and
// under Hive in a temp directory: a stored row is read back differently by each.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:omnitrain/watch/nutrition/watch_water_state.dart';
import 'package:omnitrain/watch/session/hive_watch_session_store.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';
import 'package:omnitrain/watch/session/watch_session_store.dart';

final DateTime _now = DateTime.utc(2026, 11, 22, 9);
final DateTime _cutoff = _now.subtract(const Duration(hours: 72));

String _iso(DateTime instant) => instant.toUtc().toIso8601String();

/// A water tap logged [age] before [_now].
WatchObservationRecord _tap(
  String id,
  Duration age, {
  Object? loggedAt,
  String kind = WatchObservationKind.waterGlass,
}) => WatchObservationRecord(
  recordId: id,
  sessionId: 'nutrition-2026-11-22',
  recordedAt: _now.subtract(age),
  kind: kind,
  payload: {
    'entryId': id,
    'eventId': id,
    'kind': kind,
    'loggedAt': loggedAt ?? _iso(_now.subtract(age)),
    if (kind == WatchObservationKind.waterGlass) 'glassChange': 'add',
  },
);

WatchConfirmationRecord _receipt(String id, List<String> observationIds) =>
    WatchConfirmationRecord(
      recordId: id,
      sessionId: 'nutrition-2026-11-22',
      recordedAt: _now,
      observationIds: observationIds,
    );

/// The fixture of S-30201: every kind of tap there is, around the cutoff.
Future<void> _seed(WatchSessionStore store) async {
  await store.append(_tap('old-4d', const Duration(days: 4)));
  await store.append(_tap('old-73h', const Duration(hours: 73)));
  await store.append(_tap('recent-71h', const Duration(hours: 71)));
  await store.append(_tap('at-cutoff', const Duration(hours: 72)));
  await store.append(_tap('open-4d', const Duration(days: 4)));
  await store.append(
    _tap('set-4d', const Duration(days: 4), kind: WatchObservationKind.set),
  );
  await store.append(
    _tap('unreadable', const Duration(days: 4), loggedAt: 'not a time'),
  );
  await store.append(_tap('no-time', const Duration(days: 4), loggedAt: 12345));
  await store.append(
    _receipt('r-1', [
      'old-4d',
      'old-73h',
      'recent-71h',
      'at-cutoff',
      'set-4d',
      'unreadable',
      'no-time',
    ]),
  );
}

List<String> _ids(WatchStoreContents contents) => [
  for (final observation in contents.observations) observation.recordId,
];

void _scenarios(WatchSessionStore Function() newStore) {
  test('S-30201 the receipt and the age decide what goes', () async {
    final store = newStore();
    await _seed(store);

    final dropped = await store.pruneWaterTaps(loggedBefore: _cutoff);
    final left = await store.readAll();

    expect(dropped, ['old-4d', 'old-73h']);
    expect(
      _ids(left),
      unorderedEquals([
        'recent-71h',
        'at-cutoff',
        'open-4d',
        'set-4d',
        'unreadable',
        'no-time',
      ]),
    );
    expect(
      left.confirmations.map((row) => row.recordId),
      ['r-1'],
      reason: 'the confirmation rows stay',
    );
    final byId = {
      for (final observation in left.observations)
        observation.recordId: observation,
    };
    expect(byId['recent-71h']!.confirmedAt, isNotNull);
    expect(byId['open-4d']!.confirmedAt, isNull);
  });

  test('S-30202 a prune that finds nothing drops and writes nothing', () async {
    final store = newStore();
    await _seed(store);
    await store.pruneWaterTaps(loggedBefore: _cutoff);
    final before = _ids(await store.readAll());

    final again = await store.pruneWaterTaps(loggedBefore: _cutoff);

    expect(again, isEmpty);
    expect(_ids(await store.readAll()), before);
    expect(
      await newStore().pruneWaterTaps(loggedBefore: _cutoff),
      isEmpty,
      reason: 'an empty store',
    );
  });

  test('S-30203 the engine memory follows the store', () async {
    final store = newStore();
    await _seed(store);
    final engine = WatchSessionEngine(store, clock: () => _now);
    await engine.restore();
    expect(engine.waterLog.map((row) => row.recordId), contains('old-4d'));

    final dropped = await engine.pruneWaterTaps(loggedBefore: _cutoff);

    expect(dropped, ['old-4d', 'old-73h']);
    final kept = engine.waterLog.map((row) => row.recordId).toList();
    expect(kept, isNot(contains('old-4d')));
    expect(kept, isNot(contains('old-73h')));
    expect(
      kept,
      containsAll(['recent-71h', 'at-cutoff', 'open-4d', 'unreadable']),
    );
  });
}

void main() {
  group('Mock', () {
    _scenarios(InMemoryWatchSessionStore.new);
  });

  group('Hive', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('watch_water_prune_');
      Hive.init(tempDir.path);
    });

    tearDown(() async {
      await Hive.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    _scenarios(HiveWatchSessionStore.new);
  });

  test('S-30204 restore prunes and the count does not change', () async {
    final store = InMemoryWatchSessionStore();
    final engine = WatchSessionEngine(store, clock: () => _now);
    final water = WatchWaterState(
      engine: engine,
      store: store,
      clock: () => _now,
    );
    // Taps of local today are never candidates: one confirmed, one open.
    final today = await engine.logWaterGlass('add', loggedAt: _now);
    await store.append(_receipt('r-today', [today.recordId]));
    await engine.logWaterGlass('add', loggedAt: _now);
    await store.append(_tap('old-73h', const Duration(hours: 73)));
    await store.append(_tap('recent-71h', const Duration(hours: 71)));
    await store.append(_tap('open-5d', const Duration(days: 5)));
    await store.append(_receipt('r-old', ['old-73h', 'recent-71h']));
    await engine.restore();
    await water.restore();
    // `restore` pruned inside the first call; seed again to read the contrast.
    expect(
      _ids(await store.readAll()),
      isNot(contains('old-73h')),
      reason: 'the 73 h confirmed tap is gone',
    );
    expect(
      _ids(await store.readAll()),
      containsAll(['recent-71h', 'open-5d', today.recordId]),
    );
    final glasses = water.snapshot.glasses;

    await water.restore();

    expect(water.snapshot.glasses, glasses, reason: 'the count is unchanged');
    expect(glasses, 2, reason: 'both taps of today count');
  });

  test('S-30205 the retention outlasts the longest local day by a day', () {
    expect(WatchWaterLimits.confirmedTapRetention, const Duration(hours: 72));
    expect(
      WatchWaterLimits.confirmedTapRetention.inHours,
      greaterThanOrEqualTo(49),
    );
  });

  test('S-30206 only restore prunes, never the radio or the tap path', () {
    final callers = <String>[];
    for (final entity in Directory('lib/watch').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final text = entity.readAsStringSync();
      for (final match in RegExp(r'[eE]ngine\.pruneWaterTaps\(').allMatches(text)) {
        callers.add('${entity.path.replaceAll(r'\', '/')}:${match.start}');
      }
    }

    expect(callers, hasLength(1));
    expect(
      callers.single,
      startsWith('lib/watch/nutrition/watch_water_state.dart'),
    );
    final source = File(
      'lib/watch/nutrition/watch_water_state.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final restore = source.substring(
      source.indexOf('Future<void> restore() async {'),
      source.indexOf('Future<bool> applyWaterDown('),
    );
    expect(restore, contains('_engine.pruneWaterTaps('));
    expect(
      restore.indexOf('_engine.pruneWaterTaps('),
      lessThan(restore.indexOf('_store.readAll()')),
      reason: 'the prune comes before the held frame is read',
    );
    expect(
      restore,
      contains('_clock().subtract(WatchWaterLimits.confirmedTapRetention)'),
    );
  });
}
