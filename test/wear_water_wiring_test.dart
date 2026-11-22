// The water owner and the request flags wired into the Wear shell (plan 290,
// D-29007..D-29009).
//
// Scenario mapping:
//   S-29040  the orchestrator routes `water_down` to the owner; with none: false
//   S-29041  the Wear transport says what it holds and wants on a routines request
//   S-29042  the bests flag is read on every request
//   S-29043  the shell restores the owner at launch
//   S-29044  the production entry point builds and wires the owner and the flags
//
// Mock-first: an in-memory store, a fake radio, and never a real
// `Future.delayed` inside `testWidgets` (FakeAsync would hang on it).

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain_watch_link/omnitrain_watch_link.dart';

import 'package:omnitrain/watch/app/wear_app.dart';
import 'package:omnitrain/watch/app/wear_watch_transport.dart';
import 'package:omnitrain/watch/nutrition/watch_nutrition_state.dart';
import 'package:omnitrain/watch/nutrition/watch_water_state.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';
import 'package:omnitrain/watch/start/watch_session_start_paths.dart';
import 'package:omnitrain/watch/start/watch_sync_orchestrator.dart';

const MethodChannel _methods = MethodChannel('omnitrain/watch_link/methods');
const EventChannel _events = EventChannel('omnitrain/watch_link/events');

final List<MethodCall> _calls = <MethodCall>[];

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

String _today() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}

Map<String, Object?> _waterDown({String messageId = 'msg-water-w'}) => {
  'protocolVersion': 1,
  'messageId': messageId,
  'type': 'water_down',
  'origin': 'phone',
  'sentAt': '2026-11-22T08:00:00Z',
  'payload': {
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'day': _today(),
    'glasses': 4,
    'appliedTapIds': <String>[],
  },
};

/// A radio that reaches no one: the orchestrator tests need only the routing.
class _NoRadio implements WatchSyncTransport {
  @override
  bool get isPhoneReachable => false;

  @override
  Future<void> requestRoutines({DateTime? since}) async {}

  @override
  Future<void> requestSnapshot() async {}

  @override
  Future<void> send(Map<String, Object?> envelope) async {}
}

WatchSyncOrchestrator _orchestrator(
  InMemoryWatchSessionStore store, {
  WatchWaterState? water,
}) {
  final engine = WatchSessionEngine(store);
  return WatchSyncOrchestrator(
    transport: _NoRadio(),
    paths: WatchSessionStartPaths(engine: engine, store: store),
    engine: engine,
    water: water,
  );
}

Map<Object?, Object?> _lastRoutinesFrame() {
  final sent = _calls.lastWhere((call) => call.method == 'sendMessage');
  return sent.arguments as Map<Object?, Object?>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _calls.clear();
    _messenger.setMockMethodCallHandler(_methods, (call) async {
      _calls.add(call);
      return switch (call.method) {
        'status' => <String, Object?>{
          'supported': true,
          'paired': true,
          'appInstalled': true,
          'activated': true,
          'reachable': true,
        },
        _ => null,
      };
    });
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

  test('S-29040 the orchestrator routes water_down to the owner', () async {
    final store = InMemoryWatchSessionStore();
    final engine = WatchSessionEngine(store);
    final water = WatchWaterState(engine: engine, store: store);
    final withOwner = _orchestrator(store, water: water);

    expect(await withOwner.receive(_waterDown()), isTrue);
    expect(water.snapshot.glasses, 4);

    final without = _orchestrator(InMemoryWatchSessionStore());
    expect(await without.receive(_waterDown()), isFalse);
  });

  group('S-29041 the routines request', () {
    test(
      'says what the wrist holds and wants, and keeps the old frame otherwise',
      () async {
        final transport = WearWatchTransport(link: WatchLink());
        addTearDown(transport.close);
        await transport.start();

        _calls.clear();
        await transport.requestRoutines(since: DateTime.utc(2026, 11, 20, 9));
        final plain = _lastRoutinesFrame();
        expect(plain.containsKey('holdsBests'), isFalse);
        expect(plain.containsKey('wantsWater'), isFalse);
        expect(plain['since'], '2026-11-20T09:00:00.000Z');

        transport.holdsBests = () => true;
        transport.wantsWater = true;
        _calls.clear();
        await transport.requestRoutines(since: DateTime.utc(2026, 11, 20, 9));
        final full = _lastRoutinesFrame();
        expect(full['holdsBests'], isTrue);
        expect(full['wantsWater'], isTrue);
        expect(full['since'], '2026-11-20T09:00:00.000Z');
        expect(full['request'], 'routines');

        transport.holdsBests = () => false;
        transport.wantsWater = false;
        _calls.clear();
        await transport.requestRoutines();
        expect(
          _lastRoutinesFrame().keys.toSet(),
          {'request'},
          reason: 'a false flag leaves its key off',
        );
      },
    );

    test('S-29042 the bests flag is read on every request', () async {
      final transport = WearWatchTransport(link: WatchLink());
      addTearDown(transport.close);
      await transport.start();
      var holds = false;
      transport.holdsBests = () => holds;

      _calls.clear();
      await transport.requestRoutines();
      expect(_lastRoutinesFrame().containsKey('holdsBests'), isFalse);

      holds = true;
      _calls.clear();
      await transport.requestRoutines();
      expect(_lastRoutinesFrame()['holdsBests'], isTrue);
    });
  });

  testWidgets('S-29043 the shell restores the owner at launch', (tester) async {
    final store = InMemoryWatchSessionStore();
    final seed = WatchWaterState(
      engine: WatchSessionEngine(store),
      store: store,
    );
    await seed.applyWaterDown(_waterDown());
    final transport = WearWatchTransport(link: WatchLink());
    final engine = WatchSessionEngine(store, onEmit: transport.send);
    final water = WatchWaterState(engine: engine, store: store);
    expect(water.snapshot.glasses, 0, reason: 'the premise: not restored yet');
    final paths = WatchSessionStartPaths(engine: engine, store: store);
    final nutrition = WatchNutritionState(engine: engine, store: store);
    final orchestrator = WatchSyncOrchestrator(
      transport: transport,
      paths: paths,
      engine: engine,
      nutrition: nutrition,
      water: water,
    );

    await tester.pumpWidget(
      WearApp(
        engine: engine,
        paths: paths,
        nutrition: nutrition,
        orchestrator: orchestrator,
        transport: transport,
        water: water,
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }

    expect(water.snapshot.glasses, 4);
  });

  test(
    'S-29044 the production entry builds and wires the owner and the flags',
    () {
      final source = File('lib/watch/wear_main.dart').readAsStringSync();

      expect(
        'WatchWaterState(engine: engine, store: store)'.allMatches(source),
        hasLength(1),
      );
      expect(
        'water: water,'.allMatches(source),
        hasLength(2),
        reason: 'orchestrator and shell',
      );
      expect('transport.wantsWater = true;'.allMatches(source), hasLength(1));
      expect(
        'transport.holdsBests = () => bests.hasFrame;'.allMatches(source),
        hasLength(1),
      );
    },
  );
}
