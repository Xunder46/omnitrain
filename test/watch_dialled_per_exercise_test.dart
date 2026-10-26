// Watch logging surfaces — dialled numbers belong to the exercise slot.
//
// Plan: `docs/plans/2026-10-20-46a-wrist-logging-basics-plan/2026-10-20-46a-wrist-logging-basics-plan.md`,
// D-5 and S-6410..S-6413.
// Scenario mapping:
//   S-6410 a dialled value stays on the slot it was dialled on  → `S-6410 ...`
//   S-6411 logging a slot consumes only that slot's dials       → `S-6411 ...`
//   S-6412 a weight dialled on bench never appears on squat     → `S-6412 ...`
//   S-6413 a session with no exercise has nothing to dial        → `S-6413 ...`
//   S-6415 a log clears the exercise it logged, not the one in flight
//                                                              → `S-6415 ...`
//
// An edit is held in memory until it is confirmed, keyed by the exercise the
// user was on when they made it: an unconfirmed reps value belongs to the bench
// it was dialled on, not to the next exercise the session moves to. These cases
// walk the same Dart `WatchSessionEngine` the surface logs through, so the
// position they read is the engine's own.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/watch/logging/watch_logging_state.dart';
import 'package:omnitrain/watch/logging/watch_metric_stepping.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';
import 'package:omnitrain/watch/session/watch_session_store.dart';

/// Deterministic clock: nothing here waits, so every instant is a value.
class _Clock {
  _Clock(this.now);

  DateTime now;

  DateTime call() => now;

  void advance(Duration delta) => now = now.add(delta);
}

/// A store that wraps the in-memory one and can be armed so the next `append`
/// suspends until [resume] — one commit held in flight.
class _SuspendingStore implements WatchSessionStore {
  final InMemoryWatchSessionStore _inner = InMemoryWatchSessionStore();

  Completer<void>? _waiting;
  bool _armed = false;

  void arm() => _armed = true;

  bool get suspended => _waiting != null;

  void resume() {
    final waiting = _waiting;
    _waiting = null;
    if (waiting != null && !waiting.isCompleted) waiting.complete();
  }

  @override
  Future<T> append<T extends WatchRecord>(T record) async {
    if (_armed) {
      _armed = false;
      final waiting = Completer<void>();
      _waiting = waiting;
      await waiting.future;
    }
    return _inner.append(record);
  }

  @override
  Future<WatchStoreContents> readAll() => _inner.readAll();

  @override
  Future<List<String>> pruneConfirmed() => _inner.pruneConfirmed();

  @override
  Future<List<String>> pruneSensorSamples(Iterable<String> sessionIds) =>
      _inner.pruneSensorSamples(sessionIds);
}

/// Bounded poll: never an unbounded wait on the store.
Future<bool> _spin(bool Function() condition, {int limit = 200}) async {
  var spins = 0;
  while (!condition() && spins < limit) {
    await Future<void>.delayed(Duration.zero);
    spins += 1;
  }
  return condition();
}

Map<String, Object?> _slot(String id, List<String> capabilities) => {
  'sessionExerciseId': id,
  'exerciseId': 'ex-$id',
  'name': id,
  'capabilities': capabilities,
};

