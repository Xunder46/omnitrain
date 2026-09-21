/// Debug entry point for live session mirroring on the phone.
///
/// ```sh
/// flutter run -t lib/state/watch/live_session_mirror_debug_main.dart \
///   --dart-define=LIVE_MIRROR_DEBUG=true
/// ```
///
/// Both devices are real: the wrist is the actual Wear OS engine over an
/// in-memory store, the phone is the actual `LiveSessionMirrorState`, and the
/// link between them is a loopback carrier the screen can sever. That is the one
/// thing a desktop run cannot provide, and it is exactly what this item is
/// about — so everything else is the shipping implementation.
library;

import 'package:flutter/material.dart';

import '../../core/constants/omni_theme.dart';
import '../../core/navigation/navigation.dart';
import '../../core/services/preferences_service.dart';
import '../../data/repositories/mock_workout_repository.dart';
import '../../features/session/live_session_screen.dart';
import '../../state/settings/settings_state.dart';
import '../../state/workout/workout_state.dart';
import '../../watch/logging/watch_logging_state.dart';
import '../../watch/session/in_memory_watch_session_store.dart';
import '../../watch/session/watch_session_engine.dart';
import '../../watch/session/watch_session_store.dart';
import '../../watch/start/watch_session_start_paths.dart';
import '../../watch/start/watch_sync_orchestrator.dart';
import 'live_session_mirror_state.dart';

/// Whether the QA surface was compiled in. The entry point below refuses to
/// mount without it, so a release build carries nothing.
const bool liveMirrorDebugEnabled = bool.fromEnvironment('LIVE_MIRROR_DEBUG');

