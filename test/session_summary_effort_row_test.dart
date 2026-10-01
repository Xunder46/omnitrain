import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/app.dart' show buildTheme;
import 'package:omnitrain/core/constants/modality.dart';
import 'package:omnitrain/core/constants/modality_display.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/core/services/routine_session_service.dart';
import 'package:omnitrain/core/utils/session_feeling_utils.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/calendar/day_session_list_screen.dart';
import 'package:omnitrain/features/session/session_summary_screen.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

// Helper to create a fresh mock repo
Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

/// The app's real ThemeData for the active theme, so `colorScheme.onPrimary`
/// (which the rating tiles read) is the production value, not Material's
/// default white.
ThemeData _appTheme() {
  final theme = OmniTheme.activeTheme;
  final colors = OmniTheme.colorsForTheme(theme);
  return buildTheme(
    theme: theme,
    brightness: Brightness.dark,
    secondary: colors.secondary,
    background: colors.backgroundBottom,
    surface: colors.surface,
    textPrimary: colors.textDominant,
    textSecondary: colors.textSecondary,
    divider: colors.divider,
    onPrimary: getOnPrimaryForTheme(theme),
    onSecondary: getOnSecondaryForTheme(theme),
  );
}

const _effortMarkerKey = Key('omni_session_effort_marker');
const _sheetTitle = 'How hard was this session?';

