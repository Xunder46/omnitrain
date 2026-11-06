// Plan 122, Phase 0a — the red tests for the one-time back-fill of a past
// routine session's modality from its routine's Focus, scenarios
// S-12207 and S-12210..S-12216 of
// `docs/plans/2026-11-05-122-routine-session-modality-plan/2026-11-05-122-routine-session-modality-plan.md`.
//
// Step `backfillRoutineSessionModality` (version 18, D-12206/D-12207) walks
// `getAllSessions()`, stamps `modality` from the linked routine's
// `focusModality` onto rows that are `intent == 'routine'` with a null
// modality, a non-empty `routineTemplateId` and a focused template, writes
// only `modality`, never touches planned rows, and is idempotent
// (D-12208). Both stores must agree, so the shared cases run over
// `harnessFactories` with plain `test()`: a Hive write inside a widget
// test's FakeAsync never completes. Written red first (Phase 0: the step did
// not exist, so the shared lookup helper threw a clear StateError).

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/data_version.dart';
import 'package:omnitrain/core/services/data_migration_service.dart';
import 'package:omnitrain/core/utils/logged_entry_rows.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/hive_workout_repository.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';

import 'helpers/repository_harness.dart';

/// A fixed timestamp: the fixtures take no clock reading.
const int _atMs = 1700000000000;

const String _stepName = 'backfillRoutineSessionModality';

/// Records `updateSession` ids, then calls super.
class _CountingUpdateRepo extends MockWorkoutRepository {
  final List<String> updated = [];

  @override
  Future<void> updateSession(TrainingSession session) async {
    updated.add(session.id);
    await super.updateSession(session);
  }
}

/// Throws on the 2nd and later `updateSession` call while [failing];
/// records every successful write before calling super.
class _FailingUpdateRepo extends MockWorkoutRepository {
  bool failing = true;
  final List<String> written = [];

  @override
  Future<void> updateSession(TrainingSession session) async {
    if (failing && written.isNotEmpty) throw StateError('simulated');
    written.add(session.id);
    await super.updateSession(session);
  }
}

/// The ordered migration steps of whichever store [repo] is.
List<DataMigrationStep> _steps(WorkoutRepository repo) =>
    repo is MockWorkoutRepository
    ? repo.dataMigrationStepsForTest()
    : (repo as HiveWorkoutRepository).dataMigrationStepsForTest();

/// The back-fill step itself, or a StateError that says plainly what is
/// missing — so a RED run reports the right reason, not a bare "No element".
DataMigrationStep _backfillStep(WorkoutRepository repo) {
  final steps = _steps(repo);
  final matches = steps.where((step) => step.name == _stepName).toList();
  if (matches.length != 1) {
    throw StateError(
      'plan 122 Phase 2 not implemented: the migration step '
      '"$_stepName" does not exist yet — the step list holds '
      '[${steps.map((step) => '${step.targetVersion}:${step.name}').join(', ')}]',
    );
  }
  return matches.single;
}

/// Runs the back-fill step alone, as the migration service would.
Future<void> _runStep(WorkoutRepository repo) => _backfillStep(repo).run();

/// The fixed "day D" the calendar scenario stands on.
DateTime get _dayD => DateTime.fromMillisecondsSinceEpoch(_atMs);

WorkoutTemplate _template(String id, String name, {String? focusModality}) =>
    WorkoutTemplate(
      id: id,
      name: name,
      focusModality: focusModality,
      createdAtMs: _atMs,
      updatedAtMs: _atMs,
    );

TemplateSegment _segment(String id, String templateId, [int orderIndex = 0]) =>
    TemplateSegment(
      id: id,
      templateId: templateId,
      orderIndex: orderIndex,
      segmentType: 'strength_sets',
      name: 'Main',
      createdAtMs: _atMs,
      updatedAtMs: _atMs,
    );

TemplateEffort _effort(
  String id,
  String segmentId, {
  required String effortKind,
  required String exerciseId,
  required int orderIndex,
}) => TemplateEffort(
  id: id,
  templateSegmentId: segmentId,
  orderIndex: orderIndex,
  effortKind: effortKind,
  exerciseId: exerciseId,
  createdAtMs: _atMs,
);

TemplateTarget _target(String id, String effortId, int setIndex) =>
    TemplateTarget(
      id: id,
      templateEffortId: effortId,
      metricId: 'metric-reps',
      setIndex: setIndex,
      targetInt: 8,
      createdAtMs: _atMs,
      updatedAtMs: _atMs,
    );

TrainingSession _session(
  WorkoutRepository repo,
  String id, {
  String? intent,
  String? routineTemplateId,
  String? modality,
  int? endedAtMs,
  String? title,
}) => TrainingSession(
  id: id,
  ownerUserId: LoggedEntryRows.ownerUserId,
  routineTemplateId: routineTemplateId,
  startedAtMs: _atMs,
  endedAtMs: endedAtMs,
  title: title,
  modality: modality,
  intent: intent,
  createdAtMs: _atMs,
  updatedAtMs: _atMs,
);

