// The "New PR" banner and tap as widgets (plan 289, D-28902..D-28906).
//
// Scenario mapping:
//   S-28910  a record shows the banner and gives the tap once; it goes after 4 s
//   S-28911  a set that does not beat the frame shows and taps nothing
//   S-28912  the banner fits the screen at 192 and 227 dp
//   S-28913  the banner takes no touch: Log still logs under it
//   S-28914  the shell: the rest screen shows it, in the accent, announced
//
// Mock-first: an in-memory store and never a real `Future.delayed` inside
// `testWidgets` (FakeAsync would hang on it). The screens own timers, so
// `pumpAndSettle` is never used; every wait is an explicit `pump`.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain_watch_link/omnitrain_watch_link.dart';

import 'package:omnitrain/watch/app/wear_app.dart';
import 'package:omnitrain/watch/app/wear_watch_transport.dart';
import 'package:omnitrain/watch/logging/watch_logging_pager.dart';
import 'package:omnitrain/watch/logging/watch_logging_screen.dart';
import 'package:omnitrain/watch/logging/watch_logging_state.dart';
import 'package:omnitrain/watch/logging/watch_personal_bests.dart';
import 'package:omnitrain/watch/logging/watch_rest_screen.dart';
import 'package:omnitrain/watch/logging/watch_timer_haptics.dart';
import 'package:omnitrain/watch/nutrition/watch_nutrition_state.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';
import 'package:omnitrain/watch/start/watch_session_start_paths.dart';
import 'package:omnitrain/watch/start/watch_sync_orchestrator.dart';
import 'package:omnitrain/watch/widgets/watch_personal_record_banner.dart';

const MethodChannel _methods = MethodChannel('omnitrain/watch_link/methods');
const EventChannel _events = EventChannel('omnitrain/watch_link/events');

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

class _Haptics implements WatchHaptics {
  int records = 0;
  int milestones = 0;
  int pings = 0;

  @override
  void play(WatchTimerMilestone milestone) => milestones++;

  @override
  void playRestPing() => pings++;

  @override
  void playPersonalRecord() => records++;
}

Map<String, Object?> _frame(List<Map<String, Object?>> bests) => {
  'protocolVersion': 1,
  'messageId': 'msg-pr-w',
  'type': 'bests_down',
  'origin': 'phone',
  'sentAt': '2026-11-22T08:00:00Z',
  'payload': {'generatedAt': '2026-11-22T08:00:00Z', 'bests': bests},
};

final Map<String, Object?> _lowFrame = _frame([
  {'exerciseId': 'ex-x', 'e1rmKg': 1},
]);
final Map<String, Object?> _highFrame = _frame([
  {'exerciseId': 'ex-x', 'e1rmKg': 1000000, 'repsBest': 1000000},
]);

Future<void> _session(
  WatchSessionEngine engine, {
  String name = 'Exercise X',
}) => engine.createSession(
  modality: 'resistance_lifting',
  exercises: [
    {
      'sessionExerciseId': 'sx-x',
      'exerciseId': 'ex-x',
      'name': name,
      'capabilities': ['reps', 'sets', 'load'],
    },
  ],
);

/// The logging screen alone: its state on a clock the test moves, a recording
/// haptics double, a plain app around it.
class _Screen {
  _Screen._(this.engine, this.surface, this.haptics, this._elapsed);

  final WatchSessionEngine engine;
  final WatchLoggingState surface;
  final _Haptics haptics;
  final _Elapsed _elapsed;

  static Future<_Screen> start(
    Map<String, Object?> frame, {
    String name = 'Exercise X',
  }) async {
    final store = InMemoryWatchSessionStore();
    final elapsed = _Elapsed();
    final engine = WatchSessionEngine(store, clock: elapsed.call);
    await _session(engine, name: name);
    final bests = WatchPersonalBests(store: store);
    await bests.applyBestsDown(frame);
    var ids = 0;
    return _Screen._(
      engine,
      WatchLoggingState(
        engine: engine,
        clock: elapsed.call,
        idFactory: () => 'entry-${ids++}',
        bests: bests,
      ),
      _Haptics(),
      elapsed,
    );
  }

  Widget app() => MaterialApp(
    theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
    home: WatchLoggingScreen(state: surface, haptics: haptics),
  );

