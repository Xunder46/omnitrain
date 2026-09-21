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
          modality: 'resistance_lifting',
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
      expect(clonedBlock.name, isNot(contains('(2)')));
      expect(clonedBlock.name, matches(RegExp(r'^\d{1,2}:\d{2} (AM|PM)$')));
      expect(clonedBlock.id, isNot('block-clone-source'));
      final maxTopLevelOrder = blocks
          .map((block) => block.topLevelOrderIndex ?? block.orderIndex)
          .reduce((a, b) => a > b ? a : b);
      expect(
        clonedBlock.topLevelOrderIndex ?? clonedBlock.orderIndex,
        maxTopLevelOrder,
      );

      final efforts = await repository.getSegmentEfforts('segment-clone');
      expect(efforts, hasLength(2));
      final clonedEffort = efforts.firstWhere((e) => e.blockId == newBlockId);
      expect(clonedEffort.id, isNot('effort-source'));

      final clonedObservations = await repository.getEffortObservations(
        clonedEffort.id,
      );
      expect(clonedObservations, hasLength(1));
      expect(clonedObservations.first.id, isNot('obs-source'));
      // Values must be preserved from the source — not reset to zero.
      expect(clonedObservations.first.valueInt, 10);
      expect(clonedObservations.first.valueReal, isNull);
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

    test('cloneSessionBlock preserves exact internal exercise order', () async {
      await repository.createSession(
        TrainingSession(
          id: 'session-order-clone',
          ownerUserId: 'local-user',
          startedAtMs: 1000,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );

      await repository.createSegment(
        SessionSegment(
          id: 'segment-order-clone',
          sessionId: 'session-order-clone',
          orderIndex: 0,
          segmentType: 'mixed',
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );

      await repository.createSessionBlock(
        SessionBlock(
          id: 'block-source-order',
          sessionId: 'session-order-clone',
          name: 'Source',
          orderIndex: 0,
          topLevelOrderIndex: 0,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );

      final exercises = await repository.getExercises();
      final sourceExerciseIds = [
        exercises[0].id,
        exercises[1].id,
        exercises[2].id,
      ];

      for (var i = 0; i < sourceExerciseIds.length; i++) {
        await repository.createEffort(
          SegmentEffort(
            id: 'src-eff-$i',
            segmentId: 'segment-order-clone',
            orderIndex: i,
            topLevelOrderIndex: 0,
            blockOrderIndex: i,
            effortKind: 'set',
            exerciseId: sourceExerciseIds[i],
            blockId: 'block-source-order',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
      }

      final cloneId = await repository.cloneSessionBlock('block-source-order');

      final efforts = await repository.getSegmentEfforts('segment-order-clone');
      final clonedExerciseIds = efforts
          .where((effort) => effort.blockId == cloneId)
          .map((effort) => effort.exerciseId)
          .toList();

      expect(clonedExerciseIds, sourceExerciseIds);
    });

    test('repeated block clones keep identical internal ordering', () async {
      await repository.createSession(
        TrainingSession(
          id: 'session-repeat-clone',
          ownerUserId: 'local-user',
          startedAtMs: 1000,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );

      await repository.createSegment(
        SessionSegment(
          id: 'segment-repeat-clone',
          sessionId: 'session-repeat-clone',
          orderIndex: 0,
          segmentType: 'mixed',
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );

      await repository.createSessionBlock(
        SessionBlock(
          id: 'block-repeat-source',
          sessionId: 'session-repeat-clone',
          name: 'Source',
          orderIndex: 0,
          topLevelOrderIndex: 0,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );

      final exercises = await repository.getExercises();
      final sourceExerciseIds = [
        exercises[0].id,
        exercises[2].id,
        exercises[1].id,
      ];

      for (var i = 0; i < sourceExerciseIds.length; i++) {
        await repository.createEffort(
          SegmentEffort(
            id: 'repeat-src-eff-$i',
            segmentId: 'segment-repeat-clone',
            orderIndex: i,
            topLevelOrderIndex: 0,
            blockOrderIndex: i,
            effortKind: 'set',
            exerciseId: sourceExerciseIds[i],
            blockId: 'block-repeat-source',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
      }

      final cloneA = await repository.cloneSessionBlock('block-repeat-source');
      final cloneB = await repository.cloneSessionBlock('block-repeat-source');

      final efforts = await repository.getSegmentEfforts(
        'segment-repeat-clone',
      );
      final cloneAExerciseIds = efforts
          .where((effort) => effort.blockId == cloneA)
          .map((effort) => effort.exerciseId)
          .toList();
      final cloneBExerciseIds = efforts
          .where((effort) => effort.blockId == cloneB)
          .map((effort) => effort.exerciseId)
          .toList();

      expect(cloneAExerciseIds, sourceExerciseIds);
      expect(cloneBExerciseIds, sourceExerciseIds);
    });

    test(
      'adding into earlier block appends locally without moving top-level order',
      () async {
        await repository.createSession(
          TrainingSession(
            id: 'session-append-order',
            ownerUserId: 'local-user',
            startedAtMs: 1000,
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );

        await repository.createSegment(
          SessionSegment(
            id: 'segment-append-order',
            sessionId: 'session-append-order',
            orderIndex: 0,
            segmentType: 'mixed',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );

        await repository.createSessionBlock(
          SessionBlock(
            id: 'block-a',
            sessionId: 'session-append-order',
            name: 'A',
            orderIndex: 0,
            topLevelOrderIndex: 0,
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );

        final exercises = await repository.getExercises();

        await repository.createEffort(
          SegmentEffort(
            id: 'eff-a1',
            segmentId: 'segment-append-order',
            orderIndex: 0,
            topLevelOrderIndex: 0,
            blockOrderIndex: 0,
            effortKind: 'set',
            exerciseId: exercises[0].id,
            blockId: 'block-a',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );

        await repository.createEffort(
          SegmentEffort(
            id: 'eff-x',
            segmentId: 'segment-append-order',
            orderIndex: 1,
            topLevelOrderIndex: 1,
            effortKind: 'set',
            exerciseId: exercises[1].id,
            blockId: null,
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );

        await repository.createSessionBlock(
          SessionBlock(
            id: 'block-b',
            sessionId: 'session-append-order',
            name: 'B',
            orderIndex: 2,
            topLevelOrderIndex: 2,
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );

        await repository.createEffort(
          SegmentEffort(
            id: 'eff-b1',
            segmentId: 'segment-append-order',
            orderIndex: 0,
            topLevelOrderIndex: 2,
            blockOrderIndex: 0,
            effortKind: 'set',
            exerciseId: exercises[2].id,
            blockId: 'block-b',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );

        await repository.createEffort(
          SegmentEffort(
            id: 'eff-a2',
            segmentId: 'segment-append-order',
            orderIndex: 99,
            effortKind: 'set',
            exerciseId: exercises[3].id,
            blockId: 'block-a',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );

        final blocks = await repository.getSessionBlocks(
          'session-append-order',
        );
        expect(blocks.map((block) => block.id).toList(), [
          'block-a',
          'block-b',
        ]);

        final efforts = await repository.getSegmentEfforts(
          'segment-append-order',
        );
        expect(efforts.map((effort) => effort.id).toList(), [
          'eff-a1',
          'eff-a2',
          'eff-x',
          'eff-b1',
        ]);
      },
    );

    test(
      'identical builds produce identical canonical order without timestamp dependence',
      () async {
        Future<List<String>> buildSession(
          String sessionId,
          String segmentId,
        ) async {
          await repository.createSession(
            TrainingSession(
              id: sessionId,
              ownerUserId: 'local-user',
              startedAtMs: 1000,
              createdAtMs: 1000,
              updatedAtMs: 1000,
            ),
          );

          await repository.createSegment(
            SessionSegment(
              id: segmentId,
              sessionId: sessionId,
              orderIndex: 0,
              segmentType: 'mixed',
              createdAtMs: 1000,
              updatedAtMs: 1000,
            ),
          );

          final exercises = await repository.getExercises();

          await repository.createSessionBlock(
            SessionBlock(
              id: 'block-$sessionId-a',
              sessionId: sessionId,
              name: 'A',
              orderIndex: 0,
              createdAtMs: 1000,
              updatedAtMs: 1000,
            ),
          );
          await repository.createEffort(
            SegmentEffort(
              id: 'eff-$sessionId-a1',
              segmentId: segmentId,
              orderIndex: 0,
              effortKind: 'set',
              exerciseId: exercises[0].id,
              blockId: 'block-$sessionId-a',
              createdAtMs: 1000,
              updatedAtMs: 1000,
            ),
          );
          await repository.createEffort(
            SegmentEffort(
              id: 'eff-$sessionId-x',
              segmentId: segmentId,
              orderIndex: 0,
              effortKind: 'set',
              exerciseId: exercises[1].id,
              blockId: null,
              createdAtMs: 1000,
              updatedAtMs: 1000,
            ),
          );
          await repository.createSessionBlock(
            SessionBlock(
              id: 'block-$sessionId-b',
              sessionId: sessionId,
              name: 'B',
              orderIndex: 0,
              createdAtMs: 1000,
              updatedAtMs: 1000,
            ),
          );
          await repository.createEffort(
            SegmentEffort(
              id: 'eff-$sessionId-b1',
              segmentId: segmentId,
              orderIndex: 0,
              effortKind: 'set',
              exerciseId: exercises[2].id,
              blockId: 'block-$sessionId-b',
              createdAtMs: 1000,
              updatedAtMs: 1000,
            ),
          );

          final efforts = await repository.getSegmentEfforts(segmentId);
          return efforts
              .map(
                (effort) =>
                    '${effort.exerciseId}:${effort.topLevelOrderIndex}:${effort.blockOrderIndex}',
              )
              .toList();
        }

        final firstBuild = await buildSession('session-det-1', 'segment-det-1');
        final secondBuild = await buildSession(
          'session-det-2',
          'segment-det-2',
        );

        expect(firstBuild, secondBuild);
      },
    );

    test(
      'cloneSessionBlock in modality session uses current-time title',
      () async {
        await repository.createSession(
          TrainingSession(
            id: 'session-naming',
            ownerUserId: 'local-user',
            startedAtMs: 1000,
            modality: 'resistance_lifting',
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
        final blocksAfterFirst = await repository.getSessionBlocks(
          'session-naming',
        );
        final clone2 = blocksAfterFirst.firstWhere((b) => b.id == clone2Id);
        expect(clone2.name, isNot(contains('(2)')));
        expect(clone2.name, matches(RegExp(r'^\d{1,2}:\d{2} (AM|PM)$')));

        // Second clone also remains time-based.
        final clone3Id = await repository.cloneSessionBlock(clone2Id);
        final blocksAfterSecond = await repository.getSessionBlocks(
          'session-naming',
        );
        final clone3 = blocksAfterSecond.firstWhere((b) => b.id == clone3Id);
        expect(clone3.name, isNot(contains('(2)')));
        expect(clone3.name, matches(RegExp(r'^\d{1,2}:\d{2} (AM|PM)$')));
      },
    );

    test(
      'cloneSessionBlock in rolling session uses current-time title',
      () async {
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
        final blocks = await repository.getSessionBlocks(
          'session-rolling-clone',
        );
        final cloned = blocks.firstWhere((b) => b.id == cloneId);

        expect(cloned.name, isNot(contains('(2)')));
        expect(cloned.name, matches(RegExp(r'^\d{1,2}:\d{2} (AM|PM)$')));
      },
    );

    test('cloneSessionBlock in free session uses current-time title', () async {
      await repository.createSession(
        TrainingSession(
          id: 'session-free-clone',
          ownerUserId: 'local-user',
          startedAtMs: 1000,
          modality: null,
          intent: null,
          isRolling: false,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );

      await repository.createSessionBlock(
        SessionBlock(
          id: 'block-free-source',
          sessionId: 'session-free-clone',
          name: 'Main',
          orderIndex: 0,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );

      final cloneId = await repository.cloneSessionBlock('block-free-source');
      final blocks = await repository.getSessionBlocks('session-free-clone');
      final cloned = blocks.firstWhere((b) => b.id == cloneId);

      expect(cloned.name, isNot(contains('(2)')));
      expect(cloned.name, matches(RegExp(r'^\d{1,2}:\d{2} (AM|PM)$')));
    });

    test(
      'cloneSessionBlock preserves all observation numeric values',
      () async {
        await repository.createSession(
          TrainingSession(
            id: 'session-numvals',
            ownerUserId: 'local-user',
            startedAtMs: 1000,
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
        await repository.createSegment(
          SessionSegment(
            id: 'segment-numvals',
            sessionId: 'session-numvals',
            orderIndex: 0,
            segmentType: 'mixed',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
        await repository.createSessionBlock(
          SessionBlock(
            id: 'block-numvals-src',
            sessionId: 'session-numvals',
            name: 'Source',
            orderIndex: 0,
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
        await repository.createEffort(
          SegmentEffort(
            id: 'effort-numvals',
            segmentId: 'segment-numvals',
            orderIndex: 0,
            effortKind: 'set',
            blockId: 'block-numvals-src',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );

        // Create an observation with all value fields populated.
        await repository.createObservation(
          EffortObservation(
            id: 'obs-numvals',
            effortId: 'effort-numvals',
            metricId: 'metric-weight',
            unitId: 'unit-kg',
            valueInt: 5,
            valueReal: 102.5,
            valueText: 'some note',
            rpeRating: 8,
            restDurationMs: 90000,
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );

        final newBlockId = await repository.cloneSessionBlock(
          'block-numvals-src',
        );
        final allEfforts = await repository.getSegmentEfforts(
          'segment-numvals',
        );
        final clonedEffort = allEfforts.firstWhere(
          (e) => e.blockId == newBlockId,
        );
        final clonedObs = await repository.getEffortObservations(
          clonedEffort.id,
        );

        expect(clonedObs, hasLength(1));
        expect(clonedObs.first.id, isNot('obs-numvals'));
        expect(clonedObs.first.metricId, 'metric-weight');
        expect(clonedObs.first.unitId, 'unit-kg');
        expect(clonedObs.first.valueInt, 5);
        expect(clonedObs.first.valueReal, 102.5);
        expect(clonedObs.first.valueText, 'some note');
        expect(clonedObs.first.rpeRating, 8);
        expect(clonedObs.first.restDurationMs, 90000);
      },
    );

    test(
      'cloneSessionBlock produces independent copy — mutating clone does not affect source',
      () async {
        await repository.createSession(
          TrainingSession(
            id: 'session-independence',
            ownerUserId: 'local-user',
            startedAtMs: 1000,
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
        await repository.createSegment(
          SessionSegment(
            id: 'segment-independence',
            sessionId: 'session-independence',
            orderIndex: 0,
            segmentType: 'mixed',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
        await repository.createSessionBlock(
          SessionBlock(
            id: 'block-indep-src',
            sessionId: 'session-independence',
            name: 'Source',
            orderIndex: 0,
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
        await repository.createEffort(
          SegmentEffort(
            id: 'effort-indep',
            segmentId: 'segment-independence',
            orderIndex: 0,
            effortKind: 'set',
            blockId: 'block-indep-src',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
        await repository.createObservation(
          EffortObservation(
            id: 'obs-indep',
            effortId: 'effort-indep',
            metricId: 'metric-reps',
            valueInt: 12,
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );

        final newBlockId = await repository.cloneSessionBlock(
          'block-indep-src',
        );
        final allEfforts = await repository.getSegmentEfforts(
          'segment-independence',
        );
        final clonedEffort = allEfforts.firstWhere(
          (e) => e.blockId == newBlockId,
        );
        final clonedObs = (await repository.getEffortObservations(
          clonedEffort.id,
        )).first;

        // Mutate the cloned observation.
        await repository.updateObservation(
          EffortObservation(
            id: clonedObs.id,
            effortId: clonedObs.effortId,
            metricId: clonedObs.metricId,
            valueInt: 99,
            createdAtMs: clonedObs.createdAtMs,
            updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
        );

        // Source observation must be unchanged.
        final sourceObs = await repository.getEffortObservations(
          'effort-indep',
        );
        expect(sourceObs.first.valueInt, 12);

        // Cloned observation reflects the mutation.
        final mutatedObs = await repository.getEffortObservations(
          clonedEffort.id,
        );
        expect(mutatedObs.first.valueInt, 99);
      },
    );
  });
}
