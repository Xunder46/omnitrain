// The Protein Consistency caution — the fifth registered signal (Stats PR 8b).
//
// The signal is a thin adapter: it derives its own 14-day window from
// `context.now` (D-1502), asks the load's `StatsProgressService` for the
// nutrition series spanning the window and the eight blocks before it, the
// window's per-day protein targets, the window's completed resistance-session
// count and the latest bodyweight in kilograms (D-1519), hands the figures to
// the pure rule (D-1503…D-1510) and turns a qualified shortfall into a card. It
// reads no repository, walks no history of its own and calls no personal-record
// API (D-1518).

import '../../models/nutrition_consistency.dart';
import '../../models/protein_consistency.dart';
import '../../models/signals.dart';
import 'signal.dart';

/// The card's title: it names the card for its key, its accessibility label and
/// the dismissal store, and is not rendered (D-1502).
const String _kProteinConsistencyTitle = 'Protein consistency';

/// Proposes the Protein Consistency card, or abstains when the window is too
/// thin, holds too little resistance training, or is not far enough below the
/// comparison (D-1504, D-1508, D-1510).
class ProteinConsistencySignal implements Signal {
  const ProteinConsistencySignal();

  @override
  String get id => 'protein-consistency';

  @override
  SignalKind get kind => SignalKind.caution;

  @override
  int get priority => kProteinConsistencyPriority;

  @override
  Future<SignalCard?> evaluate(SignalContext context) async {
    // D-1502: the 14 local calendar days ending with today, and the eight
    // 7-day blocks immediately before them. Calendar arithmetic, so a DST
    // transition cannot shift a boundary; the window's first day is exactly one
    // day after the baseline's last, so the two abut with no gap and no
    // overlap.
    final now = context.now;
    final windowStart = DateTime(
      now.year,
      now.month,
      now.day - (kProteinConsistencyWindowDays - 1),
    );
    final baselineStart = DateTime(
      now.year,
      now.month,
      now.day -
          (kProteinConsistencyWindowDays -
              1 +
              kProteinConsistencyBaselineWeeks * kWeekDays),
    );

    // One read of the series covers both the window and the blocks before it;
    // the days are split by the window's first day, which is the boundary the
    // rule itself uses.
    final points = await context.progressService.nutritionSeries(
      fromMs: baselineStart,
      toMs: now,
    );
    final windowDays = <ProteinDay>[];
    final baselineDays = <ProteinDay>[];
    for (final point in points) {
      final day = ProteinDay(
        day: point.date,
        protein: point.protein.toDouble(),
      );
      if (point.date.isBefore(windowStart)) {
        baselineDays.add(day);
      } else {
        windowDays.add(day);
      }
    }

    final targets = await context.progressService.proteinTargetsByDay(
      fromMs: windowStart,
      toMs: now,
    );
    final resistanceSessions = await context.progressService
        .resistanceSessionCount(fromMs: windowStart, toMs: now);
    final bodyWeightKg = await context.progressService.latestBodyWeightKg();

    final result = proteinConsistency(
      now: now,
      recentDays: windowDays,
      proteinTargets: targets,
      resistanceSessions: resistanceSessions,
      baselineDays: baselineDays,
      bodyWeightKg: bodyWeightKg,
    );
    if (result == null) return null;

    final copy = proteinConsistencyCopy(result);
    return SignalCard(
      id: id,
      kind: kind,
      priority: priority,
      title: _kProteinConsistencyTitle,
      observation: copy.observation,
      suggestion: copy.suggestion,
    );
  }
}
