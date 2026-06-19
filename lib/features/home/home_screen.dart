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
import 'widgets/nutrition_strip_bar.dart';
import '../../core/utils/timer_alert_service.dart';
import '../../core/utils/rest_notification_service.dart';
import '../../widgets/common/home_logo_button.dart';
import '../../state/nutrition_state.dart';
import '../../state/food_library_state.dart';
import '../nutrition/nutrition_screen.dart';

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
  final NutritionState nutritionState;
  final FoodLibraryState foodLibraryState;

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
    required this.nutritionState,
    required this.foodLibraryState,
    RestNotificationService? restNotificationService,
  }) : restNotificationService =
           restNotificationService ?? RestNotificationService.noop();

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  static const double _minSheetExtent = 0.0;
  double _maxSheetExtent = 0.9;

  late final DraggableScrollableController _sheetController;
  late final ValueNotifier<double> _sheetExtent;
  late final AnimationController _hintController;
  late final Animation<double> _hintOffset;

  bool _resumeCheckDone = false;
  late int _lastSeenDate; // Track the last date we checked for rollover

  @override
  void initState() {
    super.initState();
    if (!_resumeCheckDone) {
      widget.workoutState.checkForInProgressSession();
      _resumeCheckDone = true;
    }

    // Initialize last seen date for rollover detection
    _initializeLastSeenDate();

    _sheetController = DraggableScrollableController();
    _sheetExtent = ValueNotifier<double>(_minSheetExtent);

    // Phase 4.1 (D-5 / D-8 / S-054 / S-055): load today's
    // target + consumed foods on first paint so the home
    // nutrition strip renders real values without a
    // navigation.
    //
    // Implementation note: the loads run on a `Future.delayed`
    // (not `addPostFrameCallback`) so the notifyListeners
    // fired by `loadNutritionTarget` / `loadConsumedToday` happen
    // on a fresh microtask boundary, not on a post-frame boundary
    // that can be interleaved with the navigation transition's
    // own build. This avoids tripping Flutter's
    // "setState/markNeedsBuild during build" assertion when the
    // user taps the strip right after the home screen mounts:
    // the notify is scheduled for a stable frame boundary.
    //
    // The future is fire-and-forget; the loads run in the
    // background and notify listeners when complete.
    unawaited(_runInitialLoad());

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

  /// Initial-load coroutine. Uses `Future.microtask` (not
  /// `Future.delayed(Duration.zero, ...)`) so the test framework
  /// doesn't see a pending `Timer` at dispose time — a
  /// `Future.delayed` is implemented as a `Timer` under the
  /// hood, and the test binding's "Timer is still pending"
  /// assertion fires even for zero-duration timers when the
  /// widget tree is torn down. `Future.microtask` is not a
  /// timer.
  ///
  /// Deferring the first `load*` to a microtask also avoids
  /// tripping Flutter's "setState/markNeedsBuild during build"
  /// assertion when this is called from `initState` in tests
  /// that pump the home screen without first calling
  /// `pumpAndSettle` (e.g. the app_theme_reactive_test).
  Future<void> _runInitialLoad() async {
    await Future.microtask(() {});
    if (!mounted) return;
    await Future.wait([
      widget.nutritionState.loadNutritionTarget(),
      widget.nutritionState.loadConsumedToday(),
    ]);
    // One rollover check after the initial loads settle
    // (S-054): covers the edge case where the user opens the
    // app right at midnight, the loads above grabbed the new
    // day's target, but yesterday's cached `consumedToday` is
    // still in memory.
    if (mounted) _checkAndHandleDateRollover();
  }

  /// Initialize last seen date for rollover detection
  void _initializeLastSeenDate() {
    final now = DateTime.now();
    _lastSeenDate = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
  }

  /// Check if date has rolled over and trigger nutrition state rollover if needed
  void _checkAndHandleDateRollover() {
    final now = DateTime.now();
    final todayMs = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;

    if (todayMs != _lastSeenDate) {
      _lastSeenDate = todayMs;
      // Date has changed; trigger rollover (S-054). The
      // rollover clears the in-memory consumed cache and reloads
      // the target for the new day. We additionally reload
      // today's consumed foods (which the rollover does not
      // auto-reload) so the home strip rebuilds into the empty
      // state immediately rather than staying on yesterday's
      // values until the next manual load.
      // Schedule the rollover through `addPostFrameCallback`
      // (not `Future.microtask`): a microtask runs *between*
      // frames, but the strip's `ListenableBuilder` will still
      // try to rebuild in response to the notify, and if a
      // build is currently in flight we trip Flutter's
      // "setState during build" assertion. The post-frame
      // callback runs *after* the current frame, so the notify
      // schedules a clean rebuild for the next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(() async {
          await widget.nutritionState.rolloverToDate(todayMs);
          if (mounted) {
            await widget.nutritionState.loadConsumedToday();
          }
        }());
      });
    }
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

  void _openHubSheet() {
    if (mounted) {
      _snapSheet(_maxSheetExtent);
    }
  }

  /// Open the nutrition screen to view and edit daily targets and
  /// the Foods I Eat card (D-5: the strip is always tappable →
  /// NutritionScreen in all states).
  void _openNutritionScreen() {
    OmniNavigator.push(
      context,
      (_) => NutritionScreen(
        nutritionState: widget.nutritionState,
        foodLibraryState: widget.foodLibraryState,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: HomeLogoButton(onTap: _openHubSheet),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                flex: 15,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16.0, 5.0, 16.0, 0.0),
                    child: Column(
                      children: [
                        Text(
                          'TRAIN',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2.0,
                                color: OmniTheme.colors.textDominant,
                                shadows: [
                                  Shadow(
                                    color: Colors.black.withOpacity(0.5),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                        ),
                        const SizedBox(height: 20),
                        // Grid view with training modalities
                        Expanded(
                          child: ListenableBuilder(
                            listenable: widget.workoutState,
                            builder: (context, child) {
                              const standardGridSpacing = 16.0;
                              const utilitySectionGap =
                                  standardGridSpacing * 1;

                              final session =
                                  widget.workoutState.currentSession;
                              final isRoutineSession =
                                  session?.intent == 'routine';
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
                                            : session?.modality ==
                                                  tile.modality);

                                    return EnergyTile(
                                      title: tile.label,
                                      icon: tile.iconData,
                                      iconWidget: tile.iconWidget,
                                      accentColor: tile.accentColor,
                                      isSecondary: tile.isSecondary,
                                      isActive: isActive,
                                      onTap: () => _handleTileTap(
                                        context,
                                        tile,
                                        isActive,
                                      ),
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
                                          crossAxisSpacing:
                                              standardGridSpacing,
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
                                          crossAxisSpacing:
                                              standardGridSpacing,
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
              ),
              // Phase 4.1.1 (D-8 follow-up) home nutrition strip.
              // Top gap = 2 × standardGridSpacing (D-8 inherits
              // D-5's spacing rule; the standardGridSpacing is
              // local to the tile grid above). The strip is
              // wrapped in `Expanded(flex: 2)` so the progress
              // bar fills the rest of the bottom area (between
              // the tile-grid bottom + 2 × standardGridSpacing
              // and the physical bottom edge of the screen).
              // The tile grid gets `Expanded(flex: 15)` so it
              // keeps the bulk of the vertical space — the
              // strip is a substantial but bounded region
              // (~98 px on a typical iPhone screen: 64 px
              // bar + 34 px bottom safe-area inset label gap),
              // not a 50/50 share that would cut the tiles in
              // half. The strip's `Material`/`Ink` decoration
              // reaches the physical bottom edge (S-056), and
              // the bar is glued to the top of the strip with
              // no padding / no outer `Container`.
              //
              // The previous `isCurrent` route gate (S-057) is
              // removed: the data layer's microtask-deferred
              // notify avoids the build-during-build race that
              // the gate used to mask, so the strip can keep
              // rendering current values through a push/pop
              // transition.
              //
              // Phase 4.1.2 (S-058): the strip's bar keeps
              // its original D-8 `contentHeight: 64` and the
              // home screen's `flex: 2` is unchanged. The
              // change is purely internal to the strip
              // widget: the bar is glued to the top of the
              // strip with no padding / no outer `Container`,
              // a chevron-right navigation indicator is
              // vertically centered inside the bar at the
              // right edge, and the "calories eaten /
              // calories planned" label is dropped into the
              // gap BELOW the bar (the `Material` / `Ink`
              // decoration area between the bar's bottom and
              // the physical bottom edge, S-056). The label
              // itself stays chevron-free.
              SizedBox(height: 16.0 * 2),
              Expanded(
                flex: 2,
                child: ListenableBuilder(
                  listenable: widget.nutritionState,
                  builder: (context, _) {
                    final target = widget.nutritionState.nutritionTarget;
                    final targetCalories =
                        (target != null && target.calories > 0)
                            ? target.calories.round()
                            : null;
                    return NutritionStripBar(
                      consumedCalories:
                          widget.nutritionState.todayConsumedCalories,
                      targetCalories: targetCalories,
                      proteinKcal: widget.nutritionState.todayProteinKcal,
                      netCarbsKcal:
                          widget.nutritionState.todayNetCarbsKcal,
                      fatKcal: widget.nutritionState.todayFatKcal,
                      onTap: _openNutritionScreen,
                    );
                  },
                ),
              ),
            ],
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
                          color: OmniTheme.colors.textSecondary.withOpacity(
                            0.3,
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  Text(
                    'Free Training',
                    style: Theme.of(innerCtx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: OmniTheme.colors.textDominant,
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
            .clamp(0.5, 0.86);

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
                                          color: OmniTheme.colors.textSecondary
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
