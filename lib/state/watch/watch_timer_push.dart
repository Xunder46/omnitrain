/// The phone's work timers, told to the watch (plan 43b3 D-2).
///
/// Plan: `docs/plans/2026-10-20-43b3-shared-timer-phone-sends-plan/`.
///
/// Same shape as `WatchSessionAutoPush`, and for the same reasons: a listener on
/// the bound `WorkoutState`, a trailing debounce window, one drain at a time,
/// and a pass bounded by a timeout. What differs is the content: every pass
/// composes the in-progress work timers of the phone's held session — and its
/// open rest, if it has one — as one `timer_state` frame, and sends only what
/// the wrist has not already been told.
///
/// Two rules shape the comparison:
///
/// 1. **The wrist's earlier start wins** (D-3, D-3b). A kind the mirror already
///    holds for the same slot — with the same state and stamps, or with an
///    earlier start — is not sent: it is the wrist's own timer the phone
///    adopted, or the frame this push already delivered. A skipped kind is not
///    recorded as delivered, so a later pause on the phone still travels. A
///    skipped identical timer is remembered, so the clear still goes out when
///    the phone's interval ends (plan 43c).
/// 2. **A replacement clears first** (D-2b). The wrist ignores a later start
///    while it still holds an earlier, not-stopped timer of the same kind and
///    slot, so a new interval replacing a delivered one goes out as two frames:
///    `{kind: null}` and then the new timer. A frame the radio did not carry
///    leaves the ledger untouched and stops the pass.
///
/// 3. **A snapshot names only the delivered timers the phone still runs (plan
///    121a D-1); a wrist clock for an interval the phone has already logged is
///    cleared whether or not the phone remembers delivering it (D-4, D-5).**
///    Plan 127 D-1, D-2: the named value is the phone's CURRENT timer for the
///    kind, and a start the radio refused (an owed one) rides the snapshot too,
///    matched against the ledger record first.
///
/// A rest travels on its own rule (plan 50a D-3). It belongs to no slot, and
/// the phone opens it at the instant the set was logged while the wrist starts
/// its own copy a few milliseconds later: two rests whose starts are within
/// half a second are the same rest, so the wrist's copy is not echoed back. A
/// pause or a resume on the phone still travels. A rest never answers
/// "earlier": the phone's frame supersedes the wrist's own copy.
///
/// The wrist is otherwise told work timers only (43b3 D-4).
library;

import 'dart:async';
import 'dart:convert';

import '../../core/platform/watch_delivery.dart';
import '../../core/sync_protocol/wire_timestamps.dart';
import '../../data/models/models.dart';
import '../workout/workout_state.dart';
import 'live_session_mirror_state.dart';

/// One timer as the mirror holds it: the slot it names and its start.
typedef _MirrorTimer = ({Object? slotId, Object? startedAt});

/// How the wrist's timer, as the mirror holds it, relates to the phone's.
enum _WristHolds {
  /// The wrist holds nothing that makes sending pointless.
  no,

  /// The same slot, not stopped, every field equal: the phone's own timer is
  /// the wrist's (adopted from it, or already delivered).
  identical,

  /// The same slot, not stopped, with an EARLIER start: it wins on the wrist.
  earlier,
}

/// Watches the phone's in-progress work timers and keeps the wrist told.
class WatchTimerPush {
  WatchTimerPush({
    required LiveSessionMirrorState mirror,
    Duration debounce = const Duration(milliseconds: 250),
    Duration sendTimeout = const Duration(seconds: 10),
    void Function(Object error, StackTrace stack)? onFailure,
    void Function()? onOwed,
  }) : _mirror = mirror,
       _debounce = debounce,
       _sendTimeout = sendTimeout,
       _onFailure = onFailure,
       _onOwed = onOwed;

  final LiveSessionMirrorState _mirror;

  /// How long the state must be quiet before the composed timers are sent. A
  /// constructor knob so tests drive it.
  final Duration _debounce;

  /// How long one pass may take before it is abandoned and reported. A
  /// constructor knob so tests drive it.
  final Duration _sendTimeout;

  /// Where a failure the push can report goes.
  final void Function(Object error, StackTrace stack)? _onFailure;

