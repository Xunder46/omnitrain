import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/constants/modality.dart';
import '../../core/constants/modality_colors.dart';
import '../../core/constants/omni_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../state/calendar/calendar_state.dart';
import '../../state/settings/settings_state.dart';
import '../../state/workout/workout_state.dart';
import '../../widgets/layout/omni_gradient_background.dart';
import '../../widgets/layout/omni_surface.dart';

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

  // Index 0 = 29 days ago, index 29 = today.
  final List<int> _dayCounts = List.filled(30, 0);

  // modality key → 30-element list of average rest seconds (null = no data that day).
  Map<String?, List<double?>> _restAvgsByModality = {};

  // Anchored at load time so the chart label never drifts after midnight rebuilds.
  DateTime? _thirtyDaysAgo;
  DateTime? _today;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final thirtyDaysAgo = today.subtract(const Duration(days: 29));
      final fromMs = thirtyDaysAgo.millisecondsSinceEpoch;
      final toMs = OmniDateUtils.endOfDayMs(now);

      // Load all sessions (for aggregate stats) and 30-day window (for chart) in parallel.
      final results = await Future.wait([
        widget.workoutState.getAllSessions(),
        widget.workoutState.getSessionsByDateRange(fromMs, toMs),
      ]);

      final allSessions = results[0];
      final recentSessions = results[1];

      // Compute all-time aggregates from completed sessions only.
      int totalCount = 0;
      int totalMs = 0;
      for (final s in allSessions) {
        if (s.endedAtMs != null) {
          totalCount++;
          totalMs += s.endedAtMs! - s.startedAtMs;
        }
      }

      // Build per-day counts for the 30-day chart window.
      final counts = List.filled(30, 0);
      for (final s in recentSessions) {
        if (s.endedAtMs == null) continue;
        final sessionDateTime = DateTime.fromMillisecondsSinceEpoch(s.startedAtMs);
        final sessionDay = DateTime(
          sessionDateTime.year,
          sessionDateTime.month,
          sessionDateTime.day,
        );
        final dayIndex = sessionDay.difference(thirtyDaysAgo).inDays;
        if (dayIndex >= 0 && dayIndex < 30) {
          counts[dayIndex]++;
        }
      }

      // Reuse CalendarState streak logic — do not re-implement the calculation.
      final calendarState = CalendarState(widget.workoutState.repository);
      await calendarState.init();
      final streak = calendarState.streakDays;

      // Fetch closed rests in the 30-day window, grouped by modality.
      final restsByModality = await widget.workoutState.repository
          .getEntryRestsByModalityInDateRange(fromMs, toMs);

      final restAvgs = <String?, List<double?>>{};
      for (final entry in restsByModality.entries) {
        final modality = entry.key;
        final rests = entry.value;

        final sumSecs = List<double>.filled(30, 0);
        final countPerDay = List<int>.filled(30, 0);

        for (final rest in rests) {
          final restDt = DateTime.fromMillisecondsSinceEpoch(rest.restStartMs);
          final restDay = DateTime(restDt.year, restDt.month, restDt.day);
          final dayIndex = restDay.difference(thirtyDaysAgo).inDays;
          if (dayIndex < 0 || dayIndex >= 30) continue;
          final durationSecs = (rest.restEndMs! - rest.restStartMs) / 1000.0;
          sumSecs[dayIndex] += durationSecs;
          countPerDay[dayIndex]++;
        }

        final avgs = <double?>[];
        for (var i = 0; i < 30; i++) {
          avgs.add(countPerDay[i] > 0 ? sumSecs[i] / countPerDay[i] : null);
        }
        restAvgs[modality] = avgs;
      }

      if (!mounted) return;

      setState(() {
        _totalSessions = totalCount;
        _totalDurationMs = totalMs;
        _streakDays = streak;
        for (var i = 0; i < 30; i++) {
          _dayCounts[i] = counts[i];
        }
        _restAvgsByModality = restAvgs;
        // Anchor the date range so chart labels never drift after midnight rebuilds.
        _thirtyDaysAgo = thirtyDaysAgo;
        _today = today;
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
        final themeColors = OmniTheme.colorsForTheme(widget.settingsState.appTheme);

        return Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            title: const Text('Stats'),
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
          body: OmniGradientBackground(
            child: SafeArea(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                      children: _totalSessions == 0
                          ? [_buildEmptyState(context, themeColors)]
                          : [
                              _buildSectionLabel('ALL TIME', themeColors),
                              const SizedBox(height: 8),
                              _buildAggregateCard(context, themeColors),
                              const SizedBox(height: 24),
                              _buildSectionLabel('ACTIVITY', themeColors),
                              const SizedBox(height: 8),
                              _buildActivityCard(context, themeColors),
                              if (_restAvgsByModality.isNotEmpty) ...[
                                const SizedBox(height: 24),
                                _buildSectionLabel('REST TIME', themeColors),
                                const SizedBox(height: 8),
                                _buildRestTimeCard(context, themeColors),
                              ],
                            ],
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionLabel(String label, OmniThemeColors themeColors) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 3.0,
        color: themeColors.textMuted,
      ),
    );
  }

  Widget _buildAggregateCard(BuildContext context, OmniThemeColors themeColors) {
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
              label: 'Total Time',
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

  Widget _buildActivityCard(BuildContext context, OmniThemeColors themeColors) {
    final theme = Theme.of(context);
    // Use anchored dates from _loadData — never recompute from DateTime.now() here,
    // otherwise a midnight rebuild (e.g. theme change) would shift the label
    // while _dayCounts still represents the original window.
    final thirtyDaysAgo = _thirtyDaysAgo!;
    final today = _today!;

    final maxCount = _dayCounts.reduce(max);
    final double maxY = max(1.0, maxCount.toDouble());
    final double yInterval = max(1.0, (maxY / 4).ceilToDouble());

    return OmniSurface(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '30-Day Activity',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: OmniTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  '${OmniDateUtils.shortMonthName(thirtyDaysAgo.month)} ${thirtyDaysAgo.day}'
                  ' – '
                  '${OmniDateUtils.shortMonthName(today.month)} ${today.day}',
                  style: TextStyle(
                    fontSize: 11,
                    color: themeColors.textMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              // Reserve ~28 px for the y-axis labels; distribute the rest
              // across 30 bars, using 65 % of each slot as bar width.
              final slotWidth = (constraints.maxWidth - 28) / 30;
              final barWidth = (slotWidth * 0.65).clamp(3.0, 16.0);

              return SizedBox(
                height: 160,
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: maxY + yInterval * 0.3,
                    minY: 0,
                    barTouchData: BarTouchData(handleBuiltInTouches: false),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 28,
                          interval: yInterval,
                          getTitlesWidget: (value, meta) {
                            if (value != value.floorToDouble()) {
                              return const SizedBox.shrink();
                            }
                            final intVal = value.toInt();
                            if (intVal < 0) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Text(
                                intVal.toString(),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: themeColors.textMuted,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 24,
                          getTitlesWidget: (value, meta) {
                            final idx = value.toInt();
                            const labelIndices = {0, 7, 14, 21, 28};
                            if (!labelIndices.contains(idx)) {
                              return const SizedBox.shrink();
                            }
                            final date = thirtyDaysAgo.add(Duration(days: idx));
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '${OmniDateUtils.shortMonthName(date.month)} ${date.day}',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: themeColors.textMuted,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: yInterval,
                      getDrawingHorizontalLine: (_) => FlLine(
                        color: themeColors.divider,
                        strokeWidth: 1,
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    barGroups: List.generate(30, (i) {
                      return BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: _dayCounts[i].toDouble(),
                            color: themeColors.primary,
                            width: barWidth,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(3),
                            ),
                          ),
                        ],
                      );
                    }),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRestTimeCard(BuildContext context, OmniThemeColors themeColors) {
    final theme = Theme.of(context);
    final thirtyDaysAgo = _thirtyDaysAgo!;
    final today = _today!;

    // Stable display order for modalities.
    const displayOrder = <String?>[
      'cardio_endurance',
      'resistance_lifting',
      'sports',
      'isometric_stretching',
      null, // Free Training
    ];

    final visibleModalities = displayOrder
        .where((m) => _restAvgsByModality.containsKey(m))
        .toList();

    // Build LineChartBarData for each visible modality.
    final lineBars = <LineChartBarData>[];
    double maxY = 10.0;

    for (final modality in visibleModalities) {
      final avgs = _restAvgsByModality[modality]!;
      final spots = <FlSpot>[];
      for (var i = 0; i < 30; i++) {
        if (avgs[i] != null) {
          spots.add(FlSpot(i.toDouble(), avgs[i]!));
          if (avgs[i]! > maxY) maxY = avgs[i]!;
        }
      }
      if (spots.isEmpty) continue;
      lineBars.add(LineChartBarData(
        spots: spots,
        color: ModalityColors.forModality(modality),
        isCurved: true,
        curveSmoothness: 0.3,
        barWidth: 2,
        isStrokeCapRound: true,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: false),
      ));
    }

    if (lineBars.isEmpty) return const SizedBox.shrink();

    // Y axis interval: aim for ~4 ticks, rounded to nearest 10.
    final rawInterval = (maxY / 4).ceilToDouble();
    final yInterval = max(10.0, (rawInterval / 10).ceil() * 10.0);

    return OmniSurface(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '30-Day Rest Time',
            style: theme.textTheme.titleSmall?.copyWith(
              color: OmniTheme.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${OmniDateUtils.shortMonthName(thirtyDaysAgo.month)} ${thirtyDaysAgo.day}'
            ' – '
            '${OmniDateUtils.shortMonthName(today.month)} ${today.day}',
            style: TextStyle(fontSize: 11, color: themeColors.textMuted),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 160,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: 29,
                minY: 0,
                maxY: maxY + yInterval * 0.3,
                lineTouchData: const LineTouchData(enabled: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      interval: yInterval,
                      getTitlesWidget: (value, meta) {
                        if (value != value.floorToDouble()) {
                          return const SizedBox.shrink();
                        }
                        final intVal = value.toInt();
                        if (intVal < 0) return const SizedBox.shrink();
                        final mins = intVal ~/ 60;
                        final secs = intVal % 60;
                        final label =
                            '$mins:${secs.toString().padLeft(2, '0')}';
                        return Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 10,
                              color: themeColors.textMuted,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        // Three labels: start (0), middle (15), end (29).
                        if (idx != 0 && idx != 15 && idx != 29) {
                          return const SizedBox.shrink();
                        }
                        final date = thirtyDaysAgo.add(Duration(days: idx));
                        final label =
                            '${OmniDateUtils.shortMonthName(date.month)} ${date.day}';
                        final align = idx == 0
                            ? TextAlign.left
                            : idx == 29
                                ? TextAlign.right
                                : TextAlign.center;
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            label,
                            textAlign: align,
                            style: TextStyle(
                              fontSize: 9,
                              color: themeColors.textMuted,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: yInterval,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: themeColors.divider,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: lineBars,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: visibleModalities.map((modality) {
              final color = ModalityColors.forModality(modality);
              final label = modality == null
                  ? 'Free Training'
                  : Modality.getDisplayName(modality);
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 3,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: themeColors.textMuted,
                    ),
                  ),
                ],
              );
            }).toList(),
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
            Icons.bar_chart_outlined,
            size: 48,
            color: themeColors.textMuted.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No sessions yet',
            style: theme.textTheme.titleMedium?.copyWith(
              color: OmniTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Complete your first session to see stats here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
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
            letterSpacing: 1.5,
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
