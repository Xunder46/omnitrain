/// How close two end instants must be before they count as the same instant.
///
/// Two devices stamp the end of one workout from two clocks; a second or two
/// between their stamps is skew, not a decision. The reconciliation rules
/// (D-14601, D-14630) compare end instants, so they compare them through
/// [kEndSkewToleranceMs] instead of exactly: two ends within the tolerance are
/// the same instant and D-14601's tie-break decides (a finished workout is never
/// deleted by one), and only an end earlier by MORE than the tolerance is the
/// earlier end D-14630 replaces for (D-15403).
///
/// The rule is symmetric on purpose, so the phone bridge, the Dart wrist twin
/// and the Swift engine reach the same answer from the same two stamps.
/// Proved by `test/sync_protocol_fixtures_test.dart` (S-15405..S-15407),
/// `test/watch_session_adoption_bridge_test.dart`, `test/watch_session_engine_test.dart`
/// and the Swift `WatchEndedIsFinalTests`.
library;

/// The tolerance, in milliseconds, within which two end instants are the same
/// instant — inclusive: exactly this far apart is still the same instant.
const int kEndSkewToleranceMs = 2000;

const Duration kEndSkewTolerance = Duration(milliseconds: kEndSkewToleranceMs);

/// Whether [incoming] is the earlier end that replaces [held]: earlier by MORE
/// than the tolerance.
bool endsBeforeHeldByMoreThanSkew(DateTime incoming, DateTime held) =>
    held.difference(incoming).inMicroseconds > kEndSkewToleranceMs * 1000;

/// Whether [incomingMs] is the earlier end that replaces [heldMs]: earlier by
/// MORE than the tolerance. The millisecond form the phone's own rows keep.
bool endsBeforeHeldMsByMoreThanSkew(int incomingMs, int heldMs) =>
    heldMs - incomingMs > kEndSkewToleranceMs;

/// Whether two end instants are within the tolerance of each other — the same
/// instant for the reconciliation rules.
bool areEndsWithinSkew(DateTime a, DateTime b) =>
    a.difference(b).inMicroseconds.abs() <= kEndSkewToleranceMs * 1000;

/// How an incoming end orders against the held one.
enum EndOrder { earlier, tied, later }

/// Orders [incoming] against [held] for D-14601/D-14630.
///
/// Two ends of DIFFERENT status (a finish against a discard) are compared
/// through the tolerance: within it they are `tied`, and the tie-break (a
/// finish wins) decides, so clock skew never deletes a finished workout
/// (D-15403). Two ends of the SAME status are compared exactly, as before the
/// tolerance: nothing is at stake between them but the end time, the earlier
/// one wins deterministically, and only an exactly equal pair reaches the
/// messageId tie-break — so a skew of a few hundred milliseconds never makes
/// the outcome depend on which random message id sorts first (S-15411).
EndOrder orderEnds({
  required DateTime incoming,
  required DateTime held,
  required bool sameStatus,
}) {
  if (sameStatus) {
    if (incoming.isBefore(held)) return EndOrder.earlier;
    if (incoming.isAtSameMomentAs(held)) return EndOrder.tied;
    return EndOrder.later;
  }
  if (endsBeforeHeldByMoreThanSkew(incoming, held)) return EndOrder.earlier;
  if (areEndsWithinSkew(incoming, held)) return EndOrder.tied;
  return EndOrder.later;
}
