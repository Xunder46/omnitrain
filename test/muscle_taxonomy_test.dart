// Plan 33, Phase A part 2 — the muscle hierarchy and its interpretation rules.
//
// Scenarios S-1 (taxonomy integrity) and S-2 (interpretation: `matches` and
// `normalize`) of
// `docs/plans/2026-10-14-33-muscle-hierarchy-data-plan/2026-10-14-33-muscle-hierarchy-data-plan.md`.
//
// `MuscleTaxonomy` is the single code source of the hierarchy: two levels, one
// region per muscle, and `SeedData.sampleMuscleGroups` is built from it. Only a
// primary link matches a filter, a region selection matches the primary links
// to the region and to its own muscles, and storage order is the normalised
// one (primary first, taxonomy order).

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/models/muscle_taxonomy.dart';
import 'package:omnitrain/mock/seed_data.dart';

ExerciseMuscleLink _link(String id, [MuscleRole role = MuscleRole.primary]) =>
    ExerciseMuscleLink(muscleGroupId: id, role: role);

List<String> _ids(List<ExerciseMuscleLink> links) => [
  for (final link in links) link.muscleGroupId,
];

void main() {
  group('S-1 taxonomy integrity', () {
    test('27 entries: 5 regions, 20 muscles, 2 standalone', () {
      expect(MuscleTaxonomy.entries, hasLength(27));

      final regions = {
        for (final entry in MuscleTaxonomy.entries)
          if (MuscleTaxonomy.isRegion(entry.id)) entry.id,
      };
      expect(regions, {
        'muscle-arms',
        'muscle-legs',
        'muscle-back',
        'muscle-shoulders',
        'muscle-core',
      });

      final muscles = {
        for (final entry in MuscleTaxonomy.entries)
          if (entry.parentId != null) entry.id,
      };
      expect(muscles, hasLength(20));

      final standalone = {
        for (final entry in MuscleTaxonomy.entries)
          if (entry.parentId == null && !MuscleTaxonomy.isRegion(entry.id))
            entry.id,
      };
      expect(standalone, {'muscle-chest', 'muscle-neck'});
    });

    test('musclesOf lists the muscles of a region', () {
      expect(MuscleTaxonomy.musclesOf('muscle-legs'), const [
        'muscle-quads',
        'muscle-hamstrings',
        'muscle-glutes',
        'muscle-calves',
        'muscle-tibialis',
        'muscle-adductors',
        'muscle-abductors',
      ]);
      expect(MuscleTaxonomy.musclesOf('muscle-back').toSet(), {
        'muscle-lats',
        'muscle-traps',
        'muscle-lower-back',
      });
      expect(MuscleTaxonomy.musclesOf('muscle-chest'), isEmpty);
      expect(MuscleTaxonomy.musclesOf('muscle-neck'), isEmpty);
    });

    test('Chest and Neck are standalone: no parent, no children', () {
      expect(MuscleTaxonomy.regionOf('muscle-chest'), isNull);
      expect(MuscleTaxonomy.regionOf('muscle-neck'), isNull);
      expect(MuscleTaxonomy.isRegion('muscle-chest'), isFalse);
      expect(MuscleTaxonomy.isRegion('muscle-neck'), isFalse);
    });

    test('no entry hangs off a muscle: the hierarchy has two levels', () {
      for (final entry in MuscleTaxonomy.entries) {
        final parent = entry.parentId;
        if (parent == null) continue;
        expect(
          MuscleTaxonomy.regionOf(parent),
          isNull,
          reason:
              '${entry.id} hangs off $parent, which is itself a child '
              '(a third level)',
        );
        expect(MuscleTaxonomy.isRegion(parent), isTrue);
      }
    });

    test('the 16 pre-existing ids all survive', () {
      final ids = {for (final entry in MuscleTaxonomy.entries) entry.id};
      expect(
        ids,
        containsAll(const [
          'muscle-arms',
          'muscle-biceps',
          'muscle-triceps',
          'muscle-forearms',
          'muscle-legs',
          'muscle-quads',
          'muscle-hamstrings',
          'muscle-glutes',
          'muscle-calves',
          'muscle-adductors',
          'muscle-back',
          'muscle-traps',
          'muscle-shoulders',
          'muscle-core',
          'muscle-chest',
          'muscle-neck',
        ]),
      );
      expect(MuscleTaxonomy.regionOf('muscle-quads'), 'muscle-legs');
      expect(MuscleTaxonomy.regionOf('muscle-arms'), isNull);
    });

    test('S-18901: Brachialis, Rotator cuff and Abductors sit in their '
        'regions', () {
      expect(MuscleTaxonomy.entries, hasLength(27));

      expect(MuscleTaxonomy.musclesOf('muscle-arms'), const [
        'muscle-biceps',
        'muscle-triceps',
        'muscle-forearms',
        'muscle-brachialis',
      ]);
      expect(MuscleTaxonomy.musclesOf('muscle-shoulders'), const [
        'muscle-front-delts',
        'muscle-side-delts',
        'muscle-rear-delts',
        'muscle-rotator-cuff',
      ]);
      expect(MuscleTaxonomy.musclesOf('muscle-legs'), const [
        'muscle-quads',
        'muscle-hamstrings',
        'muscle-glutes',
        'muscle-calves',
        'muscle-tibialis',
        'muscle-adductors',
        'muscle-abductors',
      ]);

      for (final entry in const {
        'muscle-brachialis': ('Brachialis', 'muscle-arms'),
        'muscle-rotator-cuff': ('Rotator cuff', 'muscle-shoulders'),
        'muscle-abductors': ('Abductors', 'muscle-legs'),
      }.entries) {
        expect(
          MuscleTaxonomy.regionOf(entry.key),
          entry.value.$2,
          reason: '${entry.key} belongs to its region',
        );
        expect(MuscleTaxonomy.isRegion(entry.key), isFalse);
        final found = MuscleTaxonomy.entries.firstWhere(
          (candidate) => candidate.id == entry.key,
        );
        expect(found.name, entry.value.$1);
      }
    });

    test('S-18801: Shins sits under Legs, after Calves', () {
      expect(MuscleTaxonomy.entries, hasLength(27));

      final regions = {
        for (final entry in MuscleTaxonomy.entries)
          if (MuscleTaxonomy.isRegion(entry.id)) entry.id,
      };
      expect(regions, {
        'muscle-arms',
        'muscle-legs',
        'muscle-back',
        'muscle-shoulders',
        'muscle-core',
      });

      final muscles = {
        for (final entry in MuscleTaxonomy.entries)
          if (entry.parentId != null) entry.id,
      };
      expect(muscles, hasLength(20));

      expect(MuscleTaxonomy.musclesOf('muscle-legs'), const [
        'muscle-quads',
        'muscle-hamstrings',
        'muscle-glutes',
        'muscle-calves',
        'muscle-tibialis',
        'muscle-adductors',
        'muscle-abductors',
      ]);

      expect(MuscleTaxonomy.regionOf('muscle-tibialis'), 'muscle-legs');
      expect(MuscleTaxonomy.isRegion('muscle-tibialis'), isFalse);

      final tibialis = MuscleTaxonomy.entries.firstWhere(
        (entry) => entry.id == 'muscle-tibialis',
      );
      expect(tibialis.name, 'Shins');

      final groups = SeedData.sampleMuscleGroups;
      expect(
        [for (final group in groups) group.id],
        [for (final entry in MuscleTaxonomy.entries) entry.id],
      );
      expect(
        [for (final group in groups) group.name],
        [for (final entry in MuscleTaxonomy.entries) entry.name],
      );
      expect(
        [for (final group in groups) group.parentId],
        [for (final entry in MuscleTaxonomy.entries) entry.parentId],
      );
    });

    test('sampleMuscleGroups mirrors the taxonomy, Traps included', () {
      final groups = SeedData.sampleMuscleGroups;
      expect(
        [for (final group in groups) group.id],
        [for (final entry in MuscleTaxonomy.entries) entry.id],
      );
      expect(
        [for (final group in groups) group.name],
        [for (final entry in MuscleTaxonomy.entries) entry.name],
      );
      expect(
        [for (final group in groups) group.parentId],
        [for (final entry in MuscleTaxonomy.entries) entry.parentId],
      );
      expect(
        groups.firstWhere((group) => group.id == 'muscle-traps').name,
        'Traps',
      );
    });
  });

  group('S-2 interpretation', () {
    test('a region matches its muscles; a muscle matches its own id only', () {
      final quadsAndGlutes = [_link('muscle-quads'), _link('muscle-glutes')];
      expect(MuscleTaxonomy.matches('muscle-legs', quadsAndGlutes), isTrue);
      expect(MuscleTaxonomy.matches('muscle-quads', quadsAndGlutes), isTrue);
      expect(
        MuscleTaxonomy.matches('muscle-hamstrings', quadsAndGlutes),
        isFalse,
      );

      final regionOnly = [_link('muscle-legs')];
      expect(MuscleTaxonomy.matches('muscle-legs', regionOnly), isTrue);
      expect(MuscleTaxonomy.matches('muscle-quads', regionOnly), isFalse);
    });

    test('only primary links match, so a secondary muscle never does', () {
      final bench = [
        _link('muscle-chest'),
        _link('muscle-triceps', MuscleRole.secondary),
      ];
      expect(MuscleTaxonomy.matches('muscle-triceps', bench), isFalse);
      expect(MuscleTaxonomy.matches('muscle-chest', bench), isTrue);
      expect(MuscleTaxonomy.matches('muscle-arms', bench), isFalse);
    });

    test('normalize drops the region that sits next to its own muscle', () {
      expect(
        MuscleTaxonomy.normalize([_link('muscle-legs'), _link('muscle-quads')]),
        [_link('muscle-quads')],
      );
    });

    test('normalize keeps a valid pair of primaries, in taxonomy order', () {
      final chestAndTriceps = [_link('muscle-chest'), _link('muscle-triceps')];
      // Both links survive untouched; the stored order is the taxonomy's, and
      // D-2 puts Triceps (index 2) before Chest (index 21).
      expect(MuscleTaxonomy.normalize(chestAndTriceps).toSet(), {
        _link('muscle-chest'),
        _link('muscle-triceps'),
      });
      expect(_ids(MuscleTaxonomy.normalize(chestAndTriceps)), [
        'muscle-triceps',
        'muscle-chest',
      ]);
    });

    test('normalize throws for a secondary without a primary', () {
      expect(
        () => MuscleTaxonomy.normalize([
          _link('muscle-triceps', MuscleRole.secondary),
        ]),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('normalize throws when one id carries both roles', () {
      expect(
        () => MuscleTaxonomy.normalize([
          _link('muscle-quads'),
          _link('muscle-quads', MuscleRole.secondary),
        ]),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('normalize accepts an empty list', () {
      expect(MuscleTaxonomy.normalize(const []), isEmpty);
    });

    test('normalize sorts primary first, then the secondary links', () {
      expect(
        _ids(
          MuscleTaxonomy.normalize([
            _link('muscle-glutes', MuscleRole.secondary),
            _link('muscle-quads'),
            _link('muscle-chest'),
          ]),
        ),
        ['muscle-quads', 'muscle-chest', 'muscle-glutes'],
      );
    });

    test('S-18802: storage rules with Shins', () {
      // (a) A region link next to its own muscle is dropped.
      expect(
        MuscleTaxonomy.normalize([
          _link('muscle-legs'),
          _link('muscle-tibialis'),
        ]),
        [_link('muscle-tibialis')],
      );

      // (b) Both primaries survive, in taxonomy order.
      expect(
        MuscleTaxonomy.normalize([
          _link('muscle-tibialis'),
          _link('muscle-calves'),
        ]),
        [_link('muscle-calves'), _link('muscle-tibialis')],
      );

      // (c) Shins sorts before Adductors.
      expect(
        MuscleTaxonomy.normalize([
          _link('muscle-adductors'),
          _link('muscle-tibialis'),
        ]),
        [_link('muscle-tibialis'), _link('muscle-adductors')],
      );

      // (d) A secondary without a primary throws.
      expect(
        () => MuscleTaxonomy.normalize([
          _link('muscle-tibialis', MuscleRole.secondary),
        ]),
        throwsA(isA<ArgumentError>()),
      );

      // (e) One id in both roles throws.
      expect(
        () => MuscleTaxonomy.normalize([
          _link('muscle-tibialis'),
          _link('muscle-tibialis', MuscleRole.secondary),
        ]),
        throwsA(isA<ArgumentError>()),
      );

      // (f) Identical links are de-duplicated.
      expect(
        MuscleTaxonomy.normalize([
          _link('muscle-tibialis'),
          _link('muscle-tibialis'),
        ]),
        [_link('muscle-tibialis')],
      );

      // (g) Selecting Legs matches a primary Shins link.
      expect(
        MuscleTaxonomy.matches('muscle-legs', [_link('muscle-tibialis')]),
        isTrue,
      );

      // (h) Calves does not match a Shins link.
      expect(
        MuscleTaxonomy.matches('muscle-calves', [_link('muscle-tibialis')]),
        isFalse,
      );

      // (i) A secondary Shins link never matches Shins.
      expect(
        MuscleTaxonomy.matches('muscle-tibialis', [
          _link('muscle-calves'),
          _link('muscle-tibialis', MuscleRole.secondary),
        ]),
        isFalse,
      );
    });

    test('S-18902: storage rules with the new muscles', () {
      // (a) Arms is dropped next to its own new muscle.
      expect(
        MuscleTaxonomy.normalize([
          _link('muscle-arms'),
          _link('muscle-brachialis'),
        ]),
        [_link('muscle-brachialis')],
      );

      // (b) Both primaries survive, in taxonomy order.
      expect(
        MuscleTaxonomy.normalize([
          _link('muscle-brachialis'),
          _link('muscle-biceps'),
        ]),
        [_link('muscle-biceps'), _link('muscle-brachialis')],
      );

      // (c) Abductors sorts after Adductors.
      expect(
        MuscleTaxonomy.normalize([
          _link('muscle-abductors'),
          _link('muscle-adductors'),
        ]),
        [_link('muscle-adductors'), _link('muscle-abductors')],
      );

      // (d) Shoulders is dropped next to its own muscles.
      expect(
        MuscleTaxonomy.normalize([
          _link('muscle-shoulders'),
          _link('muscle-rotator-cuff'),
          _link('muscle-rear-delts', MuscleRole.secondary),
        ]),
        [
          _link('muscle-rotator-cuff'),
          _link('muscle-rear-delts', MuscleRole.secondary),
        ],
      );

      // (e) One id in both roles throws.
      expect(
        () => MuscleTaxonomy.normalize([
          _link('muscle-abductors'),
          _link('muscle-abductors', MuscleRole.secondary),
        ]),
        throwsA(isA<ArgumentError>()),
      );

      // Region filters match a primary link to a new muscle; a secondary or
      // another muscle's primary link never matches.
      expect(
        MuscleTaxonomy.matches('muscle-legs', [_link('muscle-abductors')]),
        isTrue,
      );
      expect(
        MuscleTaxonomy.matches('muscle-glutes', [
          _link('muscle-abductors'),
          _link('muscle-glutes', MuscleRole.secondary),
        ]),
        isFalse,
      );
      expect(
        MuscleTaxonomy.matches('muscle-shoulders', [
          _link('muscle-rotator-cuff'),
        ]),
        isTrue,
      );
      expect(
        MuscleTaxonomy.matches('muscle-rear-delts', [
          _link('muscle-rotator-cuff'),
          _link('muscle-rear-delts', MuscleRole.secondary),
        ]),
        isFalse,
      );
      expect(
        MuscleTaxonomy.matches('muscle-arms', [_link('muscle-brachialis')]),
        isTrue,
      );
    });
  });
}
