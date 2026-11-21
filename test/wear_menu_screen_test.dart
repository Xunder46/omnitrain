// The Wear wrist's session menu as a screen: the shell's Menu button, the rows
// over the live session, and the three actions (plan 281, phase P3b).
//
// Scenario mapping:
//   S-28122   the menu lists the ladder, Add/End/Discard, and no remove control
//             → `S-28122 ...`
//   S-28123   End with a logged effort asks Finish Workout?; Cancel keeps the
//             session; Finish completes it and the start surface shows
//             → `S-28123 ...`
//   S-28124   End with nothing logged asks Discard session? instead
//             → `S-28124 ...`
//   S-28125   Discard Session asks first; Cancel changes nothing; Discard
//             abandons and the entries stay in history → `S-28125 ...`
//   S-28126   tapping a row jumps and closes the menu → `S-28126 ...`
//   S-28127   a running hold shows the caption, refuses the rows, leaves the
//             three actions enabled → `S-28127 ...`
//   S-28127b  once the hold stops the menu refreshes and the rows work
//             → `S-28127b ...`
//   S-28128   Add Exercise appends at the end and keeps the position
//             → `S-28128 ...`
//   S-28129   the phone's completed lifecycle closes the menu by itself
//             → `S-28129 ...`
//   S-28130   adding an exercise from the menu leaves a running rest running
//             → `S-28130 ...`
//   S-28122b  the current exercise's row is the prominent one
//             → `S-28122b ...`
//   S-28123b  dismissing the Finish question (a null pop) is not confirming it
//             → `S-28123b ...`
//   S-28125b  dismissing the Discard question (a null pop) is not discarding
//             → `S-28125b ...`
//   S-28129b  the phone ending the session closes the question page and the
//             menu both → `S-28129b ...`
//   S-28131   the start picker's default follows the pick on a session that
//             already holds an exercise → `S-28131 ...`
//   S-28131b  with keepPosition: true the pick never moves the session
//             → `S-28131b ...`
//   S-28133   a slot the phone removed vanishes on the refresh and a stale row
//             tap changes nothing → `S-28133 ...`
//   S-28134   a double-tap in the Add list adds exactly one slot
//             → `S-28134 ...`
//   S-28134b  two picks raced inside one frame still add exactly one slot
//             → `S-28134b ...`
//   S-28135   a session whose only slot was removed shows no rows but keeps
//             its actions, and End asks the discard question
//             → `S-28135 ...`
//   S-28136   after End the shell stops its one-second ticker
//             → `S-28136 ...`
//
// Everything here is Mock-first: an in-memory store, a fake link and never a
// real `Future.delayed` inside `testWidgets` (FakeAsync would hang on it). The
// shell and the menu each own a 1 s periodic timer, so `pumpAndSettle` is never
// used; every wait is an explicit `pump` with a duration.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain_watch_link/omnitrain_watch_link.dart';

import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/watch/app/wear_app.dart';
import 'package:omnitrain/watch/app/wear_watch_transport.dart';
import 'package:omnitrain/watch/logging/watch_menu_screen.dart';
import 'package:omnitrain/watch/logging/watch_menu_state.dart';
import 'package:omnitrain/watch/nutrition/watch_nutrition_state.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';
import 'package:omnitrain/watch/start/watch_exercise_picker.dart';
import 'package:omnitrain/watch/start/watch_session_start_paths.dart';
import 'package:omnitrain/watch/start/watch_start_screen.dart';
import 'package:omnitrain/watch/start/watch_sync_orchestrator.dart';

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

/// Opens the menu over the current surface. Not `pumpAndSettle`: the shell and
/// the menu own 1 s periodic timers, and settling on them never returns.
Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.text(WearApp.menuLabel));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Lets a popped route retire: the pop lands, its transition steps out, and
/// one more frame takes the retiring route out of the tree. `pump()` without a
/// duration advances no clock, so no periodic timer fires here. A single long
/// pump does not work: the exit controller needs its first tick and then
/// stepped frames before it reports dismissed.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 6; i++) {
    if (find.byType(WatchMenuScreen).evaluate().isEmpty) break;
    await tester.pump(const Duration(milliseconds: 120));
  }
  await tester.pump();
}

/// The menu's own [label], not the covered surface's identical text.
Finder _menuText(String label) => find.descendant(
  of: find.byType(WatchMenuScreen),
  matching: find.text(label),
);

