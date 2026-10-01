/// The exercises the wrist may offer without reaching the phone (S-003).
///
/// Three sources, in this order: what the user used on the wrist most recently,
/// the phone's own fallback list, and every exercise a synced routine names.
/// Deduplicated by exercise id keeping the first mention, so an exercise's
/// identity comes from the earliest source that knew it and the list the user
/// reads is stable between syncs.
///
/// Routine coverage is not left to the phone: the protocol's validator rejects a
/// `routines_down` whose fallback list misses one, and this derivation adds them
/// anyway — a routine the watch holds must always be loggable offline.
library;

import 'watch_routine_catalog.dart';

List<WatchCatalogExercise> deriveFallbackExercises({
  required List<WatchCatalogExercise> recents,
  required List<WatchCatalogExercise> syncedFallback,
  required List<WatchRoutine> routines,
}) {
  final seen = <String>{};
  final offered = <WatchCatalogExercise>[];

  for (final exercise in [
    ...recents,
    ...syncedFallback,
    for (final routine in routines)
      for (final effort in routine.efforts) effort.catalogExercise,
  ]) {
    if (seen.add(exercise.exerciseId)) offered.add(exercise);
  }

  return List.unmodifiable(offered);
}
