import 'package:flutter/material.dart';
import '../exercise/exercise_picker_screen.dart';
import '../../core/navigation/navigation.dart';
import '../../widgets/pickers/modality_picker_dialog.dart';
import '../../core/constants/modality_config.dart';
import '../../core/constants/modality_display.dart';
import '../../core/constants/metric_ids.dart';
import '../../core/constants/omni_theme.dart';
import '../../core/constants/workout_constants.dart';
import '../../widgets/session/inline_metric_editor.dart';
import '../../state/routine/routine_state.dart';
import '../../state/settings/settings_state.dart';
import '../../state/workout/workout_state.dart';
import '../../core/utils/unit_formatter.dart';
import '../../data/models/models.dart';
import '../../widgets/inputs/numeric_field_with_done_bar.dart';
import '../../widgets/layout/omni_back_header.dart';

/// Screen for creating or editing a workout routine (template)
class RoutineSetupScreen extends StatefulWidget {
  final RoutineState routineState;
  final WorkoutState? workoutState; // Optional for loading exercise data
  final String? templateId; // null = create new, non-null = edit existing
  final SettingsState? settingsState;

  const RoutineSetupScreen({
    super.key,
    required this.routineState,
    this.workoutState,
    this.templateId,
    this.settingsState,
  });

  @override
  State<RoutineSetupScreen> createState() => _RoutineSetupScreenState();
}

class _RoutineSetupScreenState extends State<RoutineSetupScreen> {
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  bool _isLoading = true;

  String get _preferredWeightUnitLabel => widget.settingsState != null
      ? UnitFormatter.weightLabelUpper(widget.settingsState!)
      : UnitFormatter.weightLabelUpperForUnit('kg');

  /// Convert a raw display-unit value to canonical kg for storage.
  double _toCanonicalWeight(double displayValue) => widget.settingsState != null
      ? UnitFormatter.toCanonicalWeight(displayValue, widget.settingsState!)
      : displayValue;

  /// Convert a canonical kg value to the user's preferred display unit.
  double _fromCanonicalWeight(double kg) => widget.settingsState != null
      ? UnitFormatter.convertWeight(kg, widget.settingsState!)
      : kg;
  Map<String, Exercise> _exerciseCache = {};
  bool _showListView = true;
  int _currentExerciseIndex = 0;
  int _currentSet = 1;
  String? _selectedFocusModality;

  // Scroll controller for the exercise list view. Scrolled to the bottom
  // when returning from exercise detail so the user lands near 'Add Exercise'.
  final ScrollController _listScrollController = ScrollController();

  static const List<String> _segmentTypes = [
    'warmup',
    'main',
    'accessory',
    'finisher',
    'cooldown',
  ];

  @override
  void initState() {
    super.initState();
    widget.routineState.setAutosaveEnabled(false);
    _nameController = TextEditingController();
    _descriptionController = TextEditingController();
    _loadRoutine();
  }

