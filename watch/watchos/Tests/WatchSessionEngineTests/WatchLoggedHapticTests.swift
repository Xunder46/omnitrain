//
//  WatchLoggedHapticTests.swift
//  WatchSessionEngineTests
//
//  S-7801 to S-7805 of
//  `docs/plans/2026-10-21-51e-wrist-taps-confirm-plan/2026-10-21-51e-wrist-taps-confirm-plan.md`
//  — a recorded log plays one success tap (D-1, D-2), a start plays none, a
//  refused log plays nothing, and the surfaces map the taps and name the list
//  button (D-3).
//

import Foundation
import XCTest

@testable import WatchSessionEngine

final class WatchLoggedHapticTests: XCTestCase {

    // MARK: - Harness

    private func slot(
        _ id: String,
        capabilities: [String],
        roundDurationSecs: Int? = nil
    ) -> [String: Any] {
        var slot: [String: Any] = [
            "sessionExerciseId": id,
            "exerciseId": "ex-\(id)",
            "name": id,
            "capabilities": capabilities,
        ]
        if let roundDurationSecs {
            slot[WatchCatalogExercise.roundDurationKey] = roundDurationSecs
        }
        return slot
    }

    @MainActor
    private func field(_ model: WatchLoggingModel, _ metricKey: String) -> WatchMetricField {
        model.state.fields.first { $0.metricKey == metricKey }!
    }

    /// The bench set every case starts from: reps 10, load 0, with the
    /// `RecordingHaptics` the model plays into kept for the assertions.
    @MainActor
    private func benchModel(
        _ harness: Harness,
        exercises: [[String: Any]]? = nil
    ) async -> (engine: WatchSessionEngine, model: WatchLoggingModel, haptics: RecordingHaptics) {
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: nil,
            exercises: exercises ?? [exercise("sx-bench")]
        )
        let haptics = RecordingHaptics()
        let model = WatchLoggingModel(
            state: WatchLoggingState(engine: engine, clock: harness.clock.call),
            haptics: haptics
        )
        return (engine, model, haptics)
    }

    /// A model over an arrangement the caller names, with its recorder.
    @MainActor
    private func model(
        for exercises: [[String: Any]],
        _ harness: Harness
    ) async -> (WatchLoggingModel, RecordingHaptics) {
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil, exercises: exercises)
        let haptics = RecordingHaptics()
        let model = WatchLoggingModel(
            state: WatchLoggingState(engine: engine, clock: harness.clock.call),
            haptics: haptics
        )
        return (model, haptics)
    }

    // MARK: - S-7801 a set plays one tap per log

    @MainActor
    func testS7801ASetPlaysOneTapPerLoggedSet() async throws {
        let harness = Harness()
        let (_, model, haptics) = await benchModel(harness)

        await model.primaryAction()
        XCTAssertEqual(haptics.logged, 1, "the first log plays one tap")
        XCTAssertEqual(haptics.nexts, 0, "the primary button never plays the rest's Next tap")

        harness.clock.advance(120)
        await model.primaryAction()
        XCTAssertEqual(haptics.logged, 2, "the second log plays the second tap")
        XCTAssertEqual(haptics.nexts, 0)
    }

    // MARK: - S-7802 a timed effort starts silently, then logs

    @MainActor
    func testS7802ATimedEffortStartsSilentlyAndLogsOnTheSecondTap() async throws {
        let harness = Harness()
        let (model, haptics) = await model(
            for: [slot("sx-run", capabilities: ["time", "distance"])],
            harness
        )

        await model.primaryAction()
        XCTAssertEqual(haptics.logged, 0, "starting the clock is not logging")

        harness.clock.advance(60)
        await model.primaryAction()
        XCTAssertEqual(haptics.logged, 1, "the log that ended the effort plays one tap")
    }

    // MARK: - S-7803 the other entry plays the same tap

    @MainActor
    func testS7803LogPlaysTheTap() async throws {
        let harness = Harness()
        let (_, model, haptics) = await benchModel(harness)

        await model.log()
        XCTAssertEqual(haptics.logged, 1, "the direct entry plays the same tap")
    }

    // MARK: - S-7804 a refused log plays nothing

    @MainActor
    func testS7804ARefusedLogPlaysNothing() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil)
        let haptics = RecordingHaptics()
        let model = WatchLoggingModel(
            state: WatchLoggingState(engine: engine, clock: harness.clock.call),
            haptics: haptics
        )

        await model.primaryAction()
        XCTAssertEqual(haptics.logged, 0, "nothing to log against plays nothing")

        await model.log()
        XCTAssertEqual(haptics.logged, 0, "the direct entry is silent too")
    }

    // MARK: - S-7805 the surfaces play the taps

    /// A file of the watch package's engine module, read from the repository
    /// root, with every comment-only line blanked out (the line count is kept).
    private func engineSource(_ name: String) throws -> String {
        let url = Fixtures.repositoryRoot
            .appendingPathComponent("watch/watchos/Sources/WatchSessionEngine/\(name)")
        let text = try String(contentsOf: url, encoding: .utf8)
        return strippingCommentLines(text)
    }

    /// Blanks every line whose trimmed text starts with `//`, keeping the line
    /// boundaries so line indexes stay true. A trailing `//` comment on a code
    /// line is blanked too, so prose there can neither satisfy a guard nor trip
    /// one.
    private func strippingCommentLines(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { return "" }
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    func testS7805TheSurfacesPlayTheTapsAndNameTheListButton() throws {
        let rest = try engineSource("WatchRestView.swift")
        XCTAssertTrue(rest.contains("haptics.playNext()"), "the rest's Next plays the directional tap")

        let nutrition = try engineSource("WatchNutritionView.swift")
        XCTAssertTrue(nutrition.contains(".success"), "the food log plays the success tap")
        XCTAssertTrue(
            nutrition.contains("await model.log() != nil"),
            "the food log's tap is guarded by the record"
        )

        let logging = try engineSource("WatchLoggingView.swift")
        let logged = try XCTUnwrap(logging.range(of: "playLogged()"), "WristHaptics maps playLogged")
        let success = try XCTUnwrap(
            logging.range(of: ".success", range: logged.upperBound..<logging.endIndex),
            "playLogged plays .success"
        )
        XCTAssertLessThanOrEqual(
            logging.distance(from: logged.upperBound, to: success.lowerBound),
            120,
            ".success is the body of playLogged, not a distant line"
        )
        let next = try XCTUnwrap(logging.range(of: "playNext()"), "WristHaptics maps playNext")
        let up = try XCTUnwrap(
            logging.range(of: ".directionUp", range: next.upperBound..<logging.endIndex),
            "playNext plays .directionUp"
        )
        XCTAssertLessThanOrEqual(
            logging.distance(from: next.upperBound, to: up.lowerBound),
            120,
            ".directionUp is the body of playNext, not a distant line"
        )

        let content = try String(
            contentsOf: Fixtures.repositoryRoot
                .appendingPathComponent("ios/OmniTrain Watch App/ContentView.swift"),
            encoding: .utf8
        )
        XCTAssertEqual(
            content.components(separatedBy: ".accessibilityLabel(\"Exercises\")").count - 1,
            2,
            "both list buttons (rest and logging toolbars) carry the label"
        )
    }
}
