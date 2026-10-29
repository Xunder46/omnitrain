// Plan 90: the session's effort rating also goes into Apple Fitness as the
// workout's "Workout Effort".
//
// Plan: `docs/plans/2026-10-28-90-fitness-effort-from-rating-plan/`, Phase 1
// (D-1 to D-5, D-7). Scenario mapping:
//   S-90-1 the 1-5 to 1-10 mapping                 → `S-90-1 ...`
//   S-90-2 the sync service's gates                → `S-90-2 ...`
//   S-90-3 a rating change writes again            → `S-90-3 ...`
//   S-90-4 outcomes and the retry schedule         → `S-90-4 ...`
//   S-90-5 the two hooks (phone rating, wrist)     → `S-90-5 ...`
//   S-90-6 delete clears the effort first          → `S-90-6 ...`
//   S-90-7 the contract's no-op answers + channel  → `S-90-7 ...`
// The private fakes of `test/health_platform_test.dart` and
// `test/watch_session_import_test.dart` carry their own S-90-7 test.
//
// Every test is a plain `test()`: the retry waits are a fake delay the test
// releases by hand, so no real time passes anywhere.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/modality.dart';
import 'package:omnitrain/core/services/health_effort_mapper.dart';
import 'package:omnitrain/core/services/health_platform_service.dart';
import 'package:omnitrain/core/services/health_sync_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/watch/watch_session_inbox.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/sync_protocol_harness.dart' show loadProtocolValidator;
import 'helpers/watch_capture_import_harness.dart';

/// One call the sync service made of the platform.
class _EffortCall {
  _EffortCall(this.kind, this.start, this.end, this.score, this.at);

  /// `set`, `clear` or `delete`.
  final String kind;
  final DateTime start;
  final DateTime end;
  final int? score;

  /// How much fake time had passed when the call was made.
  final Duration at;
}

/// A fake delay: every wait is recorded and held until the test releases it,
/// and releasing it advances a fake clock by the wait's length.
class _FakeDelay {
  Duration elapsed = Duration.zero;
  final List<Duration> requested = [];
  final List<Completer<void>> _pending = [];

  int get pendingCount => _pending.length;

  Future<void> call(Duration wait) {
    requested.add(wait);
    final gate = Completer<void>();
    _pending.add(gate);
    return gate.future.then((_) => elapsed += wait);
  }

  /// Releases the oldest wait and lets everything it unblocks run.
  Future<void> releaseNext() async {
    _pending.removeAt(0).complete();
    await pumpEventQueue();
  }
}

/// Records every effort and delete call; answers the queued outcomes in
/// order, then [fallback].
class _EffortPlatform implements HealthPlatformService {
  _EffortPlatform(this.delay);

  final _FakeDelay delay;
  final List<_EffortCall> calls = [];
  final List<HealthEffortOutcome> outcomes = [];
  HealthEffortOutcome fallback = HealthEffortOutcome.written;
  bool throwOnSet = false;

  List<_EffortCall> get sets => [
    for (final c in calls)
      if (c.kind == 'set') c,
  ];

  @override
  Future<HealthEffortOutcome> setWorkoutEffort(
    DateTime start,
    DateTime end,
    int score,
  ) async {
    calls.add(_EffortCall('set', start, end, score, delay.elapsed));
    if (throwOnSet) throw Exception('platform effort exploded');
    return outcomes.isEmpty ? fallback : outcomes.removeAt(0);
  }

  @override
  Future<bool> clearWorkoutEffort(DateTime start, DateTime end) async {
    calls.add(_EffortCall('clear', start, end, null, delay.elapsed));
    return true;
  }

  @override
  Future<bool> deleteWorkouts(DateTime start, DateTime end) async {
    calls.add(_EffortCall('delete', start, end, null, delay.elapsed));
    return true;
  }

  @override
  Future<bool> requestWritePermission() async => true;

  @override
  Future<bool> requestReadPermission() async => true;

  @override
  Future<bool> writeWorkout(HealthWorkoutDraft workout) async => true;

  @override
  Future<List<HealthWeightSample>> readBodyWeightSince(DateTime since) async =>
      const [];
}

