//
//  WatchWaterBarSourceTests.swift
//  WatchSessionEngineTests
//
//  Phase 4 of `docs/plans/2026-11-01-95-watch-water-bar-plan/`: the water bar
//  on the wrist's Nutrition screen, the host that owns its state and model, and
//  the rule on which taps may be pruned. Scenarios S-94b-22 to S-94b-24
//  (decisions D-31 to D-35). Plan 96
//  (`docs/plans/2026-11-01-96-watch-water-follow-up-plan/`) adds S-94c-5: the
//  bar reads one snapshot per redraw (D-42); and S-94b-25a replaces S-94b-25:
//  D-43 (supersedes D-37) lets only the launch prune old confirmed taps.
//
//  The bar and the host compile only for watchOS, so what `swift test` can hold
//  is the text they are made of. Every guard reads a file with its comment
//  lines removed, so prose can neither satisfy a guard nor trip one. The
//  comment-stripping helper is copied from `WatchNutritionWiringSourceTests`,
//  not shared, as the plan asks.
//

import Foundation
import XCTest

final class WatchWaterBarSourceTests: XCTestCase {

    // MARK: - Reading the two targets

    private static let appDirectory = "ios/OmniTrain Watch App"

    /// A file of the app target, comments stripped.
    private func appSource(_ name: String) throws -> String {
        let url = Fixtures.repositoryRoot
            .appendingPathComponent("\(Self.appDirectory)/\(name)")
        return strippingCommentLines(try String(contentsOf: url, encoding: .utf8))
    }

    /// A file of the watch package's engine module, comments stripped.
    private func engineSource(_ name: String) throws -> String {
        let url = Fixtures.sourcesRoot.appendingPathComponent(name)
        return strippingCommentLines(try String(contentsOf: url, encoding: .utf8))
    }

