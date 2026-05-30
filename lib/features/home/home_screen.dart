import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/services/routine_session_service.dart';
import '../../core/services/session_summary_service.dart';
import '../../state/workout/workout_state.dart';
import '../../state/home/home_state.dart';
import '../../state/routine/routine_state.dart';
import '../../state/calendar/calendar_state.dart';
import '../../state/period/period_state.dart';
import '../../state/profile/profile_state.dart';
import '../../state/settings/settings_state.dart';
import '../../core/constants/home_tiles.dart';
import '../../core/constants/omni_theme.dart';
import '../../core/navigation/navigation.dart';
import '../../widgets/cards/energy_tile.dart';
import '../../widgets/cards/maintenance_tile.dart';
import '../session/workout_session_screen.dart';
import '../routine/my_routines_screen.dart';
import '../calendar/calendar_screen.dart';
import '../profile/profile_screen.dart';
import '../settings/settings_screen.dart';
import '../stats/stats_screen.dart';
import '../../core/utils/timer_alert_service.dart';
import '../../core/utils/rest_notification_service.dart';

class HomeScreen extends StatefulWidget {
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
  final RestNotificationService restNotificationService;

  HomeScreen({
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
    required this.timerAlertService,
    RestNotificationService? restNotificationService,
  }) : restNotificationService =
           restNotificationService ?? RestNotificationService.noop();

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  static const double _minSheetExtent = 0.10;
  double _maxSheetExtent = 0.9;

  late final DraggableScrollableController _sheetController;
  late final ValueNotifier<double> _sheetExtent;
  late final AnimationController _hintController;
  late final Animation<double> _hintOffset;

  bool _resumeCheckDone = false;

