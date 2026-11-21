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
/// the swipe pager, the exercise menu, the effort-rating prompt, the personal
/// record banner, the water bar, the workout summary, the diagnostics view and
/// the accent theming that the Apple wrist has. Its `End` control is the
/// stopgap for the menu's End until that port lands.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/omni_theme.dart';
import '../../core/platform/watch_request_frames.dart';
import '../logging/watch_logging_screen.dart';
import '../logging/watch_logging_state.dart';
import '../logging/watch_metric_stepping.dart';
import '../logging/watch_rest_screen.dart';
import '../nutrition/watch_nutrition_screen.dart';
import '../nutrition/watch_nutrition_state.dart';
import '../session/watch_session_engine.dart';
import '../session/watch_records.dart';
import '../start/watch_session_start_paths.dart';
import '../start/watch_start_screen.dart';
import '../start/watch_sync_orchestrator.dart';
import 'wear_watch_transport.dart';

class WearApp extends StatefulWidget {
  const WearApp({
    super.key,
    required this.engine,
    required this.paths,
    required this.nutrition,
    required this.orchestrator,
    required this.transport,
    this.units = const WatchUnitPreferences(),
  });

  final WatchSessionEngine engine;
  final WatchSessionStartPaths paths;
  final WatchNutritionState nutrition;
  final WatchSyncOrchestrator orchestrator;
  final WearWatchTransport transport;

  /// The saved unit preferences the wrist reads in, as the phone wrote them.
  final WatchUnitPreferences units;

  /// The copy the wrist shows while it restores what it holds.
  static const String loadingLabel = 'OmniTrain';

  /// The stopgap end control the menu will replace.
  static const String endLabel = 'End';

  @override
  State<WearApp> createState() => WearAppState();
}

/// Public so a test can drive the shell the way the platform does.
class WearAppState extends State<WearApp> with WidgetsBindingObserver {
  static const Duration _tick = Duration(seconds: 1);

  late final WatchLoggingState _logging = WatchLoggingState(
    engine: widget.engine,
    units: widget.units,
  );

  Timer? _ticker;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.transport.onIncoming(_onFrame);
    unawaited(_boot());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(widget.transport.close());
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
    } on Object catch (error, stack) {
      debugPrint('OmniTrain wrist restore failed: $error\n$stack');
    } finally {
      if (mounted) setState(() => _ready = true);
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

  /// The stopgap until the exercise menu lands: finish the workout from here.
  Future<void> _finish() async {
    await widget.engine.finishSession();
    if (!mounted) return;
    setState(_syncTicker);
  }

  Future<void> _requestSync() async {
    await widget.orchestrator.sync(reconnect: true);
    if (mounted) setState(_refresh);
  }

  void _openNutrition() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          body: SafeArea(child: WatchNutritionScreen(state: widget.nutrition)),
        ),
      ),
    );
  }

  void _started(WatchSessionRecord session) {
    setState(_syncTicker);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: WearApp.loadingLabel,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      home: Scaffold(body: SafeArea(child: _surface())),
    );
  }

  Widget _surface() {
    if (!_ready) {
      return const Center(child: CircularProgressIndicator());
    }

    final session = widget.engine.session;
    if (session != null && session.status == WatchSessionStatus.active) {
      if (_logging.isResting) {
        return WatchRestScreen(state: _logging, onNext: _endRest);
      }
      return Column(
        children: [
          Expanded(child: WatchLoggingScreen(state: _logging)),
          TextButton(
            style: ButtonStyle(
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    OmniTheme.buttonUtilityRadius,
                  ),
                ),
              ),
            ),
            onPressed: _finish,
            child: const Text(WearApp.endLabel),
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
