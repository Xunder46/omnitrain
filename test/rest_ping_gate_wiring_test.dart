// Plan 86 P2 — the wiring binds the rest-ping gate to the watch link and the
// mirror (D-3, D-8). Scenario mapping:
//   S-15609 the gate is read at call time          → `S-15609 ...`
//   S-15609 with no watch graph the gate stays null → `S-15609 with no watch ...`
//   S-15610 the listeners drive the takeover        → `S-15610 ...`
//   S-15611 no phantom ping after the wrist ends    → `S-15611 ...`
//
// Real objects throughout: a real `WatchLinkState` over a `_Source` fake
// (copied from `test/watch_link_state_test.dart:32`), a real
// `LiveSessionMirrorState` over a recording `WatchMirrorTransport` fed the way
// `test/watch_session_adoption_bridge_test.dart` feeds snapshots, a real
// `WorkoutState` over a `MockWorkoutRepository` seeded with the session row,
// and the service through `RestNotificationService.withPlugin`. Plain `test()`:
// no widget, no real clock.

import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/platform/watch_delivery.dart';
import 'package:omnitrain/core/platform/watch_link_info.dart';
import 'package:omnitrain/core/platform/watch_link_source.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/core/utils/logged_entry_rows.dart';
import 'package:omnitrain/core/utils/rest_notification_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/watch/live_session_mirror_state.dart';
import 'package:omnitrain/state/watch/watch_link_state.dart';
import 'package:omnitrain/state/watch/watch_rest_ping_wiring.dart';
import 'package:omnitrain/state/watch/watch_sync_wiring.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'helpers/sync_protocol_harness.dart' show loadProtocolValidator;

final DateTime _now = DateTime.utc(2026, 10, 26, 12);
final int _nowMs = _now.millisecondsSinceEpoch;

final WatchLinkInfo _connected = WatchLinkInfo(
  paired: true,
  appInstalled: true,
  reachable: true,
);

final WatchLinkInfo _notReachable = WatchLinkInfo(
  paired: true,
  appInstalled: true,
  reachable: false,
);

/// The link fake from `test/watch_link_state_test.dart:32`.
class _Source implements WatchLinkSource {
  WatchLinkInfo infoValue = _connected;

  final StreamController<WatchLinkInfo> changes =
      StreamController<WatchLinkInfo>.broadcast();
  final StreamController<DateTime> heardEvents =
      StreamController<DateTime>.broadcast();

  @override
  Future<WatchLinkInfo> linkInfo() async => infoValue;

  @override
  Stream<WatchLinkInfo> get linkChanges => changes.stream;

  @override
  Stream<DateTime> get heard => heardEvents.stream;
}

/// A transport that records what the phone sent and carries nothing.
class _RecordingTransport implements WatchMirrorTransport {
  final List<Map<String, Object?>> sent = [];

  @override
  Future<WatchDelivery> send(Map<String, Object?> envelope) async {
    sent.add(envelope);
    return WatchDelivery.delivered;
  }

  @override
  Future<void> requestSnapshot() async {}
}

/// One ladder slot as the wrist sends it.
Map<String, Object?> _slot(String sessionExerciseId, String exerciseId) => {
  'sessionExerciseId': sessionExerciseId,
  'exerciseId': exerciseId,
  'name': exerciseId,
  'capabilities': ['sets', 'reps', 'load'],
};

/// One `session_snapshot` from the wrist.
Map<String, Object?> _snapshot({
  required String sessionId,
  required int revision,
  String status = WatchSessionStatus.active,
  String messageId = 'msg-snapshot',
}) => {
  'protocolVersion': SyncProtocolValidator.protocolVersion,
  'messageId': messageId,
  'sessionId': sessionId,
  'type': 'session_snapshot',
  'origin': 'watch',
  'sentAt': '2026-10-26T10:00:00Z',
  'payload': {
    'sessionId': sessionId,
    'revision': revision,
    'status': status,
    'currentExerciseIndex': 0,
    'exercises': [_slot('sl-1', 'ex-bench')],
    'entries': <Object?>[],
    'timers': <String, Object?>{},
  },
};

