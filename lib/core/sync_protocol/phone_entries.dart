/// The phone's own entries, as the protocol's `session_snapshot` carries them
/// down to the wrist.
///
/// One set the phone logged is one row group: its observations carry the group's
/// number in their ids (`obs-<effortId>-<n>-<metricKey>`, `EntryRows`) and were
/// written together, so they share a stamp. This file turns a slot's groups into
/// wire entries — minting the id (`entry-<sessionExerciseId>-<n>`, D-33), writing
/// the group's stamp as the protocol's UTC instant (D-36), and leaving out what
/// the wire cannot carry (D-60).
///
/// The other kinds the phone logs are its instances, not its groups (D-130): a
/// `timed` instance becomes a `timed` entry, the same record on a hold effort a
/// `hold` entry, and a `round` instance a `round` entry, each named by the
/// record's own index (D-131) and carrying the fields the wrist's own logger
/// writes for that kind (`watch/watchos/Sources/WatchSessionEngine/`
/// `WatchLoggingState.swift`). An instance the wire cannot express is omitted,
/// never placeheld (D-132).
///
/// The provenance rule lives here too (D-34/D-133): a group a live watch-inbox
/// row claims by stamp is the wrist's own and is **not** projected, and a
/// wrist-logged `timed`, `hold` or `round` entry claims the phone record the
/// importer wrote for it the same way. The wrist already holds it, and naming it
/// back under a phone id would double it. Every unclaimed entry is the phone's
/// own.
///
/// Nothing here touches a store: the repository reads that feed it live in
/// `WatchSessionAdoptionBridge.projectSession`.
///
/// Verified by `test/watch_session_projection_test.dart` (S-31, S-33, S-34,
/// S-36, S-37, S-39, S-40, S-43, S-59, S-60, S-140…S-143).
library;

import '../../data/models/models.dart';
import '../constants/metric_ids.dart';
import '../utils/entry_rows.dart';
import 'wire_limits.dart';
import 'wire_timestamps.dart';

abstract final class PhoneEntries {
  /// The wire kind of a phone set entry.
  static const String setKind = 'set';

  /// The wire kind of a phone timed entry, and of a hold's: an entry the wrist's
  /// own logger spells `timed` (`WatchLoggingState.metricPayload`,
  /// `watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift:587`).
  static const String timedKind = 'timed';

  /// The wire kind of an instance on an effort carrying the `hold` capability.
  static const String holdKind = 'hold';

  /// The wire kind of a phone round entry.
  static const String roundKind = 'round';

  /// [groups] as the wire entries of the slot [sessionExerciseId].
  ///
  /// [exerciseId] is the exercise the slot holds. [wristLoggedAtMs] is the
  /// `loggedAt` of every live watch-inbox row staged for that slot — the wrist's
  /// own entries this phone imported — read in ascending order. A row claims one
  /// group (the first unclaimed group stamped the same); a claimed group is the
  /// wrist's and is left out. The rest are the phone's own, in ascending entry
  /// number.
  static List<Map<String, Object?>> project({
    required String sessionExerciseId,
    required String exerciseId,
    required List<SetRows> groups,
    required List<int> wristLoggedAtMs,
  }) {
    final claimed = claimedBy(groups: groups, wristLoggedAtMs: wristLoggedAtMs);
    final entries = <Map<String, Object?>>[];
    for (final group in groups) {
      if (claimed.contains(group.number)) continue;
      final entry = _entry(
        sessionExerciseId: sessionExerciseId,
        exerciseId: exerciseId,
        group: group,
      );
      if (entry != null) entries.add(entry);
    }
    return entries;
  }

  /// A `timed` slot's instances as the wire entries of [sessionExerciseId]
  /// (D-130's `timed` row).
  ///
  /// One instance is one entry, named `entry-<sessionExerciseId>-<n>` with `n`
  /// the record's own `TimedInstance.entryIndex` (D-131) — 0-based, not a
  /// position: deleting an entry leaves the other ids alone — and its window is
  /// written the way the wrist's own logger writes one
  /// (`WatchLoggingState.windowPayload(coversDistance:)`,
  /// `watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift:628`):
  /// `startedAt`, `endedAt`, `loggedAt` = `endedAt`, plus the entry's distance
  /// when it recorded one above 0.
  ///
  /// [rows] are the effort's observations: the entry's distance is the one
  /// [EntryRows.distanceEntries] pairs with it, which is the entry's own place
  /// among the effort's instances. [wristLoggedAtMs] are the live watch-inbox
  /// stamps for that slot, in ascending order — the wrist's own timed entries,
  /// whose phone records are left out (D-133, S-142).
  ///
  /// An instance with no window to speak of — one that never started, or one
  /// whose end does not follow its start — carries no entry (D-132, S-143).
  static List<Map<String, Object?>> projectTimed({
    required String sessionExerciseId,
    required String exerciseId,
    required List<TimedInstance> instances,
    required List<EffortObservation> rows,
    required List<int> wristLoggedAtMs,
  }) {
    final claimed = resolveRecordClaims(
      createdAtMs: [for (final instance in instances) instance.createdAtMs],
      wristLoggedAtMs: wristLoggedAtMs,
    );
    final distances = EntryRows.distanceEntries(
      rows: rows,
      instanceCount: instances.length,
    );

    final entries = <Map<String, Object?>>[];
    for (var position = 0; position < instances.length; position++) {
      if (claimed.contains(position)) continue;
      final instance = instances[position];
      final entry = _windowedEntry(
        sessionExerciseId: sessionExerciseId,
        exerciseId: exerciseId,
        kind: timedKind,
        entryIndex: instance.entryIndex,
        startedAtMs: instance.startedAtMs,
        finishedAtMs: instance.finishedAtMs,
        extra: _distanceFields(distances[position]),
      );
      if (entry != null) entries.add(entry);
    }
    return entries;
  }

