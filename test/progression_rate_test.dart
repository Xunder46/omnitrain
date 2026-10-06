// Stats PR 6b, Phase 1 — the Progression Rate's pure math.
//
// The two windows, the exercise-session samples they count, the rates and the
// three thresholds are pure Dart: `now` is a parameter, and there is no clock
// and no repository. Scenarios S-1802 … S-1809 of
// `docs/plans/2026-10-03-06b-stats-pr6b-progression-rate-plan/2026-10-03-06b-stats-pr6b-progression-rate-plan.md`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/progression_rate.dart';
import 'package:omnitrain/core/models/signals.dart';
import 'package:omnitrain/core/services/signals/progression_rate_signal.dart';

/// The fixtures' fixed `now`, so both window boundaries are exact instants.
final DateTime _now = DateTime(2026, 10, 3, 12);

/// The session grid every 20-counted fixture uses: one first-ever session, four
/// in the prior window and four in the recent window.
const List<int> _grid = [61, 54, 47, 40, 33, 26, 19, 12, 5];

int _at(int daysAgo) =>
    _now.subtract(Duration(days: daysAgo)).millisecondsSinceEpoch;

/// Samples for [id] at the given `(daysAgo, value)` points.
List<ProgressionSample> _points(String id, List<(int, double)> points) => [
  for (final point in points)
    ProgressionSample(
      exerciseId: id,
      sessionStartMs: _at(point.$1),
      value: point.$2,
    ),
];

/// One exercise on [days], valued from [first] by [pattern]: a `true` entry
/// steps up and a `false` entry steps down, so the realised comparisons match
/// the pattern exactly. `pattern[0..3]` are the prior window's comparisons and
/// `pattern[4..7]` the recent window's.
List<ProgressionSample> _exercise(
  String id,
  List<bool> pattern, {
  double first = 100,
  List<int> days = _grid,
}) {
  final values = <double>[first];
  for (final progressed in pattern) {
    values.add(progressed ? values.last + 1 : values.last - 1);
  }
  return [
    for (var i = 0; i < days.length; i++)
      ProgressionSample(
        exerciseId: id,
        sessionStartMs: _at(days[i]),
        value: values[i],
      ),
  ];
}

/// Five exercises with the given prior/recent progression patterns, so each
/// period holds twenty counted comparisons.
List<ProgressionSample> _twenty(
  List<bool> priorA,
  List<bool> recentA,
  List<bool> priorB,
  List<bool> recentB,
  List<bool> priorC,
  List<bool> recentC,
  List<bool> priorD,
  List<bool> recentD,
  List<bool> priorE,
  List<bool> recentE,
) => [
  ..._exercise('a', [...priorA, ...recentA]),
  ..._exercise('b', [...priorB, ...recentB]),
  ..._exercise('c', [...priorC, ...recentC]),
  ..._exercise('d', [...priorD, ...recentD]),
  ..._exercise('e', [...priorE, ...recentE]),
];

/// Samples for one exercise with exactly [priorCounted] and [recentCounted]
/// counted comparisons, of which [priorProgressions] and [recentProgressions]
/// step up. The sessions sit on distinct instants inside each window, so the
/// counts are hit exactly rather than through a rounded fixture.
List<ProgressionSample> _counted(
  String id, {
  required int priorCounted,
  required int priorProgressions,
  required int recentCounted,
  required int recentProgressions,
}) {
  final samples = <ProgressionSample>[
    ProgressionSample(exerciseId: id, sessionStartMs: _at(61), value: 100),
  ];
  var value = 100.0;
  for (var i = 0; i < priorCounted; i++) {
    value += i < priorProgressions ? 1 : -1;
    samples.add(
      ProgressionSample(
        exerciseId: id,
        sessionStartMs: _at(40) + i,
        value: value,
      ),
    );
  }
  for (var i = 0; i < recentCounted; i++) {
    value += i < recentProgressions ? 1 : -1;
    samples.add(
      ProgressionSample(
        exerciseId: id,
        sessionStartMs: _at(10) + i,
        value: value,
      ),
    );
  }
  return samples;
}

/// The two shipped files this signal is allowed to be made of: its pure math
/// and its thin adapter. A structural guard scans these and nothing else.
const List<String> _progressionSourceFiles = [
  'lib/core/models/progression_rate.dart',
  'lib/core/services/signals/progression_rate_signal.dart',
];

