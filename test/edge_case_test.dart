import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/utils/date_utils.dart';
import 'package:omnitrain/core/utils/exercise_helpers.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';
import 'package:omnitrain/state/period/period_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

/// Convenience: seed a completed TrainingSession directly into the repo.
Future<TrainingSession> _seedCompletedSession(
  MockWorkoutRepository repo, {
  required String id,
  required DateTime day,
  int durationMs = 3600000,
  String? modality,
}) async {
  final startMs = day.millisecondsSinceEpoch;
  final s = TrainingSession(
    id: id,
    ownerUserId: 'u-1',
    startedAtMs: startMs,
    endedAtMs: startMs + durationMs,
    modality: modality,
    createdAtMs: startMs,
    updatedAtMs: startMs,
  );
  await repo.createSession(s);
  return s;
}

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // Models — untested fromMap/toMap round-trips
  // ══════════════════════════════════════════════════════════════════════════

  group('Discipline', () {
    test('fromMap/toMap round-trip preserves all fields', () {
      final map = {
        'id': 'disc-1',
        'category_id': 'cat-1',
        'key': 'boxing',
        'name': 'Boxing',
        'created_at_ms': 100,
        'updated_at_ms': 200,
      };
      final obj = Discipline.fromMap(map);
      expect(obj.id, 'disc-1');
      expect(obj.categoryId, 'cat-1');
      expect(obj.key, 'boxing');
      expect(obj.name, 'Boxing');
      final result = obj.toMap();
      expect(result['id'], 'disc-1');
      expect(result['category_id'], 'cat-1');
      expect(result['key'], 'boxing');
      expect(result['name'], 'Boxing');
      expect(result['created_at_ms'], 100);
      expect(result['updated_at_ms'], 200);
    });
  });

  group('WorkoutTemplate', () {
    test('fromMap/toMap round-trip preserves all optional fields', () {
      final map = {
        'id': 'tmpl-1',
        'owner_user_id': 'u-1',
        'name': 'Push Day',
        'description': 'Chest and shoulders',
        'focus_modality': 'resistance_lifting',
        'primary_discipline_id': 'disc-1',
        'note': 'Keep rest short',
        'created_at_ms': 1000,
        'updated_at_ms': 2000,
      };
      final obj = WorkoutTemplate.fromMap(map);
      expect(obj.name, 'Push Day');
      expect(obj.description, 'Chest and shoulders');
      expect(obj.focusModality, 'resistance_lifting');
      expect(obj.note, 'Keep rest short');
      final result = obj.toMap();
      expect(result['focus_modality'], 'resistance_lifting');
      expect(result['primary_discipline_id'], 'disc-1');
    });

    test('fromMap handles null optional fields', () {
      final map = {
        'id': 'tmpl-2',
        'name': 'Empty Template',
        'created_at_ms': 1,
        'updated_at_ms': 1,
      };
      final obj = WorkoutTemplate.fromMap(map);
      expect(obj.ownerUserId, isNull);
      expect(obj.description, isNull);
      expect(obj.focusModality, isNull);
      expect(obj.note, isNull);
    });
  });

  group('MuscleGroup', () {
    test('fromMap/toMap round-trip', () {
      final map = {'id': 'mg-1', 'name': 'Quadriceps', 'created_at_ms': 500};
      final obj = MuscleGroup.fromMap(map);
      expect(obj.id, 'mg-1');
      expect(obj.name, 'Quadriceps');
      expect(obj.createdAtMs, 500);
      final result = obj.toMap();
      expect(result['name'], 'Quadriceps');
      expect(result['created_at_ms'], 500);
    });
  });

  group('SessionSegment', () {
    test('fromMap/toMap round-trip preserves optional name and note', () {
      final map = {
        'id': 'seg-1',
        'session_id': 'sess-1',
        'order_index': 1,
        'segment_type': 'warmup',
        'name': 'Warm-up Block',
        'note': 'Start easy',
        'created_at_ms': 100,
        'updated_at_ms': 200,
      };
      final obj = SessionSegment.fromMap(map);
      expect(obj.segmentType, 'warmup');
      expect(obj.name, 'Warm-up Block');
      expect(obj.note, 'Start easy');
      expect(obj.orderIndex, 1);
      final result = obj.toMap();
      expect(result['segment_type'], 'warmup');
      expect(result['name'], 'Warm-up Block');
      expect(result['order_index'], 1);
    });

    test('fromMap handles null optional fields', () {
      final map = {
        'id': 'seg-2',
        'session_id': 'sess-1',
        'order_index': 0,
        'segment_type': 'main',
        'created_at_ms': 1,
        'updated_at_ms': 1,
      };
      final obj = SessionSegment.fromMap(map);
      expect(obj.name, isNull);
      expect(obj.note, isNull);
      expect(obj.disciplineId, isNull);
    });
  });

  group('SegmentEffort', () {
    test('fromMap/toMap round-trip preserves all fields', () {
      final map = {
        'id': 'eff-1',
        'segment_id': 'seg-1',
        'order_index': 2,
        'effort_kind': 'set',
        'exercise_id': 'ex-1',
        'note': 'Focus on form',
        'created_at_ms': 100,
        'updated_at_ms': 200,
      };
      final obj = SegmentEffort.fromMap(map);
      expect(obj.orderIndex, 2);
      expect(obj.effortKind, 'set');
      expect(obj.exerciseId, 'ex-1');
      expect(obj.note, 'Focus on form');
      final result = obj.toMap();
      expect(result['effort_kind'], 'set');
      expect(result['order_index'], 2);
      expect(result['exercise_id'], 'ex-1');
    });

    test('fromMap handles null exercise_id (free effort)', () {
      final map = {
        'id': 'eff-2',
        'segment_id': 'seg-1',
        'order_index': 0,
        'effort_kind': 'timed',
        'created_at_ms': 1,
        'updated_at_ms': 1,
      };
      final obj = SegmentEffort.fromMap(map);
      expect(obj.exerciseId, isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Utils — edge cases not covered in utils_test.dart
  // ══════════════════════════════════════════════════════════════════════════

  group('OmniDateUtils.formatRange', () {
    test('same-day range produces repeated date string', () {
      // No short-circuit in impl: same day = "May 10 – May 10, 2025"
      final dayMs = DateTime(2025, 5, 10).millisecondsSinceEpoch;
      expect(OmniDateUtils.formatRange(dayMs, dayMs), 'May 10 – May 10, 2025');
    });
  });

  group('ExerciseCapabilities', () {
    test('supportsAny with empty required list returns false', () {
      final ex = Exercise(
        id: 'ex-1',
        ownerUserId: 'u-1',
        disciplineId: 'd-1',
        name: 'Squat',
        description: '',
        movementPattern: 'squat',
        isArchived: false,
        createdAtMs: 0,
        updatedAtMs: 0,
        capabilities: ['reps', 'load', 'sets'],
      );
      // An empty query list should never match anything
      expect(ex.supportsAny([]), false);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // WorkoutState — entry CRUD and session lifecycle
  // ══════════════════════════════════════════════════════════════════════════

  group('WorkoutState', () {
    test('addEntry increases entry count', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession();

      final exercises = await repo.getExercises();
      final effortId = await state.addExerciseToSession(
        exercises.first,
        chosenMetric: 'reps',
      );

      final before = (state.getExercisesWithEntries().first['entries'] as List).length;
      await state.addEntry(effortId);
      final after = (state.getExercisesWithEntries().first['entries'] as List).length;

      expect(after, before + 1);
    });

    test('updateEntryValue changes reps value for a set entry', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession();

      final exercises = await repo.getExercises();
      final effortId = await state.addExerciseToSession(
        exercises.first,
        chosenMetric: 'reps',
      );

      await state.updateEntryValue(effortId, 0, 'reps', 15);

      final entries = state.getExercisesWithEntries().first['entries'] as List;
      expect(entries.first['reps'], 15);
    });

    test('markSetSkipped marks entry as skipped (uses skipped key, not valueBool)', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession();

      final exercises = await repo.getExercises();
      final effortId = await state.addExerciseToSession(
        exercises.first,
        chosenMetric: 'reps',
      );

      await state.markSetSkipped(effortId, 0);

      final entries = state.getExercisesWithEntries().first['entries'] as List;
      expect(entries.first['skipped'], true);
    });

    test('deleteEntry reduces entry count', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession();

      final exercises = await repo.getExercises();
      final effortId = await state.addExerciseToSession(
        exercises.first,
        chosenMetric: 'reps',
      );
      await state.addEntry(effortId);

      expect(
        (state.getExercisesWithEntries().first['entries'] as List).length,
        2,
      );

      await state.deleteEntry(effortId, 1);

      expect(
        (state.getExercisesWithEntries().first['entries'] as List).length,
        1,
      );
    });

    test('removeExerciseFromSession removes the effort from the list', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession();

      final exercises = await repo.getExercises();
      final effortId = await state.addExerciseToSession(exercises.first);

      expect(state.getExercisesWithEntries(), isNotEmpty);

      await state.removeExerciseFromSession(effortId);

      expect(state.getExercisesWithEntries(), isEmpty);
    });

    test('updateSessionNote persists note on current session', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession();

      await state.updateSessionNote('Felt strong today');

      expect(state.currentSession!.note, 'Felt strong today');
    });

    test('discardCurrentSession clears hasSession and removes from repo', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession();

      final sessionId = state.currentSession!.id;

      await state.discardCurrentSession();

      expect(state.hasSession, isFalse);

      // Confirm removed from repository
      final all = await repo.getSessionsByDateRange(0, 9999999999999);
      expect(all.any((s) => s.id == sessionId), isFalse);
    });

    group('timed entry pause/resume', () {
      test('pauseTimedEntry transitions active → paused', () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession(modality: 'cardio_endurance');

        final exercises = await repo.getExercises();
        final timedEx = exercises.firstWhere(
          (e) => e.capabilities.contains('time'),
          orElse: () => exercises.first,
        );
        final effortId = await state.addExerciseToSession(timedEx);

        await state.startTimedEntry(effortId, 0);
        await state.pauseTimedEntry(effortId, 0);

        final instances = state.getTimedInstancesForEffort(effortId);
        expect(instances.first.state, TimedState.paused);
        expect(instances.first.pausedAtMs, isNotNull);
      });

      test('resumeTimedEntry transitions paused → active and accumulates pause duration', () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession(modality: 'cardio_endurance');

        final exercises = await repo.getExercises();
        final timedEx = exercises.firstWhere(
          (e) => e.capabilities.contains('time'),
          orElse: () => exercises.first,
        );
        final effortId = await state.addExerciseToSession(timedEx);

        await state.startTimedEntry(effortId, 0);
        await state.pauseTimedEntry(effortId, 0);
        await state.resumeTimedEntry(effortId, 0);

        final instances = state.getTimedInstancesForEffort(effortId);
        expect(instances.first.state, TimedState.active);
        expect(instances.first.pausedAtMs, isNull);
        expect(instances.first.totalPausedDurationMs, greaterThanOrEqualTo(0));
      });
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // CalendarState — derived stats and multi-entry days
  // ══════════════════════════════════════════════════════════════════════════

  group('CalendarState', () {
    test('totalTrainingMs sums durations of non-rolling completed sessions this month', () async {
      final repo = await _freshRepo();
      final now = DateTime.now();

      await _seedCompletedSession(
        repo,
        id: 's1',
        day: DateTime(now.year, now.month, 3),
        durationMs: 3600000, // 1 hour
      );
      await _seedCompletedSession(
        repo,
        id: 's2',
        day: DateTime(now.year, now.month, 4),
        durationMs: 1800000, // 30 min
      );

      // Rolling session — wall-clock is 8 h but must NOT be counted.
      final rollingStart = DateTime(now.year, now.month, 5).millisecondsSinceEpoch;
      await repo.createSession(TrainingSession(
        id: 's-rolling',
        ownerUserId: 'u-1',
        startedAtMs: rollingStart,
        endedAtMs: rollingStart + 28800000, // 8 hours
        isRolling: true,
        createdAtMs: rollingStart,
        updatedAtMs: rollingStart,
      ));

      final state = CalendarState(repo);
      await state.init();

      expect(state.totalTrainingMs, 5400000); // 1h30m — rolling excluded
    });

    test('totalTrainingMs — mixed month: only non-rolling duration counts', () async {
      final repo = await _freshRepo();
      final now = DateTime.now();

      // 1 non-rolling session: 1 hour
      await _seedCompletedSession(
        repo,
        id: 's-nonrolling',
        day: DateTime(now.year, now.month, 10),
        durationMs: 3600000,
      );

      // 1 rolling session: 8 hours wall-clock
      final rollingStart = DateTime(now.year, now.month, 11).millisecondsSinceEpoch;
      await repo.createSession(TrainingSession(
        id: 's-rolling',
        ownerUserId: 'u-1',
        startedAtMs: rollingStart,
        endedAtMs: rollingStart + 28800000,
        isRolling: true,
        createdAtMs: rollingStart,
        updatedAtMs: rollingStart,
      ));

      final state = CalendarState(repo);
      await state.init();

      expect(state.totalTrainingMs, 3600000); // 1 h only
    });

    test('totalTrainingMs — all-rolling month equals zero', () async {
      final repo = await _freshRepo();
      final now = DateTime.now();

      final s1Start = DateTime(now.year, now.month, 6).millisecondsSinceEpoch;
      final s2Start = DateTime(now.year, now.month, 7).millisecondsSinceEpoch;

      await repo.createSession(TrainingSession(
        id: 'r1',
        ownerUserId: 'u-1',
        startedAtMs: s1Start,
        endedAtMs: s1Start + 36000000, // 10 h
        isRolling: true,
        createdAtMs: s1Start,
        updatedAtMs: s1Start,
      ));
      await repo.createSession(TrainingSession(
        id: 'r2',
        ownerUserId: 'u-1',
        startedAtMs: s2Start,
        endedAtMs: s2Start + 43200000, // 12 h
        isRolling: true,
        createdAtMs: s2Start,
        updatedAtMs: s2Start,
      ));

      final state = CalendarState(repo);
      await state.init();

      expect(state.totalTrainingMs, 0);
    });

    test('completedSessionCount includes rolling sessions even when duration is excluded', () async {
      final repo = await _freshRepo();
      final now = DateTime.now();

      // 1 non-rolling: 1 h
      await _seedCompletedSession(
        repo,
        id: 's-nonrolling',
        day: DateTime(now.year, now.month, 12),
        durationMs: 3600000,
      );

      // 1 rolling: 8 h wall-clock
      final rollingStart = DateTime(now.year, now.month, 13).millisecondsSinceEpoch;
      await repo.createSession(TrainingSession(
        id: 's-rolling',
        ownerUserId: 'u-1',
        startedAtMs: rollingStart,
        endedAtMs: rollingStart + 28800000,
        isRolling: true,
        createdAtMs: rollingStart,
        updatedAtMs: rollingStart,
      ));

      final state = CalendarState(repo);
      await state.init();

      // Both sessions count as completed for the session count …
      expect(state.completedSessionCount, 2);
      // … but only the non-rolling one contributes to training time.
      expect(state.totalTrainingMs, 3600000);
    });

    test('modalityBreakdown groups completed sessions by modality key', () async {
      final repo = await _freshRepo();
      final now = DateTime.now();

      await _seedCompletedSession(
        repo,
        id: 's1',
        day: DateTime(now.year, now.month, 3),
        modality: 'strength',
      );
      await _seedCompletedSession(
        repo,
        id: 's2',
        day: DateTime(now.year, now.month, 4),
        modality: 'strength',
      );
      await _seedCompletedSession(
        repo,
        id: 's3',
        day: DateTime(now.year, now.month, 5),
        modality: 'cardio_endurance',
      );

      final state = CalendarState(repo);
      await state.init();

      final breakdown = state.modalityBreakdown;
      expect(breakdown['strength'], 2);
      expect(breakdown['cardio_endurance'], 1);
    });

    test('streakDays is > 0 when today and yesterday both have completed sessions', () async {
      final repo = await _freshRepo();
      final today = DateTime.now();
      final yesterday = today.subtract(const Duration(days: 1));

      await _seedCompletedSession(repo, id: 'today', day: today);
      await _seedCompletedSession(repo, id: 'yesterday', day: yesterday);

      final state = CalendarState(repo);
      await state.init();

      expect(state.streakDays, greaterThanOrEqualTo(2));
    });

    test('entriesForDay returns all entries on the same calendar day', () async {
      final repo = await _freshRepo();
      final now = DateTime.now();
      final targetDay = DateTime(now.year, now.month, 8);

      // Two completed sessions on the same day (different start times)
      await _seedCompletedSession(repo, id: 's-am', day: targetDay, durationMs: 3600000);
      // A second session starting 2 hours after midnight the same day
      final s2Start = targetDay.millisecondsSinceEpoch + 7200000;
      final s2 = TrainingSession(
        id: 's-pm',
        ownerUserId: 'u-1',
        startedAtMs: s2Start,
        endedAtMs: s2Start + 1800000,
        createdAtMs: s2Start,
        updatedAtMs: s2Start,
      );
      await repo.createSession(s2);

      final state = CalendarState(repo);
      await state.init();

      final entries = state.entriesForDay(targetDay);
      expect(entries.length, 2);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // PeriodState — single-day, colorHex, updatePeriod
  // ══════════════════════════════════════════════════════════════════════════

  group('PeriodState', () {
    test('createPeriod succeeds when startMs equals endMs (single-day period)', () async {
      final repo = await _freshRepo();
      final state = PeriodState(repo);

      final dayMs = DateTime(2026, 6, 15).millisecondsSinceEpoch;
      final ok = await state.createPeriod(
        name: 'Single Day',
        startMs: dayMs,
        endMs: dayMs,
      );

      expect(ok, isTrue);
      await state.load();
      expect(state.periods.any((p) => p.name == 'Single Day'), isTrue);
    });

    test('colorHex is preserved through createPeriod and load', () async {
      final repo = await _freshRepo();
      final state = PeriodState(repo);

      final startMs = DateTime(2026, 7, 1).millisecondsSinceEpoch;
      final endMs = DateTime(2026, 7, 31).millisecondsSinceEpoch;
      final ok = await state.createPeriod(
        name: 'Color Period',
        startMs: startMs,
        endMs: endMs,
        colorHex: '#E91E63',
      );

      expect(ok, isTrue);
      await state.load();
      final period = state.periods.firstWhere((p) => p.name == 'Color Period');
      expect(period.colorHex, '#E91E63');
    });

    test('updatePeriod changes name and colorHex', () async {
      final repo = await _freshRepo();
      final state = PeriodState(repo);

      final startMs = DateTime(2026, 8, 1).millisecondsSinceEpoch;
      final endMs = DateTime(2026, 8, 31).millisecondsSinceEpoch;
      await state.createPeriod(
        name: 'Old Name',
        startMs: startMs,
        endMs: endMs,
        colorHex: '#FF0000',
      );
      await state.load();
      final period = state.periods.first;

      final ok = await state.updatePeriod(
        id: period.id,
        createdAtMs: period.createdAtMs,
        name: 'New Name',
        startMs: startMs,
        endMs: endMs,
        colorHex: '#00BCD4',
      );

      expect(ok, isTrue);
      await state.load();
      final updated = state.periods.firstWhere((p) => p.id == period.id);
      expect(updated.name, 'New Name');
      expect(updated.colorHex, '#00BCD4');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // RoutineState — countPlannedSessionsForTemplate and targetMin/Max
  // ══════════════════════════════════════════════════════════════════════════

  group('RoutineState', () {
    test('countPlannedSessionsForTemplate returns 0 for unknown template', () async {
      final repo = await _freshRepo();
      final state = RoutineState(repo);

      final count = await state.countPlannedSessionsForTemplate('no-such-template');
      expect(count, 0);
    });

    test('countPlannedSessionsForTemplate reflects linked planned sessions', () async {
      final repo = await _freshRepo();
      final state = RoutineState(repo);
      state.setAutosaveEnabled(false);

      await state.createNewRoutine('Pull Day');
      await state.saveRoutine();
      final templateId = state.currentTemplate!.id;

      // Seed two planned sessions linked to template
      final now = DateTime.now().millisecondsSinceEpoch;
      await repo.createPlannedSession(PlannedSession(
        id: 'ps-1',
        ownerUserId: 'u-1',
        scheduledDateMs: now + 86400000,
        routineTemplateId: templateId,
        isCompleted: false,
        createdAtMs: now,
        updatedAtMs: now,
      ));
      await repo.createPlannedSession(PlannedSession(
        id: 'ps-2',
        ownerUserId: 'u-1',
        scheduledDateMs: now + 172800000,
        routineTemplateId: templateId,
        isCompleted: false,
        createdAtMs: now,
        updatedAtMs: now,
      ));

      final count = await state.countPlannedSessionsForTemplate(templateId);
      expect(count, 2);
    });

    test('setTargetValue stores targetMin and targetMax for a range target', () async {
      final repo = await _freshRepo();
      final state = RoutineState(repo);
      state.setAutosaveEnabled(false);

      final exercises = await repo.getExercises();
      await state.createNewRoutine('Hypertrophy');
      final effortId =
          await state.addExerciseToRoutine(exercises.first, 'set');

      await state.setTargetValue(
        effortId,
        'metric-reps',
        'unit-reps',
        setIndex: 0,
        targetMin: 8.0,
        targetMax: 12.0,
      );

      final targets = state.getEffortTargets(effortId);
      expect(targets, hasLength(1));
      expect(targets.first.targetMin, 8.0);
      expect(targets.first.targetMax, 12.0);
    });

    test('setTargetValue with different setIndex values creates independent per-set targets', () async {
      final repo = await _freshRepo();
      final state = RoutineState(repo);
      state.setAutosaveEnabled(false);

      final exercises = await repo.getExercises();
      await state.createNewRoutine('Strength');
      final effortId =
          await state.addExerciseToRoutine(exercises.first, 'set');

      await state.setTargetValue(
        effortId,
        'metric-reps',
        'unit-reps',
        setIndex: 1,
        targetInt: 5,
      );
      await state.setTargetValue(
        effortId,
        'metric-reps',
        'unit-reps',
        setIndex: 2,
        targetInt: 3,
      );

      final t1 = state.getEffortTargetsForSet(effortId, 1);
      final t2 = state.getEffortTargetsForSet(effortId, 2);
      final t3 = state.getEffortTargetsForSet(effortId, 0);

      expect(t1, hasLength(1));
      expect(t1.first.targetInt, 5);
      expect(t2, hasLength(1));
      expect(t2.first.targetInt, 3);
      expect(t3, isEmpty); // setIndex 0 not set
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // MockWorkoutRepository — hasPeriodOverlap boundary conditions
  // ══════════════════════════════════════════════════════════════════════════

  group('MockWorkoutRepository.hasPeriodOverlap', () {
    // Helper: seed a period into the repo directly.
    Future<void> seedPeriod(
      MockWorkoutRepository repo, {
      required String id,
      required int startMs,
      required int endMs,
    }) async {
      await repo.createPeriod(TrainingPeriod(
        id: id,
        name: 'Period $id',
        startDateMs: startMs,
        endDateMs: endMs,
        createdAtMs: 0,
        updatedAtMs: 0,
      ));
    }

    test('returns false when no periods exist', () async {
      final repo = await _freshRepo();
      final overlap = await repo.hasPeriodOverlap(1000, 2000);
      expect(overlap, isFalse);
    });

    test('returns false for completely non-overlapping range', () async {
      final repo = await _freshRepo();
      // Existing period: 100–200
      await seedPeriod(repo, id: 'p1', startMs: 100, endMs: 200);

      // Query entirely after existing period
      expect(await repo.hasPeriodOverlap(300, 400), isFalse);
      // Query entirely before existing period
      expect(await repo.hasPeriodOverlap(0, 50), isFalse);
    });

    test('returns true when new range overlaps an existing period', () async {
      final repo = await _freshRepo();
      await seedPeriod(repo, id: 'p1', startMs: 100, endMs: 300);

      // Partially overlapping from the left
      expect(await repo.hasPeriodOverlap(50, 150), isTrue);
      // Partially overlapping from the right
      expect(await repo.hasPeriodOverlap(250, 400), isTrue);
      // Entirely inside
      expect(await repo.hasPeriodOverlap(150, 200), isTrue);
      // Entirely surrounding
      expect(await repo.hasPeriodOverlap(0, 500), isTrue);
    });

    test('returns true at inclusive boundary (touching endDateMs)', () async {
      final repo = await _freshRepo();
      // Period ends at ms 200
      await seedPeriod(repo, id: 'p1', startMs: 100, endMs: 200);

      // New period starts exactly at the same ms — should overlap per inclusive check
      expect(await repo.hasPeriodOverlap(200, 300), isTrue);
    });

    test('returns true at inclusive boundary (touching startDateMs)', () async {
      final repo = await _freshRepo();
      // Period starts at ms 200
      await seedPeriod(repo, id: 'p1', startMs: 200, endMs: 400);

      // New period ends exactly at startDateMs — should overlap
      expect(await repo.hasPeriodOverlap(100, 200), isTrue);
    });

    test('excludeId skips that period from the overlap check', () async {
      final repo = await _freshRepo();
      await seedPeriod(repo, id: 'p1', startMs: 100, endMs: 300);

      // Without excludeId: overlaps
      expect(await repo.hasPeriodOverlap(100, 300), isTrue);
      // With excludeId matching the only period: no overlap
      expect(await repo.hasPeriodOverlap(100, 300, excludeId: 'p1'), isFalse);
    });

    test('excludeId only skips the matching period, not others', () async {
      final repo = await _freshRepo();
      await seedPeriod(repo, id: 'p1', startMs: 100, endMs: 300);
      await seedPeriod(repo, id: 'p2', startMs: 200, endMs: 400);

      // Excluding p1 still finds p2 overlap
      expect(await repo.hasPeriodOverlap(150, 350, excludeId: 'p1'), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // NutritionTarget — daily targets (backward-walk + forward-propagation)
  // ══════════════════════════════════════════════════════════════════════════

  group('NutritionTarget (date-keyed) edge cases', () {
    test('backward-walk returns null when no ancestor exists', () async {
      final repo = await _freshRepo();
      final farFuture = OmniDateUtils.startOfDayMs(
        DateTime.now().add(const Duration(days: 30)),
      );
      expect(await repo.getNutritionTargetForDate(farFuture), isNull);
    });

    test('backward-walk finds the nearest ancestor (not the earliest)',
        () async {
      final repo = await _freshRepo();
      final threeDaysAgo = OmniDateUtils.startOfDayMs(
        DateTime.now().subtract(const Duration(days: 3)),
      );
      final oneDayAgo = OmniDateUtils.startOfDayMs(
        DateTime.now().subtract(const Duration(days: 1)),
      );
      await repo.saveNutritionTargetForDate(
        threeDaysAgo,
        NutritionTarget(calories: 1500),
      );
      await repo.saveNutritionTargetForDate(
        oneDayAgo,
        NutritionTarget(calories: 2400),
      );

      final today = OmniDateUtils.todayMidnightMs();
      // The two-days-ago slot is empty; the walk should land on the most
      // recent ancestor (yesterday) and ignore the three-days-ago value.
      final result = await repo.getNutritionTargetForDate(today);
      expect(result?.calories, 2400);
    });

    test(
        'forward-propagation updates future targets that match the OLD values',
        () async {
      final repo = await _freshRepo();
      final today = OmniDateUtils.todayMidnightMs();
      final tomorrow = OmniDateUtils.startOfDayMs(
        DateTime.now().add(const Duration(days: 1)),
      );
      final dayAfter = OmniDateUtils.startOfDayMs(
        DateTime.now().add(const Duration(days: 2)),
      );

      // Seed today + tomorrow + day-after with the SAME values.
      final shared = NutritionTarget(
        calories: 2000,
        protein: 120,
        carbs: 250,
        fat: 70,
      );
      await repo.saveNutritionTargetForDate(today, shared);
      await repo.saveNutritionTargetForDate(tomorrow, shared);
      await repo.saveNutritionTargetForDate(dayAfter, shared);

      // Edit today's values.
      await repo.saveNutritionTargetForDate(
        today,
        NutritionTarget(calories: 2500, protein: 150, carbs: 300, fat: 80),
      );

      // Tomorrow should propagate.
      final tomorrowTarget = await repo.getNutritionTargetForDate(tomorrow);
      expect(tomorrowTarget?.calories, 2500);
      expect(tomorrowTarget?.protein, 150);

      // Day-after should also propagate.
      final dayAfterTarget = await repo.getNutritionTargetForDate(dayAfter);
      expect(dayAfterTarget?.calories, 2500);
      expect(dayAfterTarget?.protein, 150);
    });

    test(
        'forward-propagation does NOT touch future targets that already '
        'differed from the old values', () async {
      final repo = await _freshRepo();
      final today = OmniDateUtils.todayMidnightMs();
      final tomorrow = OmniDateUtils.startOfDayMs(
        DateTime.now().add(const Duration(days: 1)),
      );

      // Today: A. Tomorrow: A. Day-after: B (user explicitly changed it).
      final a = NutritionTarget(
        calories: 2000,
        protein: 120,
        carbs: 250,
        fat: 70,
      );
      final b = NutritionTarget(
        calories: 3000,
        protein: 180,
        carbs: 350,
        fat: 100,
      );
      await repo.saveNutritionTargetForDate(today, a);
      await repo.saveNutritionTargetForDate(tomorrow, a);
      // (Day-after left as B; it does not match A, so propagation skips it.)
      final dayAfter = OmniDateUtils.startOfDayMs(
        DateTime.now().add(const Duration(days: 2)),
      );
      await repo.saveNutritionTargetForDate(dayAfter, b);

      // Edit today → A becomes A'.
      final aPrime = NutritionTarget(
        calories: 2500,
        protein: 150,
        carbs: 300,
        fat: 80,
      );
      await repo.saveNutritionTargetForDate(today, aPrime);

      // Tomorrow matches OLD A, so it should be updated to A'.
      final tomorrowTarget = await repo.getNutritionTargetForDate(tomorrow);
      expect(tomorrowTarget?.calories, 2500);

      // Day-after matches NEITHER old A nor new A' (it was B); the
      // repository's propagation rule looks for matches against the OLD
      // value. Day-after was B, not A, so it stays B.
      final dayAfterTarget = await repo.getNutritionTargetForDate(dayAfter);
      expect(dayAfterTarget?.calories, 3000);
    });

    test('legacy get/save methods delegate to today\'s date', () async {
      final repo = await _freshRepo();
      await repo.saveNutritionTarget(
        NutritionTarget(calories: 1900, protein: 100),
      );
      final today = OmniDateUtils.todayMidnightMs();
      final reloaded = await repo.getNutritionTargetForDate(today);
      expect(reloaded?.calories, 1900);
      expect(reloaded?.protein, 100);

      // Legacy getter agrees.
      final legacy = await repo.getNutritionTarget();
      expect(legacy?.calories, 1900);
    });
  });
}