/// A sync service that only records which sessions it was told were rated:
/// the hook tests watch the call itself, not what the service then does.
class _RatedSpy extends HealthSyncService {
  _RatedSpy(MockWorkoutRepository repository)
    : super(
        platform: const UnavailableHealthPlatformService(),
        repository: repository,
        isWriteEnabled: () => true,
        isReadEnabled: () => false,
      );

  final List<TrainingSession> rated = [];

  @override
  Future<void> onSessionRated(TrainingSession session) async {
    rated.add(session);
  }
}

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

final DateTime _day = DateTime(2026, 10, 28);
int _at(int hour, int minute) =>
    _day.add(Duration(hours: hour, minutes: minute)).millisecondsSinceEpoch;

TrainingSession _session(
  String id, {
  int? feeling,
  bool ended = true,
  int startMs = 0,
  int endMs = 0,
}) {
  final start = startMs == 0 ? _at(9, 0) : startMs;
  final end = endMs == 0 ? _at(10, 0) : endMs;
  return TrainingSession(
    id: id,
    ownerUserId: 'user-1',
    startedAtMs: start,
    endedAtMs: ended ? end : null,
    modality: Modality.resistanceLifting,
    sessionFeeling: feeling,
    createdAtMs: start,
    updatedAtMs: end,
  );
}

/// The real sync service over the recording platform and the fake delay.
class _Rig {
  _Rig._(this.repo, this.platform, this.delay, this.sync);

  final MockWorkoutRepository repo;
  final _EffortPlatform platform;
  final _FakeDelay delay;
  final HealthSyncService sync;
  bool writeEnabled = true;

  static Future<_Rig> create() async {
    final repo = await _freshRepo();
    final delay = _FakeDelay();
    final platform = _EffortPlatform(delay);
    late final _Rig rig;
    final sync = HealthSyncService(
      platform: platform,
      repository: repo,
      isWriteEnabled: () => rig.writeEnabled,
      isReadEnabled: () => false,
      effortRetryDelay: delay.call,
    );
    rig = _Rig._(repo, platform, delay, sync);
    return rig;
  }

  /// Starts a rating write without waiting for its retries.
  Future<void> rate(TrainingSession session) async {
    unawaited(sync.onSessionRated(session));
    await pumpEventQueue();
  }
}