  /// A `round` slot's instances as the wire entries of [sessionExerciseId]
  /// (D-130's `round` row).
  ///
  /// A round entry carries its window like a timed one, its own number —
  /// `RoundInstance.roundIndex` + 1, the 1-based `roundNumber` the wire requires
  /// (D-131) — and the time it spent paused. A pause is written only when it is
  /// above 0 and no longer than the window itself (D-132): a round's window is
  /// what the wrist reads it against, and a pause past its end describes a
  /// record the phone does not have.
  ///
  /// [rows], [wristLoggedAtMs] and the omission rules read as in [projectTimed].
  static List<Map<String, Object?>> projectRound({
    required String sessionExerciseId,
    required String exerciseId,
    required List<RoundInstance> instances,
    required List<EffortObservation> rows,
    required List<int> wristLoggedAtMs,
  }) {
    final claimed = resolveRecordClaims(
      createdAtMs: [for (final instance in instances) instance.createdAtMs],
      wristLoggedAtMs: wristLoggedAtMs,
    );
    final distances = EntryRows.distanceEntries(
      rows: rows,
      instanceCount: instances.length,
    );

    final entries = <Map<String, Object?>>[];
    for (var position = 0; position < instances.length; position++) {
      if (claimed.contains(position)) continue;
      final instance = instances[position];
      final roundNumber = instance.roundIndex + 1;
      if (roundNumber < 1) continue;
      final pausedMs = instance.totalPausedDurationMs;
      final window = _window(instance.startedAtMs, instance.finishedAtMs);
      final entry = _windowedEntry(
        sessionExerciseId: sessionExerciseId,
        exerciseId: exerciseId,
        kind: roundKind,
        entryIndex: instance.roundIndex,
        startedAtMs: instance.startedAtMs,
        finishedAtMs: instance.finishedAtMs,
        extra: <String, Object?>{
          'roundNumber': roundNumber,
          if (window != null &&
              pausedMs > 0 &&
              pausedMs <= window.$2 - window.$1)
            'pausedMs': pausedMs,
          ..._distanceFields(distances[position]),
        },
      );
      if (entry != null) entries.add(entry);
    }
    return entries;
  }

  /// An instance on a hold effort as the wire entry of [sessionExerciseId]
  /// (D-130's hold row).
  ///
  /// The same record a [projectTimed] carries is a `hold` on the wire when the
  /// effort carries the `hold` capability, with the weight it was held with
  /// added: the wire's `extraLoadKg`, the field the wrist's own logger writes
  /// for a hold (`WatchLoggingState.metricPayload`'s `extraLoadKg`,
  /// `watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift:587`).
  /// A hold's window does **not** cover distance there and carries none here.
  ///
  /// [rows] are the effort's observations: the hold's added weight is the one
  /// `EntryRows.companions` pairs with the entry, sent only when it is not
  /// exactly 0 (D-132) and with its own sign otherwise. [wristLoggedAtMs] reads
  /// as in [projectTimed].
  static List<Map<String, Object?>> projectHold({
    required String sessionExerciseId,
    required String exerciseId,
    required List<TimedInstance> instances,
    required List<EffortObservation> rows,
    required List<int> wristLoggedAtMs,
  }) {
    final claimed = resolveRecordClaims(
      createdAtMs: [for (final instance in instances) instance.createdAtMs],
      wristLoggedAtMs: wristLoggedAtMs,
    );
    final extraLoads = EntryRows.companions(
      rows: rows,
      metricId: MetricIds.extraWeight,
      entryCount: instances.length,
    );

    final entries = <Map<String, Object?>>[];
    for (var position = 0; position < instances.length; position++) {
      if (claimed.contains(position)) continue;
      final instance = instances[position];
      final entry = _windowedEntry(
        sessionExerciseId: sessionExerciseId,
        exerciseId: exerciseId,
        kind: holdKind,
        entryIndex: instance.entryIndex,
        startedAtMs: instance.startedAtMs,
        finishedAtMs: instance.finishedAtMs,
        extra: _extraLoadFields(extraLoads[position]),
      );
      if (entry != null) entries.add(entry);
    }
    return entries;
  }

