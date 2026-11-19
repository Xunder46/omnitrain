// Plan 208 Phase 2c: proves `runStartup` passes the platform health
// gateway to `SettingsState`'s `activeEnergySource` parameter. If that
// second argument were dropped, the Settings "Read active energy"
// switch would silently resolve to "denied" in the real app.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/app.dart';
import 'package:omnitrain/core/constants/health_constants.dart';
import 'package:omnitrain/core/models/app_version_info.dart';
import 'package:omnitrain/core/services/health_platform_service.dart';
import 'package:omnitrain/core/services/preferences_service.dart';
import 'package:omnitrain/core/utils/rest_notification_service.dart';
import 'package:omnitrain/core/utils/timer_alert_service.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/main.dart' as app_main;

class _FakePreferencesService implements PreferencesService {
  int _hubOpenCount = 0;

  @override
  Future<void> init() async {}

  @override
  int getHubOpenCount() => _hubOpenCount;

  @override
  Future<void> incrementHubOpenCount() async {
    _hubOpenCount += 1;
  }
}

class _SucceedingRestNotificationService extends RestNotificationService {
  _SucceedingRestNotificationService() : super.noop();

  @override
  Future<void> initialize() async {}
}

class _CountingGateway extends UnavailableHealthPlatformService {
  int activeEnergyPermissionRequests = 0;

  @override
  Future<bool> requestActiveEnergyReadPermission() async {
    activeEnergyPermissionRequests += 1;
    return true;
  }
}

class _WeightOnlyGateway implements HealthPlatformService {
  const _WeightOnlyGateway();

  @override
  Future<bool> requestWritePermission() async => false;

  @override
  Future<bool> requestReadPermission() async => false;

  @override
  Future<bool> writeWorkout(HealthWorkoutDraft workout) async => false;

  @override
  Future<bool> deleteWorkouts(DateTime start, DateTime end) async => false;

  @override
  Future<HealthEffortOutcome> setWorkoutEffort(
    DateTime start,
    DateTime end,
    int score,
  ) async => HealthEffortOutcome.unavailable;

  @override
  Future<bool> clearWorkoutEffort(DateTime start, DateTime end) async => false;

  @override
  Future<List<HealthWeightSample>> readBodyWeightSince(DateTime since) async =>
      const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'S-20850 runStartup hands the health gateway to the active-energy switch',
    () async {
      final counting = _CountingGateway();

      final app = await app_main.runStartup(
        createRepository: () async => MockWorkoutRepository(),
        createPreferencesService: () => _FakePreferencesService(),
        createTimerAlertService: () => TimerAlertService.forTesting(isWeb: true),
        createRestNotificationService: () => _SucceedingRestNotificationService(),
        createImageStorageService: () async => null,
        createHealthPlatformGateway: () => counting,
        loadAppVersionInfo: () async =>
            const AppVersionInfo(version: '1.0.0', build: '1'),
        onNonFatalStartupIssue: (_, _) async {},
      );

      expect(app, isA<MyApp>());
      final settings = (app as MyApp).settingsState;

      await settings.setHealthReadActiveEnergyEnabled(true);

      expect(counting.activeEnergyPermissionRequests, 1);
      expect(settings.healthReadActiveEnergy, HealthToggleState.on);
    },
  );

  test(
    'S-20850 a gateway without the active-energy interface leaves the switch denied',
    () async {
      final app = await app_main.runStartup(
        createRepository: () async => MockWorkoutRepository(),
        createPreferencesService: () => _FakePreferencesService(),
        createTimerAlertService: () => TimerAlertService.forTesting(isWeb: true),
        createRestNotificationService: () => _SucceedingRestNotificationService(),
        createImageStorageService: () async => null,
        createHealthPlatformGateway: () => const _WeightOnlyGateway(),
        loadAppVersionInfo: () async =>
            const AppVersionInfo(version: '1.0.0', build: '1'),
        onNonFatalStartupIssue: (_, _) async {},
      );

      expect(app, isA<MyApp>());
      final settings = (app as MyApp).settingsState;

      await settings.setHealthReadActiveEnergyEnabled(true);

      expect(settings.healthReadActiveEnergy, HealthToggleState.permissionDenied);
    },
  );
}
