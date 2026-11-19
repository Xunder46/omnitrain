import '../../data/models/models.dart';
import '../../data/models/muscle_taxonomy.dart';

/// The muscle choices of the exercise editor: an immutable map from a muscle
/// group id to the role the exercise gives it.
///
/// [cycle] is the editor's single mutation path: off → primary → secondary →
/// off. A region and one of its own muscles can never carry a role at the same
/// time — [cycle] drops the region the moment a muscle gains one, and
/// [MuscleSelection.fromLinks] drops the region it finds next to its muscle.
class MuscleSelection {
  MuscleSelection([Map<String, MuscleRole> roles = const {}])
    : _roles = Map.unmodifiable(roles);

  /// The selection stored in [links], in the editor's shape.
  ///
  /// A region entry whose own muscle is present is dropped, so a stored
  /// region-plus-muscle pair opens as the muscle alone; for a duplicated id
  /// the primary role wins.
  factory MuscleSelection.fromLinks(List<ExerciseMuscleLink> links) {
    final presentIds = {for (final link in links) link.muscleGroupId};
    final roles = <String, MuscleRole>{};
    for (final link in links) {
      if (MuscleTaxonomy.isRegion(link.muscleGroupId) &&
          MuscleTaxonomy.musclesOf(
            link.muscleGroupId,
          ).any(presentIds.contains)) {
        continue;
      }
      if (roles[link.muscleGroupId] == MuscleRole.primary) continue;
      roles[link.muscleGroupId] = link.role;
    }
    return MuscleSelection(roles);
  }

  final Map<String, MuscleRole> _roles;

  /// The role [id] carries, or `null` when it is not chosen.
  MuscleRole? roleOf(String id) => _roles[id];

  /// Whether at least one of [regionId]'s own muscles carries a role; only
  /// then can the region chip not be tapped.
  bool isCovered(String regionId) {
    if (!MuscleTaxonomy.isRegion(regionId)) return false;
    return MuscleTaxonomy.musclesOf(regionId).any(_roles.containsKey);
  }

  /// The next selection in the off → main → assists → off cycle.
  ///
  /// A covered region is inert and returns this selection unchanged. A muscle
  /// gaining its first role also removes its region's own entry.
  MuscleSelection cycle(String id) {
    if (isCovered(id)) return this;

    final roles = Map<String, MuscleRole>.from(_roles);
    final role = _roles[id];
    if (role == null) {
      roles[id] = MuscleRole.primary;
      final regionId = MuscleTaxonomy.regionOf(id);
      if (regionId != null) roles.remove(regionId);
    } else if (role == MuscleRole.primary) {
      roles[id] = MuscleRole.secondary;
    } else {
      roles.remove(id);
    }
    return MuscleSelection(roles);
  }

  /// The chosen ids carrying [role], in taxonomy order, unknown ids last.
  List<String> idsWith(MuscleRole role) {
    final ids = [
      for (final entry in _roles.entries)
        if (entry.value == role) entry.key,
    ];
    ids.sort((a, b) {
      final aIndex = MuscleTaxonomy.orderIndex(a);
      final bIndex = MuscleTaxonomy.orderIndex(b);
      if (aIndex != bIndex) return aIndex.compareTo(bIndex);
      return a.compareTo(b);
    });
    return ids;
  }

  bool get isEmpty => _roles.isEmpty;

  bool get hasPrimary => _roles.values.contains(MuscleRole.primary);

  /// Whether the selection is non-empty and carries no primary muscle.
  bool get hasOnlyAssists => _roles.isNotEmpty && !hasPrimary;

  /// The storable form of the selection, in [MuscleTaxonomy.normalize] order.
  ///
  /// Throws an [ArgumentError] for a selection of assists alone; callers check
  /// [hasOnlyAssists] first.
  List<ExerciseMuscleLink> toLinks() => MuscleTaxonomy.normalize([
    for (final entry in _roles.entries)
      ExerciseMuscleLink(muscleGroupId: entry.key, role: entry.value),
  ]);

  @override
  bool operator ==(Object other) {
    if (other is! MuscleSelection) return false;
    if (other._roles.length != _roles.length) return false;
    for (final entry in _roles.entries) {
      if (other._roles[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    var hash = 0;
    for (final entry in _roles.entries) {
      hash ^= Object.hash(entry.key, entry.value);
    }
    return hash;
  }

  @override
  String toString() =>
      'MuscleSelection({'
      '${[for (final id in idsWith(MuscleRole.primary)) '$id: primary', for (final id in idsWith(MuscleRole.secondary)) '$id: secondary'].join(', ')}})';
}
