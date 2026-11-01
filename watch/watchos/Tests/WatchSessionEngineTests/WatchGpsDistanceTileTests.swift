//
//  WatchGpsDistanceTileTests.swift
//  WatchSessionEngineTests
//
//  Plan 93 (`docs/plans/2026-11-01-93-wrist-distance-tile-gps-only-plan/…`):
//  a timed effort on a distance exercise shows a Distance tile only while GPS
//  has measured movement inside the running effort's own window, read-only;
//  nothing the user dials on the wrist reaches the log.
//
//  Scenario mapping:
//    S-16001 before Start there is no tile                         → `testS16001...`
//    S-16002 a sample exactly at the Start instant is the baseline → `testS16002...`
//    S-16003 stale pre-Start samples never count                   → `testS16003...`
//    S-16004 a still watch with samples inside the window          → `testS16004...`
//    S-16005 Location refused                                      → `testS16005...`
//    S-16006 first movement shows the tile, read-only, no Crown    → `testS16006...`
//    S-16007 the next effort measures its own window               → `testS16007...`
//    S-16008 an exercise without distance never shows the tile     → `testS16008...`
//    S-16009 a hold and a period never show the tile               → `testS16009...`
//    S-16010 the tile reads in the phone's unit                    → `testS16010...`
//    S-16011 a measured tile has no − / + (view source scan)       → `testS16011...`
//    S-16012 nothing dialled on the wrist reaches the log (Crown)  → `testS16012...`
//            (the plain-state half: WatchLoggingSurfacesTests S-006)
//    S-16013 no source file produces "entered"                     → `testS16013...`
//
//  Every fix is awaited through `eventually` (the readout, or the count of
//  stored `gps` samples when the readout cannot change) before the clock
//  moves, so the sample is stamped at the instant the scenario names.
//

import XCTest

@testable import WatchSessionEngine

final class WatchGpsDistanceTileTests: XCTestCase {

    private var harness: Harness!
    private var source: FakeSensorSource!
    private var clock: TestClock!

    override func setUp() {
        super.setUp()
        harness = Harness()
        source = FakeSensorSource()
        clock = harness.clock
    }

    override func tearDown() {
        source.close()
        super.tearDown()
    }

    /// F-RUN's slot: timed work over a distance the modality can cover.
    private static let run: [String: Any] = [
        "sessionExerciseId": "sx-run",
        "exerciseId": "ex-run",
        "name": "Run",
        "capabilities": ["time", "distance"],
    ]

    private func session(
        _ engine: WatchSessionEngine,
        modality: String = "cardio_endurance",
        slot: [String: Any] = WatchGpsDistanceTileTests.run
    ) async -> WatchSessionRecord {
        await engine.createSession(modality: modality, exercises: [slot])
    }

    private func measuring(
        _ engine: WatchSessionEngine,
        _ session: WatchSessionRecord
    ) async -> WatchSensorRecorder {
        let recorder = WatchSensorRecorder(engine: engine, source: source, clock: clock.call)
        await recorder.start(session)
        return recorder
    }

    private func surface(
        _ engine: WatchSessionEngine,
        _ recorder: WatchSensorRecorder? = nil,
        units: WatchUnitPreferences = WatchUnitPreferences()
    ) -> WatchLoggingState {
        WatchLoggingState(engine: engine, clock: clock.call, units: units, sensors: recorder)
    }

    private func gpsSamples(_ engine: WatchSessionEngine) -> Int {
        engine.sensorSamples.filter { $0.kind == WatchSensorKind.gps }.count
    }

    /// Stores one `gps` sample of cumulative `metres` at the clock's current
    /// instant, and waits until it is stored.
    private func fix(_ metres: Double, on engine: WatchSessionEngine) async {
        let before = gpsSamples(engine)
        source.fix(metres)
        await eventually({ self.gpsSamples(engine) == before + 1 }, "the gps sample was never stored")
    }

    private func distance(_ state: WatchLoggingState) throws -> WatchMetricField {
        try XCTUnwrap(state.fields.first { $0.metricKey == WatchMetricKey.distance }, "no distance tile")
    }

    private func assertNoDistanceKeys(
        _ payload: [String: Any],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertNil(payload["distanceMeters"], "no distance travels", file: file, line: line)
        XCTAssertNil(payload["distanceSource"], "no source travels", file: file, line: line)
    }

