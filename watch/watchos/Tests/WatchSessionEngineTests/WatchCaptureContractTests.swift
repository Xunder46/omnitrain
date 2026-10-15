//
//  WatchCaptureContractTests.swift
//  WatchSessionEngineTests
//
//  The Swift half of F-CAP, `watch/contract/watch_capture_contract.json`:
//  one wrist session end to end, replayed from the contract's own timeline
//  through the wrist, and the events it emits compared with the contract's
//  `expectedEvents` value for value. The Dart suite
//  (`test/watch_capture_contract_test.dart`) imports the same events on the
//  phone, so the two stacks are held to one set of numbers.
//
//  Plan: `docs/plans/2026-09-25-02-stats-pr2-watch-capture-plan.md`,
//  Phase 4a (the replay up to End) and Phase 4b (all three cases, rating
//  included).
//
//  The replay follows the wrist's own flow (D-1315): `startWork` is the Start
//  that begins the current effort's clock — planned at the case's
//  `periodSeconds` for a period — and `log` ends that clock at the log
//  instant. Nothing starts a clock the user did not, so no op dials a length.
//

import XCTest

@testable import WatchSessionEngine

/// Replays one F-CAP case: each timeline op, in array order, at its own
/// instant, through the same engine and logging surface a wrist runs.
final class CaptureReplay {
    let captureCase: [String: Any]
    /// The length a period is planned at: the case's own `periodSeconds`.
    let periodSeconds: Double
    let clock: TestClock
    let store: InMemoryWatchSessionStore
    private(set) var emitted: [[String: Any]] = []
    private(set) var engine: WatchSessionEngine!
    private(set) var surface: WatchLoggingState!
    private(set) var preferences: WatchPhonePreferences!
    private(set) var rating: WatchEffortRatingState!
    private(set) var orchestrator: WatchSyncOrchestrator!

    private var recordIds = 0
    private var scriptedEntryIds: [String] = []

    init(_ name: String) throws {
        let contract = try Fixtures.captureContract()
        let cases = (contract["cases"] as? [[String: Any]]) ?? []
        guard let found = cases.first(where: { $0["name"] as? String == name }) else {
            throw ReplayError.malformed("F-CAP has no case \"\(name)\"")
        }
        captureCase = found
        guard let period = numericValue(found["periodSeconds"]) else {
            throw ReplayError.malformed("F-CAP case \"\(name)\" has no periodSeconds")
        }
        periodSeconds = period

        let first = (found["timeline"] as? [[String: Any]])?.first
        clock = TestClock(try parseUtcIso(first?["at"]))
        store = InMemoryWatchSessionStore()
        build()
    }

    var sessionId: String { captureCase["sessionId"] as? String ?? "" }

    var timeline: [[String: Any]] { (captureCase["timeline"] as? [[String: Any]]) ?? [] }

    var expectedEvents: [[String: Any]] {
        (captureCase["expectedEvents"] as? [[String: Any]]) ?? []
    }

    /// The observation events the wrist emitted, one per `observations_up`, in
    /// the order it emitted them — which is the order it stored them.
    var emittedEvents: [[String: Any]] {
        emitted
            .filter { $0["type"] as? String == "observations_up" }
            .compactMap { ((($0["payload"] as? [String: Any])?["events"]) as? [[String: Any]])?.first }
    }

    /// The emitted event with `entryId`, or a failure naming it.
    func event(_ entryId: String) throws -> [String: Any] {
        guard let event = emittedEvents.first(where: { $0["entryId"] as? String == entryId }) else {
            throw ReplayError.malformed("the wrist emitted no \(entryId)")
        }
        return event
    }

    /// Applies the timeline's ops in order, stopping before the first op whose
    /// name is in `stoppingBefore`.
    func run(stoppingBefore: Set<String> = []) async throws {
        for op in timeline {
            let name = op["op"] as? String ?? ""
            if stoppingBefore.contains(name) { return }
            clock.now = try parseUtcIso(op["at"])
            try await apply(name, op)
        }
    }

    /// A kill and a relaunch: new objects over the same storage, restored in
    /// launch order.
    func relaunch() async {
        build()
        await engine.restore()
        await preferences.restore()
        await rating.restore()
    }

