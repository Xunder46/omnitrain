/// Distances, and the entries they belong to.
///
/// A distance is a `metric-distance` observation, but it means nothing on its
/// own: it belongs to the entry it was recorded for. Storage links the two by
/// nothing but the number in the row's id and their relative order, so this
/// file is the one place that turns a list of rows into the row each entry
/// owns (D-312) and that says what a row's source means (D-301). The Summary's
/// DISTANCE rows, the write behind its dialog and the Stats pace all read
/// through here, so they cannot disagree about which distance is whose.
///
/// Plan: `.github/agents/plans/2026-09-26-03a-stats-pr3a-phone-distance-plan.md`.
/// Verified by `test/distance_source_test.dart`.
library;

import '../../data/models/models.dart';
import '../constants/metric_ids.dart';

abstract final class DistancePairing {
  /// The row each entry owns, in entry order: `paired[0]` is the first
  /// entry's distance row, or null when it has none.
  ///
  /// Rows are ordered by the entry number their id carries
  /// (`obs-<effortId>-<n>-distance`), then by [EffortObservation.createdAtMs],
  /// then by id — so the pairing does not depend on the order a store happens
  /// to return them in (Hive reads `…-10-distance` before `…-2-distance`).
  /// Entries are the caller's own, already in entry order; a row past the last
  /// entry is ignored, and an entry with no row reads null.
  static List<EffortObservation?> forEntries({
    required List<EffortObservation> distanceRows,
    required int entryCount,
  }) {
    final ordered =
        distanceRows.where((row) => row.metricId == MetricIds.distance).toList()
          ..sort(_compare);

    final paired = List<EffortObservation?>.filled(entryCount, null);
    for (var i = 0; i < entryCount && i < ordered.length; i++) {
      paired[i] = ordered[i];
    }
    return paired;
  }

  /// The entry number [id] carries for [effortId], or null when it does not
  /// follow the `obs-<effortId>-<n>-distance` pattern — an id the write had to
  /// disambiguate, or a row another writer named differently.
  static int? entryNumberInId(String id, String effortId) {
    if (!id.startsWith('obs-$effortId-')) return null;
    return _entryNumber(id);
  }

  static int _compare(EffortObservation a, EffortObservation b) {
    final aNumber = _entryNumber(a.id);
    final bNumber = _entryNumber(b.id);

    if (aNumber != null && bNumber != null && aNumber != bNumber) {
      return aNumber.compareTo(bNumber);
    }
    if ((aNumber != null) != (bNumber != null)) {
      // A numbered row sorts ahead of one that could not be read: numbered
      // rows are the ones every writer names predictably.
      return aNumber != null ? -1 : 1;
    }

    final createdCompare = a.createdAtMs.compareTo(b.createdAtMs);
    return createdCompare != 0 ? createdCompare : a.id.compareTo(b.id);
  }

  /// `obs-…-<n>-distance` → `n`. An effort id may itself contain dashes, so
  /// only the suffix is matched.
  static int? _entryNumber(String id) {
    final match = RegExp(r'-(\d+)-distance$').firstMatch(id);
    return int.tryParse(match?.group(1) ?? '');
  }
}

/// What a stored distance's source means (D-301).
abstract final class DistanceSource {
  /// The source [stored] resolves to. A row with no source — every row written
  /// before the field existed, and every row the phone or the watch import
  /// writes today — reads as entered.
  static String resolve(String? stored) =>
      stored ?? EffortObservation.sourceEntered;

  /// True when [stored] marks a value as the watch's estimate rather than a
  /// measurement or someone's entry. The only source that is ever marked.
  static bool isEstimated(String? stored) =>
      stored == EffortObservation.sourceEstimated;
}
