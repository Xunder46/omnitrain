//
//  WatchCancelEmptyFreeWorkoutTests.swift
//  WatchSessionEngineTests
//
//  Closing the free workout's picker without choosing cancels the empty
//  session it started (plan 57, scenarios S-8701..S-8706).
//
//  Plan:
//  `docs/plans/2026-10-23-57-cancel-empty-free-workout-plan/2026-10-23-57-cancel-empty-free-workout-plan.md`.
//
//  S-8706 reads the two targets' sources with their comment lines stripped,
//  the way `WatchNutritionWiringSourceTests` does: the views compile only
//  under xcodebuild, so what `swift test` can hold is the text the wiring is
//  made of.
//

import Foundation
import XCTest

@testable import WatchSessionEngine

final class WatchCancelEmptyFreeWorkoutTests: XCTestCase {

    // MARK: - Fixture readers (copied from WatchSessionStartPathsTests.swift,
    // whose helpers are private to that file)

    private enum StartFixtureError: Error {
        case malformed(String)
    }

    private func startContract() throws -> [String: Any] {
        let url = Fixtures.repositoryRoot
            .appendingPathComponent("watch/contract/watch_start_paths_contract.json")
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StartFixtureError.malformed("watch_start_paths_contract.json")
        }
        return object
    }

    private func object(_ value: Any?) throws -> [String: Any] {
        guard let value = value as? [String: Any] else {
            throw StartFixtureError.malformed("expected an object, found \(String(describing: value))")
        }
        return value
    }

    private func firstMessage() throws -> [String: Any] {
        let fallback = try object(try startContract()["fallback"])
        return try object(fallback["routinesDown"])
    }

    // MARK: - Source readers (the same stripping WatchNutritionWiringSourceTests
    // applies, so a sentence of prose can neither satisfy a guard nor trip one)

    private func appSource(_ name: String) throws -> String {
        let url = Fixtures.repositoryRoot
            .appendingPathComponent("ios/OmniTrain Watch App/\(name)")
        return strippingCommentLines(try String(contentsOf: url, encoding: .utf8))
    }

    private func engineSource(_ name: String) throws -> String {
        let url = Fixtures.repositoryRoot
            .appendingPathComponent("watch/watchos/Sources/WatchSessionEngine/\(name)")
        return strippingCommentLines(try String(contentsOf: url, encoding: .utf8))
    }

    private func strippingCommentLines(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { return "" }
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    // MARK: - S-8701: the empty free workout is cancelled

    func testS8701CancellingAnEmptyFreeWorkoutAbandonsIt() async throws {
        let harness = WatchStartHarness()
        await harness.launch()
        _ = try await harness.receive(try firstMessage())
        _ = await harness.paths.startFreeWorkout()

        let cancelled = await harness.paths.cancelEmptyFreeWorkout()

        XCTAssertTrue(cancelled, "S-8701 the empty session was given up")
        XCTAssertEqual(
            harness.engine.session?.status,
            WatchSessionStatus.abandoned,
            "S-8701 the session reads abandoned, not active"
        )
    }

    // MARK: - S-8702: a fresh start after the cancel

    func testS8702AFreshFreeWorkoutStartsAfterTheCancel() async throws {
        let harness = WatchStartHarness()
        await harness.launch()
        _ = try await harness.receive(try firstMessage())
        let first = await harness.paths.startFreeWorkout()
        let cancelled = await harness.paths.cancelEmptyFreeWorkout()
        XCTAssertTrue(cancelled)

        let second = await harness.paths.startFreeWorkout()

        // The harness pins `sessionIdFactory` to one constant, so the fresh
        // start is told apart by its row: a different record, not the cancelled
        // one (the plan's "different sessionId" reads here as a different row).
        XCTAssertNotEqual(
            second.recordId,
            first.recordId,
            "S-8702 a new session row, not the cancelled one"
        )
        XCTAssertEqual(second.status, WatchSessionStatus.active, "S-8702 it is live")
        XCTAssertTrue(second.exercises.isEmpty, "S-8702 and empty, waiting for the picker")
    }

    // MARK: - S-8703: a session holding a pick is never touched

    func testS8703ASessionWithAnExerciseIsNotCancelled() async throws {
        let harness = WatchStartHarness()
        await harness.launch()
        _ = try await harness.receive(try firstMessage())
        let bench = try XCTUnwrap(
            harness.paths.fallbackExercises.first { $0.exerciseId == "ex-barbell-bench-press" }
        )
        _ = await harness.paths.startFreeWorkout()
        _ = await harness.paths.addExerciseToSession(bench)

        let cancelled = await harness.paths.cancelEmptyFreeWorkout()

        XCTAssertFalse(cancelled, "S-8703 a session holding an exercise is never given up")
        XCTAssertEqual(harness.engine.session?.status, WatchSessionStatus.active)
        XCTAssertEqual(harness.engine.session?.exercises.count, 1)
    }

    // MARK: - S-8704: a slot the phone pushed is an exercise too

    func testS8704ASessionHoldingAPushedSlotIsNotCancelled() async throws {
        let harness = WatchStartHarness()
        await harness.launch()
        _ = try await harness.receive(try firstMessage())
        _ = await harness.paths.startFreeWorkout()
        let slot: [String: Any] = [
            "sessionExerciseId": "s-phone-push",
            "exerciseId": "ex-phone-push",
            "name": "Phone Push",
            "capabilities": ["sets", "reps", "load"],
        ]
        _ = await harness.engine.insertExercise(slot, moveTo: false)

        let cancelled = await harness.paths.cancelEmptyFreeWorkout()

        XCTAssertFalse(cancelled, "S-8704 the phone's push made the session worth keeping")
        XCTAssertEqual(harness.engine.session?.status, WatchSessionStatus.active)
    }

    // MARK: - S-8705: a session that is not active is never touched

    func testS8705ACompletedSessionIsNotCancelled() async throws {
        let harness = WatchStartHarness()
        await harness.launch()
        _ = try await harness.receive(try firstMessage())
        _ = await harness.paths.startFreeWorkout()
        _ = await harness.engine.finishSession()

        let cancelled = await harness.paths.cancelEmptyFreeWorkout()

        XCTAssertFalse(cancelled, "S-8705 a finished session is history, not a live one to cancel")
        XCTAssertEqual(harness.engine.session?.status, WatchSessionStatus.completed)
    }

    func testS8705WithNoSessionAtAllCancelIsFalse() async throws {
        let harness = WatchStartHarness()
        await harness.launch()
        _ = try await harness.receive(try firstMessage())

        let cancelled = await harness.paths.cancelEmptyFreeWorkout()

        XCTAssertFalse(cancelled, "S-8705 nothing held, nothing cancelled")
        XCTAssertNil(harness.engine.session)
    }

    // MARK: - S-8706: the wiring is the text the two targets are made of

    func testS8706ThePickerSheetCancelsOnDismissAndTheHostReReads() throws {
        let start = try engineSource("WatchStartView.swift")
        XCTAssertTrue(
            start.contains(".sheet(isPresented: $pickingExercise, onDismiss: cancelIfNothingPicked)"),
            "S-8706 the picker sheet cancels on dismiss"
        )
        XCTAssertTrue(
            start.contains("cancelEmptyFreeWorkout()"),
            "S-8706 the dismiss asks the paths, whose guard keeps a picked session"
        )
        XCTAssertTrue(
            start.contains("onFreeWorkoutCancelled()"),
            "S-8706 the host is told so it re-reads the engine"
        )

        let content = try appSource("ContentView.swift")
        XCTAssertTrue(
            content.contains("onFreeWorkoutCancelled: { host.noteSurfaceChange() }"),
            "S-8706 the host re-reads the engine the same way a start does"
        )
    }
}
