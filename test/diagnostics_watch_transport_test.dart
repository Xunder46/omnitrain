// The diagnostics hooks in the phone's watch transport (plan 143, D-14303).
//
// The transport is observed, not driven: every scenario runs the loopback
// harness of `test/watch_transport_test.dart` with a `DiagnosticsLog` over
// `InMemoryDiagnosticsStorage`, and asserts on what the log recorded — while
// the deliveries, the frames the endpoint saw and the handler calls stay
// exactly what they were before the hooks existed (S-14313).

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/platform/watch_delivery.dart';
import 'package:omnitrain/core/platform/watch_link_info.dart';
import 'package:omnitrain/core/platform/watch_queue_control.dart';
import 'package:omnitrain/core/platform/watch_transport.dart';
import 'package:omnitrain/core/services/diagnostics_log.dart';
import 'package:omnitrain/core/services/diagnostics_storage.dart';

final DateTime _start = DateTime.utc(2026, 11, 10, 12);

Map<String, Object?> _timer(String id) =>
    {'type': 'timer_state', 'messageId': id, 'sessionId': 's-1'};

Map<String, Object?> _receipt(String id) =>
    {'type': 'receipt', 'messageId': id, 'sessionId': 's-1'};

Map<String, Object?> _snap(String id) =>
    {'type': 'session_snapshot', 'messageId': id, 'sessionId': 's-1'};

Map<String, Object?> _energy(String id) =>
    {'type': 'energy_live', 'messageId': id, 'sessionId': 's-1'};

WatchQueuedTransfer _transferOf(Map<String, Object?> frame) {
  final payload = frame['payload'];
  final changeId = payload is Map ? payload['changeId'] : null;
  return WatchQueuedTransfer(
    messageId: frame['messageId'] is String ? frame['messageId'] as String : '',
    type: frame['type'] is String ? frame['type'] as String : '',
    sessionId: frame['sessionId'] is String ? frame['sessionId'] as String : null,
    changeId: changeId is String ? changeId : null,
  );
}

/// One end of a two-ended in-memory link, as `test/watch_transport_test.dart`
/// builds it. What this end sends appears on the other end's stream, in order.
class _Endpoint implements WatchMessageChannel, WatchQueueControl {
  _Endpoint({required this.outbound, required this.inbound});

  final StreamController<Map<String, Object?>> outbound;

  /// The frames arriving at this end.
  final StreamController<Map<String, Object?>> inbound;

  /// Everything this end handed to the radio, in order.
  final List<Map<String, Object?>> sent = [];

  /// Everything this end handed to the OS queue, in order.
  final List<Map<String, Object?>> queued = [];

  bool reachable = true;

  /// A send the radio refuses. Null means every send is taken.
  Object? sendFailure;

  /// A queue the OS refuses. Null means every queue call is taken.
  Object? queueFailure;

  /// A reachability read that throws. Null means the read is answered.
  Object? reachFailure;

  /// The transfers the OS still holds, as the native link would list them.
  final List<WatchQueuedTransfer> outstanding = [];

  /// The ids of every cancel call, in order.
  final List<List<String>> cancels = [];

  @override
  Future<void> queue(Map<String, Object?> frame) async {
    final failure = queueFailure;
    if (failure != null) throw failure;
    queued.add(frame);
    final id = frame['messageId'];
    if (id is String && outstanding.any((held) => held.messageId == id)) return;
    outstanding.add(_transferOf(frame));
  }

  @override
  Future<List<WatchQueuedTransfer>> outstandingTransfers() async =>
      List<WatchQueuedTransfer>.of(outstanding);

  @override
  Future<int> cancelTransfers(List<String> messageIds) async {
    cancels.add(List<String>.of(messageIds));
    final before = outstanding.length;
    outstanding.removeWhere((held) => messageIds.contains(held.messageId));
    return before - outstanding.length;
  }

  WatchLinkInfo infoValue = const WatchLinkInfo(
    paired: true,
    appInstalled: true,
    reachable: true,
  );

  @override
  Future<bool> get isPaired async => true;

  @override
  Future<bool> get isReachable async {
    final failure = reachFailure;
    if (failure != null) throw failure;
    return reachable;
  }

  @override
  Stream<Map<String, Object?>> get messages => inbound.stream;

  @override
  Stream<bool> get reachability => reachabilityController.stream;

  final StreamController<bool> reachabilityController =
      StreamController<bool>.broadcast();

  @override
  Future<WatchLinkInfo> get info async => infoValue;

