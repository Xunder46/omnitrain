/// Debug entry point for the wrist session start paths on a Wear OS device.
///
/// ```sh
/// flutter run -t lib/watch/debug/watch_start_debug_main.dart \
///   --dart-define=WATCH_START_DEBUG=true
/// ```
///
/// Seeds a catalog the way a `routines_down` message would and runs the real
/// start surfaces against it, on an in-memory store so a QA session cannot
/// collide with the app's own data. The reachability switch stands in for the
/// transport: it is the one thing a desktop run cannot have, and it is what the
/// search-on-phone affordance reads.
library;

import 'package:flutter/material.dart';

import '../logging/watch_logging_screen.dart';
import '../logging/watch_logging_state.dart';
import '../nutrition/watch_nutrition_screen.dart';
import '../nutrition/watch_nutrition_state.dart';
import '../session/in_memory_watch_session_store.dart';
import '../session/watch_records.dart';
import '../session/watch_session_engine.dart';
import '../session/watch_session_store.dart';
import '../start/watch_session_start_paths.dart';
import '../start/watch_start_screen.dart';
import '../start/watch_sync_orchestrator.dart';

/// Whether the QA surface was compiled in. The entry point below refuses to
/// mount without it, so a release build carries nothing.
const bool watchStartDebugEnabled = bool.fromEnvironment('WATCH_START_DEBUG');

/// A transport with a switch where the radio would be: it answers nothing and
/// reports what the toggle says. A desktop run has no way to carry a message,
/// so what the watch owes the phone is kept where a real transport would have
/// put it — in flight, undelivered.
class _DebugTransport implements WatchSyncTransport {
  _DebugTransport(this.isPhoneReachable);

  @override
  bool isPhoneReachable;

  /// What the watch handed over, in order.
  final List<Map<String, Object?>> sent = [];

  @override
  Future<void> requestRoutines({DateTime? since}) async {}

  @override
  Future<void> requestSnapshot() async {}

  @override
  Future<void> send(Map<String, Object?> envelope) async => sent.add(envelope);
}

/// Two routines and the fallback list that covers them, shaped exactly as the
/// phone would send them.
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
        'routineId': 'routine-push-a',
        'name': 'Push A',
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
            ],
          },
        ],
      },
      {
        'routineId': 'routine-conditioning',
        'name': 'Conditioning',
        'updatedAt': '2026-07-12T09:00:00Z',
        'segments': [
          {
            'segmentId': 'seg-rounds',
            'name': 'Rounds',
            'efforts': [
              {
                'effortId': 'eff-burpee',
                'exerciseId': 'ex-burpee',
                'exerciseName': 'Burpee',
                'effortKind': 'round',
                'capabilities': ['time', 'rounds'],
                'targets': {'rounds': 5},
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
        'exerciseId': 'ex-burpee',
        'name': 'Burpee',
        'capabilities': ['time', 'rounds'],
      },
      {
        'exerciseId': 'ex-goblet-squat',
        'name': 'Goblet Squat',
        'capabilities': ['sets', 'reps', 'load'],
      },
    ],
  },
};

/// Five foods in three categories, shaped exactly as the phone would send
/// them — the same dataset the protocol fixture and the parity contract use.
const Map<String, Object?> _foodsDown = {
  'protocolVersion': 1,
  'messageId': 'msg-debug-foods-1',
  'type': 'foods_down',
  'origin': 'phone',
  'sentAt': '2026-07-13T17:00:00Z',
  'payload': {
    'generatedAt': '2026-07-13T17:00:00Z',
    'categories': [
      {'categoryId': 'foodcat-protein', 'name': 'Protein'},
      {'categoryId': 'foodcat-carbs', 'name': 'Carbs'},
      {'categoryId': 'foodcat-fruit', 'name': 'Fruit'},
    ],
    'foods': [
      {
        'foodId': 'food-oatmeal',
        'name': 'Oatmeal',
        'categoryId': 'foodcat-carbs',
        'referenceAmount': 100,
        'referenceLabel': 'g',
        'caloriesPerServing': 190,
        'defaultServings': 1.5,
      },
      {
        'foodId': 'food-banana',
        'name': 'Banana',
        'categoryId': 'foodcat-fruit',
        'referenceAmount': 1,
        'referenceLabel': 'banana',
        'caloriesPerServing': 105,
        'defaultServings': 1,
      },
      {
        'foodId': 'food-egg',
        'name': 'Egg',
        'categoryId': 'foodcat-protein',
        'referenceAmount': 1,
        'referenceLabel': 'egg',
        'caloriesPerServing': 78,
        'defaultServings': 2,
      },
      {
        'foodId': 'food-greek-yogurt',
        'name': 'Greek Yogurt',
        'categoryId': 'foodcat-protein',
        'referenceAmount': 1,
        'referenceLabel': 'cup',
        'caloriesPerServing': 130,
        'defaultServings': 1,
      },
      {
        'foodId': 'food-almonds',
        'name': 'Almonds',
        'categoryId': null,
        'referenceAmount': 30,
        'referenceLabel': 'g',
        'caloriesPerServing': 170,
        'defaultServings': 1,
      },
    ],
  },
};

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    MaterialApp(
      title: 'Watch start debug',
      debugShowCheckedModeBanner: false,
      // Deliberately plain: this harness shows the start paths, not theme work.
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      home: watchStartDebugEnabled
          ? const _WatchStartDebugHarness()
          : const _BuildFlagMissing(),
    ),
  );
}

