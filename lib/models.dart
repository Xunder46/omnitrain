// Data model classes aligned with SQLite schema

class SportCategory {
  final String id;
  final String key;
  final String name;
  final int createdAtMs;
  final int updatedAtMs;
  final int? deletedAtMs;

  SportCategory({required this.id, required this.key, required this.name, required this.createdAtMs, required this.updatedAtMs, this.deletedAtMs});

  factory SportCategory.fromMap(Map<String, dynamic> m) => SportCategory(
      id: m['id'] as String,
      key: m['key'] as String,
      name: m['name'] as String,
      createdAtMs: m['created_at_ms'] as int,
      updatedAtMs: m['updated_at_ms'] as int,
      deletedAtMs: m['deleted_at_ms'] as int?);

  Map<String, dynamic> toMap() => {
        'id': id,
        'key': key,
        'name': name,
        'created_at_ms': createdAtMs,
        'updated_at_ms': updatedAtMs,
        'deleted_at_ms': deletedAtMs
      };
}

class Discipline {
  final String id;
  final String categoryId;
  final String key;
  final String name;
  final int createdAtMs;
  final int updatedAtMs;

  Discipline({required this.id, required this.categoryId, required this.key, required this.name, required this.createdAtMs, required this.updatedAtMs});

  factory Discipline.fromMap(Map<String, dynamic> m) => Discipline(
      id: m['id'] as String,
      categoryId: m['category_id'] as String,
      key: m['key'] as String,
      name: m['name'] as String,
      createdAtMs: m['created_at_ms'] as int,
      updatedAtMs: m['updated_at_ms'] as int);

  Map<String, dynamic> toMap() => {
        'id': id,
        'category_id': categoryId,
        'key': key,
        'name': name,
        'created_at_ms': createdAtMs,
        'updated_at_ms': updatedAtMs
      };
}

class Exercise {
  final String id;
  final String? ownerUserId;
  final String? disciplineId;
  final String name;
  final String? description;
  final String? movementPattern;
  final bool isArchived;
  final int createdAtMs;
  final int updatedAtMs;

  Exercise({required this.id, this.ownerUserId, this.disciplineId, required this.name, this.description, this.movementPattern, this.isArchived = false, required this.createdAtMs, required this.updatedAtMs});

  factory Exercise.fromMap(Map<String, dynamic> m) => Exercise(
      id: m['id'] as String,
      ownerUserId: m['owner_user_id'] as String?,
      disciplineId: m['discipline_id'] as String?,
      name: m['name'] as String,
      description: m['description'] as String?,
      movementPattern: m['movement_pattern'] as String?,
      isArchived: (m['is_archived'] as int?) == 1,
      createdAtMs: m['created_at_ms'] as int,
      updatedAtMs: m['updated_at_ms'] as int);

  Map<String, dynamic> toMap() => {
        'id': id,
        'owner_user_id': ownerUserId,
        'discipline_id': disciplineId,
        'name': name,
        'description': description,
        'movement_pattern': movementPattern,
        'is_archived': isArchived ? 1 : 0,
        'created_at_ms': createdAtMs,
        'updated_at_ms': updatedAtMs
      };
}

class Equipment {
  final String id;
  final String name;
  final int createdAtMs;

  Equipment({required this.id, required this.name, required this.createdAtMs});

  factory Equipment.fromMap(Map<String, dynamic> m) => Equipment(id: m['id'] as String, name: m['name'] as String, createdAtMs: m['created_at_ms'] as int);

  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'created_at_ms': createdAtMs};
}

class TrainingSession {
  final String id;
  final String ownerUserId;
  final int startedAtMs;
  final int? endedAtMs;
  final String? title;
  final String? note;
  final String? locationText;
  final double? perceivedSessionRpe;
  final int createdAtMs;
  final int updatedAtMs;

  TrainingSession({required this.id, required this.ownerUserId, required this.startedAtMs, this.endedAtMs, this.title, this.note, this.locationText, this.perceivedSessionRpe, required this.createdAtMs, required this.updatedAtMs});

