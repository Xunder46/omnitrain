import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';
import '../../widgets/layout/omni_gradient_background.dart';

/// Placeholder screen for My Routines feature
/// Displays "Coming Soon" message with folder icon
/// Future: Will show list of saved workout routines and allow creation/editing
class MyRoutinesScreen extends StatelessWidget {
  const MyRoutinesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('My Routines'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: OmniGradientBackground(
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Folder icon
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: OmniTheme.textPrimary.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    Icons.folder_open,
                    size: 60,
                    color: OmniTheme.textPrimary.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 32),
                // Coming Soon text
                Text(
                  'Coming Soon',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: OmniTheme.textPrimary,
                    shadows: [
                      Shadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Description
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0),
                  child: Text(
                    'Save and organize your favorite workout routines for quick access',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: OmniTheme.textPrimary.withOpacity(0.7),
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
