import '../../models/hold_progress.dart';
import '../../models/signals.dart';
import '../stats_progress_service.dart';
import 'signal.dart';

const String _kHoldProgressTitle = 'Hold progress';

/// Proposes the Hold Progress card, or abstains (D-17903).
class HoldProgressSignal implements Signal {
  const HoldProgressSignal();

  @override
  String get id => 'hold-progress';

  @override
  SignalKind get kind => SignalKind.positive;

  @override
  int get priority => kHoldProgressPriority;

  @override
  bool get needsRatedWeeks => false;

  @override
  Future<String?> waitingFor(SignalContext context) async => null;

  @override
  Future<SignalCard?> evaluate(SignalContext context) async {
    final sections = await context.progressService.computeInstrumentSections(
      window: context.window,
    );
    final result = holdProgress(sections);
    if (result == null) return null;
    return SignalCard(
      id: id,
      kind: kind,
      priority: priority,
      title: _kHoldProgressTitle,
      observation: holdProgressObservation(
        result,
        weeks: StatsProgressService.kStatsWindowDays ~/ 7,
      ),
    );
  }
}
