// Cross-stack conformance: the phone's reconciler and the wrist's engine on the
// same fixtures, in lockstep.
//
// Plan: `docs/plans/2026-09-21-13-watch-integration-shipping.md`,
// Phase 5 (D-4).
// Scenario mapping:
//   S-008 snapshot merge                  → `S-008 ...`
//   S-009 remove the current exercise     → `S-009 ...`
//
// Two engines implement the same protocol rules — `SyncSessionReconciler` on the
// phone, `WatchSessionEngine` on the wrist — and until now the shared fixtures
// held each side to the spec separately. This test holds them to *each other*:
// the same fixture replayed through both must converge on the same structure
// state, or the divergence fails here rather than on a user's wrist.
//
// What "the same" means: the ladder in order (slot id and exercise id), the
// current position, the revision, the status, and which timers exist. Entries are
// deliberately out of the comparison — the phone's reconciler takes entries from
// every `observations_up` it is handed, while the wrist is the device that
// produced them and never applies its own; a difference in entry *provenance*
// that is not a difference in structure. Entry ids are checked for agreement on
// the fixtures where the wrist does receive them, through the snapshot.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/sync_protocol/session_reconciler.dart';
import 'package:omnitrain/watch/logging/watch_logging_state.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';

const String _fixtures = 'watch/sync_protocol/fixtures/reconciliation';

final DateTime _now = DateTime.utc(2026, 9, 21, 12);

/// Deterministic clock: both engines read time only through an injected clock,
/// so the scripted five-step run is a list of instants, not a wait.
class _Clock {
  _Clock(this.now);

  DateTime now;

  DateTime call() => now;

  void advance(Duration delta) => now = now.add(delta);
}

Map<String, Object?> _asObject(Object? value) =>
    (value as Map).cast<String, Object?>();

List<Map<String, Object?>> _objectsIn(Object? value) =>
    ((value as List?) ?? const []).map(_asObject).toList(growable: false);

Map<String, Object?> _payloadOf(Map<String, Object?> envelope) =>
    _asObject(envelope['payload']);

List<Map<String, Object?>> _streamOf(Map<String, Object?> fixture) =>
    _objectsIn(fixture['stream']);

/// Every reconciliation fixture, newest protocol rules included.
List<Map<String, Object?>> _fixtures_() {
  final directory = Directory('${Directory.current.path}/$_fixtures');
  return [
    for (final file in directory.listSync().whereType<File>())
      if (file.path.endsWith('.json'))
        _asObject(jsonDecode(file.readAsStringSync())),
    // The version-mismatch fixture carries cases rather than a stream and is
    // driven by the protocol gate's own test.
  ].where((fixture) => fixture['snapshot'] != null).toList(growable: false);
}

String _fixtureName(Map<String, Object?> fixture) =>
    '${fixture['name']} ';

/// The structure state both engines must agree on.
Map<String, Object?> _structureOf(
  List<Map<String, Object?>> exercises,
  Map<String, Object?> state,
) => {
  'ladder': [
    for (final slot in exercises)
      {
        'sessionExerciseId': slot['sessionExerciseId'],
        'exerciseId': slot['exerciseId'],
      },
  ],
  'currentExerciseIndex': state['currentExerciseIndex'],
  'revision': state['revision'],
  'status': state['status'],
  'timers': ((state['timers'] as Map?)?.keys.toList() ?? const [])..sort(),
};

