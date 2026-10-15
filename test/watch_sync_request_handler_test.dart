// The phone's answer to the wrist's Sync request, when the wrist says which
// exercise list it already holds.
//
// Plan: `docs/plans/2026-10-11-23e2-phone-sends-exercise-batches-plan/`
// (D-3834). Scenario mapping:
//   S-3850 the wrist names the current version → `S-3850 ...`
//   S-3851 no version: the batches in index order → `S-3851 ...`
//   S-3852 a stale version: the batches → `S-3852 ...`
//   S-3853 a batch the radio refuses stops the rest → `S-3853 ...`
//   S-3854 the version round-trips, and a custom exercise stales it
//          → `S-3854 ...`
//   S-3857 a phone with no capable exercise sends no batch → `S-3857 ...`
//          (the ratified D-3831 behaviour the review asked to pin)
//
// The transport here is a recorder, not the graph: this file is about what the
// handler sends, and in what order. That the graph's inbound handler hands the
// frame's version on is S-3855 in `test/watch_session_projection_test.dart`.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/platform/watch_delivery.dart';
import 'package:omnitrain/core/platform/watch_transport.dart';
import 'package:omnitrain/core/utils/watch_reference_sync.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/watch/live_session_mirror_state.dart';
import 'package:omnitrain/state/watch/watch_sync_request_handler.dart';
import 'package:omnitrain/state/watch/watch_sync_wiring.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/sync_protocol_harness.dart';

final DateTime _now = DateTime.utc(2026, 10, 11, 12);

/// A transport that keeps what it was handed, and can answer [undelivered] for
/// one `exercises_down` batch (S-3853).
class _RecordingTransport implements WatchMirrorTransport {
  final List<Map<String, Object?>> sent = [];

  /// The `batchIndex` the radio refuses, or null when it carries every batch.
  int? undeliveredBatchIndex;

  @override
  Future<WatchDelivery> send(Map<String, Object?> envelope) async {
    sent.add(envelope);
    if (envelope['type'] == 'exercises_down' && undeliveredBatchIndex != null) {
      final payload = asObject(envelope['payload']);
      if (payload['batchIndex'] == undeliveredBatchIndex) {
        return WatchDelivery.undelivered;
      }
    }
    return WatchDelivery.delivered;
  }

  @override
  Future<void> requestSnapshot() async {}

  /// The types the transport was handed, in send order.
  List<String> get types => [
    for (final frame in sent) frame['type']! as String,
  ];

  /// Every frame of [type], in send order.
  List<Map<String, Object?>> ofType(String type) => [
    for (final frame in sent)
      if (frame['type'] == type) frame,
  ];

  /// The batch indices of the `exercises_down` frames it was handed, in order.
  List<Object?> get batchIndices => [
    for (final batch in ofType('exercises_down'))
      asObject(batch['payload'])['batchIndex'],
  ];

  /// The version the first batch of the last answer names, or null when no
  /// batch was sent.
  String? get sentVersion {
    final batches = ofType('exercises_down');
    return batches.isEmpty
        ? null
        : asObject(batches.first['payload'])['catalogVersion']! as String;
  }
}

