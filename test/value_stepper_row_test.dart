// `ValueStepperRow` — the reps/weight `−  <value>  +` row.
//
// Plan: `docs/plans/2026-10-15-38b-reps-screen-plan/2026-10-15-38b-reps-screen-plan.md`.
// Scenario mapping:
//   S-4241 reps: one step per tap, floors at 0, ceilings at 999
//   S-4242 weight: 2.5 kg / 5 lb steps in the shown unit, floors at -200
//   S-4243 two taps compose through the pending value
//   S-4244 press and hold repeats at 200 ms and stores once, on the lift
//   S-4245 the hold speeds up to 100 ms, then 50 ms
//   S-4246 a read-only row does nothing; an enabled number still opens the popup
//   S-4247 48 dp targets, tooltips, a full-width row that fits a short phone
//   S-4248 a cancelled hold commits once; a dispose mid-hold leaves no timer
//   S-4258 a step past the popup's own ceiling is a no-op
//   S-4259 a lock mid-hold drops the pending intent without a store
//   S-4326 the row sits in a 20/4-margined, shadowless `OmniSurface`
//   S-4413 duration mode: the value stays an int through the editor (`03:00`),
//          one tap is 15 s, `min: 15` floors the step, `MetricStepCalc` keeps
//          the ten-hour ceiling, `onEditorTap` replaces the generic popup
//   S-4704 the ceiling is 10 h (36000 s): `+` at 3600 writes 3615, `+` at
//          36000 writes nothing
//   S-4705 a duration past an hour is drawn h:mm:ss, below it mm:ss, and the
//          widest form (`10:00:00`) still fits a 320 x 568 phone
//   S-4707 the label sits centred directly under the number, the `tap to type`
//          hint under the label, and a locked row hides the hint
//
// FakeAsync only: the repeat timer runs on `tester.pump(Duration)`, never on a
// real delay.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/widgets/layout/omni_surface.dart';
import 'package:omnitrain/widgets/session/inline_metric_editor.dart';
import 'package:omnitrain/widgets/session/value_stepper_row.dart';

/// Flutter's long-press deadline: the first repeat tick lands here.
const _longPressDelay = Duration(milliseconds: 500);

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

Future<void> _pumpRow(
  WidgetTester tester, {
  String metricType = 'reps',
  required num currentValue,
  String unitLabel = 'REPS',
  double step = 1,
  bool isReadOnly = false,
  num? min,
  VoidCallback? onEditorTap,
  required ValueChanged<dynamic> onValueChanged,
}) {
  return tester.pumpWidget(
    _host(
      ValueStepperRow(
        metricType: metricType,
        currentValue: currentValue,
        unitLabel: unitLabel,
        step: step,
        isReadOnly: isReadOnly,
        min: min,
        onEditorTap: onEditorTap,
        onValueChanged: onValueChanged,
      ),
    ),
  );
}

/// The duration row as the round screen configures it: seconds, 15 s a step,
/// floored at 15 s.
Future<void> _pumpDurationRow(
  WidgetTester tester, {
  required num currentValue,
  bool isReadOnly = false,
  VoidCallback? onEditorTap,
  required ValueChanged<dynamic> onValueChanged,
}) {
  return _pumpRow(
    tester,
    metricType: 'duration',
    currentValue: currentValue,
    unitLabel: 'ROUND LENGTH',
    step: 15,
    isReadOnly: isReadOnly,
    min: 15,
    onEditorTap: onEditorTap,
    onValueChanged: onValueChanged,
  );
}

Finder _plus(String metricType) =>
    find.byKey(Key('value-stepper-plus-$metricType'));

Finder _minus(String metricType) =>
    find.byKey(Key('value-stepper-minus-$metricType'));

/// Hosts the row at the top-left of the body, so its outer margins are
/// measurable against the body's own edges.
Future<void> _pumpBoxedRow(
  WidgetTester tester, {
  String metricType = 'reps',
  num currentValue = 10,
  String unitLabel = 'REPS',
  double step = 1,
  bool isReadOnly = false,
  ValueChanged<dynamic>? onValueChanged,
}) {
  return tester.pumpWidget(
    _host(
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ValueStepperRow(
            metricType: metricType,
            currentValue: currentValue,
            unitLabel: unitLabel,
            step: step,
            isReadOnly: isReadOnly,
            onValueChanged: onValueChanged ?? (_) {},
          ),
        ],
      ),
    ),
  );
}

