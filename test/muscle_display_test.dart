import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/utils/muscle_display.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/models/muscle_taxonomy.dart';

/// Every taxonomy entry as a [MuscleGroup], minus [exclude].
List<MuscleGroup> _groups({Set<String> exclude = const {}}) => [
  for (final entry in MuscleTaxonomy.entries)
    if (!exclude.contains(entry.id))
      MuscleGroup(
        id: entry.id,
        name: entry.name,
        parentId: entry.parentId,
        createdAtMs: 0,
      ),
];

ExerciseMuscleLink _link(String id, MuscleRole role) =>
    ExerciseMuscleLink(muscleGroupId: id, role: role);

void main() {
  test(
    'S-1 muscleFilterEntries runs standalone, then regions with muscles',
    () {
      final entries = muscleFilterEntries(_groups());

      expect(
        [for (final entry in entries) entry.group.id],
        const [
          'muscle-chest',
          'muscle-neck',
          'muscle-back',
          'muscle-lats',
          'muscle-traps',
          'muscle-lower-back',
          'muscle-shoulders',
          'muscle-front-delts',
          'muscle-side-delts',
          'muscle-rear-delts',
          'muscle-arms',
          'muscle-biceps',
          'muscle-triceps',
          'muscle-forearms',
          'muscle-core',
          'muscle-abs',
          'muscle-obliques',
          'muscle-legs',
          'muscle-quads',
          'muscle-hamstrings',
          'muscle-glutes',
          'muscle-calves',
          'muscle-adductors',
        ],
      );
      expect(entries, hasLength(23));

      const topLevel = [
        'muscle-chest',
        'muscle-neck',
        'muscle-back',
        'muscle-shoulders',
        'muscle-arms',
        'muscle-core',
        'muscle-legs',
      ];
      for (final entry in entries) {
        expect(
          entry.depth,
          topLevel.contains(entry.group.id) ? 0 : 1,
          reason: '${entry.group.id} depth',
        );
      }
    },
  );

  test('S-1 a group missing from the list is skipped, the rest unchanged', () {
    final entries = muscleFilterEntries(_groups(exclude: {'muscle-obliques'}));

    final ids = [for (final entry in entries) entry.group.id];
    expect(ids, isNot(contains('muscle-obliques')));
    expect(ids, hasLength(22));
    expect(
      ids.indexOf('muscle-abs') + 1,
      ids.indexOf('muscle-legs'),
      reason: 'Abs stays directly above the Legs region',
    );

    final full = muscleFilterEntries(_groups());
    expect(
      [for (final entry in full) entry.group.id]
        ..removeWhere((id) => id == 'muscle-obliques'),
      ids,
    );
  });

  test('S-1 muscleNamesWithRole follows the links and their roles', () {
    final groups = _groups();
    final benchPress = [
      _link('muscle-chest', MuscleRole.primary),
      _link('muscle-triceps', MuscleRole.secondary),
      _link('muscle-front-delts', MuscleRole.secondary),
    ];

    expect(muscleNamesWithRole(benchPress, groups, MuscleRole.primary), [
      'Chest',
    ]);
    expect(muscleNamesWithRole(benchPress, groups, MuscleRole.secondary), [
      'Triceps',
      'Front delts',
    ]);

    final tennisMatch = [
      _link('muscle-legs', MuscleRole.primary),
      _link('muscle-shoulders', MuscleRole.primary),
      _link('muscle-core', MuscleRole.primary),
    ];

    expect(muscleNamesWithRole(tennisMatch, groups, MuscleRole.primary), [
      'Legs',
      'Shoulders',
      'Core',
    ]);
    expect(muscleNamesWithRole(tennisMatch, groups, MuscleRole.secondary), []);
  });

  test('S-1 musclesWithRole keeps link order and skips missing groups', () {
    final links = [
      _link('muscle-hamstrings', MuscleRole.primary),
      _link('muscle-gone', MuscleRole.primary),
      _link('muscle-glutes', MuscleRole.primary),
    ];

    final groups = musclesWithRole(links, _groups(), MuscleRole.primary);
    expect(
      [for (final group in groups) group.id],
      ['muscle-hamstrings', 'muscle-glutes'],
    );
    expect(groups.first.name, 'Hamstrings');
  });

  test('S-1 empty links name no muscle', () {
    expect(muscleNamesWithRole(const [], _groups(), MuscleRole.primary), []);
    expect(
      muscleNamesWithRole(const [], _groups(), MuscleRole.secondary),
      isEmpty,
    );
  });

  test('S-1 muscleTaxonomyName resolves known ids and echoes unknown ones', () {
    expect(muscleTaxonomyName('muscle-legs'), 'Legs');
    expect(muscleTaxonomyName('muscle-front-delts'), 'Front delts');
    expect(muscleTaxonomyName('muscle-nothing'), 'muscle-nothing');
  });

  test('S-1 the constants carry the display order', () {
    expect(kMuscleStandaloneIds, ['muscle-chest', 'muscle-neck']);
    expect(kMuscleRegionOrder, [
      'muscle-back',
      'muscle-shoulders',
      'muscle-arms',
      'muscle-core',
      'muscle-legs',
    ]);
  });
}
