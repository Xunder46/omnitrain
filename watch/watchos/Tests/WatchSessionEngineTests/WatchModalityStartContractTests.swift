//
//  WatchModalityStartContractTests.swift
//  WatchSessionEngineTests
//
//  The wrist half of the Start surface's modality grid: the four cells are the
//  shared contract, row for row.
//
//  Plan: `docs/plans/2026-11-15-176-watch-modality-start-grid-plan/2026-11-15-176-watch-modality-start-grid-plan.md`,
//  scenarios S-17602 (the grid wears exactly the contract's values, both stacks)
//  and S-17603 (the cell's VoiceOver sentence).
//
//  Like the accent suite beside this one, nothing is restated here: the table is
//  read from `watch/contract/watch_modality_start_contract.json`, which the
//  phone's own tokens are held to in `test/watch_modality_start_contract_test.dart`.
//

import Foundation
import XCTest

@testable import WatchSessionEngine

final class WatchModalityStartContractTests: XCTestCase {

    private func contract() throws -> [String: Any] {
        let url = Fixtures.repositoryRoot
            .appendingPathComponent("watch/contract/watch_modality_start_contract.json")
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FixtureError.malformed("watch_modality_start_contract.json")
        }
        return object
    }

    private func rows() throws -> [[String: Any]] {
        guard let rows = try contract()["gridOrder"] as? [[String: Any]] else {
            throw FixtureError.malformed("gridOrder")
        }
        return rows
    }

    private enum FixtureError: Error {
        case malformed(String)
    }

    // MARK: - S-17602 the four cells are the contract, in its order

    func testS17602TheCellsAreTheContractsRowsInOrder() throws {
        let rows = try rows()

        XCTAssertEqual(rows.count, WatchModalityStart.cells.count, "the grid offers the contract's four rows")
        XCTAssertEqual(
            WatchModalityStart.cells.map(\.key),
            rows.compactMap { $0["key"] as? String },
            "the cells are the contract's keys, in its order"
        )
        XCTAssertEqual(
            WatchModalityStart.cells.map(\.label),
            rows.compactMap { $0["label"] as? String },
            "the cells show the contract's short labels, not the phone's long names"
        )
        XCTAssertEqual(
            WatchModalityStart.cells.map(\.hex),
            rows.compactMap { $0["hex"] as? String },
            "the cells wear the phone's own modality colours"
        )
    }

    func testS17602TheGridIsThePhonesHomeTileOrder() throws {
        XCTAssertEqual(
            WatchModalityStart.cells.map(\.key),
            ["cardio_endurance", "resistance_lifting", "sports", "isometric_stretching"],
            "the grid reads as the phone's home tiles do: Cardio, Resistance, Sports, Isometric"
        )
    }

    func testS17602EveryHexIsARenderableAccent() throws {
        for row in try rows() {
            let hex = try XCTUnwrap(row["hex"] as? String, "each row names a hex")
            XCTAssertTrue(
                hex.count == 7 && hex.hasPrefix("#") && hex.dropFirst().allSatisfy(\.isHexDigit),
                "\(hex) is #RRGGBB, the shape WatchAccent(hex:) parses"
            )
            let accent = try XCTUnwrap(WatchAccent(hex: hex), "\(hex) parses")
            XCTAssertTrue(
                accent.isUsable,
                "\(hex) clears the accent contrast floor, so the cell is readable when worn"
            )
        }
    }

    // MARK: - S-17603 the cell's VoiceOver sentence

    func testS17603EachCellIsSpokenAsItsStartSentence() throws {
        let pattern = try XCTUnwrap(
            contract()["startSurfaceSentence"] as? String,
            "the contract carries the sentence pattern"
        )
        XCTAssertEqual(pattern, "Start <Label> workout")

        for cell in WatchModalityStart.cells {
            XCTAssertEqual(
                WatchModalityStart.startSentence(for: cell.label),
                pattern.replacingOccurrences(of: "<Label>", with: cell.label),
                "\(cell.label) is spoken exactly as the contract's pattern says"
            )
        }
    }

    func testS17603TheFourSentencesAreTheOnesOwnerAndQARead() {
        XCTAssertEqual(
            WatchModalityStart.cells.map { WatchModalityStart.startSentence(for: $0.label) },
            [
                "Start Cardio workout",
                "Start Resistance workout",
                "Start Sports workout",
                "Start Isometric workout",
            ],
            "the grid's four spoken labels"
        )
    }
}
