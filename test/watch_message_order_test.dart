// The phone handles incoming frames one at a time, in arrival order, and
// ignores a stale session snapshot (plan 63, D-2 and D-3).
//
// Scenario mapping:
//   S-9301 two frames are handled one at a time, in arrival order
//                                                      → `S-9301 ...`
//   S-9302 a handler that throws does not stop the lane → `S-9302 ...`
//   S-9303 a handler that hangs is given up on after the timeout
//                                                      → `S-9303 ...`
//   S-9304 a frame is heard when it arrives, not when its turn comes
//                                                      → `S-9304 ...`
//   S-9305 a snapshot stamped earlier than the newest applied is ignored
//                                                      → `S-9305 ...`
//   S-9306 the stale rule's arms: equal applies, later applies, an
//          unparsable stamp is not stale                → `S-9306 ...`
//   S-9307 one newest stamp across workouts             → `S-9307 ...`

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/platform/watch_delivery.dart';
import 'package:omnitrain/core/platform/watch_link_info.dart';
import 'package:omnitrain/core/platform/watch_transport.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/state/watch/live_session_mirror_state.dart';
import 'package:omnitrain/watch/session/watch_records.dart';

import 'helpers/sync_protocol_harness.dart';

/// The instant the later snapshot of a pair is stamped. The earlier one is
/// 1 ms before it — not a whole second, so a rule that only compared seconds
/// could not pass these tests.
final DateTime _t2 = DateTime.utc(2026, 7, 13, 6, 30);
final DateTime _t1 = _t2.subtract(const Duration(milliseconds: 1));
final DateTime _t3 = _t2.add(const Duration(milliseconds: 1));

/// The channel the transport listens to, with only what these cases need: one
/// inbound stream the test emits on, and a link that is always up.
class _Channel implements WatchMessageChannel {
  final StreamController<Map<String, Object?>> inbound =
      StreamController<Map<String, Object?>>.broadcast();

  @override
  Future<bool> get isPaired async => true;

  @override
  Future<bool> get isReachable async => true;

  @override
  Stream<Map<String, Object?>> get messages => inbound.stream;

  @override
  Stream<bool> get reachability => const Stream<bool>.empty();

  @override
  Future<WatchLinkInfo> get info async => const WatchLinkInfo(
    paired: true,
    appInstalled: true,
    reachable: true,
  );

  @override
  Future<void> send(Map<String, Object?> frame) async {}

  @override
  Future<void> queue(Map<String, Object?> frame) async {}
}

/// A mirror with nobody on the other end: what it sends is recorded and
/// nothing comes back.
class _RecordingTransport implements WatchMirrorTransport {
  final List<Map<String, Object?>> sent = [];

  @override
  Future<WatchDelivery> send(Map<String, Object?> envelope) async {
    sent.add(envelope);
    return WatchDelivery.delivered;
  }

  @override
  Future<void> requestSnapshot() async {}
}

Map<String, Object?> _slot(String id) => {
  'sessionExerciseId': id,
  'exerciseId': 'ex-$id',
  'name': id,
  'capabilities': ['sets', 'reps', 'load'],
};

/// Two slots, so a snapshot naming position 1 is in range for the validator.
List<Map<String, Object?>> _ladder() => [_slot('sx-a'), _slot('sx-b')];

Map<String, Object?> _snapshotPayload({
  String sessionId = 's-live-1',
  String status = WatchSessionStatus.active,
  int revision = 0,
  int currentExerciseIndex = 0,
}) => {
  'sessionId': sessionId,
  'status': status,
  'revision': revision,
  'currentExerciseIndex': currentExerciseIndex,
  'exercises': _ladder(),
  'entries': const [],
  'timers': const {},
};

/// A watch-origin `session_snapshot` envelope with a controlled `sentAt`.
Map<String, Object?> _snapshot({
  required DateTime sentAt,
  String sessionId = 's-live-1',
  int revision = 0,
  int currentExerciseIndex = 0,
}) => {
  'protocolVersion': SyncProtocolValidator.protocolVersion,
  'messageId': 'msg-snapshot-$revision-$sessionId',
  'sessionId': sessionId,
  'type': 'session_snapshot',
  'origin': 'watch',
  'sentAt': isoUtc(sentAt),
  'payload': _snapshotPayload(
    sessionId: sessionId,
    revision: revision,
    currentExerciseIndex: currentExerciseIndex,
  ),
};

