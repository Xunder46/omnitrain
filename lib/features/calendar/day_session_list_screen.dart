import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/omni_theme.dart';
import '../../core/navigation/navigation.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/modality_color_utils.dart';
import '../../core/utils/session_feeling_utils.dart';
import '../../core/utils/recurrence_rule.dart';
import '../../state/calendar/calendar_state.dart';
import '../../state/routine/routine_state.dart';
import '../../state/workout/workout_state.dart';
import '../../core/services/routine_session_service.dart';
import '../../core/services/session_summary_service.dart';
import '../../core/utils/timer_alert_service.dart';
import '../../core/utils/rest_notification_service.dart';
import '../../data/models/models.dart';
import '../../core/constants/modality.dart';
import '../../state/settings/settings_state.dart';
import '../session/workout_session_screen.dart';
import '../session/session_summary_screen.dart';
import '../../widgets/layout/omni_back_header.dart';
import '../../widgets/layout/omni_bottom_cta.dart';
import '../../widgets/layout/omni_card_header.dart';
import '../../widgets/dialogs/confirmation_dialog.dart';
import '../../widgets/feedback/omni_message.dart';
import '../../widgets/common/omni_empty_state.dart';
import '../../widgets/inputs/numeric_field_with_done_bar.dart';

/// Shows all sessions (planned + completed TrainingSessions) for a single day.
///
/// Behavior by date:
///   Past:          read-only list, no add/edit/delete.
///   Today/Future:  completed sessions shown but non-editable;
///                  planned sessions can be added, edited and deleted; tapping a
///                  planned row opens its edit sheet (no pencil button). Only a
///                  planned row of TODAY has a play button that starts the
///                  workout (plan 248).
class DaySessionListScreen extends StatefulWidget {
  final DateTime date;
  final CalendarState calendarState;
  final RoutineState routineState;
  final WorkoutState workoutState;
  final RoutineSessionService routineSessionService;
  final SessionSummaryService sessionSummaryService;
  final SettingsState settingsState;
  final TimerAlertService timerAlertService;
  final RestNotificationService restNotificationService;

  DaySessionListScreen({
    super.key,
    required this.date,
    required this.calendarState,
    required this.routineState,
    required this.workoutState,
    required this.routineSessionService,
    required this.sessionSummaryService,
    required this.settingsState,
    required this.timerAlertService,
    RestNotificationService? restNotificationService,
  }) : restNotificationService =
           restNotificationService ?? RestNotificationService.noop();

  @override
  State<DaySessionListScreen> createState() => _DaySessionListScreenState();
}

class _DaySessionListScreenState extends State<DaySessionListScreen> {
  bool get _isPast => OmniDateUtils.isPastDay(widget.date);
  bool get _isTodayOrFuture => !_isPast;

  List<CalendarEntry> get _allEntries =>
      widget.calendarState.entriesForDay(widget.date);

  List<CalendarEntry> get _completedEntries =>
      _allEntries.where((e) => e.isCompleted).toList();

  List<CalendarEntry> get _plannedEntries => _allEntries
      .where((e) => !e.isCompleted && e.plannedSession != null)
      .toList();

