import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/constants/omni_theme.dart';
import '../../core/models/stats_progress.dart';
import '../../core/services/stats_progress_service.dart';
import '../../core/utils/chart_axis_helper.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/session_feeling_utils.dart';
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

      // Compute progress data (e1RM trends, volume trends, cardio trends,
      // PRs, and the nutrition trend — all in one call so we don't
      // double-walk the repository for the same screen).
      final progressData = await StatsProgressService(
        widget.workoutState.repository,
      ).computeProgressData();

      if (!mounted) return;

      setState(() {
        _totalSessions = totalCount;
        _totalDurationMs = totalMs;
        _streakDays = streak;
        _progressData = progressData;
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
                            ..._buildFeelingSection(context, themeColors),
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
          if (data != null)
            _buildWindowChip(context, themeColors, data.window),
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
    // reps-axis exercise (`.github/agents/plans/stats-summary-fix-pack-plan.md`,
    // Push-Up mixed-axis bug fix).
    final repsDisplay = lift.repsTrend.toList();
    final repsHasAddedWeight =
        repsDisplay.any((p) => (p.extraWeightKg ?? 0) > 0);

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
        Icon(
          Icons.info_outline,
          size: 14,
          color: themeColors.textMuted,
        ),
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
                sideTitles: SideTitles(
                  showTitles: false,
                  reservedSize: 0,
                ),
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
          if (data != null)
            _buildWindowChip(context, themeColors, data.window),
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

  // ── Feeling section ───────────────────────────────────────────────────────

  /// The HOW DID IT FEEL section surfaces the post-session feeling
  /// (1..5) as a trend so the user can read its drift against
  /// the training-time trend on the same time window. Universal
  /// across modalities — built from `TrainingSession.sessionFeeling`
  /// only, never gated on strength / cardio / effort data.
  ///
  /// Deliberate non-features:
  ///   - No stat tile, no average-feeling scalar, no Feeling pill
  ///     in the ALL TIME row.
  ///   - No rest / deload / recovery suggestion.
  ///   - Sessions without a feeling are omitted (no zero-fill,
  ///     no interpolated dip).
  ///   - When zero sessions in the window have a feeling, an
  ///     explicit empty state renders — not a chart, not a flat
  ///     line at zero.
  List<Widget> _buildFeelingSection(
    BuildContext context,
    OmniThemeColors themeColors,
  ) {
    final data = _progressData;
    final trend = data?.feelingTrend ?? const <FeelingTrendPoint>[];
    final widgets = <Widget>[
      const SizedBox(height: 24),
      OmniCardHeader(
        title: 'HOW DID IT FEEL',
        actions: [
          if (data != null)
            _buildWindowChip(context, themeColors, data.window),
        ],
      ),
    ];

    // Empty-state path: sessions exist but none in the window
    // have a feeling logged. Render an explicit message rather
    // than a chart that would either be blank or fabricate a
    // misleading flat line at the floor.
    if (trend.isEmpty) {
      widgets.add(
        _buildSectionEmptyState(
          context,
          themeColors,
          'No feeling logged in this window yet',
        ),
      );
      return widgets;
    }

    widgets.add(_buildFeelingCard(context, themeColors, trend));
    return widgets;
  }

  Widget _buildFeelingCard(
    BuildContext context,
    OmniThemeColors themeColors,
    List<FeelingTrendPoint> trend,
  ) {
    // Fixed 1..5 semantic range with integer ticks (1, 2, 3, 4,
    // 5). Feeling is ordinal, not continuous — never let the
    // y-axis auto-scale to a flat line at a single value (which
    // would read as zero context), never let it stretch below
    // 1 or above 5, and never pad above the max with a 6th tick.
    // The pinned y-axis labels are bare integers (no unit
    // suffix).
    const feelingBounds = ChartAxisBounds(min: 1, max: 5, interval: 1);

    // The connecting line is ONE fixed color — `themeColors.primary`
    // — independent of any session's rating. Every other chart on
    // the screen already uses this single-color convention, and it
    // guarantees the line is always legible against the chart
    // background regardless of which rating was most recently
    // logged. (Previously this took `feelingColor(latest, context)`,
    // which made the line vanish when the latest rating mapped to a
    // color close to the background — e.g. feeling=5 resolved to
    // `Theme.of(context).primaryColor`, which on some themes is
    // the same hue as the chart background.)
    //
    // The points carry the meaning instead. Each point is painted in
    // its own session's feeling color via `feelingColor(...)` — the
    // same shared source the post-workout survey tile and the
    // day-session-list border already use. Three surfaces, one
    // palette source, no extra tile, no stat number.
    //
    // Each point also keeps the surface-color halo stroke so it
    // stays visible when its feeling color is close to the
    // background or sits exactly on a horizontal gridline — a flat
    // series still reads as a row of distinct points.
    final lineColor = themeColors.primary;
    final pointColors = List<Color>.generate(
      trend.length,
      (i) => feelingColor(trend[i].feeling, themeColors),
    );
    final spots = List.generate(
      trend.length,
      (i) => FlSpot(i.toDouble(), trend[i].feeling.toDouble()),
    );

    return OmniSurface(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
      child: ScrollableTrendChart(
            themeColors: themeColors,
            bounds: feelingBounds,
            unitLabel: '',
            pointCount: trend.length,
            chartBuilder: (plotWidth) {
              return LineChart(
                LineChartData(
                  minX: 0,
                  maxX: (trend.length - 1).toDouble(),
                  minY: feelingBounds.min,
                  maxY: feelingBounds.max,
                  lineTouchData: const LineTouchData(enabled: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: false,
                        reservedSize: 0,
                      ),
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
                            text: ChartAxisHelper.formatDateLabel(
                              trend[idx].date,
                            ),
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
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: themeColors.divider,
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      color: lineColor,
                      // Straight segments (no curve) so the line
                      // reads unambiguously on a 120dp-tall
                      // chart. Curved segments with sparse data
                      // can pull control points off-grid and
                      // render the line as a smear.
                      isCurved: false,
                      // 2dp line + 3dp dots — the same conventions every other
                      // chart on this screen (e1RM, volume, cardio
                      // pace + distance, cardio duration, nutrition
                      // calories, nutrition macros) already uses.
                      // Heavier weights and a glow shadow were tried
                      // here earlier but made the feeling chart
                      // visually louder than every other trend on
                      // the screen; the standard 2dp / 3dp / 1.5dp
                      // triple reads correctly against the chart
                      // background on every theme without any
                      // extra contrast tooling.
                      barWidth: 2,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (p, x, data, i) => FlDotCirclePainter(
                          radius: 3,
                          color: pointColors[i],
                          strokeWidth: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
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
      const SizedBox(height: 24),
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
    final macroColors = themeColors.macroChart;
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
              child: _nutritionView == _NutritionView.macros
                  ? Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        _buildLegendItem(
                          theme,
                          macroColors.protein,
                          'Protein (g)',
                          themeColors,
                        ),
                        _buildLegendItem(
                          theme,
                          macroColors.carbs,
                          'Carbs (g)',
                          themeColors,
                        ),
                        _buildLegendItem(
                          theme,
                          macroColors.fat,
                          'Fat (g)',
                          themeColors,
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
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
              child: _nutritionView == _NutritionView.macros
                  ? Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        _buildLegendItem(
                          theme,
                          macroColors.protein,
                          'Protein (g)',
                          themeColors,
                        ),
                        _buildLegendItem(
                          theme,
                          macroColors.carbs,
                          'Carbs (g)',
                          themeColors,
                        ),
                        _buildLegendItem(
                          theme,
                          macroColors.fat,
                          'Fat (g)',
                          themeColors,
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
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
        ButtonSegment(
          value: _NutritionView.calories,
          label: Text('Calories'),
        ),
        ButtonSegment(
          value: _NutritionView.macros,
          label: Text('Macros'),
        ),
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
                sideTitles: SideTitles(
                  showTitles: false,
                  reservedSize: 0,
                ),
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
                sideTitles: SideTitles(
                  showTitles: false,
                  reservedSize: 0,
                ),
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
                    if (value == 0 || value == (emptyPointCount - 1).toDouble()) {
                      return buildEdgeAwareDateLabel(
                        meta: meta,
                        text: ChartAxisHelper.formatDateLabel(
                          DateTime.now()
                              .subtract(Duration(days: ((emptyPointCount - 1) - value).toInt())),
                        ),
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
              else
                ...[
                  LineChartBarData(
                    spots:
                        List.generate(emptyPointCount, (i) => FlSpot(i.toDouble(), 0)),
                    color: macroColors.protein,
                    isCurved: true,
                    curveSmoothness: 0.3,
                    barWidth: 2,
                    isStrokeCapRound: true,
                    dotData: FlDotData(show: false),
                    belowBarData: BarAreaData(show: false),
                  ),
                  LineChartBarData(
                    spots:
                        List.generate(emptyPointCount, (i) => FlSpot(i.toDouble(), 0)),
                    color: macroColors.carbs,
                    isCurved: true,
                    curveSmoothness: 0.3,
                    barWidth: 2,
                    isStrokeCapRound: true,
                    dotData: FlDotData(show: false),
                    belowBarData: BarAreaData(show: false),
                  ),
                  LineChartBarData(
                    spots:
                        List.generate(emptyPointCount, (i) => FlSpot(i.toDouble(), 0)),
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
                sideTitles: SideTitles(
                  showTitles: false,
                  reservedSize: 0,
                ),
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
            _buildCardioDurationChart(themeColors, cardio.trend),
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
                sideTitles: SideTitles(
                  showTitles: false,
                  reservedSize: 0,
                ),
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
                  getDotPainter: (p, x, data, i) => FlDotCirclePainter(
                    radius: 3,
                    color: themeColors.secondary,
                    strokeWidth: 1.5,
                    strokeColor: themeColors.surface,
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
                    getDotPainter: (p, x, data, i) => FlDotCirclePainter(
                      radius: 3,
                      color: themeColors.primary,
                      strokeWidth: 1.5,
                      strokeColor: themeColors.surface,
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

  Widget _buildLegendItem(
    ThemeData theme,
    Color color,
    String label,
    OmniThemeColors themeColors,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
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

  Widget _buildCardioDurationChart(
    OmniThemeColors themeColors,
    List<CardioTrendPoint> points,
  ) {
    final durationValues = points.map((p) => p.durationSecs / 60.0).toList();
    final spots = List.generate(
      points.length,
      (i) => FlSpot(i.toDouble(), durationValues[i]),
    );

    final bounds = ChartAxisHelper.computeBounds(durationValues);

    return ScrollableTrendChart(
      themeColors: themeColors,
      bounds: bounds,
      unitLabel: 'min',
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
                sideTitles: SideTitles(
                  showTitles: false,
                  reservedSize: 0,
                ),
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
                color: themeColors.secondary,
                isCurved: true,
                curveSmoothness: 0.3,
                barWidth: 2,
                isStrokeCapRound: true,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (p, x, data, i) => FlDotCirclePainter(
                    radius: 3,
                    color: themeColors.secondary,
                    strokeWidth: 1.5,
                    strokeColor: themeColors.surface,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  color: themeColors.secondary.withAlpha(25),
                ),
              ),
            ],
          ),
        );
      },
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
    if (point.distanceM != null) {
      final km = point.distanceM! / 1000.0;
      final isKm = distUnit == 'km';
      final val = isKm ? km : km * 0.621371;
      parts.add('Distance: ${val.toStringAsFixed(2)} $distUnit');
    }
    if (point.paceSecPerKm != null) {
      final displayPace = _paceForDisplay(point.paceSecPerKm!, distUnit);
      parts.add('Pace: ${displayPace.toStringAsFixed(0)} s/$distUnit');
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

  double _paceForDisplay(double paceSecPerKm, String distUnit) {
    if (distUnit == 'mi') {
      // Convert sec/km to sec/mi for display when miles are preferred.
      return paceSecPerKm * 1.609344;
    }
    return paceSecPerKm;
  }

  double _distanceForDisplay(double distanceM, String distUnit) {
    final km = distanceM / 1000.0;
    return distUnit == 'mi' ? km * 0.621371 : km;
  }
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