  factory TrainingSession.fromMap(Map<String, dynamic> m) => TrainingSession(
      id: m['id'] as String,
      ownerUserId: m['owner_user_id'] as String,
      startedAtMs: m['started_at_ms'] as int,
      endedAtMs: m['ended_at_ms'] as int?,
      title: m['title'] as String?,
      note: m['note'] as String?,
      locationText: m['location_text'] as String?,
      perceivedSessionRpe: (m['perceived_session_rpe'] as num?)?.toDouble(),
      createdAtMs: m['created_at_ms'] as int,
      updatedAtMs: m['updated_at_ms'] as int);

  Map<String, dynamic> toMap() => {
        'id': id,
        'owner_user_id': ownerUserId,
        'started_at_ms': startedAtMs,
        'ended_at_ms': endedAtMs,
        'title': title,
        'note': note,
        'location_text': locationText,
        'perceived_session_rpe': perceivedSessionRpe,
        'created_at_ms': createdAtMs,
        'updated_at_ms': updatedAtMs
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

  SessionSegment({required this.id, required this.sessionId, required this.orderIndex, required this.segmentType, this.disciplineId, this.name, this.note, required this.createdAtMs, required this.updatedAtMs});

  factory SessionSegment.fromMap(Map<String, dynamic> m) => SessionSegment(
      id: m['id'] as String,
      sessionId: m['session_id'] as String,
      orderIndex: m['order_index'] as int,
      segmentType: m['segment_type'] as String,
      disciplineId: m['discipline_id'] as String?,
      name: m['name'] as String?,
      note: m['note'] as String?,
      createdAtMs: m['created_at_ms'] as int,
      updatedAtMs: m['updated_at_ms'] as int);

  Map<String, dynamic> toMap() => {
        'id': id,
        'session_id': sessionId,
        'order_index': orderIndex,
        'segment_type': segmentType,
        'discipline_id': disciplineId,
        'name': name,
        'note': note,
        'created_at_ms': createdAtMs,
        'updated_at_ms': updatedAtMs
      };
}

class SegmentEffort {
  final String id;
  final String segmentId;
  final int orderIndex;
  final String effortKind;
  final String? exerciseId;
  final String? note;
  final int createdAtMs;
  final int updatedAtMs;

  SegmentEffort({required this.id, required this.segmentId, required this.orderIndex, required this.effortKind, this.exerciseId, this.note, required this.createdAtMs, required this.updatedAtMs});

  factory SegmentEffort.fromMap(Map<String, dynamic> m) => SegmentEffort(
      id: m['id'] as String,
      segmentId: m['segment_id'] as String,
      orderIndex: m['order_index'] as int,
      effortKind: m['effort_kind'] as String,
      exerciseId: m['exercise_id'] as String?,
      note: m['note'] as String?,
      createdAtMs: m['created_at_ms'] as int,
      updatedAtMs: m['updated_at_ms'] as int);

  Map<String, dynamic> toMap() => {
        'id': id,
        'segment_id': segmentId,
        'order_index': orderIndex,
        'effort_kind': effortKind,
        'exercise_id': exerciseId,
        'note': note,
        'created_at_ms': createdAtMs,
        'updated_at_ms': updatedAtMs
      };
}

class UnitModel {
  final String id;
  final String key;
  final String name;
  final String? unitType;
  final int createdAtMs;

  UnitModel({required this.id, required this.key, required this.name, this.unitType, required this.createdAtMs});

  factory UnitModel.fromMap(Map<String, dynamic> m) => UnitModel(id: m['id'] as String, key: m['key'] as String, name: m['name'] as String, unitType: m['unit_type'] as String?, createdAtMs: m['created_at_ms'] as int);

  Map<String, dynamic> toMap() => {'id': id, 'key': key, 'name': name, 'unit_type': unitType, 'created_at_ms': createdAtMs};
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

