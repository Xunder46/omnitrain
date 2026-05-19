import 'package:flutter/material.dart';

import '../../core/constants/modality_colors.dart';
import '../../core/constants/omni_theme.dart';
import '../../core/services/routine_session_service.dart';
import '../../core/services/session_summary_service.dart';
import '../../core/navigation/navigation.dart';
import '../../data/repositories/workout_repository.dart';
import '../../state/calendar/calendar_state.dart';
import '../../state/home/home_state.dart';
import '../../state/period/period_state.dart';
import '../../state/profile/profile_state.dart';
import '../../state/routine/routine_state.dart';
import '../../state/settings/settings_state.dart';
import '../../state/workout/workout_state.dart';
import '../../widgets/layout/omni_surface.dart';
import '../../core/utils/timer_alert_service.dart';
import '../home/home_screen.dart';

/// First-launch onboarding flow — three swipeable pages.
/// Shown once on fresh install; never shown again after dismissal.
/// Completion flag: WorkoutRepository.setPreferenceBool('onboarding_complete', true)
class OnboardingScreen extends StatefulWidget {
  final WorkoutRepository repository;
  final WorkoutState workoutState;
  final HomeState homeState;
  final RoutineState routineState;
  final RoutineSessionService routineSessionService;
  final SessionSummaryService sessionSummaryService;
  final CalendarState calendarState;
  final PeriodState periodState;
  final ProfileState profileState;
  final SettingsState settingsState;
  final TimerAlertService timerAlertService;

