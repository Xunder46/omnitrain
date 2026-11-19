import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../core/constants/modality_display.dart';
import '../../core/constants/modality_colors.dart';
import '../../core/services/session_summary_service.dart';
import '../../core/models/session_summary.dart';
import '../../core/constants/modality_config.dart';
import '../../core/constants/effort_defaults.dart';
import '../../core/services/routine_session_service.dart';
import '../../core/utils/session_feeling_utils.dart';
import '../../core/utils/unit_formatter.dart';
import '../../core/utils/summary_exercise_rows.dart';
import '../../core/utils/distance_source.dart';
import '../../state/settings/settings_state.dart';
import '../../state/workout/workout_state.dart';
import '../../state/routine/routine_state.dart';
import '../../state/calendar/calendar_state.dart';
import '../../state/period/period_state.dart';
import '../../widgets/buttons/omni_utility_button.dart';
import '../../widgets/layout/omni_bottom_cta.dart';
import '../../widgets/layout/omni_back_header.dart';
import '../../widgets/layout/omni_card_header.dart';
import '../../widgets/layout/omni_surface.dart';
import '../../widgets/session/effort_rating_sheet.dart';
import '../../widgets/session/metric_crown_widget.dart';
import '../../widgets/session/session_distance_card.dart';
import '../exercise/exercise_picker_screen.dart';
import '../../widgets/pickers/metric_chooser_dialog.dart';
import '../../data/models/models.dart';
import '../../core/utils/timer_alert_service.dart';
import '../../core/utils/rest_notification_service.dart';
import '../calendar/calendar_screen.dart';
import 'workout_session_screen.dart';
import '../../core/navigation/navigation.dart';
import '../../widgets/dialogs/confirmation_dialog.dart';
import '../../widgets/feedback/omni_message.dart';

class SessionSummaryScreen extends StatefulWidget {
  final WorkoutState workoutState;
  final RoutineState routineState;
  final SessionSummaryService sessionSummaryService;
  final Future<void> Function(String sessionId)? onSessionSaved;
  final SettingsState settingsState;
  final TimerAlertService timerAlertService;
  final RestNotificationService restNotificationService;

  /// True when this summary was reached from the calendar / day-list
  /// flow (i.e. viewing a historical session). Drives:
  ///   • "Open Calendar" to pop back (one route) instead of pushing a
  ///     fresh `CalendarScreen`.
  ///   • "Discard" to pop back to the originating calendar or day
  ///     list (after deleting the session) instead of `popUntil(isFirst)`.
  ///
  /// `false` (default) preserves the post-workout flow: the summary
  /// was reached via `pushReplacement` from `WorkoutSessionScreen`,
  /// and Discard / Open Calendar behave as before.
  final bool openedFromCalendar;

  /// The `CalendarState` that originated this summary. Required when
  /// [openedFromCalendar] is true so Discard can refresh the calendar
  /// after deleting the session.
  final CalendarState? originatingCalendarState;

