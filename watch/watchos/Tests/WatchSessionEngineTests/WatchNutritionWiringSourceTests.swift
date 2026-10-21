//
//  WatchNutritionWiringSourceTests.swift
//  WatchSessionEngineTests
//
//  Source guards for the watch app's way into the food quick-log: the host owns
//  the quick-log's state and restores it, the start screen opens the surface,
//  and the session menu carries the same row between Add Exercise and End
//  Session.
//
//  Plan: `docs/plans/2026-10-21-49b-wrist-food-logging-reachable-plan/2026-10-21-49b-wrist-food-logging-reachable-plan.md`,
//  scenarios S-7201, S-7202, S-7203 and S-7205 (decisions D-1, D-2, D-3).
//
//  The app target has no test target and the views compile only under
//  xcodebuild, so what `swift test` can hold is the text the wiring is made of.
//  `WatchMenuCopy` is platform-independent, so the copy half (S-7202) is
//  executable here; `WatchStartView` is watchOS-only and is therefore read from
//  its source, compared against the package's own constant.
//
//  Every guard reads a file's text with its comment lines removed, so a sentence
//  of prose can neither satisfy a guard nor trip one.
//

import Foundation
import XCTest

import WatchSessionEngine

final class WatchNutritionWiringSourceTests: XCTestCase {

    // MARK: - Reading the two targets

    /// A file of the app target, read from the repository root, with every
    /// comment-only line blanked out (the line count is kept).
    private func appSource(_ name: String) throws -> String {
        let url = Fixtures.repositoryRoot
            .appendingPathComponent("ios/OmniTrain Watch App/\(name)")
        let text = try String(contentsOf: url, encoding: .utf8)
        return strippingCommentLines(text)
    }

    /// A file of the watch package's engine module, read the same way.
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

    // MARK: - Matching helpers

