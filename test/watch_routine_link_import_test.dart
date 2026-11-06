// 125a (Phase 0): the importer links a wrist-run routine the phone never
// adopted (phone away) to the routine its slot ids spell, and stamps the run
// with the routine's identity.
//
// Plan: `docs/plans/2026-11-05-125-wrist-routine-focus-modality-plan/`
// `2026-11-05-125a-contract-and-phone-plan.md`, D-125-3, D-125-4, D-125-5.
// Scenario mapping:
//   S-12514 buildRoutinesDown keeps `focusModality` OFF the wire (D-125-2)
//   S-12515 the provider-only run imports as the routine, Focus as modality
//   S-12516 the wrist's own end.modality wins over the routine's Focus
//   S-12517 a routine with no Focus imports with modality null
//   S-12518 the routine deleted before import imports free, no throw
//   S-12519 a free workout's slot ids never link (exercise ids are not effort ids)
//   S-12520 the routine edited after the wrist started imports free
//   S-12521 create-only: an adopted session's identity is never rewritten
//
// Plain `test()` on the Mock store, the staging helper style of
// `test/watch_session_import_test.dart` (`_inbox`, `_deliverEach`, `_set`,
// `_end`): no widget and no real clock, every future a microtask of the mock
// repository. The template/segment/effort seeding follows
// `test/routine_session_modality_test.dart`.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/block_types.dart';
import 'package:omnitrain/core/constants/modality.dart';
import 'package:omnitrain/core/utils/logged_entry_rows.dart';
import 'package:omnitrain/core/utils/watch_reference_sync.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/watch/watch_session_inbox.dart';

import 'helpers/sync_protocol_harness.dart';
import 'helpers/watch_capture_import_harness.dart'
    show CaptureTransport, observationsUp, seedExercise;

/// The phone's clock: fixed, so every stamp the inbox writes is the same.
final DateTime _phoneNow = DateTime.utc(2026, 11, 5, 11);

const int _atMs = 1730000000000;

const String _startIso = '2026-11-05T10:10:00Z';
const String _endIso = '2026-11-05T10:40:00Z';

/// The wrist's per-session token (plan 81 D-4): slot ids are
/// `sx-<effortId>~<token>`.
const String _token = 'tokw';

int _msOf(String iso) => DateTime.parse(iso).toUtc().millisecondsSinceEpoch;

WatchSessionInbox _inbox(WorkoutRepository repository) {
  var ids = 0;
  return WatchSessionInbox(
    repository: repository,
    transport: CaptureTransport(),
    validator: loadProtocolValidator(),
    clock: () => _phoneNow,
    idFactory: () => 'msg-phone-${++ids}',
    onHistoryChanged: () async {},
    // A failure inside the inbox fails the test where it happened.
    onFailure: Error.throwWithStackTrace,
  );
}

Map<String, Object?> _set(
  String entryId, {
  required String slot,
  required String exerciseId,
}) => {
  'entryId': entryId,
  'eventId': entryId,
  'kind': 'set',
  'loggedAt': '2026-11-05T10:20:00Z',
  'sessionExerciseId': slot,
  'exerciseId': exerciseId,
  'reps': 8,
  'loadKg': 40,
};

Map<String, Object?> _end(String sessionId, {String? modality}) => {
  'entryId': 'end-$sessionId',
  'eventId': 'end-$sessionId',
  'kind': 'session_end',
  'loggedAt': _endIso,
  'startedAt': _startIso,
  'endedAt': _endIso,
  'status': 'completed',
  'modality': ?modality,
};

