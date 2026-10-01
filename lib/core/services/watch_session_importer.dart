/// Turns a wrist session the phone has staged into ordinary phone history.
///
/// Plan: `docs/plans/2026-09-25-02-stats-pr2-watch-capture-plan.md`
/// (Stats PR 2), D-110, D-132 – D-138, D-140.
///
/// Everything the phone learns about a wrist session is staged first, in the
/// watch session inbox (`WatchInboxEntry`, put-if-absent by `entryId`). This
/// service reads only those staged rows and the repository — never a message —
/// so what history holds is a function of what was staged, not of the order it
/// arrived in or of how often it was delivered.
///
/// One pass over a session consumes every row staged for it and not yet
/// applied: each is materialised, used (a rating, a correction, a deletion),
/// or deliberately discarded, and then stamped applied. An applied row is a
/// tombstone: it is never materialised again, which is what keeps history the
/// user deleted deleted (D-136).
///
/// Values the importer writes come from the wrist's own data (its timestamps,
/// its summaries) or from the staging stamps of the phone's own annotations —
/// never from the phone's clock at import time — so the same staged rows
/// reach the same rows in any arrival order (S-262).
library;

import '../constants/block_types.dart';
import '../constants/metric_ids.dart';
import '../utils/entry_rows.dart';
import '../utils/logged_entry_rows.dart';
import '../../data/models/models.dart';
import '../../data/repositories/workout_repository.dart';

/// What one pass over a session did.
class WatchSessionImport {
  const WatchSessionImport({
    this.appliedEntryIds = const [],
    this.historyChanged = false,
  });

  /// The wrist entries this pass applied — materialised or discarded. What the
  /// phone's receipt names.
  final List<String> appliedEntryIds;

  /// Whether any history row was created, changed or removed.
  final bool historyChanged;
}

/// A wrist session's rows, applied to history.
class WatchSessionImporter {
  WatchSessionImporter({
    required WorkoutRepository repository,
    DateTime Function()? clock,
  }) : _repository = repository,
       _clock = clock ?? _utcNow;

  static DateTime _utcNow() => DateTime.now().toUtc();

  final WorkoutRepository _repository;
  final DateTime Function() _clock;

  static const String _completed = 'completed';

  // ---------------------------------------------------------------------------
  // Deterministic ids: every row an import creates derives from wrist ids, so a
  // second pass finds the row the first one made.
  // ---------------------------------------------------------------------------

  /// The imported session's one segment.
  static String segmentIdFor(String sessionId) => 'segment-$sessionId';

  /// The effort for one slot, exercise and (phone) effort kind — the key
  /// D-134 gives an effort. It ends with the kind, so the entry index the
  /// phone parses out of an observation id is never taken from it.
  static String effortIdFor(
    String sessionId,
    String sessionExerciseId,
    String exerciseId,
    String effortKind,
  ) => 'effort-$sessionId-$sessionExerciseId-$exerciseId-$effortKind';

  /// The `TimedInstance` of a timed or hold entry.
  static String timedInstanceIdFor(String sessionId, String entryId) =>
      'timed-$sessionId-$entryId';

  /// The `RoundInstance` of a round entry.
  static String roundInstanceIdFor(String sessionId, String entryId) =>
      'round-$sessionId-$entryId';

  /// The phone's effort kind for a wire kind: a hold is the phone's `drill`.
  static String effortKindFor(String wireKind) => switch (wireKind) {
    WatchInboxEntry.kindTimed => BlockTypes.timed,
    WatchInboxEntry.kindRound => BlockTypes.round,
    WatchInboxEntry.kindHold => BlockTypes.drill,
    _ => BlockTypes.set,
  };

  static const Set<String> _effortKinds = {
    WatchInboxEntry.kindSet,
    WatchInboxEntry.kindTimed,
    WatchInboxEntry.kindRound,
    WatchInboxEntry.kindHold,
  };

  // ---------------------------------------------------------------------------
  // The pass
  // ---------------------------------------------------------------------------

  /// Applies every staged, unapplied row of [watchSessionId].
  ///
  /// Nothing happens before the session's `session_end` is staged: until then
  /// the rows wait. After it, the session is imported (completed, with at
  /// least one effort entry the phone did not delete), or its rows are
  /// consumed without history (abandoned, empty, or deleted by the user), or
  /// an imported session is topped up with what arrived since.
  Future<WatchSessionImport> apply(String watchSessionId) async {
    final rows = await _repository.getWatchInboxEntriesForSession(
      watchSessionId,
    );
    final endRow = _first(
      rows,
      (row) =>
          row.origin == WatchInboxEntry.originWatch &&
          row.kind == WatchInboxEntry.kindSessionEnd,
    );
    if (endRow == null) return const WatchSessionImport();

    final unapplied = [
      for (final row in rows)
        if (row.appliedAtMs == null) row,
    ];
    if (unapplied.isEmpty) return const WatchSessionImport();

    final end = _End.parse(endRow);
    if (end == null || end.status != _completed) {
      // An abandoned session is consumed and acknowledged without history
      // (D-133). An end the phone cannot read can never import, and a row
      // nothing can use is not one the wrist should re-send for ever.
      return _consume(unapplied);
    }

    final corrections = [
      for (final row in rows)
        if (row.kind == WatchInboxEntry.kindPhoneCorrection) row,
    ];
    final deletions = [
      for (final row in rows)
        if (row.kind == WatchInboxEntry.kindPhoneDeletion) row,
    ];
    final deleted = {for (final row in deletions) ?_entryIdOf(row)};
    final deletedEarlier = {
      for (final row in deletions)
        if (row.appliedAtMs != null) ?_entryIdOf(row),
    };

    final entries = [
      for (final row in rows)
        if (row.origin == WatchInboxEntry.originWatch &&
            _effortKinds.contains(row.kind))
          ?_Entry.parse(row, corrections),
    ];
    // What earlier passes turned into rows, and what history should hold now.
    final materialised = [
      for (final entry in entries)
        if (entry.row.appliedAtMs != null &&
            !deletedEarlier.contains(entry.entryId))
          entry,
    ];
    final live = [
      for (final entry in entries)
        if (!deleted.contains(entry.entryId)) entry,
    ];

    final existing = await _repository.getSession(watchSessionId);
    if (existing == null) {
      // An applied end with rows behind it means history held this session
      // and the user deleted it: it stays deleted (D-136). With nothing the
      // phone did not delete, the session is empty (D-133) — until a late
      // entry arrives, which imports it then (the same history as if that
      // entry had arrived first).
      final deletedByUser =
          endRow.appliedAtMs != null && materialised.isNotEmpty;
      if (deletedByUser || live.isEmpty) return _consume(unapplied);
    }

    final pass = _Pass(
      repository: _repository,
      sessionId: watchSessionId,
      end: end,
    );
    await pass.run(
      existing: existing,
      rows: rows,
      unapplied: unapplied,
      corrections: corrections,
      materialised: materialised,
      live: live,
    );
    await _markApplied(unapplied);
    return WatchSessionImport(
      appliedEntryIds: _wristIds(unapplied),
      historyChanged: pass.changed,
    );
  }

