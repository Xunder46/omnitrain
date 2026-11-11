import Foundation

/// What happened when the wrist offered its diagnostics log to the phone (plan 144, D-14402).
public enum WatchDiagnosticsSendOutcome: Equatable {
    case sent
    case phoneAppMissing
    case notReady
    case failed

    /// The words the Diagnostics screen shows.
    public var message: String {
        switch self {
        case .sent: return "Sent. The phone has it when it next wakes."
        case .phoneAppMissing: return "Install the OmniTrain app on the phone."
        case .notReady: return "Phone link not ready."
        case .failed: return "Could not send."
        }
    }
}
