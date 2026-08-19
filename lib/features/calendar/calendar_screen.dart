import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';
import '../../core/navigation/navigation.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/modality_color_utils.dart';
import '../../core/constants/home_tiles.dart';
import '../../widgets/layout/omni_back_header.dart';
import '../../state/calendar/calendar_state.dart';
import '../../state/settings/settings_state.dart';
import '../../state/workout/workout_state.dart';
import '../../state/routine/routine_state.dart';
import '../../state/period/period_state.dart';
import '../../core/services/routine_session_service.dart';
import '../../core/services/session_summary_service.dart';
import '../../core/utils/timer_alert_service.dart';
import '../../core/utils/rest_notification_service.dart';
import '../../data/models/models.dart';
import '../session/session_summary_screen.dart';
import 'day_session_list_screen.dart';
import '../period/period_list_screen.dart';

class CalendarScreen extends StatefulWidget {
  final CalendarState calendarState;
  final PeriodState periodState;
  final WorkoutState workoutState;
  final RoutineState routineState;
  final RoutineSessionService routineSessionService;
  final SessionSummaryService sessionSummaryService;
  final SettingsState settingsState;
  final TimerAlertService timerAlertService;
  final RestNotificationService restNotificationService;

  CalendarScreen({
    super.key,
    required this.calendarState,
    required this.periodState,
    required this.workoutState,
    required this.routineState,
    required this.routineSessionService,
    required this.sessionSummaryService,
    required this.settingsState,
    required this.timerAlertService,
    RestNotificationService? restNotificationService,
  }) : restNotificationService =
           restNotificationService ?? RestNotificationService.noop();

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  static const _mondayLabels = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];
  static const _sundayLabels = [
    'Sun',
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
  ];

  List<String> get _weekLabels => widget.settingsState.startOfWeek == 'sunday'
      ? _sundayLabels
      : _mondayLabels;

  String get _startOfWeek => widget.settingsState.startOfWeek;

  @override
  void initState() {
    super.initState();
    // Init loads current month; only call if not yet initialised.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.calendarState.init();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      appBar: OmniBackHeader(
        title: 'Calendar',
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: OutlinedButton(
              onPressed: () => _openPeriods(context),
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      OmniTheme.buttonUtilityRadius,
                    ),
                  ),
                ),
                side: WidgetStatePropertyAll(
                  BorderSide(color: Theme.of(context).colorScheme.primary),
                ),
                foregroundColor: WidgetStatePropertyAll(
                  Theme.of(context).colorScheme.primary,
                ),
              ),
              child: const Text('+'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([
            widget.calendarState,
            widget.settingsState,
          ]),
          builder: (context, _) {
            return Column(
              children: [
                _MonthHeader(
                  year: widget.calendarState.year,
                  month: widget.calendarState.month,
                  onPrevious: widget.calendarState.goToPreviousMonth,
                  onNext: widget.calendarState.goToNextMonth,
                ),
                _WeekDayRow(labels: _weekLabels),
                if (widget.calendarState.isLoading)
                  SizedBox.expand(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  Flexible(
                    fit: FlexFit.loose,
                    child: _MonthGrid(
                      year: widget.calendarState.year,
                      month: widget.calendarState.month,
                      entriesByDay: widget.calendarState.entriesByDay,
                      periods: widget.calendarState.periods,
                      startOfWeek: _startOfWeek,
                      onDayTap: (date) => _onDayTap(context, date),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: _MonthlyStatsStrip(
                      completedSessions:
                          widget.calendarState.completedSessionCount,
                      totalTrainingMs: widget.calendarState.totalTrainingMs,
                      streakDays: widget.calendarState.streakDays,
                      modalityBreakdown: widget.calendarState.modalityBreakdown,
                      isActiveStreak: widget.calendarState.isActiveStreak,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _openPeriods(BuildContext context) async {
    await OmniNavigator.push(
      context,
      (_) => PeriodListScreen(periodState: widget.periodState),
    );
    if (context.mounted) {
      widget.calendarState.refresh();
    }
  }

  Future<void> _onDayTap(BuildContext context, DateTime date) async {
    final entries = widget.calendarState.entriesForDay(date);

    if (OmniDateUtils.isPastDay(date)) {
      if (entries.length == 1) {
        final entry = entries.first;
        // Single past session → open summary screen if it's a real completed session,
        // or DaySessionListScreen for a planned-not-completed session.
        if (entry.session != null && entry.session!.endedAtMs != null) {
          _openSessionSummary(context, entry.session!.id);
        } else {
          await _openDayList(context, date);
        }
      } else {
        await _openDayList(context, date);
      }
    } else {
      await _openDayList(context, date);
    }
  }

  void _openSessionSummary(BuildContext context, String sessionId) {
    widget.workoutState.loadHistoricalSession(sessionId).then((_) {
      if (context.mounted) {
        OmniNavigator.push(
          context,
          (_) => SessionSummaryScreen(
            workoutState: widget.workoutState,
            routineState: widget.routineState,
            sessionSummaryService: widget.sessionSummaryService,
            settingsState: widget.settingsState,
            timerAlertService: widget.timerAlertService,
            restNotificationService: widget.restNotificationService,
            openedFromCalendar: true,
            originatingCalendarState: widget.calendarState,
          ),
        );
      }
    });
  }

  Future<void> _openDayList(BuildContext context, DateTime date) async {
    await OmniNavigator.push(
      context,
      (_) => DaySessionListScreen(
        date: date,
        calendarState: widget.calendarState,
        routineState: widget.routineState,
        workoutState: widget.workoutState,
        routineSessionService: widget.routineSessionService,
        sessionSummaryService: widget.sessionSummaryService,
        settingsState: widget.settingsState,
        timerAlertService: widget.timerAlertService,
        restNotificationService: widget.restNotificationService,
      ),
    );
    // Refresh calendar after returning from day list (user may have added/deleted).
    await widget.calendarState.refresh();
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ────────────────────────────────────────────────────────────────────────────

class _MonthHeader extends StatelessWidget {
  final int year;
  final int month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  const _MonthHeader({
    required this.year,
    required this.month,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            color: OmniTheme.colors.textDominant,
            onPressed: onPrevious,
          ),
          Expanded(
            child: Text(
              '${OmniDateUtils.fullMonthName(month)} $year',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            color: OmniTheme.colors.textDominant,
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

class _WeekDayRow extends StatelessWidget {
  final List<String> labels;

  const _WeekDayRow({required this.labels});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: labels
            .map(
              (l) => Expanded(
                child: Center(
                  child: Text(
                    l,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: OmniTheme.colors.textSecondary.withOpacity(0.7),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  final int year;
  final int month;
  final Map<int, List<CalendarEntry>> entriesByDay;
  final List<TrainingPeriod> periods;
  final String startOfWeek;
  final void Function(DateTime) onDayTap;

  const _MonthGrid({
    required this.year,
    required this.month,
    required this.entriesByDay,
    required this.periods,
    required this.startOfWeek,
    required this.onDayTap,
  });

  /// Floor for a day cell's height. Below this the day number and a single
  /// row of session dots stop fitting, so the grid scrolls instead of
  /// squeezing further.
  static const double _minRowHeight = 52;

  /// Maximum aspect ratio for grid cells (height:width). Prevents cells from
  /// stretching arbitrarily tall on tall screens with few rows.
  static const double _maxAspectRatio = 0.7;

  static const double _rowSpacing = 2;
  static const double _columnSpacing = 2;
  static const double _horizontalPadding = 4;

  @override
  Widget build(BuildContext context) {
    final grid = OmniDateUtils.buildMonthGrid(
      year,
      month,
      startOfWeek: startOfWeek,
    );
    final rowCount = (grid.length / 7).ceil();

    return LayoutBuilder(
      builder: (context, constraints) {
        // Cell height is driven by the height actually available, not by the
        // viewport's width. A month needing six rows therefore packs into the
        // same space a five-row month uses, and wide screens no longer inflate
        // the grid past the bottom of the screen.
        final cellWidth =
            (constraints.maxWidth -
                _horizontalPadding * 2 -
                _columnSpacing * 6) /
            7;
        final spacing = _rowSpacing * (rowCount - 1);

        // Cap row height to maintain aspect ratio and prevent cells from
        // stretching arbitrarily tall on tall screens.
        final maxRowHeight = cellWidth / _maxAspectRatio;

        // Compute rowHeight: use available space when constrained (the normal path).
        // When unconstrained (e.g., rare test setup or future scrollable context),
        // fall back to maxRowHeight; this is not the app's typical path.
        double computedRowHeight;
        if (constraints.maxHeight.isFinite) {
          computedRowHeight = (constraints.maxHeight - spacing) / rowCount;
        } else {
          // Defensive fallback: not typically reached in the app.
          computedRowHeight = maxRowHeight;
        }

        final rowHeight = math.max(
          _minRowHeight,
          math.min(computedRowHeight, maxRowHeight),
        );

        final gridHeight = rowHeight * rowCount + spacing;
        final actualHeight = constraints.maxHeight.isFinite
            ? math.min(gridHeight, constraints.maxHeight)
            : gridHeight;
        final fits = actualHeight >= gridHeight;

        final gridView = GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
          physics: fits
              ? const NeverScrollableScrollPhysics()
              : const ClampingScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: _rowSpacing,
            crossAxisSpacing: _columnSpacing,
            childAspectRatio: cellWidth / rowHeight,
          ),
          itemCount: grid.length,
          itemBuilder: (context, index) {
            final date = grid[index];
            if (date == null) return const SizedBox.shrink();

            final dayMs = OmniDateUtils.startOfDayMs(date);
            final entries = entriesByDay[dayMs] ?? [];
            final isToday = OmniDateUtils.isToday(date);

            return _DayCell(
              date: date,
              entries: entries,
              periods: periods,
              isToday: isToday,
              onTap: () => onDayTap(date),
            );
          },
        );

        // Wrap the grid in a SizedBox to control its height.
        // This prevents the grid from expanding to fill available space
        // and allows the stats strip to sit directly below it.
        // Clamp the height to available space; if it doesn't fit, the grid scrolls.
        return SizedBox(
          width: constraints.maxWidth,
          height: actualHeight,
          child: gridView,
        );
      },
    );
  }
}

class _DayCell extends StatelessWidget {
  final DateTime date;
  final List<CalendarEntry> entries;
  final List<TrainingPeriod> periods;
  final bool isToday;
  final VoidCallback onTap;

  const _DayCell({
    required this.date,
    required this.entries,
    required this.periods,
    required this.isToday,
    required this.onTap,
  });

  Color _resolvePeriodHighlightColor(BuildContext context) {
    final dayMs = OmniDateUtils.startOfDayMs(date);
    final period = periods
        .where((p) => p.startDateMs <= dayMs && p.endDateMs >= dayMs)
        .firstOrNull;
    if (period == null) {
      return Colors.grey.withOpacity(0.08);
    }

    if (period.colorHex == null || period.colorHex!.length != 7) {
      return Theme.of(context).colorScheme.primary.withOpacity(0.14);
    }

    final hex = period.colorHex!.replaceFirst('#', '');
    final value = int.tryParse(hex, radix: 16);
    if (value == null) {
      return Theme.of(context).colorScheme.primary.withOpacity(0.14);
    }

    return Color(0xFF000000 | value).withOpacity(0.14);
  }

  @override
  Widget build(BuildContext context) {
    final periodHighlightColor = _resolvePeriodHighlightColor(context);

    return GestureDetector(
      onTap: entries.isNotEmpty || OmniDateUtils.isTodayOrFuture(date)
          ? onTap
          : null,
      child: Container(
        decoration: BoxDecoration(
          color: periodHighlightColor,
          borderRadius: BorderRadius.circular(8),
          border: isToday
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.6),
                  width: 1.5,
                )
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 4),
            Text(
              '${date.day}',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                color: isToday
                    ? Theme.of(context).colorScheme.primary
                    : OmniTheme.colors.textDominant.withOpacity(0.85),
              ),
            ),
            const SizedBox(height: 3),
            if (entries.isNotEmpty)
              Expanded(child: _SessionIndicators(entries: entries)),
          ],
        ),
      ),
    );
  }
}

/// Two dots per row, filling as many rows as the cell has room for. A short
/// cell shows the guaranteed minimum of one row; a taller cell shows more
/// before falling back to a "+N" badge in the final slot.
class _SessionIndicators extends StatelessWidget {
  final List<CalendarEntry> entries;

  const _SessionIndicators({required this.entries});

  /// 14pt dot plus its 1pt vertical margins.
  static const double _slotExtent = 16.0;
  static const int _dotsPerRow = 2;
  static const int _maxRows = 3;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final rows = constraints.maxHeight.isFinite
            ? (constraints.maxHeight ~/ _slotExtent).clamp(1, _maxRows)
            : 1;
        final capacity = rows * _dotsPerRow;

        // The badge takes the last slot, so it displaces one dot.
        final hidden = entries.length > capacity
            ? entries.length - capacity + 1
            : 0;
        final visible = hidden > 0
            ? entries.take(capacity - 1).toList()
            : entries;

        final slots = <Widget>[
          for (final entry in visible) _Dot(entry: entry),
          if (hidden > 0) _OverflowBadge(count: hidden),
        ];

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < slots.length; i += _dotsPerRow)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: slots.sublist(
                  i,
                  math.min(i + _dotsPerRow, slots.length),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _OverflowBadge extends StatelessWidget {
  final int count;

  const _OverflowBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14.0,
      height: 14.0,
      margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
      alignment: Alignment.center,
      child: Text(
        '+$count',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: OmniTheme.colors.textSecondary.withOpacity(0.75),
          fontWeight: FontWeight.w600,
          height: 1.0,
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final CalendarEntry entry;

  const _Dot({required this.entry});

  @override
  Widget build(BuildContext context) {
    final color = ModalityColorUtils.colorForModality(entry.modality);
    const size = 14.0;

    return Container(
      width: size,
      height: size,
      margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
      decoration: entry.isCompleted
          ? BoxDecoration(color: color, shape: BoxShape.circle)
          : BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2),
            ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Monthly stats strip
// ────────────────────────────────────────────────────────────────────────────

class _MonthlyStatsStrip extends StatelessWidget {
  final int completedSessions;
  final int totalTrainingMs;
  final int streakDays;
  final Map<String?, int> modalityBreakdown;
  final bool isActiveStreak;

  const _MonthlyStatsStrip({
    required this.completedSessions,
    required this.totalTrainingMs,
    required this.streakDays,
    required this.modalityBreakdown,
    required this.isActiveStreak,
  });

  String _formatTrainingTime(int ms) {
    if (ms <= 0) return '—';
    final totalSeconds = ms ~/ 1000;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    if (hours > 0) {
      return minutes > 0 ? '${hours}h ${minutes}m' : '${hours}h';
    }
    if (minutes > 0) return '${minutes}m';
    return '${totalSeconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final sortedModalities = modalityBreakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final modalityChips = sortedModalities.map((entry) {
      final color = ModalityColorUtils.colorForModality(entry.key);
      final tileLabel = HomeTiles.all
          .firstWhere(
            (t) => t.modality == entry.key,
            orElse: () => HomeTiles.all.first,
          )
          .label;
      final chipStyle = Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: OmniTheme.colors.textSecondary);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(tileLabel, style: chipStyle),
          const SizedBox(width: 4),
          Text(
            '${entry.value}',
            style: chipStyle?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      );
    }).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(
          height: 1,
          thickness: 0.5,
          color: OmniTheme.colors.textSecondary.withOpacity(0.15),
        ),
        const SizedBox(height: 14),
        Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _CompactStat(
                    label: 'SESSIONS',
                    value: completedSessions > 0 ? '$completedSessions' : '—',
                  ),
                ),
                Expanded(
                  child: _CompactStat(
                    label: 'TIME',
                    value: _formatTrainingTime(totalTrainingMs),
                  ),
                ),
                Expanded(
                  child: _CompactStat(
                    label: isActiveStreak ? 'STREAK' : 'BEST RUN',
                    value: completedSessions == 0
                        ? '—'
                        : (streakDays >= 3
                              ? '🔥 ${streakDays}d'
                              : (streakDays == 0 ? '0' : '${streakDays}d')),
                  ),
                ),
              ],
            ),
            if (sortedModalities.isNotEmpty) ...[
              const SizedBox(height: 18),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 20,
                runSpacing: 10,
                children: modalityChips,
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _CompactStat extends StatelessWidget {
  final String label;
  final String value;

  const _CompactStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // scaleDown keeps both lines on one line at large text scales, where
        // three side-by-side stats would otherwise run off the edge.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
              color: OmniTheme.colors.textSecondary.withOpacity(0.55),
            ),
          ),
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            maxLines: 1,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              letterSpacing: -0.5,
              color: OmniTheme.colors.textDominant,
            ),
          ),
        ),
      ],
    );
  }
}
