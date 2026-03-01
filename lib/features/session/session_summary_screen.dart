import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';
import '../../core/constants/modality_display.dart';
import '../../core/services/session_summary_service.dart';
import '../../core/models/session_summary.dart';
import '../../core/constants/modality_config.dart';
import '../../core/constants/effort_defaults.dart';
import '../../state/workout/workout_state.dart';
import '../../state/routine/routine_state.dart';
import '../../widgets/layout/omni_gradient_background.dart';
import '../../widgets/pickers/exercise_picker_dialog.dart';
import '../../widgets/pickers/metric_chooser_dialog.dart';
import '../../data/models/models.dart';
import 'session_overview_screen.dart';

class SessionSummaryScreen extends StatefulWidget {
  final WorkoutState workoutState;
  final RoutineState routineState;
  final SessionSummaryService sessionSummaryService;

  const SessionSummaryScreen({
    super.key,
    required this.workoutState,
    required this.routineState,
    required this.sessionSummaryService,
  });

  @override
  State<SessionSummaryScreen> createState() => _SessionSummaryScreenState();
}

class _SessionSummaryScreenState extends State<SessionSummaryScreen> {
  late SessionSummary _summary;
  late TextEditingController _noteController;
  Timer? _noteDebounce;
  bool _isLoading = true;

  VolumeComparison? _volumeComparison;
  List<PRAchievement> _prs = [];
  Set<int> _workoutDays = {};
  int _daysInMonth = 30;

  List<SessionTemplateExercise> _draftExercises = [];

  // ──── Modality grouping constants (presentation only) ────────────────────

  /// Fixed render order for modality groups on the summary screen.
  static const _groupOrder = ['strength', 'cardio', 'rounds', 'isometric'];

  /// Display labels for each group (per design spec).
  static const _groupLabels = {
    'strength': 'Strength',
    'cardio': 'Cardio',
    'rounds': 'Rounds',
    'isometric': 'Intervals',
  };

  /// Maps effortKind → canonical group key used for grouping/display.
  static String _groupForEffort(String effortKind) {
    switch (effortKind) {
      case 'set':
        return 'strength';
      case 'timed':
        return 'cardio';
      case 'round':
        return 'rounds';
      case 'drill':
        return 'isometric';
      default:
        return 'strength';
    }
  }

