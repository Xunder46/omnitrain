// Stats PR 9a, Phase 1 — the Sustained High Load rule and its copy.
//
// The rule is pure Dart: the week list and the Mix gate are parameters, so
// there is no clock here, no repository, no service and no Flutter. Scenarios
// S-2402…S-2409 of
// `docs/plans/2026-10-04-09a-stats-pr9a-sustained-high-load-plan/2026-10-04-09a-stats-pr9a-sustained-high-load-plan.md`.

import 'package:omnitrain/core/models/signals.dart';
import 'package:omnitrain/core/models/sustained_high_load.dart';
import 'package:omnitrain/core/models/training_load.dart';
import 'package:omnitrain/core/services/signals/signal_registry.dart';
import 'package:test/test.dart';

/// The weeks of [loads], oldest first, each starting seven calendar days after
/// the last. A week with a positive load is rated; an empty week is not — every
/// fixture in the plan's scenarios follows that rule.
List<WeeklyLoad> _weeks(List<double> loads) => [
  for (var i = 0; i < loads.length; i++)
    WeeklyLoad(
      weekStart: DateTime(2026, 1, 5 + 7 * i),
      loadMinutes: loads[i],
      hasRatedSession: loads[i] > 0,
    ),
];

/// [repeats] copies of [load].
List<double> _repeat(double load, int repeats) =>
    List<double>.filled(repeats, load);

/// S-2401's twelve-week baseline: ten rated weeks at 240 then two empty weeks.
List<double> get _baseline2400 => [..._repeat(240, 10), 0, 0];

