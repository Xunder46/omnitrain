// filepath: lib/state/stats/stats_primer_state.dart
//
// State for the one-time Stats page primer (see
// `docs/plans/2026-10-04-10b-stats-pr10b-primer-sheet-plan/2026-10-04-10b-stats-pr10b-primer-sheet-plan.md`).
//
// A first-time user opening Stats sees one empty card and nothing else.
// Nothing on the screen explains the Signals cards or the chart icon, so the
// first time they tap Stats from Home we want a single dismissible primer that
// explains the page in three short blocks.
//
// This state tracks the "has the user seen the primer yet?" flag. The flag is
// PERSISTED via the repository preference surface (`'primer_seen_stats'`) so it
// survives a full app close + relaunch, and it is deliberately distinct from
// the Nutrition primer's `'primer_seen_nutrition'` so the two flags are
// readable and writable independently. Until [init] completes, the seen value
// is `false` (the safer default — assume unseen until we know better) so a
// missed hydration is conservative.

import 'package:flutter/foundation.dart';

import '../../data/repositories/workout_repository.dart';

/// One-shot Stats primer state.
///
/// Hydration contract:
/// 1. Construct the state in `lib/main.dart` (right after the repository is
///    initialised).
/// 2. Call [init] BEFORE `runApp` so the first frame sees the correct persisted
///    seen value. [init] is idempotent — calling it more than once is safe and
///    notifies only on the first call.
///
/// Seen-state contract:
/// - Before [init] completes, [shouldShowPrimer] returns `true` (unseen by
///   default). The home screen never opens the primer until the user taps the
///   Stats tile, so the brief pre-init window never produces a visible wrong
///   auto-show.
/// - The header "?" control on the Stats page never mutates the seen state —
///   reopening the primer is independent of the once-per-install auto-show.
class StatsPrimerState extends ChangeNotifier {
  /// Repository preference key for the persisted seen flag.
  ///
  /// Exposed as a static const so tests can clear or assert the same key
  /// without string-typing it twice. The string is intentionally distinct from
  /// `'primer_seen_nutrition'` — a regression that swaps one key for the other
  /// would silently couple two unrelated flags.
  static const String preferenceKey = 'primer_seen_stats';

  final WorkoutRepository _repository;

  /// `true` once the user has dismissed the auto-shown primer (or the persisted
  /// flag is set on cold start).
  bool _seen = false;

  /// `true` once [init] has hydrated the persisted flag. Makes [init]
  /// idempotent: a second call is a no-op and does not notify again.
  bool _initialized = false;

  StatsPrimerState(this._repository);

  /// `true` when the next Stats tap from Home should auto-show the primer. The
  /// getter is the SINGLE source of truth for the auto-show decision — both the
  /// home screen's tap handler and the header "?" control consult it.
  bool get shouldShowPrimer => !_seen;

  /// `true` once the user has ever dismissed the primer on this install (or the
  /// persisted flag was set on cold start). The header "?" uses this to decide
  /// whether its tap should re-mark (it never does — see note in class doc).
  bool get hasSeen => _seen;

  /// Read the persisted seen flag from the repository and hydrate
  /// [shouldShowPrimer]. Safe to call before `runApp`; a failure falls back to
  /// "unseen" so the user gets the primer at least once. Idempotent — only the
  /// first call reads and notifies.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      _seen = await _repository.getPreferenceBool(preferenceKey);
    } catch (_) {
      // Leave `_seen = false` (the safer default — show the primer rather than
      // silently skip it on a hydration error). The next markSeen() will retry
      // the write.
    }
    notifyListeners();
  }

  /// Record that the user has seen the primer. Idempotent — a second call is a
  /// no-op. Fires [notifyListeners] exactly once (on the first call) so the
  /// home-screen rebuild picks up the new value.
  Future<void> markSeen() async {
    if (_seen) return;
    _seen = true;
    notifyListeners();
    await _repository.setPreferenceBool(preferenceKey, true);
  }
}