/// F-122: the 3 templates, the 9 sessions s-a..s-i and the planned rows
/// p-1, p-2, exactly per the plan's fixture table.
Future<void> _stageF122(WorkoutRepository repo) async {
  await repo.createTemplate(
    _template(
      'tpl-122-iso',
      'Evening Stretch',
      focusModality: 'isometric_stretching',
    ),
  );
  await repo.createTemplateSegment(_segment('tseg-122-iso', 'tpl-122-iso'));
  await repo.createTemplateEffort(
    _effort(
      'teff-122-hold',
      'tseg-122-iso',
      effortKind: 'drill',
      exerciseId: 'exercise-plank-hold',
      orderIndex: 0,
    ),
  );
  await repo.createTemplateEffort(
    _effort(
      'teff-122-squat',
      'tseg-122-iso',
      effortKind: 'set',
      exerciseId: 'exercise-barbell-squat',
      orderIndex: 1,
    ),
  );
  for (var setIndex = 0; setIndex < 3; setIndex++) {
    await repo.createTemplateTarget(
      _target('ttar-122-squat-$setIndex', 'teff-122-squat', setIndex),
    );
  }

  await repo.createTemplate(_template('tpl-122-mixed', 'Mixed Day'));
  await repo.createTemplateSegment(_segment('tseg-122-mixed', 'tpl-122-mixed'));
  await repo.createTemplateEffort(
    _effort(
      'teff-122-mixed-set',
      'tseg-122-mixed',
      effortKind: 'set',
      exerciseId: 'exercise-barbell-squat',
      orderIndex: 0,
    ),
  );

  await repo.createTemplate(
    _template('tpl-122-cardio', 'Easy Run', focusModality: 'cardio_endurance'),
  );
  await repo.createTemplateSegment(
    _segment('tseg-122-cardio', 'tpl-122-cardio'),
  );
  await repo.createTemplateEffort(
    _effort(
      'teff-122-run',
      'tseg-122-cardio',
      effortKind: 'timed',
      exerciseId: 'exercise-easy-run',
      orderIndex: 0,
    ),
  );

  await repo.createSession(
    _session(
      repo,
      's-a',
      intent: 'routine',
      routineTemplateId: 'tpl-122-iso',
      endedAtMs: _atMs + 3600000,
      title: 'Evening Stretch',
    ),
  );
  await repo.createSession(
    _session(
      repo,
      's-b',
      intent: 'routine',
      routineTemplateId: 'tpl-122-mixed',
      endedAtMs: _atMs + 2700000,
      title: 'Mixed Day',
    ),
  );
  await repo.createSession(
    _session(
      repo,
      's-c',
      intent: 'routine',
      routineTemplateId: 'tpl-122-deleted',
      endedAtMs: _atMs + 2700000,
    ),
  );
  await repo.createSession(
    _session(
      repo,
      's-d',
      intent: 'routine',
      routineTemplateId: 'tpl-122-iso',
      modality: 'resistance_lifting',
      endedAtMs: _atMs + 2700000,
      title: 'Evening Stretch',
    ),
  );
  await repo.createSession(_session(repo, 's-e', endedAtMs: _atMs + 2700000));
  await repo.createSession(
    _session(
      repo,
      's-f',
      intent: 'routine',
      routineTemplateId: 'tpl-122-iso',
      title: 'Evening Stretch',
    ),
  );
  await repo.createSession(
    _session(
      repo,
      's-g',
      routineTemplateId: 'tpl-122-iso',
      endedAtMs: _atMs + 2700000,
      title: 'Evening Stretch',
    ),
  );
  await repo.createSession(
    _session(repo, 's-h', intent: 'routine', endedAtMs: _atMs + 2700000),
  );
  await repo.createSession(
    _session(
      repo,
      's-i',
      intent: 'routine',
      routineTemplateId: 'tpl-122-cardio',
      endedAtMs: _atMs + 2700000,
      title: 'Easy Run',
    ),
  );

  await repo.createPlannedSession(
    PlannedSession(
      id: 'p-1',
      ownerUserId: LoggedEntryRows.ownerUserId,
      scheduledDateMs: _atMs + 86400000,
      routineTemplateId: 'tpl-122-iso',
      createdAtMs: _atMs,
      updatedAtMs: _atMs,
    ),
  );
  await repo.createPlannedSession(
    PlannedSession(
      id: 'p-2',
      ownerUserId: LoggedEntryRows.ownerUserId,
      scheduledDateMs: _atMs,
      routineTemplateId: 'tpl-122-iso',
      isCompleted: true,
      linkedSessionId: 's-a',
      createdAtMs: _atMs,
      updatedAtMs: _atMs,
    ),
  );
}

