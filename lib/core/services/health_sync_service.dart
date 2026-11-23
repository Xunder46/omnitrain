// filepath: lib/core/services/health_sync_service.dart
//
// The two opt-in health pipelines:
//
//   * write  — a completed session goes out to the platform health store
//     exactly once (gated by the `Write workouts` toggle, idempotent per
//     session id, S-008); deleting a finished session asks the store to
//     remove its workout again (plan 89, same toggle); a finished session's
//     rating becomes its workout's Workout Effort (plan 90, same toggle);
//     a catch-up that moves a finished session's end rewrites its workout to
//     the new window (plan 146c D-14634), never one the wrist saved
//     (D-14636).
//   * read   — body weight comes back on app foreground (gated by the
//     `Read body weight` toggle) and is merged into the stored
//     measurement history.
//
// Both directions are deliberately best-effort: nothing in here ever
// throws, prompts, or blocks the session lifecycle or the UI. The
// permission prompt happens only when the user flips a toggle
// (SettingsState owns the toggles); a foreground read that lacks
// permission simply yields nothing.
//
// Layer note: this is the lowest layer, so it depends on the repository and
// the platform gateway only. Toggle state arrives as callbacks rather than a
// `SettingsState` reference, and the read reports what it imported instead of
// pushing the result into `ProfileState`. The caller owns the refresh.

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../data/models/models.dart';
import '../../data/repositories/workout_repository.dart';
import '../constants/health_constants.dart';
import '../constants/profile_measurements.dart';
import '../../watch/sensors/watch_platform_workout.dart';
import '../utils/watch_reference_sync.dart';
import 'health_effort_mapper.dart';
import 'health_modality_mapper.dart';
import 'health_platform_service.dart';

/// Namespace for imported body-weight rows, so they are distinguishable
/// from user-logged measurements.
const String _importedWeightPrefix = 'health-bodyweight-';

class HealthSyncService {
  final HealthPlatformService _platform;
  final WorkoutRepository _repository;
  final bool Function() _isWriteEnabled;
  final bool Function() _isReadEnabled;

  /// The measured energy each workout written or rewritten this run carries,
  /// so the same energy arriving again rewrites nothing (plan 307 D-30704).
  final Map<String, double> _energyWritten = {};

  /// The sessions a wrist ran, as the phone's end told this run (plan 308
  /// D-30804), so a later rewrite types the workout the way the first write did.
  final Set<String> _wristRan = {};

  /// Sessions written during this process. The persisted ledger covers
  /// restarts; this set also prevents a double fire within one run
  /// without a ledger round-trip.
  final Set<String> _writtenThisRun = {};

  /// How long the effort write waits before each retry (plan 90 D-3). Tests
  /// inject a delay they release by hand.
  final Future<void> Function(Duration) _effortRetryDelay;

  HealthSyncService({
    required HealthPlatformService platform,
    required WorkoutRepository repository,
    required bool Function() isWriteEnabled,
    required bool Function() isReadEnabled,
    Future<void> Function(Duration)? effortRetryDelay,
  }) : _platform = platform,
       _repository = repository,
       _isWriteEnabled = isWriteEnabled,
       _isReadEnabled = isReadEnabled,
       _effortRetryDelay = effortRetryDelay ?? Future<void>.delayed;

  /// Writes a completed session to the platform health store when the
  /// user has opted in. Safe to call again for the same session — the
  /// platform is touched at most once per session id.
  ///
  /// [wristRan] is true for a session a wrist ran (plan 308): the workout is
  /// then typed the way the wrist's own rule types it, so a Wear watch's workout
  /// reads as the Apple watch's does.
  Future<void> onSessionCompleted(
    TrainingSession session, {
    bool wristRan = false,
  }) async {
    final endedAtMs = session.endedAtMs;
    if (endedAtMs == null) return;
    if (!_isWriteEnabled()) return;
    if (_writtenThisRun.contains(session.id)) return;
    if (wristRan) _wristRan.add(session.id);

    try {
      if (await _ledgerContains(session.id)) return;

      final energyKcal = await _measuredEnergyKcal(session.id);
      final written = await _platform.writeWorkout(
        HealthWorkoutDraft(
          activityKind: await _activityKindOf(session),
          start: DateTime.fromMillisecondsSinceEpoch(session.startedAtMs),
          end: DateTime.fromMillisecondsSinceEpoch(endedAtMs),
          title: session.title,
          energyKcal: energyKcal,
          activityTypeName: await _wristTypeNameOf(session, wristRan: wristRan),
        ),
      );
      if (!written) {
        // Transient failure or permission revoked in the system settings.
        // Left unrecorded so the next completion attempt can retry; the
        // toggle itself is only flipped by an explicit user action.
        return;
      }

      _writtenThisRun.add(session.id);
      if (energyKcal != null) _energyWritten[session.id] = energyKcal;
      await _rememberWritten(session.id);
    } catch (e) {
      debugPrint('Health workout write skipped: $e');
    }
  }