    private func apply(_ name: String, _ op: [String: Any]) async throws {
        switch name {
        case "preferences":
            // Through the orchestrator, as a sync delivers it.
            let applied = try await orchestrator.receive(
                preferencesDown(
                    op["effortRatingPrompt"] as? Bool ?? false,
                    generatedAt: op["generatedAt"] as? String ?? ""
                )
            )
            guard applied else { throw ReplayError.malformed("the wrist refused \(op)") }
        case "start":
            scriptedEntryIds = (op["entryIds"] as? [String]) ?? []
            _ = await engine.createSession(
                modality: op["modality"] as? String,
                exercises: (op["exercises"] as? [[String: Any]]) ?? []
            )
        case "startWork":
            // The wrist's Start: the current effort's own clock (D-1304).
            await surface.startWork()
        case "hr":
            _ = await engine.appendSensorSample(
                kind: WatchSensorKind.heartRate,
                value: try number(op["bpm"]),
                recordedAt: clock.now
            )
        case "steps":
            _ = await engine.appendSensorSample(
                kind: WatchSensorKind.steps,
                value: try number(op["count"]),
                recordedAt: clock.now
            )
        case "dial":
            try dial(op["metric"] as? String ?? "", to: try number(op["value"]))
        case "log":
            try await log(op["entryId"] as? String ?? "")
        case "advance":
            _ = await engine.advanceExercise()
            let slot = engine.currentExercise?["sessionExerciseId"] as? String
            guard slot == op["sessionExerciseId"] as? String else {
                throw ReplayError.malformed("advanced to \(slot ?? "nothing"), not \(op)")
            }
        case "pauseRound":
            _ = await engine.pauseTimer(kind: WatchTimerKind.round)
        case "resumeRound":
            _ = await engine.resumeTimer(kind: WatchTimerKind.round)
        case "end":
            await rating.end()
        case "answer":
            rating.select(Int(try number(op["rating"])))
            guard try await rating.confirm() != nil else {
                throw ReplayError.malformed("the prompt recorded no answer for \(op)")
            }
        default:
            throw ReplayError.malformed("an op this replay does not know: \(name)")
        }
    }

    /// Dials `metric` to exactly `value`, in whole detents. The guard for
    /// S-1303: a surface that offers no such row refuses the dial.
    func dial(_ metric: String, to value: Double) throws {
        guard let field = surface.fields.first(where: { $0.metricKey == metric }) else {
            throw ReplayError.malformed("the surface has no \(metric) to dial")
        }
        surface.adjust(metric, detents: (value - field.value) / field.step)
        let dialled = surface.fields.first { $0.metricKey == metric }?.value
        guard dialled == value else {
            throw ReplayError.malformed("dialled \(metric) to \(dialled ?? -1), not \(value)")
        }
    }

    private func log(_ entryId: String) async throws {
        let logged = try await surface.log()
        guard logged.entryId == entryId else {
            throw ReplayError.malformed("logged \(logged.entryId), the timeline says \(entryId)")
        }
    }

    private func build() {
        engine = WatchSessionEngine(
            store: store,
            onEmit: { [weak self] envelope in self?.emitted.append(envelope) },
            validator: Harness.validator(),
            clock: clock.call,
            idFactory: { [weak self] in
                guard let self else { return UUID().uuidString }
                self.recordIds += 1
                return "rec-\(self.recordIds)"
            },
            sessionIdFactory: { [weak self] in self?.sessionId ?? "" }
        )
        surface = WatchLoggingState(
            engine: engine,
            clock: clock.call,
            idFactory: { [weak self] in
                guard let self, !self.scriptedEntryIds.isEmpty else { return UUID().uuidString }
                return self.scriptedEntryIds.removeFirst()
            },
            roundPresetMs: Int((periodSeconds * 1000).rounded())
        )
        preferences = WatchPhonePreferences(store: store, validator: Harness.validator(), clock: clock.call)
        rating = WatchEffortRatingState(engine: engine, store: store, preferences: preferences, clock: clock.call)
        orchestrator = WatchSyncOrchestrator(
            transport: RecordingTransport(),
            paths: WatchSessionStartPaths(engine: engine, store: store, validator: Harness.validator(), clock: clock.call),
            engine: engine,
            preferences: preferences
        )
    }

    private func number(_ value: Any?) throws -> Double {
        guard let number = numericValue(value) else {
            throw ReplayError.malformed("expected a number, found \(describe(value))")
        }
        return number
    }

    enum ReplayError: Error {
        case malformed(String)
    }
}

