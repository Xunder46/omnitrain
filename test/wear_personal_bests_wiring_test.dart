// The bests owner wired into the Wear shell (plan 288, D-28808).
//
// Scenario mapping:
//   S-28830  the orchestrator routes `bests_down` to the owner; with none: false
//   S-28831  the shell restores the owner at launch
//   S-28832  the production entry point builds one owner and gives it to both
//
// Mock-first: an in-memory store, a fake radio, and never a real
// `Future.delayed` inside `testWidgets` (FakeAsync would hang on it).

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain_watch_link/omnitrain_watch_link.dart';

import 'package:omnitrain/watch/app/wear_app.dart';
import 'package:omnitrain/watch/app/wear_watch_transport.dart';
import 'package:omnitrain/watch/logging/watch_personal_bests.dart';
import 'package:omnitrain/watch/nutrition/watch_nutrition_state.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';
import 'package:omnitrain/watch/start/watch_session_start_paths.dart';
import 'package:omnitrain/watch/start/watch_sync_orchestrator.dart';

const MethodChannel _methods = MethodChannel('omnitrain/watch_link/methods');
const EventChannel _events = EventChannel('omnitrain/watch_link/events');

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

Map<String, Object?> _bestsDown({String messageId = 'msg-bests-w'}) => {
  'protocolVersion': 1,
  'messageId': messageId,
  'type': 'bests_down',
  'origin': 'phone',
  'sentAt': '2026-11-22T09:00:00Z',
  'payload': {
    'generatedAt': '2026-11-22T09:00:00Z',
    'bests': [
      {'exerciseId': 'ex-bench', 'e1rmKg': 100},
    ],
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
  WatchPersonalBests? bests,
}) {
  final engine = WatchSessionEngine(store);
  return WatchSyncOrchestrator(
    transport: _NoRadio(),
    paths: WatchSessionStartPaths(engine: engine, store: store),
    engine: engine,
    bests: bests,
  );
}

void main() {
  test('S-28830 the orchestrator routes bests_down to the owner', () async {
    final store = InMemoryWatchSessionStore();
    final bests = WatchPersonalBests(store: store);
    final withOwner = _orchestrator(store, bests: bests);

    expect(await withOwner.receive(_bestsDown()), isTrue);
    expect(bests.hasFrame, isTrue);

    final without = _orchestrator(InMemoryWatchSessionStore());
    expect(await without.receive(_bestsDown()), isFalse);
  });

  group('the shell', () {
    setUp(() {
      _messenger.setMockMethodCallHandler(_methods, (call) async {
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

    testWidgets('S-28831 the shell restores the owner at launch', (
      tester,
    ) async {
      final store = InMemoryWatchSessionStore();
      await WatchPersonalBests(store: store).applyBestsDown(_bestsDown());
      final bests = WatchPersonalBests(store: store);
      expect(bests.hasFrame, isFalse, reason: 'the premise: not restored yet');

      final transport = WearWatchTransport(link: WatchLink());
      final engine = WatchSessionEngine(store, onEmit: transport.send);
      final paths = WatchSessionStartPaths(engine: engine, store: store);
      final nutrition = WatchNutritionState(engine: engine, store: store);
      final orchestrator = WatchSyncOrchestrator(
        transport: transport,
        paths: paths,
        engine: engine,
        nutrition: nutrition,
        bests: bests,
      );
      await tester.pumpWidget(
        WearApp(
          engine: engine,
          paths: paths,
          nutrition: nutrition,
          orchestrator: orchestrator,
          transport: transport,
          bests: bests,
        ),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump();
      }

      expect(bests.hasFrame, isTrue);
    });
  });

  test('S-28832 the production entry builds one owner and wires both', () {
    final source = File('lib/watch/wear_main.dart').readAsStringSync();

    expect('WatchPersonalBests(store: store)'.allMatches(source), hasLength(1));
    expect(
      'bests: bests,'.allMatches(source),
      hasLength(2),
      reason: 'the orchestrator and the shell take the same owner',
    );
  });
}
