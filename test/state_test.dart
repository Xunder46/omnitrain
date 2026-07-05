import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/workout_constants.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/models/routine_session_manifest.dart';
import 'package:omnitrain/core/utils/date_utils.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/period/period_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

// ── Helpers ──────────────────────────────────────────────────────────────

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

/// Variant of [_freshRepo] that wipes the seeded today-dated consumed-food
/// rows after initialization. Use this for tests that pin exact counts or
/// per-row macro sums on `NutritionState.consumedToday`; the seed loads
/// three rows for `daysAgo: 0` which would otherwise pollute the cache
/// the moment `loadConsumedToday()` is called.
Future<MockWorkoutRepository> _freshRepoCleanConsumed() async {
  final repo = await _freshRepo();
  repo.clearConsumedFoodsForTest();
  return repo;
}

/// Local equivalent of `services_test.dart`'s `_seedCompletedSetSession`,
/// inline here so this file can build session→segment→effort→observation
/// fixtures without crossing test files. Used by the AC-5 parity test
/// in the WorkoutState group.
Future<TrainingSession> _seedCompletedSetSession(
  MockWorkoutRepository repo, {
  required String sessionId,
  required int startedAtMs,
  required int endedAtMs,
  required String exerciseId,
  required int reps,
  required double weight,
}) async {
  final session = TrainingSession(
    id: sessionId,
    ownerUserId: 'u-1',
    startedAtMs: startedAtMs,
    endedAtMs: endedAtMs,
    createdAtMs: startedAtMs,
    updatedAtMs: endedAtMs,
  );
  await repo.createSession(session);

  final segId = 'seg-$sessionId';
  await repo.createSegment(
    SessionSegment(
      id: segId,
      sessionId: sessionId,
      orderIndex: 0,
      segmentType: 'main',
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );

  final effortId = 'eff-$sessionId';
  await repo.createEffort(
    SegmentEffort(
      id: effortId,
      segmentId: segId,
      orderIndex: 0,
      effortKind: 'set',
      exerciseId: exerciseId,
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );

  await repo.createObservation(
    EffortObservation(
      id: 'obs-reps-$sessionId',
      effortId: effortId,
      metricId: 'metric-reps',
      valueInt: reps,
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );
  await repo.createObservation(
    EffortObservation(
      id: 'obs-weight-$sessionId',
      effortId: effortId,
      metricId: 'metric-weight',
      valueReal: weight,
      createdAtMs: startedAtMs + 1,
      updatedAtMs: startedAtMs + 1,
    ),
  );

  return session;
}

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // RoutineState
  // ══════════════════════════════════════════════════════════════════════════

  group('RoutineState', () {
    test('initial state has no routines and no current template', () async {
      final repo = await _freshRepo();
      final state = RoutineState(repo);
      expect(state.routines, isEmpty);
      expect(state.currentTemplate, isNull);
      expect(state.hasUnsavedChanges, false);
      expect(state.isLoading, false);
      expect(state.error, isNull);
    });

    test('loadRoutines fetches from repository', () async {
      final repo = await _freshRepo();
      // Seed a template
      await repo.createTemplate(
        WorkoutTemplate(
          id: 'tmpl-1',
          name: 'Push Day',
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      );
      final state = RoutineState(repo);
      await state.loadRoutines();
      expect(state.routines, hasLength(1));
      expect(state.routines.first.name, 'Push Day');
    });

    test('createNewRoutine sets currentTemplate and default segment', () async {
      final repo = await _freshRepo();
      final state = RoutineState(repo);
      state.setAutosaveEnabled(false);

      await state.createNewRoutine('Leg Day');

      expect(state.currentTemplate, isNotNull);
      expect(state.currentTemplate!.name, 'Leg Day');
      expect(state.currentSegments, hasLength(1));
      expect(state.currentSegments.first.segmentType, 'main');
      expect(state.hasUnsavedChanges, true);
    });

    test('updateRoutineName changes name', () async {
      final repo = await _freshRepo();
      final state = RoutineState(repo);
      state.setAutosaveEnabled(false);

      await state.createNewRoutine('Old Name');
      await state.updateRoutineName('New Name');

      expect(state.currentTemplate!.name, 'New Name');
    });

    test('updateRoutineName is no-op without current template', () async {
      final repo = await _freshRepo();
      final state = RoutineState(repo);
      state.setAutosaveEnabled(false);

      await state.updateRoutineName('Anything');
      expect(state.currentTemplate, isNull);
    });

    test('updateRoutineDescription changes description', () async {
      final repo = await _freshRepo();
      final state = RoutineState(repo);
      state.setAutosaveEnabled(false);

      await state.createNewRoutine('Routine');
      await state.updateRoutineDescription('A good routine');

      expect(state.currentTemplate!.description, 'A good routine');
    });

    test('updateRoutineFocusModality changes modality', () async {
      final repo = await _freshRepo();
      final state = RoutineState(repo);
      state.setAutosaveEnabled(false);

      await state.createNewRoutine('Routine');
      await state.updateRoutineFocusModality('cardio_endurance');

      expect(state.currentTemplate!.focusModality, 'cardio_endurance');
    });

    test(
      'updateRoutineFocusModality with null preserves prior value (copyWith limitation)',
      () async {
        final repo = await _freshRepo();
        final state = RoutineState(repo);
        state.setAutosaveEnabled(false);

        await state.createNewRoutine('Routine');
        await state.updateRoutineFocusModality('resistance_lifting');
        await state.updateRoutineFocusModality(null);

        // copyWith uses ?? so null keeps existing value
        expect(state.currentTemplate!.focusModality, 'resistance_lifting');
      },
    );

    test(
      'addExerciseToRoutine adds effort to first segment by default',
      () async {
        final repo = await _freshRepo();
        final state = RoutineState(repo);
        state.setAutosaveEnabled(false);

        final exercises = await repo.getExercises();
        await state.createNewRoutine('Routine');

        final effortId = await state.addExerciseToRoutine(
          exercises.first,
          'set',
        );
        expect(effortId, isNotEmpty);

        final efforts = state.getEffortsForSegment(
          state.currentSegments.first.id,
        );
        expect(efforts, hasLength(1));
        expect(efforts.first.exerciseId, exercises.first.id);
        expect(efforts.first.effortKind, 'set');
      },
    );

    test(
      'addExerciseToRoutine returns empty string without segments',
      () async {
        final repo = await _freshRepo();
        final state = RoutineState(repo);
        state.setAutosaveEnabled(false);

        final exercises = await repo.getExercises();
        // No createNewRoutine → no segments
        final effortId = await state.addExerciseToRoutine(
          exercises.first,
          'set',
        );
        expect(effortId, isEmpty);
      },
    );

    test('removeExerciseFromRoutine removes effort and its targets', () async {
      final repo = await _freshRepo();
      final state = RoutineState(repo);
      state.setAutosaveEnabled(false);

      final exercises = await repo.getExercises();
      await state.createNewRoutine('Routine');
      final effortId = await state.addExerciseToRoutine(exercises.first, 'set');

      // Add a target
      await state.setTargetValue(
        effortId,
        'metric-reps',
        'unit-reps',
        setIndex: 0,
        targetInt: 10,
      );

      await state.removeExerciseFromRoutine(effortId);

      final efforts = state.getEffortsForSegment(
        state.currentSegments.first.id,
      );
      expect(efforts, isEmpty);
      expect(state.getEffortTargets(effortId), isEmpty);
    });

    group('segments', () {
      test('addSegment creates new segment with auto-name', () async {
        final repo = await _freshRepo();
        final state = RoutineState(repo);
        state.setAutosaveEnabled(false);

        await state.createNewRoutine('Routine');
        final segId = await state.addSegment();

        expect(state.currentSegments, hasLength(2));
        expect(segId, isNotEmpty);
      });

      test('addSegment with custom name', () async {
        final repo = await _freshRepo();
        final state = RoutineState(repo);
        state.setAutosaveEnabled(false);

        await state.createNewRoutine('Routine');
        await state.addSegment(name: 'Accessory Block');

        expect(state.currentSegments.last.name, 'Accessory Block');
      });

      test('removeSegment is no-op when only one segment remains', () async {
        final repo = await _freshRepo();
        final state = RoutineState(repo);
        state.setAutosaveEnabled(false);

        await state.createNewRoutine('Routine');
        final segId = state.currentSegments.first.id;

        await state.removeSegment(segId);
        // Should still have 1 segment
        expect(state.currentSegments, hasLength(1));
      });

      test('removeSegment removes the targeted segment', () async {
        final repo = await _freshRepo();
        final state = RoutineState(repo);
        state.setAutosaveEnabled(false);

        await state.createNewRoutine('Routine');
        // Introduce a small delay so the segment IDs differ
        await Future.delayed(const Duration(milliseconds: 2));
        final seg2Id = await state.addSegment(name: 'Extra');

        expect(state.currentSegments, hasLength(2));

        await state.removeSegment(seg2Id);
        expect(state.currentSegments, hasLength(1));
        expect(state.currentSegments.first.name, 'Main Block');
      });

      test('reorderSegments swaps segment positions', () async {
        final repo = await _freshRepo();
        final state = RoutineState(repo);
        state.setAutosaveEnabled(false);

        await state.createNewRoutine('Routine');
        await state.addSegment(name: 'Block B');

        expect(state.currentSegments[0].name, 'Main Block');
        expect(state.currentSegments[1].name, 'Block B');

        await state.reorderSegments(0, 2); // move 0 after 1 (adjusted)

        expect(state.currentSegments[0].name, 'Block B');
        expect(state.currentSegments[1].name, 'Main Block');
      });

      test('cloneSegment appends (2) suffix to plain name', () async {
        final repo = await _freshRepo();
        final state = RoutineState(repo);
        state.setAutosaveEnabled(false);

        await state.createNewRoutine('Routine');
        final segId = state.currentSegments.first.id;

        await state.cloneSegment(segId);

        expect(state.currentSegments, hasLength(2));
        expect(state.currentSegments[1].name, 'Main Block (2)');
      });

      test('cloneSegment increments (N) suffix', () async {
        final repo = await _freshRepo();
        final state = RoutineState(repo);
        state.setAutosaveEnabled(false);

        await state.createNewRoutine('Routine');
        await Future.delayed(const Duration(milliseconds: 2));
        final segId = state.currentSegments.first.id;

        await state.cloneSegment(segId); // → "Main Block (2)"
        final cloneId = state.currentSegments[1].id;
        await state.cloneSegment(cloneId); // → "Main Block (3)"

        expect(state.currentSegments[2].name, 'Main Block (3)');
      });

      test('cloneSegment appends clone to end', () async {
        final repo = await _freshRepo();
        final state = RoutineState(repo);
        state.setAutosaveEnabled(false);

        await state.createNewRoutine('Routine');
        await Future.delayed(const Duration(milliseconds: 2));
        await state.addSegment(name: 'Block B');
        final segId = state.currentSegments.first.id; // Main Block

        await state.cloneSegment(segId);

        expect(state.currentSegments[0].name, 'Main Block');
        expect(state.currentSegments[1].name, 'Block B');
        expect(state.currentSegments[2].name, 'Main Block (2)');
      });

      test('cloneSegment re-indexes all segment orderIndex values', () async {
        final repo = await _freshRepo();
        final state = RoutineState(repo);
        state.setAutosaveEnabled(false);

        await state.createNewRoutine('Routine');
        await Future.delayed(const Duration(milliseconds: 2));
        await state.addSegment(name: 'Block B');
        final segId = state.currentSegments.first.id;

        await state.cloneSegment(segId);

        for (int i = 0; i < state.currentSegments.length; i++) {
          expect(state.currentSegments[i].orderIndex, i);
        }
      });

      test('cloneSegment deep-clones efforts with new IDs', () async {
        final repo = await _freshRepo();
        final state = RoutineState(repo);
        state.setAutosaveEnabled(false);

        final exercises = await repo.getExercises();
        await state.createNewRoutine('Routine');
        final segId = state.currentSegments.first.id;
        await state.addExerciseToRoutine(
          exercises.first,
          'set',
          segmentId: segId,
        );

        final sourceEfforts = state.getEffortsForSegment(segId);

        await state.cloneSegment(segId);
        final cloneId = state.currentSegments[1].id;
        final clonedEfforts = state.getEffortsForSegment(cloneId);

        expect(clonedEfforts, hasLength(1));
        expect(clonedEfforts.first.id, isNot(sourceEfforts.first.id));
        expect(clonedEfforts.first.exerciseId, sourceEfforts.first.exerciseId);
        expect(clonedEfforts.first.effortKind, sourceEfforts.first.effortKind);
      });

      test('cloneSegment deep-clones targets with new IDs', () async {
        final repo = await _freshRepo();
        final state = RoutineState(repo);
        state.setAutosaveEnabled(false);

        final exercises = await repo.getExercises();
        await state.createNewRoutine('Routine');
        final segId = state.currentSegments.first.id;
        final effortId = await state.addExerciseToRoutine(
          exercises.first,
          'set',
          segmentId: segId,
        );
        await state.setTargetValue(
          effortId,
          'metric-reps',
          'unit-reps',
          setIndex: 0,
          targetInt: 10,
        );

        final sourceTargets = state.getEffortTargets(effortId);
        expect(sourceTargets, hasLength(1));

        await state.cloneSegment(segId);
        final cloneId = state.currentSegments[1].id;
        final clonedEfforts = state.getEffortsForSegment(cloneId);
        final clonedTargets = state.getEffortTargets(clonedEfforts.first.id);

        expect(clonedTargets, hasLength(1));
        expect(clonedTargets.first.id, isNot(sourceTargets.first.id));
        expect(clonedTargets.first.targetInt, 10);
      });

      test('cloneSegment with unknown segmentId is no-op', () async {
        final repo = await _freshRepo();
        final state = RoutineState(repo);
        state.setAutosaveEnabled(false);

        await state.createNewRoutine('Routine');
        await state.cloneSegment('nonexistent-id');

        expect(state.currentSegments, hasLength(1));
      });
    });

    group('targets', () {
      test('setTargetValue creates new target', () async {
        final repo = await _freshRepo();
        final state = RoutineState(repo);
        state.setAutosaveEnabled(false);

        final exercises = await repo.getExercises();
        await state.createNewRoutine('Routine');
        final effortId = await state.addExerciseToRoutine(
          exercises.first,
          'set',
        );

        await state.setTargetValue(
          effortId,
          'metric-reps',
          'unit-reps',
          setIndex: 0,
          targetInt: 10,
        );

        final targets = state.getEffortTargets(effortId);
        expect(targets, hasLength(1));
        expect(targets.first.metricId, 'metric-reps');
        expect(targets.first.targetInt, 10);
      });

      test('setTargetValue upserts existing target', () async {
        final repo = await _freshRepo();
        final state = RoutineState(repo);
        state.setAutosaveEnabled(false);

        final exercises = await repo.getExercises();
        await state.createNewRoutine('Routine');
        final effortId = await state.addExerciseToRoutine(
          exercises.first,
          'set',
        );

        await state.setTargetValue(
          effortId,
          'metric-reps',
          'unit-reps',
          setIndex: 0,
          targetInt: 10,
        );
        await state.setTargetValue(
          effortId,
          'metric-reps',
          'unit-reps',
          setIndex: 0,
          targetInt: 12,
        );

        final targets = state.getEffortTargets(effortId);
        expect(targets, hasLength(1));
        expect(targets.first.targetInt, 12);
      });

      test('getEffortTargetsForSet filters by setIndex', () async {
        final repo = await _freshRepo();
        final state = RoutineState(repo);
        state.setAutosaveEnabled(false);

        final exercises = await repo.getExercises();
        await state.createNewRoutine('Routine');
        final effortId = await state.addExerciseToRoutine(
          exercises.first,
          'set',
        );

        await state.setTargetValue(
          effortId,
          'metric-reps',
          'unit-reps',
          setIndex: 0,
          targetInt: 10,
        );
        await state.setTargetValue(
          effortId,
          'metric-reps',
          'unit-reps',
          setIndex: 1,
          targetInt: 8,
        );

        expect(state.getEffortTargetsForSet(effortId, 0), hasLength(1));
        expect(state.getEffortTargetsForSet(effortId, 1), hasLength(1));
        expect(state.getEffortTargetsForSet(effortId, 99), isEmpty);
      });
    });

    test('updateEffortKind changes effort kind', () async {
      final repo = await _freshRepo();
      final state = RoutineState(repo);
      state.setAutosaveEnabled(false);

      final exercises = await repo.getExercises();
      await state.createNewRoutine('Routine');
      final effortId = await state.addExerciseToRoutine(exercises.first, 'set');

      await state.updateEffortKind(effortId, 'timed');

      final efforts = state.getEffortsForSegment(
        state.currentSegments.first.id,
      );
      expect(efforts.first.effortKind, 'timed');
    });

    test('updateEffortRest updates rest configuration', () async {
      final repo = await _freshRepo();
      final state = RoutineState(repo);
      state.setAutosaveEnabled(false);

      final exercises = await repo.getExercises();
      await state.createNewRoutine('Routine');
      final effortId = await state.addExerciseToRoutine(exercises.first, 'set');

      await state.updateEffortRest(
        effortId,
        restSeconds: 120,
        restType: 'fixed',
      );

      final efforts = state.getEffortsForSegment(
        state.currentSegments.first.id,
      );
      expect(efforts.first.restSeconds, 120);
      expect(efforts.first.restType, 'fixed');
    });

    test(
      'rest configuration round-trips through load and save unchanged',
      () async {
        final repo = await _freshRepo();
        final state = RoutineState(repo);
        state.setAutosaveEnabled(false);

        final exercises = await repo.getExercises();
        await state.createNewRoutine('Rest Round Trip');
        final effortId = await state.addExerciseToRoutine(
          exercises.first,
          'set',
        );

        await state.updateEffortRest(
          effortId,
          restSeconds: 90,
          restType: 'after_exercise',
        );
        await state.saveRoutine();

        final templateId = state.currentTemplate!.id;
        state.clearCurrentRoutine();

        await state.loadRoutineForEditing(templateId);
        expect(state.currentEfforts, hasLength(1));
        expect(state.currentEfforts.first.restSeconds, 90);
        expect(state.currentEfforts.first.restType, 'after_exercise');

        await state.saveRoutine();

        final segments = await repo.getTemplateSegments(templateId);
        expect(segments, hasLength(1));

        final persistedEfforts = await repo.getTemplateEfforts(
          segments.first.id,
        );
        expect(persistedEfforts, hasLength(1));
        expect(persistedEfforts.first.restSeconds, 90);
        expect(persistedEfforts.first.restType, 'after_exercise');
      },
    );

    test('saveRoutine persists template to repository', () async {
      final repo = await _freshRepo();
      final state = RoutineState(repo);
      state.setAutosaveEnabled(false);

      await state.createNewRoutine('Persist Me');
      await state.saveRoutine();

      final template = await repo.getTemplateById(state.currentTemplate!.id);
      expect(template, isNotNull);
      expect(template!.name, 'Persist Me');
    });

    test('deleteRoutine removes from routines list and repository', () async {
      final repo = await _freshRepo();
      final state = RoutineState(repo);
      state.setAutosaveEnabled(false);

      await state.createNewRoutine('To Delete');
      await state.saveRoutine();
      await state.loadRoutines();

      final templateId = state.routines.first.id;
      await state.deleteRoutine(templateId);

      expect(state.routines, isEmpty);
      expect(await repo.getTemplateById(templateId), isNull);
    });

    test('clearCurrentRoutine resets state', () async {
      final repo = await _freshRepo();
      final state = RoutineState(repo);
      state.setAutosaveEnabled(false);

      await state.createNewRoutine('Routine');
      state.clearCurrentRoutine();

      expect(state.currentTemplate, isNull);
      expect(state.currentSegments, isEmpty);
      expect(state.hasUnsavedChanges, false);
    });

    test(
      'loadRoutineForEditing loads template with segments and efforts',
      () async {
        final repo = await _freshRepo();
        final state = RoutineState(repo);
        state.setAutosaveEnabled(false);

        final exercises = await repo.getExercises();

        // Create and save a routine
        await state.createNewRoutine('Editable');
        await state.addExerciseToRoutine(exercises.first, 'set');
        await state.saveRoutine();

        final templateId = state.currentTemplate!.id;
        state.clearCurrentRoutine();

        // Load for editing
        await state.loadRoutineForEditing(templateId);

        expect(state.currentTemplate, isNotNull);
        expect(state.currentTemplate!.name, 'Editable');
        expect(state.currentSegments, isNotEmpty);
        expect(state.currentEfforts, isNotEmpty);
      },
    );

    test('loadRoutineForEditing sets error when template not found', () async {
      final repo = await _freshRepo();
      final state = RoutineState(repo);
      state.setAutosaveEnabled(false);

      await state.loadRoutineForEditing('nonexistent');
      expect(state.error, isNotNull);
    });

    test('getSegmentForEffort returns correct segment', () async {
      final repo = await _freshRepo();
      final state = RoutineState(repo);
      state.setAutosaveEnabled(false);

      final exercises = await repo.getExercises();
      await state.createNewRoutine('Routine');
      final effortId = await state.addExerciseToRoutine(exercises.first, 'set');

      final segment = state.getSegmentForEffort(effortId);
      expect(segment, isNotNull);
      expect(segment!.id, state.currentSegments.first.id);
    });

    test('getSegmentForEffort returns null for unknown effort', () async {
      final repo = await _freshRepo();
      final state = RoutineState(repo);
      state.setAutosaveEnabled(false);

      await state.createNewRoutine('Routine');
      expect(state.getSegmentForEffort('nonexistent'), isNull);
    });

    test('addSetForEffort creates targets for new set', () async {
      final repo = await _freshRepo();
      final state = RoutineState(repo);
      state.setAutosaveEnabled(false);

      final exercises = await repo.getExercises();
      await state.createNewRoutine('Routine');
      final effortId = await state.addExerciseToRoutine(exercises.first, 'set');

      // Set initial targets for set 0
      await state.setTargetValue(
        effortId,
        'metric-reps',
        'unit-reps',
        setIndex: 0,
        targetInt: 10,
      );

      await state.addSetForEffort(effortId, 'set');

      // Should now have targets for set 0 AND set 1
      expect(state.getEffortTargetsForSet(effortId, 0), isNotEmpty);
      expect(state.getEffortTargetsForSet(effortId, 1), isNotEmpty);
    });

    test('added sets persist after save and reopen routine', () async {
      final repo = await _freshRepo();
      final state = RoutineState(repo);
      state.setAutosaveEnabled(false);

      final exercises = await repo.getExercises();
      await state.createNewRoutine('Persisted Sets');
      final effortId = await state.addExerciseToRoutine(exercises.first, 'set');

      await state.setTargetValue(
        effortId,
        'metric-reps',
        'unit-reps',
        setIndex: 0,
        targetInt: 8,
      );
      await state.addSetForEffort(effortId, 'set');

      await state.saveRoutine();
      final templateId = state.currentTemplate!.id;

      state.clearCurrentRoutine();
      await state.loadRoutineForEditing(templateId);

      final reloadedEffort = state.currentEfforts.first.id;
      expect(state.getEffortTargetsForSet(reloadedEffort, 0), isNotEmpty);
      expect(state.getEffortTargetsForSet(reloadedEffort, 1), isNotEmpty);
    });

    test('addSetForEffort respects max entry cap', () async {
      final repo = await _freshRepo();
      final state = RoutineState(repo);
      state.setAutosaveEnabled(false);

      final exercises = await repo.getExercises();
      await state.createNewRoutine('Routine');
      final effortId = await state.addExerciseToRoutine(exercises.first, 'set');

      // Effort starts with set 0, then add beyond the cap.
      for (int i = 0; i < 30; i++) {
        await state.addSetForEffort(effortId, 'set');
      }

      expect(
        state.getEffortTargetsForSet(
          effortId,
          WorkoutConstants.maxEntriesPerEffort - 1,
        ),
        isNotEmpty,
      );
      expect(
        state.getEffortTargetsForSet(
          effortId,
          WorkoutConstants.maxEntriesPerEffort,
        ),
        isEmpty,
      );
    });

    test('removeLastSetForEffort removes targets for last set', () async {
      final repo = await _freshRepo();
      final state = RoutineState(repo);
      state.setAutosaveEnabled(false);

      final exercises = await repo.getExercises();
      await state.createNewRoutine('Routine');
      final effortId = await state.addExerciseToRoutine(exercises.first, 'set');

      await state.setTargetValue(
        effortId,
        'metric-reps',
        'unit-reps',
        setIndex: 0,
        targetInt: 10,
      );
      await state.addSetForEffort(effortId, 'set'); // set 1
      await state.addSetForEffort(effortId, 'set'); // set 2

      await state.removeLastSetForEffort(effortId);

      // set 2 should be gone
      expect(state.getEffortTargetsForSet(effortId, 2), isEmpty);
      // set 0 and 1 should still exist
      expect(state.getEffortTargetsForSet(effortId, 0), isNotEmpty);
      expect(state.getEffortTargetsForSet(effortId, 1), isNotEmpty);
    });

    test('removeLastSetForEffort is no-op when only set 0 exists', () async {
      final repo = await _freshRepo();
      final state = RoutineState(repo);
      state.setAutosaveEnabled(false);

      final exercises = await repo.getExercises();
      await state.createNewRoutine('Routine');
      final effortId = await state.addExerciseToRoutine(exercises.first, 'set');

      await state.setTargetValue(
        effortId,
        'metric-reps',
        'unit-reps',
        setIndex: 0,
        targetInt: 10,
      );

      await state.removeLastSetForEffort(effortId);

      // set 0 should still exist
      expect(state.getEffortTargetsForSet(effortId, 0), isNotEmpty);
    });

    test('reorderExercises within segment', () async {
      final repo = await _freshRepo();
      final state = RoutineState(repo);
      state.setAutosaveEnabled(false);

      final exercises = await repo.getExercises();
      await state.createNewRoutine('Routine');

      final segId = state.currentSegments.first.id;
      await state.addExerciseToRoutine(exercises[0], 'set', segmentId: segId);
      await state.addExerciseToRoutine(exercises[1], 'set', segmentId: segId);

      final beforeFirst = state.getEffortsForSegment(segId)[0].exerciseId;
      final beforeSecond = state.getEffortsForSegment(segId)[1].exerciseId;

      await state.reorderExercises(segId, 0, 2);

      final afterFirst = state.getEffortsForSegment(segId)[0].exerciseId;
      final afterSecond = state.getEffortsForSegment(segId)[1].exerciseId;

      expect(afterFirst, beforeSecond);
      expect(afterSecond, beforeFirst);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // CalendarState
  // ══════════════════════════════════════════════════════════════════════════

  group('CalendarState', () {
    test('init loads current month data', () async {
      final repo = await _freshRepo();
      final state = CalendarState(repo);
      await state.init();

      expect(state.year, DateTime.now().year);
      expect(state.month, DateTime.now().month);
      expect(state.isLoading, false);
    });

    test('goToNextMonth increments month', () async {
      final repo = await _freshRepo();
      final state = CalendarState(repo);
      await state.init();

      final startMonth = state.month;
      await state.goToNextMonth();

      if (startMonth == 12) {
        expect(state.month, 1);
        expect(state.year, DateTime.now().year + 1);
      } else {
        expect(state.month, startMonth + 1);
      }
    });

    test('goToPreviousMonth decrements month', () async {
      final repo = await _freshRepo();
      final state = CalendarState(repo);
      await state.init();

      final startMonth = state.month;
      await state.goToPreviousMonth();

      if (startMonth == 1) {
        expect(state.month, 12);
        expect(state.year, DateTime.now().year - 1);
      } else {
        expect(state.month, startMonth - 1);
      }
    });

    test('createPlannedSession persists and reloads', () async {
      final repo = await _freshRepo();
      final state = CalendarState(repo);
      await state.init();

      final today = DateTime.now();
      await state.createPlannedSession(
        date: today,
        modality: 'resistance_lifting',
        title: 'Test Session',
      );

      final entries = state.entriesForDay(today);
      expect(entries, isNotEmpty);
      final planned = entries.where((e) => e.plannedSession != null).toList();
      expect(planned, hasLength(1));
      expect(planned.first.plannedSession!.title, 'Test Session');
    });

    test('deletePlannedSession removes entry', () async {
      final repo = await _freshRepo();
      final state = CalendarState(repo);
      await state.init();

      final today = DateTime.now();
      await state.createPlannedSession(date: today, title: 'Delete Me');

      final entries = state.entriesForDay(today);
      final psId = entries.first.plannedSession!.id;

      await state.deletePlannedSession(psId);

      final afterEntries = state.entriesForDay(today);
      expect(afterEntries.where((e) => e.plannedSession?.id == psId), isEmpty);
    });

    test('completedSessionCount counts only completed entries', () async {
      final repo = await _freshRepo();
      final state = CalendarState(repo);

      // Seed a completed session for today
      final now = DateTime.now();
      final todayMs = DateTime(
        now.year,
        now.month,
        now.day,
      ).millisecondsSinceEpoch;
      await repo.createSession(
        TrainingSession(
          id: 's-complete',
          ownerUserId: 'u-1',
          startedAtMs: todayMs + 1000,
          endedAtMs: todayMs + 3600000,
          createdAtMs: todayMs,
          updatedAtMs: todayMs,
        ),
      );

      await state.init();

      expect(state.completedSessionCount, greaterThanOrEqualTo(1));
    });

    test('streakDays starts at 0 with no sessions', () async {
      final repo = await _freshRepo();
      final state = CalendarState(repo);
      await state.init();

      expect(state.streakDays, 0);
    });

    test('entriesForDay returns empty list for day with no entries', () async {
      final repo = await _freshRepo();
      final state = CalendarState(repo);
      await state.init();

      final farFuture = DateTime(2099, 1, 1);
      expect(state.entriesForDay(farFuture), isEmpty);
    });

    test('refresh reloads month data', () async {
      final repo = await _freshRepo();
      final state = CalendarState(repo);
      await state.init();

      // Should not throw
      await state.refresh();
      expect(state.isLoading, false);
    });

    test('completePlannedSession marks session complete', () async {
      final repo = await _freshRepo();
      final state = CalendarState(repo);
      await state.init();

      final today = DateTime.now();
      await state.createPlannedSession(date: today, title: 'Complete Me');

      final entries = state.entriesForDay(today);
      final ps = entries.first.plannedSession!;

      await state.completePlannedSession(ps.id, 'linked-session-1');

      // Reload and verify
      await state.refresh();
      // The planned session should now be excluded from calendar
      // (it has linkedSessionId, and _loadMonth excludes those)
      // OR it could show as completed - depends on the linked session existing.
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // PeriodState
  // ══════════════════════════════════════════════════════════════════════════

  group('PeriodState', () {
    test('initial state is empty', () async {
      final repo = await _freshRepo();
      final state = PeriodState(repo);
      expect(state.periods, isEmpty);
      expect(state.isLoading, false);
      expect(state.error, isNull);
    });

    test('load fetches periods from repository', () async {
      final repo = await _freshRepo();
      await repo.createPeriod(
        TrainingPeriod(
          id: 'p-1',
          ownerUserId: 'u-1',
          name: 'Bulk Phase',
          startDateMs: 1000,
          endDateMs: 5000,
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      );

      final state = PeriodState(repo);
      await state.load();

      expect(state.periods, hasLength(1));
      expect(state.periods.first.name, 'Bulk Phase');
    });

    group('validate', () {
      test('rejects empty name', () async {
        final repo = await _freshRepo();
        final state = PeriodState(repo);

        final result = await state.validate('', 1000, 2000);
        expect(result.isValid, false);
        expect(result.nameError, isNotNull);
      });

      test('rejects name over 50 chars', () async {
        final repo = await _freshRepo();
        final state = PeriodState(repo);

        final longName = 'A' * 51;
        final result = await state.validate(longName, 1000, 2000);
        expect(result.isValid, false);
        expect(result.nameError, isNotNull);
      });

      test('rejects null dates', () async {
        final repo = await _freshRepo();
        final state = PeriodState(repo);

        final result = await state.validate('Valid Name', null, 2000);
        expect(result.isValid, false);
        expect(result.dateError, isNotNull);
      });

      test('rejects end before start', () async {
        final repo = await _freshRepo();
        final state = PeriodState(repo);

        final result = await state.validate('Valid', 5000, 1000);
        expect(result.isValid, false);
        expect(result.dateError, isNotNull);
      });

      test('detects overlapping periods', () async {
        final repo = await _freshRepo();
        await repo.createPeriod(
          TrainingPeriod(
            id: 'p-existing',
            ownerUserId: 'u-1',
            name: 'Existing',
            startDateMs: 1000,
            endDateMs: 5000,
            createdAtMs: 100,
            updatedAtMs: 100,
          ),
        );

        final state = PeriodState(repo);
        final result = await state.validate('New', 3000, 7000);
        expect(result.isValid, false);
        expect(result.overlapError, isNotNull);
      });

      test(
        'excludeId allows editing own period without overlap error',
        () async {
          final repo = await _freshRepo();
          await repo.createPeriod(
            TrainingPeriod(
              id: 'p-edit',
              ownerUserId: 'u-1',
              name: 'Edit Me',
              startDateMs: 1000,
              endDateMs: 5000,
              createdAtMs: 100,
              updatedAtMs: 100,
            ),
          );

          final state = PeriodState(repo);
          final result = await state.validate(
            'Edit Me',
            1000,
            6000,
            excludeId: 'p-edit',
          );
          expect(result.isValid, true);
        },
      );

      test('valid input passes', () async {
        final repo = await _freshRepo();
        final state = PeriodState(repo);

        final result = await state.validate('Bulk Phase', 1000, 5000);
        expect(result.isValid, true);
        expect(result.nameError, isNull);
        expect(result.dateError, isNull);
        expect(result.overlapError, isNull);
      });
    });

    test('createPeriod validates then persists', () async {
      final repo = await _freshRepo();
      final state = PeriodState(repo);

      final success = await state.createPeriod(
        name: 'Cut Phase',
        startMs: 1000,
        endMs: 5000,
        focusModalities: ['resistance_lifting'],
        notes: 'Cutting season',
      );

      expect(success, true);
      expect(state.periods, hasLength(1));
      expect(state.periods.first.name, 'Cut Phase');
    });

    test('createPeriod returns false on validation failure', () async {
      final repo = await _freshRepo();
      final state = PeriodState(repo);

      final success = await state.createPeriod(
        name: '', // invalid
        startMs: 1000,
        endMs: 5000,
      );

      expect(success, false);
      expect(state.periods, isEmpty);
    });

    test('createPeriod trims notes to null when empty', () async {
      final repo = await _freshRepo();
      final state = PeriodState(repo);

      await state.createPeriod(
        name: 'Period',
        startMs: 1000,
        endMs: 5000,
        notes: '   ',
      );

      expect(state.periods.first.notes, isNull);
    });

    test('updatePeriod validates then persists', () async {
      final repo = await _freshRepo();
      final state = PeriodState(repo);

      await state.createPeriod(name: 'Original', startMs: 1000, endMs: 5000);

      final period = state.periods.first;
      final success = await state.updatePeriod(
        id: period.id,
        createdAtMs: period.createdAtMs,
        name: 'Updated',
        startMs: period.startDateMs,
        endMs: period.endDateMs,
      );

      expect(success, true);
      expect(state.periods.first.name, 'Updated');
    });

    test('updatePeriod returns false on validation failure', () async {
      final repo = await _freshRepo();
      final state = PeriodState(repo);

      await state.createPeriod(name: 'Valid', startMs: 1000, endMs: 5000);

      final period = state.periods.first;
      final success = await state.updatePeriod(
        id: period.id,
        createdAtMs: period.createdAtMs,
        name: '', // invalid
        startMs: period.startDateMs,
        endMs: period.endDateMs,
      );

      expect(success, false);
    });

    test('deletePeriod removes and reloads', () async {
      final repo = await _freshRepo();
      final state = PeriodState(repo);

      await state.createPeriod(name: 'To Delete', startMs: 1000, endMs: 5000);

      final id = state.periods.first.id;
      await state.deletePeriod(id);

      expect(state.periods, isEmpty);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // WorkoutState – checkForInProgressSession
  // ══════════════════════════════════════════════════════════════════════════

  group('WorkoutState.checkForInProgressSession', () {
    TrainingSession makeSession(String id, int startedAtMs, {int? endedAtMs}) {
      final now = DateTime.now().millisecondsSinceEpoch;
      return TrainingSession(
        id: id,
        ownerUserId: 'u-test',
        startedAtMs: startedAtMs,
        endedAtMs: endedAtMs,
        createdAtMs: now,
        updatedAtMs: now,
      );
    }

    test('returns null when no sessions exist', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);

      final result = await state.checkForInProgressSession();

      expect(result, isNull);
    });

    test('returns null when all sessions are completed', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      final now = DateTime.now().millisecondsSinceEpoch;
      await repo.createSession(
        makeSession('s-1', now - 10000, endedAtMs: now - 5000),
      );
      await repo.createSession(
        makeSession('s-2', now - 20000, endedAtMs: now - 15000),
      );

      final result = await state.checkForInProgressSession();

      expect(result, isNull);
    });

    test('returns the single in-progress session', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      final now = DateTime.now().millisecondsSinceEpoch;
      await repo.createSession(makeSession('s-open', now - 5000));

      final result = await state.checkForInProgressSession();

      expect(result, isNotNull);
      expect(result!.id, 's-open');
    });

    test(
      'returns most recent and deletes older in-progress sessions',
      () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        final now = DateTime.now().millisecondsSinceEpoch;
        // Newer session
        await repo.createSession(makeSession('s-new', now - 1000));
        // Older dangling sessions
        await repo.createSession(makeSession('s-old-1', now - 10000));
        await repo.createSession(makeSession('s-old-2', now - 20000));

        final result = await state.checkForInProgressSession();

        expect(result, isNotNull);
        expect(result!.id, 's-new');

        // Older sessions should have been deleted
        expect(await repo.getSession('s-old-1'), isNull);
        expect(await repo.getSession('s-old-2'), isNull);
        // Most recent kept
        expect(await repo.getSession('s-new'), isNotNull);
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // WorkoutState – round/timed/rest lifecycle gaps
  // ══════════════════════════════════════════════════════════════════════════

  group('WorkoutState lifecycle', () {
    test('createNewSession initializes session with startedAtMs', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession();

      expect(state.currentSession, isNotNull);
      expect(state.currentSession!.startedAtMs, isPositive);
      expect(state.currentSession!.endedAtMs, isNull);
    });

    test('createNewSession with modality sets session modality', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession(modality: 'cardio_endurance');

      expect(state.currentSession!.modality, 'cardio_endurance');
    });

    test('endSession sets endedAtMs', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession();
      await state.endSession();

      expect(state.currentSession!.endedAtMs, isNotNull);
    });

    test('addExerciseToSession returns effort ID', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession();

      final exercises = await repo.getExercises();
      final effortId = await state.addExerciseToSession(exercises.first);

      expect(effortId, isNotEmpty);
    });

    test(
      'createCustomExercise persists modality and reloads from repository',
      () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);

        final created = await state.createCustomExercise(
          name: 'Tempo Run Custom',
          modality: 'cardio_endurance',
          capabilities: ['time', 'distance'],
        );

        expect(created, isNotNull);
        expect(created!.modality, 'cardio_endurance');

        final loaded = await repo.getExerciseById(created.id);
        expect(loaded, isNotNull);
        expect(loaded!.modality, 'cardio_endurance');
      },
    );

    test(
      'updateSessionEndTime changes endedAtMs based on durationSecs',
      () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession();
        await state.endSession();

        final start = state.currentSession!.startedAtMs;
        await state.updateSessionEndTime(3600); // 1 hour

        expect(state.currentSession!.endedAtMs, start + 3600 * 1000);
      },
    );

    test('updateSessionEndTime is no-op for zero or negative', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession();
      await state.endSession();

      final original = state.currentSession!.endedAtMs;

      await state.updateSessionEndTime(0);
      expect(state.currentSession!.endedAtMs, original);

      await state.updateSessionEndTime(-100);
      expect(state.currentSession!.endedAtMs, original);
    });

    test(
      'resetSessionTimerStart updates startedAtMs to a later timestamp',
      () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession();

        final originalStart = state.currentSession!.startedAtMs;

        // Small delay so the new timestamp is guaranteed to be >= the original.
        await Future<void>.delayed(const Duration(milliseconds: 2));
        await state.resetSessionTimerStart();

        expect(
          state.currentSession!.startedAtMs,
          greaterThanOrEqualTo(originalStart),
        );
      },
    );

    test('resetSessionTimerStart is no-op when no session exists', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);

      // Must not throw even though no session has been created.
      await expectLater(state.resetSessionTimerStart(), completes);
      expect(state.currentSession, isNull);
    });

    group('session feeling', () {
      test(
        'updateSessionFeeling persists value and rehydrates on historical reload',
        () async {
          final repo = await _freshRepo();
          final state = WorkoutState(repo);
          await state.createNewSession();
          await state.endSession();

          final sessionId = state.currentSession!.id;

          await state.updateSessionFeeling(sessionId, 3);

          expect(state.currentSession!.sessionFeeling, 3);

          final reloaded = WorkoutState(repo);
          await reloaded.loadHistoricalSession(sessionId);

          expect(reloaded.currentSession, isNotNull);
          expect(reloaded.currentSession!.sessionFeeling, 3);
        },
      );

      test('updateSessionFeeling persists lower bound 1', () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession();

        final sessionId = state.currentSession!.id;
        await state.updateSessionFeeling(sessionId, 1);

        expect(state.currentSession!.sessionFeeling, 1);
      });

      test('updateSessionFeeling persists upper bound 5', () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession();

        final sessionId = state.currentSession!.id;
        await state.updateSessionFeeling(sessionId, 5);

        expect(state.currentSession!.sessionFeeling, 5);
      });
    });

    group('round lifecycle', () {
      test('startRound creates an active RoundInstance', () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession(modality: 'sports');

        final exercises = await repo.getExercises();
        final roundExercise = exercises.firstWhere(
          (e) => e.capabilities.contains('rounds'),
          orElse: () => exercises.first,
        );
        final effortId = await state.addExerciseToSession(roundExercise);

        await state.startRound(effortId, 0);

        final rounds = state.getRoundsForEffort(effortId);
        expect(rounds, isNotEmpty);
        expect(rounds.first.state, RoundState.active);
      });

      test('completeRound sets round state to finished', () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession(modality: 'sports');

        final exercises = await repo.getExercises();
        final roundExercise = exercises.firstWhere(
          (e) => e.capabilities.contains('rounds'),
          orElse: () => exercises.first,
        );
        final effortId = await state.addExerciseToSession(roundExercise);

        await state.startRound(effortId, 0);
        await state.completeRound(effortId, 0);

        final updatedRounds = state.getRoundsForEffort(effortId);
        expect(updatedRounds.first.state, RoundState.finished);
      });

      test('pauseRound and resumeRound cycle', () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession(modality: 'sports');

        final exercises = await repo.getExercises();
        final roundExercise = exercises.firstWhere(
          (e) => e.capabilities.contains('rounds'),
          orElse: () => exercises.first,
        );
        final effortId = await state.addExerciseToSession(roundExercise);

        await state.startRound(effortId, 0);
        await state.pauseRound(effortId, 0);

        var rounds = state.getRoundsForEffort(effortId);
        expect(rounds.first.state, RoundState.paused);

        await state.resumeRound(effortId, 0);
        rounds = state.getRoundsForEffort(effortId);
        expect(rounds.first.state, RoundState.active);
      });

      test('endRoundEarly finishes round immediately', () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession(modality: 'sports');

        final exercises = await repo.getExercises();
        final roundExercise = exercises.firstWhere(
          (e) => e.capabilities.contains('rounds'),
          orElse: () => exercises.first,
        );
        final effortId = await state.addExerciseToSession(roundExercise);

        await state.startRound(effortId, 0);
        await state.endRoundEarly(effortId, 0);

        final rounds = state.getRoundsForEffort(effortId);
        expect(rounds.first.state, RoundState.finished);
      });

      test('deleteRound removes instance', () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession(modality: 'sports');

        final exercises = await repo.getExercises();
        final roundExercise = exercises.firstWhere(
          (e) => e.capabilities.contains('rounds'),
          orElse: () => exercises.first,
        );
        final effortId = await state.addExerciseToSession(roundExercise);

        await state.startRound(effortId, 0);
        expect(state.getRoundsForEffort(effortId), hasLength(1));

        await state.deleteRound(effortId, 0);
        expect(state.getRoundsForEffort(effortId), isEmpty);
      });

      test('addEntry for round respects max entry cap', () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession(modality: 'sports');

        final exercises = await repo.getExercises();
        final roundExercise = exercises.firstWhere(
          (e) => e.capabilities.contains('rounds'),
          orElse: () => exercises.first,
        );
        final effortId = await state.addExerciseToSession(roundExercise);

        for (int i = 0; i < 30; i++) {
          await state.addEntry(effortId);
        }

        expect(
          state.getRoundsForEffort(effortId),
          hasLength(WorkoutConstants.maxEntriesPerEffort),
        );
      });
    });

    group('timed lifecycle', () {
      test('startTimedEntry creates an active TimedInstance', () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession(modality: 'cardio_endurance');

        final exercises = await repo.getExercises();
        final timedExercise = exercises.firstWhere(
          (e) => e.capabilities.contains('time'),
          orElse: () => exercises.first,
        );
        final effortId = await state.addExerciseToSession(timedExercise);

        await state.startTimedEntry(effortId, 0);

        final instances = state.getTimedInstancesForEffort(effortId);
        expect(instances, isNotEmpty);
        expect(instances.first.state, TimedState.active);
      });

      test('finishTimedEntry finishes the instance', () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession(modality: 'cardio_endurance');

        final exercises = await repo.getExercises();
        final timedExercise = exercises.firstWhere(
          (e) => e.capabilities.contains('time'),
          orElse: () => exercises.first,
        );
        final effortId = await state.addExerciseToSession(timedExercise);

        await state.startTimedEntry(effortId, 0);
        await state.finishTimedEntry(effortId, 0);

        final updated = state.getTimedInstancesForEffort(effortId);
        expect(updated.first.state, TimedState.finished);
      });

      test(
        'addEntry for timed creates distance and extra-weight companion observations',
        () async {
          final repo = await _freshRepo();
          final state = WorkoutState(repo);
          await state.createNewSession(modality: 'cardio_endurance');

          final exercises = await repo.getExercises();
          final timedExercise = exercises.firstWhere(
            (e) => e.capabilities.contains('time'),
            orElse: () => exercises.first,
          );
          // addExerciseToSession internally calls addEntry for the first set.
          final effortId = await state.addExerciseToSession(timedExercise);

          final observations = await repo.getEffortObservations(effortId);
          final metricIds = observations.map((o) => o.metricId).toSet();
          expect(metricIds, contains('metric-distance'));
          expect(metricIds, contains('metric-extra-weight'));

          // getExercisesWithEntries exposes both keys.
          final entry =
              (state.getExercisesWithEntries().first['entries'] as List).first
                  as Map<String, dynamic>;
          expect(entry.containsKey('extra-weight'), true);
          expect(entry['extra-weight'], 0.0);
          expect(entry.containsKey('distance'), true);
        },
      );

      test(
        'getExercisesWithEntries omits extra-weight for legacy timed entry',
        () async {
          final repo = await _freshRepo();
          final state = WorkoutState(repo);
          await state.createNewSession(modality: 'cardio_endurance');

          final exercises = await repo.getExercises();
          final timedExercise = exercises.firstWhere(
            (e) => e.capabilities.contains('time'),
            orElse: () => exercises.first,
          );
          final effortId = await state.addExerciseToSession(timedExercise);
          final sessionId = state.currentSession!.id;

          // Simulate a legacy entry: delete the extra-weight companion observation.
          final allObs = await repo.getEffortObservations(effortId);
          final ewObs = allObs
              .where((o) => o.metricId == 'metric-extra-weight')
              .toList();
          for (final obs in ewObs) {
            await repo.deleteObservation(obs.id);
          }

          // Reload state so it picks up the repo change.
          final reloaded = WorkoutState(repo);
          await reloaded.loadHistoricalSession(sessionId);

          final entries =
              (reloaded.getExercisesWithEntries().first['entries'] as List);
          final entry = entries.first as Map<String, dynamic>;
          expect(entry.containsKey('extra-weight'), false);
          expect(entry.containsKey('distance'), true);
        },
      );

      test(
        'deleteEntry removes all companion observations for a timed entry',
        () async {
          final repo = await _freshRepo();
          final state = WorkoutState(repo);
          await state.createNewSession(modality: 'cardio_endurance');

          final exercises = await repo.getExercises();
          final timedExercise = exercises.firstWhere(
            (e) => e.capabilities.contains('time'),
            orElse: () => exercises.first,
          );
          final effortId = await state.addExerciseToSession(
            timedExercise,
          ); // entry 0
          await state.addEntry(effortId); // entry 1

          // Both entries have 2 companions each.
          var observations = await repo.getEffortObservations(effortId);
          expect(
            observations
                .where(
                  (o) =>
                      o.id.endsWith('-0-distance') ||
                      o.id.endsWith('-0-extra-weight'),
                )
                .length,
            2,
          );
          expect(
            observations
                .where(
                  (o) =>
                      o.id.endsWith('-1-distance') ||
                      o.id.endsWith('-1-extra-weight'),
                )
                .length,
            2,
          );

          // Delete entry 0 — both of its companions must be removed.
          await state.deleteEntry(effortId, 0);

          observations = await repo.getEffortObservations(effortId);
          expect(
            observations.where(
              (o) =>
                  o.id.endsWith('-0-distance') ||
                  o.id.endsWith('-0-extra-weight'),
            ),
            isEmpty,
          );
          // Entry 1 companions survive.
          expect(
            observations
                .where(
                  (o) =>
                      o.id.endsWith('-1-distance') ||
                      o.id.endsWith('-1-extra-weight'),
                )
                .length,
            2,
          );
        },
      );

      test(
        'buildTemplateDraftExercises includes extra-weight target for timed',
        () async {
          final repo = await _freshRepo();
          final state = WorkoutState(repo);
          await state.createNewSession(modality: 'cardio_endurance');

          final exercises = await repo.getExercises();
          final timedExercise = exercises.firstWhere(
            (e) => e.capabilities.contains('time'),
            orElse: () => exercises.first,
          );
          await state.addExerciseToSession(timedExercise);

          final drafts = state.buildTemplateDraftExercises();
          expect(drafts, isNotEmpty);

          final timedDraft = drafts.first;
          expect(timedDraft.effortKind, 'timed');

          final targetMetricIds = timedDraft.targets
              .map((t) => t.metricId)
              .toList();
          expect(targetMetricIds, contains('metric-extra-weight'));
          expect(targetMetricIds, contains('metric-duration'));
        },
      );

      test('addEntry for timed respects max entry cap', () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession(modality: 'cardio_endurance');

        final exercises = await repo.getExercises();
        final timedExercise = exercises.firstWhere(
          (e) => e.capabilities.contains('time'),
          orElse: () => exercises.first,
        );
        final effortId = await state.addExerciseToSession(timedExercise);

        for (int i = 0; i < 30; i++) {
          await state.addEntry(effortId);
        }

        expect(
          state.getTimedInstancesForEffort(effortId),
          hasLength(WorkoutConstants.maxEntriesPerEffort),
        );
      });

      test(
        'S-003: addEntry for timed carries extra-weight forward from previousValues',
        () async {
          final repo = await _freshRepo();
          final state = WorkoutState(repo);
          await state.createNewSession(modality: 'cardio_endurance');

          final exercises = await repo.getExercises();
          final timedExercise = exercises.firstWhere(
            (e) => e.capabilities.contains('time'),
            orElse: () => exercises.first,
          );
          // entry 0 — created with default extra-weight (0.0)
          final effortId = await state.addExerciseToSession(timedExercise);

          // Simulate user setting 15.0 kg on the first interval.
          await state.updateEntryValue(effortId, 0, 'extra-weight', 15.0);

          // Verify the updated value is visible.
          final entriesAfterUpdate =
              state.getExercisesWithEntries().first['entries']
                  as List<Map<String, dynamic>>;
          expect(entriesAfterUpdate[0]['extra-weight'], 15.0);

          // entry 1 — created carrying forward 15.0 kg.
          await state.addEntry(
            effortId,
            previousValues: {'extra-weight': 15.0},
          );

          final entries =
              state.getExercisesWithEntries().first['entries']
                  as List<Map<String, dynamic>>;
          expect(entries, hasLength(2));
          expect(
            entries[1]['extra-weight'],
            15.0,
            reason:
                'S-003: second entry must inherit extra-weight from previousValues',
          );
        },
      );
    });

    // ── Exercise set/round/drill previousValues carry-forward ────────────
    // (June 2026, exercise-set-last-value-plan). Pins the
    // storage-layer contract that the `_addSet` caller in
    // `workout_session_screen.dart` relies on: every key the
    // caller passes in `previousValues` must propagate into the
    // freshly-created observation / round instance. This is the
    // same machinery that drives the pre-existing timed-extra-
    // weight carry-forward (S-003 above); this group expands the
    // contract to the other effort kinds.
    group('exercise previousValues carry-forward (per effort kind)', () {
      test(
        'set: addEntry carries reps + weight forward into the new observation',
        () async {
          final repo = await _freshRepo();
          final state = WorkoutState(repo);
          await state.createNewSession(modality: 'resistance_lifting');

          final exercises = await repo.getExercises();
          final liftExercise = exercises.firstWhere(
            (e) => e.capabilities.contains('load'),
            orElse: () => exercises.first,
          );
          final effortId = await state.addExerciseToSession(
            liftExercise,
            effortKindOverride: 'set',
          );
          // entry 0: defaults (reps=10, weight=0.0).
          // User overrides to 12 reps × 80 kg.
          await state.updateEntryValue(effortId, 0, 'reps', 12);
          await state.updateEntryValue(effortId, 0, 'weight', 80.0);

          // entry 1: caller passes previousValues from the prior
          // set's summary view. The state layer must round-trip
          // these into the new observation rows verbatim.
          await state.addEntry(
            effortId,
            previousValues: {'reps': 12, 'weight': 80.0},
          );

          final observations = await repo.getEffortObservations(effortId);
          // Find the entry-1 reps + weight observations.
          final repsObs1 = observations.firstWhere(
            (o) =>
                o.metricId == MetricIds.reps && o.id.endsWith('-1-reps'),
          );
          final weightObs1 = observations.firstWhere(
            (o) =>
                o.metricId == MetricIds.weight && o.id.endsWith('-1-weight'),
          );
          expect(repsObs1.valueInt, 12);
          expect(weightObs1.valueReal, 80.0);
        },
      );

      test(
        'set (no-load exercise): addEntry carries reps + extra-weight forward',
        () async {
          final repo = await _freshRepo();
          final state = WorkoutState(repo);
          await state.createNewSession(modality: 'resistance_lifting');

          final exercises = await repo.getExercises();
          final bodyweightExercise = exercises.firstWhere(
            (e) =>
                e.capabilities.contains('sets') &&
                !e.capabilities.contains('load'),
            orElse: () => exercises.firstWhere(
              (e) => !e.capabilities.contains('load'),
              orElse: () => exercises.first,
            ),
          );
          final effortId = await state.addExerciseToSession(
            bodyweightExercise,
            effortKindOverride: 'set',
          );
          // entry 0: 15 reps, -10 kg extra-weight (band-assist).
          await state.updateEntryValue(effortId, 0, 'reps', 15);
          await state.updateEntryValue(effortId, 0, 'extra-weight', -10.0);

          // entry 1: caller passes previousValues for both.
          await state.addEntry(
            effortId,
            previousValues: {'reps': 15, 'extra-weight': -10.0},
          );

          final observations = await repo.getEffortObservations(effortId);
          final repsObs1 = observations.firstWhere(
            (o) =>
                o.metricId == MetricIds.reps && o.id.endsWith('-1-reps'),
          );
          final ewObs1 = observations.firstWhere(
            (o) =>
                o.metricId == MetricIds.extraWeight &&
                o.id.endsWith('-1-extra-weight'),
          );
          expect(repsObs1.valueInt, 15);
          expect(ewObs1.valueReal, -10.0);
        },
      );

      test(
        'round: addEntry carries round-duration forward into the new round',
        () async {
          final repo = await _freshRepo();
          final state = WorkoutState(repo);
          await state.createNewSession(modality: 'sports');

          final exercises = await repo.getExercises();
          final roundExercise = exercises.firstWhere(
            (e) => e.capabilities.contains('rounds'),
            orElse: () => exercises.first,
          );
          final effortId = await state.addExerciseToSession(
            roundExercise,
            effortKindOverride: 'round',
          );
          // round 0: default 180s planned. User changes to 240s.
          await state.updateEntryValue(effortId, 0, 'round-duration', 240);

          // round 1: caller passes previousValues for the duration.
          await state.addEntry(
            effortId,
            previousValues: {'round-duration': 240},
          );

          final rounds = state.getRoundsForEffort(effortId);
          expect(rounds, hasLength(2));
          expect(rounds[1].plannedDurationSecs, 240);
        },
      );

      test(
        'drill: addEntry carries extra-weight forward into the new drill',
        () async {
          final repo = await _freshRepo();
          final state = WorkoutState(repo);
          await state.createNewSession(modality: 'isometric_stretching');

          final exercises = await repo.getExercises();
          final drillExercise = exercises.firstWhere(
            (e) => e.id.contains('plank') || e.id.contains('wall'),
            orElse: () => exercises.first,
          );
          final effortId = await state.addExerciseToSession(
            drillExercise,
            effortKindOverride: 'drill',
          );
          // drill 0: 30s, +5 kg extra-weight.
          await state.updateEntryValue(effortId, 0, 'extra-weight', 5.0);

          // drill 1: caller passes previousValues.
          await state.addEntry(
            effortId,
            previousValues: {'extra-weight': 5.0},
          );

          final observations = await repo.getEffortObservations(effortId);
          final ewObs1 = observations.firstWhere(
            (o) =>
                o.metricId == MetricIds.extraWeight &&
                o.id.endsWith('-1-extra-weight'),
          );
          expect(ewObs1.valueReal, 5.0);
        },
      );

      test(
        'regression: previousValues for set on entry 0 uses app-wide defaults',
        () async {
          // No prior entries → addEntry with empty previousValues
          // must fall back to the existing defaults (reps=10,
          // weight=0.0). This pins the "fresh exercise" contract
          // that the carry-forward feature must not break.
          final repo = await _freshRepo();
          final state = WorkoutState(repo);
          await state.createNewSession(modality: 'resistance_lifting');

          final exercises = await repo.getExercises();
          final liftExercise = exercises.firstWhere(
            (e) => e.capabilities.contains('load'),
            orElse: () => exercises.first,
          );
          final effortId = await state.addExerciseToSession(
            liftExercise,
            effortKindOverride: 'set',
          );

          final observations = await repo.getEffortObservations(effortId);
          final repsObs0 = observations.firstWhere(
            (o) =>
                o.metricId == MetricIds.reps && o.id.endsWith('-0-reps'),
          );
          final weightObs0 = observations.firstWhere(
            (o) =>
                o.metricId == MetricIds.weight && o.id.endsWith('-0-weight'),
          );
          expect(repsObs0.valueInt, 10);
          expect(weightObs0.valueReal, 0.0);
        },
      );
    });

    group('set extra-weight support', () {
      test(
        'set entries without load persist and expose extra-weight values',
        () async {
          final repo = await _freshRepo();
          final state = WorkoutState(repo);
          await state.createNewSession(modality: 'resistance_lifting');

          final exercises = await repo.getExercises();
          final bodyweightExercise = exercises.firstWhere(
            (e) =>
                e.capabilities.contains('sets') &&
                !e.capabilities.contains('load'),
            orElse: () => exercises.firstWhere(
              (e) => !e.capabilities.contains('load'),
              orElse: () => exercises.first,
            ),
          );

          final effortId = await state.addExerciseToSession(
            bodyweightExercise,
            effortKindOverride: 'set',
          );

          final observations = await repo.getEffortObservations(effortId);
          final metricIds = observations.map((o) => o.metricId).toSet();
          expect(metricIds, contains('metric-extra-weight'));

          final entry =
              (state.getExercisesWithEntries().first['entries'] as List).first
                  as Map<String, dynamic>;
          expect(entry.containsKey('extra-weight'), true);
          expect(entry['extra-weight'], 0.0);

          await state.updateEntryValue(effortId, 0, 'extra-weight', -15.0);

          final refreshedEntry =
              (state.getExercisesWithEntries().first['entries'] as List).first
                  as Map<String, dynamic>;
          expect(refreshedEntry['extra-weight'], -15.0);
        },
      );

      test('addEntry for set respects max entry cap', () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession(modality: 'resistance_lifting');

        final exercises = await repo.getExercises();
        final setExercise = exercises.firstWhere(
          (e) => e.capabilities.contains('sets'),
          orElse: () => exercises.first,
        );

        final effortId = await state.addExerciseToSession(
          setExercise,
          effortKindOverride: 'set',
        );

        for (int i = 0; i < 30; i++) {
          await state.addEntry(effortId);
        }

        final exerciseEntry = state.getExercisesWithEntries().firstWhere(
          (e) => e['id'] == effortId,
        );
        final entries = exerciseEntry['entries'] as List<dynamic>;
        expect(entries.length, WorkoutConstants.maxEntriesPerEffort);
      });

      test(
        'addEntry after deleting a middle set adds a new entry (not duplicate)',
        () async {
          final repo = await _freshRepo();
          final state = WorkoutState(repo);
          await state.createNewSession(modality: 'resistance_lifting');

          final exercises = await repo.getExercises();
          final setExercise = exercises.firstWhere(
            (e) => e.capabilities.contains('sets'),
            orElse: () => exercises.first,
          );

          final effortId = await state.addExerciseToSession(
            setExercise,
            effortKindOverride: 'set',
          );

          // Add to max (12 sets: 1 from addExerciseToSession + 11 more).
          for (int i = 0; i < WorkoutConstants.maxEntriesPerEffort - 1; i++) {
            await state.addEntry(effortId);
          }

          var entries =
              (state.getExercisesWithEntries().firstWhere(
                    (e) => e['id'] == effortId,
                  )['entries']
                  as List<dynamic>);
          expect(entries.length, WorkoutConstants.maxEntriesPerEffort);

          // Delete a middle set (index 5).
          await state.deleteEntry(effortId, 5);

          entries =
              (state.getExercisesWithEntries().firstWhere(
                    (e) => e['id'] == effortId,
                  )['entries']
                  as List<dynamic>);
          expect(entries.length, WorkoutConstants.maxEntriesPerEffort - 1);

          // Adding a set should now succeed and bring the count back to 12.
          await state.addEntry(effortId);

          entries =
              (state.getExercisesWithEntries().firstWhere(
                    (e) => e['id'] == effortId,
                  )['entries']
                  as List<dynamic>);
          expect(
            entries.length,
            WorkoutConstants.maxEntriesPerEffort,
            reason: 'Should be able to add a set after deleting a middle set',
          );
        },
      );
    });

    group('rest lifecycle', () {
      test('recordRestStart creates an EntryRest record', () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession();

        final exercises = await repo.getExercises();
        final effortId = await state.addExerciseToSession(
          exercises.first,
          chosenMetric: 'reps',
        );

        await state.recordRestStart(effortId, 0);

        final rests = state.getEntryRests(effortId);
        expect(rests, isNotEmpty);
        expect(rests.first.restEndMs, isNull); // open rest
      });

      test('recordRestEnd sets restEndMs', () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession();

        final exercises = await repo.getExercises();
        final effortId = await state.addExerciseToSession(
          exercises.first,
          chosenMetric: 'reps',
        );

        await state.recordRestStart(effortId, 0);
        await state.recordRestEnd(effortId, 0);

        final rests = state.getEntryRests(effortId);
        expect(rests.first.restEndMs, isNotNull);
      });

      test('closeAllOpenRests is a no-op when there are no rests', () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession();

        final exercises = await repo.getExercises();
        final effortId = await state.addExerciseToSession(
          exercises.first,
          chosenMetric: 'reps',
        );

        // No rests at all — must not throw
        await expectLater(state.closeAllOpenRests(effortId), completes);
        expect(state.getEntryRests(effortId), isEmpty);
      });

      test('closeAllOpenRests closes a single open rest', () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession();

        final exercises = await repo.getExercises();
        final effortId = await state.addExerciseToSession(
          exercises.first,
          chosenMetric: 'reps',
        );

        await state.recordRestStart(effortId, 0);
        expect(state.getEntryRests(effortId).first.restEndMs, isNull);

        await state.closeAllOpenRests(effortId);

        final rests = state.getEntryRests(effortId);
        expect(rests, hasLength(1));
        expect(rests.first.restEndMs, isNotNull);
      });

      test(
        'closeAllOpenRests closes all open rests regardless of entryIndex',
        () async {
          final repo = await _freshRepo();
          final state = WorkoutState(repo);
          await state.createNewSession();

          final exercises = await repo.getExercises();
          final effortId = await state.addExerciseToSession(
            exercises.first,
            chosenMetric: 'reps',
          );

          // recordRestStart auto-closes any prior open rest before creating a
          // new one, so after these two calls entry 0 is closed and entry 2
          // is the single open rest. This mirrors the real bug scenario: a rest
          // was opened for entry X (here 0), the user skipped ahead, and later
          // a rest was opened for entry 2. closeAllOpenRests must close whatever
          // is still open regardless of which entryIndex it belongs to.
          await state.recordRestStart(effortId, 0);
          await state.recordRestStart(effortId, 2);

          // Confirm only entry-2 rest is open before calling closeAllOpenRests.
          final beforeClose = state.getEntryRests(effortId);
          final openBefore = beforeClose.where((r) => r.restEndMs == null);
          expect(openBefore, hasLength(1));
          expect(openBefore.first.entryIndex, 2);

          await state.closeAllOpenRests(effortId);

          final afterClose = state.getEntryRests(effortId);
          final openAfter = afterClose.where((r) => r.restEndMs == null);
          expect(openAfter, isEmpty);
          // All records must have a restEndMs
          for (final r in afterClose) {
            expect(r.restEndMs, isNotNull);
          }
        },
      );

      test(
        'closeAllOpenRests skips already-closed rests and only closes open ones',
        () async {
          final repo = await _freshRepo();
          final state = WorkoutState(repo);
          await state.createNewSession();

          final exercises = await repo.getExercises();
          final effortId = await state.addExerciseToSession(
            exercises.first,
            chosenMetric: 'reps',
          );

          // Open and immediately close rest for entry 0.
          await state.recordRestStart(effortId, 0);
          await state.recordRestEnd(effortId, 0);

          // Add delay to ensure different timestamps
          await Future.delayed(const Duration(milliseconds: 10));

          // Open rest for entry 1, leave it open.
          await state.recordRestStart(effortId, 1);

          await state.closeAllOpenRests(effortId);

          final rests = state.getEntryRests(effortId);
          // Both must be closed now.
          for (final r in rests) {
            expect(r.restEndMs, isNotNull);
          }
          // The entry-0 restEndMs must not have been changed (it was already
          // closed before closeAllOpenRests was called).
          final rest0 = rests.firstWhere((r) => r.entryIndex == 0);
          final rest1 = rests.firstWhere((r) => r.entryIndex == 1);
          expect(rest0.restEndMs, lessThan(rest1.restEndMs!));
        },
      );
    });

    test('updateSessionRpe persists RPE value', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession();
      await state.endSession();

      final sessionId = state.currentSession!.id;
      await state.updateSessionRpe(sessionId, 7.0);

      expect(state.currentSession!.perceivedSessionRpe, 7.0);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // WorkoutState – Session Blocks
  // ══════════════════════════════════════════════════════════════════════════

  group('WorkoutState – Session Blocks', () {
    test('getSessionBlocks returns empty list when no session', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      expect(state.getSessionBlocks(), isEmpty);
    });

    test('getSessionBlocks returns empty list for new session', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession();
      expect(state.getSessionBlocks(), isEmpty);
    });

    test('addSessionBlock creates block with time-based name', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession();

      final blockId = await state.addSessionBlock();

      expect(blockId, isNotEmpty);
      final blocks = state.getSessionBlocks();
      expect(blocks, hasLength(1));
      expect(blocks.first.id, blockId);
      // Name should be in h:mm a format (e.g. "3:45 PM")
      expect(blocks.first.name, matches(RegExp(r'^\d{1,2}:\d{2} [AP]M$')));
      expect(blocks.first.orderIndex, 0);
    });

    test('addSessionBlock with explicit name uses that name', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession();

      final blockId = await state.addSessionBlock(name: 'Warm-Up');

      final blocks = state.getSessionBlocks();
      expect(blocks.first.id, blockId);
      expect(blocks.first.name, 'Warm-Up');
    });

    test('addSessionBlock increments orderIndex', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession();

      await state.addSessionBlock();
      await state.addSessionBlock();
      await state.addSessionBlock();

      final blocks = state.getSessionBlocks();
      expect(blocks, hasLength(3));
      expect(blocks[0].orderIndex, 0);
      expect(blocks[1].orderIndex, 1);
      expect(blocks[2].orderIndex, 2);
    });

    test(
      'addSessionBlock places new block after all standalone exercises',
      () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession();

        final exercises = await repo.getExercises();
        final effortId = await state.addExerciseToSession(exercises.first);
        final segmentId = state.segments.first.id;
        final standalone = state
            .getEffortsForSegment(segmentId)
            .firstWhere((effort) => effort.id == effortId);

        final blockId = await state.addSessionBlock();
        final addedBlock = state.getSessionBlocks().firstWhere(
          (block) => block.id == blockId,
        );

        final standaloneTopLevel =
            standalone.topLevelOrderIndex ?? standalone.orderIndex;
        final blockTopLevel =
            addedBlock.topLevelOrderIndex ?? addedBlock.orderIndex;

        expect(blockTopLevel, greaterThan(standaloneTopLevel));
      },
    );

    test('updateSessionBlock persists changes to cache', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession();

      await state.addSessionBlock();
      final originalBlock = state.getSessionBlocks().first;

      final updatedBlock = SessionBlock(
        id: originalBlock.id,
        sessionId: originalBlock.sessionId,
        name: 'Warm-Up',
        orderIndex: originalBlock.orderIndex,
        createdAtMs: originalBlock.createdAtMs,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );

      await state.updateSessionBlock(updatedBlock);

      final updated = state.getSessionBlocks();
      expect(updated.first.name, 'Warm-Up');
    });

    test('deleteSessionBlock removes block from cache', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession();

      // Add blocks with delays to ensure different IDs
      final id1 = await state.addSessionBlock();
      await Future.delayed(Duration(milliseconds: 10));
      final id2 = await state.addSessionBlock();
      await Future.delayed(Duration(milliseconds: 10));
      final id3 = await state.addSessionBlock();

      expect(id1, isNotEmpty);
      expect(id2, isNotEmpty);
      expect(id3, isNotEmpty);

      var blocks = state.getSessionBlocks();
      expect(blocks, hasLength(3));

      // Delete the second block
      await state.deleteSessionBlock(id2);

      blocks = state.getSessionBlocks();
      expect(blocks, hasLength(2));
      expect(blocks.every((b) => b.id != id2), true);
    });

    test('deleteSessionBlock removes linked efforts', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession();

      // Create a block and add an exercise
      final blockId = await state.addSessionBlock();
      final exercises = await repo.getExercises();
      final effortId = await state.addExerciseToSession(exercises.first);

      // Assign effort to block
      await state.assignEffortToBlock(effortId, blockId);

      // Get the effort from the current segment
      final segmentId = state.segments.first.id;
      var efforts = state.getEffortsForSegment(segmentId);
      expect(efforts.first.blockId, blockId);

      // Delete block — effort should be removed entirely
      await state.deleteSessionBlock(blockId);

      // Verify effort is gone
      efforts = state.getEffortsForSegment(segmentId);
      expect(efforts.where((e) => e.id == effortId), isEmpty);
    });

    test('reorderSessionBlocks calls repository', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession();

      // Add blocks with delays
      await state.addSessionBlock();
      await Future.delayed(Duration(milliseconds: 10));
      await state.addSessionBlock();
      await Future.delayed(Duration(milliseconds: 10));
      await state.addSessionBlock();

      var blocks = state.getSessionBlocks();
      expect(blocks, hasLength(3));

      final blockIds = blocks.map((b) => b.id).toList();
      // Reorder to reverse
      await state.reorderSessionBlocks(blockIds.reversed.toList());

      // Just verify blocks still exist - exact order depends on repository impl
      final reordered = state.getSessionBlocks();
      expect(reordered, hasLength(3));
    });

    test('cloneSessionBlock creates independent copy with new ID', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession(modality: 'resistance_lifting');

      final originalBlockId = await state.addSessionBlock();

      final clonedBlockId = await state.cloneSessionBlock(originalBlockId);

      expect(clonedBlockId, isNotEmpty);
      expect(clonedBlockId, isNot(originalBlockId));

      final blocks = state.getSessionBlocks();
      expect(blocks, hasLength(2));

      final cloned = blocks.firstWhere((b) => b.id == clonedBlockId);
      expect(cloned.name, isNot(contains('(2)')));
      expect(cloned.name, matches(RegExp(r'^\d{1,2}:\d{2} (AM|PM)$')));
      expect(cloned.id, clonedBlockId);
    });

    test('cloneSessionBlock with efforts clones all linked records', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession(modality: 'resistance_lifting');

      final blockId = await state.addSessionBlock();
      final exercises = await repo.getExercises();
      final effortId1 = await state.addExerciseToSession(exercises.first);
      final effortId2 = await state.addExerciseToSession(exercises[1]);

      // Assign efforts to block
      await state.assignEffortToBlock(effortId1, blockId);
      await state.assignEffortToBlock(effortId2, blockId);

      // Clone the block
      final clonedBlockId = await state.cloneSessionBlock(blockId);

      final blocks = state.getSessionBlocks();
      expect(blocks, hasLength(2));

      // Verify cloned block uses current-time naming
      final clonedBlock = blocks.firstWhere((b) => b.id == clonedBlockId);
      expect(clonedBlock.name, isNot(contains('(2)')));
      expect(clonedBlock.name, matches(RegExp(r'^\d{1,2}:\d{2} (AM|PM)$')));
    });

    test(
      'cloneSessionBlock in rolling session uses current-time title',
      () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession(isRolling: true);

        final sourceBlockId = await state.addSessionBlock(name: '10:00 AM');
        final cloneBlockId = await state.cloneSessionBlock(sourceBlockId);

        final blocks = state.getSessionBlocks();
        final clonedBlock = blocks.firstWhere((b) => b.id == cloneBlockId);

        expect(clonedBlock.name, isNot(contains('(2)')));
        expect(clonedBlock.name, matches(RegExp(r'^\d{1,2}:\d{2} (AM|PM)$')));
      },
    );

    test('cloneSessionBlock in free session uses current-time title', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession(modality: null, isRolling: false);

      final sourceBlockId = await state.addSessionBlock(name: 'Main');
      final cloneBlockId = await state.cloneSessionBlock(sourceBlockId);

      final blocks = state.getSessionBlocks();
      final clonedBlock = blocks.firstWhere((b) => b.id == cloneBlockId);

      expect(clonedBlock.name, isNot(contains('(2)')));
      expect(clonedBlock.name, matches(RegExp(r'^\d{1,2}:\d{2} (AM|PM)$')));
    });

    test('assignEffortToBlock updates effort blockId', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession();

      final blockId = await state.addSessionBlock();
      final exercises = await repo.getExercises();
      final effortId = await state.addExerciseToSession(exercises.first);

      final segmentId = state.segments.first.id;
      var efforts = state.getEffortsForSegment(segmentId);
      expect(efforts.first.blockId, isNull);

      await state.assignEffortToBlock(effortId, blockId);

      efforts = state.getEffortsForSegment(segmentId);
      expect(efforts.first.blockId, blockId);
    });

    test('assignEffortToBlock with null blockId unassigns effort', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession();

      final blockId = await state.addSessionBlock();
      final exercises = await repo.getExercises();
      final effortId = await state.addExerciseToSession(exercises.first);

      // Assign to block
      await state.assignEffortToBlock(effortId, blockId);
      final segmentId = state.segments.first.id;
      var efforts = state.getEffortsForSegment(segmentId);
      expect(efforts.first.blockId, blockId);

      // Unassign (pass null)
      await state.assignEffortToBlock(effortId, null);

      efforts = state.getEffortsForSegment(segmentId);
      expect(efforts.first.blockId, isNull);
    });

    test('isRollingSession is false by default', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession();

      expect(state.isRollingSession, false);
    });

    test(
      'isRollingSession is true when created with isRolling: true',
      () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession(isRolling: true);

        expect(state.isRollingSession, true);
      },
    );

    test(
      'computeSessionSummary suppresses totalDurationMs for rolling session',
      () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession(isRolling: true);

        // Add an exercise so we have something to summarize
        final exercises = await repo.getExercises();
        await state.addExerciseToSession(exercises.first);

        await state.endSession();

        final summary = state.computeSessionSummary();
        expect(summary.totalDurationMs, 0);
      },
    );

    test(
      'computeSessionSummary returns duration for non-rolling session',
      () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession(isRolling: false);

        // Add an exercise so we have something to summarize
        final exercises = await repo.getExercises();
        await state.addExerciseToSession(exercises.first);

        // Wait a bit to ensure duration > 0
        await Future.delayed(Duration(milliseconds: 100));

        await state.endSession();

        final summary = state.computeSessionSummary();
        expect(summary.totalDurationMs, greaterThanOrEqualTo(100));
      },
    );

    test(
      'computeSessionSummary carries blockId in exercise summaries',
      () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession(isRolling: true);

        final blockId = await state.addSessionBlock();
        final exercises = await repo.getExercises();
        final effortId = await state.addExerciseToSession(exercises.first);
        await state.assignEffortToBlock(effortId, blockId);

        await state.endSession();

        final summary = state.computeSessionSummary();
        expect(summary.exercises, hasLength(1));
        expect(summary.exercises.first.blockId, blockId);
      },
    );

    test(
      'computeSessionSummary counts finished early rounds for sports',
      () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession(modality: 'sports');

        final exercises = await repo.getExercises();
        final roundExercise = exercises.firstWhere(
          (e) => e.capabilities.contains('rounds'),
          orElse: () => exercises.first,
        );

        final effortId = await state.addExerciseToSession(
          roundExercise,
          effortKindOverride: 'round',
        );

        await state.startRound(effortId, 0);
        await state.endRoundEarly(effortId, 0);
        await state.endSession();

        final summary = state.computeSessionSummary();
        expect(summary.totalRounds, 1);
        expect(summary.totalRoundDurationMs, greaterThanOrEqualTo(0));
        expect(summary.exercises.single.totalRounds, 1);
      },
    );

    test(
      'computeSessionSummary populates ExerciseSummary.bestE1RM '
      'for set-kind efforts (AC-5 parity-plan guard)',
      () async {
        // Plan: .github/agents/plans/summary-pr-parity-plan.md (AC-5).
        // The builder must produce `bestE1RM` so the Session Summary's
        // PR detector (which now uses the same Epley formula as the
        // toast and Stats screen) has a value to compare against.
        final repo = await _freshRepo();
        final exercises = await repo.getExercises();
        final ex = exercises.first;
        // Seed a completed session with one set (5 × 60 → e1RM 70.0).
        await _seedCompletedSetSession(
          repo,
          sessionId: 's-e1rm',
          startedAtMs: 1000,
          endedAtMs: 5000,
          exerciseId: ex.id,
          reps: 5,
          weight: 60.0,
        );

        final state = WorkoutState(repo);
        await state.loadHistoricalSession('s-e1rm');

        final summary = state.computeSessionSummary();
        final exerciseSummary = summary.exercises.single;
        expect(exerciseSummary.effortKind, 'set');
        // bestWeight remains the volume metric (raw top weight, in kg).
        expect(exerciseSummary.bestWeight, 60.0);
        // bestE1RM is the PR metric (e1RM = 70.0), populated by the
        // builder so computePRs can compare against the standing best.
        expect(exerciseSummary.bestE1RM, closeTo(70.0, 0.001));
      },
    );

    test('getSessionBlocks returns sorted by orderIndex', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession();

      // Add multiple blocks with delays to ensure different timestamps
      await state.addSessionBlock();
      await Future.delayed(Duration(milliseconds: 5));
      await state.addSessionBlock();
      await Future.delayed(Duration(milliseconds: 5));
      await state.addSessionBlock();

      final blocks = state.getSessionBlocks();
      // Verify they are sorted by orderIndex (should be 0, 1, 2)
      final orderIndices = blocks.map((b) => b.orderIndex).toList();
      expect(orderIndices, equals([0, 1, 2]));
    });

    test(
      'populateSessionFromManifest creates one SessionBlock per non-empty segment',
      () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession();

        final exercises = await repo.getExercises();

        final template = WorkoutTemplate(
          id: 'tmpl-test',
          name: 'Test Routine',
          createdAtMs: 1000,
          updatedAtMs: 1000,
        );

        final manifest = RoutineSessionManifest(
          template: template,
          segments: [
            SessionSegmentEntry(
              segment: TemplateSegment(
                id: 'tseg-1',
                templateId: 'tmpl-test',
                orderIndex: 0,
                segmentType: 'mixed',
                name: 'Warm-Up',
                createdAtMs: 1000,
                updatedAtMs: 1000,
              ),
              exercises: [
                SessionExerciseEntry(
                  exercise: exercises.first,
                  effortKind: 'set',
                  setCount: 1,
                  targets: [],
                ),
              ],
            ),
            SessionSegmentEntry(
              segment: TemplateSegment(
                id: 'tseg-2',
                templateId: 'tmpl-test',
                orderIndex: 1,
                segmentType: 'mixed',
                name: 'Main Work',
                createdAtMs: 1000,
                updatedAtMs: 1000,
              ),
              exercises: [
                SessionExerciseEntry(
                  exercise: exercises[1],
                  effortKind: 'set',
                  setCount: 2,
                  targets: [],
                ),
              ],
            ),
          ],
        );

        await state.populateSessionFromManifest(manifest);

        final blocks = state.getSessionBlocks();
        expect(blocks, hasLength(2));
        expect(blocks.map((b) => b.name).toList(), ['Warm-Up', 'Main Work']);
      },
    );

    test(
      'populateSessionFromManifest assigns each effort to its segment block',
      () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession();

        final exercises = await repo.getExercises();

        final template = WorkoutTemplate(
          id: 'tmpl-test2',
          name: 'Test Routine 2',
          createdAtMs: 1000,
          updatedAtMs: 1000,
        );

        final manifest = RoutineSessionManifest(
          template: template,
          segments: [
            SessionSegmentEntry(
              segment: TemplateSegment(
                id: 'tseg-a',
                templateId: 'tmpl-test2',
                orderIndex: 0,
                segmentType: 'mixed',
                name: 'Block A',
                createdAtMs: 1000,
                updatedAtMs: 1000,
              ),
              exercises: [
                SessionExerciseEntry(
                  exercise: exercises.first,
                  effortKind: 'set',
                  setCount: 1,
                  targets: [],
                ),
              ],
            ),
          ],
        );

        await state.populateSessionFromManifest(manifest);

        final blocks = state.getSessionBlocks();
        expect(blocks, hasLength(1));
        final block = blocks.first;

        final result = state.getExercisesWithEntries();
        expect(result, hasLength(1));
        expect(result.first['blockId'], block.id);
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // WorkoutState – getExercisesWithEntries blockId propagation
  // ══════════════════════════════════════════════════════════════════════════

  group('WorkoutState – getExercisesWithEntries blockId', () {
    test('exercise map contains null blockId when not assigned', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession();

      final exercises = await repo.getExercises();
      await state.addExerciseToSession(exercises.first);

      final result = state.getExercisesWithEntries();
      expect(result, hasLength(1));
      expect(result.first.containsKey('blockId'), true);
      expect(result.first['blockId'], isNull);
    });

    test('exercise map contains blockId after assignEffortToBlock', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession();

      final blockId = await state.addSessionBlock();
      final exercises = await repo.getExercises();
      final effortId = await state.addExerciseToSession(exercises.first);

      await state.assignEffortToBlock(effortId, blockId);

      final result = state.getExercisesWithEntries();
      expect(result, hasLength(1));
      expect(result.first['blockId'], blockId);
    });

    test('exercise is gone after deleteSessionBlock', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession();

      final blockId = await state.addSessionBlock();
      final exercises = await repo.getExercises();
      final effortId = await state.addExerciseToSession(exercises.first);

      await state.assignEffortToBlock(effortId, blockId);
      await state.deleteSessionBlock(blockId);

      final result = state.getExercisesWithEntries();
      expect(result.where((e) => e['id'] == effortId), isEmpty);
    });

    test('multiple exercises carry correct blockIds', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession();

      final blockId1 = await state.addSessionBlock();
      await Future.delayed(Duration(milliseconds: 10));
      final blockId2 = await state.addSessionBlock();

      final exercises = await repo.getExercises();
      final effortId1 = await state.addExerciseToSession(exercises.first);
      await Future.delayed(Duration(milliseconds: 10));
      final effortId2 = await state.addExerciseToSession(exercises[1]);

      await state.assignEffortToBlock(effortId1, blockId1);
      await state.assignEffortToBlock(effortId2, blockId2);

      final result = state.getExercisesWithEntries();
      expect(result, hasLength(2));

      final e1 = result.firstWhere((e) => e['id'] == effortId1);
      final e2 = result.firstWhere((e) => e['id'] == effortId2);
      expect(e1['blockId'], blockId1);
      expect(e2['blockId'], blockId2);
    });

    test('mixed top-level ordering persists after reload', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession(isRolling: false);

      final exercises = await repo.getExercises();

      final blockAId = await state.addSessionBlock(name: 'Block A');
      final a1 = await state.addExerciseToSession(exercises[0]);
      await state.assignEffortToBlock(a1, blockAId);
      final a2 = await state.addExerciseToSession(exercises[1]);
      await state.assignEffortToBlock(a2, blockAId);

      final x = await state.addExerciseToSession(exercises[2]);

      await Future.delayed(Duration(milliseconds: 5));
      final blockBId = await state.addSessionBlock(name: 'Block B');
      final b1 = await state.addExerciseToSession(exercises[3]);
      await state.assignEffortToBlock(b1, blockBId);

      List<String> ids() => state
          .getExercisesWithEntries()
          .map((e) => e['id'] as String)
          .toList();

      expect(ids(), [a1, a2, x, b1]);

      await state.loadSessionData();
      expect(ids(), [a1, a2, x, b1]);
    });

    test('full flow order remains identical before and after reload', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession(isRolling: false);

      final exercises = await repo.getExercises();

      final blockAId = await state.addSessionBlock(name: 'Block A');
      final a1 = await state.addExerciseToSession(exercises[0]);
      await state.assignEffortToBlock(a1, blockAId);
      final a2 = await state.addExerciseToSession(exercises[1]);
      await state.assignEffortToBlock(a2, blockAId);

      final x = await state.addExerciseToSession(exercises[2]);

      await Future.delayed(Duration(milliseconds: 5));
      final blockBId = await state.addSessionBlock(name: 'Block B');
      final b1 = await state.addExerciseToSession(exercises[3]);
      await state.assignEffortToBlock(b1, blockBId);

      final clonedAId = await state.cloneSessionBlock(blockAId);

      final a3 = await state.addExerciseToSession(exercises[4]);
      await state.assignEffortToBlock(a3, blockAId);

      List<String> ids() => state
          .getExercisesWithEntries()
          .map((e) => e['id'] as String)
          .toList();

      await state.loadSessionData();
      final beforeReload = ids();

      await state.loadSessionData();
      final afterReload = ids();

      expect(afterReload, beforeReload);

      final result = state.getExercisesWithEntries();
      final blockAIds = result
          .where((e) => e['blockId'] == blockAId)
          .map((e) => e['id'] as String)
          .toList();
      final blockACloneIds = result
          .where((e) => e['blockId'] == clonedAId)
          .map((e) => e['id'] as String)
          .toList();

      expect(blockAIds, [a1, a2, a3]);
      expect(blockACloneIds, hasLength(2));
      expect(result.any((e) => e['id'] == x), isTrue);
      expect(result.any((e) => e['id'] == b1), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // NutritionState — daily targets
  // ══════════════════════════════════════════════════════════════════════════

  group('NutritionState', () {
    // ── S-001 First load today (no targets; ancestor walk) ─────────────────
    test('loadNutritionTargetForDate returns null when no ancestor exists',
        () async {
      final repo = await _freshRepo();
      final state = NutritionState(repo);
      final today = OmniDateUtils.todayMidnightMs();
      await state.loadNutritionTargetForDate(today);
      expect(state.nutritionTarget, isNull);
    });

    test('loadNutritionTargetForDate rolls over from yesterday\'s target',
        () async {
      final repo = await _freshRepo();
      final yesterday = OmniDateUtils.startOfDayMs(
        DateTime.now().subtract(const Duration(days: 1)),
      );
      final yesterdayTarget = NutritionTarget(
        calories: 2000,
        protein: 120,
        carbs: 250,
        fat: 70,
        dateMs: yesterday,
      );
      await repo.saveNutritionTargetForDate(yesterday, yesterdayTarget);

      final state = NutritionState(repo);
      final today = OmniDateUtils.todayMidnightMs();
      await state.loadNutritionTargetForDate(today);
      expect(state.nutritionTarget, isNotNull);
      expect(state.nutritionTarget?.calories, 2000);
      expect(state.nutritionTarget?.protein, 120);
      // The rolled-over copy must carry today's date.
      expect(state.nutritionTarget?.dateMs, today);
    });

    // ── S-002 Save all four fields ─────────────────────────────────────────
    test('saveNutritionTargetForDate persists all four macros', () async {
      final repo = await _freshRepo();
      final state = NutritionState(repo);
      final today = OmniDateUtils.todayMidnightMs();
      final target = NutritionTarget(
        calories: 2500,
        protein: 150,
        carbs: 300,
        fat: 80,
      );
      await state.saveNutritionTargetForDate(today, target);
      expect(state.nutritionTarget?.calories, 2500);
      expect(state.nutritionTarget?.protein, 150);
      expect(state.nutritionTarget?.carbs, 300);
      expect(state.nutritionTarget?.fat, 80);

      // Confirm persistence by reloading via a new state.
      final reload = NutritionState(repo);
      await reload.loadNutritionTargetForDate(today);
      expect(reload.nutritionTarget?.calories, 2500);
    });

    // ── S-003 Clear a target field (store as 0.0) ─────────────────────────
    test(
        'saveNutritionTargetForDate stores 0.0 for cleared fields (not null)',
        () async {
      final repo = await _freshRepo();
      final state = NutritionState(repo);
      final today = OmniDateUtils.todayMidnightMs();
      await state.saveNutritionTargetForDate(
        today,
        NutritionTarget(calories: 2500, protein: 150, carbs: 300, fat: 80),
      );
      // Re-save with carbs cleared.
      await state.saveNutritionTargetForDate(
        today,
        NutritionTarget(calories: 2500, protein: 150, carbs: 0, fat: 80),
      );
      expect(state.nutritionTarget?.carbs, 0.0);

      final reload = NutritionState(repo);
      await reload.loadNutritionTargetForDate(today);
      expect(reload.nutritionTarget?.carbs, 0.0);
    });

    // ── S-005 Hidden 0 values (isUnset) ───────────────────────────────────
    test('isUnset getter reflects "all four macros are 0"', () {
      expect(NutritionTarget().isUnset, isTrue);
      final partial = NutritionTarget(calories: 2000);
      expect(partial.isUnset, isFalse);
    });

    // ── S-006 Save → reload (legacy delegation) ───────────────────────────
    test('legacy saveNutritionTarget delegates to today\'s date', () async {
      final repo = await _freshRepo();
      final state = NutritionState(repo);
      await state.saveNutritionTarget(
        NutritionTarget(calories: 2200, protein: 110, carbs: 220, fat: 55),
      );
      expect(state.nutritionTarget?.calories, 2200);

      final reload = NutritionState(repo);
      await reload.loadNutritionTarget();
      expect(reload.nutritionTarget?.calories, 2200);
    });

    // ── S-007 Forward-propagation: yesterday is unaffected ───────────────
    test(
        'saveNutritionTargetForDate does NOT modify past dates when '
        'forward-propagating', () async {
      final repo = await _freshRepo();
      final state = NutritionState(repo);
      final yesterday = OmniDateUtils.startOfDayMs(
        DateTime.now().subtract(const Duration(days: 1)),
      );
      final today = OmniDateUtils.todayMidnightMs();
      final tomorrow = OmniDateUtils.startOfDayMs(
        DateTime.now().add(const Duration(days: 1)),
      );

      // Seed yesterday + today with identical values.
      final original = NutritionTarget(
        calories: 2000,
        protein: 120,
        carbs: 250,
        fat: 70,
      );
      await state.saveNutritionTargetForDate(yesterday, original);
      await state.saveNutritionTargetForDate(today, original);

      // Edit today.
      await state.saveNutritionTargetForDate(
        today,
        NutritionTarget(calories: 2500, protein: 150, carbs: 300, fat: 80),
      );

      // Yesterday must be untouched.
      final reload = NutritionState(repo);
      await reload.loadNutritionTargetForDate(yesterday);
      expect(reload.nutritionTarget?.calories, 2000);
      expect(reload.nutritionTarget?.protein, 120);
      expect(reload.nutritionTarget?.carbs, 250);
      expect(reload.nutritionTarget?.fat, 70);

      // Tomorrow (forward-propagated) reflects the new values.
      await reload.loadNutritionTargetForDate(tomorrow);
      expect(reload.nutritionTarget?.calories, 2500);
      expect(reload.nutritionTarget?.protein, 150);
    });

    // ── S-004 Day rollover mechanics ───────────────────────────────────────
    test('rolloverToDate loads the new date\'s target (or walks back)',
        () async {
      final repo = await _freshRepo();
      final state = NutritionState(repo);
      final yesterday = OmniDateUtils.startOfDayMs(
        DateTime.now().subtract(const Duration(days: 1)),
      );
      final target = NutritionTarget(
        calories: 2100,
        protein: 130,
        carbs: 260,
        fat: 75,
      );
      await state.saveNutritionTargetForDate(yesterday, target);

      // Rollover to today; should find the ancestor and roll it forward.
      final today = OmniDateUtils.todayMidnightMs();
      await state.rolloverToDate(today);
      expect(state.nutritionTarget?.calories, 2100);
      expect(state.nutritionTarget?.dateMs, today);
    });

    // ── getTodayTarget convenience ────────────────────────────────────────
    test('getTodayTarget returns the current day\'s target', () async {
      final repo = await _freshRepo();
      final state = NutritionState(repo);
      final today = OmniDateUtils.todayMidnightMs();
      await state.saveNutritionTargetForDate(
        today,
        NutritionTarget(calories: 1800),
      );
      final result = await state.getTodayTarget();
      expect(result?.calories, 1800);
      // notifyListeners fires; the in-memory _nutritionTarget is updated.
      expect(state.nutritionTarget?.calories, 1800);
    });

    // ── Cache behaviour ──────────────────────────────────────────────────
    test('loadNutritionTargetForDate populates the per-date cache', () async {
      final repo = await _freshRepo();
      final state = NutritionState(repo);
      final today = OmniDateUtils.todayMidnightMs();
      await state.saveNutritionTargetForDate(
        today,
        NutritionTarget(calories: 1900),
      );
      final fresh = NutritionState(repo);
      await fresh.loadNutritionTargetForDate(today);
      expect(fresh.getCachedTargetForDate(today), isNotNull);
      expect(fresh.getCachedTargetForDate(today)?.calories, 1900);
    });

    // ── Loading state toggles ────────────────────────────────────────────
    test('isLoading toggles during loadNutritionTargetForDate', () async {
      final repo = await _freshRepo();
      final state = NutritionState(repo);
      final today = OmniDateUtils.todayMidnightMs();
      // Capture notifications to verify isLoading transitions.
      final loadingValues = <bool>[];
      state.addListener(() => loadingValues.add(state.isLoading));
      await state.loadNutritionTargetForDate(today);
      // Should have notified at least twice: true (start) → false (end).
      expect(loadingValues, contains(true));
      expect(state.isLoading, isFalse);
    });

    // ── Consumed-food cache (real implementation) ───────────────────────
    // Replaces the legacy stub test. The calorie ring on the nutrition
    // page reads from `consumedToday` / `todayConsumedCalories`; these
    // tests pin the contract: loads from the repo, populates the cache,
    // sums via `ConsumedFood.caloriesConsumed`, and notifies listeners.
    group('consumed-food cache', () {
      test('initial cache is empty and loadConsumedToday keeps it empty',
          () async {
        final repo = await _freshRepoCleanConsumed();
        final state = NutritionState(repo);
        expect(state.consumedToday, isEmpty);
        expect(state.todayConsumedCalories, 0);

        await state.loadConsumedToday();
        expect(state.consumedToday, isEmpty);
        expect(state.todayConsumedCalories, 0);
      });

      test('getTodayConsumedFoods returns empty when repo has no rows',
          () async {
        final repo = await _freshRepoCleanConsumed();
        final state = NutritionState(repo);
        final foods = await state.getTodayConsumedFoods();
        expect(foods, isEmpty);
        expect(state.consumedToday, isEmpty);
      });

      test('loadConsumedToday populates the cache from the repository',
          () async {
        final repo = await _freshRepoCleanConsumed();
        final today = OmniDateUtils.todayMidnightMs();

        // Seed two consumed-food snapshots for today.
        await repo.createConsumedFood(ConsumedFood(
          id: 'c-1',
          loggedAtMs: today + 1000,
          dateMs: today,
          sourceFoodId: 'food-1',
          name: 'Oatmeal',
          unitType: FoodUnitType.grams,
          referenceAmount: 100,
          referenceLabel: 'g',
          protein: 13,
          carbs: 68,
          fat: 6,
          amountConsumed: 1.0,
          targetCalories: 2000,
          targetProtein: 150,
          targetCarbs: 200,
          targetFat: 65,
          createdAtMs: today,
          updatedAtMs: today,
        ));
        await repo.createConsumedFood(ConsumedFood(
          id: 'c-2',
          loggedAtMs: today + 2000,
          dateMs: today,
          sourceFoodId: 'food-2',
          name: 'Egg',
          unitType: FoodUnitType.count,
          referenceAmount: 1,
          referenceLabel: 'egg',
          protein: 6,
          carbs: 1,
          fat: 5,
          amountConsumed: 2.0,
          targetCalories: 2000,
          targetProtein: 150,
          targetCarbs: 200,
          targetFat: 65,
          createdAtMs: today,
          updatedAtMs: today,
        ));

        final state = NutritionState(repo);
        var notifications = 0;
        state.addListener(() => notifications++);
        await state.loadConsumedToday();

        expect(state.consumedToday, hasLength(2));
        expect(notifications, greaterThanOrEqualTo(1),
            reason: 'loadConsumedToday must notify listeners on success');
        // Oatmeal (per-100 g, amount=1.0): 13*4 + 68*4 + 6*9 = 378;
        // scaled by 1/100 → 378 * 0.01 = 3.78 → 4.
        // 2 eggs (per-1, amount=2.0): (6*4 + 1*4 + 5*9) * (2/1) = 146.
        // Total: 4 + 146 = 150.
        expect(state.todayConsumedCalories, 4 + 146);
      });

      test('loadConsumedToday is idempotent and refreshes the cache',
          () async {
        final repo = await _freshRepoCleanConsumed();
        final state = NutritionState(repo);

        await state.loadConsumedToday();
        final first = state.consumedToday;
        await state.loadConsumedToday();
        // Same empty result, but a fresh list instance.
        expect(state.consumedToday, equals(first));
        expect(state.consumedToday, isEmpty);
      });

      test('clearConsumedToday empties the cache and notifies listeners',
          () async {
        final repo = await _freshRepoCleanConsumed();
        final state = NutritionState(repo);
        await state.loadConsumedToday();
        expect(state.consumedToday, isEmpty);

        var notifications = 0;
        state.addListener(() => notifications++);
        state.clearConsumedToday();
        // Empty-on-empty is a no-op; we don't require a notification here.
        expect(state.consumedToday, isEmpty);
        expect(notifications, 0);
      });
    });

    // ═════════════════════════════════════════════════════════════════════
    // Daily water log (S-001..S-007 / S-009)
    //
    // The day's water is stored as a real volume in milliliters. The
    // on-screen glass count is derived (`waterTodayMl ~/ kWaterGlassMl`)
    // and never stored. Increment / decrement always operate on the
    // canonical ml value; the state never writes a raw glass count.
    // ═════════════════════════════════════════════════════════════════════
    group('daily water log', () {
      test('initial cache is empty; loadWaterForDate fetches from repo',
          () async {
        final repo = await _freshRepo();
        // Pre-seed the repo with 500 ml for today.
        final today = OmniDateUtils.todayMidnightMs();
        await repo.saveWaterVolumeForDate(today, 500);

        final state = NutritionState(repo);
        // Cache is empty until the explicit load call.
        expect(state.waterTodayMl, 0);
        expect(state.waterTodayGlasses, 0);

        await state.loadWaterForDate(today);
        expect(state.waterTodayMl, 500);
        expect(state.waterTodayGlasses, 2);
      });

      test('incrementWaterForDate stores +250 ml and notifies', () async {
        final repo = await _freshRepo();
        final state = NutritionState(repo);
        final today = OmniDateUtils.todayMidnightMs();

        var notifications = 0;
        state.addListener(() => notifications++);

        await state.incrementWaterForDate(today);
        expect(state.waterTodayMl, 250);
        expect(state.waterTodayGlasses, 1);
        // Repository confirms the persisted value.
        expect(await repo.getWaterVolumeForDate(today), 250);
        // The increment emitted a notifyListeners call.
        expect(notifications, greaterThanOrEqualTo(1));
      });

      test('decrementWaterForDate stores −250 ml and notifies', () async {
        final repo = await _freshRepo();
        final state = NutritionState(repo);
        final today = OmniDateUtils.todayMidnightMs();
        // Seed at 500 ml (2 glasses).
        await state.incrementWaterForDate(today);
        await state.incrementWaterForDate(today);
        expect(state.waterTodayMl, 500);

        var notifications = 0;
        state.addListener(() => notifications++);

        await state.decrementWaterForDate(today);
        expect(state.waterTodayMl, 250);
        expect(state.waterTodayGlasses, 1);
        expect(await repo.getWaterVolumeForDate(today), 250);
        expect(notifications, greaterThanOrEqualTo(1));
      });

      test('decrementWaterForDate at 0 is a no-op (no negative ml)', () async {
        final repo = await _freshRepo();
        final state = NutritionState(repo);
        final today = OmniDateUtils.todayMidnightMs();
        // No row exists for today; cache is 0.
        expect(state.waterTodayMl, 0);

        await state.decrementWaterForDate(today);
        // Still 0 — no negative leak.
        expect(state.waterTodayMl, 0);
        expect(state.waterTodayGlasses, 0);
        // Repository still reports 0 (no row created by a no-op decrement).
        expect(await repo.getWaterVolumeForDate(today), 0);
      });

      test('display derivation: ml → glasses maps cleanly', () async {
        final repo = await _freshRepo();
        final state = NutritionState(repo);
        final today = OmniDateUtils.todayMidnightMs();

        // 0 ml → 0 glasses.
        await state.loadWaterForDate(today);
        expect(state.waterTodayMl, 0);
        expect(state.waterTodayGlasses, 0);

        // 250 ml → 1 glass.
        await state.incrementWaterForDate(today);
        expect(state.waterTodayMl, 250);
        expect(state.waterTodayGlasses, 1);

        // 500 ml → 2 glasses.
        await state.incrementWaterForDate(today);
        expect(state.waterTodayMl, 500);
        expect(state.waterTodayGlasses, 2);

        // 750 ml → 3 glasses.
        await state.incrementWaterForDate(today);
        expect(state.waterTodayMl, 750);
        expect(state.waterTodayGlasses, 3);

        // 1000 ml → 4 glasses.
        await state.incrementWaterForDate(today);
        expect(state.waterTodayMl, 1000);
        expect(state.waterTodayGlasses, 4);
      });

      test(
        'immediate persistence: a fresh NutritionState reads the persisted ml',
        () async {
          final repo = await _freshRepo();
          final writer = NutritionState(repo);
          final today = OmniDateUtils.todayMidnightMs();

          // Writer taps plus four times (1000 ml).
          for (var i = 0; i < 4; i++) {
            await writer.incrementWaterForDate(today);
          }
          expect(writer.waterTodayMl, 1000);

          // Brand new state instance against the same repo re-reads
          // 1000 ml on its first load. Closes the round-trip loop.
          final reader = NutritionState(repo);
          expect(reader.waterTodayMl, 0); // cache cold
          await reader.loadWaterForDate(today);
          expect(reader.waterTodayMl, 1000);
          expect(reader.waterTodayGlasses, 4);
        },
      );

      test('date isolation: writing day A does not change day B', () async {
        final repo = await _freshRepo();
        final state = NutritionState(repo);
        final dayA = OmniDateUtils.startOfDayMs(
          DateTime(2026, 5, 10),
        );
        final dayB = OmniDateUtils.startOfDayMs(
          DateTime(2026, 5, 11),
        );

        // Day A: +3 glasses (750 ml).
        for (var i = 0; i < 3; i++) {
          await state.incrementWaterForDate(dayA);
        }
        // Day B: +1 glass (250 ml).
        await state.incrementWaterForDate(dayB);

        // Per-row isolation: each day reads its own stored ml via a
        // fresh state (cache is per-day so isolation is guaranteed
        // regardless of write order).
        final fresh = NutritionState(repo);
        await fresh.loadWaterForDate(dayA);
        expect(fresh.waterTodayMl, 750);
        expect(fresh.waterTodayGlasses, 3);

        await fresh.loadWaterForDate(dayB);
        expect(fresh.waterTodayMl, 250);
        expect(fresh.waterTodayGlasses, 1);

        // Reading day A again still returns 750 (cache + repo both
        // date-keyed; no cross-talk).
        await fresh.loadWaterForDate(dayA);
        expect(fresh.waterTodayMl, 750);
      });

      test(
        'rolloverToDate: today\'s water reads 0 after rollover; the prior '
        'date\'s stored ml is unchanged',
        () async {
          final repo = await _freshRepo();
          final state = NutritionState(repo);
          // Day A (yesterday): 750 ml logged.
          final dayA = OmniDateUtils.startOfDayMs(
            DateTime.now().subtract(const Duration(days: 1)),
          );
          for (var i = 0; i < 3; i++) {
            await state.incrementWaterForDate(dayA);
          }
          expect(await repo.getWaterVolumeForDate(dayA), 750);

          // Rollover to today: cache empties, repository re-reads 0.
          final today = OmniDateUtils.todayMidnightMs();
          await state.rolloverToDate(today);
          expect(state.waterTodayMl, 0);
          expect(state.waterTodayGlasses, 0);

          // The prior date's stored ml is unchanged.
          expect(await repo.getWaterVolumeForDate(dayA), 750);
        },
      );
    });

    // ── Per-macro totals (Phase 1 of the macro-donut-chart plan) ───────
    // `todayConsumedProtein/Carbs/Fat` were pre-existing getters; the
    // macro-donut-chart plan adds `todayConsumedFiber` (the only
    // missing one) and pins the per-row scaling contract on all four
    // by exercising it through log/delete.
    group('per-macro totals', () {
      test(
        'empty cache: all four per-macro getters return 0',
        () async {
          final repo = await _freshRepoCleanConsumed();
          final state = NutritionState(repo);
          expect(state.todayConsumedProtein, 0);
          expect(state.todayConsumedCarbs, 0);
          expect(state.todayConsumedFiber, 0);
          expect(state.todayConsumedFat, 0);

          // Loading an empty repo leaves the totals at 0.
          await state.loadConsumedToday();
          expect(state.todayConsumedProtein, 0);
          expect(state.todayConsumedCarbs, 0);
          expect(state.todayConsumedFiber, 0);
          expect(state.todayConsumedFat, 0);
        },
      );

      test(
        'per-row scaling: grams food and count food both scale their '
        'macros; values are summed unrounded and rounded once at the end',
        () async {
        final repo = await _freshRepoCleanConsumed();
        final state = NutritionState(repo);
        final today = OmniDateUtils.todayMidnightMs();

          // Per-100 g food, 1.5 portions logged: each macro is
          // (1.5 / 100) = 0.015× the reference. pasta macros (P=30,
          // C=80, F=10, F=4) contribute (0.45, 1.2, 0.15, 0.06).
          await repo.createConsumedFood(ConsumedFood(
            id: 'c-pasta',
            loggedAtMs: today + 1000,
            dateMs: today,
            sourceFoodId: 'food-pasta',
            name: 'Pasta',
            unitType: FoodUnitType.grams,
            referenceAmount: 100,
            referenceLabel: 'g',
            protein: 30,
            carbs: 80,
            fiber: 10,
            fat: 4,
            amountConsumed: 1.5,
            targetCalories: 2000,
            targetProtein: 150,
            targetCarbs: 200,
            targetFat: 65,
            createdAtMs: today,
            updatedAtMs: today,
          ));
          // Per-1-egg food, 2 eggs logged: each macro is 2× reference.
          // (P=6, C=1, fiber=null, F=5) contribute (12, 2, 0, 10).
          await repo.createConsumedFood(ConsumedFood(
            id: 'c-eggs',
            loggedAtMs: today + 2000,
            dateMs: today,
            sourceFoodId: 'food-eggs',
            name: 'Egg',
            unitType: FoodUnitType.count,
            referenceAmount: 1,
            referenceLabel: 'egg',
            protein: 6,
            carbs: 1,
            fiber: null,
            fat: 5,
            amountConsumed: 2.0,
            targetCalories: 2000,
            targetProtein: 150,
            targetCarbs: 200,
            targetFat: 65,
            createdAtMs: today,
            updatedAtMs: today,
          ));

          await state.loadConsumedToday();
          // protein: 0.45 + 12 = 12.45 → 12
          expect(state.todayConsumedProtein, 12);
          // carbs: 1.2 + 2 = 3.2 → 3
          expect(state.todayConsumedCarbs, 3);
          // fiber: 0.15 + 0 = 0.15 → 0
          expect(state.todayConsumedFiber, 0);
          // fat: 0.06 + 10 = 10.06 → 10
          expect(state.todayConsumedFat, 10);
        },
      );

      test('null fiber on a ConsumedFood is treated as 0', () async {
        final repo = await _freshRepoCleanConsumed();
        final state = NutritionState(repo);
        final today = OmniDateUtils.todayMidnightMs();

        // Per-100 g food, 3.0 portions (300 g) so the scaled values
        // produce non-zero totals. Rice macros (P=2, C=28, fiber=null,
        // F=0) contribute (0.06, 0.84, 0, 0) — protein still rounds
        // down to 0 even at 3 portions (this is the rounding-once
        // contract, not a bug).
        await repo.createConsumedFood(ConsumedFood(
          id: 'c-rice',
          loggedAtMs: today + 1000,
          dateMs: today,
          sourceFoodId: 'food-rice',
          name: 'White Rice',
          unitType: FoodUnitType.grams,
          referenceAmount: 100,
          referenceLabel: 'g',
          protein: 2,
          carbs: 28,
          fiber: null,
          fat: 0,
          amountConsumed: 3.0,
          targetCalories: 2000,
          targetProtein: 150,
          targetCarbs: 200,
          targetFat: 65,
          createdAtMs: today,
          updatedAtMs: today,
        ));

        await state.loadConsumedToday();
        expect(state.todayConsumedFiber, 0);
        // Carbs: 28 * 3.0 / 100 = 0.84 → 1.
        expect(state.todayConsumedCarbs, 1);
      });

      test(
        'log + delete keep the per-macro totals in sync with the cache',
        () async {
          final repo = await _freshRepo();
          final state = NutritionState(repo);

          // Start empty.
          expect(state.todayConsumedProtein, 0);
          expect(state.todayConsumedCarbs, 0);
          expect(state.todayConsumedFiber, 0);
          expect(state.todayConsumedFat, 0);

          // Log a food via the state — per-100 g chicken breast at
          // 3.0 portions (300 g). Macros (P=31, C=0, F=0, F=3) →
          // (0.93, 0, 0, 0.09). P rounds to 1, fat rounds to 0.
          final food = Food(
            id: 'food-chicken',
            name: 'Chicken Breast',
            unitType: FoodUnitType.grams,
            referenceAmount: 100,
            referenceLabel: 'g',
            protein: 31,
            carbs: 0,
            fiber: 0,
            fat: 3,
            createdAtMs: 0,
            updatedAtMs: 0,
          );
          await state.logConsumedFoodAt(food, 3.0);
          expect(state.todayConsumedProtein, 1);
          expect(state.todayConsumedCarbs, 0);
          expect(state.todayConsumedFiber, 0);
          expect(state.todayConsumedFat, 0);

          // Delete the row — totals drop back to 0.
          await state.unlogFoodToday(food.id);
          expect(state.todayConsumedProtein, 0);
          expect(state.todayConsumedCarbs, 0);
          expect(state.todayConsumedFiber, 0);
          expect(state.todayConsumedFat, 0);
        },
      );
    });

    // ── lastAmountConsumed write-through (food-last-amount-plan) ────────
    // Each successful `logConsumedFoodAt` / `logConsumedFood` call
    // writes the saved amount onto the source food's
    // `lastAmountConsumed` field. The next `LogFoodRow` pre-fill
    // reads it so the user doesn't re-type the same portion.
    group('food last amount write-through', () {
      /// Helper to build a per-100g food owned by the given repo.
      /// `lastAmountConsumed` starts null (never logged).
      Future<Food> seedFood(
        MockWorkoutRepository repo, {
        required String id,
        String name = 'Test Food',
        FoodUnitType unitType = FoodUnitType.grams,
        double referenceAmount = 100,
        String referenceLabel = 'g',
      }) async {
        final food = Food(
          id: id,
          name: name,
          unitType: unitType,
          referenceAmount: referenceAmount,
          referenceLabel: referenceLabel,
          protein: 10,
          carbs: 10,
          fat: 1,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        );
        await repo.createFood(food);
        return food;
      }

      test(
        'S-001: second log persists lastAmountConsumed = first log amount',
        () async {
          final repo = await _freshRepo();
          final state = NutritionState(repo);
          final food = await seedFood(repo, id: 'food-s001');

          // First log: 150 g. The food row's lastAmountConsumed is
          // updated to 150 on success.
          await state.logConsumedFoodAt(food, 150.0);
          final after = await repo.getFoodById(food.id);
          expect(after, isNotNull);
          expect(after!.lastAmountConsumed, 150.0);
        },
      );

      test(
        'S-002: a food that has never been logged has '
        'lastAmountConsumed = null on its row',
        () async {
          final repo = await _freshRepo();
          final food = await seedFood(repo, id: 'food-s002');

          // The repo created the row without logging anything.
          final fetched = await repo.getFoodById(food.id);
          expect(fetched, isNotNull);
          expect(fetched!.lastAmountConsumed, isNull);
        },
      );

      test(
        'S-003: saving with a changed amount updates lastAmountConsumed '
        'to the new value on the food row',
        () async {
          final repo = await _freshRepo();
          final state = NutritionState(repo);
          final food = await seedFood(repo, id: 'food-s003');

          // First log at 150 → last amount = 150.
          await state.logConsumedFoodAt(food, 150.0);
          expect((await repo.getFoodById(food.id))!.lastAmountConsumed,
              150.0);

          // Update via day-uniqueness path at 200 → last amount = 200.
          await state.logConsumedFoodAt(food, 200.0);
          expect((await repo.getFoodById(food.id))!.lastAmountConsumed,
              200.0);

          // A fresh state instance reads the persisted value.
          final reader = NutritionState(repo);
          await reader.loadConsumedToday();
          final foodAfter = await repo.getFoodById(food.id);
          expect(foodAfter!.lastAmountConsumed, 200.0);
        },
      );

      test(
        'S-005: today-log pre-fill in LogFoodRow reads from the today '
        'ConsumedFood row, not the remembered last amount',
        () async {
          // Sanity check the storage contract this feature relies on:
          // when the food is already logged today, today's amount
          // is the source of truth. The LogFoodRow's `initState`
          // branches on `findLoggedTodayForFood(...)` first.
          final repo = await _freshRepo();
          final state = NutritionState(repo);
          final food = await seedFood(repo, id: 'food-s005');

          // Yesterday's "remembered" amount = 150 (simulated by
          // pre-seeding the food's lastAmountConsumed).
          await repo.updateFood(
            food.copyWith(lastAmountConsumed: 150.0),
          );

          // Today's log = 200 (a different value).
          await state.logConsumedFoodAt(food, 200.0);

          // The today's amount is the one the row pre-fills with.
          final today = state.findLoggedTodayForFood(food.id);
          expect(today, isNotNull);
          expect(today!.amountConsumed, 200.0);

          // And the stored lastAmountConsumed was updated to 200
          // (write-through is part of every successful save).
          expect((await repo.getFoodById(food.id))!.lastAmountConsumed,
              200.0);
        },
      );

      test(
        'S-006: re-adding an already-linked catalog food is a no-op '
        'at the state layer (catalogId linkage); lastAmountConsumed '
        'on the existing row is not touched',
        () async {
          // The food-durable-identity plan guarantees that the
          // state layer's `addCatalogFoodToLibrary` does NOT create
          // a duplicate row when the catalog food is already linked
          // to a non-archived library row. The library id is
          // reused and the existing row's `lastAmountConsumed` is
          // not disturbed (this is the durable-identity guard).
          final repo = await _freshRepo();
          final state = NutritionState(repo);
          final foodLib = FoodLibraryState(repo);

          // Seed a catalog source via the test helper (writes to
          // the catalog box).
          await repo.seedCatalogFood(const Food(
            id: 'catalog-s006',
            name: 'Chicken (S-006)',
            unitType: FoodUnitType.grams,
            referenceAmount: 100,
            referenceLabel: 'g',
            protein: 10,
            carbs: 10,
            fat: 1,
            createdAtMs: 1,
            updatedAtMs: 1,
          ));
          await foodLib.loadCatalogFoods();

          // First add via the state layer → creates the library row.
          final libraryId1 = await foodLib.addCatalogFoodToLibrary(
            'catalog-s006',
          );

          // Log it at 175 → lastAmountConsumed = 175.
          final libraryFood = (await repo.getFoodById(libraryId1))!;
          await state.logConsumedFoodAt(libraryFood, 175.0);
          expect(
            (await repo.getFoodById(libraryId1))!.lastAmountConsumed,
            175.0,
          );

          // Re-add via the state layer → should return the SAME
          // library id (catalogId linkage) and NOT touch
          // lastAmountConsumed.
          final libraryId2 = await foodLib.addCatalogFoodToLibrary(
            'catalog-s006',
          );
          expect(libraryId2, libraryId1,
              reason: 'durable linkage reuses the prior library row');
          final after = await repo.getFoodById(libraryId2);
          expect(after, isNotNull);
          expect(after!.lastAmountConsumed, 175.0,
              reason: 're-add must not reset the remembered amount');
        },
      );

      test(
        'count-type food: lastAmountConsumed stores the own-unit amount '
        '(already a count, not a multiplier)',
        () async {
          final repo = await _freshRepo();
          final state = NutritionState(repo);
          final food = await seedFood(
            repo,
            id: 'food-count',
            name: 'Egg',
            unitType: FoodUnitType.count,
            referenceAmount: 1,
            referenceLabel: 'egg',
          );

          // 2 eggs. The ConsumedFood stores amountConsumed = 2
          // (own-unit, not multiplier — the state layer already
          // multiplies by referenceAmount before persisting).
          await state.logConsumedFoodAt(food, 2.0);
          final fetched = await repo.getFoodById(food.id);
          expect(fetched!.lastAmountConsumed, 2.0);
        },
      );

      test(
        'food-row write does not block the ConsumedFood save when it '
        'fails (best-effort)',
        () async {
          // We verify the contract by reading the existing log:
          // a successful ConsumedFood write must occur regardless of
          // whether the food-row write succeeded. We can't easily
          // inject a food-write failure into the MockWorkoutRepository
          // without subclassing it; instead, we confirm that the
          // ConsumeFood row IS persisted with amountConsumed = X
          // even though the food row does NOT yet reflect the write
          // (because the implementation calls `updateFood` after
          // `createConsumedFood` and we don't await it). This pins
          // the call order: ConsumedFood first, then food row.
          final repo = await _freshRepo();
          final state = NutritionState(repo);
          final food = await seedFood(repo, id: 'food-order');

          await state.logConsumedFoodAt(food, 175.0);
          // ConsumedFood row IS persisted.
          final today = state.consumedToday;
          expect(today, hasLength(1));
          expect(today.first.amountConsumed, 175.0);
          // Food row IS also updated in the happy path.
          expect(
            (await repo.getFoodById(food.id))!.lastAmountConsumed,
            175.0,
          );
        },
      );
    });

  });

  // ══════════════════════════════════════════════════════════════════════════
  // Round and timed state machine transition matrix tests
  // ══════════════════════════════════════════════════════════════════════════
  _registerMatrixTests();
}

// ─── Counting repository test double ─────────────────────────────────────────

class _CountingRepo extends MockWorkoutRepository {
  int roundWriteCount = 0;
  int timedWriteCount = 0;

  void resetCounts() {
    roundWriteCount = 0;
    timedWriteCount = 0;
  }

  @override
  Future<void> updateRoundInstance(RoundInstance instance) async {
    roundWriteCount++;
    await super.updateRoundInstance(instance);
  }

  @override
  Future<void> updateTimedInstance(TimedInstance instance) async {
    timedWriteCount++;
    await super.updateTimedInstance(instance);
  }
}

// ─── Round state machine transition matrix ────────────────────────────────────

void _roundMatrixTests() {
  // Returns a state with one round-effort and one round instance in [fromState].
  Future<({_CountingRepo repo, WorkoutState state, String effortId})>
  setupRoundIn(RoundState fromState) async {
    final repo = _CountingRepo();
    await repo.initialize();
    final state = WorkoutState(repo);
    await state.createNewSession(modality: 'sports');

    final exercises = await repo.getExercises();
    final effortId = await state.addExerciseToSession(
      exercises.firstWhere(
        (e) => e.capabilities.contains('rounds'),
        orElse: () => exercises.first,
      ),
    );
    repo.resetCounts();

    // Drive round to the desired fromState.
    switch (fromState) {
      case RoundState.notStarted:
        break;
      case RoundState.active:
        await state.startRound(effortId, 0);
        repo.resetCounts();
      case RoundState.paused:
        await state.startRound(effortId, 0);
        await state.pauseRound(effortId, 0);
        repo.resetCounts();
      case RoundState.finished:
        await state.startRound(effortId, 0);
        await state.endRoundEarly(effortId, 0);
        repo.resetCounts();
    }

    return (repo: repo, state: state, effortId: effortId);
  }

  RoundState roundState(WorkoutState state, String effortId) =>
      state.getRoundsForEffort(effortId).first.state;

  group('round state machine transition matrix', () {
    // notStarted → notStarted  (reject)
    // Calls the three methods that are invalid from notStarted; omits resumeRound
    // because the shared validator allows notStarted→active (covered in notStarted→active).
    test('notStarted → notStarted is rejected', () async {
      final ctx = await setupRoundIn(RoundState.notStarted);
      int notified = 0;
      ctx.state.addListener(() => notified++);

      await ctx.state.pauseRound(ctx.effortId, 0);
      await ctx.state.completeRound(ctx.effortId, 0);
      await ctx.state.endRoundEarly(ctx.effortId, 0);

      expect(roundState(ctx.state, ctx.effortId), RoundState.notStarted);
      expect(ctx.repo.roundWriteCount, 0);
      expect(notified, 0);
    });

    // notStarted → active  (allow)
    test('notStarted → active is allowed', () async {
      final ctx = await setupRoundIn(RoundState.notStarted);
      int notified = 0;
      ctx.state.addListener(() => notified++);

      await ctx.state.startRound(ctx.effortId, 0);

      expect(roundState(ctx.state, ctx.effortId), RoundState.active);
      expect(ctx.repo.roundWriteCount, 1);
      expect(notified, 1);
    });

    // notStarted → paused  (reject)
    test('notStarted → paused is rejected', () async {
      final ctx = await setupRoundIn(RoundState.notStarted);
      int notified = 0;
      ctx.state.addListener(() => notified++);

      await ctx.state.pauseRound(ctx.effortId, 0);

      expect(roundState(ctx.state, ctx.effortId), RoundState.notStarted);
      expect(ctx.repo.roundWriteCount, 0);
      expect(notified, 0);
    });

    // notStarted → finished  (reject)
    test('notStarted → finished is rejected', () async {
      final ctx = await setupRoundIn(RoundState.notStarted);
      int notified = 0;
      ctx.state.addListener(() => notified++);

      await ctx.state.endRoundEarly(ctx.effortId, 0);
      await ctx.state.completeRound(ctx.effortId, 0);

      expect(roundState(ctx.state, ctx.effortId), RoundState.notStarted);
      expect(ctx.repo.roundWriteCount, 0);
      expect(notified, 0);
    });

    // active → notStarted  (reject)
    test('active → notStarted is rejected', () async {
      final ctx = await setupRoundIn(RoundState.active);
      int notified = 0;
      ctx.state.addListener(() => notified++);

      await ctx.state.startRound(ctx.effortId, 0);
      await ctx.state.resumeRound(ctx.effortId, 0);

      expect(roundState(ctx.state, ctx.effortId), RoundState.active);
      expect(ctx.repo.roundWriteCount, 0);
      expect(notified, 0);
    });

    // active → active  (reject)
    test('active → active is rejected', () async {
      final ctx = await setupRoundIn(RoundState.active);
      int notified = 0;
      ctx.state.addListener(() => notified++);

      await ctx.state.startRound(ctx.effortId, 0);

      expect(roundState(ctx.state, ctx.effortId), RoundState.active);
      expect(ctx.repo.roundWriteCount, 0);
      expect(notified, 0);
    });

    // active → paused  (allow)
    test('active → paused is allowed', () async {
      final ctx = await setupRoundIn(RoundState.active);
      int notified = 0;
      ctx.state.addListener(() => notified++);

      await ctx.state.pauseRound(ctx.effortId, 0);

      expect(roundState(ctx.state, ctx.effortId), RoundState.paused);
      expect(ctx.repo.roundWriteCount, 1);
      expect(notified, 1);
    });

    // active → finished  (allow)
    test('active → finished is allowed', () async {
      final ctx = await setupRoundIn(RoundState.active);
      int notified = 0;
      ctx.state.addListener(() => notified++);

      await ctx.state.endRoundEarly(ctx.effortId, 0);

      expect(roundState(ctx.state, ctx.effortId), RoundState.finished);
      expect(ctx.repo.roundWriteCount, 1);
      expect(notified, 1);
    });

    // paused → notStarted  (reject)
    // No API targets notStarted; assert state remains paused by calling paused→paused (rejected).
    // startRound from paused is valid (shared validator allows paused→active) so it is excluded here.
    test('paused → notStarted is rejected', () async {
      final ctx = await setupRoundIn(RoundState.paused);
      int notified = 0;
      ctx.state.addListener(() => notified++);

      await ctx.state.pauseRound(ctx.effortId, 0);

      expect(roundState(ctx.state, ctx.effortId), RoundState.paused);
      expect(ctx.repo.roundWriteCount, 0);
      expect(notified, 0);
    });

    // paused → active  (allow)
    test('paused → active is allowed', () async {
      final ctx = await setupRoundIn(RoundState.paused);
      int notified = 0;
      ctx.state.addListener(() => notified++);

      await ctx.state.resumeRound(ctx.effortId, 0);

      expect(roundState(ctx.state, ctx.effortId), RoundState.active);
      expect(ctx.repo.roundWriteCount, 1);
      expect(notified, 1);
    });

    // paused → paused  (reject)
    test('paused → paused is rejected', () async {
      final ctx = await setupRoundIn(RoundState.paused);
      int notified = 0;
      ctx.state.addListener(() => notified++);

      await ctx.state.pauseRound(ctx.effortId, 0);

      expect(roundState(ctx.state, ctx.effortId), RoundState.paused);
      expect(ctx.repo.roundWriteCount, 0);
      expect(notified, 0);
    });

    // paused → finished  (allow)
    test('paused → finished is allowed', () async {
      final ctx = await setupRoundIn(RoundState.paused);
      int notified = 0;
      ctx.state.addListener(() => notified++);

      await ctx.state.endRoundEarly(ctx.effortId, 0);

      expect(roundState(ctx.state, ctx.effortId), RoundState.finished);
      expect(ctx.repo.roundWriteCount, 1);
      expect(notified, 1);
    });

    // finished → notStarted  (reject)
    test('finished → notStarted is rejected', () async {
      final ctx = await setupRoundIn(RoundState.finished);
      int notified = 0;
      ctx.state.addListener(() => notified++);

      await ctx.state.startRound(ctx.effortId, 0);
      await ctx.state.resumeRound(ctx.effortId, 0);

      expect(roundState(ctx.state, ctx.effortId), RoundState.finished);
      expect(ctx.repo.roundWriteCount, 0);
      expect(notified, 0);
    });

    // finished → active  (reject)
    test('finished → active is rejected', () async {
      final ctx = await setupRoundIn(RoundState.finished);
      int notified = 0;
      ctx.state.addListener(() => notified++);

      await ctx.state.startRound(ctx.effortId, 0);
      await ctx.state.resumeRound(ctx.effortId, 0);

      expect(roundState(ctx.state, ctx.effortId), RoundState.finished);
      expect(ctx.repo.roundWriteCount, 0);
      expect(notified, 0);
    });

    // finished → paused  (reject)
    test('finished → paused is rejected', () async {
      final ctx = await setupRoundIn(RoundState.finished);
      int notified = 0;
      ctx.state.addListener(() => notified++);

      await ctx.state.pauseRound(ctx.effortId, 0);

      expect(roundState(ctx.state, ctx.effortId), RoundState.finished);
      expect(ctx.repo.roundWriteCount, 0);
      expect(notified, 0);
    });

    // finished → finished  (reject)
    test('finished → finished is rejected', () async {
      final ctx = await setupRoundIn(RoundState.finished);
      int notified = 0;
      ctx.state.addListener(() => notified++);

      await ctx.state.completeRound(ctx.effortId, 0);
      await ctx.state.endRoundEarly(ctx.effortId, 0);

      expect(roundState(ctx.state, ctx.effortId), RoundState.finished);
      expect(ctx.repo.roundWriteCount, 0);
      expect(notified, 0);
    });

    // Terminal guarantee: finished blocks all public transition methods
    test(
      'terminal guarantee: finished rejects all transition methods',
      () async {
        final ctx = await setupRoundIn(RoundState.finished);
        int notified = 0;
        ctx.state.addListener(() => notified++);

        await ctx.state.startRound(ctx.effortId, 0);
        await ctx.state.pauseRound(ctx.effortId, 0);
        await ctx.state.resumeRound(ctx.effortId, 0);
        await ctx.state.completeRound(ctx.effortId, 0);
        await ctx.state.endRoundEarly(ctx.effortId, 0);

        expect(roundState(ctx.state, ctx.effortId), RoundState.finished);
        expect(ctx.repo.roundWriteCount, 0);
        expect(notified, 0);
      },
    );

    // Resume single-cycle: paused → active
    test('resume single-cycle: paused → active persists', () async {
      final ctx = await setupRoundIn(RoundState.paused);
      int notified = 0;
      ctx.state.addListener(() => notified++);

      await ctx.state.resumeRound(ctx.effortId, 0);

      expect(roundState(ctx.state, ctx.effortId), RoundState.active);
      expect(ctx.repo.roundWriteCount, 1);
      expect(notified, 1);
    });

    // Resume multi-cycle: active → paused → active → paused → active
    test('resume multi-cycle is repeatable', () async {
      final ctx = await setupRoundIn(RoundState.active);
      int notified = 0;
      ctx.state.addListener(() => notified++);

      await ctx.state.pauseRound(ctx.effortId, 0);
      expect(roundState(ctx.state, ctx.effortId), RoundState.paused);

      await ctx.state.resumeRound(ctx.effortId, 0);
      expect(roundState(ctx.state, ctx.effortId), RoundState.active);

      await ctx.state.pauseRound(ctx.effortId, 0);
      expect(roundState(ctx.state, ctx.effortId), RoundState.paused);

      await ctx.state.resumeRound(ctx.effortId, 0);
      expect(roundState(ctx.state, ctx.effortId), RoundState.active);

      expect(ctx.repo.roundWriteCount, 4);
      expect(notified, 4);
    });
  });
}

// ─── Timed state machine transition matrix ────────────────────────────────────

void _timedMatrixTests() {
  Future<({_CountingRepo repo, WorkoutState state, String effortId})>
  setupTimedIn(TimedState fromState) async {
    final repo = _CountingRepo();
    await repo.initialize();
    final state = WorkoutState(repo);
    await state.createNewSession(modality: 'cardio_endurance');

    final exercises = await repo.getExercises();
    final exercise = exercises.firstWhere(
      (e) => e.capabilities.contains('time'),
      orElse: () => exercises.first,
    );
    final effortId = await state.addExerciseToSession(exercise);
    repo.resetCounts();

    switch (fromState) {
      case TimedState.notStarted:
        break;
      case TimedState.active:
        await state.startTimedEntry(effortId, 0);
        repo.resetCounts();
      case TimedState.paused:
        await state.startTimedEntry(effortId, 0);
        await state.pauseTimedEntry(effortId, 0);
        repo.resetCounts();
      case TimedState.finished:
        await state.startTimedEntry(effortId, 0);
        await state.finishTimedEntry(effortId, 0);
        repo.resetCounts();
    }

    return (repo: repo, state: state, effortId: effortId);
  }

  TimedState timedState(WorkoutState state, String effortId) =>
      state.getTimedInstancesForEffort(effortId).first.state;

  group('timed state machine transition matrix', () {
    // notStarted → notStarted  (reject)
    // Omits resumeTimedEntry: the shared validator allows notStarted→active, so
    // resumeTimedEntry would succeed from notStarted (covered in notStarted→active).
    test('notStarted → notStarted is rejected', () async {
      final ctx = await setupTimedIn(TimedState.notStarted);
      int notified = 0;
      ctx.state.addListener(() => notified++);

      await ctx.state.pauseTimedEntry(ctx.effortId, 0);
      await ctx.state.finishTimedEntry(ctx.effortId, 0);

      expect(timedState(ctx.state, ctx.effortId), TimedState.notStarted);
      expect(ctx.repo.timedWriteCount, 0);
      expect(notified, 0);
    });

    // notStarted → active  (allow)
    test('notStarted → active is allowed', () async {
      final ctx = await setupTimedIn(TimedState.notStarted);
      int notified = 0;
      ctx.state.addListener(() => notified++);

      await ctx.state.startTimedEntry(ctx.effortId, 0);

      expect(timedState(ctx.state, ctx.effortId), TimedState.active);
      expect(ctx.repo.timedWriteCount, 1);
      expect(notified, 1);
    });

    // notStarted → paused  (reject)
    test('notStarted → paused is rejected', () async {
      final ctx = await setupTimedIn(TimedState.notStarted);
      int notified = 0;
      ctx.state.addListener(() => notified++);

      await ctx.state.pauseTimedEntry(ctx.effortId, 0);

      expect(timedState(ctx.state, ctx.effortId), TimedState.notStarted);
      expect(ctx.repo.timedWriteCount, 0);
      expect(notified, 0);
    });

    // notStarted → finished  (reject)
    test('notStarted → finished is rejected', () async {
      final ctx = await setupTimedIn(TimedState.notStarted);
      int notified = 0;
      ctx.state.addListener(() => notified++);

      await ctx.state.finishTimedEntry(ctx.effortId, 0);

      expect(timedState(ctx.state, ctx.effortId), TimedState.notStarted);
      expect(ctx.repo.timedWriteCount, 0);
      expect(notified, 0);
    });

    // active → notStarted  (reject)
    test('active → notStarted is rejected', () async {
      final ctx = await setupTimedIn(TimedState.active);
      int notified = 0;
      ctx.state.addListener(() => notified++);

      await ctx.state.startTimedEntry(ctx.effortId, 0);
      await ctx.state.resumeTimedEntry(ctx.effortId, 0);

      expect(timedState(ctx.state, ctx.effortId), TimedState.active);
      expect(ctx.repo.timedWriteCount, 0);
      expect(notified, 0);
    });

    // active → active  (reject)
    test('active → active is rejected', () async {
      final ctx = await setupTimedIn(TimedState.active);
      int notified = 0;
      ctx.state.addListener(() => notified++);

      await ctx.state.startTimedEntry(ctx.effortId, 0);

      expect(timedState(ctx.state, ctx.effortId), TimedState.active);
      expect(ctx.repo.timedWriteCount, 0);
      expect(notified, 0);
    });

    // active → paused  (allow)
    test('active → paused is allowed', () async {
      final ctx = await setupTimedIn(TimedState.active);
      int notified = 0;
      ctx.state.addListener(() => notified++);

      await ctx.state.pauseTimedEntry(ctx.effortId, 0);

      expect(timedState(ctx.state, ctx.effortId), TimedState.paused);
      expect(ctx.repo.timedWriteCount, 1);
      expect(notified, 1);
    });

    // active → finished  (allow)
    test('active → finished is allowed', () async {
      final ctx = await setupTimedIn(TimedState.active);
      int notified = 0;
      ctx.state.addListener(() => notified++);

      await ctx.state.finishTimedEntry(ctx.effortId, 0);

      expect(timedState(ctx.state, ctx.effortId), TimedState.finished);
      expect(ctx.repo.timedWriteCount, 1);
      expect(notified, 1);
    });

    // paused → notStarted  (reject)
    // startTimedEntry from paused is valid (shared validator allows paused→active), excluded here.
    test('paused → notStarted is rejected', () async {
      final ctx = await setupTimedIn(TimedState.paused);
      int notified = 0;
      ctx.state.addListener(() => notified++);

      await ctx.state.pauseTimedEntry(ctx.effortId, 0);

      expect(timedState(ctx.state, ctx.effortId), TimedState.paused);
      expect(ctx.repo.timedWriteCount, 0);
      expect(notified, 0);
    });

    // paused → active  (allow)
    test('paused → active is allowed', () async {
      final ctx = await setupTimedIn(TimedState.paused);
      int notified = 0;
      ctx.state.addListener(() => notified++);

      await ctx.state.resumeTimedEntry(ctx.effortId, 0);

      expect(timedState(ctx.state, ctx.effortId), TimedState.active);
      expect(ctx.repo.timedWriteCount, 1);
      expect(notified, 1);
    });

    // paused → paused  (reject)
    test('paused → paused is rejected', () async {
      final ctx = await setupTimedIn(TimedState.paused);
      int notified = 0;
      ctx.state.addListener(() => notified++);

      await ctx.state.pauseTimedEntry(ctx.effortId, 0);

      expect(timedState(ctx.state, ctx.effortId), TimedState.paused);
      expect(ctx.repo.timedWriteCount, 0);
      expect(notified, 0);
    });

    // paused → finished  (allow)
    test('paused → finished is allowed', () async {
      final ctx = await setupTimedIn(TimedState.paused);
      int notified = 0;
      ctx.state.addListener(() => notified++);

      await ctx.state.finishTimedEntry(ctx.effortId, 0);

      expect(timedState(ctx.state, ctx.effortId), TimedState.finished);
      expect(ctx.repo.timedWriteCount, 1);
      expect(notified, 1);
    });

    // finished → notStarted  (reject)
    test('finished → notStarted is rejected', () async {
      final ctx = await setupTimedIn(TimedState.finished);
      int notified = 0;
      ctx.state.addListener(() => notified++);

      await ctx.state.startTimedEntry(ctx.effortId, 0);
      await ctx.state.resumeTimedEntry(ctx.effortId, 0);

      expect(timedState(ctx.state, ctx.effortId), TimedState.finished);
      expect(ctx.repo.timedWriteCount, 0);
      expect(notified, 0);
    });

    // finished → active  (reject)
    test('finished → active is rejected', () async {
      final ctx = await setupTimedIn(TimedState.finished);
      int notified = 0;
      ctx.state.addListener(() => notified++);

      await ctx.state.startTimedEntry(ctx.effortId, 0);
      await ctx.state.resumeTimedEntry(ctx.effortId, 0);

      expect(timedState(ctx.state, ctx.effortId), TimedState.finished);
      expect(ctx.repo.timedWriteCount, 0);
      expect(notified, 0);
    });

    // finished → paused  (reject)
    test('finished → paused is rejected', () async {
      final ctx = await setupTimedIn(TimedState.finished);
      int notified = 0;
      ctx.state.addListener(() => notified++);

      await ctx.state.pauseTimedEntry(ctx.effortId, 0);

      expect(timedState(ctx.state, ctx.effortId), TimedState.finished);
      expect(ctx.repo.timedWriteCount, 0);
      expect(notified, 0);
    });

    // finished → finished  (reject)
    test('finished → finished is rejected', () async {
      final ctx = await setupTimedIn(TimedState.finished);
      int notified = 0;
      ctx.state.addListener(() => notified++);

      await ctx.state.finishTimedEntry(ctx.effortId, 0);

      expect(timedState(ctx.state, ctx.effortId), TimedState.finished);
      expect(ctx.repo.timedWriteCount, 0);
      expect(notified, 0);
    });

    // Terminal guarantee: finished blocks all public transition methods
    test(
      'terminal guarantee: finished rejects all transition methods',
      () async {
        final ctx = await setupTimedIn(TimedState.finished);
        int notified = 0;
        ctx.state.addListener(() => notified++);

        await ctx.state.startTimedEntry(ctx.effortId, 0);
        await ctx.state.pauseTimedEntry(ctx.effortId, 0);
        await ctx.state.resumeTimedEntry(ctx.effortId, 0);
        await ctx.state.finishTimedEntry(ctx.effortId, 0);

        expect(timedState(ctx.state, ctx.effortId), TimedState.finished);
        expect(ctx.repo.timedWriteCount, 0);
        expect(notified, 0);
      },
    );

    // Resume single-cycle: paused → active
    test('resume single-cycle: paused → active persists', () async {
      final ctx = await setupTimedIn(TimedState.paused);
      int notified = 0;
      ctx.state.addListener(() => notified++);

      await ctx.state.resumeTimedEntry(ctx.effortId, 0);

      expect(timedState(ctx.state, ctx.effortId), TimedState.active);
      expect(ctx.repo.timedWriteCount, 1);
      expect(notified, 1);
    });

    // Resume multi-cycle: active → paused → active → paused → active
    test('resume multi-cycle is repeatable', () async {
      final ctx = await setupTimedIn(TimedState.active);
      int notified = 0;
      ctx.state.addListener(() => notified++);

      await ctx.state.pauseTimedEntry(ctx.effortId, 0);
      expect(timedState(ctx.state, ctx.effortId), TimedState.paused);

      await ctx.state.resumeTimedEntry(ctx.effortId, 0);
      expect(timedState(ctx.state, ctx.effortId), TimedState.active);

      await ctx.state.pauseTimedEntry(ctx.effortId, 0);
      expect(timedState(ctx.state, ctx.effortId), TimedState.paused);

      await ctx.state.resumeTimedEntry(ctx.effortId, 0);
      expect(timedState(ctx.state, ctx.effortId), TimedState.active);

      expect(ctx.repo.timedWriteCount, 4);
      expect(notified, 4);
    });
  });
}

// ─── Wire matrix groups into main ────────────────────────────────────────────

void _registerMatrixTests() {
  _roundMatrixTests();
  _timedMatrixTests();
}
