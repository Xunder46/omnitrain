// Plan 23b phase P1 (D-3505..D-3507) — the phone's OPEN session screen follows
// the watch.
//
// The defect: a wrist write reaches `WorkoutState` (`refreshEfforts`,
// `appendSessionSlots`) but the screen's `_exercises` is filled once by
// `_loadExercises()` and the state listener only answered an ended or discarded
// session, so a merged set, a merged timed entry or a slot the wrist added
// stayed invisible until the user left the session and opened it again.
//
// The phone is wired the way the shipping graph wires it — the inbox on an
// entry-staging transport, the mirror behind it, the adoption bridge behind
// that, and `WorkoutState` last (`test/watch_session_merge_test.dart`, S-9) —
// and the screens are the real ones, mounted as
// `test/session_screen_build_phase_notify_test.dart` mounts them. Mock-first:
// every future below is a microtask of the mock repository, so no real clock,
// Hive write or `Future.delayed` runs inside FakeAsync.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/block_types.dart';
import 'package:omnitrain/core/constants/capability.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/core/utils/unit_formatter.dart';
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
import 'package:omnitrain/widgets/session/inline_metric_editor.dart';

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
const String _t2 = '2026-10-05T10:20:00Z';
const String _t3 = '2026-10-05T10:30:00Z';

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
    restNotificationService:
        restNotifications ?? FakeRestNotificationService(),
    initialFocusId: initialFocusId,
  ),
);