  /// Rewrites the workout of a finished session whose end moved later
  /// (D-14634), so the store's span follows the session (S-14670).
  ///
  /// The delete and the effort clear ask for `[startedAtMs, startedAtMs + 1 s)`
  /// — the start the write used and nothing that starts later (D-15501), so a
  /// workout this app wrote for a later session inside the old extended window
  /// is never touched, and a repeated move still leaves exactly one. The rating
  /// is re-applied over the new span; a session with no rating writes none. The
  /// ledger is never touched — the session stays written, and a repeated
  /// catch-up with the same end sends nothing.
  ///
  /// Only a session the ledger names is rewritten: a workout the wrist saved
  /// carries heart rate, energy and a route, and replacing it with a bare
  /// phone draft would lose them, so such a session is left entirely alone
  /// (D-14636, S-14671). Best-effort like the other paths: nothing throws, and
  /// a delete or write the platform refuses ends the call silently.
  ///
  /// D-15404: the delete runs before the write, so a new write that fails —
  /// returns false or throws — writes the span the workout had back again
  /// instead of leaving it deleted. The ledger is not touched either way: the
  /// session is still written, and the store still holds a workout for it.
  Future<void> rewriteWorkout(
    TrainingSession session, {
    required int previousEndedAtMs,
  }) async {
    final endedAtMs = session.endedAtMs;
    if (endedAtMs == null) return;
    if (!_isWriteEnabled()) return;
    if (endedAtMs <= previousEndedAtMs) return;
    await _replaceWorkout(session, previousEndedAtMs: previousEndedAtMs);
  }

  /// A workout a watch measured the energy of arrives after the workout was
  /// written (plan 307 D-30704): the wrist's `completed` ends the session
  /// first and the end entry carrying the energy is imported a moment later.
  /// When the ledger names the session as written by this phone and the
  /// measured energy differs from what the workout carries, the workout is
  /// replaced once with it. A session this phone did not write (the Apple
  /// watch's own workout) is left entirely alone, the same rule as
  /// [rewriteWorkout]. Best-effort: nothing throws.
  Future<void> onEnergyAttached(TrainingSession session) async {
    final endedAtMs = session.endedAtMs;
    if (endedAtMs == null) return;
    if (!_isWriteEnabled()) return;
    try {
      final energyKcal = await _measuredEnergyKcal(session.id);
      if (energyKcal == null) return;
      if (_energyWritten[session.id] == energyKcal) return;
      // The ledger check is `_replaceWorkout`'s: a session this phone did not
      // write is left alone there.
      await _replaceWorkout(
        session,
        previousEndedAtMs: endedAtMs,
        energyKcal: energyKcal,
      );
    } catch (e) {
      debugPrint('Health workout energy update skipped: $e');
    }
  }

  /// The energy a watch measured for the session, in whole kilocalories, or
  /// null for none and for an estimate: an estimate is never written to a
  /// health store as if it had been measured.
  Future<double?> _measuredEnergyKcal(String sessionId) async {
    try {
      final energy = await _repository.getSessionEnergy(sessionId);
      if (energy == null || energy.source != SessionEnergy.sourceMeasured) {
        return null;
      }
      final kcal = energy.activeKcal;
      return kcal.isFinite && kcal > 0 ? kcal.roundToDouble() : null;
    } catch (_) {
      return null;
    }
  }

