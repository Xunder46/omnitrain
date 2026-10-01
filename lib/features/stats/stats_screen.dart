import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/constants/omni_theme.dart';
import '../../core/models/stats_progress.dart';
import '../../core/services/stats_progress_service.dart';
import '../../core/utils/chart_axis_helper.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/unit_formatter.dart';
import '../../state/calendar/calendar_state.dart';
import '../../state/settings/settings_state.dart';
import '../../state/workout/workout_state.dart';
import '../../widgets/layout/omni_surface.dart';
import '../../widgets/layout/omni_back_header.dart';
import '../../widgets/layout/omni_card_header.dart';
import '../../widgets/chart/edge_aware_date_label.dart';
import 'widgets/scrollable_trend_chart.dart';

/// Segmented toggle state for the NUTRITION card. Local widget
/// state only — not persisted across sessions. The two views
/// share the same plotted-day set; switching just swaps the
/// chart area, never re-queries the repository.
enum _NutritionView { calories, macros }

class StatsScreen extends StatefulWidget {
  final WorkoutState workoutState;
  final SettingsState settingsState;

  const StatsScreen({
    super.key,
    required this.workoutState,
    required this.settingsState,
  });

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  static const double _kBottomAxisReservedSize = 20;

  bool _isLoading = true;
  int _totalSessions = 0;
  int _totalDurationMs = 0;
  int _streakDays = 0;

  StatsProgressData? _progressData;
  _NutritionView _nutritionView = _NutritionView.calories;

