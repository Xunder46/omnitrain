import '../../../data/repositories/workout_repository.dart';
import '../../models/signals.dart';
import '../../models/stats_progress.dart';
import '../../models/training_load.dart';
import '../stats_progress_service.dart';

/// The contract every signal implements (D-1015).
///
/// A signal reads the load it is handed and either proposes a card or abstains
/// by returning null (D-1008). It reads history only through the
/// [StatsProgressService] in its [SignalContext] — the cached snapshot and the
/// memoised sections the screen already built — and never from the repository
/// itself, so a load walks history once (D-1014, D-18105).
abstract class Signal {
  /// The stable id used for the dismissal store, the widget key and the
  /// semantic label.
  String get id;

  /// Whether this signal speaks as a positive or a caution (D-1002).
  SignalKind get kind;

  /// Rank within [kind] only; higher wins (D-1005).
  int get priority;

  /// True when this signal reads the load measure or the effort ratings, so it
  /// stays silent until `signalsGateMet` is true; false when it reads neither
  /// and may speak from the first session (D-17501).
  bool get needsRatedWeeks;

  /// One sentence on what the user can supply to wake this signal, or null when
  /// it is not short of anything the user can supply (D-17601).
  Future<String?> waitingFor(SignalContext context);

  /// Proposes this signal's card, or null to abstain (D-1008).
  Future<SignalCard?> evaluate(SignalContext context);
}

/// Everything a signal may read during one evaluation (D-1015).
///
/// All six members are carried from the start so a later signal needs no
/// change to the contract.
class SignalContext {
  final DateTime now;
  final StatsWindow window;
  final MixLayerData? mix;
  final StatsProgressService progressService;
  final WorkoutRepository repository;

  /// The Start of Week setting, `monday` or `sunday` (D-17802).
  final String startOfWeek;

  const SignalContext({
    required this.now,
    required this.window,
    required this.mix,
    required this.progressService,
    required this.repository,
    this.startOfWeek = 'monday',
  });
}
