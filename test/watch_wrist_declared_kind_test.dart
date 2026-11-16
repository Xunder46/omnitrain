// Plan 206 P2 — the phone honours a wrist slot's declared effort kind.
//
// Plan: `docs/plans/2026-11-15-206-wrist-logging-follows-modality-plan/2026-11-15-206-wrist-logging-follows-modality-plan.md`,
// Phase P2, scenario S-20606 (tests only: pins behaviour the phone already
// has, so no phone change is needed):
//   S-20606 a slot declaring `timed` is adopted as a timed effort        → `S-20606 a wrist slot ...`
//   S-20606 the same exercise undeclared resolves from its capabilities  → `S-20606 the same exercise ...`
//   S-20606 a declared `drill` and a declared `round` are adopted as such → `S-20606 a declared drill ...`
//
// `WatchSessionAdoptionBridge._effortKind` (lib/state/watch/
// watch_session_adoption_bridge.dart ~1600): a declared kind in
// `set/timed/round/drill` wins over the capabilities. Every snapshot arrives
// through the real `LiveSessionMirrorState` behind the real
// `WatchIncomingRouter`, exactly as plan 203's
// `test/watch_session_wrist_modality_test.dart` proves it; the harness is
// copied from that file. Both stores run every scenario through the same
// harness (`harnessFactories`). Plain `test()`: no widget is involved, and a
// Hive write inside a widget test's fake-async zone never drains.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/block_types.dart';
import 'package:omnitrain/core/constants/capability.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/watch/live_session_mirror_state.dart';
import 'package:omnitrain/state/watch/watch_incoming_router.dart';
import 'package:omnitrain/state/watch/watch_nutrition_log_bridge.dart';
import 'package:omnitrain/state/watch/watch_session_adoption_bridge.dart';
import 'package:omnitrain/state/watch/watch_session_inbox.dart';
import 'package:omnitrain/state/watch/watch_sync_wiring.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/watch/session/watch_records.dart';

import 'helpers/repository_harness.dart';
import 'helpers/sync_protocol_harness.dart';
import 'helpers/watch_capture_import_harness.dart'
    show CaptureTransport, importedEfforts;

/// The phone's clock, pinned: every row an adoption writes carries the same
/// stamps.
final DateTime _adoptedAt = DateTime.utc(2026, 11, 15, 12);

final SyncProtocolValidator _validator = loadProtocolValidator();

// ─── The harness (copied from plan 203's wrist-modality test) ───────────────

Future<WorkoutRepository> _open(RepositoryHarness harness) async {
  final repository = await harness.open();
  await seedExercise(
    repository,
    id: 'ex-w206-a',
    name: 'Endurance Row',
    capabilities: const [
      ExerciseCapability.sets,
      ExerciseCapability.reps,
      ExerciseCapability.time,
    ],
  );
  await seedExercise(
    repository,
    id: 'ex-w206-drill',
    name: 'Skill Drill',
    capabilities: const [
      ExerciseCapability.reps,
      ExerciseCapability.sets,
      ExerciseCapability.load,
    ],
  );
  await seedExercise(
    repository,
    id: 'ex-w206-round',
    name: 'Interval Round',
    capabilities: const [ExerciseCapability.time, ExerciseCapability.distance],
  );
  // Both implementations keep capabilities in a store of their own (see
  // `test/watch_session_adoption_bridge_test.dart`): set them the way the app
  // does, or a slot this session projects is unrenderable.
  await repository.setExerciseCapabilities('ex-w206-a', const [
    ExerciseCapability.sets,
    ExerciseCapability.reps,
    ExerciseCapability.time,
  ]);
  await repository.setExerciseCapabilities('ex-w206-drill', const [
    ExerciseCapability.reps,
    ExerciseCapability.sets,
    ExerciseCapability.load,
  ]);
  await repository.setExerciseCapabilities('ex-w206-round', const [
    ExerciseCapability.time,
    ExerciseCapability.distance,
  ]);
  return repository;
}

/// One ladder slot as the wrist sends it. [declaredKind] left null omits the
/// `effortKind` key, so an undeclared slot rides the wire without it.
Map<String, Object?> _slot(
  String sessionExerciseId,
  String exerciseId, {
  String? declaredKind,
  required List<String> capabilities,
}) => {
  'sessionExerciseId': sessionExerciseId,
  'exerciseId': exerciseId,
  'name': exerciseId,
  'capabilities': capabilities,
  'effortKind': ?declaredKind,
};

/// One `session_snapshot` from the wrist.
Map<String, Object?> _snapshot({
  required String sessionId,
  required List<Map<String, Object?>> exercises,
  int revision = 3,
  String messageId = 'msg-snapshot',
}) => {
  'protocolVersion': SyncProtocolValidator.protocolVersion,
  'messageId': messageId,
  'sessionId': sessionId,
  'type': 'session_snapshot',
  'origin': 'watch',
  'sentAt': '2026-11-15T11:00:00Z',
  'payload': {
    'sessionId': sessionId,
    'revision': revision,
    'status': WatchSessionStatus.active,
    'currentExerciseIndex': 0,
    'exercises': [...exercises],
    'entries': <Object?>[],
    'timers': <String, Object?>{},
    'modality': 'cardio_endurance',
  },
};

