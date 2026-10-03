// Stats PR 7a, Phase 1 — the Modality Mix Shift rule and its copy.
//
// The rule is pure Dart: `now` is not even a parameter, and there is no clock,
// no repository and no Flutter. Scenarios S-1901, S-1902, S-1903, S-1905,
// S-1906, S-1908, S-1910 and S-1911 of
// `docs/plans/2026-10-03-07a-stats-pr7a-mix-shift-plan/2026-10-03-07a-stats-pr7a-mix-shift-plan.md`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/exercise_metric.dart';
import 'package:omnitrain/core/models/modality_mix_shift.dart';
import 'package:omnitrain/core/models/signals.dart';
import 'package:omnitrain/core/models/training_load.dart';
import 'package:omnitrain/core/services/signals/modality_mix_shift_signal.dart';

/// The two shipped files this signal is allowed to be made of: its pure rule
/// and its thin adapter. A structural guard scans these and nothing else.
const List<String> _mixShiftSourceFiles = [
  'lib/core/models/modality_mix_shift.dart',
  'lib/core/services/signals/modality_mix_shift_signal.dart',
];

/// [path] with its comments stripped, so a guard fires on code and not on a
/// comment that merely names what the code must not do.
String _strippedSource(String path) {
  final source = File(
    path,
  ).readAsStringSync().replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  return source
      .split('\n')
      .map((line) {
        final i = line.indexOf('//');
        return i < 0 ? line : line.substring(0, i);
      })
      .join('\n');
}

/// One bar, built the way the service builds it, so the percents under test are
/// the shared `mixSegments` percents and never a hand-written number.
List<MixSegment> _bar(Map<ExerciseSection, double> measure) =>
    mixSegments(measure);

/// One rule call over two hand-built bars.
ModalityMixShift? _shift({
  MixMeasure measure = MixMeasure.load,
  required Map<ExerciseSection, double> recent,
  required Map<ExerciseSection, double> baseline,
}) => modalityMixShift(
  measure: measure,
  recent: _bar(recent),
  baseline: _bar(baseline),
);

