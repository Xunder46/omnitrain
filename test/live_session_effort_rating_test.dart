// The phone's own Finish on the Watch Session screen, and the session effort
// rating it asks for.
//
// Plan: `docs/plans/2026-09-25-02-stats-pr2-watch-capture-plan.md`
// (Stats PR 2), Phase 5 — D-139.
// Scenario mapping:
//   S-281 phone Finish, setting on               → `S-281 ...`
//   S-282 phone Finish, setting off              → `S-282 ...`
//   S-283 the wrist ended it                     → `S-283 ...`
//   S-284 answered after the import landed       → `S-284 ...`
//   A-62  a session with nothing logged asks nothing → `A-62 ...`
// The inbox's half of the phone's rating (what is staged, what is written) is
// `test/watch_session_import_test.dart` (`S-281`, `S-284`).
//
// Everything below the screen is the shipping graph's: the mirror's transport
// stages the phone's own changes in the inbox (`WatchInboxStagingTransport`),
// and the wrist's events reach history through `WatchSessionInbox.receive`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/live_session_screen.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/watch/live_session_mirror_state.dart';
import 'package:omnitrain/state/watch/watch_session_inbox.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/session/effort_rating_sheet.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/sync_protocol_harness.dart';
import 'helpers/watch_capture_import_harness.dart';

const String _sessionId = 's-live-1';
const String _sheetTitle = 'How hard was this session?';

/// The phone's clock: fixed, so every stamp is the same on every run.
final DateTime _phoneNow = DateTime.utc(2026, 9, 25, 11);

/// The one set the wrist logged in `s-live-1`, as it sends it.
Map<String, Object?> _set() => {
  'entryId': 'e-1',
  'eventId': 'e-1',
  'kind': 'set',
  'loggedAt': '2026-09-25T10:05:00.000Z',
  'sessionExerciseId': 'sx-bench',
  'exerciseId': 'ex-bench',
  'reps': 5,
  'loadKg': 80,
};

/// The wrist's end for `s-live-1`: the phone's Finish ended it (D-120).
Map<String, Object?> _end() => {
  'entryId': 'end-$_sessionId',
  'eventId': 'end-$_sessionId',
  'kind': 'session_end',
  'loggedAt': '2026-09-25T10:20:00.000Z',
  'startedAt': '2026-09-25T10:00:00.000Z',
  'endedAt': '2026-09-25T10:20:00.000Z',
  'status': 'completed',
};

/// A wrist rating for `s-live-1` — adversarial: the phone ended the session,
/// so no wrist should send one (S-216), and if one arrives it must lose.
Map<String, Object?> _wristRating(int rating) => {
  'entryId': 'rating-$_sessionId',
  'eventId': 'rating-$_sessionId',
  'kind': 'effort_rating',
  'loggedAt': '2026-09-25T10:20:10.000Z',
  'rating': rating,
};

/// The phone's watch graph around one live session, as `createWatchSync`
/// builds it: the inbox, and a mirror whose transport stages in it.
class _Graph {
  _Graph._(
    this.repository,
    this.settings,
    this.transport,
    this.inbox,
    this.mirror,
    this._refreshes,
  );

  final MockWorkoutRepository repository;
  final SettingsState settings;
  final CaptureTransport transport;
  final WatchSessionInbox inbox;
  final LiveSessionMirrorState mirror;

  /// The calendar's refresh (D-142), as the shipping graph wires it.
  final int Function() _refreshes;

  int get refreshes => _refreshes();

  static Future<_Graph> build({
    bool effortRatingOn = true,
    List<Map<String, Object?>>? entries,
  }) async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    await seedCaptureCatalog(repository);
    final settings = SettingsState(repository, fakePreferencesService());
    await settings.initialize();
    await settings.setShowFeelingSurvey(effortRatingOn);

