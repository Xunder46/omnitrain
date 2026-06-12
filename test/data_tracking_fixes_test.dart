import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/services/routine_session_service.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/core/utils/unit_formatter.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/home/home_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'helpers/fake_preferences_service.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

/// Returns a [SettingsState] whose preferred weight unit is [unit] ('kg' or 'lbs').
Future<SettingsState> _settingsWithUnit(
  MockWorkoutRepository repo,
  String unit,
) async {
  final s = SettingsState(repo, fakePreferencesService());
  await s.setPreferredWeightUnit(unit);
  return s;
}

/// Seeds a completed session with one set-based effort directly into the repo.
/// All weights are assumed to be in canonical kg (post-fix format).
Future<TrainingSession> _buildCompletedSession(
  MockWorkoutRepository repo, {
  required String sessionId,
  required int startedAtMs,
  required int endedAtMs,
  required String exerciseId,
  required int reps,
  required double weightKg,
}) async {
  final session = TrainingSession(
    id: sessionId,
    ownerUserId: 'u-test',
    startedAtMs: startedAtMs,
    endedAtMs: endedAtMs,
    createdAtMs: startedAtMs,
    updatedAtMs: endedAtMs,
  );
  await repo.createSession(session);

  final segId = 'seg-$sessionId';
  await repo.createSegment(
    SessionSegment(
      id: segId,
      sessionId: sessionId,
      orderIndex: 0,
      segmentType: 'main',
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );

  final effortId = 'eff-$sessionId';
  await repo.createEffort(
    SegmentEffort(
      id: effortId,
      segmentId: segId,
      orderIndex: 0,
      effortKind: 'set',
      exerciseId: exerciseId,
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );

  await repo.createObservation(
    EffortObservation(
      id: 'obs-reps-$sessionId',
      effortId: effortId,
      metricId: 'metric-reps',
      valueInt: reps,
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );
  await repo.createObservation(
    EffortObservation(
      id: 'obs-weight-$sessionId',
      effortId: effortId,
      metricId: 'metric-weight',
      valueReal: weightKg,
      createdAtMs: startedAtMs + 1,
      updatedAtMs: startedAtMs + 1,
    ),
  );

  return session;
}

void main() {
  group('Data tracking fixes', () {
    test('maintenance hint persists across HomeState init cycles', () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();

      final firstState = HomeState(repository);
      await firstState.init();
      expect(firstState.shouldShowMaintenanceHint, isTrue);

      await firstState.markMaintenanceHintSeen();
      expect(firstState.shouldShowMaintenanceHint, isFalse);

      final secondState = HomeState(repository);
      await secondState.init();
      expect(secondState.shouldShowMaintenanceHint, isFalse);
    });

    test('skip marker persists and rehydrates on reload', () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();

      final state = WorkoutState(repository);
      await state.createNewSession();

      final exercise = (await repository.getExercises()).first;
      await state.addExerciseToSession(exercise, chosenMetric: 'reps');

      final effortId = state.getExercisesWithEntries().first['id'] as String;
      await state.markSetSkipped(effortId, 0);

      final inMemoryEntry =
          (state.getExercisesWithEntries().first['entries'] as List).first
              as Map<String, dynamic>;
      expect(inMemoryEntry['skipped'], isTrue);
      expect(inMemoryEntry['reps'], 0);

      final reloaded = WorkoutState(repository);
      await reloaded.loadHistoricalSession(state.currentSession!.id);

      final reloadedEntry =
          (reloaded.getExercisesWithEntries().first['entries'] as List).first
              as Map<String, dynamic>;
      expect(reloadedEntry['skipped'], isTrue);
      expect(reloadedEntry['reps'], 0);
    });

    test('skip marker clears when reps are later logged', () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();

      final state = WorkoutState(repository);
      await state.createNewSession();

      final exercise = (await repository.getExercises()).first;
      await state.addExerciseToSession(exercise, chosenMetric: 'reps');

      final effortId = state.getExercisesWithEntries().first['id'] as String;
      await state.markSetSkipped(effortId, 0);

      await state.updateEntryValue(effortId, 0, 'reps', 8);

      final entry =
          (state.getExercisesWithEntries().first['entries'] as List).first
              as Map<String, dynamic>;
      expect(entry['reps'], 8);
      expect(entry['skipped'], isFalse);

      final observations = await repository.getEffortObservations(effortId);
      final repsObs = observations.firstWhere((o) => o.metricId == 'metric-reps');
      expect(repsObs.valueInt, 8);
      expect(repsObs.valueBool, isFalse);
    });

    test('session RPE persists and rehydrates', () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();

      final state = WorkoutState(repository);
      await state.createNewSession();
      final sessionId = state.currentSession!.id;

      await state.updateSessionRpe(sessionId, 7.0);

      final persisted = await repository.getSession(sessionId);
      expect(persisted?.perceivedSessionRpe, 7.0);

      final reloaded = WorkoutState(repository);
      await reloaded.loadHistoricalSession(sessionId);
      expect(reloaded.currentSession?.perceivedSessionRpe, 7.0);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Volume calculation — regression tests for the lbs double-conversion bug.
  //
  // Root cause: weight observations were stored as the raw display value (lbs)
  // rather than canonical kg. SessionSummaryBuilder treats all stored weights
  // as kg, so a 100-lbs entry was counted as 100 kg, and the summary screen
  // applied another ×2.20462 conversion → ~220.4 lbs displayed instead of
  // 100 lbs. Fix: _updateMetricValue converts display→kg before persisting;
  // the display layer converts kg→display on read.
  // ══════════════════════════════════════════════════════════════════════════

  group('Volume calculation', () {
    const kgToLbs = 2.20462;

    // ── Single-exercise kg session ──────────────────────────────────────────

    test('single-exercise kg session: totalVolume is reps × weight in kg',
        () async {
      final repo = await _freshRepo();
      final exercises = await repo.getExercises();
      // Use _buildCompletedSession to avoid timestamp-collision issues in the
      // sequential observation grouper. One set × 10 reps × 100 kg = 1000 kg.
      final session = await _buildCompletedSession(
        repo,
        sessionId: 'kg-session',
        startedAtMs: 1000,
        endedAtMs: 2000,
        exerciseId: exercises.first.id,
        reps: 10,
        weightKg: 100.0,
      );

      final state = WorkoutState(repo);
      await state.loadHistoricalSession(session.id);
      final summary = state.computeSessionSummary();

      expect(summary.totalVolume, closeTo(1000.0, 0.01));
    });

    // ── Single-exercise lbs session ─────────────────────────────────────────

    test(
      'single-exercise lbs session: totalVolume in kg displays correctly in lbs',
      () async {
        final repo = await _freshRepo();
        final exercises = await repo.getExercises();
        final lbsSettings = await _settingsWithUnit(repo, 'lbs');

        // User sees 100 lbs in the editor. Screen converts to kg before storing:
        // 100 lbs / 2.20462 ≈ 45.359 kg.
        final weightKg = 100.0 / kgToLbs;
        final session = await _buildCompletedSession(
          repo,
          sessionId: 'lbs-session',
          startedAtMs: 1000,
          endedAtMs: 2000,
          exerciseId: exercises.first.id,
          reps: 10,
          weightKg: weightKg,
        );

        final state = WorkoutState(repo);
        await state.loadHistoricalSession(session.id);
        final summary = state.computeSessionSummary();

        // totalVolume must be in kg (10 × 45.359 ≈ 453.59 kg).
        expect(summary.totalVolume, closeTo(10 * weightKg, 0.01));

        // Formatted as lbs via the display layer → should equal 1000 lbs.
        final formatted = UnitFormatter.formatWeight(
          summary.totalVolume,
          lbsSettings,
          decimals: 1,
        );
        // 453.59 kg × 2.20462 ≈ 1000.0 lbs
        expect(formatted, contains('1000'));
        expect(formatted, contains('lbs'));
      },
    );

    // ── Regression: the old double-conversion must NOT occur ────────────────

    test(
      'regression: storing canonical kg never produces 2.2× inflation',
      () async {
        final repo = await _freshRepo();
        final exercises = await repo.getExercises();
        final lbsSettings = await _settingsWithUnit(repo, 'lbs');

        // Store 100 lbs converted to canonical kg (as the fixed screen does).
        final weightKg = 100.0 / kgToLbs;
        final session = await _buildCompletedSession(
          repo,
          sessionId: 'regression-session',
          startedAtMs: 1000,
          endedAtMs: 2000,
          exerciseId: exercises.first.id,
          reps: 10,
          weightKg: weightKg,
        );

        final state = WorkoutState(repo);
        await state.loadHistoricalSession(session.id);
        final summary = state.computeSessionSummary();

        final displayedLbs = UnitFormatter.convertWeight(
          summary.totalVolume,
          lbsSettings,
        );

        // Must be ~1000 lbs, not ~2204 lbs (the pre-fix inflated value).
        expect(displayedLbs, closeTo(1000.0, 1.0));
        expect(
          displayedLbs,
          lessThan(1100.0),
          reason: 'double-conversion would yield ~2204; got $displayedLbs',
        );
      },
    );

    // ── Multi-exercise session ───────────────────────────────────────────────

    test('multi-exercise session: totalVolume is summed across exercises',
        () async {
      final repo = await _freshRepo();
      final exercises = await repo.getExercises();

      final state = WorkoutState(repo);
      await state.createNewSession();

      // Exercise A: 1 set × 8 reps × 60 kg = 480
      final effortA = await state.addExerciseToSession(
        exercises[0],
        chosenMetric: 'reps',
      );
      await state.updateEntryValue(effortA, 0, 'reps', 8);
      await state.updateEntryValue(effortA, 0, 'weight', 60.0);

      // Exercise B: 1 set × 5 reps × 100 kg = 500
      final effortB = await state.addExerciseToSession(
        exercises[1],
        chosenMetric: 'reps',
      );
      await state.updateEntryValue(effortB, 0, 'reps', 5);
      await state.updateEntryValue(effortB, 0, 'weight', 100.0);

      await state.endSession();
      final summary = state.computeSessionSummary();

      expect(summary.totalVolume, closeTo(480.0 + 500.0, 0.01));
    });

    // ── Bilateral-capable exercise ───────────────────────────────────────────

    test(
      'bilateral-capable exercise: volume is not double-counted per side',
      () async {
        final repo = await _freshRepo();
        final exercises = await repo.getExercises();

        // Find an exercise with the bilateral capability (e.g. dumbbell row).
        final bilateral = exercises.firstWhere(
          (e) => e.capabilities.contains('bilateral'),
          orElse: () => exercises.first,
        );

        final state = WorkoutState(repo);
        await state.createNewSession();

        final effortId = await state.addExerciseToSession(
          bilateral,
          chosenMetric: 'reps',
        );
        // 1 set × 10 reps × 20 kg = 200 kg (NOT 400 kg).
        await state.updateEntryValue(effortId, 0, 'reps', 10);
        await state.updateEntryValue(effortId, 0, 'weight', 20.0);

        await state.endSession();
        final summary = state.computeSessionSummary();

        expect(
          summary.totalVolume,
          closeTo(200.0, 0.01),
          reason:
              'bilateral exercises must not be counted twice (expected 200, '
              'got ${summary.totalVolume})',
        );
      },
    );

    // ── Volume comparison delta for lbs user ─────────────────────────────────

    test(
      'volume comparison delta is correct for lbs user',
      () async {
        final repo = await _freshRepo();
        final exercises = await repo.getExercises();
        final exId = exercises.first.id;
        final service = SessionSummaryService(repo);

        // Previous session: 10 reps × 40 kg (stored canonically).
        await _buildCompletedSession(
          repo,
          sessionId: 'prev',
          startedAtMs: 1000,
          endedAtMs: 2000,
          exerciseId: exId,
          reps: 10,
          weightKg: 40.0,
        );

        // Current session: 10 reps × 50 kg.
        final currSession = await _buildCompletedSession(
          repo,
          sessionId: 'curr',
          startedAtMs: 5000,
          endedAtMs: 6000,
          exerciseId: exId,
          reps: 10,
          weightKg: 50.0,
        );

        final result = await service.compareToPreviousSession(
          currSession,
          500.0, // currentVolume = 10 × 50 kg
        );

        // Delta should be 100 kg (not inflated by ×2.20462).
        expect(result.previousVolume, closeTo(400.0, 0.01));
        expect(result.delta, closeTo(100.0, 0.01));
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Routine round-trip unit tests (Iteration 2 of the double-conversion fix)
  //
  // These tests exercise the path:
  //   RoutineState.setTargetValue (canonical kg) →
  //   RoutineSessionService.buildSessionFromTemplate →
  //   WorkoutState.populateSessionFromManifest →
  //   getExercisesWithEntries → entry['weight'] (canonical kg)
  //
  // The UI layer (routine_setup_screen.dart) is responsible for converting the
  // user's display-unit value to canonical kg before calling setTargetValue.
  // These tests assume that has already happened, exactly as the screen now does.
  // ══════════════════════════════════════════════════════════════════════════

  group('Routine round-trip (Iteration 2)', () {
    const kgToLbs = 2.20462;

    /// Build a routine with one set-based exercise whose weight target is
    /// [weightKg] (canonical kg) and whose reps target is [reps].
    /// Returns the template ID after saving.
    Future<String> buildSavedRoutine(
      MockWorkoutRepository repo, {
      required double weightKg,
      required int reps,
    }) async {
      final routineState = RoutineState(repo);
      routineState.setAutosaveEnabled(false);

      await routineState.createNewRoutine('Test Routine');
      final templateId = routineState.currentTemplate!.id;

      // Find a set-based exercise.
      final exercises = await repo.getExercises();
      final setExercise = exercises.firstWhere(
        (e) => e.capabilities.contains('load'),
        orElse: () => exercises.first,
      );

      // Add the exercise to the routine.
      final effortId = await routineState.addExerciseToRoutine(
        setExercise,
        'set',
      );
      expect(effortId, isNotEmpty);

      // Simulate what the fixed screen does: setTargetValue receives canonical kg.
      await routineState.setTargetValue(
        effortId,
        MetricIds.reps,
        MetricIds.unitReps,
        setIndex: 0,
        targetInt: reps,
      );
      await routineState.setTargetValue(
        effortId,
        MetricIds.weight,
        MetricIds.unitKg,
        setIndex: 0,
        targetMin: weightKg, // already canonical kg
      );

      await routineState.saveRoutine();
      return templateId;
    }

    test(
      'round-trip lbs: 35 lbs weight stores as ~15.88 kg and sessions shows ~35 lbs',
      () async {
        final repo = await _freshRepo();
        final lbsSettings = await _settingsWithUnit(repo, 'lbs');

        // 35 lbs → canonical kg (what the fixed screen now stores).
        final canonicalKg = 35.0 / kgToLbs;
        final templateId = await buildSavedRoutine(
          repo,
          weightKg: canonicalKg,
          reps: 10,
        );

        // Build manifest and populate a session.
        final service = RoutineSessionService(repo);
        final manifest = await service.buildSessionFromTemplate(templateId);

        final workoutState = WorkoutState(repo);
        await workoutState.createNewSession();
        await workoutState.populateSessionFromManifest(manifest);

        final exercises = workoutState.getExercisesWithEntries();
        final entries = exercises.first['entries'] as List;
        final entry = entries.first as Map<String, dynamic>;
        final storedWeight = (entry['weight'] as num).toDouble();

        // Stored value must be canonical kg (~15.88), not the display value (35.0).
        expect(storedWeight, closeTo(canonicalKg, 0.01));

        // Display layer converts kg → lbs → should show ~35 lbs.
        final displayedLbs = UnitFormatter.convertWeight(
          storedWeight,
          lbsSettings,
        );
        expect(displayedLbs, closeTo(35.0, 0.1));
      },
    );

    test(
      'round-trip kg: 100 kg weight stores as 100 kg and sessions shows 100 kg',
      () async {
        final repo = await _freshRepo();
        final kgSettings = await _settingsWithUnit(repo, 'kg');

        final templateId = await buildSavedRoutine(
          repo,
          weightKg: 100.0, // canonical kg, no conversion needed
          reps: 10,
        );

        final service = RoutineSessionService(repo);
        final manifest = await service.buildSessionFromTemplate(templateId);

        final workoutState = WorkoutState(repo);
        await workoutState.createNewSession();
        await workoutState.populateSessionFromManifest(manifest);

        final exercises = workoutState.getExercisesWithEntries();
        final entries = exercises.first['entries'] as List;
        final entry = entries.first as Map<String, dynamic>;
        final storedWeight = (entry['weight'] as num).toDouble();

        // For kg users, no conversion — value must pass through unchanged.
        expect(storedWeight, closeTo(100.0, 0.01));
        expect(
          UnitFormatter.convertWeight(storedWeight, kgSettings),
          closeTo(100.0, 0.01),
        );
      },
    );

    test(
      'regression: storing canonical kg prevents the 2.2× display inflation',
      () async {
        final repo = await _freshRepo();
        final lbsSettings = await _settingsWithUnit(repo, 'lbs');

        // The pre-fix bug: 35.0 was stored directly (as raw lbs value).
        // With the fix, 35.0 lbs → ~15.88 kg is what gets stored.
        final canonicalKg = 35.0 / kgToLbs;
        final templateId = await buildSavedRoutine(
          repo,
          weightKg: canonicalKg,
          reps: 10,
        );

        final service = RoutineSessionService(repo);
        final manifest = await service.buildSessionFromTemplate(templateId);

        final workoutState = WorkoutState(repo);
        await workoutState.createNewSession();
        await workoutState.populateSessionFromManifest(manifest);

        final exercises = workoutState.getExercisesWithEntries();
        final entries = exercises.first['entries'] as List;
        final entry = entries.first as Map<String, dynamic>;
        final storedWeight = (entry['weight'] as num).toDouble();

        final displayedLbs = UnitFormatter.convertWeight(
          storedWeight,
          lbsSettings,
        );

        // Must show ~35 lbs; the pre-fix bug would show ~77.2 lbs.
        expect(
          displayedLbs,
          lessThan(40.0),
          reason:
              'pre-fix double-conversion would yield ~77.2 lbs; '
              'got $displayedLbs',
        );
        expect(displayedLbs, closeTo(35.0, 0.1));
      },
    );

    test(
      'toCanonicalWeight / convertWeight round-trip is lossless for common values',
      () async {
        final repo = await _freshRepo();
        final lbsSettings = await _settingsWithUnit(repo, 'lbs');

        for (final lbs in [5.0, 10.0, 35.0, 100.0, 225.0]) {
          final kg = UnitFormatter.toCanonicalWeight(lbs, lbsSettings);
          final backToLbs = UnitFormatter.convertWeight(kg, lbsSettings);
          expect(backToLbs, closeTo(lbs, 0.001),
              reason: '$lbs lbs → $kg kg → $backToLbs lbs (should be $lbs)');
        }
      },
    );
  });
}
