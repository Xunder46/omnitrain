// The Wear wrist's end-of-workout summary, as state (plan 292, D-29201..D-29203).
//
// Scenario mapping:
//   S-29201  the duration text
//   S-29202  the rows and their labels
//   S-29203  a workout the wrist ended, with efforts and other entries
//   S-29204  the average heart rate: the window and the rounding
//   S-29205  the gates: never seen active, no effort, abandoned, noted again
//   S-29206  a workout the phone ended owes nothing
//   S-29207  a new workout replaces a pending summary
//   S-29208  Done takes it away for good
//   S-29209  the engine's endedByPhone helper
//
// Plain `test()` throughout: the state layer, the in-memory store, a clock the
// test moves.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/watch/logging/watch_workout_summary.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';

class _Clock {
  DateTime now = DateTime.utc(2026, 11, 22, 9);

  DateTime call() => now;

  void advance(Duration delta) => now = now.add(delta);
}

List<Map<String, Object?>> _slots() => [
  {
    'sessionExerciseId': 'sx-a',
    'exerciseId': 'ex-a',
    'name': 'Squat',
    'capabilities': ['reps', 'sets', 'load'],
  },
];

Map<String, Object?> _set(String id, _Clock clock) => {
  'entryId': id,
  'eventId': id,
  'kind': WatchObservationKind.set,
  'loggedAt': utcIso(clock.now),
  'sessionExerciseId': 'sx-a',
  'exerciseId': 'ex-a',
  'reps': 5,
  'loadKg': 80,
};

Map<String, Object?> _timed(String id, _Clock clock) => {
  'entryId': id,
  'eventId': id,
  'kind': WatchObservationKind.timed,
  'loggedAt': utcIso(clock.now),
  'sessionExerciseId': 'sx-a',
  'exerciseId': 'ex-a',
  'startedAt': utcIso(clock.now.subtract(const Duration(minutes: 5))),
  'endedAt': utcIso(clock.now),
};

Map<String, Object?> _rest(String id, String after, _Clock clock) => {
  'entryId': id,
  'eventId': id,
  'kind': WatchObservationKind.rest,
  'loggedAt': utcIso(clock.now),
  'sessionExerciseId': 'sx-a',
  'exerciseId': 'ex-a',
  'startedAt': utcIso(clock.now),
  'endedAt': utcIso(clock.now),
  'afterEntryId': after,
};

Map<String, Object?> _lifecycle(String sessionId, String state) => {
  'protocolVersion': 1,
  'messageId': 'msg-$state-$sessionId',
  'sessionId': sessionId,
  'type': 'session_lifecycle',
  'origin': 'phone',
  'sentAt': '2026-11-22T10:00:00Z',
  'payload': {'state': state, 'at': '2026-11-22T10:00:00Z'},
};

class _Rig {
  _Rig() {
    engine = WatchSessionEngine(store, clock: clock.call);
    summary = WatchWorkoutSummaryState(engine: engine);
  }

  final InMemoryWatchSessionStore store = InMemoryWatchSessionStore();
  final _Clock clock = _Clock();
  late final WatchSessionEngine engine;
  late final WatchWorkoutSummaryState summary;

  /// Starts a workout and lets the summary state see it active, the way the
  /// shell's builds do.
  Future<void> start() async {
    await engine.createSession(
      modality: 'resistance_lifting',
      exercises: _slots(),
    );
    summary.note(engine.session);
  }
}

