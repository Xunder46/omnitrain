/// The wrist's radio on Wear OS: `WatchLink` behind `WatchSyncTransport`.
///
/// Plan: `docs/plans/2026-11-20-280-wear-os-shell-plan/2026-11-20-280-wear-os-shell-plan.md`
/// (D-28006). The Dart counterpart of the Swift `WatchConnectivityBridge` for the
/// part the Wear data layer needs:
///
/// 1. **Reachability is the platform's answer, re-read rather than guessed.** A
///    frame leaves when the orchestrator syncs, and the orchestrator asks whether
///    the phone is there; a send the radio refuses reports the real reason.
/// 2. **Arrivals are handled one at a time, in arrival order**, so the engine's
///    state changes in the order the phone sent it.
/// 3. **A durable frame the radio cannot carry is queued**, and only what the
///    protocol owes for good is durable: a logged observation, a lifecycle
///    message, a session start, and the snapshot of a workout that is still
///    running. A timer, a request and an ended workout's snapshot are live state
///    that would arrive wrong, so they are reported and dropped, and the next
///    sync re-sends what is owed from storage.
///
/// 4. **Only the newest copy of a workout waits** (plan 294, the Apple bridge's
///    plan 69 D-3…D-8): a snapshot replaces the session's queued snapshots, a
///    lifecycle replaces its queued non-terminal lifecycles, and a terminal
///    lifecycle (`completed`, `abandoned`) replaces both and is never stale. A
///    queued copy stamped later than the frame wins and the frame is not queued.
///    A logged observation is never withdrawn. Listing, withdrawing and queuing
///    run one at a time.
library;

import 'dart:async';

import 'package:omnitrain_watch_link/omnitrain_watch_link.dart';

import '../../core/platform/watch_frame_wire.dart';
import '../../core/platform/watch_request_frames.dart';
import '../../core/services/diagnostics_log.dart';
import '../diagnostics/watch_diagnostics_send_outcome.dart';
import '../start/watch_sync_orchestrator.dart';

/// What the wrist app hands arriving frames to.
typedef WearInboundHandler = Future<void> Function(Map<String, Object?> frame);

class WearWatchTransport implements WatchSyncTransport {
  WearWatchTransport({
    WatchLink? link,
    void Function(Object error, StackTrace stack)? onFailure,
    Duration sendTimeout = const Duration(seconds: 5),
    DiagnosticsLog? diagnostics,
    Duration diagnosticsSendTimeout = const Duration(seconds: 10),
  }) : _link = link ?? WatchLink(),
       _onFailure = onFailure,
       _sendTimeout = sendTimeout,
       _diagnostics = diagnostics,
       _diagnosticsSendTimeout = diagnosticsSendTimeout;

  final WatchLink _link;

  /// The wrist's diagnostics log, when the app keeps one (plan 293): every frame
  /// sent or received leaves one line. Never a payload value: the frame's name,
  /// the session it names, an outcome word and an error's type.
  final DiagnosticsLog? _diagnostics;
  final void Function(Object error, StackTrace stack)? _onFailure;

  /// How long a live send may wait for the platform. The protocol recovers what
  /// a timeout drops, so the wrist never waits on a radio longer than this.
  final Duration _sendTimeout;

  StreamSubscription<WatchLinkEvent>? _events;

  /// Frames are handed over one at a time; this is the turn of the frame being
  /// handled, and the next frame's turn chains after it.
  Future<void> _lane = Future<void>.value();

  bool _reachable = false;

  /// The end of the last list-withdraw-queue step: the next step starts after
  /// it, so two hand-overs at once cannot both keep a copy (plan 294 D-29404).
  Future<void> _queueTail = Future<void>.value();
  WearInboundHandler? _inbound;

  /// The frames the wrist may hand the OS to deliver later (the Swift
  /// `WatchConnectivityBridge.isDurable` table, plan 69 D-2).
  static const Set<String> durableTypes = {
    'observations_up',
    'session_lifecycle',
    'session_started',
  };

