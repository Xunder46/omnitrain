/// In-memory [WatchSessionStore] for tests and desktop runs.
///
/// Same append-only contract as the Hive-backed store; nothing is written to
/// disk, so it is what the unit tests use to simulate the watch's process
/// boundary (a fresh engine over the same store instance).
library;

import 'watch_records.dart';
import 'watch_session_store.dart';

class InMemoryWatchSessionStore implements WatchSessionStore {
  /// Every row, in append order. One list, because that is the whole storage
  /// model: rows are added and (after confirmation) dropped, never rewritten.
  final List<WatchRecord> _rows = [];

  int _sequence = 0;

  @override
  Future<T> append<T extends WatchRecord>(T record) async {
    for (final row in _rows) {
      if (row.recordId == record.recordId &&
          row.recordType == record.recordType) {
        return row as T;
      }
    }

    final stored = record.withSequence(++_sequence);
    _rows.add(stored);
    return stored as T;
  }

  @override
  Future<WatchStoreContents> readAll() async {
    final sessions = <WatchSessionRecord>[];
    final observations = <WatchObservationRecord>[];
    final timers = <WatchTimerRecord>[];
    final sensorSamples = <WatchSensorSampleRecord>[];
    final confirmations = <WatchConfirmationRecord>[];
    final routineCatalogs = <WatchRoutineCatalogRecord>[];

    for (final row in _rows) {
      switch (row) {
        case final WatchSessionRecord session:
          sessions.add(session);
        case final WatchObservationRecord observation:
          observations.add(observation);
        case final WatchTimerRecord timer:
          timers.add(timer);
        case final WatchSensorSampleRecord sample:
          sensorSamples.add(sample);
        case final WatchConfirmationRecord confirmation:
          confirmations.add(confirmation);
        case final WatchRoutineCatalogRecord catalog:
          routineCatalogs.add(catalog);
      }
    }

    return WatchStoreContents(
      sessions: List.unmodifiable(sessions),
      observations: List.unmodifiable(
        applyConfirmations(observations, confirmations),
      ),
      timers: List.unmodifiable(timers),
      sensorSamples: List.unmodifiable(sensorSamples),
      confirmations: List.unmodifiable(confirmations),
      routineCatalogs: List.unmodifiable(routineCatalogs),
    );
  }

  @override
  Future<List<String>> pruneConfirmed() async {
    final contents = await readAll();
    final confirmed = [
      for (final observation in contents.observations)
        if (observation.confirmedAt != null) observation.recordId,
    ];
    final dropped = confirmed.toSet();
    _rows.removeWhere(
      (row) => row is WatchObservationRecord && dropped.contains(row.recordId),
    );
    return confirmed;
  }

  @override
  Future<List<String>> pruneSensorSamples(Iterable<String> sessionIds) async {
    final sessions = sessionIds.toSet();
    final dropped = [
      for (final row in _rows)
        if (row is WatchSensorSampleRecord && sessions.contains(row.sessionId))
          row.recordId,
    ];
    _rows.removeWhere(
      (row) =>
          row is WatchSensorSampleRecord && sessions.contains(row.sessionId),
    );
    return dropped;
  }
}