void main() {
  final fixtures = _fixtures_();

  test('the fixture set is the protocol register, not a hardcoded list', () {
    expect(
      Directory('${Directory.current.path}/$_fixtures')
          .listSync()
          .whereType<File>()
          .length,
      greaterThanOrEqualTo(10),
    );
  });

  for (final fixture in fixtures) {
    test('S-008/S-009 ${_fixtureName(fixture)}converges on both stacks',
        () async {
      final snapshot = _asObject(fixture['snapshot']);
      final phone = SyncSessionReconciler.fromSnapshot(_payloadOf(snapshot));
      final engine = WatchSessionEngine(
        InMemoryWatchSessionStore(),
        clock: () => _now,
      );
      await engine.applyMessage(snapshot);

      for (final message in _streamOf(fixture)) {
        phone.applyMessage(message);
        // The wrist's own product: it logged those entries, and a device does
        // not apply its own observations back onto itself.
        if (message['type'] == 'observations_up') continue;
        await engine.applyMessage(message);
      }

      final phoneState = phone.convergedState();
      final watchState = engine.sessionSnapshot()!;
      final watchPayload = _payloadOf(watchState);

      expect(
        _structureOf(engine.session!.exercises, watchPayload),
        _structureOf(
          _objectsIn(phoneState['exercises']),
          phoneState,
        ),
        reason: '${fixture['name']} diverged between the two stacks',
      );
    });
  }

  test('S-31 a snapshot\'s own entries are absorbed by both stacks, once each',
      () async {
    final fixture = fixtures.firstWhere(
      (fixture) => (fixture['name']! as String).contains('adds the entries'),
    );
    final snapshot = _asObject(fixture['snapshot']);
    final phone = SyncSessionReconciler.fromSnapshot(_payloadOf(snapshot));
    final engine = WatchSessionEngine(
      InMemoryWatchSessionStore(),
      clock: () => _now,
    );
    await engine.applyMessage(snapshot);

    final named = <String>[
      for (final entry in _objectsIn(_payloadOf(snapshot)['entries']))
        entry['entryId']! as String,
    ];

    for (final message in _streamOf(fixture)) {
      phone.applyMessage(message);
      if (message['type'] == 'observations_up') continue;
      await engine.applyMessage(message);
      if (message['type'] == 'session_snapshot') {
        named.addAll([
          for (final entry in _objectsIn(_payloadOf(message)['entries']))
            entry['entryId']! as String,
        ]);
      }
    }

    final phoneEntryIds = _objectsIn(phone.convergedState()['entries'])
        .map((entry) => entry['entryId'])
        .toList(growable: false);
    final watchEntryIds =
        engine.entries.map((entry) => entry.entryId).toList(growable: false);

    expect(
      named.toSet(),
      equals(<String>{'entry-slot-bench-0', 'entry-slot-bench-1'}),
      reason: 'the fixture names a held id and an id the wrist does not hold',
    );
    expect(
      watchEntryIds,
      containsAll(named.toSet()),
      reason: 'the wrist stores the id it does not hold and does not double '
          'the one it already has',
    );
    expect(
      phoneEntryIds,
      containsAll(named.toSet()),
      reason: 'the phone holds the entries its own answers carry',
    );
    expect(
      watchEntryIds.length,
      watchEntryIds.toSet().length,
      reason: 'no entry may be stored twice',
    );
    expect(phoneEntryIds.length, phoneEntryIds.toSet().length);
  });

  test('S-35 a held id the phone edited is re-stated on the wrist, not resaved',
      () async {
    // The shared fixture re-carries `entry-slot-bench-0` with the same values,
    // so its single `expected` block — the phone's converged state, which keeps
    // the first value it stored for a held id — cannot show the divergence a
    // real edit produces. The edit is made here, on the fixture as it is read:
    // same id, same row group, a new weight.
    final fixture = fixtures.firstWhere(
      (fixture) => (fixture['name']! as String).contains('adds the entries'),
    );
    final stream = jsonDecode(jsonEncode(_streamOf(fixture)))! as List;
    for (final message in stream.cast<Map<String, Object?>>()) {
      if (message['type'] != 'session_snapshot') continue;
      for (final entry in _objectsIn(_payloadOf(message)['entries'])) {
        if (entry['entryId'] == 'entry-slot-bench-0') entry['loadKg'] = 65;
      }
    }

    final snapshot = _asObject(fixture['snapshot']);
    final phone = SyncSessionReconciler.fromSnapshot(_payloadOf(snapshot));
    final engine = WatchSessionEngine(
      InMemoryWatchSessionStore(),
      clock: () => _now,
    );
    await engine.applyMessage(snapshot);

    for (final message in stream.cast<Map<String, Object?>>()) {
      phone.applyMessage(message);
      if (message['type'] == 'observations_up') continue;
      await engine.applyMessage(message);
    }

    Map<String, Object?> entryOf(String id) => _objectsIn(
      phone.convergedState()['entries'],
    ).firstWhere((entry) => entry['entryId'] == id);

    final wrist = {
      for (final entry in engine.entries) entry.entryId: entry.payload,
    };

    expect(
      wrist['entry-slot-bench-0']!['loadKg'],
      65,
      reason:
          'S-35 the wrist holds the id, so the answer re-states it: the wrist '
          'shows the weight the phone has now',
    );
    expect(
      entryOf('entry-slot-bench-0')['loadKg'],
      60,
      reason:
          'D-35 the phone keeps the first value it stored for a held id; only '
          'the wrist re-states, which is why the two stacks diverge here',
    );
    expect(
      wrist.keys.toList()..sort(),
      ['entry-slot-bench-0', 'entry-slot-bench-1'],
      reason: 'S-35 a re-statement neither appends a row nor drops one',
    );
    expect(wrist['entry-slot-bench-1']!['loadKg'], 62.5);
    expect(
      engine.observations.map((observation) => observation.entryId).toList(),
      ['entry-slot-bench-0', 'entry-slot-bench-1'],
      reason: 'S-35 the store is append-only: exactly one row per held id',
    );
  });

  test('S-67 a re-stated assist is neither duplicated nor zeroed', () async {
    final fixture = _asObject(
      jsonDecode(
        File(
          '${Directory.current.path}/$_fixtures/band_assist_carried.json',
        ).readAsStringSync(),
      ),
    );
    final snapshot = _asObject(fixture['snapshot']);
    final phone = SyncSessionReconciler.fromSnapshot(_payloadOf(snapshot));
    final engine = WatchSessionEngine(
      InMemoryWatchSessionStore(),
      clock: () => _now,
    );
    await engine.applyMessage(snapshot);

    for (final message in _streamOf(fixture)) {
      phone.applyMessage(message);
      // The wrist's own product: it logged that assist, and a device does not
      // apply its own observations back onto itself.
      if (message['type'] == 'observations_up') continue;
      await engine.applyMessage(message);
    }

    const expectedLoads = <String, Object?>{
      'entry-slot-bench-0': -20,
      'B7D3E1F2-9A4C-4D6E-8F10-2A3B4C5D6E7F': -22.5,
      'entry-slot-bench-1': -200,
    };

    expect(
      {
        for (final entry in _objectsIn(phone.convergedState()['entries']))
          entry['entryId']! as String: entry['loadKg'],
      },
      equals(expectedLoads),
      reason: 'S-67 the phone converges on the assist it held, the assist the '
          'wrist logged and the new floor set — none zeroed, none re-signed',
    );
    expect(
      {
        for (final entry in engine.entries)
          entry.entryId: entry.payload['loadKg'],
      },
      equals(expectedLoads),
      reason: 'S-67 the wrist shows the same three ids with the same loads',
    );
    expect(
      engine.entries.map((entry) => entry.entryId).toSet().length,
      engine.entries.length,
      reason: 'S-67 a re-statement stores no second row',
    );
  });

  test('S-009 removing the current exercise leaves both stacks on the next one',
      () async {
    final fixture = fixtures.firstWhere(
      (fixture) => (fixture['name']! as String).contains(
        'advances to the next valid exercise',
      ),
    );
    final snapshot = _asObject(fixture['snapshot']);
    final phone = SyncSessionReconciler.fromSnapshot(_payloadOf(snapshot));
    final engine = WatchSessionEngine(
      InMemoryWatchSessionStore(),
      clock: () => _now,
    );
    await engine.applyMessage(snapshot);

    final ladderBefore = [...engine.session!.exercises];
    final before = engine.session!.currentExerciseIndex;
    final removed =
        ladderBefore[before]['sessionExerciseId']! as String;

    for (final message in _streamOf(fixture)) {
      phone.applyMessage(message);
      await engine.applyMessage(message);
    }

    final after = phone.convergedState();
    final ladderAfter = engine.session!.exercises;

    // The point of the fixture: the position stays inside the ladder and moves
    // to the exercise that followed the removed one, on both stacks.
    expect(
      ladderAfter.any((slot) => slot['sessionExerciseId'] == removed),
      isFalse,
    );
    expect(engine.session!.currentExerciseIndex, after['currentExerciseIndex']);
    expect(engine.session!.currentExerciseIndex, lessThan(ladderAfter.length));
  });

  test('S-335 the scripted run leaves three rests, the same in both stacks',
      () async {
    final clock = _Clock(_now);
    final emitted = <Map<String, Object?>>[];
    final store = InMemoryWatchSessionStore();
    final engine = WatchSessionEngine(
      store,
      clock: clock.call,
      onEmit: emitted.add,
    );
    await engine.createSession(
      modality: 'resistance_lifting',
      exercises: [
        {
          'sessionExerciseId': 'sx-bench',
          'exerciseId': 'ex-bench',
          'name': 'Bench Press',
          'capabilities': const ['reps', 'sets', 'load'],
        },
      ],
    );
    final surface = WatchLoggingState(engine: engine, clock: clock.call);

    await surface.log(); // A at T0
    clock.advance(const Duration(seconds: 45));
    await surface.log(); // B at T0+45s, which ends R1
    clock.advance(const Duration(seconds: 15));
    await surface.log(); // C at T0+60s, which ends R2
    clock.advance(const Duration(seconds: 30));
    await surface.endRest(); // Next at T0+90s, which ends R3
    clock.advance(const Duration(seconds: 30));
    await engine.finishSession(); // End at T0+120s, no rest running

    final events = [
      for (final envelope in emitted)
        if (envelope['type'] == 'observations_up')
          for (final event in _objectsIn(_payloadOf(envelope)['events'])) event,
    ];
    expect(
      [for (final event in events) event['kind']],
      ['set', 'rest', 'set', 'rest', 'set', 'rest'],
      reason: 'S-335 rest(R1) < B < rest(R2) < C < rest(R3), and End adds none',
    );

    final sets = [
      for (final event in events)
        if (event['kind'] == 'set') event,
    ];
    final rests = [
      for (final event in events)
        if (event['kind'] == 'rest') event,
    ];
    expect(
      [for (final rest in rests) rest['afterEntryId']],
      [for (final set in sets) set['entryId']],
      reason: 'S-335 each rest follows the set that ended it',
    );
    expect(
      [for (final rest in rests) rest['startedAt']],
      [
        utcIso(_now),
        utcIso(_now.add(const Duration(seconds: 45))),
        utcIso(_now.add(const Duration(seconds: 60))),
      ],
      reason: 'S-335 each rest starts at the instant its set was logged',
    );
    expect(
      [for (final rest in rests) rest['endedAt']],
      [
        utcIso(_now.add(const Duration(seconds: 45))),
        utcIso(_now.add(const Duration(seconds: 60))),
        utcIso(_now.add(const Duration(seconds: 90))),
      ],
      reason: 'S-335 the windows are 45 s, 15 s and 30 s',
    );

    expect(
      [
        for (final row in (await store.readAll()).observations)
          if (row.kind == WatchObservationKind.rest)
            [row.payload['startedAt'], row.payload['endedAt']],
      ],
      [
        for (final rest in rests) [rest['startedAt'], rest['endedAt']],
      ],
      reason: 'S-335 emitted state is stored state',
    );
  });
}