  @override
  Widget build(BuildContext context) {
    final title =
        OmniDateUtils.formatShort(widget.date) +
        (OmniDateUtils.isToday(widget.date) ? ' · Today' : '');

    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      appBar: OmniBackHeader(title: title),
      // Primary bottom CTA on the host's `bottomNavigationBar`. For
      // today/future dates this routes through the shared
      // `OmniBottomCTA` (see
      // `docs/plans/day-session-list-bottom-cta-plan.md`)
      // so the "+ New Planned Session" button sits at the same width,
      // height, and safe-area-anchored bottom as every other primary
      // bottom CTA in the app. For past dates the screen is
      // read-only and the slot is null.
      bottomNavigationBar: _isTodayOrFuture
          ? OmniBottomCTA(
              label: '+ New Planned Session',
              onPressed: () => _addPlanned(context),
            )
          : null,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.calendarState,
          builder: (context, _) {
            final completed = _completedEntries;
            final planned = _plannedEntries;
            final isEmpty = completed.isEmpty && planned.isEmpty;

            return Column(
              children: [
                Expanded(
                  child: isEmpty
                      // A past day has no bottom button, so it gets no hint
                      // pointing at one (D-28.2).
                      ? OmniEmptyState(
                          icon: _isPast
                              ? Icons.event_busy
                              : Icons.event_available,
                          title: _isPast
                              ? 'No sessions on this day.'
                              : 'No sessions planned yet.',
                          hint: _isPast
                              ? null
                              : 'Add one with the button below.',
                        )
                      : ListView(
                          // Bottom padding clears the host's shared
                          // bottom CTA when `_isTodayOrFuture` is
                          // true. For past dates the bottom
                          // NavigationBar slot is null and the
                          // standard 16 px padding is used.
                          padding: EdgeInsets.fromLTRB(
                            16,
                            8,
                            16,
                            _isTodayOrFuture
                                ? OmniTheme.formBottomCTAClearance
                                : 16,
                          ),
                          children: [
                            if (completed.isNotEmpty) ...[
                              const OmniCardHeader(
                                title: 'COMPLETED',
                                padding: EdgeInsets.only(bottom: 8, top: 4),
                              ),
                              ...completed.map(
                                (e) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _SessionRow(
                                    entry: e,
                                    routineState: widget.routineState,
                                    onTap: () => _tapCompleted(context, e),
                                    onDelete: null,
                                  ),
                                ),
                              ),
                              if (planned.isNotEmpty)
                                const SizedBox(height: 12),
                            ],
                            if (planned.isNotEmpty) ...[
                              const OmniCardHeader(
                                title: 'PLANNED',
                                padding: EdgeInsets.only(bottom: 8, top: 4),
                              ),
                              ...planned.map((e) {
                                final isEditable = _isTodayOrFuture;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _SessionRow(
                                    entry: e,
                                    routineState: widget.routineState,
                                    onTap: isEditable
                                        ? () => _editPlanned(context, e)
                                        : null,
                                    onStart:
                                        isEditable &&
                                            OmniDateUtils.isToday(widget.date)
                                        ? () => _startPlanned(context, e)
                                        : null,
                                    // A missed plan stays visible, and can be
                                    // deleted (plan 272): move and mark-done
                                    // stay off for past days.
                                    onDelete: () => _deletePlanned(
                                      context,
                                      e.plannedSession!,
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ─── Navigation: Tap completed session → open summary ────────────────────

  Future<void> _tapCompleted(BuildContext context, CalendarEntry entry) async {
    final sessionId =
        entry.session?.id ?? entry.plannedSession?.linkedSessionId;
    if (sessionId == null) return;

    // Plan 229: load the historical session into workoutState, then show
    // summary; the running workout is put back when the summary closes.
    await widget.workoutState.viewHistoricalSession(sessionId);

    if (context.mounted) {
      await OmniNavigator.push(
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
    await widget.workoutState.resumeSuspendedLiveSession();
  }

  // ─── Navigation: Start button on a planned session → start workout ───────

  Future<void> _startPlanned(BuildContext context, CalendarEntry entry) async {
    final ps = entry.plannedSession;
    if (ps == null) return;

    // Check if user has an active session already.
    if (widget.workoutState.hasActiveSession) {
      final confirmed = await ConfirmationDialog.showTwoChoice(
        context: context,
        title: 'Start New Session?',
        body: const Text(
          'Your current session will be discarded and cannot be recovered.',
        ),
        dismissLabel: 'Cancel',
        confirmLabel: 'Start New',
        dismissKey: const Key('day-session-new-start-cancel'),
        confirmKey: const Key('day-session-new-start-confirm'),
        isDestructive: true,
      );
      if (!confirmed) return;
    }

    try {
      // Plan 240: a routine that cannot start (an empty one) is found out
      // BEFORE the running workout is discarded.
      final manifest = ps.routineTemplateId == null
          ? null
          : await widget.routineSessionService.buildSessionFromTemplate(
              ps.routineTemplateId!,
            );

      // Plan 230: confirmed Start New really discards the running workout.
      await widget.workoutState.discardUnfinishedSession();

      if (manifest != null) {
        // Start routine-based session.
        await widget.workoutState.createNewSession(
          // Routine session carries the routine's Focus as a snapshot.
          modality: manifest.template.focusModality,
          title: manifest.template.name,
          intent: 'routine',
          routineTemplateId: manifest.template.id,
          includeDefaultSegment: false,
        );

        await widget.workoutState.loadSessionData();
        await widget.workoutState.populateSessionFromManifest(manifest);
      } else {
        // Start modality-only session.
        await widget.workoutState.createNewSession(modality: ps.modality);
      }

      // Navigate to workout screen.
      if (context.mounted) {
        OmniNavigator.push(
          context,
          (_) => WorkoutSessionScreen(
            workoutState: widget.workoutState,
            routineState: widget.routineState,
            sessionSummaryService: widget.sessionSummaryService,
            onSessionSaved: (sessionId) async {
              try {
                await widget.calendarState.completePlannedSession(
                  ps.id,
                  sessionId,
                );
              } catch (e) {
                if (!mounted) return;
                debugPrint('Link planned session: $e');
                OmniMessage.error(
                  context,
                  'Session saved, but could not link the planned session. '
                  'Try again.',
                );
              }
            },
            settingsState: widget.settingsState,
            timerAlertService: widget.timerAlertService,
            restNotificationService: widget.restNotificationService,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        debugPrint('Start session: $e');
        OmniMessage.error(context, 'Could not start the session. Try again.');
      }
    }
  }

  // ─── CRUD: Add planned session ────────────────────────────────────────────

  Future<void> _addPlanned(BuildContext context) async {
    await widget.routineState.loadRoutines();
    final result = await showModalBottomSheet<_PlannedSessionFormResult>(
      context: context,
      isScrollControlled: true,
      // Plan 277: the Repeat section makes the sheet tall; keep it below the
      // status bar instead of running under the clock and notch.
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PlannedSessionForm(
        date: widget.date,
        initial: null,
        routineState: widget.routineState,
      ),
    );
    if (result == null) return;
    if (!context.mounted) return;

    if (result.rule == null) {
      await widget.calendarState.createPlannedSession(
        date: widget.date,
        modality: result.modality,
        routineTemplateId: result.routineTemplateId,
        title: result.title.isNotEmpty ? result.title : null,
        note: result.note.isNotEmpty ? result.note : null,
      );
      return;
    }

    await widget.calendarState.createRecurringPlannedSessions(
      first: widget.date,
      rule: result.rule!,
      modality: result.modality,
      routineTemplateId: result.routineTemplateId,
      title: result.title.isNotEmpty ? result.title : null,
      note: result.note.isNotEmpty ? result.note : null,
    );
  }

  Future<void> _editPlanned(BuildContext context, CalendarEntry entry) async {
    final ps = entry.plannedSession!;
    await widget.routineState.loadRoutines();
    final result = await showModalBottomSheet<_PlannedSessionFormResult>(
      context: context,
      isScrollControlled: true,
      // Plan 277: the Repeat section makes the sheet tall; keep it below the
      // status bar instead of running under the clock and notch.
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PlannedSessionForm(
        date: widget.date,
        initial: ps,
        routineState: widget.routineState,
      ),
    );
    if (result == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final updated = PlannedSession(
      id: ps.id,
      ownerUserId: ps.ownerUserId,
      scheduledDateMs: ps.scheduledDateMs,
      modality: result.modality,
      routineTemplateId: result.routineTemplateId,
      title: result.title.isNotEmpty ? result.title : null,
      note: result.note.isNotEmpty ? result.note : null,
      isCompleted: ps.isCompleted,
      linkedSessionId: ps.linkedSessionId,
      recurrenceRule: ps.recurrenceRule,
      createdAtMs: ps.createdAtMs,
      updatedAtMs: now,
    );

    final series = RecurrenceRule.tryParse(ps.recurrenceRule);
    if (series != null) {
      if (!context.mounted) return;
      final choice = await ConfirmationDialog.showThreeChoice(
        context: context,
        title: 'Change this session?',
        body: const Text('It is part of a repeating series.'),
        firstLabel: 'Just this one',
        secondLabel: 'This and all after it',
        cancelLabel: 'Cancel',
        cancelKey: const Key('day-session-series-edit-cancel'),
        firstKey: const Key('day-session-series-edit-one'),
        secondKey: const Key('day-session-series-edit-after'),
        isDestructive: false,
      );
      if (!context.mounted) return;
      switch (choice) {
        case ThreeChoice.first:
          await widget.calendarState.updatePlannedSession(updated);
        case ThreeChoice.second:
          await widget.calendarState.updateSeriesFrom(updated);
        case ThreeChoice.cancel:
          break;
      }
      return;
    }

    final repeat = result.rule;
    if (repeat != null) {
      // Repeat turned on for a plain plan (D-27711): this plan stays as the
      // first of the new series; only the LATER dates are created.
      await widget.calendarState.updatePlannedSession(
        PlannedSession(
          id: updated.id,
          ownerUserId: updated.ownerUserId,
          scheduledDateMs: updated.scheduledDateMs,
          modality: updated.modality,
          routineTemplateId: updated.routineTemplateId,
          title: updated.title,
          note: updated.note,
          isCompleted: updated.isCompleted,
          linkedSessionId: updated.linkedSessionId,
          recurrenceRule: repeat.encode(),
          createdAtMs: updated.createdAtMs,
          updatedAtMs: updated.updatedAtMs,
        ),
      );
      if (!context.mounted) return;
      try {
        await widget.calendarState.createRecurringPlannedSessions(
          first: widget.date,
          rule: repeat,
          skipFirst: true,
          modality: result.modality,
          routineTemplateId: result.routineTemplateId,
          title: result.title.isNotEmpty ? result.title : null,
          note: result.note.isNotEmpty ? result.note : null,
        );
      } catch (_) {
        if (context.mounted) {
          OmniMessage.error(context, 'Could not save. Try again.');
        }
      }
      return;
    }
    await widget.calendarState.updatePlannedSession(updated);
  }

  Future<void> _deletePlanned(BuildContext context, PlannedSession ps) async {
    final series = RecurrenceRule.tryParse(ps.recurrenceRule);
    if (series != null) {
      final choice = await ConfirmationDialog.showThreeChoice(
        context: context,
        title: 'Delete this session?',
        body: const Text('It is part of a repeating series.'),
        firstLabel: 'Just this one',
        secondLabel: 'This and all after it',
        cancelLabel: 'Cancel',
        cancelKey: const Key('day-session-delete-cancel'),
        firstKey: const Key('day-session-series-delete-one'),
        secondKey: const Key('day-session-series-delete-after'),
        isDestructive: true,
      );
      if (!context.mounted) return;
      switch (choice) {
        case ThreeChoice.first:
          await widget.calendarState.deletePlannedSession(ps.id);
        case ThreeChoice.second:
          await widget.calendarState.deleteSeriesFrom(ps);
        case ThreeChoice.cancel:
          break;
      }
      return;
    }

    final confirmed = await ConfirmationDialog.showTwoChoice(
      context: context,
      title: ps.title != null
          ? 'Delete "${ps.title}"?'
          : 'Delete this planned session?',
      dismissLabel: 'Cancel',
      confirmLabel: 'Delete',
      dismissKey: const Key('day-session-delete-cancel'),
      confirmKey: const Key('day-session-delete-confirm'),
      isDestructive: true,
    );
    if (confirmed) {
      await widget.calendarState.deletePlannedSession(ps.id);
    }
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _SessionRow extends StatelessWidget {
  final CalendarEntry entry;
  final RoutineState routineState;
  final VoidCallback? onTap;
  final VoidCallback? onStart;
  final VoidCallback? onDelete;

  const _SessionRow({
    required this.entry,
    required this.routineState,
    this.onTap,
    this.onStart,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final themeColors = OmniTheme.colorsForTheme(OmniTheme.activeTheme);
    final color = ModalityColorUtils.colorForModality(entry.modality);
    final label = _resolveLabel();
    final subtitle = _buildSubtitle();
    final stateColor = entry.isCompleted
        ? themeColors.primary
        : themeColors.textMuted;
    final feeling = entry.session?.sessionFeeling;
    final leftBorderColor = feeling != null
        ? feelingColor(feeling, themeColors)
        : null;

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: themeColors.surface.withOpacity(0.85),
            border: leftBorderColor != null
                ? Border(
                    left: BorderSide(color: leftBorderColor, width: 4),
                    top: BorderSide(color: themeColors.surfaceBorder),
                    right: BorderSide(color: themeColors.surfaceBorder),
                    bottom: BorderSide(color: themeColors.surfaceBorder),
                  )
                : Border.all(color: themeColors.surfaceBorder),
          ),
          child: ListTile(
            isThreeLine: entry.isCompleted && entry.session != null,
            leading: Container(
              width: 12,
              height: 12,
              decoration: entry.isCompleted
                  ? BoxDecoration(color: color, shape: BoxShape.circle)
                  : BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: color, width: 2),
                    ),
            ),
            title: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: OmniTheme.colors.textDominant,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  subtitle,
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: stateColor),
                ),
                if (entry.isCompleted && entry.session != null)
                  Text(
                    _formatTimeDuration(entry.session!),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: themeColors.textMuted,
                    ),
                  ),
              ],
            ),
            trailing: (onStart != null || onDelete != null)
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (onStart != null)
                        IconButton(
                          key: const Key('day-session-start'),
                          icon: const Icon(Icons.play_arrow, size: 24),
                          color: OmniTheme.colors.primary,
                          tooltip: 'Start session',
                          onPressed: onStart,
                        ),
                      if (onDelete != null)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          color: Theme.of(context).colorScheme.error,
                          tooltip: 'Delete session',
                          onPressed: onDelete,
                        ),
                    ],
                  )
                : null,
          ),
        ),
      ),
    );
  }

  String _resolveLabel() {
    final ps = entry.plannedSession;
    final session = entry.session;

    // Use custom title if available.
    if (ps?.title != null) return ps!.title!;
    if (session?.title != null) return session!.title!;

    // If planned session has routineTemplateId, resolve template name.
    if (ps?.routineTemplateId != null) {
      final template = routineState.routines
          .where((t) => t.id == ps!.routineTemplateId)
          .firstOrNull;
      if (template != null) {
        return template.name;
      } else {
        return 'Custom Routine';
      }
    }

    // Fall back to modality label.
    return ModalityColorUtils.labelForModality(entry.modality);
  }

  String _buildSubtitle() {
    final ps = entry.plannedSession;
    final modalityLabel = ModalityColorUtils.labelForModality(entry.modality);
    final stateLabel = entry.isCompleted ? 'Completed' : 'Planned';

    // If title is template name, don't repeat it — just show modality + state.
    if (ps?.routineTemplateId != null) {
      // Template name is already in the title: show only the Focus (if any) + state.
      if (entry.modality != null) return '$modalityLabel  ·  $stateLabel';
      return stateLabel;
    }

    return '$modalityLabel  ·  $stateLabel';
  }

  String _formatTimeDuration(TrainingSession session) {
    final start = DateTime.fromMillisecondsSinceEpoch(session.startedAtMs);
    final hour = start.hour;
    final minute = start.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final timeStr = '$hour12:$minute $period';

    if (session.endedAtMs == null) {
      return timeStr;
    }

    // Rolling sessions have no meaningful duration; show start time only.
    if (session.isRolling) return timeStr;

    final durationMs = session.endedAtMs! - session.startedAtMs;
    final totalMinutes = (durationMs / 60000).round();
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    final durationStr = hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';

    return '$timeStr · $durationStr';
  }
}

// ─── Bottom-sheet form ─────────────────────────────────────────────────────────

class _PlannedSessionFormResult {
  final String? modality;
  final String? routineTemplateId;
  final String title;
  final String note;

  /// The Repeat rule the sheet produced (D-27708); null while the sheet has
  /// no Repeat UI yet (P3a wiring only — P3b fills it from the settings).
  final RecurrenceRule? rule;
  const _PlannedSessionFormResult({
    required this.modality,
    required this.routineTemplateId,
    required this.title,
    required this.note,
    this.rule,
  });
}

class _PlannedSessionForm extends StatefulWidget {
  final DateTime date;
  final PlannedSession? initial;
  final RoutineState routineState;

  const _PlannedSessionForm({
    required this.date,
    required this.initial,
    required this.routineState,
  });

  @override
  State<_PlannedSessionForm> createState() => _PlannedSessionFormState();
}

class _PlannedSessionFormState extends State<_PlannedSessionForm> {
  late TextEditingController _titleCtrl;
  late TextEditingController _noteCtrl;

  // Repeat settings (plan 277). A Repeat OFF resets them to these defaults,
  // so a later ON starts clean (S-27726).
  bool _repeatOn = false;
  int _every = 1;
  RecurrenceUnit _unit = RecurrenceUnit.week;
  late final Set<int> _weekdays;
  RecurrenceEnd _endMode = RecurrenceEnd.count;
  int _count = 8;
  DateTime? _until;
  late final TextEditingController _countCtrl;

  static const _weekdayLabels = <String>[
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  // Mode: 'free' or 'routine'
  String _mode = 'free';

  // For 'free' mode:
  String? _selectedModality;

  // For 'routine' mode:
  String? _selectedTemplateId;

  static const _modalities = [
    null,
    Modality.cardioEndurance,
    Modality.resistanceLifting,
    Modality.sports,
    Modality.isometricStretching,
  ];

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.initial?.title ?? '');
    _noteCtrl = TextEditingController(text: widget.initial?.note ?? '');
    _weekdays = <int>{widget.date.weekday};
    _countCtrl = TextEditingController(text: '8');

    if (widget.initial?.routineTemplateId != null) {
      _mode = 'routine';
      _selectedTemplateId = widget.initial!.routineTemplateId;
    } else {
      _mode = 'free';
      _selectedModality = widget.initial?.modality;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _noteCtrl.dispose();
    _countCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeColors = OmniTheme.colorsForTheme(OmniTheme.activeTheme);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        decoration: BoxDecoration(
          color: themeColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.initial == null
                        ? 'New Planned Session'
                        : 'Edit Session',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: themeColors.textMuted,
                    ),
                    // Long localized titles can exceed the 360 px
                    // form width when paired with the trailing
                    // IconButton; ellipsis keeps the layout
                    // constrained instead of throwing a
                    // RenderFlex overflow (26 px was observed on
                    // a phone-width sheet).
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  color: themeColors.textMuted,
                ),
              ],
            ),
            const SizedBox(height: 16),

            Text(
              'Session Type',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: themeColors.textMuted,
              ),
            ),
            const SizedBox(height: 8),

            // Mode selector: Free Training vs Routine
            Row(
              children: [
                Expanded(
                  child: (_mode == 'free')
                      ? FilledButton(
                          style: _selectedModeButtonStyle(
                            theme,
                          ).copyWith(shape: _modeButtonShape),
                          onPressed: () => setState(() => _mode = 'free'),
                          child: const Text(
                            'Free Training',
                            textAlign: TextAlign.center,
                            maxLines: 2,
                          ),
                        )
                      : OutlinedButton(
                          style: _unselectedModeButtonStyle(
                            theme,
                          ).copyWith(shape: _modeButtonShape),
                          onPressed: () => setState(() => _mode = 'free'),
                          child: const Text(
                            'Free Training',
                            textAlign: TextAlign.center,
                            maxLines: 2,
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: (_mode == 'routine')
                      ? FilledButton(
                          style: _selectedModeButtonStyle(
                            theme,
                          ).copyWith(shape: _modeButtonShape),
                          onPressed: () => setState(() => _mode = 'routine'),
                          child: const Text(
                            'Routine',
                            textAlign: TextAlign.center,
                            maxLines: 2,
                          ),
                        )
                      : OutlinedButton(
                          style: _unselectedModeButtonStyle(
                            theme,
                          ).copyWith(shape: _modeButtonShape),
                          onPressed: () => setState(() => _mode = 'routine'),
                          child: const Text(
                            'Routine',
                            textAlign: TextAlign.center,
                            maxLines: 2,
                          ),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Picker based on mode
            if (_mode == 'free')
              DropdownButtonFormField<String?>(
                initialValue: _selectedModality,
                isExpanded: true,
                decoration: _fieldDecoration('Modality', theme),
                items: _modalities
                    .map(
                      (m) => DropdownMenuItem<String?>(
                        value: m,
                        child: Text(ModalityColorUtils.labelForModality(m)),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _selectedModality = v),
              )
            else
              DropdownButtonFormField<String?>(
                initialValue: _selectedTemplateId,
                isExpanded: true,
                decoration: _fieldDecoration('Routine', theme),
                items: widget.routineState.routines
                    .map(
                      (t) => DropdownMenuItem<String?>(
                        value: t.id,
                        child: Text(t.name),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _selectedTemplateId = v),
              ),
            const SizedBox(height: 12),

            TextField(
              textCapitalization: TextCapitalization.words,
              controller: _titleCtrl,
              style: theme.textTheme.bodyMedium,
              decoration: _fieldDecoration('Title (optional)', theme),
            ),
            const SizedBox(height: 12),
            TextField(
              textCapitalization: TextCapitalization.sentences,
              controller: _noteCtrl,
              style: theme.textTheme.bodyMedium,
              decoration: _fieldDecoration('Notes (optional)', theme),
              maxLines: 2,
            ),
            const SizedBox(height: 20),
            ..._repeatSection(theme, themeColors),
            SizedBox(
              height: OmniTheme.buttonPrimaryHeight,
              width: double.infinity,
              child: FilledButton(
                style: ButtonStyle(
                  shape: WidgetStateProperty.all(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        OmniTheme.buttonBorderRadius,
                      ),
                    ),
                  ),
                ),
                // A Routine plan needs a routine: without one the button is
                // off, so it can never save as Free Training (plan 262).
                // A repeat with `On date` and no date chosen is not ready.
                onPressed:
                    ((_mode == 'routine' && _selectedTemplateId == null) ||
                        !_repeatReady)
                    ? null
                    : _submit,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    widget.initial == null ? 'Add Session' : 'Save Changes',
                  ),
                ),
              ),
            ),
          ],
        ),
        ), // SingleChildScrollView
      ),
    );
  }

