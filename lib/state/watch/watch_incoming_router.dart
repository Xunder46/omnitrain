// Where a message that arrived from a wrist goes on the phone.
//
// Plan: `docs/plans/2026-07-13-12-e-watch-nutrition-quick-log-plan.md`,
// scenarios S-002 and S-006.
//
// One transport, several owners: session state belongs to the live mirror, and
// the food the user logged belongs to the day log. A quick-log is often both —
// a snack mid-workout rides the session it was taken in and is still food the
// user ate — so the two are asked independently rather than one being chosen.
// Each ignores what is not its own.
//
// The watch session inbox is asked first (Stats PR 2,
// `docs/plans/2026-09-25-02-stats-pr2-watch-capture-plan.md`, D-132):
// what a wrist session will become in history is staged before the mirror or
// the day log can answer the message, so nothing either of them does — a
// refusal, a snapshot answer — can come before it is durable.
//
// The session the wrist is running is adopted last (watch session sync PR 1,
// `docs/plans/2026-10-05-15a-watch-session-sync-pr1-plan/…`, D-2): after the
// mirror has reconciled a snapshot, the adoption bridge projects that verdict
// into the phone's own session state, so the phone logs into the same ladder
// the wrist is looking at.

library;

import '../../watch/session/watch_records.dart' show WatchLifecycleState;
import 'live_session_mirror_state.dart';
import 'watch_nutrition_log_bridge.dart';
import 'watch_session_adoption_bridge.dart';
import 'watch_session_inbox.dart';

/// What happened to one message from the wrist.
class WatchIncomingReceipt {
  const WatchIncomingReceipt({
    required this.inbox,
    required this.session,
    required this.nutrition,
  });

  /// The watch session inbox's verdict. [WatchInboxOutcome.ignored] is the
  /// ordinary answer for anything that is not a wrist session's entries.
  final WatchInboxOutcome inbox;

  /// The live mirror's verdict. [MirrorOutcome.ignored] means the message named
  /// no session this phone is holding — the ordinary answer for a quick-log
  /// taken with no workout running.
  final MirrorOutcome session;

  /// What the day log did with it. [WatchNutritionLogOutcome.ignored] is the
  /// ordinary answer for anything that is not a quick-log, including the
  /// entries of a session the mirror has just applied.
  final WatchNutritionLogOutcome nutrition;

  /// True when this message left a row in the phone's day log.
  bool get loggedFood => nutrition == WatchNutritionLogOutcome.applied;
}

class WatchIncomingRouter {
  const WatchIncomingRouter({
    required WatchSessionInbox inbox,
    required LiveSessionMirrorState mirror,
    required WatchNutritionLogBridge nutrition,
    WatchSessionAdoptionBridge? adoption,
  }) : _inbox = inbox,
       _mirror = mirror,
       _nutrition = nutrition,
       _adoption = adoption;

  final WatchSessionInbox _inbox;
  final LiveSessionMirrorState _mirror;
  final WatchNutritionLogBridge _nutrition;

  /// Optional: a phone with no session state (a build flag, a test that only
  /// exercises the day log) adopts nothing.
  final WatchSessionAdoptionBridge? _adoption;

  /// Applies one message from the wrist to each of its owners, the inbox
  /// first.
  ///
  /// None is told which part is its own: the inbox answers
  /// [WatchInboxOutcome.ignored] for anything that is not a wrist session's
  /// entries, the mirror answers [MirrorOutcome.ignored] for a session it is
  /// not holding, and the day log answers [WatchNutritionLogOutcome.ignored]
  /// for anything that is not a quick-log.
  ///
  /// The session the wrist is running is adopted after the mirror has answered,
  /// from the snapshot it applied (D-2). Only a snapshot carries a ladder, and
  /// only a mirror that applied it has a converged session to adopt.
  ///
  /// The two directions of *ending* are answered here as well. A wrist
  /// `session_lifecycle` ends the phone's copy of the session it names, through
  /// the ordinary finish (D-5). A snapshot of a session whose row is already
  /// history adopts nothing (G1) and is answered with that session's
  /// `completed` lifecycle, so a wrist still looking at it catches up.
  Future<WatchIncomingReceipt> receive(Map<String, Object?> envelope) async {
    final staged = await _inbox.receive(envelope);
    final session = await _mirror.receive(envelope);
    if (envelope['type'] == 'session_snapshot' &&
        session == MirrorOutcome.applied) {
      final adopted = await _adoption?.consider(_mirror.state);
      // G1: the snapshot named a session whose row is already history, so
      // nothing was adopted and nothing was reloaded. The wrist is still
      // looking at a session this phone has finished, and the only thing that
      // tells it so is the session's own lifecycle: the mirror composes it
      // from the session it has just converged on and sends it (G2 — the phone
      // never pushes an end of its own accord, it answers one).
      if (adopted == WatchSessionAdoption.alreadyEnded) {
        await _mirror.reportLifecycle(WatchLifecycleState.completed);
      }
    }
    // The wrist is the authority on when its own session is over: its
    // `session_lifecycle` ends the phone's copy of that session through the
    // ordinary finish (D-5). After the mirror, because the lifecycle is also
    // the mirror's to apply, and the two read the same frame.
    if (envelope['type'] == 'session_lifecycle') {
      await _adoption?.onLifecycle(envelope);
    }
    final logged = await _nutrition.receive(envelope);
    return WatchIncomingReceipt(
      inbox: staged.outcome,
      session: session,
      nutrition: logged.outcome,
    );
  }
}
