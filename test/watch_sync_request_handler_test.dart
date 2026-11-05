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
// Plan: `docs/plans/2026-10-21-49a-phone-sends-foods-plan/` (D-1..D-3).
// Scenario mapping:
//   S-7101 preferences, foods, routines, then the batches → `S-7101 ...`
//   S-7102 the food list's order and values, and it validates → `S-7102 ...`
//   S-7103 the version early return does not skip the foods → `S-7103 ...`
//   S-7104 a phone with no foods sends an empty foods frame (S-15204)
//          → `S-7104 ...`
//   S-7105 an undelivered foods frame does not stop the batches → `S-7105 ...`
//
// Plan: `docs/plans/2026-10-22-53-watch-food-screen-and-fresh-foods-plan/`
// (D-7). Scenario mapping:
//   S-8308 a library nobody loaded answers with the repository's foods
//          → `S-8308 ...`
//   S-8309 a log written through to the repository reaches the next request
//          → `S-8309 ...`
//   S-8310 a throwing food read still answers with the rest → `S-8310 ...`
//   S-8316 a throwing group read still sends the foods, uncategorised
//          → `S-8316 ...`
//
// Plan: `docs/plans/2026-10-26-87a-wrist-bests-contract-and-phone-sender-plan/`
// (D-4, D-11). Scenario mapping:
//   S-87a-6 a since-current request is answered with the bests alone
//          → `S-87a-6 ...`
//   S-87a-7 a bests frame the radio refuses changes neither the batches nor
//          the answer → `S-87a-7 ...`
//   S-87a-8 a workout completed between two requests changes the next frame
//          → `S-87a-8 ...`
//   S-87a-11 the sent frame validates, with and without history
//          → `S-87a-11 ...`
//   S-87a-12 each frame is stamped with its request's own clock
//          → `S-87a-12 ...`
//   S-87a-13 no completed sessions reaches the wrist as an empty array
//          → `S-87a-13 ...`
//
// Plan: `docs/plans/2026-10-27-87c-bests-only-when-changed-plan/`
// (D-4, D-5). Scenario mapping:
//   S-87c-1 an idle raise at the same revision is sent no frame and reads no
//          history → `S-87c-1 ...`
//   S-87c-2 a completed workout reaches the next request, then goes quiet
//          → `S-87c-2 ...`
//   S-87c-3 a write that leaves the bests identical costs one walk and no
//          frame → `S-87c-3 ...`
//   S-87c-4 a wrist that does not say it holds the bests is sent them every
//          time → `S-87c-4 ...`
//   S-87c-5 a frame the radio did not carry is sent again, a delivered one is
//          skipped → `S-87c-5 ...`
//   S-87c-6 a phone that relaunched sends once → `S-87c-6 ...`
//   S-87c-7 a repository that cannot tell the revision sends only when the
//          entries moved → `S-87c-7 ...`
//   S-87c-12 a write that lands during the walk is not hidden
//          → `S-87c-12 ...`
//   S-87c-13 an undelivered frame is re-sent, then goes quiet
//          → `S-87c-13 ...`
//   S-87c-14 a request without the flag always sends, even with remembered
//          state → `S-87c-14 ...`
//
// Plan: `docs/plans/2026-11-01-94-watch-water-logging-plan/` (D-6, D-8(a),
// D-9, D-11). Scenario mapping:
//   S-94a-21 a wrist that asks gets the count on every request → `S-94a-21 ...`
//   S-94a-22 a wrist that does not ask gets none → `S-94a-22 ...`
//   S-94a-23 no foods, no routines, still a count → `S-94a-23 ...`
//   S-94a-24 the frame is the phone's own number → `S-94a-24 ...`
//   S-94a-25 a lost or failed count never breaks the answer → `S-94a-25 ...`
//
// The transport here is a recorder, not the graph: this file is about what the
// handler sends, and in what order. That the graph's inbound handler hands the
// frame's version on is S-3855 in `test/watch_session_projection_test.dart`.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/water_constants.dart';
import 'package:omnitrain/core/platform/watch_delivery.dart';
import 'package:omnitrain/core/platform/watch_transport.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/core/sync_protocol/wire_timestamps.dart';
import 'package:omnitrain/core/utils/watch_reference_sync.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/watch/live_session_mirror_state.dart';
import 'package:omnitrain/state/watch/watch_sync_request_handler.dart';
import 'package:omnitrain/state/watch/watch_sync_wiring.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/revisioned_repository.dart';
import 'helpers/sync_protocol_harness.dart';

final DateTime _now = DateTime.utc(2026, 10, 11, 12);

/// A transport that keeps what it was handed, and can answer [undelivered] for
/// one `exercises_down` batch (S-3853).
class _RecordingTransport implements WatchMirrorTransport {
  final List<Map<String, Object?>> sent = [];

  /// The `batchIndex` the radio refuses, or null when it carries every batch.
  int? undeliveredBatchIndex;

  /// Whether the radio refuses the `foods_down` frame (S-7105).
  bool undeliveredFoods = false;

  /// Whether the radio refuses the `bests_down` frame (S-87a-7).
  bool undeliveredBests = false;

  /// What the radio answers for the `bests_down` frame, when set — the
  /// `queued` answer the real transport never gives it (S-87c-5).
  WatchDelivery? bestsDelivery;

  /// Whether the radio refuses the `water_down` frame (S-94a-25).
  bool undeliveredWater = false;

