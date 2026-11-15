//
//  DiagnosticsEntryPoint.swift
//  OmniTrain Watch App
//
//  Whether this build shows the Start screen's Diagnostics button (plan 177,
//  D-17703). The log itself keeps recording in every build; only the way in is
//  gated, so a walk the owner debugs with can never be lost to a hidden button.
//

import Foundation

/// The one watch-side gate on the Diagnostics entry point.
///
/// Visible in Debug and Profile. A Release build hides it unless the owner asks
/// for it, either by adding `OMNITRAIN_DIAGNOSTICS` to the watch app target's
/// Active Compilation Conditions (a rebuild, and the only path on TestFlight) or
/// by setting `OMNITRAIN_DIAGNOSTICS=1` in the scheme's run action (no rebuild).
enum DiagnosticsEntryPoint {
    static var isVisible: Bool {
        #if DEBUG || PROFILE || OMNITRAIN_DIAGNOSTICS
        return true
        #else
        return ProcessInfo.processInfo.environment["OMNITRAIN_DIAGNOSTICS"] == "1"
        #endif
    }
}
