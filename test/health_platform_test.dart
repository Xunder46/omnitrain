// filepath: test/health_platform_test.dart
//
// Scenario coverage for the platform health integration plan
// (`docs/plans/2026-07-13-04-pr3-platform-health-integration-plan.md`):
//
//   * S-001 / S-002 — a completed session is written to the platform
//     health service exactly once, with the mapped activity kind and the
//     session's wall-clock timing.
//   * S-003 — a disabled write toggle produces no write at all.
//   * S-004 — enabled body-weight read merges samples into the stored
//     measurement history and refreshes the Profile measurement view, which
//     is where body weight is displayed (see the plan's amended S-004).
//   * S-005 — OS permission denial flips the toggle to `denied` and
//     leaves the app fully functional.
//   * S-006 — toggles start off on a wiped (reinstall-equivalent) store.
//   * S-007 — an unmapped modality writes with the generic kind.
//   * S-008 — one platform entry per session, across repeats and restarts.
//   * S-89-4 / S-89-5 (plan 89) — discarding a finished session asks the
//     store to delete exactly its span, never blocking or failing the discard.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/health_constants.dart';
import 'package:omnitrain/core/constants/modality.dart';
import 'package:omnitrain/core/constants/profile_measurements.dart';
import 'package:omnitrain/core/models/app_version_info.dart';
import 'package:omnitrain/core/services/health_platform_service.dart';
import 'package:omnitrain/core/services/health_sync_service.dart';
import 'package:omnitrain/core/utils/unit_formatter.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/settings/settings_screen.dart';
import 'package:omnitrain/main.dart' as app_main;
import 'package:omnitrain/state/profile/profile_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/watch/live_session_mirror_state.dart';
import 'package:omnitrain/state/watch/watch_session_adoption_bridge.dart';
import 'package:omnitrain/state/watch/watch_sync_wiring.dart'
    show watchSessionPlaceholder;
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';
import 'helpers/sync_protocol_harness.dart' show loadProtocolValidator;
import 'helpers/watch_capture_import_harness.dart' show CaptureTransport;

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

/// Test double standing in for the platform gateway (HealthKit /
/// Health Connect). Records every call so the tests can assert call
/// counts and payloads without touching a native plugin.
class _FakeHealthPlatform implements HealthPlatformService {
  bool writeGranted = true;
  bool readGranted = true;
  bool writeSucceeds = true;
  bool throwOnWrite = false;

  int writePermissionRequests = 0;
  int readPermissionRequests = 0;
  int readQueries = 0;
  DateTime? lastReadSince;

  final List<HealthWorkoutDraft> writtenWorkouts = [];
  List<HealthWeightSample> weightSamples = const [];

  /// Plan 89: what the store still holds, and every delete window asked for.
  final List<HealthWorkoutDraft> store = [];
  final List<(DateTime, DateTime)> deleteRequests = [];
  bool deleteSucceeds = true;
  bool throwOnDelete = false;

  /// Held open to prove a discard never waits on the platform.
  Completer<bool>? pendingDelete;

  @override
  Future<bool> deleteWorkouts(DateTime start, DateTime end) {
    deleteRequests.add((start, end));
    if (throwOnDelete) throw Exception('platform delete exploded');
    if (pendingDelete != null) return pendingDelete!.future;
    if (!deleteSucceeds) return Future.value(false);
    // The health plugin's iOS rule, read from its source (plan 89 D-5):
    // `.strictStartDate` - a workout goes when it starts in [start, end).
    store.removeWhere((w) => !w.start.isBefore(start) && w.start.isBefore(end));
    return Future.value(true);
  }

  @override
  Future<bool> requestWritePermission() async {
    writePermissionRequests++;
    return writeGranted;
  }

  @override
  Future<bool> requestReadPermission() async {
    readPermissionRequests++;
    return readGranted;
  }

  @override
  Future<bool> writeWorkout(HealthWorkoutDraft workout) async {
    if (throwOnWrite) {
      throw Exception('platform write exploded');
    }
    if (!writeSucceeds) return false;
    writtenWorkouts.add(workout);
    store.add(workout);
    return true;
  }

  @override
  Future<List<HealthWeightSample>> readBodyWeightSince(DateTime since) async {
    readQueries++;
    lastReadSince = since;
    return weightSamples;
  }
}

/// One wired app fragment: repository + settings + sync service +
/// workout state, all sharing the same fake platform. Mirrors how
/// `main.dart` assembles the production graph.
class _Rig {
  final MockWorkoutRepository repo;
  final SettingsState settings;
  final ProfileState profile;
  final _FakeHealthPlatform platform;
  final HealthSyncService sync;
  final WorkoutState workoutState;

  _Rig._({
    required this.repo,
    required this.settings,
    required this.profile,
    required this.platform,
    required this.sync,
    required this.workoutState,
  });

