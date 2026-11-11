import 'diagnostics_storage.dart';

/// The storage the app uses when there is no file system: memory.
Future<DiagnosticsStorage> openDefaultDiagnosticsStorage() async =>
    InMemoryDiagnosticsStorage();
