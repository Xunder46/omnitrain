// The Hold Progress rule (plan 106), pure: synthetic Instruments rows, no
// repository, no widget. Scenarios S-17901 … S-17907 of
// `docs/plans/2026-11-03-106-hold-progress-plan/`.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/exercise_metric.dart';
import 'package:omnitrain/core/models/hold_progress.dart';
import 'package:omnitrain/core/models/instrument_list.dart';

InstrumentRow _row({
  String id = 'ex-squat',
  String name = 'Deep Squat',
  required num recent,
  num? previous,
  int sessions = 3,
  NativeMetric metric = NativeMetric.hold,
  NativeMetric? previousMetric,
  ExerciseSection section = ExerciseSection.isometric,
}) => InstrumentRow(
  summary: ExerciseMetricSummary(
    exerciseId: id,
    name: name,
    section: section,
    best: NativeValue(metric: metric, value: recent.toDouble()),
    points: const [],
    lastTrainedMs: 0,
    sessionCount: sessions,
  ),
  previousValue: previous == null
      ? null
      : NativeValue(metric: previousMetric ?? metric, value: previous.toDouble()),
);

InstrumentSectionData _section(
  List<InstrumentRow> rows, {
  ExerciseSection section = ExerciseSection.isometric,
}) => InstrumentSectionData(section: section, rows: rows, trainingDayCount: 3);

HoldProgressResult? _rule(List<InstrumentRow> rows) =>
    holdProgress([_section(rows)]);

void main() {
  test('the constants the rule is built from are the ones the plan names', () {
    expect(kHoldProgressMinSessions, 3);
    expect(kHoldProgressMinGainSecs, 10);
    expect(kHoldProgressMinGainPercent, 10);
    expect(kHoldProgressPriority, 40);
  });

  group('S-17901 a hold that improved', () {
    test('60 s against 40 s over three sessions', () {
      final result = _rule([_row(recent: 60, previous: 40)]);
      expect(result, isNotNull);
      expect(result!.name, 'Deep Squat');
      expect(result.recentSecs, 60);
      expect(result.previousSecs, 40);
      expect(result.gainSecs, 20);
      expect(
        holdProgressObservation(result, weeks: 4),
        'Your longest hold on Deep Squat is up 20 s over the last 4 weeks, now 60 s.',
      );
    });

    test('no sections at all is no result', () {
      expect(holdProgress(const []), isNull);
    });
  });

  group('S-17902 the gain thresholds are inclusive', () {
    test('a gain of 9 s is too small', () {
      expect(_rule([_row(recent: 49, previous: 40)]), isNull);
    });

    test('a gain of exactly 10 s that is exactly 10% fires', () {
      final result = _rule([_row(recent: 110, previous: 100)]);
      expect(result, isNotNull);
      expect(result!.gainSecs, 10);
    });

    test('a gain of 10 s that is 9.9% does not', () {
      expect(_rule([_row(recent: 111, previous: 101)]), isNull);
    });
  });

  group('S-17903 at least three sessions', () {
    test('two sessions with a big gain say nothing', () {
      expect(_rule([_row(recent: 60, previous: 40, sessions: 2)]), isNull);
    });

    test('three sessions are enough', () {
      expect(_rule([_row(recent: 60, previous: 40, sessions: 3)]), isNotNull);
    });
  });

  group('S-17904 an earlier window is needed', () {
    test('no previous value', () {
      expect(_rule([_row(recent: 60)]), isNull);
    });

    test('a previous value on another metric', () {
      expect(
        _rule([_row(recent: 60, previous: 40, previousMetric: NativeMetric.duration)]),
        isNull,
      );
    });

    test('a previous value of zero', () {
      expect(_rule([_row(recent: 60, previous: 0)]), isNull);
    });

    test('a hold that got shorter', () {
      expect(_rule([_row(recent: 40, previous: 60)]), isNull);
    });
  });

  group('S-17905 only isometric holds count', () {
    test('an isometric-section row on the duration metric is ignored', () {
      expect(
        _rule([_row(recent: 600, previous: 300, metric: NativeMetric.duration)]),
        isNull,
      );
    });

    test('a best value on another metric is ignored whatever the earlier one was', () {
      // Only `best.metric != hold` rejects this: the earlier value is a hold.
      expect(
        _rule([
          _row(
            recent: 600,
            previous: 300,
            metric: NativeMetric.duration,
            previousMetric: NativeMetric.hold,
          ),
        ]),
        isNull,
      );
    });

    test('a hold-metric row in another section is ignored', () {
      // Only the section filter rejects this: both figures are holds.
      expect(
        holdProgress([
          _section(
            [
              _row(
                recent: 60,
                previous: 40,
                section: ExerciseSection.cardio,
              ),
            ],
            section: ExerciseSection.cardio,
          ),
        ]),
        isNull,
      );
    });

    test('a resistance-section row with a big gain is ignored', () {
      expect(
        holdProgress([
          _section(
            [
              _row(
                recent: 150,
                previous: 100,
                metric: NativeMetric.estimatedOneRepMax,
                section: ExerciseSection.resistance,
              ),
            ],
            section: ExerciseSection.resistance,
          ),
        ]),
        isNull,
      );
    });
  });

  group('S-17906 the biggest gain wins', () {
    test('gains of 15, 25 and 25: the tie goes to the name ascending', () {
      final result = _rule([
        _row(id: 'ex-a', name: 'Wall Sit', recent: 55, previous: 40),
        _row(id: 'ex-b', name: 'Plank', recent: 85, previous: 60),
        _row(id: 'ex-c', name: 'Dead Hang', recent: 75, previous: 50),
      ]);
      expect(result!.name, 'Dead Hang');
      expect(result.gainSecs, 25);
    });

    test('rows of two sections: the biggest gain across sections', () {
      final result = holdProgress([
        _section([_row(id: 'ex-a', name: 'Wall Sit', recent: 55, previous: 40)]),
        _section([
          _row(id: 'ex-b', name: 'Plank', recent: 100, previous: 60),
        ]),
      ]);
      expect(result!.name, 'Plank');
    });
  });

  group('S-17907 the copy', () {
    test('a 15 s gain on Dead Hang', () {
      const result = HoldProgressResult(
        name: 'Dead Hang',
        exerciseId: 'ex-c',
        recentSecs: 75,
        previousSecs: 60,
      );
      expect(
        holdProgressObservation(result, weeks: 4),
        'Your longest hold on Dead Hang is up 15 s over the last 4 weeks, now 75 s.',
      );
    });
  });
}