  /// Called at the end of [_owe] when it recorded at least one entry: asks the
  /// graph for a snapshot pass (plan 127 D-5).
  final void Function()? _onOwed;

  WorkoutState? _workoutState;
  Timer? _window;

  /// The session the ledger belongs to, or null while there is none.
  String? _sessionId;

  /// The timer JSON last delivered to the wrist, per wire kind. A null-only
  /// frame removes its kinds; a frame the radio did not carry leaves this as it
  /// was, so the next notification offers it again.
  final Map<String, Map<String, Object?>> _delivered = {};

  /// The wrist's own timers the phone runs (plan 43c D-3), per wire kind: the
  /// mirror held exactly the phone's timer, so nothing was sent and `_delivered`
  /// has no entry. When the phone's interval ends the wrist's clock must still
  /// be cleared.
  final Map<String, _MirrorTimer> _adopted = {};

  /// Mirror copies this push has cleared on the wrist, and the mirror copies
  /// the reconcile cleared (plan 121a D-5). The mirror holds only
  /// what the WATCH reports and the watch sends nothing back for a clear, so
  /// without this a stale copy would keep blocking every later, newer phone
  /// timer of its kind.
  final Map<String, _MirrorTimer> _stale = {};

  /// The starts this push offered and the radio did not carry (plan 98 D-2), per
  /// wire kind. The wrist never held them, so a clears-only pass — the trigger
  /// where the wrist talks to the phone, or comes back into reach — may send
  /// them; every other start stays withheld (54 D-1a), because a timer the wrist
  /// already ended was delivered or adopted, never owed. An owed start also
  /// rides the durable snapshots as the newest offered record for its kind
  /// (plan 127 D-2). Cleared per kind when
  /// the frame is delivered or the phone no longer wants that kind, and with the
  /// ledger on a session change.
  final Map<String, Map<String, Object?>> _owed = {};

  /// The drain a running [flush] is, and whether another pass was asked for
  /// while it ran. Two flushes that overlap are one drain.
  Future<void>? _draining;
  bool _again = false;

  /// Whether a flush that joined a running drain asked for a full pass (54,
  /// fix round 1). The request decides what the pass it asks for may send: a
  /// clears-only pass must never withhold a start an ordinary [flush] — a phone
  /// state change — owes.
  bool _fullAgain = false;

  /// The timers this push has delivered or owes to the wrist, per wire kind,
  /// in the shape a snapshot's `timers` takes — but the value is the phone's
  /// CURRENT timer for the kind, not the stored copy.
  ///
  /// A snapshot names the phone's current timer for a kind the ledger
  /// delivered or owes (candidates `_delivered ∪ _owed`, matched against the
  /// owed record first — plan 127 D-1, D-2), read from the phone's state when
  /// the snapshot is composed, so a logged interval cannot come back on the
  /// wrist through the durable snapshot. An owed start rides the snapshot;
  /// for a work kind already delivered with a different slot or start, the
  /// new start is withheld and omission stops the old one (plan 127 D-2).
  Map<String, Object?> snapshotTimers() {
    final state = _workoutState;
    final session = state?.currentSession;
    if (state == null ||
        session == null ||
        !state.hasActiveSession ||
        _sessionId != session.id) {
      return const <String, Object?>{};
    }
    final wanted = _composeWanted(state);
    final named = <String, Object?>{};
    for (final kind in {..._delivered.keys, ..._owed.keys}) {
      final current = wanted[kind];
      if (current == null) continue; // (ii) the phone no longer runs it
      final owed = _owed[kind];
      final delivered = _delivered[kind];
      // The ledger record the snapshot is matched against: an owed frame (the
      // newest offered) first, else the delivered one (plan 127 D-2).
      final record = owed ?? delivered;
      if (record == null) continue;
      if (kind != 'rest') {
        // D-2 replacement rule: while the wrist may still hold an older phone
        // timer of this kind (a different slot or start was delivered), the new
        // one is withheld: a snapshot cannot clear, and omitting stops the old
        // one.
        if (owed != null &&
            delivered != null &&
            (current['sessionExerciseId'] != delivered['sessionExerciseId'] ||
                !_sameInstant(current['startedAt'], delivered['startedAt']))) {
          continue;
        }
        if (current['sessionExerciseId'] != record['sessionExerciseId']) {
          continue; // (iii)
        }
      }
      final sameStart = kind == 'rest'
          ? _restStartWithinTolerance(current['startedAt'], record['startedAt'])
          : _sameInstant(current['startedAt'], record['startedAt']);
      if (!sameStart) continue; // (iv)
      if (_wristEnded(session.id, kind, record)) continue; // (v)
      // D-1: the value is what the phone runs NOW (a pause the radio refused
      // still rides), never the stored delivered copy.
      named[kind] = {...current};
    }
    return named;
  }

