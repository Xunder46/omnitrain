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
  }) : _mirror = mirror,
       _debounce = debounce,
       _sendTimeout = sendTimeout,
       _onFailure = onFailure;

  final LiveSessionMirrorState _mirror;

  /// How long the state must be quiet before the composed timers are sent. A
  /// constructor knob so tests drive it.
  final Duration _debounce;

  /// How long one pass may take before it is abandoned and reported. A
  /// constructor knob so tests drive it.
  final Duration _sendTimeout;

  /// Where a failure the push can report goes.
  final void Function(Object error, StackTrace stack)? _onFailure;

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

  /// Mirror copies this push has cleared on the wrist. The mirror holds only
  /// what the WATCH reports and the watch sends nothing back for a clear, so
  /// without this a stale copy would keep blocking every later, newer phone
  /// timer of its kind.
  final Map<String, _MirrorTimer> _stale = {};

  /// The drain a running [flush] is, and whether another pass was asked for
  /// while it ran. Two flushes that overlap are one drain.
  Future<void>? _draining;
  bool _again = false;

  /// The timers this push has delivered to the wrist and still holds on it,
  /// per wire kind, in the shape a snapshot's `timers` takes.
  ///
  /// A snapshot speaks for the wrist's timer state as a whole: it stops every
  /// timer the phone started that the snapshot does not name. A snapshot the
  /// phone composes therefore carries these, or the first snapshot after the
  /// phone starts an interval — or a rest — would reset the wrist's clock to
  /// zero.
  Map<String, Object?> deliveredTimers() => {
    for (final entry in _delivered.entries) entry.key: {...entry.value},
  };

  /// Binds the state whose changes are pushed. Binding the same state twice
  /// leaves one listener; [dispose] removes it.
  void bindWorkoutState(WorkoutState state) {
    if (identical(_workoutState, state)) return;
    _workoutState?.removeListener(_onChanged);
    _workoutState = state;
    state.addListener(_onChanged);
  }

  /// Closes the pending window and pushes the newest timers at once.
  ///
  /// A flush that arrives while one is running joins it and asks for one more
  /// pass after it, instead of running beside it.
  Future<void> flush() async {
    _window?.cancel();
    _window = null;

    final running = _draining;
    if (running != null) {
      _again = true;
      return running;
    }

    final drained = Completer<void>();
    _draining = drained.future;
    try {
      do {
        _again = false;
        await _pushOnce().timeout(
          _sendTimeout,
          onTimeout: () {
            _report(
              TimeoutException('timer push pass exceeded $_sendTimeout'),
              StackTrace.current,
            );
          },
        );
      } while (_again);
    } finally {
      _draining = null;
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
  /// with what the wrist holds and was delivered, and send what is left.
  Future<void> _pushOnce() async {
    try {
      final state = _workoutState;
      final session = state?.currentSession;
      if (state == null || session == null || !state.hasActiveSession) {
        _delivered.clear();
        _adopted.clear();
        _stale.clear();
        _sessionId = null;
        return;
      }
      if (_sessionId != session.id) {
        _delivered.clear();
        _adopted.clear();
        _stale.clear();
        _sessionId = session.id;
      }

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

      if (clears.isEmpty && next.isEmpty) return;

      if (clears.isNotEmpty) {
        if (!await _send(session.id, clears)) return;
        for (final kind in clears.keys) {
          _delivered.remove(kind);
          final cleared = _adopted.remove(kind);
          if (cleared != null) _stale[kind] = cleared;
        }
      }
      if (next.isEmpty) return;
      if (!await _send(session.id, next)) return;
      _delivered.addAll(next);
    } on Exception catch (e, s) {
      // A push that cannot be made must not disturb the phone — but it is
      // reported rather than swallowed.
      _report(e, s);
    }
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
