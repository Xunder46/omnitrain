import '../../core/constants/catalog_version.dart';
import '../../core/models/demo_routine_spec.dart';
import '../../data/models/models.dart';
import '../../data/repositories/workout_repository.dart';
import 'catalog_source.dart';

/// Reconciles the device's stored catalog against the bundled catalog.
///
/// At app start, [refresh] compares the device's stored catalog version
/// (via [WorkoutRepository.getCatalogVersion]) against the bundled
/// [CatalogSource.version]. If the bundled version is newer, every
/// seed-authored entity the device is missing is added, every
/// untouched seed-authored entity whose bundled content differs is
/// updated, and every seed-authored entity the user has touched is
/// left alone. User-created entries are never read or modified.
///
/// ## Invariants
///
/// - **Additive and corrective**: only adds or updates app-authored
///   rows. Never deletes any row. Never overwrites a row whose id
///   does not appear in the bundled catalog (so user-created rows
///   survive).
/// - **User-edits respected**: rows the user has touched (per the
///   per-entry tombstone markers set by the state layer) are skipped.
/// - **Interruption-safe**: each entity is read, compared, and written
///   individually. On a mid-loop failure the orchestrator re-throws
///   without advancing the stored version, so the next launch retries
///   the refresh from where it left off.
/// - **Idempotent**: a second [refresh] call after a successful first
///   call is a no-op (versions already match).
/// - **Update-in-place**: rows are never cleared then re-populated.
///   Existing rows are diffed against the bundled source and patched
///   one at a time.
///
/// ## Data-source pluggability
///
/// The orchestrator depends only on the [CatalogSource] interface; the
/// bundled implementation can be swapped for a remote / server-provided
/// one without touching this class.
class CatalogRefreshService {
  CatalogRefreshService(this._repository, this._source);

  final WorkoutRepository _repository;
  final CatalogSource _source;

  /// Run the catalog reconciliation.
  ///
  /// Returns `true` when a refresh actually ran, `false` when the device
  /// is already at or beyond the bundled version.
  ///
  /// Re-throws on any mid-refresh failure; the stored catalog version is
  /// NOT advanced on failure, so the next launch retries the work.
  Future<bool> refresh() async {
    final storedVersion = await _repository.getCatalogVersion();
    if (storedVersion >= _source.version) {
      return false;
    }

    await _refreshExercises();
    await _refreshExerciseCapabilities();
    await _refreshMuscleGroups();
    await _refreshExerciseMuscleGroups();
    await _refreshFoodCatalog();
    await _refreshDemoRoutines();

    await _repository.setCatalogVersion(_source.version);
    return true;
  }

  Future<void> _refreshExercises() async {
    for (final seedExercise in _source.exercises) {
      if (await _repository.isSeedEntryTouched(
        SeedEntryType.exercise,
        seedExercise.id,
      )) {
        continue;
      }

      final existing = await _repository.getExerciseById(seedExercise.id);
      if (existing == null) {
        await _repository.createExercise(seedExercise);
        continue;
      }

      if (_exerciseDiffers(existing, seedExercise)) {
        await _repository.updateExercise(seedExercise);
      }
    }
  }

  Future<void> _refreshExerciseCapabilities() async {
    for (final entry in _source.exerciseCapabilities.entries) {
      final exerciseId = entry.key;
      if (await _repository.isSeedEntryTouched(
        SeedEntryType.exercise,
        exerciseId,
      )) {
        continue;
      }

      final existing = await _repository.getExerciseCapabilities(exerciseId);
      final bundled = List<String>.from(entry.value);
      if (!_listEqualsIgnoreOrder(existing, bundled)) {
        await _repository.setExerciseCapabilities(exerciseId, bundled);
      }
    }
  }

