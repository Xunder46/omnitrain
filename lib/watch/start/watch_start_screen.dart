/// Where a session begins on the wrist: a synced routine, or a free workout.
///
/// Plan: `.github/agents/plans/2026-07-13-08-b-watch-session-start-paths-plan.md`,
/// frontend changes.
///
/// Everything on this screen is already on the watch. The routine list is read
/// from local storage, so it renders with the phone off, in airplane mode, or
/// before the wrist has ever seen a radio — which is the point of syncing
/// proactively rather than at session start.
library;

import 'package:flutter/material.dart';

import '../../core/constants/omni_theme.dart';
import '../session/watch_records.dart';
import 'watch_exercise_picker.dart';
import 'watch_session_start_paths.dart';

class WatchStartScreen extends StatelessWidget {
  const WatchStartScreen({
    super.key,
    required this.paths,
    this.onSessionStarted,
    this.onOpenNutrition,
  });

  final WatchSessionStartPaths paths;

  /// Handed the session that is ready to log. Left null, the session still
  /// starts — the watch app owns navigation, not this widget.
  final void Function(WatchSessionRecord session)? onSessionStarted;

  /// Opens the quick-log surface. Left null, the tile is not offered.
  ///
  /// Nutrition logging is independent of training sessions, so this sits on the
  /// home surface rather than behind a workout (S-006).
  final VoidCallback? onOpenNutrition;

  /// Wrist-scale layout: the phone's spacing tokens are sized for a full-width
  /// screen, so the watch carries its own two values rather than scaling a
  /// phone token down.
  static const double surfaceInset = 8;
  static const double surfaceInsetCompact = 4;
  static const double rowGap = 4;

  /// The home surface's way into the quick-log, which is reachable with no
  /// workout running.
  static const String logFoodLabel = 'Log food';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: surfaceInset,
            vertical: surfaceInsetCompact,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: paths.routines.isEmpty
                    ? _nothingSynced(context)
                    : _routineList(context),
              ),
              const SizedBox(height: rowGap),
              _freeWorkoutButton(context),
              if (onOpenNutrition != null) ...[
                const SizedBox(height: rowGap),
                WatchUtilityButton(
                  label: logFoodLabel,
                  onPressed: onOpenNutrition!,
                ),
              ],
              if (paths.phoneReachable) ...[
                const SizedBox(height: rowGap),
                const SearchOnPhoneHint(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// With nothing synced there is no routine to start and no exercise to pick.
  /// Saying so — and saying who fixes it — beats an empty list.
  Widget _nothingSynced(BuildContext context) {
    final styles = Theme.of(context).textTheme;
    return Center(
      child: Text(
        'No routines yet. Sync with your phone to get them.',
        style: styles.bodySmall,
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _routineList(BuildContext context) {
    return ListView.separated(
      itemCount: paths.routines.length,
      separatorBuilder: (context, index) => const SizedBox(height: rowGap),
      itemBuilder: (context, index) {
        final routine = paths.routines[index];
        return WatchPrimaryButton(
          label: routine.name,
          onPressed: () => _startFromRoutine(routine.routineId),
        );
      },
    );
  }

  Widget _freeWorkoutButton(BuildContext context) => WatchUtilityButton(
    label: 'Free workout',
    onPressed: () => _startFreeWorkout(context),
  );

  /// Path 1: the routine's template becomes the session, and the first exercise
  /// is what the logging surface shows.
  Future<void> _startFromRoutine(String routineId) async {
    onSessionStarted?.call(await paths.startFromRoutine(routineId));
  }

  /// Path 2: an empty session, then the picker — the fallback list, or whatever
  /// the phone pushes for the search the wrist cannot do itself.
  Future<void> _startFreeWorkout(BuildContext context) async {
    await paths.startFreeWorkout();
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => WatchExercisePickerScreen(
          paths: paths,
          onExerciseAdded: onSessionStarted,
        ),
      ),
    );
  }
}

/// The wrist's primary action: full width, at the token height, with an
/// explicit shape rather than whatever Material 3 defaults to.
class WatchPrimaryButton extends StatelessWidget {
  const WatchPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: ButtonStyle(
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(OmniTheme.buttonBorderRadius),
          ),
        ),
        minimumSize: WidgetStateProperty.all(
          const Size.fromHeight(OmniTheme.buttonPrimaryHeight),
        ),
      ),
      onPressed: onPressed,
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

/// The secondary action, at the same height so the two never look like a
/// hierarchy the wrist does not have room to explain.
class WatchUtilityButton extends StatelessWidget {
  const WatchUtilityButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: ButtonStyle(
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(OmniTheme.buttonUtilityRadius),
          ),
        ),
        minimumSize: WidgetStateProperty.all(
          const Size.fromHeight(OmniTheme.buttonPrimaryHeight),
        ),
      ),
      onPressed: onPressed,
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

/// "The full catalog is a phone away" — shown only while the phone can actually
/// be reached, because it is a promise about a radio.
class SearchOnPhoneHint extends StatelessWidget {
  const SearchOnPhoneHint({super.key});

  static const String label = 'Search on phone';
  static const double iconSize = 14;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.phone_iphone, size: iconSize),
        const SizedBox(width: WatchStartScreen.rowGap),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall,
            maxLines: 2,
          ),
        ),
      ],
    );
  }
}
