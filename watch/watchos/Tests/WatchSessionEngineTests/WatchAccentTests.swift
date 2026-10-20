//
//  WatchAccentTests.swift
//  WatchSessionEngineTests
//
//  Phase D1 of
//  `docs/plans/2026-10-11-23d-watch-accent-color-plan/2026-10-11-23d-watch-accent-color-plan.md`:
//  the accent the wrist wears (D-3704, D-3705, S-3710 – S-3712).
//
//  Every expectation is read from `watch/contract/watch_accent_contract.json` —
//  the table both watch clients share — so a hex here is the contract rather
//  than a restatement of it. The luminance and both contrasts are computed from
//  the hex, and the table's floor is what decides whether an accent is worn.
//

import XCTest

@testable import WatchSessionEngine

final class WatchAccentTests: XCTestCase {

    /// One row of the shared table.
    private struct ThemeRow {
        let theme: String
        let hex: String
        let labelIsDark: Bool
    }

    private struct AccentTable {
        /// The floor an accent clears to be worn at all (D-3704).
        let minContrastAgainstBlack: Double
        let themes: [ThemeRow]

        static func load() throws -> AccentTable {
            let contract = try Fixtures.accentContract()
            let rows = try XCTUnwrap(
                contract["themes"] as? [[String: Any]],
                "the contract carries its themes"
            )
            let themes = try rows.map { row in
                ThemeRow(
                    theme: try XCTUnwrap(row["theme"] as? String, "a row's theme"),
                    hex: try XCTUnwrap(row["hex"] as? String, "a row's hex"),
                    labelIsDark: try XCTUnwrap(row["labelIsDark"] as? Bool, "a row's labelIsDark")
                )
            }
            return AccentTable(
                minContrastAgainstBlack: try XCTUnwrap(
                    (contract["minContrastAgainstBlack"] as? NSNumber)?.doubleValue,
                    "the contract's minContrastAgainstBlack"
                ),
                themes: themes
            )
        }
    }

    private var table: AccentTable!

    override func setUpWithError() throws {
        table = try AccentTable.load()
    }

    /// The channels `#RRGGBB` names, read out of the string here so a row is
    /// held to its own hex rather than to the parser under test.
    private func channels(_ hex: String) throws -> (Double, Double, Double) {
        let value = try XCTUnwrap(Int(hex.dropFirst(), radix: 16), "\(hex) is a #RRGGBB accent")
        return (
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        )
    }

    private func accent(_ hex: String) throws -> WatchAccent {
        try XCTUnwrap(WatchAccent(hex: hex), "\(hex) parses as a #RRGGBB accent")
    }

    // MARK: - S-3710 every row of the shared table

    func testS3710EveryRowOfTheSharedTableParsesWithTheTablesLabel() throws {
        XCTAssertEqual(table.themes.count, 6, "the table carries every theme")
        XCTAssertEqual(
            Set(table.themes.map(\.theme)).count,
            table.themes.count,
            "no theme is listed twice"
        )
        XCTAssertEqual(
            WatchAccent.minContrastAgainstBlack,
            table.minContrastAgainstBlack,
            "S-3710: the floor the code enforces is the floor the table carries"
        )
        for row in table.themes {
            let parsed = try accent(row.hex)
            let expected = try channels(row.hex)
            XCTAssertEqual(parsed.red, expected.0, accuracy: 1e-12, "\(row.theme): red")
            XCTAssertEqual(parsed.green, expected.1, accuracy: 1e-12, "\(row.theme): green")
            XCTAssertEqual(parsed.blue, expected.2, accuracy: 1e-12, "\(row.theme): blue")
            XCTAssertEqual(
                parsed.labelIsDark,
                row.labelIsDark,
                "S-3710: \(row.theme) takes the label the table names"
            )
            XCTAssertEqual(
                WatchAccent.usable(hex: row.hex),
                parsed,
                "S-3710: \(row.theme) is worn as itself"
            )
            XCTAssertGreaterThanOrEqual(
                parsed.contrastAgainstBlack,
                table.minContrastAgainstBlack,
                "\(row.theme): every theme accent clears the contrast floor"
            )
            XCTAssertTrue(parsed.isUsable, "\(row.theme): and so is worn")
        }
    }

    func testS3710LightAccentsTakeDarkLabelsAndDarkAccentsLightOnes() throws {
        let white = try accent("#FFFFFF")
        let black = try accent("#000000")

        XCTAssertTrue(white.labelIsDark, "S-3710: dark labels read better on white")
        XCTAssertFalse(black.labelIsDark, "S-3710: and light labels read better on black")
        XCTAssertEqual(white.contrastAgainstBlack, 21, accuracy: 1e-9, "white against black is the maximum")
        XCTAssertEqual(black.contrastAgainstWhite, 21, accuracy: 1e-9, "black against white is the maximum")
        XCTAssertEqual(black.contrastAgainstBlack, 1, accuracy: 1e-9, "and black against black the minimum")
        XCTAssertEqual(
            try accent("#000000").relativeLuminance,
            0,
            accuracy: 1e-12,
            "S-3710: black is the luminance floor"
        )
        XCTAssertEqual(
            try accent("#FFFFFF").relativeLuminance,
            1,
            accuracy: 1e-9,
            "S-3710: and white the ceiling"
        )
    }

    // MARK: - S-3711 a string that is not #RRGGBB parses to nothing

    func testS3711AStringThatIsNotSixHexDigitsParsesToNothing() throws {
        for hex in ["#GGGGGG", "2DE2E6", "#FFF", "#2DE2E6FF", "#2DE2E", "#+2DE2E", "#", ""] {
            XCTAssertNil(WatchAccent(hex: hex), "S-3711: \(hex) is not a #RRGGBB accent")
        }

        // The shape the schema's pattern allows is the shape that parses, the
        // lowercase digits included.
        XCTAssertEqual(
            try accent("#2DE2E6"),
            try accent("#2de2e6"),
            "S-3711: a lowercase spelling is the same color"
        )
    }

    // MARK: - S-3712 an accent too dark to wear

    func testS3712ANearBlackAccentIsRefusedRatherThanWorn() throws {
        // A hex the pattern accepts, and a color nothing can be read on: the
        // wrist keeps its default look instead (D-3704).
        let nearBlack = try accent("#101010")
        XCTAssertLessThan(
            nearBlack.contrastAgainstBlack,
            table.minContrastAgainstBlack,
            "S-3712: #101010 does not clear the floor"
        )
        XCTAssertFalse(nearBlack.isUsable, "S-3712: so it is not a usable accent")
        XCTAssertFalse(nearBlack.labelIsDark, "S-3712: a near-black accent takes light labels")
        XCTAssertNil(WatchAccent.usable(hex: "#101010"), "S-3712: and the preference path drops it")

        // Nothing to wear: no accent, a string that does not parse, and a color
        // too dark all read as no accent rather than as some default color.
        XCTAssertNil(WatchAccent.usable(hex: nil), "S-3712: no accent is nothing to wear")
        XCTAssertNil(
            WatchAccent.usable(hex: "teal"),
            "S-3712: the string the schema refuses is nothing to wear"
        )
        XCTAssertNil(WatchAccent.usable(hex: "#010203"), "S-3712: so is a color too dark to read")
    }
}
