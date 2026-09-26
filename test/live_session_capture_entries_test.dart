// The Watch Session screen counts what the user logged, not what the wrist
// reports about the session as a whole.
//
// Plan: `.github/agents/plans/2026-09-25-02-stats-pr2-watch-capture-plan.md`
// (Stats PR 2), D-141.
// Scenario mapping:
//   S-254 effort entries only → `S-254 ...`
//
// A wrist that ends a session reports an `effort_rating` and a `session_end`
// alongside the entries the user logged (PROTOCOL.md, "Session capture"). Both
// are session-scoped: neither is a set, a timed effort, a round or a hold, so
// neither is a row in the LOGGED list or a unit of "logged" in any count.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/live_session_screen.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/watch/live_session_mirror_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/live_session_fixtures.dart';

/// The session id `liveWatchSession` holds.
const String _sessionId = 's-live-ui';

/// The session effort rating, as a wrist reports it inside a snapshot.
Map<String, Object?> _ratingEntry() => {
  'entryId': 'rating-$_sessionId',
  'eventId': 'rating-$_sessionId',
  'kind': 'effort_rating',
  'loggedAt': '2026-07-13T06:40:20Z',
  'rating': 4,
};

/// The session end, as a wrist reports it inside a snapshot.
Map<String, Object?> _endEntry() => {
  'entryId': 'end-$_sessionId',
  'eventId': 'end-$_sessionId',
  'kind': 'session_end',
  'loggedAt': '2026-07-13T06:40:00Z',
  'startedAt': '2026-07-13T05:30:00Z',
  'endedAt': '2026-07-13T06:40:00Z',
  'status': 'completed',
};

void main() {
  late MockWorkoutRepository repository;
  late SettingsState settings;

  setUp(() async {
    repository = MockWorkoutRepository();
    await repository.initialize();
    settings = SettingsState(repository, fakePreferencesService());
    await settings.initialize();
  });

  Future<void> pumpScreen(
    WidgetTester tester,
    LiveSessionMirrorState liveSession,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: LiveSessionScreen(
          liveSession: liveSession,
          workoutState: WorkoutState(repository),
          settingsState: settings,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('S-254 the Watch Session screen lists effort entries only', () {
    testWidgets('S-254 the LOGGED list shows the set and nothing else', (
      tester,
    ) async {
      final liveSession = liveWatchSession(
        entries: [liveSessionEntry('e-1'), _ratingEntry(), _endEntry()],
      );
      expect(
        liveSession.entries,
        hasLength(3),
        reason: 'the mirror holds all three: it is the screen that filters',
      );

      await pumpScreen(tester, liveSession);

      expect(
        find.byKey(const Key('live_session_entry_e-1')),
        findsOneWidget,
        reason: 'S-254 the set is listed',
      );
      expect(
        find.byKey(const Key('live_session_entry_rating-$_sessionId')),
        findsNothing,
        reason: 'S-254 the effort rating is not a logged row',
      );
      expect(
        find.byKey(const Key('live_session_entry_end-$_sessionId')),
        findsNothing,
        reason: 'S-254 the session end is not a logged row',
      );
    });

    testWidgets('S-254 the status counts one logged entry', (tester) async {
      await pumpScreen(
        tester,
        liveWatchSession(
          entries: [liveSessionEntry('e-1'), _ratingEntry(), _endEntry()],
        ),
      );

      expect(
        find.text('1 of 3 · 1 logged'),
        findsOneWidget,
        reason: 'S-254 the status reads "1 logged"',
      );
    });

    testWidgets('S-254 the completed card counts one logged entry', (
      tester,
    ) async {
      final liveSession = liveWatchSession(
        entries: [liveSessionEntry('e-1'), _ratingEntry(), _endEntry()],
      );
      await pumpScreen(tester, liveSession);

      await tester.tap(find.byKey(const Key('live_session_finish')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('live_session_completed')), findsOneWidget);
      expect(
        find.text(
          '1 logged across 3 exercises — '
          'everything both devices recorded, in order.',
        ),
        findsOneWidget,
        reason: 'S-254 the completed card counts 1',
      );
      expect(
        (liveSession.completedRecord!['entries']! as List).length,
        3,
        reason: 'the record itself keeps every entry; only the count filters',
      );
    });
  });
}
