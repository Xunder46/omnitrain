// What the Wear transport writes to the diagnostics log (plan 293, D-29302).
//
// Scenario mapping:
//   S-29310  a live send is one frame_sent line naming its session
//   S-29311  a queued send, and a send nothing could carry
//   S-29312  a refused frame names the error's type and leaks no value
//   S-29313  the name rule: type, request, unknown
//   S-29314  an arrival is recorded before its handler runs
//   S-29315  a failing handler is recorded and the lane goes on
//   S-29316  a transport with no log works as before
//
// Plain `test()` over the link package's own channels (mocked), an in-memory
// log on a fixed clock.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain_watch_link/omnitrain_watch_link.dart';

import 'package:omnitrain/core/services/diagnostics_log.dart';
import 'package:omnitrain/core/services/diagnostics_storage.dart';
import 'package:omnitrain/watch/app/wear_watch_transport.dart';

const MethodChannel _methods = MethodChannel('omnitrain/watch_link/methods');
const EventChannel _events = EventChannel('omnitrain/watch_link/events');

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

void _answer(Future<Object?> Function(MethodCall call) handler) {
  _messenger.setMockMethodCallHandler(_methods, handler);
}

Map<String, Object?> _frame(
  String type, {
  String? sessionId,
  Map<String, Object?> payload = const {},
}) => {
  'protocolVersion': 1,
  'messageId': 'msg-$type',
  'type': type,
  'origin': 'watch',
  'sentAt': '2026-11-22T09:00:00Z',
  'sessionId': ?sessionId,
  'payload': payload,
};

DiagnosticsLog _log() => DiagnosticsLog(
  storage: InMemoryDiagnosticsStorage(),
  clock: () => DateTime.utc(2026, 11, 22, 9),
);

List<String> _lines(DiagnosticsLog log) => [
  for (final event in log.events())
    '${event.kind} ${event.detail ?? ''} ${event.session ?? ''}'.trim(),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _answer((_) async => null);
    _messenger.setMockStreamHandler(
      _events,
      MockStreamHandler.inline(
        onListen: (arguments, events) {},
        onCancel: (arguments) {},
      ),
    );
  });

  tearDown(() {
    _messenger.setMockMethodCallHandler(_methods, null);
    _messenger.setMockStreamHandler(_events, null);
  });

  test(
    'S-29310 a live send is one frame_sent line naming its session',
    () async {
      final log = _log();
      final transport = WearWatchTransport(link: WatchLink(), diagnostics: log);
      addTearDown(transport.close);
      await transport.start();

      await transport.send(_frame('observations_up', sessionId: 'sess-1'));

      expect(_lines(log), ['frame_sent observations_up live sess-1']);
    },
  );

  test('S-29311 a queued send, and a send nothing could carry', () async {
    final log = _log();
    final transport = WearWatchTransport(link: WatchLink(), diagnostics: log);
    addTearDown(transport.close);
    await transport.start();

    _answer((call) async {
      if (call.method == 'sendMessage') {
        throw PlatformException(code: 'not_reachable');
      }
      return 'queued';
    });
    await transport.send(_frame('observations_up', sessionId: 'sess-1'));

    _answer((call) async {
      if (call.method == 'sendMessage' || call.method == 'transferUserInfo') {
        throw PlatformException(code: 'not_reachable');
      }
      return null;
    });
    await transport.send(_frame('session_lifecycle', sessionId: 'sess-2'));

    expect(_lines(log), [
      'frame_sent observations_up queued sess-1',
      'frame_not_sent session_lifecycle WatchLinkException sess-2',
    ]);
  });

  test(
    'S-29312 a refused frame names the error type and leaks no value',
    () async {
      final log = _log();
      final transport = WearWatchTransport(link: WatchLink(), diagnostics: log);
      addTearDown(transport.close);
      await transport.start();
      _answer((call) async {
        if (call.method == 'sendMessage') {
          throw PlatformException(code: 'not_reachable');
        }
        return null;
      });

      await transport.send(
        _frame(
          'timer_state',
          sessionId: 'sess-3',
          payload: {'secret': 'weight-82.5-kg-private'},
        ),
      );

      expect(_lines(log), [
        'frame_not_sent timer_state WatchLinkException sess-3',
      ]);
      final text = log.shareText();
      expect(text, isNot(contains('weight-82.5')));
      expect(text, isNot(contains('secret')));
      expect(text, isNot(contains('not_reachable')));
    },
  );

  test('S-29313 the name rule: type, request, unknown', () async {
    final log = _log();
    final transport = WearWatchTransport(link: WatchLink(), diagnostics: log);
    addTearDown(transport.close);
    await transport.start();

    await transport.send(<String, Object?>{'request': 'routines'});
    await transport.send(<String, Object?>{'something': 'else'});
    await transport.send(_frame('timer_state'));

    expect(_lines(log), [
      'frame_sent routines live',
      'frame_sent unknown live',
      'frame_sent timer_state live',
    ]);
  });

  test('S-29314 an arrival is recorded before its handler runs', () async {
    final log = _log();
    final transport = WearWatchTransport(link: WatchLink(), diagnostics: log);
    addTearDown(transport.close);
    List<String>? seenByHandler;
    transport.onIncoming((frame) async {
      seenByHandler = _lines(log);
    });

    await transport.deliver(_frame('structure_change', sessionId: 'sess-4'));

    expect(seenByHandler, ['frame_received structure_change sess-4']);
    expect(_lines(log), ['frame_received structure_change sess-4']);
  });

  test('S-29315 a failing handler is recorded and the lane goes on', () async {
    final log = _log();
    final failures = <Object>[];
    final transport = WearWatchTransport(
      link: WatchLink(),
      diagnostics: log,
      onFailure: (error, stack) => failures.add(error),
    );
    addTearDown(transport.close);
    var calls = 0;
    transport.onIncoming((frame) async {
      calls++;
      if (calls == 1) throw StateError('boom: weight-82.5');
    });

    await transport.deliver(_frame('exercise_push', sessionId: 'sess-5'));
    await transport.deliver(_frame('timer_state', sessionId: 'sess-5'));

    expect(_lines(log), [
      'frame_received exercise_push sess-5',
      'frame_handler_failed exercise_push StateError sess-5',
      'frame_received timer_state sess-5',
    ]);
    expect(calls, 2, reason: 'the lane still delivered the next frame');
    expect(failures, hasLength(1));
    expect(log.shareText(), isNot(contains('weight-82.5')));
  });

  test('S-29316 a transport with no log works as before', () async {
    final transport = WearWatchTransport(link: WatchLink());
    addTearDown(transport.close);
    await transport.start();
    var handled = 0;
    transport.onIncoming((frame) async => handled++);

    await transport.send(_frame('observations_up', sessionId: 'sess-6'));
    await transport.deliver(_frame('timer_state'));
    _answer((call) async {
      if (call.method == 'sendMessage') {
        throw PlatformException(code: 'not_reachable');
      }
      return null;
    });
    await transport.send(_frame('timer_state'));

    expect(handled, 1);
  });
}
