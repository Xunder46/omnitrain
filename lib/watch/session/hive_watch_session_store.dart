/// Hive-backed [WatchSessionStore]: the watch's on-device persistence.
///
/// One box per record family, each row a JSON string keyed by its record id —
/// the same encoding on every platform, no adapters and no code generation.
/// The store adds rows and drops confirmed observations; it never rewrites one
/// (see `watch_session_store.dart` for the contract).
library;

import 'dart:convert';

import 'package:hive/hive.dart';

import 'watch_records.dart';
import 'watch_session_store.dart';

class HiveWatchSessionStore implements WatchSessionStore {
  HiveWatchSessionStore({String name = 'watch_session'}) : _name = name;

  /// Box-name prefix. Distinct engines on one device stay separable.
  final String _name;

  int? _lastSequence;

  Future<Box<String>> _boxFor(String recordType) =>
      Hive.openBox<String>('${_name}_${recordType}s');

  @override
  Future<T> append<T extends WatchRecord>(T record) async {
    final box = await _boxFor(record.recordType);

    final existing = box.get(record.recordId);
    if (existing != null) {
      return WatchRecord.fromJson(asJsonObject(jsonDecode(existing))) as T;
    }

    final stored = record.withSequence(await _nextSequence());
    await box.put(stored.recordId, jsonEncode(stored.toJson()));
    return stored as T;
  }

  @override
  Future<WatchStoreContents> readAll() async {
    final rows = await _allRows();
    final sessions = <WatchSessionRecord>[];
    final observations = <WatchObservationRecord>[];
    final timers = <WatchTimerRecord>[];
    final confirmations = <WatchConfirmationRecord>[];

    for (final row in rows) {
      switch (row) {
        case final WatchSessionRecord session:
          sessions.add(session);
        case final WatchObservationRecord observation:
          observations.add(observation);
        case final WatchTimerRecord timer:
          timers.add(timer);
        case final WatchConfirmationRecord confirmation:
          confirmations.add(confirmation);
      }
    }

    return WatchStoreContents(
      sessions: sessions,
      observations: applyConfirmations(observations, confirmations),
      timers: timers,
      confirmations: confirmations,
    );
  }

  @override
  Future<List<String>> pruneConfirmed() async {
    final contents = await readAll();
    final confirmed = [
      for (final observation in contents.observations)
        if (observation.confirmedAt != null) observation.recordId,
    ];

    if (confirmed.isNotEmpty) {
      final box = await _boxFor(WatchObservationRecord.type);
      await box.deleteAll(confirmed);
    }
    return confirmed;
  }

  /// Every row the store holds, in append order. Rows written in the same
  /// millisecond are ordered by the sequence the store assigned them.
  Future<List<WatchRecord>> _allRows() async {
    final rows = <WatchRecord>[];
    for (final type in const [
      WatchSessionRecord.type,
      WatchObservationRecord.type,
      WatchTimerRecord.type,
      WatchConfirmationRecord.type,
    ]) {
      final box = await _boxFor(type);
      for (final encoded in box.values) {
        rows.add(WatchRecord.fromJson(asJsonObject(jsonDecode(encoded))));
      }
    }
    rows.sort((a, b) => a.sequence.compareTo(b.sequence));
    return rows;
  }

  /// The append counter lives in memory and is rebuilt from stored rows the
  /// first time this process appends, so a relaunch never reuses a sequence.
  Future<int> _nextSequence() async {
    final highest = _lastSequence ??= (await _allRows()).fold<int>(
      0,
      (sequence, row) => row.sequence > sequence ? row.sequence : sequence,
    );
    return highest + 1;
  }
}
