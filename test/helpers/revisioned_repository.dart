// A repository double that answers a settable revision and counts the reads
// the phone makes from it.
//
// Plan 74 (`test/watch_sync_idle_reads_test.dart`, S-10405..S-10411) counts the
// reference side: `referenceRevision` and the foods, routines and exercise
// reads. Plan 87c adds the history side: `historyRevision` and the session
// reads the bests walk makes (S-87c-1..S-87c-14).

import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';

/// A [MockWorkoutRepository] whose two revisions are settable and whose reads
/// are counted.
class RevisionedRepository extends MockWorkoutRepository {
  /// The number [referenceRevision] answers.
  int? revision = 1;

  /// The number [historyRevision] answers; null is "cannot tell", the Mock's
  /// own answer.
  int? history = 1;

  int foodReads = 0;
  int groupReads = 0;
  int templateReads = 0;
  int segmentReads = 0;
  int exerciseReads = 0;
  int capabilityReads = 0;
  int sessionReads = 0;

  /// Bumps [history] by one on every session read, simulating a write landing
  /// while the phone walks the history (S-87c-12).
  bool bumpHistoryOnRead = false;

  /// When set, the next food read throws once and the flag clears itself.
  bool throwOnceOnFoods = false;

  void resetCounts() {
    foodReads = 0;
    groupReads = 0;
    templateReads = 0;
    segmentReads = 0;
    exerciseReads = 0;
    capabilityReads = 0;
    sessionReads = 0;
  }

  @override
  int? get referenceRevision => revision;

  @override
  int? get historyRevision => history;

  @override
  Future<List<TrainingSession>> getAllSessions() async {
    sessionReads++;
    if (bumpHistoryOnRead) history = (history ?? 0) + 1;
    return super.getAllSessions();
  }

  @override
  Future<List<Food>> getFoods({bool includeArchived = false}) async {
    foodReads++;
    if (throwOnceOnFoods) {
      throwOnceOnFoods = false;
      throw Exception('food read failed once');
    }
    return super.getFoods(includeArchived: includeArchived);
  }

  @override
  Future<List<FoodGroup>> getFoodGroups({bool includeArchived = false}) async {
    groupReads++;
    return super.getFoodGroups(includeArchived: includeArchived);
  }

  @override
  Future<List<WorkoutTemplate>> getTemplates() async {
    templateReads++;
    return super.getTemplates();
  }

  @override
  Future<List<TemplateSegment>> getTemplateSegments(String templateId) async {
    segmentReads++;
    return super.getTemplateSegments(templateId);
  }

  @override
  Future<List<Exercise>> getExercises() async {
    exerciseReads++;
    return super.getExercises();
  }

  @override
  Future<List<String>> getExerciseCapabilities(String exerciseId) async {
    capabilityReads++;
    return super.getExerciseCapabilities(exerciseId);
  }
}
