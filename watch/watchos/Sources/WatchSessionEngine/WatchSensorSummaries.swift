//
//  WatchSensorSummaries.swift
//  WatchSessionEngine
//
//  What the wrist computes from its own readings before it may let them go:
//  heart rate over a window, the steps inside a window, the pauses a window
//  excludes, and the set blocks a session end summarises.
//
//  Plan: `.github/agents/plans/2026-09-25-02-stats-pr2-watch-capture-plan.md`,
//  D-121 to D-126. Raw readings never leave the watch (PROTOCOL.md, "Session
//  capture"); these values are the only thing derived from them that does, so
//  they are computed here, once, from stored rows — never from a live
//  subscription, and never with a clock.
//
//  Every comparison is made in whole milliseconds, the resolution the wire
//  writes timestamps at (A-9), so a window means the same thing here as it does
//  to the phone reading the event's `startedAt` and `endedAt`.
//
//  Two guards go beyond the plan's letter, both for one reason: a summary must
//  never make its event unsendable, because a refused event is a refused log.
//  A heart rate below the schema's minimum is not a reading (D-122 names only
//  values at or below zero), and a negative or non-finite step count is not a
//  count. See the plan's Assumption Log.
//

import Foundation

/// One heart-rate pair over a window: what the wire carries as
/// `avgHeartRateBpm` and `maxHeartRateBpm`.
public struct WatchHeartRateSummary: Equatable {
    /// The arithmetic mean of the qualifying readings, unrounded.
    public let averageBpm: Double

    /// The largest qualifying reading.
    public let maximumBpm: Double

    public init(averageBpm: Double, maximumBpm: Double) {
        self.averageBpm = averageBpm
        self.maximumBpm = maximumBpm
    }

    /// The pair in the protocol's field names. The two travel together.
    public var fields: [String: Any] {
        ["avgHeartRateBpm": averageBpm, "maxHeartRateBpm": maximumBpm]
    }
}

/// A stretch of a window the wrist's timer was paused for: `[start, end)`,
/// half-open, so the instant a timer resumes counts again (D-122 b).
public struct WatchPauseInterval: Equatable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
}

/// A set block: every set of one session logged for one slot and exercise,
/// and the span its heart rate is summarised over (D-123).
public struct WatchSetBlockSpan: Equatable {
    public let sessionExerciseId: String
    public let exerciseId: String

    /// The `loggedAt` of the latest effort entry logged strictly before the
    /// block's first set, or the session's start when there is none — so the
    /// span includes the work, and the rests, that led into the block.
    public let startedAt: Date

    /// The block's last set's `loggedAt`.
    public let endedAt: Date

