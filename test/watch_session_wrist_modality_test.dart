// Plan 203 P1 — the phone adopts a wrist workout with the modality the wrist
// names.
//
// Plan: `docs/plans/2026-11-15-203-wrist-modality-reaches-phone-plan/2026-11-15-203-wrist-modality-reaches-phone-plan.md`,
// Phase P1 — D-20301, D-20302, D-20303. Scenario mapping:
//   S-20301 a wrist snapshot naming cardio_endurance adopts as Cardio → `S-20301 ...`
//   S-20302 a snapshot with no modality adopts as Free Training      → `S-20302 ...`
//   S-20303 an unknown, empty or non-string modality is ignored      → `S-20303 ...`
//   S-20304 the wrist's own modality wins over the routine's Focus   → `S-20304 ...`
//   S-20305 a session the phone already holds is not rewritten       → `S-20305 ...`
//   S-20307 source guard: only a snapshot's modality is read         → `S-20307 ...`
//
// Every snapshot arrives through the real `LiveSessionMirrorState` behind the
// real `WatchIncomingRouter` (the harness of
// `test/watch_session_adoption_bridge_test.dart`), so the router wiring is part
// of what these tests prove. The routine-matching case (S-20304) seeds the
// template the way `test/watch_routine_adoption_test.dart` does. Both stores
// run every scenario through the same harness (`harnessFactories`): Mock and
// Hive. Plain `test()`: no widget is involved, and a Hive write inside a
// widget test's fake-async zone never drains.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/block_types.dart';
import 'package:omnitrain/core/constants/capability.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/data/models/models.dart';
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
import 'helpers/watch_capture_import_harness.dart' show CaptureTransport;

/// The phone's clock, pinned: every row an adoption writes carries the same
/// stamps.
final DateTime _adoptedAt = DateTime.utc(2026, 11, 15, 12);

final SyncProtocolValidator _validator = loadProtocolValidator();

/// Marks a snapshot's `modality` key as absent, so a `null` modality can be
/// sent on the wire separately from no key at all.
const Object _absent = Object();

// ─── Fixture T (the routine the wrist started, from plan 36c) ───────────────

const String _templateId = 'routine-push';
const String _segmentId = 'routine-push-seg';
const String _benchEffortId = 'eff-bench';
const String _plankEffortId = 'eff-plank';
const String _benchSlot = 'sx-eff-bench';
const String _plankSlot = 'sx-eff-plank';

/// The per-session token the wrist appends to its slot ids (plan 81 D-1).
const String _token = 'ab12cd34';
const String _benchTokenedSlot = '$_benchSlot~$_token';
const String _plankTokenedSlot = '$_plankSlot~$_token';
const int _seededAt = 1788000000000;

// ─── The harness ────────────────────────────────────────────────────────────

Future<WorkoutRepository> _open(
  RepositoryHarness harness, {
  bool withTemplate = false,
  String? focusModality,
}) async {
  final repository = await harness.open();
  await seedExercise(
    repository,
    id: 'ex-bench',
    name: 'Barbell Bench Press',
    capabilities: const [
      ExerciseCapability.sets,
      ExerciseCapability.reps,
      ExerciseCapability.load,
    ],
  );
  await seedExercise(
    repository,
    id: 'ex-plank',
    name: 'Plank',
    capabilities: const [ExerciseCapability.hold, ExerciseCapability.time],
  );
  // Both implementations keep capabilities in a store of their own (see
  // `test/watch_session_adoption_bridge_test.dart`): set them the way the app
  // does, or a slot this session projects is unrenderable.
  await repository.setExerciseCapabilities('ex-bench', const [
    ExerciseCapability.sets,
    ExerciseCapability.reps,
    ExerciseCapability.load,
  ]);
  await repository.setExerciseCapabilities('ex-plank', const [
    ExerciseCapability.hold,
    ExerciseCapability.time,
  ]);
  if (withTemplate) {
    await _seedTemplate(repository, focusModality: focusModality);
  }
  return repository;
}

/// Fixture T: template "Push A", one segment, a `set` bench effort and a
/// `timed` plank effort (its ids are what the wrist's slot ids are built
/// from), whose Focus is [focusModality].
Future<void> _seedTemplate(
  WorkoutRepository repository, {
  required String? focusModality,
}) async {
  await repository.createTemplate(
    WorkoutTemplate(
      id: _templateId,
      ownerUserId: null,
      name: 'Push A',
      description: null,
      focusModality: focusModality,
      primaryDisciplineId: null,
      note: null,
      isBuiltInDemo: false,
      createdAtMs: _seededAt,
      updatedAtMs: _seededAt,
    ),
  );
  await repository.createTemplateSegment(
    TemplateSegment(
      id: _segmentId,
      templateId: _templateId,
      orderIndex: 0,
      segmentType: 'strength_sets',
      disciplineId: null,
      name: 'Main',
      note: null,
      createdAtMs: _seededAt,
      updatedAtMs: _seededAt,
    ),
  );
  await repository.createTemplateEffort(
    TemplateEffort(
      id: _benchEffortId,
      templateSegmentId: _segmentId,
      orderIndex: 0,
      effortKind: BlockTypes.set,
      modality: null,
      exerciseId: 'ex-bench',
      note: null,
      restSeconds: null,
      restType: null,
      createdAtMs: _seededAt,
    ),
  );
  await repository.createTemplateEffort(
    TemplateEffort(
      id: _plankEffortId,
      templateSegmentId: _segmentId,
      orderIndex: 1,
      effortKind: BlockTypes.timed,
      modality: null,
      exerciseId: 'ex-plank',
      note: null,
      restSeconds: null,
      restType: null,
      createdAtMs: _seededAt,
    ),
  );
}

