// filepath: test/helpers/test_stats_primer_state.dart
//
// Tiny test helper for constructing a hydrated
// `StatsPrimerState` against a `WorkoutRepository`.
//
// Every test that pumps `HomeScreen` with the Stats primer
// injected needs to wire the state through the constructor. The
// helper centralises the (construct, init) pair so test
// files stay one line per state, mirroring
// `test/helpers/test_nutrition_primer_state.dart`.

import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/stats/stats_primer_state.dart';

/// Build a hydrated [StatsPrimerState] from [repo]. Calls
/// `init()` so the persisted seen flag is read before the
/// first frame. Returns the state ready to be passed to
/// `HomeScreen(...)`.
Future<StatsPrimerState> buildStatsPrimerState(WorkoutRepository repo) async {
  final state = StatsPrimerState(repo);
  await state.init();
  return state;
}
