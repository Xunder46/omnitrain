/// The day's glasses of water on the Wear wrist: the phone's count as the newest
/// `water_down` brought it, plus the wrist's own taps the phone has not counted
/// yet.
///
/// Plan: `docs/plans/2026-11-22-290-wear-water-count-plan/2026-11-22-290-wear-water-count-plan.md`
/// (D-29003..D-29006). The Dart twin of the Apple client's `WatchWater.swift`
/// (series 94-96).
///
/// The phone owns the day's water. The wrist sends taps, never a total, and
/// stores no count: the number it shows is computed on every read from the held
/// frame and the stored taps, so a relaunch, a receipt or a local midnight never
/// leaves a stale number behind.
library;

import 'dart:math' as math;

import '../../core/sync_protocol/message_validator.dart';
import '../session/watch_records.dart';
import '../session/watch_session_engine.dart';
import '../session/watch_session_store.dart';

/// The wrist's limits on water taps.
abstract final class WatchWaterLimits {
  /// How many taps the wrist stores per local day. Equal to
  /// `appliedTapIds.maxItems` in `water_down.schema.json` and to the phone's
  /// `kWatchWaterTapsPerDay`: the phone lists at most that many taps for a day,
  /// so a wrist that never taps past it has every receipted tap listed.
  static const int tapsPerDay = 500;

  /// How long a tap the phone confirmed is kept; a launch drops the older ones
  /// (plan 302 D-30203, the Apple wrist's plan 96 D-43). The count reads only
  /// taps of local today, and a local day in any zone lasts at most 25 hours,
  /// so a tap older than that is unreadable by every count; the retention adds
  /// more than a day of margin (it must be at least 49 hours) so a launch clock
  /// that runs fast cannot drop a tap a count can read.
  static const Duration confirmedTapRetention = Duration(hours: 72);
}

/// What a screen reader says about the water bar, worded after the phone's own
/// tooltips.
abstract final class WatchWaterCopy {
  static const String addLabel = 'Add one glass';
  static const String removeLabel = 'Remove one glass';

  /// The middle of the bar, the drop and the number, is one element.
  static const String countLabel = 'Water';

  /// The count as spoken: "1 glass", otherwise "N glasses".
  static String spokenCount(int glasses) =>
      glasses == 1 ? '1 glass' : '$glasses glasses';
}

/// One read of the water count: the glasses, both buttons' rules and the count
/// as spoken, all from the same instant and the same taps.
class WatchWaterSnapshot {
  const WatchWaterSnapshot({
    required this.glasses,
    required this.canAdd,
    required this.canRemove,
    required this.spokenCount,
  });

  final int glasses;
  final bool canAdd;
  final bool canRemove;
  final String spokenCount;
}

typedef _Frame = ({
  DateTime generatedAt,
  String day,
  int glasses,
  List<String> appliedTapIds,
});

typedef _Tap = ({
  String id,
  String change,
  DateTime loggedAt,
  int sequence,
  int position,
});

class WatchWaterState {
  WatchWaterState({
    required WatchSessionEngine engine,
    required WatchSessionStore store,
    SyncProtocolValidator? validator,
    DateTime Function()? clock,
  }) : _engine = engine,
       _store = store,
       _validator = validator,
       _clock = clock ?? (() => DateTime.now().toUtc());

  final WatchSessionEngine _engine;
  final WatchSessionStore _store;
  final SyncProtocolValidator? _validator;
  final DateTime Function() _clock;

  /// The newest frame, or null before the first one. Its `generatedAt` can run
  /// ahead of the stored row's: a repeat of the held content advances it in
  /// memory without writing.
  _Frame? _held;

  /// The work in flight: frame applies and presses run one at a time, so two
  /// frames cannot both pass the "newer" check and two presses cannot both pass
  /// the cap.
  Future<void> _gate = Future<void>.value();

  /// Fires after [restore], after an applied frame and after a stored tap; never
  /// for a refused, dropped or unchanged frame, nor a press that stored nothing.
  void Function()? onWaterChanged;

