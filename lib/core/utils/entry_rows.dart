/// Entry identity: which stored row belongs to which entry (D-324).
///
/// An entry's rows are never found by their position in a list whose order
/// depends on the store, and never by an id built from the entry's display
/// position: Hive reads `obs-…-10-…` before `obs-…-2-…`, and ids are never
/// renumbered (G1, G4). A row instead carries the entry it was logged for as a
/// number in its id, and this file is the one place that reads it back — so
/// every phone reader and writer agrees on where an edit, a delete or a
/// distance lands.
///
/// Plan: `docs/plans/2026-09-27-03a2-stats-pr3a2-entry-identity-plan.md`.
/// The watch import numbers its own rows and keeps its own parser (O-2).
/// Verified by `test/entry_rows_test.dart`.
library;

import '../../data/models/models.dart';
import '../constants/metric_ids.dart';

/// One set entry: the rows that carry its number.
class SetRows {
  const SetRows(this.number, this.rows);

  /// The entry number these rows carry.
  final int number;

  final List<EffortObservation> rows;

  /// This entry's row of [metricId], or null when it holds none.
  EffortObservation? rowFor(String metricId) {
    for (final row in rows) {
      if (row.metricId == metricId) return row;
    }
    return null;
  }

  /// The entry as the UI reads it, in the shape the grouper has always built.
  Map<String, dynamic> get entry {
    final entry = <String, dynamic>{'reps': 0, 'weight': 0.0, 'skipped': false};
    for (final row in rows) {
      switch (row.metricId) {
        case MetricIds.reps:
          entry['reps'] = row.valueInt ?? 0;
          entry['skipped'] = row.valueBool ?? false;
        case MetricIds.weight:
          entry['weight'] = row.valueReal ?? 0.0;
        case MetricIds.extraWeight:
          entry['extra-weight'] = row.valueReal ?? 0.0;
      }
    }
    return entry;
  }
}

/// One entry a distance belongs to (D-328): where the write addresses it, the
/// row it owns (or none), and the number shown beside the exercise name.
class DistanceEntry {
  const DistanceEntry({
    required this.entryIndex,
    required this.row,
    required this.displayNumber,
  });

  /// The index every distance operation takes for this entry.
  final int entryIndex;

  /// The stored row, or null when the entry has none yet.
  final EffortObservation? row;

  /// 1 for the first entry. Shown only when an effort has two or more.
  final int displayNumber;

  double get metres => row?.valueReal ?? 0.0;
}

abstract final class EntryRows {
  /// The metric keys an entry-level id ends with, longest first so that
  /// `round-duration` is read as one key rather than two.
  static final List<String> _metricKeys =
      MetricIds.metricIdToKey.values.toList()
        ..sort((a, b) => b.length.compareTo(a.length));

  /// The id pattern: `obs-<effortId>-<n>-<metricKey>` (D-324). A suffix is not
  /// part of the shape, so a suffixed id carries no number (D-704).
  static final RegExp _idPattern = RegExp(
    '^obs-.*-(\\d+)-(${_metricKeys.join('|')})\$',
  );

  /// [id]'s entry number and metric key, or null when it does not follow the
  /// `obs-<effortId>-<n>-<metricKey>` pattern — an id another writer named
  /// differently, or a row the store gave a UUID (D-324).
  static ({int number, String metricKey})? parseId(String id) {
    final match = _idPattern.firstMatch(id);
    final number = int.tryParse(match?.group(1) ?? '');
    final metricKey = match?.group(2);
    if (number == null || metricKey == null) return null;
    return (number: number, metricKey: metricKey);
  }

  /// The entry number [id] carries, or null when it carries none.
  static int? numberInId(String id) => parseId(id)?.number;

