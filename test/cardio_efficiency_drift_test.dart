// Stats PR 9b, Phase 1 — the Cardio Efficiency Drift rule and its copy.
//
// The rule is pure Dart: `now` and the eligible efforts are parameters, so
// there is no clock here, no repository, no service and no Flutter. Scenarios
// S-2501…S-2510 of
// `docs/plans/2026-10-04-09b-stats-pr9b-cardio-efficiency-drift-plan/2026-10-04-09b-stats-pr9b-cardio-efficiency-drift-plan.md`.
//
// Every efficiency below is hand-computed as
// `distanceMetres × 60 ÷ (avgHeartRateBpm × durationSecs)`; with an average
// heart rate of 150 and a 480-second effort the divisor is 72000, so 2790 m
// reads 2.325, 2850 m reads 2.375, 2880 m reads 2.4 and 3000 m reads 2.5.

import 'package:omnitrain/core/models/cardio_efficiency_drift.dart';
import 'package:omnitrain/core/models/training_load.dart';
import 'package:test/test.dart';

final DateTime _now = DateTime(2026, 6, 15, 12, 0);

DateTime _at(int daysAgo, {int hour = 12, int minute = 0}) =>
    DateTime(_now.year, _now.month, _now.day - daysAgo, hour, minute);

CardioEffort _effort({
  String exerciseId = 'run',
  String exerciseName = 'Treadmill Run',
  required int daysAgo,
  int hour = 12,
  int minute = 0,
  required int durationSecs,
  required double distanceMetres,
  double avgHeartRateBpm = 150,
}) => CardioEffort(
  exerciseId: exerciseId,
  exerciseName: exerciseName,
  start: _at(daysAgo, hour: hour, minute: minute),
  durationSecs: durationSecs,
  distanceMetres: distanceMetres,
  avgHeartRateBpm: avgHeartRateBpm,
);

/// One exercise's efforts at [durationSecs], [recentDays] in the recent window
/// and [referenceDays] in the reference window. The default starts are S-2501's
/// four-and-four.
List<CardioEffort> _pair({
  String exerciseId = 'run',
  String exerciseName = 'Treadmill Run',
  int durationSecs = 480,
  double recentMetres = 2790,
  double referenceMetres = 3000,
  List<int> recentDays = const [3, 6, 9, 12],
  List<int> referenceDays = const [30, 33, 36, 39],
}) => [
  for (final d in recentDays)
    _effort(
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      daysAgo: d,
      durationSecs: durationSecs,
      distanceMetres: recentMetres,
    ),
  for (final d in referenceDays)
    _effort(
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      daysAgo: d,
      durationSecs: durationSecs,
      distanceMetres: referenceMetres,
    ),
];

CardioEfficiencyDriftResult? _for(List<CardioEffort> efforts) =>
    cardioEfficiencyDriftFor(efforts: efforts, now: _now);

