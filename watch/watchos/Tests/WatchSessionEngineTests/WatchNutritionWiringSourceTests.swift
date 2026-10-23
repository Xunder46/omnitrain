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
//  scenarios S-7201, S-7202, S-7203 and S-7205 (decisions D-1, D-2, D-3), and
//  `docs/plans/2026-10-22-53-watch-food-screen-and-fresh-foods-plan/2026-10-22-53-watch-food-screen-and-fresh-foods-plan.md`,
//  scenarios S-8311, S-8312 and S-8318 (decisions D-4, D-5, D-6, D-10).
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
            menu.contains("nutritionModel: host.nutritionModel"),
            "S-7201 the menu is handed the same model, so its row pushes the same quick-log (D-3, D-10)"
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
            source.contains("nutritionModel: WatchNutritionModel? = nil"),
            "S-7203 the model is optional, so a menu without one keeps the row off (D-3, D-10)"
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
            row.contains("WatchNutritionView(model: nutritionModel)"),
            "S-7203 the destination is the existing quick-log view over the handed model"
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

    // MARK: - S-8311: the host owns one model, and the sheet uses it

    /// `ContentView.swift` builds the quick-log's model once, in the host, and
    /// the sheet presents the surface over that model. A model built on every
    /// body evaluation would reset the crown and drop the state's change
    /// observer, which is what redraws an open surface (D-4, D-6).
    func testS8311TheHostOwnsTheOneNutritionModel() throws {
        let view = try appSource("ContentView.swift")

        XCTAssertEqual(
            occurrences(of: "WatchNutritionModel(", in: view),
            1,
            "S-8311 the app builds one model for its life"
        )

        let hostInit = try XCTUnwrap(
            braceBody(ofLineContaining: "init() {", in: view),
            "S-8311 the host has a construction path"
        )
        XCTAssertTrue(
            hostInit.contains("let nutritionModel = WatchNutritionModel(state: nutrition)"),
            "S-8311 the model is built in the host, beside the state it observes"
        )

        let content = try XCTUnwrap(
            braceBody(ofLineContaining: "struct ContentView: View", in: view),
            "S-8311 the shell is the view the sheet is applied to"
        )
        XCTAssertFalse(
            content.contains("WatchNutritionModel("),
            "S-8311 no view body builds a model of its own"
        )
        XCTAssertTrue(
            content.contains("WatchNutritionView(model: host.nutritionModel)"),
            "S-8311 the sheet presents the surface over the host's one model"
        )
    }

    // MARK: - S-8312: the list lists, the food screen edits

    /// The quick-log's list carries the foods and the empty state alone; the
    /// portion row, Log and the confirmation live on the pushed food screen, and
    /// the push follows the selection, whose dismissal deselects (D-4, D-5).
    func testS8312TheListIsTheListAndTheFoodScreenEdits() throws {
        let source = try engineSource("WatchNutritionView.swift")

        let list = try XCTUnwrap(
            braceBody(ofLineContaining: "public struct WatchNutritionView: View", in: source),
            "S-8312 the quick-log's list view is the surface's entry"
        )
        XCTAssertFalse(list.contains("portionRow"), "S-8312 the list does not draw the portion row")
        XCTAssertFalse(list.contains("logButton"), "S-8312 the list does not draw the Log button")
        XCTAssertTrue(
            list.contains("navigationDestination(isPresented:"),
            "S-8312 the list pushes the food screen"
        )
        XCTAssertTrue(
            list.contains("model.isShowingFood"),
            "S-8312 the push follows the selection"
        )

        let foodScreen = try XCTUnwrap(
            braceBody(ofLineContaining: "struct WatchFoodPortionView: View", in: source),
            "S-8312 the food screen exists"
        )
        XCTAssertTrue(
            foodScreen.contains("portionRow"),
            "S-8312 the food screen draws the portion row"
        )
        XCTAssertTrue(
            foodScreen.contains("logButton"),
            "S-8312 the food screen draws the Log button"
        )
        XCTAssertTrue(
            foodScreen.contains("Text(confirmation)"),
            "S-8312 the confirmation line is the food screen's"
        )

        let model = try XCTUnwrap(
            braceBody(ofLineContaining: "public final class WatchNutritionModel", in: source),
            "S-8312 the surface's model exists"
        )
        XCTAssertTrue(
            model.contains("state.deselect()"),
            "S-8312 leaving the food screen clears the selection"
        )

        let dismiss = try XCTUnwrap(
            braceBody(ofLineContaining: "public func deselect()", in: source),
            "S-8312 the model carries its own dismiss"
        )
        XCTAssertTrue(
            dismiss.contains("crownPosition = 0"),
            "S-8312 the crown starts over with the next food"
        )
    }

    // MARK: - S-8318: the menu pushes the host's model

    /// The session menu carries the host's model instead of building one, so a
    /// `foods_down` that lands while the menu's quick-log is open redraws it and
    /// the crown survives a body evaluation (D-10).
    func testS8318TheMenuPushesTheHostsNutritionModel() throws {
        let source = try engineSource("WatchMenuView.swift")

        XCTAssertEqual(
            occurrences(of: "WatchNutritionModel(", in: source),
            0,
            "S-8318 the menu builds no model of its own"
        )

        let row = try XCTUnwrap(
            braceBody(ofLineContaining: "private var logFoodRow", in: source),
            "S-8318 the menu carries the Log food row"
        )
        XCTAssertTrue(
            row.contains("WatchNutritionView(model: nutritionModel)"),
            "S-8318 the row pushes the quick-log over the handed model"
        )

        let view = try appSource("ContentView.swift")
        let menu = try XCTUnwrap(
            callBody(of: "WatchMenuView", in: view),
            "S-8318 the shell opens the menu"
        )
        XCTAssertTrue(
            menu.contains("nutritionModel: host.nutritionModel"),
            "S-8318 the menu is handed the host's one model"
        )
    }
}
