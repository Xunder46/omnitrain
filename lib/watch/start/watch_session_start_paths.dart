/// The two ways a session starts on the wrist, and everything that happens to
/// the exercise ladder afterwards.
///
/// Plan: `docs/plans/2026-07-13-08-b-watch-session-start-paths-plan.md`,
/// scenarios S-001 to S-005.
///
/// The full catalog never reaches the watch (a 23-sport catalog on a 40mm screen
/// is misery, and it duplicates data for no benefit). What the wrist holds is
/// reference data the phone sent down: the user's routines, and a fallback
/// exercise list that covers every one of them — which is why both paths work
/// with the phone switched off, and why starting a session is a read of local
/// storage rather than a request to the phone.
///
/// The phone is still the owner of session structure (PROTOCOL.md, authority
/// rule 2). A pushed exercise lands through [WatchSessionEngine.applyExercisePush];
/// nothing here originates a routine or edits one.
library;

import 'package:uuid/uuid.dart';

import '../../core/sync_protocol/message_validator.dart';
import '../session/watch_records.dart';
import '../session/watch_session_engine.dart';
import '../session/watch_session_store.dart';
import 'watch_fallback_list.dart';
import 'watch_routine_catalog.dart';

/// What happened to a `routines_down` message.
class WatchCatalogSyncResult {
  const WatchCatalogSyncResult({required this.decision, required this.applied});

  /// The receiver's verdict on the message, in the shape the protocol defines.
  final SyncMessageDecision decision;

  /// True when this message became the catalog the watch reads. A conformant
  /// message older than the cached one is understood and dropped, so it is
  /// false without being a rejection.
  final bool applied;
}

class WatchSessionStartPaths {
  WatchSessionStartPaths({
    required WatchSessionEngine engine,
    required WatchSessionStore store,
    SyncProtocolValidator? validator,
    DateTime Function()? clock,
    String Function()? idFactory,
  }) : _engine = engine,
       _store = store,
       _validator = validator,
       _clock = clock ?? _utcNow,
       _newId = idFactory ?? _uuid;

  static const Uuid _uuidV4 = Uuid();

  static DateTime _utcNow() => DateTime.now().toUtc();

  static String _uuid() => _uuidV4.v4();

  final WatchSessionEngine _engine;
  final WatchSessionStore _store;
  final SyncProtocolValidator? _validator;
  final DateTime Function() _clock;
  final String Function() _newId;

  WatchRoutineCatalogRecord? _catalog;
  List<WatchRoutine> _routines = const [];
  List<WatchCatalogExercise> _syncedFallback = const [];
  List<WatchCatalogExercise> _recents = const [];

  /// Whether the phone can be reached right now — what the wrist's
  /// search-on-phone affordance is shown on. The sync orchestrator is what
  /// knows, and it writes the flag here so the surfaces have one place to read.
  bool phoneReachable = false;

  /// The user's routines, as last synced. Empty until the phone has sent them.
  List<WatchRoutine> get routines => List.unmodifiable(_routines);

  /// When the phone generated the catalog the watch is holding, or null when no
  /// phone has sent one yet.
  DateTime? get syncedAt => _catalog?.generatedAt;

  /// Everything the wrist may offer offline, recents first (S-003).
  List<WatchCatalogExercise> get fallbackExercises => List.unmodifiable(
    deriveFallbackExercises(
      recents: _recents,
      syncedFallback: _syncedFallback,
      routines: _routines,
    ),
  );

  // ---------------------------------------------------------------------------
  // Storage
  // ---------------------------------------------------------------------------

  /// Reads the catalog and the watch's own usage back out of storage. Call on
  /// launch, and after any suspension: what comes back is what the watch knew
  /// at kill time.
  Future<void> restore() async {
    final contents = await _store.readAll();

    _catalog = contents.routineCatalogs.isEmpty
        ? null
        : contents.routineCatalogs.reduce(
            (newest, row) => row.sequence > newest.sequence ? row : newest,
          );

    final catalog = _catalog;
    if (catalog == null) {
      _routines = const [];
      _syncedFallback = const [];
    } else {
      final synced = WatchRoutinesDown.fromCatalog(catalog);
      _routines = synced.routines;
      _syncedFallback = synced.fallbackExercises;
    }

    _recents = _recentlyUsed(contents.sessions);
  }