  SessionSummaryScreen({
    super.key,
    required this.workoutState,
    required this.routineState,
    required this.sessionSummaryService,
    this.onSessionSaved,
    required this.settingsState,
    required this.timerAlertService,
    RestNotificationService? restNotificationService,
    this.openedFromCalendar = false,
    this.originatingCalendarState,
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

  /// True only while the automatic post-workout question is on screen
  /// (plan 42a D-3). The user's own answer clears it first, so only a rating
  /// that arrived from outside (the watch) closes the sheet.
  bool _autoFeelingSheetOpen = false;

  Map<String, GroupDelta> _groupDeltas = {};
  ComparisonBasis? _comparisonBasis;
  Map<String, List<PRAchievement>> _prsByGroup = {};
  Map<String, SessionGroupMetrics> _groupMetrics = {};
  int _restTimeMs = 0;
  ({int avgBpm, int maxBpm})? _heartRate;

  /// The active-energy row for the loaded session, if one is stored.
  ({int kcal, bool measured})? _energy;
  String _preferredWeightUnit = 'kg';
  late final CalendarState _calendarState;
  late final PeriodState _periodState;
  late final RoutineSessionService _routineSessionService;

  /// True when the summary was reached from the calendar flow (so
  /// Discard / Open Calendar should navigate back, not exit to the hub).
  bool get _isHistoricalView => widget.openedFromCalendar;

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
    _notifySessionSaved();
    widget.workoutState.wristSummary.addListener(_reloadHeartRateOnWristSummary);
    _loadAsyncData();
  }

  @override
  void dispose() {
    widget.workoutState.removeListener(_closeAutoSheetOnOutsideRating);
    widget.workoutState.wristSummary.removeListener(_reloadHeartRateOnWristSummary);
    final pending = _noteDebounce;
    if (pending != null && pending.isActive) {
      pending.cancel();
      unawaited(
        widget.workoutState.updateSessionNote(_noteController.text.trim()),
      );
    }
    _noteController.dispose();
    super.dispose();
  }

  /// The workout is already stored when the summary opens (Finish ends it
  /// first), so the saved-session hook — which links a planned session — runs
  /// here and not on "Done": Back must not leave the plan uncompleted.
  void _notifySessionSaved() {
    if (_isHistoricalView) return;
    final sessionId = widget.workoutState.currentSession?.id;
    final onSaved = widget.onSessionSaved;
    if (sessionId == null || onSaved == null) return;
    onSaved(sessionId);
  }

  Future<void> _loadAsyncData() async {
    setState(() => _isLoading = true);

    final currentSession = widget.workoutState.currentSession;
    if (currentSession != null) {
      final comparison = await widget.sessionSummaryService
          .compareGroupsToPreviousSession(currentSession, _summary);
      // Exclude the current session so the just-finished workout's
      // own PRs are not compared against themselves (D-3 in
      // docs/plans/summary-pr-parity-plan.md). The same
      // e1RM formula is used by the in-workout toast and the Stats
      // screen — single source of truth
      // (StatsProgressService.epley1RM).
      final prs = await widget.sessionSummaryService.computePRs(
        _summary.exercises,
        currentSessionId: currentSession.id,
      );
      final groupedPrs = widget.sessionSummaryService.groupPrsByEffortKind(
        prs,
        _summary.exercises,
      );
      final groupMetrics = await widget.sessionSummaryService.buildGroupMetrics(
        _summary,
        modality: currentSession.modality,
      );
      final restTimeMs = await widget.sessionSummaryService
          .computeSessionRestTimeMs(currentSession.id);
      final heartRate = await widget.sessionSummaryService.getSessionHeartRate(
        currentSession.id,
      );
      final energy = await widget.sessionSummaryService.getSessionEnergy(
        currentSession.id,
      );
      final preferredWeightUnit = await widget.sessionSummaryService
          .getPreferredWeightUnit();

      if (!mounted) return;

      setState(() {
        _groupDeltas = comparison.deltas;
        _comparisonBasis = comparison.basis;
        _prsByGroup = groupedPrs;
        _groupMetrics = groupMetrics;
        _restTimeMs = restTimeMs;
        _heartRate = heartRate;
        _energy = energy;
        _preferredWeightUnit = preferredWeightUnit;
        _isLoading = false;
      });
    }
  }

  /// The wrist's heart-rate summary landed after this screen opened (plan 72):
  /// re-read the heart rate and the energy alone, so nothing else on the
  /// screen reloads.
  Future<void> _reloadHeartRateOnWristSummary() async {
    final arrived = widget.workoutState.wristSummary.value;
    final session = widget.workoutState.currentSession;
    if (arrived == null || session == null || arrived.sessionId != session.id) {
      return;
    }
    final heartRate = await widget.sessionSummaryService.getSessionHeartRate(
      session.id,
    );
    final energy = await widget.sessionSummaryService.getSessionEnergy(
      session.id,
    );
    if (!mounted) return;
    setState(() {
      _heartRate = heartRate;
      _energy = energy;
    });
  }

  /// Plan 238: a note still waiting in the 600 ms pause is written now, so a
  /// Done or Back inside that pause does not lose it.
  Future<void> _flushNote() async {
    final pending = _noteDebounce;
    if (pending == null || !pending.isActive) return;
    pending.cancel();
    await widget.workoutState.updateSessionNote(_noteController.text.trim());
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

    // Only show automatic prompt for fresh sessions, not historical ones
    if (_isHistoricalView) return;

    final session = widget.workoutState.currentSession;
    if (session == null) return;
    if (session.sessionFeeling != null) return;

    _hasShownFeelingSheet = true;
    _autoFeelingSheetOpen = true;
    widget.workoutState.addListener(_closeAutoSheetOnOutsideRating);

    try {
      await EffortRatingSheet.show(
        context,
        mustAnswer: true,
        modality: session.modality,
        startedAt: OmniDateUtils.fromMs(session.startedAtMs),
        onRated: _saveAutomaticRating,
      );
    } finally {
      _autoFeelingSheetOpen = false;
      widget.workoutState.removeListener(_closeAutoSheetOnOutsideRating);
    }

    // Rebuild to reflect any rating changes made in the automatic prompt
    if (mounted) {
      setState(() {});
    }
  }

  /// Closes the automatic question when the live session got a rating from
  /// outside this sheet (the watch answered first, D-3). The pop is guarded:
  /// it only runs while a route sits on top of this screen, so it can never
  /// pop the Summary itself.
  void _closeAutoSheetOnOutsideRating() {
    if (!_autoFeelingSheetOpen || !mounted) return;
    if (widget.workoutState.currentSession?.sessionFeeling == null) return;
    final route = ModalRoute.of(context);
    if (route == null || route.isCurrent) return;
    // Cleared before the pop so a second notification during the sheet's
    // exit animation cannot pop the Summary behind it.
    _autoFeelingSheetOpen = false;
    Navigator.of(context).pop();
  }

  /// Where the AUTOMATIC question's answer goes: first answer wins, so a
  /// rating already stored (the watch's) is left alone. The Add/Change control
  /// keeps [_saveEffortRating], which is an explicit edit.
  Future<bool> _saveAutomaticRating(int rating) async {
    final session = widget.workoutState.currentSession;
    if (session == null) return false;
    _autoFeelingSheetOpen = false;
    await widget.workoutState.updateSessionFeeling(
      session.id,
      rating,
      onlyIfUnrated: true,
    );
    return true;
  }

  /// Open the effort-rating sheet from the Summary's add/change control.
  /// Unlike the post-workout prompt (isDismissible: false), this sheet
  /// CAN be dismissed without selecting a value — tapping outside or
  /// swiping down cancels without changing the rating.
  Future<void> _openEffortRatingSheet() async {
    final session = widget.workoutState.currentSession;
    if (session == null) return;

    final saved = await EffortRatingSheet.show(
      context,
      mustAnswer: false,
      modality: session.modality,
      startedAt: OmniDateUtils.fromMs(session.startedAtMs),
      initialRating: session.sessionFeeling,
      onRated: _saveEffortRating,
    );

    // A calendar-opened summary returns to a day list / grid that drew
    // the old rating; refresh it the same way Discard does.
    if (saved != null && _isHistoricalView) {
      await _refreshOriginatingCalendar();
    }

    // Rebuild to reflect any rating changes made in the sheet
    if (mounted) {
      setState(() {});
    }
  }

  /// Where either rating sheet's answer goes: the summary's session, through
  /// [WorkoutState.updateSessionFeeling]. Answers false — and the sheet stays
  /// open — only when no session is loaded to rate.
  Future<bool> _saveEffortRating(int rating) async {
    final session = widget.workoutState.currentSession;
    if (session == null) return false;
    await widget.workoutState.updateSessionFeeling(session.id, rating);
    return true;
  }

  /// Reload the calendar this summary was opened from so it reflects a
  /// change made here (a discarded session, a new effort rating).
  Future<void> _refreshOriginatingCalendar() async {
    try {
      await (widget.originatingCalendarState ?? _calendarState).refresh();
    } catch (_) {
      // Calendar refresh is best-effort; a failure here shouldn't block
      // the user.
    }
  }

  Future<void> _showDiscardDialog() async {
    final confirmed = await ConfirmationDialog.showTwoChoice(
      context: context,
      title: 'Discard session?',
      body: Text(
        _isHistoricalView
            ? 'This will permanently delete this session from your history '
                  'and return to the previous screen.'
            : 'This will remove all session data and return to Home.',
      ),
      dismissLabel: 'Cancel',
      confirmLabel: 'Discard',
      dismissKey: const Key('session-summary-discard-cancel'),
      confirmKey: const Key('session-summary-discard-confirm'),
      isDestructive: true,
    );

    if (confirmed && mounted) {
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

    Navigator.pop(context); // close the loading spinner

    if (_isHistoricalView) {
      // Refresh the originating calendar so the deleted session
      // disappears from the grid, then pop back to where the user
      // came from (calendar or day list).
      await _refreshOriginatingCalendar();
      if (!mounted) return;
      Navigator.pop(context);
    } else {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _finishAndSaveSession() async {
    // Plan 238: write a note still in its 600 ms pause before the session ends.
    await _flushNote();
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    if (!_isHistoricalView) {
      await widget.workoutState.endSession();
    }
    widget.workoutState.clearSession();

    if (!mounted) return;

    Navigator.pop(context); // close the loading spinner

    if (_isHistoricalView) {
      // The session is already in the repository — there's nothing to
      // save. Pop back to the originating calendar or day list.
      Navigator.pop(context);
      return;
    }

    Navigator.of(context).popUntil((route) => route.isFirst);
    OmniMessage.show(
      context,
      'Workout session saved successfully',
      duration: const Duration(seconds: 2),
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
    if (_isHistoricalView) {
      // Reached via the calendar flow → behave like the system back
      // button. Popping returns the user to the originating calendar
      // or day list instead of stacking a fresh `CalendarScreen` on
      // top of the summary.
      Navigator.pop(context);
      return;
    }
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
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.06),
                  ),
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
                              tooltip: 'Remove exercise',
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
                        child: const Text('Save'),
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
              PopupMenuItem(value: 'edit', child: Text('Edit Session')),
              PopupMenuItem(value: 'save', child: Text('Save as Routine')),
              PopupMenuItem(value: 'discard', child: Text('Discard')),
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
                      // The date header (with the modality chip) and
                      // the session info card are always rendered; for
                      // a rolling session the card carries only the
                      // EFFORT row (no Duration/Rest Time row).
                      _buildSessionInfoHeader(theme),
                      _buildSessionInfoCard(theme),
                      ..._buildGroupCards(theme),
                      ..._buildExerciseSection(theme),
                      ..._buildDistanceSection(),
                      const SizedBox(height: 16),
                      const OmniCardHeader(title: 'SESSION NOTE'),
                      _buildNoteCard(theme),
                      const SizedBox(height: 16),
                      Center(child: _buildOpenCalendarButton()),
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

  /// Combined session info card: Duration pill + Rest Time pill + Effort pill.
  ///
  /// Replaces the previous two-card layout (header card + stats card)
  /// per the Phase 2.1 refinement. The page title lives in
  /// [OmniBackHeader]; the date and modality chip live in
  /// [_buildSessionInfoHeader] above this card. The card body is
  /// content-only. The EFFORT row is always shown (even if toggle is off),
  /// as two halves: the rating pill carries a pen (icon-only) button whose
  /// tooltip reads "Add rating" or "Change rating", and the right half is a
  /// CALORIES pill. The rating pill's own caption explains what the value
  /// means. The value
  /// text uses the pills' shared value color; the rating's intensity is a
  /// non-text marker in its ramp step, because low ramp steps are below the
  /// text contrast floor (D-15 in the Stats PR 1 plan).
  ///
  /// For rolling sessions, Duration/Rest Time are hidden, but the EFFORT row
  /// remains visible so the user can rate the session.
  Widget _buildSessionInfoCard(ThemeData theme) {
    final session = widget.workoutState.currentSession;
    final feeling = session?.sessionFeeling;
    final themeColors = OmniTheme.colorsForTheme(OmniTheme.activeTheme);
    final isRolling = widget.workoutState.isRollingSession;

    return OmniSurface(
      key: const Key('omni_session_info_card'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // First row: Duration | Rest Time (hidden for rolling sessions)
          if (!isRolling) ...[
            Row(
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
            // Gap between rows (only when Duration row is visible)
            const SizedBox(height: 16),
          ],
          // Heart-rate row: only when the watch recorded a session heart
          // rate (D-3, plan 66b). Sits between the Duration/Rest row and the
          // Effort row.
          if (_heartRate case final heartRate?) ...[
            Row(
              key: const Key('omni_session_heart_rate_row'),
              children: [
                Expanded(
                  child: _StatPill(
                    label: 'Avg heart rate',
                    value: '${heartRate.avgBpm} bpm',
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _StatPill(
                    label: 'Max heart rate',
                    value: '${heartRate.maxBpm} bpm',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          // Effort + calories row: always visible (even for rolling
          // sessions). LEFT half: the rating pill with its outlined pen
          // button right beside the value; RIGHT half: the Calories pill.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _StatPill(
                  label: 'Effort',
                  value: feeling != null ? '$feeling / 5' : '—',
                  caption: 'How hard the session felt',
                  captionKey: const Key('omni_session_effort_caption'),
                  leading: feeling != null
                      ? Container(
                          key: const Key('omni_session_effort_marker'),
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: feelingColor(feeling, themeColors),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        )
                      : null,
                  trailing: OmniUtilityIconButton(
                    buttonKey: const Key('omni_session_effort_rating_button'),
                    tooltip: feeling != null ? 'Change rating' : 'Add rating',
                    icon: feeling != null ? Icons.edit_outlined : Icons.add,
                    onPressed: _openEffortRatingSheet,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: KeyedSubtree(
                  key: const Key('omni_session_calories_pill'),
                  child: _StatPill(label: 'Calories', value: _energyLabel()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The label of the CALORIES pill: a measured row reads plain, an
  /// estimated row carries a `~`, and no stored row reads `—`.
  String _energyLabel() {
    final e = _energy;
    if (e == null) return '—';
    return e.measured ? '${e.kcal} kcal' : '~${e.kcal} kcal';
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

  /// Compact `Open Calendar` button on its own centred row directly
  /// under the SESSION NOTE card, no longer inside a card header.
  /// Extracted so the body composition site stays compact.
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

  // ── EXERCISES section (plan 245) ─────────────────────────────────────────

  /// The EXERCISES header and card, or nothing at all when no exercise has
  /// logged work. One row per exercise in the session's order: its name and,
  /// under it, each set / hold / round that was logged.
  List<Widget> _buildExerciseSection(ThemeData theme) {
    final rows = buildSummaryExerciseRows(
      widget.workoutState.getExercisesWithEntries(),
      weightUnitLabel: UnitFormatter.weightLabel(widget.settingsState),
      formatWeight: (kg) =>
          UnitFormatter.formatWeightValue(kg, widget.settingsState),
    );
    if (rows.isEmpty) return const [];

    final themeColors = OmniTheme.colorsForTheme(OmniTheme.activeTheme);
    return [
      const SizedBox(height: 16),
      const OmniCardHeader(title: 'EXERCISES'),
      OmniSurface(
        key: const Key('omni_session_exercise_card'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(color: themeColors.surfaceBorder, height: 1),
              Padding(
                key: Key('summary_exercise_row_$i'),
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(rows[i].name, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        for (final item in rows[i].items)
                          Text(
                            item,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    ];
  }

  // ── DISTANCE section (D-315, D-319) ──────────────────────────────────────

  /// The DISTANCE header and card, or nothing at all when no entry has a row:
  /// a session that tracked nothing through Cardio and holds no stored
  /// distance shows no section.
  List<Widget> _buildDistanceSection() {
    final rows = _buildDistanceRows();
    if (rows.isEmpty) return const [];

    return [
      const SizedBox(height: 16),
      const OmniCardHeader(title: 'DISTANCE'),
      SessionDistanceCard(rows: rows),
    ];
  }

  /// One row per entry a distance belongs to, in the Summary's effort order
  /// and then entry order (D-315).
  ///
  /// The entries come from the same list every distance write addresses
  /// (D-328), so the row on screen and the row an edit lands on are the same
  /// entry. A non-Cardio effort shows only the entries that hold a distance:
  /// on those the rows themselves are the entries.
  List<DistanceRowModel> _buildDistanceRows() {
    final unit = widget.settingsState.preferredDistanceUnit;
    final metresPerUnit = UnitFormatter.metresPerUnit(unit);
    final unitLabel = UnitFormatter.distanceLabelForUnit(unit);
    final rows = <DistanceRowModel>[];

    for (final exercise in widget.workoutState.getExercisesWithEntries()) {
      final effortId = exercise['id'] as String;
      final trackedThroughCardio = exercise['effortKind'] == 'timed';
      final exerciseName = exercise['name'] as String;
      final entries = widget.workoutState.getEffortDistanceEntries(effortId);

      for (final entry in entries) {
        final metres = entry.metres;
        // A Cardio-tracked entry keeps its row whether or not a distance was
        // recorded; any other kind appears only when it holds one.
        if (!trackedThroughCardio && metres <= 0) continue;

        final estimated = DistanceSource.isEstimated(entry.row?.valueSource);
        rows.add(
          DistanceRowModel(
            name: entries.length > 1
                ? '$exerciseName · ${entry.displayNumber}'
                : exerciseName,
            value: metres > 0
                ? (metres / metresPerUnit).toStringAsFixed(2)
                : SessionDistanceCard.absentValue,
            unitLabel: estimated ? '$unitLabel est.' : unitLabel,
            onTap: () => _editDistance(effortId, entry.entryIndex, metres),
          ),
        );
      }
    }

    return rows;
  }

  /// Opens the distance field for one entry (D-316) and applies the answer.
  Future<void> _editDistance(
    String effortId,
    int entryIndex,
    double currentMetres,
  ) async {
    final unit = widget.settingsState.preferredDistanceUnit;
    final metresPerUnit = UnitFormatter.metresPerUnit(unit);
    final currentUnits = currentMetres / metresPerUnit;

    await showMetricEditPopup(
      context,
      metricType: 'distance',
      currentValue: currentUnits,
      unitLabel: UnitFormatter.distanceLabelUpperForUnit(unit),
      onValueChanged: (value) => _applyDistance(
        effortId: effortId,
        entryIndex: entryIndex,
        prefilledUnits: double.parse(currentUnits.toStringAsFixed(2)),
        enteredUnits: (value as num).toDouble(),
        metresPerUnit: metresPerUnit,
      ),
    );
  }

  /// Records what the dialog answered (D-307).
  ///
  /// The dialog pre-filled the stored value to two decimals, so an answer equal
  /// to that pre-fill is a confirm: it records the stored metres as they are,
  /// which is what confirms an estimate. Anything else stores what was typed,
  /// and zero removes the distance.
  Future<void> _applyDistance({
    required String effortId,
    required int entryIndex,
    required double prefilledUnits,
    required double enteredUnits,
    required double metresPerUnit,
  }) async {
    if (enteredUnits > 0 && enteredUnits == prefilledUnits) {
      await widget.workoutState.confirmEntryDistance(effortId, entryIndex);
    } else {
      await widget.workoutState.setEntryDistance(
        effortId,
        entryIndex,
        enteredUnits * metresPerUnit,
      );
    }

    if (!mounted) return;
    setState(() {});
  }

  /// The one line that says what the group figures were compared with, or null
  /// when no figure is shown (plan 246).
  Widget? _buildComparisonBasisLine(ThemeData theme) {
    final basis = _comparisonBasis;
    if (basis == null) return null;
    final anyFigure = _groupDeltas.values.any((d) => d.delta != null);
    if (!anyFigure) return null;
    final date = _formatDate(
      DateTime.fromMillisecondsSinceEpoch(basis.previousStartedAtMs),
    );
    final what = basis.isRoutine ? basis.label : '${basis.label} session';
    return Text(
      'Compared with your last $what ($date)',
      key: const Key('summary_comparison_basis'),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  List<Widget> _buildGroupCards(ThemeData theme) {
    if (_groupMetrics.isEmpty) {
      return const [];
    }

    final widgets = <Widget>[const SizedBox(height: 16)];
    final basisLine = _buildComparisonBasisLine(theme);
    if (basisLine != null) {
      widgets.add(basisLine);
      widgets.add(const SizedBox(height: 8));
    }
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
            Divider(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
              height: 1,
            ),
            const SizedBox(height: 10),
            for (final pr in prs)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  // Reps-axis (bodyweight) PRs read as
                  // `${pr.exerciseName}: New best ${reps} reps (was ${prev} reps)`.
                  // Weight-axis PRs read as
                  // `${pr.exerciseName}: New best ${weight} (was ${prev})`
                  // — the existing behaviour, preserved verbatim
                  // for loaded exercises. The two branches
                  // share the layout so the list reads identically
                  // regardless of which axis fired.
                  pr.metricLabel == 'reps'
                      ? '${pr.exerciseName}: New best ${pr.newBest.toInt()} reps (was ${pr.previousBest.toInt()} reps)'
                      : '${pr.exerciseName}: New best ${_formatWeight(pr.newBest)} (was ${_formatWeight(pr.previousBest)})',
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
        formattedValue = ModalityDisplay.roundCount(
          widget.workoutState.currentSession?.modality,
          count,
        );
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

  /// Short "Mon D" date (e.g. "Sep 18").
  static String _formatDate(DateTime date) {
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
}

class _StatPill extends StatelessWidget {
  final String label;
  final String value;

  /// Optional non-text mark drawn immediately before [value] (the EFFORT
  /// row's intensity marker).
  final Widget? leading;

  /// Optional control drawn right after [value] on the same line (the EFFORT
  /// row's pen button). It wraps under the value on a very narrow pill.
  final Widget? trailing;

  /// Optional muted line under the value, inside the pill's own column (the
  /// EFFORT row's "How hard the session felt").
  final String? caption;

  /// The key carried by the caption [Text], so a reader can point at just
  /// that line.
  final Key? captionKey;

  const _StatPill({
    required this.label,
    required this.value,
    this.leading,
    this.trailing,
    this.caption,
    this.captionKey,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueText = Text(
      value,
      style: theme.textTheme.titleLarge?.copyWith(
        color: theme.colorScheme.primary,
      ),
    );
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
        if (leading == null && trailing == null)
          valueText
        else
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              ?leading,
              valueText,
              ?trailing,
            ],
          ),
        if (caption != null) ...[
          const SizedBox(height: 4),
          Text(
            caption!,
            key: captionKey,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ],
      ],
    );
  }
}
