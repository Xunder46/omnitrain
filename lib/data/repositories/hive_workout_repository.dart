import 'package:hive_flutter/hive_flutter.dart';

import '../models/models.dart';
import '../../mock/seed_data.dart';
import '../../core/constants/modality_config.dart';
import '../../core/utils/exercise_helpers.dart';
import 'workout_repository.dart';

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

  // Planned sessions box: key = PlannedSession.id, value = PlannedSession.toMap()
  late Box<Map> _plannedSessionsBox;

  // Training periods box: key = TrainingPeriod.id, value = TrainingPeriod.toMap()
  late Box<Map> _periodsBox;

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

    _roundInstancesBox = await Hive.openBox<Map>('round_instances');

    _timedInstancesBox = await Hive.openBox<Map>('timed_instances');

    _plannedSessionsBox = await Hive.openBox<Map>('planned_sessions');
    _periodsBox = await Hive.openBox<Map>('training_periods');

    _exerciseMuscleGroupsBox = await Hive.openBox<List>(
      'exercise_muscle_groups',
    );
    _exerciseEquipmentBox = await Hive.openBox<List>('exercise_equipment');
    _exerciseTagsBox = await Hive.openBox<List>('exercise_tags');
    _metricEffortKindsBox = await Hive.openBox<List>('metric_effort_kinds');
    _exerciseCapabilitiesBox = await Hive.openBox<List>(
      'exercise_capabilities',
    );

    final seedLoaded = _metaBox.get(_seedLoadedKey) as bool? ?? false;
    if (!seedLoaded) {
      await _seedData();
      await _metaBox.put(_seedLoadedKey, true);
    }

    await _migrateSeedUnits();
    await _migrateExerciseRoundDefaults();
    await _migrateSessionFeelingFields();
    await _seedCalendarData();
    await _purgeCalendarSeedData();

    _initialized = true;
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
    final migrated =
        _metaBox.get(_calendarDataMigrationKey) as bool? ?? false;
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

    if (searchText != null && searchText.isNotEmpty) {
      final lowerSearch = searchText.toLowerCase();
      results = results.where((e) {
        final nameMatch = e.name.toLowerCase().contains(lowerSearch);
        final descMatch =
            e.description?.toLowerCase().contains(lowerSearch) ?? false;
        return nameMatch || descMatch;
      });
    }

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
      createdAtMs: existing.createdAtMs,
      updatedAtMs: now,
    );

    await _sessionsBox.put(sessionId, updated.toMap());
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

    await _observationsBox.deleteAll(observationIds);
    await _effortsBox.deleteAll(effortIds);
    await _segmentsBox.deleteAll(segmentIds);
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

    efforts.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    return efforts;
  }

  @override
  Future<String> createEffort(SegmentEffort effort) async {
    await _effortsBox.put(effort.id, effort.toMap());
    return effort.id;
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
    await _roundInstancesBox.delete(id);
  }

  @override
  Future<void> deleteRoundInstancesForEffort(String effortId) async {
    final idsToDelete = <dynamic>[];
    for (final entry in _roundInstancesBox.toMap().entries) {
      final raw = _asStringMap(entry.value);
      if (raw['effort_id'] == effortId) {
        idsToDelete.add(entry.key);
      }
    }
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
    await _timedInstancesBox.delete(id);
  }

  @override
  Future<void> deleteTimedInstancesForEffort(String effortId) async {
    final idsToDelete = <dynamic>[];
    for (final entry in _timedInstancesBox.toMap().entries) {
      final raw = _asStringMap(entry.value);
      if (raw['effort_id'] == effortId) {
        idsToDelete.add(entry.key);
      }
    }
    await _timedInstancesBox.deleteAll(idsToDelete);
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

    if (searchText != null && searchText.isNotEmpty) {
      final lowerSearch = searchText.toLowerCase();
      results = results.where((e) {
        final nameMatch = e.name.toLowerCase().contains(lowerSearch);
        final descMatch =
            e.description?.toLowerCase().contains(lowerSearch) ?? false;
        return nameMatch || descMatch;
      });
    }

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

    final allExercises = results.toList();

    if (modality == null) {
      allExercises.sort((a, b) => a.name.compareTo(b.name));
      return allExercises
          .map((e) => e.copyWith(capabilities: _getCapabilities(e.id)))
          .toList();
    }

    final modalityConfig = ModalityConfig.forModality(modality);
    if (modalityConfig == null) {
      allExercises.sort((a, b) => a.name.compareTo(b.name));
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
}
