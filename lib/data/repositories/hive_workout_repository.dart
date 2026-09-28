import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../datasources/food_catalog_loader.dart';
import '../../mock/seed_data.dart';
import '../../core/constants/data_version.dart';
import '../../core/constants/modality_config.dart';
import '../../core/services/data_migration_service.dart';
import '../../core/utils/fuzzy_search.dart';
import '../../core/utils/exercise_helpers.dart';
import '../../core/utils/entry_rows.dart';
import '../../core/utils/date_utils.dart';
import 'workout_repository.dart';

const _hiveUuid = Uuid();

/// A concrete [DataMigrationStep] that runs a single `Future<void>` closure.
class _MethodStep extends DataMigrationStep {
  _MethodStep(this.targetVersion, this.name, this._body);

  @override
  final int targetVersion;

  @override
  final String name;

  final Future<void> Function() _body;

  @override
  Future<void> run() => _body();
}

/// Hive-backed repository for local persistence on web.
/// Stores raw Map data to avoid TypeAdapter boilerplate.
class HiveWorkoutRepository implements WorkoutRepository {
  static const String _metaBoxName = 'meta';
  static const String _seedLoadedKey = 'seed_loaded';
  static const String _seedUnitsMigrationKey = 'seed_units_migrated_v1';
  static const String _exerciseRoundDefaultsMigrationKey =
      'exercise_round_defaults_migrated_v1';
  static const String _sessionFeelingFieldsMigrationKey =
      'session_feeling_fields_migrated_v1';
  static const String _calendarDataMigrationKey = 'calendar_data_seeded_v1';
  static const String _calendarSeedPurgeMigrationKey =
      'calendar_seed_purged_v1';
  static const String _exerciseContentFieldsMigrationKey =
      'exercise_content_fields_migrated_v1';
  static const String _timedExtraWeightMigrationKey =
      'timed_extra_weight_migrated_v1';
  static const String _exerciseLibraryRefreshMigrationKey =
      'exercise_library_refreshed_v5';
  static const String _nutritionTargetsDailyMigrationKey =
      'nutrition_targets_daily_migrated_v1';
  static const String _foodCatalogSeededKey = 'food_catalog_seeded_v1';
  static const String _defaultFoodGroupsSeededKey =
      'default_food_groups_seeded_v1';
  static const String _foodCategoryGroupIdMigratedKey =
      'food_category_groupid_migrated_v1';
  static const String _catalogVersionKey = 'catalog_version';
  static const String _seedEntryTouchedKeyPrefix = 'seed_entry_touched_';

  // Data-migration version sequence keys. The legacy one-shot markers
  // above are read ONCE by the back-compat shim in DataMigrationService
  // (on the first launch under the new system) to map legacy installs
  // to the correct starting version. From that point on, the device's
  // `data_version` integer is the single source of truth.
  static const String _dataVersionKey = 'data_version';
  static const String _dataVersionLastFromKey = 'data_version_last_from';
  static const String _dataVersionLastToKey = 'data_version_last_to';

  /// The Hive meta-box key for the one-shot category→groupId migration.
  /// Exposed via [visibleForTesting] so migration tests can clear the
  /// marker to force a re-run.
  @visibleForTesting
  static String get foodCategoryGroupIdMigratedKey =>
      _foodCategoryGroupIdMigratedKey;

  /// The Hive meta-box key prefix for per-entry tombstones set when a
  /// user mutates a seed entry. Tests use [visibleForTesting] to clear
  /// markers so they can verify the refresh re-applies bundled values
  /// when no user edit has happened.
  @visibleForTesting
  static String seedEntryTouchedKey(String entityType, String id) =>
      '$_seedEntryTouchedKeyPrefix${entityType}_$id';

  /// The Hive meta-box key for the device's stored catalog version.
  @visibleForTesting
  static String get catalogVersionKey => _catalogVersionKey;

  late Box<Map> _exercisesBox;
  late Box<Map> _sessionsBox;
  late Box<Map> _userProfilesBox;
  late Box<Map> _bodyMeasurementsBox;
  late Box<Map> _segmentsBox;
  late Box<Map> _effortsBox;
  late Box<Map> _observationsBox;
  late Box<Map> _unitsBox;
  late Box<Map> _metricsBox;
  late Box<Map> _muscleGroupsBox;
  late Box<Map> _disciplinesBox;
  late Box<Map> _sportCategoriesBox;
  late Box<Map> _equipmentBox;
  late Box<Map> _tagsBox;
  late Box<Map> _templatesBox;
  late Box<Map> _templateSegmentsBox;
  late Box<Map> _templateEffortsBox;
  late Box<Map> _templateTargetsBox;

  // Round instances box: key = RoundInstance.id, value = RoundInstance.toMap()
  // effortId-level lookup is done by scanning (same pattern as observations).
  late Box<Map> _roundInstancesBox;

  // Timed instances box: key = TimedInstance.id, value = TimedInstance.toMap()
  // Stores wall-clock tracked durations for timed/drill efforts.
  late Box<Map> _timedInstancesBox;

  // Entry rests box: key = EntryRest.id, value = EntryRest.toMap()
  // Wall-clock rest periods between consecutive sets/rounds for all effort kinds.
  late Box<Map> _entryRestsBox;

  // Exercise notes box: key = ExerciseNote.id, value = ExerciseNote.toMap()
  late Box<Map> _exerciseNotesBox;

  // Planned sessions box: key = PlannedSession.id, value = PlannedSession.toMap()
  late Box<Map> _plannedSessionsBox;

  // Training periods box: key = TrainingPeriod.id, value = TrainingPeriod.toMap()
  late Box<Map> _periodsBox;

  // Session blocks box: key = SessionBlock.id, value = SessionBlock.toMap()
  late Box<Map> _sessionBlocksBox;

  late Box<Map> _nutritionTargetsBox;

  // Date-keyed nutrition targets box: key = dateMs (as string), value = NutritionTarget.toMap()
  // Supports day-based targets with backward walkback and forward propagation
  late Box<Map> _nutritionTargetsByDateBox;

  // Food library boxes: key = id, value = FoodGroup.toMap() or Food.toMap()
  late Box<Map> _foodGroupsBox;
  late Box<Map> _foodsBox;

  // Food catalog box: read-only bundled foods
  late Box<Map> _foodCatalogBox;

  // Day nutrition log box: consumed foods (frozen snapshots)
  late Box<Map> _consumedFoodsBox;

  // Daily water log box: key = dateMs.toString(), value = WaterLogEntry.toMap()
  // Stores the day's volume in milliliters; absence of a key = 0 ml for the day.
  late Box<Map> _waterLogBox;

  // Watch session inbox (D-132): key = WatchInboxEntry.entryId,
  // value = WatchInboxEntry.toMap(). Put-if-absent; rows are never deleted
  // (applied rows are tombstones), so no history delete cascades into it.
  late Box<Map> _watchInboxBox;

  // Wrist-measured sensor summaries (D-131): key = SensorSummary.id,
  // value = SensorSummary.toMap(). Deleted together with their target.
  late Box<Map> _sensorSummariesBox;

  late Box<List> _exerciseMuscleGroupsBox;
  late Box<List> _exerciseEquipmentBox;
  late Box<List> _exerciseTagsBox;
  late Box<List> _metricEffortKindsBox;
  late Box<List> _exerciseCapabilitiesBox;

  late Box _metaBox;

  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    await Hive.initFlutter();

    _metaBox = await Hive.openBox(_metaBoxName);
    _exercisesBox = await Hive.openBox<Map>('exercises');
    _sessionsBox = await Hive.openBox<Map>('sessions');
    _userProfilesBox = await Hive.openBox<Map>('user_profile');
    _bodyMeasurementsBox = await Hive.openBox<Map>('body_measurements');
    _segmentsBox = await Hive.openBox<Map>('segments');
    _effortsBox = await Hive.openBox<Map>('efforts');
    _observationsBox = await Hive.openBox<Map>('observations');
    _unitsBox = await Hive.openBox<Map>('units');
    _metricsBox = await Hive.openBox<Map>('metrics');
    _muscleGroupsBox = await Hive.openBox<Map>('muscle_groups');
    _disciplinesBox = await Hive.openBox<Map>('disciplines');
    _sportCategoriesBox = await Hive.openBox<Map>('sport_categories');
    _equipmentBox = await Hive.openBox<Map>('equipment');
    _tagsBox = await Hive.openBox<Map>('tags');
    _templatesBox = await Hive.openBox<Map>('templates');
    _templateSegmentsBox = await Hive.openBox<Map>('template_segments');
    _templateEffortsBox = await Hive.openBox<Map>('template_efforts');
    _templateTargetsBox = await Hive.openBox<Map>('template_targets');

    _nutritionTargetsBox = await Hive.openBox<Map>('nutrition_targets');
    _nutritionTargetsByDateBox = await Hive.openBox<Map>(
      'nutrition_targets_by_date',
    );

    _foodGroupsBox = await Hive.openBox<Map>('food_groups');
    _foodsBox = await Hive.openBox<Map>('foods');
    _foodCatalogBox = await Hive.openBox<Map>('foods_catalog');
    _consumedFoodsBox = await Hive.openBox<Map>('consumed_foods');
    _waterLogBox = await Hive.openBox<Map>('water_log');

    _roundInstancesBox = await Hive.openBox<Map>('round_instances');

    _timedInstancesBox = await Hive.openBox<Map>('timed_instances');

    _entryRestsBox = await Hive.openBox<Map>('entry_rests');
    _exerciseNotesBox = await Hive.openBox<Map>('exercise_notes');

    _plannedSessionsBox = await Hive.openBox<Map>('planned_sessions');
    _periodsBox = await Hive.openBox<Map>('training_periods');
    _sessionBlocksBox = await Hive.openBox<Map>('session_blocks');

    // New in Stats PR 2. Both start empty on existing installs and hold no
    // derived data, so no data-migration step is needed.
    _watchInboxBox = await Hive.openBox<Map>('watch_inbox');
    _sensorSummariesBox = await Hive.openBox<Map>('sensor_summaries');

    _exerciseMuscleGroupsBox = await Hive.openBox<List>(
      'exercise_muscle_groups',
    );
    _exerciseEquipmentBox = await Hive.openBox<List>('exercise_equipment');
    _exerciseTagsBox = await Hive.openBox<List>('exercise_tags');
    _metricEffortKindsBox = await Hive.openBox<List>('metric_effort_kinds');
    _exerciseCapabilitiesBox = await Hive.openBox<List>(
      'exercise_capabilities',
    );

    // Run the consolidated data-migration sequence. Replaces the previous
    // per-step `bool`-gated calls; the device's `data_version` integer
    // is now the single source of truth for "which migration step the
    // device has reached". The back-compat shim inside the service maps
    // any legacy one-shot markers to a starting version on the first
    // launch under the new system, so existing installs do not re-run
    // already-applied steps.
    await _runDataMigrations();