/// The slot the harness starts its session on, shaped as the phone would send
/// it.
const List<Map<String, Object?>> _slots = [
  {
    'sessionExerciseId': 'sx-bench',
    'exerciseId': 'ex-barbell-bench-press',
    'name': 'Barbell Bench Press',
    'capabilities': ['sets', 'reps', 'load'],
  },
  {
    'sessionExerciseId': 'sx-plank',
    'exerciseId': 'ex-plank',
    'name': 'Plank',
    'capabilities': ['time', 'hold'],
  },
  {
    'sessionExerciseId': 'sx-squat',
    'exerciseId': 'ex-goblet-squat',
    'name': 'Goblet Squat',
    'capabilities': ['sets', 'reps', 'load'],
  },
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    MaterialApp(
      title: 'Live mirror debug',
      debugShowCheckedModeBanner: false,
      // Deliberately plain: this harness shows the link, not theme work.
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      home: liveMirrorDebugEnabled
          ? const _LiveMirrorDebugHarness()
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
            'Run with --dart-define=LIVE_MIRROR_DEBUG=true',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _LiveMirrorDebugHarness extends StatefulWidget {
  const _LiveMirrorDebugHarness();

  @override
  State<_LiveMirrorDebugHarness> createState() =>
      _LiveMirrorDebugHarnessState();
}

class _LiveMirrorDebugHarnessState extends State<_LiveMirrorDebugHarness> {
  final WatchSessionStore _store = InMemoryWatchSessionStore();
  final _Link _link = _Link();

  late final _WatchTransport _watchTransport = _WatchTransport(_link);
  late final _PhoneTransport _phoneTransport = _PhoneTransport(_link);

  late final WatchSessionEngine _engine = WatchSessionEngine(
    _store,
    onEmit: _watchTransport.send,
  );
  late final WatchSessionStartPaths _paths = WatchSessionStartPaths(
    engine: _engine,
    store: _store,
  );
  late final WatchSyncOrchestrator _orchestrator = WatchSyncOrchestrator(
    transport: _watchTransport,
    paths: _paths,
    engine: _engine,
  );
  late final LiveSessionMirrorState _mirror = LiveSessionMirrorState(
    transport: _phoneTransport,
    snapshot: {
      'sessionId': 's-debug-live',
      'status': 'active',
      'revision': 0,
      'currentExerciseIndex': 0,
      'exercises': _slots,
      'entries': const <Object?>[],
      'timers': const <String, Object?>{},
    },
  );

  /// The wrist's view of the same session, for the side-by-side readout.
  late final WatchLoggingState _wrist = WatchLoggingState(engine: _engine);

  String _note = 'not started';

  @override
  void initState() {
    super.initState();
    _link.toPhone = _mirror.receive;
    _link.toWatch = _orchestrator.receive;
    _mirror.addListener(_repaint);
    _launch();
  }

  @override
  void dispose() {
    _mirror.removeListener(_repaint);
    super.dispose();
  }

  void _repaint() {
    if (mounted) setState(() {});
  }

  Future<void> _launch() async {
    await _engine.restore();
    await _paths.restore();
    await _engine.createSession(
      modality: 'resistance_lifting',
      exercises: _slots,
    );
    await _orchestrator.sync();
    _note = 'session started on the wrist';
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live mirror')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const Text('Linked'),
            subtitle: Text(_link.linked ? 'carrying' : 'buffered'),
            value: _link.linked,
            onChanged: (linked) {
              setState(() => _link.linked = linked);
              if (linked) _reconnect();
            },
          ),
          _Readout(
            title: 'Wrist',
            lines: [
              'exercise: ${_wrist.exerciseName ?? "none"}',
              'revision: ${_engine.session?.revision ?? 0}',
              'entries: ${_engine.entries.length}',
              'owed to phone: ${_engine.pendingObservations().length}',
              'buffered: ${_link.upBuffered.length}',
            ],
          ),
          _Readout(
            title: 'Phone',
            lines: [
              'exercise index: ${_mirror.state['currentExerciseIndex']}',
              'revision: ${_mirror.state['revision']}',
              'entries: ${(_mirror.state['entries']! as List).length}',
              'sent: ${_phoneTransport.sent.length}',
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(_note),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _actionButton(onPressed: _logOnWrist, label: 'Log a set'),
              _actionButton(onPressed: _advanceWrist, label: 'Next exercise'),
              _actionButton(
                onPressed: _reorderOnPhone,
                label: 'Reorder on phone',
              ),
              _actionButton(
                onPressed: _manageOnPhone,
                label: 'Manage on phone',
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The states the live session screen needs to search the catalog and to show
  /// loads in the saved unit. Built on first use so the harness's own screen
  /// never waits on a repository.
  late final Future<({WorkoutState workoutState, SettingsState settingsState})>
  _phoneStates = _buildPhoneStates();

  static Future<({WorkoutState workoutState, SettingsState settingsState})>
  _buildPhoneStates() async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    final preferences = PreferencesServiceImpl();
    await preferences.init();
    final settingsState = SettingsState(repository, preferences);
    await settingsState.initialize();
    return (
      workoutState: WorkoutState(repository),
      settingsState: settingsState,
    );
  }

  /// Opens the shipping live session screen over the harness's session — the
  /// screen itself, not a debug stand-in for it.
  Future<void> _manageOnPhone() async {
    final states = await _phoneStates;
    if (!mounted) return;
    await OmniNavigator.push(
      context,
      (_) => LiveSessionScreen(
        liveSession: _mirror,
        workoutState: states.workoutState,
        settingsState: states.settingsState,
      ),
    );
  }

  /// One harness action. The shape is set explicitly because every button in
  /// the app does — a debug surface is not a reason to skip the button spec.
  Widget _actionButton({
    required VoidCallback onPressed,
    required String label,
  }) => FilledButton(
    style: ButtonStyle(
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OmniTheme.buttonUtilityRadius),
        ),
      ),
    ),
    onPressed: onPressed,
    child: Text(label),
  );

  Future<void> _logOnWrist() async {
    final slot = _engine.currentExercise;
    if (slot == null) return;
    final entryId = 'e-debug-${_engine.entries.length + 1}';
    await _engine.appendObservation({
      'entryId': entryId,
      'eventId': entryId,
      'kind': 'set',
      'loggedAt': _wrist.now().toUtc().toIso8601String(),
      'sessionExerciseId': slot['sessionExerciseId'],
      'exerciseId': slot['exerciseId'],
      'reps': 5,
      'loadKg': 80,
    });
    _note = 'logged $entryId on the wrist';
    setState(() {});
  }

  Future<void> _advanceWrist() async {
    await _engine.advanceExercise();
    _note = 'wrist advanced';
    setState(() {});
  }

  Future<void> _reorderOnPhone() async {
    final order = [
      for (final slot in _engine.session?.exercises ?? const [])
        slot['sessionExerciseId']! as String,
    ].reversed.toList();
    try {
      await _mirror.applyStructureChange([
        {'kind': 'reorder_exercises', 'order': order},
      ]);
      _note = 'phone reordered: ${order.join(", ")}';
    } on WatchEmissionRejected catch (error) {
      // A refusal is a QA observation, not a crash: the watch declined the
      // message, applied nothing, and answered with its own snapshot.
      _note = 'wrist refused the change: ${error.message}';
    }
    setState(() {});
  }

  /// What a reconnect does: the buffered arms go up, then both sides exchange
  /// snapshots.
  Future<void> _reconnect() async {
    await _link.flush();
    await _orchestrator.sync(reconnect: true);
    await _mirror.sync();
    _note = 'reconnected';
    setState(() {});
  }
}

class _Readout extends StatelessWidget {
  const _Readout({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          for (final line in lines) Text(line),
        ],
      ),
    );
  }
}

