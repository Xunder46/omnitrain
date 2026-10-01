import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/constants/omni_theme.dart';
import '../../core/models/exercise_metric.dart';
import '../../core/services/stats_progress_service.dart';
import '../../core/utils/chart_axis_helper.dart';
import '../../core/utils/date_utils.dart';
import '../../state/settings/settings_state.dart';
import '../../state/workout/workout_state.dart';
import '../../widgets/chart/edge_aware_date_label.dart';
import '../../widgets/layout/omni_back_header.dart';
import '../../widgets/layout/omni_card_header.dart';
import '../../widgets/layout/omni_surface.dart';
import 'widgets/native_value_format.dart';
import 'widgets/scrollable_trend_chart.dart';
import 'widgets/stats_pill.dart';

/// How many of the most recent training days the history list shows. The chart
/// above it carries the whole series, so the list is a readout rather than a
/// second trend.
const int kRecentSessionCount = 20;

/// One exercise's full history: its all-time best on the metric its section
/// reads it by, that metric's trend over every training day, and the recent
/// days with their values.
///
/// Reached from a Records & Trends entry, and owned here so both screens read
/// one exercise's history the same way.
class ExerciseProgressScreen extends StatefulWidget {
  final WorkoutState workoutState;
  final SettingsState settingsState;
  final String exerciseId;

  const ExerciseProgressScreen({
    super.key,
    required this.workoutState,
    required this.settingsState,
    required this.exerciseId,
  });

  @override
  State<ExerciseProgressScreen> createState() => _ExerciseProgressScreenState();
}

class _ExerciseProgressScreenState extends State<ExerciseProgressScreen> {
  static const double _kBottomAxisReservedSize = 20;

