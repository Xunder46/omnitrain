// The Wear Start screen on a small round watch (plan 296, D-29601..D-29604).
//
// Measured before the change with a widget probe at the real sizes: at 192 dp
// the pinned buttons left the routine list zero height, and with Diagnostics
// and the phone in range the column overflowed by 96 px (45 px at 227 dp).
//   S-29601 192 and 227 dp: no overflow, the first routine on screen at 40 dp
//   S-29602 192 dp, nothing synced: the empty sentence, every button reachable
//   S-29603 192 dp: every button scrolls into view and does what it did
//   S-29604 192 dp: the routines come first, the buttons after
//   S-29605 192 dp: compact buttons are exactly 40 dp and 8 dp from each edge
//   S-29606 300 dp: the roomy layout is unchanged

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';
import 'package:omnitrain/watch/start/watch_exercise_picker.dart';
import 'package:omnitrain/watch/start/watch_routine_catalog.dart';
import 'package:omnitrain/watch/start/watch_session_start_paths.dart';
import 'package:omnitrain/watch/start/watch_start_screen.dart';

class _Paths extends WatchSessionStartPaths {
  _Paths(this._list, {required super.engine, required super.store});

  final List<WatchRoutine> _list;

  @override
  List<WatchRoutine> get routines => _list;
}

WatchRoutine _routine(String name) => WatchRoutine(
  routineId: name,
  name: name,
  updatedAt: DateTime.utc(2026),
  segments: const [],
);

class _Taps {
  int sync = 0;
  int nutrition = 0;
  int diagnostics = 0;
}

Future<_Taps> _open(
  WidgetTester tester,
  double side, {
  int routines = 4,
  bool everything = true,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(side, side);
  addTearDown(tester.view.reset);
  final store = InMemoryWatchSessionStore();
  final engine = WatchSessionEngine(store, onEmit: (_) async {});
  final paths = _Paths(
    [for (var i = 0; i < routines; i++) _routine('Routine $i')],
    engine: engine,
    store: store,
  )..phoneReachable = everything;
  final taps = _Taps();
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      home: WatchStartScreen(
        paths: paths,
        onRequestSync: () => taps.sync++,
        onOpenNutrition: () => taps.nutrition++,
        onOpenDiagnostics: everything ? () => taps.diagnostics++ : null,
      ),
    ),
  );
  await tester.pump();
  return taps;
}

Finder _button(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate(
    (widget) => widget is FilledButton || widget is OutlinedButton,
  ),
);

/// Scrolls [target] into the list's viewport and then fully on screen: a
/// partly visible button's centre can sit under the bezel and miss a tap.
Future<void> _reveal(WidgetTester tester, Finder target) async {
  for (var i = 0; i < 30 && target.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -60));
    await tester.pump();
  }
  await tester.ensureVisible(target);
  await tester.pump();
}

void main() {
  for (final side in const [192.0, 227.0]) {
    testWidgets('S-29601 ${side}dp nothing overflows, the first routine shows '
        'at 40 dp', (tester) async {
      await _open(tester, side);

      expect(tester.takeException(), isNull, reason: 'no overflow');
      expect(find.text('Routine 0'), findsOneWidget);
      final rect = tester.getRect(_button('Routine 0'));
      expect(rect.height, 40);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(
        rect.top,
        greaterThanOrEqualTo(WatchStartScreen.compactEdgeInset),
        reason: 'clear of the round bezel at the top',
      );
      expect(rect.bottom, lessThanOrEqualTo(side));
    });
  }

  testWidgets('S-29602 192dp nothing synced: the sentence, every button '
      'reachable', (tester) async {
    await _open(tester, 192, routines: 0);

    expect(tester.takeException(), isNull);
    expect(find.text(WatchStartScreen.nothingSyncedLabel), findsOneWidget);
    await _reveal(tester, find.text(WatchStartScreen.diagnosticsLabel));
    await _reveal(tester, find.text(SearchOnPhoneHint.label));
    expect(find.text(WatchStartScreen.diagnosticsLabel), findsOneWidget);
    expect(find.text(SearchOnPhoneHint.label), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('S-29603 192dp every button scrolls into view and works', (
    tester,
  ) async {
    final taps = await _open(tester, 192);

    await _reveal(tester, _button(WatchStartScreen.syncLabel));
    await tester.tap(_button(WatchStartScreen.syncLabel));
    await _reveal(tester, _button(WatchStartScreen.logFoodLabel));
    await tester.tap(_button(WatchStartScreen.logFoodLabel));
    await _reveal(tester, _button(WatchStartScreen.diagnosticsLabel));
    await tester.tap(_button(WatchStartScreen.diagnosticsLabel));
    await tester.pump();

    expect(taps.sync, 1);
    expect(taps.nutrition, 1);
    expect(taps.diagnostics, 1);

    await _reveal(tester, _button('Free workout'));
    await tester.tap(_button('Free workout'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(WatchExercisePickerScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('S-29604 192dp the routines come first, the buttons after', (
    tester,
  ) async {
    await _open(tester, 192, routines: 2, everything: false);

    final routine = tester.getTopLeft(_button('Routine 0')).dy;
    final second = tester.getTopLeft(_button('Routine 1')).dy;
    final sync = tester.getTopLeft(_button(WatchStartScreen.syncLabel)).dy;
    final free = tester.getTopLeft(_button('Free workout')).dy;
    expect(routine, lessThan(second));
    expect(second, lessThan(sync));
    expect(sync, lessThan(free));
    expect(find.text(WatchStartScreen.diagnosticsLabel), findsNothing);
    expect(find.text(SearchOnPhoneHint.label), findsNothing);
  });

  testWidgets(
    'S-29605 192dp compact buttons are exactly 40 dp and inset 8 dp',
    (tester) async {
      await _open(tester, 192, routines: 1, everything: false);

      final sync = tester.getRect(_button(WatchStartScreen.syncLabel));
      expect(sync.height, 40, reason: 'not padded up to the 48 dp tap area');
      expect(sync.left, 8);
      expect(sync.right, 192 - 8);
      final routine = tester.getRect(_button('Routine 0'));
      expect(routine.height, 40);
      expect(sync.top - routine.bottom, 4, reason: 'the 4 dp gap');
    },
  );

  testWidgets('S-29605 192dp every compact button is exactly 40 dp', (
    tester,
  ) async {
    await _open(tester, 192);

    for (final label in const [
      WatchStartScreen.syncLabel,
      'Free workout',
      WatchStartScreen.logFoodLabel,
      WatchStartScreen.diagnosticsLabel,
    ]) {
      await _reveal(tester, _button(label));
      expect(tester.getSize(_button(label)).height, 40, reason: label);
    }
  });

  testWidgets('S-29607 300dp nothing synced: the sentence shows', (
    tester,
  ) async {
    await _open(tester, 300, routines: 0);

    expect(tester.takeException(), isNull);
    expect(find.text(WatchStartScreen.nothingSyncedLabel), findsOneWidget);
  });

  testWidgets('S-29606 300dp the roomy layout is unchanged', (tester) async {
    await _open(tester, 300);

    expect(tester.takeException(), isNull);
    expect(
      find.descendant(
        of: find.byType(Expanded),
        matching: find.byType(ListView),
      ),
      findsOneWidget,
    );
    expect(tester.getSize(_button(WatchStartScreen.syncLabel)).height, 56);
    expect(tester.getSize(_button('Routine 0')).height, 56);
    expect(find.text(SearchOnPhoneHint.label), findsOneWidget);
    expect(find.text(WatchStartScreen.diagnosticsLabel), findsOneWidget);
  });
}