  Future<WatchSessionImport> _consume(List<WatchInboxEntry> unapplied) async {
    await _markApplied(unapplied);
    return WatchSessionImport(appliedEntryIds: _wristIds(unapplied));
  }

  Future<void> _markApplied(List<WatchInboxEntry> rows) =>
      _repository.markWatchInboxEntriesApplied([
        for (final row in rows) row.entryId,
      ], _clock().toUtc().millisecondsSinceEpoch);

  static List<String> _wristIds(List<WatchInboxEntry> rows) => [
    for (final row in rows)
      if (row.origin == WatchInboxEntry.originWatch) row.entryId,
  ];

  static String? _entryIdOf(WatchInboxEntry annotation) {
    final entryId = annotation.payload['entryId'];
    return entryId is String && entryId.isNotEmpty ? entryId : null;
  }

  static WatchInboxEntry? _first(
    Iterable<WatchInboxEntry> rows,
    bool Function(WatchInboxEntry) test,
  ) {
    for (final row in rows) {
      if (test(row)) return row;
    }
    return null;
  }
}

// -----------------------------------------------------------------------------
// One pass: what it writes
// -----------------------------------------------------------------------------

class _Pass {
  _Pass({
    required WorkoutRepository repository,
    required this.sessionId,
    required this.end,
  }) : _repository = repository;

  final WorkoutRepository _repository;
  final String sessionId;
  final _End end;

  /// Whether this pass wrote anything to history.
  bool changed = false;

  Future<void> run({
    required TrainingSession? existing,
    required List<WatchInboxEntry> rows,
    required List<WatchInboxEntry> unapplied,
    required List<WatchInboxEntry> corrections,
    required List<_Entry> materialised,
    required List<_Entry> live,
  }) async {
    if (existing == null) {
      await _createSession(rows);
    } else {
      await _topUpRating(existing, unapplied);
      if (end.row.appliedAtMs == null) await _attachSessionSummary();
    }

    final segmentId = await _segmentId();
    final efforts = {
      for (final effort in await _repository.getSegmentEfforts(segmentId))
        effort.id: effort,
    };
    final before = _byKey(materialised);
    final now = _byKey(live);

    // Efforts rank by their first entry, then its entryId (D-134).
    final ranked = now.keys.toList()
      ..sort((a, b) => _Entry.compare(now[a]!.first, now[b]!.first));
    // The fields each entry's corrections staged since the last pass name:
    // only those are applied to rows already in history, so an edit the user
    // made to another field on the phone stays (D-137).
    final freshCorrections = <String, Set<String>>{};
    for (final row in unapplied) {
      if (row.kind != WatchInboxEntry.kindPhoneCorrection) continue;
      final entryId = WatchSessionImporter._entryIdOf(row);
      final values = row.payload['correction'];
      if (entryId == null || values is! Map) continue;
      (freshCorrections[entryId] ??= {}).addAll(values.keys.cast<String>());
    }

    for (var rank = 0; rank < ranked.length; rank++) {
      final key = ranked[rank];
      final effortId = key.effortId(sessionId);
      final prior = efforts[effortId];
      final earlier = before[key] ?? const <_Entry>[];
      // The user removed this effort from history: it is never re-created.
      if (prior == null && earlier.isNotEmpty) continue;
      await _placeEffort(key, effortId, segmentId, prior, rank, now[key]!);
      await _placeEntries(key, effortId, earlier, now[key]!, freshCorrections);
    }

    // Every entry of an effort was deleted after it was imported.
    for (final key in before.keys) {
      if (now.containsKey(key)) continue;
      final effortId = key.effortId(sessionId);
      if (!efforts.containsKey(effortId)) continue;
      final rows = await _EffortRows.read(
        _repository,
        sessionId: sessionId,
        effortId: effortId,
        before: before[key]!,
        now: const [],
      );
      if (rows.holdsUserRows) {
        // Rows the user added keep the effort: only the wrist's go (A-51).
        await _placeAroundUserRows(
          key,
          effortId,
          before[key]!,
          const [],
          const {},
          rows,
        );
        continue;
      }
      await _repository.deleteEffort(effortId);
      changed = true;
    }
  }

  // --- The session ------------------------------------------------------------

  Future<void> _createSession(List<WatchInboxEntry> rows) async {
    await _repository.createSession(
      TrainingSession(
        id: sessionId,
        ownerUserId: LoggedEntryRows.ownerUserId,
        startedAtMs: end.startedAtMs,
        endedAtMs: end.endedAtMs,
        modality: end.modality,
        sessionFeeling: _ratingAtImport(rows),
        createdAtMs: end.startedAtMs,
        updatedAtMs: end.endedAtMs,
      ),
    );
    changed = true;
    await _attachSessionSummary();
  }

  /// D-138: the phone's own staged rating, else the wrist's, else none.
  int? _ratingAtImport(List<WatchInboxEntry> rows) =>
      _ratingOf(rows, WatchInboxEntry.kindPhoneRating) ??
      _ratingOf(rows, WatchInboxEntry.kindEffortRating);

