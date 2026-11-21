// The Wear logging surface fits 192 and 227 dp watches: the layout guard
// tests (plan 282, phase P2). Production lives in `lib/watch/` (phase P1);
// this file only guards it.
//
// Scenario mapping:
//   S-28201   the logging shell lays out without overflow on every effort kind
//             at 227 and 192 dp → `S-28201 <kind> at <size> dp lays out
//             without overflow`
//   S-28202   `Log` and `Menu` are on screen, inside the view, non-overlapping,
//             and at least their compact heights → `S-28202 <kind> at <size>
//             dp: Log and Menu are on screen`
//   S-28203   a session with no exercise shows no rows and no exception
//             → `S-28203 ...`
//   S-28204   the screen alone at 192x160 with the worst header (name, merged
//             countdown+sensors line, two rows) fits → `S-28204 ...`
//   S-28204b  the rows scale down inside their space when the header is
//             crowded → `S-28204b ...`
//   S-28205   the compact rows stay dialable: the step button and the crown
//             both move the numeral → `S-28205 ...`
//   S-28206   tapping `Log` at 192 dp logs exactly one set entry for the slot
//             → `S-28206 ...`
//   S-28207   the large layout (default 800x600) is unchanged: separate unit
//             text, 56 dp `Log`, at least 48 dp `Menu` → `S-28207 ...`
//   S-28207b  after a logged set the rest surface fits at 227 and 192 dp
//             → `S-28207b ...`
//   S-28208   a compact row joins its label and unit on one line →
//             `S-28208 ...`
//
// Everything here is Mock-first: an in-memory store, a fake link and never a
// real `Future.delayed` inside `testWidgets` (FakeAsync would hang on it). The
// shell and the screens each own a 1 s periodic timer, so `pumpAndSettle` is
// never used; every wait is an explicit `pump`.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain_watch_link/omnitrain_watch_link.dart';

import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/watch/app/wear_app.dart';
import 'package:omnitrain/watch/app/wear_watch_transport.dart';
import 'package:omnitrain/watch/logging/watch_logging_screen.dart';
import 'package:omnitrain/watch/logging/watch_logging_state.dart';
import 'package:omnitrain/watch/nutrition/watch_nutrition_state.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';
import 'package:omnitrain/watch/start/watch_session_start_paths.dart';
import 'package:omnitrain/watch/start/watch_sync_orchestrator.dart';
import 'package:omnitrain/watch/sensors/watch_sensor_recording.dart';
import 'package:omnitrain/watch/widgets/watch_controls.dart';

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

/// The effort kinds and the slots that declare them, as the phone writes them:
/// a slot may carry `effortKind`, and `WatchLoggingState.effortKind` honours it.
const List<Map<String, Object?>> _kinds = [
  {
    'kind': 'set',
    'capabilities': <String>['reps', 'sets', 'load'],
  },
  {
    'kind': 'timed',
    'capabilities': <String>['time', 'distance'],
  },
  {
    'kind': 'drill',
    'capabilities': <String>['hold', 'load'],
  },
  {
    'kind': 'round',
    'capabilities': <String>['rounds'],
  },
];

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

/// The two compact watch sizes every shell test guards.
const List<double> _compactSizes = [227, 192];

void _setView(WidgetTester tester, double width, double height) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);
}

/// The digit-only `Text` under a row's label: the numeral the user dials.
Finder _numeralOf(Finder row) => find.descendant(
  of: row,
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Text &&
        widget.data != null &&
        RegExp(r'^\d+$').hasMatch(widget.data!),
  ),
);

/// Deterministic clock. Sensor timestamps are asserted against this, never
/// against `DateTime.now()`.
class _Clock {
  _Clock(this.now);

  DateTime now;

  DateTime call() => now;

  void advance(Duration delta) => now = now.add(delta);
}

/// The sensor hardware, with the permissions the user granted and two streams
/// the test drives. Nothing is subscribed here, so nothing to close.
class _FakeSensorSource implements WatchSensorSource {
  WatchSensorPermission heartRateGrant = WatchSensorPermission.granted;
  WatchSensorPermission locationGrant = WatchSensorPermission.granted;