  /// Applies a `routines_down` message: the routines, and the fallback list
  /// that covers them.
  ///
  /// The message is stored whole and the newest one wins, so the list the user
  /// sees updates on the next background sync with no action from them (S-004).
  Future<WatchCatalogSyncResult> applyRoutinesDown(
    Map<String, Object?> envelope,
  ) async {
    final decision = SyncProtocolValidator.evaluateOrAccept(
      _validator,
      envelope,
    );
    if (!decision.accepted) {
      return WatchCatalogSyncResult(decision: decision, applied: false);
    }

    final sent = WatchRoutinesDown.fromEnvelope(envelope);
    final cached = _catalog;
    if (cached != null && sent.generatedAt.isBefore(cached.generatedAt)) {
      return WatchCatalogSyncResult(
        decision: SyncMessageDecision(
          decision: SyncProtocolValidator.acceptDecision,
          reason:
              'an older view of the routines is not a newer truth; '
              'the catalog generated at ${utcIso(cached.generatedAt)} stands',
          respondWithSnapshot: false,
          rejections: const [],
        ),
        applied: false,
      );
    }

    _catalog = await _store.append(
      sent.toRecord(recordId: _newId(), recordedAt: _clock()),
    );
    _routines = sent.routines;
    _syncedFallback = sent.fallbackExercises;

    return WatchCatalogSyncResult(decision: decision, applied: true);
  }

  // ---------------------------------------------------------------------------
  // Path 1 — from a routine
  // ---------------------------------------------------------------------------

  /// Starts the routine [routineId] names, exactly as its template dictates.
  ///
  /// The routine's efforts become the session's slots — one per effort, so a
  /// routine that names the same exercise twice gets two of them. Each slot
  /// carries the capabilities the phone resolved the exercise from, which is
  /// what makes the logging surface the right one without asking the phone.
  ///
  /// The session carries no modality: `routines_down` has no field for one, so
  /// the wrist resolves each exercise from its capabilities instead of guessing
  /// from the routine. See the plan's open items.
  Future<WatchSessionRecord> startFromRoutine(String routineId) async {
    final routine = _routine(routineId);
    return _engine.createSession(modality: null, exercises: routine.slots);
  }

  // ---------------------------------------------------------------------------
  // Path 2 — free workout
  // ---------------------------------------------------------------------------

  /// Starts an empty session. Exercises are added one at a time, from the
  /// fallback list or by a push from the phone.
  Future<WatchSessionRecord> startFreeWorkout() =>
      _engine.createSession(modality: null);

  /// Adds [exercise] to the live session and moves the user to it.
  ///
  /// Choosing an exercise *is* a request to do it, so the session follows the
  /// pick — unlike a push from the phone, which must not move the user
  /// mid-set.
  Future<WatchSessionRecord> addExerciseToSession(
    WatchCatalogExercise exercise, {
    int? atIndex,
  }) => _engine.insertExercise(
    exercise.toSlot(sessionExerciseId: _availableSlotId(exercise)),
    atIndex: atIndex,
    moveTo: true,
  );

  // ---------------------------------------------------------------------------
  // Derived state
  // ---------------------------------------------------------------------------

  WatchRoutine _routine(String routineId) {
    for (final routine in _routines) {
      if (routine.routineId == routineId) return routine;
    }
    throw StateError(
      'no routine "$routineId": the phone has not synced one by that id',
    );
  }

  /// A slot id the session is not using yet. The same exercise may legitimately
  /// fill two slots — that is what a superset is — so a second pick gets its
  /// own id rather than being swallowed as a duplicate.
  String _availableSlotId(WatchCatalogExercise exercise) {
    final taken = {
      for (final slot
          in _engine.session?.exercises ?? const <Map<String, Object?>>[])
        slot['sessionExerciseId'],
    };

    final base = exercise.slotId;
    if (!taken.contains(base)) return base;
    for (var suffix = 2; ; suffix++) {
      final candidate = '$base-$suffix';
      if (!taken.contains(candidate)) return candidate;
    }
  }

  /// The exercises the wrist used most recently, newest session first.
  ///
  /// Read out of the sessions the watch already keeps rather than written to a
  /// list of its own: a relaunch cannot lose what storage already held.
  static List<WatchCatalogExercise> _recentlyUsed(
    List<WatchSessionRecord> rows,
  ) {
    final newestPerSession = <String, WatchSessionRecord>{};
    for (final row in rows) {
      final known = newestPerSession[row.sessionId];
      if (known == null || row.sequence > known.sequence) {
        newestPerSession[row.sessionId] = row;
      }
    }

    final ordered = newestPerSession.values.toList()
      ..sort((a, b) => b.sequence.compareTo(a.sequence));

    final seen = <String>{};
    final recents = <WatchCatalogExercise>[];
    for (final session in ordered) {
      for (final slot in session.exercises) {
        final exercise = WatchCatalogExercise.fromSlot(slot);
        if (exercise != null && seen.add(exercise.exerciseId)) {
          recents.add(exercise);
        }
      }
    }
    return List.unmodifiable(recents);
  }
}
