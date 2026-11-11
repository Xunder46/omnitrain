import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'diagnostics_storage.dart';
import 'diagnostics_storage_io.dart';

/// The watch-received file: `<app support>/watch-diagnostics/watch-received.jsonl`.
/// A directory that cannot be resolved in time falls back to memory, never a failure.
Future<WatchReceivedSource> openWatchReceivedStorage() async {
  try {
    // A platform call that never answers must not hold startup: after two
    // seconds the log keeps to memory for this run.
    final Directory base = await getApplicationSupportDirectory().timeout(
      const Duration(seconds: 2),
    );
    final storage = FileDiagnosticsStorage(
      File(p.join(base.path, 'watch-diagnostics', 'watch-received.jsonl')),
    );
    return WatchReceivedSource(storage: storage, receivedAt: storage.modified);
  } catch (_) {
    return WatchReceivedSource(
      storage: InMemoryDiagnosticsStorage(),
      receivedAt: _neverReceived,
    );
  }
}

DateTime? _neverReceived() => null;

/// The log's file: `<app support>/watch-diagnostics/phone-diagnostics.jsonl`.
/// A directory that cannot be resolved in time falls back to memory, never a failure.
Future<DiagnosticsStorage> openDefaultDiagnosticsStorage() async {
  try {
    // A platform call that never answers must not hold startup: after two
    // seconds the log keeps to memory for this run.
    final Directory base = await getApplicationSupportDirectory().timeout(
      const Duration(seconds: 2),
    );
    return FileDiagnosticsStorage(
      File(p.join(base.path, 'watch-diagnostics', 'phone-diagnostics.jsonl')),
    );
  } catch (_) {
    return InMemoryDiagnosticsStorage();
  }
}