/// The in-process radio: one switch, two directions.
///
/// A severed link buffers rather than delivers, exactly as a store-and-forward
/// radio does, so the screen can model airplane mode by toggling `linked`.
class _Link {
  bool linked = true;

  /// What could not be carried while the link was down, per direction.
  final List<Map<String, Object?>> upBuffered = [];
  final List<Map<String, Object?>> downBuffered = [];

  /// Where each direction goes when the link is up.
  late final Future<void> Function(Map<String, Object?>) toPhone;
  late final Future<void> Function(Map<String, Object?>) toWatch;

  Future<void> up(Map<String, Object?> envelope) async {
    if (linked) {
      await toPhone(envelope);
    } else {
      upBuffered.add(envelope);
    }
  }

  Future<void> down(Map<String, Object?> envelope) async {
    if (linked) {
      await toWatch(envelope);
    } else {
      downBuffered.add(envelope);
    }
  }

  /// Carries everything buffered while the link was down, both ways.
  Future<void> flush() async {
    final up = [...upBuffered];
    final down = [...downBuffered];
    upBuffered.clear();
    downBuffered.clear();
    for (final envelope in up) {
      await toPhone(envelope);
    }
    for (final envelope in down) {
      await toWatch(envelope);
    }
  }
}

/// The link, watch end.
class _WatchTransport implements WatchSyncTransport {
  _WatchTransport(this.link);

  final _Link link;

  /// Everything that went up, whether or not it was carried.
  final List<Map<String, Object?>> sent = [];

  @override
  bool get isPhoneReachable => link.linked;

  @override
  Future<void> requestRoutines({DateTime? since}) async {}

  @override
  Future<void> requestSnapshot() async => link.flush();

  @override
  Future<void> send(Map<String, Object?> envelope) async {
    sent.add(envelope);
    await link.up(envelope);
  }
}

/// The link, phone end.
class _PhoneTransport implements WatchMirrorTransport {
  _PhoneTransport(this.link);

  final _Link link;

  /// Everything that went down, whether or not it was carried.
  final List<Map<String, Object?>> sent = [];

  @override
  Future<void> requestSnapshot() async => link.flush();

  @override
  Future<void> send(Map<String, Object?> envelope) async {
    sent.add(envelope);
    await link.down(envelope);
  }
}
