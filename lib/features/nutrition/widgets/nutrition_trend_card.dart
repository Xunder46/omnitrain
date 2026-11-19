import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/omni_theme.dart';
import '../../../core/models/stats_progress.dart';
import '../../../core/utils/chart_axis_helper.dart';
import '../../../widgets/chart/chart_primitives.dart';
import '../../../widgets/chart/edge_aware_date_label.dart';
import '../../../widgets/chart/scrollable_trend_chart.dart';
import '../../../widgets/common/omni_empty_state.dart';
import '../../../widgets/layout/omni_surface.dart';

/// Which of the two nutrition trends a [NutritionTrendCard] plots.
enum NutritionTrendView { calories, macros }

/// One nutrition trend card: a scrollable trend chart for the given [view]
/// plus its legend row. The full-history nutrition screen stacks one card per
/// view — Calories above Macros — so both trends are visible at once, with no
/// toggle. With no logged day the card is the shared `OmniEmptyState` instead
/// of a flat line at zero (S-2803), whichever view it was asked for.
class NutritionTrendCard extends StatelessWidget {
  /// The plotted days, oldest first.
  final List<NutritionTrendPoint> trend;

  /// Saved nutrition targets projected onto the trend's x-axis. `null` means
  /// no target was ever saved, and the dashed target line is not drawn.
  final NutritionAdherence? adherence;

  final OmniThemeColors themeColors;

  /// Which trend this card plots.
  final NutritionTrendView view;

  const NutritionTrendCard({
    super.key,
    required this.trend,
    required this.adherence,
    required this.themeColors,
    required this.view,
  });