  @override
  void dispose() {
    widget.routineState.setAutosaveEnabled(true);
    _nameController.dispose();
    _descriptionController.dispose();
    _listScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadRoutine() async {
    if (widget.templateId != null) {
      // Load existing routine for editing
      await widget.routineState.loadRoutineForEditing(widget.templateId!);
      _nameController.text = widget.routineState.currentTemplate?.name ?? '';
      _descriptionController.text =
          widget.routineState.currentTemplate?.description ?? '';
      _selectedFocusModality =
          widget.routineState.currentTemplate?.focusModality;
    } else {
      // Create new routine
      await widget.routineState.createNewRoutine('New Routine');
      _nameController.text = '';
      _descriptionController.text = '';
      _selectedFocusModality = null;
    }

    if (widget.workoutState != null) {
      await widget.workoutState!.loadAllExercises();
      _exerciseCache = {
        for (final exercise in widget.workoutState!.allExercises)
          exercise.id: exercise,
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
        extendBody: true,
        body: SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }

    return ListenableBuilder(
      listenable: widget.routineState,
      builder: (context, child) {
        final content =
            (_showListView || widget.routineState.currentEfforts.isEmpty)
            ? _buildListView(theme)
            : _buildDetailView(theme);

        return WillPopScope(onWillPop: _handleWillPop, child: content);
      },
    );
  }

  Widget _buildListView(ThemeData theme) {
    final segments = widget.routineState.currentSegments;
    final efforts = widget.routineState.currentEfforts;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      extendBodyBehindAppBar: true,
      appBar: OmniBackHeader(
        title: 'Exercises',
        subtitle: '${efforts.length} exercise${efforts.length != 1 ? 's' : ''}',
        onBack: () => _discardAndPop(),
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 8),
                _buildRoutineNameField(theme),
                const SizedBox(height: 12),
                _buildRoutineDescriptionField(theme),
                const SizedBox(height: 12),
                _buildRoutineModalityField(theme),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    controller: _listScrollController,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 140),
                    children: [
                      for (final entry in segments.asMap().entries)
                        _buildSegmentCard(entry.key, entry.value, theme),
                      const SizedBox(height: 12),
                      _buildAddBlockButton(theme),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _buildBottomActions(theme),
        ],
      ),
    );
  }

  Widget _buildRoutineNameField(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        textCapitalization: TextCapitalization.words,
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

  Widget _buildRoutineDescriptionField(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        textCapitalization: TextCapitalization.sentences,
        controller: _descriptionController,
        onChanged: (value) =>
            widget.routineState.updateRoutineDescription(value),
        decoration: InputDecoration(
          labelText: 'Description (optional)',
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
        minLines: 1,
        maxLines: 2,
      ),
    );
  }

  Widget _buildRoutineModalityField(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DropdownButtonFormField<String?>(
        initialValue: _selectedFocusModality,
        decoration: InputDecoration(
          labelText: 'Focus Modality',
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
        items: [
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('Mixed / Not set'),
          ),
          for (final entry in ModalityDisplay.names.entries)
            DropdownMenuItem<String?>(
              value: entry.key,
              child: Text(entry.value),
            ),
        ],
        onChanged: (value) {
          setState(() => _selectedFocusModality = value);
          widget.routineState.updateRoutineFocusModality(value);
        },
      ),
    );
  }

  Widget _buildSegmentCard(
    int index,
    TemplateSegment segment,
    ThemeData theme,
  ) {
    final efforts = widget.routineState.getEffortsForSegment(segment.id);

    return Card(
      color: theme.colorScheme.surface.withOpacity(0.7),
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        segment.name ?? 'Block ${index + 1}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _segmentLabel(segment.segmentType),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color:
                              theme.textTheme.bodyMedium?.color ??
                              theme.colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_upward, size: 18),
                  color: theme.colorScheme.primary,
                  onPressed: index > 0
                      ? () => widget.routineState.reorderSegments(
                          index,
                          index - 1,
                        )
                      : null,
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_downward, size: 18),
                  color: theme.colorScheme.primary,
                  onPressed:
                      index < widget.routineState.currentSegments.length - 1
                      ? () => widget.routineState.reorderSegments(
                          index,
                          index + 1,
                        )
                      : null,
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Add exercise to block',
                  onPressed: () => _addExercise(context, segment.id),
                ),
                PopupMenuButton(
                  color: theme.colorScheme.surface,
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      onTap: () => _editSegment(segment),
                      child: Row(
                        children: [
                          Icon(
                            Icons.edit,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          const Text('Edit Block'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      onTap: () => widget.routineState.cloneSegment(segment.id),
                      child: Row(
                        children: [
                          Icon(
                            Icons.copy,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          const Text('Clone Block'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      onTap: () => _confirmDeleteSegment(segment),
                      child: Row(
                        children: [
                          const Icon(Icons.delete, size: 18, color: Colors.red),
                          const SizedBox(width: 8),
                          const Text('Delete Block'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (efforts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No exercises in this block yet.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
              )
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: efforts.length,
                onReorder: (oldIndex, newIndex) {
                  widget.routineState.reorderExercises(
                    segment.id,
                    oldIndex,
                    newIndex,
                  );
                },
                itemBuilder: (context, effortIndex) {
                  final effort = efforts[effortIndex];
                  final exercise = _exerciseCache[effort.exerciseId];
                  final restLabel = _formatRestLabel(effort);
                  final targets = widget.routineState.getEffortTargets(effort.id);
                  final setCount = _getSetCount(effort, targets);

                  return ExerciseCard(
                    key: ValueKey(effort.id),
                    index: effortIndex,
                    effort: effort,
                    exercise: exercise,
                    restLabel: restLabel,
                    setCount: setCount,
                    onDelete: () => _removeExercise(effort.id),
                    onChangeTracking: () =>
                        _changeTracking(context, effort, exercise),
                    onEditRest: () => _editRest(effort),
                    onTap: () => _openDetailForEffort(effort.id),
                  );
                },
              ),

          ],
        ),
      ),
    );
  }

  Widget _buildAddBlockButton(ThemeData theme) {
    return OutlinedButton.icon(
      onPressed: _addSegment,
      icon: const Icon(Icons.add_circle_outline),
      label: const Text('Add Block'),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        side: BorderSide(color: theme.colorScheme.primary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildBottomActions(ThemeData theme) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.surface.withOpacity(0.0),
              theme.colorScheme.surface.withOpacity(0.92),
              theme.colorScheme.surface,
            ],
            stops: const [0.0, 0.35, 1.0],
          ),
        ),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(16, 24, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: OmniTheme.buttonPrimaryHeight,
                  child: OutlinedButton(
                    onPressed: _discardAndPop,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                      ),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          OmniTheme.buttonBorderRadius,
                        ),
                      ),
                    ),
                    child: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Cancel'),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: OmniTheme.buttonPrimaryHeight,
                  child: FilledButton(
                    onPressed: _saveRoutine,
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          OmniTheme.buttonBorderRadius,
                        ),
                      ),
                    ),
                    child: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Save'),
                    ),
                  ),
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
    final segment = widget.routineState.getSegmentForEffort(effort.id);
    final targets = widget.routineState.getEffortTargets(effort.id);
    final setCount = _getSetCount(effort, targets);
    if (_currentSet > setCount) {
      _currentSet = setCount;
    }
    final canAddSet = setCount < WorkoutConstants.maxEntriesPerEffort;
    final exerciseName = exercise?.name ?? 'Unknown Exercise';

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      extendBodyBehindAppBar: true,
      appBar: OmniBackHeader(
        title: exerciseName,
        subtitle: 'Exercise ${_currentExerciseIndex + 1} / ${efforts.length}',
        onBack: () {
          setState(() => _showListView = true);
          _scrollListToBottom();
        },
      ),
      body: GestureDetector(
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
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            segment?.name ?? 'Block',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color:
                                  theme.textTheme.bodyMedium?.color ??
                                  theme.colorScheme.onSurface.withOpacity(0.7),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            exercise?.name ?? 'Unknown Exercise',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
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
                            child: _buildSetProgress(
                              setCount,
                              effort,
                              canAddSet,
                              theme,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Center(
                            child: _buildPreviousSetStats(
                              effort,
                              targets,
                              theme,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Center(child: _buildSetIndicator(setCount, theme)),
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
    );
  }

  void _addExercise(BuildContext context, String segmentId) async {
    if (widget.workoutState == null) return;

    // Step 1: Pick exercise
    final exercise = await OmniNavigator.push<Exercise>(
      context,
      (_) => ExercisePickerScreen(workoutState: widget.workoutState!),
    );

    if (exercise == null) return;

    _exerciseCache[exercise.id] = exercise;

    // Step 2: Pick modality using the shared picker.
    final modalityResult = await showDialog<(bool, String?)>(
      context: context,
      builder: (_) => const ModalityPickerDialog(),
    );

    if (modalityResult == null) return;

    final (_, pickedModality) = modalityResult;
    if (pickedModality == null) return;

    final effortKind =
        ModalityConfig.forModality(pickedModality)?.effortKind ?? 'set';

    await widget.routineState.addExerciseToRoutine(
      exercise,
      effortKind,
      segmentId: segmentId,
    );
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

  void _openDetailForEffort(String effortId) {
    final efforts = widget.routineState.currentEfforts;
    final index = efforts.indexWhere((e) => e.id == effortId);
    if (index == -1) return;
    _openDetail(index);
  }

  Future<void> _changeTracking(
    BuildContext context,
    TemplateEffort effort,
    Exercise? exercise,
  ) async {
    if (exercise == null) return;

    final modalityResult = await showDialog<(bool, String?)>(
      context: context,
      builder: (_) => const ModalityPickerDialog(),
    );

    if (modalityResult == null) return;

    final (_, pickedModality) = modalityResult;
    if (pickedModality == null) return;

    final effortKind =
        ModalityConfig.forModality(pickedModality)?.effortKind ?? 'set';
    await widget.routineState.updateEffortKind(effort.id, effortKind);
  }

  Future<void> _addSegment() async {
    await widget.routineState.addSegment();
  }

  Future<void> _editSegment(TemplateSegment segment) async {
    final nameController = TextEditingController(text: segment.name ?? '');
    String selectedType = segment.segmentType;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Block'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              textCapitalization: TextCapitalization.sentences,
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Block Name'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selectedType,
              items: _segmentTypes
                  .map(
                    (type) => DropdownMenuItem(
                      value: type,
                      child: Text(_segmentLabel(type)),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                selectedType = value;
              },
              decoration: const InputDecoration(labelText: 'Block Type'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == true) {
      await widget.routineState.updateSegment(
        segment.id,
        name: nameController.text.trim().isEmpty
            ? segment.name
            : nameController.text.trim(),
        segmentType: selectedType,
      );
    }
  }

  Future<void> _confirmDeleteSegment(TemplateSegment segment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Block?'),
        content: const Text('This block and its exercises will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.routineState.removeSegment(segment.id);
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
    }
  }

  String _segmentLabel(String segmentType) {
    switch (segmentType) {
      case 'warmup':
        return 'Warmup';
      case 'main':
        return 'Main';
      case 'accessory':
        return 'Accessory';
      case 'finisher':
        return 'Finisher';
      case 'cooldown':
        return 'Cooldown';
      default:
        return 'Block';
    }
  }

  String? _formatRestLabel(TemplateEffort effort) {
    final restSeconds = effort.restSeconds;
    if (restSeconds == null || restSeconds <= 0) return null;
    final minutes = restSeconds ~/ 60;
    final seconds = restSeconds % 60;
    final timeLabel = minutes > 0
        ? '${minutes}m ${seconds.toString().padLeft(2, '0')}s'
        : '${seconds}s';

    if (effort.restType == null || effort.restType == 'between_sets') {
      return 'Rest $timeLabel between sets';
    }
    if (effort.restType == 'after_exercise') {
      return 'Rest $timeLabel after exercise';
    }
    return 'Rest $timeLabel';
  }

  Future<void> _editRest(TemplateEffort effort) async {
    final restController = TextEditingController(
      text: effort.restSeconds?.toString() ?? '',
    );
    String restType = effort.restType ?? 'between_sets';

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Rest'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NumericFieldWithDoneBar(
              controller: restController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Rest seconds'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: restType,
              items: const [
                DropdownMenuItem(
                  value: 'between_sets',
                  child: Text('Between sets'),
                ),
                DropdownMenuItem(
                  value: 'after_exercise',
                  child: Text('After exercise'),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                restType = value;
              },
              decoration: const InputDecoration(labelText: 'Rest type'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == true) {
      final parsed = int.tryParse(restController.text.trim());
      await widget.routineState.updateEffortRest(
        effort.id,
        restSeconds: parsed,
        restType: restType,
      );
    }
  }

  Future<void> _saveRoutine() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Please enter a routine name')));
      return;
    }

    await widget.routineState.saveRoutine();

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Routine saved successfully')));

    Navigator.pop(context);
  }

  Future<bool> _handleWillPop() async {
    if (!_showListView) {
      setState(() => _showListView = true);
      _scrollListToBottom();
      return false;
    }

    widget.routineState.clearCurrentRoutine();
    return true;
  }

  void _discardAndPop() {
    widget.routineState.clearCurrentRoutine();
    Navigator.of(context).pop();
  }

  void _updateUi(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  /// Scrolls the exercise list to the bottom after the current frame renders.
  /// Called when navigating back from a detail view to the list view so the
  /// user lands near the 'Add Exercise' button at the bottom.
  void _scrollListToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_listScrollController.hasClients &&
          _listScrollController.position.maxScrollExtent > 0) {
        _listScrollController.jumpTo(
          _listScrollController.position.maxScrollExtent,
        );
      }
    });
  }
}

