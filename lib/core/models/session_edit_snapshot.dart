import '../../data/models/models.dart';

/// An immutable point-in-time snapshot of a session's mutable data,
/// captured when the user enters edit mode from the summary screen.
///
/// Stored in [WorkoutSessionScreen] while editing. On *Save*, it is discarded.
/// On *Back* (without Save), [WorkoutState.restoreSessionSnapshot] uses it to
/// undo all structural changes (added/removed exercises, added/removed sets)
/// that were persisted immediately to the repository, and to put back the
/// sensor summaries those changes and the undo deleted.
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

  /// The session's wrist-measured sensor summaries at snapshot time.
  ///
  /// A summary is deleted together with the effort, timed instance or round
  /// instance it targets (D-131). Both a live edit (deleting a round, removing
  /// an exercise) and the restore's own delete-and-re-create do that, and
  /// re-creating a row does not bring its summary back, so the restore
  /// re-creates these (put-if-absent). Summaries are immutable; the list is a
  /// copy.
  final List<SensorSummary> sensorSummaries;

  /// The `entryId` of every applied inbox row of the session, read from the
  /// repository *before* the session's rows are loaded (D-801).
  ///
  /// The restore uses it to tell a watch entry that was already in history
  /// when the snapshot was taken from one that arrived while the screen was
  /// open: the latter is not named here and is recovered (D-802).
  ///
  /// `null` means the caller recorded no watermark, and `null` means no
  /// recovery — the restore then behaves exactly as it did before the field
  /// existed (D-803). Reading it before the rows keeps the watermark a subset
  /// of what the snapshot's rows reflect, so it can only ever under-name, and
  /// over-recovery is idempotent (D-806).
  final Set<String>? watchEntryIdsAppliedAtSnapshot;

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
    required this.sensorSummaries,
    this.watchEntryIdsAppliedAtSnapshot,
  });
}
