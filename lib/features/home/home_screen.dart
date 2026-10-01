import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/services/routine_session_service.dart';
import '../../core/services/session_summary_service.dart';
import '../../core/models/app_version_info.dart';
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
import '../exercise/exercise_library_screen.dart';
import 'widgets/nutrition_summary_card.dart';
import '../../core/utils/timer_alert_service.dart';
import '../../core/utils/rest_notification_service.dart';
import '../../widgets/common/home_logo_button.dart';
import '../../state/nutrition_state.dart';
import '../../widgets/dialogs/confirmation_dialog.dart';
import '../../state/food_library_state.dart';
import '../../state/nutrition/nutrition_primer_state.dart';
import '../../state/exercise/exercise_library_state.dart';
import '../../state/watch/live_session_mirror_state.dart';
import '../../state/watch/watch_session_inbox.dart';
import '../../widgets/session/live_session_entry_point.dart';
import '../session/live_session_screen.dart';
import '../nutrition/nutrition_screen.dart';
import '../nutrition/widgets/nutrition_primer_sheet.dart';

/// Hub-sheet layout constants used to size the destination grid against the
/// sheet's fully-open height.
///
/// These describe the sheet's own chrome — the parts of the open sheet that
/// are not grid. They are not tile dimensions: tile *content* sizing lives in
/// `TileArtworkMetrics`, and hub tile height is derived here, never fixed.

/// Gap between the sheet's top edge and the drag handle bar.
const double hubHandleTopPadding = 20.0;

/// Handle block: [hubHandleTopPadding] + 6pt bar + 0pt bottom padding.
const double hubHandleBlockHeight = hubHandleTopPadding + 6.0;

/// `HUB` eyebrow (labelMedium, 12pt) at its rendered line height, before
/// text scaling. Rounded up so the reserve is never short.
const double hubHeaderHeight = 20.0;

/// Deliberate breathing room between the HUB eyebrow and the first tile row.
/// Pinned by `home_logo_hub_open_test.dart`.
const double hubHeaderToGridGap = 60.0;

/// Bottom of the sheet's `SliverPadding(fromLTRB(16, 0, 16, 4))`.
const double hubGridBottomPadding = 4.0;

/// The square-ish proportion the hub grid uses when the sheet is tall enough
/// to afford it (width / height).
const double hubTileNaturalAspectRatio = 1.1;

/// Floor for a hub tile, mirroring the Home grid's 56pt tile floor. Below
/// this the tile has no room for a label at all.
const double hubMinTileHeight = 56.0;

