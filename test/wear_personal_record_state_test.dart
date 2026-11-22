// The "New PR" verdict on a log, as state (plan 289, D-28901).
//
// Scenario mapping:
//   S-28901  a set that beats the frame stamps a 4 s banner window
//   S-28902  a set that does not beat it shows nothing
//   S-28903  no bests owner: nothing
//   S-28904  an owner holding no frame: nothing
//   S-28905  a timed effort is not a claim
//   S-28906  a second record restarts the window
//   S-28907  a later non-record clears the flag, not the window
//   S-28908  a log whose write fails gives no verdict
//   S-28909  a set the engine takes without a log() never reaches the judge
//
// Plain `test()` throughout: the state layer, the in-memory store. A fixed clock
// the test advances; nothing reads the real time.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/watch/logging/watch_logging_state.dart';
import 'package:omnitrain/watch/logging/watch_metric_stepping.dart';
import 'package:omnitrain/watch/logging/watch_personal_bests.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';

class _Clock {
  DateTime now = DateTime.utc(2026, 11, 22, 9);

  DateTime call() => now;

  void advance(Duration delta) => now = now.add(delta);
}

/// A store whose observation writes can be made to fail, as a full disk would.
class _FlakyStore extends InMemoryWatchSessionStore {
  bool failObservations = false;

  @override
  Future<T> append<T extends WatchRecord>(T record) async {
    if (failObservations && record is WatchObservationRecord) {
      throw StateError('disk full');
    }
    return super.append(record);
  }
}

Map<String, Object?> _frame(List<Map<String, Object?>> bests) => {
  'protocolVersion': 1,
  'messageId': 'msg-pr',
  'type': 'bests_down',
  'origin': 'phone',
  'sentAt': '2026-11-22T08:00:00Z',
  'payload': {'generatedAt': '2026-11-22T08:00:00Z', 'bests': bests},
};

/// A frame any set beats on both axes (a one-kilogram best, no reps best).
final Map<String, Object?> _lowFrame = _frame([
  {'exerciseId': 'ex-x', 'e1rmKg': 1},
]);

/// A frame no set beats on either axis.
final Map<String, Object?> _highFrame = _frame([
  {'exerciseId': 'ex-x', 'e1rmKg': 1000000, 'repsBest': 1000000},
]);

class _Rig {
  _Rig._(this.store, this.engine, this.clock, this.bests, this.surface);

  final _FlakyStore store;
  final WatchSessionEngine engine;
  final _Clock clock;
  final WatchPersonalBests bests;
  final WatchLoggingState surface;

  static Future<_Rig> start({
    List<String> capabilities = const ['reps', 'sets', 'load'],
    bool giveOwner = true,
    Map<String, Object?>? frame,
  }) async {
    final clock = _Clock();
    final store = _FlakyStore();
    final engine = WatchSessionEngine(store, clock: clock.call);
    await engine.createSession(
      modality: 'resistance_lifting',
      exercises: [
        {
          'sessionExerciseId': 'sx-x',
          'exerciseId': 'ex-x',
          'name': 'Exercise X',
          'capabilities': capabilities,
        },
      ],
    );
    final bests = WatchPersonalBests(store: store);
    if (frame != null) await bests.applyBestsDown(frame);
    var ids = 0;
    final surface = WatchLoggingState(
      engine: engine,
      clock: clock.call,
      idFactory: () => 'entry-${ids++}',
      bests: giveOwner ? bests : null,
    );
    return _Rig._(store, engine, clock, bests, surface);
  }
}

