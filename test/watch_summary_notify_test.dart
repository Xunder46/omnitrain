// The wrist's heart-rate summary reaching the screens that show it (plan 72):
// the inbox tells a settled session's summary once, the state publishes the
// session and a count, and the wiring forwards the first to the second.
//
// Scenario mapping (plan 72):
//   S-10201 the inbox callback fires for a pass that stored a summary, and for
//           no other
//   S-10202 `noteWristSummary` publishes the session and counts, without
//           notifying the whole state
//   S-10203 the wiring bridge forwards to the bound state
//   S-10207 the session summary screen listens and re-reads only the heart
//           rate (source guard)
//
// Plain `test()`: no widget is involved, and a Hive write inside a widget
// test's fake-async zone never drains.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/platform/watch_delivery.dart';
import 'package:omnitrain/core/platform/watch_transport.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/watch/watch_session_inbox.dart';
import 'package:omnitrain/state/watch/watch_sync_wiring.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/repository_harness.dart';
import 'helpers/sync_protocol_harness.dart';
import 'helpers/watch_capture_import_harness.dart'
    show CaptureTransport, observationsUp;

/// Heart-rate values unlike any fixture default (plan 72).
const double _avg = 133;
const double _max = 171;

/// The session the scenarios run on, unlike the fixtures' `phone-s1`.
const String _sessionId = 'phone-s2';

final DateTime _phoneNow = DateTime.utc(2026, 9, 25, 11);

String _iso(int ms) =>
    DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();

/// One wrist `session_end` for a followed session, as an `observations_up`
/// event — the shape the inbox stages from.
Map<String, Object?> _endEvent({
  String status = 'completed',
  double? avg = _avg,
  double? max = _max,
  bool followed = true,
}) => {
  'entryId': 'end-$_sessionId',
  'eventId': 'end-$_sessionId',
  'kind': WatchInboxEntry.kindSessionEnd,
  'loggedAt': _iso(fixtureStart + 3600000),
  'startedAt': _iso(fixtureStart),
  'endedAt': _iso(fixtureStart + 3600000),
  'status': status,
  if (followed) 'followed': true,
  'avgHeartRateBpm': ?avg,
  'maxHeartRateBpm': ?max,
};

/// One wrist set row, the arm that must not fire the callback.
Map<String, Object?> _setEvent() => {
  'entryId': 'set-a',
  'eventId': 'set-a',
  'kind': WatchInboxEntry.kindSet,
  'loggedAt': _iso(fixtureStart + 60000),
  'sessionExerciseId': 'a',
  'exerciseId': 'ex-row',
  'reps': 9,
};

/// The phone's session `phone-s2`: one segment, two set efforts, so the
/// followed branch has history to sit beside.
Future<void> _seedPhoneSession(WorkoutRepository repo) async {
  await seedSession(repo, sessionId: _sessionId);
  await seedExercise(repo, id: 'ex-row', name: 'Row', capabilities: ['load']);
}

/// An inbox wired the way the existing inbox tests wire one, with a recording
/// `onSensorSummaryAttached`.
WatchSessionInbox _inbox(
  WorkoutRepository repository,
  CaptureTransport transport,
  List<String> summaries,
) => WatchSessionInbox(
  repository: repository,
  transport: transport,
  validator: loadProtocolValidator(),
  clock: () => _phoneNow,
  idFactory: () => 'msg-phone',
  onSensorSummaryAttached: (sessionId) async => summaries.add(sessionId),
  // A failure inside the inbox fails the test where it happened.
  onFailure: Error.throwWithStackTrace,
);

/// The phone's radio: hands the phone one frame from the wrist the way the
/// platform channel does (copied from the adoption build-notify test).
class _PhoneRadio implements WatchTransport {
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
  Future<WatchDelivery> send(Map<String, Object?> envelope) async =>
      WatchDelivery.delivered;

  Future<void> fromWrist(Map<String, Object?> frame) async {
    final handler = _handler;
    if (handler == null) {
      throw StateError('the phone graph never bound its inbound handler');
    }
    await handler(frame);
  }
}

