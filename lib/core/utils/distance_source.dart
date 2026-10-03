/// Distances, and the entries they belong to.
///
/// A distance is a `metric-distance` observation, but it means nothing on its
/// own: it belongs to the entry it was recorded for. Which row that is comes
/// from [EntryRows] (D-324), so the Summary's DISTANCE rows, the write behind
/// its dialog and the Stats pace cannot disagree about which distance is whose.
/// A row's source is read as stored — a row with no source is a row with no
/// source, never an entry (D-701). The other half of the story — what a source
/// means — is [DistanceSource] (D-301).
///
/// Plan: `docs/plans/2026-09-27-03a2-stats-pr3a2-entry-identity-plan.md`.
/// Verified by `test/distance_source_test.dart`.
library;

import '../../data/models/models.dart';
import '../constants/metric_ids.dart';
import 'entry_rows.dart';

abstract final class DistancePairing {
  /// The row each entry owns, in entry order: `paired[0]` is the first
  /// entry's distance row, or null when it has none.
  ///
  /// Entries are the caller's own, already in entry order; a row placed past
  /// the last entry belongs to no entry: it pairs with nothing. An entry with
  /// no row reads null. Thin delegate to [EntryRows.companions], kept so that
  /// every caller of 3a's contract reads the same pairing.
  static List<EffortObservation?> forEntries({
    required List<EffortObservation> distanceRows,
    required int entryCount,
  }) => EntryRows.companions(
    rows: distanceRows,
    metricId: MetricIds.distance,
    entryCount: entryCount,
  );
}

/// What a stored distance's source means (D-301, D-701): [isEstimated] answers
/// whether a stored value is the watch's estimate, and a distance that holds a
/// value always carries a source.
abstract final class DistanceSource {
  /// True when [stored] marks a value as the watch's estimate rather than a
  /// measurement or someone's entry. The only source that is ever marked.
  static bool isEstimated(String? stored) =>
      stored == EffortObservation.sourceEstimated;
}