  @override
  Future<WatchSensorPermission> heartRatePermission() async => heartRateGrant;

  @override
  Future<WatchSensorPermission> locationPermission() async => locationGrant;

  @override
  Stream<double> heartRate() => const Stream<double>.empty();

  @override
  Stream<WatchLocationFix> location() => const Stream<WatchLocationFix>.empty();
}

/// The worst compact header (name, merged countdown+sensors line, two rows)
/// pumped at `192 x height` on a bare `MaterialApp`, the fixture S-28204 and
/// S-28204b share. Returns the state so a test can read its fields.
Future<WatchLoggingState> _pumpWorstHeader(
  WidgetTester tester,
  double height,
) async {
  _setView(tester, 192, height);
  final clock = _Clock(DateTime.utc(2026, 7, 13, 17));
  final source = _FakeSensorSource();
  final store = InMemoryWatchSessionStore();
  final engine = WatchSessionEngine(store, clock: clock.call);

  await engine.createSession(
    modality: 'sports',
    exercises: <Map<String, Object?>>[
      <String, Object?>{
        'sessionExerciseId': 'sx-round',
        'exerciseId': 'ex-round',
        'name': 'Bag Rounds',
        'capabilities': <String>['rounds'],
        'effortKind': 'round',
      },
    ],
  );
  await engine.startTimer(WatchTimerKind.round, plannedDurationMs: 60000);
  await engine.appendSensorSample(kind: WatchSensorKind.heartRate, value: 128);
  await engine.appendSensorSample(kind: WatchSensorKind.gps, value: 1000);
  clock.advance(const Duration(minutes: 5));

  final state = WatchLoggingState(
    engine: engine,
    clock: clock.call,
    sensors: WatchSensorRecorder(
      engine: engine,
      source: source,
      clock: clock.call,
    ),
  );

  await tester.pumpWidget(MaterialApp(home: WatchLoggingScreen(state: state)));
  await tester.pump();
  return state;
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

  for (final kind in _kinds) {
    final kindName = kind['kind'] as String;
    final capabilities = kind['capabilities'] as List<String>;

    for (final size in _compactSizes) {
      testWidgets(
        'S-28201 $kindName at ${size.round()} dp lays out without overflow',
        (tester) async {
          _setView(tester, size, size);
          final harness = _Harness();
          await _kindSession(harness, kindName, capabilities);
          await _open(tester, harness);

          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'S-28202 $kindName at ${size.round()} dp: Log and Menu are on screen',
        (tester) async {
          _setView(tester, size, size);
          final harness = _Harness();
          await _kindSession(harness, kindName, capabilities);
          await _open(tester, harness);

          final logRect = tester.getRect(
            find.widgetWithText(FilledButton, 'Log'),
          );
          final menuRect = tester.getRect(
            find.widgetWithText(TextButton, WearApp.menuLabel),
          );
          expect(logRect.top, greaterThanOrEqualTo(0));
          expect(logRect.left, greaterThanOrEqualTo(0));
          expect(logRect.right, lessThanOrEqualTo(size));
          expect(logRect.bottom, lessThanOrEqualTo(size));
          expect(menuRect.top, greaterThanOrEqualTo(0));
          expect(menuRect.left, greaterThanOrEqualTo(0));
          expect(menuRect.right, lessThanOrEqualTo(size));
          expect(menuRect.bottom, lessThanOrEqualTo(size));
          // The two share the bottom of the screen and never overlap.
          expect(logRect.bottom, lessThanOrEqualTo(menuRect.top + 0.01));
          // The compact Log keeps the compact token (40) exactly: it carries
          // `shrinkWrap`, so the padded tap target does not draw it at 48 —
          // still far below the phone's 56, which is the mutant this pair
          // catches.
          expect(
            logRect.height,
            closeTo(WatchLayout.compactButtonHeight, 0.01),
          );
          expect(logRect.height, lessThan(OmniTheme.buttonPrimaryHeight));
          expect(
            menuRect.height,
            closeTo(WatchLayout.compactMenuHeight, 0.01),
          );
          // The compact padding (2) is the whole gap between Log and Menu.
          expect(menuRect.top - logRect.bottom, closeTo(2, 0.01));

          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('S-28203 a session with no exercise lays out without overflow', (
    tester,
  ) async {
    _setView(tester, 192, 192);
    final harness = _Harness();
    await harness.engine.createSession(
      modality: 'resistance_lifting',
      exercises: <Map<String, Object?>>[],
    );
    await _open(tester, harness);

    final logButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Log'),
    );
    expect(logButton.onPressed, isNull, reason: 'nothing to log against');

    expect(tester.takeException(), isNull);
  });

  testWidgets('S-28204 the worst compact header fits 192x160', (tester) async {
    final state = await _pumpWorstHeader(tester, 160);

    expect(find.text('Bag Rounds'), findsOneWidget);
    // The countdown and the sensors share ONE line (D-28204).
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data != null &&
            widget.data!.contains('left') &&
            widget.data!.contains('bpm'),
      ),
      findsOneWidget,
    );
    for (final field in state.fields) {
      expect(find.text(field.label), findsOneWidget);
    }
    final logRect = tester.getRect(find.widgetWithText(FilledButton, 'Log'));
    expect(logRect.bottom, lessThanOrEqualTo(160));

    expect(tester.takeException(), isNull);

    // Dispose the screen so its ticker does not outlive the test.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'S-28204b the rows scale down inside their space when the header is crowded',
    (tester) async {
      final state = await _pumpWorstHeader(tester, 140);

      // At 192x140 the two rows (about 88 dp) only get the space between the
      // merged header line and the Log button (about 62 dp), so the FittedBox
      // scale-down is what keeps every row inside it.
      final mergedLine = find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data != null &&
            widget.data!.contains('left') &&
            widget.data!.contains('bpm'),
      );
      final mergedBottom = tester.getRect(mergedLine).bottom;
      final logTop = tester.getRect(
        find.widgetWithText(FilledButton, 'Log'),
      ).top;
      for (final field in state.fields) {
        final labelTop = tester.getRect(find.text(field.label)).top;
        expect(labelTop, greaterThanOrEqualTo(mergedBottom));
        final moreBottom = tester
            .getRect(find.byTooltip('More ${field.label}'))
            .bottom;
        expect(moreBottom, lessThanOrEqualTo(logTop));
      }

      expect(tester.takeException(), isNull);

      // Dispose the screen so its ticker does not outlive the test.
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('S-28205 the compact rows stay dialable: tap and crown', (
    tester,
  ) async {
    _setView(tester, 192, 192);
    final harness = _Harness();
    await _kindSession(harness, 'set', ['reps', 'sets', 'load']);
    await _open(tester, harness);

    final row = find.ancestor(
      of: find.byTooltip('More Reps'),
      matching: find.byType(Row),
    );
    expect(_numeralOf(row), findsOneWidget);
    final before = int.parse(tester.widget<Text>(_numeralOf(row)).data!);

    // Compact step buttons are 36 dp squares (D-28203); the default 48 dp
    // tap target would fail this.
    for (final tooltip in const ['More Reps', 'Less Reps']) {
      final stepSize = tester.getSize(find.byTooltip(tooltip));
      expect(stepSize.width, lessThanOrEqualTo(36.01), reason: tooltip);
      expect(stepSize.height, lessThanOrEqualTo(36.01), reason: tooltip);
    }
    // The compact ROW itself stays 44 dp (label 16 + numeral 28); a padded
    // tap target on the step buttons would stretch it to 48.
    final rowFinder = find
        .ancestor(of: find.byTooltip('More Reps'), matching: find.byType(Row))
        .first;
    expect(tester.getSize(rowFinder).height, lessThan(46));
    // The compact numeral carries the titleLarge style, not the headline one.
    expect(
      tester.widget<Text>(_numeralOf(row)).style!.fontSize,
      Theme.of(tester.element(_numeralOf(row))).textTheme.titleLarge!.fontSize,
    );

    await tester.tap(find.byTooltip('More Reps'));
    await tester.pump();
    expect(int.parse(tester.widget<Text>(_numeralOf(row)).data!), before + 1);

    // The crown's own path, as the rotary surfaces test drives it: one scroll
    // of two detents over the Reps row.
    tester.binding.handlePointerEvent(
      PointerScrollEvent(
        position: tester.getCenter(find.text('Reps')),
        scrollDelta: const Offset(0, -64),
      ),
    );
    await tester.pump();
    expect(int.parse(tester.widget<Text>(_numeralOf(row)).data!), before + 3);

    expect(tester.takeException(), isNull);
  });

  testWidgets('S-28206 tapping Log logs exactly one set at 192x192', (
    tester,
  ) async {
    _setView(tester, 192, 192);
    final harness = _Harness();
    await _kindSession(harness, 'set', ['reps', 'sets', 'load']);
    await _open(tester, harness);

    await tester.tap(find.widgetWithText(FilledButton, 'Log'));
    await tester.pump();
    await tester.pump();

    final slotEntries = harness.engine.entries
        .where((entry) => entry.payload['sessionExerciseId'] == 'sx-set')
        .toList();
    expect(slotEntries, hasLength(1));
    expect(slotEntries.single.kind, WatchObservationKind.set);
    expect(slotEntries.single.payload['kind'], 'set');

    expect(tester.takeException(), isNull);
  });

  testWidgets('S-28207 the large layout is unchanged at 800x600', (
    tester,
  ) async {
    final harness = _Harness();
    await _kindSession(harness, 'set', ['reps', 'sets', 'load']);
    await _open(tester, harness);

    // The unit keeps its own `Text`; nothing joined with the compact mark.
    expect(find.text('kg'), findsOneWidget);
    expect(find.textContaining(' · '), findsNothing);
    expect(
      tester.getRect(find.widgetWithText(FilledButton, 'Log')).height,
      OmniTheme.buttonPrimaryHeight,
    );
    expect(
      tester.getRect(find.widgetWithText(TextButton, WearApp.menuLabel)).height,
      greaterThanOrEqualTo(48),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('S-28208 a compact row joins its label and unit', (tester) async {
    _setView(tester, 192, 192);
    final harness = _Harness();
    await _kindSession(harness, 'set', ['reps', 'sets', 'load']);
    await _open(tester, harness);

    // The compact row prints `Load · kg` on one line; the unit never gets its
    // own `Text` there (S-28207 keeps the two separate at large size).
    expect(find.textContaining(' · kg'), findsOneWidget);
    expect(find.text('kg'), findsNothing);

    expect(tester.takeException(), isNull);
  });

  for (final size in _compactSizes) {
    testWidgets('S-28207b the rest surface fits at ${size.round()} dp', (
      tester,
    ) async {
      _setView(tester, size, size);
      final harness = _Harness();
      await _kindSession(harness, 'set', ['reps', 'sets', 'load']);
      await _open(tester, harness);

      await tester.tap(find.widgetWithText(FilledButton, 'Log'));
      // The logged set opens a rest; the shell's 1 s ticker is what moves the
      // surface over to it, so pump past one tick until `Next` shows.
      var sawNext = false;
      for (var i = 0; i < 8 && !sawNext; i++) {
        await tester.pump(const Duration(milliseconds: 1050));
        sawNext = find.text('Next').evaluate().isNotEmpty;
      }
      expect(find.text('Next'), findsOneWidget);

      final nextRect = tester.getRect(
        find.widgetWithText(FilledButton, 'Next'),
      );
      final menuRect = tester.getRect(
        find.widgetWithText(TextButton, WearApp.menuLabel),
      );
      expect(nextRect.top, greaterThanOrEqualTo(0));
      expect(nextRect.left, greaterThanOrEqualTo(0));
      expect(nextRect.right, lessThanOrEqualTo(size));
      expect(nextRect.bottom, lessThanOrEqualTo(size));
      expect(menuRect.top, greaterThanOrEqualTo(0));
      expect(menuRect.left, greaterThanOrEqualTo(0));
      expect(menuRect.right, lessThanOrEqualTo(size));
      expect(menuRect.bottom, lessThanOrEqualTo(size));

      expect(tester.takeException(), isNull);
    });
  }
}
