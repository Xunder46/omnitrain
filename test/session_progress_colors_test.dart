// One definition of the session progress colours (plan 44, D-3).
//
// Plan: `docs/plans/2026-10-19-44-logger-feedback-round-plan/2026-10-19-44-logger-feedback-round-plan.md`.
// Scenario mapping:
//   S-5102 dim primary and track grey are one definition, on every theme
//   S-5106 (painter clause) a drained ring paints the track only, no arc
//
// The expected colours are derived from each theme's `ColorScheme`, never from
// a literal, so a theme change cannot quietly pass.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/app.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/widgets/session/session_progress_colors.dart';
import 'package:omnitrain/widgets/session/set_segment_bar.dart';
import 'package:omnitrain/widgets/session/timer_ring.dart';

/// A themed app, built the same way `test/sports_emphasis_redesign_test.dart`
/// builds one.
Widget _themeWrappedApp({required Widget home, required AppTheme theme}) {
  final colors = OmniTheme.colorsForTheme(theme);
  return MaterialApp(
    theme: buildTheme(
      theme: theme,
      brightness: Brightness.dark,
      secondary: colors.secondary,
      background: colors.backgroundTop,
      surface: colors.surface,
      textPrimary: colors.textDominant,
      textSecondary: colors.textSecondary,
      divider: colors.divider,
      onPrimary: getOnPrimaryForTheme(theme),
      onSecondary: getOnSecondaryForTheme(theme),
    ),
    home: home,
  );
}

Widget _probe({required TimerRingLook look}) => SingleChildScrollView(
  child: Column(
    children: [
      SetSegmentBar(
        count: 3,
        focusedIndex: 1,
        isLogged: (i) => i == 0,
        onTap: (_) {},
      ),
      TimerRing(
        key: const Key('probe-ring-ready'),
        progress: 0.5,
        running: false,
        look: look,
        child: const SizedBox(),
      ),
      const TimerRing(
        key: Key('probe-ring-counting'),
        progress: 0.5,
        running: false,
        child: SizedBox(),
      ),
    ],
  ),
);

ColorScheme _scheme(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(SetSegmentBar))).colorScheme;

Color _segmentFill(WidgetTester tester, int index) {
  final container = tester.widget<Container>(
    find.descendant(
      of: find.byKey(Key('set-segment-$index')),
      matching: find.byType(Container),
    ),
  );
  return (container.decoration! as BoxDecoration).color!;
}

TimerRingPainter _painter(WidgetTester tester, String ringKey) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(
      of: find.byKey(Key(ringKey)),
      matching: find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter is TimerRingPainter,
      ),
    ),
  );
  return paint.painter! as TimerRingPainter;
}

/// A lone `CustomPaint` carrying the painter, so the canvas calls can be read.
Widget _paintedRing(TimerRingPainter painter) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 100,
        height: 100,
        child: CustomPaint(key: const Key('painted-ring'), painter: painter),
      ),
    ),
  ),
);

void main() {
  group('S-5102 session progress colours', () {
    for (final theme in AppTheme.values) {
      testWidgets('the set bar and both ring looks read one definition '
          '(${theme.name})', (tester) async {
        await tester.pumpWidget(
          _themeWrappedApp(
            home: _probe(look: TimerRingLook.ready),
            theme: theme,
          ),
        );

        final scheme = _scheme(tester);
        final ready = _painter(tester, 'probe-ring-ready');
        final counting = _painter(tester, 'probe-ring-counting');

        // S-5102 pixel-identical values: "this is next" and "not reached".
        expect(
          SessionProgressColors.dimPrimary(scheme),
          scheme.primary.withAlpha(115),
        );
        expect(
          SessionProgressColors.trackGrey(scheme),
          scheme.onSurface.withAlpha(51),
        );

        // The ready ring's arc is the focused, unlogged segment's fill.
        expect(ready.arcColor, _segmentFill(tester, 1));
        expect(ready.arcColor, SessionProgressColors.dimPrimary(scheme));
        expect(
          ready.trackColor.a,
          0,
          reason: 'the ready look paints no grey track',
        );

        // The counting ring's track is the unlogged segment's fill.
        expect(counting.trackColor, _segmentFill(tester, 2));
        expect(counting.trackColor, SessionProgressColors.trackGrey(scheme));

        // The counting arc is the logged segment's fill: the theme primary.
        expect(counting.arcColor, _segmentFill(tester, 0));
        expect(counting.arcColor, scheme.primary);
      });
    }
  });

  group('S-5106 drained ring paints the track only', () {
    testWidgets('progress 0 draws the track circle and no arc', (tester) async {
      final scheme = ThemeData.dark().colorScheme;
      await tester.pumpWidget(
        _paintedRing(
          TimerRingPainter(
            progress: 0,
            trackColor: SessionProgressColors.trackGrey(scheme),
            arcColor: scheme.primary,
          ),
        ),
      );

      // The pattern is positional and exact: the track first, then nothing.
      expect(
        find.byKey(const Key('painted-ring')),
        paints..arc(startAngle: 0, sweepAngle: 2 * math.pi, useCenter: false),
      );
    });

    testWidgets('progress above 0 adds the progress arc', (tester) async {
      final scheme = ThemeData.dark().colorScheme;
      await tester.pumpWidget(
        _paintedRing(
          TimerRingPainter(
            progress: 0.5,
            trackColor: SessionProgressColors.trackGrey(scheme),
            arcColor: scheme.primary,
          ),
        ),
      );

      expect(
        find.byKey(const Key('painted-ring')),
        paints
          ..arc(startAngle: 0, sweepAngle: 2 * math.pi, useCenter: false)
          ..arc(
            startAngle: -math.pi / 2,
            sweepAngle: 2 * math.pi * 0.5,
            useCenter: false,
          ),
      );
    });
  });
}