/// [path] with its comments stripped, so a guard fires on code and not on a
/// comment that merely names what the code must not do.
String _strippedSource(String path) {
  final source = File(path)
      .readAsStringSync()
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  return source
      .split('\n')
      .map((line) {
        final i = line.indexOf('//');
        return i < 0 ? line : line.substring(0, i);
      })
      .join('\n');
}

void main() {
  group('the two windows and the qualification test', () {
    test('S-1802 a 5-point improvement shows nothing', () {
      // Prior 15/20 = 75%, recent 16/20 = 80%: the improvement is 5 points.
      final samples = _twenty(
        [true, true, true, true],
        [true, true, true, true],
        [true, true, true, false],
        [true, true, true, false],
        [true, true, true, false],
        [true, true, true, false],
        [true, true, true, false],
        [true, true, true, false],
        [true, true, false, false],
        [true, true, true, false],
      );

      expect(progressionRate(samples: samples, now: _now), isNull);
    });

    test('S-1803 a high improvement on a low rate shows nothing', () {
      // Prior 10/20 = 50%, recent 14/20 = 70%: the rate is under the floor.
      final samples = _twenty(
        [true, true, false, false],
        [true, true, true, false],
        [true, true, false, false],
        [true, true, true, false],
        [true, true, false, false],
        [true, true, true, false],
        [true, true, false, false],
        [true, true, true, false],
        [true, true, false, false],
        [true, true, false, false],
      );

      expect(progressionRate(samples: samples, now: _now), isNull);
    });

    test('S-1804 seven counted sessions in the recent period shows nothing', () {
      final samples = <ProgressionSample>[
        for (final id in ['a', 'b', 'c', 'd', 'e'])
          ..._points(id, [
            (61, 100),
            (54, 99),
            (47, 98),
            (40, 97),
            (33, 96),
          ]),
        ..._points('a', [(26, 200), (19, 201)]),
        ..._points('b', [(26, 200), (19, 201)]),
        ..._points('c', [(26, 200), (19, 201)]),
        ..._points('d', [(26, 200)]),
      ];

      expect(progressionRate(samples: samples, now: _now), isNull);
    });

    test('S-1804 seven counted sessions in the prior period shows nothing', () {
      final samples = <ProgressionSample>[
        for (final id in ['a', 'b', 'c', 'd', 'e'])
          ..._points(id, [
            (61, 100),
            (26, 200),
            (19, 201),
            (12, 202),
            (5, 203),
          ]),
        ..._points('a', [(54, 99), (47, 98)]),
        ..._points('b', [(54, 99), (47, 98)]),
        ..._points('c', [(54, 99), (47, 98)]),
        ..._points('d', [(54, 99)]),
      ];

      expect(progressionRate(samples: samples, now: _now), isNull);
    });

    test('S-1805 exactly 75% and exactly +10 points shows the card', () {
      // Prior 13/20 = 65%, recent 15/20 = 75%.
      final samples = _twenty(
        [true, true, true, true],
        [true, true, true, true],
        [true, true, true, false],
        [true, true, true, false],
        [true, true, true, false],
        [true, true, true, false],
        [true, true, false, false],
        [true, true, true, false],
        [true, false, false, false],
        [true, true, false, false],
      );

      final rate = progressionRate(samples: samples, now: _now);

      expect(rate, isNotNull);
      expect(rate!.recentCounted, 20);
      expect(rate.priorCounted, 20);
      expect(rate.recentRate, 0.75);
      expect(rate.recentPercent, 75);
      expect(rate.priorPercent, 65);
    });

    test('S-1805 exactly +10 points on 80% shows the card', () {
      // Prior 14/20 = 70%, recent 16/20 = 80%.
      final samples = _twenty(
        [true, true, true, true],
        [true, true, true, true],
        [true, true, true, false],
        [true, true, true, false],
        [true, true, true, false],
        [true, true, true, false],
        [true, true, true, false],
        [true, true, true, false],
        [true, false, false, false],
        [true, true, true, false],
      );

      final rate = progressionRate(samples: samples, now: _now);

      expect(rate, isNotNull);
      expect(rate!.recentRate, 0.8);
      expect(rate.priorRate, 0.7);
      expect(rate.recentPercent, 80);
      expect(rate.priorPercent, 70);
    });

    test('S-1805 exactly eight counted sessions in each period shows the card', () {
      final samples = [
        ..._exercise('a', [false, false, false, false, true, true, true, true]),
        ..._exercise('b', [false, false, false, false, true, true, true, true]),
      ];

      final rate = progressionRate(samples: samples, now: _now);

      expect(rate, isNotNull);
      expect(rate!.recentCounted, 8);
      expect(rate.priorCounted, 8);
      expect(rate.recentPercent, 100);
    });
  });

  group('the ordering and the exclusions', () {
    test('D-1105 a predecessor outside both windows still decides the comparison', () {
      final samples = <ProgressionSample>[
        // The 60-day sample is outside both windows and is this exercise's
        // first-ever, so it is dropped; the 54-day sample compares against it
        // and is counted in the prior window.
        ..._points('a', [
          (60, 200),
          (54, 100),
          (47, 101),
          (40, 102),
          (33, 103),
          (26, 104),
          (19, 105),
          (12, 106),
          (5, 107),
        ]),
        ..._exercise('b', [true, true, true, true, true, true, true, true]),
      ];

      final rate = progressionRate(samples: samples, now: _now);

      expect(rate, isNotNull);
      expect(rate!.priorCounted, 8);
      expect(rate.recentCounted, 8);
    });

    test('D-1104 a session with no readable value is not counted', () {
      final samples = <ProgressionSample>[
        ..._exercise('a', [false, false, false, false, true, true, true, true]),
        ..._exercise('b', [false, false, false, false, true, true, true, true]),
        // The 54-day zero is dropped, so this exercise's first-ever is the
        // 61-day sample and its 47-day sample is counted, not a progression.
        ..._points('c', [(61, 100), (54, 0), (47, 50)]),
      ];

      final rate = progressionRate(samples: samples, now: _now);

      expect(rate, isNotNull);
      expect(rate!.priorCounted, 9);
      expect(rate.priorProgressions, 0);
      expect(rate.recentCounted, 8);
    });

    test('D-1106 the recent window starts at exactly now minus 28 days', () {
      final samples = _points('a', [
        (57, 100),
        (56, 90),
        (55, 91),
        (54, 92),
        (53, 93),
        (46, 94),
        (39, 95),
        (32, 96),
        (31, 97),
        (28, 98),
        (27, 99),
        (26, 100),
        (25, 101),
        (18, 102),
        (11, 103),
        (4, 104),
        (3, 105),
      ]);

      final rate = progressionRate(samples: samples, now: _now);

      expect(rate, isNotNull);
      expect(rate!.priorCounted, 8);
      expect(rate.recentCounted, 8);
      expect(rate.recentPercent, 100);
      expect(rate.priorPercent, 88);
    });
  });

  group('the rates and the copy', () {
    test('S-1806 an exact tie counts as a progression', () {
      final samples = <ProgressionSample>[
        // The 26-day value ties the 33-day value exactly.
        ..._points('a', [
          (61, 100),
          (54, 99),
          (47, 98),
          (40, 97),
          (33, 96),
          (26, 96),
          (19, 97),
          (12, 98),
          (5, 99),
        ]),
        ..._exercise('b', [false, false, false, false, true, true, true, true]),
      ];

      final rate = progressionRate(samples: samples, now: _now);

      expect(rate, isNotNull);
      expect(rate!.recentCounted, 8);
      expect(rate.recentProgressions, 8);
      expect(rate.recentPercent, 100);
    });

    test('S-1809 a worse value is counted but is not a progression', () {
      final samples = <ProgressionSample>[
        ..._exercise('a', [false, false, false, false, true, true, true, true]),
        ..._exercise('b', [false, false, false, false, true, true, true, false]),
      ];

      final rate = progressionRate(samples: samples, now: _now);

      expect(rate, isNotNull);
      expect(rate!.recentCounted, 8);
      expect(rate.recentProgressions, 7);
      expect(rate.recentPercent, 88);
    });

    test('D-1107 only the display is rounded', () {
      final samples = [
        ..._exercise('a', [false, false, false, false, true, true, true, true]),
        ..._exercise('b', [false, false, false, false, true, true, true, false]),
      ];

      final rate = progressionRate(samples: samples, now: _now);

      expect(rate!.recentRate, 7 / 8);
      expect(rate.recentPercent, 88);
    });

    test('D-1109 the observation and the suggestion', () {
      final rate = ProgressionRate.fromCounts(
        recentProgressions: 16,
        recentCounted: 20,
        priorProgressions: 13,
        priorCounted: 20,
      );

      final copy = progressionRateCopy(rate);

      expect(
        copy.observation,
        'Resistance progression rate is 80% over the last 4 weeks, up from 65%.',
      );
      expect(copy.suggestion, 'The current approach is working.');
    });
  });

  group('the structural guards', () {
    test('D-1108 the qualification test compares exact fractions, not the '
        'rounded percentages', () {
      // Fixture A: recent 299/400 = 74.75% against prior 260/400 = 65%. The
      // two percentages the card would display are 75% and 65% — a 10-point
      // improvement that passes every displayed threshold — but the exact
      // recent rate is under 3/4, so no card may show.
      final a = _counted(
        'a',
        priorCounted: 400,
        priorProgressions: 260,
        recentCounted: 400,
        recentProgressions: 299,
      );
      final aDisplayed = ProgressionRate.fromCounts(
        recentProgressions: 299,
        recentCounted: 400,
        priorProgressions: 260,
        priorCounted: 400,
      );
      expect(aDisplayed.recentPercent, 75);
      expect(aDisplayed.priorPercent, 65);
      expect(aDisplayed.recentPercent - aDisplayed.priorPercent, 10);
      expect(progressionRate(samples: a, now: _now), isNull);

      // Fixture B: recent 159/200 = 79.5% against prior 140/200 = 70%. The
      // displayed percentages are 80% and 70% — exactly +10 points — but the
      // exact improvement is 9.5 points, under 1/10, so no card may show.
      final b = _counted(
        'b',
        priorCounted: 200,
        priorProgressions: 140,
        recentCounted: 200,
        recentProgressions: 159,
      );
      final bDisplayed = ProgressionRate.fromCounts(
        recentProgressions: 159,
        recentCounted: 200,
        priorProgressions: 140,
        priorCounted: 200,
      );
      expect(bDisplayed.recentPercent, 80);
      expect(bDisplayed.priorPercent, 70);
      expect(bDisplayed.recentPercent - bDisplayed.priorPercent, 10);
      expect(progressionRate(samples: b, now: _now), isNull);
    });

    test('the new files compute no estimated 1RM of their own', () {
      // The estimated-1RM formula lives once, in
      // `StatsProgressService.epley1RM` (`weight * (1 + reps / 30)`). A local
      // copy — the `0.0333` slope, the `reps / 30` shape, or an `Epley`
      // constant — would be a second definition and could drift from the
      // helper the Instruments rows already use (D-1101).
      const forbidden = <String>['0.0333', 'epley', 'reps / 30', '1 + reps'];
      for (final path in _progressionSourceFiles) {
        final source = _strippedSource(path).toLowerCase();
        for (final identifier in forbidden) {
          expect(
            source.contains(identifier),
            isFalse,
            reason: '$path must not define its own estimated 1RM '
                '("$identifier"); it must use the shared '
                'StatsProgressService.epley1RM through the sample walk',
          );
        }
      }
    });

    test('the registered signal declares the contract the docs describe', () {
      const signal = ProgressionRateSignal();
      expect(signal.id, 'progression-rate');
      expect(signal.kind, SignalKind.positive);
      expect(signal.priority, kProgressionRatePriority);
    });

    test('the new files call no personal-record API', () {
      // A progression compares a session with the exercise's previous
      // session; a personal record compares strictly with the all-time best,
      // so a tie counts here and is not a PR (D-1111). These are the PR
      // path's names as used by `test/in_session_pr_toast_test.dart`: the
      // standing-best queries and the source-of-truth helper.
      const forbidden = <String>[
        'getAllTimeBestE1RM',
        'getAllTimeBestReps',
        'epley1RM',
      ];
      for (final path in _progressionSourceFiles) {
        final source = _strippedSource(path);
        for (final identifier in forbidden) {
          expect(
            source.contains(identifier),
            isFalse,
            reason: '$path must not call the PR API ("$identifier") — a tie '
                'is a progression, not a PR (D-1111)',
          );
        }
      }
    });
  });
}
