//
//  WatchSpokenTextTests.swift
//  WatchSessionEngineTests
//
//  The spoken-text helpers the wrist's VoiceOver labels read (plan 84, D-1,
//  D-8): scenarios S-15301, S-15302 and S-15309. Pure functions, so they run
//  on macOS under `swift test`.
//

import WatchSessionEngine
import XCTest

final class WatchSpokenTextTests: XCTestCase {

    // MARK: - S-15301 duration speaks whole units, zero units dropped

    func testS15301DurationSpeaksHoursMinutesSecondsAndDropsZeroUnits() {
        XCTAssertEqual(WatchSpokenText.duration(seconds: 0), "0 seconds", "S-15301 a zero rest is spoken")
        XCTAssertEqual(WatchSpokenText.duration(seconds: 1), "1 second", "S-15301 the singular second")
        XCTAssertEqual(WatchSpokenText.duration(seconds: 45), "45 seconds", "S-15301 plain seconds")
        XCTAssertEqual(WatchSpokenText.duration(seconds: 60), "1 minute", "S-15301 the singular minute")
        XCTAssertEqual(
            WatchSpokenText.duration(seconds: 125),
            "2 minutes 5 seconds",
            "S-15301 minutes then seconds, zero units dropped"
        )
        XCTAssertEqual(
            WatchSpokenText.duration(seconds: 3723),
            "1 hour 2 minutes 3 seconds",
            "S-15301 hours, minutes and seconds in that order"
        )
        XCTAssertEqual(WatchSpokenText.duration(seconds: 3600), "1 hour", "S-15301 the singular hour")
        XCTAssertEqual(
            WatchSpokenText.duration(seconds: -5),
            "0 seconds",
            "S-15301 a negative duration reads as zero"
        )
    }

    // MARK: - S-15302 rating speaks value and scale

    func testS15302RatingSpeaksTheValueAndTheScale() {
        XCTAssertEqual(WatchSpokenText.rating(3, of: 5), "Rating 3 of 5", "S-15302 the five-step scale")
        XCTAssertEqual(WatchSpokenText.rating(1, of: 10), "Rating 1 of 10", "S-15302 a ten-step scale")
    }

    // MARK: - S-15309 the zero-unit dropping table

    func testS15309DurationDropsEveryZeroUnitExceptAZeroTotal() {
        XCTAssertEqual(
            WatchSpokenText.duration(seconds: 61),
            "1 minute 1 second",
            "S-15309 the zero hour is dropped"
        )
        XCTAssertEqual(
            WatchSpokenText.duration(seconds: 3660),
            "1 hour 1 minute",
            "S-15309 the zero seconds are dropped"
        )
        XCTAssertEqual(
            WatchSpokenText.duration(seconds: 3661),
            "1 hour 1 minute 1 second",
            "S-15309 every unit present keeps its place"
        )
        XCTAssertEqual(
            WatchSpokenText.duration(seconds: 2700),
            "45 minutes",
            "S-15309 a half hour is minutes alone"
        )
        XCTAssertEqual(WatchSpokenText.duration(seconds: 120), "2 minutes", "S-15309 the plural minute")
        XCTAssertEqual(
            WatchSpokenText.duration(seconds: 0),
            "0 seconds",
            "S-15309 zero is the only total that keeps a zero unit"
        )
    }
}
