// The Cardio Efficiency Drift caution — the sixth registered signal
// (Stats PR 9b).
//
// The signal is a thin adapter: it asks the load's `StatsProgressService` for
// the eligible cardio efforts over the whole span the comparison needs
// (D-1816), reads one Mix payload for the lifting sentence's own 28-day period
// (D-1807), hands the figures to the pure rule (D-1801…D-1808) and turns a
// qualified drift into a card. It reads no repository, walks no history of its
// own and calls no personal-record API (D-1810).

import '../../models/cardio_efficiency_drift.dart';
import '../../models/exercise_metric.dart';
import '../../models/signals.dart';
import '../../models/training_load.dart';
import 'signal.dart';

/// The card's title: it names the card for its key, its accessibility label
/// and the dismissal store, and is not rendered (D-1809).
const String _kCardioEfficiencyDriftTitle = 'Cardio efficiency drift';

/// Proposes the Cardio Efficiency Drift card when one exercise's measured pace
/// at the same average heart rate fell over comparable-duration efforts, or
/// abstains (D-1805, D-1814).
class CardioEfficiencyDriftSignal implements Signal {
  const CardioEfficiencyDriftSignal();

  @override
  String get id => 'cardio-efficiency-drift';

  @override
  SignalKind get kind => SignalKind.caution;

  @override
  int get priority => kCardioEfficiencyDriftPriority;

  @override
  Future<SignalCard?> evaluate(SignalContext context) async {
    // D-1816: the whole span the comparison needs — the reference window's far
    // edge through `now`. The rule applies its own window boundaries, so the
    // service is asked for no window decision of its own.
    final now = context.now;
    final efforts = await context.progressService.cardioEfforts(
      fromMs: DateTime(
        now.year,
        now.month,
        now.day - kCardioEfficiencyReferenceWeeksFrom * 7,
      ),
      toMs: now,
    );

    // D-1807: one payload for the lifting sentence's own 28 local calendar
    // days, read for both figures. A null payload means the period holds no
    // time at all, so the sentence cannot fire.
    final mix = await context.progressService.computeMixPeriod(
      fromMs: DateTime(
        now.year,
        now.month,
        now.day - (kCardioEfficiencyLiftLoadWindowDays - 1),
      ),
      toMs: now,
    );

    final result = cardioEfficiencyDrift(
      efforts: efforts,
      now: now,
      liftRecentLoad: _resistanceLoad(mix?.segments),
      liftUsualLoad: _resistanceLoad(mix?.baselineSegments),
      liftMeasure: mix?.measure ?? MixMeasure.time,
    );
    if (result == null) return null;

    final copy = cardioEfficiencyDriftCopy(result);
    return SignalCard(
      id: id,
      kind: kind,
      priority: priority,
      title: _kCardioEfficiencyDriftTitle,
      observation: copy.observation,
      suggestion: copy.suggestion,
    );
  }

  /// The summed measures of [segments] for Resistance — the lifting load the
  /// sentence compares (D-1807). A null payload contributes nothing.
  static double _resistanceLoad(List<MixSegment>? segments) {
    if (segments == null) return 0;
    var total = 0.0;
    for (final segment in segments) {
      if (segment.section != ExerciseSection.resistance) continue;
      total += segment.measure;
    }
    return total;
  }
}