  /// Height of the legend row below the chart.
  static const double _kNutritionLegendRowHeight = 24;
  static const double _kNutritionLegendGap = 8;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OmniSurface(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (trend.isEmpty)
            const OmniEmptyState(
              compact: true,
              title: 'No data yet',
              hint: 'Log food to see your trend.',
            )
          else if (trend.length >= 2) ...[
            if (view == NutritionTrendView.calories)
              _buildCaloriesChart(themeColors, trend)
            else
              _buildMacrosChart(theme, themeColors, trend),
            const SizedBox(height: _kNutritionLegendGap),
            SizedBox(
              height: _kNutritionLegendRowHeight,
              child: _buildNutritionLegend(theme, themeColors),
            ),
          ] else
          // S-004: exactly 1 logged day → inline single-point card.
          if (view == NutritionTrendView.calories)
            _buildSingleNutritionCaloriesPoint(
              theme: theme,
              themeColors: themeColors,
              point: trend.first,
            )
          else
            _buildSingleNutritionMacrosPoint(
              theme: theme,
              themeColors: themeColors,
              point: trend.first,
            ),
        ],
      ),
    );
  }

  // ── Nutrition: calories chart ─────────────────────────────

  Widget _buildCaloriesChart(
    OmniThemeColors themeColors,
    List<NutritionTrendPoint> trend,
  ) {
    final values = trend.map((p) => p.calories.toDouble()).toList();
    final bounds = ChartAxisHelper.computeBounds(values);
    final spots = List.generate(
      trend.length,
      (i) => FlSpot(i.toDouble(), trend[i].calories.toDouble()),
    );

    // Dashed target line. Steps at every saved target change —
    // each `NutritionAdherenceTargetPoint` extends forward to
    // the next point. We project the steps onto the actuals'
    // x-axis (one y-value per actuals index) and let fl_chart
    // draw the dashed segments between them. Empty when no
    // target has ever been saved.
    final targetSeries = _buildTargetCaloriesSeries(themeColors, trend);

    return ScrollableTrendChart(
      themeColors: themeColors,
      bounds: bounds,
      unitLabel: 'kcal',
      pointCount: trend.length,
      chartBuilder: (plotWidth) {
        return LineChart(
          LineChartData(
            minX: 0,
            maxX: (trend.length - 1).toDouble(),
            minY: bounds.min,
            maxY: bounds.max,
            lineTouchData: const LineTouchData(enabled: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false, reservedSize: 0),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: kChartBottomAxisReservedSize,
                  interval: 1,
                  getTitlesWidget: (value, meta) {
                    final idx = value.round();
                    if (idx < 0 || idx >= trend.length) {
                      return const SizedBox.shrink();
                    }
                    if (!ChartAxisHelper.shouldShowDateLabel(
                      idx,
                      trend.length,
                    )) {
                      return const SizedBox.shrink();
                    }
                    return buildEdgeAwareDateLabel(
                      meta: meta,
                      text: ChartAxisHelper.formatDateLabel(trend[idx].date),
                      style: TextStyle(
                        fontSize: 9,
                        color: themeColors.textMuted,
                      ),
                      isFirst: idx == 0,
                      isLast: idx == trend.length - 1,
                    );
                  },
                ),
              ),
            ),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: themeColors.divider, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            lineBarsData: [
              // Target line first so the actuals draw on top.
              // `dotData.show: false` keeps the dashed line clean.
              ?targetSeries,
              LineChartBarData(
                spots: spots,
                color: themeColors.primary,
                isCurved: true,
                curveSmoothness: 0.3,
                barWidth: 2,
                isStrokeCapRound: true,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (p, x, data, i) => FlDotCirclePainter(
                    radius: 3,
                    color: themeColors.primary,
                    strokeWidth: 1.5,
                    strokeColor: themeColors.surface,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  color: themeColors.primary.withAlpha(25),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Projects the piecewise `NutritionAdherenceTargetPoint`
  /// list onto the actuals' x-axis (one y-value per actuals
  /// index) and returns a dashed `LineChartBarData` ready to
  /// drop into the calories chart's `lineBarsData`. Returns
  /// `null` when no target has ever been saved (so the dashed
  /// line is not drawn at all).
  LineChartBarData? _buildTargetCaloriesSeries(
    OmniThemeColors themeColors,
    List<NutritionTrendPoint> trend,
  ) {
    final targetLine = adherence?.targetLine ?? const [];
    if (targetLine.isEmpty) return null;
    final spots = <FlSpot>[];
    var currentTarget = targetLine.first;
    var currentTargetIdx = 0;
    for (var i = 0; i < trend.length; i++) {
      // Find the most recent target whose date is on or before
      // this actuals day.
      while (currentTargetIdx < targetLine.length - 1 &&
          !targetLine[currentTargetIdx + 1].date.isAfter(trend[i].date)) {
        currentTargetIdx++;
        currentTarget = targetLine[currentTargetIdx];
      }
      spots.add(FlSpot(i.toDouble(), currentTarget.calories));
    }
    return LineChartBarData(
      spots: spots,
      color: themeColors.primary.withAlpha(120),
      isCurved: false,
      barWidth: 1.5,
      isStrokeCapRound: true,
      dashArray: const [4, 4],
      dotData: FlDotData(show: false),
      belowBarData: BarAreaData(show: false),
    );
  }

  /// Same as [_buildTargetCaloriesSeries] but for the macros
  /// view: returns up to three dashed `LineChartBarData` for
  /// protein, carbs, and fat. Empty list when no target has
  /// ever been saved.
  List<LineChartBarData> _buildTargetMacroSeries(
    OmniThemeColors themeColors,
    List<NutritionTrendPoint> trend,
  ) {
    final targetLine = adherence?.targetLine ?? const [];
    if (targetLine.isEmpty) return const [];
    final macroColors = themeColors.macroChart;
    final series = <_MacroTargetSeries>[];
    void seriesFor({
      required Color color,
      required double Function(NutritionAdherenceTargetPoint) value,
    }) {
      final spots = <FlSpot>[];
      var currentTarget = targetLine.first;
      var currentTargetIdx = 0;
      for (var i = 0; i < trend.length; i++) {
        while (currentTargetIdx < targetLine.length - 1 &&
            !targetLine[currentTargetIdx + 1].date.isAfter(trend[i].date)) {
          currentTargetIdx++;
          currentTarget = targetLine[currentTargetIdx];
        }
        spots.add(FlSpot(i.toDouble(), value(currentTarget)));
      }
      series.add(_MacroTargetSeries(color: color, spots: spots));
    }

    seriesFor(color: macroColors.protein, value: (t) => t.protein);
    seriesFor(color: macroColors.carbs, value: (t) => t.carbs);
    seriesFor(color: macroColors.fat, value: (t) => t.fat);
    return [
      for (final s in series)
        LineChartBarData(
          spots: s.spots,
          color: s.color.withAlpha(120),
          isCurved: false,
          barWidth: 1.5,
          isStrokeCapRound: true,
          dashArray: const [4, 4],
          dotData: FlDotData(show: false),
          belowBarData: BarAreaData(show: false),
        ),
    ];
  }

  // ── Nutrition: macros chart (3 lines + legend) ───────────────────────────

  Widget _buildMacrosChart(
    ThemeData theme,
    OmniThemeColors themeColors,
    List<NutritionTrendPoint> trend,
  ) {
    final macroColors = themeColors.macroChart;
    final proteinValues = trend.map((p) => p.protein.toDouble()).toList();
    final carbsValues = trend.map((p) => p.carbs.toDouble()).toList();
    final fatValues = trend.map((p) => p.fat.toDouble()).toList();

    // Compute shared y-bounds across the three series so the
    // lines live on a single scale. Floors are per-line so a
    // zero-only series still gets a visible range.
    final allValues = [...proteinValues, ...carbsValues, ...fatValues];
    final bounds = allValues.every((v) => v == 0)
        ? const ChartAxisBounds(min: 0, max: 1, interval: 1)
        : ChartAxisHelper.computeBounds(allValues);

    LineChartBarData series({
      required List<double> values,
      required Color color,
    }) {
      final spots = <FlSpot>[];
      for (var i = 0; i < values.length; i++) {
        spots.add(FlSpot(i.toDouble(), values[i]));
      }
      return LineChartBarData(
        spots: spots,
        color: color,
        isCurved: true,
        curveSmoothness: 0.3,
        barWidth: 2,
        isStrokeCapRound: true,
        dotData: FlDotData(
          show: true,
          getDotPainter: (p, x, data, i) => FlDotCirclePainter(
            radius: 3,
            color: color,
            strokeWidth: 1.5,
            strokeColor: themeColors.surface,
          ),
        ),
        belowBarData: BarAreaData(show: false),
      );
    }

    return ScrollableTrendChart(
      themeColors: themeColors,
      bounds: bounds,
      unitLabel: 'g',
      pointCount: trend.length,
      chartBuilder: (plotWidth) {
        return LineChart(
          LineChartData(
            minX: 0,
            maxX: (trend.length - 1).toDouble(),
            minY: bounds.min,
            maxY: bounds.max,
            lineTouchData: const LineTouchData(enabled: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false, reservedSize: 0),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: kChartBottomAxisReservedSize,
                  interval: 1,
                  getTitlesWidget: (value, meta) {
                    final idx = value.round();
                    if (idx < 0 || idx >= trend.length) {
                      return const SizedBox.shrink();
                    }
                    if (!ChartAxisHelper.shouldShowDateLabel(
                      idx,
                      trend.length,
                    )) {
                      return const SizedBox.shrink();
                    }
                    return buildEdgeAwareDateLabel(
                      meta: meta,
                      text: ChartAxisHelper.formatDateLabel(trend[idx].date),
                      style: TextStyle(
                        fontSize: 9,
                        color: themeColors.textMuted,
                      ),
                      isFirst: idx == 0,
                      isLast: idx == trend.length - 1,
                    );
                  },
                ),
              ),
            ),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: themeColors.divider, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            lineBarsData: [
              // Target lines first (drawn behind the actuals so
              // they read as a baseline reference, not as data).
              ..._buildTargetMacroSeries(themeColors, trend),
              // NOTE: the carbs line plots **total** carbs grams
              // (not net carbs), matching the home strip's "total
              // carbs for blue" semantics.
              series(values: proteinValues, color: macroColors.protein),
              series(values: carbsValues, color: macroColors.carbs),
              series(values: fatValues, color: macroColors.fat),
            ],
          ),
        );
      },
    );
  }

  // ── Nutrition: single-point fallback (S-004) ─────────────────────────────

  Widget _buildSingleNutritionCaloriesPoint({
    required ThemeData theme,
    required OmniThemeColors themeColors,
    required NutritionTrendPoint point,
  }) {
    return buildSinglePointCard(
      theme: theme,
      themeColors: themeColors,
      label: 'Calories:',
      value: '${point.calories} kcal',
      date: point.date,
    );
  }

  Widget _buildSingleNutritionMacrosPoint({
    required ThemeData theme,
    required OmniThemeColors themeColors,
    required NutritionTrendPoint point,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: themeColors.divider.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'P ${point.protein} g · C ${point.carbs} g · F ${point.fat} g',
            style: theme.textTheme.bodySmall?.copyWith(
              color: OmniTheme.colors.textDominant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '1 day — log more to see a trend',
            style: theme.textTheme.labelSmall?.copyWith(
              color: themeColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  /// Build the card's legend row. Carries the card's view's
  /// macro / calorie markers plus a "Target"
  /// marker whenever the adherence series has a target
  /// line. The dashed line is rendered with a 2-pixel solid
  /// swatch followed by a 2-pixel gap so the legend swatch
  /// matches the on-chart dash pattern.
  Widget _buildNutritionLegend(ThemeData theme, OmniThemeColors themeColors) {
    final macroColors = themeColors.macroChart;
    final hasTarget = (adherence?.targetLine.isNotEmpty ?? false);
    final List<Widget> items;
    if (view == NutritionTrendView.calories) {
      items = [
        buildLegendItem(
          theme,
          themeColors.primary,
          'Calories (kcal)',
          themeColors,
        ),
        if (hasTarget)
          _buildDashedLegendItem(
            theme,
            themeColors.primary.withAlpha(120),
            // The target in effect on the latest day, as the Nutrition screen
            // shows it — the dashes alone never said what the line meant.
            'Target ${adherence!.targetLine.last.calories.round()} '
            'kcal',
            themeColors,
          ),
      ];
    } else {
      items = [
        buildLegendItem(theme, macroColors.protein, 'Protein (g)', themeColors),
        buildLegendItem(theme, macroColors.carbs, 'Carbs (g)', themeColors),
        buildLegendItem(theme, macroColors.fat, 'Fat (g)', themeColors),
        if (hasTarget)
          _buildDashedLegendItem(
            theme,
            themeColors.textMuted,
            'Target',
            themeColors,
          ),
      ];
    }
    // One line in a fixed-height slot: scale down rather than wrap, so the
    // legend is never clipped by the card at any width or text size.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            items[i],
          ],
        ],
      ),
    );
  }

  /// Like `buildLegendItem` but renders the swatch as a short piece of the
  /// chart's own dashed target line (same dash, gap and stroke), so the
  /// legend reads as that line rather than as dots.
  Widget _buildDashedLegendItem(
    ThemeData theme,
    Color color,
    String label,
    OmniThemeColors themeColors,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: const Size(16, 8),
          painter: _DashedLegendSwatchPainter(color: color),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: themeColors.textMuted,
          ),
        ),
      ],
    );
  }
}

/// Renders the dashed legend swatch for the nutrition target line: four
/// pixels on, four off, 1.5 pixels thick — the chart line's own
/// `dashArray: [4, 4]` and `barWidth: 1.5`, so the two read as one thing.
class _DashedLegendSwatchPainter extends CustomPainter {
  final Color color;
  _DashedLegendSwatchPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final y = size.height / 2;
    var x = 0.0;
    while (x < size.width) {
      final end = (x + 4).clamp(0, size.width).toDouble();
      canvas.drawLine(Offset(x, y), Offset(end, y), paint);
      x += 8;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLegendSwatchPainter old) =>
      old.color != color;
}

/// PR 2b macros-target-series helper. Carries the color and
/// spots for one macro's target line; projected from the
/// adherence series by `_buildTargetMacroSeries`.
class _MacroTargetSeries {
  final Color color;
  final List<FlSpot> spots;
  const _MacroTargetSeries({required this.color, required this.spots});
}