    /// Every Swift file of the engine module and of the app target, by name,
    /// comments stripped.
    private func everySource() throws -> [(name: String, text: String)] {
        let directories = [
            Fixtures.sourcesRoot,
            Fixtures.repositoryRoot.appendingPathComponent(Self.appDirectory),
        ]
        var files: [(name: String, text: String)] = []
        for directory in directories {
            let urls = try FileManager.default
                .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "swift" }
            for url in urls {
                let text = try String(contentsOf: url, encoding: .utf8)
                files.append((url.lastPathComponent, strippingCommentLines(text)))
            }
        }
        return files
    }

    /// Blanks every line whose trimmed text starts with `//`, and the trailing
    /// `//` comment of a code line, keeping the line boundaries.
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

    private func sourceLines(_ source: String) -> [String] {
        source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private func occurrences(of needle: String, in source: String) -> Int {
        source.components(separatedBy: needle).count - 1
    }

    /// The brace-balanced body of the first line containing `needle`, or nil.
    private func braceBody(ofLineContaining needle: String, in source: String) -> String? {
        let lines = sourceLines(source)
        guard let start = lines.firstIndex(where: { $0.contains(needle) }) else { return nil }
        return braceBlock(from: start, in: lines).map { lines[start...$0].joined(separator: "\n") }
    }

    /// The index of the line that closes the brace block opened on `start`.
    private func braceBlock(from start: Int, in lines: [String]) -> Int? {
        var depth = 0
        var started = false
        for index in start..<lines.count {
            for character in lines[index] {
                if character == "{" {
                    depth += 1
                    started = true
                } else if character == "}" {
                    depth -= 1
                }
            }
            if started, depth == 0 { return index }
        }
        return nil
    }

    /// The parenthesis-balanced argument list of the first call to `name(`.
    private func callBody(of name: String, in source: String) -> String? {
        let lines = sourceLines(source)
        guard let start = lines.firstIndex(where: { $0.contains("\(name)(") }) else { return nil }
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

    /// The offset of the first `needle` in `source`, or nil.
    private func offset(of needle: String, in source: String) -> Int? {
        source.range(of: needle).map { source.distance(from: source.startIndex, to: $0.lowerBound) }
    }

    /// The bar's own declaration, read from the Nutrition view's file.
    private func barBody() throws -> String {
        let source = try engineSource("WatchNutritionView.swift")
        return try XCTUnwrap(
            braceBody(ofLineContaining: "struct WatchWaterBar: View", in: source),
            "the water bar is declared beside the Nutrition list (D-31)"
        )
    }

    // MARK: - S-94b-22: the bar is on the list only, empty list included

    /// The list draws the bar once, after the empty/list branch and outside the
    /// scroll view, so it sits at the bottom with or without foods; the food's
    /// own screen and every other file draw none (D-31).
    func testS94b22TheBarIsOnTheListOnlyEmptyListIncluded() throws {
        let source = try engineSource("WatchNutritionView.swift")
        let list = try XCTUnwrap(
            braceBody(ofLineContaining: "public struct WatchNutritionView: View", in: source),
            "S-94b-22 the Nutrition list view exists"
        )
        let lines = sourceLines(list)
        let bodyStart = try XCTUnwrap(
            lines.firstIndex { $0.contains("var body: some View") },
            "S-94b-22 the list has a body"
        )
        let bodyEnd = try XCTUnwrap(braceBlock(from: bodyStart, in: lines))
        let body = Array(lines[bodyStart...bodyEnd])

        XCTAssertEqual(
            body.filter { $0.contains("WatchWaterBar(") }.count,
            1,
            "S-94b-22 the list's body draws the water bar exactly once"
        )
        let bar = try XCTUnwrap(body.firstIndex { $0.contains("WatchWaterBar(") })

        let branch = try XCTUnwrap(
            body.firstIndex { $0.contains("if model.foods.isEmpty") },
            "S-94b-22 the list still branches on an empty food list"
        )
        // The if/else block ends on the first line that closes it and does not
        // carry an `else`.
        var branchEnd = branch
        var depth = 0
        for index in branch..<body.count {
            for character in body[index] {
                if character == "{" { depth += 1 } else if character == "}" { depth -= 1 }
            }
            if depth == 0, !body[index].contains("else") {
                branchEnd = index
                break
            }
        }
        XCTAssertTrue(
            body[branch...branchEnd].contains { $0.contains("} else {") },
            "S-94b-22 the branch has its list half"
        )
        XCTAssertGreaterThan(
            bar,
            branchEnd,
            "S-94b-22 the bar follows the whole empty/list branch, so both halves show it"
        )

        let scroll = try XCTUnwrap(
            braceBody(ofLineContaining: "ScrollView {", in: list),
            "S-94b-22 the foods scroll"
        )
        XCTAssertFalse(
            scroll.contains("WatchWaterBar("),
            "S-94b-22 the bar is pinned, not scrolled away with the foods"
        )

        let food = try XCTUnwrap(
            braceBody(ofLineContaining: "public struct WatchFoodPortionView: View", in: source),
            "S-94b-22 the food's screen exists"
        )
        XCTAssertFalse(food.contains("WatchWaterBar("), "S-94b-22 a food's screen carries no bar")
        XCTAssertFalse(food.contains("WatchWaterModel"), "S-94b-22 a food's screen is handed no water model")

        XCTAssertEqual(
            occurrences(of: "WatchWaterBar(", in: source),
            1,
            "S-94b-22 the Nutrition file draws the bar once, in the list"
        )
        for file in try everySource() where file.name != "WatchNutritionView.swift" {
            XCTAssertEqual(
                occurrences(of: "WatchWaterBar(", in: file.text),
                0,
                "S-94b-22 \(file.name) draws no water bar: Home, the menu and the logging surfaces carry none"
            )
        }

        let barSource = try barBody()
        let minus = try XCTUnwrap(offset(of: "press(.remove)", in: barSource), "S-94b-22 minus removes a glass")
        let minusIcon = try XCTUnwrap(offset(of: "Image(systemName: \"minus\")", in: barSource))
        let drop = try XCTUnwrap(
            offset(of: "Image(systemName: \"drop.fill\")", in: barSource),
            "S-94b-22 the middle shows the water drop (Q3)"
        )
        let count = try XCTUnwrap(
            offset(of: "Text(\"\\(snapshot.glasses)\")", in: barSource),
            "S-94b-22 the middle shows the count"
        )
        let plus = try XCTUnwrap(offset(of: "press(.add)", in: barSource), "S-94b-22 plus adds a glass")
        let plusIcon = try XCTUnwrap(offset(of: "Image(systemName: \"plus\")", in: barSource))
        XCTAssertLessThan(minus, drop, "S-94b-22 minus comes first, on the left")
        XCTAssertLessThan(minusIcon, drop, "S-94b-22 the minus symbol sits left of the middle")
        XCTAssertLessThan(drop, count, "S-94b-22 the drop comes before the number (Q3)")
        XCTAssertLessThan(count, plus, "S-94b-22 plus comes last, on the right")
        XCTAssertLessThan(count, plusIcon, "S-94b-22 the plus symbol sits right of the middle")
    }

    // MARK: - S-94b-23: the host owns one water state and one model

    /// One water state and one model for the life of the app, built in the
    /// host, handed to the orchestrator, restored right after the food list,
    /// and given to the Nutrition sheet; the session menu gets none (D-35).
    func testS94b23TheHostOwnsOneWaterStateAndOneModel() throws {
        let view = try appSource("ContentView.swift")

        XCTAssertEqual(occurrences(of: "WatchWaterState(", in: view), 1, "S-94b-23 one water state")
        XCTAssertEqual(occurrences(of: "WatchWaterModel(", in: view), 1, "S-94b-23 one water model")

        let hostInit = try XCTUnwrap(
            braceBody(ofLineContaining: "init() {", in: view),
            "S-94b-23 the host has a construction path"
        )
        XCTAssertTrue(hostInit.contains("WatchWaterState("), "S-94b-23 the state is built in the host")
        XCTAssertTrue(hostInit.contains("WatchWaterModel("), "S-94b-23 the model is built in the host")

        let orchestrator = try XCTUnwrap(
            callBody(of: "WatchSyncOrchestrator", in: view),
            "S-94b-23 the host builds the orchestrator"
        )
        XCTAssertTrue(
            orchestrator.contains("water: water"),
            "S-94b-23 the orchestrator is handed the water state, so every sync asks for the count"
        )

        let restore = try XCTUnwrap(
            braceBody(ofLineContaining: "func restore() async", in: view),
            "S-94b-23 the host has a restore path"
        )
        let restoreLines = sourceLines(restore)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let nutrition = try XCTUnwrap(
            restoreLines.firstIndex(of: "await nutrition.restore()"),
            "S-94b-23 the food list is restored"
        )
        XCTAssertEqual(
            restoreLines.firstIndex(of: "await water.restore()"),
            nutrition + 1,
            "S-94b-23 the water count is restored right after the food list (after the engine's taps)"
        )

        let content = try XCTUnwrap(
            braceBody(ofLineContaining: "struct ContentView: View", in: view),
            "S-94b-23 the shell exists"
        )
        XCTAssertTrue(
            content.contains("WatchNutritionView(model: host.nutritionModel, water: host.waterModel)"),
            "S-94b-23 the Nutrition sheet shows the host's one water model"
        )

        let menu = try XCTUnwrap(callBody(of: "WatchMenuView", in: view), "S-94b-23 the shell hosts the menu")
        XCTAssertFalse(
            menu.lowercased().contains("water"),
            "S-94b-23 no water from inside a workout: the session menu gets no water"
        )
    }

    // MARK: - S-94b-24: haptic, VoiceOver, minute refresh, 40 mm

    /// A click only on a press that stored a tap (Q2), a spoken label on every
    /// control, a minute's re-read so midnight turns the count over, a count
    /// that fits a 40 mm screen, and buttons that follow their rules (D-31 to
    /// D-34, D-27).
    func testS94b24HapticVoiceOverMinuteRefreshAndFit() throws {
        let bar = try barBody()
        let lines = sourceLines(bar)

        // The click: every one sits in the branch a stored tap takes.
        let clicks = lines.indices.filter { lines[$0].contains(".play(") }
        XCTAssertEqual(clicks.count, 2, "S-94b-24 one click per button")
        for index in clicks {
            XCTAssertTrue(lines[index].contains(".play(.click)"), "S-94b-24 the tap is the light click (Q2)")
            let guardLine = lines[..<index].last { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
            XCTAssertTrue(
                guardLine.contains("if await model.press(.add)")
                    || guardLine.contains("if await model.press(.remove)"),
                "S-94b-24 the click plays only when the press stored a tap: \(guardLine)"
            )
        }
        XCTAssertEqual(occurrences(of: "if await model.press(.add)", in: bar), 1)
        XCTAssertEqual(occurrences(of: "if await model.press(.remove)", in: bar), 1)

        // Each button's own modifiers, read between its press and the next control.
        let minusStart = try XCTUnwrap(offset(of: "press(.remove)", in: bar))
        let middle = try XCTUnwrap(offset(of: "Image(systemName: \"drop.fill\")", in: bar))
        let plusStart = try XCTUnwrap(offset(of: "press(.add)", in: bar))
        XCTAssertLessThan(minusStart, middle)
        XCTAssertLessThan(middle, plusStart)
        let minus = String(bar.dropFirst(minusStart).prefix(middle - minusStart))
        let plus = String(bar.dropFirst(plusStart))

        XCTAssertTrue(minus.contains(".disabled(!snapshot.canRemove)"), "S-94b-24 minus is off while it would do nothing")
        XCTAssertTrue(
            minus.contains(".accessibilityLabel(WatchWaterCopy.removeLabel)"),
            "S-94b-24 minus speaks Remove one glass"
        )
        XCTAssertTrue(minus.contains(".buttonStyle(.bordered)"), "S-94b-24 bordered like the portion row")
        XCTAssertFalse(minus.contains("Text("), "S-94b-24 the minus button is icon-only")

        XCTAssertTrue(plus.contains(".disabled(!snapshot.canAdd)"), "S-94b-24 plus is off past the cap")
        XCTAssertTrue(
            plus.contains(".accessibilityLabel(WatchWaterCopy.addLabel)"),
            "S-94b-24 plus speaks Add one glass"
        )
        XCTAssertTrue(plus.contains(".buttonStyle(.bordered)"), "S-94b-24 bordered like the portion row")
        XCTAssertFalse(plus.contains("Text("), "S-94b-24 the plus button is icon-only")

        // The middle: one element, labelled Water, valued with the spoken count.
        let center = String(bar.dropFirst(middle).prefix(plusStart - middle))
        XCTAssertTrue(
            center.contains(".accessibilityElement(children: .ignore)"),
            "S-94b-24 the drop and the number are one element"
        )
        XCTAssertTrue(
            center.contains(".accessibilityLabel(WatchWaterCopy.countLabel)"),
            "S-94b-24 the middle is labelled Water"
        )
        XCTAssertTrue(
            center.contains(".accessibilityValue(snapshot.spokenCount)"),
            "S-94b-24 the middle's value is the spoken count"
        )

        // The count's own chain fits a 40 mm screen.
        let countLine = try XCTUnwrap(lines.firstIndex { $0.contains("Text(\"\\(snapshot.glasses)\")") })
        let chain = lines[(countLine + 1)...]
            .prefix { $0.trimmingCharacters(in: .whitespaces).hasPrefix(".") }
            .joined(separator: "\n")
        XCTAssertTrue(chain.contains(".lineLimit(1)"), "S-94b-24 the count stays on one line")
        XCTAssertTrue(chain.contains(".minimumScaleFactor("), "S-94b-24 a wide count shrinks to fit 40 mm")

        XCTAssertTrue(
            bar.contains("TimelineView(.everyMinute)"),
            "S-94b-24 the bar re-reads every minute, so local midnight turns the count over (D-34)"
        )
    }

    // MARK: - S-94c-5: the bar reads one snapshot per redraw

    /// Plan 96 D-42: the bar binds the model's snapshot once, first inside the
    /// minute timeline, and every control reads that one value; the model has
    /// no separate accessors left for a view to re-read.
    func testS94c5TheBarReadsOneSnapshotPerRedraw() throws {
        let bar = try barBody()
        XCTAssertEqual(
            occurrences(of: "model.snapshot", in: bar),
            1,
            "S-94c-5 the bar reads the model's snapshot exactly once per redraw"
        )
        let lines = sourceLines(bar)
        let timeline = try XCTUnwrap(
            lines.firstIndex { $0.contains("TimelineView(.everyMinute) {") },
            "S-94c-5 the bar keeps its minute timeline (D-34)"
        )
        let first = lines[(timeline + 1)...]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        XCTAssertEqual(
            first,
            "let snapshot = model.snapshot",
            "S-94c-5 the snapshot is bound first inside the timeline, so the minute tick re-reads it"
        )

        for file in try everySource() {
            for accessor in ["glasses", "canAdd", "canRemove", "spokenCount"] {
                XCTAssertEqual(
                    occurrences(of: "model.\(accessor)", in: file.text),
                    0,
                    "S-94c-5 \(file.name) reads model.\(accessor); read it from one snapshot instead"
                )
            }
        }

        let model = try XCTUnwrap(
            braceBody(
                ofLineContaining: "public final class WatchWaterModel",
                in: try engineSource("WatchWater.swift")
            ),
            "S-94c-5 the water model exists"
        )
        for accessor in ["glasses", "canAdd", "canRemove", "spokenCount"] {
            XCTAssertFalse(
                model.contains("var \(accessor)"),
                "S-94c-5 WatchWaterModel declares no var \(accessor): views read the snapshot"
            )
        }
    }

    // MARK: - S-94b-25a: pruneConfirmed() has no caller; only launch prunes taps

    /// `pruneConfirmed()` would drop today's confirmed taps the count still
    /// reads, so nothing in the module or the app may call it: its declarations
    /// and the engine's own delegation to its store are the only occurrences.
    /// Taps leave only through `pruneWaterTaps(loggedBefore:)`, called once, by
    /// `WatchWaterState.restore()` (plan 96 D-43, I-12).
    func testS94b25aPruneConfirmedHasNoCallerAndOnlyLaunchPrunesTaps() throws {
        var callers: [String] = []
        var tapPruneCallers: [String] = []
        for file in try everySource() {
            for line in sourceLines(file.text) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if line.contains("pruneConfirmed("), !line.contains("func pruneConfirmed"),
                   !(file.name == "WatchSessionEngine.swift"
                       && trimmed == "let pruned = await store.pruneConfirmed()") {
                    callers.append("\(file.name): \(trimmed)")
                }
                if line.contains("pruneWaterTaps("), !line.contains("func pruneWaterTaps"),
                   !(file.name == "WatchSessionEngine.swift"
                       && trimmed == "let pruned = await store.pruneWaterTaps(loggedBefore: cutoff)") {
                    tapPruneCallers.append("\(file.name): \(trimmed)")
                }
            }
        }
        XCTAssertEqual(
            callers,
            [],
            "S-94b-25a plan 96 D-43 (supersedes plan 95 D-37): pruneConfirmed() would drop taps the "
                + "water count still reads, so it has no production caller"
        )
        XCTAssertEqual(
            tapPruneCallers.count,
            1,
            "S-94b-25a plan 96 D-43: the tap prune has exactly one caller, the launch; found \(tapPruneCallers)"
        )
        XCTAssertTrue(
            tapPruneCallers.first?.hasPrefix("WatchWater.swift: ") ?? false,
            "S-94b-25a plan 96 D-43: the one tap-prune caller is WatchWater.swift; found \(tapPruneCallers)"
        )

        let water = try engineSource("WatchWater.swift")
        let restore = try XCTUnwrap(
            braceBody(ofLineContaining: "public func restore() async {", in: water),
            "WatchWaterState declares restore()"
        )
        XCTAssertEqual(
            occurrences(of: "pruneWaterTaps(", in: restore),
            1,
            "S-94b-25a plan 96 D-43: the tap prune runs inside WatchWaterState.restore(), once per launch"
        )
    }
}
