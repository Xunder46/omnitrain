//
//  WatchSheetSoliditySourceTests.swift
//  WatchSessionEngineTests
//
//  S-22301, S-22302, S-22303, S-22304, S-22306, S-22312 of
//  `docs/plans/2026-11-17-223-watch-solid-popups-and-clock-clearance-plan.md`,
//  phase P1 (decisions D-22301, D-22302, D-22308, D-22309, D-22314, D-22315):
//  every wrist sheet wears the one solid backdrop, and the Finish and Discard
//  questions are the menu sheet's own screens, not system alerts.
//
//  Source scans, like the other wrist view guards: the watch target's views are
//  compiled only by the watch scheme, so `swift test` can hold their shape but
//  not run them; the drawn sheet is the owner's device check. Comment lines are
//  stripped, so prose can neither satisfy a guard nor trip one.
//

import Foundation
import XCTest

@testable import WatchSessionEngine

final class WatchSheetSoliditySourceTests: XCTestCase {

    // MARK: - S-22301 every sheet wears the solid backdrop exactly once

    func testS22301EverySheetWearsTheSolidBackdropOnce() throws {
        let startLines = sourceLines(
            try solidSource("watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift")
        )
        for picker in ["WatchExercisePickerView", "WatchPlannedPickerView"] {
            let body = try XCTUnwrap(
                bodyBlock(ofStruct: "struct \(picker)", in: startLines),
                "S-22301 \(picker) has a body"
            )
            XCTAssertEqual(
                body.filter { $0.trimmingCharacters(in: .whitespaces) == ".solidSheetBackground()" }.count,
                1,
                "S-22301 \(picker)'s sheet content wears the solid backdrop exactly once"
            )
        }

        let menuLines = sourceLines(
            try solidSource("watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift")
        )
        let menuBody = try XCTUnwrap(
            block(from: "public var body:", in: menuLines),
            "S-22301 the menu view has a body"
        )
        XCTAssertEqual(
            menuBody.filter { $0.trimmingCharacters(in: .whitespaces) == ".solidSheetBackground()" }.count,
            1,
            "S-22301 the menu's sheet content wears the solid backdrop exactly once"
        )

        let shellLines = sourceLines(try solidSource("ios/OmniTrain Watch App/ContentView.swift"))
        XCTAssertEqual(
            occurrences(of: ".solidSheetBackground()", in: shellLines.joined(separator: "\n")),
            2,
            "S-22301 the shell's food and diagnostics sheets are the two backdrop sites"
        )
        for (sheetMarker, contentMarker) in [
            (".sheet(isPresented: $showingFood)", "WatchNutritionView("),
            (".sheet(isPresented: $showingDiagnostics)", "WatchDiagnosticsView("),
        ] {
            let sheet = try XCTUnwrap(
                shellLines.firstIndex { $0.contains(sheetMarker) },
                "S-22301 the shell has its \(sheetMarker) sheet"
            )
            XCTAssertTrue(
                shellLines[sheet + 1].trimmingCharacters(in: .whitespaces) == "NavigationStack {",
                "S-22301 the sheet's content opens its own NavigationStack"
            )
            XCTAssertTrue(
                shellLines[sheet + 2].contains(contentMarker),
                "S-22301 the sheet shows \(contentMarker)"
            )
            XCTAssertTrue(
                shellLines[sheet + 3].trimmingCharacters(in: .whitespaces) == "}",
                "S-22301 the NavigationStack closes before the backdrop"
            )
            XCTAssertTrue(
                shellLines[sheet + 4].trimmingCharacters(in: .whitespaces) == ".solidSheetBackground()",
                "S-22301 the backdrop sits directly on the sheet's root content"
            )
        }

        let backdrop = try solidSource("watch/watchos/Sources/WatchSessionEngine/WatchSheetBackground.swift")
        XCTAssertEqual(
            occurrences(of: "content.presentationBackground(Self.color)", in: backdrop),
            1,
            "S-22301 the 9.4+ path colours the sheet's own backdrop"
        )
        XCTAssertEqual(
            occurrences(of: "content.background(Self.color, ignoresSafeAreaEdges: .all)", in: backdrop),
            1,
            "S-22301 the floor paints the content's own background"
        )
        XCTAssertEqual(
            occurrences(of: "static let color = Color.black", in: backdrop),
            1,
            "S-22301 one place decides the colour"
        )
        XCTAssertEqual(
            occurrences(of: "if #available(watchOS 9.4, *) {", in: backdrop),
            1,
            "S-22301 the newer API sits behind one availability branch"
        )
    }

    // MARK: - S-22302 no menu question is a system alert

