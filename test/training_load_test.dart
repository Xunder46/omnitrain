// Stats PR 5a, Phase 1 — the training-load definitions.
//
// The pure rules of `lib/core/models/training_load.dart` and the week-start
// helper on `OmniDateUtils`: session load (D-901), measured active time
// (D-903), the per-session time split (D-904–D-906), the load split (D-907),
// the percentage rounding (D-912), the segment order (D-913) and the baseline
// period's calendar blocks (D-934).
//
// Scenarios S-1501, S-1503, S-1504, S-1506, S-1507, S-1508, S-1512, S-1515 and
// S-1516 of
// `docs/plans/2026-10-02-05a-stats-pr5a-mix-data-plan/2026-10-02-05a-stats-pr5a-mix-data-plan.md`.

import 'package:omnitrain/core/models/exercise_metric.dart';
import 'package:omnitrain/core/models/training_load.dart';
import 'package:omnitrain/core/utils/date_utils.dart';
import 'package:test/test.dart';

/// The section named [section] in [segments], or a failure naming what the
/// list held instead.
MixSegment _segmentOf(List<MixSegment> segments, ExerciseSection section) {
  final matches = segments.where((s) => s.section == section).toList();
  expect(matches, hasLength(1), reason: '$section must appear exactly once');
  return matches.single;
}

/// The sum of every segment's percent — the figure D-912 pins to 100.
int _percentTotal(List<MixSegment> segments) =>
    segments.fold<int>(0, (sum, s) => sum + s.percent);

/// The first local day in 2026 whose midnight is not exactly 24 hours after the
/// previous day's — a DST transition in the machine's own zone. Null when the
/// zone has no DST, in which case no duration step can shift a boundary.
DateTime? _dstTransitionDay() {
  var day = DateTime(2026, 1, 1);
  while (day.year == 2026) {
    final next = DateTime(day.year, day.month, day.day + 1);
    if (next.difference(day) != const Duration(days: 1)) return next;
    day = next;
  }
  return null;
}

