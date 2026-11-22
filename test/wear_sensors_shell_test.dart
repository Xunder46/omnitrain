// The Wear shell wires the session's sensors (plan 297, D-29704..D-29706).
//   S-29706 a session that becomes active starts the sensors; a beat is stored
//           and shown on the logging surface
//   S-29707 a session that ends stops them; a later beat is not stored
//   S-29708 a session restored at launch starts them
//   S-29709 an abandoned session stops them
//   S-29710 a denied source records nothing and logging still works
//   S-29711 a source that throws leaves the shell standing and logging working
//   S-29712 two sessions in a row start twice, one at a time
//   S-29713 the entry point and the shell are wired (source scan)
//   S-30008 a workout begins and ends once with the session; launch asks first (plan 300)
//   S-29714 a stop that never answers does not block the next session's start
//   S-29715 leaving the app stops the sensors
//
// Mock-first: an in-memory store, a fake link and never a real
// `Future.delayed` inside `testWidgets` (FakeAsync would hang on it). The shell
// owns a 1 s periodic timer, so `pumpAndSettle` is never used. A session that
// starts after launch reaches the shell through a frame handed to the
// transport, the path a phone's frame takes.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain_watch_link/omnitrain_watch_link.dart';

import 'package:omnitrain/watch/app/wear_app.dart';
import 'package:omnitrain/watch/app/wear_watch_transport.dart';
import 'package:omnitrain/watch/nutrition/watch_nutrition_state.dart';
import 'package:omnitrain/watch/sensors/watch_platform_workout.dart';
import 'package:omnitrain/watch/sensors/watch_sensor_recording.dart';
import 'package:omnitrain/watch/sensors/wear_sensor_source.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';
import 'package:omnitrain/watch/start/watch_session_start_paths.dart';
import 'package:omnitrain/watch/start/watch_sync_orchestrator.dart';

const MethodChannel _methods = MethodChannel('omnitrain/watch_link/methods');
const EventChannel _events = EventChannel('omnitrain/watch_link/events');

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

/// A source the test drives by hand: one controller per `heartRate()` call, so
/// each listener's life is visible.
class _FakeSensors implements WatchSensorSource {
  _FakeSensors({
    this.heart = WatchSensorPermission.granted,
    this.permissionThrows = false,
    this.cancelNeverAnswers = false,
  });

  final WatchSensorPermission heart;
  final bool permissionThrows;
  final bool cancelNeverAnswers;
  final List<StreamController<double>> controllers = [];
  int permissionAsks = 0;

  bool get listening => controllers.isNotEmpty && controllers.last.hasListener;

  @override
  Future<WatchSensorPermission> heartRatePermission() async {
    permissionAsks++;
    if (permissionThrows) throw StateError('sensor service is down');
    return heart;
  }

  @override
  Future<WatchSensorPermission> locationPermission() async =>
      WatchSensorPermission.unavailable;

  @override
  Stream<double> heartRate() {
    final controller = cancelNeverAnswers
        ? StreamController<double>(onCancel: () => Completer<void>().future)
        : StreamController<double>(onCancel: () => Future<void>.value());
    controllers.add(controller);
    return controller.stream;
  }

  @override
  Stream<WatchLocationFix> location() => const Stream.empty();
}

/// Counts how many times the shell stops the sensors.
class _CountingSensors extends WatchSessionSensors {
  _CountingSensors({required super.platform, required super.recorder});

  int stops = 0;

  @override
  Future<void> stop() {
    stops++;
    return super.stop();
  }
}

/// A platform workout that opens nothing, so the shell tests stay off channels.
class _NoWorkout implements WatchPlatformWorkoutStore {
  const _NoWorkout();

  @override
  Future<void> begin(String activityType) async {}

  @override
  Future<void> end() async {}

  @override
  Future<List<String>> inProgressActivityTypes() async => const [];
}