    /// The lines of `source`.
    private func sourceLines(_ source: String) -> [String] {
        source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    /// How many times `needle` occurs in `source`.
    private func occurrences(of needle: String, in source: String) -> Int {
        source.components(separatedBy: needle).count - 1
    }

    /// The brace-balanced body of the first line containing `needle`, from its
    /// opening brace to its closing one, or nil when that line is not there.
    private func braceBody(ofLineContaining needle: String, in source: String) -> String? {
        let lines = sourceLines(source)
        guard let start = lines.firstIndex(where: { $0.contains(needle) }) else {
            return nil
        }

        var depth = 0
        var started = false
        var body: [String] = []
        for line in lines[start...] {
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

    /// The parenthesis-balanced argument list of the first call to `name(`, from
    /// its opening parenthesis to its closing one, or nil when the call is not
    /// there. A multi-line call's arguments span several lines, so the statement
    /// form `braceBody` reads does not fit them.
    private func callBody(of name: String, in source: String) -> String? {
        let lines = sourceLines(source)
        guard let start = lines.firstIndex(where: { $0.contains("\(name)(") }) else {
            return nil
        }

        var depth = 0
        var started = false
        var body: [String] = []
        for line in lines[start...] {
            for character in line {
                if character == "(" {
                    depth += 1
                    started = true
                } else if character == ")" {
                    depth -= 1
                }
            }
            if started { body.append(line) }
            if started, depth == 0 { return body.joined(separator: "\n") }
        }
        return nil
    }

    /// A line of `source` whose trimmed text is exactly `text`: the use of a row
    /// builder, not its declaration, which carries a signature after the name.
    private func usageLine(of text: String, in source: String) -> Int? {
        sourceLines(source).firstIndex { $0.trimmingCharacters(in: .whitespaces) == text }
    }

    // MARK: - S-7201: the host owns the quick-log's state

    /// One `WatchNutritionState` for the life of the app, built over the same
    /// engine and store as everything else (D-1): the host keeps it, hands it to
    /// the orchestrator so a `foods_down` lands, and restores it on launch. The
    /// start screen opens the surface through `onOpenNutrition`, and the sheet's
    /// body is the one quick-log view.
    func testS7201TheHostOwnsTheNutritionStateAndRestoresIt() throws {
        let view = try appSource("ContentView.swift")

        XCTAssertEqual(
            occurrences(of: "WatchNutritionState(", in: view),
            1,
            "S-7201 one quick-log state serves the app's life, like the logging and rating states"
        )

        let orchestrator = try XCTUnwrap(
            callBody(of: "WatchSyncOrchestrator", in: view),
            "S-7201 the host builds the orchestrator"
        )
        XCTAssertTrue(
            orchestrator.contains("nutrition: nutrition"),
            "S-7201 the orchestrator is handed the quick-log state, or a foods_down is stored nowhere"
        )

        let restore = try XCTUnwrap(
            braceBody(ofLineContaining: "func restore() async", in: view),
            "S-7201 the host has a restore path"
        )
        XCTAssertTrue(
            restore.contains("await nutrition.restore()"),
            "S-7201 a relaunch reads back the food list the phone last sent"
        )

        XCTAssertTrue(
            view.contains("onOpenNutrition:"),
            "S-7201 the start screen is given the way into the quick-log (D-2)"
        )
        XCTAssertTrue(
            view.contains("WatchNutritionView("),
            "S-7201 the surface the start screen opens is the existing quick-log view"
        )

        let menu = try XCTUnwrap(
            callBody(of: "WatchMenuView", in: view),
            "S-7201 the shell hosts the session menu"
        )
        XCTAssertTrue(
            menu.contains("nutrition: host.nutrition"),
            "S-7201 the menu is handed the same state, so its row pushes the same quick-log (D-3)"
        )
    }

    // MARK: - S-7202: the menu's words are the start screen's

    /// The menu row says what the start screen's button says, and the start
    /// screen's constant is the same words: two surfaces, one phrase (D-3).
    func testS7202TheLogFoodCopyIsTheStartScreens() throws {
        XCTAssertEqual(
            WatchMenuCopy.logFoodLabel,
            "Log food",
            "S-7202 the menu's way into the quick-log is named as the start screen names it"
        )

        let start = try engineSource("WatchStartView.swift")
        XCTAssertTrue(
            start.contains("public static let logFoodLabel = \"Log food\""),
            "S-7202 WatchStartView.logFoodLabel carries the same words, so the two cannot drift"
        )
    }

    // MARK: - S-7203: the row sits between Add Exercise and End Session

    /// The menu's Log food row is a `NavigationLink` to the quick-log, labelled
    /// with the shared copy, placed after Add Exercise and before End Session and
    /// never disabled: eating is independent of the effort being logged (D-3).
    func testS7203TheMenuRowSitsBetweenAddExerciseAndFinish() throws {
        let source = try engineSource("WatchMenuView.swift")

        XCTAssertTrue(
            source.contains("nutrition: WatchNutritionState? = nil"),
            "S-7203 the state is optional, so a menu without one keeps the row off (D-3)"
        )

        let add = try XCTUnwrap(
            usageLine(of: "addExerciseRow", in: source),
            "S-7203 the menu carries the Add Exercise row"
        )
        let food = try XCTUnwrap(
            usageLine(of: "logFoodRow", in: source),
            "S-7203 the menu carries the Log food row"
        )
        let finish = try XCTUnwrap(
            usageLine(of: "finishRow", in: source),
            "S-7203 the menu carries the End Session row"
        )

        XCTAssertLessThan(add, food, "S-7203 Log food comes after Add Exercise")
        XCTAssertLessThan(food, finish, "S-7203 and before End Session")

        let row = try XCTUnwrap(
            braceBody(ofLineContaining: "private var logFoodRow", in: source),
            "S-7203 the row is the view's own property"
        )
        XCTAssertTrue(
            row.contains("NavigationLink {"),
            "S-7203 the row pushes the quick-log the way Add Exercise pushes its list"
        )
        XCTAssertTrue(
            row.contains("WatchNutritionView(model: WatchNutritionModel(state: nutrition))"),
            "S-7203 the destination is the existing quick-log view over the host's state"
        )
        XCTAssertTrue(
            row.contains("Text(WatchMenuCopy.logFoodLabel)"),
            "S-7203 the label is the shared copy, not a second literal"
        )
        XCTAssertFalse(
            row.contains(".disabled("),
            "S-7203 the row is never disabled: food is independent of the effort"
        )
    }

    // MARK: - S-7205: Log food sits right under Free workout

    /// On the start screen the Log food button comes directly after Free
    /// workout and before Sync, so it is above the fold rather than behind a
    /// rarely used row.
    func testS7205LogFoodSitsRightUnderFreeWorkout() throws {
        let start = try engineSource("WatchStartView.swift")

        let free = try XCTUnwrap(
            sourceLines(start).firstIndex { $0.contains("Button(\"Free workout\")") },
            "S-7205 the start screen carries the Free workout button"
        )
        let food = try XCTUnwrap(
            sourceLines(start).firstIndex { $0.contains("if let onOpenNutrition") },
            "S-7205 the start screen carries the Log food button"
        )
        let sync = try XCTUnwrap(
            sourceLines(start).firstIndex { $0.contains("Self.syncLabel") },
            "S-7205 the start screen carries the Sync button"
        )

        XCTAssertLessThan(free, food, "S-7205 Log food comes right after Free workout")
        XCTAssertLessThan(food, sync, "S-7205 and before Sync")
    }
}
