import '../../data/models/models.dart';
import '../../data/models/muscle_taxonomy.dart';

/// The standalone muscle ids of the display order: no region, no indent.
const List<String> kMuscleStandaloneIds = ['muscle-chest', 'muscle-neck'];

/// The regions of the display order, each followed by its own muscles.
const List<String> kMuscleRegionOrder = [
  'muscle-back',
  'muscle-shoulders',
  'muscle-arms',
  'muscle-core',
  'muscle-legs',
];

/// One row of the muscle filter: the group it shows and how far it is
/// indented — 0 for a standalone entry and a region, 1 for a muscle.
class MuscleFilterEntry {
  const MuscleFilterEntry(this.group, this.depth);

  final MuscleGroup group;
  final int depth;
}

/// Taxonomy name of [id] ('Legs' for 'muscle-legs'); the id itself for an id
/// the taxonomy does not know.
String muscleTaxonomyName(String id) {
  for (final entry in MuscleTaxonomy.entries) {
    if (entry.id == id) return entry.name;
  }
  return id;
}

/// The picker filter's entries: the standalone ids first (depth 0), then each
/// region of [kMuscleRegionOrder] (depth 0) followed by its muscles (depth 1),
/// both in taxonomy order. An id missing from [groups] is skipped.
List<MuscleFilterEntry> muscleFilterEntries(List<MuscleGroup> groups) {
  final byId = {for (final group in groups) group.id: group};
  final entries = <MuscleFilterEntry>[];
  void add(String id, int depth) {
    final group = byId[id];
    if (group != null) entries.add(MuscleFilterEntry(group, depth));
  }

  for (final id in kMuscleStandaloneIds) {
    add(id, 0);
  }
  for (final regionId in kMuscleRegionOrder) {
    add(regionId, 0);
    for (final id in MuscleTaxonomy.musclesOf(regionId)) {
      add(id, 1);
    }
  }
  return entries;
}

/// The groups of the links carrying [role], in link order; a link whose group
/// is missing from [groups] is skipped.
List<MuscleGroup> musclesWithRole(
  List<ExerciseMuscleLink> links,
  List<MuscleGroup> groups,
  MuscleRole role,
) {
  final byId = {for (final group in groups) group.id: group};
  final result = <MuscleGroup>[];
  for (final link in links) {
    if (link.role != role) continue;
    final group = byId[link.muscleGroupId];
    if (group != null) result.add(group);
  }
  return result;
}

/// The names of [musclesWithRole].
List<String> muscleNamesWithRole(
  List<ExerciseMuscleLink> links,
  List<MuscleGroup> groups,
  MuscleRole role,
) => [for (final group in musclesWithRole(links, groups, role)) group.name];
