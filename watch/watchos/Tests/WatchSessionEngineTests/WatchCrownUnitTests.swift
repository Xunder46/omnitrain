//
//  WatchCrownUnitTests.swift
//  WatchSessionEngineTests
//
//  S-7501 to S-7505 of
//  `docs/plans/2026-10-21-51a-wrist-crown-and-layout-plan/2026-10-21-51a-wrist-crown-and-layout-plan.md`
//  — the Crown unit on watchOS is one value unit per detent (D-1, D-2), the
//  logging and rating states step one value per event, and the surfaces pass
//  the constant to `.digitalCrownRotation(by:)` rather than a literal.
//

import Foundation
import XCTest

@testable import WatchSessionEngine

final class WatchCrownUnitTests: XCTestCase {

    // MARK: - S-7501 one value unit per detent

    @MainActor
    func testS7501TheCrownUnitIsOneValueUnit() {
        XCTAssertEqual(WatchMetricStepping.pointsPerDetent, 1)
        XCTAssertEqual(WatchLoggingModel.pointsPerDetent, 1)
    }

    // MARK: - S-7502 one value unit steps the armed count by one

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

    /// The bench set every crown case starts from: reps 10, load 0.
    @MainActor
    private func benchModel(
        _ harness: Harness,
        exercises: [[String: Any]]? = nil
    ) async -> (engine: WatchSessionEngine, model: WatchLoggingModel) {
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: nil,
            exercises: exercises ?? [exercise("sx-bench")]
        )
        let model = WatchLoggingModel(
            state: WatchLoggingState(engine: engine, clock: harness.clock.call),
            haptics: RecordingHaptics()
        )
        return (engine, model)
    }

    @MainActor
    func testS7502OneValueUnitStepsTheRepsByOne() async throws {
        let harness = Harness()
        let (_, model) = await benchModel(harness)
        XCTAssertEqual(field(model, WatchMetricKey.reps).value, 10)

        model.turn(to: 1)
        XCTAssertEqual(field(model, WatchMetricKey.reps).value, 11, "crown value 1 is one detent")

        model.turn(to: 3)
        XCTAssertEqual(field(model, WatchMetricKey.reps).value, 13, "two more value units are two more steps")
    }

    // MARK: - S-7503 the rating scale steps by one

    func testS7503TheFirstTwoValueUnitsPickTheFirstTwoNumbers() async throws {
        let wrist = await RatingHarness().launch()
        await wrist.sync(true, generatedAt: "2026-10-21T09:00:00Z")
        try await wrist.loggedSession(
            start: "2026-10-21T10:00:00Z",
            set: "e-1",
            logged: "2026-10-21T10:05:00Z",
            end: "2026-10-21T10:10:00Z"
        )
        let state = try XCTUnwrap(wrist.rating)
        XCTAssertNil(state.selected, "nothing is picked before the first turn")

        state.turnCrown(to: 1)
        XCTAssertEqual(state.selected, 1, "one value unit picks the lowest number")

        state.turnCrown(to: 2)
        XCTAssertEqual(state.selected, 2, "the next value unit picks the next number")
    }

    // MARK: - S-7504 the nutrition model borrows the constant

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

    func testS7504NutritionDeclaresTheCrownUnitWithoutALiteral() throws {
        let source = try engineSource("WatchNutritionView.swift")
        let line = try XCTUnwrap(
            source.split(separator: "\n", omittingEmptySubsequences: false)
                .first { $0.contains("static let pointsPerDetent") }
                .map(String.init),
            "WatchNutritionModel declares pointsPerDetent"
        )

        XCTAssertTrue(
            line.contains("WatchMetricStepping.pointsPerDetent"),
            "the declaration borrows the shared constant: \(line)"
        )
        XCTAssertFalse(
            line.contains { $0.isNumber },
            "the declaration carries no number of its own: \(line)"
        )
    }

    // MARK: - S-7505 the crown sites pass the constant

    func testS7505TheCrownSitesPassTheUnitConstant() throws {
        for name in ["WatchLoggingView.swift", "WatchEffortRatingView.swift", "WatchNutritionView.swift"] {
            let source = try engineSource(name)
            let start = try XCTUnwrap(
                source.range(of: "digitalCrownRotation"),
                "\(name) binds the Crown"
            )
            let end = try XCTUnwrap(
                source.range(
                    of: "isHapticFeedbackEnabled",
                    range: start.upperBound..<source.endIndex
                ),
                "\(name)'s Crown call ends at its haptic flag"
            )
            let call = source[start.lowerBound..<end.lowerBound]
            let by = try XCTUnwrap(
                call.range(of: "by: "),
                "\(name) passes a step to the Crown"
            )
            let step = call[by.upperBound...].first

            XCTAssertNotNil(step, "\(name) passes something as the step")
            XCTAssertFalse(
                step?.isNumber ?? true,
                "\(name) passes a constant, not a digit literal"
            )
        }
    }
}