  /// Binds the state whose changes are pushed. Binding the same state twice
  /// leaves one listener; [dispose] removes it.
  void bindWorkoutState(WorkoutState state) {
    if (identical(_workoutState, state)) return;
    _workoutState?.removeListener(_onChanged);
    _workoutState = state;
    state.addListener(_onChanged);
  }

  /// Pushes the clears this push owes and the starts the radio refused (plan
  /// 98 D-2), for the trigger where the wrist talks to the phone or comes back
  /// into reach: a clear it never received is re-offered, and a start the wrist
  /// never held is sent now, while every other start is withheld so a timer the
  /// wrist already ended is not restarted (54 D-1).
  Future<void> flushClears() => _flush(clearsOnly: true);

  /// Closes the pending window and pushes the newest timers at once.
  Future<void> flush() => _flush(clearsOnly: false);

  /// Runs a drain, or joins the one running and asks for one more pass after it.
  ///
  /// The request that asks for a pass decides what it may send, so an ordinary
  /// [flush] that joins or follows a clears-only drain still gets a full pass:
  /// a start the phone owes is never withheld because a clears-only flush
  /// happened to be running.
  ///
  /// The converse window is accepted: a clears-only flush that joins a running
  /// full drain makes the follow-up pass clears-only. The start that full pass
  /// could not send is owed (plan 98 D-2), so the follow-up pass sends it; a
  /// start that was not offered yet waits for the next phone-state trigger.
  /// A full follow-up on a wrist-frame trigger is the behaviour 54 D-1a rules
  /// out.
  Future<void> _flush({required bool clearsOnly}) async {
    // Only a full pass takes over the pending window. A clears-only pass sends
    // no start, so cancelling the window would lose the phone news it was armed
    // for (plan 98: a reachability event inside the window of a timer start).
    if (!clearsOnly) {
      _window?.cancel();
      _window = null;
    }

    final running = _draining;
    if (running != null) {
      _again = true;
      if (!clearsOnly) _fullAgain = true;
      return running;
    }

    final drained = Completer<void>();
    _draining = drained.future;
    try {
      var onlyClears = clearsOnly;
      do {
        _again = false;
        await _pushOnce(clearsOnly: onlyClears).timeout(
          _sendTimeout,
          onTimeout: () {
            _report(
              TimeoutException('timer push pass exceeded $_sendTimeout'),
              StackTrace.current,
            );
          },
        );
        onlyClears = !_fullAgain;
        _fullAgain = false;
      } while (_again);
    } finally {
      _draining = null;
      _fullAgain = false;
      drained.complete();
    }
  }

  /// Unbinds the state and cancels the pending window.
  void dispose() {
    _workoutState?.removeListener(_onChanged);
    _workoutState = null;
    _window?.cancel();
    _window = null;
  }

  void _onChanged() {
    _window?.cancel();
    _window = Timer(
      _debounce,
      () => unawaited(
        flush().catchError((Object e, StackTrace s) => _report(e, s)),
      ),
    );
  }