  @override
  void initState() {
    super.initState();
    if (!_resumeCheckDone) {
      widget.workoutState.checkForInProgressSession();
      _resumeCheckDone = true;
    }

    _sheetController = DraggableScrollableController();
    _sheetExtent = ValueNotifier<double>(_minSheetExtent);

    // Silent session restoration logic
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || widget.workoutState.hasActiveSession) return;
      final session = await widget.workoutState.checkForInProgressSession();
      if (session != null && mounted) {
        await widget.workoutState.loadHistoricalSession(session.id);
      }
    });

    _sheetExtent.addListener(_onSheetExtentChanged);
    _hintController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _hintOffset = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.0,
          end: -5.0,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: -5.0,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 50,
      ),
    ]).animate(_hintController);

    if (widget.homeState.shouldShowMaintenanceHint) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_playHintAnimationBurst());
      });
    }
  }

  @override
  void dispose() {
    _sheetController.dispose();
    _sheetExtent.removeListener(_onSheetExtentChanged);
    _sheetExtent.dispose();
    _hintController.dispose();
    super.dispose();
  }

  void _onSheetExtentChanged() {
    // Stop animation if user pulls the sheet beyond minimum extent
    if (_sheetExtent.value > _minSheetExtent + 0.01) {
      if (_hintController.isAnimating) {
        _hintController.stop();
        unawaited(widget.homeState.markMaintenanceHintSeen());
      }
    }
  }

  Future<void> _playHintAnimationBurst() async {
    if (_hintController.isAnimating) return;

    try {
      for (var i = 0; i < 3 && mounted; i++) {
        await _hintController.forward(from: 0.0);
        if (!mounted) return;
        await _hintController.reverse();
      }
      _hintController.value = 0.0;
    } on TickerCanceled {
      // Animation was stopped because the widget was disposed or the user
      // interacted with the maintenance sheet.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Image.asset(
          'assets/icon/omnitrain_logo.png',
          height: 40,
          width: 40,
        ),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 15.0, 16.0, 0.0),
              child: Column(
                children: [
                  Text(
                    'TRAIN',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.0,
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
                  const SizedBox(height: 30),
                  // Grid view with training modalities
                  Expanded(
                    child: ListenableBuilder(
                      listenable: widget.workoutState,
                      builder: (context, child) {
                        const standardGridSpacing = 16.0;
                        const utilitySectionGap = standardGridSpacing * 1.7;

                        final session = widget.workoutState.currentSession;
                        final isRoutineSession = session?.intent == 'routine';
                        final hasActiveSession =
                            widget.workoutState.hasActiveSession;

                        final tiles = HomeTiles.all
                            .map((tile) {
                              final isActive =
                                  hasActiveSession &&
                                  (tile.key == 'my_routines'
                                      ? isRoutineSession
                                      : tile.modality == null
                                      ? session?.modality == null &&
                                            !isRoutineSession
                                      : session?.modality == tile.modality);

                              return EnergyTile(
                                title: tile.label,
                                icon: tile.iconData,
                                iconWidget: tile.iconWidget,
                                gradientColors: tile.gradientColors,
                                accentColor: tile.accentColor,
                                isActive: isActive,
                                onTap: () =>
                                    _handleTileTap(context, tile, isActive),
                              );
                            })
                            .toList(growable: false);

                        return CustomScrollView(
                          slivers: [
                            SliverGrid(
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    mainAxisSpacing: standardGridSpacing,
                                    crossAxisSpacing: standardGridSpacing,
                                    childAspectRatio: 1.0,
                                  ),
                              delegate: SliverChildBuilderDelegate((
                                context,
                                index,
                              ) {
                                return tiles[index];
                              }, childCount: 4),
                            ),
                            const SliverToBoxAdapter(
                              child: SizedBox(height: utilitySectionGap),
                            ),
                            SliverGrid(
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    crossAxisSpacing: standardGridSpacing,
                                    childAspectRatio: 1.0,
                                  ),
                              delegate: SliverChildBuilderDelegate((
                                context,
                                index,
                              ) {
                                return tiles[index + 4];
                              }, childCount: 2),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          _buildMaintenanceSheet(context),
        ],
      ),
    );
  }

  /// Handle tile tap - route to appropriate screen based on tile type
  /// Modality tiles (cardio, resistance, sports, isometric, free training) start sessions
  /// Special tiles (my routines) navigate to feature screens
  Future<void> _handleTileTap(
    BuildContext context,
    HomeTileConfig tile,
    bool isActive,
  ) async {
    // Special case: My Routines tile
    if (tile.key == 'my_routines') {
      if (isActive) {
        OmniNavigator.push(
          context,
          (_) => WorkoutSessionScreen(
            workoutState: widget.workoutState,
            routineState: widget.routineState,
            sessionSummaryService: widget.sessionSummaryService,
            settingsState: widget.settingsState,
            timerAlertService: widget.timerAlertService,
            restNotificationService: widget.restNotificationService,
          ),
        );
      } else {
        // Guard: any active session (rolling or otherwise) conflicts with
        // starting a routine, which would create a new competing session.
        if (widget.workoutState.hasActiveSession) {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Start New Session?'),
              content: const Text(
                'Opening a routine will start a new session. Current session will be saved.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: ButtonStyle(
                    shape: WidgetStateProperty.all(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          OmniTheme.buttonUtilityRadius,
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ButtonStyle(
                    shape: WidgetStateProperty.all(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          OmniTheme.buttonUtilityRadius,
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Continue'),
                ),
              ],
            ),
          );
          if (confirmed != true) return;
          widget.workoutState.clearSession();
        }
        if (context.mounted) {
          OmniNavigator.push(
            context,
            (_) => MyRoutinesScreen(
              routineState: widget.routineState,
              workoutState: widget.workoutState,
              routineSessionService: widget.routineSessionService,
              sessionSummaryService: widget.sessionSummaryService,
              settingsState: widget.settingsState,
              timerAlertService: widget.timerAlertService,
              restNotificationService: widget.restNotificationService,
            ),
          );
        }
      }
      return;
    }

    // All other tiles are modality-based workout tiles (including Free Training).
    // If tapping the currently active tile, navigate directly to the session.
    if (isActive) {
      OmniNavigator.push(
        context,
        (_) => WorkoutSessionScreen(
          workoutState: widget.workoutState,
          routineState: widget.routineState,
          sessionSummaryService: widget.sessionSummaryService,
          settingsState: widget.settingsState,
          preferredModality: tile.modality,
          timerAlertService: widget.timerAlertService,
          restNotificationService: widget.restNotificationService,
        ),
      );
      return;
    }

    // Tapping an inactive tile while a session is active:
    if (widget.workoutState.hasActiveSession) {
      if (widget.workoutState.isRollingSession) {
        // Rolling session: navigate directly — no dialog, no new session.
        // Pass the tapped tile's modality so ExercisePickerScreen pre-filters.
        OmniNavigator.push(
          context,
          (_) => WorkoutSessionScreen(
            workoutState: widget.workoutState,
            routineState: widget.routineState,
            sessionSummaryService: widget.sessionSummaryService,
            settingsState: widget.settingsState,
            preferredModality: tile.modality,
            timerAlertService: widget.timerAlertService,
            restNotificationService: widget.restNotificationService,
          ),
        );
        return;
      }

      // Non-rolling: show conflict dialog before switching session.
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
              style: ButtonStyle(
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      OmniTheme.buttonUtilityRadius,
                    ),
                  ),
                ),
              ),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: ButtonStyle(
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      OmniTheme.buttonUtilityRadius,
                    ),
                  ),
                ),
              ),
              child: const Text('Start New'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    // Free Training tile (null modality): show rolling toggle start sheet.
    if (tile.modality == null) {
      if (context.mounted) {
        await _showFreeTrainingStartSheet(context);
      }
      return;
    }

    // Standard modality tile: clear any prior session and start a new one.
    widget.workoutState.clearSession();
    await widget.workoutState.createNewSession(modality: tile.modality);

    if (context.mounted) {
      OmniNavigator.push(
        context,
        (_) => WorkoutSessionScreen(
          workoutState: widget.workoutState,
          routineState: widget.routineState,
          sessionSummaryService: widget.sessionSummaryService,
          settingsState: widget.settingsState,
          preferredModality: tile.modality,
          timerAlertService: widget.timerAlertService,
          restNotificationService: widget.restNotificationService,
        ),
      );
    }
  }

  /// Shows a bottom sheet for starting a Free Training session.
  /// Includes a rolling toggle with inline guidance text.
  Future<void> _showFreeTrainingStartSheet(BuildContext context) async {
    bool isRolling = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (innerCtx, setSheetState) {
            final bottomPadding = MediaQuery.of(innerCtx).padding.bottom;
            final themeColors = OmniTheme.colorsForTheme(
              widget.settingsState.appTheme,
            );

            return Container(
              padding: EdgeInsets.fromLTRB(20, 0, 20, bottomPadding + 20),
              decoration: BoxDecoration(
                color: themeColors.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                border: Border(
                  top: BorderSide(
                    color: themeColors.surfaceBorder,
                    width: OmniTheme.surfaceBorderWidth,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.35),
                    blurRadius: 30,
                    offset: const Offset(0, -12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag handle
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 20),
                      child: Container(
                        width: 32,
                        height: 4,
                        decoration: BoxDecoration(
                          color: OmniTheme.textSecondary.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  Text(
                    'Free Training',
                    style: Theme.of(innerCtx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: OmniTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Rolling Session'),
                    subtitle: const Text(
                      'A rolling session stays open all day. Tap any tile to return and '
                      'add more work at any time. No session timer — just your sets.',
                    ),
                    value: isRolling,
                    onChanged: (value) =>
                        setSheetState(() => isRolling = value),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: OmniTheme.buttonPrimaryHeight,
                    width: double.infinity,
                    child: FilledButton(
                      style: ButtonStyle(
                        shape: WidgetStateProperty.all(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              OmniTheme.buttonBorderRadius,
                            ),
                          ),
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(innerCtx).pop();
                        _startFreeSession(context, isRolling: isRolling);
                      },
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Start Session'),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Creates a free training session (with optional rolling flag) and navigates
  /// to the session screen.
  Future<void> _startFreeSession(
    BuildContext context, {
    required bool isRolling,
  }) async {
    widget.workoutState.clearSession();
    await widget.workoutState.createNewSession(isRolling: isRolling);
    if (context.mounted) {
      OmniNavigator.push(
        context,
        (_) => WorkoutSessionScreen(
          workoutState: widget.workoutState,
          routineState: widget.routineState,
          sessionSummaryService: widget.sessionSummaryService,
          settingsState: widget.settingsState,
          timerAlertService: widget.timerAlertService,
          restNotificationService: widget.restNotificationService,
        ),
      );
    }
  }

  Widget _buildMaintenanceSheet(BuildContext context) {
    final mq = MediaQuery.of(context);
    // `context` here is the outer Scaffold context, so `padding.top` is the
    // status-bar safe-area only.  Add `kToolbarHeight` explicitly to account
    // for the transparent AppBar so the sheet top lands at the TRAIN title
    // level instead of covering the logo.
    _maxSheetExtent =
        ((mq.size.height - mq.padding.top - kToolbarHeight) / mq.size.height)
            .clamp(0.5, 0.9);

    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (notification) {
        _sheetExtent.value = notification.extent;
        return false;
      },
      child: DraggableScrollableSheet(
        controller: _sheetController,
        minChildSize: _minSheetExtent,
        maxChildSize: _maxSheetExtent,
        initialChildSize: _minSheetExtent,
        snap: true,
        snapSizes: [_minSheetExtent, _maxSheetExtent],
        builder: (context, scrollController) {
          return ValueListenableBuilder<double>(
            valueListenable: _sheetExtent,
            builder: (context, extent, child) {
              final t =
                  ((extent - _minSheetExtent) /
                          (_maxSheetExtent - _minSheetExtent))
                      .clamp(0.0, 1.0);
              final contentOpacity = t.clamp(0.0, 1.0);
              final slideOffset = 20.0 * (1.0 - t);

              final sheetColors = OmniTheme.colorsForTheme(
                widget.settingsState.appTheme,
              );
              return Container(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  color: sheetColors.surface,
                  border: Border(
                    top: BorderSide(
                      color: sheetColors.surfaceBorder,
                      width: OmniTheme.surfaceBorderWidth,
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.35),
                      blurRadius: 30,
                      offset: const Offset(0, -12),
                    ),
                  ],
                ),
                child: CustomScrollView(
                  controller: scrollController,
                  slivers: [
                    SliverToBoxAdapter(child: _buildHandle()),
                    SliverToBoxAdapter(
                      child: IgnorePointer(
                        ignoring: contentOpacity < 0.05,
                        child: Opacity(
                          opacity: contentOpacity,
                          child: Transform.translate(
                            offset: Offset(0, slideOffset),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'HUB',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: OmniTheme.textSecondary
                                              .withOpacity(0.7),
                                          letterSpacing: 3.0,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      sliver: SliverToBoxAdapter(
                        child: IgnorePointer(
                          ignoring: contentOpacity < 0.05,
                          child: Opacity(
                            opacity: contentOpacity,
                            child: Transform.translate(
                              offset: Offset(0, slideOffset),
                              child: _buildMaintenanceGrid(context),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildHandle() {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 12),
      child: Center(
        child: GestureDetector(
          onTap: () => _snapSheet(_maxSheetExtent),
          child: AnimatedBuilder(
            animation: _hintOffset,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(0, _hintOffset.value),
                child: child,
              );
            },
            child: Container(
              width: 50,
              height: 6,
              decoration: BoxDecoration(
                color: OmniTheme.colorsForTheme(
                  widget.settingsState.appTheme,
                ).primary.withOpacity(0.4),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMaintenanceGrid(BuildContext context) {
    final items = [
      _MaintenanceItem(
        title: 'Calendar',
        icon: Icons.calendar_today,
        onTap: () => OmniNavigator.push(
          context,
          (_) => CalendarScreen(
            calendarState: widget.calendarState,
            periodState: widget.periodState,
            workoutState: widget.workoutState,
            routineState: widget.routineState,
            routineSessionService: widget.routineSessionService,
            sessionSummaryService: widget.sessionSummaryService,
            settingsState: widget.settingsState,
            timerAlertService: widget.timerAlertService,
            restNotificationService: widget.restNotificationService,
          ),
        ),
      ),
      _MaintenanceItem(
        title: 'Stats',
        icon: Icons.query_stats,
        onTap: () => OmniNavigator.push(
          context,
          (_) => StatsScreen(
            workoutState: widget.workoutState,
            settingsState: widget.settingsState,
          ),
        ),
      ),
      _MaintenanceItem(
        title: 'Profile',
        icon: Icons.person_outline,
        onTap: () => OmniNavigator.push(
          context,
          (_) => ProfileScreen(
            profileState: widget.profileState,
            settingsState: widget.settingsState,
          ),
        ),
      ),
      _MaintenanceItem(
        title: 'Settings',
        icon: Icons.tune,
        onTap: () => OmniNavigator.push(
          context,
          (_) => SettingsScreen(
            settingsState: widget.settingsState,
            timerAlertService: widget.timerAlertService,
            restNotificationService: widget.restNotificationService,
          ),
        ),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 1.1,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return MaintenanceTile(
          title: item.title,
          icon: item.icon,
          onTap: item.onTap,
          activeTheme: widget.settingsState.appTheme,
        );
      },
    );
  }

  void _snapSheet(double extent) {
    _sheetController.animateTo(
      extent,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }
}

class _MaintenanceItem {
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  const _MaintenanceItem({
    required this.title,
    required this.icon,
    required this.onTap,
  });
}