void main() {
  test('the constant contracts', () {
    expect(kCardioEfficiencyDriftPriority, 50);
    expect(kCardioEfficiencyRecentDays, 14);
    expect(kCardioEfficiencyReferenceWeeksFrom, 6);
    expect(kCardioEfficiencyReferenceWeeksTo, 4);
    expect(kCardioEfficiencyDurationTolerancePercent, 10);
    expect(kCardioEfficiencyMinEffortsPerWindow, 3);
    expect(kCardioEfficiencyDriftPercent, 5);
    expect(kCardioEfficiencyLiftLoadRisePercent, 15);
    expect(kCardioEfficiencyLiftLoadWindowDays, 28);
  });

  test('D-1803 the efficiency is distance per heart-rate-minute', () {
    // 3000 × 60 = 180000, ÷ (150 × 480 = 72000) = 2.5.
    expect(
      cardioEfficiency(
        _effort(daysAgo: 3, durationSecs: 480, distanceMetres: 3000),
      ),
      2.5,
    );
    // 2850 × 60 = 171000, ÷ 72000 = 2.375.
    expect(
      cardioEfficiency(
        _effort(daysAgo: 3, durationSecs: 480, distanceMetres: 2850),
      ),
      2.375,
    );
    // 2400 × 60 = 144000, ÷ 72000 = 2.0.
    expect(
      cardioEfficiency(
        _effort(daysAgo: 3, durationSecs: 480, distanceMetres: 2400),
      ),
      2.0,
    );
  });

  test('D-1801 the two windows are local calendar spans', () {
    final windows = cardioEfficiencyWindows(_now);
    expect(windows.recentStart, DateTime(2026, 6, 2)); // day(13) 00:00
    expect(windows.recentEnd, DateTime(2026, 6, 16)); // tomorrow 00:00
    expect(windows.referenceStart, DateTime(2026, 5, 4)); // day(42) 00:00
    expect(windows.referenceEnd, DateTime(2026, 5, 18)); // day(28) 00:00
  });

  test('S-2501 four comparable runs, 7% worse, fires with the exact copy', () {
    final efforts = _pair();
    final result = _for(efforts);
    expect(result, isNotNull);
    expect(result!.exerciseId, 'run');
    expect(result.exerciseName, 'Treadmill Run');
    expect(result.anchorSecs, 480);
    expect(result.driftPercent, 7);
    expect(result.liftRisePercent, isNull);

    final copy = cardioEfficiencyDriftCopy(result);
    expect(
      copy.observation,
      'At similar durations, your Treadmill Run efforts are about 7% less '
      'efficient (slower pace at the same heart rate) than 4–6 weeks ago.',
    );
    expect(copy.suggestion, 'An easier week is one option.');
  });

  test('S-2502 the 5% boundary is inclusive', () {
    // 2850 m: 2.375 × 100 = 237.5 ≤ 2.5 × 95 = 237.5 → fires at exactly 5%.
    final atBoundary = _for(_pair(recentMetres: 2850));
    expect(atBoundary, isNotNull);
    expect(atBoundary!.driftPercent, 5);

    // 2880 m: 2.4 × 100 = 240 > 237.5 → 4% worse does not fire.
    expect(_for(_pair(recentMetres: 2880)), isNull);
  });

  test('S-2503 three efforts per window is the floor', () {
    final two = _pair(recentDays: const [3, 6]);
    expect(cardioEffortGroups(two).length, 1);
    expect(cardioEffortGroups(two).single.efforts.length, 6);
    expect(_for(two), isNull);

    final three = _pair(recentDays: const [3, 6, 9]);
    final result = _for(three);
    expect(result, isNotNull);
    expect(result!.driftPercent, 7);
  });

  test('S-2506 A the ±10% boundary groups inclusively', () {
    // 480 × 11 = 5280 = 528 × 10, so 528 s joins the 480 s anchor's group.
    // recent:  480 s at 2790 m → 2.325;  528 s at 3069 m → 184140 ÷ 79200 = 2.325.
    // reference: 480 s at 3000 m → 2.5;  528 s at 3300 m → 198000 ÷ 79200 = 2.5.
    final efforts = [
      ..._pair(
        durationSecs: 480,
        recentMetres: 2790,
        referenceMetres: 3000,
        recentDays: const [3, 6, 9],
        referenceDays: const [30, 33, 36],
      ),
      ..._pair(
        durationSecs: 528,
        recentMetres: 3069,
        referenceMetres: 3300,
        recentDays: const [4, 7, 10],
        referenceDays: const [31, 34, 37],
      ),
    ];
    final groups = cardioEffortGroups(efforts);
    expect(groups.length, 1);
    expect(groups.single.anchorSecs, 480);
    expect(groups.single.efforts.length, 12);

    final result = _for(efforts);
    expect(result, isNotNull);
    expect(result!.anchorSecs, 480);
    expect(result.driftPercent, 7);
  });

  test('S-2506 B 529 s is not within 10% of 480 s', () {
    // 529 × 10 = 5290 > 5280, so the two durations form two groups; the 480 s
    // group has only two recent efforts (below the floor) and the 529 s group
    // does not drift (both windows 3300 m → 2.4953), so nothing shows.
    final efforts = [
      ..._pair(
        durationSecs: 480,
        recentMetres: 2790,
        referenceMetres: 3000,
        recentDays: const [3, 6],
        referenceDays: const [30, 33],
      ),
      ..._pair(
        durationSecs: 529,
        recentMetres: 3300,
        referenceMetres: 3300,
        recentDays: const [4, 7, 10],
        referenceDays: const [31, 34, 37],
      ),
    ];
    final groups = cardioEffortGroups(efforts);
    expect(groups.length, 2);
    expect([for (final g in groups) g.anchorSecs], [480, 529]);
    expect(_for(efforts), isNull);
  });

  test('S-2506 C 30 and 45 minutes never merge', () {
    // 2700 × 10 = 27000 > 1800 × 11 = 19800. Both groups hold three recent and
    // three reference efforts at equal efficiency (1800 s at 9000 m → 2.0;
    // 2700 s at 13500 m → 2.0), so neither drifts and nothing shows.
    final efforts = [
      ..._pair(
        durationSecs: 1800,
        recentMetres: 9000,
        referenceMetres: 9000,
        recentDays: const [3, 6, 9],
        referenceDays: const [30, 33, 36],
      ),
      ..._pair(
        durationSecs: 2700,
        recentMetres: 13500,
        referenceMetres: 13500,
        recentDays: const [4, 7, 10],
        referenceDays: const [31, 34, 37],
      ),
    ];
    final groups = cardioEffortGroups(efforts);
    expect(groups.length, 2);
    expect([for (final g in groups) g.anchorSecs], [1800, 2700]);
    expect(_for(efforts), isNull);
  });

  test('S-2506 D a middle duration does not chain 480 s to 529 s', () {
    // 480 → 500 is within 10% (500 × 100 = 50000 <= 480 × 110 = 52800) and
    // 500 → 529 is too (52900 <= 55000), but the bound is measured against the
    // anchor, so 529 s never joins the 480 s group. An implementation that
    // compared a candidate with the previous member would merge all three and
    // report the 529 s group's drift at the 480 s anchor with p = 2.
    final efforts = [
      ..._pair(
        durationSecs: 480,
        recentMetres: 3000,
        referenceMetres: 3000,
        recentDays: const [3, 6, 9],
        referenceDays: const [30, 33, 36],
      ),
      // 500 s at 3125 m → 187500 ÷ 75000 = 2.5 in both windows.
      ..._pair(
        durationSecs: 500,
        recentMetres: 3125,
        referenceMetres: 3125,
        recentDays: const [4, 7, 10],
        referenceDays: const [31, 34, 37],
      ),
      // 529 s at 3300 m → 198000 ÷ 79350 = 2.4953; at 3069 m the ratio is
      // 3069 ÷ 3300 = 0.93, exactly 7% worse.
      ..._pair(
        durationSecs: 529,
        recentMetres: 3069,
        referenceMetres: 3300,
        recentDays: const [5, 8, 11],
        referenceDays: const [32, 35, 38],
      ),
    ];

    final groups = cardioEffortGroups(efforts);
    expect([for (final g in groups) g.anchorSecs], [480, 529]);
    for (final group in groups) {
      final durations = group.efforts.map((e) => e.durationSecs).toSet();
      expect(durations.contains(480) && durations.contains(529), isFalse);
    }

    final result = _for(efforts);
    expect(result, isNotNull);
    expect(result!.anchorSecs, 529);
    expect(result.driftPercent, 7);
  });

  test('S-2507 different exercises are never compared', () {
    final run = _pair(
      exerciseId: 'run',
      exerciseName: 'Treadmill Run',
      recentMetres: 2850,
      referenceMetres: 3000,
    );
    // The ride is 20% faster recently: 3600 m → 3.0 against 2.5, so it never
    // fires.
    final ride = _pair(
      exerciseId: 'ride',
      exerciseName: 'Stationary Bike',
      recentMetres: 3600,
      referenceMetres: 3000,
    );
    final groups = cardioEffortGroups([...run, ...ride]);
    expect(groups.length, 2);
    for (final group in groups) {
      expect(group.efforts.map((e) => e.exerciseId).toSet().length, 1);
    }

    final result = _for([...run, ...ride]);
    expect(result, isNotNull);
    expect(result!.exerciseId, 'run');
    expect(result.exerciseName, 'Treadmill Run');
    expect(result.driftPercent, 5);

    final runEven = _pair(
      exerciseId: 'run',
      exerciseName: 'Treadmill Run',
      recentMetres: 3000,
      referenceMetres: 3000,
    );
    final rideSlower = _pair(
      exerciseId: 'ride',
      exerciseName: 'Stationary Bike',
      recentMetres: 2850,
      referenceMetres: 3000,
    );
    final reversed = _for([...runEven, ...rideSlower]);
    expect(reversed, isNotNull);
    expect(reversed!.exerciseId, 'ride');
    expect(reversed.driftPercent, 5);
  });

  test('S-2508 the window edges, and a gap effort changes nothing', () {
    final windows = cardioEfficiencyWindows(_now);

    String where(DateTime start) {
      if (!start.isBefore(windows.recentStart) &&
          start.isBefore(windows.recentEnd)) {
        return 'recent';
      }
      if (!start.isBefore(windows.referenceStart) &&
          start.isBefore(windows.referenceEnd)) {
        return 'reference';
      }
      return 'neither';
    }

    expect(where(_at(13, hour: 0)), 'recent');
    expect(where(_at(14, hour: 23, minute: 59)), 'neither');
    expect(where(_at(27, hour: 23, minute: 59)), 'neither');
    expect(where(_at(28, hour: 0)), 'neither');
    expect(where(_at(42, hour: 0)), 'reference');
    expect(where(_at(43, hour: 0)), 'neither');

    // A 470 s gap effort would, as an anchor, absorb the 480 s efforts and
    // split them from the 528 s ones; the windows are applied before grouping,
    // so it is never an anchor and the result is the same as without it.
    final windowed = [
      ..._pair(durationSecs: 480, recentMetres: 2790, referenceMetres: 3000),
      ..._pair(
        durationSecs: 528,
        recentMetres: 3069,
        referenceMetres: 3300,
        recentDays: const [4, 7, 10],
        referenceDays: const [31, 34, 37],
      ),
    ];
    final without = _for(windowed);
    expect(without, isNotNull);
    expect(without!.driftPercent, 7);
    expect(without.anchorSecs, 480);

    final withGap = _for([
      ...windowed,
      _effort(daysAgo: 20, durationSecs: 470, distanceMetres: 2730),
      _effort(daysAgo: 43, durationSecs: 470, distanceMetres: 2730),
    ]);
    expect(withGap, isNotNull);
    expect(withGap!.driftPercent, without.driftPercent);
    expect(withGap.anchorSecs, without.anchorSecs);
    expect(withGap.exerciseId, without.exerciseId);
  });

  test('S-2509 the lifting sentence fires only at 15% or more', () {
    final efforts = _pair();

    // 1380 × 84 × 100 = 11592000 = 3600 × 28 × 115 → exactly +15%.
    final at = cardioEfficiencyDrift(
      efforts: efforts,
      now: _now,
      liftRecentLoad: 1380,
      liftUsualLoad: 3600,
      liftMeasure: MixMeasure.load,
    );
    expect(at, isNotNull);
    expect(at!.liftRisePercent, 15);
    expect(
      cardioEfficiencyDriftCopy(at).observation,
      'At similar durations, your Treadmill Run efforts are about 7% less '
      'efficient (slower pace at the same heart rate) than 4–6 weeks ago. '
      'Lifting load is 15% above your usual over the same period.',
    );

    // 1350 × 84 × 100 = 11340000 < 11592000 → 12.5% is below the floor.
    final below = cardioEfficiencyDrift(
      efforts: efforts,
      now: _now,
      liftRecentLoad: 1350,
      liftUsualLoad: 3600,
      liftMeasure: MixMeasure.load,
    );
    expect(below, isNotNull);
    expect(below!.liftRisePercent, isNull);
    expect(
      cardioEfficiencyDriftCopy(below).observation,
      isNot(contains('Lifting load')),
    );

    final timeMeasure = cardioEfficiencyDrift(
      efforts: efforts,
      now: _now,
      liftRecentLoad: 1380,
      liftUsualLoad: 3600,
      liftMeasure: MixMeasure.time,
    );
    expect(timeMeasure, isNotNull);
    expect(timeMeasure!.liftRisePercent, isNull);

    final noBaseline = cardioEfficiencyDrift(
      efforts: efforts,
      now: _now,
      liftRecentLoad: 1380,
      liftUsualLoad: 0,
      liftMeasure: MixMeasure.load,
    );
    expect(noBaseline, isNotNull);
    expect(noBaseline!.liftRisePercent, isNull);

    // A lift rise with no drift shows nothing at all.
    expect(
      cardioEfficiencyDrift(
        efforts: _pair(recentMetres: 3000),
        now: _now,
        liftRecentLoad: 1380,
        liftUsualLoad: 3600,
        liftMeasure: MixMeasure.load,
      ),
      isNull,
    );
  });

  test('S-2510 one card, the largest drift', () {
    CardioEfficiencyDriftResult? run(List<CardioEffort> efforts) =>
        cardioEfficiencyDrift(
          efforts: efforts,
          now: _now,
          liftRecentLoad: 0,
          liftUsualLoad: 0,
          liftMeasure: MixMeasure.load,
        );

    // A: 5% and 12% both qualify → the 12% ride is reported.
    // 2640 m → 2.2 against 2.5 = 12% worse.
    final a = run([
      ..._pair(
        exerciseId: 'run',
        exerciseName: 'Treadmill Run',
        recentMetres: 2850,
      ),
      ..._pair(
        exerciseId: 'ride',
        exerciseName: 'Stationary Bike',
        recentMetres: 2640,
      ),
    ]);
    expect(a, isNotNull);
    expect(a!.exerciseId, 'ride');
    expect(a.exerciseName, 'Stationary Bike');
    expect(a.driftPercent, 12);

    // B: both exactly 5% → the lower exercise id wins.
    final b = run([
      ..._pair(exerciseId: 'aaa', exerciseName: 'A', recentMetres: 2850),
      ..._pair(exerciseId: 'bbb', exerciseName: 'B', recentMetres: 2850),
    ]);
    expect(b, isNotNull);
    expect(b!.exerciseId, 'aaa');
    expect(b.driftPercent, 5);

    // C: one exercise, two groups at the same p → the shorter anchor wins.
    // 720 s: 4275 m → 2.375 against 4500 m → 2.5 = 5%.
    final c = [
      ..._pair(exerciseId: 'run', durationSecs: 480, recentMetres: 2850),
      ..._pair(
        exerciseId: 'run',
        durationSecs: 720,
        recentMetres: 4275,
        referenceMetres: 4500,
        recentDays: const [4, 7, 10],
        referenceDays: const [31, 34, 37],
      ),
    ];
    expect(cardioEffortGroups(c).length, 2);
    final result = run(c);
    expect(result, isNotNull);
    expect(result!.driftPercent, 5);
    expect(result.anchorSecs, 480);
  });
}
