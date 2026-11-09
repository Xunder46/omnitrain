// The app's channel over the phone's watch link: one `messages` stream for
// both kinds of arriving frame, reachability as a bool, and a queue that hands
// the OS a frame.
//
// Plan: `docs/plans/2026-10-21-47a-watch-link-plugin-plan/2026-10-21-47a-watch-link-plugin-plan.md`
// (D-4 Dart API, D-5 app side).
// Scenario mapping:
//   S-6816 a `userInfo` frame reaches the handler exactly like a message
//          (the channel merges both into `messages`)
//   S-9703 the channel exposes the queue without plugin types

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/platform/watch_connectivity_channel.dart';
import 'package:omnitrain/core/platform/watch_link_info.dart';
import 'package:omnitrain/core/platform/watch_queue_control.dart';
import 'package:omnitrain_watch_link/omnitrain_watch_link.dart';

const MethodChannel _methods = MethodChannel('omnitrain/watch_link/methods');
const EventChannel _events = EventChannel('omnitrain/watch_link/events');

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

/// Every call the channel made on the method channel, in order.
final List<MethodCall> _calls = <MethodCall>[];

/// Lets queued microtasks and zero-delay timers run; no real time passes.
Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// What the native side of the event channel saw.
class _NativeEvents {
  int listens = 0;
  MockStreamHandlerEventSink? sink;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _NativeEvents native;

  WatchLink link() => WatchLink(methods: _methods, events: _events);

  setUp(() {
    _calls.clear();
    native = _NativeEvents();
    _messenger.setMockMethodCallHandler(_methods, (call) async {
      _calls.add(call);
      switch (call.method) {
        case 'status':
          return <String, Object?>{
            'supported': true,
            'paired': true,
            'appInstalled': false,
            'activated': true,
            'reachable': true,
          };
        case 'transferUserInfo':
          return 'queued';
        case 'outstandingTransfers':
          return <Object?>[
            <String, Object?>{
              'messageId': 'm1',
              'type': 'session_snapshot',
              'sessionId': 's-1',
            },
            <String, Object?>{
              'messageId': 'm2',
              'type': 'structure_change',
              'sessionId': 's-1',
              'changeId': 'c1',
            },
            <String, Object?>{'messageId': 'r1', 'type': 'receipt'},
            <String, Object?>{'type': 'foods_down'},
            42,
          ];
        case 'cancelTransfers':
          return 2;
      }
      return null;
    });
    _messenger.setMockStreamHandler(
      _events,
      MockStreamHandler.inline(
        onListen: (arguments, events) {
          native.listens += 1;
          native.sink = events;
        },
      ),
    );
  });

  tearDown(() {
    _messenger.setMockMethodCallHandler(_methods, null);
    _messenger.setMockStreamHandler(_events, null);
  });

  group('S-6816 the channel over the plugin', () {
    test('S-6816 messages carries a message frame and a userInfo frame in '
        'order, and nothing else', () async {
      final channel = WatchConnectivityChannel(link: link());
      final frames = <Map<String, Object?>>[];
      final subscription = channel.messages.listen(frames.add);
      await _settle();
      expect(native.sink, isNotNull);

      native.sink!.success(<String, Object?>{
        'kind': 'message',
        'frame': <String, Object?>{'type': 'receipt', 'messageId': 'm-6816'},
      });
      native.sink!.success(<String, Object?>{
        'kind': 'userInfo',
        'frame': <String, Object?>{
          'type': 'session_snapshot',
          'payload': <String, Object?>{'sessionId': 's-6816'},
        },
      });
      native.sink!.success(<String, Object?>{
        'kind': 'reachability',
        'reachable': false,
      });
      await _settle();
      await subscription.cancel();

      expect(frames, hasLength(2));
      expect(frames.first, <String, Object?>{
        'type': 'receipt',
        'messageId': 'm-6816',
      });
      expect(frames.last, <String, Object?>{
        'type': 'session_snapshot',
        'payload': <String, Object?>{'sessionId': 's-6816'},
      });
    });

    test('S-6816 reachability yields the bool, not the frame', () async {
      final channel = WatchConnectivityChannel(link: link());
      final changes = <bool>[];
      final subscription = channel.reachability.listen(changes.add);
      await _settle();
      expect(native.sink, isNotNull);

      native.sink!.success(<String, Object?>{
        'kind': 'message',
        'frame': <String, Object?>{'type': 'timer_state'},
      });
      native.sink!.success(<String, Object?>{
        'kind': 'reachability',
        'reachable': false,
      });
      native.sink!.success(<String, Object?>{
        'kind': 'reachability',
        'reachable': true,
      });
      await _settle();
      await subscription.cancel();

      expect(changes, [false, true]);
    });

    test('S-6816 queue hands transferUserInfo the frame itself', () async {
      final channel = WatchConnectivityChannel(link: link());
      const frame = <String, Object?>{
        'type': 'receipt',
        'messageId': 'm-queue-6816',
        'payload': <String, Object?>{
          'entryIds': <String>['e-6816'],
        },
      };

      await channel.queue(frame);

      expect(_calls.single.method, 'transferUserInfo');
      expect(_calls.single.arguments, frame);
    });

    test('S-6816 info maps the native status onto WatchLinkInfo', () async {
      final channel = WatchConnectivityChannel(link: link());

      final info = await channel.info;

      expect(
        info,
        const WatchLinkInfo(paired: true, appInstalled: false, reachable: true),
      );
      expect(_calls.single.method, 'status');
    });
  });

  group('S-9703 the channel exposes the queue without plugin types', () {
    test('S-9703 outstandingTransfers returns the three core-typed transfers '
        'in order', () async {
      final channel = WatchConnectivityChannel(link: link());

      final transfers = await channel.outstandingTransfers();

      expect(transfers, const [
        WatchQueuedTransfer(
          messageId: 'm1',
          type: 'session_snapshot',
          sessionId: 's-1',
        ),
        WatchQueuedTransfer(
          messageId: 'm2',
          type: 'structure_change',
          sessionId: 's-1',
          changeId: 'c1',
        ),
        WatchQueuedTransfer(messageId: 'r1', type: 'receipt'),
      ]);
    });

    test(
      'S-9703 cancelTransfers forwards the ids and returns the count',
      () async {
        final channel = WatchConnectivityChannel(link: link());

        final cancelled = await channel.cancelTransfers(['m1', 'm2']);

        expect(cancelled, 2);
        expect(_calls.single.method, 'cancelTransfers');
        expect(_calls.single.arguments, <String, Object?>{
          'messageIds': <String>['m1', 'm2'],
        });
      },
    );

    test('S-9703 cancelTransfers with an empty list cancels nothing', () async {
      final channel = WatchConnectivityChannel(link: link());

      final cancelled = await channel.cancelTransfers([]);

      expect(cancelled, 0);
      expect(_calls, isEmpty);
    });

    test('S-9703 the channel is a WatchQueueControl', () {
      final channel = WatchConnectivityChannel(link: link());

      expect(channel, isA<WatchQueueControl>());
    });
  });
}
