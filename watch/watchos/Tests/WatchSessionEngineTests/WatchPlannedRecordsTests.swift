//
//  WatchPlannedRecordsTests.swift
//  WatchSessionEngineTests
//
//  S-8966 (plan 129): the wrist keeps the newest planned-session list, an older
//  one is dropped without a write, a relaunch reads the newest back out of
//  storage, and a frame the validator rejects is refused before anything is
//  stored. The dates derive from a runner-local 2026-11-05 at run time — no
//  hard-coded epoch milliseconds.
//

import XCTest

@testable import WatchSessionEngine

// MARK: - Shared planned-session fixtures (used by the start-paths tests too)

/// The runner's local 2026-11-05, plus `offset` days (plan 129 Scenarios).
func plannedDay(_ offset: Int = 0) -> Date {
    var components = DateComponents()
    components.year = 2026
    components.month = 11
    components.day = 5
    let base = Calendar.current.date(from: components)!
    return Calendar.current.date(byAdding: .day, value: offset, to: base) ?? base
}

/// An instant later on `plannedDay()`, named by the runner's own clock.
func plannedHour(_ hour: Int) -> Date {
    Calendar.current.date(byAdding: .hour, value: hour, to: plannedDay()) ?? plannedDay()
}

func milliseconds(_ date: Date) -> Int {
    Int(date.timeIntervalSince1970 * 1000)
}

struct PlannedRow {
    let id: String
    let name: String
    let scheduledMs: Int
    let templateId: String?
    let modality: String?
}

func planRow(
    _ id: String,
    _ name: String,
    on day: Date,
    templateId: String? = nil,
    modality: String? = nil
) -> PlannedRow {
    PlannedRow(
        id: id,
        name: name,
        scheduledMs: milliseconds(day),
        templateId: templateId,
        modality: modality
    )
}

/// A schema-conformant `planned_down` with the given plans (plan 129, D-8961).
/// A conformant frame by construction: the tests assert the validator's own
/// verdict on the baseline shape once, so a drift here fails loudly.
func plannedDown(
    generatedAt: Date,
    _ rows: [PlannedRow],
    messageId: String = "msg-planned-down-1"
) -> [String: Any] {
    [
        "protocolVersion": 1,
        "messageId": messageId,
        "type": "planned_down",
        "origin": "phone",
        "sentAt": utcIso(generatedAt),
        "payload": [
            "generatedAt": utcIso(generatedAt),
            "plans": rows.map { row in
                var plan: [String: Any] = [
                    "plannedSessionId": row.id,
                    "name": row.name,
                    "scheduledDateMs": row.scheduledMs,
                    "createdAtMs": planRowCreatedAt(row),
                    "updatedAtMs": planRowUpdatedAt(row),
                ]
                if let templateId = row.templateId { plan["routineTemplateId"] = templateId }
                if let modality = row.modality { plan["modality"] = modality }
                return plan
            },
        ] as [String: Any],
    ]
}

private func planRowCreatedAt(_ row: PlannedRow) -> Int {
    max(0, row.scheduledMs - 3_600_000)
}

private func planRowUpdatedAt(_ row: PlannedRow) -> Int {
    row.scheduledMs
}

/// A wrist clocked inside 2026-11-05, its own local today (plan 129 D-8963).
private func plannedHarness(store: WatchSessionStore = InMemoryWatchSessionStore())
    async -> WatchStartHarness
{
    let harness = WatchStartHarness(store: store)
    harness.clock.now = plannedHour(13)
    return harness
}

final class WatchPlannedRecordsTests: XCTestCase {

    // MARK: - S-8966 the wrist keeps the newest list

    func testS8966TheNewestRowWinsAndAnOlderOneIsFetchedNoMore() async throws {
        let harness = await plannedHarness()
        let newest = plannedDown(
            generatedAt: plannedHour(12),
            [
                planRow("p-a", "Push", on: plannedDay()),
                planRow("p-b", "Free", on: plannedDay(), templateId: nil),
            ]
        )
        let older = plannedDown(
            generatedAt: plannedHour(9),
            [
                planRow("p-c", "Older Push", on: plannedDay()),
                planRow("p-d", "Older Free", on: plannedDay(), modality: "sports"),
            ]
        )

        XCTAssertTrue(Harness.validator().validateEnvelope(newest).isEmpty)
        let firstApplied = try await harness.receive(newest)
        let olderApplied = try await harness.receive(older)
        XCTAssertTrue(firstApplied, "the first view applies")
        XCTAssertFalse(olderApplied, "an older view is dropped")

        let contents = await harness.store.readAll()
        XCTAssertEqual(
            contents.plannedCatalogs.compactMap { try? WatchPlannedDown(catalog: $0).plans }
                .flatMap { $0.map(\.plannedSessionId) },
            ["p-a", "p-b"],
            "the log holds the same view rows, and no older one"
        )
        XCTAssertEqual(contents.routineCatalogs.count, 0, "the plans keep their own rows")
    }

