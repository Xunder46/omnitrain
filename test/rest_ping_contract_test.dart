// The phone half of the rest-ping contract: the one table both rules read, and
// what the phone sends it in.
//
// Plan: `docs/plans/2026-10-08-22-rest-ping-on-watch-plan/2026-10-08-22-rest-ping-on-watch-plan.md`
// (D-242, D-243, D-246, D-248, D-250). Scenario mapping:
//   S-241 one-second polls → `S-241 ...`
//   S-242 Off → `S-242 ...`
//   S-244 the interval lowered mid-rest → `S-244 ...`
//   S-221 the same second polled twice → `S-221 ...`
//   S-223 a long interval → `S-223 ...`
//   S-246 the wire → `S-246 ...`
//   S-248 end to end on the phone → `S-248 ...`
//
// The table is the single source of the numbers, so this file walks it instead
// of restating it. Two of its rows are not the phone's to judge — S-243's gap
// between polls and S-222's second poll, the interval arriving after the rest
// opened — because the phone's own loop polls every elapsed second and
// remembers the second it last pinged; those rows belong to the wrist's rule,
// which reads the same table.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/platform/watch_delivery.dart';
import 'package:omnitrain/core/platform/watch_transport.dart';
import 'package:omnitrain/core/sync_protocol/wire_timestamps.dart';
import 'package:omnitrain/core/utils/rest_ping_utils.dart';
import 'package:omnitrain/core/utils/watch_reference_sync.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/watch/live_session_mirror_state.dart';
import 'package:omnitrain/state/watch/watch_sync_request_handler.dart';
import 'package:omnitrain/state/watch/watch_sync_wiring.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/sync_protocol_harness.dart';

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

/// The row a scenario owns.
Map<String, Object?> _case(String scenario) => _cases().firstWhere(
  (row) => (row['name']! as String).startsWith('$scenario '),
  orElse: () => throw StateError('the table holds no row for $scenario'),
);

List<int> _seconds(Map<String, Object?> row, String key) => [
  for (final second in row[key]! as List) second! as int,
];

/// The phone's ping, driven the way `_checkRestPings` drives it
/// (`lib/features/session/workout_session_global_timer.dart:34`): every elapsed
/// second of the open rest is polled, the last second pinged is remembered, and
/// a rest that opens starts from zero because the app clears its map per rest
/// (`workout_session_screen.dart:782`, `workout_session_timer_mixin.dart:512`).
List<int> _phoneTaps(Map<String, Object?> row) {
  final interval = row['intervalSeconds']! as int;
  final taps = <int>[];
  var lastPinged = 0;

  for (final elapsed in _seconds(row, 'pollsSeconds')) {
    if (!shouldFireRestPing(
      elapsed: elapsed,
      interval: interval,
      lastPinged: lastPinged,
    )) {
      continue;
    }
    taps.add(elapsed);
    lastPinged = elapsed;
  }
  return taps;
}

final DateTime _now = DateTime.utc(2026, 10, 8, 12);

/// A transport that keeps what it was handed, so the phone's answer can be read.
class _RecordingTransport implements WatchMirrorTransport {
  final List<Map<String, Object?>> sent = [];

  @override
  Future<WatchDelivery> send(Map<String, Object?> envelope) async {
    sent.add(envelope);
    return WatchDelivery.delivered;
  }

  @override
  Future<void> requestSnapshot() async {}
}

