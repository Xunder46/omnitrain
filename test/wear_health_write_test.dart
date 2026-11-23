// A workout the Wear wrist ran reaches Health Connect, written by the phone
// (plan 307).
//
// Plan: `docs/plans/2026-11-22-307-wear-health-connect-write-plan/2026-11-22-307-wear-health-connect-write-plan.md`
//   S-30701 Android: the wrist's end writes the workout; iOS: it does not
//   S-30702 Android: the phone's own end of a wrist-run session writes once
//   S-30703 the default and a phone-only session are unchanged
//   S-30704 the planned-set rule still uses "the wrist ran it"
//   S-30705 the measured energy on the draft (and never an estimate)
//   S-30706 energy that arrives after the write replaces the workout once
//   S-30707 the gateway: whole kilocalories, one retry without them
//   S-30708 the write permission asks for the calories too (Android)
//   S-30709 the manifest and the wiring (source guards)
//
// Plain `test()` over the in-memory repository and a recording platform.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/health_constants.dart';
import 'package:omnitrain/core/constants/modality.dart';
import 'package:omnitrain/core/services/health_platform_gateway_io.dart';
import 'package:omnitrain/core/services/health_platform_service.dart';
import 'package:omnitrain/core/services/health_sync_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

class _Platform implements HealthPlatformService {
  final List<HealthWorkoutDraft> written = [];
  final List<HealthWorkoutDraft> store = [];
  final Set<int> failWriteCalls = {};
  int writeCalls = 0;
  int deletes = 0;

  @override
  Future<bool> writeWorkout(HealthWorkoutDraft workout) async {
    writeCalls++;
    if (failWriteCalls.contains(writeCalls)) return false;
    written.add(workout);
    store.add(workout);
    return true;
  }

  @override
  Future<bool> deleteWorkouts(DateTime start, DateTime end) async {
    deletes++;
    store.removeWhere((w) => !w.start.isBefore(start) && w.start.isBefore(end));
    return true;
  }

  @override
  Future<bool> requestWritePermission() async => true;

  @override
  Future<bool> requestReadPermission() async => true;

  @override
  Future<HealthEffortOutcome> setWorkoutEffort(
    DateTime start,
    DateTime end,
    int score,
  ) async => HealthEffortOutcome.unavailable;

  @override
  Future<bool> clearWorkoutEffort(DateTime start, DateTime end) async => true;

  @override
  Future<List<HealthWeightSample>> readBodyWeightSince(DateTime since) async =>
      const [];
}

class _Rig {
  _Rig._(this.repo, this.platform, this.sync);

  final MockWorkoutRepository repo;
  final _Platform platform;
  final HealthSyncService sync;
  bool writeEnabled = true;

  static Future<_Rig> create() async {
    final repo = MockWorkoutRepository();
    await repo.initialize();
    final platform = _Platform();
    late _Rig rig;
    final sync = HealthSyncService(
      platform: platform,
      repository: repo,
      isWriteEnabled: () => rig.writeEnabled,
      isReadEnabled: () => false,
    );
    rig = _Rig._(repo, platform, sync);
    return rig;
  }

  WorkoutState workout({
    bool Function(String sessionId)? wristRuns,
    bool? wristSavesOwnWorkout,
  }) => WorkoutState(
    repo,
    healthSync: sync,
    wristRunsSession: wristRuns,
    wristSavesOwnWorkout: wristSavesOwnWorkout ?? true,
  );

  Future<void> measured(String id, double kcal) => repo.putSessionEnergy(
    SessionEnergy(
      sessionId: id,
      activeKcal: kcal,
      source: SessionEnergy.sourceMeasured,
      updatedAtMs: 1,
    ),
  );
}

DateTime _at(int minutes) => DateTime(2026, 11, 22, 9, minutes);

TrainingSession _session(String id, {int endMinute = 30}) => TrainingSession(
  id: id,
  ownerUserId: 'u-1',
  startedAtMs: _at(0).millisecondsSinceEpoch,
  endedAtMs: _at(endMinute).millisecondsSinceEpoch,
  modality: Modality.resistanceLifting,
  title: 'Wear day',
  createdAtMs: _at(0).millisecondsSinceEpoch,
  updatedAtMs: _at(endMinute).millisecondsSinceEpoch,
);