  const OnboardingScreen({
    super.key,
    required this.repository,
    required this.workoutState,
    required this.homeState,
    required this.routineState,
    required this.routineSessionService,
    required this.sessionSummaryService,
    required this.calendarState,
    required this.periodState,
    required this.profileState,
    required this.settingsState,
    required this.timerAlertService,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final PageController _pageController;
  int _currentPage = 0;
  static const int _pageCount = 3;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _complete(BuildContext context) async {
    await widget.repository.setPreferenceBool('onboarding_complete', true);
    if (!context.mounted) return;
    OmniNavigator.pushReplacement(
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeColors = OmniTheme.colorsForTheme(OmniTheme.activeTheme);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // ─── Page content ───────────────────────────────────────────
          PageView(
            controller: _pageController,
            onPageChanged: (i) => setState(() => _currentPage = i),
            children: [
              _buildWelcomePage(context, themeColors),
              _buildHowYouTrainPage(context, themeColors),
              _buildHowYouPlanPage(context, themeColors),
            ],
          ),

          // ─── Top bar: Skip button (hidden on last page) ──────────────
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: AnimatedOpacity(
                opacity: _currentPage < _pageCount - 1 ? 1.0 : 0.0,
                duration: OmniTheme.animationDuration,
                child: IgnorePointer(
                  ignoring: _currentPage >= _pageCount - 1,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: themeColors.textMuted,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          OmniTheme.buttonUtilityRadius,
                        ),
                      ),
                    ),
                    onPressed: () => _complete(context),
                    child: const Text('Skip'),
                  ),
                ),
              ),
            ),
          ),

          // ─── Bottom: Page dots ───────────────────────────────────────
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 32),
                child: _PageDots(
                  count: _pageCount,
                  current: _currentPage,
                  activeColor: themeColors.primary,
                  inactiveColor: themeColors.textMuted.withValues(alpha: 0.35),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Page 1: Welcome ─────────────────────────────────────────────────────────
  Widget _buildWelcomePage(BuildContext context, OmniThemeColors themeColors) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/icon/omnitrain_logo.png',
              width: 120,
              height: 120,
            ),
            const SizedBox(height: 36),
            Text(
              'OMNITRAIN',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 3.0,
                color: themeColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'one app for every way you train',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w400,
                color: themeColors.textMuted,
              ),
            ),
            // Space to keep content clear of the page dots
            const SizedBox(height: 64),
          ],
        ),
      ),
    );
  }

  // ── Page 2: How You Train ────────────────────────────────────────────────────
  Widget _buildHowYouTrainPage(BuildContext context, OmniThemeColors themeColors) {
    const modalities = [
      _ModalityData(
        name: 'Cardio / Endurance',
        description: 'Continuous time and distance based activities',
        color: ModalityColors.cardioEndurance,
      ),
      _ModalityData(
        name: 'Resistance / Lifting',
        description: 'Set, rep, and load based strength training',
        color: ModalityColors.resistanceLifting,
      ),
      _ModalityData(
        name: 'Sports',
        description:
            'Round and time based training for martial arts and sports',
        color: ModalityColors.sports,
      ),
      _ModalityData(
        name: 'Isometric / Stretching',
        description: 'Hold based exercises and mobility work',
        color: ModalityColors.isometricStretching,
      ),
      _ModalityData(
        name: 'Free Training',
        description: 'Mix anything, no modality constraint',
        color: ModalityColors.freeTraining,
      ),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 32),
            Text(
              'How You Train',
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: themeColors.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'OmniTrain adapts its interface to the way you actually train.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: themeColors.textMuted,
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.separated(
                itemCount: modalities.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                padding: const EdgeInsets.only(bottom: 72),
                itemBuilder: (_, index) =>
                    _ModalityTile(data: modalities[index]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Page 3: How You Plan ─────────────────────────────────────────────────────
  Widget _buildHowYouPlanPage(
    BuildContext context,
    OmniThemeColors themeColors,
  ) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 32),
            Text(
              'How You Plan',
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: themeColors.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your training calendar keeps everything in one place.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: themeColors.textMuted,
              ),
            ),
            const SizedBox(height: 28),
            _PlanFeatureBullet(
              icon: Icons.calendar_today_outlined,
              text: 'Schedule upcoming training sessions by day',
              themeColors: themeColors,
            ),
            const SizedBox(height: 16),
            _PlanFeatureBullet(
              icon: Icons.flag_outlined,
              text: 'Create named training periods and goals',
              themeColors: themeColors,
            ),
            const SizedBox(height: 16),
            _PlanFeatureBullet(
              icon: Icons.history_outlined,
              text: 'Review your full session history at a glance',
              themeColors: themeColors,
            ),
            const Spacer(),
            // "Get Started" CTA
            SizedBox(
              height: OmniTheme.buttonPrimaryHeight,
              width: double.infinity,
              child: FilledButton(
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.all(themeColors.primary),
                  foregroundColor: WidgetStateProperty.all(
                    const Color(0xFF060B14),
                  ),
                  shape: WidgetStateProperty.all(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        OmniTheme.buttonBorderRadius,
                      ),
                    ),
                  ),
                ),
                onPressed: () => _complete(context),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Get Started',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 72),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────
// Private widget: Page indicator dots
// ────────────────────────────────────────────────────────────────────────────────

class _PageDots extends StatelessWidget {
  final int count;
  final int current;
  final Color activeColor;
  final Color inactiveColor;

  const _PageDots({
    required this.count,
    required this.current,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (i) {
        final isActive = i == current;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: AnimatedContainer(
            duration: OmniTheme.animationDuration,
            curve: OmniTheme.animationCurve,
            width: isActive ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: isActive ? activeColor : inactiveColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        );
      }),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────
// Private data class: modality tile data
// ────────────────────────────────────────────────────────────────────────────────

class _ModalityData {
  final String name;
  final String description;
  final Color color;

  const _ModalityData({
    required this.name,
    required this.description,
    required this.color,
  });
}

// ────────────────────────────────────────────────────────────────────────────────
// Private widget: single modality tile
// ────────────────────────────────────────────────────────────────────────────────

class _ModalityTile extends StatelessWidget {
  final _ModalityData data;

  const _ModalityTile({required this.data});

  @override
  Widget build(BuildContext context) {
    final themeColors = OmniTheme.colorsForTheme(OmniTheme.activeTheme);

    return OmniSurface(
      padding: EdgeInsets.zero,
      showShadow: false,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(OmniTheme.surfaceBorderRadius),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Accent color bar
              Container(width: 4, color: data.color),
              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: data.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              data.name,
                              maxLines: 2,
                              softWrap: true,
                              overflow: TextOverflow.visible,
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: OmniTheme.textPrimary,
                                letterSpacing: OmniTheme.titleLetterSpacing,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 18),
                        child: Text(
                          data.description,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: themeColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────
// Private widget: plan feature bullet row
// ────────────────────────────────────────────────────────────────────────────────

class _PlanFeatureBullet extends StatelessWidget {
  final IconData icon;
  final String text;
  final OmniThemeColors themeColors;

  const _PlanFeatureBullet({
    required this.icon,
    required this.text,
    required this.themeColors,
  });

  @override
  Widget build(BuildContext context) {
    return OmniSurface(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      showShadow: false,
      child: Row(
        children: [
          Icon(icon, color: themeColors.primary, size: 22),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: OmniTheme.textPrimary,
                letterSpacing: OmniTheme.titleLetterSpacing,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
