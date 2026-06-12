import 'dart:convert';
import 'package:test/test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/core/constants/capability.dart';

void main() {
  // ── SportCategory ─────────────────────────────────────────────────────────

  group('SportCategory', () {
    test('fromMap/toMap round-trip preserves all fields', () {
      final map = {
        'id': 'cat-1',
        'key': 'combat',
        'name': 'Combat Sports',
        'description': 'Fighting disciplines',
        'icon_name': 'fist',
        'sort_order': 3,
        'created_at_ms': 1000,
        'updated_at_ms': 2000,
        'deleted_at_ms': 3000,
      };
      final obj = SportCategory.fromMap(map);
      final result = obj.toMap();
      expect(result['id'], 'cat-1');
      expect(result['key'], 'combat');
      expect(result['name'], 'Combat Sports');
      expect(result['description'], 'Fighting disciplines');
      expect(result['icon_name'], 'fist');
      expect(result['sort_order'], 3);
      expect(result['created_at_ms'], 1000);
      expect(result['updated_at_ms'], 2000);
      expect(result['deleted_at_ms'], 3000);
    });

    test('fromMap defaults sortOrder to 0 when missing', () {
      final map = {
        'id': 'cat-1',
        'key': 'k',
        'name': 'n',
        'created_at_ms': 1,
        'updated_at_ms': 2,
      };
      final obj = SportCategory.fromMap(map);
      expect(obj.sortOrder, 0);
    });
  });

  // ── Exercise ──────────────────────────────────────────────────────────────

  group('Exercise', () {
    test('fromMap/toMap round-trip preserves howToSteps via JSON', () {
      final steps = ['Step 1', 'Step 2', 'Step 3'];
      final map = {
        'id': 'ex-1',
        'name': 'Barbell Squat',
        'is_archived': 0,
        'created_at_ms': 100,
        'updated_at_ms': 200,
        'how_to_steps': jsonEncode(steps),
      };
      final obj = Exercise.fromMap(map);
      expect(obj.howToSteps, steps);

      final result = obj.toMap();
      expect(jsonDecode(result['how_to_steps'] as String), steps);
    });

    test('fromMap handles null howToSteps', () {
      final map = {
        'id': 'ex-1',
        'name': 'Test',
        'is_archived': 0,
        'created_at_ms': 100,
        'updated_at_ms': 200,
      };
      final obj = Exercise.fromMap(map);
      expect(obj.howToSteps, isNull);
    });

    test('fromMap coerces isArchived from int to bool', () {
      final archived = Exercise.fromMap({
        'id': 'ex-1',
        'name': 'Test',
        'is_archived': 1,
        'created_at_ms': 100,
        'updated_at_ms': 200,
      });
      expect(archived.isArchived, true);

      final notArchived = Exercise.fromMap({
        'id': 'ex-2',
        'name': 'Test2',
        'is_archived': 0,
        'created_at_ms': 100,
        'updated_at_ms': 200,
      });
      expect(notArchived.isArchived, false);
    });

    test('toMap converts isArchived to int', () {
      final obj = Exercise(
        id: 'ex-1',
        name: 'Test',
        isArchived: true,
        createdAtMs: 100,
        updatedAtMs: 200,
      );
      expect(obj.toMap()['is_archived'], 1);
    });

    test('fromMap does not populate capabilities from map', () {
      final map = {
        'id': 'ex-1',
        'name': 'Test',
        'is_archived': 0,
        'created_at_ms': 100,
        'updated_at_ms': 200,
      };
      final obj = Exercise.fromMap(map);
      expect(obj.capabilities, isEmpty);
    });

    test('Exercise constructed with bilateral capability exposes it', () {
      final exercise = Exercise(
        id: 'ex-bilateral',
        name: 'Dumbbell Curl',
        createdAtMs: 0,
        updatedAtMs: 0,
        capabilities: const [
          ExerciseCapability.bilateral,
          ExerciseCapability.reps,
          ExerciseCapability.load,
        ],
      );
      expect(
        exercise.capabilities.contains(ExerciseCapability.bilateral),
        isTrue,
      );
      expect(exercise.capabilities, containsAll(['bilateral', 'reps', 'load']));
    });
  });

  // ── TrainingSession ───────────────────────────────────────────────────────

  group('TrainingSession', () {
    test('fromMap coerces perceivedSessionRpe from int via num', () {
      final map = {
        'id': 's-1',
        'owner_user_id': 'u-1',
        'started_at_ms': 1000,
        'perceived_session_rpe': 7,
        'created_at_ms': 100,
        'updated_at_ms': 200,
      };
      final obj = TrainingSession.fromMap(map);
      expect(obj.perceivedSessionRpe, 7.0);
      expect(obj.perceivedSessionRpe, isA<double>());
    });

    test('fromMap handles null perceivedSessionRpe', () {
      final map = {
        'id': 's-1',
        'owner_user_id': 'u-1',
        'started_at_ms': 1000,
        'created_at_ms': 100,
        'updated_at_ms': 200,
      };
      final obj = TrainingSession.fromMap(map);
      expect(obj.perceivedSessionRpe, isNull);
    });

    test('fromMap/toMap round-trip preserves all fields', () {
      final map = {
        'id': 's-1',
        'owner_user_id': 'u-1',
        'routine_template_id': 'r-1',
        'started_at_ms': 1000,
        'ended_at_ms': 5000,
        'title': 'Morning Lift',
        'note': 'Felt great',
        'location_text': 'Home gym',
        'modality': 'resistance_lifting',
        'intent': 'hypertrophy',
        'perceived_session_rpe': 8.5,
        'session_feeling': 4,
        'quality_rating': 3,
        'created_at_ms': 100,
        'updated_at_ms': 200,
      };
      final obj = TrainingSession.fromMap(map);
      final result = obj.toMap();
      expect(result['id'], 's-1');
      expect(result['routine_template_id'], 'r-1');
      expect(result['modality'], 'resistance_lifting');
      expect(result['session_feeling'], 4);
      expect(result['perceived_session_rpe'], 8.5);
    });

    test('fromMap/toMap handles isRolling int-bool conversion', () {
      final map = {
        'id': 's-rolling',
        'owner_user_id': 'u-1',
        'started_at_ms': 1000,
        'is_rolling': 1,
        'created_at_ms': 100,
        'updated_at_ms': 200,
      };
      final obj = TrainingSession.fromMap(map);
      expect(obj.isRolling, true);

      final result = obj.toMap();
      expect(result['is_rolling'], 1);
    });
  });

  // ── SessionBlock ──────────────────────────────────────────────────────────

  group('SessionBlock', () {
    test('fromMap/toMap round-trip preserves all fields', () {
      final map = {
        'id': 'block-1',
        'session_id': 'session-1',
        'name': 'Warm-Up',
        'order_index': 2,
        'top_level_order_index': 5,
        'created_at_ms': 100,
        'updated_at_ms': 200,
      };

      final obj = SessionBlock.fromMap(map);
      final result = obj.toMap();

      expect(result['id'], 'block-1');
      expect(result['session_id'], 'session-1');
      expect(result['name'], 'Warm-Up');
      expect(result['order_index'], 2);
      expect(obj.topLevelOrderIndex, 5);
      expect(result['top_level_order_index'], 5);
      expect(result['created_at_ms'], 100);
      expect(result['updated_at_ms'], 200);
    });

    test('fromMap backfills topLevelOrderIndex from orderIndex', () {
      final obj = SessionBlock.fromMap({
        'id': 'block-2',
        'session_id': 'session-1',
        'name': 'Main',
        'order_index': 7,
        'created_at_ms': 100,
        'updated_at_ms': 200,
      });

      expect(obj.topLevelOrderIndex, 7);
      expect(obj.toMap()['top_level_order_index'], 7);
    });
  });

  // ── SegmentEffort ────────────────────────────────────────────────────────

  group('SegmentEffort', () {
    test('fromMap/toMap round-trip preserves nullable blockId', () {
      final map = {
        'id': 'effort-1',
        'segment_id': 'segment-1',
        'order_index': 0,
        'top_level_order_index': 3,
        'block_order_index': 1,
        'effort_kind': 'set',
        'exercise_id': 'exercise-1',
        'note': 'note',
        'block_id': 'block-1',
        'created_at_ms': 100,
        'updated_at_ms': 200,
      };

      final obj = SegmentEffort.fromMap(map);
      final result = obj.toMap();

      expect(obj.blockId, 'block-1');
      expect(obj.topLevelOrderIndex, 3);
      expect(obj.blockOrderIndex, 1);
      expect(result['block_id'], 'block-1');
      expect(result['top_level_order_index'], 3);
      expect(result['block_order_index'], 1);
    });

    test('fromMap handles null blockId', () {
      final obj = SegmentEffort.fromMap({
        'id': 'effort-2',
        'segment_id': 'segment-1',
        'order_index': 1,
        'effort_kind': 'timed',
        'created_at_ms': 100,
        'updated_at_ms': 200,
      });

      expect(obj.blockId, isNull);
      expect(obj.topLevelOrderIndex, 1);
      expect(obj.blockOrderIndex, isNull);
      expect(obj.toMap()['block_id'], isNull);
      expect(obj.toMap()['top_level_order_index'], 1);
      expect(obj.toMap()['block_order_index'], isNull);
    });

    test('fromMap backfills blockOrderIndex for legacy blocked effort', () {
      final obj = SegmentEffort.fromMap({
        'id': 'effort-3',
        'segment_id': 'segment-1',
        'order_index': 4,
        'effort_kind': 'set',
        'block_id': 'block-legacy',
        'created_at_ms': 100,
        'updated_at_ms': 200,
      });

      expect(obj.topLevelOrderIndex, 4);
      expect(obj.blockOrderIndex, 4);
    });
  });

  // ── MetricDefinition ──────────────────────────────────────────────────────

  group('MetricDefinition', () {
    test('fromMap coerces isCore from int to bool', () {
      final core = MetricDefinition.fromMap({
        'id': 'm-1',
        'key': 'reps',
        'name': 'Reps',
        'data_type': 'int',
        'is_core': 1,
        'created_at_ms': 100,
      });
      expect(core.isCore, true);

      final notCore = MetricDefinition.fromMap({
        'id': 'm-2',
        'key': 'vest',
        'name': 'Vest',
        'data_type': 'int',
        'is_core': 0,
        'created_at_ms': 100,
      });
      expect(notCore.isCore, false);
    });

    test('fromMap handles null isCore as false', () {
      final obj = MetricDefinition.fromMap({
        'id': 'm-1',
        'key': 'k',
        'name': 'n',
        'data_type': 'int',
        'created_at_ms': 100,
      });
      expect(obj.isCore, false);
    });
  });

  // ── EffortObservation ─────────────────────────────────────────────────────

  group('EffortObservation', () {
    test('fromMap coerces valueReal from int via num', () {
      final obj = EffortObservation.fromMap({
        'id': 'o-1',
        'effort_id': 'e-1',
        'metric_id': 'm-1',
        'value_real': 85,
        'created_at_ms': 100,
        'updated_at_ms': 200,
      });
      expect(obj.valueReal, 85.0);
      expect(obj.valueReal, isA<double>());
    });

    test('fromMap coerces valueBool from int', () {
      final trueObs = EffortObservation.fromMap({
        'id': 'o-1',
        'effort_id': 'e-1',
        'metric_id': 'm-1',
        'value_bool': 1,
        'created_at_ms': 100,
        'updated_at_ms': 200,
      });
      expect(trueObs.valueBool, true);

      final falseObs = EffortObservation.fromMap({
        'id': 'o-2',
        'effort_id': 'e-1',
        'metric_id': 'm-1',
        'value_bool': 0,
        'created_at_ms': 100,
        'updated_at_ms': 200,
      });
      expect(falseObs.valueBool, false);
    });

    test('fromMap null valueBool resolves to false (not null)', () {
      final obj = EffortObservation.fromMap({
        'id': 'o-1',
        'effort_id': 'e-1',
        'metric_id': 'm-1',
        'created_at_ms': 100,
        'updated_at_ms': 200,
      });
      // This is a known behavior: null in map becomes false, not null
      expect(obj.valueBool, false);
    });
  });

  // ── PlannedSession ────────────────────────────────────────────────────────

  group('PlannedSession', () {
    test('fromMap coerces isCompleted from int to bool', () {
      final completed = PlannedSession.fromMap({
        'id': 'p-1',
        'owner_user_id': 'u-1',
        'scheduled_date_ms': 1000,
        'is_completed': 1,
        'created_at_ms': 100,
        'updated_at_ms': 200,
      });
      expect(completed.isCompleted, true);

      final notCompleted = PlannedSession.fromMap({
        'id': 'p-2',
        'owner_user_id': 'u-1',
        'scheduled_date_ms': 1000,
        'is_completed': 0,
        'created_at_ms': 100,
        'updated_at_ms': 200,
      });
      expect(notCompleted.isCompleted, false);
    });

    test('fromMap handles null isCompleted as false', () {
      final obj = PlannedSession.fromMap({
        'id': 'p-1',
        'owner_user_id': 'u-1',
        'scheduled_date_ms': 1000,
        'created_at_ms': 100,
        'updated_at_ms': 200,
      });
      expect(obj.isCompleted, false);
    });
  });

  // ── TrainingPeriod ────────────────────────────────────────────────────────

  group('TrainingPeriod', () {
    test('fromMap parses focusModalities from CSV', () {
      final obj = TrainingPeriod.fromMap({
        'id': 'tp-1',
        'name': 'Competition Prep',
        'start_date_ms': 1000,
        'end_date_ms': 5000,
        'focus_modalities_csv': 'resistance_lifting,cardio_endurance',
        'created_at_ms': 100,
        'updated_at_ms': 200,
      });
      expect(obj.focusModalities, ['resistance_lifting', 'cardio_endurance']);
    });

    test('fromMap handles empty CSV as empty list', () {
      final obj = TrainingPeriod.fromMap({
        'id': 'tp-1',
        'name': 'Rest Week',
        'start_date_ms': 1000,
        'end_date_ms': 5000,
        'focus_modalities_csv': '',
        'created_at_ms': 100,
        'updated_at_ms': 200,
      });
      expect(obj.focusModalities, isEmpty);
    });

    test('fromMap handles null CSV as empty list', () {
      final obj = TrainingPeriod.fromMap({
        'id': 'tp-1',
        'name': 'Rest Week',
        'start_date_ms': 1000,
        'end_date_ms': 5000,
        'created_at_ms': 100,
        'updated_at_ms': 200,
      });
      expect(obj.focusModalities, isEmpty);
    });

    test('toMap serializes focusModalities as CSV', () {
      final obj = TrainingPeriod(
        id: 'tp-1',
        name: 'Prep',
        startDateMs: 1000,
        endDateMs: 5000,
        focusModalities: ['cardio_endurance', 'sports_martial_arts'],
        createdAtMs: 100,
        updatedAtMs: 200,
      );
      expect(
        obj.toMap()['focus_modalities_csv'],
        'cardio_endurance,sports_martial_arts',
      );
    });

    test('toMap serializes empty focusModalities as empty string', () {
      final obj = TrainingPeriod(
        id: 'tp-1',
        name: 'Prep',
        startDateMs: 1000,
        endDateMs: 5000,
        createdAtMs: 100,
        updatedAtMs: 200,
      );
      expect(obj.toMap()['focus_modalities_csv'], '');
    });

    test('single modality CSV round-trip', () {
      final map = {
        'id': 'tp-1',
        'name': 'Prep',
        'start_date_ms': 1000,
        'end_date_ms': 5000,
        'focus_modalities_csv': 'resistance_lifting',
        'created_at_ms': 100,
        'updated_at_ms': 200,
      };
      final obj = TrainingPeriod.fromMap(map);
      expect(obj.focusModalities, ['resistance_lifting']);

      final result = obj.toMap();
      expect(result['focus_modalities_csv'], 'resistance_lifting');
    });
  });

  // ── RoundInstance ─────────────────────────────────────────────────────────

  group('RoundInstance', () {
    test('fromMap/toMap round-trip preserves all fields', () {
      final map = {
        'id': 'r-1',
        'effort_id': 'e-1',
        'round_index': 0,
        'planned_duration_secs': 180,
        'actual_duration_secs': 175,
        'started_at_ms': 1000,
        'finished_at_ms': 176000,
        'completed': 1,
        'state': 'finished',
        'paused_at_ms': null,
        'total_paused_duration_ms': 5000,
        'created_at_ms': 100,
        'updated_at_ms': 200,
      };
      final obj = RoundInstance.fromMap(map);
      final result = obj.toMap();
      expect(result['id'], 'r-1');
      expect(result['planned_duration_secs'], 180);
      expect(result['actual_duration_secs'], 175);
      expect(result['completed'], 1);
      expect(result['state'], 'finished');
      expect(result['total_paused_duration_ms'], 5000);
    });

    test('fromMap defaults missing fields correctly', () {
      final map = {
        'id': 'r-1',
        'effort_id': 'e-1',
        'round_index': 0,
        'created_at_ms': 100,
        'updated_at_ms': 200,
      };
      final obj = RoundInstance.fromMap(map);
      expect(obj.plannedDurationSecs, 180); // default
      expect(obj.actualDurationSecs, 0);
      expect(obj.startedAtMs, 0);
      expect(obj.completed, false);
      expect(obj.totalPausedDurationMs, 0);
      expect(obj.state, RoundState.notStarted);
    });

    test('_stateFromMap infers finished from timestamps when state column missing', () {
      final map = {
        'id': 'r-1',
        'effort_id': 'e-1',
        'round_index': 0,
        'finished_at_ms': 5000,
        'started_at_ms': 1000,
        'created_at_ms': 100,
        'updated_at_ms': 200,
      };
      final obj = RoundInstance.fromMap(map);
      expect(obj.state, RoundState.finished);
    });

    test('_stateFromMap infers active from startedAtMs when state column missing', () {
      final map = {
        'id': 'r-1',
        'effort_id': 'e-1',
        'round_index': 0,
        'started_at_ms': 1000,
        'created_at_ms': 100,
        'updated_at_ms': 200,
      };
      final obj = RoundInstance.fromMap(map);
      expect(obj.state, RoundState.active);
    });

    test('_stateFromMap infers notStarted when no timestamps and no state', () {
      final map = {
        'id': 'r-1',
        'effort_id': 'e-1',
        'round_index': 0,
        'started_at_ms': 0,
        'created_at_ms': 100,
        'updated_at_ms': 200,
      };
      final obj = RoundInstance.fromMap(map);
      expect(obj.state, RoundState.notStarted);
    });

    test('_stateFromMap uses explicit state when present', () {
      final map = {
        'id': 'r-1',
        'effort_id': 'e-1',
        'round_index': 0,
        'state': 'paused',
        'started_at_ms': 1000,
        'created_at_ms': 100,
        'updated_at_ms': 200,
      };
      final obj = RoundInstance.fromMap(map);
      expect(obj.state, RoundState.paused);
    });

    test('copyWith sentinel allows setting finishedAtMs to null', () {
      final obj = RoundInstance(
        id: 'r-1',
        effortId: 'e-1',
        roundIndex: 0,
        finishedAtMs: 5000,
        createdAtMs: 100,
        updatedAtMs: 200,
      );
      final updated = obj.copyWith(finishedAtMs: null);
      expect(updated.finishedAtMs, isNull);
    });

    test('copyWith without finishedAtMs preserves existing value', () {
      final obj = RoundInstance(
        id: 'r-1',
        effortId: 'e-1',
        roundIndex: 0,
        finishedAtMs: 5000,
        createdAtMs: 100,
        updatedAtMs: 200,
      );
      final updated = obj.copyWith(completed: true);
      expect(updated.finishedAtMs, 5000);
    });

    test('copyWith sentinel allows setting pausedAtMs to null', () {
      final obj = RoundInstance(
        id: 'r-1',
        effortId: 'e-1',
        roundIndex: 0,
        pausedAtMs: 3000,
        createdAtMs: 100,
        updatedAtMs: 200,
      );
      final updated = obj.copyWith(pausedAtMs: null);
      expect(updated.pausedAtMs, isNull);
    });

    test('elapsedMs returns 0 when notStarted', () {
      final obj = RoundInstance(
        id: 'r-1',
        effortId: 'e-1',
        roundIndex: 0,
        state: RoundState.notStarted,
        startedAtMs: 0,
        createdAtMs: 100,
        updatedAtMs: 200,
      );
      expect(obj.elapsedMs, 0);
    });

    test('elapsedMs returns actualDurationSecs * 1000 when finished', () {
      final obj = RoundInstance(
        id: 'r-1',
        effortId: 'e-1',
        roundIndex: 0,
        state: RoundState.finished,
        actualDurationSecs: 120,
        startedAtMs: 1000,
        createdAtMs: 100,
        updatedAtMs: 200,
      );
      expect(obj.elapsedMs, 120000);
    });

    test('elapsedMs uses pausedAtMs as reference when paused', () {
      final obj = RoundInstance(
        id: 'r-1',
        effortId: 'e-1',
        roundIndex: 0,
        state: RoundState.paused,
        startedAtMs: 1000,
        pausedAtMs: 61000,
        totalPausedDurationMs: 0,
        plannedDurationSecs: 180,
        createdAtMs: 100,
        updatedAtMs: 200,
      );
      expect(obj.elapsedMs, 60000); // 61000 - 1000 - 0 = 60000
    });

    test('remainingMs is planned minus elapsed', () {
      final obj = RoundInstance(
        id: 'r-1',
        effortId: 'e-1',
        roundIndex: 0,
        state: RoundState.finished,
        actualDurationSecs: 120,
        plannedDurationSecs: 180,
        startedAtMs: 1000,
        createdAtMs: 100,
        updatedAtMs: 200,
      );
      expect(obj.remainingMs, 60000); // 180000 - 120000
    });

    test('remainingMs clamps to 0 when elapsed exceeds planned', () {
      final obj = RoundInstance(
        id: 'r-1',
        effortId: 'e-1',
        roundIndex: 0,
        state: RoundState.finished,
        actualDurationSecs: 200,
        plannedDurationSecs: 180,
        startedAtMs: 1000,
        createdAtMs: 100,
        updatedAtMs: 200,
      );
      expect(obj.remainingMs, 0);
    });
  });

  // ── TimedInstance ─────────────────────────────────────────────────────────

  group('TimedInstance', () {
    test('fromMap/toMap round-trip preserves all fields', () {
      final map = {
        'id': 't-1',
        'effort_id': 'e-1',
        'entry_index': 0,
        'target_duration_secs': 300,
        'actual_duration_secs': 295,
        'started_at_ms': 1000,
        'finished_at_ms': 296000,
        'state': 'finished',
        'paused_at_ms': null,
        'total_paused_duration_ms': 0,
        'created_at_ms': 100,
        'updated_at_ms': 200,
      };
      final obj = TimedInstance.fromMap(map);
      final result = obj.toMap();
      expect(result['id'], 't-1');
      expect(result['target_duration_secs'], 300);
      expect(result['state'], 'finished');
    });

    test('_stateFromMap backward-compat inference', () {
      // Finished: has finished_at_ms
      final finished = TimedInstance.fromMap({
        'id': 't-1',
        'effort_id': 'e-1',
        'entry_index': 0,
        'finished_at_ms': 5000,
        'started_at_ms': 1000,
        'created_at_ms': 100,
        'updated_at_ms': 200,
      });
      expect(finished.state, TimedState.finished);

      // Active: has started_at_ms > 0 but no finished_at_ms
      final active = TimedInstance.fromMap({
        'id': 't-2',
        'effort_id': 'e-1',
        'entry_index': 0,
        'started_at_ms': 1000,
        'created_at_ms': 100,
        'updated_at_ms': 200,
      });
      expect(active.state, TimedState.active);

      // NotStarted: started_at_ms = 0
      final notStarted = TimedInstance.fromMap({
        'id': 't-3',
        'effort_id': 'e-1',
        'entry_index': 0,
        'started_at_ms': 0,
        'created_at_ms': 100,
        'updated_at_ms': 200,
      });
      expect(notStarted.state, TimedState.notStarted);
    });

    test('copyWith sentinel allows setting finishedAtMs to null', () {
      final obj = TimedInstance(
        id: 't-1',
        effortId: 'e-1',
        entryIndex: 0,
        finishedAtMs: 5000,
        createdAtMs: 100,
        updatedAtMs: 200,
      );
      final updated = obj.copyWith(finishedAtMs: null);
      expect(updated.finishedAtMs, isNull);
    });

    test('elapsedMs returns 0 when notStarted', () {
      final obj = TimedInstance(
        id: 't-1',
        effortId: 'e-1',
        entryIndex: 0,
        state: TimedState.notStarted,
        startedAtMs: 0,
        createdAtMs: 100,
        updatedAtMs: 200,
      );
      expect(obj.elapsedMs, 0);
    });

    test('elapsedMs returns actualDurationSecs * 1000 when finished', () {
      final obj = TimedInstance(
        id: 't-1',
        effortId: 'e-1',
        entryIndex: 0,
        state: TimedState.finished,
        actualDurationSecs: 300,
        startedAtMs: 1000,
        createdAtMs: 100,
        updatedAtMs: 200,
      );
      expect(obj.elapsedMs, 300000);
    });

    test('elapsedMs clamped to 24 hours', () {
      // Set startedAtMs far in the past so elapsed would exceed 24h
      final now = DateTime.now().millisecondsSinceEpoch;
      final twoDaysAgo = now - 2 * 86400000;
      final obj = TimedInstance(
        id: 't-1',
        effortId: 'e-1',
        entryIndex: 0,
        state: TimedState.active,
        startedAtMs: twoDaysAgo,
        totalPausedDurationMs: 0,
        createdAtMs: 100,
        updatedAtMs: 200,
      );
      expect(obj.elapsedMs, 86400000);
    });

    test('fromMap defaults targetDurationSecs to 0', () {
      final map = {
        'id': 't-1',
        'effort_id': 'e-1',
        'entry_index': 0,
        'created_at_ms': 100,
        'updated_at_ms': 200,
      };
      final obj = TimedInstance.fromMap(map);
      expect(obj.targetDurationSecs, 0);
    });
  });

  // ── EntryRest ─────────────────────────────────────────────────────────────

  group('EntryRest', () {
    test('fromMap/toMap round-trip', () {
      final map = {
        'id': 'er-1',
        'effort_id': 'e-1',
        'entry_index': 2,
        'rest_start_ms': 1000,
        'rest_end_ms': 61000,
        'created_at_ms': 100,
        'updated_at_ms': 200,
      };
      final obj = EntryRest.fromMap(map);
      expect(obj.entryIndex, 2);
      expect(obj.restStartMs, 1000);
      expect(obj.restEndMs, 61000);

      final result = obj.toMap();
      expect(result['entry_index'], 2);
      expect(result['rest_start_ms'], 1000);
      expect(result['rest_end_ms'], 61000);
    });

    test('elapsedSeconds uses restEndMs when available', () {
      final obj = EntryRest(
        id: 'er-1',
        effortId: 'e-1',
        entryIndex: 0,
        restStartMs: 1000,
        restEndMs: 61000,
        createdAtMs: 100,
        updatedAtMs: 200,
      );
      expect(obj.elapsedSeconds(999999), 60); // uses restEndMs, not nowMs
    });

    test('elapsedSeconds uses nowMs when restEndMs is null (open rest)', () {
      final obj = EntryRest(
        id: 'er-1',
        effortId: 'e-1',
        entryIndex: 0,
        restStartMs: 1000,
        restEndMs: null,
        createdAtMs: 100,
        updatedAtMs: 200,
      );
      expect(obj.elapsedSeconds(31000), 30); // (31000 - 1000) / 1000
    });

    test('elapsedSeconds clamps to 0 minimum', () {
      final obj = EntryRest(
        id: 'er-1',
        effortId: 'e-1',
        entryIndex: 0,
        restStartMs: 50000,
        restEndMs: 1000,
        createdAtMs: 100,
        updatedAtMs: 200,
      );
      expect(obj.elapsedSeconds(0), 0);
    });

    test('elapsedSeconds clamps to 99999 maximum', () {
      final obj = EntryRest(
        id: 'er-1',
        effortId: 'e-1',
        entryIndex: 0,
        restStartMs: 0,
        restEndMs: 200000000,
        createdAtMs: 100,
        updatedAtMs: 200,
      );
      expect(obj.elapsedSeconds(0), 99999);
    });

    test('copyWith sentinel allows setting restEndMs to null', () {
      final obj = EntryRest(
        id: 'er-1',
        effortId: 'e-1',
        entryIndex: 0,
        restStartMs: 1000,
        restEndMs: 5000,
        createdAtMs: 100,
        updatedAtMs: 200,
      );
      final updated = obj.copyWith(restEndMs: null);
      expect(updated.restEndMs, isNull);
    });

    test('copyWith without restEndMs preserves existing value', () {
      final obj = EntryRest(
        id: 'er-1',
        effortId: 'e-1',
        entryIndex: 0,
        restStartMs: 1000,
        restEndMs: 5000,
        createdAtMs: 100,
        updatedAtMs: 200,
      );
      final updated = obj.copyWith(entryIndex: 3);
      expect(updated.restEndMs, 5000);
      expect(updated.entryIndex, 3);
    });
  });

  // ── ExerciseNote ──────────────────────────────────────────────────────────

  group('ExerciseNote', () {
    test('fromMap/toMap round-trip', () {
      final map = {
        'id': 'n-1',
        'exercise_id': 'ex-1',
        'note': 'Drive through heels',
        'last_session_id': 's-1',
        'created_at_ms': 100,
        'updated_at_ms': 200,
      };
      final obj = ExerciseNote.fromMap(map);
      final result = obj.toMap();
      expect(result['note'], 'Drive through heels');
      expect(result['last_session_id'], 's-1');
    });

    test('copyWith sentinel allows setting lastSessionId to null', () {
      final obj = ExerciseNote(
        id: 'n-1',
        exerciseId: 'ex-1',
        note: 'Test',
        lastSessionId: 's-1',
        createdAtMs: 100,
        updatedAtMs: 200,
      );
      final updated = obj.copyWith(lastSessionId: null);
      expect(updated.lastSessionId, isNull);
    });

    test('copyWith preserves lastSessionId when not provided', () {
      final obj = ExerciseNote(
        id: 'n-1',
        exerciseId: 'ex-1',
        note: 'Test',
        lastSessionId: 's-1',
        createdAtMs: 100,
        updatedAtMs: 200,
      );
      final updated = obj.copyWith(note: 'Updated');
      expect(updated.lastSessionId, 's-1');
      expect(updated.note, 'Updated');
    });
  });

  // ── TemplateSegment & TemplateTarget updatedAtMs fallback ─────────────────

  group('TemplateSegment', () {
    test('fromMap falls back updatedAtMs to createdAtMs when missing', () {
      final obj = TemplateSegment.fromMap({
        'id': 'ts-1',
        'template_id': 't-1',
        'order_index': 0,
        'segment_type': 'normal',
        'created_at_ms': 5000,
      });
      expect(obj.updatedAtMs, 5000);
    });

    test('fromMap uses updatedAtMs when present', () {
      final obj = TemplateSegment.fromMap({
        'id': 'ts-1',
        'template_id': 't-1',
        'order_index': 0,
        'segment_type': 'normal',
        'created_at_ms': 5000,
        'updated_at_ms': 7000,
      });
      expect(obj.updatedAtMs, 7000);
    });
  });

  group('TemplateTarget', () {
    test('fromMap coerces targetMin/targetMax from int via num', () {
      final obj = TemplateTarget.fromMap({
        'id': 'tt-1',
        'template_effort_id': 'te-1',
        'metric_id': 'm-1',
        'set_index': 0,
        'target_min': 8,
        'target_max': 12,
        'created_at_ms': 100,
        'updated_at_ms': 200,
      });
      expect(obj.targetMin, 8.0);
      expect(obj.targetMax, 12.0);
    });

    test('fromMap falls back updatedAtMs to createdAtMs', () {
      final obj = TemplateTarget.fromMap({
        'id': 'tt-1',
        'template_effort_id': 'te-1',
        'metric_id': 'm-1',
        'set_index': 0,
        'created_at_ms': 100,
      });
      expect(obj.updatedAtMs, 100);
    });
  });

  // ── BodyMeasurementEntry ──────────────────────────────────────────────────

  group('BodyMeasurementEntry', () {
    test('fromMap coerces value from int via num', () {
      final obj = BodyMeasurementEntry.fromMap({
        'id': 'bm-1',
        'measurement_type': 'bodyweight',
        'value': 82,
        'unit_id': 'unit-kg',
        'recorded_at_ms': 1000,
      });
      expect(obj.value, 82.0);
      expect(obj.value, isA<double>());
    });
  });

  // ── NutritionTarget ──────────────────────────────────────────────────────

  group('NutritionTarget', () {
    test('fromMap/toMap round-trip preserves all fields', () {
      final obj = NutritionTarget(
        calories: 2500,
        protein: 180,
        carbs: 300,
        fat: 80,
        dateMs: 1749312000000,
      );
      final map = obj.toMap();
      expect(map['calories'], 2500);
      expect(map['protein'], 180);
      expect(map['carbs'], 300);
      expect(map['fat'], 80);
      expect(map['date_ms'], 1749312000000);

      final restored = NutritionTarget.fromMap(map);
      expect(restored.calories, 2500);
      expect(restored.protein, 180);
      expect(restored.carbs, 300);
      expect(restored.fat, 80);
      expect(restored.dateMs, 1749312000000);
    });

    test('defaults are 0.0 (not nullable) when constructed empty', () {
      final obj = NutritionTarget();
      expect(obj.calories, 0.0);
      expect(obj.protein, 0.0);
      expect(obj.carbs, 0.0);
      expect(obj.fat, 0.0);
      expect(obj.dateMs, isNull);
    });

    test('fromMap defaults missing fields to 0.0', () {
      final obj = NutritionTarget.fromMap(const {});
      expect(obj.calories, 0.0);
      expect(obj.protein, 0.0);
      expect(obj.carbs, 0.0);
      expect(obj.fat, 0.0);
      expect(obj.dateMs, isNull);
    });

    test('fromMap accepts int values for numeric fields via num cast', () {
      // Hive stores everything as `dynamic`; ints are a valid input form.
      final obj = NutritionTarget.fromMap({
        'calories': 2500,
        'protein': 180,
        'carbs': 300,
        'fat': 80,
      });
      expect(obj.calories, 2500.0);
      expect(obj.protein, 180.0);
    });

    test('isUnset is true only when all macros are 0', () {
      expect(NutritionTarget().isUnset, isTrue);
      expect(
        NutritionTarget(calories: 0, protein: 0, carbs: 0, fat: 0).isUnset,
        isTrue,
      );
      expect(NutritionTarget(calories: 1).isUnset, isFalse);
      expect(NutritionTarget(protein: 1).isUnset, isFalse);
      expect(NutritionTarget(carbs: 1).isUnset, isFalse);
      expect(NutritionTarget(fat: 1).isUnset, isFalse);
    });

    test('copyWith updates only the provided fields', () {
      final base = NutritionTarget(
        calories: 2000,
        protein: 100,
        carbs: 200,
        fat: 60,
        dateMs: 1000,
      );
      final updated = base.copyWith(calories: 2500);
      expect(updated.calories, 2500);
      expect(updated.protein, 100);
      expect(updated.carbs, 200);
      expect(updated.fat, 60);
      expect(updated.dateMs, 1000);
    });

    test('legacy round-trip (dateMs omitted) is null', () {
      // The legacy single-row target never had a date_ms; round-tripping an
      // explicit dateMs=missing must produce a null dateMs.
      final obj = NutritionTarget(calories: 2000, protein: 100);
      final map = obj.toMap();
      expect(map.containsKey('date_ms'), isTrue);
      expect(map['date_ms'], isNull);
      final restored = NutritionTarget.fromMap(map);
      expect(restored.dateMs, isNull);
    });
  });

  // ── Food (June 2026 — imagePath + fiber round-trip) ─────────────────────

  group('Food', () {
    Food baseFood({String? imagePath}) => Food(
          id: 'food-1',
          name: 'Chicken breast, skinless',
          unitType: FoodUnitType.grams,
          referenceAmount: 100,
          referenceLabel: 'g',
          protein: 31,
          carbs: 0,
          fiber: 0,
          fat: 4,
          imagePath: imagePath,
          createdAtMs: 1700000000000,
          updatedAtMs: 1700000000000,
        );

    test('imagePath round-trips through fromMap/toMap', () {
      final obj = baseFood(imagePath: '/tmp/photos/chicken.jpg');
      final map = obj.toMap();
      expect(map['image_path'], '/tmp/photos/chicken.jpg');

      final restored = Food.fromMap(map);
      expect(restored.imagePath, '/tmp/photos/chicken.jpg');
    });

    test('imagePath null round-trips as null', () {
      final obj = baseFood();
      final map = obj.toMap();
      expect(map['image_path'], isNull);

      final restored = Food.fromMap(map);
      expect(restored.imagePath, isNull);
    });

    test('fromMap handles missing image_path as null (legacy row)', () {
      final map = <String, dynamic>{
        'id': 'food-1',
        'name': 'Chicken breast, skinless',
        'unit_type': 'grams',
        'reference_amount': 100,
        'reference_label': 'g',
        'is_catalog': 0,
        'protein': 31,
        'carbs': 0,
        'fiber': 0,
        'fat': 4,
        'is_archived': 0,
        'created_at_ms': 1700000000000,
        'updated_at_ms': 1700000000000,
      };
      final restored = Food.fromMap(map);
      expect(restored.imagePath, isNull);
    });

    test('copyWith sentinel allows clearing imagePath', () {
      final withImage = baseFood(imagePath: '/tmp/photos/x.jpg');
      final cleared = withImage.copyWith(imagePath: null);
      expect(cleared.imagePath, isNull);
    });

    test('copyWith without imagePath preserves existing value', () {
      final withImage = baseFood(imagePath: '/tmp/photos/x.jpg');
      final same = withImage.copyWith(name: 'Renamed');
      expect(same.imagePath, '/tmp/photos/x.jpg');
      expect(same.name, 'Renamed');
    });

    test('fiber round-trips through fromMap/toMap', () {
      final obj = baseFood().copyWith(carbs: 20, fiber: 5);
      final map = obj.toMap();
      expect(map['fiber'], 5);

      final restored = Food.fromMap(map);
      expect(restored.fiber, 5);
      expect(restored.carbs, 20);
    });
  });
}
