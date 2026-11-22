// Only the newest copy of a workout waits in the Wear wrist's OS queue.
//
// Plan: `docs/plans/2026-11-22-294-wear-newest-copy-queue-plan/2026-11-22-294-wear-newest-copy-queue-plan.md`
// (D-29401..D-29408). The Dart twin of the Apple bridge's plan 69 rule
// (S-9901..S-9916). The mock channel keeps a mutable queue (a cancel removes
// ids, a queue call that finds the id already there answers `already_queued`
// like the plugin) and records every call in order.
//   S-29401 a snapshot replaces the session's snapshots, nothing else
//   S-29402 same id, newer content: cancel first, then queue
//   S-29403 a stale copy is not queued; an equal stamp replaces
//   S-29404 a terminal lifecycle replaces the live state and is never stale
//   S-29405 a non-terminal lifecycle replaces only non-terminal lifecycles
//   S-29406 observations stay; timers and requests never queue or list
//   S-29407 forty snapshots leave one
//   S-29408 a live send withdraws older waiting copies, never a newer one
//   S-29409 an unreadable stamp: oldest on a copy, newest on the frame
//   S-29410 a list failure is reported and the frame still queues
//   S-29411 a cancel failure and a queue failure
//   S-29412 two hand-overs at once leave one copy
//   S-29413 copies left by an earlier run are matched
//   S-29415 the Kotlin source reads state and sentAt from the stored frame

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain_watch_link/omnitrain_watch_link.dart';

import 'package:omnitrain/watch/app/wear_watch_transport.dart';

const MethodChannel _methods = MethodChannel('omnitrain/watch_link/methods');
const EventChannel _events = EventChannel('omnitrain/watch_link/events');

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

/// The data items the fake data layer holds: one map per transfer, as the
/// plugin would answer them.
final List<Map<String, Object?>> _queue = <Map<String, Object?>>[];

/// Every call that reached the platform, in order: `send:<id>`, `list`,
/// `cancel:<ids>`, `queue:<id>`.
final List<String> _log = <String>[];
final List<List<String>> _cancels = <List<String>>[];
final List<Map<String, Object?>> _queuedFrames = <Map<String, Object?>>[];
final List<Map<String, Object?>> _sentFrames = <Map<String, Object?>>[];
final List<Object> _failures = <Object>[];

bool _radioUp = false;
bool _listFails = false;
bool _cancelFails = false;
bool _queueFails = false;
Completer<void>? _listGate;
int _listCalls = 0;

String _t(int n) => '2026-11-22T10:00:${n.toString().padLeft(2, '0')}Z';

Map<String, Object?> snap(String session, String id, int t) => {
  'type': 'session_snapshot',
  'messageId': id,
  'sessionId': session,
  'sentAt': _t(t),
  'payload': {'status': 'active'},
};

Map<String, Object?> lc(String session, String state, String id, int t) => {
  'type': 'session_lifecycle',
  'messageId': id,
  'sessionId': session,
  'sentAt': _t(t),
  'payload': {'state': state},
};

Map<String, Object?> obs(String session, String id) => {
  'type': 'observations_up',
  'messageId': id,
  'sessionId': session,
  'sentAt': _t(0),
  'payload': <String, Object?>{},
};

Map<String, Object?> _entry(Map<String, Object?> frame) {
  final payload = frame['payload'];
  final entry = <String, Object?>{
    'messageId': frame['messageId'],
    'type': frame['type'] ?? '',
  };
  if (frame['sessionId'] is String) entry['sessionId'] = frame['sessionId'];
  if (frame['sentAt'] is String) entry['sentAt'] = frame['sentAt'];
  if (payload is Map && payload['state'] is String) {
    entry['state'] = payload['state'];
  }
  return entry;
}

void _seed(List<Map<String, Object?>> frames) {
  _queue
    ..clear()
    ..addAll(frames.map(_entry));
}

/// The ids waiting, in queue order; an entry without an id reads `foo`.
List<String> _ids() => [
  for (final entry in _queue) (entry['messageId'] as String?) ?? 'foo',
];

