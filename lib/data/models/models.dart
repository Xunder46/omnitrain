import 'dart:convert';

// Data model classes aligned with SQLite schema

class SportCategory {
  final String id;
  final String key;
  final String name;
  final String? description;
  final String? iconName;
  final int sortOrder;
  final int createdAtMs;
  final int updatedAtMs;
  final int? deletedAtMs;

  SportCategory({
    required this.id,
    required this.key,
    required this.name,
    this.description,
    this.iconName,
    this.sortOrder = 0,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.deletedAtMs,
  });

  factory SportCategory.fromMap(Map<String, dynamic> m) => SportCategory(
    id: m['id'] as String,
    key: m['key'] as String,
    name: m['name'] as String,
    description: m['description'] as String?,
    iconName: m['icon_name'] as String?,
    sortOrder: m['sort_order'] as int? ?? 0,
    createdAtMs: m['created_at_ms'] as int,
    updatedAtMs: m['updated_at_ms'] as int,
    deletedAtMs: m['deleted_at_ms'] as int?,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'key': key,
    'name': name,
    'description': description,
    'icon_name': iconName,
    'sort_order': sortOrder,
    'created_at_ms': createdAtMs,
    'updated_at_ms': updatedAtMs,
    'deleted_at_ms': deletedAtMs,
  };
}

class Discipline {
  final String id;
  final String categoryId;
  final String key;
  final String name;
  final int createdAtMs;
  final int updatedAtMs;