void main() {
  group('the table every device reads', () {
    test('every row names its scenario, polls in order, and taps a second it '
        'polled', () {
      final rows = _cases();

      expect(rows, isNotEmpty, reason: 'D-246 one table, read by both rules');
      for (final row in rows) {
        final name = row['name']! as String;
        final polls = _seconds(row, 'pollsSeconds');
        final taps = _seconds(row, 'tapSeconds');

        expect(
          name,
          matches(RegExp(r'^S-\d+ \S')),
          reason: 'a row names the scenario it carries',
        );
        expect(
          row['intervalSeconds'],
          isA<int>(),
          reason: '$name: the interval is the phone setting it stands for',
        );
        expect(
          row['intervalSeconds']! as int,
          greaterThanOrEqualTo(0),
          reason: '$name: 0 is Off',
        );
        expect(polls, isNotEmpty, reason: '$name polls the seconds of a rest');
        expect(
          polls,
          orderedEquals(polls.toList()..sort()),
          reason: '$name: a rest polls its elapsed seconds in order',
        );
        expect(
          taps,
          orderedEquals(taps.toList()..sort()),
          reason: '$name: a rest never pings the same second twice',
        );
        for (final tap in taps) {
          expect(
            polls,
            contains(tap),
            reason: '$name: a tap is a second the row polls',
          );
        }
      }
    });

    test('the rows are the seven scenarios the plan names', () {
      expect(
        {for (final row in _cases()) (row['name']! as String).split(' ').first},
        {'S-221', 'S-222', 'S-223', 'S-241', 'S-242', 'S-243', 'S-244'},
        reason: 'the register is the table: two edge rows and five core rows',
      );
    });
  });

  group('S-241 one-second polls', () {
    test('S-241 an interval of 30 polled every second from 0 to 100 pings at '
        '30, 60 and 90 and nowhere else', () {
      final row = _case('S-241');

      expect(
        _phoneTaps(row),
        _seconds(row, 'tapSeconds'),
        reason: 'S-241 the table\'s own taps, driven through the phone\'s rule',
      );
    });
  });

  group('S-221 the same second polled twice', () {
    test('S-221 a second polled three times pings once', () {
      final row = _case('S-221');

      expect(
        _phoneTaps(row),
        _seconds(row, 'tapSeconds'),
        reason:
            'S-221 the ping is the boundary crossed, not the poll that '
            'noticed it',
      );
      expect(
        _seconds(row, 'pollsSeconds'),
        [
          row['intervalSeconds'],
          row['intervalSeconds'],
          row['intervalSeconds'],
        ],
        reason: 'S-221 the fixture polls one second three times',
      );
    });
  });

  group('S-223 a long interval', () {
    test('S-223 an interval of 180 over 0 to 200 pings once, at 180', () {
      final row = _case('S-223');

      expect(
        _phoneTaps(row),
        _seconds(row, 'tapSeconds'),
        reason: 'S-223 the only boundary inside the rest is the one it crosses',
      );
    });
  });

  group('S-242 Off', () {
    test('S-242 an interval of 0 polled every second from 0 to 600 pings '
        'nowhere', () {
      final row = _case('S-242');

      expect(
        _phoneTaps(row),
        _seconds(row, 'tapSeconds'),
        reason: 'S-242 Off taps on no second, however long the rest runs',
      );
    });
  });

  group('S-244 the interval is lowered mid-rest', () {
    test('S-244 the phone pings only the boundaries still to come after the '
        'interval is lowered past one already pinged', () {
      final row = _case('S-244');

      expect(
        _phoneTaps(row),
        _seconds(row, 'tapSeconds'),
        reason:
            'S-244 a boundary already pinged is not pinged again when the '
            'interval is lowered past it',
      );
    });
  });

  group('S-246 the wire', () {
    test('S-246 the payload carries the interval the table names, and the '
        'protocol accepts it', () {
      final field = _contract()['preferencesField']! as String;
      final message = WatchReferenceSync.buildPreferencesDown(
        effortRatingPrompt: false,
        restPingSeconds: 90,
        generatedAt: _now,
      );

      expect(
        asObject(message['payload']),
        {'generatedAt': utcIso(_now), 'effortRatingPrompt': false, field: 90},
        reason:
            'S-246 the payload is the phone\'s settings, under the key the '
            'contract names',
      );
      expect(
        loadProtocolValidator().validateEnvelope(message),
        isEmpty,
        reason: 'S-246 the wrist must be able to accept what the phone sends',
      );
    });

    test('S-246 two intervals stamped in one millisecond are two messages, and '
        'a rebuild is one', () {
      final sixty = WatchReferenceSync.buildPreferencesDown(
        effortRatingPrompt: false,
        restPingSeconds: 60,
        generatedAt: _now,
      );
      final ninety = WatchReferenceSync.buildPreferencesDown(
        effortRatingPrompt: false,
        restPingSeconds: 90,
        generatedAt: _now,
      );

      expect(
        sixty['messageId'],
        isNot(ninety['messageId']),
        reason:
            'S-246 a tie on generatedAt goes to the later-received copy, so '
            'two settings must not share a delivery key',
      );
      expect(
        WatchReferenceSync.buildPreferencesDown(
          effortRatingPrompt: false,
          restPingSeconds: 90,
          generatedAt: _now,
        )['messageId'],
        ninety['messageId'],
        reason: 'S-246 a rebuild of the same settings is the same message',
      );
    });
  });

  group('S-248 the phone sends the interval it holds', () {
    test('S-248 a wrist sync is answered with the Rest Ping setting the phone '
        'holds', () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();
      final settings = SettingsState(repository, fakePreferencesService());
      await settings.setRestPingInterval(45);

      final transport = _RecordingTransport();
      final handler = WatchSyncRequestHandler(
        mirror: LiveSessionMirrorState(
          transport: transport,
          snapshot: watchSessionPlaceholder,
        ),
        transport: transport,
        repository: repository,
        settings: settings,
        clock: () => _now,
      );

      expect(
        await handler.handle(WatchTransportRequest.routines),
        isTrue,
        reason: 'S-248 the wrist asked, so the phone answered',
      );

      final preferences = transport.sent.firstWhere(
        (frame) => frame['type'] == 'preferences_down',
      );
      expect(
        asObject(preferences['payload']),
        {
          'generatedAt': utcIso(_now),
          'effortRatingPrompt': settings.showFeelingSurvey,
          _contract()['preferencesField']! as String: 45,
        },
        reason:
            'S-248 the setting the phone holds when the wrist asks is the '
            'one that reaches it',
      );
    });
  });
}
