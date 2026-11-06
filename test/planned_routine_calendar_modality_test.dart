import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/modality.dart';
import 'package:omnitrain/core/services/routine_session_service.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/core/utils/modality_color_utils.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/features/calendar/day_session_list_screen.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';
import 'helpers/repository_harness.dart';

// Plan 124: a PlannedSession row for a routine takes the routine's
// focusModality as its calendar entry modality, resolved at display time.
// Phase 0 = red tests only: no production change is expected yet, so
// S-12401, S-12405, S-12406, S-12407 and S-12411 (p-1 line) fail today.

final _clock124 = DateTime(2026, 11, 10, 12);

DateTime _day124(int day) => DateTime(2026, 11, day);

final int _rowAt124 = DateTime(2026, 11, 1).millisecondsSinceEpoch;

WorkoutTemplate _template124(String id, String? focus, String name) =>
    WorkoutTemplate(
      id: id,
      name: name,
      focusModality: focus,
      createdAtMs: _rowAt124,
      updatedAtMs: _rowAt124,
    );

PlannedSession _planned124(
  String id,
  int day,
  String? routineTemplateId, {
  String? modality,
  String? title,
  String? linkedSessionId,
}) => PlannedSession(
  id: id,
  ownerUserId: 'user-1',
  scheduledDateMs: _day124(day).millisecondsSinceEpoch,
  modality: modality,
  routineTemplateId: routineTemplateId,
  title: title,
  isCompleted: false,
  linkedSessionId: linkedSessionId,
  createdAtMs: _rowAt124,
  updatedAtMs: _rowAt124,
);

/// Fixture F-124: three routines and seven planned rows (see the plan).
Future<void> _seedF124(WorkoutRepository repo) async {
  await repo.createTemplate(
    _template124('tpl-124-iso', Modality.isometricStretching, 'Iso Rework 124'),
  );
  await repo.createTemplate(
    _template124('tpl-124-mixed', null, 'No Focus Routine 124'),
  );
  await repo.createTemplate(
    _template124(
      'tpl-124-cardio',
      Modality.cardioEndurance,
      'Cardio Block 124',
    ),
  );
  await repo.createPlannedSession(
    _planned124('p-1', 12, 'tpl-124-iso', title: 'Plan Iso 124'),
  );
  await repo.createPlannedSession(
    _planned124('p-2', 12, 'tpl-124-cardio', title: 'Plan Cardio 124'),
  );
  await repo.createPlannedSession(
    _planned124('p-3', 13, 'tpl-124-mixed', title: 'Plan Mixed 124'),
  );
  await repo.createPlannedSession(
    _planned124('p-4', 14, 'tpl-124-gone', title: 'Plan Orphan 124'),
  );
  await repo.createPlannedSession(
    _planned124(
      'p-5',
      15,
      null,
      modality: Modality.sports,
      title: 'Plan Sports 124',
    ),
  );
  await repo.createPlannedSession(
    _planned124('p-6', 3, 'tpl-124-iso', title: 'Plan Past Iso 124'),
  );
  await repo.createPlannedSession(
    _planned124(
      'p-7',
      12,
      'tpl-124-iso',
      title: 'Plan Linked 124',
      linkedSessionId: 's-124',
    ),
  );
}

Future<CalendarState> _loadedNovember124(WorkoutRepository repo) async {
  await _seedF124(repo);
  final state = CalendarState(repo, now: () => _clock124);
  await state.init();
  return state;
}

CalendarEntry _plannedEntryFor(List<CalendarEntry> day, String plannedId) =>
    day.firstWhere((e) => e.plannedSession?.id == plannedId);

Future<List<Map<String, dynamic>>> _plannedRowMaps(
  WorkoutRepository repo,
) async => (await repo.getPlannedSessions())
    .map((p) => p.toMap())
    .toList(growable: false);

/// A Mock repository that counts the reads and planned writes the calendar
/// makes on its own (after [recording] is switched on, so seeding is ignored).
class _CountingMockRepo extends MockWorkoutRepository {
  int getTemplatesCalls = 0;
  final List<PlannedSession> plannedWrites = [];
  bool recording = false;

  @override
  Future<List<WorkoutTemplate>> getTemplates() async {
    if (recording) getTemplatesCalls++;
    return super.getTemplates();
  }

  @override
  Future<String> createPlannedSession(PlannedSession session) async {
    if (recording) plannedWrites.add(session);
    return super.createPlannedSession(session);
  }

  @override
  Future<void> updatePlannedSession(PlannedSession session) async {
    if (recording) plannedWrites.add(session);
    return super.updatePlannedSession(session);
  }
}