  /// Whether the frame may wait in the OS queue when the radio refuses it.
  static bool isDurable(Map<String, Object?> frame) {
    final type = frame['type'];
    if (type is! String) return false;
    if (durableTypes.contains(type)) return true;
    if (type != 'session_snapshot') return false;
    final payload = frame['payload'];
    return payload is Map && payload['status'] == 'active';
  }

  @override
  bool get isPhoneReachable => _reachable;

  /// Whether the wrist holds a bests frame, read on every routines request so
  /// the phone can skip a frame that has not changed (series 87c). Null means
  /// "no": the key is then left off, as it is for a wrist that holds nothing.
  bool Function()? holdsBests;

  /// Whether the wrist hosts the water bar and so asks for the day's water on
  /// every routines request (plan 94 D-9, plan 290). False leaves the key off:
  /// a wrist without a bar sends the same frame it always sent.
  bool wantsWater = false;

  /// Hands every arriving frame to [handler]. Frames that arrive before this is
  /// called wait in the platform's buffer and are flushed to it.
  void onIncoming(WearInboundHandler handler) => _inbound = handler;

  /// Starts listening, then reads the pairing once.
  ///
  /// Listening comes first: the platform withholds its event stream until the
  /// first listener attaches and then flushes what it buffered, so a frame that
  /// arrived during launch is waiting for this subscription.
  Future<void> start() async {
    _events ??= _link.events.listen(_onEvent, onError: _report);
    await refreshReachability();
  }

  Future<void> close() async {
    await _events?.cancel();
    _events = null;
  }

  /// Re-reads whether the phone can be reached. Cheap, and never throws.
  Future<void> refreshReachability() async {
    try {
      final status = await _link.status();
      _reachable = status.reachable;
    } on Object catch (error, stack) {
      _report(error, stack);
    }
  }

  void _onEvent(WatchLinkEvent event) {
    switch (event) {
      case WatchLinkMessage(:final frame):
      case WatchLinkUserInfo(:final frame):
        deliver(frame);
      case WatchLinkReachability(:final reachable):
        _reachable = reachable;
      case WatchLinkStateChanged(:final status):
        _reachable = status.reachable;
    }
  }

  /// Hands [frame] to the inbound handler the way an arrival does, in the same
  /// one-at-a-time lane.
  ///
  /// The event channel's own path is the one that runs on a watch; this entry
  /// point exists so a widget test can drive the shell without a platform
  /// stream (which `testWidgets`' fake clock delivers only after the test ends),
  /// and so a future non-Wear socket has one place to hand frames in.
  Future<void> deliver(Map<String, Object?> frame) {
    final turn = _lane.then((_) => _deliver(frame));
    // A frame that fails is reported by `_deliver`; the lane itself must never
    // stay broken, or every later arrival would be skipped.
    _lane = turn.catchError((Object _) {});
    return turn;
  }

  Future<void> _deliver(Map<String, Object?> frame) async {
    final handler = _inbound;
    if (handler == null) return;
    try {
      _diagnostics?.note(
        'frame_received',
        session: _sessionOf(frame),
        detail: _nameOf(frame),
      );
      await handler(frame);
    } on Object catch (error, stack) {
      _diagnostics?.note(
        'frame_handler_failed',
        session: _sessionOf(frame),
        detail: '${_nameOf(frame)} ${error.runtimeType}',
      );
      _report(error, stack);
    }
  }

  @override
  Future<void> requestRoutines({DateTime? since}) => send(
    WatchTransportRequest.routinesFrame(
      since: since,
      holdsBests: holdsBests?.call() ?? false,
      wantsWater: wantsWater,
    ),
  );

  @override
  Future<void> requestSnapshot() => send(WatchTransportRequest.snapshotFrame());

  /// How long a diagnostics send may wait for the platform before it is
  /// reported as failed (plan 304).
  final Duration _diagnosticsSendTimeout;

