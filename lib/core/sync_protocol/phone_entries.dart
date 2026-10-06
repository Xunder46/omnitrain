/// The phone's own set entries, as the protocol's `session_snapshot` carries
/// them down to the wrist.
///
/// One set the phone logged is one row group: its observations carry the group's
/// number in their ids (`obs-<effortId>-<n>-<metricKey>`, `EntryRows`) and were
/// written together, so they share a stamp. This file turns a slot's groups into
/// wire entries — minting the id (`entry-<sessionExerciseId>-<n>`, D-33), writing
/// the group's stamp as the protocol's UTC instant (D-36), and leaving out what
/// the wire cannot carry (D-60).
///
/// The provenance rule lives here too (D-34): a group a live watch-inbox row
/// claims by stamp is the wrist's own and is **not** projected. The wrist
/// already holds it, and naming it back under a phone id would double it. Every
/// unclaimed group is the phone's own.
///
/// Nothing here touches a store: the repository reads that feed it live in
/// `WatchSessionAdoptionBridge.projectSession`.
///
/// Verified by `test/watch_session_projection_test.dart` (S-31, S-33, S-34,
/// S-36, S-37, S-39, S-40, S-43, S-59, S-60).
library;

import '../utils/entry_rows.dart';
import 'wire_limits.dart';
import 'wire_timestamps.dart';

abstract final class PhoneEntries {
  /// The kind every projected entry carries. Only a set has a wire shape yet
  /// (D-39): a timed, hold or round entry still needs its window, distance and
  /// round fields mapped from its instance row.
  static const String setKind = 'set';

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

  /// The entry numbers [wristLoggedAtMs] claim (D-34).
  ///
  /// Each stamp claims **one** group: the first unclaimed group it matches, in
  /// ascending number. One row, one group — which is what makes a wrist entry
  /// and a phone entry written in the same millisecond a benign
  /// under-projection (the later group is left unclaimed and is projected)
  /// rather than a lost one.
  static Set<int> claimedBy({
    required List<SetRows> groups,
    required List<int> wristLoggedAtMs,
  }) {
    final claimed = <int>{};
    for (final stamp in wristLoggedAtMs) {
      for (final group in groups) {
        if (claimed.contains(group.number)) continue;
        if (stampOf(group) != stamp) continue;
        claimed.add(group.number);
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
      'loggedAt': utcIso(
        DateTime.fromMillisecondsSinceEpoch(stampOf(group), isUtc: true),
      ),
      'sessionExerciseId': sessionExerciseId,
      'exerciseId': exerciseId,
      'reps': reps,
    };
    if (weightKg != 0) entry['loadKg'] = weightKg;
    return entry;
  }
}