void main() {
  group('plan 124 — calendar state over the shared harnesses', () {
    for (final factory in harnessFactories) {
      final harness = factory();
      group('on ${harness.name}', () {
        late WorkoutRepository repo;

        setUp(() async => repo = await harness.open());
        tearDown(() async => harness.close());

        test(
          'S-12401: a planned routine resolves its Focus (red today)',
          () async {
            final state = await _loadedNovember124(repo);
            final nov12 = state.entriesForDay(_day124(12));
            final p1 = _plannedEntryFor(nov12, 'p-1');
            expect(p1.isCompleted, isFalse);
            expect(p1.modality, Modality.isometricStretching);
          },
        );

        test('S-12402: a routine with no Focus stays Free', () async {
          final state = await _loadedNovember124(repo);
          final nov13 = state.entriesForDay(_day124(13));
          final p3 = _plannedEntryFor(nov13, 'p-3');
          expect(p3.modality, isNull);
        });

        test(
          'S-12402: an empty-string Focus counts as no Focus (Free)',
          () async {
            await repo.createTemplate(
              _template124('tpl-124-empty', '', 'Empty Focus Routine 124'),
            );
            await repo.createPlannedSession(
              _planned124('p-8', 16, 'tpl-124-empty'),
            );
            final state = await _loadedNovember124(repo);
            final p8 = _plannedEntryFor(state.entriesForDay(_day124(16)), 'p-8');
            expect(p8.modality, isNull);
          },
        );

        test(
          'S-12403: an orphan routine id never throws, stays Free',
          () async {
            final state = await _loadedNovember124(repo);
            final nov14 = state.entriesForDay(_day124(14));
            final p4 = _plannedEntryFor(nov14, 'p-4');
            expect(p4.isCompleted, isFalse);
            expect(p4.modality, isNull);
          },
        );

        test('S-12404: a plain-modality plan keeps its own modality', () async {
          final state = await _loadedNovember124(repo);
          final nov15 = state.entriesForDay(_day124(15));
          final p5 = _plannedEntryFor(nov15, 'p-5');
          expect(p5.modality, Modality.sports);
        });

        test(
          'S-12405: a Focus edit after planning changes the plan colour (red today)',
          () async {
            final state = await _loadedNovember124(repo);
            final rowBefore = (await _plannedRowMaps(
              repo,
            )).firstWhere((m) => m['id'] == 'p-1');

            final tpl = (await repo.getTemplateById('tpl-124-iso'))!;
            await repo.updateTemplate(
              tpl.copyWith(focusModality: Modality.cardioEndurance),
            );
            await state.refresh();

            final p1 = _plannedEntryFor(
              state.entriesForDay(_day124(12)),
              'p-1',
            );
            expect(p1.modality, Modality.cardioEndurance);

            final rowAfter = (await _plannedRowMaps(
              repo,
            )).firstWhere((m) => m['id'] == 'p-1');
            expect(rowAfter, rowBefore);
          },
        );

        test(
          'S-12406: a planned routine in the past still resolves (red today)',
          () async {
            final state = await _loadedNovember124(repo);
            final nov3 = state.entriesForDay(_day124(3));
            final p6 = _plannedEntryFor(nov3, 'p-6');
            expect(p6.isCompleted, isFalse);
            expect(p6.modality, Modality.isometricStretching);
          },
        );

        test(
          'S-12407: two routine plans on one day resolve apart (red today)',
          () async {
            final state = await _loadedNovember124(repo);
            // p-7 is linked to a session: it stays out of the grid.
            expect(
              state
                  .entriesForDay(_day124(12))
                  .any((e) => e.plannedSession?.id == 'p-7'),
              isFalse,
            );
            final nov12 = state.entriesForDay(_day124(12)).where((e) {
              final id = e.plannedSession?.id;
              return id != null && const {'p-1', 'p-2'}.contains(id);
            }).toList();

            final modalities = nov12.map((e) => e.modality).toSet();
            expect(modalities, {
              Modality.isometricStretching,
              Modality.cardioEndurance,
            });

            final colors = modalities
                .map(ModalityColorUtils.colorForModality)
                .toSet();
            expect(colors, hasLength(2));
          },
        );

        test(
          'S-12410: planned entries stay out of the monthly breakdown',
          () async {
            final start = _day124(
              5,
            ).add(const Duration(hours: 9)).millisecondsSinceEpoch;
            await _seedF124(repo);
            await repo.createSession(
              TrainingSession(
                id: 's-124-free',
                ownerUserId: 'user-1',
                startedAtMs: start,
                endedAtMs: start + 3600000,
                modality: null,
                isRolling: false,
                createdAtMs: start,
                updatedAtMs: start,
              ),
            );
            final state = CalendarState(repo, now: () => _clock124);
            await state.init();
            expect(state.modalityBreakdown, <String?, int>{null: 1});
          },
        );
      });
    }
  });

  group('plan 124 — S-12408 reads and writes (Mock only)', () {
    Future<({CalendarState state, _CountingMockRepo repo})>
    loadCounted124() async {
      final repo = _CountingMockRepo();
      await repo.initialize();
      await _seedF124(repo);
      repo.recording = true;
      final state = CalendarState(repo, now: () => _clock124);
      await state.init();
      return (state: state, repo: repo);
    }

    test('S-12408: a routine-planned month writes nothing planned', () async {
      final loaded = await loadCounted124();
      final beforeMaps = await _plannedRowMaps(loaded.repo);
      await loaded.state.refresh();
      final afterMaps = await _plannedRowMaps(loaded.repo);
      expect(afterMaps, beforeMaps);
      expect(loaded.repo.plannedWrites, isEmpty);
    });

    test(
      'S-12408: a routine-planned month reads templates once per load (red today)',
      () async {
        final loaded = await loadCounted124();
        expect(loaded.repo.getTemplatesCalls, 1);
      },
    );

    test('S-12408: a plain-modality month reads no templates', () async {
      final repo = _CountingMockRepo();
      await repo.initialize();
      await repo.createPlannedSession(
        _planned124(
          'p-5',
          15,
          null,
          modality: Modality.sports,
          title: 'Plan Sports 124',
        ),
      );
      repo.recording = true;
      final state = CalendarState(repo, now: () => _clock124);
      await state.init();
      expect(repo.getTemplatesCalls, 0);
    });
  });

  group('plan 124 — day list screen (Mock only)', () {
    Future<(CalendarState, MockWorkoutRepository)> loadedMock124() async {
      final repo = MockWorkoutRepository();
      await repo.initialize();
      await _seedF124(repo);
      final state = CalendarState(repo, now: () => _clock124);
      await state.init();
      return (state, repo);
    }

    Future<void> pumpDay(
      WidgetTester tester,
      CalendarState calendarState,
      WorkoutRepository repo,
      DateTime day,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: DaySessionListScreen(
            date: day,
            calendarState: calendarState,
            routineState: RoutineState(repo),
            workoutState: WorkoutState(repo),
            routineSessionService: RoutineSessionService(repo),
            sessionSummaryService: SessionSummaryService(repo),
            settingsState: SettingsState(repo, fakePreferencesService()),
            timerAlertService: FakeTimerAlertService(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'S-12411 (p-1): the card subtitle names the Focus (red today)',
      (tester) async {
        final (calendarState, repo) = await loadedMock124();
        await pumpDay(tester, calendarState, repo, _day124(12));
        expect(find.text('Isometric / Stretching  ·  Planned'), findsOneWidget);
      },
    );

    testWidgets('S-12411 (p-3): a no-Focus routine card keeps just Planned', (
      tester,
    ) async {
      final (calendarState, repo) = await loadedMock124();
      await pumpDay(tester, calendarState, repo, _day124(13));
      expect(find.text('Planned'), findsOneWidget);
    });

    testWidgets('S-12411 (p-5): a plain-modality card keeps its label', (
      tester,
    ) async {
      final (calendarState, repo) = await loadedMock124();
      await pumpDay(tester, calendarState, repo, _day124(15));
      expect(find.text('Sports  ·  Planned'), findsOneWidget);
    });

    testWidgets(
      'S-12409: tapping a planned routine leaves the plan row untouched',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = MockWorkoutRepository();
        await repo.initialize();
        final exercise = (await repo.getExercises()).first;
        await repo.createTemplate(
          _template124(
            'tpl-124-iso',
            Modality.isometricStretching,
            'Iso Rework 124',
          ),
        );
        await repo.createTemplateSegment(
          TemplateSegment(
            id: 'seg-124-iso',
            templateId: 'tpl-124-iso',
            orderIndex: 0,
            segmentType: 'workout',
            name: 'Main',
            createdAtMs: _rowAt124,
            updatedAtMs: _rowAt124,
          ),
        );
        await repo.createTemplateEffort(
          TemplateEffort(
            id: 'eff-124-iso',
            templateSegmentId: 'seg-124-iso',
            orderIndex: 0,
            effortKind: 'set',
            exerciseId: exercise.id,
            createdAtMs: _rowAt124,
          ),
        );

        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        await repo.createPlannedSession(
          PlannedSession(
            id: 'p-1',
            ownerUserId: 'user-1',
            scheduledDateMs: today.millisecondsSinceEpoch,
            modality: null,
            routineTemplateId: 'tpl-124-iso',
            title: 'Plan Today 124',
            isCompleted: false,
            createdAtMs: _rowAt124,
            updatedAtMs: _rowAt124,
          ),
        );
        final rowBefore = (await _plannedRowMaps(
          repo,
        )).firstWhere((m) => m['id'] == 'p-1');

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

        await tester.tap(find.text('Plan Today 124'));
        await tester.pumpAndSettle();

        final rowAfter = (await _plannedRowMaps(
          repo,
        )).firstWhere((m) => m['id'] == 'p-1');
        expect(rowAfter, rowBefore);
        expect(workoutState.hasActiveSession, isTrue);
        expect(
          await repo.getSession(workoutState.currentSession!.id),
          isNotNull,
        );
      },
    );
  });
}
