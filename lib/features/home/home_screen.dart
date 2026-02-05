import 'package:flutter/material.dart';
import '../../state/workout/workout_state.dart';
import '../session/workout_session_screen.dart';

class HomeScreen extends StatelessWidget {
  final WorkoutState workoutState;

  const HomeScreen({super.key, required this.workoutState});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Omnitrain'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: FilledButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Text('New Workout Session'),
            onPressed: () async {
              if (!workoutState.hasSession) {
                await workoutState.createNewSession();
              }
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => WorkoutSessionScreen(workoutState: workoutState),
              ));
            },
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
          ),
        ),
      ),
    );
  }
}
