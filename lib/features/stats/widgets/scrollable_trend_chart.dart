// filepath: lib/features/stats/widgets/scrollable_trend_chart.dart
import 'package:flutter/material.dart';

import '../../../core/constants/omni_theme.dart';
import '../../../core/utils/chart_axis_helper.dart';

/// Default number of data points visible in the scrollable plot
/// before horizontal scroll engages. The plot width is
/// `max(viewportWidth, pointCount × perPointWidth)` where
/// `perPointWidth = max(28, viewportWidth / maxVisiblePoints)` —
/// so `maxVisiblePoints` points always fit on screen for any
/// viewport wider than `28 × maxVisiblePoints`. When `pointCount`
/// exceeds `maxVisiblePoints`, the inner width grows past the
/// viewport and the chart becomes drag-scrollable.
const int kScrollableTrendMaxVisiblePoints = 8;

/// Minimum per-point horizontal slot width inside the scrollable
/// plot. Ensures date labels stay legible on narrow phones: even
/// when `viewportWidth / maxVisiblePoints` would otherwise be
/// smaller (e.g. a 120 dp viewport with 8 visible points →
/// 7 dp each), the wrapper floors the slot at 28 dp.
const double kScrollableTrendMinPerPointWidth = 28.0;

/// Horizontal margin applied to the left and right edges of the
/// plot area to prevent edge points and labels from clipping (D-4).
/// Ensures leftmost and rightmost points render fully with complete
/// markers even at scroll extremes.
const double kScrollableTrendHorizontalMargin = 12.0;

/// A horizontally scrollable trend chart with a pinned y-axis
/// label column. Replaces the fixed-width rendering for every
/// stats chart on [StatsScreen] (strength e1RM, strength volume,
/// cardio pace, cardio duration, nutrition calories, nutrition
/// macros) and the profile measurement history sheet.
///
/// ## Layout
///
/// ```
/// ┌──────────────┬────────────────────────────────────┐
/// │              │  horizontal scroll view             │
/// │ pinned y-axis│  ┌──────────────────────────────┐  │
/// │  (static)    │  │  plot (intrinsic width =      │  │
/// │              │  │   max(viewport, n*perPoint))  │  │
/// │  labels      │  │                              │  │
/// │  (min/..)    │  │  curves + x-axis dates       │  │
/// │              │  └──────────────────────────────┘  │
/// │  unit text   │  ▲ opens scrolled to newest (right)│
/// └──────────────┴────────────────────────────────────┘
/// ```
///
/// The pinned column is **not** drawn by `fl_chart` — fl_chart
/// has no native pinned axis. Instead the wrapper renders the
/// same label values (min / min+interval / … / max) the chart
/// would have used with `leftTitles: showTitles: true`, and the
/// chart itself has `leftTitles: showTitles: false`. The two
/// share the **same** [ChartAxisBounds] (min / max / interval),
/// so labels stay aligned with the plot as the user scrolls.
///
/// ## Newest-first open
///
/// A [ScrollController] is wired to the horizontal
/// `SingleChildScrollView`. After the first layout the wrapper
/// jumps to `maxScrollExtent` so the user opens the card looking
/// at the most recent point on the right. `reverse: true` would
/// flip the plot direction too, so we use a programmatic jump
/// instead.
///
/// ## Sparse-data clamp
///
/// When `pointCount ≤ maxVisiblePoints` the wrapper passes
/// `physics: NeverScrollableScrollPhysics()` to the inner scroll
/// view and constrains the plot width to the viewport — the
/// chart fills the card with no scroll. When `pointCount` exceeds
/// [maxVisiblePoints], the inner width grows past the viewport
/// (per-point width × pointCount) and the chart becomes
/// drag-scrollable.
///
/// ## No popups
///
/// The wrapper itself does not enable `lineTouchData` — callers
/// pass the inner [LineChart] with whatever touch behavior they
/// want. Stats-screen callers pass `LineTouchData(enabled: false)`
/// (the on-card popup was removed in this iteration; exact values
/// are read from the pinned y-axis labels).
class ScrollableTrendChart extends StatefulWidget {
  /// Theme colors used to render the pinned y-axis labels. The
  /// screen passes this in so the wrapper stays reactive to
  /// `SettingsState` (no global `OmniTheme.activeTheme` shortcut).
  final OmniThemeColors themeColors;