  /// The delete-then-write at the heart of [rewriteWorkout], with the energy
  /// the session now carries (D-15404: a write that fails writes the previous
  /// span back).
  Future<void> _replaceWorkout(
    TrainingSession session, {
    required int previousEndedAtMs,
    double? energyKcal,
  }) async {
    final endedAtMs = session.endedAtMs;
    if (endedAtMs == null) return;
    energyKcal ??= await _measuredEnergyKcal(session.id);
    try {
      if (!await _ledgerContains(session.id)) return;

      final start = DateTime.fromMillisecondsSinceEpoch(session.startedAtMs);
      // D-15501: the session's own start only, so a workout this app wrote for
      // a later session is never deleted; the 1 s margin absorbs the store's
      // date rounding.
      final windowEnd = start.add(const Duration(seconds: 1));
      final end = DateTime.fromMillisecondsSinceEpoch(endedAtMs);
      // Read before the delete: a repository failure here must not leave the
      // workout deleted with nothing written in its place (D-15404).
      final activityKind = await _activityKindOf(session);
      final typeName = await _wristTypeNameOf(session);

      final deleted = await _platform.deleteWorkouts(start, windowEnd);
      if (!deleted) return;

      try {
        await _platform.clearWorkoutEffort(start, windowEnd);
      } catch (e) {
        debugPrint('Health workout effort clear skipped: $e');
      }

      var written = false;
      try {
        written = await _platform.writeWorkout(
          HealthWorkoutDraft(
            activityKind: activityKind,
            start: start,
            end: end,
            title: session.title,
            energyKcal: energyKcal,
            activityTypeName: typeName,
          ),
        );
      } catch (e) {
        debugPrint('Health workout write skipped: $e');
      }
      if (!written) {
        await _restorePreviousSpan(
          session,
          activityKind: activityKind,
          activityTypeName: typeName,
          start: start,
          previousEndedAtMs: previousEndedAtMs,
        );
        return;
      }
      if (energyKcal != null) _energyWritten[session.id] = energyKcal;

      final rating = session.sessionFeeling;
      final score = rating == null ? null : ratingToAppleEffort(rating);
      if (score != null) {
        await _platform.setWorkoutEffort(start, end, score);
      }
    } catch (e) {
      debugPrint('Health workout rewrite skipped: $e');
    }
  }

  /// D-15404: writes a failed rewrite's previous span back, with the rating it
  /// had — the clear took that off — so the delete the rewrite already ran
  /// cannot lose the workout (S-15409). The ledger is left as it is: the
  /// session is still written. Best-effort, like every other path here: a
  /// refusal or an error ends the call silently.
  Future<void> _restorePreviousSpan(
    TrainingSession session, {
    required HealthActivityKind activityKind,
    String? activityTypeName,
    required DateTime start,
    required int previousEndedAtMs,
  }) async {
    try {
      final end = DateTime.fromMillisecondsSinceEpoch(previousEndedAtMs);
      final written = await _platform.writeWorkout(
        HealthWorkoutDraft(
          activityKind: activityKind,
          start: start,
          end: end,
          title: session.title,
          activityTypeName: activityTypeName,
        ),
      );
      if (!written) return;

      final rating = session.sessionFeeling;
      final score = rating == null ? null : ratingToAppleEffort(rating);
      if (score != null) {
        await _platform.setWorkoutEffort(start, end, score);
      }
    } catch (e) {
      debugPrint('Health workout restore skipped: $e');
    }
  }

  /// The Health Connect exercise name the wrist's own rule gives a session a
  /// wrist ran, or null for a session it did not run (plan 308 D-30804).
  ///
  /// A wrist ran it when the caller says so or this run was told so earlier, or
  /// when the phone holds a watch-origin inbox row for it (the later paths after
  /// a restart). The inputs are the session's modality and its exercises in
  /// session order, each as the slot the phone sends the wrist: its capabilities
  /// and the Health kind the phone names for it. A session with no modality uses
  /// only its first exercise, because the wrist fixes the type when the first
  /// exercise opens the workout and never retypes it. Nothing throws.
  Future<String?> _wristTypeNameOf(
    TrainingSession session, {
    bool wristRan = false,
  }) async {
    try {
      var ran = wristRan || _wristRan.contains(session.id);
      if (!ran) {
        ran = (await _repository.getWatchInboxEntriesForSession(
          session.id,
        )).any((row) => row.origin == WatchInboxEntry.originWatch);
      }
      if (!ran) return null;

      // Both repositories return a session's segments and a segment's efforts in
      // the session's own order, which is the order the wrist's rule reads.
      final segments =
          (await _repository.getSegmentsBySession())[session.id] ?? const [];
      final effortsBySegment = await _repository.getEffortsBySegment();
      final exercises = {
        for (final row in await _repository.getExercises()) row.id: row,
      };
      final slots = <Map<String, Object?>>[];
      for (final segment in segments) {
        // The repository's own order: top-level position, then block position
        // (not the raw `orderIndex`, which a block can contradict).
        for (final effort in effortsBySegment[segment.id] ?? const []) {
          final exercise = exercises[effort.exerciseId];
          if (exercise == null) continue;
          slots.add({
            'capabilities': exercise.capabilities,
            'healthActivity': WatchReferenceSync.healthActivityOf(
              disciplineId: exercise.disciplineId,
              exerciseId: exercise.id,
            ),
          });
        }
      }
      final used = session.modality == null ? slots.take(1).toList() : slots;
      return WatchActivityTypes.forModalityAndExercises(
        session.modality,
        used,
      )?.wear;
    } catch (_) {
      return null;
    }
  }