Future<Object?> _handle(MethodCall call) async {
  switch (call.method) {
    case 'status':
      return <String, Object?>{
        'supported': true,
        'paired': true,
        'appInstalled': true,
        'activated': true,
        'reachable': _radioUp,
      };
    case 'sendMessage':
      final frame = Map<String, Object?>.from(call.arguments as Map);
      _log.add('send:${frame['messageId']}');
      if (!_radioUp) {
        throw PlatformException(code: 'not_reachable');
      }
      _sentFrames.add(frame);
      return null;
    case 'transferUserInfo':
      final frame = Map<String, Object?>.from(call.arguments as Map);
      _log.add('queue:${frame['messageId']}');
      if (_queueFails) throw PlatformException(code: 'send_failed');
      _queuedFrames.add(frame);
      if (_queue.any((e) => e['messageId'] == frame['messageId'])) {
        return 'already_queued';
      }
      _queue.add(_entry(frame));
      return 'queued';
    case 'outstandingTransfers':
      _log.add('list');
      _listCalls++;
      final gate = _listGate;
      if (gate != null && _listCalls == 1) await gate.future;
      if (_listFails) throw PlatformException(code: 'send_failed');
      return <Object?>[for (final e in _queue) Map<String, Object?>.of(e)];
    case 'cancelTransfers':
      final ids = List<String>.from(
        ((call.arguments as Map)['messageIds'] as List).cast<String>(),
      );
      _log.add('cancel:${ids.join(',')}');
      _cancels.add(ids);
      if (_cancelFails) throw PlatformException(code: 'send_failed');
      final before = _queue.length;
      _queue.removeWhere((e) => ids.contains(e['messageId']));
      return before - _queue.length;
  }
  return null;
}

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