  /// [rows] in entry order (D-324): by entry number, then by the order the row
  /// was written. A row with no number belongs to no entry and sorts last, in
  /// the store's own order, so the order stays total (D-705).
  static List<EffortObservation> ordered(Iterable<EffortObservation> rows) {
    final listed = rows.indexed.toList()
      ..sort((a, b) {
        final byRule = _compareByEntry(a.$2, b.$2);
        // The store's order breaks every tie, so the result does not depend on
        // which sort the runtime picks.
        return byRule != 0 ? byRule : a.$1.compareTo(b.$1);
      });
    return [for (final (_, row) in listed) row];
  }

  /// The row each entry owns of [metricId], in entry order: `paired[0]` is the
  /// first entry's row, or null when it has none. Only numbered rows pair; a
  /// row placed past the last entry belongs to no entry: it pairs with nothing
  /// and is ignored (D-321, D-322, D-713).
  static List<EffortObservation?> companions({
    required Iterable<EffortObservation> rows,
    required String metricId,
    required int entryCount,
  }) {
    final metricRows = ordered(
      rows.where(
        (row) => row.metricId == metricId && numberInId(row.id) != null,
      ),
    );
    final paired = List<EffortObservation?>.filled(entryCount, null);
    for (var i = 0; i < entryCount && i < metricRows.length; i++) {
      paired[i] = metricRows[i];
    }
    return paired;
  }

  /// The number a new row takes (D-325): 1 + the highest number the effort
  /// holds, or 0 when it holds none. Numbering above every existing row is
  /// what keeps a new row from landing on a stored one.
  static int nextNumber(Iterable<EffortObservation> rows) =>
      numberForNewRow(rows) ?? 0;

  /// The same number, or null when no row of the effort carries one — then the
  /// writer has nothing to count and keeps the name it built before.
  static int? numberForNewRow(Iterable<EffortObservation> rows) {
    var highest = -1;
    for (final row in rows) {
      final number = numberInId(row.id);
      if (number != null && number > highest) highest = number;
    }
    return highest < 0 ? null : highest + 1;
  }

  /// The effort's set entries, in entry order (D-324): entry k is the k-th
  /// group of rows that share a number, in ascending number. A row with no
  /// number belongs to no entry: it is in no group, is ignored by every reader
  /// and stays stored (D-705).
  static List<SetRows> setGroups(Iterable<EffortObservation> rows) {
    final byNumber = <int, List<EffortObservation>>{};
    for (final row in rows) {
      final number = numberInId(row.id);
      if (number == null) continue;
      (byNumber[number] ??= []).add(row);
    }

    final numbers = byNumber.keys.toList()..sort();
    return [for (final number in numbers) SetRows(number, byNumber[number]!)];
  }

  /// The effort's set entries as the UI reads them.
  static List<Map<String, dynamic>> setEntries(
    Iterable<EffortObservation> rows,
  ) => [for (final group in setGroups(rows)) group.entry];

  /// [effortId]'s distance entries (D-328).
  ///
  /// A `timed` effort's entries are its timed instances, so an entry keeps its
  /// place whether or not a distance was recorded. Any other kind has no
  /// distance entries at all: a distance belongs to a timed entry, and a row
  /// stored on another kind is not one (D-703).
  static List<DistanceEntry> distanceEntries({
    required Iterable<EffortObservation> rows,
    required int instanceCount,
  }) {
    final entries = companions(
      rows: rows,
      metricId: MetricIds.distance,
      entryCount: instanceCount,
    );

    return [
      for (var i = 0; i < entries.length; i++)
        DistanceEntry(entryIndex: i, row: entries[i], displayNumber: i + 1),
    ];
  }

  static int _compareByEntry(EffortObservation a, EffortObservation b) {
    final aNumber = numberInId(a.id);
    final bNumber = numberInId(b.id);
    if (aNumber == null || bNumber == null) {
      if (aNumber == bNumber) return 0;
      return aNumber == null ? 1 : -1;
    }
    if (aNumber != bNumber) return aNumber.compareTo(bNumber);

    final byCreated = a.createdAtMs.compareTo(b.createdAtMs);
    return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
  }
}