  /// The entry numbers [wristLoggedAtMs] claim (D-34): [resolveClaims]'s
  /// `.groups`, so the projection and every caller that asks about a row read
  /// the claim rule once.
  static Set<int> claimedBy({
    required List<SetRows> groups,
    required List<int> wristLoggedAtMs,
  }) => resolveClaims(groups: groups, wristLoggedAtMs: wristLoggedAtMs).groups;

  /// What [wristLoggedAtMs] claims, in one pass: the group numbers claimed
  /// (`.groups`) and the **indexes** into [wristLoggedAtMs] that claimed one
  /// (`.stamps`).
  ///
  /// Each stamp claims **one** group: the first unclaimed group it matches, in
  /// ascending number. One row, one group — which is what makes a wrist entry
  /// and a phone entry written in the same millisecond a benign
  /// under-projection (the later group is left unclaimed and is projected)
  /// rather than a lost one.
  ///
  /// The indexes are what lets a caller holding one row per stamp map a claim
  /// back to the row it came from. Asking about one stamp at a time is **not**
  /// the same question: two rows sharing a stamp claim one group each, so
  /// row-by-row both read as claiming while one pass over both sees the second
  /// group gone. Callers that report which rows the wrist holds must pass every
  /// stamp of the slot, or they disagree with the projection (F4).
  static ({Set<int> groups, Set<int> stamps}) resolveClaims({
    required List<SetRows> groups,
    required List<int> wristLoggedAtMs,
  }) {
    final claimed = <int>{};
    final claiming = <int>{};
    for (var index = 0; index < wristLoggedAtMs.length; index++) {
      final stamp = wristLoggedAtMs[index];
      for (final group in groups) {
        if (claimed.contains(group.number)) continue;
        if (stampOf(group) != stamp) continue;
        claimed.add(group.number);
        claiming.add(index);
        break;
      }
    }
    return (groups: claimed, stamps: claiming);
  }

  /// The indexes into [createdAtMs] that [wristLoggedAtMs] claim (D-133).
  ///
  /// The non-set twin of [resolveClaims], over records rather than groups: one
  /// stamp claims **one** record — the first unclaimed one it matches, in the
  /// order the caller lists them — because a wrist entry produces at most one
  /// phone record. [createdAtMs] is the stamp of each record the phone holds for
  /// the slot, in the order the store lists it: a `TimedInstance`'s
  /// `createdAtMs`, which the importer wrote from the row's `loggedAt`
  /// (`watch_session_importer.dart:926`), or a `RoundInstance`'s, written the
  /// same way (`:970`).
  ///
  /// The indexes are positions in [createdAtMs], which is what lets a caller
  /// holding one list of records map a claim back to the record it came from.
  /// Two entries written in the same millisecond therefore leave the later
  /// record unclaimed and projected rather than lost — the benign
  /// under-projection [resolveClaims] documents, in the other direction.
  static Set<int> resolveRecordClaims({
    required List<int> createdAtMs,
    required List<int> wristLoggedAtMs,
  }) {
    final claimed = <int>{};
    for (final stamp in wristLoggedAtMs) {
      for (var index = 0; index < createdAtMs.length; index++) {
        if (claimed.contains(index)) continue;
        if (createdAtMs[index] != stamp) continue;
        claimed.add(index);
        break;
      }
    }
    return claimed;
  }

  /// The stamp a group carries: the earliest `createdAtMs` among its rows.
  ///
  /// An entry's rows are written together and share one stamp, so the earliest
  /// reads the same whichever store returned them in whichever order.
  static int stampOf(SetRows group) {
    var earliest = group.rows.first.createdAtMs;
    for (final row in group.rows) {
      if (row.createdAtMs < earliest) earliest = row.createdAtMs;
    }
    return earliest;
  }

  /// [entries] in the order the protocol reads them: by `loggedAt`, then by
  /// `entryId` — the wrist's own order (`WatchSessionEngine`'s
  /// `_byLoggedAtThenEntryId`), so a phone entry sits where the phone shows it.
  static List<Map<String, Object?>> ordered(
    Iterable<Map<String, Object?>> entries,
  ) {
    final listed = entries.toList()
      ..sort((a, b) {
        final byStamp = parseUtcIso(
          a['loggedAt'],
        ).compareTo(parseUtcIso(b['loggedAt']));
        if (byStamp != 0) return byStamp;
        return (a['entryId']! as String).compareTo(b['entryId']! as String);
      });
    return listed;
  }