void main() {
  late MockWorkoutRepository repository;
  late SettingsState settings;
  late _RecordingTransport transport;
  late WatchSyncRequestHandler handler;

  setUp(() async {
    repository = MockWorkoutRepository();
    await repository.initialize();
    settings = SettingsState(repository, fakePreferencesService());
    transport = _RecordingTransport();
    handler = WatchSyncRequestHandler(
      mirror: LiveSessionMirrorState(
        transport: transport,
        snapshot: watchSessionPlaceholder,
      ),
      transport: transport,
      repository: repository,
      settings: settings,
      clock: () => _now,
    );
  });

  /// The version the phone would name for the exercise list it holds right now.
  Future<String> currentVersion() async {
    final batches = await WatchReferenceSync.buildExercisesDown(
      repository: repository,
      generatedAt: _now,
    );
    return asObject(batches.first['payload'])['catalogVersion']! as String;
  }

  group('S-3850…S-3853 the phone sends only the list the wrist lacks', () {
    test(
      'S-3850 the wrist names the current version: no batch travels',
      () async {
        final version = await currentVersion();

        expect(
          await handler.handle(
            WatchTransportRequest.routines,
            exercisesVersion: version,
          ),
          isTrue,
          reason: 'S-3850 the wrist asked, so the phone answered',
        );

        expect(
          transport.types,
          ['preferences_down', 'routines_down'],
          reason:
              'S-3850 the wrist holds the list, so the preferences and the '
              'routines travel and no exercise batch does',
        );
      },
    );

    test('S-3857 a phone with no capable exercise sends preferences and '
        'routines and no batch', () async {
      repository.clear();
      await repository.createExercise(
        Exercise(
          id: 'exercise-plain',
          name: 'Plain Move',
          createdAtMs: _now.millisecondsSinceEpoch,
          updatedAtMs: _now.millisecondsSinceEpoch,
        ),
      );
      await repository.setExerciseCapabilities('exercise-plain', const []);

      expect(await handler.handle(WatchTransportRequest.routines), isTrue);

      expect(
        transport.types,
        ['preferences_down', 'routines_down'],
        reason:
            'S-3857 no exercise the wrist could log is no list to send, so '
            'the wrist keeps the list it holds (D-3831)',
      );
    });

    test('S-3851 with no version the phone sends the whole list, in index '
        'order', () async {
      expect(await handler.handle(WatchTransportRequest.routines), isTrue);

      expect(
        transport.types.take(2),
        ['preferences_down', 'routines_down'],
        reason: 'S-253 the preferences lead, and the routines follow them',
      );
      expect(
        transport.batchIndices,
        [0, 1, 2],
        reason:
            'S-3851 the seeded catalog fills three batches of at most 100, '
            'sent one at a time in index order',
      );
      expect(
        transport.types.skip(2),
        everyElement('exercises_down'),
        reason: 'S-3851 nothing but the exercise list follows the routines',
      );
    });

    test(
      'S-3852 a version the phone no longer holds sends the whole list',
      () async {
        expect(
          await handler.handle(
            WatchTransportRequest.routines,
            exercisesVersion: 'v1-0-nothing-here',
          ),
          isTrue,
        );

        expect(
          transport.batchIndices,
          [0, 1, 2],
          reason:
              'S-3852 the version differs from the list the phone holds, so '
              'the whole list travels again',
        );
      },
    );

    test('S-3853 a batch the radio refuses stops the rest, and the answer '
        'still holds', () async {
      transport.undeliveredBatchIndex = 1;

      expect(await handler.handle(WatchTransportRequest.routines), isTrue);

      expect(
        transport.batchIndices,
        [0, 1],
        reason:
            'S-3853 the batch after the one the radio refused is never '
            'attempted: the wrist keeps the list it had',
      );
    });
  });

  group(
    'S-3854 the version round-trips, and a change to the list stales it',
    () {
      test('S-3854 a sync with the sent version sends no batch, and a custom '
          'exercise stales it', () async {
        await handler.handle(WatchTransportRequest.routines);
        final held = transport.sentVersion!;
        expect(held, isNotEmpty);

        transport.sent.clear();
        await handler.handle(
          WatchTransportRequest.routines,
          exercisesVersion: held,
        );
        expect(
          transport.ofType('exercises_down'),
          isEmpty,
          reason:
              'S-3854 the wrist holds the version the phone named, so the '
              'list is not sent again',
        );

        await repository.createExercise(
          Exercise(
            id: 'exercise-custom-burpee',
            name: 'Custom Burpee',
            createdAtMs: _now.millisecondsSinceEpoch,
            updatedAtMs: _now.millisecondsSinceEpoch,
          ),
        );
        await repository.setExerciseCapabilities(
          'exercise-custom-burpee',
          const ['reps', 'sets'],
        );

        transport.sent.clear();
        expect(
          await handler.handle(
            WatchTransportRequest.routines,
            exercisesVersion: held,
          ),
          isTrue,
        );
        expect(
          transport.ofType('exercises_down'),
          isNotEmpty,
          reason:
              'S-3854 the phone\'s list changed, so the old version is stale '
              'and the whole list travels',
        );
        expect(
          transport.sentVersion,
          isNot(held),
          reason: 'S-3854 the list with the custom exercise is another version',
        );
      });
    },
  );

  group('S-3903 the phone sends its units with the preferences', () {
    Map<String, Object?> sentPreferences() =>
        asObject(transport.ofType('preferences_down').single['payload']);

    test('pounds and miles travel as the phone holds them', () async {
      await settings.setPreferredWeightUnit('lbs');
      await settings.setPreferredDistanceUnit('miles');

      expect(await handler.handle(WatchTransportRequest.routines), isTrue);

      final payload = sentPreferences();
      expect(payload['weightUnit'], 'lbs');
      expect(payload['distanceUnit'], 'miles');
    });

    test('the defaults travel too, so the wrist is told rather than left '
        'to assume', () async {
      expect(await handler.handle(WatchTransportRequest.routines), isTrue);

      final payload = sentPreferences();
      expect(payload['weightUnit'], 'kg');
      expect(payload['distanceUnit'], 'km');
    });
  });
}
