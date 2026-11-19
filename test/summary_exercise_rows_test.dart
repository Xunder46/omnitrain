import 'package:flutter_test/flutter_test.dart';

import 'package:omnitrain/core/utils/summary_exercise_rows.dart';

/// Level A fixtures for plan 245, in the shape of
/// `WorkoutState.getExercisesWithEntries()` rows.
Map<String, dynamic> _exercise(
  String id,
  String name,
  String kind,
  List<Map<String, dynamic>> entries,
) => {'id': id, 'name': name, 'effortKind': kind, 'entries': entries};

String _fmtKg(double kg) =>
    kg == kg.roundToDouble() ? kg.toStringAsFixed(0) : kg.toString();

void main() {
  group('Summary exercise rows (plan 245)', () {
    test('S-24501 sets read reps x weight', () {
      final rows = buildSummaryExerciseRows(
        [
          _exercise('e1', 'Bench Press', 'set', [
            {'reps': 10, 'weight': 60.0, 'skipped': false},
            {'reps': 8, 'weight': 60.0, 'skipped': false},
            {'reps': 6, 'weight': 62.5, 'skipped': false},
          ]),
        ],
        weightUnitLabel: 'kg',
        formatWeight: _fmtKg,
      );
      expect(rows.length, 1);
      expect(rows.first.effortId, 'e1');
      expect(rows.first.name, 'Bench Press');
      expect(rows.first.items, ['10×60 kg', '8×60 kg', '6×62.5 kg']);
    });

    test('S-24502 a skipped set gives no item', () {
      final rows = buildSummaryExerciseRows(
        [
          _exercise('e1', 'Bench Press', 'set', [
            {'reps': 10, 'weight': 60.0, 'skipped': false},
            {'reps': 8, 'weight': 60.0, 'skipped': true},
          ]),
        ],
        weightUnitLabel: 'kg',
        formatWeight: _fmtKg,
      );
      expect(rows.single.items, ['10×60 kg']);
    });

    test('S-24503 bodyweight sets read reps, with added weight when given', () {
      final rows = buildSummaryExerciseRows(
        [
          _exercise('e1', 'Pull Up', 'set', [
            {'reps': 12, 'weight': 0.0, 'extra-weight': 10.0},
            {'reps': 12, 'weight': 0.0},
            {'reps': 12, 'weight': 0.0, 'extra-weight': 0.0},
          ]),
        ],
        weightUnitLabel: 'kg',
        formatWeight: _fmtKg,
      );
      expect(rows.single.items, ['12 reps +10 kg', '12 reps', '12 reps']);
    });

    test(
      'S-24504 timed entries read their elapsed time, zero gives nothing',
      () {
        final rows = buildSummaryExerciseRows(
          [
            _exercise('e1', 'Plank', 'timed', [
              {'elapsedSecs': 600, 'timedState': 'finished'},
              {'elapsedSecs': 0, 'timedState': 'notStarted'},
              {'elapsedSecs': 45, 'timedState': 'finished'},
            ]),
          ],
          weightUnitLabel: 'kg',
          formatWeight: _fmtKg,
        );
        expect(rows.single.items, ['10:00', '00:45']);
      },
    );

    test('S-24505 drill entries read their elapsed time in hours form', () {
      final rows = buildSummaryExerciseRows(
        [
          _exercise('e1', 'Bag Drill', 'drill', [
            {'elapsedSecs': 3725, 'timedState': 'finished'},
            {'elapsedSecs': 0, 'timedState': 'notStarted'},
          ]),
        ],
        weightUnitLabel: 'kg',
        formatWeight: _fmtKg,
      );
      expect(rows.single.items, ['1:02:05']);
    });

    test('S-24506 rounds read their actual duration, zero gives nothing', () {
      final rows = buildSummaryExerciseRows(
        [
          _exercise('e1', 'Rowing', 'round', [
            {'rounds': 1, 'actualDuration': 180},
            {'rounds': 2, 'actualDuration': 0},
            {'rounds': 3, 'actualDuration': 125},
          ]),
        ],
        weightUnitLabel: 'kg',
        formatWeight: _fmtKg,
      );
      expect(rows.single.items, ['03:00', '02:05']);
    });

    test('S-24507 an exercise with no logged work gives no row', () {
      final rows = buildSummaryExerciseRows(
        [
          _exercise('e1', 'Bench Press', 'set', [
            {'reps': 8, 'weight': 60.0, 'skipped': true},
          ]),
          _exercise('e2', 'Plank', 'timed', [
            {'elapsedSecs': 0, 'timedState': 'notStarted'},
          ]),
          _exercise('e3', 'Rowing', 'set', []),
        ],
        weightUnitLabel: 'kg',
        formatWeight: _fmtKg,
      );
      expect(rows, isEmpty);
    });

    test('S-24508 rows keep input order and unknown kinds give no row', () {
      final rows = buildSummaryExerciseRows(
        [
          _exercise('b', 'Bench Press', 'set', [
            {'reps': 8, 'weight': 60.0, 'skipped': false},
          ]),
          _exercise('a', 'Plank', 'timed', [
            {'elapsedSecs': 45, 'timedState': 'finished'},
          ]),
          _exercise('c', 'Mystery Move', 'mystery', [
            {'elapsedSecs': 45, 'timedState': 'finished'},
          ]),
        ],
        weightUnitLabel: 'kg',
        formatWeight: _fmtKg,
      );
      expect(rows.map((r) => r.effortId), ['b', 'a']);
      expect(rows.map((r) => r.name), ['Bench Press', 'Plank']);
    });

    test('S-24509 the unit label and the formatter are both used', () {
      final rows = buildSummaryExerciseRows(
        [
          _exercise('e1', 'Bench Press', 'set', [
            {'reps': 10, 'weight': 60.0, 'skipped': false},
          ]),
        ],
        weightUnitLabel: 'lbs',
        formatWeight: (kg) => (kg * 2.2).toStringAsFixed(1),
      );
      expect(rows.single.items, ['10×132.0 lbs']);
    });

    test('S-24510 a set with no reps gives no item', () {
      final rows = buildSummaryExerciseRows(
        [
          _exercise('e1', 'Bench Press', 'set', [
            {'reps': 0, 'weight': 60.0, 'skipped': false},
            {'reps': 5, 'weight': 60.0, 'skipped': false},
          ]),
        ],
        weightUnitLabel: 'kg',
        formatWeight: _fmtKg,
      );
      expect(rows.single.items, ['5×60 kg']);
    });
  });
}
