// filepath: test/health_platform_test.dart
//
// Scenario coverage for the platform health integration plan
// (`.github/agents/plans/2026-07-13-04-pr3-platform-health-integration-plan.md`):
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
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

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
    final workoutState = WorkoutState(repo, healthSync: sync);
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
}
