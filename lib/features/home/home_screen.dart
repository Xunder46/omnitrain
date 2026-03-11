import 'package:flutter/material.dart';
import '../../core/services/routine_session_service.dart';
import '../../core/services/session_summary_service.dart';
import '../../state/workout/workout_state.dart';
import '../../state/home/home_state.dart';
import '../../state/routine/routine_state.dart';
import '../../state/calendar/calendar_state.dart';
import '../../state/period/period_state.dart';
import '../../core/constants/home_tiles.dart';
import '../../core/constants/omni_theme.dart';
import '../../widgets/layout/omni_gradient_background.dart';
import '../../widgets/cards/energy_tile.dart';
import '../../widgets/cards/maintenance_tile.dart';
import '../session/workout_session_screen.dart';
import '../routine/my_routines_screen.dart';
import '../calendar/calendar_screen.dart';
import 'maintenance_placeholder_screen.dart';

class HomeScreen extends StatefulWidget {
  final WorkoutState workoutState;
  final HomeState homeState;
  final RoutineState routineState;
  final RoutineSessionService routineSessionService;
  final SessionSummaryService sessionSummaryService;
  final CalendarState calendarState;
  final PeriodState periodState;

  const HomeScreen({
    super.key,
    required this.workoutState,
    required this.homeState,
    required this.routineState,
    required this.routineSessionService,
    required this.sessionSummaryService,
    required this.calendarState,
    required this.periodState,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  static const double _minSheetExtent = 0.07;
  static const double _midSheetExtent = 0.45;
  static const double _maxSheetExtent = 0.92;

  late final DraggableScrollableController _sheetController;
  late final ValueNotifier<double> _sheetExtent;
  late final AnimationController _hintController;
  late final Animation<double> _hintOffset;

  @override
  void initState() {
    super.initState();
    _sheetController = DraggableScrollableController();
    _sheetExtent = ValueNotifier<double>(_minSheetExtent);

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
        _playHintAnimationTwice();
      });
    }
  }

  @override
  void dispose() {
    _sheetController.dispose();
    _sheetExtent.dispose();
    _hintController.dispose();
    super.dispose();
  }

  void _playHintAnimationTwice() {
    _hintController.forward().whenComplete(() {
      if (!mounted) return;
      _hintController.reset();
      _hintController.forward().whenComplete(() {
        if (mounted) {
          widget.homeState.markMaintenanceHintSeen();
        }
      });
    });
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
      body: OmniGradientBackground(
        child: Stack(
          children: [
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(30.0, 15.0, 16.0, 0.0),
                child: Column(
                  children: [
                    Text(
                      'TRAIN',
                      style: TextStyle(
                        fontSize: 18,
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
                          return GridView.count(
                            crossAxisCount: 2,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                            childAspectRatio: 1.0,
                            children: HomeTiles.all.map((tile) {
                              // Determine if this tile is the currently active session
                              final session =
                                  widget.workoutState.currentSession;
                              final isRoutineSession =
                                  session?.intent == 'routine';
                              final isActive =
                                  widget.workoutState.hasActiveSession &&
                                  (tile.key == 'my_routines'
                                      ? isRoutineSession
                                      : tile.modality == null
                                      ? session?.modality == null &&
                                            !isRoutineSession
                                      : session?.modality == tile.modality);

                              return EnergyTile(
                                title: tile.label,
                                icon: tile.iconData,
                                gradientColors: tile.gradientColors,
                                accentColor: tile.accentColor,
                                isActive: isActive,
                                onTap: () =>
                                    _handleTileTap(context, tile, isActive),
                              );
                            }).toList(),
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
    // Special case: My Routines tile navigates to routine screen
    if (tile.key == 'my_routines') {
      if (isActive) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => WorkoutSessionScreen(
              workoutState: widget.workoutState,
              routineState: widget.routineState,
              sessionSummaryService: widget.sessionSummaryService,
            ),
          ),
        );
      } else {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MyRoutinesScreen(
              routineState: widget.routineState,
              workoutState: widget.workoutState,
              routineSessionService: widget.routineSessionService,
              sessionSummaryService: widget.sessionSummaryService,
            ),
          ),
        );
      }
      return;
    }

    // All other tiles are modality-based workout tiles
    // If tapping active tile, navigate directly to session
    if (isActive) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => WorkoutSessionScreen(
            workoutState: widget.workoutState,
            routineState: widget.routineState,
            sessionSummaryService: widget.sessionSummaryService,
          ),
        ),
      );
      return;
    }

    // If tapping inactive tile and session is active, confirm before switching
    if (widget.workoutState.hasActiveSession) {
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
              style: ButtonStyle(
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
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

    // Start new session with selected modality
    widget.workoutState.clearSession();
    await widget.workoutState.createNewSession(modality: tile.modality);

    // Navigate to workout session screen
    if (context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => WorkoutSessionScreen(
            workoutState: widget.workoutState,
            routineState: widget.routineState,
            sessionSummaryService: widget.sessionSummaryService,
          ),
        ),
      );
    }
  }

  Widget _buildMaintenanceSheet(BuildContext context) {
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
        snapSizes: const [_minSheetExtent, _midSheetExtent, _maxSheetExtent],
        builder: (context, scrollController) {
          return ValueListenableBuilder<double>(
            valueListenable: _sheetExtent,
            builder: (context, extent, child) {
              final t = _extentToProgress(extent);
              final contentOpacity = t.clamp(0.0, 1.0);
              final slideOffset = 20.0 * (1.0 - t);

              return Container(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      OmniTheme.backgroundGradientTop,
                      OmniTheme.backgroundGradientBottom,
                    ],
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
                                    'SYSTEM',
                                    style: TextStyle(
                                      color: OmniTheme.textSecondary
                                          .withOpacity(0.7),
                                      fontSize: 12,
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
          onTap: () => _snapSheet(_midSheetExtent),
          child: AnimatedBuilder(
            animation: _hintOffset,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(0, _hintOffset.value),
                child: child,
              );
            },
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
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
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CalendarScreen(
              calendarState: widget.calendarState,
              periodState: widget.periodState,
              workoutState: widget.workoutState,
              routineState: widget.routineState,
              routineSessionService: widget.routineSessionService,
              sessionSummaryService: widget.sessionSummaryService,
            ),
          ),
        ),
      ),
      _MaintenanceItem(
        title: 'Stats',
        icon: Icons.query_stats,
        onTap: () => _openPlaceholder(
          context,
          title: 'Stats',
          description: 'Review performance trends and training history',
        ),
      ),
      _MaintenanceItem(
        title: 'Profile',
        icon: Icons.person_outline,
        onTap: () => _openPlaceholder(
          context,
          title: 'Profile',
          description: 'Manage your identity, preferences, and security layer',
        ),
      ),
      _MaintenanceItem(
        title: 'Settings',
        icon: Icons.tune,
        onTap: () => _openPlaceholder(
          context,
          title: 'Settings',
          description: 'Control system behavior, notifications, and defaults',
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

  double _extentToProgress(double extent) {
    final t = (extent - _minSheetExtent) / (_maxSheetExtent - _minSheetExtent);
    return t.clamp(0.0, 1.0);
  }

  void _openPlaceholder(
    BuildContext context, {
    required String title,
    required String description,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MaintenancePlaceholderScreen(
          title: title,
          description: description,
        ),
      ),
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
