//
//  WatchPlannedSurfaceSourceTests.swift
//  WatchSessionEngineTests
//
//  Source guards for what `swift test` cannot compile: the watchOS-only start
//  surface's planned-workout button and picker, and the copy they read. Plan
//  `docs/plans/2026-11-05-129-wrist-planned-button-plan/2026-11-05-129-wrist-planned-button-plan.md`,
//  scenarios S-8965 and S-8969 (decisions D-8963, D-8964, D-8965, D-8969).
//
//  Every guard reads a file's text with its comment lines removed, so a
//  sentence of prose can neither satisfy a guard nor trip one.
//

import Foundation
import XCTest

final class WatchPlannedSurfaceSourceTests: XCTestCase {

    // MARK: - Reading the surface

    private func engineSource(_ name: String) throws -> String {
        let url = Fixtures.sourcesRoot.appendingPathComponent(name)
        let text = try String(contentsOf: url, encoding: .utf8)
        return strippingCommentLines(text)
    }

    /// Blanks every line whose trimmed text starts with `//`, keeping the line
    /// boundaries. A trailing `//` comment on a code line is blanked too, so
    /// prose there can neither satisfy a guard nor trip one.
    private func strippingCommentLines(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false)
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

    /// How many times `needle` appears.
    private func occurrences(of needle: String, in source: String) -> Int {
        var count = 0
        var range = source.startIndex..<source.endIndex
        while let found = source.range(of: needle, range: range) {
            count += 1
            range = found.upperBound..<source.endIndex
        }
        return count
    }

    // MARK: - S-8965 the planned button is the first thing on the surface

    func testS8965ThePlannedButtonComesBeforeTheRoutineList() throws {
        let view = try engineSource("WatchStartView.swift")

        let lines = sourceLines(view)
        let plannedIndex = lines.firstIndex { $0.contains("if !startablePlans.isEmpty") }
        let emptyRoutinesIndex = lines.firstIndex { $0.contains("if paths.routines.isEmpty") }
        let routinesRow = sourceLines(view)
        let forEachIndex = routinesRow.firstIndex { $0.contains("ForEach(paths.routines") }

        XCTAssertNotNil(plannedIndex, "the planned button block is in the view")
        XCTAssertNotNil(emptyRoutinesIndex, "the empty-routines branch is in the view")
        XCTAssertNotNil(forEachIndex, "the routine `ForEach` is in the view")
        XCTAssertTrue(plannedIndex! < emptyRoutinesIndex!, "the planned button stands above the empty-routines branch")
        XCTAssertTrue(plannedIndex! < forEachIndex!, "the planned button stands above the routine rows")
    }

    func testS8965ThePlannedCaptionCountsThePlans() throws {
        let view = try engineSource("WatchStartView.swift")

        let plannedBlock = try XCTUnwrap(
            braceBody(ofLineContaining: "if !startablePlans.isEmpty", in: view),
            "the planned button block is in the view"
        )
        XCTAssertTrue(
            occurrences(of: "startablePlans.count > 1", in: plannedBlock) == 1,
            "the caption counts the wrist's plans once"
        )
        XCTAssertTrue(
            occurrences(of: "WatchStartSurfaceCopy.plannedLabel", in: plannedBlock) == 1,
            "several plans are captioned with the shared label"
        )
        XCTAssertTrue(
            occurrences(of: "startablePlans[0].name", in: plannedBlock) == 1,
            "one plan is captioned with its own name"
        )
        // The three caption pieces stand together in the same statement, in
        // that order.
        let blockLines = sourceLines(plannedBlock)
        let totalCount = blockLines.firstIndex { $0.contains("startablePlans.count > 1") }
        let labelCount = blockLines.firstIndex { $0.contains("WatchStartSurfaceCopy.plannedLabel") }
        let nameCount = blockLines.firstIndex { $0.contains("startablePlans[0].name") }
        XCTAssertTrue(
            (totalCount != nil && labelCount != nil && nameCount != nil),
            "the caption is one statement holding all three pieces"
        )
        if let totalCount, let labelCount, let nameCount {
            XCTAssertTrue(totalCount < labelCount, "the count precedes the label")
            XCTAssertTrue(labelCount < nameCount, "the label precedes the single plan's name")
        }
    }

    func testS8965ThePlannedButtonWearsBorderedAndTheRoutineStaysProminent() throws {
        let view = try engineSource("WatchStartView.swift")

        let plannedBlock = try XCTUnwrap(
            braceBody(ofLineContaining: "if !startablePlans.isEmpty", in: view),
            "the planned button block is in the view"
        )
        XCTAssertTrue(
            plannedBlock.contains("Button(") && plannedBlock.contains(".buttonStyle(.bordered)"),
            "the planned button follows its `Button(` with the bordered style"
        )
        XCTAssertTrue(
            !plannedBlock.contains(".watchProminent()"),
            "the planned button never competes with the routines"
        )

        let routineBlock = try XCTUnwrap(
            braceBody(ofLineContaining: "ForEach(paths.routines", in: view),
            "the routine rows are in the view"
        )
        XCTAssertTrue(
            routineBlock.contains("Button(routine.name)"),
            "the routine block still taps its own row"
        )
        XCTAssertTrue(
            routineBlock.contains(".watchProminent()"),
            "the routine rows keep their prominent style"
        )
    }

    // MARK: - S-8965 the picker and its state

    func testS8965ThePlanPickerSheetAndItsStateExist() throws {
        let view = try engineSource("WatchStartView.swift")

        XCTAssertTrue(
            occurrences(of: ".sheet(isPresented: $pickingPlan)", in: view) == 1,
            "one sheet presents the planned picker"
        )
        XCTAssertTrue(
            occurrences(of: "@State private var pickingPlan = false", in: view) == 1,
            "one state flag holds the planned picker"
        )
    }

    func testS8965ThePlannedPickerShowsOnlyNames() throws {
        let view = try engineSource("WatchStartView.swift")

        let picker = try XCTUnwrap(
            braceBody(ofLineContaining: "public struct WatchPlannedPickerView", in: view),
            "the planned picker is in the view"
        )
        XCTAssertTrue(
            occurrences(of: "Button(plan.name)", in: picker) == 1,
            "each plan is a row named for itself"
        )
        XCTAssertTrue(
            !picker.contains("Text("),
            "the picker carries no other sentence"
        )
    }

    // MARK: - S-8969 the copy lives in the shared enum

    func testS8969ThePlannedCopyLivesInWatchStartSurfaceCopy() throws {
        let paths = try engineSource("WatchStartPaths.swift")

        XCTAssertTrue(
            occurrences(of: "public static let plannedLabel = \"Planned\"", in: paths) == 1,
            "the planned button's label is declared once"
        )
        XCTAssertTrue(
            occurrences(of: "public static let plannedPickerTitle = \"Planned workouts\"", in: paths) == 1,
            "the planned picker's title is declared once"
        )
    }
}
