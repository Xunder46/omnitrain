// filepath: lib/core/services/health_platform_gateway_stub.dart
//
// Web stub for the platform health gateway. Selected by the
// conditional export in `health_platform_gateway.dart` when
// `dart.library.io` is unavailable. No writable health store exists on
// web, so the no-op gateway is returned.

import 'health_platform_service.dart';

HealthPlatformService createHealthPlatformService() =>
    const UnavailableHealthPlatformService();
