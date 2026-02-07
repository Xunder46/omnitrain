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
