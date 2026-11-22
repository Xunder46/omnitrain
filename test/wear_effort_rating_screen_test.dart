// The Wear effort-rating prompt: the question the wrist asks when a workout
// with a logged effort is ended while the phone's setting asks for it (plan
// 285, phase P2). Production lives in `lib/watch/` (phase P1); this file only
// guards it.
//
// Scenario mapping:
//   S-28501   End with the setting on shows the question alone
//             → `S-28501 ...`
//   S-28502   nothing owed shows the start surface: setting off, or the
//             setting on with nothing logged (the discard question)
//             → `S-28502a ...` / `S-28502b ...`
//   S-28503   Confirm records the picked rating and shows the start surface
//             → `S-28503 ...`
//   S-28504   Skip shows the start surface and records nothing
//             → `S-28504 ...`
//   S-28505   the rotary steps the number; a turn down from nothing picks
//             nothing; the screen alone redraws itself on a state change
//             → `S-28505 ...` / `S-28505b ...` / `S-28505c ...`
//   S-28506   a vertical drag steps the number → `S-28506 ...`
//   S-28507   the prompt fits 227 and 192 dp at exact compact sizes, and a
//             crowded watch still fits it → `S-28507a ...` / `S-28507b ...` /
//             `S-28507c ...`
//   S-28508   Confirm is disabled until a number is picked → `S-28508 ...`
//   S-28509   the numbers are named for a screen reader → `S-28509 ...`
//   S-28510   the question is asked again at launch → `S-28510 ...`
//   S-28511   the phone answering first closes the prompt → `S-28511 ...`
//   S-28512   a shell without a rating state never asks → `S-28512 ...`
//   S-28513   the menu's End goes through the rating state (plain `test()`)
//             → `S-28513 ...`
//   S-28514   Discard owes nothing → `S-28514 ...`
//
// Everything here is Mock-first: an in-memory store, a fake link and never a
// real `Future.delayed` inside `testWidgets` (FakeAsync would hang on it). The
// shell and the screens own 1 s periodic timers, so `pumpAndSettle` is never
// used; every wait is an explicit `pump`.
//
// The harness is copied from `test/wear_logging_layout_test.dart` (channel
// mocks, `_open`, `_setView`, `_kindSession`) and gains a
// `WatchPhonePreferences` and a `WatchEffortRatingState`, wired the way
// `wear_main.dart` wires them. The menu End flow is copied from
// `test/wear_menu_screen_test.dart` (`_openMenu`, `_settle`); the
// `preferences_down` envelope from `test/wear_phone_settings_test.dart`; the
// phone's snapshot from `test/watch_effort_rating_engine_test.dart` (S-28406).

import 'dart:ui' show Tristate;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain_watch_link/omnitrain_watch_link.dart';

import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/watch/app/wear_app.dart';
import 'package:omnitrain/watch/app/wear_watch_transport.dart';
import 'package:omnitrain/watch/logging/watch_effort_rating_screen.dart';
import 'package:omnitrain/watch/logging/watch_effort_rating_state.dart';
import 'package:omnitrain/watch/logging/watch_menu_screen.dart';
import 'package:omnitrain/watch/logging/watch_menu_state.dart';
import 'package:omnitrain/watch/logging/watch_workout_summary_screen.dart';
import 'package:omnitrain/watch/nutrition/watch_nutrition_state.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';
import 'package:omnitrain/watch/start/watch_phone_preferences.dart';
import 'package:omnitrain/watch/start/watch_session_start_paths.dart';
import 'package:omnitrain/watch/start/watch_start_screen.dart';
import 'package:omnitrain/watch/start/watch_sync_orchestrator.dart';
import 'package:omnitrain/watch/widgets/watch_controls.dart';

const String _t1 = '2026-09-25T09:00:00Z';

/// A `preferences_down` envelope, the helper from
/// `test/wear_phone_settings_test.dart`: protocolVersion 1, a phone origin,
/// and the effort-rating setting the caller chooses.
Map<String, Object?> _envelope({
  String messageId = 'msg-prefs',
  required bool effortRatingPrompt,
}) => {
  'protocolVersion': 1,
  'messageId': messageId,
  'type': 'preferences_down',
  'origin': 'phone',
  'sentAt': '2026-09-25T09:00:00Z',
  'payload': {
    'generatedAt': _t1,
    'effortRatingPrompt': effortRatingPrompt,
    'restPingSeconds': 90,
  },
};

