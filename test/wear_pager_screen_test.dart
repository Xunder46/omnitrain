// The Wear wrist's exercise pager as a widget (plan 287, D-28703..D-28708).
//
// Scenario mapping:
//   S-28710  a left swipe pages to the next exercise, with its n/N counter
//   S-28711  a right swipe pages to the previous one
//   S-28712  a swipe past either end does nothing (no wrap)
//   S-28713  a short drag and a vertical drag do not page
//   S-28714  a swipe while a work clock runs: notice, no move, notice goes
//   S-28715  one exercise: no counter, no paging
//   S-28716  Log after a swipe writes to the exercise on screen
//   S-28717  while a landing is in flight the logger ignores touches
//   S-28718  a move the user did not make shows at once, with no slide
//   S-28719  the new page slides in from the swiped side; the old one goes
//   S-28720  with reduced motion the new page only fades
//   S-28721  the shell pages the logging surface and not the rest surface
//
// Mock-first: an in-memory store and no real `Future.delayed` inside
// `testWidgets` (FakeAsync would hang on it). The pager and the logger own
// timers, so `pumpAndSettle` is never used; every wait is an explicit `pump`.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain_watch_link/omnitrain_watch_link.dart';

import 'package:omnitrain/watch/app/wear_app.dart';
import 'package:omnitrain/watch/app/wear_watch_transport.dart';
import 'package:omnitrain/watch/logging/watch_logging_pager.dart';
import 'package:omnitrain/watch/logging/watch_logging_screen.dart';
import 'package:omnitrain/watch/logging/watch_logging_state.dart';
import 'package:omnitrain/watch/logging/watch_menu_state.dart';
import 'package:omnitrain/watch/logging/watch_pager_state.dart';
import 'package:omnitrain/watch/logging/watch_rest_screen.dart';
import 'package:omnitrain/watch/nutrition/watch_nutrition_state.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';
import 'package:omnitrain/watch/start/watch_session_start_paths.dart';
import 'package:omnitrain/watch/start/watch_sync_orchestrator.dart';

const MethodChannel _methods = MethodChannel('omnitrain/watch_link/methods');
const EventChannel _events = EventChannel('omnitrain/watch_link/events');

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

/// A store whose session writes can be held, so a swipe's landing stays in
/// flight while the test acts (S-28717). Observation writes are never held.
class _GatedStore extends InMemoryWatchSessionStore {
  Completer<void>? gate;

  /// While true a session write throws, as a full disk would (S-28727).
  bool failSessionWrites = false;

  @override
  Future<T> append<T extends WatchRecord>(T record) async {
    final held = gate;
    if (held != null && record is WatchSessionRecord) await held.future;
    if (failSessionWrites && record is WatchSessionRecord) {
      throw StateError('disk full');
    }
    return super.append(record);
  }
}

List<Map<String, Object?>> _slots(int count) => [
  for (final (id, name) in const [
    ('sx-bench', 'Bench Press'),
    ('sx-row', 'Row'),
    ('sx-press', 'Press'),
  ].take(count))
    <String, Object?>{
      'sessionExerciseId': id,
      'exerciseId': 'ex-$id',
      'name': name,
      'capabilities': <String>['reps', 'sets', 'load'],
    },
];

class _Rig {
  _Rig(this.count) {
    engine = WatchSessionEngine(store, onEmit: emitted.add);
    paths = WatchSessionStartPaths(engine: engine, store: store);
    menu = WatchMenuState(engine: engine, paths: paths);
    logging = WatchLoggingState(engine: engine);
  }

  final int count;
  final _GatedStore store = _GatedStore();
  final List<Map<String, Object?>> emitted = [];
  late final WatchSessionEngine engine;
  late final WatchSessionStartPaths paths;
  late final WatchMenuState menu;
  late final WatchLoggingState logging;

  Future<void> start() => engine.createSession(
    modality: 'resistance_lifting',
    exercises: _slots(count),
  );

  int get index => engine.session!.currentExerciseIndex;

  /// The `exerciseIndex` of every `exercise_advanced` lifecycle announced so far.
  List<int> get lifecycleIndexes => [
    for (final frame in emitted)
      if (frame['type'] == 'session_lifecycle' &&
          (frame['payload']! as Map)['state'] ==
              WatchLifecycleState.exerciseAdvanced)
        (frame['payload']! as Map)['exerciseIndex']! as int,
  ];

  /// The slot ids of the sets logged so far, in order.
  List<Object?> get loggedSlots => [
    for (final entry in engine.entries)
      if (entry.kind == WatchObservationKind.set)
        entry.payload['sessionExerciseId'],
  ];
}