    /// The event the surface logged last, with the schema's verdict on the
    /// frame that carried it.
    private func loggedEvent() throws -> (event: [String: Any], rejections: [SyncProtocolRejection]) {
        let envelope = try XCTUnwrap(
            harness.emitted.last(where: { $0["type"] as? String == "observations_up" })
        )
        let events = (envelope["payload"] as? [String: Any])?["events"] as? [[String: Any]]
        return (try XCTUnwrap(events?.first), Harness.validator().validateEnvelope(envelope))
    }

    // MARK: - S-16001 before Start there is no tile

    @MainActor
    func testS16001BeforeStartThereIsNoTile() async throws {
        let engine = await harness.runningEngine()
        let live = await session(engine)
        let recorder = await measuring(engine, live)
        await fix(800, on: engine)

        let state = surface(engine, recorder)
        let model = WatchLoggingModel(state: state, haptics: RecordingHaptics())
        XCTAssertEqual(state.effortKind, WatchEffortKind.timed)
        XCTAssertEqual(state.fields.map(\.metricKey), [], "a stale sample and no Start: no tile")
        XCTAssertNil(model.armedMetricKey)
        XCTAssertEqual(model.primaryTitle, "Start")

        // The same session without a recorder.
        let bare = surface(engine)
        let bareModel = WatchLoggingModel(state: bare, haptics: RecordingHaptics())
        XCTAssertEqual(bare.effortKind, WatchEffortKind.timed)
        XCTAssertEqual(bare.fields.map(\.metricKey), [], "no recorder: no tile")
        XCTAssertNil(bareModel.armedMetricKey)
        XCTAssertEqual(bareModel.primaryTitle, "Start")
    }

    // MARK: - S-16002 a sample exactly at the Start instant is the baseline

    func testS16002ASampleExactlyAtTheStartInstantIsTheBaseline() async throws {
        let engine = await harness.runningEngine()
        let live = await session(engine)
        let recorder = await measuring(engine, live)
        let state = surface(engine, recorder)

        await state.startWork()
        // The clock has not moved since Start: the sample is the baseline.
        await fix(800, on: engine)
        clock.advance(600)

        XCTAssertEqual(state.fields.map(\.metricKey), [], "the window covered nothing")
        let logged = try await state.log()
        assertNoDistanceKeys(logged.payload)
    }

    // MARK: - S-16003 stale pre-Start samples never count

    func testS16003StalePreStartSamplesNeverCount() async throws {
        let engine = await harness.runningEngine()
        let live = await session(engine)
        let recorder = await measuring(engine, live)
        let state = surface(engine, recorder)
        await fix(800, on: engine)

        clock.advance(300)
        await state.startWork()
        XCTAssertEqual(state.fields.map(\.metricKey), [], "at Start the baseline is 800")

        clock.advance(1200)
        XCTAssertEqual(state.fields.map(\.metricKey), [], "nothing after the baseline")
        let logged = try await state.log()
        assertNoDistanceKeys(logged.payload)
    }

    // MARK: - S-16004 a still watch with samples inside the window measures 0

    func testS16004AStillWatchWithSamplesInsideTheWindowMeasuresZero() async throws {
        let engine = await harness.runningEngine()
        let live = await session(engine)
        let recorder = await measuring(engine, live)
        let state = surface(engine, recorder)
        await fix(800, on: engine)

        clock.advance(300)
        await state.startWork()
        clock.advance(60)
        await fix(800, on: engine)
        clock.advance(60)
        await fix(800, on: engine)
        XCTAssertEqual(gpsSamples(engine), 3)

        XCTAssertTrue(state.isMeasuringDistance, "the subscription runs")
        XCTAssertEqual(state.fields.map(\.metricKey), [], "(800−800)+(800−800) = 0: no tile")
        let logged = try await state.log()
        assertNoDistanceKeys(logged.payload)
    }

    // MARK: - S-16005 Location refused

