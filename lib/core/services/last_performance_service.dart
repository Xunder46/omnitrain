import '../../data/models/models.dart';
import '../../data/repositories/workout_repository.dart';
import '../utils/entry_rows.dart';

/// One logged set of an earlier workout: reps and the load in kg (0 for no load).
class LastSet {
  const LastSet({required this.reps, required this.weightKg});

  final int reps;
  final double weightKg;
}

/// The sets of the newest finished workout that holds the exercise (plan 249).
class LastSets {
  const LastSets({required this.startedAtMs, required this.sets});

  /// When that workout started (local epoch ms).
  final int startedAtMs;

  /// Its non-skipped sets with reps above 0, block by block, in entry order.
  final List<LastSet> sets;
}

/// Reads "what did I do last time" for one reps-and-sets exercise through the
/// repository interface only. Nothing is cached: a Finish can change the answer,
/// so every caller asks fresh (plan 249 D-24901).
class LastPerformanceService {
  LastPerformanceService(this._repository);

  final WorkoutRepository _repository;

  /// The newest finished workout (by start time, not by store order) that holds
  /// at least one kept `set` entry for [exerciseId], or null. [excludeSessionId]
  /// is the running workout, never its own "last time".
  Future<LastSets?> lastSetsFor(
    String exerciseId, {
    String? excludeSessionId,
  }) async {
    final sessions =
        (await _repository.getAllSessions())
            .where((s) => s.endedAtMs != null && s.id != excludeSessionId)
            .toList()
          ..sort((a, b) => b.startedAtMs.compareTo(a.startedAtMs));
    if (sessions.isEmpty) return null;

    final segmentsBySession = await _repository.getSegmentsBySession();
    final effortsBySegment = await _repository.getEffortsBySegment();
    final observationsByEffort = await _repository.getObservationsByEffort();

    for (final session in sessions) {
      final segments = [
        ...(segmentsBySession[session.id] ?? const <SessionSegment>[]),
      ]..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      final sets = <LastSet>[];
      for (final segment in segments) {
        final efforts = [
          ...(effortsBySegment[segment.id] ?? const <SegmentEffort>[]),
        ]..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
        for (final effort in efforts) {
          if (effort.effortKind != 'set' || effort.exerciseId != exerciseId) {
            continue;
          }
          final rows =
              observationsByEffort[effort.id] ?? const <EffortObservation>[];
          for (final entry in EntryRows.setEntries(rows)) {
            if (entry['skipped'] == true) continue;
            final reps = entry['reps'] as int? ?? 0;
            if (reps <= 0) continue;
            sets.add(
              LastSet(
                reps: reps,
                weightKg: (entry['weight'] as num?)?.toDouble() ?? 0.0,
              ),
            );
          }
        }
      }
      if (sets.isNotEmpty) {
        return LastSets(startedAtMs: session.startedAtMs, sets: sets);
      }
    }
    return null;
  }
}