  /// The discipline id every exercised row of the session must carry for the
  /// write to pick the yoga kind (D-19313 of plan 119).
  static const String _yogaDisciplineId = 'discipline-yoga';

  /// The activity kind a completed phone workout records as: Yoga when the
  /// session's segments look up to exercises ALL under the Yoga discipline
  /// (and at least one effort names an exercised id), the modality mapping
  /// otherwise — a mixed session, a deleted custom or an empty one never
  /// half-labels (S-19311).
  Future<HealthActivityKind> _activityKindOf(TrainingSession session) async {
    final effortsBySegment = await _repository.getEffortsBySegment();
    final segments = (await _repository.getSegmentsBySession())[session.id];
    if (segments == null || segments.isEmpty) {
      return mapModalityToActivityKind(session.modality);
    }
    final efforts = [
      for (final segment in segments) ...effortsBySegment[segment.id] ?? [],
    ];
    if (efforts.isEmpty) {
      return mapModalityToActivityKind(session.modality);
    }

    final rows = await _repository.getExercises();
    final disciplineById = {for (final row in rows) row.id: row.disciplineId};
    for (final effort in efforts) {
      final id = effort.exerciseId;
      if (id == null || disciplineById[id] != _yogaDisciplineId) {
        return mapModalityToActivityKind(session.modality);
      }
    }
    return HealthActivityKind.yoga;
  }

  /// When a `noWorkout` answer is tried again, counted from the first try
  /// (plan 90 D-3): a watch workout reaches the phone's store a little after
  /// the finish. After the last one the write gives up (limit L-1).
  static const List<Duration> effortRetryOffsets = [
    Duration(seconds: 20),
    Duration(seconds: 90),
    Duration(minutes: 5),
  ];

  /// The newest effort write per session, by a token no write reuses: a write
  /// whose token is no longer here was overtaken by a newer rating or by the
  /// session's delete, and drops its pending retries (S-90-4).
  final Map<String, int> _effortWriteBySession = {};
  int _effortWrites = 0;

  /// Writes a finished session's rating to its workout as Workout Effort
  /// when the user has opted in to writing workouts (plan 90 D-3).
  ///
  /// The span is the session's own `[startedAtMs, endedAtMs]`, the one the
  /// delete uses. A session with no end or no rating asks nothing. Only a
  /// `noWorkout` answer is retried, on [effortRetryOffsets]; every other
  /// answer, and any error, ends the write silently.
  Future<void> onSessionRated(TrainingSession session) async {
    final endedAtMs = session.endedAtMs;
    final rating = session.sessionFeeling;
    if (endedAtMs == null || rating == null) return;
    final score = ratingToAppleEffort(rating);
    if (score == null) return;
    if (!_isWriteEnabled()) return;

    final token = ++_effortWrites;
    _effortWriteBySession[session.id] = token;
    final start = DateTime.fromMillisecondsSinceEpoch(session.startedAtMs);
    final end = DateTime.fromMillisecondsSinceEpoch(endedAtMs);

    try {
      var waited = Duration.zero;
      for (final offset in [Duration.zero, ...effortRetryOffsets]) {
        if (offset > waited) {
          await _effortRetryDelay(offset - waited);
          waited = offset;
          if (_effortWriteBySession[session.id] != token) return;
          if (!_isWriteEnabled()) return;
        }
        final outcome = await _platform.setWorkoutEffort(start, end, score);
        if (outcome != HealthEffortOutcome.noWorkout) return;
      }
    } catch (e) {
      debugPrint('Health workout effort skipped: $e');
    } finally {
      if (_effortWriteBySession[session.id] == token) {
        _effortWriteBySession.remove(session.id);
      }
    }
  }

