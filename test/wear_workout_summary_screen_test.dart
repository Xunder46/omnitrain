// The Wear wrist's end-of-workout summary as a screen and in the shell (plan
// 292, D-29204, D-29205).
//
// Scenario mapping:
//   S-29210  the screen: title, rows, Done; no Avg HR row without heart rate
//   S-29211  Done calls back once
//   S-29212  the shell shows it after Finish, Done returns to the start screen
//   S-29213  with the effort question on: the question first, then the summary
//   S-29214  the screen fits 192 and 227 dp and Done is reachable
//   S-29215  an empty workout and one the phone ended show none
//   S-29216  a new workout gives way over a summary
//
// Mock-first: an in-memory store, a fake link and never a real
// `Future.delayed` inside `testWidgets` (FakeAsync would hang on it). The shell
// and the screens own 1 s periodic timers, so `pumpAndSettle` is never used;
// every wait is an explicit `pump`. The harness is copied from
// `test/wear_effort_rating_screen_test.dart`.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain_watch_link/omnitrain_watch_link.dart';

import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/watch/app/wear_app.dart';
import 'package:omnitrain/watch/app/wear_watch_transport.dart';
import 'package:omnitrain/watch/logging/watch_effort_rating_state.dart';
import 'package:omnitrain/watch/logging/watch_menu_state.dart';
import 'package:omnitrain/watch/logging/watch_workout_summary.dart';
import 'package:omnitrain/watch/logging/watch_workout_summary_screen.dart';
import 'package:omnitrain/watch/nutrition/watch_nutrition_state.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';
import 'package:omnitrain/watch/start/watch_phone_preferences.dart';
import 'package:omnitrain/watch/start/watch_session_start_paths.dart';
import 'package:omnitrain/watch/start/watch_start_screen.dart';
import 'package:omnitrain/watch/start/watch_sync_orchestrator.dart';

const MethodChannel _methods = MethodChannel('omnitrain/watch_link/methods');
const EventChannel _events = EventChannel('omnitrain/watch_link/events');

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

final DateTime _entryClock = DateTime.utc(2026, 11, 22, 9);

WatchWorkoutSummary _summary({
  int efforts = 12,
  bool allSets = true,
  int? bpm = 128,
  int seconds = 754,
}) => WatchWorkoutSummary(
  sessionId: 's-1',
  startedAt: _entryClock,
  endedAt: _entryClock.add(Duration(seconds: seconds)),
  effortCount: efforts,
  allSets: allSets,
  averageBpm: bpm,
);

Widget _screen(WatchWorkoutSummary summary, VoidCallback onDone) => MaterialApp(
  theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
  home: WatchWorkoutSummaryScreen(summary: summary, onDone: onDone),
);

class _Harness {
  _Harness({bool withRating = false})
    : store = InMemoryWatchSessionStore(),
      transport = WearWatchTransport(link: WatchLink()) {
    engine = WatchSessionEngine(store, onEmit: transport.send);
    paths = WatchSessionStartPaths(engine: engine, store: store);
    nutrition = WatchNutritionState(engine: engine, store: store);
    preferences = WatchPhonePreferences(store: store);
    if (withRating) {
      rating = WatchEffortRatingState(
        engine: engine,
        store: store,
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

  Future<void> session({bool withSet = true}) async {
    await engine.createSession(
      modality: 'resistance_lifting',
      exercises: [
        {
          'sessionExerciseId': 'sx-set',
          'exerciseId': 'ex-set',
          'name': 'Slot set',
          'capabilities': ['reps', 'sets', 'load'],
        },
      ],
    );
    if (withSet) {
      await engine.appendObservation({
        'entryId': 'entry-summary-1',
        'eventId': 'entry-summary-1',
        'kind': WatchObservationKind.set,
        'loggedAt': utcIso(_entryClock),
        'sessionExerciseId': 'sx-set',
        'exerciseId': 'ex-set',
        'reps': 8,
        'loadKg': 40,
      });
    }
  }
}

Future<void> _open(WidgetTester tester, _Harness harness) async {
  await tester.pumpWidget(harness.app());
  for (var i = 0; i < 8; i++) {
    await tester.pump();
  }
}

/// The menu's End, through its Finish question, as the rating test drives it.
Future<void> _endFromMenu(WidgetTester tester) async {
  await tester.tap(find.text(WearApp.menuLabel));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.text(WatchMenuCopy.finishLabel));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
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
  await tester.pump();
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
  await tester.pump();
}

void _setView(WidgetTester tester, double width, double height) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);
}

Map<String, Object?> _lifecycleFrame(String sessionId, String state) => {
  'protocolVersion': SyncProtocolValidator.protocolVersion,
  'messageId': 'msg-$state-summary',
  'sessionId': sessionId,
  'type': 'session_lifecycle',
  'origin': 'phone',
  'sentAt': '2026-11-22T10:00:00Z',
  'payload': {'state': state, 'at': '2026-11-22T10:00:00Z'},
};

