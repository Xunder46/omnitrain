import '../models/models.dart';
import '../../mock/seed_data.dart';
import '../../core/constants/modality_config.dart';
import '../../core/constants/modality.dart';
import 'workout_repository.dart';

/// In-memory mock implementation of WorkoutRepository for development/testing.
/// Uses in-memory data and loads from mock/seed_data.dart.
/// Web-compatible (no SQLite / platform APIs).
class MockWorkoutRepository implements WorkoutRepository {
  final Map<String, Exercise> _exercises = {};
  final Map<String, TrainingSession> _sessions = {};
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
  final Map<String, List<String>> _exerciseMuscleGroups = {}; // exerciseId -> List<muscleGroupId>
  final Map<String, List<String>> _exerciseEquipment = {}; // exerciseId -> List<equipmentId>
  final Map<String, List<String>> _exerciseTags = {}; // exerciseId -> List<tagId>
  final Map<String, List<String>> _metricEffortKinds = {}; // metricId -> List<effortKind>
  final Map<String, List<String>> _exerciseCapabilities = {}; // exerciseId -> List<capability>

  bool _initialized = false;

  /// Initializes the repository with seed data from mock/seed_data.dart
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

    // Load templates
    for (final template in SeedData.sampleTemplates) {
      _templates[template.id] = template;
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

    _initialized = true;
  }

  // ===== EXERCISES =====

  @override
  Future<List<Exercise>> getExercises() async {
    return _exercises.values.where((e) => !e.isArchived).toList();
  }

  @override
  Future<Exercise?> getExerciseById(String id) async {
    return _exercises[id];
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
        final descMatch = e.description?.toLowerCase().contains(lowerSearch) ?? false;
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
  Future<String> createSession(TrainingSession session) async {
    _sessions[session.id] = session;
    return session.id;
  }

  @override
  Future<void> updateSession(TrainingSession session) async {
    _sessions[session.id] = session;
  }

  // ===== SEGMENTS =====

  @override
  Future<List<SessionSegment>> getSessionSegments(String sessionId) async {
    return _segments.values
        .where((s) => s.sessionId == sessionId)
        .toList()
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
    return _efforts.values
        .where((e) => e.segmentId == segmentId)
        .toList()
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
    // Then remove the effort itself
    _efforts.remove(id);
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
    return _sportCategories.values.firstWhere(
      (c) => c.key == key,
      orElse: () => SportCategory(
        id: '',
        key: key,
        name: '',
        createdAtMs: 0,
        updatedAtMs: 0,
      ),
    ).id.isEmpty
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
  Future<List<MetricDefinition>> getMetricsForEffortKind(String effortKind) async {
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
  Future<void> setExerciseCapabilities(String exerciseId, List<String> capabilities) async {
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
        final descMatch = e.description?.toLowerCase().contains(lowerSearch) ?? false;
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

    // For modalities that map to multiple categories (e.g., sports = martial arts + sports),
    // filter exercises to match the relevant categories
    if (modality != null) {
      final categoryIds = Modality.modalityToCategoryIds[modality];
      if (categoryIds != null && categoryIds.isNotEmpty) {
        results = results.where((e) {
          if (e.disciplineId == null) return false;
          final discipline = _disciplines[e.disciplineId];
          return discipline != null && categoryIds.contains(discipline.categoryId);
        });
      }
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

    // Return only the exercises (scores were for ranking, UI will partition at threshold)
    return scoredExercises.map((e) => e.$1).toList();
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
  Future<List<TemplateSegment>> getTemplateSegments(String templateId) async {
    return _templateSegments.values
        .where((s) => s.templateId == templateId)
        .toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
  }

  @override
  Future<List<TemplateEffort>> getTemplateEfforts(String templateSegmentId) async {
    return _templateEfforts.values
        .where((e) => e.templateSegmentId == templateSegmentId)
        .toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
  }

  @override
  Future<List<TemplateTarget>> getTemplateTargets(String templateEffortId) async {
    return _templateTargets.values
        .where((t) => t.templateEffortId == templateEffortId)
        .toList();
  }

  // ===== UTILITY METHODS =====

  /// Clears all data (useful for testing)
  void clear() {
    _exercises.clear();
    _sessions.clear();
    _segments.clear();
    _efforts.clear();
    _observations.clear();
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
    _initialized = false;
  }

  /// Resets to seed data only
  Future<void> reset() async {
    clear();
    await initialize();
  }
}
