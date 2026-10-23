//
//  WatchSyncProgress.swift
//  WatchSessionEngine
//
//  Whether the wrist is still waiting on the phone's answer to a sync (plan 55,
//  `docs/plans/2026-10-22-55-wrist-sync-progress-plan/2026-10-22-55-wrist-sync-progress-plan.md`,
//  D-1 and D-5). A pure type outside the watchOS-only views, so the desktop
//  toolchain can assert when the Sync button becomes a spinner.
//
//  `WatchSyncOrchestrator.sync` awaits only the sends: the phone's replies
//  (`preferences_down`, `routines_down`, `foods_down`, `exercises_down`,
//  `session_snapshot`) arrive later through `receive`. So "still syncing" cannot
//  be read from the request — it is derived from the arrivals, and capped so a
//  phone that never answers cannot leave the wrist spinning.
//

import Foundation

/// The window's lengths, in one place so the host and the suite read the same
/// numbers.
public enum WatchSyncProgressCopy {
    /// How long the wrist waits after the newest reply before calling the sync
    /// finished. A batch normally lands well within a second of the one before.
    public static let quietSeconds: TimeInterval = 2.0

    /// The longest a sync may show as running, whether or not anything arrives.
    public static let capSeconds: TimeInterval = 20.0

    /// The message types that are a sync's replies. Anything else says nothing
    /// about the sync being finished.
    public static let replyTypes: Set<String> = [
        "preferences_down",
        "routines_down",
        "foods_down",
        "exercises_down",
        "session_snapshot",
    ]
}

/// Whether a sync is running, derived from the clock and the replies that have
/// arrived since it began.
///
/// The clock is injected so a test drives the window by hand; production passes
/// the default.
public struct WatchSyncProgress {
    private let clock: () -> Date

    /// When the running sync began, or nil when none ever did.
    private var beganAt: Date?

    /// The newest reply arrival of the running sync.
    private var newestReplyAt: Date?

    /// Whether a `routines_down` has arrived since `beganAt` — the sync is not
    /// finished until the routines it was asked for are here.
    private var routinesArrived = false

    public init(clock: @escaping () -> Date = { Date() }) {
        self.clock = clock
    }

    /// Whether a sync is still running as of the injected clock.
    public func isActive() -> Bool {
        isActive(at: clock())
    }

    /// Whether a sync is still running at `now`.
    ///
    /// Finished at the cap regardless of arrivals; otherwise finished once the
    /// routines have arrived and the newest reply has been quiet for
    /// `quietSeconds`.
    public func isActive(at now: Date) -> Bool {
        guard let beganAt else { return false }
        if now.timeIntervalSince(beganAt) >= WatchSyncProgressCopy.capSeconds { return false }
        guard routinesArrived, let newestReplyAt else { return true }
        return now.timeIntervalSince(newestReplyAt) < WatchSyncProgressCopy.quietSeconds
    }

    /// Starts a sync as of the injected clock.
    public mutating func begin() {
        begin(at: clock())
    }

    /// Starts a sync at `now`, unless one is still running: a second request
    /// while the wrist is waiting continues the running one rather than
    /// restarting its window. A fresh begin forgets every earlier arrival.
    public mutating func begin(at now: Date) {
        guard !isActive(at: now) else { return }
        beganAt = now
        newestReplyAt = nil
        routinesArrived = false
    }

    /// Records one arriving message. Only a reply type counts, and only while
    /// the sync is running: a straggler after it finished must not revive it.
    /// Any later reply becomes the newest, whichever type it is.
    public mutating func noteArrival(type: String, at now: Date) {
        guard isActive(at: now), WatchSyncProgressCopy.replyTypes.contains(type) else { return }
        newestReplyAt = now
        if type == "routines_down" { routinesArrived = true }
    }
}
