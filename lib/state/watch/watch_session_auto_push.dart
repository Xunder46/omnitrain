/// The one place a session is pushed from the phone (D-75).
///
/// Plan: `docs/plans/2026-10-06-17a-watch-auto-sync-pr1-plan/2026-10-06-17a-watch-auto-sync-pr1-plan.md`
/// (D-75…D-77, D-81…D-83). Before this, work done on the phone about a running
/// session reached the watch only when somebody tapped Sync.
///
/// Three rules shape this class:
///
/// 1. **Coalesce, then send only what changed** (D-76). Every notification of
///    the bound `WorkoutState` restarts a trailing window; when it closes the
///    payload is composed fresh and sent only if its deterministic encoding
///    differs from the last payload this push sent or baselined. A rest-timer
///    tick therefore sends nothing, and a burst of changes inside one window is
///    one frame. The payload is never cached: the newest state is the one that
///    matters.
/// 2. **The session's end is announced** (D-81). The phone's *own* sessions
///    decide — the ids of the payloads this push composed or baselined whose end
///    is not yet decided, not the mirror's session, which a wrist starting its
///    own workout moves onto a session this phone never held (F6). A row that
///    exists and ended → [LiveSessionMirrorState.completeSession] for it; a row
///    that is gone → [LiveSessionMirrorState.reportLifecycleFor] `abandoned` for
///    it; a session still running is kept only while it is still the phone's
///    current own session. Each id is dropped as it is announced, so each session
///    in an app run is announced once (F1), and a frame the wrist sends inside
///    the window cannot erase a finished session's pending announcement (S-87).
///    Never the phone's current-session pointer, which calendar browsing repoints
///    at a past session.
/// 3. **Dropped, never queued** (D-83). The transport reports what it cannot
///    carry and never throws; this push adds no queue, no retry and no
///    user-visible state, and a failure it can report — a repository read
///    included — leaves the phone undisturbed (F4). An `Error` is a programming
///    fault and is not swallowed (G2).
///
/// It persists nothing and writes nothing: it reads the phone's session through
/// the projection and the mirrored session's row through [getSession], and sends.
library;

import 'dart:async';
import 'dart:convert';

import '../../data/models/models.dart' show TrainingSession;
import '../../watch/session/watch_records.dart' show WatchLifecycleState;
import '../workout/workout_state.dart';
import 'live_session_mirror_state.dart';

/// Watches the phone's own session and keeps the watch told about it.
class WatchSessionAutoPush {
  WatchSessionAutoPush({
    required LiveSessionMirrorState mirror,
    required Future<TrainingSession?> Function(String sessionId) getSession,
    Duration debounce = const Duration(milliseconds: 250),
  }) : _mirror = mirror,
       _getSession = getSession,
       _debounce = debounce;

  final LiveSessionMirrorState _mirror;

  /// The row of the session the mirror holds, read from the repository the
  /// graph already has. A narrow seam on purpose: `lib/state` keeps depending
  /// on the [WorkoutRepository] interface, not on a storage implementation.
  final Future<TrainingSession?> Function(String sessionId) _getSession;

  /// How long the state must be quiet before the composed payload is sent
  /// (D-76). A constructor knob so tests drive it.
  final Duration _debounce;

  WorkoutState? _workoutState;
  Timer? _window;

  /// The encoding of the last payload this push sent or baselined, or null
  /// while it has none — the first composed payload is always sent.
  String? _baseline;

  /// The ids of the sessions the phone itself composed or baselined whose end
  /// has not been decided yet, oldest first — sessions it holds and has told the
  /// wrist about.
  ///
  /// A set rather than one id: a frame the wrist sends inside the debounce window
  /// re-baselines onto a newer session, and a single id would lose a finished
  /// session's pending announcement (S-87). Never the mirror's session: the wrist
  /// can start a workout of its own, which the phone refuses to adopt (D-10) and
  /// which is therefore not the phone's to end (F6).
  final List<String> _pendingEnds = [];

  /// The drain a running [flush] is, and whether another pass was asked for
  /// while it ran. Two flushes that overlap are one drain (F4).
  Future<void>? _draining;
  bool _again = false;

  /// Binds the state whose changes are pushed. Binding the same state twice
  /// leaves one listener; [dispose] removes it.
  void bindWorkoutState(WorkoutState state) {
    if (identical(_workoutState, state)) return;
    _workoutState?.removeListener(_onChanged);
    _workoutState = state;
    state.addListener(_onChanged);
  }

