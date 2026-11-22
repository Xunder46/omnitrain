/// The Wear OS shell: the app the wrist actually launches.
///
/// Plan: `docs/plans/2026-11-20-280-wear-os-shell-plan/2026-11-20-280-wear-os-shell-plan.md`
/// (D-28007). The Dart counterpart of the watchOS `ContentView`: it hosts the
/// surfaces that already exist in `lib/watch/` — start, logging, rest, nutrition
/// — over the real engine, and it is the only thing that owns navigation, the
/// app's lifecycle and the radio.
///
/// Everything is injected, so a desktop test builds this app with an in-memory
/// store and a fake link instead of reaching for Hive and a paired watch.
///
/// What this shell does **not** host yet is recorded in the plan's Open items:
/// the workout summary and the diagnostics view that the Apple wrist has. Its
/// `Menu` button opens the exercise menu (plan 281). The shell
/// wears the phone's accent colour
/// (plan 286) and swipes between exercises on the logging surface (plan 287);
/// a set that beats the phone's best shows a `New PR` banner (plan 289), and
/// the Log food screen shows the day's water bar (plan 291).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/omni_theme.dart';
import '../../core/platform/watch_request_frames.dart';
import '../logging/watch_effort_rating_screen.dart';
import '../logging/watch_effort_rating_state.dart';
import '../logging/watch_logging_pager.dart';
import '../logging/watch_logging_state.dart';
import '../logging/watch_menu_screen.dart';
import '../logging/watch_menu_state.dart';
import '../logging/watch_metric_stepping.dart';
import '../logging/watch_personal_bests.dart';
import '../logging/watch_rest_screen.dart';
import '../nutrition/watch_nutrition_screen.dart';
import '../nutrition/watch_nutrition_state.dart';
import '../nutrition/watch_water_state.dart';
import '../session/watch_session_engine.dart';
import '../session/watch_records.dart';
import '../start/watch_session_start_paths.dart';
import '../start/watch_phone_preferences.dart';
import '../start/watch_start_screen.dart';
import '../start/watch_sync_orchestrator.dart';
import '../widgets/watch_accent.dart';
import '../widgets/watch_controls.dart';
import 'wear_watch_transport.dart';

class WearApp extends StatefulWidget {
  const WearApp({
    super.key,
    required this.engine,
    required this.paths,
    required this.nutrition,
    required this.orchestrator,
    required this.transport,
    this.navigatorKey,
    this.units = const WatchUnitPreferences(),
    this.preferences,
    this.rating,
    this.bests,
    this.water,
  });

  final WatchSessionEngine engine;
  final WatchSessionStartPaths paths;
  final WatchNutritionState nutrition;
  final WatchSyncOrchestrator orchestrator;
  final WearWatchTransport transport;

  /// The shell's navigator. Left null the shell makes its own; the desktop QA
  /// harness passes one so it can offer a Back button and Esc where a watch has
  /// the system swipe-back (plan 281).
  final GlobalKey<NavigatorState>? navigatorKey;

  /// The saved unit preferences the wrist reads in, as the phone wrote them.
  final WatchUnitPreferences units;

  /// The phone's synced settings. When given, the logging surface reads its
  /// units and the rest ping from them (plan 283a); left null it reads
  /// [units] as before.
  final WatchPhonePreferences? preferences;

  /// The effort-rating state (plan 285). When given, a workout ended from the
  /// menu may owe the rating, and the shell shows the question alone while one
  /// is owed; left null the shell never asks.
  final WatchEffortRatingState? rating;

  /// The phone's standing bests (plan 288). When given, the shell restores them
  /// at launch so a `bests_down` frame and the sets the wrist holds are known
  /// before the first set is logged; left null the shell holds none.
  final WatchPersonalBests? bests;

  /// The day's water (plan 290). When given, the shell restores it at launch so
  /// the phone's count and the wrist's own taps are known before the bar exists;
  /// left null the shell holds none.
  final WatchWaterState? water;

