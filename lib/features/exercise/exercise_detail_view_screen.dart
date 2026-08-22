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
//
// The body content is exposed separately as `ExerciseDetailViewBody`
// so other screens (e.g. `ExerciseLibraryDetailScreen`) can reuse it
// without nesting a second `Scaffold` / `OmniBackHeader`.

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
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: OmniBackHeader(title: widget.title ?? 'Exercise Details'),
      body: SafeArea(
        child: ExerciseDetailViewBody(
          exercise: widget.exercise,
          discipline: _resolveDiscipline(widget.exercise.disciplineId),
          muscleGroups: _muscleGroupsForExercise,
        ),
      ),
      bottomNavigationBar: widget.showAddAction
          ? _ExerciseDetailAddBar(onPressed: _onAddPressed)
          : null,
    );
  }
}

/// Body content of the read-only details surface — name, optional
/// description, discipline, capabilities, muscles. Renders inside a
/// `SingleChildScrollView` so a long body scrolls cleanly. Has no
/// `Scaffold` / `OmniBackHeader`; the owning screen provides those.
///
/// Reused by:
///   - `ExerciseDetailViewScreen` (full screen with app bar + Add button)
///   - `ExerciseLibraryDetailScreen` (library management surface; the
///     library supplies its own app bar and management action bar).
class ExerciseDetailViewBody extends StatelessWidget {
  /// Capabilities that describe how a user records what they did —
  /// the things the workout screen asks for via metric editors. These
  /// are the only chips that belong under "Tracking Methods".
  static const Set<String> _trackingCapabilities = {
    ExerciseCapability.time,
    ExerciseCapability.hold,
    ExerciseCapability.reps,
    ExerciseCapability.sets,
    ExerciseCapability.load,
    ExerciseCapability.distance,
    ExerciseCapability.rounds,
  };

  /// Capabilities that describe how the movement is performed rather
  /// than how it is measured. They are shown to the user, but under
  /// "Movement Properties", not "Tracking Methods" — telling someone
  /// they can "track by bilateral" is meaningless because bilateral
  /// describes the limb pairing, not a measurement.
  static const Set<String> _movementCapabilities = {
    ExerciseCapability.bilateral,
  };

  final Exercise exercise;
  final Discipline? discipline;
  final List<MuscleGroup> muscleGroups;

  /// Padding for content inside the scrollable body.
  /// Defaults to `EdgeInsets.fromLTRB(16, 16, 16, 24)` to preserve the
  /// previous hardcoded padding, but can be overridden for contexts
  /// (like library detail screen) that manage padding externally.
  final EdgeInsets contentPadding;

  const ExerciseDetailViewBody({
    super.key,
    required this.exercise,
    required this.discipline,
    required this.muscleGroups,
    this.contentPadding = const EdgeInsets.fromLTRB(16, 16, 16, 24),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDescription =
        exercise.description != null && exercise.description!.trim().isNotEmpty;
    final hasDiscipline = discipline != null;
    final trackingCaps = exercise.capabilities
        .where(_trackingCapabilities.contains)
        .toList();
    final movementCaps = exercise.capabilities
        .where(_movementCapabilities.contains)
        .toList();
    final hasTracking = trackingCaps.isNotEmpty;
    final hasMovement = movementCaps.isNotEmpty;
    final hasMuscles = muscleGroups.isNotEmpty;
    final isCustom = exercise.isCustomExercise;

    return SingleChildScrollView(
      padding: contentPadding,
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
              child: _MetaChip(label: discipline!.name),
            ),
          if (hasDiscipline) const SizedBox(height: 12),

          // Tracking Methods — only chips that describe how the
          // exercise is measured. Movement properties (e.g. bilateral)
          // do NOT appear here; they are shown in the section below.
          if (hasTracking)
            _DetailRow(
              key: const Key('exercise_detail_capabilities_section'),
              label: 'Tracking Methods',
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final cap in trackingCaps)
                    _MetaChip(label: ExerciseCapability.getDisplayName(cap)),
                ],
              ),
            ),
          if (hasTracking) const SizedBox(height: 12),

          // Movement Properties — chips that describe how the movement
          // is performed (e.g. bilateral). Rendered under its own
          // heading so the user can distinguish measurement methods
          // from movement characteristics. Omitted when the exercise
          // has no movement-property capabilities.
          if (hasMovement)
            _DetailRow(
              key: const Key('exercise_detail_movement_section'),
              label: 'Movement Properties',
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final cap in movementCaps)
                    _MetaChip(label: ExerciseCapability.getDisplayName(cap)),
                ],
              ),
            ),
          if (hasMovement) const SizedBox(height: 12),

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
    );
  }
}

/// Bottom navigation bar for `ExerciseDetailViewScreen` that hosts
/// the Add action. Extracted as a small widget so the screen can
/// stay focused on app-bar / body / action-bar composition.
class _ExerciseDetailAddBar extends StatelessWidget {
  final VoidCallback onPressed;
  const _ExerciseDetailAddBar({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SizedBox(
          height: OmniTheme.buttonPrimaryHeight,
          width: double.infinity,
          child: FilledButton(
            key: const Key('exercise_detail_add_button'),
            onPressed: onPressed,
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