LiveSessionMirrorState _mirror() {
  final mirror = LiveSessionMirrorState(
    transport: _RecordingTransport(),
    snapshot: _snapshotPayload(),
    validator: loadProtocolValidator(),
  );
  return mirror;
}

void main() {
  group('S-9301 the phone handles two frames one at a time, in arrival order',
      () {
    test('S-9301 the second handler does not start until the first completes',
        () async {
      final channel = _Channel();
      final transport = WatchConnectivityTransport(channel: channel);
      addTearDown(transport.close);

      final firstStarted = Completer<void>();
      final secondStarted = Completer<void>();
      final firstGate = Completer<void>();
      final order = <String>[];

      transport.onIncoming((frame) async {
        if (frame['n'] == 1) {
          order.add('first-start');
          firstStarted.complete();
          await firstGate.future;
          order.add('first-end');
        } else {
          order.add('second-start');
          secondStarted.complete();
          order.add('second-end');
        }
      });

      channel.inbound.add(const {'type': 'session_snapshot', 'n': 1});
      channel.inbound.add(const {'type': 'session_snapshot', 'n': 2});
      await firstStarted.future;

      expect(
        secondStarted.isCompleted,
        isFalse,
        reason: 'the second handler must not start while the first is running',
      );

      firstGate.complete();
      await secondStarted.future;

      expect(order, ['first-start', 'first-end', 'second-start', 'second-end']);
    });
  });

  group('S-9302 a handler that throws does not stop the lane', () {
    test('S-9302 the second frame is still handled, the failure reported once',
        () async {
      final channel = _Channel();
      final failures = <Object>[];
      final transport = WatchConnectivityTransport(
        channel: channel,
        onFailure: (error, stack) => failures.add(error),
      );
      addTearDown(transport.close);

      final handled = <int>[];
      transport.onIncoming((frame) async {
        final n = frame['n']! as int;
        if (n == 1) throw StateError('the first handler failed');
        handled.add(n);
      });

      channel.inbound.add(const {'type': 'session_snapshot', 'n': 1});
      channel.inbound.add(const {'type': 'session_snapshot', 'n': 2});
      await pumpEventQueue();
      await pumpEventQueue();

      expect(handled, [2]);
      expect(failures, hasLength(1));
    });
  });

  group('S-9303 a handler that hangs is given up on after the timeout', () {
    test(
      'S-9303 with a 50 ms timeout the second handler starts within 500 ms '
      'and the TimeoutException is reported',
      () async {
        final channel = _Channel();
        final failures = <Object>[];
        final transport = WatchConnectivityTransport(
          channel: channel,
          onFailure: (error, stack) => failures.add(error),
          handlerTimeout: const Duration(milliseconds: 50),
        );
        addTearDown(transport.close);

        final secondStarted = Completer<void>();
        transport.onIncoming((frame) async {
          if (frame['n'] == 1) {
            // Never completes: the handler hangs for ever.
            await Completer<void>().future;
          } else {
            secondStarted.complete();
          }
        });

        final start = DateTime.now();
        channel.inbound.add(const {'type': 'session_snapshot', 'n': 1});
        channel.inbound.add(const {'type': 'session_snapshot', 'n': 2});

        await secondStarted.future.timeout(const Duration(milliseconds: 500));
        final elapsed = DateTime.now().difference(start);

        expect(elapsed, lessThan(const Duration(seconds: 5)));
        expect(failures.whereType<TimeoutException>(), isNotEmpty);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });

  group('S-9304 a frame is heard when it arrives, not when its turn comes', () {
    test('S-9304 both frames are heard before the first handler completes',
        () async {
      final channel = _Channel();
      final stamps = <DateTime>[
        DateTime.utc(2026, 7, 13, 6),
        DateTime.utc(2026, 7, 13, 6, 0, 1),
      ];
      var clockIndex = 0;
      final transport = WatchConnectivityTransport(
        channel: channel,
        clock: () => stamps[clockIndex++],
      );
      addTearDown(transport.close);

      final heard = <DateTime>[];
      transport.heard.listen(heard.add);

      final firstGate = Completer<void>();
      transport.onIncoming((frame) async {
        if (frame['n'] == 1) await firstGate.future;
      });

      channel.inbound.add(const {'type': 'session_snapshot', 'n': 1});
      channel.inbound.add(const {'type': 'session_snapshot', 'n': 2});
      await pumpEventQueue();
      await pumpEventQueue();
      expect(
        heard,
        stamps,
        reason: 'both frames were heard while the first handler was suspended',
      );

      firstGate.complete();
      await pumpEventQueue();
      expect(heard, stamps, reason: 'hearing is not re-reported later');
    });
  });

  group('S-9305 a snapshot stamped earlier than the newest applied is ignored',
      () {
    test('S-9305 the state stays at the newer snapshot, nothing is notified',
        () async {
      final mirror = _mirror();
      var notifications = 0;
      mirror.addListener(() => notifications++);

      final newer = _snapshot(
        sentAt: _t2,
        revision: 5,
        currentExerciseIndex: 1,
      );
      final older = _snapshot(
        sentAt: _t1,
        revision: 4,
        currentExerciseIndex: 0,
      );

      final firstOutcome = await mirror.receive(newer);
      expect(firstOutcome, MirrorOutcome.applied);
      expect(mirror.currentExerciseIndex, 1);

      final secondOutcome = await mirror.receive(older);
      expect(secondOutcome, MirrorOutcome.ignored);
      expect(
        mirror.currentExerciseIndex,
        1,
        reason: 'the older snapshot changed nothing',
      );
      expect(mirror.state['revision'], 5);
      expect(
        notifications,
        1,
        reason: 'the ignored snapshot never notified a listener',
      );
    });
  });

  group('S-9306 the stale rule, one test per arm', () {
    test('S-9306a a snapshot stamped the same instant as the newest applies',
        () async {
      final mirror = _mirror();
      final first = _snapshot(sentAt: _t2, revision: 5, currentExerciseIndex: 1);
      final equal = _snapshot(
        sentAt: _t2,
        revision: 6,
        currentExerciseIndex: 0,
      );

      expect(await mirror.receive(first), MirrorOutcome.applied);
      expect(await mirror.receive(equal), MirrorOutcome.applied);
      expect(mirror.currentExerciseIndex, 0);
      expect(mirror.state['revision'], 6);
    });

    test('S-9306b a snapshot stamped later than the newest applies', () async {
      final mirror = _mirror();
      final first = _snapshot(sentAt: _t2, revision: 5, currentExerciseIndex: 1);
      final later = _snapshot(
        sentAt: _t3,
        revision: 6,
        currentExerciseIndex: 0,
      );

      expect(await mirror.receive(first), MirrorOutcome.applied);
      expect(await mirror.receive(later), MirrorOutcome.applied);
      expect(mirror.currentExerciseIndex, 0);
    });

    test('S-9306c a snapshot with no parsable sentAt is not called stale',
        () async {
      final mirror = _mirror();
      // The stale rule only has arms once the mirror holds a newest stamp:
      // apply one real snapshot first, so the guards below are the ones judged.
      expect(
        await mirror.receive(
          _snapshot(sentAt: _t2, revision: 5, currentExerciseIndex: 1),
        ),
        MirrorOutcome.applied,
      );
      // The guard is live here: a genuinely older stamp is stale.
      expect(mirror.isStaleSnapshot(_snapshot(sentAt: _t1)), isTrue);
      expect(
        mirror.isStaleSnapshot({
          'type': 'session_snapshot',
          'sentAt': 'not-a-date',
        }),
        isFalse,
      );
      expect(
        mirror.isStaleSnapshot({
          'type': 'session_snapshot',
          'sentAt': 42,
        }),
        isFalse,
      );
      expect(mirror.isStaleSnapshot({'type': 'session_snapshot'}), isFalse);
      expect(
        mirror.isStaleSnapshot({
          'type': 'timer_state',
          'sentAt': _t1.toIso8601String(),
        }),
        isFalse,
        reason: 'only a session_snapshot is judged for staleness',
      );
    });
  });

  group('S-9307 one newest stamp across workouts', () {
    test('S-9307 an older snapshot of an earlier workout is ignored', () async {
      final mirror = _mirror();

      final newerWorkout = _snapshot(
        sentAt: _t2,
        sessionId: 's-b',
        revision: 5,
      );
      final olderWorkout = _snapshot(
        sentAt: _t1,
        sessionId: 's-a',
        revision: 4,
      );

      expect(await mirror.receive(newerWorkout), MirrorOutcome.applied);
      expect(mirror.sessionId, 's-b');

      expect(await mirror.receive(olderWorkout), MirrorOutcome.ignored);
      expect(
        mirror.sessionId,
        's-b',
        reason: 'the mirror still holds the newer workout',
      );
    });
  });
}