  @override
  Future<WatchDelivery> send(Map<String, Object?> envelope) async {
    sent.add(envelope);
    if (envelope['type'] == 'water_down' && undeliveredWater) {
      return WatchDelivery.undelivered;
    }
    if (envelope['type'] == 'bests_down' && bestsDelivery != null) {
      return bestsDelivery!;
    }
    if (envelope['type'] == 'foods_down' && undeliveredFoods) {
      return WatchDelivery.undelivered;
    }
    if (envelope['type'] == 'bests_down' && undeliveredBests) {
      return WatchDelivery.undelivered;
    }
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

/// A frame with the two values that move between identical sends removed, so
/// two builds over the same inputs can be compared (S-7102).
Map<String, Object?> _withoutClockFields(Map<String, Object?> frame) {
  final payload = Map<String, Object?>.from(asObject(frame['payload']))
    ..remove('generatedAt');
  return (Map<String, Object?>.from(frame)
        ..remove('messageId')
        ..remove('sentAt'))
      ..['payload'] = payload;
}

/// A food as the phone's library holds it, with values unlike the defaults.
Food _food(
  String id,
  String name,
  String groupId, {
  double protein = 0,
  double carbs = 0,
  double fat = 0,
  double? lastAmountConsumed,
}) => Food(
  id: id,
  name: name,
  groupId: groupId,
  unitType: FoodUnitType.grams,
  referenceAmount: 120,
  referenceLabel: 'g',
  protein: protein,
  carbs: carbs,
  fat: fat,
  lastAmountConsumed: lastAmountConsumed,
  createdAtMs: _now.millisecondsSinceEpoch,
  updatedAtMs: _now.millisecondsSinceEpoch,
);

/// A repository whose food reads can be made to throw exactly once, the way a
/// storage failure does: the handler has to answer with what its cache holds
/// (S-8310, S-8316). Armed after a test has populated its library, so the read
/// that fails is the handler's own.
class _ThrowingOnceRepository extends MockWorkoutRepository {
  bool throwOnFoods = false;
  bool throwOnGroups = false;

  bool _foodsThrown = false;
  bool _groupsThrown = false;

  @override
  Future<List<Food>> getFoods({bool includeArchived = false}) {
    if (throwOnFoods && !_foodsThrown) {
      _foodsThrown = true;
      throw StateError('the food table is unavailable');
    }
    return super.getFoods(includeArchived: includeArchived);
  }

  @override
  Future<List<FoodGroup>> getFoodGroups({bool includeArchived = false}) {
    if (throwOnGroups && !_groupsThrown) {
      _groupsThrown = true;
      throw StateError('the food group table is unavailable');
    }
    return super.getFoodGroups(includeArchived: includeArchived);
  }
}

/// A repository whose water read throws, the way a storage failure does: the
/// answer must go on without the count (S-94a-25).
class _ThrowingWaterRepository extends MockWorkoutRepository {
  @override
  Future<int> getWaterVolumeForDate(int dateMs) =>
      throw StateError('the water box is unavailable');
}

/// A completed session holding one set effort (reps × weight), the way the
/// phone stores a workout — the fixture `StatsProgressService` reads its bests
/// from (S-87a-8, S-87a-11). The exercise need not exist in the catalog: the
/// history walk reads efforts, not exercise rows (87a, A-11).
Future<void> _seedCompletedSetSession(
  MockWorkoutRepository repo, {
  required String sessionId,
  required String exerciseId,
  required int reps,
  required double weight,
}) async {
  final startedAtMs = _now.millisecondsSinceEpoch;
  final endedAtMs = startedAtMs + 1000;
  await repo.createSession(
    TrainingSession(
      id: sessionId,
      ownerUserId: 'u-1',
      startedAtMs: startedAtMs,
      endedAtMs: endedAtMs,
      createdAtMs: startedAtMs,
      updatedAtMs: endedAtMs,
    ),
  );

  final segmentId = 'seg-$sessionId';
  await repo.createSegment(
    SessionSegment(
      id: segmentId,
      sessionId: sessionId,
      orderIndex: 0,
      segmentType: 'main',
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );

  final effortId = 'eff-$sessionId';
  await repo.createEffort(
    SegmentEffort(
      id: effortId,
      segmentId: segmentId,
      orderIndex: 0,
      effortKind: 'set',
      exerciseId: exerciseId,
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );
  await repo.createObservation(
    EffortObservation(
      id: 'obs-$effortId-0-reps',
      effortId: effortId,
      metricId: 'metric-reps',
      valueInt: reps,
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );
  await repo.createObservation(
    EffortObservation(
      id: 'obs-$effortId-0-weight',
      effortId: effortId,
      metricId: 'metric-weight',
      valueReal: weight,
      createdAtMs: startedAtMs + 1,
      updatedAtMs: startedAtMs + 1,
    ),
  );
}

/// The 87a history H (S-87c-1..S-87c-14): bench-press 100 × 5 and 100 × 3 in
/// session 1, bench-press 90 × 8, squat 140 × 5 and push-up 0 × 12 in session
/// 2, and session 3 still in progress with a 200 kg bench set of its own — a
/// set the bests must not count.
Future<void> _seedHistory(MockWorkoutRepository repo) async {
  await _seedSession(repo, 'session-1');
  await _seedSet(
    repo,
    sessionId: 'session-1',
    orderIndex: 0,
    exerciseId: 'exercise-bench-press',
    reps: 5,
    weight: 100,
  );
  await _seedSet(
    repo,
    sessionId: 'session-1',
    orderIndex: 1,
    exerciseId: 'exercise-bench-press',
    reps: 3,
    weight: 100,
  );
  await _seedSession(repo, 'session-2');
  await _seedSet(
    repo,
    sessionId: 'session-2',
    orderIndex: 0,
    exerciseId: 'exercise-bench-press',
    reps: 8,
    weight: 90,
  );
  await _seedSet(
    repo,
    sessionId: 'session-2',
    orderIndex: 1,
    exerciseId: 'exercise-squat',
    reps: 5,
    weight: 140,
  );
  await _seedSet(
    repo,
    sessionId: 'session-2',
    orderIndex: 2,
    exerciseId: 'exercise-push-up',
    reps: 12,
    weight: 0,
  );
  await _seedSession(repo, 'session-3', open: true);
  await _seedSet(
    repo,
    sessionId: 'session-3',
    orderIndex: 0,
    exerciseId: 'exercise-bench-press',
    reps: 5,
    weight: 200,
  );
}

/// A session header with no sets; [open] leaves it in progress.
Future<void> _seedSession(
  MockWorkoutRepository repo,
  String id, {
  bool open = false,
}) async {
  final startedAtMs = _now.millisecondsSinceEpoch;
  await repo.createSession(
    TrainingSession(
      id: id,
      ownerUserId: 'u-1',
      startedAtMs: startedAtMs,
      endedAtMs: open ? null : startedAtMs + 1000,
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );
}

/// One set effort in [sessionId], in a segment of its own, the way the history
/// walk reads one (S-87a-11).
Future<void> _seedSet(
  MockWorkoutRepository repo, {
  required String sessionId,
  required int orderIndex,
  required String exerciseId,
  required int reps,
  required double weight,
}) async {
  final startedAtMs = _now.millisecondsSinceEpoch;
  final segmentId = 'seg-$sessionId-$orderIndex';
  await repo.createSegment(
    SessionSegment(
      id: segmentId,
      sessionId: sessionId,
      orderIndex: orderIndex,
      segmentType: 'main',
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );

  final effortId = 'eff-$sessionId-$orderIndex';
  await repo.createEffort(
    SegmentEffort(
      id: effortId,
      segmentId: segmentId,
      orderIndex: orderIndex,
      effortKind: 'set',
      exerciseId: exerciseId,
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );
  await repo.createObservation(
    EffortObservation(
      id: 'obs-$effortId-reps',
      effortId: effortId,
      metricId: 'metric-reps',
      valueInt: reps,
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );
  await repo.createObservation(
    EffortObservation(
      id: 'obs-$effortId-weight',
      effortId: effortId,
      metricId: 'metric-weight',
      valueReal: weight,
      createdAtMs: startedAtMs + 1,
      updatedAtMs: startedAtMs + 1,
    ),
  );
}

void main() {
  late MockWorkoutRepository repository;
  late SettingsState settings;
  late _RecordingTransport transport;
  late WatchSyncRequestHandler handler;

  /// The clock the handler reads; a test that needs two different request
  /// instants moves it (S-87a-12).
  late DateTime current;

  WatchSyncRequestHandler handlerFor(FoodLibraryState library) =>
      WatchSyncRequestHandler(
        mirror: LiveSessionMirrorState(
          transport: transport,
          snapshot: watchSessionPlaceholder,
        ),
        transport: transport,
        repository: repository,
        settings: settings,
        foodLibrary: library,
        clock: () => current,
      );

  setUp(() async {
    repository = MockWorkoutRepository();
    await repository.initialize();
    settings = SettingsState(repository, fakePreferencesService());
    transport = _RecordingTransport();
    current = _now;
    handler = handlerFor(FoodLibraryState(repository));
  });

  /// A library holding four foods in two seeded categories, created out of
  /// order so the Foods-I-Eat order is not the insertion order.
  Future<FoodLibraryState> libraryWithFoods() async {
    await repository.createFood(
      _food(
        'food-protein-lamb',
        'Lamb Loin',
        'food-group-proteins',
        protein: 25,
        fat: 12,
      ),
    );
    await repository.createFood(
      _food(
        'food-veg-broccoli',
        'Broccoli Crowns',
        'food-group-vegetables',
        protein: 3,
        carbs: 7,
        fat: 0.4,
      ),
    );
    await repository.createFood(
      _food(
        'food-protein-beef',
        'Beef Tenderloin',
        'food-group-proteins',
        protein: 30,
        fat: 8,
        lastAmountConsumed: 150,
      ),
    );
    await repository.createFood(
      _food(
        'food-veg-asparagus',
        'Asparagus Spears',
        'food-group-vegetables',
        protein: 2,
        carbs: 4,
        fat: 0.2,
      ),
    );

    final library = FoodLibraryState(repository);
    await library.loadFoods();
    await library.loadFoodGroups();
    return library;
  }

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
          ['preferences_down', 'foods_down', 'routines_down', 'bests_down'],
          reason:
              'S-3850 the wrist holds the list, so the preferences, the '
              'foods and the routines travel and no exercise batch does '
              '(S-15204: the foods frame is the empty one); the bests close '
              'every answer (87a, D-4)',
        );
      },
    );

    test('S-3857 a phone with no capable exercise sends preferences, foods '
        'and routines and no batch', () async {
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
        ['preferences_down', 'foods_down', 'routines_down', 'bests_down'],
        reason:
            'S-3857 no exercise the wrist could log is no list to send, so '
            'the wrist keeps the list it holds (D-3831); the empty foods '
            'frame still travels (S-15204), and the bests still close the '
            'answer (87a, D-4)',
      );
    });

    test('S-3851 with no version the phone sends the whole list, in index '
        'order', () async {
      expect(await handler.handle(WatchTransportRequest.routines), isTrue);

      expect(
        transport.types.take(3),
        ['preferences_down', 'foods_down', 'routines_down'],
        reason:
            'S-253 the preferences lead, the foods follow them (empty on a '
            'phone with none, S-15204), and the routines close the bundle',
      );
      expect(
        transport.batchIndices,
        [0, 1, 2],
        reason:
            'S-3851 the seeded catalog fills three batches of at most 100, '
            'sent one at a time in index order',
      );
      expect(
        transport.types.skip(3),
        ['exercises_down', 'exercises_down', 'exercises_down', 'bests_down'],
        reason:
            'S-3851 the exercise batches follow the routines, then exactly '
            'one bests frame closes the answer (87a, D-4)',
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

  group('S-7101…S-7105 the phone sends the food list with the routines', () {
    test('S-7101 the preferences, the foods, the routines, then the exercise '
        'batches travel in that order', () async {
      final answer = handlerFor(await libraryWithFoods());

      expect(await answer.handle(WatchTransportRequest.routines), isTrue);

      expect(
        transport.types.take(3),
        ['preferences_down', 'foods_down', 'routines_down'],
        reason:
            'S-7101 the preferences lead, then the foods, then the routines; '
            'the exercise list follows them',
      );
      expect(
        transport.types.skip(3),
        ['exercises_down', 'exercises_down', 'exercises_down', 'bests_down'],
        reason:
            'S-7101 only the exercise batches follow the food list, and the '
            'bests close the answer (87a, D-4)',
      );
      expect(
        transport.batchIndices,
        [0, 1, 2],
        reason: 'S-7101 the food list does not displace the exercise batches',
      );
    });

    test('S-7102 the foods travel in the Foods-I-Eat order, with the phone\'s '
        'own serving values, and the frame validates', () async {
      final library = await libraryWithFoods();
      final answer = handlerFor(library);

      expect(await answer.handle(WatchTransportRequest.routines), isTrue);

      final frame = transport.ofType('foods_down').single;
      expect(
        loadProtocolValidator().validateEnvelope(frame),
        isEmpty,
        reason: 'S-7102 the frame is one the protocol schema admits',
      );

      final payload = asObject(frame['payload']);
      final rows = objectsOf(payload['foods']);
      expect(
        [for (final row in rows) row['foodId']],
        [
          'food-protein-beef',
          'food-protein-lamb',
          'food-veg-asparagus',
          'food-veg-broccoli',
        ],
        reason:
            'S-7102 the categories and the foods inside them are alphabetical, '
            'not in the order the foods were created',
      );

      final beef = rows.first;
      expect(beef['name'], 'Beef Tenderloin');
      expect(
        beef['caloriesPerServing'],
        192,
        reason:
            'S-7102 the calories come from the macros the phone holds: '
            '30 g protein and 8 g fat is 30 * 4 + 8 * 9',
      );
      expect(
        beef['defaultServings'],
        1.25,
        reason: 'S-7102 150 g of a food whose serving is 120 g is 1.25',
      );
      expect(
        {for (final row in rows) row['foodId']},
        {
          'food-protein-beef',
          'food-protein-lamb',
          'food-veg-asparagus',
          'food-veg-broccoli',
        },
      );

      final expected = WatchReferenceSync.buildFoodsDown(
        foods: library.foods,
        groups: library.foodGroups,
        generatedAt: _now,
      );
      expect(
        _withoutClockFields(frame),
        _withoutClockFields(expected),
        reason:
            'S-7102 the handler and buildFoodsDown over the same inputs are '
            'the same message',
      );
    });

    test('S-7103 a wrist that holds the exercise list still receives the '
        'foods', () async {
      final version = await currentVersion();
      final answer = handlerFor(await libraryWithFoods());

      expect(
        await answer.handle(
          WatchTransportRequest.routines,
          exercisesVersion: version,
        ),
        isTrue,
      );

      expect(
        transport.types,
        ['preferences_down', 'foods_down', 'routines_down', 'bests_down'],
        reason:
            'S-7103 the version early return sits after the foods and the '
            'routines, so the foods still travel and no exercise batch does; '
            'the bests are sent whatever the wrist holds (87a, D-4)',
      );
    });

    test('S-7104 (S-15204) a phone with no foods sends an empty foods frame '
        'and still sends the rest', () async {
      expect(await handler.handle(WatchTransportRequest.routines), isTrue);

      final foods = transport.ofType('foods_down');
      expect(
        foods,
        hasLength(1),
        reason:
            'S-15204 a readable, empty library is a message: the wrist is '
            'told the list is empty (D-4)',
      );
      final payload = asObject(foods.single['payload']);
      expect(payload['foods'], isEmpty);
      expect(payload['categories'], isEmpty);
      expect(
        loadProtocolValidator().validateEnvelope(foods.single),
        isEmpty,
        reason: 'S-15204 the empty frame is one the protocol schema admits',
      );
      expect(
        transport.types.take(3),
        ['preferences_down', 'foods_down', 'routines_down'],
        reason: 'S-15204 the empty frame travels in the bundle\'s middle slot',
      );
      expect(
        transport.batchIndices,
        [0, 1, 2],
        reason: 'S-7104 the exercise batches are untouched',
      );
    });

    test('S-7105 a foods frame the radio refuses does not stop the exercise '
        'batches', () async {
      transport.undeliveredFoods = true;
      final answer = handlerFor(await libraryWithFoods());

      expect(await answer.handle(WatchTransportRequest.routines), isTrue);

      expect(
        transport.ofType('foods_down'),
        hasLength(1),
        reason: 'S-7105 the foods were attempted once',
      );
      expect(
        transport.ofType('routines_down'),
        isEmpty,
        reason:
            'S-7105 the routines frame is the bundle\'s commit marker: a '
            'foods frame the radio refused means it is not sent, so the '
            'wrist\'s `since` stays old and the next request re-sends all '
            'three',
      );
      expect(
        transport.batchIndices,
        [0, 1, 2],
        reason:
            'S-7105 a refused foods frame is not a reason to hold back the '
            'exercise list',
      );
    });
  });

  group('S-8308…S-8310, S-8316 the handler reloads the food library per '
      'request', () {
    /// The rows of the one `foods_down` the answer carried.
    List<Map<String, Object?>> sentFoods() =>
        objectsOf(asObject(transport.ofType('foods_down').single['payload'])['foods']);

    test('S-8308 a library nobody loaded still answers with the repository\'s '
        'foods', () async {
      await repository.createFood(
        _food('food-f', 'F', 'food-group-x', lastAmountConsumed: 1),
      );

      expect(
        await handler.handle(WatchTransportRequest.routines),
        isTrue,
        reason: 'S-8308 the request is answered even though nothing on the '
            'phone had opened Nutrition',
      );

      final rows = sentFoods();
      expect(
        [for (final row in rows) row['foodId']],
        ['food-f'],
        reason:
            'S-8308 the handler reads the foods from storage, so a library '
            'cache nobody populated is not an empty food list',
      );
      expect(
        loadProtocolValidator().validateEnvelope(
          transport.ofType('foods_down').single,
        ),
        isEmpty,
        reason: 'S-8308 the frame is one the protocol schema admits',
      );
    });

    test('S-8309 a log written through to the repository reaches the next '
        'request', () async {
      final food = _food(
        'food-f',
        'F',
        'food-group-x',
        lastAmountConsumed: 1,
      );
      await repository.createFood(food);
      final library = FoodLibraryState(repository);
      await library.loadFoods();
      await library.loadFoodGroups();
      final answer = handlerFor(library);

      expect(await answer.handle(WatchTransportRequest.routines), isTrue);
      expect(
        (sentFoods().single['defaultServings']! as num).toDouble(),
        closeTo(1 / 120, 1e-9),
        reason: 'S-8309 the cache the library loaded holds the amount the '
            'phone had when it loaded',
      );

      // The write-through leaves the repository row newer than the cache, as
      // `NutritionState._writeThroughLastAmount` does after a log.
      await repository.updateFood(food.copyWith(lastAmountConsumed: 3.0));
      transport.sent.clear();

      expect(await answer.handle(WatchTransportRequest.routines), isTrue);
      expect(
        (sentFoods().single['defaultServings']! as num).toDouble(),
        closeTo(3 / 120, 1e-9),
        reason:
            'S-8309 the reload every request is what makes a log land on the '
            'wrist\'s next sync rather than on the next launch',
      );
    });

    test('S-8310 a throwing food read still answers with the rest', () async {
      final throwing = _ThrowingOnceRepository();
      await throwing.initialize();
      await throwing.createFoodGroup(
        FoodGroup(
          id: 'food-group-x',
          name: 'X',
          createdAtMs: _now.millisecondsSinceEpoch,
          updatedAtMs: _now.millisecondsSinceEpoch,
        ),
      );
      await throwing.createFood(_food('food-f', 'F', 'food-group-x'));
      final library = FoodLibraryState(throwing);
      await library.loadFoods();
      await library.loadFoodGroups();
      throwing.throwOnFoods = true;
      repository = throwing;
      final answer = handlerFor(library);

      expect(
        await answer.handle(WatchTransportRequest.routines),
        isTrue,
        reason: 'S-8310 a storage failure on the foods does not fail the '
            'request',
      );

      expect(
        transport.types.take(2),
        ['preferences_down', 'routines_down'],
        reason: 'S-8310 the preferences and the routines still travel',
      );
      expect(
        transport.batchIndices,
        [0, 1, 2],
        reason: 'S-8310 the exercise list still travels',
      );
      expect(
        transport.ofType('foods_down'),
        isEmpty,
        reason: 'S-8310 a failed read leaves no foods to send, and nothing '
            'else is withheld for it',
      );

      await throwing.createFood(_food('food-g', 'G', 'food-group-x'));
      transport.sent.clear();
      expect(await answer.handle(WatchTransportRequest.routines), isTrue);
      expect(
        [for (final row in sentFoods()) row['foodId']],
        unorderedEquals(['food-f', 'food-g']),
        reason: 'S-8310 the reload is per request: a failed read costs one '
            'sync, not the list',
      );
    });

    test('S-8316 a throwing group read still sends the foods, uncategorised', () async {
      final throwing = _ThrowingOnceRepository();
      await throwing.initialize();
      await throwing.createFoodGroup(
        FoodGroup(
          id: 'food-group-x',
          name: 'X',
          createdAtMs: _now.millisecondsSinceEpoch,
          updatedAtMs: _now.millisecondsSinceEpoch,
        ),
      );
      await throwing.createFood(_food('food-f', 'F', 'food-group-x'));
      final library = FoodLibraryState(throwing);
      await library.loadFoods();
      await library.loadFoodGroups();
      throwing.throwOnGroups = true;
      repository = throwing;

      expect(
        await handlerFor(library).handle(WatchTransportRequest.routines),
        isTrue,
        reason: 'S-8316 a storage failure on the categories does not fail the '
            'request',
      );

      final frame = transport.ofType('foods_down').single;
      expect(
        objectsOf(asObject(frame['payload'])['categories']),
        isEmpty,
        reason: 'S-8316 the group cache a failed load leaves behind is empty',
      );
      final rows = objectsOf(asObject(frame['payload'])['foods']);
      expect(
        [for (final row in rows) row['foodId']],
        ['food-f'],
        reason: 'S-8316 the foods still travel',
      );
      expect(
        [for (final row in rows) row['categoryId']],
        everyElement(isNull),
        reason: 'S-8316 a food whose category the phone cannot name carries '
            'none, which is a valid row rather than a dropped one',
      );
      expect(
        loadProtocolValidator().validateEnvelope(frame),
        isEmpty,
        reason: 'S-8316 the frame validates',
      );
    });
  });

  group('S-87a-6…S-87a-13 the bests close every answer', () {
    /// The `generatedAt` of the one `routines_down` frame sent so far — the
    /// stamp the wrist names back as its `since`.
    DateTime sentStamp() => parseUtcIso(
      asObject(
        transport.ofType('routines_down').single['payload'],
      )['generatedAt'],
    );

    /// The entries of the one `bests_down` frame sent so far.
    List<Map<String, Object?>> sentBests() => objectsOf(
      asObject(transport.ofType('bests_down').single['payload'])['bests'],
    );

    test('S-87a-6 a since-current request is answered with none of the three '
        'bundle frames and exactly one bests_down', () async {
      await handler.handle(WatchTransportRequest.routines);
      final stamp = sentStamp();

      transport.sent.clear();

      expect(
        await handler.handle(
          WatchTransportRequest.routines,
          since: stamp,
          exercisesVersion: await currentVersion(),
        ),
        isTrue,
        reason: 'S-87a-6 the wrist asked, so the phone answered',
      );

      for (final type in [
        'preferences_down',
        'foods_down',
        'routines_down',
      ]) {
        expect(
          transport.ofType(type),
          isEmpty,
          reason: 'S-87a-6 the wrist holds the current bundle, so $type stays '
              'put',
        );
      }
      expect(
        transport.ofType('exercises_down'),
        isEmpty,
        reason: 'S-87a-6 the wrist holds the current list, so no batch '
            'travels',
      );
      expect(
        transport.types,
        ['bests_down'],
        reason:
            'S-87a-6 bests change after every completed workout, so they '
            'travel on every request whatever `since` says (D-4)',
      );
    });

    test('S-87a-7 a bests frame the radio refuses leaves the batches and the '
        'answer as they were', () async {
      transport.undeliveredBests = true;

      expect(await handler.handle(WatchTransportRequest.routines), isTrue);

      expect(
        transport.types.take(3),
        ['preferences_down', 'foods_down', 'routines_down'],
        reason: 'S-87a-7 the bundle is untouched by the refused frame',
      );
      expect(
        transport.batchIndices,
        [0, 1, 2],
        reason: 'S-87a-7 a refused bests frame is not a reason to hold back '
            'the exercise list',
      );
      expect(
        transport.ofType('bests_down'),
        hasLength(1),
        reason: 'S-87a-7 the bests were attempted once, after everything else',
      );
      expect(
        transport.types.last,
        'bests_down',
        reason: 'S-87a-7 the bests are the last frame of every answer (D-11)',
      );
    });

    test('S-87a-8 a workout completed between two requests changes the next '
        'frame', () async {
      const exerciseId = 'exercise-bench-press';
      await _seedCompletedSetSession(
        repository,
        sessionId: 'session-first',
        exerciseId: exerciseId,
        reps: 5,
        weight: 100,
      );

      expect(await handler.handle(WatchTransportRequest.routines), isTrue);
      final first = sentBests().single;
      expect(
        first['e1rmKg'],
        StatsProgressService.epley1RM(100.0, 5),
        reason: 'S-87a-8 the first frame holds the history as it stands',
      );

      await _seedCompletedSetSession(
        repository,
        sessionId: 'session-better',
        exerciseId: exerciseId,
        reps: 5,
        weight: 120,
      );
      current = _now.add(const Duration(minutes: 5));
      transport.sent.clear();

      expect(await handler.handle(WatchTransportRequest.routines), isTrue);
      final second = sentBests().single;
      expect(
        second['e1rmKg'],
        StatsProgressService.epley1RM(120.0, 5),
        reason:
            'S-87a-8 the frame is built from storage read at request time, so '
            'a workout completed between two requests reaches the wrist',
      );
      expect(
        second['e1rmKg'],
        isNot(first['e1rmKg']),
        reason: 'S-87a-8 a held StatsProgressService would have served the '
            'bests of the first request',
      );
    });

    test('S-87a-11 the sent frame validates, with and without history',
        () async {
      expect(await handler.handle(WatchTransportRequest.routines), isTrue);

      final emptyHistory = transport.ofType('bests_down').single;
      expect(
        loadProtocolValidator().validateEnvelope(
          (jsonDecode(jsonEncode(emptyHistory)) as Map)
              .cast<String, Object?>(),
        ),
        isEmpty,
        reason: 'S-87a-11 an empty-history frame is one the protocol admits',
      );

      await _seedCompletedSetSession(
        repository,
        sessionId: 'session-valid',
        exerciseId: 'exercise-bench-press',
        reps: 5,
        weight: 100,
      );
      transport.sent.clear();

      expect(await handler.handle(WatchTransportRequest.routines), isTrue);
      final frame = transport.ofType('bests_down').single;
      expect(
        objectsOf(asObject(frame['payload'])['bests']),
        isNotEmpty,
        reason: 'S-87a-11 the second frame carries the new history',
      );
      expect(
        loadProtocolValidator().validateEnvelope(
          (jsonDecode(jsonEncode(frame)) as Map).cast<String, Object?>(),
        ),
        isEmpty,
        reason: 'S-87a-11 the sender and the contract cannot drift',
      );
    });

    test('S-87a-12 each frame is stamped with that request\'s own clock',
        () async {
      final start = _now;

      expect(await handler.handle(WatchTransportRequest.routines), isTrue);
      expect(
        asObject(
          transport.ofType('bests_down').single['payload'],
        )['generatedAt'],
        utcIso(start),
        reason: 'S-87a-12 the first frame is stamped with the phone\'s clock',
      );

      current = start.add(const Duration(minutes: 3));
      transport.sent.clear();

      expect(await handler.handle(WatchTransportRequest.routines), isTrue);
      expect(
        asObject(
          transport.ofType('bests_down').single['payload'],
        )['generatedAt'],
        utcIso(current),
        reason:
            'S-87a-12 not a stored bundle stamp: the second request carries '
            'its own clock reading',
      );
      expect(
        asObject(
          transport.ofType('routines_down').single['payload'],
        )['generatedAt'],
        utcIso(start),
        reason:
            'S-87a-12 the bundle keeps its stamp while its content stands '
            'still, so bests are not part of the bundle',
      );
    });

    test('S-87a-13 no completed sessions reaches the wrist as an empty array',
        () async {
      expect(await handler.handle(WatchTransportRequest.routines), isTrue);

      final frames = transport.ofType('bests_down');
      expect(
        frames,
        hasLength(1),
        reason: 'S-87a-13 the frame travels even when the phone has no history',
      );
      expect(
        asObject(frames.single['payload'])['bests'],
        isEmpty,
        reason:
            'S-87a-13 an empty array is "no history"; a missing frame would '
            'leave the wrist unable to tell',
      );
    });
  });

  group('S-87c-1…S-87c-14 the bests are sent only when they moved', () {
    late RevisionedRepository repo;

    /// The wrist's raise, as the wiring hands it on: the flag is the wrist's
    /// own claim that it holds a bests frame (D-2).
    Future<bool> raise({required bool holdsBests}) => handler.handle(
      WatchTransportRequest.routines,
      holdsBests: holdsBests,
    );

    /// The entry of [exerciseId] in the one `bests_down` frame sent so far.
    Map<String, Object?> bestEntry(String exerciseId) => objectsOf(
      asObject(transport.ofType('bests_down').single['payload'])['bests'],
    ).singleWhere((entry) => entry['exerciseId'] == exerciseId);

    setUp(() async {
      repo = RevisionedRepository();
      await repo.initialize();
      repository = repo;
      handler = handlerFor(FoodLibraryState(repository));
    });

    test('S-87c-1 a wrist holding the bests, raising again at the same '
        'revision, is sent none and reads no history', () async {
      await _seedHistory(repo);
      repo.history = 5;

      expect(await raise(holdsBests: true), isTrue);
      expect(
        transport.ofType('bests_down'),
        hasLength(1),
        reason: 'S-87c-1 a wrist that holds nothing is sent the frame',
      );
      expect(
        bestEntry('exercise-bench-press')['e1rmKg'],
        StatsProgressService.epley1RM(100.0, 5),
        reason: 'S-87c-1 100 × 5 is the standing best of the two 100 kg sets',
      );
      expect(
        repo.sessionReads,
        greaterThan(0),
        reason: 'S-87c-1 the first answer walks the history',
      );

      transport.sent.clear();
      repo.resetCounts();

      expect(await raise(holdsBests: true), isTrue);

      expect(
        transport.ofType('bests_down'),
        isEmpty,
        reason: 'S-87c-1 the wrist holds the bests and the revision stands '
            'still, so no frame travels',
      );
      expect(
        repo.sessionReads,
        0,
        reason: 'S-87c-1 the skip reads no history: no StatsProgressService '
            'is even created',
      );
    });

    test('S-87c-2 a completed workout reaches the next request, then goes '
        'quiet', () async {
      await _seedHistory(repo);
      repo.history = 5;

      expect(await raise(holdsBests: true), isTrue);
      expect(
        bestEntry('exercise-bench-press')['e1rmKg'],
        StatsProgressService.epley1RM(100.0, 5),
      );

      await _seedCompletedSetSession(
        repo,
        sessionId: 'session-4',
        exerciseId: 'exercise-bench-press',
        reps: 5,
        weight: 120,
      );
      repo.history = 6;
      current = _now.add(const Duration(minutes: 5));
      transport.sent.clear();

      expect(await raise(holdsBests: true), isTrue);
      expect(
        transport.ofType('bests_down'),
        hasLength(1),
        reason: 'S-87c-2 a completed workout moves the revision, so the next '
            'request walks and sends',
      );
      expect(
        bestEntry('exercise-bench-press')['e1rmKg'],
        StatsProgressService.epley1RM(120.0, 5),
        reason: 'S-87c-2 the frame holds the new best',
      );

      transport.sent.clear();
      repo.resetCounts();

      expect(await raise(holdsBests: true), isTrue);
      expect(
        transport.ofType('bests_down'),
        isEmpty,
        reason: 'S-87c-2 request 3 at the delivered revision sends nothing',
      );
      expect(
        repo.sessionReads,
        0,
        reason: 'S-87c-2 and reads nothing',
      );
    });

    test('S-87c-3 a write that leaves the bests identical costs one walk and '
        'no frame', () async {
      await _seedHistory(repo);
      repo.history = 5;

      expect(await raise(holdsBests: true), isTrue);

      // An in-progress set: a write, but the bests cannot move.
      await _seedSet(
        repo,
        sessionId: 'session-3',
        orderIndex: 1,
        exerciseId: 'exercise-bench-press',
        reps: 3,
        weight: 200,
      );
      repo.history = 6;
      current = _now.add(const Duration(minutes: 1));
      transport.sent.clear();
      repo.resetCounts();

      expect(await raise(holdsBests: true), isTrue);

      expect(
        repo.sessionReads,
        greaterThan(0),
        reason: 'S-87c-3 a moved revision walks once',
      );
      expect(
        transport.ofType('bests_down'),
        isEmpty,
        reason: 'S-87c-3 the walk found the same entries, so no frame travels',
      );

      transport.sent.clear();
      repo.resetCounts();

      expect(await raise(holdsBests: true), isTrue);
      expect(
        transport.ofType('bests_down'),
        isEmpty,
        reason: 'S-87c-3 the entries still stand still',
      );
      expect(
        repo.sessionReads,
        0,
        reason: 'S-87c-3 the walk\'s revision was remembered, so the third '
            'request reads nothing (A-87c-2)',
      );
    });

    test('S-87c-4 a request that does not say the wrist holds the bests sends '
        'the frame every time', () async {
      await _seedHistory(repo);
      repo.history = 5;

      // The key's spellings — absent, `false`, `"true"`, `1`, null — all
      // reach the handler as false: D-2's parse is what `holdsBestsOf` does,
      // and S-87c-9 pins it in `test/watch_transport_test.dart`.
      for (var request = 1; request <= 2; request++) {
        transport.sent.clear();
        repo.resetCounts();

        expect(await raise(holdsBests: false), isTrue);
        expect(
          transport.ofType('bests_down'),
          hasLength(1),
          reason: 'S-87c-4 request $request: an older wrist, or one that lost '
              'its copy, is sent the frame as today (D-5(a)), even at an '
              'unchanged revision',
        );
        expect(
          repo.sessionReads,
          greaterThan(0),
          reason: 'S-87c-4 request $request walks the history',
        );
      }
    });

    test('S-87c-5 a frame the radio did not carry is sent again, and after a '
        'delivered one the next request skips it', () async {
      await _seedHistory(repo);
      repo.history = 5;
      transport.bestsDelivery = WatchDelivery.undelivered;

      expect(await raise(holdsBests: true), isTrue);
      expect(
        transport.ofType('bests_down'),
        hasLength(1),
        reason: 'S-87c-5 the frame was built and attempted',
      );

      transport.sent.clear();
      transport.bestsDelivery = null;
      repo.resetCounts();

      expect(await raise(holdsBests: true), isTrue);
      expect(
        transport.ofType('bests_down'),
        hasLength(1),
        reason: 'S-87c-5 nothing was remembered for an undelivered frame, so '
            'it is built and sent again',
      );
      expect(repo.sessionReads, greaterThan(0), reason: 'S-87c-5 and walked');

      transport.sent.clear();
      repo.resetCounts();

      expect(await raise(holdsBests: true), isTrue);
      expect(
        transport.ofType('bests_down'),
        isEmpty,
        reason: 'S-87c-5 the second answer was delivered, so the third '
            'request skips',
      );
      expect(repo.sessionReads, 0, reason: 'S-87c-5 and reads nothing');
    });

    test('S-87c-5 a queued frame is not delivered, so the next request sends '
        'it again', () async {
      await _seedHistory(repo);
      repo.history = 5;
      transport.bestsDelivery = WatchDelivery.queued;

      expect(await raise(holdsBests: true), isTrue);
      expect(transport.ofType('bests_down'), hasLength(1));

      transport.sent.clear();
      transport.bestsDelivery = null;
      repo.resetCounts();

      expect(await raise(holdsBests: true), isTrue);
      expect(
        transport.ofType('bests_down'),
        hasLength(1),
        reason: 'S-87c-5 `queued` is not delivered (D-5(d), q-g), so nothing '
            'is remembered and the frame travels again',
      );
      expect(repo.sessionReads, greaterThan(0), reason: 'S-87c-5 and walked');
    });

    test('S-87c-6 a phone that relaunched sends the frame once', () async {
      await _seedHistory(repo);
      repo.history = 5;

      expect(await raise(holdsBests: true), isTrue);
      transport.sent.clear();

      // A relaunch: a new handler over the same storage, at the same revision.
      handler = handlerFor(FoodLibraryState(repository));

      expect(await raise(holdsBests: true), isTrue);
      expect(
        transport.ofType('bests_down'),
        hasLength(1),
        reason: 'S-87c-6 a handler holding nothing cannot know the wrist '
            'holds the current bests, so it sends them once',
      );

      transport.sent.clear();
      repo.resetCounts();

      expect(await raise(holdsBests: true), isTrue);
      expect(transport.ofType('bests_down'), isEmpty);
      expect(repo.sessionReads, 0);
    });

    test('S-87c-7 a repository that cannot tell the revision walks every '
        'request and sends only when the entries moved', () async {
      await _seedHistory(repo);
      repo.history = null;

      expect(await raise(holdsBests: true), isTrue);
      expect(transport.ofType('bests_down'), hasLength(1));

      transport.sent.clear();
      repo.resetCounts();
      // The stamp moves; the entries do not (87c, A-87c-1): `generatedAt` must
      // stay out of the compared text.
      current = _now.add(const Duration(minutes: 1));

      expect(await raise(holdsBests: true), isTrue);
      expect(
        repo.sessionReads,
        greaterThan(0),
        reason: 'S-87c-7 with no revision the phone cannot skip the walk',
      );
      expect(
        transport.ofType('bests_down'),
        isEmpty,
        reason: 'S-87c-7 the entries text is unchanged, so no frame travels — '
            'the only guard a null revision leaves',
      );

      await _seedCompletedSetSession(
        repo,
        sessionId: 'session-5',
        exerciseId: 'exercise-bench-press',
        reps: 5,
        weight: 130,
      );
      transport.sent.clear();
      repo.resetCounts();

      expect(await raise(holdsBests: true), isTrue);
      expect(
        transport.ofType('bests_down'),
        hasLength(1),
        reason: 'S-87c-7 a new best changes the entries text, so the frame '
            'travels',
      );
      expect(
        bestEntry('exercise-bench-press')['e1rmKg'],
        StatsProgressService.epley1RM(130.0, 5),
      );
    });

    test('S-87c-12 a write that lands during the walk is not hidden', () async {
      await _seedHistory(repo);
      repo.history = 5;
      // `getAllSessions` bumps the revision, so every walk is also a write —
      // the case the read-before-walk rule protects against.
      repo.bumpHistoryOnRead = true;

      expect(await raise(holdsBests: true), isTrue);
      expect(
        transport.ofType('bests_down'),
        hasLength(1),
        reason: 'S-87c-12 request 1 walks and sends',
      );

      await _seedCompletedSetSession(
        repo,
        sessionId: 'session-6',
        exerciseId: 'exercise-bench-press',
        reps: 5,
        weight: 110,
      );
      transport.sent.clear();
      repo.resetCounts();

      expect(await raise(holdsBests: true), isTrue);
      expect(
        transport.ofType('bests_down'),
        hasLength(1),
        reason: 'S-87c-12 the revision read at the start is older than the '
            'history, so request 2 walks and sends the new best',
      );
      expect(
        bestEntry('exercise-bench-press')['e1rmKg'],
        StatsProgressService.epley1RM(110.0, 5),
      );

      transport.sent.clear();
      repo.resetCounts();

      expect(await raise(holdsBests: true), isTrue);
      expect(
        repo.sessionReads,
        greaterThan(0),
        reason: 'S-87c-12 request 3 walks again: the remembered revision is '
            'the one read before request 2\'s walk, and the history has '
            'moved since',
      );
      expect(
        transport.ofType('bests_down'),
        isEmpty,
        reason: 'S-87c-12 the entries stand still, so the walk sends nothing',
      );
    });

    test('S-87c-13 an undelivered frame is re-sent, then the wrist goes '
        'quiet', () async {
      await _seedHistory(repo);
      repo.history = 5;
      transport.bestsDelivery = WatchDelivery.undelivered;

      expect(await raise(holdsBests: true), isTrue);
      transport.bestsDelivery = null;

      expect(await raise(holdsBests: true), isTrue);
      expect(
        transport.ofType('bests_down'),
        hasLength(2),
        reason: 'S-87c-13 the undelivered frame was not remembered, so the '
            'next request built and sent it again',
      );

      transport.sent.clear();
      repo.resetCounts();

      expect(await raise(holdsBests: true), isTrue);
      expect(
        transport.ofType('bests_down'),
        isEmpty,
        reason: 'S-87c-13 the delivered frame is remembered, so request 3 '
            'sends nothing',
      );
      expect(
        repo.sessionReads,
        0,
        reason: 'S-87c-13 and reads nothing',
      );
    });

    test('S-87c-14 a request without the flag always sends, even with '
        'remembered state', () async {
      await _seedHistory(repo);
      repo.history = 5;

      expect(await raise(holdsBests: true), isTrue);

      // The key absent, `false`, and `"true"` (a string) all arrive as false:
      // D-2's parse is `holdsBestsOf`, pinned by S-87c-9.
      for (final variant in ['absent', 'false', 'a string']) {
        transport.sent.clear();
        repo.resetCounts();

        expect(await raise(holdsBests: false), isTrue);
        expect(
          transport.ofType('bests_down'),
          hasLength(1),
          reason: 'S-87c-14 the $variant request walks and sends even though '
              'the handler remembers a delivered frame (D-5(a))',
        );
        expect(repo.sessionReads, greaterThan(0), reason: 'S-87c-14 and walked');
      }

      transport.sent.clear();
      repo.resetCounts();

      expect(await raise(holdsBests: true), isTrue);
      expect(
        transport.ofType('bests_down'),
        isEmpty,
        reason: 'S-87c-14 each delivery refreshed the remembered pair, so a '
            'holds request still skips',
      );
      expect(repo.sessionReads, 0);
    });
  });

  group('S-94a-21…S-94a-25 the water count rides an answer that asks', () {
    // Shared fixture W (plan 94, D-16): the phone's local 2026-11-01, asked at
    // local noon; the day string and dateMs derive from the same local date.
    final day = DateTime(2026, 11, 1);
    final dayMs = day.millisecondsSinceEpoch;
    final dayText =
        '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';

    /// The payload of the one `water_down` frame sent so far.
    Map<String, Object?> waterPayload() =>
        asObject(transport.ofType('water_down').single['payload']);

    setUp(() async {
      current = DateTime(2026, 11, 1, 12).toUtc();
      // D at 600 ml with the ledger ["w-1"]: 350 ml, then one wrist add.
      await repository.saveWaterVolumeForDate(dayMs, 350);
      expect(
        await repository.applyWaterTap(
          dateMs: dayMs,
          tapId: 'w-1',
          deltaMl: kWaterGlassMl,
        ),
        isTrue,
      );
      expect(await repository.getWaterVolumeForDate(dayMs), 600);
    });

    test('S-94a-21 a wrist that asks gets the count on every request, after '
        'the batches and before the bests', () async {
      final validator = loadProtocolValidator();

      expect(
        await handler.handle(WatchTransportRequest.routines, wantsWater: true),
        isTrue,
      );
      expect(transport.ofType('water_down'), hasLength(1));
      expect(waterPayload()['day'], dayText);
      expect(waterPayload()['glasses'], 2, reason: 'S-94a-21 600 ~/ 250 = 2');
      expect(waterPayload()['appliedTapIds'], ['w-1']);
      expect(
        validator.validateEnvelope(transport.ofType('water_down').single),
        isEmpty,
      );

      final types = transport.types;
      final lastBatch = types.lastIndexOf('exercises_down');
      expect(lastBatch, greaterThanOrEqualTo(0));
      expect(
        types.indexOf('water_down'),
        lastBatch + 1,
        reason: 'S-94a-21 the count comes right after the last exercise batch',
      );
      expect(
        types.last,
        'bests_down',
        reason: 'S-94a-21 the bests stay the last frame (87a D-11)',
      );
      expect(types.indexOf('bests_down'), types.indexOf('water_down') + 1);

      final stamp = parseUtcIso(
        asObject(
          transport.ofType('routines_down').single['payload'],
        )['generatedAt'],
      );
      final version = await currentVersion();
      transport.sent.clear();

      expect(
        await handler.handle(
          WatchTransportRequest.routines,
          since: stamp,
          exercisesVersion: version,
          holdsBests: true,
          wantsWater: true,
        ),
        isTrue,
      );
      expect(
        transport.types,
        ['water_down'],
        reason: 'S-94a-21 no bundle, no batches, no bests — and still the one '
            'count, whatever since, the version and the bests decided',
      );
      expect(waterPayload()['day'], dayText);
      expect(waterPayload()['glasses'], 2);
      expect(waterPayload()['appliedTapIds'], ['w-1']);
      expect(
        validator.validateEnvelope(transport.ofType('water_down').single),
        isEmpty,
      );
    });

    test('S-94a-22 a wrist that does not ask gets none', () async {
      final notAsked = <Map<String, Object?>>[
        const {'request': 'routines'},
        const {'request': 'routines', 'wantsWater': false},
        const {'request': 'routines', 'wantsWater': 'true'},
        const {'request': 'routines', 'wantsWater': 1},
        const {'request': 'routines', 'wantsWater': null},
      ];
      for (final frame in notAsked) {
        transport.sent.clear();
        expect(
          await handler.handle(
            WatchTransportRequest.routines,
            wantsWater: WatchTransportRequest.wantsWaterOf(frame),
          ),
          isTrue,
        );
        expect(
          transport.ofType('water_down'),
          isEmpty,
          reason: 'S-94a-22 $frame did not ask, so no count travels',
        );
        expect(transport.types.last, 'bests_down');
      }

      transport.sent.clear();
      expect(await handler.handle(WatchTransportRequest.routines), isTrue);
      expect(
        transport.ofType('water_down'),
        isEmpty,
        reason: 'S-94a-22 a caller that passes nothing is not asking',
      );
    });

    test('S-94a-23 no foods, no routines, still a count', () async {
      repository = MockWorkoutRepository();
      await repository.initialize();
      handler = handlerFor(FoodLibraryState(repository));
      expect(await repository.getFoods(includeArchived: true), isEmpty);
      expect(await repository.getTemplates(), isEmpty);
      expect(await repository.getWaterVolumeForDate(dayMs), 0);

      expect(
        await handler.handle(WatchTransportRequest.routines, wantsWater: true),
        isTrue,
      );
      expect(transport.ofType('water_down'), hasLength(1));
      expect(waterPayload()['day'], dayText);
      expect(waterPayload()['glasses'], 0);
      expect(waterPayload()['appliedTapIds'], isEmpty);
      expect(
        loadProtocolValidator().validateEnvelope(
          transport.ofType('water_down').single,
        ),
        isEmpty,
      );
    });

    test("S-94a-24 the frame is the phone's own number", () async {
      expect(
        await handler.handle(WatchTransportRequest.routines, wantsWater: true),
        isTrue,
      );
      final frame = transport.ofType('water_down').single;

      final nutrition = NutritionState(repository);
      await nutrition.loadWaterForDate(dayMs);
      expect(nutrition.waterTodayGlasses, 2);
      expect(
        waterPayload()['glasses'],
        nutrition.waterTodayGlasses,
        reason: 'S-94a-24 the wrist is told the number the phone shows',
      );
      expect(
        frame['messageId'],
        'msg-water-${current.millisecondsSinceEpoch}-2-1',
      );
    });

    test('S-94a-24 only water_constants.dart turns milliliters into glasses '
        '(code lines; comments may name the rule)', () {
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final codeLines = entity.readAsLinesSync().where(
          (line) => !line.trimLeft().startsWith('//'),
        );
        if (codeLines.any((line) => line.contains('~/ kWaterGlassMl'))) {
          offenders.add(entity.path.replaceAll(r'\', '/'));
        }
      }
      expect(
        offenders,
        ['lib/core/constants/water_constants.dart'],
        reason: 'S-94a-24 waterGlassesFor is the one owner of the glass count '
            '(D-11)',
      );
    });

    test('S-94a-25 a count the radio did not carry leaves the bests and the '
        'answer as they were', () async {
      transport.undeliveredWater = true;

      expect(
        await handler.handle(WatchTransportRequest.routines, wantsWater: true),
        isTrue,
      );
      expect(transport.ofType('water_down'), hasLength(1));
      expect(
        transport.types.last,
        'bests_down',
        reason: 'S-94a-25 the bests still go out after the refused count',
      );
      expect(transport.types.indexOf('bests_down'),
          transport.types.indexOf('water_down') + 1);
    });

    test('S-94a-25 a water read that throws sends no count and the rest of the '
        'answer as if nobody asked', () async {
      final throwing = _ThrowingWaterRepository();
      await throwing.initialize();
      repository = throwing;

      transport = _RecordingTransport();
      handler = handlerFor(FoodLibraryState(repository));
      expect(
        await handler.handle(WatchTransportRequest.routines, wantsWater: true),
        isTrue,
      );
      final asked = transport.sent;
      expect(
        asked.where((frame) => frame['type'] == 'water_down'),
        isEmpty,
        reason: 'S-94a-25 a read that throws sends no frame',
      );

      transport = _RecordingTransport();
      handler = handlerFor(FoodLibraryState(repository));
      expect(await handler.handle(WatchTransportRequest.routines), isTrue);

      expect(
        jsonEncode(asked),
        jsonEncode(transport.sent),
        reason: 'S-94a-25 the rest of the answer is the one a wrist that did '
            'not ask gets',
      );
    });
  });
}
