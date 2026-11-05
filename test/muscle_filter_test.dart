// Plan 33, Phase A part 2 — the muscle filter answers by the hierarchy, on
// both implementations.
//
// Scenario S-5 of
// `docs/plans/2026-10-14-33-muscle-hierarchy-data-plan/2026-10-14-33-muscle-hierarchy-data-plan.md`.
//
// Only a primary link matches: selecting a region matches the primary links to
// the region and to its muscles, selecting a muscle matches that id only, and a
// secondary-only link to the selected muscle excludes the exercise. The ranked
// query keeps its own ordering but filters identically. Both stores must
// answer the same, so every case runs over `harnessFactories` with plain
// `test()`.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

import 'helpers/repository_harness.dart';

/// A fixed timestamp: the fixtures take no clock reading.
const int _atMs = 1700000000000;

ExerciseMuscleLink _link(String id, [MuscleRole role = MuscleRole.primary]) =>
    ExerciseMuscleLink(muscleGroupId: id, role: role);

List<String> _ids(List<Exercise> exercises) => [
  for (final exercise in exercises) exercise.id,
];

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — muscle filter', () {
      late WorkoutRepository repo;

      setUp(() async => repo = await harness.open());
      tearDown(() async => await harness.close());

      test('S-5 Legs returns the squat and Tennis Match, each once', () async {
        final ids = _ids(
          await repo.searchExercises(muscleGroupIds: ['muscle-legs']),
        );

        expect(ids.where((id) => id == 'exercise-barbell-squat'), hasLength(1));
        expect(ids.where((id) => id == 'exercise-tennis-match'), hasLength(1));
        expect(
          ids,
          isNot(contains('exercise-bench-press')),
          reason: 'the bench press carries no primary leg link',
        );
      });

      test('S-5 Quadriceps returns the squat, not Tennis Match', () async {
        final ids = _ids(
          await repo.searchExercises(muscleGroupIds: ['muscle-quads']),
        );

        expect(ids, contains('exercise-barbell-squat'));
        expect(ids, isNot(contains('exercise-tennis-match')));
      });

      test('S-5 Triceps returns the pressdown, not the bench press', () async {
        final ids = _ids(
          await repo.searchExercises(muscleGroupIds: ['muscle-triceps']),
        );

        expect(ids, contains('exercise-triceps-pressdown'));
        expect(ids, isNot(contains('exercise-bench-press')));
      });

      test('S-5 Chest returns the bench press', () async {
        final ids = _ids(
          await repo.searchExercises(muscleGroupIds: ['muscle-chest']),
        );

        expect(ids, contains('exercise-bench-press'));
        expect(
          ids,
          isNot(contains('exercise-triceps-pressdown')),
          reason: 'the pressdown is tagged triceps primary, never chest',
        );
      });

      test('S-5 Arms returns the pressdown and Volleyball Match', () async {
        final ids = _ids(
          await repo.searchExercises(muscleGroupIds: ['muscle-arms']),
        );

        expect(ids, contains('exercise-triceps-pressdown'));
        expect(ids, contains('exercise-volleyball-match'));
        expect(
          ids,
          isNot(contains('exercise-bench-press')),
          reason: 'the bench press loads the triceps only as a secondary',
        );
      });

      test('S-5 two selections of the same lift return it once', () async {
        final ids = _ids(
          await repo.searchExercises(
            muscleGroupIds: ['muscle-quads', 'muscle-legs'],
          ),
        );

        expect(ids.where((id) => id == 'exercise-barbell-squat'), hasLength(1));
      });

      test('S-5 the ranked query filters the same way', () async {
        Future<List<String>> ranked(List<String> selected) async => _ids(
          await repo.getExercisesRankedForModality(
            'resistance_lifting',
            muscleGroupIds: selected,
          ),
        );

        final legs = await ranked(['muscle-legs']);
        expect(
          legs.where((id) => id == 'exercise-barbell-squat'),
          hasLength(1),
        );
        expect(legs.where((id) => id == 'exercise-tennis-match'), hasLength(1));

        final quads = await ranked(['muscle-quads']);
        expect(quads, contains('exercise-barbell-squat'));
        expect(quads, isNot(contains('exercise-tennis-match')));

        final triceps = await ranked(['muscle-triceps']);
        expect(triceps, contains('exercise-triceps-pressdown'));
        expect(triceps, isNot(contains('exercise-bench-press')));

        final chest = await ranked(['muscle-chest']);
        expect(chest, contains('exercise-bench-press'));
      });

      test('S-5 a secondary-only link excludes the exercise', () async {
        await repo.createExercise(
          Exercise(
            id: 'ex-secondary-only',
            ownerUserId: 'user-1',
            name: 'Secondary Only Fixture',
            createdAtMs: _atMs,
            updatedAtMs: _atMs,
          ),
        );
        await repo.setExerciseMuscleLinks('ex-secondary-only', [
          _link('muscle-chest'),
          _link('muscle-lats', MuscleRole.secondary),
        ]);

        final lats = _ids(
          await repo.searchExercises(muscleGroupIds: ['muscle-lats']),
        );
        expect(lats, isNot(contains('ex-secondary-only')));

        final back = _ids(
          await repo.searchExercises(muscleGroupIds: ['muscle-back']),
        );
        expect(back, isNot(contains('ex-secondary-only')));

        final chest = _ids(
          await repo.searchExercises(muscleGroupIds: ['muscle-chest']),
        );
        expect(chest, contains('ex-secondary-only'));
      });

      // Plan 114, S-18804 — Shins (`muscle-tibialis`) is a Legs muscle of its
      // own: the bundled Tibialis Raise matches Shins only, an exercise
      // carrying Calves *and* Shins matches both, a secondary-only Shins link
      // matches nothing, and a Legs selection still reaches every leg muscle.
      group('S-18804 Shins filtering on a fresh install', () {
        Future<void> custom(
          String id,
          String name,
          List<ExerciseMuscleLink> links,
        ) async {
          await repo.createExercise(
            Exercise(
              id: id,
              ownerUserId: 'user-1',
              name: name,
              createdAtMs: _atMs,
              updatedAtMs: _atMs,
            ),
          );
          await repo.setExerciseMuscleLinks(id, links);
        }

        test('S-18804 Shins, Calves and Legs by hierarchy', () async {
          // X: two primary leg muscles, one of them the new one.
          await custom('ex-shin-box-hop', 'Shin Box Hop', [
            _link('muscle-calves'),
            _link('muscle-tibialis'),
          ]);
          // Y: Shins as an assist only.
          await custom('ex-step-down', 'Step-Down', [
            _link('muscle-quads'),
            _link('muscle-tibialis', MuscleRole.secondary),
          ]);
          // Z: the region itself, primary.
          await custom('ex-hill-walk', 'Hill Walk', [_link('muscle-legs')]);
          // E: tagged with nothing.
          await custom('ex-mobility-flow', 'Mobility Flow', const []);
          // W: the user's own near-twin of the bundled row — same name,
          // different id, still on Calves.
          await custom('ex-custom-tibialis-raise', 'Tibialis Raise', [
            _link('muscle-calves'),
          ]);

          final shins = _ids(
            await repo.searchExercises(muscleGroupIds: ['muscle-tibialis']),
          );
          expect(
            shins.toSet(),
            equals({'exercise-tibialis-raise', 'ex-shin-box-hop'}),
            reason: 'Shins matches a primary Shins link and nothing else',
          );
          expect(shins, hasLength(2), reason: 'each match appears once');
          expect(
            shins.where((id) => id == 'exercise-tibialis-raise'),
            hasLength(1),
          );
          expect(shins.where((id) => id == 'ex-shin-box-hop'), hasLength(1));
          expect(shins, isNot(contains('ex-step-down')));
          expect(shins, isNot(contains('ex-hill-walk')));
          expect(shins, isNot(contains('ex-custom-tibialis-raise')));
          expect(shins, isNot(contains('ex-mobility-flow')));

          final calves = _ids(
            await repo.searchExercises(muscleGroupIds: ['muscle-calves']),
          );
          expect(calves, contains('ex-shin-box-hop'));
          expect(calves, contains('ex-custom-tibialis-raise'));
          expect(calves, contains('exercise-standing-calf-raise'));
          expect(calves, isNot(contains('exercise-tibialis-raise')));
          expect(calves, isNot(contains('exercise-nordic-curl')));
          expect(calves, isNot(contains('ex-step-down')));

          final legs = _ids(
            await repo.searchExercises(muscleGroupIds: ['muscle-legs']),
          );
          for (final id in [
            'exercise-tibialis-raise',
            'ex-shin-box-hop',
            'ex-step-down',
            'ex-hill-walk',
            'ex-custom-tibialis-raise',
          ]) {
            expect(legs.where((other) => other == id), hasLength(1), reason: id);
          }
          expect(legs, isNot(contains('ex-mobility-flow')));

          final both = _ids(
            await repo.searchExercises(
              muscleGroupIds: ['muscle-tibialis', 'muscle-legs'],
            ),
          );
          expect(
            both.where((id) => id == 'exercise-tibialis-raise'),
            hasLength(1),
            reason: 'two selections of the same lift return it once',
          );

          final unfiltered = _ids(
            await repo.getExercisesRankedForModality('resistance_lifting'),
          );
          final ranked = _ids(
            await repo.getExercisesRankedForModality(
              'resistance_lifting',
              muscleGroupIds: ['muscle-tibialis'],
            ),
          );
          expect(
            ranked,
            equals([
              for (final id in unfiltered)
                if (id == 'exercise-tibialis-raise' || id == 'ex-shin-box-hop')
                  id,
            ]),
            reason: 'the ranked query keeps its order and filters the same way',
          );
          expect(ranked, contains('exercise-tibialis-raise'));
          expect(ranked, contains('ex-shin-box-hop'));
          expect(ranked, isNot(contains('ex-step-down')));
        });
      });

      // Plan 115a, S-18905 — Brachialis, Rotator cuff and Abductors are
      // muscles of their own: the re-tagged bundled rows sit on the new
      // muscle only as a main link, a user's near-twin keeps its own tags,
      // and a secondary-only link to a new muscle matches nothing.
      group('S-18905 Brachialis, Rotator cuff and Abductors', () {
        Future<void> custom(
          String id,
          String name,
          List<ExerciseMuscleLink> links,
        ) async {
          await repo.createExercise(
            Exercise(
              id: id,
              ownerUserId: 'user-1',
              name: name,
              createdAtMs: _atMs,
              updatedAtMs: _atMs,
            ),
          );
          await repo.setExerciseMuscleLinks(id, links);
        }

        test('S-18905 the new muscles, their regions and the re-tags', () async {
          // G: the user tagged it Glutes before the change, and it stays.
          await custom('ex-glute-side-raise', 'Glute Side Raise', [
            _link('muscle-glutes'),
          ]);
          // B: both the old muscle and the new one, primary.
          await custom('ex-band-abduction', 'Band Abduction', [
            _link('muscle-abductors'),
            _link('muscle-glutes'),
          ]);
          // H: the user's own near-twin of the bundled Hammer Curl — same
          // name, its own id, still on Biceps alone.
          await custom('ex-custom-hammer-curl', 'Hammer Curl', [
            _link('muscle-biceps'),
          ]);
          // R: the new muscle as an assist only.
          await custom('ex-shoulder-prehab', 'Shoulder Prehab', [
            _link('muscle-rear-delts'),
            _link('muscle-rotator-cuff', MuscleRole.secondary),
          ]);
          // E: tagged with nothing.
          await custom('ex-empty-move', 'Empty Move', const []);

          const abductionRows = [
            'exercise-cable-hip-abduction',
            'exercise-machine-hip-abduction',
            'exercise-banded-clamshell',
            'exercise-banded-lateral-walk',
          ];
          const cuffRows = [
            'exercise-cable-external-rotation',
            'exercise-side-lying-external-rotation',
            'exercise-cable-internal-rotation',
          ];
          const brachialisRows = [
            'exercise-hammer-curl',
            'exercise-reverse-curl',
            'exercise-zottman-curl',
            'exercise-cross-body-hammer-curl',
          ];

          final abduction = _ids(
            await repo.searchExercises(muscleGroupIds: ['muscle-abductors']),
          );
          expect(
            abduction.toSet(),
            equals({...abductionRows, 'ex-band-abduction'}),
            reason: 'Abductors matches the four bundled rows and the custom',
          );
          expect(abduction, hasLength(5), reason: 'each match appears once');

          final glutes = _ids(
            await repo.searchExercises(muscleGroupIds: ['muscle-glutes']),
          );
          expect(glutes, contains('ex-glute-side-raise'));
          expect(glutes, contains('ex-band-abduction'));
          expect(glutes, contains('exercise-barbell-hip-thrust'));
          expect(
            glutes,
            isNot(contains('exercise-cable-hip-abduction')),
            reason: 'Glutes is only an assist on the re-tagged row',
          );
          expect(
            glutes,
            isNot(contains('exercise-machine-hip-abduction')),
            reason: 'Glutes is only an assist on the new machine row',
          );

          final legs = _ids(
            await repo.searchExercises(muscleGroupIds: ['muscle-legs']),
          );
          for (final id in [
            ...abductionRows,
            'ex-glute-side-raise',
            'ex-band-abduction',
          ]) {
            expect(legs.where((other) => other == id), hasLength(1), reason: id);
          }
          expect(legs, isNot(contains('ex-empty-move')));

          final rotatorCuff = _ids(
            await repo.searchExercises(muscleGroupIds: ['muscle-rotator-cuff']),
          );
          expect(
            rotatorCuff.toSet(),
            equals(cuffRows.toSet()),
            reason: 'only a main Rotator cuff link matches',
          );
          expect(rotatorCuff, hasLength(3));
          expect(rotatorCuff, isNot(contains('ex-shoulder-prehab')));
          expect(
            rotatorCuff,
            isNot(contains('exercise-band-pull-apart')),
            reason: 'the band pull-apart links Rotator cuff as an assist only',
          );

          final rearDelts = _ids(
            await repo.searchExercises(muscleGroupIds: ['muscle-rear-delts']),
          );
          for (final id in [
            'ex-shoulder-prehab',
            'exercise-band-pull-apart',
            'exercise-cable-rear-delt-fly',
            'exercise-reverse-pec-deck',
            'exercise-rear-delt-fly',
          ]) {
            expect(rearDelts, contains(id), reason: id);
          }
          expect(rearDelts, isNot(contains('exercise-cable-external-rotation')));

          final shoulders = _ids(
            await repo.searchExercises(muscleGroupIds: ['muscle-shoulders']),
          );
          expect(
            shoulders.where((id) => id == 'exercise-cable-external-rotation'),
            hasLength(1),
            reason: 'the region reaches the row through Rotator cuff',
          );
          expect(
            shoulders.where((id) => id == 'ex-shoulder-prehab'),
            hasLength(1),
            reason: 'the region reaches the custom through Rear delts',
          );

          final brachialis = _ids(
            await repo.searchExercises(muscleGroupIds: ['muscle-brachialis']),
          );
          expect(brachialis.toSet(), equals(brachialisRows.toSet()));
          expect(brachialis, hasLength(4));
          expect(
            brachialis,
            isNot(contains('ex-custom-hammer-curl')),
            reason: 'the custom twin is tagged Biceps only',
          );

          final biceps = _ids(
            await repo.searchExercises(muscleGroupIds: ['muscle-biceps']),
          );
          expect(biceps, contains('exercise-hammer-curl'));
          expect(biceps, contains('ex-custom-hammer-curl'));
          expect(biceps, contains('exercise-incline-dumbbell-curl'));
          expect(
            biceps,
            isNot(contains('exercise-reverse-curl')),
            reason: 'Biceps is only an assist on the reverse curl',
          );

          final armsAndBrachialis = _ids(
            await repo.searchExercises(
              muscleGroupIds: ['muscle-arms', 'muscle-brachialis'],
            ),
          );
          expect(
            armsAndBrachialis.where((id) => id == 'exercise-hammer-curl'),
            hasLength(1),
            reason: 'two selections that both match return the lift once',
          );

          final unfiltered = _ids(
            await repo.getExercisesRankedForModality('resistance_lifting'),
          );
          final ranked = _ids(
            await repo.getExercisesRankedForModality(
              'resistance_lifting',
              muscleGroupIds: ['muscle-abductors'],
            ),
          );
          final abductorSet = abduction.toSet();
          expect(
            ranked,
            equals([
              for (final id in unfiltered)
                if (abductorSet.contains(id)) id,
            ]),
            reason: 'the ranked query keeps its order and filters the same way',
          );
          expect(ranked, hasLength(5));

          final legExtensionEquipment = await repo.getExerciseEquipment(
            'exercise-leg-extension',
          );
          expect(
            [for (final equipment in legExtensionEquipment) equipment.name],
            equals(['Machine']),
          );

          final bandEquipment = await repo.getExerciseEquipment(
            'exercise-band-pull-apart',
          );
          expect(
            [for (final equipment in bandEquipment) equipment.name],
            equals(['Resistance Band']),
          );
        });
      });

      // Plan 115b, S-19005 — the 20 new rows list under their main muscle
      // only, so Obliques and Calves gain rows while Abductors and Adductors
      // do not; a custom with the same name as a new row keeps its own
      // tagging, and a secondary-only link never matches.
      group('S-19005 the new rows and their main muscles', () {
        Future<void> custom(
          String id,
          String name,
          List<ExerciseMuscleLink> links,
        ) async {
          await repo.createExercise(
            Exercise(
              id: id,
              ownerUserId: 'user-1',
              name: name,
              createdAtMs: _atMs,
              updatedAtMs: _atMs,
            ),
          );
          await repo.setExerciseMuscleLinks(id, links);
        }

        test('S-19005 the new muscles, the near-twin and the re-tags', () async {
          // U: the user's own "Sit-Up" — the same name as a bundled row,
          // abs primary.
          await custom('ex-custom-sit-up', 'Sit-Up', [_link('muscle-abs')]);
          // O: Obliques as an assist only.
          await custom('ex-oblique-reach', 'Oblique Reach', [
            _link('muscle-abs'),
            _link('muscle-obliques', MuscleRole.secondary),
          ]);
          // B: two main links, both inside Core and one inside Back.
          await custom('ex-side-bend', 'Side Bend', [
            _link('muscle-obliques'),
            _link('muscle-lower-back'),
          ]);
          // E: tagged with nothing.
          await custom('ex-hip-flexor-raise', 'Hip Flexor Raise', const []);

          const coreRows = [
            'exercise-sit-up',
            'exercise-crunch',
            'exercise-reverse-crunch',
            'exercise-bicycle-crunch',
            'exercise-russian-twist',
            'exercise-hanging-knee-raise',
            'exercise-dead-bug',
            'exercise-bird-dog',
            'exercise-cable-side-bend',
          ];
          const abductorRows = [
            'exercise-cable-hip-abduction',
            'exercise-machine-hip-abduction',
            'exercise-banded-clamshell',
            'exercise-banded-lateral-walk',
          ];
          const calfRows = [
            'exercise-donkey-calf-raise',
            'exercise-leg-press-calf-raise',
          ];
          const lowerBackRows = [
            'exercise-bird-dog',
            'exercise-rack-pull',
            'exercise-reverse-hyperextension',
          ];
          const gluteRows = [
            'exercise-trap-bar-deadlift',
            'exercise-rack-pull',
            'exercise-lateral-lunge',
            'exercise-curtsy-lunge',
            'exercise-single-leg-hip-thrust',
            'exercise-reverse-hyperextension',
            'exercise-sled-push',
            'exercise-sled-drag',
          ];

          final obliques = _ids(
            await repo.searchExercises(muscleGroupIds: ['muscle-obliques']),
          );
          for (final id in [
            'exercise-bicycle-crunch',
            'exercise-russian-twist',
            'exercise-cable-side-bend',
            'ex-side-bend',
          ]) {
            expect(
              obliques.where((other) => other == id),
              hasLength(1),
              reason: id,
            );
          }
          for (final id in [
            'exercise-sit-up',
            'exercise-crunch',
            'exercise-reverse-crunch',
            'exercise-hanging-knee-raise',
            'exercise-dead-bug',
            'ex-oblique-reach',
          ]) {
            expect(obliques, isNot(contains(id)), reason: id);
          }

          final abs = _ids(
            await repo.searchExercises(muscleGroupIds: ['muscle-abs']),
          );
          for (final id in [
            'exercise-sit-up',
            'exercise-crunch',
            'exercise-reverse-crunch',
            'exercise-bicycle-crunch',
            'exercise-hanging-knee-raise',
            'exercise-dead-bug',
            'exercise-bird-dog',
            'ex-custom-sit-up',
            'ex-oblique-reach',
          ]) {
            expect(abs, contains(id), reason: id);
          }
          expect(
            abs,
            isNot(contains('exercise-russian-twist')),
            reason: 'Russian Twist is tagged Obliques main, Abs assist',
          );
          expect(
            abs,
            isNot(contains('exercise-cable-side-bend')),
            reason: 'Cable Side Bend is tagged Obliques main',
          );

          final core = _ids(
            await repo.searchExercises(muscleGroupIds: ['muscle-core']),
          );
          for (final id in [
            ...coreRows,
            'ex-custom-sit-up',
            'ex-oblique-reach',
            'ex-side-bend',
          ]) {
            expect(core.where((other) => other == id), hasLength(1), reason: id);
          }
          expect(core, isNot(contains('ex-hip-flexor-raise')));

          final lowerBack = _ids(
            await repo.searchExercises(muscleGroupIds: ['muscle-lower-back']),
          );
          for (final id in [...lowerBackRows, 'ex-side-bend']) {
            expect(lowerBack, contains(id), reason: id);
          }
          expect(
            lowerBack,
            isNot(contains('exercise-cable-side-bend')),
            reason: 'Lower back is only an assist on Cable Side Bend',
          );
          expect(
            lowerBack,
            isNot(contains('exercise-trap-bar-deadlift')),
            reason: 'Lower back is only an assist on Trap-Bar Deadlift',
          );

          final back = _ids(
            await repo.searchExercises(muscleGroupIds: ['muscle-back']),
          );
          for (final id in ['exercise-rack-pull', 'exercise-bird-dog']) {
            expect(back.where((other) => other == id), hasLength(1), reason: id);
          }

          final calves = _ids(
            await repo.searchExercises(muscleGroupIds: ['muscle-calves']),
          );
          for (final id in calfRows) {
            expect(calves, contains(id), reason: id);
          }
          for (final id in ['exercise-sled-push', 'exercise-sled-drag']) {
            expect(
              calves,
              isNot(contains(id)),
              reason: '$id tags Calves as an assist only',
            );
          }

          final abductors = _ids(
            await repo.searchExercises(muscleGroupIds: ['muscle-abductors']),
          );
          expect(
            abductors.toSet(),
            equals(abductorRows.toSet()),
            reason: 'the new rows never list Abductors as a main muscle',
          );
          expect(abductors, hasLength(4));
          expect(abductors, isNot(contains('exercise-curtsy-lunge')));

          final adductors = _ids(
            await repo.searchExercises(muscleGroupIds: ['muscle-adductors']),
          );
          expect(
            adductors,
            isNot(contains('exercise-lateral-lunge')),
            reason: 'Adductors is only an assist on Lateral Lunge',
          );

          final glutes = _ids(
            await repo.searchExercises(muscleGroupIds: ['muscle-glutes']),
          );
          for (final id in gluteRows) {
            expect(glutes, contains(id), reason: id);
          }

          final frontDelts = _ids(
            await repo.searchExercises(muscleGroupIds: ['muscle-front-delts']),
          );
          expect(frontDelts, contains('exercise-push-press'));

          final triceps = _ids(
            await repo.searchExercises(muscleGroupIds: ['muscle-triceps']),
          );
          expect(
            triceps,
            isNot(contains('exercise-push-press')),
            reason: 'Triceps is only an assist on Push Press',
          );

          final legsAndGlutes = _ids(
            await repo.searchExercises(
              muscleGroupIds: ['muscle-legs', 'muscle-glutes'],
            ),
          );
          expect(
            legsAndGlutes.where((id) => id == 'exercise-sled-push'),
            hasLength(1),
            reason: 'two selections of the same lift return it once',
          );

          final sitUpSearch = _ids(
            await repo.searchExercises(searchText: 'Sit-Up'),
          );
          expect(sitUpSearch, contains('ex-custom-sit-up'));
          expect(sitUpSearch, contains('exercise-sit-up'));

          final deadBugSearch = _ids(
            await repo.searchExercises(searchText: 'Dead Bug'),
          );
          expect(deadBugSearch, contains('exercise-dead-bug'));
          expect(deadBugSearch, contains('exercise-dead-bug-hold'));

          final unfiltered = _ids(
            await repo.getExercisesRankedForModality('resistance_lifting'),
          );
          final ranked = _ids(
            await repo.getExercisesRankedForModality(
              'resistance_lifting',
              muscleGroupIds: ['muscle-obliques'],
            ),
          );
          final obliquesSet = obliques.toSet();
          expect(
            ranked,
            equals([
              for (final id in unfiltered)
                if (obliquesSet.contains(id)) id,
            ]),
            reason: 'the ranked query keeps its order and filters the same way',
          );
        });
      });
    });
  }
}
