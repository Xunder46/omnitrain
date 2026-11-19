import '../../models/consistency.dart';
import '../../models/signals.dart';
import 'session_history.dart';
import 'signal.dart';

const String _kTrainingGapTitle = 'Training gap';

/// Proposes the Training Gap card, or abstains (D-17804).
class TrainingGapSignal implements Signal {
  const TrainingGapSignal();

  @override
  String get id => 'training-gap';

  @override
  SignalKind get kind => SignalKind.caution;

  @override
  int get priority => kTrainingGapPriority;

  @override
  bool get needsRatedWeeks => false;

  @override
  Future<String?> waitingFor(SignalContext context) async => null;

  @override
  Future<SignalCard?> evaluate(SignalContext context) async {
    final result = trainingGap(
      sessionStarts: await completedSessionStarts(context),
      now: context.now,
      startOfWeek: context.startOfWeek,
    );
    if (result == null) return null;
    return SignalCard(
      id: id,
      kind: kind,
      priority: priority,
      title: _kTrainingGapTitle,
      observation: trainingGapObservation(result),
    );
  }
}
