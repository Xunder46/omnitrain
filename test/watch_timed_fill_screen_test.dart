// Plan 43a phase P2 (D-4, D-5): the phone's OPEN session screen lets go of the
// timer UI state of an interval the wrist finished.
//
// The importer (P1) fills the phone's first unfinished interval with the
// wrist's timed, hold or round entry. Before P2 the open screen's resync
// replaced `_exercises` only: the ticker the phone had running for that
// position kept firing as a no-op, and `_effortRunning`/`_inProgressKeys` kept
// the key until the next `_toggleEffortTimer` drained it. `_dropFinishedTimerState`
// runs inside `_resyncExercisesFromState` and drops those keys.
//
// Mock-first: every future below is a microtask of the mock repository, so no
// real clock, Hive write or `Future.delayed` runs inside FakeAsync.
//
//   S-5008 the crash probe: a running phone interval the wrist fills → this file
//   S-5009 the same on a round effort                                 → this file

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
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/widgets/session/set_segment_bar.dart';
import 'package:omnitrain/widgets/session/timer_ring.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_rest_notification_service.dart';
import 'helpers/fake_timer_alert_service.dart';
import 'helpers/sync_protocol_harness.dart';
import 'helpers/watch_capture_import_harness.dart'
    show CaptureTransport, observationsUp, seedExercise;

final SyncProtocolValidator _validator = loadProtocolValidator();

/// The phone's clock when nothing in the scenario moves it.
final DateTime _phoneNow = DateTime.utc(2026, 10, 5, 11);

const String _t1 = '2026-10-05T10:10:00Z';
const String _t3 = '2026-10-05T10:30:00Z';

/// The phone every scenario is measured at: a tall 390 x 844.
const Size _phoneSurface = Size(390, 844);

/// A clock a scenario can hold still.
class _Clock {
  DateTime now = _phoneNow;
}

/// One phone: the repository, the graph that carries the wrist's messages into
/// it, and the session state the screen is handed.
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

  return _Phone(
    repository: repository,
    transport: transport,
    state: state,
    bridge: bridge,
    settings: settings,
    routine: RoutineState(repository),
    summary: SessionSummaryService(repository),
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
/// with these capabilities logs rounds (`test/round_countdown_screen_test.dart`
/// seeds the same way).
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

/// A timed entry the wrist logged (cardio): 20 minutes, `T1` to `T3`.
Map<String, Object?> _timed(
  String entryId, {
  required String slot,
  required String exerciseId,
  required String startedAt,
  required String endedAt,
}) => {
  'entryId': entryId,
  'eventId': entryId,
  'kind': 'timed',
  'loggedAt': endedAt,
  'sessionExerciseId': slot,
  'exerciseId': exerciseId,
  'startedAt': startedAt,
  'endedAt': endedAt,
};

/// A round entry the wrist logged, 20 minutes in the same window.
Map<String, Object?> _round(
  String entryId, {
  required String slot,
  required String exerciseId,
  required int roundNumber,
  required String startedAt,
  required String endedAt,
}) => {
  'entryId': entryId,
  'eventId': entryId,
  'kind': 'round',
  'loggedAt': endedAt,
  'sessionExerciseId': slot,
  'exerciseId': exerciseId,
  'startedAt': startedAt,
  'endedAt': endedAt,
  'roundNumber': roundNumber,
};

// ─── Reading what happened ──────────────────────────────────────────────────

/// The entries of one displayed exercise, as the screen reads them.
List<Map<String, dynamic>> _entriesOf(_Phone phone, String effortId) {
  final exercise = phone.state.getExercisesWithEntries().firstWhere(
    (e) => e['id'] == effortId,
  );
  return (exercise['entries'] as List).cast<Map<String, dynamic>>();
}

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
}

