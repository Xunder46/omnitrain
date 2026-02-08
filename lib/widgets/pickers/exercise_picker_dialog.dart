import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/models/models.dart';
import '../../state/workout/workout_state.dart';

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
  List<MuscleGroup> _muscleGroups = [];
  List<Discipline> _disciplines = [];
  Map<String, List<MuscleGroup>> _exerciseMuscleGroupsCache = {};

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

    setState(() => _isLoading = false);
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _searchExercises();
    });
  }

  Future<void> _searchExercises() async {
    final searchText = _searchController.text.trim();
    final muscleGroupIds = _selectedMuscleGroupId != null ? [_selectedMuscleGroupId!] : null;

    final results = await widget.workoutState.getExercisesRankedForModality(
      searchText: searchText.isEmpty ? null : searchText,
      disciplineId: _selectedDisciplineId,
      muscleGroupIds: muscleGroupIds,
    );

    // Load muscle groups for each exercise for display
    for (final exercise in results) {
      if (!_exerciseMuscleGroupsCache.containsKey(exercise.id)) {
        final muscles = await widget.workoutState.getExerciseMuscleGroups(exercise.id);
        _exerciseMuscleGroupsCache[exercise.id] = muscles;
      }
    }

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
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
            const SizedBox(height: 16),

            // Search field
            TextField(
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
            const SizedBox(height: 12),

            // Filter row
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedDisciplineId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Discipline',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All')),
                      ..._disciplines.map((d) => DropdownMenuItem(
                            value: d.id,
                            child: Text(
                              d.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          )),
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
                    value: _selectedMuscleGroupId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Muscle',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All')),
                      ..._muscleGroups.map((mg) => DropdownMenuItem(
                            value: mg.id,
                            child: Text(
                              mg.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          )),
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
            if (_selectedDisciplineId != null || _selectedMuscleGroupId != null || _searchController.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.clear_all, size: 16),
                  label: const Text('Clear Filters'),
                ),
              ),

            const SizedBox(height: 16),

            // Results count
            Text(
              '${_filteredExercises.length} exercise${_filteredExercises.length != 1 ? 's' : ''} found',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 8),

            // Exercise list
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredExercises.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search_off,
                                size: 64,
                                color: theme.colorScheme.onSurface.withOpacity(0.3),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No exercises found',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Try adjusting your filters',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                                ),
                              ),
                            ],
                          ),
                        )
                      : _buildExerciseList(theme),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic>? _getModalityConfig(String modality) {
    const configs = {
      'cardio_endurance': {'primaryMetric': 'time'},
      'resistance_lifting': {'primaryMetric': 'reps'},
      'martial_arts': {'primaryMetric': 'time'},
      'isometric_stretching': {'primaryMetric': 'hold'},
      'sports': {'primaryMetric': 'time'},
    };
    return configs[modality];
  }

  Widget _buildExerciseList(ThemeData theme) {
    // Determine if we need section headers (when modality is set)
    final hasModality = widget.sessionModality != null;
    final modalityConfig = hasModality ? _getModalityConfig(widget.sessionModality!) : null;
    final primaryMetric = modalityConfig?['primaryMetric'] as String?;

    // Split into recommended and other if modality is set
    final recommended = <Exercise>[];
    final others = <Exercise>[];

    if (hasModality && primaryMetric != null) {
      for (final exercise in _filteredExercises) {
        if (exercise.supports(primaryMetric)) {
          recommended.add(exercise);
        } else {
          others.add(exercise);
        }
      }
    } else {
      // No modality - all exercises in one group
      recommended.addAll(_filteredExercises);
    }

    return ListView.builder(
      itemCount: _calculateItemCount(recommended.length, others.length, hasModality && primaryMetric != null),
      itemBuilder: (context, index) {
        return _buildListItem(context, theme, index, recommended, others, hasModality && primaryMetric != null);
      },
    );
  }

  int _calculateItemCount(int recommendedCount, int othersCount, bool hasSections) {
    if (!hasSections) return recommendedCount;
    // Headers + exercises
    int count = 0;
    if (recommendedCount > 0) count += 1 + recommendedCount; // Header + exercises
    if (othersCount > 0) count += 1 + othersCount; // Header + exercises
    return count;
  }

  Widget _buildListItem(BuildContext context, ThemeData theme, int index, 
      List<Exercise> recommended, List<Exercise> others, bool hasSections) {
    if (!hasSections) {
      // No sections - simple list
      return _buildExerciseTile(context, theme, recommended[index]);
    }

    // With sections
    if (recommended.isNotEmpty) {
      if (index == 0) {
        return _buildSectionHeader(theme, 'Recommended for this workout', Icons.star, theme.colorScheme.primary);
      }
      if (index <= recommended.length) {
        return _buildExerciseTile(context, theme, recommended[index - 1]);
      }
      // Adjust index for "others" section
      final othersIndex = index - recommended.length - 1;
      if (othersIndex == 0 && others.isNotEmpty) {
        return _buildSectionHeader(theme, 'Other exercises', Icons.fitness_center, theme.colorScheme.onSurface.withOpacity(0.6));
      }
      if (othersIndex > 0 && othersIndex <= others.length) {
        return _buildExerciseTile(context, theme, others[othersIndex - 1]);
      }
    } else if (others.isNotEmpty) {
      // Only "others" section
      if (index == 0) {
        return _buildSectionHeader(theme, 'All exercises', Icons.fitness_center, theme.colorScheme.onSurface.withOpacity(0.6));
      }
      return _buildExerciseTile(context, theme, others[index - 1]);
    }

    return const SizedBox.shrink();
  }

  Widget _buildSectionHeader(ThemeData theme, String title, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExerciseTile(BuildContext context, ThemeData theme, Exercise exercise) {
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
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (exercise.description != null && exercise.description!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              exercise.description!,
              style: theme.textTheme.bodySmall,
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
                    style: theme.textTheme.labelSmall,
                  ),
                  backgroundColor: theme.colorScheme.primaryContainer,
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ...muscleGroups.map((mg) => Chip(
                    label: Text(
                      mg.name,
                      style: theme.textTheme.labelSmall,
                    ),
                    backgroundColor: theme.colorScheme.secondaryContainer,
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  )),
            ],
          ),
        ],
      ),
      onTap: () => Navigator.of(context).pop(exercise),
    );
  }
}
