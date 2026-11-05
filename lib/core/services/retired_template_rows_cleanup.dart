import '../constants/retired_template_seed.dart';
import '../../data/repositories/workout_repository.dart';

/// One-time removal of the retired seed template rows. This is a deliberate
/// exception to the catalog refresh's never-delete rule, run as data-migration
/// step 17. A row is deleted only if its id is one of the retired ids AND the
/// retired template it hung under does not exist; a segment or effort that
/// still holds a row this cleanup did not delete is kept. Deletion is
/// bottom-up (targets, efforts, segments), so an interrupted run leaves a
/// readable chain and the next run finishes.
class RetiredTemplateRowsCleanup {
  RetiredTemplateRowsCleanup(this._repository);

  final WorkoutRepository _repository;

  Future<void> run() async {
    for (final templateId in RetiredTemplateSeed.templateIds) {
      if (await _repository.getTemplateById(templateId) != null) continue;
      for (final segment in await _repository.getTemplateSegments(templateId)) {
        if (RetiredTemplateSeed.segmentTemplate[segment.id] != templateId) {
          continue;
        }
        await _removeSegment(segment.id);
      }
    }
  }

  Future<void> _removeSegment(String segmentId) async {
    for (final effort in await _repository.getTemplateEfforts(segmentId)) {
      if (RetiredTemplateSeed.effortSegment[effort.id] != segmentId) continue;
      await _removeEffort(effort.id);
    }
    if ((await _repository.getTemplateEfforts(segmentId)).isEmpty) {
      await _repository.deleteTemplateSegment(segmentId);
    }
  }

  Future<void> _removeEffort(String effortId) async {
    for (final target in await _repository.getTemplateTargets(effortId)) {
      if (RetiredTemplateSeed.targetEffort[target.id] != effortId) continue;
      await _repository.deleteTemplateTarget(target.id);
    }
    if ((await _repository.getTemplateTargets(effortId)).isEmpty) {
      await _repository.deleteTemplateEffort(effortId);
    }
  }
}
