/// The exercise picker for a free workout: the fallback list, and nothing else.
///
/// Plan: `.github/agents/plans/2026-07-13-08-b-watch-session-start-paths-plan.md`,
/// S-002 and S-005.
///
/// The full catalog deliberately never reaches the wrist, so this is not a
/// search screen — it is a short list of what the watch knows it can log: what
/// the user used recently, what the phone offered, and every exercise a synced
/// routine names. When the phone is reachable, the screen says where the rest
/// lives and waits for the push.
library;

import 'package:flutter/material.dart';

import '../session/watch_records.dart';
import 'watch_routine_catalog.dart';
import 'watch_session_start_paths.dart';
import 'watch_start_screen.dart';

class WatchExercisePickerScreen extends StatelessWidget {
  const WatchExercisePickerScreen({
    super.key,
    required this.paths,
    this.onExerciseAdded,
  });

  final WatchSessionStartPaths paths;

  /// Handed the session once the added exercise is the one to log. Left null,
  /// the exercise is still added.
  final void Function(WatchSessionRecord session)? onExerciseAdded;

  @override
  Widget build(BuildContext context) {
    final exercises = paths.fallbackExercises;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: WatchStartScreen.surfaceInset,
            vertical: WatchStartScreen.surfaceInsetCompact,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: exercises.isEmpty
                    ? _nothingToOffer(context)
                    : _exerciseList(context, exercises),
              ),
              if (paths.phoneReachable) ...[
                const SizedBox(height: WatchStartScreen.rowGap),
                const SearchOnPhoneHint(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Offline with nothing synced yet: the one thing that helps is the phone.
  Widget _nothingToOffer(BuildContext context) {
    return Center(
      child: Text(
        'No exercises yet. Search on the phone and send one over.',
        style: Theme.of(context).textTheme.bodySmall,
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _exerciseList(
    BuildContext context,
    List<WatchCatalogExercise> exercises,
  ) {
    return ListView.separated(
      itemCount: exercises.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: WatchStartScreen.rowGap),
      itemBuilder: (context, index) {
        final exercise = exercises[index];
        return WatchUtilityButton(
          label: exercise.name,
          onPressed: () => _add(context, exercise),
        );
      },
    );
  }

  /// Picking an exercise *is* the request: the list dismisses itself and hands
  /// the session over, so the user lands on the logging surface. Adding another
  /// later is the same flow again — the wrist never makes a pick feel like a
  /// half-finished form.
  Future<void> _add(
    BuildContext context,
    WatchCatalogExercise exercise,
  ) async {
    final session = await paths.addExerciseToSession(exercise);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    onExerciseAdded?.call(session);
  }
}
