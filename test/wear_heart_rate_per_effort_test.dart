// The Wear wrist stamps each timed, round and hold effort it logs with the
// heart rate it measured over that effort's own window, and a round with the
// time its countdown spent paused (plan 311).
//
// Plan: `docs/plans/2026-11-22-311-wear-heart-rate-per-effort-plan/2026-11-22-311-wear-heart-rate-per-effort-plan.md`
//   S-31101 a pause interval is half-open: the resume instant counts again
//   S-31102 a timer's pauses, read from its rows
//   S-31103 a round's pausedMs: accumulated, open, capped, post-window
//   S-31104 the engine's timerRows: one timer kind of one session, in order
//   S-31105 a timed effort carries its window's heart rate; a set carries none
//   S-31106 a hold carries its window's heart rate too
//   S-31107 a round leaves its paused stretches out and carries pausedMs
//   S-31108 the emission validator accepts every logged entry
//
// Mock-first. Plain `test()` for the state layer; no real clock thresholds:
// the fixture clock is advanced by hand.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/watch/logging/watch_logging_state.dart';
import 'package:omnitrain/watch/logging/watch_metric_stepping.dart';
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

Map<String, Object?> _slot(String id, List<String> capabilities) => {
  'sessionExerciseId': id,
  'exerciseId': 'ex-$id',
  'name': id,
  'capabilities': capabilities,
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

  Future<WatchSessionRecord> start({String modality = 'resistance_lifting'}) =>
      engine.createSession(modality: modality);

  Future<WatchLoggingState> surface(
    String modality,
    List<Map<String, Object?>> slots,
  ) async {
    await engine.createSession(modality: modality, exercises: slots);
    return WatchLoggingState(engine: engine, clock: clock.call);
  }
}

/// One stored timer row, built by hand for the `pauses` scenarios.
WatchTimerRecord _row({
  required String id,
  required DateTime startedAt,
  required DateTime recordedAt,
  String kind = WatchTimerKind.round,
  DateTime? pausedAt,
  DateTime? stoppedAt,
  int sequence = 0,
  int accumulatedPauseMs = 0,
}) => WatchTimerRecord(
  recordId: id,
  sessionId: 's',
  recordedAt: recordedAt,
  kind: kind,
  startedAt: startedAt,
  pausedAt: pausedAt,
  stoppedAt: stoppedAt,
  accumulatedPauseMs: accumulatedPauseMs,
  sequence: sequence,
);

/// The readings the round scenarios stamp over a 1:00 countdown: one at 0:10,
/// one and 0:20 and 0:30 inside a 0:15 -> 0:35 pause, one at 0:40.
List<WatchSensorSampleRecord> _roundReadings() => [
  hr(100, 0, 10),
  hr(110, 0, 20),
  hr(140, 0, 30),
  hr(160, 0, 40),
];