void main() {
  test('the constant contracts', () {
    expect(kSustainedHighLoadPriority, 100);
    expect(kSustainedHighLoadMinStreakWeeks, 5);
    expect(kSustainedHighLoadMinRatedWeeks, 8);
    expect(kSustainedHighLoadHigherPercent, 110);
    expect(kSustainedHighLoadEasierPercent, 80);
    expect(kSustainedHighLoadMinEasierGaps, 2);
    expect(kSustainedHighLoadGapMinWeeks, 3);
    expect(kSustainedHighLoadGapMaxWeeks, 5);
  });

  test('the baseline stage abstains below twelve earlier weeks', () {
    expect(
      sustainedHighLoadBaseline(
        weeks: _weeks(_repeat(240, 11)),
        beforeIndex: 11,
      ),
      isNull,
    );
    final baseline = sustainedHighLoadBaseline(
      weeks: _weeks(_baseline2400),
      beforeIndex: 12,
    );
    expect(baseline, isNotNull);
    expect(baseline!.usualLoadMinutes, 200);
    expect(baseline.ratedWeeks, 10);
  });

  test('S-2402 the 110% boundary is inclusive', () {
    final inclusive = _weeks([..._baseline2400, 220, ..._repeat(230, 4)]);
    final streak = sustainedHighLoadStreak(weeks: inclusive);
    expect(streak.weekCount, 5);
    expect(streak.usualLoadMinutes, 200);
    expect(streak.ratedBaselineWeeks, 10);
    expect(streak.firstWeekStart, inclusive[12].weekStart);
    expect(sustainedHighLoad(weeks: inclusive, mixShowsLoad: true), isNotNull);

    final justBelow = _weeks([..._baseline2400, 219, ..._repeat(230, 4)]);
    final below = sustainedHighLoadStreak(weeks: justBelow);
    expect(below.weekCount, 4);
    expect(below.usualLoadMinutes, closeTo(198.25, 1e-9));
    expect(sustainedHighLoad(weeks: justBelow, mixShowsLoad: true), isNull);
  });

  test('S-2403 four weeks is not five', () {
    final weeks = _weeks([..._baseline2400, ..._repeat(230, 4)]);
    final streak = sustainedHighLoadStreak(weeks: weeks);
    expect(streak.weekCount, 4);
    expect(streak.usualLoadMinutes, 200);
    expect(sustainedHighLoad(weeks: weeks, mixShowsLoad: true), isNull);
  });

  test('S-2404 the rated-history floor, and the twelve-week requirement', () {
    final a = _weeks([
      ..._repeat(240, 8),
      ..._repeat(0, 4),
      ..._repeat(184, 5),
    ]);
    final streakA = sustainedHighLoadStreak(weeks: a);
    expect(streakA.weekCount, 5);
    expect(streakA.usualLoadMinutes, 160);
    expect(streakA.ratedBaselineWeeks, 8);
    expect(sustainedHighLoad(weeks: a, mixShowsLoad: true), isNotNull);

    final b = _weeks([
      ..._repeat(240, 7),
      ..._repeat(0, 5),
      ..._repeat(154, 5),
    ]);
    expect(sustainedHighLoadStreak(weeks: b).weekCount, 0);
    expect(sustainedHighLoad(weeks: b, mixShowsLoad: true), isNull);

    final c = _weeks([..._repeat(240, 10), 0, ..._repeat(230, 5)]);
    expect(sustainedHighLoadStreak(weeks: c).weekCount, 0);
    expect(sustainedHighLoad(weeks: c, mixShowsLoad: true), isNull);
  });

  test('S-2405 a 105% week resets the count at that week', () {
    final weeks = _weeks([..._baseline2400, 230, 230, 210, 230, 230, 230]);
    final streak = sustainedHighLoadStreak(weeks: weeks);
    expect(streak.weekCount, 3);
    expect(streak.usualLoadMinutes, closeTo(2350 / 12, 1e-9));
    expect(streak.ratedBaselineWeeks, 10);
    expect(streak.firstWeekStart, weeks[15].weekStart);
    expect(sustainedHighLoad(weeks: weeks, mixShowsLoad: true), isNull);
  });

  test('S-2406 the easier boundary, and an ordinary week that is neither', () {
    final atBoundary = _weeks([..._baseline2400, 160, ..._repeat(230, 5)]);
    final boundaryStreak = sustainedHighLoadStreak(weeks: atBoundary);
    expect(boundaryStreak.weekCount, 5);
    expect(boundaryStreak.usualLoadMinutes, closeTo(2320 / 12, 1e-9));
    expect(sustainedHighLoad(weeks: atBoundary, mixShowsLoad: true), isNotNull);

    final neither = _weeks([..._baseline2400, 162, ..._repeat(230, 5)]);
    final neitherStreak = sustainedHighLoadStreak(weeks: neither);
    expect(neitherStreak.weekCount, 5);
    expect(neitherStreak.usualLoadMinutes, closeTo(2322 / 12, 1e-9));
    expect(sustainedHighLoad(weeks: neither, mixShowsLoad: true), isNotNull);

    // The easier boundary is inclusive, and the history fact is its only
    // reader: a week at exactly 80% of the usual is easier, half a minute
    // above it is not.
    final easier = _weeks([
      160,
      ..._repeat(200, 2),
      160,
      ..._repeat(200, 2),
      160,
      ..._repeat(200, 7),
    ]);
    expect(
      sustainedHighLoadEasierGapWeeks(
        weeks: easier,
        beforeIndex: 14,
        usual: 200,
      ),
      3,
    );
    final above = _weeks([
      160,
      ..._repeat(200, 2),
      160,
      ..._repeat(200, 2),
      160.5,
      ..._repeat(200, 7),
    ]);
    expect(
      sustainedHighLoadEasierGapWeeks(
        weeks: above,
        beforeIndex: 14,
        usual: 200,
      ),
      isNull,
    );
  });

  test('S-2407 the history fact shows the interval', () {
    final weeks = _weeks([
      200,
      250,
      250,
      200,
      250,
      250,
      250,
      250,
      200,
      250,
      250,
      200,
      ..._repeat(250, 12),
      ..._repeat(280, 5),
    ]);
    final streak = sustainedHighLoadStreak(weeks: weeks);
    expect(streak.weekCount, 5);
    expect(streak.usualLoadMinutes, 250);
    expect(streak.ratedBaselineWeeks, 12);
    expect(streak.firstWeekStart, weeks[24].weekStart);

    final result = sustainedHighLoad(weeks: weeks, mixShowsLoad: true);
    expect(result, isNotNull);
    expect(result!.streakWeeks, 5);
    expect(result.easierGapWeeks, 3);

    final copy = sustainedHighLoadCopy(result);
    expect(
      copy.observation,
      "You've had 5 consecutive weeks above your usual training load, with no "
      'easier week. Earlier in your history, you usually had an easier week '
      'every 3 weeks.',
    );
    expect(copy.suggestion, 'An easier week is one option.');
  });

  test('S-2408 the even-count median is the lower one', () {
    final weeks = _weeks([
      200,
      250,
      250,
      200,
      250,
      250,
      250,
      250,
      200,
      250,
      250,
      250,
      ..._repeat(250, 12),
      ..._repeat(280, 5),
    ]);
    expect(sustainedHighLoadStreak(weeks: weeks).weekCount, 5);
    final result = sustainedHighLoad(weeks: weeks, mixShowsLoad: true);
    expect(result, isNotNull);
    expect(result!.easierGapWeeks, 3);
    expect(
      sustainedHighLoadCopy(result).observation,
      contains('every 3 weeks.'),
    );
  });

  test('S-2409 the fact is absent when the habit is not there', () {
    final a = _weeks([..._baseline2400, ..._repeat(230, 5)]);
    final b = _weeks([
      200,
      250,
      250,
      200,
      250,
      250,
      250,
      250,
      250,
      200,
      250,
      250,
      ..._repeat(250, 12),
      ..._repeat(280, 5),
    ]);
    final c = _weeks([..._repeat(250, 24), ..._repeat(280, 5)]);

    for (final weeks in [a, b, c]) {
      final result = sustainedHighLoad(weeks: weeks, mixShowsLoad: true);
      expect(result, isNotNull);
      expect(result!.streakWeeks, 5);
      expect(result.easierGapWeeks, isNull);
      final copy = sustainedHighLoadCopy(result);
      expect(copy.observation, isNot(contains('Earlier in your history')));
    }
  });

  // ─── structural guards (Phase 3B) ─────────────────────────────────────────
  //
  // The registry's caution order and the copy's wording are the two things a
  // later change could break without any scenario above noticing.

  test('the registry lists the cautions in strictly ascending priority', () {
    final cautions = buildSignalRegistry()
        .where((signal) => signal.kind == SignalKind.caution)
        .toList();

    for (var i = 1; i < cautions.length; i++) {
      expect(
        cautions[i].priority,
        greaterThan(cautions[i - 1].priority),
        reason:
            '${cautions[i].id} (${cautions[i].priority}) must sit after '
            '${cautions[i - 1].id} (${cautions[i - 1].priority})',
      );
    }
  });

  test('the copy is the exact shipped wording', () {
    final withoutFact = sustainedHighLoadCopy(
      sustainedHighLoad(
        weeks: _weeks([..._baseline2400, ..._repeat(230, 5)]),
        mixShowsLoad: true,
      )!,
    );
    expect(
      withoutFact.observation,
      "You've had 5 consecutive weeks above your usual training load, with no "
      'easier week.',
    );
    expect(withoutFact.suggestion, 'An easier week is one option.');

    final withFact = sustainedHighLoadCopy(
      sustainedHighLoad(
        weeks: _weeks([
          200,
          250,
          250,
          200,
          250,
          250,
          250,
          250,
          200,
          250,
          250,
          200,
          ..._repeat(250, 12),
          ..._repeat(280, 5),
        ]),
        mixShowsLoad: true,
      )!,
    );
    expect(
      withFact.observation,
      "You've had 5 consecutive weeks above your usual training load, with no "
      'easier week. Earlier in your history, you usually had an easier week '
      'every 3 weeks.',
    );
    expect(withFact.suggestion, 'An easier week is one option.');
  });

  test('the copy carries no amount, no percentage and no causal word', () {
    const units = ['%', 'min', 'kg', 'lb', 'kcal'];
    const causal = ['fatigue', 'because', 'due to', 'cause'];

    final results = [
      sustainedHighLoad(
        weeks: _weeks([..._baseline2400, ..._repeat(230, 5)]),
        mixShowsLoad: true,
      )!,
      sustainedHighLoad(
        weeks: _weeks([
          200,
          250,
          250,
          200,
          250,
          250,
          250,
          250,
          200,
          250,
          250,
          200,
          ..._repeat(250, 12),
          ..._repeat(280, 5),
        ]),
        mixShowsLoad: true,
      )!,
    ];

    for (final result in results) {
      final copy = sustainedHighLoadCopy(result);
      for (final text in [copy.observation, copy.suggestion]) {
        final lower = text.toLowerCase();
        for (final token in [...units, ...causal]) {
          expect(lower, isNot(contains(token)), reason: 'in "$text"');
        }
      }
    }
  });
}
