import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../../mock/seed_data.dart';
import '../../mock/food_catalog_seed.dart';
import '../../core/constants/modality_config.dart';
import '../../core/utils/fuzzy_search.dart';
import '../../core/utils/exercise_helpers.dart';
import '../../core/utils/date_utils.dart';
import 'workout_repository.dart';

const _mockUuid = Uuid();

/// In-memory mock implementation of WorkoutRepository for development/testing.
/// Uses in-memory data and loads from mock/seed_data.dart.
/// Web-compatible (no SQLite / platform APIs).
class MockWorkoutRepository implements WorkoutRepository {
  final Map<String, Exercise> _exercises = {};
  final Map<String, TrainingSession> _sessions = {};
  final Map<String, UserProfile> _userProfiles = {};
  final Map<String, BodyMeasurementEntry> _bodyMeasurements = {};
  final Map<String, SessionSegment> _segments = {};
  final Map<String, SegmentEffort> _efforts = {};
  final Map<String, EffortObservation> _observations = {};
  final Map<String, UnitModel> _units = {};
  final Map<String, MetricDefinition> _metrics = {};
  final Map<String, MuscleGroup> _muscleGroups = {};
  final Map<String, Discipline> _disciplines = {};
  final Map<String, SportCategory> _sportCategories = {};
  final Map<String, Equipment> _equipment = {};
  final Map<String, Tag> _tags = {};
  final Map<String, WorkoutTemplate> _templates = {};
  final Map<String, TemplateSegment> _templateSegments = {};
  final Map<String, TemplateEffort> _templateEfforts = {};
  final Map<String, TemplateTarget> _templateTargets = {};

  // Relationship maps
  final Map<String, List<String>> _exerciseMuscleGroups =
      {}; // exerciseId -> List<muscleGroupId>
  final Map<String, List<String>> _exerciseEquipment =
      {}; // exerciseId -> List<equipmentId>
  final Map<String, List<String>> _exerciseTags =
      {}; // exerciseId -> List<tagId>
  final Map<String, List<String>> _metricEffortKinds =
      {}; // metricId -> List<effortKind>
  final Map<String, List<String>> _exerciseCapabilities =
      {}; // exerciseId -> List<capability>

  // Round instances: effortId -> List<RoundInstance> (ordered by roundIndex)
  // Stores the full lifecycle of each timed round for effortKind == 'round' efforts.
  final Map<String, List<RoundInstance>> _roundInstances = {};

  // Timed instances: effortId -> List<TimedInstance> (ordered by entryIndex)
  // Stores the full lifecycle of each timed/drill entry duration.
  final Map<String, List<TimedInstance>> _timedInstances = {};

  // Entry rests: effortId -> List<EntryRest> (ordered by entryIndex)
  // Wall-clock rest periods between consecutive sets/rounds for all effort kinds.
  final Map<String, List<EntryRest>> _entryRests = {};

  // Calendar: planned sessions and training periods
  final Map<String, PlannedSession> _plannedSessions = {};
  final Map<String, TrainingPeriod> _periods = {};
  final Map<String, ExerciseNote> _exerciseNotes = {};
  final Map<String, SessionBlock> _sessionBlocks = {};
  final Map<String, bool> _boolPrefs = {};
  final Map<String, String> _stringPrefs = {};

  // Food library: maps for FoodGroup and Food
  final Map<String, FoodGroup> _foodGroups = {};
  final Map<String, Food> _foods = {};

  // Food catalog: read-only bundled foods (separate from user library)
  final Map<String, Food> _catalogFoods = {};

  // Day nutrition log: consumed foods per day (frozen snapshots)
  final Map<String, ConsumedFood> _consumedFoods = {};

  // Date-keyed nutrition targets: dateMs (as int) -> NutritionTarget
  // Supports day-based targets with backward walkback and forward propagation
  final Map<int, NutritionTarget> _nutritionTargetsByDate = {};

  bool _initialized = false;

  /// Initializes the repository with seed data from mock/seed_data.dart
  @override
  Future<void> initialize() async {
    if (_initialized) return;

    // Load sport categories
    for (final category in SeedData.sampleSportCategories) {
      _sportCategories[category.id] = category;
    }

    // Load disciplines
    for (final discipline in SeedData.sampleDisciplines) {
      _disciplines[discipline.id] = discipline;
    }

    // Load exercises
    for (final exercise in SeedData.sampleExercises) {
      _exercises[exercise.id] = exercise;
    }

    // Load muscle groups
    for (final muscleGroup in SeedData.sampleMuscleGroups) {
      _muscleGroups[muscleGroup.id] = muscleGroup;
    }

    // Load equipment
    for (final equip in SeedData.sampleEquipment) {
      _equipment[equip.id] = equip;
    }

    // Load tags
    for (final tag in SeedData.sampleTags) {
      _tags[tag.id] = tag;
    }

    // Load units
    for (final unit in SeedData.defaultUnits) {
      _units[unit.id] = unit;
    }

    // Load metrics
    for (final metric in SeedData.defaultMetrics) {
      _metrics[metric.id] = metric;
    }

    // Load template segments
    for (final segment in SeedData.sampleTemplateSegments) {
      _templateSegments[segment.id] = segment;
    }

    // Load template efforts
    for (final effort in SeedData.sampleTemplateEfforts) {
      _templateEfforts[effort.id] = effort;
    }

    // Load template targets
    for (final target in SeedData.sampleTemplateTargets) {
      _templateTargets[target.id] = target;
    }

    // Load relationships
    for (final entry in SeedData.exerciseMuscleGroupRelationships.entries) {
      _exerciseMuscleGroups[entry.key] = List.from(entry.value);
    }

    for (final entry in SeedData.exerciseEquipmentRelationships.entries) {
      _exerciseEquipment[entry.key] = List.from(entry.value);
    }

    for (final entry in SeedData.exerciseCapabilityRelationships.entries) {
      _exerciseCapabilities[entry.key] = List.from(entry.value);
    }

    // Build metric applicability map
    for (final applicability in SeedData.metricApplicability) {
      _metricEffortKinds
          .putIfAbsent(applicability.metricId, () => [])
          .add(applicability.effortKind);
    }

    // Calendar maps intentionally start empty; users create planned sessions
    // and periods through calendar/period flows.

    // Load the food catalog (read-only bundled foods)
    for (final catalogFood in FoodCatalogSeed.sampleCatalogFoods) {
      _catalogFoods[catalogFood.id] = catalogFood;
    }

    // Load default food group categories (Proteins, Vegetables, …).
    // Mock starts empty so there are no user-created groups to collide with.
    for (final group in SeedData.defaultFoodGroups) {
      _foodGroups[group.id] = group;
    }

    // Seed the now-relative nutrition log so the Stats screen's
    // Nutrition Trend card has data on the web/QA build. These rows
    // are frozen snapshots — once written, editing the source food
    // or targets does not change them.
    for (final consumed in SeedData.sampleConsumedFoods()) {
      _consumedFoods[consumed.id] = consumed;
    }

    // NOTE: SeedData.sampleTrainingSessions/sampleSessionSegments/sampleSessionBlocks/
    // sampleSegmentEfforts are available as reference data but NOT auto-loaded here.
    // Use them to manually populate a demo session when needed.

    _initialized = true;
  }

