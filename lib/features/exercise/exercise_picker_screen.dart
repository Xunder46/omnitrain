import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';
import '../../core/utils/exercise_helpers.dart';
import '../../data/models/models.dart';
import '../../state/workout/workout_state.dart';
import '../../features/exercise/exercise_detail_view_screen.dart';
import '../../features/exercise/exercise_editor_screen.dart';
import '../../core/constants/modality_config.dart';
import '../../core/navigation/navigation.dart';
import '../../widgets/layout/omni_back_header.dart';

/// Full-screen page for selecting an exercise with search and filters.
///
/// Replaces the former [ExercisePickerDialog]. All search, ranking,
/// create-new, and exercise-return behaviour is preserved exactly.
/// Use [OmniNavigator.push<Exercise>] to open and await the result.
class ExercisePickerScreen extends StatefulWidget {
  final WorkoutState workoutState;
  final String? sessionModality;

  const ExercisePickerScreen({
    super.key,
    required this.workoutState,
    this.sessionModality,
  });

  @override
  State<ExercisePickerScreen> createState() => _ExercisePickerScreenState();
}

class _ExercisePickerScreenState extends State<ExercisePickerScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  List<Exercise> _filteredExercises = [];
  List<Exercise> _recommendedExercises = [];
  List<Exercise> _otherExercises = [];
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
  void didUpdateWidget(ExercisePickerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.sessionModality != widget.sessionModality) {
      _exerciseMuscleGroupsCache.clear();
      setState(() {
        _selectedDisciplineId = null;
        _selectedMuscleGroupId = null;
        _filteredExercises = [];
      });
      _searchController.clear();
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

    if (widget.workoutState.muscleGroups.isEmpty) {
      await widget.workoutState.loadMuscleGroups();
    }
    if (widget.workoutState.disciplines.isEmpty) {
      await widget.workoutState.loadDisciplines();
    }

    _muscleGroups = widget.workoutState.muscleGroups;
    _disciplines = widget.workoutState.disciplines;

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
      modality: widget.sessionModality,
      searchText: searchText.isEmpty ? null : searchText,
      disciplineId: _selectedDisciplineId,
      muscleGroupIds: muscleGroupIds,
    );

    for (final exercise in results) {
      if (!_exerciseMuscleGroupsCache.containsKey(exercise.id)) {
        final muscles = await widget.workoutState.getExerciseMuscleGroups(
          exercise.id,
        );
        _exerciseMuscleGroupsCache[exercise.id] = muscles;
      }
    }

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

  void _partitionExercises(List<Exercise> exercises) {
    if (widget.sessionModality == null) {
      _recommendedExercises = [];
      _otherExercises = [];
      return;
    }

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

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: const OmniBackHeader(title: 'Select Exercise'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // New Exercise button
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
                        color: OmniTheme.colors.textSecondary,
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
                              color: OmniTheme.colors.textSecondary,
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
                                color: OmniTheme.colors.textSecondary,
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
                        color: OmniTheme.colors.textSecondary,
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
                              color: OmniTheme.colors.textSecondary,
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
                                color: OmniTheme.colors.textSecondary,
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
                      foregroundColor: OmniTheme.colors.textSecondary,
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
    );
  }

  Widget _buildExerciseList(ThemeData theme) {
    if (widget.sessionModality == null) {
      return ListView.builder(
        itemCount: _filteredExercises.length,
        itemBuilder: (context, index) {
          return _buildExerciseTile(context, theme, _filteredExercises[index]);
        },
      );
    }

    final List<({String? headerTitle, Exercise? exercise})> listItems = [];

    if (_recommendedExercises.isNotEmpty) {
      listItems.add((headerTitle: 'Recommended', exercise: null));
      for (final exercise in _recommendedExercises) {
        listItems.add((headerTitle: null, exercise: exercise));
      }
    }

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
          color: OmniTheme.colors.textSecondary,
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
      // titleAlignment.top anchors the leading + trailing widgets to the
      // top of the row instead of vertically centering them. Without
      // this, the info control floats in the middle of empty space on
      // rows whose chip Wrap expands the row to two lines. The title and
      // subtitle positions are computed independently of titleAlignment
      // so this change does not affect the title-line baseline.
      titleAlignment: ListTileTitleAlignment.top,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              exercise.name,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: OmniTheme.colors.textDominant,
              ),
            ),
          ),
          if (exercise.isCustomExercise)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Container(
                key: const Key('exercise_row_custom_marker'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
                child: Text(
                  'Custom',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 10,
                  ),
                ),
              ),
            ),
        ],
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
                color: OmniTheme.colors.textSecondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 8),
          // Wrap in SizedBox(width: double.infinity) so the chip Wrap
          // uses the full subtitle column width (otherwise it computes
          // an intrinsic width and wraps earlier than the available
          // budget would allow).
          SizedBox(
            width: double.infinity,
            child: Wrap(
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
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: const Key('exercise_row_details_button'),
            icon: Icon(
              Icons.info_outline,
              color: theme.colorScheme.primary,
              size: 20,
            ),
            tooltip: 'View exercise details',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 44, height: 44),
            style: IconButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(OmniTheme.buttonIconRadius),
              ),
            ),
            onPressed: () => _openDetails(context, exercise),
          ),
        ],
      ),
      onTap: () => Navigator.of(context).pop(exercise),
    );
  }

  Future<void> _openDetails(BuildContext context, Exercise exercise) async {
    // Capture the navigator now so we can pop the picker from outside the
    // async gap. Using the captured reference avoids the
    // use_build_context_synchronously lint that fires on `context` after an
    // `await`.
    final pickerNavigator = Navigator.of(context);
    final result = await OmniNavigator.push<Exercise>(
      context,
      (_) => ExerciseDetailViewScreen(
        workoutState: widget.workoutState,
        exercise: exercise,
      ),
    );
    if (result == null) return;
    // Hand the chosen exercise back to the picker caller (same contract
    // as the row-body tap). Returning null is equivalent to a back press.
    if (!mounted) return;
    pickerNavigator.pop(result);
  }
}
