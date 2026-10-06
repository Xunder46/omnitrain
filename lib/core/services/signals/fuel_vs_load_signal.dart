// The Fuel vs Load caution — the fourth registered signal (Stats PR 8a).
//
// The signal is a thin adapter: it derives its own two 21-day periods from
// `context.now` (D-1405), asks the load's `StatsProgressService` for each
// period's Mix payload (D-1407) and for the per-day intake series spanning both
// (D-1409), hands the figures to the pure rule (D-1406, D-1408, D-1410) and
// turns a qualified rise into a card. It reads no repository, walks no history
// of its own and calls no personal-record API (D-1418).

import '../../models/fuel_vs_load.dart';
import '../../models/signals.dart';
import '../../models/training_load.dart';
import 'signal.dart';

/// The card's title: it names the card for its key, its accessibility label
/// and the dismissal store, and is not rendered (D-1415).
const String _kFuelVsLoadTitle = 'Fuel vs load';

/// Proposes the Fuel vs Load card, or abstains when the load did not rise or
/// the intake rose with it (D-1408, D-1410).
class FuelVsLoadSignal implements Signal {
  const FuelVsLoadSignal();

  @override
  String get id => 'fuel-vs-load';

  @override
  SignalKind get kind => SignalKind.caution;

  @override
  int get priority => kFuelVsLoadPriority;

  @override
  Future<SignalCard?> evaluate(SignalContext context) async {
    // D-1405: the 21 local calendar days ending with today, and the 21
    // immediately before them. Calendar arithmetic, so a DST transition cannot
    // shift a boundary; the prior period ends the millisecond before the
    // recent one starts, so the whole of `day(21)` is inside it and the two
    // abut with no gap and no overlap.
    final now = context.now;
    final recentStart = DateTime(
      now.year,
      now.month,
      now.day - (kFuelVsLoadWindowDays - 1),
    );
    final priorStart = DateTime(
      now.year,
      now.month,
      now.day - (2 * kFuelVsLoadWindowDays - 1),
    );
    final priorEnd = DateTime.fromMillisecondsSinceEpoch(
      recentStart.millisecondsSinceEpoch - 1,
    );

    final recent = await context.progressService.computeMixPeriod(
      fromMs: recentStart,
      toMs: now,
    );
    if (recent == null) return null;

    final prior = await context.progressService.computeMixPeriod(
      fromMs: priorStart,
      toMs: priorEnd,
    );
    if (prior == null) return null;

    final points = await context.progressService.nutritionSeries(
      fromMs: priorStart,
      toMs: now,
    );

    final result = fuelVsLoad(
      now: now,
      recentMeasure: recent.measure,
      priorMeasure: prior.measure,
      recentLoad: _periodLoad(recent),
      priorLoad: _periodLoad(prior),
      loggedDays: [
        for (final point in points)
          LoggedDay(day: point.date, intake: point.calories.toDouble()),
      ],
    );
    if (result == null) return null;

    final copy = fuelVsLoadCopy(result);
    return SignalCard(
      id: id,
      kind: kind,
      priority: priority,
      title: _kFuelVsLoadTitle,
      observation: copy.observation,
      suggestion: copy.suggestion,
    );
  }

  /// A period's load: the sum of the payload's own segments' exact measures,
  /// in load minutes (D-1407).
  static double _periodLoad(MixLayerData payload) => payload.segments
      .fold<double>(0, (total, segment) => total + segment.measure);
}
