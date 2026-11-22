/// The phone's standing bests on the Wear wrist, and the verdict a set logged on
/// the wrist gets against them.
///
/// Plan: `docs/plans/2026-11-22-288-wear-personal-bests-plan/2026-11-22-288-wear-personal-bests-plan.md`
/// (D-28803..D-28807). The Dart twin of the Apple client's
/// `WatchPersonalBests.swift`: the phone's frame (the newest `generatedAt`
/// winning, a tie going to the copy received later) and the wrist's own best
/// (the best of the sets the wrist holds, which the frame may not carry yet)
/// are compared and only their larger matters. A wrist that never received a
/// frame gives no verdict at all, so its very first sets are silent rather than
/// celebrated. Nothing here reads history per log: a verdict is two map lookups
/// and one multiplication.
library;

import 'dart:math' as math;

import '../../core/sync_protocol/message_validator.dart';
import '../session/watch_records.dart';
import '../session/watch_session_store.dart';

typedef _Frame = Map<String, ({double e1rmKg, int repsBest})>;
typedef _Own = Map<String, ({double e1rm, int reps})>;

class WatchPersonalBests {
  WatchPersonalBests({
    required WatchSessionStore store,
    SyncProtocolValidator? validator,
    DateTime Function()? clock,
  }) : _store = store,
       _validator = validator,
       _clock = clock ?? (() => DateTime.now().toUtc());

  final WatchSessionStore _store;
  final SyncProtocolValidator? _validator;
  final DateTime Function() _clock;

  /// The most reps of one set the estimate counts: the phone's
  /// `StatsProgressService.kEpleyMaxReps` (plan 157b D-2).
  static const int epleyMaxReps = 12;

  /// The frame the wrist holds, parsed once when it arrived, or null when no
  /// frame ever did. A held `bests: []` frame is an empty map, not null: then
  /// every first set of an exercise is a record.
  _Frame? _frame;

  /// The held frame's own `generatedAt`, not the row's `recordedAt`: an older
  /// copy that arrives late is dropped.
  DateTime? _frameGeneratedAt;

  /// The wrist's own best per exercise, per axis: the sets it holds. One entry
  /// per exercise, never a per-set list.
  final _Own _own = {};

  /// The apply in flight, so the next one starts when it ends.
  Future<void> _applying = Future<void>.value();

  /// Whether a frame is held at all. Without one there is no verdict.
  bool get hasFrame => _frame != null;

  /// Reads the newest frame back out of storage and rebuilds the own bests from
  /// the observations still there, confirmed or not and phone-sourced included:
  /// a wrist log must not celebrate below a set the wrist already holds, and a
  /// relaunch is exactly when the frame may lag behind what the wrist has.
  Future<void> restore() async {
    final contents = await _store.readAll();
    WatchBestsRecord? newest;
    for (final row in contents.bests) {
      if (newest == null) {
        newest = row;
        continue;
      }
      final byTime = row.generatedAt.compareTo(newest.generatedAt);
      if (byTime > 0 || (byTime == 0 && row.sequence > newest.sequence)) {
        newest = row;
      }
    }
    final parsed = newest == null ? null : _parse(newest.entries);
    _frame = parsed;
    _frameGeneratedAt = parsed == null ? null : newest!.generatedAt;
    _own
      ..clear()
      ..addAll(_rebuildOwn(contents.observations));
  }

