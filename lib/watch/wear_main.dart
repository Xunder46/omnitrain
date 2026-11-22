/// The Wear OS app's entry point: what the wear build launches.
///
/// Plan: `docs/plans/2026-11-20-280-wear-os-shell-plan/2026-11-20-280-wear-os-shell-plan.md`
/// (D-28007). Run it on a watch (or a Wear OS emulator) with:
///
/// ```sh
/// flutter run --flavor wear -t lib/watch/wear_main.dart -d <wear device>
/// ```
///
/// Everything the wrist logs lives in its own Hive directory, so the watch's
/// store never shares a box with anything else on the device, and the phone's
/// boxes are a different install entirely.
library;

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../core/services/diagnostics_log.dart';
import '../core/services/diagnostics_storage_default.dart';
import 'app/wear_app.dart';
import 'app/wear_watch_transport.dart';
import 'logging/watch_effort_rating_state.dart';
import 'logging/watch_personal_bests.dart';
import 'nutrition/watch_nutrition_state.dart';
import 'nutrition/watch_water_state.dart';
import 'sensors/watch_platform_workout.dart';
import 'sensors/watch_sensor_recording.dart';
import 'sensors/wear_sensor_source.dart';
import 'session/hive_watch_session_store.dart';
import 'session/watch_session_engine.dart';
import 'start/watch_phone_preferences.dart';
import 'start/watch_session_start_paths.dart';
import 'start/watch_sync_orchestrator.dart';

/// Hive's sub-directory for the wrist's own store.
const String wearBoxPrefix = 'omnitrain_watch';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter(wearBoxPrefix);

  // The wrist's diagnostics log (plan 293): one for the life of the app, opened
  // first so the launch line names what the previous run recorded last.
  final diagnostics = DiagnosticsLog(storage: await openDefaultDiagnosticsStorage());
  diagnostics.noteLaunch();

  final store = HiveWatchSessionStore(name: wearBoxPrefix);
  final transport = WearWatchTransport(
    onFailure: (error, stack) {
      // A refused frame is not a reason to take the wrist down: the protocol's
      // next sync re-sends what is owed.
      debugPrint('OmniTrain wrist radio: $error');
    },
    diagnostics: diagnostics,
  );
  final engine = WatchSessionEngine(store, onEmit: transport.send);
  final paths = WatchSessionStartPaths(engine: engine, store: store);
  final nutrition = WatchNutritionState(engine: engine, store: store);
  final preferences = WatchPhonePreferences(store: store);
  final bests = WatchPersonalBests(store: store);
  final water = WatchWaterState(engine: engine, store: store);
  // The session's sensors (plans 297 to 300): the native half's channels for
  // heart rate and distance, and a Health Services exercise as the platform
  // workout. One source serves both, so the permission is asked once.
  final sensorSource = WearSensorSource();
  final sensors = WatchSessionSensors(
    platform: WatchPlatformWorkout(
      store: WearPlatformWorkoutStore(source: sensorSource),
    ),
    recorder: WatchSensorRecorder(engine: engine, source: sensorSource),
  );
  // The wrist's routines request says what it holds and what it wants (series
  // 87c, plan 94): the bests flag is read on every request.
  transport.holdsBests = () => bests.hasFrame;
  transport.wantsWater = true;
  final rating = WatchEffortRatingState(
    engine: engine,
    store: store,
    preferences: preferences,
  );
  final orchestrator = WatchSyncOrchestrator(
    transport: transport,
    paths: paths,
    engine: engine,
    nutrition: nutrition,
    preferences: preferences,
    bests: bests,
    water: water,
  );

  runApp(
    WearApp(
      engine: engine,
      paths: paths,
      nutrition: nutrition,
      orchestrator: orchestrator,
      transport: transport,
      preferences: preferences,
      rating: rating,
      bests: bests,
      water: water,
      diagnostics: diagnostics,
      sensors: sensors,
    ),
  );
}
