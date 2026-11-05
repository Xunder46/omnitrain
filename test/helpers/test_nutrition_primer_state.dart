// filepath: test/helpers/test_nutrition_primer_state.dart
//
// Tiny test helper for constructing a hydrated
// `NutritionPrimerState` against a `MockWorkoutRepository`.
//
// Every test that pumps `HomeScreen` or `NutritionScreen` needs
// to wire the primer state through the constructor. The
// helper centralises the (construct, init) pair so test
// files stay one line per state.

import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/nutrition/nutrition_primer_state.dart';

/// Build a hydrated [NutritionPrimerState] from [repo]. Calls
/// `init()` so the persisted seen flag is read before the
/// first frame. Returns the state ready to be passed to
/// `HomeScreen(...)` or `NutritionScreen(...)`.
///
/// Pass `seen: true` for a test that reaches `NutritionScreen`
/// directly and does not test the primer: with the default
/// `seen: false` the primer sheet rises over the screen on
/// first open and its barrier blocks taps.
Future<NutritionPrimerState> buildNutritionPrimerState(
  WorkoutRepository repo, {
  bool seen = false,
}) async {
  final state = NutritionPrimerState(repo);
  await state.init();
  if (seen) {
    await state.markSeen();
  }
  return state;
}