    final validator = loadProtocolValidator();
    final transport = CaptureTransport();
    var ids = 0;
    var refreshes = 0;
    final inbox = WatchSessionInbox(
      repository: repository,
      transport: transport,
      validator: validator,
      clock: () => _phoneNow,
      idFactory: () => 'msg-phone-${++ids}',
      onHistoryChanged: () async => refreshes++,
      // A failure inside the inbox fails the test where it happened.
      onFailure: Error.throwWithStackTrace,
    );
    final mirror = LiveSessionMirrorState(
      transport: WatchInboxStagingTransport(inner: transport, inbox: inbox),
      validator: validator,
      clock: () => _phoneNow,
      idFactory: () => 'msg-mirror-${++ids}',
      snapshot: {
        'sessionId': _sessionId,
        'status': 'active',
        'revision': 0,
        'currentExerciseIndex': 0,
        'exercises': [
          {
            'sessionExerciseId': 'sx-bench',
            'exerciseId': 'ex-bench',
            'name': 'Barbell Bench Press',
            'capabilities': ['sets', 'reps', 'load'],
          },
        ],
        'entries': entries ?? [_set()],
        'timers': const <String, Object?>{},
      },
    );
    return _Graph._(repository, settings, transport, inbox, mirror, () => refreshes);
  }

  /// The wrist's [events] for `s-live-1`, one envelope each.
  Future<void> deliver(List<Map<String, Object?>> events) async {
    for (var i = 0; i < events.length; i++) {
      await inbox.receive(
        observationsUp(_sessionId, [events[i]], messageId: 'msg-wrist-$i'),
      );
    }
  }

  Future<WatchInboxEntry?> stagedPhoneRating() =>
      repository.getWatchInboxEntry(WatchInboxEntry.phoneRatingId(_sessionId));

  List<Object?> lifecycleStatesSent() => [
    for (final envelope in transport.ofType('session_lifecycle'))
      (envelope['payload']! as Map)['state'],
  ];
}