  /// After import, the phone's own rating always wins, and the wrist's
  /// applies only while the session has none (D-138).
  Future<void> _topUpRating(
    TrainingSession session,
    List<WatchInboxEntry> unapplied,
  ) async {
    final phone = _ratingOf(unapplied, WatchInboxEntry.kindPhoneRating);
    final wrist = _ratingOf(unapplied, WatchInboxEntry.kindEffortRating);
    final rating = phone ?? (session.sessionFeeling == null ? wrist : null);
    if (rating == null || rating == session.sessionFeeling) return;

    // Through the row's own map, so no field of the session is dropped; the
    // stamps stay the wrist's (see the library comment).
    await _repository.updateSession(
      TrainingSession.fromMap({...session.toMap(), 'session_feeling': rating}),
    );
    changed = true;
  }

  static int? _ratingOf(List<WatchInboxEntry> rows, String kind) {
    for (final row in rows) {
      if (row.kind != kind) continue;
      final rating = row.payload['rating'];
      if (rating is int && rating >= 1 && rating <= 5) return rating;
    }
    return null;
  }

  Future<String> _segmentId() async {
    final segments = await _repository.getSessionSegments(sessionId);
    if (segments.isNotEmpty) {
      final first = [...segments]
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      return first.first.id;
    }
    final segment = LoggedEntryRows.defaultSegment(
      id: WatchSessionImporter.segmentIdFor(sessionId),
      sessionId: sessionId,
      atMs: end.startedAtMs,
    );
    await _repository.createSegment(segment);
    changed = true;
    return segment.id;
  }

  // --- Efforts ----------------------------------------------------------------

  Future<void> _placeEffort(
    _Key key,
    String effortId,
    String segmentId,
    SegmentEffort? prior,
    int rank,
    List<_Entry> entries,
  ) async {
    final firstAt = entries.first.loggedAtMs;
    if (prior == null) {
      await _repository.createEffort(
        SegmentEffort(
          id: effortId,
          segmentId: segmentId,
          orderIndex: rank,
          topLevelOrderIndex: rank,
          effortKind: key.effortKind,
          exerciseId: key.exerciseId,
          createdAtMs: firstAt,
          updatedAtMs: firstAt,
        ),
      );
      changed = true;
      if (key.effortKind == BlockTypes.set) {
        await _attachSetBlockSummary(key, effortId);
      }
      return;
    }

    final priorRank = prior.topLevelOrderIndex ?? prior.orderIndex;
    if (prior.orderIndex == rank &&
        priorRank == rank &&
        prior.createdAtMs == firstAt) {
      return;
    }
    await _repository.updateEffort(
      SegmentEffort.fromMap({
        ...prior.toMap(),
        'order_index': rank,
        'top_level_order_index': rank,
        'created_at_ms': firstAt,
        'updated_at_ms': firstAt,
      }),
    );
    changed = true;
  }

  // --- Entries ----------------------------------------------------------------

  /// Brings one effort's entry rows to [now]: entries deleted since they were
  /// imported are removed, entries whose position moved (an earlier entry
  /// arrived late) are moved, new entries are created, and corrections staged
  /// since the import are applied. Positions are the entries' order by
  /// `loggedAt`, then `entryId` (D-134) — unless the user has added rows of
  /// their own to the effort, which [_placeAroundUserRows] then keeps.
  Future<void> _placeEntries(
    _Key key,
    String effortId,
    List<_Entry> before,
    List<_Entry> now,
    Map<String, Set<String>> freshCorrections,
  ) async {
    final rows = await _EffortRows.read(
      _repository,
      sessionId: sessionId,
      effortId: effortId,
      before: before,
      now: now,
    );
    if (rows.holdsUserRows) {
      await _placeAroundUserRows(
        key,
        effortId,
        before,
        now,
        freshCorrections,
        rows,
      );
      return;
    }

    final oldIndex = {
      for (var i = 0; i < before.length; i++) before[i].entryId: i,
    };
    final newIndex = {for (var i = 0; i < now.length; i++) now[i].entryId: i};
    final removed = [
      for (final entry in before)
        if (!newIndex.containsKey(entry.entryId)) entry,
    ];
    final moved = [
      for (final entry in before)
        if (newIndex.containsKey(entry.entryId) &&
            newIndex[entry.entryId] != oldIndex[entry.entryId])
          entry,
    ];
    final added = [
      for (final entry in now)
        if (!oldIndex.containsKey(entry.entryId)) entry,
    ];

    // Observation ids carry the entry index, so a moved entry's rows are
    // re-keyed: every affected row is read and deleted first, then written at
    // its new index, so no move can land on a row another has yet to leave.
    if (removed.isNotEmpty || moved.isNotEmpty) {
      final byIndex = _observationsByIndex(
        effortId,
        await _repository.getEffortObservations(effortId),
      );
      for (final entry in [...removed, ...moved]) {
        for (final row in byIndex[oldIndex[entry.entryId]!] ?? const []) {
          await _repository.deleteObservation(row.observation.id);
          changed = true;
        }
      }
      for (final entry in moved) {
        for (final row in byIndex[oldIndex[entry.entryId]!] ?? const []) {
          await _repository.createObservation(
            EffortObservation.fromMap({
              ...row.observation.toMap(),
              'id': LoggedEntryRows.observationId(
                effortId,
                newIndex[entry.entryId]!,
                row.metricKey,
              ),
            }),
          );
        }
      }
    }

    for (final entry in removed) {
      await _deleteInstance(entry, effortId);
    }
    for (final entry in moved) {
      await _reindexInstance(entry, effortId, newIndex[entry.entryId]!);
    }
    for (final entry in added) {
      await _createEntry(key, entry, effortId, newIndex[entry.entryId]!);
    }
    for (final entry in now) {
      if (!oldIndex.containsKey(entry.entryId)) continue;
      final fields = freshCorrections[entry.entryId];
      if (fields == null) continue;
      await _applyCorrections(
        entry,
        effortId,
        newIndex[entry.entryId]!,
        fields,
      );
    }
  }