/// One `session_lifecycle` from the wrist, as the shipping watch emits it.
Map<String, Object?> _lifecycle(
  String sessionId, {
  String state = WatchLifecycleState.completed,
  String messageId = 'msg-wrist-lifecycle',
}) => {
  'protocolVersion': SyncProtocolValidator.protocolVersion,
  'messageId': messageId,
  'sessionId': sessionId,
  'type': 'session_lifecycle',
  'origin': 'watch',
  'sentAt': '2026-10-26T10:30:00Z',
  'payload': {'state': state, 'at': '2026-10-26T10:30:00Z'},
};

RestNotificationService _service(
  List<int> scheduledIds,
  List<int> canceledIds,
) => RestNotificationService.withPlugin(
  FlutterLocalNotificationsPlugin(),
  isWeb: false,
  nowProvider: () => _now,
  cancelOverride: (id) async => canceledIds.add(id),
  zonedScheduleOverride:
      ({
        required id,
        required title,
        required body,
        required scheduledDate,
        required details,
      }) async {
        scheduledIds.add(id);
      },
);

/// The phone: session `s-1` loaded as its own, the link connected, the
/// mirror holding `s-1` active, and the gate bound.
Future<
  ({
    RestNotificationService service,
    _Source source,
    LiveSessionMirrorState mirror,
    WorkoutState state,
    List<int> scheduledIds,
    List<int> canceledIds,
  })
>
_fixture() async {
  final repository = MockWorkoutRepository();
  await repository.initialize();
  const at = 1780000000000;
  await repository.createSession(
    TrainingSession(
      id: 's-1',
      ownerUserId: LoggedEntryRows.ownerUserId,
      startedAtMs: at,
      createdAtMs: at,
      updatedAtMs: at,
    ),
  );
  final state = WorkoutState(repository);
  await state.loadHistoricalSession('s-1');
  expect(state.currentSession?.id, 's-1');

  final source = _Source();
  final link = WatchLinkState(source: source, repository: repository);
  await link.initialize();
  expect(link.phase, WatchLinkPhase.connected);

  final transport = _RecordingTransport();
  final mirror = LiveSessionMirrorState(
    transport: transport,
    snapshot: watchSessionPlaceholder,
    validator: loadProtocolValidator(),
  );
  final outcome = await mirror.receive(
    _snapshot(sessionId: 's-1', revision: 3, messageId: 'msg-s1'),
  );
  expect(outcome, MirrorOutcome.applied);
  expect(mirror.sessionId, 's-1');
  expect(mirror.isActive, isTrue);

  final scheduledIds = <int>[];
  final canceledIds = <int>[];
  final service = _service(scheduledIds, canceledIds);
  bindRestPingGate(
    service: service,
    link: link,
    mirror: mirror,
    workoutState: state,
  );
  return (
    service: service,
    source: source,
    mirror: mirror,
    state: state,
    scheduledIds: scheduledIds,
    canceledIds: canceledIds,
  );
}

