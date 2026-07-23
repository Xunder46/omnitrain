import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/capability.dart';
import 'package:omnitrain/core/constants/catalog_version.dart';
import 'package:omnitrain/core/models/demo_routine_spec.dart';
import 'package:omnitrain/core/services/catalog_refresh_service.dart';
import 'package:omnitrain/core/services/catalog_source.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/core/utils/exercise_helpers.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/mock/food_catalog_seed.dart';
import 'package:omnitrain/mock/seed_data.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

/// A [CatalogSource] whose bundled catalog can be supplied directly,
/// independent of [SeedData]. Lets tests stage the "old vs new catalog"
/// scenario without rebuilding the seed data.
class _FakeCatalogSource implements CatalogSource {
  _FakeCatalogSource({
    required this.version,
    required this.exercises,
    required this.exerciseCapabilities,
    required this.exerciseMuscleGroups,
    required this.foodCatalog,
    this.routineTemplates = const [],
  });

  @override
  final int version;

  @override
  final List<Exercise> exercises;

  @override
  final Map<String, List<String>> exerciseCapabilities;

  @override
  final Map<String, List<String>> exerciseMuscleGroups;

  @override
  final List<Food> foodCatalog;

  @override
  final List<DemoRoutineBundle> routineTemplates;
}

CatalogSource _bundledSource() {
  return _FakeCatalogSource(
    version: bundledCatalogVersion,
    exercises: SeedData.sampleExercises,
    exerciseCapabilities: SeedData.exerciseCapabilityRelationships,
    exerciseMuscleGroups: SeedData.exerciseMuscleGroupRelationships,
    foodCatalog: FoodCatalogSeed.sampleCatalogFoods,
  );
}

/// A repo that throws on the SECOND `setExerciseCapabilities` call (the
/// first call is the test setup that strips `bilateral` from the seed
/// entry; the second call is the refresh's corrective write). Models a
/// real mid-refresh failure where the first write succeeds but the second
/// fails (e.g. a transient I/O error).
class _OnceThrowingRepo extends MockWorkoutRepository {
  _OnceThrowingRepo();

  int _callCount = 0;

  @override
  Future<void> setExerciseCapabilities(
    String exerciseId,
    List<String> capabilities,
  ) async {
    _callCount++;
    if (_callCount == 2) {
      throw StateError('simulated mid-refresh failure');
    }
    return super.setExerciseCapabilities(exerciseId, capabilities);
  }
}

