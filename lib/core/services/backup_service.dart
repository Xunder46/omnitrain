import '../../data/models/backup_codec.dart';
import '../../data/models/backup_snapshot.dart';
import '../../data/repositories/workout_repository.dart';
import '../constants/data_version.dart';
import '../models/app_version_info.dart';

/// Outcome of a restore: restored, or refused with a plain-words reason
/// (nothing was changed).
class BackupRestoreResult {
  const BackupRestoreResult.restored() : refusal = null;
  const BackupRestoreResult.refused(String reason) : refusal = reason;
  final String? refusal;
  bool get isRestored => refusal == null;
}

/// What a backup file holds, for the confirmation text.
class BackupInfo {
  const BackupInfo({
    required this.exportedAtMs,
    required this.appVersion,
    required this.sessions,
    required this.routines,
    required this.foods,
  });
  final int exportedAtMs;
  final String appVersion;
  final int sessions;
  final int routines;
  final int foods;
}

/// The result of reading a file without restoring: info, or the reason it
/// would be refused (format and version checks only).
class BackupCheck {
  const BackupCheck.ok(BackupInfo this.info) : refusal = null;
  const BackupCheck.refused(String this.refusal) : info = null;
  final BackupInfo? info;
  final String? refusal;
}

class BackupService {
  BackupService(this._repository, this._appVersion);
  final WorkoutRepository _repository;
  final AppVersionInfo _appVersion;

  static const String newerAppMessage =
      'This backup was made by a newer version of OmniTrain. '
      'Update the app and try again.';
  static const String runningWorkoutMessage =
      'Finish or discard your running workout first.';
  static const String failedMessage = 'Could not restore. Nothing was changed.';
  static const String partialMessage =
      'Could not restore. Some data may have changed.';

  Future<String> exportToText() async => encodeBackup(
    await _repository.exportSnapshot(),
    appVersion: _appVersion.version,
  );

  BackupCheck inspect(String text) {
    try {
      final snapshot = decodeBackup(text);
      if (snapshot.dataVersion > currentDataVersion) {
        return BackupCheck.refused(newerAppMessage);
      }
      final header = decodeBackupHeader(text);
      return BackupCheck.ok(
        BackupInfo(
          exportedAtMs: header.exportedAtMs,
          appVersion: header.appVersion,
          sessions: snapshot.collections['sessions']?.length ?? 0,
          routines: snapshot.collections['templates']?.length ?? 0,
          foods: snapshot.collections['foods']?.length ?? 0,
        ),
      );
    } on BackupFormatException catch (e) {
      return BackupCheck.refused(e.message);
    } catch (_) {
      return const BackupCheck.refused('This is not an OmniTrain backup file.');
    }
  }

  BackupInfo? describe(String text) => inspect(text).info;

  Future<BackupRestoreResult> restoreFromText(String text) async {
    // 1. Format and version checks first: a refused file never touches data.
    final check = inspect(text);
    if (check.refusal != null) {
      return BackupRestoreResult.refused(check.refusal!);
    }

    // 2. A workout still running on this phone blocks the restore; a rolling
    //    free session with no end does not.
    try {
      final running = await _repository.getInProgressSessions();
      if (running.any((s) => !s.isRolling)) {
        return const BackupRestoreResult.refused(runningWorkoutMessage);
      }
    } catch (_) {
      return const BackupRestoreResult.refused(failedMessage);
    }

    // 3. Take the rollback snapshot before anything is written.
    late final BackupSnapshot snapshot;
    late final BackupSnapshot rollback;
    try {
      snapshot = decodeBackup(text);
      rollback = await _repository.exportSnapshot();
    } catch (_) {
      return const BackupRestoreResult.refused(failedMessage);
    }

    // 4. Import; on any throw put the rollback back and refuse.
    try {
      await _repository.importSnapshot(snapshot);
      return const BackupRestoreResult.restored();
    } catch (_) {
      try {
        await _repository.importSnapshot(rollback);
        return const BackupRestoreResult.refused(failedMessage);
      } catch (_) {
        return const BackupRestoreResult.refused(partialMessage);
      }
    }
  }

  /// The local date of [now], zero-padded, in the share sheet's name.
  static String fileName(DateTime now) {
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return 'omnitrain-backup-${now.year}-$month-$day.json';
  }
}