  /// The y-axis bounds shared by the pinned column and the plot.
  /// Pass the same `ChartAxisBounds` you would use for
  /// `LineChartData.minY/maxY/interval` so labels align.
  final ChartAxisBounds bounds;

  /// Unit label rendered next to each y-axis value (e.g. `'kg'`,
  /// `' kcal'`, `' g'`). Empty string omits the unit.
  final String unitLabel;

  /// Number of points being plotted. Used to compute the
  /// intrinsic plot width and to decide whether the scroll
  /// engages.
  final int pointCount;

  /// Builder for the inner `LineChart` (with `leftTitles`
  /// hidden). The wrapper supplies a `SizedBox` parent that
  /// pins the plot to the resolved width × [height].
  final Widget Function(double plotWidth) chartBuilder;

  /// Maximum number of data points visible in the plot at once
  /// before horizontal scroll engages. The per-point slot width
  /// is derived as `max(28, viewportWidth / maxVisiblePoints)` so
  /// the chart scales to the available card width. Defaults to
  /// [kScrollableTrendMaxVisiblePoints] (8).
  final int maxVisiblePoints;

  /// Optional override for the chart height. Defaults to
  /// [kScrollableTrendChartHeight].
  final double height;

  const ScrollableTrendChart({
    super.key,
    required this.themeColors,
    required this.bounds,
    required this.unitLabel,
    required this.pointCount,
    required this.chartBuilder,
    this.maxVisiblePoints = kScrollableTrendMaxVisiblePoints,
    this.height = kScrollableTrendChartHeight,
  });

  @override
  State<ScrollableTrendChart> createState() => _ScrollableTrendChartState();
}

/// Standard on-card chart height. Kept here so the wrapper owns
/// its vertical footprint and callers do not have to import
/// private constants from `stats_screen.dart`.
const double kScrollableTrendChartHeight = 120.0;

class _ScrollableTrendChartState extends State<ScrollableTrendChart> {
  final ScrollController _controller = ScrollController();
  // Track whether we've already jumped to the newest point so
  // we don't fight the user's drag (e.g. if they scroll back
  // manually, we don't yank the view to the right again).
  bool _hasJumpedToNewest = false;

  @override
  void initState() {
    super.initState();
    // The newest-first jump is scheduled after the first frame
    // because the controller's position is only attached once
    // the inner SingleChildScrollView builds, and the position's
    // viewport/content dimensions are computed during the first
    // layout pass. addPostFrameCallback fires after that pass.
    WidgetsBinding.instance.addPostFrameCallback(_jumpToNewestIfReady);
  }

  @override
  void didUpdateWidget(covariant ScrollableTrendChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the dataset changed (e.g. more points added), allow the
    // jump-once behavior to fire again on the next frame so the
    // user always opens the chart looking at the newest point
    // even after the data shifts.
    if (oldWidget.pointCount != widget.pointCount) {
      _hasJumpedToNewest = false;
      WidgetsBinding.instance.addPostFrameCallback(_jumpToNewestIfReady);
    }
  }