    public init(sessionExerciseId: String, exerciseId: String, startedAt: Date, endedAt: Date) {
        self.sessionExerciseId = sessionExerciseId
        self.exerciseId = exerciseId
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

public enum WatchSensorSummaries {
    /// The lowest reading that is a heart rate: the protocol's own minimum for
    /// the heart-rate fields, so a pair built from qualifying readings is always
    /// sendable.
    public static let lowestHeartRateBpm = 1.0

    /// The heart-rate pair over `[start, end]` — both ends inclusive — leaving
    /// out any reading inside a pause, or nil when no reading qualifies.
    ///
    /// Absence is the answer to "nothing was measured", never zero: a session
    /// with the sensor off reports no pair at all (D-122 f).
    public static func heartRate(
        _ samples: [WatchSensorSampleRecord],
        from start: Date,
        through end: Date,
        excluding pauses: [WatchPauseInterval] = []
    ) -> WatchHeartRateSummary? {
        let first = wholeMilliseconds(start)
        let last = wholeMilliseconds(end)
        let paused = pauses.map { (wholeMilliseconds($0.start), wholeMilliseconds($0.end)) }

        var readings: [Double] = []
        for sample in samples where sample.kind == WatchSensorKind.heartRate {
            guard sample.value.isFinite, sample.value >= lowestHeartRateBpm else { continue }
            let at = wholeMilliseconds(sample.recordedAt)
            guard at >= first, at <= last else { continue }
            guard !paused.contains(where: { at >= $0.0 && at < $0.1 }) else { continue }
            readings.append(sample.value)
        }

        guard let lowest = readings.min(), let highest = readings.max() else { return nil }
        // The mean lies between the extremes; the clamp only removes the
        // floating-point noise that could otherwise nudge an average of equal
        // readings past its own maximum.
        let mean = readings.reduce(0, +) / Double(readings.count)
        return WatchHeartRateSummary(
            averageBpm: min(max(mean, lowest), highest),
            maximumBpm: highest
        )
    }

    /// The steps taken inside `[start, end]`, from the platform's cumulative
    /// counter, or nil when no count was sampled inside the window (D-125).
    ///
    /// The chain starts at the last count before the window — or zero when
    /// there is none — and adds each step forward. A count smaller than the one
    /// before it means the counter restarted (a recovered workout), so the new
    /// count is itself the steps since the restart. A measured zero is zero, and
    /// is reported.
    public static func steps(
        _ samples: [WatchSensorSampleRecord],
        from start: Date,
        through end: Date
    ) -> Int? {
        let first = wholeMilliseconds(start)
        let last = wholeMilliseconds(end)

        let counts = samples
            .filter { $0.kind == WatchSensorKind.steps && $0.value.isFinite && $0.value >= 0 }
            .sorted {
                (wholeMilliseconds($0.recordedAt), $0.sequence)
                    < (wholeMilliseconds($1.recordedAt), $1.sequence)
            }
        let inside = counts.filter {
            let at = wholeMilliseconds($0.recordedAt)
            return at >= first && at <= last
        }
        guard !inside.isEmpty else { return nil }

        var previous = counts.last { wholeMilliseconds($0.recordedAt) < first }?.value ?? 0
        var total = 0.0
        for sample in inside {
            total += sample.value >= previous ? sample.value - previous : sample.value
            previous = sample.value
        }
        return Int(total.rounded())
    }

    /// The pauses of the timer that started at `startedAt`, read from its
    /// stored rows (D-122 c).
    ///
    /// A pause begins at a row's `pausedAt`. It ends where that timer next ran
    /// again — the first later row without a `pausedAt` — or, when it never
    /// did, where the row itself stopped, or else at the window's end. `rows`
    /// are one timer kind of one session; the rows of the timer that timed the
    /// entry are the ones that share its start.
    public static func pauses(
        of rows: [WatchTimerRecord],
        startedAt: Date,
        windowEnd: Date
    ) -> [WatchPauseInterval] {
        let started = wholeMilliseconds(startedAt)
        let timer = rows
            .filter { wholeMilliseconds($0.startedAt) == started }
            .sorted { $0.sequence < $1.sequence }

        var intervals: [WatchPauseInterval] = []
        for (index, row) in timer.enumerated() {
            guard let pausedAt = row.pausedAt else { continue }
            let resumedAt = timer[(index + 1)...].first { $0.pausedAt == nil }?.recordedAt
            intervals.append(
                WatchPauseInterval(start: pausedAt, end: resumedAt ?? row.stoppedAt ?? windowEnd)
            )
        }
        return intervals
    }

    /// A round's pause as the wire carries it (D-126): the countdown's
    /// accumulated pause plus any pause still open, counted up to the window's
    /// end.
    ///
    /// Measured to the window's end rather than to the instant of logging: a
    /// countdown paused after it had already run out paused nothing the round
    /// contains. And never longer than the window, which is the protocol's own
    /// rule for the field — the bookkeeping cannot make a log unsendable.
    public static func pausedMs(
        _ countdown: WatchTimerRecord,
        windowStart: Date,
        windowEnd: Date
    ) -> Int {
        let windowMs = max(0, wholeMilliseconds(windowEnd) - wholeMilliseconds(windowStart))

        var paused = Int64(max(0, countdown.accumulatedPauseMs))
        if let pausedAt = countdown.pausedAt {
            let pauseEnd = min(
                wholeMilliseconds(countdown.stoppedAt ?? windowEnd),
                wholeMilliseconds(windowEnd)
            )
            paused += max(0, pauseEnd - wholeMilliseconds(pausedAt))
        }
        return Int(min(paused, windowMs))
    }

    /// The session's set blocks and their spans, in the order the blocks began
    /// (D-123).
    ///
    /// `entries` are the session's entries as the wrist holds them — the
    /// phone's deletions already dropped — in the protocol's event shape. A set
    /// block is every set with the same slot and exercise; interleaved blocks
    /// (a superset) may overlap, and each is summarised over its own span.
    public static func blockSpans(
        _ entries: [[String: Any]],
        sessionStartedAt: Date
    ) -> [WatchSetBlockSpan] {
        let efforts = entries
            .compactMap(LoggedEffort.init)
            .sorted {
                (wholeMilliseconds($0.loggedAt), $0.entryId)
                    < (wholeMilliseconds($1.loggedAt), $1.entryId)
            }

        var order: [BlockKey] = []
        var sets: [BlockKey: [LoggedEffort]] = [:]
        for effort in efforts where effort.kind == WatchObservationKind.set {
            guard let key = effort.blockKey else { continue }
            if sets[key] == nil { order.append(key) }
            sets[key, default: []].append(effort)
        }

        return order.compactMap { key in
            guard let block = sets[key], let first = block.first, let last = block.last else {
                return nil
            }
            let firstSet = wholeMilliseconds(first.loggedAt)
            let leadIn = efforts.last { wholeMilliseconds($0.loggedAt) < firstSet }
            return WatchSetBlockSpan(
                sessionExerciseId: key.sessionExerciseId,
                exerciseId: key.exerciseId,
                startedAt: leadIn?.loggedAt ?? sessionStartedAt,
                endedAt: last.loggedAt
            )
        }
    }

    /// `instant` at the resolution the wire writes it: what a phone reading the
    /// event's timestamp gets back. Windows are normalised through here before
    /// anything is summarised over them.
    public static func wireInstant(_ instant: Date) -> Date {
        (try? parseUtcIso(utcIso(instant))) ?? instant
    }

    private struct BlockKey: Hashable {
        let sessionExerciseId: String
        let exerciseId: String
    }

    /// An effort entry, reduced to what a set block's span needs.
    private struct LoggedEffort {
        let entryId: String
        let kind: String
        let loggedAt: Date
        let blockKey: BlockKey?

        init?(_ entry: [String: Any]) {
            guard let kind = entry["kind"] as? String,
                  WatchObservationKind.efforts.contains(kind),
                  let loggedAt = try? parseUtcIso(entry["loggedAt"])
            else { return nil }

            self.entryId = entry["entryId"] as? String ?? ""
            self.kind = kind
            self.loggedAt = loggedAt
            if let slot = entry["sessionExerciseId"] as? String,
               let exercise = entry["exerciseId"] as? String {
                blockKey = BlockKey(sessionExerciseId: slot, exerciseId: exercise)
            } else {
                blockKey = nil
            }
        }
    }
}

/// Whole milliseconds since the epoch — the resolution every comparison in a
/// summary is made at.
func wholeMilliseconds(_ instant: Date) -> Int64 {
    Int64((instant.timeIntervalSince1970 * 1000).rounded())
}