class _Harness {
  _Harness(this.source, {WatchPlatformWorkoutStore? workout})
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
    sensors = _CountingSensors(
      platform: WatchPlatformWorkout(store: workout ?? const _NoWorkout()),
      recorder: WatchSensorRecorder(engine: engine, source: source),
    );
  }

  final _FakeSensors source;
  final InMemoryWatchSessionStore store;
  final WearWatchTransport transport;
  late final WatchSessionEngine engine;
  late final WatchSessionStartPaths paths;
  late final WatchNutritionState nutrition;
  late final WatchSyncOrchestrator orchestrator;
  late final _CountingSensors sensors;

  Widget app() => WearApp(
    engine: engine,
    paths: paths,
    nutrition: nutrition,
    orchestrator: orchestrator,
    transport: transport,
    sensors: sensors,
  );

  Future<void> startSession() => engine.createSession(
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

  /// Hands the shell a frame the way the radio does, so it re-reads the engine:
  /// every arrival ends in the shell's `_syncTicker`, whatever the frame is (a
  /// type nobody handles is the smallest one).
  Future<void> poke(WidgetTester tester) async {
    await transport.deliver(<String, Object?>{'type': 'probe_down'});
    await _pumpSome(tester);
  }

  double? get storedBeat =>
      engine.newestSensorSamples()[WatchSensorKind.heartRate]?.value;
}