  /// Applies a `bests_down` message; true when the frame it stored is now the
  /// one that decides.
  ///
  /// A message the wrist cannot read is refused whole with nothing stored and
  /// the previous frame still deciding. A frame older than the held one is
  /// understood and dropped. A frame carrying the numbers the wrist already
  /// holds writes nothing. Anything else is stored (a frame stamped the same
  /// moment as the held one included, so the later-received of the two
  /// decides), and every other frame is pruned away.
  Future<bool> applyBestsDown(Map<String, Object?> envelope) {
    // One frame at a time: the transport hands each arrival over as it comes,
    // and two applies interleaving at their awaits could prune the newer
    // frame's row away while the older one decides in memory.
    final result = _applying.then((_) => _apply(envelope));
    _applying = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  Future<bool> _apply(Map<String, Object?> envelope) async {
    final decision = SyncProtocolValidator.evaluateOrAccept(
      _validator,
      envelope,
    );
    if (!decision.accepted) return false;
    if (envelope['type'] != 'bests_down') return false;

    final messageId = envelope['messageId'];
    final payload = envelope['payload'];
    if (messageId is! String || payload is! Map) return false;

    final generatedAt = _instant(payload['generatedAt']);
    final raw = payload['bests'];
    if (generatedAt == null || raw is! List) return false;

    final entries = <Map<String, Object?>>[];
    for (final item in raw) {
      if (item is! Map) return false;
      entries.add(Map<String, Object?>.from(item));
    }
    final parsed = _parse(entries);
    if (parsed == null) return false;

    final held = _frameGeneratedAt;
    if (held != null && generatedAt.isBefore(held)) return false;
    final frame = _frame;
    if (frame != null && _sameFrame(frame, parsed)) return false;

    final stored = await _store.append(
      WatchBestsRecord(
        recordId: 'bests-$messageId',
        recordedAt: _clock(),
        generatedAt: generatedAt,
        entries: entries,
      ),
    );

    _frame = parsed;
    _frameGeneratedAt = generatedAt;
    await _store.pruneBests(keepingRecordId: stored.recordId);
    return true;
  }

  /// Whether the set the wrist just logged beat the best it knows, and the fold
  /// of that set into the own bests.
  ///
  /// Only an effort of kind `set` with reps >= 1 is a claim; anything else
  /// returns false and changes nothing. A set with a load above zero is
  /// measured on the weight axis, `loadKg * (1 + min(reps, 12) / 30.0)` in the
  /// phone's own operation order so an equal set compares equal bit for bit; a
  /// set without one, or with a negative one (the band assist), is measured on
  /// the reps axis, exactly as the phone's toast does.
  ///
  /// The verdict is read before the fold, and the set is folded in either way:
  /// the own best is what stops the same set celebrating twice, whether or not
  /// a frame is held and whether or not this set was a record. Only a held
  /// frame grants a verdict at all.
  bool noteLogged({
    required String kind,
    required String exerciseId,
    required int reps,
    double? loadKg,
  }) {
    if (kind != WatchObservationKind.set || exerciseId.isEmpty || reps < 1) {
      return false;
    }
    final record = _beatsStandingBest(exerciseId, reps, loadKg);
    _fold(exerciseId, reps, loadKg, _own);
    return record;
  }

  /// The verdict against `max(held frame's best, own best)`, strict `>` per
  /// axis, a missing axis counting as zero. Called before the set is folded in.
  bool _beatsStandingBest(String exerciseId, int reps, double? loadKg) {
    final frame = _frame;
    if (frame == null) return false;
    final held = frame[exerciseId];
    final mine = _own[exerciseId];

    if (loadKg != null && loadKg > 0) {
      final estimate = _estimateOneRepMax(loadKg, reps);
      final best = math.max(held?.e1rmKg ?? 0, mine?.e1rm ?? 0);
      return estimate > best;
    }

    final best = math.max(held?.repsBest ?? 0, mine?.reps ?? 0);
    return reps > best;
  }

  /// Epley, in the phone's operation order (`StatsProgressService.epley1RM`).
  static double _estimateOneRepMax(double loadKg, int reps) =>
      loadKg * (1 + math.min(reps, epleyMaxReps) / 30.0);

  /// Folds one logged set into [own], on the axis its verdict used: a loaded
  /// set updates the weight axis, everything else the reps axis. It never lowers
  /// a standing best.
  static void _fold(String exerciseId, int reps, double? loadKg, _Own own) {
    final standing = own[exerciseId] ?? (e1rm: 0.0, reps: 0);
    if (loadKg != null && loadKg > 0) {
      own[exerciseId] = (
        e1rm: math.max(standing.e1rm, _estimateOneRepMax(loadKg, reps)),
        reps: standing.reps,
      );
    } else {
      own[exerciseId] = (
        e1rm: standing.e1rm,
        reps: math.max(standing.reps, reps),
      );
    }
  }

  /// The own bests rebuilt in one pass over the observations still stored:
  /// every `set` with reps >= 1, folded through the same function the live path
  /// uses.
  static _Own _rebuildOwn(List<WatchObservationRecord> observations) {
    final own = <String, ({double e1rm, int reps})>{};
    for (final observation in observations) {
      if (observation.kind != WatchObservationKind.set) continue;
      final exerciseId = observation.payload['exerciseId'];
      final reps = observation.payload['reps'];
      final load = observation.payload['loadKg'];
      if (exerciseId is! String || exerciseId.isEmpty) continue;
      if (reps is! num || reps.toInt() < 1) continue;
      _fold(
        exerciseId,
        reps.toInt(),
        load is num ? load.toDouble() : null,
        own,
      );
    }
    return own;
  }

  /// The frame's `bests` entries parsed once into the map detection reads, or
  /// null for an entry that is not the shape the payload promises: a frame is
  /// refused whole rather than half-understood.
  ///
  /// An entry names a non-empty string `exerciseId` and at least one axis: a
  /// finite `e1rmKg` above zero and/or a whole `repsBest` of one or more. A
  /// missing axis reads as zero, which is what an exercise absent from the frame
  /// reads as too.
  static _Frame? _parse(List<Map<String, Object?>> entries) {
    final parsed = <String, ({double e1rmKg, int repsBest})>{};
    for (final entry in entries) {
      final exerciseId = entry['exerciseId'];
      if (exerciseId is! String || exerciseId.isEmpty) return null;

      var e1rmKg = 0.0;
      if (entry.containsKey('e1rmKg')) {
        final value = entry['e1rmKg'];
        if (value is! num || !value.isFinite || value <= 0) return null;
        e1rmKg = value.toDouble();
      }

      var repsBest = 0;
      if (entry.containsKey('repsBest')) {
        final value = entry['repsBest'];
        if (value is! int || value < 1) return null;
        repsBest = value;
      }

      if (e1rmKg <= 0 && repsBest <= 0) return null;

      final standing = parsed[exerciseId] ?? (e1rmKg: 0.0, repsBest: 0);
      parsed[exerciseId] = (
        e1rmKg: math.max(standing.e1rmKg, e1rmKg),
        repsBest: math.max(standing.repsBest, repsBest),
      );
    }
    return parsed;
  }

  /// Whether two parsed frames carry the same numbers: what turns a repeated
  /// frame into no write at all.
  static bool _sameFrame(_Frame a, _Frame b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other == null ||
          other.e1rmKg != entry.value.e1rmKg ||
          other.repsBest != entry.value.repsBest) {
        return false;
      }
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
