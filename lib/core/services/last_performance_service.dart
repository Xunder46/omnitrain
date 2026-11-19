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

/// The four bulk reads the lookup answers from.
class _History {
  const _History({
    required this.sessions,
    required this.segments,
    required this.efforts,
    required this.observations,
  });

  final List<TrainingSession> sessions;
  final Map<String, List<SessionSegment>> segments;
  final Map<String, List<SegmentEffort>> efforts;
  final Map<String, List<EffortObservation>> observations;
}

/// Reads "what did I do last time" for one reps-and-sets exercise through the
/// repository interface only. By default nothing is cached: a Finish can change
/// the answer, so a screen asks fresh (plan 249 D-24901). A live workout that
/// asks for every exercise it adds builds it with [cacheHistory], so a routine
/// of many sets reads the history once (plan 250 D-25003). A workout the wrist
/// finishes while this one is live is not seen until the next workout: a
/// prefill one workout behind is accepted (plan 250 open item 5).
class LastPerformanceService {
  LastPerformanceService(this._repository, {this.cacheHistory = false});

  final WorkoutRepository _repository;

  /// True keeps the four bulk reads after the first call.
  final bool cacheHistory;

  /// The one read in flight or done (single-flight: two callers that arrive
  /// before it finishes share it instead of each reading the history).
  Future<_History>? _pending;

  Future<_History> _read() async => _History(
    sessions: await _repository.getAllSessions(),
    segments: await _repository.getSegmentsBySession(),
    efforts: await _repository.getEffortsBySegment(),
    observations: await _repository.getObservationsByEffort(),
  );

  Future<_History> _load() async {
    if (!cacheHistory) return _read();
    final pending = _pending ??= _read();
    try {
      return await pending;
    } catch (_) {
      // A failed read is not kept: the next call tries again.
      if (identical(_pending, pending)) _pending = null;
      rethrow;
    }
  }

  /// The newest finished workout (by start time, not by store order) that holds
  /// at least one kept `set` entry for [exerciseId], or null. [excludeSessionId]
  /// is the running workout, never its own "last time".
  Future<LastSets?> lastSetsFor(
    String exerciseId, {
    String? excludeSessionId,
  }) async {
    final history = await _load();
    final sessions =
        history.sessions
            .where((s) => s.endedAtMs != null && s.id != excludeSessionId)
            .toList()
          ..sort((a, b) => b.startedAtMs.compareTo(a.startedAtMs));

    for (final session in sessions) {
      final segments = [
        ...(history.segments[session.id] ?? const <SessionSegment>[]),
      ]..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      final sets = <LastSet>[];
      for (final segment in segments) {
        final efforts = [
          ...(history.efforts[segment.id] ?? const <SegmentEffort>[]),
        ]..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
        for (final effort in efforts) {
          if (effort.effortKind != 'set' || effort.exerciseId != exerciseId) {
            continue;
          }
          final rows =
              history.observations[effort.id] ?? const <EffortObservation>[];
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
