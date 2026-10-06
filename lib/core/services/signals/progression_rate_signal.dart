// The Progression Rate — the first registered signal (Stats PR 6b).
//
// The signal is a thin adapter: it asks the load's `StatsProgressService` for
// the samples it already knows how to walk (D-1112), hands them to the pure
// math with the load's `now`, and turns a qualified rate into a card. It reads
// no repository and calls no personal-record API — a tie counts here and is
// not a PR there (D-1111).

import '../../models/progression_rate.dart';
import '../../models/signals.dart';
import 'signal.dart';

/// The card's title: it names the card for its key, its accessibility label
/// and the dismissal store, and is not rendered (D-1001, D-1109).
const String _kProgressionRateTitle = 'Progression rate';

/// Proposes the Progression Rate card, or abstains when the rate does not
/// qualify (D-1008, D-1109, D-1110).
class ProgressionRateSignal implements Signal {
  const ProgressionRateSignal();

  @override
  String get id => 'progression-rate';

  @override
  SignalKind get kind => SignalKind.positive;

  @override
  int get priority => kProgressionRatePriority;

  @override
  Future<SignalCard?> evaluate(SignalContext context) async {
    final samples = await context.progressService.progressionSamples();
    final rate = progressionRate(samples: samples, now: context.now);
    if (rate == null) return null;

    final copy = progressionRateCopy(rate);
    return SignalCard(
      id: id,
      kind: kind,
      priority: priority,
      title: _kProgressionRateTitle,
      observation: copy.observation,
      suggestion: copy.suggestion,
    );
  }
}
