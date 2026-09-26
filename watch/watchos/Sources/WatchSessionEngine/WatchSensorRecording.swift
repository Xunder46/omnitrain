//
//  WatchSensorRecording.swift
//  WatchSessionEngine
//
//  Sensor recording: what the watch listens to while a session runs. Mirrors
//  `lib/watch/sensors/watch_sensor_recording.dart`.
//
//  Plan: `.github/agents/plans/2026-07-13-11-d-watch-sensor-recording-plan.md`,
//  scenarios S-002, S-003, S-004 and S-006.
//
//  Two rules shape this layer:
//
//  1. **A reading is stored, not held.** Every sample goes into the same
//     append-only store as everything else, and the live readout is derived from
//     the newest stored row rather than from a field kept in memory. A kill
//     mid-run therefore costs the user nothing: what was measured is on disk.
//  2. **Denial is not failure.** A permission the user refused, or hardware the
//     device does not have, skips the subscription and nothing else. Logging is
//     the primary action of the watch and never depends on a sensor (S-006).
//
//  The OS bindings — `HKWorkoutSession`, `HKLiveWorkoutBuilder`,
//  `CLLocationManager` — satisfy `WatchSensorSource` and
//  `WatchPlatformWorkoutStore`; this file stays free of them so the behaviour is
//  testable and identical to the Flutter client's.
//

import Foundation

/// What the platform says about one sensor.
public enum WatchSensorPermission {
    /// The user has allowed it, and the hardware is there.
    case granted

    /// The user said no. Asking again is the platform's business, not the watch's.
    case denied

    /// There is nothing to ask: no radio, no sensor, no watch face for it.
    case unavailable
}

/// One location fix, reduced to the only thing a training session needs from it:
/// how far the user has covered in total.
///
/// Route geometry is out of scope on purpose. The watch is an instrument panel,
/// not a map, and a polyline is the largest thing this app could store for the
/// least information.
public struct WatchLocationFix: Equatable {
    /// Metres covered since the session started, cumulative — the platform
    /// already tracks the running total, and the wrist only has to carry it.
    public let distanceMeters: Double

    public init(distanceMeters: Double) {
        self.distanceMeters = distanceMeters
    }
}

/// The device's sensors, behind the one interface the watch is allowed to see.
public protocol WatchSensorSource {
    func heartRatePermission() async -> WatchSensorPermission

    func locationPermission() async -> WatchSensorPermission

    func stepsPermission() async -> WatchSensorPermission

    /// Beats per minute, as the sensor reports them.
    func heartRate() -> AsyncStream<Double>

    /// Location fixes, whenever the platform produces one.
    func location() -> AsyncStream<WatchLocationFix>

    /// The platform's step count since its workout began, cumulative: each
    /// value supersedes the one before (`WatchSensorKind.steps`).
    func steps() -> AsyncStream<Double>
}

/// What the sensors are reading right now, resolved together because a readout
/// shows them together.
public struct WatchSensorReadings {
    /// Nothing measured yet: the state a session starts in, and the state a view
    /// with no sensors at all stays in.
    public static let none = WatchSensorReadings()

    /// The newest stored beat, or nil when none has been recorded.
    public let heartRate: Double?

    /// Metres covered: the settled total once recording has stopped, and the
    /// latest fix while it runs.
    public let distanceMeters: Double?

    public init(heartRate: Double? = nil, distanceMeters: Double? = nil) {
        self.heartRate = heartRate
        self.distanceMeters = distanceMeters
    }
}

/// The sensors of a running session, writing what they read into the session's
/// own storage.
public final class WatchSensorRecorder {
    private let engine: WatchSessionEngine
    private let source: WatchSensorSource
    private let clock: () -> Date

    private var beatTask: Task<Void, Never>?
    private var fixTask: Task<Void, Never>?
    private var stepsTask: Task<Void, Never>?

    /// Every write this recorder makes, one at a time and in arrival order.
    private let writes = WatchSensorWrites()

    /// Whether a location subscription is live. False for work that has no
    /// distance, and false when the user refused permission.
    public private(set) var isMeasuringDistance = false

    public init(
        engine: WatchSessionEngine,
        source: WatchSensorSource,
        clock: @escaping () -> Date = { Date() }
    ) {
        self.engine = engine
        self.source = source
        self.clock = clock
    }

    /// What the sensors are reading, as one resolution of stored rows.
    public var readings: WatchSensorReadings {
        let newest = engine.newestSensorSamples()
        return WatchSensorReadings(
            heartRate: newest[WatchSensorKind.heartRate]?.value,
            distanceMeters: newest[WatchSensorKind.distance]?.value
                ?? newest[WatchSensorKind.gps]?.value
        )
    }

