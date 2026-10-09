// A watch session in history is rated the way PR 1 rates any session: its
// Session Summary, opened from the calendar, shows the wrist's rating and
// offers PR 1's control to add or change one.
//
// Plan: `docs/plans/2026-09-25-02-stats-pr2-watch-capture-plan.md`
// (Stats PR 2), Phase 5 — D-138, D-139.
// Scenario mapping:
//   S-285 the Summary offers to add a rating    → `S-285 ...`
//   S-286 the Summary shows the wrist's rating  → `S-286 ...`
//
// The session is imported the shipping way — F-CAP's events, one
// `observations_up` each, through `WatchSessionInbox.receive` — and opened the
// way a user reaches it: the calendar's day list, then its row.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/app.dart' show buildTheme;
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/core/services/routine_session_service.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/core/utils/modality_color_utils.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/calendar/day_session_list_screen.dart';
import 'package:omnitrain/features/session/session_summary_screen.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/watch/watch_session_inbox.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';
import 'helpers/sync_protocol_harness.dart';
import 'helpers/watch_capture_import_harness.dart';

const String _capId = 's-cap-1';
const Key _effortMarkerKey = Key('omni_session_effort_marker');

/// The app's real ThemeData for the active theme, as PR 1's Summary tests use.
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

IntensityRampPalette get _ramp => OmniTheme.colors.intensityRamp;

/// A phone that imported F-CAP's [caseName] from the wrist.
Future<MockWorkoutRepository> _importedCapture(String caseName) async {
  final repository = MockWorkoutRepository();
  await repository.initialize();
  await seedCaptureCatalog(repository);
  var ids = 0;
  final inbox = WatchSessionInbox(
    repository: repository,
    transport: CaptureTransport(),
    validator: loadProtocolValidator(),
    clock: () => DateTime.utc(2026, 9, 25, 11),
    idFactory: () => 'msg-phone-${++ids}',
    onFailure: Error.throwWithStackTrace,
  );
  final events = captureEvents(caseName);
  for (var i = 0; i < events.length; i++) {
    await inbox.receive(
      observationsUp(_capId, [events[i]], messageId: 'msg-$caseName-$i'),
    );
  }
  return repository;
}