    @MainActor
    func testS16005LocationRefusedShowsNoTileAndLogsNoDistance() async throws {
        source.locationGrant = .denied
        let engine = await harness.runningEngine()
        let live = await session(engine)
        let recorder = await measuring(engine, live)
        let state = surface(engine, recorder)
        let model = WatchLoggingModel(state: state, haptics: RecordingHaptics())

        await state.startWork()
        clock.advance(600)
        XCTAssertFalse(state.isMeasuringDistance, "access was refused")
        XCTAssertEqual(state.fields.map(\.metricKey), [], "before the dial attempts")

        state.adjust(WatchMetricKey.distance, detents: 25)
        model.turn(to: 3 * WatchLoggingModel.pointsPerDetent)
        model.stepArmed(1)

        XCTAssertEqual(state.fields.map(\.metricKey), [], "after the dial attempts")
        XCTAssertTrue(state.sensorNotices.contains(WatchSensorNoticeCopy.noDistance))
        let logged = try await state.log()
        assertNoDistanceKeys(logged.payload)
    }

    // MARK: - S-16006 first movement shows the tile, read-only, without the Crown

    @MainActor
    func testS16006FirstMovementShowsAReadOnlyTileThatNeverTakesTheCrown() async throws {
        let engine = await harness.runningEngine()
        let live = await session(engine)
        let recorder = await measuring(engine, live)
        let state = surface(engine, recorder)
        let model = WatchLoggingModel(state: state, haptics: RecordingHaptics())
        await fix(300, on: engine)

        clock.advance(60)
        await state.startWork()
        clock.advance(600)
        XCTAssertEqual(state.fields.map(\.metricKey), [], "before the fix: no tile")

        await fix(1534, on: engine)
        XCTAssertEqual(state.fields.map(\.metricKey), [WatchMetricKey.distance])
        let tile = try distance(state)
        XCTAssertTrue(tile.isMeasured)
        XCTAssertEqual(tile.value, 1234, "1534 − 300: the effort's own window")
        XCTAssertEqual(tile.displayValue, "1.2")
        XCTAssertEqual(tile.unitLabel, "km")
        XCTAssertNil(model.armedMetricKey, "the tile never takes the Crown")
        XCTAssertEqual(model.primaryTitle, "Log")

        model.turn(to: 3 * WatchLoggingModel.pointsPerDetent)
        XCTAssertNil(model.armedMetricKey, "after a turn the Crown is still unarmed")
        model.stepArmed(1)
        state.adjust(WatchMetricKey.distance, detents: 10)
        XCTAssertEqual(try distance(state).value, 1234, "turn, step and adjust change nothing")
        XCTAssertEqual(model.primaryTitle, "Log")

        clock.advance(600)
        let logged = try await state.log()
        XCTAssertEqual(logged.payload["distanceMeters"] as? Double, 1234, "I-1: the Log equals the tile")
        XCTAssertEqual(logged.payload["distanceSource"] as? String, "gps")
    }

    // MARK: - S-16007 the next effort starts with no tile and measures its own window

    func testS16007TheNextEffortStartsWithNoTileAndMeasuresItsOwnWindow() async throws {
        let engine = await harness.runningEngine()
        let live = await session(engine)
        let recorder = await measuring(engine, live)
        let state = surface(engine, recorder)

        // Effort 1.
        await state.startWork()
        clock.advance(600)
        await fix(500, on: engine)
        clock.advance(600)
        let first = try await state.log()
        XCTAssertEqual(first.payload["distanceMeters"] as? Double, 500)
        XCTAssertEqual(first.payload["distanceSource"] as? String, "gps")

        // Rest: movement while no work clock runs.
        clock.advance(200)
        await fix(650, on: engine)
        clock.advance(100)
        XCTAssertEqual(state.fields.map(\.metricKey), [], "a stopped clock measures nothing")

        // Effort 2.
        await state.startWork()
        XCTAssertEqual(state.fields.map(\.metricKey), [], "right after Start the baseline is 650")
        clock.advance(60)
        await fix(850, on: engine)
        let tile = try distance(state)
        XCTAssertTrue(tile.isMeasured)
        XCTAssertEqual(tile.value, 200, "850 − 650: this effort's own window")
        XCTAssertEqual(recorder.readings.distanceMeters, 850, "the session total is a different number")

        clock.advance(600)
        let second = try await state.log()
        XCTAssertEqual(second.payload["distanceMeters"] as? Double, 200)
        XCTAssertEqual(second.payload["distanceSource"] as? String, "gps")
    }

