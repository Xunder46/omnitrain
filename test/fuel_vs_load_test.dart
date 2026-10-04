// Stats PR 8a, Phase 1 — the Fuel vs Load rule and its copy.
//
// The rule is pure Dart: `now` is a parameter, so there is no clock, no
// repository and no Flutter. Scenarios S-2101…S-2109 and S-2111 of
// `docs/plans/2026-10-03-08a-stats-pr8a-fuel-vs-load-plan/2026-10-03-08a-stats-pr8a-fuel-vs-load-plan.md`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/fuel_vs_load.dart';
import 'package:omnitrain/core/models/nutrition_consistency.dart';
import 'package:omnitrain/core/models/training_load.dart';

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

/// The 42 logged days of S-2101: the prior period (days 41…21) at
/// [priorIntake] and the recent period (days 20…0) at [recentIntake], omitting
/// every day in [skip].
List<LoggedDay> _sixWeeks({
  required DateTime anchor,
  required double priorIntake,
  required double recentIntake,
  Set<int> skip = const {},
}) => [
  for (var n = 41; n >= 21; n--)
    if (!skip.contains(n)) LoggedDay(day: _day(anchor, n), intake: priorIntake),
  for (var n = 20; n >= 0; n--)
    if (!skip.contains(n))
      LoggedDay(day: _day(anchor, n), intake: recentIntake),
];

/// One rule call over the hand-built figures.
FuelVsLoad? _rule({
  required DateTime anchor,
  required List<LoggedDay> loggedDays,
  double recentLoad = 1250,
  double priorLoad = 1000,
  MixMeasure recentMeasure = MixMeasure.load,
  MixMeasure priorMeasure = MixMeasure.load,
}) => fuelVsLoad(
  now: anchor,
  recentMeasure: recentMeasure,
  priorMeasure: priorMeasure,
  recentLoad: recentLoad,
  priorLoad: priorLoad,
  loggedDays: loggedDays,
);