  /// An imported effort the user has added rows of their own to in history
  /// (A-51). It is the user's to arrange: nothing already in it moves, a wrist
  /// entry that arrives now is placed after its last row, and a change the
  /// phone makes to a wrist entry reaches only that entry's own rows, found by
  /// the stamp every imported row carries ([_EffortRows]). No wrist entry ever
  /// lands on, moves, edits or deletes a row the user made.
  Future<void> _placeAroundUserRows(
    _Key key,
    String effortId,
    List<_Entry> before,
    List<_Entry> now,
    Map<String, Set<String>> freshCorrections,
    _EffortRows rows,
  ) async {
    final placed = {for (final entry in before) entry.entryId};
    final live = {for (final entry in now) entry.entryId};

    // Deleted since they were imported: their own rows go, nothing else.
    for (final entry in before) {
      if (live.contains(entry.entryId)) continue;
      for (final row in rows.ownRowsOf(entry)) {
        await _repository.deleteObservation(row.id);
        changed = true;
      }
      await _deleteInstance(entry, effortId);
    }

    // New to history: after the effort's last row, in logged order — or where
    // a pass that did not finish already put it.
    var next = rows.lastIndex + 1;
    for (final entry in now) {
      if (placed.contains(entry.entryId)) continue;
      final index = rows.unfinishedPlaceOf(entry) ?? next++;
      await _createEntry(key, entry, effortId, index);
      // An instance a pass that did not finish left elsewhere follows its rows.
      await _reindexInstance(entry, effortId, index);
    }

    for (final entry in now) {
      if (!placed.contains(entry.entryId)) continue;
      final fields = freshCorrections[entry.entryId];
      if (fields == null) continue;
      await _applyCorrections(
        entry,
        effortId,
        rows.indexOf(entry),
        fields,
        ownRowsOnly: true,
      );
    }
  }

  static Map<int, List<({EffortObservation observation, String metricKey})>>
  _observationsByIndex(String effortId, List<EffortObservation> rows) {
    final prefix = 'obs-$effortId-';
    final grouped =
        <int, List<({EffortObservation observation, String metricKey})>>{};
    for (final row in rows) {
      if (!row.id.startsWith(prefix)) continue;
      final parsed = EntryRows.parseId(row.id);
      if (parsed == null) continue;
      (grouped[parsed.number] ??= []).add((
        observation: row,
        metricKey: parsed.metricKey,
      ));
    }
    return grouped;
  }

  Future<void> _deleteInstance(_Entry entry, String effortId) async {
    switch (entry.wireKind) {
      case WatchInboxEntry.kindTimed:
      case WatchInboxEntry.kindHold:
        final id = WatchSessionImporter.timedInstanceIdFor(
          sessionId,
          entry.entryId,
        );
        if (await _timedInstance(effortId, id) == null) return;
        await _repository.deleteTimedInstance(id);
        changed = true;
      case WatchInboxEntry.kindRound:
        final id = WatchSessionImporter.roundInstanceIdFor(
          sessionId,
          entry.entryId,
        );
        if (await _roundInstance(effortId, id) == null) return;
        await _repository.deleteRoundInstance(id);
        changed = true;
    }
  }

  Future<void> _reindexInstance(
    _Entry entry,
    String effortId,
    int index,
  ) async {
    switch (entry.wireKind) {
      case WatchInboxEntry.kindTimed:
      case WatchInboxEntry.kindHold:
        final instance = await _timedInstance(
          effortId,
          WatchSessionImporter.timedInstanceIdFor(sessionId, entry.entryId),
        );
        if (instance == null || instance.entryIndex == index) return;
        await _repository.updateTimedInstance(
          instance.copyWith(entryIndex: index),
        );
        changed = true;
      case WatchInboxEntry.kindRound:
        final instance = await _roundInstance(
          effortId,
          WatchSessionImporter.roundInstanceIdFor(sessionId, entry.entryId),
        );
        if (instance == null || instance.roundIndex == index) return;
        await _repository.updateRoundInstance(
          instance.copyWith(roundIndex: index),
        );
        changed = true;
    }
  }

  /// One entry's rows, exactly as the phone's own logging builds them
  /// (`LoggedEntryRows`), with the wrist's values in them.
  Future<void> _createEntry(
    _Key key,
    _Entry entry,
    String effortId,
    int index,
  ) async {
    final at = entry.loggedAtMs;
    final List<EffortObservation> observations;
    switch (entry.wireKind) {
      case WatchInboxEntry.kindSet:
        final exercise = await _repository.getExerciseById(key.exerciseId);
        observations = LoggedEntryRows.setObservations(
          effortId: effortId,
          entryIndex: index,
          reps: entry.reps!,
          weightKg: entry.loadKg ?? 0.0,
          exerciseHasLoad: exercise?.capabilities.contains('load') ?? false,
          atMs: at,
        );
      case WatchInboxEntry.kindTimed:
        await _createTimedInstance(entry, effortId, index);
        observations = LoggedEntryRows.timedObservations(
          effortId: effortId,
          entryIndex: index,
          distanceMeters: entry.distanceMeters ?? 0.0,
          // A distance the wrist dialled without naming its source was
          // entered by hand: watch sessions never run GPS (D-335).
          distanceSource: (entry.distanceMeters ?? 0.0) > 0
              ? entry.distanceSource ?? EffortObservation.sourceEntered
              : null,
          atMs: at,
        );
      case WatchInboxEntry.kindHold:
        await _createTimedInstance(entry, effortId, index);
        observations = LoggedEntryRows.drillObservations(
          effortId: effortId,
          entryIndex: index,
          extraWeightKg: entry.extraLoadKg ?? 0.0,
          atMs: at,
        );
      default:
        await _createRoundInstance(entry, effortId, index);
        observations = const [];
    }
    for (final observation in observations) {
      await _repository.createObservation(
        _stampedByCorrections(observation, entry),
      );
    }
    changed = true;
  }

  Future<void> _createTimedInstance(
    _Entry entry,
    String effortId,
    int index,
  ) async {
    final id = WatchSessionImporter.timedInstanceIdFor(
      sessionId,
      entry.entryId,
    );
    if (await _timedInstance(effortId, id) == null) {
      await _repository.createTimedInstance(
        TimedInstance(
          id: id,
          effortId: effortId,
          entryIndex: index,
          actualDurationSecs: entry.activeSecs(),
          startedAtMs: entry.startedAtMs!,
          finishedAtMs: entry.endedAtMs!,
          state: TimedState.finished,
          createdAtMs: entry.loggedAtMs,
          updatedAtMs: entry.windowStampMs,
        ),
      );
    }
    await _attach(
      () => SensorSummary(
        sessionId: sessionId,
        scope: SensorSummary.scopeTimedInstance,
        targetId: id,
        windowStartMs: entry.measuredStartMs!,
        windowEndMs: entry.measuredEndMs!,
        avgHeartRateBpm: entry.avgHeartRateBpm,
        maxHeartRateBpm: entry.maxHeartRateBpm,
        steps: entry.steps,
        createdAtMs: entry.loggedAtMs,
      ),
      when: entry.hasSummary,
    );
  }

