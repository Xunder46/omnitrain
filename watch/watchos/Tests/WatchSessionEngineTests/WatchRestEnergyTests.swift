//
//  WatchRestEnergyTests.swift
//  WatchSessionEngineTests
//
//  Plan 134e (the wrist's rest screen says the calories burned so far),
//  scenarios S-13480..S-13484 of
//  `docs/plans/2026-11-09-134e-wrist-rest-calories-plan/2026-11-09-134e-wrist-rest-calories-plan.md`.
//
//  S-13480 drives a recorder over a session and a fake source with energy
//  granted; S-13481..S-13482 read a `WatchLoggingState` over an engine; S-13484
//  guards the `WatchRestView.swift` source exactly as WatchRestLabelsTests'
//  S-7610 does.
//

import XCTest

@testable import WatchSessionEngine

final class WatchRestEnergyTests: XCTestCase {

    // MARK: - S-13480 the newest stored count is the reading

    func testS13480TheNewestStoredEnergyCountIsTheReading() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let live = await engine.createSession(modality: "resistance_lifting", exercises: [exercise("sx-bench")])
        let source = YieldingSensorSource()
        let recorder = WatchSensorRecorder(engine: engine, source: source, clock: harness.clock.call)

        XCTAssertNil(
            recorder.readings.activeEnergyKcal,
            "S-13480 with no energy sample there is no reading"
        )

        await recorder.start(live)
        harness.clock.advance(300)
        source.energy(40.0)
        await eventually {
            recorder.readings.activeEnergyKcal == 40.0
        }
        harness.clock.advance(300)
        source.energy(95.5)
        await eventually {
            recorder.readings.activeEnergyKcal == 95.5
        }
        XCTAssertEqual(
            recorder.readings.activeEnergyKcal,
            95.5,
            "S-13480 the newest stored cumulative sample is the reading"
        )
    }

    // MARK: - S-13481 the label, rounded, nothing under half a kilocalorie

    func testS13481TheEnergyLabelRoundsTheHalfKilocalorieUpAndHidesBelowIt() async throws {
        let roundedUp = try await stateOverEnergy(95.5)
        XCTAssertEqual(
            roundedUp.sensorLabels.activeEnergy,
            "96 kcal burned",
            "S-13481 95.5 rounds to 96"
        )

        let bigTotal = try await stateOverEnergy(1234.4)
        XCTAssertEqual(
            bigTotal.sensorLabels.activeEnergy,
            "1234 kcal burned",
            "S-13481 the whole running total, rounded"
        )

        let exactlyHalf = try await stateOverEnergy(0.5)
        XCTAssertEqual(
            exactlyHalf.sensorLabels.activeEnergy,
            "1 kcal burned",
            "S-13481 0.5 rounds up to 1"
        )

        let lessThanHalf = try await stateOverEnergy(0.3)
        XCTAssertNil(
            lessThanHalf.sensorLabels.activeEnergy,
            "S-13481 below half a kilocalorie shows nothing"
        )

        let empty = try await stateOverEnergy(nil)
        XCTAssertNil(
            empty.sensorLabels.activeEnergy,
            "S-13481 no sample shows nothing"
        )
    }

    // MARK: - S-13482 the accessor reads the same labels

    func testS13482TheAccessorEqualsTheLabelResolution() async throws {
        let state = try await stateOverEnergy(95.5)
        XCTAssertEqual(
            state.activeEnergyLabel,
            state.sensorLabels.activeEnergy,
            "S-13482 the accessor is the label resolution, no second derivation"
        )
    }

    // MARK: - S-13483 what VoiceOver says

    func testS13483TheSpokenEnergyNeverSpeaksANegative() {
        XCTAssertEqual(
            WatchSpokenText.activeEnergy(kilocalories: 96),
            "96 kilocalories burned",
            "S-13483 the plural count"
        )
        XCTAssertEqual(
            WatchSpokenText.activeEnergy(kilocalories: 1),
            "1 kilocalorie burned",
            "S-13483 one speaks the singular"
        )
        XCTAssertEqual(
            WatchSpokenText.activeEnergy(kilocalories: 0),
            "0 kilocalories burned",
            "S-13483 zero stays a count, not a silence"
        )
        XCTAssertEqual(
            WatchSpokenText.activeEnergy(kilocalories: -4),
            "0 kilocalories burned",
            "S-13483 a negative reads as zero"
        )
    }

    // MARK: - S-13484 the source guard: the line sits under the clock

    func testS13484TheRestViewShowsTheBurnedLineUnderTheClock() throws {
        let source = try engineSource("WatchRestView.swift")
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        XCTAssertTrue(
            source.contains("if let burned = state.activeEnergyLabel {"),
            "S-13484 the conditional statement, verbatim"
        )
        XCTAssertTrue(
            source.contains("Text(burned)"),
            "S-13484 the burned text, verbatim"
        )
        XCTAssertTrue(
            source.contains(".accessibilityLabel(\"Calories burned\")"),
            "S-13484 the VoiceOver label, verbatim"
        )

        let elapsedIndex = try XCTUnwrap(
            lines.firstIndex { $0.contains("Text(elapsed)") },
            "S-13484 the clock line stays on the screen"
        )
        let burnedIndex = try XCTUnwrap(
            lines.firstIndex { $0.contains("if let burned = state.activeEnergyLabel {") },
            "S-13484 the burned line"
        )
        let nextIndex = try XCTUnwrap(
            lines.firstIndex { $0.contains("Text(labels.next)") },
            "S-13484 the next line stays on the screen"
        )
        XCTAssertLessThan(elapsedIndex, burnedIndex, "S-13484 the burned line follows the clock")
        XCTAssertLessThan(burnedIndex, nextIndex, "S-13484 and precedes what is next")
    }

    // MARK: - Helpers

    /// A running session with `kilocalories` stored as its newest active-energy
    /// sample (nil stores none), and the logging state over it, wired to a
    /// sensor recorder so `readings` resolves the engine's stored rows.
    private func stateOverEnergy(_ kilocalories: Double?) async throws -> WatchLoggingState {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        if let kilocalories {
            await engine.appendSensorSample(kind: WatchSensorKind.activeEnergy, value: kilocalories)
        }
        return WatchLoggingState(
            engine: engine,
            clock: harness.clock.call,
            sensors: WatchSensorRecorder(
                engine: engine,
                source: YieldingSensorSource(),
                clock: harness.clock.call
            )
        )
    }

    /// A file of the watch package's engine module, read from the repository
    /// root, with every comment-only line blanked out (the line count is kept).
    private func engineSource(_ name: String) throws -> String {
        let url = Fixtures.repositoryRoot
            .appendingPathComponent("watch/watchos/Sources/WatchSessionEngine/\(name)")
        let text = try String(contentsOf: url, encoding: .utf8)
        return strippingCommentLines(text)
    }

    /// Blanks every line whose trimmed text starts with `//`, keeping the line
    /// boundaries so line indexes stay true, and blanks trailing `//` comments
    /// on code lines.
    private func strippingCommentLines(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { return "" }
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }
}
