// Whether the diagnostics entry points are shown (plan 177, D-17702).
//
// Diagnostics is a debugging tool, so neither entry point — the Settings row on
// the phone, the Start screen's button on the watch — ships to users. The log
// itself keeps recording in every build (D-17701); only the way in is gated.
//
// Shipping rule: visible in debug and profile builds, hidden in release unless
// the owner asks for it (currently switched off by [kHideDiagnosticsInRelease]
// until the first release):
//
//   flutter run --release --dart-define=OMNITRAIN_DIAGNOSTICS=true
//
// The key is read here and nowhere else in this track.

import 'package:flutter/foundation.dart';

/// Whether this build was made with `--dart-define=OMNITRAIN_DIAGNOSTICS=true`.
const bool kOmnitrainDiagnosticsOverride = bool.fromEnvironment(
  'OMNITRAIN_DIAGNOSTICS',
);

/// Pre-release switch: while the app is not released, release builds keep the
/// entry point too. Set to `true` before shipping to hide it again in release
/// (the watch has the matching `hidesInRelease` in `DiagnosticsEntryPoint.swift`).
const bool kHideDiagnosticsInRelease = false;

/// The gate `lib/main.dart` reads when it builds `MyApp`.
const bool kDiagnosticsEntryVisible =
    !kHideDiagnosticsInRelease ||
    kOmnitrainDiagnosticsOverride ||
    kDebugMode ||
    kProfileMode;

/// The visibility rule as a pure function, so a test can exercise the whole
/// truth table without a build mode to switch. [hideInRelease] defaults to the
/// shipping rule; the app passes [kHideDiagnosticsInRelease].
bool diagnosticsEntryVisibleFor({
  required bool debugBuild,
  required bool profileBuild,
  required bool override,
  bool hideInRelease = true,
}) => !hideInRelease || debugBuild || profileBuild || override;
