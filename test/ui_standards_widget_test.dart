import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/core/models/stats_progress.dart';
import 'package:omnitrain/core/services/routine_session_service.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/core/utils/date_utils.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/features/calendar/day_session_list_screen.dart';
import 'package:omnitrain/features/stats/widgets/recent_pr_list.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/layout/omni_card_header.dart';
import 'package:omnitrain/widgets/layout/omni_surface.dart';
import 'package:omnitrain/widgets/pickers/modality_picker_dialog.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

/// `CalendarState` whose day lookup is fixed by the test, because
/// `CalendarState._loadMonth` drops every session that is still open — the
/// "In Progress" branch of `DaySessionListScreen` is unreachable from real
/// state.
class _FixedEntriesCalendarState extends CalendarState {
  // A super parameter is not available here: the super constructor's parameter
  // is a private field parameter, which another library cannot name.
  // ignore: use_super_parameters
  _FixedEntriesCalendarState(WorkoutRepository repository, this.entries)
    : super(repository);

  final List<CalendarEntry> entries;

  @override
  List<CalendarEntry> entriesForDay(DateTime day) => entries;
}

CalendarEntry _completedEntry(DateTime day) => CalendarEntry.fromSession(
  TrainingSession(
    id: 'completed-1',
    ownerUserId: 'u-1',
    startedAtMs: day.millisecondsSinceEpoch,
    endedAtMs: day.millisecondsSinceEpoch + 3600000,
    modality: 'resistance_lifting',
    createdAtMs: day.millisecondsSinceEpoch,
    updatedAtMs: day.millisecondsSinceEpoch,
  ),
);

CalendarEntry _inProgressEntry(DateTime day) => CalendarEntry.fromSession(
  TrainingSession(
    id: 'open-1',
    ownerUserId: 'u-1',
    startedAtMs: day.millisecondsSinceEpoch,
    modality: 'resistance_lifting',
    isRolling: true,
    createdAtMs: day.millisecondsSinceEpoch,
    updatedAtMs: day.millisecondsSinceEpoch,
  ),
);

CalendarEntry _plannedEntry(DateTime day) =>
    CalendarEntry.fromPlannedSession(
      PlannedSession(
        id: 'planned-1',
        ownerUserId: 'u-1',
        scheduledDateMs: OmniDateUtils.startOfDayMs(day),
        modality: 'cardio_endurance',
        title: 'Planned Cardio',
        createdAtMs: day.millisecondsSinceEpoch,
        updatedAtMs: day.millisecondsSinceEpoch,
      ),
    );

/// Pushes a [ModalityPickerDialog] as a route over a host button and hands the
/// route's result to [capture].
Future<void> _pumpPickerHost(
  WidgetTester tester,
  void Function(Object? value) capture,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                capture(
                  await Navigator.of(context).push<Object>(
                    MaterialPageRoute<Object>(
                      builder: (_) => const ModalityPickerDialog(),
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // S-2602 — ModalityPickerDialog
  // ══════════════════════════════════════════════════════════════════════════
  group('Mock S-2602 ModalityPickerDialog', () {
    testWidgets('no OutlinedButton; Cancel is a TextButton with the D-26.2 '
        'shape', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ModalityPickerDialog())),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.byType(TextButton), findsOneWidget);

      final cancel = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Cancel'),
      );
      final shape = cancel.style?.shape?.resolve(<WidgetState>{});
      expect(shape, isA<RoundedRectangleBorder>());
      expect(
        (shape! as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(OmniTheme.buttonUtilityRadius),
      );
    });

    testWidgets('a row still returns (true, modality)', (tester) async {
      Object? popped;
      await _pumpPickerHost(tester, (value) => popped = value);

      await tester.tap(find.text('Cardio'));
      await tester.pumpAndSettle();

      expect(popped, (true, 'cardio_endurance'));
    });

    testWidgets('Cancel returns null', (tester) async {
      Object? popped = 'unset';
      await _pumpPickerHost(tester, (value) => popped = value);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(popped, isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // S-2605a — RecentPRList
  // ══════════════════════════════════════════════════════════════════════════

  group('Mock S-2605a RecentPRList', () {
    testWidgets('the RECENT PRS header sits above the card, not inside it', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      final repo = await _freshRepo();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecentPRList(
                prs: [
                  StatsPR(
                    exerciseName: 'Back Squat',
                    date: DateTime(2026, 3, 4),
                    e1Rm: 120,
                  ),
                ],
                settingsState: SettingsState(repo, fakePreferencesService()),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('RECENT PRS'), findsOneWidget);
      expect(find.byType(OmniCardHeader), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(OmniCardHeader),
          matching: find.text('RECENT PRS'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(OmniSurface),
          matching: find.text('RECENT PRS'),
        ),
        findsNothing,
        reason: 'the title must live outside the card (D-26.4)',
      );
      expect(find.text('Recent PRs'), findsNothing);
      expect(
        tester.getTopLeft(find.byType(OmniCardHeader)).dy,
        lessThan(tester.getTopLeft(find.byType(OmniSurface)).dy),
      );

      // The rows the card owns are unchanged.
      expect(find.text('Back Squat'), findsOneWidget);
    });

    testWidgets('an empty list still renders the card', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      final repo = await _freshRepo();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecentPRList(
                prs: const [],
                settingsState: SettingsState(repo, fakePreferencesService()),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('RECENT PRS'), findsOneWidget);
      expect(find.byType(OmniSurface), findsOneWidget);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // S-2605b — DaySessionListScreen section headers
  // ══════════════════════════════════════════════════════════════════════════

  group('Mock S-2605b DaySessionListScreen headers', () {
    testWidgets('a completed, a planned and an open session give three '
        'uppercase OmniCardHeaders', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      final repo = await _freshRepo();
      final day = DateTime(2099, 12, 31);
      final calendarState = _FixedEntriesCalendarState(repo, [
        _completedEntry(day),
        _inProgressEntry(day),
        _plannedEntry(day),
      ]);

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

      expect(find.byType(OmniCardHeader), findsNWidgets(3));
      for (final title in const ['COMPLETED', 'PLANNED', 'IN PROGRESS']) {
        expect(
          find.descendant(
            of: find.byType(OmniCardHeader),
            matching: find.text(title),
          ),
          findsOneWidget,
          reason: '$title must be an OmniCardHeader title',
        );
      }
      // The old private `_SectionHeader` labels are gone.
      expect(find.text('Completed'), findsNothing);
      expect(find.text('Planned'), findsNothing);
      expect(find.text('In Progress'), findsNothing);
    });

    testWidgets('no header renders when the day is empty', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      final repo = await _freshRepo();
      final calendarState = _FixedEntriesCalendarState(repo, const []);

      await tester.pumpWidget(
        MaterialApp(
          home: DaySessionListScreen(
            date: DateTime(2099, 12, 31),
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

      expect(find.byType(OmniCardHeader), findsNothing);
      expect(find.text('No sessions planned yet.'), findsOneWidget);
    });
  });
}