    func testS22302NoMenuQuestionIsASystemAlert() throws {
        let source = try solidSource("watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift")
        let lines = sourceLines(source)

        XCTAssertFalse(
            source.contains(".alert("),
            "S-22302 no menu question is a system alert"
        )

        let finish = try XCTUnwrap(
            block(from: "private var finishQuestion", in: lines),
            "S-22302 the menu has a finishQuestion"
        )
        XCTAssertTrue(
            finish.contains { $0.trimmingCharacters(in: .whitespaces) == "Button(WatchMenuCopy.confirmFinish) {" },
            "S-22302 the Finish question carries the Finish answer"
        )
        XCTAssertFalse(
            finish.contains { $0.contains("role: .destructive") },
            "S-22302 Finish never looks destructive"
        )

        let discard = try XCTUnwrap(
            block(from: "private var discardQuestion", in: lines),
            "S-22302 the menu has a discardQuestion"
        )
        XCTAssertTrue(
            discard.contains {
                $0.trimmingCharacters(in: .whitespaces)
                    == "Button(WatchMenuCopy.discardConfirmDiscard, role: .destructive) {"
            },
            "S-22302 the Discard question's Discard is destructive"
        )

        let body = try XCTUnwrap(
            block(from: "public var body:", in: lines),
            "S-22302 the menu has a body"
        )
        var index = 0
        for step in [
            "if confirmingFinish {",
            "finishQuestion",
            "} else if confirmingDiscard {",
            "discardQuestion",
            "} else {",
            "menu",
        ] {
            let at = try XCTUnwrap(
                body[index...].firstIndex { $0.trimmingCharacters(in: .whitespaces) == step },
                "S-22302 the body shows \(step) in the question-first order"
            )
            XCTAssertGreaterThan(at, 0, "S-22302 \(step) is inside the body")
            index = at + 1
        }
    }

    // MARK: - S-22303 the accent still wraps the sheets

    func testS22303TheAccentStillWrapsTheSheets() throws {
        let shellLines = sourceLines(try solidSource("ios/OmniTrain Watch App/ContentView.swift"))

        let accent = try XCTUnwrap(
            shellLines.lastIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix(".environment(\\.watchAccent,") },
            "S-22303 the shell sets the watch accent"
        )
        let lastSheet = try XCTUnwrap(
            shellLines.lastIndex { $0.contains(".sheet(isPresented:") },
            "S-22303 the shell presents sheets"
        )
        let lastBackdrop = try XCTUnwrap(
            shellLines.lastIndex { $0.trimmingCharacters(in: .whitespaces) == ".solidSheetBackground()" },
            "S-22303 the shell carries the backdrop sites"
        )
        XCTAssertGreaterThan(accent, lastSheet, "S-22303 the accent wraps every sheet")
        XCTAssertGreaterThan(accent, lastBackdrop, "S-22303 the accent wraps the backdrop sites too")