  Future<T> _exclusive<T>(Future<T> Function() body) {
    final result = _gate.then((_) => body());
    _gate = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  // ---------------------------------------------------------------------------
  // The frame
  // ---------------------------------------------------------------------------

  /// Reads the held frame back out of storage: the row with the greatest
  /// (`generatedAt`, `sequence`). Call on launch, after the engine's own restore
  /// (the count folds the engine's stored taps).
  /// It first drops the confirmed taps older than [WatchWaterLimits.confirmedTapRetention] (plan 302); that prune runs here only, once per launch.
  Future<void> restore() async {
    await _exclusive(() async {
      await _engine.pruneWaterTaps(
        loggedBefore: _clock().subtract(WatchWaterLimits.confirmedTapRetention),
      );
      final contents = await _store.readAll();
      WatchWaterRecord? newest;
      for (final row in contents.water) {
        if (newest == null) {
          newest = row;
          continue;
        }
        final byTime = row.generatedAt.compareTo(newest.generatedAt);
        if (byTime > 0 || (byTime == 0 && row.sequence > newest.sequence)) {
          newest = row;
        }
      }
      _held = newest == null
          ? null
          : (
              generatedAt: newest.generatedAt,
              day: newest.day,
              glasses: newest.glasses,
              appliedTapIds: newest.appliedTapIds,
            );
    });
    onWaterChanged?.call();
  }

  /// Applies a `water_down` message; true when the frame it stored is now the
  /// one that decides.
  ///
  /// In order: a message the validator refuses stores nothing; a message the
  /// wrist cannot read stores nothing; a frame older than the held one is
  /// dropped; a frame carrying the held content again writes nothing and only
  /// moves the held `generatedAt` forward. Anything else is stored (a tie in
  /// `generatedAt` with different content included, so the later received
  /// decides), held, and every other frame row is pruned away.
  Future<bool> applyWaterDown(Map<String, Object?> envelope) async {
    final decision = SyncProtocolValidator.evaluateOrAccept(
      _validator,
      envelope,
    );
    if (!decision.accepted) return false;
    if (envelope['type'] != 'water_down') return false;

    final messageId = envelope['messageId'];
    final payload = envelope['payload'];
    if (messageId is! String || payload is! Map) return false;

    final generatedAt = _instant(payload['generatedAt']);
    final day = payload['day'];
    final glasses = payload['glasses'];
    final tapIds = payload['appliedTapIds'];
    if (generatedAt == null ||
        day is! String ||
        glasses is! int ||
        glasses < 0 ||
        tapIds is! List) {
      return false;
    }
    final appliedTapIds = <String>[];
    for (final id in tapIds) {
      if (id is! String) return false;
      appliedTapIds.add(id);
    }

    final applied = await _exclusive(() async {
      final current = _held;
      if (current != null) {
        if (generatedAt.isBefore(current.generatedAt)) return false;
        if (current.day == day &&
            current.glasses == glasses &&
            _sameIds(current.appliedTapIds, appliedTapIds)) {
          _held = (
            generatedAt: generatedAt,
            day: current.day,
            glasses: current.glasses,
            appliedTapIds: current.appliedTapIds,
          );
          return false;
        }
      }

      final stored = await _store.append(
        WatchWaterRecord(
          recordId: 'water-$messageId',
          recordedAt: _clock(),
          generatedAt: generatedAt,
          day: day,
          glasses: glasses,
          appliedTapIds: appliedTapIds,
        ),
      );
      _held = (
        generatedAt: generatedAt,
        day: day,
        glasses: glasses,
        appliedTapIds: appliedTapIds,
      );
      await _store.pruneWater(keepingRecordId: stored.recordId);
      return true;
    });

    if (applied) onWaterChanged?.call();
    return applied;
  }

  // ---------------------------------------------------------------------------
  // The count
  // ---------------------------------------------------------------------------

  /// The count and both buttons' rules, from one clock read and one read of the
  /// stored taps. Computed on every read, never cached: a cache would need to
  /// hear of every receipt, minute and zone change.
  ///
  /// The glasses shown are the held frame's count when its day is the wrist's
  /// local today, else 0; then the wrist's taps of local today that the frame
  /// does not list, confirmed or not (only the frame's list takes a tap out),
  /// folded in `loggedAt` order, ties by store order: add +1, remove -1 but
  /// never below 0.
  WatchWaterSnapshot get snapshot {
    final now = _clock().toLocal();
    final frame = _held;
    final taps = _todaysTaps(now);
    final listed = <String>{...?frame?.appliedTapIds};
    var count = frame != null && frame.day == _localDay(now)
        ? frame.glasses
        : 0;
    for (final tap in taps) {
      if (listed.contains(tap.id)) continue;
      count = tap.change == WatchGlassChange.add
          ? count + 1
          : math.max(0, count - 1);
    }
    final canAdd = taps.length < WatchWaterLimits.tapsPerDay;
    return WatchWaterSnapshot(
      glasses: count,
      canAdd: canAdd,
      canRemove: canAdd && count > 0,
      spokenCount: WatchWaterCopy.spokenCount(count),
    );
  }

  // ---------------------------------------------------------------------------
  // The presses
  // ---------------------------------------------------------------------------

  /// One press of plus or minus: stores one tap, logged at this state's clock,
  /// and returns whether it did. A press whose button's rule is false (or whose
  /// [change] is not a [WatchGlassChange]) stores nothing, emits nothing and
  /// returns false; so does a press whose write fails.
  Future<bool> press(String change) async {
    final stored = await _exclusive(() async {
      final current = snapshot;
      final allowed = switch (change) {
        WatchGlassChange.add => current.canAdd,
        WatchGlassChange.remove => current.canRemove,
        _ => false,
      };
      if (!allowed) return false;
      try {
        final tap = await _engine.logWaterGlass(change, loggedAt: _clock());
        return _engine.waterLog.any((row) => row.recordId == tap.recordId);
      } on Object {
        return false;
      }
    });
    if (stored) onWaterChanged?.call();
    return stored;
  }

  // ---------------------------------------------------------------------------
  // Days and taps
  // ---------------------------------------------------------------------------

  /// The wrist's own taps whose `loggedAt` falls on the local day of [now], in
  /// fold order: `loggedAt`, then store sequence, then store position. Only a tap
  /// stored under a session id local today can carry is parsed; the rest of the
  /// history is skipped unread.
  List<_Tap> _todaysTaps(DateTime now) {
    final candidates = _sessionIds(now);
    final taps = <_Tap>[];
    var position = 0;
    for (final record in _engine.waterLog) {
      final at = position++;
      if (!candidates.contains(record.sessionId)) continue;
      final change = record.payload['glassChange'];
      final loggedAt = _instant(record.payload['loggedAt']);
      if (change is! String ||
          !WatchGlassChange.all.contains(change) ||
          loggedAt == null) {
        continue;
      }
      final local = loggedAt.toLocal();
      if (local.year != now.year ||
          local.month != now.month ||
          local.day != now.day) {
        continue;
      }
      final id = record.payload['entryId'];
      taps.add((
        id: id is String ? id : record.recordId,
        change: change,
        loggedAt: loggedAt,
        sequence: record.sequence,
        position: at,
      ));
    }
    taps.sort((a, b) {
      final byTime = a.loggedAt.compareTo(b.loggedAt);
      if (byTime != 0) return byTime;
      final bySequence = a.sequence.compareTo(b.sequence);
      return bySequence != 0 ? bySequence : a.position.compareTo(b.position);
    });
    return taps;
  }

  /// The session ids a tap of local today can be stored under: a tap is stored
  /// under `WatchNutritionSession.idFor(loggedAt)`, its UTC date, so these are
  /// the UTC dates the local day touches (at most three: a local day lasts at
  /// most 25 hours).
  Set<String> _sessionIds(DateTime now) {
    final start = DateTime(now.year, now.month, now.day).toUtc();
    final end = DateTime(now.year, now.month, now.day + 1).toUtc();
    final ids = <String>{};
    var instant = start;
    while (instant.isBefore(end)) {
      ids.add(WatchNutritionSession.idFor(instant));
      instant = DateTime.utc(instant.year, instant.month, instant.day + 1);
    }
    return ids;
  }

  /// The zero-padded `YYYY-MM-DD` of [instant] (already local): the form a
  /// frame's `day` is written in.
  static String _localDay(DateTime instant) {
    final month = instant.month.toString().padLeft(2, '0');
    final day = instant.day.toString().padLeft(2, '0');
    return '${instant.year.toString().padLeft(4, '0')}-$month-$day';
  }

  static bool _sameIds(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// A UTC instant from the wire, or null when it is not one.
  static DateTime? _instant(Object? value) {
    if (value is! String) return null;
    try {
      return parseUtcIso(value);
    } on FormatException {
      return null;
    }
  }
}
