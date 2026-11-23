// Calories on the Wear wrist, the Dart half (plan 305).
//
// Plan: `docs/plans/2026-11-22-305-wear-calories-dart-plan/2026-11-22-305-wear-calories-dart-plan.md`
//   S-30501 the summaries chain
//   S-30502 the recorder stores and announces energy
//   S-30503 the announce rule
//   S-30504 a recovered counter
//   S-30505 the frame's shape, and the validator's refusal
//   S-30506 the session end carries the total
//   S-30507 the label
//   S-30508 the rest screen
//   S-30509 the Wear source and the transport's log coalescing
//
// Mock-first. Plain `test()` for the state layer; widget tests never await a
// real `Future.delayed`.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain_watch_link/omnitrain_watch_link.dart';

import 'package:omnitrain/core/services/diagnostics_log.dart';
import 'package:omnitrain/core/services/diagnostics_storage.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/watch/app/wear_watch_transport.dart';
import 'package:omnitrain/watch/logging/watch_logging_state.dart';
import 'package:omnitrain/watch/logging/watch_rest_screen.dart';
import 'package:omnitrain/watch/sensors/watch_sensor_recording.dart';
import 'package:omnitrain/watch/sensors/wear_sensor_source.dart';
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

final DateTime _t0 = DateTime.utc(2026, 11, 22, 9);

WatchSensorSampleRecord _sample(
  double kcal,
  int seconds, {
  String session = 's',
  int sequence = 0,
}) => WatchSensorSampleRecord(
  recordId: 'r-$session-$seconds-$sequence',
  sessionId: session,
  recordedAt: _t0.add(Duration(seconds: seconds)),
  kind: WatchSensorKind.activeEnergy,
  value: kcal,
  sequence: sequence,
);

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

class _EnergySource implements WatchSensorSource, WatchEnergySource {
  WatchSensorPermission grant = WatchSensorPermission.granted;
  int permissionAsks = 0;
  final _kcal = StreamController<double>.broadcast();

  @override
  Future<WatchSensorPermission> activeEnergyPermission() async {
    permissionAsks++;
    return grant;
  }

  @override
  Stream<double> activeEnergy() => _kcal.stream;

  @override
  Future<WatchSensorPermission> heartRatePermission() async =>
      WatchSensorPermission.unavailable;

  @override
  Future<WatchSensorPermission> locationPermission() async =>
      WatchSensorPermission.unavailable;

  @override
  Stream<double> heartRate() => const Stream.empty();

  @override
  Stream<WatchLocationFix> location() => const Stream.empty();

  Future<void> add(double kcal) async {
    _kcal.add(kcal);
    await pumpEventQueue();
  }
}

class _PlainSource implements WatchSensorSource {
  @override
  Future<WatchSensorPermission> heartRatePermission() async =>
      WatchSensorPermission.unavailable;

  @override
  Future<WatchSensorPermission> locationPermission() async =>
      WatchSensorPermission.unavailable;

  @override
  Stream<double> heartRate() => const Stream.empty();

