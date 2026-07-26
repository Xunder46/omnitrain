import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef _BaseDirectoryResolver = Future<String> Function();

class StartupFailureDiagnosticWriter {
  static const String diagnosticFileName =
      'omnitrain_startup_failure_latest.txt';

  final _BaseDirectoryResolver _resolveBaseDirectory;

  StartupFailureDiagnosticWriter._({
    required _BaseDirectoryResolver resolveBaseDirectory,
  }) : _resolveBaseDirectory = resolveBaseDirectory;

  StartupFailureDiagnosticWriter.create()
      : _resolveBaseDirectory = _defaultBaseDirectory;

  StartupFailureDiagnosticWriter.fromBaseDirectory(String baseDirectory)
      : _resolveBaseDirectory = (() async => baseDirectory);

  static Future<String> _defaultBaseDirectory() async {
    if (Platform.isAndroid) {
      final external = await getExternalStorageDirectory();
      if (external != null && external.path.isNotEmpty) {
        return external.path;
      }
    }

    final support = await getApplicationSupportDirectory();
    return support.path;
  }

  Future<void> writeLatestFailure(Object error, StackTrace stackTrace) async {
    try {
      final baseDirectory = await _resolveBaseDirectory();
      if (baseDirectory.isEmpty) return;

      final baseDir = Directory(baseDirectory);
      await baseDir.create(recursive: true);

      final filePath = p.join(baseDirectory, diagnosticFileName);
      final file = File(filePath);
      final payload = _buildPayload(error, stackTrace);

      // `writeAsString` uses FileMode.write by default, which
      // truncates existing content. This keeps only the latest failure.
      await file.writeAsString(payload, flush: true);
    } catch (_) {
      // Best-effort diagnostic channel only: never throw.
    }
  }

  String _buildPayload(Object error, StackTrace stackTrace) {
    final ts = DateTime.now().toUtc().toIso8601String();
    return [
      'timestamp_utc: $ts',
      'error: $error',
      '',
      'stack_trace:',
      '$stackTrace',
      '',
    ].join('\n');
  }
}