void main() {
  group('sessionLoadMinutes (D-901)', () {
    test('S-1501 a 60-minute session rated 4 is 240 load', () {
      expect(sessionLoadMinutes(sessionTimeSecs: 3600, rating: 4), 240.0);
    });

    test('each rating 1 through 5 gives 60 × rating', () {
      for (var rating = 1; rating <= 5; rating++) {
        expect(
          sessionLoadMinutes(sessionTimeSecs: 3600, rating: rating),
          60.0 * rating,
        );
      }
    });

    test('S-1502 an unrated session has zero load and is never estimated', () {
      expect(sessionLoadMinutes(sessionTimeSecs: 3600, rating: null), 0.0);
    });

    test('zero duration gives zero load', () {
      expect(sessionLoadMinutes(sessionTimeSecs: 0, rating: 5), 0.0);
    });

    test('a negative duration gives zero load', () {
      expect(sessionLoadMinutes(sessionTimeSecs: -60, rating: 5), 0.0);
    });
  });

  group('sessionTimeByModality (D-904–D-906)', () {
    test('S-1503 20 minutes of holds leaves Resistance the 40-minute '
        'remainder', () {
      final time = sessionTimeByModality(
        durationSecs: 3600,
        isRolling: false,
        measuredSecs: {ExerciseSection.isometric: 1200},
        dominantSection: ExerciseSection.isometric,
      );
      expect(time[ExerciseSection.resistance], 2400.0);
      expect(time[ExerciseSection.isometric], 1200.0);
    });

    test('S-1504 the same geometry reads the same in minutes', () {
      final time = sessionTimeByModality(
        durationSecs: 3600,
        isRolling: false,
        measuredSecs: {ExerciseSection.isometric: 1200},
        dominantSection: ExerciseSection.isometric,
      );
      expect(time[ExerciseSection.resistance]! / 60, 40.0);
      expect(time[ExerciseSection.isometric]! / 60, 20.0);
    });

    test('S-1505 a 75-minute lifting session with a 15-minute warm-up', () {
      final time = sessionTimeByModality(
        durationSecs: 4500,
        isRolling: false,
        measuredSecs: {ExerciseSection.cardio: 900},
        dominantSection: ExerciseSection.cardio,
      );
      expect(time[ExerciseSection.resistance], 3600.0);
      expect(time[ExerciseSection.cardio], 900.0);
    });

    test('S-1506 A measured time over the duration goes to the dominant '
        'modality', () {
      final time = sessionTimeByModality(
        durationSecs: 1800,
        isRolling: false,
        measuredSecs: {
          ExerciseSection.isometric: 2100,
          ExerciseSection.cardio: 600,
        },
        dominantSection: ExerciseSection.isometric,
      );
      expect(time, {ExerciseSection.isometric: 1800.0});
    });

    test(
      'S-1506 B a tie in the dominant count resolves by declaration order',
      () {
        final time = sessionTimeByModality(
          durationSecs: 600,
          isRolling: false,
          measuredSecs: {ExerciseSection.cardio: 900},
          dominantSection: ExerciseSection.resistance,
        );
        expect(time, {ExerciseSection.resistance: 600.0});
      },
    );

    test('S-1507 the whole session goes to the dominant modality', () {
      final time = sessionTimeByModality(
        durationSecs: 1200,
        isRolling: false,
        measuredSecs: {
          ExerciseSection.isometric: 800,
          ExerciseSection.cardio: 800,
        },
        dominantSection: ExerciseSection.cardio,
      );
      expect(time, {ExerciseSection.cardio: 1200.0});
    });

    test('S-1508 a rolling session counts measured time only', () {
      final time = sessionTimeByModality(
        durationSecs: 10800,
        isRolling: true,
        measuredSecs: {ExerciseSection.cardio: 1800},
        dominantSection: ExerciseSection.cardio,
      );
      expect(time, {ExerciseSection.cardio: 1800.0});
      expect(time.containsKey(ExerciseSection.resistance), isFalse);
    });

    test('S-1509 A a sets-only rolling session contributes no time', () {
      final time = sessionTimeByModality(
        durationSecs: 10800,
        isRolling: true,
        measuredSecs: const {},
        dominantSection: ExerciseSection.resistance,
      );
      expect(time, isEmpty);
    });

    test('S-1515 a lifting-only session is all Resistance', () {
      final time = sessionTimeByModality(
        durationSecs: 5400,
        isRolling: false,
        measuredSecs: const {},
        dominantSection: ExerciseSection.resistance,
      );
      expect(time, {ExerciseSection.resistance: 5400.0});
    });

    test('S-1516 every modality splits four ways', () {
      final time = sessionTimeByModality(
        durationSecs: 3600,
        isRolling: false,
        measuredSecs: {
          ExerciseSection.cardio: 600,
          ExerciseSection.isometric: 600,
          ExerciseSection.sports: 600,
        },
        dominantSection: ExerciseSection.resistance,
      );
      expect(time[ExerciseSection.resistance], 1800.0);
      expect(time[ExerciseSection.cardio], 600.0);
      expect(time[ExerciseSection.isometric], 600.0);
      expect(time[ExerciseSection.sports], 600.0);
    });

    test('the remainder is never below zero', () {
      final time = sessionTimeByModality(
        durationSecs: 600,
        isRolling: false,
        measuredSecs: {ExerciseSection.cardio: 600},
        dominantSection: ExerciseSection.cardio,
      );
      expect(time[ExerciseSection.resistance], 0.0);
    });

    test(
      'a session with no effort that maps to a section contributes nothing',
      () {
        final time = sessionTimeByModality(
          durationSecs: 1800,
          isRolling: false,
          measuredSecs: {ExerciseSection.cardio: 2400},
          dominantSection: null,
        );
        expect(time, isEmpty);
      },
    );
  });

  group('sessionLoadByModality (D-907)', () {
    test('S-1503 the load splits in proportion to the time', () {
      final load = sessionLoadByModality(
        timeByModality: {
          ExerciseSection.resistance: 2400,
          ExerciseSection.isometric: 1200,
        },
        rating: 3,
      );
      expect(load[ExerciseSection.resistance], 120.0);
      expect(load[ExerciseSection.isometric], 60.0);
    });

    test('S-1508 a rolling session loads its measured time only', () {
      final load = sessionLoadByModality(
        timeByModality: {ExerciseSection.cardio: 1800},
        rating: 4,
      );
      expect(load, {ExerciseSection.cardio: 120.0});
    });

    test('an unrated session loads nothing', () {
      final load = sessionLoadByModality(
        timeByModality: {ExerciseSection.resistance: 3600},
        rating: null,
      );
      expect(load[ExerciseSection.resistance], 0.0);
    });

    test('zero session time loads nothing', () {
      final load = sessionLoadByModality(
        timeByModality: {ExerciseSection.resistance: 0},
        rating: 5,
      );
      expect(load[ExerciseSection.resistance], 0.0);
    });

    test('the split sums to the session load', () {
      final load = sessionLoadByModality(
        timeByModality: {
          ExerciseSection.resistance: 1800,
          ExerciseSection.cardio: 600,
          ExerciseSection.isometric: 600,
          ExerciseSection.sports: 600,
        },
        rating: 5,
      );
      final total = load.values.fold<double>(0, (a, b) => a + b);
      expect(total, closeTo(300.0, 1e-9));
    });
  });

  group('mixSegments (D-912, D-913)', () {
    test('S-1501 a single modality is one 100% segment', () {
      final segments = mixSegments({ExerciseSection.resistance: 240.0});
      expect(segments, hasLength(1));
      expect(segments.single.section, ExerciseSection.resistance);
      expect(segments.single.measure, 240.0);
      expect(segments.single.percent, 100);
    });

    test('S-1503 the segments are 67/33 in descending measure', () {
      final segments = mixSegments({
        ExerciseSection.resistance: 2400,
        ExerciseSection.isometric: 1200,
      });
      expect(segments.map((s) => s.section), [
        ExerciseSection.resistance,
        ExerciseSection.isometric,
      ]);
      expect(segments[0].percent, 67);
      expect(segments[1].percent, 33);
      expect(_percentTotal(segments), 100);
    });

    test('S-1504 the same geometry reads 67/33', () {
      final segments = mixSegments({
        ExerciseSection.resistance: 2400,
        ExerciseSection.isometric: 1200,
      });
      expect(segments[0].percent, 67);
      expect(segments[1].percent, 33);
    });

    test('S-1505 the segments are 80/20', () {
      final segments = mixSegments({
        ExerciseSection.resistance: 3600,
        ExerciseSection.cardio: 900,
      });
      expect(segments.map((s) => s.section), [
        ExerciseSection.resistance,
        ExerciseSection.cardio,
      ]);
      expect(segments[0].percent, 80);
      expect(segments[1].percent, 20);
    });

    test('S-1506 A the dominant modality is the only segment', () {
      final segments = mixSegments({ExerciseSection.isometric: 1800});
      expect(segments, hasLength(1));
      expect(segments.single.section, ExerciseSection.isometric);
      expect(segments.single.percent, 100);
    });

    test('S-1507 the dominant modality is the only segment', () {
      final segments = mixSegments({ExerciseSection.cardio: 1200});
      expect(segments, hasLength(1));
      expect(segments.single.section, ExerciseSection.cardio);
      expect(segments.single.percent, 100);
    });

    test('S-1508 the rolling session is one Cardio segment', () {
      final segments = mixSegments({ExerciseSection.cardio: 1800});
      expect(segments, hasLength(1));
      expect(segments.single.section, ExerciseSection.cardio);
      expect(segments.single.percent, 100);
    });

    test(
      'S-1512 equal measures tie-break by declaration order and sum to 100',
      () {
        final segments = mixSegments({
          ExerciseSection.cardio: 1200,
          ExerciseSection.isometric: 1200,
          ExerciseSection.sports: 1200,
        });
        expect(segments.map((s) => s.section), [
          ExerciseSection.cardio,
          ExerciseSection.isometric,
          ExerciseSection.sports,
        ]);
        expect(segments.map((s) => s.percent), [34, 33, 33]);
        expect(_percentTotal(segments), 100);
      },
    );

    test(
      'S-1515 a lifting-only window is one full-width Resistance segment',
      () {
        final segments = mixSegments({ExerciseSection.resistance: 5400});
        expect(segments, hasLength(1));
        expect(segments.single.section, ExerciseSection.resistance);
        expect(segments.single.percent, 100);
      },
    );

    test('S-1516 four modalities are 50/17/17/16 and sum to 100', () {
      final segments = mixSegments({
        ExerciseSection.resistance: 1800,
        ExerciseSection.cardio: 600,
        ExerciseSection.isometric: 600,
        ExerciseSection.sports: 600,
      });
      expect(segments.map((s) => s.section), [
        ExerciseSection.resistance,
        ExerciseSection.cardio,
        ExerciseSection.isometric,
        ExerciseSection.sports,
      ]);
      expect(segments.map((s) => s.percent), [50, 17, 17, 16]);
      expect(_percentTotal(segments), 100);
    });

    test('a zero-measure modality is never a segment', () {
      final segments = mixSegments({
        ExerciseSection.resistance: 100,
        ExerciseSection.cardio: 0,
      });
      expect(segments, hasLength(1));
      expect(segments.single.section, ExerciseSection.resistance);
    });

    test('an empty measure yields no segments', () {
      expect(mixSegments(const {}), isEmpty);
    });

    test('a positive measure always gets a segment, even at 0%', () {
      final segments = mixSegments({
        ExerciseSection.resistance: 100000,
        ExerciseSection.cardio: 1,
      });
      expect(segments, hasLength(2));
      expect(_segmentOf(segments, ExerciseSection.cardio).percent, 0);
      expect(_percentTotal(segments), 100);
    });
  });

  group('OmniDateUtils.startOfWeek (D-910, D-935)', () {
    test('monday start: every weekday resolves to the same Monday', () {
      for (var i = 0; i < 7; i++) {
        final day = DateTime(2026, 1, 5 + i);
        expect(
          OmniDateUtils.startOfWeek(day, startOfWeek: 'monday'),
          DateTime(2026, 1, 5),
        );
      }
    });

    test('sunday start: every weekday resolves to the same Sunday', () {
      for (var i = 0; i < 7; i++) {
        final day = DateTime(2026, 1, 5 + i);
        final expected = i == 6 ? DateTime(2026, 1, 11) : DateTime(2026, 1, 4);
        expect(OmniDateUtils.startOfWeek(day, startOfWeek: 'sunday'), expected);
      }
    });

    test('any setting other than sunday starts the week on Monday', () {
      final day = DateTime(2026, 1, 8);
      expect(
        OmniDateUtils.startOfWeek(day, startOfWeek: 'friday'),
        DateTime(2026, 1, 5),
      );
      expect(OmniDateUtils.startOfWeek(day), DateTime(2026, 1, 5));
    });

    test('the result is local midnight', () {
      final start = OmniDateUtils.startOfWeek(
        DateTime(2026, 1, 8, 17, 42, 13, 500),
        startOfWeek: 'monday',
      );
      expect(start.hour, 0);
      expect(start.minute, 0);
      expect(start.second, 0);
      expect(start.millisecond, 0);
    });
  });

  group('baselineBlockStarts (D-934)', () {
    test('exactly 12 blocks of 7 calendar days tile the period', () {
      final fromDay = DateTime(2026, 5, 6);
      final blocks = baselineBlockStarts(fromDay);
      expect(blocks, hasLength(kTrainingLoadBaselineWeeks));
      expect(blocks.first, DateTime(2026, 2, 11));
      expect(blocks.last, DateTime(2026, 4, 29));
      for (var i = 0; i < blocks.length; i++) {
        expect(
          blocks[i],
          DateTime(
            fromDay.year,
            fromDay.month,
            fromDay.day - (kTrainingLoadBaselineWeeks - i) * 7,
          ),
        );
        expect(blocks[i].hour, 0);
      }
    });

    test('no gap: each block starts 7 calendar days after the previous', () {
      final blocks = baselineBlockStarts(DateTime(2026, 5, 6));
      for (var i = 1; i < blocks.length; i++) {
        expect(
          blocks[i],
          DateTime(
            blocks[i - 1].year,
            blocks[i - 1].month,
            blocks[i - 1].day + 7,
          ),
        );
      }
    });

    test('the last block ends the instant before fromDay', () {
      final fromDay = DateTime(2026, 5, 6);
      final last = baselineBlockStarts(fromDay).last;
      expect(DateTime(last.year, last.month, last.day + 7), fromDay);
    });

    test('the blocks are anchored at fromDay, not at a week boundary', () {
      final fromDay = DateTime(2026, 5, 6); // a Wednesday
      final blocks = baselineBlockStarts(fromDay);
      for (final block in blocks) {
        expect(block.weekday, DateTime.wednesday);
      }
    });

    test('the blocks are unshifted across a DST transition', () {
      final transition = _dstTransitionDay();
      if (transition == null) return;
      final fromDay = DateTime(
        transition.year,
        transition.month,
        transition.day + 40,
      );
      final blocks = baselineBlockStarts(fromDay);
      for (var i = 0; i < blocks.length; i++) {
        expect(
          blocks[i].hour,
          0,
          reason: 'block $i must start at local midnight',
        );
        expect(blocks[i].minute, 0);
        expect(
          blocks[i],
          DateTime(
            fromDay.year,
            fromDay.month,
            fromDay.day - (kTrainingLoadBaselineWeeks - i) * 7,
          ),
        );
      }
    });
  });

  group('the constants (D-908, D-917, D-934)', () {
    test('the strip holds kMixStripWeeks weeks', () {
      expect(kMixStripWeeks, 8);
    });

    test('the baseline spans kTrainingLoadBaselineWeeks blocks', () {
      expect(kTrainingLoadBaselineWeeks, 12);
    });

    test('the load measure needs kTrainingLoadMinRatedWeeks rated weeks', () {
      expect(kTrainingLoadMinRatedWeeks, 4);
    });

    test('kTrainingLoadMaxUnratedShare is the inclusive unrated boundary', () {
      expect(kTrainingLoadMaxUnratedShare, 0.25);
    });

    test('the modality order is the enum declaration order', () {
      expect(ExerciseSection.values, [
        ExerciseSection.resistance,
        ExerciseSection.cardio,
        ExerciseSection.isometric,
        ExerciseSection.sports,
      ]);
    });
  });
}
