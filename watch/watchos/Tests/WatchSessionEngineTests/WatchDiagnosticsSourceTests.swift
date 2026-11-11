//
//  WatchDiagnosticsSourceTests.swift
//  WatchSessionEngineTests
//
//  Source guards for what `swift test` cannot compile: the watch app target
//  records launches, scene phases, reachability and reachability-link problems
//  into the one diagnostics log it builds, the platform radio notes its late
//  send refusals, and the Start screen opens the Diagnostics surface. Plan
//  `docs/plans/2026-11-10-142-diagnostics-log-plan/2026-11-10-142-diagnostics-log-plan.md`,
//  scenario S-14213 (decisions D-14204, D-14205, D-14206, D-14209, D-14210).
//
//  Every guard reads a file's text with its comment lines removed, so a
//  sentence of prose can neither satisfy a guard nor trip one. The governor's
//  watch app build is the compiler check.
//

import Foundation
import XCTest

#if canImport(SwiftUI)
import SwiftUI
#endif

final class WatchDiagnosticsSourceTests: XCTestCase {

    private func appSource(_ name: String) throws -> String {
        let url = Fixtures.repositoryRoot
            .appendingPathComponent("ios/OmniTrain Watch App/\(name)")
        let text = try String(contentsOf: url, encoding: .utf8)
        return strippingCommentLines(text)
    }

    private func packageSource(_ name: String) throws -> String {
        let url = Fixtures.repositoryRoot
            .appendingPathComponent("watch/watchos/Sources/WatchSessionEngine/\(name)")
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

    private func occurrences(of needle: String, in source: String) -> Int {
        source.components(separatedBy: needle).count - 1
    }

    // MARK: - S-14213 (D-14204) the launch and the recovery relaunch are recorded

    func testS14213TheAppNotesTheRecoveryRelaunch() throws {
        let app = try appSource("OmniTrainApp.swift")

        XCTAssertTrue(
            app.contains(#"host.diagnostics.note("recovery_relaunch")"#),
            "S-14213 the workout-recovery relaunch is recorded before the recovery runs"
        )
    }

    func testS14213TheHostBuildsTheLogOnceAndHandsItOn() throws {
        let view = try appSource("ContentView.swift")

        XCTAssertTrue(
            view.contains("diagnostics.noteLaunch()"),
            "S-14213 the launch is recorded when the host is built"
        )
        XCTAssertGreaterThanOrEqual(
            occurrences(of: "diagnostics: diagnostics)", in: view),
            3,
            "S-14213 the one log is handed to the radio halves, the engine and the platform workout"
        )
        XCTAssertTrue(
            view.contains("WatchPlatformWorkout(store: healthStore, diagnostics: diagnostics)"),
            "S-14213 the platform workout notes into the same log"
        )
    }

    // MARK: - S-14213 (D-14205, D-14209) the scene phases and the link are recorded

    func testS14213TheHostNotesReachabilityLinkProblemAndScene() throws {
        let view = try appSource("ContentView.swift")

        XCTAssertTrue(
            view.contains(#"self.diagnostics.note("reachability", detail: reachable ? "reachable" : "unreachable")"#),
            "S-14213 every reachability answer is recorded"
        )
        XCTAssertTrue(
            view.contains(#"self?.diagnostics.note("link_problem", detail: problem ? "true" : "false")"#),
            "S-14213 the link-problem report is recorded"
        )
        XCTAssertTrue(
            view.contains(#"host.diagnostics.note("scene", detail: "\(phase)")"#),
            "S-14213 every scene phase, not only .active, is recorded"
        )
    }

    /// S-14213 the scene note runs for every phase: it stands as the handler's
    /// first statement, before the `.active` branch, in the actual layout.
    func testS14213TheSceneNoteIsTheFirstStatementOfTheScenePhaseHandler() throws {
        let view = try appSource("ContentView.swift")
        let expected = [
            "        .onChange(of: scenePhase) { _, phase in",
            #"            host.diagnostics.note("scene", detail: "\(phase)")"#,
            "            if phase == .active {",
        ].joined(separator: "\n")

        XCTAssertTrue(
            view.contains(expected),
            "S-14213 every scene phase is noted, not only the .active branch"
        )
    }

    // MARK: - S-14213 (D-14210) the Start screen opens the Diagnostics surface

    func testS14213TheStartScreenOpensTheDiagnosticsSurface() throws {
        let view = try appSource("ContentView.swift")
        let start = try packageSource("WatchStartView.swift")

        XCTAssertTrue(
            view.contains("onOpenDiagnostics: { showingDiagnostics = true }"),
            "S-14213 the host hands the Start screen the sheet's opening"
        )
        XCTAssertTrue(
            view.contains("WatchDiagnosticsView(log: host.diagnostics, onSend: { url in host.sendDiagnostics(url) })"),
            "S-14213 the sheet shows the host's own log"
        )
        XCTAssertTrue(
            start.contains("if let onOpenDiagnostics {"),
            "S-14213 the button is there only when the app asks for it"
        )
        XCTAssertTrue(
            start.contains("Button(Self.diagnosticsLabel, action: onOpenDiagnostics)"),
            "S-14213 the button opens the diagnostics"
        )
        XCTAssertTrue(
            start.contains(#"static let diagnosticsLabel = "Diagnostics""#),
            "S-14213 the button carries its label from the one constant"
        )
        XCTAssertTrue(
            start.contains("self.onOpenDiagnostics = onOpenDiagnostics"),
            "S-14213 the init keeps the closure"
        )
    }

    // MARK: - S-14213 (D-14206) the platform's late refusal is recorded

    // MARK: - S-14213 the scene phase interpolates to its bare case name

#if canImport(SwiftUI)
    /// S-14213 the scene note's detail is `"\(phase)"`: SwiftUI interpolates
    /// a `ScenePhase` to its bare case name, the word the summary maps.
    func testS14213TheScenePhaseInterpolatesToItsBareCaseName() {
        XCTAssertEqual("\(ScenePhase.active)", "active", "S-14213 the active phase's word")
        XCTAssertEqual("\(ScenePhase.inactive)", "inactive", "S-14213 the inactive phase's word")
        XCTAssertEqual("\(ScenePhase.background)", "background", "S-14213 the background phase's word")
    }
#endif

    func testS14213TheRadioNotesTheLateRefusal() throws {
        let radio = try appSource("OmniTrainWatchConnectivity.swift")

        XCTAssertTrue(
            radio.contains("self.diagnostics?.note("),
            "S-14213 the radio notes into the optional log"
        )
        XCTAssertTrue(
            radio.contains(#""frame_send_refused""#),
            "S-14213 the late refusal's kind is frame_send_refused"
        )
    }
}
