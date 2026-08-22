// PR 8 — Exercise Library Detail Screen
//
// Management surface for a single exercise. Opens via the library's
// row tap.
//
// Layout: Renders `ExerciseDetailViewBody` (read-only metadata) and
// `_ManagementActionBar` (action buttons) in a single-padded Column
// (padding via ExerciseDetailViewBody.contentPadding).
//
// Differences from the read-only viewer:
//   - Built-in rows surface a `Copy` action (key
//     `exercise_library_copy_button`).
//   - Custom rows surface `Edit` (key `exercise_library_edit_button`)
//     and `Remove` (key `exercise_library_remove_button`).
//   - Built-in rows do NOT expose Edit or Remove. Every action button
//     is gated on `Exercise.isCustomExercise`; the underlying service
//     also rejects built-in mutations via `BuiltInExerciseImmutableError`.
//
// This screen never offers an "Add to Workout" action. The library is
// a management surface, not a workout-entry surface.

import 'package:flutter/material.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/core/services/exercise_library_service.dart';
import 'package:omnitrain/core/utils/exercise_helpers.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/state/exercise/exercise_library_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/layout/omni_back_header.dart';

import 'exercise_detail_view_screen.dart';
import '../../widgets/dialogs/confirmation_dialog.dart';

class ExerciseLibraryDetailScreen extends StatefulWidget {
  final Exercise exercise;
  final ExerciseLibraryState libraryState;
  final WorkoutState workoutState;

  const ExerciseLibraryDetailScreen({
    super.key,
    required this.exercise,
    required this.libraryState,
    required this.workoutState,
  });

  @override
  State<ExerciseLibraryDetailScreen> createState() =>
      _ExerciseLibraryDetailScreenState();
}

