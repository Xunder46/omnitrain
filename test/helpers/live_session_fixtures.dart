// Shared fixtures for the phone's live watch session — the mirror, a ladder,
// entries, and a transport that records what the phone emits.
//
// Plan: `docs/plans/2026-07-13-10-c2-phone-manage-bridge-live-sessions-plan.md`.
//
// The wire itself is proven in `test/phone_manage_bridge_test.dart`, where both
// devices are real. Widget and flow tests only need to know what the phone was
// shown and what it sent, so the transport here carries nothing.

import 'package:omnitrain/state/watch/live_session_mirror_state.dart';

/// Records what the phone emitted and carries nothing.
class RecordingMirrorTransport implements WatchMirrorTransport {
  final List<Map<String, Object?>> sent = [];
  int snapshotRequests = 0;

  /// The payloads of every message of [type] the phone sent.
  List<Map<String, Object?>> payloadsOf(String type) => [
    for (final envelope in sent)
      if (envelope['type'] == type) (envelope['payload']! as Map).cast(),
  ];

  /// The `changes` of the one `structure_change` the phone sent, as the `kind`
  /// of each change.
  List<Object?> changeKinds() => [
    for (final payload in payloadsOf('structure_change'))
      for (final change in payload['changes']! as List) (change as Map)['kind'],
  ];

  @override
  Future<void> send(Map<String, Object?> envelope) async => sent.add(envelope);

  @override
  Future<void> requestSnapshot() async => snapshotRequests++;
}

/// A ladder in the protocol's `sessionExercise` shape, as the phone sends it.
List<Map<String, Object?>> liveSessionSlots() => [
  liveSessionSlot('sx-bench', 'Barbell Bench Press'),
  liveSessionSlot('sx-plank', 'Plank', capabilities: const ['time', 'hold']),
  liveSessionSlot('sx-squat', 'Goblet Squat'),
];

/// The slot ids of a ladder, in order.
List<String> slotIdsOf(Iterable<Map<String, Object?>> exercises) => [
  for (final slot in exercises) slot['sessionExerciseId']! as String,
];

Map<String, Object?> liveSessionSlot(
  String slotId,
  String name, {
  List<String> capabilities = const ['sets', 'reps', 'load'],
}) => {
  'sessionExerciseId': slotId,
  'exerciseId': 'ex-$slotId',
  'name': name,
  'capabilities': capabilities,
};

/// One `set` entry as the wrist reports it.
Map<String, Object?> liveSessionEntry(
  String entryId, {
  String slot = 'sx-bench',
  int reps = 5,
  double loadKg = 80,
  String loggedAt = '2026-07-13T06:00:00Z',
}) => {
  'entryId': entryId,
  'eventId': entryId,
  'kind': 'set',
  'loggedAt': loggedAt,
  'sessionExerciseId': slot,
  'exerciseId': 'ex-$slot',
  'reps': reps,
  'loadKg': loadKg,
};

/// A live watch session as the phone's mirror holds it.
LiveSessionMirrorState liveWatchSession({
  String status = 'active',
  int revision = 7,
  int currentExerciseIndex = 0,
  List<Map<String, Object?>>? exercises,
  List<Map<String, Object?>> entries = const [],
  WatchMirrorTransport? transport,
}) => LiveSessionMirrorState(
  transport: transport ?? RecordingMirrorTransport(),
  snapshot: {
    'sessionId': 's-live-ui',
    'status': status,
    'revision': revision,
    'currentExerciseIndex': currentExerciseIndex,
    'exercises': exercises ?? liveSessionSlots(),
    'entries': entries,
    'timers': const <String, Object?>{},
  },
);
