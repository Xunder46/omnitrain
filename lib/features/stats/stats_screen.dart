import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/constants/omni_theme.dart';
import '../../core/models/fuel_summary.dart';
import '../../core/models/instrument_list.dart';
import '../../core/models/stats_progress.dart';
import '../../core/services/stats_progress_service.dart';
import '../../core/utils/chart_axis_helper.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/unit_formatter.dart';
import '../../core/navigation/omni_navigator.dart';
import '../../state/calendar/calendar_state.dart';
import '../../state/settings/settings_state.dart';
import '../../state/workout/workout_state.dart';
import '../../widgets/layout/omni_surface.dart';
import '../../widgets/layout/omni_back_header.dart';
import '../../widgets/layout/omni_card_header.dart';
import '../../widgets/chart/chart_primitives.dart';
import '../../widgets/chart/edge_aware_date_label.dart';
import '../nutrition/nutrition_trend_screen.dart';
import '../nutrition/widgets/nutrition_trend_card.dart';
import 'records_and_trends_screen.dart';
import 'widgets/fuel_section.dart';
import 'widgets/instrument_list.dart';
import 'widgets/recent_pr_list.dart';
import 'widgets/scrollable_trend_chart.dart';
import 'widgets/stats_pill.dart';
import 'widgets/window_chip.dart';

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
  bool _isLoading = true;
  int _totalSessions = 0;
  int _totalDurationMs = 0;
  int _streakDays = 0;

  StatsProgressData? _progressData;
  List<InstrumentSectionData> _instrumentSections = const [];

  NutritionAdherence? _nutritionAdherence;
  FuelSummary? _fuelSummary;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    try {
      // Reuse CalendarState streak logic — do not re-implement the calculation.
      final calendarState = CalendarState(widget.workoutState.repository);
      await calendarState.init();
      final streak = calendarState.streakDays;

      // One service instance for the whole load. The service caches its
      // history snapshot per instance, so every `compute*` call below
      // shares a single read of the repository — constructing a second
      // instance here would silently double that cost.
      final service = StatsProgressService(widget.workoutState.repository);

      // All-time aggregates (completed sessions and their duration) come from
      // the service, so the screen and Records & Trends agree on the figures.
      final totals = await service.computeTotals();

      // Compute progress data (e1RM trends, cardio trends, isometric trends,
      // sports trends, PRs, and the nutrition trend — all in one call so we don't
      // double-walk the repository for the same screen).
      final progressData = await service.computeProgressData();

      final adherence = await service.computeNutritionAdherence();

      // The Fuel row's own window, resolved in the same load as everything
      // else so the row never computes during a build.
      final fuelSummary = await service.computeFuelSummary();

      // The Instruments list is the same window's work, so it resolves the
      // window from the data we already have rather than resolving it again.
      final instrumentSections = await service.computeInstrumentSections(
        window: progressData.window,
      );

      if (!mounted) return;

      setState(() {
        _totalSessions = totals.completedSessions;
        _totalDurationMs = totals.durationMs;
        _streakDays = streak;
        _progressData = progressData;
        _instrumentSections = instrumentSections;
        _nutritionAdherence = adherence;
        _fuelSummary = fuelSummary;
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
        final window = _progressData?.window;

        return Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,
          extendBodyBehindAppBar: true,
          appBar: OmniBackHeader(
            title: 'Stats',
            actions: [
              Semantics(
                label: 'Records & Trends',
                button: true,
                child: IconButton(
                  icon: const Icon(Icons.show_chart),
                  color: OmniTheme.colors.textDominant,
                  tooltip: 'Records & Trends',
                  onPressed: () => OmniNavigator.push(
                    context,
                    (_) => RecordsAndTrendsScreen(
                      workoutState: widget.workoutState,
                      settingsState: widget.settingsState,
                    ),
                  ),
                ),
              ),
            ],
          ),
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
                            if (window != null &&
                                _instrumentSections.isNotEmpty) ...[
                              InstrumentList(
                                sections: _instrumentSections,
                                window: window,
                                themeColors: themeColors,
                                workoutState: widget.workoutState,
                                settingsState: widget.settingsState,
                              ),
                              const SizedBox(height: 24),
                            ],
                            if (_fuelSummary != null) ...[
                              FuelSection(
                                summary: _fuelSummary!,
                                themeColors: themeColors,
                                onTap: () => OmniNavigator.push(
                                  context,
                                  (_) => NutritionTrendScreen(
                                    workoutState: widget.workoutState,
                                    settingsState: widget.settingsState,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],
                            Column(
                              key: const Key('stats_legacy_sections'),
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ..._buildStrengthSection(context, themeColors),
                                const SizedBox(height: 24),
                                ..._buildCardioSection(context, themeColors),
                                const SizedBox(height: 24),
                                ..._buildIsometricSection(context, themeColors),
                                const SizedBox(height: 24),
                                ..._buildSportsSection(context, themeColors),
                                const SizedBox(height: 24),
                                ..._buildNutritionSection(themeColors),
                              ],
                            ),
                          ],
                  ),
          ),
        );
      },
    );
  }

  // ── All-time aggregate ────────────────────────────────────────────────────

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
            child: StatsPill(
              label: 'Sessions',
              value: _totalSessions.toString(),
              themeColors: themeColors,
              theme: theme,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: StatsPill(
              label: 'Time',
              value: _formatDuration(_totalDurationMs),
              themeColors: themeColors,
              theme: theme,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: StatsPill(
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
          if (data != null)
            StatsWindowChip(window: data.window, themeColors: themeColors),
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
      widgets.add(
        RecentPRList(prs: data.recentPRs, settingsState: widget.settingsState),
      );
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
            buildSinglePointCard(
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
            buildSinglePointCard(
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
            buildSinglePointCard(
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
                  reservedSize: kChartBottomAxisReservedSize,
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
          if (data != null)
            StatsWindowChip(window: data.window, themeColors: themeColors),
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
          if (data != null)
            StatsWindowChip(window: data.window, themeColors: themeColors),
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
                  reservedSize: kChartBottomAxisReservedSize,
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
          if (data != null)
            StatsWindowChip(window: data.window, themeColors: themeColors),
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

  // ── Nutrition section (kcal + macros trend card) ─────────────────────────

  /// The NUTRITION section. The card is shared with the full-history trend
  /// screen; only the trend window differs, so both hosts render one widget.
  List<Widget> _buildNutritionSection(OmniThemeColors themeColors) {
    final trend = _progressData?.nutritionTrend ?? const [];
    return [
      const OmniCardHeader(title: 'NUTRITION'),
      NutritionTrendCard(
        trend: trend,
        adherence: _nutritionAdherence,
        themeColors: themeColors,
      ),
    ];
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
                  buildLegendItem(
                    theme,
                    themeColors.secondary,
                    'Pace (s/$distUnit)',
                    themeColors,
                  ),
                  buildLegendItem(
                    theme,
                    themeColors.primary,
                    'Distance ($distUnit)',
                    themeColors,
                  ),
                  if (_hasEstimatedDay(cardio.trend))
                    buildLegendItem(
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
                  reservedSize: kChartBottomAxisReservedSize,
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
