import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/app_version_info.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/settings/settings_screen.dart';
import 'package:omnitrain/state/settings/settings_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

/// The Settings page used to be a lazy ListView whose guess of its own
/// length swung by thousands of pixels while scrolling; a fling at the
/// bottom then kept re-aiming and the page jittered. The scrollable length
/// must be the same wherever the page is scrolled to.
void main() {
  for (final scale in <double>[1.0, 1.3]) {
    testWidgets('settings scroll length never changes while scrolling '
        '(text scale $scale)', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final repo = MockWorkoutRepository();
      await repo.initialize();
      final settingsState = SettingsState(repo, fakePreferencesService());
      await settingsState.initialize();

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: SettingsScreen(
            settingsState: settingsState,
            timerAlertService: FakeTimerAlertService(),
            appVersionInfo: const AppVersionInfo(version: '0.0.0', build: '0'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      final extents = <int>{};
      for (var i = 0; i < 80; i++) {
        extents.add(position.maxScrollExtent.round());
        if (position.pixels >= position.maxScrollExtent - 1) break;
        position.jumpTo(
          (position.pixels + 80).clamp(0.0, position.maxScrollExtent),
        );
        await tester.pump();
      }

      expect(
        extents.length,
        1,
        reason: 'scroll length changed while scrolling: $extents',
      );
    });
  }
}
