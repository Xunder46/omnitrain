/// Debug entry point for the Wear menu on a macOS desktop QA run.
///
/// ```sh
/// flutter run -d macos -t lib/watch/debug/wear_menu_debug_main.dart
/// ```
///
/// This is a QA harness, not the production entry point (the wear build runs
/// `lib/watch/wear_main.dart`, and no production file imports this one). It
/// composes the same engine, start paths, nutrition state, sync orchestrator
/// and radio the production shell uses over an in-memory store, seeds a
/// routines frame, and opens a running three-exercise session before the shell
/// boots. The macOS build has no native link, so the radio fails quietly
/// behind the harness's `onFailure` hook; that is intended. Back (or Esc) stands
/// in for the system swipe-back a watch has.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/wear_app.dart';
import '../app/wear_watch_transport.dart';
import '../nutrition/watch_nutrition_state.dart';
import '../session/in_memory_watch_session_store.dart';
import '../session/watch_session_engine.dart';
import '../start/watch_session_start_paths.dart';
import '../start/watch_sync_orchestrator.dart';

/// One routine and the fallback list Add Exercise offers, shaped exactly as
/// the phone would send it.
const Map<String, Object?> _routinesDown = {
  'protocolVersion': 1,
  'messageId': 'msg-debug-1',
  'type': 'routines_down',
  'origin': 'phone',
  'sentAt': '2026-07-13T17:00:00Z',
  'payload': {
    'generatedAt': '2026-07-13T17:00:00Z',
    'routines': [
      {
        'routineId': 'routine-demo',
        'name': 'Demo',
        'updatedAt': '2026-07-12T09:00:00Z',
        'segments': [
          {
            'segmentId': 'seg-main',
            'name': 'Main',
            'efforts': [
              {
                'effortId': 'eff-bench',
                'exerciseId': 'ex-barbell-bench-press',
                'exerciseName': 'Barbell Bench Press',
                'effortKind': 'set',
                'capabilities': ['sets', 'reps', 'load'],
                'targets': {'sets': 3, 'reps': 5, 'loadKg': 80},
              },
              {
                'effortId': 'eff-plank',
                'exerciseId': 'ex-plank',
                'exerciseName': 'Plank',
                'effortKind': 'timed',
                'capabilities': ['time', 'hold'],
                'targets': {'holdMs': 60000},
              },
              {
                'effortId': 'eff-goblet-squat',
                'exerciseId': 'ex-goblet-squat',
                'exerciseName': 'Goblet Squat',
                'effortKind': 'set',
                'capabilities': ['sets', 'reps', 'load'],
                'targets': {'sets': 3, 'reps': 10, 'loadKg': 24},
              },
            ],
          },
        ],
      },
    ],
    'fallbackExercises': [
      {
        'exerciseId': 'ex-barbell-bench-press',
        'name': 'Barbell Bench Press',
        'capabilities': ['sets', 'reps', 'load'],
      },
      {
        'exerciseId': 'ex-plank',
        'name': 'Plank',
        'capabilities': ['time', 'hold'],
      },
      {
        'exerciseId': 'ex-goblet-squat',
        'name': 'Goblet Squat',
        'capabilities': ['sets', 'reps', 'load'],
      },
      {
        'exerciseId': 'ex-burpee',
        'name': 'Burpee',
        'capabilities': ['time', 'rounds'],
      },
    ],
  },
};

Future<void> main() async {
  // The macOS build has no native link, so the radio's sends fail with a
  // missing-plugin error: log it instead of leaving it unhandled.
  await runZonedGuarded(
    _run,
    (error, stack) => debugPrint('Wear menu harness: $error'),
  );
}

Future<void> _run() async {
  WidgetsFlutterBinding.ensureInitialized();

  final store = InMemoryWatchSessionStore();
  final transport = WearWatchTransport(
    onFailure: (error, stack) => debugPrint('Wear menu harness radio: $error'),
  );
  final engine = WatchSessionEngine(store, onEmit: transport.send);
  final paths = WatchSessionStartPaths(engine: engine, store: store);
  final nutrition = WatchNutritionState(engine: engine, store: store);
  final orchestrator = WatchSyncOrchestrator(
    transport: transport,
    paths: paths,
    engine: engine,
    nutrition: nutrition,
  );

  await engine.restore();
  await paths.restore();
  await nutrition.restore();
  await orchestrator.receive(_routinesDown);
  await paths.startFromRoutine('routine-demo');

  final navigator = GlobalKey<NavigatorState>();
  runApp(
    // Deliberately plain: this harness shows the menu, not theme work. The
    // 227x227 clip stands in for the round watch face a desktop window lacks;
    // Back (or Esc) stands in for the swipe-back a watch has.
    Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: Colors.black,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                navigator.currentState?.maybePop(),
          },
          child: Focus(
            autofocus: true,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ClipOval(
                  child: SizedBox(
                    width: 227,
                    height: 227,
                    child: Builder(
                      builder: (context) => MediaQuery(
                        data: MediaQuery.of(
                          context,
                        ).copyWith(size: const Size(227, 227)),
                        child: WearApp(
                          engine: engine,
                          paths: paths,
                          nutrition: nutrition,
                          orchestrator: orchestrator,
                          transport: transport,
                          navigatorKey: navigator,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => navigator.currentState?.maybePop(),
                  child: const Text('Back (Esc)'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
