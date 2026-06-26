import 'package:flutter/foundation.dart';
import '../core/constants/water_constants.dart';
import '../core/utils/date_utils.dart';
import '../data/models/models.dart';
import '../data/repositories/workout_repository.dart';

class NutritionState extends ChangeNotifier {
  final WorkoutRepository _repository;

  NutritionState(this._repository);

  NutritionTarget? _nutritionTarget;
  NutritionTarget? get nutritionTarget => _nutritionTarget;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// Per-date cache of loaded targets. Avoids repeated repository round-trips
  /// when the UI navigates between dates or re-queries the same day.
  final Map<int, NutritionTarget?> _targetsByDate = {};

  /// Returns the most recent cached or loaded target for [dateMs], if any.
  /// Does not trigger a repository fetch.
  NutritionTarget? getCachedTargetForDate(int dateMs) =>
      _targetsByDate[dateMs];

  // ─── Consumed foods (today's day-log) ──────────────────────────────────
  // Source of truth for the calorie ring on the nutrition page. Backed by
  // `WorkoutRepository.getConsumedFoodsForDate`, which both implementations
  // (`HiveWorkoutRepository` and future `SqliteWorkoutRepository`) already
  // provide. The state caches the result and notifies listeners on every
  // successful load so the ring rebuilds when the day's log changes.

  /// Cached list of consumed-food snapshots for today (local-time).
  /// Empty when nothing has been loaded yet or when nothing was logged.
  List<ConsumedFood> _consumedToday = const [];

  /// Unmodifiable view of today's consumed foods. Safe to read from `build`.
  /// Callers must not mutate the returned list.
  List<ConsumedFood> get consumedToday => List.unmodifiable(_consumedToday);

  /// Sums `caloriesConsumed` across the cached [consumedToday] list.
  /// Returns 0 for an empty list. Pure / derived — no repo call.
  int get todayConsumedCalories => _consumedToday.fold<int>(
        0,
        (sum, c) => sum + c.caloriesConsumed,
      );

  // ─── Daily water log ───────────────────────────────────────────────────
  // Source of truth for the water tracker on the bottom-right of the
  // calorie-ring card. Backed by `WorkoutRepository.getWaterVolumeForDate`,
  // which both implementations (`MockWorkoutRepository` and future
  // `SqliteWorkoutRepository`) provide. The state caches the result and
  // notifies listeners on every successful load / write so the count
  // rebuilds when the day's volume changes.
  //
  // The on-screen glass count is derived (`_waterTodayMl ~/ kWaterGlassMl`)
  // and never stored — the canonical unit is milliliters, so historical
  // totals stay unit-clean if the per-glass amount ever changes. Water
  // has no goal (no progress bar, no target); it is tracked and stored
  // for the historical record only.

  /// Cached water volume for the most recently loaded day, in milliliters.
  /// `0` until the first explicit load (or rollover) runs.
  int _waterTodayMl = 0;

  /// Stored water volume for the active day in milliliters.
  /// Always `>= 0` — the state layer floors decrement at 0 ml.
  int get waterTodayMl => _waterTodayMl;

  /// Whole glass count derived from the stored ml. Integer division
  /// (so 250 ml → 1 glass, 750 ml → 3 glasses, 0 ml → 0 glasses).
  /// The icon + "250 ml" annotation carries the per-glass amount
  /// so the user can decode the unit at a glance.
  int get waterTodayGlasses => _waterTodayMl ~/ kWaterGlassMl;

  /// Load the water volume for a specific date from the repository into
  /// the cache, and notify listeners. Safe to call repeatedly; an empty
  /// repo returns `0` (no exception, no error state). Past dates are
  /// stored alongside today — the cache is replaced, not merged.
  Future<void> loadWaterForDate(int dateMs) async {
    try {
      final ml = await _repository.getWaterVolumeForDate(dateMs);
      _waterTodayMl = ml;
    } catch (_) {
      // Leave the previous cache intact; surface a safe 0 default
      // for the freshly-loaded day so a stale value does not leak.
      _waterTodayMl = 0;
    }
    notifyListeners();
  }