  @override
  Stream<WatchLocationFix> location() => const Stream.empty();
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
        exercises: [_slot('sx-a')],
      );

  List<Map<String, Object?>> get energyFrames => [
    for (final frame in emitted)
      if (frame['type'] == 'energy_live') frame,
  ];

  Future<void> store1(double kcal, {Duration after = Duration.zero}) async {
    clock.advance(after);
    await engine.appendSensorSample(
      kind: WatchSensorKind.activeEnergy,
      value: kcal,
      recordedAt: clock.now,
    );
  }

  /// Stores one count and announces it, as the recorder does.
  Future<void> reading(double kcal, {Duration after = Duration.zero}) async {
    await store1(kcal, after: after);
    engine.announceEnergy(kilocalories: kcal, at: clock.now);
  }

  double? totalOf(Map<String, Object?> frame) =>
      ((frame['payload']! as Map)['activeEnergyKcal'] as num?)?.toDouble();

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
  group('S-30501 the summaries chain', () {
    double? total(
      List<WatchSensorSampleRecord> samples, {
      int from = 0,
      int to = 1000,
    }) => WatchSensorSummaries.activeEnergy(
      samples,
      _t0.add(Duration(seconds: from)),
      _t0.add(Duration(seconds: to)),
    );

    test('a plain run adds up to the last count', () {
      expect(total([_sample(40, 10), _sample(95.5, 20)]), 95.5);
    });

    test('a smaller count is a restarted counter: it adds whole', () {
      expect(
        total([
          _sample(100, 10),
          _sample(160, 20),
          _sample(20, 30),
          _sample(50, 40),
        ]),
        210,
      );
    });

    test('the last count before the window is the base', () {
      expect(
        total([_sample(30, 5), _sample(50, 15), _sample(90, 25)], from: 10),
        60,
      );
    });

    test(
      'a count outside the window or not a finite non-negative number is ignored',
      () {
        expect(
          total([
            _sample(double.nan, 10),
            _sample(-5, 11),
            _sample(double.infinity, 12),
            _sample(40, 2000),
          ]),
          isNull,
        );
      },
    );

    test('a negative count inside a chain is skipped, not subtracted', () {
      expect(total([_sample(10, 10), _sample(-5, 15), _sample(30, 20)]), 30);
    });

    test('samples of another kind are not energy', () {
      final heartRate = WatchSensorSampleRecord(
        recordId: 'hr-1',
        sessionId: 's',
        recordedAt: _t0.add(const Duration(seconds: 15)),
        kind: WatchSensorKind.heartRate,
        value: 180,
      );

      expect(total([_sample(10, 10), heartRate, _sample(25, 20)]), 25);
    });

    test('rounds to one decimal and a zero total is null', () {
      expect(total([_sample(12.34, 10)]), 12.3);
      expect(total([_sample(0.04, 10)]), isNull);
      expect(total([_sample(0, 10)]), isNull);
    });

    test('samples of the same instant order by sequence', () {
      expect(
        total([_sample(50, 10, sequence: 2), _sample(20, 10, sequence: 1)]),
        50,
        reason: '20 then 50: the chain adds 20 and 30',
      );
    });

    test('the window includes both ends', () {
      expect(total([_sample(10, 10), _sample(25, 20)], from: 10, to: 20), 25);
    });
  });

  group('S-30502 the recorder', () {
    test('stores each count at its instant and shows the newest', () async {
      final rig = _Rig();
      final session = await rig.start();
      final source = _EnergySource();
      // The recorder's clock is not the engine's: the stored row must carry the
      // instant the reading arrived, not whenever the engine got to it.
      final arrival = _Clock(_t0.add(const Duration(hours: 1)));
      final recorder = WatchSensorRecorder(
        engine: rig.engine,
        source: source,
        clock: arrival.call,
      );

      await recorder.start(session);
      expect(recorder.readings.activeEnergyKcal, isNull);
      await source.add(5);
      arrival.advance(const Duration(seconds: 3));
      await source.add(12.5);

      final stored = rig.engine.sensorSamples
          .where((s) => s.kind == WatchSensorKind.activeEnergy)
          .toList();
      expect(stored.map((s) => s.value), [5, 12.5]);
      expect(
        stored.last.recordedAt,
        _t0.add(const Duration(hours: 1, seconds: 3)),
      );
      expect(recorder.readings.activeEnergyKcal, 12.5);
      await recorder.stop();
    });

    test('a refused permission stores nothing and never subscribes', () async {
      final rig = _Rig();
      final session = await rig.start();
      final source = _EnergySource()..grant = WatchSensorPermission.denied;
      final recorder = WatchSensorRecorder(
        engine: rig.engine,
        source: source,
        clock: rig.clock.call,
      );

      await recorder.start(session);
      await source.add(9);

      expect(source.permissionAsks, 1);
      expect(rig.engine.sensorSamples, isEmpty);
      expect(recorder.readings.activeEnergyKcal, isNull);
    });

    test(
      'a source without energy is a wrist without a calorie count',
      () async {
        final rig = _Rig();
        final session = await rig.start();
        final recorder = WatchSensorRecorder(
          engine: rig.engine,
          source: _PlainSource(),
          clock: rig.clock.call,
        );

        await recorder.start(session);

        expect(recorder.readings.activeEnergyKcal, isNull);
        await recorder.stop();
      },
    );

    test('stop cancels it: a later count stores nothing', () async {
      final rig = _Rig();
      final session = await rig.start();
      final source = _EnergySource();
      final recorder = WatchSensorRecorder(
        engine: rig.engine,
        source: source,
        clock: rig.clock.call,
      );
      await recorder.start(session);
      await source.add(5);

      await recorder.stop();
      rig.clock.advance(const Duration(seconds: 1));
      await source.add(50);

      expect(
        rig.engine.sensorSamples
            .where((s) => s.kind == WatchSensorKind.activeEnergy)
            .map((s) => s.value),
        [5],
      );
    });

    test('each stored reading is announced with its own instant', () async {
      final rig = _Rig();
      final session = await rig.start();
      final source = _EnergySource();
      final recorder = WatchSensorRecorder(
        engine: rig.engine,
        source: source,
        clock: rig.clock.call,
      );
      await recorder.start(session);

      await source.add(5);

      expect(rig.energyFrames, hasLength(1));
      expect((rig.energyFrames.single['payload']! as Map)['at'], utcIso(_t0));
      await recorder.stop();
    });

    test('every modality counts energy, not only distance work', () async {
      final rig = _Rig();
      final session = await rig.start(); // resistance_lifting: no distance
      final source = _EnergySource();
      final recorder = WatchSensorRecorder(
        engine: rig.engine,
        source: source,
        clock: rig.clock.call,
      );

      await recorder.start(session);

      expect(source.permissionAsks, 1);
      await recorder.stop();
    });
  });

  group('S-30503 the announce rule', () {
    test('first, then only half a kcal and five seconds on', () async {
      final rig = _Rig();
      await rig.start();

      await rig.reading(10);
      expect(rig.energyFrames, hasLength(1), reason: 'the first goes');

      await rig.reading(10.3, after: const Duration(seconds: 10));
      expect(rig.energyFrames, hasLength(1), reason: 'less than half a kcal');

      // Ten seconds after the last FRAME, with 2 kcal gained: both hold.
      await rig.reading(12, after: const Duration(seconds: 2));
      expect(rig.energyFrames, hasLength(2), reason: 'both now hold');
      expect(rig.totalOf(rig.energyFrames.last), 12);

      await rig.reading(13, after: const Duration(seconds: 3));
      expect(rig.energyFrames, hasLength(2), reason: 'less than five seconds');
      await rig.reading(13.4, after: const Duration(seconds: 1));
      expect(rig.energyFrames, hasLength(2), reason: 'short on both');
      await rig.reading(14, after: const Duration(seconds: 1));
      expect(rig.energyFrames, hasLength(3), reason: 'six seconds, 2 kcal');
    });

    test('the same total again is not news', () async {
      final rig = _Rig();
      await rig.start();
      await rig.reading(10);

      rig.engine.announceEnergy(
        kilocalories: 10,
        at: _t0.add(const Duration(seconds: 30)),
      );

      expect(rig.energyFrames, hasLength(1));
    });

    test('exactly half a kcal and exactly five seconds goes', () async {
      final rig = _Rig();
      await rig.start();
      await rig.reading(10);

      await rig.reading(10.5, after: const Duration(seconds: 5));

      expect(rig.energyFrames, hasLength(2));
    });

    test(
      'a fall goes at once (no stored count to chain: the raw value)',
      () async {
        final rig = _Rig();
        await rig.start();
        rig.engine.announceEnergy(kilocalories: 40, at: _t0);

        rig.engine.announceEnergy(
          kilocalories: 3,
          at: _t0.add(const Duration(seconds: 1)),
        );

        expect(rig.energyFrames.map(rig.totalOf), [40, 3]);
      },
    );

    test(
      'a value that is not a finite number of at least zero sends nothing',
      () async {
        final rig = _Rig();
        await rig.start();

        rig.engine.announceEnergy(kilocalories: double.nan, at: _t0);
        rig.engine.announceEnergy(kilocalories: -1, at: _t0);
        rig.engine.announceEnergy(kilocalories: double.infinity, at: _t0);

        expect(rig.energyFrames, isEmpty);
      },
    );

    test('a zero is a real reading and goes', () async {
      final rig = _Rig();
      await rig.start();

      rig.engine.announceEnergy(kilocalories: 0, at: _t0);

      expect(rig.energyFrames, hasLength(1));
      expect(rig.totalOf(rig.energyFrames.single), 0);
    });

    test('nothing goes once the session has ended', () async {
      final rig = _Rig();
      await rig.start();
      await rig.engine.finishSession();

      // No count stored: the raw value would be a first frame for the session,
      // so only the session's status keeps it from going out.
      rig.engine.announceEnergy(
        kilocalories: 99,
        at: _t0.add(const Duration(minutes: 5)),
      );

      expect(rig.energyFrames, isEmpty);
    });

    test('a new session starts its own count', () async {
      final rig = _Rig();
      await rig.start();
      await rig.reading(10);
      await rig.engine.finishSession();
      await rig.start();

      rig.engine.announceEnergy(
        kilocalories: 10,
        at: rig.clock.now.add(const Duration(seconds: 1)),
      );

      expect(
        rig.energyFrames,
        hasLength(2),
        reason: 'first for the new session',
      );
    });

    test('the frame is live only: nothing is stored for it', () async {
      final rig = _Rig();
      await rig.start();
      await rig.reading(10);

      expect(
        rig.engine.pendingObservations().expand(
          (f) => (f['payload']! as Map)['events'] as List,
        ),
        isEmpty,
      );
    });
  });

  test('S-30504 a recovered counter never pulls the total down', () async {
    final rig = _Rig();
    await rig.start();
    await rig.reading(100);
    await rig.reading(120, after: const Duration(seconds: 10));

    // The workout was recovered: the platform counter restarts from zero.
    await rig.reading(20, after: const Duration(seconds: 10));

    expect(rig.totalOf(rig.energyFrames.last), 140);
    expect(
      rig.energyFrames.map(rig.totalOf),
      [100, 120, 140],
      reason: 'the chain: 100, +20, +20 after the restart',
    );
  });

  group('S-30505 the frame', () {
    test('has the keys of the shared fixture and conforms', () async {
      final rig = _Rig();
      final session = await rig.start();
      await rig.reading(42.5);
      final frame = rig.energyFrames.single;
      final fixture =
          jsonDecode(
                File(
                  'watch/sync_protocol/fixtures/valid/energy_live.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;

      expect(frame.keys.toSet(), fixture.keys.toSet());
      expect(
        (frame['payload']! as Map).keys.toSet(),
        (fixture['payload']! as Map).keys.toSet(),
      );
      expect(frame['type'], 'energy_live');
      expect(frame['origin'], 'watch');
      expect(frame['sessionId'], session.sessionId);
      expect(
        frame['messageId'],
        'msg-energy-${session.sessionId}-${_t0.millisecondsSinceEpoch}',
      );
      expect(frame['sentAt'], utcIso(_t0));
      expect(_validator().validateEnvelope(frame), isEmpty);
    });

    test(
      'a refused frame records no mark, so the next reading may go',
      () async {
        final rig = _Rig();
        // An engine whose validator refuses everything: the refused frame must
        // record no mark, so the next reading is a first one again.
        _RefusingValidator.asked = 0;
        final refusing = WatchSessionEngine(
          InMemoryWatchSessionStore(),
          clock: rig.clock.call,
          onEmit: rig.emitted.add,
          validator: _RefusingValidator(),
        );
        await refusing.createSession(
          modality: null,
          exercises: [_slot('sx-a')],
        );
        _RefusingValidator.asked = 0;

        refusing.announceEnergy(kilocalories: 5, at: _t0);
        refusing.announceEnergy(
          kilocalories: 5.1,
          at: _t0.add(const Duration(seconds: 1)),
        );

        expect(rig.energyFrames, isEmpty);
        expect(
          _RefusingValidator.asked,
          2,
          reason:
              'the second call was a first call again, not a suppressed one',
        );
      },
    );
  });

  group('S-30506 the session end', () {
    test('carries the measured total for a wrist-created session', () async {
      final rig = _Rig();
      final session = await rig.start();
      await rig.reading(10);
      await rig.reading(30, after: const Duration(seconds: 30));
      rig.clock.advance(const Duration(seconds: 5));
      await rig.engine.finishSession();

      final end = rig.sessionEnd(session.sessionId)!;

      expect(end['activeEnergyKcal'], 30);
    });

    test('a followed session carries it too', () async {
      final rig = _Rig();
      final session = await rig.start(source: 'phone');
      await rig.reading(8);
      await rig.reading(21.5, after: const Duration(seconds: 20));
      await rig.engine.finishSession();

      final end = rig.sessionEnd(session.sessionId)!;

      expect(end['followed'], isTrue);
      expect(end['activeEnergyKcal'], 21.5);
    });

    test('omits the field when nothing was measured', () async {
      final rig = _Rig();
      final session = await rig.start();
      await rig.engine.finishSession();

      final end = rig.sessionEnd(session.sessionId)!;

      expect(end.containsKey('activeEnergyKcal'), isFalse);
    });

    test('a restarted counter adds whole, as the live total did', () async {
      final rig = _Rig();
      final session = await rig.start();
      await rig.reading(100);
      await rig.reading(20, after: const Duration(seconds: 10));
      await rig.engine.finishSession();

      expect(rig.sessionEnd(session.sessionId)!['activeEnergyKcal'], 120);
    });

    test('conforms to the protocol with the field present', () async {
      final rig = _Rig();
      await rig.start();
      await rig.reading(10);
      await rig.reading(30, after: const Duration(seconds: 30));
      await rig.engine.finishSession();

      for (final frame in rig.engine.pendingObservations()) {
        expect(_validator().validateEnvelope(frame), isEmpty);
      }
    });
  });

  group('S-30507 the label', () {
    Future<String?> labelFor(double? kcal) async {
      final rig = _Rig(validate: false);
      final session = await rig.start();
      final recorder = WatchSensorRecorder(
        engine: rig.engine,
        source: _PlainSource(),
        clock: rig.clock.call,
      );
      await recorder.start(session);
      if (kcal != null) await rig.store1(kcal);
      return WatchLoggingState(
        engine: rig.engine,
        clock: rig.clock.call,
        sensors: recorder,
      ).activeEnergyLabel;
    }

    test('whole kilocalories, once at least half one is measured', () async {
      expect(await labelFor(95.5), '96 kcal burned');
      expect(await labelFor(1234.4), '1234 kcal burned');
      expect(await labelFor(0.5), '1 kcal burned');
      expect(await labelFor(0.3), isNull);
      expect(await labelFor(null), isNull);
    });
  });

  group('S-30508 the rest screen', () {
    Future<WatchLoggingState> resting(
      WidgetTester tester, {
      double? kcal,
    }) async {
      final rig = _Rig(validate: false);
      final session = await rig.start();
      final recorder = WatchSensorRecorder(
        engine: rig.engine,
        source: _PlainSource(),
        clock: rig.clock.call,
      );
      await tester.runAsync(() => recorder.start(session));
      final state = WatchLoggingState(
        engine: rig.engine,
        clock: rig.clock.call,
        sensors: recorder,
      );
      await tester.runAsync(() async {
        await state.log();
        if (kcal != null) await rig.store1(kcal);
      });
      return state;
    }

    testWidgets('shows the line under the clock only with a reading', (
      tester,
    ) async {
      final withReading = await resting(tester, kcal: 95.5);
      await tester.pumpWidget(
        MaterialApp(
          home: WatchRestScreen(state: withReading, onNext: () {}),
        ),
      );
      await tester.pump();

      expect(find.text('96 kcal burned'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
      final clock = tester.getRect(find.text('0:00'));
      final line = tester.getRect(find.text('96 kcal burned'));
      expect(line.top, greaterThanOrEqualTo(clock.bottom));

      final without = await resting(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: WatchRestScreen(state: without, onNext: () {}),
        ),
      );
      await tester.pump();
      expect(find.textContaining('kcal'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('is spoken as calories burned', (tester) async {
      final state = await resting(tester, kcal: 1);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: WatchRestScreen(state: state, onNext: () {}),
        ),
      );
      await tester.pump();

      final node = tester.getSemantics(find.text('1 kcal burned'));
      expect(node.label, contains('Calories burned'));
      expect(node.value, '1 kilocalorie burned');
      handle.dispose();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('scales the line down on a very narrow screen', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(110, 192);
      addTearDown(tester.view.reset);
      final state = await resting(tester, kcal: 1234.4);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
          home: WatchRestScreen(state: state, onNext: () {}),
        ),
      );
      await tester.pump();

      final line = tester.getRect(find.text('1234 kcal burned'));
      expect(line.left, greaterThanOrEqualTo(0));
      expect(line.right, lessThanOrEqualTo(110));
      await tester.pumpWidget(const SizedBox());
    });

    for (final side in const [192.0, 227.0]) {
      testWidgets('fits ${side}dp with a four-digit total', (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = Size(side, side);
        addTearDown(tester.view.reset);
        final state = await resting(tester, kcal: 1234.4);

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
            home: WatchRestScreen(state: state, onNext: () {}),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull, reason: 'no overflow');
        expect(find.text('1234 kcal burned'), findsOneWidget);
        expect(find.text('0:00'), findsOneWidget);
        final next = tester.getRect(find.text('Next'));
        expect(next.bottom, lessThanOrEqualTo(side));
        await tester.pumpWidget(const SizedBox());
      });
    }
  });

  group('S-30509 the Wear source and the transport log', () {
    const methods = MethodChannel('omnitrain/wear_sensors/methods');
    const energy = EventChannel('omnitrain/wear_sensors/energy');

    TestDefaultBinaryMessenger messenger() =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() {
      messenger().setMockMethodCallHandler(methods, null);
      messenger().setMockStreamHandler(energy, null);
    });

    test('asks on the sensors channel and reads the energy channel', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final asked = <String>[];
      messenger().setMockMethodCallHandler(methods, (call) async {
        asked.add(call.method);
        return 'granted';
      });
      messenger().setMockStreamHandler(
        energy,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            events
              ..success(12.5)
              ..success('junk')
              ..success(20)
              ..endOfStream();
          },
        ),
      );
      final source = WearSensorSource();

      expect(
        await source.activeEnergyPermission(),
        WatchSensorPermission.granted,
      );
      expect(asked, ['activeEnergyPermission']);
      expect(await source.activeEnergy().toList(), [12.5, 20.0]);
      expect(WearSensorSource.energyName, 'omnitrain/wear_sensors/energy');
      expect(source, isA<WatchEnergySource>());
    });

    test('a missing native half reads unavailable', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      messenger().setMockMethodCallHandler(methods, null);

      expect(
        await WearSensorSource().activeEnergyPermission(),
        WatchSensorPermission.unavailable,
      );
    });

    group('the log', () {
      const linkMethods = MethodChannel('omnitrain/watch_link/methods');
      const linkEvents = EventChannel('omnitrain/watch_link/events');

      setUp(() {
        TestWidgetsFlutterBinding.ensureInitialized();
        messenger().setMockMethodCallHandler(linkMethods, (_) async => null);
        messenger().setMockStreamHandler(
          linkEvents,
          MockStreamHandler.inline(onListen: (a, e) {}),
        );
      });
      tearDown(() {
        messenger().setMockMethodCallHandler(linkMethods, null);
        messenger().setMockStreamHandler(linkEvents, null);
      });

      Map<String, Object?> frame(String type, String id) => {
        'protocolVersion': 1,
        'messageId': id,
        'type': type,
        'origin': 'watch',
        'sentAt': '2026-11-22T09:00:00Z',
        'sessionId': 's1',
        'payload': <String, Object?>{},
      };

      test('energy frames coalesce, other frames do not', () async {
        var now = _t0;
        final log = DiagnosticsLog(
          storage: InMemoryDiagnosticsStorage(),
          clock: () => now,
        );
        final transport = WearWatchTransport(
          link: WatchLink(),
          diagnostics: log,
        );
        addTearDown(transport.close);
        await transport.start();

        for (var i = 0; i < 5; i++) {
          now = _t0.add(Duration(seconds: i * 5));
          await transport.send(frame('energy_live', 'e$i'));
          await transport.send(frame('observations_up', 'o$i'));
        }

        final lines = [for (final e in log.events()) '${e.kind} ${e.detail}'];
        expect(
          lines.where((l) => l.startsWith('frame_sent energy_live')),
          hasLength(1),
          reason: 'five live energy frames inside a minute are one line',
        );
        expect(
          lines.where((l) => l.startsWith('frame_sent observations_up')),
          hasLength(5),
        );
      });

      test(
        'an energy frame the radio refuses is dropped, never queued',
        () async {
          final calls = <String>[];
          messenger().setMockMethodCallHandler(linkMethods, (call) async {
            calls.add(call.method);
            if (call.method == 'sendMessage') {
              throw PlatformException(code: 'not_reachable');
            }
            return null;
          });
          final transport = WearWatchTransport(link: WatchLink());
          addTearDown(transport.close);
          await transport.start();

          await transport.send(frame('energy_live', 'e1'));

          expect(calls, contains('sendMessage'));
          expect(calls, isNot(contains('transferUserInfo')));
        },
      );
    });
  });
}

/// A validator that refuses everything, counting how often it was asked.
class _RefusingValidator implements SyncProtocolValidator {
  static int asked = 0;

  @override
  List<SyncProtocolRejection> validateEnvelope(Map<String, Object?> envelope) {
    asked++;
    return const [
      SyncProtocolRejection(code: 'test', path: r'$', message: 'refused'),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
