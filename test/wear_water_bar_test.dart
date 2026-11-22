// The water bar on the Wear nutrition screen (plan 291, D-29101..D-29105).
//
// Scenario mapping:
//   S-29101  the bar sits under the list, also with no foods; none without an owner
//   S-29102  plus adds a glass at once, stores one tap and clicks once
//   S-29103  minus removes one
//   S-29104  minus at zero is inert: no tap, no click
//   S-29105  the 500th tap is stored, then both buttons are inert
//   S-29106  the names a screen reader says
//   S-29107  a frame arriving while the screen is open changes the count
//   S-29108  local midnight with the screen open: the new day within a minute
//   S-29109  the bar fits 192 and 227 dp under the portion row and Log
//   S-29110  leaving the screen clears the owner's listener and the timer
//   S-29111  the shell opens the screen with its own owner
//   S-29112  a press whose write fails clicks nothing and throws nothing
//
// Mock-first: an in-memory store and never a real `Future.delayed` inside
// `testWidgets` (FakeAsync would hang on it). Every wait is an explicit `pump`.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain_watch_link/omnitrain_watch_link.dart';

import 'package:omnitrain/watch/app/wear_app.dart';
import 'package:omnitrain/watch/app/wear_watch_transport.dart';
import 'package:omnitrain/watch/nutrition/watch_nutrition_screen.dart';
import 'package:omnitrain/watch/nutrition/watch_nutrition_state.dart';
import 'package:omnitrain/watch/nutrition/watch_water_bar.dart';
import 'package:omnitrain/watch/nutrition/watch_water_state.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';
import 'package:omnitrain/watch/start/watch_session_start_paths.dart';
import 'package:omnitrain/watch/start/watch_start_screen.dart';
import 'package:omnitrain/watch/start/watch_sync_orchestrator.dart';

const MethodChannel _methods = MethodChannel('omnitrain/watch_link/methods');
const EventChannel _events = EventChannel('omnitrain/watch_link/events');

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

/// A store whose observation writes can be made to fail, as a full disk would.
class _FlakyStore extends InMemoryWatchSessionStore {
  bool failObservations = false;

  @override
  Future<T> append<T extends WatchRecord>(T record) async {
    if (failObservations && record is WatchObservationRecord) {
      throw StateError('disk full');
    }
    return super.append(record);
  }
}

class _Clock {
  /// Noon, local time, on a fixed day.
  DateTime local = DateTime(2026, 11, 22, 12);

  DateTime call() => local.toUtc();

  void advance(Duration delta) => local = local.add(delta);
}

String _dayOf(DateTime local) =>
    '${local.year.toString().padLeft(4, '0')}-'
    '${local.month.toString().padLeft(2, '0')}-'
    '${local.day.toString().padLeft(2, '0')}';

Map<String, Object?> _fixture(String name) =>
    jsonDecode(
          File(
            'watch/sync_protocol/fixtures/valid/$name.json',
          ).readAsStringSync(),
        )
        as Map<String, Object?>;

class _Rig {
  _Rig._(this.store, this.engine, this.clock, this.water, this.nutrition);

  final _FlakyStore store;
  final WatchSessionEngine engine;
  final _Clock clock;
  final WatchWaterState water;
  final WatchNutritionState nutrition;

  static Future<_Rig> start({bool foods = true, int glasses = 3}) async {
    final clock = _Clock();
    final store = _FlakyStore();
    final engine = WatchSessionEngine(store, clock: clock.call);
    final nutrition = WatchNutritionState(engine: engine, store: store);
    if (foods) await nutrition.applyFoodsDown(_fixture('foods_down'));
    final water = WatchWaterState(
      engine: engine,
      store: store,
      clock: clock.call,
    );
    final rig = _Rig._(store, engine, clock, water, nutrition);
    if (glasses >= 0) await rig.frame(glasses);
    return rig;
  }

  /// A `water_down` frame for the wrist's local today, stamped now.
  Future<bool> frame(int glasses, {String id = 'msg-water'}) =>
      water.applyWaterDown({
        'protocolVersion': 1,
        'messageId': id,
        'type': 'water_down',
        'origin': 'phone',
        'sentAt': '2026-11-22T08:00:00Z',
        'payload': {
          'generatedAt': clock.call().toIso8601String(),
          'day': _dayOf(clock.local),
          'glasses': glasses,
          'appliedTapIds': <String>[],
        },
      });

  Widget screen({bool withWater = true}) => MaterialApp(
    theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
    home: WatchNutritionScreen(
      state: nutrition,
      water: withWater ? water : null,
    ),
  );
}

Finder _count(String text) => find.descendant(
  of: find.byKey(WatchWaterBar.countKey),
  matching: find.text(text),
);

IconButton _button(WidgetTester tester, Key key) => tester.widget<IconButton>(
  find.descendant(of: find.byKey(key), matching: find.byType(IconButton)),
);

