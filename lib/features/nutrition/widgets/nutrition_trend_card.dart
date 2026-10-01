import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/omni_theme.dart';
import '../../../core/models/stats_progress.dart';
import '../../../core/utils/chart_axis_helper.dart';
import '../../../widgets/chart/chart_primitives.dart';
import '../../../widgets/chart/edge_aware_date_label.dart';
import '../../../widgets/layout/omni_surface.dart';
import '../../stats/widgets/scrollable_trend_chart.dart';

/// Segmented toggle state for the NUTRITION card. Local widget
/// state only — not persisted across sessions. The two views
/// share the same plotted-day set; switching just swaps the
/// chart area, never re-queries the repository.
enum _NutritionView { calories, macros }

/// The NUTRITION trend card: a Calories / Macros toggle over a
/// scrollable trend chart, plus the legend row.
///
/// Rendered by two hosts — the Stats screen's NUTRITION section and
/// `NutritionTrendScreen` — so both show the same card over the same
/// repository data.
class NutritionTrendCard extends StatefulWidget {
  /// The plotted days, oldest first.
  final List<NutritionTrendPoint> trend;

  /// Saved nutrition targets projected onto the trend's x-axis. `null` means
  /// no target was ever saved, and the dashed target line is not drawn.
  final NutritionAdherence? adherence;

  final OmniThemeColors themeColors;

  const NutritionTrendCard({
    super.key,
    required this.trend,
    required this.adherence,
    required this.themeColors,
  });

  @override
  State<NutritionTrendCard> createState() => _NutritionTrendCardState();
}

class _NutritionTrendCardState extends State<NutritionTrendCard> {
  /// Reserved height for the legend row that lives below the
  /// macros chart. The calories view reserves the same height
  /// with an empty `SizedBox` so toggling between the two views
  /// does not change the card's total height.
  static const double _kNutritionLegendRowHeight = 24;
  static const double _kNutritionLegendGap = 8;

