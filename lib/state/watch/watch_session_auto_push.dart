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
/// 2. **The session's end is announced** (D-81). While the mirror holds session
///    X as active, X's own repository row decides: ended → [LiveSessionMirrorState.completeSession],
///    gone → [LiveSessionMirrorState.reportLifecycle] `abandoned`. Never the
///    phone's current-session pointer, which calendar browsing repoints at a
///    past session.
/// 3. **Dropped, never queued** (D-83). The transport reports what it cannot
///    carry and never throws; this push adds no queue, no retry and no
///    user-visible state, and a failure leaves the phone undisturbed.
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

  /// Binds the state whose changes are pushed. Binding the same state twice
  /// leaves one listener; [dispose] removes it.
  void bindWorkoutState(WorkoutState state) {
    if (identical(_workoutState, state)) return;
    _workoutState?.removeListener(_onChanged);
    _workoutState = state;
    state.addListener(_onChanged);
  }

  /// Closes the pending window and pushes the newest state at once.
  Future<void> flush() async {
    _window?.cancel();
    _window = null;

    await _announceEnd();
    final composed = await _mirror.projectedSession();
    if (composed == null) return; // nothing of the phone's own to assert

    final encoded = _encode(composed);
    if (encoded == _baseline) return;
    _baseline = encoded;
    await _mirror.sendState(composed);
  }

  /// Takes the phone's current session as the new baseline, sending nothing
  /// (D-82): a frame the phone applied from the wrist is never answered with a
  /// push of the rows that frame just brought in.
  Future<void> rebaseline() async {
    final composed = await _mirror.projectedSession();
    if (composed == null) return;
    _baseline = _encode(composed);
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

  /// The end rules of D-81, decided by the mirrored session's own row — never
  /// by the phone's current-session pointer, which [WorkoutState.loadHistoricalSession]
  /// repoints at a past session while the mirrored one is still live.
  ///
  /// Nothing fires for a row that exists and is unended, and nothing fires
  /// twice: [LiveSessionMirrorState.completeSession] memoises and
  /// [LiveSessionMirrorState.reportLifecycle] applies locally, so both leave the
  /// mirror no longer holding the session as active.
  Future<void> _announceEnd() async {
    if (!_mirror.isActive) return;
    final sessionId = _mirror.sessionId;
    if (sessionId == null) return;

    final row = await _getSession(sessionId);
    if (row == null) {
      await _mirror.reportLifecycle(WatchLifecycleState.abandoned);
      return;
    }
    if (row.endedAtMs != null) await _mirror.completeSession();
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
