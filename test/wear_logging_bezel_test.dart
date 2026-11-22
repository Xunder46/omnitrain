// The Wear logging screen's header clears the round bezel (plan 301,
// D-30101..D-30103).
//
// Measured on the emulator first: the compact header sat left-aligned at the
// top-left, outside the visible circle of a 192 dp watch, and the first words
// of the exercise name and the heart-rate number were cut off.
//   S-30101 192 and 227 dp: the name's corners are inside the circle
//   S-30102 a long name and the counter: narrow, centred, ellipsized, inside
//   S-30103 the merged sensor line: one line, centred, inside the circle
//   S-30104 192 dp, every effort kind: no overflow, `Log` still on screen
//   S-30105 300 dp: the roomy layout is unchanged

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omnitrain/watch/logging/watch_logging_screen.dart';
import 'package:omnitrain/watch/logging/watch_logging_state.dart';
import 'package:omnitrain/watch/sensors/watch_sensor_recording.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';

class _NoSensors implements WatchSensorSource {
  @override
  Future<WatchSensorPermission> heartRatePermission() async =>
      WatchSensorPermission.unavailable;

  @override
  Future<WatchSensorPermission> locationPermission() async =>
      WatchSensorPermission.unavailable;

  @override
  Stream<double> heartRate() => const Stream<double>.empty();

  @override
  Stream<WatchLocationFix> location() => const Stream<WatchLocationFix>.empty();
}

void _setView(WidgetTester tester, double side) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(side, side);
  addTearDown(tester.view.reset);
}

/// Whether every corner of [rect] is inside the circle a round watch of
/// [side] dp shows (centred, radius `side / 2`), with [margin] dp to spare.
bool _insideCircle(Rect rect, double side, {double margin = 2}) {
  final centre = Offset(side / 2, side / 2);
  final radius = side / 2 - margin;
  return [
    rect.topLeft,
    rect.topRight,
    rect.bottomLeft,
    rect.bottomRight,
  ].every((corner) => (corner - centre).distance <= radius);
}

Future<WatchLoggingState> _pump(
  WidgetTester tester,
  double side, {
  List<String> names = const ['Squat'],
  String effortKind = 'set',
  List<String> capabilities = const ['reps', 'sets', 'load'],
  bool sensors = false,
  String? pageLabel,
  int current = 0,
}) async {
  _setView(tester, side);
  final engine = WatchSessionEngine(InMemoryWatchSessionStore());
  await engine.createSession(
    modality: 'resistance_lifting',
    exercises: <Map<String, Object?>>[
      for (var i = 0; i < names.length; i++)
        <String, Object?>{
          'sessionExerciseId': 'sx-$i',
          'exerciseId': 'ex-$i',
          'name': names[i],
          'capabilities': capabilities,
          'effortKind': effortKind,
        },
    ],
  );
  for (var i = 0; i < current; i++) {
    await engine.advanceExercise();
  }
  if (sensors) {
    await engine.appendSensorSample(
      kind: WatchSensorKind.heartRate,
      value: 130,
    );
    await engine.appendSensorSample(kind: WatchSensorKind.gps, value: 12345);
  }
  final state = WatchLoggingState(
    engine: engine,
    sensors: sensors
        ? WatchSensorRecorder(engine: engine, source: _NoSensors())
        : null,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      home: WatchLoggingScreen(state: state, pageLabel: pageLabel),
    ),
  );
  await tester.pump();
  return state;
}

void main() {
  for (final side in const [192.0, 227.0]) {
    testWidgets('S-30101 ${side}dp the name is inside the circle', (
      tester,
    ) async {
      await _pump(tester, side);

      final rect = tester.getRect(find.text('Squat'));
      expect(_insideCircle(rect, side), isTrue, reason: '$rect');
      expect(
        rect.top,
        greaterThanOrEqualTo(WatchLoggingScreen.compactTopInset),
      );
      expect((rect.center.dx - side / 2).abs(), lessThan(1), reason: 'centred');
      expect(tester.takeException(), isNull);
    });

    testWidgets('S-30102 ${side}dp a long name and the counter', (
      tester,
    ) async {
      const long = 'Single Arm Dumbbell Romanian Deadlift';
      await _pump(
        tester,
        side,
        names: const ['Squat', long, 'Row'],
        pageLabel: '2/3',
        current: 1,
      );

      final name = tester.getRect(find.text(long));
      final counter = tester.getRect(find.text('2/3'));
      final row = name.expandToInclude(counter);
      expect(
        row.width,
        lessThanOrEqualTo(WatchLoggingScreen.compactNameMaxWidth),
      );
      expect((row.center.dx - side / 2).abs(), lessThan(1), reason: 'centred');
      expect(_insideCircle(row, side), isTrue, reason: '$row');
      expect(find.text('2/3'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text(long)).overflow,
        TextOverflow.ellipsis,
        reason: 'the name ellipsizes, it is never wrapped or overflowed',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('S-30103 ${side}dp the merged sensor line is inside', (
      tester,
    ) async {
      await _pump(tester, side, sensors: true);

      final line = find.textContaining('130 bpm');
      expect(line, findsOneWidget);
      final rect = tester.getRect(line);
      expect(
        rect.width,
        lessThanOrEqualTo(WatchLoggingScreen.compactSensorMaxWidth),
      );
      expect((rect.center.dx - side / 2).abs(), lessThan(1), reason: 'centred');
      expect(_insideCircle(rect, side), isTrue, reason: '$rect');
      expect(
        tester.getRect(find.text('Squat')).bottom,
        lessThanOrEqualTo(rect.top + 1),
        reason: 'the line sits under the name',
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final kind in const [
    ('set', ['reps', 'sets', 'load']),
    ('timed', ['time', 'distance']),
    ('drill', ['hold', 'load']),
    ('round', ['rounds']),
  ]) {
    testWidgets('S-30104 192dp ${kind.$1}: no overflow, Log on screen', (
      tester,
    ) async {
      await _pump(
        tester,
        192,
        effortKind: kind.$1,
        capabilities: kind.$2,
        sensors: true,
      );

      expect(tester.takeException(), isNull, reason: 'no overflow');
      final log = tester.getRect(
        find.ancestor(
          of: find.text('Log'),
          matching: find.byWidgetPredicate(
            (widget) => widget is FilledButton || widget is OutlinedButton,
          ),
        ),
      );
      expect(log.height, 40);
      expect(log.top, greaterThanOrEqualTo(0));
      expect(log.bottom, 190, reason: 'the 2 dp bottom padding is unchanged');
    });
  }

  testWidgets('S-30105 300dp the roomy layout is unchanged', (tester) async {
    await _pump(tester, 300, sensors: true);

    final rect = tester.getRect(find.text('Squat'));
    final line = tester.getRect(find.textContaining('130 bpm'));
    expect(line.left, WatchLoggingScreen.surfaceInset, reason: 'left-aligned');
    expect(rect.left, WatchLoggingScreen.surfaceInset);
    expect(rect.top, lessThanOrEqualTo(8));
    expect(tester.takeException(), isNull);
  });
}
