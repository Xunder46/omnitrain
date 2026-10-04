// Stats PR 8b, Phase 1 — the Protein Consistency rule and its copy.
//
// The rule is pure Dart: `now` is a parameter, so there is no clock, no
// repository and no Flutter. Scenarios S-2201…S-2213 of
// `docs/plans/2026-10-03-08b-stats-pr8b-protein-consistency-plan/2026-10-03-08b-stats-pr8b-protein-consistency-plan.md`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/nutrition_consistency.dart';
import 'package:omnitrain/core/models/protein_consistency.dart';

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

/// Local midnight [daysAgo] local calendar days before [anchor].
DateTime _day(DateTime anchor, int daysAgo) =>
    DateTime(anchor.year, anchor.month, anchor.day - daysAgo);

/// S-2201's window rows: one [ProteinDay] on each of days [first]…[last], each
/// at [protein] grams.
List<ProteinDay> _rows({
  required DateTime anchor,
  double protein = 120,
  int first = 13,
  int last = 2,
}) => [
  for (var n = first; n >= last; n--)
    ProteinDay(day: _day(anchor, n), protein: protein),
];

/// A stored target of [protein] grams on each of days [first]…[last].
Map<DateTime, double> _targets({
  required DateTime anchor,
  double protein = 150,
  int first = 0,
  int last = 13,
}) => {for (var n = first; n <= last; n++) _day(anchor, n): protein};

/// One 7-day baseline block starting [startDaysAgo] with [logged] of its days
/// logged at [protein] grams.
List<ProteinDay> _block({
  required DateTime anchor,
  required int startDaysAgo,
  required int logged,
  double protein = 145,
}) => [
  for (var i = 0; i < logged; i++)
    ProteinDay(day: _day(anchor, startDaysAgo - i), protein: protein),
];

/// S-2205's baseline: the blocks starting day(69) and day(62) have 7 of 7 days
/// logged at 145 g; the other six have 3 of 7.
List<ProteinDay> _usualBaseline({required DateTime anchor}) => [
  ..._block(anchor: anchor, startDaysAgo: 69, logged: 7),
  ..._block(anchor: anchor, startDaysAgo: 62, logged: 7),
  for (final start in const [55, 48, 41, 34, 27, 20])
    ..._block(anchor: anchor, startDaysAgo: start, logged: 3),
];

/// S-2212's baseline: all eight blocks have exactly 3 of 7 days logged.
List<ProteinDay> _sparseBaseline({required DateTime anchor}) => [
  for (final start in const [69, 62, 55, 48, 41, 34, 27, 20])
    ..._block(anchor: anchor, startDaysAgo: start, logged: 3),
];

/// One rule call over the hand-built figures.
ProteinConsistency? _rule({
  required DateTime anchor,
  List<ProteinDay>? recentDays,
  Map<DateTime, double> proteinTargets = const {},
  int resistanceSessions = 3,
  List<ProteinDay> baselineDays = const [],
  double? bodyWeightKg,
}) => proteinConsistency(
  now: anchor,
  recentDays: recentDays ?? _rows(anchor: anchor),
  proteinTargets: proteinTargets,
  resistanceSessions: resistanceSessions,
  baselineDays: baselineDays,
  bodyWeightKg: bodyWeightKg,
);

