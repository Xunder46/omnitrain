import 'fuel_vs_load_signal.dart';
import 'interference_signal.dart';
import 'modality_mix_shift_signal.dart';
import 'progression_rate_signal.dart';
import 'signal.dart';

/// The signals the Stats screen evaluates, in evaluation order (D-1016).
///
/// This is the only place a signal is registered. The layer, the service and
/// the screen never name a concrete signal; a new signal is one line here.
List<Signal> buildSignalRegistry() => const <Signal>[
  FuelVsLoadSignal(),
  ProgressionRateSignal(),
  ModalityMixShiftSignal(),
  InterferenceSignal(),
];
