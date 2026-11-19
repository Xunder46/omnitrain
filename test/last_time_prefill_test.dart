// Plan 250 P2 — the state tests for "a new set starts from last time"
// (S-25001..S-25010).
//
// A new set effort's entries (an exercise added to a live workout, a routine's
// sets) start from the same-numbered set of the last finished workout of that
// exercise; "+ Add Set" and the wrist's seeded entry keep their own defaults.
// Plain `test()`: a Hive write never settles inside a `testWidgets`.
//
// Plan: `docs/plans/2026-11-19-250-last-time-prefill-plan/2026-11-19-250-last-time-prefill-plan.md`.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/constants/modality.dart';
import 'package:omnitrain/core/models/routine_session_manifest.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/repository_harness.dart';

// ─── Fixture times ──────────────────────────────────────────────────────────

final _s1Start = DateTime(2026, 11, 10, 12).millisecondsSinceEpoch;
final _s1End = DateTime(2026, 11, 10, 13).millisecondsSinceEpoch;
final _s2Start = DateTime(2026, 11, 12, 12).millisecondsSinceEpoch;
final _s2End = DateTime(2026, 11, 12, 13).millisecondsSinceEpoch;

// ─── Seeding ────────────────────────────────────────────────────────────────

/// A finished session with one segment and one `set` effort for [exerciseId],
/// holding [sets] as reps/weight rows the way the logger numbers them
/// (entry 0 first).
Future<void> seedHistory(
  WorkoutRepository repo, {
  required String sessionId,
  required int startedAtMs,
  int? endedAtMs,
  required List<(int reps, double kg)> sets,
  required String exerciseId,
}) async {
  await repo.createSession(
    TrainingSession(
      id: sessionId,
      ownerUserId: 'user-1',
      startedAtMs: startedAtMs,
      endedAtMs: endedAtMs,
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );
  final segId = 'seg-$sessionId';
  await repo.createSegment(
    SessionSegment(
      id: segId,
      sessionId: sessionId,
      orderIndex: 0,
      segmentType: 'workout',
      name: 'Main Workout',
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );
  final effortId = 'eff-$segId-$exerciseId';
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
  for (var n = 0; n < sets.length; n++) {
    final at = startedAtMs + 1000 + n;
    await repo.createObservation(repsRow(effortId, n, sets[n].$1, atMs: at));
    await repo.createObservation(
      weightRow(effortId, n, sets[n].$2, atMs: at + 1),
    );
  }
}

/// A real library exercise that carries both the `load` and `reps`
/// capabilities — the exercise the history holds and the live workout adds.
Future<Exercise> repsAndLoadExercise(WorkoutRepository repo) async =>
    (await repo.getExercises()).firstWhere(
      (e) => e.capabilities.contains('load') && e.capabilities.contains('reps'),
    );

/// A live resistance-lifting workout holding [exercise] as a `set` effort.
Future<(WorkoutState, String)> liveSetEffort(
  WorkoutRepository repo, {
  required Exercise exercise,
}) async {
  final state = WorkoutState(repo);
  await state.createNewSession(modality: Modality.resistanceLifting);
  final effortId = await state.addExerciseToSession(
    exercise,
    effortKindOverride: 'set',
  );
  return (state, effortId);
}

/// The (reps, kg) pairs the live workout's [effortId] holds, in entry order,
/// as `getExercisesWithEntries` shows them.
List<(int reps, double kg)> entriesOf(WorkoutState state, String effortId) {
  final effort = state.getExercisesWithEntries().firstWhere(
    (map) => map['id'] == effortId,
  );
  final entries = (effort['entries'] as List).cast<Map<String, dynamic>>();
  return [
    for (final entry in entries)
      (entry['reps'] as int, (entry['weight'] as num).toDouble()),
  ];
}

void expectEntries(
  List<(int reps, double kg)> actual,
  List<(int reps, double kg)> expected,
) {
  expect(actual, hasLength(expected.length));
  for (var i = 0; i < expected.length; i++) {
    expect(actual[i].$1, expected[i].$1, reason: 'entry $i reps');
    expect(actual[i].$2, expected[i].$2, reason: 'entry $i weight');
  }
}

/// The manifest one segment with [exercises] hangs off.
RoutineSessionManifest manifestWith({
  required Exercise exercise,
  required int setCount,
  List<TemplateTarget> targets = const [],
  String templateId = 'tmpl-250',
}) => RoutineSessionManifest(
  template: WorkoutTemplate(
    id: templateId,
    name: 'Last Time Routine',
    createdAtMs: 1000,
    updatedAtMs: 1000,
  ),
  segments: [
    SessionSegmentEntry(
      segment: TemplateSegment(
        id: 'tseg-$templateId',
        templateId: templateId,
        orderIndex: 0,
        segmentType: 'mixed',
        name: 'Main Work',
        createdAtMs: 1000,
        updatedAtMs: 1000,
      ),
      exercises: [
        SessionExerciseEntry(
          exercise: exercise,
          effortKind: 'set',
          setCount: setCount,
          targets: targets,
        ),
      ],
    ),
  ],
);

// ─── Tests ──────────────────────────────────────────────────────────────────

void main() {
  for (final make in harnessFactories) {
    final name = make().name;
    group('$name: a new set starts from last time', () {
      late RepositoryHarness harness;
      setUp(() => harness = make());
      tearDown(() => harness.close());

      test('S-25001 adding the exercise pre-fills from the newest finished '
          'workout, and the store holds the same numbers', () async {
        final repo = await harness.open();
        final exercise = await repsAndLoadExercise(repo);
        await seedHistory(
          repo,
          sessionId: 's1',
          startedAtMs: _s1Start,
          endedAtMs: _s1End,
          sets: [(8, 80.0), (8, 80.0), (6, 82.5)],
          exerciseId: exercise.id,
        );
        await seedHistory(
          repo,
          sessionId: 's2',
          startedAtMs: _s2Start,
          endedAtMs: _s2End,
          sets: [(5, 90.0)],
          exerciseId: exercise.id,
        );

        final (state, effortId) = await liveSetEffort(repo, exercise: exercise);

        expectEntries(entriesOf(state, effortId), [(5, 90.0)]);

        // The store, not only the cache: the rows the logger would read
        // back after a restart carry the same numbers.
        final rows = await repo.getEffortObservations(effortId);
        expect(
          rows.firstWhere((o) => o.metricId == MetricIds.reps).valueInt,
          5,
        );
        expect(
          rows.firstWhere((o) => o.metricId == MetricIds.weight).valueReal,
          90.0,
        );
      });

      test('S-25002 a routine with more sets than last time repeats its final '
          'set', () async {
        final repo = await harness.open();
        final exercise = await repsAndLoadExercise(repo);
        await seedHistory(
          repo,
          sessionId: 's1',
          startedAtMs: _s1Start,
          endedAtMs: _s1End,
          sets: [(8, 80.0), (8, 80.0), (6, 82.5)],
          exerciseId: exercise.id,
        );

        final state = WorkoutState(repo);
        await state.createNewSession(
          modality: Modality.resistanceLifting,
          includeDefaultSegment: false,
          routineTemplateId: 'tmpl-250',
          intent: 'routine',
        );
        await state.populateSessionFromManifest(
          manifestWith(exercise: exercise, setCount: 4),
        );

        final effortId = state.getExercisesWithEntries().single['id'] as String;
        expectEntries(entriesOf(state, effortId), [
          (8, 80.0),
          (8, 80.0),
          (6, 82.5),
          (6, 82.5),
        ]);
      });

      test('S-25003 the logger\'s "+ Add Set" carries the set just done, not '
          'last time', () async {
        final repo = await harness.open();
        final exercise = await repsAndLoadExercise(repo);
        await seedHistory(
          repo,
          sessionId: 's1',
          startedAtMs: _s1Start,
          endedAtMs: _s1End,
          sets: [(8, 80.0), (8, 80.0), (6, 82.5)],
          exerciseId: exercise.id,
        );

        final (state, effortId) = await liveSetEffort(repo, exercise: exercise);
        await state.addEntry(
          effortId,
          previousValues: {'reps': 7, 'weight': 85.0},
        );

        expectEntries(entriesOf(state, effortId), [(8, 80.0), (7, 85.0)]);
      });

      test('S-25004 no history keeps the app-wide defaults', () async {
        final repo = await harness.open();
        final exercise = await repsAndLoadExercise(repo);

        final (state, effortId) = await liveSetEffort(repo, exercise: exercise);

        expectEntries(entriesOf(state, effortId), [(10, 0.0)]);
      });

      test(
        'S-25005 a timed effort is not prefilled from the history\'s sets',
        () async {
          final repo = await harness.open();
          final exercise = await repsAndLoadExercise(repo);
          await seedHistory(
            repo,
            sessionId: 's1',
            startedAtMs: _s1Start,
            endedAtMs: _s1End,
            sets: [(8, 80.0), (8, 80.0), (6, 82.5)],
            exerciseId: exercise.id,
          );

          final state = WorkoutState(repo);
          await state.createNewSession(modality: Modality.resistanceLifting);
          final effortId = await state.addExerciseToSession(
            exercise,
            effortKindOverride: 'timed',
          );

          final effortMap = state.getExercisesWithEntries().firstWhere(
            (map) => map['id'] == effortId,
          );
          expect(effortMap['effortKind'], 'timed');
          final entries = (effortMap['entries'] as List)
              .cast<Map<String, dynamic>>();
          expect(entries, hasLength(1));
          expect(entries.single.containsKey('reps'), isFalse);
          expect(entries.single['duration'], 0);

          // No reps row in the store either.
          final rows = await repo.getEffortObservations(effortId);
          expect(rows.where((o) => o.metricId == MetricIds.reps), isEmpty);
        },
      );

      test(
        'S-25006 the wrist\'s seeded first entry starts at the defaults, not '
        'last time',
        () async {
          final repo = await harness.open();
          final exercise = await repsAndLoadExercise(repo);
          await seedHistory(
            repo,
            sessionId: 's1',
            startedAtMs: _s1Start,
            endedAtMs: _s1End,
            sets: [(8, 80.0), (8, 80.0), (6, 82.5)],
            exerciseId: exercise.id,
          );

          final (state, effortId) = await liveSetEffort(
            repo,
            exercise: exercise,
          );
          await state.deleteEntry(effortId, 0);
          await state.seedFirstEntry(effortId);

          expectEntries(entriesOf(state, effortId), [(10, 0.0)]);
        },
      );

      test(
        'S-25008 a routine\'s sets pre-fill from last time, per set index',
        () async {
          final repo = await harness.open();
          final exercise = await repsAndLoadExercise(repo);
          await seedHistory(
            repo,
            sessionId: 's1',
            startedAtMs: _s1Start,
            endedAtMs: _s1End,
            sets: [(8, 80.0), (8, 80.0), (6, 82.5)],
            exerciseId: exercise.id,
          );

          final state = WorkoutState(repo);
          await state.createNewSession(
            modality: Modality.resistanceLifting,
            includeDefaultSegment: false,
            routineTemplateId: 'tmpl-250',
            intent: 'routine',
          );
          await state.populateSessionFromManifest(
            manifestWith(exercise: exercise, setCount: 3),
          );

          final effortId =
              state.getExercisesWithEntries().single['id'] as String;
          expectEntries(entriesOf(state, effortId), [
            (8, 80.0),
            (8, 80.0),
            (6, 82.5),
          ]);
        },
      );

      test(
        'S-25009 a routine\'s own reps target wins on set 1; last time keeps '
        'the load',
        () async {
          final repo = await harness.open();
          final exercise = await repsAndLoadExercise(repo);
          await seedHistory(
            repo,
            sessionId: 's1',
            startedAtMs: _s1Start,
            endedAtMs: _s1End,
            sets: [(8, 80.0), (8, 80.0), (6, 82.5)],
            exerciseId: exercise.id,
          );

          final state = WorkoutState(repo);
          await state.createNewSession(
            modality: Modality.resistanceLifting,
            includeDefaultSegment: false,
            routineTemplateId: 'tmpl-250',
            intent: 'routine',
          );
          await state.populateSessionFromManifest(
            manifestWith(
              exercise: exercise,
              setCount: 3,
              targets: [
                TemplateTarget(
                  id: 'tt-250-1',
                  templateEffortId: 'teff-250-1',
                  metricId: MetricIds.reps,
                  setIndex: 0,
                  unitId: MetricIds.unitReps,
                  targetInt: 12,
                  createdAtMs: 1000,
                  updatedAtMs: 1000,
                ),
              ],
            ),
          );

          final effortId =
              state.getExercisesWithEntries().single['id'] as String;
          expectEntries(entriesOf(state, effortId), [
            (12, 80.0),
            (8, 80.0),
            (6, 82.5),
          ]);
        },
      );

      // A finished workout opened for editing is loaded as the current one:
      // it is FINISHED, so the finished-only filter alone does not keep it
      // from answering for itself — the exclusion must cover it (D-25001).
      test('S-25011 a finished workout loaded as the current one is not its '
          'own last time', () async {
        final repo = await harness.open();
        final exercise = await repsAndLoadExercise(repo);
        await seedHistory(
          repo,
          sessionId: 's1',
          startedAtMs: _s1Start,
          endedAtMs: _s1End,
          sets: [(8, 80.0), (8, 80.0), (6, 82.5)],
          exerciseId: exercise.id,
        );
        await seedHistory(
          repo,
          sessionId: 's2',
          startedAtMs: _s2Start,
          endedAtMs: _s2End,
          sets: [(5, 90.0)],
          exerciseId: exercise.id,
        );

        final state = WorkoutState(repo);
        await state.loadHistoricalSession('s2');

        final effortId = await state.addExerciseToSession(
          exercise,
          effortKindOverride: 'set',
        );
        expect(effortId, isNotEmpty,
            reason: 'adding to a loaded finished session works');

        // The new effort's first entry is s1's (8, 80), not s2's (5, 90):
        // s2 is the session being edited and must not answer for itself.
        expectEntries(entriesOf(state, effortId), [(8, 80.0)]);
      });

      // The history lookup is built per current session id: a second workout
      // started on the same state must read the history again (D-25003).
      test('S-25012 a second workout on the same state reads the history '
          'again', () async {
        final repo = await harness.open();
        final exercise = await repsAndLoadExercise(repo);
        await seedHistory(
          repo,
          sessionId: 's1',
          startedAtMs: _s1Start,
          endedAtMs: _s1End,
          sets: [(8, 80.0), (8, 80.0), (6, 82.5)],
          exerciseId: exercise.id,
        );
        await seedHistory(
          repo,
          sessionId: 's2',
          startedAtMs: _s2Start,
          endedAtMs: _s2End,
          sets: [(5, 90.0)],
          exerciseId: exercise.id,
        );

        final state = WorkoutState(repo);
        await state.createNewSession(modality: Modality.resistanceLifting);
        final firstEffortId = await state.addExerciseToSession(
          exercise,
          effortKindOverride: 'set',
        );
        // The cache is loaded: workout A starts from s2's set.
        expectEntries(entriesOf(state, firstEffortId), [(5, 90.0)]);

        await state.discardCurrentSession();

        // A newer workout happened between the two, seeded straight into the
        // store — the cache the first workout built does not know it.
        await seedHistory(
          repo,
          sessionId: 's3',
          startedAtMs: DateTime(2026, 11, 14, 12).millisecondsSinceEpoch,
          endedAtMs: DateTime(2026, 11, 14, 13).millisecondsSinceEpoch,
          sets: [(7, 95.0)],
          exerciseId: exercise.id,
        );

        await state.createNewSession(modality: Modality.resistanceLifting);
        final secondEffortId = await state.addExerciseToSession(
          exercise,
          effortKindOverride: 'set',
        );

        // The history was read again for the new session: s3's set.
        expectEntries(entriesOf(state, secondEffortId), [(7, 95.0)]);
      });
    });
  }

  // S-25007 is Mock only: the history lookup failing must not fail the add
  // (plan 250 D-25004).
  test('S-25007 a repository whose history read throws still adds the '
      'exercise with the defaults', () async {
    final repo = _ThrowingHistoryRepo();
    await repo.initialize();
    final exercise = await repsAndLoadExercise(repo);
    await seedHistory(
      repo,
      sessionId: 's1',
      startedAtMs: _s1Start,
      endedAtMs: _s1End,
      sets: [(8, 80.0), (8, 80.0), (6, 82.5)],
      exerciseId: exercise.id,
    );

    final state = WorkoutState(repo);
    await state.createNewSession(modality: Modality.resistanceLifting);
    repo.failReads = true;

    final effortId = await state.addExerciseToSession(
      exercise,
      effortKindOverride: 'set',
    );

    expect(effortId, isNotEmpty);
    expectEntries(entriesOf(state, effortId), [(10, 0.0)]);
  });

  // S-25010 is Mock only: a routine with many exercises and sets reads the
  // history once per workout, not once per set (plan 250 D-25003).
  test('S-25010 a two-exercise routine reads the sessions of the store '
      'exactly once', () async {
    final repo = _CountingRepo();
    await repo.initialize();
    final lifts = (await repo.getExercises())
        .where(
          (e) =>
              e.capabilities.contains('load') &&
              e.capabilities.contains('reps'),
        )
        .toList();
    final exerciseA = lifts[0];
    final exerciseB = lifts[1];
    await seedHistory(
      repo,
      sessionId: 's1',
      startedAtMs: _s1Start,
      endedAtMs: _s1End,
      sets: [(8, 80.0), (8, 80.0), (6, 82.5)],
      exerciseId: exerciseA.id,
    );
    await seedHistory(
      repo,
      sessionId: 's2',
      startedAtMs: _s2Start,
      endedAtMs: _s2End,
      sets: [(5, 90.0)],
      exerciseId: exerciseB.id,
    );

    final state = WorkoutState(repo);
    await state.createNewSession(modality: Modality.resistanceLifting);
    repo.sessionReads = 0;

    await state.populateSessionFromManifest(
      RoutineSessionManifest(
        template: WorkoutTemplate(
          id: 'tmpl-250-two',
          name: 'Two Lifts',
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
        segments: [
          SessionSegmentEntry(
            segment: TemplateSegment(
              id: 'tseg-250-two',
              templateId: 'tmpl-250-two',
              orderIndex: 0,
              segmentType: 'mixed',
              name: 'Main Work',
              createdAtMs: 1000,
              updatedAtMs: 1000,
            ),
            exercises: [
              SessionExerciseEntry(
                exercise: exerciseA,
                effortKind: 'set',
                setCount: 3,
                targets: [],
              ),
              SessionExerciseEntry(
                exercise: exerciseB,
                effortKind: 'set',
                setCount: 3,
                targets: [],
              ),
            ],
          ),
        ],
      ),
    );

    expect(repo.sessionReads, 1);

    // Both efforts pre-filled from their own exercise's last time.
    final withEntries = state.getExercisesWithEntries();
    final effortA =
        withEntries.firstWhere((map) => map['exerciseId'] == exerciseA.id)['id']
            as String;
    final effortB =
        withEntries.firstWhere((map) => map['exerciseId'] == exerciseB.id)['id']
            as String;
    expectEntries(entriesOf(state, effortA), [(8, 80.0), (8, 80.0), (6, 82.5)]);
    expectEntries(entriesOf(state, effortB), [(5, 90.0), (5, 90.0), (5, 90.0)]);
  });
}

/// A repository whose session reads throw once [failReads] is on: a failed
/// lookup must not fail the add.
class _ThrowingHistoryRepo extends MockWorkoutRepository {
  bool failReads = false;

  @override
  Future<List<TrainingSession>> getAllSessions() async {
    if (failReads) throw StateError('boom');
    return super.getAllSessions();
  }
}

/// A repository that counts its session reads, for the once-per-workout
/// cache.
class _CountingRepo extends MockWorkoutRepository {
  int sessionReads = 0;

  @override
  Future<List<TrainingSession>> getAllSessions() {
    sessionReads++;
    return super.getAllSessions();
  }
}
