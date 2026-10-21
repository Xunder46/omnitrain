// The plugin package's Dart side: two channels, the errors they report, and
// the events they carry.
//
// Plan: `docs/plans/2026-10-21-47a-watch-link-plugin-plan/2026-10-21-47a-watch-link-plugin-plan.md`
// (D-2 method contract, D-3 event contract, D-4 Dart API).
// Scenario mapping:
//   S-6801 status() decodes the native map
//   S-6802 sendMessage completes, maps a platform error, and times out
//   S-6803 transferUserInfo answers `queued` / `already_queued`
//   S-6804 events decode the four kinds in order and skip an unknown kind
//   S-6805 one broadcast stream: two listeners, one native `listen`

import 'dart:async';

// `fake_async` ships with `flutter_test`; the timeout test must never read the
// real clock (plan S-6802).
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain_watch_link/omnitrain_watch_link.dart';

const MethodChannel _methods = MethodChannel('omnitrain/watch_link/methods');
const EventChannel _events = EventChannel('omnitrain/watch_link/events');

/// Every call the plugin made on the method channel, in order.
final List<MethodCall> _calls = <MethodCall>[];

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

/// Answers the method channel with [handler] and records the call.
void _answer(Future<Object?> Function(MethodCall call) handler) {
  _messenger.setMockMethodCallHandler(_methods, (call) {
    _calls.add(call);
    return handler(call);
  });
}

/// Lets queued microtasks and zero-delay timers run; no real time passes.
Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// What the native side of the event channel saw.
class _NativeEvents {
  int listens = 0;
  int cancels = 0;
  Object? listenArguments;
  MockStreamHandlerEventSink? sink;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _NativeEvents native;

  setUp(() {
    _calls.clear();
    _answer((_) async => null);
    native = _NativeEvents();
    _messenger.setMockStreamHandler(
      _events,
      MockStreamHandler.inline(
        onListen: (arguments, events) {
          native.listens += 1;
          native.listenArguments = arguments;
          native.sink = events;
        },
        onCancel: (arguments) {
          native.cancels += 1;
        },
      ),
    );
  });

  tearDown(() {
    _messenger.setMockMethodCallHandler(_methods, null);
    _messenger.setMockStreamHandler(_events, null);
  });

  group('S-6801 status', () {
    test('decodes the native status map', () async {
      _answer(
        (_) async => <String, Object?>{
          'supported': true,
          'paired': true,
          'appInstalled': true,
          'activated': true,
          'reachable': false,
        },
      );

      final status = await WatchLink().status();

      expect(status.supported, isTrue);
      expect(status.paired, isTrue);
      expect(status.appInstalled, isTrue);
      expect(status.activated, isTrue);
      expect(status.reachable, isFalse);
      expect(_calls.single.method, 'status');
      expect(_calls.single.arguments, isNull);
    });

    test('treats missing keys as false', () async {
      _answer((_) async => <String, Object?>{'paired': true});

      final status = await WatchLink().status();

      expect(status.supported, isFalse);
      expect(status.paired, isTrue);
      expect(status.appInstalled, isFalse);
      expect(status.activated, isFalse);
      expect(status.reachable, isFalse);
      expect(_calls.single.method, 'status');
      expect(_calls.single.arguments, isNull);
    });
  });

  group('S-6802 sendMessage', () {
    const frame = <String, Object?>{'type': 'receipt', 'messageId': 'm-1'};

    test('sends the frame itself and completes on a null result', () async {
      _answer((_) async => null);

      await WatchLink().sendMessage(frame);

      expect(_calls.single.method, 'sendMessage');
      expect(_calls.single.arguments, frame);
    });

    test(
      'turns a platform error into WatchLinkException with its code',
      () async {
        _answer(
          (_) async => throw PlatformException(
            code: 'not_reachable',
            message: 'the watch is out of reach',
          ),
        );

        await expectLater(
          WatchLink().sendMessage(frame),
          throwsA(
            isA<WatchLinkException>()
                .having((e) => e.code, 'code', 'not_reachable')
                .having(
                  (e) => e.message,
                  'message',
                  'the watch is out of reach',
                ),
          ),
        );
        expect(_calls.single.method, 'sendMessage');
        expect(_calls.single.arguments, frame);
      },
    );

    test('times out with WatchLinkException(timeout) under fake time', () {
      fakeAsync((async) {
        final never = Completer<Object?>();
        _answer((_) => never.future);
        Object? error;

        WatchLink()
            .sendMessage(frame, timeout: const Duration(seconds: 3))
            .catchError((Object caught) {
              error = caught;
            });
        async.flushMicrotasks();

        expect(_calls.single.method, 'sendMessage');
        expect(_calls.single.arguments, frame);
        expect(error, isNull);

        async.elapse(const Duration(seconds: 3));
        async.flushMicrotasks();

        expect(error, isA<WatchLinkException>());
        expect((error! as WatchLinkException).code, 'timeout');
      });
    });
  });

