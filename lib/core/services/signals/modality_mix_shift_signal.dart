// The Modality Mix Shift — the second registered signal (Stats PR 7a).
//
// The signal is a thin adapter: it derives its own 28-day period from
// `context.now` (D-1201), asks the load's `StatsProgressService` for that
// period's payload (D-1204), hands the payload's own measure, segments and
// baseline segments to the pure rule (D-1205), and turns a qualified shift
// into a card. It reads no repository and walks no history of its own.

import '../../models/modality_mix_shift.dart';
import '../../models/signals.dart';
import 'signal.dart';

/// The card's title: it names the card for its key, its accessibility label
/// and the dismissal store, and is not rendered (D-1216).
const String _kModalityMixShiftTitle = 'Modality mix shift';

/// Proposes the Modality Mix Shift card, or abstains when no regularly trained
/// modality has fallen below half its usual share (D-1203, D-1210).
class ModalityMixShiftSignal implements Signal {
  const ModalityMixShiftSignal();

  @override
  String get id => 'modality-mix-shift';

  @override
  SignalKind get kind => SignalKind.caution;

  @override
  int get priority => kModalityMixShiftPriority;

  @override
  Future<SignalCard?> evaluate(SignalContext context) async {
    // D-1201: the 28 local calendar days ending with today, built from
    // calendar components so a DST transition cannot shift a boundary.
    final now = context.now;
    final fromMs = DateTime(
      now.year,
      now.month,
      now.day - (kModalityMixShiftPeriodDays - 1),
    );

    final period = await context.progressService.computeMixPeriod(
      fromMs: fromMs,
      toMs: now,
    );
    if (period == null) return null;

    final shift = modalityMixShift(
      measure: period.measure,
      recent: period.segments,
      baseline: period.baselineSegments,
    );
    if (shift == null) return null;

    final copy = modalityMixShiftCopy(shift);
    return SignalCard(
      id: id,
      kind: kind,
      priority: priority,
      title: _kModalityMixShiftTitle,
      observation: copy.observation,
      suggestion: copy.suggestion,
    );
  }
}
