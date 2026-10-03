import '../../data/repositories/workout_repository.dart';
import '../models/signals.dart';
import '../models/stats_progress.dart';
import '../models/training_load.dart';
import 'signals/signal.dart';
import 'signals/signal_registry.dart';
import 'stats_progress_service.dart';

/// Evaluates the registered signals for one Stats load and owns the dismissal
/// store (D-1009, D-1010, D-1014).
///
/// The screen builds one of these from the [StatsProgressService] it already
/// built, so an evaluation costs no second walk of history.
class SignalsService {
  final WorkoutRepository _repository;
  final StatsProgressService _progressService;
  final List<Signal> _signals;

  SignalsService({
    required WorkoutRepository repository,
    required StatsProgressService progressService,
    List<Signal>? signals,
  }) : _repository = repository,
       _progressService = progressService,
       _signals = signals ?? buildSignalRegistry();

  /// The candidates of one load, in registry order (D-1014).
  ///
  /// When the gate is unmet no signal is touched and the result is empty
  /// (D-1006); otherwise every registered signal is evaluated once and the
  /// cards of currently dismissed signals are dropped (D-1011).
  ///
  /// [dismissedAtMs] lets a caller that already read the store pass that map
  /// in, so one load reads the store once; when it is omitted the store is
  /// read here, which is what the service-level tests and `dismiss` rely on.
  Future<List<SignalCard>> evaluateCandidates({
    required DateTime now,
    required StatsWindow window,
    required MixLayerData? mix,
    Map<String, int>? dismissedAtMs,
  }) async {
    if (!signalsGateMet(mix)) return const [];
    final dismissed = dismissedAtMs ?? await loadDismissals();
    final context = SignalContext(
      now: now,
      window: window,
      mix: mix,
      progressService: _progressService,
      repository: _repository,
    );
    final cards = <SignalCard>[];
    for (final signal in _signals) {
      final card = await signal.evaluate(context);
      if (card == null) continue;
      final dismissedAt = dismissed[card.id];
      if (dismissedAt != null &&
          isSignalDismissed(dismissedAtMs: dismissedAt, now: now)) {
        continue;
      }
      cards.add(card);
    }
    return cards;
  }

  /// The stored dismissal map, read through the repository preference API
  /// (D-1009). Never throws.
  Future<Map<String, int>> loadDismissals() async {
    final raw = await _repository.getPreferenceString(kSignalDismissalsKey);
    return parseSignalDismissals(raw);
  }

  /// Records a dismissal of [id] at [now] and returns the new store (D-1010).
  ///
  /// Entries already at or past [kSignalDismissalDays] are pruned, so the store
  /// cannot grow without bound (D-1013).
  Future<Map<String, int>> dismiss(String id, DateTime now) async {
    final next = signalDismissalsWith(await loadDismissals(), id, now);
    await persistDismissals(next);
    return next;
  }

  /// Writes [dismissals] under [kSignalDismissalsKey] (D-1009).
  ///
  /// Never throws: a dismissal whose write fails is simply not remembered, and
  /// the caller has already moved the view on (D-1010).
  Future<void> persistDismissals(Map<String, int> dismissals) async {
    try {
      await _repository.setPreferenceString(
        kSignalDismissalsKey,
        encodeSignalDismissals(dismissals),
      );
    } catch (_) {
      // Not remembered; nothing else changes.
    }
  }
}
