// filepath: lib/core/services/health_platform_gateway.dart
//
// Public entry point for the platform health gateway.
//
// The concrete implementation is selected at compile time via a
// conditional export, mirroring `image_storage_service.dart`:
//
//   * On io targets the `health`-package-backed variant is selected.
//     It self-selects at runtime and stays a no-op on desktop, where
//     no platform health store exists.
//   * On web the stub is selected. The `health` package imports
//     `dart:io`, so it must never enter the web compilation path; the
//     stub is a no-op so every caller stays branch-free.

export 'health_platform_gateway_stub.dart'
    if (dart.library.io) 'health_platform_gateway_io.dart';