/// Refuses to run without the build flag, rather than pretending to.
class _BuildFlagMissing extends StatelessWidget {
  const _BuildFlagMissing();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Run with --dart-define=WATCH_START_DEBUG=true',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _WatchStartDebugHarness extends StatefulWidget {
  const _WatchStartDebugHarness();

  @override
  State<_WatchStartDebugHarness> createState() =>
      _WatchStartDebugHarnessState();
}

class _WatchStartDebugHarnessState extends State<_WatchStartDebugHarness>
    with WidgetsBindingObserver {
  final WatchSessionStore _store = InMemoryWatchSessionStore();
  final _DebugTransport _transport = _DebugTransport(false);

  late final WatchSessionEngine _engine = WatchSessionEngine(
    _store,
    onEmit: _transport.send,
  );
  late final WatchSessionStartPaths _paths = WatchSessionStartPaths(
    engine: _engine,
    store: _store,
  );
  late final WatchNutritionState _nutrition = WatchNutritionState(
    engine: _engine,
    store: _store,
  );
  late final WatchSyncOrchestrator _orchestrator = WatchSyncOrchestrator(
    transport: _transport,
    paths: _paths,
    engine: _engine,
    nutrition: _nutrition,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// D-183 in the harness: the resumed app catches the wrist up, the same
  /// trigger the real shell calls on its scene phase.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _orchestrator.catchUp(reachable: true);
    }
  }

  /// The launch sequence: restore, then take the catalogs the phone sent.
  Future<void> _sync() async {
    await _engine.restore();
    await _paths.restore();
    await _nutrition.restore();
    await _orchestrator.receive(_routinesDown);
    await _orchestrator.receive(_foodsDown);
    if (mounted) setState(() {});
  }

  /// What the watch handed to the radio, in order. A desktop run carries
  /// nothing, so this line is the only way to see what a real transport would
  /// have been given.
  String get _handedOver {
    if (_transport.sent.isEmpty) return 'Nothing handed over yet.';
    final types = _transport.sent
        .map((envelope) => envelope['type'])
        .join(', ');
    return 'Handed over: $types';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: WatchStartScreen(
                paths: _paths,
                onSessionStarted: _openLogging,
                onOpenNutrition: _openNutrition,
              ),
            ),
            SwitchListTile(
              dense: true,
              title: const Text('Phone reachable'),
              value: _transport.isPhoneReachable,
              onChanged: (reachable) async {
                _transport.isPhoneReachable = reachable;
                await _orchestrator.sync(reconnect: true);
                if (mounted) setState(() {});
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                _handedOver,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openLogging(WatchSessionRecord session) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            WatchLoggingScreen(state: WatchLoggingState(engine: _engine)),
      ),
    );
  }

  void _openNutrition() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => WatchNutritionScreen(state: _nutrition),
      ),
    );
  }
}
