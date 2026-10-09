// The Dart half of the rest-ping contract: the rule the Wear surface runs,
// read from the one table both rules share.
//
// Plan: `docs/plans/2026-10-08-22b-rest-ping-wear-settings-docs-plan/`
// (D-261, D-265). Scenario mapping:
//   S-241 the table, one-second polls        → `S-241 ...`
//   S-242 Off and unknown                    → `S-242 ...`
//   S-243 a gap taps once                    → `S-243 ...`
//   S-244 the interval changes mid-rest      → `S-244 ...`
//   S-245 the next rest starts clean         → `S-245 ...`
//   S-221 the same second polled three times → `S-221 ...`
//   S-222 the interval arrives mid-rest      → `S-222 ...`
//   S-223 a large interval                   → `S-223 ...`
//   S-224 a closed rest is never evaluated   → `S-224 ...`
//
// The table is the single source of the numbers, so this file walks it instead
// of restating it: a row's `pollsSeconds` are the elapsed seconds at which the
// wrist consults the rule and its `tapSeconds` are the polls that tap.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/watch/watch_session_inbox.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/watch/logging/watch_metric_stepping.dart';
import 'package:omnitrain/watch/logging/watch_rest_ping.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/sync_protocol_harness.dart';
import 'helpers/watch_capture_import_harness.dart';

/// `watch/contract/watch_rest_ping_contract.json`, parsed.
Map<String, Object?> _contract() => asObject(
  jsonDecode(
    File(
      '${Directory.current.path}/watch/contract/'
      'watch_rest_ping_contract.json',
    ).readAsStringSync(),
  ),
);

/// The table's cases, in file order.
List<Map<String, Object?>> _cases() => objectsOf(_contract()['cases']);

/// The rows a scenario owns — a scenario may carry more than one.
List<Map<String, Object?>> _casesFor(String scenario) => [
  for (final row in _cases())
    if ((row['name']! as String).startsWith('$scenario ')) row,
];

/// The one row a scenario owns.
Map<String, Object?> _case(String scenario) => _casesFor(scenario).first;

List<int> _seconds(Map<String, Object?> row, String key) => [
  for (final second in row[key]! as List) second! as int,
];

/// S-340's fixture as the wrist delivered it: one set at `T0 = 10:00:00`, the
/// rest that followed it from `T0+10s` to `T0+80s`, and the end at `T0+3600s`.
/// Staged one `observations_up` per event and imported.
const String _importedSessionId = 's-cap-1';
const String _importedSessionStart = '2026-09-25T10:00:00.000Z';
const String _importedSessionEnd = '2026-09-25T11:00:00.000Z';
const String _importedRestStart = '2026-09-25T10:00:10.000Z';
const String _importedRestEnd = '2026-09-25T10:01:20.000Z';

Future<MockWorkoutRepository> _importedRepoWithRest() async {
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
      'entryId': 'e-set-a',
      'eventId': 'e-set-a',
      'kind': 'set',
      'loggedAt': _importedSessionStart,
      'sessionExerciseId': 'sx-bench',
      'exerciseId': 'ex-bench',
      'reps': 5,
      'loadKg': 80,
    },
    {
      'entryId': 'e-rest-a',
      'eventId': 'e-rest-a',
      'kind': 'rest',
      'loggedAt': _importedRestEnd,
      'sessionExerciseId': 'sx-bench',
      'exerciseId': 'ex-bench',
      'startedAt': _importedRestStart,
      'endedAt': _importedRestEnd,
      'afterEntryId': 'e-set-a',
    },
    {
      'entryId': 'end-$_importedSessionId',
      'eventId': 'end-$_importedSessionId',
      'kind': 'session_end',
      'loggedAt': _importedSessionEnd,
      'startedAt': _importedSessionStart,
      'endedAt': _importedSessionEnd,
      'status': 'completed',
    },
  ];
  for (var i = 0; i < events.length; i++) {
    await inbox.receive(
      observationsUp(_importedSessionId, [events[i]], messageId: 'msg-s340-$i'),
    );
  }
  return repository;
}

/// The rule driven the way the wrist drives it: once per poll second, with the
/// open rest row's id carried between polls.
List<int> _taps(Map<String, Object?> row, {String restId = 'rest-A'}) {
  final rule = WatchRestPing();
  final interval = row['intervalSeconds']! as int;
  final taps = <int>[];

  for (final elapsed in _seconds(row, 'pollsSeconds')) {
    if (rule.isOwed(restId: restId, elapsed: elapsed, interval: interval)) {
      taps.add(elapsed);
    }
  }
  return taps;
}