  bool _isLoading = true;
  ExerciseMetricSummary? _summary;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    try {
      final service = StatsProgressService(widget.workoutState.repository);
      final summaries = await service.computeExerciseMetrics();
      ExerciseMetricSummary? summary;
      for (final candidate in summaries) {
        if (candidate.exerciseId == widget.exerciseId) {
          summary = candidate;
          break;
        }
      }

      if (!mounted) return;
      setState(() {
        _summary = summary;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.settingsState,
      builder: (context, _) {
        final themeColors = OmniTheme.colorsForTheme(
          widget.settingsState.appTheme,
        );
        final summary = _summary;

        return Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,
          extendBodyBehindAppBar: true,
          appBar: OmniBackHeader(
            title: 'Exercise Progress',
            subtitle: summary?.name,
          ),
          body: SafeArea(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                    children: summary == null
                        ? [_buildEmptyState(context, themeColors)]
                        : _buildContent(context, themeColors, summary),
                  ),
          ),
        );
      },
    );
  }

  List<Widget> _buildContent(
    BuildContext context,
    OmniThemeColors themeColors,
    ExerciseMetricSummary summary,
  ) {
    final children = <Widget>[
      const OmniCardHeader(title: 'ALL TIME'),
      _buildBestCard(context, themeColors, summary),
    ];

    if (summary.points.isNotEmpty) {
      children.add(const SizedBox(height: 24));
      children.add(const OmniCardHeader(title: 'TREND'));
      children.add(
        OmniSurface(
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
          child: _buildChart(themeColors, summary),
        ),
      );
    }

    final recent = summary.points.reversed
        .take(kRecentSessionCount)
        .toList(growable: false);
    if (recent.isNotEmpty) {
      children.add(const SizedBox(height: 24));
      children.add(const OmniCardHeader(title: 'RECENT SESSIONS'));
      children.add(_buildHistory(context, themeColors, summary, recent));
    }

    return children;
  }

  Widget _buildBestCard(
    BuildContext context,
    OmniThemeColors themeColors,
    ExerciseMetricSummary summary,
  ) {
    final theme = Theme.of(context);
    final secondaryLabel = _secondaryLabel(summary.best.secondaryMetric);
    final secondary = formatNativeSecondary(summary.best, widget.settingsState);

    return OmniSurface(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: StatsPill(
              label: 'Best',
              value: formatNativeValue(summary.best, widget.settingsState),
              themeColors: themeColors,
              theme: theme,
            ),
          ),
          if (secondary != null && secondaryLabel != null) ...[
            const SizedBox(width: 16),
            Expanded(
              child: StatsPill(
                label: secondaryLabel,
                value: secondary,
                themeColors: themeColors,
                theme: theme,
              ),
            ),
          ],
          const SizedBox(width: 16),
          Expanded(
            child: StatsPill(
              label: 'Sessions',
              value: summary.sessionCount.toString(),
              themeColors: themeColors,
              theme: theme,
            ),
          ),
        ],
      ),
    );
  }

  /// The name a [NativeValue]'s second figure reads under. It is the metric
  /// that names it, not the screen.
  static String? _secondaryLabel(NativeMetric? metric) {
    switch (metric) {
      case NativeMetric.duration:
        return 'Total hold';
      case NativeMetric.roundMinutes:
        return 'Total time';
      case NativeMetric.estimatedOneRepMax:
      case NativeMetric.reps:
      case NativeMetric.pace:
      case NativeMetric.hold:
      case NativeMetric.rounds:
      case null:
        return null;
    }
  }

  Widget _buildChart(
    OmniThemeColors themeColors,
    ExerciseMetricSummary summary,
  ) {
    final metric = summary.best.metric;
    final points = summary.points;
    final dates = points
        .map((p) => DateTime.fromMillisecondsSinceEpoch(p.dayMs))
        .toList(growable: false);
    final values = points
        .map(
          (p) => nativeMetricDisplayValue(
            p.value.metric,
            p.value.value,
            widget.settingsState,
          ),
        )
        .toList(growable: false);

    // A single point has no trend to draw, so it reads as one figure rather
    // than a chart with one marker on it.
    if (values.length == 1) {
      return _buildSinglePointCard(
        themeColors: themeColors,
        label: formatNativeValue(points.first.value, widget.settingsState),
        date: dates.first,
      );
    }

    final bounds = ChartAxisHelper.computeBounds(values);
    final spots = List.generate(
      values.length,
      (i) => FlSpot(i.toDouble(), values[i]),
    );

    return ScrollableTrendChart(
      themeColors: themeColors,
      bounds: bounds,
      unitLabel: nativeMetricUnitLabel(metric, widget.settingsState),
      pointCount: points.length,
      chartBuilder: (plotWidth) {
        return LineChart(
          LineChartData(
            minX: 0,
            maxX: (points.length - 1).toDouble(),
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
                  reservedSize: _kBottomAxisReservedSize,
                  interval: 1,
                  getTitlesWidget: (value, meta) {
                    final idx = value.round();
                    if (idx < 0 || idx >= dates.length) {
                      return const SizedBox.shrink();
                    }
                    if (!ChartAxisHelper.shouldShowDateLabel(
                      idx,
                      dates.length,
                    )) {
                      return const SizedBox.shrink();
                    }
                    return buildEdgeAwareDateLabel(
                      meta: meta,
                      text: ChartAxisHelper.formatDateLabel(dates[idx]),
                      style: TextStyle(
                        fontSize: 9,
                        color: themeColors.textMuted,
                      ),
                      isFirst: idx == 0,
                      isLast: idx == dates.length - 1,
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

  Widget _buildSinglePointCard({
    required OmniThemeColors themeColors,
    required String label,
    required DateTime date,
  }) {
    final theme = Theme.of(context);

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
            '$label · ${OmniDateUtils.formatShort(date)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: OmniTheme.colors.textDominant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '1 session — log more to see a trend',
            style: theme.textTheme.labelSmall?.copyWith(
              color: themeColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistory(
    BuildContext context,
    OmniThemeColors themeColors,
    ExerciseMetricSummary summary,
    List<ExerciseMetricPoint> recent,
  ) {
    final theme = Theme.of(context);

    return OmniSurface(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final point in recent)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      OmniDateUtils.formatShort(
                        DateTime.fromMillisecondsSinceEpoch(point.dayMs),
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: OmniTheme.colors.textDominant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatNativeValue(point.value, widget.settingsState),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: themeColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, OmniThemeColors themeColors) {
    final theme = Theme.of(context);

    return OmniSurface(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          Icon(
            Icons.show_chart,
            size: 48,
            color: themeColors.textMuted.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No history for this exercise',
            style: theme.textTheme.titleMedium?.copyWith(
              color: OmniTheme.colors.textDominant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Log it in a completed session to see its progress here.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: themeColors.textMuted,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
