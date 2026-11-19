import 'diagnostics_storage.dart';

/// The storage the app uses when there is no file system: memory.
Future<DiagnosticsStorage> openDefaultDiagnosticsStorage() async =>
    InMemoryDiagnosticsStorage();

/// The watch-received log the web build never has: memory, empty, no time.
Future<WatchReceivedSource> openWatchReceivedStorage() async =>
    WatchReceivedSource(
      storage: InMemoryDiagnosticsStorage(),
      receivedAt: _neverReceived,
    );

DateTime? _neverReceived() => null;
