// filepath: lib/core/services/health_sync_service.dart
//
// The two opt-in health pipelines:
//
//   * write  — a completed session goes out to the platform health store
//     exactly once (gated by the `Write workouts` toggle, idempotent per
//     session id, S-008).
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

  HealthSyncService({
    required HealthPlatformService platform,
    required WorkoutRepository repository,
    required bool Function() isWriteEnabled,
    required bool Function() isReadEnabled,
  }) : _platform = platform,
       _repository = repository,
       _isWriteEnabled = isWriteEnabled,
       _isReadEnabled = isReadEnabled;

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
