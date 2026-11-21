// The wiring tests for plan 283a: the phone's settings reach the wrist's
// logging surfaces (phase P2t). Production lives in `lib/watch/` (phase P2);
// this file only guards it.
//
// Scenario mapping:
//   S-28310   the orchestrator routes `preferences_down` to the settings owner
//             → `S-28310 ...`
//   S-28311   the logging state reads the phone's unit on every access
//             → `S-28311 ...`
//   S-28312   the shell restores the stored settings at launch → `S-28312 ...`
//   S-28312b  a copy that arrives while the session runs shows on the next
//             repaint → `S-28312b ...`
//   S-28313   the rest ping interval follows the phone → `S-28313 ...`
//
// The envelope helper is copied from `test/watch_phone_preferences_test.dart`
// (a test file is never imported); the shell harness is copied from
// `test/wear_logging_layout_test.dart` and gains the `preferences` field.
//
// Never `pumpAndSettle` and never a real `Future.delayed` inside `testWidgets`
// (the shell owns a 1 s periodic ticker; FakeAsync). Every wait is an explicit
// `pump`.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/utils/unit_formatter.dart';
import 'package:omnitrain_watch_link/omnitrain_watch_link.dart';

import 'package:omnitrain/watch/app/wear_app.dart';
import 'package:omnitrain/watch/app/wear_watch_transport.dart';
import 'package:omnitrain/watch/logging/watch_logging_state.dart';
import 'package:omnitrain/watch/logging/watch_metric_stepping.dart';
import 'package:omnitrain/watch/logging/watch_rest_screen.dart';
import 'package:omnitrain/watch/nutrition/watch_nutrition_state.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';
import 'package:omnitrain/watch/start/watch_phone_preferences.dart';
import 'package:omnitrain/watch/start/watch_session_start_paths.dart';
import 'package:omnitrain/watch/start/watch_sync_orchestrator.dart';

const String _t1 = '2026-09-25T09:00:00Z';
const String _t2 = '2026-09-25T10:00:00Z';

/// A `preferences_down` envelope, the helper from
/// `test/watch_phone_preferences_test.dart`: protocolVersion 1, a phone
/// origin, and a payload whose optional keys are present only when given.
Map<String, Object?> _envelope({
  String messageId = 'msg-prefs',
  Object? generatedAt,
  Object? effortRatingPrompt,
  Object? restPingSeconds,
  String? accentColorHex,
  String? weightUnit,
  String? distanceUnit,
}) => {
  'protocolVersion': 1,
  'messageId': messageId,
  'type': 'preferences_down',
  'origin': 'phone',
  'sentAt': '2026-09-25T09:00:00Z',
  'payload': {
    'generatedAt': ?generatedAt,
    'effortRatingPrompt': ?effortRatingPrompt,
    'restPingSeconds': ?restPingSeconds,
    'accentColorHex': ?accentColorHex,
    'weightUnit': ?weightUnit,
    'distanceUnit': ?distanceUnit,
  },
};

const MethodChannel _methods = MethodChannel('omnitrain/watch_link/methods');
const EventChannel _events = EventChannel('omnitrain/watch_link/events');

final List<MethodCall> _calls = <MethodCall>[];

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

/// A transport that records what it was asked for and never invents a reply,
/// the way `test/watch_session_start_test.dart` builds one.
class _Transport implements WatchSyncTransport {
  @override
  bool isPhoneReachable = false;

  @override
  Future<void> requestRoutines({DateTime? since}) async {}

  @override
  Future<void> requestSnapshot() async {}

  @override
  Future<void> send(Map<String, Object?> envelope) async {}
}

/// The shell's graph, built the way `wear_main.dart` builds it but over an
/// in-memory store and a fake radio. When no owner is handed in, one fresh
/// `WatchPhonePreferences` is built over the store and given to BOTH the
/// orchestrator and the shell, exactly as `wear_main.dart` does.
class _Harness {
  factory _Harness({
    InMemoryWatchSessionStore? store,
    WatchPhonePreferences? preferences,
  }) {
    final effectiveStore = store ?? InMemoryWatchSessionStore();
    return _Harness._(
      effectiveStore,
      preferences ?? WatchPhonePreferences(store: effectiveStore),
    );
  }

  _Harness._(this.store, this.preferences)
    : transport = WearWatchTransport(link: WatchLink()) {
    engine = WatchSessionEngine(store, onEmit: transport.send);
    paths = WatchSessionStartPaths(engine: engine, store: store);
    nutrition = WatchNutritionState(engine: engine, store: store);
    orchestrator = WatchSyncOrchestrator(
      transport: transport,
      paths: paths,
      engine: engine,
      nutrition: nutrition,
      preferences: preferences,
    );
  }

  final InMemoryWatchSessionStore store;
  final WearWatchTransport transport;
  final WatchPhonePreferences preferences;
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
    preferences: preferences,
  );
}

Future<void> _open(WidgetTester tester, _Harness harness) async {
  await tester.pumpWidget(harness.app());
  // Restore, the status read and the first frame: all microtasks, no clock.
  for (var i = 0; i < 8; i++) {
    await tester.pump();
  }
}

