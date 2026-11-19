// filepath: lib/core/services/health_effort_mapper.dart
//
// The session effort rating as Apple's Workout Effort (plan 90 D-2).
//
// OmniTrain rates a session 1 to 5 (`TrainingSession.sessionFeeling`, 1 = very
// easy, 5 = max effort); Fitness shows a workout's effort 1 to 10. Each step of
// the rating is two steps of Apple's scale (OQ-1), so very easy is 2 and max
// effort is 10. Pinned by `test/health_effort_test.dart` (S-90-1).

/// Apple's Workout Effort score for a session [rating], or null when the
/// rating is outside 1 to 5.
int? ratingToAppleEffort(int rating) {
  if (rating < 1 || rating > 5) return null;
  return rating * 2;
}