  /// One pass: compose the held session's in-progress work timers, compare them
  /// with what the wrist holds and was delivered, and send what is left. A
  /// clears-only pass sends no start (54 D-1).
  Future<void> _pushOnce({required bool clearsOnly}) async {
    try {
      final state = _workoutState;
      final session = state?.currentSession;
      if (state == null || session == null || !state.hasActiveSession) {
        _delivered.clear();
        _adopted.clear();
        _stale.clear();
        _owed.clear();
        _sessionId = null;
        return;
      }
      if (_sessionId != session.id) {
        _delivered.clear();
        _adopted.clear();
        _stale.clear();
        _owed.clear();
        _sessionId = session.id;
      }

      final wanted = _composeWanted(state);

      // Plan 98 D-2: a start the phone no longer wants is not owed any more.
      _owed.removeWhere((kind, _) => !wanted.containsKey(kind));

      // Plan 43c D-3: a timer the wrist started and the phone ran is over when
      // the phone no longer wants that slot and start. If the mirror still
      // holds it the wrist's clock must be cleared; if the wrist logged or
      // stopped first there is nothing to clear.
      final retired = <String>{};
      for (final held in _adopted.entries.toList()) {
        final timer = wanted[held.key];
        final sameInterval =
            timer != null &&
            timer['sessionExerciseId'] == held.value.slotId &&
            (held.key == 'rest'
                ? _restStartWithinTolerance(
                    timer['startedAt'],
                    held.value.startedAt,
                  )
                : _sameInstant(timer['startedAt'], held.value.startedAt));
        if (sameInterval) continue;
        if (_mirrorHolds(session.id, held.key, held.value)) {
          retired.add(held.key);
        } else {
          _adopted.remove(held.key);
        }
      }

      final clears = <String, Object?>{};
      final next = <String, Map<String, Object?>>{};
      for (final entry in wanted.entries) {
        final kind = entry.key;
        final timer = entry.value;
        final holds = retired.contains(kind)
            ? _WristHolds.no
            : _wristHolds(session.id, kind, timer);
        if (holds == _WristHolds.identical) {
          _adopted[kind] = (
            slotId: timer['sessionExerciseId'],
            startedAt: timer['startedAt'],
          );
        }
        if (holds != _WristHolds.no) continue;
        final delivered = _delivered[kind];
        if (delivered != null && _encode(delivered) == _encode(timer)) {
          continue;
        }
        if (delivered != null &&
            !_sameInstant(delivered['startedAt'], timer['startedAt'])) {
          // D-2b: the wrist would ignore a later start while it still holds
          // the earlier one, so the clear must be its own frame before it.
          clears[kind] = null;
        }
        next[kind] = timer;
      }
      for (final kind in _delivered.keys) {
        if (!wanted.containsKey(kind)) clears[kind] = null;
      }
      for (final kind in retired) {
        clears[kind] = null;
      }
      // Plan 121a D-4: a wrist clock for an interval the phone has already logged
      // is over, whoever started it and whatever the phone remembers.
      final reconciled = <String, _MirrorTimer>{};
      for (final kind in _workKinds) {
        if (wanted.containsKey(kind) || clears.containsKey(kind)) continue;
        final held = _loggedWristTimer(state, session.id, kind);
        if (held == null) continue;
        clears[kind] = null;
        reconciled[kind] = held;
      }
      // 54 D-1: the wrist's own frame triggers the debt, not the phone's news.
      // The debt includes a start the radio refused (plan 98 D-2): the wrist
      // never held it, so sending it cannot restart a timer the wrist ended.
      if (clearsOnly) {
        next.removeWhere((kind, _) => !_owed.containsKey(kind));
        // Plan 127 D-4: a snapshot (or a frame whose answer was lost) may have
        // delivered an owed START, and the wrist may then have ended it. An
        // owed start (never delivered on a frame) is dropped, and no longer
        // owed, when the mirror holds that very slot and start as stopped
        // (54 D-1a). A paused or running copy is NOT a reason to drop: the
        // owed record is the phone's newest state (a refused pause or resume
        // included), and sending it is how the wrist learns it (review finding).
        next.removeWhere((kind, timer) {
          // An owed pause or resume (a delivered kind) is not a start.
          if (_delivered.containsKey(kind)) return false;
          if (!_wristEnded(session.id, kind, timer)) return false;
          _owed.remove(kind);
          return true;
        });
      }

      if (clears.isEmpty && next.isEmpty) return;

      if (clears.isNotEmpty) {
        if (!await _send(session.id, clears)) {
          _owe(session.id, next);
          return;
        }
        for (final kind in clears.keys) {
          _delivered.remove(kind);
          final cleared = _adopted.remove(kind);
          if (cleared != null) {
            _stale[kind] = cleared;
          } else {
            final logged = reconciled[kind];
            if (logged != null) _stale[kind] = logged;
          }
        }
      }
      if (next.isEmpty) return;
      if (!await _send(session.id, next)) {
        _owe(session.id, next);
        return;
      }
      _delivered.addAll(next);
      _owed.removeWhere((kind, _) => next.containsKey(kind));
    } on Exception catch (e, s) {
      // A push that cannot be made must not disturb the phone — but it is
      // reported rather than swallowed.
      _report(e, s);
    }
  }

