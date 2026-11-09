import 'package:flutter/material.dart';

import '../../core/constants/omni_theme.dart';
import '../../core/constants/workout_constants.dart';
import '../layout/omni_surface.dart';

/// Secondary control that adds or removes an entry of the current effort:
/// `−  <Set 2 of 3>  +`, boxed in an `OmniSurface` and sitting in the body
/// below the exercise's controls, away from the primary row.
///
/// The middle text is the caller's whole count line — `Set 2 of 3`, `Interval
/// 3 of 6`, `Round 1 of 4` / `Period 1 of 4`, `Hold 2 of 3` — so the control
/// stays modality-neutral. Both buttons are 48 dp targets even though the
/// glyphs are small. The `−` removes the whole exercise when the effort holds
/// a single entry ([removeIsExercise]).
class SetCountStepper extends StatelessWidget {
  /// The count line between the two buttons, e.g. `Set 2 of 3`.
  final String text;

  /// Whether another entry may be added (`false` at the per-effort cap).
  final bool canAdd;

  /// When true the `−` removes the whole exercise instead of one entry.
  final bool removeIsExercise;

  /// Called by `+`.
  final VoidCallback onAdd;

  /// Called by `−`.
  final VoidCallback onRemove;

  /// When false the `−` button is disabled and does nothing. Callers whose
  /// rule is narrower than `removeIsExercise` — the routine editor only
  /// removes the last entry of several — pass it instead of hiding the button.
  final bool canRemove;

  /// Replaces the `+` button's key (default `set-count-add`).
  final Key? addKey;

  /// Replaces the `−` button's key (default `set-count-remove`).
  final Key? removeKey;

  const SetCountStepper({
    super.key,
    required this.text,
    required this.canAdd,
    required this.removeIsExercise,
    required this.onAdd,
    required this.onRemove,
    this.canRemove = true,
    this.addKey,
    this.removeKey,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final buttonStyle = IconButton.styleFrom(
      minimumSize: const Size(48, 48),
      shape: const CircleBorder(),
      foregroundColor: scheme.onSurface.withAlpha(115),
      disabledForegroundColor: scheme.onSurface.withAlpha(51),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: OmniSurface(
        showShadow: false,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Row(
          children: [
            IconButton(
              key: removeKey ?? const Key('set-count-remove'),
              iconSize: 20,
              tooltip: removeIsExercise ? 'Remove exercise' : 'Remove set',
              onPressed: canRemove ? onRemove : null,
              icon: Icon(
                removeIsExercise ? Icons.delete_outline : Icons.remove,
              ),
              style: buttonStyle,
            ),
            Expanded(
              child: Center(
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    letterSpacing: 2.0,
                    color: OmniTheme.colors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            IconButton(
              key: addKey ?? const Key('set-count-add'),
              iconSize: 20,
              tooltip: canAdd
                  ? 'Add set'
                  : 'Max ${WorkoutConstants.maxEntriesPerEffort} entries',
              onPressed: canAdd ? onAdd : null,
              icon: const Icon(Icons.add),
              style: buttonStyle,
            ),
          ],
        ),
      ),
    );
  }
}