  /// Add muscle groups the device is missing and patch renamed ones.
  ///
  /// Runs before [_refreshExerciseMuscleGroups] so a relationship written by
  /// that step always resolves. There is no touched-entry check here: muscle
  /// groups are app-authored reference data with no user-editing surface.
  Future<void> _refreshMuscleGroups() async {
    final existing = {for (final g in await _repository.getMuscleGroups()) g.id: g};

    for (final bundled in _source.muscleGroups) {
      final current = existing[bundled.id];
      if (current == null || current.name != bundled.name) {
        await _repository.upsertMuscleGroup(bundled);
      }
    }
  }

  Future<void> _refreshExerciseMuscleGroups() async {
    for (final entry in _source.exerciseMuscleGroups.entries) {
      final exerciseId = entry.key;
      if (await _repository.isSeedEntryTouched(
        SeedEntryType.exercise,
        exerciseId,
      )) {
        continue;
      }

      final existing = await _repository.getExerciseMuscleGroups(exerciseId);
      final existingIds = existing.map((m) => m.id).toList();
      final bundled = List<String>.from(entry.value);
      if (!_listEqualsIgnoreOrder(existingIds, bundled)) {
        await _repository.setExerciseMuscleGroups(exerciseId, bundled);
      }
    }
  }

  Future<void> _refreshFoodCatalog() async {
    for (final bundledFood in _source.foodCatalog) {
      if (await _repository.isSeedEntryTouched(
        SeedEntryType.foodCatalog,
        bundledFood.id,
      )) {
        continue;
      }

      final existing = await _repository.getCatalogFoodById(bundledFood.id);
      if (existing == null) {
        await _repository.createCatalogFood(bundledFood);
        continue;
      }

      if (_foodDiffers(existing, bundledFood)) {
        await _repository.updateCatalogFood(bundledFood);
      }
    }
  }

  /// Reconcile bundled demo [WorkoutTemplate]s onto the device.
  ///
  /// Each bundle contains a template + segments + efforts + targets; the
  /// orchestrator writes the whole subtree in one shot so the device never
  /// observes a half-written demo. User edits and deletions are tracked via
  /// the per-entry tombstone returned by
  /// [WorkoutRepository.isSeedEntryTouched] for [SeedEntryType.routineTemplate]
  /// — a touched demo is skipped entirely so the user's mutation (or
  /// delete) remains authoritative.
  ///
  /// A previously-stored demo that has been *deleted* leaves no row behind
  /// for the in-place-update path: the existing-row check returns `null`
  /// and the bundled content is re-created. That's why the state layer
  /// must call [WorkoutRepository.markSeedEntryTouched] for
  /// [SeedEntryType.routineTemplate] whenever the user deletes or edits a
  /// demo.
  Future<void> _refreshDemoRoutines() async {
    for (final bundle in _source.routineTemplates) {
      final templateId = bundle.template.id;
      if (await _repository.isSeedEntryTouched(
        SeedEntryType.routineTemplate,
        templateId,
      )) {
        continue;
      }

      final existing = await _repository.getTemplateById(templateId);
      if (existing == null) {
        await _writeFullDemoBundle(bundle);
        continue;
      }

      if (_demoBundleTemplateDiffers(existing, bundle.template)) {
        // Patch the template row in place and let the existing
        // segments/efforts/targets stay (they are managed by the
        // routine editor; the user may have edited them too).
        await _repository.updateTemplate(bundle.template);
      }
    }
  }

