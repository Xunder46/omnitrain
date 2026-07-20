class StartupFailureDiagnosticWriter {
  static const String diagnosticFileName =
      'omnitrain_startup_failure_latest.txt';

  StartupFailureDiagnosticWriter.create();

  StartupFailureDiagnosticWriter.fromBaseDirectory(String baseDirectory);

  Future<void> writeLatestFailure(Object error, StackTrace stackTrace) async {
    // Web/no-IO targets intentionally do nothing.
  }
}