/// One two-slot routine `R` (`drill` + `set`, as the 122 seeding shapes them)
/// whose exercises exist in the catalog.
Future<WorkoutTemplate> _seedRoutine(
  MockWorkoutRepository repository, {
  required String id,
  required String name,
  String? focusModality,
  required List<String> effortIds,
}) async {
  await seedExercise(
    repository,
    id: 'ex-hold-$id',
    name: 'Hold $id',
    capabilities: ['hold', 'time', 'sets'],
  );
  await seedExercise(
    repository,
    id: 'ex-reps-$id',
    name: 'Reps $id',
    capabilities: ['reps', 'sets', 'load'],
  );
  await repository.createTemplate(
    WorkoutTemplate(
      id: id,
      name: name,
      focusModality: focusModality,
      createdAtMs: _atMs,
      updatedAtMs: _atMs,
    ),
  );
  await repository.createTemplateSegment(
    TemplateSegment(
      id: 'seg-$id',
      templateId: id,
      orderIndex: 0,
      segmentType: BlockTypes.strengthSets,
      name: 'Main',
      createdAtMs: _atMs,
      updatedAtMs: _atMs,
    ),
  );
  var order = 0;
  for (final effortId in effortIds) {
    await repository.createTemplateEffort(
      TemplateEffort(
        id: effortId,
        templateSegmentId: 'seg-$id',
        orderIndex: order++,
        effortKind: order == 1 ? BlockTypes.drill : BlockTypes.set,
        exerciseId: order == 1 ? 'ex-hold-$id' : 'ex-reps-$id',
        createdAtMs: _atMs,
      ),
    );
  }
  return await repository.getTemplateById(id) ?? (throw StateError('seeding'));
}

/// One set row from the wrist for each slot, then the completed end: the pass
/// that imports a finished provider-only session.
Future<void> _stageRoutineRun(
  MockWorkoutRepository repository,
  String sessionId,
  Map<String, String> slots, {
  String? endModality,
}) async {
  final inbox = _inbox(repository);
  final entries = slots.keys.toList();
  for (var i = 0; i < entries.length; i++) {
    await inbox.receive(
      observationsUp(sessionId, [
        _set('entry-$i', slot: entries[i], exerciseId: slots[entries[i]]!),
      ], messageId: 'msg-$i'),
    );
  }
  await inbox.receive(
    observationsUp(sessionId, [
      _end(sessionId, modality: endModality),
    ], messageId: 'msg-end'),
  );
}

/// The stored session row, or null.
Future<TrainingSession?> _session(
  WorkoutRepository repository,
  String sessionId,
) => repository.getSession(sessionId);