void main() {
  testWidgets(
    'S-5008 a watch interval fills the open timed effort and the phone\'s running timer stops',
    (WidgetTester tester) async {
      final phone = await _phone();
      await phone.router.receive(
        _snapshot(
          exercises: [
            _slot('sl-run', 'ex-run', 'Trail Run', _timedCapabilities),
          ],
        ),
      );

      // Two intervals the way the phone writes them: an instance plus its
      // distance rows each, both not started.
      await phone.state.addEntry('sl-run');
      await phone.state.addEntry('sl-run');

      // Interval 1 is the phone's own: started, then logged through the state
      // (`finishTimedEntry` after `startTimedEntry`), which is what the screen's
      // Log Interval control does in one tap.
      await phone.state.startTimedEntry('sl-run', 0);
      await phone.state.finishTimedEntry('sl-run', 0);

      await _mount(tester, _screen(phone, initialFocusId: 'sl-run'));

      expect(
        find.text('Interval 2 of 2'),
        findsOneWidget,
        reason:
            'S-5008 the screen opens on the first unfinished interval of the two the '
            'phone wrote',
      );
      expect(
        find.widgetWithText(FilledButton, 'Start'),
        findsOneWidget,
        reason: 'S-5008 and nothing has started interval 2 yet',
      );

      // The phone's own timer on interval 2, through the screen's start control.
      await tester.tap(find.widgetWithText(FilledButton, 'Start'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(
        find.widgetWithText(FilledButton, 'Log Interval'),
        findsOneWidget,
        reason:
            'S-5008 the running interval offers the phone\'s own log control: its '
            'timer is counting on interval 2',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'S-5008 nothing escapes the frame',
      );

      // The wrist logs the interval it just finished.
      await phone.router.receive(
        observationsUp('s-w1', [
          _timed(
            'sx-run-1',
            slot: 'sl-run',
            exerciseId: 'ex-run',
            startedAt: _t1,
            endedAt: _t3,
          ),
        ], messageId: 'msg-timed-1'),
      );
      await tester.pump();

      expect(
        tester.takeException(),
        isNull,
        reason:
            'S-5008 D-5 the fill reaches the open screen with a ticker running on the '
            'interval it fills, and nothing escapes the frame',
      );
      expect(
        _entriesOf(phone, 'sl-run'),
        hasLength(2),
        reason:
            'S-5008 the wrist\'s interval FILLED interval 2: the effort still holds '
            'the phone\'s two intervals',
      );
      expect(
        find.text('Interval 2 of 2'),
        findsOneWidget,
        reason:
            'S-5008 the screen still counts two intervals, and the user stays on '
            'interval 2',
      );
      expect(
        find.text('Interval 2 of 3'),
        findsNothing,
        reason: 'S-5008 no third interval appeared beside the phone\'s own',
      );
      expect(
        find.text('LOGGED'),
        findsOneWidget,
        reason:
            'S-5008 interval 2 reads as logged once the wrist\'s entry fills it',
      );
      expect(
        find.descendant(
          of: find.byType(SetSegmentBar),
          matching: find.text('20:00'),
        ),
        findsOneWidget,
        reason:
            'S-5008 the bar caption for interval 2 is the wrist\'s 20:00, not the '
            'seconds the phone had counted',
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('count-up-digits')),
          matching: find.text('20:00'),
        ),
        findsOneWidget,
        reason: 'S-5008 and the open interval reads the same 20:00',
      );

      final instances = phone.state.getTimedInstancesForEffort('sl-run');
      expect(
        instances,
        hasLength(2),
        reason:
            'S-5008 two TimedInstances for the effort: the wrist\'s entry filled the '
            'second one instead of adding a third',
      );
      expect(
        instances[1].state,
        TimedState.finished,
        reason: 'S-5008 and the second instance is finished',
      );

      // Past the ticker's own period: the phone's timer for interval 2 must be
      // gone, not merely a no-op that fires forever.
      await tester.pump(const Duration(seconds: 3));
      expect(
        tester.takeException(),
        isNull,
        reason: 'S-5008 D-4 no exception from the resync or the ticker',
      );
      expect(
        find.widgetWithText(FilledButton, 'Log Interval'),
        findsNothing,
        reason:
            'S-5008 no running timer control is left for interval 2: the phone\'s '
            'ticker for that position was dropped',
      );
      expect(phone.failures, isEmpty);
    },
  );

  testWidgets('S-5009 the same for a round effort', (
    WidgetTester tester,
  ) async {
    final phone = await _phone();
    await phone.router.receive(
      _snapshot(
        exercises: [
          _slot('sl-bag', 'ex-round', 'Heavy Bag', _roundCapabilities),
        ],
      ),
    );

    // Two rounds the way the phone writes them; the first started and finished
    // through the state, which is what the screen's Start/Log controls do.
    await phone.state.addEntry('sl-bag');
    await phone.state.addEntry('sl-bag');
    await phone.state.startRound('sl-bag', 0);
    await phone.state.completeRound('sl-bag', 0);

    await _mount(tester, _screen(phone, initialFocusId: 'sl-bag'));

    expect(
      find.text('Round 2 of 2'),
      findsOneWidget,
      reason: 'S-5009 the screen opens on round 2 of the two the phone wrote',
    );
    expect(
      find.widgetWithText(FilledButton, 'Start'),
      findsOneWidget,
      reason: 'S-5009 and round 2 has not started',
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Start'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(
      find.widgetWithText(FilledButton, 'Log Round'),
      findsOneWidget,
      reason:
          'S-5009 round 2 is running and the phone offers its own log control',
    );

    await phone.router.receive(
      observationsUp('s-w1', [
        _round(
          'sx-bag-1',
          slot: 'sl-bag',
          exerciseId: 'ex-round',
          roundNumber: 2,
          startedAt: _t1,
          endedAt: _t3,
        ),
      ], messageId: 'msg-round-1'),
    );
    await tester.pump();

    expect(
      tester.takeException(),
      isNull,
      reason:
          'S-5009 D-5 the fill reaches the open screen with a ticker running on the '
          'round it fills, and nothing escapes the frame',
    );
    expect(
      _entriesOf(phone, 'sl-bag'),
      hasLength(2),
      reason: 'S-5009 the wrist\'s round FILLED round 2: still two rounds',
    );
    expect(
      find.text('Round 2 of 2'),
      findsOneWidget,
      reason: 'S-5009 the screen still counts two rounds and stays on round 2',
    );
    expect(
      find.text('Round 2 of 3'),
      findsNothing,
      reason: 'S-5009 no third round appeared beside the phone\'s own',
    );
    expect(
      find.text('LOGGED'),
      findsOneWidget,
      reason: 'S-5009 round 2 reads as logged once the wrist\'s entry fills it',
    );
    expect(
      find.descendant(
        of: find.byType(TimerRing),
        matching: find.text('COMPLETED'),
      ),
      findsOneWidget,
      reason: 'S-5009 the ring reads the round as completed',
    );
    expect(
      find.descendant(of: find.byType(TimerRing), matching: find.text('20:00')),
      findsOneWidget,
      reason: 'S-5009 with the wrist\'s 20:00 total',
    );
    expect(
      find.descendant(
        of: find.byType(SetSegmentBar),
        matching: find.text('20:00'),
      ),
      findsOneWidget,
      reason: 'S-5009 and the bar caption for round 2 shows the same total',
    );

    final rounds = phone.state.getRoundsForEffort('sl-bag');
    expect(
      rounds,
      hasLength(2),
      reason: 'S-5009 two RoundInstances for the effort',
    );
    expect(
      rounds[1].state,
      RoundState.finished,
      reason: 'S-5009 and the second round is finished',
    );

    await tester.pump(const Duration(seconds: 3));
    expect(
      tester.takeException(),
      isNull,
      reason: 'S-5009 D-4 no exception from the resync or the ticker',
    );
    expect(
      find.widgetWithText(FilledButton, 'Log Round'),
      findsNothing,
      reason:
          'S-5009 no running timer control is left for round 2: the phone\'s ticker '
          'for that position was dropped',
    );
    expect(phone.failures, isEmpty);
  });
}
