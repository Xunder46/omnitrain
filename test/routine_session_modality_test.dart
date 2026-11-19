// Plan 122 — routine-session modality, Phase 0b (start path / tile /
// add-exercise). Scenarios from
// `docs/plans/2026-11-05-122-routine-session-modality-plan/2026-11-05-122-routine-session-modality-plan.md`:
//
//   S-12201 — My Routines start of a focused routine stamps the Focus.
//   S-12202 — My Routines start of a no-focus routine keeps null (guard).
//   S-12203 — Day list tap of a planned routine stamps the Focus; the
//             planned row is untouched.
//   S-12205 — While a routine session is active only the Routines tile
//             is active (D-12204).
//   S-12206 — Mid-session add in a focused routine still asks the kind
//             (ModalityPickerDialog) and the answer decides the kind
//             (D-12205).
//   S-12217 — Session overview add in a focused routine: same guard,
//             and the picker is opened with `sessionModality: null`
//             (D-12213).
//   S-12218 — The picker shows NO "Recommended" section in a routine
//             session (D-12213): one unranked list.
//   S-12219 — Guards: a home-tile modality session and Free Training
//             keep today's add-exercise behaviour exactly (D-12205).
//   S-12208 — Health type for a focused routine session follows the
//             Focus mapping; a null-modality routine session is "other"
//             (D-12210 pin).
//
// Phase 0 = red tests only: the file touches no production code. The
// add-exercise scenarios build their sessions stamped directly via
// `createNewSession`, so they do not depend on Phase 1.
//
// The add-path scenarios are Mock-only `testWidgets` (Mock-first: every
// persisting tap runs against `MockWorkoutRepository` — no Hive in
// `testWidgets`). S-12208 runs as plain `test()` on the harness of
// `test/health_yoga_kind_test.dart`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/block_types.dart';
import 'package:omnitrain/core/constants/capability.dart';
import 'package:omnitrain/core/constants/health_constants.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/constants/modality.dart';
import 'package:omnitrain/core/services/health_platform_service.dart';
import 'package:omnitrain/core/services/health_sync_service.dart';
import 'package:omnitrain/core/services/exercise_library_service.dart';
import 'package:omnitrain/core/services/routine_session_service.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/calendar/day_session_list_screen.dart';
import 'package:omnitrain/features/exercise/exercise_picker_screen.dart';
import 'package:omnitrain/features/home/home_screen.dart';
import 'package:omnitrain/features/routine/my_routines_screen.dart';
import 'package:omnitrain/features/session/session_overview_screen.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';
import 'package:omnitrain/state/exercise/exercise_library_state.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/home/home_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/period/period_state.dart';
import 'package:omnitrain/state/profile/profile_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/cards/energy_tile.dart';
import 'package:omnitrain/widgets/pickers/modality_picker_dialog.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';
import 'helpers/test_nutrition_primer_state.dart';

// ── Fixture F-122 (shelf used by this file; the back-fill suite owns the
//    row-exact parts) ────────────────────────────────────────────────────────

const int _f122AtMs = 1700000000000;
const String _tplIso = 'tpl-122-iso';
const String _tplMixed = 'tpl-122-mixed';

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

Future<Exercise> _seedExercise(
  MockWorkoutRepository repo, {
  required String id,
  required String name,
  required List<String> capabilities,
}) async {
  await repo.createExercise(
    Exercise(
      id: id,
      name: name,
      createdAtMs: _f122AtMs,
      updatedAtMs: _f122AtMs,
    ),
  );
  await repo.setExerciseCapabilities(id, capabilities);
  return (await repo.getExerciseById(id))!;
}