/// The frame that mounts the screen, then the frame that runs its deferred
/// first load (D-150).
Future<void> _mount(WidgetTester tester, Widget screen) async {
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

const List<String> _setCapabilities = [
  ExerciseCapability.sets,
  ExerciseCapability.reps,
  ExerciseCapability.load,
];

const List<String> _timedCapabilities = [
  ExerciseCapability.time,
  ExerciseCapability.distance,
];

Map<String, Object?> _setSlot(String slot, String exerciseId, String name) =>
    _slot(slot, exerciseId, name, _setCapabilities);

/// One `session_snapshot` from the wrist, adopting `s-w1` onto the phone.
Map<String, Object?> _snapshot({
  String messageId = 'msg-snapshot',
  List<Map<String, Object?>>? exercises,
  int currentExerciseIndex = 0,
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
    // The validator refuses an index outside the ladder
    // (`message_validator.dart`, `currentExerciseIndex`), so every fixture
    // below names a slot it carries.
    'currentExerciseIndex': currentExerciseIndex,
    'exercises':
        exercises ??
        [
          _setSlot('sl-1', 'ex-1', 'Barbell Bench Press'),
          _setSlot('sl-2', 'ex-2', 'Barbell Back Squat'),
        ],
    'entries': <Object?>[],
    'timers': <String, Object?>{},
  },
};

/// A set the wrist logged, naming the slot it belongs to.
Map<String, Object?> _set(
  String entryId, {
  required String slot,
  required String exerciseId,
  required int reps,
  required num loadKg,
  required String loggedAt,
}) => {
  'entryId': entryId,
  'eventId': entryId,
  'kind': 'set',
  'loggedAt': loggedAt,
  'sessionExerciseId': slot,
  'exerciseId': exerciseId,
  'reps': reps,
  'loadKg': loadKg,
};

/// One rest the wrist observed, naming the entry it followed (the shape
/// `watch_session_merge_test.dart` S-320 sends).
Map<String, Object?> _rest(
  String entryId, {
  required String slot,
  required String exerciseId,
  required String afterEntryId,
  required String startedAt,
  required String endedAt,
}) => {
  'entryId': entryId,
  'eventId': entryId,
  'kind': 'rest',
  'loggedAt': endedAt,
  'sessionExerciseId': slot,
  'exerciseId': exerciseId,
  'startedAt': startedAt,
  'endedAt': endedAt,
  'afterEntryId': afterEntryId,
};

/// A timed entry the wrist logged (cardio), naming the slot it belongs to.
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

/// One slot the wrist added, as `appendSessionSlots` takes it.
SegmentEffort _addedSlot({
  required String id,
  required String segmentId,
  required String exerciseId,
  required int orderIndex,
}) {
  final atMs = _phoneNow.millisecondsSinceEpoch;
  return SegmentEffort(
    id: id,
    segmentId: segmentId,
    orderIndex: orderIndex,
    effortKind: BlockTypes.set,
    exerciseId: exerciseId,
    createdAtMs: atMs,
    updatedAtMs: atMs,
  );
}

// ─── Reading what happened ──────────────────────────────────────────────────

/// The entries of one displayed exercise, as the screen reads them.
List<Map<String, dynamic>> _entriesOf(_Phone phone, String effortId) {
  final exercise = phone.state
      .getExercisesWithEntries()
      .firstWhere((e) => e['id'] == effortId);
  return (exercise['entries'] as List).cast<Map<String, dynamic>>();
}

Future<void> _seed(MockWorkoutRepository repository) async {
  await seedExercise(
    repository,
    id: 'ex-1',
    name: 'Barbell Bench Press',
    capabilities: _setCapabilities,
  );
  await seedExercise(
    repository,
    id: 'ex-2',
    name: 'Barbell Back Squat',
    capabilities: _setCapabilities,
  );
  await seedExercise(
    repository,
    id: 'ex-3',
    name: 'Pull-Up',
    capabilities: _setCapabilities,
  );
  await seedExercise(
    repository,
    id: 'ex-run',
    name: 'Trail Run',
    capabilities: _timedCapabilities,
  );
}

void main() {
  test('S-3510 the watch revision moves for a watch write, never for the user\'s', () async {
    final phone = await _phone();
    await phone.router.receive(_snapshot());
    expect(
      phone.state.currentSession?.id,
      's-w1',
      reason: 'S-3510 the phone holds the session the wrist is running',
    );

    final atAdoption = phone.state.watchRefreshRevision;

    // The user's own writes: their source is the phone, so nothing about the
    // screen's data changed behind it.
    await phone.state.addEntry('sl-1');
    await phone.state.updateEntryValue('sl-1', 0, 'reps', 8);
    expect(
      phone.state.watchRefreshRevision,
      atAdoption,
      reason:
          'S-3510 D-3505 the phone\'s own writes do not move the revision — and so the screen '
          'cannot loop on its own reload',
    );

    await phone.state.refreshEfforts(['sl-1']);
    expect(
      phone.state.watchRefreshRevision,
      atAdoption + 1,
      reason: 'S-3510 a watch-merged effort moves it, once per refresh',
    );

    await phone.state.appendSessionSlots([
      _addedSlot(
        id: 'sl-3',
        segmentId: phone.state.segments.first.id,
        exerciseId: 'ex-3',
        orderIndex: 2,
      ),
    ], sessionId: 's-w1');
    expect(
      phone.state.watchRefreshRevision,
      atAdoption + 2,
      reason: 'S-3510 a slot the wrist added moves it',
    );

    await phone.state.appendSessionSlots([
      _addedSlot(
        id: 'sl-9',
        segmentId: phone.state.segments.first.id,
        exerciseId: 'ex-3',
        orderIndex: 3,
      ),
    ], sessionId: 's-other');
    expect(
      phone.state.watchRefreshRevision,
      atAdoption + 2,
      reason:
          'S-3510 a slot named for another session is not this session\'s news',
    );
    expect(phone.failures, isEmpty);
  });

  testWidgets('S-3511 a wrist set appears in the open list without navigation', (
    WidgetTester tester,
  ) async {
    final phone = await _phone();
    await phone.router.receive(_snapshot());
    await _mount(tester, _screen(phone));

    expect(
      find.text('0 sets'),
      findsNWidgets(2),
      reason: 'S-3511 the screen\'s first snapshot: two exercises, no sets',
    );

    await phone.router.receive(
      observationsUp('s-w1', [
        _set(
          'sx-1',
          slot: 'sl-1',
          exerciseId: 'ex-1',
          reps: 8,
          loadKg: 40,
          loggedAt: _t1,
        ),
      ], messageId: 'msg-set-1'),
    );
    await tester.pump();

    expect(
      _entriesOf(phone, 'sl-1'),
      hasLength(1),
      reason: 'S-3511 the wrist\'s set is one entry of the phone\'s own effort',
    );
    expect(
      find.text('1 set'),
      findsOneWidget,
      reason:
          'S-3511 the open list shows the set the wrist logged — the user never left the screen',
    );
    expect(
      find.text('0 sets'),
      findsOneWidget,
      reason: 'S-3511 the other exercise still shows no sets',
    );
    expect(tester.takeException(), isNull, reason: 'S-3511 nothing escapes the frame');
    expect(phone.failures, isEmpty);
  });

  testWidgets('S-3511 the open entry shows the wrist\'s reps and load', (
    WidgetTester tester,
  ) async {
    final phone = await _phone();
    await phone.router.receive(_snapshot());
    await _mount(tester, _screen(phone, initialFocusId: 'sl-1'));

    expect(
      find.descendant(
        of: find.byType(InlineMetricEditor),
        matching: find.text('0'),
      ),
      findsOneWidget,
      reason:
          'S-3511 the open entry starts with no reps — the effort holds no entries, so the '
          'detail falls back to a zero entry',
    );
    await phone.router.receive(
      observationsUp('s-w1', [
        _set(
          'sx-1',
          slot: 'sl-1',
          exerciseId: 'ex-1',
          reps: 8,
          loadKg: 40,
          loggedAt: _t1,
        ),
      ], messageId: 'msg-set-1'),
    );
    await tester.pump();

    final weight = UnitFormatter.convertWeight(40.0, phone.settings);
    expect(
      find.descendant(
        of: find.byType(InlineMetricEditor),
        matching: find.text('8'),
      ),
      findsOneWidget,
      reason: 'S-3511 the wrist\'s reps are on the entry the user has open',
    );
    expect(
      find.descendant(
        of: find.byType(InlineMetricEditor),
        matching: find.text(weight.toStringAsFixed(1)),
      ),
      findsOneWidget,
      reason: 'S-3511 the wrist\'s load is too (${weight.toStringAsFixed(1)})',
    );
    expect(
      find.text('Set 1 of 1'),
      findsOneWidget,
      reason: 'S-3511 the entry the user is on is still set 1 of the grown list',
    );
    expect(tester.takeException(), isNull, reason: 'S-3511 nothing escapes the frame');
    expect(phone.failures, isEmpty);
  });

  testWidgets('S-3512 a wrist timed entry appears on a timed effort', (
    WidgetTester tester,
  ) async {
    final phone = await _phone();
    await phone.router.receive(
      _snapshot(
        exercises: [_slot('sl-run', 'ex-run', 'Trail Run', _timedCapabilities)],
      ),
    );
    await _mount(tester, _screen(phone));

    expect(
      find.text('Trail Run'),
      findsOneWidget,
      reason: 'S-3512 the timed effort of the held session is on screen',
    );
    expect(
      find.text('00:00 total'),
      findsOneWidget,
      reason: 'S-3512 and it has no time in it yet',
    );

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
      _entriesOf(phone, 'sl-run'),
      hasLength(1),
      reason: 'S-3512 the wrist\'s timed entry is one entry of the effort',
    );
    expect(
      find.text('20:00 total'),
      findsOneWidget,
      reason:
          'S-3512 the open list shows the wrist\'s timed entry — a cardio interval the phone '
          'never logged',
    );
    expect(tester.takeException(), isNull, reason: 'S-3512 nothing escapes the frame');
    expect(phone.failures, isEmpty);
  });

  testWidgets('S-3513 a slot the wrist added shows as a new row at the end', (
    WidgetTester tester,
  ) async {
    final phone = await _phone();
    await phone.router.receive(_snapshot());
    await _mount(tester, _screen(phone));

    expect(
      find.byType(ListTile),
      findsNWidgets(2),
      reason: 'S-3513 the screen\'s first snapshot: two exercise rows',
    );
    expect(find.text('Pull-Up'), findsNothing, reason: 'S-3513 not yet on the phone');

    await phone.router.receive(
      _snapshot(
        messageId: 'msg-snapshot-2',
        exercises: [
          _setSlot('sl-1', 'ex-1', 'Barbell Bench Press'),
          _setSlot('sl-2', 'ex-2', 'Barbell Back Squat'),
          _setSlot('sl-3', 'ex-3', 'Pull-Up'),
        ],
      ),
    );
    await tester.pump();

    expect(
      phone.state.getExercisesWithEntries().map((e) => e['id']).toList(),
      ['sl-1', 'sl-2', 'sl-3'],
      reason: 'S-3513 the wrist added a third slot to the session the phone holds',
    );
    expect(
      find.byType(ListTile),
      findsNWidgets(3),
      reason: 'S-3513 the whole exercise the wrist added is a row on the open screen',
    );
    expect(find.text('Pull-Up'), findsOneWidget, reason: 'S-3513 named as the phone knows it');
    expect(
      tester.getCenter(find.text('Pull-Up')).dy,
      greaterThan(tester.getCenter(find.text('Barbell Back Squat')).dy),
      reason: 'S-3513 at the end, after the two the phone already had',
    );
    expect(tester.takeException(), isNull, reason: 'S-3513 nothing escapes the frame');
    expect(phone.failures, isEmpty);
  });

  testWidgets('S-3514 a wrist merge leaves the open entry and its rest alone', (
    WidgetTester tester,
  ) async {
    final phone = await _phone();
    await phone.router.receive(_snapshot());

    // The user's own three sets on sl-1, with a rest running after the first.
    await phone.state.addEntry('sl-1');
    await phone.state.addEntry('sl-1');
    await phone.state.addEntry('sl-1');
    await phone.state.updateEntryValue('sl-1', 0, 'reps', 8);
    await phone.state.recordRestStart('sl-1', 1);

    await _mount(tester, _screen(phone, initialFocusId: 'sl-1'));

    expect(
      find.text('Set 2 of 3'),
      findsOneWidget,
      reason: 'S-3514 the user is on set 2 of the three sets they logged',
    );
    expect(
      find.byKey(const Key('rest-overlay-chip')),
      findsOneWidget,
      reason: 'S-3514 their rest after set 1 is counting',
    );

    await phone.router.receive(
      observationsUp('s-w1', [
        _set(
          'sx-9',
          slot: 'sl-1',
          exerciseId: 'ex-1',
          reps: 10,
          loadKg: 45,
          loggedAt: _t2,
        ),
      ], messageId: 'msg-set-9'),
    );
    await tester.pump();

    expect(
      _entriesOf(phone, 'sl-1'),
      hasLength(4),
      reason: 'S-3514 the wrist\'s set landed as a fourth entry of the effort',
    );
    expect(
      find.text('Set 2 of 4'),
      findsOneWidget,
      reason:
          'S-3514 the list was re-read (the new entry is in the label) and the user is still on '
          'set 2, not moved to the first',
    );
    expect(
      find.byKey(const Key('rest-overlay-chip')),
      findsOneWidget,
      reason: 'S-3514 the rest the user is in is still counting',
    );
    expect(
      find.text('Set 2 of 3'),
      findsNothing,
      reason:
          'S-3514 the old count is gone: the label was rebuilt from the list the resync read',
    );
    expect(tester.takeException(), isNull, reason: 'S-3514 nothing escapes the frame');
    expect(phone.failures, isEmpty);
  });

  testWidgets('S-3515 the set the wrist logged is offered no second log', (
    WidgetTester tester,
  ) async {
    final phone = await _phone();
    await phone.router.receive(_snapshot());

    // One entry the user has never logged: a row of sl-1 with no rest after it,
    // so nothing marks it logged and the phone offers its Log Set control.
    await phone.state.addEntry('sl-1');

    final restNotifications = FakeRestNotificationService();
    await _mount(
      tester,
      _screen(
        phone,
        initialFocusId: 'sl-1',
        restNotifications: restNotifications,
      ),
    );

    expect(
      find.widgetWithText(FilledButton, 'Log Set'),
      findsOneWidget,
      reason:
          'S-3515 the user is on the one set of the effort, and the phone has logged '
          'nothing, so the control it offers is the Log Set button',
    );
    // The wrist's set for sl-1 and the rest it started after it, through the
    // production path every other scenario here uses. The set lands as an extra
    // entry of the effort, after the one the user added.
    await phone.router.receive(
      observationsUp('s-w1', [
        _set(
          'sx-9',
          slot: 'sl-1',
          exerciseId: 'ex-1',
          reps: 10,
          loadKg: 45,
          loggedAt: _t2,
        ),
        _rest(
          'rest-w9',
          slot: 'sl-1',
          exerciseId: 'ex-1',
          afterEntryId: 'sx-9',
          startedAt: _t2,
          endedAt: _t3,
        ),
      ], messageId: 'msg-set-9'),
    );
    await tester.pump();

    expect(
      _entriesOf(phone, 'sl-1'),
      hasLength(2),
      reason:
          'S-3515 the set the wrist logged is an entry of the effort, beside the one the '
          'user added',
    );

    final pingsBeforeTheNavigation = restNotifications.scheduled.length;

    // The user walks with the screen's own next-set control onto the set the
    // wrist logged.
    await tester.tap(find.byTooltip('Next'));
    await tester.pump();

    final entries = _entriesOf(phone, 'sl-1');
    final wristEntry = entries[1];
    expect(
      find.text('Set 2 of 2'),
      findsOneWidget,
      reason:
          'S-3515 the user is on the set the wrist logged: the label counts both entries of '
          'the effort, the one the user added and the one the wrist sent (entries $entries)',
    );
    expect(
      wristEntry['reps'],
      10,
      reason: 'S-3515 the set the wrist logged still carries its own reps',
    );
    expect(
      wristEntry['weight'],
      45.0,
      reason: 'S-3515 and its own load: the phone leaves the wrist\'s values alone',
    );
    expect(
      find.text('LOGGED'),
      findsOneWidget,
      reason:
          'S-3515 the phone reads that set as logged — the rest the wrist sent after it is '
          'what the set\'s status is read from, and the same rest is what the resync keys '
          'its logged sets on',
    );
    expect(
      find.widgetWithText(FilledButton, 'Log Set'),
      findsNothing,
      reason:
          'S-3515 and it offers no control that logs that set a second time: the phone '
          'starts no rest for a set the wrist logged, and schedules no rest pings for one',
    );
    expect(
      phone.state.getEntryRests('sl-1'),
      hasLength(1),
      reason:
          'S-3515 the effort holds the one rest the wrist\'s own set came with and no '
          'other, so the phone opened no rest of its own for the set the user is on',
    );
    expect(
      phone.state.getEntryRests('sl-1').single.entryIndex,
      2,
      reason:
          'S-3515 and that rest is the wrist\'s: it follows the entry the wrist sent',
    );
    expect(
      restNotifications.scheduled.length,
      pingsBeforeTheNavigation,
      reason:
          'S-3515 no rest pings were scheduled either: nothing about the set the wrist '
          'logged restarted a rest on the phone',
    );

    // Control. An effort whose set the wrist sent without a rest behind it
    // leaves the resync nothing to read a status from: the control is there and
    // pressing it does log the set and does start its rest. So the assertions
    // above answer the wrist's rest, not the harness's ability to press the
    // control.
    await phone.router.receive(
      observationsUp('s-w1', [
        _set(
          'sx-2',
          slot: 'sl-2',
          exerciseId: 'ex-2',
          reps: 8,
          loadKg: 40,
          loggedAt: _t1,
        ),
      ], messageId: 'msg-set-2'),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Next'));
    await tester.pump();

    expect(
      find.text('Set 1 of 1'),
      findsOneWidget,
      reason: 'S-3515 the next effort holds the one set the wrist sent for it',
    );

    final pingsBeforeTheControlTap = restNotifications.scheduled.length;
    await tester.tap(find.widgetWithText(FilledButton, 'Log Set'));
    for (int i = 0; i < 4; i++) {
      await tester.pump();
    }

    expect(
      phone.state
          .getEntryRests('sl-2')
          .where((rest) => rest.entryIndex == 1 && rest.restEndMs == null),
      hasLength(1),
      reason:
          'S-3515 control: with no rest of the wrist\'s behind it the set is the phone\'s to '
          'log, and logging it opens the rest for entry 1 — which is what the phone must not '
          'do for the set the wrist logged',
    );
    expect(
      restNotifications.scheduled.length,
      pingsBeforeTheControlTap + 1,
      reason:
          'S-3515 control: and the log schedules that rest\'s pings, so the count above '
          'measures the wrist\'s rest and not a tap that never landed',
    );
    expect(tester.takeException(), isNull, reason: 'S-3515 nothing escapes the frame');
    expect(phone.failures, isEmpty);
  });
}
