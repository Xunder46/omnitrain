// A timer the phone clears reaches the watch as a stopped timer, never as a
// null: iOS WatchConnectivity refuses a message dictionary that holds a null,
// so every `{rest: null}` / `{hold: null}` the phone sent was dropped by the
// radio (the 2026-11-19 diagnostics log: 451 failed `timer_state` sends, 3
// delivered). The watch already stores a timer carrying `stoppedAt` as a
// stopped row, which ends the running timer of that kind.
//
// Scenario mapping (no plan file; a fix found from the diagnostics log):
//   S-27601 a clear is sent as a stopped timer, with no null anywhere
//   S-27602 a started timer, and a frame with no timers, go out untouched
//   S-27603 the queue path is made safe the same way
//   S-27604 a frame that cannot be read is left alone, never invented
//   S-27605 a refused send keeps its error code for the diagnostics log

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/platform/watch_connectivity_channel.dart';
import 'package:omnitrain_watch_link/omnitrain_watch_link.dart';

const MethodChannel _methods = MethodChannel('omnitrain/watch_link/methods');
const EventChannel _events = EventChannel('omnitrain/watch_link/events');

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

const String _sentAt = '2026-11-19T21:27:28.000Z';

Map<String, Object?> _timerState(Map<String, Object?> timers) => {
  'protocolVersion': 1,
  'messageId': 'm-27601',
  'sessionId': 's-27601',
  'type': 'timer_state',
  'origin': 'phone',
  'sentAt': _sentAt,
  'payload': {'timers': timers},
};

/// True when [value] holds a null anywhere inside it.
bool _holdsNull(Object? value) {
  if (value == null) return true;
  if (value is Map) return value.values.any(_holdsNull);
  if (value is List) return value.any(_holdsNull);
  return false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<MethodCall> calls = <MethodCall>[];
  PlatformException? refuse;

  WatchConnectivityChannel channel() => WatchConnectivityChannel(
    link: WatchLink(methods: _methods, events: _events),
  );

  setUp(() {
    calls.clear();
    refuse = null;
    _messenger.setMockMethodCallHandler(_methods, (call) async {
      calls.add(call);
      final error = refuse;
      if (error != null) throw error;
      if (call.method == 'transferUserInfo') return 'queued';
      return null;
    });
  });

  tearDown(() => _messenger.setMockMethodCallHandler(_methods, null));

  Map<Object?, Object?> timersOf(MethodCall call) =>
      ((call.arguments as Map)['payload'] as Map)['timers']
          as Map<Object?, Object?>;

  group('S-27601 a clear is a stopped timer', () {
    test('S-27601 null kinds leave as stopped timers, no null anywhere', () async {
      await channel().send(_timerState({'rest': null, 'hold': null}));

      final sent = calls.single;
      expect(sent.method, 'sendMessage');
      expect(_holdsNull(sent.arguments), isFalse);
      expect(timersOf(sent), {
        'rest': {
          'kind': 'rest',
          'state': 'stopped',
          'startedAt': _sentAt,
          'stoppedAt': _sentAt,
        },
        'hold': {
          'kind': 'hold',
          'state': 'stopped',
          'startedAt': _sentAt,
          'stoppedAt': _sentAt,
        },
      });
    });

    test('S-27601 a clear beside a running timer keeps the running one', () async {
      final running = {
        'kind': 'hold',
        'state': 'running',
        'startedAt': '2026-11-19T21:26:46.205Z',
        'sessionExerciseId': 'sx-1',
      };

      await channel().send(_timerState({'hold': running, 'rest': null}));

      final timers = timersOf(calls.single);
      expect(timers['hold'], running);
      expect((timers['rest'] as Map)['state'], 'stopped');
    });
  });

  group('S-27602 nothing else is touched', () {
    test('S-27602 a started timer goes out exactly as it was', () async {
      final frame = _timerState({
        'rest': {
          'kind': 'rest',
          'state': 'running',
          'startedAt': '2026-11-19T21:27:00.000Z',
        },
      });

      await channel().send(frame);

      expect(calls.single.arguments, frame);
    });

    test('S-27602 a frame that is not a timer frame goes out exactly as it '
        'was', () async {
      const frame = <String, Object?>{
        'type': 'receipt',
        'messageId': 'm-27602',
        'sentAt': _sentAt,
        'payload': <String, Object?>{
          'entryIds': <String>['e-1'],
        },
      };

      await channel().send(frame);

      expect(calls.single.arguments, frame);
    });
  });

  group('S-27603 the queue path', () {
    test('S-27603 a queued frame carries no null either', () async {
      await channel().queue(_timerState({'hold': null}));

      final sent = calls.single;
      expect(sent.method, 'transferUserInfo');
      expect(_holdsNull(sent.arguments), isFalse);
      expect((timersOf(sent)['hold'] as Map)['state'], 'stopped');
    });
  });

  group('S-27604 a frame that cannot be read', () {
    test('S-27604 no sentAt: the frame is left as it is', () async {
      const frame = <String, Object?>{
        'type': 'timer_state',
        'payload': <String, Object?>{
          'timers': <String, Object?>{'rest': null},
        },
      };

      await channel().send(frame);

      expect(calls.single.arguments, frame);
    });
  });

  group('S-27605 a refused send keeps its code', () {
    test('S-27605 the error the transport logs names the radio code', () async {
      refuse = PlatformException(code: 'send_failed', message: 'detail');

      await expectLater(
        channel().send(_timerState({'rest': null})),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'send_failed',
          ),
        ),
      );
    });
  });
}
