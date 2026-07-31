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
import 'package:omnitrain/state/exercise/exercise_library_state.dart';
import 'package:omnitrain/core/services/exercise_library_service.dart';

/// Build a hydrated [NutritionPrimerState] from [repo]. Calls
/// `init()` so the persisted seen flag is read before the
/// first frame. Returns the state ready to be passed to
/// `HomeScreen(...)` or `NutritionScreen(...)`.
Future<NutritionPrimerState> buildNutritionPrimerState(
  WorkoutRepository repo,
) async {
  final state = NutritionPrimerState(repo);
  await state.init();
  return state;
}
