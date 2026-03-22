import '../models/models.dart';
import '../../mock/seed_data.dart';
import '../../core/constants/modality_config.dart';
import '../../core/utils/exercise_helpers.dart';
import 'workout_repository.dart';

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
  final Map<String, bool> _prefs = {};

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

    // Filter by search text (case-insensitive, matches name or description)
    if (searchText != null && searchText.isNotEmpty) {
      final lowerSearch = searchText.toLowerCase();
      results = results.where((e) {
        final nameMatch = e.name.toLowerCase().contains(lowerSearch);
        final descMatch =
            e.description?.toLowerCase().contains(lowerSearch) ?? false;
        return nameMatch || descMatch;
      });
    }

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
      _efforts.remove(effortId);
    }

    _segments.removeWhere((_, segment) => segment.sessionId == id);
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
    return _efforts.values.where((e) => e.segmentId == segmentId).toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
  }

  @override
  Future<String> createEffort(SegmentEffort effort) async {
    _efforts[effort.id] = effort;
    return effort.id;
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
    _roundInstances
        .putIfAbsent(instance.effortId, () => [])
        .add(instance);
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
    _timedInstances
        .putIfAbsent(instance.effortId, () => [])
        .add(instance);
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

    // Apply search text filter (case-insensitive, matches name or description)
    if (searchText != null && searchText.isNotEmpty) {
      final lowerSearch = searchText.toLowerCase();
      results = results.where((e) {
        final nameMatch = e.name.toLowerCase().contains(lowerSearch);
        final descMatch =
            e.description?.toLowerCase().contains(lowerSearch) ?? false;
        return nameMatch || descMatch;
      });
    }

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

    final allExercises = results.toList();

    // If no modality, return alphabetically sorted (Free Training mode)
    if (modality == null) {
      allExercises.sort((a, b) => a.name.compareTo(b.name));
      return allExercises.map((e) {
        final caps = _exerciseCapabilities[e.id] ?? [];
        return e.copyWith(capabilities: caps);
      }).toList();
    }

    // Get the modality configuration for ranking
    final modalityConfig = ModalityConfig.forModality(modality);
    if (modalityConfig == null) {
      // Fallback if config not found (shouldn't happen for valid modalities)
      allExercises.sort((a, b) => a.name.compareTo(b.name));
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

    // Sort by score descending, then alphabetically for ties
    scoredExercises.sort((a, b) {
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
    _initialized = false;
  }

  /// Resets to seed data only
  Future<void> reset() async {
    clear();
    await initialize();
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
    _plannedSessions.removeWhere(
      (_, s) => s.routineTemplateId == templateId,
    );
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
  Future<bool> getPreferenceBool(String key, {bool defaultValue = false}) async {
    return _prefs[key] ?? defaultValue;
  }

  @override
  Future<void> setPreferenceBool(String key, bool value) async {
    _prefs[key] = value;
  }
}
