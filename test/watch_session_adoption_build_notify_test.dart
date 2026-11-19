// Problem B: `setState() or markNeedsBuild() called during build`.
//
// The owner saw that line in the phone's console while the phone adopted and
// considered wrist snapshots during a Sync, and it is the abbreviated repeat of
// a full report nobody has yet. This file is the reproduction attempt the brief
// asks for — a reproduction attempt, not a fix: the real `HomeScreen` (which
// observes `WorkoutState` through a `ListenableBuilder`), the real watch graph
// `createWatchSync` builds, and one wrist `session_snapshot` handed to the radio
// on the schedules a build could catch — while the screen is mounted, from
// inside a build (`initState` runs during the build phase), and from a
// post-frame callback — once for a session that is adopted and once for a skip.
//
// It does NOT reproduce. See the evidence file beside the plan
// (`2026-10-05-15a-watch-session-sync-pr1-plan.evidence.md`, "Fix round 2" →
// "Problem B") for what was tried and the log the owner must send. The reason is
// structural, and
// it is why no production change accompanies this file: every entry into the
// watch path yields before it notifies. `WatchIncomingRouter.receive` awaits the
// inbox first, the mirror second, and only then asks the adoption bridge, which
// awaits the repository and `loadHistoricalSession` — so the `WorkoutState`
// notification always lands in a microtask after the frame that handed the frame
// over, never inside that frame's build. The mirror is a `ChangeNotifier` too,
// but nothing in `lib/features/` or `lib/widgets/` listens to it.
//
// What these tests still prove, and why they are not vacuous: on every schedule
// the delivery runs to completion while the real screen is mounted, no framework
// exception is raised, and each case asserts the effect it is supposed to have —
// so a test cannot pass by never delivering anything. They cannot prove the
// error impossible: a schedule that puts a notification inside a build would
// have to exist in the watch path first.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/platform/watch_delivery.dart';
import 'package:omnitrain/core/platform/watch_transport.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/session_summary_screen.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/watch/watch_sync_wiring.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';
import 'helpers/watch_capture_import_harness.dart'
    show importedEfforts, importedRows, importedSegment, seedExercise;
import 'home_short_viewport_test.dart' show buildHomeScreen;

final DateTime _now = DateTime.utc(2026, 10, 6, 9);

/// One ladder slot as the wrist sends it.
Map<String, Object?> _slot(String sessionExerciseId, String exerciseId) => {
  'sessionExerciseId': sessionExerciseId,
  'exerciseId': exerciseId,
  'name': exerciseId,
  'capabilities': const ['sets', 'reps', 'load'],
};

/// One `session_snapshot` from the wrist.
Map<String, Object?> _snapshot({
  required String sessionId,
  required int revision,
  List<Map<String, Object?>> exercises = const [],
  String messageId = 'msg-snapshot',
}) => {
  'protocolVersion': SyncProtocolValidator.protocolVersion,
  'messageId': messageId,
  'sessionId': sessionId,
  'type': 'session_snapshot',
  'origin': 'watch',
  'sentAt': '2026-10-06T09:00:00Z',
  'payload': {
    'sessionId': sessionId,
    'revision': revision,
    'status': WatchSessionStatus.active,
    'currentExerciseIndex': 0,
    'exercises': [...exercises],
    'entries': <Object?>[],
    'timers': <String, Object?>{},
  },
};

/// The phone's radio: hands the phone one frame from the wrist the way the
/// platform channel does.
class _PhoneRadio implements WatchTransport {
  WatchInboundHandler? _handler;

  @override
  bool get isPhoneReachable => true;

  @override
  void onIncoming(WatchInboundHandler handler) => _handler = handler;

  @override
  Future<void> refreshReachability() async {}

  @override
  Future<void> requestRoutines({DateTime? since}) async =>
      send(WatchTransportRequest.routinesFrame(since: since));

  @override
  Future<void> requestSnapshot() async =>
      send(WatchTransportRequest.snapshotFrame());

  @override
  Future<WatchDelivery> send(Map<String, Object?> envelope) async =>
      WatchDelivery.delivered;

  /// One frame from the wrist, the way the radio delivers one.
  Future<void> fromWrist(Map<String, Object?> frame) async {
    final handler = _handler;
    if (handler == null) {
      throw StateError('the phone graph never bound its inbound handler');
    }
    await handler(frame);
  }
}

/// Delivers a frame from inside a build: `initState` runs while the framework is
/// building the tree, which is the moment the owner's report names.
class _DeliverDuringBuild extends StatefulWidget {
  const _DeliverDuringBuild({required this.deliver});

  final Future<void> Function() deliver;

  @override
  State<_DeliverDuringBuild> createState() => _DeliverDuringBuildState();
}

