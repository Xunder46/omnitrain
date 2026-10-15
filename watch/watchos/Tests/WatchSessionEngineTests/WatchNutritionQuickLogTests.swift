//
//  WatchNutritionQuickLogTests.swift
//  WatchSessionEngineTests
//
//  The native watchOS half of
//  `docs/plans/2026-07-13-12-e-watch-nutrition-quick-log-plan.md` —
//  the same scenarios the Dart suite proves in
//  `test/watch_nutrition_quick_log_test.dart`, run against the Swift quick-log.
//
//  Two sources are read from the repository rather than restated here: the
//  protocol schemas and fixtures (so "conformant" is the schema's verdict) and
//  `watch/contract/watch_nutrition_contract.json`, the list the Wear OS suite is
//  held to as well. A rule that changes on one platform therefore fails the
//  other's tests.
//
//  "Phone offline" is simulated by giving the watch nothing but its own storage:
//  every offline claim is checked by rebuilding the watch over the same store
//  with no transport in sight.
//

import XCTest

@testable import WatchSessionEngine

final class WatchNutritionQuickLogTests: XCTestCase {

    // MARK: - Fixtures

    private func nutritionContract() throws -> [String: Any] {
        let url = Fixtures.repositoryRoot
            .appendingPathComponent("watch/contract/watch_nutrition_contract.json")
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(
                domain: "WatchNutritionQuickLogTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "malformed nutrition contract"]
            )
        }
        return object
    }

    private func foodsDownEnvelope() throws -> [String: Any] {
        try Fixtures.json("fixtures/valid/foods_down.json")
    }

    private func payload(_ envelope: [String: Any]) throws -> [String: Any] {
        guard let payload = envelope["payload"] as? [String: Any] else {
            throw NSError(
                domain: "WatchNutritionQuickLogTests",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "envelope has no payload"]
            )
        }
        return payload
    }

    private func strings(_ value: Any?) -> [String] {
        (value as? [String]) ?? []
    }

    private func ids(_ foods: [WatchFood]) -> [String] {
        foods.map(\.foodId)
    }

    private func ids(_ observations: [WatchObservationRecord]) -> [String] {
        observations.compactMap { $0.payload["foodId"] as? String }
    }

    // MARK: - The watch a user taps on

    /// A watch: one engine and its quick-log state, rebuilt over the same store
    /// to simulate a relaunch.
    private final class NutritionHarness {
        let clock: TestClock
        let store: WatchSessionStore
        let sessionId: String
        let transport = RecordingTransport()
        private(set) var emitted: [[String: Any]] = []
        private var ids = 0

        private(set) var engine: WatchSessionEngine!
        private(set) var nutrition: WatchNutritionState!
        private(set) var orchestrator: WatchSyncOrchestrator!

        init(
            store: WatchSessionStore = InMemoryWatchSessionStore(),
            sessionId: String = "s-watch-1"
        ) {
            self.clock = TestClock(testInstant())
            self.store = store
            self.sessionId = sessionId
            build()
        }

        /// A watch that has restored: engine first, then the synced food list,
        /// exactly as a launch would.
        @discardableResult
        func launch() async -> NutritionHarness {
            build()
            await engine.restore()
            await nutrition.restore()
            return self
        }

        private func build() {
            engine = WatchSessionEngine(
                store: store,
                onEmit: { [weak self] envelope in self?.emitted.append(envelope) },
                validator: Harness.validator(),
                clock: clock.call,
                idFactory: { [weak self] in
                    guard let self else { return UUID().uuidString }
                    self.ids += 1
                    return "rec-\(self.ids)"
                },
                sessionIdFactory: { [weak self] in self?.sessionId ?? "s-watch-1" }
            )
            nutrition = WatchNutritionState(
                engine: engine,
                store: store,
                validator: Harness.validator(),
                clock: clock.call
            )
            orchestrator = WatchSyncOrchestrator(
                transport: transport,
                paths: WatchSessionStartPaths(
                    engine: engine,
                    store: store,
                    validator: Harness.validator(),
                    clock: clock.call
                ),
                engine: engine,
                nutrition: nutrition
            )
        }

        /// The list a user sees once the phone has synced it.
        func syncFoods() async throws {
            let result = await nutrition.applyFoodsDown(try Self.envelope())
            XCTAssertTrue(result.applied)
        }

        static func envelope() throws -> [String: Any] {
            try Fixtures.json("fixtures/valid/foods_down.json")
        }

        /// Every message of `type` the watch emitted, in order.
        func emitted(_ type: String) -> [[String: Any]] {
            emitted.filter { $0["type"] as? String == type }
        }
    }

    // MARK: - S-001 quick-logging a food with the phone out of reach

    func testQuickLoggingPersistsTheObservationAndEmitsIt() async throws {
        let watch = await NutritionHarness().launch()
        try await watch.syncFoods()

        watch.nutrition.select("food-oatmeal")
        let record = try await watch.nutrition.logSelected()

        XCTAssertEqual(record.kind, WatchObservationKind.nutritionQuickLog)
        XCTAssertEqual(record.payload["foodId"] as? String, "food-oatmeal")
        XCTAssertEqual(record.payload["servings"] as? Double, 1.5)

        // 190 kcal a serving, logged at 1.5 servings.
        XCTAssertEqual(record.payload["calories"] as? Double, 285)
        XCTAssertEqual(record.payload["entryId"] as? String, record.payload["eventId"] as? String)

        let stored = await watch.store.readAll()
        XCTAssertTrue(
            stored.observations.contains { $0.recordId == record.recordId },
            "the log reached storage before anything was emitted"
        )

        let envelope = try XCTUnwrap(watch.emitted("observations_up").last)
        XCTAssertTrue(Harness.validator().validateEnvelope(envelope).isEmpty)
    }

    func testQuickLoggingNeedsNoSession() async throws {
        let watch = await NutritionHarness().launch()
        try await watch.syncFoods()

        watch.nutrition.select("food-banana")
        _ = try await watch.nutrition.logSelected()

        XCTAssertNil(watch.engine.session)
        let sessionId = try XCTUnwrap(
            watch.emitted("observations_up").last?["sessionId"] as? String
        )
        XCTAssertTrue(
            sessionId.hasPrefix(WatchNutritionSession.prefix),
            "a standalone quick-log carries the nutrition log's own id"
        )
    }

    func testTheSurfaceSaysWhatItJustLogged() async throws {
        let watch = await NutritionHarness().launch()
        try await watch.syncFoods()

        watch.nutrition.select("food-banana")
        _ = try await watch.nutrition.logSelected()

        let confirmation = try XCTUnwrap(watch.nutrition.confirmation)
        XCTAssertTrue(confirmation.contains("Banana"))
    }

    // MARK: - S-002 the phone applies a quick-log exactly once

    func testAReplayedEventMaterialisesOneEntry() async throws {
        let watch = await NutritionHarness().launch()
        try await watch.syncFoods()

        watch.nutrition.select("food-oatmeal")
        let record = try await watch.nutrition.logSelected()
        let envelope = try XCTUnwrap(watch.emitted("observations_up").last)
        let events = try XCTUnwrap(
            try payload(envelope)["events"] as? [[String: Any]]
        )
        let event = try XCTUnwrap(events.first)

        // The phone deduplicates on `entryId` — `eventId` is the delivery key and
        // `entryId` the entry's identity — so the event the phone materialises
        // carries the wrist's own row id, and re-delivery is the same entry.
        XCTAssertEqual(events.count, 1, "one event per log")
        XCTAssertEqual(event["entryId"] as? String, record.recordId)
        XCTAssertEqual(event["eventId"] as? String, record.recordId)
        XCTAssertEqual(
            event["kind"] as? String,
            WatchObservationKind.nutritionQuickLog
        )
        XCTAssertEqual(event["foodId"] as? String, "food-oatmeal")
        XCTAssertEqual(event["servings"] as? Double, 1.5)
        XCTAssertEqual(event["calories"] as? Double, 285)
    }

    func testThePhonesReceiptIsWhatLetsTheWatchDropTheRow() async throws {
        let watch = await NutritionHarness().launch()
        try await watch.syncFoods()

        watch.nutrition.select("food-egg")
        let record = try await watch.nutrition.logSelected()
        XCTAssertEqual(
            watch.engine.pendingObservations().count,
            1,
            "a log with no session owes the phone a message"
        )

        // The receipt the phone sends, read from the schema set the watch
        // judges with — a receipt nobody sends is what let this row be owed
        // forever.
        let receipt = try receiptEnvelope(
            entryIds: [record.entryId],
            messageId: "msg-receipt-1"
        )
        let applied = try await watch.orchestrator.receive(receipt)

        XCTAssertTrue(applied, "the receipt names a row the watch holds")
        XCTAssertTrue(
            watch.engine.pendingObservations().isEmpty,
            "nothing is owed once the phone has taken responsibility for it"
        )
        let pruned = await watch.engine.pruneConfirmed()
        XCTAssertTrue(pruned.contains(record.recordId))
    }

    /// The phone's receipt for `entryIds`, exactly as the phone side builds it.
    private func receiptEnvelope(
        entryIds: [String],
        messageId: String
    ) throws -> [String: Any] {
        [
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": messageId,
            "type": "receipt",
            "origin": "phone",
            "sentAt": utcIso(testInstant()),
            "payload": ["entryIds": entryIds],
        ]
    }

    func testAReceiptForARowTheWatchDoesNotHoldChangesNothing() async throws {
        let watch = await NutritionHarness().launch()

        let applied = try await watch.orchestrator.receive(
            receiptEnvelope(entryIds: ["e-never-logged"], messageId: "msg-receipt-2")
        )

        XCTAssertFalse(applied, "nothing the watch holds was acknowledged")
    }

    // MARK: - S-003 frequents / favorites parity with the phone

    func testTheWristDerivesTheContractsOrder() async throws {
        let contract = try nutritionContract()
        let watch = await NutritionHarness().launch()
        try await watch.syncFoods()

        XCTAssertEqual(
            ids(watch.nutrition.foods),
            strings(contract["phoneOrder"]),
            "with nothing logged yet, the wrist shows the phone's order"
        )

        let recent = try XCTUnwrap(contract["recentlyLoggedFoodIds"] as? [String: Any])
        // Logged oldest first, as a user would: the list keeps the newest on top.
        for foodId in strings(recent["ids"]).reversed() {
            watch.nutrition.select(foodId)
            _ = try await watch.nutrition.logSelected()
        }

        XCTAssertEqual(
            ids(watch.nutrition.foods),
            strings(contract["expected"]),
            "what the wrist logs moves to the front, in recency order"
        )
    }

    func testASyncedFoodCarriesWhatTheWristPrintsAndLogs() async throws {
        let watch = await NutritionHarness().launch()
        try await watch.syncFoods()

        let oatmeal = try XCTUnwrap(watch.nutrition.food("food-oatmeal"))
        XCTAssertEqual(oatmeal.name, "Oatmeal")
        XCTAssertEqual(oatmeal.referenceAmount, 100)
        XCTAssertEqual(oatmeal.referenceLabel, "g")
        XCTAssertEqual(oatmeal.calories(at: 1.5), 285)
    }

    func testAnOlderViewOfTheListIsNotANewerTruth() async throws {
        let watch = await NutritionHarness().launch()
        try await watch.syncFoods()

        var older = try NutritionHarness.envelope()
        older["messageId"] = "msg-foods-0"
        older["sentAt"] = "2026-07-13T16:00:00Z"
        var body = try payload(older)
        body["generatedAt"] = "2026-07-13T16:00:00Z"
        body["foods"] = [
            [
                "foodId": "food-toast",
                "name": "Toast",
                "categoryId": NSNull(),
                "referenceAmount": 1,
                "referenceLabel": "slice",
                "caloriesPerServing": 80,
                "defaultServings": 1,
            ]
        ]
        older["payload"] = body

        let result = await watch.nutrition.applyFoodsDown(older)

        XCTAssertFalse(result.applied)
        XCTAssertTrue(
            result.rejections.isEmpty,
            "understood and dropped is not a rejection"
        )
        XCTAssertNil(watch.nutrition.food("food-toast"))
        XCTAssertNotNil(watch.nutrition.food("food-oatmeal"))
    }

    func testAMessageTheWristCannotReadIsRefusedWhole() async throws {
        let watch = await NutritionHarness().launch()
        try await watch.syncFoods()

        let result = await watch.nutrition.applyFoodsDown(["type": "foods_down"])

        XCTAssertFalse(result.applied)
        XCTAssertFalse(result.rejections.isEmpty)
        XCTAssertNotNil(watch.nutrition.food("food-oatmeal"))
    }

    func testTheOrchestratorRoutesASyncedListToTheSurface() async throws {
        let watch = await NutritionHarness().launch()

        let applied = try await watch.orchestrator.receive(try NutritionHarness.envelope())

        XCTAssertTrue(applied)
        XCTAssertEqual(
            ids(watch.nutrition.foods),
            strings(try nutritionContract()["phoneOrder"])
        )
    }

    // MARK: - S-004 portion adjustment changes the logged quantity

    func testADetentMovesThePortionByTheContractsStep() async throws {
        let portion = try XCTUnwrap(
            try nutritionContract()["portion"] as? [String: Any]
        )
        let watch = await NutritionHarness().launch()
        try await watch.syncFoods()

        watch.nutrition.select("food-oatmeal")
        let before = watch.nutrition.servings
        watch.nutrition.stepPortion(1)

        XCTAssertEqual(
            watch.nutrition.servings - before,
            portion["stepServings"] as? Double
        )

        watch.nutrition.stepPortion(-1)
        XCTAssertEqual(watch.nutrition.servings, before)
    }

    func testTheLoggedPortionIsTheAdjustedQuantity() async throws {
        let watch = await NutritionHarness().launch()
        try await watch.syncFoods()

        watch.nutrition.select("food-oatmeal")
        watch.nutrition.stepPortion(1) // 1.5 → 2.0
        let record = try await watch.nutrition.logSelected()

        XCTAssertEqual(record.payload["servings"] as? Double, 2)
        XCTAssertEqual(record.payload["calories"] as? Double, 380)
        XCTAssertTrue(
            Harness.validator().validateEnvelope(
                try XCTUnwrap(watch.emitted("observations_up").last)
            ).isEmpty
        )
    }

    func testThePortionStaysInsideTheContractsBounds() async throws {
        let portion = try XCTUnwrap(
            try nutritionContract()["portion"] as? [String: Any]
        )
        let watch = await NutritionHarness().launch()
        try await watch.syncFoods()

        watch.nutrition.select("food-oatmeal")
        watch.nutrition.stepPortion(-99)
        XCTAssertEqual(
            watch.nutrition.servings,
            portion["minServings"] as? Double
        )

        watch.nutrition.stepPortion(999)
        XCTAssertEqual(
            watch.nutrition.servings,
            portion["maxServings"] as? Double
        )
    }

    func testANewSelectionStartsFromThatFoodsOwnPortion() async throws {
        let watch = await NutritionHarness().launch()
        try await watch.syncFoods()

        watch.nutrition.select("food-oatmeal")
        watch.nutrition.stepPortion(2)
        watch.nutrition.select("food-egg")

        XCTAssertEqual(watch.nutrition.servings, 2)
        XCTAssertEqual(watch.nutrition.selected?.foodId, "food-egg")
    }

    // MARK: - S-005 a quick-log survives a kill before sync

    func testARelaunchRestoresTheEntryAndDeliversItLater() async throws {
        let watch = await NutritionHarness().launch()
        try await watch.syncFoods()

        watch.nutrition.select("food-greek-yogurt")
        let record = try await watch.nutrition.logSelected()

        // The kill: a fresh engine and a fresh state over the same storage.
        let relaunched = await NutritionHarness(store: watch.store).launch()

        let pending = relaunched.engine.pendingObservations()
        XCTAssertEqual(
            pending.count,
            1,
            "the unacknowledged log is rebuilt from storage"
        )
        let events = try XCTUnwrap(
            try payload(pending[0])["events"] as? [[String: Any]]
        )
        XCTAssertEqual(events.first?["entryId"] as? String, record.recordId)
        XCTAssertEqual(events.first?["foodId"] as? String, "food-greek-yogurt")

        try await relaunched.orchestrator.sync()

        XCTAssertTrue(
            relaunched.transport.sent.contains { $0["type"] as? String == "observations_up" },
            "the phone is handed the log it never received"
        )
        XCTAssertEqual(
            ids(relaunched.engine.nutritionLog),
            ["food-greek-yogurt"]
        )
    }

    func testALogTakenMidSessionTravelsWithTheSession() async throws {
        let watch = await NutritionHarness().launch()
        try await watch.syncFoods()

        _ = try await watch.engine.createSession(modality: "resistance_lifting")
        watch.nutrition.select("food-almonds")
        let record = try await watch.nutrition.logSelected()

        XCTAssertEqual(
            record.sessionId,
            try XCTUnwrap(watch.engine.session).sessionId,
            "eating during a session is part of that session"
        )
        XCTAssertTrue(
            watch.engine.entries.contains { $0.recordId == record.recordId }
        )
    }

    // MARK: - S-006 the surface needs no session

    func testTheSurfaceIsReachableAndLogsWithNoSession() async throws {
        let watch = await NutritionHarness().launch()
        try await watch.syncFoods()

        XCTAssertNil(watch.engine.session, "no workout is running")

        watch.nutrition.select("food-oatmeal")
        XCTAssertEqual(watch.nutrition.portionLabel, "1.5 × 100 g")
        XCTAssertEqual(watch.nutrition.calories, 285)

        let record = try await watch.nutrition.logSelected()

        XCTAssertEqual(
            ids(watch.engine.nutritionLog),
            ["food-oatmeal"],
            "the surface logs with nothing else running"
        )
        XCTAssertEqual(record.sessionId, WatchNutritionSession.idFor(watch.clock.now))
    }

    func testWithNothingSyncedTheSurfaceOffersNothing() async throws {
        let watch = await NutritionHarness().launch()

        XCTAssertTrue(watch.nutrition.foods.isEmpty)
        XCTAssertNil(watch.nutrition.selected)

        do {
            _ = try await watch.nutrition.logSelected()
            XCTFail("a log with nothing selected must be refused")
        } catch is WatchNutritionError {
            // The expected refusal: a food the user did not pick is not a food
            // they ate.
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testLoggingConsultsNoPermission() async throws {
        // No sensor recorder is injected anywhere on this path — nutrition
        // logging requires no Motion & Fitness or Health permission to work.
        let watch = await NutritionHarness().launch()
        try await watch.syncFoods()

        watch.nutrition.select("food-egg")
        _ = try await watch.nutrition.logSelected()

        XCTAssertEqual(watch.engine.nutritionLog.count, 1)
    }

    // MARK: - Protocol serialization

    func testTheEventMatchesTheShapeTheProtocolFixturePins() async throws {
        let fixture = try Fixtures.json("fixtures/valid/observations_up.json")
        let events = try XCTUnwrap(try payload(fixture)["events"] as? [[String: Any]])
        let fixtureEvent = try XCTUnwrap(
            events.first { $0["kind"] as? String == WatchObservationKind.nutritionQuickLog }
        )

        let watch = await NutritionHarness().launch()
        try await watch.syncFoods()
        watch.nutrition.select("food-oatmeal")
        let record = try await watch.nutrition.logSelected()

        XCTAssertEqual(
            Set(record.payload.keys),
            Set(fixtureEvent.keys),
            "the wrist adds no field the fixture does not carry"
        )
    }

    func testTheKindsTheWristCanEmitAreAClosedSet() {
        XCTAssertEqual(
            Set(WatchObservationKind.all),
            Set([
                "set", "timed", "round", "hold", WatchObservationKind.nutritionQuickLog,
                "effort_rating", "session_end", WatchObservationKind.rest,
            ]),
            "what the phone can be sent is a list, not whatever a client happens to spell"
        )
        XCTAssertFalse(
            WatchObservationKind.efforts.contains(WatchObservationKind.rest),
            "a rest records no work in a slot, so it is never an effort entry"
        )
    }
}