/// The pager alone, in a plain app. The host rebuilds only when the test asks
/// (`rebuild`), the way the shell's one-second tick does.
class _Host {
  _Host(this.rig, {this.clock, this.reduceMotion = false});

  final _Rig rig;
  final DateTime Function()? clock;
  final bool reduceMotion;
  late void Function() rebuild;

  Widget widget() => MaterialApp(
    theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
      child: child!,
    ),
    home: Scaffold(
      body: StatefulBuilder(
        builder: (context, setState) {
          rebuild = () => setState(() {});
          return WatchLoggingPager(
            menu: rig.menu,
            logging: rig.logging,
            clock: clock,
            onMoved: rebuild,
          );
        },
      ),
    ),
  );
}

Future<void> _show(WidgetTester tester, _Host host) async {
  await tester.pumpWidget(host.widget());
  await tester.pump();
}

/// Drags across the pager and lets the landing and the slide finish.
Future<void> _swipe(WidgetTester tester, double dx) async {
  await tester.drag(find.byType(WatchLoggingPager), Offset(dx, 0));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

final Finder _counter = find.byWidgetPredicate(
  (widget) =>
      widget is Text && RegExp(r'^\d+/\d+$').hasMatch(widget.data ?? ''),
);

Finder _slides() => find.descendant(
  of: find.byType(WatchLoggingPager),
  matching: find.byType(SlideTransition),
);

DateTime _t0 = DateTime.utc(2026, 11, 21, 12);

class _ShellHarness {
  _ShellHarness()
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

Future<void> _openShell(WidgetTester tester, _ShellHarness harness) async {
  await tester.pumpWidget(harness.app());
  for (var i = 0; i < 8; i++) {
    await tester.pump();
  }
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

  testWidgets('S-28710 a left swipe pages to the next exercise', (
    tester,
  ) async {
    final rig = _Rig(3);
    await rig.start();
    await _show(tester, _Host(rig));
    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);

    await _swipe(tester, -80);

    expect(rig.index, 1);
    expect(find.text('Row'), findsOneWidget);
    expect(find.text('Bench Press'), findsNothing);
    expect(find.text('2/3'), findsOneWidget);
  });

  testWidgets('S-28711 a right swipe pages to the previous exercise', (
    tester,
  ) async {
    final rig = _Rig(3);
    await rig.start();
    await rig.engine.selectExercise('sx-row');
    await _show(tester, _Host(rig));
    expect(find.text('Row'), findsOneWidget, reason: 'the premise: on page 2');

    await _swipe(tester, 80);

    expect(rig.index, 0);
    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);
  });

  testWidgets('S-28712 a swipe past either end does nothing', (tester) async {
    final rig = _Rig(3);
    await rig.start();
    final host = _Host(rig);
    await _show(tester, host);
    final before = rig.lifecycleIndexes.length;

    await _swipe(tester, 80);
    expect(rig.index, 0, reason: 'right of the first page: no wrap');

    await rig.engine.selectExercise('sx-press');
    host.rebuild();
    await tester.pump();
    final mid = rig.lifecycleIndexes.length;
    await _swipe(tester, -80);

    expect(rig.index, 2, reason: 'left of the last page: no wrap');
    expect(rig.lifecycleIndexes.length, mid);
    expect(mid, before + 1, reason: 'only the test\'s own select announced');
  });

  testWidgets('S-28713 a short drag and a vertical drag do not page', (
    tester,
  ) async {
    final rig = _Rig(3);
    await rig.start();
    await _show(tester, _Host(rig));

    await _swipe(tester, -20);
    expect(rig.index, 0, reason: 'under the 24 point threshold');

    await tester.drag(find.byType(WatchLoggingScreen), const Offset(0, 80));
    await tester.pump(const Duration(milliseconds: 300));
    expect(rig.index, 0, reason: 'a vertical drag is the value rows\'s');
  });

  testWidgets('S-28714 a swipe while a work clock runs shows the notice', (
    tester,
  ) async {
    final rig = _Rig(3);
    await rig.start();
    await rig.engine.startTimer(WatchTimerKind.elapsed);
    var now = _t0;
    await _show(tester, _Host(rig, clock: () => now));
    expect(find.text(WatchPagerCopy.lockedNotice), findsNothing);

    await _swipe(tester, -80);

    expect(rig.index, 0, reason: 'a locked swipe does not move the session');
    expect(find.text(WatchPagerCopy.lockedNotice), findsOneWidget);

    now = now.add(const Duration(milliseconds: 1600));
    await tester.pump(const Duration(milliseconds: 1700));

    expect(find.text(WatchPagerCopy.lockedNotice), findsNothing);
  });

  testWidgets('S-28715 one exercise shows no counter and does not page', (
    tester,
  ) async {
    final rig = _Rig(1);
    await rig.start();
    await _show(tester, _Host(rig));
    expect(find.text('Bench Press'), findsOneWidget);
    expect(_counter, findsNothing);

    await _swipe(tester, -80);

    expect(rig.index, 0);
    expect(_counter, findsNothing);
    expect(find.text(WatchPagerCopy.lockedNotice), findsNothing);
  });

  testWidgets('S-28716 Log after a swipe writes to the exercise on screen', (
    tester,
  ) async {
    final rig = _Rig(3);
    await rig.start();
    await _show(tester, _Host(rig));

    await _swipe(tester, -80);
    await tester.tap(find.text('Log'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(rig.loggedSlots, ['sx-row']);
  });

  testWidgets(
    'S-28717 while a landing is in flight the logger ignores touches',
    (tester) async {
      final rig = _Rig(3);
      await rig.start();
      await _show(tester, _Host(rig));
      final gate = Completer<void>();
      rig.store.gate = gate;

      await tester.drag(find.byType(WatchLoggingPager), const Offset(-80, 0));
      await tester.pump();
      await tester.tap(find.text('Log'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));

      expect(rig.index, 0, reason: 'the premise: the landing is still held');
      expect(
        rig.loggedSlots,
        isEmpty,
        reason: 'a Log now would write to the exercise being left',
      );

      gate.complete();
      rig.store.gate = null;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(rig.index, 1);

      await tester.tap(find.text('Log'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(rig.loggedSlots, ['sx-row']);
    },
  );

  testWidgets('S-28727 a swipe whose write fails leaves the logger usable', (
    tester,
  ) async {
    final rig = _Rig(3);
    await rig.start();
    await _show(tester, _Host(rig));
    rig.store.failSessionWrites = true;

    await _swipe(tester, -80);

    expect(rig.index, 0, reason: 'the move did not happen');
    expect(find.text('Bench Press'), findsOneWidget);
    rig.store.failSessionWrites = false;
    await tester.tap(find.text('Log'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      rig.loggedSlots,
      ['sx-bench'],
      reason: 'the logger still takes touches after the failed landing',
    );
  });

  testWidgets(
    'S-28722 a second swipe while a landing is in flight is ignored',
    (tester) async {
      final rig = _Rig(3);
      await rig.start();
      await _show(tester, _Host(rig));
      final gate = Completer<void>();
      rig.store.gate = gate;

      await tester.drag(find.byType(WatchLoggingPager), const Offset(-80, 0));
      await tester.pump();
      await tester.drag(find.byType(WatchLoggingPager), const Offset(-80, 0));
      await tester.pump();
      gate.complete();
      rig.store.gate = null;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(rig.index, 1, reason: 'the second swipe did not queue a move');
      expect(rig.lifecycleIndexes, [
        1,
      ], reason: 'one landing, one announcement');
    },
  );

  testWidgets(
    'S-28723 a swipe taps the wrist: a click, a heavy tap when locked',
    (tester) async {
      final haptics = <Object?>[];
      _messenger.setMockMethodCallHandler(SystemChannels.platform, (
        call,
      ) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments);
        }
        return null;
      });
      addTearDown(
        () =>
            _messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final rig = _Rig(3);
      await rig.start();
      await _show(tester, _Host(rig));

      await _swipe(tester, -80);
      expect(haptics, ['HapticFeedbackType.selectionClick']);

      await _swipe(tester, 80);
      await _swipe(tester, 80);
      expect(haptics, [
        'HapticFeedbackType.selectionClick',
        'HapticFeedbackType.selectionClick',
      ], reason: 'a swipe off the first page is not a swipe: no tap');

      await rig.engine.startTimer(WatchTimerKind.elapsed);
      await _swipe(tester, -80);
      expect(haptics.last, 'HapticFeedbackType.heavyImpact');
      expect(haptics, hasLength(3));
      await tester.pump(const Duration(milliseconds: 1700));
    },
  );

  testWidgets(
    'S-28724 only the user\'s own swipe slides, not a later move back',
    (tester) async {
      final rig = _Rig(3);
      await rig.start();
      final host = _Host(rig);
      await _show(tester, host);

      await _swipe(tester, -80);
      expect(rig.index, 1, reason: 'the premise: the swipe went to the Row');
      await tester.pump(const Duration(seconds: 1));
      await rig.engine.selectExercise('sx-press');
      host.rebuild();
      await tester.pump(const Duration(milliseconds: 300));

      await rig.engine.selectExercise('sx-row');
      host.rebuild();
      await tester.pump();

      expect(find.text('Row'), findsOneWidget);
      expect(_slides(), findsNothing, reason: 'the swipe\'s slide ended');
    },
  );

  for (final side in const [192.0, 227.0]) {
    testWidgets('S-28726 the counter fits beside a long name at ${side}dp', (
      tester,
    ) async {
      tester.view.physicalSize = Size(side, side);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final rig = _Rig(3);
      await rig.engine.createSession(
        modality: 'resistance_lifting',
        exercises: [
          for (final slot in _slots(3))
            {...slot, 'name': 'Incline Dumbbell Bench Press Close Grip'},
        ],
      );
      await _show(tester, _Host(rig));

      expect(tester.takeException(), isNull, reason: 'no overflow');
      expect(_counter, findsOneWidget);
      expect(
        tester.getTopRight(_counter).dx,
        lessThanOrEqualTo(side),
        reason: 'the counter is on the screen, the name gave way to it',
      );
    });
  }

  testWidgets('S-28725 a swipe onward and straight back leaves one logger', (
    tester,
  ) async {
    final rig = _Rig(3);
    await rig.start();
    await _show(tester, _Host(rig));

    await tester.drag(find.byType(WatchLoggingPager), const Offset(-80, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.drag(find.byType(WatchLoggingPager), const Offset(80, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(rig.index, 0);
    expect(find.text('Bench Press'), findsOneWidget);
    expect(
      find.byType(WatchLoggingScreen),
      findsOneWidget,
      reason: 'the page being left must not be mistaken for the one back',
    );
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('S-28719 the new page slides in from the swiped side', (
    tester,
  ) async {
    final rig = _Rig(3);
    await rig.start();
    await rig.engine.selectExercise('sx-row');
    await _show(tester, _Host(rig));

    await tester.drag(find.byType(WatchLoggingPager), const Offset(-80, 0));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('Press'), findsOneWidget);
    expect(
      find.byType(WatchLoggingScreen),
      findsOneWidget,
      reason: 'the old page goes at once',
    );
    final left = tester.widget<SlideTransition>(_slides());
    expect(
      left.position.value.dx,
      closeTo(1, 0.01),
      reason: 'enters from the right',
    );
    await tester.pump(const Duration(milliseconds: 400));

    await tester.drag(find.byType(WatchLoggingPager), const Offset(80, 0));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('Row'), findsOneWidget);
    final right = tester.widget<SlideTransition>(_slides());
    expect(
      right.position.value.dx,
      closeTo(-1, 0.01),
      reason: 'enters from the left',
    );
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('S-28720 with reduced motion the new page only fades', (
    tester,
  ) async {
    final rig = _Rig(3);
    await rig.start();
    await _show(tester, _Host(rig, reduceMotion: true));

    await tester.drag(find.byType(WatchLoggingPager), const Offset(-80, 0));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('Row'), findsOneWidget);
    expect(_slides(), findsNothing);
    expect(
      find.descendant(
        of: find.byType(WatchLoggingPager),
        matching: find.byType(FadeTransition),
      ),
      findsWidgets,
    );
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('S-28718 a move the user did not make shows at once, no slide', (
    tester,
  ) async {
    final harness = _ShellHarness();
    await harness.engine.createSession(
      modality: 'resistance_lifting',
      exercises: _slots(3),
    );
    await _openShell(tester, harness);
    expect(find.text('Bench Press'), findsOneWidget);

    await harness.engine.selectExercise('sx-press');
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Press'), findsOneWidget);
    expect(find.text('3/3'), findsOneWidget);
    // A move the user did not make shows at once: nothing slides in.
    expect(_slides(), findsNothing);
  });

  testWidgets('S-28721 the shell pages the logging surface, not the rest', (
    tester,
  ) async {
    final harness = _ShellHarness();
    await harness.engine.createSession(
      modality: 'resistance_lifting',
      exercises: _slots(3),
    );
    await _openShell(tester, harness);
    expect(find.byType(WatchLoggingPager), findsOneWidget);

    await tester.drag(find.byType(WatchLoggingPager), const Offset(-80, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 1));

    expect(harness.engine.session!.currentExerciseIndex, 1);
    expect(find.text('Row'), findsOneWidget);
    expect(find.text('2/3'), findsOneWidget);
    expect(find.text(WearApp.menuLabel), findsOneWidget);

    await harness.engine.startTimer(WatchTimerKind.rest);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(WatchRestScreen), findsOneWidget);
    expect(find.byType(WatchLoggingPager), findsNothing);

    await tester.drag(find.byType(WatchRestScreen), const Offset(-80, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      harness.engine.session!.currentExerciseIndex,
      1,
      reason: 'the rest surface is not paged',
    );
  });
}