Map<String, Object?> _ratingOn() => {
  'protocolVersion': 1,
  'messageId': 'msg-prefs-summary',
  'type': 'preferences_down',
  'origin': 'phone',
  'sentAt': '2026-11-22T08:00:00Z',
  'payload': {
    'generatedAt': '2026-11-22T08:00:00Z',
    'effortRatingPrompt': true,
    'restPingSeconds': 0,
  },
};

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

  testWidgets('S-29210 the screen: title, rows and Done', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_screen(_summary(), () {}));

    expect(find.text('Workout done'), findsOneWidget);
    expect(find.text('Time'), findsOneWidget);
    expect(find.text('12:34'), findsOneWidget);
    expect(find.text('Sets'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('Avg HR'), findsOneWidget);
    expect(find.text('128 bpm'), findsOneWidget);
    expect(find.byKey(WatchWorkoutSummaryScreen.doneKey), findsOneWidget);
    final time = tester.getSemantics(find.bySemanticsLabel('Time'));
    expect(time.value, '12:34', reason: 'a row is one node: label and value');

    await tester.pumpWidget(
      _screen(_summary(bpm: null, allSets: false), () {}),
    );
    expect(find.text('Avg HR'), findsNothing, reason: 'no heart rate');
    expect(find.text('Efforts'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('S-29211 Done calls back once', (tester) async {
    var done = 0;
    await tester.pumpWidget(_screen(_summary(), () => done++));

    await tester.tap(find.byKey(WatchWorkoutSummaryScreen.doneKey));
    await tester.pump();

    expect(done, 1);
  });

  testWidgets('S-29212 the shell shows it after Finish and Done returns', (
    tester,
  ) async {
    _setView(tester, 227, 227);
    final harness = _Harness();
    await harness.session();
    await _open(tester, harness);

    await _endFromMenu(tester);

    expect(find.text('Workout done'), findsOneWidget);
    expect(find.text('Sets'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text(WearApp.menuLabel), findsNothing);

    await tester.tap(find.byKey(WatchWorkoutSummaryScreen.doneKey));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Workout done'), findsNothing);
    expect(find.text(WatchStartScreen.logFoodLabel), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'S-29213 with the question on: the question first, then the summary',
    (tester) async {
      _setView(tester, 227, 227);
      final harness = _Harness(withRating: true);
      await harness.session();
      await harness.preferences.applyPreferencesDown(_ratingOn());
      await _open(tester, harness);

      await _endFromMenu(tester);

      expect(find.text('How hard was this session?'), findsOneWidget);
      expect(
        find.text('Workout done'),
        findsNothing,
        reason: 'the question wins',
      );

      await tester.tap(find.text('Skip'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Workout done'), findsOneWidget);
      await tester.tap(find.byKey(WatchWorkoutSummaryScreen.doneKey));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(find.text(WatchStartScreen.logFoodLabel), findsOneWidget);
    },
  );

  for (final side in const [192.0, 227.0]) {
    testWidgets('S-29214 the screen fits ${side}dp and Done is reachable', (
      tester,
    ) async {
      _setView(tester, side, side);
      var done = 0;
      await tester.pumpWidget(
        _screen(
          _summary(seconds: 3725, allSets: false, efforts: 12),
          () => done++,
        ),
      );

      expect(tester.takeException(), isNull, reason: 'no overflow');
      expect(find.text('1:02:05'), findsOneWidget);
      await tester.ensureVisible(find.byKey(WatchWorkoutSummaryScreen.doneKey));
      await tester.pump();
      await tester.tap(find.byKey(WatchWorkoutSummaryScreen.doneKey));
      expect(done, 1);
    });
  }

  testWidgets('S-29215 an empty workout and one the phone ended show none', (
    tester,
  ) async {
    _setView(tester, 227, 227);
    final empty = _Harness();
    await empty.session(withSet: false);
    await _open(tester, empty);
    await empty.engine.finishSession();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Workout done'), findsNothing, reason: 'nothing logged');
    expect(find.text(WatchStartScreen.logFoodLabel), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    final phone = _Harness();
    await phone.session();
    await _open(tester, phone);
    await phone.transport.deliver(
      _lifecycleFrame(phone.engine.session!.sessionId, 'completed'),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(phone.engine.session!.status, WatchSessionStatus.completed);
    expect(
      find.text('Workout done'),
      findsNothing,
      reason: 'the phone ended it',
    );
    expect(find.text(WatchStartScreen.logFoodLabel), findsOneWidget);
  });

  testWidgets('S-29216 a new workout gives way over a summary', (tester) async {
    _setView(tester, 227, 227);
    final harness = _Harness();
    await harness.session();
    await _open(tester, harness);
    await _endFromMenu(tester);
    expect(find.text('Workout done'), findsOneWidget, reason: 'the premise');

    await harness.session(withSet: false);
    // The shell redraws on what the phone sends: any arriving frame does it
    // (the ticker is off after the End).
    await harness.transport.deliver(_ratingOn());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Workout done'), findsNothing);
    expect(
      find.text('Log'),
      findsOneWidget,
      reason: 'the new workout\'s surface',
    );
  });
}
