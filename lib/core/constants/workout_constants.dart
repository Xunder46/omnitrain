/// Application-wide constants for workout tracking
class WorkoutConstants {
  /// Default planned duration for round-based exercises (in seconds)
  static const int defaultRoundDurationSecs = 180; // 3 minutes

  /// Cap multiplier for round actual duration (safety margin for clock drift).
  /// When a round is ended early via wall-clock elapsed, the actual duration
  /// is clamped to [plannedDurationSecs * roundActualDurationCapFactor]
  /// to guard against device sleep, pause-time rounding, and clock skew.
  /// Example: 180s planned → max 360s actual permitted.
  static const int roundActualDurationCapFactor = 2;
}