  @override
  Future<void> send(Map<String, Object?> frame) async {
    final failure = sendFailure;
    if (failure != null) throw failure;
    sent.add(frame);
    outbound.add(frame);
  }
}

/// Two channels wired to each other: the phone's and the wrist's.
class _Link {
  _Link() {
    phone = _Endpoint(outbound: _toWatch, inbound: _toPhone);
    watch = _Endpoint(outbound: _toPhone, inbound: _toWatch);
  }

  final StreamController<Map<String, Object?>> _toPhone =
      StreamController<Map<String, Object?>>.broadcast();
  final StreamController<Map<String, Object?>> _toWatch =
      StreamController<Map<String, Object?>>.broadcast();

  late final _Endpoint phone;
  late final _Endpoint watch;

  Future<void> close() async {
    await _toPhone.close();
    await _toWatch.close();
  }
}

/// One endpoint on its own, for cases that push frames in by hand.
class _Sandbox {
  final StreamController<Map<String, Object?>> inbound =
      StreamController<Map<String, Object?>>.broadcast();
  final StreamController<Map<String, Object?>> outbound =
      StreamController<Map<String, Object?>>.broadcast();

  late final _Endpoint endpoint = _Endpoint(outbound: outbound, inbound: inbound);

  Future<void> dispose() async {
    await inbound.close();
    await outbound.close();
  }
}

/// Lets the link's broadcast streams deliver everything already queued.
Future<void> _settle() => pumpEventQueue();

/// A storage that fails everything, as a broken file system would.
class _ThrowingStorage implements DiagnosticsStorage {
  @override
  String read() => throw StateError('rating 97531');

  @override
  bool append(String text) => throw StateError('rating 97531');

  @override
  bool replace(String text) => throw StateError('rating 97531');
}

/// What the S-14313 fixtures produced: what the caller was told, what the
/// endpoint saw and what the handlers took.
class _FixtureRecord {
  _FixtureRecord(this.deliveries, this.sent, this.queued, this.handled, this.failures);

  final List<WatchDelivery> deliveries;
  final List<Map<String, Object?>> sent;
  final List<Map<String, Object?>> queued;
  final List<String> handled;
  final List<String> failures;
}

/// The S-14309 send fixtures and the S-14311 handler fixtures, over one link
/// and two sandboxes, with whatever log the caller handed in.
Future<_FixtureRecord> _runObservationFixtures(DiagnosticsLog? diagnostics) async {
  final link = _Link();
  final failures = <String>[];
  final transport = WatchConnectivityTransport(
    channel: link.phone,
    diagnostics: diagnostics,
    onFailure: (error, stack) => failures.add(error.runtimeType.toString()),
  );
  final handled = <String>[];
  transport.onIncoming((frame) async {
    final type = frame['type'];
    handled.add(type is String ? type : 'unknown');
  });

  final deliveries = <WatchDelivery>[];
  deliveries.add(await transport.send(_timer('m1')));
  link.phone.reachable = false;
  deliveries.add(await transport.send(_receipt('r1')));
  deliveries.add(await transport.send(_timer('m2')));
  link.phone.reachable = true;
  link.phone.sendFailure = StateError('rating 97531');
  deliveries.add(await transport.send(_snap('m3')));
  deliveries.add(await transport.send(_timer('m4')));
  link.phone.sendFailure = null;
  link.phone.reachable = false;
  link.phone.queueFailure = StateError('rating 97531');
  deliveries.add(await transport.send(_receipt('r2')));

  await link.watch.send(_timer('w1'));
  await _settle();

  final throwing = _Sandbox();
  final throwingFailures = <String>[];
  final throwingTransport = WatchConnectivityTransport(
    channel: throwing.endpoint,
    diagnostics: diagnostics,
    onFailure: (error, stack) => throwingFailures.add(error.runtimeType.toString()),
  );
  throwingTransport.onIncoming((frame) async {
    throw StateError('rating 97531');
  });
  throwing.inbound.add(_timer('w2'));
  await _settle();
  handled.add('throwing:${throwingFailures.length}');

  await transport.close();
  await throwingTransport.close();
  await throwing.dispose();
  await link.close();

  return _FixtureRecord(
    deliveries,
    List<Map<String, Object?>>.of(link.phone.sent),
    List<Map<String, Object?>>.of(link.phone.queued),
    List<String>.of(handled),
    List<String>.of(failures),
  );
}

