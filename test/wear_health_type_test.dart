// A Wear workout is typed in Health Connect the way the Apple watch types its
// own (plan 308).
//
// Plan: `docs/plans/2026-11-22-308-wear-health-workout-type-plan/2026-11-22-308-wear-health-workout-type-plan.md`
//   S-30801 one rule: the pure function agrees with the wrist's own
//   S-30802 the gateway table covers every name the wrist can produce
//   S-30803 a Free session is typed by its first exercise
//   S-30804 only the first exercise counts for a Free session
//   S-30805 a routine: named kinds by majority, else the modality
//   S-30806 a session the wrist did not run is typed as before
//   S-30807 the late paths keep the type, also after a restart
//
// Plain `test()` over the in-memory repository and a recording platform.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/health_constants.dart';
import 'package:omnitrain/core/constants/modality.dart';
import 'package:omnitrain/core/services/health_platform_gateway_io.dart';
import 'package:omnitrain/core/services/health_platform_service.dart';
import 'package:omnitrain/core/services/health_sync_service.dart';
import 'package:omnitrain/core/utils/watch_reference_sync.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/watch/sensors/watch_platform_workout.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:health/health.dart' show HealthWorkoutActivityType;

class _Platform implements HealthPlatformService {
  final List<HealthWorkoutDraft> store = [];

  @override
  Future<bool> writeWorkout(HealthWorkoutDraft workout) async {
    store.add(workout);
    return true;
  }