/// Gap between the live-session entry point and the TRAIN label.
const double liveSessionEntryGap = 12.0;

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
  final NutritionPrimerState nutritionPrimerState;
  final ExerciseLibraryState exerciseLibraryState;
  final AppVersionInfo? appVersionInfo;

  /// The session running on the wrist, when there is one. Null in builds with
  /// no watch sync — the panel then has nothing to surface, and nothing is
  /// reserved for it.
  final LiveSessionMirrorState? liveSession;

  /// Where the Watch Session screen records the phone's own effort rating
  /// for the wrist session it finished (D-139); null exactly when
  /// [liveSession] is.
  final WatchSessionRatings? watchSessionRatings;

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
    required this.nutritionPrimerState,
    required this.exerciseLibraryState,
    this.appVersionInfo,
    this.liveSession,
    this.watchSessionRatings,
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

    // A watch session can start, move on, or end while this panel is on screen;
    // the entry point shows it or does not, and the reserved height follows.
    widget.liveSession?.addListener(_onLiveSessionChanged);

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
    widget.liveSession?.removeListener(_onLiveSessionChanged);
    _sheetController.dispose();
    _sheetExtent.removeListener(_onSheetExtentChanged);
    _sheetExtent.dispose();
    _hintController.dispose();
    super.dispose();
  }

  /// A watch session started, moved, or ended: the entry point and the height
  /// reserved for it both follow from that.
  void _onLiveSessionChanged() {
    if (mounted) setState(() {});
  }

  /// The session running on the wrist, or null when there is nothing to
  /// surface. A session the phone has closed is not live: the panel stops
  /// offering it the moment Finish lands.
  LiveSessionMirrorState? get _liveWatchSession {
    final session = widget.liveSession;
    return session != null && session.isActive ? session : null;
  }

  void _openLiveSession(LiveSessionMirrorState liveSession) {
    OmniNavigator.push(
      context,
      (_) => LiveSessionScreen(
        liveSession: liveSession,
        workoutState: widget.workoutState,
        settingsState: widget.settingsState,
        watchSessionRatings: widget.watchSessionRatings,
      ),
    );
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
    _lastSeenDate = DateTime(
      now.year,
      now.month,
      now.day,
    ).millisecondsSinceEpoch;
  }

  /// Check if date has rolled over and trigger nutrition state rollover if needed
  void _checkAndHandleDateRollover() {
    final now = DateTime.now();
    final todayMs = DateTime(
      now.year,
      now.month,
      now.day,
    ).millisecondsSinceEpoch;

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
  ///
  /// First-ever tap of the home strip fires the one-shot primer
  /// (`NutritionPrimerSheet`) over the home screen via
  /// `showModalBottomSheet`. On dismiss, the seen-flag is marked
  /// AND `NutritionScreen` is pushed — the primer is a sheet, NOT
  /// a route, so it does not block navigation; the user can dismiss
  /// it and reach the page behind it. Subsequent taps push the
  /// page directly with no overlay (S-005: the primer never gates
  /// access). The header "?" on the nutrition page reopens the
  /// primer at any time without mutating the seen state.
  Future<void> _openNutritionScreen() async {
    // Auto-show path: first tap, primer not yet seen. Open the
    // primer sheet, mark seen on dismiss, then push the page.
    if (widget.nutritionPrimerState.shouldShowPrimer) {
      await _showNutritionPrimer();
    }
    if (!mounted) return;
    OmniNavigator.push(
      context,
      (_) => NutritionScreen(
        nutritionState: widget.nutritionState,
        foodLibraryState: widget.foodLibraryState,
        nutritionPrimerState: widget.nutritionPrimerState,
      ),
    );
  }

  /// Show the [NutritionPrimerSheet] over the home screen. The
  /// seen flag is marked ON DISMISS (in the post-pop callback),
  /// not on show, so a sheet that gets dismissed externally (e.g.
  /// by a back-tap) still counts as "seen" — the user has at
  /// least read the primer once.
  Future<void> _showNutritionPrimer() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: NutritionPrimerSheet(
            onDismiss: () {
              // Mark seen AFTER the sheet pops. Fire-and-forget: the
              // seen flag is local UX state and the round-trip
              // cannot fail the user-facing flow.
              unawaited(widget.nutritionPrimerState.markSeen());
            },
          ),
        );
      },
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
        toolbarHeight: 60,
      ),
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                const standardGridSpacing = 16.0;
                const minTileSide = 56.0;
                const titleToGridGap = 15.0;
                const gridToCardGap = 22.0;
                const outerPaddingTop = 10.0;
                const outerPaddingBottom = 6.0;

                // The TRAIN title and the summary card
                // both scale with the active `textScaler`
                // (MyApp clamps it to 1.1–1.6; tests may
                // use 1.0). We read the active scale
                // here so the shrink-to-fit math stays
                // accurate across accessibility settings.
                final textScale = MediaQuery.textScalerOf(context).scale(1.0);
                final titleHeight = 30.0 * textScale;
                // The live-session entry point, when a watch session is live.
                // Nothing is reserved for a panel with nothing to surface.
                // The block's height is the widget's own budget, asked for
                // rather than restated here.
                final liveSession = _liveWatchSession;
                final liveSessionBlock = liveSession == null
                    ? 0.0
                    : LiveSessionEntryPoint.budgetHeight(textScale) +
                          liveSessionEntryGap;
                // Measured card natural total height at
                // `textScaler = 1.0` is 112 px (the card
                // has no internal slack to compress, per
                // its design contract — see the
                // `NutritionSummaryCard` doc).
                const cardNaturalHeight = 112.0;
                final cardHeight = cardNaturalHeight * textScale;

                // Natural square tile side from the
                // available content width.
                final naturalTileSide =
                    (constraints.maxWidth - standardGridSpacing) / 2;
                final naturalGridHeight =
                    naturalTileSide * 3 + standardGridSpacing * 2;

                // Total content height at natural sizes.
                final totalNatural =
                    liveSessionBlock +
                    titleHeight +
                    titleToGridGap +
                    naturalGridHeight +
                    gridToCardGap +
                    cardHeight +
                    outerPaddingTop +
                    outerPaddingBottom;

                // If the natural content is too tall, compress
                // the tiles proportionally. The card always
                // renders at its natural height (it's the
                // "peer" element below the grid).
                final available = constraints.maxHeight;
                double tileSide = naturalTileSide;
                if (totalNatural > available && available > 0) {
                  final overflow = totalNatural - available;
                  final compressedSide = naturalTileSide - (overflow / 3);
                  tileSide = compressedSide < minTileSide
                      ? minTileSide
                      : compressedSide;
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (liveSession != null) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: LiveSessionEntryPoint(
                          liveSession: liveSession,
                          onTap: () => _openLiveSession(liveSession),
                        ),
                      ),
                      const SizedBox(height: liveSessionEntryGap),
                    ],
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 0.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'TRAIN',
                            textAlign: TextAlign.center,
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
                          const SizedBox(height: titleToGridGap),
                          // Non-scrolling training-tile grid.
                          // Three rows of two square tiles each
                          // (2 + 2 + 2 = 6), with a 16 px gap
                          // between rows. The tile side is
                          // computed above from both the
                          // available width and the available
                          // height — on short screens the tiles
                          // compress so the grid + card + gaps
                          // always fit at once (no scroll, no
                          // clip, no overlap).
                          ListenableBuilder(
                            listenable: widget.workoutState,
                            builder: (context, _) {
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
                                      artworkBuilder: tile.artworkBuilder,
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

                              Widget rowOf(int start, int end) {
                                return Row(
                                  children: [
                                    for (var i = start; i < end; i++) ...[
                                      if (i > start)
                                        const SizedBox(
                                          width: standardGridSpacing,
                                        ),
                                      Expanded(
                                        child: SizedBox(
                                          height: tileSide,
                                          child: tiles[i],
                                        ),
                                      ),
                                    ],
                                  ],
                                );
                              }

                              return Column(
                                children: [
                                  rowOf(0, 2),
                                  const SizedBox(height: standardGridSpacing),
                                  rowOf(2, 4),
                                  const SizedBox(height: standardGridSpacing),
                                  rowOf(4, 6),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: gridToCardGap),
                    // Peer calorie summary card. Sits below
                    // the grid in the body `Column` — NOT
                    // pinned to the bottom of the screen and
                    // NOT wrapped in its own `Expanded`. The
                    // card's own outer
                    // `Padding(symmetric(horizontal: 16))`
                    // aligns its left/right edges with the
                    // training-tile grid's left/right edges
                    // (both 16 px from the screen edge).
                    ListenableBuilder(
                      listenable: widget.nutritionState,
                      builder: (context, _) {
                        final target = widget.nutritionState.nutritionTarget;
                        final targetCalories =
                            (target != null && target.calories > 0)
                            ? target.calories.round()
                            : null;
                        return NutritionSummaryCard(
                          consumedCalories:
                              widget.nutritionState.todayConsumedCalories,
                          targetCalories: targetCalories,
                          proteinKcal: widget.nutritionState.todayProteinKcal,
                          carbsKcal: widget.nutritionState.todayNetCarbsKcal,
                          fatKcal: widget.nutritionState.todayFatKcal,
                          onTap: _openNutritionScreen,
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                );
              },
            ),
          ),
          // The sheet's own available height, not `MediaQuery.size.height`.
          // `DraggableScrollableSheet` sizes its extent as a fraction of the
          // height its parent gives it, so this is the number the hub grid
          // must be measured against.
          //
          // The OUTER `context` is passed on deliberately, not the builder's.
          // Inside the Scaffold body `MediaQuery.padding.top` already carries
          // the 60pt AppBar (the Scaffold extends the body behind it), so
          // reading it there would subtract the toolbar twice and open the
          // sheet 60pt short of the logo.
          LayoutBuilder(
            builder: (_, constraints) =>
                _buildMaintenanceSheet(context, constraints.maxHeight),
          ),
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
            barrierDismissible: true,
            builder: (context) => ConfirmationDialog.twoChoice(
              title: 'Start New Session?',
              body: const Text(
                'Your current session will be discarded and cannot be recovered.',
              ),
              dismissLabel: 'Cancel',
              confirmLabel: 'Continue',
              dismissKey: const Key('home-routine-open-cancel'),
              confirmKey: const Key('home-routine-open-confirm'),
              isDestructive: true,
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
        barrierDismissible: true,
        builder: (context) => ConfirmationDialog.twoChoice(
          title: 'Start New Session?',
          body: const Text(
            'Your current session will be discarded and cannot be recovered.',
          ),
          dismissLabel: 'Cancel',
          confirmLabel: 'Start New',
          dismissKey: const Key('home-modality-change-cancel'),
          confirmKey: const Key('home-modality-change-confirm'),
          isDestructive: true,
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

  Widget _buildMaintenanceSheet(BuildContext context, double availableHeight) {
    final mq = MediaQuery.of(context);
    // `context` here is the outer Scaffold context, so `padding.top` is the
    // status-bar safe-area only.  Subtract the AppBar's actual toolbar
    // height (the host Scaffold sets `toolbarHeight: 60` on its AppBar)
    // so the sheet top lands exactly at the AppBar's bottom edge instead
    // of covering the logo. The named local keeps the AppBar's
    // `toolbarHeight` and the sheet-extent calculation in sync — using
    // `kToolbarHeight` (56) would leave a 4 px drift.
    //
    // Upper clamp is `0.76` (was 0.86): the previous 0.86 left a sizeable
    // empty band of unrendered sheet height below the 5-tile grid on
    // tall screens, which read as "the tiles are still low" because the
    // grid sat in the upper-middle of an oversized sheet. Capping at
    // 0.76 shrinks the sheet so the grid is visually centred, the
    // tiles reach near the bottom edge with a small breathing gap, and
    // the bottom row no longer floats in empty space. See plan
    // `hub-sheet-gap-and-logo-clip-plan.md` for the full chain.
    const appBarToolbarHeight = 60.0;
    const hubSheetMaxExtent = 0.95;
    _maxSheetExtent =
        ((mq.size.height - mq.padding.top - appBarToolbarHeight) /
                mq.size.height)
            .clamp(0.5, hubSheetMaxExtent);

    // The height the sheet occupies when fully open: the extent fraction
    // applied to the height its parent offers. Every hub tile is sized
    // against this, never against the live extent — see the note at the
    // grid call site.
    final openSheetHeight = _maxSheetExtent * availableHeight;

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
                    // HUB label + tile grid fused into one SliverPadding
                    // so the HUB eyebrow reads as the grid's section
                    // header (4 px visual breath) and shares the grid's
                    // 16 px horizontal alignment. See plan
                    // hub-sheet-gap-and-logo-clip-plan.md for the chain
                    // of cuts.
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      sliver: SliverToBoxAdapter(
                        child: IgnorePointer(
                          ignoring: contentOpacity < 0.05,
                          child: Opacity(
                            opacity: contentOpacity,
                            child: Transform.translate(
                              offset: Offset(0, slideOffset),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 0),
                                    child: Text(
                                      'HUB',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            color: OmniTheme
                                                .colors
                                                .textSecondary
                                                .withOpacity(0.7),
                                            letterSpacing: 3.0,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                  SizedBox(height: hubHeaderToGridGap),
                                  // Tiles size against the sheet's
                                  // FULLY-OPEN height, not its current
                                  // extent. Sizing against the current
                                  // extent would resize the whole grid
                                  // continuously during a drag — visually
                                  // unstable, and it draws attention to
                                  // the chrome instead of the
                                  // destinations. Against the open height
                                  // the grid is laid out once, holds
                                  // still while dragging, and is
                                  // guaranteed to fit in the state the
                                  // user ends up in.
                                  _buildMaintenanceGrid(
                                    context,
                                    openSheetHeight: openSheetHeight,
                                    bottomInset: mq.padding.bottom,
                                    textScale: MediaQuery.textScalerOf(
                                      context,
                                    ).scale(1.0),
                                  ),
                                ],
                              ),
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
      // Top 20 puts the handle bar a comfortable distance below the
      // sheet's rounded top edge — earlier follow-ups had the handle
      // hugging the edge (top: 4) which read as the handle being
      // "too high" against the rounded sheet clip. Bottom 0 keeps
      // the handle bar flush against the HUB section header below.
      // See plan `hub-sheet-gap-and-logo-clip-plan.md` for the
      // full chain of cuts.
      padding: const EdgeInsets.only(top: hubHandleTopPadding, bottom: 0),
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

  Widget _buildMaintenanceGrid(
    BuildContext context, {
    required double openSheetHeight,
    required double bottomInset,
    required double textScale,
  }) {
    final items = [
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
        title: 'Settings',
        icon: Icons.tune,
        onTap: () => OmniNavigator.push(
          context,
          (_) => SettingsScreen(
            settingsState: widget.settingsState,
            timerAlertService: widget.timerAlertService,
            restNotificationService: widget.restNotificationService,
            profileState: widget.profileState,
            appVersionInfo:
                widget.appVersionInfo ??
                const AppVersionInfo(version: '0.0.0', build: '0'),
          ),
        ),
      ),
      _MaintenanceItem(
        title: 'Exercise Library',
        icon: Icons.library_books_outlined,
        onTap: () => OmniNavigator.push(
          context,
          (_) => ExerciseLibraryScreen(
            exerciseLibraryState: widget.exerciseLibraryState,
            workoutState: widget.workoutState,
          ),
        ),
      ),
    ];

    // `padding: EdgeInsets.zero` is required: `BoxScrollView.buildSlivers`
    // auto-injects `MediaQuery.padding` as a `SliverPadding` around the
    // grid when `padding` is null. That phantom sliver sits between the
    // HUB header and the first tile row, creating a ~60 px floating
    // band that pushed the grid into the visual middle of the
    // oversized sheet. Pinning the padding to zero keeps the content
    // anchored to the top of the sheet. The sheet itself positions the
    // grid via the surrounding `SliverPadding(fromLTRB(16, 0, 16, 4))`,
    // so we do not lose any system inset handling.
    const crossAxisCount = 2;
    const gridSpacing = 16.0;
    final rowCount = (items.length + crossAxisCount - 1) ~/ crossAxisCount;

    // Everything inside the fully-open sheet that sits above or below the
    // grid. Deliberately a slight over-estimate: over-reserving costs a few
    // points of tile height, under-reserving lets the last row run past the
    // sheet's bottom edge.
    final chromeHeight =
        hubHandleBlockHeight +
        hubHeaderHeight * textScale +
        hubHeaderToGridGap +
        hubGridBottomPadding +
        bottomInset;

    final fittedTileHeight =
        (openSheetHeight - chromeHeight - gridSpacing * (rowCount - 1)) /
        rowCount;

    return LayoutBuilder(
      builder: (context, constraints) {
        // The natural (pre-responsive) tile height: the square-ish
        // proportion the grid has always used. On a tall sheet this still
        // wins, so the hub renders exactly as it does today; only when the
        // sheet is too short to seat three rows does the fitted height take
        // over.
        final tileWidth =
            (constraints.maxWidth - gridSpacing * (crossAxisCount - 1)) /
            crossAxisCount;
        final naturalTileHeight = tileWidth / hubTileNaturalAspectRatio;

        final tileHeight = math.max(
          hubMinTileHeight,
          math.min(naturalTileHeight, fittedTileHeight),
        );

        // `padding: EdgeInsets.zero` is required: `BoxScrollView.buildSlivers`
        // auto-injects `MediaQuery.padding` as a `SliverPadding` around the
        // grid when `padding` is null. That phantom sliver sits between the
        // HUB header and the first tile row, creating a ~60 px floating
        // band that pushed the grid into the visual middle of the
        // oversized sheet. Pinning the padding to zero keeps the content
        // anchored to the top of the sheet. The sheet itself positions the
        // grid via the surrounding `SliverPadding(fromLTRB(16, 0, 16, 4))`,
        // so we do not lose any system inset handling.
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: gridSpacing,
            crossAxisSpacing: gridSpacing,
            mainAxisExtent: tileHeight,
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