  _NutritionView _nutritionView = _NutritionView.calories;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeColors = widget.themeColors;
    final trend = widget.trend;
    return OmniSurface(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildNutritionToggle(theme, themeColors),
          const SizedBox(height: 12),
          if (trend.isEmpty) ...[
            _buildEmptyNutritionChart(theme, themeColors),
            const SizedBox(height: _kNutritionLegendGap),
            SizedBox(
              height: _kNutritionLegendRowHeight,
              child: _buildNutritionLegend(theme, themeColors),
            ),
          ] else if (trend.length >= 2) ...[
            if (_nutritionView == _NutritionView.calories)
              _buildCaloriesChart(themeColors, trend)
            else
              _buildMacrosChart(theme, themeColors, trend),
            const SizedBox(height: _kNutritionLegendGap),
            // Always reserve the legend row's height so toggling
            // Calories ↔ Macros does not change the card's height.
            SizedBox(
              height: _kNutritionLegendRowHeight,
              child: _buildNutritionLegend(theme, themeColors),
            ),
          ] else
          // S-004: exactly 1 logged day → inline single-point card.
          if (_nutritionView == _NutritionView.calories)
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

  /// Segmented toggle. Uses Material 3 SegmentedButton for a
  /// unified toggle control look. Selection is local widget state —
  /// the underlying trend data is unchanged across toggles (S-003).
  Widget _buildNutritionToggle(ThemeData theme, OmniThemeColors themeColors) {
    return SegmentedButton<_NutritionView>(
      segments: const [
        ButtonSegment(value: _NutritionView.calories, label: Text('Calories')),
        ButtonSegment(value: _NutritionView.macros, label: Text('Macros')),
      ],
      selected: {_nutritionView},
      onSelectionChanged: (selection) {
        if (selection.isNotEmpty && selection.first != _nutritionView) {
          setState(() => _nutritionView = selection.first);
        }
      },
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return themeColors.primary;
          }
          return themeColors.surface;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return themeColors.surface;
          }
          return themeColors.textSecondary;
        }),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(OmniTheme.buttonUtilityRadius),
          ),
        ),
      ),
    );
  }

  // ── Nutrition: calories chart (default view) ─────────────────────────────

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
    final targetLine = widget.adherence?.targetLine ?? const [];
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
    final targetLine = widget.adherence?.targetLine ?? const [];
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

  /// Builds an empty chart showing zero values when there's no
  /// nutrition data logged. This maintains the same visual structure
  /// as the regular charts.
  Widget _buildEmptyNutritionChart(
    ThemeData theme,
    OmniThemeColors themeColors,
  ) {
    final macroColors = themeColors.macroChart;
    const emptyPointCount = 7;
    final bounds = const ChartAxisBounds(min: 0, max: 1, interval: 1);

    return ScrollableTrendChart(
      themeColors: themeColors,
      bounds: bounds,
      unitLabel: '',
      pointCount: emptyPointCount,
      chartBuilder: (plotWidth) {
        return LineChart(
          LineChartData(
            minX: 0,
            maxX: (emptyPointCount - 1).toDouble(),
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
                    if (value == 0 ||
                        value == (emptyPointCount - 1).toDouble()) {
                      return buildEdgeAwareDateLabel(
                        meta: meta,
                        // Calendar arithmetic, not `subtract(Duration(...))`
                        // — across a DST transition a Duration lands on the
                        // wrong wall-clock day. Cosmetic here (empty-state
                        // axis) but kept consistent with the service so the
                        // pattern does not get copied back out.
                        text: ChartAxisHelper.formatDateLabel(() {
                          final now = DateTime.now();
                          return DateTime(
                            now.year,
                            now.month,
                            now.day - ((emptyPointCount - 1) - value).toInt(),
                          );
                        }()),
                        style: TextStyle(
                          fontSize: 9,
                          color: themeColors.textMuted,
                        ),
                        isFirst: value == 0,
                        isLast: value == (emptyPointCount - 1).toDouble(),
                      );
                    }
                    return const SizedBox.shrink();
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
              if (_nutritionView == _NutritionView.calories)
                LineChartBarData(
                  spots: List.generate(
                    emptyPointCount,
                    (i) => FlSpot(i.toDouble(), 0),
                  ),
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
                )
              else ...[
                LineChartBarData(
                  spots: List.generate(
                    emptyPointCount,
                    (i) => FlSpot(i.toDouble(), 0),
                  ),
                  color: macroColors.protein,
                  isCurved: true,
                  curveSmoothness: 0.3,
                  barWidth: 2,
                  isStrokeCapRound: true,
                  dotData: FlDotData(show: false),
                  belowBarData: BarAreaData(show: false),
                ),
                LineChartBarData(
                  spots: List.generate(
                    emptyPointCount,
                    (i) => FlSpot(i.toDouble(), 0),
                  ),
                  color: macroColors.carbs,
                  isCurved: true,
                  curveSmoothness: 0.3,
                  barWidth: 2,
                  isStrokeCapRound: true,
                  dotData: FlDotData(show: false),
                  belowBarData: BarAreaData(show: false),
                ),
                LineChartBarData(
                  spots: List.generate(
                    emptyPointCount,
                    (i) => FlSpot(i.toDouble(), 0),
                  ),
                  color: macroColors.fat,
                  isCurved: true,
                  curveSmoothness: 0.3,
                  barWidth: 2,
                  isStrokeCapRound: true,
                  dotData: FlDotData(show: false),
                  belowBarData: BarAreaData(show: false),
                ),
              ],
            ],
          ),
        );
      },
    );
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

  /// Build the NUTRITION card's legend row. Carries the
  /// active view's macro / calorie markers plus a "Target"
  /// marker whenever the adherence series has a target
  /// line. The dashed line is rendered with a 2-pixel solid
  /// swatch followed by a 2-pixel gap so the legend swatch
  /// matches the on-chart dash pattern.
  Widget _buildNutritionLegend(ThemeData theme, OmniThemeColors themeColors) {
    final macroColors = themeColors.macroChart;
    final hasTarget = (widget.adherence?.targetLine.isNotEmpty ?? false);
    if (_nutritionView == _NutritionView.calories) {
      return Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
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
              'Target (kcal)',
              themeColors,
            ),
        ],
      );
    }
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
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
      ],
    );
  }

  /// Like `buildLegendItem` but renders the color swatch as
  /// a 2-pixel-on / 2-pixel-off dash so the legend reads as
  /// the same dashed target line the chart draws.
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
          size: const Size(12, 8),
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

/// Renders the dashed legend swatch for the nutrition
/// target line. Two pixels on, two pixels off — same dash
/// pattern the chart line uses (`dashArray: [4, 4]`).
class _DashedLegendSwatchPainter extends CustomPainter {
  final Color color;
  _DashedLegendSwatchPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final y = size.height / 2;
    // 2-pixel dashes with 2-pixel gaps, repeating across
    // the 12-pixel swatch width.
    var x = 0.0;
    while (x < size.width) {
      final end = (x + 2).clamp(0, size.width).toDouble();
      canvas.drawLine(Offset(x, y), Offset(end, y), paint);
      x += 4;
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
