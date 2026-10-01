// The phone's half of a nutrition quick-log: what the wrist logged, in the
// phone's own day log.
//
// Plan: `docs/plans/2026-07-13-12-e-watch-nutrition-quick-log-plan.md`,
// scenario S-002.
//
// The wrist sends an observation, not a consumed-food row: what it knows is a
// food id and a portion, and the phone owns everything else about the food. The
// bridge therefore looks the food up in the phone's own library and writes
// through the phone's normal log path, which already keeps one row per food per
// day — so a redelivered message updates the row it made the first time instead
// of recording a second meal.

library;

import 'package:uuid/uuid.dart';

import '../../core/sync_protocol/message_validator.dart';
import '../../core/sync_protocol/phone_envelope.dart';
import '../../data/models/models.dart';
import '../../watch/session/watch_records.dart';
import '../food_library_state.dart';
import '../nutrition_state.dart';
import 'live_session_mirror_state.dart';

/// What [WatchNutritionLogBridge.receive] did with a message.
enum WatchNutritionLogOutcome {
  /// The message's quick-logs are in the phone's day log.
  applied,

  /// Conformant, and nothing this bridge logs: another surface's news, or a
  /// message that named no food.
  ignored,

  /// This build could not read the message. Nothing was logged.
  refused,
}

/// What one message did to the phone's day log.
class WatchNutritionLogResult {
  const WatchNutritionLogResult({
    required this.outcome,
    this.loggedFoodIds = const [],
    this.unplacedFoodIds = const [],
    this.acknowledgedEntryIds = const [],
  });

  final WatchNutritionLogOutcome outcome;

  /// The foods this message left in the day log, in the order it named them.
  final List<String> loggedFoodIds;

  /// Named by the message and missing from the day log: the library no longer
  /// holds the food, or the portion was not a number. Reported rather than
  /// guessed at — with no food there are no macros to freeze onto a row.
  final List<String> unplacedFoodIds;

  /// The observations this message asked the phone to take responsibility for,
  /// whether or not a row came of them. What the receipt names.
  final List<String> acknowledgedEntryIds;
}

/// Turns the wrist's quick-logs into the phone's consumed-food rows.
class WatchNutritionLogBridge {
  WatchNutritionLogBridge({
    required NutritionState nutrition,
    required FoodLibraryState library,
    SyncProtocolValidator? validator,
    WatchMirrorTransport? transport,
    DateTime Function()? clock,
    String Function()? idFactory,
  }) : _nutrition = nutrition,
       _library = library,
       _validator = validator,
       _transport = transport,
       _clock = clock ?? _utcNow,
       _newId = idFactory ?? _uuid;

  static DateTime _utcNow() => DateTime.now().toUtc();

  static const Uuid _uuidV4 = Uuid();

  static String _uuid() => _uuidV4.v4();

  final NutritionState _nutrition;
  final FoodLibraryState _library;
  final SyncProtocolValidator? _validator;

  /// Where the receipt goes. Null in a test that only cares what was logged;
  /// a bridge with nowhere to answer still applies the message, it just leaves
  /// the wrist owing it.
  final WatchMirrorTransport? _transport;

  final DateTime Function() _clock;
  final String Function() _newId;

  /// The phone's acknowledgement of the observations a message carried, in the
  /// shape the protocol pins.
  ///
  /// Not tied to any session: a quick-log taken with no workout running names a
  /// session the phone does not hold, so the snapshot — the other way the watch
  /// learns an entry arrived — can never carry it back.
  static Map<String, Object?> receiptFor({
    required List<String> entryIds,
    required DateTime sentAt,
    required String messageId,
  }) => phoneEnvelope(
    type: 'receipt',
    messageId: messageId,
    sentAt: sentAt,
    payload: {'entryIds': entryIds},
  );

  /// Applies every nutrition quick-log in [envelope] and reports what landed.
  ///
  /// Idempotent by the phone's own rule rather than by a ledger of its own: one
  /// row per food per day means a message that arrives twice leaves one entry
  /// (S-002).
  Future<WatchNutritionLogResult> receive(Map<String, Object?> envelope) async {
    final decision = SyncProtocolValidator.evaluateOrAccept(
      _validator,
      envelope,
    );
    if (!decision.accepted) {
      return const WatchNutritionLogResult(
        outcome: WatchNutritionLogOutcome.refused,
      );
    }

    final events = _quickLogs(envelope);
    if (events.isEmpty) {
      return const WatchNutritionLogResult(
        outcome: WatchNutritionLogOutcome.ignored,
      );
    }

    final logged = <String>[];
    final unplaced = <String>[];
    // Every quick-log the phone has now seen, resolvable or not: a row nothing
    // can resolve is not a row worth the wrist re-sending forever, and the
    // bridge reports what it could not place rather than going silent about it.
    final acknowledged = <String>[];
    for (final event in events) {
      if (event['entryId'] case final String entryId) acknowledged.add(entryId);

      final foodId = event['foodId'];
      if (foodId is! String) continue;
      final food = _foodById(foodId);
      final servings = event['servings'];
      if (food == null || servings is! num) {
        unplaced.add(foodId);
        continue;
      }
      // The portion travels in servings of the food's own reference amount, and
      // the day log counts in the food's own unit.
      final rowId = await _nutrition.logConsumedFoodAt(
        food,
        servings * food.referenceAmount,
      );
      if (rowId == null) {
        unplaced.add(foodId);
        continue;
      }
      logged.add(foodId);
    }

    await _acknowledge(acknowledged);

    return WatchNutritionLogResult(
      outcome: logged.isEmpty
          ? WatchNutritionLogOutcome.ignored
          : WatchNutritionLogOutcome.applied,
      loggedFoodIds: logged,
      unplacedFoodIds: unplaced,
      acknowledgedEntryIds: acknowledged,
    );
  }

  /// Tells the wrist which observations the phone has taken on.
  ///
  /// Sent even when nothing could be logged, because what a receipt asserts is
  /// "the phone has this", not "the day log changed".
  Future<void> _acknowledge(List<String> entryIds) async {
    final transport = _transport;
    if (transport == null || entryIds.isEmpty) return;

    await transport.send(
      receiptFor(entryIds: entryIds, sentAt: _clock(), messageId: _newId()),
    );
  }

  /// The quick-log events in [envelope], and nothing else: sets, holds and
  /// rounds travel as session entries, and the session is not this bridge's.
  List<Map<String, Object?>> _quickLogs(Map<String, Object?> envelope) {
    if (envelope['type'] != 'observations_up') return const [];
    final payload = envelope['payload'];
    if (payload is! Map) return const [];
    final events = payload['events'];
    if (events is! List) return const [];

    return [
      for (final event in events)
        if (event is Map &&
            event['kind'] == WatchObservationKind.nutritionQuickLog)
          event.cast<String, Object?>(),
    ];
  }

  Food? _foodById(String foodId) {
    for (final food in _library.foods) {
      if (food.id == foodId) return food;
    }
    return null;
  }
}
