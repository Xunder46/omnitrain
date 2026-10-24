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
//   S-7104 a phone with no foods sends no foods frame → `S-7104 ...`
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
// The transport here is a recorder, not the graph: this file is about what the
// handler sends, and in what order. That the graph's inbound handler hands the
// frame's version on is S-3855 in `test/watch_session_projection_test.dart`.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/platform/watch_delivery.dart';
import 'package:omnitrain/core/platform/watch_transport.dart';
import 'package:omnitrain/core/utils/watch_reference_sync.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/food_library_state.dart';
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

  /// Whether the radio refuses the `foods_down` frame (S-7105).
  bool undeliveredFoods = false;

  @override
  Future<WatchDelivery> send(Map<String, Object?> envelope) async {
    sent.add(envelope);
    if (envelope['type'] == 'foods_down' && undeliveredFoods) {
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

void main() {
  late MockWorkoutRepository repository;
  late SettingsState settings;
  late _RecordingTransport transport;
  late WatchSyncRequestHandler handler;

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
        clock: () => _now,
      );

  setUp(() async {
    repository = MockWorkoutRepository();
    await repository.initialize();
    settings = SettingsState(repository, fakePreferencesService());
    transport = _RecordingTransport();
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
        everyElement('exercises_down'),
        reason: 'S-7101 only the exercise batches follow the food list',
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
        ['preferences_down', 'foods_down', 'routines_down'],
        reason:
            'S-7103 the version early return sits after the foods and the '
            'routines, so the foods still travel and no exercise batch does',
      );
    });

    test('S-7104 a phone with no foods sends no foods frame and still sends '
        'the rest', () async {
      expect(await handler.handle(WatchTransportRequest.routines), isTrue);

      expect(
        transport.ofType('foods_down'),
        isEmpty,
        reason: 'S-7104 an empty food list is not a message to send (D-2)',
      );
      expect(
        transport.types.take(2),
        ['preferences_down', 'routines_down'],
        reason: 'S-7104 the rest of the answer still travels',
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
}
