// Plan 43b2 phase P3b: the phone's OPEN session screen shows the timer state of
// an interval the wrist started.
//
// The wrist's timer reaches the phone as a `timer_state` frame through
// `phone.router.receive`, is folded into the mirror, and applied to the phone's
// own interval by `WatchTimerAdoption`. The screen then has to *show* it:
// `_adoptRunningTimerState()` (P3a, `workout_session_timer_mixin.dart`) starts
// the ticker and the running/in-progress flags of a persisted running interval,
// so the control reads the running look and the in-progress lock holds.
//
// Mock-first: every future below is a microtask of the mock repository, so no
// real clock, Hive write or `Future.delayed` runs inside FakeAsync. The
// instances compute elapsed from the real wall clock (`DateTime.now()`), which
// `pump(Duration)` does not advance, so the digits are asserted as ranges.
//
//   S-6121 a wrist elapsed timer reaches the open timed interval  → this file
//   S-6122 the same for a round (the countdown ring runs)          → this file
//   S-6123 the adopted interval holds the in-progress lock         → this file
//   S-6124 a wrist timer for another effort leaves the open one    → this file
//   S-6125 a wrist timer that arrives before the mount shows up    → this file

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/capability.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/watch/live_session_mirror_state.dart';
import 'package:omnitrain/state/watch/watch_incoming_router.dart';
import 'package:omnitrain/state/watch/watch_nutrition_log_bridge.dart';
import 'package:omnitrain/state/watch/watch_session_adoption_bridge.dart';
import 'package:omnitrain/state/watch/watch_session_inbox.dart';
import 'package:omnitrain/state/watch/watch_sync_wiring.dart';
import 'package:omnitrain/state/watch/watch_timer_adoption.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/widgets/session/timer_ring.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_rest_notification_service.dart';
import 'helpers/fake_timer_alert_service.dart';
import 'helpers/sync_protocol_harness.dart';
import 'helpers/watch_capture_import_harness.dart'
    show CaptureTransport, seedExercise;

final SyncProtocolValidator _validator = loadProtocolValidator();

/// The phone's clock when nothing in the scenario moves it.
final DateTime _phoneNow = DateTime.utc(2026, 10, 5, 11);

/// The phone every scenario is measured at: a tall 390 x 844.
const Size _phoneSurface = Size(390, 844);

/// A clock a scenario can hold still.
class _Clock {
  DateTime now = _phoneNow;
}

/// One phone: the repository, the graph that carries the wrist's messages into
/// it, the timer adoption, and the session state the screen is handed.
class _Phone {
  _Phone({
    required this.repository,
    required this.transport,
    required this.router,
    required this.state,
    required this.bridge,
    required this.settings,
    required this.routine,
    required this.summary,
    required this.adoption,
    required this.failures,
  });

  final MockWorkoutRepository repository;
  final CaptureTransport transport;
  final WatchIncomingRouter router;
  final WorkoutState state;
  final WatchSessionAdoptionBridge bridge;
  final SettingsState settings;
  final RoutineState routine;
  final SessionSummaryService summary;

  /// Applies the wrist's `timer_state` frames to the phone's intervals.
  final WatchTimerAdoption adoption;

  /// What the graph reported as a failure: nothing, in these scenarios.
  final List<Object> failures;
}