void main() {
  // ── S-10201 ────────────────────────────────────────────────────────────────
  for (final harnessFactory in harnessFactories) {
    final harness = harnessFactory();
    group('inbox sensor-summary callback (${harness.name})', () {
      late WorkoutRepository repo;
      late CaptureTransport transport;
      late List<String> summaries;

      setUp(() async {
        repo = await harness.open();
        transport = CaptureTransport();
        summaries = [];
      });

      tearDown(harness.close);

      test('S-10201 a followed completed end fires once with the session id',
          () async {
        await _seedPhoneSession(repo);
        final inbox = _inbox(repo, transport, summaries);

        await inbox.receive(
          observationsUp(_sessionId, [_endEvent()], messageId: 'msg-1'),
        );

        expect(summaries, [_sessionId], reason: 'S-10201 once, with the id');
      });

      test('S-10201 an end with no heart rate does not fire', () async {
        await _seedPhoneSession(repo);
        final inbox = _inbox(repo, transport, summaries);

        await inbox.receive(
          observationsUp(
            _sessionId,
            [_endEvent(avg: null, max: null)],
            messageId: 'msg-1',
          ),
        );

        expect(summaries, isEmpty, reason: 'S-10201 no summary, no call');
      });

      test('S-10201 the same end settled again does not fire a second time',
          () async {
        await _seedPhoneSession(repo);
        final inbox = _inbox(repo, transport, summaries);
        await inbox.receive(
          observationsUp(_sessionId, [_endEvent()], messageId: 'msg-1'),
        );
        expect(summaries, [_sessionId]);

        await inbox.receive(
          observationsUp(_sessionId, [_endEvent()], messageId: 'msg-2'),
        );

        expect(
          summaries,
          [_sessionId],
          reason: 'S-10201 the second pass attached nothing',
        );
      });

      test('S-10201 a set row only does not fire', () async {
        await _seedPhoneSession(repo);
        final inbox = _inbox(repo, transport, summaries);

        await inbox.receive(
          observationsUp(_sessionId, [_setEvent()], messageId: 'msg-1'),
        );

        expect(summaries, isEmpty, reason: 'S-10201 rows alone tell nobody');
      });
    });
  }

  // ── S-10202 ────────────────────────────────────────────────────────────────
  test('S-10202 noteWristSummary publishes the session and counts, and does '
      'not notify the state', () async {
    final repo = MockWorkoutRepository();
    await repo.initialize();
    final state = WorkoutState(repo);
    var notifications = 0;
    state.addListener(() => notifications++);

    state.noteWristSummary('a');
    expect(
      state.wristSummary.value,
      (sessionId: 'a', count: 1),
      reason: 'S-10202 the first arrival',
    );
    state.noteWristSummary('a');
    expect(
      state.wristSummary.value,
      (sessionId: 'a', count: 2),
      reason: 'S-10202 a second arrival for the same session is a new value',
    );
    state.noteWristSummary('b');
    expect(
      state.wristSummary.value,
      (sessionId: 'b', count: 3),
      reason: 'S-10202 the count carries across sessions',
    );
    expect(
      notifications,
      0,
      reason: 'S-10202 the whole state is not notified',
    );
  });

  // ── S-10203 ────────────────────────────────────────────────────────────────
  test('S-10203 the wiring bridge forwards a settled summary to the bound '
      'state', () async {
    final repo = MockWorkoutRepository();
    await repo.initialize();
    await _seedPhoneSession(repo);
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsState(repo, fakePreferencesService());
    await settings.initialize();
    final radio = _PhoneRadio();
    final graph = (await createWatchSync(
      repository: repo,
      nutritionState: NutritionState(repo),
      foodLibraryState: FoodLibraryState(repo),
      settingsState: settings,
      transport: radio,
      clock: () => _phoneNow,
    ))!;
    final state = WorkoutState(repo);
    graph.adoption.bindWorkoutState(state);

    await radio.fromWrist(
      observationsUp(_sessionId, [_endEvent()], messageId: 'msg-w'),
    );

    expect(
      state.wristSummary.value?.sessionId,
      _sessionId,
      reason: 'S-10203 the bound state heard the summary',
    );
  });

  // ── S-10207 ────────────────────────────────────────────────────────────────
  test('S-10207 the summary screen listens for the wrist summary and re-reads '
      'only the heart rate', () {
    final source = File(
      'lib/features/session/session_summary_screen.dart',
    ).readAsStringSync();
    // Comment-stripped, so a mention in a doc comment cannot satisfy the guard.
    final stripped = source.replaceAll(RegExp(r'//.*'), '');

    expect(
      stripped,
      contains(
        'widget.workoutState.wristSummary.addListener(_reloadHeartRateOnWristSummary);',
      ),
      reason: 'S-10207 the screen listens',
    );
    expect(
      stripped,
      contains(
        'widget.workoutState.wristSummary.removeListener(_reloadHeartRateOnWristSummary);',
      ),
      reason: 'S-10207 the listener is removed',
    );

    const signature = 'Future<void> _reloadHeartRateOnWristSummary()';
    final start = stripped.indexOf(signature);
    expect(start, greaterThanOrEqualTo(0), reason: 'S-10207 the handler exists');
    final next = stripped.indexOf('  Future<void> ', start + signature.length);
    expect(next, greaterThan(start), reason: 'S-10207 the handler ends');
    final body = stripped.substring(start, next);
    expect(
      body,
      contains('getSessionHeartRate('),
      reason: 'S-10207 the handler re-reads the heart rate',
    );
    expect(
      body,
      isNot(contains('_loadAsyncData(')),
      reason: 'S-10207 nothing else on the screen reloads',
    );
  });
}
