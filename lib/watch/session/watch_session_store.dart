/// The storage contract the watch session engine depends on.
///
/// Append-only by construction (PROTOCOL.md, authority rule 1): a store offers
/// no update, no delete and no remove. [WatchSessionStore.append] is the only
/// way anything enters the store, and [WatchSessionStore.pruneConfirmed] is the
/// only way anything leaves it — and it may only drop what the phone has
/// already acknowledged.
///
/// `test/watch_session_engine_test.dart` (S-004) fails the build if a mutating
/// method is added to this contract or if the engine reaches for a store method
/// outside this set.
library;

import 'watch_records.dart';

/// Everything the store holds, in append order.
class WatchStoreContents {
  const WatchStoreContents({
    this.sessions = const [],
    this.observations = const [],
    this.timers = const [],
    this.confirmations = const [],
    this.routineCatalogs = const [],
  });

  final List<WatchSessionRecord> sessions;

  /// Observations with any recorded confirmation already folded in as
  /// [WatchObservationRecord.confirmedAt].
  final List<WatchObservationRecord> observations;

  final List<WatchTimerRecord> timers;

  final List<WatchConfirmationRecord> confirmations;

  /// The reference data the phone sent down, oldest first. The newest row is
  /// the catalog that applies.
  final List<WatchRoutineCatalogRecord> routineCatalogs;

  bool get isEmpty =>
      sessions.isEmpty &&
      observations.isEmpty &&
      timers.isEmpty &&
      confirmations.isEmpty &&
      routineCatalogs.isEmpty;
}

abstract class WatchSessionStore {
  /// Writes [record], assigning its append-order sequence.
  ///
  /// Appending a record whose id is already stored is a no-op that returns the
  /// stored row: the watch's writes are replayable without duplicating data.
  Future<T> append<T extends WatchRecord>(T record);

  /// Every row, in append order, with confirmations folded into observations.
  Future<WatchStoreContents> readAll();

  /// Drops confirmed observations, returning the record ids that were dropped.
  /// Unconfirmed observations are retained indefinitely.
  Future<List<String>> pruneConfirmed();
}

/// Folds [confirmations] into [observations] as their `confirmedAt` receipt.
///
/// Read-time derivation rather than a write: the observation row is never
/// rewritten, and a confirmation is itself just another append.
List<WatchObservationRecord> applyConfirmations(
  List<WatchObservationRecord> observations,
  List<WatchConfirmationRecord> confirmations,
) {
  if (confirmations.isEmpty) return observations;

  final receipts = <String, DateTime>{};
  for (final confirmation in confirmations) {
    for (final observationId in confirmation.observationIds) {
      final existing = receipts[observationId];
      if (existing == null || confirmation.confirmedAt.isAfter(existing)) {
        receipts[observationId] = confirmation.confirmedAt;
      }
    }
  }

  return [
    for (final observation in observations)
      switch (receipts[observation.recordId]) {
        null => observation,
        final confirmedAt => observation.withConfirmation(confirmedAt),
      },
  ];
}