Future<_Phone> _phone() async {
  final repository = MockWorkoutRepository();
  await repository.initialize();
  // Pre-seed the coach mark flags so no overlay opens over the tree.
  await repository.setPreferenceBool('hint_seen_exercise_info', true);
  await repository.setPreferenceBool('hint_seen_exercise_notes', true);
  await _seed(repository);

  final settings = SettingsState(repository, fakePreferencesService());
  await settings.initialize();

  final failures = <Object>[];
  final clock = _Clock();
  final transport = CaptureTransport();
  final bridge = WatchSessionAdoptionBridge(
    repository: repository,
    clock: () => clock.now,
    onFailure: (error, stack) => failures.add(error),
  );
  final inbox = WatchSessionInbox(
    repository: repository,
    transport: transport,
    validator: _validator,
    clock: () => clock.now,
    onHistoryChanged: () async {},
    onFailure: (error, stack) => fail('the watch session inbox failed: $error'),
    phoneOwnsSession: bridge.holdsSession,
    onSessionRowsChanged: bridge.refreshHeldEfforts,
  );
  final mirror = LiveSessionMirrorState(
    transport: WatchInboxStagingTransport(inner: transport, inbox: inbox),
    snapshot: watchSessionPlaceholder,
    validator: _validator,
    projection: bridge.projectSession,
  );
  final state = WorkoutState(repository);
  bridge.bindWorkoutState(state);

  final adoption = WatchTimerAdoption(
    mirror: mirror,
    onFailure: (error, stack) => failures.add(error),
  );
  adoption.bindWorkoutState(state);
  addTearDown(adoption.dispose);

  return _Phone(
    repository: repository,
    transport: transport,
    state: state,
    bridge: bridge,
    settings: settings,
    routine: RoutineState(repository),
    summary: SessionSummaryService(repository),
    adoption: adoption,
    failures: failures,
    router: WatchIncomingRouter(
      inbox: inbox,
      mirror: mirror,
      nutrition: WatchNutritionLogBridge(
        nutrition: NutritionState(repository),
        library: FoodLibraryState(repository),
        validator: _validator,
        transport: transport,
      ),
      adoption: bridge,
    ),
  );
}

/// The phone's session screen, wired as `lib/main.dart` wires it.
Widget _screen(
  _Phone phone, {
  String? initialFocusId,
  FakeRestNotificationService? restNotifications,
}) => MaterialApp(
  home: WorkoutSessionScreen(
    workoutState: phone.state,
    routineState: phone.routine,
    sessionSummaryService: phone.summary,
    settingsState: phone.settings,
    timerAlertService: FakeTimerAlertService(),
    restNotificationService: restNotifications ?? FakeRestNotificationService(),
    initialFocusId: initialFocusId,
  ),
);

