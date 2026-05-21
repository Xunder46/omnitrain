import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';
import '../../data/models/models.dart';
import '../../state/workout/workout_state.dart';
import '../../features/exercise/exercise_editor_screen.dart';
import '../../core/constants/modality_config.dart';
import '../../core/navigation/navigation.dart';

/// Dialog for selecting an exercise with search and filters
class ExercisePickerDialog extends StatefulWidget {
  final WorkoutState workoutState;
  final String? sessionModality;

  const ExercisePickerDialog({
    super.key,
    required this.workoutState,
    this.sessionModality,
  });

  @override
  State<ExercisePickerDialog> createState() => _ExercisePickerDialogState();
}

class _ExercisePickerDialogState extends State<ExercisePickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  List<Exercise> _filteredExercises = [];
  List<Exercise> _recommendedExercises =
      []; // Exercises with score >= threshold
  List<Exercise> _otherExercises = []; // Exercises with score < threshold
  List<MuscleGroup> _muscleGroups = [];
  List<Discipline> _disciplines = [];
  final Map<String, List<MuscleGroup>> _exerciseMuscleGroupsCache = {};

  String? _selectedDisciplineId;
  String? _selectedMuscleGroupId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void didUpdateWidget(ExercisePickerDialog oldWidget) {
    super.didUpdateWidget(oldWidget);

    // If the modality changed, refresh the exercise list and clear cache
    if (oldWidget.sessionModality != widget.sessionModality) {
      // Clear muscle groups cache since ordering may change with modality
      _exerciseMuscleGroupsCache.clear();
      // Reset filters to start fresh with new modality
      setState(() {
        _selectedDisciplineId = null;
        _selectedMuscleGroupId = null;
        _filteredExercises = []; // Clear the list immediately
      });
      _searchController.clear();
      // Refresh exercises with new modality
      _searchExercises();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    // Load reference data if not already loaded
    if (widget.workoutState.muscleGroups.isEmpty) {
      await widget.workoutState.loadMuscleGroups();
    }
    if (widget.workoutState.disciplines.isEmpty) {
      await widget.workoutState.loadDisciplines();
    }

    _muscleGroups = widget.workoutState.muscleGroups;
    _disciplines = widget.workoutState.disciplines;

    // Load initial filtered exercises
    await _searchExercises();

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _searchExercises();
    });
  }

  Future<void> _searchExercises() async {
    final searchText = _searchController.text.trim();
    final muscleGroupIds = _selectedMuscleGroupId != null
        ? [_selectedMuscleGroupId!]
        : null;

    final results = await widget.workoutState.getExercisesRankedForModality(
      modality: widget
          .sessionModality, // Explicitly pass modality to ensure consistency
      searchText: searchText.isEmpty ? null : searchText,
      disciplineId: _selectedDisciplineId,
      muscleGroupIds: muscleGroupIds,
    );

    // Load muscle groups for each exercise for display
    for (final exercise in results) {
      if (!_exerciseMuscleGroupsCache.containsKey(exercise.id)) {
        final muscles = await widget.workoutState.getExerciseMuscleGroups(
          exercise.id,
        );
        _exerciseMuscleGroupsCache[exercise.id] = muscles;
      }
    }

    // Partition exercises into Recommended and Other based on relevance score
    _partitionExercises(results);

    if (mounted) {
      setState(() {
        _filteredExercises = results;
      });
    }
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _selectedDisciplineId = null;
      _selectedMuscleGroupId = null;
    });
    _searchExercises();
  }

  /// Partition exercises into Recommended and Other sections based on modality and score
  void _partitionExercises(List<Exercise> exercises) {
    // In Free Training mode (no modality) or if scores not available, don't partition
    if (widget.sessionModality == null) {
      _recommendedExercises = [];
      _otherExercises = [];
      return;
    }

    // Partition by relevance score threshold
    _recommendedExercises = exercises
        .where(
          (e) =>
              e.relevanceScore != null &&
              e.relevanceScore! >= RECOMMENDED_SCORE_THRESHOLD,
        )
        .toList();

    _otherExercises = exercises
        .where(
          (e) =>
              e.relevanceScore == null ||
              e.relevanceScore! < RECOMMENDED_SCORE_THRESHOLD,
        )
        .toList();
  }

  Future<void> _openCreateExercise() async {
    final created = await OmniNavigator.push<Exercise>(
      context,
      (_) => ExerciseEditorScreen(
        workoutState: widget.workoutState,
        contextModality: widget.sessionModality,
      ),
    );

    if (created == null) return;

    _exerciseMuscleGroupsCache.remove(created.id);
    _searchController.text = created.name;
    await _searchExercises();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeColors = OmniTheme.colorsForTheme(OmniTheme.activeTheme);
    final pickerTheme = theme.copyWith(
      colorScheme: theme.colorScheme.copyWith(
        primary: themeColors.primary,
        onPrimary: Colors.white,
        surface: themeColors.surface,
        onSurface: OmniTheme.textPrimary,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStatePropertyAll(themeColors.primary),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          minimumSize: const WidgetStatePropertyAll(
            Size.fromHeight(OmniTheme.buttonPrimaryHeight),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(OmniTheme.buttonBorderRadius),
            ),
          ),
        ),
      ),
    );

    return Theme(
      data: pickerTheme,
      child: MediaQuery.removeViewInsets(
        context: context,
        removeBottom: true,
        child: Dialog(
          backgroundColor: themeColors.surface,
          surfaceTintColor: Colors.transparent,
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: BoxDecoration(color: themeColors.surface),
            width: MediaQuery.of(context).size.width * 0.9,
            height: MediaQuery.of(context).size.height * 0.86,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Select Exercise',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _openCreateExercise,
                    icon: const Icon(Icons.add),
                    label: const Text('New Exercise'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.primary,
                      backgroundColor: Colors.transparent,
                      side: BorderSide(
                        color: theme.colorScheme.primary,
                        width: 1.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          OmniTheme.buttonUtilityRadius,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Search field
                TextField(
                  textCapitalization: TextCapitalization.none,
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search exercises...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              _searchExercises();
                            },
                          )
                        : null,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: themeColors.surfaceBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: theme.colorScheme.primary),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: themeColors.surfaceBorder),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Filter row
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedDisciplineId,
                        isExpanded: true,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: OmniTheme.textSecondary,
                        ),
                        decoration: InputDecoration(
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: themeColors.surfaceBorder,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: theme.colorScheme.primary,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          labelText: 'Discipline',
                          border: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: themeColors.surfaceBorder,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          isDense: true,
                        ),
                        items: [
                          DropdownMenuItem(
                            value: null,
                            child: Text(
                              'All',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: OmniTheme.textSecondary,
                              ),
                            ),
                          ),
                          ..._disciplines.map(
                            (d) => DropdownMenuItem(
                              value: d.id,
                              child: Text(
                                d.name,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: OmniTheme.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() => _selectedDisciplineId = value);
                          _searchExercises();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedMuscleGroupId,
                        isExpanded: true,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: OmniTheme.textSecondary,
                        ),
                        decoration: InputDecoration(
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: themeColors.surfaceBorder,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: theme.colorScheme.primary,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          labelText: 'Muscle',
                          border: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: themeColors.surfaceBorder,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          isDense: true,
                        ),
                        items: [
                          DropdownMenuItem(
                            value: null,
                            child: Text(
                              'All',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: OmniTheme.textSecondary,
                              ),
                            ),
                          ),
                          ..._muscleGroups.map(
                            (mg) => DropdownMenuItem(
                              value: mg.id,
                              child: Text(
                                mg.name,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: OmniTheme.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() => _selectedMuscleGroupId = value);
                          _searchExercises();
                        },
                      ),
                    ),
                  ],
                ),

                // Clear filters button (only show when filters are active)
                if (_selectedDisciplineId != null ||
                    _selectedMuscleGroupId != null ||
                    _searchController.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextButton.icon(
                      onPressed: _clearFilters,
                      style: TextButton.styleFrom(
                        foregroundColor: OmniTheme.textSecondary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            OmniTheme.buttonUtilityRadius,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.clear_all, size: 16),
                      label: const Text('Clear Filters'),
                    ),
                  ),

                const SizedBox(height: 16),

                // Results count
                Text(
                  '${_filteredExercises.length} exercise${_filteredExercises.length != 1 ? 's' : ''} found',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 8),

                // Exercise list
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _filteredExercises.isEmpty
                      ? LayoutBuilder(
                          builder: (context, constraints) {
                            return SingleChildScrollView(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: constraints.maxHeight,
                                ),
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.search_off,
                                        size: 64,
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: 0.3),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        'No exercises found',
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                              color: theme.colorScheme.onSurface
                                                  .withValues(alpha: 0.6),
                                            ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Try adjusting your filters',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: theme.colorScheme.onSurface
                                                  .withValues(alpha: 0.5),
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        )
                      : _buildExerciseList(theme),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExerciseList(ThemeData theme) {
    // In Free Training mode or when no modality, show simple unsorted list
    if (widget.sessionModality == null) {
      return ListView.builder(
        itemCount: _filteredExercises.length,
        itemBuilder: (context, index) {
          return _buildExerciseTile(context, theme, _filteredExercises[index]);
        },
      );
    }

    // With modality: build sectioned list with proper index handling
    final List<({String? headerTitle, Exercise? exercise})> listItems = [];

    // Add Recommended section if non-empty
    if (_recommendedExercises.isNotEmpty) {
      listItems.add((headerTitle: 'Recommended', exercise: null));
      for (final exercise in _recommendedExercises) {
        listItems.add((headerTitle: null, exercise: exercise));
      }
    }

    // Add Other section if non-empty
    if (_otherExercises.isNotEmpty) {
      listItems.add((headerTitle: 'Other', exercise: null));
      for (final exercise in _otherExercises) {
        listItems.add((headerTitle: null, exercise: exercise));
      }
    }

    if (listItems.isEmpty) {
      return const SizedBox.shrink();
    }

    return ListView.builder(
      itemCount: listItems.length,
      itemBuilder: (context, index) {
        final item = listItems[index];
        if (item.headerTitle != null) {
          return _buildSectionHeader(theme, item.headerTitle!);
        }
        return _buildExerciseTile(context, theme, item.exercise!);
      },
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: OmniTheme.textSecondary,
        ),
      ),
    );
  }

  Widget _buildExerciseTile(
    BuildContext context,
    ThemeData theme,
    Exercise exercise,
  ) {
    final themeColors = OmniTheme.colorsForTheme(OmniTheme.activeTheme);
    final muscleGroups = _exerciseMuscleGroupsCache[exercise.id] ?? [];
    final discipline = _disciplines.firstWhere(
      (d) => d.id == exercise.disciplineId,
      orElse: () => Discipline(
        id: '',
        categoryId: '',
        key: '',
        name: '',
        createdAtMs: 0,
        updatedAtMs: 0,
      ),
    );

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      title: Text(
        exercise.name,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: OmniTheme.textPrimary,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (exercise.description != null &&
              exercise.description!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              exercise.description!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: OmniTheme.textSecondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (discipline.name.isNotEmpty)
                Chip(
                  label: Text(
                    discipline.name,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: themeColors.textMuted,
                    ),
                  ),
                  backgroundColor: Colors.transparent,
                  side: BorderSide(color: themeColors.surfaceBorder),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ...muscleGroups.map(
                (mg) => Chip(
                  label: Text(
                    mg.name,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: themeColors.textMuted,
                    ),
                  ),
                  backgroundColor: Colors.transparent,
                  side: BorderSide(color: themeColors.surfaceBorder),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ],
      ),
      onTap: () => Navigator.of(context).pop(exercise),
    );
  }
}