void main() {
  group('the transport notes the link (plan 143, D-14303)', () {
    test('S-14309 every send outcome is noted, and never the error message',
        () async {
      var now = _start;
      final log = DiagnosticsLog(
        storage: InMemoryDiagnosticsStorage(),
        clock: () => now,
      );
      final link = _Link();
      final transport = WatchConnectivityTransport(
        channel: link.phone,
        diagnostics: log,
      );
      addTearDown(transport.close);
      addTearDown(link.close);

      expect(await transport.send(_timer('m1')), WatchDelivery.delivered);
      link.phone.reachable = false;
      expect(await transport.send(_receipt('r1')), WatchDelivery.queued);
      expect(await transport.send(_timer('m2')), WatchDelivery.undelivered);
      link.phone.reachable = true;
      link.phone.sendFailure = StateError('rating 97531');
      expect(await transport.send(_snap('m3')), WatchDelivery.queued);
      expect(await transport.send(_timer('m4')), WatchDelivery.undelivered);
      link.phone.sendFailure = null;
      link.phone.reachable = false;
      link.phone.queueFailure = StateError('rating 97531');
      expect(await transport.send(_receipt('r2')), WatchDelivery.undelivered);

      final sent = [
        for (final event in log.events())
          if (event.kind == 'frame_sent') event,
      ];
      expect(
        sent.map((event) => event.detail),
        [
          'timer_state delivered',
          'receipt queued',
          'timer_state undelivered',
          'session_snapshot failed: StateError',
          'session_snapshot queued',
          'timer_state failed: StateError',
          'receipt failed: StateError',
        ],
      );
      expect(
        sent.map((event) => event.session),
        List<String>.filled(sent.length, 's-1'),
      );
      expect(log.shareText(), isNot(contains('97531')));
    });

    test('S-14310 a failed energy_live send is never coalesced', () async {
      final log = DiagnosticsLog(
        storage: InMemoryDiagnosticsStorage(),
        clock: () => _start,
      );
      final link = _Link();
      final transport = WatchConnectivityTransport(
        channel: link.phone,
        diagnostics: log,
      );
      addTearDown(transport.close);
      addTearDown(link.close);
      link.phone.sendFailure = StateError('radio');

      await transport.send(_energy('e1'));
      await transport.send(_energy('e2'));

      expect(
        [
          for (final event in log.events())
            if (event.kind == 'frame_sent') event.detail,
        ],
        ['energy_live failed: StateError', 'energy_live failed: StateError'],
        reason: 'only an ordinary delivery is coalesced; every failure counts',
      );
    });

    test('S-14310 energy_live sent and received is one line a minute',
        () async {
      var now = _start;
      final log = DiagnosticsLog(
        storage: InMemoryDiagnosticsStorage(),
        clock: () => now,
      );
      final link = _Link();
      final transport = WatchConnectivityTransport(
        channel: link.phone,
        diagnostics: log,
      );
      addTearDown(transport.close);
      addTearDown(link.close);
      var handled = 0;
      transport.onIncoming((frame) async => handled++);

      for (var index = 1; index <= 30; index++) {
        expect(
          await transport.send(_energy('e$index')),
          WatchDelivery.delivered,
        );
        now = now.add(const Duration(milliseconds: 500));
      }
      now = now.add(const Duration(seconds: 61));
      expect(await transport.send(_energy('e31')), WatchDelivery.delivered);

      final sent = [
        for (final event in log.events())
          if (event.kind == 'frame_sent') event,
      ];
      expect(sent.map((event) => event.detail), [
        'energy_live delivered x1',
        'energy_live delivered x30',
      ]);

      for (var index = 1; index <= 30; index++) {
        await link.watch.send(_energy('w$index'));
        await _settle();
        now = now.add(const Duration(milliseconds: 500));
      }
      now = now.add(const Duration(seconds: 61));
      await link.watch.send(_energy('w31'));
      await _settle();

      final received = [
        for (final event in log.events())
          if (event.kind == 'frame_received') event,
      ];
      expect(received.map((event) => event.detail), [
        'energy_live x1',
        'energy_live x30',
      ]);
      expect(handled, 31);
    });

    test('S-14311 an arriving frame is noted received, failed or timed out',
        () async {
      var now = _start;
      final log = DiagnosticsLog(
        storage: InMemoryDiagnosticsStorage(),
        clock: () => now,
      );
      final link = _Link();
      final transport = WatchConnectivityTransport(
        channel: link.phone,
        diagnostics: log,
      );
      addTearDown(transport.close);
      addTearDown(link.close);

      // The handler reads the log at its own entry, so the assertion is about
      // order: the note must already be there when the handler runs.
      final atEntry = <String?>[];
      var handled = 0;
      transport.onIncoming((frame) async {
        final received = [
          for (final event in log.events())
            if (event.kind == 'frame_received') event,
        ];
        atEntry.add(received.isEmpty ? null : received.last.detail);
        handled++;
      });

      await link.watch.send(_timer('m1'));
      await _settle();
      expect(handled, 1);
      expect(atEntry, ['timer_state'],
          reason: 'frame_received is noted before the handler runs');

      // A handler that throws: the failure is named, its message never is.
      final throwing = _Sandbox();
      addTearDown(throwing.dispose);
      final reported = <Object>[];
      final throwingTransport = WatchConnectivityTransport(
        channel: throwing.endpoint,
        diagnostics: log,
        onFailure: (error, stack) => reported.add(error),
      );
      addTearDown(throwingTransport.close);
      throwingTransport.onIncoming((frame) async {
        throw StateError('rating 97531');
      });
      throwing.inbound.add(_timer('m3'));
      await _settle();
      expect(reported.single, isA<StateError>());
      expect(
        [
          for (final event in log.events())
            if (event.kind == 'frame_handler_failed') event.detail,
        ],
        contains('timer_state StateError'),
      );
      expect(log.shareText(), isNot(contains('97531')));

      // A handler that never finishes within its timeout.
      final hanging = _Sandbox();
      addTearDown(hanging.dispose);
      final hangingTransport = WatchConnectivityTransport(
        channel: hanging.endpoint,
        diagnostics: log,
        handlerTimeout: const Duration(milliseconds: 10),
      );
      addTearDown(hangingTransport.close);
      hangingTransport.onIncoming((frame) => Completer<void>().future);
      hanging.inbound.add(_timer('m4'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await _settle();
      expect(
        [
          for (final event in log.events())
            if (event.kind == 'frame_handler_failed') event.detail,
        ],
        contains('timer_state timeout'),
      );
    });

    test('S-14312 reachability is noted both ways', () async {
      var now = _start;
      final log = DiagnosticsLog(
        storage: InMemoryDiagnosticsStorage(),
        clock: () => now,
      );
      final link = _Link();
      final transport = WatchConnectivityTransport(
        channel: link.phone,
        diagnostics: log,
      );
      addTearDown(transport.close);
      addTearDown(link.close);
      transport.onIncoming((frame) async {});

      link.phone.reachabilityController.add(true);
      await _settle();
      link.phone.reachabilityController.add(false);
      await _settle();

      expect(
        [
          for (final event in log.events())
            if (event.kind == 'reachability') event.detail,
        ],
        ['reachable', 'unreachable'],
      );
    });

    test('S-14313 a broken log or no log changes nothing the link sees',
        () async {
      final base = await _runObservationFixtures(
        DiagnosticsLog(storage: InMemoryDiagnosticsStorage(), clock: () => _start),
      );
      final throwing = await _runObservationFixtures(
        DiagnosticsLog(storage: _ThrowingStorage(), clock: () => _start),
      );
      final none = await _runObservationFixtures(null);

      expect(throwing.deliveries, base.deliveries);
      expect(throwing.sent, base.sent);
      expect(throwing.queued, base.queued);
      expect(throwing.handled, base.handled);
      expect(throwing.failures, base.failures);

      expect(none.deliveries, base.deliveries);
      expect(none.sent, base.sent);
      expect(none.queued, base.queued);
      expect(none.handled, base.handled);
      expect(none.failures, base.failures);
    });

    test('link_error a reachability read that throws is noted without its '
        'message', () async {
      var now = _start;
      final log = DiagnosticsLog(
        storage: InMemoryDiagnosticsStorage(),
        clock: () => now,
      );
      final link = _Link();
      final transport = WatchConnectivityTransport(
        channel: link.phone,
        diagnostics: log,
      );
      addTearDown(transport.close);
      addTearDown(link.close);
      link.phone.reachFailure = StateError('rating 97531');

      expect(await transport.send(_timer('m1')), WatchDelivery.undelivered);

      expect(
        [
          for (final event in log.events())
            if (event.kind == 'link_error') event.detail,
        ],
        ['StateError'],
      );
      expect(
        [
          for (final event in log.events())
            if (event.kind == 'frame_sent') event.detail,
        ],
        ['timer_state undelivered'],
      );
      expect(log.shareText(), isNot(contains('97531')));
    });
  });
}
