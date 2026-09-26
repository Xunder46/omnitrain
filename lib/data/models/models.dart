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
  /// Sport-specific default duration round/period (in seconds).
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
  final int? sessionFeeling; // Session effort rating, 1-5: 1=Very easy, 5=Max effort
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

  /// `true` when this template shipped as a built-in demo via the versioned
  /// catalog refresh pipeline. The flag is informational only — the refresh
  /// still gates writes on the per-entry tombstone returned by
  /// [WorkoutRepository.isSeedEntryTouched] so that user edits and deletions
  /// remain authoritative.
  final bool isBuiltInDemo;
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
    this.isBuiltInDemo = false,
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
    isBuiltInDemo: (m['is_built_in_demo'] as int? ?? 0) == 1,
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
    'is_built_in_demo': isBuiltInDemo ? 1 : 0,
    'created_at_ms': createdAtMs,
    'updated_at_ms': updatedAtMs,
  };

  /// Returns a copy with selected fields replaced. `isBuiltInDemo` defaults
  /// to preserving the current value, mirroring the
  /// `Optional<String?>`-style semantics of the other nullable fields.
  WorkoutTemplate copyWith({
    String? id,
    String? ownerUserId,
    String? name,
    String? description,
    String? focusModality,
    String? primaryDisciplineId,
    String? note,
    bool? isBuiltInDemo,
    int? createdAtMs,
    int? updatedAtMs,
  }) {
    return WorkoutTemplate(
      id: id ?? this.id,
      ownerUserId: ownerUserId ?? this.ownerUserId,
      name: name ?? this.name,
      description: description ?? this.description,
      focusModality: focusModality ?? this.focusModality,
      primaryDisciplineId: primaryDisciplineId ?? this.primaryDisciplineId,
      note: note ?? this.note,
      isBuiltInDemo: isBuiltInDemo ?? this.isBuiltInDemo,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }
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
/// While the rest is active, the user can tap the rest tile to **pause**
/// (stop) and **resume** the counted time. The pause is captured as
/// [restPausedAtMs] and the elapsed formula subtracts
/// [restPausedDurationMs] (accumulated across all pause/resume cycles)
/// so the recorded rest duration excludes any stopped interval. While
/// paused, [restIsPaused] is `true` and the elapsed is frozen at the
/// pause time; on resume, the new pause-time is added to the
/// accumulator.
///
/// Because all times are wall-clock epoch milliseconds, rest durations
/// survive app backgrounding, device restarts, and navigation. The UI
/// derives the display value without a Stopwatch.
///
/// [entryIndex] is 0-based and identifies the set/round that this rest
/// *precedes* (i.e., the set the athlete is currently resting before).
///
/// Pure Dart — no Flutter imports.
class EntryRest {
  final String id; // 'rest-{effortId}-{entryIndex}'
  final String effortId;
  final int entryIndex; // 0-based; this rest precedes this set/round
  final int restStartMs; // wall-clock epoch ms when previous set was logged
  final int?
  restEndMs; // wall-clock epoch ms when this set/round began; null = still resting
  /// `true` when the user has tapped the rest tile to stop the counted
  /// time. While `true`, [restPausedAtMs] holds the wall-clock
  /// moment the rest was paused (used to freeze the elapsed display).
  final bool restIsPaused;

  /// Wall-clock epoch ms when the rest was paused; `null` while not
  /// paused. Persisted so the pause state survives reloads.
  final int? restPausedAtMs;

  /// Accumulated duration the rest spent in the paused state, in
  /// milliseconds. Excluded from the recorded rest duration on
  /// close/finish. The field is the single source of truth for
  /// "time not counted toward the rest" across all pause/resume
  /// cycles.
  final int restPausedDurationMs;
  final int createdAtMs;
  final int updatedAtMs;

  const EntryRest({
    required this.id,
    required this.effortId,
    required this.entryIndex,
    required this.restStartMs,
    this.restEndMs,
    this.restIsPaused = false,
    this.restPausedAtMs,
    this.restPausedDurationMs = 0,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  /// Elapsed rest in whole seconds, excluding any paused interval.
  /// Live (unbounded) while [restEndMs] is null.
  int elapsedSeconds(int nowMs) {
    final effectiveEndMs =
        restEndMs ?? (restIsPaused ? (restPausedAtMs ?? nowMs) : nowMs);
    return ((effectiveEndMs - restStartMs - restPausedDurationMs) / 1000)
        .round()
        .clamp(0, 99999);
  }

  factory EntryRest.fromMap(Map<String, dynamic> m) => EntryRest(
    id: m['id'] as String,
    effortId: m['effort_id'] as String,
    entryIndex: m['entry_index'] as int,
    restStartMs: m['rest_start_ms'] as int,
    restEndMs: m['rest_end_ms'] as int?,
    restIsPaused: (m['rest_is_paused'] as int? ?? 0) == 1,
    restPausedAtMs: m['rest_paused_at_ms'] as int?,
    restPausedDurationMs: m['rest_paused_duration_ms'] as int? ?? 0,
    createdAtMs: m['created_at_ms'] as int,
    updatedAtMs: m['updated_at_ms'] as int,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'effort_id': effortId,
    'entry_index': entryIndex,
    'rest_start_ms': restStartMs,
    'rest_end_ms': restEndMs,
    'rest_is_paused': restIsPaused ? 1 : 0,
    'rest_paused_at_ms': restPausedAtMs,
    'rest_paused_duration_ms': restPausedDurationMs,
    'created_at_ms': createdAtMs,
    'updated_at_ms': updatedAtMs,
  };

  EntryRest copyWith({
    String? id,
    String? effortId,
    int? entryIndex,
    int? restStartMs,
    Object? restEndMs = _entryRestCopyWithUnset,
    bool? restIsPaused,
    Object? restPausedAtMs = _entryRestCopyWithUnset,
    int? restPausedDurationMs,
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
    restIsPaused: restIsPaused ?? this.restIsPaused,
    restPausedAtMs: restPausedAtMs == _entryRestCopyWithUnset
        ? this.restPausedAtMs
        : restPausedAtMs as int?,
    restPausedDurationMs: restPausedDurationMs ?? this.restPausedDurationMs,
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

class NutritionTarget {
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final int?
  dateMs; // Optional date (ms since epoch); null for legacy global targets

  NutritionTarget({
    this.calories = 0.0,
    this.protein = 0.0,
    this.carbs = 0.0,
    this.fat = 0.0,
    this.dateMs,
  });

  /// Check if this target is "unset" (all macros are 0)
  bool get isUnset =>
      calories == 0.0 && protein == 0.0 && carbs == 0.0 && fat == 0.0;

  factory NutritionTarget.fromMap(Map<String, dynamic> m) => NutritionTarget(
    calories: ((m['calories'] as num?) ?? 0.0).toDouble(),
    protein: ((m['protein'] as num?) ?? 0.0).toDouble(),
    carbs: ((m['carbs'] as num?) ?? 0.0).toDouble(),
    fat: ((m['fat'] as num?) ?? 0.0).toDouble(),
    dateMs: m['date_ms'] as int?,
  );

  Map<String, dynamic> toMap() => {
    'calories': calories,
    'protein': protein,
    'carbs': carbs,
    'fat': fat,
    'date_ms': dateMs,
  };

  NutritionTarget copyWith({
    double? calories,
    double? protein,
    double? carbs,
    double? fat,
    int? dateMs,
  }) {
    return NutritionTarget(
      calories: calories ?? this.calories,
      protein: protein ?? this.protein,
      carbs: carbs ?? this.carbs,
      fat: fat ?? this.fat,
      dateMs: dateMs ?? this.dateMs,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FoodGroup — User-created food grouping category (e.g., "Proteins", "Vegetables")
// ─────────────────────────────────────────────────────────────────────────────

class FoodGroup {
  final String id;
  final String name;
  final String? color;
  final bool isArchived;
  final int createdAtMs;
  final int updatedAtMs;

  const FoodGroup({
    required this.id,
    required this.name,
    this.color,
    this.isArchived = false,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  factory FoodGroup.fromMap(Map<String, dynamic> m) => FoodGroup(
    id: m['id'] as String,
    name: m['name'] as String,
    color: m['color'] as String?,
    isArchived: (m['is_archived'] as int?) == 1,
    createdAtMs: m['created_at_ms'] as int,
    updatedAtMs: m['updated_at_ms'] as int,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'color': color,
    'is_archived': isArchived ? 1 : 0,
    'created_at_ms': createdAtMs,
    'updated_at_ms': updatedAtMs,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Food — A food item with macronutrient metadata
// ─────────────────────────────────────────────────────────────────────────────
// Food Unit Type — the reference unit system for a food item.
// ─────────────────────────────────────────────────────────────────────────────

/// The unit system used for a food's reference amount.
/// - `count`: discrete items (e.g. "1 egg", "1 slice")
/// - `grams`: weight-based (e.g. "100 g")
enum FoodUnitType {
  count,
  grams;

  /// Parse from string (storage format: 'count' or 'grams')
  static FoodUnitType fromString(String? value) {
    if (value == 'count') return FoodUnitType.count;
    return FoodUnitType.grams; // default
  }

  /// Serialize to string for storage
  String toStorageString() => name;
}

// ─────────────────────────────────────────────────────────────────────────────
//
// Calories are computed (not stored): protein * 4 + carbs * 4 + fat * 9
// All macro values are stored as integers (grams serving).

class Food {
  final String id;
  final String name;
  final String? groupId;

  /// Unit type: count (discrete items) or grams (weight-based).
  final FoodUnitType unitType;

  /// Reference amount — the quantity this food's macros are expressed per.
  /// E.g., 100.0 for "100 g", 1.0 for "1 egg".
  final double referenceAmount;

  /// Reference label — the display unit for the reference amount.
  /// E.g., "g", "egg", "tbsp", "slice".
  final String referenceLabel;

  /// Whether this is a catalog (bundled) food vs user-owned library food.
  /// Catalog foods are read-only; library foods are user-editable.
  final bool isCatalog;

  /// The ID of the catalog food this library food is linked to.
  /// Only populated for non-catalog (user-owned) foods that were copied
  /// from a catalog entry. This provides a durable identity link that
  /// survives edits to name, macros, or other fields.
  final String? catalogId;

  final double protein;
  final double carbs;
  final double? fiber;
  final double fat;
  final double? sodium;
  final bool isArchived;
  final String? notes;

  /// Native-first local file path for an optional food photo. Same
  /// contract as [UserProfile.avatarPath]: the path is opaque to the
  /// repository and only the user (or the OS photo picker) can keep
  /// the file alive. Web has no persistent file API, so the picker
  /// is a no-op there and the field stays `null`.
  final String? imagePath;

  /// Remembered "last amount" the user logged for this food, in the
  /// food's own unit (grams for grams-type, count-multiplier for
  /// count-type — see [NutritionState.logConsumedFoodAt] for the
  /// own-unit contract). `null` when the food has never been logged.
  ///
  /// Drives the `LogFoodRow` pre-fill (June 2026, food-last-amount
  /// plan): when the food is not logged today, the amount input is
  /// pre-filled with this value so the user does not have to retype
  /// the same portion every day. When null, the input falls back to
  /// the food's [referenceAmount] (for grams-type) or `1.0`
  /// (count-type). Overwritten on every successful save through
  /// `NutritionState`; never mutated by an unsaved UI edit.
  ///
  /// Stored on the food row (not on `ConsumedFood`) so a remove-then-
  /// re-add via `addCatalogFoodToLibrary` (with `catalogId`
  /// linkage, per `food-durable-identity-plan.md`) reuses the same
  /// library food and therefore the same remembered amount.
  final double? lastAmountConsumed;

  final int createdAtMs;
  final int updatedAtMs;

  // ─── Deprecated fields — kept for legacy compatibility ───────────────────────
  /// @deprecated Use [referenceAmount] instead. Kept for legacy row compatibility.
  int get servingSize => referenceAmount.round();

  /// @deprecated Use [referenceLabel] instead. Kept for legacy row compatibility.
  String get servingUnit => referenceLabel;
  // ─────────────────────────────────────────────────────────────────────────

  const Food({
    required this.id,
    required this.name,
    this.groupId,
    required this.unitType,
    required this.referenceAmount,
    required this.referenceLabel,
    this.isCatalog = false,
    this.catalogId,
    required this.protein,
    required this.carbs,
    this.fiber,
    required this.fat,
    this.sodium,
    this.isArchived = false,
    this.notes,
    this.imagePath,
    this.lastAmountConsumed,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  /// Helper: true if this is a catalog (bundled) food
  bool get isCatalogFood => isCatalog;

  /// Helper: true if this is a user-owned library food
  bool get isLibraryFood => !isCatalog;

  /// Computed calorie value: protein * 4 + carbs * 4 + fat * 9.
  /// Macros are stored as `double` to support fractional grams
  /// (e.g. `0.5` g of fat); the calorie count is rounded to `int`
  /// at the display boundary because the UI shows whole kcal.
  int get calories => (protein * 4 + carbs * 4 + fat * 9).round();

  /// Computed net carbs: carbs - (fiber ?? 0).
  /// Rounded to `int` for parity with the existing
  /// `todayConsumedNetCarbsRaw` chart math (which always emits
  /// int grams for the donut).
  int get netCarbs => (carbs - (fiber ?? 0)).round();

  factory Food.fromMap(Map<String, dynamic> m) {
    // Handle legacy rows: if new fields are missing, fall back to serving fields
    final hasNewFields =
        m['unit_type'] != null || m['reference_amount'] != null;

    return Food(
      id: m['id'] as String,
      name: m['name'] as String,
      groupId: m['group_id'] as String?,
      unitType: hasNewFields
          ? FoodUnitType.fromString(m['unit_type'] as String?)
          : FoodUnitType.grams,
      referenceAmount: hasNewFields
          ? ((m['reference_amount'] as num?) ?? 100.0).toDouble()
          : (m['serving_size'] as num?)?.toDouble() ?? 100.0,
      referenceLabel: hasNewFields
          ? (m['reference_label'] as String?) ?? 'g'
          : (m['serving_unit'] as String?) ?? 'g',
      isCatalog: hasNewFields ? (m['is_catalog'] as int?) == 1 : false,
      catalogId: m['catalog_id'] as String?,
      // Macros are widened to `double` to support fractional
      // grams; the cast below accepts both legacy `INTEGER` rows
      // (where `m['protein']` is an `int`) and the new `REAL`
      // rows (where it is a `double`), so the change is
      // back-compatible without a row migration.
      protein: ((m['protein'] as num?) ?? 0.0).toDouble(),
      carbs: ((m['carbs'] as num?) ?? 0.0).toDouble(),
      fiber: (m['fiber'] as num?)?.toDouble(),
      fat: ((m['fat'] as num?) ?? 0.0).toDouble(),
      sodium: (m['sodium'] as num?)?.toDouble(),
      isArchived: (m['is_archived'] as int?) == 1,
      notes: m['notes'] as String?,
      imagePath: m['image_path'] as String?,
      // Remembered last amount. Missing key → null (legacy rows).
      lastAmountConsumed: (m['last_amount_consumed'] as num?)?.toDouble(),
      createdAtMs: m['created_at_ms'] as int,
      updatedAtMs: m['updated_at_ms'] as int,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'group_id': groupId,
    'unit_type': unitType.toStorageString(),
    'reference_amount': referenceAmount,
    'reference_label': referenceLabel,
    'is_catalog': isCatalog ? 1 : 0,
    'catalog_id': catalogId,
    'protein': protein,
    'carbs': carbs,
    'fiber': fiber,
    'fat': fat,
    'sodium': sodium,
    'is_archived': isArchived ? 1 : 0,
    'notes': notes,
    'image_path': imagePath,
    'last_amount_consumed': lastAmountConsumed,
    'created_at_ms': createdAtMs,
    'updated_at_ms': updatedAtMs,
  };

  Food copyWith({
    String? id,
    String? name,
    Object? groupId = _foodCopyWithUnset,
    FoodUnitType? unitType,
    double? referenceAmount,
    String? referenceLabel,
    bool? isCatalog,
    Object? catalogId = _foodCopyWithUnset,
    double? protein,
    double? carbs,
    double? fiber,
    double? fat,
    double? sodium,
    bool? isArchived,
    String? notes,
    Object? imagePath = _foodCopyWithUnset,
    Object? lastAmountConsumed = _foodCopyWithUnset,
    int? createdAtMs,
    int? updatedAtMs,
  }) {
    return Food(
      id: id ?? this.id,
      name: name ?? this.name,
      groupId: identical(groupId, _foodCopyWithUnset)
          ? this.groupId
          : groupId as String?,
      unitType: unitType ?? this.unitType,
      referenceAmount: referenceAmount ?? this.referenceAmount,
      referenceLabel: referenceLabel ?? this.referenceLabel,
      isCatalog: isCatalog ?? this.isCatalog,
      catalogId: identical(catalogId, _foodCopyWithUnset)
          ? this.catalogId
          : catalogId as String?,
      protein: protein ?? this.protein,
      carbs: carbs ?? this.carbs,
      fiber: fiber ?? this.fiber,
      fat: fat ?? this.fat,
      sodium: sodium ?? this.sodium,
      isArchived: isArchived ?? this.isArchived,
      notes: notes ?? this.notes,
      imagePath: identical(imagePath, _foodCopyWithUnset)
          ? this.imagePath
          : imagePath as String?,
      lastAmountConsumed: identical(lastAmountConsumed, _foodCopyWithUnset)
          ? this.lastAmountConsumed
          : lastAmountConsumed as double?,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }
}

// Sentinel used by [Food.copyWith] to distinguish "argument omitted"
// from "argument was explicitly null". `groupId` and `imagePath` are
// the two nullable fields on `Food` and callers need to be able to
// clear them.
const Object _foodCopyWithUnset = Object();

// ─────────────────────────────────────────────────────────────────────────────
// ConsumedFood — A frozen snapshot of a logged food for a specific day.
// ─────────────────────────────────────────────────────────────────────────────
//
// This model stores a complete snapshot of a food at the moment it was logged,
// ensuring historical data remains accurate even if the source food or daily
// targets are later edited or deleted.
//
// All fields prefixed "snapshot" or "target" are frozen at log time:
// - The food's name, unit type, reference amount/label, and macros
// - The group (id + name) the food belonged to
// - The daily nutrition targets that were in effect

class ConsumedFood {
  final String id;
  final int loggedAtMs; // when the user logged this (wall clock)
  final int dateMs; // day key (local midnight ms) this counts toward

  // Source reference — nullable if the original food was deleted
  final String? sourceFoodId;

  // Frozen food snapshot. Macros are stored as `double` to
  // support fractional grams; see `Food` for the rationale and
  // the `fromMap` back-compat pattern.
  final String name;
  final FoodUnitType unitType;
  final double referenceAmount;
  final String referenceLabel;
  final double protein;
  final double carbs;
  final double? fiber;
  final double fat;
  final double? sodium;

  // How much was consumed (in the food's reference unit)
  final double amountConsumed;

  // Frozen group snapshot (so logs remain readable even if group is renamed/deleted)
  final String? groupIdSnapshot;
  final String? groupNameSnapshot;

  // Frozen daily targets (so past days don't change when targets are edited)
  final double targetCalories;
  final double targetProtein;
  final double targetCarbs;
  final double targetFat;

  final int createdAtMs;
  final int updatedAtMs;

  const ConsumedFood({
    required this.id,
    required this.loggedAtMs,
    required this.dateMs,
    this.sourceFoodId,
    required this.name,
    required this.unitType,
    required this.referenceAmount,
    required this.referenceLabel,
    required this.protein,
    required this.carbs,
    this.fiber,
    required this.fat,
    this.sodium,
    required this.amountConsumed,
    this.groupIdSnapshot,
    this.groupNameSnapshot,
    required this.targetCalories,
    required this.targetProtein,
    required this.targetCarbs,
    required this.targetFat,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  /// Computed calories consumed:
  /// `(protein * 4 + carbs * 4 + fat * 9) * (amountConsumed / referenceAmount)`.
  ///
  /// The macros on the snapshot are stored **the food's reference**
  /// (e.g. 100 g or 1 egg). The `amountConsumed` is in the
  /// food's own unit (g for grams-type foods, count for count-type
  /// foods), so the scaling factor is `amountConsumed / referenceAmount`.
  ///
  /// This uses the frozen macro and reference values, not the current
  /// live food values. Examples:
  ///   - 150 g of a per-100 g food (31P / 0C / 3F = 151 kcal):
  ///     151 * (150 / 100) = 151 * 1.5 = 226.
  ///   - 3 of a per-1-egg food (6P / 1C / 5F = 73 kcal):
  ///     73 * (3 / 1) = 73 * 3 = 219.
  int get caloriesConsumed =>
      ((protein * 4 + carbs * 4 + fat * 9) * (amountConsumed / referenceAmount))
          .round();

  factory ConsumedFood.fromMap(Map<String, dynamic> m) => ConsumedFood(
    id: m['id'] as String,
    loggedAtMs: m['logged_at_ms'] as int,
    dateMs: m['date_ms'] as int,
    sourceFoodId: m['source_food_id'] as String?,
    name: m['name'] as String,
    unitType: FoodUnitType.fromString(m['unit_type'] as String?),
    referenceAmount: ((m['reference_amount'] as num?) ?? 100.0).toDouble(),
    referenceLabel: (m['reference_label'] as String?) ?? 'g',
    // Macros are widened to `double` for fractional grams; the
    // cast below accepts both legacy `INTEGER` rows and the new
    // `REAL` rows. See `Food.fromMap` for the rationale.
    protein: ((m['protein'] as num?) ?? 0.0).toDouble(),
    carbs: ((m['carbs'] as num?) ?? 0.0).toDouble(),
    fiber: (m['fiber'] as num?)?.toDouble(),
    fat: ((m['fat'] as num?) ?? 0.0).toDouble(),
    sodium: (m['sodium'] as num?)?.toDouble(),
    amountConsumed: ((m['amount_consumed'] as num?) ?? 1.0).toDouble(),
    groupIdSnapshot: m['group_id_snapshot'] as String?,
    groupNameSnapshot: m['group_name_snapshot'] as String?,
    targetCalories: ((m['target_calories'] as num?) ?? 0.0).toDouble(),
    targetProtein: ((m['target_protein'] as num?) ?? 0.0).toDouble(),
    targetCarbs: ((m['target_carbs'] as num?) ?? 0.0).toDouble(),
    targetFat: ((m['target_fat'] as num?) ?? 0.0).toDouble(),
    createdAtMs: m['created_at_ms'] as int,
    updatedAtMs: m['updated_at_ms'] as int,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'logged_at_ms': loggedAtMs,
    'date_ms': dateMs,
    'source_food_id': sourceFoodId,
    'name': name,
    'unit_type': unitType.toStorageString(),
    'reference_amount': referenceAmount,
    'reference_label': referenceLabel,
    'protein': protein,
    'carbs': carbs,
    'fiber': fiber,
    'fat': fat,
    'sodium': sodium,
    'amount_consumed': amountConsumed,
    'group_id_snapshot': groupIdSnapshot,
    'group_name_snapshot': groupNameSnapshot,
    'target_calories': targetCalories,
    'target_protein': targetProtein,
    'target_carbs': targetCarbs,
    'target_fat': targetFat,
    'created_at_ms': createdAtMs,
    'updated_at_ms': updatedAtMs,
  };

  ConsumedFood copyWith({
    String? id,
    int? loggedAtMs,
    int? dateMs,
    String? sourceFoodId,
    String? name,
    FoodUnitType? unitType,
    double? referenceAmount,
    String? referenceLabel,
    double? protein,
    double? carbs,
    double? fiber,
    double? fat,
    double? sodium,
    double? amountConsumed,
    String? groupIdSnapshot,
    String? groupNameSnapshot,
    double? targetCalories,
    double? targetProtein,
    double? targetCarbs,
    double? targetFat,
    int? createdAtMs,
    int? updatedAtMs,
  }) {
    return ConsumedFood(
      id: id ?? this.id,
      loggedAtMs: loggedAtMs ?? this.loggedAtMs,
      dateMs: dateMs ?? this.dateMs,
      sourceFoodId: sourceFoodId ?? this.sourceFoodId,
      name: name ?? this.name,
      unitType: unitType ?? this.unitType,
      referenceAmount: referenceAmount ?? this.referenceAmount,
      referenceLabel: referenceLabel ?? this.referenceLabel,
      protein: protein ?? this.protein,
      carbs: carbs ?? this.carbs,
      fiber: fiber ?? this.fiber,
      fat: fat ?? this.fat,
      sodium: sodium ?? this.sodium,
      amountConsumed: amountConsumed ?? this.amountConsumed,
      groupIdSnapshot: groupIdSnapshot ?? this.groupIdSnapshot,
      groupNameSnapshot: groupNameSnapshot ?? this.groupNameSnapshot,
      targetCalories: targetCalories ?? this.targetCalories,
      targetProtein: targetProtein ?? this.targetProtein,
      targetCarbs: targetCarbs ?? this.targetCarbs,
      targetFat: targetFat ?? this.targetFat,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WaterLogEntry — Per-day water volume in milliliters.
// ─────────────────────────────────────────────────────────────────────────────
//
// One row per calendar day, keyed by `dateMs` (local midnight). The day's
// water volume is stored as a real volume in milliliters so the historical
// record stays unit-clean — the on-screen "glass count" is derived at the
// display boundary (`volumeMl ~/ kWaterGlassMl`), not stored. Editing a day's
// water writes a new `updatedAtMs`; past days are never mutated automatically.
//
// Water has no goal — like macros and sodium, it is tracked and stored for the
// historical record only. Each new day starts at 0; logging takes effect
// immediately and survives closing and reopening the app on the same day.

class WaterLogEntry {
  /// Deterministic id (`'water-<dateMs>'`) so the per-day row has a stable
  /// storage key. Callers never construct a `WaterLogEntry` directly — the
  /// repository owns the id minting and `NutritionState` writes through it.
  final String id;

  /// Day key (local midnight ms) this row counts toward.
  final int dateMs;

  /// Stored volume in milliliters. Always `>= 0`. The state layer floors
  /// the value at 0 ml when a decrement would otherwise go negative.
  final int volumeMl;

  final int createdAtMs;
  final int updatedAtMs;

  const WaterLogEntry({
    required this.id,
    required this.dateMs,
    required this.volumeMl,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  /// Stable per-day id (`'water-<dateMs>'`). Used by both repository
  /// implementations to derive the storage key from the date.
  static String idForDate(int dateMs) => 'water-$dateMs';

  factory WaterLogEntry.fromMap(Map<String, dynamic> m) => WaterLogEntry(
    id: m['id'] as String,
    dateMs: m['date_ms'] as int,
    volumeMl: m['volume_ml'] as int,
    createdAtMs: m['created_at_ms'] as int,
    updatedAtMs: m['updated_at_ms'] as int,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'date_ms': dateMs,
    'volume_ml': volumeMl,
    'created_at_ms': createdAtMs,
    'updated_at_ms': updatedAtMs,
  };

  WaterLogEntry copyWith({
    String? id,
    int? dateMs,
    int? volumeMl,
    int? createdAtMs,
    int? updatedAtMs,
  }) {
    return WaterLogEntry(
      id: id ?? this.id,
      dateMs: dateMs ?? this.dateMs,
      volumeMl: volumeMl ?? this.volumeMl,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Watch capture — wrist-measured summaries and the watch session inbox
// (Stats PR 2, D-131 / D-132)
// ─────────────────────────────────────────────────────────────────────────────

/// A heart-rate and step summary the wrist measured over one window of a
/// wrist session. It attaches to exactly one target: the session itself, a
/// set block ([SegmentEffort]), a timed or hold entry ([TimedInstance]) or a
/// round ([RoundInstance]).
///
/// It is measured, never entered, so it is not an [EffortObservation] and is
/// never read or edited as a manual metric (`metric-heart-rate` stays
/// unused). It is a separate row rather than new columns on its targets
/// because those rows are rebuilt field by field in several places, where a
/// new field would be silently dropped.
///
/// Invariants, enforced here at construction (a violation throws
/// [ArgumentError]) and mirrored by CHECK constraints on `app_sensor_summary`
/// in `scripts/sqlite_schema.sql`:
///   - [scope] is one of [scopes]; a `session` summary targets its own session.
///   - One row per (scope, target): [id] is derived from both, so the
///     repository's put-if-absent keeps the pair unique.
///   - The heart-rate pair travels together, both or neither, with
///     1 ≤ average ≤ maximum. A missing reading is absence, never zero.
///   - [steps] is ≥ 0 and appears only on a `timed_instance`. A measured 0 is
///     a value.
///   - At least one measured value: an empty summary cannot exist.
///   - The window is ordered, and [source] is `watch`.
///
/// A summary is deleted together with its target, and every summary carries
/// the [sessionId] it belongs to so deleting the session removes all of them.
/// Verified by `test/watch_capture_repository_parity_test.dart`.
class SensorSummary {
  static const String scopeSession = 'session';
  static const String scopeEffort = 'effort';
  static const String scopeTimedInstance = 'timed_instance';
  static const String scopeRoundInstance = 'round_instance';

  /// Every scope, in the order a session's summaries are listed.
  static const List<String> scopes = [
    scopeSession,
    scopeEffort,
    scopeTimedInstance,
    scopeRoundInstance,
  ];

  static const String sourceWatch = 'watch';

  /// Every source a summary may come from.
  static const List<String> sources = [sourceWatch];

  /// Deterministic storage key: one row per (scope, target).
  static String idFor(String scope, String targetId) =>
      'sensor-$scope-$targetId';

  final String id;

  /// The [TrainingSession] this summary belongs to, whatever its scope.
  final String sessionId;
  final String scope;

  /// The id of the row the summary attaches to: the session, the
  /// [SegmentEffort], the [TimedInstance] or the [RoundInstance].
  final String targetId;

  /// The window the summary covers, wall-clock epoch ms, both ends inclusive.
  final int windowStartMs;
  final int windowEndMs;

  /// Unrounded arithmetic mean of the qualifying heart-rate samples.
  final double? avgHeartRateBpm;
  final double? maxHeartRateBpm;

  /// Steps taken inside the window (timed entries only).
  final int? steps;
  final String source;
  final int createdAtMs;

  SensorSummary({
    required this.sessionId,
    required this.scope,
    required this.targetId,
    required this.windowStartMs,
    required this.windowEndMs,
    this.avgHeartRateBpm,
    this.maxHeartRateBpm,
    this.steps,
    this.source = sourceWatch,
    required this.createdAtMs,
  }) : id = idFor(scope, targetId) {
    _checkInvariants();
  }

  void _checkInvariants() {
    if (!scopes.contains(scope)) {
      throw ArgumentError.value(scope, 'scope', 'D-131: unknown summary scope');
    }
    if (sessionId.isEmpty || targetId.isEmpty) {
      throw ArgumentError('D-131: a summary names its session and its target');
    }
    if (scope == scopeSession && targetId != sessionId) {
      throw ArgumentError.value(
        targetId,
        'targetId',
        'D-131: a session summary targets its own session ($sessionId)',
      );
    }
    final avg = avgHeartRateBpm;
    final max = maxHeartRateBpm;
    if ((avg == null) != (max == null)) {
      throw ArgumentError(
        'D-131: the heart-rate average and maximum are both present or both '
        'absent',
      );
    }
    if (avg != null && max != null) {
      if (!avg.isFinite || !max.isFinite) {
        throw ArgumentError('D-131: heart rate must be a finite number');
      }
      if (avg < 1) {
        throw ArgumentError.value(
          avg,
          'avgHeartRateBpm',
          'D-131: a missing heart rate is absent, never zero; 1 ≤ average',
        );
      }
      if (avg > max) {
        throw ArgumentError.value(
          avg,
          'avgHeartRateBpm',
          'D-131: the heart-rate average cannot exceed the maximum ($max)',
        );
      }
    }
    final stepCount = steps;
    if (stepCount != null) {
      if (stepCount < 0) {
        throw ArgumentError.value(stepCount, 'steps', 'D-131: steps ≥ 0');
      }
      if (scope != scopeTimedInstance) {
        throw ArgumentError.value(
          scope,
          'scope',
          'D-131: steps are recorded only on a timed_instance summary',
        );
      }
    }
    if (avg == null && stepCount == null) {
      throw ArgumentError(
        'D-131: a summary holds at least one measured value; an empty '
        'summary is never stored',
      );
    }
    if (windowEndMs < windowStartMs) {
      throw ArgumentError.value(
        windowEndMs,
        'windowEndMs',
        'D-131: the window ends at or after it starts ($windowStartMs)',
      );
    }
    if (!sources.contains(source)) {
      throw ArgumentError.value(source, 'source', 'D-131: unknown source');
    }
  }

  factory SensorSummary.fromMap(Map<String, dynamic> m) {
    final summary = SensorSummary(
      sessionId: m['session_id'] as String,
      scope: m['scope'] as String,
      targetId: m['target_id'] as String,
      windowStartMs: m['window_start_ms'] as int,
      windowEndMs: m['window_end_ms'] as int,
      avgHeartRateBpm: (m['avg_heart_rate_bpm'] as num?)?.toDouble(),
      maxHeartRateBpm: (m['max_heart_rate_bpm'] as num?)?.toDouble(),
      steps: m['steps'] as int?,
      source: m['source'] as String,
      createdAtMs: m['created_at_ms'] as int,
    );
    final storedId = m['id'] as String?;
    if (storedId != null && storedId != summary.id) {
      throw ArgumentError.value(
        storedId,
        'id',
        'D-131: a stored summary id must be ${summary.id}',
      );
    }
    return summary;
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'session_id': sessionId,
    'scope': scope,
    'target_id': targetId,
    'window_start_ms': windowStartMs,
    'window_end_ms': windowEndMs,
    'avg_heart_rate_bpm': avgHeartRateBpm,
    'max_heart_rate_bpm': maxHeartRateBpm,
    'steps': steps,
    'source': source,
    'created_at_ms': createdAtMs,
  };
}

/// One thing the phone learned about a wrist session before it became
/// history: a wrist event, or one of the phone's own annotations on that
/// session.
///
/// Wrist kinds are the protocol's `set`, `timed`, `round`, `hold`,
/// `effort_rating` and `session_end` events. Phone kinds are the phone's own
/// rating (`phone_rating`), and the live corrections and deletions it sent
/// for a wrist entry (`phone_correction`, `phone_deletion`). The phone mints
/// the annotation ids deterministically ([phoneRatingId], [phoneChangeId]),
/// so a phone annotation is staged at most once too.
///
/// The repository stages rows put-if-absent by [entryId]: the first copy is
/// the record, and a redelivered or altered copy never replaces it. Rows are
/// never deleted, and no history delete cascades into the inbox: once
/// [appliedAtMs] is set, a row is the tombstone that stops a later sync from
/// re-creating history the user deleted.
///
/// [payload] is the event object as it arrived, or the phone's annotation.
/// It is held as its JSON encoding, so the map a caller reads is a fresh copy
/// and a staged row cannot be changed through it.
///
/// Verified by `test/watch_capture_repository_parity_test.dart`.
class WatchInboxEntry {
  static const String originWatch = 'watch';
  static const String originPhone = 'phone';

  static const String kindSet = 'set';
  static const String kindTimed = 'timed';
  static const String kindRound = 'round';
  static const String kindHold = 'hold';
  static const String kindEffortRating = 'effort_rating';
  static const String kindSessionEnd = 'session_end';
  static const String kindPhoneRating = 'phone_rating';
  static const String kindPhoneCorrection = 'phone_correction';
  static const String kindPhoneDeletion = 'phone_deletion';

  /// The wrist event kinds the inbox stages (origin `watch`).
  static const List<String> watchKinds = [
    kindSet,
    kindTimed,
    kindRound,
    kindHold,
    kindEffortRating,
    kindSessionEnd,
  ];

  /// The phone's own annotation kinds (origin `phone`).
  static const List<String> phoneKinds = [
    kindPhoneRating,
    kindPhoneCorrection,
    kindPhoneDeletion,
  ];

  static const String _phoneChangeIdPrefix = 'phone-change-';

  /// The id of the phone's own rating for [watchSessionId]: one per session.
  static String phoneRatingId(String watchSessionId) =>
      'phone-rating-$watchSessionId';

  /// The id of the [index]th change of the phone's structure change
  /// [changeId] (a `correct_entry` or `delete_entry`).
  static String phoneChangeId(String changeId, int index) =>
      '$_phoneChangeIdPrefix$changeId-$index';

  final String entryId;
  final String watchSessionId;
  final String kind;
  final String origin;

  /// The JSON encoding of [payload], exactly as stored.
  final String payloadJson;

  /// Wall-clock epoch ms when the phone staged the row.
  final int receivedAtMs;

  /// Wall-clock epoch ms when the row was applied (materialised into
  /// history, or deliberately discarded); `null` while it waits.
  final int? appliedAtMs;

  WatchInboxEntry({
    required String entryId,
    required String watchSessionId,
    required String kind,
    required String origin,
    required Map<String, dynamic> payload,
    required int receivedAtMs,
    int? appliedAtMs,
  }) : this._(
         entryId: entryId,
         watchSessionId: watchSessionId,
         kind: kind,
         origin: origin,
         payloadJson: _encodePayload(payload),
         receivedAtMs: receivedAtMs,
         appliedAtMs: appliedAtMs,
       );

  WatchInboxEntry._({
    required this.entryId,
    required this.watchSessionId,
    required this.kind,
    required this.origin,
    required this.payloadJson,
    required this.receivedAtMs,
    this.appliedAtMs,
  }) {
    _checkInvariants();
  }

  static String _encodePayload(Map<String, dynamic> payload) {
    try {
      return jsonEncode(payload);
    } on JsonUnsupportedObjectError catch (e) {
      throw ArgumentError.value(
        payload,
        'payload',
        'D-132: a staged payload must be JSON (${e.unsupportedObject})',
      );
    }
  }

  void _checkInvariants() {
    if (entryId.isEmpty || watchSessionId.isEmpty) {
      throw ArgumentError('D-132: a staged row names its entry and session');
    }
    final List<String> allowedKinds;
    if (origin == originWatch) {
      allowedKinds = watchKinds;
    } else if (origin == originPhone) {
      allowedKinds = phoneKinds;
    } else {
      throw ArgumentError.value(origin, 'origin', 'D-132: watch or phone');
    }
    if (!allowedKinds.contains(kind)) {
      throw ArgumentError.value(
        kind,
        'kind',
        'D-132: not a kind the inbox stages for origin $origin',
      );
    }
    if (kind == kindPhoneRating && entryId != phoneRatingId(watchSessionId)) {
      throw ArgumentError.value(
        entryId,
        'entryId',
        'D-132: the phone rating id is ${phoneRatingId(watchSessionId)}',
      );
    }
    if ((kind == kindPhoneCorrection || kind == kindPhoneDeletion) &&
        !entryId.startsWith(_phoneChangeIdPrefix)) {
      throw ArgumentError.value(
        entryId,
        'entryId',
        'D-132: a phone change id comes from phoneChangeId',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(payloadJson);
    } on FormatException {
      throw ArgumentError.value(payloadJson, 'payloadJson', 'D-132: not JSON');
    }
    if (decoded is! Map<String, dynamic>) {
      throw ArgumentError.value(
        payloadJson,
        'payloadJson',
        'D-132: a staged payload is a JSON object',
      );
    }
  }

  /// A fresh copy of the staged payload.
  Map<String, dynamic> get payload =>
      jsonDecode(payloadJson) as Map<String, dynamic>;

  factory WatchInboxEntry.fromMap(Map<String, dynamic> m) => WatchInboxEntry._(
    entryId: m['entry_id'] as String,
    watchSessionId: m['watch_session_id'] as String,
    kind: m['kind'] as String,
    origin: m['origin'] as String,
    payloadJson: m['payload_json'] as String,
    receivedAtMs: m['received_at_ms'] as int,
    appliedAtMs: m['applied_at_ms'] as int?,
  );

  Map<String, dynamic> toMap() => {
    'entry_id': entryId,
    'watch_session_id': watchSessionId,
    'kind': kind,
    'origin': origin,
    'payload_json': payloadJson,
    'received_at_ms': receivedAtMs,
    'applied_at_ms': appliedAtMs,
  };
}