/// One ladder slot as the wrist sends it.
Map<String, Object?> _slot(
  String sessionExerciseId,
  String exerciseId, {
  String? declaredKind,
  List<String> capabilities = const [
    ExerciseCapability.sets,
    ExerciseCapability.reps,
    ExerciseCapability.load,
  ],
}) => {
  'sessionExerciseId': sessionExerciseId,
  'exerciseId': exerciseId,
  'name': exerciseId,
  'capabilities': capabilities,
  'effortKind': ?declaredKind,
};

/// The routine ladder whose slot ids spell the seeded template (plan 36c).
Map<String, Object?> _benchTokened() =>
    _slot(_benchTokenedSlot, 'ex-bench', declaredKind: BlockTypes.set);

Map<String, Object?> _plankTokened() => _slot(
  _plankTokenedSlot,
  'ex-plank',
  declaredKind: BlockTypes.timed,
  capabilities: const [ExerciseCapability.hold, ExerciseCapability.time],
);

/// One `session_snapshot` from the wrist. [modality] left at [_absent] omits
/// the key; any other value — including `null`, `''` or a number — rides the
/// payload as it stands.
Map<String, Object?> _snapshot({
  required String sessionId,
  int revision = 3,
  List<Map<String, Object?>> exercises = const [],
  Object? modality = _absent,
  String messageId = 'msg-snapshot',
}) {
  final payload = <String, Object?>{
    'sessionId': sessionId,
    'revision': revision,
    'status': WatchSessionStatus.active,
    'currentExerciseIndex': 0,
    'exercises': [...exercises],
    'entries': <Object?>[],
    'timers': <String, Object?>{},
  };
  if (!identical(modality, _absent)) payload['modality'] = modality;
  return {
    'protocolVersion': SyncProtocolValidator.protocolVersion,
    'messageId': messageId,
    'sessionId': sessionId,
    'type': 'session_snapshot',
    'origin': 'watch',
    'sentAt': '2026-11-15T11:00:00Z',
    'payload': payload,
  };
}

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
    'S-20301 a wrist snapshot naming cardio_endurance adopts as Cardio',
    () async {
      // Two known keys, so a hard-coded `cardio_endurance` dies on the second.
      for (final (sessionId, modality) in const [
        ('s-w203a', 'cardio_endurance'),
        ('s-w203a2', 'sports'),
      ]) {
        for (final factory in harnessFactories) {
          final harness = factory();
          try {
            final repository = await _open(harness);
            final phone = await _phone(repository);

            await phone.router.receive(
              _snapshot(
                sessionId: sessionId,
                messageId: 'msg-$sessionId',
                // A free-style ladder: no routine matches it.
                exercises: [
                  _slot('sl-1', 'ex-bench', declaredKind: BlockTypes.set),
                ],
                modality: modality,
              ),
            );

            final session = await repository.getSession(sessionId);
            expect(
              session,
              isNotNull,
              reason: '${harness.name}: S-20301 the snapshot adopted',
            );
            expect(
              session!.modality,
              modality,
              reason:
                  '${harness.name}: S-20301 the row holds the modality the '
                  'wrist named ($modality), not Free Training',
            );
            expect(
              phone.failures,
              isEmpty,
              reason: '${harness.name}: S-20301 no failure',
            );
          } finally {
            await harness.close();
          }
        }
      }
    },
  );

  test('S-20302 a snapshot with no modality adopts as Free Training '
      '(today\'s behaviour)', () async {
    for (final factory in harnessFactories) {
      final harness = factory();
      try {
        final repository = await _open(harness);
        final phone = await _phone(repository);

        await phone.router.receive(
          _snapshot(
            sessionId: 's-w203b',
            messageId: 'msg-s-w203b',
            exercises: [
              _slot('sl-1', 'ex-bench', declaredKind: BlockTypes.set),
            ],
          ),
        );

        final session = await repository.getSession('s-w203b');
        expect(
          session,
          isNotNull,
          reason: '${harness.name}: S-20302 the snapshot adopted',
        );
        expect(
          session!.modality,
          isNull,
          reason:
              '${harness.name}: S-20302 without the key the row is Free '
              'Training, byte-for-byte today\'s',
        );
        expect(phone.failures, isEmpty, reason: '${harness.name}: no failure');
      } finally {
        await harness.close();
      }
    }
  });

  test('S-20303 an unknown, empty or non-string modality is ignored', () async {
    // Three separate runs. A key the phone cannot render is adopted with no
    // modality (D-20302); an empty string and a number are refused by the
    // wire's own schema (`modality` is typed a non-empty string), so the
    // snapshot never reaches adoption at all. None of them may plant a
    // modality on the stored session.
    for (final (sessionId, value, schemaAllows) in const [
      ('s-w203c1', 'curling', true),
      ('s-w203c2', '', false),
      ('s-w203c3', 5, false),
    ]) {
      for (final factory in harnessFactories) {
        final harness = factory();
        try {
          final repository = await _open(harness);
          final phone = await _phone(repository);

          final receipt = await phone.router.receive(
            _snapshot(
              sessionId: sessionId,
              messageId: 'msg-$sessionId',
              exercises: [
                _slot('sl-1', 'ex-bench', declaredKind: BlockTypes.set),
              ],
              modality: value,
            ),
          );
          final session = await repository.getSession(sessionId);
          if (schemaAllows) {
            expect(
              receipt.session,
              MirrorOutcome.applied,
              reason: '${harness.name}: S-20303 the snapshot applied',
            );
            expect(
              session,
              isNotNull,
              reason: '${harness.name}: S-20303 the snapshot adopted',
            );
            expect(
              session!.modality,
              isNull,
              reason:
                  '${harness.name}: S-20303 an unknown modality ($value) is '
                  'ignored, the row stays Free Training',
            );
          } else {
            expect(
              session,
              isNull,
              reason:
                  '${harness.name}: S-20303 the schema refuses modality '
                  '${value.runtimeType} "$value", so nothing is adopted',
            );
          }
          expect(
            phone.failures,
            isEmpty,
            reason: '${harness.name}: no failure',
          );
        } finally {
          await harness.close();
        }
      }
    }
  });

  test('S-20304 the wrist\'s own modality wins over the routine\'s Focus and '
      'the routine still links', () async {
    for (final factory in harnessFactories) {
      final harness = factory();
      try {
        final repository = await _open(
          harness,
          withTemplate: true,
          focusModality: 'resistance_lifting',
        );
        final phone = await _phone(repository);

        await phone.router.receive(
          _snapshot(
            sessionId: 's-w203d',
            messageId: 'msg-s-w203d',
            // The ladder the wrist builds from the template's effort ids:
            // this snapshot IS a run of Push A.
            exercises: [_benchTokened(), _plankTokened()],
            modality: 'cardio_endurance',
          ),
        );

        final session = await repository.getSession('s-w203d');
        expect(
          session,
          isNotNull,
          reason: '${harness.name}: S-20304 the snapshot adopted',
        );
        expect(
          session!.modality,
          'cardio_endurance',
          reason:
              '${harness.name}: S-20304 the wrist\'s own key wins over the '
              'routine\'s Focus (resistance_lifting)',
        );
        expect(
          session.routineTemplateId,
          _templateId,
          reason: '${harness.name}: S-20304 the routine still links',
        );
        expect(phone.failures, isEmpty, reason: '${harness.name}: no failure');
      } finally {
        await harness.close();
      }
    }
  });

  test('S-20305 a session the phone already holds is not rewritten', () async {
    for (final factory in harnessFactories) {
      final harness = factory();
      try {
        final repository = await _open(harness);
        final phone = await _phone(repository);

        // 1. Adopted with no modality: Free Training.
        await phone.router.receive(
          _snapshot(
            sessionId: 's-w203e',
            messageId: 'msg-s-w203e-1',
            exercises: [
              _slot('sl-1', 'ex-bench', declaredKind: BlockTypes.set),
            ],
          ),
        );
        expect(
          (await repository.getSession('s-w203e'))!.modality,
          isNull,
          reason: '${harness.name}: S-20305 the adoption is Free Training',
        );

        // 2. A later snapshot of the same session names a modality. The phone
        // holds the session, so nothing is rewritten (D-20303).
        await phone.router.receive(
          _snapshot(
            sessionId: 's-w203e',
            revision: 4,
            messageId: 'msg-s-w203e-2',
            exercises: [
              _slot('sl-1', 'ex-bench', declaredKind: BlockTypes.set),
            ],
            modality: 'cardio_endurance',
          ),
        );

        expect(
          (await repository.getSession('s-w203e'))!.modality,
          isNull,
          reason:
              '${harness.name}: S-20305 the held session\'s modality is '
              'unchanged',
        );
        expect(phone.failures, isEmpty, reason: '${harness.name}: no failure');
      } finally {
        await harness.close();
      }
    }
  });

  test('S-20307 source guard: only a snapshot\'s modality is read', () {
    final source = File(
      '${Directory.current.path}/lib/state/watch/watch_incoming_router.dart',
    ).readAsStringSync();
    final lines = [for (final line in source.split('\n')) line.trim()];

    // The whole statement that returns null for anything that is not a
    // `session_snapshot`, as a whole line — never a substring.
    expect(
      lines,
      contains('if (envelope[\'type\'] != \'session_snapshot\') return null;'),
      reason: 'S-20307 the guard reads the type before the payload',
    );
    // The whole argument the router hands `consider`.
    expect(
      lines,
      contains('wristModality: _wristModality(envelope),'),
      reason: 'S-20307 the router passes the wrist\'s modality to consider',
    );
  });
}