  /// Composes the in-progress work timers of the held session — and its open
  /// rest, if it has one — as one map by wire kind. Shared by [_pushOnce] and
  /// [snapshotTimers], so the two never disagree (plan 121a D-1).
  Map<String, Map<String, Object?>> _composeWanted(WorkoutState state) {
    final wanted = <String, Map<String, Object?>>{};
    for (final timer in state.inProgressWorkTimers()) {
      wanted[timer.wireKind] = <String, Object?>{
        'kind': timer.wireKind,
        'state': timer.paused ? 'paused' : 'running',
        'startedAt': utcIso(
          DateTime.fromMillisecondsSinceEpoch(timer.startedAtMs, isUtc: true),
        ),
        'accumulatedPauseMs': timer.accumulatedPauseMs,
        if (timer.paused)
          'pausedAt': utcIso(
            DateTime.fromMillisecondsSinceEpoch(
              timer.pausedAtMs!,
              isUtc: true,
            ),
          ),
        if (timer.plannedDurationMs != null)
          'plannedDurationMs': timer.plannedDurationMs,
        'sessionExerciseId': timer.effortId,
      };
    }

    // Plan 50a D-2: a rest belongs to no slot and has no planned length, so
    // it is composed without either key. The validator refuses a rest that
    // carries a plan.
    final rest = state.inProgressRest();
    if (rest != null) {
      wanted['rest'] = <String, Object?>{
        'kind': 'rest',
        'state': rest.paused ? 'paused' : 'running',
        'startedAt': utcIso(
          DateTime.fromMillisecondsSinceEpoch(rest.startedAtMs, isUtc: true),
        ),
        'accumulatedPauseMs': rest.accumulatedPauseMs,
        if (rest.paused)
          'pausedAt': utcIso(
            DateTime.fromMillisecondsSinceEpoch(
              rest.pausedAtMs!,
              isUtc: true,
            ),
          ),
      };
    }
    return wanted;
  }

  /// Records [next] as the starts the radio refused (plan 98 D-2) — except a
  /// timer the wrist itself ended: the mirror holds that very timer as
  /// stopped, so sending it again would restart a clock the wrist finished
  /// (54 D-1a). The review of plan 98 found this path.
  void _owe(String sessionId, Map<String, Map<String, Object?>> next) {
    var owedAny = false;
    for (final entry in next.entries) {
      if (!_wristEnded(sessionId, entry.key, entry.value)) {
        _owed[entry.key] = entry.value;
        owedAny = true;
      }
    }
    // A delivered frame never calls it (plan 127 D-5).
    if (owedAny) _onOwed?.call();
  }

  /// True when the mirror holds [timer] of [kind] as stopped: the same slot and
  /// the same start (a rest within the tolerance of 50a D-3).
  bool _wristEnded(String sessionId, String kind, Map<String, Object?> timer) {
    if (_mirror.sessionId != sessionId) return false;
    final timers = _mirror.state['timers'];
    if (timers is! Map) return false;
    final held = timers[kind];
    if (held is! Map || held['state'] != 'stopped') return false;
    if (kind != 'rest' &&
        held['sessionExerciseId'] != timer['sessionExerciseId']) {
      return false;
    }
    return kind == 'rest'
        ? _restStartWithinTolerance(held['startedAt'], timer['startedAt'])
        : _sameInstant(held['startedAt'], timer['startedAt']);
  }