void main() {
  group('S-90-1 the rating maps to Apple\'s Workout Effort', () {
    test('S-90-1 1, 2, 3, 4, 5 give 2, 4, 6, 8, 10', () {
      expect(
        [for (var r = 1; r <= 5; r++) ratingToAppleEffort(r)],
        [2, 4, 6, 8, 10],
      );
    });

    test('S-90-1 0, 6 and negatives give null', () {
      expect(ratingToAppleEffort(0), isNull);
      expect(ratingToAppleEffort(6), isNull);
      expect(ratingToAppleEffort(-1), isNull);
      expect(ratingToAppleEffort(-5), isNull);
    });
  });

  group('S-90-2 the sync service writes a rated, finished session', () {
    test('S-90-2 toggle on: one setWorkoutEffort with the exact span and the '
        'mapped score', () async {
      final rig = await _Rig.create();
      final session = _session('s-1', feeling: 4);
      await rig.rate(session);

      expect(rig.platform.sets, hasLength(1));
      final call = rig.platform.sets.single;
      expect(call.start, DateTime.fromMillisecondsSinceEpoch(_at(9, 0)));
      expect(call.end, DateTime.fromMillisecondsSinceEpoch(_at(10, 0)));
      expect(call.score, 8);
    });

    test('S-90-2 toggle off: no call', () async {
      final rig = await _Rig.create();
      rig.writeEnabled = false;
      await rig.rate(_session('s-1', feeling: 4));
      expect(rig.platform.calls, isEmpty);
    });

    test('S-90-2 a session without a rating: no call', () async {
      final rig = await _Rig.create();
      await rig.rate(_session('s-1'));
      expect(rig.platform.calls, isEmpty);
    });

    test('S-90-2 a session without an end: no call', () async {
      final rig = await _Rig.create();
      await rig.rate(_session('s-1', feeling: 4, ended: false));
      expect(rig.platform.calls, isEmpty);
    });
  });

  group('S-90-3 a rating change', () {
    test('S-90-3 a second rating calls again with the new score', () async {
      final rig = await _Rig.create();
      await rig.rate(_session('s-1', feeling: 4));
      await rig.rate(_session('s-1', feeling: 2));
      expect([for (final c in rig.platform.sets) c.score], [8, 4]);
    });

    test('S-90-3 the same rating twice is safe', () async {
      final rig = await _Rig.create();
      await rig.rate(_session('s-1', feeling: 3));
      await rig.rate(_session('s-1', feeling: 3));
      expect([for (final c in rig.platform.sets) c.score], [6, 6]);
      expect(rig.delay.pendingCount, 0);
    });
  });

  group('S-90-4 outcomes and retries', () {
    for (final outcome in const [
      HealthEffortOutcome.leftAlone,
      HealthEffortOutcome.unavailable,
    ]) {
      test('S-90-4 ${outcome.name} stops silently with no retry', () async {
        final rig = await _Rig.create();
        rig.platform.fallback = outcome;
        await rig.rate(_session('s-1', feeling: 5));
        expect(rig.platform.sets, hasLength(1));
        expect(rig.delay.requested, isEmpty);
      });
    }

    test('S-90-4 a platform error stops silently with no retry', () async {
      final rig = await _Rig.create();
      rig.platform.throwOnSet = true;
      await expectLater(
        rig.sync.onSessionRated(_session('s-1', feeling: 5)),
        completes,
      );
      expect(rig.platform.sets, hasLength(1));
      expect(rig.delay.requested, isEmpty);
    });

    test('S-90-4 noWorkout retries at 20 s, 90 s and 5 min and stops after '
        'the last', () async {
      final rig = await _Rig.create();
      rig.platform.fallback = HealthEffortOutcome.noWorkout;
      final done = rig.sync.onSessionRated(_session('s-1', feeling: 2));
      await pumpEventQueue();

      for (var i = 0; i < 3; i++) {
        expect(rig.delay.pendingCount, 1, reason: 'retry ${i + 1} is waiting');
        await rig.delay.releaseNext();
      }
      await done;

      expect(
        [for (final c in rig.platform.sets) c.at],
        const [
          Duration.zero,
          Duration(seconds: 20),
          Duration(seconds: 90),
          Duration(minutes: 5),
        ],
      );
      expect([for (final c in rig.platform.sets) c.score], [4, 4, 4, 4]);
      expect(rig.delay.pendingCount, 0, reason: 'no fourth retry');
    });

    test('S-90-4 a retry that finds the workout stops the schedule', () async {
      final rig = await _Rig.create();
      rig.platform.outcomes.addAll(const [
        HealthEffortOutcome.noWorkout,
        HealthEffortOutcome.written,
      ]);
      rig.platform.fallback = HealthEffortOutcome.noWorkout;
      final done = rig.sync.onSessionRated(_session('s-1', feeling: 2));
      await pumpEventQueue();
      await rig.delay.releaseNext();
      await done;

      expect(rig.platform.sets, hasLength(2));
      expect(rig.platform.sets.last.at, const Duration(seconds: 20));
      expect(rig.delay.pendingCount, 0);
      expect(rig.delay.requested, hasLength(1));
    });

    test('S-90-4 a newer rating cancels the pending retries for that '
        'session', () async {
      final rig = await _Rig.create();
      rig.platform.outcomes.add(HealthEffortOutcome.noWorkout);
      await rig.rate(_session('s-1', feeling: 3));
      expect(rig.delay.pendingCount, 1);

      // The newer rating finds the workout at once.
      await rig.rate(_session('s-1', feeling: 5));
      expect([for (final c in rig.platform.sets) c.score], [6, 10]);

      // The old rating's retry wakes and must not write its stale score.
      rig.platform.fallback = HealthEffortOutcome.noWorkout;
      await rig.delay.releaseNext();
      expect([for (final c in rig.platform.sets) c.score], [6, 10]);
      expect(rig.delay.pendingCount, 0);
    });

    test('S-90-4 a retry for one session leaves another session\'s write '
        'alone', () async {
      final rig = await _Rig.create();
      rig.platform.outcomes.add(HealthEffortOutcome.noWorkout);
      await rig.rate(_session('s-1', feeling: 3));
      await rig.rate(
        _session('s-2', feeling: 1, startMs: _at(11, 0), endMs: _at(12, 0)),
      );
      rig.platform.fallback = HealthEffortOutcome.written;
      await rig.delay.releaseNext();
      expect([for (final c in rig.platform.sets) c.score], [6, 2, 6]);
    });

    test('S-90-4 switching Write workouts off stops a pending retry', () async {
      final rig = await _Rig.create();
      rig.platform.fallback = HealthEffortOutcome.noWorkout;
      await rig.rate(_session('s-1', feeling: 3));
      rig.writeEnabled = false;
      await rig.delay.releaseNext();
      expect(rig.platform.sets, hasLength(1));
      expect(rig.delay.pendingCount, 0);
    });
  });

  group('S-90-5 the hooks', () {
    test('S-90-5 rating an ended, loaded session tells the sync service '
        'once', () async {
      final repo = await _freshRepo();
      final spy = _RatedSpy(repo);
      final state = WorkoutState(repo, healthSync: spy);
      await repo.createSession(_session('s-1'));
      await state.loadHistoricalSession('s-1');

      await state.updateSessionFeeling('s-1', 4);

      expect(spy.rated, hasLength(1));
      expect(spy.rated.single.id, 's-1');
      expect(spy.rated.single.sessionFeeling, 4);
      expect(spy.rated.single.endedAtMs, _at(10, 0));
    });

    test('S-90-5 rating an ended session that is not the loaded one (the '
        'calendar edit) tells the sync service once', () async {
      final repo = await _freshRepo();
      final spy = _RatedSpy(repo);
      final state = WorkoutState(repo, healthSync: spy);
      await repo.createSession(_session('s-1'));

      await state.updateSessionFeeling('s-1', 2);

      expect(spy.rated, hasLength(1));
      expect(spy.rated.single.id, 's-1');
      expect(spy.rated.single.sessionFeeling, 2);
    });

    test('S-90-5 rating a still-running session does not', () async {
      final repo = await _freshRepo();
      final spy = _RatedSpy(repo);
      final state = WorkoutState(repo, healthSync: spy);
      await state.createNewSession(modality: Modality.resistanceLifting);
      final running = state.currentSession!;
      expect(running.endedAtMs, isNull);

      await state.updateSessionFeeling(running.id, 3);

      expect(state.currentSession?.sessionFeeling, 3);
      expect(spy.rated, isEmpty);
    });

    test(
      'S-90-5 an only-if-unrated rating that does not land does not',
      () async {
        final repo = await _freshRepo();
        final spy = _RatedSpy(repo);
        final state = WorkoutState(repo, healthSync: spy);
        await repo.createSession(_session('s-1', feeling: 5));

        await state.updateSessionFeeling('s-1', 2, onlyIfUnrated: true);

        expect(spy.rated, isEmpty);
      },
    );

    group('the wrist import', () {
      const sid = 's-wrist-90';

      Map<String, Object?> setEvent() => {
        'entryId': 'e-1',
        'eventId': 'e-1',
        'kind': 'set',
        'loggedAt': '2026-09-25T09:05:00.000Z',
        'sessionExerciseId': 'sx-bench',
        'exerciseId': 'ex-bench',
        'reps': 5,
        'loadKg': 80,
      };
      Map<String, Object?> endEvent() => {
        'entryId': 'end-$sid',
        'eventId': 'end-$sid',
        'kind': 'session_end',
        'loggedAt': '2026-09-25T09:30:00.000Z',
        'startedAt': '2026-09-25T09:00:00.000Z',
        'endedAt': '2026-09-25T09:30:00.000Z',
        'status': 'completed',
      };
      Map<String, Object?> ratingEvent(int rating) => {
        'entryId': 'rating-$sid',
        'eventId': 'rating-$sid',
        'kind': 'effort_rating',
        'loggedAt': '2026-09-25T09:30:10.000Z',
        'rating': rating,
      };

      Future<(MockWorkoutRepository, _RatedSpy, WatchSessionInbox)>
      wristRig() async {
        final repo = await _freshRepo();
        await seedCaptureCatalog(repo);
        final spy = _RatedSpy(repo);
        var ids = 0;
        final inbox = WatchSessionInbox(
          repository: repo,
          transport: CaptureTransport(),
          validator: loadProtocolValidator(),
          clock: () => DateTime.utc(2026, 9, 25, 11),
          idFactory: () => 'msg-phone-${++ids}',
          onFailure: Error.throwWithStackTrace,
          healthSync: spy,
        );
        return (repo, spy, inbox);
      }

      Future<void> deliver(
        WatchSessionInbox inbox,
        List<Map<String, Object?>> events,
      ) async {
        for (var i = 0; i < events.length; i++) {
          await inbox.receive(
            observationsUp(sid, [events[i]], messageId: 'msg-w-$i'),
          );
        }
        await pumpEventQueue();
      }

      test('S-90-5 an import that applies a rating after the session landed '
          'tells the sync service once', () async {
        final (repo, spy, inbox) = await wristRig();
        await deliver(inbox, [setEvent(), endEvent()]);
        expect(spy.rated, isEmpty, reason: 'the session landed unrated');

        await deliver(inbox, [ratingEvent(4)]);

        expect(spy.rated, hasLength(1));
        expect(spy.rated.single.id, sid);
        expect(spy.rated.single.sessionFeeling, 4);
        expect(spy.rated.single.endedAtMs, isNotNull);
        expect((await repo.getSession(sid))?.sessionFeeling, 4);
      });

      test('S-90-5 an import that creates the session with its rating tells '
          'the sync service once', () async {
        final (repo, spy, inbox) = await wristRig();
        await deliver(inbox, [ratingEvent(2), setEvent(), endEvent()]);

        expect((await repo.getSession(sid))?.sessionFeeling, 2);
        expect(spy.rated, hasLength(1));
        expect(spy.rated.single.id, sid);
        expect(spy.rated.single.sessionFeeling, 2);
      });

      test('S-90-5 an import that applies no rating does not', () async {
        final (repo, spy, inbox) = await wristRig();
        await deliver(inbox, [setEvent(), endEvent()]);

        expect(await repo.getSession(sid), isNotNull);
        expect(spy.rated, isEmpty);
      });
    });
  });

  group('S-90-6 delete clears the effort, then the workout', () {
    test('S-90-6 discarding a finished session calls clearWorkoutEffort then '
        'deleteWorkouts, both with the exact span', () async {
      final rig = await _Rig.create();
      final state = WorkoutState(rig.repo, healthSync: rig.sync);
      await rig.repo.createSession(_session('s-1', feeling: 4));
      await state.loadHistoricalSession('s-1');

      await state.discardCurrentSession();
      await pumpEventQueue();

      expect([for (final c in rig.platform.calls) c.kind], ['clear', 'delete']);
      for (final c in rig.platform.calls) {
        expect(c.start, DateTime.fromMillisecondsSinceEpoch(_at(9, 0)));
        expect(c.end, DateTime.fromMillisecondsSinceEpoch(_at(10, 0)));
      }
    });

    test('S-90-6 a discarded running session calls neither', () async {
      final rig = await _Rig.create();
      final state = WorkoutState(rig.repo, healthSync: rig.sync);
      await state.createNewSession(modality: Modality.resistanceLifting);

      await state.discardCurrentSession();
      await pumpEventQueue();

      expect(rig.platform.calls, isEmpty);
    });
  });

  group('S-90-7 the contract', () {
    test('S-90-7 the unavailable service answers unavailable', () async {
      const service = UnavailableHealthPlatformService();
      final start = DateTime(2026, 10, 28, 9);
      final end = DateTime(2026, 10, 28, 10);
      expect(
        await service.setWorkoutEffort(start, end, 8),
        HealthEffortOutcome.unavailable,
      );
      expect(await service.clearWorkoutEffort(start, end), isFalse);
    });

    test('S-90-7 nothing outside the io gateway names the effort channel', () {
      const gateway = 'lib/core/services/health_platform_gateway_io.dart';
      final offenders = <String>[];
      for (final dir in const [
        'lib/state',
        'lib/features',
        'lib/widgets',
        'lib/core',
      ]) {
        for (final entity in Directory(dir).listSync(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;
          if (entity.path.replaceAll('\\', '/') == gateway) continue;
          if (entity.readAsStringSync().contains('omnitrain/health_effort')) {
            offenders.add(entity.path);
          }
        }
      }
      expect(offenders, isEmpty);
    });
  });
}