        let backdrop = try solidSource("watch/watchos/Sources/WatchSessionEngine/WatchSheetBackground.swift")
        XCTAssertFalse(backdrop.contains(".tint("), "S-22303 the backdrop sets no tint of its own")
        XCTAssertFalse(backdrop.contains("watchAccent"), "S-22303 the backdrop reads no accent of its own")
    }

    // MARK: - S-22304 the Finish question runs the end in order

    func testS22304TheFinishQuestionRunsTheEndInOrder() throws {
        let lines = sourceLines(
            try solidSource("watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift")
        )
        let question = try XCTUnwrap(
            block(from: "private var finishQuestion", in: lines),
            "S-22304 the menu has a finishQuestion"
        )

        let finishButton = try XCTUnwrap(
            question.firstIndex { $0.trimmingCharacters(in: .whitespaces) == "Button(WatchMenuCopy.confirmFinish) {" },
            "S-22304 the question carries the Finish answer"
        )
        let cancelButton = try XCTUnwrap(
            question.firstIndex {
                $0.trimmingCharacters(in: .whitespaces) == "Button(WatchMenuCopy.confirmCancel, role: .cancel) {"
            },
            "S-22304 the question carries Cancel"
        )
        let tap = try XCTUnwrap(
            question.firstIndex { $0.contains("haptics.playFinished()") },
            "S-22304 the Finish tap confirms the choice"
        )
        let end = try XCTUnwrap(
            question.firstIndex { $0.contains("await state.finish()") },
            "S-22304 the rating state's end runs"
        )
        let back = try XCTUnwrap(
            question.firstIndex { $0.contains("onFinish()") },
            "S-22304 and the surface is handed back"
        )
        XCTAssertGreaterThan(tap, finishButton, "S-22304 the order belongs to the Finish answer")
        XCTAssertGreaterThan(end, tap, "S-22304 the tap comes before the end (D-3402)")
        XCTAssertGreaterThan(back, end, "S-22304 the end comes before the hand-back")
        XCTAssertLessThan(back, cancelButton, "S-22304 and all before Cancel is reached")
        XCTAssertEqual(
            question[cancelButton + 1].trimmingCharacters(in: .whitespaces),
            "confirmingFinish = false",
            "S-22304 Cancel only puts the menu back"
        )
    }

    // MARK: - S-22306 the question lives inside the menu sheet

    func testS22306TheQuestionLivesInsideTheMenuSheet() throws {
        let shellLines = sourceLines(try solidSource("ios/OmniTrain Watch App/ContentView.swift"))
        XCTAssertTrue(
            shellLines.contains {
                $0.trimmingCharacters(in: .whitespaces) == "if status != WatchSessionStatus.active { showingMenu = false }"
            },
            "S-22306 the sheet closes itself when the session ends"
        )
        XCTAssertTrue(
            shellLines.contains { $0.trimmingCharacters(in: .whitespaces) == "if owed { showingMenu = false }" },
            "S-22306 and when a rating is owed"
        )

        let shell = shellLines.joined(separator: "\n")
        XCTAssertFalse(shell.contains(".alert("), "S-22306 the shell raises no system alert")
        XCTAssertFalse(
            shell.contains("WatchMenuConfirmationView"),
            "S-22306 no code path presents the question outside the menu sheet"
        )

        let menuLines = sourceLines(
            try solidSource("watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift")
        )
        XCTAssertTrue(
            menuLines.contains {
                $0.trimmingCharacters(in: .whitespaces) == "private struct WatchMenuConfirmationView<Answers: View>: View {"
            },
            "S-22306 the question is the menu sheet's own private view"
        )
    }

    // MARK: - S-22312 one question at a time

    func testS22312OneQuestionAtATime() throws {
        let lines = sourceLines(
            try solidSource("watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift")
        )

        let finish = try XCTUnwrap(
            block(from: "private var finishRow", in: lines),
            "S-22312 the menu has a finishRow"
        )
        let rule = try XCTUnwrap(
            finish.firstIndex { $0.trimmingCharacters(in: .whitespaces) == "if state.hasWorkToSave {" },
            "S-22312 End reads the save rule"
        )
        let raiseFinish = try XCTUnwrap(
            finish.firstIndex { $0.trimmingCharacters(in: .whitespaces) == "confirmingFinish = true" },
            "S-22312 the Finish question is raised"
        )
        let elseArm = try XCTUnwrap(
            finish.firstIndex { $0.trimmingCharacters(in: .whitespaces) == "} else {" },
            "S-22312 the rule has two arms"
        )
        let raiseDiscard = try XCTUnwrap(
            finish.firstIndex { $0.trimmingCharacters(in: .whitespaces) == "confirmingDiscard = true" },
            "S-22312 and an empty End raises the discard question"
        )
        XCTAssertGreaterThan(raiseFinish, rule, "S-22312 the Finish flag belongs to the then arm")
        XCTAssertGreaterThan(elseArm, raiseFinish, "S-22312 the arms are exclusive")
        XCTAssertGreaterThan(raiseDiscard, elseArm, "S-22312 the discard flag belongs to the else arm")
        // Lead, mutation pass: an else arm that also raised the Finish flag kept
        // every index check above green, so each flag is raised exactly once.
        XCTAssertEqual(
            finish.filter { $0.trimmingCharacters(in: .whitespaces) == "confirmingFinish = true" }.count,
            1,
            "S-22312 End raises the Finish question from one arm only"
        )
        XCTAssertEqual(
            finish.filter { $0.trimmingCharacters(in: .whitespaces) == "confirmingDiscard = true" }.count,
            1,
            "S-22312 End raises the discard question from one arm only"
        )

        let discard = try XCTUnwrap(
            block(from: "private var discardRow", in: lines),
            "S-22312 the menu has a discardRow"
        )
        XCTAssertTrue(
            discard.contains { $0.trimmingCharacters(in: .whitespaces) == "confirmingDiscard = true" },
            "S-22312 the Discard row raises the discard question"
        )
        XCTAssertFalse(
            discard.contains { $0.contains("confirmingFinish") },
            "S-22312 the Discard row raises only the discard question"
        )

        let source = lines.joined(separator: "\n")
        XCTAssertEqual(
            occurrences(of: "WatchMenuConfirmationView(", in: source),
            2,
            "S-22312 one shared layout names exactly one question per call site"
        )
    }

    // MARK: - Helpers (copied from WatchMenuTests)

    /// A repository file, read from `Fixtures.repositoryRoot`, with every comment
    /// line blanked out, so a sentence of prose can neither satisfy a guard nor
    /// trip one. A trailing `//` on a code line is blanked with it; the guarded
    /// files keep no `//` inside a string literal.
    private func solidSource(_ path: String) throws -> String {
        let url = Fixtures.repositoryRoot.appendingPathComponent(path)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { return "" }
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    private func sourceLines(_ source: String) -> [String] {
        source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    /// How many times `needle` occurs in `source`.
    private func occurrences(of needle: String, in source: String) -> Int {
        source.components(separatedBy: needle).count - 1
    }

    /// The lines from the first line containing `marker` through the brace that
    /// closes the block it opens, or nil when the file carries no such marker.
    private func block(from marker: String, in lines: [String]) -> [String]? {
        guard let start = lines.firstIndex(where: { $0.contains(marker) }) else {
            return nil
        }

        var depth = 0
        var block: [String] = []
        for line in lines[start...] {
            block.append(line)
            depth += line.filter { $0 == "{" }.count - line.filter { $0 == "}" }.count
            if depth == 0, block.count > 1 { return block }
        }
        return nil
    }

    /// The `var body:` block inside the struct `marker` names.
    private func bodyBlock(ofStruct marker: String, in lines: [String]) -> [String]? {
        guard let structLines = block(from: marker, in: lines) else { return nil }
        return block(from: "var body:", in: structLines)
    }
}
