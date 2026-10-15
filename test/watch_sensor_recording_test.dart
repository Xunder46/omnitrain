/// Sensor recording on the wrist: the platform workout session, live heart
/// rate, and GPS-derived distance.
///
/// Plan: `docs/plans/2026-07-13-11-d-watch-sensor-recording-plan.md`,
/// scenarios S-001 to S-008. The same register runs in
/// `watch/watchos/Tests/WatchSessionEngineTests/WatchSensorRecordingTests.swift`,
/// and both suites read `watch/contract/watch_sensor_contract.json`.
///
/// Scenario map:
///   S-001 strength session does not activate GPS           → `S-001 ...`
///   S-002 distance session activates GPS and logs distance  → `S-002 ...`
///   S-003 live heart rate on the logging surface            → `S-003 ...`
///   S-004 GPS-derived distance leaves the watch             → `S-004 ...`
///   S-005 force-kill leaves no stuck platform workout       → `S-005 ...`
///   S-006 permission denial degrades gracefully             → `S-006 ...`
///   S-007 unmapped modality falls back to a generic type    → `S-007 ...`
///   S-008 GPS activation derives from capabilities          → `S-008 ...`
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/capability.dart';
import 'package:omnitrain/core/constants/modality.dart';
import 'package:omnitrain/core/constants/modality_config.dart';
import 'package:omnitrain/core/utils/unit_formatter.dart';
import 'package:omnitrain/watch/logging/watch_logging_screen.dart';
import 'package:omnitrain/watch/logging/watch_logging_state.dart';
import 'package:omnitrain/watch/logging/watch_metric_stepping.dart';
import 'package:omnitrain/watch/sensors/watch_platform_workout.dart';
import 'package:omnitrain/watch/sensors/watch_sensor_recording.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';

/// Deterministic clock. Sensor timestamps are asserted against this, never
/// against `DateTime.now()`.
class _Clock {
  _Clock(this.now);

  DateTime now;

  DateTime call() => now;

  void advance(Duration delta) => now = now.add(delta);
}

Map<String, Object?> _slot(String id, List<String> capabilities) => {
  'sessionExerciseId': id,
  'exerciseId': 'ex-$id',
  'name': id,
  'capabilities': capabilities,
};

/// The sensor hardware, with the permissions the user granted and two streams
/// the test drives. Every subscription is counted, so "was the radio woken for
/// work that has no distance" is an assertion rather than an assumption.
class _FakeSensorSource implements WatchSensorSource {
  WatchSensorPermission heartRateGrant = WatchSensorPermission.granted;
  WatchSensorPermission locationGrant = WatchSensorPermission.granted;

  int heartRateSubscriptions = 0;
  int locationSubscriptions = 0;

  final _beats = StreamController<double>.broadcast();
  final _fixes = StreamController<WatchLocationFix>.broadcast();

  @override
  Future<WatchSensorPermission> heartRatePermission() async => heartRateGrant;

  @override
  Future<WatchSensorPermission> locationPermission() async => locationGrant;

  @override
  Stream<double> heartRate() {
    heartRateSubscriptions++;
    return _beats.stream;
  }

  @override
  Stream<WatchLocationFix> location() {
    locationSubscriptions++;
    return _fixes.stream;
  }

  Future<void> beat(double beatsPerMinute) async {
    _beats.add(beatsPerMinute);
    await pumpEventQueue();
  }

  Future<void> fix(double cumulativeMetres) async {
    _fixes.add(WatchLocationFix(distanceMeters: cumulativeMetres));
    await pumpEventQueue();
  }

  Future<void> close() async {
    await _beats.close();
    await _fixes.close();
  }
}

/// The health store, as the watch sees it: sessions it started, and whatever a
/// previous process left in progress.
class _FakePlatformStore implements WatchPlatformWorkoutStore {
  final List<String> begun = [];
  final List<String> ended = [];

  /// What the health store reports as still running — the shape a kill leaves
  /// behind.
  final List<String> inProgress = [];

