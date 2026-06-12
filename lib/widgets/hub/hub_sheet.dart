import 'package:flutter/material.dart';

import '../../features/calendar/calendar_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/stats/stats_screen.dart';
import '../../features/nutrition/nutrition_screen.dart';
import '../../state/calendar/calendar_state.dart';
import '../../state/food_library_state.dart';
import '../../state/nutrition_state.dart';
import '../../state/period/period_state.dart';
import '../../state/profile/profile_state.dart';
import '../../state/routine/routine_state.dart';
import '../../state/settings/settings_state.dart';
import '../../state/workout/workout_state.dart';
import '../../core/services/routine_session_service.dart';
import '../../core/services/session_summary_service.dart';
import '../../core/utils/timer_alert_service.dart';
import '../../core/utils/rest_notification_service.dart';
import '../../core/constants/omni_theme.dart';
import '../../widgets/cards/maintenance_tile.dart';

class HubSheet extends StatelessWidget {
  final ScrollController scrollController;
  final ProfileState profileState;
  final WorkoutState workoutState;
  final SettingsState settingsState;
  final TimerAlertService timerAlertService;
  final RestNotificationService restNotificationService;
  final CalendarState calendarState;
  final PeriodState periodState;
  final RoutineState routineState;
  final NutritionState nutritionState;
  final FoodLibraryState foodLibraryState;
  final RoutineSessionService routineSessionService;
  final SessionSummaryService sessionSummaryService;

  const HubSheet({
    super.key,
    required this.scrollController,
    required this.profileState,
    required this.workoutState,
    required this.settingsState,
    required this.timerAlertService,
    required this.restNotificationService,
    required this.calendarState,
    required this.periodState,
    required this.routineState,
    required this.nutritionState,
    required this.foodLibraryState,
    required this.routineSessionService,
    required this.sessionSummaryService,
  });

  @override
  Widget build(BuildContext context) {
    final themeColors = OmniTheme.colorsForTheme(settingsState.appTheme);
    
    final maintenanceItems = [
      _HubItem(
        title: 'Calendar',
        icon: Icons.calendar_today,
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => CalendarScreen(
              calendarState: calendarState,
              periodState: periodState,
              workoutState: workoutState,
              routineState: routineState,
              routineSessionService: routineSessionService,
              sessionSummaryService: sessionSummaryService,
              settingsState: settingsState,
              timerAlertService: timerAlertService,
              restNotificationService: restNotificationService,
            ),
          ));
        },
      ),
      _HubItem(
        title: 'Stats',
        icon: Icons.bar_chart,
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => StatsScreen(
              workoutState: workoutState,
              settingsState: settingsState,
            ),
          ));
        },
      ),
      _HubItem(
        title: 'Nutrition',
        icon: Icons.monitor_heart_outlined,
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => NutritionScreen(
              nutritionState: nutritionState,
              foodLibraryState: foodLibraryState,
            ),
          ));
        },
      ),
      _HubItem(
        title: 'Profile',
        icon: Icons.person_outline,
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => ProfileScreen(
              profileState: profileState,
              settingsState: settingsState,
            ),
          ));
        },
      ),
      _HubItem(
        title: 'Settings',
        icon: Icons.settings_outlined,
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => SettingsScreen(
              settingsState: settingsState,
              timerAlertService: timerAlertService,
              restNotificationService: restNotificationService,
            ),
          ));
        },
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: themeColors.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: ListView(
        controller: scrollController,
        children: [
          // Header with "HUB" title
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
            child: Text(
              'HUB',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: themeColors.textMuted,
              ),
            ),
          ),
          // Grid of maintenance items
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.0,
              children: maintenanceItems,
            ),
          ),
        ],
      ),
    );
  }
}

class _HubItem extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  const _HubItem({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MaintenanceTile(
      title: title,
      icon: icon,
      onTap: onTap,
      activeTheme: AppTheme.abyssalNeon,
    );
  }
}