void main() {
  group('modalityMixShift', () {
    test('S-1901 the pack example fires, naming Isometric and Resistance', () {
      final shift = _shift(
        recent: {
          ExerciseSection.resistance: 68,
          ExerciseSection.isometric: 5,
          ExerciseSection.sports: 27,
        },
        baseline: {
          ExerciseSection.resistance: 88,
          ExerciseSection.isometric: 12,
        },
      );

      expect(shift, isNotNull);
      expect(shift!.section, ExerciseSection.isometric);
      expect(shift.recentPercent, 5);
      expect(shift.baselinePercent, 12);
      expect(shift.grownSection, ExerciseSection.resistance);
      expect(shift.grownPercent, 68);

      final copy = modalityMixShiftCopy(shift);
      expect(
        copy.observation,
        'Isometric is 5% of your load over the last 4 weeks, down from its '
        'usual 12%. Resistance has grown to 68%.',
      );
      expect(
        copy.suggestion,
        'An isometric session this week would bring your mix back toward '
        'usual.',
      );
    });

    test('S-1902 exactly half does not fire', () {
      final shift = _shift(
        recent: {ExerciseSection.resistance: 94, ExerciseSection.isometric: 6},
        baseline: {
          ExerciseSection.resistance: 88,
          ExerciseSection.isometric: 12,
        },
      );

      expect(shift, isNull);
    });

    test('S-1903 below the regularly-trained floor never fires', () {
      final shift = _shift(
        recent: {ExerciseSection.resistance: 100},
        baseline: {
          ExerciseSection.resistance: 92,
          ExerciseSection.isometric: 8,
        },
      );

      expect(shift, isNull);
    });

    test('S-1905 the larger relative drop wins', () {
      final shift = _shift(
        recent: {
          ExerciseSection.resistance: 60,
          ExerciseSection.cardio: 8,
          ExerciseSection.isometric: 5,
          ExerciseSection.sports: 27,
        },
        baseline: {
          ExerciseSection.resistance: 60,
          ExerciseSection.cardio: 28,
          ExerciseSection.isometric: 12,
        },
      );

      expect(shift, isNotNull);
      expect(shift!.section, ExerciseSection.cardio);
      expect(shift.recentPercent, 8);
      expect(shift.baselinePercent, 28);
      expect(shift.grownSection, ExerciseSection.resistance);
      expect(shift.grownPercent, 60);
      expect(
        modalityMixShiftCopy(shift).observation,
        'Cardio is 8% of your load over the last 4 weeks, down from its usual '
        '28%. Resistance has grown to 60%.',
      );
    });

    test('S-1906 the regularly-trained threshold is exactly 10%', () {
      final shift = _shift(
        recent: {ExerciseSection.resistance: 96, ExerciseSection.isometric: 4},
        baseline: {
          ExerciseSection.resistance: 90,
          ExerciseSection.isometric: 10,
        },
      );

      expect(shift, isNotNull);
      expect(shift!.section, ExerciseSection.isometric);
      expect(shift.recentPercent, 4);
      expect(shift.baselinePercent, 10);
      expect(shift.grownSection, ExerciseSection.resistance);
      expect(shift.grownPercent, 96);

      final copy = modalityMixShiftCopy(shift);
      expect(
        copy.observation,
        'Isometric is 4% of your load over the last 4 weeks, down from its '
        'usual 10%. Resistance has grown to 96%.',
      );
      expect(
        copy.suggestion,
        'An isometric session this week would bring your mix back toward '
        'usual.',
      );
    });

    test('S-1908 the fire test is exact-fraction, not rounded-percentage', () {
      // Exact: 2 × 53 × 1000 = 106000 < 106 × 1000 = 106000 is false. A
      // rounded-percent reading (2 × 5 = 10 < 11) would fire.
      final shift = _shift(
        recent: {
          ExerciseSection.resistance: 947,
          ExerciseSection.isometric: 53,
        },
        baseline: {
          ExerciseSection.resistance: 894,
          ExerciseSection.isometric: 106,
        },
      );

      expect(shift, isNull);
    });

    test('S-1910 the second sentence is omitted when the reported modality is '
        'the largest', () {
      // D-1207 fires on the two shares, not on the two measures: the recent
      // bar's total is 46, so Cardio's 20 must fall under half of its usual
      // share (`2 × 20 × 100 = 4000 < 88 × 46 = 4048`). Cardio is also the
      // largest recent share, so D-1212 omits sentence two.
      final shift = _shift(
        recent: {
          ExerciseSection.cardio: 20,
          ExerciseSection.resistance: 18,
          ExerciseSection.isometric: 8,
        },
        baseline: {
          ExerciseSection.cardio: 88,
          ExerciseSection.resistance: 10,
          ExerciseSection.isometric: 2,
        },
      );

      expect(shift, isNotNull);
      expect(shift!.section, ExerciseSection.cardio);
      expect(shift.recentPercent, 44);
      expect(shift.baselinePercent, 88);
      expect(shift.grownSection, isNull);
      expect(shift.grownPercent, isNull);
      expect(
        modalityMixShiftCopy(shift).observation,
        'Cardio is 44% of your load over the last 4 weeks, down from its usual '
        '88%.',
      );
    });

    test('S-1911 an exact ratio tie resolves in declaration order', () {
      // 42 / 4 / 4 of 50: the shared `mixSegments` percents are exactly 84 / 8
      // / 8, so the copy reads the shared rounded percent and no
      // largest-remainder tie-break is in play. Cardio and Isometric fire with
      // the identical ratio `4 × 100 / (50 × 20)`, so D-1209 reports Cardio.
      final shift = _shift(
        recent: {
          ExerciseSection.resistance: 42,
          ExerciseSection.cardio: 4,
          ExerciseSection.isometric: 4,
        },
        baseline: {
          ExerciseSection.resistance: 60,
          ExerciseSection.cardio: 20,
          ExerciseSection.isometric: 20,
        },
      );

      expect(shift, isNotNull);
      expect(shift!.section, ExerciseSection.cardio);
      expect(shift.recentPercent, 8);
      expect(shift.baselinePercent, 20);
      expect(shift.grownSection, ExerciseSection.resistance);
      expect(shift.grownPercent, 84);
      expect(
        modalityMixShiftCopy(shift).observation,
        'Cardio is 8% of your load over the last 4 weeks, down from its usual '
        '20%. Resistance has grown to 84%.',
      );
    });

    test('an empty baseline abstains', () {
      final shift = _shift(
        recent: {ExerciseSection.resistance: 100},
        baseline: const {},
      );

      expect(shift, isNull);
    });

    test('a recent total of zero abstains', () {
      final shift = _shift(
        recent: const {},
        baseline: {ExerciseSection.resistance: 100},
      );

      expect(shift, isNull);
    });

    test('a modality absent from the recent bar reads 0% and fires', () {
      final shift = _shift(
        recent: {ExerciseSection.resistance: 100},
        baseline: {
          ExerciseSection.resistance: 80,
          ExerciseSection.isometric: 20,
        },
      );

      expect(shift, isNotNull);
      expect(shift!.section, ExerciseSection.isometric);
      expect(shift.recentPercent, 0);
      expect(shift.baselinePercent, 20);
      expect(shift.grownSection, ExerciseSection.resistance);
      expect(shift.grownPercent, 100);
      expect(
        modalityMixShiftCopy(shift).observation,
        'Isometric is 0% of your load over the last 4 weeks, down from its '
        'usual 20%. Resistance has grown to 100%.',
      );
    });

    test('the time measure abstains', () {
      final shift = _shift(
        measure: MixMeasure.time,
        recent: {ExerciseSection.resistance: 100},
        baseline: {
          ExerciseSection.resistance: 80,
          ExerciseSection.isometric: 20,
        },
      );

      expect(shift, isNull);
    });
  });

  group('the copy helpers', () {
    test('the noun and article name each modality', () {
      expect(modalityMixShiftNoun(ExerciseSection.resistance), 'lifting');
      expect(modalityMixShiftNoun(ExerciseSection.cardio), 'cardio');
      expect(modalityMixShiftNoun(ExerciseSection.isometric), 'isometric');
      expect(modalityMixShiftNoun(ExerciseSection.sports), 'sports');

      expect(modalityMixShiftArticle(ExerciseSection.resistance), 'A');
      expect(modalityMixShiftArticle(ExerciseSection.cardio), 'A');
      expect(modalityMixShiftArticle(ExerciseSection.isometric), 'An');
      expect(modalityMixShiftArticle(ExerciseSection.sports), 'A');
    });
  });

  group('the structural guards', () {
    test('D-1207 the half-share test compares exact fractions, not the two '
        'rounded percentages', () {
      // The fixture is built so the exact share and the floored share straddle
      // the half-share boundary: isometric is 106/1000 = 10.6% of the baseline
      // (rounded 11%) and 53/1000 = 5.3% of the recent bar (rounded 5%). The
      // rounded reading `2 × 5 = 10 < 11` fires; the exact reading
      // `2 × 53 × 1000 = 106000 < 106 × 1000 = 106000` does not. The rule must
      // read the segments' exact `measure`, so the card must not appear.
      final recent = _bar({
        ExerciseSection.resistance: 947,
        ExerciseSection.isometric: 53,
      });
      final baseline = _bar({
        ExerciseSection.resistance: 894,
        ExerciseSection.isometric: 106,
      });

      // The rounded percentages really do straddle the boundary — otherwise
      // this guard would pass for the wrong reason.
      final recentIsometric = recent.firstWhere(
        (s) => s.section == ExerciseSection.isometric,
      );
      final baselineIsometric = baseline.firstWhere(
        (s) => s.section == ExerciseSection.isometric,
      );
      expect(recentIsometric.percent, 5);
      expect(baselineIsometric.percent, 11);
      expect(2 * recentIsometric.percent < baselineIsometric.percent, isTrue);

      expect(
        modalityMixShift(
          measure: MixMeasure.load,
          recent: recent,
          baseline: baseline,
        ),
        isNull,
      );
    });

    test('the rule derives no percentage of its own', () {
      // The rounded percentages are `mixSegments`' alone (D-912, D-1205). A
      // local `* 100 / total`, a `round()` or a `toStringAsFixed` in either
      // shipped file would be a second definition of the share and could drift
      // from the bar the Mix layer renders.
      const forbidden = <String>[
        '* 100',
        'round(',
        'toStringAsFixed',
        'percent =',
      ];
      for (final path in _mixShiftSourceFiles) {
        final source = _strippedSource(path);
        for (final identifier in forbidden) {
          expect(
            source.contains(identifier),
            isFalse,
            reason: '$path must not derive a percentage of its own '
                '("$identifier"); the shares come from the payload\'s own '
                'segments (D-1205)',
          );
        }
      }
    });

    test('the adapter walks no history of its own', () {
      // The signal is a thin adapter: it asks `StatsProgressService` for the
      // period payload and hands that payload's own segments to the rule. A
      // repository read, a window-scoped walk or a second entry point would be
      // a second source of the figures the Mix layer shows (D-1204, D-1205).
      const forbidden = <String>[
        'context.repository',
        'computeMixLayer',
        'computeTotals',
        'computeProgressData',
        'getAllSessions',
        'getSessionsByDateRange',
        'getSegmentsBySession',
        'getEffortsBySegment',
      ];
      final source = _strippedSource(
        'lib/core/services/signals/modality_mix_shift_signal.dart',
      );
      for (final identifier in forbidden) {
        expect(
          source.contains(identifier),
          isFalse,
          reason: 'the adapter must not walk history itself ("$identifier"); '
              'it calls computeMixPeriod and nothing else (D-1204)',
        );
      }
      expect(source.contains('computeMixPeriod'), isTrue);
    });

    test('the registered signal declares the contract the docs describe', () {
      const signal = ModalityMixShiftSignal();
      expect(signal.id, 'modality-mix-shift');
      expect(signal.kind, SignalKind.caution);
      expect(signal.priority, kModalityMixShiftPriority);
    });

    test('the constant contracts', () {
      // The three constants the docs name. A changed value is a changed rule:
      // the period span, the regularly-trained floor and the caution order's
      // place for this signal.
      expect(kModalityMixShiftPeriodDays, 28);
      expect(kModalityMixShiftMinBaselineShare, 0.10);
      expect(kModalityMixShiftPriority, 400);
    });
  });
}