class _ExerciseLibraryDetailScreenState
    extends State<ExerciseLibraryDetailScreen> {
  List<Discipline> _disciplines = const [];
  List<MuscleGroup> _muscleGroupsForExercise = const [];

  Exercise get exercise => widget.exercise;
  ExerciseLibraryState get libraryState => widget.libraryState;
  WorkoutState get workoutState => widget.workoutState;

  @override
  void initState() {
    super.initState();
    _loadReference();
  }

  Future<void> _loadReference() async {
    if (workoutState.muscleGroups.isEmpty) {
      await workoutState.loadMuscleGroups();
    }
    if (workoutState.disciplines.isEmpty) {
      await workoutState.loadDisciplines();
    }
    final muscles = await workoutState.getExerciseMuscleGroups(exercise.id);
    if (!mounted) return;
    setState(() {
      _disciplines = workoutState.disciplines;
      _muscleGroupsForExercise = muscles;
    });
  }

  Discipline? _resolveDiscipline(String? id) {
    if (id == null) return null;
    for (final d in _disciplines) {
      if (d.id == id) return d;
    }
    return null;
  }

  Future<void> _onCopy(BuildContext context) async {
    try {
      final created = await libraryState.copyAsCustom(exercise);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Copied as "${created.name}"')));
      Navigator.of(context).pop();
    } on BuiltInExerciseImmutableError {
      // Defensive — UI prevents this path.
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Built-in exercises cannot be copied.')),
      );
    }
  }

  Future<void> _onEdit(BuildContext context) async {
    // PR 8 reuses the PR 7 read-only details surface for inspection;
    // edit body lives behind the editor screen via the existing
    // ExerciseEditorScreen in edit mode. We surface a future
    // rename-flow via the library service directly here so the
    // edit action does not require a full editor round-trip.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (!context.mounted) return;
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => _RenameDialog(initialName: exercise.name),
    );
    if (newName == null || newName.trim().isEmpty) return;
    try {
      await libraryState.renameCustom(exercise: exercise, newName: newName);
      navigator.pop();
    } on BuiltInExerciseImmutableError {
      messenger.showSnackBar(
        const SnackBar(content: Text('Built-in exercises cannot be renamed.')),
      );
    }
  }

  Future<void> _onRemove(BuildContext context) async {
    // Capture navigator + messenger before the await so we can use
    // them safely after `planRemoval` resolves.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final plan = await libraryState.service.planRemoval(exercise.id);
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _RemoveDialog(plan: plan),
    );
    if (confirmed != true) return;
    try {
      await libraryState.removeExercise(exercise);
      navigator.pop();
    } on BuiltInExerciseImmutableError {
      messenger.showSnackBar(
        const SnackBar(content: Text('Built-in exercises cannot be removed.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCustom = exercise.isCustomExercise;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: OmniBackHeader(
        title: isCustom ? 'Custom Exercise' : 'Built-in Exercise',
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: libraryState,
          builder: (context, _) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Render the PR 7 read-only surface body content
                  // directly — no nested Scaffold / app bar.
                  ExerciseDetailViewBody(
                    key: const Key('exercise_library_detail_metadata'),
                    exercise: exercise,
                    discipline: _resolveDiscipline(exercise.disciplineId),
                    muscleGroups: _muscleGroupsForExercise,
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 24),
                  // Management action bar lives inside the scrolling
                  // column so the user never loses it behind a long
                  // body, regardless of device size.
                  _ManagementActionBar(
                    isCustom: isCustom,
                    onCopy: () => _onCopy(context),
                    onEdit: () => _onEdit(context),
                    onRemove: () => _onRemove(context),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ManagementActionBar extends StatelessWidget {
  final bool isCustom;
  final VoidCallback onCopy;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  const _ManagementActionBar({
    required this.isCustom,
    required this.onCopy,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (isCustom) {
      return Row(
        key: const Key('exercise_library_action_bar'),
        children: [
          Expanded(
            child: OutlinedButton.icon(
              key: const Key('exercise_library_edit_button'),
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit'),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
                side: BorderSide(color: theme.colorScheme.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    OmniTheme.buttonUtilityRadius,
                  ),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              key: const Key('exercise_library_remove_button'),
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Remove'),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
                side: BorderSide(color: theme.colorScheme.error),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    OmniTheme.buttonUtilityRadius,
                  ),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      );
    }

    return SizedBox(
      key: const Key('exercise_library_action_bar'),
      width: double.infinity,
      child: OutlinedButton.icon(
        key: const Key('exercise_library_copy_button'),
        onPressed: onCopy,
        icon: const Icon(Icons.copy_all_outlined, size: 18),
        label: const Text('Make a copy'),
        style: OutlinedButton.styleFrom(
          foregroundColor: theme.colorScheme.primary,
          side: BorderSide(color: theme.colorScheme.primary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(OmniTheme.buttonUtilityRadius),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  final String initialName;
  const _RenameDialog({required this.initialName});

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Rename exercise'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'New name',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                OmniTheme.buttonUtilityRadius,
              ),
            ),
          ),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final value = _controller.text.trim();
            if (value.isEmpty) return;
            Navigator.pop(context, value);
          },
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                OmniTheme.buttonUtilityRadius,
              ),
            ),
          ),
          child: Text(
            'Save',
            style: TextStyle(color: theme.colorScheme.onPrimary),
          ),
        ),
      ],
    );
  }
}

class _RemoveDialog extends StatelessWidget {
  final ExerciseRemovalPlan plan;
  const _RemoveDialog({required this.plan});

  @override
  Widget build(BuildContext context) {
    final hasRefs = plan.totalReferences > 0;
    final explanation = hasRefs
        ? 'This exercise is referenced in ${plan.totalReferences} place'
              '${plan.totalReferences == 1 ? '' : 's'}. '
              'Removing it will retire the row so it disappears from '
              'pickers and routine templates, but historical session '
              'values stay resolvable.'
        : 'This custom exercise is not used in any active session or '
              'routine. Removing it will delete the row permanently.';

    return ConfirmationDialog.twoChoice(
      title: 'Remove exercise?',
      body: Text(explanation),
      dismissLabel: 'Cancel',
      confirmLabel: hasRefs ? 'Retire' : 'Delete',
      dismissKey: const Key('exercise_library_remove_cancel_button'),
      confirmKey: const Key('exercise_library_remove_confirm_button'),
      isDestructive: true,
    );
  }
}
