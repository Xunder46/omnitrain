import '../../../data/repositories/workout_repository.dart';
import '../../models/signals.dart';
import '../../models/stats_progress.dart';
import '../../models/training_load.dart';
import '../stats_progress_service.dart';

/// The contract every signal implements (D-1015).
///
/// A signal reads the load it is handed and either proposes a card or abstains
/// by returning null (D-1008). It reads the repository only through
/// [SignalContext], and it never walks history a second time (D-1014).
abstract class Signal {
  /// The stable id used for the dismissal store, the widget key and the
  /// semantic label.
  String get id;

  /// Whether this signal speaks as a positive or a caution (D-1002).
  SignalKind get kind;

  /// Rank within [kind] only; higher wins (D-1005).
  int get priority;

  /// Proposes this signal's card, or null to abstain (D-1008).
  Future<SignalCard?> evaluate(SignalContext context);
}

/// Everything a signal may read during one evaluation (D-1015).
///
/// All five members are carried from the start so a later signal needs no
/// change to the contract.
class SignalContext {
  final DateTime now;
  final StatsWindow window;
  final MixLayerData? mix;
  final StatsProgressService progressService;
  final WorkoutRepository repository;

  const SignalContext({
    required this.now,
    required this.window,
    required this.mix,
    required this.progressService,
    required this.repository,
  });
}