/// Pumps a reps row with the hint switch and the number-tap probe exposed.
Future<void> _pumpHintRow(
  WidgetTester tester, {
  num currentValue = 10,
  bool showTapHint = true,
  bool isReadOnly = false,
  VoidCallback? onEditorTap,
  VoidCallback? onNumberTap,
  required ValueChanged<dynamic> onValueChanged,
}) {
  return tester.pumpWidget(
    _host(
      ValueStepperRow(
        metricType: 'reps',
        currentValue: currentValue,
        unitLabel: 'REPS',
        isReadOnly: isReadOnly,
        onEditorTap: onEditorTap,
        showTapHint: showTapHint,
        onNumberTap: onNumberTap,
        onValueChanged: onValueChanged,
      ),
    ),
  );
}

/// The number as drawn — the first [Text] inside the editor is the value.
String _shownNumber(WidgetTester tester) {
  final text = tester.widget<Text>(
    find
        .descendant(
          of: find.byType(InlineMetricEditor),
          matching: find.byType(Text),
        )
        .first,
  );
  return text.data!;
}

/// The number [Text] as drawn (the first inside the editor).
Finder _numberText() => find
    .descendant(of: find.byType(InlineMetricEditor), matching: find.byType(Text))
    .first;

/// The `tap to type` hint line, keyed by the editor.
Finder _tapHint() => find.byKey(const Key('tap-hint'));

/// S-4707 shape: the label centred directly under the number, the hint under
/// the label. Relations only — the test font is wider than the real one.
void _expectLabelUnderNumber(
  WidgetTester tester,
  String label, {
  bool withHint = true,
}) {
  final number = tester.getRect(_numberText());
  final unit = tester.getRect(find.text(label));
  expect(
    unit.center.dx,
    closeTo(number.center.dx, 1),
    reason: 'the label is centred under the number',
  );
  expect(
    unit.top,
    greaterThanOrEqualTo(number.bottom - 0.01),
    reason: 'the label is not beside the number',
  );
  expect(
    unit.top,
    lessThanOrEqualTo(number.bottom + 4),
    reason: 'the label sits directly under the number',
  );

  if (!withHint) {
    expect(_tapHint(), findsNothing);
    return;
  }
  expect(tester.widget<Text>(_tapHint()).data, 'tap to type');
  final hint = tester.getRect(_tapHint());
  expect(
    hint.top,
    greaterThanOrEqualTo(unit.bottom - 0.01),
    reason: 'the hint is under the label',
  );
  expect(
    hint.top,
    lessThanOrEqualTo(unit.bottom + 4),
    reason: 'the hint sits directly under the label',
  );
  expect(
    hint.center.dx,
    closeTo(unit.center.dx, 1),
    reason: 'the hint is centred with the label',
  );
}

/// How many ticks have fired [elapsedMs] after the pointer went down, derived
/// from the row's own schedule so the assertions cannot drift from it.
int _ticksBy(int elapsedMs) {
  var ticks = 1;
  var at = _longPressDelay.inMilliseconds;
  while (at + ValueStepperRow.repeatInterval(ticks).inMilliseconds <=
      elapsedMs) {
    at += ValueStepperRow.repeatInterval(ticks).inMilliseconds;
    ticks += 1;
  }
  return ticks;
}

