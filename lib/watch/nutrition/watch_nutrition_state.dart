/// The quick-log screen's state: the synced food list, the food and portion the
/// user has picked, and the observation that comes out of confirming them.
///
/// Plan: `docs/plans/2026-07-13-12-e-watch-nutrition-quick-log-plan.md`,
/// scenarios S-001 to S-006.
///
/// Everything the screen shows is derived — the list from the synced catalog
/// and the wrist's own log, the calories from the portion — and the only thing
/// held in memory is an edit the user has made but not yet confirmed, which is
/// not data yet: a kill mid-turn costs a turn, never a food. Confirming goes
/// straight to the engine's `logNutrition`, so the event, its storage and its
/// message are the item-6 path with nothing translated in between.
///
/// Nothing here needs a session: eating is not a training event, and the surface
/// is reachable with no workout running (S-006).
library;

import '../../core/sync_protocol/message_validator.dart';
import '../session/watch_records.dart';
import '../session/watch_session_engine.dart';
import '../session/watch_session_store.dart';
import 'watch_food_catalog.dart';

/// The portion control's detents and bounds, in servings.
///
/// The values are not the wrist's to choose — `watch/contract/watch_nutrition_contract.json`
/// carries them and both clients' suites assert against it, so the two watch
/// clients cannot disagree about what a detent is worth.
abstract final class WatchNutritionPortion {
  static const double stepServings = 0.5;
  static const double minServings = 0.5;
  static const double maxServings = 10;
}

/// What happened to a `foods_down` message.
class WatchFoodsDownResult {
  const WatchFoodsDownResult({required this.decision, required this.applied});

  /// The receiver's verdict on the message, in the shape the protocol defines.
  final SyncMessageDecision decision;

  /// True when this message became the list the wrist reads. A conformant
  /// message older than the cached one is understood and dropped, so it is
  /// false without being a rejection.
  final bool applied;
}

class WatchNutritionState {
  WatchNutritionState({
    required WatchSessionEngine engine,
    required WatchSessionStore store,
    SyncProtocolValidator? validator,
    DateTime Function()? clock,
  }) : _engine = engine,
       _store = store,
       _validator = validator,
       _clock = clock ?? _utcNow;

  static DateTime _utcNow() => DateTime.now().toUtc();

  final WatchSessionEngine _engine;
  final WatchSessionStore _store;
  final SyncProtocolValidator? _validator;
  final DateTime Function() _clock;

  WatchFoodCatalogRecord? _catalog;
  List<WatchFood> _syncedFoods = const [];
  List<WatchFoodCategory> _categories = const [];

  String? _selectedFoodId;
  double _servings = WatchNutritionPortion.minServings;
  String? _confirmation;

  // ---------------------------------------------------------------------------
  // What the surface reads
  // ---------------------------------------------------------------------------

  /// The wrist's list: the phone's Foods I Eat order, with what the user
  /// logged here recently lifted to the front.
  List<WatchFood> get foods => List.unmodifiable(
    deriveWatchFoodList(
      foods: _syncedFoods,
      categories: _categories,
      recentFoodIds: _recentFoodIds,
    ),
  );

  /// The food with [foodId] as the wrist holds it, or null when the phone has
  /// not sent one.
  WatchFood? food(String foodId) {
    for (final candidate in _syncedFoods) {
      if (candidate.foodId == foodId) return candidate;
    }
    return null;
  }

  /// When the phone generated the list the watch is holding, or null when no
  /// phone has sent one yet.
  DateTime? get syncedAt => _catalog?.generatedAt;

  String? get selectedFoodId => _selectedFoodId;

  WatchFood? get selected {
    final foodId = _selectedFoodId;
    return foodId == null ? null : food(foodId);
  }

  /// The portion the user has dialled in, in servings of the selected food.
  double get servings => _servings;

  /// What the current portion costs, in kcal.
  int get calories => selected?.caloriesAt(_servings) ?? 0;

  /// The portion as the wrist prints it — `1.5 × 100 g` — or an empty string
  /// while nothing is selected.
  String get portionLabel {
    final food = selected;
    if (food == null) return '';
    return '${_formatAmount(_servings)} × '
        '${_formatAmount(food.referenceAmount)} ${food.referenceLabel}';
  }

  /// What the wrist says after a log, or null when nothing has been logged
  /// since the user last touched the surface.
  String? get confirmation => _confirmation;

  // ---------------------------------------------------------------------------
  // The synced list
  // ---------------------------------------------------------------------------

