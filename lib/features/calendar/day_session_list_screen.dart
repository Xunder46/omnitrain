import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';
import '../../core/navigation/navigation.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/modality_color_utils.dart';
import '../../core/utils/session_feeling_utils.dart';
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

/// Shows all sessions (planned + completed TrainingSessions) for a single day.
///
/// Behavior by date:
///   Past:          read-only list, no add/edit/delete.
///   Today/Future:  completed sessions shown but non-editable;
///                  planned sessions can be added, edited, deleted, and tapped to start.
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

  List<CalendarEntry> get _inProgressEntries =>
      _allEntries.where((e) => !e.isCompleted && e.session != null).toList();

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
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.calendarState,
          builder: (context, _) {
            final completed = _completedEntries;
            final inProgress = _inProgressEntries;
            final planned = _plannedEntries;
            final isEmpty =
                completed.isEmpty && inProgress.isEmpty && planned.isEmpty;

            return Column(
              children: [
                Expanded(
                  child: isEmpty
                      ? _EmptyState(isPast: _isPast)
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          children: [
                            if (completed.isNotEmpty) ...[
                              const _SectionHeader(title: 'Completed'),
                              ...completed.map(
                                (e) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _SessionRow(
                                    entry: e,
                                    routineState: widget.routineState,
                                    onTap: () => _tapCompleted(context, e),
                                    onEdit: null,
                                    onDelete: null,
                                  ),
                                ),
                              ),
                              if (planned.isNotEmpty)
                                const SizedBox(height: 12),
                            ],
                            if (planned.isNotEmpty) ...[
                              const _SectionHeader(title: 'Planned'),
                              ...planned.map((e) {
                                final isEditable = _isTodayOrFuture;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _SessionRow(
                                    entry: e,
                                    routineState: widget.routineState,
                                    onTap: isEditable
                                        ? () => _tapPlanned(context, e)
                                        : null,
                                    onEdit: isEditable
                                        ? () => _editPlanned(context, e)
                                        : null,
                                    onDelete: isEditable
                                        ? () => _deletePlanned(
                                            context,
                                            e.plannedSession!,
                                          )
                                        : null,
                                  ),
                                );
                              }),
                            ],
                            if (inProgress.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              const _SectionHeader(title: 'In Progress'),
                              ...inProgress.map(
                                (e) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _SessionRow(
                                    entry: e,
                                    routineState: widget.routineState,
                                    onTap: null,
                                    onEdit: null,
                                    onDelete: null,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                ),
                if (_isTodayOrFuture)
                  _AddButton(onTap: () => _addPlanned(context)),
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

    // Load the historical session into workoutState, then show summary.
    await widget.workoutState.loadHistoricalSession(sessionId);

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
  }

  // ─── Navigation: Tap planned session → start workout ─────────────────────

  Future<void> _tapPlanned(BuildContext context, CalendarEntry entry) async {
    final ps = entry.plannedSession;
    if (ps == null) return;

    // Check if user has an active session already.
    if (widget.workoutState.hasActiveSession) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Start New Session?'),
          content: const Text(
            'Starting this session will save your current session first.',
          ),
          actions: [
            TextButton(
              style: ButtonStyle(
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      OmniTheme.buttonUtilityRadius,
                    ),
                  ),
                ),
              ),
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: ButtonStyle(
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      OmniTheme.buttonUtilityRadius,
                    ),
                  ),
                ),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Start New'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    try {
      widget.workoutState.clearSession();

      if (ps.routineTemplateId != null) {
        // Start routine-based session.
        final manifest = await widget.routineSessionService
            .buildSessionFromTemplate(ps.routineTemplateId!);

        await widget.workoutState.createNewSession(
          modality: null,
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
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Session saved, but failed to link planned session: $e',
                    ),
                  ),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error starting session: $e')));
      }
    }
  }

  // ─── CRUD: Add planned session ────────────────────────────────────────────

  Future<void> _addPlanned(BuildContext context) async {
    await widget.routineState.loadRoutines();
    final result = await showModalBottomSheet<_PlannedSessionFormResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PlannedSessionForm(
        date: widget.date,
        initial: null,
        routineState: widget.routineState,
      ),
    );
    if (result == null) return;

    await widget.calendarState.createPlannedSession(
      date: widget.date,
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
    await widget.calendarState.updatePlannedSession(updated);
  }

  Future<void> _deletePlanned(BuildContext context, PlannedSession ps) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Session'),
        content: Text('Delete "${ps.title ?? 'this planned session'}"?'),
        actions: [
          TextButton(
            style: ButtonStyle(
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    OmniTheme.buttonUtilityRadius,
                  ),
                ),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: ButtonStyle(
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    OmniTheme.buttonUtilityRadius,
                  ),
                ),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.calendarState.deletePlannedSession(ps.id);
    }
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool isPast;
  const _EmptyState({required this.isPast});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        isPast ? 'No sessions on this day.' : 'No sessions planned yet.',
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: OmniTheme.textSecondary.withOpacity(0.6),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: OmniTheme.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: SizedBox(
        height: OmniTheme.buttonPrimaryHeight,
        width: double.infinity,
        child: OutlinedButton.icon(
          style: ButtonStyle(
            shape: WidgetStateProperty.all(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  OmniTheme.buttonBorderRadius,
                ),
              ),
            ),
          ),
          onPressed: onTap,
          icon: const Icon(Icons.add),
          label: const FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('Add Planned Session'),
          ),
        ),
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  final CalendarEntry entry;
  final RoutineState routineState;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _SessionRow({
    required this.entry,
    required this.routineState,
    this.onTap,
    this.onEdit,
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
        ? feelingColor(feeling, context)
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
                color: OmniTheme.textPrimary,
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
            trailing: (onEdit != null || onDelete != null)
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (onEdit != null)
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          color: OmniTheme.textSecondary,
                          onPressed: onEdit,
                        ),
                      if (onDelete != null)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          color: Colors.redAccent,
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
    final session = entry.session;
    final modalityLabel = ModalityColorUtils.labelForModality(entry.modality);
    final stateLabel = entry.isCompleted ? 'Completed' : 'Planned';

    if (session != null && !entry.isCompleted) {
      return '$modalityLabel  ·  In Progress';
    }

    // If title is template name, don't repeat it — just show modality + state.
    if (ps?.routineTemplateId != null) {
      return stateLabel; // Template name is already in title.
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
  const _PlannedSessionFormResult({
    required this.modality,
    required this.routineTemplateId,
    required this.title,
    required this.note,
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  widget.initial == null
                      ? 'Add Planned Session'
                      : 'Edit Session',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: themeColors.textMuted,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
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
                          style: _selectedModeButtonStyle(theme),
                          onPressed: () => setState(() => _mode = 'free'),
                          child: const Text(
                            'Free Training',
                            textAlign: TextAlign.center,
                            maxLines: 2,
                          ),
                        )
                      : OutlinedButton(
                          style: _unselectedModeButtonStyle(theme),
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
                          style: _selectedModeButtonStyle(theme),
                          onPressed: () => setState(() => _mode = 'routine'),
                          child: const Text(
                            'Routine',
                            textAlign: TextAlign.center,
                            maxLines: 2,
                          ),
                        )
                      : OutlinedButton(
                          style: _unselectedModeButtonStyle(theme),
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
                onPressed: _submit,
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
      ),
    );
  }

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
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OmniTheme.buttonBorderRadius),
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
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OmniTheme.buttonBorderRadius),
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
      ),
    );
  }
}
