// The state half of first-answer-wins: a rating the wrist's import wrote
// reaches the phone's live session, and the late automatic answer cannot
// replace it.
//
// Plan: `docs/plans/2026-10-19-42a-rating-wrist-answers-first-plan/`
// (42a, P1) — D-1, D-2.
// Scenario mapping:
//   S-4301 the wrist's answer settles once and the live session adopts it
//   S-4302 the phone's answer already in the row wins, with no callback
//   S-4304 onlyIfUnrated leaves the stored rating alone
//
// Every stored-data scenario runs on `MockWorkoutRepository` and on
// `HiveWorkoutRepository` (the harness in `test/helpers/repository_harness.dart`).

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/platform/watch_delivery.dart';
import 'package:omnitrain/core/platform/watch_transport.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/watch/watch_session_inbox.dart';
import 'package:omnitrain/state/watch/watch_sync_wiring.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/repository_harness.dart' show RepositoryHarness, harnessFactories;
import 'helpers/sync_protocol_harness.dart';
import 'helpers/watch_capture_import_harness.dart';

const String _sessionId = 's-w1';

/// The phone's clock, fixed so every stamp the inbox writes is predictable.
final DateTime _phoneNow = DateTime.utc(2026, 9, 25, 11);

/// The capture case's completed session without its rating: the row exists,
/// has no rating, and the wrist's answer arrives afterwards.
List<Map<String, Object?>> _eventsWithoutRating() => [
  for (final event in captureEvents('full'))
    if (event['kind'] != 'effort_rating') event,
];

/// The wrist's own effort rating for [_sessionId].
Map<String, Object?> _rating(int rating) => {
  'entryId': 'rating-s-w1',
  'eventId': 'rating-s-w1',
  'kind': 'effort_rating',
  'loggedAt': '2026-09-25T10:55:20.000Z',
  'rating': rating,
};

/// Delivers [events] one envelope each, the way the wrist sends them.
Future<void> _deliverEach(
  WatchSessionInbox inbox,
  List<Map<String, Object?>> events, {
  String tag = 'a',
}) async {
  for (var i = 0; i < events.length; i++) {
    await inbox.receive(
      observationsUp(_sessionId, [events[i]], messageId: 'msg-$tag-$i'),
    );
  }
}

WatchSessionInbox _inbox(
  WorkoutRepository repository, {
  Future<void> Function(String sessionId, int rating)? onSessionRated,
  bool Function(String sessionId)? phoneOwnsSession,
}) {
  var ids = 0;
  return WatchSessionInbox(
    repository: repository,
    transport: CaptureTransport(),
    validator: loadProtocolValidator(),
    clock: () => _phoneNow,
    idFactory: () => 'msg-phone-${++ids}',
    onFailure: Error.throwWithStackTrace,
    onSessionRated: onSessionRated,
    phoneOwnsSession: phoneOwnsSession,
  );
}

/// Runs [body] against one repository implementation, closing it afterwards.
Future<void> _onEachStore(
  Future<void> Function(RepositoryHarness harness, WorkoutRepository repository)
  body,
) async {
  for (final factory in harnessFactories) {
    final harness = factory();
    final repository = await harness.open();
    try {
      await seedCaptureCatalog(repository);
      await body(harness, repository);
    } finally {
      await harness.close();
    }
  }
}

/// The phone graph over a fake radio, the way `lib/main.dart` builds it.
class _Radio implements WatchTransport {
  final List<Map<String, Object?>> sent = [];
  WatchInboundHandler? _handler;

  @override
  bool get isPhoneReachable => true;

  @override
  void onIncoming(WatchInboundHandler handler) => _handler = handler;

  @override
  Future<void> refreshReachability() async {}

  @override
  Future<void> requestRoutines({DateTime? since}) async =>
      send(WatchTransportRequest.routinesFrame(since: since));

  @override
  Future<void> requestSnapshot() async =>
      send(WatchTransportRequest.snapshotFrame());

  @override
  Future<WatchDelivery> send(Map<String, Object?> envelope) async {
    sent.add(envelope);
    return WatchDelivery.delivered;
  }

  Future<void> fromWrist(Map<String, Object?> frame) async {
    final handler = _handler;
    if (handler == null) {
      throw StateError('the phone graph never bound its inbound handler');
    }
    await handler(frame);
  }
}