const MethodChannel _methods = MethodChannel('omnitrain/watch_link/methods');
const EventChannel _events = EventChannel('omnitrain/watch_link/events');

final List<MethodCall> _calls = <MethodCall>[];

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

/// The shell's graph, built the way `wear_main.dart` builds it but over an
/// in-memory store and a fake radio. `withRating: false` builds the shell
/// without the rating state, exactly as a shell that does not wire one yet.
class _Harness {
  _Harness({InMemoryWatchSessionStore? store, bool withRating = true})
    : store = store ?? InMemoryWatchSessionStore(),
      transport = WearWatchTransport(link: WatchLink()) {
    engine = WatchSessionEngine(this.store, onEmit: transport.send);
    paths = WatchSessionStartPaths(engine: engine, store: this.store);
    nutrition = WatchNutritionState(engine: engine, store: this.store);
    preferences = WatchPhonePreferences(store: this.store);
    if (withRating) {
      rating = WatchEffortRatingState(
        engine: engine,
        store: this.store,
        preferences: preferences,
      );
    }
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
  late final WatchSessionEngine engine;
  late final WatchSessionStartPaths paths;
  late final WatchNutritionState nutrition;
  late final WatchPhonePreferences preferences;
  WatchEffortRatingState? rating;
  late final WatchSyncOrchestrator orchestrator;

  Widget app() => WearApp(
    engine: engine,
    paths: paths,
    nutrition: nutrition,
    orchestrator: orchestrator,
    transport: transport,
    preferences: preferences,
    rating: rating,
  );
}

Future<void> _open(WidgetTester tester, _Harness harness) async {
  await tester.pumpWidget(harness.app());
  // Restore, the status read and the first frame: all microtasks, no clock.
  for (var i = 0; i < 8; i++) {
    await tester.pump();
  }
}

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

/// A session with one logged set on the slot the session starts with.
Future<void> _loggedSetSession(_Harness harness) async {
  await _kindSession(harness, 'set', ['reps', 'sets', 'load']);
  await harness.engine.appendObservation(_wristSet('entry-rating-1', 'sx-set'));
}

/// A menu rig with no widgets, the way `test/watch_menu_state_test.dart` builds
/// one: the in-memory store, a fixed clock, and a session id of our own.
class _MenuRig {
  _MenuRig() : store = InMemoryWatchSessionStore() {
    engine = WatchSessionEngine(
      store,
      clock: _fixedClock,
      sessionIdFactory: () => sessionId,
    );
    paths = WatchSessionStartPaths(
      engine: engine,
      store: store,
      clock: _fixedClock,
    );
    preferences = WatchPhonePreferences(store: store, clock: _fixedClock);
  }

  DateTime _fixedClock() => DateTime.utc(2026, 11, 21, 12);

  final InMemoryWatchSessionStore store;
  final String sessionId = 'menu-rating-session';
  late final WatchSessionEngine engine;
  late final WatchSessionStartPaths paths;
  late final WatchPhonePreferences preferences;

  /// A session with one logged set on the slot the session starts with.
  Future<void> loggedSet() async {
    await engine.createSession(
      modality: 'resistance_lifting',
      exercises: <Map<String, Object?>>[
        <String, Object?>{
          'sessionExerciseId': 'sx-set',
          'exerciseId': 'ex-set',
          'name': 'Slot set',
          'capabilities': ['reps', 'sets', 'load'],
          'effortKind': 'set',
        },
      ],
    );
    await engine.appendObservation(_wristSet('entry-rating-1', 'sx-set'));
  }