    // MARK: - S-16008 an exercise without the distance capability never shows the tile

    func testS16008AnExerciseWithoutDistanceNeverShowsTheTile() async throws {
        let engine = await harness.runningEngine()
        let live = await session(engine, slot: [
            "sessionExerciseId": "sx-row",
            "exerciseId": "ex-row",
            "name": "Row",
            "capabilities": ["time"],
        ])
        let recorder = await measuring(engine, live)
        let state = surface(engine, recorder)
        XCTAssertEqual(state.fields.map(\.metricKey), [], "before Start")

        await state.startWork()
        clock.advance(60)
        await fix(400, on: engine)
        XCTAssertEqual(state.fields.map(\.metricKey), [], "after movement")
    }

    // MARK: - S-16009 a hold and a period never show the tile, even with movement

    func testS16009AHoldAndAPeriodNeverShowTheTileEvenWithMovement() async throws {
        // (a) A period.
        let periodEngine = await harness.runningEngine()
        let period = await session(periodEngine, modality: "sports", slot: [
            "sessionExerciseId": "sx-period",
            "exerciseId": "ex-period",
            "name": "Period",
            "capabilities": ["time", "rounds", "distance"],
        ])
        let periodRecorder = await measuring(periodEngine, period)
        let periodState = surface(periodEngine, periodRecorder)
        XCTAssertEqual(periodState.effortKind, WatchEffortKind.round)
        XCTAssertEqual(periodState.fields.map(\.metricKey), [WatchMetricKey.roundDuration])
        await periodState.startWork()
        clock.advance(60)
        await fix(400, on: periodEngine)
        XCTAssertEqual(periodState.fields.map(\.metricKey), [], "a running period has no rows (D-3404)")
        source.close()

        // (b) A hold, on a harness and sensor source of its own.
        let holdHarness = Harness()
        let holdSource = FakeSensorSource()
        defer { holdSource.close() }
        let holdEngine = await holdHarness.runningEngine()
        let hold = await holdEngine.createSession(
            modality: "isometric_stretching",
            exercises: [[
                "sessionExerciseId": "sx-plank",
                "exerciseId": "ex-plank",
                "name": "Plank",
                "capabilities": ["hold", "time", "distance"],
            ]]
        )
        let holdRecorder = WatchSensorRecorder(
            engine: holdEngine,
            source: holdSource,
            clock: holdHarness.clock.call
        )
        await holdRecorder.start(hold)
        let holdState = WatchLoggingState(
            engine: holdEngine,
            clock: holdHarness.clock.call,
            sensors: holdRecorder
        )
        XCTAssertEqual(holdState.effortKind, WatchEffortKind.drill)
        XCTAssertEqual(holdState.fields.map(\.metricKey), [WatchMetricKey.extraWeight])
        await holdState.startWork()
        holdHarness.clock.advance(60)
        holdSource.fix(400)
        await eventually { self.gpsSamples(holdEngine) == 1 }
        XCTAssertEqual(holdState.fields.map(\.metricKey), [WatchMetricKey.extraWeight])
    }

    // MARK: - S-16010 the tile reads in the phone's unit

    func testS16010TheTileReadsInThePhonesUnit() async throws {
        let engine = await harness.runningEngine()
        let live = await session(engine)
        let recorder = await measuring(engine, live)
        let miles = surface(engine, recorder, units: WatchUnitPreferences(distanceUnit: "miles"))
        let kilometres = surface(engine, recorder)

        await miles.startWork()
        clock.advance(600)
        await fix(1609.344, on: engine)

        let mileTile = try distance(miles)
        XCTAssertEqual(mileTile.displayValue, "1.0")
        XCTAssertEqual(mileTile.unitLabel, "mi")
        XCTAssertEqual(mileTile.value, 1609.344)
        let kmTile = try distance(kilometres)
        XCTAssertEqual(kmTile.displayValue, "1.6")
        XCTAssertEqual(kmTile.unitLabel, "km")
        XCTAssertEqual(kmTile.value, 1609.344)

        let logged = try await miles.log()
        XCTAssertEqual(try XCTUnwrap(logged.payload["distanceMeters"] as? Double), 1609.344, accuracy: 0.001)
        XCTAssertEqual(logged.payload["distanceSource"] as? String, "gps")
    }