  /// How the wrist's timer of [kind], as the mirror holds it, relates to
  /// [timer] (D-3b): the same slot and not stopped, and either every field
  /// equal to ours or a start earlier than ours, which wins on the wrist. A
  /// mirror copy this push has already cleared (plan 43c D-3) holds nothing.
  _WristHolds _wristHolds(
    String sessionId,
    String kind,
    Map<String, Object?> timer,
  ) {
    if (_mirror.sessionId != sessionId) return _WristHolds.no;
    final timers = _mirror.state['timers'];
    if (timers is! Map) return _WristHolds.no;
    final held = timers[kind];
    if (held is! Map) return _WristHolds.no;
    if (kind != 'rest' &&
        held['sessionExerciseId'] != timer['sessionExerciseId']) {
      return _WristHolds.no;
    }
    if (held['state'] == 'stopped') return _WristHolds.no;
    final stale = _stale[kind];
    if (stale != null &&
        stale.slotId == held['sessionExerciseId'] &&
        (kind == 'rest'
            // The adopted copy sits milliseconds after the phone's start, so
            // an exact comparison would never recognise it.
            ? _restStartWithinTolerance(stale.startedAt, held['startedAt'])
            : _sameInstant(stale.startedAt, held['startedAt']))) {
      return _WristHolds.no;
    }

    final sameState =
        held['state'] == timer['state'] &&
        _sameInstant(held['pausedAt'], timer['pausedAt']) &&
        (held['accumulatedPauseMs'] ?? 0) == (timer['accumulatedPauseMs'] ?? 0);

    // D-3 for a rest: no slot to compare, and a start within half a second is
    // the same rest (the wrist starts its own a moment after the phone logs
    // the set). It never answers `earlier` — the phone's frame supersedes it.
    if (kind == 'rest') {
      if (!_restStartWithinTolerance(held['startedAt'], timer['startedAt'])) {
        return _WristHolds.no;
      }
      return sameState ? _WristHolds.identical : _WristHolds.no;
    }

    final same =
        sameState && _sameInstant(held['startedAt'], timer['startedAt']);
    if (same) return _WristHolds.identical;

    final theirs = _instant(held['startedAt']);
    final ours = _instant(timer['startedAt']);
    return theirs != null && ours != null && theirs.isBefore(ours)
        ? _WristHolds.earlier
        : _WristHolds.no;
  }

  /// The work kinds the reconcile covers (a rest is never reconciled).
  static const List<String> _workKinds = ['elapsed', 'hold', 'round'];

  /// How far apart the wrist's start and the phone's logged start may be and
  /// still name one interval; the same tolerance as TimerManager's
  /// `_sameStartToleranceMs` (plan 121a D-4).
  static const int _loggedStartToleranceMs = 1000;

