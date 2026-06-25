import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';
import '../../core/navigation/navigation.dart';
import '../../core/services/routine_session_service.dart';
import '../../core/services/session_summary_service.dart';
import '../../state/food_library_state.dart';
import '../../state/nutrition_state.dart';
import '../../state/nutrition/nutrition_primer_state.dart';
import '../../state/workout/workout_state.dart';
import '../../state/home/home_state.dart';
import '../../state/routine/routine_state.dart';
import '../../state/calendar/calendar_state.dart';
import '../../state/period/period_state.dart';
import '../../state/profile/profile_state.dart';
import '../../state/settings/settings_state.dart';
import '../../core/utils/timer_alert_service.dart';
import '../../core/utils/rest_notification_service.dart';
import '../../widgets/logo/animated_zen_halo.dart';
import '../home/home_screen.dart';

/// OMNITRAIN Splash Screen
/// Displays animated Zen Event Horizon logo with app name
/// Auto-transitions to HomeScreen after configured duration
class OmniSplashScreen extends StatefulWidget {
  final WorkoutState workoutState;
  final HomeState homeState;
  final RoutineState routineState;
  final RoutineSessionService routineSessionService;
  final SessionSummaryService sessionSummaryService;
  final CalendarState calendarState;
  final PeriodState periodState;
  final ProfileState profileState;
  final SettingsState settingsState;
  final NutritionState nutritionState;
  final FoodLibraryState foodLibraryState;
  final NutritionPrimerState nutritionPrimerState;
  final TimerAlertService timerAlertService;
  final RestNotificationService restNotificationService;
  final Duration duration;

  OmniSplashScreen({
    super.key,
    required this.workoutState,
    required this.homeState,
    required this.routineState,
    required this.routineSessionService,
    required this.sessionSummaryService,
    required this.calendarState,
    required this.periodState,
    required this.profileState,
    required this.settingsState,
    required this.nutritionState,
    required this.foodLibraryState,
    required this.nutritionPrimerState,
    required this.timerAlertService,
    RestNotificationService? restNotificationService,
    this.duration = OmniTheme.splashDuration,
  }) : restNotificationService =
           restNotificationService ?? RestNotificationService.noop();

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
        OmniNavigator.pushReplacementFade(
          context,
          (_) => HomeScreen(
            workoutState: widget.workoutState,
            homeState: widget.homeState,
            routineState: widget.routineState,
            routineSessionService: widget.routineSessionService,
            sessionSummaryService: widget.sessionSummaryService,
            calendarState: widget.calendarState,
            periodState: widget.periodState,
            profileState: widget.profileState,
            settingsState: widget.settingsState,
            timerAlertService: widget.timerAlertService,
            restNotificationService: widget.restNotificationService,
            nutritionState: widget.nutritionState,
            foodLibraryState: widget.foodLibraryState,
            nutritionPrimerState: widget.nutritionPrimerState,
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
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Zen Event Horizon Logo
              const AnimatedZenHalo(size: 160.0),
              const SizedBox(height: 32),
              // App Name
              Text(
                'OMNITRAIN',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 4.0,
                  color: Colors.white.withOpacity(0.85),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