void main() {
  group('125a the importer links the routine (D-125-3, D-125-4)', () {
    test(
      'S-12514 buildRoutinesDown carries NO focusModality key (D-125-2)',
      () async {
        final repository = MockWorkoutRepository();
        await repository.initialize();
        await _seedRoutine(
          repository,
          id: 'tpl-focus',
          name: 'Evening Stretch',
          focusModality: Modality.isometricStretching,
          effortIds: ['teff-hold', 'teff-squat'],
        );

        final message = await WatchReferenceSync.buildRoutinesDown(
          repository: repository,
          generatedAt: _phoneNow,
        );
        final routines = (message['payload']! as Map)['routines']! as List;
        expect(routines, hasLength(1));
        expect(
          (routines.single as Map).containsKey('focusModality'),
          isFalse,
          reason: 'D-125-2 the phone does not emit focusModality in 125a',
        );
      },
    );

    test(
      'S-12515 a provider-only run imports as the routine, Focus won',
      () async {
        final repository = MockWorkoutRepository();
        await repository.initialize();
        await _seedRoutine(
          repository,
          id: 'tpl-r',
          name: 'Evening Stretch',
          focusModality: Modality.isometricStretching,
          effortIds: ['teff-r-a', 'teff-r-b'],
        );

        await _stageRoutineRun(repository, 'w-12515', {
          'sx-teff-r-a~$_token': 'ex-hold-tpl-r',
          'sx-teff-r-b~$_token': 'ex-reps-tpl-r',
        });

        final session = await _session(repository, 'w-12515');
        expect(session, isNotNull);
        expect(session!.intent, 'routine');
        expect(session.routineTemplateId, 'tpl-r');
        expect(session.title, 'Evening Stretch');
        expect(
          session.modality,
          Modality.isometricStretching,
          reason:
              'D-125-4 the routine Focus stamps modality when the wrist '
              'sent none',
        );
      },
    );

    test(
      "S-12516 the wrist's end.modality wins and the routine still links",
      () async {
        final repository = MockWorkoutRepository();
        await repository.initialize();
        await _seedRoutine(
          repository,
          id: 'tpl-r',
          name: 'Evening Stretch',
          focusModality: Modality.isometricStretching,
          effortIds: ['teff-r-a', 'teff-r-b'],
        );

        await _stageRoutineRun(repository, 'w-12516', {
          'sx-teff-r-a~$_token': 'ex-hold-tpl-r',
          'sx-teff-r-b~$_token': 'ex-reps-tpl-r',
        }, endModality: Modality.sports);

        final session = await _session(repository, 'w-12516');
        expect(session!.modality, Modality.sports);
        expect(session.intent, 'routine');
        expect(session.routineTemplateId, 'tpl-r');
        expect(session.title, 'Evening Stretch');
      },
    );

    test('S-12517 a routine with no Focus links with modality null', () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();
      await _seedRoutine(
        repository,
        id: 'tpl-r',
        name: 'Mixed Day',
        focusModality: null,
        effortIds: ['teff-r-a', 'teff-r-b'],
      );

      await _stageRoutineRun(repository, 'w-12517', {
        'sx-teff-r-a~$_token': 'ex-hold-tpl-r',
        'sx-teff-r-b~$_token': 'ex-reps-tpl-r',
      });

      final session = await _session(repository, 'w-12517');
      expect(session!.intent, 'routine');
      expect(session.routineTemplateId, 'tpl-r');
      expect(session.title, 'Mixed Day');
      expect(
        session.modality,
        isNull,
        reason: 'S-12517 no Focus and no wrist modality stays null',
      );
    });

    test('S-12518 the routine deleted before the import imports free, and '
        'throws nothing', () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();
      await _seedRoutine(
        repository,
        id: 'tpl-r',
        name: 'Evening Stretch',
        focusModality: Modality.isometricStretching,
        effortIds: ['teff-r-a', 'teff-r-b'],
      );
      await repository.deleteTemplate('tpl-r');

      await _stageRoutineRun(repository, 'w-12518', {
        'sx-teff-r-a~$_token': 'ex-hold-tpl-r',
        'sx-teff-r-b~$_token': 'ex-reps-tpl-r',
      });

      final session = await _session(repository, 'w-12518');
      expect(session, isNotNull, reason: 'S-12518 the run still imports');
      expect(session!.intent, isNull);
      expect(session.routineTemplateId, isNull);
      expect(session.title, isNull);
    });

    test('S-12519 a free workout slot ids never link', () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();
      await _seedRoutine(
        repository,
        id: 'tpl-r',
        name: 'Evening Stretch',
        focusModality: Modality.isometricStretching,
        effortIds: ['teff-r-a', 'teff-r-b'],
      );

      // Free picks are `sx-<exerciseId>`; no template effort's id is an
      // exercise id.
      await _stageRoutineRun(repository, 'w-12519', {
        'sx-ex-reps-tpl-r': 'ex-reps-tpl-r',
      });

      final session = await _session(repository, 'w-12519');
      expect(session, isNotNull);
      expect(session!.intent, isNull);
      expect(session.routineTemplateId, isNull);
      expect(session.title, isNull);
    });

    test(
      'S-12519 a run mixing one routine effort with a free pick never links',
      () async {
        final repository = MockWorkoutRepository();
        await repository.initialize();
        await _seedRoutine(
          repository,
          id: 'tpl-r',
          name: 'Evening Stretch',
          focusModality: Modality.isometricStretching,
          effortIds: ['teff-r-a', 'teff-r-b'],
        );

        // One slot names an effort of R, the other is a free pick: D-125-3
        // needs EVERY decoded id to be one of the template's own.
        await _stageRoutineRun(repository, 'w-12519m', {
          'sx-teff-r-a~$_token': 'ex-hold-tpl-r',
          'sx-ex-reps-tpl-r~$_token': 'ex-reps-tpl-r',
        });

        final session = await _session(repository, 'w-12519m');
        expect(session, isNotNull);
        expect(session!.intent, isNull);
        expect(session.routineTemplateId, isNull);
        expect(session.title, isNull);
      },
    );

    test('S-12515 the effort id is the text before the LAST tilde', () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();
      await _seedRoutine(
        repository,
        id: 'tpl-r',
        name: 'Evening Stretch',
        focusModality: Modality.isometricStretching,
        effortIds: ['teff~a'],
      );

      await _stageRoutineRun(repository, 'w-12515t', {
        'sx-teff~a~$_token': 'ex-hold-tpl-r',
      });

      final session = await _session(repository, 'w-12515t');
      expect(session, isNotNull);
      expect(session!.routineTemplateId, 'tpl-r');
    });

    test(
      'S-12520 the routine edited after the wrist started imports free',
      () async {
        final repository = MockWorkoutRepository();
        await repository.initialize();
        await _seedRoutine(
          repository,
          id: 'tpl-r',
          name: 'Evening Stretch',
          focusModality: Modality.isometricStretching,
          effortIds: ['teff-r-a', 'teff-r-b'],
        );
        // The user replaced the routine's efforts while the wrist ran.
        await repository.deleteTemplateEffort('teff-r-a');
        await repository.deleteTemplateEffort('teff-r-b');
        await repository.createTemplateEffort(
          TemplateEffort(
            id: 'teff-r-c',
            templateSegmentId: 'seg-tpl-r',
            orderIndex: 0,
            effortKind: BlockTypes.set,
            exerciseId: 'ex-reps-tpl-r',
            createdAtMs: _atMs,
          ),
        );

        await _stageRoutineRun(repository, 'w-12520', {
          'sx-teff-r-a~$_token': 'ex-hold-tpl-r',
          'sx-teff-r-b~$_token': 'ex-reps-tpl-r',
        });

        final session = await _session(repository, 'w-12520');
        expect(session, isNotNull);
        expect(session!.intent, isNull);
        expect(session.routineTemplateId, isNull);
        expect(session.title, isNull);
      },
    );

    test('S-12521 an adopted session is never rewritten by the importer '
        '(create-only)', () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();
      await repository.createSession(
        TrainingSession(
          id: 'w-12521',
          ownerUserId: LoggedEntryRows.ownerUserId,
          startedAtMs: _msOf(_startIso),
          endedAtMs: _msOf(_endIso),
          modality: Modality.resistanceLifting,
          title: 'Adopted name',
          intent: 'routine',
          routineTemplateId: 'tpl-adopted',
          sessionFeeling: null,
          createdAtMs: _msOf(_startIso),
          updatedAtMs: _msOf(_endIso),
        ),
      );
      await _seedRoutine(
        repository,
        id: 'tpl-r',
        name: 'Evening Stretch',
        focusModality: Modality.isometricStretching,
        effortIds: ['teff-r-a', 'teff-r-b'],
      );

      await _stageRoutineRun(repository, 'w-12521', {
        'sx-teff-r-a~$_token': 'ex-hold-tpl-r',
        'sx-teff-r-b~$_token': 'ex-reps-tpl-r',
      });

      final session = await _session(repository, 'w-12521');
      expect(session, isNotNull);
      expect(session!.title, 'Adopted name');
      expect(session.intent, 'routine');
      expect(session.routineTemplateId, 'tpl-adopted');
      expect(session.modality, Modality.resistanceLifting);
    });
  });
}