void main() {
  group('S-30701 a wrist end on each platform', () {
    test('Android: the wrist\'s completed writes the workout once', () async {
      final rig = await _Rig.create();
      final state = rig.workout(
        wristRuns: (_) => true,
        wristSavesOwnWorkout: false,
      );
      await state.createNewSession(modality: Modality.resistanceLifting);

      await state.endSession(writeToHealth: false);

      expect(rig.platform.written, hasLength(1));
      expect(
        rig.platform.written.single.activityKind,
        HealthActivityKind.strength,
      );
    });

    test(
      'iOS: the Apple watch saved it, so the phone writes nothing',
      () async {
        final rig = await _Rig.create();
        final state = rig.workout(
          wristRuns: (_) => true,
          wristSavesOwnWorkout: true,
        );
        await state.createNewSession(modality: Modality.resistanceLifting);

        await state.endSession(writeToHealth: false);

        expect(rig.platform.written, isEmpty);
      },
    );

    test('Android: the setting off writes nothing', () async {
      final rig = await _Rig.create();
      rig.writeEnabled = false;
      final state = rig.workout(
        wristRuns: (_) => true,
        wristSavesOwnWorkout: false,
      );
      await state.createNewSession(modality: Modality.resistanceLifting);

      await state.endSession(writeToHealth: false);

      expect(rig.platform.written, isEmpty);
    });

    test('Android: the same end twice still writes once', () async {
      final rig = await _Rig.create();
      final state = rig.workout(
        wristRuns: (_) => true,
        wristSavesOwnWorkout: false,
      );
      await state.createNewSession(modality: Modality.resistanceLifting);

      await state.endSession(writeToHealth: false);
      await state.endSession(writeToHealth: false);

      expect(rig.platform.written, hasLength(1));
    });
  });

  group('S-30702 the phone ends a session the wrist is running', () {
    test('Android writes once; iOS writes nothing', () async {
      final android = await _Rig.create();
      final androidState = android.workout(
        wristRuns: (_) => true,
        wristSavesOwnWorkout: false,
      );
      await androidState.createNewSession(modality: Modality.sports);
      await androidState.endSession();
      expect(android.platform.written, hasLength(1));

      final ios = await _Rig.create();
      final iosState = ios.workout(
        wristRuns: (_) => true,
        wristSavesOwnWorkout: true,
      );
      await iosState.createNewSession(modality: Modality.sports);
      await iosState.endSession();
      expect(ios.platform.written, isEmpty);
    });
  });

  group('S-30703 the default and a phone-only session', () {
    test(
      'without the flag the wrist still saves its own (plan 89c1)',
      () async {
        final rig = await _Rig.create();
        final state = rig.workout(wristRuns: (_) => true);
        await state.createNewSession(modality: Modality.sports);

        await state.endSession(writeToHealth: false);
        await state.endSession();

        expect(rig.platform.written, isEmpty);
      },
    );

    test('a session the wrist does not run writes on both platforms', () async {
      for (final saves in [true, false]) {
        final rig = await _Rig.create();
        final state = rig.workout(
          wristRuns: (_) => false,
          wristSavesOwnWorkout: saves,
        );
        await state.createNewSession(modality: Modality.sports);

        await state.endSession();

        expect(rig.platform.written, hasLength(1), reason: 'saves=$saves');
      }
    });
  });

  group('S-30704 the planned-set rule still reads "the wrist ran it"', () {
    Future<int> exercisesLeftAfterEnd({required bool wristSavesOwn}) async {
      final rig = await _Rig.create();
      final state = rig.workout(
        wristRuns: (_) => true,
        wristSavesOwnWorkout: wristSavesOwn,
      );
      await state.createNewSession(modality: Modality.resistanceLifting);
      final exercise = (await rig.repo.getExercises()).firstWhere(
        (e) => e.capabilities.contains('sets'),
      );
      await state.addExerciseToSession(exercise);
      final before = state.currentSession!.id;

      await state.endSession();

      final segments = (await rig.repo.getSegmentsBySession())[before] ?? [];
      var count = 0;
      for (final segment in segments) {
        count += state.getEffortsForSegment(segment.id).length;
      }
      return count;
    }

    test(
      'a wrist-run workout keeps its exercises on either platform',
      () async {
        expect(await exercisesLeftAfterEnd(wristSavesOwn: true), 1);
        expect(
          await exercisesLeftAfterEnd(wristSavesOwn: false),
          1,
          reason: 'Android still counts the wrist as having had a hand in it',
        );
      },
    );
  });

  group('S-30705 the measured energy on the draft', () {
    test('a measured total is written in whole kilocalories', () async {
      final rig = await _Rig.create();
      final session = _session('s1');
      await rig.repo.createSession(session);
      await rig.measured('s1', 312.4);

      await rig.sync.onSessionCompleted(session);

      expect(rig.platform.written.single.energyKcal, 312);
    });

    test('an estimate is never written as if it were measured', () async {
      final rig = await _Rig.create();
      final session = _session('s2');
      await rig.repo.createSession(session);
      await rig.repo.putSessionEnergy(
        SessionEnergy(
          sessionId: 's2',
          activeKcal: 250,
          source: SessionEnergy.sourceEstimated,
          bodyWeightKg: 80,
          updatedAtMs: 1,
        ),
      );

      await rig.sync.onSessionCompleted(session);

      expect(rig.platform.written.single.energyKcal, isNull);
    });

    test('a measured zero is no figure at all', () async {
      final rig = await _Rig.create();
      final session = _session('s-zero');
      await rig.repo.createSession(session);
      await rig.measured('s-zero', 0);

      await rig.sync.onSessionCompleted(session);

      expect(rig.platform.written.single.energyKcal, isNull);
    });

    test('no energy at all writes the workout without any', () async {
      final rig = await _Rig.create();
      final session = _session('s3');
      await rig.repo.createSession(session);

      await rig.sync.onSessionCompleted(session);

      expect(rig.platform.written.single.energyKcal, isNull);
    });
  });

  group('S-30706 energy that arrives after the write', () {
    Future<(_Rig, TrainingSession)> writtenWithout() async {
      final rig = await _Rig.create();
      final session = _session('s-late');
      await rig.repo.createSession(session);
      await rig.sync.onSessionCompleted(session);
      expect(rig.platform.store.single.energyKcal, isNull);
      return (rig, session);
    }

    test('replaces the one workout, once, with the energy', () async {
      final (rig, session) = await writtenWithout();
      await rig.measured('s-late', 312.4);

      await rig.sync.onEnergyAttached(session);

      expect(rig.platform.store, hasLength(1));
      expect(rig.platform.store.single.energyKcal, 312);
      expect(rig.platform.store.single.start, _at(0));
      expect(rig.platform.store.single.end, _at(30));
      expect(rig.platform.store.single.title, 'Wear day');

      final writes = rig.platform.writeCalls;
      await rig.sync.onEnergyAttached(session);
      expect(rig.platform.writeCalls, writes, reason: 'the same energy twice');
    });

    test('a changed energy replaces it again', () async {
      final (rig, session) = await writtenWithout();
      await rig.measured('s-late', 300);
      await rig.sync.onEnergyAttached(session);

      await rig.measured('s-late', 410);
      await rig.sync.onEnergyAttached(session);

      expect(rig.platform.store, hasLength(1));
      expect(rig.platform.store.single.energyKcal, 410);
    });

    test(
      'a session this phone never wrote is left alone (the Apple wrist)',
      () async {
        final rig = await _Rig.create();
        final session = _session('s-apple');
        await rig.repo.createSession(session);
        await rig.measured('s-apple', 312);

        await rig.sync.onEnergyAttached(session);

        expect(rig.platform.writeCalls, 0);
        expect(rig.platform.deletes, 0);
      },
    );

    test('the setting off replaces nothing', () async {
      final (rig, session) = await writtenWithout();
      await rig.measured('s-late', 312);
      rig.writeEnabled = false;

      await rig.sync.onEnergyAttached(session);

      expect(rig.platform.store.single.energyKcal, isNull);
    });

    test('an estimate replaces nothing', () async {
      final (rig, session) = await writtenWithout();
      await rig.repo.putSessionEnergy(
        SessionEnergy(
          sessionId: 's-late',
          activeKcal: 250,
          source: SessionEnergy.sourceEstimated,
          bodyWeightKg: 80,
          updatedAtMs: 1,
        ),
      );

      await rig.sync.onEnergyAttached(session);

      expect(rig.platform.writeCalls, 1);
    });

    test('a failed replacement puts the workout back without energy', () async {
      final (rig, session) = await writtenWithout();
      await rig.measured('s-late', 312);
      // Write 1 was the original; 2 is the replacement (fails); 3 the restore.
      rig.platform.failWriteCalls.add(2);

      await rig.sync.onEnergyAttached(session);

      expect(rig.platform.store, hasLength(1));
      expect(rig.platform.store.single.energyKcal, isNull);
      expect(rig.platform.writeCalls, 3);
    });

    test('a session still running is not touched', () async {
      final (rig, _) = await writtenWithout();
      final running = TrainingSession(
        id: 's-late',
        ownerUserId: 'u-1',
        startedAtMs: _at(0).millisecondsSinceEpoch,
        modality: Modality.resistanceLifting,
        createdAtMs: _at(0).millisecondsSinceEpoch,
        updatedAtMs: _at(0).millisecondsSinceEpoch,
      );
      await rig.measured('s-late', 312);

      await rig.sync.onEnergyAttached(running);

      expect(rig.platform.writeCalls, 1);
    });

    test(
      'a moved end replaces the workout carrying the energy it has',
      () async {
        final (rig, session) = await writtenWithout();
        await rig.measured('s-late', 312);
        await rig.sync.onEnergyAttached(session);

        final moved = TrainingSession.fromMap({
          ...session.toMap(),
          'ended_at_ms': _at(40).millisecondsSinceEpoch,
        });
        await rig.sync.rewriteWorkout(
          moved,
          previousEndedAtMs: session.endedAtMs!,
        );

        expect(rig.platform.store, hasLength(1));
        expect(rig.platform.store.single.end, _at(40));
        expect(rig.platform.store.single.energyKcal, 312);
      },
    );
  });

  group('S-30707 and S-30708 the gateway (source guards)', () {
    final source = File(
      'lib/core/services/health_platform_gateway_io.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    test('whole kilocalories, only a positive finite figure', () {
      expect(source, contains('final energy = workout.energyKcal;'));
      expect(
        source,
        contains(
          'final kcal = energy == null || !energy.isFinite || energy <= 0',
        ),
      );
      expect(source, contains(': energy.round();'));
      expect(source, contains('totalEnergyBurned: kcal,'));
    });

    test('a failed write that carried energy is retried once without', () {
      final start = source.indexOf('Future<bool> writeWorkout(');
      final end = source.indexOf('Future<bool> _writeWorkoutOnce(');
      final body = source.substring(start, end);

      expect(
        body,
        contains('if (await _writeWorkoutOnce(workout, kcal)) return true;'),
      );
      expect(body, contains('return _writeWorkoutOnce(workout, null);'));
      expect(
        body.indexOf('_writeWorkoutOnce(workout, kcal)'),
        lessThan(body.indexOf('_writeWorkoutOnce(workout, null)')),
      );
    });

    test('the write permission asks for the calories too, on Android only', () {
      final start = source.indexOf('Future<bool> requestWritePermission()');
      final end = source.indexOf('Future<bool> requestReadPermission()');
      final body = source.substring(start, end);

      expect(body, contains('HealthDataType.WORKOUT,'));
      expect(
        body,
        contains('if (!_isIOS) HealthDataType.TOTAL_CALORIES_BURNED,'),
      );
      expect(body, contains('], write: true);'));
    });
  });

  group('S-30707 the gateway through the plugin channel', () {
    const plugin = MethodChannel('flutter_health');
    final calls = <MethodCall>[];
    var failFirstWrite = false;
    var writes = 0;

    setUp(() {
      calls.clear();
      writes = 0;
      failFirstWrite = false;
      TestWidgetsFlutterBinding.ensureInitialized();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(plugin, (call) async {
            calls.add(call);
            if (call.method == 'writeWorkoutData') {
              writes++;
              return !(failFirstWrite && writes == 1);
            }
            return true;
          });
    });
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(plugin, null),
    );

    HealthWorkoutDraft draft(double? kcal) => HealthWorkoutDraft(
      activityKind: HealthActivityKind.strength,
      start: DateTime.utc(2026, 11, 22, 9),
      end: DateTime.utc(2026, 11, 22, 9, 30),
      energyKcal: kcal,
    );

    test(
      'Android asks the workout and its calories with one access each',
      () async {
        await HealthPluginPlatformService(
          isIOS: false,
        ).requestWritePermission();

        final ask = calls.singleWhere(
          (c) => c.method == 'requestAuthorization',
        );
        final args = Map<Object?, Object?>.from(ask.arguments as Map);
        expect(args['types'], ['WORKOUT', 'TOTAL_CALORIES_BURNED']);
        expect(args['permissions'], [1, 1], reason: 'WRITE for each type');
      },
    );

    test('iOS asks only the workout', () async {
      await HealthPluginPlatformService(isIOS: true).requestWritePermission();

      final ask = calls.singleWhere((c) => c.method == 'requestAuthorization');
      final args = Map<Object?, Object?>.from(ask.arguments as Map);
      expect(args['types'], ['WORKOUT']);
      expect(args['permissions'], [1]);
    });

    test('a read still asks one read access for its one type', () async {
      await HealthPluginPlatformService(isIOS: false).requestReadPermission();

      final ask = calls.singleWhere((c) => c.method == 'requestAuthorization');
      final args = Map<Object?, Object?>.from(ask.arguments as Map);
      expect(args['types'], ['WEIGHT']);
      expect(args['permissions'], [0]);
    });

    test('the calories travel as whole kilocalories', () async {
      final ok = await HealthPluginPlatformService(
        isIOS: false,
      ).writeWorkout(draft(312.6));

      expect(ok, isTrue);
      final write = calls.singleWhere((c) => c.method == 'writeWorkoutData');
      expect((write.arguments as Map)['totalEnergyBurned'], 313);
    });

    test(
      'a write the platform refuses is retried once without calories',
      () async {
        failFirstWrite = true;

        final ok = await HealthPluginPlatformService(
          isIOS: false,
        ).writeWorkout(draft(312));

        expect(ok, isTrue);
        final sent = [
          for (final c in calls)
            if (c.method == 'writeWorkoutData')
              (c.arguments as Map)['totalEnergyBurned'],
        ];
        expect(sent, [312, null]);
      },
    );

    test('a workout with no energy is one plain write', () async {
      await HealthPluginPlatformService(isIOS: false).writeWorkout(draft(null));

      expect(calls.where((c) => c.method == 'writeWorkoutData'), hasLength(1));
      expect((calls.last.arguments as Map)['totalEnergyBurned'], isNull);
    });
  });

  group('S-30709 the manifest and the wiring (source guards)', () {
    test('the phone manifest declares the calories write', () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();

      expect(
        manifest,
        contains(
          '<uses-permission android:name="android.permission.health.WRITE_TOTAL_CALORIES_BURNED" />',
        ),
      );
    });

    test('the app tells the workout state whether the wrist saves its own', () {
      final main = File('lib/main.dart').readAsStringSync();

      expect(
        main,
        contains(
          'wristSavesOwnWorkout: defaultTargetPlatform != TargetPlatform.android,',
        ),
      );
    });

    test('the inbox hands the health sync a stored wrist summary', () {
      final inbox = File(
        'lib/state/watch/watch_session_inbox.dart',
      ).readAsStringSync().replaceAll('\r\n', '\n');

      expect(
        inbox,
        contains(
          'await _onSensorSummaryAttached?.call(sessionId);\n        await _sendEnergyToHealth(sessionId);',
        ),
      );
      expect(inbox, contains('await healthSync.onEnergyAttached(session);'));
    });
  });
}
