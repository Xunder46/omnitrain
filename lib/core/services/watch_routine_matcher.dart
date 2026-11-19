/// Finds the phone's own routine a wrist run is a run of, from slot ids alone.
///
/// Plan 125a D-125-3: the link the wire never carries, read off the ladder. A
/// slot id is `sx-` and a template effort id (the wrist suffixes a
/// per-session token after the last `~`, plan 81 D-4), so a run whose every
/// slot names an effort of one template is that template's run. The first
/// template `getTemplates` lists that covers every slot wins.
library;

import '../../data/models/models.dart';
import '../../data/repositories/workout_repository.dart';

class WatchRoutineMatcher {
  WatchRoutineMatcher(this._repository);

  static const String _slotIdPrefix = 'sx-';

  final WorkoutRepository _repository;

  /// The effort id a slot id carries: `sx-<effortId>~<token>` decodes to the
  /// text before the LAST `~`; an id without `~` decodes as before. Null when
  /// the id lacks the `sx-` prefix or has no effort id after it.
  static String? effortIdOf(String slotId) {
    if (!slotId.startsWith(_slotIdPrefix)) return null;
    final rest = slotId.substring(_slotIdPrefix.length);
    final effortId = rest.contains('~')
        ? rest.substring(0, rest.lastIndexOf('~'))
        : rest;
    return effortId.isEmpty ? null : effortId;
  }

  /// The routine [slotIds] spell, or null. Null for no slots, a malformed
  /// slot id, and an effort id no template holds.
  Future<WorkoutTemplate?> templateFor(Iterable<String> slotIds) async {
    final effortIdBySlot = <String, String>{};
    for (final slotId in slotIds) {
      final effortId = effortIdOf(slotId);
      if (effortId == null) return null;
      effortIdBySlot[slotId] = effortId;
    }
    if (effortIdBySlot.isEmpty) return null;

    for (final template in await _repository.getTemplates()) {
      final effortIds = <String>{};
      for (final segment in await _repository.getTemplateSegments(
        template.id,
      )) {
        for (final effort in await _repository.getTemplateEfforts(segment.id)) {
          effortIds.add(effort.id);
        }
      }
      if (effortIdBySlot.values.every(effortIds.contains)) return template;
    }
    return null;
  }
}
