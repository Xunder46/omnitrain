// Plan 179 P1 — a session with no sets shares its time across what was timed.
//
// The pure scenarios S-20001..S-20006 of
// `docs/plans/2026-11-15-179-stats-mix-no-sets-plan/2026-11-15-179-stats-mix-no-sets-plan.md`:
// `sessionTimeByModality` with `hasSets` false scales the measured time to the
// whole duration; a set-effort session keeps the remainder rule; the overflow
// branch and the no-measured-time rule run first.

import 'package:omnitrain/core/models/exercise_metric.dart';
import 'package:omnitrain/core/models/training_load.dart';
import 'package:test/test.dart';

void main() {
  test('S-20001 a run-only session reads Cardio over its whole length', () {
    final time = sessionTimeByModality(
      durationSecs: 2400,
      isRolling: false,
      measuredSecs: {ExerciseSection.cardio: 1800.0},
      dominantSection: ExerciseSection.cardio,
      hasSets: false,
    );
    expect(time, {ExerciseSection.cardio: 2400.0});

    final segments = mixSegments(time);
    expect(segments, hasLength(1));
    expect(segments.single.section, ExerciseSection.cardio);
    expect(segments.single.percent, 100);
  });

  test('S-20002 a hold-only session reads Isometric over its whole length', () {
    final time = sessionTimeByModality(
      durationSecs: 3600,
      isRolling: false,
      measuredSecs: {ExerciseSection.isometric: 1080.0},
      dominantSection: ExerciseSection.isometric,
      hasSets: false,
    );
    expect(time, {ExerciseSection.isometric: 3600.0});

    final segments = mixSegments(time);
    expect(segments, hasLength(1));
    expect(segments.single.section, ExerciseSection.isometric);
    expect(segments.single.percent, 100);
  });

  test('S-20003 two timed modalities split the duration in proportion', () {
    final time = sessionTimeByModality(
      durationSecs: 3000,
      isRolling: false,
      measuredSecs: {
        ExerciseSection.cardio: 1800.0,
        ExerciseSection.isometric: 600.0,
      },
      dominantSection: ExerciseSection.cardio,
      hasSets: false,
    );
    expect(time[ExerciseSection.cardio], 2250.0);
    expect(time[ExerciseSection.isometric], 750.0);
    expect(time.values.fold<double>(0, (a, b) => a + b), closeTo(3000, 1e-9));

    final segments = mixSegments(time);
    expect(segments.map((s) => s.section), [
      ExerciseSection.cardio,
      ExerciseSection.isometric,
    ]);
    expect(segments[0].percent, 75);
    expect(segments[1].percent, 25);
  });

  test('S-20004 a session with sets keeps the remainder rule', () {
    final time = sessionTimeByModality(
      durationSecs: 2400,
      isRolling: false,
      measuredSecs: {ExerciseSection.cardio: 1800.0},
      dominantSection: ExerciseSection.cardio,
      hasSets: true,
    );
    expect(time[ExerciseSection.cardio], 1800.0);
    expect(time[ExerciseSection.resistance], 600.0);

    final segments = mixSegments(time);
    expect(segments.map((s) => s.section), [
      ExerciseSection.cardio,
      ExerciseSection.resistance,
    ]);
    expect(segments[0].percent, 75);
    expect(segments[1].percent, 25);
  });

  test('S-20005 measured time over the duration still goes to the dominant '
      'modality before the new rule', () {
    final time = sessionTimeByModality(
      durationSecs: 1800,
      isRolling: false,
      measuredSecs: {
        ExerciseSection.isometric: 2100.0,
        ExerciseSection.cardio: 600.0,
      },
      dominantSection: ExerciseSection.isometric,
      hasSets: false,
    );
    expect(time, {ExerciseSection.isometric: 1800.0});
  });

  test('S-20006 a session with no measured time stays all Resistance', () {
    final time = sessionTimeByModality(
      durationSecs: 1800,
      isRolling: false,
      measuredSecs: <ExerciseSection, double>{},
      dominantSection: ExerciseSection.cardio,
      hasSets: false,
    );
    expect(time, {ExerciseSection.resistance: 1800.0});
  });
}
