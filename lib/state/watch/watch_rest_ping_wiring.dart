import 'dart:async';

import '../../core/utils/rest_notification_service.dart';
import '../../core/utils/wrist_rest_ping_rule.dart';
import '../workout/workout_state.dart';
import 'live_session_mirror_state.dart';
import 'watch_link_state.dart';

/// Wires the rest-ping gate (plan 86, D-8): while the wrist is connected and
/// mirroring the phone's current session, the wrist owns the rest pings and
/// the phone's background notifications stay quiet.
///
/// The gate closure reads the link, the mirror and the workout state at call
/// time, so every pass of the service sees the state as it is then. With no
/// watch graph at all (`link == null && mirror == null`) nothing is bound and
/// the gate stays null — the phone never quiets itself.
void bindRestPingGate({
  required RestNotificationService service,
  required WatchLinkState? link,
  required LiveSessionMirrorState? mirror,
  required WorkoutState workoutState,
}) {
  if (link == null && mirror == null) return;

  service.wristOwnsPings = () => wristOwnsRestPings(
    linkConnected: link?.phase == WatchLinkPhase.connected,
    mirrorActive: mirror?.isActive ?? false,
    mirrorSessionId: mirror?.sessionId,
    phoneSessionId: workoutState.currentSession?.id,
  );

  // The gate's value before the mirror change being handled: the field is
  // what tells "the wrist stopped holding the phone's session" apart from
  // "it never held it".
  bool previousGate = service.wristOwnsPings!();

  // A link change is always worth a re-read: the takeover when the wrist
  // drops (S-15610) and the hand-back when it returns both run through
  // `reevaluate`.
  link?.addListener(() {
    // Keep the memory current across a link flip too: a gate that went false
    // because the wrist dropped out is not an "owned" rest a later mirror
    // change may cancel.
    previousGate = service.wristOwnsPings!();
    unawaited(service.reevaluate());
  });

  // A mirror change ends the owned rest when the mirror no longer reports an
  // active session matching the phone's: cancel and forget, so no phantom
  // ping is re-scheduled for a rest the wrist finished (S-15611). Otherwise
  // re-read the gate.
  mirror?.addListener(() {
    final gate = service.wristOwnsPings!();
    final wasOwned = previousGate;
    previousGate = gate;
    final mirrorStillHoldsPhoneSession =
        mirror.isActive && mirror.sessionId == workoutState.currentSession?.id;
    // Only an ENDED mirror session ends the owned rest. A switch to another
    // active session (the wrist moved on with no end frame) hands the pings
    // back: re-evaluate, so the phone's still-open rest is not left silent.
    if (wasOwned && !mirrorStillHoldsPhoneSession && !mirror.isActive) {
      unawaited(service.cancelRestNotifications());
    } else {
      unawaited(service.reevaluate());
    }
  });
}