void main() {
  group('S-31101 the pause interval is half-open', () {
    final start = _t0;
    final end = _t0.add(const Duration(minutes: 1));
    final readings = [
      hr(100, 0, 10),
      hr(110, 0, 15),
      hr(140, 0, 30),
      hr(150, 0, 35),
      hr(160, 0, 40),
    ];
    final pause = WatchPauseInterval(
      start: _t0.add(const Duration(seconds: 15)),
      end: _t0.add(const Duration(seconds: 35)),
    );

    test(
      'readings inside the pause are left out, the resume instant is kept',
      () {
        final pair = WatchSensorSummaries.heartRate(
          readings,
          start,
          end,
          excluding: [pause],
        );

        expect(pair, isNotNull);
        expect(pair!.averageBpm, closeTo(136.6667, 1e-3));
        expect(pair.maximumBpm, 160);
      },
    );

    test('without the exclusion every reading counts', () {
      final pair = WatchSensorSummaries.heartRate(readings, start, end);

      expect(pair, isNotNull);
      expect(pair!.averageBpm, 132);
      expect(pair.maximumBpm, 160);
    });
  });

  group('S-31102 the pauses of one timer, read from its rows', () {
    final startedAt = _t0;
    final windowEnd = _t0.add(const Duration(minutes: 1));

    test('a pause ends where the timer next ran again', () {
      final rows = [
        _row(
          id: 'r1',
          startedAt: startedAt,
          recordedAt: _t0.add(const Duration(seconds: 15)),
          pausedAt: _t0.add(const Duration(seconds: 15)),
          sequence: 1,
        ),
        _row(
          id: 'r2',
          startedAt: startedAt,
          recordedAt: _t0.add(const Duration(seconds: 35)),
          sequence: 2,
        ),
      ];

      final pauses = WatchSensorSummaries.pauses(rows, startedAt, windowEnd);

      expect(pauses, hasLength(1));
      expect(pauses.single.start, _t0.add(const Duration(seconds: 15)));
      expect(pauses.single.end, _t0.add(const Duration(seconds: 35)));
    });

    test('a pause that never resumed ends where the row stopped', () {
      final rows = [
        _row(
          id: 'r1',
          startedAt: startedAt,
          recordedAt: _t0.add(const Duration(seconds: 15)),
          pausedAt: _t0.add(const Duration(seconds: 15)),
          stoppedAt: _t0.add(const Duration(seconds: 50)),
          sequence: 1,
        ),
      ];

      final pauses = WatchSensorSummaries.pauses(rows, startedAt, windowEnd);

      expect(pauses.single.end, _t0.add(const Duration(seconds: 50)));
    });

    test('a pause with nothing after it ends at the window\'s end', () {
      final rows = [
        _row(
          id: 'r1',
          startedAt: startedAt,
          recordedAt: _t0.add(const Duration(seconds: 15)),
          pausedAt: _t0.add(const Duration(seconds: 15)),
          sequence: 1,
        ),
      ];

      final pauses = WatchSensorSummaries.pauses(rows, startedAt, windowEnd);

      expect(pauses.single.end, windowEnd);
    });

    test('a row of another timer never contributes', () {
      final other = _row(
        id: 'other',
        startedAt: _t0.add(const Duration(seconds: 5)),
        recordedAt: _t0.add(const Duration(seconds: 15)),
        pausedAt: _t0.add(const Duration(seconds: 15)),
        sequence: 1,
      );
      final rows = [
        other,
        _row(
          id: 'r1',
          startedAt: startedAt,
          recordedAt: _t0.add(const Duration(seconds: 20)),
          pausedAt: _t0.add(const Duration(seconds: 20)),
          sequence: 2,
        ),
        _row(
          id: 'r2',
          startedAt: startedAt,
          recordedAt: _t0.add(const Duration(seconds: 40)),
          sequence: 3,
        ),
      ];

      final pauses = WatchSensorSummaries.pauses(rows, startedAt, windowEnd);

      expect(pauses, hasLength(1));
      expect(pauses.single.start, _t0.add(const Duration(seconds: 20)));
      expect(pauses.single.end, _t0.add(const Duration(seconds: 40)));
    });
  });

  group('S-31103 a round\'s pausedMs', () {
    final windowStart = _t0;
    final windowEnd = _t0.add(const Duration(minutes: 1));

    WatchTimerRecord countdown({
      DateTime? pausedAt,
      DateTime? stoppedAt,
      int accumulatedPauseMs = 0,
    }) => _row(
      id: 'c',
      startedAt: windowStart,
      recordedAt: pausedAt ?? stoppedAt ?? windowEnd,
      pausedAt: pausedAt,
      stoppedAt: stoppedAt,
      accumulatedPauseMs: accumulatedPauseMs,
    );

    test('an accumulated pause alone is what it accumulated', () {
      expect(
        WatchSensorSummaries.pausedMs(
          countdown(accumulatedPauseMs: 20000),
          windowStart,
          windowEnd,
        ),
        20000,
      );
    });

    test('an open pause is counted up to the window\'s end', () {
      expect(
        WatchSensorSummaries.pausedMs(
          countdown(
            pausedAt: _t0.add(const Duration(seconds: 50)),
            accumulatedPauseMs: 20000,
          ),
          windowStart,
          windowEnd,
        ),
        30000,
      );
    });

    test('the pause is never longer than the window', () {
      expect(
        WatchSensorSummaries.pausedMs(
          countdown(accumulatedPauseMs: 90000),
          windowStart,
          windowEnd,
        ),
        60000,
      );
    });

    test('a pause that opened after the window adds nothing', () {
      expect(
        WatchSensorSummaries.pausedMs(
          countdown(
            pausedAt: _t0.add(const Duration(seconds: 70)),
            accumulatedPauseMs: 20000,
          ),
          windowStart,
          windowEnd,
        ),
        20000,
      );
    });
  });

  group('S-31104 the engine\'s timerRows', () {
    test('one timer kind of the current session, in append order', () async {
      final rig = _Rig(validate: false);
      await rig.start();

      await rig.engine.startTimer(WatchTimerKind.rest);
      rig.clock.advance(const Duration(seconds: 10));
      await rig.engine.stopTimer(kind: WatchTimerKind.rest);
      rig.clock.advance(const Duration(seconds: 10));
      await rig.engine.startTimer(
        WatchTimerKind.round,
        plannedDurationMs: 60000,
      );
      rig.clock.advance(const Duration(seconds: 10));
      await rig.engine.pauseTimer(kind: WatchTimerKind.round);
      rig.clock.advance(const Duration(seconds: 10));
      await rig.engine.resumeTimer(kind: WatchTimerKind.round);

      final round = rig.engine.timerRows(WatchTimerKind.round);
      expect(round, hasLength(3));
      expect(
        [for (final row in round) row.state],
        [
          WatchTimerState.running,
          WatchTimerState.paused,
          WatchTimerState.running,
        ],
        reason: 'the rows are the append order: start, pause, resume',
      );
      expect(
        [for (final row in round) row.startedAt],
        everyElement(round.first.startedAt),
        reason: 'every row of the timer shares its start',
      );
      expect(rig.engine.timerRows(WatchTimerKind.rest), hasLength(2));
      expect(rig.engine.timerRows(WatchTimerKind.hold), isEmpty);
    });

    test('a second session never sees the first\'s rows', () async {
      final rig = _Rig(validate: false);
      await rig.start();
      await rig.engine.startTimer(WatchTimerKind.round);
      rig.clock.advance(const Duration(seconds: 10));

      await rig.engine.finishSession();
      rig.clock.advance(const Duration(seconds: 10));
      await rig.start();

      expect(rig.engine.timerRows(WatchTimerKind.round), isEmpty);

      await rig.engine.startTimer(WatchTimerKind.round);
      final rows = rig.engine.timerRows(WatchTimerKind.round);
      expect(rows, hasLength(1));
      expect(rows.single.sessionId, rig.engine.session!.sessionId);
    });
  });

  group('S-31105 a timed effort carries its window\'s heart rate', () {
    test('readings inside the window land on the entry', () async {
      final rig = _Rig();
      final surface = await rig.surface('cardio_endurance', [
        _slot('sx-run', ['time', 'distance']),
      ]);
      await rig.engine.appendSensorSample(
        kind: WatchSensorKind.heartRate,
        value: 100,
        recordedAt: _t0.add(const Duration(minutes: 6)),
      );
      await rig.engine.appendSensorSample(
        kind: WatchSensorKind.heartRate,
        value: 140,
        recordedAt: _t0.add(const Duration(minutes: 7)),
      );
      await rig.engine.appendSensorSample(
        kind: WatchSensorKind.heartRate,
        value: 200,
        recordedAt: _t0.add(const Duration(minutes: 15)),
      );

      rig.clock.advance(const Duration(minutes: 10));
      surface.adjust(WatchMetricKey.duration, 60); // a 5-minute window
      final stored = await surface.log();

      expect(stored.kind, WatchObservationKind.timed);
      expect(stored.payload['startedAt'], '2026-01-05T10:05:00.000Z');
      expect(stored.payload['endedAt'], '2026-01-05T10:10:00.000Z');
      expect(stored.payload['avgHeartRateBpm'], 120);
      expect(stored.payload['maxHeartRateBpm'], 140);
    });

    test('a window nothing was measured over adds nothing', () async {
      final rig = _Rig();
      final surface = await rig.surface('cardio_endurance', [
        _slot('sx-run', ['time', 'distance']),
      ]);

      rig.clock.advance(const Duration(minutes: 10));
      surface.adjust(WatchMetricKey.duration, 60);
      final stored = await surface.log();

      expect(stored.payload.containsKey('avgHeartRateBpm'), isFalse);
      expect(stored.payload.containsKey('maxHeartRateBpm'), isFalse);
    });

    test('a set has no window of its own and carries nothing', () async {
      final rig = _Rig();
      final surface = await rig.surface('resistance_lifting', [
        _slot('sx-bench', ['reps', 'sets', 'load']),
      ]);
      await rig.engine.appendSensorSample(
        kind: WatchSensorKind.heartRate,
        value: 120,
        recordedAt: _t0.add(const Duration(minutes: 1)),
      );

      rig.clock.advance(const Duration(minutes: 2));
      final stored = await surface.log();

      expect(stored.kind, WatchObservationKind.set);
      expect(stored.payload.containsKey('avgHeartRateBpm'), isFalse);
      expect(stored.payload.containsKey('maxHeartRateBpm'), isFalse);
    });
  });

  group('S-31106 a hold carries its window\'s heart rate too', () {
    test('the pair sits beside the extra load the hold carried', () async {
      final rig = _Rig();
      final surface = await rig.surface('isometric_stretching', [
        _slot('sx-plank', ['hold', 'time']),
      ]);
      await rig.engine.appendSensorSample(
        kind: WatchSensorKind.heartRate,
        value: 100,
        recordedAt: _t0.add(const Duration(minutes: 9)),
      );
      await rig.engine.appendSensorSample(
        kind: WatchSensorKind.heartRate,
        value: 140,
        recordedAt: _t0.add(const Duration(minutes: 9, seconds: 30)),
      );

      rig.clock.advance(const Duration(minutes: 10));
      surface.adjust(WatchMetricKey.duration, 12); // a 1-minute hold
      surface.adjust(WatchMetricKey.extraWeight, -4);
      final stored = await surface.log();

      expect(stored.kind, WatchObservationKind.hold);
      expect(stored.payload['avgHeartRateBpm'], 120);
      expect(stored.payload['maxHeartRateBpm'], 140);
      expect(stored.payload['extraLoadKg'], -10);
    });
  });

  group('S-31107 a round leaves its paused stretches out', () {
    test(
      'a paused round keeps only the readings outside the pause and sends pausedMs',
      () async {
        final rig = _Rig();
        final surface = await rig.surface('sports', [
          _slot('sx-period', ['time', 'rounds']),
        ]);
        await rig.engine.startTimer(
          WatchTimerKind.round,
          plannedDurationMs: 60000,
        );
        for (final reading in _roundReadings()) {
          await rig.engine.appendSensorSample(
            kind: WatchSensorKind.heartRate,
            value: reading.value,
            recordedAt: reading.recordedAt,
          );
        }

        rig.clock.advance(const Duration(seconds: 15));
        await rig.engine.pauseTimer(kind: WatchTimerKind.round);
        rig.clock.advance(const Duration(seconds: 20));
        await rig.engine.resumeTimer(kind: WatchTimerKind.round);
        rig.clock.advance(const Duration(seconds: 25)); // the 1:00 mark

        final stored = await surface.log();

        expect(stored.kind, WatchObservationKind.round);
        expect(stored.payload['startedAt'], '2026-01-05T10:00:00.000Z');
        expect(stored.payload['endedAt'], '2026-01-05T10:01:00.000Z');
        expect(stored.payload['avgHeartRateBpm'], 130);
        expect(stored.payload['maxHeartRateBpm'], 160);
        expect(stored.payload['pausedMs'], 20000);
      },
    );

    test(
      'a never-paused round counts every reading and sends no pausedMs',
      () async {
        final rig = _Rig();
        final surface = await rig.surface('sports', [
          _slot('sx-period', ['time', 'rounds']),
        ]);
        await rig.engine.startTimer(
          WatchTimerKind.round,
          plannedDurationMs: 60000,
        );
        for (final reading in _roundReadings()) {
          await rig.engine.appendSensorSample(
            kind: WatchSensorKind.heartRate,
            value: reading.value,
            recordedAt: reading.recordedAt,
          );
        }

        rig.clock.advance(const Duration(minutes: 1)); // the 1:00 mark
        final stored = await surface.log();

        expect(stored.payload['avgHeartRateBpm'], 127.5);
        expect(stored.payload['maxHeartRateBpm'], 160);
        expect(stored.payload.containsKey('pausedMs'), isFalse);
      },
    );

    test(
      'a round paused for the whole window sends no pair and a full pause',
      () async {
        final rig = _Rig();
        final surface = await rig.surface('sports', [
          _slot('sx-period', ['time', 'rounds']),
        ]);
        await rig.engine.startTimer(
          WatchTimerKind.round,
          plannedDurationMs: 60000,
        );
        for (final reading in _roundReadings()) {
          await rig.engine.appendSensorSample(
            kind: WatchSensorKind.heartRate,
            value: reading.value,
            recordedAt: reading.recordedAt,
          );
        }

        await rig.engine.pauseTimer(kind: WatchTimerKind.round);
        rig.clock.advance(const Duration(minutes: 1)); // the 1:00 mark
        final stored = await surface.log();

        expect(stored.payload.containsKey('avgHeartRateBpm'), isFalse);
        expect(stored.payload.containsKey('maxHeartRateBpm'), isFalse);
        expect(stored.payload['pausedMs'], 60000);
      },
    );
  });

  group('S-31108 the emission validator accepts every logged entry', () {
    test('the entries of S-31105..S-31107 pass the shared schemas', () async {
      final validator = _validator();

      // S-31105: a timed effort with readings, and a bare set.
      final timedRig = _Rig();
      final timed = await timedRig.surface('cardio_endurance', [
        _slot('sx-run', ['time', 'distance']),
        _slot('sx-bench', ['reps', 'sets', 'load']),
      ]);
      await timedRig.engine.appendSensorSample(
        kind: WatchSensorKind.heartRate,
        value: 100,
        recordedAt: _t0.add(const Duration(minutes: 6)),
      );
      await timedRig.engine.appendSensorSample(
        kind: WatchSensorKind.heartRate,
        value: 140,
        recordedAt: _t0.add(const Duration(minutes: 7)),
      );
      timedRig.clock.advance(const Duration(minutes: 10));
      timed.adjust(WatchMetricKey.duration, 60);
      await timed.log();
      await timedRig.engine.advanceExercise();
      timedRig.clock.advance(const Duration(minutes: 1));
      await timed.log();

      // S-31106: a hold with readings.
      final holdRig = _Rig();
      final hold = await holdRig.surface('isometric_stretching', [
        _slot('sx-plank', ['hold', 'time']),
      ]);
      await holdRig.engine.appendSensorSample(
        kind: WatchSensorKind.heartRate,
        value: 120,
        recordedAt: _t0.add(const Duration(minutes: 9)),
      );
      holdRig.clock.advance(const Duration(minutes: 10));
      hold.adjust(WatchMetricKey.duration, 12);
      await hold.log();

      // S-31107: a paused round, a never-paused one, a fully paused one.
      final roundRig = _Rig();
      final rounds = await roundRig.surface('sports', [
        _slot('sx-period', ['time', 'rounds']),
      ]);
      await roundRig.engine.startTimer(
        WatchTimerKind.round,
        plannedDurationMs: 60000,
      );
      for (final reading in _roundReadings()) {
        await roundRig.engine.appendSensorSample(
          kind: WatchSensorKind.heartRate,
          value: reading.value,
          recordedAt: reading.recordedAt,
        );
      }
      roundRig.clock.advance(const Duration(seconds: 15));
      await roundRig.engine.pauseTimer(kind: WatchTimerKind.round);
      roundRig.clock.advance(const Duration(seconds: 20));
      await roundRig.engine.resumeTimer(kind: WatchTimerKind.round);
      roundRig.clock.advance(const Duration(seconds: 25));
      await rounds.log();
      roundRig.clock.advance(const Duration(minutes: 1));
      await roundRig.engine.startTimer(
        WatchTimerKind.round,
        plannedDurationMs: 60000,
      );
      roundRig.clock.advance(const Duration(minutes: 1));
      await rounds.log();
      roundRig.clock.advance(const Duration(minutes: 1));
      await roundRig.engine.startTimer(
        WatchTimerKind.round,
        plannedDurationMs: 60000,
      );
      await roundRig.engine.pauseTimer(kind: WatchTimerKind.round);
      roundRig.clock.advance(const Duration(minutes: 1));
      await rounds.log();

      for (final rig in [timedRig, holdRig, roundRig]) {
        for (final frame in rig.emitted) {
          if (frame['type'] != 'observations_up') continue;
          final rejections = validator.validateEnvelope(frame);
          expect(
            rejections,
            isEmpty,
            reason: 'a wrist frame the schemas refused: ${frame['messageId']}',
          );
        }
      }
    });

    test('a round whose pausedMs exceeds its window is refused', () {
      final round = {
        'entryId': 'r-over',
        'eventId': 'r-over',
        'kind': WatchObservationKind.round,
        'loggedAt': '2026-01-05T10:01:00Z',
        'startedAt': '2026-01-05T10:00:00Z',
        'endedAt': '2026-01-05T10:01:00Z',
        'sessionExerciseId': 'sx-a',
        'exerciseId': 'ex-sx-a',
        'roundNumber': 1,
        'pausedMs': 70000,
      };
      final envelope = {
        'protocolVersion': SyncProtocolValidator.protocolVersion,
        'messageId': 'msg-bad-pause',
        'sessionId': 's',
        'type': 'observations_up',
        'origin': 'watch',
        'sentAt': '2026-01-05T10:01:00Z',
        'payload': <String, Object?>{
          'events': [round],
        },
      };

      final rejections = _validator().validateEnvelope(envelope);
      expect(rejections, isNotEmpty);

      // The same shape within the bound is accepted, so the refusal above is
      // the length's and not the event's.
      final within = {
        ...envelope,
        'messageId': 'msg-ok-pause',
        'payload': <String, Object?>{
          'events': [
            {...round, 'entryId': 'r-ok', 'eventId': 'r-ok', 'pausedMs': 20000},
          ],
        },
      };
      expect(_validator().validateEnvelope(within), isEmpty);
    });
  });

  group('S-31109 the corners the mutation pass found', () {
    // Plan 311, lead mutation pass: M05 (rows not sorted), M08 (a stop beats a
    // resume), M12 (an open pause ends at the stop, not at the window's end),
    // M14 (a negative accumulated pause is not a pause). M22 (the kind guard
    // for a set) is equivalent: a set carries no window keys, so the
    // `startedAt` check ends it first.
    final windowEnd = _t0.add(const Duration(minutes: 1));

    test('rows handed over out of order read the same pauses', () {
      final paused = _row(
        id: 'r1',
        startedAt: _t0,
        recordedAt: _t0.add(const Duration(seconds: 15)),
        pausedAt: _t0.add(const Duration(seconds: 15)),
        sequence: 1,
      );
      final resumed = _row(
        id: 'r2',
        startedAt: _t0,
        recordedAt: _t0.add(const Duration(seconds: 35)),
        sequence: 2,
      );

      final pauses = WatchSensorSummaries.pauses(
        [resumed, paused],
        _t0,
        windowEnd,
      );

      expect(pauses, hasLength(1));
      expect(pauses.single.end, _t0.add(const Duration(seconds: 35)));
    });

    test('a later resume wins over the paused row\'s own stop', () {
      final pauses = WatchSensorSummaries.pauses(
        [
          _row(
            id: 'r1',
            startedAt: _t0,
            recordedAt: _t0.add(const Duration(seconds: 15)),
            pausedAt: _t0.add(const Duration(seconds: 15)),
            stoppedAt: _t0.add(const Duration(seconds: 50)),
            sequence: 1,
          ),
          _row(
            id: 'r2',
            startedAt: _t0,
            recordedAt: _t0.add(const Duration(seconds: 35)),
            sequence: 2,
          ),
        ],
        _t0,
        windowEnd,
      );

      expect(pauses.single.end, _t0.add(const Duration(seconds: 35)));
    });

    test(
      'an open pause is counted up to the stop, not to the window\'s end',
      () {
        final countdown = _row(
          id: 'c',
          startedAt: _t0,
          recordedAt: _t0.add(const Duration(seconds: 55)),
          pausedAt: _t0.add(const Duration(seconds: 50)),
          stoppedAt: _t0.add(const Duration(seconds: 55)),
          accumulatedPauseMs: 20000,
          sequence: 1,
        );

        expect(WatchSensorSummaries.pausedMs(countdown, _t0, windowEnd), 25000);
      },
    );

    test('a negative accumulated pause counts as none', () {
      final countdown = _row(
        id: 'c',
        startedAt: _t0,
        recordedAt: _t0.add(const Duration(seconds: 30)),
        accumulatedPauseMs: -5000,
        sequence: 1,
      );

      expect(WatchSensorSummaries.pausedMs(countdown, _t0, windowEnd), 0);
    });
  });
}
