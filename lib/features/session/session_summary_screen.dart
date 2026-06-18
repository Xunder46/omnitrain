import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';
import '../../core/constants/modality_display.dart';
import '../../core/constants/modality_colors.dart';
import '../../core/services/session_summary_service.dart';
import '../../core/models/session_summary.dart';
import '../../core/constants/modality_config.dart';
import '../../core/constants/effort_defaults.dart';
import '../../core/services/routine_session_service.dart';
import '../../core/utils/session_feeling_utils.dart';
import '../../core/utils/unit_formatter.dart';
import '../../state/settings/settings_state.dart';
import '../../state/workout/workout_state.dart';
import '../../state/routine/routine_state.dart';
import '../../state/calendar/calendar_state.dart';
import '../../state/period/period_state.dart';
import '../../widgets/layout/omni_bottom_cta.dart';
import '../../widgets/layout/omni_back_header.dart';
import '../../widgets/layout/omni_card_header.dart';
import '../../widgets/layout/omni_surface.dart';
import '../exercise/exercise_picker_screen.dart';
import '../../widgets/pickers/metric_chooser_dialog.dart';
import '../../data/models/models.dart';
import '../../core/utils/timer_alert_service.dart';
import '../../core/utils/rest_notification_service.dart';
import '../calendar/calendar_screen.dart';
import 'workout_session_screen.dart';
import '../../core/navigation/navigation.dart';

class SessionSummaryScreen extends StatefulWidget {
  final WorkoutState workoutState;
  final RoutineState routineState;
  final SessionSummaryService sessionSummaryService;
  final Future<void> Function(String sessionId)? onSessionSaved;
  final SettingsState settingsState;
  final TimerAlertService timerAlertService;
  final RestNotificationService restNotificationService;

  SessionSummaryScreen({
    super.key,
    required this.workoutState,
    required this.routineState,
    required this.sessionSummaryService,
    this.onSessionSaved,
    required this.settingsState,
    required this.timerAlertService,
    RestNotificationService? restNotificationService,
  }) : restNotificationService =
           restNotificationService ?? RestNotificationService.noop();

  @override
  State<SessionSummaryScreen> createState() => _SessionSummaryScreenState();
}

class _SessionSummaryScreenState extends State<SessionSummaryScreen> {
  late SessionSummary _summary;
  late TextEditingController _noteController;
  Timer? _noteDebounce;
  bool _isLoading = true;
  bool _hasShownFeelingSheet = false;

  Map<String, GroupDelta> _groupDeltas = {};
  Map<String, List<PRAchievement>> _prsByGroup = {};
  Map<String, SessionGroupMetrics> _groupMetrics = {};
  int _restTimeMs = 0;
  String _preferredWeightUnit = 'kg';
  Set<int> _workoutDays = {};
  int _daysInMonth = 30;
  late final CalendarState _calendarState;
  late final PeriodState _periodState;
  late final RoutineSessionService _routineSessionService;

  List<SessionTemplateExercise> _draftExercises = [];

  // ──── Modality grouping constants (presentation only) ────────────────────

  /// Fixed render order for modality groups on the summary screen.
  static const _groupOrder = ['strength', 'cardio', 'rounds', 'isometric'];

  /// Display labels for each group (per design spec).
  static const _groupLabels = {
    'strength': 'Strength',
    'cardio': 'Cardio',
    'rounds': 'Sports',
    'isometric': 'Isometric',
  };

