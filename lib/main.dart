import 'package:flutter/material.dart';
import 'app.dart';
import 'data/repositories/mock_workout_repository.dart';
import 'state/workout/workout_state.dart';
import 'state/home/home_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // Initialize repository (web-compatible, in-memory)
    final repository = MockWorkoutRepository();
    await repository.initialize();

    // Create state with repository
    final workoutState = WorkoutState(repository);
    final homeState = HomeState();

    runApp(MyApp(
      workoutState: workoutState,
      homeState: homeState,
    ));
  } catch (e) {
    print('Error initializing app: $e');
    runApp(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('Error initializing app. Check console for details.'),
        ),
      ),
    ));
  }
}