  @override
  Future<bool> deleteWorkouts(DateTime start, DateTime end) async {
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

DateTime _at(int minutes) => DateTime(2026, 11, 22, 9, minutes);

class _Rig {
  _Rig(this.repo, this.platform);

  final MockWorkoutRepository repo;
  final _Platform platform;

  HealthSyncService service() => HealthSyncService(
    platform: platform,
    repository: repo,
    isWriteEnabled: () => true,
    isReadEnabled: () => false,
  );

  static Future<_Rig> create() async {
    final repo = MockWorkoutRepository();
    await repo.initialize();
    return _Rig(repo, _Platform());
  }

  /// A finished session [id] with one segment whose efforts are [exerciseIds]
  /// in order.
  Future<TrainingSession> session(
    String id,
    List<String> exerciseIds, {
    String? modality,
  }) async {
    final session = TrainingSession(
      id: id,
      ownerUserId: 'u-1',
      startedAtMs: _at(0).millisecondsSinceEpoch,
      endedAtMs: _at(30).millisecondsSinceEpoch,
      modality: modality,
      title: 'Wear day',
      createdAtMs: _at(0).millisecondsSinceEpoch,
      updatedAtMs: _at(30).millisecondsSinceEpoch,
    );
    await repo.createSession(session);
    await repo.createSegment(
      SessionSegment(
        id: '$id-seg',
        sessionId: id,
        orderIndex: 0,
        segmentType: 'main',
        createdAtMs: 1,
        updatedAtMs: 1,
      ),
    );
    for (var i = 0; i < exerciseIds.length; i++) {
      await repo.createEffort(
        SegmentEffort(
          id: '$id-e$i',
          segmentId: '$id-seg',
          orderIndex: i,
          effortKind: 'set',
          exerciseId: exerciseIds[i],
          createdAtMs: 1,
          updatedAtMs: 1,
        ),
      );
    }
    return session;
  }

  Future<String?> typeOf(
    String id,
    List<String> exerciseIds, {
    String? modality,
    bool wristRan = true,
  }) async {
    final s = await session(id, exerciseIds, modality: modality);
    await service().onSessionCompleted(s, wristRan: wristRan);
    return platform.store.last.activityTypeName;
  }
}

Future<String> _exerciseWhere(
  _Rig rig,
  bool Function(Exercise) test, {
  String? reason,
}) async {
  final rows = await rig.repo.getExercises();
  return rows
      .firstWhere(test, orElse: () => throw StateError(reason ?? 'none'))
      .id;
}

void main() {
  group('S-30801 one rule', () {
    final slots = <String, List<Map<String, Object?>>>{
      'none': const [],
      'a run': [
        {
          'capabilities': ['time', 'distance'],
        },
      ],
      'a lift': [
        {
          'capabilities': ['reps', 'sets', 'load'],
        },
      ],
      'a hold': [
        {
          'capabilities': ['hold', 'time'],
        },
      ],
      'a plank': [
        {
          'capabilities': ['hold', 'sets'],
        },
      ],
      'timed': [
        {
          'capabilities': ['time'],
        },
      ],
      'named cycling x2 + run': [
        {
          'capabilities': ['time'],
          'healthActivity': 'cycling',
        },
        {
          'capabilities': ['time'],
          'healthActivity': 'cycling',
        },
        {
          'capabilities': ['time', 'distance'],
        },
      ],
      'lift, lift, run': [
        {
          'capabilities': ['reps', 'sets', 'load'],
        },
        {
          'capabilities': ['reps', 'sets', 'load'],
        },
        {
          'capabilities': ['time', 'distance'],
        },
      ],
      'tie run, lift': [
        {
          'capabilities': ['time', 'distance'],
        },
        {
          'capabilities': ['reps', 'sets', 'load'],
        },
      ],
      'unknown kind': [
        {
          'capabilities': ['reps'],
          'healthActivity': 'padel',
        },
      ],
    };

    test('agrees with the wrist\'s own session rule for every modality', () {
      for (final modality in <String?>[
        null,
        ...WatchActivityTypes.byModality.keys,
        'not_a_modality',
      ]) {
        for (final entry in slots.entries) {
          final record = WatchSessionRecord(
            recordId: 'r',
            sessionId: 's',
            recordedAt: _at(0),
            startedAt: _at(0),
            modality: modality,
            source: 'watch',
            status: WatchSessionStatus.active,
            currentExerciseIndex: 0,
            exercises: entry.value,
          );

          expect(
            WatchActivityTypes.forModalityAndExercises(modality, entry.value),
            WatchActivityTypes.forSession(record),
            reason: 'modality=$modality slots=${entry.key}',
          );
        }
      }
    });

    test('a Free session with no exercise has no type yet', () {
      expect(
        WatchActivityTypes.forModalityAndExercises(null, const []),
        isNull,
      );
    });
  });

  group('S-30802 the gateway table', () {
    test('every name the wrist can produce is mapped', () {
      final names = <String>{
        for (final t in WatchActivityTypes.byModality.values) t.wear,
        WatchActivityTypes.generic.wear,
        for (final kind in [
          ...WatchReferenceSync.healthActivityByDiscipline.values,
          'hiking',
          'walking',
        ])
          WatchActivityTypes.forExercise(
            capabilities: const [],
            healthActivity: kind,
          ).wear,
      };

      final unmapped = [
        for (final name in names)
          if (!healthConnectTypeByWearName.containsKey(name)) name,
      ];
      expect(unmapped, isEmpty);
    });

    test('the main types map to their namesakes', () {
      expect(
        healthConnectTypeByWearName['exercise_type_running'],
        HealthWorkoutActivityType.RUNNING,
      );
      expect(
        healthConnectTypeByWearName['exercise_type_biking'],
        HealthWorkoutActivityType.BIKING,
      );
      expect(
        healthConnectTypeByWearName['exercise_type_strength_training'],
        HealthWorkoutActivityType.STRENGTH_TRAINING,
      );
      expect(
        healthConnectTypeByWearName['exercise_type_cross_training'],
        HealthWorkoutActivityType.HIGH_INTENSITY_INTERVAL_TRAINING,
      );
      expect(
        healthConnectTypeByWearName['exercise_type_flexibility'],
        HealthWorkoutActivityType.OTHER,
      );
    });

    group('through the plugin channel', () {
      const plugin = MethodChannel('flutter_health');
      final calls = <MethodCall>[];

      setUp(() {
        TestWidgetsFlutterBinding.ensureInitialized();
        calls.clear();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(plugin, (call) async {
              calls.add(call);
              return true;
            });
      });
      tearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(plugin, null),
      );

      HealthWorkoutDraft draft(String? name) => HealthWorkoutDraft(
        activityKind: HealthActivityKind.cardio,
        start: DateTime.utc(2026, 11, 22, 9),
        end: DateTime.utc(2026, 11, 22, 9, 30),
        activityTypeName: name,
      );

      String sent() =>
          (calls.singleWhere((c) => c.method == 'writeWorkoutData').arguments
                  as Map)['activityType']
              as String;

      test('Android writes the wrist\'s type', () async {
        await HealthPluginPlatformService(
          isIOS: false,
        ).writeWorkout(draft('exercise_type_running'));

        expect(sent(), 'RUNNING');
      });

      test('an unmapped name falls back to the kind', () async {
        await HealthPluginPlatformService(
          isIOS: false,
        ).writeWorkout(draft('exercise_type_something_new'));

        expect(sent(), 'OTHER', reason: 'cardio writes as the generic type');
      });

      test('no name is the kind, as before', () async {
        await HealthPluginPlatformService(
          isIOS: false,
        ).writeWorkout(draft(null));

        expect(sent(), 'OTHER');
      });

      test('iOS ignores the name', () async {
        await HealthPluginPlatformService(
          isIOS: true,
        ).writeWorkout(draft('exercise_type_running'));

        expect(sent(), isNot('RUNNING'));
      });
    });
  });

  group('S-30803 a Free session is typed by its first exercise', () {
    test('a run', () async {
      final rig = await _Rig.create();

      expect(
        await rig.typeOf('free-run', ['exercise-easy-run']),
        'exercise_type_running',
      );
    });

    test('a lift', () async {
      final rig = await _Rig.create();
      final lift = await _exerciseWhere(
        rig,
        (e) =>
            WatchReferenceSync.healthActivityOf(
              disciplineId: e.disciplineId,
              exerciseId: e.id,
            ) ==
            'traditionalStrengthTraining',
      );

      expect(
        await rig.typeOf('free-lift', [lift]),
        'exercise_type_strength_training',
      );
    });

    test('an exercise the library no longer holds votes for nothing', () async {
      final rig = await _Rig.create();

      expect(await rig.typeOf('free-gone', ['exercise-deleted']), isNull);
    });
  });

  group('S-30804 only the first exercise counts for a Free session', () {
    test(
      'a run first, then lifts, is a run; lifts first, then a run, is strength',
      () async {
        final rig = await _Rig.create();
        final lift = await _exerciseWhere(
          rig,
          (e) =>
              WatchReferenceSync.healthActivityOf(
                disciplineId: e.disciplineId,
                exerciseId: e.id,
              ) ==
              'traditionalStrengthTraining',
        );

        expect(
          await rig.typeOf('run-first', ['exercise-easy-run', lift, lift]),
          'exercise_type_running',
        );
        expect(
          await rig.typeOf('lift-first', [
            lift,
            'exercise-easy-run',
            'exercise-long-run',
          ]),
          'exercise_type_strength_training',
        );
      },
    );
  });

  group('S-30804 order is the session order, not the store order', () {
    test(
      'efforts are read in the repository order, not the raw index',
      () async {
        final rig = await _Rig.create();
        final lift = await _exerciseWhere(
          rig,
          (e) =>
              WatchReferenceSync.healthActivityOf(
                disciplineId: e.disciplineId,
                exerciseId: e.id,
              ) ==
              'traditionalStrengthTraining',
        );
        final s = await rig.session('ooo', const []);
        // The lift is stored first, carries the lower raw `orderIndex`, but sits
        // SECOND in the session by its top-level position: the session order is
        // the repository's, not the raw index.
        await rig.repo.createEffort(
          SegmentEffort(
            id: 'ooo-lift',
            segmentId: 'ooo-seg',
            orderIndex: 0,
            topLevelOrderIndex: 1,
            effortKind: 'set',
            exerciseId: lift,
            createdAtMs: 1,
            updatedAtMs: 1,
          ),
        );
        await rig.repo.createEffort(
          SegmentEffort(
            id: 'ooo-run',
            segmentId: 'ooo-seg',
            orderIndex: 1,
            topLevelOrderIndex: 0,
            effortKind: 'set',
            exerciseId: 'exercise-easy-run',
            createdAtMs: 1,
            updatedAtMs: 1,
          ),
        );

        await rig.service().onSessionCompleted(s, wristRan: true);

        expect(
          rig.platform.store.single.activityTypeName,
          'exercise_type_running',
        );
      },
    );

    test('segments stored out of order are read in their own order', () async {
      final rig = await _Rig.create();
      final lift = await _exerciseWhere(
        rig,
        (e) =>
            WatchReferenceSync.healthActivityOf(
              disciplineId: e.disciplineId,
              exerciseId: e.id,
            ) ==
            'traditionalStrengthTraining',
      );
      final s = await rig.session('segs', const []);
      // Segment 1 (a lift) is stored before segment 0 (a run).
      for (final (index, exercise) in [(1, lift), (0, 'exercise-easy-run')]) {
        await rig.repo.createSegment(
          SessionSegment(
            id: 'segs-s$index',
            sessionId: 'segs',
            orderIndex: index,
            segmentType: 'main',
            createdAtMs: 1,
            updatedAtMs: 1,
          ),
        );
        await rig.repo.createEffort(
          SegmentEffort(
            id: 'segs-e$index',
            segmentId: 'segs-s$index',
            orderIndex: 0,
            effortKind: 'set',
            exerciseId: exercise,
            createdAtMs: 1,
            updatedAtMs: 1,
          ),
        );
      }

      await rig.service().onSessionCompleted(s, wristRan: true);

      expect(
        rig.platform.store.single.activityTypeName,
        'exercise_type_running',
      );
    });
  });

  group('S-30804 the end of a real session passes the wrist flag', () {
    Future<String?> endedWith({
      required bool Function(String)? wristRuns,
      required bool writeToHealth,
    }) async {
      final rig = await _Rig.create();
      final state = WorkoutState(
        rig.repo,
        healthSync: rig.service(),
        wristRunsSession: wristRuns,
        wristSavesOwnWorkout: false,
      );
      await state.createNewSession();
      final run = (await rig.repo.getExercises()).firstWhere(
        (e) => e.id == 'exercise-easy-run',
      );
      await state.addExerciseToSession(run);

      await state.endSession(writeToHealth: writeToHealth);

      return rig.platform.store.isEmpty
          ? 'nothing written'
          : rig.platform.store.single.activityTypeName;
    }

    test('the wrist end is typed by the wrist rule', () async {
      expect(
        await endedWith(wristRuns: (_) => false, writeToHealth: false),
        'exercise_type_running',
      );
    });

    test('the phone End of a session the wrist runs is typed too', () async {
      expect(
        await endedWith(wristRuns: (_) => true, writeToHealth: true),
        'exercise_type_running',
      );
    });

    test('the phone End of a phone-only session is not', () async {
      expect(
        await endedWith(wristRuns: (_) => false, writeToHealth: true),
        isNull,
      );
    });
  });

  group('S-30805 a routine', () {
    test('the majority of the named kinds wins', () async {
      final rig = await _Rig.create();
      final cycling = await _exerciseWhere(
        rig,
        (e) => e.disciplineId == 'discipline-cycling',
      );

      expect(
        await rig.typeOf('ride', [
          cycling,
          cycling,
          'exercise-easy-run',
        ], modality: Modality.cardioEndurance),
        'exercise_type_biking',
      );
    });

    test('with no kind named the modality decides', () async {
      final rig = await _Rig.create();

      expect(
        await rig.typeOf('sports-day', const [], modality: Modality.sports),
        'exercise_type_other_workout',
      );
      expect(
        await rig.typeOf(
          'cardio-none',
          const [],
          modality: Modality.cardioEndurance,
        ),
        'exercise_type_running',
      );
    });

    test('a routine uses every exercise, not just the first', () async {
      final rig = await _Rig.create();
      final cycling = await _exerciseWhere(
        rig,
        (e) => e.disciplineId == 'discipline-cycling',
      );

      expect(
        await rig.typeOf('run-then-rides', [
          'exercise-easy-run',
          cycling,
          cycling,
        ], modality: Modality.cardioEndurance),
        'exercise_type_biking',
      );
    });
  });

  group('S-30806 a session the wrist did not run', () {
    test('no name, so the phone\'s own typing applies', () async {
      final rig = await _Rig.create();

      expect(
        await rig.typeOf('phone-only', ['exercise-easy-run'], wristRan: false),
        isNull,
      );
      expect(
        rig.platform.store.last.activityKind,
        HealthActivityKind.other,
        reason: 'the modality-less coarse kind, as before',
      );
    });

    test(
      'a watch-origin inbox row marks the session as the wrist\'s',
      () async {
        final rig = await _Rig.create();
        final s = await rig.session('with-row', ['exercise-easy-run']);
        await rig.repo.stageWatchInboxEntry(
          WatchInboxEntry(
            entryId: 'row-1',
            watchSessionId: 'with-row',
            kind: WatchInboxEntry.kindSet,
            origin: WatchInboxEntry.originWatch,
            payload: const {},
            receivedAtMs: 1,
          ),
        );

        // Even the first write, with no flag from the caller, learns it from
        // the inbox.
        await rig.service().onSessionCompleted(s);
        expect(
          rig.platform.store.last.activityTypeName,
          'exercise_type_running',
        );

        // A later path after a restart (no memory) reads it the same way.
        final fresh = rig.service();
        await fresh.rewriteWorkout(
          TrainingSession.fromMap({
            ...s.toMap(),
            'ended_at_ms': _at(40).millisecondsSinceEpoch,
          }),
          previousEndedAtMs: s.endedAtMs!,
        );
        expect(
          rig.platform.store.single.activityTypeName,
          'exercise_type_running',
        );
      },
    );
  });

  group('S-30807 the late paths keep the type', () {
    test(
      'the energy replacement types the workout like the first write',
      () async {
        final rig = await _Rig.create();
        final s = await rig.session('late', ['exercise-easy-run']);
        final service = rig.service();
        await service.onSessionCompleted(s, wristRan: true);
        expect(
          rig.platform.store.single.activityTypeName,
          'exercise_type_running',
        );

        await rig.repo.putSessionEnergy(
          SessionEnergy(
            sessionId: 'late',
            activeKcal: 300,
            source: SessionEnergy.sourceMeasured,
            updatedAtMs: 1,
          ),
        );
        await service.onEnergyAttached(s);

        expect(rig.platform.store, hasLength(1));
        expect(rig.platform.store.single.energyKcal, 300);
        expect(
          rig.platform.store.single.activityTypeName,
          'exercise_type_running',
        );
      },
    );
  });
}
