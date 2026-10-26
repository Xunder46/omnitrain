// The APPLE WATCH row in Settings: shown only with a link state, read-only,
// between WORKOUT and HEALTH, and live while the screen is open.
//
// Plan: `docs/plans/2026-10-21-47c-watch-status-on-phone-plan/2026-10-21-47c-watch-status-on-phone-plan.md`
// (D-4). Scenario mapping:
//   S-6910 no link state, no section         → `S-6910 ...`
//   S-6911 the row per phase and last sync   → `S-6911 ...`
//   S-6912 the row is read-only              → `S-6912 ...`
//   S-6913 the section sits between the two  → `S-6913 ...`
//   S-6914 a heard event updates the line    → `S-6914 ...`

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/app_version_info.dart';
import 'package:omnitrain/core/platform/watch_link_info.dart';
import 'package:omnitrain/core/platform/watch_link_source.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/settings/settings_screen.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/watch/watch_link_state.dart';
import 'package:omnitrain/widgets/layout/omni_surface.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_rest_notification_service.dart';
import 'helpers/fake_timer_alert_service.dart';

const WatchLinkInfo _notPaired = WatchLinkInfo(
  paired: false,
  appInstalled: false,
  reachable: false,
);

const WatchLinkInfo _appNotInstalled = WatchLinkInfo(
  paired: true,
  appInstalled: false,
  reachable: false,
);

const WatchLinkInfo _notReachable = WatchLinkInfo(
  paired: true,
  appInstalled: true,
  reachable: false,
);

const WatchLinkInfo _connected = WatchLinkInfo(
  paired: true,
  appInstalled: true,
  reachable: true,
);

/// The fake source the state test uses, copied here so the widget test owns
/// its own instance and `test/watch_link_state_test.dart` stays untouched.
class _Source implements WatchLinkSource {
  WatchLinkInfo infoValue = _connected;
  Object? infoError;

  final StreamController<WatchLinkInfo> changes =
      StreamController<WatchLinkInfo>.broadcast();
  final StreamController<DateTime> heardEvents =
      StreamController<DateTime>.broadcast();

  @override
  Future<WatchLinkInfo> linkInfo() async {
    final error = infoError;
    if (error != null) throw error;
    return infoValue;
  }

  @override
  Stream<WatchLinkInfo> get linkChanges => changes.stream;

  @override
  Stream<DateTime> get heard => heardEvents.stream;

  Future<void> close() async {
    await changes.close();
    await heardEvents.close();
  }
}

