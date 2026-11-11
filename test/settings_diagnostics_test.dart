// The Diagnostics row in Settings (plan 143, S-14315): shown only with a
// watch link state and a log, between the Apple Watch row and HEALTH, and
// tapping it puts the share text on the clipboard with a "Diagnostics copied"
// message. An empty log shows "Nothing recorded yet" and copies nothing.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/app_version_info.dart';
import 'package:omnitrain/core/platform/watch_link_info.dart';
import 'package:omnitrain/core/platform/watch_link_source.dart';
import 'package:omnitrain/core/services/diagnostics_log.dart';
import 'package:omnitrain/core/services/diagnostics_storage.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/settings/settings_screen.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/watch/watch_link_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_rest_notification_service.dart';
import 'helpers/fake_timer_alert_service.dart';

const WatchLinkInfo _connected = WatchLinkInfo(
  paired: true,
  appInstalled: true,
  reachable: true,
);

/// The fake source the state test uses, copied here so this widget test owns
/// its own instance.
class _Source implements WatchLinkSource {
  WatchLinkInfo infoValue = _connected;
  Object? infoError;

  @override
  Future<WatchLinkInfo> linkInfo() async {
    final error = infoError;
    if (error != null) throw error;
    return infoValue;
  }

  @override
  Stream<WatchLinkInfo> get linkChanges => const Stream.empty();

  @override
  Stream<DateTime> get heard => const Stream.empty();
}

void main() {
  testWidgets('S-14315 a log of 2 events shows Diagnostics, 2 events, Copy', (
    WidgetTester tester,
  ) async {
    final settings = await _makeSettings();
    final log = _logOfEvents(2);
    final watch = await _makeWatchLink();

    await _pumpSettings(
      tester,
      settings: settings,
      watchLinkState: watch,
      diagnostics: log,
    );

    expect(find.text('APPLE WATCH'), findsOneWidget);
    expect(find.text('Diagnostics'), findsOneWidget);
    expect(find.text('2 events'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
  });

  testWidgets('S-14315 a log of 1 event shows 1 event', (
    WidgetTester tester,
  ) async {
    final settings = await _makeSettings();
    final log = _logOfEvents(1);
    final watch = await _makeWatchLink();

    await _pumpSettings(
      tester,
      settings: settings,
      watchLinkState: watch,
      diagnostics: log,
    );

    expect(find.text('1 event'), findsOneWidget);
  });

  testWidgets(
    'S-14315 without a watch link state there is no Diagnostics row',
    (WidgetTester tester) async {
      final settings = await _makeSettings();
      final log = _logOfEvents(2);

      await _pumpSettings(tester, settings: settings, diagnostics: log);

      expect(find.text('APPLE WATCH'), findsNothing);
      expect(find.text('Diagnostics'), findsNothing);
    },
  );

  testWidgets(
    'S-14315 with a link state but no log there is no Diagnostics row',
    (WidgetTester tester) async {
      final settings = await _makeSettings();
      final watch = await _makeWatchLink();

      await _pumpSettings(
        tester,
        settings: settings,
        watchLinkState: watch,
        diagnostics: null,
      );

      expect(find.text('Apple Watch'), findsOneWidget);
      expect(find.text('Diagnostics'), findsNothing);
    },
  );

  group('copy', () {
    String? copied;

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
      copied = null;
    });

    testWidgets(
      'S-14315 tapping the row puts the share text on the clipboard and '
      'says Diagnostics copied',
      (WidgetTester tester) async {
        final settings = await _makeSettings();
        final log = _logOfEvents(2);
        final watch = await _makeWatchLink();

        await _pumpSettings(
          tester,
          settings: settings,
          watchLinkState: watch,
          diagnostics: log,
        );

        await tester.tap(find.text('Diagnostics'));
        await tester.pump();

        expect(copied, isNotNull);
        expect(copied!.split('\n')[0], 'OmniTrain phone diagnostics');
        expect(copied!.split('\n')[1], 'App 0.0.0 (0)');
        expect(copied, contains('Events 2'));
        expect('launch'.allMatches(copied!).length, 2);
        expect(find.text('Diagnostics copied'), findsOneWidget);
      },
    );

    testWidgets(
      'S-14315 an empty log shows Nothing recorded yet and copies nothing',
      (WidgetTester tester) async {
        final settings = await _makeSettings();
        final log = _logOfEvents(0);
        final watch = await _makeWatchLink();

        await _pumpSettings(
          tester,
          settings: settings,
          watchLinkState: watch,
          diagnostics: log,
        );

        expect(find.text('Diagnostics'), findsOneWidget);
        expect(find.text('Nothing recorded yet'), findsOneWidget);
        expect(find.text('Copy'), findsOneWidget);

        await tester.tap(find.text('Diagnostics'));
        await tester.pump();

        expect(copied, isNull);
        expect(find.text('Diagnostics copied'), findsNothing);
      },
    );
  });

  testWidgets(
    'S-14315 the Diagnostics row sits between the Apple Watch row and HEALTH',
    (WidgetTester tester) async {
      final settings = await _makeSettings();
      final watch = await _makeWatchLink();
      final log = _logOfEvents(2);

      await _pumpSettings(
        tester,
        settings: settings,
        watchLinkState: watch,
        diagnostics: log,
      );

      final appleWatch = tester.getTopLeft(find.text('Apple Watch')).dy;
      final diagnostics = tester.getTopLeft(find.text('Diagnostics')).dy;
      final health = tester.getTopLeft(find.text('HEALTH')).dy;

      expect(diagnostics, greaterThan(appleWatch));
      expect(diagnostics, lessThan(health));
    },
  );
}

Future<SettingsState> _makeSettings() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  final state = SettingsState(repo, fakePreferencesService());
  await state.initialize();
  return state;
}

Future<WatchLinkState> _makeWatchLink() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  final state = WatchLinkState(source: _Source(), repository: repo);
  await state.initialize();
  return state;
}

DiagnosticsLog _logOfEvents(int count) {
  final log = DiagnosticsLog(
    storage: InMemoryDiagnosticsStorage(),
    clock: () => DateTime.utc(2026, 1, 1, 12),
  );
  for (var i = 0; i < count; i++) {
    log.note('launch', detail: 'previous=none');
  }
  return log;
}

Future<void> _pumpSettings(
  WidgetTester tester, {
  required SettingsState settings,
  WatchLinkState? watchLinkState,
  DiagnosticsLog? diagnostics,
}) async {
  // The whole Settings column, so every section header is laid out and can
  // be compared by position.
  await tester.binding.setSurfaceSize(const Size(800, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      home: SettingsScreen(
        settingsState: settings,
        timerAlertService: FakeTimerAlertService(),
        restNotificationService: FakeRestNotificationService(),
        appVersionInfo: const AppVersionInfo(version: '0.0.0', build: '0'),
        watchLinkState: watchLinkState,
        diagnostics: diagnostics,
      ),
    ),
  );
  await tester.pumpAndSettle();
}