  List<Widget> _repeatSection(ThemeData theme, OmniThemeColors themeColors) {
    // A row already in a series shows a read-only line only (D-27709): the
    // pattern of a series cannot be changed from one row's edit sheet.
    final series = widget.initial == null
        ? null
        : RecurrenceRule.tryParse(widget.initial!.recurrenceRule);
    if (series != null) {
      final d = series.describe(widget.date);
      return [
        Text(
          'Repeats ${d[0].toLowerCase()}${d.substring(1)}',
          key: const Key('repeat-series-summary'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: themeColors.textMuted,
          ),
        ),
        const SizedBox(height: 20),
      ];
    }

    final rows = <Widget>[
      Row(
        children: [
          Text(
            'Repeat',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: themeColors.textMuted,
            ),
          ),
          const Spacer(),
          Switch(
            key: const Key('repeat-switch'),
            value: _repeatOn,
            onChanged: (on) => setState(() {
              _repeatOn = on;
              if (!on) {
                // Off drops every setting, so a later ON starts clean
                // (S-27726).
                _every = 1;
                _unit = RecurrenceUnit.week;
                _weekdays
                  ..clear()
                  ..add(widget.date.weekday);
                _endMode = RecurrenceEnd.count;
                _count = 8;
                _countCtrl.text = '8';
                _until = null;
              }
            }),
          ),
        ],
      ),
    ];
    if (!_repeatOn) {
      return [...rows, const SizedBox(height: 20)];
    }