  /// The mirror's running [kind] copy when the phone has already logged that very
  /// interval (plan 121a D-4), else null. Needs all of: the mirror is for
  /// [sessionId]; the copy is a Map not `stopped` that names a non-empty slot;
  /// it is not the copy this push already cleared (`_stale`); the phone's effort
  /// of that slot has the effort kind that maps to [kind] (`timed`→`elapsed`,
  /// `drill`→`hold`, `round`→`round`); at least one of its intervals is finished
  /// with a start within [_loggedStartToleranceMs] of the copy's start, and none
  /// is active or paused with such a start.
  _MirrorTimer? _loggedWristTimer(
    WorkoutState state,
    String sessionId,
    String kind,
  ) {
    if (_mirror.sessionId != sessionId) return null;
    final timers = _mirror.state['timers'];
    if (timers is! Map) return null;
    final held = timers[kind];
    if (held is! Map || held['state'] == 'stopped') return null;
    final slot = held['sessionExerciseId'];
    if (slot is! String || slot.isEmpty) return null;
    final stale = _stale[kind];
    if (stale != null &&
        stale.slotId == slot &&
        _sameInstant(stale.startedAt, held['startedAt'])) {
      return null;
    }
    final started = _instant(held['startedAt']);
    if (started == null) return null;
    final startMs = started.millisecondsSinceEpoch;

    SegmentEffort? effort;
    for (final segment in state.segments) {
      for (final candidate in state.getEffortsForSegment(segment.id)) {
        if (candidate.id == slot) effort = candidate;
      }
    }
    if (effort == null) return null;
    final mapsTo = switch (effort.effortKind) {
      'timed' => 'elapsed',
      'drill' => 'hold',
      'round' => 'round',
      _ => null,
    };
    if (mapsTo != kind) return null;

    var finished = false;
    var inProgress = false;
    // One-sided: the phone's interval started at or after the wrist's copy. A
    // copy that started LATER than the logged interval is a newer wrist timer
    // (S-6329), never the one the phone logged.
    bool near(int ms) {
      final gap = ms - startMs;
      return gap >= 0 && gap <= _loggedStartToleranceMs;
    }
    if (effort.effortKind == 'round') {
      for (final round in state.getRoundsForEffort(slot)) {
        if (!near(round.startedAtMs)) continue;
        if (round.state == RoundState.finished) finished = true;
        if (round.state == RoundState.active ||
            round.state == RoundState.paused) {
          inProgress = true;
        }
      }
    } else {
      for (final timed in state.getTimedInstancesForEffort(slot)) {
        if (!near(timed.startedAtMs)) continue;
        if (timed.state == TimedState.finished) finished = true;
        if (timed.state == TimedState.active ||
            timed.state == TimedState.paused) {
          inProgress = true;
        }
      }
    }
    if (!finished || inProgress) return null;
    return (slotId: slot, startedAt: held['startedAt']);
  }

  /// True while the mirror holds exactly [timer] for [kind]: the same slot and
  /// start, not stopped, and not already cleared by this push.
  bool _mirrorHolds(String sessionId, String kind, _MirrorTimer timer) {
    if (_mirror.sessionId != sessionId) return false;
    final timers = _mirror.state['timers'];
    if (timers is! Map) return false;
    final held = timers[kind];
    if (held is! Map) return false;
    return held['sessionExerciseId'] == timer.slotId &&
        held['state'] != 'stopped' &&
        (kind == 'rest'
            ? _restStartWithinTolerance(held['startedAt'], timer.startedAt)
            : _sameInstant(held['startedAt'], timer.startedAt));
  }

  /// How far apart two rest starts may be and still name one rest (50a D-3):
  /// half a second. The phone opens its rest at the set's logged instant while
  /// the wrist starts its own tens of milliseconds later; a wider window would
  /// merge two real consecutive rests logged less than a second apart.
  static const int _restStartToleranceMs = 500;

  static bool _restStartWithinTolerance(Object? a, Object? b) {
    final left = _instant(a);
    final right = _instant(b);
    if (left == null || right == null) return false;
    return left.difference(right).inMilliseconds.abs() <= _restStartToleranceMs;
  }

  /// Sends one frame and answers whether the radio delivered it. An undelivered
  /// frame leaves the ledger as it was and stops the pass.
  Future<bool> _send(String sessionId, Map<String, Object?> timers) async {
    final delivery = await _mirror.sendTimers(sessionId, timers);
    return delivery == WatchDelivery.delivered;
  }

  static DateTime? _instant(Object? value) {
    if (value is! String) return null;
    try {
      return parseUtcIso(value);
    } on FormatException {
      return null;
    }
  }

  static bool _sameInstant(Object? a, Object? b) {
    final left = _instant(a);
    final right = _instant(b);
    if (left == null || right == null) return a == b;
    return left == right;
  }

  static String _encode(Map<String, Object?> payload) =>
      jsonEncode(_sorted(payload));

  static Object? _sorted(Object? value) {
    if (value is Map) {
      final entries = [
        for (final entry in value.entries)
          MapEntry(entry.key.toString(), entry.value),
      ]..sort((a, b) => a.key.compareTo(b.key));
      return <String, Object?>{
        for (final entry in entries) entry.key: _sorted(entry.value),
      };
    }
    if (value is List) return [for (final item in value) _sorted(item)];
    return value;
  }

  /// Hands [error] to the injected failure hook, when the graph gave one.
  void _report(Object error, StackTrace stack) =>
      _onFailure?.call(error, stack);
}
