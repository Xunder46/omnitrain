// `TimerRing` — the countdown ring the round effort shows (plan 38d).
//
// Plan: `docs/plans/2026-10-16-38d-countdown-plan/2026-10-16-38d-countdown-plan.md`.
// Scenario mapping:
//   S-4401 the painter reads the remaining fraction: 1.0 before Start, 0.75
//          mid-round, 0.0 at `00:00`
//   S-4402 the digits sit inside the ring, centred
//   S-4408 the ring is 260 dp, never wider than the screen minus 64; the arc
//          sweeps smoothly between the screen's ticks while running, and is
//          applied at once when not running or when the round length grows
//
// No real clock: the sweep runs on `tester.pump(Duration)` only.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/widgets/session/timer_ring.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

/// The ring as the round screen shows it: the digits are the child.
Widget _ring({required double progress, bool running = false}) => TimerRing(
  progress: progress,
  running: running,
  child: const Text('03:00'),
);

/// The painter the ring currently paints with.
TimerRingPainter _painter(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(
      of: find.byType(TimerRing),
      matching: find.byType(CustomPaint),
    ),
  );
  return paint.painter! as TimerRingPainter;
}

double _progress(WidgetTester tester) => _painter(tester).progress;

ColorScheme _scheme(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(TimerRing))).colorScheme;

void main() {
  group('S-4401 ring progress', () {
    testWidgets('a full ring reads progress 1.0 with scheme colours', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_ring(progress: 1.0)));

      final painter = _painter(tester);
      expect(painter.progress, 1.0);
      expect(painter.trackColor, _scheme(tester).onSurface.withAlpha(51));
      expect(painter.arcColor, _scheme(tester).primary);
      expect(painter.strokeWidth, 8);
    });

    testWidgets('0.75 and 0.0 read back unchanged', (tester) async {
      await tester.pumpWidget(_host(_ring(progress: 0.75)));
      expect(_progress(tester), 0.75);

      await tester.pumpWidget(_host(_ring(progress: 0.0)));
      expect(_progress(tester), 0.0);
    });

    test('shouldRepaint follows the progress and the two colours', () {
      const scheme = ColorScheme.light();
      TimerRingPainter painterWith(double progress) => TimerRingPainter(
        progress: progress,
        trackColor: scheme.onSurface,
        arcColor: scheme.primary,
      );

      expect(painterWith(0.5).shouldRepaint(painterWith(0.5)), isFalse);
      expect(painterWith(0.4).shouldRepaint(painterWith(0.5)), isTrue);
    });
  });

  group('S-4402 digits', () {
    testWidgets('the child is centred inside the ring', (tester) async {
      await tester.pumpWidget(_host(_ring(progress: 1.0)));

      expect(find.text('03:00'), findsOneWidget);
      expect(
        tester.getCenter(find.text('03:00')),
        tester.getCenter(find.byType(TimerRing)),
      );
    });

    testWidgets('the ring carries the remaining-time label', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(_ring(progress: 1.0)));

      expect(find.bySemanticsLabel(RegExp('Time remaining')), findsOneWidget);

      handle.dispose();
    });
  });

  group('S-4408 size', () {
    testWidgets('260 dp by default, screen minus 64 on a narrow surface', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_ring(progress: 1.0)));
      expect(tester.getSize(find.byType(TimerRing)), const Size(260, 260));

      await tester.binding.setSurfaceSize(const Size(300, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_host(_ring(progress: 1.0)));
      expect(tester.getSize(find.byType(TimerRing)), const Size(236, 236));
    });
  });

  group('S-4408 sweep', () {
    testWidgets('a falling progress sweeps while running', (tester) async {
      await tester.pumpWidget(_host(_ring(progress: 0.75, running: true)));
      expect(_progress(tester), 0.75);

      await tester.pumpWidget(_host(_ring(progress: 0.70, running: true)));
      expect(
        _progress(tester),
        0.75,
        reason: 'the sweep starts where the ring was',
      );

      await tester.pump(const Duration(milliseconds: 500));
      expect(_progress(tester), greaterThan(0.70));
      expect(_progress(tester), lessThan(0.75));

      await tester.pump(const Duration(milliseconds: 500));
      expect(_progress(tester), 0.70);
    });

    testWidgets('a stopped ring applies the new value at once', (tester) async {
      await tester.pumpWidget(_host(_ring(progress: 0.75)));
      await tester.pumpWidget(_host(_ring(progress: 0.70)));

      expect(_progress(tester), 0.70);
      await tester.pump(const Duration(milliseconds: 500));
      expect(_progress(tester), 0.70);
    });

    testWidgets('a growing progress while running is applied at once', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_ring(progress: 0.5, running: true)));
      await tester.pumpWidget(_host(_ring(progress: 0.9, running: true)));

      expect(_progress(tester), 0.9);
      await tester.pump(const Duration(milliseconds: 500));
      expect(_progress(tester), 0.9);
    });

    testWidgets('the canvas gets a full track circle and a 2π·progress arc', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_ring(progress: 0.75)));

      // The ring's own paint: the CustomPaint under TimerRing.
      final ringPaint = find.descendant(
        of: find.byType(TimerRing),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint && widget.painter is TimerRingPainter,
        ),
      );

      // The track first: a whole turn from 3 o'clock. Then the remaining-time
      // arc: three quarters of a turn from the top. The sweep is positive,
      // which in the canvas' y-down space is clockwise, and it is proportional
      // to the progress: 2π·0.75, not π·0.75. The pattern is positional — the
      // painter draws the track arc before the progress arc.
      expect(
        ringPaint,
        paints
          ..arc(startAngle: 0, sweepAngle: 2 * math.pi, useCenter: false)
          ..arc(
            startAngle: -math.pi / 2,
            sweepAngle: 2 * math.pi * 0.75,
            useCenter: false,
          ),
      );
    });
  });
}