  /// Convenience: load today's water volume.
  Future<void> loadWaterForToday() =>
      loadWaterForDate(OmniDateUtils.todayMidnightMs());

  /// Add one glass (250 ml) to [dateMs] and persist immediately. The
  /// tap-only control never accepts a typed amount; the per-glass
  /// amount is fixed by [kWaterGlassMl]. Always succeeds — the
  /// repository clamps at 0 ml as a final defense and `kWaterGlassMl`
  /// is always positive, so the resulting volume is always non-negative.
  Future<void> incrementWaterForDate(int dateMs) async {
    final current = await _repository.getWaterVolumeForDate(dateMs);
    final next = current + kWaterGlassMl;
    await _repository.saveWaterVolumeForDate(dateMs, next);
    _waterTodayMl = next;
    notifyListeners();
  }

  /// Remove one glass (250 ml) from [dateMs] and persist immediately.
  /// Floors at `0` ml — a minus at 0 ml is a no-op (no negative
  /// leak, no spurious row, no notification).
  Future<void> decrementWaterForDate(int dateMs) async {
    final current = await _repository.getWaterVolumeForDate(dateMs);
    if (current <= 0) {
      // Already at zero — no write, no notification. This is the
      // tap-only no-op the disabled minus button also enforces.
      return;
    }
    final next = current - kWaterGlassMl < 0 ? 0 : current - kWaterGlassMl;
    await _repository.saveWaterVolumeForDate(dateMs, next);
    _waterTodayMl = next;
    notifyListeners();
  }

