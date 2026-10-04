// The Sustained High Load caution — the fifth registered signal (Stats PR 9a).
//
// The signal is a thin adapter: it asks the load's `StatsProgressService` for
// the completed weekly series (D-1703), hands the series to the pure rule to
// find the streak, reads one Mix payload for the span the streak covers
// (D-1709) and uses it only to decide whether that span was measured in load or
// in time (D-1709). It reads no repository, walks no history of its own and
// calls no personal-record API (D-1714).

import '../../models/signals.dart';
import '../../models/sustained_high_load.dart';
import '../../models/training_load.dart';
import 'signal.dart';

/// The card's title: it names the card for its key, its accessibility label
/// and the dismissal store, and is not rendered (D-1713).
const String _kSustainedHighLoadTitle = 'Sustained high load';

/// Proposes the Sustained High Load card when the completed weeks ran above
/// usual with no easier week, or abstains (D-1708, D-1709).
class SustainedHighLoadSignal implements Signal {
  const SustainedHighLoadSignal();

  @override
  String get id => 'sustained-high-load';

  @override
  SignalKind get kind => SignalKind.caution;

  @override
  int get priority => kSustainedHighLoadPriority;

  @override
  Future<SignalCard?> evaluate(SignalContext context) async {
    // D-1703: the completed weeks the service returns, oldest first, with the
    // week containing `now` already excluded.
    final weeks = await context.progressService.weeklyLoads(now: context.now);
    final streak = sustainedHighLoadStreak(weeks: weeks);

    // D-1709: below the floor the rule cannot qualify, so the Mix payload —
    // the only expensive read here — is never requested.
    if (streak.weekCount < kSustainedHighLoadMinStreakWeeks) return null;

    // D-1709: one payload for the streak's own span, from its first week's
    // start through `now`.
    final mix = await context.progressService.computeMixPeriod(
      fromMs: streak.firstWeekStart!,
      toMs: context.now,
    );
    final mixShowsLoad = mix != null && mix.measure == MixMeasure.load;

    final result = sustainedHighLoad(weeks: weeks, mixShowsLoad: mixShowsLoad);
    if (result == null) return null;

    final copy = sustainedHighLoadCopy(result);
    return SignalCard(
      id: id,
      kind: kind,
      priority: priority,
      title: _kSustainedHighLoadTitle,
      observation: copy.observation,
      suggestion: copy.suggestion,
    );
  }
}