/// `tpl-122-iso` "Evening Stretch", Focus isometric_stretching; segment
/// `tseg-122-iso`; `teff-122-hold` (hold-capable exercise, `drill`) and
/// `teff-122-squat` (reps-capable exercise, `set`, 3 targets → 3 sets).
Future<WorkoutTemplate> _seedIsoRoutine(MockWorkoutRepository repo) async {
  final holdEx = await _seedExercise(
    repo,
    // hold + time + sets scores above the Recommended threshold for
    // isometric_stretching (primary 15 + isometric bonus 15 + secondary 10),
    // so S-12218 can see the Recommended section appear today.
    id: 'ex-122-hold',
    name: 'Plank Hold 122',
    capabilities: [
      ExerciseCapability.hold,
      ExerciseCapability.time,
      ExerciseCapability.sets,
    ],
  );
  final repsEx = await _seedExercise(
    repo,
    id: 'ex-122-squat',
    name: 'Goblet Squat 122',
    capabilities: [
      ExerciseCapability.reps,
      ExerciseCapability.sets,
      ExerciseCapability.load,
    ],
  );

  final template = WorkoutTemplate(
    id: _tplIso,
    name: 'Evening Stretch',
    focusModality: Modality.isometricStretching,
    createdAtMs: _f122AtMs,
    updatedAtMs: _f122AtMs,
  );
  await repo.createTemplate(template);
  await repo.createTemplateSegment(
    TemplateSegment(
      id: 'tseg-122-iso',
      templateId: _tplIso,
      orderIndex: 0,
      segmentType: BlockTypes.strengthSets,
      name: 'Main',
      createdAtMs: _f122AtMs,
      updatedAtMs: _f122AtMs,
    ),
  );
  await repo.createTemplateEffort(
    TemplateEffort(
      id: 'teff-122-hold',
      templateSegmentId: 'tseg-122-iso',
      orderIndex: 0,
      effortKind: BlockTypes.drill,
      exerciseId: holdEx.id,
      createdAtMs: _f122AtMs,
    ),
  );
  await repo.createTemplateEffort(
    TemplateEffort(
      id: 'teff-122-squat',
      templateSegmentId: 'tseg-122-iso',
      orderIndex: 1,
      effortKind: BlockTypes.set,
      exerciseId: repsEx.id,
      createdAtMs: _f122AtMs,
    ),
  );
  for (final setIndex in [0, 1, 2]) {
    await repo.createTemplateTarget(
      TemplateTarget(
        id: 'tegt-122-squat-$setIndex',
        templateEffortId: 'teff-122-squat',
        metricId: MetricIds.reps,
        setIndex: setIndex,
        targetInt: 10,
        createdAtMs: _f122AtMs,
        updatedAtMs: _f122AtMs,
      ),
    );
  }
  return template;
}

/// `tpl-122-mixed` "Mixed Day" — no Focus, one `set` effort.
Future<WorkoutTemplate> _seedMixedRoutine(MockWorkoutRepository repo) async {
  final repsEx = await _seedExercise(
    repo,
    id: 'ex-122-squat',
    name: 'Goblet Squat 122',
    capabilities: [
      ExerciseCapability.reps,
      ExerciseCapability.sets,
      ExerciseCapability.load,
    ],
  );
  final template = WorkoutTemplate(
    id: _tplMixed,
    name: 'Mixed Day',
    focusModality: null,
    createdAtMs: _f122AtMs,
    updatedAtMs: _f122AtMs,
  );
  await repo.createTemplate(template);
  await repo.createTemplateSegment(
    TemplateSegment(
      id: 'tseg-122-mixed',
      templateId: _tplMixed,
      orderIndex: 0,
      segmentType: BlockTypes.strengthSets,
      name: 'Main',
      createdAtMs: _f122AtMs,
      updatedAtMs: _f122AtMs,
    ),
  );
  await repo.createTemplateEffort(
    TemplateEffort(
      id: 'teff-122-mixed-set',
      templateSegmentId: 'tseg-122-mixed',
      orderIndex: 0,
      effortKind: BlockTypes.set,
      exerciseId: repsEx.id,
      createdAtMs: _f122AtMs,
    ),
  );
  return template;
}

Future<List<Map<String, dynamic>>> _plannedRowMaps(
  MockWorkoutRepository repo,
) async => (await repo.getPlannedSessions())
    .map((p) => p.toMap())
    .toList(growable: false);

// ── Rigs for the session screens and the picker ───────────────────────────