  /// Asks the platform store to remove the workout of a deleted, finished
  /// session when the user has opted in to writing workouts (plan 89 D-4).
  ///
  /// The window is the session's own `[startedAtMs, endedAtMs]` and nothing
  /// wider (D-5). It is asked for whether or not the ledger names the
  /// session, since a workout the watch saved has no ledger entry. A session
  /// still in progress was never written by the phone and asks nothing.
  /// Best-effort: a refusal or an error is logged and swallowed.
  Future<void> onSessionDeleted(TrainingSession session) async {
    final endedAtMs = session.endedAtMs;
    if (endedAtMs == null) return;
    if (!_isWriteEnabled()) return;

    _writtenThisRun.remove(session.id);
    _effortWriteBySession.remove(session.id);
    try {
      await _forgetWritten(session.id);
    } catch (e) {
      debugPrint('Health ledger cleanup skipped: $e');
    }

    // Plan 90 D-5: the effort first, while the workout it hangs on is still
    // there to find.
    try {
      await _platform.clearWorkoutEffort(
        DateTime.fromMillisecondsSinceEpoch(session.startedAtMs),
        DateTime.fromMillisecondsSinceEpoch(endedAtMs),
      );
    } catch (e) {
      debugPrint('Health workout effort clear skipped: $e');
    }

    try {
      await _platform.deleteWorkouts(
        DateTime.fromMillisecondsSinceEpoch(session.startedAtMs),
        DateTime.fromMillisecondsSinceEpoch(endedAtMs),
      );
    } catch (e) {
      debugPrint('Health workout delete skipped: $e');
    }
  }

  /// Imports body weight from the platform store and returns the rows it
  /// wrote, so the caller can refresh whatever displays them. Empty when the
  /// toggle is off, nothing was available, or the platform refused. Called on
  /// app foreground; never prompts for permission and never throws.
  Future<List<BodyMeasurementEntry>> syncOnForeground() async {
    if (!_isReadEnabled()) return const [];

    try {
      final since = DateTime.now().subtract(
        const Duration(days: HealthPrefs.bodyWeightLookbackDays),
      );
      final samples = await _platform.readBodyWeightSince(since);
      if (samples.isEmpty) return const [];

      final imported = [for (final sample in samples) _entryFor(sample)];
      for (final entry in imported) {
        await _repository.saveMeasurementEntry(entry);
      }
      return imported;
    } catch (e) {
      debugPrint('Health body weight import skipped: $e');
      return const [];
    }
  }

  /// Deterministic id per platform sample: re-reading the same sample
  /// upserts the same row instead of appending a duplicate.
  BodyMeasurementEntry _entryFor(HealthWeightSample sample) {
    final dedupeKey =
        sample.sourceId ?? '${sample.sampledAt.millisecondsSinceEpoch}';
    return BodyMeasurementEntry(
      id: '$_importedWeightPrefix$dedupeKey',
      measurementType: ProfileMeasurements.bodyweight.type,
      value: sample.kilograms,
      unitId: ProfileMeasurements.bodyweight.unitId,
      recordedAtMs: sample.sampledAt.millisecondsSinceEpoch,
    );
  }

  Future<bool> _ledgerContains(String sessionId) async {
    final ids = await _loadLedger();
    return ids.contains(sessionId);
  }

  Future<void> _rememberWritten(String sessionId) async {
    final ids = await _loadLedger();
    if (ids.contains(sessionId)) return;
    ids.add(sessionId);
    final trimmed = ids.length > HealthPrefs.writtenSessionIdLimit
        ? ids.sublist(ids.length - HealthPrefs.writtenSessionIdLimit)
        : ids;
    await _repository.setPreferenceString(
      HealthPrefs.writtenSessionIdsKey,
      jsonEncode(trimmed),
    );
  }

  Future<void> _forgetWritten(String sessionId) async {
    final ids = await _loadLedger();
    if (!ids.remove(sessionId)) return;
    await _repository.setPreferenceString(
      HealthPrefs.writtenSessionIdsKey,
      jsonEncode(ids),
    );
  }

  Future<List<String>> _loadLedger() async {
    final raw = await _repository.getPreferenceString(
      HealthPrefs.writtenSessionIdsKey,
      defaultValue: '[]',
    );
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded.whereType<String>().toList();
    } catch (_) {
      // Corrupt ledger: start over rather than blocking future writes.
      return [];
    }
  }
}
