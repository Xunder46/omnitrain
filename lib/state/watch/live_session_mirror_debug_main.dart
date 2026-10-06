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
import '../../core/services/preferences_service.dart';
import '../../core/utils/watch_reference_sync.dart';
import '../../data/models/models.dart';
import '../../data/repositories/mock_workout_repository.dart';
import '../../data/repositories/workout_repository.dart';
import '../../state/food_library_state.dart';
import '../../state/nutrition_state.dart';
import '../../state/settings/settings_state.dart';
import '../../state/workout/workout_state.dart';
import '../../watch/logging/watch_logging_state.dart';
import '../../watch/nutrition/watch_nutrition_state.dart';
import '../../watch/session/in_memory_watch_session_store.dart';
import '../../watch/session/watch_session_engine.dart';
import '../../watch/session/watch_session_store.dart';
import '../../watch/start/watch_session_start_paths.dart';
import '../../watch/start/watch_sync_orchestrator.dart';
import 'live_session_mirror_state.dart';
import 'watch_incoming_router.dart';
import 'watch_nutrition_log_bridge.dart';
import 'watch_session_inbox.dart';

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
  late final WatchNutritionState _wristNutrition = WatchNutritionState(
    engine: _engine,
    store: _store,
  );
  late final WatchSyncOrchestrator _orchestrator = WatchSyncOrchestrator(
    transport: _watchTransport,
    paths: _paths,
    engine: _engine,
    nutrition: _wristNutrition,
  );
  late final LiveSessionMirrorState _mirror = LiveSessionMirrorState(
    transport: _phoneTransport,
    snapshot: {
      'sessionId': 's-debug-live',
      'status': 'active',
      'revision': 0,
      'currentExerciseIndex': 0,
      'exercises': _slots,
      'entries': <Object?>[],
      'timers': const <String, Object?>{},
    },
  );

  /// The wrist's view of the same session, for the side-by-side readout.
  late final WatchLoggingState _wrist = WatchLoggingState(engine: _engine);

  /// Points a message from the wrist at both of its owners. Built with the
  /// phone states on first use, so the harness renders before a repository is
  /// touched.
  WatchIncomingRouter? _router;

  /// The phone states once they exist — what the readout reads the day log
  /// through.
  _PhoneStates? _states;

  /// How many rows the phone's day log holds. The day log's own count rather
  /// than a tally of messages: a food the wrist logged twice is one row.
  int get _dayLogRows => _states?.nutrition.consumedToday.length ?? 0;

  String _note = 'not started';

  @override
  void initState() {
    super.initState();
    _link.toPhone = _receiveFromWrist;
    _link.toWatch = _receiveFromPhone;
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

  /// The shipping router over the shipping states: session news to the mirror,
  /// and the food the user logged to the phone's own day log.
  Future<WatchIncomingRouter> _incomingRouter() async {
    final built = _router;
    if (built != null) return built;

    final states = _states = await _phoneStates;
    return _router = WatchIncomingRouter(
      inbox: WatchSessionInbox(
        repository: states.repository,
        transport: _phoneTransport,
      ),
      mirror: _mirror,
      nutrition: WatchNutritionLogBridge(
        nutrition: states.nutrition,
        library: states.foodLibrary,
        transport: _phoneTransport,
      ),
    );
  }

  /// One message arriving from the wrist. A quick-log leaves a row in the day
  /// log, which is what the Phone readout counts.
  Future<void> _receiveFromWrist(Map<String, Object?> envelope) async {
    final receipt = await (await _incomingRouter()).receive(envelope);
    if (receipt.loggedFood) {
      _note = 'phone filed a quick-log: $_dayLogRows rows in the day log';
      if (mounted) setState(() {});
    }
  }

  /// One message arriving from the phone. A receipt is the phone taking
  /// responsibility for what the wrist sent, which is the only thing that
  /// empties the wrist's `owed to phone` line.
  Future<void> _receiveFromPhone(Map<String, Object?> envelope) async {
    final changed = await _orchestrator.receive(envelope);
    if (!changed || !mounted) return;
    _note = envelope['type'] == 'receipt'
        ? 'phone took what the wrist sent: '
              '${_engine.pendingObservations().length} owed'
        : 'phone sent ${envelope['type']}';
    setState(() {});
  }

  Future<void> _launch() async {
    await _engine.restore();
    await _paths.restore();
    await _wristNutrition.restore();
    await _engine.createSession(
      modality: 'resistance_lifting',
      exercises: _slots,
    );
    await _orchestrator.sync();
    await _syncPhoneLists();
    _note = 'session started on the wrist';
    setState(() {});
  }

  /// The reference data the phone would send down, built by the phone's own
  /// builder from the phone's own library. The harness carries no radio, but the
  /// producer is the shipping one — as is the bridge the answers come back
  /// through.
  Future<void> _syncPhoneLists() async {
    final states = await _phoneStates;
    await _orchestrator.receive(
      WatchReferenceSync.buildFoodsDown(
        foods: states.foodLibrary.foods,
        groups: states.foodLibrary.activeFoodGroups,
        generatedAt: DateTime.now().toUtc(),
      ),
    );
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
              'foods synced: ${_wristNutrition.foods.length}',
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
              'day log: $_dayLogRows rows from the wrist',
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
              _actionButton(onPressed: _logFoodOnWrist, label: 'Log a food'),
              _actionButton(onPressed: _advanceWrist, label: 'Next exercise'),
              _actionButton(
                onPressed: _reorderOnPhone,
                label: 'Reorder on phone',
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The states the readout reads through: the catalog and settings the
  /// session side needs, plus the nutrition side the day log needs. Built on
  /// first use so the harness's own screen never waits on a repository.
  late final Future<_PhoneStates> _phoneStates = _buildPhoneStates();

  static Future<_PhoneStates> _buildPhoneStates() async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    for (final group in _seedFoodGroups) {
      await repository.createFoodGroup(group);
    }
    for (final food in _seedFoods) {
      await repository.createFood(food);
    }

    final preferences = PreferencesServiceImpl();
    await preferences.init();
    final settingsState = SettingsState(repository, preferences);
    await settingsState.initialize();

    final foodLibrary = FoodLibraryState(repository);
    await foodLibrary.loadFoodGroups();
    await foodLibrary.loadFoods();

    return _PhoneStates(
      repository: repository,
      workoutState: WorkoutState(repository),
      settingsState: settingsState,
      foodLibrary: foodLibrary,
      nutrition: NutritionState(repository),
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

  /// The loop this harness exists to show: a quick-log taken on the wrist with
  /// a workout running rides that session, is carried up, and is filed by the
  /// phone's day log rather than by the mirror.
  Future<void> _logFoodOnWrist() async {
    final foods = _wristNutrition.foods;
    if (foods.isEmpty) {
      _note = 'the wrist has no synced foods yet';
      setState(() {});
      return;
    }

    final food = foods.first;
    _wristNutrition.select(food.foodId);
    await _wristNutrition.logSelected();
    _note = 'logged ${food.name} on the wrist';
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

/// The states the harness's phone half runs on.
class _PhoneStates {
  const _PhoneStates({
    required this.repository,
    required this.workoutState,
    required this.settingsState,
    required this.foodLibrary,
    required this.nutrition,
  });

  /// The phone's storage, which the watch session inbox stages into.
  final WorkoutRepository repository;
  final WorkoutState workoutState;
  final SettingsState settingsState;
  final FoodLibraryState foodLibrary;
  final NutritionState nutrition;
}

/// The phone's own foods, so the harness's food messages are built from a
/// library the way the app builds them rather than hand-written. Macros are the
/// only thing the wire derives from; the rest the wrist reads as sent.
final List<FoodGroup> _seedFoodGroups = [
  FoodGroup(
    id: 'foodcat-protein',
    name: 'Protein',
    createdAtMs: 0,
    updatedAtMs: 0,
  ),
  FoodGroup(id: 'foodcat-carbs', name: 'Carbs', createdAtMs: 0, updatedAtMs: 0),
  FoodGroup(id: 'foodcat-fruit', name: 'Fruit', createdAtMs: 0, updatedAtMs: 0),
];

final List<Food> _seedFoods = [
  _seedFood(
    'food-oatmeal',
    'Oatmeal',
    groupId: 'foodcat-carbs',
    protein: 5,
    carbs: 34,
    fat: 3.5,
    lastAmountConsumed: 150,
  ),
  _seedFood(
    'food-banana',
    'Banana',
    groupId: 'foodcat-fruit',
    referenceAmount: 1,
    referenceLabel: 'banana',
    protein: 1.3,
    carbs: 23,
    fat: 0.3,
  ),
  _seedFood(
    'food-egg',
    'Egg',
    groupId: 'foodcat-protein',
    referenceAmount: 1,
    referenceLabel: 'egg',
    protein: 6.3,
    carbs: 0.6,
    fat: 5.3,
  ),
  _seedFood(
    'food-greek-yogurt',
    'Greek Yogurt',
    groupId: 'foodcat-protein',
    referenceAmount: 1,
    referenceLabel: 'cup',
    protein: 18,
    carbs: 8,
    fat: 4,
  ),
  _seedFood('food-almonds', 'Almonds', protein: 6, carbs: 6, fat: 15),
];

Food _seedFood(
  String id,
  String name, {
  String? groupId,
  double referenceAmount = 100,
  String referenceLabel = 'g',
  required double protein,
  required double carbs,
  required double fat,
  double? lastAmountConsumed,
}) => Food(
  id: id,
  name: name,
  groupId: groupId,
  unitType: FoodUnitType.grams,
  referenceAmount: referenceAmount,
  referenceLabel: referenceLabel,
  protein: protein,
  carbs: carbs,
  fat: fat,
  lastAmountConsumed: lastAmountConsumed,
  createdAtMs: 0,
  updatedAtMs: 0,
);

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