void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(600, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// [text] inside the open rating sheet (the Summary behind it also
/// renders digits, e.g. in the calendar grid).
Finder _inSheet(String text) => find.descendant(
  of: find.byType(BottomSheet),
  matching: find.text(text),
);

Future<void> _tapTile(WidgetTester tester, int n) async {
  final tile = _inSheet('$n');
  await tester.ensureVisible(tile);
  await tester.tap(tile.first);
  await tester.pumpAndSettle();
}

/// The box decoration of rating tile [n] in the open sheet.
BoxDecoration _tileDecoration(WidgetTester tester, int n) {
  final tile = tester.widget<AnimatedContainer>(
    find.ancestor(of: _inSheet('$n'), matching: find.byType(AnimatedContainer)),
  );
  return tile.decoration! as BoxDecoration;
}

/// The value text of the stat pill labelled [label] (the pill upper-cases
/// its label, so pass e.g. 'EFFORT').
Text _pillValue(WidgetTester tester, String label) {
  final pill = find
      .ancestor(of: find.text(label), matching: find.byType(Column))
      .first;
  final values = tester
      .widgetList<Text>(find.descendant(of: pill, matching: find.byType(Text)))
      .where((t) => t.data != label)
      .toList();
  expect(values, hasLength(1), reason: '$label pill must have one value');
  return values.single;
}

Color _markerColor(WidgetTester tester) {
  final marker = tester.widget<Container>(find.byKey(_effortMarkerKey));
  return (marker.decoration! as BoxDecoration).color!;
}

IntensityRampPalette get _ramp => OmniTheme.colors.intensityRamp;

// Helper to build SessionSummaryScreen with all required dependencies
Future<Widget> _buildSessionSummaryScreen({
  required WorkoutState workoutState,
  required MockWorkoutRepository repo,
  bool showFeelingSurvey = true,
  bool openedFromCalendar = false,
}) async {
  final routineState = RoutineState(repo);
  final sessionSummaryService = SessionSummaryService(repo);
  final prefs = fakePreferencesService();
  final settingsState = SettingsState(repo, prefs);

  if (!showFeelingSurvey) {
    await settingsState.setShowFeelingSurvey(false);
  }

  return MaterialApp(
    theme: _appTheme(),
    home: SessionSummaryScreen(
      workoutState: workoutState,
      routineState: routineState,
      sessionSummaryService: sessionSummaryService,
      settingsState: settingsState,
      timerAlertService: FakeTimerAlertService(),
      openedFromCalendar: openedFromCalendar,
    ),
  );
}

void main() {
  group('SessionSummaryScreen EFFORT row (Phase 3)', () {
    testWidgets(
      'Task 1a: Automatic prompt with survey ON — EFFORT row refreshes after prompt closes',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(600, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        await workoutState.createNewSession();
        final session = workoutState.currentSession!;

        await tester.pumpWidget(await _buildSessionSummaryScreen(
          workoutState: workoutState,
          repo: repo,
          showFeelingSurvey: true,
        ));
        await tester.pumpAndSettle();

        // Verify automatic prompt is open
        expect(find.text('How hard was this session?'), findsOneWidget);

        // The end labels are the effort anchors, not the old feeling words.
        expect(_inSheet('Very easy'), findsOneWidget);
        expect(_inSheet('Max effort'), findsOneWidget);
        expect(find.text('Rough'), findsNothing);
        expect(find.text('Great'), findsNothing);

        // F-4: the system back button must not close a must-answer prompt.
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(
          find.text('How hard was this session?'),
          findsOneWidget,
          reason:
              'F-4 the system back button does not close a must-answer sheet',
        );

        // Tap tile 4 on the automatic prompt (scoped to BottomSheet)
        final tile4 = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('4'),
        );
        await tester.ensureVisible(tile4);
        await tester.tap(tile4.first);
        await tester.pumpAndSettle();

        // Sheet closes
        expect(find.text('How hard was this session?'), findsNothing);

        // CRITICAL: After automatic prompt closes, EFFORT row MUST show the value
        // This test FAILS without setState in _showFeelingSheet
        expect(find.text('4 / 5'), findsOneWidget, reason: 'EFFORT row must refresh after automatic prompt');
        expect(find.text('Change'), findsOneWidget);

        // Verify repository has the value
        final updated = await repo.getSession(session.id);
        expect(updated?.sessionFeeling, 4);
      },
    );

    testWidgets(
      'Task 1b: User-opened sheet with survey OFF — setState needed for refresh',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(600, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        await workoutState.createNewSession();
        final session = workoutState.currentSession!;

        await tester.pumpWidget(await _buildSessionSummaryScreen(
          workoutState: workoutState,
          repo: repo,
          showFeelingSurvey: false, // No automatic prompt
        ));
        await tester.pumpAndSettle();

        // No automatic prompt, unrated state
        expect(find.text('How hard was this session?'), findsNothing);
        expect(find.text('Add rating'), findsOneWidget);

        // Tap "Add rating"
        await tester.tap(find.text('Add rating'));
        await tester.pumpAndSettle();

        expect(find.text('How hard was this session?'), findsOneWidget);

        // Tap tile 4 on user-opened sheet
        final tile4 = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('4'),
        );
        await tester.ensureVisible(tile4);
        await tester.tap(tile4.first);
        await tester.pumpAndSettle();

        expect(find.text('How hard was this session?'), findsNothing);

        // CRITICAL: User-opened sheet needs setState to refresh
        // This test FAILS without setState in _openEffortRatingSheet
        expect(find.text('4 / 5'), findsOneWidget, reason: 'EFFORT row must refresh after user-opened sheet');
        expect(find.text('Change'), findsOneWidget);

        final updated = await repo.getSession(session.id);
        expect(updated?.sessionFeeling, 4);
      },
    );

    testWidgets(
      'S-3: Fresh session — user adds rating from Summary (button path)',
      (WidgetTester tester) async {
        // Large surface to fit Summary + Sheet
        tester.view.physicalSize = const Size(600, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);

        // Create a fresh session (no rating)
        await workoutState.createNewSession();
        final session = workoutState.currentSession!;

        // TURN OFF automatic prompt so we test the button path
        await tester.pumpWidget(await _buildSessionSummaryScreen(
          workoutState: workoutState,
          repo: repo,
          showFeelingSurvey: false,
        ));
        await tester.pumpAndSettle();

        // Verify no automatic prompt, EFFORT row shows unrated state:
        // the dash is the EFFORT value (the only one on the screen) and
        // there is no intensity marker.
        expect(find.text('How hard was this session?'), findsNothing);
        expect(find.text('—'), findsOneWidget);
        expect(_pillValue(tester, 'EFFORT').data, '—');
        expect(find.byKey(_effortMarkerKey), findsNothing,
            reason: 'an unrated session has no intensity marker');
        expect(find.text('Add rating'), findsOneWidget);

        // Tap "Add rating" button
        await tester.tap(find.text('Add rating'));
        await tester.pumpAndSettle();

        // Verify sheet is open
        expect(find.text('How hard was this session?'), findsOneWidget);

        // Find the tile with "4" on the user-opened sheet
        final tile4 = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('4'),
        );
        await tester.ensureVisible(tile4);
        await tester.tap(tile4.first);
        await tester.pumpAndSettle();

        // Sheet should close, verify value is displayed
        expect(find.text('How hard was this session?'), findsNothing);
        expect(find.text('4 / 5'), findsOneWidget);
        expect(find.text('Change'), findsOneWidget);
        expect(_markerColor(tester), _ramp.step4);

        // Verify repository has the value
        final updated = await repo.getSession(session.id);
        expect(updated?.sessionFeeling, 4);
      },
    );

    testWidgets(
      'Fresh session — Change replaces an existing rating (button path)',
      (WidgetTester tester) async {
        _useTallSurface(tester);
        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        await workoutState.createNewSession();
        final session = workoutState.currentSession!;
        await workoutState.updateSessionFeeling(session.id, 2);

        await tester.pumpWidget(await _buildSessionSummaryScreen(
          workoutState: workoutState,
          repo: repo,
          showFeelingSurvey: false,
        ));
        await tester.pumpAndSettle();

        expect(find.text('2 / 5'), findsOneWidget);
        await tester.tap(find.text('Change'));
        await tester.pumpAndSettle();
        expect(find.text(_sheetTitle), findsOneWidget);

        await _tapTile(tester, 4);

        expect(find.text(_sheetTitle), findsNothing);
        expect(find.text('4 / 5'), findsOneWidget);
        expect(find.text('2 / 5'), findsNothing);
        expect(find.text('Change'), findsOneWidget);
        expect(_markerColor(tester), _ramp.step4);
        expect((await repo.getSession(session.id))?.sessionFeeling, 4);
      },
    );

    testWidgets(
      'Change sheet pre-selects the stored rating, and the selected tile '
      'number uses effortTileTextColor (ratings 1–5)',
      (WidgetTester tester) async {
        _useTallSurface(tester);
        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        await workoutState.createNewSession();

        await tester.pumpWidget(await _buildSessionSummaryScreen(
          workoutState: workoutState,
          repo: repo,
          showFeelingSurvey: false,
        ));
        await tester.pumpAndSettle();

        final colors = OmniTheme.colors;
        final rampSteps = [
          _ramp.step1,
          _ramp.step2,
          _ramp.step3,
          _ramp.step4,
          _ramp.step5,
        ];

        // Add rating 1 first, then walk the stored value through 2..5.
        await tester.tap(find.text('Add rating'));
        await tester.pumpAndSettle();
        await _tapTile(tester, 1);

        for (var stored = 1; stored <= 5; stored++) {
          expect(find.text('$stored / 5'), findsOneWidget);
          await tester.tap(find.text('Change'));
          await tester.pumpAndSettle();

          for (var n = 1; n <= 5; n++) {
            final fill = _tileDecoration(tester, n).color;
            if (n == stored) {
              expect(fill, rampSteps[n - 1],
                  reason: 'stored rating $stored must open pre-selected');
            } else {
              expect(fill, isNot(rampSteps[n - 1]),
                  reason: 'tile $n must not be selected when $stored is');
            }
          }

          // The selected number is drawn in the colour the helper picks
          // for this step with the theme's real onPrimary.
          final numberFinder = _inSheet('$stored');
          final onPrimary =
              Theme.of(tester.element(numberFinder)).colorScheme.onPrimary;
          final expected =
              effortTileTextColor(stored, colors, onPrimary: onPrimary);
          expect(expected, isNot(Colors.white),
              reason: 'guard: the app theme must be in effect');
          expect(tester.widget<Text>(numberFinder).style?.color, expected,
              reason: 'selected tile $stored number colour');

          if (stored < 5) {
            await _tapTile(tester, stored + 1);
          } else {
            // Close without choosing: tap the barrier above the sheet.
            await tester.tapAt(const Offset(100, 100));
            await tester.pumpAndSettle();
          }
        }
        expect(find.text(_sheetTitle), findsNothing);
        expect(find.text('5 / 5'), findsOneWidget);
      },
    );

    testWidgets(
      'EFFORT value is drawn in the stat pills\' shared value colour; the '
      'ramp step is carried by a 12×12 marker 8dp before the value',
      (WidgetTester tester) async {
        _useTallSurface(tester);
        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        await workoutState.createNewSession();
        await workoutState.updateSessionFeeling(
            workoutState.currentSession!.id, 1);

        await tester.pumpWidget(await _buildSessionSummaryScreen(
          workoutState: workoutState,
          repo: repo,
          showFeelingSurvey: false,
        ));
        await tester.pumpAndSettle();

        final effortValue = _pillValue(tester, 'EFFORT');
        expect(effortValue.data, '1 / 5');
        expect(
          effortValue.style?.color,
          _pillValue(tester, 'DURATION').style?.color,
          reason: 'the value text must use the default pill colour, '
              'not the ramp (step 1 is ~1.8:1 — below the text floor)',
        );
        expect(effortValue.style?.color, isNot(_ramp.step1));

        final marker = tester.widget<Container>(find.byKey(_effortMarkerKey));
        final decoration = marker.decoration! as BoxDecoration;
        expect(decoration.color, _ramp.step1);
        expect(decoration.borderRadius, BorderRadius.circular(3));
        expect(tester.getSize(find.byKey(_effortMarkerKey)),
            const Size(12, 12));
        final markerRect = tester.getRect(find.byKey(_effortMarkerKey));
        final valueRect = tester.getRect(find.text('1 / 5'));
        expect(valueRect.left - markerRect.right, 8,
            reason: 'marker sits immediately before the value, 8dp gap');
        expect(markerRect.center.dy, closeTo(valueRect.center.dy, 0.5),
            reason: 'marker is vertically centred on the value');
      },
    );

    testWidgets(
      'S-6: a session stored with 5 before any interaction shows "5 / 5" '
      'and still stores 5 (no conversion)',
      (WidgetTester tester) async {
        _useTallSurface(tester);
        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        final monthAgo = DateTime.now().subtract(const Duration(days: 30));
        const sessionId = 'pre-redefinition-session';
        await repo.createSession(TrainingSession(
          id: sessionId,
          ownerUserId: 'u-1',
          startedAtMs: monthAgo.millisecondsSinceEpoch,
          endedAtMs:
              monthAgo.add(const Duration(minutes: 50)).millisecondsSinceEpoch,
          title: 'Old Great Session',
          modality: Modality.resistanceLifting,
          sessionFeeling: 5, // answered "Great" under the old survey
          createdAtMs: monthAgo.millisecondsSinceEpoch,
          updatedAtMs: monthAgo.millisecondsSinceEpoch,
        ));
        await workoutState.loadHistoricalSession(sessionId);

        await tester.pumpWidget(await _buildSessionSummaryScreen(
          workoutState: workoutState,
          repo: repo,
          openedFromCalendar: true,
        ));
        await tester.pumpAndSettle();

        expect(find.text(_sheetTitle), findsNothing);
        expect(_pillValue(tester, 'EFFORT').data, '5 / 5');
        expect(_markerColor(tester), _ramp.step5);
        expect(find.text('Change'), findsOneWidget);
        expect(find.text('Great'), findsNothing);
        expect((await repo.getSession(sessionId))?.sessionFeeling, 5);
      },
    );

    testWidgets(
      'Change sheet swiped down closes it without changing the rating',
      (WidgetTester tester) async {
        _useTallSurface(tester);
        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        await workoutState.createNewSession();
        final session = workoutState.currentSession!;
        await workoutState.updateSessionFeeling(session.id, 3);

        await tester.pumpWidget(await _buildSessionSummaryScreen(
          workoutState: workoutState,
          repo: repo,
          showFeelingSurvey: false,
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Change'));
        await tester.pumpAndSettle();
        expect(find.text(_sheetTitle), findsOneWidget);

        // Drag from the title (not a tile) straight down.
        await tester.drag(find.text(_sheetTitle), const Offset(0, 600));
        await tester.pumpAndSettle();

        expect(find.text(_sheetTitle), findsNothing);
        expect(find.text('3 / 5'), findsOneWidget);
        expect((await repo.getSession(session.id))?.sessionFeeling, 3);
      },
    );

    testWidgets(
      'Sheet subtitle reads "· Today" for a session that started today',
      (WidgetTester tester) async {
        _useTallSurface(tester);
        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        await workoutState.createNewSession();
        final modality = workoutState.currentSession!.modality;

        await tester.pumpWidget(await _buildSessionSummaryScreen(
          workoutState: workoutState,
          repo: repo,
        ));
        await tester.pumpAndSettle();

        expect(find.text(_sheetTitle), findsOneWidget);
        expect(
          _inSheet('${ModalityDisplay.getName(modality)} · Today'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Sheet subtitle shows the session date (not "Today") for a past '
      'session opened from the calendar',
      (WidgetTester tester) async {
        _useTallSurface(tester);
        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        final startedAt = DateTime(2025, 3, 7, 9, 30);
        const sessionId = 'past-subtitle-session';
        await repo.createSession(TrainingSession(
          id: sessionId,
          ownerUserId: 'u-1',
          startedAtMs: startedAt.millisecondsSinceEpoch,
          endedAtMs: startedAt
              .add(const Duration(minutes: 40))
              .millisecondsSinceEpoch,
          title: 'Past Lift',
          modality: Modality.resistanceLifting,
          createdAtMs: startedAt.millisecondsSinceEpoch,
          updatedAtMs: startedAt.millisecondsSinceEpoch,
        ));
        await workoutState.loadHistoricalSession(sessionId);

        await tester.pumpWidget(await _buildSessionSummaryScreen(
          workoutState: workoutState,
          repo: repo,
          openedFromCalendar: true,
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Add rating'));
        await tester.pumpAndSettle();

        final name = ModalityDisplay.getName(Modality.resistanceLifting);
        expect(_inSheet('$name · Mar 7'), findsOneWidget);
        expect(_inSheet('$name · Today'), findsNothing);
      },
    );

    testWidgets(
      'S-5: day list → rated-5 session → Summary → Change to 1 → back: '
      'the row is re-tinted with ramp step 1',
      (WidgetTester tester) async {
        _useTallSurface(tester);
        final repo = await _freshRepo();
        final today = DateTime.now();
        final startedAt = DateTime(today.year, today.month, today.day, 0, 5);
        const sessionId = 'calendar-rated-five';
        const title = 'Rated Five Lift';
        await repo.createSession(TrainingSession(
          id: sessionId,
          ownerUserId: 'u-1',
          startedAtMs: startedAt.millisecondsSinceEpoch,
          endedAtMs: startedAt
              .add(const Duration(minutes: 30))
              .millisecondsSinceEpoch,
          title: title,
          modality: Modality.resistanceLifting,
          sessionFeeling: 5,
          createdAtMs: startedAt.millisecondsSinceEpoch,
          updatedAtMs: startedAt.millisecondsSinceEpoch,
        ));

        final calendarState = CalendarState(repo);
        await calendarState.init();
        final settingsState = SettingsState(repo, fakePreferencesService());

        await tester.pumpWidget(MaterialApp(
          theme: _appTheme(),
          home: DaySessionListScreen(
            date: DateTime(today.year, today.month, today.day),
            calendarState: calendarState,
            routineState: RoutineState(repo),
            workoutState: WorkoutState(repo),
            routineSessionService: RoutineSessionService(repo),
            sessionSummaryService: SessionSummaryService(repo),
            settingsState: settingsState,
            timerAlertService: FakeTimerAlertService(),
          ),
        ));
        await tester.pumpAndSettle();

        Color leftTint() {
          final tinted = tester
              .widgetList<Container>(find.ancestor(
                of: find.text(title),
                matching: find.byType(Container),
              ))
              .where((c) {
                final d = c.decoration;
                return d is BoxDecoration &&
                    d.border is Border &&
                    (d.border! as Border).left.width == 4;
              })
              .toList();
          expect(tinted, hasLength(1), reason: 'row must carry a left tint');
          return ((tinted.single.decoration! as BoxDecoration).border!
                  as Border)
              .left
              .color;
        }

        expect(leftTint(), _ramp.step5);

        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
        expect(find.byType(SessionSummaryScreen), findsOneWidget);
        expect(find.text('5 / 5'), findsOneWidget);

        await tester.tap(find.text('Change'));
        await tester.pumpAndSettle();
        await _tapTile(tester, 1);
        expect(find.text('1 / 5'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();
        expect(find.byType(SessionSummaryScreen), findsNothing);

        expect((await repo.getSession(sessionId))?.sessionFeeling, 1);
        expect(leftTint(), _ramp.step1,
            reason: 'the day list must show the new rating on return');
      },
    );

    testWidgets(
      'S-4/S-5: Historical session — add and change rating (opened from calendar)',
      (WidgetTester tester) async {
        // Large surface to fit Summary + Sheet
        tester.view.physicalSize = const Size(600, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);

        // Create a past session with no rating
        final yesterday = DateTime.now().subtract(const Duration(days: 1));
        final sessionId = 'historical-session';
        final session = TrainingSession(
          id: sessionId,
          ownerUserId: 'u-1',
          startedAtMs: yesterday.millisecondsSinceEpoch,
          endedAtMs: yesterday.add(const Duration(minutes: 45)).millisecondsSinceEpoch,
          title: 'Yesterday Session',
          modality: 'cardioEndurance',
          sessionFeeling: null,
          createdAtMs: yesterday.millisecondsSinceEpoch,
          updatedAtMs: yesterday.millisecondsSinceEpoch,
        );
        await repo.createSession(session);

        // Load historical session
        await workoutState.loadHistoricalSession(sessionId);

        // OPENED FROM CALENDAR so no automatic prompt appears even with survey ON
        await tester.pumpWidget(await _buildSessionSummaryScreen(
          workoutState: workoutState,
          repo: repo,
          openedFromCalendar: true,
        ));
        await tester.pumpAndSettle();

        // No automatic prompt
        expect(find.text('How hard was this session?'), findsNothing, reason: 'Historical summary must not show automatic prompt');

        // Add rating: tap "Add rating"
        expect(find.text('Add rating'), findsOneWidget);
        await tester.tap(find.text('Add rating'));
        await tester.pumpAndSettle();

        // Select rating 2
        final tile2 = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('2'),
        );
        await tester.ensureVisible(tile2);
        await tester.tap(tile2.first);
        await tester.pumpAndSettle();

        // Verify added
        expect(find.text('2 / 5'), findsOneWidget);
        var stored = await repo.getSession(sessionId);
        expect(stored?.sessionFeeling, 2);

        // Change rating: tap "Change"
        await tester.tap(find.text('Change'));
        await tester.pumpAndSettle();

        // Select rating 5
        final tile5 = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('5'),
        );
        await tester.ensureVisible(tile5);
        await tester.tap(tile5.first);
        await tester.pumpAndSettle();

        // Verify changed
        expect(find.text('5 / 5'), findsOneWidget);
        stored = await repo.getSession(sessionId);
        expect(stored?.sessionFeeling, 5);
      },
    );

    testWidgets(
      'S-5.5: User-opened sheet dismissed — value unchanged (button path)',
      (WidgetTester tester) async {
        // Large surface to fit Summary + Sheet
        tester.view.physicalSize = const Size(600, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);

        // Create session with rating 3
        await workoutState.createNewSession();
        final session = workoutState.currentSession!;
        await workoutState.updateSessionFeeling(session.id, 3);

        // TURN OFF automatic prompt for button path test
        await tester.pumpWidget(await _buildSessionSummaryScreen(
          workoutState: workoutState,
          repo: repo,
          showFeelingSurvey: false,
        ));
        await tester.pumpAndSettle();

        // Verify current value is 3
        expect(find.text('3 / 5'), findsOneWidget);

        // Tap "Change"
        await tester.tap(find.text('Change'));
        await tester.pumpAndSettle();

        // Dismiss by tapping barrier (outside the sheet, in the dim area)
        await tester.tapAt(const Offset(100, 100));
        await tester.pumpAndSettle();

        // Verify sheet is closed and value is unchanged
        expect(find.text('How hard was this session?'), findsNothing);
        expect(find.text('3 / 5'), findsOneWidget);

        // Verify repository was not updated
        final stored = await repo.getSession(session.id);
        expect(stored?.sessionFeeling, 3);
      },
    );

    testWidgets(
      'F-4: the user-opened Change sheet stays dismissible by the system '
      'back button',
      (WidgetTester tester) async {
        _useTallSurface(tester);
        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        await workoutState.createNewSession();
        final session = workoutState.currentSession!;
        await workoutState.updateSessionFeeling(session.id, 3);

        await tester.pumpWidget(await _buildSessionSummaryScreen(
          workoutState: workoutState,
          repo: repo,
          showFeelingSurvey: false,
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Change'));
        await tester.pumpAndSettle();
        expect(find.text(_sheetTitle), findsOneWidget);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(
          find.text(_sheetTitle),
          findsNothing,
          reason: 'F-4 a sheet the user opened themselves stays dismissible '
              'by the system back button',
        );
        expect(find.text('3 / 5'), findsOneWidget);
        expect((await repo.getSession(session.id))?.sessionFeeling, 3);
      },
    );

    testWidgets(
      'Task 3: Rolling session — EFFORT row visible, Duration/Rest hidden',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(600, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);

        // Create a new session, then make it rolling
        await workoutState.createNewSession();
        final sessionId = workoutState.currentSession!.id;

        // Update the session to be rolling with a rating
        final now = DateTime.now();
        final session = TrainingSession(
          id: sessionId,
          ownerUserId: 'u-1',
          startedAtMs: now.millisecondsSinceEpoch,
          endedAtMs: null, // No end = rolling
          title: 'Rolling Session',
          modality: null, // Free training
          sessionFeeling: 2, // Already has a rating
          createdAtMs: now.millisecondsSinceEpoch,
          updatedAtMs: now.millisecondsSinceEpoch,
          isRolling: true,
        );
        await repo.updateSession(session);

        // Reload to get the updated rolling session
        await workoutState.loadHistoricalSession(sessionId);

        await tester.pumpWidget(await _buildSessionSummaryScreen(
          workoutState: workoutState,
          repo: repo,
          showFeelingSurvey: false,
        ));
        await tester.pumpAndSettle();

        // EFFORT row MUST be visible for rolling sessions
        expect(find.text('EFFORT'), findsOneWidget, reason: 'EFFORT label must be visible');
        expect(find.text('2 / 5'), findsOneWidget, reason: 'EFFORT value must be visible');
        expect(find.text('Change'), findsOneWidget, reason: 'Change button must be visible');

        // Duration and Rest Time must be HIDDEN for rolling sessions
        expect(find.text('DURATION'), findsNothing, reason: 'Duration must be hidden in rolling session');
        expect(find.text('REST TIME'), findsNothing, reason: 'Rest Time must be hidden in rolling session');
      },
    );
  });
}
