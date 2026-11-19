/// Decision rule for plan 86: while the watch is reachable and mirroring
/// the phone's current session, the wrist owns the rest pings and the
/// phone's background rest notifications stay quiet.
///
/// Pure function — no state imports, no I/O; the caller reads the four
/// inputs from `WatchLinkState`, `LiveSessionMirrorState` and
/// `WorkoutState` at call time.
bool wristOwnsRestPings({
  required bool linkConnected,
  required bool mirrorActive,
  required String? mirrorSessionId,
  required String? phoneSessionId,
}) {
  return linkConnected &&
      mirrorActive &&
      mirrorSessionId != null &&
      mirrorSessionId == phoneSessionId;
}