  Future<void> _createRoundInstance(
    _Entry entry,
    String effortId,
    int index,
  ) async {
    final id = WatchSessionImporter.roundInstanceIdFor(
      sessionId,
      entry.entryId,
    );
    if (await _roundInstance(effortId, id) == null) {
      final actual = entry.activeSecs();
      await _repository.createRoundInstance(
        RoundInstance(
          id: id,
          effortId: effortId,
          roundIndex: index,
          plannedDurationSecs: actual,
          actualDurationSecs: actual,
          startedAtMs: entry.startedAtMs!,
          finishedAtMs: entry.endedAtMs!,
          completed: true,
          state: RoundState.finished,
          totalPausedDurationMs: entry.pausedMs,
          createdAtMs: entry.loggedAtMs,
          updatedAtMs: entry.windowStampMs,
        ),
      );
    }
    await _attach(
      () => SensorSummary(
        sessionId: sessionId,
        scope: SensorSummary.scopeRoundInstance,
        targetId: id,
        windowStartMs: entry.measuredStartMs!,
        windowEndMs: entry.measuredEndMs!,
        avgHeartRateBpm: entry.avgHeartRateBpm,
        maxHeartRateBpm: entry.maxHeartRateBpm,
        createdAtMs: entry.loggedAtMs,
      ),
      when: entry.hasSummary,
    );
  }

  /// A correction staged after the import edits the imported row: only the
  /// metrics it names, so an edit the user made to another stays (D-137).
  ///
  /// [index] is where the entry's rows are, or null when they cannot be found
  /// — then a set's correction has nothing to edit. With [ownRowsOnly] a row
  /// is edited only if it carries the entry's own stamp (A-51).
  Future<void> _applyCorrections(
    _Entry entry,
    String effortId,
    int? index,
    Set<String> fields, {
    bool ownRowsOnly = false,
  }) async {
    final windowCorrected =
        (fields.contains('startedAt') || fields.contains('endedAt')) &&
        entry.windowCorrected;
    switch (entry.wireKind) {
      case WatchInboxEntry.kindSet:
        if (index == null) return;
        for (final (key, metricKey) in const [
          ('reps', 'reps'),
          ('loadKg', 'weight'),
        ]) {
          if (!fields.contains(key) || !entry.correctedAtMs.containsKey(key)) {
            continue;
          }
          final id = LoggedEntryRows.observationId(effortId, index, metricKey);
          EffortObservation? row;
          for (final o in await _repository.getEffortObservations(effortId)) {
            if (o.id == id) row = o;
          }
          if (row == null) continue;
          if (ownRowsOnly && row.createdAtMs != entry.loggedAtMs) continue;
          final updated = EffortObservation.fromMap({
            ...row.toMap(),
            if (key == 'reps') 'value_int': entry.reps,
            if (key == 'loadKg') 'value_real': entry.loadKg ?? 0.0,
            'updated_at_ms': entry.stampFor(key),
          });
          await _repository.updateObservation(updated);
          changed = true;
        }
      case WatchInboxEntry.kindTimed:
      case WatchInboxEntry.kindHold:
        if (!windowCorrected) return;
        final instance = await _timedInstance(
          effortId,
          WatchSessionImporter.timedInstanceIdFor(sessionId, entry.entryId),
        );
        if (instance == null) return;
        await _repository.updateTimedInstance(
          instance.copyWith(
            startedAtMs: entry.startedAtMs,
            finishedAtMs: entry.endedAtMs,
            actualDurationSecs: entry.activeSecs(),
            updatedAtMs: entry.windowStampMs,
          ),
        );
        changed = true;
      default:
        if (!windowCorrected) return;
        final instance = await _roundInstance(
          effortId,
          WatchSessionImporter.roundInstanceIdFor(sessionId, entry.entryId),
        );
        if (instance == null) return;
        final actual = entry.activeSecs();
        await _repository.updateRoundInstance(
          instance.copyWith(
            startedAtMs: entry.startedAtMs,
            finishedAtMs: entry.endedAtMs,
            actualDurationSecs: actual,
            plannedDurationSecs: actual,
            updatedAtMs: entry.windowStampMs,
          ),
        );
        changed = true;
    }
  }

  /// A row a correction touched is stamped with the correction's staging time;
  /// the same stamp whether the correction arrived before or after the import.
  static EffortObservation _stampedByCorrections(
    EffortObservation row,
    _Entry entry,
  ) {
    final field = switch (row.metricId) {
      MetricIds.reps => 'reps',
      MetricIds.weight => 'loadKg',
      _ => null,
    };
    if (field == null || !entry.correctedAtMs.containsKey(field)) return row;
    return EffortObservation.fromMap({
      ...row.toMap(),
      'updated_at_ms': entry.stampFor(field),
    });
  }

  Future<TimedInstance?> _timedInstance(String effortId, String id) async {
    for (final instance in await _repository.getTimedInstances(effortId)) {
      if (instance.id == id) return instance;
    }
    return null;
  }

  Future<RoundInstance?> _roundInstance(String effortId, String id) async {
    for (final instance in await _repository.getRoundInstances(effortId)) {
      if (instance.id == id) return instance;
    }
    return null;
  }

  // --- Summaries --------------------------------------------------------------

  /// Summaries attach when their target is created — which may be long after
  /// the summary itself arrived (a set block travels in `session_end`).
  Future<void> _attachSessionSummary() => _attach(
    () => SensorSummary(
      sessionId: sessionId,
      scope: SensorSummary.scopeSession,
      targetId: sessionId,
      windowStartMs: end.startedAtMs,
      windowEndMs: end.endedAtMs,
      avgHeartRateBpm: end.avgHeartRateBpm,
      maxHeartRateBpm: end.maxHeartRateBpm,
      createdAtMs: end.loggedAtMs,
    ),
    when: end.avgHeartRateBpm != null || end.maxHeartRateBpm != null,
  );