  /// Jump the controller to its newest point (right edge) when
  /// the position has valid content dimensions. Idempotent — a
  /// `_hasJumpedToNewest` flag prevents fighting user drags.
  void _jumpToNewestIfReady(Duration _) {
    if (!mounted) return;
    if (_hasJumpedToNewest) return;
    if (!_controller.hasClients) {
      // Controller not attached yet — try again next frame.
      WidgetsBinding.instance.addPostFrameCallback(_jumpToNewestIfReady);
      return;
    }
    final position = _controller.position;
    if (!position.hasContentDimensions) {
      // Layout still computing dimensions — try again next frame.
      WidgetsBinding.instance.addPostFrameCallback(_jumpToNewestIfReady);
      return;
    }
    if (position.maxScrollExtent <= 0) {
      // Nothing to scroll to (sparse data fits viewport) — done.
      _hasJumpedToNewest = true;
      return;
    }
    _controller.jumpTo(position.maxScrollExtent);
    _hasJumpedToNewest = true;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Pinned y-axis label column. Width is fixed; height
        // matches the plot. Padding mirrors the chart's
        // `reservedSize` so the min/max labels line up with the
        // plot's top/bottom gridlines.
        SizedBox(
          width: kScrollableTrendPinnedAxisWidth,
          height: widget.height,
          child: _PinnedYAxis(
            bounds: widget.bounds,
            unitLabel: widget.unitLabel,
            themeColors: widget.themeColors,
            chartHeight: widget.height,
          ),
        ),
        // Scrollable plot. The inner [SingleChildScrollView]
        // owns the horizontal axis; the surrounding
        // [Expanded] flexes it to fill the card width minus the
        // pinned column.
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final viewportWidth = constraints.maxWidth;
              // Per-point slot width is derived from the viewport
              // and the configured maxVisiblePoints so the chart
              // shows exactly [maxVisiblePoints] points at a time
              // when pointCount exceeds it. Floor at
              // kScrollableTrendMinPerPointWidth so date labels
              // stay legible on narrow viewports.
              final perPointWidth = viewportWidth <= 0
                  ? kScrollableTrendMinPerPointWidth
                  : (viewportWidth / widget.maxVisiblePoints)
                      .clamp(kScrollableTrendMinPerPointWidth, double.infinity);
              final scrollable = widget.pointCount > widget.maxVisiblePoints;
              // Compute natural plot width. For scrollable data (pointCount >
              // maxVisiblePoints), add horizontal margins to prevent edge
              // points and labels from clipping (D-4). For sparse non-scrollable
              // data, no margins needed (data sits in viewport).
              final horizontalMargin =
                  scrollable ? kScrollableTrendHorizontalMargin : 0.0;
              final naturalWidth =
                  widget.pointCount * perPointWidth + 2 * horizontalMargin;
              final plotWidth = naturalWidth > viewportWidth
                  ? naturalWidth
                  : viewportWidth;

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                controller: scrollable ? _controller : null,
                physics: scrollable
                    ? const AlwaysScrollableScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                child: SizedBox(
                  width: plotWidth,
                  height: widget.height,
                  child: scrollable
                      ? Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: kScrollableTrendHorizontalMargin,
                          ),
                          child: widget.chartBuilder(plotWidth -
                              2 * kScrollableTrendHorizontalMargin),
                        )
                      : widget.chartBuilder(plotWidth),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Width reserved for the pinned y-axis label column. Wide
/// enough for a 4-digit value + unit (`'1234 kg'`) at 9px.
const double kScrollableTrendPinnedAxisWidth = 64.0;

/// The static label column that replaces fl_chart's `leftTitles`.
/// Renders the same y-axis values the chart uses (min, min+1*interval,
/// …, max) so the labels stay aligned with the plot as the user
/// scrolls horizontally.
class _PinnedYAxis extends StatelessWidget {
  final ChartAxisBounds bounds;
  final String unitLabel;
  final OmniThemeColors themeColors;
  final double chartHeight;

  const _PinnedYAxis({
    required this.bounds,
    required this.unitLabel,
    required this.themeColors,
    required this.chartHeight,
  });

  @override
  Widget build(BuildContext context) {
    // Build the same value list the chart would draw. We add a
    // small epsilon when reading the value back so the renderer
    // hits the same bucket the chart picked (fl_chart's
    // SideTitleWidget is fed the *raw* value, not a bucketed
    // integer — the same yInterval that drives grid lines drives
    // the labels, so the labels render at min, min+interval,
    // …, max).
    final values = <double>[];
    for (double v = bounds.min; v <= bounds.max + bounds.interval / 2; v += bounds.interval) {
      values.add(v);
      if (values.length > 12) break; // hard cap to avoid runaway loops
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final v in values.reversed)
                Padding(
                  // Mirror the chart's y-axis label padding so the
                  // values visually align with the gridlines.
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    // Bare numeric value, no unit. Unit appears once
                    // in the dedicated position below the labels (D-3).
                    v.toStringAsFixed(0),
                    style: TextStyle(
                      fontSize: 9,
                      color: themeColors.textMuted,
                    ),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                  ),
                ),
            ],
          ),
        ),
        // Unit label appears exactly once per chart, below all y-axis
        // values (D-3: shared unit display).
        if (unitLabel.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 4, top: 4),
            child: Text(
              unitLabel,
              style: TextStyle(
                fontSize: 9,
                color: themeColors.textMuted,
              ),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
            ),
          ),
      ],
    );
  }
}