  /// Load nutrition target for a specific date.
  /// If not found for that date, the repository walks backward to find
  /// the most recent ancestor target and returns a copy rolled forward.
  Future<void> loadNutritionTargetForDate(int dateMs) async {
    _isLoading = true;
    // Defer the loading-flipped-true notify to the next microtask
    // so callers that fire this from `initState` (e.g. the
    // nutrition screen, the home screen) do not race with the
    // ongoing frame's build. The end-of-load notify below runs
    // in a fresh microtask after the await so it is naturally
    // safe.
    Future.microtask(notifyListeners);

    try {
      final target = await _repository.getNutritionTargetForDate(dateMs);
      _nutritionTarget = target;
      _targetsByDate[dateMs] = target;
    } catch (e) {
      _nutritionTarget = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Save nutrition target for a specific date and propagate forward
  /// to future dates that still have the old values.
  Future<void> saveNutritionTargetForDate(
      int dateMs, NutritionTarget target) async {
    _isLoading = true;
    notifyListeners();

    try {
      await _repository.saveNutritionTargetForDate(dateMs, target);
      _nutritionTarget = target.copyWith(dateMs: dateMs);
      _targetsByDate[dateMs] = _nutritionTarget;
    } catch (e) {
      _nutritionTarget = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Get today's nutrition target (convenience method).
  /// Loads from the repository, updates [_nutritionTarget] and the cache,
  /// and notifies listeners.
  Future<NutritionTarget?> getTodayTarget() async {
    final todayMs = OmniDateUtils.todayMidnightMs();
    final target = await _repository.getNutritionTargetForDate(todayMs);
    _nutritionTarget = target;
    _targetsByDate[todayMs] = target;
    notifyListeners();
    return target;
  }

  /// Handle day rollover (called when app detects date change).
  ///
  /// Safety net for long-running apps: clears the in-memory
  /// `consumedToday` cache and the per-date target cache so a
  /// yesterday's totals cannot leak into today. Then reloads the
  /// target for [dateMs] (which performs the backward-walk
  /// fallback for the new day).
  ///
  /// Past `ConsumedFood` rows in storage are unaffected — the
  /// cache is the only thing cleared; `getConsumedFoodsForDate`
  /// returns the same rows for the same dateMs on every call.
  Future<void> rolloverToDate(int dateMs) async {
    // Drop any cached "today" state. A new day must start empty.
    if (_consumedToday.isNotEmpty) {
      _consumedToday = const [];
    }
    // Drop the per-date target cache so the new date picks up the
    // latest ancestor (or null) from the repository, not a stale
    // yesterday's value.
    _targetsByDate.clear();
    _nutritionTarget = null;
    // Drop the water cache so yesterday's volume does not leak into
    // today. The new day's volume (typically 0 ml) is re-read by
    // `loadWaterForDate(dateMs)` below. Prior dates' stored ml are
    // untouched in the repository — the rollover only clears the
    // in-memory cache, not the historical record.
    _waterTodayMl = 0;
    notifyListeners();
    await loadNutritionTargetForDate(dateMs);
    await loadWaterForDate(dateMs);
  }

  /// Legacy methods for backwards compatibility - delegate to date-aware methods.
  Future<void> loadNutritionTarget() async {
    await loadNutritionTargetForDate(OmniDateUtils.todayMidnightMs());
  }

  Future<void> saveNutritionTarget(NutritionTarget target) async {
    await saveNutritionTargetForDate(
      OmniDateUtils.todayMidnightMs(),
      target,
    );
  }

  // ─── Consumed-food operations (today's day-log) ───────────────────────
  // Powers the calorie ring on the nutrition page. The repository is the
  // single source of truth for the underlying rows; this state layer caches
  // the result for the active day and notifies listeners when it changes.

  /// Load today's consumed foods from the repository into [_consumedToday]
  /// and notify listeners. Safe to call repeatedly; an empty repo returns
  /// an empty list (no exception, no error state).
  ///
  /// Idempotent: a successful load always replaces [_consumedToday] with a
  /// fresh list. A failed load leaves the previous cache intact (matches
  /// the existing `loadNutritionTargetForDate` error pattern).
  Future<void> loadConsumedToday() async {
    final todayMs = OmniDateUtils.todayMidnightMs();
    try {
      final entries = await _repository.getConsumedFoodsForDate(todayMs);
      _consumedToday = entries;
    } catch (_) {
      // Leave the previous cache intact; surface a safe empty state.
      _consumedToday = const [];
    }
    notifyListeners();
  }

  /// Get today's consumed foods (convenience method).
  ///
  /// Loads the latest snapshot from the repository, updates
  /// [_consumedToday], and notifies listeners. Returns the list so callers
  /// can `await` and use it directly.
  ///
  /// Replaces the previous stub that returned an empty list. Kept on the
  /// public API so the existing call sites and tests keep working.
  Future<List<ConsumedFood>> getTodayConsumedFoods() async {
    final todayMs = OmniDateUtils.todayMidnightMs();
    try {
      final entries = await _repository.getConsumedFoodsForDate(todayMs);
      _consumedToday = entries;
    } catch (_) {
      _consumedToday = const [];
    }
    notifyListeners();
    return _consumedToday;
  }

  /// Log a consumed food item for today.
  ///
  /// Creates a frozen [ConsumedFood] snapshot from the source [food] and
  /// the currently-cached [nutritionTarget], persists it via the
  /// repository, and refreshes the [_consumedToday] cache so the calorie
  /// ring updates immediately.
  ///
  /// The snapshot freezes:
  ///   - food name, unit type, reference amount/label, macros
  ///   - today's daily targets (so historical totals stay stable when the
  ///     user later edits their targets)
  ///   - the source food's group id and name (via lookup, nullable if
  ///     the group has been removed)
  ///
  /// Returns the id of the newly-created consumed-food row, or `null` if
  /// persistence failed. The cache is left untouched on failure so the
  /// ring does not flicker.
  Future<String?> logConsumedFood(Food food, double amountConsumed) async {
    // Validation: the amount must be a finite positive number. The
    // frozen-snapshot contract requires a meaningful amount; 0 or
    // negative inputs are rejected as a no-op (returns null without
    // mutating state).
    if (!amountConsumed.isFinite || amountConsumed <= 0) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    final todayMs = OmniDateUtils.todayMidnightMs();
    final target = _nutritionTarget ?? NutritionTarget();

    // Look up the group name snapshot from the live food (nullable if the
    // food has no group, or the group has been removed). We deliberately
    // do not block logging on a missing group — the snapshot tolerates
    // nulls.
    String? groupNameSnapshot;
    if (food.groupId != null) {
      try {
        final group = await _repository.getFoodGroupById(food.groupId!);
        groupNameSnapshot = group?.name;
      } catch (_) {
        groupNameSnapshot = null;
      }
    }

    final entry = ConsumedFood(
      id: 'consumed-$now-${now ~/ 1000}',
      loggedAtMs: now,
      dateMs: todayMs,
      sourceFoodId: food.id,
      name: food.name,
      unitType: food.unitType,
      referenceAmount: food.referenceAmount,
      referenceLabel: food.referenceLabel,
      protein: food.protein,
      carbs: food.carbs,
      fiber: food.fiber,
      fat: food.fat,
      // D-7: freeze the source food's sodium onto the snapshot at
      // log time. Editing the food's sodium later does not change
      // the logged day's sodium total.
      sodium: food.sodium,
      amountConsumed: amountConsumed,
      groupIdSnapshot: food.groupId,
      groupNameSnapshot: groupNameSnapshot,
      targetCalories: target.calories,
      targetProtein: target.protein,
      targetCarbs: target.carbs,
      targetFat: target.fat,
      createdAtMs: now,
      updatedAtMs: now,
    );

    try {
      final id = await _repository.createConsumedFood(entry);
      // Refresh the cache so the ring rebuilds without a separate load.
      _consumedToday = [
        ..._consumedToday,
        entry.copyWith(id: id),
      ];
      // Write-through: update the food row's `lastAmountConsumed`
      // so the next time the user opens Foods I Eat, this row
      // pre-fills with the amount they just logged (June 2026,
      // food-last-amount plan). Best-effort: a transient
      // `updateFood` failure does not roll back the ConsumedFood
      // write (which is the source of truth for today's log) and
      // does not block returning the new id. The user can retry
      // the log; a future load will pick up the value.
      await _writeThroughLastAmount(food, amountConsumed);
      notifyListeners();
      return id;
    } catch (_) {
      return null;
    }
  }

  /// Remove a consumed-food entry by id and refresh the cache.
  /// No-op (and returns false) if the id is not in the cache.
  Future<bool> deleteConsumedFood(String id) async {
    final had = _consumedToday.any((c) => c.id == id);
    if (!had) return false;
    try {
      await _repository.deleteConsumedFood(id);
      _consumedToday = _consumedToday.where((c) => c.id != id).toList();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Handle day rollover for the consumed-food cache. The next
  /// [loadConsumedToday] / [getTodayConsumedFoods] call will repopulate
  /// from the repository for the new day. The cache itself is cleared
  /// here so the ring does not show yesterday's totals during the gap.
  void clearConsumedToday() {
    if (_consumedToday.isEmpty) return;
    _consumedToday = const [];
    notifyListeners();
  }

  // ─── Day-uniqueness + checkbox-driven log (log from library) ─────────────
  // Powers the per-row checkbox + amount input on the food library card.
  // The day-uniqueness contract: there is at most one `ConsumedFood` row
  // per `(sourceFoodId, dateMs)` — toggling the checkbox on a food that
  // is already logged updates the existing row; toggling it off deletes
  // the row. Editing the amount updates the existing row in place.
  // The frozen-snapshot semantics (R-8) are preserved because
  // `logConsumedFoodAt` always re-snapshots the source food's
  // name/unit/macros/target at the time of the call, and `unlogFoodToday`
  // only removes the row.

  /// Look up the cached `ConsumedFood` row for [foodId] and today, or
  /// `null` if no such row exists.
  ///
  /// Pure / cache-only: does not trigger a repository fetch. The cache
  /// is kept in sync by [loadConsumedToday] / [refreshConsumedToday] /
  /// [logConsumedFoodAt] / [unlogFoodToday]. Callers that need a
  /// cold-cache fallback (e.g. test fixtures mutating the repository
  /// directly) should call [refreshConsumedToday] first.
  ConsumedFood? findLoggedTodayForFood(String foodId) {
    final todayMs = OmniDateUtils.todayMidnightMs();
    for (final c in _consumedToday) {
      if (c.sourceFoodId == foodId && c.dateMs == todayMs) return c;
    }
    return null;
  }

  /// Returns `true` when the cache contains a `ConsumedFood` row for
  /// [foodId] and today. Used by the row's checkbox `value:` binding.
  bool isFoodLoggedToday(String foodId) =>
      findLoggedTodayForFood(foodId) != null;

  /// Log a food as consumed (or update the existing row, if the food
  /// is already logged today) at the given [amount] in the food's
  /// own unit. Enforces the day-uniqueness contract.
  ///
  /// The amount is validated: must be > 0. Returns `null` (and does
  /// not modify state) for invalid amounts.
  ///
  /// On a fresh log, builds a frozen `ConsumedFood` snapshot from the
  /// source food + cached target. On an update, preserves the
  /// original snapshot's name, unit, reference, macros, group, and
  /// target fields; only `amountConsumed` and `updatedAtMs` change.
  /// This keeps the frozen-snapshot contract intact (R-8): the row's
  /// macros/targets are NOT recomputed from the live food.
  Future<String?> logConsumedFoodAt(Food food, double amount) async {
    if (!amount.isFinite || amount <= 0) return null;
    final existing = findLoggedTodayForFood(food.id);
    if (existing != null) {
      // Day-uniqueness: update the existing row's amount only.
      final now = DateTime.now().millisecondsSinceEpoch;
      final updated = existing.copyWith(
        amountConsumed: amount,
        updatedAtMs: now,
      );
      try {
        await _repository.updateConsumedFood(updated);
      } catch (_) {
        return null;
      }
      _consumedToday = _consumedToday
          .map((c) => c.id == existing.id ? updated : c)
          .toList();
      // Write-through: same contract as `logConsumedFood` (June
      // 2026, food-last-amount plan). Best-effort.
      await _writeThroughLastAmount(food, amount);
      notifyListeners();
      return existing.id;
    }
    // Fresh log: delegate to the existing snapshot-builder.
    return logConsumedFood(food, amount);
  }

  /// Remove the consumed-food row for [foodId] and today.
  ///
  /// Returns `true` if a row was removed, `false` otherwise (no-op for
  /// unknown / not-logged-today ids). On success the cache is updated
  /// and listeners are notified so the ring + checkbox state update
  /// live.
  Future<bool> unlogFoodToday(String foodId) async {
    final existing = findLoggedTodayForFood(foodId);
    if (existing == null) return false;
    return deleteConsumedFood(existing.id);
  }

  // ─── food lastAmountConsumed write-through (food-last-amount-plan) ──
  // A successful `logConsumedFoodAt` / `logConsumedFood` call must also
  // stamp the saved amount onto the source food's
  // `lastAmountConsumed` field so the next `LogFoodRow` pre-fill can
  // read it (S-001 / S-003). The `ConsumedFood` row is the source of
  // truth for today's totals and is written first; this write-through
  // is best-effort — a transient `updateFood` failure must not roll
  // back the day's log or block the call from returning the new id.

  /// Write [amount] onto [food]'s `lastAmountConsumed` field via
  /// the existing `updateFood` repository method. Best-effort: a
  /// thrown exception (e.g. a transient storage error) is logged
  /// to the debug channel but never rethrown. The caller is the
  /// only path that invokes this method.
  Future<void> _writeThroughLastAmount(Food food, double amount) async {
    try {
      final updated = food.copyWith(
        lastAmountConsumed: amount,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      await _repository.updateFood(updated);
    } catch (e) {
      // Best-effort: never roll back the day's log. The user can
      // re-log the food; the next load will pick up the value.
      debugPrint(
        'NutritionState: lastAmountConsumed write-through failed '
        'for ${food.id}: $e',
      );
    }
  }

  // ─── Derived totals (cache-only) ──────────────────────────────────────
  // The cache is the single source of truth for the calorie ring and
  // the "Consumed Today" list. These getters fold the cache; they do
  // not touch the repository.

  /// Sum of `(protein * amountConsumed / referenceAmount)` across the
  /// cached [consumedToday] list, accumulated as a double and rounded
  /// once at the end. Returns 0 for an empty list.
  ///
  /// The scaling mirrors [ConsumedFood.caloriesConsumed]: the macros
  /// on each snapshot are stored per the food's reference, and
  /// `amountConsumed` is in the food's own unit. Summing unrounded
  /// values and rounding once at the end matches the calorie math
  /// (which is also rounded once) and avoids per-row rounding drift —
  /// e.g. a 30g-protein-per-100g food at 1.5 portions contributes
  /// 0.45 g per row; rounding per row to 0 would erase the entry.
  int get todayConsumedProtein => _consumedToday.fold<double>(
        0,
        (sum, c) => sum + c.protein * c.amountConsumed / c.referenceAmount,
      ).round();

  /// Sum of `(carbs * amountConsumed / referenceAmount)` across the
  /// cached [consumedToday] list, accumulated as a double and rounded
  /// once at the end. Returns 0 for an empty list.
  int get todayConsumedCarbs => _consumedToday.fold<double>(
        0,
        (sum, c) => sum + c.carbs * c.amountConsumed / c.referenceAmount,
      ).round();

  /// Sum of `(fat * amountConsumed / referenceAmount)` across the
  /// cached [consumedToday] list, accumulated as a double and rounded
  /// once at the end. Returns 0 for an empty list.
  int get todayConsumedFat => _consumedToday.fold<double>(
        0,
        (sum, c) => sum + c.fat * c.amountConsumed / c.referenceAmount,
      ).round();

  /// Sum of `(fiber * amountConsumed / referenceAmount)` across the
  /// cached [consumedToday] list, accumulated as a double and rounded
  /// once at the end. `ConsumedFood.fiber` is `int?`; null is treated
  /// as 0. Returns 0 for an empty list.
  ///
  /// Used by the macro-distribution donut chart. Note that the donut
  /// separates **net carbs** (`carbs - fiber`) from **fiber**, so this
  /// getter returns the raw fiber grams — net carbs must be derived at
  /// the chart site as `max(0, todayConsumedCarbs - todayConsumedFiber)`.
  int get todayConsumedFiber => _consumedToday.fold<double>(
        0,
        (sum, c) =>
            sum + (c.fiber ?? 0) * c.amountConsumed / c.referenceAmount,
      ).round();

  /// Sum of `(sodium * amountConsumed / referenceAmount)` across the
  /// cached [consumedToday] list, accumulated as a double and rounded
  /// once at the end (D-7). `ConsumedFood.sodium` is `int?`; null is
  /// treated as 0. Returns 0 for an empty list.
  ///
  /// Sodium is frozen onto each `ConsumedFood` snapshot at log time,
  /// so this getter is unaffected by later edits to the source
  /// food's `sodium` field. Rows logged before the freeze landed read
  /// as 0 (the field defaults to null and is treated as 0 here) —
  /// the ring card renders "Na 0 mg" until those days are re-logged
  /// with the new code path.
  int get todayConsumedSodium => _consumedToday.fold<double>(
        0,
        (sum, c) =>
            sum + (c.sodium ?? 0) * c.amountConsumed / c.referenceAmount,
      ).round();

  // ─── Per-macro calorie contributions (D-4 / D-5) ───────────────────────
  // The home nutrition strip (D-5) needs the calorie contribution of
  // each macro so the segmented bar can lay out segments proportional
  // to "macro's share of consumed calories". The math follows D-4:
  //   protein × 4
  //   totalCarbs × 4   (NOT net carbs — D-5 says "total-carb calories
  //                     for blue"; net carbs is the donut's keto view
  //                     per D-4 and is irrelevant to the strip)
  //   fat × 9
  //
  // Getters accumulate as a double and round once at the end so a
  // row whose macros land on .5 doesn't drift across segments.
  // The strip widget itself stays math-free: it receives the
  // already-rounded calorie counts and the segment widths come from
  // the total.

  /// Protein calories today: `protein × amountConsumed / referenceAmount × 4`.
  int get todayProteinKcal => _consumedToday.fold<double>(
        0,
        (sum, c) => sum + c.protein * c.amountConsumed / c.referenceAmount * 4,
      ).round();

  /// Total-carbs calories today: `carbs × amountConsumed / referenceAmount × 4`.
  /// (D-5: "total-carb calories for blue". Net-carbs is the donut's
  /// keto view per D-4 and is intentionally NOT what the strip uses.)
  int get todayTotalCarbsKcal => _consumedToday.fold<double>(
        0,
        (sum, c) => sum + c.carbs * c.amountConsumed / c.referenceAmount * 4,
      ).round();

  /// Net-carbs calories today: `(carbs - fiber) × amountConsumed / referenceAmount × 4`.
  /// Uses the same net-carbs formula as the donut chart for consistent macro percentage
  /// calculations across the app (home strip bar and nutrition donut chart).
  int get todayNetCarbsKcal => _consumedToday.fold<double>(
        0,
        (sum, c) {
          final netCarbs = c.carbs - (c.fiber ?? 0);
          return sum +
              (netCarbs > 0 ? netCarbs : 0) *
                  c.amountConsumed /
                  c.referenceAmount *
                  4;
        },
      ).round();

  /// Fat calories today: `fat × amountConsumed / referenceAmount × 9`.
  int get todayFatKcal => _consumedToday.fold<double>(
        0,
        (sum, c) => sum + c.fat * c.amountConsumed / c.referenceAmount * 9,
      ).round();

  /// Sum of the three per-macro calorie contributions. Differs from
  /// [todayConsumedCalories] only by the rounding-once contract:
  /// summing the three rounded integers can drift by ±1 kcal from
  /// the calorie ring's headline total. The strip uses this sum to
  /// compute segment widths (which is what the per-macro shares are
  /// a percentage of), so the in-strip percentages sum to 100
  /// independently of the headline ring total.
  ///
  /// Uses [todayNetCarbsKcal] (net carbs, not total carbs) for consistency
  /// with the donut chart's percentage calculation.
  int get todayConsumedKcalFromMacros =>
      todayProteinKcal + todayNetCarbsKcal + todayFatKcal;

  /// `consumedToday` sorted by `loggedAtMs` ascending. Returns a new
  /// list (the cache stays in insertion order; this getter is for
  /// presentation and for deterministic test ordering).
  List<ConsumedFood> get consumedTodaySorted => [..._consumedToday]
    ..sort((a, b) => a.loggedAtMs.compareTo(b.loggedAtMs));

  /// Reload today's consumed foods from the repository and return the
  /// resulting cache. Sugar for [loadConsumedToday] at call sites
  /// that need the list (e.g. test fixtures reloading after an
  /// external edit).
  Future<List<ConsumedFood>> refreshConsumedToday() async {
    await loadConsumedToday();
    return _consumedToday;
  }
}