/// The `sendMessage` / `transferUserInfo` traffic the wrist owes the phone.
int _framesUp() => _calls
    .where((call) => call.method == 'sendMessage' || call.method == 'transferUserInfo')
    .length;

/// The instant the logged entries carry: fixed, never `DateTime.now()`.
final DateTime _entryClock = DateTime.utc(2026, 11, 21, 12);

/// Three ladder slots, ids and names no engine default mints.
Future<void> _threeSlots(_Harness harness) async {
  await harness.engine.createSession(
    modality: 'resistance_lifting',
    exercises: <Map<String, Object?>>[
      <String, Object?>{
        'sessionExerciseId': 'sx-bench',
        'exerciseId': 'ex-barbell-bench-press',
        'name': 'Bench Press',
        'capabilities': <String>['reps', 'sets', 'load'],
      },
      <String, Object?>{
        'sessionExerciseId': 'sx-row',
        'exerciseId': 'ex-menu-row',
        'name': 'Row',
        'capabilities': <String>['reps', 'sets', 'load'],
      },
      <String, Object?>{
        'sessionExerciseId': 'sx-press',
        'exerciseId': 'ex-menu-press',
        'name': 'Press',
        'capabilities': <String>['reps', 'sets', 'load'],
      },
    ],
  );
}

