//
//  WatchAccessibilitySourceTests.swift
//  WatchSessionEngineTests
//
//  Source guards for the wrist's VoiceOver labels (plan 84): the rest clock
//  speaks its time and Next carries its hint (S-15303), the menu row reads as
//  one element (S-15304), and a ratchet holds the count of files carrying
//  accessibility modifiers so the coverage cannot quietly shrink.
//
//  The watchOS-only views do not compile under `swift test`; what is held
//  off-device is the shape of their modifier chains, read from the files with
//  every comment line removed, so a sentence of prose can neither satisfy a
//  guard nor trip one.
//

import Foundation
import XCTest

final class WatchAccessibilitySourceTests: XCTestCase {

    // MARK: - S-15303: the rest clock speaks, Next hints

    func testS15303TheRestClockSpeaksItsTimeAndNextCarriesItsHint() throws {
        let source = try engineSource("WatchRestView.swift")

        let clockStatements = [
            ".accessibilityLabel(\"Rest time\")",
            ".accessibilityValue(WatchSpokenText.duration(seconds: state.restElapsedSeconds() ?? 0))",
            ".accessibilityAddTraits(.updatesFrequently)",
        ]
        let clock = try XCTUnwrap(
            source.range(of: "Text(elapsed)"),
            "S-15303 the rest clock's Text is in the source"
        )
        let nextLine = try XCTUnwrap(
            source.range(of: "Text(labels.next)"),
            "S-15303 the Next line is in the source"
        )
        for statement in clockStatements {
            XCTAssertTrue(
                source.contains(statement),
                "S-15303 the clock chain should carry \(statement)"
            )
            let range = try XCTUnwrap(
                source.range(of: statement),
                "S-15303 \(statement) is in the source"
            )
            XCTAssertTrue(
                range.lowerBound > clock.upperBound,
                "S-15303 \(statement) belongs to the clock's own chain, after Text(elapsed)"
            )
            XCTAssertTrue(
                range.upperBound < nextLine.lowerBound,
                "S-15303 \(statement) belongs to the clock's own chain, before Text(labels.next)"
            )
        }

        let hint = ".accessibilityHint(state.restLabels.next)"
        XCTAssertTrue(
            source.contains(hint),
            "S-15303 Next should carry the hint the line above it shows"
        )
        let nextButton = try XCTUnwrap(
            propertyBody(named: "nextButton", in: source),
            "S-15303 the rest view has a nextButton property"
        )
        XCTAssertTrue(
            nextButton.contains(hint),
            "S-15303 the hint belongs to nextButton"
        )
        let prominent = try XCTUnwrap(
            nextButton.range(of: ".watchProminent()"),
            "S-15303 nextButton keeps its prominent style"
        )
        let hintRange = try XCTUnwrap(
            nextButton.range(of: hint),
            "S-15303 the hint is in nextButton"
        )
        XCTAssertTrue(
            hintRange.lowerBound > prominent.upperBound,
            "S-15303 the hint is appended after .watchProminent(), not before it"
        )
    }

    // MARK: - S-15304: the menu row reads as one element

    func testS15304TheMenuRowCombinesItsNameAndCountIntoOneElement() throws {
        let source = try engineSource("WatchMenuView.swift")
        let rowBody = try XCTUnwrap(
            functionBody(of: "func rowLabel", in: source),
            "S-15304 the menu view has a rowLabel function"
        )

        let combine = ".accessibilityElement(children: .combine)"
        XCTAssertTrue(
            rowBody.contains(combine),
            "S-15304 the row's VStack should combine its children for VoiceOver"
        )
        XCTAssertEqual(
            occurrences(of: combine, in: source),
            1,
            "S-15304 the combine belongs to rowLabel alone in this file"
        )
    }

    // MARK: - S-15305: the summary rows combine, the title is a header