/// Opens the calendar's day list on the day the imported session started, in
/// the phone's own time zone.
Future<void> _openDayList(
  WidgetTester tester,
  MockWorkoutRepository repository,
) async {
  tester.view.physicalSize = const Size(600, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final session = (await repository.getSession(_capId))!;
  final start = DateTime.fromMillisecondsSinceEpoch(session.startedAtMs);
  final calendar = CalendarState(repository);
  await calendar.init();
  while (calendar.year * 12 + calendar.month > start.year * 12 + start.month) {
    await calendar.goToPreviousMonth();
  }
  while (calendar.year * 12 + calendar.month < start.year * 12 + start.month) {
    await calendar.goToNextMonth();
  }

  await tester.pumpWidget(
    MaterialApp(
      theme: _appTheme(),
      home: DaySessionListScreen(
        date: DateTime(start.year, start.month, start.day),
        calendarState: calendar,
        routineState: RoutineState(repository),
        workoutState: WorkoutState(repository),
        routineSessionService: RoutineSessionService(repository),
        sessionSummaryService: SessionSummaryService(repository),
        settingsState: SettingsState(repository, fakePreferencesService()),
        timerAlertService: FakeTimerAlertService(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The day list's row for the imported session: a wrist session has no title
/// and no modality, so the row reads as the modality label for none (D-135).
Finder _importedRow() => find.text(ModalityColorUtils.labelForModality(null));

Future<void> _openSummary(WidgetTester tester) async {
  await tester.tap(_importedRow());
  await tester.pumpAndSettle();
  expect(find.byType(SessionSummaryScreen), findsOneWidget);
}

Future<void> _back(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.arrow_back));
  await tester.pumpAndSettle();
}

Future<void> _tapTile(WidgetTester tester, int n) async {
  final tile = find.descendant(
    of: find.byType(BottomSheet),
    matching: find.text('$n'),
  );
  await tester.ensureVisible(tile);
  await tester.tap(tile.first);
  await tester.pumpAndSettle();
}

Color _markerColor(WidgetTester tester) {
  final marker = tester.widget<Container>(find.byKey(_effortMarkerKey));
  return (marker.decoration! as BoxDecoration).color!;
}

/// The day list row's left tint — PR 1's calendar display of a rating.
Color? _rowTint(WidgetTester tester) {
  final tinted = tester
      .widgetList<Container>(
        find.ancestor(of: _importedRow(), matching: find.byType(Container)),
      )
      .where((c) {
        final d = c.decoration;
        return d is BoxDecoration &&
            d.border is Border &&
            (d.border! as Border).left.width == 4;
      })
      .toList();
  if (tinted.isEmpty) return null;
  return ((tinted.single.decoration! as BoxDecoration).border! as Border)
      .left
      .color;
}

// ─── S-329 — the totals ─────────────────────────────────────────────────────
//
// The rest total the Summary counts is the same whether the rest came from
// the wrist or from the phone's own timer, because both are one closed
// `EntryRest` of the effort the set preceded, over the same window
// (18c D-210 – D-219, 18d D-235).

/// The window the imported session covers, and the window inside it the one
/// rest covers, as the wrist sends them.
const String _sessionStart = '2026-09-25T10:00:00.000Z';
const String _sessionEnd = '2026-09-25T10:30:00.000Z';
const String _restStart = '2026-09-25T10:05:00.000Z';
const String _restEnd = '2026-09-25T10:06:10.000Z';

/// 10:05:00 → 10:06:10.
const int _restWindowMs = 70000;

/// The phone's own session, the control.
const String _phoneSessionId = 's-phone-1';

DateTime _at(String iso) => DateTime.parse(iso).toUtc();
int _atMs(String iso) => _at(iso).millisecondsSinceEpoch;

/// A phone that took a wrist session's set and rest over the wire: the set,
/// then the rest that followed it, then the end.
Future<MockWorkoutRepository> _importedSessionWithRest() async {
  final repository = MockWorkoutRepository();
  await repository.initialize();
  await seedCaptureCatalog(repository);
  var ids = 0;
  final inbox = WatchSessionInbox(
    repository: repository,
    transport: CaptureTransport(),
    validator: loadProtocolValidator(),
    clock: () => DateTime.utc(2026, 9, 25, 11),
    idFactory: () => 'msg-phone-${++ids}',
    onFailure: Error.throwWithStackTrace,
  );
  final events = <Map<String, Object?>>[
    {
      'entryId': 'e-set1',
      'eventId': 'e-set1',
      'kind': 'set',
      'loggedAt': _restStart,
      'sessionExerciseId': 'sx-bench',
      'exerciseId': 'ex-bench',
      'reps': 5,
      'loadKg': 80,
    },
    {
      'entryId': 'e-rest1',
      'eventId': 'e-rest1',
      'kind': 'rest',
      'loggedAt': _restEnd,
      'sessionExerciseId': 'sx-bench',
      'exerciseId': 'ex-bench',
      'startedAt': _restStart,
      'endedAt': _restEnd,
      'afterEntryId': 'e-set1',
    },
    {
      'entryId': 'end-$_capId',
      'eventId': 'end-$_capId',
      'kind': 'session_end',
      'loggedAt': _sessionEnd,
      'startedAt': _sessionStart,
      'endedAt': _sessionEnd,
      'status': 'completed',
    },
  ];
  for (var i = 0; i < events.length; i++) {
    await inbox.receive(
      observationsUp(_capId, [events[i]], messageId: 'msg-s329-$i'),
    );
  }
  return repository;
}

/// The phone's own session over the same window, with the rest its timer
/// leaves at the spot the set precedes — `rest-{effortId}-1`, closed and
/// never paused, exactly as `TimerManager.recordRestEnd` persists it.
Future<MockWorkoutRepository> _phoneCountedSessionWithRest() async {
  final repository = MockWorkoutRepository();
  await repository.initialize();
  final startedAtMs = _atMs(_sessionStart);
  await repository.createSession(
    TrainingSession(
      id: _phoneSessionId,
      ownerUserId: 'user-1',
      startedAtMs: startedAtMs,
      endedAtMs: _atMs(_sessionEnd),
      title: 'Bench Session',
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );
  await repository.createSegment(
    SessionSegment(
      id: 'seg-$_phoneSessionId',
      sessionId: _phoneSessionId,
      orderIndex: 0,
      segmentType: 'workout',
      name: 'Main Workout',
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );
  final effortId = 'e-$_phoneSessionId-0';
  await repository.createEffort(
    SegmentEffort(
      id: effortId,
      segmentId: 'seg-$_phoneSessionId',
      orderIndex: 0,
      topLevelOrderIndex: 0,
      effortKind: 'set',
      exerciseId: 'ex-bench',
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );
  await repository.createEntryRest(
    EntryRest(
      id: 'rest-$effortId-1',
      effortId: effortId,
      entryIndex: 1,
      restStartMs: _atMs(_restStart),
      restEndMs: _atMs(_restEnd),
      createdAtMs: _atMs(_restEnd),
      updatedAtMs: _atMs(_restEnd),
    ),
  );
  return repository;
}

/// The one rest row of [sessionId]'s single effort.
Future<EntryRest> _onlyRest(
  MockWorkoutRepository repository,
  String sessionId,
) async {
  final segment = (await repository.getSessionSegments(sessionId)).single;
  final effort = (await repository.getSegmentEfforts(segment.id)).single;
  final rests = await repository.getEntryRests(effort.id);
  expect(rests, hasLength(1), reason: 'S-329 the session holds one rest');
  return rests.single;
}

void main() {
  group('S-285 the Summary offers to add a rating', () {
    testWidgets('S-285 an imported watch session with no rating offers '
        'PR 1’s add control, and the rating it adds survives reopening', (
      tester,
    ) async {
      // `prompt-off`: the wrist never asked, so the session has no rating.
      final repository = await _importedCapture('prompt-off');
      expect(
        (await repository.getSession(_capId))?.sessionFeeling,
        isNull,
        reason: 'S-285 the imported session has no rating',
      );

      await _openDayList(tester, repository);
      expect(
        _rowTint(tester),
        isNull,
        reason: 'S-285 an unrated session carries no rating tint',
      );
      await _openSummary(tester);

      expect(
        find.text('How hard was this session?'),
        findsNothing,
        reason: 'S-285 a calendar-opened summary asks nothing on its own',
      );
      expect(
        find.text('Add rating'),
        findsOneWidget,
        reason: 'S-285 PR 1’s add-rating control',
      );
      expect(
        find.byKey(_effortMarkerKey),
        findsNothing,
        reason: 'S-285 no rating, no marker',
      );

      await tester.tap(find.text('Add rating'));
      await tester.pumpAndSettle();
      await _tapTile(tester, 4);

      expect(find.text('4 / 5'), findsOneWidget, reason: 'S-285 added');
      expect(
        (await repository.getSession(_capId))?.sessionFeeling,
        4,
        reason: 'S-285 the rating persists',
      );

      await _back(tester);
      expect(find.byType(SessionSummaryScreen), findsNothing);
      expect(
        _rowTint(tester),
        _ramp.step4,
        reason: 'S-285 the day list shows the new rating on return',
      );

      await _openSummary(tester);
      expect(
        find.text('4 / 5'),
        findsOneWidget,
        reason: 'S-285 the rating survives reopening',
      );
      expect(find.text('Change'), findsOneWidget, reason: 'S-285');
      expect(_markerColor(tester), _ramp.step4, reason: 'S-285');
    });
  });

  group('S-286 the Summary shows the wrist’s rating', () {
    testWidgets('S-286 an imported watch session shows the wrist’s rating '
        'as PR 1 displays ratings', (tester) async {
      // `full`: the wrist asked, and the user answered 4.
      final repository = await _importedCapture('full');
      expect(
        (await repository.getSession(_capId))?.sessionFeeling,
        4,
        reason: 'S-286 the import carries the wrist’s rating',
      );

      await _openDayList(tester, repository);
      expect(
        _rowTint(tester),
        _ramp.step4,
        reason: 'S-286 the day list tints the row with the rating’s step',
      );
      await _openSummary(tester);

      expect(
        find.text('4 / 5'),
        findsOneWidget,
        reason: 'S-286 the EFFORT row shows the wrist’s rating',
      );
      expect(
        _markerColor(tester),
        _ramp.step4,
        reason: 'S-286 its intensity marker is the rating’s ramp step',
      );
      expect(
        find.text('Change'),
        findsOneWidget,
        reason: 'S-286 a rated session offers PR 1’s Change control',
      );
      expect(
        find.text('How hard was this session?'),
        findsNothing,
        reason: 'S-286 and asks nothing on its own',
      );
    });
  });

  group('S-329 the totals', () {
    test('S-329 a rest the wrist sent and a rest the phone counted, over the '
        'same window, total the same', () async {
      final imported = await _importedSessionWithRest();
      final counted = await _phoneCountedSessionWithRest();

      // The imported rest landed as one closed, unpaused row after the set
      // it followed (18c D-210, D-214) — the shape the total counts.
      final importedRest = await _onlyRest(imported, _capId);
      expect(importedRest.entryIndex, 1, reason: 'S-329 the rest follows the set');
      expect(importedRest.id, 'rest-${importedRest.effortId}-1', reason: 'S-329');
      expect(
        importedRest.restStartMs,
        _atMs(_restStart),
        reason: 'S-329 the window is the one the wrist sent',
      );
      expect(importedRest.restEndMs, _atMs(_restEnd), reason: 'S-329');
      expect(
        importedRest.restIsPaused,
        isFalse,
        reason: 'S-329 a watch rest arrives closed and unpaused',
      );
      expect(importedRest.restPausedDurationMs, 0, reason: 'S-329');

      final importedTotal = await SessionSummaryService(
        imported,
      ).computeSessionRestTimeMs(_capId);
      final countedTotal = await SessionSummaryService(
        counted,
      ).computeSessionRestTimeMs(_phoneSessionId);

      expect(
        importedTotal,
        _restWindowMs,
        reason: 'S-329 the wrist’s 10:05:00…10:06:10 rest is 70 s of the '
            'session’s 10:00:00…10:30:00 window',
      );
      expect(
        countedTotal,
        _restWindowMs,
        reason: 'S-329 the phone’s own rest over that window is 70 s too',
      );
      expect(
        importedTotal,
        countedTotal,
        reason: 'S-329 the wrist’s rest is counted exactly as the phone’s own',
      );
      final countedRest = await _onlyRest(counted, _phoneSessionId);
      expect(
        [
          countedRest.entryIndex,
          countedRest.restStartMs,
          countedRest.restEndMs,
          countedRest.restIsPaused,
          countedRest.restPausedDurationMs,
        ],
        [
          importedRest.entryIndex,
          importedRest.restStartMs,
          importedRest.restEndMs,
          importedRest.restIsPaused,
          importedRest.restPausedDurationMs,
        ],
        reason: 'S-329 both writers leave the same rest: the same spot, the '
            'same window, never paused',
      );
    });
  });
}