  /// Hands the phone the wrist's diagnostics [text] (plan 304). Never a sync
  /// frame: the platform carries it on its own path, so it cannot change what
  /// syncs. An empty [text] sends nothing. The outcome is one line in the log
  /// (the outcome word only, never the text).
  Future<WatchDiagnosticsSendOutcome> sendDiagnostics(String text) async {
    if (text.isEmpty) return WatchDiagnosticsSendOutcome.nothingToSend;
    WatchDiagnosticsSendOutcome outcome;
    try {
      await _link.sendDiagnostics(text).timeout(_diagnosticsSendTimeout);
      outcome = WatchDiagnosticsSendOutcome.sent;
    } on WatchLinkException catch (error) {
      outcome = switch (error.code) {
        'not_supported' => WatchDiagnosticsSendOutcome.notReady,
        'phone_app_missing' => WatchDiagnosticsSendOutcome.phoneAppMissing,
        _ => WatchDiagnosticsSendOutcome.failed,
      };
    } on Object {
      outcome = WatchDiagnosticsSendOutcome.failed;
    }
    _diagnostics?.note('diagnostics_send', detail: outcome.name);
    return outcome;
  }

  /// Hands the phone one frame the wrist owes it.
  ///
  /// The frame is made radio-safe first (the 2026-11-19 null-in-timers fix), so
  /// both platforms send the same shape. A refusal on a durable frame goes to the
  /// OS queue, after the copies it replaces are withdrawn; anything else is
  /// reported, and the next sync re-sends what the protocol still owes. A
  /// snapshot or lifecycle that went out live withdraws the older copies still
  /// waiting (plan 294 D-29404).
  @override
  Future<void> send(Map<String, Object?> envelope) async {
    final frame = wireSafeFrame(envelope);
    try {
      await _link.sendMessage(frame, timeout: _sendTimeout);
      _noteSent(frame, 'live');
    } on WatchLinkException catch (error) {
      if (!isDurable(frame)) {
        _noteNotSent(frame, error);
        _report(error, StackTrace.current);
        return;
      }
      await _inQueueLane(() => _queueNewest(frame));
      return;
    }
    if (isDurable(frame)) {
      await _inQueueLane(() => _withdrawSuperseded(frame));
    }
  }

  /// Runs [step] after the previous list-withdraw-queue step finished, whether
  /// that one succeeded or threw.
  Future<T> _inQueueLane<T>(Future<T> Function() step) {
    final turn = _queueTail.then((_) => step());
    _queueTail = turn.then<void>((_) {}, onError: (Object _) {});
    return turn;
  }

  /// Queues a frame the radio refused, after withdrawing the waiting copies it
  /// replaces. A waiting copy with a LATER stamp is newer than the frame: the
  /// frame is then not queued and nothing is withdrawn (not a failure). A
  /// non-snapshot that already waits under its own `messageId` is not queued
  /// again; a snapshot's id does not change with its content, so it is
  /// replaced like any other.
  Future<void> _queueNewest(Map<String, Object?> frame) async {
    final held = await _heldTransfers();
    final own = frame['messageId'];
    if (frame['type'] != 'session_snapshot' &&
        own is String &&
        held.any((transfer) => transfer.messageId == own)) {
      _noteSent(frame, 'queued');
      return;
    }
    final found = _superseded(frame, held);
    if (found.newerExists) {
      _noteSent(frame, 'superseded');
      return;
    }
    if (found.olderIds.isNotEmpty) await _cancelTransfers(found.olderIds);
    try {
      await _link.transferUserInfo(frame);
      _noteSent(frame, 'queued');
    } on WatchLinkException catch (queueError) {
      _noteNotSent(frame, queueError);
      _report(queueError, StackTrace.current);
    }
  }

  /// After a frame went out live: cancels the waiting copies it replaces, never
  /// a newer one.
  Future<void> _withdrawSuperseded(Map<String, Object?> frame) async {
    final type = frame['type'];
    if (type != 'session_snapshot' && type != 'session_lifecycle') return;
    final found = _superseded(frame, await _heldTransfers());
    if (found.olderIds.isNotEmpty) await _cancelTransfers(found.olderIds);
  }

  /// The transfers this device's queue still holds. A list that fails is
  /// reported and read as empty: the queue call still runs (plan 294 D-29405).
  Future<List<WatchLinkTransfer>> _heldTransfers() async {
    try {
      return await _link.outstandingTransfers();
    } on Object catch (error, stack) {
      _report(error, stack);
      return const <WatchLinkTransfer>[];
    }
  }

