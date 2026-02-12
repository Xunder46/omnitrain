import 'package:flutter/material.dart';
import '../../state/workout/workout_state.dart';
import '../../core/constants/home_tiles.dart';
import '../../core/constants/omni_theme.dart';
import '../../widgets/layout/omni_gradient_background.dart';
import '../../widgets/cards/energy_tile.dart';
import '../session/workout_session_screen.dart';

class HomeScreen extends StatelessWidget {
  final WorkoutState workoutState;

  const HomeScreen({super.key, required this.workoutState});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        title: const Text(
          'OMNITRAIN',
          style: TextStyle(
            fontSize: 16,
            letterSpacing: OmniTheme.headerLetterSpacing,
            fontWeight: FontWeight.w600,
            color: OmniTheme.backgroundGradientTop,
          ),
        ),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: OmniGradientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: ListenableBuilder(
              listenable: workoutState,
              builder: (context, child) {
                return GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 1.0,
                  children: HomeTiles.all.map((tile) {
                    // Determine if this tile is the currently active session
                    final isActive = workoutState.hasActiveSession &&
                        workoutState.currentSession?.modality == tile.modality;

                    return EnergyTile(
                      title: tile.label,
                      icon: tile.iconData,
                      gradientColors: tile.gradientColors,
                      isActive: isActive,
                      onTap: () => _handleTileTap(context, tile, isActive),
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Handle tile tap - either resume active session or start new one
  Future<void> _handleTileTap(
    BuildContext context,
    HomeTileConfig tile,
    bool isActive,
  ) async {
    // If tapping active tile, navigate directly to session
    if (isActive) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => WorkoutSessionScreen(workoutState: workoutState),
        ),
      );
      return;
    }

    // If tapping inactive tile and session is active, confirm before switching
    if (workoutState.hasActiveSession) {
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
    }

    // Start new session with selected modality
    workoutState.clearSession();
    await workoutState.createNewSession(modality: tile.modality);

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
