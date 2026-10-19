//
//  WatchSensorCoordinator.swift
//  WatchSessionEngine
//
//  The watch's sensors, following the session's life the way the workout does
//  (`WatchWorkoutCoordinator`, `WatchPlatformWorkout.swift`). The sensors run
//  exactly while a session is active: one subscription per session, a change of
//  session id while recording is a stop then a start, and every other status —
//  completed, abandoned, or no session at all — stops them.
//
//  The one record of what the sensors belong to is `recordingSessionId`, and the
//  id is written **before** the source is asked, for the same reason
//  `WatchWorkoutCoordinator.apply` writes `openedForSessionId` before
//  `platform.start`: a refusal must not be asked about again on the next refresh
//  while the same session is live. The recorder already swallows a refusal
//  (`WatchSensorRecording.start`), so nothing here throws and nothing here
//  retries — logging and syncing never depend on a sensor.
//
//  Plan: `docs/plans/2026-10-10-19d-watch-heart-rate-and-steps-plan/`, scenarios
//  S-3100…S-3108 and S-3111…S-3113, S-3115
//  (`watch/watchos/Tests/WatchSessionEngineTests/WatchSensorCoordinatorTests.swift`).
//

import Foundation

/// The watch's sensors, following the session's life.
///
/// The only caller of `WatchSensorRecorder`, beside the logging surface that
/// reads it. A plain class rather than `@MainActor` or an `actor` so the package
/// still builds and tests on macOS (`Package.swift` sets no default isolation).
/// Its work runs on one serial tail — an `NSLock`-guarded task chained behind the
/// previous one, the shape `WatchSensorWrites.enqueue` and
/// `WatchWorkoutCoordinator` both use — so a refresh never overlaps another and
/// two refreshes produce the calls of one, in order.
///
/// The tail matters more here than for the workout: a `start` is several awaits
/// long (a permission probe, then a subscription per kind), so `Task.yield`
/// would not be enough to keep a `refresh(nil)` from clearing the id while a
/// `refresh(session)` is still inside `start`.
public final class WatchSensorCoordinator {
    private let recorder: WatchSensorRecorder
    private let lock = NSLock()
    private var tail: Task<Void, Never>?

    /// The session the sensors are recording for, or nil when nothing runs. A
    /// change of id while it is set is the stop-then-start of a session replaced
    /// by the phone's reset, and every other status clears it.
    private(set) var recordingSessionId: String?

    public init(recorder: WatchSensorRecorder) {
        self.recorder = recorder
    }

    /// Brings the sensors in line with `session`, whatever it is now.
    ///
    /// Returns once this refresh's own work has run — not once the tail is
    /// empty, so a caller's later refresh is still ordered behind it.
    public func refresh(_ session: WatchSessionRecord?) async {
        await enqueue { await self.apply(session) }.value
    }

    private func apply(_ session: WatchSessionRecord?) async {
        if let recording = recordingSessionId, recording != session?.sessionId {
            await recorder.stop()
            recordingSessionId = nil
        }

        if session?.status == WatchSessionStatus.active {
            if recordingSessionId == nil {
                recordingSessionId = session?.sessionId
                if let session { await recorder.start(session) }
            } else if let session {
                await recorder.sessionChanged(session)
            }
            return
        }

        if recordingSessionId != nil {
            await recorder.stop()
            recordingSessionId = nil
        }
    }

    /// Runs `work` after every call enqueued before it; awaiting the returned
    /// task waits for this one.
    private func enqueue(_ work: @escaping () async -> Void) -> Task<Void, Never> {
        lock.lock()
        defer { lock.unlock() }

        let previous = tail
        let next = Task {
            await previous?.value
            await work()
        }
        tail = next
        return next
    }
}
