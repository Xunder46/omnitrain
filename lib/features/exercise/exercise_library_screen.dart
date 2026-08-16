// PR 8 — Exercise Library Screen
//
// Full-screen management surface for the user's exercise catalog.
// Opened via the wired maintenance-sheet `Exercise Library` tile
// (NOT the home tile grid).
//
// Differences from ExercisePickerScreen:
//   - No "Add to workout" action (rows never pop a selected exercise).
//   - "Custom only" toggle (key `exercise_library_custom_only_toggle`).
//   - Tap a row to open the management details surface
//     (ExerciseLibraryDetailScreen), which exposes Copy / Edit / Remove.
//
// The details affordance from PR 7 (`exercise_row_details_button`) is
// reused — tapping it opens `ExerciseDetailViewScreen` (read-only,
// with the Add action suppressed) so the user can re-inspect the
// metadata without committing to anything.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/core/navigation/navigation.dart';
import 'package:omnitrain/core/utils/exercise_helpers.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/state/exercise/exercise_library_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/layout/omni_back_header.dart';

import 'exercise_detail_view_screen.dart';
import 'exercise_library_detail_screen.dart';

class ExerciseLibraryScreen extends StatefulWidget {
  final ExerciseLibraryState exerciseLibraryState;
  final WorkoutState workoutState;

  const ExerciseLibraryScreen({
    super.key,
    required this.exerciseLibraryState,
    required this.workoutState,
  });

  @override
  State<ExerciseLibraryScreen> createState() => _ExerciseLibraryScreenState();
}

class _ExerciseLibraryScreenState extends State<ExerciseLibraryScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  List<Discipline> _disciplines = const [];
  final Map<String, List<MuscleGroup>> _exerciseMuscleGroupsCache = {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await widget.exerciseLibraryState.reload();
    await _loadReference();
    if (mounted) {
      await _warmCache(widget.exerciseLibraryState.exercises);
    }
  }

  Future<void> _loadReference() async {
    if (widget.workoutState.muscleGroups.isEmpty) {
      await widget.workoutState.loadMuscleGroups();
    }
    if (widget.workoutState.disciplines.isEmpty) {
      await widget.workoutState.loadDisciplines();
    }
    if (!mounted) return;
    setState(() {
      _disciplines = widget.workoutState.disciplines;
    });
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      widget.exerciseLibraryState.setSearchText(_searchController.text);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.exerciseLibraryState,
      builder: (context, _) {
        final theme = Theme.of(context);
        final themeColors = OmniTheme.colorsForTheme(OmniTheme.activeTheme);
        final state = widget.exerciseLibraryState;
        final exercises = state.exercises;

        return Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: true,
          appBar: const OmniBackHeader(title: 'Exercise Library'),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    key: const Key('exercise_library_search_field'),
                    controller: _searchController,
                    textCapitalization: TextCapitalization.none,
                    decoration: InputDecoration(
                      hintText: 'Search exercises...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                widget.exerciseLibraryState.setSearchText(null);
                              },
                            )
                          : null,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: themeColors.surfaceBorder,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: themeColors.surfaceBorder,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    key: const Key('exercise_library_custom_only_toggle'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Custom only',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: OmniTheme.colors.textDominant,
                      ),
                    ),
                    subtitle: Text(
                      'Show user-created exercises only',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: OmniTheme.colors.textSecondary,
                      ),
                    ),
                    value: state.customOnly,
                    onChanged: state.setCustomOnly,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${exercises.length} exercise${exercises.length != 1 ? 's' : ''} found',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: state.isLoading && exercises.isEmpty
                        ? const Center(child: CircularProgressIndicator())
                        : exercises.isEmpty
                        ? const _EmptyState()
                        : ListView.builder(
                            itemCount: exercises.length,
                            itemBuilder: (context, index) =>
                                _buildRow(context, theme, exercises[index]),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRow(BuildContext context, ThemeData theme, Exercise exercise) {
    final muscleGroups = _exerciseMuscleGroupsCache[exercise.id] ?? const [];
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
      // rows whose chip Wrap expands the row. See the picker for the
      // rationale.
      titleAlignment: ListTileTitleAlignment.top,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
      subtitle: (discipline.name.isEmpty && muscleGroups.isEmpty)
          ? null
          : SizedBox(
              // Force the chip Wrap to use the full subtitle column
              // width instead of computing an intrinsic width that
              // would cause earlier wrapping. See the picker for the
              // rationale.
              width: double.infinity,
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (discipline.name.isNotEmpty)
                    _TagChip(label: discipline.name),
                  ...muscleGroups.map((mg) => _TagChip(label: mg.name)),
                ],
              ),
            ),
      trailing: IconButton(
        key: const Key('exercise_row_details_button'),
        icon: Icon(
          Icons.info_outline,
          color: theme.colorScheme.primary,
          size: 20,
        ),
        tooltip: 'View exercise details',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(
          width: 44,
          height: 44,
        ),
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              OmniTheme.buttonIconRadius,
            ),
          ),
        ),
        onPressed: () => _openReadOnlyDetails(exercise),
      ),
      onTap: () => _openManagementDetails(exercise),
    );
  }

  Future<void> _openReadOnlyDetails(Exercise exercise) async {
    await OmniNavigator.push<Exercise>(
      context,
      (_) => ExerciseDetailViewScreen(
        workoutState: widget.workoutState,
        exercise: exercise,
        title: 'Exercise Details',
        showAddAction: false,
      ),
    );
  }

  Future<void> _openManagementDetails(Exercise exercise) async {
    await OmniNavigator.push<void>(
      context,
      (_) => ExerciseLibraryDetailScreen(
        exercise: exercise,
        libraryState: widget.exerciseLibraryState,
        workoutState: widget.workoutState,
      ),
    );
    if (mounted) {
      await widget.exerciseLibraryState.reload();
      await _warmCache(widget.exerciseLibraryState.exercises);
    }
  }

  Future<void> _warmCache(List<Exercise> exercises) async {
    for (final exercise in exercises) {
      if (_exerciseMuscleGroupsCache.containsKey(exercise.id)) continue;
      final muscles = await widget.workoutState.getExerciseMuscleGroups(
        exercise.id,
      );
      if (!mounted) return;
      setState(() {
        _exerciseMuscleGroupsCache[exercise.id] = muscles;
      });
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.fitness_center_outlined,
                    size: 64,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No exercises found',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Adjust your search or clear filters.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  const _TagChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeColors = OmniTheme.colorsForTheme(OmniTheme.activeTheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: themeColors.surfaceBorder),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: themeColors.textMuted,
        ),
      ),
    );
  }
}
