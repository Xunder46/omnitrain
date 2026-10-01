// Stats PR 3b, Phase 3 — the row guard: after any sequence of phone edits,
// skips, duplicates and watch imports, a session's rows hold exactly what its
// entries need and nothing else.
//
// Three invariants, checked per effort (D-339):
//   I-a  a timed effort holds one distance row and one extra-weight row per
//        entry, and a drill effort one extra-weight row per entry;
//   I-b  a set effort holds one reps row and one weight row per entry number,
//        and at most one extra-weight row;
//   I-c  a distance row that carries a value carries a source.
//
// Plan: `docs/plans/2026-09-27-03b-stats-pr3b-distance-source-import-plan.md`.
// Verified by `test/row_invariants_guard_test.dart` (S-883 – S-887).

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/utils/entry_rows.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

/// Every row a session's efforts hold, checked against I-a, I-b and I-c.
///
/// [step] names the move that just ran, so a failure says which step of the
/// scenario broke the store rather than only which effort.
Future<void> expectRowInvariants(
  WorkoutRepository repository,
  String sessionId, {
  required String step,
}) async {
  for (final segment in await repository.getSessionSegments(sessionId)) {
    for (final effort in await repository.getSegmentEfforts(segment.id)) {
      final rows = await repository.getEffortObservations(effort.id);
      final entries = (await repository.getTimedInstances(effort.id)).length;
      final where = '$step: effort ${effort.id} (${effort.effortKind})';

      switch (effort.effortKind) {
        case 'timed':
          _expectRowCount(rows, MetricIds.distance, entries, where);
          _expectRowCount(rows, MetricIds.extraWeight, entries, where);
        case 'drill':
          _expectRowCount(rows, MetricIds.extraWeight, entries, where);
        case 'set':
          _checkSetGroups(rows, where);
      }
      _checkDistanceSources(rows, where);
    }
  }
}

/// I-a: `count` rows of [metricId], one per entry.
void _expectRowCount(
  List<EffortObservation> rows,
  String metricId,
  int entries,
  String where,
) {
  final found = rows.where((row) => row.metricId == metricId).length;
  expect(
    found,
    entries,
    reason: '$where holds $found $metricId rows for $entries entries (I-a)',
  );
}

/// I-b: exactly one reps row and one weight row per entry number, and at most
/// one extra-weight row.
void _checkSetGroups(List<EffortObservation> rows, String where) {
  final byNumber = <int, List<EffortObservation>>{};
  for (final row in rows) {
    final number = EntryRows.numberInId(row.id);
    // D-339's numbering rule gives every row a number; a writer this guard
    // exercises (`SessionCore`, `WatchSessionImporter`) never produces the
    // legacy, number-less shape `EntryRows` still tolerates for old data, so
    // one showing up here is the guard's own signal, not a row to wave past.
    expect(
      number,
      isNotNull,
      reason: '$where holds a set row with no entry number: ${row.id}',
    );
    if (number == null) continue;
    (byNumber[number] ??= []).add(row);
  }

  for (final MapEntry(key: number, value: group) in byNumber.entries) {
    final at = '$where, entry $number';
    for (final metricId in [MetricIds.reps, MetricIds.weight]) {
      final found = group.where((row) => row.metricId == metricId).length;
      expect(found, 1, reason: '$at holds $found $metricId rows (I-b)');
    }
    final extraWeight = group
        .where((row) => row.metricId == MetricIds.extraWeight)
        .length;
    expect(
      extraWeight,
      lessThanOrEqualTo(1),
      reason: '$at holds $extraWeight extra-weight rows (I-b)',
    );
  }
}

/// I-c: a distance with a value has a source.
void _checkDistanceSources(List<EffortObservation> rows, String where) {
  for (final row in rows) {
    if (row.metricId != MetricIds.distance) continue;
    if ((row.valueReal ?? 0.0) <= 0) continue;
    expect(
      row.valueSource,
      isNotNull,
      reason: '$where holds an unsourced distance of ${row.valueReal} m (I-c)',
    );
  }
}