/// One phone, wired the way `createWatchSync` wires it: the watch session
/// inbox, the mirror behind the entry-staging transport, the router that
/// drives them, and the bridge bound to a real `WorkoutState`.
class _Phone {
  _Phone({
    required this.router,
    required this.mirror,
    required this.state,
    required this.failures,
  });

  final WatchIncomingRouter router;
  final LiveSessionMirrorState mirror;
  final WorkoutState state;

  /// What the bridge reported as a failure: nothing, in these tests.
  final List<Object> failures;
}

Future<_Phone> _phone(WorkoutRepository repository) async {
  final failures = <Object>[];
  final transport = CaptureTransport();
  final inbox = WatchSessionInbox(
    repository: repository,
    transport: transport,
    clock: () => _adoptedAt,
    onFailure: (error, stack) => fail('the watch session inbox failed: $error'),
  );
  final mirror = LiveSessionMirrorState(
    transport: WatchInboxStagingTransport(inner: transport, inbox: inbox),
    snapshot: watchSessionPlaceholder,
    validator: _validator,
    clock: () => _adoptedAt,
  );
  final bridge = WatchSessionAdoptionBridge(
    repository: repository,
    clock: () => _adoptedAt,
    onFailure: (error, stack) => failures.add(error),
  );
  final state = WorkoutState(repository);
  bridge.bindWorkoutState(state);

  return _Phone(
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
    mirror: mirror,
    state: state,
    failures: failures,
  );
}

void main() {
  test(
    'S-20606 a wrist slot that declares timed is adopted as a timed effort',
    () async {
      for (final factory in harnessFactories) {
        final harness = factory();
        try {
          final repository = await _open(harness);
          final phone = await _phone(repository);

          await phone.router.receive(
            _snapshot(
              sessionId: 's-w-206',
              messageId: 'msg-s-w-206',
              exercises: [
                _slot(
                  'sl-w206-timed',
                  'ex-w206-a',
                  declaredKind: BlockTypes.timed,
                  capabilities: const [
                    ExerciseCapability.sets,
                    ExerciseCapability.reps,
                    ExerciseCapability.time,
                  ],
                ),
              ],
            ),
          );

          final efforts = await importedEfforts(repository, 's-w-206');
          expect(
            [for (final effort in efforts) effort.effortKind],
            [BlockTypes.timed],
            reason:
                '${harness.name}: S-20606 the declared kind wins over the '
                'capabilities (which alone would resolve to set)',
          );
          expect(phone.failures, isEmpty, reason: '${harness.name}: no failure');
        } finally {
          await harness.close();
        }
      }
    },
  );

  test(
    'S-20606 the same exercise without a declared kind keeps resolving from '
    'its capabilities',
    () async {
      for (final factory in harnessFactories) {
        final harness = factory();
        try {
          final repository = await _open(harness);
          final phone = await _phone(repository);

          // The identical snapshot, only the `effortKind` key is gone.
          await phone.router.receive(
            _snapshot(
              sessionId: 's-w-206-b',
              messageId: 'msg-s-w-206-b',
              exercises: [
                _slot(
                  'sl-w206-cap',
                  'ex-w206-a',
                  capabilities: const [
                    ExerciseCapability.sets,
                    ExerciseCapability.reps,
                    ExerciseCapability.time,
                  ],
                ),
              ],
            ),
          );

          final efforts = await importedEfforts(repository, 's-w-206-b');
          expect(
            [for (final effort in efforts) effort.effortKind],
            [BlockTypes.set],
            reason:
                '${harness.name}: S-20606 with nothing declared the capability '
                'resolution decides — the set-deciding metrics beat `time`, so '
                'the effort logs as a set',
          );
          expect(phone.failures, isEmpty, reason: '${harness.name}: no failure');
        } finally {
          await harness.close();
        }
      }
    },
  );

  test(
    'S-20606 a declared drill and a declared round are adopted as those kinds',
    () async {
      for (final factory in harnessFactories) {
        final harness = factory();
        try {
          final repository = await _open(harness);
          final phone = await _phone(repository);

          await phone.router.receive(
            _snapshot(
              sessionId: 's-w-206-c',
              messageId: 'msg-s-w-206-c',
              exercises: [
                _slot(
                  'sl-w206-drill',
                  'ex-w206-drill',
                  declaredKind: BlockTypes.drill,
                  capabilities: const [
                    ExerciseCapability.reps,
                    ExerciseCapability.sets,
                    ExerciseCapability.load,
                  ],
                ),
                _slot(
                  'sl-w206-round',
                  'ex-w206-round',
                  declaredKind: BlockTypes.round,
                  capabilities: const [
                    ExerciseCapability.time,
                    ExerciseCapability.distance,
                  ],
                ),
              ],
            ),
          );

          final efforts = await importedEfforts(repository, 's-w-206-c');
          expect(
            [for (final effort in efforts) effort.effortKind],
            [BlockTypes.drill, BlockTypes.round],
            reason:
                '${harness.name}: S-20606 each declared kind is honoured in '
                'the slot\'s own order — a drill over set-deciding '
                'capabilities, a round over time and distance',
          );
          expect(phone.failures, isEmpty, reason: '${harness.name}: no failure');
        } finally {
          await harness.close();
        }
      }
    },
  );
}
