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
///    it; a session still running is kept while it still runs and the phone is
///    not on another live session of its own. Each id is dropped as it is
///    announced, so each session in an app run is announced once (F1), and a
///    frame the wrist sends inside the window cannot erase a finished session's
///    pending announcement (S-87).
///    Never the phone's current-session pointer, which calendar browsing repoints
///    at a past session.
/// 3. **Dropped, never queued** (D-83). The transport reports what it cannot
///    carry and never throws; this push adds no queue, no retry and no
///    user-visible state, and a failure it can report — a repository read
///    included — leaves the phone undisturbed (F4). A pass that never finishes
///    is abandoned at its `sendTimeout` and reported through the failure hook,
///    so a silent radio cannot swallow every later frame for the rest of the
///    app run (D-98), and the debounce path reports what escapes a pass instead
///    of raising an unhandled async error (D-99). An `Error` is a programming
///    fault and is not swallowed (G2): a direct caller still sees it.
/// 4. **A set that vanished is announced** (D-110). The push is the only
///    component that knows what the wrist was last told, so it keeps that ledger
///    per session (D-111) and sends one `delete_entry` for every id that was in
///    it and is no longer held. The first pass for a session only seeds it. Each
///    deletion carries a change id minted per *event* (F2) and an id whose frame
///    the transport threw on stays owed until it has gone (F7).
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
    Future<Set<String>> Function(String sessionId)? heldWristEntryIds,
    Duration debounce = const Duration(milliseconds: 250),
    Duration sendTimeout = const Duration(seconds: 10),
    DateTime Function()? clock,
    void Function(Object error, StackTrace stack)? onFailure,
  }) : _mirror = mirror,
       _getSession = getSession,
       _heldWristEntryIds = heldWristEntryIds ?? _noWristEntries,
       _debounce = debounce,
       _sendTimeout = sendTimeout,
       _clock = clock ?? DateTime.now,
       _onFailure = onFailure;

  /// No ids of the wrist's own: the default for a push built without the
  /// adoption bridge, where only the phone's own entries are known.
  static Future<Set<String>> _noWristEntries(String sessionId) async =>
      const <String>{};

  final LiveSessionMirrorState _mirror;

  /// The row of the session the mirror holds, read from the repository the
  /// graph already has. A narrow seam on purpose: `lib/state` keeps depending
  /// on the [WorkoutRepository] interface, not on a storage implementation.
  final Future<TrainingSession?> Function(String sessionId) _getSession;

  /// The ids the wrist itself logged and this phone still holds for a session —
  /// the bridge's claim rule, injected the way [_getSession] is (D-112).
  final Future<Set<String>> Function(String sessionId) _heldWristEntryIds;

  /// How long the state must be quiet before the composed payload is sent
  /// (D-76). A constructor knob so tests drive it.
  final Duration _debounce;

  /// How long one pass may take before it is abandoned and reported (D-98). A
  /// radio that never answers must not hold the drain open for the rest of the
  /// app run — every later frame would be dropped by the `_again` branch. A
  /// constructor knob so tests drive it.
  final Duration _sendTimeout;

  /// The phone's wall clock, for the stamp a deletion frame's change id carries
  /// (F2) — the same clock the graph stamps with. A constructor knob so tests
  /// pin it.
  final DateTime Function() _clock;

  /// Where a failure the push can report — a pass that timed out (D-98), or an
  /// `Exception` a pass could not read past — goes. An `Error` is not reported
  /// here: a direct caller still sees it (G2).
  final void Function(Object error, StackTrace stack)? _onFailure;

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

  /// The entry ids the wrist was expected to hold at the end of this push's last
  /// pass, per composed session (D-111): what the phone told the wrist about,
  /// which is the only thing that can vanish from it.
  ///
  /// Keyed by composed session id and dropped for the others on every pass, so a
  /// phone that leaves a session and comes back re-seeds rather than comparing
  /// the held session against another session's ids (D-114). Memory-only, and
  /// that is the contract: a relaunch re-seeds from what the phone holds now
  /// (D-111). An id whose frame the transport threw on stays in it (F7).
  final Map<String, Set<String>> _announced = {};

  /// The deletions that have not gone out yet, per composed session, by entry id
  /// → the change id that event was minted (F2, F7).
  ///
  /// An entry leaves it when its frame has been handed to the mirror, and the
  /// change id it carries is minted once per deletion event and reused while the
  /// frame is owed: a transport that fails the future costs a retry, never a new
  /// change that would make the wrist apply the deletion twice. Dropped with the
  /// ledger (D-114), except that an id the payload carries again — re-created
  /// under a reused number — supersedes its deletion and is released at once.
  final Map<String, Map<String, String>> _owed = {};

  /// How many deletion frames this push has minted a change id for. Part of the
  /// id rather than the whole of it, so two deletion events inside one
  /// millisecond are still two changes (F2).
  int _deleteSerial = 0;

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
        // One pass is bounded (D-98): the drain completes when the pass does or
        // when the timeout expires, so a hung send cannot wedge every later
        // push. A timed-out pass is reported, never thrown, never retried and
        // never queued — its baseline was already stored before the send, so
        // nothing is re-sent for the same payload (D-83). The abandoned pass is
        // not cancelled, so it may also report on its own later failure: a
        // second report for the one pass, with no other effect.
        await _pushOnce().timeout(
          _sendTimeout,
          onTimeout: () {
            _report(
              TimeoutException('push pass exceeded $_sendTimeout'),
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

  /// One pass: every pending session's end, decided by its own row, then the
  /// entries that vanished since the last pass, and then the composed payload
  /// when it differs from the baseline.
  ///
  /// The deletions go out **before** the snapshot of the same pass: an entry the
  /// phone re-created under a reused id must end up visible, and the snapshot
  /// that follows is what restores it (D-111, D-113).
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

      final ended = await _announceEnd(composedId);

      if (composed == null || composedId == null) return;

      // D-176: the mirror still holds the wrist's own session W, so the phone
      // is not in the session the wrist is: W is ended by name first (a foreign
      // snapshot would be refused while W is active), then P is asserted even
      // when it equals the baseline — a wrist holding W has no P yet — and the
      // request's answer is what moves the mirror onto P and clears the debt.
      // At most one reset per pass, never re-tried inside it (D-178).
      if (_mirror.owesResetFor(composedId)) {
        final held = _mirror.sessionId!;
        // The pass's own end for that very session is the reset's first frame
        // already: the discard that made it pending is the same news.
        if (!ended.contains(held)) {
          await _mirror.reportLifecycleFor(
            held,
            WatchLifecycleState.abandoned,
          );
        }
        await _mirror.sendState(composed);
        _baseline = _encode(composed);
        await _mirror.requestSnapshot();
      }

      await _announceDeletions(composedId, composed);
      final encoded = _encode(composed);
      if (encoded == _baseline) return;
      _baseline = encoded;
      await _mirror.sendState(composed);
    } on Exception catch (e, s) {
      // F4: a push that cannot be made must not disturb the phone — but it is
      // reported rather than swallowed (D-98, D-99).
      _report(e, s);
    }
  }

  /// Announces every entry id the wrist was expected to hold and should not any
  /// more, one `structure_change` frame each (D-110, D-111, S-120).
  ///
  /// `held` is what the wrist holds now: the ids the payload carries — the
  /// phone's own and the wrist's imported ones (D-112) — plus nothing else. The
  /// ids that were in the ledger and are not in `held` have vanished since the
  /// last pass, and each goes out as a `deleteEntryAs(sessionId, …)` naming
  /// [sessionId], in ascending id order so the frames are the same whichever
  /// store returned the rows in whichever order.
  ///
  /// Each id carries a change id minted once per deletion *event* (F2, D-116):
  /// `del-<entryId>-<stamp>-<n>`. The wrist drops a change id it has already
  /// applied, and it does so durably, so a fixed `del-<entryId>` would make it
  /// swallow the second deletion of a number the phone re-used. The stamp makes
  /// two events in two app runs differ, the serial two events inside one
  /// millisecond, and the event's own id is kept while its frame is owed.
  ///
  /// Every id that vanished stays in the ledger until its frame has gone (F7):
  /// a transport that fails the future for a send leaves the id owed, with the
  /// change id it was minted with, so a later pass announces it instead of
  /// losing the deletion for the rest of the app run. An id the payload carries
  /// again was re-created, which supersedes the deletion and releases it; the
  /// frames still go out in the order the ids sort in.
  ///
  /// The first pass for a session only seeds the ledger and announces nothing
  /// (S-123): nothing has vanished yet, and announcing the difference against an
  /// empty set would delete everything the wrist already held. A session the
  /// push composes nothing of is not a pass of its own — the caller does not
  /// call this at all, so a phone browsing a past session keeps its ledger.
  Future<void> _announceDeletions(
    String sessionId,
    Map<String, Object?> composed,
  ) async {
    final entries = composed['entries'];
    final held = <String>{
      if (entries is List)
        for (final entry in entries)
          if (entry is Map && entry['entryId'] is String)
            entry['entryId'] as String,
      ...await _heldWristEntryIds(sessionId),
    };

    final previous = _announced[sessionId] ?? const <String>{};
    final owed = _owed[sessionId] ??= <String, String>{};
    _owed.removeWhere((id, _) => id != sessionId);
    // Both ledgers belong to [sessionId] alone: a pass of another session drops
    // them, so a phone that leaves and comes back seeds again from what it holds
    // then instead of comparing against ids it announced before the switch
    // (D-114).
    _announced.removeWhere((id, _) => id != sessionId);
    // The ids belong to [sessionId] alone: the mirror's own session can differ
    // — a wrist that started its own workout — and applying the frame to it
    // would hide an entry of a session the frame does not name (F3).
    owed.removeWhere((entryId, _) => held.contains(entryId));

    final vanished = previous.difference(held).toList()..sort();
    for (final entryId in vanished) {
      owed.putIfAbsent(entryId, () => _deleteChangeId(entryId));
    }
    try {
      for (final entryId in vanished) {
        await _mirror.deleteEntryAs(
          sessionId,
          entryId,
          changeId: owed[entryId]!,
        );
        owed.remove(entryId);
      }
    } finally {
      // Whatever did not go out is still owed — and still expected by the
      // wrist — so the next pass sees it as vanished and announces it again.
      _announced[sessionId] = {...held, ...owed.keys};
    }
  }

  /// The change id of one deletion *event* (F2, D-116): the entry it names, the
  /// instant the event was first seen, and a serial so two events inside one
  /// millisecond are still two changes.
  String _deleteChangeId(String entryId) =>
      'del-$entryId-${_clock().millisecondsSinceEpoch}-${_deleteSerial++}';

  /// Hands [error] to the injected failure hook, when the graph gave one.
  void _report(Object error, StackTrace stack) => _onFailure?.call(error, stack);

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
    // D-99: whatever escapes a pass from the timer path — an `Error`, which
    // `_pushOnce` deliberately does not catch — is reported through the hook
    // rather than surfacing as an unhandled async error with no reporter. A
    // direct caller of `flush()` still sees it.
    _window = Timer(
      _debounce,
      () => unawaited(
        flush().catchError((Object e, StackTrace s) => _report(e, s)),
      ),
    );
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
  /// running is kept unless the phone has moved on to a different live session
  /// of its own — [currentId] — because a session the phone merely stopped
  /// composing while it runs is not an end (S-88).
  ///
  /// Returns the ids an end frame actually went out for, so the rest of the pass
  /// can tell its own end from a second one for the same session (D-176).
  Future<Set<String>> _announceEnd(String? currentId) async {
    if (_pendingEnds.isEmpty) return const <String>{};
    final announced = <String>{};
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
        // Still running: it stays pending unless the phone has moved on to a
        // different live session of its own. Composing nothing at all — the
        // user browsing a past session — is not moving on, so the end is kept
        // for whenever it comes (S-88).
        if (currentId != null && currentId != sessionId) {
          _pendingEnds.remove(sessionId);
        }
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
        announced.add(sessionId);
        continue;
      }
      if (held) {
        await _mirror.completeSession();
        announced.add(sessionId);
      } else {
        await _mirror.reportLifecycleFor(
          sessionId,
          WatchLifecycleState.completed,
        );
        announced.add(sessionId);
      }
    }
    return announced;
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
