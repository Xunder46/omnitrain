// The engine's water tap (plan 290, D-29002).
//
// Scenario mapping:
//   S-29010  a tap is stored under the day's nutrition id and emitted
//   S-29011  a tap never rides a running workout
//   S-29012  an unknown change is refused before anything is stored
//   S-29013  confirmed taps stay in the log
//   S-29014  the log is rebuilt after a relaunch
//   S-29015  the emitted frame passes the shared schema
//   S-29016  water_glass is in the kind set and is not an effort
//
// Plain `test()` throughout: the engine and the in-memory store, a fixed clock.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';

const String _protocolRoot = 'watch/sync_protocol';

/// The shared schemas, keyed the way `$ref` addresses them (`/` on every
/// platform: `file.path` has `\` on Windows).
SyncProtocolValidator _validator() {
  final root = Directory('${Directory.current.path}/$_protocolRoot/schemas');
  return SyncProtocolValidator({
    for (final file in root.listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('.json'))
        file.path.substring(root.path.length + 1).replaceAll(r'\', '/'):
            jsonDecode(file.readAsStringSync()),
  });
}

final DateTime _t = DateTime.utc(2026, 11, 22, 9, 30);

class _Rig {
  _Rig({InMemoryWatchSessionStore? store})
    : store = store ?? InMemoryWatchSessionStore() {
    engine = WatchSessionEngine(
      this.store,
      onEmit: emitted.add,
      clock: () => _t,
    );
  }

  final InMemoryWatchSessionStore store;
  final List<Map<String, Object?>> emitted = [];
  late final WatchSessionEngine engine;
}

void main() {
  test('S-29010 a tap is stored under the nutrition id and emitted', () async {
    final rig = _Rig();

    final tap = await rig.engine.logWaterGlass(
      WatchGlassChange.add,
      loggedAt: _t,
    );

    expect(tap.kind, WatchObservationKind.waterGlass);
    expect(tap.sessionId, 'nutrition-2026-11-22');
    expect(
      tap.payload.keys,
      unorderedEquals([
        'entryId',
        'eventId',
        'kind',
        'loggedAt',
        'glassChange',
      ]),
    );
    expect(tap.payload['entryId'], tap.payload['eventId']);
    expect(tap.payload['loggedAt'], '2026-11-22T09:30:00.000Z');
    expect(tap.payload['glassChange'], 'add');
    expect(rig.engine.waterLog.map((row) => row.recordId), [tap.recordId]);
    expect(
      (await rig.store.readAll()).observations.map((row) => row.recordId),
      [tap.recordId],
      reason: 'stored',
    );
    expect(rig.emitted, hasLength(1));
    expect(rig.emitted.single['type'], 'observations_up');
    expect(rig.emitted.single['sessionId'], 'nutrition-2026-11-22');
  });

  test('S-29011 a tap never rides a running workout', () async {
    final rig = _Rig();
    await rig.engine.createSession(
      modality: 'resistance_lifting',
      exercises: [
        {
          'sessionExerciseId': 'sx-a',
          'exerciseId': 'ex-a',
          'name': 'A',
          'capabilities': ['reps'],
        },
      ],
    );
    final workoutId = rig.engine.session!.sessionId;

    final tap = await rig.engine.logWaterGlass(
      WatchGlassChange.add,
      loggedAt: _t,
    );

    expect(tap.sessionId, isNot(workoutId));
    expect(tap.sessionId, 'nutrition-2026-11-22');
    expect(rig.engine.observations, isEmpty);
    expect(rig.engine.entries, isEmpty);
    final snapshot = rig.engine.sessionSnapshot()!;
    expect((snapshot['payload']! as Map)['entries'], isEmpty);
    expect(rig.engine.waterLog, hasLength(1));
  });

  test(
    'S-29012 an unknown change is refused before anything is stored',
    () async {
      final rig = _Rig();

      expect(() => rig.engine.logWaterGlass('stir'), throwsArgumentError);

      expect(rig.engine.waterLog, isEmpty);
      expect((await rig.store.readAll()).observations, isEmpty);
      expect(rig.emitted, isEmpty);
    },
  );

  test('S-29013 confirmed taps stay in the log', () async {
    final rig = _Rig();
    final taps = [
      await rig.engine.logWaterGlass(WatchGlassChange.add, loggedAt: _t),
      await rig.engine.logWaterGlass(WatchGlassChange.add, loggedAt: _t),
      await rig.engine.logWaterGlass(WatchGlassChange.remove, loggedAt: _t),
    ];

    await rig.engine.confirmObservations([taps[0].recordId, taps[1].recordId]);

    expect(rig.engine.waterLog.map((row) => row.recordId), [
      for (final tap in taps) tap.recordId,
    ]);
  });

  test('S-29014 the log is rebuilt after a relaunch', () async {
    final rig = _Rig();
    final tap = await rig.engine.logWaterGlass(
      WatchGlassChange.add,
      loggedAt: _t,
    );

    final reborn = WatchSessionEngine(rig.store, clock: () => _t);
    expect(reborn.waterLog, isEmpty, reason: 'the premise: before restore');
    await reborn.restore();

    expect(reborn.waterLog.map((row) => row.recordId), [tap.recordId]);
  });

  test('S-29015 the emitted frame passes the shared schema', () async {
    final rig = _Rig();
    await rig.engine.logWaterGlass(WatchGlassChange.remove, loggedAt: _t);

    final decision = _validator().evaluateIncoming(
      rig.emitted.single,
      receiverVersion: SyncProtocolValidator.protocolVersion,
    );

    expect(decision.accepted, isTrue, reason: decision.reason);
  });

  test('S-29016 water_glass is in the kind set and is not an effort', () {
    expect(WatchObservationKind.all, contains(WatchObservationKind.waterGlass));
    expect(
      WatchObservationKind.efforts,
      isNot(contains(WatchObservationKind.waterGlass)),
    );
    expect(WatchGlassChange.all, ['add', 'remove']);
  });

  test('S-29017 the water log holds only water taps', () async {
    final rig = _Rig();
    await rig.engine.logNutrition(foodId: 'f-oats', servings: 1, loggedAt: _t);
    final tap = await rig.engine.logWaterGlass(
      WatchGlassChange.add,
      loggedAt: _t,
    );

    expect(rig.engine.waterLog.map((row) => row.recordId), [tap.recordId]);
    expect(rig.engine.nutritionLog, hasLength(1));
  });
}