void main() {
  group('CatalogRefreshService', () {
    // ─────────────────────────────────────────────────────────────────────
    // S-001: version gating — no refresh when versions match
    // ─────────────────────────────────────────────────────────────────────
    test('S-001: no refresh when stored version equals bundled version', () async {
      final repo = MockWorkoutRepository();
      await repo.initialize();

      await repo.setCatalogVersion(bundledCatalogVersion);

      final service = CatalogRefreshService(repo, _bundledSource());
      final didRefresh = await service.refresh();

      expect(didRefresh, isFalse);
      expect(
        await repo.getCatalogVersion(),
        equals(bundledCatalogVersion),
        reason: 'stored version must not change when no refresh runs',
      );
    });

    test(
      'S-001b: stored version above bundled version is treated as no-op',
      () async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        await repo.setCatalogVersion(bundledCatalogVersion + 10);

        final service = CatalogRefreshService(repo, _bundledSource());
        final didRefresh = await service.refresh();

        expect(didRefresh, isFalse);
      },
    );

    // ─────────────────────────────────────────────────────────────────────
    // S-002: catalog change reaches existing install (bilateral arrives)
    // ─────────────────────────────────────────────────────────────────────
    test(
      'S-002: missing seed capability on existing install is added by refresh',
      () async {
        final repo = MockWorkoutRepository();
        await repo.initialize();

        // Simulate an "old" device: stored version is one behind, and the
        // bilateral capability is missing from the seed entry that ships
        // with the bundled catalog.
        await repo.setCatalogVersion(bundledCatalogVersion - 1);
        const dumbbellCurlId = 'exercise-dumbbell-curl';
        final preRefreshCaps = await repo.getExerciseCapabilities(
          dumbbellCurlId,
        );
        expect(
          preRefreshCaps,
          contains(ExerciseCapability.bilateral),
          reason:
              'bundled seed should contain bilateral; if this fails, the '
              'scenario setup is wrong',
        );
        // Strip bilateral without setting a tombstone: this models a
        // device that simply hasn't received the new flag yet.
        await repo.setExerciseCapabilities(
          dumbbellCurlId,
          preRefreshCaps
              .where((c) => c != ExerciseCapability.bilateral)
              .toList(),
        );
        expect(
          await repo.getExerciseCapabilities(dumbbellCurlId),
          isNot(contains(ExerciseCapability.bilateral)),
          reason: 'setup must produce a device without the bilateral flag',
        );

        final service = CatalogRefreshService(repo, _bundledSource());
        final didRefresh = await service.refresh();

        expect(didRefresh, isTrue);
        expect(
          await repo.getExerciseCapabilities(dumbbellCurlId),
          contains(ExerciseCapability.bilateral),
          reason: 'refresh must add the missing capability to the device',
        );
        expect(
          await repo.getCatalogVersion(),
          equals(bundledCatalogVersion),
          reason: 'stored version must advance to the bundled version',
        );
      },
    );

    // ─────────────────────────────────────────────────────────────────────
    // S-003: user-created entry is preserved
    // ─────────────────────────────────────────────────────────────────────
    test('S-003: a user-created exercise is not touched by the refresh', () async {
      final repo = MockWorkoutRepository();
      await repo.initialize();
      await repo.setCatalogVersion(bundledCatalogVersion - 1);

      final now = DateTime.now().millisecondsSinceEpoch;
      const userId = 'exercise-user-custom-squat';
      await repo.createExercise(
        Exercise(
          id: userId,
          name: 'My Custom Squat',
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );
      await repo.setExerciseCapabilities(userId, const ['reps', 'sets']);
      final before = await repo.getExerciseById(userId);

      final service = CatalogRefreshService(repo, _bundledSource());
      await service.refresh();

      final after = await repo.getExerciseById(userId);
      expect(after, isNotNull);
      expect(after!.name, equals('My Custom Squat'));
      expect(after.capabilities, equals(const ['reps', 'sets']));
      expect(after.createdAtMs, equals(before!.createdAtMs));
      expect(
        await repo.isSeedEntryTouched(SeedEntryType.exercise, userId),
        isFalse,
        reason: 'a user-created entry must never be tombstoned by refresh',
      );
    });

    test('S-003b: a user-created food is not touched by the refresh', () async {
      final repo = MockWorkoutRepository();
      await repo.initialize();
      await repo.setCatalogVersion(bundledCatalogVersion - 1);

      final now = DateTime.now().millisecondsSinceEpoch;
      const userFoodId = 'food-user-mine-1';
      await repo.createFood(
        Food(
          id: userFoodId,
          name: 'My Recipe',
          unitType: FoodUnitType.grams,
          referenceAmount: 100,
          referenceLabel: 'g',
          protein: 12,
          carbs: 30,
          fat: 5,
          isCatalog: false,
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );

      final service = CatalogRefreshService(repo, _bundledSource());
      await service.refresh();

      final after = await repo.getFoodById(userFoodId);
      expect(after, isNotNull);
      expect(after!.name, equals('My Recipe'));
      expect(after.protein, equals(12));
    });

    // ─────────────────────────────────────────────────────────────────────
    // S-004: user-edited seed entry is not overwritten
    // ─────────────────────────────────────────────────────────────────────
    test(
      'S-004: a seed entry the user has edited is not overwritten by the refresh',
      () async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        await repo.setCatalogVersion(bundledCatalogVersion - 1);

        const dumbbellCurlId = 'exercise-dumbbell-curl';
        final original = await repo.getExerciseById(dumbbellCurlId);
        expect(original, isNotNull);
        await repo.updateExercise(
          original!.copyWith(name: 'DB Curl (mine)'),
        );
        await repo.markSeedEntryTouched(
          SeedEntryType.exercise,
          dumbbellCurlId,
        );

        final service = CatalogRefreshService(repo, _bundledSource());
        await service.refresh();

        final after = await repo.getExerciseById(dumbbellCurlId);
        expect(after, isNotNull);
        expect(
          after!.name,
          equals('DB Curl (mine)'),
          reason: 'user-edited seed entry must retain its user-provided name',
        );
      },
    );

    test(
      'S-004b: a user-edited catalog food is not overwritten by the refresh',
      () async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        await repo.setCatalogVersion(bundledCatalogVersion - 1);

        const eggId = 'egg';
        final original = await repo.getCatalogFoodById(eggId);
        expect(original, isNotNull);
        await repo.updateCatalogFood(
          original!.copyWith(name: 'My Eggs', protein: 7),
        );
        await repo.markSeedEntryTouched(
          SeedEntryType.foodCatalog,
          eggId,
        );

        final service = CatalogRefreshService(repo, _bundledSource());
        await service.refresh();

        final after = await repo.getCatalogFoodById(eggId);
        expect(after, isNotNull);
        expect(after!.name, equals('My Eggs'));
        expect(after.protein, equals(7));
      },
    );

    // ─────────────────────────────────────────────────────────────────────
    // S-005: idempotency
    // ─────────────────────────────────────────────────────────────────────
    test(
      'S-005: running refresh twice yields identical state with no duplicates',
      () async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        await repo.setCatalogVersion(bundledCatalogVersion - 1);

        final exercisesBefore = await repo.getExercises();
        final catalogFoodsBefore = await repo.getCatalogFoods();

        final service = CatalogRefreshService(repo, _bundledSource());
        final firstRefresh = await service.refresh();
        final exercisesAfterFirst = await repo.getExercises();
        final catalogAfterFirst = await repo.getCatalogFoods();

        expect(firstRefresh, isTrue);
        expect(
          exercisesAfterFirst.length,
          equals(exercisesBefore.length),
          reason: 'no exercise ids should be added beyond what was already '
              'on the device',
        );
        expect(catalogAfterFirst.length, equals(catalogFoodsBefore.length));

        final secondRefresh = await service.refresh();
        expect(secondRefresh, isFalse);

        final exercisesAfterSecond = await repo.getExercises();
        final catalogAfterSecond = await repo.getCatalogFoods();
        expect(exercisesAfterSecond.length, equals(exercisesAfterFirst.length));
        expect(catalogAfterSecond.length, equals(catalogAfterFirst.length));
        final firstIds = exercisesAfterFirst.map((e) => e.id).toSet();
        final secondIds = exercisesAfterSecond.map((e) => e.id).toSet();
        expect(secondIds, equals(firstIds));
      },
    );

    // ─────────────────────────────────────────────────────────────────────
    // S-006: interruption safety
    // ─────────────────────────────────────────────────────────────────────
    test(
      'S-006: a mid-refresh failure leaves prior data intact and the stored '
      'version is not advanced',
      () async {
        final repo = _OnceThrowingRepo();
        await repo.initialize();
        await repo.setCatalogVersion(bundledCatalogVersion - 1);

        const dumbbellCurlId = 'exercise-dumbbell-curl';
        final preCaps = await repo.getExerciseCapabilities(dumbbellCurlId);
        await repo.setExerciseCapabilities(
          dumbbellCurlId,
          preCaps.where((c) => c != ExerciseCapability.bilateral).toList(),
        );
        final storedVersionBefore = await repo.getCatalogVersion();

        final service = CatalogRefreshService(repo, _bundledSource());

        Object? caughtError;
        try {
          await service.refresh();
        } catch (e) {
          caughtError = e;
        }
        expect(
          caughtError,
          isNotNull,
          reason: 'refresh must propagate the simulated failure',
        );

        expect(
          await repo.getCatalogVersion(),
          equals(storedVersionBefore),
          reason: 'on failure the stored version must stay at the old value',
        );
        final postCaps = await repo.getExerciseCapabilities(dumbbellCurlId);
        expect(
          postCaps,
          isNot(contains(ExerciseCapability.bilateral)),
          reason: 'failed refresh must not leave partial state behind',
        );
      },
    );

    test(
      'S-006b: after a failed refresh the next launch retries from scratch',
      () async {
        final repo = _OnceThrowingRepo();
        await repo.initialize();
        await repo.setCatalogVersion(bundledCatalogVersion - 1);
        const dumbbellCurlId = 'exercise-dumbbell-curl';
        final preCaps = await repo.getExerciseCapabilities(dumbbellCurlId);
        await repo.setExerciseCapabilities(
          dumbbellCurlId,
          preCaps.where((c) => c != ExerciseCapability.bilateral).toList(),
        );

        final service = CatalogRefreshService(repo, _bundledSource());
        try {
          await service.refresh();
          fail('expected refresh to throw');
        } catch (_) {
          // Expected.
        }

        final secondRefresh = await service.refresh();
        expect(secondRefresh, isTrue);
        expect(
          await repo.getExerciseCapabilities(dumbbellCurlId),
          contains(ExerciseCapability.bilateral),
        );
      },
    );
  });

  // ────────────────────────────────────────────────────────────────────────
  // S-007: real catalog-loading path delivers the change (masking test)
  // ────────────────────────────────────────────────────────────────────────
  testWidgets(
    'S-007: bilateral note visible through the real startup path',
    (WidgetTester tester) async {
      final repository = MockWorkoutRepository();
      await repository.initialize();
      await repository.setCatalogVersion(bundledCatalogVersion - 1);
      const dumbbellCurlId = 'exercise-dumbbell-curl';
      final preCaps = await repository.getExerciseCapabilities(dumbbellCurlId);
      await repository.setExerciseCapabilities(
        dumbbellCurlId,
        preCaps.where((c) => c != ExerciseCapability.bilateral).toList(),
      );

      final refresh = CatalogRefreshService(repository, _bundledSource());
      await refresh.refresh();

      await repository.setPreferenceBool('hint_seen_exercise_info', true);
      await repository.setPreferenceBool('hint_seen_exercise_notes', true);
      final workoutState = WorkoutState(repository);
      final routineState = RoutineState(repository);
      final sessionSummaryService = SessionSummaryService(repository);
      await workoutState.createNewSession(modality: 'resistance_lifting');

      final bilateralExercise = (await workoutState
          .getExercisesRankedForModality(modality: 'resistance_lifting'))
          .firstWhere(
        (e) => e.capabilities.contains(ExerciseCapability.bilateral),
      );
      await workoutState.addExerciseToSession(
        bilateralExercise,
        chosenMetric: 'reps',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutSessionScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: sessionSummaryService,
            timerAlertService: FakeTimerAlertService(),
            settingsState: SettingsState(
              repository,
              fakePreferencesService(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(bilateralExercise.name));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('exercise-info-button')));
      await tester.pumpAndSettle();

      expect(find.text('LOGGING NOTE'), findsOneWidget);
      expect(
        find.textContaining('Log both sides as a single combined set'),
        findsOneWidget,
      );
    },
  );
}