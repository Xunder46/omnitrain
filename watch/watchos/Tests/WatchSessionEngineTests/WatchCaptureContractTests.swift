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
//  One deliberate difference from a user's taps (O-13): after a round is
//  logged, the replay starts the next round's countdown itself, planned at the
//  round length that was dialled, as the contract's description states. The
//  wrist's own follow-on countdown reverts to the default length after a
//  dialled round, and PR 2 leaves that behaviour as it is.
//

import XCTest

@testable import WatchSessionEngine

/// Replays one F-CAP case: each timeline op, in array order, at its own
/// instant, through the same engine and logging surface a wrist runs.
final class CaptureReplay {
    let captureCase: [String: Any]
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

    /// Dials `metric` to exactly `value`, in whole detents.
    private func dial(_ metric: String, to value: Double) throws {
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
        let roundLength = surface.effortKind == WatchEffortKind.round
            ? surface.fields.first { $0.metricKey == WatchMetricKey.roundDuration }?.value
            : nil

        let logged = try await surface.log()
        guard logged.entryId == entryId else {
            throw ReplayError.malformed("logged \(logged.entryId), the timeline says \(entryId)")
        }

        // O-13: the next round's countdown, planned at the length dialled for
        // the round that started it — started here, explicitly.
        if let roundLength {
            _ = try await engine.startTimer(
                WatchTimerKind.round,
                plannedDurationMs: Int((roundLength * 1000).rounded())
            )
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
            }
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
        XCTAssertEqual(replay.emittedEvents.count, 8, "F-CAP prompt-off: no rating, so eight events")
        XCTAssertFalse(replay.rating.isPromptOwed, "F-CAP prompt-off: the setting is off, so nothing is owed")
    }
}