Future<void> _pumpSome(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

Future<void> _open(WidgetTester tester, _Harness harness) async {
  await tester.pumpWidget(harness.app());
  await _pumpSome(tester);
}

void main() {
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
      MockStreamHandler.inline(onListen: (arguments, events) {}),
    );
  });

  tearDown(() {
    _messenger.setMockMethodCallHandler(_methods, null);
    _messenger.setMockStreamHandler(_events, null);
  });

  testWidgets('S-29706 an active session starts the sensors and shows a beat', (
    tester,
  ) async {
    final harness = _Harness(_FakeSensors());
    await _open(tester, harness);
    expect(harness.source.controllers, isEmpty, reason: 'idle: no sensors');

    await harness.startSession();
    await harness.poke(tester);

    expect(harness.source.listening, isTrue);
    harness.source.controllers.last.add(91);
    await _pumpSome(tester);
    expect(harness.storedBeat, 91);
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('91 bpm'), findsOneWidget);
  });

  testWidgets('S-29707 an ended session stops the sensors', (tester) async {
    final harness = _Harness(_FakeSensors());
    await _open(tester, harness);
    await harness.startSession();
    await harness.poke(tester);
    expect(harness.source.listening, isTrue);

    await harness.engine.finishSession();
    await harness.poke(tester);

    expect(harness.source.listening, isFalse);
    expect(harness.source.controllers.single.hasListener, isFalse);
  });

  testWidgets('S-29707 an ended session is stopped once, not every tick', (
    tester,
  ) async {
    final harness = _Harness(_FakeSensors());
    await _open(tester, harness);
    await harness.startSession();
    await harness.poke(tester);
    expect(harness.sensors.stops, 0);

    await harness.engine.finishSession();
    await harness.poke(tester);
    await harness.poke(tester);
    await tester.pump(const Duration(seconds: 2));
    await harness.poke(tester);

    expect(harness.sensors.stops, 1);
  });

  testWidgets('S-29708 a session restored at launch starts the sensors', (
    tester,
  ) async {
    final harness = _Harness(_FakeSensors());
    await harness.startSession();

    await _open(tester, harness);

    expect(harness.source.listening, isTrue);
  });

  testWidgets('S-29709 an abandoned session stops the sensors', (tester) async {
    final harness = _Harness(_FakeSensors());
    await _open(tester, harness);
    await harness.startSession();
    await harness.poke(tester);
    expect(harness.source.listening, isTrue);

    await harness.engine.abandonSession();
    await harness.poke(tester);

    expect(harness.source.listening, isFalse);
  });

  testWidgets('S-29710 a denied source records nothing and logging works', (
    tester,
  ) async {
    final harness = _Harness(_FakeSensors(heart: WatchSensorPermission.denied));
    await _open(tester, harness);
    await harness.startSession();
    await harness.poke(tester);

    expect(harness.source.permissionAsks, 1);
    expect(harness.source.controllers, isEmpty);
    expect(harness.storedBeat, isNull);
    expect(find.text('Log'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('S-29711 a source that throws leaves the shell standing', (
    tester,
  ) async {
    final harness = _Harness(_FakeSensors(permissionThrows: true));
    await _open(tester, harness);
    await harness.startSession();
    await harness.poke(tester);

    expect(harness.source.permissionAsks, 1);
    expect(harness.source.controllers, isEmpty);
    expect(find.text('Log'), findsOneWidget);
    expect(find.text('Menu'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('S-29712 two sessions in a row start twice, one at a time', (
    tester,
  ) async {
    final harness = _Harness(_FakeSensors());
    await _open(tester, harness);
    await harness.startSession();
    await harness.poke(tester);
    final first = harness.source.controllers.single;
    expect(first.hasListener, isTrue);

    await harness.engine.finishSession();
    await harness.poke(tester);
    expect(first.hasListener, isFalse);
    await tester.pump(const Duration(seconds: 6));

    await harness.startSession();
    await harness.poke(tester);

    expect(harness.source.controllers, hasLength(2));
    expect(harness.source.controllers.last.hasListener, isTrue);
    expect(first.hasListener, isFalse, reason: 'the first stays stopped');
  });

  testWidgets('S-29712 asking again for the same session starts it once', (
    tester,
  ) async {
    final harness = _Harness(_FakeSensors());
    await _open(tester, harness);
    await harness.startSession();

    await harness.poke(tester);
    await harness.poke(tester);
    await tester.pump(const Duration(seconds: 1));
    await harness.poke(tester);

    expect(harness.source.permissionAsks, 1);
    expect(harness.source.controllers, hasLength(1));
  });

  testWidgets(
    'S-29714 a stop that never answers does not block the next start',
    (tester) async {
      final harness = _Harness(_FakeSensors(cancelNeverAnswers: true));
      await _open(tester, harness);
      await harness.startSession();
      await harness.poke(tester);
      await harness.engine.finishSession();
      await harness.poke(tester);

      await harness.startSession();
      await harness.poke(tester);
      expect(harness.source.controllers, hasLength(1), reason: 'still waiting');

      await tester.pump(const Duration(seconds: 6));
      await _pumpSome(tester);

      expect(harness.source.controllers, hasLength(2));
      expect(harness.source.controllers.last.hasListener, isTrue);

      // The shell's own stop at dispose waits on the same hung cancel: let its
      // timeout run so no timer outlives the test.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 6));
    },
  );

  testWidgets('S-29715 leaving the app stops the sensors', (tester) async {
    final harness = _Harness(_FakeSensors());
    await _open(tester, harness);
    await harness.startSession();
    await harness.poke(tester);
    expect(harness.source.listening, isTrue);

    await tester.pumpWidget(const SizedBox());
    await _pumpSome(tester);

    expect(harness.source.listening, isFalse);
  });

  testWidgets('S-30008 a workout begins and ends once with the session', (
    tester,
  ) async {
    const workoutChannel = MethodChannel(WearPlatformWorkoutStore.methodsName);
    final calls = <MethodCall>[];
    _messenger.setMockMethodCallHandler(workoutChannel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => _messenger.setMockMethodCallHandler(workoutChannel, null),
    );
    final source = _FakeSensors();
    final harness = _Harness(
      source,
      workout: WearPlatformWorkoutStore(source: source),
    );
    await _open(tester, harness);

    await harness.startSession();
    await harness.poke(tester);
    await harness.poke(tester);

    expect(calls.map((call) => call.method), ['inProgress', 'begin']);
    expect(calls.last.arguments, 'exercise_type_strength_training');

    await harness.engine.finishSession();
    await harness.poke(tester);
    await harness.poke(tester);

    expect(calls.map((call) => call.method), ['inProgress', 'begin', 'end']);
  });

  test('S-29713 the entry point and the shell are wired', () {
    final main = File('lib/watch/wear_main.dart').readAsStringSync();
    final app = File('lib/watch/app/wear_app.dart').readAsStringSync();

    expect('WearSensorSource()'.allMatches(main), hasLength(1));
    expect(
      'WearPlatformWorkoutStore(source: sensorSource)'.allMatches(main),
      hasLength(1),
    );
    expect(
      'WatchSensorRecorder(engine: engine, source: sensorSource)'.allMatches(
        main,
      ),
      hasLength(1),
    );
    expect('sensors: sensors,'.allMatches(main), hasLength(1));
    expect(app, contains('sensors: widget.sensors?.recorder,'));
    final ticker = app.indexOf('void _syncTicker() {');
    final body = app.substring(ticker, app.indexOf('}', ticker + 40));
    expect(body, contains('_syncSensors();'));
    expect(app, contains('await widget.sensors?.recoverInProgress();'));
  });
}