    func testS8966AnUnreadableStoredRowOffersNoPlan() async throws {
        // Plan 129 review 1, finding 3: a stored row the read cannot parse
        // leaves no plans in memory — at a relaunch and right after a sync,
        // which both go through the same rule.
        let store = InMemoryWatchSessionStore()
        _ = await store.append(
            .plannedCatalog(
                WatchPlannedCatalogRecord(
                    recordId: "planned-corrupt",
                    recordedAt: plannedHour(8),
                    generatedAt: plannedHour(8),
                    plans: [["plannedSessionId": "p-corrupt"]]
                )
            )
        )

        let relaunch = await plannedHarness(store: store)
        await relaunch.launch()
        XCTAssertEqual(
            relaunch.paths.startablePlannedSessions.map(\.plannedSessionId),
            [],
            "a relaunch offers nothing from a row it cannot read"
        )
        let restoredRows = await store.readAll()
        XCTAssertEqual(
            restoredRows.plannedCatalogs.count,
            1,
            "the unreadable row is in the store the relaunch read"
        )

        // Each arm gets a row of its own, so one check cannot hide the other:
        // the live harness writes a readable row first and then an unreadable
        // one, and the surface must offer nothing from the second.
        let live = await plannedHarness(store: store)
        await live.launch()
        let applied = try await live.receive(
            plannedDown(
                generatedAt: plannedHour(10),
                [planRow("p-written", "Written push", on: plannedDay())]
            )
        )
        XCTAssertTrue(applied)
        XCTAssertEqual(
            live.paths.startablePlannedSessions.map(\.plannedSessionId),
            ["p-written"],
            "a sync offers the row it just wrote"
        )
        let storedRows = await store.readAll()
        let readable = try XCTUnwrap(storedRows.plannedCatalogs.last)
        var unreadableJson = readable.toJson()
        unreadableJson["recordId"] = "planned-corrupt-after-sync"
        unreadableJson["plans"] = [["plannedSessionId": "p-corrupt-after-sync"]]
        _ = await store.append(try StoredWatchRecord.fromJson(unreadableJson))
        XCTAssertEqual(
            live.paths.startablePlannedSessions.map(\.plannedSessionId),
            ["p-written"],
            "the rows the store holds do not change the memory until a sync reads them"
        )
    }

    func testS8966ARelaunchRestoresTheNewestListOfPlans() async throws {
        let store = InMemoryWatchSessionStore()
        let first = await plannedHarness(store: store)
        let morningApplied = try await first.receive(
            plannedDown(
                generatedAt: plannedHour(8),
                [planRow("p-morning", "Hill sprints", on: plannedDay())]
            )
        )
        XCTAssertTrue(morningApplied)
        let eveningApplied = try await first.receive(
            plannedDown(
                generatedAt: plannedHour(16),
                [planRow("p-latest", "Evening push", on: plannedDay())]
            )
        )
        XCTAssertTrue(eveningApplied)

        let second = await plannedHarness(store: store)
        await second.launch()

        XCTAssertEqual(
            second.paths.startablePlannedSessions.map(\.plannedSessionId),
            ["p-latest"],
            "the newest row, not the first one the phone ever sent"
        )
    }

    // MARK: - S-8966 a frame the validator refuses is refused before storing

    func testS8966AWatchOriginFrameIsRefusedWithNothingStored() async throws {
        let harness = await plannedHarness()
        let frame = try Fixtures.json("fixtures/invalid/planned_down_watch_origin.json")

        let applied = try await harness.receive(frame)

        XCTAssertFalse(applied)
        let contents = await harness.store.readAll()
        XCTAssertTrue(contents.plannedCatalogs.isEmpty, "nothing was appended")
    }

    func testS8966AnUnknownFieldIsRefusedWithNothingStored() async throws {
        let harness = await plannedHarness()
        var frame = plannedDown(
            generatedAt: plannedHour(10),
            [planRow("p-x", "Push", on: plannedDay(), templateId: "tpl-push-a")]
        )
        frame["payload"] = [
            "generatedAt": utcIso(plannedHour(10)),
            "plans": [[
                "plannedSessionId": "p-x",
                "name": "Push",
                "scheduledDateMs": milliseconds(plannedDay()),
                "createdAtMs": milliseconds(plannedDay()),
                "updatedAtMs": milliseconds(plannedDay()),
                "routineTemplateId": "tpl-push-a",
            ]] as [[String: Any]],
            "plansMeta": "a field the schema does not know",
        ]

        let applied = try await harness.receive(frame)

        XCTAssertFalse(applied)
        let contents = await harness.store.readAll()
        XCTAssertTrue(contents.plannedCatalogs.isEmpty, "nothing was appended")
    }

    // MARK: - the stored row round-trips through the file format

    func testPlannedCatalogRecordRoundTripsThroughJson() throws {
        let row = try WatchPlannedDown(
            envelope: plannedDown(
                generatedAt: plannedHour(9),
                [
                    planRow("p-file", "Saved", on: plannedDay(), templateId: "tpl-push-a"),
                ]
            )
        ).toRecord(recordId: "plc-1", recordedAt: plannedHour(9)).withSequence(3)

        let restored = try WatchPlannedCatalogRecord.fromJson(row.toJson())

        XCTAssertEqual(restored.recordId, "plc-1")
        XCTAssertEqual(restored.sessionId, "", "a catalog row belongs to the watch")
        XCTAssertEqual(restored.sequence, 3)
        XCTAssertEqual(restored.toJson()["recordType"] as? String, "planned_catalog")
        let plans = try WatchPlannedDown(catalog: restored).plans
        XCTAssertEqual(plans.first?.plannedSessionId, "p-file")
        XCTAssertEqual(plans.first?.name, "Saved")
        XCTAssertEqual(plans.first?.routineTemplateId, "tpl-push-a")
        XCTAssertEqual(plans.first?.modality, nil)
    }

    func testStoredWatchRecordKnowsThePlannedCatalogFamily() throws {
        let record = StoredWatchRecord.plannedCatalog(
            WatchPlannedCatalogRecord(
                recordId: "plc-2",
                recordedAt: plannedHour(9),
                generatedAt: plannedHour(9)
            )
        )

        XCTAssertEqual(record.recordType, StoredWatchRecord.plannedCatalogType)
        XCTAssertEqual(record.recordId, "plc-2")
        XCTAssertEqual(record.sessionId, "")
        XCTAssertEqual(record.plannedCatalogRow?.recordId, "plc-2")
    }
}