  Future<void> _attachSetBlockSummary(_Key key, String effortId) async {
    for (final block in end.setBlocks) {
      if (block.sessionExerciseId != key.sessionExerciseId ||
          block.exerciseId != key.exerciseId) {
        continue;
      }
      await _attach(
        () => SensorSummary(
          sessionId: sessionId,
          scope: SensorSummary.scopeEffort,
          targetId: effortId,
          windowStartMs: block.startedAtMs,
          windowEndMs: block.endedAtMs,
          avgHeartRateBpm: block.avgHeartRateBpm,
          maxHeartRateBpm: block.maxHeartRateBpm,
          createdAtMs: end.loggedAtMs,
        ),
        when: true,
      );
    }
  }

  /// Stores a summary unless one is already there. A summary the model
  /// refuses (D-131: absence is never zero, the pair travels together) is a
  /// measurement the phone does not keep, never a reason to stop the import.
  Future<void> _attach(
    SensorSummary Function() build, {
    required bool when,
  }) async {
    if (!when) return;
    final SensorSummary summary;
    try {
      summary = build();
    } on ArgumentError {
      return;
    }
    if (await _repository.createSensorSummary(summary)) changed = true;
  }

  static Map<_Key, List<_Entry>> _byKey(List<_Entry> entries) {
    final grouped = <_Key, List<_Entry>>{};
    for (final entry in entries) {
      (grouped[entry.key] ??= []).add(entry);
    }
    for (final list in grouped.values) {
      list.sort(_Entry.compare);
    }
    return grouped;
  }
}

// -----------------------------------------------------------------------------
// Whose rows an imported effort holds (A-51)
// -----------------------------------------------------------------------------

/// One imported effort's rows as a pass finds them, told apart into the
/// importer's and the user's.
///
/// Every row the importer writes carries its entry's `loggedAt` as its
/// `createdAtMs` (A-40), which no edit through the phone changes; and while
/// nobody else has added to the effort, its entries sit in logged order. So a
/// row is the importer's when it carries the stamp of the entry that order
/// puts at its index, or of an entry not yet placed (rows a pass that did not
/// finish wrote); an instance is the importer's when its id is one the
/// importer gives a staged entry. Anything else was made by the user.
class _EffortRows {
  _EffortRows._({
    required this.holdsUserRows,
    required this.lastIndex,
    required String sessionId,
    required Map<int, List<EffortObservation>> byIndex,
    required Map<int, Set<int>> indicesByStamp,
    required Map<int, int> stagedPerStamp,
    required Map<String, int> instanceIndex,
    required Map<int, int> instancesAt,
  }) : _sessionId = sessionId,
       _byIndex = byIndex,
       _indicesByStamp = indicesByStamp,
       _stagedPerStamp = stagedPerStamp,
       _instanceIndex = instanceIndex,
       _instancesAt = instancesAt;

  /// Whether the effort holds a row or an instance the user made.
  final bool holdsUserRows;

  /// The highest position any row or instance of the effort holds, or -1.
  final int lastIndex;

  final String _sessionId;
  final Map<int, List<EffortObservation>> _byIndex;
  final Map<int, Set<int>> _indicesByStamp;
  final Map<int, int> _stagedPerStamp;
  final Map<String, int> _instanceIndex;
  final Map<int, int> _instancesAt;

  static Future<_EffortRows> read(
    WorkoutRepository repository, {
    required String sessionId,
    required String effortId,
    required List<_Entry> before,
    required List<_Entry> now,
  }) async {
    final placedIds = {for (final entry in before) entry.entryId};
    final laidOut = {
      for (var i = 0; i < before.length; i++) i: before[i].loggedAtMs,
    };
    final unplacedStamps = {
      for (final entry in now)
        if (!placedIds.contains(entry.entryId)) entry.loggedAtMs,
    };
    final staged = {
      for (final entry in [...before, ...now]) entry.entryId: entry,
    };
    final stagedPerStamp = <int, int>{};
    for (final entry in staged.values) {
      stagedPerStamp[entry.loggedAtMs] =
          (stagedPerStamp[entry.loggedAtMs] ?? 0) + 1;
    }
    final ownInstanceIds = {
      for (final entry in staged.values) ...{
        WatchSessionImporter.timedInstanceIdFor(sessionId, entry.entryId),
        WatchSessionImporter.roundInstanceIdFor(sessionId, entry.entryId),
      },
    };

    var holdsUserRows = false;
    var lastIndex = -1;
    final byIndex = <int, List<EffortObservation>>{};
    final indicesByStamp = <int, Set<int>>{};
    final grouped = _Pass._observationsByIndex(
      effortId,
      await repository.getEffortObservations(effortId),
    );
    for (final MapEntry(key: index, value: rows) in grouped.entries) {
      if (index > lastIndex) lastIndex = index;
      for (final (:observation, metricKey: _) in rows) {
        final stamp = observation.createdAtMs;
        (byIndex[index] ??= []).add(observation);
        (indicesByStamp[stamp] ??= {}).add(index);
        if (stamp != laidOut[index] && !unplacedStamps.contains(stamp)) {
          holdsUserRows = true;
        }
      }
    }

    final instanceIndex = <String, int>{};
    final instancesAt = <int, int>{};
    void instance(String id, int index) {
      if (index > lastIndex) lastIndex = index;
      instanceIndex[id] = index;
      instancesAt[index] = (instancesAt[index] ?? 0) + 1;
      if (!ownInstanceIds.contains(id)) holdsUserRows = true;
    }

    for (final timed in await repository.getTimedInstances(effortId)) {
      instance(timed.id, timed.entryIndex);
    }
    for (final round in await repository.getRoundInstances(effortId)) {
      instance(round.id, round.roundIndex);
    }

    return _EffortRows._(
      holdsUserRows: holdsUserRows,
      lastIndex: lastIndex,
      sessionId: sessionId,
      byIndex: byIndex,
      indicesByStamp: indicesByStamp,
      stagedPerStamp: stagedPerStamp,
      instanceIndex: instanceIndex,
      instancesAt: instancesAt,
    );
  }