void main() {
  setUpAll(() {
    if (tz.timeZoneDatabase.locations.isEmpty) {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('UTC'));
    }
  });

  group('S-15609 the gate is read at call time', () {
    test(
      'true while owned, false after the link drops, false after the wrist moves on',
      () async {
        final f = await _fixture();
        expect(f.service.wristOwnsPings!(), isTrue);

        f.source.infoValue = _notReachable;
        f.source.changes.add(_notReachable);
        await pumpEventQueue();
        expect(f.service.wristOwnsPings!(), isFalse);

        final outcome = await f.mirror.receive(
          _snapshot(sessionId: 's-2', revision: 1, messageId: 'msg-s2'),
        );
        expect(outcome, MirrorOutcome.applied);
        expect(f.mirror.sessionId, 's-2');
        expect(f.service.wristOwnsPings!(), isFalse);
      },
    );

    test('with no watch graph the gate stays null', () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();
      final state = WorkoutState(repository);
      final service = _service(<int>[], <int>[]);

      bindRestPingGate(
        service: service,
        link: null,
        mirror: null,
        workoutState: state,
      );

      expect(service.wristOwnsPings, isNull);
    });
  });

  group('S-15610 the listeners drive the takeover', () {
    test(
      'link drop re-schedules the 48 future boundaries; link return cancels',
      () async {
        final f = await _fixture();

        // Remembered under a true gate: nothing scheduled, 50 cancels.
        await f.service.scheduleRestPings(
          restStartMs: _nowMs - 70000,
          intervalSecs: 30,
          soundId: 'soft_chime',
        );
        expect(f.scheduledIds, isEmpty);
        expect(f.canceledIds.length, 50);

        // The link drops: the phone takes over. 30 s and 60 s are in the past
        // at the pinned now, so 48 schedules, ids 102..149.
        f.source.infoValue = _notReachable;
        f.source.changes.add(_notReachable);
        await pumpEventQueue();
        expect(f.scheduledIds.length, 48);
        expect(
          f.scheduledIds,
          List.generate(
            48,
            (i) => RestNotificationService.restPingBaseId + 2 + i,
          ),
        );
        expect(f.canceledIds.length, 100);

        // The link returns: the wrist owns the pings again, what was
        // scheduled is withdrawn.
        f.source.infoValue = _connected;
        f.source.changes.add(_connected);
        await pumpEventQueue();
        expect(f.scheduledIds.length, 48);
        expect(f.canceledIds.length, 150);
      },
    );
  });

  group('S-15611 no phantom ping after the wrist ends the session', () {
    test(
      'lifecycle completed cancels and forgets; a later link flap schedules nothing',
      () async {
        final f = await _fixture();

        // Remembered under a true gate.
        await f.service.scheduleRestPings(
          restStartMs: _nowMs - 70000,
          intervalSecs: 30,
          soundId: 'soft_chime',
        );
        expect(f.scheduledIds, isEmpty);
        expect(f.canceledIds.length, 50);

        // The wrist's session_lifecycle completed for s-1 arrives through the
        // real mirror: the wiring cancels and forgets.
        final outcome = await f.mirror.receive(_lifecycle('s-1'));
        expect(outcome, MirrorOutcome.applied);
        await pumpEventQueue();
        expect(f.mirror.isActive, isFalse);
        expect(f.scheduledIds, isEmpty);
        expect(f.canceledIds.length, 100);

        // A later link flap re-evaluates nothing: the request was forgotten.
        f.source.infoValue = _notReachable;
        f.source.changes.add(_notReachable);
        await pumpEventQueue();
        expect(f.scheduledIds, isEmpty);
        expect(f.canceledIds.length, 100);
      },
    );
  });

  group('S-15611b a wrist that moves to another session does not silence the phone', () {
    test(
      'a snapshot naming s-2 while the phone stays on s-1 re-schedules the open rest',
      () async {
        final f = await _fixture();

        // Remembered under a true gate (the wrist owns s-1's pings).
        await f.service.scheduleRestPings(
          restStartMs: _nowMs - 70000,
          intervalSecs: 30,
          soundId: 'soft_chime',
        );
        expect(f.scheduledIds, isEmpty);

        // The wrist abandons s-1 with no end frame and starts s-2: the mirror
        // switches wholesale, still active, now naming a different session.
        await f.mirror.receive(
          _snapshot(sessionId: 's-2', revision: 1, messageId: 'msg-s2b'),
        );
        await pumpEventQueue();
        expect(f.mirror.sessionId, 's-2');
        expect(f.mirror.isActive, isTrue);

        // The phone's rest is still open and nobody pings it now: the pings are
        // handed back, from the rest's own start (48 future boundaries).
        expect(f.scheduledIds.length, 48);
        expect(f.scheduledIds.first, RestNotificationService.restPingBaseId + 2);
      },
    );
  });
}