void main() {
  final anchor = DateTime(2026, 6, 15, 10, 30);

  test('the constant contracts', () {
    expect(kFuelVsLoadWindowDays, 21);
    expect(kFuelVsLoadLoadRisePercent, 20);
    expect(kFuelVsLoadIntakeTolerancePercent, 5);
    expect(kFuelVsLoadPriority, 300);
  });

  test('S-2101 the pack row fires with the load percentage and the span', () {
    final days = _sixWeeks(
      anchor: anchor,
      priorIntake: 2000,
      recentIntake: 2040,
    );
    expect(fuelVsLoadGate(now: anchor, loggedDays: days), isTrue);

    final result = _rule(anchor: anchor, loggedDays: days);
    expect(result, isNotNull);
    expect(result!.loadRisePercent, 25);

    final copy = fuelVsLoadCopy(result);
    expect(
      copy.observation,
      'Training load is up 25% over the last 3 weeks; your average daily '
      'intake has not risen with it.',
    );
    expect(
      copy.suggestion,
      'Worth checking that intake is keeping up with training.',
    );
  });

  test('S-2102 one block at 4 of 7 logged days suppresses everything', () {
    final days = _sixWeeks(
      anchor: anchor,
      priorIntake: 2000,
      recentIntake: 2040,
      skip: const {9, 8, 7},
    );
    expect(fuelVsLoadGate(now: anchor, loggedDays: days), isFalse);
    expect(_rule(anchor: anchor, loggedDays: days), isNull);
  });

  test('S-2103 +19% load shows nothing', () {
    final days = _sixWeeks(
      anchor: anchor,
      priorIntake: 2000,
      recentIntake: 2000,
    );
    expect(fuelVsLoadLoadTest(recentLoad: 1190, priorLoad: 1000), isFalse);
    expect(100 * 1190, lessThan((100 + kFuelVsLoadLoadRisePercent) * 1000));
    expect(_rule(anchor: anchor, recentLoad: 1190, loggedDays: days), isNull);
  });

  test('S-2104 exactly +20% load fires', () {
    final days = _sixWeeks(
      anchor: anchor,
      priorIntake: 2000,
      recentIntake: 2000,
    );
    expect(fuelVsLoadLoadTest(recentLoad: 1200, priorLoad: 1000), isTrue);
    expect(
      100 * 1200,
      greaterThanOrEqualTo((100 + kFuelVsLoadLoadRisePercent) * 1000),
    );

    final result = _rule(anchor: anchor, recentLoad: 1200, loggedDays: days);
    expect(result, isNotNull);
    expect(result!.loadRisePercent, 20);
    expect(
      fuelVsLoadCopy(result).observation,
      'Training load is up 20% over the last 3 weeks; your average daily '
      'intake has not risen with it.',
    );
  });

  test('S-2105 exactly +5% intake still fires', () {
    final days = _sixWeeks(
      anchor: anchor,
      priorIntake: 2000,
      recentIntake: 2100,
    );
    expect(
      fuelVsLoadIntakeTest(
        recentIntakeTotal: 2100 * 21,
        recentLoggedDays: 21,
        priorIntakeTotal: 2000 * 21,
        priorLoggedDays: 21,
      ),
      isTrue,
    );
    expect(
      100 * (2100 * 21) * 21,
      lessThanOrEqualTo(
        (100 + kFuelVsLoadIntakeTolerancePercent) * (2000 * 21) * 21,
      ),
    );

    final result = _rule(anchor: anchor, loggedDays: days);
    expect(result, isNotNull);
    expect(result!.loadRisePercent, 25);
  });

  test('S-2106 +6% intake shows nothing', () {
    final days = _sixWeeks(
      anchor: anchor,
      priorIntake: 2000,
      recentIntake: 2120,
    );
    expect(
      fuelVsLoadIntakeTest(
        recentIntakeTotal: 2120 * 21,
        recentLoggedDays: 21,
        priorIntakeTotal: 2000 * 21,
        priorLoggedDays: 21,
      ),
      isFalse,
    );
    expect(
      100 * (2120 * 21) * 21,
      greaterThan((100 + kFuelVsLoadIntakeTolerancePercent) * (2000 * 21) * 21),
    );
    expect(_rule(anchor: anchor, loggedDays: days), isNull);
  });

  test('S-2107 the intake mean divides by logged days, not the window', () {
    const skip = {15, 14, 8, 7, 1, 0};
    final recentStart = _day(anchor, 20);

    final high = _sixWeeks(
      anchor: anchor,
      priorIntake: 2000,
      recentIntake: 2500,
      skip: skip,
    );
    expect(fuelVsLoadGate(now: anchor, loggedDays: high), isTrue);
    final recentDays = high.where((d) => !d.day.isBefore(recentStart)).toList();
    expect(recentDays.length, 15);
    expect(loggedDayMean(recentDays.map((d) => d.intake)), 2500);
    expect(_rule(anchor: anchor, loggedDays: high), isNull);

    final flat = _sixWeeks(
      anchor: anchor,
      priorIntake: 2000,
      recentIntake: 2000,
      skip: skip,
    );
    expect(_rule(anchor: anchor, loggedDays: flat), isNotNull);
  });

  test('S-2108 no intake figure and no reduction wording', () {
    final days = _sixWeeks(
      anchor: anchor,
      priorIntake: 2000,
      recentIntake: 2040,
    );
    final result = _rule(anchor: anchor, loggedDays: days)!;
    final copy = fuelVsLoadCopy(result);
    final forbidden = RegExp(r'\d+\s*(cal|kcal|calorie)', caseSensitive: false);

    for (final text in [copy.observation, copy.suggestion]) {
      expect(text, isNot(matches(forbidden)));
      expect(text.toLowerCase(), isNot(contains('eat less')));
      expect(text.toLowerCase(), isNot(contains('eat fewer')));
      expect(text.toLowerCase(), isNot(contains('reduce')));
      expect(text.toLowerCase(), isNot(contains('cut back')));
      expect(text.toLowerCase(), isNot(contains('lower your intake')));
    }
    expect(
      RegExp(
        r'\d+',
      ).allMatches(copy.observation).map((m) => m.group(0)).toList(),
      ['25', '3'],
    );

    final source = _strippedSource('lib/core/models/fuel_vs_load.dart');
    expect(source, isNot(contains('cal')));
    expect(source, isNot(contains('kcal')));
  });

  test('S-2109 a falling load never produces a card', () {
    final days = _sixWeeks(
      anchor: anchor,
      priorIntake: 2000,
      recentIntake: 2000,
    );
    expect(fuelVsLoadLoadTest(recentLoad: 700, priorLoad: 1000), isFalse);
    expect(_rule(anchor: anchor, recentLoad: 700, loggedDays: days), isNull);
  });

  test('S-2111 a period measuring time suppresses the card', () {
    final days = _sixWeeks(
      anchor: anchor,
      priorIntake: 2000,
      recentIntake: 2040,
    );
    expect(
      fuelVsLoadMeasureGate(
        recentMeasure: MixMeasure.load,
        priorMeasure: MixMeasure.time,
      ),
      isFalse,
    );
    expect(
      _rule(anchor: anchor, priorMeasure: MixMeasure.time, loggedDays: days),
      isNull,
    );
    expect(
      _rule(anchor: anchor, recentMeasure: MixMeasure.time, loggedDays: days),
      isNull,
    );
  });

  group('the structural guards', () {
    test('the span is derived from its constant, not written', () {
      // D-1412: the observation's span is `kFuelVsLoadWindowDays ~/ 7` alone.
      // A `3 weeks` literal is a second definition of the same window and
      // would keep rendering 3 weeks if the constant moved.
      final source = _strippedSource('lib/core/models/fuel_vs_load.dart');
      expect(
        source.contains('3 weeks'),
        isFalse,
        reason: 'the span must be derived from kFuelVsLoadWindowDays, not '
            'written as a literal',
      );
      expect(
        source.contains('kFuelVsLoadWindowDays ~/ 7'),
        isTrue,
        reason: 'the observation must interpolate the owning constant',
      );

      final days = _sixWeeks(
        anchor: anchor,
        priorIntake: 2000,
        recentIntake: 2040,
      );
      final result = _rule(anchor: anchor, loggedDays: days);
      expect(result, isNotNull);
      expect(
        fuelVsLoadCopy(result!).observation,
        contains('over the last 3 weeks;'),
      );
    });

    test('the adapter walks no history and calls no PR API', () {
      // D-1418: the signal is a thin adapter. It asks `StatsProgressService`
      // for the two Mix payloads and the per-day intake series. A repository
      // read, a window-scoped walk or a personal-record call would be a second
      // source of the figures the Mix layer shows.
      const forbidden = <String>[
        'context.repository',
        'computeMixLayer',
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
        'lib/core/services/signals/fuel_vs_load_signal.dart',
      );
      for (final identifier in forbidden) {
        expect(
          source.contains(identifier),
          isFalse,
          reason: 'the adapter must not walk history itself ("$identifier"); '
              'it calls computeMixPeriod and nutritionSeries and nothing else '
              '(D-1418)',
        );
      }
      expect(source.contains('computeMixPeriod'), isTrue);
      expect(source.contains('nutritionSeries'), isTrue);
    });
  });
}
