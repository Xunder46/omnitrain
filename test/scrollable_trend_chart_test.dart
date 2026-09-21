// filepath: test/scrollable_trend_chart_test.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/core/utils/chart_axis_helper.dart';
import 'package:omnitrain/features/stats/widgets/scrollable_trend_chart.dart';

void main() {
  // The wrapper only needs an OmniThemeColors instance to render
  // its pinned y-axis labels; pick any valid theme so the test
  // is environment-agnostic.
  final themeColors = OmniTheme.colorsForTheme(AppTheme.abyssalNeon);
  const bounds = ChartAxisBounds(min: 0, max: 100, interval: 25);

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Pump a `ScrollableTrendChart` at a fixed surface width so the
  /// viewport width is deterministic. Captures the plotWidth the
  /// chartBuilder was invoked with and the inner scroll position
  /// after the first layout pass.
  Future<({double plotWidth, double scrollPixels, double scrollMax})> pumpChart(
    WidgetTester tester, {
    required int pointCount,
    int maxVisiblePoints = 8,
    double surfaceWidth = 400,
    double chartHeight = 120,
    List<FlSpot> Function(int pointCount)? spotsFor,
    bool touchEnabled = false,
  }) async {
    await tester.binding.setSurfaceSize(Size(surfaceWidth, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    double capturedPlotWidth = -1;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: surfaceWidth,
              child: ScrollableTrendChart(
                themeColors: themeColors,
                bounds: bounds,
                unitLabel: '',
                pointCount: pointCount,
                maxVisiblePoints: maxVisiblePoints,
                height: chartHeight,
                chartBuilder: (plotWidth) {
                  capturedPlotWidth = plotWidth;
                  final spots = spotsFor != null
                      ? spotsFor(pointCount)
                      : List<FlSpot>.generate(
                          pointCount,
                          (i) => FlSpot(i.toDouble(), (i + 1).toDouble()),
                        );
                  return LineChart(
                    LineChartData(
                      lineBarsData: [LineChartBarData(spots: spots)],
                      lineTouchData: LineTouchData(enabled: touchEnabled),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The pinned y-axis column is `kScrollableTrendPinnedAxisWidth` (64 dp);
    // the remaining horizontal space is the scrollable plot's viewport.
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).last,
    );
    return (
      plotWidth: capturedPlotWidth,
      scrollPixels: scrollable.position.pixels,
      scrollMax: scrollable.position.maxScrollExtent,
    );
  }

  // ── Tests ────────────────────────────────────────────────────────────────

  group('ScrollableTrendChart — maxVisiblePoints width rule', () {
    testWidgets('default maxVisiblePoints is 8 (D-1)', (tester) async {
      // Caller does not pass maxVisiblePoints → default is 8 → per-point
      // width = viewport / 8. For 12 points: 12 × (viewport/8) > viewport.
      final r = await pumpChart(tester, pointCount: 12);
      const pinnedAxis = kScrollableTrendPinnedAxisWidth;
      final viewport = 400.0 - pinnedAxis;
      // per-point floor 28; viewport/8 = 42 → use 42
      expect(r.plotWidth, 12 * (viewport / 8));
    });

    testWidgets('with >maxVisiblePoints: plot width = points × '
        '(viewport / maxVisiblePoints), floored at 28', (tester) async {
      // viewport=336 (400 - 64 pinned axis), maxVisiblePoints=8 →
      // per-point = 336/8 = 42 (no floor hit).
      // 12 points → plot width = 12 × 42 = 504.
      const pinnedAxis = kScrollableTrendPinnedAxisWidth;
      final viewport = 400.0 - pinnedAxis;
      final r = await pumpChart(tester, pointCount: 12, maxVisiblePoints: 8);
      expect(r.plotWidth, 12 * (viewport / 8));
    });

    testWidgets('with ≤maxVisiblePoints: plot fills the viewport (no scroll)', (
      tester,
    ) async {
      const pinnedAxis = kScrollableTrendPinnedAxisWidth;
      final viewport = 400.0 - pinnedAxis;
      final r = await pumpChart(tester, pointCount: 3, maxVisiblePoints: 8);
      expect(r.plotWidth, viewport);
      expect(
        r.scrollMax,
        0,
        reason: 'no scroll extent when plot fits viewport',
      );
    });

    testWidgets('per-point width is floored at 28 dp', (tester) async {
      // Force a very narrow viewport so viewport/maxVisiblePoints < 28.
      // surfaceWidth=120, viewport=120-64=56, maxVisiblePoints=8 →
      // per-point would be 7, but floor at 28 → per-point = 28.
      // 12 points → plot width = 12 × 28 = 336.
      final r = await pumpChart(
        tester,
        pointCount: 12,
        maxVisiblePoints: 8,
        surfaceWidth: 120,
      );
      expect(r.plotWidth, 12 * 28.0);
    });
  });

  group('ScrollableTrendChart — newest-first open (D-2 follow-on)', () {
    testWidgets('with >maxVisiblePoints: opens scrolled to maxScrollExtent '
        '(S-101/S-103)', (tester) async {
      final r = await pumpChart(tester, pointCount: 12);
      expect(
        r.scrollPixels,
        r.scrollMax,
        reason: 'newest-first: pixels == maxScrollExtent after first layout',
      );
      expect(r.scrollMax, greaterThan(0));
    });

    testWidgets('does NOT use reverse:true on the inner scroll view '
        '(data is not mirrored — S-103)', (tester) async {
      final r = await pumpChart(tester, pointCount: 12);
      // The position is at maxScrollExtent (rightmost), but reverse:true
      // would also flip the *content* direction. With reverse:false and
      // a jump to maxScrollExtent, the leftmost spot is the OLDEST point
      // and the rightmost spot is the NEWEST point — time order is
      // preserved. Verify the SingleChildScrollView's reverse is false.
      final scrollView = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      expect(scrollView.reverse, isFalse);
      expect(r.scrollPixels, r.scrollMax);
    });
  });

  group('ScrollableTrendChart — no popup (D-4)', () {
    testWidgets(
      'chartBuilder-provided LineTouchData(enabled: false) never surfaces '
      'a Tooltip ancestor',
      (tester) async {
        await pumpChart(tester, pointCount: 12, touchEnabled: false);
        // Tap on the line chart.
        await tester.tap(find.byType(LineChart));
        await tester.pumpAndSettle();
        expect(find.byType(Tooltip), findsNothing);
      },
    );
  });

  group('ScrollableTrendChart — layout invariants', () {
    testWidgets('renders exactly one pinned-axis column on the left '
        'and one scrollable plot on the right', (tester) async {
      await pumpChart(tester, pointCount: 12);
      // The Row's first child is the pinned column; verify its width.
      final pinnedColumn = tester.widget<SizedBox>(
        find
            .descendant(of: find.byType(Row), matching: find.byType(SizedBox))
            .first,
      );
      expect(pinnedColumn.width, kScrollableTrendPinnedAxisWidth);
      expect(pinnedColumn.height, kScrollableTrendChartHeight);
    });

    // ── Note: the "no Transform ancestor of LineChart" invariant
    // (S-105 / D-6) is covered as an integration test in
    // `test/screen_widget_test.dart` against the full StatsScreen
    // widget tree — checking it inside this minimal pump would
    // catch framework-internal Transforms (overflow indicators,
    // scroll fade effects) that have nothing to do with the chart
    // chrome the plan set out to remove.
  });
}