/// A one-slot session, for S-28135.
Future<void> _oneSlot(_Harness harness) async {
  await harness.engine.createSession(
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
}

/// What Add Exercise offers: a `routines_down` the phone sent before the
/// shell booted, whose fallback list carries two exercises (the shape
/// `test/wear_app_test.dart` S-28024 delivers).
Future<void> _syncExercises(_Harness harness) async {
  await harness.orchestrator.receive(<String, Object?>{
    'protocolVersion': SyncProtocolValidator.protocolVersion,
    'messageId': 'msg-menu-fallback',
    'type': 'routines_down',
    'origin': 'phone',
    'sentAt': utcIso(_entryClock),
    'payload': <String, Object?>{
      'generatedAt': utcIso(_entryClock),
      'routines': <Object?>[],
      'fallbackExercises': <Object?>[
        <String, Object?>{
          'exerciseId': 'ex-menu-curl',
          'name': 'Curl Bar Curl',
          'capabilities': <String>['reps', 'sets', 'load'],
        },
        <String, Object?>{
          'exerciseId': 'ex-menu-fly',
          'name': 'Dumbbell Fly',
          'capabilities': <String>['reps', 'sets', 'load'],
        },
      ],
    },
  });
}

/// A set the wrist logged on a slot, the shape the logging surface hands
/// the engine (`test/watch_session_finish_test.dart` `_wristSet`): its
/// payload names the slot, which is what the menu counts.
Map<String, Object?> _wristSet(String entryId, String slotId) => {
  'entryId': entryId,
  'eventId': entryId,
  'kind': WatchObservationKind.set,
  'loggedAt': utcIso(_entryClock),
  'sessionExerciseId': slotId,
  'exerciseId': 'ex-barbell-bench-press',
  'reps': 8,
  'loadKg': 40,
};

/// One `session_lifecycle` from the phone, naming the session it is about
/// (the helper at `test/watch_session_engine_test.dart` line 158).
Map<String, Object?> _lifecycleFrame(
  String sessionId, {
  required String messageId,
  required String state,
}) => {
  'protocolVersion': SyncProtocolValidator.protocolVersion,
  'messageId': messageId,
  'sessionId': sessionId,
  'type': 'session_lifecycle',
  'origin': 'phone',
  'sentAt': '2026-07-13T06:30:00Z',
  'payload': <String, Object?>{
    'state': state,
    'at': '2026-07-13T06:30:00Z',
  },
};

/// One `structure_change` from the phone, over the wrist's own session
/// (the helper at `test/watch_session_engine_test.dart` line 115).
Map<String, Object?> _structureChange(
  String sessionId, {
  required String changeId,
  required List<Map<String, Object?>> changes,
}) => {
  'protocolVersion': SyncProtocolValidator.protocolVersion,
  'messageId': 'msg-$changeId',
  'sessionId': sessionId,
  'type': 'structure_change',
  'origin': 'phone',
  'sentAt': '2026-07-13T06:30:00Z',
  'payload': <String, Object?>{'changeId': changeId, 'changes': changes},
};

/// Confirms or cancels the open dialog, then settles the route animations.
Future<void> _answerDialog(WidgetTester tester, String answer) async {
  await tester.tap(find.text(answer));
  await _settle(tester);
}

/// The menu row's button for [label]: every row is an OutlinedButton except
/// the current one, which is a tonal FilledButton.
OutlinedButton rowButton(WidgetTester tester, String label) =>
    tester.widget<OutlinedButton>(
      find.ancestor(of: find.text(label), matching: find.byType(OutlinedButton)),
    );

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

  testWidgets('S-28122 the menu lists the ladder, the actions, and no remove control',
      (tester) async {
    final harness = _Harness();
    await _threeSlots(harness);
    await _open(tester, harness);
    await _openMenu(tester);

    // The menu is over the logging surface, which still names the first slot,
    // so every label here is the menu's own.
    expect(_menuText('Bench Press'), findsOneWidget);
    expect(_menuText('Row'), findsOneWidget);
    expect(_menuText('Press'), findsOneWidget);
    expect(_menuText(WatchMenuCopy.addExerciseLabel), findsOneWidget);
    expect(_menuText(WatchMenuCopy.finishLabel), findsOneWidget);
    expect(_menuText(WatchMenuCopy.discardLabel), findsOneWidget);
    expect(find.textContaining('Remove'), findsNothing);
    expect(find.textContaining('remove'), findsNothing);
  });

  testWidgets('S-28123 End with a logged effort asks Finish, cancels, then finishes',
      (tester) async {
    final harness = _Harness();
    await _threeSlots(harness);
    await harness.engine.appendObservation(_wristSet('entry-menu-1', 'sx-bench'));
    await _open(tester, harness);
    await _openMenu(tester);

    await tester.tap(find.text(WatchMenuCopy.finishLabel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(WatchMenuCopy.confirmTitle), findsOneWidget);
    expect(find.text(WatchMenuCopy.confirmBody), findsOneWidget);

    await _answerDialog(tester, WatchMenuCopy.confirmCancel);
    expect(find.byType(WatchMenuScreen), findsOneWidget);
    expect(harness.engine.session!.status, WatchSessionStatus.active);

    await tester.tap(find.text(WatchMenuCopy.finishLabel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(WatchMenuCopy.confirmTitle), findsOneWidget);
    await _answerDialog(tester, WatchMenuCopy.confirmFinish);

    expect(harness.engine.session!.status, WatchSessionStatus.completed);
    expect(find.byType(WatchStartScreen), findsOneWidget);
    expect(find.byType(WatchMenuScreen), findsNothing);
  });

  testWidgets('S-28124 End with nothing logged asks the discard question',
      (tester) async {
    final harness = _Harness();
    await _threeSlots(harness);
    await _open(tester, harness);
    await _openMenu(tester);

    await tester.tap(find.text(WatchMenuCopy.finishLabel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(WatchMenuCopy.discardConfirmTitle), findsOneWidget);
    expect(find.text(WatchMenuCopy.confirmTitle), findsNothing);

    await _answerDialog(tester, WatchMenuCopy.discardConfirmDiscard);
    expect(harness.engine.session!.status, WatchSessionStatus.abandoned);
    expect(find.byType(WatchStartScreen), findsOneWidget);
  });

  testWidgets('S-28125 Discard asks first, cancels without change, then abandons',
      (tester) async {
    final harness = _Harness();
    await _threeSlots(harness);
    await harness.engine.appendObservation(_wristSet('entry-menu-2', 'sx-bench'));
    await _open(tester, harness);
    await _openMenu(tester);

    await tester.tap(find.text(WatchMenuCopy.discardLabel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(WatchMenuCopy.discardConfirmTitle), findsOneWidget);

    await _answerDialog(tester, WatchMenuCopy.discardConfirmCancel);
    expect(find.byType(WatchMenuScreen), findsOneWidget);
    expect(harness.engine.session!.status, WatchSessionStatus.active);

    await tester.tap(find.text(WatchMenuCopy.discardLabel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _answerDialog(tester, WatchMenuCopy.discardConfirmDiscard);

    expect(harness.engine.session!.status, WatchSessionStatus.abandoned);
    expect(find.byType(WatchStartScreen), findsOneWidget);
    // Logged entries stay in history (D-28102).
    expect(
      harness.engine.entries
          .where((entry) => entry.kind == WatchObservationKind.set),
      isNotEmpty,
    );
  });

  testWidgets('S-28126 tapping a row jumps and closes the menu', (tester) async {
    final harness = _Harness();
    await _threeSlots(harness);
    await _open(tester, harness);
    await _openMenu(tester);

    await tester.tap(_menuText('Press'));
    await _settle(tester);

    expect(find.byType(WatchMenuScreen), findsNothing);
    expect(harness.engine.session!.currentExerciseIndex, 2);
    // The logging surface now names the third exercise.
    expect(find.text('Press'), findsWidgets);
  });

  testWidgets('S-28127 a running hold shows the caption, locks the rows, spares the actions',
      (tester) async {
    final harness = _Harness();
    await _threeSlots(harness);
    await _open(tester, harness);
    // The hold is running before the menu opens, so its first build reads the
    // lock; the shell's own surfaces are not rebuilt for it.
    await harness.engine.startTimer(
      WatchTimerKind.hold,
      sessionExerciseId: 'sx-bench',
    );
    await _openMenu(tester);

    expect(find.text(WatchMenuCopy.lockedCaption), findsOneWidget);

    final framesBefore = _framesUp();
    await tester.tap(find.text('Row'));
    await tester.pump();
    expect(harness.engine.session!.currentExerciseIndex, 0);
    expect(_framesUp(), framesBefore,
        reason: 'a refused jump emits no frame for the phone');

    // The lock never covers the three actions.
    expect(rowButton(tester, WatchMenuCopy.addExerciseLabel).onPressed, isNotNull);
    expect(rowButton(tester, WatchMenuCopy.finishLabel).onPressed, isNotNull);
    expect(rowButton(tester, WatchMenuCopy.discardLabel).onPressed, isNotNull);
    // And the row buttons are the ones disabled.
    expect(rowButton(tester, 'Row').onPressed, isNull);
    expect(rowButton(tester, 'Press').onPressed, isNull);
  });

  testWidgets('S-28127b once the hold stops the menu refreshes and the rows work',
      (tester) async {
    final harness = _Harness();
    await _threeSlots(harness);
    await _open(tester, harness);
    await harness.engine.startTimer(
      WatchTimerKind.hold,
      sessionExerciseId: 'sx-bench',
    );
    await _openMenu(tester);
    expect(find.text(WatchMenuCopy.lockedCaption), findsOneWidget);

    await harness.engine.stopTimer(kind: WatchTimerKind.hold);
    // The menu's own 1 s refresh notices the stopped clock.
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(WatchMenuCopy.lockedCaption), findsNothing);

    await tester.tap(find.text('Row'));
    await _settle(tester);
    expect(harness.engine.session!.currentExerciseIndex, 1);
    expect(find.byType(WatchMenuScreen), findsNothing);
  });

  testWidgets('S-28128 Add Exercise appends at the end and keeps the position',
      (tester) async {
    final harness = _Harness();
    await _threeSlots(harness);
    await _syncExercises(harness);
    await _open(tester, harness);
    await _openMenu(tester);

    await tester.tap(find.text(WatchMenuCopy.addExerciseLabel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Curl Bar Curl'), findsOneWidget);

    await tester.tap(find.text('Curl Bar Curl'));
    await _settle(tester);

    // The menu is back, the new row last, and the position did not move.
    expect(find.byType(WatchMenuScreen), findsOneWidget);
    final session = harness.engine.session!;
    expect(session.exercises, hasLength(4));
    expect(session.exercises.last['name'], 'Curl Bar Curl');
    expect(session.currentExerciseIndex, 0, reason: 'the add never jumps (D-28108)');
    expect(_menuText('Curl Bar Curl'), findsOneWidget);
  });

  testWidgets('S-28129 the phone ending the session closes the menu by itself',
      (tester) async {
    final harness = _Harness();
    await _threeSlots(harness);
    await _open(tester, harness);
    await _openMenu(tester);
    expect(find.byType(WatchMenuScreen), findsOneWidget);

    await harness.transport.deliver(
      _lifecycleFrame(
        harness.engine.session!.sessionId,
        messageId: 'msg-menu-done',
        state: 'completed',
      ),
    );
    await tester.pump();
    // The menu's own refresh is what notices; then the route settles.
    await tester.pump(const Duration(seconds: 1));
    await _settle(tester);

    expect(find.byType(WatchMenuScreen), findsNothing);
    expect(find.byType(WatchStartScreen), findsOneWidget);
  });

  testWidgets('S-28130 adding an exercise from the menu leaves the rest running',
      (tester) async {
    final harness = _Harness();
    await _threeSlots(harness);
    await _syncExercises(harness);
    await harness.engine.startTimer(WatchTimerKind.rest);
    await _open(tester, harness);

    expect(find.text('Next'), findsOneWidget);
    expect(find.text(WearApp.menuLabel), findsOneWidget);
    await _openMenu(tester);

    await tester.tap(find.text(WatchMenuCopy.addExerciseLabel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Curl Bar Curl'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(WatchMenuScreen), findsOneWidget);
    expect(
      harness.engine.timerFor(WatchTimerKind.rest)!.state,
      WatchTimerState.running,
      reason: 'adding an exercise never stops the rest (D-28110)',
    );
  });

  testWidgets('S-28133 a slot the phone removed vanishes, and its stale row tap does nothing',
      (tester) async {
    final harness = _Harness();
    await _threeSlots(harness);
    await _open(tester, harness);
    await _openMenu(tester);

    final stale = rowButton(tester, 'Press');
    expect(
      await harness.engine.applyMessage(
        _structureChange(
          harness.engine.session!.sessionId,
          changeId: 'rm-1',
          changes: <Map<String, Object?>>[
            <String, Object?>{
              'kind': 'remove_exercise',
              'sessionExerciseId': 'sx-press',
            },
          ],
        ),
      ),
      isTrue,
    );
    // The menu's 1 s refresh rebuilds its rows.
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Press'), findsNothing);

    // The captured button of the removed row is still in the test's hand; the
    // menu must never follow it.
    final framesBefore = _framesUp();
    stale.onPressed!();
    // `_settle`, not one long pump: a menu that wrongly popped is still in the
    // tree until its exit transition has stepped out.
    await _settle(tester);
    expect(harness.engine.session!.currentExerciseIndex, 0);
    expect(_framesUp(), framesBefore,
        reason: 'a stale row tap sends no frame for the phone');
    expect(find.byType(WatchMenuScreen), findsOneWidget);
    // And the menu still lists the two rows that remain: a tap that moved
    // nothing must not close it either (S-28133b guard).
    expect(_menuText('Bench Press'), findsOneWidget);
    expect(_menuText('Row'), findsOneWidget);
  });

  testWidgets('S-28134 a double-tap in the Add list adds exactly one slot',
      (tester) async {
    final harness = _Harness();
    await _threeSlots(harness);
    await _syncExercises(harness);
    await _open(tester, harness);
    await _openMenu(tester);

    await tester.tap(find.text(WatchMenuCopy.addExerciseLabel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final slotsBefore = harness.engine.session!.exercises.length;

    // Two taps inside one frame: no pump between them.
    final curl = find.text('Curl Bar Curl');
    await tester.tap(curl);
    await tester.tap(curl, warnIfMissed: false);
    await _settle(tester);

    expect(harness.engine.session!.exercises, hasLength(slotsBefore + 1));
    expect(_menuText('Curl Bar Curl'), findsOneWidget,
        reason: 'one new row, not two');
    expect(find.byType(WatchMenuScreen), findsOneWidget);
  });

  testWidgets('S-28135 a session whose only slot was removed keeps its actions',
      (tester) async {
    final harness = _Harness();
    await _oneSlot(harness);
    await _syncExercises(harness);
    await _open(tester, harness);
    await _openMenu(tester);

    expect(
      await harness.engine.applyMessage(
        _structureChange(
          harness.engine.session!.sessionId,
          changeId: 'rm-only',
          changes: <Map<String, Object?>>[
            <String, Object?>{
              'kind': 'remove_exercise',
              'sessionExerciseId': 'sx-bench',
            },
          ],
        ),
      ),
      isTrue,
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Bench Press'), findsNothing);
    expect(find.text(WatchMenuCopy.addExerciseLabel), findsOneWidget);
    expect(find.text(WatchMenuCopy.finishLabel), findsOneWidget);
    expect(find.text(WatchMenuCopy.discardLabel), findsOneWidget);

    // Nothing is logged and nothing runs, so End has nothing to save.
    await tester.tap(find.text(WatchMenuCopy.finishLabel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(WatchMenuCopy.discardConfirmTitle), findsOneWidget);
    expect(find.text(WatchMenuCopy.confirmTitle), findsNothing);
  });

  testWidgets('S-28122b the current exercise is the prominent row',
      (tester) async {
    final harness = _Harness();
    await _threeSlots(harness);
    // The session sits on the middle slot before the shell boots.
    await harness.engine.selectExercise('sx-row');
    await _open(tester, harness);
    await _openMenu(tester);

    // The Row row is the tonal FilledButton; the other two are outlined.
    expect(
      find.ancestor(of: _menuText('Row'), matching: find.byType(FilledButton)),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: _menuText('Row'),
        matching: find.byType(OutlinedButton),
      ),
      findsNothing,
    );
    expect(
      find.ancestor(
        of: _menuText('Bench Press'),
        matching: find.byType(FilledButton),
      ),
      findsNothing,
    );
    expect(
      find.ancestor(
        of: _menuText('Bench Press'),
        matching: find.byType(OutlinedButton),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: _menuText('Press'),
        matching: find.byType(FilledButton),
      ),
      findsNothing,
    );
    expect(
      find.ancestor(
        of: _menuText('Press'),
        matching: find.byType(OutlinedButton),
      ),
      findsOneWidget,
    );
  });

  testWidgets('S-28123c the Finish question is a full-screen page, not a dialog',
      (tester) async {
    final harness = _Harness();
    await _threeSlots(harness);
    await harness.engine.appendObservation(_wristSet('entry-menu-3c', 'sx-bench'));
    await _open(tester, harness);
    await _openMenu(tester);

    await tester.tap(find.text(WatchMenuCopy.finishLabel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The stock dialog cut its body and buttons off at watch sizes (D-28113):
    // the question is a page as big as the app, with the full-screen dialog
    // shell and no centred AlertDialog.
    expect(find.text(WatchMenuCopy.confirmTitle), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    // `Dialog` itself always spans the route; the page inside it is what shows
    // whether the dialog's inset is gone.
    expect(
      tester.getSize(
        find.descendant(of: find.byType(Dialog), matching: find.byType(Scaffold)),
      ),
      tester.getSize(find.byType(WearApp)),
    );
  });

  testWidgets('S-28123b dismissing the Finish question is not confirming it',
      (tester) async {
    final harness = _Harness();
    await _threeSlots(harness);
    await harness.engine.appendObservation(_wristSet('entry-menu-3', 'sx-bench'));
    await _open(tester, harness);
    await _openMenu(tester);

    await tester.tap(find.text(WatchMenuCopy.finishLabel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(WatchMenuCopy.confirmTitle), findsOneWidget);

    // No button pressed: a null result, the way the system back dismisses it.
    final framesBefore = _framesUp();
    Navigator.of(tester.element(find.text(WatchMenuCopy.confirmTitle))).pop();
    await _settle(tester);

    expect(harness.engine.session!.status, WatchSessionStatus.active);
    expect(find.byType(WatchMenuScreen), findsOneWidget);
    expect(_framesUp(), framesBefore,
        reason: 'a dismissed question sends no frame for the phone');
  });

  testWidgets('S-28125b dismissing the Discard question is not discarding',
      (tester) async {
    final harness = _Harness();
    await _threeSlots(harness);
    await harness.engine.appendObservation(_wristSet('entry-menu-4', 'sx-bench'));
    await _open(tester, harness);
    await _openMenu(tester);

    await tester.tap(find.text(WatchMenuCopy.discardLabel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(WatchMenuCopy.discardConfirmTitle), findsOneWidget);

    final framesBefore = _framesUp();
    Navigator.of(
      tester.element(find.text(WatchMenuCopy.discardConfirmTitle)),
    ).pop();
    await _settle(tester);

    expect(harness.engine.session!.status, WatchSessionStatus.active);
    expect(find.byType(WatchMenuScreen), findsOneWidget);
    expect(_framesUp(), framesBefore,
        reason: 'a dismissed question sends no frame for the phone');
  });

  testWidgets('S-28129b the phone ending the session closes the question page too',
      (tester) async {
    final harness = _Harness();
    await _threeSlots(harness);
    await harness.engine.appendObservation(_wristSet('entry-menu-5', 'sx-bench'));
    await _open(tester, harness);
    await _openMenu(tester);

    await tester.tap(find.text(WatchMenuCopy.finishLabel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(WatchMenuCopy.confirmTitle), findsOneWidget);

    await harness.transport.deliver(
      _lifecycleFrame(
        harness.engine.session!.sessionId,
        messageId: 'msg-menu-done-b',
        state: 'completed',
      ),
    );
    await tester.pump();
    // The menu's own refresh is what notices; then the routes settle.
    await tester.pump(const Duration(seconds: 1));
    await _settle(tester);

    // Both the question page and the menu are gone, start surface shows.
    expect(find.text(WatchMenuCopy.confirmTitle), findsNothing);
    expect(find.byType(WatchMenuScreen), findsNothing);
    expect(find.byType(WatchStartScreen), findsOneWidget);
  });

  testWidgets('S-28131 the picker default follows the pick on a live session',
      (tester) async {
    final harness = _Harness();
    await _oneSlot(harness);
    await _syncExercises(harness);

    // The picker as the start screen pushes it: the default keepPosition.
    await tester.pumpWidget(
      MaterialApp(home: WatchExercisePickerScreen(paths: harness.paths)),
    );
    await tester.pump();

    await tester.tap(find.text('Curl Bar Curl'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final session = harness.engine.session!;
    expect(session.exercises, hasLength(2));
    expect(session.currentExerciseIndex, 1,
        reason: 'the default picker moves the session to the pick');
  });

  testWidgets('S-28131b a keepPosition pick never moves the session',
      (tester) async {
    final harness = _Harness();
    await _oneSlot(harness);
    await _syncExercises(harness);

    await tester.pumpWidget(
      MaterialApp(
        home: WatchExercisePickerScreen(
          paths: harness.paths,
          keepPosition: true,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Curl Bar Curl'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final session = harness.engine.session!;
    expect(session.exercises, hasLength(2));
    expect(session.currentExerciseIndex, 0,
        reason: 'keepPosition keeps the user on their exercise');
  });

  testWidgets('S-28134b two picks raced inside one frame add exactly one slot',
      (tester) async {
    final harness = _Harness();
    await _threeSlots(harness);
    await _syncExercises(harness);
    await _open(tester, harness);
    await _openMenu(tester);

    await tester.tap(find.text(WatchMenuCopy.addExerciseLabel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final slotsBefore = harness.engine.session!.exercises.length;

    // No await between the two picks: the second starts before the first
    // finished, which a pair of `tester.tap`s separated by pumps never does.
    final button = tester.widget<WatchUtilityButton>(
      find.widgetWithText(WatchUtilityButton, 'Curl Bar Curl'),
    );
    button.onPressed();
    button.onPressed();
    await tester.pump();
    await _settle(tester);

    expect(harness.engine.session!.exercises, hasLength(slotsBefore + 1));
    // Both picks reach `_add`, which share one slot id (so the engine keeps
    // one slot), but without the guard each one pops: the second pop would
    // close the menu under the list.
    expect(find.byType(WatchExercisePickerScreen), findsNothing);
    expect(find.byType(WatchMenuScreen), findsOneWidget);
  });

  testWidgets('S-28136 after End the shell stops its one-second ticker',
      (tester) async {
    final harness = _Harness();
    await _threeSlots(harness);
    await harness.engine.appendObservation(_wristSet('entry-menu-6', 'sx-bench'));
    await _open(tester, harness);
    await _openMenu(tester);
    expect(
      tester.state<WearAppState>(find.byType(WearApp)).isTicking,
      isTrue,
    );

    await tester.tap(find.text(WatchMenuCopy.finishLabel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(WatchMenuCopy.confirmTitle), findsOneWidget);
    await _answerDialog(tester, WatchMenuCopy.confirmFinish);

    expect(find.byType(WatchStartScreen), findsOneWidget);

    // The shell's once-a-second rebuild must stop once the session is over: a
    // ticker left running on the idle start surface rebuilds it every second.
    await _settle(tester);
    expect(
      tester.state<WearAppState>(find.byType(WearApp)).isTicking,
      isFalse,
    );
  });
}