    func testS15305TheSummaryRowsCombineAndTheTitleIsAHeader() throws {
        let source = try engineSource("WatchWorkoutSummaryView.swift")

        let title = try XCTUnwrap(
            source.range(of: "Text(WatchWorkoutSummaryCopy.title)"),
            "S-15305 the summary title is in the source"
        )
        let header = ".accessibilityAddTraits(.isHeader)"
        let headerRange = try XCTUnwrap(
            source.range(of: header),
            "S-15305 the title should carry \(header)"
        )
        XCTAssertTrue(
            headerRange.lowerBound > title.upperBound,
            "S-15305 the header trait belongs to the title's own chain, after Text(WatchWorkoutSummaryCopy.title)"
        )

        let combine = ".accessibilityElement(children: .combine)"
        XCTAssertEqual(
            occurrences(of: combine, in: source),
            1,
            "S-15305 the combine belongs to the row HStack alone in this file"
        )
        let rowValue = try XCTUnwrap(
            source.range(of: "Text(row.value)"),
            "S-15305 the row value is in the source"
        )
        let footnote = try XCTUnwrap(
            source.range(of: ".font(.footnote)"),
            "S-15305 the row chain keeps its footnote style"
        )
        let combineRange = try XCTUnwrap(
            source.range(of: combine),
            "S-15305 \(combine) is in the source"
        )
        XCTAssertTrue(
            combineRange.lowerBound > rowValue.upperBound,
            "S-15305 the combine belongs to the row HStack, after its Texts"
        )
        XCTAssertTrue(
            combineRange.upperBound < footnote.lowerBound,
            "S-15305 the combine is appended to the row HStack, before .font(.footnote)"
        )
    }

    // MARK: - S-15306: the rating scale speaks, the crown carries the choice

    func testS15306TheRatingScaleSpeaksAndTheCrownCarriesTheChoice() throws {
        let source = try engineSource("WatchEffortRatingView.swift")

        let scaleBody = try XCTUnwrap(
            functionBody(of: "func scaleButton", in: source),
            "S-15306 the rating view has a scaleButton function"
        )
        let label = ".accessibilityLabel(WatchSpokenText.rating(value, of: WatchEffortRatingCopy.highest))"
        XCTAssertEqual(
            occurrences(of: label, in: scaleBody),
            2,
            "S-15306 both branches of the scale carry the spoken label"
        )
        let selected = ".accessibilityAddTraits(.isSelected)"
        XCTAssertEqual(
            occurrences(of: selected, in: scaleBody),
            1,
            "S-15306 only the selected branch carries the selected trait"
        )
        let prominent = try XCTUnwrap(
            scaleBody.range(of: ".watchProminent()"),
            "S-15306 the selected branch keeps its prominent style"
        )
        let selectedRange = try XCTUnwrap(
            scaleBody.range(of: selected),
            "S-15306 \(selected) is in the source"
        )
        XCTAssertTrue(
            selectedRange.lowerBound > prominent.upperBound,
            "S-15306 the selected trait is appended to the prominent branch"
        )

        let value = ".accessibilityValue(state.selected.map { WatchSpokenText.rating($0, of: WatchEffortRatingCopy.highest) } ?? \"No rating\")"
        let valueRange = try XCTUnwrap(
            source.range(of: value),
            "S-15306 the crown's view should carry \(value)"
        )
        let dismiss = try XCTUnwrap(
            source.range(of: ".interactiveDismissDisabled(true)"),
            "S-15306 the body keeps its interactiveDismissDisabled"
        )
        XCTAssertTrue(
            valueRange.lowerBound > dismiss.upperBound,
            "S-15306 the value is appended after .interactiveDismissDisabled(true)"
        )
        let scaleStart = try XCTUnwrap(
            source.range(of: "private func scaleButton"),
            "S-15306 the scaleButton function is in the source"
        )
        XCTAssertTrue(
            valueRange.upperBound < scaleStart.lowerBound,
            "S-15306 the value belongs to the body's own chain, before scaleButton"
        )

        let hint = ".accessibilityHint(\"Saves your rating\")"
        let confirmBody = try XCTUnwrap(
            propertyBody(named: "confirmButton", in: source),
            "S-15306 the rating view has a confirmButton property"
        )
        XCTAssertTrue(
            confirmBody.contains(hint),
            "S-15306 Confirm should carry \(hint)"
        )
        let disabled = try XCTUnwrap(
            confirmBody.range(of: ".disabled(!state.canConfirm)"),
            "S-15306 confirmButton keeps its disabled gate"
        )
        let hintRange = try XCTUnwrap(
            confirmBody.range(of: hint),
            "S-15306 the hint is in confirmButton"
        )
        XCTAssertTrue(
            hintRange.lowerBound > disabled.upperBound,
            "S-15306 the hint is appended after .disabled(!state.canConfirm)"
        )
        XCTAssertEqual(
            occurrences(of: hint, in: source),
            1,
            "S-15306 the hint belongs to confirmButton alone; Skip is unchanged"
        )
    }