  NutritionAdherence? _nutritionAdherence;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    try {
      final allSessions = await widget.workoutState.getAllSessions();

      // Compute all-time aggregates from completed sessions only.
      // Rolling sessions still count as completed sessions, but they do not
      // contribute to total duration to stay aligned with session-summary logic.
      int totalCount = 0;
      int totalMs = 0;
      for (final s in allSessions) {
        if (s.endedAtMs == null) continue;
        totalCount++;
        if (!s.isRolling) {
          totalMs += s.endedAtMs! - s.startedAtMs;
        }
      }

      // Reuse CalendarState streak logic — do not re-implement the calculation.
      final calendarState = CalendarState(widget.workoutState.repository);
      await calendarState.init();
      final streak = calendarState.streakDays;

      // One service instance for the whole load. The service caches its
      // history snapshot per instance, so every `compute*` call below
      // shares a single read of the repository — constructing a second
      // instance here would silently double that cost.
      final service = StatsProgressService(widget.workoutState.repository);

      // Compute progress data (e1RM trends, cardio trends, isometric trends,
      // sports trends, PRs, and the nutrition trend — all in one call so we don't
      // double-walk the repository for the same screen).
      final progressData = await service.computeProgressData();

      final adherence = await service.computeNutritionAdherence();

      if (!mounted) return;

      setState(() {
        _totalSessions = totalCount;
        _totalDurationMs = totalMs;
        _streakDays = streak;
        _progressData = progressData;
        _nutritionAdherence = adherence;
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

        return Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,
          extendBodyBehindAppBar: true,
          appBar: const OmniBackHeader(title: 'Stats'),
          body: SafeArea(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                    children: _totalSessions == 0
                        ? [_buildEmptyState(context, themeColors)]
                        : [
                            const OmniCardHeader(title: 'ALL TIME'),
                            _buildAggregateCard(context, themeColors),
                            const SizedBox(height: 24),
                            ..._buildStrengthSection(context, themeColors),
                            const SizedBox(height: 24),
                            ..._buildCardioSection(context, themeColors),
                            const SizedBox(height: 24),
                            ..._buildIsometricSection(context, themeColors),
                            const SizedBox(height: 24),
                            ..._buildSportsSection(context, themeColors),
                            const SizedBox(height: 24),
                            ..._buildNutritionSection(context, themeColors),
                          ],
                  ),
          ),
        );
      },
    );
  }

  // ── Section label ─────────────────────────────────────────────────────────

  /// Small inline label that explains which "current window"
  /// decided which exercises appear in this section. Reads as
  /// `· Off-Season Strength Block` (period) or
  /// `· Last 14 training days` (recent-days fallback). Lives
  /// in the [OmniCardHeader] actions slot of the section above
  /// the relevant card so the readout explains itself.
  Widget _buildWindowChip(
    BuildContext context,
    OmniThemeColors themeColors,
    StatsWindow window,
  ) {
    final theme = Theme.of(context);
    return Text(
      key: const Key('stats_window_chip'),
      '· ${window.label}',
      style: theme.textTheme.labelSmall?.copyWith(
        color: themeColors.textMuted,
        fontStyle: FontStyle.italic,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildAggregateCard(
    BuildContext context,
    OmniThemeColors themeColors,
  ) {
    final theme = Theme.of(context);

    return OmniSurface(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _StatsPill(
              label: 'Sessions',
              value: _totalSessions.toString(),
              themeColors: themeColors,
              theme: theme,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _StatsPill(
              label: 'Time',
              value: _formatDuration(_totalDurationMs),
              themeColors: themeColors,
              theme: theme,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _StatsPill(
              label: 'Streak',
              value: '$_streakDays d',
              themeColors: themeColors,
              theme: theme,
              trailingIcon: _streakDays >= 3
                  ? Icon(
                      Icons.local_fire_department,
                      size: 18,
                      color: themeColors.primary,
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  // ── Strength section ──────────────────────────────────────────────────────

  List<Widget> _buildStrengthSection(
    BuildContext context,
    OmniThemeColors themeColors,
  ) {
    final data = _progressData;
    final widgets = <Widget>[
      OmniCardHeader(
        title: 'STRENGTH',
        actions: [
          if (data != null) _buildWindowChip(context, themeColors, data.window),
        ],
      ),
    ];

    if (data == null || data.topLifts.isEmpty) {
      widgets.add(
        _buildSectionEmptyState(
          context,
          themeColors,
          'No strength history yet. Log your first sets to see trends here.',
        ),
      );
      return widgets;
    }

    for (final lift in data.topLifts) {
      widgets.add(_buildLiftCard(context, themeColors, lift));
      widgets.add(const SizedBox(height: 12));
    }

    if (data.recentPRs.isNotEmpty) {
      widgets.add(_buildPRList(context, themeColors, data.recentPRs));
    }

    return widgets;
  }

  Widget _buildLiftCard(
    BuildContext context,
    OmniThemeColors themeColors,
    LiftProgress lift,
  ) {
    final theme = Theme.of(context);
    final weightLabel = UnitFormatter.weightLabel(widget.settingsState);
    final e1RmDisplay = lift.e1RmTrend
        .map(
          (p) => TrendPoint(
            date: p.date,
            value: UnitFormatter.convertWeight(p.value, widget.settingsState),
          ),
        )
        .toList();
    final volumeDisplay = lift.volumeTrend
        .map(
          (p) => TrendPoint(
            date: p.date,
            value: UnitFormatter.convertWeight(p.value, widget.settingsState),
          ),
        )
        .toList();
    // Reps-axis (bodyweight) display. Convert nothing — reps are
    // already unit-free integers. The `extraWeightKg` annotation
    // (set when a bodyweight set was performed with added weight,
    // e.g. a dip belt) is preserved through to the trend chart
    // and single-point card so the user sees a "+10 kg" marker
    // on the day that used added weight. This is annotation only
    // — the reps trend never produces a kg-derived figure on a
    // reps-axis exercise (`docs/plans/stats-summary-fix-pack-plan.md`,
    // Push-Up mixed-axis bug fix).
    final repsDisplay = lift.repsTrend.toList();
    final repsHasAddedWeight = repsDisplay.any(
      (p) => (p.extraWeightKg ?? 0) > 0,
    );

    return OmniSurface(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            lift.exerciseName,
            style: theme.textTheme.titleSmall?.copyWith(
              color: OmniTheme.colors.textDominant,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (e1RmDisplay.length >= 2) ...[
            const SizedBox(height: 4),
            Text(
              'Estimated 1RM',
              style: theme.textTheme.labelSmall?.copyWith(
                color: themeColors.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            _buildTrendChart(themeColors, e1RmDisplay, label: weightLabel),
          ] else if (e1RmDisplay.length == 1) ...[
            const SizedBox(height: 8),
            _buildSinglePointCard(
              theme: theme,
              themeColors: themeColors,
              label: 'Estimated 1RM:',
              value:
                  '${e1RmDisplay.first.value.toStringAsFixed(1)} $weightLabel',
              date: e1RmDisplay.first.date,
            ),
          ],
          if (volumeDisplay.length >= 2) ...[
            const SizedBox(height: 12),
            Text(
              'Volume',
              style: theme.textTheme.labelSmall?.copyWith(
                color: themeColors.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            _buildTrendChart(themeColors, volumeDisplay, label: weightLabel),
          ] else if (volumeDisplay.length == 1) ...[
            const SizedBox(height: 8),
            _buildSinglePointCard(
              theme: theme,
              themeColors: themeColors,
              label: 'Volume:',
              value:
                  '${volumeDisplay.first.value.toStringAsFixed(0)} $weightLabel',
              date: volumeDisplay.first.date,
            ),
          ],
          if (repsDisplay.length >= 2) ...[
            const SizedBox(height: 12),
            Text(
              'Reps',
              style: theme.textTheme.labelSmall?.copyWith(
                color: themeColors.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            _buildTrendChart(themeColors, repsDisplay, label: 'reps'),
            if (repsHasAddedWeight) ...[
              const SizedBox(height: 6),
              _buildAddedWeightNote(theme, themeColors),
            ],
          ] else if (repsDisplay.length == 1) ...[
            const SizedBox(height: 8),
            _buildSinglePointCard(
              theme: theme,
              themeColors: themeColors,
              label: 'Reps:',
              value: _formatRepsValue(repsDisplay.first),
              date: repsDisplay.first.date,
            ),
          ],
        ],
      ),
    );
  }

  /// Format a single reps-axis data point's value with the
  /// optional added-weight annotation. The kg figure is rendered
  /// in the user's preferred weight unit (kg/lbs) so the
  /// annotation reads naturally next to the weight-based values
  /// on the same screen.
  String _formatRepsValue(TrendPoint point) {
    final reps = point.value.toInt();
    final extra = point.extraWeightKg;
    if (extra == null || extra <= 0) return '$reps reps';
    final converted = UnitFormatter.convertWeight(extra, widget.settingsState);
    final unit = UnitFormatter.weightLabel(widget.settingsState);
    return '$reps reps (+${_formatNumber(converted)} $unit)';
  }

  /// Small note shown beneath a multi-point reps trend chart
  /// when at least one day on the trend had added weight. The
  /// individual per-day annotation lives on the data point (the
  /// chart's tooltip) — this is the inline cue so the user
  /// knows the kg figure on this card is annotation-only, never
  /// a Total Volume contribution.
  Widget _buildAddedWeightNote(ThemeData theme, OmniThemeColors themeColors) {
    return Row(
      children: [
        Icon(Icons.info_outline, size: 14, color: themeColors.textMuted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Some sessions used added weight — annotation only, not added to volume.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: themeColors.textMuted,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTrendChart(
    OmniThemeColors themeColors,
    List<TrendPoint> points, {
    required String label,
  }) {
    final values = points.map((p) => p.value).toList();
    final bounds = ChartAxisHelper.computeBounds(values);

    final spots = List.generate(
      points.length,
      (i) => FlSpot(i.toDouble(), points[i].value),
    );

    return ScrollableTrendChart(
      themeColors: themeColors,
      bounds: bounds,
      unitLabel: label,
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
                    if (idx < 0 || idx >= points.length) {
                      return const SizedBox.shrink();
                    }
                    if (!ChartAxisHelper.shouldShowDateLabel(
                      idx,
                      points.length,
                    )) {
                      return const SizedBox.shrink();
                    }
                    return buildEdgeAwareDateLabel(
                      meta: meta,
                      text: ChartAxisHelper.formatDateLabel(points[idx].date),
                      style: TextStyle(
                        fontSize: 9,
                        color: themeColors.textMuted,
                      ),
                      isFirst: idx == 0,
                      isLast: idx == points.length - 1,
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

  Widget _buildPRList(
    BuildContext context,
    OmniThemeColors themeColors,
    List<StatsPR> prs,
  ) {
    final theme = Theme.of(context);
    final weightLabel = UnitFormatter.weightLabel(widget.settingsState);

    return OmniSurface(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent PRs',
            style: theme.textTheme.titleSmall?.copyWith(
              color: OmniTheme.colors.textDominant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          ...prs.map((pr) {
            final dateStr =
                '${OmniDateUtils.shortMonthName(pr.date.month)} ${pr.date.day},'
                ' ${pr.date.year}';
            // Reps-axis PR (bodyweight) and weight-axis PR
            // (e1RM) render differently on the right side:
            //   - `pr.reps != null` → `${reps} reps`
            //   - `pr.e1Rm != null` → `${displayE1Rm} $weightLabel`
            // Exactly one of the two is non-null on any given PR
            // (asserted in `StatsPR`).
            final String valueText;
            if (pr.reps != null) {
              valueText = '${pr.reps} reps';
            } else {
              final displayE1Rm = UnitFormatter.convertWeight(
                pr.e1Rm!,
                widget.settingsState,
              );
              valueText = '${displayE1Rm.toStringAsFixed(1)} $weightLabel';
            }
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.emoji_events_outlined,
                    size: 16,
                    color: themeColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      pr.exerciseName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: OmniTheme.colors.textDominant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    valueText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: themeColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    dateStr,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: themeColors.textMuted,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Cardio section ────────────────────────────────────────────────────────

  List<Widget> _buildCardioSection(
    BuildContext context,
    OmniThemeColors themeColors,
  ) {
    final data = _progressData;
    final widgets = <Widget>[
      OmniCardHeader(
        title: 'CARDIO',
        actions: [
          if (data != null) _buildWindowChip(context, themeColors, data.window),
        ],
      ),
    ];

    if (data == null || data.topCardio.isEmpty) {
      widgets.add(
        _buildSectionEmptyState(
          context,
          themeColors,
          'No cardio history yet. Log timed efforts to see trends here.',
        ),
      );
      return widgets;
    }

    for (final cardio in data.topCardio) {
      widgets.add(_buildCardioCard(context, themeColors, cardio));
      widgets.add(const SizedBox(height: 12));
    }

    return widgets;
  }

  // ── Isometric section ─────────────────────────────────────────────────────

  List<Widget> _buildIsometricSection(
    BuildContext context,
    OmniThemeColors themeColors,
  ) {
    final data = _progressData;
    final widgets = <Widget>[
      OmniCardHeader(
        title: 'ISOMETRIC',
        actions: [
          if (data != null) _buildWindowChip(context, themeColors, data.window),
        ],
      ),
    ];

    if (data == null || data.topIsometric.isEmpty) {
      widgets.add(
        _buildSectionEmptyState(
          context,
          themeColors,
          'No isometric history yet. Log hold exercises to see trends here.',
        ),
      );
      return widgets;
    }

    for (final drill in data.topIsometric) {
      widgets.add(_buildDrillCard(context, themeColors, drill));
      widgets.add(const SizedBox(height: 12));
    }

    return widgets;
  }

  Widget _buildDrillCard(
    BuildContext context,
    OmniThemeColors themeColors,
    DrillProgress drill,
  ) {
    final theme = Theme.of(context);

    return OmniSurface(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            drill.exerciseName,
            style: theme.textTheme.titleSmall?.copyWith(
              color: OmniTheme.colors.textDominant,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (drill.trend.length >= 2) ...[
            const SizedBox(height: 4),
            Text(
              'Duration (sec)',
              style: theme.textTheme.labelSmall?.copyWith(
                color: themeColors.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            _buildDurationChart(
              themeColors,
              drill.trend,
              unitLabel: 'sec',
              color: themeColors.primary,
            ),
          ] else if (drill.trend.length == 1) ...[
            const SizedBox(height: 8),
            _buildSingleDurationPointCard(
              theme: theme,
              themeColors: themeColors,
              point: drill.trend.first,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDurationChart(
    OmniThemeColors themeColors,
    List<CardioTrendPoint> points, {
    required String unitLabel,
    required Color color,
    double divisor = 1.0,
  }) {
    final durationValues = points
        .map((p) => p.durationSecs.toDouble() / divisor)
        .toList();
    final spots = List.generate(
      points.length,
      (i) => FlSpot(i.toDouble(), durationValues[i]),
    );

    final bounds = ChartAxisHelper.computeBounds(durationValues);

    return ScrollableTrendChart(
      themeColors: themeColors,
      bounds: bounds,
      unitLabel: unitLabel,
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
                    if (idx < 0 || idx >= points.length) {
                      return const SizedBox.shrink();
                    }
                    if (!ChartAxisHelper.shouldShowDateLabel(
                      idx,
                      points.length,
                    )) {
                      return const SizedBox.shrink();
                    }
                    return buildEdgeAwareDateLabel(
                      meta: meta,
                      text: ChartAxisHelper.formatDateLabel(points[idx].date),
                      style: TextStyle(
                        fontSize: 9,
                        color: themeColors.textMuted,
                      ),
                      isFirst: idx == 0,
                      isLast: idx == points.length - 1,
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
                belowBarData: BarAreaData(
                  show: true,
                  color: color.withAlpha(25),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSingleDurationPointCard({
    required ThemeData theme,
    required OmniThemeColors themeColors,
    required CardioTrendPoint point,
  }) {
    final secs = point.durationSecs;
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
            '$secs sec',
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

  // ── Sports section ────────────────────────────────────────────────────────

  List<Widget> _buildSportsSection(
    BuildContext context,
    OmniThemeColors themeColors,
  ) {
    final data = _progressData;
    final widgets = <Widget>[
      OmniCardHeader(
        title: 'SPORTS',
        actions: [
          if (data != null) _buildWindowChip(context, themeColors, data.window),
        ],
      ),
    ];

    if (data == null || data.topSports.isEmpty) {
      widgets.add(
        _buildSectionEmptyState(
          context,
          themeColors,
          'No sports history yet. Log sports rounds to see trends here.',
        ),
      );
      return widgets;
    }

    for (final round in data.topSports) {
      widgets.add(_buildRoundCard(context, themeColors, round));
      widgets.add(const SizedBox(height: 12));
    }

    return widgets;
  }

  Widget _buildRoundCard(
    BuildContext context,
    OmniThemeColors themeColors,
    RoundProgress round,
  ) {
    final theme = Theme.of(context);

    return OmniSurface(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            round.exerciseName,
            style: theme.textTheme.titleSmall?.copyWith(
              color: OmniTheme.colors.textDominant,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (round.trend.length >= 2) ...[
            const SizedBox(height: 4),
            Text(
              'Duration (sec)',
              style: theme.textTheme.labelSmall?.copyWith(
                color: themeColors.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            _buildDurationChart(
              themeColors,
              round.trend,
              unitLabel: 'sec',
              color: themeColors.secondary,
            ),
          ] else if (round.trend.length == 1) ...[
            const SizedBox(height: 8),
            _buildSingleDurationPointCard(
              theme: theme,
              themeColors: themeColors,
              point: round.trend.first,
            ),
          ],
        ],
      ),
    );
  }

  // ── Nutrition section (last 10-day kcal + macros trend) ──────────────────

  /// Returns the widgets for the NUTRITION section. Returns an
  /// empty list when the trend has zero logged days in the last
  /// 10 — the card hides itself in that case (S-005). S-006 (no
  /// sessions at all) is handled upstream because this method is
  /// only called in the has-sessions branch.
  List<Widget> _buildNutritionSection(
    BuildContext context,
    OmniThemeColors themeColors,
  ) {
    final trend = _progressData?.nutritionTrend ?? const [];
    return [
      const OmniCardHeader(title: 'NUTRITION'),
      _buildNutritionCard(context, themeColors, trend),
    ];
  }

  /// Reserved height for the legend row that lives below the
  /// macros chart. The calories view reserves the same height
  /// with an empty `SizedBox` so toggling between the two views
  /// does not change the card's total height.
  static const double _kNutritionLegendRowHeight = 24;
  static const double _kNutritionLegendGap = 8;

  Widget _buildNutritionCard(
    BuildContext context,
    OmniThemeColors themeColors,
    List<NutritionTrendPoint> trend,
  ) {
    final theme = Theme.of(context);
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
              _buildMacrosChart(context, theme, themeColors, trend),
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
                  reservedSize: _kBottomAxisReservedSize,
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
    final targetLine = _nutritionAdherence?.targetLine ?? const [];
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
    final targetLine = _nutritionAdherence?.targetLine ?? const [];
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
                  reservedSize: _kBottomAxisReservedSize,
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
    BuildContext context,
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
                  reservedSize: _kBottomAxisReservedSize,
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
    return _buildSinglePointCard(
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

  Widget _buildCardioCard(
    BuildContext context,
    OmniThemeColors themeColors,
    CardioProgress cardio,
  ) {
    final theme = Theme.of(context);
    final hasPace = cardio.trend.any((p) => p.paceSecPerKm != null);
    final hasDistance = cardio.trend.any(
      (p) => p.distanceM != null && p.distanceM! > 0,
    );
    final distUnit = UnitFormatter.distanceLabel(widget.settingsState);

    return OmniSurface(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            cardio.exerciseName,
            style: theme.textTheme.titleSmall?.copyWith(
              color: OmniTheme.colors.textDominant,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (hasPace && cardio.trend.length >= 2) ...[
            const SizedBox(height: 4),
            Text(
              'Pace (s/$distUnit)',
              style: theme.textTheme.labelSmall?.copyWith(
                color: themeColors.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            _buildCardioPaceChart(themeColors, cardio.trend, distUnit),
            if (hasDistance) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  _buildLegendItem(
                    theme,
                    themeColors.secondary,
                    'Pace (s/$distUnit)',
                    themeColors,
                  ),
                  _buildLegendItem(
                    theme,
                    themeColors.primary,
                    'Distance ($distUnit)',
                    themeColors,
                  ),
                  if (_hasEstimatedDay(cardio.trend))
                    _buildLegendItem(
                      theme,
                      themeColors.surface,
                      'est.',
                      themeColors,
                      outline: themeColors.textMuted,
                    ),
                ],
              ),
            ],
          ] else if (cardio.trend.length >= 2) ...[
            const SizedBox(height: 4),
            Text(
              'Duration (min)',
              style: theme.textTheme.labelSmall?.copyWith(
                color: themeColors.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            _buildDurationChart(
              themeColors,
              cardio.trend,
              unitLabel: 'min',
              color: themeColors.secondary,
              divisor: 60.0,
            ),
          ] else if (cardio.trend.length == 1) ...[
            const SizedBox(height: 8),
            _buildSingleCardioPointCard(
              theme: theme,
              themeColors: themeColors,
              point: cardio.trend.first,
              distUnit: distUnit,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCardioPaceChart(
    OmniThemeColors themeColors,
    List<CardioTrendPoint> points,
    String distUnit,
  ) {
    final pacePoints = <FlSpot>[];
    final paceValues = <double>[];
    final distanceByIndex = <int, double>{};
    for (var i = 0; i < points.length; i++) {
      final pace = points[i].paceSecPerKm;
      if (pace != null) {
        final displayPace = _paceForDisplay(pace, distUnit);
        pacePoints.add(FlSpot(i.toDouble(), displayPace));
        paceValues.add(displayPace);
      }

      final distanceM = points[i].distanceM;
      if (distanceM != null && distanceM > 0) {
        distanceByIndex[i] = _distanceForDisplay(distanceM, distUnit);
      }
    }

    if (pacePoints.isEmpty) return const SizedBox.shrink();

    final bounds = ChartAxisHelper.computeBounds(paceValues);
    final unitLabel = 's/$distUnit';

    final distanceValues = distanceByIndex.values.toList();
    final distanceScale = distanceValues.isEmpty
        ? null
        : _LinearScale.fromSourceAndTarget(
            sourceMin: distanceValues.reduce((a, b) => a < b ? a : b),
            sourceMax: distanceValues.reduce((a, b) => a > b ? a : b),
            targetMin: bounds.min,
            targetMax: bounds.max,
          );

    final distancePoints = <FlSpot>[];
    if (distanceScale != null) {
      for (final entry in distanceByIndex.entries) {
        distancePoints.add(
          FlSpot(entry.key.toDouble(), distanceScale.toTarget(entry.value)),
        );
      }
    }

    return ScrollableTrendChart(
      themeColors: themeColors,
      bounds: bounds,
      unitLabel: unitLabel,
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
                    if (idx < 0 || idx >= points.length) {
                      return const SizedBox.shrink();
                    }
                    if (!ChartAxisHelper.shouldShowDateLabel(
                      idx,
                      points.length,
                    )) {
                      return const SizedBox.shrink();
                    }
                    return buildEdgeAwareDateLabel(
                      meta: meta,
                      text: ChartAxisHelper.formatDateLabel(points[idx].date),
                      style: TextStyle(
                        fontSize: 9,
                        color: themeColors.textMuted,
                      ),
                      isFirst: idx == 0,
                      isLast: idx == points.length - 1,
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
                spots: pacePoints,
                color: themeColors.secondary,
                isCurved: true,
                curveSmoothness: 0.3,
                barWidth: 2,
                isStrokeCapRound: true,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (p, x, data, i) => _cardioDotPainter(
                    points,
                    p,
                    themeColors.secondary,
                    themeColors,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  color: themeColors.secondary.withAlpha(25),
                ),
              ),
              if (distancePoints.isNotEmpty)
                LineChartBarData(
                  spots: distancePoints,
                  color: themeColors.primary,
                  isCurved: true,
                  curveSmoothness: 0.3,
                  barWidth: 2,
                  isStrokeCapRound: true,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (p, x, data, i) => _cardioDotPainter(
                      points,
                      p,
                      themeColors.primary,
                      themeColors,
                    ),
                  ),
                  belowBarData: BarAreaData(show: false),
                ),
            ],
          ),
        );
      },
    );
  }

  /// True when any day in [trend] carries a distance the watch estimated, so
  /// the card needs the `est.` legend item (D-317).
  bool _hasEstimatedDay(List<CardioTrendPoint> trend) =>
      trend.any((point) => point.distanceEstimated);

  /// The dot for one cardio spot: an estimated day is drawn hollow — the
  /// series colour on the stroke, the surface on the fill — and every other
  /// day keeps the filled dot it always had.
  ///
  /// The estimate flag is looked up through the spot's `x`, its trend index,
  /// because a series may hold fewer spots than the trend has days.
  FlDotPainter _cardioDotPainter(
    List<CardioTrendPoint> trend,
    FlSpot spot,
    Color seriesColor,
    OmniThemeColors themeColors,
  ) {
    final index = spot.x.round();
    final estimated =
        index >= 0 && index < trend.length && trend[index].distanceEstimated;
    return FlDotCirclePainter(
      radius: 3,
      color: estimated ? themeColors.surface : seriesColor,
      strokeWidth: 1.5,
      strokeColor: estimated ? seriesColor : themeColors.surface,
    );
  }

  Widget _buildLegendItem(
    ThemeData theme,
    Color color,
    String label,
    OmniThemeColors themeColors, {
    Color? outline,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
            border: outline == null ? null : Border.all(color: outline),
          ),
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

  /// Deliberate single-point card for a lift metric (e1RM or volume).
  Widget _buildSinglePointCard({
    required ThemeData theme,
    required OmniThemeColors themeColors,
    required String label,
    required String value,
    required DateTime date,
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
            '$label $value',
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

  /// Deliberate single-point card for a cardio metric.
  Widget _buildSingleCardioPointCard({
    required ThemeData theme,
    required OmniThemeColors themeColors,
    required CardioTrendPoint point,
    required String distUnit,
  }) {
    final mins = point.durationSecs ~/ 60;
    final secs = point.durationSecs % 60;
    final durStr = '$mins:${secs.toString().padLeft(2, '0')}';

    final parts = <String>['Duration: $durStr'];
    final estimateSuffix = point.distanceEstimated ? ' est.' : '';
    if (point.distanceM != null) {
      final value = _distanceForDisplay(point.distanceM!, distUnit);
      parts.add(
        'Distance: ${value.toStringAsFixed(2)} $distUnit$estimateSuffix',
      );
    }
    if (point.paceSecPerKm != null) {
      final displayPace = _paceForDisplay(point.paceSecPerKm!, distUnit);
      parts.add(
        'Pace: ${displayPace.toStringAsFixed(0)} s/$distUnit$estimateSuffix',
      );
    }

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
            parts.join(' · '),
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

  // ── Shared helpers ────────────────────────────────────────────────────────

  Widget _buildSectionEmptyState(
    BuildContext context,
    OmniThemeColors themeColors,
    String message,
  ) {
    return OmniSurface(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Center(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: themeColors.textMuted),
          ),
        ),
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
            Icons.bar_chart_outlined,
            size: 48,
            color: themeColors.textMuted.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No sessions yet',
            style: theme.textTheme.titleMedium?.copyWith(
              color: OmniTheme.colors.textDominant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Complete your first session to see stats here.',
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

  /// Formats a duration in milliseconds as "Xh Ym" for all-time totals.
  String _formatDuration(int ms) => OmniDateUtils.formatDurationHoursMins(ms);

  /// Compact numeric formatter used for the added-weight
  /// annotation on a reps-axis trend point. Strips trailing
  /// zeros so a 10 kg value reads "10" rather than "10.0" and
  /// keeps a single decimal otherwise.
  String _formatNumber(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(1);
  }

  /// Seconds per display unit of distance — the pace a stored sec/km figure
  /// reads as in the preferred unit. The conversion is
  /// [UnitFormatter.metresPerUnit]'s, so no km↔mi constant is repeated here.
  double _paceForDisplay(double paceSecPerKm, String distUnit) {
    return paceSecPerKm * UnitFormatter.metresPerUnit(distUnit) / 1000.0;
  }

  /// Metres as the display value of [distUnit].
  double _distanceForDisplay(double distanceM, String distUnit) {
    return distanceM / UnitFormatter.metresPerUnit(distUnit);
  }

  /// Build the NUTRITION card's legend row. Carries the
  /// active view's macro / calorie markers plus a "Target"
  /// marker whenever the adherence series has a target
  /// line. The dashed line is rendered with a 2-pixel solid
  /// swatch followed by a 2-pixel gap so the legend swatch
  /// matches the on-chart dash pattern.
  Widget _buildNutritionLegend(ThemeData theme, OmniThemeColors themeColors) {
    final macroColors = themeColors.macroChart;
    final hasTarget = (_nutritionAdherence?.targetLine.isNotEmpty ?? false);
    if (_nutritionView == _NutritionView.calories) {
      return Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          _buildLegendItem(
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
        _buildLegendItem(
          theme,
          macroColors.protein,
          'Protein (g)',
          themeColors,
        ),
        _buildLegendItem(theme, macroColors.carbs, 'Carbs (g)', themeColors),
        _buildLegendItem(theme, macroColors.fat, 'Fat (g)', themeColors),
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

  /// Like `_buildLegendItem` but renders the color swatch as
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

/// Holds one chart series for the multi-line VOLUME TRENDS
/// and CONSISTENCY charts: the line color, the x-indexed
/// data points, and the legend label. Indexed against the
/// shared period-points x-axis so every series can share one
/// `ScrollableTrendChart`.
class _ChartSeries {
  final Color color;
  final List<FlSpot> spots;
  final String legendLabel;
  const _ChartSeries({
    required this.color,
    required this.spots,
    required this.legendLabel,
  });
}

class _LinearScale {
  final double sourceMin;
  final double sourceMax;
  final double targetMin;
  final double targetMax;

  const _LinearScale({
    required this.sourceMin,
    required this.sourceMax,
    required this.targetMin,
    required this.targetMax,
  });

  factory _LinearScale.fromSourceAndTarget({
    required double sourceMin,
    required double sourceMax,
    required double targetMin,
    required double targetMax,
  }) {
    return _LinearScale(
      sourceMin: sourceMin,
      sourceMax: sourceMax,
      targetMin: targetMin,
      targetMax: targetMax,
    );
  }

  double toTarget(double sourceValue) {
    final sourceRange = sourceMax - sourceMin;
    if (sourceRange == 0) {
      return targetMin + (targetMax - targetMin) / 2.0;
    }
    final t = (sourceValue - sourceMin) / sourceRange;
    return targetMin + t * (targetMax - targetMin);
  }

  double toSource(double targetValue) {
    final targetRange = targetMax - targetMin;
    if (targetRange == 0) {
      return sourceMin;
    }
    final t = (targetValue - targetMin) / targetRange;
    return sourceMin + t * (sourceMax - sourceMin);
  }
}

class _StatsPill extends StatelessWidget {
  final String label;
  final String value;
  final OmniThemeColors themeColors;
  final ThemeData theme;
  final Widget? trailingIcon;

  const _StatsPill({
    required this.label,
    required this.value,
    required this.themeColors,
    required this.theme,
    this.trailingIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 0.5,
            color: themeColors.textMuted,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: themeColors.primary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailingIcon != null) ...[
              const SizedBox(width: 4),
              trailingIcon!,
            ],
          ],
        ),
      ],
    );
  }
}