void main() {
  test(
    'S-28901 a set that beats the frame stamps a four-second window',
    () async {
      final rig = await _Rig.start(frame: _lowFrame);
      final loggedAt = rig.clock.now;
      expect(
        rig.surface.isPersonalRecordBannerVisible(loggedAt),
        isFalse,
        reason: 'the premise: nothing before the log',
      );

      await rig.surface.log();

      expect(rig.surface.lastLogWasPersonalRecord, isTrue);
      expect(
        rig.surface.personalRecordBannerUntil,
        loggedAt.add(const Duration(seconds: 4)),
      );
      expect(
        rig.surface.isPersonalRecordBannerVisible(
          loggedAt.add(const Duration(milliseconds: 3999)),
        ),
        isTrue,
      );
      expect(
        rig.surface.isPersonalRecordBannerVisible(
          loggedAt.add(const Duration(seconds: 4)),
        ),
        isFalse,
        reason: 'gone exactly at the end of the window',
      );
    },
  );

  test('S-28902 a set that does not beat the frame shows nothing', () async {
    final rig = await _Rig.start(frame: _highFrame);

    await rig.surface.log();

    expect(rig.surface.lastLogWasPersonalRecord, isFalse);
    expect(rig.surface.personalRecordBannerUntil, isNull);
    expect(rig.surface.isPersonalRecordBannerVisible(rig.clock.now), isFalse);
  });

  test('S-28903 with no bests owner nothing is a record', () async {
    final rig = await _Rig.start(giveOwner: false, frame: _lowFrame);

    await rig.surface.log();

    expect(rig.surface.lastLogWasPersonalRecord, isFalse);
    expect(rig.surface.personalRecordBannerUntil, isNull);
  });

  test('S-28904 an owner holding no frame says nothing', () async {
    final rig = await _Rig.start();
    expect(rig.bests.hasFrame, isFalse, reason: 'the premise');

    await rig.surface.log();

    expect(rig.surface.lastLogWasPersonalRecord, isFalse);
    expect(rig.surface.personalRecordBannerUntil, isNull);
  });

  test('S-28905 a timed effort is not a claim', () async {
    final rig = await _Rig.start(
      capabilities: const ['time', 'distance'],
      frame: _frame(const []),
    );
    expect(rig.surface.effortKind, 'timed', reason: 'the premise');
    rig.surface.adjust(WatchMetricKey.duration, 60);
    rig.clock.advance(const Duration(minutes: 6));

    await rig.surface.log();

    expect(rig.surface.lastLogWasPersonalRecord, isFalse);
    expect(rig.surface.personalRecordBannerUntil, isNull);
  });

  test('S-28906 a second record restarts the window', () async {
    final rig = await _Rig.start(frame: _lowFrame);
    await rig.surface.log();
    rig.clock.advance(const Duration(seconds: 2));
    rig.surface.adjust(WatchMetricKey.reps, 1);
    final secondAt = rig.clock.now;

    await rig.surface.log();

    expect(rig.surface.lastLogWasPersonalRecord, isTrue);
    expect(
      rig.surface.personalRecordBannerUntil,
      secondAt.add(const Duration(seconds: 4)),
    );
    expect(
      rig.surface.isPersonalRecordBannerVisible(
        secondAt.add(const Duration(milliseconds: 3999)),
      ),
      isTrue,
      reason: 'five seconds after the first record, still inside the second',
    );
  });

  test('S-28907 a later non-record clears the flag, not the window', () async {
    final rig = await _Rig.start(frame: _lowFrame);
    await rig.surface.log();
    final until = rig.surface.personalRecordBannerUntil;
    rig.clock.advance(const Duration(seconds: 1));

    await rig.surface.log();

    expect(
      rig.surface.lastLogWasPersonalRecord,
      isFalse,
      reason: 'an equal set is not a record: it matches the first',
    );
    expect(
      rig.surface.personalRecordBannerUntil,
      until,
      reason: 'the first record keeps its own window',
    );
  });

  test('S-28908 a log whose write fails gives no verdict', () async {
    final rig = await _Rig.start(frame: _lowFrame);
    rig.store.failObservations = true;

    await expectLater(rig.surface.log(), throwsStateError);

    expect(rig.surface.lastLogWasPersonalRecord, isFalse);
    expect(rig.surface.personalRecordBannerUntil, isNull);

    rig.store.failObservations = false;
    await rig.surface.log();
    expect(
      rig.surface.lastLogWasPersonalRecord,
      isTrue,
      reason: 'the failed set was never folded into the own best',
    );
  });

  test(
    'S-28909 a set the engine takes without a log() never reaches the judge',
    () async {
      final rig = await _Rig.start(frame: _lowFrame);

      await rig.engine.appendObservation({
        'entryId': 'phone-1',
        'eventId': 'phone-1',
        'kind': WatchObservationKind.set,
        'loggedAt': '2026-11-22T09:00:00Z',
        'sessionExerciseId': 'sx-x',
        'exerciseId': 'ex-x',
        'reps': 8,
        'loadKg': 100,
      });

      expect(rig.surface.lastLogWasPersonalRecord, isFalse);
      expect(rig.surface.personalRecordBannerUntil, isNull);
      await rig.surface.log();
      expect(
        rig.surface.lastLogWasPersonalRecord,
        isTrue,
        reason:
            'the phone-logged set was not folded: the wrist set is a record',
      );
    },
  );

  test(
    'S-28915 a loaded set is judged on the weight axis, an unloaded one on reps',
    () async {
      // Weight beats the one-kilogram best but nothing beats the reps best.
      final frame = _frame([
        {'exerciseId': 'ex-x', 'e1rmKg': 1, 'repsBest': 1000000},
      ]);
      final unloaded = await _Rig.start(frame: frame);
      await unloaded.surface.log();
      expect(
        unloaded.surface.lastLogWasPersonalRecord,
        isFalse,
        reason: 'no load dialled: the reps axis decides, and nothing beats it',
      );

      final loaded = await _Rig.start(frame: frame);
      loaded.surface.adjust(WatchMetricKey.weight, 20);
      await loaded.surface.log();
      expect(
        loaded.surface.lastLogWasPersonalRecord,
        isTrue,
        reason: 'the dialled load reaches the judge and beats 1 kg',
      );
    },
  );
}
