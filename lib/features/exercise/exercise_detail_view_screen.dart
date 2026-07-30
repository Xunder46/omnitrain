// PR 7 — Exercise Details View (read-only).
//
// A reusable surface that shows a single exercise's reference data:
// name, optional description, discipline, capabilities, and muscles.
// Reused by:
//   - `ExercisePickerScreen` (tap the per-row details control)
//   - PR 8 (Exercise Library)
//
// This widget is deliberately display-only. It never mutates the
// repository and never owns business logic — the picker is responsible
// for converting the user's "Add" tap into the existing add-to-session
// flow. The single Add action here returns the [Exercise] to its caller
// via `Navigator.pop` exactly once, with rapid-tap idempotency enforced
// by a private boolean guard.

import 'package:flutter/material.dart';
import 'package:omnitrain/core/constants/capability.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/core/utils/exercise_helpers.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/layout/omni_back_header.dart';
import 'package:omnitrain/widgets/layout/omni_surface.dart';

/// Read-only details view for a single [Exercise].
///
/// Pushed via [OmniNavigator.push] from the picker. Returns `null` on
/// back, or the [Exercise] when the user taps Add. Rapid taps on Add
/// are de-duplicated — only one pop reaches the caller.
class ExerciseDetailViewScreen extends StatefulWidget {
  /// The exercise being inspected. May be bundled or custom.
  final Exercise exercise;

  /// Read-only state owner. Used to resolve discipline + muscle group
  /// display data; the screen never writes through it.
  final WorkoutState workoutState;

  /// Optional override for the title in the AppBar. Defaults to
  /// "Exercise Details".
  final String? title;

  /// When true, the Add action is hidden. PR 8 reuses the surface in
  /// management contexts where adding to a session is not relevant.
  final bool showAddAction;

  const ExerciseDetailViewScreen({
    super.key,
    required this.exercise,
    required this.workoutState,
    this.title,
    this.showAddAction = true,
  });

  @override
  State<ExerciseDetailViewScreen> createState() =>
      _ExerciseDetailViewScreenState();
}

class _ExerciseDetailViewScreenState extends State<ExerciseDetailViewScreen> {
  bool _hasPoppedWithAdd = false;

  List<Discipline> _disciplines = const [];
  List<MuscleGroup> _muscleGroupsForExercise = const [];

  @override
  void initState() {
    super.initState();
    _loadReference();
  }

  Future<void> _loadReference() async {
    if (widget.workoutState.disciplines.isEmpty) {
      await widget.workoutState.loadDisciplines();
    }
    if (widget.workoutState.muscleGroups.isEmpty) {
      await widget.workoutState.loadMuscleGroups();
    }
    final muscles = await widget.workoutState.getExerciseMuscleGroups(
      widget.exercise.id,
    );
    if (!mounted) return;
    setState(() {
      _disciplines = widget.workoutState.disciplines;
      _muscleGroupsForExercise = muscles;
    });
  }

  void _onAddPressed() {
    // Idempotency guard: rapid taps on the Add button must pop exactly
    // once. Subsequent taps are no-ops until the screen unmounts.
    if (_hasPoppedWithAdd) return;
    _hasPoppedWithAdd = true;
    Navigator.of(context).pop(widget.exercise);
  }

  Discipline? _resolveDiscipline(String? id) {
    if (id == null) return null;
    for (final d in _disciplines) {
      if (d.id == id) return d;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final exercise = widget.exercise;
    final discipline = _resolveDiscipline(exercise.disciplineId);
    final muscleGroups = _muscleGroupsForExercise;
    final hasDescription =
        exercise.description != null && exercise.description!.trim().isNotEmpty;
    final hasDiscipline = discipline != null;
    final hasCapabilities = exercise.capabilities.isNotEmpty;
    final hasMuscles = muscleGroups.isNotEmpty;
    final isCustom = exercise.isCustomExercise;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: OmniBackHeader(title: widget.title ?? 'Exercise Details'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title row + optional custom marker.
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      exercise.name,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: OmniTheme.colors.textDominant,
                      ),
                    ),
                  ),
                  if (isCustom)
                    Container(
                      key: const Key('exercise_detail_custom_marker'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.15,
                        ),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.5,
                          ),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        'Custom',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // Description (collapsed when absent).
              if (hasDescription)
                OmniSurface(
                  key: const Key('exercise_detail_description_section'),
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    exercise.description!.trim(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: OmniTheme.colors.textDominant,
                      height: 1.4,
                    ),
                  ),
                ),
              if (hasDescription) const SizedBox(height: 16),

              // Discipline (collapsed when absent).
              if (hasDiscipline)
                _DetailRow(
                  key: const Key('exercise_detail_discipline_section'),
                  label: 'Discipline',
                  child: _MetaChip(label: discipline.name),
                ),
              if (hasDiscipline) const SizedBox(height: 12),

              // Tracking methods = capabilities.
              if (hasCapabilities)
                _DetailRow(
                  key: const Key('exercise_detail_capabilities_section'),
                  label: 'Tracking Methods',
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final cap in exercise.capabilities)
                        _MetaChip(
                          label: ExerciseCapability.getDisplayName(cap),
                        ),
                    ],
                  ),
                ),
              if (hasCapabilities) const SizedBox(height: 12),

              // Muscles (collapsed when absent).
              if (hasMuscles)
                _DetailRow(
                  key: const Key('exercise_detail_muscles_section'),
                  label: 'Muscles',
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final mg in muscleGroups) _MetaChip(label: mg.name),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: widget.showAddAction
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  height: OmniTheme.buttonPrimaryHeight,
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('exercise_detail_add_button'),
                    onPressed: _onAddPressed,
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          OmniTheme.buttonBorderRadius,
                        ),
                      ),
                    ),
                    child: const Text('Add'),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final Widget child;

  const _DetailRow({super.key, required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: OmniTheme.colors.textSecondary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  const _MetaChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeColors = OmniTheme.colorsForTheme(OmniTheme.activeTheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: themeColors.surfaceBorder),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: OmniTheme.colors.textSecondary,
        ),
      ),
    );
  }
}
