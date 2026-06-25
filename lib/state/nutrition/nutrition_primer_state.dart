// filepath: lib/state/nutrition/nutrition_primer_state.dart
//
// State for the one-time Daily Nutrition page primer (see
// `.github/agents/plans/nutrition-page-primer-plan.md`).
//
// The Daily Nutrition page inverts the usual food-logging model:
// users curate a "Foods I Eat" list once from the global library,
// then check foods off daily (with an adjustable per-food
// portion) and watch the day roll up into a calories/macros
// ring + water + sodium. New users have no context for any of
// that, so the first time they tap the home nutrition strip we
// want a single dismissible primer that explains the page in
// three short blocks.
//
// This state tracks the "has the user seen the primer yet?"
// flag. The flag is PERSISTED via the repository preference
// surface (`'primer_seen_nutrition'`) so it survives a full
// app close + relaunch. Until [init] completes, the seen
// value is `false` (the safer default — assume unseen until
// we know better) so a missed hydration is conservative.
//
// IMPORTANT: do NOT model this on `HomeState._maintenanceHintSeen`
// without the persistence round-trip. The maintenance hint
// flag is in-memory-only by design; the nutrition primer MUST
// survive a relaunch. The wrong-pattern guard test
// (S-006) asserts on the persisted value to catch a
// regression that drops persistence.

import 'package:flutter/foundation.dart';

import '../../data/repositories/workout_repository.dart';

/// One-shot Daily Nutrition primer state.
///
/// Hydration contract:
/// 1. Construct the state in `main.dart` (right after the
///    repository is initialised).
/// 2. Call [init] BEFORE `runApp` so the first frame sees the
///    correct persisted seen value. [init] is idempotent —
///    calling it more than once is safe.
///
/// Seen-state contract:
/// - Before [init] completes, [shouldShowPrimer] returns `true`
///   (unseen by default). The home screen never opens the
///   primer until the user taps the nutrition strip, so the
///   brief pre-init window never produces a visible wrong
///   auto-show.
/// - The header "?" control on the nutrition page never
///   mutates the seen state — reopening the primer is
///   independent of the once-per-install auto-show.
class NutritionPrimerState extends ChangeNotifier {
  /// Repository preference key for the persisted seen flag.
  ///
  /// Exposed as a static const so tests can clear or assert
  /// the same key without string-typing it twice. The string
  /// is intentionally distinct from `'hint_seen_maintenance'`
  /// — a regression that swaps one key for the other would
  /// silently couple two unrelated flags.
  static const String preferenceKey = 'primer_seen_nutrition';

  final WorkoutRepository _repository;

  /// `true` once the user has dismissed the auto-shown primer
  /// (or the persisted flag is set on cold start).
  bool _seen = false;

  NutritionPrimerState(this._repository);

  /// `true` when the next home-strip tap should auto-show the
  /// primer. The getter is the SINGLE source of truth for the
  /// auto-show decision — both the home screen's tap handler
  /// and the header "?" control consult it.
  bool get shouldShowPrimer => !_seen;

  /// `true` once the user has ever dismissed the primer on
  /// this install (or the persisted flag was set on cold
  /// start). The header "?" uses this to decide whether its
  /// tap should re-mark (it never does — see note in class
  /// doc).
  bool get hasSeen => _seen;

  /// Read the persisted seen flag from the repository and
  /// hydrate [shouldShowPrimer]. Safe to call before
  /// `runApp`; failures fall back to "unseen" so the user
  /// gets the primer at least once.
  Future<void> init() async {
    try {
      final persisted =
          await _repository.getPreferenceBool(preferenceKey);
      _seen = persisted;
    } catch (_) {
      // Leave `_seen = false` (the safer default — show the
      // primer rather than silently skip it on a hydration
      // error). The next markSeen() will retry the write.
    }
    notifyListeners();
  }

  /// Record that the user has seen the primer. Idempotent —
  /// a second call is a no-op. Fires [notifyListeners] exactly
  /// once (on the first call) so the home-screen rebuild
  /// picks up the new value.
  Future<void> markSeen() async {
    if (_seen) return;
    _seen = true;
    notifyListeners();
    await _repository.setPreferenceBool(preferenceKey, true);
  }
}
