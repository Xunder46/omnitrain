// The Wear shell's diagnostics: what it records and the screen it opens (plan
// 293, D-29303..D-29307).
//
// Scenario mapping:
//   S-29317  the app lifecycle is recorded as scene lines
//   S-29318  the phone's reachability is recorded once per change
//   S-29319  the Start screen offers Diagnostics only with a log
//   S-29320  the button opens the screen with the headline and lines
//   S-29321  the screen fits 192 and 227 dp and scrolls
//   S-29322  the production entry point wires the log
//
// Mock-first: an in-memory store, a fake link and never a real
// `Future.delayed` inside `testWidgets` (FakeAsync would hang on it). The shell
// owns a 1 s periodic timer, so `pumpAndSettle` is never used.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain_watch_link/omnitrain_watch_link.dart';

import 'package:omnitrain/core/services/diagnostics_log.dart';
import 'package:omnitrain/core/services/diagnostics_storage.dart';
import 'package:omnitrain/watch/app/wear_app.dart';
import 'package:omnitrain/watch/app/wear_watch_transport.dart';
import 'package:omnitrain/watch/diagnostics/watch_diagnostics_screen.dart';
import 'package:omnitrain/watch/nutrition/watch_nutrition_state.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';
import 'package:omnitrain/watch/start/watch_session_start_paths.dart';
import 'package:omnitrain/watch/start/watch_start_screen.dart';
import 'package:omnitrain/watch/start/watch_sync_orchestrator.dart';

const MethodChannel _methods = MethodChannel('omnitrain/watch_link/methods');
const EventChannel _events = EventChannel('omnitrain/watch_link/events');

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

bool _reachable = false;

DiagnosticsLog _log() => DiagnosticsLog(
  storage: InMemoryDiagnosticsStorage(),
  clock: () => DateTime.utc(2026, 11, 22, 9),
);

class _Harness {
  _Harness({this.log})
    : store = InMemoryWatchSessionStore(),
      transport = WearWatchTransport(link: WatchLink(), diagnostics: log) {
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

  final DiagnosticsLog? log;
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
    diagnostics: log,
  );

  Future<void> runningSession() => engine.createSession(
    modality: 'resistance_lifting',
    exercises: [
      {
        'sessionExerciseId': 'sx-a',
        'exerciseId': 'ex-a',
        'name': 'Squat',
        'capabilities': ['reps', 'sets', 'load'],
      },
    ],
  );
}

Future<void> _open(WidgetTester tester, _Harness harness) async {
  await tester.pumpWidget(harness.app());
  for (var i = 0; i < 8; i++) {
    await tester.pump();
  }
}

List<String> _scenes(DiagnosticsLog log) => [
  for (final event in log.events())
    if (event.kind == 'scene') event.detail!,
];

List<String> _reachability(DiagnosticsLog log) => [
  for (final event in log.events())
    if (event.kind == 'reachability') event.detail!,
];

void main() {
  setUp(() {
    _reachable = false;
    _messenger.setMockMethodCallHandler(_methods, (call) async {
      return switch (call.method) {
        'status' => <String, Object?>{
          'supported': true,
          'paired': true,
          'appInstalled': true,
          'activated': true,
          'reachable': _reachable,
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

  testWidgets('S-29317 the app lifecycle is recorded as scene lines', (
    tester,
  ) async {
    final log = _log();
    final harness = _Harness(log: log);
    await _open(tester, harness);
    final before = _scenes(log).length;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    final scenes = _scenes(log).skip(before).toList();
    expect(scenes.first, 'inactive');
    expect(scenes.last, 'active');
    expect(scenes, contains('background'));
    expect(
      scenes.every(
        (detail) => const ['active', 'inactive', 'background'].contains(detail),
      ),
      isTrue,
      reason: 'only the three plain words',
    );
    expect(
      scenes.indexOf('background'),
      greaterThan(scenes.indexOf('inactive')),
    );
  });

  testWidgets('S-29318 the phone\'s reachability is recorded once per change', (
    tester,
  ) async {
    final log = _log();
    final harness = _Harness(log: log);
    await harness.runningSession();
    await _open(tester, harness);
    expect(_reachability(log), ['unreachable'], reason: 'the first answer');

    Future<void> tick({required bool reachable}) async {
      _reachable = reachable;
      await harness.transport.refreshReachability();
      await tester.pump(const Duration(seconds: 1));
    }

    await tick(reachable: false);
    await tick(reachable: true);
    await tick(reachable: true);
    await tick(reachable: true);
    await tick(reachable: false);
    await tick(reachable: false);

    expect(_reachability(log), ['unreachable', 'reachable', 'unreachable']);
  });

  testWidgets('S-29319 the Start screen offers Diagnostics only with a log', (
    tester,
  ) async {
    final withLog = _Harness(log: _log());
    await _open(tester, withLog);
    expect(find.text(WatchStartScreen.diagnosticsLabel), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    final without = _Harness();
    await _open(tester, without);
    expect(find.text(WatchStartScreen.diagnosticsLabel), findsNothing);
    expect(find.text(WatchStartScreen.logFoodLabel), findsOneWidget);
  });

  testWidgets(
    'S-29320 the button opens the screen with the headline and lines',
    (tester) async {
      final log = _log()..noteLaunch();
      final harness = _Harness(log: log);
      await _open(tester, harness);

      await tester.tap(find.text(WatchStartScreen.diagnosticsLabel));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(WatchDiagnosticsScreen), findsOneWidget);
      expect(find.text('Diagnostics'), findsWidgets);
      expect(find.textContaining('Started '), findsOneWidget);
      expect(find.textContaining('First run recorded.'), findsOneWidget);
      expect(find.textContaining(' launch previous=none'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final side in const [192.0, 227.0]) {
    testWidgets('S-29321 the screen fits ${side}dp and scrolls', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = Size(side, side);
      addTearDown(tester.view.reset);
      final log = _log()..noteLaunch();
      for (var i = 0; i < 60; i++) {
        log.note(
          'frame_received',
          session: 'session-$i',
          detail: 'observations_up $i',
        );
      }

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
          home: WatchDiagnosticsScreen(log: log),
        ),
      );

      expect(tester.takeException(), isNull, reason: 'no overflow');
      expect(find.textContaining('Started '), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  test('S-29322 the production entry point wires the log', () {
    final source = File('lib/watch/wear_main.dart').readAsStringSync();

    expect(
      'DiagnosticsLog(storage: await openDefaultDiagnosticsStorage())'
          .allMatches(source),
      hasLength(1),
    );
    expect('diagnostics.noteLaunch();'.allMatches(source), hasLength(1));
    expect(
      'diagnostics: diagnostics,'.allMatches(source),
      hasLength(2),
      reason: 'the transport and the shell',
    );
  });
}
