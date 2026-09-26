// Where a message that arrived from a wrist goes on the phone.
//
// Plan: `.github/agents/plans/2026-07-13-12-e-watch-nutrition-quick-log-plan.md`,
// scenarios S-002 and S-006.
//
// One transport, several owners: session state belongs to the live mirror, and
// the food the user logged belongs to the day log. A quick-log is often both —
// a snack mid-workout rides the session it was taken in and is still food the
// user ate — so the two are asked independently rather than one being chosen.
// Each ignores what is not its own.
//
// The watch session inbox is asked first (Stats PR 2,
// `.github/agents/plans/2026-09-25-02-stats-pr2-watch-capture-plan.md`, D-132):
// what a wrist session will become in history is staged before the mirror or
// the day log can answer the message, so nothing either of them does — a
// refusal, a snapshot answer — can come before it is durable.

library;

import 'live_session_mirror_state.dart';
import 'watch_nutrition_log_bridge.dart';
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
  }) : _inbox = inbox,
       _mirror = mirror,
       _nutrition = nutrition;

  final WatchSessionInbox _inbox;
  final LiveSessionMirrorState _mirror;
  final WatchNutritionLogBridge _nutrition;

  /// Applies one message from the wrist to each of its owners, the inbox
  /// first.
  ///
  /// None is told which part is its own: the inbox answers
  /// [WatchInboxOutcome.ignored] for anything that is not a wrist session's
  /// entries, the mirror answers [MirrorOutcome.ignored] for a session it is
  /// not holding, and the day log answers [WatchNutritionLogOutcome.ignored]
  /// for anything that is not a quick-log.
  Future<WatchIncomingReceipt> receive(Map<String, Object?> envelope) async {
    final staged = await _inbox.receive(envelope);
    final session = await _mirror.receive(envelope);
    final logged = await _nutrition.receive(envelope);
    return WatchIncomingReceipt(
      inbox: staged.outcome,
      session: session,
      nutrition: logged.outcome,
    );
  }
}