Future<void> _pumpSessionScreen(
  WidgetTester tester,
  MockWorkoutRepository repo,
  WorkoutState workoutState,
) async {
  await tester.binding.setSurfaceSize(const Size(600, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: WorkoutSessionScreen(
        workoutState: workoutState,
        routineState: RoutineState(repo),
        sessionSummaryService: SessionSummaryService(repo),
        settingsState: SettingsState(repo, fakePreferencesService()),
        timerAlertService: FakeTimerAlertService(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpOverviewScreen(
  WidgetTester tester,
  MockWorkoutRepository repo,
  WorkoutState workoutState,
) async {
  await tester.binding.setSurfaceSize(const Size(600, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: SessionOverviewScreen(
        workoutState: workoutState,
        routineState: RoutineState(repo),
        sessionSummaryService: SessionSummaryService(repo),
        settingsState: SettingsState(repo, fakePreferencesService()),
        timerAlertService: FakeTimerAlertService(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Opens the exercise picker from the given add button, narrows its list by
/// a fuzzy search on [exerciseName] and taps the one row that remains.
Future<void> _tapAddAndPick(
  WidgetTester tester,
  Finder addButton,
  String exerciseName,
) async {
  await tester.tap(addButton);
  await tester.pumpAndSettle();
  expect(find.byType(ExercisePickerScreen), findsOneWidget);

  await tester.enterText(
    find.widgetWithText(TextField, 'Search exercises...'),
    exerciseName,
  );
  // The picker's search debounce re-runs after 300 ms of fake time.
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();

  // The exercise rows are ListTiles; tapping the raw text would be ambiguous
  // once the search field's EditableText carries the same string.
  await tester.tap(
    find.descendant(
      of: find.byType(ListTile),
      matching: find.text(exerciseName),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _dialogOption(String label) => find.descendant(
  of: find.byType(ModalityPickerDialog),
  matching: find.text(label),
);

// ── S-12208 rig (copy of test/health_yoga_kind_test.dart) ─────────────────

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

class _HealthRig {
  final MockWorkoutRepository repo;
  final SettingsState settings;
  final _FakeHealthPlatform platform;
  final HealthSyncService sync;
  final WorkoutState workoutState;

  _HealthRig._({
    required this.repo,
    required this.settings,
    required this.platform,
    required this.sync,
    required this.workoutState,
  });

  static Future<_HealthRig> create() async {
    final repo = MockWorkoutRepository();
    await repo.initialize();
    final platform = _FakeHealthPlatform();
    final settings = SettingsState(
      repo,
      fakePreferencesService(),
      healthPlatform: platform,
    );
    await settings.initialize();
    await settings.setHealthWriteWorkoutsEnabled(true);
    final sync = HealthSyncService(
      platform: platform,
      repository: repo,
      isWriteEnabled: () =>
          settings.healthWriteWorkouts == HealthToggleState.on,
      isReadEnabled: () =>
          settings.healthReadBodyWeight == HealthToggleState.on,
    );
    final workoutState = WorkoutState(repo, healthSync: sync);
    return _HealthRig._(
      repo: repo,
      settings: settings,
      platform: platform,
      sync: sync,
      workoutState: workoutState,
    );
  }

  /// Adds the non-yoga exercise to the running session.
  Future<void> addNonYogaExercise(String id) async {
    final exercise = (await repo.getExerciseById(id))!;
    await workoutState.addExerciseToSession(exercise);
  }
}

// ── Home rig (copy of test/interaction_flow_test.dart's builder) ──────────

Future<({HomeScreen screen, WorkoutState workoutState})>
_buildHomeWithLoadedRoutineSession(MockWorkoutRepository repo) async {
  final seedState = WorkoutState(repo);
  await seedState.createNewSession(
    modality: Modality.isometricStretching,
    title: 'Evening Stretch',
    intent: 'routine',
    routineTemplateId: _tplIso,
  );
  final holdEx = (await repo.getExerciseById('ex-122-hold'))!;
  await seedState.addExerciseToSession(holdEx, effortKindOverride: 'drill');
  final sessionId = seedState.currentSession!.id;

  final workoutState = WorkoutState(repo);
  await workoutState.loadHistoricalSession(sessionId);

  final homeState = HomeState(repo);
  await homeState.init();
  final routineState = RoutineState(repo);
  final routineSessionService = RoutineSessionService(repo);
  final sessionSummaryService = SessionSummaryService(repo);
  final calendarState = CalendarState(repo);
  await calendarState.init();
  final periodState = PeriodState(repo);
  final profileState = ProfileState(repo);
  await profileState.loadProfile();
  final settingsState = SettingsState(repo, fakePreferencesService());
  await settingsState.initialize();
  final nutritionPrimerState = await buildNutritionPrimerState(repo);

  final screen = HomeScreen(
    workoutState: workoutState,
    homeState: homeState,
    routineState: routineState,
    routineSessionService: routineSessionService,
    sessionSummaryService: sessionSummaryService,
    calendarState: calendarState,
    periodState: periodState,
    profileState: profileState,
    settingsState: settingsState,
    timerAlertService: FakeTimerAlertService(),
    nutritionState: NutritionState(repo),
    foodLibraryState: FoodLibraryState(repo),
    nutritionPrimerState: nutritionPrimerState,
    exerciseLibraryState: ExerciseLibraryState(
      service: ExerciseLibraryService(repo),
      workoutState: workoutState,
    ),
  );

  return (screen: screen, workoutState: workoutState);
}

void main() {
  group('plan 122 — start paths (S-12201, S-12202, S-12203)', () {
    testWidgets('S-12201: starting "Evening Stretch" carries the Focus '
        '(red today: modality null)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = await _freshRepo();
      await _seedIsoRoutine(repo);
      final workoutState = WorkoutState(repo);
      await tester.pumpWidget(
        MaterialApp(
          home: MyRoutinesScreen(
            routineState: RoutineState(repo),
            workoutState: workoutState,
            routineSessionService: RoutineSessionService(repo),
            sessionSummaryService: SessionSummaryService(repo),
            settingsState: SettingsState(repo, fakePreferencesService()),
            timerAlertService: FakeTimerAlertService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('routine-card-start')).first);
      await tester.pumpAndSettle();

      expect(workoutState.hasActiveSession, isTrue);
      final session = workoutState.currentSession!;
      // D-12201a: the Focus is stamped verbatim at start (red today: null).
      expect(session.modality, Modality.isometricStretching);
      expect(session.intent, 'routine');
      expect(session.routineTemplateId, _tplIso);
      expect(session.title, 'Evening Stretch');

      // D-12203: the Focus never changes a routine exercise's kind.
      final efforts = workoutState.getEffortsForSegment(
        workoutState.segments.first.id,
      );
      expect(
        efforts.map((e) => e.effortKind),
        ['drill', 'set'],
        reason: 'effort kinds stay per-template, in template order',
      );
    });

    testWidgets('S-12202: a no-focus routine starts with modality null '
        '(guard, green today)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = await _freshRepo();
      await _seedMixedRoutine(repo);
      final workoutState = WorkoutState(repo);
      await tester.pumpWidget(
        MaterialApp(
          home: MyRoutinesScreen(
            routineState: RoutineState(repo),
            workoutState: workoutState,
            routineSessionService: RoutineSessionService(repo),
            sessionSummaryService: SessionSummaryService(repo),
            settingsState: SettingsState(repo, fakePreferencesService()),
            timerAlertService: FakeTimerAlertService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('routine-card-start')).first);
      await tester.pumpAndSettle();

      expect(workoutState.hasActiveSession, isTrue);
      expect(workoutState.currentSession!.modality, isNull);
    });

    testWidgets(
      'S-12203: tapping the planned routine on today stamps the Focus; '
      'the planned row is untouched (red today)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _freshRepo();
        await _seedIsoRoutine(repo);

        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        await repo.createPlannedSession(
          PlannedSession(
            id: 'p-122-1',
            ownerUserId: 'user-1',
            scheduledDateMs: today.millisecondsSinceEpoch,
            modality: null,
            routineTemplateId: _tplIso,
            title: 'Plan Today 122',
            isCompleted: false,
            createdAtMs: _f122AtMs,
            updatedAtMs: _f122AtMs,
          ),
        );
        final rowBefore = (await _plannedRowMaps(
          repo,
        )).firstWhere((m) => m['id'] == 'p-122-1');

        final calendarState = CalendarState(repo);
        await calendarState.init();
        final workoutState = WorkoutState(repo);

        await tester.pumpWidget(
          MaterialApp(
            home: DaySessionListScreen(
              date: today,
              calendarState: calendarState,
              routineState: RoutineState(repo),
              workoutState: workoutState,
              routineSessionService: RoutineSessionService(repo),
              sessionSummaryService: SessionSummaryService(repo),
              settingsState: SettingsState(repo, fakePreferencesService()),
              timerAlertService: FakeTimerAlertService(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Plan Today 122'));
        await tester.pumpAndSettle();

        // D-12201b: the planned-routine branch stamps the Focus
        // (red today: creates the session with modality null).
        expect(workoutState.hasActiveSession, isTrue);
        expect(
          workoutState.currentSession!.modality,
          Modality.isometricStretching,
        );
        expect(workoutState.currentSession!.intent, 'routine');

        // The planned row is never written to.
        final rowAfter = (await _plannedRowMaps(
          repo,
        )).firstWhere((m) => m['id'] == 'p-122-1');
        expect(rowAfter, rowBefore);
      },
    );
  });

  group('plan 122 — S-12205 only the Routines tile is active', () {
    testWidgets('an active routine session lights exactly the Routines tile', (
      tester,
    ) async {
      final repo = await _freshRepo();
      await _seedIsoRoutine(repo);
      final setup = await _buildHomeWithLoadedRoutineSession(repo);

      await tester.pumpWidget(MaterialApp(home: setup.screen));
      // pump() with an explicit duration rather than pumpAndSettle: the
      // active tile carries the repeating "Workout in progress" pulse.
      await tester.pump(const Duration(milliseconds: 200));

      final activeTiles = tester
          .widgetList<EnergyTile>(find.byType(EnergyTile))
          .where((tile) => tile.isActive)
          .toList();

      // D-12204: only the Routines tile lights — the Isometric tile stays
      // dark even though the session's modality matches it.
      expect(activeTiles, hasLength(1));
      expect(activeTiles.single.title, 'Routines');
    });
  });

  group('plan 122 — add exercise in a focused routine (S-12206, S-12218)', () {
    Future<WorkoutState> pumpStampedRoutineSession(WidgetTester tester) async {
      final repo = await _freshRepo();
      await _seedExercise(
        repo,
        id: 'ex-122-squat',
        name: 'Goblet Squat 122',
        capabilities: [
          ExerciseCapability.reps,
          ExerciseCapability.sets,
          ExerciseCapability.load,
        ],
      );
      await repo.createTemplate(
        WorkoutTemplate(
          id: _tplIso,
          name: 'Evening Stretch',
          focusModality: Modality.isometricStretching,
          createdAtMs: _f122AtMs,
          updatedAtMs: _f122AtMs,
        ),
      );
      final workoutState = WorkoutState(repo);
      // Stamped routine session, built directly (no Phase 1 dependency).
      await workoutState.createNewSession(
        modality: Modality.isometricStretching,
        intent: 'routine',
        routineTemplateId: _tplIso,
        title: 'Evening Stretch',
      );
      await _pumpSessionScreen(tester, repo, workoutState);
      return workoutState;
    }

    Future<void> expectDialogAnswerKind(
      WidgetTester tester, {
      required String answer,
      required String expectedKind,
      required WorkoutState workoutState,
    }) async {
      // D-12205: a routine session always asks the exercise kind, whatever
      // its stamped Focus.
      expect(find.byType(ModalityPickerDialog), findsOneWidget);
      await tester.tap(_dialogOption(answer));
      await tester.pumpAndSettle();

      final kinds = workoutState
          .getEffortsForSegment(workoutState.segments.first.id)
          .map((e) => e.effortKind)
          .toList();
      expect(kinds, hasLength(1));
      expect(kinds.single, expectedKind);
    }

    testWidgets('S-12206 (a): answering "Resistance" gives a `set` effort '
        '(red today: the dialog is skipped for the stamped fixture)', (
      tester,
    ) async {
      final workoutState = await pumpStampedRoutineSession(tester);
      await _tapAddAndPick(
        tester,
        find.byKey(const Key('add-exercise')),
        'Goblet Squat 122',
      );
      await expectDialogAnswerKind(
        tester,
        answer: 'Resistance',
        expectedKind: 'set',
        workoutState: workoutState,
      );
    });

    testWidgets('S-12206 (b): answering "Isometric" gives a `drill` effort', (
      tester,
    ) async {
      final workoutState = await pumpStampedRoutineSession(tester);
      await _tapAddAndPick(
        tester,
        find.byKey(const Key('add-exercise')),
        'Goblet Squat 122',
      );
      await expectDialogAnswerKind(
        tester,
        answer: 'Isometric',
        expectedKind: 'drill',
        workoutState: workoutState,
      );
    });

    testWidgets(
      'S-12218: the picker shows no "Recommended" section in a routine '
      'session (red today: it opens ranked by the Focus)',
      (tester) async {
        await pumpStampedRoutineSession(tester);

        await tester.tap(find.byKey(const Key('add-exercise')));
        await tester.pumpAndSettle();
        expect(find.byType(ExercisePickerScreen), findsOneWidget);

        // D-12213: the picker opens unranked (sessionModality null) —
        // one flat list, no Recommended section.
        expect(find.text('Recommended'), findsNothing);
      },
    );
  });

  group('plan 122 — guards (S-12219)', () {
    testWidgets(
      'S-12219 (i): a home-tile modality session keeps today\'s add flow — '
      'no kind dialog, Recommended list, `drill` effort',
      (tester) async {
        final repo = await _freshRepo();
        await _seedExercise(
          repo,
          id: 'ex-122-hold',
          name: 'Plank Hold 122',
          capabilities: [
            ExerciseCapability.hold,
            ExerciseCapability.time,
            ExerciseCapability.sets,
          ],
        );
        final workoutState = WorkoutState(repo);
        // (i): intent null, modality stamped — a tile-started session.
        await workoutState.createNewSession(
          modality: Modality.isometricStretching,
        );
        await _pumpSessionScreen(tester, repo, workoutState);

        await tester.tap(find.byKey(const Key('add-exercise')));
        await tester.pumpAndSettle();
        expect(find.byType(ExercisePickerScreen), findsOneWidget);
        // The picker IS ranked for the session's modality today (green pin).
        expect(find.text('Recommended'), findsOneWidget);

        await tester.enterText(
          find.widgetWithText(TextField, 'Search exercises...'),
          'Plank Hold 122',
        );
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(ListTile),
            matching: find.text('Plank Hold 122'),
          ),
        );
        await tester.pumpAndSettle();

        // No kind dialog for a tile-started modality session (green pin).
        expect(find.byType(ModalityPickerDialog), findsNothing);
        final kinds = workoutState
            .getEffortsForSegment(workoutState.segments.first.id)
            .map((e) => e.effortKind)
            .toList();
        expect(kinds, hasLength(1));
        expect(kinds.single, 'drill');
      },
    );

    testWidgets(
      'S-12219 (ii): Free Training keeps asking the kind (green pin)',
      (tester) async {
        final repo = await _freshRepo();
        await _seedExercise(
          repo,
          id: 'ex-122-hold',
          name: 'Plank Hold 122',
          capabilities: [
            ExerciseCapability.hold,
            ExerciseCapability.time,
            ExerciseCapability.sets,
          ],
        );
        final workoutState = WorkoutState(repo);
        // (ii): Free Training — intent null, modality null.
        await workoutState.createNewSession();
        await _pumpSessionScreen(tester, repo, workoutState);

        await _tapAddAndPick(
          tester,
          find.byKey(const Key('add-exercise')),
          'Plank Hold 122',
        );

        expect(
          find.byType(ModalityPickerDialog),
          findsOneWidget,
          reason: 'Free Training still asks the exercise kind',
        );
        await tester.tap(_dialogOption('Isometric'));
        await tester.pumpAndSettle();
        final kinds = workoutState
            .getEffortsForSegment(workoutState.segments.first.id)
            .map((e) => e.effortKind)
            .toList();
        expect(kinds, hasLength(1));
        expect(kinds.single, 'drill');
      },
    );
  });

  group('plan 122 — session overview add (S-12217)', () {
    testWidgets(
      'S-12217: overview add in a focused routine asks the kind and opens '
      'the picker unranked (red today)',
      (tester) async {
        final repo = await _freshRepo();
        await _seedExercise(
          repo,
          id: 'ex-122-squat',
          name: 'Goblet Squat 122',
          capabilities: [
            ExerciseCapability.reps,
            ExerciseCapability.sets,
            ExerciseCapability.load,
          ],
        );
        await repo.createTemplate(
          WorkoutTemplate(
            id: _tplIso,
            name: 'Evening Stretch',
            focusModality: Modality.isometricStretching,
            createdAtMs: _f122AtMs,
            updatedAtMs: _f122AtMs,
          ),
        );
        final workoutState = WorkoutState(repo);
        // Stamped routine session, built directly (no Phase 1 dependency).
        await workoutState.createNewSession(
          modality: Modality.isometricStretching,
          intent: 'routine',
          routineTemplateId: _tplIso,
          title: 'Evening Stretch',
        );
        await _pumpOverviewScreen(tester, repo, workoutState);

        await tester.tap(find.text('Add Exercise'));
        await tester.pumpAndSettle();
        expect(find.byType(ExercisePickerScreen), findsOneWidget);

        // D-12213: the picker is built with sessionModality == null
        // (red today: 'isometric_stretching').
        final picker = tester.widget<ExercisePickerScreen>(
          find.byType(ExercisePickerScreen),
        );
        expect(picker.sessionModality, isNull);

        // D-12205: overview add in a routine session still asks the kind
        // (red today: the dialog is skipped for the stamped fixture).
        await tester.enterText(
          find.widgetWithText(TextField, 'Search exercises...'),
          'Goblet Squat 122',
        );
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(ListTile),
            matching: find.text('Goblet Squat 122'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(ModalityPickerDialog), findsOneWidget);
        await tester.tap(_dialogOption('Resistance'));
        await tester.pumpAndSettle();

        final kinds = workoutState
            .getEffortsForSegment(workoutState.segments.first.id)
            .map((e) => e.effortKind)
            .toList();
        expect(kinds, hasLength(1));
        expect(kinds.single, 'set');
      },
    );
  });

  group('plan 122 — S-12208 Health type pin (plain test)', () {
    test('S-12208 (a): a focused routine session with cardio Focus writes '
        'HealthActivityKind.cardio (green pin)', () async {
      final rig = await _HealthRig.create();
      await rig.workoutState.createNewSession(
        modality: Modality.cardioEndurance,
        intent: 'routine',
        routineTemplateId: 'tpl-122-cardio',
        title: 'Easy Run',
      );
      await rig.addNonYogaExercise('exercise-rowing-intervals');
      await rig.workoutState.endSession();

      expect(rig.platform.writtenWorkouts, hasLength(1));
      expect(
        rig.platform.writtenWorkouts.single.activityKind,
        HealthActivityKind.cardio,
      );
    });

    test('S-12208 (b): a no-focus routine session writes "other" '
        '(green pin)', () async {
      final rig = await _HealthRig.create();
      await rig.workoutState.createNewSession(
        intent: 'routine',
        routineTemplateId: 'tpl-122-cardio',
        title: 'Easy Run',
      );
      await rig.addNonYogaExercise('exercise-rowing-intervals');
      await rig.workoutState.endSession();

      expect(rig.platform.writtenWorkouts, hasLength(1));
      expect(
        rig.platform.writtenWorkouts.single.activityKind,
        HealthActivityKind.other,
      );
    });
  });
}