/// Card displaying an exercise in the routine setup
class ExerciseCard extends StatelessWidget {
  final int index;
  final TemplateEffort effort;
  final Exercise? exercise;
  final String? restLabel;
  final int setCount;
  final VoidCallback onDelete;
  final VoidCallback onChangeTracking;
  final VoidCallback onEditRest;
  final VoidCallback onTap;

  const ExerciseCard({
    super.key,
    required this.index,
    required this.effort,
    required this.exercise,
    this.restLabel,
    required this.setCount,
    required this.onDelete,
    required this.onChangeTracking,
    required this.onEditRest,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surface.withOpacity(0.7),
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
                child: Icon(
                  Icons.drag_indicator,
                  color: theme.colorScheme.onSurface.withOpacity(0.55),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exercise?.name ?? 'Unknown Exercise',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _getTrackingLabel(effort.effortKind),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.textTheme.bodyMedium?.color ??
                            theme.colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                    if (restLabel != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        restLabel!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary.withOpacity(0.8),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      '$setCount set${setCount == 1 ? '' : 's'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton(
                color: theme.colorScheme.surface,
                itemBuilder: (context) => [
                  PopupMenuItem(
                    onTap: onChangeTracking,
                    child: Row(
                      children: [
                        Icon(
                          Icons.tune,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        const Text('Change Tracking'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    onTap: onEditRest,
                    child: Row(
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        const Text('Edit Rest'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    onTap: onDelete,
                    child: Row(
                      children: [
                        const Icon(Icons.delete, size: 18, color: Colors.red),
                        const SizedBox(width: 8),
                        const Text('Remove'),
                      ],
                    ),
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

  int? _getTargetInt(
    List<TemplateTarget> targets,
    String metricId,
    int setIndex,
  ) {
    for (final target in targets) {
      if (target.metricId == metricId && (target.setIndex ?? 0) == setIndex) {
        return target.targetInt;
      }
    }
    return null;
  }

  double _getTargetDouble(
    List<TemplateTarget> targets,
    String metricId,
    int setIndex,
  ) {
    for (final target in targets) {
      if (target.metricId == metricId && (target.setIndex ?? 0) == setIndex) {
        return target.targetMin ??
            target.targetMax ??
            (target.targetInt?.toDouble() ?? 0.0);
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
        // Target stored in canonical kg; convert to display unit for editor.
        final weight = _fromCanonicalWeight(
          _getTargetDouble(targets, MetricIds.weight, setIndex),
        );
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
              unitLabel: _preferredWeightUnitLabel,
              onValueChanged: (value) => widget.routineState.setTargetValue(
                effort.id,
                MetricIds.weight,
                MetricIds.unitKg,
                setIndex: setIndex,
                // Convert display-unit value to canonical kg before persisting.
                targetMin: _toCanonicalWeight(value as double),
              ),
            ),
          ],
        );
      case 'timed':
        final hasTimedExtraWeightTarget = targets.any(
          (t) => t.metricId == MetricIds.extraWeight,
        );
        if (!hasTimedExtraWeightTarget) return const SizedBox.shrink();
        // Target stored in canonical kg; convert to display unit for editor.
        final timedExtraWeight = _fromCanonicalWeight(
          _getTargetDouble(targets, MetricIds.extraWeight, setIndex),
        );
        return InlineMetricEditor(
          metricType: 'extra-weight',
          currentValue: timedExtraWeight,
          unitLabel: 'EXTRA $_preferredWeightUnitLabel',
          onValueChanged: (value) => widget.routineState.setTargetValue(
            effort.id,
            MetricIds.extraWeight,
            MetricIds.unitKg,
            setIndex: setIndex,
            // Convert display-unit value to canonical kg before persisting.
            targetMin: _toCanonicalWeight(value as double),
          ),
        );
      case 'round':
        final roundDuration =
            _getTargetInt(targets, MetricIds.roundDuration, setIndex) ?? 180;
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
        // Target stored in canonical kg; convert to display unit for editor.
        final extraWeight = _fromCanonicalWeight(
          _getTargetDouble(targets, MetricIds.extraWeight, setIndex),
        );
        return InlineMetricEditor(
          metricType: 'extra-weight',
          currentValue: extraWeight,
          unitLabel: 'EXTRA $_preferredWeightUnitLabel',
          onValueChanged: (value) => widget.routineState.setTargetValue(
            effort.id,
            MetricIds.extraWeight,
            MetricIds.unitKg,
            setIndex: setIndex,
            // Convert display-unit value to canonical kg before persisting.
            targetMin: _toCanonicalWeight(value as double),
          ),
        );
      default:
        return Text('—', style: theme.textTheme.displayLarge);
    }
  }

  Widget _buildSetProgress(
    int totalEntries,
    TemplateEffort effort,
    bool canAddSet,
    ThemeData theme,
  ) {
    String label;
    switch (effort.effortKind) {
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

    // Only allow removing the last set to prevent mid-sequence deletion.
    final canRemove = totalEntries > 1 && _currentSet == totalEntries;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compactSpacing = constraints.maxWidth < 320 ? 2.0 : 4.0;
        final compactLetterSpacing = constraints.maxWidth < 320 ? 1.0 : 2.0;

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Tooltip(
              message: 'Remove set',
              child: InkWell(
                key: const Key('routine-remove-set'),
                onTap: canRemove ? () => _deleteLastSet(effort) : null,
                customBorder: const CircleBorder(),
                child: Container(
                  constraints:
                      const BoxConstraints(minWidth: 50, minHeight: 50),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.remove,
                    size: 24,
                    color: canRemove
                        ? theme.colorScheme.onSurface
                            .withAlpha((0.35 * 255).round())
                        : theme.colorScheme.onSurface
                            .withAlpha((0.15 * 255).round()),
                  ),
                ),
              ),
            ),
            SizedBox(width: compactSpacing),
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  letterSpacing: compactLetterSpacing,
                  color: theme.colorScheme.onSurface
                      .withAlpha((0.6 * 255).round()),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            SizedBox(width: compactSpacing),
            Tooltip(
              message: canAddSet
                  ? 'Add set'
                  : 'Max ${WorkoutConstants.maxEntriesPerEffort} entries',
              child: InkWell(
                key: const Key('routine-add-set'),
                onTap: canAddSet ? () => _addSet(effort) : null,
                customBorder: const CircleBorder(),
                child: Container(
                  constraints:
                      const BoxConstraints(minWidth: 50, minHeight: 50),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.add,
                    size: 24,
                    color: canAddSet
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface
                            .withAlpha((0.2 * 255).round()),
                  ),
                ),
              ),
            ),
          ],
        );
      },
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
        final weight = _getTargetDouble(
          targets,
          MetricIds.weight,
          previousIndex,
        );
        statsText = widget.settingsState != null
            ? 'Previous: $reps reps @ ${UnitFormatter.formatWeightValue(weight, widget.settingsState!)} ${UnitFormatter.weightLabel(widget.settingsState!)}'
            : 'Previous: $reps reps @ ${weight.toStringAsFixed(1)} ${UnitFormatter.weightLabelForUnit('kg')}';
        break;
      case 'timed':
        final duration =
            _getTargetInt(targets, MetricIds.duration, previousIndex) ?? 0;
        final mins = duration ~/ 60;
        final secs = duration % 60;
        statsText =
            'Previous: ${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
        final timedPrevEw =
            targets.any((t) => t.metricId == MetricIds.extraWeight)
            ? _getTargetDouble(targets, MetricIds.extraWeight, previousIndex)
            : null;
        if (timedPrevEw != null && timedPrevEw != 0.0) {
          statsText += widget.settingsState != null
              ? ' + ${UnitFormatter.formatWeightValue(timedPrevEw, widget.settingsState!)} ${UnitFormatter.weightLabel(widget.settingsState!)}'
              : ' + ${timedPrevEw.toStringAsFixed(1)} ${UnitFormatter.weightLabelForUnit('kg')}';
        }
        break;
      case 'round':
        final roundDuration =
            _getTargetInt(targets, MetricIds.roundDuration, previousIndex) ?? 0;
        final mins = roundDuration ~/ 60;
        final secs = roundDuration % 60;
        statsText =
            'Previous: ${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')} per round';
        break;
      case 'drill':
        final duration =
            _getTargetInt(targets, MetricIds.duration, previousIndex) ?? 0;
        final extraWeight = _getTargetDouble(
          targets,
          MetricIds.extraWeight,
          previousIndex,
        );
        final mins = duration ~/ 60;
        final secs = duration % 60;
        final ewSign = extraWeight > 0 ? '+' : '';
        statsText = widget.settingsState != null
            ? 'Previous: ${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')} hold @ $ewSign${UnitFormatter.formatWeightValue(extraWeight.abs(), widget.settingsState!)} ${UnitFormatter.weightLabel(widget.settingsState!)}'
            : 'Previous: ${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')} hold @ $ewSign${extraWeight.toStringAsFixed(1)} ${UnitFormatter.weightLabelForUnit('kg')}';
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
    _updateUi(() => _currentSet--);
  }

