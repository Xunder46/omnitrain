// The wrist's radio on Wear OS (`WearWatchTransport`), over the link package's
// own channels.
//
// Plan: `docs/plans/2026-11-20-280-wear-os-shell-plan/2026-11-20-280-wear-os-shell-plan.md`
// (D-28006). Scenario mapping:
//   S-28010 reachability is the platform's answer, and its events
//   S-28011 a request names no `type` and carries the wrist's `since`
//   S-28012 a durable frame refused live waits in the OS queue
//   S-28013 a non-durable frame refused live is reported and dropped
//   S-28014 a frame is made radio-safe before it leaves
//   S-28015 arrivals are handed over in order, one at a time
//   S-28016 the durability table

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain_watch_link/omnitrain_watch_link.dart';

import 'package:omnitrain/watch/app/wear_watch_transport.dart';

const MethodChannel _methods = MethodChannel('omnitrain/watch_link/methods');
const EventChannel _events = EventChannel('omnitrain/watch_link/events');

final List<MethodCall> _calls = <MethodCall>[];

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

void _answer(Future<Object?> Function(MethodCall call) handler) {
  _messenger.setMockMethodCallHandler(_methods, (call) {
    _calls.add(call);
    return handler(call);
  });
}

Future<void> _settle() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

MockStreamHandlerEventSink? _sink;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _calls.clear();
    _answer((_) async => null);
    _messenger.setMockStreamHandler(
      _events,
      MockStreamHandler.inline(
        onListen: (arguments, events) {
          _sink = events;
        },
        onCancel: (arguments) {
          _sink = null;
        },
      ),
    );
  });

  tearDown(() {
    _messenger.setMockMethodCallHandler(_methods, null);
    _messenger.setMockStreamHandler(_events, null);
  });

  group('S-28010 reachability', () {
    test('is read from the platform status', () async {
      _answer(
        (call) async => call.method == 'status'
            ? <String, Object?>{
                'supported': true,
                'paired': true,
                'appInstalled': true,
                'activated': true,
                'reachable': true,
              }
            : null,
      );

      final transport = WearWatchTransport(link: WatchLink());
      addTearDown(transport.close);
      expect(transport.isPhoneReachable, isFalse);

      await transport.start();

      expect(transport.isPhoneReachable, isTrue);
    });

    test('follows the reachability and state events', () async {
      final transport = WearWatchTransport(link: WatchLink());
      addTearDown(transport.close);
      await transport.start();
      expect(transport.isPhoneReachable, isFalse);

      _sink!.success(<String, Object?>{'kind': 'reachability', 'reachable': true});
      await _settle();
      expect(transport.isPhoneReachable, isTrue);

      _sink!.success(<String, Object?>{
        'kind': 'state',
        'supported': true,
        'paired': true,
        'appInstalled': true,
        'activated': true,
        'reachable': false,
      });
      await _settle();
      expect(transport.isPhoneReachable, isFalse);
    });
  });

  group('S-28011 request frames', () {
    test('a routines request carries no type and names the wrist since', () async {
      final transport = WearWatchTransport(link: WatchLink());
      addTearDown(transport.close);
      await transport.start();
      _calls.clear();

      await transport.requestRoutines(since: DateTime.utc(2026, 11, 20, 9));

      final sent = _calls.singleWhere((call) => call.method == 'sendMessage');
      final frame = sent.arguments as Map<Object?, Object?>;
      expect(frame.containsKey('type'), isFalse);
      expect(frame['request'], 'routines');
      expect(frame['since'], '2026-11-20T09:00:00.000Z');
    });

    test('a snapshot request carries no type and no since', () async {
      final transport = WearWatchTransport(link: WatchLink());
      addTearDown(transport.close);
      await transport.start();
      _calls.clear();

      await transport.requestSnapshot();

      final sent = _calls.singleWhere((call) => call.method == 'sendMessage');
      final frame = sent.arguments as Map<Object?, Object?>;
      expect(frame['request'], 'snapshot');
      expect(frame.containsKey('type'), isFalse);
      expect(frame.containsKey('since'), isFalse);
    });
  });

  group('S-28012 a durable frame refused live is queued', () {
    test('an observation goes to the OS queue when the radio refuses it', () async {
      _answer((call) async {
        if (call.method == 'sendMessage') {
          throw PlatformException(code: 'not_reachable');
        }
        if (call.method == 'transferUserInfo') return 'queued';
        return null;
      });

      final failures = <Object>[];
      final transport = WearWatchTransport(
        link: WatchLink(),
        onFailure: (error, stack) => failures.add(error),
      );
      addTearDown(transport.close);
      await transport.start();
      _calls.clear();

      await transport.send(<String, Object?>{
        'protocolVersion': 1,
        'messageId': 'msg-1',
        'type': 'observations_up',
        'origin': 'watch',
        'sentAt': '2026-11-20T09:00:00Z',
        'payload': <String, Object?>{'observations': <Object?>[]},
      });

      final queued = _calls.singleWhere(
        (call) => call.method == 'transferUserInfo',
      );
      expect(
        (queued.arguments as Map<Object?, Object?>)['messageId'],
        'msg-1',
      );
      expect(failures, isEmpty);
    });

    test('a running snapshot is durable and an ended one is not', () {
      Map<String, Object?> snapshot(String status) => <String, Object?>{
        'type': 'session_snapshot',
        'payload': <String, Object?>{'status': status},
      };

      expect(WearWatchTransport.isDurable(snapshot('active')), isTrue);
      expect(WearWatchTransport.isDurable(snapshot('completed')), isFalse);
      expect(
        WearWatchTransport.isDurable(<String, Object?>{'type': 'timer_state'}),
        isFalse,
      );
      expect(
        WearWatchTransport.isDurable(<String, Object?>{'request': 'snapshot'}),
        isFalse,
      );
    });
  });

  group('S-28013 a non-durable frame is reported and dropped', () {
    test('a timer refused live never reaches the queue', () async {
      _answer((call) async {
        if (call.method == 'sendMessage') {
          throw PlatformException(code: 'not_reachable');
        }
        return null;
      });

      final failures = <Object>[];
      final transport = WearWatchTransport(
        link: WatchLink(),
        onFailure: (error, stack) => failures.add(error),
      );
      addTearDown(transport.close);
      await transport.start();
      _calls.clear();

      await transport.send(<String, Object?>{
        'protocolVersion': 1,
        'messageId': 'msg-2',
        'type': 'timer_state',
        'origin': 'watch',
        'sentAt': '2026-11-20T09:00:00Z',
        'payload': <String, Object?>{},
      });

      expect(
        _calls.where((call) => call.method == 'transferUserInfo'),
        isEmpty,
      );
      expect(failures, hasLength(1));
      expect(failures.single, isA<WatchLinkException>());
    });
  });

  group('S-28014 a frame is radio-safe before it leaves', () {
    test('a null timer travels as a stopped timer', () async {
      final transport = WearWatchTransport(link: WatchLink());
      addTearDown(transport.close);
      await transport.start();
      _calls.clear();

      await transport.send(<String, Object?>{
        'protocolVersion': 1,
        'messageId': 'msg-3',
        'type': 'timer_state',
        'origin': 'watch',
        'sentAt': '2026-11-20T09:00:00Z',
        'payload': <String, Object?>{
          'timers': <String, Object?>{'rest': null},
        },
      });

      final sent = _calls.singleWhere((call) => call.method == 'sendMessage');
      final timers =
          ((sent.arguments as Map<Object?, Object?>)['payload']
              as Map<Object?, Object?>)['timers'] as Map<Object?, Object?>;
      expect(timers['rest'], <String, Object?>{
        'kind': 'rest',
        'state': 'stopped',
        'startedAt': '2026-11-20T09:00:00Z',
        'stoppedAt': '2026-11-20T09:00:00Z',
      });
    });
  });

  group('S-28015 arrivals are handed over in order, one at a time', () {
    test('two frames that arrive together are handled in sequence', () async {
      final transport = WearWatchTransport(link: WatchLink());
      addTearDown(transport.close);

      final seen = <String>[];
      var running = 0;
      var overlapped = false;
      final done = Completer<void>();
      transport.onIncoming((frame) async {
        running += 1;
        if (running > 1) overlapped = true;
        seen.add(frame['messageId'] as String);
        await Future<void>.delayed(Duration.zero);
        running -= 1;
        if (seen.length == 2 && !done.isCompleted) done.complete();
      });

      await transport.start();

      _sink!.success(<String, Object?>{
        'kind': 'message',
        'frame': <String, Object?>{'messageId': 'a', 'type': 'receipt'},
      });
      _sink!.success(<String, Object?>{
        'kind': 'userInfo',
        'frame': <String, Object?>{'messageId': 'b', 'type': 'receipt'},
      });

      await done.future;

      expect(seen, <String>['a', 'b']);
      expect(overlapped, isFalse);
    });
  });

  group('S-28016 the durability table', () {
    test('a lifecycle and a start are durable, a receipt is not', () {
      for (final type in <String>[
        'observations_up',
        'session_lifecycle',
        'session_started',
      ]) {
        expect(
          WearWatchTransport.isDurable(<String, Object?>{
            'type': type,
            'payload': <String, Object?>{},
          }),
          isTrue,
          reason: '$type is owed for good',
        );
      }
      for (final type in <String>['receipt', 'energy_live', 'water_down']) {
        expect(
          WearWatchTransport.isDurable(<String, Object?>{'type': type}),
          isFalse,
          reason: '$type is live state',
        );
      }
    });
  });
}