/// Every session of [repo], keyed by id, as the row's map.
Future<Map<String, Map<String, dynamic>>> _sessionMaps(
  WorkoutRepository repo,
) async => {
  for (final session in await repo.getAllSessions())
    session.id: session.toMap(),
};

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — back-fill routine session modality', () {
      late WorkoutRepository repo;

      setUp(() async => repo = await harness.open());
      tearDown(() async => await harness.close());

      test(
        'S-12210 back-fill selection on the full fixture, planned untouched',
        () async {
          await _stageF122(repo);
          await repo.setDataVersion(17);
          final before = await _sessionMaps(repo);
          expect(before.keys, containsAll(['s-a', 's-f', 's-h']));
          final plannedBefore = (await repo.getPlannedSessionsByTemplateId(
            'tpl-122-iso',
          )).map((row) => row.toMap()).toList();

          await _runStep(repo);

          final after = await _sessionMaps(repo);
          // Exactly the 3 rows the table names changed.
          final changed = [
            for (final id in before.keys)
              if (!mapEquals(before[id], after[id])) id,
          ];
          expect(changed.toSet(), {
            's-a',
            's-f',
            's-i',
          }, reason: 'exactly s-a, s-f, s-i changed');
          // And each wrote only 'modality'.
          const expectedModality = {
            's-a': 'isometric_stretching',
            's-f': 'isometric_stretching',
            's-i': 'cardio_endurance',
          };
          for (final id in changed) {
            final expected = {...before[id]!}
              ..removeWhere((key, _) => key == 'modality');
            final written = {...after[id]!}
              ..removeWhere((key, _) => key == 'modality');
            expect(written, expected, reason: 'only "modality" differs on $id');
            expect(
              after[id]!['modality'],
              expectedModality[id],
              reason: '$id took the template Focus verbatim',
            );
          }
          // All 6 unchanged rows keep their maps, and their modality.
          const expectedStays = {
            's-b': null,
            's-c': null,
            's-d': 'resistance_lifting',
            's-e': null,
            's-g': null,
            's-h': null,
          };
          for (final entry in expectedStays.entries) {
            expect(after[entry.key]!, before[entry.key]!);
            expect(after[entry.key]!['modality'], entry.value);
          }

          // Both planned rows are byte-identical after.
          expect(
            (await repo.getPlannedSessionsByTemplateId(
              'tpl-122-iso',
            )).map((row) => row.toMap()).toList(),
            plannedBefore,
          );
        },
      );

      test('S-12207 the calendar breakdown follows the back-fill', () async {
        // F-122 rows s-a, s-b only, both on day D; version staged at 17.
        await repo.createTemplate(
          _template(
            'tpl-122-iso',
            'Evening Stretch',
            focusModality: 'isometric_stretching',
          ),
        );
        await repo.createTemplate(_template('tpl-122-mixed', 'Mixed Day'));
        await repo.createSession(
          _session(
            repo,
            's-a',
            intent: 'routine',
            routineTemplateId: 'tpl-122-iso',
            endedAtMs: _atMs + 3600000,
            title: 'Evening Stretch',
          ),
        );
        await repo.createSession(
          _session(
            repo,
            's-b',
            intent: 'routine',
            routineTemplateId: 'tpl-122-mixed',
            endedAtMs: _atMs + 2700000,
            title: 'Mixed Day',
          ),
        );
        await repo.setDataVersion(17);

        await _runStep(repo);

        final calendarState = CalendarState(repo, now: () => _dayD);
        await calendarState.init();
        expect(
          calendarState.modalityBreakdown,
          {'isometric_stretching': 1, null: 1},
          reason: 's-a stamped from the Focus, s-b (no-focus routine) null',
        );
      });

      test(
        'S-12210 a routine whose Focus is an empty string stamps nothing',
        () async {
          await repo.createTemplate(
            _template('tpl-122-empty', 'Blank Focus', focusModality: ''),
          );
          await repo.createSession(
            _session(
              repo,
              's-empty',
              intent: 'routine',
              routineTemplateId: 'tpl-122-empty',
              endedAtMs: _atMs + 2700000,
            ),
          );
          final before = (await repo.getSession('s-empty'))!.toMap();

          await _runStep(repo);

          expect(
            (await repo.getSession('s-empty'))!.toMap(),
            before,
            reason:
                'D-12206: an empty Focus is no Focus, so it is never copied',
          );
        },
      );

      test('S-12211 a deleted routine never throws', () async {
        await repo.createSession(
          _session(
            repo,
            's-c',
            intent: 'routine',
            routineTemplateId: 'tpl-122-deleted',
            endedAtMs: _atMs + 2700000,
          ),
        );
        final before = (await repo.getSession('s-c'))!.toMap();

        await _runStep(repo);

        expect(
          (await repo.getSession('s-c'))!.toMap(),
          before,
          reason: 'the missing template is skipped silently',
        );
      });

      test(
        'S-12216 a focus edit after the back-fill leaves stamped rows',
        () async {
          await _stageF122(repo);
          await _runStep(repo);

          final template = (await repo.getTemplateById('tpl-122-iso'))!;
          await repo.updateTemplate(
            template.copyWith(focusModality: 'cardio_endurance'),
          );

          await _runStep(repo);

          expect(
            (await repo.getSession('s-a'))!.modality,
            'isometric_stretching',
            reason: 'a session modality is never rewritten by a routine edit',
          );
          expect(
            (await repo.getSession('s-f'))!.modality,
            'isometric_stretching',
          );
        },
      );

      test('S-12214 the pinned sequence ends at the back-fill step', () async {
        expect(currentDataVersion, 18);
        final steps = _steps(repo);
        final sequence = [
          for (final step in steps) '${step.targetVersion}:${step.name}',
        ];
        expect(
          sequence.last,
          '18:$_stepName',
          reason: 'the back-fill is appended as the last step',
        );
        expect(
          sequence,
          contains('17:retireOrphanTemplateRows'),
          reason: 'step 17 is still present',
        );
      });

      test('S-12215 a fresh install runs the step over nothing', () async {
        expect(currentDataVersion, 18);
        expect(await repo.getDataVersion(), currentDataVersion);
        final before = await _sessionMaps(repo);
        expect(
          before.values.every((row) => row['intent'] != 'routine'),
          isTrue,
          reason: 'the seed holds no routine session',
        );

        await _runStep(repo);

        expect(await _sessionMaps(repo), before);
      });
    });
  }

  test('S-12212 the counting store records 3 writes, then 0', () async {
    final repo = _CountingUpdateRepo();
    await repo.initialize();
    await _stageF122(repo);

    await _runStep(repo);

    expect(repo.updated.toSet(), {'s-a', 's-f', 's-i'});
    expect(repo.updated, hasLength(3));

    repo.updated.clear();
    await _runStep(repo);

    expect(repo.updated, isEmpty, reason: 'nothing is left to stamp');
  });

  test('S-12213 an interrupted back-fill retries and completes', () async {
    final repo = _FailingUpdateRepo();
    await repo.initialize();
    await _stageF122(repo);
    await repo.setDataVersion(17);

    await expectLater(
      DataMigrationService(
        repository: repo,
        targetVersion: currentDataVersion,
        steps: _steps(repo),
      ).run(),
      throwsA(isA<StateError>()),
    );
    expect(await repo.getDataVersion(), 17);
    expect(repo.written, hasLength(1));
    final firstWritten = repo.written.single;
    expect(
      [
        for (final id in const {'s-a', 's-f', 's-i'})
          (await repo.getSession(id))!.modality,
      ].whereType<String>().toSet(),
      hasLength(1),
      reason: 'exactly one of {s-a, s-f, s-i} stamped',
    );

    repo.failing = false;
    await DataMigrationService(
      repository: repo,
      targetVersion: currentDataVersion,
      steps: _steps(repo),
    ).run();

    expect(await repo.getDataVersion(), currentDataVersion);
    expect((await repo.getSession('s-a'))!.modality, 'isometric_stretching');
    expect((await repo.getSession('s-f'))!.modality, 'isometric_stretching');
    expect((await repo.getSession('s-i'))!.modality, 'cardio_endurance');
    expect(
      repo.written.where((id) => id == firstWritten),
      hasLength(1),
      reason: 'the row stamped first is written exactly once in total',
    );
  });

  test('S-12214 Mock and Hive expose identical step sequences', () async {
    final sequences = <String, List<String>>{};
    for (final factory in harnessFactories) {
      final harness = factory();
      final repo = await harness.open();
      try {
        final steps = _steps(repo);
        sequences[harness.name] = [
          for (final step in steps) '${step.targetVersion}:${step.name}',
        ];
      } finally {
        await harness.close();
      }
    }
    expect(sequences['Mock'], sequences['Hive']);
    expect(
      sequences['Mock']!.last,
      '18:$_stepName',
      reason: 'both lists end at the appended steps',
    );
  });

  test(
    'S-12214 a Hive restart over a staged store runs the new step',
    () async {
      final harness = HiveRepositoryHarness();
      final repo = await harness.open();
      try {
        await _stageF122(repo);
        await repo.setDataVersion(17);

        final reopened = await harness.restart();

        expect(await reopened.getDataVersion(), currentDataVersion);
        expect(
          (await reopened.getSession('s-a'))!.modality,
          'isometric_stretching',
          reason: 'the back-fill ran at restart and persisted',
        );
      } finally {
        await harness.close();
      }
    },
  );
}