  /// One second on the clock and on the tester.
  Future<void> second(WidgetTester tester) async {
    _elapsed.advance(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  List<Object?> get loggedSets => [
    for (final entry in engine.entries)
      if (entry.kind == WatchObservationKind.set) entry.recordId,
  ];
}

class _Elapsed {
  DateTime now = DateTime.utc(2026, 11, 22, 9);

  DateTime call() => now;

  void advance(Duration delta) => now = now.add(delta);
}

Future<void> _tapLog(WidgetTester tester) async {
  await tester.tap(find.text('Log'));
  await tester.pump();
  await tester.pump();
}

Finder _banner() => find.text(WatchPersonalRecordCopy.label);

void main() {
  testWidgets('S-28910 a record shows the banner and the tap once, then goes', (
    tester,
  ) async {
    final screen = await _Screen.start(_lowFrame);
    await tester.pumpWidget(screen.app());
    expect(_banner(), findsNothing, reason: 'the premise');

    await _tapLog(tester);

    expect(_banner(), findsOneWidget);
    expect(find.byIcon(Icons.emoji_events), findsOneWidget);
    expect(screen.haptics.records, 1);

    for (var i = 0; i < 3; i++) {
      await screen.second(tester);
      expect(_banner(), findsOneWidget, reason: 'still up after ${i + 1} s');
    }
    await screen.second(tester);
    await screen.second(tester);
    expect(_banner(), findsNothing, reason: 'gone after the 4 s window');
    expect(screen.haptics.records, 1, reason: 'the tap is not repeated');
  });

  testWidgets('S-28911 a set that does not beat the frame shows nothing', (
    tester,
  ) async {
    final screen = await _Screen.start(_highFrame);
    await tester.pumpWidget(screen.app());

    await _tapLog(tester);

    expect(_banner(), findsNothing);
    expect(find.byIcon(Icons.emoji_events), findsNothing);
    expect(screen.haptics.records, 0);
    expect(screen.loggedSets, hasLength(1), reason: 'the set was logged');
  });

  for (final side in const [192.0, 227.0]) {
    testWidgets('S-28912 the banner fits the screen at ${side}dp', (
      tester,
    ) async {
      tester.view.physicalSize = Size(side, side);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final screen = await _Screen.start(
        _lowFrame,
        name: 'Incline Dumbbell Bench Press Close Grip',
      );
      await tester.pumpWidget(screen.app());

      await _tapLog(tester);

      expect(_banner(), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'no overflow');
      final rect = tester.getRect(_banner());
      expect(
        Rect.fromLTWH(0, 0, side, side).contains(rect.topLeft) &&
            Rect.fromLTWH(0, 0, side, side).contains(rect.bottomRight),
        isTrue,
        reason: 'the banner is on the screen: $rect',
      );
    });
  }

  testWidgets('S-28913 the banner takes no touch: Log still logs under it', (
    tester,
  ) async {
    final screen = await _Screen.start(_lowFrame);
    await tester.pumpWidget(screen.app());
    await _tapLog(tester);
    expect(_banner(), findsOneWidget, reason: 'the premise: the banner is up');
    final ignoring = tester.widget<IgnorePointer>(
      find.ancestor(of: _banner(), matching: find.byType(IgnorePointer)).first,
    );
    expect(ignoring.ignoring, isTrue);

    await _tapLog(tester);

    expect(screen.loggedSets, hasLength(2));
  });

  test(
    'S-28916 the system tap for a record is the platform vibration',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final calls = <MethodCall>[];
      _messenger.setMockMethodCallHandler(SystemChannels.platform, (
        call,
      ) async {
        calls.add(call);
        return null;
      });
      addTearDown(
        () =>
            _messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );

      const SystemWatchHaptics().playPersonalRecord();

      expect(
        [for (final call in calls) call.method],
        ['HapticFeedback.vibrate'],
      );
      expect(calls.single.arguments, isNull, reason: 'the plain vibration');
    },
  );

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

    testWidgets('S-28914 the rest screen shows the banner, in the accent', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final store = InMemoryWatchSessionStore();
      final transport = WearWatchTransport(link: WatchLink());
      final engine = WatchSessionEngine(store, onEmit: transport.send);
      await _session(engine);
      final bests = WatchPersonalBests(store: store);
      await bests.applyBestsDown(_lowFrame);
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
      expect(find.byType(WatchLoggingPager), findsOneWidget);
      expect(_banner(), findsNothing, reason: 'the premise');

      await _tapLog(tester);
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(WatchRestScreen), findsOneWidget);
      expect(
        _banner(),
        findsOneWidget,
        reason: 'one banner, on the rest screen',
      );
      final capsule = tester.widget<DecoratedBox>(
        find.ancestor(of: _banner(), matching: find.byType(DecoratedBox)).first,
      );
      final primary = Theme.of(tester.element(_banner())).colorScheme.primary;
      expect(
        (capsule.decoration as BoxDecoration).color,
        primary,
        reason: 'the capsule wears the theme accent',
      );
      expect(
        find.bySemanticsLabel(WatchPersonalRecordCopy.spoken),
        findsOneWidget,
        reason: 'a screen reader announces it',
      );
      expect(
        tester
            .getSemantics(find.bySemanticsLabel(WatchPersonalRecordCopy.spoken))
            .flagsCollection
            .isLiveRegion,
        isTrue,
        reason: 'announced when it appears',
      );
      expect(
        find.bySemanticsLabel(WatchPersonalRecordCopy.label),
        findsNothing,
        reason: 'the words and the trophy are decoration under the one label',
      );

      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(WatchLoggingPager), findsOneWidget);
      expect(
        _banner(),
        findsOneWidget,
        reason: 'still inside the window: the logging screen shows it again',
      );
      semantics.dispose();
    });
  });
}