  /// Cancels the waiting copies [ids]; a failure is reported, never thrown.
  Future<void> _cancelTransfers(List<String> ids) async {
    try {
      await _link.cancelTransfers(ids);
    } on Object catch (error, stack) {
      _report(error, stack);
    }
  }

  static const Set<String> _terminalStates = {'completed', 'abandoned'};

  /// An unreadable stamp counts as oldest on a waiting copy and as newest on
  /// the frame (plan 294 D-29402).
  static final DateTime _oldest = DateTime.fromMillisecondsSinceEpoch(
    0,
    isUtc: true,
  );
  static final DateTime _newest = DateTime.utc(9999);

  static DateTime? _stamp(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  static bool _isTerminalState(Object? state) =>
      state is String && _terminalStates.contains(state);

  /// The waiting copies [frame] replaces (older or equal stamp), and whether a
  /// copy it would replace is newer than the frame (then the frame is stale).
  /// A snapshot replaces the snapshots of its session; a non-terminal lifecycle
  /// the non-terminal lifecycles of its session; a terminal lifecycle both of
  /// those, and is never stale. A logged observation, a terminal lifecycle and
  /// another session's frame are never replaced; a copy with no type is never
  /// touched.
  ({List<String> olderIds, bool newerExists}) _superseded(
    Map<String, Object?> frame,
    List<WatchLinkTransfer> held,
  ) {
    final olderIds = <String>[];
    var newerExists = false;
    final type = frame['type'];
    final sessionId = frame['sessionId'];
    if ((type != 'session_snapshot' && type != 'session_lifecycle') ||
        sessionId is! String) {
      return (olderIds: olderIds, newerExists: false);
    }
    final payload = frame['payload'];
    final terminal =
        type == 'session_lifecycle' &&
        _isTerminalState(payload is Map ? payload['state'] : null);
    final own = frame['messageId'];
    final sent = _stamp(frame['sentAt']) ?? _newest;
    for (final copy in held) {
      if (copy.sessionId != sessionId || copy.type.isEmpty) continue;
      final bool replaced;
      if (type == 'session_snapshot') {
        replaced = copy.type == 'session_snapshot';
      } else if (copy.type == 'session_snapshot') {
        replaced = terminal;
      } else {
        replaced =
            copy.type == 'session_lifecycle' && !_isTerminalState(copy.state);
      }
      if (!replaced) continue;
      if (copy.messageId == own && type != 'session_snapshot') continue;
      if (!terminal && (_stamp(copy.sentAt) ?? _oldest).isAfter(sent)) {
        newerExists = true;
      } else {
        olderIds.add(copy.messageId);
      }
    }
    return (olderIds: olderIds, newerExists: newerExists);
  }

  /// The name a frame goes by in the log: its `type`, else its request name,
  /// else `unknown`.
  static String _nameOf(Map<String, Object?> frame) {
    final type = frame['type'];
    if (type is String && type.isNotEmpty) return type;
    return WatchTransportRequest.nameOf(frame) ?? 'unknown';
  }

  static String? _sessionOf(Map<String, Object?> frame) {
    final session = frame['sessionId'];
    return session is String && session.isNotEmpty ? session : null;
  }

  /// The types the log coalesces to one line a minute when sent live, as the
  /// Apple bridge's `chattyTypes` does (plan 305, D-30508): a live reading every
  /// few seconds would push everything else out of the 3000-line log. The phone
  /// never sends the wrist such a frame, so receiving is not coalesced.
  static const Set<String> chattyTypes = {'energy_live'};

  void _noteSent(Map<String, Object?> frame, String outcome) {
    final name = _nameOf(frame);
    _diagnostics?.note(
      'frame_sent',
      session: _sessionOf(frame),
      detail: '$name $outcome',
      coalesce: outcome == 'live' && chattyTypes.contains(name)
          ? 'frame_sent/$name'
          : null,
    );
  }

  void _noteNotSent(Map<String, Object?> frame, Object error) =>
      _diagnostics?.note(
        'frame_not_sent',
        session: _sessionOf(frame),
        detail: '${_nameOf(frame)} ${error.runtimeType}',
      );

  void _report(Object error, StackTrace stack) =>
      _onFailure?.call(error, stack);
}