  /// Where [entry]'s rows are: the one position holding rows with its stamp,
  /// when no other staged entry of the effort shares that stamp. Null when it
  /// has none, or they cannot be told apart from another entry's.
  int? indexOf(_Entry entry) {
    if (_stagedPerStamp[entry.loggedAtMs] != 1) return null;
    final indices = _indicesByStamp[entry.loggedAtMs];
    return indices != null && indices.length == 1 ? indices.single : null;
  }

  /// [entry]'s own rows — found by [indexOf], and carrying its stamp.
  List<EffortObservation> ownRowsOf(_Entry entry) {
    final index = indexOf(entry);
    if (index == null) return const [];
    return [
      for (final row in _byIndex[index] ?? const <EffortObservation>[])
        if (row.createdAtMs == entry.loggedAtMs) row,
    ];
  }

  /// Where a pass that did not finish already put [entry], which is not yet
  /// placed — so placing it again rewrites its own rows instead of adding a
  /// second copy. Null when it was never put anywhere, or when the position
  /// holds anything that might not be its own.
  ///
  /// Its own instance, written first, says where; a set has none, so a
  /// position holding its stamp is taken only when every row there holds
  /// exactly what the entry would write, which rewriting cannot change.
  int? unfinishedPlaceOf(_Entry entry) {
    bool onlyStamped(int index) =>
        (_byIndex[index] ?? const <EffortObservation>[]).every(
          (row) => row.createdAtMs == entry.loggedAtMs,
        );

    final instanceAt = _ownInstanceIndex(entry);
    if (instanceAt != null) {
      return (_instancesAt[instanceAt] ?? 0) == 1 && onlyStamped(instanceAt)
          ? instanceAt
          : null;
    }
    final index = indexOf(entry);
    if (index == null || (_instancesAt[index] ?? 0) != 0) return null;
    final rows = _byIndex[index] ?? const <EffortObservation>[];
    return rows.every((row) => _holdsWhatItWrites(row, entry)) ? index : null;
  }

  static bool _holdsWhatItWrites(EffortObservation row, _Entry entry) {
    if (row.createdAtMs != entry.loggedAtMs) return false;
    return switch (row.metricId) {
      MetricIds.reps => row.valueInt == entry.reps,
      MetricIds.weight => row.valueReal == (entry.loadKg ?? 0.0),
      MetricIds.extraWeight => row.valueReal == 0.0,
      _ => false,
    };
  }

  int? _ownInstanceIndex(_Entry entry) =>
      _instanceIndex[WatchSessionImporter.timedInstanceIdFor(
        _sessionId,
        entry.entryId,
      )] ??
      _instanceIndex[WatchSessionImporter.roundInstanceIdFor(
        _sessionId,
        entry.entryId,
      )];
}

// -----------------------------------------------------------------------------
// What the staged rows say
// -----------------------------------------------------------------------------

/// An effort's identity (D-134): the slot, the exercise and the phone's kind.
class _Key {
  const _Key(this.sessionExerciseId, this.exerciseId, this.effortKind);

  final String sessionExerciseId;
  final String exerciseId;
  final String effortKind;

  String effortId(String sessionId) => WatchSessionImporter.effortIdFor(
    sessionId,
    sessionExerciseId,
    exerciseId,
    effortKind,
  );

  @override
  bool operator ==(Object other) =>
      other is _Key &&
      other.sessionExerciseId == sessionExerciseId &&
      other.exerciseId == exerciseId &&
      other.effortKind == effortKind;

  @override
  int get hashCode => Object.hash(sessionExerciseId, exerciseId, effortKind);
}

/// One wrist effort entry as history will hold it: the event as the wrist
/// sent it, with the phone's live corrections applied (D-137).
class _Entry {
  _Entry._({
    required this.row,
    required this.key,
    required this.loggedAtMs,
    required this.reps,
    required this.loadKg,
    required this.startedAtMs,
    required this.endedAtMs,
    required this.measuredStartMs,
    required this.measuredEndMs,
    required this.pausedMs,
    required this.distanceMeters,
    required this.distanceSource,
    required this.extraLoadKg,
    required this.avgHeartRateBpm,
    required this.maxHeartRateBpm,
    required this.steps,
    required this.correctedAtMs,
  });

  final WatchInboxEntry row;
  final _Key key;
  final int loggedAtMs;
  final int? reps;
  final double? loadKg;

  /// The entry's window, corrections applied.
  final int? startedAtMs;
  final int? endedAtMs;

  /// The window the wrist measured its summary over: the event's own.
  final int? measuredStartMs;
  final int? measuredEndMs;
  final int pausedMs;
  final double? distanceMeters;

  /// Where the distance came from, as the wrist sent it. Null when the event
  /// carried no source, or carried one that is not a known value.
  final String? distanceSource;
  final double? extraLoadKg;
  final double? avgHeartRateBpm;
  final double? maxHeartRateBpm;
  final int? steps;

  /// Wire field → the staging time of the latest correction that set it.
  final Map<String, int> correctedAtMs;

  String get entryId => row.entryId;
  String get wireKind => row.kind;

  bool get hasSummary =>
      measuredStartMs != null &&
      measuredEndMs != null &&
      (avgHeartRateBpm != null || maxHeartRateBpm != null || steps != null);

  bool get windowCorrected =>
      correctedAtMs.containsKey('startedAt') ||
      correctedAtMs.containsKey('endedAt');

  /// A row's `updatedAtMs`: the entry's `loggedAt`, or the latest correction
  /// of [field] staged after it.
  int stampFor(String field) {
    final corrected = correctedAtMs[field];
    return corrected == null || corrected < loggedAtMs ? loggedAtMs : corrected;
  }

  int get windowStampMs {
    final a = stampFor('startedAt');
    final b = stampFor('endedAt');
    return a > b ? a : b;
  }

  /// Seconds of active time in the window: the window, less any pause.
  int activeSecs() {
    final ms = endedAtMs! - startedAtMs! - pausedMs;
    return ms <= 0 ? 0 : (ms / Duration.millisecondsPerSecond).round();
  }

  static int compare(_Entry a, _Entry b) {
    final byTime = a.loggedAtMs.compareTo(b.loggedAtMs);
    return byTime != 0 ? byTime : a.entryId.compareTo(b.entryId);
  }

