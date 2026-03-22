import '../../data/models/models.dart';

/// An immutable point-in-time snapshot of a session's mutable data,
/// captured when the user enters edit mode from the summary screen.
///
/// Stored in [WorkoutSessionScreen] while editing. On *Save*, it is discarded.
/// On *Back* (without Save), [WorkoutState.restoreSessionSnapshot] uses it to
/// undo all structural changes (added/removed exercises, added/removed sets)
/// that were persisted immediately to the repository.
///
/// Note: metric-value edits are separately buffered in [_editBuffer] on the
/// screen and never reach the repository until Save — so they are automatically
/// discarded on Back without any repository interaction.
///
/// Pure Dart — no Flutter imports.
class SessionEditSnapshot {
  /// The ID of the session this snapshot belongs to.
  final String sessionId;

  /// Ordered list of the session's segments at snapshot time.
  /// Segments are not mutated during editing; captured for completeness.
  final List<SessionSegment> segments;

  /// Efforts keyed by segmentId. Deep-copied at snapshot time.
  final Map<String, List<SegmentEffort>> efforts;

  /// EffortObservations keyed by effortId. Deep-copied at snapshot time.
  /// Captures observation count and values so add-set / delete-set can be undone.
  final Map<String, List<EffortObservation>> observations;

  /// RoundInstances keyed by effortId. Deep-copied at snapshot time.
  final Map<String, List<RoundInstance>> roundInstances;

  /// TimedInstances keyed by effortId. Deep-copied at snapshot time.
  final Map<String, List<TimedInstance>> timedInstances;

  /// Exercise cache at snapshot time.
  /// Needed to restore exercises for efforts that were removed during editing
  /// (so their exerciseId still resolves after restore).
  final Map<String, Exercise> exerciseCache;

  // NOTE: EntryRest records are intentionally NOT included in the snapshot.
  // Rest records are never structurally mutated during edit mode — no new rests
  // are created, and add/remove set operations do not touch them. There is
  // therefore nothing to roll back, and omitting them keeps the snapshot lean.

  const SessionEditSnapshot({
    required this.sessionId,
    required this.segments,
    required this.efforts,
    required this.observations,
    required this.roundInstances,
    required this.timedInstances,
    required this.exerciseCache,
  });
}
