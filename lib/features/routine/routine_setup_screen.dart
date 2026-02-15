import 'package:flutter/material.dart';
import '../../widgets/layout/omni_gradient_background.dart';
import '../../widgets/pickers/exercise_picker_dialog.dart';
import '../../widgets/pickers/metric_chooser_dialog.dart';
import '../../core/constants/modality_config.dart';
import '../../core/constants/metric_ids.dart';
import '../../core/constants/omni_theme.dart';
import '../../widgets/session/inline_metric_editor.dart';
import '../../state/routine/routine_state.dart';
import '../../state/workout/workout_state.dart';
import '../../data/models/models.dart';

/// Screen for creating or editing a workout routine (template)
class RoutineSetupScreen extends StatefulWidget {
  final RoutineState routineState;
  final WorkoutState? workoutState; // Optional for loading exercise data
  final String? templateId; // null = create new, non-null = edit existing

  const RoutineSetupScreen({
    super.key,
    required this.routineState,
    this.workoutState,
    this.templateId,
  });

  @override
  State<RoutineSetupScreen> createState() => _RoutineSetupScreenState();
}

class _RoutineSetupScreenState extends State<RoutineSetupScreen> {
  late TextEditingController _nameController;
  bool _isLoading = true;
  Map<String, Exercise> _exerciseCache = {};
  bool _showListView = true;
  int _currentExerciseIndex = 0;
  int _currentSet = 1;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _loadRoutine();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadRoutine() async {
    if (widget.templateId != null) {
      // Load existing routine for editing
      await widget.routineState.loadRoutineForEditing(widget.templateId!);
      _nameController.text = widget.routineState.currentTemplate?.name ?? '';
    } else {
      // Create new routine
      await widget.routineState.createNewRoutine('New Routine');
      _nameController.text = '';
    }

    if (widget.workoutState != null) {
      await widget.workoutState!.loadAllExercises();
      _exerciseCache = {
        for (final exercise in widget.workoutState!.allExercises) exercise.id: exercise,
      };
    }

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: OmniGradientBackground(
          child: SafeArea(
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      );
    }

    return ListenableBuilder(
      listenable: widget.routineState,
      builder: (context, child) {
        if (_showListView || widget.routineState.currentEfforts.isEmpty) {
          return _buildListView(theme);
        }

        return _buildDetailView(theme);
      },
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final efforts = widget.routineState.currentEfforts;
    final exerciseName = _showListView || efforts.isEmpty
        ? 'Exercises'
        : (_exerciseCache[efforts[_currentExerciseIndex].exerciseId]?.name ??
            'Unknown Exercise');
    final subtitle = _showListView
        ? '${efforts.length} exercise${efforts.length != 1 ? 's' : ''}'
        : 'Exercise ${_currentExerciseIndex + 1} / ${efforts.length}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: OmniTheme.textPrimary),
            onPressed: () {
              if (!_showListView) {
                setState(() => _showListView = true);
              } else {
                Navigator.of(context).pop();
              }
            },
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  exerciseName,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: OmniTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: OmniTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListView(ThemeData theme) {
    final efforts = widget.routineState.currentEfforts;

    if (efforts.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: OmniGradientBackground(
          child: Stack(
            children: [
              Center(
                child: Text(
                  'No exercises',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: OmniTheme.textPrimary,
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    _buildHeader(theme),
                    const SizedBox(height: 8),
                    _buildRoutineNameField(theme),
                    const Spacer(),
                  ],
                ),
              ),
              Positioned(
                right: 10,
                bottom: 110,
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    width: 60,
                    height: 60,
                    child: FilledButton(
                      style: ButtonStyle(
                        shape: WidgetStateProperty.all(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      onPressed: () => _addExercise(context),
                      child: const Icon(Icons.add),
                    ),
                  ),
                ),
              ),
              _buildBottomActions(theme),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: OmniGradientBackground(
        child: Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
                  _buildHeader(theme),
                  const SizedBox(height: 8),
                  _buildRoutineNameField(theme),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 140),
                      onReorder: (oldIndex, newIndex) {
                        final updatedIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
                        widget.routineState.reorderExercises(oldIndex, newIndex);
                        if (_currentExerciseIndex == oldIndex) {
                          setState(() => _currentExerciseIndex = updatedIndex);
                        }
                      },
                      buildDefaultDragHandles: false,
                      itemCount: efforts.length,
                      itemBuilder: (context, index) {
                        final effort = efforts[index];
                        final exercise = _exerciseCache[effort.exerciseId];

                        return ExerciseCard(
                          key: ValueKey(effort.id),
                          index: index,
                          effort: effort,
                          exercise: exercise,
                          onDelete: () => _removeExercise(effort.id),
                          onChangeTracking: () => _changeTracking(context, effort, exercise),
                          onTap: () => _openDetail(index),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 10,
              bottom: 110,
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: 60,
                  height: 60,
                  child: FilledButton(
                    style: ButtonStyle(
                      shape: WidgetStateProperty.all(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    onPressed: () => _addExercise(context),
                    child: const Icon(Icons.add),
                  ),
                ),
              ),
            ),
            _buildBottomActions(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildRoutineNameField(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: _nameController,
        onChanged: (value) => widget.routineState.updateRoutineName(value),
        decoration: InputDecoration(
          labelText: 'Routine Name',
          labelStyle: const TextStyle(color: Colors.grey),
          filled: true,
          fillColor: theme.colorScheme.surface.withOpacity(0.7),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey[700]!),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey[700]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.colorScheme.primary),
          ),
        ),
        style: TextStyle(color: theme.colorScheme.onSurface),
      ),
    );
  }

  Widget _buildBottomActions(ThemeData theme) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 10,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: theme.colorScheme.onSurface.withOpacity(0.7)),
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _saveRoutine,
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailView(ThemeData theme) {
    final efforts = widget.routineState.currentEfforts;
    if (efforts.isEmpty) {
      return _buildListView(theme);
    }

    final effort = efforts[_currentExerciseIndex];
    final exercise = _exerciseCache[effort.exerciseId];
    final targets = widget.routineState.getEffortTargets(effort.id);
    final setCount = _getSetCount(effort, targets);
    if (_currentSet > setCount) {
      _currentSet = setCount;
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: OmniGradientBackground(
        child: GestureDetector(
          onHorizontalDragEnd: (details) {
            if (details.primaryVelocity == null) return;
            if (details.primaryVelocity! > 200) {
              _previousSet();
            } else if (details.primaryVelocity! < -200) {
              _nextSet();
            }
          },
          onVerticalDragEnd: (details) {
            if (details.primaryVelocity == null) return;
            if (details.primaryVelocity! < -200) {
              _switchExercise(1);
            } else if (details.primaryVelocity! > 200) {
              _switchExercise(-1);
            }
          },
          child: SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    _buildHeader(theme),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              exercise?.name ?? 'Unknown Exercise',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: OmniTheme.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _getTrackingLabel(effort.effortKind),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Center(
                              child: _buildMetricWidget(effort, targets, theme),
                            ),
                            const SizedBox(height: 16),
                            Center(
                              child: _buildSetProgress(setCount, effort.effortKind, theme),
                            ),
                            const SizedBox(height: 12),
                            Center(
                              child: _buildPreviousSetStats(effort, targets, theme),
                            ),
                            const SizedBox(height: 12),
                            Center(
                              child: _buildSetIndicator(setCount, theme),
                            ),
                            const SizedBox(height: 80),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: _buildSetControls(setCount, effort),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _addExercise(BuildContext context) async {
    if (widget.workoutState == null) return;

    // Step 1: Pick exercise
    final exercise = await showDialog<Exercise>(
      context: context,
      builder: (_) => ExercisePickerDialog(
        workoutState: widget.workoutState!,
      ),
    );

    if (exercise == null) return;

    _exerciseCache[exercise.id] = exercise;

    // Step 2: Pick tracking method
    final chosenMetric = await showDialog<String>(
      context: context,
      builder: (_) => MetricChooserDialog(exercise: exercise),
    );

    if (chosenMetric == null) return;

    final effortKind = ModalityConfig.effortKindFromMetric(chosenMetric);

    await widget.routineState.addExerciseToRoutine(exercise, effortKind);
    if (mounted) {
      setState(() {
        _currentExerciseIndex = widget.routineState.currentEfforts.length - 1;
        _showListView = false;
      });
    }
  }

  void _removeExercise(String templateEffortId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF2a2a2a),
        title: Text('Remove Exercise?', style: TextStyle(color: Colors.white)),
        content: Text(
          'This exercise will be removed from the routine.',
          style: TextStyle(color: Colors.grey[300]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.routineState.removeExerciseFromRoutine(templateEffortId);
              if (!mounted) return;
              final remaining = widget.routineState.currentEfforts.length;
              setState(() {
                if (remaining == 0) {
                  _showListView = true;
                  _currentExerciseIndex = 0;
                } else if (_currentExerciseIndex >= remaining) {
                  _currentExerciseIndex = remaining - 1;
                }
              });
            },
            child: Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _openDetail(int index) {
    setState(() {
      _currentExerciseIndex = index;
      _showListView = false;
      _currentSet = 1;
    });
  }

  Future<void> _changeTracking(
    BuildContext context,
    TemplateEffort effort,
    Exercise? exercise,
  ) async {
    if (exercise == null) return;

    final chosenMetric = await showDialog<String>(
      context: context,
      builder: (_) => MetricChooserDialog(exercise: exercise),
    );

    if (chosenMetric == null) return;

    final effortKind = ModalityConfig.effortKindFromMetric(chosenMetric);
    await widget.routineState.updateEffortKind(effort.id, effortKind);
  }

  Future<void> _saveRoutine() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter a routine name')),
      );
      return;
    }

    await widget.routineState.saveRoutine();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Routine saved successfully')),
    );

    Navigator.pop(context);
  }
}

/// Card displaying an exercise in the routine setup
class ExerciseCard extends StatelessWidget {
  final int index;
  final TemplateEffort effort;
  final Exercise? exercise;
  final VoidCallback onDelete;
  final VoidCallback onChangeTracking;
  final VoidCallback onTap;

  const ExerciseCard({
    super.key,
    required this.index,
    required this.effort,
    required this.exercise,
    required this.onDelete,
    required this.onChangeTracking,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: OmniTheme.surfaceColor.withOpacity(0.7),
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: const Icon(Icons.drag_indicator, color: Colors.grey, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exercise?.name ?? 'Unknown Exercise',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: OmniTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _getTrackingLabel(effort.effortKind),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: OmniTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton(
                color: theme.colorScheme.surface,
                itemBuilder: (context) => [
                  PopupMenuItem(
                    child: Row(
                      children: [
                        Icon(Icons.tune, size: 18, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        const Text('Change Tracking'),
                      ],
                    ),
                    onTap: onChangeTracking,
                  ),
                  PopupMenuItem(
                    child: Row(
                      children: [
                        const Icon(Icons.delete, size: 18, color: Colors.red),
                        const SizedBox(width: 8),
                        const Text('Remove'),
                      ],
                    ),
                    onTap: onDelete,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _getTrackingLabel(String effortKind) {
  switch (effortKind) {
    case 'timed':
      return 'Track by Time';
    case 'drill':
      return 'Track by Hold Time';
    case 'round':
      return 'Track by Rounds';
    case 'set':
      return 'Track by Reps & Sets';
    default:
      return 'Track by Reps & Sets';
  }
}

extension on _RoutineSetupScreenState {
  int _getSetCount(TemplateEffort effort, List<TemplateTarget> targets) {
    if (targets.isEmpty) return 1;
    int maxIndex = 0;
    for (final target in targets) {
      final index = target.setIndex ?? 0;
      if (index > maxIndex) maxIndex = index;
    }
    return maxIndex + 1;
  }

  int? _getTargetInt(List<TemplateTarget> targets, String metricId, int setIndex) {
    for (final target in targets) {
      if (target.metricId == metricId && (target.setIndex ?? 0) == setIndex) {
        return target.targetInt;
      }
    }
    return null;
  }

  double _getTargetDouble(List<TemplateTarget> targets, String metricId, int setIndex) {
    for (final target in targets) {
      if (target.metricId == metricId && (target.setIndex ?? 0) == setIndex) {
        return target.targetMin ?? target.targetMax ?? (target.targetInt?.toDouble() ?? 0.0);
      }
    }
    return 0.0;
  }

  Widget _buildMetricWidget(
    TemplateEffort effort,
    List<TemplateTarget> targets,
    ThemeData theme,
  ) {
    final setIndex = _currentSet - 1;

    switch (effort.effortKind) {
      case 'set':
        final reps = _getTargetInt(targets, MetricIds.reps, setIndex) ?? 10;
        final weight = _getTargetDouble(targets, MetricIds.weight, setIndex);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            InlineMetricEditor(
              metricType: 'reps',
              currentValue: reps,
              unitLabel: 'REPS',
              onValueChanged: (value) => widget.routineState.setTargetValue(
                effort.id,
                MetricIds.reps,
                MetricIds.unitReps,
                setIndex: setIndex,
                targetInt: value as int,
              ),
            ),
            InlineMetricEditor(
              metricType: 'weight',
              currentValue: weight,
              unitLabel: 'LBS',
              onValueChanged: (value) => widget.routineState.setTargetValue(
                effort.id,
                MetricIds.weight,
                MetricIds.unitKg,
                setIndex: setIndex,
                targetMin: value as double,
              ),
            ),
          ],
        );
      case 'timed':
        final duration = _getTargetInt(targets, MetricIds.duration, setIndex) ?? 0;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InlineMetricEditor(
              metricType: 'duration',
              currentValue: duration,
              unitLabel: 'TIME',
              onValueChanged: (value) => widget.routineState.setTargetValue(
                effort.id,
                MetricIds.duration,
                MetricIds.unitSeconds,
                setIndex: setIndex,
                targetInt: value as int,
              ),
            ),
          ],
        );
      case 'round':
        final roundDuration = _getTargetInt(targets, MetricIds.roundDuration, setIndex) ?? 180;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'ROUND $_currentSet',
              style: theme.textTheme.displayLarge?.copyWith(
                fontWeight: FontWeight.w300,
                letterSpacing: -2,
                fontSize: theme.textTheme.displayMedium?.fontSize,
              ),
            ),
            const SizedBox(height: 12),
            InlineMetricEditor(
              metricType: 'duration',
              currentValue: roundDuration,
              unitLabel: 'DURATION',
              onValueChanged: (value) async {
                await widget.routineState.setTargetValue(
                  effort.id,
                  MetricIds.roundDuration,
                  MetricIds.unitSeconds,
                  setIndex: setIndex,
                  targetInt: value as int,
                );
                await widget.routineState.setTargetValue(
                  effort.id,
                  MetricIds.rounds,
                  MetricIds.unitRounds,
                  setIndex: setIndex,
                  targetInt: 1,
                );
              },
            ),
          ],
        );
      case 'drill':
        final duration = _getTargetInt(targets, MetricIds.duration, setIndex) ?? 0;
        final rpe = _getTargetInt(targets, MetricIds.rpe, setIndex) ?? 5;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InlineMetricEditor(
              metricType: 'duration',
              currentValue: duration,
              unitLabel: 'HOLD TIME',
              onValueChanged: (value) => widget.routineState.setTargetValue(
                effort.id,
                MetricIds.duration,
                MetricIds.unitSeconds,
                setIndex: setIndex,
                targetInt: value as int,
              ),
            ),
            InlineMetricEditor(
              metricType: 'rpe',
              currentValue: rpe,
              unitLabel: 'RPE',
              onValueChanged: (value) => widget.routineState.setTargetValue(
                effort.id,
                MetricIds.rpe,
                null,
                setIndex: setIndex,
                targetInt: value as int,
              ),
            ),
          ],
        );
      default:
        return Text('—', style: theme.textTheme.displayLarge);
    }
  }

  Widget _buildSetProgress(int totalEntries, String effortKind, ThemeData theme) {
    String label;
    switch (effortKind) {
      case 'set':
        label = 'Set $_currentSet of $totalEntries';
        break;
      case 'timed':
        label = 'Interval $_currentSet of $totalEntries';
        break;
      case 'round':
        label = 'Round $_currentSet of $totalEntries';
        break;
      case 'drill':
        label = 'Hold $_currentSet of $totalEntries';
        break;
      default:
        label = 'Set $_currentSet of $totalEntries';
    }

    return Text(
      label,
      style: theme.textTheme.titleMedium?.copyWith(
        letterSpacing: 2,
        color: theme.colorScheme.onSurface.withAlpha((0.6 * 255).round()),
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildPreviousSetStats(
    TemplateEffort effort,
    List<TemplateTarget> targets,
    ThemeData theme,
  ) {
    if (_currentSet <= 1) {
      return const SizedBox.shrink();
    }

    final previousIndex = _currentSet - 2;
    String statsText = '';

    switch (effort.effortKind) {
      case 'set':
        final reps = _getTargetInt(targets, MetricIds.reps, previousIndex) ?? 0;
        final weight = _getTargetDouble(targets, MetricIds.weight, previousIndex);
        statsText = 'Previous: $reps reps @ ${weight.toStringAsFixed(1)} lbs';
        break;
      case 'timed':
        final duration = _getTargetInt(targets, MetricIds.duration, previousIndex) ?? 0;
        final mins = duration ~/ 60;
        final secs = duration % 60;
        statsText = 'Previous: ${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
        break;
      case 'round':
        final roundDuration = _getTargetInt(targets, MetricIds.roundDuration, previousIndex) ?? 0;
        final mins = roundDuration ~/ 60;
        final secs = roundDuration % 60;
        statsText = 'Previous: ${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')} per round';
        break;
      case 'drill':
        final duration = _getTargetInt(targets, MetricIds.duration, previousIndex) ?? 0;
        final rpe = _getTargetInt(targets, MetricIds.rpe, previousIndex) ?? 5;
        final mins = duration ~/ 60;
        final secs = duration % 60;
        statsText = 'Previous: ${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')} hold @ RPE $rpe';
        break;
      default:
        return const SizedBox.shrink();
    }

    return Text(
      statsText,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurface.withAlpha((0.5 * 255).round()),
        fontStyle: FontStyle.italic,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildSetIndicator(int totalEntries, ThemeData theme) {
    if (totalEntries <= 1) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 8,
      children: List.generate(totalEntries, (index) {
        final isActive = index == _currentSet - 1;
        return GestureDetector(
          onTap: () => _jumpToSet(index + 1),
          child: Container(
            width: isActive ? 14 : 10,
            height: isActive ? 14 : 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withAlpha((0.2 * 255).round()),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildSetControls(int totalEntries, TemplateEffort effort) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildArrowButton(
          icon: Icons.arrow_back,
          label: 'Previous Set',
          isEnabled: _currentSet > 1,
          onPressed: _currentSet > 1 ? _previousSet : null,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildIconButton(
              Icons.playlist_add,
              () => _addSet(effort),
              tooltip: 'Add set',
            ),
            const SizedBox(width: 24),
            _buildIconButton(
              Icons.delete_outline,
              () => _deleteLastSet(effort),
              tooltip: 'Delete last set',
            ),
          ],
        ),
        _buildArrowButton(
          icon: Icons.arrow_forward,
          label: 'Next Set',
          isEnabled: _currentSet < totalEntries,
          onPressed: _currentSet < totalEntries ? _nextSet : null,
        ),
      ],
    );
  }

  void _previousSet() {
    if (_currentSet <= 1) return;
    setState(() => _currentSet--);
  }

  void _nextSet() {
    final efforts = widget.routineState.currentEfforts;
    if (efforts.isEmpty) return;
    final effort = efforts[_currentExerciseIndex];
    final targets = widget.routineState.getEffortTargets(effort.id);
    final setCount = _getSetCount(effort, targets);
    if (_currentSet >= setCount) return;
    setState(() => _currentSet++);
  }

  void _jumpToSet(int setNumber) {
    setState(() {
      _currentSet = setNumber;
    });
  }

  Future<void> _addSet(TemplateEffort effort) async {
    await widget.routineState.addSetForEffort(effort.id, effort.effortKind);
    final targets = widget.routineState.getEffortTargets(effort.id);
    final setCount = _getSetCount(effort, targets);
    if (mounted) {
      setState(() => _currentSet = setCount);
    }
  }

  Future<void> _deleteLastSet(TemplateEffort effort) async {
    final targets = widget.routineState.getEffortTargets(effort.id);
    final setCount = _getSetCount(effort, targets);
    if (setCount <= 1) return;
    await widget.routineState.removeLastSetForEffort(effort.id);
    if (mounted && _currentSet > setCount - 1) {
      setState(() => _currentSet = setCount - 1);
    }
  }

  Widget _buildArrowButton({
    required IconData icon,
    required String label,
    required bool isEnabled,
    required VoidCallback? onPressed,
  }) {
    final theme = Theme.of(context);
    return Tooltip(
      message: label,
      child: Container(
        decoration: const BoxDecoration(shape: BoxShape.circle),
        child: Material(
          shape: const CircleBorder(),
          color: isEnabled
              ? theme.colorScheme.onSurface.withAlpha((0.1 * 255).round())
              : theme.colorScheme.onSurface.withAlpha((0.05 * 255).round()),
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(
                icon,
                size: 24,
                color: isEnabled
                    ? theme.colorScheme.onSurface.withAlpha((0.5 * 255).round())
                    : theme.colorScheme.onSurface.withAlpha((0.2 * 255).round()),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton(
    IconData icon,
    VoidCallback onPressed, {
    String? tooltip,
  }) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip ?? '',
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon),
        color: theme.colorScheme.onSurface.withAlpha((0.5 * 255).round()),
        iconSize: 28,
      ),
    );
  }

  void _switchExercise(int delta) {
    final efforts = widget.routineState.currentEfforts;
    if (efforts.isEmpty) return;
    final newIndex = _currentExerciseIndex + delta;
    if (newIndex < 0 || newIndex >= efforts.length) return;
    setState(() {
      _currentExerciseIndex = newIndex;
      _currentSet = 1;
    });
  }
}
