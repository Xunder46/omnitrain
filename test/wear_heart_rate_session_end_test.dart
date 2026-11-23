// The Wear wrist sends the session's heart rate on `session_end` (plan 310).
//
// Plan: `docs/plans/2026-11-22-310-wear-heart-rate-session-end-plan/2026-11-22-310-wear-heart-rate-session-end-plan.md`
//   S-31001 the heart-rate window, both ends inclusive
//   S-31002 absence is the answer: nothing measured sends nothing
//   S-31003 a set block's span, and what never makes or leads one
//   S-31004 interleaved blocks, out-of-order entries, the 10:20 tie
//   S-31005 the session end carries the pair and one pair per set block
//   S-31006 no readings, or readings outside every block span
//   S-31007 a followed end, and a set the phone deleted
//   S-31008 the emission validator accepts the engine's own entries
//
// Mock-first. Plain `test()` for the state layer; widget tests never await a
// real `Future.delayed`.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_sensor_summaries.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';

class _Clock {
  _Clock(this.now);
  DateTime now;
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

final DateTime _t0 = DateTime.utc(2026, 1, 5, 10);

WatchSensorSampleRecord hr(
  double bpm,
  int minute,
  int second,
) => WatchSensorSampleRecord(
  recordId:
      'hr-${_t0.add(Duration(minutes: minute, seconds: second)).toUtc().millisecondsSinceEpoch}-$bpm',
  sessionId: 's',
  recordedAt: _t0.add(Duration(minutes: minute, seconds: second)),
  kind: WatchSensorKind.heartRate,
  value: bpm,
);

WatchSensorSampleRecord _steps(
  double count,
  int minute,
) => WatchSensorSampleRecord(
  recordId:
      'steps-${_t0.add(Duration(minutes: minute)).toUtc().millisecondsSinceEpoch}',
  sessionId: 's',
  recordedAt: _t0.add(Duration(minutes: minute)),
  kind: WatchSensorKind.steps,
  value: count,
);

/// One `set` effort as the wrist's logging hands it to the engine.
Map<String, Object?> _setEntry(
  String id, {
  required String slot,
  required String exercise,
  required DateTime at,
}) => {
  'entryId': id,
  'eventId': id,
  'kind': 'set',
  'loggedAt': utcIso(at),
  'sessionExerciseId': slot,
  'exerciseId': exercise,
  'reps': 5,
  'loadKg': 80,
};

/// One entry that is not a set: [kind] as the wire spells it.
Map<String, Object?> _otherEntry(
  String id, {
  required String kind,
  required DateTime at,
  String? slot,
  String? exercise,
}) => {
  'entryId': id,
  'eventId': id,
  'kind': kind,
  'loggedAt': utcIso(at),
  'sessionExerciseId': ?slot,
  'exerciseId': ?exercise,
};

Map<String, Object?> _slot(String id) => {
  'sessionExerciseId': id,
  'exerciseId': 'ex-$id',
  'name': id,
  'capabilities': ['reps', 'sets', 'load'],
};

SyncProtocolValidator _validator() {
  final root = Directory(
    '${Directory.current.path}/watch/sync_protocol/schemas',
  );
  return SyncProtocolValidator({
    for (final file in root.listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('.json'))
        file.path.substring(root.path.length + 1).replaceAll(r'\', '/'):
            jsonDecode(file.readAsStringSync()),
  });
}

class _Rig {
  _Rig({bool validate = true})
    : clock = _Clock(_t0),
      store = InMemoryWatchSessionStore() {
    engine = WatchSessionEngine(
      store,
      clock: clock.call,
      onEmit: emitted.add,
      validator: validate ? _validator() : null,
    );
  }

  final _Clock clock;
  final InMemoryWatchSessionStore store;
  final List<Map<String, Object?>> emitted = [];
  late final WatchSessionEngine engine;

  Future<WatchSessionRecord> start({String source = 'watch'}) =>
      engine.createSession(
        modality: 'resistance_lifting',
        source: source,
        exercises: [_slot('slotA'), _slot('slotB')],
      );

  Map<String, Object?>? sessionEnd(String sessionId) {
    for (final frame in engine.pendingObservations()) {
      for (final event in (frame['payload']! as Map)['events'] as List) {
        final map = (event as Map).cast<String, Object?>();
        if (map['kind'] == WatchObservationKind.sessionEnd) return map;
      }
    }
    return null;
  }
}

void main() {
  group('S-31001 the heart-rate window, both ends inclusive', () {
    test('the window keeps the readings at both ends and ignores the rest', () {
      final pair = WatchSensorSummaries.heartRate(
        [
          hr(60, -1, 59), // before the window
          hr(100, 0, 0), // at the start instant
          hr(120, 5, 0),
          hr(140, 10, 0),
          hr(160, 30, 0), // at the end instant
          hr(180, 30, 1), // a millisecond past the end
          hr(0.5, 15, 0), // below the protocol's floor
          hr(double.nan, 16, 0), // not a measurement
          _steps(999, 20), // another kind
        ],
        _t0,
        _t0.add(const Duration(minutes: 30)),
      );

      expect(pair, isNotNull);
      expect(pair!.averageBpm, 130);
      expect(pair.maximumBpm, 160);
    });

    test('each non-qualifying reading alone gives null', () {
      final ignored = <List<WatchSensorSampleRecord>>[
        [hr(60, -1, 59)], // before the window
        [hr(180, 30, 1)], // past the end
        [hr(0.5, 15, 0)], // below the floor
        [hr(double.nan, 16, 0)], // not finite
        [_steps(999, 20)], // another kind
      ];

      for (final samples in ignored) {
        expect(
          WatchSensorSummaries.heartRate(
            samples,
            _t0,
            _t0.add(const Duration(minutes: 30)),
          ),
          isNull,
          reason:
              '${samples.first.value} at '
              '${utcIso(samples.first.recordedAt)} does not qualify',
        );
      }
    });
  });

  group('S-31002 absence is the answer', () {
    final window = (_t0, _t0.add(const Duration(minutes: 30)));

    test('a reading only before the window gives null', () {
      expect(
        WatchSensorSummaries.heartRate([hr(60, -1, 59)], window.$1, window.$2),
        isNull,
      );
    });

    test('an empty list gives null', () {
      expect(
        WatchSensorSummaries.heartRate(const [], window.$1, window.$2),
        isNull,
      );
    });

    test('only readings below the floor give null', () {
      expect(
        WatchSensorSummaries.heartRate(
          [hr(0.5, 15, 0), hr(0.9, 16, 0)],
          window.$1,
          window.$2,
        ),
        isNull,
      );
    });
  });

  group('S-31003 a set block and its span', () {
    test('blocks come out in the order they began, each over its span', () {
      final spans = WatchSensorSummaries.blockSpans([
        _setEntry(
          'e1',
          slot: 'slotA',
          exercise: 'exA',
          at: _t0.add(const Duration(minutes: 2)),
        ),
        _setEntry(
          'e2',
          slot: 'slotA',
          exercise: 'exA',
          at: _t0.add(const Duration(minutes: 6)),
        ),
        _setEntry(
          'e3',
          slot: 'slotB',
          exercise: 'exB',
          at: _t0.add(const Duration(minutes: 12)),
        ),
        _otherEntry(
          'e4',
          kind: 'timed',
          at: _t0.add(const Duration(minutes: 20)),
          slot: 'slotC',
          exercise: 'exC',
        ),
        _otherEntry(
          'e5',
          kind: 'rest',
          at: _t0.add(const Duration(minutes: 13)),
          slot: 'slotA',
          exercise: 'exA',
        ),
        {
          'entryId': 'e6',
          'eventId': 'e6',
          'kind': 'set',
          'loggedAt': 'not-a-time',
          'sessionExerciseId': 'slotA',
          'exerciseId': 'exA',
          'reps': 5,
          'loadKg': 80,
        },
        {
          'entryId': 'e7',
          'eventId': 'e7',
          'kind': 'set',
          'loggedAt': utcIso(_t0.add(const Duration(minutes: 14))),
          'reps': 5,
          'loadKg': 80,
        },
      ], _t0);

      expect(spans, hasLength(2));
      expect(spans[0].sessionExerciseId, 'slotA');
      expect(spans[0].exerciseId, 'exA');
      expect(spans[0].startedAt, _t0);
      expect(spans[0].endedAt, _t0.add(const Duration(minutes: 6)));
      expect(spans[1].sessionExerciseId, 'slotB');
      expect(spans[1].exerciseId, 'exB');
      expect(spans[1].startedAt, _t0.add(const Duration(minutes: 6)));
      expect(spans[1].endedAt, _t0.add(const Duration(minutes: 12)));
    });
  });

  group('S-31004 interleaved blocks and the tie', () {
    test(
      'the tie at 10:20 breaks by entryId, and each block leads from its own effort',
      () {
        final spans = WatchSensorSummaries.blockSpans([
          _setEntry(
            's-b',
            slot: 'slotD',
            exercise: 'exD',
            at: _t0.add(const Duration(minutes: 20)),
          ),
          _setEntry(
            'a1',
            slot: 'slotA',
            exercise: 'exA',
            at: _t0.add(const Duration(minutes: 2)),
          ),
          _setEntry(
            'b1',
            slot: 'slotB',
            exercise: 'exB',
            at: _t0.add(const Duration(minutes: 5)),
          ),
          _setEntry(
            'a2',
            slot: 'slotA',
            exercise: 'exA',
            at: _t0.add(const Duration(minutes: 8)),
          ),
          _setEntry(
            's-a',
            slot: 'slotC',
            exercise: 'exC',
            at: _t0.add(const Duration(minutes: 20)),
          ),
        ], _t0);

        expect(spans.map((span) => span.sessionExerciseId), [
          'slotA',
          'slotB',
          'slotC',
          'slotD',
        ]);
        expect(spans[0].startedAt, _t0);
        expect(spans[0].endedAt, _t0.add(const Duration(minutes: 8)));
        expect(spans[1].startedAt, _t0.add(const Duration(minutes: 2)));
        expect(spans[1].endedAt, _t0.add(const Duration(minutes: 5)));
        expect(spans[2].startedAt, _t0.add(const Duration(minutes: 8)));
        expect(spans[2].endedAt, _t0.add(const Duration(minutes: 20)));
        expect(spans[3].startedAt, _t0.add(const Duration(minutes: 8)));
        expect(spans[3].endedAt, _t0.add(const Duration(minutes: 20)));
      },
    );
  });

  group(
    'S-31005 the session end carries the pair and one pair per set block',
    () {
      test('a wrist-created session with readings over every span', () async {
        final rig = _Rig(validate: false);
        await rig.start();
        await rig.engine.appendSensorSample(
          kind: WatchSensorKind.heartRate,
          value: 100,
          recordedAt: _t0.add(const Duration(minutes: 1)),
        );
        await rig.engine.appendSensorSample(
          kind: WatchSensorKind.heartRate,
          value: 120,
          recordedAt: _t0.add(const Duration(minutes: 5)),
        );
        await rig.engine.appendSensorSample(
          kind: WatchSensorKind.heartRate,
          value: 140,
          recordedAt: _t0.add(const Duration(minutes: 10)),
        );
        await rig.engine.appendObservation(
          _setEntry(
            'e1',
            slot: 'slotA',
            exercise: 'exA',
            at: _t0.add(const Duration(minutes: 2)),
          ),
        );
        await rig.engine.appendObservation(
          _setEntry(
            'e2',
            slot: 'slotA',
            exercise: 'exA',
            at: _t0.add(const Duration(minutes: 6)),
          ),
        );
        await rig.engine.appendObservation(
          _setEntry(
            'e3',
            slot: 'slotB',
            exercise: 'exB',
            at: _t0.add(const Duration(minutes: 12)),
          ),
        );
        rig.clock.advance(const Duration(minutes: 30));
        await rig.engine.finishSession();

        final end = rig.sessionEnd(rig.engine.session!.sessionId);
        expect(end, isNotNull);
        expect(end!['avgHeartRateBpm'], 120);
        expect(end['maxHeartRateBpm'], 140);

        final blocks = end['setBlockHeartRates']! as List;
        expect(blocks, hasLength(2));
        expect(blocks[0], {
          'sessionExerciseId': 'slotA',
          'exerciseId': 'exA',
          'startedAt': '2026-01-05T10:00:00.000Z',
          'endedAt': '2026-01-05T10:06:00.000Z',
          'avgHeartRateBpm': 110,
          'maxHeartRateBpm': 120,
        });
        expect(blocks[1], {
          'sessionExerciseId': 'slotB',
          'exerciseId': 'exB',
          'startedAt': '2026-01-05T10:06:00.000Z',
          'endedAt': '2026-01-05T10:12:00.000Z',
          'avgHeartRateBpm': 140,
          'maxHeartRateBpm': 140,
        });
      });
    },
  );

  group('S-31006 absence over the whole session, and over every span', () {
    test(
      'a session with no heart-rate samples sends none of the keys',
      () async {
        final rig = _Rig(validate: false);
        await rig.start();
        await rig.engine.appendObservation(
          _setEntry(
            'e1',
            slot: 'slotA',
            exercise: 'exA',
            at: _t0.add(const Duration(minutes: 2)),
          ),
        );
        rig.clock.advance(const Duration(minutes: 30));
        await rig.engine.finishSession();

        final end = rig.sessionEnd(rig.engine.session!.sessionId)!;
        expect(end.containsKey('avgHeartRateBpm'), isFalse);
        expect(end.containsKey('maxHeartRateBpm'), isFalse);
        expect(end.containsKey('setBlockHeartRates'), isFalse);
      },
    );

    test(
      'readings outside every block span keep the session pair only',
      () async {
        final rig = _Rig(validate: false);
        await rig.start();
        await rig.engine.appendSensorSample(
          kind: WatchSensorKind.heartRate,
          value: 140,
          recordedAt: _t0.add(const Duration(minutes: 20)),
        );
        await rig.engine.appendObservation(
          _setEntry(
            'e1',
            slot: 'slotA',
            exercise: 'exA',
            at: _t0.add(const Duration(minutes: 2)),
          ),
        );
        await rig.engine.appendObservation(
          _setEntry(
            'e2',
            slot: 'slotA',
            exercise: 'exA',
            at: _t0.add(const Duration(minutes: 6)),
          ),
        );
        rig.clock.advance(const Duration(minutes: 30));
        await rig.engine.finishSession();

        final end = rig.sessionEnd(rig.engine.session!.sessionId)!;
        expect(end['avgHeartRateBpm'], 140);
        expect(end['maxHeartRateBpm'], 140);
        expect(end.containsKey('setBlockHeartRates'), isFalse);
      },
    );
  });

  group('S-31007 a followed end, and a set the phone deleted', () {
    test('a followed session carries the pair and followed: true', () async {
      final rig = _Rig(validate: false);
      await rig.start(source: 'phone');
      await rig.engine.appendSensorSample(
        kind: WatchSensorKind.heartRate,
        value: 100,
        recordedAt: _t0.add(const Duration(minutes: 1)),
      );
      await rig.engine.appendSensorSample(
        kind: WatchSensorKind.heartRate,
        value: 160,
        recordedAt: _t0.add(const Duration(minutes: 5)),
      );
      await rig.engine.appendObservation(
        _setEntry(
          'e1',
          slot: 'slotA',
          exercise: 'exA',
          at: _t0.add(const Duration(minutes: 2)),
        ),
      );
      rig.clock.advance(const Duration(minutes: 30));
      await rig.engine.finishSession();

      final end = rig.sessionEnd(rig.engine.session!.sessionId)!;
      expect(end['followed'], true);
      expect(end['avgHeartRateBpm'], 130);
      expect(end['maxHeartRateBpm'], 160);
      expect(end['setBlockHeartRates'], hasLength(1));
    });

    test('a set the phone deleted is not a block member', () async {
      final rig = _Rig(validate: false);
      await rig.start();
      await rig.engine.appendSensorSample(
        kind: WatchSensorKind.heartRate,
        value: 100,
        recordedAt: _t0.add(const Duration(minutes: 1)),
      );
      await rig.engine.appendSensorSample(
        kind: WatchSensorKind.heartRate,
        value: 140,
        recordedAt: _t0.add(const Duration(minutes: 10)),
      );
      await rig.engine.appendObservation(
        _setEntry(
          'e1',
          slot: 'slotA',
          exercise: 'exA',
          at: _t0.add(const Duration(minutes: 2)),
        ),
      );
      await rig.engine.appendObservation(
        _setEntry(
          'e2',
          slot: 'slotA',
          exercise: 'exA',
          at: _t0.add(const Duration(minutes: 6)),
        ),
      );
      await rig.engine.appendObservation(
        _setEntry(
          'e3',
          slot: 'slotB',
          exercise: 'exB',
          at: _t0.add(const Duration(minutes: 12)),
        ),
      );
      expect(
        await rig.engine.applyMessage({
          'protocolVersion': SyncProtocolValidator.protocolVersion,
          'messageId': 'msg-delete-1',
          'sessionId': rig.engine.session!.sessionId,
          'type': 'structure_change',
          'origin': 'phone',
          'sentAt': utcIso(_t0.add(const Duration(minutes: 15))),
          'payload': <String, Object?>{
            'changeId': 'chg-1',
            'changes': [
              <String, Object?>{'kind': 'delete_entry', 'entryId': 'e3'},
            ],
          },
        }),
        isTrue,
      );
      rig.clock.advance(const Duration(minutes: 30));
      await rig.engine.finishSession();

      final end = rig.sessionEnd(rig.engine.session!.sessionId)!;
      final blocks = end['setBlockHeartRates']! as List;
      expect(blocks, hasLength(1));
      expect((blocks.first as Map)['sessionExerciseId'], 'slotA');
    });
  });

  group('S-31008 the emission validator accepts the engine\'s own entries', () {
    test('a session_end the engine builds passes its own validator', () async {
      final rig = _Rig();
      await rig.start();
      await rig.engine.appendSensorSample(
        kind: WatchSensorKind.heartRate,
        value: 100,
        recordedAt: _t0.add(const Duration(minutes: 1)),
      );
      await rig.engine.appendSensorSample(
        kind: WatchSensorKind.heartRate,
        value: 140,
        recordedAt: _t0.add(const Duration(minutes: 5)),
      );
      await rig.engine.appendObservation(
        _setEntry(
          'e1',
          slot: 'slotA',
          exercise: 'exA',
          at: _t0.add(const Duration(minutes: 2)),
        ),
      );
      await rig.engine.appendObservation(
        _setEntry(
          'e2',
          slot: 'slotA',
          exercise: 'exA',
          at: _t0.add(const Duration(minutes: 6)),
        ),
      );
      rig.clock.advance(const Duration(minutes: 30));

      // A pair above its own maximum would make the end unsendable: the
      // engine throws before anything is stored or emitted.
      await rig.engine.finishSession();

      final end = rig.sessionEnd(rig.engine.session!.sessionId)!;
      expect(end['avgHeartRateBpm'], 120);
      expect(end['maxHeartRateBpm'], 140);
      expect(end['setBlockHeartRates'], hasLength(1));
    });

    test('a hand-built pair above its maximum is refused', () {
      final end = {
        'entryId': 'end-s',
        'eventId': 'end-s',
        'kind': WatchObservationKind.sessionEnd,
        'loggedAt': '2026-01-05T10:30:00Z',
        'startedAt': '2026-01-05T10:00:00Z',
        'endedAt': '2026-01-05T10:30:00Z',
        'status': WatchSessionStatus.completed,
        'avgHeartRateBpm': 200,
        'maxHeartRateBpm': 100,
      };
      final envelope = {
        'protocolVersion': SyncProtocolValidator.protocolVersion,
        'messageId': 'msg-bad-pair',
        'sessionId': 's',
        'type': 'observations_up',
        'origin': 'watch',
        'sentAt': '2026-01-05T10:30:00Z',
        'payload': <String, Object?>{
          'events': [end],
        },
      };

      final rejections = _validator().validateEnvelope(envelope);
      expect(rejections, isNotEmpty);
    });
  });

  group('S-31009 what the pair cannot be confused with', () {
    // Plan 310, mutation pass: a mean computed from equal readings drifts past
    // its own maximum (or below its minimum) by float noise, so the pair
    // clamps. Derived with a throwaway script: seven readings of 61.1 average
    // above 61.1, three readings of 62.3 average below 62.3.
    test('equal readings average to exactly their value', () {
      final window = (_t0, _t0.add(const Duration(minutes: 30)));
      final high = WatchSensorSummaries.heartRate(
        [for (var i = 0; i < 7; i++) hr(61.1, 1, i)],
        window.$1,
        window.$2,
      )!;
      expect(high.averageBpm, 61.1);
      expect(high.maximumBpm, 61.1);

      final low = WatchSensorSummaries.heartRate(
        [for (var i = 0; i < 3; i++) hr(62.3, 1, i)],
        window.$1,
        window.$2,
      )!;
      expect(low.averageBpm, 62.3);
      expect(low.maximumBpm, 62.3);
    });

    test('an earlier session\'s sets and a skewed reading never reach the '
        'next session\'s end', () async {
      final rig = _Rig(validate: false);
      await rig.start();
      // The first session logs a set, and holds a reading stamped inside the
      // second session's window (a skewed clock).
      await rig.engine.appendObservation(
        _setEntry(
          'f1',
          slot: 'slotA',
          exercise: 'exA',
          at: _t0.add(const Duration(minutes: 3)),
        ),
      );
      await rig.engine.appendSensorSample(
        kind: WatchSensorKind.heartRate,
        value: 200,
        recordedAt: _t0.add(const Duration(minutes: 45)),
      );
      rig.clock.advance(const Duration(minutes: 10));
      await rig.engine.finishSession();

      rig.clock.advance(const Duration(minutes: 30)); // the second starts 10:40
      final second = await rig.start();
      await rig.engine.appendSensorSample(
        kind: WatchSensorKind.heartRate,
        value: 100,
        recordedAt: _t0.add(const Duration(minutes: 41)),
      );
      await rig.engine.appendObservation(
        _setEntry(
          'g1',
          slot: 'slotB',
          exercise: 'exB',
          at: _t0.add(const Duration(minutes: 45)),
        ),
      );
      rig.clock.advance(const Duration(minutes: 10)); // it ends 10:50
      await rig.engine.finishSession();

      Map<String, Object?>? endOf(String sessionId) {
        final id = WatchSessionCapture.sessionEndId(sessionId);
        for (final frame in rig.engine.pendingObservations()) {
          for (final event in (frame['payload']! as Map)['events'] as List) {
            final map = (event as Map).cast<String, Object?>();
            if (map['entryId'] == id) return map;
          }
        }
        return null;
      }

      final end = endOf(second.sessionId)!;
      expect(end['avgHeartRateBpm'], 100);
      expect(end['maxHeartRateBpm'], 100);
      final blocks = end['setBlockHeartRates']! as List;
      expect(blocks, hasLength(1));
      expect((blocks.single as Map)['sessionExerciseId'], 'slotB');
      expect((blocks.single as Map)['startedAt'], '2026-01-05T10:40:00.000Z');
      expect((blocks.single as Map)['endedAt'], '2026-01-05T10:45:00.000Z');
    });
  });
}
