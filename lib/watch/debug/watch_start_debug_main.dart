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
/// reports what the toggle says.
class _DebugTransport implements WatchSyncTransport {
  _DebugTransport(this.isPhoneReachable);

  @override
  bool isPhoneReachable;

  @override
  Future<void> requestRoutines({DateTime? since}) async {}
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

class _WatchStartDebugHarnessState extends State<_WatchStartDebugHarness> {
  final WatchSessionStore _store = InMemoryWatchSessionStore();
  final _DebugTransport _transport = _DebugTransport(false);

  late final WatchSessionEngine _engine = WatchSessionEngine(_store);
  late final WatchSessionStartPaths _paths = WatchSessionStartPaths(
    engine: _engine,
    store: _store,
  );
  late final WatchSyncOrchestrator _orchestrator = WatchSyncOrchestrator(
    transport: _transport,
    paths: _paths,
    engine: _engine,
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  /// The launch sequence: restore, then take the catalog the phone sent.
  Future<void> _sync() async {
    await _engine.restore();
    await _paths.restore();
    await _orchestrator.receive(_routinesDown);
    if (mounted) setState(() {});
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
              ),
            ),
            SwitchListTile(
              dense: true,
              title: const Text('Phone reachable'),
              value: _transport.isPhoneReachable,
              onChanged: (reachable) {
                setState(() => _transport.isPhoneReachable = reachable);
                _orchestrator.sync(reconnect: true);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openLogging(WatchSessionRecord session) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => WatchLoggingScreen(
          state: WatchLoggingState(engine: _engine),
        ),
      ),
    );
  }
}