/// Fails, naming `scenario`, unless `actual` is `expected` event for event:
/// the same count, the same keys, and the same values (numbers by value).
func assertEventsEqual(
    _ actual: [[String: Any]],
    _ expected: [[String: Any]],
    _ scenario: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(
        actual.compactMap { $0["entryId"] as? String },
        expected.compactMap { $0["entryId"] as? String },
        "\(scenario): the wrist's events, in store order",
        file: file,
        line: line
    )
    for (emitted, wanted) in zip(actual, expected) {
        let entryId = wanted["entryId"] as? String ?? "?"
        XCTAssertEqual(
            Set(emitted.keys),
            Set(wanted.keys),
            "\(scenario): \(entryId) carries exactly the contract's fields",
            file: file,
            line: line
        )
        for (key, value) in wanted where !deepEquals(emitted[key], value) {
            XCTFail(
                "\(scenario): \(entryId).\(key) is \(describe(emitted[key])), "
                    + "the contract says \(describe(value))",
                file: file,
                line: line
            )
        }
    }
}

final class WatchCaptureContractTests: XCTestCase {

    // MARK: - Phase 4a: the wrist's events up to End

    func testFCapFullUpToEndEmitsTheContractsEvents() async throws {
        let replay = try CaptureReplay("full")
        try await replay.run(stoppingBefore: ["answer"])

        assertEventsEqual(
            replay.emittedEvents,
            replay.expectedEvents.filter { $0["kind"] as? String != "effort_rating" },
            "S-231/S-232/S-233/S-234 F-CAP full, up to End"
        )
    }

    func testFCapNoSensorsUpToEndEmitsTheContractsEvents() async throws {
        let replay = try CaptureReplay("no-sensors")
        try await replay.run(stoppingBefore: ["answer"])

        assertEventsEqual(
            replay.emittedEvents,
            replay.expectedEvents.filter { $0["kind"] as? String != "effort_rating" },
            "S-235 F-CAP no-sensors, up to End"
        )
    }

    // MARK: - Phase 4b: every case, rating included

    func testFCapFullEmitsExactlyTheContractsEvents() async throws {
        let replay = try CaptureReplay("full")
        try await replay.run()

        assertEventsEqual(replay.emittedEvents, replay.expectedEvents, "F-CAP full")
        XCTAssertFalse(replay.rating.isPromptOwed, "F-CAP full: the answer settled the prompt")
    }

    func testFCapNoSensorsEmitsExactlyTheContractsEvents() async throws {
        let replay = try CaptureReplay("no-sensors")
        try await replay.run()

        assertEventsEqual(replay.emittedEvents, replay.expectedEvents, "F-CAP no-sensors")
    }

    func testFCapPromptOffEmitsExactlyTheContractsEvents() async throws {
        let replay = try CaptureReplay("prompt-off")
        try await replay.run()

        assertEventsEqual(replay.emittedEvents, replay.expectedEvents, "F-CAP prompt-off")
        XCTAssertEqual(replay.emittedEvents.count, 11, "F-CAP prompt-off: no rating, so eleven events")
        XCTAssertFalse(replay.rating.isPromptOwed, "F-CAP prompt-off: the setting is off, so nothing is owed")
    }

    // MARK: - S-1303: a length is never dialled

    /// S-1303 (D-1305): the effort's own clock is its length, so neither the
    /// timed effort nor a period offers a row to dial, and the replay refuses
    /// the dial that the timeline used to carry.
    func testS1303ATimedSurfaceHasNoLengthToDial() async throws {
        let timed = try CaptureReplay("full")
        try await timed.run(stoppingBefore: ["log"])
        XCTAssertEqual(timed.surface.effortKind, WatchEffortKind.timed, "S-1303: the timed effort is current")
        XCTAssertTrue(timed.surface.fields.isEmpty, "S-1303: a timed effort shows no row to dial")
        assertMalformed("the surface has no duration to dial") {
            try timed.dial(WatchMetricKey.duration, to: 1200)
        }

        let period = try CaptureReplay("full")
        try await period.run(stoppingBefore: ["pauseRound"])
        XCTAssertEqual(period.surface.effortKind, WatchEffortKind.round, "S-1303: the period is current")
        XCTAssertTrue(period.surface.fields.isEmpty, "S-1303: a period shows no length to dial")
        assertMalformed("the surface has no round-duration to dial") {
            try period.dial(WatchMetricKey.roundDuration, to: 300)
        }
    }

    /// Asserts `body` throws the replay's own malformed error, naming `message`.
    private func assertMalformed(
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () throws -> Void
    ) {
        do {
            try body()
            XCTFail("S-1303: expected \"\(message)\" and nothing was thrown", file: file, line: line)
        } catch CaptureReplay.ReplayError.malformed(let thrown) {
            XCTAssertEqual(thrown, message, "S-1303: the replay's own message", file: file, line: line)
        } catch {
            XCTFail("S-1303: expected \"\(message)\", got \(error)", file: file, line: line)
        }
    }
}
