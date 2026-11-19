// Public entry point for the diagnostics log's default storage.
//
// Native targets keep the log in one file in the app's support directory; web
// keeps it in memory (plan 143, D-14301). Same shape as
// `startup_failure_diagnostic_writer.dart`.

export 'diagnostics_storage_default_stub.dart'
    if (dart.library.io) 'diagnostics_storage_default_io.dart';
