// The Cross-Modality Interference — the third registered signal (Stats PR 7b).
//
// The signal is a thin adapter: it asks the load's `StatsProgressService` for
// the session payloads it already knows how to walk (D-1316), hands them and
// the load's `now` to the pure rule (D-1301–D-1313), and turns a qualified
// pattern into a card. It reads no repository, walks no history of its own and
// calls no personal-record API (D-1319).

import '../../models/interference.dart';
import '../../models/signals.dart';
import 'signal.dart';

/// The card's title: it names the card for its key, its accessibility label
/// and the dismissal store, and is not rendered (D-1315).
const String _kCrossModalityInterferenceTitle =
    'Interference after hard sports sessions';

/// Proposes the Cross-Modality Interference card, or abstains when fewer than
/// three dipped follow-ups fall in the pattern window (D-1309).
class InterferenceSignal implements Signal {
  const InterferenceSignal();

  @override
  String get id => 'cross-modality-interference';

  @override
  SignalKind get kind => SignalKind.caution;

  @override
  int get priority => kCrossModalityInterferencePriority;

  @override
  Future<SignalCard?> evaluate(SignalContext context) async {
    final sessions = await context.progressService.interferenceSessions();
    final result = crossModalityInterference(
      sessions: sessions,
      now: context.now,
    );
    if (result == null) return null;

    final copy = crossModalityInterferenceCopy(result);
    return SignalCard(
      id: id,
      kind: kind,
      priority: priority,
      title: _kCrossModalityInterferenceTitle,
      observation: copy.observation,
      suggestion: copy.suggestion,
    );
  }
}