void main() {
  test('S-4301 the wrist answer settles once and the live session adopts it', () async {
    await _onEachStore((harness, repository) async {
      var calls = 0;
      int? rated;
      final state = WorkoutState(repository);
      final inbox = _inbox(
        repository,
        onSessionRated: (sessionId, rating) async {
          calls++;
          rated = rating;
          await state.adoptSessionFeeling(sessionId, rating);
        },
      );

      await _deliverEach(inbox, _eventsWithoutRating());
      expect(
        (await repository.getSession(_sessionId))!.sessionFeeling,
        isNull,
        reason: '${harness.name}: the session is imported before the answer',
      );
      await state.loadHistoricalSession(_sessionId);
      expect(
        state.currentSession!.sessionFeeling,
        isNull,
        reason: '${harness.name}: the live session has no rating yet',
      );

      await _deliverEach(inbox, [_rating(4)], tag: 'rating');

      expect(calls, 1, reason: '${harness.name}: the rating is reported once');
      expect(rated, 4, reason: '${harness.name}: the value is the wrist’s');
      expect(
        (await repository.getSession(_sessionId))!.sessionFeeling,
        4,
        reason: '${harness.name}: the row holds the wrist’s rating',
      );
      expect(
        state.currentSession!.sessionFeeling,
        4,
        reason: '${harness.name}: the live session adopts it without a reload',
      );
    });
  });

  test('S-4301 the shipping graph hands the imported rating to the bound '
      'session', () async {
    await _onEachStore((harness, repository) async {
      final settings = SettingsState(repository, fakePreferencesService());
      await settings.initialize();
      final radio = _Radio();
      final state = WorkoutState(repository);
      final graph = (await createWatchSync(
        repository: repository,
        nutritionState: NutritionState(repository),
        foodLibraryState: FoodLibraryState(repository),
        settingsState: settings,
        transport: radio,
        clock: () => _phoneNow,
        onFailure: (error, stack) => fail('${harness.name}: $error'),
      ))!;
      graph.adoption.bindWorkoutState(state);

      var ids = 0;
      for (final event in _eventsWithoutRating()) {
        await radio.fromWrist(
          observationsUp(
            _sessionId,
            [event],
            messageId: 'msg-import-${++ids}',
          ),
        );
      }
      await state.loadHistoricalSession(_sessionId);
      expect(
        state.currentSession!.sessionFeeling,
        isNull,
        reason: '${harness.name}: the live session has no rating yet',
      );

      await radio.fromWrist(
        observationsUp(
          _sessionId,
          [_rating(4)],
          messageId: 'msg-rating-${++ids}',
        ),
      );

      expect(
        (await repository.getSession(_sessionId))!.sessionFeeling,
        4,
        reason: '${harness.name}: the wiring’s inbox writes the wrist’s rating',
      );
      expect(
        state.currentSession!.sessionFeeling,
        4,
        reason: '${harness.name}: the graph adopts it on the bound state (D-1)',
      );
    });
  });

  test('S-4301 a wrist answer that reaches a session the phone still holds '
      'is adopted too', () async {
    await _onEachStore((harness, repository) async {
      var calls = 0;
      int? rated;

      // The ordinary import creates the row the phone holds, with no rating.
      final importer = _inbox(repository);
      await _deliverEach(importer, _eventsWithoutRating());
      expect(
        (await repository.getSession(_sessionId))!.sessionFeeling,
        isNull,
        reason: '${harness.name}: the held session has no rating yet',
      );

      // The wrist's answer arrives while the phone owns the session, so the
      // importer merges it rather than importing it.
      final inbox = _inbox(
        repository,
        phoneOwnsSession: (_) => true,
        onSessionRated: (sessionId, rating) async {
          calls++;
          rated = rating;
        },
      );
      await _deliverEach(inbox, [_rating(4)], tag: 'rating');

      expect(calls, 1, reason: '${harness.name}: the merge reports the rating once');
      expect(rated, 4, reason: '${harness.name}: the value is the wrist’s');
      expect(
        (await repository.getSession(_sessionId))!.sessionFeeling,
        4,
        reason: '${harness.name}: the held row takes the wrist’s rating (D-19)',
      );
    });
  });

  test('S-4302 the phone’s answer already in the row wins, with no callback', () async {
    await _onEachStore((harness, repository) async {
      var calls = 0;
      final inbox = _inbox(
        repository,
        onSessionRated: (sessionId, rating) async => calls++,
      );

      await _deliverEach(inbox, _eventsWithoutRating());
      await repository.updateSessionFeeling(_sessionId, 2);

      await _deliverEach(inbox, [_rating(5)], tag: 'wrist');

      expect(
        calls,
        0,
        reason: '${harness.name}: a wrist rating nothing wrote reports nothing',
      );
      expect(
        (await repository.getSession(_sessionId))!.sessionFeeling,
        2,
        reason: '${harness.name}: the phone’s rating stands (D-138)',
      );
    });
  });

  test('S-4304 onlyIfUnrated leaves the stored rating alone, the default '
      'still writes', () async {
    await _onEachStore((harness, repository) async {
      final state = WorkoutState(repository);
      final inbox = _inbox(repository);

      await _deliverEach(inbox, _eventsWithoutRating());
      await state.loadHistoricalSession(_sessionId);
      await repository.updateSessionFeeling(_sessionId, 4);
      expect(
        state.currentSession!.sessionFeeling,
        isNull,
        reason: '${harness.name}: the import wrote the row, not the state',
      );

      await state.updateSessionFeeling(
        _sessionId,
        2,
        onlyIfUnrated: true,
      );

      expect(
        (await repository.getSession(_sessionId))!.sessionFeeling,
        4,
        reason: '${harness.name}: the late automatic answer writes nothing',
      );
      expect(
        state.currentSession!.sessionFeeling,
        isNull,
        reason: '${harness.name}: and the live session is untouched',
      );

      await state.updateSessionFeeling(_sessionId, 2);

      expect(
        (await repository.getSession(_sessionId))!.sessionFeeling,
        2,
        reason: '${harness.name}: an explicit edit still writes (default)',
      );
      expect(
        state.currentSession!.sessionFeeling,
        2,
        reason: '${harness.name}: and reaches the live session',
      );
    });
  });
}
