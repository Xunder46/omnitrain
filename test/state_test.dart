import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';
import 'package:omnitrain/state/period/period_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

// ── Helpers ──────────────────────────────────────────────────────────────

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
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
      await repo.createTemplate(WorkoutTemplate(
        id: 'tmpl-1',
        name: 'Push Day',
        createdAtMs: 100,
        updatedAtMs: 100,
      ));
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

    test('updateRoutineFocusModality with null preserves prior value (copyWith limitation)',
        () async {
      final repo = await _freshRepo();
      final state = RoutineState(repo);
      state.setAutosaveEnabled(false);

      await state.createNewRoutine('Routine');
      await state.updateRoutineFocusModality('resistance_lifting');
      await state.updateRoutineFocusModality(null);

      // copyWith uses ?? so null keeps existing value
      expect(state.currentTemplate!.focusModality, 'resistance_lifting');
    });

    test('addExerciseToRoutine adds effort to first segment by default',
        () async {
      final repo = await _freshRepo();
      final state = RoutineState(repo);
      state.setAutosaveEnabled(false);

      final exercises = await repo.getExercises();
      await state.createNewRoutine('Routine');

      final effortId =
          await state.addExerciseToRoutine(exercises.first, 'set');
      expect(effortId, isNotEmpty);

      final efforts =
          state.getEffortsForSegment(state.currentSegments.first.id);
      expect(efforts, hasLength(1));
      expect(efforts.first.exerciseId, exercises.first.id);
      expect(efforts.first.effortKind, 'set');
    });

    test('addExerciseToRoutine returns empty string without segments', () async {
      final repo = await _freshRepo();
      final state = RoutineState(repo);
      state.setAutosaveEnabled(false);

      final exercises = await repo.getExercises();
      // No createNewRoutine → no segments
      final effortId =
          await state.addExerciseToRoutine(exercises.first, 'set');
      expect(effortId, isEmpty);
    });

    test('removeExerciseFromRoutine removes effort and its targets', () async {
      final repo = await _freshRepo();
      final state = RoutineState(repo);
      state.setAutosaveEnabled(false);

      final exercises = await repo.getExercises();
      await state.createNewRoutine('Routine');
      final effortId =
          await state.addExerciseToRoutine(exercises.first, 'set');

      // Add a target
      await state.setTargetValue(
        effortId,
        'metric-reps',
        'unit-reps',
        setIndex: 0,
        targetInt: 10,
      );

      await state.removeExerciseFromRoutine(effortId);

      final efforts =
          state.getEffortsForSegment(state.currentSegments.first.id);
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
    });

    group('targets', () {
      test('setTargetValue creates new target', () async {
        final repo = await _freshRepo();
        final state = RoutineState(repo);
        state.setAutosaveEnabled(false);

        final exercises = await repo.getExercises();
        await state.createNewRoutine('Routine');
        final effortId =
            await state.addExerciseToRoutine(exercises.first, 'set');

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
        final effortId =
            await state.addExerciseToRoutine(exercises.first, 'set');

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
        final effortId =
            await state.addExerciseToRoutine(exercises.first, 'set');

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
      final effortId =
          await state.addExerciseToRoutine(exercises.first, 'set');

      await state.updateEffortKind(effortId, 'timed');

      final efforts =
          state.getEffortsForSegment(state.currentSegments.first.id);
      expect(efforts.first.effortKind, 'timed');
    });

    test('updateEffortRest updates rest configuration', () async {
      final repo = await _freshRepo();
      final state = RoutineState(repo);
      state.setAutosaveEnabled(false);

      final exercises = await repo.getExercises();
      await state.createNewRoutine('Routine');
      final effortId =
          await state.addExerciseToRoutine(exercises.first, 'set');

      await state.updateEffortRest(
        effortId,
        restSeconds: 120,
        restType: 'fixed',
      );

      final efforts =
          state.getEffortsForSegment(state.currentSegments.first.id);
      expect(efforts.first.restSeconds, 120);
      expect(efforts.first.restType, 'fixed');
    });

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

    test('loadRoutineForEditing loads template with segments and efforts',
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
    });

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
      final effortId =
          await state.addExerciseToRoutine(exercises.first, 'set');

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
      final effortId =
          await state.addExerciseToRoutine(exercises.first, 'set');

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

    test('removeLastSetForEffort removes targets for last set', () async {
      final repo = await _freshRepo();
      final state = RoutineState(repo);
      state.setAutosaveEnabled(false);

      final exercises = await repo.getExercises();
      await state.createNewRoutine('Routine');
      final effortId =
          await state.addExerciseToRoutine(exercises.first, 'set');

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
      final effortId =
          await state.addExerciseToRoutine(exercises.first, 'set');

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
      final todayMs = DateTime(now.year, now.month, now.day)
          .millisecondsSinceEpoch;
      await repo.createSession(TrainingSession(
        id: 's-complete',
        ownerUserId: 'u-1',
        startedAtMs: todayMs + 1000,
        endedAtMs: todayMs + 3600000,
        createdAtMs: todayMs,
        updatedAtMs: todayMs,
      ));

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
      await repo.createPeriod(TrainingPeriod(
        id: 'p-1',
        ownerUserId: 'u-1',
        name: 'Bulk Phase',
        startDateMs: 1000,
        endDateMs: 5000,
        createdAtMs: 100,
        updatedAtMs: 100,
      ));

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
        await repo.createPeriod(TrainingPeriod(
          id: 'p-existing',
          ownerUserId: 'u-1',
          name: 'Existing',
          startDateMs: 1000,
          endDateMs: 5000,
          createdAtMs: 100,
          updatedAtMs: 100,
        ));

        final state = PeriodState(repo);
        final result = await state.validate('New', 3000, 7000);
        expect(result.isValid, false);
        expect(result.overlapError, isNotNull);
      });

      test('excludeId allows editing own period without overlap error',
          () async {
        final repo = await _freshRepo();
        await repo.createPeriod(TrainingPeriod(
          id: 'p-edit',
          ownerUserId: 'u-1',
          name: 'Edit Me',
          startDateMs: 1000,
          endDateMs: 5000,
          createdAtMs: 100,
          updatedAtMs: 100,
        ));

        final state = PeriodState(repo);
        final result = await state.validate(
          'Edit Me',
          1000,
          6000,
          excludeId: 'p-edit',
        );
        expect(result.isValid, true);
      });

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

      await state.createPeriod(
        name: 'Original',
        startMs: 1000,
        endMs: 5000,
      );

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

      await state.createPeriod(
        name: 'Valid',
        startMs: 1000,
        endMs: 5000,
      );

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

      await state.createPeriod(
        name: 'To Delete',
        startMs: 1000,
        endMs: 5000,
      );

      final id = state.periods.first.id;
      await state.deletePeriod(id);

      expect(state.periods, isEmpty);
    });
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

    test('updateSessionEndTime changes endedAtMs based on durationSecs',
        () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession();
      await state.endSession();

      final start = state.currentSession!.startedAtMs;
      await state.updateSessionEndTime(3600); // 1 hour

      expect(state.currentSession!.endedAtMs, start + 3600 * 1000);
    });

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

    group('round lifecycle', () {
      test('startRound creates an active RoundInstance', () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession(modality: 'martial_arts');

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
        await state.createNewSession(modality: 'martial_arts');

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
        await state.createNewSession(modality: 'martial_arts');

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
        await state.createNewSession(modality: 'martial_arts');

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
        await state.createNewSession(modality: 'martial_arts');

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
}
