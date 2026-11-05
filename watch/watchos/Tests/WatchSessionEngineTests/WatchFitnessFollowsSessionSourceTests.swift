//
//  WatchFitnessFollowsSessionSourceTests.swift
//  WatchSessionEngineTests
//
//  Source guards for what `swift test` cannot compile: the watch app's
//  HealthKit store discards a workout it is not asked to save, and the app
//  declares the system's workout-recovery hook, which ends a workout a
//  force-quit left open through the same recovery the launch task runs. Plan
//  `docs/plans/2026-10-28-89-fitness-workouts-follow-the-session-plan/2026-10-28-89-fitness-workouts-follow-the-session-plan.md`,
//  scenario S-89-3 (decisions D-1 and D-3).
//
//  Every guard reads a file's text with its comment lines removed, so a
//  sentence of prose can neither satisfy a guard nor trip one. The governor's
//  watch app build is the compiler check.
//

import Foundation
import XCTest

final class WatchFitnessFollowsSessionSourceTests: XCTestCase {

    private func appSource(_ name: String) throws -> String {
        let url = Fixtures.repositoryRoot
            .appendingPathComponent("ios/OmniTrain Watch App/\(name)")
        let text = try String(contentsOf: url, encoding: .utf8)
        return strippingCommentLines(text)
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

    private func lines(_ source: String) -> [String] {
        source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private func occurrences(of needle: String, in source: String) -> Int {
        source.components(separatedBy: needle).count - 1
    }

    /// The brace-balanced body of the first line containing `needle`.
    private func braceBody(ofLineContaining needle: String, in source: String) -> String? {
        let all = lines(source)
        guard let start = all.firstIndex(where: { $0.contains(needle) }) else { return nil }
        var depth = 0
        var started = false
        var body: [String] = []
        for line in all[start...] {
            for character in line {
                if character == "{" {
                    depth += 1
                    started = true
                } else if character == "}" {
                    depth -= 1
                }
            }
            if started { body.append(line) }
            if started, depth == 0 { break }
        }
        return started ? body.joined(separator: "\n") : nil
    }

    // MARK: - S-89-3 (D-1) the store discards what it is not asked to save

    func testS89_3TheStoreDiscardsAndFinishesOnceEachAndFinishesOnlyWhenSaving() throws {
        let store = try appSource("HealthKitWorkoutStore.swift")

        XCTAssertEqual(occurrences(of: "discardWorkout()", in: store), 1, "S-89-3 the store calls discardWorkout once")
        XCTAssertEqual(occurrences(of: "finishWorkout()", in: store), 1, "S-89-3 the store calls finishWorkout once")

        let end = try XCTUnwrap(
            braceBody(ofLineContaining: "func end(saving: Bool)", in: store),
            "S-89-3 the store implements end(saving:)"
        )
        let body = lines(end)
        let ifSaving = try XCTUnwrap(
            body.firstIndex { $0.trimmingCharacters(in: .whitespaces) == "if saving {" },
            "S-89-3 end(saving:) branches on the flag"
        )
        let orElse = try XCTUnwrap(
            body[ifSaving...].firstIndex { $0.trimmingCharacters(in: .whitespaces) == "} else {" },
            "S-89-3 end(saving:) has a branch for a workout it does not save"
        )
        let finish = try XCTUnwrap(body.firstIndex { $0.contains("finishWorkout()") })
        let discard = try XCTUnwrap(body.firstIndex { $0.contains("discardWorkout()") })

        XCTAssertTrue(
            ifSaving < finish && finish < orElse,
            "S-89-3 finishWorkout is reachable only when saving"
        )
        XCTAssertGreaterThan(discard, orElse, "S-89-3 discardWorkout is the not-saving branch")
    }

    // MARK: - S-89-3 (D-3) the app declares the workout-recovery hook

    func testS89_3TheAppDeclaresTheWorkoutRecoveryDelegate() throws {
        let app = try appSource("OmniTrainApp.swift")

        XCTAssertTrue(app.contains("@WKApplicationDelegateAdaptor"), "S-89-3 the app installs an application delegate")
        XCTAssertTrue(app.contains("WKApplicationDelegate {"), "S-89-3 a class conforms to WKApplicationDelegate")
        let hook = try XCTUnwrap(
            braceBody(ofLineContaining: "func handleActiveWorkoutRecovery()", in: app),
            "S-89-3 the delegate implements handleActiveWorkoutRecovery"
        )
        XCTAssertTrue(
            hook.contains("host.recoverStrandedWorkout()"),
            "S-89-3 the hook runs the host's one recovery"
        )
        XCTAssertTrue(
            app.contains("ContentView(host: delegate.host)"),
            "S-89-3 the surface is handed the delegate's host, so there is one host, not two"
        )
        XCTAssertEqual(occurrences(of: "WatchAppHost()", in: app), 1, "S-89-3 the app builds one host")
    }

    func testS89_3TheLaunchAndTheHookShareOneRecoveryThatReadsTheStoredSession() throws {
        let view = try appSource("ContentView.swift")

        let recovery = try XCTUnwrap(
            braceBody(ofLineContaining: "func recoverStrandedWorkout() async", in: view),
            "S-89-3 the host has one recovery method"
        )
        XCTAssertTrue(
            recovery.contains("workout.recoverInProgress(storedSession:"),
            "S-89-3 the recovery is the coordinator's, told about the persisted session"
        )
        XCTAssertTrue(
            recovery.contains("engine.storedSession()"),
            "S-89-3 the persisted session is the engine's answer"
        )

        let restore = try XCTUnwrap(
            braceBody(ofLineContaining: "func restore() async", in: view),
            "S-89-3 the host carries the launch restore"
        )
        let recover = try XCTUnwrap(restore.range(of: "await recoverStrandedWorkout()"), "S-89-3 the launch runs the same recovery")
        let engine = try XCTUnwrap(restore.range(of: "await engine.restore()"))
        XCTAssertLessThan(
            recover.lowerBound,
            engine.lowerBound,
            "S-89-3 a stranded workout ends before a restored session can open one"
        )
        XCTAssertEqual(
            occurrences(of: "recoverInProgress(", in: view),
            1,
            "S-89-3 no second, divergent recovery call in the host"
        )
    }
}