  @override
  void initState() {
    super.initState();
    final repository = widget.workoutState.repository;
    _calendarState = CalendarState(repository);
    // CalendarState.init() is async but its first statement is the
    // synchronous `_year = now.year` assignment (no `await` before it),
    // so a fire-and-forget call is sufficient to prime the late
    // fields. Without this call, tapping "Open Calendar" in the
    // calendar card throws `LateInitializationError` on the late
    // `_year` field (Phase 4 review feedback — was A5 in the plan).
    _calendarState.init();
    _periodState = PeriodState(repository);
    _routineSessionService = RoutineSessionService(repository);
    _summary = widget.workoutState.computeSessionSummary();
    _noteController = TextEditingController(
      text: widget.workoutState.currentSession?.note ?? '',
    );
    _draftExercises = widget.workoutState.buildTemplateDraftExercises();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showFeelingSheet(context);
    });
    _loadAsyncData();
  }

  @override
  void dispose() {
    _noteDebounce?.cancel();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadAsyncData() async {
    setState(() => _isLoading = true);

    final currentSession = widget.workoutState.currentSession;
    if (currentSession != null) {
      final groupDeltas = await widget.sessionSummaryService
          .compareGroupsToPreviousSession(currentSession, _summary);
      final prs = await widget.sessionSummaryService.computePRs(
        _summary.exercises,
      );
      final groupedPrs = widget.sessionSummaryService.groupPrsByEffortKind(
        prs,
        _summary.exercises,
      );
      final groupMetrics = await widget.sessionSummaryService.buildGroupMetrics(
        _summary,
      );
      final restTimeMs = await widget.sessionSummaryService
          .computeSessionRestTimeMs(currentSession.id);
      final preferredWeightUnit = await widget.sessionSummaryService
          .getPreferredWeightUnit();
      await _loadCalendarData();

      if (!mounted) return;

      setState(() {
        _groupDeltas = groupDeltas;
        _prsByGroup = groupedPrs;
        _groupMetrics = groupMetrics;
        _restTimeMs = restTimeMs;
        _preferredWeightUnit = preferredWeightUnit;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadCalendarData() async {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    _daysInMonth = DateTime(now.year, now.month + 1, 0).day;

    final sessions = await widget.workoutState.getSessionsByDateRange(
      monthStart.millisecondsSinceEpoch,
      monthEnd.millisecondsSinceEpoch,
    );

    final days = <int>{};
    for (final session in sessions) {
      if (session.endedAtMs == null) continue;
      final day = DateTime.fromMillisecondsSinceEpoch(session.startedAtMs).day;
      days.add(day);
    }

    final currentSession = widget.workoutState.currentSession;
    if (currentSession != null) {
      final currentDay = DateTime.fromMillisecondsSinceEpoch(
        currentSession.startedAtMs,
      ).day;
      days.add(currentDay);
    }

    _workoutDays = days;
  }

  void _handleNoteChanged(String value) {
    _noteDebounce?.cancel();
    _noteDebounce = Timer(const Duration(milliseconds: 600), () async {
      await widget.workoutState.updateSessionNote(value.trim());
    });
  }

  Future<void> _refreshSummary() async {
    setState(() {
      _summary = widget.workoutState.computeSessionSummary();
      _draftExercises = widget.workoutState.buildTemplateDraftExercises();
    });
    await _loadAsyncData();
  }

  Future<void> _showFeelingSheet(BuildContext context) async {
    if (!widget.settingsState.showFeelingSurvey) return;
    if (_hasShownFeelingSheet) return;

    final session = widget.workoutState.currentSession;
    if (session == null) return;
    if (session.sessionFeeling != null) return;

    _hasShownFeelingSheet = true;

    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      isScrollControlled: true,
      builder: (context) => _FeelingSheetContent(
        workoutState: widget.workoutState,
        modality: session.modality,
      ),
    );
  }

  Future<void> _showDiscardDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard session?'),
        content: const Text(
          'This will remove all session data and return to Home.',
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
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
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
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _discardSession();
    }
  }

  Future<void> _discardSession() async {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    await widget.workoutState.discardCurrentSession();

    if (!mounted) return;

    Navigator.pop(context);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _finishAndSaveSession() async {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    await widget.workoutState.endSession();
    final completedSessionId = widget.workoutState.currentSession?.id;
    if (completedSessionId != null && widget.onSessionSaved != null) {
      await widget.onSessionSaved!(completedSessionId);
    }
    widget.workoutState.clearSession();

    if (!mounted) return;

    Navigator.pop(context);
    Navigator.of(context).popUntil((route) => route.isFirst);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Workout session saved successfully'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openEditSession() async {
    await OmniNavigator.push(
      context,
      (_) => WorkoutSessionScreen(
        workoutState: widget.workoutState,
        routineState: widget.routineState,
        sessionSummaryService: widget.sessionSummaryService,
        settingsState: widget.settingsState,
        timerAlertService: widget.timerAlertService,
        restNotificationService: widget.restNotificationService,
        editMode: true,
      ),
    );

    if (mounted) {
      await _refreshSummary();
    }
  }

  Future<void> _openCalendarScreen() async {
    await OmniNavigator.push(
      context,
      (_) => CalendarScreen(
        calendarState: _calendarState,
        periodState: _periodState,
        workoutState: widget.workoutState,
        routineState: widget.routineState,
        routineSessionService: _routineSessionService,
        sessionSummaryService: widget.sessionSummaryService,
        settingsState: widget.settingsState,
        timerAlertService: widget.timerAlertService,
        restNotificationService: widget.restNotificationService,
      ),
    );
  }

  Future<void> _openSaveAsRoutineSheet() async {
    final session = widget.workoutState.currentSession;
    if (session == null) return;

    final date = DateTime.fromMillisecondsSinceEpoch(session.startedAtMs);
    final defaultName =
        '${ModalityDisplay.getName(session.modality)} - ${_formatDate(date)}';
    final nameController = TextEditingController(text: defaultName);

    final exercises = List<SessionTemplateExercise>.from(_draftExercises);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> addExercise() async {
              final modality = session.modality;
              final selectedExercise = await OmniNavigator.push<Exercise>(
                context,
                (_) => ExercisePickerScreen(
                  workoutState: widget.workoutState,
                  sessionModality: modality,
                ),
              );

              if (selectedExercise == null) return;

              String? chosenMetric;
              if (modality == null) {
                chosenMetric = await showDialog<String>(
                  context: context,
                  builder: (context) =>
                      MetricChooserDialog(exercise: selectedExercise),
                );

                if (chosenMetric == null) return;
              }

              final effortKind = modality != null
                  ? ModalityConfig.forModality(modality)?.effortKind ?? 'set'
                  : (chosenMetric != null
                        ? ModalityConfig.effortKindFromMetric(chosenMetric)
                        : 'set');

              final defaults = EffortDefaults.getDefaultTargets(effortKind);
              final targets = defaults.entries
                  .map(
                    (entry) => TemplateTargetDraft(
                      metricId: entry.key,
                      setIndex: 0,
                      unitId: null,
                      valueReal: entry.value is double
                          ? entry.value as double
                          : null,
                      valueInt: entry.value is int ? entry.value as int : null,
                      valueText: entry.value is String
                          ? entry.value as String
                          : null,
                    ),
                  )
                  .toList();

              setSheetState(() {
                exercises.add(
                  SessionTemplateExercise(
                    exerciseId: selectedExercise.id,
                    name: selectedExercise.name,
                    effortKind: effortKind,
                    targets: targets,
                  ),
                );
              });
            }

            return SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Save as Routine',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          onPressed: addExercise,
                          icon: const Icon(Icons.add),
                          tooltip: 'Add exercise',
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      textCapitalization: TextCapitalization.words,
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Routine name',
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 320,
                      child: ReorderableListView.builder(
                        itemCount: exercises.length,
                        onReorder: (oldIndex, newIndex) {
                          setSheetState(() {
                            if (newIndex > oldIndex) newIndex -= 1;
                            final item = exercises.removeAt(oldIndex);
                            exercises.insert(newIndex, item);
                          });
                        },
                        itemBuilder: (context, index) {
                          final exercise = exercises[index];
                          return ListTile(
                            key: ValueKey('${exercise.exerciseId}-$index'),
                            title: Text(exercise.name),
                            subtitle: Text(exercise.effortKind),
                            trailing: IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                setSheetState(() {
                                  exercises.removeAt(index);
                                });
                              },
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
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
                        onPressed: exercises.isEmpty
                            ? null
                            : () async {
                                final draft = SessionTemplateDraft(
                                  name: nameController.text.trim().isEmpty
                                      ? defaultName
                                      : nameController.text.trim(),
                                  focusModality: session.modality,
                                  exercises: exercises,
                                );

                                await widget.sessionSummaryService
                                    .saveRoutineFromDraft(
                                      draft,
                                      focusModality: session.modality,
                                    );

                                await widget.routineState.loadRoutines();
                                if (!mounted) return;
                                Navigator.pop(context);
                                await _finishAndSaveSession();
                              },
                        child: const Text('Save Routine'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    nameController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = widget.workoutState.currentSession;
    final title = session?.title ?? ModalityDisplay.getName(session?.modality);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      extendBodyBehindAppBar: true,
      appBar: OmniBackHeader(
        title: title,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'edit':
                  _openEditSession();
                  break;
                case 'save':
                  _openSaveAsRoutineSheet();
                  break;
                case 'discard':
                  _showDiscardDialog();
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'edit',
                child: Text('Edit Session'),
              ),
              PopupMenuItem(
                value: 'save',
                child: Text('Save as Routine'),
              ),
              PopupMenuItem(
                value: 'discard',
                child: Text('Discard'),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      // The date header (with the modality chip) is
                      // always rendered — even when the combined
                      // Duration/Rest Time card is hidden for a
                      // rolling session. The header acts as a
                      // day-context reminder; the card body is the
                      // only part that the rolling branch omits.
                      _buildSessionInfoHeader(theme),
                      if (!widget.workoutState.isRollingSession) ...[
                        _buildSessionInfoCard(theme),
                      ],
                      ..._buildGroupCards(theme),
                      const SizedBox(height: 16),
                      const OmniCardHeader(title: 'SESSION NOTE'),
                      _buildNoteCard(theme),
                      const SizedBox(height: 16),
                      _buildCalendarHeader(theme),
                      _buildCalendarCard(theme),
                      if (_isLoading)
                        Padding(
                          padding: const EdgeInsets.only(top: 24.0),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      const SizedBox(height: 120),
                    ]),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: OmniBottomCTA(
              label: 'Done',
              onPressed: _finishAndSaveSession,
            ),
          ),
        ],
      ),
    );
  }

  /// Header for the first (combined session info) card. The date+time
  /// is the title; the modality chip sits in the actions slot on the
  /// right (per the Phase 2.2 refinement — chip belongs to the first
  /// card, not the page-level header).
  Widget _buildSessionInfoHeader(ThemeData theme) {
    final session = widget.workoutState.currentSession;
    final startedAt = session != null
        ? DateTime.fromMillisecondsSinceEpoch(session.startedAtMs)
        : DateTime.now();
    return OmniCardHeader(
      key: const Key('omni_session_info_header'),
      title: _formatDateTime(startedAt),
      actions: [_buildModalityChip(theme)],
    );
  }

  /// Combined session info card: Duration pill + Rest Time pill.
  ///
  /// Replaces the previous two-card layout (header card + stats card)
  /// per the Phase 2.1 refinement. The page title lives in
  /// [OmniBackHeader]; the date and modality chip live in
  /// [_buildSessionInfoHeader] above this card. The card body is
  /// content-only.
  Widget _buildSessionInfoCard(ThemeData theme) {
    return OmniSurface(
      key: const Key('omni_session_info_card'),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: _StatPill(
              label: 'Duration',
              value: _formatDuration(_summary.totalDurationMs),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _StatPill(
              label: 'Rest Time',
              value: _formatDurationOrZero(_restTimeMs),
            ),
          ),
        ],
      ),
    );
  }

  /// Small modality pill rendered in the top-right of the first card's
  /// [OmniCardHeader] actions slot (per the Phase 2.2 refinement —
  /// the chip belongs to the first card, not the page-level header).
  Widget _buildModalityChip(ThemeData theme) {
    final session = widget.workoutState.currentSession;
    final modalityLabel = ModalityDisplay.getName(session?.modality);
    return Container(
      key: const Key('omni_session_summary_modality_chip'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        modalityLabel,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  /// Calendar card header: month label on the left, "Open Calendar"
  /// button on the right. Lives above the calendar [OmniSurface].
  Widget _buildCalendarHeader(ThemeData theme) {
    final now = DateTime.now();
    final monthLabel = '${_monthName(now.month)} ${now.year}';
    return OmniCardHeader(
      title: monthLabel,
      actions: [_buildOpenCalendarButton()],
    );
  }

  /// Compact `Open Calendar` button used in the calendar card's
  /// [OmniCardHeader] actions slot. Extracted so the body composition
  /// site stays compact and so the button lives outside the card
  /// (D-2: controls pertinent to a card live in its header).
  Widget _buildOpenCalendarButton() {
    return FilledButton.tonalIcon(
      onPressed: _openCalendarScreen,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(OmniTheme.buttonUtilityRadius),
          ),
        ),
      ),
      icon: const Icon(Icons.open_in_new, size: 16),
      label: const Text('Open Calendar'),
    );
  }

  List<Widget> _buildGroupCards(ThemeData theme) {
    if (_groupMetrics.isEmpty) {
      return const [];
    }

    final widgets = <Widget>[const SizedBox(height: 16)];
    for (final key in _groupOrder) {
      final metrics = _groupMetrics[key];
      if (metrics == null) continue;
      widgets.add(_buildGroupCard(theme, key, metrics, _groupDeltas[key]));
      widgets.add(const SizedBox(height: 16));
    }
    return widgets;
  }

  Widget _buildGroupCard(
    ThemeData theme,
    String groupKey,
    SessionGroupMetrics metrics,
    GroupDelta? delta,
  ) {
    final label = _groupLabels[groupKey] ?? groupKey;
    final labelColor = ModalityColors.forSummaryGroupLabel(groupKey);

    final primaryLabel = metrics.primaryLabel;
    final primaryValue = metrics.primaryCount.toString();

    String secondaryLabel;
    String secondaryValue;

    if (groupKey == 'strength') {
      secondaryLabel = 'Total Volume';
      secondaryValue = _formatWeight(metrics.totalVolumeKg);
    } else {
      secondaryLabel = 'Total Time';
      secondaryValue = _formatDurationOrZero(metrics.effortDurationMs);
    }

    final prs = _prsByGroup[groupKey] ?? const <PRAchievement>[];

    return OmniSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: labelColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _buildGroupComparisonChip(theme, delta),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatPill(label: primaryLabel, value: primaryValue),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _StatPill(label: secondaryLabel, value: secondaryValue),
              ),
            ],
          ),
          if (prs.isNotEmpty) ...[
            const SizedBox(height: 12),
            Divider(color: Colors.white.withOpacity(0.06), height: 1),
            const SizedBox(height: 10),
            for (final pr in prs)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${pr.exerciseName}: New best ${_formatWeight(pr.newBest)} (was ${_formatWeight(pr.previousBest)})',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildGroupComparisonChip(ThemeData theme, GroupDelta? delta) {
    final dimColor = theme.colorScheme.onSurface.withOpacity(0.65);
    final dimStyle = theme.textTheme.labelSmall?.copyWith(
      color: dimColor,
      fontWeight: FontWeight.w600,
    );

    if (delta == null || !delta.hasPrevious || delta.delta == null) {
      return SizedBox(
        width: 92,
        child: Text('—', textAlign: TextAlign.right, style: dimStyle),
      );
    }

    final d = delta.delta!;
    if (d == 0) {
      return SizedBox(
        width: 92,
        child: Text('—', textAlign: TextAlign.right, style: dimStyle),
      );
    }

    final isPositive = d > 0;
    final arrow = isPositive ? '↑' : '↓';
    final sign = isPositive ? '+' : '-';
    final arrowColor = isPositive
        ? theme.colorScheme.primary
        : theme.colorScheme.error.withOpacity(0.8);

    final String formattedValue;
    switch (delta.unit) {
      case 'kg':
        final converted = _convertKgToPreferred(d.abs());
        formattedValue = '${_formatNumber(converted)} $_preferredWeightUnit';
        break;
      case 'ms':
        formattedValue = _formatDurationDelta(d.abs().toInt());
        break;
      case 'rounds':
        final count = d.abs().toInt();
        formattedValue = '$count round${count != 1 ? 's' : ''}';
        break;
      default:
        formattedValue = _formatNumber(d.abs());
    }

    return SizedBox(
      width: 92,
      child: Text(
        '$arrow $sign$formattedValue',
        textAlign: TextAlign.right,
        style: theme.textTheme.labelSmall?.copyWith(
          color: arrowColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _formatDurationDelta(int ms) {
    if (ms >= 60000) {
      final minutes = (ms / 60000).round();
      return '$minutes min';
    }
    return '${(ms / 1000).round()}s';
  }

  Widget _buildNoteCard(ThemeData theme) {
    // Title is rendered by the `OmniCardHeader` above this card (see
    // the body composition site). The card body is content-only.
    return OmniSurface(
      padding: const EdgeInsets.all(16),
      child: TextField(
        textCapitalization: TextCapitalization.sentences,
        controller: _noteController,
        onChanged: _handleNoteChanged,
        maxLines: 3,
        decoration: const InputDecoration(
          hintText: 'Leave a note about today\'s session',
          border: OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _buildCalendarCard(ThemeData theme) {
    // Month label + "Open Calendar" button live in the
    // `OmniCardHeader` above this card (see `_buildCalendarHeader`
    // and the body composition site). The card body is content-only.
    final now = DateTime.now();
    final workoutDays = _workoutDays.length;
    final restDays = (_daysInMonth - workoutDays).clamp(0, _daysInMonth);

    return OmniSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCalendarGrid(theme, now),
          const SizedBox(height: 12),
          Text(
            '$workoutDays workout days / $restDays rest days',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarGrid(ThemeData theme, DateTime now) {
    final startOfWeek = widget.settingsState.startOfWeek;
    final firstDay = DateTime(now.year, now.month, 1);
    // Dart weekday: 1=Mon … 7=Sun
    final int leadingBlanks = startOfWeek == 'sunday'
        ? firstDay.weekday %
              7 // Sun=0, Mon=1, … Sat=6
        : firstDay.weekday - 1; // Mon=0, Tue=1, … Sun=6
    final daysInMonth = _daysInMonth;
    final totalSlots = daysInMonth + leadingBlanks;
    final rows = (totalSlots / 7).ceil();

    final cells = <Widget>[];
    final today = DateTime.now().day;

    for (int i = 0; i < rows * 7; i++) {
      final dayNumber = i - leadingBlanks + 1;
      if (dayNumber < 1 || dayNumber > daysInMonth) {
        cells.add(const SizedBox.shrink());
        continue;
      }

      final isWorkout = _workoutDays.contains(dayNumber);
      final isToday = dayNumber == today;

      cells.add(
        Container(
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isWorkout
                ? theme.colorScheme.primary.withOpacity(0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isToday
                ? Border.all(color: theme.colorScheme.primary)
                : null,
          ),
          alignment: Alignment.center,
          child: Text(dayNumber.toString(), style: theme.textTheme.bodySmall),
        ),
      );
    }

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: cells,
    );
  }

  String _formatDuration(int durationMs) {
    final totalSeconds = (durationMs / 1000).floor();
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }

  String _formatDurationOrZero(int durationMs) {
    if (durationMs <= 0) {
      return '0';
    }
    return _formatDuration(durationMs);
  }

  double _convertKgToPreferred(double kg) {
    return UnitFormatter.convertWeight(kg, widget.settingsState);
  }

  String _formatWeight(double valueKg) {
    return UnitFormatter.formatWeight(valueKg, widget.settingsState);
  }

  String _formatNumber(double value) {
    if (value.abs() < 1) {
      return value.toStringAsFixed(1);
    }
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(1);
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  String _formatDateTime(DateTime date) {
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final suffix = date.hour >= 12 ? 'PM' : 'AM';
    return '${_formatDate(date)} at $hour:$minute $suffix';
  }

  String _monthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[month - 1];
  }
}

/// Modal bottom sheet content for session feeling rating (1-5).
class _FeelingSheetContent extends StatefulWidget {
  final WorkoutState workoutState;
  final String? modality;

  const _FeelingSheetContent({required this.workoutState, this.modality});

  @override
  State<_FeelingSheetContent> createState() => _FeelingSheetContentState();
}

class _FeelingSheetContentState extends State<_FeelingSheetContent> {
  int? _selectedFeeling;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeColors = OmniTheme.colorsForTheme(OmniTheme.activeTheme);
    final accentColor = ModalityColors.forModality(widget.modality);
    final displayName = ModalityDisplay.getName(widget.modality);
    final subtitle = '$displayName · Today';

    return Container(
      decoration: BoxDecoration(
        color: themeColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        12,
        24,
        MediaQuery.of(context).padding.bottom + 40,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: themeColors.primary.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
              margin: const EdgeInsets.only(bottom: 28),
            ),
          ),
          // Title
          Text(
            'How did it feel?',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.9),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          // Subtitle
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: themeColors.textMuted,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 36),
          // Number tiles row
          Row(
            children: [
              for (int i = 1; i <= 5; i++) ...[
                Expanded(child: _buildFeelingTile(i, accentColor)),
                if (i < 5) const SizedBox(width: 10),
              ],
            ],
          ),
          const SizedBox(height: 10),
          // Range labels row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Rough',
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.0,
                    color: themeColors.textMuted,
                  ),
                ),
                Text(
                  'Great',
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.0,
                    color: themeColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeelingTile(int number, Color accentColor) {
    final theme = Theme.of(context);
    final isSelected = _selectedFeeling == number;
    final tileColor = feelingColor(number, context);

    return GestureDetector(
      onTap: () => _selectFeeling(number),
      child: AspectRatio(
        aspectRatio: 1.0,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: isSelected
                ? tileColor
                : theme.colorScheme.surface.withOpacity(0.6),
            border: Border.all(
              color: isSelected
                  ? tileColor
                  : theme.colorScheme.onSurface.withOpacity(0.12),
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: Text(
              number.toString(),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w500,
                color: isSelected
                    ? Colors.white
                    : theme.colorScheme.onSurface.withOpacity(0.35),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _selectFeeling(int feeling) async {
    setState(() => _selectedFeeling = feeling);

    final session = widget.workoutState.currentSession;
    if (session != null) {
      await widget.workoutState.updateSessionFeeling(session.id, feeling);
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final String value;

  const _StatPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 1.5,
            color: theme.colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }
}