  static Future<_Rig> create({
    bool writeEnabled = false,
    bool readEnabled = false,
    bool Function(String sessionId)? wristRunsSession,
  }) async {
    final repo = await _freshRepo();
    final platform = _FakeHealthPlatform();
    final settings = SettingsState(
      repo,
      fakePreferencesService(),
      healthPlatform: platform,
    );
    await settings.initialize();
    if (writeEnabled) {
      await settings.setHealthWriteWorkoutsEnabled(true);
    }
    if (readEnabled) {
      await settings.setHealthReadBodyWeightEnabled(true);
    }
    final profile = ProfileState(repo);
    final sync = HealthSyncService(
      platform: platform,
      repository: repo,
      isWriteEnabled: () =>
          settings.healthWriteWorkouts == HealthToggleState.on,
      isReadEnabled: () =>
          settings.healthReadBodyWeight == HealthToggleState.on,
    );
    final workoutState = WorkoutState(
      repo,
      healthSync: sync,
      wristRunsSession: wristRunsSession,
    );
    return _Rig._(
      repo: repo,
      settings: settings,
      profile: profile,
      platform: platform,
      sync: sync,
      workoutState: workoutState,
    );
  }

  /// The production foreground path: run the read pipeline, then refresh the
  /// Profile measurement view with whatever it imported.
  Future<void> importBodyWeight() =>
      app_main.syncHealthBodyWeight(sync, profile);
}