  /// Reads the food list back out of storage. Call on launch, and after any
  /// suspension: what comes back is what the phone last sent.
  Future<void> restore() async {
    final contents = await _store.readAll();
    _catalog = contents.foodCatalogs.isEmpty
        ? null
        : contents.foodCatalogs.reduce(
            (newest, row) => row.sequence > newest.sequence ? row : newest,
          );
    _applyCatalog();
  }

  /// Applies a `foods_down` message: the list the user quick-logs from.
  ///
  /// The message is stored whole and the newest one wins, so the list the user
  /// sees updates on the next background sync with no action from them (S-003).
  Future<WatchFoodsDownResult> applyFoodsDown(
    Map<String, Object?> envelope,
  ) async {
    final decision = SyncProtocolValidator.evaluateOrAccept(
      _validator,
      envelope,
    );
    if (!decision.accepted) {
      return WatchFoodsDownResult(decision: decision, applied: false);
    }

    final sent = WatchFoodsDown.fromEnvelope(envelope);
    final cached = _catalog;
    if (cached != null && sent.generatedAt.isBefore(cached.generatedAt)) {
      return WatchFoodsDownResult(
        decision: SyncMessageDecision(
          decision: SyncProtocolValidator.acceptDecision,
          reason:
              'an older view of the food list is not a newer truth; '
              'the list generated at ${utcIso(cached.generatedAt)} stands',
          respondWithSnapshot: false,
          rejections: const [],
        ),
        applied: false,
      );
    }

    final record = WatchFoodCatalogRecord(
      recordId: 'foods-${envelope['messageId']}',
      recordedAt: sent.generatedAt,
      generatedAt: sent.generatedAt,
      foods: [for (final food in sent.foods) food.toJson()],
      categories: [for (final category in sent.categories) category.toJson()],
    );
    final stored = await _store.append(record);
    _catalog = stored;
    _applyCatalog();

    return WatchFoodsDownResult(decision: decision, applied: true);
  }

  void _applyCatalog() {
    final catalog = _catalog;
    if (catalog == null) {
      _syncedFoods = const [];
      _categories = const [];
      return;
    }
    final synced = WatchFoodsDown.fromCatalog(catalog);
    _syncedFoods = synced.foods;
    _categories = synced.categories;
  }

  /// The foods the user logged on the wrist, newest first.
  ///
  /// Read out of the observations the store already holds rather than written
  /// to a list of its own: a relaunch cannot lose what storage kept.
  List<String> get _recentFoodIds {
    final seen = <String>{};
    final recent = <String>[];
    for (final observation in _engine.nutritionLog.reversed) {
      final foodId = observation.payload['foodId'];
      if (foodId is String && seen.add(foodId)) recent.add(foodId);
    }
    return recent;
  }

  // ---------------------------------------------------------------------------
  // The portion
  // ---------------------------------------------------------------------------

  /// Picks [foodId] and starts its portion where the phone left it — the amount
  /// the user logged last, or one serving.
  void select(String foodId) {
    final food = this.food(foodId);
    if (food == null) return;
    _selectedFoodId = foodId;
    _servings = _clampServings(food.defaultServings);
    _confirmation = null;
  }

  /// A turn of the rotary input, in detents: one detent is
  /// [WatchNutritionPortion.stepServings] of the food.
  void stepPortion(int detents) {
    _servings = _clampServings(
      _servings + detents * WatchNutritionPortion.stepServings,
    );
    _confirmation = null;
  }

  static double _clampServings(double servings) => servings
      .clamp(
        WatchNutritionPortion.minServings,
        WatchNutritionPortion.maxServings,
      )
      .toDouble();

  // ---------------------------------------------------------------------------
  // Logging
  // ---------------------------------------------------------------------------

  /// Logs the selected food at the current portion, and says so on the wrist.
  ///
  /// The engine stores the event before anything is emitted, so the only thing
  /// this can fail at is having nothing selected — and a food the user did not
  /// pick is not a food they ate.
  Future<WatchObservationRecord> logSelected() async {
    final food = selected;
    if (food == null) {
      throw StateError(
        'logSelected() was called with no food selected; select one first',
      );
    }

    final record = await _engine.logNutrition(
      foodId: food.foodId,
      servings: _servings,
      calories: food.caloriesAt(_servings).toDouble(),
      loggedAt: _clock(),
    );
    _confirmation =
        '${food.name} \u00b7 $portionLabel \u00b7 ${food.caloriesAt(_servings)} kcal';
    return record;
  }

  /// A number as the wrist prints it: whole numbers without a trailing `.0`,
  /// and everything else at the resolution a portion detent can produce.
  static String _formatAmount(double amount) {
    if (amount == amount.roundToDouble()) return amount.round().toString();
    return amount.toStringAsFixed(1);
  }
}
