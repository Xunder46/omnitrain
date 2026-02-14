import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';
import '../../state/workout/workout_state.dart';
import '../../state/home/home_state.dart';
import '../../widgets/layout/omni_gradient_background.dart';
import '../../widgets/logo/animated_zen_halo.dart';
import '../home/home_screen.dart';

/// OMNITRAIN Splash Screen
/// Displays animated Zen Event Horizon logo with app name
/// Auto-transitions to HomeScreen after configured duration
class OmniSplashScreen extends StatefulWidget {
  final WorkoutState workoutState;
  final HomeState homeState;
  final Duration duration;

  const OmniSplashScreen({
    super.key,
    required this.workoutState,
    required this.homeState,
    this.duration = OmniTheme.splashDuration,
  });

  @override
  State<OmniSplashScreen> createState() => _OmniSplashScreenState();
}

class _OmniSplashScreenState extends State<OmniSplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    // Fade-in animation for logo + text
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );

    _fadeController.forward();

    // Auto-navigate after splash duration
    Future.delayed(widget.duration, () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                HomeScreen(
                  workoutState: widget.workoutState,
                  homeState: widget.homeState,
                ),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
              return FadeTransition(
                opacity: animation,
                child: child,
              );
            },
            transitionDuration: const Duration(milliseconds: 600),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: OmniGradientBackground(
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Zen Event Horizon Logo
                const AnimatedZenHalo(
                  size: 160.0,
                ),
                const SizedBox(height: 32),
                // App Name
                Text(
                  'OMNITRAIN',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 4.0,
                    color: Colors.white.withOpacity(0.85),
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