void main() {
  group('the table, walked by the Dart rule', () {
    test('every row taps exactly the seconds it names', () {
      final rows = _cases();

      expect(rows, isNotEmpty, reason: 'D-261 the table is the rule\'s source');
      for (final row in rows) {
        expect(
          _taps(row),
          _seconds(row, 'tapSeconds'),
          reason: row['name']! as String,
        );
      }
    });

    test('S-241 an interval of 30 polled every second from 0 to 100 taps at '
        '30, 60 and 90 and nowhere else', () {
      final row = _case('S-241');

      expect(
        _taps(row),
        _seconds(row, 'tapSeconds'),
        reason: 'S-241 the Dart rule reports the table\'s own taps',
      );
    });
  });

  group('S-242 Off and unknown', () {
    test('S-242 an interval of 0 polled every second to 600 taps nowhere', () {
      final row = _case('S-242');

      expect(_taps(row), isEmpty, reason: 'S-242 Off never pings');
      expect(
        _seconds(row, 'tapSeconds'),
        isEmpty,
        reason: 'S-242 the table\'s Off row names no tap',
      );
    });

    test('S-242 the interval reaches the rule from Settings, and Off is its '
        'never-set default', () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();
      final settings = SettingsState(repository, fakePreferencesService());
      await settings.initialize();

      expect(
        WatchUnitPreferences.fromSettings(settings).restPingSeconds,
        0,
        reason: 'S-242 a phone that has never set it sends Off',
      );

      await settings.setRestPingInterval(45);

      expect(
        WatchUnitPreferences.fromSettings(settings).restPingSeconds,
        45,
        reason: 'S-242 the wrist carries the interval the phone holds',
      );
    });
  });

  group('S-243 a gap taps once', () {
    test('S-243 an interval of 60 polled at 0, 59, 200, 201 and 240 taps at '
        '200 and 240, not once per skipped multiple', () {
      final row = _case('S-243');

      expect(
        _taps(row),
        _seconds(row, 'tapSeconds'),
        reason: 'S-243 the boundary is crossed, not counted',
      );
    });
  });

  group('S-244 the interval changes mid-rest', () {
    test('S-244 the table row taps only the boundaries still to come', () {
      final row = _case('S-244');

      expect(
        _taps(row),
        _seconds(row, 'tapSeconds'),
        reason: 'S-244 a boundary already pinged is not pinged again',
      );
    });

    test('S-244 lowering the interval past a boundary already pinged does not '
        'ping it again', () {
      final rule = WatchRestPing();
      final before = <int>[
        for (var elapsed = 0; elapsed <= 70; elapsed++)
          if (rule.isOwed(restId: 'rest-A', elapsed: elapsed, interval: 60))
            elapsed,
      ];
      expect(before, [60], reason: 'S-244 the interval of 60 tapped at 60');

      expect(
        rule.isOwed(restId: 'rest-A', elapsed: 70, interval: 30),
        isFalse,
        reason: 'S-244 the same second is not pinged again after the change',
      );
      expect(
        rule.isOwed(restId: 'rest-A', elapsed: 90, interval: 30),
        isTrue,
        reason: 'S-244 the next tap is the next multiple of the new interval',
      );
    });
  });

  group('S-245 a rest ends, the next starts clean', () {
    test('S-245 the next rest row taps at its own first boundary, and a closed '
        'rest is never evaluated', () {
      final rule = WatchRestPing();

      final firstRest = <int>[
        for (var elapsed = 0; elapsed <= 65; elapsed++)
          if (rule.isOwed(restId: 'rest-A', elapsed: elapsed, interval: 30))
            elapsed,
      ];
      expect(firstRest, [30, 60], reason: 'S-245 rest A taps at its multiples');

      expect(
        rule.isOwed(restId: null, elapsed: null, interval: 30),
        isFalse,
        reason: 'S-245 rest A is closed, so the rule is not consulted',
      );

      final nextRest = <int>[
        for (var elapsed = 0; elapsed <= 35; elapsed++)
          if (rule.isOwed(restId: 'rest-B', elapsed: elapsed, interval: 30))
            elapsed,
      ];
      expect(
        nextRest,
        [30],
        reason: 'S-245 a new rest row starts from nothing, not from rest A\'s '
            'last boundary',
      );
    });
  });

  group('S-221 the same second polled three times', () {
    test('S-221 an interval of 30 with the same second polled three times taps '
        'once', () {
      final row = _case('S-221');

      expect(
        _taps(row),
        _seconds(row, 'tapSeconds'),
        reason: 'S-221 the ping is the boundary crossed, not the poll that '
            'noticed it',
      );
    });
  });

  group('S-222 the interval arrives mid-rest', () {
    test('S-222 arriving at elapsed 20, the formula governs: 30, 60 and 90',
        () {
      final row = _casesFor('S-222').first;
      final interval = row['intervalSeconds']! as int;
      final rule = WatchRestPing();
      final taps = <int>[];

      for (final elapsed in _seconds(row, 'pollsSeconds')) {
        // Off until the copy lands at elapsed 20, which is this row's fixture.
        final live = elapsed < 20 ? 0 : interval;
        if (rule.isOwed(restId: 'rest-A', elapsed: elapsed, interval: live)) {
          taps.add(elapsed);
        }
      }

      expect(
        taps,
        _seconds(row, 'tapSeconds'),
        reason: 'S-222 the boundary is crossed, not counted',
      );
    });

    test('S-222 arriving at elapsed 35 taps once on the next poll, then the '
        'multiples after it', () {
      final row = _casesFor('S-222').last;

      expect(
        _taps(row),
        _seconds(row, 'tapSeconds'),
        reason: 'S-222 a boundary that fell before the interval arrived still '
            'taps, once, on the next poll',
      );
    });
  });

  group('S-223 a large interval', () {
    test('S-223 an interval of 180 over 0 to 200 taps once, at 180', () {
      final row = _case('S-223');

      expect(
        _taps(row),
        _seconds(row, 'tapSeconds'),
        reason: 'S-223 the only boundary inside the rest is the one it crosses',
      );
    });
  });

  group('S-224 a closed rest is never evaluated', () {
    test('S-224 a rest closed before its next boundary taps nothing afterwards',
        () {
      final rule = WatchRestPing();

      expect(
        rule.isOwed(restId: 'rest-A', elapsed: 30, interval: 30),
        isTrue,
        reason: 'S-224 the boundary at 30 taps while the rest is open',
      );

      // Next at 40: the elapsed getter is nil once the rest is closed, so the
      // rule is not consulted with an elapsed at all.
      expect(
        rule.isOwed(restId: null, elapsed: null, interval: 30),
        isFalse,
        reason: 'S-224 a closed rest has no id and no elapsed to judge',
      );
      for (final elapsed in const [60, 90, 120]) {
        expect(
          rule.isOwed(restId: null, elapsed: elapsed, interval: 30),
          isFalse,
          reason: 'S-224 a closed rest has no row id, so nothing taps',
        );
      }
      expect(
        rule.isOwed(restId: 'rest-A', elapsed: null, interval: 30),
        isFalse,
        reason: 'S-224 no elapsed means no rest to judge',
      );
    });
  });

  group('S-340 an imported wrist rest', () {
    test(
      'S-340 the phone hands the ping loop no row to evaluate: what the wrist '
      'sent is over before it arrives',
      () async {
        final repository = await _importedRepoWithRest();
        final workout = WorkoutState(repository);
        await workout.loadHistoricalSession(_importedSessionId);

        final segment =
            (await repository.getSessionSegments(_importedSessionId)).single;
        final effortId = (await repository.getSegmentEfforts(segment.id))
            .single
            .id;

        final rests = workout.getEntryRests(effortId);
        expect(rests, hasLength(1), reason: 'S-340 the import left one rest');

        // The loop `_checkRestPings` runs: every row whose `restEndMs` is
        // null. One closed row means the loop has nothing to hand the rule.
        final open = [
          for (final rest in rests)
            if (rest.restEndMs == null) rest,
        ];
        expect(
          open,
          isEmpty,
          reason:
              'S-340 the phone holds no open rest, so nothing on the session '
              'screen is owed a ping',
        );

        // Positive control: the row's id against a boundary the rule does
        // tap, so the assertions below are not passing on an id it ignores.
        final rule = WatchRestPing();
        expect(
          rule.isOwed(restId: rests.single.id, elapsed: 30, interval: 30),
          isTrue,
          reason: 'S-340 the boundary at 30 taps while a rest is open',
        );

        expect(
          workout.getRestElapsedSeconds(effortId, rests.single.entryIndex),
          0,
          reason: 'S-340 the elapsed getter answers zero once the rest is over',
        );
        expect(
          rule.isOwed(restId: rests.single.id, elapsed: 0, interval: 30),
          isFalse,
          reason: 'S-340 an elapsed of zero is no boundary: nothing taps',
        );
      },
    );
  });
}