    rows.add(const SizedBox(height: 12));
    rows.add(
      Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              key: const Key('repeat-every'),
              initialValue: _every,
              isExpanded: true,
              decoration: _fieldDecoration('Every', theme),
              items: List.generate(12, (index) => index + 1)
                  .map(
                    (n) => DropdownMenuItem<int>(value: n, child: Text('$n')),
                  )
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _every = v);
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<RecurrenceUnit>(
              key: const Key('repeat-unit'),
              initialValue: _unit,
              isExpanded: true,
              decoration: _fieldDecoration('Unit', theme),
              items: const <DropdownMenuItem<RecurrenceUnit>>[
                DropdownMenuItem(
                  value: RecurrenceUnit.day,
                  child: Text('Days'),
                ),
                DropdownMenuItem(
                  value: RecurrenceUnit.week,
                  child: Text('Weeks'),
                ),
                DropdownMenuItem(
                  value: RecurrenceUnit.month,
                  child: Text('Months'),
                ),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _unit = v);
              },
            ),
          ),
        ],
      ),
    );

    if (_unit == RecurrenceUnit.week) {
      rows.add(const SizedBox(height: 12));
      rows.add(
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var day = 1; day <= 7; day++)
              FilterChip(
                key: Key('repeat-weekday-$day'),
                showCheckmark: false,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    OmniTheme.buttonUtilityRadius,
                  ),
                ),
                selected: _weekdays.contains(day),
                onSelected: day == widget.date.weekday
                    // The planned day is always the first session: its chip
                    // can never be un-ticked.
                    ? (_) {}
                    : (ticked) => setState(() {
                        if (ticked) {
                          _weekdays.add(day);
                        } else {
                          _weekdays.remove(day);
                        }
                      }),
                label: Text(_weekdayLabels[day - 1]),
              ),
          ],
        ),
      );
    }

    rows.add(const SizedBox(height: 12));
    rows.add(
      Text(
        'Ends',
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: themeColors.textMuted,
        ),
      ),
    );
    rows.add(const SizedBox(height: 8));
    rows.add(
      Row(
        children: [
          Expanded(
            child: _endMode == RecurrenceEnd.count
                ? FilledButton(
                    key: const Key('repeat-end-count'),
                    style: _selectedModeButtonStyle(theme).copyWith(
                      shape: _modeButtonShape,
                    ),
                    onPressed: () =>
                        setState(() => _endMode = RecurrenceEnd.count),
                    child: const Text(
                      'After',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                    ),
                  )
                : OutlinedButton(
                    key: const Key('repeat-end-count'),
                    style: _unselectedModeButtonStyle(theme).copyWith(
                      shape: _modeButtonShape,
                    ),
                    onPressed: () =>
                        setState(() => _endMode = RecurrenceEnd.count),
                    child: const Text(
                      'After',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _endMode == RecurrenceEnd.date
                ? FilledButton(
                    key: const Key('repeat-end-date'),
                    style: _selectedModeButtonStyle(theme).copyWith(
                      shape: _modeButtonShape,
                    ),
                    onPressed: () =>
                        setState(() => _endMode = RecurrenceEnd.date),
                    child: const Text(
                      'On date',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                    ),
                  )
                : OutlinedButton(
                    key: const Key('repeat-end-date'),
                    style: _unselectedModeButtonStyle(theme).copyWith(
                      shape: _modeButtonShape,
                    ),
                    onPressed: () =>
                        setState(() => _endMode = RecurrenceEnd.date),
                    child: const Text(
                      'On date',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                    ),
                  ),
          ),
        ],
      ),
    );

    rows.add(const SizedBox(height: 12));
    if (_endMode == RecurrenceEnd.count) {
      rows.add(
        NumericFieldWithDoneBar(
          key: const Key('repeat-count'),
          controller: _countCtrl,
          decoration: _fieldDecoration('Sessions', theme),
          onChanged: (text) => setState(() {
            final parsed = int.tryParse(text) ?? 2;
            _count = parsed < 2 ? 2 : (parsed > 366 ? 366 : parsed);
          }),
        ),
      );
    } else {
      final firstDate = DateTime(
        widget.date.year,
        widget.date.month,
        widget.date.day + 1,
      );
      final lastDate = DateTime(
        widget.date.year + 1,
        widget.date.month,
        widget.date.day,
      );
      final firstPlus7 = DateTime(
        widget.date.year,
        widget.date.month,
        widget.date.day + 7,
      );
      final initialCandidate = _until ?? firstPlus7;
      final initial = initialCandidate.isBefore(firstDate)
          ? firstDate
          : (initialCandidate.isAfter(lastDate) ? lastDate : initialCandidate);
      rows.add(
        OutlinedButton(
          key: const Key('repeat-until'),
          style: _unselectedModeButtonStyle(theme).copyWith(
            shape: _modeButtonShape,
          ),
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: initial,
              firstDate: firstDate,
              lastDate: lastDate,
            );
            if (picked == null) return;
            // The picker already bounds the range; guard anyway.
            if (picked.isBefore(firstDate) || picked.isAfter(lastDate)) return;
            setState(() => _until = picked);
          },
          child: Text(
            _until == null
                ? 'Choose date'
                : '${_until!.day} '
                      '${OmniDateUtils.shortMonthName(_until!.month)} '
                      '${_until!.year}',
          ),
        ),
      );
    }

    rows.add(const SizedBox(height: 12));
    final rule = _liveRule();
    rows.add(
      Text(
        (_endMode == RecurrenceEnd.date && _until == null)
            ? 'Choose an end date'
            : rule.summary(widget.date, rule.dates(widget.date).length),
        key: const Key('repeat-summary'),
        style: theme.textTheme.bodySmall?.copyWith(
          color: themeColors.textMuted,
        ),
      ),
    );
    rows.add(const SizedBox(height: 20));
    return rows;
  }

  RecurrenceRule _liveRule() {
    return RecurrenceRule(
      series: 'preview',
      unit: _unit,
      every: _every,
      weekdays: _weekdays.toList()..sort(),
      end: _endMode,
      count: _count,
      until: _until,
    );
  }

  bool get _repeatReady =>
      !_repeatOn || _endMode == RecurrenceEnd.count || _until != null;

  static final WidgetStateProperty<OutlinedBorder?> _modeButtonShape =
      WidgetStateProperty.all(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OmniTheme.buttonBorderRadius),
        ),
      );

  ButtonStyle _selectedModeButtonStyle(ThemeData theme) {
    return ButtonStyle(
      minimumSize: WidgetStateProperty.all(const Size.fromHeight(52)),
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      backgroundColor: WidgetStateProperty.all(
        theme.colorScheme.primary.withValues(alpha: 0.22),
      ),
      foregroundColor: WidgetStateProperty.all(theme.colorScheme.onSurface),
      side: WidgetStateProperty.all(
        BorderSide(
          color: theme.colorScheme.primary.withValues(alpha: 0.75),
          width: 1.2,
        ),
      ),
    );
  }

  ButtonStyle _unselectedModeButtonStyle(ThemeData theme) {
    return ButtonStyle(
      minimumSize: WidgetStateProperty.all(const Size.fromHeight(52)),
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      foregroundColor: WidgetStateProperty.all(theme.colorScheme.onSurface),
      side: WidgetStateProperty.all(
        BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.55),
          width: 1.2,
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(String label, ThemeData theme) {
    return InputDecoration(
      labelText: label,
      labelStyle: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.55),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.4),
      ),
      border: OutlineInputBorder(
        borderSide: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.55),
        ),
      ),
    );
  }

  void _submit() {
    Navigator.pop(
      context,
      _PlannedSessionFormResult(
        modality: _mode == 'free' ? _selectedModality : null,
        routineTemplateId: _mode == 'routine' ? _selectedTemplateId : null,
        title: _titleCtrl.text.trim(),
        note: _noteCtrl.text.trim(),
        rule: _repeatOn
            ? RecurrenceRule(
                series: const Uuid().v4(),
                unit: _unit,
                every: _every,
                weekdays: _weekdays.toList()..sort(),
                end: _endMode,
                count: _count,
                until: _endMode == RecurrenceEnd.date ? _until : null,
              )
            : null,
      ),
    );
  }
}
