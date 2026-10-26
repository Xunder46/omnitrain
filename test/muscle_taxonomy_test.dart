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
    test('23 entries: 5 regions, 16 muscles, 2 standalone', () {
      expect(MuscleTaxonomy.entries, hasLength(23));

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
      expect(muscles, hasLength(16));

      final standalone = {
        for (final entry in MuscleTaxonomy.entries)
          if (entry.parentId == null && !MuscleTaxonomy.isRegion(entry.id))
            entry.id,
      };
      expect(standalone, {'muscle-chest', 'muscle-neck'});
    });

    test('musclesOf lists the muscles of a region', () {
      expect(MuscleTaxonomy.musclesOf('muscle-legs').toSet(), {
        'muscle-quads',
        'muscle-hamstrings',
        'muscle-glutes',
        'muscle-calves',
        'muscle-adductors',
      });
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
  });
}