  MetricDefinition({required this.id, required this.key, required this.name, required this.dataType, this.defaultUnitId, this.isCore = false, this.appliesToEffortKind, required this.createdAtMs});

  factory MetricDefinition.fromMap(Map<String, dynamic> m) => MetricDefinition(
      id: m['id'] as String,
      key: m['key'] as String,
      name: m['name'] as String,
      dataType: m['data_type'] as String,
      defaultUnitId: m['default_unit_id'] as String?,
      isCore: (m['is_core'] as int?) == 1,
      appliesToEffortKind: m['applies_to_effort_kind'] as String?,
      createdAtMs: m['created_at_ms'] as int);

  Map<String, dynamic> toMap() => {
        'id': id,
        'key': key,
        'name': name,
        'data_type': dataType,
        'default_unit_id': defaultUnitId,
        'is_core': isCore ? 1 : 0,
        'applies_to_effort_kind': appliesToEffortKind,
        'created_at_ms': createdAtMs
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
  final int createdAtMs;
  final int updatedAtMs;

  EffortObservation({required this.id, required this.effortId, required this.metricId, this.unitId, this.valueInt, this.valueReal, this.valueText, this.valueBool, required this.createdAtMs, required this.updatedAtMs});

  factory EffortObservation.fromMap(Map<String, dynamic> m) => EffortObservation(
      id: m['id'] as String,
      effortId: m['effort_id'] as String,
      metricId: m['metric_id'] as String,
      unitId: m['unit_id'] as String?,
      valueInt: m['value_int'] as int?,
      valueReal: (m['value_real'] as num?)?.toDouble(),
      valueText: m['value_text'] as String?,
      valueBool: (m['value_bool'] as int?) == 1,
      createdAtMs: m['created_at_ms'] as int,
      updatedAtMs: m['updated_at_ms'] as int);

  Map<String, dynamic> toMap() => {
        'id': id,
        'effort_id': effortId,
        'metric_id': metricId,
        'unit_id': unitId,
        'value_int': valueInt,
        'value_real': valueReal,
        'value_text': valueText,
        'value_bool': valueBool == true ? 1 : 0,
        'created_at_ms': createdAtMs,
        'updated_at_ms': updatedAtMs
      };
}

class WorkoutTemplate {
  final String id;
  final String? ownerUserId;
  final String name;
  final String? primaryDisciplineId;
  final String? note;
  final int createdAtMs;
  final int updatedAtMs;

  WorkoutTemplate({required this.id, this.ownerUserId, required this.name, this.primaryDisciplineId, this.note, required this.createdAtMs, required this.updatedAtMs});

  factory WorkoutTemplate.fromMap(Map<String, dynamic> m) => WorkoutTemplate(
      id: m['id'] as String,
      ownerUserId: m['owner_user_id'] as String?,
      name: m['name'] as String,
      primaryDisciplineId: m['primary_discipline_id'] as String?,
      note: m['note'] as String?,
      createdAtMs: m['created_at_ms'] as int,
      updatedAtMs: m['updated_at_ms'] as int);

  Map<String, dynamic> toMap() => {
        'id': id,
        'owner_user_id': ownerUserId,
        'name': name,
        'primary_discipline_id': primaryDisciplineId,
        'note': note,
        'created_at_ms': createdAtMs,
        'updated_at_ms': updatedAtMs
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

  TemplateSegment({required this.id, required this.templateId, required this.orderIndex, required this.segmentType, this.disciplineId, this.name, this.note, required this.createdAtMs});

  factory TemplateSegment.fromMap(Map<String, dynamic> m) => TemplateSegment(
      id: m['id'] as String,
      templateId: m['template_id'] as String,
      orderIndex: m['order_index'] as int,
      segmentType: m['segment_type'] as String,
      disciplineId: m['discipline_id'] as String?,
      name: m['name'] as String?,
      note: m['note'] as String?,
      createdAtMs: m['created_at_ms'] as int);

  Map<String, dynamic> toMap() => {
        'id': id,
        'template_id': templateId,
        'order_index': orderIndex,
        'segment_type': segmentType,
        'discipline_id': disciplineId,
        'name': name,
        'note': note,
        'created_at_ms': createdAtMs
      };
}

class TemplateEffort {
  final String id;
  final String templateSegmentId;
  final int orderIndex;
  final String effortKind;
  final String? exerciseId;
  final String? note;
  final int createdAtMs;

