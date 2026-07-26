// Public entry point for startup failure diagnostic persistence.
//
// Native targets use an IO implementation that writes the latest
// startup failure to a fixed file in app-private storage.
// Web selects a no-op stub.

export 'startup_failure_diagnostic_writer_stub.dart'
    if (dart.library.io) 'startup_failure_diagnostic_writer_io.dart';