void main() {
  group('write path', () {
    test('writes exactly one workout per completed session (S-001)', () async {
      final rig = await _Rig.create(writeEnabled: true);

      await rig.workoutState.createNewSession(
        modality: Modality.resistanceLifting,
        title: 'Heavy day',
      );
      await rig.workoutState.endSession();

      final session = rig.workoutState.currentSession!;
      expect(session.endedAtMs, isNotNull);
      expect(rig.platform.writtenWorkouts, hasLength(1));

      final draft = rig.platform.writtenWorkouts.single;
      expect(draft.activityKind, HealthActivityKind.strength);
      expect(draft.start.millisecondsSinceEpoch, session.startedAtMs);
      expect(draft.end.millisecondsSinceEpoch, session.endedAtMs);
      expect(draft.title, 'Heavy day');
    });

    test(
      'maps each effort-kind family to its activity kind on write',
      () async {
        const expectations = <String, HealthActivityKind>{
          Modality.resistanceLifting: HealthActivityKind.strength,
          Modality.cardioEndurance: HealthActivityKind.cardio,
          Modality.isometricStretching: HealthActivityKind.flexibility,
          Modality.sports: HealthActivityKind.sport,
        };

        for (final entry in expectations.entries) {
          final rig = await _Rig.create(writeEnabled: true);
          await rig.workoutState.createNewSession(modality: entry.key);
          await rig.workoutState.endSession();

          expect(
            rig.platform.writtenWorkouts.single.activityKind,
            entry.value,
            reason: 'modality "${entry.key}"',
          );
        }
      },
    );

    test('disabled write produces no entry and never touches the '
        'platform (S-003)', () async {
      final rig = await _Rig.create();

      await rig.workoutState.createNewSession(modality: Modality.sports);
      await rig.workoutState.endSession();

      expect(rig.workoutState.currentSession!.endedAtMs, isNotNull);
      expect(rig.platform.writtenWorkouts, isEmpty);
      expect(rig.platform.writePermissionRequests, 0);
    });

    test('repeated completion writes once and only once (S-008)', () async {
      final rig = await _Rig.create(writeEnabled: true);

      await rig.workoutState.createNewSession(modality: Modality.sports);
      await rig.workoutState.endSession();
      await rig.workoutState.endSession();

      expect(rig.platform.writtenWorkouts, hasLength(1));
    });

    test(
      'a restart does not re-write an already synced session (S-008)',
      () async {
        final rig = await _Rig.create(writeEnabled: true);
        await rig.workoutState.createNewSession(modality: Modality.sports);
        await rig.workoutState.endSession();
        final sessionId = rig.workoutState.currentSession!.id;
        expect(rig.platform.writtenWorkouts, hasLength(1));

        // Simulate a fresh launch over the same persisted store: brand-new
        // settings / sync service instances, same repository.
        final restartedSettings = SettingsState(
          rig.repo,
          fakePreferencesService(),
        );
        await restartedSettings.initialize();
        expect(restartedSettings.healthWriteWorkouts, HealthToggleState.on);

        final restartedPlatform = _FakeHealthPlatform();
        final restartedSync = HealthSyncService(
          platform: restartedPlatform,
          repository: rig.repo,
          isWriteEnabled: () =>
              restartedSettings.healthWriteWorkouts == HealthToggleState.on,
          isReadEnabled: () =>
              restartedSettings.healthReadBodyWeight == HealthToggleState.on,
        );

        final persisted = await rig.repo.getSession(sessionId);
        expect(persisted, isNotNull);
        await restartedSync.onSessionCompleted(persisted!);

        expect(restartedPlatform.writtenWorkouts, isEmpty);
      },
    );

    test('unmapped modality writes with the generic kind (S-007)', () async {
      final rig = await _Rig.create(writeEnabled: true);

      await rig.workoutState.createNewSession(modality: 'quantum_flexing');
      await rig.workoutState.endSession();

      expect(
        rig.platform.writtenWorkouts.single.activityKind,
        HealthActivityKind.other,
      );
    });

    test('the session is never left un-ended by a platform failure', () async {
      final rig = await _Rig.create(writeEnabled: true);
      rig.platform.throwOnWrite = true;

      await rig.workoutState.createNewSession(modality: Modality.sports);
      await rig.workoutState.endSession();

      expect(rig.workoutState.currentSession!.endedAtMs, isNotNull);
      expect(rig.workoutState.error, isNull);
      expect(rig.platform.writtenWorkouts, isEmpty);

      final persisted = await rig.repo.getSession(
        rig.workoutState.currentSession!.id,
      );
      expect(persisted!.endedAtMs, isNotNull);
    });

    test('an unsaved (open) session is never written', () async {
      final rig = await _Rig.create(writeEnabled: true);

      final openSession = TrainingSession(
        id: 'open-session',
        ownerUserId: 'user-1',
        startedAtMs: 1000,
        createdAtMs: 1000,
        updatedAtMs: 1000,
      );
      await rig.sync.onSessionCompleted(openSession);

      expect(rig.platform.writtenWorkouts, isEmpty);
    });

    test('disabling write stops future writes but keeps already '
        'written sessions', () async {
      final rig = await _Rig.create(writeEnabled: true);

      await rig.workoutState.createNewSession(modality: Modality.sports);
      await rig.workoutState.endSession();
      expect(rig.platform.writtenWorkouts, hasLength(1));

      await rig.settings.setHealthWriteWorkoutsEnabled(false);

      await Future<void>.delayed(const Duration(milliseconds: 2));
      await rig.workoutState.createNewSession(modality: Modality.sports);
      await rig.workoutState.endSession();

      expect(rig.platform.writtenWorkouts, hasLength(1));
    });
  });

  group('plan 89: deleting a session removes its workout', () {
    final day = DateTime(2026, 10, 28);
    int at(int hour, int minute) =>
        day.add(Duration(hours: hour, minutes: minute)).millisecondsSinceEpoch;

    /// Saves a finished session row; [written] also runs the real write-back
    /// so the store and the ledger hold it.
    Future<TrainingSession> finished(
      _Rig rig,
      String id,
      int startMs,
      int endMs, {
      bool written = true,
      bool isRolling = false,
    }) async {
      final row = TrainingSession(
        id: id,
        ownerUserId: 'user-1',
        startedAtMs: startMs,
        endedAtMs: endMs,
        modality: Modality.resistanceLifting,
        isRolling: isRolling,
        createdAtMs: startMs,
        updatedAtMs: endMs,
      );
      await rig.repo.createSession(row);
      if (written) await rig.sync.onSessionCompleted(row);
      return row;
    }

    /// The Session Summary path: open the session, then discard it.
    Future<void> discard(_Rig rig, String id) async {
      await rig.workoutState.loadHistoricalSession(id);
      expect(rig.workoutState.currentSession?.id, id);
      await rig.workoutState.discardCurrentSession();
      await pumpEventQueue();
    }

    Future<List<String>> ledger(_Rig rig) async {
      final raw = await rig.repo.getPreferenceString(
        HealthPrefs.writtenSessionIdsKey,
        defaultValue: '[]',
      );
      return (jsonDecode(raw ?? '[]') as List).cast<String>();
    }

    Future<void> expectDiscarded(_Rig rig, String id) async {
      expect(rig.workoutState.currentSession, isNull);
      expect(rig.workoutState.error, isNull);
      expect(await rig.repo.getSession(id), isNull);
    }

    (DateTime, DateTime) span(TrainingSession s) => (
      DateTime.fromMillisecondsSinceEpoch(s.startedAtMs),
      DateTime.fromMillisecondsSinceEpoch(s.endedAtMs!),
    );

    test('S-89-4 a written session asks the store to delete its span once '
        'and leaves the ledger', () async {
      final rig = await _Rig.create(writeEnabled: true);
      final a = await finished(rig, 'a', at(10, 0), at(10, 45));
      expect(await ledger(rig), contains('a'));

      await discard(rig, 'a');

      await expectDiscarded(rig, 'a');
      expect(rig.platform.deleteRequests, [span(a)]);
      expect(rig.platform.store, isEmpty);
      expect(await ledger(rig), isNot(contains('a')));
    });

    test('S-89-4 a session the phone never wrote still asks the store '
        '(a watch-saved workout has no ledger entry)', () async {
      final rig = await _Rig.create(writeEnabled: true);
      final w = await finished(rig, 'w', at(9, 0), at(9, 30), written: false);

      await discard(rig, 'w');

      await expectDiscarded(rig, 'w');
      expect(rig.platform.deleteRequests, [span(w)]);
    });

    test('S-89-4 a store that refuses leaves the discard successful', () async {
      final rig = await _Rig.create(writeEnabled: true);
      final a = await finished(rig, 'a', at(10, 0), at(10, 45));
      rig.platform.deleteSucceeds = false;

      await discard(rig, 'a');

      await expectDiscarded(rig, 'a');
      expect(rig.platform.deleteRequests, [span(a)]);
    });

    test('S-89-4 a store that throws leaves the discard successful', () async {
      final rig = await _Rig.create(writeEnabled: true);
      final a = await finished(rig, 'a', at(10, 0), at(10, 45));
      rig.platform.throwOnDelete = true;

      await discard(rig, 'a');

      await expectDiscarded(rig, 'a');
      expect(rig.platform.deleteRequests, [span(a)]);
    });

    test('S-89-4 the discard does not wait for the store', () async {
      final rig = await _Rig.create(writeEnabled: true);
      await finished(rig, 'a', at(10, 0), at(10, 45));
      rig.platform.pendingDelete = Completer<bool>();
      await rig.workoutState.loadHistoricalSession('a');

      var discardDone = false;
      unawaited(
        rig.workoutState.discardCurrentSession().then(
          (_) => discardDone = true,
        ),
      );
      await pumpEventQueue();

      expect(rig.platform.deleteRequests, hasLength(1));
      expect(discardDone, isTrue, reason: 'store still pending');
      await expectDiscarded(rig, 'a');
      rig.platform.pendingDelete!.complete(true);
    });

    test('S-89-4 with Write workouts off nothing reaches the store', () async {
      final rig = await _Rig.create(writeEnabled: true);
      await finished(rig, 'a', at(10, 0), at(10, 45));
      await rig.settings.setHealthWriteWorkoutsEnabled(false);

      await discard(rig, 'a');

      await expectDiscarded(rig, 'a');
      expect(rig.platform.deleteRequests, isEmpty);
      expect(rig.platform.store, hasLength(1));
    });

    test('S-89-5 deleting B of back-to-back A and B asks for exactly B and '
        'keeps A', () async {
      final rig = await _Rig.create(writeEnabled: true);
      final a = await finished(rig, 'a', at(10, 0), at(10, 45));
      await finished(rig, 'b', at(10, 45), at(11, 30));
      expect(rig.platform.store, hasLength(2));

      await discard(rig, 'b');

      expect(rig.platform.deleteRequests, [
        (DateTime(2026, 10, 28, 10, 45), DateTime(2026, 10, 28, 11, 30)),
      ]);
      expect(rig.platform.store.map((w) => w.start), [span(a).$1]);
      expect(await ledger(rig), ['a']);
    });

    test('S-89-5 deleting A of back-to-back A and B keeps B', () async {
      final rig = await _Rig.create(writeEnabled: true);
      await finished(rig, 'a', at(10, 0), at(10, 45));
      final b = await finished(rig, 'b', at(10, 45), at(11, 30));

      await discard(rig, 'a');

      expect(rig.platform.store.map((w) => w.start), [span(b).$1]);
      expect(rig.platform.deleteRequests, [
        (DateTime(2026, 10, 28, 10, 0), DateTime(2026, 10, 28, 10, 45)),
      ]);
    });

    test('S-89-5 a rolling session spanning a day is passed its own span '
        'only', () async {
      final rig = await _Rig.create(writeEnabled: true);
      final before = await finished(rig, 'before', at(6, 0), at(7, 0));
      final rolling = await finished(
        rig,
        'rolling',
        at(8, 0),
        at(32, 0),
        isRolling: true,
      );
      final after = await finished(rig, 'after', at(32, 0), at(33, 0));

      await discard(rig, 'rolling');

      expect(rig.platform.deleteRequests, [span(rolling)]);
      expect(rig.platform.store.map((w) => w.start), [
        span(before).$1,
        span(after).$1,
      ]);
    });

    test('D-4 discarding a session still in progress asks nothing of the '
        'store (the phone never wrote it)', () async {
      final rig = await _Rig.create(writeEnabled: true);
      await rig.workoutState.createNewSession(modality: Modality.sports);
      final id = rig.workoutState.currentSession!.id;

      await rig.workoutState.discardCurrentSession();
      await pumpEventQueue();

      await expectDiscarded(rig, id);
      expect(rig.platform.deleteRequests, isEmpty);
    });

    test('D-4 the no-op gateway reports the delete as not done', () async {
      const gateway = UnavailableHealthPlatformService();
      expect(await gateway.deleteWorkouts(day, day), isFalse);
    });
  });

  group('plan 89c1: one Fitness workout per session', () {
    Future<List<String>> ledger(_Rig rig) async {
      final raw = await rig.repo.getPreferenceString(
        HealthPrefs.writtenSessionIdsKey,
        defaultValue: '[]',
      );
      return (jsonDecode(raw ?? '[]') as List).cast<String>();
    }

    /// One ladder slot as the wrist sends it.
    Map<String, Object?> slot(Exercise exercise) => <String, Object?>{
      'sessionExerciseId': 'sl-${exercise.id}',
      'exerciseId': exercise.id,
      'name': exercise.name,
      'capabilities': const ['time', 'distance'],
    };

    /// The wrist's session as the mirror converged it.
    Map<String, Object?> wristState(
      String sessionId, {
      List<Map<String, Object?>> exercises = const [],
      String status = WatchSessionStatus.active,
    }) => <String, Object?>{
      'sessionId': sessionId,
      'status': status,
      'revision': 1,
      'currentExerciseIndex': 0,
      'exercises': [...exercises],
      'entries': <Object?>[],
      'timers': <String, Object?>{},
    };

    /// A wrist frame of [type] about [sessionId].
    Map<String, Object?> wristFrame(
      String type,
      String sessionId,
      Map<String, Object?> payload, {
      String messageId = 'msg-1',
    }) => <String, Object?>{
      'protocolVersion': SyncProtocolValidator.protocolVersion,
      'messageId': messageId,
      'sessionId': sessionId,
      'type': type,
      'origin': 'watch',
      'sentAt': '2026-10-28T10:30:00.000Z',
      'payload': payload,
    };

    Map<String, Object?> wristEnd(String sessionId, String state) =>
        wristFrame('session_lifecycle', sessionId, <String, Object?>{
          'state': state,
          'at': '2026-10-28T10:30:00.000Z',
        });

    /// A Free session started on the wrist, adopted by the phone through the
    /// real bridge: the shape the owner's outdoor walk had.
    Future<WatchSessionAdoptionBridge> adoptWristSession(
      _Rig rig,
      String sessionId,
    ) async {
      final bridge = WatchSessionAdoptionBridge(repository: rig.repo)
        ..bindWorkoutState(rig.workoutState);
      final exercise = (await rig.repo.getExercises()).first;
      final outcome = await bridge.consider(
        wristState(sessionId, exercises: [slot(exercise)]),
      );
      expect(outcome, WatchSessionAdoption.adopted, reason: 'fixture adopts');
      expect(rig.workoutState.currentSession?.id, sessionId);
      expect(rig.workoutState.currentSession?.endedAtMs, isNull);
      return bridge;
    }

    test('S-89c1-1 the wrist\'s completed ends the held session and writes '
        'no workout from the phone', () async {
      final rig = await _Rig.create(writeEnabled: true);
      final bridge = await adoptWristSession(rig, 'w-walk');

      await bridge.onLifecycle(
        wristEnd('w-walk', WatchLifecycleState.completed),
      );
      await pumpEventQueue();

      expect((await rig.repo.getSession('w-walk'))?.endedAtMs, isNotNull);
      expect(rig.workoutState.currentSession?.endedAtMs, isNotNull);
      expect(rig.workoutState.error, isNull);
      expect(rig.platform.writtenWorkouts, isEmpty);
      expect(await ledger(rig), isNot(contains('w-walk')));
    });

    test('S-89c1-2 the wrist\'s abandoned still discards the session and '
        'writes nothing', () async {
      final rig = await _Rig.create(writeEnabled: true);
      final bridge = await adoptWristSession(rig, 'w-walk');

      await bridge.onLifecycle(
        wristEnd('w-walk', WatchLifecycleState.abandoned),
      );
      await pumpEventQueue();

      expect(await rig.repo.getSession('w-walk'), isNull);
      expect(rig.workoutState.currentSession, isNull);
      expect(rig.platform.writtenWorkouts, isEmpty);
      expect(await ledger(rig), isEmpty);
    });

    test('S-89c1-3 a phone-only session ended by the phone writes exactly one '
        'workout', () async {
      final rig = await _Rig.create(writeEnabled: true);
      await rig.workoutState.createNewSession(
        modality: Modality.cardioEndurance,
      );
      final id = rig.workoutState.currentSession!.id;

      await rig.workoutState.endSession();

      expect(rig.workoutState.currentSession!.endedAtMs, isNotNull);
      expect(rig.platform.writtenWorkouts, hasLength(1));
      expect(await ledger(rig), [id]);
    });

    test('S-89c1-3 with Write workouts off a phone-only session writes '
        'none', () async {
      final rig = await _Rig.create();
      await rig.workoutState.createNewSession(
        modality: Modality.cardioEndurance,
      );

      await rig.workoutState.endSession();

      expect(rig.workoutState.currentSession!.endedAtMs, isNotNull);
      expect(rig.platform.writtenWorkouts, isEmpty);
    });

    group('S-89c1-4 the phone ends a session the wrist is running', () {
      /// The phone's mirror, wired into the phone's state the way `main.dart`
      /// wires it, then told by the wrist what it holds.
      Future<(_Rig, LiveSessionMirrorState)> phoneWithMirror() async {
        final mirror = LiveSessionMirrorState(
          transport: CaptureTransport(),
          snapshot: watchSessionPlaceholder,
          validator: loadProtocolValidator(),
        );
        final rig = await _Rig.create(
          writeEnabled: true,
          wristRunsSession: mirror.wristRunsSession,
        );
        await rig.workoutState.createNewSession(
          modality: Modality.cardioEndurance,
        );
        return (rig, mirror);
      }

      Future<void> wristReports(
        LiveSessionMirrorState mirror,
        Map<String, Object?> state,
      ) async {
        final outcome = await mirror.receive(
          wristFrame(
            'session_snapshot',
            state['sessionId']! as String,
            state,
            messageId: 'msg-snap-${state['sessionId']}',
          ),
        );
        expect(outcome, MirrorOutcome.applied, reason: 'fixture applies');
      }

      Future<Map<String, Object?>> walkSlot(_Rig rig) async =>
          slot((await rig.repo.getExercises()).first);

      test('the wrist holds the same session active: no workout', () async {
        final (rig, mirror) = await phoneWithMirror();
        final id = rig.workoutState.currentSession!.id;
        await wristReports(
          mirror,
          wristState(id, exercises: [await walkSlot(rig)]),
        );

        await rig.workoutState.endSession();

        expect(rig.workoutState.currentSession!.endedAtMs, isNotNull);
        expect(rig.platform.writtenWorkouts, isEmpty);
        expect(await ledger(rig), isNot(contains(id)));
      });

      test('the wrist holds a different session X while the phone ends Y: '
          'Y writes one workout', () async {
        final (rig, mirror) = await phoneWithMirror();
        final id = rig.workoutState.currentSession!.id;
        await wristReports(
          mirror,
          wristState('w-other', exercises: [await walkSlot(rig)]),
        );

        await rig.workoutState.endSession();

        expect(rig.platform.writtenWorkouts, hasLength(1));
        expect(await ledger(rig), [id]);
      });

      test('the wrist holds no session: one workout', () async {
        final (rig, _) = await phoneWithMirror();

        await rig.workoutState.endSession();

        expect(rig.platform.writtenWorkouts, hasLength(1));
      });

      test('the wrist holds the same session but no longer active: one '
          'workout', () async {
        final (rig, mirror) = await phoneWithMirror();
        final id = rig.workoutState.currentSession!.id;
        await wristReports(
          mirror,
          wristState(
            id,
            exercises: [await walkSlot(rig)],
            status: WatchSessionStatus.abandoned,
          ),
        );

        await rig.workoutState.endSession();

        expect(rig.platform.writtenWorkouts, hasLength(1));
      });

      test('the wrist holds the same session with no exercise yet (it has no '
          'workout open): one workout', () async {
        final (rig, mirror) = await phoneWithMirror();
        final id = rig.workoutState.currentSession!.id;
        await wristReports(mirror, wristState(id));

        await rig.workoutState.endSession();

        expect(rig.platform.writtenWorkouts, hasLength(1));
      });
    });

    test('S-89c1-5 the wrist\'s completed arriving twice ends once and writes '
        'nothing', () async {
      final rig = await _Rig.create(writeEnabled: true);
      final bridge = await adoptWristSession(rig, 'w-walk');

      await bridge.onLifecycle(
        wristEnd('w-walk', WatchLifecycleState.completed),
      );
      final endedAtMs = (await rig.repo.getSession('w-walk'))!.endedAtMs;
      expect(endedAtMs, isNotNull);
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await bridge.onLifecycle(
        wristEnd('w-walk', WatchLifecycleState.completed),
      );
      await pumpEventQueue();

      expect((await rig.repo.getSession('w-walk'))!.endedAtMs, endedAtMs);
      expect(rig.platform.writtenWorkouts, isEmpty);
    });

    test('S-89c1-5 the wrist\'s completed after the phone already ended the '
        'session ends nothing and writes nothing more', () async {
      final rig = await _Rig.create(writeEnabled: true);
      final bridge = await adoptWristSession(rig, 'w-walk');
      await rig.workoutState.endSession();
      final endedAtMs = (await rig.repo.getSession('w-walk'))!.endedAtMs;
      final writesAfterPhoneEnd = rig.platform.writtenWorkouts.length;

      await Future<void>.delayed(const Duration(milliseconds: 2));
      await bridge.onLifecycle(
        wristEnd('w-walk', WatchLifecycleState.completed),
      );
      await pumpEventQueue();

      expect((await rig.repo.getSession('w-walk'))!.endedAtMs, endedAtMs);
      expect(rig.platform.writtenWorkouts, hasLength(writesAfterPhoneEnd));
    });
  });

  group('toggles and permissions', () {
    test(
      'enabling write with granted permission persists the on state',
      () async {
        final rig = await _Rig.create();

        await rig.settings.setHealthWriteWorkoutsEnabled(true);

        expect(rig.settings.healthWriteWorkouts, HealthToggleState.on);
        expect(rig.platform.writePermissionRequests, 1);
        expect(
          await rig.repo.getPreferenceString(HealthPrefs.writeWorkoutsKey),
          'on',
        );
      },
    );

    test('denied permission flips the toggle to denied without throwing '
        '(S-005)', () async {
      final rig = await _Rig.create();
      rig.platform.writeGranted = false;

      await rig.settings.setHealthWriteWorkoutsEnabled(true);

      expect(
        rig.settings.healthWriteWorkouts,
        HealthToggleState.permissionDenied,
      );
      expect(
        await rig.repo.getPreferenceString(HealthPrefs.writeWorkoutsKey),
        'denied',
      );
      // App stays functional: sessions still complete normally.
      await rig.workoutState.createNewSession(modality: Modality.sports);
      await rig.workoutState.endSession();
      expect(rig.workoutState.error, isNull);
    });

    test('re-enabling after denial prompts the OS again (S-005)', () async {
      final rig = await _Rig.create();
      rig.platform.writeGranted = false;
      await rig.settings.setHealthWriteWorkoutsEnabled(true);
      expect(
        rig.settings.healthWriteWorkouts,
        HealthToggleState.permissionDenied,
      );

      rig.platform.writeGranted = true;
      await rig.settings.setHealthWriteWorkoutsEnabled(true);

      expect(rig.settings.healthWriteWorkouts, HealthToggleState.on);
      expect(rig.platform.writePermissionRequests, 2);
    });

    test('write and read toggles stay independent', () async {
      final rig = await _Rig.create();
      await rig.settings.setHealthWriteWorkoutsEnabled(true);

      rig.platform.readGranted = false;
      await rig.settings.setHealthReadBodyWeightEnabled(true);

      expect(rig.settings.healthWriteWorkouts, HealthToggleState.on);
      expect(
        rig.settings.healthReadBodyWeight,
        HealthToggleState.permissionDenied,
      );
    });

    test('a wiped store starts with both toggles off (S-006)', () async {
      // Reinstall-equivalent: new repository, new settings instance.
      final rig = await _Rig.create();
      await rig.settings.setHealthWriteWorkoutsEnabled(true);
      await rig.settings.setHealthReadBodyWeightEnabled(true);

      final reinstalledRepo = await _freshRepo();
      final reinstalled = SettingsState(
        reinstalledRepo,
        fakePreferencesService(),
      );
      await reinstalled.initialize();

      expect(reinstalled.healthWriteWorkouts, HealthToggleState.off);
      expect(reinstalled.healthReadBodyWeight, HealthToggleState.off);
    });
  });

  group('read path', () {
    test('imports body weight samples into the measurement history '
        '(S-004)', () async {
      final rig = await _Rig.create(readEnabled: true);
      final now = DateTime.now();
      rig.platform.weightSamples = [
        HealthWeightSample(
          sourceId: 'sample-a',
          sampledAt: now.subtract(const Duration(days: 2)),
          kilograms: 81.5,
        ),
        HealthWeightSample(
          sourceId: 'sample-b',
          sampledAt: now.subtract(const Duration(days: 5)),
          kilograms: 82.0,
        ),
      ];

      await rig.importBodyWeight();

      final history = await rig.repo.getMeasurementHistory(
        ProfileMeasurements.bodyweight.type,
      );
      expect(history, hasLength(2));
      expect(history.first.value, 81.5);
      expect(history.first.unitId, ProfileMeasurements.bodyweight.unitId);
      expect(
        history.first.measurementType,
        ProfileMeasurements.bodyweight.type,
      );
      expect(rig.profile.latestBodyWeightKg, 81.5);
    });

    test(
      'queries the platform with the 90-day lookback window (S-004)',
      () async {
        final rig = await _Rig.create(readEnabled: true);
        final before = DateTime.now().subtract(
          Duration(days: HealthPrefs.bodyWeightLookbackDays),
        );

        await rig.sync.syncOnForeground();

        final since = rig.platform.lastReadSince!;
        expect(
          since.difference(before).abs() < const Duration(minutes: 1),
          isTrue,
        );
      },
    );

    test('successive foreground cycles do not duplicate samples', () async {
      final rig = await _Rig.create(readEnabled: true);
      rig.platform.weightSamples = [
        HealthWeightSample(
          sourceId: 'sample-a',
          sampledAt: DateTime.now().subtract(const Duration(days: 1)),
          kilograms: 80.0,
        ),
      ];

      await rig.sync.syncOnForeground();
      await rig.sync.syncOnForeground();

      final history = await rig.repo.getMeasurementHistory(
        ProfileMeasurements.bodyweight.type,
      );
      expect(history, hasLength(1));
      expect(rig.platform.readQueries, 2);
    });

    test('disabled and denied read never query the platform', () async {
      final disabled = await _Rig.create();
      await disabled.sync.syncOnForeground();
      expect(disabled.platform.readQueries, 0);

      final denied = await _Rig.create();
      denied.platform.readGranted = false;
      await denied.settings.setHealthReadBodyWeightEnabled(true);
      await denied.sync.syncOnForeground();
      expect(denied.platform.readQueries, 0);
      expect(
        await denied.repo.getMeasurementHistory(
          ProfileMeasurements.bodyweight.type,
        ),
        isEmpty,
      );
    });

    test('a platform read failure leaves stored data untouched', () async {
      final rig = await _Rig.create(readEnabled: true);
      rig.platform.weightSamples = [
        HealthWeightSample(
          sourceId: 'sample-a',
          sampledAt: DateTime.now(),
          kilograms: 80.0,
        ),
      ];
      final brokenPlatform = _ThrowingReadPlatform();
      final sync = HealthSyncService(
        platform: brokenPlatform,
        repository: rig.repo,
        isWriteEnabled: () =>
            rig.settings.healthWriteWorkouts == HealthToggleState.on,
        isReadEnabled: () =>
            rig.settings.healthReadBodyWeight == HealthToggleState.on,
      );

      await sync.syncOnForeground();

      expect(
        await rig.repo.getMeasurementHistory(
          ProfileMeasurements.bodyweight.type,
        ),
        isEmpty,
      );
    });
  });

  group('settings UI', () {
    Future<_Rig> pumpSettings(
      WidgetTester tester, {
      bool writeEnabled = false,
      bool readEnabled = false,
      bool denyWrite = false,
      bool denyRead = false,
    }) async {
      final rig = await _Rig.create(
        writeEnabled: writeEnabled,
        readEnabled: readEnabled,
      );
      if (denyWrite) {
        await rig.settings.setHealthWriteWorkoutsEnabled(false);
        rig.platform.writeGranted = false;
        await rig.settings.setHealthWriteWorkoutsEnabled(true);
      }
      if (denyRead) {
        await rig.settings.setHealthReadBodyWeightEnabled(false);
        rig.platform.readGranted = false;
        await rig.settings.setHealthReadBodyWeightEnabled(true);
      }

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            settingsState: rig.settings,
            timerAlertService: FakeTimerAlertService(),
            appVersionInfo: const AppVersionInfo(version: '0.0.0', build: '0'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('HEALTH'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      return rig;
    }

    testWidgets('renders both toggles with plain-language copy', (
      tester,
    ) async {
      await pumpSettings(tester);

      expect(find.text('HEALTH'), findsOneWidget);
      expect(find.text('Write workouts'), findsOneWidget);
      expect(find.text('Read body weight'), findsOneWidget);
      expect(
        find.textContaining('Adds finished workouts to Apple Health'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Shows body weight recorded by other apps'),
        findsOneWidget,
      );

      expect(
        tester.widget<Switch>(find.byKey(healthWriteToggleKey)).value,
        isFalse,
      );
      expect(
        tester.widget<Switch>(find.byKey(healthReadToggleKey)).value,
        isFalse,
      );
    });

    testWidgets('reflecting state: enabled toggles render on', (tester) async {
      await pumpSettings(tester, writeEnabled: true, readEnabled: true);

      expect(
        tester.widget<Switch>(find.byKey(healthWriteToggleKey)).value,
        isTrue,
      );
      expect(
        tester.widget<Switch>(find.byKey(healthReadToggleKey)).value,
        isTrue,
      );
    });

    testWidgets('denied state shows the system-settings pointer (S-005)', (
      tester,
    ) async {
      await pumpSettings(tester, denyWrite: true, denyRead: true);

      expect(
        find.textContaining('Allow access in your phone settings'),
        findsNWidgets(2),
      );
      expect(find.text('Open settings'), findsNWidgets(2));
      expect(
        tester.widget<Switch>(find.byKey(healthWriteToggleKey)).value,
        isFalse,
        reason: 'denied renders as off',
      );
      expect(
        tester.widget<Switch>(find.byKey(healthReadToggleKey)).value,
        isFalse,
        reason: 'denied renders as off',
      );
    });

    testWidgets('tapping the write toggle enables the pipeline', (
      tester,
    ) async {
      final rig = await pumpSettings(tester);

      await tester.tap(find.byKey(healthWriteToggleKey));
      await tester.pumpAndSettle();

      expect(rig.settings.healthWriteWorkouts, HealthToggleState.on);
      expect(rig.platform.writePermissionRequests, 1);
    });
  });

  group('foreground trigger', () {
    testWidgets('a background → foreground cycle imports body weight and '
        'refreshes the Profile view (S-004)', (tester) async {
      final rig = await _Rig.create(readEnabled: true);
      rig.platform.weightSamples = [
        HealthWeightSample(
          sourceId: 'sample-resume',
          sampledAt: DateTime.now().subtract(const Duration(days: 1)),
          kilograms: 79.5,
        ),
      ];

      // Built the way main.dart builds it, so this exercises the shipped
      // trigger rather than calling the pipeline directly.
      final listener = app_main.createHealthLifecycleListener(
        rig.sync,
        rig.profile,
      );
      addTearDown(listener.dispose);
      await tester.pumpWidget(const SizedBox.shrink());

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(rig.platform.readQueries, 1);
      expect(rig.profile.latestBodyWeightKg, 79.5);
      expect(
        await rig.repo.getMeasurementHistory(
          ProfileMeasurements.bodyweight.type,
        ),
        hasLength(1),
      );
    });

    testWidgets('a resume with the read toggle off imports nothing', (
      tester,
    ) async {
      final rig = await _Rig.create();
      rig.platform.weightSamples = [
        HealthWeightSample(
          sourceId: 'sample-resume',
          sampledAt: DateTime.now(),
          kilograms: 79.5,
        ),
      ];

      final listener = app_main.createHealthLifecycleListener(
        rig.sync,
        rig.profile,
      );
      addTearDown(listener.dispose);
      await tester.pumpWidget(const SizedBox.shrink());

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(rig.platform.readQueries, 0);
      expect(rig.profile.latestBodyWeightKg, isNull);
    });
  });

  group('unit conversion', () {
    test('platform pound samples convert to canonical kilograms', () {
      expect(
        weightToKilograms(value: 220.462, unitLabel: 'lb'),
        closeTo(100.0, 0.01),
      );
      expect(
        weightToKilograms(value: 220.462, unitLabel: 'POUND'),
        closeTo(100.0, 0.01),
      );
      expect(weightToKilograms(value: 80.0, unitLabel: 'kg'), 80.0);
      expect(weightToKilograms(value: 80.0, unitLabel: 'KILOGRAM'), 80.0);
    });

    test('canonical kilograms round-trip through the display unit', () async {
      final repo = await _freshRepo();
      final settings = SettingsState(repo, fakePreferencesService());
      await settings.initialize();
      await settings.setPreferredWeightUnit('lbs');

      final kg = weightToKilograms(value: 220.462, unitLabel: 'lb');
      expect(UnitFormatter.convertWeight(kg, settings), closeTo(220.462, 0.01));
    });
  });
}

class _ThrowingReadPlatform implements HealthPlatformService {
  @override
  Future<bool> requestReadPermission() async => true;

  @override
  Future<bool> requestWritePermission() async => true;

  @override
  Future<List<HealthWeightSample>> readBodyWeightSince(DateTime since) async {
    throw Exception('platform read exploded');
  }

  @override
  Future<bool> writeWorkout(HealthWorkoutDraft workout) async => false;

  @override
  Future<bool> deleteWorkouts(DateTime start, DateTime end) async => false;
}