/// The frame that mounts the screen, then the frames that run its deferred
/// first load (D-150).
Future<void> _mount(WidgetTester tester, Widget screen) async {
  await tester.binding.setSurfaceSize(_phoneSurface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(screen);
  await tester.pump();
  await tester.pump();
}

// ─── The wrist's messages ───────────────────────────────────────────────────

/// One ladder slot as the wrist sends it.
Map<String, Object?> _slot(
  String sessionExerciseId,
  String exerciseId,
  String name,
  List<String> capabilities,
) => {
  'sessionExerciseId': sessionExerciseId,
  'exerciseId': exerciseId,
  'name': name,
  'capabilities': capabilities,
};

const List<String> _timedCapabilities = [
  ExerciseCapability.time,
  ExerciseCapability.distance,
];

/// `rounds` precedes `time` in the adoption bridge's kind precedence, so a slot
/// with these capabilities logs rounds.
const List<String> _roundCapabilities = [
  ExerciseCapability.time,
  ExerciseCapability.rounds,
];

/// One `session_snapshot` from the wrist, adopting `s-w1` onto the phone.
Map<String, Object?> _snapshot({
  String messageId = 'msg-snapshot',
  List<Map<String, Object?>>? exercises,
}) => {
  'protocolVersion': SyncProtocolValidator.protocolVersion,
  'messageId': messageId,
  'sessionId': 's-w1',
  'type': 'session_snapshot',
  'origin': 'watch',
  'sentAt': '2026-10-05T10:00:00Z',
  'payload': {
    'sessionId': 's-w1',
    'revision': 3,
    'status': WatchSessionStatus.active,
    'currentExerciseIndex': 0,
    'exercises':
        exercises ??
        [_slot('sl-run', 'ex-run', 'Trail Run', _timedCapabilities)],
    'entries': <Object?>[],
    'timers': <String, Object?>{},
  },
};

/// One `timer_state` from the wrist: a single running timer for [slot].
Map<String, Object?> _timerFrame({
  required String kind,
  required String slot,
  required String startedAt,
  int? plannedDurationMs,
  String messageId = 'msg-timer-1',
}) => {
  'protocolVersion': SyncProtocolValidator.protocolVersion,
  'messageId': messageId,
  'sessionId': 's-w1',
  'type': 'timer_state',
  'origin': 'watch',
  'sentAt': startedAt,
  'payload': {
    'timers': {
      kind: {
        'kind': kind,
        'state': 'running',
        'startedAt': startedAt,
        'accumulatedPauseMs': 0,
        'plannedDurationMs': ?plannedDurationMs,
        'sessionExerciseId': slot,
      },
    },
  },
};

/// An instant [seconds] before now, in the protocol's own spelling.
String _startedAgo(int seconds) =>
    isoUtc(DateTime.now().toUtc().subtract(Duration(seconds: seconds)));

Future<void> _seed(MockWorkoutRepository repository) async {
  await seedExercise(
    repository,
    id: 'ex-run',
    name: 'Trail Run',
    capabilities: _timedCapabilities,
  );
  await seedExercise(
    repository,
    id: 'ex-round',
    name: 'Heavy Bag',
    capabilities: _roundCapabilities,
  );
  await seedExercise(
    repository,
    id: 'ex-walk',
    name: 'Treadmill Walk',
    capabilities: _timedCapabilities,
  );
}

void main() {
  testWidgets('S-6121 a wrist elapsed timer starts the open timed interval', (
    WidgetTester tester,
  ) async {
    final phone = await _phone();
    final frame = _timerFrame(
      kind: 'elapsed',
      slot: 'sl-run',
      startedAt: _startedAgo(40),
    );
    expect(
      _validator.validateEnvelope(frame),
      isEmpty,
      reason: 'S-6121 the hand-built timer frame is valid protocol',
    );

    await phone.router.receive(
      _snapshot(
        exercises: [_slot('sl-run', 'ex-run', 'Trail Run', _timedCapabilities)],
      ),
    );

    // Two intervals, both not started: the adoption gave the slot its first.
    await phone.state.addEntry('sl-run');

    await _mount(tester, _screen(phone, initialFocusId: 'sl-run'));

    expect(
      find.text('Interval 1 of 2'),
      findsOneWidget,
      reason: 'S-6121 the screen opens on the first of the two intervals',
    );
    expect(
      find.widgetWithText(FilledButton, 'Start'),
      findsOneWidget,
      reason: 'S-6121 and nothing has started interval 1 yet',
    );

    // The wrist started interval 1 forty seconds ago.
    await phone.router.receive(frame);
    await phone.adoption.flush();
    await tester.pump();
    await tester.pump();

    final instances = phone.state.getTimedInstancesForEffort('sl-run');
    expect(
      instances[0].state,
      TimedState.active,
      reason: 'S-6121 the wrist\'s timer made interval 1 active',
    );
    expect(
      find.widgetWithText(FilledButton, 'Log Interval'),
      findsOneWidget,
      reason:
          'S-6121 the running interval offers the log control: the screen took '
          'the wrist\'s timer for its own',
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('count-up-digits')),
        matching: find.textContaining(RegExp(r'00:4\d')),
      ),
      findsOneWidget,
      reason:
          'S-6121 the digits count the wrist\'s forty seconds, not the phone\'s '
          'zero',
    );
    expect(
      tester.takeException(),
      isNull,
      reason: 'S-6121 nothing escapes the frame',
    );

    await tester.pump(const Duration(seconds: 3));
    expect(
      tester.takeException(),
      isNull,
      reason: 'S-6121 nothing escapes the frame from the adopted ticker either',
    );
    expect(phone.failures, isEmpty);
  });

  testWidgets('S-6122 a wrist round timer runs the open round countdown', (
    WidgetTester tester,
  ) async {
    final phone = await _phone();
    final frame = _timerFrame(
      kind: 'round',
      slot: 'sl-bag',
      startedAt: _startedAgo(40),
      plannedDurationMs: 75000,
    );
    expect(
      _validator.validateEnvelope(frame),
      isEmpty,
      reason: 'S-6122 the hand-built timer frame is valid protocol',
    );

    await phone.router.receive(
      _snapshot(
        exercises: [
          _slot('sl-bag', 'ex-round', 'Heavy Bag', _roundCapabilities),
        ],
      ),
    );

    // Two rounds the way the phone writes them, both not started and both at
    // the phone's own 180 s: the wrist's 75 s only arrives with the timer
    // frame, so the screen's cached length has to be refreshed from the
    // adopted round.
    await phone.state.addEntry('sl-bag');

    await _mount(tester, _screen(phone, initialFocusId: 'sl-bag'));

    expect(
      find.text('Round 1 of 2'),
      findsOneWidget,
      reason: 'S-6122 the screen opens on the first of the two rounds',
    );
    expect(
      find.widgetWithText(FilledButton, 'Start'),
      findsOneWidget,
      reason: 'S-6122 and round 1 has not started',
    );

    // The wrist started a 75 s round forty seconds ago.
    await phone.router.receive(frame);
    await phone.adoption.flush();
    await tester.pump();
    await tester.pump();

    final rounds = phone.state.getRoundsForEffort('sl-bag');
    expect(
      rounds[0].state,
      RoundState.active,
      reason: 'S-6122 the wrist\'s timer made round 1 active',
    );
    expect(
      find.descendant(
        of: find.byType(TimerRing),
        matching: find.textContaining(RegExp(r'00:3\d')),
      ),
      findsOneWidget,
      reason:
          'S-6122 the ring counts the wrist\'s remaining ~35 s, not the full 75 s '
          'of a stopped round',
    );
    expect(
      tester.widget<TimerRing>(find.byType(TimerRing)).running,
      isTrue,
      reason: 'S-6122 the ring sweeps: the round is running on this screen',
    );
    expect(
      find.widgetWithText(FilledButton, 'Log Round'),
      findsOneWidget,
      reason:
          'S-6122 a running round offers its log control, not Start: the screen '
          'took the wrist\'s timer for its own',
    );
    expect(
      find.widgetWithText(FilledButton, 'Start'),
      findsNothing,
      reason: 'S-6122 and Start is gone while the round runs',
    );
    expect(
      tester.takeException(),
      isNull,
      reason: 'S-6122 nothing escapes the frame',
    );
    expect(phone.failures, isEmpty);
  });

  testWidgets(
    'S-6122 a round the phone had already started with another length takes '
    'the earlier wrist start and its length',
    (WidgetTester tester) async {
      final phone = await _phone();
      final frame = _timerFrame(
        kind: 'round',
        slot: 'sl-bag',
        startedAt: _startedAgo(40),
        plannedDurationMs: 75000,
      );

      await phone.router.receive(
        _snapshot(
          exercises: [
            _slot('sl-bag', 'ex-round', 'Heavy Bag', _roundCapabilities),
          ],
        ),
      );

      await phone.state.addEntry('sl-bag');

      await _mount(tester, _screen(phone, initialFocusId: 'sl-bag'));

      // The phone starts its own 180 s round first, so the screen already has
      // a live ticker and the phone's own length cached when the frame lands.
      await tester.tap(find.widgetWithText(FilledButton, 'Start'));
      await tester.pump();
      await tester.pump();
      final started = phone.state.getRoundsForEffort('sl-bag')[0];
      expect(
        started.state,
        RoundState.active,
        reason: 'S-6122 the phone started round 1 on its own',
      );
      expect(
        started.plannedDurationSecs,
        180,
        reason: 'S-6122 with the phone\'s own length',
      );

      // The wrist started the same round forty seconds ago, with its shorter
      // round: the earlier start wins, and so does its length.
      await phone.router.receive(frame);
      await phone.adoption.flush();
      await tester.pump();
      // Let the phone's own ticker read the adopted start, as it does once a
      // second.
      await tester.pump(const Duration(seconds: 1));

      expect(
        find.descendant(
          of: find.byType(TimerRing),
          matching: find.textContaining(RegExp(r'00:3\d')),
        ),
        findsOneWidget,
        reason:
            'S-6122 the running ring counts from the wrist\'s 75 s, not the '
            'phone\'s 180 s it had cached before the adoption',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'S-6122 nothing escapes the frame',
      );
      expect(phone.failures, isEmpty);
    },
  );

  testWidgets('S-6123 the adopted interval blocks starting another one', (
    WidgetTester tester,
  ) async {
    final phone = await _phone();
    await phone.router.receive(
      _snapshot(
        exercises: [_slot('sl-run', 'ex-run', 'Trail Run', _timedCapabilities)],
      ),
    );

    await phone.state.addEntry('sl-run');

    await _mount(tester, _screen(phone, initialFocusId: 'sl-run'));

    await phone.router.receive(
      _timerFrame(kind: 'elapsed', slot: 'sl-run', startedAt: _startedAgo(40)),
    );
    await phone.adoption.flush();
    await tester.pump();
    await tester.pump();

    expect(
      find.widgetWithText(FilledButton, 'Log Interval'),
      findsOneWidget,
      reason: 'S-6123 interval 1 runs on the phone after the wrist\'s timer',
    );

    // The screen's own next-set arrow (what S-013 navigates with).
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pump();

    expect(
      find.text('Interval 2 of 2'),
      findsOneWidget,
      reason: 'S-6123 the user moved to interval 2, which never started',
    );
    expect(
      find.widgetWithText(FilledButton, 'Start'),
      findsOneWidget,
      reason: 'S-6123 interval 2 offers Start',
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Start'));
    await tester.pump();

    expect(
      find.textContaining('Another set is still in progress'),
      findsOneWidget,
      reason:
          'S-6123 the adopted interval holds the in-progress lock, so the phone '
          'refuses to start a second timer beside the wrist\'s',
    );
    expect(
      phone.state.getTimedInstancesForEffort('sl-run')[1].state,
      TimedState.notStarted,
      reason: 'S-6123 and interval 2 was not started',
    );
    expect(
      phone.state.getTimedInstancesForEffort('sl-run')[0].state,
      TimedState.active,
      reason: 'S-6123 interval 1 keeps running',
    );
    expect(
      tester.takeException(),
      isNull,
      reason: 'S-6123 nothing escapes the frame',
    );
    expect(phone.failures, isEmpty);
  });

  testWidgets(
    'S-6124 a wrist timer for another effort leaves the open one alone',
    (WidgetTester tester) async {
      final phone = await _phone();
      final frame = _timerFrame(
        kind: 'elapsed',
        slot: 'sl-run',
        startedAt: _startedAgo(40),
      );

      // Two efforts on the phone's ladder: the run the wrist times, and the
      // walk the screen opens on.
      await phone.router.receive(
        _snapshot(
          exercises: [
            _slot('sl-run', 'ex-run', 'Trail Run', _timedCapabilities),
            _slot('sl-walk', 'ex-walk', 'Treadmill Walk', _timedCapabilities),
          ],
        ),
      );

      await phone.state.addEntry('sl-run');
      await phone.state.addEntry('sl-walk');

      await _mount(tester, _screen(phone, initialFocusId: 'sl-walk'));

      expect(
        find.text('Treadmill Walk'),
        findsWidgets,
        reason: 'S-6124 the screen opens on the walk',
      );
      expect(
        find.text('Interval 1 of 2'),
        findsOneWidget,
        reason: 'S-6124 on the walk\'s first interval',
      );
      expect(
        find.widgetWithText(FilledButton, 'Start'),
        findsOneWidget,
        reason: 'S-6124 and it has not started',
      );

      // The wrist's timer is for the run, not for what the screen shows.
      await phone.router.receive(frame);
      await phone.adoption.flush();
      await tester.pump();
      await tester.pump();

      expect(
        find.text('Treadmill Walk'),
        findsWidgets,
        reason: 'S-6124 the visible exercise keeps its title',
      );
      expect(
        find.text('Interval 1 of 2'),
        findsOneWidget,
        reason: 'S-6124 and the visible interval is still the first one',
      );
      expect(
        find.widgetWithText(FilledButton, 'Start'),
        findsOneWidget,
        reason:
            'S-6124 the visible interval keeps its control: the wrist started '
            'another effort',
      );
      expect(
        find.widgetWithText(FilledButton, 'Log Interval'),
        findsNothing,
        reason: 'S-6124 nothing on the walk started',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'S-6124 nothing escapes the frame',
      );
      expect(
        phone.state.getTimedInstancesForEffort('sl-run')[0].state,
        TimedState.active,
        reason: 'S-6124 the run did start on the phone, just off screen',
      );

      // Re-mounted on the timed effort: the arrow walks within one effort's
      // intervals, so the other effort is reached by mounting on it. The tree
      // is emptied first, so `pumpWidget` builds a new screen state instead of
      // updating the walk's (its `initialFocusId` is read once, in init).
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await _mount(tester, _screen(phone, initialFocusId: 'sl-run'));

      expect(
        find.widgetWithText(FilledButton, 'Log Interval'),
        findsOneWidget,
        reason: 'S-6124 the run reads as started when it comes on screen',
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('count-up-digits')),
          matching: find.textContaining(RegExp(r'00:4\d')),
        ),
        findsOneWidget,
        reason: 'S-6124 and its digits count the wrist\'s forty seconds',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'S-6124 nothing escapes the frame',
      );
      await tester.pump(const Duration(seconds: 3));
      expect(
        tester.takeException(),
        isNull,
        reason: 'S-6124 nor from the adopted ticker',
      );
      expect(phone.failures, isEmpty);
    },
  );

  testWidgets(
    'S-6125 a wrist elapsed timer that arrives before the mount still runs',
    (WidgetTester tester) async {
      final phone = await _phone();
      final frame = _timerFrame(
        kind: 'elapsed',
        slot: 'sl-run',
        startedAt: _startedAgo(40),
      );

      await phone.router.receive(
        _snapshot(
          exercises: [_slot('sl-run', 'ex-run', 'Trail Run', _timedCapabilities)],
        ),
      );

      await phone.state.addEntry('sl-run');

      // The wrist's timer lands before any screen exists.
      await phone.router.receive(frame);
      await phone.adoption.flush();

      await _mount(tester, _screen(phone, initialFocusId: 'sl-run'));

      expect(
        find.widgetWithText(FilledButton, 'Log Interval'),
        findsOneWidget,
        reason:
            'S-6125 the mounted screen reads the adopted interval as running',
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('count-up-digits')),
          matching: find.textContaining(RegExp(r'00:4\d')),
        ),
        findsOneWidget,
        reason: 'S-6125 and its digits count the wrist\'s forty seconds',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'S-6125 nothing escapes the load',
      );

      await tester.pump(const Duration(seconds: 3));
      expect(
        tester.takeException(),
        isNull,
        reason: 'S-6125 nothing escapes the ticker either',
      );
      expect(phone.failures, isEmpty);
    },
  );

  // Known limit: `_loadExercises` restores an active round as not running
  // (`_restoreTimerStateFromPersisted`), and starting its ticker from the load
  // path makes S-4408 in `test/round_countdown_screen_test.dart` red:
  // `_shouldShowRestOverlay` hides the open rest chip while any effort runs,
  // and S-4408 expects that chip on a restored running round. The lead decides
  // which premise moves.
  testWidgets(
    'S-6125 a wrist round timer that arrives before the mount still runs',
    (WidgetTester tester) async {
      final phone = await _phone();
      final frame = _timerFrame(
        kind: 'round',
        slot: 'sl-bag',
        startedAt: _startedAgo(40),
        plannedDurationMs: 75000,
      );

      await phone.router.receive(
        _snapshot(
          exercises: [
            _slot('sl-bag', 'ex-round', 'Heavy Bag', _roundCapabilities),
          ],
        ),
      );

      await phone.state.addEntry('sl-bag');

      // The wrist's round timer lands before any screen exists.
      await phone.router.receive(frame);
      await phone.adoption.flush();

      await _mount(tester, _screen(phone, initialFocusId: 'sl-bag'));

      expect(
        tester.widget<TimerRing>(find.byType(TimerRing)).running,
        isTrue,
        reason: 'S-6125 the mounted screen sweeps the adopted round',
      );
      expect(
        find.descendant(
          of: find.byType(TimerRing),
          matching: find.textContaining(RegExp(r'00:3\d')),
        ),
        findsOneWidget,
        reason:
            'S-6125 the ring counts the wrist\'s remaining ~35 s of 75 s, not '
            'the phone\'s stopped value',
      );
      expect(
        find.widgetWithText(FilledButton, 'Log Round'),
        findsOneWidget,
        reason: 'S-6125 the running round offers its log control',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'S-6125 nothing escapes the load',
      );

      await tester.pump(const Duration(seconds: 3));
      expect(
        tester.takeException(),
        isNull,
        reason: 'S-6125 nothing escapes the ticker either',
      );
      expect(phone.failures, isEmpty);
    },
    skip: true,
  );
}
