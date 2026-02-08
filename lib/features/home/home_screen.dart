import 'package:flutter/material.dart';
import '../../state/workout/workout_state.dart';
import '../../core/constants/home_tiles.dart';
import '../../widgets/cards/modality_tile_widget.dart';
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
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 1.0,
            children: HomeTiles.all.map((tile) {
              return ModalityTile(
                config: tile,
                onTap: () => _startWorkout(context, tile),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  /// Start a workout session with the selected modality
  Future<void> _startWorkout(BuildContext context, HomeTileConfig tile) async {
    // Check if there's an active session
    if (workoutState.hasActiveSession) {
      // Show warning dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Start New Session?'),
          content: const Text(
            'Changing modality will start a new session. Current session will be saved.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Start New'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
      
      // Clear current session
      workoutState.clearSession();
    }

    // Create new session with the tile's modality (null for Free Training)
    if (!workoutState.hasSession) {
      await workoutState.createNewSession(modality: tile.modality);
    }

    // Navigate to workout session screen
    if (context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => WorkoutSessionScreen(workoutState: workoutState),
        ),
      );
    }
  }
}