Future<void> _pumpScreen(WidgetTester tester, _Graph graph) async {
  await tester.binding.setSurfaceSize(const Size(800, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: LiveSessionScreen(
        liveSession: graph.mirror,
        workoutState: WorkoutState(graph.repository),
        settingsState: graph.settings,
        watchSessionRatings: graph.inbox,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _finish(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('live_session_finish')));
  await tester.pumpAndSettle();
}

Future<void> _answer(WidgetTester tester, int rating) async {
  final tile = find.descendant(
    of: find.byType(BottomSheet),
    matching: find.text('$rating'),
  );
  await tester.ensureVisible(tile);
  await tester.tap(tile.first);
  await tester.pumpAndSettle();
}

void main() {
  group('S-281 the phone’s Finish, with the setting on', () {
    testWidgets('S-281 Finish asks PR 1’s question, which only an answer '
        'closes, and the answer is the phone’s own', (tester) async {
      final graph = await _Graph.build();
      await _pumpScreen(tester, graph);

      await _finish(tester);
      expect(
        find.byType(EffortRatingSheet),
        findsOneWidget,
        reason: 'S-281 the phone’s Finish shows PR 1’s effort-rating sheet',
      );
      expect(find.text(_sheetTitle), findsOneWidget, reason: 'S-281');
      expect(
        graph.lifecycleStatesSent(),
        ['completed'],
        reason:
            'S-281 the wrist is told the phone ended the session, which is '
            'why the wrist owes no prompt (S-216)',
      );

      // It must be answered: neither a tap outside nor a swipe closes it.
      await tester.tapAt(const Offset(24, 24));
      await tester.pumpAndSettle();
      expect(
        find.byType(EffortRatingSheet),
        findsOneWidget,
        reason: 'S-281 a tap outside the sheet does not close it',
      );
      await tester.drag(find.byType(BottomSheet), const Offset(0, 600));
      await tester.pumpAndSettle();
      expect(
        find.byType(EffortRatingSheet),
        findsOneWidget,
        reason: 'S-281 a swipe does not close it',
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        find.byType(EffortRatingSheet),
        findsOneWidget,
        reason: 'F-4 the system back button does not close it either',
      );
      expect(
        await graph.stagedPhoneRating(),
        isNull,
        reason: 'S-281 nothing is recorded until the user answers',
      );

      await _answer(tester, 3);
      expect(
        find.byType(EffortRatingSheet),
        findsNothing,
        reason: 'S-281 an answer closes it',
      );
      expect(
        find.byKey(const Key('live_session_completed')),
        findsOneWidget,
        reason: 'S-281 the screen shows the session the phone closed',
      );
      expect(
        (await graph.stagedPhoneRating())?.payload['rating'],
        3,
        reason:
            'S-281 nothing is imported yet, so the answer is staged as the '
            'phone’s own rating',
      );

      // The wrist's events arrive — with a wrist rating the phone must beat.
      await graph.deliver([_set(), _end(), _wristRating(5)]);
      expect(
        (await graph.repository.getSession(_sessionId))?.sessionFeeling,
        3,
        reason: 'S-281 the phone’s rating is the one history keeps',
      );
    });

    testWidgets('A-62 a session with nothing logged asks nothing', (
      tester,
    ) async {
      final graph = await _Graph.build(entries: const []);
      await _pumpScreen(tester, graph);

      await _finish(tester);
      expect(
        find.byType(EffortRatingSheet),
        findsNothing,
        reason:
            'A-62 an empty session is never history (D-133), so it is not '
            'rated — as the wrist does not ask for one (D-117)',
      );
      expect(
        find.byKey(const Key('live_session_completed')),
        findsOneWidget,
        reason: 'A-62 the Finish itself still closes the session',
      );
      expect(graph.lifecycleStatesSent(), ['completed'], reason: 'A-62');
      expect(await graph.stagedPhoneRating(), isNull, reason: 'A-62');
    });
  });

  group('S-282 the phone’s Finish, with the setting off', () {
    testWidgets('S-282 Finish closes the session and asks nothing', (
      tester,
    ) async {
      final graph = await _Graph.build(effortRatingOn: false);
      await _pumpScreen(tester, graph);

      await _finish(tester);
      expect(
        find.byType(EffortRatingSheet),
        findsNothing,
        reason: 'S-282 with the setting off there is no sheet',
      );
      expect(find.text(_sheetTitle), findsNothing, reason: 'S-282');
      expect(
        find.byKey(const Key('live_session_completed')),
        findsOneWidget,
        reason: 'S-282 the screen shows the session the phone closed',
      );
      expect(graph.lifecycleStatesSent(), ['completed'], reason: 'S-282');
      expect(
        await graph.stagedPhoneRating(),
        isNull,
        reason: 'S-282 nothing is recorded',
      );
    });
  });

  group('S-283 the wrist ended it', () {
    testWidgets('S-283 the screen shows the completed session, with no '
        'Finish and no sheet', (tester) async {
      final graph = await _Graph.build();
      await _pumpScreen(tester, graph);
      expect(
        find.byKey(const Key('live_session_finish')),
        findsOneWidget,
        reason: 'S-283 a running session offers Finish',
      );

      // The wrist's own End reaches the phone as its lifecycle message.
      final outcome = await graph.mirror.receive({
        'protocolVersion': 1,
        'messageId': 'msg-wrist-end',
        'sessionId': _sessionId,
        'type': 'session_lifecycle',
        'origin': 'watch',
        'sentAt': '2026-09-25T10:20:00Z',
        'payload': {'state': 'completed', 'at': '2026-09-25T10:20:00Z'},
      });
      await tester.pumpAndSettle();
      expect(outcome, MirrorOutcome.applied, reason: 'S-283');
      expect(graph.mirror.status, 'completed', reason: 'S-283');

      expect(
        find.byKey(const Key('live_session_completed')),
        findsOneWidget,
        reason: 'S-283 the screen shows the completed state',
      );
      expect(
        find.text(
          '1 logged across 1 exercise — '
          'everything both devices recorded, in order.',
        ),
        findsOneWidget,
        reason: 'S-283 what the wrist closed, counted as the phone counts it',
      );
      expect(
        find.byKey(const Key('live_session_finish')),
        findsNothing,
        reason: 'S-283 a session the wrist completed offers no Finish',
      );
      expect(
        find.byType(EffortRatingSheet),
        findsNothing,
        reason: 'S-283 and never asks: the wrist that ended it asks',
      );
      expect(
        graph.lifecycleStatesSent(),
        isEmpty,
        reason: 'S-283 the phone ended nothing',
      );
      expect(await graph.stagedPhoneRating(), isNull, reason: 'S-283');
    });
  });

  group('S-284 answered after the import landed', () {
    testWidgets('S-284 the answer is written to the imported session', (
      tester,
    ) async {
      final graph = await _Graph.build();
      await _pumpScreen(tester, graph);

      await _finish(tester);
      expect(find.byType(EffortRatingSheet), findsOneWidget, reason: 'S-284');

      // The wrist syncs while the question is still open: the session is
      // imported, with no rating of its own.
      await graph.deliver([_set(), _end()]);
      expect(
        (await graph.repository.getSession(_sessionId))?.sessionFeeling,
        isNull,
        reason: 'S-284 the import landed before the answer',
      );
      final refreshesBeforeAnswer = graph.refreshes;

      await _answer(tester, 2);
      expect(
        (await graph.repository.getSession(_sessionId))?.sessionFeeling,
        2,
        reason: 'S-284 the answer is written to sessionFeeling',
      );
      expect(
        await graph.stagedPhoneRating(),
        isNull,
        reason: 'S-284 directly: nothing is staged for an imported session',
      );
      expect(
        graph.refreshes,
        refreshesBeforeAnswer + 1,
        reason:
            'F-8 the answer to an imported session is a history change, so '
            'the calendar refreshes (D-142)',
      );
    });
  });
}
