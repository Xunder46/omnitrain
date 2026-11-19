// The Settings Diagnostics row counts the watch's received log and copies both
// logs together (plan 144, S-14406, D-14406).

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

/// The fake source the settings diagnostics test uses, copied here so this
/// widget test owns its own instance.
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

  testWidgets('S-14406 a phone log of 2 and a watch log of 3 count both', (
    WidgetTester tester,
  ) async {
    final settings = await _makeSettings();
    final watch = await _makeWatchLink();
    final log = _phoneLogOf(2);
    _attachWatchLog(log, 3, () => DateTime.utc(2026, 7, 13, 6, 5));

    await _pumpSettings(
      tester,
      settings: settings,
      watchLinkState: watch,
      diagnostics: log,
    );

    expect(find.text('2 events · watch log 3 events'), findsOneWidget);
  });

  testWidgets('S-14406 a watch log of 1 event is singular', (
    WidgetTester tester,
  ) async {
    final settings = await _makeSettings();
    final watch = await _makeWatchLink();
    final log = _phoneLogOf(2);
    _attachWatchLog(log, 1, () => DateTime.utc(2026, 7, 13, 6, 5));

    await _pumpSettings(
      tester,
      settings: settings,
      watchLinkState: watch,
      diagnostics: log,
    );

    expect(find.text('2 events · watch log 1 event'), findsOneWidget);
  });

  testWidgets('S-14406 with no watch log attached the subtitle is as before', (
    WidgetTester tester,
  ) async {
    final settings = await _makeSettings();
    final watch = await _makeWatchLink();
    final log = _phoneLogOf(2);

    await _pumpSettings(
      tester,
      settings: settings,
      watchLinkState: watch,
      diagnostics: log,
    );

    expect(find.text('2 events'), findsOneWidget);
  });

  testWidgets(
    'S-14406 tapping Copy puts both logs on the clipboard, watch lines tagged',
    (WidgetTester tester) async {
      final settings = await _makeSettings();
      final watch = await _makeWatchLink();
      final log = _phoneLogOf(2);
      _attachWatchLog(log, 3, () => DateTime.utc(2026, 7, 13, 6, 5));

      await _pumpSettings(
        tester,
        settings: settings,
        watchLinkState: watch,
        diagnostics: log,
      );

      await tester.tap(find.text('Diagnostics'));
      await tester.pump();

      expect(copied, isNotNull);
      expect(copied, contains('Watch log received 2026-07-13T06:05:00Z'));
      expect(copied, contains('[watch] launch'));
      expect('[watch]'.allMatches(copied!).length, 3);
      expect('[phone]'.allMatches(copied!).length, 2);
      expect(find.text('Diagnostics copied'), findsOneWidget);
    },
  );

  testWidgets('S-14406 an empty phone log with a watch log is not Nothing yet', (
    WidgetTester tester,
  ) async {
    final settings = await _makeSettings();
    final watch = await _makeWatchLink();
    final log = _phoneLogOf(0);
    _attachWatchLog(log, 2, () => DateTime.utc(2026, 7, 13, 6, 5));

    await _pumpSettings(
      tester,
      settings: settings,
      watchLinkState: watch,
      diagnostics: log,
    );

    expect(find.text('0 events · watch log 2 events'), findsOneWidget);
    expect(find.text('Nothing recorded yet'), findsNothing);
  });
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

DiagnosticsLog _phoneLogOf(int count) {
  final log = DiagnosticsLog(
    storage: InMemoryDiagnosticsStorage(),
    clock: () => DateTime.utc(2026, 1, 1, 12),
  );
  for (var i = 0; i < count; i++) {
    log.note('launch', detail: 'previous=none');
  }
  return log;
}

/// Writes [count] watch lines through a log over the attached storage, so the
/// line shape is the log's own, and attaches it.
void _attachWatchLog(DiagnosticsLog log, int count, DateTime? Function() at) {
  final storage = InMemoryDiagnosticsStorage();
  var tick = DateTime.utc(2026, 7, 13, 6, 0, 1);
  final writer = DiagnosticsLog(
    storage: storage,
    clock: () {
      final now = tick;
      tick = tick.add(const Duration(seconds: 1));
      return now;
    },
  );
  for (var i = 0; i < count; i++) {
    writer.note('launch', detail: 'previous=none');
  }
  log.attachWatchReceived(storage, at);
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