  Future<WatchEffortRatingState> ratingState() async => WatchEffortRatingState(
    engine: engine,
    store: store,
    preferences: preferences,
    clock: _fixedClock,
  );
}

/// The state the S-28513 rig leaves after the End: the setting on, one logged
/// set, a prompt owed — for tests that mount `WatchEffortRatingScreen` alone.
Future<WatchEffortRatingState> _owedStateAfterEnd() async {
  final rig = _MenuRig();
  await rig.loggedSet();
  await rig.preferences.applyPreferencesDown(
    _envelope(effortRatingPrompt: true),
  );
  final rating = await rig.ratingState();
  final menu = WatchMenuState(
    engine: rig.engine,
    paths: rig.paths,
    rating: rating,
  );
  await menu.finish();
  expect(rating.isPromptOwed, isTrue);
  return rating;
}


/// Applies the phone's `preferences_down` carrying [asks].
Future<void> _applySettings(_Harness harness, {required bool asks}) async {
  expect(
    await harness.preferences.applyPreferencesDown(
      _envelope(effortRatingPrompt: asks),
    ),
    isTrue,
    reason: 'the preferences copy applies',
  );
}

/// The common fixture: 227x227 view, the setting as [asks], a running session
/// with one logged set, the shell open. Returns the harness; the session id is
/// read off `harness.engine.session!`.
Future<_Harness> _promptSetup(
  WidgetTester tester, {
  bool asks = true,
  bool withRating = true,
}) async {
  _setView(tester, 227, 227);
  final harness = _Harness(withRating: withRating);
  await _loggedSetSession(harness);
  await _applySettings(harness, asks: asks);
  await _open(tester, harness);
  return harness;
}

/// The menu's End, through its Finish question, as S-28123 drives it, then the
/// route settled and one more frame for the rating listener's rebuild.
Future<void> _endFromMenu(WidgetTester tester) async {
  await tester.tap(find.text(WearApp.menuLabel));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.text(WatchMenuCopy.finishLabel));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  // The confirm page scrolls; the action button can sit below the fold at
  // 192x192. The dialog route is not opaque, so the scrollable is picked by
  // the question title, not by type.
  await tester.scrollUntilVisible(
    find.text(WatchMenuCopy.confirmFinish),
    100,
    scrollable: find.ancestor(
      of: find.text(WatchMenuCopy.confirmTitle),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.pump();
  await tester.tap(find.text(WatchMenuCopy.confirmFinish));
  await _settle(tester);
  await tester.pump();
}

/// The menu's End when nothing is logged asks the discard question, as S-28124
/// drives it; the session then ends abandoned.
Future<void> _discardFromMenu(WidgetTester tester) async {
  await tester.tap(find.text(WearApp.menuLabel));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.text(WatchMenuCopy.finishLabel));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  // The confirm page scrolls; the action button can sit below the fold. The
  // dialog route is not opaque, so the scrollable is picked by the question
  // title, not by type.
  await tester.scrollUntilVisible(
    find.text(WatchMenuCopy.discardConfirmDiscard),
    100,
    scrollable: find.ancestor(
      of: find.text(WatchMenuCopy.discardConfirmTitle),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.pump();
  await tester.tap(find.text(WatchMenuCopy.discardConfirmDiscard));
  await _settle(tester);
  await tester.pump();
}

/// Lets a popped route retire, exactly as `test/wear_menu_screen_test.dart`'s
/// `_settle`: `pump()` without a duration advances no clock, so no periodic
/// timer fires here.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 6; i++) {
    if (find.byType(WatchMenuScreen).evaluate().isEmpty) break;
    await tester.pump(const Duration(milliseconds: 120));
  }
  await tester.pump();
}

void _setView(WidgetTester tester, double width, double height) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);
}

/// The instant the logged entries carry: fixed, never `DateTime.now()`.
final DateTime _entryClock = DateTime.utc(2026, 11, 21, 12);

/// A set the wrist logged on a slot, the shape the logging surface hands the
/// engine (`test/wear_menu_screen_test.dart` `_wristSet`).
Map<String, Object?> _wristSet(String entryId, String slotId) => {
  'entryId': entryId,
  'eventId': entryId,
  'kind': WatchObservationKind.set,
  'loggedAt': utcIso(_entryClock),
  'sessionExerciseId': slotId,
  'exerciseId': 'ex-$slotId',
  'reps': 8,
  'loadKg': 40,
};

/// One slot map, the shape a snapshot's `exercises` carries.
Map<String, Object?> _slot(String slot) => {
  'sessionExerciseId': slot,
  'exerciseId': 'ex-$slot',
  'name': slot,
  'capabilities': ['reps', 'sets', 'load'],
};

/// One `session_snapshot` from the phone, over the wrist's own session, the
/// helper from `test/watch_effort_rating_engine_test.dart`.
Map<String, Object?> _snapshotOf(
  String sessionId, {
  required String messageId,
  required List<Map<String, Object?>> entries,
}) => {
  'protocolVersion': SyncProtocolValidator.protocolVersion,
  'messageId': messageId,
  'sessionId': sessionId,
  'type': 'session_snapshot',
  'origin': 'phone',
  'sentAt': '2026-07-13T06:30:00Z',
  'payload': <String, Object?>{
    'sessionId': sessionId,
    'revision': 0,
    'status': WatchSessionStatus.active,
    'currentExerciseIndex': 0,
    'exercises': [_slot('sx-set')],
    'entries': entries,
    'timers': <String, Object?>{},
  },
};