void main() {
  test('S-29201 the duration text', () {
    expect(WatchWorkoutSummary.durationText(0), '0:00');
    expect(WatchWorkoutSummary.durationText(59), '0:59');
    expect(WatchWorkoutSummary.durationText(754), '12:34');
    expect(WatchWorkoutSummary.durationText(3599), '59:59');
    expect(WatchWorkoutSummary.durationText(3600), '1:00:00');
    expect(WatchWorkoutSummary.durationText(3725), '1:02:05');
    expect(WatchWorkoutSummary.durationText(-5), '0:00');
  });

  test('S-29202 the rows and their labels', () {
    final start = DateTime.utc(2026, 11, 22, 9);
    final end = start.add(const Duration(seconds: 754));
    WatchWorkoutSummary build({
      required bool allSets,
      int? bpm,
      int efforts = 3,
    }) => WatchWorkoutSummary(
      sessionId: 's',
      startedAt: start,
      endedAt: end,
      effortCount: efforts,
      allSets: allSets,
      averageBpm: bpm,
    );

    expect(
      [
        for (final row in build(allSets: true, bpm: 130).rows)
          '${row.label} ${row.value}',
      ],
      ['Time 12:34', 'Sets 3', 'Avg HR 130 bpm'],
    );
    expect(build(allSets: false, efforts: 2).rows[1].label, 'Efforts');
    expect(build(allSets: false, efforts: 2).rows[1].value, '2');
    expect(build(allSets: true).rows, hasLength(2), reason: 'no heart rate');
  });

  test(
    'S-29203 a workout the wrist ended, with efforts and other entries',
    () async {
      final rig = _Rig();
      await rig.start();
      final startedAt = rig.engine.session!.startedAt;
      await rig.engine.appendObservation(_set('e1', rig.clock));
      await rig.engine.appendObservation(_rest('r1', 'e1', rig.clock));
      await rig.engine.appendObservation(_set('e2', rig.clock));
      await rig.engine.logNutrition(foodId: 'f-oats', servings: 1);
      rig.clock.advance(const Duration(minutes: 12));

      await rig.engine.finishSession();
      rig.summary.note(rig.engine.session);

      final pending = rig.summary.pending;
      expect(pending, isNotNull);
      expect(
        pending!.effortCount,
        2,
        reason: 'a rest and a food are not efforts',
      );
      expect(pending.allSets, isTrue);
      expect(pending.sessionId, rig.engine.session!.sessionId);
      expect(pending.startedAt, startedAt);
      expect(pending.endedAt, rig.engine.session!.recordedAt);
      expect(pending.averageBpm, isNull);
    },
  );

  test('S-29204 the average heart rate: the window and the rounding', () async {
    final rig = _Rig();
    await rig.start();
    final start = rig.engine.session!.startedAt;
    await rig.engine.appendSensorSample(
      kind: WatchSensorKind.heartRate,
      value: 200,
      recordedAt: start.subtract(const Duration(seconds: 30)),
    );
    for (final (offset, bpm) in [(10, 120.0), (20, 130.0), (30, 140.0)]) {
      await rig.engine.appendSensorSample(
        kind: WatchSensorKind.heartRate,
        value: bpm,
        recordedAt: start.add(Duration(seconds: offset)),
      );
    }
    // Another kind of reading inside the window is not a heart rate.
    await rig.engine.appendSensorSample(
      kind: WatchSensorKind.gps,
      value: 5000,
      recordedAt: start.add(const Duration(seconds: 15)),
    );
    await rig.engine.appendObservation(_set('e1', rig.clock));
    rig.clock.advance(const Duration(minutes: 1));
    await rig.engine.finishSession();
    // A reading stamped after the end is outside the window too.
    await rig.engine.appendSensorSample(
      kind: WatchSensorKind.heartRate,
      value: 250,
      recordedAt: rig.engine.session!.recordedAt.add(
        const Duration(minutes: 1),
      ),
    );
    rig.summary.note(rig.engine.session);
    expect(
      rig.summary.pending!.averageBpm,
      130,
      reason: 'the early 200, the late 250 and the gps reading are out',
    );

    final rounded = _Rig();
    await rounded.start();
    await rounded.engine.appendSensorSample(
      kind: WatchSensorKind.heartRate,
      value: 129.5,
      recordedAt: rounded.engine.session!.startedAt.add(
        const Duration(seconds: 5),
      ),
    );
    await rounded.engine.appendObservation(_set('e1', rounded.clock));
    rounded.clock.advance(const Duration(minutes: 1));
    await rounded.engine.finishSession();
    rounded.summary.note(rounded.engine.session);
    expect(rounded.summary.pending!.averageBpm, 130, reason: '129.5 rounds up');

    final none = _Rig();
    await none.start();
    await none.engine.appendObservation(_set('e1', none.clock));
    await none.engine.finishSession();
    none.summary.note(none.engine.session);
    expect(none.summary.pending!.averageBpm, isNull);
  });

  test(
    'S-29205 the gates: never seen active, no effort, abandoned, noted again',
    () async {
      // (a) completed, but this process never saw it active: a relaunch.
      final unseen = _Rig();
      await unseen.engine.createSession(
        modality: 'resistance_lifting',
        exercises: _slots(),
      );
      await unseen.engine.appendObservation(_set('e1', unseen.clock));
      await unseen.engine.finishSession();
      unseen.summary.note(unseen.engine.session);
      expect(unseen.summary.pending, isNull, reason: 'never seen active');

      // (b) completed with no effort entry.
      final empty = _Rig();
      await empty.start();
      await empty.engine.finishSession();
      empty.summary.note(empty.engine.session);
      expect(empty.summary.pending, isNull, reason: 'no effort');

      // (c) abandoned.
      final abandoned = _Rig();
      await abandoned.start();
      await abandoned.engine.appendObservation(_set('e1', abandoned.clock));
      await abandoned.engine.abandonSession();
      abandoned.summary.note(abandoned.engine.session);
      expect(abandoned.summary.pending, isNull, reason: 'abandoned');

      // (d) noted again after Done: it does not come back.
      final again = _Rig();
      await again.start();
      await again.engine.appendObservation(_set('e1', again.clock));
      await again.engine.finishSession();
      again.summary.note(again.engine.session);
      expect(again.summary.pending, isNotNull, reason: 'the premise');
      again.summary.dismissPending();
      again.summary.note(again.engine.session);
      expect(again.summary.pending, isNull);

      // A mix of efforts reads `Efforts`.
      final mix = _Rig();
      await mix.start();
      await mix.engine.appendObservation(_set('e1', mix.clock));
      await mix.engine.appendObservation(_timed('e2', mix.clock));
      await mix.engine.finishSession();
      mix.summary.note(mix.engine.session);
      expect(mix.summary.pending!.allSets, isFalse);
      expect(mix.summary.pending!.effortCount, 2);
    },
  );

  test('S-29206 a workout the phone ended owes nothing', () async {
    final rig = _Rig();
    await rig.start();
    await rig.engine.appendObservation(_set('e1', rig.clock));

    await rig.engine.applyMessage(
      _lifecycle(rig.engine.session!.sessionId, 'completed'),
    );
    rig.summary.note(rig.engine.session);

    expect(rig.engine.session!.status, WatchSessionStatus.completed);
    expect(rig.summary.pending, isNull);
  });

  test('S-29207 a new workout replaces a pending summary', () async {
    final rig = _Rig();
    await rig.start();
    await rig.engine.appendObservation(_set('e1', rig.clock));
    await rig.engine.finishSession();
    rig.summary.note(rig.engine.session);
    expect(rig.summary.pending, isNotNull, reason: 'the premise');

    await rig.engine.createSession(
      modality: 'resistance_lifting',
      exercises: _slots(),
    );
    rig.summary.note(rig.engine.session);

    expect(rig.summary.pending, isNull);
  });

  test('S-29208 Done takes it away for good', () async {
    final rig = _Rig();
    await rig.start();
    await rig.engine.appendObservation(_set('e1', rig.clock));
    await rig.engine.finishSession();
    rig.summary.note(rig.engine.session);
    expect(rig.summary.pending, isNotNull, reason: 'the premise');

    rig.summary.dismissPending();
    rig.summary.note(rig.engine.session);
    rig.summary.note(rig.engine.session);

    expect(rig.summary.pending, isNull);
  });

  test('S-29209 the engine\'s endedByPhone helper', () async {
    final wrist = _Rig();
    await wrist.start();
    await wrist.engine.finishSession();
    expect(wrist.engine.endedByPhone(wrist.engine.session!), isFalse);

    final phone = _Rig();
    await phone.start();
    await phone.engine.applyMessage(
      _lifecycle(phone.engine.session!.sessionId, 'completed'),
    );
    expect(phone.engine.endedByPhone(phone.engine.session!), isTrue);
  });
}