  /// One instance as the wire spells a non-set entry (D-130), or null when the
  /// wire cannot carry it (D-132): an instance that never started or whose end
  /// does not follow its start has no window, and no window is no entry.
  ///
  /// [extra] is the kind's own extra fields — a round's number, a hold's added
  /// weight, an entry's distance — and is written only for an entry that is
  /// carried at all.
  static Map<String, Object?>? _windowedEntry({
    required String sessionExerciseId,
    required String exerciseId,
    required String kind,
    required int entryIndex,
    required int startedAtMs,
    required int? finishedAtMs,
    required Map<String, Object?> extra,
  }) {
    final window = _window(startedAtMs, finishedAtMs);
    if (window == null) return null;

    final entryId = 'entry-$sessionExerciseId-$entryIndex';
    return <String, Object?>{
      'entryId': entryId,
      'eventId': entryId,
      'kind': kind,
      'loggedAt': _instant(window.$2),
      'sessionExerciseId': sessionExerciseId,
      'exerciseId': exerciseId,
      'startedAt': _instant(window.$1),
      'endedAt': _instant(window.$2),
      ...extra,
    };
  }

  /// The window an instance is carried with, or null when it has none to carry
  /// (D-132): a record that never started (`startedAtMs` 0) and one whose end
  /// does not follow its start — a window of no length is no window.
  static (int, int)? _window(int startedAtMs, int? finishedAtMs) {
    if (startedAtMs <= 0 || finishedAtMs == null) return null;
    if (finishedAtMs <= startedAtMs) return null;
    return (startedAtMs, finishedAtMs);
  }

  /// A distance entry's fields, or none when it recorded no distance: a distance
  /// of 0 is omitted, never sent as 0 (D-132).
  ///
  /// `distanceSource` travels only with the metres it describes, which is also
  /// the only shape a receiver accepts (`message_validator.dart`'s capture and
  /// source rules): a source of the wire's own vocabulary is carried, and a row
  /// that names none is carried as metres alone — the way the wrist's own logger
  /// writes a window's distance.
  static Map<String, Object?> _distanceFields(DistanceEntry? entry) {
    final row = entry?.row;
    final metres = row?.valueReal ?? 0.0;
    if (metres <= 0) return const {};

    final fields = <String, Object?>{'distanceMeters': metres};
    final source = row?.valueSource;
    if (source != null && EffortObservation.valueSources.contains(source)) {
      fields['distanceSource'] = source;
    }
    return fields;
  }

  /// A hold's added weight as the wire spells it, or none when it is exactly 0
  /// (D-132). A weight that is not 0 is carried with its own sign.
  static Map<String, Object?> _extraLoadFields(EffortObservation? row) {
    final weightKg = row?.valueReal ?? 0.0;
    if (weightKg == 0) return const {};
    return <String, Object?>{'extraLoadKg': weightKg};
  }

  /// One group as the wire spells an entry, or null when the wire cannot carry
  /// it (D-60). The omissions are exactly two: `reps` has a minimum of 1 and the
  /// phone writes a skipped set as reps 0, and `loadKg` has a minimum of
  /// [WireLimits.minLoadKg] — a band-assisted set is stored negative and is
  /// carried with its sign, while a weight below the floor is left out. A
  /// rejected entry rejects the **whole** snapshot, so an entry that cannot be
  /// rendered is omitted, never placeheld (S-59, S-60).
  ///
  /// A weight of zero (or no weight at all) is carried without a `loadKg` key:
  /// the wire keeps "no load" and "load 0" indistinguishable, as it always has.
  /// A set's added weight is not sent either: the wire's extra load is a hold's.
  static Map<String, Object?>? _entry({
    required String sessionExerciseId,
    required String exerciseId,
    required SetRows group,
  }) {
    final set = group.entry;
    final reps = (set['reps'] as int?) ?? 0;
    if (reps < 1) return null;

    final weightKg = (set['weight'] as double?) ?? 0.0;
    if (weightKg < WireLimits.minLoadKg) return null;

    final entryId = 'entry-$sessionExerciseId-${group.number}';
    final entry = <String, Object?>{
      'entryId': entryId,
      'eventId': entryId,
      'kind': setKind,
      'loggedAt': _instant(stampOf(group)),
      'sessionExerciseId': sessionExerciseId,
      'exerciseId': exerciseId,
      'reps': reps,
    };
    if (weightKg != 0) entry['loadKg'] = weightKg;
    return entry;
  }

  /// An epoch instant as the protocol's UTC instant.
  static String _instant(int epochMs) =>
      utcIso(DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true));
}
