// Plan 119, Phase 3A — S-19311: the phone Health kind.
//
// A completed session whose exercises are all under the Yoga discipline records
// as Yoga on the phone's health store (D-19313); a mixed session, a session
// naming an exercise the store does not know, and an empty session keep the
// modality mapping; a Free session of poses is Yoga too. The rig is the one of
// `test/health_platform_test.dart` over the in-memory store — the writer reads
// the session's segments and efforts from the repository, so one implementation
// is enough — and no widget is pumped, so these run as plain `test()`.
//
// `docs/plans/2026-11-05-119-yoga-catalog-plan/2026-11-05-119-yoga-catalog-plan.md`.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/health_constants.dart';
import 'package:omnitrain/core/constants/modality.dart';
import 'package:omnitrain/core/services/health_platform_service.dart';
import 'package:omnitrain/core/services/health_sync_service.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

/// Test double standing in for the platform gateway (HealthKit /
/// Health Connect), recording every write.
class _FakeHealthPlatform implements HealthPlatformService {
  final List<HealthWorkoutDraft> writtenWorkouts = [];

  @override
  Future<bool> requestWritePermission() async => true;

  @override
  Future<bool> requestReadPermission() async => true;

  @override
  Future<bool> writeWorkout(HealthWorkoutDraft workout) async {
    writtenWorkouts.add(workout);
    return true;
  }

  @override
  Future<bool> deleteWorkouts(DateTime start, DateTime end) async => true;

  @override
  Future<HealthEffortOutcome> setWorkoutEffort(
    DateTime start,
    DateTime end,
    int score,
  ) async => HealthEffortOutcome.unavailable;

  @override
  Future<bool> clearWorkoutEffort(DateTime start, DateTime end) async => false;

  @override
  Future<List<HealthWeightSample>> readBodyWeightSince(DateTime since) async =>
      const [];
}

/// One wired app fragment: repository + settings + sync service + workout
/// state, all sharing the same fake platform — the shape of
/// `test/health_platform_test.dart`'s `_Rig`.
class _Rig {
  final MockWorkoutRepository repo;
  final SettingsState settings;
  final _FakeHealthPlatform platform;
  final HealthSyncService sync;
  final WorkoutState workoutState;

  _Rig._({
    required this.repo,
    required this.settings,
    required this.platform,
    required this.sync,
    required this.workoutState,
  });

  static Future<_Rig> create({bool writeEnabled = false}) async {
    final repo = await _freshRepo();
    final platform = _FakeHealthPlatform();
    final settings = SettingsState(
      repo,
      fakePreferencesService(),
      healthPlatform: platform,
    );
    await settings.initialize();
    if (writeEnabled) {
      await settings.setHealthWriteWorkoutsEnabled(true);
    }
    final sync = HealthSyncService(
      platform: platform,
      repository: repo,
      isWriteEnabled: () =>
          settings.healthWriteWorkouts == HealthToggleState.on,
      isReadEnabled: () =>
          settings.healthReadBodyWeight == HealthToggleState.on,
    );
    final workoutState = WorkoutState(repo, healthSync: sync);
    return _Rig._(
      repo: repo,
      settings: settings,
      platform: platform,
      sync: sync,
      workoutState: workoutState,
    );
  }

  /// Adds the bundled exercise [id] to the running session.
  Future<void> addExercise(String id) async {
    final exercise = (await repo.getExerciseById(id))!;
    await workoutState.addExerciseToSession(exercise);
  }

  /// The activity kind of the one workout this session wrote.
  HealthActivityKind get writtenKind {
    expect(writtenWorkouts, hasLength(1), reason: 'one workout per session');
    return writtenWorkouts.single.activityKind;
  }

  List<HealthWorkoutDraft> get writtenWorkouts => platform.writtenWorkouts;
}

void main() {
  group('S-19311 the phone Health kind', () {
    test('A: a session of poses records as yoga', () async {
      final rig = await _Rig.create(writeEnabled: true);
      await rig.workoutState.createNewSession(
        modality: Modality.isometricStretching,
      );
      await rig.addExercise('exercise-mountain-pose');
      await rig.addExercise('exercise-mountain-pose');
      await rig.workoutState.endSession();

      expect(rig.writtenKind, equals(HealthActivityKind.yoga));
    });

    test('B: a mixed session keeps the modality mapping', () async {
      final rig = await _Rig.create(writeEnabled: true);
      await rig.workoutState.createNewSession(
        modality: Modality.isometricStretching,
      );
      await rig.addExercise('exercise-mountain-pose');
      await rig.addExercise('exercise-rowing-intervals');
      await rig.workoutState.endSession();

      expect(rig.writtenKind, equals(HealthActivityKind.flexibility));
    });

    test('C: an unknown exercised row keeps the modality mapping', () async {
      final rig = await _Rig.create(writeEnabled: true);
      await rig.workoutState.createNewSession(
        modality: Modality.isometricStretching,
      );
      await rig.addExercise('exercise-mountain-pose');
      // The effort names a row the store no longer holds: an absent discipline
      // is not a Yoga discipline, so the session is not all-Yoga.
      await rig.repo.deleteExercise('exercise-mountain-pose');
      await rig.workoutState.endSession();

      expect(rig.writtenKind, equals(HealthActivityKind.flexibility));
    });

    test('D: an empty session keeps the modality mapping', () async {
      final rig = await _Rig.create(writeEnabled: true);
      await rig.workoutState.createNewSession(
        modality: Modality.isometricStretching,
      );
      await rig.workoutState.endSession();

      expect(rig.writtenKind, equals(HealthActivityKind.flexibility));
    });

    test('E: a Free session of poses records as yoga', () async {
      final rig = await _Rig.create(writeEnabled: true);
      await rig.workoutState.createNewSession();
      await rig.addExercise('exercise-tree-pose');
      await rig.workoutState.endSession();

      expect(rig.writtenKind, equals(HealthActivityKind.yoga));
    });
  });
}
