import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/settings/settings_screen.dart';
import 'package:omnitrain/state/settings/settings_state.dart';

import 'helpers/fake_rest_notification_service.dart';
import 'helpers/fake_timer_alert_service.dart';

void main() {
  Future<SettingsState> makeSettings() async {
    final repo = MockWorkoutRepository();
    await repo.initialize();
    final state = SettingsState(repo);
    await state.initialize();
    return state;
  }

  group('SOUNDS & ALERTS section', () {
    testWidgets('section header SOUNDS & ALERTS is present', (
      WidgetTester tester,
    ) async {
      final settings = await makeSettings();

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            settingsState: settings,
            timerAlertService: FakeTimerAlertService(),
            restNotificationService: FakeRestNotificationService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('SOUNDS & ALERTS'), findsOneWidget);
    });

    testWidgets('shows default Effort Timer Sound value Boxing Bell', (
      WidgetTester tester,
    ) async {
      final settings = await makeSettings();

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            settingsState: settings,
            timerAlertService: FakeTimerAlertService(),
            restNotificationService: FakeRestNotificationService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Boxing Bell'), findsWidgets);
    });

    testWidgets('shows default Rest Ping value Off', (
      WidgetTester tester,
    ) async {
      final settings = await makeSettings();

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            settingsState: settings,
            timerAlertService: FakeTimerAlertService(),
            restNotificationService: FakeRestNotificationService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Off'), findsOneWidget);
    });

    testWidgets('shows default Rest Ping Sound value Soft Chime', (
      WidgetTester tester,
    ) async {
      final settings = await makeSettings();

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            settingsState: settings,
            timerAlertService: FakeTimerAlertService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Soft Chime'), findsOneWidget);
    });

    testWidgets(
      'PREFERENCES appears before SOUNDS & ALERTS before APPEARANCE',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 3000));
        final settings = await makeSettings();

        await tester.pumpWidget(
          MaterialApp(
            home: SettingsScreen(
              settingsState: settings,
              timerAlertService: FakeTimerAlertService(),
              restNotificationService: FakeRestNotificationService(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final prefPos = tester.getTopLeft(find.text('PREFERENCES')).dy;
        final soundPos = tester.getTopLeft(find.text('SOUNDS & ALERTS')).dy;
        final appPos = tester.getTopLeft(find.text('APPEARANCE')).dy;

        expect(prefPos, lessThan(soundPos));
        expect(soundPos, lessThan(appPos));
      },
    );

    testWidgets('tapping Effort Timer Sound row opens bottom sheet', (
      WidgetTester tester,
    ) async {
      final settings = await makeSettings();

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            settingsState: settings,
            timerAlertService: FakeTimerAlertService(),
            restNotificationService: FakeRestNotificationService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Effort Timer Sound'));
      await tester.pumpAndSettle();

      expect(find.text('Digital Buzzer'), findsOneWidget);
    });

    testWidgets('tapping Rest Ping row opens interval picker bottom sheet', (
      WidgetTester tester,
    ) async {
      final settings = await makeSettings();

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            settingsState: settings,
            timerAlertService: FakeTimerAlertService(),
            restNotificationService: FakeRestNotificationService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Rest Ping'));
      await tester.pumpAndSettle();

      expect(find.text('Rest Ping Interval'), findsOneWidget);
      expect(find.text('30s'), findsOneWidget);
      expect(find.text('1 min'), findsOneWidget);
    });

    testWidgets('selecting an interval in the picker updates the state', (
      WidgetTester tester,
    ) async {
      final settings = await makeSettings();
      expect(settings.restPingInterval, 0);

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            settingsState: settings,
            timerAlertService: FakeTimerAlertService(),
            restNotificationService: FakeRestNotificationService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Rest Ping'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('1 min'));
      await tester.pumpAndSettle();

      expect(settings.restPingInterval, 60);
    });

    testWidgets(
      'S-019: first interval activation dialog covers both rest and effort alerts',
      (WidgetTester tester) async {
        final settings = await makeSettings();
        // notificationPermissionAsked is false by default
        expect(settings.notificationPermissionAsked, isFalse);

        await tester.pumpWidget(
          MaterialApp(
            home: SettingsScreen(
              settingsState: settings,
              timerAlertService: FakeTimerAlertService(),
              restNotificationService: FakeRestNotificationService(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Rest Ping'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('1 min'));
        await tester.pumpAndSettle();

        // Dialog should appear covering both rest pings and effort timer alerts
        expect(find.text('Enable Timer Notifications?'), findsOneWidget);
        expect(
          find.text(
            'Notifications keep rest pings and effort timer alerts working when '
            'your phone is locked. You can change this any time in Settings.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('shows notification permission row with Not yet asked state', (
      WidgetTester tester,
    ) async {
      final settings = await makeSettings();
      final restService = FakeRestNotificationService();

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            settingsState: settings,
            timerAlertService: FakeTimerAlertService(),
            restNotificationService: restService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Notification Permission'), findsOneWidget);
      expect(find.text('Not yet asked'), findsOneWidget);
      expect(
        find.text(
          'Required for rest and effort timer alerts while phone is locked or app is backgrounded',
        ),
        findsOneWidget,
      );
      expect(restService.hasPermissionCallCount, 0);
    });

    testWidgets('shows disabled state when permission was asked and denied', (
      WidgetTester tester,
    ) async {
      final settings = await makeSettings();
      await settings.setNotificationPermissionAsked();
      final restService = FakeRestNotificationService()
        ..permissionGranted = false;

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            settingsState: settings,
            timerAlertService: FakeTimerAlertService(),
            restNotificationService: restService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Disabled - tap to open Settings'), findsOneWidget);
      expect(restService.hasPermissionCallCount, greaterThan(0));
    });

    testWidgets(
      'tapping notification row requests permission the first time',
      (WidgetTester tester) async {
        final settings = await makeSettings();
        final restService = FakeRestNotificationService()
          ..permissionGranted = true;

        await tester.pumpWidget(
          MaterialApp(
            home: SettingsScreen(
              settingsState: settings,
              timerAlertService: FakeTimerAlertService(),
              restNotificationService: restService,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Notification Permission'));
        await tester.pumpAndSettle();

        expect(restService.requestPermissionCallCount, 1);
        expect(settings.notificationPermissionAsked, isTrue);
        expect(find.text('Enabled'), findsOneWidget);
      },
    );

    testWidgets(
      'tapping notification row when denied refreshes disabled status',
      (WidgetTester tester) async {
        final settings = await makeSettings();
        await settings.setNotificationPermissionAsked();
        final restService = FakeRestNotificationService()
          ..permissionGranted = false;

        await tester.pumpWidget(
          MaterialApp(
            home: SettingsScreen(
              settingsState: settings,
              timerAlertService: FakeTimerAlertService(),
              restNotificationService: restService,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final initialHasPermissionCalls = restService.hasPermissionCallCount;
        await tester.tap(find.text('Notification Permission'));
        await tester.pumpAndSettle();

        expect(restService.hasPermissionCallCount, initialHasPermissionCalls);
        expect(find.text('Disabled - tap to open Settings'), findsOneWidget);
      },
    );
  });
}
