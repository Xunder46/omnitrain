/// Block type constants for segment_type and effort_kind
/// These define how work is structured and which metrics are logged

class BlockTypes {
  // Segment types (used in app_session_segment.segment_type)
  static const String strengthSets = 'strength_sets';
  static const String timedActivity = 'timed_activity';
  static const String distanceIntervals = 'distance_intervals';
  static const String roundBased = 'round_based';
  static const String amrapForTime = 'amrap_for_time';
  static const String drillSkill = 'drill_skill';
  static const String freeform = 'freeform';

  // Effort kinds (used in app_segment_effort.effort_kind)
  // In most cases, effort_kind matches segment_type
  static const String set = 'set'; // Individual set within strength_sets
  static const String interval = 'interval'; // Individual interval within distance_intervals
  static const String round = 'round'; // Individual round within round_based
  static const String timed = 'timed'; // For timed_activity
  static const String amrap = 'amrap'; // For amrap_for_time
  static const String drill = 'drill'; // For drill_skill
  static const String note = 'note'; // For freeform

  static const List<String> allSegmentTypes = [
    strengthSets,
    timedActivity,
    distanceIntervals,
    roundBased,
    amrapForTime,
    drillSkill,
    freeform,
  ];

  static const List<String> allEffortKinds = [
    set,
    interval,
    round,
    timed,
    amrap,
    drill,
    note,
  ];
}