    _initialized = true;
  }

  /// Run the consolidated data-migration sequence once on startup. Each
  /// step delegates to the existing private method body — only the gating
  /// has changed (legacy `bool` marker → version check), so behavior is
  /// preserved exactly.
  Future<void> _runDataMigrations() async {
    final service = DataMigrationService(
      repository: this,
      targetVersion: currentDataVersion,
      steps: _dataMigrationSteps(),
    );
    await service.run();
  }

  /// The ordered list of consolidated data-migration steps. Each step's
  /// `targetVersion` corresponds to the version the device lands at after
  /// the step completes. Adding a new step = append a row + bump
  /// [currentDataVersion] in `lib/core/constants/data_version.dart`.
  ///
  /// The `run` closure captures `this` and calls the existing private
  /// method. The legacy `bool` gates inside those methods are now
  /// redundant (the version gate is the only one that matters), but
  /// they remain in place as a defense-in-depth check; the steps are
  /// idempotent so the redundant gates are no-ops.
  List<DataMigrationStep> _dataMigrationSteps() {
    final repo = this;
    return [
      _MethodStep(2, 'seedData', () => repo._seedData()),
      _MethodStep(3, 'seedUnits', () => repo._migrateSeedUnits()),
      _MethodStep(
        4,
        'exerciseRoundDefaults',
        () => repo._migrateExerciseRoundDefaults(),
      ),
      _MethodStep(
        5,
        'sessionFeelingFields',
        () => repo._migrateSessionFeelingFields(),
      ),
      _MethodStep(6, 'seedCalendarData', () => repo._seedCalendarData()),
      _MethodStep(
        7,
        'purgeCalendarSeedData',
        () => repo._purgeCalendarSeedData(),
      ),
      _MethodStep(
        8,
        'exerciseContentFields',
        () => repo._migrateExerciseContentFields(),
      ),
      _MethodStep(9, 'timedExtraWeight', () => repo._migrateTimedExtraWeight()),
      _MethodStep(
        10,
        'exerciseLibraryRefresh',
        () => repo._migrateExerciseLibraryRefresh(),
      ),
      _MethodStep(
        11,
        'dailyNutritionTargets',
        () => repo._migrateDailyNutritionTargets(),
      ),
      _MethodStep(12, 'seedFoodCatalog', () => repo._seedFoodCatalog()),
      _MethodStep(
        13,
        'seedDefaultFoodGroups',
        () => repo._seedDefaultFoodGroups(),
      ),
      _MethodStep(
        14,
        'foodCategoryToGroupId',
        () => repo._migrateFoodCategoryToGroupId(),
      ),
    ];
  }

  /// Seed the food catalog from the bundled asset on first install.
  /// The catalog is read-only; this method only runs once (guarded by
  /// [_foodCatalogSeededKey]) and never overwrites existing rows.
  Future<void> _seedFoodCatalog() async {
    final seeded = _metaBox.get(_foodCatalogSeededKey) as bool? ?? false;
    if (seeded) return;

    try {
      final catalogFoods = await FoodCatalogLoader.loadFromAsset();
      final entries = <String, Map>{
        for (final food in catalogFoods) food.id: food.toMap(),
      };
      await _foodCatalogBox.putAll(entries);
      await _metaBox.put(_foodCatalogSeededKey, true);
    } catch (e) {
      // Asset load failure is non-fatal: the catalog will simply be empty.
      // The app remains functional; users can still build their own library.
    }
  }

  /// Seed default food group categories (Proteins, Vegetables, …) on first
  /// install and idempotently backfill them on existing installs.
  ///
  /// Idempotency rules:
  /// - Guarded by [_defaultFoodGroupsSeededKey] so the work runs at most once
  ///   per install. The marker is set only after all 9 default groups are
  ///   successfully written.
  /// - Each default group is inserted by its stable id. If a group with that
  ///   id already exists (e.g. a future migration added a group of its own),
  ///   the existing row is preserved untouched.
  /// - A name-based collision check (case-insensitive) prevents duplicate
  ///   "Proteins" / "Vegetables" / … groups if the user already created one
  ///   with that name before the migration ran.
  Future<void> _seedDefaultFoodGroups() async {
    final seeded = _metaBox.get(_defaultFoodGroupsSeededKey) as bool? ?? false;
    if (seeded) return;

    // Snapshot existing names once so we can detect collisions cheaply.
    final existingNames = <String>{
      for (final raw in _foodGroupsBox.values)
        (raw['name'] as String? ?? '').toLowerCase(),
    };

    for (final group in SeedData.defaultFoodGroups) {
      // Stable-id match: the row is already populated; never overwrite.
      if (_foodGroupsBox.containsKey(group.id)) continue;

      // Name match: the user already created a group with the same name.
      // Skip seeding to avoid a duplicate (the user's row wins).
      if (existingNames.contains(group.name.toLowerCase())) continue;

      await _foodGroupsBox.put(group.id, group.toMap());
    }

    await _metaBox.put(_defaultFoodGroupsSeededKey, true);
  }

  /// One-shot migration: resolve the catalog's `notes` category string
  /// (legacy storage: "Proteins" / "Dairy" / …) into a proper
  /// `group_id` FK pointing at the matching default `FoodGroup`.
  ///
  /// Why needed:
  /// - Old installs have catalog rows where `notes` carries the category
  ///   label and `group_id` is NULL. The new contract is `group_id`
  ///   as the single source of truth, with `notes` reserved for free-form
  ///   user notes.
  /// - This migration backfills `group_id` on existing rows in BOTH
  ///   `_foodCatalogBox` and `_foodsBox` (the latter covers any catalog
  ///   food the user has already added to their library on a previous
  ///   install). It does not touch user-authored library foods.
  ///
  /// Matching rule:
  /// - Build a `category-name (lower-cased) -> FoodGroup.id` lookup from
  ///   the *active* default food groups present in `_foodGroupsBox`.
  ///   This way, if the user renamed or deleted a default group, we
  ///   still match against the user's intent (their renamed group wins).
  /// - Rows whose `notes` doesn't match any active default are simply
  ///   left as `group_id = NULL` (treated as Ungrouped).
  /// - `notes` is cleared to NULL only when we successfully resolved a
  ///   match; we do not stomp unrelated user notes.
  ///
  /// Library-box heuristic:
  /// - `_foodsBox` only stores rows with `is_catalog = 0`, so the
  ///   `is_catalog` flag is useless for picking catalog-backed rows.
  ///   Instead we identify catalog-copied rows by their `notes` value
  ///   matching one of the 9 default category names exactly (case-
  ///   insensitive). User-authored library foods would not carry a
  ///   category name in `notes` by default.
  ///
  /// Idempotency:
  /// - Guarded by [_foodCategoryGroupIdMigratedKey].
  /// - The marker is set only after a full pass; partial work is
  ///   safe to retry (writes overwrite).
  Future<void> _migrateFoodCategoryToGroupId() async {
    final migrated =
        _metaBox.get(_foodCategoryGroupIdMigratedKey) as bool? ?? false;
    if (migrated) return;

    // Build a name -> groupId lookup from the ACTIVE default groups.
    // Built from _foodGroupsBox (not SeedData) so the migration honours
    // user renames: a user who renamed "Proteins" → "Legumes" would
    // no longer match catalog rows carrying notes='Proteins'.
    final nameToGroupId = <String, String>{
      for (final raw in _foodGroupsBox.values)
        if ((raw['is_archived'] as int? ?? 0) == 0)
          (raw['name'] as String? ?? '').toLowerCase(): raw['id'] as String,
    };

    Future<void> migrateCatalogBox() async {
      final keys = _foodCatalogBox.keys.toList(growable: false);
      for (final key in keys) {
        final raw = _foodCatalogBox.get(key);
        if (raw == null) continue;

        final notes = raw['notes'] as String?;
        final groupId = raw['group_id'] as String?;
        if (notes == null || notes.isEmpty) continue;
        if (groupId != null) continue; // already migrated

        final resolved = nameToGroupId[notes.toLowerCase()];
        if (resolved == null) continue; // no active match; leave as-is

        raw['group_id'] = resolved;
        raw['notes'] = null;
        await _foodCatalogBox.put(key, raw);
      }
    }

    Future<void> migrateLibraryBox() async {
      // Only touch library rows whose notes match a known category name.
      // User-authored foods with arbitrary notes are left alone.
      final keys = _foodsBox.keys.toList(growable: false);
      for (final key in keys) {
        final raw = _foodsBox.get(key);
        if (raw == null) continue;

        final notes = raw['notes'] as String?;
        final groupId = raw['group_id'] as String?;
        if (notes == null || notes.isEmpty) continue;
        if (groupId != null) continue; // already migrated

        // Heuristic: only consider notes that match a known default
        // category name. This avoids stomping user-typed notes.
        if (!nameToGroupId.containsKey(notes.toLowerCase())) continue;

        final resolved = nameToGroupId[notes.toLowerCase()]!;
        raw['group_id'] = resolved;
        raw['notes'] = null;
        await _foodsBox.put(key, raw);
      }
    }

    await migrateCatalogBox();
    await migrateLibraryBox();

    await _metaBox.put(_foodCategoryGroupIdMigratedKey, true);
  }

  /// Test-only entry point: clears the migration marker and re-runs
  /// the category→groupId migration. Lets tests verify behaviour
  /// under user-modified group names that wouldn't normally exist
  /// after a fresh initialize().
  @visibleForTesting
  Future<void> rerunCategoryMigrationForTest() async {
    await _metaBox.delete(_foodCategoryGroupIdMigratedKey);
    await _migrateFoodCategoryToGroupId();
  }

  Future<void> _seedData() async {
    await _sportCategoriesBox.putAll({
      for (final category in SeedData.sampleSportCategories)
        category.id: category.toMap(),
    });

    await _disciplinesBox.putAll({
      for (final discipline in SeedData.sampleDisciplines)
        discipline.id: discipline.toMap(),
    });

    await _exercisesBox.putAll({
      for (final exercise in SeedData.sampleExercises)
        exercise.id: exercise.toMap(),
    });

    await _muscleGroupsBox.putAll({
      for (final muscleGroup in SeedData.sampleMuscleGroups)
        muscleGroup.id: muscleGroup.toMap(),
    });

    await _equipmentBox.putAll({
      for (final equip in SeedData.sampleEquipment) equip.id: equip.toMap(),
    });

    await _tagsBox.putAll({
      for (final tag in SeedData.sampleTags) tag.id: tag.toMap(),
    });

    await _unitsBox.putAll({
      for (final unit in SeedData.defaultUnits) unit.id: unit.toMap(),
    });

    await _metricsBox.putAll({
      for (final metric in SeedData.defaultMetrics) metric.id: metric.toMap(),
    });

    await _templateSegmentsBox.putAll({
      for (final segment in SeedData.sampleTemplateSegments)
        segment.id: segment.toMap(),
    });

    await _templateEffortsBox.putAll({
      for (final effort in SeedData.sampleTemplateEfforts)
        effort.id: effort.toMap(),
    });

    await _templateTargetsBox.putAll({
      for (final target in SeedData.sampleTemplateTargets)
        target.id: target.toMap(),
    });

    await _exerciseMuscleGroupsBox.putAll({
      for (final entry in SeedData.exerciseMuscleGroupRelationships.entries)
        entry.key: List<String>.from(entry.value),
    });

    await _exerciseEquipmentBox.putAll({
      for (final entry in SeedData.exerciseEquipmentRelationships.entries)
        entry.key: List<String>.from(entry.value),
    });

    await _exerciseCapabilitiesBox.putAll({
      for (final entry in SeedData.exerciseCapabilityRelationships.entries)
        entry.key: List<String>.from(entry.value),
    });

    final Map<String, List<String>> metricEffortKinds = {};
    for (final applicability in SeedData.metricApplicability) {
      metricEffortKinds
          .putIfAbsent(applicability.metricId, () => [])
          .add(applicability.effortKind);
    }
    await _metricEffortKindsBox.putAll(metricEffortKinds);

    // NOTE: SeedData.sampleTrainingSessions/sampleSessionSegments/sampleSessionBlocks/
    // sampleSegmentEfforts are available as reference data but NOT auto-seeded here.
    // Use them to manually populate a demo session when needed.
  }

  /// Backfills newly added seed units for existing installs where `_seed_loaded`
  /// prevents `_seedData()` from running again.
  Future<void> _migrateSeedUnits() async {
    final migrated = _metaBox.get(_seedUnitsMigrationKey) as bool? ?? false;
    if (migrated) return;

    for (final unit in SeedData.defaultUnits) {
      if (_unitsBox.containsKey(unit.id)) continue;
      await _unitsBox.put(unit.id, unit.toMap());
    }

    await _metaBox.put(_seedUnitsMigrationKey, true);
  }

  /// Backfills `default_round_duration_secs` for existing Hive installs that
  /// were seeded before this field was introduced.
  ///
  /// Why needed:
  /// - Existing users already have `_seed_loaded == true`, so `_seedData()` no
  ///   longer runs and older exercise rows remain without this key.
  /// - Missing key means `Exercise.defaultRoundDurationSecs == null`, causing
  ///   round efforts to fall back to 180s globally.
  ///
  /// This migration is idempotent and only writes when the stored value is null.
  Future<void> _migrateExerciseRoundDefaults() async {
    final migrated =
        _metaBox.get(_exerciseRoundDefaultsMigrationKey) as bool? ?? false;
    if (migrated) return;

    for (final seedExercise in SeedData.sampleExercises) {
      final defaultSecs = seedExercise.defaultRoundDurationSecs;
      if (defaultSecs == null) continue;

      final raw = _exercisesBox.get(seedExercise.id);
      if (raw == null) continue;

      final exerciseMap = _asStringMap(raw);
      if (exerciseMap['default_round_duration_secs'] != null) continue;

      exerciseMap['default_round_duration_secs'] = defaultSecs;
      await _exercisesBox.put(seedExercise.id, exerciseMap);
    }

    await _metaBox.put(_exerciseRoundDefaultsMigrationKey, true);
  }

  /// Migration note: session_feeling_v1, quality_rating_v1 added as nullable int fields.
  /// No backfill needed - null is the correct default for all existing sessions.
  Future<void> _migrateSessionFeelingFields() async {
    final migrated =
        _metaBox.get(_sessionFeelingFieldsMigrationKey) as bool? ?? false;
    if (migrated) return;
    await _metaBox.put(_sessionFeelingFieldsMigrationKey, true);
  }

  /// Legacy no-op migration key from the initial Calendar & Periods rollout.
  ///
  /// Historical note: this originally seeded demo planned sessions/periods for
  /// old installs. The placeholders were removed, but we preserve the key so
  /// existing meta data remains compatible.
  Future<void> _seedCalendarData() async {
    final migrated = _metaBox.get(_calendarDataMigrationKey) as bool? ?? false;
    if (migrated) return;
    await _metaBox.put(_calendarDataMigrationKey, true);
  }

  /// Removes historical calendar demo seed rows from existing installs.
  ///
  /// Deletes only known placeholder IDs to avoid touching user-created data.
  /// Idempotent: guarded by [_calendarSeedPurgeMigrationKey] in the meta box.
  Future<void> _purgeCalendarSeedData() async {
    final purged =
        _metaBox.get(_calendarSeedPurgeMigrationKey) as bool? ?? false;
    if (purged) return;

    const plannedSeedIds = <String>[
      'planned-session-1',
      'planned-session-2',
      'planned-session-3',
      'planned-session-4',
      'planned-session-5',
      'planned-session-6',
      'planned-session-7',
      'planned-session-8',
    ];
    const periodSeedIds = <String>['period-1', 'period-2'];

    for (final id in plannedSeedIds) {
      await _plannedSessionsBox.delete(id);
    }
    for (final id in periodSeedIds) {
      await _periodsBox.delete(id);
    }

    await _metaBox.put(_calendarSeedPurgeMigrationKey, true);
  }

  /// Migration note: metric-extra-weight is now also applicable to timed efforts,
  /// enabling loaded carries and weighted cardio to log load alongside duration/distance.
  /// Backfills the _metricEffortKindsBox entry for existing installs.
  /// No observation backfill needed — the UI guard (entryData['extra-weight'] != null)
  /// handles pre-existing timed entries that lack an extra-weight observation.
  Future<void> _migrateTimedExtraWeight() async {
    final migrated =
        _metaBox.get(_timedExtraWeightMigrationKey) as bool? ?? false;
    if (migrated) return;

    final existingKinds = _metricEffortKindsBox.get('metric-extra-weight');
    if (existingKinds != null) {
      final kinds = List<String>.from(existingKinds);
      if (!kinds.contains('timed')) {
        kinds.add('timed');
        await _metricEffortKindsBox.put('metric-extra-weight', kinds);
      }
    } else {
      // Key absent entirely — create it fresh with both effort kinds.
      // Guards against corrupted or partially-initialised installs where the
      // seed never populated this entry.
      await _metricEffortKindsBox.put('metric-extra-weight', [
        'drill',
        'timed',
      ]);
    }

    await _metaBox.put(_timedExtraWeightMigrationKey, true);
  }

  /// Migration note: how_to_steps and image_asset_path added as nullable fields.
  /// No backfill needed - null is the correct default for existing exercises.
  Future<void> _migrateExerciseContentFields() async {
    final migrated =
        _metaBox.get(_exerciseContentFieldsMigrationKey) as bool? ?? false;
    if (migrated) return;
    await _metaBox.put(_exerciseContentFieldsMigrationKey, true);
  }

  /// Backfills and refreshes seed exercise content for existing installs.
  ///
  /// Why needed:
  /// - Seed data is loaded once behind `_seed_loaded`, so newly added seed
  ///   exercises and updated descriptions/cues are not visible to existing users.
  /// - This migration upserts current seed exercises and relationship maps while
  ///   leaving user-created exercises untouched.
  Future<void> _migrateExerciseLibraryRefresh() async {
    final migrated =
        _metaBox.get(_exerciseLibraryRefreshMigrationKey) as bool? ?? false;
    if (migrated) return;

    await _sportCategoriesBox.putAll({
      for (final category in SeedData.sampleSportCategories)
        category.id: category.toMap(),
    });

    await _disciplinesBox.putAll({
      for (final discipline in SeedData.sampleDisciplines)
        discipline.id: discipline.toMap(),
    });

    await _exercisesBox.putAll({
      for (final exercise in SeedData.sampleExercises)
        exercise.id: exercise.toMap(),
    });

    await _exerciseMuscleGroupsBox.putAll({
      for (final entry in SeedData.exerciseMuscleGroupRelationships.entries)
        entry.key: List<String>.from(entry.value),
    });

    await _exerciseEquipmentBox.putAll({
      for (final entry in SeedData.exerciseEquipmentRelationships.entries)
        entry.key: List<String>.from(entry.value),
    });

    await _exerciseCapabilitiesBox.putAll({
      for (final entry in SeedData.exerciseCapabilityRelationships.entries)
        entry.key: List<String>.from(entry.value),
    });

    await _metaBox.put(_exerciseLibraryRefreshMigrationKey, true);
  }

  /// Migrates legacy nullable NutritionTarget to non-nullable defaults (0.0).
  /// Creates new daily-keyed box for date-based targets on first install.
  Future<void> _migrateDailyNutritionTargets() async {
    final migrated =
        _metaBox.get(_nutritionTargetsDailyMigrationKey) as bool? ?? false;
    if (migrated) return;

    // If there's a legacy global target, migrate it to today's date
    final legacyRaw = _nutritionTargetsBox.get('user-targets');
    if (legacyRaw != null) {
      try {
        final legacyMap = _asStringMap(legacyRaw);
        // Convert nullable fields to non-nullable with 0.0 defaults
        final migratedMap = {
          'calories': ((legacyMap['calories'] as num?) ?? 0.0).toDouble(),
          'protein': ((legacyMap['protein'] as num?) ?? 0.0).toDouble(),
          'carbs': ((legacyMap['carbs'] as num?) ?? 0.0).toDouble(),
          'fat': ((legacyMap['fat'] as num?) ?? 0.0).toDouble(),
          'date_ms': null, // Legacy targets have no date
        };
        // Store back with migrated values
        await _nutritionTargetsBox.put('user-targets', migratedMap);
      } catch (e) {
        // If parsing fails, leave it as-is; subsequent loads will handle it
      }
    }

    await _metaBox.put(_nutritionTargetsDailyMigrationKey, true);
  }

  Map<String, dynamic> _asStringMap(dynamic raw) {
    return Map<String, dynamic>.from(raw as Map);
  }

  List<String> _asStringList(dynamic raw) {
    if (raw == null) return <String>[];
    return (raw as List).map((e) => e.toString()).toList();
  }

  // ===== EXERCISES =====

  @override
  Future<List<Exercise>> getExercises() async {
    return _exercisesBox.values
        .map((raw) => Exercise.fromMap(_asStringMap(raw)))
        .where((e) => !e.isArchived)
        .map((e) => e.copyWith(capabilities: _getCapabilities(e.id)))
        .toList();
  }

  @override
  Future<Exercise?> getExerciseById(String id) async {
    final raw = _exercisesBox.get(id);
    if (raw == null) return null;
    final exercise = Exercise.fromMap(_asStringMap(raw));
    return exercise.copyWith(capabilities: _getCapabilities(exercise.id));
  }

  @override
  Future<String> createExercise(Exercise exercise) async {
    await _exercisesBox.put(exercise.id, exercise.toMap());
    return exercise.id;
  }

  @override
  Future<void> updateExercise(Exercise exercise) async {
    await _exercisesBox.put(exercise.id, exercise.toMap());
  }

  @override
  Future<void> deleteExercise(String id) async {
    await _exercisesBox.delete(id);
  }

  @override
  Future<List<Exercise>> searchExercises({
    String? searchText,
    String? disciplineId,
    List<String>? muscleGroupIds,
  }) async {
    var results = _exercisesBox.values
        .map((raw) => Exercise.fromMap(_asStringMap(raw)))
        .where((e) => !e.isArchived);

    if (disciplineId != null && disciplineId.isNotEmpty) {
      results = results.where((e) => e.disciplineId == disciplineId);
    }

    if (muscleGroupIds != null && muscleGroupIds.isNotEmpty) {
      results = results.where((e) {
        final exerciseMuscles = _asStringList(
          _exerciseMuscleGroupsBox.get(e.id),
        );
        return exerciseMuscles.any((id) => muscleGroupIds.contains(id));
      });
    }

    if (searchText != null && searchText.isNotEmpty) {
      return FuzzySearch.filterAndRank(searchText, results.toList());
    }

    return results.toList();
  }

  // ===== SESSIONS =====

  @override
  Future<TrainingSession?> getSession(String id) async {
    final raw = _sessionsBox.get(id);
    if (raw == null) return null;
    return TrainingSession.fromMap(_asStringMap(raw));
  }

  @override
  Future<List<TrainingSession>> getAllSessions() async {
    final sessions = _sessionsBox.values
        .map((raw) => TrainingSession.fromMap(_asStringMap(raw)))
        .toList();
    sessions.sort((a, b) => b.startedAtMs.compareTo(a.startedAtMs));
    return sessions;
  }

  @override
  Future<List<TrainingSession>> getSessionsByDateRange(
    int fromMs,
    int toMs,
  ) async {
    final sessions = _sessionsBox.values
        .map((raw) => TrainingSession.fromMap(_asStringMap(raw)))
        .where((s) => s.startedAtMs >= fromMs && s.startedAtMs <= toMs)
        .toList();
    sessions.sort((a, b) => a.startedAtMs.compareTo(b.startedAtMs));
    return sessions;
  }

  @override
  Future<double?> getPersonalRecordCandidates(
    String exerciseId, {
    String? metricId,
  }) async {
    final sessionsById = <String, TrainingSession>{};
    for (final raw in _sessionsBox.values) {
      final session = TrainingSession.fromMap(_asStringMap(raw));
      sessionsById[session.id] = session;
    }

    final segmentSessionIds = <String, String>{};
    for (final raw in _segmentsBox.values) {
      final segment = SessionSegment.fromMap(_asStringMap(raw));
      segmentSessionIds[segment.id] = segment.sessionId;
    }

    final validEffortIds = <String>{};
    for (final raw in _effortsBox.values) {
      final effort = SegmentEffort.fromMap(_asStringMap(raw));
      if (effort.exerciseId != exerciseId) continue;
      final sessionId = segmentSessionIds[effort.segmentId];
      if (sessionId == null) continue;
      final session = sessionsById[sessionId];
      if (session == null || session.endedAtMs == null) continue;
      validEffortIds.add(effort.id);
    }

    double? best;
    for (final raw in _observationsBox.values) {
      final observation = EffortObservation.fromMap(_asStringMap(raw));
      if (!validEffortIds.contains(observation.effortId)) continue;
      if (metricId != null && observation.metricId != metricId) continue;
      final value = observation.valueReal ?? observation.valueInt?.toDouble();
      if (value == null) continue;
      if (best == null || value > best) {
        best = value;
      }
    }

    return best;
  }

  @override
  Future<String> createSession(TrainingSession session) async {
    await _sessionsBox.put(session.id, session.toMap());
    return session.id;
  }

  @override
  Future<void> updateSession(TrainingSession session) async {
    await _sessionsBox.put(session.id, session.toMap());
  }

  @override
  Future<void> updateSessionFeeling(String sessionId, int feeling) async {
    final raw = _sessionsBox.get(sessionId);
    if (raw == null) return;

    final existing = TrainingSession.fromMap(_asStringMap(raw));
    final now = DateTime.now().millisecondsSinceEpoch;
    final updated = TrainingSession(
      id: existing.id,
      ownerUserId: existing.ownerUserId,
      routineTemplateId: existing.routineTemplateId,
      startedAtMs: existing.startedAtMs,
      endedAtMs: existing.endedAtMs,
      title: existing.title,
      note: existing.note,
      locationText: existing.locationText,
      modality: existing.modality,
      intent: existing.intent,
      perceivedSessionRpe: existing.perceivedSessionRpe,
      sessionFeeling: feeling,
      qualityRating: existing.qualityRating,
      isRolling: existing.isRolling,
      createdAtMs: existing.createdAtMs,
      updatedAtMs: now,
    );

    await _sessionsBox.put(sessionId, updated.toMap());
  }

  @override
  Future<bool> getPreferenceBool(
    String key, {
    bool defaultValue = false,
  }) async {
    return _metaBox.get(key) as bool? ?? defaultValue;
  }

  @override
  Future<void> setPreferenceBool(String key, bool value) async {
    await _metaBox.put(key, value);
  }

  @override
  Future<String?> getPreferenceString(
    String key, {
    String? defaultValue,
  }) async {
    return _metaBox.get(key) as String? ?? defaultValue;
  }

  @override
  Future<void> setPreferenceString(String key, String value) async {
    await _metaBox.put(key, value);
  }

  // ===== NUTRITION =====

  @override
  Future<NutritionTarget?> getNutritionTargetForDate(int dateMs) async {
    final dateKey = dateMs.toString();

    // Check if target exists for this exact date
    final raw = _nutritionTargetsByDateBox.get(dateKey);
    if (raw != null) {
      return NutritionTarget.fromMap(_asStringMap(raw));
    }

    // Walk backward to find the most recent ancestor target
    int searchDateMs = dateMs - (24 * 60 * 60 * 1000); // Start 1 day before
    while (searchDateMs > 0) {
      final ancestorRaw = _nutritionTargetsByDateBox.get(
        searchDateMs.toString(),
      );
      if (ancestorRaw != null) {
        // Found an ancestor; return a copy (rolls over to the requested date)
        final ancestorTarget = NutritionTarget.fromMap(
          _asStringMap(ancestorRaw),
        );
        return ancestorTarget.copyWith(dateMs: dateMs);
      }
      searchDateMs -= (24 * 60 * 60 * 1000); // Go back another day
    }

    // No ancestor found
    return null;
  }

  @override
  Future<void> saveNutritionTargetForDate(
    int dateMs,
    NutritionTarget target,
  ) async {
    final dateKey = dateMs.toString();

    // Fetch the old target (if it exists) to compare for forward propagation
    final oldRaw = _nutritionTargetsByDateBox.get(dateKey);
    final oldTarget = oldRaw != null
        ? NutritionTarget.fromMap(_asStringMap(oldRaw))
        : null;

    // Save the new target for this date
    final targetToSave = target.copyWith(dateMs: dateMs);
    await _nutritionTargetsByDateBox.put(dateKey, targetToSave.toMap());

    // Forward propagation: update future dates that had the old values
    if (oldTarget != null) {
      final allKeys = _nutritionTargetsByDateBox.keys
          .map((k) => int.tryParse(k.toString()) ?? 0)
          .toList();
      final sortedFutureKeys = allKeys.where((k) => k > dateMs).toList()
        ..sort();

      for (final futureKey in sortedFutureKeys) {
        final futureRaw = _nutritionTargetsByDateBox.get(futureKey.toString());
        if (futureRaw != null) {
          final futureTarget = NutritionTarget.fromMap(_asStringMap(futureRaw));
          // Only update if the future target is identical to the old one
          if (futureTarget.calories == oldTarget.calories &&
              futureTarget.protein == oldTarget.protein &&
              futureTarget.carbs == oldTarget.carbs &&
              futureTarget.fat == oldTarget.fat) {
            // Update to the new values, preserving the future date
            final updated = target.copyWith(dateMs: futureKey);
            await _nutritionTargetsByDateBox.put(
              futureKey.toString(),
              updated.toMap(),
            );
          }
        }
      }
    }
  }

  @override
  Future<NutritionTarget?> getNutritionTarget() async {
    return getNutritionTargetForDate(OmniDateUtils.todayMidnightMs());
  }

  @override
  Future<void> saveNutritionTarget(NutritionTarget target) async {
    return saveNutritionTargetForDate(OmniDateUtils.todayMidnightMs(), target);
  }

  @override
  Future<void> deleteSession(String id) async {
    final segmentIds = <dynamic>[];
    for (final entry in _segmentsBox.toMap().entries) {
      final raw = _asStringMap(entry.value);
      if (raw['session_id'] == id) {
        segmentIds.add(entry.key);
      }
    }

    final effortIds = <dynamic>[];
    for (final entry in _effortsBox.toMap().entries) {
      final raw = _asStringMap(entry.value);
      if (segmentIds.contains(raw['segment_id'])) {
        effortIds.add(entry.key);
      }
    }

    final observationIds = <dynamic>[];
    for (final entry in _observationsBox.toMap().entries) {
      final raw = _asStringMap(entry.value);
      if (effortIds.contains(raw['effort_id'])) {
        observationIds.add(entry.key);
      }
    }

    // Also delete round instances for all affected efforts
    final roundInstanceIds = <dynamic>[];
    for (final entry in _roundInstancesBox.toMap().entries) {
      final raw = _asStringMap(entry.value);
      if (effortIds.contains(raw['effort_id'])) {
        roundInstanceIds.add(entry.key);
      }
    }
    await _roundInstancesBox.deleteAll(roundInstanceIds);

    // Also delete timed instances for all affected efforts
    final timedInstanceIds = <dynamic>[];
    for (final entry in _timedInstancesBox.toMap().entries) {
      final raw = _asStringMap(entry.value);
      if (effortIds.contains(raw['effort_id'])) {
        timedInstanceIds.add(entry.key);
      }
    }
    await _timedInstancesBox.deleteAll(timedInstanceIds);

    // Also delete entry rests for all affected efforts
    final entryRestIds = <dynamic>[];
    for (final entry in _entryRestsBox.toMap().entries) {
      final raw = _asStringMap(entry.value);
      if (effortIds.contains(raw['effort_id'])) {
        entryRestIds.add(entry.key);
      }
    }
    await _entryRestsBox.deleteAll(entryRestIds);

    await _observationsBox.deleteAll(observationIds);
    await _effortsBox.deleteAll(effortIds);
    await _segmentsBox.deleteAll(segmentIds);
    final blockIds = <dynamic>[];
    for (final entry in _sessionBlocksBox.toMap().entries) {
      final raw = _asStringMap(entry.value);
      if (raw['session_id'] == id) {
        blockIds.add(entry.key);
      }
    }
    await _sessionBlocksBox.deleteAll(blockIds);
    await _deleteSensorSummariesForSession(id);
    await _sessionsBox.delete(id);
  }

  // ===== PROFILE =====

  @override
  Future<UserProfile?> getProfile() async {
    final localRaw = _userProfilesBox.get('local-user');
    if (localRaw != null) {
      return UserProfile.fromMap(_asStringMap(localRaw));
    }
    if (_userProfilesBox.isEmpty) return null;
    return UserProfile.fromMap(_asStringMap(_userProfilesBox.values.first));
  }

  @override
  Future<void> saveProfile(UserProfile profile) async {
    await _userProfilesBox.put(profile.id, profile.toMap());
  }

  @override
  Future<List<BodyMeasurementEntry>> getMeasurementHistory(
    String measurementType,
  ) async {
    final entries = _bodyMeasurementsBox.values
        .map((raw) => BodyMeasurementEntry.fromMap(_asStringMap(raw)))
        .where((entry) => entry.measurementType == measurementType)
        .toList();
    entries.sort((a, b) => b.recordedAtMs.compareTo(a.recordedAtMs));
    return entries;
  }

  @override
  Future<BodyMeasurementEntry?> getLatestMeasurement(
    String measurementType,
  ) async {
    final entries = await getMeasurementHistory(measurementType);
    return entries.isEmpty ? null : entries.first;
  }

  @override
  Future<void> saveMeasurementEntry(BodyMeasurementEntry entry) async {
    await _bodyMeasurementsBox.put(entry.id, entry.toMap());
  }

  @override
  Future<void> deleteMeasurementEntry(String entryId) async {
    await _bodyMeasurementsBox.delete(entryId);
  }

  // ===== SEGMENTS =====

  @override
  Future<List<SessionSegment>> getSessionSegments(String sessionId) async {
    final segments = _segmentsBox.values
        .map((raw) => SessionSegment.fromMap(_asStringMap(raw)))
        .where((s) => s.sessionId == sessionId)
        .toList();

    segments.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    return segments;
  }

  @override
  Future<Map<String, List<SessionSegment>>> getSegmentsBySession() async {
    final grouped = <String, List<SessionSegment>>{};
    for (final raw in _segmentsBox.values) {
      final segment = SessionSegment.fromMap(_asStringMap(raw));
      (grouped[segment.sessionId] ??= <SessionSegment>[]).add(segment);
    }
    for (final segments in grouped.values) {
      segments.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    }
    return grouped;
  }

  @override
  Future<String> createSegment(SessionSegment segment) async {
    await _segmentsBox.put(segment.id, segment.toMap());
    return segment.id;
  }

  // ===== EFFORTS =====

  @override
  Future<List<SegmentEffort>> getSegmentEfforts(String segmentId) async {
    final efforts = _effortsBox.values
        .map((raw) => SegmentEffort.fromMap(_asStringMap(raw)))
        .where((e) => e.segmentId == segmentId)
        .toList();

    efforts.sort(_compareEfforts);
    return efforts;
  }

  /// The canonical effort ordering. Extracted so [getSegmentEfforts] and
  /// [getEffortsBySegment] cannot drift apart — the bulk path must sort
  /// exactly the way the per-segment path does.
  int _compareEfforts(SegmentEffort a, SegmentEffort b) {
    final topCompare = _effectiveEffortTopLevelOrder(
      a,
    ).compareTo(_effectiveEffortTopLevelOrder(b));
    if (topCompare != 0) return topCompare;

    if (a.blockId != null && b.blockId != null && a.blockId == b.blockId) {
      final blockCompare = _effectiveEffortBlockOrder(
        a,
      ).compareTo(_effectiveEffortBlockOrder(b));
      if (blockCompare != 0) return blockCompare;
    }

    final legacyCompare = a.orderIndex.compareTo(b.orderIndex);
    if (legacyCompare != 0) return legacyCompare;

    final createdCompare = a.createdAtMs.compareTo(b.createdAtMs);
    if (createdCompare != 0) return createdCompare;

    return a.id.compareTo(b.id);
  }

  @override
  Future<Map<String, List<SegmentEffort>>> getEffortsBySegment() async {
    final grouped = <String, List<SegmentEffort>>{};
    for (final raw in _effortsBox.values) {
      final effort = SegmentEffort.fromMap(_asStringMap(raw));
      (grouped[effort.segmentId] ??= <SegmentEffort>[]).add(effort);
    }
    for (final efforts in grouped.values) {
      efforts.sort(_compareEfforts);
    }
    return grouped;
  }

  @override
  Future<String> createEffort(SegmentEffort effort) async {
    final sessionId = _getSessionIdForSegment(effort.segmentId);

    int? topLevelOrderIndex = effort.topLevelOrderIndex;
    int? blockOrderIndex = effort.blockOrderIndex;

    if (effort.blockId == null) {
      if (sessionId != null) {
        topLevelOrderIndex ??= _nextTopLevelOrderForSession(sessionId);
      }
      blockOrderIndex = null;
    } else {
      topLevelOrderIndex ??= _blockTopLevelOrderOrFallback(
        effort.blockId!,
        effort.segmentId,
      );
      blockOrderIndex ??= _nextBlockOrderIndex(effort.blockId!);
    }

    final normalized = SegmentEffort(
      id: effort.id,
      segmentId: effort.segmentId,
      orderIndex: effort.blockId == null
          ? (topLevelOrderIndex ?? effort.orderIndex)
          : (blockOrderIndex ?? effort.orderIndex),
      topLevelOrderIndex: topLevelOrderIndex,
      blockOrderIndex: blockOrderIndex,
      effortKind: effort.effortKind,
      exerciseId: effort.exerciseId,
      note: effort.note,
      blockId: effort.blockId,
      createdAtMs: effort.createdAtMs,
      updatedAtMs: effort.updatedAtMs,
    );

    await _effortsBox.put(normalized.id, normalized.toMap());
    return normalized.id;
  }

  @override
  Future<void> updateEffort(SegmentEffort effort) async {
    if (!_effortsBox.containsKey(effort.id)) return;
    await _effortsBox.put(effort.id, effort.toMap());
  }

  // ===== OBSERVATIONS =====

  @override
  Future<List<EffortObservation>> getEffortObservations(String effortId) async {
    return _observationsBox.values
        .map((raw) => EffortObservation.fromMap(_asStringMap(raw)))
        .where((o) => o.effortId == effortId)
        .toList();
  }

  @override
  Future<Map<String, List<EffortObservation>>> getObservationsByEffort() async {
    final grouped = <String, List<EffortObservation>>{};
    for (final raw in _observationsBox.values) {
      final observation = EffortObservation.fromMap(_asStringMap(raw));
      (grouped[observation.effortId] ??= <EffortObservation>[]).add(
        observation,
      );
    }
    return grouped;
  }

  @override
  Future<String> createObservation(EffortObservation observation) async {
    await _observationsBox.put(observation.id, observation.toMap());
    return observation.id;
  }

  @override
  Future<void> updateObservation(EffortObservation observation) async {
    await _observationsBox.put(observation.id, observation.toMap());
  }

  @override
  Future<void> deleteObservation(String id) async {
    await _observationsBox.delete(id);
  }

  @override
  Future<void> deleteObservationsForEffort(String effortId) async {
    final idsToDelete = <dynamic>[];
    for (final entry in _observationsBox.toMap().entries) {
      final raw = _asStringMap(entry.value);
      if (raw['effort_id'] == effortId) {
        idsToDelete.add(entry.key);
      }
    }
    await _observationsBox.deleteAll(idsToDelete);
  }

  // ===== EFFORTS (additional) =====

  @override
  Future<void> deleteEffort(String id) async {
    await deleteObservationsForEffort(id);
    await deleteRoundInstancesForEffort(id);
    await deleteTimedInstancesForEffort(id);
    await deleteEntryRestsForEffort(id);
    await _deleteSensorSummariesTargeting(SensorSummary.scopeEffort, [id]);
    await _effortsBox.delete(id);
  }

  // ===== ROUND INSTANCES =====

  @override
  Future<List<RoundInstance>> getRoundInstances(String effortId) async {
    final instances = _roundInstancesBox.values
        .map((raw) => RoundInstance.fromMap(_asStringMap(raw)))
        .where((r) => r.effortId == effortId)
        .toList();
    instances.sort((a, b) => a.roundIndex.compareTo(b.roundIndex));
    return instances;
  }

  @override
  Future<String> createRoundInstance(RoundInstance instance) async {
    await _roundInstancesBox.put(instance.id, instance.toMap());
    return instance.id;
  }

  @override
  Future<void> updateRoundInstance(RoundInstance instance) async {
    await _roundInstancesBox.put(instance.id, instance.toMap());
  }

  @override
  Future<void> deleteRoundInstance(String id) async {
    await _deleteSensorSummariesTargeting(SensorSummary.scopeRoundInstance, [
      id,
    ]);
    await _roundInstancesBox.delete(id);
  }

  @override
  Future<void> deleteRoundInstancesForEffort(String effortId) async {
    final idsToDelete = <dynamic>[];
    final instanceIds = <String>[];
    for (final entry in _roundInstancesBox.toMap().entries) {
      final raw = _asStringMap(entry.value);
      if (raw['effort_id'] == effortId) {
        idsToDelete.add(entry.key);
        instanceIds.add(raw['id'] as String);
      }
    }
    await _deleteSensorSummariesTargeting(
      SensorSummary.scopeRoundInstance,
      instanceIds,
    );
    await _roundInstancesBox.deleteAll(idsToDelete);
  }

  // ===== TIMED INSTANCES =====

  @override
  Future<List<TimedInstance>> getTimedInstances(String effortId) async {
    final instances = _timedInstancesBox.values
        .map((raw) => TimedInstance.fromMap(_asStringMap(raw)))
        .where((t) => t.effortId == effortId)
        .toList();
    instances.sort((a, b) => a.entryIndex.compareTo(b.entryIndex));
    return instances;
  }

  @override
  Future<Map<String, List<TimedInstance>>> getTimedInstancesByEffort() async {
    final grouped = <String, List<TimedInstance>>{};
    for (final raw in _timedInstancesBox.values) {
      final instance = TimedInstance.fromMap(_asStringMap(raw));
      (grouped[instance.effortId] ??= <TimedInstance>[]).add(instance);
    }
    for (final instances in grouped.values) {
      instances.sort((a, b) => a.entryIndex.compareTo(b.entryIndex));
    }
    return grouped;
  }

  @override
  Future<String> createTimedInstance(TimedInstance instance) async {
    await _timedInstancesBox.put(instance.id, instance.toMap());
    return instance.id;
  }

  @override
  Future<void> updateTimedInstance(TimedInstance instance) async {
    await _timedInstancesBox.put(instance.id, instance.toMap());
  }

  @override
  Future<void> deleteTimedInstance(String id) async {
    await _deleteSensorSummariesTargeting(SensorSummary.scopeTimedInstance, [
      id,
    ]);
    await _timedInstancesBox.delete(id);
  }

  @override
  Future<void> deleteTimedInstancesForEffort(String effortId) async {
    final idsToDelete = <dynamic>[];
    final instanceIds = <String>[];
    for (final entry in _timedInstancesBox.toMap().entries) {
      final raw = _asStringMap(entry.value);
      if (raw['effort_id'] == effortId) {
        idsToDelete.add(entry.key);
        instanceIds.add(raw['id'] as String);
      }
    }
    await _deleteSensorSummariesTargeting(
      SensorSummary.scopeTimedInstance,
      instanceIds,
    );
    await _timedInstancesBox.deleteAll(idsToDelete);
  }

  // ===== ENTRY RESTS =====

  @override
  Future<List<EntryRest>> getEntryRests(String effortId) async {
    final rests = _entryRestsBox.values
        .map((raw) => EntryRest.fromMap(_asStringMap(raw)))
        .where((r) => r.effortId == effortId)
        .toList();
    rests.sort((a, b) => a.entryIndex.compareTo(b.entryIndex));
    return rests;
  }

  @override
  Future<String> createEntryRest(EntryRest rest) async {
    await _entryRestsBox.put(rest.id, rest.toMap());
    return rest.id;
  }

  @override
  Future<void> updateEntryRest(EntryRest rest) async {
    await _entryRestsBox.put(rest.id, rest.toMap());
  }

  @override
  Future<void> deleteEntryRestsForEffort(String effortId) async {
    final idsToDelete = <dynamic>[];
    for (final entry in _entryRestsBox.toMap().entries) {
      final raw = _asStringMap(entry.value);
      if (raw['effort_id'] == effortId) {
        idsToDelete.add(entry.key);
      }
    }
    await _entryRestsBox.deleteAll(idsToDelete);
  }

  @override
  Future<ExerciseNote?> getExerciseNote(String exerciseId) async {
    try {
      return _exerciseNotesBox.values
          .map((raw) => ExerciseNote.fromMap(_asStringMap(raw)))
          .firstWhere((n) => n.exerciseId == exerciseId);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveExerciseNote(ExerciseNote note) async {
    await _exerciseNotesBox.put(note.id, note.toMap());
  }

  @override
  Future<void> deleteExerciseNote(String exerciseId) async {
    final idsToDelete = <dynamic>[];
    for (final entry in _exerciseNotesBox.toMap().entries) {
      final raw = _asStringMap(entry.value);
      if (raw['exercise_id'] == exerciseId) {
        idsToDelete.add(entry.key);
      }
    }
    await _exerciseNotesBox.deleteAll(idsToDelete);
  }

  // ===== SPORT CATEGORIES =====

  @override
  Future<List<SportCategory>> getSportCategories() async {
    final categories = _sportCategoriesBox.values
        .map((raw) => SportCategory.fromMap(_asStringMap(raw)))
        .toList();
    categories.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return categories;
  }

  @override
  Future<SportCategory?> getSportCategoryById(String id) async {
    final raw = _sportCategoriesBox.get(id);
    if (raw == null) return null;
    return SportCategory.fromMap(_asStringMap(raw));
  }

  @override
  Future<SportCategory?> getSportCategoryByKey(String key) async {
    for (final raw in _sportCategoriesBox.values) {
      final category = SportCategory.fromMap(_asStringMap(raw));
      if (category.key == key) return category;
    }
    return null;
  }

  // ===== DISCIPLINES =====

  @override
  Future<List<Discipline>> getDisciplines() async {
    return _disciplinesBox.values
        .map((raw) => Discipline.fromMap(_asStringMap(raw)))
        .toList();
  }

  @override
  Future<Discipline?> getDisciplineById(String id) async {
    final raw = _disciplinesBox.get(id);
    if (raw == null) return null;
    return Discipline.fromMap(_asStringMap(raw));
  }

  @override
  Future<List<Discipline>> getDisciplinesByCategory(String categoryId) async {
    return _disciplinesBox.values
        .map((raw) => Discipline.fromMap(_asStringMap(raw)))
        .where((d) => d.categoryId == categoryId)
        .toList();
  }

  // ===== MUSCLE GROUPS =====

  @override
  Future<List<MuscleGroup>> getMuscleGroups() async {
    return _muscleGroupsBox.values
        .map((raw) => MuscleGroup.fromMap(_asStringMap(raw)))
        .toList();
  }

  @override
  Future<void> upsertMuscleGroup(MuscleGroup group) async {
    await _muscleGroupsBox.put(group.id, group.toMap());
  }

  @override
  Future<List<MuscleGroup>> getExerciseMuscleGroups(String exerciseId) async {
    final muscleGroupIds = _asStringList(
      _exerciseMuscleGroupsBox.get(exerciseId),
    );
    return muscleGroupIds
        .map((id) => _muscleGroupsBox.get(id))
        .whereType<Map>()
        .map((raw) => MuscleGroup.fromMap(_asStringMap(raw)))
        .toList();
  }

  @override
  Future<void> setExerciseMuscleGroups(
    String exerciseId,
    List<String> muscleGroupIds,
  ) async {
    await _exerciseMuscleGroupsBox.put(
      exerciseId,
      List<String>.from(muscleGroupIds),
    );
  }

  // ===== EQUIPMENT =====

  @override
  Future<List<Equipment>> getEquipment() async {
    return _equipmentBox.values
        .map((raw) => Equipment.fromMap(_asStringMap(raw)))
        .toList();
  }

  @override
  Future<List<Equipment>> getExerciseEquipment(String exerciseId) async {
    final equipmentIds = _asStringList(_exerciseEquipmentBox.get(exerciseId));
    return equipmentIds
        .map((id) => _equipmentBox.get(id))
        .whereType<Map>()
        .map((raw) => Equipment.fromMap(_asStringMap(raw)))
        .toList();
  }

  // ===== TAGS =====

  @override
  Future<List<Tag>> getTags() async {
    return _tagsBox.values
        .map((raw) => Tag.fromMap(_asStringMap(raw)))
        .toList();
  }

  @override
  Future<List<Tag>> getExerciseTags(String exerciseId) async {
    final tagIds = _asStringList(_exerciseTagsBox.get(exerciseId));
    return tagIds
        .map((id) => _tagsBox.get(id))
        .whereType<Map>()
        .map((raw) => Tag.fromMap(_asStringMap(raw)))
        .toList();
  }

  // ===== UNITS =====

  @override
  Future<List<UnitModel>> getUnits() async {
    return _unitsBox.values
        .map((raw) => UnitModel.fromMap(_asStringMap(raw)))
        .toList();
  }

  @override
  Future<UnitModel?> getUnitById(String id) async {
    final raw = _unitsBox.get(id);
    if (raw == null) return null;
    return UnitModel.fromMap(_asStringMap(raw));
  }

  // ===== METRICS =====

  @override
  Future<List<MetricDefinition>> getMetricDefinitions() async {
    return _metricsBox.values
        .map((raw) => MetricDefinition.fromMap(_asStringMap(raw)))
        .toList();
  }

  @override
  Future<List<MetricDefinition>> getMetricsForEffortKind(
    String effortKind,
  ) async {
    final metricIds = <String>[];
    for (final entry in _metricEffortKindsBox.toMap().entries) {
      final effortKinds = _asStringList(entry.value);
      if (effortKinds.contains(effortKind)) {
        metricIds.add(entry.key.toString());
      }
    }

    return metricIds
        .map((id) => _metricsBox.get(id))
        .whereType<Map>()
        .map((raw) => MetricDefinition.fromMap(_asStringMap(raw)))
        .toList();
  }

  @override
  Future<MetricDefinition?> getMetricById(String id) async {
    final raw = _metricsBox.get(id);
    if (raw == null) return null;
    return MetricDefinition.fromMap(_asStringMap(raw));
  }

  // ===== EXERCISE CAPABILITIES =====

  @override
  Future<List<String>> getExerciseCapabilities(String exerciseId) async {
    return _getCapabilities(exerciseId);
  }

  @override
  Future<void> setExerciseCapabilities(
    String exerciseId,
    List<String> capabilities,
  ) async {
    await _exerciseCapabilitiesBox.put(
      exerciseId,
      List<String>.from(capabilities),
    );
  }

  List<String> _getCapabilities(String exerciseId) {
    return _asStringList(_exerciseCapabilitiesBox.get(exerciseId));
  }

  @override
  Future<List<Exercise>> getExercisesRankedForModality(
    String? modality, {
    String? searchText,
    String? disciplineId,
    List<String>? muscleGroupIds,
  }) async {
    var results = _exercisesBox.values
        .map((raw) => Exercise.fromMap(_asStringMap(raw)))
        .where((e) => !e.isArchived);

    if (disciplineId != null && disciplineId.isNotEmpty) {
      results = results.where((e) => e.disciplineId == disciplineId);
    }

    if (muscleGroupIds != null && muscleGroupIds.isNotEmpty) {
      results = results.where((e) {
        final exerciseMuscles = _asStringList(
          _exerciseMuscleGroupsBox.get(e.id),
        );
        return exerciseMuscles.any((id) => muscleGroupIds.contains(id));
      });
    }

    final hasSearchText = searchText != null && searchText.isNotEmpty;
    Map<String, int> fuzzyScores = const {};
    if (hasSearchText) {
      final matched = FuzzySearch.filterAndRank(searchText, results.toList());
      fuzzyScores = {
        for (final exercise in matched)
          exercise.id: FuzzySearch.score(searchText, exercise.name),
      };
      results = matched;
    }

    final allExercises = results.toList();

    if (modality == null) {
      if (!hasSearchText) {
        allExercises.sort((a, b) => a.name.compareTo(b.name));
      }
      return allExercises
          .map((e) => e.copyWith(capabilities: _getCapabilities(e.id)))
          .toList();
    }

    final modalityConfig = ModalityConfig.forModality(modality);
    if (modalityConfig == null) {
      if (!hasSearchText) {
        allExercises.sort((a, b) => a.name.compareTo(b.name));
      }
      return allExercises
          .map((e) => e.copyWith(capabilities: _getCapabilities(e.id)))
          .toList();
    }

    final scoredExercises = <(Exercise, double)>[];

    for (final exercise in allExercises) {
      final caps = _getCapabilities(exercise.id);
      final exerciseWithCaps = exercise.copyWith(capabilities: caps);

      String? exerciseCategoryId;
      if (exercise.disciplineId != null) {
        final disciplineRaw = _disciplinesBox.get(exercise.disciplineId);
        if (disciplineRaw != null) {
          final discipline = Discipline.fromMap(_asStringMap(disciplineRaw));
          exerciseCategoryId = discipline.categoryId;
        }
      }

      final score = modalityConfig.calculateRelevanceScore(
        exerciseCapabilities: caps,
        exerciseCategoryId: exerciseCategoryId,
      );

      scoredExercises.add((exerciseWithCaps, score));
    }

    scoredExercises.sort((a, b) {
      if (hasSearchText) {
        final fuzzyCompare = (fuzzyScores[a.$1.id] ?? (1 << 30)).compareTo(
          fuzzyScores[b.$1.id] ?? (1 << 30),
        );
        if (fuzzyCompare != 0) return fuzzyCompare;
      }

      final scoreCompare = b.$2.compareTo(a.$2);
      if (scoreCompare != 0) return scoreCompare;
      return a.$1.name.compareTo(b.$1.name);
    });

    // Attach scores to exercises for UI partitioning (Recommended vs Other)
    return scoredExercises
        .map((e) => e.$1.copyWith(relevanceScore: e.$2))
        .toList();
  }

  // ===== TEMPLATES =====

  @override
  Future<List<WorkoutTemplate>> getTemplates() async {
    return _templatesBox.values
        .map((raw) => WorkoutTemplate.fromMap(_asStringMap(raw)))
        .toList();
  }

  @override
  Future<WorkoutTemplate?> getTemplateById(String id) async {
    final raw = _templatesBox.get(id);
    if (raw == null) return null;
    return WorkoutTemplate.fromMap(_asStringMap(raw));
  }

  @override
  Future<String> createTemplate(WorkoutTemplate template) async {
    await _templatesBox.put(template.id, template.toMap());
    return template.id;
  }

  @override
  Future<void> updateTemplate(WorkoutTemplate template) async {
    await _templatesBox.put(template.id, template.toMap());
  }

  @override
  Future<void> deleteTemplate(String id) async {
    final segmentIds = _templateSegmentsBox.values
        .map((raw) => TemplateSegment.fromMap(_asStringMap(raw)))
        .where((segment) => segment.templateId == id)
        .map((segment) => segment.id)
        .toList();

    for (final segmentId in segmentIds) {
      await deleteTemplateSegment(segmentId);
    }

    await _templatesBox.delete(id);
  }

  @override
  Future<List<TemplateSegment>> getTemplateSegments(String templateId) async {
    final segments = _templateSegmentsBox.values
        .map((raw) => TemplateSegment.fromMap(_asStringMap(raw)))
        .where((s) => s.templateId == templateId)
        .toList();

    segments.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    return segments;
  }

  @override
  Future<String> createTemplateSegment(TemplateSegment segment) async {
    await _templateSegmentsBox.put(segment.id, segment.toMap());
    return segment.id;
  }

  @override
  Future<void> updateTemplateSegment(TemplateSegment segment) async {
    await _templateSegmentsBox.put(segment.id, segment.toMap());
  }

  @override
  Future<void> deleteTemplateSegment(String id) async {
    final effortIds = _templateEffortsBox.values
        .map((raw) => TemplateEffort.fromMap(_asStringMap(raw)))
        .where((effort) => effort.templateSegmentId == id)
        .map((effort) => effort.id)
        .toList();

    for (final effortId in effortIds) {
      await deleteTemplateEffort(effortId);
    }

    await _templateSegmentsBox.delete(id);
  }

  @override
  Future<List<TemplateEffort>> getTemplateEfforts(
    String templateSegmentId,
  ) async {
    final efforts = _templateEffortsBox.values
        .map((raw) => TemplateEffort.fromMap(_asStringMap(raw)))
        .where((e) => e.templateSegmentId == templateSegmentId)
        .toList();

    efforts.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    return efforts;
  }

  @override
  Future<String> createTemplateEffort(TemplateEffort effort) async {
    await _templateEffortsBox.put(effort.id, effort.toMap());
    return effort.id;
  }

  @override
  Future<void> updateTemplateEffort(TemplateEffort effort) async {
    await _templateEffortsBox.put(effort.id, effort.toMap());
  }

  @override
  Future<void> deleteTemplateEffort(String id) async {
    await deleteTemplateTargetsForEffort(id);
    await _templateEffortsBox.delete(id);
  }

  @override
  Future<List<TemplateTarget>> getTemplateTargets(
    String templateEffortId,
  ) async {
    return _templateTargetsBox.values
        .map((raw) => TemplateTarget.fromMap(_asStringMap(raw)))
        .where((t) => t.templateEffortId == templateEffortId)
        .toList();
  }

  @override
  Future<String> createTemplateTarget(TemplateTarget target) async {
    await _templateTargetsBox.put(target.id, target.toMap());
    return target.id;
  }

  @override
  Future<void> updateTemplateTarget(TemplateTarget target) async {
    await _templateTargetsBox.put(target.id, target.toMap());
  }

  @override
  Future<void> deleteTemplateTarget(String id) async {
    await _templateTargetsBox.delete(id);
  }

  @override
  Future<void> deleteTemplateTargetsForEffort(String templateEffortId) async {
    final idsToDelete = <dynamic>[];
    for (final entry in _templateTargetsBox.toMap().entries) {
      final raw = _asStringMap(entry.value);
      if (raw['template_effort_id'] == templateEffortId) {
        idsToDelete.add(entry.key);
      }
    }
    await _templateTargetsBox.deleteAll(idsToDelete);
  }

  // ===== FOOD GROUPS =====

  @override
  Future<List<FoodGroup>> getFoodGroups({bool includeArchived = false}) async {
    final groups = _foodGroupsBox.values
        .map((raw) => FoodGroup.fromMap(_asStringMap(raw)))
        .toList();

    if (!includeArchived) {
      return groups.where((g) => !g.isArchived).toList();
    }
    return groups;
  }

  @override
  Future<FoodGroup?> getFoodGroupById(String id) async {
    final raw = _foodGroupsBox.get(id);
    if (raw == null) return null;
    return FoodGroup.fromMap(_asStringMap(raw));
  }

  @override
  Future<String> createFoodGroup(FoodGroup group) async {
    await _foodGroupsBox.put(group.id, group.toMap());
    return group.id;
  }

  @override
  Future<void> updateFoodGroup(FoodGroup group) async {
    await _foodGroupsBox.put(group.id, group.toMap());
  }

  @override
  Future<void> archiveFoodGroup(String id) async {
    final raw = _foodGroupsBox.get(id);
    if (raw == null) return;

    final group = FoodGroup.fromMap(_asStringMap(raw));
    final archived = FoodGroup(
      id: group.id,
      name: group.name,
      color: group.color,
      isArchived: true,
      createdAtMs: group.createdAtMs,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    await _foodGroupsBox.put(id, archived.toMap());
  }

  @override
  Future<void> reassignFoodsToGroup(
    List<String> foodIds,
    String? targetGroupId,
  ) async {
    if (foodIds.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final id in foodIds) {
      final raw = _foodsBox.get(id);
      if (raw == null) continue;
      final food = Food.fromMap(_asStringMap(raw));
      if (food.isCatalog) continue; // safety: catalog foods are read-only
      final updated = food.copyWith(groupId: targetGroupId, updatedAtMs: now);
      await _foodsBox.put(id, updated.toMap());
    }
  }

  @override
  Future<void> reassignCatalogFoodsToGroup(
    List<String> catalogFoodIds,
    String? targetGroupId,
  ) async {
    if (catalogFoodIds.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final id in catalogFoodIds) {
      final raw = _foodCatalogBox.get(id);
      if (raw == null) continue;
      final food = Food.fromMap(_asStringMap(raw));
      // Safety: bundled catalog foods are never passed here (the
      // bundled-food guard at the state layer rejects them), but
      // double-check defensively in case a future caller forgets.
      // The bundled id set lives in `FoodLibraryState._bundledCatalogFoodIds`
      // which the repository does not import; the state layer is
      // the only caller and filters before invoking this method.
      final updated = food.copyWith(groupId: targetGroupId, updatedAtMs: now);
      await _foodCatalogBox.put(id, updated.toMap());
    }
  }

  // ===== FOODS =====

  @override
  Future<List<Food>> getFoods({bool includeArchived = false}) async {
    // Returns only library foods (isCatalog == false)
    var foods = _foodsBox.values
        .map((raw) => Food.fromMap(_asStringMap(raw)))
        .where((f) => !f.isCatalog)
        .toList();

    if (!includeArchived) {
      foods = foods.where((f) => !f.isArchived).toList();
    }
    return foods;
  }

  @override
  Future<List<Food>> getFoodsByGroup(
    String groupId, {
    bool includeArchived = false,
  }) async {
    var foods = _foodsBox.values
        .map((raw) => Food.fromMap(_asStringMap(raw)))
        .where((f) => !f.isCatalog && f.groupId == groupId)
        .toList();

    if (!includeArchived) {
      foods = foods.where((f) => !f.isArchived).toList();
    }
    return foods;
  }

  @override
  Future<Food?> getFoodById(String id) async {
    final raw = _foodsBox.get(id);
    if (raw == null) return null;
    final food = Food.fromMap(_asStringMap(raw));
    // Only return library foods
    if (food.isCatalog) return null;
    return food;
  }

  @override
  Future<List<Food>> searchFoods(
    String query, {
    bool includeArchived = false,
  }) async {
    final lowerQuery = query.toLowerCase();
    var foods = _foodsBox.values
        .map((raw) => Food.fromMap(_asStringMap(raw)))
        .where((f) {
          if (f.isCatalog) return false; // Only search library
          if (!includeArchived && f.isArchived) return false;
          return f.name.toLowerCase().contains(lowerQuery);
        })
        .toList();

    return foods;
  }

  @override
  Future<String> createFood(Food food) async {
    await _foodsBox.put(food.id, food.toMap());
    return food.id;
  }

  @override
  Future<void> updateFood(Food food) async {
    await _foodsBox.put(food.id, food.toMap());
  }

  @override
  Future<void> archiveFood(String id) async {
    final raw = _foodsBox.get(id);
    if (raw == null) return;

    final food = Food.fromMap(_asStringMap(raw));
    final archived = food.copyWith(
      isArchived: true,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    await _foodsBox.put(id, archived.toMap());
  }

  @override
  Future<void> removeFood(String id) async {
    // Only remove from the user-owned library (isCatalog = false).
    // Catalog foods are read-only and cannot be removed through this method.
    final raw = _foodsBox.get(id);
    if (raw == null) return;

    final food = Food.fromMap(_asStringMap(raw));
    if (food.isCatalog) return;

    // Hard-delete: remove the row entirely.
    // Past ConsumedFood rows are unaffected because they store a frozen snapshot.
    await _foodsBox.delete(id);
  }

  // ===== FOOD CATALOG =====

  @override
  Future<List<Food>> getCatalogFoods({bool includeArchived = false}) async {
    var foods = _foodCatalogBox.values
        .map((raw) => Food.fromMap(_asStringMap(raw)))
        .toList();

    if (!includeArchived) {
      foods = foods.where((f) => !f.isArchived).toList();
    }
    return foods;
  }

  @override
  Future<Food?> getCatalogFoodById(String id) async {
    final raw = _foodCatalogBox.get(id);
    if (raw == null) return null;
    return Food.fromMap(_asStringMap(raw));
  }

  @override
  Future<String> createCatalogFood(Food food) async {
    // The new row is marked isCatalog = true; the caller's id is
    // respected if non-empty, otherwise a fresh id is generated.
    final now = DateTime.now().millisecondsSinceEpoch;
    final newId = food.id.isEmpty
        ? 'food-$now-${DateTime.now().microsecond}'
        : food.id;
    final newFood = food.copyWith(
      id: newId,
      isCatalog: true,
      createdAtMs: now,
      updatedAtMs: now,
    );
    await _foodCatalogBox.put(newId, newFood.toMap());
    return newId;
  }

  @override
  Future<void> updateCatalogFood(Food food) async {
    if (food.isCatalog != true) {
      throw StateError(
        'updateCatalogFood: food.isCatalog must be true (got '
        '${food.isCatalog} for id ${food.id})',
      );
    }
    if (_foodCatalogBox.get(food.id) == null) {
      throw StateError('Catalog food not found: ${food.id}');
    }
    await _foodCatalogBox.put(food.id, food.toMap());
  }

  @override
  Future<void> deleteCatalogFood(String id) async {
    if (_foodCatalogBox.get(id) == null) {
      throw StateError('Catalog food not found: $id');
    }
    await _foodCatalogBox.delete(id);
  }

  @override
  Future<String> addCatalogFoodToLibrary(String catalogFoodId) async {
    final raw = _foodCatalogBox.get(catalogFoodId);
    if (raw == null) {
      throw Exception('Catalog food not found: $catalogFoodId');
    }

    final catalogFood = Food.fromMap(_asStringMap(raw));
    final now = DateTime.now().millisecondsSinceEpoch;
    final newId = 'food-$now-${DateTime.now().microsecond}';

    // Create a library copy with isCatalog = false and catalogId set
    // to create a durable link back to the source catalog food.
    // copyWith() carries groupId across by default, so the catalog's
    // resolved group_id propagates to the library row.
    final libraryFood = catalogFood.copyWith(
      id: newId,
      isCatalog: false,
      catalogId: catalogFoodId,
      createdAtMs: now,
      updatedAtMs: now,
    );

    await _foodsBox.put(newId, libraryFood.toMap());
    return newId;
  }

  // ===== CONSUMED FOODS (DAY LOG) =====

  @override
  Future<List<ConsumedFood>> getConsumedFoodsForDate(int dateMs) async {
    return _consumedFoodsBox.values
        .map((raw) => ConsumedFood.fromMap(_asStringMap(raw)))
        .where((c) => c.dateMs == dateMs)
        .toList();
  }

  @override
  Future<String> createConsumedFood(ConsumedFood entry) async {
    await _consumedFoodsBox.put(entry.id, entry.toMap());
    return entry.id;
  }

  @override
  Future<void> deleteConsumedFood(String id) async {
    await _consumedFoodsBox.delete(id);
  }

  @override
  Future<List<ConsumedFood>> getConsumedFoodsInRange(
    int fromMs,
    int toMs,
  ) async {
    return _consumedFoodsBox.values
        .map((raw) => ConsumedFood.fromMap(_asStringMap(raw)))
        .where((c) => c.dateMs >= fromMs && c.dateMs <= toMs)
        .toList();
  }

  @override
  Future<void> updateConsumedFood(ConsumedFood entry) async {
    if (!_consumedFoodsBox.containsKey(entry.id)) {
      throw StateError(
        'updateConsumedFood: no ConsumedFood with id "${entry.id}"',
      );
    }
    await _consumedFoodsBox.put(entry.id, entry.toMap());
  }

  @override
  Future<ConsumedFood?> getConsumedFoodById(String id) async {
    final raw = _consumedFoodsBox.get(id);
    if (raw == null) return null;
    return ConsumedFood.fromMap(_asStringMap(raw));
  }

  // ===== WATER LOG (DAY LOG) =====

  /// Daily water volume map keyed by `dateMs` (local midnight) in milliliters.
  /// Absence of a key = 0 ml for that day — callers never see `null`.
  @override
  Future<int> getWaterVolumeForDate(int dateMs) async {
    final raw = _waterLogBox.get(dateMs.toString());
    if (raw == null) return 0;
    final map = _asStringMap(raw);
    return (map['volume_ml'] as int?) ?? 0;
  }

  @override
  Future<void> saveWaterVolumeForDate(int dateMs, int volumeMl) async {
    // Clamp at 0 — the state layer should already have floored the value,
    // but the repository is the last line of defense against bad inputs.
    final clamped = volumeMl < 0 ? 0 : volumeMl;
    final key = dateMs.toString();
    final raw = _waterLogBox.get(key);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (raw == null) {
      await _waterLogBox.put(key, <String, dynamic>{
        'id': WaterLogEntry.idForDate(dateMs),
        'date_ms': dateMs,
        'volume_ml': clamped,
        'created_at_ms': now,
        'updated_at_ms': now,
      });
    } else {
      final existing = _asStringMap(raw);
      await _waterLogBox.put(key, <String, dynamic>{
        'id': WaterLogEntry.idForDate(dateMs),
        'date_ms': dateMs,
        'volume_ml': clamped,
        'created_at_ms': (existing['created_at_ms'] as int?) ?? now,
        'updated_at_ms': now,
      });
    }
  }

  // ===== CATALOG VERSION + SEED-ENTRY TOMBSTONES =====
  //
  // The bundled catalog carries a version constant (see
  // [bundledCatalogVersion] in lib/core/constants/catalog_version.dart).
  // At app start, [CatalogRefreshService] compares the device's stored
  // version against the bundled version and re-applies any new or changed
  // seed entries in place. Per-entry tombstones — set by the state layer
  // when the user mutates a seed entry — protect user edits from being
  // overwritten by the refresh.

  @override
  Future<int> getCatalogVersion({int defaultValue = 0}) async {
    final raw = _metaBox.get(_catalogVersionKey);
    if (raw is int) return raw;
    return defaultValue;
  }

  @override
  Future<void> setCatalogVersion(int version) async {
    await _metaBox.put(_catalogVersionKey, version);
  }

  @override
  Future<bool> isSeedEntryTouched(String entityType, String id) async {
    return (_metaBox.get(seedEntryTouchedKey(entityType, id)) as bool?) ??
        false;
  }

  @override
  Future<void> markSeedEntryTouched(String entityType, String id) async {
    await _metaBox.put(seedEntryTouchedKey(entityType, id), true);
  }

  // ===== DATA-MIGRATION VERSION SEQUENCE =====
  //
  // The device's `data_version` integer is the single source of truth for
  // "which consolidated migration step the device has reached". The
  // legacy one-shot markers (`seed_units_migrated_v1`, etc.) are read
  // ONCE by [DataMigrationService]'s back-compat shim (on the first
  // launch under the new system) to map legacy installs to the correct
  // starting version. From that point on, the legacy markers are ignored.

  @override
  Future<int> getDataVersion({int defaultValue = 1}) async {
    final raw = _metaBox.get(_dataVersionKey);
    if (raw is int) return raw;
    return defaultValue;
  }

  @override
  Future<void> setDataVersion(int version) async {
    await _metaBox.put(_dataVersionKey, version);
  }

  @override
  Future<int> getLegacyAppliedDataVersion() async {
    // Walk the legacy markers in REVERSE order; the highest one present
    // wins because the legacy code always ran them in order (a device
    // with the LATER marker present is guaranteed to have the earlier
    // ones present too).
    if (_metaBox.get(_foodCategoryGroupIdMigratedKey) == true) return 14;
    if (_metaBox.get(_defaultFoodGroupsSeededKey) == true) return 13;
    if (_metaBox.get(_foodCatalogSeededKey) == true) return 12;
    if (_metaBox.get(_nutritionTargetsDailyMigrationKey) == true) return 11;
    if (_metaBox.get(_exerciseLibraryRefreshMigrationKey) == true) return 10;
    if (_metaBox.get(_timedExtraWeightMigrationKey) == true) return 9;
    if (_metaBox.get(_exerciseContentFieldsMigrationKey) == true) return 8;
    if (_metaBox.get(_calendarSeedPurgeMigrationKey) == true) return 7;
    if (_metaBox.get(_calendarDataMigrationKey) == true) return 6;
    if (_metaBox.get(_sessionFeelingFieldsMigrationKey) == true) return 5;
    if (_metaBox.get(_exerciseRoundDefaultsMigrationKey) == true) return 4;
    if (_metaBox.get(_seedUnitsMigrationKey) == true) return 3;
    if (_metaBox.get(_seedLoadedKey) == true) return 2;
    return 1;
  }

  @override
  Future<({int from, int to})?> getLastDataVersionTransition() async {
    final from = _metaBox.get(_dataVersionLastFromKey);
    final to = _metaBox.get(_dataVersionLastToKey);
    if (from is int && to is int) return (from: from, to: to);
    return null;
  }

  @override
  Future<void> setLastDataVersionTransition(int from, int to) async {
    await _metaBox.put(_dataVersionLastFromKey, from);
    await _metaBox.put(_dataVersionLastToKey, to);
  }

  // ===== UTILITY METHODS =====

  Future<void> clear() async {
    await _exercisesBox.clear();
    await _sessionsBox.clear();
    await _userProfilesBox.clear();
    await _bodyMeasurementsBox.clear();
    await _segmentsBox.clear();
    await _effortsBox.clear();
    await _observationsBox.clear();
    await _roundInstancesBox.clear();
    await _timedInstancesBox.clear();
    await _entryRestsBox.clear();
    await _exerciseNotesBox.clear();
    await _unitsBox.clear();
    await _metricsBox.clear();
    await _muscleGroupsBox.clear();
    await _disciplinesBox.clear();
    await _sportCategoriesBox.clear();
    await _equipmentBox.clear();
    await _tagsBox.clear();
    await _templatesBox.clear();
    await _templateSegmentsBox.clear();
    await _templateEffortsBox.clear();
    await _templateTargetsBox.clear();
    await _exerciseMuscleGroupsBox.clear();
    await _exerciseEquipmentBox.clear();
    await _exerciseTagsBox.clear();
    await _metricEffortKindsBox.clear();
    await _exerciseCapabilitiesBox.clear();
    await _plannedSessionsBox.clear();
    await _periodsBox.clear();
    await _sessionBlocksBox.clear();
    await _foodGroupsBox.clear();
    await _foodsBox.clear();
    await _foodCatalogBox.clear();
    await _consumedFoodsBox.clear();
    await _waterLogBox.clear();
    await _watchInboxBox.clear();
    await _sensorSummariesBox.clear();
    await _metaBox.delete(_seedLoadedKey);
    _initialized = false;
  }

  Future<void> reset() async {
    await clear();
    await initialize();
  }

  // ===== PLANNED SESSIONS =====

  @override
  Future<List<PlannedSession>> getPlannedSessions() async {
    final list = _plannedSessionsBox.values
        .map((raw) => PlannedSession.fromMap(_asStringMap(raw)))
        .toList();
    list.sort((a, b) => a.scheduledDateMs.compareTo(b.scheduledDateMs));
    return list;
  }

  @override
  Future<List<PlannedSession>> getPlannedSessionsForDateRange(
    int fromMs,
    int toMs,
  ) async {
    final list = _plannedSessionsBox.values
        .map((raw) => PlannedSession.fromMap(_asStringMap(raw)))
        .where((s) => s.scheduledDateMs >= fromMs && s.scheduledDateMs <= toMs)
        .toList();
    list.sort((a, b) => a.scheduledDateMs.compareTo(b.scheduledDateMs));
    return list;
  }

  @override
  Future<String> createPlannedSession(PlannedSession session) async {
    await _plannedSessionsBox.put(session.id, session.toMap());
    return session.id;
  }

  @override
  Future<void> updatePlannedSession(PlannedSession session) async {
    await _plannedSessionsBox.put(session.id, session.toMap());
  }

  @override
  Future<void> deletePlannedSession(String id) async {
    await _plannedSessionsBox.delete(id);
  }

  @override
  Future<List<PlannedSession>> getPlannedSessionsByTemplateId(
    String templateId,
  ) async {
    return _plannedSessionsBox.values
        .map((raw) => PlannedSession.fromMap(_asStringMap(raw)))
        .where((s) => s.routineTemplateId == templateId)
        .toList();
  }

  @override
  Future<void> deletePlannedSessionsByTemplateId(String templateId) async {
    final toDelete = _plannedSessionsBox.keys.where((key) {
      final raw = _plannedSessionsBox.get(key);
      if (raw == null) return false;
      final m = _asStringMap(raw);
      return m['routine_template_id'] == templateId;
    }).toList();
    await _plannedSessionsBox.deleteAll(toDelete);
  }

  // ===== TRAINING PERIODS =====

  @override
  Future<List<TrainingPeriod>> getPeriods() async {
    final list = _periodsBox.values
        .map((raw) => TrainingPeriod.fromMap(_asStringMap(raw)))
        .toList();
    list.sort((a, b) => a.startDateMs.compareTo(b.startDateMs));
    return list;
  }

  @override
  Future<TrainingPeriod?> getPeriodById(String id) async {
    final raw = _periodsBox.get(id);
    if (raw == null) return null;
    return TrainingPeriod.fromMap(_asStringMap(raw));
  }

  @override
  Future<String> createPeriod(TrainingPeriod period) async {
    await _periodsBox.put(period.id, period.toMap());
    return period.id;
  }

  @override
  Future<void> updatePeriod(TrainingPeriod period) async {
    await _periodsBox.put(period.id, period.toMap());
  }

  @override
  Future<void> deletePeriod(String id) async {
    await _periodsBox.delete(id);
  }

  @override
  Future<bool> hasPeriodOverlap(
    int startMs,
    int endMs, {
    String? excludeId,
  }) async {
    return _periodsBox.values.any((raw) {
      final p = TrainingPeriod.fromMap(_asStringMap(raw));
      if (p.id == excludeId) return false;
      return startMs <= p.endDateMs && endMs >= p.startDateMs;
    });
  }

  // ===== SESSION BLOCKS =====

  @override
  Future<List<SessionBlock>> getSessionBlocks(String sessionId) async {
    final blocks = _sessionBlocksBox.values
        .map((raw) => SessionBlock.fromMap(_asStringMap(raw)))
        .where((b) => b.sessionId == sessionId)
        .toList();
    blocks.sort((a, b) {
      final topCompare = _effectiveBlockTopLevelOrder(
        a,
      ).compareTo(_effectiveBlockTopLevelOrder(b));
      if (topCompare != 0) return topCompare;

      final legacyCompare = a.orderIndex.compareTo(b.orderIndex);
      if (legacyCompare != 0) return legacyCompare;

      final createdCompare = a.createdAtMs.compareTo(b.createdAtMs);
      if (createdCompare != 0) return createdCompare;

      return a.id.compareTo(b.id);
    });
    return blocks;
  }

  @override
  Future<String> createSessionBlock(SessionBlock block) async {
    final normalized = SessionBlock(
      id: block.id,
      sessionId: block.sessionId,
      name: block.name,
      orderIndex: block.orderIndex,
      topLevelOrderIndex:
          block.topLevelOrderIndex ??
          _nextTopLevelOrderForSession(block.sessionId),
      createdAtMs: block.createdAtMs,
      updatedAtMs: block.updatedAtMs,
    );
    await _sessionBlocksBox.put(normalized.id, normalized.toMap());
    return normalized.id;
  }

  @override
  Future<void> updateSessionBlock(SessionBlock block) async {
    await _sessionBlocksBox.put(block.id, block.toMap());
  }

  @override
  Future<void> deleteSessionBlock(String blockId) async {
    // 1. Find all efforts linked to this block
    final linkedEffortKeys = _effortsBox
        .toMap()
        .entries
        .where((e) => _asStringMap(e.value)['block_id'] == blockId)
        .map((e) => e.key)
        .toList();

    // 2. For each linked effort, cascade-delete sub-records then the effort itself
    for (final effortKey in linkedEffortKeys) {
      // D-131: summaries of the effort and of its instances go with them.
      final effortId =
          _asStringMap(_effortsBox.get(effortKey)!)['id'] as String;
      await _deleteSensorSummariesTargeting(SensorSummary.scopeEffort, [
        effortId,
      ]);
      await _deleteSensorSummariesTargeting(
        SensorSummary.scopeRoundInstance,
        _roundInstancesBox.values
            .map(_asStringMap)
            .where((m) => m['effort_id'] == effortId)
            .map((m) => m['id'] as String),
      );
      await _deleteSensorSummariesTargeting(
        SensorSummary.scopeTimedInstance,
        _timedInstancesBox.values
            .map(_asStringMap)
            .where((m) => m['effort_id'] == effortId)
            .map((m) => m['id'] as String),
      );

      final obsKeys = _observationsBox
          .toMap()
          .entries
          .where((e) => _asStringMap(e.value)['effort_id'] == effortKey)
          .map((e) => e.key)
          .toList();
      for (final k in obsKeys) {
        await _observationsBox.delete(k);
      }

      final riKeys = _roundInstancesBox
          .toMap()
          .entries
          .where((e) => _asStringMap(e.value)['effort_id'] == effortKey)
          .map((e) => e.key)
          .toList();
      for (final k in riKeys) {
        await _roundInstancesBox.delete(k);
      }

      final tiKeys = _timedInstancesBox
          .toMap()
          .entries
          .where((e) => _asStringMap(e.value)['effort_id'] == effortKey)
          .map((e) => e.key)
          .toList();
      for (final k in tiKeys) {
        await _timedInstancesBox.delete(k);
      }

      final erKeys = _entryRestsBox
          .toMap()
          .entries
          .where((e) => _asStringMap(e.value)['effort_id'] == effortKey)
          .map((e) => e.key)
          .toList();
      for (final k in erKeys) {
        await _entryRestsBox.delete(k);
      }

      await _effortsBox.delete(effortKey);
    }

    // 3. Delete the block itself
    await _sessionBlocksBox.delete(blockId);
  }

  @override
  Future<void> reorderSessionBlocks(
    String sessionId,
    List<String> orderedIds,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < orderedIds.length; i++) {
      final id = orderedIds[i];
      final raw = _sessionBlocksBox.get(id);
      if (raw == null) continue;
      final m = _asStringMap(raw);
      if (m['session_id'] != sessionId) continue;
      m['order_index'] = i;
      m['top_level_order_index'] = i;
      m['updated_at_ms'] = now;
      await _sessionBlocksBox.put(id, m);
    }
  }

  @override
  Future<String> cloneSessionBlock(String blockId) async {
    final originalRaw = _sessionBlocksBox.get(blockId);
    if (originalRaw == null) {
      throw StateError('SessionBlock $blockId not found');
    }
    final original = SessionBlock.fromMap(_asStringMap(originalRaw));

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final name = _formatBlockTimeLabel(nowMs);

    final maxOrder = _sessionBlocksBox.values
        .map((raw) => SessionBlock.fromMap(_asStringMap(raw)))
        .where((b) => b.sessionId == original.sessionId)
        .fold<int>(-1, (m, b) => b.orderIndex > m ? b.orderIndex : m);

    final newBlock = SessionBlock(
      id: _hiveUuid.v4(),
      sessionId: original.sessionId,
      name: name,
      orderIndex: maxOrder + 1,
      topLevelOrderIndex: _nextTopLevelOrderForSession(original.sessionId),
      createdAtMs: nowMs,
      updatedAtMs: nowMs,
    );
    await _sessionBlocksBox.put(newBlock.id, newBlock.toMap());

    // Deep-clone all efforts linked to the original block
    final linkedEfforts =
        _effortsBox.values
            .map((raw) => SegmentEffort.fromMap(_asStringMap(raw)))
            .where((effort) => effort.blockId == blockId)
            .toList()
          ..sort((a, b) {
            final blockCompare = _effectiveEffortBlockOrder(
              a,
            ).compareTo(_effectiveEffortBlockOrder(b));
            if (blockCompare != 0) return blockCompare;

            final legacyCompare = a.orderIndex.compareTo(b.orderIndex);
            if (legacyCompare != 0) return legacyCompare;

            final createdCompare = a.createdAtMs.compareTo(b.createdAtMs);
            if (createdCompare != 0) return createdCompare;

            return a.id.compareTo(b.id);
          });

    for (var i = 0; i < linkedEfforts.length; i++) {
      final originalEffort = linkedEfforts[i];
      final newEffortId = _hiveUuid.v4();

      final newEffort = SegmentEffort(
        id: newEffortId,
        segmentId: originalEffort.segmentId,
        orderIndex: i,
        topLevelOrderIndex: newBlock.topLevelOrderIndex ?? newBlock.orderIndex,
        blockOrderIndex: i,
        effortKind: originalEffort.effortKind,
        exerciseId: originalEffort.exerciseId,
        note: originalEffort.note,
        blockId: newBlock.id,
        createdAtMs: nowMs,
        updatedAtMs: nowMs,
      );
      await _effortsBox.put(newEffortId, newEffort.toMap());

      // Clone observations — preserve all numeric values from the source
      for (final obsEntry in _observationsBox.toMap().entries) {
        final obsMap = _asStringMap(obsEntry.value);
        if (obsMap['effort_id'] != originalEffort.id) continue;
        final obs = EffortObservation.fromMap(obsMap);
        final newObs = EffortObservation(
          id: _clonedRowId(
            obs.id,
            sourceEffortId: originalEffort.id,
            newEffortId: newEffortId,
            freshId: _hiveUuid.v4(),
          ),
          effortId: newEffortId,
          metricId: obs.metricId,
          unitId: obs.unitId,
          valueInt: obs.valueInt,
          valueReal: obs.valueReal,
          valueText: obs.valueText,
          valueBool: obs.valueBool,
          valueSource: obs.valueSource,
          rpeRating: obs.rpeRating,
          restDurationMs: obs.restDurationMs,
          createdAtMs: nowMs,
          updatedAtMs: nowMs,
        );
        await _observationsBox.put(newObs.id, newObs.toMap());
      }

      // Clone round instances with state reset to notStarted
      for (final riEntry in _roundInstancesBox.toMap().entries) {
        final riMap = _asStringMap(riEntry.value);
        if (riMap['effort_id'] != originalEffort.id) continue;
        final ri = RoundInstance.fromMap(riMap);
        final newRi = RoundInstance(
          id: _hiveUuid.v4(),
          effortId: newEffortId,
          roundIndex: ri.roundIndex,
          plannedDurationSecs: ri.plannedDurationSecs,
          actualDurationSecs: 0,
          startedAtMs: 0,
          finishedAtMs: null,
          completed: false,
          state: RoundState.notStarted,
          pausedAtMs: null,
          totalPausedDurationMs: 0,
          createdAtMs: nowMs,
          updatedAtMs: nowMs,
        );
        await _roundInstancesBox.put(newRi.id, newRi.toMap());
      }

      // Clone timed instances with state reset to notStarted
      for (final tiEntry in _timedInstancesBox.toMap().entries) {
        final tiMap = _asStringMap(tiEntry.value);
        if (tiMap['effort_id'] != originalEffort.id) continue;
        final ti = TimedInstance.fromMap(tiMap);
        final newTi = TimedInstance(
          id: _hiveUuid.v4(),
          effortId: newEffortId,
          entryIndex: ti.entryIndex,
          targetDurationSecs: ti.targetDurationSecs,
          actualDurationSecs: 0,
          startedAtMs: 0,
          finishedAtMs: null,
          state: TimedState.notStarted,
          pausedAtMs: null,
          totalPausedDurationMs: 0,
          createdAtMs: nowMs,
          updatedAtMs: nowMs,
        );
        await _timedInstancesBox.put(newTi.id, newTi.toMap());
      }
    }

    return newBlock.id;
  }

  /// A copied row's id (D-329): its source id with the effort id replaced, so
  /// the copy's entries stay addressable like any other. Nothing else about the
  /// id changes — a 3a suffix stays, because dropping it would put two copied
  /// rows on one id and merge them (F-8). A source row that carries no entry
  /// number, or belongs to another effort, keeps a fresh unique id.
  String _clonedRowId(
    String sourceId, {
    required String sourceEffortId,
    required String newEffortId,
    required String freshId,
  }) {
    final prefix = 'obs-$sourceEffortId-';
    if (!sourceId.startsWith(prefix)) return freshId;
    if (EntryRows.parseId(sourceId) == null) return freshId;
    return 'obs-$newEffortId-${sourceId.substring(prefix.length)}';
  }

  String _formatBlockTimeLabel(int timestampMs) {
    final now = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final hour12 = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final minute = now.minute.toString().padLeft(2, '0');
    final period = now.hour < 12 ? 'AM' : 'PM';
    return '$hour12:$minute $period';
  }

  @override
  Future<void> assignEffortToBlock(String effortId, String? blockId) async {
    final raw = _effortsBox.get(effortId);
    if (raw == null) return;
    final m = _asStringMap(raw);

    final segmentId = m['segment_id'] as String?;

    if (blockId == null) {
      final sessionId = segmentId == null
          ? null
          : _getSessionIdForSegment(segmentId);
      final topLevelOrderIndex =
          (m['top_level_order_index'] as int?) ??
          (sessionId == null
              ? (m['order_index'] as int? ?? 0)
              : _nextTopLevelOrderForSession(sessionId));
      m['top_level_order_index'] = topLevelOrderIndex;
      m['block_order_index'] = null;
      m['order_index'] = topLevelOrderIndex;
    } else {
      final topLevelOrderIndex = _blockTopLevelOrderOrFallback(
        blockId,
        segmentId ?? '',
      );
      final blockOrderIndex = _nextBlockOrderIndex(blockId);
      m['top_level_order_index'] = topLevelOrderIndex;
      m['block_order_index'] = blockOrderIndex;
      m['order_index'] = blockOrderIndex;
    }

    m['block_id'] = blockId;
    m['updated_at_ms'] = DateTime.now().millisecondsSinceEpoch;
    await _effortsBox.put(effortId, m);
  }

  int _effectiveBlockTopLevelOrder(SessionBlock block) =>
      block.topLevelOrderIndex ?? block.orderIndex;

  int _effectiveEffortTopLevelOrder(SegmentEffort effort) =>
      effort.topLevelOrderIndex ?? effort.orderIndex;

  int _effectiveEffortBlockOrder(SegmentEffort effort) =>
      effort.blockOrderIndex ?? effort.orderIndex;

  String? _getSessionIdForSegment(String segmentId) {
    final segmentRaw = _segmentsBox.get(segmentId);
    if (segmentRaw == null) return null;
    return _asStringMap(segmentRaw)['session_id'] as String?;
  }

  int _nextTopLevelOrderForSession(String sessionId) {
    var maxOrder = -1;

    for (final blockRaw in _sessionBlocksBox.values) {
      final block = SessionBlock.fromMap(_asStringMap(blockRaw));
      if (block.sessionId != sessionId) continue;
      final order = _effectiveBlockTopLevelOrder(block);
      if (order > maxOrder) maxOrder = order;
    }

    final segmentIds = _segmentsBox.values
        .map((raw) => SessionSegment.fromMap(_asStringMap(raw)))
        .where((segment) => segment.sessionId == sessionId)
        .map((segment) => segment.id)
        .toSet();

    for (final effortRaw in _effortsBox.values) {
      final effort = SegmentEffort.fromMap(_asStringMap(effortRaw));
      if (!segmentIds.contains(effort.segmentId)) continue;
      if (effort.blockId != null) continue;
      final order = _effectiveEffortTopLevelOrder(effort);
      if (order > maxOrder) maxOrder = order;
    }

    return maxOrder + 1;
  }

  int _nextBlockOrderIndex(String blockId) {
    var maxOrder = -1;

    for (final effortRaw in _effortsBox.values) {
      final effort = SegmentEffort.fromMap(_asStringMap(effortRaw));
      if (effort.blockId != blockId) continue;
      final order = _effectiveEffortBlockOrder(effort);
      if (order > maxOrder) maxOrder = order;
    }

    return maxOrder + 1;
  }

  int _blockTopLevelOrderOrFallback(String blockId, String segmentId) {
    final blockRaw = _sessionBlocksBox.get(blockId);
    if (blockRaw != null) {
      final block = SessionBlock.fromMap(_asStringMap(blockRaw));
      return _effectiveBlockTopLevelOrder(block);
    }

    final sessionId = _getSessionIdForSegment(segmentId);
    if (sessionId == null) return 0;
    return _nextTopLevelOrderForSession(sessionId);
  }

  @override
  Future<List<TrainingSession>> getInProgressSessions() async {
    final List<TrainingSession> inProgressSessions = [];
    try {
      for (final sessionMap in _sessionsBox.values) {
        try {
          final map = _asStringMap(sessionMap);
          if (map['ended_at_ms'] == null) {
            inProgressSessions.add(TrainingSession.fromMap(map));
          }
        } catch (e) {
          // Log and skip malformed records
        }
      }
      inProgressSessions.sort((a, b) => b.startedAtMs.compareTo(a.startedAtMs));
    } catch (e) {
      // Error retrieving in-progress sessions
    }
    return inProgressSessions;
  }

  // ===== WATCH CAPTURE: SESSION INBOX + SENSOR SUMMARIES (D-131 / D-132) =====

  @override
  Future<bool> stageWatchInboxEntry(WatchInboxEntry entry) async {
    // Put-if-absent. No await between the check and the put, so a
    // concurrent stage of the same id cannot slip in between them.
    if (_watchInboxBox.containsKey(entry.entryId)) return false;
    await _watchInboxBox.put(entry.entryId, entry.toMap());
    return true;
  }

  @override
  Future<List<WatchInboxEntry>> getWatchInboxEntriesForSession(
    String watchSessionId,
  ) async {
    final entries = _watchInboxBox.values
        .map(_asStringMap)
        .where((m) => m['watch_session_id'] == watchSessionId)
        .map(WatchInboxEntry.fromMap)
        .toList();
    entries.sort((a, b) {
      final byReceived = a.receivedAtMs.compareTo(b.receivedAtMs);
      if (byReceived != 0) return byReceived;
      return a.entryId.compareTo(b.entryId);
    });
    return entries;
  }

  @override
  Future<WatchInboxEntry?> getWatchInboxEntry(String entryId) async {
    final raw = _watchInboxBox.get(entryId);
    if (raw == null) return null;
    return WatchInboxEntry.fromMap(_asStringMap(raw));
  }

  @override
  Future<void> markWatchInboxEntriesApplied(
    Iterable<String> entryIds,
    int appliedAtMs,
  ) async {
    final updates = <String, Map<String, dynamic>>{};
    for (final entryId in entryIds.toSet()) {
      final raw = _watchInboxBox.get(entryId);
      if (raw == null) continue;
      final staged = WatchInboxEntry.fromMap(_asStringMap(raw));
      if (staged.appliedAtMs != null) continue;
      updates[entryId] = WatchInboxEntry.fromMap({
        ...staged.toMap(),
        'applied_at_ms': appliedAtMs,
      }).toMap();
    }
    if (updates.isEmpty) return;
    await _watchInboxBox.putAll(updates);
  }

  @override
  Future<List<String>> getWatchSessionIdsWithUnappliedEnd() async {
    final ends = _watchInboxBox.values
        .map(_asStringMap)
        .where(
          (m) =>
              m['kind'] == WatchInboxEntry.kindSessionEnd &&
              m['applied_at_ms'] == null,
        )
        .map(WatchInboxEntry.fromMap)
        .toList();
    ends.sort((a, b) {
      final byReceived = a.receivedAtMs.compareTo(b.receivedAtMs);
      if (byReceived != 0) return byReceived;
      return a.watchSessionId.compareTo(b.watchSessionId);
    });
    final ids = <String>[];
    for (final end in ends) {
      if (!ids.contains(end.watchSessionId)) ids.add(end.watchSessionId);
    }
    return ids;
  }

  @override
  Future<bool> createSensorSummary(SensorSummary summary) async {
    // Put-if-absent by id (one row per scope + target); see
    // stageWatchInboxEntry for why the check and the put are not split.
    if (_sensorSummariesBox.containsKey(summary.id)) return false;
    await _sensorSummariesBox.put(summary.id, summary.toMap());
    return true;
  }

  @override
  Future<List<SensorSummary>> getSensorSummariesForSession(
    String sessionId,
  ) async {
    final summaries = _sensorSummariesBox.values
        .map(_asStringMap)
        .where((m) => m['session_id'] == sessionId)
        .map(SensorSummary.fromMap)
        .toList();
    summaries.sort((a, b) {
      final byScope = SensorSummary.scopes
          .indexOf(a.scope)
          .compareTo(SensorSummary.scopes.indexOf(b.scope));
      if (byScope != 0) return byScope;
      final byStart = a.windowStartMs.compareTo(b.windowStartMs);
      if (byStart != 0) return byStart;
      return a.targetId.compareTo(b.targetId);
    });
    return summaries;
  }

  /// D-131: every summary carries its session, so none outlives it.
  Future<void> _deleteSensorSummariesForSession(String sessionId) async {
    final keys = <dynamic>[];
    for (final entry in _sensorSummariesBox.toMap().entries) {
      if (_asStringMap(entry.value)['session_id'] == sessionId) {
        keys.add(entry.key);
      }
    }
    await _sensorSummariesBox.deleteAll(keys);
  }

  /// D-131: a summary is deleted together with its target. Removes every
  /// summary of [scope] whose target is one of [targetIds].
  Future<void> _deleteSensorSummariesTargeting(
    String scope,
    Iterable<String> targetIds,
  ) async {
    final targets = targetIds.toSet();
    if (targets.isEmpty) return;
    final keys = <dynamic>[];
    for (final entry in _sensorSummariesBox.toMap().entries) {
      final raw = _asStringMap(entry.value);
      if (raw['scope'] == scope && targets.contains(raw['target_id'])) {
        keys.add(entry.key);
      }
    }
    await _sensorSummariesBox.deleteAll(keys);
  }
}
