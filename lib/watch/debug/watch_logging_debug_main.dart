/// Debug entry point for the wrist logging surfaces on a Wear OS device.
///
/// ```sh
/// flutter run -t lib/watch/debug/watch_logging_debug_main.dart \
///   --dart-define=WATCH_LOGGING_DEBUG=true
/// ```
///
/// The session and its slot come from the engine QA surface's own store by
/// default, so `watch_session_debug_main.dart` can create a session and this
/// surface logs against it on the same watch. The exercise kind is chosen on
/// screen, because the four effort kinds are what this harness exists to try.
library;

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/omni_theme.dart';
import '../logging/watch_logging_screen.dart';
import '../logging/watch_logging_state.dart';
import '../logging/watch_metric_stepping.dart';
import '../session/in_memory_watch_session_store.dart';
import '../session/watch_session_engine.dart';

/// Whether the QA surface was compiled in. The entry point below refuses to
/// mount the surface without it, so a release build carries nothing.
const bool watchLoggingDebugEnabled = bool.fromEnvironment(
  'WATCH_LOGGING_DEBUG',
);

/// One slot per effort kind, so the harness can switch between all four. Each
/// carries the modality the phone would start it in, because that is what the
/// surface reads its terminology from.
const List<({String modality, Map<String, Object?> slot})> _slots = [
  (
    modality: 'resistance_lifting',
    slot: {
      'sessionExerciseId': 'sx-bench',
      'exerciseId': 'ex-barbell-bench-press',
      'name': 'Bench Press',
      'capabilities': ['reps', 'sets', 'load'],
    },
  ),
  (
    modality: 'cardio_endurance',
    slot: {
      'sessionExerciseId': 'sx-run',
      'exerciseId': 'ex-run',
      'name': 'Run',
      'capabilities': ['time', 'distance'],
    },
  ),
  (
    modality: 'sports',
    slot: {
      'sessionExerciseId': 'sx-round',
      'exerciseId': 'ex-burpee',
      'name': 'Burpee',
      'capabilities': ['time', 'rounds'],
    },
  ),
  (
    modality: 'isometric_stretching',
    slot: {
      'sessionExerciseId': 'sx-plank',
      'exerciseId': 'ex-plank',
      'name': 'Plank',
      'capabilities': ['hold', 'time'],
    },
  ),
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    MaterialApp(
      title: 'Watch logging debug',
      debugShowCheckedModeBanner: false,
      // Deliberately plain: this harness shows the logging rules, not theme
      // work.
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      home: watchLoggingDebugEnabled
          ? const _WatchLoggingDebugHarness()
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
            'Run with --dart-define=WATCH_LOGGING_DEBUG=true',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _WatchLoggingDebugHarness extends StatefulWidget {
  const _WatchLoggingDebugHarness();

  @override
  State<_WatchLoggingDebugHarness> createState() =>
      _WatchLoggingDebugHarnessState();
}

class _WatchLoggingDebugHarnessState extends State<_WatchLoggingDebugHarness> {
  static const Uuid _uuid = Uuid();

  final WatchSessionEngine _engine = WatchSessionEngine(
    InMemoryWatchSessionStore(),
  );

  late WatchLoggingState _state = _stateFor(0);
  String? _failure;

  WatchLoggingState _stateFor(int index) => WatchLoggingState(
    engine: _engine,
    idFactory: _uuid.v4,
    units: const WatchUnitPreferences(),
  );

  /// Opens the slot at [index] as a session of its own.
  Future<void> _open(int index) async {
    setState(() {
      _failure = null;
      _state = _stateFor(index);
    });
    try {
      await _engine.createSession(
        modality: _slots[index].modality,
        exercises: [_slots[index].slot],
      );
    } on Object catch (error) {
      setState(() => _failure = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failure != null) {
      return Scaffold(body: Center(child: Text(_failure!)));
    }

    return Scaffold(
      body: Column(
        children: [
          Expanded(child: WatchLoggingScreen(state: _state)),
          _slotPicker(context),
        ],
      ),
    );
  }

  Widget _slotPicker(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Wrap(
      spacing: 8,
      children: [
        for (var index = 0; index < _slots.length; index++)
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
            onPressed: () => _open(index),
            child: Text('${_slots[index].slot['name']}'),
          ),
      ],
    ),
  );
}