  // ===== EXERCISES =====

  @override
  Future<List<Exercise>> getExercises() async {
    return _exercises.values.where((e) => !e.isArchived).map((e) {
      final caps = _exerciseCapabilities[e.id] ?? [];
      return e.copyWith(capabilities: caps);
    }).toList();
  }

  @override
  Future<Exercise?> getExerciseById(String id) async {
    final exercise = _exercises[id];
    if (exercise == null) return null;
    final caps = _exerciseCapabilities[exercise.id] ?? [];
    return exercise.copyWith(capabilities: caps);
  }

  @override
  Future<String> createExercise(Exercise exercise) async {
    _exercises[exercise.id] = exercise;
    return exercise.id;
  }

  @override
  Future<void> updateExercise(Exercise exercise) async {
    _exercises[exercise.id] = exercise;
  }

  @override
  Future<void> deleteExercise(String id) async {
    _exercises.remove(id);
  }

  @override
  Future<List<Exercise>> searchExercises({
    String? searchText,
    String? disciplineId,
    List<String>? muscleGroupIds,
  }) async {
    var results = _exercises.values.where((e) => !e.isArchived);

    // Filter by discipline
    if (disciplineId != null && disciplineId.isNotEmpty) {
      results = results.where((e) => e.disciplineId == disciplineId);
    }

    // Filter by muscle groups (exercise must have at least one of the specified muscle groups)
    if (muscleGroupIds != null && muscleGroupIds.isNotEmpty) {
      results = results.where((e) {
        final exerciseMuscles = _exerciseMuscleGroups[e.id] ?? [];
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
    return _sessions[id];
  }

  @override
  Future<List<TrainingSession>> getAllSessions() async {
    final sessions = _sessions.values.toList();
    sessions.sort((a, b) => b.startedAtMs.compareTo(a.startedAtMs));
    return sessions;
  }

  @override
  Future<List<TrainingSession>> getSessionsByDateRange(
    int fromMs,
    int toMs,
  ) async {
    final sessions = _sessions.values
        .where((s) => s.startedAtMs >= fromMs && s.startedAtMs <= toMs)
        .toList();
    sessions.sort((a, b) => a.startedAtMs.compareTo(b.startedAtMs));
    return sessions;
  }

  @override
  Future<List<TrainingSession>> getInProgressSessions() async {
    final inProgressSessions = _sessions.values
        .where((session) => session.endedAtMs == null)
        .toList();
    inProgressSessions.sort((a, b) => b.startedAtMs.compareTo(a.startedAtMs));
    return inProgressSessions;
  }

  @override
  Future<double?> getPersonalRecordCandidates(
    String exerciseId, {
    String? metricId,
  }) async {
    final segmentSessionIds = <String, String>{
      for (final segment in _segments.values) segment.id: segment.sessionId,
    };

    final validEffortIds = <String>{};
    for (final effort in _efforts.values) {
      if (effort.exerciseId != exerciseId) continue;
      final sessionId = segmentSessionIds[effort.segmentId];
      if (sessionId == null) continue;
      final session = _sessions[sessionId];
      if (session == null || session.endedAtMs == null) continue;
      validEffortIds.add(effort.id);
    }

    double? best;
    for (final observation in _observations.values) {
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
    _sessions[session.id] = session;
    return session.id;
  }

  @override
  Future<void> updateSession(TrainingSession session) async {
    _sessions[session.id] = session;
  }

  @override
  Future<void> updateSessionFeeling(String sessionId, int feeling) async {
    final existing = _sessions[sessionId];
    if (existing == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    _sessions[sessionId] = TrainingSession(
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
  }

  @override
  Future<void> deleteSession(String id) async {
    final segmentIds = _segments.values
        .where((s) => s.sessionId == id)
        .map((s) => s.id)
        .toList();

    final effortIds = _efforts.values
        .where((e) => segmentIds.contains(e.segmentId))
        .map((e) => e.id)
        .toList();

    for (final effortId in effortIds) {
      _observations.removeWhere((_, obs) => obs.effortId == effortId);
      _roundInstances.remove(effortId);
      _timedInstances.remove(effortId);
      _entryRests.remove(effortId);
      _efforts.remove(effortId);
    }

    _segments.removeWhere((_, segment) => segment.sessionId == id);
    _sessionBlocks.removeWhere((_, block) => block.sessionId == id);
    _sessions.remove(id);
  }

  // ===== PROFILE =====

  @override
  Future<UserProfile?> getProfile() async {
    if (_userProfiles.containsKey('local-user')) {
      return _userProfiles['local-user'];
    }
    if (_userProfiles.isEmpty) return null;
    return _userProfiles.values.first;
  }

  @override
  Future<void> saveProfile(UserProfile profile) async {
    _userProfiles[profile.id] = profile;
  }

  @override
  Future<List<BodyMeasurementEntry>> getMeasurementHistory(
    String measurementType,
  ) async {
    final entries = _bodyMeasurements.values
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
    _bodyMeasurements[entry.id] = entry;
  }

  @override
  Future<void> deleteMeasurementEntry(String entryId) async {
    _bodyMeasurements.remove(entryId);
  }

  // ===== SEGMENTS =====

  @override
  Future<List<SessionSegment>> getSessionSegments(String sessionId) async {
    return _segments.values.where((s) => s.sessionId == sessionId).toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
  }

  @override
  Future<String> createSegment(SessionSegment segment) async {
    _segments[segment.id] = segment;
    return segment.id;
  }

  // ===== EFFORTS =====

  @override
  Future<List<SegmentEffort>> getSegmentEfforts(String segmentId) async {
    final efforts = _efforts.values
        .where((e) => e.segmentId == segmentId)
        .toList();
    efforts.sort((a, b) {
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
    });
    return efforts;
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

    _efforts[normalized.id] = normalized;
    return normalized.id;
  }

  // ===== OBSERVATIONS =====

  @override
  Future<List<EffortObservation>> getEffortObservations(String effortId) async {
    return _observations.values.where((o) => o.effortId == effortId).toList();
  }

  @override
  Future<String> createObservation(EffortObservation observation) async {
    _observations[observation.id] = observation;
    return observation.id;
  }

  @override
  Future<void> updateObservation(EffortObservation observation) async {
    _observations[observation.id] = observation;
  }

  @override
  Future<void> deleteObservation(String id) async {
    _observations.remove(id);
  }

  @override
  Future<void> deleteObservationsForEffort(String effortId) async {
    // Remove all observations for the given effort
    _observations.removeWhere((id, obs) => obs.effortId == effortId);
  }

  // ===== EFFORTS (additional) =====

  @override
  Future<void> deleteEffort(String id) async {
    // First delete all observations for this effort
    await deleteObservationsForEffort(id);
    // Delete all round instances for this effort
    await deleteRoundInstancesForEffort(id);
    // Delete all timed instances for this effort
    await deleteTimedInstancesForEffort(id);
    // Delete all entry rest records for this effort
    await deleteEntryRestsForEffort(id);
    // Then remove the effort itself
    _efforts.remove(id);
  }

  // ===== ROUND INSTANCES =====

  @override
  Future<List<RoundInstance>> getRoundInstances(String effortId) async {
    final list = _roundInstances[effortId] ?? [];
    // Return a sorted copy so roundIndex ordering is always guaranteed
    return List<RoundInstance>.from(list)
      ..sort((a, b) => a.roundIndex.compareTo(b.roundIndex));
  }

  @override
  Future<String> createRoundInstance(RoundInstance instance) async {
    _roundInstances.putIfAbsent(instance.effortId, () => []).add(instance);
    return instance.id;
  }

  @override
  Future<void> updateRoundInstance(RoundInstance instance) async {
    final list = _roundInstances[instance.effortId];
    if (list == null) return;
    final idx = list.indexWhere((r) => r.id == instance.id);
    if (idx != -1) list[idx] = instance;
  }

  @override
  Future<void> deleteRoundInstance(String id) async {
    for (final list in _roundInstances.values) {
      list.removeWhere((r) => r.id == id);
    }
  }

  @override
  Future<void> deleteRoundInstancesForEffort(String effortId) async {
    _roundInstances.remove(effortId);
  }

  // ===== TIMED INSTANCES =====

  @override
  Future<List<TimedInstance>> getTimedInstances(String effortId) async {
    final list = _timedInstances[effortId] ?? [];
    // Return a sorted copy so entryIndex ordering is always guaranteed
    return List<TimedInstance>.from(list)
      ..sort((a, b) => a.entryIndex.compareTo(b.entryIndex));
  }

  @override
  Future<String> createTimedInstance(TimedInstance instance) async {
    _timedInstances.putIfAbsent(instance.effortId, () => []).add(instance);
    return instance.id;
  }

  @override
  Future<void> updateTimedInstance(TimedInstance instance) async {
    final list = _timedInstances[instance.effortId];
    if (list == null) return;
    final idx = list.indexWhere((t) => t.id == instance.id);
    if (idx != -1) list[idx] = instance;
  }

  @override
  Future<void> deleteTimedInstance(String id) async {
    for (final list in _timedInstances.values) {
      list.removeWhere((t) => t.id == id);
    }
  }

  @override
  Future<void> deleteTimedInstancesForEffort(String effortId) async {
    _timedInstances.remove(effortId);
  }

  // ===== ENTRY RESTS =====

  @override
  Future<List<EntryRest>> getEntryRests(String effortId) async {
    final list = _entryRests[effortId] ?? [];
    return List<EntryRest>.from(list)
      ..sort((a, b) => a.entryIndex.compareTo(b.entryIndex));
  }

  @override
  Future<String> createEntryRest(EntryRest rest) async {
    _entryRests.putIfAbsent(rest.effortId, () => []).add(rest);
    return rest.id;
  }

  @override
  Future<void> updateEntryRest(EntryRest rest) async {
    final list = _entryRests[rest.effortId];
    if (list == null) return;
    final idx = list.indexWhere((r) => r.id == rest.id);
    if (idx != -1) list[idx] = rest;
  }

  @override
  Future<void> deleteEntryRestsForEffort(String effortId) async {
    _entryRests.remove(effortId);
  }

  @override
  Future<Map<String?, List<EntryRest>>> getEntryRestsByModalityInDateRange(
    int fromMs,
    int toMs,
  ) async {
    final result = <String?, List<EntryRest>>{};
    for (final restList in _entryRests.values) {
      for (final rest in restList) {
        if (rest.restEndMs == null) continue;
        if (rest.restStartMs < fromMs || rest.restStartMs > toMs) continue;

        final effort = _efforts[rest.effortId];
        if (effort == null) continue;
        final segment = _segments[effort.segmentId];
        if (segment == null) continue;
        final session = _sessions[segment.sessionId];
        if (session == null) continue;

        final modality = session.modality;

        result.putIfAbsent(modality, () => []).add(rest);
      }
    }
    return result;
  }

  // ===== EXERCISE NOTES =====

  @override
  Future<ExerciseNote?> getExerciseNote(String exerciseId) async {
    return _exerciseNotes[exerciseId];
  }

  @override
  Future<void> saveExerciseNote(ExerciseNote note) async {
    _exerciseNotes[note.exerciseId] = note;
  }

  @override
  Future<void> deleteExerciseNote(String exerciseId) async {
    _exerciseNotes.remove(exerciseId);
  }

  // ===== SPORT CATEGORIES =====

  @override
  Future<List<SportCategory>> getSportCategories() async {
    return _sportCategories.values.toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  @override
  Future<SportCategory?> getSportCategoryById(String id) async {
    return _sportCategories[id];
  }

  @override
  Future<SportCategory?> getSportCategoryByKey(String key) async {
    return _sportCategories.values
            .firstWhere(
              (c) => c.key == key,
              orElse: () => SportCategory(
                id: '',
                key: key,
                name: '',
                createdAtMs: 0,
                updatedAtMs: 0,
              ),
            )
            .id
            .isEmpty
        ? null
        : _sportCategories.values.firstWhere((c) => c.key == key);
  }

  // ===== DISCIPLINES =====

  @override
  Future<List<Discipline>> getDisciplines() async {
    return _disciplines.values.toList();
  }

  @override
  Future<Discipline?> getDisciplineById(String id) async {
    return _disciplines[id];
  }

  @override
  Future<List<Discipline>> getDisciplinesByCategory(String categoryId) async {
    return _disciplines.values
        .where((d) => d.categoryId == categoryId)
        .toList();
  }

  // ===== MUSCLE GROUPS =====

  @override
  Future<List<MuscleGroup>> getMuscleGroups() async {
    return _muscleGroups.values.toList();
  }

  @override
  Future<List<MuscleGroup>> getExerciseMuscleGroups(String exerciseId) async {
    final muscleGroupIds = _exerciseMuscleGroups[exerciseId] ?? [];
    return muscleGroupIds
        .map((id) => _muscleGroups[id])
        .whereType<MuscleGroup>()
        .toList();
  }

  @override
  Future<void> setExerciseMuscleGroups(
    String exerciseId,
    List<String> muscleGroupIds,
  ) async {
    _exerciseMuscleGroups[exerciseId] = List.from(muscleGroupIds);
  }

  // ===== EQUIPMENT =====

  @override
  Future<List<Equipment>> getEquipment() async {
    return _equipment.values.toList();
  }

  @override
  Future<List<Equipment>> getExerciseEquipment(String exerciseId) async {
    final equipmentIds = _exerciseEquipment[exerciseId] ?? [];
    return equipmentIds
        .map((id) => _equipment[id])
        .whereType<Equipment>()
        .toList();
  }

  // ===== TAGS =====

  @override
  Future<List<Tag>> getTags() async {
    return _tags.values.toList();
  }

  @override
  Future<List<Tag>> getExerciseTags(String exerciseId) async {
    final tagIds = _exerciseTags[exerciseId] ?? [];
    return tagIds.map((id) => _tags[id]).whereType<Tag>().toList();
  }

  // ===== UNITS =====

  @override
  Future<List<UnitModel>> getUnits() async {
    return _units.values.toList();
  }

  @override
  Future<UnitModel?> getUnitById(String id) async {
    return _units[id];
  }

  // ===== METRICS =====

  @override
  Future<List<MetricDefinition>> getMetricDefinitions() async {
    return _metrics.values.toList();
  }

  @override
  Future<List<MetricDefinition>> getMetricsForEffortKind(
    String effortKind,
  ) async {
    final metricIds = _metricEffortKinds.entries
        .where((entry) => entry.value.contains(effortKind))
        .map((entry) => entry.key)
        .toList();

    return metricIds
        .map((id) => _metrics[id])
        .whereType<MetricDefinition>()
        .toList();
  }

  // ===== EXERCISE CAPABILITIES =====

  @override
  Future<List<String>> getExerciseCapabilities(String exerciseId) async {
    return _exerciseCapabilities[exerciseId] ?? [];
  }

  @override
  Future<void> setExerciseCapabilities(
    String exerciseId,
    List<String> capabilities,
  ) async {
    _exerciseCapabilities[exerciseId] = List.from(capabilities);
  }

  @override
  Future<List<Exercise>> getExercisesRankedForModality(
    String? modality, {
    String? searchText,
    String? disciplineId,
    List<String>? muscleGroupIds,
  }) async {
    // Start with all non-archived exercises
    var results = _exercises.values.where((e) => !e.isArchived);

    // Filter by discipline
    if (disciplineId != null && disciplineId.isNotEmpty) {
      results = results.where((e) => e.disciplineId == disciplineId);
    }

    // Filter by muscle groups (exercise must have at least one of the specified muscle groups)
    if (muscleGroupIds != null && muscleGroupIds.isNotEmpty) {
      results = results.where((e) {
        final exerciseMuscles = _exerciseMuscleGroups[e.id] ?? [];
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

    // If no modality, return alphabetically sorted (Free Training mode)
    if (modality == null) {
      if (!hasSearchText) {
        allExercises.sort((a, b) => a.name.compareTo(b.name));
      }
      return allExercises.map((e) {
        final caps = _exerciseCapabilities[e.id] ?? [];
        return e.copyWith(capabilities: caps);
      }).toList();
    }

    // Get the modality configuration for ranking
    final modalityConfig = ModalityConfig.forModality(modality);
    if (modalityConfig == null) {
      // Fallback if config not found (shouldn't happen for valid modalities)
      if (!hasSearchText) {
        allExercises.sort((a, b) => a.name.compareTo(b.name));
      }
      return allExercises.map((e) {
        final caps = _exerciseCapabilities[e.id] ?? [];
        return e.copyWith(capabilities: caps);
      }).toList();
    }

    // Score each exercise and attach scores for later partitioning by UI
    final scoredExercises = <(Exercise, double)>[];

    for (final exercise in allExercises) {
      final caps = _exerciseCapabilities[exercise.id] ?? [];
      final exerciseWithCaps = exercise.copyWith(capabilities: caps);

      // Get the exercise's discipline's category for affinity scoring
      String? exerciseCategoryId;
      if (exercise.disciplineId != null) {
        final discipline = _disciplines[exercise.disciplineId];
        exerciseCategoryId = discipline?.categoryId;
      }

      // Calculate relevance score using the modality's scoring algorithm
      final score = modalityConfig.calculateRelevanceScore(
        exerciseCapabilities: caps,
        exerciseCategoryId: exerciseCategoryId,
      );

      scoredExercises.add((exerciseWithCaps, score));
    }

    // Sort by fuzzy score first when searching, then modality relevance.
    scoredExercises.sort((a, b) {
      if (hasSearchText) {
        final fuzzyCompare = (fuzzyScores[a.$1.id] ?? (1 << 30)).compareTo(
          fuzzyScores[b.$1.id] ?? (1 << 30),
        );
        if (fuzzyCompare != 0) return fuzzyCompare;
      }

      final scoreCompare = b.$2.compareTo(a.$2); // Descending score
      if (scoreCompare != 0) return scoreCompare;
      return a.$1.name.compareTo(b.$1.name); // Alphabetical for ties
    });

    // Attach scores to exercises for UI partitioning (Recommended vs Other)
    return scoredExercises
        .map((e) => e.$1.copyWith(relevanceScore: e.$2))
        .toList();
  }

  // ===== METRICS =====

  @override
  Future<MetricDefinition?> getMetricById(String id) async {
    return _metrics[id];
  }

  // ===== TEMPLATES =====

  @override
  Future<List<WorkoutTemplate>> getTemplates() async {
    return _templates.values.toList();
  }

  @override
  Future<WorkoutTemplate?> getTemplateById(String id) async {
    return _templates[id];
  }

  @override
  Future<String> createTemplate(WorkoutTemplate template) async {
    _templates[template.id] = template;
    return template.id;
  }

  @override
  Future<void> updateTemplate(WorkoutTemplate template) async {
    _templates[template.id] = template;
  }

  @override
  Future<void> deleteTemplate(String id) async {
    final segmentIds = _templateSegments.values
        .where((segment) => segment.templateId == id)
        .map((segment) => segment.id)
        .toList();

    for (final segmentId in segmentIds) {
      await deleteTemplateSegment(segmentId);
    }

    _templates.remove(id);
  }

  @override
  Future<List<TemplateSegment>> getTemplateSegments(String templateId) async {
    return _templateSegments.values
        .where((s) => s.templateId == templateId)
        .toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
  }

  @override
  Future<String> createTemplateSegment(TemplateSegment segment) async {
    _templateSegments[segment.id] = segment;
    return segment.id;
  }

  @override
  Future<void> updateTemplateSegment(TemplateSegment segment) async {
    _templateSegments[segment.id] = segment;
  }

  @override
  Future<void> deleteTemplateSegment(String id) async {
    final effortIds = _templateEfforts.values
        .where((effort) => effort.templateSegmentId == id)
        .map((effort) => effort.id)
        .toList();

    for (final effortId in effortIds) {
      await deleteTemplateEffort(effortId);
    }

    _templateSegments.remove(id);
  }

  @override
  Future<List<TemplateEffort>> getTemplateEfforts(
    String templateSegmentId,
  ) async {
    return _templateEfforts.values
        .where((e) => e.templateSegmentId == templateSegmentId)
        .toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
  }

  @override
  Future<String> createTemplateEffort(TemplateEffort effort) async {
    _templateEfforts[effort.id] = effort;
    return effort.id;
  }

  @override
  Future<void> updateTemplateEffort(TemplateEffort effort) async {
    _templateEfforts[effort.id] = effort;
  }

  @override
  Future<void> deleteTemplateEffort(String id) async {
    await deleteTemplateTargetsForEffort(id);
    _templateEfforts.remove(id);
  }

  @override
  Future<List<TemplateTarget>> getTemplateTargets(
    String templateEffortId,
  ) async {
    return _templateTargets.values
        .where((t) => t.templateEffortId == templateEffortId)
        .toList();
  }

  @override
  Future<String> createTemplateTarget(TemplateTarget target) async {
    _templateTargets[target.id] = target;
    return target.id;
  }

  @override
  Future<void> updateTemplateTarget(TemplateTarget target) async {
    _templateTargets[target.id] = target;
  }

  @override
  Future<void> deleteTemplateTarget(String id) async {
    _templateTargets.remove(id);
  }

  @override
  Future<void> deleteTemplateTargetsForEffort(String templateEffortId) async {
    _templateTargets.removeWhere(
      (id, target) => target.templateEffortId == templateEffortId,
    );
  }

  // ===== UTILITY METHODS =====

  // ===== FOOD GROUPS =====

  @override
  Future<List<FoodGroup>> getFoodGroups({bool includeArchived = false}) async {
    final groups = _foodGroups.values.toList();
    if (!includeArchived) {
      return groups.where((g) => !g.isArchived).toList();
    }
    return groups;
  }

  @override
  Future<FoodGroup?> getFoodGroupById(String id) async {
    return _foodGroups[id];
  }

  @override
  Future<String> createFoodGroup(FoodGroup group) async {
    _foodGroups[group.id] = group;
    return group.id;
  }

  @override
  Future<void> updateFoodGroup(FoodGroup group) async {
    _foodGroups[group.id] = group;
  }

  @override
  Future<void> archiveFoodGroup(String id) async {
    final existing = _foodGroups[id];
    if (existing == null) return;

    _foodGroups[id] = FoodGroup(
      id: existing.id,
      name: existing.name,
      color: existing.color,
      isArchived: true,
      createdAtMs: existing.createdAtMs,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  Future<void> reassignFoodsToGroup(
    List<String> foodIds,
    String? targetGroupId,
  ) async {
    if (foodIds.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final id in foodIds) {
      final existing = _foods[id];
      if (existing == null) continue;
      _foods[id] = existing.copyWith(groupId: targetGroupId, updatedAtMs: now);
    }
  }

  // ===== FOODS =====

  @override
  Future<List<Food>> getFoods({bool includeArchived = false}) async {
    // Returns only library foods (isCatalog == false)
    var foods = _foods.values.where((f) => !f.isCatalog).toList();
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
    final foods = _foods.values.where((f) => f.groupId == groupId).toList();

    if (!includeArchived) {
      return foods.where((f) => !f.isArchived).toList();
    }
    return foods;
  }

  @override
  Future<Food?> getFoodById(String id) async {
    return _foods[id];
  }

  @override
  Future<List<Food>> searchFoods(
    String query, {
    bool includeArchived = false,
  }) async {
    final lowerQuery = query.toLowerCase();
    final results = _foods.values.where((f) {
      if (!includeArchived && f.isArchived) return false;
      return f.name.toLowerCase().contains(lowerQuery);
    }).toList();

    return results;
  }

  @override
  Future<String> createFood(Food food) async {
    _foods[food.id] = food;
    return food.id;
  }

  @override
  Future<void> updateFood(Food food) async {
    _foods[food.id] = food;
  }

  @override
  Future<void> archiveFood(String id) async {
    final existing = _foods[id];
    if (existing == null) return;

    _foods[id] = existing.copyWith(
      isArchived: true,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  Future<void> removeFood(String id) async {
    // Only remove from the user-owned library (isCatalog = false).
    // Catalog foods are read-only and cannot be removed through this method.
    final existing = _foods[id];
    if (existing == null) return;
    if (existing.isCatalog) return;

    // Hard-delete: remove the row entirely.
    // Past ConsumedFood rows are unaffected because they store a frozen snapshot.
    _foods.remove(id);
  }

  // ===== FOOD CATALOG =====

  @override
  Future<List<Food>> getCatalogFoods({bool includeArchived = false}) async {
    var foods = _catalogFoods.values.toList();
    if (!includeArchived) {
      foods = foods.where((f) => !f.isArchived).toList();
    }
    return foods;
  }

  @override
  Future<Food?> getCatalogFoodById(String id) async {
    return _catalogFoods[id];
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
    _catalogFoods[newId] = newFood;
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
    if (!_catalogFoods.containsKey(food.id)) {
      throw StateError('Catalog food not found: ${food.id}');
    }
    _catalogFoods[food.id] = food.copyWith(updatedAtMs: food.updatedAtMs);
  }

  @override
  Future<void> deleteCatalogFood(String id) async {
    if (!_catalogFoods.containsKey(id)) {
      throw StateError('Catalog food not found: $id');
    }
    _catalogFoods.remove(id);
  }

  @override
  Future<String> addCatalogFoodToLibrary(String catalogFoodId) async {
    final catalogFood = _catalogFoods[catalogFoodId];
    if (catalogFood == null) {
      throw Exception('Catalog food not found: $catalogFoodId');
    }

    // Generate a new ID for the library copy
    final now = DateTime.now().millisecondsSinceEpoch;
    final newId = 'food-$now-${DateTime.now().microsecond}';

    // Create a library copy with isCatalog = false
    // copyWith() carries groupId across by default, so the catalog's
    // resolved group_id propagates to the library row.
    final libraryFood = catalogFood.copyWith(
      id: newId,
      isCatalog: false,
      createdAtMs: now,
      updatedAtMs: now,
    );

    _foods[newId] = libraryFood;
    return newId;
  }

  /// Helper method for testing: seed a catalog food directly.
  /// This bypasses the normal catalog storage and is only for test setup.
  @visibleForTesting
  Future<String> seedCatalogFood(Food food) async {
    final catalogFood = food.copyWith(isCatalog: true);
    _catalogFoods[catalogFood.id] = catalogFood;
    return catalogFood.id;
  }

  // ===== CONSUMED FOODS (DAY LOG) =====

  @override
  Future<List<ConsumedFood>> getConsumedFoodsForDate(int dateMs) async {
    return _consumedFoods.values.where((c) => c.dateMs == dateMs).toList();
  }

  @override
  Future<String> createConsumedFood(ConsumedFood entry) async {
    _consumedFoods[entry.id] = entry;
    return entry.id;
  }

  @override
  Future<void> deleteConsumedFood(String id) async {
    _consumedFoods.remove(id);
  }

  @override
  Future<List<ConsumedFood>> getConsumedFoodsInRange(
    int fromMs,
    int toMs,
  ) async {
    return _consumedFoods.values
        .where((c) => c.dateMs >= fromMs && c.dateMs <= toMs)
        .toList();
  }

  @override
  Future<void> updateConsumedFood(ConsumedFood entry) async {
    if (!_consumedFoods.containsKey(entry.id)) {
      throw StateError(
        'updateConsumedFood: no ConsumedFood with id "${entry.id}"',
      );
    }
    _consumedFoods[entry.id] = entry;
  }

  @override
  Future<ConsumedFood?> getConsumedFoodById(String id) async {
    return _consumedFoods[id];
  }

  // ===== WATER LOG (DAY LOG) =====

  /// Per-day water volume map keyed by `dateMs` (local midnight). Stores
  /// the volume in milliliters (not a glass count) so the historical
  /// record stays unit-clean. Absence of a key = 0 ml for that day.
  final Map<int, int> _waterVolumesByDate = {};

  @override
  Future<int> getWaterVolumeForDate(int dateMs) async {
    return _waterVolumesByDate[dateMs] ?? 0;
  }

  @override
  Future<void> saveWaterVolumeForDate(int dateMs, int volumeMl) async {
    // Clamp at 0 — the state layer should already have floored the value,
    // but the repository is the last line of defense against bad inputs.
    final clamped = volumeMl < 0 ? 0 : volumeMl;
    final existing = _waterVolumesByDate[dateMs];
    if (existing == null) {
      // First write for this date — use the date as the created timestamp.
      _waterVolumesByDate[dateMs] = clamped;
    } else {
      _waterVolumesByDate[dateMs] = clamped;
    }
  }

  /// Clears all data (useful for testing)
  void clear() {
    _exercises.clear();
    _sessions.clear();
    _userProfiles.clear();
    _bodyMeasurements.clear();
    _segments.clear();
    _efforts.clear();
    _observations.clear();
    _roundInstances.clear();
    _timedInstances.clear();
    _units.clear();
    _metrics.clear();
    _muscleGroups.clear();
    _disciplines.clear();
    _sportCategories.clear();
    _equipment.clear();
    _tags.clear();
    _templates.clear();
    _templateSegments.clear();
    _templateEfforts.clear();
    _templateTargets.clear();
    _exerciseMuscleGroups.clear();
    _exerciseEquipment.clear();
    _exerciseTags.clear();
    _metricEffortKinds.clear();
    _plannedSessions.clear();
    _periods.clear();
    _foodGroups.clear();
    _foods.clear();
    _catalogFoods.clear();
    _consumedFoods.clear();
    _waterVolumesByDate.clear();
    _initialized = false;
  }

  /// Resets to seed data only
  Future<void> reset() async {
    clear();
    await initialize();
  }

  /// Test-only hook: clears the seeded consumed-foods map so a test can
  /// start with an empty day-log without losing the rest of the seed
  /// (exercises, foods, etc.). The `sampleConsumedFoods()` seed preloads
  /// three today-dated rows for the Stats Nutrition Trend card; tests
  /// that exercise the per-row scaling or cache-count contract of
  /// `NutritionState.loadConsumedToday` need a clean slate.
  @visibleForTesting
  void clearConsumedFoodsForTest() {
    _consumedFoods.clear();
  }

  // ===== PLANNED SESSIONS =====

  @override
  Future<List<PlannedSession>> getPlannedSessions() async {
    final list = _plannedSessions.values.toList();
    list.sort((a, b) => a.scheduledDateMs.compareTo(b.scheduledDateMs));
    return list;
  }

  @override
  Future<List<PlannedSession>> getPlannedSessionsForDateRange(
    int fromMs,
    int toMs,
  ) async {
    final list = _plannedSessions.values
        .where((s) => s.scheduledDateMs >= fromMs && s.scheduledDateMs <= toMs)
        .toList();
    list.sort((a, b) => a.scheduledDateMs.compareTo(b.scheduledDateMs));
    return list;
  }

  @override
  Future<String> createPlannedSession(PlannedSession session) async {
    _plannedSessions[session.id] = session;
    return session.id;
  }

  @override
  Future<void> updatePlannedSession(PlannedSession session) async {
    _plannedSessions[session.id] = session;
  }

  @override
  Future<void> deletePlannedSession(String id) async {
    _plannedSessions.remove(id);
  }

  @override
  Future<List<PlannedSession>> getPlannedSessionsByTemplateId(
    String templateId,
  ) async {
    return _plannedSessions.values
        .where((s) => s.routineTemplateId == templateId)
        .toList();
  }

  @override
  Future<void> deletePlannedSessionsByTemplateId(String templateId) async {
    _plannedSessions.removeWhere((_, s) => s.routineTemplateId == templateId);
  }

  // ===== TRAINING PERIODS =====

  @override
  Future<List<TrainingPeriod>> getPeriods() async {
    final list = _periods.values.toList();
    list.sort((a, b) => a.startDateMs.compareTo(b.startDateMs));
    return list;
  }

  @override
  Future<TrainingPeriod?> getPeriodById(String id) async {
    return _periods[id];
  }

  @override
  Future<String> createPeriod(TrainingPeriod period) async {
    _periods[period.id] = period;
    return period.id;
  }

  @override
  Future<void> updatePeriod(TrainingPeriod period) async {
    _periods[period.id] = period;
  }

  @override
  Future<void> deletePeriod(String id) async {
    _periods.remove(id);
  }

  @override
  Future<bool> hasPeriodOverlap(
    int startMs,
    int endMs, {
    String? excludeId,
  }) async {
    return _periods.values.any((p) {
      if (p.id == excludeId) return false;
      return startMs <= p.endDateMs && endMs >= p.startDateMs;
    });
  }

  @override
  Future<bool> getPreferenceBool(
    String key, {
    bool defaultValue = false,
  }) async {
    return _boolPrefs[key] ?? defaultValue;
  }

  @override
  Future<void> setPreferenceBool(String key, bool value) async {
    _boolPrefs[key] = value;
  }

  @override
  Future<String?> getPreferenceString(
    String key, {
    String? defaultValue,
  }) async {
    return _stringPrefs[key] ?? defaultValue;
  }

  @override
  Future<void> setPreferenceString(String key, String value) async {
    _stringPrefs[key] = value;
  }

  // ===== NUTRITION =====

  @override
  Future<NutritionTarget?> getNutritionTargetForDate(int dateMs) async {
    // Check if target exists for this exact date
    if (_nutritionTargetsByDate.containsKey(dateMs)) {
      return _nutritionTargetsByDate[dateMs];
    }

    // Walk backward to find the most recent ancestor target
    int searchDateMs = dateMs - (24 * 60 * 60 * 1000); // Start 1 day before
    while (searchDateMs > 0) {
      if (_nutritionTargetsByDate.containsKey(searchDateMs)) {
        final ancestorTarget = _nutritionTargetsByDate[searchDateMs]!;
        // Return a copy (rolls over to the requested date)
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
    // Fetch the old target (if it exists) to compare for forward propagation
    final oldTarget = _nutritionTargetsByDate[dateMs];

    // Save the new target for this date
    final targetToSave = target.copyWith(dateMs: dateMs);
    _nutritionTargetsByDate[dateMs] = targetToSave;

    // Forward propagation: update future dates that had the old values
    if (oldTarget != null) {
      final sortedFutureKeys =
          _nutritionTargetsByDate.keys.where((k) => k > dateMs).toList()
            ..sort();

      for (final futureKey in sortedFutureKeys) {
        final futureTarget = _nutritionTargetsByDate[futureKey];
        if (futureTarget != null) {
          // Only update if the future target is identical to the old one
          if (futureTarget.calories == oldTarget.calories &&
              futureTarget.protein == oldTarget.protein &&
              futureTarget.carbs == oldTarget.carbs &&
              futureTarget.fat == oldTarget.fat) {
            // Update to the new values, preserving the future date
            final updated = target.copyWith(dateMs: futureKey);
            _nutritionTargetsByDate[futureKey] = updated;
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

  // ===== SESSION BLOCKS =====

  @override
  Future<List<SessionBlock>> getSessionBlocks(String sessionId) async {
    final blocks = _sessionBlocks.values
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
    _sessionBlocks[normalized.id] = normalized;
    return normalized.id;
  }

  @override
  Future<void> updateSessionBlock(SessionBlock block) async {
    _sessionBlocks[block.id] = block;
  }

  @override
  Future<void> deleteSessionBlock(String blockId) async {
    // 1. Find all efforts linked to this block
    final linkedEffortIds = _efforts.entries
        .where((e) => e.value.blockId == blockId)
        .map((e) => e.key)
        .toList();

    // 2. For each linked effort, cascade-delete sub-records then the effort itself
    for (final effortId in linkedEffortIds) {
      _observations.removeWhere((_, obs) => obs.effortId == effortId);
      _roundInstances.remove(effortId);
      _timedInstances.remove(effortId);
      _entryRests.remove(effortId);
      _efforts.remove(effortId);
    }

    // 3. Delete the block itself
    _sessionBlocks.remove(blockId);
  }

  @override
  Future<void> reorderSessionBlocks(
    String sessionId,
    List<String> orderedIds,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < orderedIds.length; i++) {
      final id = orderedIds[i];
      final existing = _sessionBlocks[id];
      if (existing == null) continue;
      if (existing.sessionId != sessionId) continue;
      _sessionBlocks[id] = SessionBlock(
        id: existing.id,
        sessionId: existing.sessionId,
        name: existing.name,
        orderIndex: i,
        topLevelOrderIndex: i,
        createdAtMs: existing.createdAtMs,
        updatedAtMs: now,
      );
    }
  }

  @override
  Future<String> cloneSessionBlock(String blockId) async {
    final original = _sessionBlocks[blockId];
    if (original == null) throw StateError('SessionBlock $blockId not found');

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final name = _formatBlockTimeLabel(nowMs);

    final maxOrder = _sessionBlocks.values
        .where((b) => b.sessionId == original.sessionId)
        .fold<int>(-1, (m, b) => b.orderIndex > m ? b.orderIndex : m);

    final newBlock = SessionBlock(
      id: _mockUuid.v4(),
      sessionId: original.sessionId,
      name: name,
      orderIndex: maxOrder + 1,
      topLevelOrderIndex: _nextTopLevelOrderForSession(original.sessionId),
      createdAtMs: nowMs,
      updatedAtMs: nowMs,
    );
    _sessionBlocks[newBlock.id] = newBlock;

    // Deep-clone all efforts linked to the original block
    final linkedEfforts =
        _efforts.values.where((e) => e.blockId == blockId).toList()
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
      final effort = linkedEfforts[i];
      final newEffortId = _mockUuid.v4();

      _efforts[newEffortId] = SegmentEffort(
        id: newEffortId,
        segmentId: effort.segmentId,
        orderIndex: i,
        topLevelOrderIndex: newBlock.topLevelOrderIndex ?? newBlock.orderIndex,
        blockOrderIndex: i,
        effortKind: effort.effortKind,
        exerciseId: effort.exerciseId,
        note: effort.note,
        blockId: newBlock.id,
        createdAtMs: nowMs,
        updatedAtMs: nowMs,
      );

      // Clone observations — preserve all numeric values from the source
      final observations = _observations.values
          .where((o) => o.effortId == effort.id)
          .toList();
      for (final obs in observations) {
        final newObs = EffortObservation(
          id: _mockUuid.v4(),
          effortId: newEffortId,
          metricId: obs.metricId,
          unitId: obs.unitId,
          valueInt: obs.valueInt,
          valueReal: obs.valueReal,
          valueText: obs.valueText,
          valueBool: obs.valueBool,
          rpeRating: obs.rpeRating,
          restDurationMs: obs.restDurationMs,
          createdAtMs: nowMs,
          updatedAtMs: nowMs,
        );
        _observations[newObs.id] = newObs;
      }

      // Clone round instances with state reset to notStarted
      final rounds = (_roundInstances[effort.id] ?? []);
      for (final r in rounds) {
        final newRound = RoundInstance(
          id: _mockUuid.v4(),
          effortId: newEffortId,
          roundIndex: r.roundIndex,
          plannedDurationSecs: r.plannedDurationSecs,
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
        _roundInstances.putIfAbsent(newEffortId, () => []).add(newRound);
      }

      // Clone timed instances with state reset to notStarted
      final timed = (_timedInstances[effort.id] ?? []);
      for (final t in timed) {
        final newTimed = TimedInstance(
          id: _mockUuid.v4(),
          effortId: newEffortId,
          entryIndex: t.entryIndex,
          targetDurationSecs: t.targetDurationSecs,
          actualDurationSecs: 0,
          startedAtMs: 0,
          finishedAtMs: null,
          state: TimedState.notStarted,
          pausedAtMs: null,
          totalPausedDurationMs: 0,
          createdAtMs: nowMs,
          updatedAtMs: nowMs,
        );
        _timedInstances.putIfAbsent(newEffortId, () => []).add(newTimed);
      }
    }

    return newBlock.id;
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
    final existing = _efforts[effortId];
    if (existing == null) return;

    int topLevelOrderIndex;
    int? blockOrderIndex;
    int orderIndex;

    if (blockId == null) {
      final sessionId = _getSessionIdForSegment(existing.segmentId);
      topLevelOrderIndex =
          existing.topLevelOrderIndex ??
          (sessionId == null
              ? existing.orderIndex
              : _nextTopLevelOrderForSession(sessionId));
      blockOrderIndex = null;
      orderIndex = topLevelOrderIndex;
    } else {
      topLevelOrderIndex = _blockTopLevelOrderOrFallback(
        blockId,
        existing.segmentId,
      );
      blockOrderIndex = _nextBlockOrderIndex(blockId);
      orderIndex = blockOrderIndex;
    }

    _efforts[effortId] = SegmentEffort(
      id: existing.id,
      segmentId: existing.segmentId,
      orderIndex: orderIndex,
      topLevelOrderIndex: topLevelOrderIndex,
      blockOrderIndex: blockOrderIndex,
      effortKind: existing.effortKind,
      exerciseId: existing.exerciseId,
      note: existing.note,
      blockId: blockId,
      createdAtMs: existing.createdAtMs,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  int _effectiveBlockTopLevelOrder(SessionBlock block) =>
      block.topLevelOrderIndex ?? block.orderIndex;

  int _effectiveEffortTopLevelOrder(SegmentEffort effort) =>
      effort.topLevelOrderIndex ?? effort.orderIndex;

  int _effectiveEffortBlockOrder(SegmentEffort effort) =>
      effort.blockOrderIndex ?? effort.orderIndex;

  String? _getSessionIdForSegment(String segmentId) =>
      _segments[segmentId]?.sessionId;

  int _nextTopLevelOrderForSession(String sessionId) {
    var maxOrder = -1;

    for (final block in _sessionBlocks.values) {
      if (block.sessionId != sessionId) continue;
      final order = _effectiveBlockTopLevelOrder(block);
      if (order > maxOrder) maxOrder = order;
    }

    final segmentIds = _segments.values
        .where((segment) => segment.sessionId == sessionId)
        .map((segment) => segment.id)
        .toSet();

    for (final effort in _efforts.values) {
      if (!segmentIds.contains(effort.segmentId)) continue;
      if (effort.blockId != null) continue;
      final order = _effectiveEffortTopLevelOrder(effort);
      if (order > maxOrder) maxOrder = order;
    }

    return maxOrder + 1;
  }

  int _nextBlockOrderIndex(String blockId) {
    var maxOrder = -1;

    for (final effort in _efforts.values) {
      if (effort.blockId != blockId) continue;
      final order = _effectiveEffortBlockOrder(effort);
      if (order > maxOrder) maxOrder = order;
    }

    return maxOrder + 1;
  }

  int _blockTopLevelOrderOrFallback(String blockId, String segmentId) {
    final block = _sessionBlocks[blockId];
    if (block != null) {
      return _effectiveBlockTopLevelOrder(block);
    }

    final sessionId = _getSessionIdForSegment(segmentId);
    if (sessionId == null) return 0;
    return _nextTopLevelOrderForSession(sessionId);
  }
}
