// Stats PR 7a — the Modality Mix Shift's pure rule and copy.
//
// The rule reads the period payload's own segments and re-derives no
// percentage: the fire test is an exact-fraction comparison on the segments'
// `measure`, and the copy reads their shared rounded `percent`. There is no
// clock here, no repository and no Flutter — the caller passes the payload.

import 'exercise_metric.dart';
import 'training_load.dart';

/// The signal's recent period, in local calendar days (D-1201).
const int kModalityMixShiftPeriodDays = 28;

/// The smallest baseline share at which a modality counts as regularly trained
/// (D-1206). The boundary is inclusive.
const double kModalityMixShiftMinBaselineShare = 0.10;

/// The signal's priority, below Cross-Modality Interference and above every
/// later caution (D-1214).
const int kModalityMixShiftPriority = 400;

/// A modality that has fallen to less than half its usual share of the load.
///
/// [section] is the reported modality; [recentPercent] and [baselinePercent]
/// are its rounded shares from the period's own segments and baseline
/// segments. [grownSection] and [grownPercent] name the largest recent share
/// when it belongs to a modality other than the reported one, and are null
/// otherwise (D-1211, D-1212).
class ModalityMixShift {
  const ModalityMixShift({
    required this.section,
    required this.recentPercent,
    required this.baselinePercent,
    required this.grownSection,
    required this.grownPercent,
  });

  final ExerciseSection section;
  final int recentPercent;
  final int baselinePercent;
  final ExerciseSection? grownSection;
  final int? grownPercent;
}

/// The card's copy: the observation and the suggestion.
class ModalityMixShiftCopy {
  const ModalityMixShiftCopy({
    required this.observation,
    required this.suggestion,
  });

  final String observation;
  final String suggestion;
}

/// The modality the rule reports, or null when it abstains (D-1205–D-1210).
///
/// [measure] is the period payload's own measure; [recent] and [baseline] are
/// its own segments. The rule abstains when the measure is time, when the
/// baseline bar is empty, when the recent total is not above zero, or when no
/// modality fires.
///
/// A modality is regularly trained when its baseline share is at least
/// [kModalityMixShiftMinBaselineShare], compared as the exact fraction
/// `10 × baselineMeasure >= baselineTotal` (D-1206). It fires when its recent
/// share is strictly less than half its baseline share, compared as
/// `2 × recentMeasure × baselineTotal < baselineMeasure × recentTotal` — so
/// exactly half does not fire (D-1207). A modality absent from the recent bar
/// has a recent measure of zero and can still fire (D-1208).
///
/// Among the firing modalities the reported one has the smallest exact
/// `recentShare / baselineShare`, compared by cross-multiplication; an exact
/// tie resolves in [ExerciseSection] declaration order (D-1209).
ModalityMixShift? modalityMixShift({
  required MixMeasure measure,
  required List<MixSegment> recent,
  required List<MixSegment> baseline,
}) {
  if (measure != MixMeasure.load) return null;
  if (baseline.isEmpty) return null;

  final recentBySection = <ExerciseSection, MixSegment>{
    for (final segment in recent) segment.section: segment,
  };
  final baselineBySection = <ExerciseSection, MixSegment>{
    for (final segment in baseline) segment.section: segment,
  };

  final recentTotal = recent.fold<double>(0, (a, s) => a + s.measure);
  final baselineTotal = baseline.fold<double>(0, (a, s) => a + s.measure);
  if (recentTotal <= 0) return null;

  ExerciseSection? reported;
  var reportedRecentMeasure = 0.0;
  var reportedBaselineMeasure = 0.0;

  for (final section in ExerciseSection.values) {
    final baselineMeasure = baselineBySection[section]?.measure ?? 0;
    if (baselineMeasure <= 0) continue;
    // D-1206: `baselineMeasure / baselineTotal >= kModalityMixShiftMinBaselineShare`.
    if (10 * baselineMeasure < baselineTotal) continue;

    final recentMeasure = recentBySection[section]?.measure ?? 0;
    // D-1207: `recentMeasure / recentTotal < baselineMeasure / baselineTotal / 2`.
    if (2 * recentMeasure * baselineTotal >= baselineMeasure * recentTotal) {
      continue;
    }

    // D-1209: the smallest `recentMeasure / baselineMeasure`, cross-multiplied.
    if (reported == null ||
        recentMeasure * reportedBaselineMeasure <
            reportedRecentMeasure * baselineMeasure) {
      reported = section;
      reportedRecentMeasure = recentMeasure;
      reportedBaselineMeasure = baselineMeasure;
    }
  }

  if (reported == null) return null;

  // D-1212: the largest recent share, ties in declaration order.
  MixSegment? largest;
  for (final section in ExerciseSection.values) {
    final segment = recentBySection[section];
    if (segment == null) continue;
    if (largest == null || segment.measure > largest.measure) largest = segment;
  }
  final grown = largest != null && largest.section != reported ? largest : null;

  return ModalityMixShift(
    section: reported,
    recentPercent: recentBySection[reported]?.percent ?? 0,
    baselinePercent: baselineBySection[reported]!.percent,
    grownSection: grown?.section,
    grownPercent: grown?.percent,
  );
}

/// The card's copy for [shift] (D-1211–D-1213).
ModalityMixShiftCopy modalityMixShiftCopy(ModalityMixShift shift) {
  final observation = StringBuffer(
    '${shift.section.label} is ${shift.recentPercent}% of your load over the '
    'last ${kModalityMixShiftPeriodDays ~/ 7} weeks, down from its usual '
    '${shift.baselinePercent}%.',
  );
  if (shift.grownSection != null) {
    observation.write(
      ' ${shift.grownSection!.label} has grown to ${shift.grownPercent}%.',
    );
  }
  return ModalityMixShiftCopy(
    observation: observation.toString(),
    suggestion:
        '${modalityMixShiftArticle(shift.section)} '
        '${modalityMixShiftNoun(shift.section)} session this week would bring '
        'your mix back toward usual.',
  );
}

/// The noun the suggestion names [section] by (D-1213).
String modalityMixShiftNoun(ExerciseSection section) {
  switch (section) {
    case ExerciseSection.resistance:
      return 'lifting';
    case ExerciseSection.cardio:
      return 'cardio';
    case ExerciseSection.isometric:
      return 'isometric';
    case ExerciseSection.sports:
      return 'sports';
  }
}

/// The article the suggestion opens [section]'s noun with (D-1213).
String modalityMixShiftArticle(ExerciseSection section) =>
    section == ExerciseSection.isometric ? 'An' : 'A';
