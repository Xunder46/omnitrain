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
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  _MonthGrid(
                    year: widget.calendarState.year,
                    month: widget.calendarState.month,
                    entriesByDay: widget.calendarState.entriesByDay,
                    periods: widget.calendarState.periods,
                    startOfWeek: _startOfWeek,
                    onDayTap: (date) => _onDayTap(context, date),
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

  @override
  Widget build(BuildContext context) {
    final grid = OmniDateUtils.buildMonthGrid(
      year,
      month,
      startOfWeek: startOfWeek,
    );

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        childAspectRatio: 0.7,
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
            if (entries.isNotEmpty) _SessionIndicators(entries: entries),
          ],
        ),
      ),
    );
  }
}

/// Row 1: first 2 dots. Row 2: 3rd dot (if present) + "+N" overflow (if >3).
class _SessionIndicators extends StatelessWidget {
  final List<CalendarEntry> entries;

  const _SessionIndicators({required this.entries});

  @override
  Widget build(BuildContext context) {
    final row1 = entries.take(2).toList();
    final hasRow2 = entries.length > 2;
    final third = entries.length > 2 ? entries[2] : null;
    final overflow = entries.length > 3 ? entries.length - 3 : 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: row1.map((e) => _Dot(entry: e)).toList(),
        ),
        if (hasRow2)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (third != null) _Dot(entry: third),
              if (overflow > 0)
                Container(
                  width: 14.0,
                  height: 14.0,
                  margin: const EdgeInsets.symmetric(
                    horizontal: 1,
                    vertical: 1,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '+$overflow',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: OmniTheme.colors.textSecondary.withOpacity(0.75),
                      fontWeight: FontWeight.w600,
                      height: 1.0,
                    ),
                  ),
                ),
            ],
          ),
      ],
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
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _CompactStat(
                  label: 'SESSIONS',
                  value: completedSessions > 0 ? '$completedSessions' : '—',
                ),
                _CompactStat(
                  label: 'TIME',
                  value: _formatTrainingTime(totalTrainingMs),
                ),
                _CompactStat(
                  label: isActiveStreak ? 'STREAK' : 'BEST RUN',
                  value: completedSessions == 0
                      ? '—'
                      : (streakDays >= 3
                            ? '🔥 ${streakDays}d'
                            : (streakDays == 0 ? '0' : '${streakDays}d')),
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
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
            color: OmniTheme.colors.textSecondary.withOpacity(0.55),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          value,
          style: Theme.of(context).textTheme.displayMedium?.copyWith(
            letterSpacing: -0.5,
            color: OmniTheme.colors.textDominant,
          ),
        ),
      ],
    );
  }
}