  /// The entry [row] describes, or null when the row cannot be read — which
  /// the inbox's staging filter makes rare, and which leaves the row to be
  /// consumed without history rather than stop the pass.
  static _Entry? parse(WatchInboxEntry row, List<WatchInboxEntry> corrections) {
    final payload = row.payload;
    final loggedAtMs = _ms(payload['loggedAt']);
    final slot = payload['sessionExerciseId'];
    final exerciseId = payload['exerciseId'];
    if (loggedAtMs == null ||
        slot is! String ||
        slot.isEmpty ||
        exerciseId is! String ||
        exerciseId.isEmpty) {
      return null;
    }

    final effective = Map<String, dynamic>.of(payload);
    final correctedAtMs = <String, int>{};
    for (final correction in corrections) {
      final change = correction.payload;
      if (change['entryId'] != row.entryId) continue;
      final values = change['correction'];
      if (values is! Map) continue;
      for (final field in const ['reps', 'loadKg', 'startedAt', 'endedAt']) {
        final value = values[field];
        final valid = switch (field) {
          'reps' => value is int && value >= 1,
          'loadKg' => value is num && value >= 0,
          _ => _ms(value) != null,
        };
        if (!valid) continue;
        effective[field] = value;
        final at = correctedAtMs[field];
        if (at == null || correction.receivedAtMs > at) {
          correctedAtMs[field] = correction.receivedAtMs;
        }
      }
    }

    final reps = effective['reps'];
    final startedAtMs = _ms(effective['startedAt']);
    final endedAtMs = _ms(effective['endedAt']);
    switch (row.kind) {
      case WatchInboxEntry.kindSet:
        if (reps is! int || reps < 1) return null;
      default:
        if (startedAtMs == null || endedAtMs == null) return null;
    }
    final pausedMs = payload['pausedMs'];

    return _Entry._(
      row: row,
      key: _Key(slot, exerciseId, WatchSessionImporter.effortKindFor(row.kind)),
      loggedAtMs: loggedAtMs,
      reps: reps is int ? reps : null,
      loadKg: _real(effective['loadKg']),
      startedAtMs: startedAtMs,
      endedAtMs: endedAtMs,
      measuredStartMs: _ms(payload['startedAt']),
      measuredEndMs: _ms(payload['endedAt']),
      pausedMs: pausedMs is int && pausedMs > 0 ? pausedMs : 0,
      distanceMeters: _real(payload['distanceMeters']),
      distanceSource: _knownDistanceSource(payload['distanceSource']),
      extraLoadKg: _real(payload['extraLoadKg']),
      avgHeartRateBpm: _real(payload['avgHeartRateBpm']),
      maxHeartRateBpm: _real(payload['maxHeartRateBpm']),
      steps: payload['steps'] is int ? payload['steps'] as int : null,
      correctedAtMs: correctedAtMs,
    );
  }
}

/// A set block's heart rate, as `session_end` carries it.
class _SetBlock {
  const _SetBlock({
    required this.sessionExerciseId,
    required this.exerciseId,
    required this.startedAtMs,
    required this.endedAtMs,
    required this.avgHeartRateBpm,
    required this.maxHeartRateBpm,
  });

  final String sessionExerciseId;
  final String exerciseId;
  final int startedAtMs;
  final int endedAtMs;
  final double? avgHeartRateBpm;
  final double? maxHeartRateBpm;
}

/// What the wrist's `session_end` says about the session.
class _End {
  const _End({
    required this.row,
    required this.loggedAtMs,
    required this.startedAtMs,
    required this.endedAtMs,
    required this.status,
    required this.modality,
    required this.avgHeartRateBpm,
    required this.maxHeartRateBpm,
    required this.setBlocks,
  });

  final WatchInboxEntry row;
  final int loggedAtMs;
  final int startedAtMs;
  final int endedAtMs;
  final String status;
  final String? modality;
  final double? avgHeartRateBpm;
  final double? maxHeartRateBpm;
  final List<_SetBlock> setBlocks;

  static _End? parse(WatchInboxEntry row) {
    final payload = row.payload;
    final loggedAtMs = _ms(payload['loggedAt']);
    final startedAtMs = _ms(payload['startedAt']);
    final endedAtMs = _ms(payload['endedAt']);
    final status = payload['status'];
    if (loggedAtMs == null ||
        startedAtMs == null ||
        endedAtMs == null ||
        status is! String) {
      return null;
    }
    final modality = payload['modality'];
    final blocks = payload['setBlockHeartRates'];
    return _End(
      row: row,
      loggedAtMs: loggedAtMs,
      startedAtMs: startedAtMs,
      endedAtMs: endedAtMs,
      status: status,
      modality: modality is String && modality.isNotEmpty ? modality : null,
      avgHeartRateBpm: _real(payload['avgHeartRateBpm']),
      maxHeartRateBpm: _real(payload['maxHeartRateBpm']),
      setBlocks: [
        if (blocks is List)
          for (final block in blocks)
            if (block is Map) ?_setBlock(block.cast<String, dynamic>()),
      ],
    );
  }

  static _SetBlock? _setBlock(Map<String, dynamic> block) {
    final slot = block['sessionExerciseId'];
    final exerciseId = block['exerciseId'];
    final startedAtMs = _ms(block['startedAt']);
    final endedAtMs = _ms(block['endedAt']);
    if (slot is! String ||
        exerciseId is! String ||
        startedAtMs == null ||
        endedAtMs == null) {
      return null;
    }
    return _SetBlock(
      sessionExerciseId: slot,
      exerciseId: exerciseId,
      startedAtMs: startedAtMs,
      endedAtMs: endedAtMs,
      avgHeartRateBpm: _real(block['avgHeartRateBpm']),
      maxHeartRateBpm: _real(block['maxHeartRateBpm']),
    );
  }
}

int? _ms(Object? iso) => iso is String
    ? DateTime.tryParse(iso)?.toUtc().millisecondsSinceEpoch
    : null;

double? _real(Object? value) =>
    value is num && value.isFinite ? value.toDouble() : null;

/// The wire's `distanceSource` when it names one of the sources a distance row
/// may carry, and null otherwise (D-334). An unknown value never reaches a
/// row, where it would be refused at construction (D-311).
String? _knownDistanceSource(Object? value) =>
    value is String && EffortObservation.valueSources.contains(value)
    ? value
    : null;
