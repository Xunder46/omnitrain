// filepath: test/health_active_energy_settings_screen_test.dart
//
// Plan 208 Phase 2b (S-20829): the Settings ▸ HEALTH `Read active energy`
// row on iOS and Android, absent on web and desktop, below `Read body
// weight`, with the D-9 subtitle. Mock harness only — a tap here writes a
// preference and never runs on Hive inside `testWidgets`.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/health_constants.dart';
import 'package:omnitrain/core/models/app_version_info.dart';
import 'package:omnitrain/core/services/health_platform_service.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/settings/settings_screen.dart';
import 'package:omnitrain/state/settings/settings_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

/// Test double for [HealthActiveEnergySource]: counts permission asks,
/// answers from [granted].
class _FakeActiveEnergySource implements HealthActiveEnergySource {
  _FakeActiveEnergySource({this.granted = true});

  final bool granted;
  int permissionRequests = 0;

  @override
  Future<bool> requestActiveEnergyReadPermission() async {
    permissionRequests++;
    return granted;
  }

  @override
  Future<Map<int, double>> readDailyActiveEnergy(List<DateTime> dayStarts) =>
      Future.value(const {});
}

const _energySubtitle =
    'Shows the calories you burn per day, from all movement, on the Stats '
    'Fuel card. Only active energy is read.';

Future<SettingsState> _pumpSettings(
  WidgetTester tester, {
  required TargetPlatform platform,
  _FakeActiveEnergySource? source,
  bool scrollToEnergyRow = false,
}) async {
  final repo = await _freshRepo();
  final settings = SettingsState(
    repo,
    fakePreferencesService(),
    activeEnergySource: source ?? _FakeActiveEnergySource(),
  );
  await settings.initialize();

  debugDefaultTargetPlatformOverride = platform;
  await tester.pumpWidget(
    MaterialApp(
      home: SettingsScreen(
        settingsState: settings,
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
  if (scrollToEnergyRow) {
    await tester.scrollUntilVisible(
      find.text('Read active energy'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }
  return settings;
}

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('S-20829 iOS shows Read active energy below Read body weight', (
    tester,
  ) async {
    await _pumpSettings(
      tester,
      platform: TargetPlatform.iOS,
      scrollToEnergyRow: true,
    );

    expect(find.text('Read active energy'), findsOneWidget);
    expect(find.text(_energySubtitle), findsOneWidget);
    final switchFinder = find.byKey(healthReadActiveEnergyToggleKey);
    expect(switchFinder, findsOneWidget);
    expect(tester.widget<Switch>(switchFinder).value, isFalse);

    final energyRect = tester.getRect(switchFinder);
    final bodyWeightRect = tester.getRect(find.byKey(healthReadToggleKey));
    expect(energyRect.top, greaterThan(bodyWeightRect.top));

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('S-20829 Android shows it too', (tester) async {
    await _pumpSettings(
      tester,
      platform: TargetPlatform.android,
      scrollToEnergyRow: true,
    );

    expect(find.text('Read active energy'), findsOneWidget);
    expect(find.text(_energySubtitle), findsOneWidget);
    expect(find.byKey(healthReadActiveEnergyToggleKey), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('S-20829 macOS shows no Read active energy row', (tester) async {
    await _pumpSettings(tester, platform: TargetPlatform.macOS);

    expect(find.byKey(healthReadActiveEnergyToggleKey), findsNothing);
    expect(find.text('Read active energy'), findsNothing);
    expect(find.text('Read body weight'), findsOneWidget);
    expect(
      find.textContaining('Shows body weight recorded by other apps'),
      findsOneWidget,
    );

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('S-20829 turning it on asks Health once and persists', (
    tester,
  ) async {
    final granting = _FakeActiveEnergySource(granted: true);
    final settings = await _pumpSettings(
      tester,
      platform: TargetPlatform.iOS,
      source: granting,
      scrollToEnergyRow: true,
    );

    await tester.tap(find.byKey(healthReadActiveEnergyToggleKey));
    await tester.pumpAndSettle();

    expect(granting.permissionRequests, 1);
    expect(settings.healthReadActiveEnergy, HealthToggleState.on);
    expect(
      tester.widget<Switch>(find.byKey(healthReadActiveEnergyToggleKey)).value,
      isTrue,
    );

    // A refusing source: the switch stays off and the denied notice appears.
    final refusing = _FakeActiveEnergySource(granted: false);
    final refused = await _pumpSettings(
      tester,
      platform: TargetPlatform.iOS,
      source: refusing,
      scrollToEnergyRow: true,
    );
    expect(find.textContaining('Permission was denied'), findsNothing);

    await tester.tap(find.byKey(healthReadActiveEnergyToggleKey));
    await tester.pumpAndSettle();

    expect(refusing.permissionRequests, 1);
    expect(refused.healthReadActiveEnergy, HealthToggleState.permissionDenied);
    expect(
      tester.widget<Switch>(find.byKey(healthReadActiveEnergyToggleKey)).value,
      isFalse,
    );
    expect(find.textContaining('Permission was denied'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('S-20829 Read body weight is unchanged on all three platforms', (
    tester,
  ) async {
    for (final platform in [
      TargetPlatform.iOS,
      TargetPlatform.android,
      TargetPlatform.macOS,
    ]) {
      await _pumpSettings(tester, platform: platform);

      expect(find.text('Read body weight'), findsOneWidget);
      expect(
        find.textContaining('Shows body weight recorded by other apps'),
        findsOneWidget,
      );
      expect(find.byKey(healthReadToggleKey), findsOneWidget);
    }

    debugDefaultTargetPlatformOverride = null;
  });
}