    // MARK: - The ratchet: the accessibility coverage cannot shrink

    /// Plan 84's partial ratchet: at least six engine files carry a real,
    /// dot-prefixed `.accessibility` modifier on comment-stripped source, and
    /// the two P1 files are named. P2 raises the floor to eight and names the
    /// summary and rating views too (S-15307).
    func testTheAccessibilityRatchetHoldsAtSixFilesNamingTheRestAndMenuViews() throws {
        let files = try FileManager.default
            .contentsOfDirectory(at: Fixtures.sourcesRoot, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }

        var carrying: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            if strippingCommentLines(text).contains(".accessibility") {
                carrying.append(file.lastPathComponent)
            }
        }

        XCTAssertGreaterThanOrEqual(
            carrying.count,
            6,
            "the ratchet: at least six engine files carry accessibility modifiers, found \(carrying.sorted())"
        )
        for named in ["WatchRestView.swift", "WatchMenuView.swift"] {
            XCTAssertTrue(
                carrying.contains(named),
                "the ratchet names \(named), found \(carrying.sorted())"
            )
        }
    }

    /// S-15307 completes the ratchet: at least eight engine files carry a
    /// real, dot-prefixed `.accessibility` modifier on comment-stripped
    /// source, and all eight are named — the four P1/P2 views and the four
    /// that already carried labels at base.
    func testTheAccessibilityRatchetHoldsAtEightFilesNamingTheSummaryAndRatingViews() throws {
        let files = try FileManager.default
            .contentsOfDirectory(at: Fixtures.sourcesRoot, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }

        var carrying: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            if strippingCommentLines(text).contains(".accessibility") {
                carrying.append(file.lastPathComponent)
            }
        }

        XCTAssertGreaterThanOrEqual(
            carrying.count,
            8,
            "the ratchet: at least eight engine files carry accessibility modifiers, found \(carrying.sorted())"
        )
        for named in [
            "WatchRestView.swift",
            "WatchMenuView.swift",
            "WatchWorkoutSummaryView.swift",
            "WatchEffortRatingView.swift",
            "WatchStartView.swift",
            "WatchExerciseListView.swift",
            "WatchLoggingView.swift",
            "WatchNutritionView.swift",
        ] {
            XCTAssertTrue(
                carrying.contains(named),
                "the ratchet names \(named), found \(carrying.sorted())"
            )
        }
    }

    // MARK: - Helpers (copied from WatchPagerSourceTests)

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

    /// The brace-balanced body of the property `var <name>:`, from its opening
    /// brace to its closing one, or nil when the property is not there.
    private func propertyBody(named name: String, in source: String) -> String? {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0.contains("var \(name):") }) else {
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
            if started, depth == 0 { return body.joined(separator: "\n") }
        }
        return nil
    }

    /// The brace-balanced body of the function `func <name>`, read the same way
    /// as `propertyBody`, for the guards that slice a function rather than a
    /// computed property.
    private func functionBody(of marker: String, in source: String) -> String? {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0.contains(marker) }) else {
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
            if started, depth == 0 { return body.joined(separator: "\n") }
        }
        return nil
    }

    /// How many times `needle` occurs in `source`.
    private func occurrences(of needle: String, in source: String) -> Int {
        source.components(separatedBy: needle).count - 1
    }
}
