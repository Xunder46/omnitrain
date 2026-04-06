import 'package:test/test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';

void main() {
  group('Session blocks repository behavior (mock)', () {
    late MockWorkoutRepository repository;

    setUp(() async {
      repository = MockWorkoutRepository();
      await repository.initialize();
    });

    test('updateSessionFeeling preserves isRolling', () async {
      final sessionId = await repository.createSession(
        TrainingSession(
          id: 'session-rolling',
          ownerUserId: 'local-user',
          startedAtMs: 1000,
          isRolling: true,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );

      await repository.updateSessionFeeling(sessionId, 4);
      final updated = await repository.getSession(sessionId);

      expect(updated, isNotNull);
      expect(updated!.sessionFeeling, 4);
      expect(updated.isRolling, isTrue);
    });

    test('deleteSessionBlock nulls blockId on linked efforts', () async {
      await repository.createSession(
        TrainingSession(
          id: 'session-a',
          ownerUserId: 'local-user',
          startedAtMs: 1000,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );

      await repository.createSegment(
        SessionSegment(
          id: 'segment-a',
          sessionId: 'session-a',
          orderIndex: 0,
          segmentType: 'mixed',
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );

      await repository.createSessionBlock(
        SessionBlock(
          id: 'block-a',
          sessionId: 'session-a',
          name: 'Main',
          orderIndex: 0,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );

      await repository.createEffort(
        SegmentEffort(
          id: 'effort-a',
          segmentId: 'segment-a',
          orderIndex: 0,
          effortKind: 'set',
          blockId: 'block-a',
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );

      await repository.deleteSessionBlock('block-a');

      final efforts = await repository.getSegmentEfforts('segment-a');
      expect(efforts, hasLength(1));
      expect(efforts.first.blockId, isNull);
    });

    test('reorderSessionBlocks only updates matching session IDs', () async {
      await repository.createSessionBlock(
        SessionBlock(
          id: 'block-a1',
          sessionId: 'session-a',
          name: 'A1',
          orderIndex: 0,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );
      await repository.createSessionBlock(
        SessionBlock(
          id: 'block-a2',
          sessionId: 'session-a',
          name: 'A2',
          orderIndex: 1,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );
      await repository.createSessionBlock(
        SessionBlock(
          id: 'block-b1',
          sessionId: 'session-b',
          name: 'B1',
          orderIndex: 5,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );

      await repository.reorderSessionBlocks('session-a', [
        'block-b1',
        'block-a2',
        'block-a1',
      ]);

      final aBlocks = await repository.getSessionBlocks('session-a');
      final bBlocks = await repository.getSessionBlocks('session-b');

      expect(aBlocks.map((b) => b.id).toList(), ['block-a2', 'block-a1']);
      expect(aBlocks.map((b) => b.orderIndex).toList(), [1, 2]);
      expect(bBlocks.single.orderIndex, 5);
    });

    test('deleteSession removes blocks for that session', () async {
      await repository.createSession(
        TrainingSession(
          id: 'session-delete',
          ownerUserId: 'local-user',
          startedAtMs: 1000,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );

      await repository.createSessionBlock(
        SessionBlock(
          id: 'block-delete',
          sessionId: 'session-delete',
          name: 'Delete me',
          orderIndex: 0,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );

      await repository.createSessionBlock(
        SessionBlock(
          id: 'block-keep',
          sessionId: 'other-session',
          name: 'Keep me',
          orderIndex: 0,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );

      await repository.deleteSession('session-delete');

      final deletedBlocks = await repository.getSessionBlocks('session-delete');
      final remainingBlocks = await repository.getSessionBlocks(
        'other-session',
      );

      expect(deletedBlocks, isEmpty);
      expect(remainingBlocks, hasLength(1));
      expect(remainingBlocks.first.id, 'block-keep');
    });

    test('cloneSessionBlock deep-copies effort graph with new IDs', () async {
      await repository.createSession(
        TrainingSession(
          id: 'session-clone',
          ownerUserId: 'local-user',
          startedAtMs: 1000,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );

      await repository.createSegment(
        SessionSegment(
          id: 'segment-clone',
          sessionId: 'session-clone',
          orderIndex: 0,
          segmentType: 'mixed',
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );

      await repository.createSessionBlock(
        SessionBlock(
          id: 'block-clone-source',
          sessionId: 'session-clone',
          name: 'Source',
          orderIndex: 0,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );

      await repository.createEffort(
        SegmentEffort(
          id: 'effort-source',
          segmentId: 'segment-clone',
          orderIndex: 0,
          effortKind: 'round',
          blockId: 'block-clone-source',
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );

      await repository.createObservation(
        EffortObservation(
          id: 'obs-source',
          effortId: 'effort-source',
          metricId: 'metric-reps',
          valueInt: 10,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );

      await repository.createRoundInstance(
        RoundInstance(
          id: 'round-source',
          effortId: 'effort-source',
          roundIndex: 0,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );

      await repository.createTimedInstance(
        TimedInstance(
          id: 'timed-source',
          effortId: 'effort-source',
          entryIndex: 0,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );

      await repository.createEntryRest(
        EntryRest(
          id: 'rest-source',
          effortId: 'effort-source',
          entryIndex: 0,
          restStartMs: 1000,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );

      final newBlockId = await repository.cloneSessionBlock(
        'block-clone-source',
      );

      final blocks = await repository.getSessionBlocks('session-clone');
      expect(blocks, hasLength(2));
      final clonedBlock = blocks.firstWhere((b) => b.id == newBlockId);
      // Cloned block should have current-time name like "10:20 PM", not original name
      expect(clonedBlock.name, matches(RegExp(r'^\d{1,2}:\d{2} [AP]M$')));
      expect(clonedBlock.id, isNot('block-clone-source'));

      final efforts = await repository.getSegmentEfforts('segment-clone');
      expect(efforts, hasLength(2));
      final clonedEffort = efforts.firstWhere((e) => e.blockId == newBlockId);
      expect(clonedEffort.id, isNot('effort-source'));

      final clonedObservations = await repository.getEffortObservations(
        clonedEffort.id,
      );
      expect(clonedObservations, hasLength(1));
      expect(clonedObservations.first.id, isNot('obs-source'));
      expect(clonedObservations.first.valueInt, 0);
      expect(clonedObservations.first.valueReal, 0.0);
      expect(clonedObservations.first.valueText, isNull);
      expect(clonedObservations.first.valueBool, isNull);
      expect(clonedObservations.first.rpeRating, isNull);
      expect(clonedObservations.first.restDurationMs, isNull);

      final clonedRounds = await repository.getRoundInstances(clonedEffort.id);
      expect(clonedRounds, hasLength(1));
      expect(clonedRounds.first.id, isNot('round-source'));
      expect(clonedRounds.first.actualDurationSecs, 0);
      expect(clonedRounds.first.startedAtMs, 0);
      expect(clonedRounds.first.finishedAtMs, isNull);
      expect(clonedRounds.first.completed, isFalse);
      expect(clonedRounds.first.state, RoundState.notStarted);
      expect(clonedRounds.first.pausedAtMs, isNull);
      expect(clonedRounds.first.totalPausedDurationMs, 0);

      final clonedTimed = await repository.getTimedInstances(clonedEffort.id);
      expect(clonedTimed, hasLength(1));
      expect(clonedTimed.first.id, isNot('timed-source'));
      expect(clonedTimed.first.actualDurationSecs, 0);
      expect(clonedTimed.first.startedAtMs, 0);
      expect(clonedTimed.first.finishedAtMs, isNull);
      expect(clonedTimed.first.state, TimedState.notStarted);
      expect(clonedTimed.first.pausedAtMs, isNull);
      expect(clonedTimed.first.totalPausedDurationMs, 0);

      final clonedRests = await repository.getEntryRests(clonedEffort.id);
      expect(clonedRests, isEmpty);
    });
  });
}