  TemplateEffort({required this.id, required this.templateSegmentId, required this.orderIndex, required this.effortKind, this.exerciseId, this.note, required this.createdAtMs});

  factory TemplateEffort.fromMap(Map<String, dynamic> m) => TemplateEffort(
      id: m['id'] as String,
      templateSegmentId: m['template_segment_id'] as String,
      orderIndex: m['order_index'] as int,
      effortKind: m['effort_kind'] as String,
      exerciseId: m['exercise_id'] as String?,
      note: m['note'] as String?,
      createdAtMs: m['created_at_ms'] as int);

  Map<String, dynamic> toMap() => {
        'id': id,
        'template_segment_id': templateSegmentId,
        'order_index': orderIndex,
        'effort_kind': effortKind,
        'exercise_id': exerciseId,
        'note': note,
        'created_at_ms': createdAtMs
      };
}

class TemplateTarget {
  final String id;
  final String templateEffortId;
  final String metricId;
  final String? unitId;
  final double? targetMin;
  final double? targetMax;
  final int? targetInt;
  final String? targetText;
  final int createdAtMs;

  TemplateTarget({required this.id, required this.templateEffortId, required this.metricId, this.unitId, this.targetMin, this.targetMax, this.targetInt, this.targetText, required this.createdAtMs});

  factory TemplateTarget.fromMap(Map<String, dynamic> m) => TemplateTarget(
      id: m['id'] as String,
      templateEffortId: m['template_effort_id'] as String,
      metricId: m['metric_id'] as String,
      unitId: m['unit_id'] as String?,
      targetMin: (m['target_min'] as num?)?.toDouble(),
      targetMax: (m['target_max'] as num?)?.toDouble(),
      targetInt: m['target_int'] as int?,
      targetText: m['target_text'] as String?,
      createdAtMs: m['created_at_ms'] as int);

  Map<String, dynamic> toMap() => {
        'id': id,
        'template_effort_id': templateEffortId,
        'metric_id': metricId,
        'unit_id': unitId,
        'target_min': targetMin,
        'target_max': targetMax,
        'target_int': targetInt,
        'target_text': targetText,
        'created_at_ms': createdAtMs
      };
}

class Tag {
  final String id;
  final String name;
  final int createdAtMs;

  Tag({required this.id, required this.name, required this.createdAtMs});

  factory Tag.fromMap(Map<String, dynamic> m) => Tag(id: m['id'] as String, name: m['name'] as String, createdAtMs: m['created_at_ms'] as int);

  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'created_at_ms': createdAtMs};
}

// Lightweight SetRow used by UI for logging sets. Kept separate from the
// typed observation rows in the DB layer for simplicity.
class SetRow {
  final String id;
  final String exerciseId;
  int reps;
  double weight;
  int duration; // seconds
  final int timestamp;

  SetRow({required this.id, required this.exerciseId, required this.reps, required this.weight, required this.duration, required this.timestamp});

  factory SetRow.fromMap(Map<String, dynamic> m) => SetRow(
      id: m['id'] as String,
      exerciseId: m['exercise_id'] as String,
      reps: m['reps'] as int,
      weight: (m['weight'] as num).toDouble(),
      duration: m['duration'] as int,
      timestamp: m['timestamp'] as int);

  Map<String, dynamic> toMap() => {
        'id': id,
        'exercise_id': exerciseId,
        'reps': reps,
        'weight': weight,
        'duration': duration,
        'timestamp': timestamp
      };
}