void main() {
  final anchor = DateTime(2026, 6, 15, 10, 30);

  test('the constant contracts', () {
    expect(kProteinConsistencyWindowDays, 14);
    expect(kProteinConsistencyMinLoggedDays, 10);
    expect(kProteinConsistencyShortfallPercent, 15);
    expect(kProteinConsistencyMinResistanceSessions, 2);
    expect(kProteinConsistencyMinBaselineWeeks, 2);
    expect(kProteinConsistencyBaselineWeeks, 8);
    expect(kProteinGuidancePerKg, 1.6);
    expect(kProteinConsistencyPriority, 200);
  });

  test('S-2201 the pack row fires with the target comparison', () {
    final rows = _rows(anchor: anchor);
    final targets = _targets(anchor: anchor);

    expect(proteinConsistencyGate(recentDays: rows), isTrue);
    expect(
      proteinConsistencyTargetMode(recentDays: rows, proteinTargets: targets),
      isTrue,
    );
    // D-1508's boundary is inclusive: exactly 15% below still fires.
    expect(
      proteinShortfallTestAgainstTarget(recentTotal: 1530, targetSum: 1800),
      isTrue,
    );
    expect(
      proteinShortfallTestAgainstTarget(recentTotal: 1440, targetSum: 1800),
      isTrue,
    );

    final result = _rule(anchor: anchor, proteinTargets: targets);
    expect(result, isNotNull);
    expect(result!.mode, ProteinComparisonMode.target);
    expect(result.average, 120);
    expect(result.comparisonMean, 150);
    expect(result.perKg, isNull);

    final copy = proteinConsistencyCopy(result);
    expect(
      copy.observation,
      'Protein has averaged 120 g/day over the last 2 weeks, about 20% under '
      'your 150 g target.',
    );
    expect(
      copy.suggestion,
      'Bringing protein back toward your target is one option.',
    );
  });

  test('S-2202 13% under shows nothing', () {
    expect(
      proteinShortfallTestAgainstTarget(recentTotal: 1560, targetSum: 1800),
      isFalse,
    );
    expect(
      _rule(
        anchor: anchor,
        recentDays: _rows(anchor: anchor, protein: 130),
        proteinTargets: _targets(anchor: anchor),
      ),
      isNull,
    );
  });

  test('S-2203 9 of 14 logged days shows nothing', () {
    final rows = _rows(anchor: anchor, protein: 100, last: 5);
    expect(rows.length, 9);
    expect(proteinConsistencyGate(recentDays: rows), isFalse);
    expect(
      _rule(
        anchor: anchor,
        recentDays: rows,
        proteinTargets: _targets(anchor: anchor),
      ),
      isNull,
    );
  });

  test('S-2204 exactly 10 of 14 logged days fires', () {
    final rows = [
      ..._rows(anchor: anchor, protein: 120, first: 13, last: 10),
      ..._rows(anchor: anchor, protein: 130, first: 9, last: 4),
    ];
    expect(rows.length, 10);
    expect(proteinConsistencyGate(recentDays: rows), isTrue);

    final result = _rule(
      anchor: anchor,
      recentDays: rows,
      proteinTargets: _targets(anchor: anchor),
      resistanceSessions: 2,
    );
    expect(result, isNotNull);
    expect(result!.average, 126);
    expect(
      proteinConsistencyCopy(result).observation,
      'Protein has averaged 126 g/day over the last 2 weeks, about 16% under '
      'your 150 g target.',
    );
  });

  test('S-2205 the own baseline pools consistent weeks and divides by '
      'logged days', () {
    final baseline = _usualBaseline(anchor: anchor);
    // D-1509: the eight blocks abut the window — day(69)…day(20), with the
    // block ending day(14) the last full week before it.
    expect(
      weekBlockStarts(
        anchorDay: _day(anchor, 14),
        weeks: kProteinConsistencyBaselineWeeks,
      ),
      [
        _day(anchor, 69),
        _day(anchor, 62),
        _day(anchor, 55),
        _day(anchor, 48),
        _day(anchor, 41),
        _day(anchor, 34),
        _day(anchor, 27),
        _day(anchor, 20),
      ],
    );

    final pool = proteinBaselinePool(now: anchor, baselineDays: baseline);
    expect(pool.consistentBlocks, 2);
    expect(pool.total, 2030);
    expect(pool.days, 14);
    expect(pool.mean, 145);

    // (a) 12 logged days at 118 g.
    expect(
      proteinShortfallTestAgainstBaseline(
        recentTotal: 1416,
        recentDays: 12,
        usualTotal: 2030,
        usualDays: 14,
      ),
      isTrue,
    );
    final fired = _rule(
      anchor: anchor,
      recentDays: _rows(anchor: anchor, protein: 118),
      baselineDays: baseline,
    );
    expect(fired, isNotNull);
    expect(fired!.mode, ProteinComparisonMode.ownBaseline);
    expect(fired.comparisonMean, 145);
    expect(
      proteinConsistencyCopy(fired).observation,
      'Protein has averaged 118 g/day over the last 2 weeks, down from your '
      'usual 145 g.',
    );

    // (b) 10 logged days at 145 g: the same usual level is a 0% shortfall.
    expect(
      proteinShortfallTestAgainstBaseline(
        recentTotal: 1450,
        recentDays: 10,
        usualTotal: 2030,
        usualDays: 14,
      ),
      isFalse,
    );
    expect(
      _rule(
        anchor: anchor,
        recentDays: _rows(anchor: anchor, protein: 145, last: 4),
        baselineDays: baseline,
      ),
      isNull,
    );
  });

  test('S-2206 no target with a bodyweight on file shows the per-kilogram '
      'figure', () {
    final result = _rule(
      anchor: anchor,
      recentDays: _rows(anchor: anchor, protein: 118),
      baselineDays: _usualBaseline(anchor: anchor),
      bodyWeightKg: 70,
    );
    expect(result, isNotNull);
    // 118 / 70 = 1.6857 -> 1.7. The latest measurement (70 kg) is the one the
    // adapter passes; choosing it from the history is the service's read.
    expect(result!.perKg, 1.7);
    final copy = proteinConsistencyCopy(result);
    expect(
      copy.observation,
      'Protein has averaged 118 g/day (1.7 g/kg) over the last 2 weeks, down '
      'from your usual 145 g.',
    );
    expect(
      copy.suggestion,
      'Commonly cited guidance for strength training is around 1.6 g/kg of '
      'bodyweight.',
    );
  });

  test('S-2207 no target and no bodyweight carries no suggestion', () {
    final result = _rule(
      anchor: anchor,
      recentDays: _rows(anchor: anchor, protein: 118),
      baselineDays: _usualBaseline(anchor: anchor),
    );
    expect(result, isNotNull);
    final copy = proteinConsistencyCopy(result!);
    expect(
      copy.observation,
      'Protein has averaged 118 g/day over the last 2 weeks, down from your '
      'usual 145 g.',
    );
    expect(copy.observation, isNot(contains('g/kg')));
    expect(copy.observation, isNot(contains('(')));
    expect(copy.suggestion, isNull);
  });

  test('S-2208 a target suppresses the reference', () {
    final result = _rule(
      anchor: anchor,
      proteinTargets: _targets(anchor: anchor),
      bodyWeightKg: 70,
    );
    expect(result, isNotNull);
    expect(result!.perKg, 1.7);
    final copy = proteinConsistencyCopy(result);
    expect(
      copy.observation,
      'Protein has averaged 120 g/day (1.7 g/kg) over the last 2 weeks, about '
      '20% under your 150 g target.',
    );
    expect(
      copy.suggestion,
      'Bringing protein back toward your target is one option.',
    );
    expect(copy.observation, isNot(contains('1.6')));
    expect(copy.suggestion, isNot(contains('1.6')));
    expect(copy.suggestion, isNot(contains('g/kg')));
  });

  test('S-2209 the resistance gate', () {
    final targets = _targets(anchor: anchor);
    // (a) exactly two completed resistance sessions.
    expect(
      _rule(anchor: anchor, proteinTargets: targets, resistanceSessions: 2),
      isNotNull,
    );
    // (b) one.
    expect(
      _rule(anchor: anchor, proteinTargets: targets, resistanceSessions: 1),
      isNull,
    );
    // (c) three completed sessions with no resistance effort — the count of
    // resistance sessions is zero; classifying efforts is the adapter's job.
    expect(
      _rule(anchor: anchor, proteinTargets: targets, resistanceSessions: 0),
      isNull,
    );
    // (d) one qualifying session: the pre-window and in-progress ones do not
    // count, so the gate sees one.
    expect(
      _rule(anchor: anchor, proteinTargets: targets, resistanceSessions: 1),
      isNull,
    );
  });

  test('S-2210 a target changed mid-window is read per day and averaged', () {
    final targets = {
      for (var n = 7; n <= 13; n++) _day(anchor, n): 150.0,
      for (var n = 0; n <= 6; n++) _day(anchor, n): 160.0,
    };
    final result = _rule(anchor: anchor, proteinTargets: targets);
    expect(result, isNotNull);
    expect(result!.mode, ProteinComparisonMode.target);
    expect(result.comparisonMean, closeTo(154.1667, 0.001));
    expect(
      proteinConsistencyCopy(result).observation,
      'Protein has averaged 120 g/day over the last 2 weeks, about 22% under '
      'your 154 g target.',
    );
  });

  test('S-2211 a mixed window falls back to the own baseline', () {
    final targets = {
      for (var n = 7; n <= 13; n++) _day(anchor, n): 150.0,
      for (var n = 0; n <= 6; n++) _day(anchor, n): 0.0,
    };
    expect(
      proteinConsistencyTargetMode(
        recentDays: _rows(anchor: anchor),
        proteinTargets: targets,
      ),
      isFalse,
    );
    final result = _rule(
      anchor: anchor,
      recentDays: _rows(anchor: anchor, protein: 118),
      proteinTargets: targets,
      baselineDays: _usualBaseline(anchor: anchor),
    );
    expect(result, isNotNull);
    expect(result!.mode, ProteinComparisonMode.ownBaseline);
    final observation = proteinConsistencyCopy(result).observation;
    expect(
      observation,
      'Protein has averaged 118 g/day over the last 2 weeks, down from your '
      'usual 145 g.',
    );
    expect(observation, isNot(contains('target')));
  });

  test('S-2212 fewer than two consistent baseline weeks shows nothing', () {
    // The scenario's fixture: all eight blocks are 3 of 7 days, so no block is
    // consistent and nothing is pooled — no day is zero-filled to reach a
    // figure.
    final sparse = proteinBaselinePool(
      now: anchor,
      baselineDays: _sparseBaseline(anchor: anchor),
    );
    expect(sparse.consistentBlocks, 0);
    expect(sparse.days, 0);
    expect(sparse.total, 0);
    expect(sparse.mean, isNull);
    expect(
      _rule(
        anchor: anchor,
        recentDays: _rows(anchor: anchor, protein: 80),
        baselineDays: _sparseBaseline(anchor: anchor),
      ),
      isNull,
    );

    // The boundary: exactly one consistent block (5 of 7 days) is still fewer
    // than [kProteinConsistencyMinBaselineWeeks], so the card abstains even
    // though the apparent shortfall is large.
    final oneBlock = [
      ..._block(anchor: anchor, startDaysAgo: 69, logged: 5),
      for (final start in const [62, 55, 48, 41, 34, 27, 20])
        ..._block(anchor: anchor, startDaysAgo: start, logged: 3),
    ];
    final pool = proteinBaselinePool(now: anchor, baselineDays: oneBlock);
    expect(pool.consistentBlocks, 1);
    expect(pool.mean, 145);
    expect(
      _rule(
        anchor: anchor,
        recentDays: _rows(anchor: anchor, protein: 80),
        baselineDays: oneBlock,
      ),
      isNull,
    );
  });

  test('S-2213 the unit conventions and the hard rules', () {
    final cards = [
      _rule(anchor: anchor, proteinTargets: _targets(anchor: anchor))!,
      _rule(
        anchor: anchor,
        recentDays: _rows(anchor: anchor, protein: 118),
        baselineDays: _usualBaseline(anchor: anchor),
      )!,
      _rule(
        anchor: anchor,
        recentDays: _rows(anchor: anchor, protein: 118),
        baselineDays: _usualBaseline(anchor: anchor),
        bodyWeightKg: 70,
      )!,
      _rule(
        anchor: anchor,
        proteinTargets: _targets(anchor: anchor),
        bodyWeightKg: 70,
      )!,
    ];

    final forbidden = RegExp(r'\d+\s*(cal|kcal|calorie)', caseSensitive: false);
    final span = '${kProteinConsistencyWindowDays ~/ 7} weeks';

    for (final card in cards) {
      final copy = proteinConsistencyCopy(card);
      for (final text in [copy.observation, copy.suggestion ?? '']) {
        expect(text, isNot(matches(forbidden)));
        expect(text.toLowerCase(), isNot(contains('eat less')));
        expect(text.toLowerCase(), isNot(contains('eat fewer')));
        expect(text.toLowerCase(), isNot(contains('reduce')));
        expect(text.toLowerCase(), isNot(contains('cut back')));
        expect(text.toLowerCase(), isNot(contains('lower your intake')));
      }
      // The span is the derived text, and every figure is a whole gram except
      // the per-kilogram one.
      expect(copy.observation, contains('over the last $span'));
      expect(
        RegExp(r'\d+\.\d+')
            .allMatches(copy.observation)
            .map((m) => m.group(0))
            .toList(),
        card.perKg == null ? isEmpty : ['1.7'],
      );
    }

    final source = _strippedSource('lib/core/models/protein_consistency.dart');
    expect(source, isNot(contains('cal')));
    expect(source, isNot(contains('kcal')));
    expect(source, isNot(contains('1.6')));
  });

  test('the span and the reference are derived, not written', () {
    // The 2-week span comes from `kProteinConsistencyWindowDays ~/ 7` and the
    // reference from `kProteinGuidancePerKg` (D-1516). A `2 weeks` or `1.6`
    // literal is a second definition of the same figure and would keep
    // rendering after the constant moved.
    final source = _strippedSource('lib/core/models/protein_consistency.dart');
    expect(
      source,
      isNot(contains('2 weeks')),
      reason: 'the span must be derived from kProteinConsistencyWindowDays, '
          'not written as a literal',
    );
    expect(
      source,
      isNot(contains('1.6')),
      reason: 'the reference must interpolate kProteinGuidancePerKg, not a '
          'decimal literal',
    );

    final targetCard = _rule(
      anchor: anchor,
      proteinTargets: _targets(anchor: anchor),
    )!;
    expect(
      proteinConsistencyCopy(targetCard).observation,
      contains('over the last 2 weeks'),
    );

    final ownCard = _rule(
      anchor: anchor,
      recentDays: _rows(anchor: anchor, protein: 118),
      baselineDays: _usualBaseline(anchor: anchor),
      bodyWeightKg: 70,
    )!;
    expect(
      proteinConsistencyCopy(ownCard).suggestion,
      contains('1.6 g/kg'),
    );
  });

  test('the adapter walks no history and calls no PR API', () {
    // The signal is a thin adapter: it asks `StatsProgressService` for the
    // window's series, the per-day targets, the resistance count and the
    // bodyweight, and hands them to the rule (D-1519). A repository read, a
    // window-scoped walk or a personal-record call would be a second source of
    // the figures. The banned set is 7b's own (see `test/interference_test.dart`,
    // `the adapter walks no history and calls no PR API`).
    const forbidden = <String>[
      'context.repository',
      'computeMixLayer',
      'computeMixPeriod',
      'computeTotals',
      'computeProgressData',
      'getAllSessions',
      'getSessionsByDateRange',
      'getSegmentsBySession',
      'getEffortsBySegment',
      'personalRecord',
      'PersonalRecord',
      'estimatedOneRepMax',
    ];
    final source = _strippedSource(
      'lib/core/services/signals/protein_consistency_signal.dart',
    );
    for (final identifier in forbidden) {
      expect(
        source.contains(identifier),
        isFalse,
        reason: 'the adapter must not walk history itself ("$identifier"); it '
            'calls the four service reads and nothing else (D-1519)',
      );
    }
    for (final read in const [
      'nutritionSeries',
      'proteinTargetsByDay',
      'resistanceSessionCount',
      'latestBodyWeightKg',
    ]) {
      expect(
        source.contains(read),
        isTrue,
        reason: 'the adapter must read "$read" from the service (D-1519)',
      );
    }
  });
}