void main() {
  group('S-4241 reps row', () {
    testWidgets('a tap steps by one and reports an int', (tester) async {
      final calls = <dynamic>[];
      await _pumpRow(tester, currentValue: 10, onValueChanged: calls.add);

      await tester.tap(_plus('reps'));
      await tester.pump();
      expect(calls, <dynamic>[11]);
      expect(calls.single, isA<int>());
      expect(_shownNumber(tester), '11');

      // The parent applied the value and rebuilt: the row follows.
      await _pumpRow(tester, currentValue: 11, onValueChanged: calls.add);
      await tester.tap(_minus('reps'));
      await tester.pump();
      expect(calls, <dynamic>[11, 10]);
    });

    testWidgets('minus at zero and plus at 999 call nothing', (tester) async {
      final atZero = <dynamic>[];
      await _pumpRow(tester, currentValue: 0, onValueChanged: atZero.add);
      await tester.tap(_minus('reps'));
      await tester.pump();
      expect(atZero, isEmpty);

      final atCeiling = <dynamic>[];
      await _pumpRow(tester, currentValue: 999, onValueChanged: atCeiling.add);
      await tester.tap(_plus('reps'));
      await tester.pump();
      expect(atCeiling, isEmpty);
    });
  });

  group('S-4242 weight row', () {
    testWidgets('plus steps 2.5 kg and reports a double', (tester) async {
      final calls = <dynamic>[];
      await _pumpRow(
        tester,
        metricType: 'weight',
        currentValue: 60.0,
        unitLabel: 'KG',
        step: 2.5,
        onValueChanged: calls.add,
      );

      await tester.tap(_plus('weight'));
      await tester.pump();
      expect(calls, <dynamic>[62.5]);
      expect(calls.single, isA<double>());
      expect(_shownNumber(tester), '62.5');
    });

    testWidgets('minus steps 2.5 kg', (tester) async {
      final calls = <dynamic>[];
      await _pumpRow(
        tester,
        metricType: 'weight',
        currentValue: 60.0,
        unitLabel: 'KG',
        step: 2.5,
        onValueChanged: calls.add,
      );

      await tester.tap(_minus('weight'));
      await tester.pump();
      expect(calls, <dynamic>[57.5]);
    });

    testWidgets('plus steps 5 lb in the shown unit', (tester) async {
      final calls = <dynamic>[];
      await _pumpRow(
        tester,
        metricType: 'weight',
        currentValue: 220.5,
        unitLabel: 'LBS',
        step: 5,
        onValueChanged: calls.add,
      );

      await tester.tap(_plus('weight'));
      await tester.pump();
      expect(calls, <dynamic>[225.5]);
    });

    testWidgets('minus steps 5 lb in the shown unit', (tester) async {
      final calls = <dynamic>[];
      await _pumpRow(
        tester,
        metricType: 'weight',
        currentValue: 220.5,
        unitLabel: 'LBS',
        step: 5,
        onValueChanged: calls.add,
      );

      await tester.tap(_minus('weight'));
      await tester.pump();
      expect(calls, <dynamic>[215.5]);
    });

    testWidgets('minus at the -200 floor calls nothing', (tester) async {
      final calls = <dynamic>[];
      await _pumpRow(
        tester,
        metricType: 'weight',
        currentValue: -200.0,
        unitLabel: 'KG',
        step: 2.5,
        onValueChanged: calls.add,
      );

      await tester.tap(_minus('weight'));
      await tester.pump();
      expect(calls, isEmpty);
    });
  });

  group('S-4243 pending', () {
    testWidgets('two taps before the parent rebuilds give 11 then 12', (
      tester,
    ) async {
      final calls = <dynamic>[];
      await _pumpRow(tester, currentValue: 10, onValueChanged: calls.add);

      await tester.tap(_plus('reps'));
      await tester.pump();
      await tester.tap(_plus('reps'));
      await tester.pump();

      expect(calls, <dynamic>[11, 12]);
      expect(_shownNumber(tester), '12');
    });
  });

  group('S-4244/S-4245 hold', () {
    testWidgets('the hold repeats at 200 ms and stores once on the lift', (
      tester,
    ) async {
      final calls = <dynamic>[];
      await _pumpRow(tester, currentValue: 10, onValueChanged: calls.add);

      final gesture = await tester.startGesture(
        tester.getCenter(_plus('reps')),
      );
      await tester.pump(_longPressDelay);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      expect(ValueStepperRow.repeatInterval(1).inMilliseconds, 200);
      expect(ValueStepperRow.repeatInterval(5).inMilliseconds, 200);
      expect(_ticksBy(1500), 6);
      expect(_shownNumber(tester), '16');
      expect(calls, isEmpty, reason: 'the hold stores nothing while held');

      await gesture.up();
      await tester.pump();
      expect(calls, <dynamic>[16]);
      expect(_shownNumber(tester), '16');
    });

    testWidgets('the hold speeds up to 100 ms, then 50 ms', (tester) async {
      final calls = <dynamic>[];
      await _pumpRow(tester, currentValue: 10, onValueChanged: calls.add);

      final gesture = await tester.startGesture(
        tester.getCenter(_plus('reps')),
      );
      await tester.pump(_longPressDelay);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(_shownNumber(tester), '16');

      await tester.pump(const Duration(milliseconds: 1000));

      final afterFirstTier = _ticksBy(1500);
      expect(_ticksBy(2500) - afterFirstTier, greaterThan(5));
      expect(ValueStepperRow.repeatInterval(6).inMilliseconds, 100);
      expect(ValueStepperRow.repeatInterval(15).inMilliseconds, 100);
      expect(ValueStepperRow.repeatInterval(16).inMilliseconds, 50);
      expect(_ticksBy(2500), 16);
      expect(_shownNumber(tester), '26');
      expect(calls, isEmpty);

      await gesture.up();
      await tester.pump();
      expect(calls, <dynamic>[26]);
    });
  });

  group('S-4246 read-only', () {
    testWidgets('a locked row steps nothing and opens no dialog', (
      tester,
    ) async {
      final calls = <dynamic>[];
      await _pumpRow(
        tester,
        currentValue: 10,
        isReadOnly: true,
        onValueChanged: calls.add,
      );

      expect(_minus('reps'), findsOneWidget);
      expect(_plus('reps'), findsOneWidget);

      await tester.tap(_plus('reps'));
      await tester.pump();
      await tester.tap(_minus('reps'));
      await tester.pump();

      final gesture = await tester.startGesture(
        tester.getCenter(_plus('reps')),
      );
      await tester.pump(_longPressDelay);
      await tester.pump(const Duration(milliseconds: 400));
      await gesture.up();
      await tester.pump();

      await tester.tap(find.byType(InlineMetricEditor));
      await tester.pump(const Duration(milliseconds: 300));

      expect(calls, isEmpty);
      expect(_shownNumber(tester), '10');
      expect(find.text('Edit Reps'), findsNothing);
    });

    testWidgets('a locked row dims its buttons', (tester) async {
      await _pumpRow(
        tester,
        currentValue: 10,
        isReadOnly: true,
        onValueChanged: (_) {},
      );

      expect(
        tester
            .widget<Icon>(
              find.descendant(of: _plus('reps'), matching: find.byType(Icon)),
            )
            .color,
        Theme.of(
          tester.element(_plus('reps')),
        ).colorScheme.onSurface.withAlpha(77),
      );

      await _pumpRow(tester, currentValue: 10, onValueChanged: (_) {});

      expect(
        tester
            .widget<Icon>(
              find.descendant(of: _plus('reps'), matching: find.byType(Icon)),
            )
            .color,
        Theme.of(tester.element(_plus('reps'))).colorScheme.onSurface,
      );
    });

    testWidgets('an enabled row keeps the tap-to-edit popup', (tester) async {
      final calls = <dynamic>[];
      await _pumpRow(tester, currentValue: 10, onValueChanged: calls.add);

      await tester.tap(find.byType(InlineMetricEditor));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Edit Reps'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '12');
      await tester.tap(find.text('Ok'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(calls, <dynamic>[12]);
    });
  });

  group('S-4247 geometry', () {
    testWidgets('48 dp targets with tooltips and a full-width row', (
      tester,
    ) async {
      await _pumpRow(
        tester,
        metricType: 'weight',
        currentValue: 60.0,
        unitLabel: 'KG',
        step: 2.5,
        onValueChanged: (_) {},
      );

      for (final key in const [
        'value-stepper-minus-weight',
        'value-stepper-plus-weight',
      ]) {
        final size = tester.getSize(find.byKey(Key(key)));
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
      expect(find.byTooltip('Decrease weight'), findsOneWidget);
      expect(find.byTooltip('Increase weight'), findsOneWidget);
      expect(
        tester.getSize(find.byType(ValueStepperRow)).width,
        tester.getSize(find.byType(Scaffold)).width,
      );

      // The new geometry: the box is inset 20 on both sides of the row.
      final surfaceRect = tester.getRect(find.byType(OmniSurface));
      expect(surfaceRect.left, 20);
      expect(
        surfaceRect.right,
        tester.getSize(find.byType(ValueStepperRow)).width - 20,
      );

      await _pumpRow(tester, currentValue: 10, onValueChanged: (_) {});
      expect(find.byTooltip('Decrease reps'), findsOneWidget);
      expect(find.byTooltip('Increase reps'), findsOneWidget);
      expect(
        find.descendant(of: _plus('reps'), matching: find.byIcon(Icons.add)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _minus('reps'),
          matching: find.byIcon(Icons.remove),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the row fits a 320 x 568 phone', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpRow(tester, currentValue: 999, onValueChanged: (_) {});
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(ValueStepperRow)).width, 320);

      final box = tester.getRect(find.byType(OmniSurface));
      expect(box.left, 20);
      expect(box.right, 300);
      expect(box.top, 4);
    });
  });

  group('S-4326 boxed row', () {
    testWidgets('one shadowless OmniSurface, 20/4 outside, 12/8 inside', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpBoxedRow(tester);

      final surface = find.byType(OmniSurface);
      expect(surface, findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ValueStepperRow),
          matching: find.byType(OmniSurface),
        ),
        findsOneWidget,
      );

      final box = tester.widget<OmniSurface>(surface);
      expect(box.showShadow, isFalse);
      expect(
        box.padding,
        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      );

      final rect = tester.getRect(surface);
      expect(rect.left, 20);
      expect(rect.right, 370);
      expect(rect.top, 4);

      for (final finder in [_minus('reps'), _plus('reps')]) {
        final size = tester.getSize(finder);
        expect(size.width, 48, reason: 'the step buttons stay 48 x 48');
        expect(size.height, 48, reason: 'the step buttons stay 48 x 48');
        final button = tester.getRect(finder);
        expect(button.left, greaterThanOrEqualTo(rect.left));
        expect(button.right, lessThanOrEqualTo(rect.right));
      }
    });

    testWidgets('the boxed row still steps and still opens the popup', (
      tester,
    ) async {
      final calls = <dynamic>[];
      await _pumpBoxedRow(tester, onValueChanged: calls.add);

      await tester.tap(_plus('reps'));
      await tester.pump();
      expect(calls, <dynamic>[11]);
      expect(_shownNumber(tester), '11');

      await tester.tap(find.byType(InlineMetricEditor));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Edit Reps'), findsOneWidget);
    });
  });

  group('S-4258 clamped step', () {
    testWidgets('a weight step past 999 calls nothing', (tester) async {
      final calls = <dynamic>[];
      await _pumpRow(
        tester,
        metricType: 'weight',
        currentValue: 999.0,
        unitLabel: 'KG',
        step: 2.5,
        onValueChanged: calls.add,
      );

      await tester.tap(_plus('weight'));
      await tester.pump();
      expect(calls, isEmpty);
    });

    testWidgets('a weight with more than one decimal steps from its shown '
        'value', (tester) async {
      final calls = <dynamic>[];
      await _pumpRow(
        tester,
        metricType: 'weight',
        currentValue: 999.04,
        unitLabel: 'KG',
        step: 2.5,
        onValueChanged: calls.add,
      );

      await tester.tap(_plus('weight'));
      await tester.pump();

      expect(calls, isEmpty);
    });
  });

  group('S-4259 lock mid-hold', () {
    testWidgets('the lock drops the pending intent without storing it', (
      tester,
    ) async {
      final calls = <dynamic>[];
      await _pumpRow(tester, currentValue: 10, onValueChanged: calls.add);

      final gesture = await tester.startGesture(
        tester.getCenter(_plus('reps')),
      );
      await tester.pump(_longPressDelay);
      await tester.pump(const Duration(milliseconds: 200));
      expect(_shownNumber(tester), '12');

      // The watch logs the set: the parent locks the row mid-hold.
      await _pumpRow(
        tester,
        currentValue: 10,
        isReadOnly: true,
        onValueChanged: calls.add,
      );
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));

      expect(calls, isEmpty);
      expect(_shownNumber(tester), '10');
    });
  });

  group('S-4248 hold teardown', () {
    testWidgets('a cancelled hold commits the pending value once', (
      tester,
    ) async {
      final calls = <dynamic>[];
      await _pumpRow(tester, currentValue: 10, onValueChanged: calls.add);

      final gesture = await tester.startGesture(
        tester.getCenter(_plus('reps')),
      );
      await tester.pump(_longPressDelay);
      await tester.pump(const Duration(milliseconds: 200));
      expect(_shownNumber(tester), '12');

      await gesture.cancel();
      await tester.pump();

      expect(calls, <dynamic>[12]);
    });

    testWidgets('a dispose mid-hold leaves no pending timer', (tester) async {
      final calls = <dynamic>[];
      await _pumpRow(tester, currentValue: 10, onValueChanged: calls.add);

      await tester.startGesture(tester.getCenter(_plus('reps')));
      await tester.pump(_longPressDelay);
      await tester.pump(const Duration(milliseconds: 400));

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump(const Duration(seconds: 2));

      expect(tester.takeException(), isNull);
      expect(calls, isEmpty);
    });
  });

  group('S-4413 duration mode', () {
    testWidgets('an int duration renders as clock text with its label', (
      tester,
    ) async {
      await _pumpDurationRow(tester, currentValue: 180, onValueChanged: (_) {});

      expect(tester.takeException(), isNull);
      expect(_shownNumber(tester), '03:00');
      expect(find.text('ROUND LENGTH'), findsOneWidget);
    });

    testWidgets('plus and minus step 15 s and report an int', (tester) async {
      final calls = <dynamic>[];
      await _pumpDurationRow(tester, currentValue: 180, onValueChanged: calls.add);

      await tester.tap(_plus('duration'));
      await tester.pump();
      expect(calls, <dynamic>[195]);
      expect(calls.single, isA<int>());
      expect(_shownNumber(tester), '03:15');

      // A fresh row, so the second step reads 180 s and not the held 195 s.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await _pumpDurationRow(tester, currentValue: 180, onValueChanged: calls.add);
      await tester.tap(_minus('duration'));
      await tester.pump();
      expect(calls, <dynamic>[195, 165]);
      expect(calls.last, isA<int>());
      expect(_shownNumber(tester), '02:45');

      expect(find.byTooltip('Increase duration'), findsOneWidget);
      expect(find.byTooltip('Decrease duration'), findsOneWidget);
    });

    testWidgets('the duration step is 15 s when the caller gives none', (
      tester,
    ) async {
      final calls = <dynamic>[];
      await tester.pumpWidget(
        _host(
          ValueStepperRow(
            metricType: 'duration',
            currentValue: 180,
            unitLabel: 'ROUND LENGTH',
            onValueChanged: calls.add,
          ),
        ),
      );

      await tester.tap(_plus('duration'));
      await tester.pump();
      expect(calls, <dynamic>[195]);
    });

    testWidgets('a step that would cross the 15 s floor lands on it', (
      tester,
    ) async {
      final calls = <dynamic>[];
      await _pumpDurationRow(tester, currentValue: 20, onValueChanged: calls.add);

      await tester.tap(_minus('duration'));
      await tester.pump();
      expect(calls, <dynamic>[15]);
      expect(_shownNumber(tester), '00:15');
    });

    testWidgets('minus at 15 s calls nothing', (tester) async {
      final calls = <dynamic>[];
      await _pumpDurationRow(tester, currentValue: 15, onValueChanged: calls.add);

      await tester.tap(_minus('duration'));
      await tester.pump();
      expect(calls, isEmpty);
      expect(_shownNumber(tester), '00:15');
    });

    testWidgets('S-4704: plus at 3600 s steps to 3615 and reads 1:00:15', (
      tester,
    ) async {
      final calls = <dynamic>[];
      await _pumpDurationRow(
        tester,
        currentValue: 3600,
        onValueChanged: calls.add,
      );
      expect(_shownNumber(tester), '1:00:00');

      await tester.tap(_plus('duration'));
      await tester.pump();
      expect(calls, <dynamic>[3615]);
      expect(_shownNumber(tester), '1:00:15');
    });

    testWidgets('S-4704: minus at 3615 s steps back to 3600', (tester) async {
      final calls = <dynamic>[];
      await _pumpDurationRow(
        tester,
        currentValue: 3615,
        onValueChanged: calls.add,
      );

      await tester.tap(_minus('duration'));
      await tester.pump();
      expect(calls, <dynamic>[3600]);
      expect(_shownNumber(tester), '1:00:00');
    });

    testWidgets('S-4704: plus at the 10-hour ceiling calls nothing', (
      tester,
    ) async {
      final calls = <dynamic>[];
      await _pumpDurationRow(
        tester,
        currentValue: 36000,
        onValueChanged: calls.add,
      );
      expect(_shownNumber(tester), '10:00:00');

      await tester.tap(_plus('duration'));
      await tester.pump();
      expect(calls, isEmpty);
      expect(_shownNumber(tester), '10:00:00');
    });

    testWidgets('S-4705: 8130 s reads 2:15:30 and 135 s reads 02:15', (
      tester,
    ) async {
      final calls = <dynamic>[];
      await _pumpDurationRow(
        tester,
        currentValue: 8130,
        onValueChanged: calls.add,
      );
      expect(_shownNumber(tester), '2:15:30');

      // A fresh row, so the second shape is read off its own value.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await _pumpDurationRow(
        tester,
        currentValue: 135,
        onValueChanged: calls.add,
      );
      expect(_shownNumber(tester), '02:15');
    });

    testWidgets('S-4705: 10:00:00 still fits a 320 x 568 phone', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpDurationRow(
        tester,
        currentValue: 36000,
        onValueChanged: (_) {},
      );
      expect(_shownNumber(tester), '10:00:00');
      expect(tester.takeException(), isNull);
    });

    testWidgets('onEditorTap takes the number tap and no popup opens', (
      tester,
    ) async {
      var taps = 0;
      await _pumpDurationRow(
        tester,
        currentValue: 180,
        onEditorTap: () => taps += 1,
        onValueChanged: (_) {},
      );

      await tester.tap(find.byType(InlineMetricEditor));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(taps, 1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Edit Duration'), findsNothing);
    });

    testWidgets('without onEditorTap the number keeps the generic popup', (
      tester,
    ) async {
      final calls = <dynamic>[];
      await _pumpDurationRow(
        tester,
        currentValue: 180,
        onValueChanged: calls.add,
      );

      await tester.tap(find.byType(InlineMetricEditor));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Edit Duration'), findsOneWidget);
    });

    testWidgets('a read-only duration row steps nothing and taps nothing', (
      tester,
    ) async {
      final calls = <dynamic>[];
      var taps = 0;
      await _pumpDurationRow(
        tester,
        currentValue: 180,
        isReadOnly: true,
        onEditorTap: () => taps += 1,
        onValueChanged: calls.add,
      );

      for (final finder in [_minus('duration'), _plus('duration')]) {
        expect(
          tester
              .widget<GestureDetector>(
                find.descendant(
                  of: finder,
                  matching: find.byType(GestureDetector),
                ),
              )
              .onTap,
          isNull,
          reason: 'a locked row has no step to give',
        );
        expect(
          tester
              .widget<Icon>(
                find.descendant(of: finder, matching: find.byType(Icon)),
              )
              .color,
          Theme.of(finder.evaluate().single).colorScheme.onSurface.withAlpha(77),
        );
      }

      await tester.tap(_plus('duration'));
      await tester.pump();
      await tester.tap(_minus('duration'));
      await tester.pump();
      await tester.tap(find.byType(InlineMetricEditor));
      await tester.pump(const Duration(milliseconds: 300));

      expect(calls, isEmpty);
      expect(taps, 0);
      expect(find.byType(AlertDialog), findsNothing);
      expect(_shownNumber(tester), '03:00');
    });
  });

  group('S-4707 anatomy', () {
    testWidgets('a reps row centres its label and hint under the number', (
      tester,
    ) async {
      await _pumpRow(tester, currentValue: 10, onValueChanged: (_) {});

      _expectLabelUnderNumber(tester, 'REPS');
    });

    testWidgets('a weight row centres its label and hint under the number', (
      tester,
    ) async {
      await _pumpRow(
        tester,
        metricType: 'weight',
        currentValue: 60.0,
        unitLabel: 'KG',
        step: 2.5,
        onValueChanged: (_) {},
      );

      _expectLabelUnderNumber(tester, 'KG');
    });

    testWidgets('a duration row centres its label and hint under the number', (
      tester,
    ) async {
      await _pumpDurationRow(tester, currentValue: 180, onValueChanged: (_) {});

      _expectLabelUnderNumber(tester, 'ROUND LENGTH');
    });

    testWidgets('a locked row hides the hint and keeps the label under the '
        'number', (tester) async {
      await _pumpRow(
        tester,
        currentValue: 10,
        isReadOnly: true,
        onValueChanged: (_) {},
      );

      _expectLabelUnderNumber(tester, 'REPS', withHint: false);
    });

    testWidgets('S-4707/S-4704: the widest weight and duration values do not '
        'overflow 390 x 844', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpRow(
        tester,
        metricType: 'weight',
        currentValue: -200.0,
        unitLabel: 'KG',
        step: 2.5,
        onValueChanged: (_) {},
      );
      expect(_shownNumber(tester), '-200.0');
      expect(tester.takeException(), isNull);
      _expectLabelUnderNumber(tester, 'KG');

      await _pumpDurationRow(
        tester,
        currentValue: 36000,
        onValueChanged: (_) {},
      );
      expect(_shownNumber(tester), '10:00:00');
      expect(tester.takeException(), isNull);
      _expectLabelUnderNumber(tester, 'ROUND LENGTH');
    });

    testWidgets('a locked duration row keeps the label and hides the hint', (
      tester,
    ) async {
      await _pumpDurationRow(
        tester,
        currentValue: 36000,
        isReadOnly: true,
        onValueChanged: (_) {},
      );

      _expectLabelUnderNumber(tester, 'ROUND LENGTH', withHint: false);
    });
  });

  group('Plan 44 hint switch and number tap', () {
    testWidgets('the default row shows one tap-to-type hint', (tester) async {
      await _pumpHintRow(tester, onValueChanged: (_) {});

      expect(_tapHint(), findsOneWidget);
      expect(tester.widget<Text>(_tapHint()).data, 'tap to type');
    });

    testWidgets('showTapHint: false shows no hint', (tester) async {
      await _pumpHintRow(
        tester,
        showTapHint: false,
        onValueChanged: (_) {},
      );

      expect(_tapHint(), findsNothing);
    });

    testWidgets('tapping the number reports the tap once, with no popup', (
      tester,
    ) async {
      var numberTaps = 0;
      await _pumpHintRow(
        tester,
        onEditorTap: () {},
        onNumberTap: () => numberTaps += 1,
        onValueChanged: (_) {},
      );

      await tester.tap(_numberText());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(numberTaps, 1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Edit Reps'), findsNothing);
    });

    testWidgets('the step buttons never report a number tap', (tester) async {
      var numberTaps = 0;
      final calls = <dynamic>[];
      await _pumpHintRow(
        tester,
        onNumberTap: () => numberTaps += 1,
        onValueChanged: calls.add,
      );

      await tester.tap(_plus('reps'));
      await tester.pump();
      await tester.tap(_minus('reps'));
      await tester.pump();

      expect(calls, isNotEmpty, reason: 'the buttons still step the row');
      expect(numberTaps, 0);
    });

    testWidgets('a read-only row reports no number tap', (tester) async {
      var numberTaps = 0;
      await _pumpHintRow(
        tester,
        isReadOnly: true,
        onNumberTap: () => numberTaps += 1,
        onValueChanged: (_) {},
      );

      await tester.tap(_numberText());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(numberTaps, 0);
      expect(tester.takeException(), isNull);
    });
  });
}
