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

library;

import 'live_session_mirror_state.dart';
import 'watch_nutrition_log_bridge.dart';

/// What happened to one message from the wrist.
class WatchIncomingReceipt {
  const WatchIncomingReceipt({required this.session, required this.nutrition});

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
    required LiveSessionMirrorState mirror,
    required WatchNutritionLogBridge nutrition,
  }) : _mirror = mirror,
       _nutrition = nutrition;

  final LiveSessionMirrorState _mirror;
  final WatchNutritionLogBridge _nutrition;

  /// Applies one message from the wrist to both of its owners.
  ///
  /// Neither is told which half is its own: the mirror answers
  /// [MirrorOutcome.ignored] for a session it is not holding, and the day log
  /// answers [WatchNutritionLogOutcome.ignored] for anything that is not a
  /// quick-log.
  Future<WatchIncomingReceipt> receive(Map<String, Object?> envelope) async {
    final session = await _mirror.receive(envelope);
    final logged = await _nutrition.receive(envelope);
    return WatchIncomingReceipt(session: session, nutrition: logged.outcome);
  }
}