/// The effort-rating entry the phone's own answer carries, in the shape
/// S-28406 delivers.
Map<String, Object?> _phoneRating(String sessionId) {
  final id = WatchSessionCapture.effortRatingId(sessionId);
  return {
    'entryId': id,
    'eventId': id,
    'kind': WatchObservationKind.effortRating,
    'loggedAt': '2026-07-13T06:10:00Z',
    'rating': 5,
  };
}

/// The `observations_up` frames the radio carried, whose events hold an
/// effort-rating entry.
List<MethodCall> _effortRatingFramesUp() => _calls.where((call) {
  if (call.method != 'sendMessage' && call.method != 'transferUserInfo') {
    return false;
  }
  final frame = call.arguments;
  if (frame is! Map || frame['type'] != 'observations_up') return false;
  final payload = frame['payload'];
  final events = payload is Map ? payload['events'] : null;
  return events is List &&
      events.any(
        (event) =>
            event is Map && event['kind'] == WatchObservationKind.effortRating,
      );
}).toList();

/// True when every one of [rects] lies inside the `size x size` view.
void _expectInsideView(Iterable<Rect> rects, double size) {
  for (final rect in rects) {
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(size));
    expect(rect.bottom, lessThanOrEqualTo(size));
  }
}

/// A workout the wrist ended shows its summary before the start surface (plan
/// 292): the tests that expect the start surface after an End dismiss it first.
Future<void> _doneSummary(WidgetTester tester) async {
  expect(find.text('Workout done'), findsOneWidget);
  await tester.tap(find.byKey(WatchWorkoutSummaryScreen.doneKey));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
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

  testWidgets('S-28501 End with the setting on shows the question alone', (
    tester,
  ) async {
    final harness = await _promptSetup(tester);
    final sessionId = harness.engine.session!.sessionId;

    await _endFromMenu(tester);

    // The question, alone: the numbers, the two ends, Confirm and Skip.
    expect(find.text('How hard was this session?'), findsOneWidget);
    for (final value in const ['1', '2', '3', '4', '5']) {
      expect(find.text(value), findsOneWidget);
    }
    expect(find.text('Very easy'), findsOneWidget);
    expect(find.text('Max effort'), findsOneWidget);
    expect(find.text('Confirm'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    // No other control: the shell's Menu button is not on this surface.
    expect(find.text(WearApp.menuLabel), findsNothing);
    // The session did end.
    expect(harness.engine.session!.status, WatchSessionStatus.completed);
    // Confirm waits for a pick.
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirm'))
          .onPressed,
      isNull,
    );
    // The prompt is about the session the End ended.
    expect(harness.rating!.promptSessionId, sessionId);

    expect(tester.takeException(), isNull);
  });

  testWidgets('S-28502a the setting off shows the start surface', (
    tester,
  ) async {
    final harness = await _promptSetup(tester, asks: false);

    await _endFromMenu(tester);

    expect(find.text('How hard was this session?'), findsNothing);
    await _doneSummary(tester);
    expect(find.byType(WatchStartScreen), findsOneWidget);
    expect(harness.engine.session!.status, WatchSessionStatus.completed);
    expect(harness.rating!.isPromptOwed, isFalse);

    expect(tester.takeException(), isNull);
  });

  testWidgets('S-28502b the setting on but nothing logged shows the start surface', (
    tester,
  ) async {
    _setView(tester, 227, 227);
    final harness = _Harness();
    await _kindSession(harness, 'set', ['reps', 'sets', 'load']);
    await _applySettings(harness, asks: true);
    await _open(tester, harness);

    await _discardFromMenu(tester);

    expect(find.text('How hard was this session?'), findsNothing);
    expect(find.byType(WatchStartScreen), findsOneWidget);
    expect(harness.engine.session!.status, WatchSessionStatus.abandoned);
    expect(harness.rating!.isPromptOwed, isFalse);

    expect(tester.takeException(), isNull);
  });

  testWidgets('S-28503 Confirm records the picked rating and shows the start surface', (
    tester,
  ) async {
    final harness = await _promptSetup(tester);
    final sessionId = harness.engine.session!.sessionId;
    await _endFromMenu(tester);

    await tester.tap(find.text('4'));
    await tester.pump();
    await tester.tap(find.text('Confirm'));
    await tester.pump();
    await tester.pump();

    // The engine holds the rating, exactly once on the wire.
    expect(harness.engine.hasEffortRating(sessionId), isTrue);
    final ratings = harness.engine.entries
        .where(
          (entry) =>
              entry.kind == WatchObservationKind.effortRating &&
              entry.payload['rating'] == 4,
        )
        .toList();
    expect(ratings, hasLength(1));
    expect(ratings.single.recordId, WatchSessionCapture.effortRatingId(sessionId));
    final frames = _effortRatingFramesUp();
    expect(frames, hasLength(1));
    final frame = frames.single.arguments as Map;
    expect(frame['sessionId'], sessionId);
    final events = (frame['payload'] as Map)['events'] as List;
    expect(events, hasLength(1));
    expect((events.single as Map)['kind'], WatchObservationKind.effortRating);
    expect((events.single as Map)['rating'], 4);
    // The shell is past the question; the summary of the workout follows it.
    await _doneSummary(tester);
    expect(find.byType(WatchStartScreen), findsOneWidget);
    expect(find.text('How hard was this session?'), findsNothing);

    expect(tester.takeException(), isNull);
  });

  testWidgets('S-28504 Skip shows the start surface and records nothing', (
    tester,
  ) async {
    final harness = await _promptSetup(tester);
    final sessionId = harness.engine.session!.sessionId;
    await _endFromMenu(tester);

    await tester.tap(find.text('2'));
    await tester.pump();
    await tester.tap(find.text('Skip'));
    await tester.pump();
    await tester.pump();

    await _doneSummary(tester);
    expect(find.byType(WatchStartScreen), findsOneWidget);
    expect(harness.engine.hasEffortRating(sessionId), isFalse);
    expect(_effortRatingFramesUp(), isEmpty);
    // The owed note is still stored; only the answer is absent. A fresh state
    // reads it back — skip is remembered only while the app runs.
    final contents = await harness.store.readAll();
    expect(contents.ratingPrompts, hasLength(1));
    expect(contents.ratingPrompts.single.sessionId, sessionId);
    final fresh = WatchEffortRatingState(
      engine: harness.engine,
      store: harness.store,
      preferences: harness.preferences,
    );
    await fresh.restore();
    expect(fresh.owedSessionIds, contains(sessionId));

    expect(tester.takeException(), isNull);
  });

  testWidgets('S-28505 the rotary steps the number', (tester) async {
    await _promptSetup(tester);
    await _endFromMenu(tester);

    final screen = find.byType(WatchEffortRatingScreen);
    // One detent up from nothing picks the lowest number.
    tester.binding.handlePointerEvent(
      PointerScrollEvent(
        position: tester.getCenter(screen),
        scrollDelta: const Offset(0, -32),
      ),
    );
    await tester.pump();
    expect(find.widgetWithText(FilledButton, '1'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirm'))
          .onPressed,
      isNotNull,
    );

    // Two more detents reach 3, where the stepping stops being guessed.
    for (var i = 0; i < 2; i++) {
      tester.binding.handlePointerEvent(
        PointerScrollEvent(
          position: tester.getCenter(screen),
          scrollDelta: const Offset(0, -32),
        ),
      );
      await tester.pump();
    }
    expect(find.widgetWithText(FilledButton, '1'), findsNothing);
    expect(find.widgetWithText(FilledButton, '3'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets('S-28505b a turn down from nothing picks nothing', (tester) async {
    await _promptSetup(tester);
    await _endFromMenu(tester);

    tester.binding.handlePointerEvent(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(WatchEffortRatingScreen)),
        scrollDelta: const Offset(0, 32),
      ),
    );
    await tester.pump();

    for (final value in const ['1', '2', '3', '4', '5']) {
      expect(find.widgetWithText(FilledButton, value), findsNothing);
    }
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirm'))
          .onPressed,
      isNull,
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('S-28505c the screen redraws itself when the state changes', (
    tester,
  ) async {
    _setView(tester, 227, 227);
    // The screen ALONE, no shell: the shell's own listener would hide a broken
    // binding.
    final rating = await _owedStateAfterEnd();
    await tester.pumpWidget(
      MaterialApp(home: WatchEffortRatingScreen(state: rating)),
    );
    await tester.pump();
    expect(find.text('How hard was this session?'), findsOneWidget);
    expect(find.byType(WatchStartScreen), findsNothing);

    rating.select(4);
    await tester.pump();

    // The pick moved into the filled button and enabled Confirm — the screen
    // rebuilt on the state's own notification.
    expect(find.widgetWithText(FilledButton, '4'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '4'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirm'))
          .onPressed,
      isNotNull,
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('S-28506 a vertical drag steps the number', (tester) async {
    final harness = await _promptSetup(tester);
    await _endFromMenu(tester);

    // -48, not -40: 32 points feed one detent and the recognizer needs a drag
    // past its slop; a -48 travel is one step up (a -80 drag measured two).
    await tester.drag(
      find.byType(WatchEffortRatingScreen),
      const Offset(0, -48),
    );
    await tester.pump();

    expect(find.widgetWithText(FilledButton, '1'), findsOneWidget);
    expect(harness.rating!.selected, 1);

    expect(tester.takeException(), isNull);
  });

  testWidgets('S-28507a the prompt fits 227x227', (tester) async {
    await _promptSetup(tester);
    await _endFromMenu(tester);

    expect(tester.takeException(), isNull);
    // The natural content fits at this size, so the FittedBox has not scaled
    // anything: the title's rect is the painted one, inside the view.
    _expectInsideView([
      tester.getRect(find.text('How hard was this session?')),
    ], 227);
    final rects = <Rect>[
      tester.getRect(find.widgetWithText(FilledButton, 'Confirm')),
      tester.getRect(find.widgetWithText(TextButton, 'Skip')),
      for (final value in const ['1', '2', '3', '4', '5'])
        tester.getRect(find.widgetWithText(OutlinedButton, value)),
    ];
    _expectInsideView(rects, 227);
    // `getSize` returns the UNSCALED layout size, so the declared sizes show
    // even if the FittedBox scaled the content (the S-28202 pattern).
    expect(
      tester.getSize(find.widgetWithText(FilledButton, 'Confirm')).height,
      closeTo(WatchLayout.compactButtonHeight, 0.01),
    );
    // The Skip carries the compact menu minimum; its content is taller than
    // that at this theme, so the rendered height only floors at it — the
    // declared minimum itself is what a mutant removes.
    final skipStyle =
        tester.widget<TextButton>(find.widgetWithText(TextButton, 'Skip'))
            .style;
    expect(skipStyle!.minimumSize, isNotNull);
    final skipMinimum = skipStyle.minimumSize!.resolve(const {});
    expect(skipMinimum, isNotNull);
    expect(
      skipMinimum!.height,
      closeTo(WatchLayout.compactMenuHeight, 0.01),
    );
    expect(
      tester.getSize(find.widgetWithText(TextButton, 'Skip')).height,
      greaterThanOrEqualTo(WatchLayout.compactMenuHeight - 0.01),
    );
    for (final value in const ['1', '2', '3', '4', '5']) {
      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, value),
      );
      // The declared minimum is the mutant's one-line target; the enclosing
      // SizedBox pins the rendered size to it either way, so the style is the
      // observable.
      expect(
        button.style!.minimumSize!.resolve(const {}),
        const Size(32, 36),
        reason: value,
      );
      final size = tester.getSize(find.widgetWithText(OutlinedButton, value));
      expect(size.width, lessThanOrEqualTo(32.01), reason: value);
      expect(size.height, lessThanOrEqualTo(36.01), reason: value);
    }
  });

  testWidgets('S-28507b the prompt fits 192x192', (tester) async {
    _setView(tester, 192, 192);
    final harness = _Harness();
    await _loggedSetSession(harness);
    await _applySettings(harness, asks: true);
    await _open(tester, harness);
    await _endFromMenu(tester);

    expect(tester.takeException(), isNull);
    // The natural content fits at this size, so the FittedBox has not scaled
    // anything: the title's rect is the painted one, inside the view.
    _expectInsideView([
      tester.getRect(find.text('How hard was this session?')),
    ], 192);
    final rects = <Rect>[
      tester.getRect(find.widgetWithText(FilledButton, 'Confirm')),
      tester.getRect(find.widgetWithText(TextButton, 'Skip')),
      for (final value in const ['1', '2', '3', '4', '5'])
        tester.getRect(find.widgetWithText(OutlinedButton, value)),
    ];
    _expectInsideView(rects, 192);
    // `getSize` returns the UNSCALED layout size, so the declared sizes show
    // even if the FittedBox scaled the content (the S-28202 pattern).
    expect(
      tester.getSize(find.widgetWithText(FilledButton, 'Confirm')).height,
      closeTo(WatchLayout.compactButtonHeight, 0.01),
    );
    // The Skip carries the compact menu minimum; its content is taller than
    // that at this theme, so the rendered height only floors at it — the
    // declared minimum itself is what a mutant removes.
    final skipStyle =
        tester.widget<TextButton>(find.widgetWithText(TextButton, 'Skip'))
            .style;
    expect(skipStyle!.minimumSize, isNotNull);
    final skipMinimum = skipStyle.minimumSize!.resolve(const {});
    expect(skipMinimum, isNotNull);
    expect(
      skipMinimum!.height,
      closeTo(WatchLayout.compactMenuHeight, 0.01),
    );
    expect(
      tester.getSize(find.widgetWithText(TextButton, 'Skip')).height,
      greaterThanOrEqualTo(WatchLayout.compactMenuHeight - 0.01),
    );
    for (final value in const ['1', '2', '3', '4', '5']) {
      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, value),
      );
      // The declared minimum is the mutant's one-line target; the enclosing
      // SizedBox pins the rendered size to it either way, so the style is the
      // observable.
      expect(
        button.style!.minimumSize!.resolve(const {}),
        const Size(32, 36),
        reason: value,
      );
      final size = tester.getSize(find.widgetWithText(OutlinedButton, value));
      expect(size.width, lessThanOrEqualTo(32.01), reason: value);
      expect(size.height, lessThanOrEqualTo(36.01), reason: value);
    }
  });

  testWidgets('S-28507c a crowded watch still fits the prompt', (tester) async {
    // Shorter than the content's natural height: only scale-down keeps it on
    // the 120-tall view.
    _setView(tester, 192, 120);
    final rating = await _owedStateAfterEnd();

    await tester.pumpWidget(
      MaterialApp(home: WatchEffortRatingScreen(state: rating)),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    final view = const Rect.fromLTWH(0, 0, 192, 120);
    for (final rect in <Rect>[
      tester.getRect(find.text('How hard was this session?')),
      for (final value in const ['1', '2', '3', '4', '5'])
        tester.getRect(find.widgetWithText(OutlinedButton, value)),
      tester.getRect(find.widgetWithText(FilledButton, 'Confirm')),
      tester.getRect(find.widgetWithText(TextButton, 'Skip')),
    ]) {
      // `getRect` is the painted rect, so a scale-down child is its scaled
      // self: every one lies inside the crowded view.
      expect(rect.top, greaterThanOrEqualTo(view.top), reason: '$rect');
      expect(rect.left, greaterThanOrEqualTo(view.left), reason: '$rect');
      expect(rect.right, lessThanOrEqualTo(view.right), reason: '$rect');
      expect(rect.bottom, lessThanOrEqualTo(view.bottom), reason: '$rect');
    }
  });

  testWidgets('S-28508 Confirm is disabled until a number is picked', (
    tester,
  ) async {
    final harness = await _promptSetup(tester);
    final sessionId = harness.engine.session!.sessionId;
    await _endFromMenu(tester);

    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirm'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Confirm'));
    await tester.pump();
    await tester.pump();

    expect(harness.engine.hasEffortRating(sessionId), isFalse);
    expect(_effortRatingFramesUp(), isEmpty);
    expect(find.text('How hard was this session?'), findsOneWidget);
    expect(find.byType(WatchStartScreen), findsNothing);

    expect(tester.takeException(), isNull);
  });

  testWidgets('S-28509 the numbers are named for a screen reader', (
    tester,
  ) async {
    await _promptSetup(tester);
    await _endFromMenu(tester);
    final semantics = tester.ensureSemantics();

    for (final value in const ['1 of 5', '2 of 5', '3 of 5', '4 of 5', '5 of 5']) {
      expect(find.bySemanticsLabel(value), findsOneWidget, reason: value);
    }

    await tester.tap(find.text('4'));
    await tester.pump();
    final picked = tester.getSemantics(find.bySemanticsLabel('4 of 5'));
    final unpicked = tester.getSemantics(find.bySemanticsLabel('5 of 5'));
    expect(
      picked.getSemanticsData().flagsCollection.isSelected,
      equals(Tristate.isTrue),
    );
    expect(
      unpicked.getSemanticsData().flagsCollection.isSelected,
      equals(Tristate.isFalse),
    );
    // `getSemantics` hands back a node, not a handle: the only handle is the
    // `ensureSemantics` one, disposed before the end-of-test verification.
    semantics.dispose();

    expect(tester.takeException(), isNull);
  });

  testWidgets('S-28510 the question is asked again at launch', (tester) async {
    final first = await _promptSetup(tester);
    await _endFromMenu(tester);
    expect(find.text('How hard was this session?'), findsOneWidget);

    // Close the shell; a NEW shell over the SAME store is a relaunch: a new
    // engine and a new rating state, restored from the same rows.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    final relaunched = _Harness(store: first.store);
    await _open(tester, relaunched);

    expect(find.text('How hard was this session?'), findsOneWidget);
    expect(find.byType(WatchStartScreen), findsNothing);

    expect(tester.takeException(), isNull);
  });

  testWidgets('S-28511 the phone answering first closes the prompt', (
    tester,
  ) async {
    final harness = await _promptSetup(tester);
    final sessionId = harness.engine.session!.sessionId;
    await _endFromMenu(tester);
    expect(find.text('How hard was this session?'), findsOneWidget);

    // The phone's snapshot arrives on the transport's inbound lane, the path
    // the shell binds `_onFrame` (and its rebuild) to.
    await harness.transport.deliver(
      _snapshotOf(sessionId,
          messageId: 'msg-phone-rating', entries: [_phoneRating(sessionId)]),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('How hard was this session?'), findsNothing);
    await _doneSummary(tester);
    expect(find.byType(WatchStartScreen), findsOneWidget);
    expect(harness.rating!.isPromptOwed, isFalse);

    expect(tester.takeException(), isNull);
  });

  testWidgets('S-28512 a shell without a rating state never asks', (
    tester,
  ) async {
    final harness = await _promptSetup(tester, withRating: false);

    await _endFromMenu(tester);

    expect(find.text('How hard was this session?'), findsNothing);
    await _doneSummary(tester);
    expect(find.byType(WatchStartScreen), findsOneWidget);
    expect(harness.engine.session!.status, WatchSessionStatus.completed);

    expect(tester.takeException(), isNull);
  });

  test("S-28513 the menu's End goes through the rating state", () async {
    // Setting on, a logged set: the finish leaves a prompt owed.
    final owed = _MenuRig();
    await owed.loggedSet();
    await owed.preferences.applyPreferencesDown(
      _envelope(effortRatingPrompt: true),
    );
    final owedRating = await owed.ratingState();
    final owedMenu = WatchMenuState(
      engine: owed.engine,
      paths: owed.paths,
      rating: owedRating,
    );
    await owedMenu.finish();
    expect(owedRating.isPromptOwed, isTrue);
    expect(owedRating.promptSessionId, owed.sessionId);
    expect(owed.engine.session!.status, WatchSessionStatus.completed);

    // Setting off: nothing owed, still completed.
    final quiet = _MenuRig();
    await quiet.loggedSet();
    await quiet.preferences.applyPreferencesDown(
      _envelope(effortRatingPrompt: false),
    );
    final quietRating = await quiet.ratingState();
    final quietMenu = WatchMenuState(
      engine: quiet.engine,
      paths: quiet.paths,
      rating: quietRating,
    );
    await quietMenu.finish();
    expect(quietRating.isPromptOwed, isFalse);
    expect(quiet.engine.session!.status, WatchSessionStatus.completed);
    expect(
      (await quiet.store.readAll()).ratingPrompts,
      isEmpty,
      reason: 'a setting-off End notes no owed prompt',
    );

    // No rating state wired: End is the engine's own finish, and a fresh state
    // over the same store reports nothing owed.
    final bare = _MenuRig();
    await bare.loggedSet();
    await bare.preferences.applyPreferencesDown(
      _envelope(effortRatingPrompt: true),
    );
    final bareMenu = WatchMenuState(engine: bare.engine, paths: bare.paths);
    await bareMenu.finish();
    expect(bare.engine.session!.status, WatchSessionStatus.completed);
    final fresh = await bare.ratingState();
    await fresh.restore();
    expect(fresh.isPromptOwed, isFalse);
  });

  test('S-28514 Discard owes nothing', () async {
    final rig = _MenuRig();
    await rig.loggedSet();
    await rig.preferences.applyPreferencesDown(
      _envelope(effortRatingPrompt: true),
    );
    final rating = await rig.ratingState();
    final menu = WatchMenuState(
      engine: rig.engine,
      paths: rig.paths,
      rating: rating,
    );

    await menu.discard();

    expect(rig.engine.session!.status, WatchSessionStatus.abandoned);
    expect(rating.isPromptOwed, isFalse);
    expect((await rig.store.readAll()).ratingPrompts, isEmpty);
  });
}
