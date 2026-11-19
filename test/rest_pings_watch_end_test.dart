// Plan 51g phase P1 — the phone stops pinging a rest the watch ended
// (S-7521..S-7524, D-1).
//
// The defect: pings are scheduled only when the app goes to the background
// (`didChangeAppLifecycleState`) or on a settings change, and the screen's
// state listener answered only an ended or discarded session. A rest the wrist
// ends reaches `WorkoutState.refreshEfforts` — which reloads the effort's rests
// and bumps `watchRefreshRevision` — so the rest chip stopped but the OS-side
// pings of the finished rest stayed scheduled and kept buzzing. The production
// line (`_onWorkoutStateChanged` → `_scheduleActiveRestNotifications()`, D-1)
// cancels when no rest is open and reschedules from the open rest's own start
// otherwise.
//
// The harness is the shipping graph of `test/watch_live_refresh_screen_test.dart`
// (S-3511): the inbox on an entry-staging transport, the mirror behind it, the
// adoption bridge behind that, and `WorkoutState` last; the screens are the real
// ones. Mock-first: every future below is a microtask of the mock repository, so
// no real clock, Hive write or `Future.delayed` runs inside FakeAsync.

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

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_rest_notification_service.dart';
import 'helpers/fake_timer_alert_service.dart';
import 'helpers/sync_protocol_harness.dart';
import 'helpers/watch_capture_import_harness.dart'
    show CaptureTransport, seedExercise;

final SyncProtocolValidator _validator = loadProtocolValidator();