  @override
  void initState() {
    super.initState();
    _summary = widget.workoutState.computeSessionSummary();
    _noteController = TextEditingController(
      text: widget.workoutState.currentSession?.note ?? '',
    );
    _draftExercises = widget.workoutState.buildTemplateDraftExercises();
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
      final comparison = await widget.sessionSummaryService
          .compareToPreviousSession(currentSession, _summary.totalVolume);
      final prs = await widget.sessionSummaryService.computePRs(
        _summary.exercises,
      );
      await _loadCalendarData();

      if (!mounted) return;

      setState(() {
        _volumeComparison = comparison;
        _prs = prs;
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
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
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
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SessionOverviewScreen(
          workoutState: widget.workoutState,
          routineState: widget.routineState,
          sessionSummaryService: widget.sessionSummaryService,
        ),
      ),
    );

    if (mounted) {
      await _refreshSummary();
    }
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
              final selectedExercise = await showDialog<Exercise>(
                context: context,
                builder: (context) => ExercisePickerDialog(
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
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              top: BorderSide(color: Colors.white.withOpacity(0.06)),
            ),
          ),
          child: SizedBox(
            width: double.infinity,
            height: OmniTheme.buttonPrimaryHeight,
            child: FilledButton(
              onPressed: _finishAndSaveSession,
              style: ButtonStyle(
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      OmniTheme.buttonBorderRadius,
                    ),
                  ),
                ),
              ),
              child: const Text('Done'),
            ),
          ),
        ),
      ),
      body: OmniGradientBackground(
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: theme.colorScheme.surface.withOpacity(0.9),
                elevation: 0,
                title: Text(title),
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
                      PopupMenuItem(
                        value: 'save',
                        child: Text('Save as Routine'),
                      ),
                      PopupMenuItem(value: 'discard', child: Text('Discard')),
                    ],
                  ),
                ],
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _buildHeaderCard(theme),
                    const SizedBox(height: 16),
                    _buildStatsCard(theme),
                    const SizedBox(height: 16),
                    _buildExerciseListSection(theme),
                    const SizedBox(height: 16),
                    _buildVolumeComparison(theme),
                    if (_prs.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildPrsCard(theme),
                    ],
                    const SizedBox(height: 16),
                    _buildNoteCard(theme),
                    const SizedBox(height: 16),
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
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(ThemeData theme) {
    final session = widget.workoutState.currentSession;
    final startedAt = session != null
        ? DateTime.fromMillisecondsSinceEpoch(session.startedAtMs)
        : DateTime.now();
    final modalityLabel = ModalityDisplay.getName(session?.modality);
    final title = session?.title ?? modalityLabel;

    return _SummaryCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 0.4),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                _formatDateTime(startedAt),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
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
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCard(ThemeData theme) {
    final pills = <Widget>[
      _StatPill(
        label: 'Duration',
        value: _formatDuration(_summary.totalDurationMs),
      ),
      _StatPill(
        label: 'Exercises',
        value: _summary.exercises.length.toString(),
      ),
    ];

    if (_summary.totalSets > 0) {
      pills.add(_StatPill(label: 'Sets', value: _summary.totalSets.toString()));
    }
    if (_summary.totalRounds > 0) {
      pills.add(
        _StatPill(label: 'Rounds', value: _summary.totalRounds.toString()),
      );
    }
    if (_summary.totalCardioDurationMs > 0) {
      pills.add(
        _StatPill(
          label: 'Cardio',
          value: _formatDuration(_summary.totalCardioDurationMs),
        ),
      );
    }

    return _SummaryCard(
      child: Wrap(spacing: 24, runSpacing: 12, children: pills),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Exercise list section
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildExerciseListSection(ThemeData theme) {
    final exercises = _summary.exercises;
    if (exercises.isEmpty) return const SizedBox.shrink();

    // Bucket exercises into groups, preserving arrival order within each.
    final Map<String, List<ExerciseSummary>> groups = {};
    for (final ex in exercises) {
      final key = _groupForEffort(ex.effortKind);
      groups.putIfAbsent(key, () => []).add(ex);
    }

    // Sort within each group by execution order (defensive; should already be ordered).
    for (final list in groups.values) {
      list.sort((a, b) => a.executionOrder.compareTo(b.executionOrder));
    }

    final isMultiModality = groups.length > 1;
    final orderedGroupKeys = _groupOrder.where(groups.containsKey).toList();

    final items = <Widget>[];

    if (isMultiModality) {
      for (int g = 0; g < orderedGroupKeys.length; g++) {
        final key = orderedGroupKeys[g];
        final groupExercises = groups[key]!;

        items.add(_buildExerciseGroupHeader(theme, key, groupExercises));
        items.add(const SizedBox(height: 8));

        for (int i = 0; i < groupExercises.length; i++) {
          items.add(_buildExerciseTile(theme, groupExercises[i]));
          if (i < groupExercises.length - 1) {
            items.add(const SizedBox(height: 6));
          }
        }

        if (g < orderedGroupKeys.length - 1) {
          items.add(const SizedBox(height: 16));
          items.add(Divider(color: Colors.white.withOpacity(0.06), height: 1));
          items.add(const SizedBox(height: 16));
        }
      }
    } else {
      // Single modality — flat list, no headers.
      for (int i = 0; i < exercises.length; i++) {
        items.add(_buildExerciseTile(theme, exercises[i]));
        if (i < exercises.length - 1) {
          items.add(const SizedBox(height: 6));
        }
      }
    }

    return _SummaryCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Exercises', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          ...items,
        ],
      ),
    );
  }

  Widget _buildExerciseGroupHeader(
    ThemeData theme,
    String groupKey,
    List<ExerciseSummary> exercises,
  ) {
    final label = _groupLabels[groupKey] ?? groupKey;
    String aggregate = '';

    switch (groupKey) {
      case 'strength':
        final totalSets = exercises.fold(0, (s, e) => s + e.setsCompleted);
        aggregate = '$totalSets set${totalSets != 1 ? 's' : ''}';
        break;
      case 'cardio':
        final totalMs = exercises.fold<int>(
          0,
          (s, e) => s + (e.totalDurationMs ?? 0),
        );
        aggregate = _formatDuration(totalMs);
        break;
      case 'rounds':
        final totalRounds = exercises.fold(0, (s, e) => s + e.totalRounds);
        aggregate = '$totalRounds round${totalRounds != 1 ? 's' : ''}';
        break;
      case 'isometric':
        final totalMs = exercises.fold<int>(
          0,
          (s, e) => s + (e.totalDurationMs ?? 0),
        );
        aggregate = _formatDuration(totalMs);
        break;
    }

    return Row(
      children: [
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 1.5,
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (aggregate.isNotEmpty) ...[
          const SizedBox(width: 8),
          Text(
            '· $aggregate',
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 0.5,
              color: theme.colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildExerciseTile(ThemeData theme, ExerciseSummary exercise) {
    final String subtitle;
    switch (exercise.effortKind) {
      case 'set':
        final sets =
            '${exercise.setsCompleted} set${exercise.setsCompleted != 1 ? 's' : ''}';
        if (exercise.bestWeight != null && exercise.bestWeight! > 0) {
          subtitle = '$sets · Best ${_formatNumber(exercise.bestWeight!)} kg';
        } else {
          subtitle = sets;
        }
        break;
      case 'timed':
        final ms = exercise.totalDurationMs ?? 0;
        subtitle = ms > 0 ? _formatDuration(ms) : '—';
        break;
      case 'round':
        final r = exercise.totalRounds;
        subtitle = '$r round${r != 1 ? 's' : ''}';
        break;
      case 'drill':
        final ms = exercise.totalDurationMs ?? 0;
        subtitle = ms > 0 ? _formatDuration(ms) : '—';
        break;
      default:
        subtitle = '${exercise.setsCompleted} entries';
    }

    return Row(
      children: [
        Expanded(
          child: Text(
            exercise.name,
            style: theme.textTheme.bodyMedium,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildVolumeComparison(ThemeData theme) {
    final comparison = _volumeComparison;
    String text;
    Color color = theme.colorScheme.onSurface;

    if (comparison == null || !comparison.hasPrevious) {
      text = 'First session recorded';
    } else {
      final delta = comparison.delta ?? 0;
      final sign = delta >= 0 ? '+' : '';
      text = '$sign${_formatNumber(delta)} kg volume vs last time';
      color = delta >= 0 ? theme.colorScheme.primary : theme.colorScheme.error;
    }

    return _SummaryCard(
      child: Row(
        children: [
          Icon(Icons.trending_up, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrsCard(ThemeData theme) {
    return _SummaryCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.emoji_events, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('PRs achieved', style: theme.textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 12),
          for (final pr in _prs)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text(
                '${pr.exerciseName}: New best ${_formatNumber(pr.newBest)} kg '
                '(was ${_formatNumber(pr.previousBest)} kg)',
                style: theme.textTheme.bodyMedium,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNoteCard(ThemeData theme) {
    return _SummaryCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Session note', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _noteController,
            onChanged: _handleNoteChanged,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Leave a note about today\'s session',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarCard(ThemeData theme) {
    final now = DateTime.now();
    final monthLabel = '${_monthName(now.month)} ${now.year}';
    final workoutDays = _workoutDays.length;
    final restDays = (_daysInMonth - workoutDays).clamp(0, _daysInMonth);

    return _SummaryCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(monthLabel, style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
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
    final firstDay = DateTime(now.year, now.month, 1);
    final firstWeekday = firstDay.weekday; // 1=Mon
    final daysInMonth = _daysInMonth;
    final totalSlots = daysInMonth + (firstWeekday - 1);
    final rows = (totalSlots / 7).ceil();

    final cells = <Widget>[];
    final today = DateTime.now().day;

    for (int i = 0; i < rows * 7; i++) {
      final dayNumber = i - (firstWeekday - 2);
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

class _SummaryCard extends StatelessWidget {
  final Widget child;

  const _SummaryCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
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
