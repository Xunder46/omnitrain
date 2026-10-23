//
//  WatchWorkoutSummary.swift
//  WatchSessionEngine
//
//  The wrist's end-of-workout summary: what a finished workout shows (time,
//  efforts, average heart rate), and the state that owes it to a workout this
//  process saw end.
//
//  Plan: `docs/plans/2026-10-23-66a-wrist-workout-summary-and-skip-plan/
//  2026-10-23-66a-wrist-workout-summary-and-skip-plan.md`, D-1 and D-2,
//  scenarios S-9601 – S-9607.
//
//  Everything here is state and arithmetic. The view
//  (`WatchWorkoutSummaryView.swift`) only binds to it, and it compiles only
//  into a watch target, so this is the part `swift test` proves.
//

import Combine
import Foundation

/// The words on the wrist's end-of-workout summary (plan 66a D-1). Wrist-only
/// copy, not part of the shared contract.
public enum WatchWorkoutSummaryCopy {
    public static let title = "Workout done"
    public static let time = "Time"
    public static let sets = "Sets"
    public static let efforts = "Efforts"
    public static let avgHeartRate = "Avg HR"
    public static let done = "Done"
    public static let bpm = "bpm"
}

public struct WatchSummaryRow: Equatable {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

/// What a finished workout shows on the wrist: how long, how many efforts, and
/// the average heart rate when the watch recorded one.
public struct WatchWorkoutSummary: Equatable {
    public let sessionId: String
    public let startedAt: Date
    public let endedAt: Date
    public let effortCount: Int
    public let allSets: Bool
    public let averageBpm: Int?

    public init(
        sessionId: String,
        startedAt: Date,
        endedAt: Date,
        effortCount: Int,
        allSets: Bool,
        averageBpm: Int?
    ) {
        self.sessionId = sessionId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.effortCount = effortCount
        self.allSets = allSets
        self.averageBpm = averageBpm
    }

    public var rows: [WatchSummaryRow] {
        var rows = [
            WatchSummaryRow(
                label: WatchWorkoutSummaryCopy.time,
                value: Self.durationText(Int(endedAt.timeIntervalSince(startedAt).rounded()))
            ),
            WatchSummaryRow(
                label: allSets ? WatchWorkoutSummaryCopy.sets : WatchWorkoutSummaryCopy.efforts,
                value: "\(effortCount)"
            ),
        ]
        if let averageBpm {
            rows.append(
                WatchSummaryRow(
                    label: WatchWorkoutSummaryCopy.avgHeartRate,
                    value: "\(averageBpm) \(WatchWorkoutSummaryCopy.bpm)"
                )
            )
        }
        return rows
    }

    /// `m:ss` under an hour, `h:mm:ss` from an hour; a negative length reads 0:00.
    public static func durationText(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }
}

/// The summary the wrist owes a workout it saw end. The host calls `note` with
/// the engine's session on every session change; a workout makes one summary,
/// and only when this process saw it active (a relaunch after the end shows
/// nothing).
public final class WatchWorkoutSummaryState: ObservableObject {
    private let engine: WatchSessionEngine
    private var activeSeenId: String?

    @Published public private(set) var pending: WatchWorkoutSummary?

    public init(engine: WatchSessionEngine) {
        self.engine = engine
    }

    public func note(_ session: WatchSessionRecord?) {
        guard let session else { return }
        if session.status == WatchSessionStatus.active {
            activeSeenId = session.sessionId
            if let held = pending, held.sessionId != session.sessionId { pending = nil }
            return
        }
        guard session.status == WatchSessionStatus.completed,
              session.sessionId == activeSeenId,
              engine.session?.sessionId == session.sessionId,
              pending?.sessionId != session.sessionId
        else { return }
        activeSeenId = nil

        let efforts = engine.entries.filter { WatchObservationKind.efforts.contains($0.kind) }
        guard !efforts.isEmpty else { return }
        let heart = WatchSensorSummaries.heartRate(
            engine.sensorSamples,
            from: session.startedAt,
            through: session.recordedAt
        )
        pending = WatchWorkoutSummary(
            sessionId: session.sessionId,
            startedAt: session.startedAt,
            endedAt: session.recordedAt,
            effortCount: efforts.count,
            allSets: efforts.allSatisfy { $0.kind == WatchObservationKind.set },
            averageBpm: heart.map { Int($0.averageBpm.rounded()) }
        )
    }

    public func dismissPending() {
        pending = nil
    }
}