WearWatchTransport _transport() {
  final transport = WearWatchTransport(
    link: WatchLink(),
    onFailure: (error, stack) => _failures.add(error),
  );
  addTearDown(transport.close);
  return transport;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _queue.clear();
    _log.clear();
    _cancels.clear();
    _queuedFrames.clear();
    _sentFrames.clear();
    _failures.clear();
    _radioUp = false;
    _listFails = false;
    _cancelFails = false;
    _queueFails = false;
    _listGate = null;
    _listCalls = 0;
    _messenger.setMockMethodCallHandler(_methods, _handle);
    _messenger.setMockStreamHandler(
      _events,
      MockStreamHandler.inline(onListen: (arguments, events) {}),
    );
  });

  tearDown(() {
    _messenger.setMockMethodCallHandler(_methods, null);
    _messenger.setMockStreamHandler(_events, null);
  });

  test(
    'S-29401 a snapshot replaces the session\'s snapshots and nothing else',
    () async {
      _seed([
        snap('s-1', 'mA', 1),
        snap('s-2', 'mB', 1),
        obs('s-1', 'mO'),
        lc('s-1', 'started', 'mL', 0),
      ]);
      _queue
        ..add(<String, Object?>{'foo': 1})
        ..add(<String, Object?>{'messageId': 'x'});

      await _transport().send(snap('s-1', 'mC', 2));

      expect(_cancels, [
        ['mA'],
      ]);
      expect(_ids(), ['mB', 'mO', 'mL', 'foo', 'x', 'mC']);
      expect(_failures, isEmpty);
    },
  );

  test('S-29402 same id, newer content: cancel first, then queue', () async {
    _seed([snap('s-1', 'mA', 1)]);

    await _transport().send(snap('s-1', 'mA', 2));

    expect(_log.where((e) => e != 'send:mA'), [
      'list',
      'cancel:mA',
      'queue:mA',
    ]);
    expect(_queue.single['sentAt'], _t(2));
  });

  test('S-29403 a stale copy is not queued; an equal stamp replaces', () async {
    _seed([snap('s-1', 'mN', 3)]);
    final transport = _transport();

    await transport.send(snap('s-1', 'mO', 2));

    expect(_cancels, isEmpty);
    expect(_queuedFrames, isEmpty);
    expect(_ids(), ['mN']);
    expect(_failures, isEmpty);

    await transport.send(snap('s-1', 'mE', 3));

    expect(_cancels, [
      ['mN'],
    ]);
    expect(_ids(), ['mE']);
  });

  test(
    'S-29404 a terminal lifecycle replaces the live state, is never stale',
    () async {
      _seed([
        lc('s-1', 'started', 'mS', 0),
        snap('s-1', 'mP', 1),
        obs('s-1', 'mO1'),
        lc('s-1', 'exercise_advanced', 'mA', 2),
        lc('s-2', 'started', 'mS2', 0),
        lc('s-3', 'abandoned', 'mX', 1),
      ]);
      final transport = _transport();

      await transport.send(lc('s-1', 'completed', 'mC', 3));

      expect(_cancels.single.toSet(), {'mS', 'mP', 'mA'});
      expect(_ids(), ['mO1', 'mS2', 'mX', 'mC']);

      await transport.send(lc('s-1', 'completed', 'mC', 3));

      expect(_cancels, hasLength(1));
      expect(_ids().where((id) => id == 'mC'), hasLength(1));
      expect(_log.where((entry) => entry == 'queue:mC'), hasLength(1));

      await transport.send(lc('s-3', 'started', 'mY', 2));

      expect(_ids(), ['mO1', 'mS2', 'mX', 'mC', 'mY']);
      expect(_cancels, hasLength(1));
    },
  );

  test(
    'S-29404 a terminal lifecycle stamped earlier than a copy still wins',
    () async {
      _seed([snap('s-1', 'mP', 9)]);

      await _transport().send(lc('s-1', 'completed', 'mC', 3));

      expect(_cancels, [
        ['mP'],
      ]);
      expect(_ids(), ['mC']);
    },
  );

  test(
    'S-29405 a non-terminal lifecycle replaces non-terminal lifecycles only',
    () async {
      _seed([
        lc('s-1', 'started', 'mS', 0),
        snap('s-1', 'mP', 1),
        lc('s-1', 'completed', 'mZ', 1),
      ]);

      await _transport().send(lc('s-1', 'exercise_advanced', 'mA', 2));

      expect(_cancels, [
        ['mS'],
      ]);
      expect(_ids(), ['mP', 'mZ', 'mA']);
    },
  );

  test('S-29405 a snapshot never replaces a lifecycle', () async {
    _seed([lc('s-1', 'started', 'mS', 0)]);

    await _transport().send(snap('s-1', 'mP', 1));

    expect(_cancels, isEmpty);
    expect(_ids(), ['mS', 'mP']);
  });

  test(
    'S-29406 observations stay; timers and requests never queue or list',
    () async {
      _seed([obs('s-1', 'mO1')]);
      final transport = _transport();

      await transport.send(obs('s-1', 'mO2'));
      await transport.send(snap('s-1', 'mP', 1));
      await transport.send(lc('s-1', 'completed', 'mC', 2));

      expect(_cancels, [
        ['mP'],
      ]);
      expect(_ids(), ['mO1', 'mO2', 'mC']);

      final listsBefore = _listCalls;
      final failuresBefore = _failures.length;
      await transport.send({
        'type': 'timer_state',
        'messageId': 'mT',
        'sessionId': 's-1',
        'sentAt': _t(3),
        'payload': {'timers': <String, Object?>{}},
      });
      await transport.requestSnapshot();

      expect(_listCalls, listsBefore);
      expect(_failures.length, failuresBefore + 2);
      expect(_ids(), ['mO1', 'mO2', 'mC']);
    },
  );

  test('S-29407 forty snapshots leave one', () async {
    final transport = _transport();

    for (var i = 1; i <= 40; i++) {
      await transport.send(snap('s-1', 'm$i', i));
      expect(
        _queue.where((e) => e['type'] == 'session_snapshot'),
        hasLength(1),
      );
    }

    expect(_cancels.expand((ids) => ids), hasLength(39));
    expect(_ids(), ['m40']);
  });

  test(
    'S-29408 a live send withdraws older copies, never a newer one',
    () async {
      _radioUp = true;
      _seed([
        snap('s-1', 'mA', 1),
        lc('s-1', 'started', 'mS', 0),
        obs('s-1', 'mO'),
      ]);
      final transport = _transport();

      await transport.send(snap('s-1', 'mB', 2));

      expect(_sentFrames.single['messageId'], 'mB');
      expect(_cancels, [
        ['mA'],
      ]);
      expect(_queuedFrames, isEmpty);

      await transport.send(lc('s-1', 'completed', 'mC', 3));

      expect(_cancels, [
        ['mA'],
        ['mS'],
      ]);
      expect(_ids(), ['mO']);

      _seed([snap('s-1', 'mN', 5)]);
      await transport.send(snap('s-1', 'mOld', 4));

      expect(_sentFrames.last['messageId'], 'mOld');
      expect(_cancels, hasLength(2));
      expect(_ids(), ['mN']);
    },
  );

  test(
    'S-29408 a live snapshot of an ended workout withdraws nothing',
    () async {
      _radioUp = true;
      _seed([snap('s-1', 'mA', 1)]);
      final ended = snap('s-1', 'mB', 2);
      (ended['payload']! as Map<String, Object?>)['status'] = 'completed';

      await _transport().send(ended);

      expect(_cancels, isEmpty);
      expect(_listCalls, 0);
      expect(_ids(), ['mA']);
    },
  );

  test(
    'S-29408 a live lifecycle never withdraws its own waiting copy',
    () async {
      _radioUp = true;
      _seed([lc('s-1', 'started', 'mS', 1)]);

      await _transport().send(lc('s-1', 'started', 'mS', 1));

      expect(_cancels, isEmpty);
      expect(_ids(), ['mS']);
    },
  );

  test('S-29408 a live observation or timer lists nothing', () async {
    _radioUp = true;
    final transport = _transport();

    await transport.send(obs('s-1', 'mO'));

    expect(_listCalls, 0);
  });

  test('S-29409 a frame naming no session replaces nothing', () async {
    _queue.add({'messageId': 'mA', 'type': 'session_snapshot'});
    final orphan = snap('s-1', 'mB', 2)..remove('sessionId');

    await _transport().send(orphan);

    expect(_cancels, isEmpty);
    expect(_ids(), ['mA', 'mB']);
  });

  test(
    'S-29409 an unreadable stamp is oldest on a copy, newest on the frame',
    () async {
      _queue.add({
        'messageId': 'mOld',
        'type': 'session_snapshot',
        'sessionId': 's-1',
      });
      final transport = _transport();

      await transport.send(snap('s-1', 'mA', 1));

      expect(_cancels, [
        ['mOld'],
      ]);
      expect(_ids(), ['mA']);

      final noStamp = snap('s-1', 'mB', 1)..remove('sentAt');
      _seed([snap('s-1', 'mLate', 9)]);
      await transport.send(noStamp);

      expect(_cancels.last, ['mLate']);
      expect(_ids(), ['mB']);
    },
  );

  test(
    'S-29410 a list failure is reported and the frame still queues',
    () async {
      _seed([snap('s-1', 'mA', 1)]);
      _listFails = true;

      await _transport().send(snap('s-1', 'mB', 2));

      expect(_failures, hasLength(1));
      expect(_cancels, isEmpty);
      expect(_ids(), ['mA', 'mB']);
    },
  );

  test('S-29411 a cancel failure still queues', () async {
    _seed([snap('s-1', 'mA', 1)]);
    _cancelFails = true;

    await _transport().send(snap('s-1', 'mB', 2));

    expect(_failures, hasLength(1));
    expect(_ids(), contains('mB'));
  });

  test('S-29411 a queue failure is reported once, after the cancel', () async {
    _seed([snap('s-1', 'mA', 1)]);
    _queueFails = true;

    await _transport().send(snap('s-1', 'mB', 2));

    expect(_failures, hasLength(1));
    expect(_cancels, [
      ['mA'],
    ]);
    expect(_ids(), isEmpty);
  });

  test('S-29412 two hand-overs at once leave one copy', () async {
    _listGate = Completer<void>();
    final transport = _transport();

    final first = transport.send(snap('s-1', 'm1', 1));
    final second = transport.send(snap('s-1', 'm2', 2));
    await _settle();

    expect(_listCalls, 1);

    _listGate!.complete();
    await Future.wait([first, second]);

    expect(_ids(), ['m2']);
  });

  test('S-29413 copies left by an earlier run are matched', () async {
    _seed([snap('s-watch-1', 'mOld', 0)]);
    final transport = _transport();

    await transport.send(snap('s-watch-1', 'mNew', 1));

    expect(_cancels, [
      ['mOld'],
    ]);
    expect(_ids(), ['mNew']);
  });

  test(
    'S-29415 the Kotlin source reads state and sentAt from the stored frame',
    () {
      final source = File(
        'packages/omnitrain_watch_link/android/src/main/kotlin/dev/sasha/'
        'omnitrain/watch_link/OmniTrainWatchLinkPlugin.kt',
      ).readAsStringSync().replaceAll('\r\n', '\n');

      final start = source.indexOf('private fun outstandingTransfers(');
      final end = source.indexOf('private fun cancelTransfers(');
      expect(start, greaterThan(0));
      expect(end, greaterThan(start));
      final body = source.substring(start, end);
      expect(body, contains('map.getByteArray(KEY_FRAME)'));
      expect(body, contains('decodeFrame(stored)'));
      expect(body, contains('entry[KEY_SENT_AT]'));
      expect(body, contains('entry[KEY_STATE]'));
      expect(source, contains('const val KEY_STATE = "state"'));
      expect(source, contains('const val KEY_SENT_AT = "sentAt"'));

      final mapStart = source.indexOf('private fun dataMapFor(');
      final mapEnd = source.indexOf('private fun outstandingTransfers(');
      final writer = source.substring(mapStart, mapEnd);
      expect(writer, isNot(contains('KEY_STATE')));
      expect(writer, isNot(contains('KEY_SENT_AT')));
    },
  );
}
