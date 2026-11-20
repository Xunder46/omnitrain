// Plan 279 P1b — state-level tests for the draft blocks the session summary
// hands the routine editor, and for the editor's seed state
// (Scenarios S-27901..S-27906, S-27915, S-27916, S-27917 of
// `docs/plans/2026-11-19-279-save-as-routine-opens-editor-plan/...`).
// Plain `test()` only: a Hive write inside `testWidgets` hangs (FakeAsync
// never advances real time). Every harness case runs through
// `harnessFactories` so Mock and Hive must end identical. Fixtures are built
// through the real writers (`createNewSession`, `addExerciseToSession`,
// `addSessionBlock`, `assignEffortToBlock`, `reorderSessionBlocks`), never
// hand-written rows — except S-27916, whose orphan `blockId` no live writer
// produces (D-27909).

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/models/session_summary.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/repository_harness.dart';

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — save-as-routine draft blocks', () {
      late WorkoutRepository repo;

      setUp(() async => repo = await harness.open());
      tearDown(() async => await harness.close());

      /// Creates a fresh resistance session, runs [build] against it, and
      /// gives the state back with the session's id.
      Future<(WorkoutState, String)> sessionWith(
        WorkoutRepository repo,
        Future<void> Function(WorkoutState) build,
      ) async {
        final state = WorkoutState(repo);
        await state.createNewSession(modality: 'resistance_lifting');
        await build(state);
        return (state, state.currentSession!.id);
      }

      /// A draft as plain names: each block's name then its exercises' names,
      /// so assertions read as lists.
      List<List<String>> shape(SessionTemplateDraft d) => [
        for (final b in d.blocks) [b.name, ...b.exercises.map((e) => e.name)],
      ];

      /// Four different seed exercises that can carry weight, by index.
      Future<List<Exercise>> pickFour() async {
        final loadable = (await repo.getExercises())
            .where((e) => e.capabilities.contains('load'))
            .toList();
        expect(
          loadable.length,
          greaterThanOrEqualTo(4),
          reason: 'the seed catalog must hold four load-capable exercises',
        );
        return [loadable[0], loadable[1], loadable[2], loadable[3]];
      }

      /// The way the summary hands the editor its draft: the state's blocks
      /// wrapped in a draft (the state exposes the blocks only).
      SessionTemplateDraft draftOf(WorkoutState state) => SessionTemplateDraft(
        name: 'Plan',
        focusModality: 'resistance_lifting',
        blocks: state.buildTemplateDraftBlocks(),
      );

      test('S-27901 named session blocks become routine blocks in the '
          'session\'s order', () async {
        final exercises = await pickFour();
        final e1 = exercises[0];
        final e2 = exercises[1];
        final e3 = exercises[2];
        final (state, _) = await sessionWith(repo, (state) async {
          final first = await state.addExerciseToSession(e1);
          final second = await state.addExerciseToSession(e2);
          final upper = await state.addSessionBlock(name: 'Upper');
          await state.assignEffortToBlock(first, upper);
          await state.assignEffortToBlock(second, upper);
          final third = await state.addExerciseToSession(e3);
          final legs = await state.addSessionBlock(name: 'Legs');
          await state.assignEffortToBlock(third, legs);
        });

        final draft = draftOf(state);
        expect(
          shape(draft),
          [
            ['Upper', e1.name, e2.name],
            ['Legs', e3.name],
          ],
          reason:
              'S-27901 the draft keeps one block per named session block, '
              'exercises in block order',
        );

        // Save as Routine: the repository holds one segment per block.
        final routineState = RoutineState(repo);
        await routineState.createRoutineFromSessionDraft(
          SessionTemplateDraft(
            name: 'Plan',
            focusModality: 'resistance_lifting',
            blocks: draft.blocks,
          ),
        );
        expect(
          await routineState.saveRoutine(),
          isTrue,
          reason: 'S-27901 the seeded routine saves',
        );

        final templateId = routineState.currentTemplate!.id;
        final segments = await repo.getTemplateSegments(templateId);
        expect(
          segments.map((s) => s.name),
          ['Upper', 'Legs'],
          reason: 'S-27901 one segment per session block, in draft order',
        );
        expect(
          segments.map((s) => s.orderIndex),
          [0, 1],
          reason: 'S-27901 segments are ordered 0, 1',
        );

        final upperEfforts = await repo.getTemplateEfforts(segments[0].id);
        expect(
          upperEfforts.map((e) => e.exerciseId),
          [e1.id, e2.id],
          reason: 'S-27901 the Upper segment holds its exercises in order',
        );
        expect(
          upperEfforts.map((e) => e.orderIndex),
          [0, 1],
          reason: 'S-27901 Upper efforts are ordered 0, 1',
        );

        final legsEfforts = await repo.getTemplateEfforts(segments[1].id);
        expect(
          legsEfforts.map((e) => e.exerciseId),
          [e3.id],
          reason: 'S-27901 the Legs segment holds its exercise',
        );
        expect(
          legsEfforts.map((e) => e.orderIndex),
          [0],
          reason: 'S-27901 the Legs effort is ordered 0',
        );
      });

      test('S-27902 a session with only loose exercises drafts one '
          'Main Block', () async {
        final exercises = await pickFour();
        final (state, _) = await sessionWith(repo, (state) async {
          await state.addExerciseToSession(exercises[0]);
          await state.addExerciseToSession(exercises[1]);
        });

        final draft = draftOf(state);
        expect(
          shape(draft),
          [
            ['Main Block', exercises[0].name, exercises[1].name],
          ],
          reason:
              'S-27902 today\'s result is guarded: the loose run stays one '
              'block named Main Block, in session order',
        );
      });

      test('S-27903 loose runs between blocks become Main Block and '
          'Main Block 2', () async {
        final exercises = await pickFour();
        final e1 = exercises[0];
        final e2 = exercises[1];
        final e3 = exercises[2];
        final (state, _) = await sessionWith(repo, (state) async {
          await state.addExerciseToSession(e1);
          final upper = await state.addSessionBlock(name: 'Upper');
          final inside = await state.addExerciseToSession(e2);
          await state.assignEffortToBlock(inside, upper);
          await state.addExerciseToSession(e3);

          // The top-level order the real writer produced: E1, Upper, E3.
          final segmentId = (await repo.getSessionSegments(
            state.currentSession!.id,
          )).first.id;
          final efforts = state.getEffortsForSegment(segmentId);
          int topOfState(String exerciseId) {
            final effort = efforts.firstWhere(
              (e) => e.exerciseId == exerciseId,
            );
            return effort.topLevelOrderIndex ?? effort.orderIndex;
          }

          expect(topOfState(e1.id), 0, reason: 'S-27903 fixture precondition');
          final upperTop = state.getSessionBlocks().firstWhere(
            (b) => b.name == 'Upper',
          );
          expect(
            upperTop.topLevelOrderIndex ?? upperTop.orderIndex,
            1,
            reason: 'S-27903 fixture precondition',
          );
          expect(topOfState(e3.id), 2, reason: 'S-27903 fixture precondition');
        });

        final draft = draftOf(state);
        expect(
          shape(draft),
          [
            ['Main Block', e1.name],
            ['Upper', e2.name],
            ['Main Block 2', e3.name],
          ],
          reason:
              'S-27903 each run of loose exercises between blocks becomes its '
              'own Main Block, numbered in order',
        );
      });

      test('S-27904 per-set targets survive into the editor routine', () async {
        final exercises = await pickFour();
        final bench = exercises[0];
        final (state, _) = await sessionWith(repo, (state) async {
          final effortId = await state.addExerciseToSession(bench);
          await state.addEntry(effortId);
          await state.addEntry(effortId);
          await state.updateEntryValue(effortId, 0, 'reps', 8);
          await state.updateEntryValue(effortId, 0, 'weight', 60.0);
          await state.updateEntryValue(effortId, 1, 'reps', 8);
          await state.updateEntryValue(effortId, 1, 'weight', 60.0);
          await state.updateEntryValue(effortId, 2, 'reps', 6);
          await state.updateEntryValue(effortId, 2, 'weight', 65.0);
        });

        final draft = draftOf(state);
        final targets = <TemplateTargetDraft>[
          for (final block in draft.blocks)
            for (final exercise in block.exercises)
              if (exercise.name == bench.name) ...exercise.targets,
        ];
        int repsOf(int setIndex) => targets
            .firstWhere(
              (t) => t.metricId == MetricIds.reps && t.setIndex == setIndex,
            )
            .valueInt!;
        double weightOf(int setIndex) => targets
            .firstWhere(
              (t) => t.metricId == MetricIds.weight && t.setIndex == setIndex,
            )
            .valueReal!;
        expect(
          [repsOf(0), repsOf(1), repsOf(2)],
          [8, 8, 6],
          reason: 'S-27904 the draft carries each set\'s reps target',
        );
        expect(
          [weightOf(0), weightOf(1), weightOf(2)],
          [60.0, 60.0, 65.0],
          reason:
              'S-27904 the draft carries each set\'s weight in canonical kg',
        );

        final routineState = RoutineState(repo);
        await routineState.createRoutineFromSessionDraft(
          SessionTemplateDraft(
            name: 'Plan',
            focusModality: 'resistance_lifting',
            blocks: draft.blocks,
          ),
        );
        final effort = routineState.currentEfforts.single;
        for (final setIndex in [0, 1, 2]) {
          final forSet = routineState.getEffortTargetsForSet(
            effort.id,
            setIndex,
          );
          expect(
            forSet.firstWhere((t) => t.metricId == MetricIds.reps).targetInt,
            repsOf(setIndex),
            reason: 'S-27904 the routine carries set $setIndex\'s reps',
          );
          expect(
            forSet.firstWhere((t) => t.metricId == MetricIds.weight).targetMin,
            weightOf(setIndex),
            reason: 'S-27904 the routine carries set $setIndex\'s weight',
          );
        }
      });

      test('S-27905 an empty session block is left out; a block holding one '
          'exercise stays', () async {
        final exercises = await pickFour();
        final (state, _) = await sessionWith(repo, (state) async {
          final held = await state.addExerciseToSession(exercises[0]);
          final holding = await state.addSessionBlock(name: 'Holding');
          await state.assignEffortToBlock(held, holding);
          await state.addSessionBlock(name: 'Empty');
        });

        final draft = draftOf(state);
        expect(
          shape(draft),
          [
            ['Holding', exercises[0].name],
          ],
          reason:
              'S-27905 the empty block is absent and the one-exercise block '
              'is present with its exercise',
        );
      });

      test(
        'S-27906 reordered session blocks draft in the moved order',
        () async {
          final exercises = await pickFour();
          final e1 = exercises[0];
          final e2 = exercises[1];
          String upperId = '';
          String legsId = '';
          final (state, _) = await sessionWith(repo, (state) async {
            final first = await state.addExerciseToSession(e1);
            upperId = await state.addSessionBlock(name: 'Upper');
            await state.assignEffortToBlock(first, upperId);
            final second = await state.addExerciseToSession(e2);
            legsId = await state.addSessionBlock(name: 'Legs');
            await state.assignEffortToBlock(second, legsId);
          });

          await state.reorderSessionBlocks([legsId, upperId]);

          final draft = draftOf(state);
          expect(
            shape(draft),
            [
              ['Legs', e2.name],
              ['Upper', e1.name],
            ],
            reason:
                'S-27906 the draft follows the order the session shows after '
                'the reorder, not the blocks\' creation order',
          );
        },
      );

      test('S-27917 two session blocks with the same name are never merged '
          'or renamed', () async {
        final exercises = await pickFour();
        final e1 = exercises[0];
        final e2 = exercises[1];
        final (state, _) = await sessionWith(repo, (state) async {
          final first = await state.addExerciseToSession(e1);
          final firstBlock = await state.addSessionBlock(name: 'Upper');
          await state.assignEffortToBlock(first, firstBlock);
          final second = await state.addExerciseToSession(e2);
          final secondBlock = await state.addSessionBlock(name: 'Upper');
          await state.assignEffortToBlock(second, secondBlock);
        });

        final draft = draftOf(state);
        expect(
          shape(draft),
          [
            ['Upper', e1.name],
            ['Upper', e2.name],
          ],
          reason:
              'S-27917 duplicate block names are kept as they are: two blocks '
              'named Upper, never merged or de-duplicated',
        );
      });

      test('S-27901b exercises inside a block keep the order the user gave '
          'them', () async {
        final exercises = await pickFour();
        final e1 = exercises[0];
        final e2 = exercises[1];
        final e3 = exercises[2];
        String e1Id = '';
        String e2Id = '';
        String e3Id = '';
        final (state, sessionId) = await sessionWith(repo, (state) async {
          e1Id = await state.addExerciseToSession(e1);
          e2Id = await state.addExerciseToSession(e2);
          e3Id = await state.addExerciseToSession(e3);
          final upper = await state.addSessionBlock(name: 'Upper');
          await state.assignEffortToBlock(e1Id, upper);
          await state.assignEffortToBlock(e2Id, upper);
          await state.assignEffortToBlock(e3Id, upper);
        });

        // Inside a block the move walks the block's own exercises.
        expect(
          await state.moveExercise(e3Id, -1),
          isTrue,
          reason: 'S-27901b the first move up applies',
        );
        expect(
          await state.moveExercise(e3Id, -1),
          isTrue,
          reason: 'S-27901b the second move up applies',
        );

        // The writer's precondition: the moves renumbered blockOrderIndex
        // 0, 1, 2 for E3, E1, E2 — and the ids still ascend in creation
        // order, so an id sort could not reproduce this order.
        final segmentId = (await repo.getSessionSegments(sessionId)).first.id;
        final stored = await repo.getSegmentEfforts(segmentId);
        int blockIndexOf(String exerciseId) => stored
            .firstWhere((e) => e.exerciseId == exerciseId)
            .blockOrderIndex!;
        expect(
          [blockIndexOf(e3.id), blockIndexOf(e1.id), blockIndexOf(e2.id)],
          [0, 1, 2],
          reason: 'S-27901b fixture precondition',
        );
        expect(
          e1.id.compareTo(e2.id) < 0 && e2.id.compareTo(e3.id) < 0,
          isTrue,
          reason: 'S-27901b fixture precondition: ids ascend E1 < E2 < E3',
        );

        final draft = draftOf(state);
        expect(
          shape(draft),
          [
            ['Upper', e3.name, e1.name, e2.name],
          ],
          reason:
              'S-27901b the draft keeps the block\'s exercises in the order '
              'the moves left them, by blockOrderIndex',
        );
      });

      test('S-27903b a loose exercise and a block at the same top-level key: '
          'the loose one comes first', () async {
        final exercises = await pickFour();
        final e1 = exercises[0];
        final e2 = exercises[1];
        final (state, _) = await sessionWith(repo, (state) async {
          final upper = await state.addSessionBlock(name: 'Upper');
          await state.addExerciseToSession(e1);
          final inside = await state.addExerciseToSession(e2);
          await state.assignEffortToBlock(inside, upper);

          // The real writers' precondition: the first block carries
          // topLevelOrderIndex 0, and a loose effort added after it keeps an
          // in-memory row without one, so its top falls back to orderIndex 0
          // — the same key the block holds. The repository normalizes the
          // tops it stores, so the tie is the in-memory view
          // buildTemplateDraftBlocks reads.
          final segmentId = (await repo.getSessionSegments(
            state.currentSession!.id,
          )).first.id;
          final loose = state
              .getEffortsForSegment(segmentId)
              .firstWhere((e) => e.blockId == null);
          final upperBlock = state.getSessionBlocks().firstWhere(
            (b) => b.name == 'Upper',
          );
          expect(
            loose.topLevelOrderIndex ?? loose.orderIndex,
            upperBlock.topLevelOrderIndex ?? upperBlock.orderIndex,
            reason: 'S-27903b fixture precondition: the keys tie',
          );
          expect(
            loose.topLevelOrderIndex ?? loose.orderIndex,
            0,
            reason: 'S-27903b fixture precondition: the tie sits at 0',
          );
        });

        final draft = draftOf(state);
        expect(
          shape(draft),
          [
            ['Main Block', e1.name],
            ['Upper', e2.name],
          ],
          reason:
              'S-27903b at a top-level tie the loose exercise is drafted '
              'before the block that shares its key',
        );
      });

      test('S-27907a the seeded template keeps the draft\'s name and focus '
          'modality', () async {
        final routineState = RoutineState(repo);
        routineState.setAutosaveEnabled(false);
        final draft = SessionTemplateDraft(
          name: 'Push Day',
          focusModality: 'resistance_lifting',
          blocks: [
            SessionTemplateBlock(
              name: 'Upper',
              exercises: [
                SessionTemplateExercise(
                  exerciseId: 'x-27907a',
                  name: 'X',
                  effortKind: 'set',
                  targets: const [],
                ),
              ],
            ),
          ],
        );

        await routineState.createRoutineFromSessionDraft(draft);

        expect(
          routineState.currentTemplate!.focusModality,
          'resistance_lifting',
          reason:
              'S-27907a the seeded template carries the draft\'s focus '
              'modality',
        );
        expect(
          routineState.currentTemplate!.name,
          'Push Day',
          reason: 'S-27907a the seeded template carries the draft\'s name',
        );
      });

      test('S-27908a an unedited seeded routine has no unsaved changes, an '
          'edited one has', () async {
        final routineState = RoutineState(repo);
        routineState.setAutosaveEnabled(false);
        final idsBefore = (await repo.getTemplates()).map((t) => t.id);

        final draft = SessionTemplateDraft(
          name: 'Plan',
          focusModality: 'resistance_lifting',
          blocks: [
            SessionTemplateBlock(
              name: 'Upper',
              exercises: [
                SessionTemplateExercise(
                  exerciseId: 'x-27908a',
                  name: 'X',
                  effortKind: 'set',
                  targets: const [],
                ),
              ],
            ),
          ],
        );
        await routineState.createRoutineFromSessionDraft(draft);

        expect(
          routineState.hasUnsavedChanges,
          isFalse,
          reason:
              'S-27908a seeding captures the baseline: an untouched seeded '
              'routine is not dirty',
        );
        final templateId = routineState.currentTemplate!.id;
        expect(
          (await repo.getTemplates()).map((t) => t.id),
          idsBefore,
          reason: 'S-27908a seeding writes nothing to the repository',
        );
        expect(
          await repo.getTemplateSegments(templateId),
          isEmpty,
          reason: 'S-27908a seeding persists no segments',
        );

        await routineState.updateRoutineName('Renamed');
        expect(
          routineState.hasUnsavedChanges,
          isTrue,
          reason: 'S-27908a an edit after seeding marks the routine dirty',
        );
      });

      test('S-27915b top-level order follows topLevelOrderIndex when it '
          'differs from orderIndex (legacy rows)', () async {
        // Synthetic fixture, written straight through the repository: no
        // live writer produces orderIndex 9 with topLevelOrderIndex 0 (the
        // loose-effort writers keep the two equal). Only rows written before
        // the renumbering rule differ like this.
        const sessionId = 's-27915b';
        await seedSession(
          repo,
          sessionId: sessionId,
          modality: 'resistance_lifting',
        );
        final exercises = await pickFour();
        for (final entry in [
          (
            id: 'eff-27915b-a',
            exerciseId: exercises[0].id,
            orderIndex: 9,
            top: 0,
          ),
          (
            id: 'eff-27915b-b',
            exerciseId: exercises[1].id,
            orderIndex: 1,
            top: 1,
          ),
        ]) {
          await repo.createEffort(
            SegmentEffort(
              id: entry.id,
              segmentId: 'seg-$sessionId',
              orderIndex: entry.orderIndex,
              topLevelOrderIndex: entry.top,
              effortKind: 'set',
              exerciseId: entry.exerciseId,
              createdAtMs: fixtureStart,
              updatedAtMs: fixtureStart,
            ),
          );
        }

        final state = WorkoutState(repo);
        await state.loadHistoricalSession(sessionId);
        final draft = draftOf(state);
        expect(
          shape(draft),
          [
            ['Main Block', exercises[0].name, exercises[1].name],
          ],
          reason:
              'S-27915b top-level order follows topLevelOrderIndex, so the '
              'legacy row with orderIndex 9 but top 0 drafts first',
        );
      });

      test('S-27915 a watch-adopted session drafts one Main Block in '
          'topLevelOrderIndex order', () async {
        // The adoption bridge writes each slot's effort with
        // `topLevelOrderIndex: orderIndex` and never a `blockId`
        // (`watch_session_adoption_bridge.dart`, `_effort`), so a watch
        // session is one loose run. The efforts here are written in an order
        // different from their top-level order, so the draft's order proves
        // the rule.
        const sessionId = 's-27915';
        await seedSession(
          repo,
          sessionId: sessionId,
          modality: 'resistance_lifting',
        );
        final exercises = await pickFour();
        // Creation order: top 2, then top 0, then top 1.
        for (final n in [2, 0, 1]) {
          await repo.createEffort(
            SegmentEffort(
              id: 'eff-27915-$n',
              segmentId: 'seg-$sessionId',
              orderIndex: n,
              topLevelOrderIndex: n,
              effortKind: 'set',
              exerciseId: exercises[n].id,
              createdAtMs: fixtureStart,
              updatedAtMs: fixtureStart,
            ),
          );
        }

        final state = WorkoutState(repo);
        await state.loadHistoricalSession(sessionId);
        final draft = draftOf(state);
        expect(
          shape(draft),
          [
            [
              'Main Block',
              exercises[0].name,
              exercises[1].name,
              exercises[2].name,
            ],
          ],
          reason:
              'S-27915 one Main Block holds all exercises ordered by '
              'topLevelOrderIndex ?? orderIndex',
        );
      });

      test('S-27916 an effort whose blockId names no session block counts as '
          'loose and joins the surrounding run', () async {
        // No live writer produces this row: deleteSessionBlock
        // cascade-deletes its linked efforts (D-27909). The orphan is written
        // straight through the repository as a synthetic fixture to pin the
        // defensive fallback.
        const sessionId = 's-27916';
        await seedSession(
          repo,
          sessionId: sessionId,
          modality: 'resistance_lifting',
        );
        final exercises = await pickFour();
        final loose = [exercises[0], exercises[1], exercises[2]];
        for (final entry in [
          (id: 'eff-27916-0', exerciseId: loose[0].id, top: 0, blockId: null),
          (
            id: 'eff-27916-1',
            exerciseId: loose[1].id,
            top: 1,
            blockId: 'no-such-block',
          ),
          (id: 'eff-27916-2', exerciseId: loose[2].id, top: 2, blockId: null),
        ]) {
          await repo.createEffort(
            SegmentEffort(
              id: entry.id,
              segmentId: 'seg-$sessionId',
              orderIndex: entry.top,
              topLevelOrderIndex: entry.top,
              effortKind: 'set',
              exerciseId: entry.exerciseId,
              blockId: entry.blockId,
              createdAtMs: fixtureStart,
              updatedAtMs: fixtureStart,
            ),
          );
        }

        final state = WorkoutState(repo);
        await state.loadHistoricalSession(sessionId);
        final draft = draftOf(state);
        expect(
          shape(draft),
          [
            ['Main Block', loose[0].name, loose[1].name, loose[2].name],
          ],
          reason:
              'S-27916 the orphan effort is loose: it joins the surrounding '
              'Main Block run, with no crash and no null name',
        );
      });

      test('S-27901h the saved fixture reads back through '
          'loadHistoricalSession with the same shape', () async {
        final exercises = await pickFour();
        final e1 = exercises[0];
        final e2 = exercises[1];
        final e3 = exercises[2];
        final (state, sessionId) = await sessionWith(repo, (state) async {
          final first = await state.addExerciseToSession(e1);
          final second = await state.addExerciseToSession(e2);
          final upper = await state.addSessionBlock(name: 'Upper');
          await state.assignEffortToBlock(first, upper);
          await state.assignEffortToBlock(second, upper);
          final third = await state.addExerciseToSession(e3);
          final legs = await state.addSessionBlock(name: 'Legs');
          await state.assignEffortToBlock(third, legs);
        });

        final draft = draftOf(state);
        final expected = shape(draft);

        // The way a historical summary reads the session back.
        final reloaded = WorkoutState(repo);
        await reloaded.loadHistoricalSession(sessionId);
        expect(
          shape(draftOf(reloaded)),
          expected,
          reason:
              'S-27901h a stored session read back drafts the same blocks as '
              'the live session did',
        );
      });
    });
  }

  // Pinned regression for the flat getter (plan 279 D-27901): the old readers
  // of `SessionTemplateDraft.exercises` must keep seeing every block's
  // exercises in order, and the exercises-only shorthand still makes one
  // `Main Block`.
  test('S-27902b the flat exercises getter stays the blocks flattened, and '
      'the exercises-only shorthand makes one Main Block', () {
    final x = SessionTemplateExercise(
      exerciseId: 'x',
      name: 'X',
      effortKind: 'set',
      targets: const [],
    );
    final y = SessionTemplateExercise(
      exerciseId: 'y',
      name: 'Y',
      effortKind: 'set',
      targets: const [],
    );
    final z = SessionTemplateExercise(
      exerciseId: 'z',
      name: 'Z',
      effortKind: 'set',
      targets: const [],
    );

    final draft = SessionTemplateDraft(
      name: 'n',
      focusModality: null,
      blocks: [
        SessionTemplateBlock(name: 'A', exercises: [x]),
        SessionTemplateBlock(name: 'B', exercises: [y, z]),
      ],
    );
    expect(
      draft.exercises,
      [x, y, z],
      reason: 'S-27902b the flat getter is the blocks flattened in order',
    );

    final shorthand = SessionTemplateDraft(
      name: 'n',
      focusModality: null,
      exercises: [x],
    );
    expect(
      shorthand.blocks.single.name,
      'Main Block',
      reason: 'S-27902b the exercises-only shorthand makes one Main Block',
    );
    expect(
      shorthand.exercises,
      [x],
      reason: 'S-27902b the shorthand\'s flat getter sees the exercise',
    );
  });
}