    /// Starts listening to whatever `session`'s modality calls for.
    ///
    /// Heart rate is recorded for every session that has a sensor to record it
    /// with, and so are steps. Location is recorded only where the modality can
    /// cover distance, so a lift does not drain the battery warming up a radio
    /// it will never use (S-001, S-002).
    public func start(_ session: WatchSessionRecord) async {
        await startHeartRate()
        await startSteps()

        guard WatchGpsPolicy.isRequired(session.modality) else { return }
        guard await source.locationPermission() == .granted else { return }

        isMeasuringDistance = true
        fixTask = consume(source.location()) { [weak self] fix in
            await self?.record(kind: WatchSensorKind.gps, value: fix.distanceMeters)
        }
    }

    /// Stops listening, and settles the session's distance.
    ///
    /// The settled total is written as a `distance` sample rather than left as
    /// the last fix: "what the session measured" is then one row the phone can
    /// read without replaying the GPS log, and a fix that arrived a metre before
    /// the user pressed finish does not have to be treated as the final answer.
    public func stop() async {
        beatTask?.cancel()
        fixTask?.cancel()
        stepsTask?.cancel()
        beatTask = nil
        fixTask = nil
        stepsTask = nil

        guard isMeasuringDistance else { return }
        isMeasuringDistance = false

        // Settled behind any fix already on its way in, so the total is the
        // last fix that arrived rather than the last one written.
        await writes.enqueue { [engine] in
            guard let measured = engine.newestSensorSample(WatchSensorKind.gps)?.value else {
                return
            }
            await engine.appendSensorSample(kind: WatchSensorKind.distance, value: measured)
        }.value
    }

    private func startHeartRate() async {
        guard await source.heartRatePermission() == .granted else { return }
        beatTask = consume(source.heartRate()) { [weak self] beats in
            await self?.record(kind: WatchSensorKind.heartRate, value: beats)
        }
    }

    /// Steps are counted for every session the user allows it for, whatever its
    /// modality: a timed effort can happen in any session, and a timed entry is
    /// what carries a step total (D-125). They feed no readout — `readings` is
    /// the beat and the distance, as before.
    private func startSteps() async {
        guard await source.stepsPermission() == .granted else { return }
        stepsTask = consume(source.steps()) { [weak self] count in
            await self?.record(kind: WatchSensorKind.steps, value: count)
        }
    }

    /// Consumes `stream`, handing each element to `onElement`; the returned task
    /// is what `stop` cancels.
    private func consume<T>(
        _ stream: AsyncStream<T>,
        onElement: @escaping (T) async -> Void
    ) -> Task<Void, Never> {
        Task { for await element in stream { await onElement(element) } }
    }

    /// Stores one reading, stamped when it arrived.
    private func record(kind: String, value: Double) async {
        let recordedAt = clock()
        await writes.enqueue { [engine] in
            await engine.appendSensorSample(kind: kind, value: value, recordedAt: recordedAt)
        }.value
    }
}

/// A chain of writes, each starting only once the one before it has finished.
///
/// Every sensor streams on a task of its own, and since steps are counted in
/// every session there are always at least two streams — three on a run —
/// while the engine and its store are built for one writer. Chaining the
/// recorder's writes keeps them in arrival order and never concurrent, however
/// the platform happens to deliver them.
final class WatchSensorWrites {
    private let lock = NSLock()
    private var tail: Task<Void, Never>?

    /// Runs `work` after every write enqueued before it; await the returned
    /// task to wait for this one.
    func enqueue(_ work: @escaping () async -> Void) -> Task<Void, Never> {
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

/// Everything a session has running on the platform: its workout registration
/// and its sensors, started and stopped together.
///
/// One object rather than two so that no caller can remember to start the
/// sensors and forget the workout — the pairing is the behaviour.
public final class WatchSessionSensors {
    private let platform: WatchPlatformWorkout

    /// The recorder behind this session: what the live readout reads, and what
    /// `stop` settles the distance through.
    public let recorder: WatchSensorRecorder

    public init(platform: WatchPlatformWorkout, recorder: WatchSensorRecorder) {
        self.platform = platform
        self.recorder = recorder
    }

    /// Registers the session with the platform and starts its sensors.
    public func start(_ session: WatchSessionRecord) async {
        await platform.start(session)
        await recorder.start(session)
    }

    /// Stops the sensors and closes the platform workout.
    public func stop() async {
        await recorder.stop()
        await platform.end()
    }

    /// Ends any workout a previous process left open. Call at launch, before
    /// anything starts.
    @discardableResult
    public func recoverInProgress() async -> [String] {
        await platform.recoverInProgress()
    }
}