  /// The copy the wrist shows while it restores what it holds.
  static const String loadingLabel = 'OmniTrain';

  /// The bottom button that opens the exercise menu (plan 281, D-28101).
  static const String menuLabel = WatchMenuCopy.menuLabel;

  @override
  State<WearApp> createState() => WearAppState();
}

/// Public so a test can drive the shell the way the platform does.
class WearAppState extends State<WearApp> with WidgetsBindingObserver {
  static const Duration _tick = Duration(seconds: 1);

  late final WatchLoggingState _logging = WatchLoggingState(
    engine: widget.engine,
    units: widget.units,
    unitsProvider: widget.preferences == null
        ? null
        : () => widget.preferences!.units,
    bests: widget.bests,
  );

  late final WatchMenuState _menu = WatchMenuState(
    engine: widget.engine,
    paths: widget.paths,
    rating: widget.rating,
  );

  /// The shell's own navigator: the shell is above the `MaterialApp` it builds,
  /// so its `context` has no navigator (the nutrition push needed this too).
  late final GlobalKey<NavigatorState> _navigator =
      widget.navigatorKey ?? GlobalKey<NavigatorState>();

  Timer? _ticker;
  bool _ready = false;

  /// Whether the shell's once-a-second rebuild is running: true while a session
  /// is active, false on an idle start surface (plan 281: a test reads it).
  @visibleForTesting
  bool get isTicking => _ticker != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.rating?.addListener(_ratingChanged);
    widget.transport.onIncoming(_onFrame);
    unawaited(_boot());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(widget.transport.close());
    widget.rating?.removeListener(_ratingChanged);
    super.dispose();
  }

  /// D-28006: the resumed app catches the wrist up, the trigger the Apple shell
  /// maps from its own scene phase.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.paths.phoneReachable = widget.transport.isPhoneReachable;
      unawaited(
        widget.orchestrator.catchUp(
          reachable: widget.transport.isPhoneReachable,
        ),
      );
    }
  }

  /// The launch sequence: restore, then take whatever the phone already sent.
  Future<void> _boot() async {
    try {
      await widget.engine.restore();
      await widget.paths.restore();
      await widget.nutrition.restore();
      await widget.preferences?.restore();
      await widget.rating?.restore();
      await widget.bests?.restore();
      await widget.water?.restore();
    } on Object catch (error, stack) {
      debugPrint('OmniTrain wrist restore failed: $error\n$stack');
    } finally {
      if (mounted) {
        setState(() {
          _ready = true;
          // The restored session may already be active: bring the shell's
          // once-a-second rebuild up with it.
          _syncTicker();
        });
      }
    }
    await widget.transport.start();
    if (!mounted) return;
    widget.paths.phoneReachable = widget.transport.isPhoneReachable;
    setState(() {});
    await widget.orchestrator.catchUp(
      reachable: widget.transport.isPhoneReachable,
    );
  }

  Future<void> _onFrame(Map<String, Object?> frame) async {
    if (WatchTransportRequest.nameOf(frame) == WatchTransportRequest.snapshot) {
      await widget.orchestrator.answerSnapshotRequest();
      return;
    }
    await widget.orchestrator.receive(frame);
    if (mounted) setState(_syncTicker);
  }

  /// The surfaces follow the engine, as they do on the Apple wrist: while a
  /// session runs, one rebuild a second keeps the countdown and the rest screen
  /// honest. With nothing running there is nothing to tick.
  void _syncTicker() {
    final active = widget.engine.session?.status == WatchSessionStatus.active;
    if (active && _ticker == null) {
      _ticker = Timer.periodic(_tick, (_) => _refresh());
    } else if (!active && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  void _refresh() {
    final reachable = widget.transport.isPhoneReachable;
    if (widget.paths.phoneReachable != reachable) {
      widget.paths.phoneReachable = reachable;
    }
    if (mounted) setState(() {});
  }

  Future<void> _endRest() async {
    await _logging.endRest();
    if (!mounted) return;
    setState(_syncTicker);
  }

  /// What the menu did that the surfaces must follow: a jump, an add, an End or
  /// a Discard (the session may now be over, so the ticker re-reads it).
  void _menuChanged() {
    if (mounted) setState(_syncTicker);
  }

  /// The owed question changed (an End owed one, an answer, a Skip): the shell
  /// redraws, and re-reads whether anything still ticks.
  void _ratingChanged() {
    if (mounted) setState(_syncTicker);
  }

  void _openMenu() {
    _navigator.currentState?.push(
      MaterialPageRoute<void>(
        builder: (context) =>
            WatchMenuScreen(state: _menu, onChanged: _menuChanged),
      ),
    );
  }

  Future<void> _requestSync() async {
    await widget.orchestrator.sync(reconnect: true);
    if (mounted) setState(_refresh);
  }

  void _openNutrition() {
    _navigator.currentState?.push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          body: SafeArea(
            child: WatchNutritionScreen(
              state: widget.nutrition,
              water: widget.water,
            ),
          ),
        ),
      ),
    );
  }

  void _started(WatchSessionRecord session) {
    setState(_syncTicker);
  }

  /// The theme the shell wears, cached by the accent string it was built from:
  /// the shell rebuilds every second while a session runs, and a new theme per
  /// tick would re-theme the whole tree each second (plan 286, D-28602).
  String? _themeHex;
  ThemeData? _theme;

  ThemeData _themeFor(String? hex) {
    final cached = _theme;
    if (cached != null && _themeHex == hex) return cached;
    final accent = WatchAccent.worn(hex);
    final scheme = ThemeData(brightness: Brightness.dark).colorScheme.copyWith(
      primary: accent.color,
      onPrimary: accent.labelColor,
    );
    final built = ThemeData(useMaterial3: true, colorScheme: scheme);
    _themeHex = hex;
    _theme = built;
    return built;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigator,
      title: WearApp.loadingLabel,
      debugShowCheckedModeBanner: false,
      theme: _themeFor(widget.preferences?.accentColorHex),
      home: Builder(
        builder: (context) =>
            Scaffold(body: SafeArea(child: _surface(context))),
      ),
    );
  }

  Widget _surface(BuildContext context) {
    if (!_ready) {
      return const Center(child: CircularProgressIndicator());
    }

    final rating = widget.rating;
    if (rating != null && rating.isPromptOwed) {
      return WatchEffortRatingScreen(state: rating);
    }

    final session = widget.engine.session;
    if (session != null && session.status == WatchSessionStatus.active) {
      final surface = _logging.isResting
          ? WatchRestScreen(state: _logging, onNext: _endRest)
          : WatchLoggingPager(
              menu: _menu,
              logging: _logging,
              onMoved: _menuChanged,
            );
      return Column(
        children: [
          Expanded(child: surface),
          TextButton(
            style: ButtonStyle(
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    OmniTheme.buttonUtilityRadius,
                  ),
                ),
              ),
              minimumSize: WatchLayout.isCompact(context)
                  ? WidgetStateProperty.all(
                      const Size.fromHeight(WatchLayout.compactMenuHeight),
                    )
                  : null,
              padding: WatchLayout.isCompact(context)
                  ? WidgetStateProperty.all(EdgeInsets.zero)
                  : null,
              tapTargetSize: WatchLayout.isCompact(context)
                  ? MaterialTapTargetSize.shrinkWrap
                  : null,
            ),
            onPressed: _openMenu,
            child: const Text(WearApp.menuLabel),
          ),
        ],
      );
    }

    return WatchStartScreen(
      paths: widget.paths,
      onSessionStarted: _started,
      onOpenNutrition: _openNutrition,
      onRequestSync: _requestSync,
    );
  }
}