void main() {
  late _Clock clock;
  late WatchSessionEngine engine;
  late WatchLoggingState surface;

  setUp(() async {
    clock = _Clock(DateTime.utc(2026, 10, 20, 17));
    engine = WatchSessionEngine(InMemoryWatchSessionStore(), clock: clock.call);
    await engine.createSession(
      modality: 'resistance_lifting',
      exercises: [
        _slot('sx-bench', ['reps', 'sets', 'load']),
        _slot('sx-squat', ['reps', 'sets', 'load']),
      ],
    );
    surface = WatchLoggingState(engine: engine, clock: clock.call);
  });

  WatchMetricField field(String metricKey) =>
      surface.fields.singleWhere((row) => row.metricKey == metricKey);

  double value(String metricKey) => field(metricKey).value;

  /// The phone moving the session to [index], which is how the wrist learns a
  /// position the user picked on the phone (a snapshot carries it verbatim).
  Future<void> selectExercise(int index) async {
    final session = engine.session!;
    final applied = await engine.applyMessage({
      'protocolVersion': 1,
      'messageId': 'm-select-$index',
      'sessionId': session.sessionId,
      'type': 'session_snapshot',
      'origin': 'phone',
      'sentAt': utcIso(clock.now),
      'payload': {
        'sessionId': session.sessionId,
        'revision': session.revision + 1,
        'status': session.status,
        'currentExerciseIndex': index,
        'exercises': session.exercises,
        'entries': const <Object?>[],
        'timers': const <String, Object?>{},
      },
    });
    expect(applied, isTrue, reason: 'the snapshot names the session in hand');
  }

  group('S-6410 a dialled value stays on the slot it was dialled on', () {
    test('S-6410 bench reps do not follow the session to squat', () async {
      expect(value(WatchMetricKey.reps), 10, reason: 'the set default');

      surface.adjust(WatchMetricKey.reps, 4);
      expect(value(WatchMetricKey.reps), 14);

      await engine.advanceExercise();
      expect(surface.exerciseName, 'sx-squat');
      expect(
        value(WatchMetricKey.reps),
        10,
        reason: "squat's own initial, not the bench's dialled count",
      );

      await selectExercise(0);
      expect(surface.exerciseName, 'sx-bench');
      expect(
        value(WatchMetricKey.reps),
        14,
        reason: 'the dial was bench work, and bench still holds it',
      );
    });
  });

  group("S-6411 logging a slot consumes only that slot's dials", () {
    test(
      'S-6411 logging squat clears squat and leaves bench dialled',
      () async {
        surface.adjust(WatchMetricKey.reps, 4);
        await engine.advanceExercise();
        surface.adjust(WatchMetricKey.reps, 2);
        surface.adjust(WatchMetricKey.weight, 2);
        expect(value(WatchMetricKey.reps), 12);
        expect(value(WatchMetricKey.weight), 5.0);

        final logged = await surface.log();
        expect(logged.payload['reps'], 12);
        expect(logged.payload['loadKg'], 5.0);

        // The phone's correction of the logged set: the field now reads the
        // observation, which is only possible if the dial was consumed by the
        // log rather than kept beside it.
        await engine.applyMessage({
          'protocolVersion': 1,
          'messageId': 'm-correct-squat',
          'sessionId': engine.session!.sessionId,
          'type': 'session_snapshot',
          'origin': 'phone',
          'sentAt': utcIso(clock.now),
          'payload': {
            'sessionId': engine.session!.sessionId,
            'revision': engine.session!.revision + 1,
            'status': engine.session!.status,
            'currentExerciseIndex': 1,
            'exercises': engine.session!.exercises,
            'entries': [
              {...logged.payload, 'reps': 9},
            ],
            'timers': const <String, Object?>{},
          },
        });
        expect(
          value(WatchMetricKey.reps),
          9,
          reason: "the squat's dialled 12 was confirmed and is no longer held",
        );

        await selectExercise(0);
        expect(
          value(WatchMetricKey.reps),
          14,
          reason: "logging squat did not touch the bench's dial",
        );
      },
    );
  });

  group('S-6415 a log clears the exercise it logged, not the one in flight', () {
    test('S-6415 bench log leaves the squat dialled meanwhile', () async {
      final store = _SuspendingStore();
      final slowEngine = WatchSessionEngine(store, clock: clock.call);
      await slowEngine.createSession(
        modality: 'resistance_lifting',
        exercises: [
          _slot('sx-bench', ['reps', 'sets', 'load']),
          _slot('sx-squat', ['reps', 'sets', 'load']),
        ],
      );
      final slowSurface = WatchLoggingState(
        engine: slowEngine,
        clock: clock.call,
      );

      double reps() => slowSurface.fields
          .singleWhere((row) => row.metricKey == WatchMetricKey.reps)
          .value;

      slowSurface.adjust(WatchMetricKey.reps, 4);
      expect(reps(), 14, reason: 'the bench dialled four detents');

      store.arm();
      final logging = slowSurface.log();

      final reached = await _spin(() => store.suspended);
      expect(reached, isTrue, reason: "the log's commit is in flight");

      await slowEngine.advanceExercise();
      expect(slowSurface.exerciseName, 'sx-squat');
      slowSurface.adjust(WatchMetricKey.reps, 2);
      expect(
        reps(),
        12,
        reason: 'the squat was dialled while the bench log was in flight',
      );

      store.resume();
      final logged = await logging;

      expect(logged.payload['reps'], 14, reason: "the bench's dial is what was logged");
      expect(
        reps(),
        12,
        reason: "the log consumed the bench's dial, not the squat's",
      );
    });
  });

  group('S-6412 a weight dialled on bench never appears on squat', () {
    test('S-6412 squat reads its own initial weight', () async {
      surface.adjust(WatchMetricKey.weight, 5);
      final benchWeight = value(WatchMetricKey.weight);
      expect(benchWeight, 12.5, reason: 'five 2.5 kg detents from zero');

      await engine.advanceExercise();
      expect(surface.exerciseName, 'sx-squat');
      expect(
        value(WatchMetricKey.weight),
        0.0,
        reason: "squat's own initial weight, not the bench's dial",
      );
      expect(value(WatchMetricKey.weight), isNot(benchWeight));
    });
  });

  group('S-6413 a session with no exercise has nothing to dial', () {
    test('S-6413 fields and adjust do not throw', () async {
      final bareEngine = WatchSessionEngine(
        InMemoryWatchSessionStore(),
        clock: clock.call,
      );
      await bareEngine.createSession(modality: null, exercises: const []);
      final bare = WatchLoggingState(engine: bareEngine, clock: clock.call);

      expect(bare.canLog, isFalse);
      expect(() => bare.fields, returnsNormally);
      expect(bare.fields, isEmpty);
      expect(
        () => bare.adjust(WatchMetricKey.reps, 1),
        returnsNormally,
        reason: 'a dial with no slot is a no-op, never a crash',
      );
      expect(bare.fields, isEmpty);
    });
  });
}
