// filepath: lib/core/services/health_sync_service.dart
//
// The two opt-in health pipelines:
//
//   * write  — a completed session goes out to the platform health store
//     exactly once (gated by the `Write workouts` toggle, idempotent per
//     session id, S-008); deleting a finished session asks the store to
//     remove its workout again (plan 89, same toggle); a finished session's
//     rating becomes its workout's Workout Effort (plan 90, same toggle).
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
  Future<void> onSessionCompleted(TrainingSession session) async {
    final endedAtMs = session.endedAtMs;
    if (endedAtMs == null) return;
    if (!_isWriteEnabled()) return;
    if (_writtenThisRun.contains(session.id)) return;

    try {
      if (await _ledgerContains(session.id)) return;

      final written = await _platform.writeWorkout(
        HealthWorkoutDraft(
          activityKind: mapModalityToActivityKind(session.modality),
          start: DateTime.fromMillisecondsSinceEpoch(session.startedAtMs),
          end: DateTime.fromMillisecondsSinceEpoch(endedAtMs),
          title: session.title,
        ),
      );
      if (!written) {
        // Transient failure or permission revoked in the system settings.
        // Left unrecorded so the next completion attempt can retry; the
        // toggle itself is only flipped by an explicit user action.
        return;
      }

      _writtenThisRun.add(session.id);
      await _rememberWritten(session.id);
    } catch (e) {
      debugPrint('Health workout write skipped: $e');
    }
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