/// A running `set` session with the load-capable slot, as the phone writes it.
Future<void> _kindSession(
  _Harness harness,
  String kind,
  List<String> capabilities,
) async {
  await harness.engine.createSession(
    modality: 'resistance_lifting',
    exercises: <Map<String, Object?>>[
      <String, Object?>{
        'sessionExerciseId': 'sx-$kind',
        'exerciseId': 'ex-$kind',
        'name': 'Slot $kind',
        'capabilities': capabilities,
        'effortKind': kind,
      },
    ],
  );
}

void _setView(WidgetTester tester, double width, double height) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);
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
      // The shell listens for arrivals; here the frames are handed to the
      // orchestrator directly.
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
    'S-28310 the orchestrator routes preferences_down to the settings owner',
    () async {
      final prefs = WatchPhonePreferences(store: InMemoryWatchSessionStore());
      final transport = _Transport();
      final engine = WatchSessionEngine(InMemoryWatchSessionStore());
      final orchestrator = WatchSyncOrchestrator(
        transport: transport,
        paths: WatchSessionStartPaths(
          engine: engine,
          store: InMemoryWatchSessionStore(),
        ),
        engine: engine,
        preferences: prefs,
      );

      // A valid copy applies and is stored on the owner.
      expect(
        await orchestrator.receive(
          _envelope(
            messageId: 'msg-t2',
            generatedAt: _t2,
            effortRatingPrompt: false,
            restPingSeconds: 0,
            weightUnit: 'lbs',
          ),
        ),
        isTrue,
      );
      expect(prefs.units.weightUnit, 'lbs');

      // An older copy is dropped: still true to the newer one.
      expect(
        await orchestrator.receive(
          _envelope(
            messageId: 'msg-t1',
            generatedAt: _t1,
            effortRatingPrompt: false,
            restPingSeconds: 0,
            weightUnit: 'kg',
          ),
        ),
        isFalse,
      );
      expect(prefs.units.weightUnit, 'lbs');

      // An orchestrator without an owner has no use for a valid copy either.
      final ownerless = WatchSyncOrchestrator(
        transport: _Transport(),
        paths: WatchSessionStartPaths(
          engine: WatchSessionEngine(InMemoryWatchSessionStore()),
          store: InMemoryWatchSessionStore(),
        ),
        engine: WatchSessionEngine(InMemoryWatchSessionStore()),
      );
      expect(
        await ownerless.receive(
          _envelope(
            messageId: 'msg-t3',
            generatedAt: _t2,
            effortRatingPrompt: false,
            restPingSeconds: 0,
            weightUnit: 'lbs',
          ),
        ),
        isFalse,
      );
      expect(
        prefs.units.weightUnit,
        'lbs',
        reason: 'the ownerless one stored nothing',
      );
    },
  );

  test(
    'S-28311 the logging state reads the phone\'s unit on every access',
    () async {
      final prefs = WatchPhonePreferences(store: InMemoryWatchSessionStore());
      final engine = WatchSessionEngine(InMemoryWatchSessionStore());
      await engine.createSession(
        modality: 'resistance_lifting',
        exercises: <Map<String, Object?>>[
          <String, Object?>{
            'sessionExerciseId': 'sx-bench',
            'exerciseId': 'ex-bench',
            'name': 'Bench',
            'capabilities': <String>['reps', 'sets', 'load'],
          },
        ],
      );
      final state = WatchLoggingState(
        engine: engine,
        unitsProvider: () => prefs.units,
      );

      state.adjust(WatchMetricKey.weight, 4);
      final field = state.fields.firstWhere(
        (field) => field.metricKey == WatchMetricKey.weight,
      );
      expect(field.value, isNonZero, reason: 'the dial left a load');
      expect(field.unitLabel, UnitFormatter.weightLabelForUnit('kg'));
      expect(
        field.displayValue,
        UnitFormatter.fromKilograms(field.value, 'kg').toStringAsFixed(1),
        reason: 'kg reads canonical',
      );

      expect(
        await prefs.applyPreferencesDown(
          _envelope(
            messageId: 'msg-lbs',
            generatedAt: _t2,
            effortRatingPrompt: false,
            restPingSeconds: 0,
            weightUnit: 'lbs',
          ),
        ),
        isTrue,
      );

      final nowLbs = state.fields.firstWhere(
        (field) => field.metricKey == WatchMetricKey.weight,
      );
      expect(
        nowLbs.value,
        field.value,
        reason: 'the canonical load is unchanged',
      );
      expect(nowLbs.unitLabel, UnitFormatter.weightLabelForUnit('lbs'));
      expect(
        nowLbs.displayValue,
        UnitFormatter.fromKilograms(nowLbs.value, 'lbs').toStringAsFixed(1),
        reason: 'the same canonical load prints in lb',
      );

      // The fixed path still works: no provider, the built-in units.
      final fixedEngine = WatchSessionEngine(InMemoryWatchSessionStore());
      await fixedEngine.createSession(
        modality: 'resistance_lifting',
        exercises: <Map<String, Object?>>[
          <String, Object?>{
            'sessionExerciseId': 'sx-fixed',
            'exerciseId': 'ex-fixed',
            'name': 'Fixed',
            'capabilities': <String>['reps', 'sets', 'load'],
          },
        ],
      );
      final fixed = WatchLoggingState(
        engine: fixedEngine,
        units: const WatchUnitPreferences(weightUnit: 'lbs'),
      );
      final fixedField = fixed.fields.firstWhere(
        (field) => field.metricKey == WatchMetricKey.weight,
      );
      expect(fixedField.unitLabel, UnitFormatter.weightLabelForUnit('lbs'));
      expect(
        fixedField.displayValue,
        UnitFormatter.fromKilograms(fixedField.value, 'lbs').toStringAsFixed(1),
      );
    },
  );

  testWidgets('S-28312 the shell restores the stored settings at launch', (
    tester,
  ) async {
    _setView(tester, 192, 192);
    // The copy is stored first, by an owner the shell never sees, over the
    // store the shell is then built on; the shell's own fresh owner must read
    // it back in `_boot`.
    final store = InMemoryWatchSessionStore();
    final stored = WatchPhonePreferences(store: store);
    expect(
      await stored.applyPreferencesDown(
        _envelope(
          messageId: 'msg-lbs',
          generatedAt: _t2,
          effortRatingPrompt: false,
          restPingSeconds: 0,
          weightUnit: 'lbs',
        ),
      ),
      isTrue,
    );

    final harness = _Harness(store: store);
    expect(
      harness.preferences.units.weightUnit,
      'kg',
      reason: 'the copy is in the store; the owner has not restored yet',
    );
    await _kindSession(harness, 'set', ['reps', 'sets', 'load']);
    await _open(tester, harness);

    // The compact row joins label and unit on one line (`Load · lbs`).
    expect(find.textContaining(' · lb'), findsOneWidget);
    expect(find.textContaining(' · kg'), findsNothing);

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'S-28312b a copy that arrives while the session runs shows on the next repaint',
    (tester) async {
      _setView(tester, 192, 192);
      final harness = _Harness();
      await _kindSession(harness, 'set', ['reps', 'sets', 'load']);
      await _open(tester, harness);

      expect(find.textContaining(' · kg'), findsOneWidget);
      expect(find.textContaining(' · lb'), findsNothing);

      expect(
        await harness.orchestrator.receive(
          _envelope(
            messageId: 'msg-live',
            generatedAt: _t2,
            effortRatingPrompt: false,
            restPingSeconds: 0,
            weightUnit: 'lbs',
          ),
        ),
        isTrue,
      );
      // The shell's 1 s ticker is what repaints the rows.
      await tester.pump(const Duration(seconds: 1));

      expect(find.textContaining(' · lb'), findsOneWidget);
      expect(find.textContaining(' · kg'), findsNothing);

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('S-28313 the rest ping interval follows the phone', (
    tester,
  ) async {
    _setView(tester, 192, 192);
    final store = InMemoryWatchSessionStore();
    final stored = WatchPhonePreferences(store: store);
    expect(
      await stored.applyPreferencesDown(
        _envelope(
          messageId: 'msg-ping',
          generatedAt: _t2,
          effortRatingPrompt: false,
          restPingSeconds: 60,
        ),
      ),
      isTrue,
    );

    final harness = _Harness(store: store);
    await _kindSession(harness, 'set', ['reps', 'sets', 'load']);
    await _open(tester, harness);

    await tester.tap(find.widgetWithText(FilledButton, 'Log'));
    // The logged set opens a rest; pump past the shell's 1 s ticks until it
    // shows, as `test/wear_logging_layout_test.dart` (S-28207b) does.
    var sawNext = false;
    for (var i = 0; i < 8 && !sawNext; i++) {
      await tester.pump(const Duration(milliseconds: 1050));
      sawNext = find.text('Next').evaluate().isNotEmpty;
    }
    expect(find.text('Next'), findsOneWidget);

    expect(
      tester
          .widget<WatchRestScreen>(find.byType(WatchRestScreen))
          .state
          .units
          .restPingSeconds,
      60,
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('S-28313 a shell with no copy rests at 0', (tester) async {
    _setView(tester, 192, 192);
    final harness = _Harness();
    await _kindSession(harness, 'set', ['reps', 'sets', 'load']);
    await _open(tester, harness);

    await tester.tap(find.widgetWithText(FilledButton, 'Log'));
    var sawNext = false;
    for (var i = 0; i < 8 && !sawNext; i++) {
      await tester.pump(const Duration(milliseconds: 1050));
      sawNext = find.text('Next').evaluate().isNotEmpty;
    }
    expect(find.text('Next'), findsOneWidget);

    expect(
      tester
          .widget<WatchRestScreen>(find.byType(WatchRestScreen))
          .state
          .units
          .restPingSeconds,
      0,
    );

    expect(tester.takeException(), isNull);
  });
}