  Discipline({
    required this.id,
    required this.categoryId,
    required this.key,
    required this.name,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  factory Discipline.fromMap(Map<String, dynamic> m) => Discipline(
    id: m['id'] as String,
    categoryId: m['category_id'] as String,
    key: m['key'] as String,
    name: m['name'] as String,
    createdAtMs: m['created_at_ms'] as int,
    updatedAtMs: m['updated_at_ms'] as int,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'category_id': categoryId,
    'key': key,
    'name': name,
    'created_at_ms': createdAtMs,
    'updated_at_ms': updatedAtMs,
  };
}

class Exercise {
  final String id;
  final String? ownerUserId;
  final String? modality;
  final String? disciplineId;
  final String name;
  final String? description;
  final String? movementPattern;
  final bool isArchived;
  final int createdAtMs;
  final int updatedAtMs;
  final List<String> capabilities;
  final double?
  relevanceScore; // Transient field: populated only by ranked queries
  /// Sport-specific default duration per round/period (in seconds).
  /// Null = use the app-wide default (WorkoutConstants.defaultRoundDurationSecs = 180).
  /// Only meaningful for effortKind == 'round' exercises (martial arts, sports).
  /// Examples: Soccer Match = 2700 (45-min half), Ice Hockey = 1200 (20-min period).
  final int? defaultRoundDurationSecs;
  final List<String>? howToSteps;
  final String? imageAssetPath;

  Exercise({
    required this.id,
    this.ownerUserId,
    this.modality,
    this.disciplineId,
    required this.name,
    this.description,
    this.movementPattern,
    this.isArchived = false,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.capabilities = const [],
    this.relevanceScore,
    this.defaultRoundDurationSecs,
    this.howToSteps,
    this.imageAssetPath,
  });

  factory Exercise.fromMap(Map<String, dynamic> m) => Exercise(
    id: m['id'] as String,
    ownerUserId: m['owner_user_id'] as String?,
    modality: m['modality'] as String?,
    disciplineId: m['discipline_id'] as String?,
    name: m['name'] as String,
    description: m['description'] as String?,
    movementPattern: m['movement_pattern'] as String?,
    isArchived: (m['is_archived'] as int?) == 1,
    createdAtMs: m['created_at_ms'] as int,
    updatedAtMs: m['updated_at_ms'] as int,
    relevanceScore: m['relevance_score'] as double?,
    defaultRoundDurationSecs: m['default_round_duration_secs'] as int?,
    howToSteps: m['how_to_steps'] != null
      ? List<String>.from(jsonDecode(m['how_to_steps'] as String) as List)
      : null,
    imageAssetPath: m['image_asset_path'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'owner_user_id': ownerUserId,
    'modality': modality,
    'discipline_id': disciplineId,
    'name': name,
    'description': description,
    'movement_pattern': movementPattern,
    'is_archived': isArchived ? 1 : 0,
    'created_at_ms': createdAtMs,
    'updated_at_ms': updatedAtMs,
    'relevance_score': relevanceScore,
    'default_round_duration_secs': defaultRoundDurationSecs,
    'how_to_steps': howToSteps != null ? jsonEncode(howToSteps) : null,
    'image_asset_path': imageAssetPath,
  };
}

// Extension methods (supports, supportsAny, copyWith) are in lib/core/utils/exercise_helpers.dart
// Models remain pure data - no business logic

class Equipment {
  final String id;
  final String name;
  final int createdAtMs;

  Equipment({required this.id, required this.name, required this.createdAtMs});

  factory Equipment.fromMap(Map<String, dynamic> m) => Equipment(
    id: m['id'] as String,
    name: m['name'] as String,
    createdAtMs: m['created_at_ms'] as int,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'created_at_ms': createdAtMs,
  };
}

class TrainingSession {
  final String id;
  final String ownerUserId;
  final String? routineTemplateId;
  final int startedAtMs;
  final int? endedAtMs;
  final String? title;
  final String? note;
  final String? locationText;
  final String? modality;
  final String? intent;
  final double? perceivedSessionRpe;
  final int? sessionFeeling; // 1-5 scale: 1=Rough, 5=Great
  final int? qualityRating; // Reserved for future computed session quality
  final bool isRolling;
  final int createdAtMs;
  final int updatedAtMs;

  TrainingSession({
    required this.id,
    required this.ownerUserId,
    this.routineTemplateId,
    required this.startedAtMs,
    this.endedAtMs,
    this.title,
    this.note,
    this.locationText,
    this.modality,
    this.intent,
    this.perceivedSessionRpe,
    this.sessionFeeling,
    this.qualityRating,
    this.isRolling = false,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  factory TrainingSession.fromMap(Map<String, dynamic> m) => TrainingSession(
    id: m['id'] as String,
    ownerUserId: m['owner_user_id'] as String,
    routineTemplateId: m['routine_template_id'] as String?,
    startedAtMs: m['started_at_ms'] as int,
    endedAtMs: m['ended_at_ms'] as int?,
    title: m['title'] as String?,
    note: m['note'] as String?,
    locationText: m['location_text'] as String?,
    modality: m['modality'] as String?,
    intent: m['intent'] as String?,
    perceivedSessionRpe: (m['perceived_session_rpe'] as num?)?.toDouble(),
    sessionFeeling: m['session_feeling'] as int?,
    qualityRating: m['quality_rating'] as int?,
    isRolling: (m['is_rolling'] as int?) == 1,
    createdAtMs: m['created_at_ms'] as int,
    updatedAtMs: m['updated_at_ms'] as int,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'owner_user_id': ownerUserId,
    'routine_template_id': routineTemplateId,
    'started_at_ms': startedAtMs,
    'ended_at_ms': endedAtMs,
    'title': title,
    'note': note,
    'location_text': locationText,
    'modality': modality,
    'intent': intent,
    'perceived_session_rpe': perceivedSessionRpe,
    'session_feeling': sessionFeeling,
    'quality_rating': qualityRating,
    'is_rolling': isRolling ? 1 : 0,
    'created_at_ms': createdAtMs,
    'updated_at_ms': updatedAtMs,
  };
}

class SessionBlock {
  final String id;
  final String sessionId;
  final String name;
  final int orderIndex;
  final int? topLevelOrderIndex;
  final int createdAtMs;
  final int updatedAtMs;

  SessionBlock({
    required this.id,
    required this.sessionId,
    required this.name,
    required this.orderIndex,
    this.topLevelOrderIndex,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  factory SessionBlock.fromMap(Map<String, dynamic> m) => SessionBlock(
    id: m['id'] as String,
    sessionId: m['session_id'] as String,
    name: m['name'] as String,
    orderIndex: m['order_index'] as int,
    topLevelOrderIndex:
        (m['top_level_order_index'] as int?) ?? (m['order_index'] as int),
    createdAtMs: m['created_at_ms'] as int,
    updatedAtMs: m['updated_at_ms'] as int,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'session_id': sessionId,
    'name': name,
    'order_index': orderIndex,
    'top_level_order_index': topLevelOrderIndex ?? orderIndex,
    'created_at_ms': createdAtMs,
    'updated_at_ms': updatedAtMs,
  };
}

class UserProfile {
  final String id;
  final String? displayName;
  final String? avatarPath;
  final int createdAtMs;

  UserProfile({
    required this.id,
    this.displayName,
    this.avatarPath,
    required this.createdAtMs,
  });

  factory UserProfile.fromMap(Map<String, dynamic> m) => UserProfile(
    id: m['id'] as String,
    displayName: m['display_name'] as String?,
    avatarPath: m['avatar_path'] as String?,
    createdAtMs: m['created_at_ms'] as int,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'display_name': displayName,
    'avatar_path': avatarPath,
    'created_at_ms': createdAtMs,
  };
}

class BodyMeasurementEntry {
  final String id;
  final String measurementType;
  final double value;
  final String unitId;
  final int recordedAtMs;

  BodyMeasurementEntry({
    required this.id,
    required this.measurementType,
    required this.value,
    required this.unitId,
    required this.recordedAtMs,
  });

  factory BodyMeasurementEntry.fromMap(Map<String, dynamic> m) =>
      BodyMeasurementEntry(
        id: m['id'] as String,
        measurementType: m['measurement_type'] as String,
        value: (m['value'] as num).toDouble(),
        unitId: m['unit_id'] as String,
        recordedAtMs: m['recorded_at_ms'] as int,
      );

  Map<String, dynamic> toMap() => {
    'id': id,
    'measurement_type': measurementType,
    'value': value,
    'unit_id': unitId,
    'recorded_at_ms': recordedAtMs,
  };
}

class SessionSegment {
  final String id;
  final String sessionId;
  final int orderIndex;
  final String segmentType;
  final String? disciplineId;
  final String? name;
  final String? note;
  final int createdAtMs;
  final int updatedAtMs;

  SessionSegment({
    required this.id,
    required this.sessionId,
    required this.orderIndex,
    required this.segmentType,
    this.disciplineId,
    this.name,
    this.note,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  factory SessionSegment.fromMap(Map<String, dynamic> m) => SessionSegment(
    id: m['id'] as String,
    sessionId: m['session_id'] as String,
    orderIndex: m['order_index'] as int,
    segmentType: m['segment_type'] as String,
    disciplineId: m['discipline_id'] as String?,
    name: m['name'] as String?,
    note: m['note'] as String?,
    createdAtMs: m['created_at_ms'] as int,
    updatedAtMs: m['updated_at_ms'] as int,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'session_id': sessionId,
    'order_index': orderIndex,
    'segment_type': segmentType,
    'discipline_id': disciplineId,
    'name': name,
    'note': note,
    'created_at_ms': createdAtMs,
    'updated_at_ms': updatedAtMs,
  };
}

class SegmentEffort {
  final String id;
  final String segmentId;
  final int orderIndex;
  final int? topLevelOrderIndex;
  final int? blockOrderIndex;
  final String effortKind;
  final String? exerciseId;
  final String? note;
  final String? blockId;
  final int createdAtMs;
  final int updatedAtMs;

  SegmentEffort({
    required this.id,
    required this.segmentId,
    required this.orderIndex,
    this.topLevelOrderIndex,
    this.blockOrderIndex,
    required this.effortKind,
    this.exerciseId,
    this.note,
    this.blockId,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  factory SegmentEffort.fromMap(Map<String, dynamic> m) => SegmentEffort(
    id: m['id'] as String,
    segmentId: m['segment_id'] as String,
    orderIndex: m['order_index'] as int,
    topLevelOrderIndex:
      (m['top_level_order_index'] as int?) ?? (m['order_index'] as int),
    blockOrderIndex:
      (m['block_order_index'] as int?) ??
      ((m['block_id'] as String?) != null ? m['order_index'] as int : null),
    effortKind: m['effort_kind'] as String,
    exerciseId: m['exercise_id'] as String?,
    note: m['note'] as String?,
    blockId: m['block_id'] as String?,
    createdAtMs: m['created_at_ms'] as int,
    updatedAtMs: m['updated_at_ms'] as int,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'segment_id': segmentId,
    'order_index': orderIndex,
    'top_level_order_index': topLevelOrderIndex ?? orderIndex,
    'block_order_index': blockOrderIndex,
    'effort_kind': effortKind,
    'exercise_id': exerciseId,
    'note': note,
    'block_id': blockId,
    'created_at_ms': createdAtMs,
    'updated_at_ms': updatedAtMs,
  };
}

class UnitModel {
  final String id;
  final String key;
  final String name;
  final String? unitType;
  final int createdAtMs;

  UnitModel({
    required this.id,
    required this.key,
    required this.name,
    this.unitType,
    required this.createdAtMs,
  });

  factory UnitModel.fromMap(Map<String, dynamic> m) => UnitModel(
    id: m['id'] as String,
    key: m['key'] as String,
    name: m['name'] as String,
    unitType: m['unit_type'] as String?,
    createdAtMs: m['created_at_ms'] as int,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'key': key,
    'name': name,
    'unit_type': unitType,
    'created_at_ms': createdAtMs,
  };
}

class MetricDefinition {
  final String id;
  final String key;
  final String name;
  final String dataType;
  final String? defaultUnitId;
  final bool isCore;
  final String? appliesToEffortKind;
  final int createdAtMs;

  MetricDefinition({
    required this.id,
    required this.key,
    required this.name,
    required this.dataType,
    this.defaultUnitId,
    this.isCore = false,
    this.appliesToEffortKind,
    required this.createdAtMs,
  });

  factory MetricDefinition.fromMap(Map<String, dynamic> m) => MetricDefinition(
    id: m['id'] as String,
    key: m['key'] as String,
    name: m['name'] as String,
    dataType: m['data_type'] as String,
    defaultUnitId: m['default_unit_id'] as String?,
    isCore: (m['is_core'] as int?) == 1,
    appliesToEffortKind: m['applies_to_effort_kind'] as String?,
    createdAtMs: m['created_at_ms'] as int,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'key': key,
    'name': name,
    'data_type': dataType,
    'default_unit_id': defaultUnitId,
    'is_core': isCore ? 1 : 0,
    'applies_to_effort_kind': appliesToEffortKind,
    'created_at_ms': createdAtMs,
  };
}

class EffortObservation {
  final String id;
  final String effortId;
  final String metricId;
  final String? unitId;
  final int? valueInt;
  final double? valueReal;
  final String? valueText;
  final bool? valueBool;
  final int? rpeRating; // RPE 1-10 scale, nullable, reserved for future use
  final int? restDurationMs; // Actual rest taken before this set, in ms
  final int createdAtMs;
  final int updatedAtMs;

  EffortObservation({
    required this.id,
    required this.effortId,
    required this.metricId,
    this.unitId,
    this.valueInt,
    this.valueReal,
    this.valueText,
    this.valueBool,
    this.rpeRating,
    this.restDurationMs,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  factory EffortObservation.fromMap(Map<String, dynamic> m) =>
      EffortObservation(
        id: m['id'] as String,
        effortId: m['effort_id'] as String,
        metricId: m['metric_id'] as String,
        unitId: m['unit_id'] as String?,
        valueInt: m['value_int'] as int?,
        valueReal: (m['value_real'] as num?)?.toDouble(),
        valueText: m['value_text'] as String?,
        valueBool: (m['value_bool'] as int?) == 1,
        rpeRating: m['rpe_rating'] as int?,
        restDurationMs: m['rest_duration_ms'] as int?,
        createdAtMs: m['created_at_ms'] as int,
        updatedAtMs: m['updated_at_ms'] as int,
      );

  Map<String, dynamic> toMap() => {
    'id': id,
    'effort_id': effortId,
    'metric_id': metricId,
    'unit_id': unitId,
    'value_int': valueInt,
    'value_real': valueReal,
    'value_text': valueText,
    'value_bool': valueBool == true ? 1 : 0,
    'rpe_rating': rpeRating,
    'rest_duration_ms': restDurationMs,
    'created_at_ms': createdAtMs,
    'updated_at_ms': updatedAtMs,
  };
}

class WorkoutTemplate {
  final String id;
  final String? ownerUserId;
  final String name;
  final String? description;
  final String? focusModality;
  final String? primaryDisciplineId;
  final String? note;
  final int createdAtMs;
  final int updatedAtMs;

  WorkoutTemplate({
    required this.id,
    this.ownerUserId,
    required this.name,
    this.description,
    this.focusModality,
    this.primaryDisciplineId,
    this.note,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  factory WorkoutTemplate.fromMap(Map<String, dynamic> m) => WorkoutTemplate(
    id: m['id'] as String,
    ownerUserId: m['owner_user_id'] as String?,
    name: m['name'] as String,
    description: m['description'] as String?,
    focusModality: m['focus_modality'] as String?,
    primaryDisciplineId: m['primary_discipline_id'] as String?,
    note: m['note'] as String?,
    createdAtMs: m['created_at_ms'] as int,
    updatedAtMs: m['updated_at_ms'] as int,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'owner_user_id': ownerUserId,
    'name': name,
    'description': description,
    'focus_modality': focusModality,
    'primary_discipline_id': primaryDisciplineId,
    'note': note,
    'created_at_ms': createdAtMs,
    'updated_at_ms': updatedAtMs,
  };
}

class TemplateSegment {
  final String id;
  final String templateId;
  final int orderIndex;
  final String segmentType;
  final String? disciplineId;
  final String? name;
  final String? note;
  final int createdAtMs;
  final int updatedAtMs;

  TemplateSegment({
    required this.id,
    required this.templateId,
    required this.orderIndex,
    required this.segmentType,
    this.disciplineId,
    this.name,
    this.note,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  factory TemplateSegment.fromMap(Map<String, dynamic> m) => TemplateSegment(
    id: m['id'] as String,
    templateId: m['template_id'] as String,
    orderIndex: m['order_index'] as int,
    segmentType: m['segment_type'] as String,
    disciplineId: m['discipline_id'] as String?,
    name: m['name'] as String?,
    note: m['note'] as String?,
    createdAtMs: m['created_at_ms'] as int,
    updatedAtMs: (m['updated_at_ms'] as int?) ?? (m['created_at_ms'] as int),
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'template_id': templateId,
    'order_index': orderIndex,
    'segment_type': segmentType,
    'discipline_id': disciplineId,
    'name': name,
    'note': note,
    'created_at_ms': createdAtMs,
    'updated_at_ms': updatedAtMs,
  };
}

class TemplateEffort {
  final String id;
  final String templateSegmentId;
  final int orderIndex;
  final String effortKind;
  final String? modality;
  final String? exerciseId;
  final String? note;
  final int? restSeconds;
  final String? restType;
  final int createdAtMs;

  TemplateEffort({
    required this.id,
    required this.templateSegmentId,
    required this.orderIndex,
    required this.effortKind,
    this.modality,
    this.exerciseId,
    this.note,
    this.restSeconds,
    this.restType,
    required this.createdAtMs,
  });

  factory TemplateEffort.fromMap(Map<String, dynamic> m) => TemplateEffort(
    id: m['id'] as String,
    templateSegmentId: m['template_segment_id'] as String,
    orderIndex: m['order_index'] as int,
    effortKind: m['effort_kind'] as String,
    modality: m['modality'] as String?,
    exerciseId: m['exercise_id'] as String?,
    note: m['note'] as String?,
    restSeconds: m['rest_seconds'] as int?,
    restType: m['rest_type'] as String?,
    createdAtMs: m['created_at_ms'] as int,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'template_segment_id': templateSegmentId,
    'order_index': orderIndex,
    'effort_kind': effortKind,
    'modality': modality,
    'exercise_id': exerciseId,
    'note': note,
    'rest_seconds': restSeconds,
    'rest_type': restType,
    'created_at_ms': createdAtMs,
  };
}

class TemplateTarget {
  final String id;
  final String templateEffortId;
  final String metricId;
  final int? setIndex;
  final String? unitId;
  final double? targetMin;
  final double? targetMax;
  final int? targetInt;
  final String? targetText;
  final int createdAtMs;
  final int updatedAtMs;

  TemplateTarget({
    required this.id,
    required this.templateEffortId,
    required this.metricId,
    this.setIndex,
    this.unitId,
    this.targetMin,
    this.targetMax,
    this.targetInt,
    this.targetText,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  factory TemplateTarget.fromMap(Map<String, dynamic> m) => TemplateTarget(
    id: m['id'] as String,
    templateEffortId: m['template_effort_id'] as String,
    metricId: m['metric_id'] as String,
    setIndex: m['set_index'] as int?,
    unitId: m['unit_id'] as String?,
    targetMin: (m['target_min'] as num?)?.toDouble(),
    targetMax: (m['target_max'] as num?)?.toDouble(),
    targetInt: m['target_int'] as int?,
    targetText: m['target_text'] as String?,
    createdAtMs: m['created_at_ms'] as int,
    updatedAtMs: (m['updated_at_ms'] as int?) ?? (m['created_at_ms'] as int),
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'template_effort_id': templateEffortId,
    'metric_id': metricId,
    'set_index': setIndex,
    'unit_id': unitId,
    'target_min': targetMin,
    'target_max': targetMax,
    'target_int': targetInt,
    'target_text': targetText,
    'created_at_ms': createdAtMs,
    'updated_at_ms': updatedAtMs,
  };
}

class Tag {
  final String id;
  final String name;
  final int createdAtMs;

  Tag({required this.id, required this.name, required this.createdAtMs});

  factory Tag.fromMap(Map<String, dynamic> m) => Tag(
    id: m['id'] as String,
    name: m['name'] as String,
    createdAtMs: m['created_at_ms'] as int,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'created_at_ms': createdAtMs,
  };
}

class MuscleGroup {
  final String id;
  final String name;
  final int createdAtMs;

  MuscleGroup({
    required this.id,
    required this.name,
    required this.createdAtMs,
  });

  factory MuscleGroup.fromMap(Map<String, dynamic> m) => MuscleGroup(
    id: m['id'] as String,
    name: m['name'] as String,
    createdAtMs: m['created_at_ms'] as int,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'created_at_ms': createdAtMs,
  };
}

class ExerciseAlias {
  final String id;
  final String exerciseId;
  final String alias;
  final int createdAtMs;

  ExerciseAlias({
    required this.id,
    required this.exerciseId,
    required this.alias,
    required this.createdAtMs,
  });

  factory ExerciseAlias.fromMap(Map<String, dynamic> m) => ExerciseAlias(
    id: m['id'] as String,
    exerciseId: m['exercise_id'] as String,
    alias: m['alias'] as String,
    createdAtMs: m['created_at_ms'] as int,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'exercise_id': exerciseId,
    'alias': alias,
    'created_at_ms': createdAtMs,
  };
}

class MetricApplicability {
  final String metricId;
  final String effortKind;

  MetricApplicability({required this.metricId, required this.effortKind});

  factory MetricApplicability.fromMap(Map<String, dynamic> m) =>
      MetricApplicability(
        metricId: m['metric_id'] as String,
        effortKind: m['effort_kind'] as String,
      );

  Map<String, dynamic> toMap() => {
    'metric_id': metricId,
    'effort_kind': effortKind,
  };
}

// Sentinel used by RoundInstance.copyWith() to distinguish "explicit null" from "not provided"
// for nullable fields (finishedAtMs, pausedAtMs).
const _roundCopyWithUnset = Object();

/// Explicit lifecycle state for a timed round.
///
/// Allowed transitions:
///   NotStarted → Active
///   Active     → Paused
///   Active     → Finished
///   Paused     → Active
///   Paused     → Finished
///
/// Finished is terminal — no further transitions are permitted.
enum RoundState {
  notStarted, // Round created; timer has never been started
  active, // Timer running; countdown in progress
  paused, // Timer paused mid-countdown; pausedAtMs is set
  finished, // Terminal — round completed naturally or ended early
}

/// Represents one timed round within a round-based effort (effortKind == 'round').
///
/// Replaces the old metric-rounds + metric-round-duration observation pair pattern.
/// Each RoundInstance captures the full lifecycle of a single round: planned duration,
/// wall-clock start/finish timestamps, accumulated pause duration, actual elapsed time,
/// explicit state, and completion flag.
///
/// Lifecycle:
///   1. Created:          state = NotStarted, startedAtMs = 0, totalPausedDurationMs = 0
///   2. Started:          state = Active, startedAtMs = now
///   3. Paused:           state = Paused, pausedAtMs = now
///   4. Resumed:          state = Active, totalPausedDurationMs += (now - pausedAtMs), pausedAtMs = null
///   5. Natural finish:   state = Finished, completed = true,
///                        actualDurationSecs = plannedDurationSecs,
///                        finishedAtMs = startedAtMs + (plannedDurationSecs * 1000) + totalPausedDurationMs
///   6. Early finish:     state = Finished, completed = false,
///                        actualDurationSecs = elapsed (derived from timestamps),
///                        finishedAtMs = now
///   7. Session close:    same as early finish (via _persistActiveRounds safety net)
///
/// Rules:
///   - completed is ONLY set to true when the countdown naturally reaches zero.
///   - Finished is terminal — no transitions from Finished are allowed.
///   - elapsed = now - startedAtMs - totalPausedDurationMs (NEVER inferred from stored duration).
///   - Countdown is presentation-only; only elapsed is stored.
///   - Partial rounds are never discarded.
class RoundInstance {
  final String id;
  final String effortId;
  final int roundIndex; // 0-based round number within the effort
  final int
  plannedDurationSecs; // Countdown target; user-configurable (default 180)
  final int
  actualDurationSecs; // Final elapsed time in secs; 0 while in-progress
  final int startedAtMs; // Wall-clock epoch ms; 0 if not yet started
  final int? finishedAtMs; // Wall-clock epoch ms; null if not finished
  final bool completed; // true ONLY if countdown naturally reached zero
  final RoundState state; // Explicit lifecycle state
  final int? pausedAtMs; // Wall-clock epoch ms when paused; null if not paused
  final int
  totalPausedDurationMs; // Accumulated pause time in ms across all pause/resume cycles
  final int createdAtMs;
  final int updatedAtMs;

  RoundInstance({
    required this.id,
    required this.effortId,
    required this.roundIndex,
    this.plannedDurationSecs = 180,
    this.actualDurationSecs = 0,
    this.startedAtMs = 0,
    this.finishedAtMs,
    this.completed = false,
    this.state = RoundState.notStarted,
    this.pausedAtMs,
    this.totalPausedDurationMs = 0,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  /// Parses a RoundState from its persisted name string.
  /// Falls back to inferring state from existing timestamp fields for backward
  /// compatibility with records created before the state column was introduced.
  static RoundState _stateFromMap(Map<String, dynamic> m) {
    final raw = m['state'] as String?;
    if (raw != null && raw.isNotEmpty) {
      for (final s in RoundState.values) {
        if (s.name == raw) return s;
      }
    }
    // Backward-compat inference: no 'state' column in old records
    if (m['finished_at_ms'] != null) return RoundState.finished;
    if ((m['started_at_ms'] as int? ?? 0) > 0) return RoundState.active;
    return RoundState.notStarted;
  }

  factory RoundInstance.fromMap(Map<String, dynamic> m) => RoundInstance(
    id: m['id'] as String,
    effortId: m['effort_id'] as String,
    roundIndex: m['round_index'] as int,
    plannedDurationSecs: m['planned_duration_secs'] as int? ?? 180,
    actualDurationSecs: m['actual_duration_secs'] as int? ?? 0,
    startedAtMs: m['started_at_ms'] as int? ?? 0,
    finishedAtMs: m['finished_at_ms'] as int?,
    completed: (m['completed'] as int?) == 1,
    state: _stateFromMap(m),
    pausedAtMs: m['paused_at_ms'] as int?,
    totalPausedDurationMs: m['total_paused_duration_ms'] as int? ?? 0,
    createdAtMs: m['created_at_ms'] as int,
    updatedAtMs: m['updated_at_ms'] as int,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'effort_id': effortId,
    'round_index': roundIndex,
    'planned_duration_secs': plannedDurationSecs,
    'actual_duration_secs': actualDurationSecs,
    'started_at_ms': startedAtMs,
    'finished_at_ms': finishedAtMs,
    'completed': completed ? 1 : 0,
    'state': state.name,
    'paused_at_ms': pausedAtMs,
    'total_paused_duration_ms': totalPausedDurationMs,
    'created_at_ms': createdAtMs,
    'updated_at_ms': updatedAtMs,
  };

  /// Returns a copy with the specified fields replaced.
  /// For nullable fields [finishedAtMs] and [pausedAtMs], pass the sentinel
  /// [_roundCopyWithUnset] (the default) to preserve the current value, or
  /// pass an explicit [int?] (including null) to override it.
  RoundInstance copyWith({
    String? id,
    String? effortId,
    int? roundIndex,
    int? plannedDurationSecs,
    int? actualDurationSecs,
    int? startedAtMs,
    Object? finishedAtMs = _roundCopyWithUnset,
    bool? completed,
    RoundState? state,
    Object? pausedAtMs = _roundCopyWithUnset,
    int? totalPausedDurationMs,
    int? createdAtMs,
    int? updatedAtMs,
  }) => RoundInstance(
    id: id ?? this.id,
    effortId: effortId ?? this.effortId,
    roundIndex: roundIndex ?? this.roundIndex,
    plannedDurationSecs: plannedDurationSecs ?? this.plannedDurationSecs,
    actualDurationSecs: actualDurationSecs ?? this.actualDurationSecs,
    startedAtMs: startedAtMs ?? this.startedAtMs,
    finishedAtMs: finishedAtMs == _roundCopyWithUnset
        ? this.finishedAtMs
        : finishedAtMs as int?,
    completed: completed ?? this.completed,
    state: state ?? this.state,
    pausedAtMs: pausedAtMs == _roundCopyWithUnset
        ? this.pausedAtMs
        : pausedAtMs as int?,
    totalPausedDurationMs: totalPausedDurationMs ?? this.totalPausedDurationMs,
    createdAtMs: createdAtMs ?? this.createdAtMs,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
  );

  // ─── Computed time helpers ───────────────────────────────────────────────

  /// Elapsed time in milliseconds, derived purely from wall-clock timestamps.
  ///
  ///   NotStarted → 0
  ///   Active     → now - startedAtMs - totalPausedDurationMs
  ///   Paused     → pausedAtMs - startedAtMs - totalPausedDurationMs  (frozen)
  ///   Finished   → actualDurationSecs * 1000  (final stored value)
  ///
  /// Never use this for a Finished round to re-derive time; use [actualDurationSecs].
  int get elapsedMs {
    if (startedAtMs == 0 || state == RoundState.notStarted) return 0;
    if (state == RoundState.finished) return actualDurationSecs * 1000;
    // Use pausedAtMs as the reference point when paused (freezes the value);
    // otherwise use the current wall clock.
    final referenceMs = (state == RoundState.paused && pausedAtMs != null)
        ? pausedAtMs!
        : DateTime.now().millisecondsSinceEpoch;
    return (referenceMs - startedAtMs - totalPausedDurationMs).clamp(
      0,
      plannedDurationSecs * 2000,
    ); // cap at 2× planned as sanity guard
  }

  /// Remaining milliseconds before the countdown completes.
  /// Always 0 for a Finished round.
  int get remainingMs {
    final planned = plannedDurationSecs * 1000;
    return (planned - elapsedMs).clamp(0, planned);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TimedInstance — Wall-clock tracked duration for timed / drill efforts
// ─────────────────────────────────────────────────────────────────────────────

const _timedCopyWithUnset = Object();

/// Explicit lifecycle state for a timed / drill entry.
///
/// Allowed transitions (same rules as RoundState):
///   NotStarted → Active
///   Active     → Paused
///   Active     → Finished
///   Paused     → Active
///   Paused     → Finished
///
/// Finished is terminal — no further transitions are permitted.
enum TimedState {
  notStarted, // Entry created; timer has never been started
  active, // Timer running; counting up
  paused, // Timer paused mid-effort; pausedAtMs is set
  finished, // Terminal — entry completed (naturally or early)
}

/// Represents one timed entry within a timed or drill effort
/// (effortKind == 'timed' or effortKind == 'drill').
///
/// Replaces the old duration EffortObservation for these effort kinds.
/// Each TimedInstance captures the full lifecycle of a single timed entry:
/// wall-clock start/finish timestamps, accumulated pause duration, actual
/// elapsed time, explicit state, and optional target duration for alert/expiry.
///
/// The companion metrics (distance for timed, extra weight for drill) remain as
/// EffortObservation records — only the duration aspect is tracked here.
///
/// Lifecycle:
///   1. Created:          state = NotStarted, startedAtMs = 0, totalPausedDurationMs = 0
///   2. Started:          state = Active, startedAtMs = now
///   3. Paused:           state = Paused, pausedAtMs = now
///   4. Resumed:          state = Active, totalPausedDurationMs += (now - pausedAtMs), pausedAtMs = null
///   5. Finished:         state = Finished, actualDurationSecs = elapsed (derived from timestamps),
///                        finishedAtMs = now
///   6. Session close:    same as finish (via _persistActiveTimedEntries safety net)
///
/// Rules:
///   - Finished is terminal — no transitions from Finished are allowed.
///   - elapsed = now - startedAtMs - totalPausedDurationMs (NEVER inferred from stored duration).
///   - Partial entries are never discarded.
///   - targetDurationSecs == 0 means open-ended (no alert/expiry).
class TimedInstance {
  final String id;
  final String effortId;
  final int entryIndex; // 0-based entry number within the effort
  final int targetDurationSecs; // User-set target; 0 = open-ended (no alert)
  final int actualDurationSecs; // Final elapsed secs; 0 while in-progress
  final int startedAtMs; // Wall-clock epoch ms; 0 if not yet started
  final int? finishedAtMs; // Wall-clock epoch ms; null if not finished
  final TimedState state; // Explicit lifecycle state
  final int? pausedAtMs; // Wall-clock epoch ms when paused; null if not paused
  final int
  totalPausedDurationMs; // Accumulated pause time in ms across all pause/resume cycles
  final int createdAtMs;
  final int updatedAtMs;

  TimedInstance({
    required this.id,
    required this.effortId,
    required this.entryIndex,
    this.targetDurationSecs = 0,
    this.actualDurationSecs = 0,
    this.startedAtMs = 0,
    this.finishedAtMs,
    this.state = TimedState.notStarted,
    this.pausedAtMs,
    this.totalPausedDurationMs = 0,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  /// Parses a TimedState from its persisted name string.
  /// Falls back to inferring state from existing timestamp fields for backward
  /// compatibility with records created before the state column was introduced.
  static TimedState _stateFromMap(Map<String, dynamic> m) {
    final raw = m['state'] as String?;
    if (raw != null && raw.isNotEmpty) {
      for (final s in TimedState.values) {
        if (s.name == raw) return s;
      }
    }
    // Backward-compat inference: no 'state' column in old records
    if (m['finished_at_ms'] != null) return TimedState.finished;
    if ((m['started_at_ms'] as int? ?? 0) > 0) return TimedState.active;
    return TimedState.notStarted;
  }

  factory TimedInstance.fromMap(Map<String, dynamic> m) => TimedInstance(
    id: m['id'] as String,
    effortId: m['effort_id'] as String,
    entryIndex: m['entry_index'] as int,
    targetDurationSecs: m['target_duration_secs'] as int? ?? 0,
    actualDurationSecs: m['actual_duration_secs'] as int? ?? 0,
    startedAtMs: m['started_at_ms'] as int? ?? 0,
    finishedAtMs: m['finished_at_ms'] as int?,
    state: _stateFromMap(m),
    pausedAtMs: m['paused_at_ms'] as int?,
    totalPausedDurationMs: m['total_paused_duration_ms'] as int? ?? 0,
    createdAtMs: m['created_at_ms'] as int,
    updatedAtMs: m['updated_at_ms'] as int,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'effort_id': effortId,
    'entry_index': entryIndex,
    'target_duration_secs': targetDurationSecs,
    'actual_duration_secs': actualDurationSecs,
    'started_at_ms': startedAtMs,
    'finished_at_ms': finishedAtMs,
    'state': state.name,
    'paused_at_ms': pausedAtMs,
    'total_paused_duration_ms': totalPausedDurationMs,
    'created_at_ms': createdAtMs,
    'updated_at_ms': updatedAtMs,
  };

  /// Returns a copy with the specified fields replaced.
  /// For nullable fields [finishedAtMs] and [pausedAtMs], pass the sentinel
  /// [_timedCopyWithUnset] (the default) to preserve the current value, or
  /// pass an explicit [int?] (including null) to override it.
  TimedInstance copyWith({
    String? id,
    String? effortId,
    int? entryIndex,
    int? targetDurationSecs,
    int? actualDurationSecs,
    int? startedAtMs,
    Object? finishedAtMs = _timedCopyWithUnset,
    TimedState? state,
    Object? pausedAtMs = _timedCopyWithUnset,
    int? totalPausedDurationMs,
    int? createdAtMs,
    int? updatedAtMs,
  }) => TimedInstance(
    id: id ?? this.id,
    effortId: effortId ?? this.effortId,
    entryIndex: entryIndex ?? this.entryIndex,
    targetDurationSecs: targetDurationSecs ?? this.targetDurationSecs,
    actualDurationSecs: actualDurationSecs ?? this.actualDurationSecs,
    startedAtMs: startedAtMs ?? this.startedAtMs,
    finishedAtMs: finishedAtMs == _timedCopyWithUnset
        ? this.finishedAtMs
        : finishedAtMs as int?,
    state: state ?? this.state,
    pausedAtMs: pausedAtMs == _timedCopyWithUnset
        ? this.pausedAtMs
        : pausedAtMs as int?,
    totalPausedDurationMs: totalPausedDurationMs ?? this.totalPausedDurationMs,
    createdAtMs: createdAtMs ?? this.createdAtMs,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
  );

  // ─── Computed time helpers ───────────────────────────────────────────────

  /// Elapsed time in milliseconds, derived purely from wall-clock timestamps.
  ///
  ///   NotStarted → 0
  ///   Active     → now - startedAtMs - totalPausedDurationMs
  ///   Paused     → pausedAtMs - startedAtMs - totalPausedDurationMs  (frozen)
  ///   Finished   → actualDurationSecs * 1000  (final stored value)
  ///
  /// Open-ended: no upper clamp (timed/drill count UP, unlike round countdowns).
  int get elapsedMs {
    if (startedAtMs == 0 || state == TimedState.notStarted) return 0;
    if (state == TimedState.finished) return actualDurationSecs * 1000;
    // Use pausedAtMs as the reference point when paused (freezes the value);
    // otherwise use the current wall clock.
    final referenceMs = (state == TimedState.paused && pausedAtMs != null)
        ? pausedAtMs!
        : DateTime.now().millisecondsSinceEpoch;
    return (referenceMs - startedAtMs - totalPausedDurationMs).clamp(
      0,
      86400000,
    ); // cap at 24 hours as sanity guard
  }
}

// UI-specific set data structures moved to lib/core/utils/exercise_helpers.dart
// Models layer reserved for persistence entities only

// ─────────────────────────────────────────────────────────────────────────────
// PlannedSession — Lightweight scheduling record for a future (or past) session
// ─────────────────────────────────────────────────────────────────────────────

/// A lightweight scheduling record for a session intent.
///
/// Unlike [TrainingSession] (which contains segments, efforts and observations),
/// a [PlannedSession] is purely intent data: a date-tagged plan to train.
///
/// When a planned session is actually executed as a workout, [linkedSessionId]
/// may be set to point to the resulting [TrainingSession].
///
/// Recurrence is NOT yet implemented.
/// [recurrenceRule] is reserved for future use; always set it to null for now.
/// Future implementation will likely use an iCalendar-style RRULE string
/// (e.g. "FREQ=WEEKLY;BYDAY=MO,WE,FR") or a custom JSON rule object.
///
/// Calendar indicator rendering:
///   isCompleted = false → outlined circle (planned, not done)
///   isCompleted = true  → filled circle  (completed)
///   Circle colour is derived from [modality] via ModalityColorUtils.
class PlannedSession {
  final String id;
  final String ownerUserId;

  /// Epoch milliseconds representing the intended training day.
  /// Store start-of-day (midnight local time) for reliable day-level grouping.
  final int scheduledDateMs;

  /// Modality key (e.g. 'cardio_endurance', 'resistance_lifting'), or null
  /// for Free Training.
  final String? modality;

  /// Optional short title.
  final String? title;

  /// Optional notes.
  final String? note;

  /// true = session has been completed; false = still planned.
  final bool isCompleted;

  /// Optional FK to a [TrainingSession] created when this plan was executed.
  final String? linkedSessionId;

  /// Optional FK to a [WorkoutTemplate] when this planned session is based on
  /// a custom routine. Null means a free-training planned session (modality only).
  final String? routineTemplateId;

  /// Reserved for future recurrence support. Always null in this implementation.
  final String? recurrenceRule;

  final int createdAtMs;
  final int updatedAtMs;

  PlannedSession({
    required this.id,
    required this.ownerUserId,
    required this.scheduledDateMs,
    this.modality,
    this.title,
    this.note,
    this.isCompleted = false,
    this.linkedSessionId,
    this.routineTemplateId,
    this.recurrenceRule,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  factory PlannedSession.fromMap(Map<String, dynamic> m) => PlannedSession(
    id: m['id'] as String,
    ownerUserId: m['owner_user_id'] as String,
    scheduledDateMs: m['scheduled_date_ms'] as int,
    modality: m['modality'] as String?,
    title: m['title'] as String?,
    note: m['note'] as String?,
    isCompleted: (m['is_completed'] as int?) == 1,
    linkedSessionId: m['linked_session_id'] as String?,
    routineTemplateId: m['routine_template_id'] as String?,
    recurrenceRule: m['recurrence_rule'] as String?,
    createdAtMs: m['created_at_ms'] as int,
    updatedAtMs: m['updated_at_ms'] as int,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'owner_user_id': ownerUserId,
    'scheduled_date_ms': scheduledDateMs,
    'modality': modality,
    'title': title,
    'note': note,
    'is_completed': isCompleted ? 1 : 0,
    'linked_session_id': linkedSessionId,
    'routine_template_id': routineTemplateId,
    'recurrence_rule': recurrenceRule,
    'created_at_ms': createdAtMs,
    'updated_at_ms': updatedAtMs,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// TrainingPeriod — Named date range with optional modality focus
// ─────────────────────────────────────────────────────────────────────────────

/// A named training period with a date range and optional modality focus.
///
/// Periods provide a high-level planning view (e.g. "Competition Prep",
/// "Off-Season Strength Block"). Periods may NOT overlap — the repository
/// enforces the rule:
///   newPeriod.start <= existing.end AND newPeriod.end >= existing.start
///
/// [focusModalities] is a list of modality keys this period targets.
/// An empty list means all modalities / unspecified focus.
///
/// Storage of [focusModalities]:
///   Persisted as a comma-separated string under the 'focus_modalities_csv'
///   map key.  An empty list is stored as an empty string.
///   Example: ['cardio_endurance','resistance_lifting']
///            → 'cardio_endurance,resistance_lifting'
class TrainingPeriod {
  final String id;
  final String? ownerUserId;
  final String name;

  /// Epoch ms representing the first day of the period (midnight local time).
  final int startDateMs;

  /// Epoch ms representing the last day of the period (end-of-day local time).
  final int endDateMs;

  /// Modality keys for the training focus. Empty = all/unspecified.
  final List<String> focusModalities;

  /// Optional free-text notes.
  final String? notes;

  /// Hex color string (e.g. '#4CAF50') used for calendar highlight.
  /// Null means use the default theme accent color.
  final String? colorHex;

  final int createdAtMs;
  final int updatedAtMs;

  TrainingPeriod({
    required this.id,
    this.ownerUserId,
    required this.name,
    required this.startDateMs,
    required this.endDateMs,
    this.focusModalities = const [],
    this.notes,
    this.colorHex,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  factory TrainingPeriod.fromMap(Map<String, dynamic> m) {
    final csv = m['focus_modalities_csv'] as String?;
    final modalities = (csv == null || csv.isEmpty)
        ? <String>[]
        : csv.split(',');
    return TrainingPeriod(
      id: m['id'] as String,
      ownerUserId: m['owner_user_id'] as String?,
      name: m['name'] as String,
      startDateMs: m['start_date_ms'] as int,
      endDateMs: m['end_date_ms'] as int,
      focusModalities: modalities,
      notes: m['notes'] as String?,
      colorHex: m['color_hex'] as String?,
      createdAtMs: m['created_at_ms'] as int,
      updatedAtMs: m['updated_at_ms'] as int,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'owner_user_id': ownerUserId,
    'name': name,
    'start_date_ms': startDateMs,
    'end_date_ms': endDateMs,
    'focus_modalities_csv': focusModalities.join(','),
    'notes': notes,
    'color_hex': colorHex,
    'created_at_ms': createdAtMs,
    'updated_at_ms': updatedAtMs,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// EntryRest — Wall-clock rest record between consecutive sets/rounds/entries
// ─────────────────────────────────────────────────────────────────────────────

/// Records the actual recovery time between consecutive sets for any effort kind
/// (set, round, timed, drill, and any future kinds).
///
/// A record is created with [restEndMs] == null the instant a set/round is logged
/// ([rest_start_ms] = wall-clock epoch ms at that moment). It is closed —
/// [restEndMs] set to the current wall-clock time — when the athlete actively
/// begins the next set/round/timer.
///
/// Because all times are wall-clock epoch milliseconds, rest durations survive
/// app backgrounding, device restarts, and navigation. The UI derives the
/// display value from `now - restStartMs` without a Stopwatch.
///
/// [entryIndex] is 0-based and identifies the set/round that this rest
/// *precedes* (i.e., the set the athlete is currently resting before).
///
/// Pure Dart — no Flutter imports.
class EntryRest {
  final String id;         // 'rest-{effortId}-{entryIndex}'
  final String effortId;
  final int entryIndex;    // 0-based; this rest precedes this set/round
  final int restStartMs;  // wall-clock epoch ms when previous set was logged
  final int? restEndMs;   // wall-clock epoch ms when this set/round began; null = still resting
  final int createdAtMs;
  final int updatedAtMs;

  const EntryRest({
    required this.id,
    required this.effortId,
    required this.entryIndex,
    required this.restStartMs,
    this.restEndMs,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  /// Elapsed rest in whole seconds. Live (unbounded) while [restEndMs] is null.
  int elapsedSeconds(int nowMs) =>
      (((restEndMs ?? nowMs) - restStartMs) / 1000).round().clamp(0, 99999);

  factory EntryRest.fromMap(Map<String, dynamic> m) => EntryRest(
    id: m['id'] as String,
    effortId: m['effort_id'] as String,
    entryIndex: m['entry_index'] as int,
    restStartMs: m['rest_start_ms'] as int,
    restEndMs: m['rest_end_ms'] as int?,
    createdAtMs: m['created_at_ms'] as int,
    updatedAtMs: m['updated_at_ms'] as int,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'effort_id': effortId,
    'entry_index': entryIndex,
    'rest_start_ms': restStartMs,
    'rest_end_ms': restEndMs,
    'created_at_ms': createdAtMs,
    'updated_at_ms': updatedAtMs,
  };

  EntryRest copyWith({
    String? id,
    String? effortId,
    int? entryIndex,
    int? restStartMs,
    Object? restEndMs = _entryRestCopyWithUnset,
    int? createdAtMs,
    int? updatedAtMs,
  }) => EntryRest(
    id: id ?? this.id,
    effortId: effortId ?? this.effortId,
    entryIndex: entryIndex ?? this.entryIndex,
    restStartMs: restStartMs ?? this.restStartMs,
    restEndMs: restEndMs == _entryRestCopyWithUnset
        ? this.restEndMs
        : restEndMs as int?,
    createdAtMs: createdAtMs ?? this.createdAtMs,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
  );
}

const Object _entryRestCopyWithUnset = Object();

/// Per-exercise user note. Persists across sessions.
/// id is a deterministic key: 'note-{exerciseId}'.
class ExerciseNote {
  final String id;
  final String exerciseId;
  final String note;
  final String? lastSessionId;
  final int createdAtMs;
  final int updatedAtMs;

  const ExerciseNote({
    required this.id,
    required this.exerciseId,
    required this.note,
    this.lastSessionId,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  factory ExerciseNote.fromMap(Map<String, dynamic> m) => ExerciseNote(
    id: m['id'] as String,
    exerciseId: m['exercise_id'] as String,
    note: m['note'] as String,
    lastSessionId: m['last_session_id'] as String?,
    createdAtMs: m['created_at_ms'] as int,
    updatedAtMs: m['updated_at_ms'] as int,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'exercise_id': exerciseId,
    'note': note,
    'last_session_id': lastSessionId,
    'created_at_ms': createdAtMs,
    'updated_at_ms': updatedAtMs,
  };

  ExerciseNote copyWith({
    String? id,
    String? exerciseId,
    String? note,
    Object? lastSessionId = _exerciseNoteCopyWithUnset,
    int? createdAtMs,
    int? updatedAtMs,
  }) => ExerciseNote(
    id: id ?? this.id,
    exerciseId: exerciseId ?? this.exerciseId,
    note: note ?? this.note,
    lastSessionId: lastSessionId == _exerciseNoteCopyWithUnset
        ? this.lastSessionId
        : lastSessionId as String?,
    createdAtMs: createdAtMs ?? this.createdAtMs,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
  );
}

const Object _exerciseNoteCopyWithUnset = Object();