    // MARK: - S-16012 nothing dialled on the wrist reaches the log (Crown half)

    @MainActor
    func testS16012NothingDialledOnTheWristReachesTheLog() async throws {
        let engine = await harness.runningEngine()
        _ = await session(engine)
        let state = surface(engine)
        let model = WatchLoggingModel(state: state, haptics: RecordingHaptics())
        XCTAssertEqual(state.fields.map(\.metricKey), [])

        await state.startWork()
        XCTAssertEqual(state.fields.map(\.metricKey), [])
        clock.advance(120)
        state.adjust(WatchMetricKey.distance, detents: 5)
        XCTAssertEqual(state.fields.map(\.metricKey), [])
        model.turn(to: 3 * WatchLoggingModel.pointsPerDetent)
        XCTAssertEqual(state.fields.map(\.metricKey), [])
        model.stepArmed(1)
        XCTAssertEqual(state.fields.map(\.metricKey), [])
        try await state.log()

        let captured = try loggedEvent()
        assertNoDistanceKeys(captured.event)
        XCTAssertTrue(captured.rejections.isEmpty, "\(captured.rejections)")
    }

    // MARK: - S-16013 no source file produces "entered"

    func testS16013NoSourceFileProducesEntered() throws {
        let root = Fixtures.repositoryRoot.appendingPathComponent("watch/watchos/Sources")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty, "the scan found the sources")

        var hits: [String] = []
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated() {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
                let code = line.range(of: "//").map { line[..<$0.lowerBound] } ?? line[...]
                if code.contains("\"entered\"") {
                    hits.append("\(file.lastPathComponent):\(index + 1)")
                }
            }
        }
        XCTAssertEqual(hits, [], "the wrist never produces distanceSource \"entered\" (I-2)")
    }

    // MARK: - S-16011 a measured tile has no − / +

    func testS16011AMeasuredTileHasNoStepButtons() throws {
        let url = Fixtures.repositoryRoot
            .appendingPathComponent("watch/watchos/Sources/WatchSessionEngine/WatchLoggingView.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { return "" }
                return line.range(of: "//").map { String(line[..<$0.lowerBound]) } ?? String(line)
            }
            .joined(separator: "\n")

        // The single-row path: a measured field leaves as its tile before any
        // step button is built.
        let row = try XCTUnwrap(
            body(of: "private func row(_ field: WatchMetricField)", in: source),
            "the single-row builder exists"
        )
        let measured = try XCTUnwrap(
            row.range(of: "if field.isMeasured {"),
            "the row branches on a measured field first (D-5)"
        )
        let other = try XCTUnwrap(
            row.range(of: "} else {", range: measured.upperBound..<row.endIndex),
            "the unmeasured branch keeps the − / + row"
        )
        let measuredBranch = row[measured.upperBound..<other.lowerBound]
        XCTAssertTrue(measuredBranch.contains("tile(field)"), "a measured field renders as its tile")
        XCTAssertFalse(measuredBranch.contains("stepButton("), "no − / + around a measured tile (D-5)")
        XCTAssertFalse(
            row[row.startIndex..<measured.lowerBound].contains("stepButton("),
            "no step button is built before the measured branch"
        )

        // The tile: the button trait belongs to unmeasured tiles only.
        let tile = try XCTUnwrap(
            body(of: "private func tile(_ field: WatchMetricField)", in: source),
            "the tile builder exists"
        )
        let traitLines = tile.split(separator: "\n").filter { $0.contains(".isButton") }
        XCTAssertFalse(traitLines.isEmpty, "an unmeasured tile is still a button")
        for line in traitLines {
            XCTAssertTrue(
                line.contains("field.isMeasured ? [] : .isButton"),
                "a measured tile has no button trait and every other tile keeps it: \(line)")
        }
    }

    /// The text between a declaration's opening brace and its matching close.
    private func body(of declaration: String, in source: String) -> Substring? {
        guard let start = source.range(of: declaration),
              let open = source.range(of: "{", range: start.upperBound..<source.endIndex)
        else { return nil }
        var depth = 0
        var index = open.lowerBound
        while index < source.endIndex {
            switch source[index] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return source[open.upperBound..<index] }
            default: break
            }
            index = source.index(after: index)
        }
        return nil
    }
}