  Future<void> _writeFullDemoBundle(DemoRoutineBundle bundle) async {
    // Templates first — segments/efforts/targets reference it.
    await _repository.createTemplate(bundle.template);

    // Map source-segment ids → freshly-created device-segment ids so the
    // effort / target rows reference the ones we just persisted. We use
    // the source ids verbatim here because the refresh is the only
    // writer of demo segments and the routine editor never edits them
    // (the user's edits apply only to the *top-level* template fields).
    for (final segmentSpec in bundle.segments) {
      await _repository.createTemplateSegment(segmentSpec.segment);

      for (final effortSpec in segmentSpec.efforts) {
        await _repository.createTemplateEffort(effortSpec.effort);

        for (final targetSpec in effortSpec.targets) {
          await _repository.createTemplateTarget(
            TemplateTarget(
              id: 'demo-ttar-${effortSpec.effort.id}-${targetSpec.setIndex ?? 0}-${targetSpec.metricId}',
              templateEffortId: effortSpec.effort.id,
              metricId: targetSpec.metricId,
              setIndex: targetSpec.setIndex,
              unitId: targetSpec.unitId,
              targetMin: targetSpec.targetMin,
              targetMax: targetSpec.targetMax,
              targetInt: targetSpec.targetInt,
              targetText: targetSpec.targetText,
              createdAtMs: bundle.template.createdAtMs,
              updatedAtMs: bundle.template.updatedAtMs,
            ),
          );
        }
      }
    }
  }

  /// `true` when the stored template row differs from the bundled row in
  /// any seed-managed field. The routine's name, description, focus
  /// modality, and `isBuiltInDemo` flag are all owned by the bundled
  /// source; segments / efforts / targets are owned by the user once
  /// they start editing, so this method only diffs the top-level
  /// template fields.
  bool _demoBundleTemplateDiffers(
    WorkoutTemplate stored,
    WorkoutTemplate bundled,
  ) {
    if (stored.name != bundled.name) return true;
    if (stored.description != bundled.description) return true;
    if (stored.focusModality != bundled.focusModality) return true;
    if (stored.primaryDisciplineId != bundled.primaryDisciplineId) return true;
    if (stored.note != bundled.note) return true;
    if (stored.isBuiltInDemo != bundled.isBuiltInDemo) return true;
    return false;
  }

  /// `true` when the two exercises differ in any seed-managed field.
  /// `updatedAtMs` is intentionally NOT compared: the bundled exercise
  /// always carries the seed's timestamp, which is irrelevant to whether
  /// the device row matches the bundled content.
  bool _exerciseDiffers(Exercise stored, Exercise bundled) {
    if (stored.name != bundled.name) return true;
    if (stored.modality != bundled.modality) return true;
    if (stored.disciplineId != bundled.disciplineId) return true;
    if (stored.description != bundled.description) return true;
    if (stored.movementPattern != bundled.movementPattern) return true;
    if (stored.isArchived != bundled.isArchived) return true;
    if (stored.defaultRoundDurationSecs != bundled.defaultRoundDurationSecs) {
      return true;
    }
    if (!_listEquals(stored.howToSteps, bundled.howToSteps)) return true;
    if (stored.imageAssetPath != bundled.imageAssetPath) return true;
    return false;
  }

  /// `true` when the two food rows differ in any seed-managed field.
  /// The refresh must NOT touch `lastAmountConsumed` (that's a per-user
  /// memory field, not part of the catalog).
  bool _foodDiffers(Food stored, Food bundled) {
    if (stored.name != bundled.name) return true;
    if (stored.groupId != bundled.groupId) return true;
    if (stored.unitType != bundled.unitType) return true;
    if (stored.referenceAmount != bundled.referenceAmount) return true;
    if (stored.referenceLabel != bundled.referenceLabel) return true;
    if (stored.protein != bundled.protein) return true;
    if (stored.carbs != bundled.carbs) return true;
    if (stored.fiber != bundled.fiber) return true;
    if (stored.fat != bundled.fat) return true;
    if (stored.sodium != bundled.sodium) return true;
    if (stored.isArchived != bundled.isArchived) return true;
    if (stored.notes != bundled.notes) return true;
    return false;
  }

  bool _listEquals(List<String>? a, List<String>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _listEqualsIgnoreOrder(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    final aSorted = List<String>.from(a)..sort();
    final bSorted = List<String>.from(b)..sort();
    for (var i = 0; i < aSorted.length; i++) {
      if (aSorted[i] != bSorted[i]) return false;
    }
    return true;
  }
}