  group('S-6803 transferUserInfo', () {
    const frame = <String, Object?>{'type': 'receipt', 'messageId': 'm-2'};

    test('answers queued', () async {
      _answer((_) async => 'queued');

      expect(await WatchLink().transferUserInfo(frame), 'queued');
      expect(_calls.single.method, 'transferUserInfo');
      expect(_calls.single.arguments, frame);
    });

    test('answers already_queued', () async {
      _answer((_) async => 'already_queued');

      expect(await WatchLink().transferUserInfo(frame), 'already_queued');
      expect(_calls.single.method, 'transferUserInfo');
      expect(_calls.single.arguments, frame);
    });
  });

  group('S-6804 events', () {
    test('decodes the four kinds in order and skips an unknown kind', () async {
      final received = <WatchLinkEvent>[];
      final subscription = WatchLink().events.listen(received.add);
      await _settle();
      expect(native.sink, isNotNull);
      expect(native.listenArguments, isNull);

      native.sink!.success(<String, Object?>{
        'kind': 'message',
        'frame': <String, Object?>{'type': 'receipt', 'messageId': 'm-3'},
      });
      native.sink!.success(<String, Object?>{
        'kind': 'userInfo',
        'frame': <String, Object?>{'type': 'session_snapshot'},
      });
      native.sink!.success(<String, Object?>{
        'kind': 'reachability',
        'reachable': true,
      });
      native.sink!.success(<String, Object?>{
        'kind': 'state',
        'supported': true,
        'paired': true,
        'appInstalled': false,
        'activated': true,
        'reachable': true,
      });
      native.sink!.success(<String, Object?>{
        'kind': 'something_new',
        'frame': <String, Object?>{'type': 'ignored'},
      });
      await _settle();
      await subscription.cancel();

      expect(received, hasLength(4));
      expect(received[0], isA<WatchLinkMessage>());
      expect((received[0] as WatchLinkMessage).frame, <String, Object?>{
        'type': 'receipt',
        'messageId': 'm-3',
      });
      expect(received[1], isA<WatchLinkUserInfo>());
      expect((received[1] as WatchLinkUserInfo).frame, <String, Object?>{
        'type': 'session_snapshot',
      });
      expect(received[2], isA<WatchLinkReachability>());
      expect((received[2] as WatchLinkReachability).reachable, isTrue);
      expect(received[3], isA<WatchLinkStateChanged>());
      final status = (received[3] as WatchLinkStateChanged).status;
      expect(status.paired, isTrue);
      expect(status.appInstalled, isFalse);
      expect(status.activated, isTrue);
      expect(_calls, isEmpty);
    });
  });

  group('S-6805 one broadcast stream', () {
    test(
      'two listeners see the same event and the native listen happens once',
      () async {
        final link = WatchLink();
        final first = <WatchLinkEvent>[];
        final second = <WatchLinkEvent>[];
        final firstSub = link.events.listen(first.add);
        final secondSub = link.events.listen(second.add);
        await _settle();

        expect(native.listens, 1);
        expect(native.listenArguments, isNull);

        native.sink!.success(<String, Object?>{
          'kind': 'reachability',
          'reachable': false,
        });
        await _settle();

        expect(first, hasLength(1));
        expect(second, hasLength(1));
        expect(first.single, isA<WatchLinkReachability>());
        expect((first.single as WatchLinkReachability).reachable, isFalse);
        expect((second.single as WatchLinkReachability).reachable, isFalse);
        expect(native.listens, 1);
        expect(_calls, isEmpty);

        await firstSub.cancel();
        await secondSub.cancel();
      },
    );
  });
}
