// A day without its own nutrition target inherits the most recent earlier one.
// Targets are keyed by local midnight, so the backward walk must step by
// calendar day: a fixed 24 h step lands at 01:00 or 23:00 local after a DST
// change and never meets a key, and the inherited target comes back null.
//
// The boundary is found by scanning a fixed year (2026) for a day whose local
// length is not 24 h, so the test never depends on today's date. It needs a
// time zone with DST: in one without (UTC), it is skipped. To force one, run
// `TZ=America/New_York flutter test test/nutrition_target_dst_walk_test.dart`.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

import 'helpers/repository_harness.dart';

/// Local midnights of every day in 2026 that follows a day whose length is
/// not 24 h (the day after a DST change), with the day before it.
List<({DateTime before, DateTime after})> _dstBoundaries() {
  final found = <({DateTime before, DateTime after})>[];
  for (
    var d = DateTime(2026, 1, 1);
    d.year == 2026;
    d = DateTime(d.year, d.month, d.day + 1)
  ) {
    final next = DateTime(d.year, d.month, d.day + 1);
    if (next.difference(d) != const Duration(hours: 24)) {
      found.add((before: DateTime(d.year, d.month, d.day - 2), after: next));
    }
  }
  return found;
}

NutritionTarget _target(double protein) =>
    NutritionTarget(calories: 2000, protein: protein, carbs: 250, fat: 70);

void main() {
  final boundaries = _dstBoundaries();

  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — nutrition target across a DST change', () {
      late WorkoutRepository repo;

      setUp(() async {
        repo = await harness.open();
      });
      tearDown(() async => harness.close());

      test(
        'local zone has a DST change in 2026',
        () {
          expect(boundaries, isNotEmpty);
        },
        skip: boundaries.isEmpty ? 'time zone without DST' : null,
      );

      for (final b in boundaries) {
        test('a target saved before ${b.after.toIso8601String()} is inherited '
            'on and after the day following the change', () async {
          await repo.saveNutritionTargetForDate(
            b.before.millisecondsSinceEpoch,
            _target(150),
          );
          for (var i = 0; i < 6; i++) {
            final day = DateTime(b.after.year, b.after.month, b.after.day + i);
            final got = await repo.getNutritionTargetForDate(
              day.millisecondsSinceEpoch,
            );
            expect(got, isNotNull, reason: 'day +$i inherits nothing');
            expect(got!.protein, 150);
            expect(got.dateMs, day.millisecondsSinceEpoch);
          }
        });
      }
    });
  }
}
