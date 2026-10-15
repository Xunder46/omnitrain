//
//  WatchUnitsTests.swift
//  WatchSessionEngineTests
//
//  The units the phone sends in `preferences_down` (S-3903 to S-3905): the wrist
//  stores them, reads the newest copy's, falls back to kilograms and kilometres
//  when told nothing, and the logging state follows a copy that lands while it
//  is alive. The Dart twin is `test/watch_sync_request_handler_test.dart`
//  (`S-3903`), and the fixtures both walk are
//  `fixtures/valid/preferences_down_units.json` and
//  `fixtures/invalid/preferences_down_units_bad.json`.
//

import XCTest
@testable import WatchSessionEngine

final class WatchUnitsTests: XCTestCase {
    private func preferences(_ harness: Harness) -> WatchPhonePreferences {
        WatchPhonePreferences(
            store: harness.store,
            validator: Harness.validator(),
            clock: harness.clock.call
        )
    }

    func testS3903AWristThatHasHeardNothingReadsKilogramsAndKilometres() {
        let units = preferences(Harness()).units

        XCTAssertEqual(units.weightUnit, "kg")
        XCTAssertEqual(units.distanceUnit, "km")
        XCTAssertFalse(units.isPounds)
        XCTAssertFalse(units.isMiles)
    }

    func testS3903TheWristStoresTheUnitsAndKeepsThemAcrossARelaunch() async throws {
        let harness = Harness()
        let prefs = preferences(harness)
        let wire = try Fixtures.json("fixtures/valid/preferences_down_units.json")

        let applied = await prefs.applyPreferencesDown(wire)
        XCTAssertTrue(applied.applied, "the fixture conforms to the schema")
        XCTAssertEqual(prefs.units.weightUnit, "lbs")
        XCTAssertEqual(prefs.units.distanceUnit, "miles")
        XCTAssertTrue(prefs.units.isPounds)
        XCTAssertTrue(prefs.units.isMiles)

        await prefs.restore()
        XCTAssertEqual(
            prefs.units,
            WatchUnitPreferences(weightUnit: "lbs", distanceUnit: "miles"),
            "the units survive a relaunch, read back out of storage"
        )
    }

    func testS3904ANewerCopyWithNoUnitsReadsAsKilogramsAndKilometres() async throws {
        let harness = Harness()
        let prefs = preferences(harness)
        let wire = try Fixtures.json("fixtures/valid/preferences_down_units.json")
        _ = await prefs.applyPreferencesDown(wire)

        var payload = try XCTUnwrap(wire["payload"] as? [String: Any])
        payload.removeValue(forKey: "weightUnit")
        payload.removeValue(forKey: "distanceUnit")
        payload["generatedAt"] = "2026-09-25T11:00:00Z"
        var plain = wire
        plain["messageId"] = "msg-preferences-units-absent"
        plain["payload"] = payload

        let applied = await prefs.applyPreferencesDown(plain)
        XCTAssertTrue(applied.applied, "the copy itself is understood")
        XCTAssertEqual(
            prefs.units,
            WatchUnitPreferences(),
            "a newer copy that names no unit does not keep the earlier copy's"
        )
    }

    func testS3904AUnitTheSchemaDoesNotKnowIsRefusedAndThePreviousOneStays() async throws {
        let harness = Harness()
        let prefs = preferences(harness)
        _ = await prefs.applyPreferencesDown(
            try Fixtures.json("fixtures/valid/preferences_down_units.json")
        )

        let refused = await prefs.applyPreferencesDown(
            try Fixtures.json("fixtures/invalid/preferences_down_units_bad.json")
        )

        XCTAssertFalse(refused.applied)
        XCTAssertFalse(refused.rejections.isEmpty)
        XCTAssertEqual(prefs.units.weightUnit, "lbs")
    }

    func testS3905TheRecordCarriesTheUnitsThroughItsOwnJson() throws {
        let record = WatchPreferencesRecord(
            recordId: "pref-units",
            recordedAt: instant("2026-10-14T10:00:00Z"),
            generatedAt: instant("2026-10-14T10:00:00Z"),
            effortRatingPrompt: false,
            restPingSeconds: 0,
            weightUnit: "lbs",
            distanceUnit: "miles"
        )

        let read = try WatchPreferencesRecord.fromJson(record.toJson())
        XCTAssertEqual(read.weightUnit, "lbs")
        XCTAssertEqual(read.distanceUnit, "miles")

        let bare = WatchPreferencesRecord(
            recordId: "pref-bare",
            recordedAt: instant("2026-10-14T10:00:00Z"),
            generatedAt: instant("2026-10-14T10:00:00Z"),
            effortRatingPrompt: false
        )
        XCTAssertNil(bare.toJson()["weightUnit"], "no unit sent, no key written")
        XCTAssertNil(try WatchPreferencesRecord.fromJson(bare.toJson()).distanceUnit)
    }

    func testS3905TheLoggingStateReadsTheUnitsAtEveryUse() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let prefs = preferences(harness)
        let state = WatchLoggingState(
            engine: engine,
            clock: harness.clock.call,
            unitsSource: { prefs.units }
        )
        XCTAssertFalse(state.units.isPounds, "before any sync the state reads kilograms")

        _ = await prefs.applyPreferencesDown(
            try Fixtures.json("fixtures/valid/preferences_down_units.json")
        )

        XCTAssertTrue(state.units.isPounds, "a sync that lands later is read, not a copy taken at launch")
        XCTAssertTrue(state.units.isMiles)
    }
}