void main() {
  Future<SettingsState> makeSettings() async {
    final repo = MockWorkoutRepository();
    await repo.initialize();
    final state = SettingsState(repo, fakePreferencesService());
    await state.initialize();
    return state;
  }

  Future<void> pumpSettings(
    WidgetTester tester, {
    required SettingsState settings,
    WatchLinkState? watchLinkState,
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
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<WatchLinkState> makeWatchLink(
    _Source source,
    MockWorkoutRepository repository, {
    WatchLinkInfo info = _connected,
  }) async {
    source.infoValue = info;
    final state = WatchLinkState(source: source, repository: repository);
    await state.initialize();
    return state;
  }

  group('APPLE WATCH section', () {
    testWidgets('S-6910 without a link state there is no APPLE WATCH section', (
      WidgetTester tester,
    ) async {
      final settings = await makeSettings();

      await pumpSettings(tester, settings: settings);

      expect(find.text('APPLE WATCH'), findsNothing);
      expect(find.text('Apple Watch'), findsNothing);
    });

    testWidgets(
      'S-6911 a connected watch shows Apple Watch, Connected and the last '
      'sync',
      (WidgetTester tester) async {
        final source = _Source();
        final repository = MockWorkoutRepository();
        await repository.initialize();
        final watch = await makeWatchLink(source, repository);
        addTearDown(() {
          watch.dispose();
          unawaited(source.close());
        });
        source.heardEvents.add(
          DateTime.now().subtract(const Duration(minutes: 5)),
        );
        await tester.pump();
        final settings = await makeSettings();

        await pumpSettings(tester, settings: settings, watchLinkState: watch);

        expect(find.text('Apple Watch'), findsOneWidget);
        expect(find.text('Connected'), findsOneWidget);
        expect(find.text('Last synced 5 min ago'), findsOneWidget);
      },
    );

    testWidgets('S-6911 a paired watch out of reach shows Not reachable', (
      WidgetTester tester,
    ) async {
      final source = _Source();
      final repository = MockWorkoutRepository();
      await repository.initialize();
      final watch = await makeWatchLink(
        source,
        repository,
        info: _notReachable,
      );
      addTearDown(() {
        watch.dispose();
        unawaited(source.close());
      });
      final settings = await makeSettings();

      await pumpSettings(tester, settings: settings, watchLinkState: watch);

      expect(find.text('Apple Watch'), findsOneWidget);
      expect(find.text('Not reachable'), findsOneWidget);
      expect(find.text('Never synced'), findsOneWidget);
    });

    testWidgets('S-6911 no paired watch shows Not paired', (
      WidgetTester tester,
    ) async {
      final source = _Source();
      final repository = MockWorkoutRepository();
      await repository.initialize();
      final watch = await makeWatchLink(source, repository, info: _notPaired);
      addTearDown(() {
        watch.dispose();
        unawaited(source.close());
      });
      final settings = await makeSettings();

      await pumpSettings(tester, settings: settings, watchLinkState: watch);

      expect(find.text('Apple Watch'), findsOneWidget);
      expect(find.text('Not paired'), findsOneWidget);
      expect(find.text('Never synced'), findsOneWidget);
    });

    testWidgets('S-6911 a paired watch without the app says so', (
      WidgetTester tester,
    ) async {
      final source = _Source();
      final repository = MockWorkoutRepository();
      await repository.initialize();
      final watch = await makeWatchLink(
        source,
        repository,
        info: _appNotInstalled,
      );
      addTearDown(() {
        watch.dispose();
        unawaited(source.close());
      });
      final settings = await makeSettings();

      await pumpSettings(tester, settings: settings, watchLinkState: watch);

      expect(find.text('Apple Watch'), findsOneWidget);
      expect(find.text('Watch app not installed'), findsOneWidget);
      expect(find.text('Never synced'), findsOneWidget);
    });

    testWidgets('S-6912 the row offers no tap target', (
      WidgetTester tester,
    ) async {
      final source = _Source();
      final repository = MockWorkoutRepository();
      await repository.initialize();
      final watch = await makeWatchLink(source, repository);
      addTearDown(() {
        watch.dispose();
        unawaited(source.close());
      });
      final settings = await makeSettings();

      await pumpSettings(tester, settings: settings, watchLinkState: watch);

      final section = find
          .ancestor(
            of: find.text('Apple Watch'),
            matching: find.byType(OmniSurface),
          )
          .first;
      expect(
        find.descendant(of: section, matching: find.byType(InkWell)),
        findsNothing,
      );
      expect(
        find.descendant(of: section, matching: find.byType(GestureDetector)),
        findsNothing,
      );
    });

    testWidgets('S-6913 APPLE WATCH sits after WORKOUT and before HEALTH', (
      WidgetTester tester,
    ) async {
      final source = _Source();
      final repository = MockWorkoutRepository();
      await repository.initialize();
      final watch = await makeWatchLink(source, repository);
      addTearDown(() {
        watch.dispose();
        unawaited(source.close());
      });
      final settings = await makeSettings();

      await pumpSettings(tester, settings: settings, watchLinkState: watch);

      final workout = tester.getTopLeft(find.text('WORKOUT')).dy;
      final appleWatch = tester.getTopLeft(find.text('APPLE WATCH')).dy;
      final health = tester.getTopLeft(find.text('HEALTH')).dy;

      expect(workout, lessThan(appleWatch));
      expect(appleWatch, lessThan(health));
    });

    testWidgets(
      'S-6914 a heard frame updates the line while Settings is open',
      (WidgetTester tester) async {
        final source = _Source();
        final repository = MockWorkoutRepository();
        await repository.initialize();
        final watch = await makeWatchLink(source, repository);
        addTearDown(() {
          watch.dispose();
          unawaited(source.close());
        });
        final settings = await makeSettings();

        await pumpSettings(tester, settings: settings, watchLinkState: watch);
        expect(find.text('Never synced'), findsOneWidget);

        // The stream delivers on a microtask, so the first pump carries the
        // event and the frame it notifies paints on the next one.
        source.heardEvents.add(DateTime.now());
        await tester.pump();
        await tester.pump();

        expect(find.text('Last synced just now'), findsOneWidget);
        expect(find.text('Never synced'), findsNothing);
      },
    );
  });
}