/// The phone's clock when nothing in the scenario moves it.
final DateTime _phoneNow = DateTime.utc(2026, 10, 5, 11);

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
Widget _screen(_Phone phone, {FakeRestNotificationService? restNotifications}) =>
    MaterialApp(
      home: WorkoutSessionScreen(
        workoutState: phone.state,
        routineState: phone.routine,
        sessionSummaryService: phone.summary,
        settingsState: phone.settings,
        timerAlertService: FakeTimerAlertService(),
        restNotificationService:
            restNotifications ?? FakeRestNotificationService(),
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

Map<String, Object?> _setSlot(String slot, String exerciseId, String name) =>
    _slot(slot, exerciseId, name, _setCapabilities);

/// One `session_snapshot` from the wrist, adopting `s-w1` onto the phone.
Map<String, Object?> _snapshot() => {
  'protocolVersion': SyncProtocolValidator.protocolVersion,
  'messageId': 'msg-snapshot',
  'sessionId': 's-w1',
  'type': 'session_snapshot',
  'origin': 'watch',
  'sentAt': '2026-10-05T10:00:00Z',
  'payload': {
    'sessionId': 's-w1',
    'revision': 3,
    'status': WatchSessionStatus.active,
    'currentExerciseIndex': 0,
    'exercises': [
      _setSlot('sl-1', 'ex-1', 'Barbell Bench Press'),
      _setSlot('sl-2', 'ex-2', 'Barbell Back Squat'),
    ],
    'entries': <Object?>[],
    'timers': <String, Object?>{},
  },
};

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
}

// ─── The wrist's writes on the rest rows ────────────────────────────────────

/// The open rest row of `sl-1` as the repository holds it.
Future<EntryRest> _openRest(_Phone phone) async {
  final rests = await phone.repository.getEntryRests('sl-1');
  return rests.singleWhere((r) => r.restEndMs == null);
}

/// The wrist's Next: the repository row of the open rest gets its end.
Future<void> _wristEndsRest(_Phone phone, EntryRest open) =>
    phone.repository.updateEntryRest(
      open.copyWith(
        restEndMs: open.restStartMs + 30000,
        updatedAtMs: open.restStartMs + 30000,
      ),
    );

/// The phone with a rest open, the screen mounted on the mock double, and the
/// app in the background: the starting state of S-7521..S-7523.
Future<void> _openRestAndPause(
  WidgetTester tester,
  _Phone phone,
  FakeRestNotificationService fake,
) async {
  await phone.state.recordRestStart('sl-1', 1);
  await tester.pump();
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  await tester.pump();
}

/// Leaves the binding as the next scenario expects to find it.
Future<void> _resume(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pump();
}

void main() {
  testWidgets('S-7521 a rest the wrist ends cancels the pings and schedules '
      'nothing new', (WidgetTester tester) async {
    final phone = await _phone();
    await phone.router.receive(_snapshot());
    final fake = FakeRestNotificationService();
    await _mount(tester, _screen(phone, restNotifications: fake));

    await _openRestAndPause(tester, phone, fake);
    expect(
      fake.scheduled,
      hasLength(1),
      reason: 'S-7521 the open rest is scheduled when the app goes to the background',
    );

    // The wrist's side: the repository row is closed, then the phone resyncs.
    await _wristEndsRest(phone, await _openRest(phone));
    final before = fake.cancelCallCount;
    await phone.state.refreshEfforts(['sl-1']);
    await tester.pump();

    expect(
      fake.cancelCallCount,
      before + 1,
      reason:
          'S-7521 D-1 the rest the watch ended cancels the pings already scheduled for it',
    );
    expect(
      fake.scheduled,
      hasLength(1),
      reason: 'S-7521 and nothing is scheduled for a rest that is no longer open',
    );

    expect(tester.takeException(), isNull, reason: 'S-7521 nothing escapes the frame');
    expect(phone.failures, isEmpty);
    await _resume(tester);
  });

  testWidgets('S-7522 a rest the wrist replaced schedules from the NEW rest\'s '
      'start', (WidgetTester tester) async {
    final phone = await _phone();
    await phone.router.receive(_snapshot());
    final fake = FakeRestNotificationService();
    await _mount(tester, _screen(phone, restNotifications: fake));

    await _openRestAndPause(tester, phone, fake);
    final firstStart = fake.scheduled.single.restStartMs;

    // The wrist's set: the old rest ends and the next one opens 90 s later.
    await _wristEndsRest(phone, await _openRest(phone));
    final secondStart = firstStart + 90000;
    await phone.repository.createEntryRest(
      EntryRest(
        id: 'rest-sl-1-2',
        effortId: 'sl-1',
        entryIndex: 2,
        restStartMs: secondStart,
        restEndMs: null,
        createdAtMs: secondStart,
        updatedAtMs: secondStart,
      ),
    );
    await phone.state.refreshEfforts(['sl-1']);
    await tester.pump();

    expect(
      fake.scheduled.last.restStartMs,
      secondStart,
      reason:
          'S-7522 D-1 the pings follow the rest the wrist opened, not the one it ended',
    );

    expect(tester.takeException(), isNull, reason: 'S-7522 nothing escapes the frame');
    expect(phone.failures, isEmpty);
    await _resume(tester);
  });

  testWidgets('S-7523 a resync with the same rest open schedules again from '
      'that rest\'s own start', (WidgetTester tester) async {
    final phone = await _phone();
    await phone.router.receive(_snapshot());
    final fake = FakeRestNotificationService();
    await _mount(tester, _screen(phone, restNotifications: fake));

    await _openRestAndPause(tester, phone, fake);
    expect(fake.scheduled, hasLength(1), reason: 'S-7523 the background schedule');

    await phone.state.refreshEfforts(['sl-1']);
    await tester.pump();

    expect(
      fake.scheduled,
      hasLength(2),
      reason: 'S-7523 a watch resync with a rest still open schedules once more',
    );
    expect(
      fake.scheduled.last.restStartMs,
      fake.scheduled.first.restStartMs,
      reason: 'S-7523 from the same rest\'s own start — the rest did not move',
    );

    expect(tester.takeException(), isNull, reason: 'S-7523 nothing escapes the frame');
    expect(phone.failures, isEmpty);
    await _resume(tester);
  });

  testWidgets('S-7524 a resync with no rest ever open cancels and never '
      'schedules', (WidgetTester tester) async {
    final phone = await _phone();
    await phone.router.receive(_snapshot());
    final fake = FakeRestNotificationService();
    await _mount(tester, _screen(phone, restNotifications: fake));

    await phone.state.refreshEfforts(['sl-1']);
    await tester.pump();

    expect(
      fake.cancelCallCount,
      greaterThanOrEqualTo(1),
      reason: 'S-7524 D-1 the resync cancels — there is no rest to ping for',
    );
    expect(
      fake.scheduled,
      isEmpty,
      reason: 'S-7524 and it never schedules without an open rest',
    );

    expect(tester.takeException(), isNull, reason: 'S-7524 nothing escapes the frame');
    expect(phone.failures, isEmpty);
  });
}