  void _nextSet() {
    final efforts = widget.routineState.currentEfforts;
    if (efforts.isEmpty) return;
    final effort = efforts[_currentExerciseIndex];
    final targets = widget.routineState.getEffortTargets(effort.id);
    final setCount = _getSetCount(effort, targets);
    if (_currentSet >= setCount) return;
    _updateUi(() => _currentSet++);
  }

  void _jumpToSet(int setNumber) {
    _updateUi(() {
      _currentSet = setNumber;
    });
  }

  Future<void> _addSet(TemplateEffort effort) async {
    final targets = widget.routineState.getEffortTargets(effort.id);
    final setCount = _getSetCount(effort, targets);
    if (setCount >= WorkoutConstants.maxEntriesPerEffort) {
      return;
    }

    await widget.routineState.addSetForEffort(effort.id, effort.effortKind);
    final updatedTargets = widget.routineState.getEffortTargets(effort.id);
    final updatedSetCount = _getSetCount(effort, updatedTargets);
    _updateUi(() => _currentSet = updatedSetCount);
  }

  Future<void> _deleteLastSet(TemplateEffort effort) async {
    final targets = widget.routineState.getEffortTargets(effort.id);
    final setCount = _getSetCount(effort, targets);
    if (setCount <= 1) return;
    await widget.routineState.removeLastSetForEffort(effort.id);
    if (_currentSet > setCount - 1) {
      _updateUi(() => _currentSet = setCount - 1);
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
                    : theme.colorScheme.onSurface.withAlpha(
                        (0.2 * 255).round(),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _switchExercise(int delta) {
    final efforts = widget.routineState.currentEfforts;
    if (efforts.isEmpty) return;
    final newIndex = _currentExerciseIndex + delta;
    if (newIndex < 0 || newIndex >= efforts.length) return;
    _updateUi(() {
      _currentExerciseIndex = newIndex;
      _currentSet = 1;
    });
  }
}
