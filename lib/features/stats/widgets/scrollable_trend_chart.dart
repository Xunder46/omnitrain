// filepath: lib/features/stats/widgets/scrollable_trend_chart.dart
import 'package:flutter/material.dart';

import '../../../core/constants/omni_theme.dart';
import '../../../core/utils/chart_axis_helper.dart';

/// Fixed per-point horizontal slot inside the scrollable plot.
/// A point is plotted at i * [perPointWidth] inside the plot's
/// intrinsic width; the scroll view's viewport then clips to a
/// portion of that. 48 gives each point a date label + a touch
/// target without crowding; for sparse data the wrapper clamps
/// to the viewport so the chart still fills the card.
const double kScrollableTrendPerPointWidth = 48.0;

/// Minimum number of points before the chart stops growing with
/// the data. The wrapper's plot width is
/// `max(viewportWidth, points * perPointWidth)` — so the scroll
/// only engages when the natural width exceeds the card. For
/// sparse data (≤ ~6 points at the default 48 px), the chart
/// fills the card cleanly with no horizontal scroll.
const int kScrollableTrendMinPointsForScroll = 8;

/// A horizontally scrollable trend chart with a pinned y-axis
/// label column. Replaces the fixed-width rendering for every
/// stats chart on [StatsScreen] (strength e1RM, strength volume,
/// cardio pace, cardio duration, nutrition calories, nutrition
/// macros).
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
/// When `points * perPointWidth ≤ viewport` the wrapper passes
/// `physics: NeverScrollableScrollPhysics()` to the inner scroll
/// view and constrains the plot width to the viewport — the
/// chart fills the card with no scroll. When `points` exceeds
/// [kScrollableTrendMinPointsForScroll] at the default
/// [kScrollableTrendPerPointWidth], the inner width grows past
/// the viewport and the chart becomes drag-scrollable.
///
/// ## Tooltips
///
/// `lineTouchData` on the inner `LineChart` is preserved. Tapping
/// a point shows the on-card tooltip as before. There is no
/// GestureDetector, modal, or sheet — the only interaction is
/// the on-card tap and the horizontal drag.
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
  /// intrinsic plot width (`points * perPointWidth`) and to
  /// decide whether the scroll engages.
  final int pointCount;

  /// Builder for the inner `LineChart` (with `leftTitles`
  /// hidden). The wrapper supplies a `SizedBox` parent that
  /// pins the plot to the resolved width × [height].
  final Widget Function(double plotWidth) chartBuilder;

  /// Per-point horizontal slot width. Defaults to
  /// [kScrollableTrendPerPointWidth]. A non-default value lets
  /// the screen pass a larger width for sparse multi-line
  /// charts where the legend is wider than the labels.
  final double perPointWidth;

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
    this.perPointWidth = kScrollableTrendPerPointWidth,
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Jump to the newest point (right edge) on the first frame
  /// after layout. We schedule this for the *next* frame so the
  /// scroll view has already computed its `maxScrollExtent`.
  void _maybeJumpToNewest() {
    if (!_controller.hasClients) return;
    if (!_controller.position.hasContentDimensions) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_controller.hasClients) return;
      _controller.jumpTo(_controller.position.maxScrollExtent);
    });
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
              // Plot width is at least the viewport, so sparse
              // data fills the card; it grows with the data so
              // dense data scrolls.
              final naturalWidth =
                  widget.pointCount * widget.perPointWidth;
              final plotWidth = naturalWidth > viewportWidth
                  ? naturalWidth
                  : viewportWidth;
              final scrollable = naturalWidth > viewportWidth;

              if (scrollable) {
                // Schedule the newest-first jump for after the
                // first layout pass so the scroll position is
                // valid.
                _maybeJumpToNewest();
              }

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                controller: scrollable ? _controller : null,
                physics: scrollable
                    ? const AlwaysScrollableScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                child: SizedBox(
                  width: plotWidth,
                  height: widget.height,
                  child: widget.chartBuilder(plotWidth),
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
        for (final v in values.reversed)
          Padding(
            // Mirror the chart's y-axis label padding so the
            // values visually align with the gridlines.
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              ChartAxisHelper.formatYAxisValue(v, unitLabel),
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