  @override
  Future<void> begin(String activityType) async {
    begun.add(activityType);
    inProgress.add(activityType);
  }

  @override
  Future<void> end() async {
    if (inProgress.isNotEmpty) ended.add(inProgress.removeAt(0));
  }

  @override
  Future<List<String>> inProgressActivityTypes() async =>
      List.unmodifiable(inProgress);
}

/// The sensor vocabulary both watch clients are held to. The watchOS suite
/// reads this same file, so a change to the table on either platform fails on
/// both.
Map<String, Object?> _contract() =>
    (jsonDecode(
              File(
                '${Directory.current.path}/watch/contract/'
                'watch_sensor_contract.json',
              ).readAsStringSync(),
            )
            as Map)
        .cast<String, Object?>();

void main() {
  late _Clock clock;
  late _FakeSensorSource source;
  late _FakePlatformStore health;
  late InMemoryWatchSessionStore store;
  late WatchSessionEngine engine;

  Future<WatchSessionSensors> sensorsFor() async {
    final sensors = WatchSessionSensors(
      platform: WatchPlatformWorkout(store: health),
      recorder: WatchSensorRecorder(
        engine: engine,
        source: source,
        clock: clock.call,
      ),
    );
    addTearDown(sensors.stop);
    return sensors;
  }

  Future<WatchSessionRecord> sessionFor(
    String? modality, {
    Map<String, Object?>? slot,
  }) => engine.createSession(modality: modality, exercises: [?slot]);

  /// Logs one entry through the engine, so retention has an observation to gate
  /// on and a receipt to wait for.
  Future<void> logEntry(String entryId) async {
    await engine.appendObservation({
      'entryId': entryId,
      'eventId': entryId,
      'kind': 'timed',
      'loggedAt': utcIso(clock.now),
      'sessionExerciseId': 'sx-run',
      'startedAt': utcIso(clock.now),
      'endedAt': utcIso(clock.now),
    });
  }

  setUp(() {
    clock = _Clock(DateTime.utc(2026, 7, 13, 17));
    source = _FakeSensorSource();
    health = _FakePlatformStore();
    store = InMemoryWatchSessionStore();
    engine = WatchSessionEngine(store, clock: clock.call);
  });

  tearDown(() => source.close());

  group('S-001 a strength session leaves the GPS radio alone', () {
    test(
      'S-001 the platform workout carries the modality\'s own type',
      () async {
        final sensors = await sensorsFor();
        final session = await sessionFor(
          Modality.resistanceLifting,
          slot: _slot('sx-bench', [
            ExerciseCapability.reps,
            ExerciseCapability.sets,
          ]),
        );

        await sensors.start(session);

        expect(health.begun, ['traditionalStrengthTraining']);
        expect(health.inProgress, ['traditionalStrengthTraining']);
      },
    );

    test(
      'S-001 no location subscription is made for work with no distance',
      () async {
        final sensors = await sensorsFor();
        final session = await sessionFor(
          Modality.resistanceLifting,
          slot: _slot('sx-bench', [
            ExerciseCapability.reps,
            ExerciseCapability.load,
          ]),
        );

        await sensors.start(session);
        await source.fix(500);

        expect(source.locationSubscriptions, 0);
        expect(sensors.recorder.isMeasuringDistance, isFalse);
        expect(
          engine.sensorSamples.where((row) => row.kind == WatchSensorKind.gps),
          isEmpty,
        );
      },
    );
  });

  group('S-002 a distance modality records GPS', () {
    test(
      'S-002 GPS starts with the session and the live distance advances',
      () async {
        final sensors = await sensorsFor();
        final session = await sessionFor(
          Modality.cardioEndurance,
          slot: _slot('sx-run', [
            ExerciseCapability.time,
            ExerciseCapability.distance,
          ]),
        );

        await sensors.start(session);
        expect(sensors.recorder.isMeasuringDistance, isTrue);
        expect(source.locationSubscriptions, 1);

        await source.fix(400);
        expect(sensors.recorder.readings.distanceMeters, 400);
        clock.advance(const Duration(seconds: 1));
        await source.fix(1200);
        expect(sensors.recorder.readings.distanceMeters, 1200);
      },
    );

    test(
      'S-002 stopping settles the session distance at the measured total',
      () async {
        final sensors = await sensorsFor();
        final session = await sessionFor(Modality.cardioEndurance);

        await sensors.start(session);
        await source.fix(400);
        clock.advance(const Duration(seconds: 1));
        await source.fix(2500);
        clock.advance(const Duration(minutes: 10));
        await sensors.stop();

        final settled = engine.sensorSamples.last;
        expect(settled.kind, WatchSensorKind.distance);
        expect(settled.value, 2500);
        expect(settled.sessionId, session.sessionId);
        expect(sensors.recorder.isMeasuringDistance, isFalse);
      },
    );
  });

  group('S-003 live heart rate', () {
    test('S-003 beats are stored against the session as they arrive', () async {
      final sensors = await sensorsFor();
      final session = await sessionFor(Modality.resistanceLifting);

      await sensors.start(session);
      expect(source.heartRateSubscriptions, 1);

      await source.beat(96);
      clock.advance(const Duration(seconds: 2));
      await source.beat(104);

      final beats = engine.sensorSamples
          .where((row) => row.kind == WatchSensorKind.heartRate)
          .toList();
      expect(beats.map((row) => row.value), [96, 104]);
      expect(beats.first.sessionId, session.sessionId);
      expect(sensors.recorder.readings.heartRate, 104);
    });

    testWidgets(
      'S-003 the logging surface shows the live heart rate and distance',
      (tester) async {
        await sessionFor(
          Modality.cardioEndurance,
          slot: _slot('sx-run', [
            ExerciseCapability.time,
            ExerciseCapability.distance,
          ]),
        );
        await engine.appendSensorSample(
          kind: WatchSensorKind.heartRate,
          value: 128,
        );
        await engine.appendSensorSample(kind: WatchSensorKind.gps, value: 1000);
        clock.advance(const Duration(minutes: 5));

        final state = WatchLoggingState(
          engine: engine,
          clock: clock.call,
          sensors: WatchSensorRecorder(
            engine: engine,
            source: source,
            clock: clock.call,
          ),
        );

        await tester.pumpWidget(
          MaterialApp(home: WatchLoggingScreen(state: state)),
        );
        await tester.pump();

        expect(find.textContaining('128'), findsWidgets);
        expect(find.textContaining('1.0'), findsWidgets);
        expect(state.paceLabel, '5:00 /km');

        // Dispose the screen so its ticker does not outlive the test.
        await tester.pumpWidget(const SizedBox());
      },
    );
  });

  group('S-004 measured distance is what leaves the watch', () {
    test(
      'S-004 the logged effort carries the GPS total, not a dialled value',
      () async {
        final sensors = await sensorsFor();
        final session = await sessionFor(
          Modality.cardioEndurance,
          slot: _slot('sx-run', [
            ExerciseCapability.time,
            ExerciseCapability.distance,
          ]),
        );
        await sensors.start(session);
        await source.fix(3000);
        clock.advance(const Duration(minutes: 20));

        final state = WatchLoggingState(
          engine: engine,
          clock: clock.call,
          sensors: sensors.recorder,
        );
        await state.log();

        final logged = engine.observations.last;
        expect(logged.payload['distanceMeters'], 3000);
        expect(logged.sessionId, session.sessionId);
      },
    );

    test(
      "S-004 without a fix the distance row is the user's to fill",
      () async {
        source.locationGrant = WatchSensorPermission.denied;
        final sensors = await sensorsFor();
        final session = await sessionFor(
          Modality.cardioEndurance,
          slot: _slot('sx-bike', [
            ExerciseCapability.time,
            ExerciseCapability.distance,
          ]),
        );
        await sensors.start(session);

        final state = WatchLoggingState(
          engine: engine,
          clock: clock.call,
          sensors: sensors.recorder,
        );
        state.adjust(WatchMetricKey.distance, 15);

        await state.log();

        expect(engine.observations.last.payload['distanceMeters'], 1500);
      },
    );
  });

  group('S-005 a kill leaves nothing running in the health store', () {
    test(
      'S-005 the next launch ends the workout the kill left behind',
      () async {
        health.inProgress.add('running');
        final sensors = await sensorsFor();

        final ended = await sensors.recoverInProgress();

        expect(ended, ['running']);
        expect(health.inProgress, isEmpty);
      },
    );

    test(
      'S-005 nothing is ended when the last session closed cleanly',
      () async {
        final sensors = await sensorsFor();

        expect(await sensors.recoverInProgress(), isEmpty);
        expect(health.ended, isEmpty);
      },
    );

    test('S-005 recovering leaves the session\'s own log untouched', () async {
      final session = await sessionFor(Modality.cardioEndurance);
      await engine.appendObservation({
        'entryId': 'e-1',
        'eventId': 'e-1',
        'kind': 'timed',
        'loggedAt': utcIso(clock.now),
        'sessionExerciseId': 'sx-run',
        'startedAt': utcIso(clock.now),
        'endedAt': utcIso(clock.now),
        'distanceMeters': 900,
      });
      health.inProgress.add('running');

      final sensors = await sensorsFor();
      await sensors.recoverInProgress();

      expect(engine.observations.single.entryId, 'e-1');
      expect(engine.session?.sessionId, session.sessionId);
    });
  });

  group('S-006 permission denial degrades gracefully', () {
    test(
      'S-006 denied heart rate skips the subscription, logging carries on',
      () async {
        source.heartRateGrant = WatchSensorPermission.denied;
        final sensors = await sensorsFor();
        final session = await sessionFor(
          Modality.resistanceLifting,
          slot: _slot('sx-bench', [
            ExerciseCapability.reps,
            ExerciseCapability.load,
          ]),
        );

        await sensors.start(session);
        await source.beat(110);

        expect(source.heartRateSubscriptions, 0);
        expect(sensors.recorder.readings.heartRate, isNull);
        final state = WatchLoggingState(
          engine: engine,
          clock: clock.call,
          sensors: sensors.recorder,
        );
        state.adjust(WatchMetricKey.reps, 7);
        final logged = await state.log();

        expect(logged.payload['reps'], 17);
        expect(engine.observations, hasLength(1));
      },
    );

    test(
      'S-006 denied location leaves the session with no distance at all',
      () async {
        source.locationGrant = WatchSensorPermission.denied;
        final sensors = await sensorsFor();
        final session = await sessionFor(Modality.cardioEndurance);

        await sensors.start(session);

        expect(source.locationSubscriptions, 0);
        expect(sensors.recorder.readings.distanceMeters, isNull);
        expect(
          engine.sensorSamples.where((row) => row.kind == WatchSensorKind.gps),
          isEmpty,
        );
      },
    );

    test('S-006 hardware that is not there is not a failure', () async {
      source.heartRateGrant = WatchSensorPermission.unavailable;
      source.locationGrant = WatchSensorPermission.unavailable;
      final sensors = await sensorsFor();
      final session = await sessionFor(Modality.cardioEndurance);

      await sensors.start(session);
      await sensors.stop();

      expect(engine.sensorSamples, isEmpty);
      expect(source.heartRateSubscriptions, 0);
      expect(source.locationSubscriptions, 0);
    });
  });

  group('S-007 an unmapped modality still produces a workout', () {
    test(
      'S-007 an unknown modality falls back to the generic platform type',
      () async {
        final sensors = await sensorsFor();
        final session = await sessionFor('not_a_modality');

        await sensors.start(session);

        expect(health.begun, [WatchActivityTypes.generic.watchOs]);
      },
    );

    test('S-007 free training falls back too', () async {
      final sensors = await sensorsFor();
      final session = await sessionFor(null);

      await sensors.start(session);

      expect(health.begun, [WatchActivityTypes.generic.watchOs]);
    });

    test(
      'S-007 every seeded modality carries a mapped type on both platforms',
      () {
        final types = _contract()['activityTypes']! as Map;

        for (final modality in Modality.all) {
          expect(
            types.keys,
            contains(modality),
            reason: '$modality has no platform workout type',
          );
          final mapped = (types[modality]! as Map).cast<String, Object?>();
          expect(mapped['watchos'], isA<String>());
          expect(mapped['wear'], isA<String>());
          expect(
            WatchActivityTypes.forModality(modality).watchOs,
            mapped['watchos'],
            reason: '$modality diverged from the shared contract',
          );
          expect(
            WatchActivityTypes.forModality(modality).wear,
            mapped['wear'],
            reason: '$modality diverged from the shared contract',
          );
        }
      },
    );

    test('S-007 the fallback is the contract\'s generic type', () {
      final generic = (_contract()['genericActivityType']! as Map)
          .cast<String, Object?>();
      expect(WatchActivityTypes.generic.watchOs, generic['watchos']);
      expect(WatchActivityTypes.generic.wear, generic['wear']);
    });
  });

  group('S-008 the GPS decision reads capabilities, not names', () {
    test('S-008 the decision follows the capability profile', () {
      for (final entry in ModalityConfig.configs.entries) {
        final config = entry.value;
        final carriesDistance = [
          ...config.primaryCapabilities,
          ...config.secondaryCapabilities,
        ].contains(ExerciseCapability.distance);

        expect(
          WatchGpsPolicy.isRequired(entry.key),
          carriesDistance,
          reason: '${entry.key} diverged from its capability profile',
        );
      }
    });

    test(
      'S-008 a modality that names distance but cannot cover it stays off',
      () {
        // Both carry the word in their profile, in the anti-capability list: the
        // decision has to read what the modality *can* do.
        expect(
          ModalityConfig.forModality(
            Modality.isometricStretching,
          )!.antiCapabilities,
          contains(ExerciseCapability.distance),
        );
        expect(
          WatchGpsPolicy.isRequired(Modality.isometricStretching),
          isFalse,
        );
        expect(WatchGpsPolicy.isRequired(Modality.resistanceLifting), isFalse);
      },
    );

    test('S-008 the contract\'s expectation list is the derived answer', () {
      final expected = (_contract()['gpsModalities']! as List).cast<String>();
      final derived = [
        for (final modality in ModalityConfig.configs.keys)
          if (WatchGpsPolicy.isRequired(modality)) modality!,
      ];

      expect(derived, unorderedEquals(expected));
    });
    test('S-008 the contract carries the capability profile Swift reads', () {
      final profiles = (_contract()['modalityCapabilities']! as List).map(
        (entry) => (entry as Map).cast<String, Object?>(),
      );
      final byModality = {
        for (final profile in profiles)
          profile['modality'] as String?: (profile['capabilities']! as List)
              .cast<String>(),
      };

      for (final entry in ModalityConfig.configs.entries) {
        final config = entry.value;
        expect(
          byModality[entry.key]?.toSet(),
          {...config.primaryCapabilities, ...config.secondaryCapabilities},
          reason:
              'the shared capability profile for ${entry.key} no longer '
              'matches ModalityConfig, so the two clients would decide GPS '
              'differently',
        );
      }
    });
  });

  group('Sensor storage', () {
    test('the sample kinds are the ones both clients agreed on', () {
      final kinds = (_contract()['kinds']! as List).cast<String>();
      expect(WatchSensorKind.all, unorderedEquals(kinds));
    });

    test('a sample round-trips through storage unchanged', () async {
      final session = await sessionFor(Modality.cardioEndurance);
      final stored = await engine.appendSensorSample(
        kind: WatchSensorKind.gps,
        value: 1234.5,
      );

      final decoded = WatchRecord.fromJson(
        (jsonDecode(jsonEncode(stored.toJson())) as Map)
            .cast<String, Object?>(),
      );

      expect(decoded, isA<WatchSensorSampleRecord>());
      final sample = decoded as WatchSensorSampleRecord;
      expect(sample.kind, WatchSensorKind.gps);
      expect(sample.value, 1234.5);
      expect(sample.sessionId, session.sessionId);
      expect(sample.recordedAt, clock.now);
      expect(sample.recordId, stored.recordId);
    });

    test('appending the same instant twice stores one row', () async {
      await sessionFor(Modality.cardioEndurance);

      final first = await engine.appendSensorSample(
        kind: WatchSensorKind.heartRate,
        value: 88,
      );
      final again = await engine.appendSensorSample(
        kind: WatchSensorKind.heartRate,
        value: 88,
      );

      expect(again.recordId, first.recordId);
      expect(engine.sensorSamples, hasLength(1));
    });

    test('samples are still there after a relaunch', () async {
      await sessionFor(Modality.cardioEndurance);
      await engine.appendSensorSample(
        kind: WatchSensorKind.heartRate,
        value: 121,
      );

      final restarted = WatchSessionEngine(store, clock: clock.call);
      await restarted.restore();

      expect(restarted.sensorSamples.single.value, 121);
      expect(restarted.sensorSamples.single.kind, WatchSensorKind.heartRate);
    });

    test('pruning confirmed observations leaves sensor rows alone', () async {
      await sessionFor(Modality.cardioEndurance);
      await engine.appendSensorSample(
        kind: WatchSensorKind.heartRate,
        value: 99,
      );

      expect(await engine.pruneConfirmed(), isEmpty);
      expect(engine.sensorSamples, hasLength(1));
    });

    test(
      'a settled session releases its log; a running one keeps it',
      () async {
        await sessionFor(
          Modality.cardioEndurance,
          slot: _slot('sx-run', [ExerciseCapability.time]),
        );
        await logEntry('e-1');
        await engine.appendSensorSample(
          kind: WatchSensorKind.heartRate,
          value: 128,
        );
        await engine.confirmObservations(['e-1']);
        await engine.finishSession();

        expect(await engine.pruneSettledSensorSamples(), hasLength(1));
        expect(engine.sensorSamples, isEmpty);
        expect(engine.observations, hasLength(1));
      },
    );

    test('a session still running never loses its readings', () async {
      await sessionFor(Modality.cardioEndurance);
      await engine.appendSensorSample(
        kind: WatchSensorKind.heartRate,
        value: 96,
      );

      expect(await engine.pruneSettledSensorSamples(), isEmpty);
      expect(engine.sensorSamples, hasLength(1));
    });

    test('an entry still owed to the phone holds the log back', () async {
      await sessionFor(Modality.cardioEndurance);
      await logEntry('e-1');
      await engine.appendSensorSample(
        kind: WatchSensorKind.heartRate,
        value: 96,
      );
      await engine.finishSession();

      expect(await engine.pruneSettledSensorSamples(), isEmpty);
      expect(engine.sensorSamples, hasLength(1));
    });
  });

  group('Sensor wiring', () {
    test(
      'starting a session closes the workout the last one left open',
      () async {
        final sensors = await sensorsFor();
        await sensors.start(await sessionFor(Modality.resistanceLifting));
        // The wrist runs one session at a time (D-171): a second workout is
        // only reachable once the first one has ended.
        await engine.finishSession();
        await sensors.start(await sessionFor(null));

        expect(health.begun, [
          'traditionalStrengthTraining',
          WatchActivityTypes.generic.watchOs,
        ]);
        expect(
          health.ended,
          ['traditionalStrengthTraining'],
          reason:
              'the platform grants one workout at a time; a second one started '
              'over a dangling first is the stuck state recovery exists to clear',
        );
      },
    );

    test('a reading is stored without being sent anywhere', () async {
      final emitted = <Map<String, Object?>>[];
      final watched = WatchSessionEngine(
        InMemoryWatchSessionStore(),
        clock: clock.call,
        onEmit: emitted.add,
      );
      await watched.createSession(
        modality: Modality.cardioEndurance,
        exercises: [
          _slot('sx-run', [ExerciseCapability.time]),
        ],
      );
      expect(
        emitted,
        hasLength(2),
        reason:
            'starting a session tells the phone, with its lifecycle frame and '
            'the snapshot that follows it (D-91)',
      );

      await watched.appendSensorSample(
        kind: WatchSensorKind.heartRate,
        value: 132,
      );
      expect(watched.sensorSamples, hasLength(1));
      expect(
        emitted,
        hasLength(2),
        reason:
            'a reading adds nothing to the outbound stream: the sync protocol '
            'carries the logged effort, and the distance in it is the reading '
            'that survived',
      );
    });

    test('the pace floor is the one both clients agreed on', () {
      expect(
        WatchSensorPace.minDistanceMeters,
        _contract()['paceMinDistanceMeters'],
        reason:
            'a pace below the floor is noise from a fix that has barely moved, '
            'and the two clients have to hide it at the same distance',
      );
    });
  });

  group('Distance readout', () {
    test(
      'the distance row is measured while GPS is on, dialled otherwise',
      () async {
        final sensors = await sensorsFor();
        final session = await sessionFor(
          Modality.cardioEndurance,
          slot: _slot('sx-run', [
            ExerciseCapability.time,
            ExerciseCapability.distance,
          ]),
        );
        await sensors.start(session);
        await source.fix(2400);

        final state = WatchLoggingState(
          engine: engine,
          clock: clock.call,
          sensors: sensors.recorder,
        );

        expect(
          state.fields
              .firstWhere((field) => field.metricKey == WatchMetricKey.distance)
              .value,
          2400,
        );
        expect(state.liveDistanceLabel, '2.4');
      },
    );

    test('a measured distance outranks the dial', () async {
      final sensors = await sensorsFor();
      await sensors.start(
        await sessionFor(
          Modality.cardioEndurance,
          slot: _slot('sx-run', [
            ExerciseCapability.time,
            ExerciseCapability.distance,
          ]),
        ),
      );
      await source.fix(3200);

      final state = WatchLoggingState(
        engine: engine,
        clock: clock.call,
        sensors: sensors.recorder,
      );
      final distance = state.fields.firstWhere(
        (field) => field.metricKey == WatchMetricKey.distance,
      );

      expect(distance.isMeasured, isTrue);
      state.adjust(WatchMetricKey.distance, 15);
      expect(
        distance.value,
        3200,
        reason: 'a measured row is not a number the user can add to',
      );

      final logged = await state.log();
      expect(
        logged.payload['distanceMeters'],
        3200,
        reason:
            'the phone receives the measured total, not the last thing the '
            'dial was set to',
      );
    });

    test('pace appears only once there is a distance to divide by', () async {
      await sessionFor(Modality.cardioEndurance);
      final state = WatchLoggingState(
        engine: engine,
        clock: clock.call,
        sensors: WatchSensorRecorder(
          engine: engine,
          source: source,
          clock: clock.call,
        ),
      );

      expect(state.paceLabel, isNull);
      await engine.appendSensorSample(kind: WatchSensorKind.gps, value: 500);
      expect(state.paceLabel, isNull, reason: 'no elapsed time has passed yet');

      clock.advance(const Duration(minutes: 5));
      expect(state.paceLabel, '10:00 /km');
    });

    test('the readout follows the saved unit preference', () async {
      await sessionFor(Modality.cardioEndurance);
      await engine.appendSensorSample(
        kind: WatchSensorKind.gps,
        value: 1609.34,
      );
      clock.advance(const Duration(minutes: 8));

      final state = WatchLoggingState(
        engine: engine,
        clock: clock.call,
        units: const WatchUnitPreferences(distanceUnit: 'miles'),
        sensors: WatchSensorRecorder(
          engine: engine,
          source: source,
          clock: clock.call,
        ),
      );

      expect(state.liveDistanceLabel, '1.0');
      expect(state.paceLabel, '8:00 /mi');
      expect(UnitFormatter.metresPerUnit('miles'), closeTo(1609.34, 0.01));
    });
  });
}
