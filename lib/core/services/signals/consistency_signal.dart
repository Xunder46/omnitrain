import '../../models/consistency.dart';
import '../../models/signals.dart';
import 'session_history.dart';
import 'signal.dart';

const String _kConsistencyTitle = 'Consistency';

/// Proposes the Consistency card, or abstains (D-17804).
class ConsistencySignal implements Signal {
  const ConsistencySignal();

  @override
  String get id => 'consistency';

  @override
  SignalKind get kind => SignalKind.positive;

  @override
  int get priority => kConsistencyPriority;

  @override
  bool get needsRatedWeeks => false;

  @override
  Future<String?> waitingFor(SignalContext context) async => null;

  @override
  Future<SignalCard?> evaluate(SignalContext context) async {
    final result = consistency(
      sessionStarts: await completedSessionStarts(context),
      now: context.now,
      startOfWeek: context.startOfWeek,
    );
    if (result == null) return null;
    return SignalCard(
      id: id,
      kind: kind,
      priority: priority,
      title: _kConsistencyTitle,
      observation: consistencyObservation(result),
    );
  }
}