class _DeliverDuringBuildState extends State<_DeliverDuringBuild> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.deliver());
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  late MockWorkoutRepository repository;
  late _PhoneRadio radio;
  late WorkoutState phoneState;
  late Widget screen;
  late List<Object> failures;
  late List<({String held, String offered})> skipped;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    failures = [];
    skipped = [];
    repository = MockWorkoutRepository();
    await repository.initialize();
    await seedExercise(
      repository,
      id: 'ex-bench',
      name: 'Bench Press',
      capabilities: const ['sets', 'reps', 'load'],
    );

    final built = await buildHomeScreen(repository);
    screen = built.screen;
    phoneState = built.workoutState;

    final settings = SettingsState(repository, fakePreferencesService());
    await settings.initialize();

    radio = _PhoneRadio();
    final graph = (await createWatchSync(
      repository: repository,
      nutritionState: NutritionState(repository),
      foodLibraryState: FoodLibraryState(repository),
      settingsState: settings,
      transport: radio,
      clock: () => _now,
      onFailure: (error, stack) => failures.add(error),
      onSkipped: (held, offered) => skipped.add((held: held, offered: offered)),
    ))!;
    graph.adoption.bindWorkoutState(phoneState);
  });

  /// Mounts the real home screen, with [during] mounted beside it when a case
  /// delivers a frame from inside a build.
  ///
  /// Bounded pumps, never `pumpAndSettle`: a session the phone is running puts
  /// the live panel on the screen, and its elapsed-time ticker schedules a frame
  /// every second, so the tree never settles. The frames these tests need are
  /// the mount frame, the post-frame work it queues, and the rebuild the
  /// delivery causes.
  Future<void> pumpHome(WidgetTester tester, {Widget? during}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: during == null
            ? screen
            : Column(children: [Expanded(child: screen), during]),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  /// Puts one exercise in the phone's own session, so it is a session with work
  /// logged in it — the one D-10 protects.
  Future<void> startPhoneSession() async {
    await phoneState.createNewSession(modality: 'resistance_lifting');
    await phoneState.addExerciseToSession(
      (await repository.getExerciseById('ex-bench'))!,
    );
  }

  testWidgets('a snapshot delivered while the home screen is mounted is '
      'adopted without a framework exception', (tester) async {
    await pumpHome(tester);

    await radio.fromWrist(
      _snapshot(
        sessionId: 's-w1',
        revision: 1,
        exercises: [_slot('sl-1', 'ex-bench')],
      ),
    );
    await tester.pump();

    expect(
      tester.takeException(),
      isNull,
      reason:
          'the watch path notifies `WorkoutState` after it has yielded, so the '
          'home screen never sees a notify during a build',
    );
    expect(
      phoneState.currentSession?.id,
      's-w1',
      reason: 'the delivery reached the screen\'s own state (S-1, D-2)',
    );
  });

  testWidgets('a skip delivered while the home screen is mounted reports '
      'through onSkipped and throws nothing', (tester) async {
    await startPhoneSession();
    final heldId = phoneState.currentSession!.id;
    await pumpHome(tester);

    await radio.fromWrist(
      _snapshot(
        sessionId: 's-w2',
        revision: 1,
        exercises: [_slot('sl-1', 'ex-bench')],
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      phoneState.currentSession?.id,
      heldId,
      reason: 'D-10 the phone keeps the session it is already running',
    );
    expect(
      skipped,
      [(held: heldId, offered: 's-w2')],
      reason: 'the skip reached the app\'s own observation of it',
    );
    expect(
      failures,
      isEmpty,
      reason: 'refusing is the rule working: the skip is not a failure',
    );
  });

  testWidgets('a snapshot delivered from inside a build is adopted without a '
      'framework exception', (tester) async {
    await pumpHome(
      tester,
      during: _DeliverDuringBuild(
        deliver: () => radio.fromWrist(
          _snapshot(
            sessionId: 's-w1',
            revision: 1,
            exercises: [_slot('sl-1', 'ex-bench')],
          ),
        ),
      ),
    );

    expect(
      tester.takeException(),
      isNull,
      reason:
          'handed over during the build phase, the frame still notifies after '
          'the frame has been built',
    );
    expect(phoneState.currentSession?.id, 's-w1');
  });

  testWidgets('a skip delivered from a post-frame callback throws nothing',
      (tester) async {
    await startPhoneSession();
    final heldId = phoneState.currentSession!.id;
    await pumpHome(tester);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        radio.fromWrist(
          _snapshot(
            sessionId: 's-w2',
            revision: 1,
            exercises: [_slot('sl-1', 'ex-bench')],
          ),
        ),
      );
    });
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(phoneState.currentSession?.id, heldId);
    expect(skipped, [(held: heldId, offered: 's-w2')]);
  });

  /// The ladder the wrist sends once it has added `C` to the S-1 session.
  Map<String, Object?> withC(String messageId) => _snapshot(
    sessionId: 's-w1',
    revision: 4,
    exercises: [
      _slot('sl-1', 'ex-bench'),
      _slot('sl-2', 'ex-squat'),
      _slot('sl-3', 'ex-deadlift'),
    ],
    messageId: messageId,
  );

  /// The two exercises the S-1 ladder's second and third slots name.
  Future<void> seedLadderExercises() async {
    await seedExercise(
      repository,
      id: 'ex-squat',
      name: 'Back Squat',
      capabilities: const ['sets', 'reps', 'load'],
    );
    await seedExercise(
      repository,
      id: 'ex-deadlift',
      name: 'Deadlift',
      capabilities: const ['sets', 'reps', 'load'],
    );
  }

  /// Adopts the wrist's `[A, B]` session, so the phone holds it.
  Future<SessionSegment> adoptHeldSession() async {
    await seedLadderExercises();
    await radio.fromWrist(
      _snapshot(
        sessionId: 's-w1',
        revision: 3,
        exercises: [_slot('sl-1', 'ex-bench'), _slot('sl-2', 'ex-squat')],
        messageId: 'msg-held',
      ),
    );
    return importedSegment(repository, 's-w1');
  }

  testWidgets('S-103 the same snapshot twice, and a stale copy after a removal',
      (tester) async {
    final segment = await adoptHeldSession();

    // 1: the add. The phone's ladder grows by C.
    var notifications = 0;
    phoneState.addListener(() => notifications += 1);
    await radio.fromWrist(withC('msg-s103-1'));
    expect(
      [
        for (final effort in phoneState.getEffortsForSegment(segment.id))
          effort.id,
      ],
      ['sl-1', 'sl-2', 'sl-3'],
      reason: 'S-103 the slot the wrist added is appended',
    );
    expect(notifications, 1, reason: 'S-103 the add is one change');

    // 2: the same ladder again. Every slot is one the phone has taken.
    final afterFirstAdd = await importedRows(repository, 's-w1');
    await radio.fromWrist(withC('msg-s103-2'));
    expect(
      [
        for (final effort in phoneState.getEffortsForSegment(segment.id))
          effort.id,
      ],
      ['sl-1', 'sl-2', 'sl-3'],
      reason: 'S-103 a redelivery adds nothing',
    );
    expect(
      await importedRows(repository, 's-w1'),
      afterFirstAdd,
      reason: 'S-103 and writes nothing',
    );
    expect(notifications, 1, reason: 'S-103 and notifies nothing');

    // 3: the phone removes C through its own session API.
    await phoneState.removeExerciseFromSession('sl-3');
    expect(
      [
        for (final effort in phoneState.getEffortsForSegment(segment.id))
          effort.id,
      ],
      ['sl-1', 'sl-2'],
      reason: 'S-103 the removal is the phone\'s own decision',
    );
    final afterRemoval = notifications;

    // 4: a stale copy of the ladder C was in. A reconcile reading only the
    // phone's current ladder would append it back (D-93).
    await radio.fromWrist(withC('msg-s103-3'));
    expect(
      [
        for (final effort in phoneState.getEffortsForSegment(segment.id))
          effort.id,
      ],
      ['sl-1', 'sl-2'],
      reason:
          'S-103 a slot the phone has seen and removed is not appended back by '
          'a snapshot older than the removal',
    );
    expect(
      [
        for (final effort in await importedEfforts(repository, 's-w1'))
          effort.id,
      ],
      ['sl-1', 'sl-2'],
      reason: 'S-103 no second effort with C\'s id exists',
    );
    expect(
      notifications,
      afterRemoval,
      reason:
          'S-103 and the stale frame notifies nothing: the removal was the last '
          'change the phone made',
    );
    expect(failures, isEmpty);
  });

  testWidgets('S-111 an append while the phone is on another screen',
      (tester) async {
    final segment = await adoptHeldSession();
    expect(
      phoneState.getEffortsForSegment(segment.id),
      hasLength(2),
      reason: 'S-111 the fixture starts at the two-slot ladder',
    );

    // The phone leaves the session screen for the session's summary — any
    // screen that is not the live session screen does for this scenario.
    final summarySettings = SettingsState(repository, fakePreferencesService());
    await summarySettings.setShowFeelingSurvey(false);
    await tester.pumpWidget(
      MaterialApp(
        home: SessionSummaryScreen(
          workoutState: phoneState,
          routineState: RoutineState(repository),
          sessionSummaryService: SessionSummaryService(repository),
          settingsState: summarySettings,
          timerAlertService: FakeTimerAlertService(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    var notifications = 0;
    phoneState.addListener(() => notifications += 1);

    await radio.fromWrist(withC('msg-s111-add'));
    await tester.pump();
    await tester.pump();

    expect(
      [
        for (final effort in phoneState.getEffortsForSegment(segment.id))
          effort.id,
      ],
      ['sl-1', 'sl-2', 'sl-3'],
      reason: 'S-111 the session\'s effort count grew by one',
    );
    expect(
      notifications,
      1,
      reason:
          'S-111 the mounted screen re-reads the session on one notification — '
          'the append is one change',
    );
    expect(
      find.byType(SessionSummaryScreen),
      findsOneWidget,
      reason: 'S-111 no screen change: the summary is still what is showing',
    );
    expect(
      find.byType(WorkoutSessionScreen),
      findsNothing,
      reason: 'S-111 the append did not open the session screen',
    );
    expect(tester.takeException(), isNull);
    expect(failures, isEmpty);
  });
}
