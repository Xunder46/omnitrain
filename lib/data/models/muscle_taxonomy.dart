import 'models.dart';

/// One entry of the muscle hierarchy: a region (which has children), a muscle
/// (which belongs to exactly one region), or a standalone entry (Chest, Neck —
/// no parent and no children).
class MuscleTaxonomyEntry {
  const MuscleTaxonomyEntry(this.id, this.name, [this.parentId]);

  final String id;
  final String name;

  /// The parent region's id, or `null` for a region or a standalone entry.
  final String? parentId;
}

/// The single code source of the muscle hierarchy: two levels, no third level.
///
/// [entries] is the ordered list (`SeedData.sampleMuscleGroups` is built from
/// it) and the order is what [ExerciseMuscleLink] storage order follows. The
/// interpretation rules the muscle filter uses live in [matches]; the storage
/// rules live in [normalize].
class MuscleTaxonomy {
  const MuscleTaxonomy._();

  static const List<MuscleTaxonomyEntry> entries = [
    MuscleTaxonomyEntry('muscle-arms', 'Arms'),
    MuscleTaxonomyEntry('muscle-biceps', 'Biceps', 'muscle-arms'),
    MuscleTaxonomyEntry('muscle-triceps', 'Triceps', 'muscle-arms'),
    MuscleTaxonomyEntry('muscle-forearms', 'Forearms', 'muscle-arms'),
    MuscleTaxonomyEntry('muscle-legs', 'Legs'),
    MuscleTaxonomyEntry('muscle-quads', 'Quadriceps', 'muscle-legs'),
    MuscleTaxonomyEntry('muscle-hamstrings', 'Hamstrings', 'muscle-legs'),
    MuscleTaxonomyEntry('muscle-glutes', 'Glutes', 'muscle-legs'),
    MuscleTaxonomyEntry('muscle-calves', 'Calves', 'muscle-legs'),
    MuscleTaxonomyEntry('muscle-adductors', 'Adductors', 'muscle-legs'),
    MuscleTaxonomyEntry('muscle-back', 'Back'),
    MuscleTaxonomyEntry('muscle-lats', 'Lats', 'muscle-back'),
    MuscleTaxonomyEntry('muscle-traps', 'Traps', 'muscle-back'),
    MuscleTaxonomyEntry('muscle-lower-back', 'Lower back', 'muscle-back'),
    MuscleTaxonomyEntry('muscle-shoulders', 'Shoulders'),
    MuscleTaxonomyEntry(
      'muscle-front-delts',
      'Front delts',
      'muscle-shoulders',
    ),
    MuscleTaxonomyEntry('muscle-side-delts', 'Side delts', 'muscle-shoulders'),
    MuscleTaxonomyEntry('muscle-rear-delts', 'Rear delts', 'muscle-shoulders'),
    MuscleTaxonomyEntry('muscle-core', 'Core'),
    MuscleTaxonomyEntry('muscle-abs', 'Abs', 'muscle-core'),
    MuscleTaxonomyEntry('muscle-obliques', 'Obliques', 'muscle-core'),
    MuscleTaxonomyEntry('muscle-chest', 'Chest'),
    MuscleTaxonomyEntry('muscle-neck', 'Neck'),
  ];

  static MuscleTaxonomyEntry? _entry(String id) {
    for (final entry in entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  /// Whether [id] is a region, i.e. it has at least one muscle below it.
  static bool isRegion(String id) {
    for (final entry in entries) {
      if (entry.parentId == id) return true;
    }
    return false;
  }

  /// The region [id] belongs to, or `null` for a region, a standalone entry
  /// and an unknown id.
  static String? regionOf(String id) => _entry(id)?.parentId;

  /// The ids of the muscles directly below [regionId], in taxonomy order.
  static List<String> musclesOf(String regionId) => [
    for (final entry in entries)
      if (entry.parentId == regionId) entry.id,
  ];

  /// The taxonomy position of [id]; unknown ids sort after every known one.
  static int orderIndex(String id) {
    for (var i = 0; i < entries.length; i++) {
      if (entries[i].id == id) return i;
    }
    return entries.length;
  }

  /// Whether an exercise carrying [links] belongs to the [selectedId] filter.
  ///
  /// Only primary links count. A region matches a primary link to the region
  /// itself or to one of its muscles; a muscle, a standalone entry and an
  /// unknown id match on the exact id only, so a region-only link never
  /// matches a muscle.
  static bool matches(String selectedId, List<ExerciseMuscleLink> links) {
    final selectedIsRegion = isRegion(selectedId);
    for (final link in links) {
      if (link.role != MuscleRole.primary) continue;
      if (link.muscleGroupId == selectedId) return true;
      if (selectedIsRegion && regionOf(link.muscleGroupId) == selectedId) {
        return true;
      }
    }
    return false;
  }

  /// The storable form of [links]: de-duplicated, without a region link that
  /// sits next to one of its own muscles, primary before secondary and, inside
  /// a role, in taxonomy order (unknown ids last, by id).
  ///
  /// Throws an [ArgumentError] when one id appears in both roles, or when the
  /// result would be non-empty without a primary. An empty list is valid.
  static List<ExerciseMuscleLink> normalize(List<ExerciseMuscleLink> links) {
    final unique = <ExerciseMuscleLink>[];
    for (final link in links) {
      if (!unique.contains(link)) unique.add(link);
    }

    final primaryIds = <String>{
      for (final link in unique)
        if (link.role == MuscleRole.primary) link.muscleGroupId,
    };
    for (final link in unique) {
      if (link.role == MuscleRole.secondary &&
          primaryIds.contains(link.muscleGroupId)) {
        throw ArgumentError.value(
          link.muscleGroupId,
          'links',
          'A muscle cannot be both primary and secondary',
        );
      }
    }

    final linkedIds = <String>{for (final link in unique) link.muscleGroupId};
    final kept = <ExerciseMuscleLink>[
      for (final link in unique)
        if (!isRegion(link.muscleGroupId) ||
            !musclesOf(link.muscleGroupId).any(linkedIds.contains))
          link,
    ];

    kept.sort(_compare);
    if (kept.isNotEmpty &&
        !kept.any((link) => link.role == MuscleRole.primary)) {
      throw ArgumentError.value(
        links,
        'links',
        'Muscle links must carry at least one primary link',
      );
    }
    return kept;
  }

  static int _compare(ExerciseMuscleLink a, ExerciseMuscleLink b) {
    if (a.role != b.role) return a.role == MuscleRole.primary ? -1 : 1;
    final aIndex = orderIndex(a.muscleGroupId);
    final bIndex = orderIndex(b.muscleGroupId);
    if (aIndex != bIndex) return aIndex.compareTo(bIndex);
    return a.muscleGroupId.compareTo(b.muscleGroupId);
  }
}