/// The platform haptic calls the test saw, by method and argument.
List<Object?> _recordHaptics() {
  final seen = <Object?>[];
  _messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'HapticFeedback.vibrate') seen.add(call.arguments);
    return null;
  });
  addTearDown(
    () => _messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return seen;
}

Future<void> _tap(WidgetTester tester, Key key) async {
  await tester.tap(find.byKey(key));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('S-29101 the bar sits under the list, also with no foods', (
    tester,
  ) async {
    final withFoods = await _Rig.start();
    await tester.pumpWidget(withFoods.screen());
    await tester.pump();

    expect(find.byType(WatchWaterBar), findsOneWidget);
    expect(find.byKey(WatchWaterBar.addKey), findsOneWidget);
    expect(find.byKey(WatchWaterBar.removeKey), findsOneWidget);
    expect(_count('3'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(WatchWaterBar)).dy,
      greaterThan(tester.getBottomLeft(find.byType(ListView)).dy - 1),
      reason: 'below the foods list, outside it',
    );
    expect(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byType(WatchWaterBar),
      ),
      findsNothing,
    );

    final empty = await _Rig.start(foods: false);
    await tester.pumpWidget(empty.screen());
    await tester.pump();
    expect(find.textContaining('No foods yet'), findsOneWidget);
    expect(find.byType(WatchWaterBar), findsOneWidget);

    await tester.pumpWidget(withFoods.screen(withWater: false));
    await tester.pump();
    expect(find.byType(WatchWaterBar), findsNothing);
    expect(find.byType(ListView), findsOneWidget, reason: 'unchanged');
  });

  testWidgets(
    'S-29102 plus adds a glass at once, stores a tap and clicks once',
    (tester) async {
      final rig = await _Rig.start();
      final haptics = _recordHaptics();
      await tester.pumpWidget(rig.screen());
      await tester.pump();

      await _tap(tester, WatchWaterBar.addKey);

      expect(_count('4'), findsOneWidget);
      final taps = rig.engine.waterLog;
      expect(taps, hasLength(1));
      expect(taps.single.payload['glassChange'], 'add');
      expect(taps.single.sessionId, startsWith('nutrition-'));
      expect(haptics, ['HapticFeedbackType.selectionClick']);
    },
  );

  testWidgets('S-29103 minus removes a glass', (tester) async {
    final rig = await _Rig.start(glasses: 4);
    final haptics = _recordHaptics();
    await tester.pumpWidget(rig.screen());
    await tester.pump();

    await _tap(tester, WatchWaterBar.removeKey);

    expect(_count('3'), findsOneWidget);
    expect(rig.engine.waterLog.single.payload['glassChange'], 'remove');
    expect(haptics, hasLength(1));
  });

  testWidgets('S-29104 minus at zero is inert: no tap and no click', (
    tester,
  ) async {
    final rig = await _Rig.start(glasses: 0);
    final haptics = _recordHaptics();
    await tester.pumpWidget(rig.screen());
    await tester.pump();

    expect(_button(tester, WatchWaterBar.removeKey).onPressed, isNull);
    await tester.tap(find.byKey(WatchWaterBar.removeKey), warnIfMissed: false);
    await tester.pump();

    expect(rig.engine.waterLog, isEmpty);
    expect(haptics, isEmpty);
    expect(_button(tester, WatchWaterBar.addKey).onPressed, isNotNull);
  });

  testWidgets('S-29105 the 500th tap is stored, then both buttons are inert', (
    tester,
  ) async {
    final rig = await _Rig.start(glasses: 0);
    for (var i = 0; i < WatchWaterLimits.tapsPerDay - 1; i++) {
      await rig.engine.logWaterGlass(
        WatchGlassChange.add,
        loggedAt: rig.clock.call(),
      );
    }
    await tester.pumpWidget(rig.screen());
    await tester.pump();
    expect(_button(tester, WatchWaterBar.addKey).onPressed, isNotNull);

    await _tap(tester, WatchWaterBar.addKey);

    expect(rig.engine.waterLog, hasLength(WatchWaterLimits.tapsPerDay));
    expect(_button(tester, WatchWaterBar.addKey).onPressed, isNull);
    expect(_button(tester, WatchWaterBar.removeKey).onPressed, isNull);
  });

  testWidgets('S-29106 the names a screen reader says', (tester) async {
    final semantics = tester.ensureSemantics();
    final rig = await _Rig.start();
    await tester.pumpWidget(rig.screen());
    await tester.pump();

    expect(
      tester
          .getSemantics(
            find.descendant(
              of: find.byKey(WatchWaterBar.addKey),
              matching: find.byType(IconButton),
            ),
          )
          .tooltip,
      'Add one glass',
    );
    expect(
      tester
          .getSemantics(
            find.descendant(
              of: find.byKey(WatchWaterBar.removeKey),
              matching: find.byType(IconButton),
            ),
          )
          .tooltip,
      'Remove one glass',
    );
    final middle = tester.getSemantics(find.byKey(WatchWaterBar.countKey));
    expect(middle.label, 'Water');
    expect(middle.value, '3 glasses');
    expect(
      find.bySemanticsLabel(RegExp(r'^3$')),
      findsNothing,
      reason: 'the digits are not a node of their own',
    );

    await rig.frame(1, id: 'msg-one');
    await tester.pump();
    expect(
      tester.getSemantics(find.byKey(WatchWaterBar.countKey)).value,
      '1 glass',
    );
    semantics.dispose();
  });

  testWidgets(
    'S-29107 a frame arriving while the screen is open changes the count',
    (tester) async {
      final rig = await _Rig.start();
      await tester.pumpWidget(rig.screen());
      await tester.pump();
      expect(_count('3'), findsOneWidget, reason: 'the premise');

      rig.clock.advance(const Duration(minutes: 1));
      await rig.frame(6, id: 'msg-six');
      await tester.pump();

      expect(_count('6'), findsOneWidget);
    },
  );

  testWidgets(
    'S-29108 local midnight with the screen open: the new day within a minute',
    (tester) async {
      final rig = await _Rig.start();
      await rig.engine.logWaterGlass(
        WatchGlassChange.add,
        loggedAt: rig.clock.call(),
      );
      await tester.pumpWidget(rig.screen());
      await tester.pump();
      expect(_count('4'), findsOneWidget, reason: 'the premise');

      rig.clock.advance(const Duration(hours: 13));
      await tester.pump(const Duration(minutes: 1));

      expect(_count('0'), findsOneWidget);
    },
  );

  for (final side in const [192.0, 227.0]) {
    testWidgets(
      'S-29109 the bar fits ${side}dp under the portion row and Log',
      (tester) async {
        tester.view.physicalSize = Size(side, side);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final rig = await _Rig.start();
        rig.nutrition.select('food-oatmeal');
        await tester.pumpWidget(rig.screen());
        await tester.pump();

        expect(tester.takeException(), isNull, reason: 'no overflow');
        expect(find.byKey(WatchNutritionScreen.logKey), findsOneWidget);
        for (final key in [WatchWaterBar.removeKey, WatchWaterBar.addKey]) {
          expect(
            tester
                .getSize(
                  find.descendant(
                    of: find.byKey(key),
                    matching: find.byType(IconButton),
                  ),
                )
                .height,
            lessThanOrEqualTo(36),
            reason: 'the compact controls on a short screen',
          );
        }
        final rect = tester.getRect(find.byType(WatchWaterBar));
        expect(
          Rect.fromLTWH(0, 0, side, side).contains(rect.topLeft) &&
              Rect.fromLTWH(0, 0, side, side).contains(rect.bottomRight),
          isTrue,
          reason: 'the bar is on the screen: $rect',
        );
      },
    );
  }

  testWidgets('S-29110 leaving the screen clears the listener and the timer', (
    tester,
  ) async {
    final rig = await _Rig.start();
    await tester.pumpWidget(rig.screen());
    await tester.pump();
    expect(rig.water.onWaterChanged, isNotNull, reason: 'the premise');

    await tester.pumpWidget(const SizedBox());

    expect(rig.water.onWaterChanged, isNull);
    expect(tester.hasRunningAnimations, isFalse);
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

    testWidgets('S-29111 the shell opens the screen with its own owner', (
      tester,
    ) async {
      final store = InMemoryWatchSessionStore();
      final transport = WearWatchTransport(link: WatchLink());
      final engine = WatchSessionEngine(store, onEmit: transport.send);
      final paths = WatchSessionStartPaths(engine: engine, store: store);
      final nutrition = WatchNutritionState(engine: engine, store: store);
      final water = WatchWaterState(engine: engine, store: store);
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

      await tester.tap(find.text(WatchStartScreen.logFoodLabel));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(WatchWaterBar), findsOneWidget);

      await _tap(tester, WatchWaterBar.addKey);

      expect(water.snapshot.glasses, 1);
      expect(engine.waterLog, hasLength(1));
    });
  });

  testWidgets(
    'S-29112 a press whose write fails clicks nothing and throws nothing',
    (tester) async {
      final rig = await _Rig.start();
      final haptics = _recordHaptics();
      await tester.pumpWidget(rig.screen());
      await tester.pump();
      rig.store.failObservations = true;

      await _tap(tester, WatchWaterBar.addKey);

      expect(tester.takeException(), isNull);
      expect(haptics, isEmpty);
      expect(_count('3'), findsOneWidget, reason: 'the count did not move');
      expect(rig.engine.waterLog, isEmpty);
    },
  );
}