  /// Closes the pending window and pushes the newest state at once.
  ///
  /// A flush that arrives while one is running joins it and asks for one more
  /// pass after it, instead of running beside it: the end rules read the phone's
  /// row and then act on it, and two passes interleaved between the two announce
  /// one end twice (F4).
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
        await _pushOnce();
      } while (_again);
    } finally {
      _draining = null;
      drained.complete();
    }
  }

  /// One pass: every pending session's end, decided by its own row, and then the
  /// composed payload when it differs from the baseline.
  ///
  /// An `Exception` (F4, D-83) — a row or a composition the phone cannot read —
  /// leaves it exactly as it was: nothing sent, nothing cached, nothing queued,
  /// and the next notification tries again. An `Error` is a programming fault
  /// and is left to surface rather than read as "nothing to send" (G2).
  Future<void> _pushOnce() async {
    try {
      final composed = await _mirror.projectedSession();
      final composedId = composed?['sessionId'] as String?;
      _remember(composedId);

      await _announceEnd(composedId);

      if (composed == null) return; // nothing of the phone's own to assert
      final encoded = _encode(composed);
      if (encoded == _baseline) return;
      _baseline = encoded;
      await _mirror.sendState(composed);
    } on Exception {
      // F4: a push that cannot be made must not disturb the phone.
    }
  }

  /// Takes the phone's current session as the new baseline, sending nothing
  /// (D-82): a frame the phone applied from the wrist is never answered with a
  /// push of the rows that frame just brought in.
  ///
  /// It does compose, though, so the session it lands on joins the pending ends:
  /// a wrist frame must not be able to leave a session the phone finished inside
  /// the debounce window unannounced (S-87).
  Future<void> rebaseline() async {
    try {
      final composed = await _mirror.projectedSession();
      if (composed == null) return;
      _remember(composed['sessionId'] as String?);
      _baseline = _encode(composed);
    } on Exception {
      // F4, and the same reason [flush] holds: a frame the phone cannot turn
      // into a baseline is not the phone's news to push.
    }
  }

  /// Notes a session the phone itself just composed as one whose end is still to
  /// be decided. A null id composes nothing of the phone's own.
  void _remember(String? sessionId) {
    if (sessionId == null || _pendingEnds.contains(sessionId)) return;
    _pendingEnds.add(sessionId);
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
    _window = Timer(_debounce, () => unawaited(flush()));
  }

  /// The end rules of D-81, decided by the row of each session the phone itself
  /// composed and pushed — never by the mirror's session, which a wrist starting
  /// its own workout moves onto a session this phone never held (F6), and never
  /// by the phone's current-session pointer, which [WorkoutState.loadHistoricalSession]
  /// repoints at a past session while the mirrored one is still live.
  ///
  /// Every pending id is decided on each pass, and dropped once it is, so one
  /// session is announced once per app run (F1). A session whose row ended is
  /// announced `completed`; one whose row is gone, `abandoned`; one that is still
  /// running is kept only while it is still the phone's current own session —
  /// [currentId] — because one the phone merely stopped composing while it runs
  /// is not an end.
  Future<void> _announceEnd(String? currentId) async {
    if (_pendingEnds.isEmpty) return;
    for (final sessionId in List<String>.of(_pendingEnds)) {
      // A session the wrist ended itself: its lifecycle is what ended the phone's
      // copy, through the router, so the mirror no longer holds it as active and
      // an end has already been said.
      final held = _mirror.sessionId == sessionId;
      if (held && !_mirror.isActive) {
        _pendingEnds.remove(sessionId);
        continue;
      }

      final row = await _getSession(sessionId);
      if (row != null && row.endedAtMs == null) {
        // Still running: it stays pending only while the phone still owns it.
        if (sessionId != currentId) _pendingEnds.remove(sessionId);
        continue;
      }

      _pendingEnds.remove(sessionId);
      if (row == null) {
        // The row is gone: the phone discarded the session, and only for its own
        // session does "no row" mean that.
        await _mirror.reportLifecycleFor(
          sessionId,
          WatchLifecycleState.abandoned,
        );
        continue;
      }
      if (held) {
        await _mirror.completeSession();
      } else {
        await _mirror.reportLifecycleFor(
          sessionId,
          WatchLifecycleState.completed,
        );
      }
    }
  }

  /// The deterministic encoding two payloads are compared by: `jsonEncode` over
  /// a recursively key-sorted copy. Dart's `Map` equality is identity, so a
  /// comparison of the maps themselves would call every payload new.
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
}
