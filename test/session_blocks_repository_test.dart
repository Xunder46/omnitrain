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

    test('deleteSessionBlock cascade-deletes linked efforts', () async {
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
      expect(efforts, isEmpty);
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
      // Cloned block should use "(2)" suffix notation
      expect(clonedBlock.name, 'Source (2)');
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

    test('cloneSessionBlock uses incremental (2)/(3) suffix naming', () async {
      await repository.createSession(
        TrainingSession(
          id: 'session-naming',
          ownerUserId: 'local-user',
          startedAtMs: 1000,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );

      await repository.createSessionBlock(
        SessionBlock(
          id: 'block-main',
          sessionId: 'session-naming',
          name: 'Main',
          orderIndex: 0,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );

      // First clone: "Main" → "Main (2)"
      final clone2Id = await repository.cloneSessionBlock('block-main');
      final blocksAfterFirst = await repository.getSessionBlocks('session-naming');
      final clone2 = blocksAfterFirst.firstWhere((b) => b.id == clone2Id);
      expect(clone2.name, 'Main (2)');

      // Second clone of (2): "Main (2)" → "Main (3)"
      final clone3Id = await repository.cloneSessionBlock(clone2Id);
      final blocksAfterSecond = await repository.getSessionBlocks('session-naming');
      final clone3 = blocksAfterSecond.firstWhere((b) => b.id == clone3Id);
      expect(clone3.name, 'Main (3)');
    });

    test('cloneSessionBlock in rolling session uses current-time title', () async {
      await repository.createSession(
        TrainingSession(
          id: 'session-rolling-clone',
          ownerUserId: 'local-user',
          startedAtMs: 1000,
          isRolling: true,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );

      await repository.createSessionBlock(
        SessionBlock(
          id: 'block-time-source',
          sessionId: 'session-rolling-clone',
          name: '10:00 AM',
          orderIndex: 0,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );

      final cloneId = await repository.cloneSessionBlock('block-time-source');
      final blocks = await repository.getSessionBlocks('session-rolling-clone');
      final cloned = blocks.firstWhere((b) => b.id == cloneId);

      expect(cloned.name, isNot(contains('(2)')));
      expect(cloned.name, matches(RegExp(r'^\d{1,2}:\d{2} (AM|PM)$')));
    });
  });
}
