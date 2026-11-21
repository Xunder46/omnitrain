// The Wear OS shell (`WearApp`): the surfaces it chooses between, and the
// frames it hands to the orchestrator.
//
// Plan: `docs/plans/2026-11-20-280-wear-os-shell-plan/2026-11-20-280-wear-os-shell-plan.md`
// (D-28007). Scenario mapping:
//   S-28020 an idle wrist shows the start surface
//   S-28021 a running session shows the logging surface, with the stopgap End
//   S-28022 a running rest shows the rest surface
//   S-28023 a snapshot request from the phone is answered with the wrist's state
//
// Everything here is Mock-first: an in-memory store, a fake link and never a
// real `Future.delayed` inside `testWidgets` (FakeAsync would hang on it).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain_watch_link/omnitrain_watch_link.dart';

import 'package:omnitrain/watch/app/wear_app.dart';
import 'package:omnitrain/watch/app/wear_watch_transport.dart';
import 'package:omnitrain/watch/nutrition/watch_nutrition_state.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';
import 'package:omnitrain/watch/start/watch_session_start_paths.dart';
import 'package:omnitrain/watch/start/watch_start_screen.dart';
import 'package:omnitrain/watch/start/watch_sync_orchestrator.dart';

const MethodChannel _methods = MethodChannel('omnitrain/watch_link/methods');
const EventChannel _events = EventChannel('omnitrain/watch_link/events');

final List<MethodCall> _calls = <MethodCall>[];

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

/// The shell's graph, built the way `wear_main.dart` builds it but over an
/// in-memory store and a fake radio.
class _Harness {
  _Harness()
    : store = InMemoryWatchSessionStore(),
      transport = WearWatchTransport(link: WatchLink()) {
    engine = WatchSessionEngine(store, onEmit: transport.send);
    paths = WatchSessionStartPaths(engine: engine, store: store);
    nutrition = WatchNutritionState(engine: engine, store: store);
    orchestrator = WatchSyncOrchestrator(
      transport: transport,
      paths: paths,
      engine: engine,
      nutrition: nutrition,
    );
  }

  final InMemoryWatchSessionStore store;
  final WearWatchTransport transport;
  late final WatchSessionEngine engine;
  late final WatchSessionStartPaths paths;
  late final WatchNutritionState nutrition;
  late final WatchSyncOrchestrator orchestrator;

  Widget app() => WearApp(
    engine: engine,
    paths: paths,
    nutrition: nutrition,
    orchestrator: orchestrator,
    transport: transport,
  );
}

Future<void> _open(WidgetTester tester, _Harness harness) async {
  await tester.pumpWidget(harness.app());
  // Restore, the status read and the first frame: all microtasks, no clock.
  for (var i = 0; i < 8; i++) {
    await tester.pump();
  }
}

void main() {
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
      // The shell listens for arrivals; the platform stream's own delivery is
      // covered by `wear_watch_transport_test.dart`, which runs with a real
      // event loop. Here the frames are handed to the transport directly.
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

  testWidgets('S-28020 an idle wrist shows the start surface', (tester) async {
    final harness = _Harness();
    await _open(tester, harness);

    expect(find.byType(WatchStartScreen), findsOneWidget);
    expect(find.text(WatchStartScreen.syncLabel), findsOneWidget);
  });

  testWidgets('S-28021 a running session shows logging and the stopgap End',
      (tester) async {
    final harness = _Harness();
    await harness.engine.createSession(
      modality: 'resistance_lifting',
      exercises: <Map<String, Object?>>[
        <String, Object?>{
          'sessionExerciseId': 'sx-bench',
          'exerciseId': 'ex-barbell-bench-press',
          'name': 'Bench Press',
          'capabilities': <String>['reps', 'sets', 'load'],
        },
      ],
    );

    await _open(tester, harness);

    expect(find.byType(WatchStartScreen), findsNothing);
    expect(find.text('Log'), findsOneWidget);
    expect(find.text(WearApp.endLabel), findsOneWidget);
  });

  testWidgets('S-28022 a running rest shows the rest surface', (tester) async {
    final harness = _Harness();
    await harness.engine.createSession(
      modality: 'resistance_lifting',
      exercises: <Map<String, Object?>>[
        <String, Object?>{
          'sessionExerciseId': 'sx-bench',
          'exerciseId': 'ex-barbell-bench-press',
          'name': 'Bench Press',
          'capabilities': <String>['reps', 'sets', 'load'],
        },
      ],
    );
    await harness.engine.startTimer(WatchTimerKind.rest);

    await _open(tester, harness);

    expect(find.text('Next'), findsOneWidget);
    expect(find.text(WearApp.endLabel), findsNothing);
  });

  testWidgets('S-28023 a snapshot request is answered with the wrist state',
      (tester) async {
    final harness = _Harness();
    await harness.engine.createSession(
      modality: 'resistance_lifting',
      exercises: <Map<String, Object?>>[
        <String, Object?>{
          'sessionExerciseId': 'sx-bench',
          'exerciseId': 'ex-barbell-bench-press',
          'name': 'Bench Press',
          'capabilities': <String>['reps', 'sets', 'load'],
        },
      ],
    );

    await _open(tester, harness);
    _calls.clear();

    // Driven through the transport's arrival lane, which is the path the event
    // channel feeds on a device. The transport's own test covers the platform
    // stream; `testWidgets`' fake clock delivers stream events only after the
    // test body, so the shell's wiring is exercised through the same lane here.
    await harness.transport.deliver(<String, Object?>{'request': 'snapshot'});
    await tester.pump();

    final sent = _calls.where((call) => call.method == 'sendMessage');
    expect(sent, hasLength(1));
    final frame = sent.single.arguments as Map<Object?, Object?>;
    expect(frame['type'], 'session_snapshot');
  });

  testWidgets('S-28024 a frame the engine owns is applied, not echoed back',
      (tester) async {
    final harness = _Harness();
    await _open(tester, harness);
    _calls.clear();

    await harness.transport.deliver(<String, Object?>{
      'protocolVersion': 1,
      'messageId': 'msg-1',
      'type': 'routines_down',
      'origin': 'phone',
      'sentAt': '2026-11-20T09:00:00Z',
      'payload': <String, Object?>{'fallbackExercises': <Object?>[]},
    });
    await tester.pump();

    // Nothing is queued for the phone and the shell is still standing.
    expect(
      _calls.where((call) => call.method == 'transferUserInfo'),
      isEmpty,
    );
    expect(find.byType(WearApp), findsOneWidget);
  });
}
