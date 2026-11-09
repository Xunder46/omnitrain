/// A work timer the watch started, applied to the phone's own interval (43b2
/// D-3).
///
/// Plan: `docs/plans/2026-10-20-43b2-shared-timer-phone-receives-plan/`.
///
/// The wrist announces every timer it starts, pauses and stops as a
/// `timer_state` frame; the mirror folds those into `state['timers']`, one map
/// per wire kind. This class listens to the mirror and, on each change, hands a
/// running timer to the interval it names through
/// `WorkoutState.adoptRemoteWorkTimer` (D-1, D-2). It also listens to the
/// `WorkoutState`, so a timer frame that arrived before the phone adopted the
/// session is still applied once the session becomes the phone's.
///
/// Three rules keep a stream of notifications from writing the same timer
/// twice:
///
/// 1. **The mirror must hold the phone's session.** A timer for a session the
///    phone is not running is not this phone's news.
/// 2. **A stop is not applied** (A-2): the wrist's logged entry fills and
///    finishes the interval (43a), which stops the phone's ticker.
/// 3. **The encoding last applied per kind is remembered,** whether or not the
///    adoption wrote: a refused timer is not retried until the frame changes.
///
/// Passes are serialized like `WatchTimerPush`'s: a flush that arrives while
/// one runs joins it and asks for one more pass.
library;

import 'dart:async';
import 'dart:convert';

import '../../core/sync_protocol/wire_timestamps.dart';
import '../workout/timer_manager.dart';
import '../workout/workout_state.dart';
import 'live_session_mirror_state.dart';

/// Watches the wrist's timers and keeps the phone's intervals in step.
class WatchTimerAdoption {
  WatchTimerAdoption({
    required LiveSessionMirrorState mirror,
    void Function(Object error, StackTrace stack)? onFailure,
  }) : _mirror = mirror,
       _onFailure = onFailure {
    _mirror.addListener(_onChanged);
  }

  /// The wire kinds this adoption reads, in the order a pass visits them.
  static const List<String> _wireKinds = ['round', 'hold', 'elapsed'];

  final LiveSessionMirrorState _mirror;

  /// Where a failure the adoption can report goes.
  final void Function(Object error, StackTrace stack)? _onFailure;

  WorkoutState? _workoutState;

  /// The session [_applied] belongs to, or null while there is none.
  String? _sessionId;

  /// The timer JSON last applied per wire kind.
  final Map<String, String> _applied = {};

  /// The pass a running [flush] is, and whether another was asked for while
  /// it ran. Two flushes that overlap are one pass.
  Future<void>? _draining;
  bool _again = false;

  /// Binds the state whose session the timers are adopted into. Binding the
  /// same state twice leaves one listener; [dispose] removes it.
  void bindWorkoutState(WorkoutState state) {
    if (identical(_workoutState, state)) return;
    _workoutState?.removeListener(_onChanged);
    _workoutState = state;
    state.addListener(_onChanged);
  }

  /// Runs one adoption pass at once.
  ///
  /// A flush that arrives while one is running joins it and asks for one more
  /// pass after it, instead of running beside it.
  Future<void> flush() async {
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
        await _adoptOnce();
      } while (_again);
    } finally {
      _draining = null;
      drained.complete();
    }
  }

  /// Removes every listener this class added.
  void dispose() {
    _mirror.removeListener(_onChanged);
    _workoutState?.removeListener(_onChanged);
    _workoutState = null;
  }

  void _onChanged() {
    unawaited(flush().catchError((Object e, StackTrace s) => _report(e, s)));
  }

  /// One pass: for each wire kind the mirror holds, hand the timer to the
  /// interval its slot names, unless it is stopped, named nothing, names no
  /// session this phone is running, or is the frame last applied.
  Future<void> _adoptOnce() async {
    try {
      final state = _workoutState;
      final session = state?.currentSession;
      if (state == null ||
          session == null ||
          !state.hasActiveSession ||
          _mirror.sessionId != session.id) {
        return;
      }
      if (_sessionId != session.id) {
        _applied.clear();
        _sessionId = session.id;
      }

      final timers = _mirror.state['timers'];
      if (timers is! Map) return;

      for (final kind in _wireKinds) {
        final timer = timers[kind];
        if (timer is! Map) continue;
        if (timer['state'] == 'stopped') continue;
        final slot = timer['sessionExerciseId'];
        if (slot is! String || slot.isEmpty) continue;

        final encoded = _encode(timer);
        if (_applied[kind] == encoded) continue;

        final remote = RemoteWorkTimer(
          wireKind: kind,
          startedAtMs: parseUtcIso(timer['startedAt']).millisecondsSinceEpoch,
          pausedAtMs: timer['pausedAt'] == null
              ? null
              : parseUtcIso(timer['pausedAt']).millisecondsSinceEpoch,
          accumulatedPauseMs: (timer['accumulatedPauseMs'] as int?) ?? 0,
          plannedDurationMs: timer['plannedDurationMs'] as int?,
        );
        await state.adoptRemoteWorkTimer(slot, remote);
        _applied[kind] = encoded;
      }
    } on Exception catch (e, s) {
      // A timer that cannot be applied must not disturb the phone — but it is
      // reported rather than swallowed.
      _report(e, s);
    }
  }

  static String _encode(Object? payload) => jsonEncode(_sorted(payload));

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
