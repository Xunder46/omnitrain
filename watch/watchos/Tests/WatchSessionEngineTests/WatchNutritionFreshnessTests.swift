//
//  WatchNutritionFreshnessTests.swift
//  WatchSessionEngineTests
//
//  Phase P2 of
//  `docs/plans/2026-10-22-53-watch-food-screen-and-fresh-foods-plan/`:
//  leaving a food clears the selection (D-1), a wrist log newer than the list
//  the phone sent becomes that food's starting amount (D-2), and the surface is
//  told when the foods it shows have changed (D-3).
//
//  The harness is the quick-log suite's own: one engine and its state over an
//  in-memory store, rebuilt over the same store to simulate a relaunch. The
//  `foods_down` envelopes are built from the shared fixture and re-dated, the
//  way the quick-log suite's older-list test builds them, so the catalog's
//  `generatedAt` can sit on either side of a log taken at the test instant.
//

import XCTest

@testable import WatchSessionEngine

final class WatchNutritionFreshnessTests: XCTestCase {

    // MARK: - Fixtures

    /// The test clock's instant — 2026-07-13T06:00:00Z — as the envelopes date
    /// their lists: one before it, one after it.
    private static let catalogBeforeTheLog = "2026-07-13T05:00:00Z"
    private static let catalogAfterTheLog = "2026-07-13T07:00:00Z"

    private func payload(_ envelope: [String: Any]) throws -> [String: Any] {
        guard let payload = envelope["payload"] as? [String: Any] else {
            throw NSError(
                domain: "WatchNutritionFreshnessTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "envelope has no payload"]
            )
        }
        return payload
    }

    /// A `foods_down` the validator accepts, generated at `generatedAt` with
    /// exactly `foods`.
    private func foodsDown(
        generatedAt: String,
        messageId: String,
        foods: [[String: Any]]
    ) throws -> [String: Any] {
        var envelope = try Fixtures.json("fixtures/valid/foods_down.json")
        envelope["messageId"] = messageId
        envelope["sentAt"] = generatedAt
        var body = try payload(envelope)
        body["generatedAt"] = generatedAt
        body["categories"] = []
        body["foods"] = foods
        envelope["payload"] = body
        return envelope
    }

    private func food(
        _ foodId: String,
        _ name: String,
        defaultServings: Double
    ) -> [String: Any] {
        [
            "foodId": foodId,
            "name": name,
            "categoryId": NSNull(),
            "referenceAmount": 100,
            "referenceLabel": "g",
            "caloriesPerServing": 100,
            "defaultServings": defaultServings,
        ]
    }

    private func ids(_ foods: [WatchFood]) -> [String] { foods.map(\.foodId) }

    /// Applies `envelope` and asserts the state took it: `await` cannot sit in
    /// XCTest's autoclosure.
    private func expectApplied(
        _ envelope: [String: Any],
        to watch: NutritionHarness,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let result = await watch.nutrition.applyFoodsDown(envelope)
        XCTAssertTrue(result.applied, file: file, line: line)
    }

    // MARK: - The watch a user taps on

    /// A watch: one engine and its quick-log state, rebuilt over the same store
    /// to simulate a relaunch. The quick-log suite's harness, without the parts
    /// these scenarios do not reach.
    private final class NutritionHarness {
        let store: WatchSessionStore
        private(set) var engine: WatchSessionEngine!
        private(set) var nutrition: WatchNutritionState!

        init(store: WatchSessionStore = InMemoryWatchSessionStore()) {
            self.store = store
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
            let clock = TestClock(testInstant())
            var ids = 0
            engine = WatchSessionEngine(
                store: store,
                onEmit: { _ in },
                validator: Harness.validator(),
                clock: clock.call,
                idFactory: {
                    ids += 1
                    return "rec-\(ids)"
                },
                sessionIdFactory: { "s-watch-1" }
            )
            nutrition = WatchNutritionState(
                engine: engine,
                store: store,
                validator: Harness.validator(),
                clock: clock.call
            )
        }
    }

    /// Counts what the state announces, the way a view model's observer would.
    private final class ChangeCounter {
        private(set) var count = 0
        func record() { count += 1 }
    }

    // MARK: - S-8301 leaving a food clears the selection

    func testS8301LeavingAFoodClearsItAndTheNextOneOpensAtItsOwnAmount() async throws {
        let watch = await NutritionHarness().launch()
        let list = try foodsDown(
            generatedAt: Self.catalogBeforeTheLog,
            messageId: "msg-foods-8301",
            foods: [
                food("food-a", "Apple", defaultServings: 2),
                food("food-b", "Bread", defaultServings: 1),
            ]
        )
        await expectApplied(list, to: watch)

        watch.nutrition.select("food-a")
        watch.nutrition.stepPortion(3)
        // 2 servings plus three detents.
        XCTAssertEqual(watch.nutrition.servings, 3.5)

        watch.nutrition.deselect()

        XCTAssertNil(watch.nutrition.selected)
        XCTAssertEqual(watch.nutrition.servings, WatchNutritionPortion.minServings)
        XCTAssertNil(watch.nutrition.confirmation)

        watch.nutrition.select("food-b")

        XCTAssertEqual(watch.nutrition.servings, 1)
    }

    // MARK: - S-8302 a log becomes that food's starting amount

    func testS8302ALogBecomesTheFoodsStartingAmount() async throws {
        let watch = await NutritionHarness().launch()
        let list = try foodsDown(
            generatedAt: Self.catalogBeforeTheLog,
            messageId: "msg-foods-8302",
            foods: [food("food-a", "Apple", defaultServings: 1)]
        )
        await expectApplied(list, to: watch)

        watch.nutrition.select("food-a")
        watch.nutrition.stepPortion(4)
        XCTAssertEqual(watch.nutrition.servings, 3)
        try await watch.nutrition.logSelected()

        XCTAssertEqual(watch.nutrition.food("food-a")?.defaultServings, 3)
        let row = try XCTUnwrap(watch.nutrition.foods.first { $0.foodId == "food-a" })
        XCTAssertEqual(row.defaultServings, 3)

        watch.nutrition.deselect()
        watch.nutrition.select("food-a")

        XCTAssertEqual(watch.nutrition.servings, 3)
    }

    // MARK: - S-8303 the phone's newer list wins; an older one cannot revert a log

    func testS8303ANewerListWinsAndAnOlderOneDoesNotRevertALog() async throws {
        let watch = await NutritionHarness().launch()
        let before = try foodsDown(
            generatedAt: Self.catalogBeforeTheLog,
            messageId: "msg-foods-8303-a",
            foods: [food("food-a", "Apple", defaultServings: 1)]
        )
        await expectApplied(before, to: watch)

        watch.nutrition.select("food-a")
        watch.nutrition.stepPortion(4) // 1 → 3
        try await watch.nutrition.logSelected()

        // Generated before the log, so the wrist's own amount stands.
        let older = try foodsDown(
            generatedAt: "2026-07-13T05:30:00Z",
            messageId: "msg-foods-8303-b",
            foods: [food("food-a", "Apple", defaultServings: 1)]
        )
        await expectApplied(older, to: watch)
        XCTAssertEqual(watch.nutrition.food("food-a")?.defaultServings, 3)

        // Generated after the log: it carries the phone's own last amount.
        let newer = try foodsDown(
            generatedAt: "2026-07-13T06:30:00Z",
            messageId: "msg-foods-8303-c",
            foods: [food("food-a", "Apple", defaultServings: 2)]
        )
        await expectApplied(newer, to: watch)
        XCTAssertEqual(watch.nutrition.food("food-a")?.defaultServings, 2)
    }

    // MARK: - S-8304 a relaunch keeps the derived amount

    func testS8304ARelaunchKeepsTheDerivedStartingAmount() async throws {
        let watch = await NutritionHarness().launch()
        let list = try foodsDown(
            generatedAt: Self.catalogBeforeTheLog,
            messageId: "msg-foods-8304",
            foods: [food("food-a", "Apple", defaultServings: 1)]
        )
        await expectApplied(list, to: watch)

        watch.nutrition.select("food-a")
        watch.nutrition.stepPortion(4) // 1 → 3
        try await watch.nutrition.logSelected()

        let relaunched = await NutritionHarness(store: watch.store).launch()

        XCTAssertEqual(relaunched.nutrition.food("food-a")?.defaultServings, 3)
        XCTAssertEqual(ids(relaunched.nutrition.foods), ["food-a"])
    }

    // MARK: - S-8305 the surface is told when the foods change

    func testS8305FoodChangesAreAnnouncedOnlyWhenTheListChanges() async throws {
        let watch = await NutritionHarness().launch()
        let changes = ChangeCounter()
        watch.nutrition.onFoodsChanged = { changes.record() }
        XCTAssertEqual(changes.count, 0)

        let applied = try foodsDown(
            generatedAt: Self.catalogBeforeTheLog,
            messageId: "msg-foods-8305-a",
            foods: [food("food-a", "Apple", defaultServings: 1)]
        )
        await expectApplied(applied, to: watch)
        XCTAssertEqual(changes.count, 1, "an applied list announces once")

        // Understood and dropped: nothing shown changed.
        let dropped = try foodsDown(
            generatedAt: "2026-07-13T04:00:00Z",
            messageId: "msg-foods-8305-b",
            foods: [food("food-a", "Apple", defaultServings: 1)]
        )
        let droppedResult = await watch.nutrition.applyFoodsDown(dropped)
        XCTAssertFalse(droppedResult.applied)
        XCTAssertEqual(changes.count, 1, "a dropped list announces nothing")

        // Refused by the validator: the payload was never read.
        let refused = await watch.nutrition.applyFoodsDown(["type": "foods_down"])
        XCTAssertFalse(refused.applied)
        XCTAssertFalse(refused.rejections.isEmpty)
        XCTAssertEqual(changes.count, 1, "a refused message announces nothing")

        await watch.nutrition.restore()
        XCTAssertEqual(changes.count, 2, "a restore announces what storage holds")

        watch.nutrition.select("food-a")
        try await watch.nutrition.logSelected()
        XCTAssertEqual(changes.count, 3, "a log is a new starting amount")
    }

    // MARK: - S-8306 the catalog wins when it is newer than the log

    func testS8306ALogOlderThanTheCatalogKeepsTheCatalogsAmount() async throws {
        let watch = await NutritionHarness().launch()
        let list = try foodsDown(
            generatedAt: Self.catalogAfterTheLog,
            messageId: "msg-foods-8306",
            foods: [food("food-a", "Apple", defaultServings: 1)]
        )
        await expectApplied(list, to: watch)

        watch.nutrition.select("food-a")
        watch.nutrition.stepPortion(4) // 1 → 3, logged before the list was generated
        try await watch.nutrition.logSelected()

        XCTAssertEqual(watch.nutrition.food("food-a")?.defaultServings, 1)

        watch.nutrition.deselect()
        watch.nutrition.select("food-a")
        XCTAssertEqual(watch.nutrition.servings, 1)
    }

    // MARK: - S-8313 leaving nothing changes nothing

    func testS8313DeselectingNothingChangesNothing() async throws {
        let watch = await NutritionHarness().launch()
        XCTAssertTrue(watch.nutrition.foods.isEmpty)

        watch.nutrition.deselect()

        XCTAssertNil(watch.nutrition.selected)
        XCTAssertEqual(watch.nutrition.servings, WatchNutritionPortion.minServings)
        XCTAssertNil(watch.nutrition.confirmation)

        // After a real one, a second is still a no-op.
        let list = try foodsDown(
            generatedAt: Self.catalogBeforeTheLog,
            messageId: "msg-foods-8313",
            foods: [food("food-a", "Apple", defaultServings: 2)]
        )
        await expectApplied(list, to: watch)
        watch.nutrition.select("food-a")
        watch.nutrition.stepPortion(2)
        watch.nutrition.deselect()

        let afterFirst = watch.nutrition.servings
        watch.nutrition.deselect()

        XCTAssertNil(watch.nutrition.selected)
        XCTAssertEqual(watch.nutrition.servings, afterFirst)
        XCTAssertNil(watch.nutrition.confirmation)
    }

    // MARK: - S-8314 a list that drops the selected food clears the selection

    func testS8314ANewerListThatDropsTheSelectedFoodClearsTheSelection() async throws {
        let watch = await NutritionHarness().launch()
        let both = try foodsDown(
            generatedAt: Self.catalogBeforeTheLog,
            messageId: "msg-foods-8314-a",
            foods: [
                food("food-a", "Apple", defaultServings: 1),
                food("food-b", "Bread", defaultServings: 2),
            ]
        )
        await expectApplied(both, to: watch)

        watch.nutrition.select("food-a")
        watch.nutrition.stepPortion(2)

        let breadOnly = try foodsDown(
            generatedAt: "2026-07-13T05:30:00Z",
            messageId: "msg-foods-8314-b",
            foods: [food("food-b", "Bread", defaultServings: 2)]
        )
        await expectApplied(breadOnly, to: watch)

        XCTAssertNil(watch.nutrition.selected)

        watch.nutrition.select("food-b")
        XCTAssertEqual(watch.nutrition.servings, 2)
    }

    // MARK: - S-8315 the derived default is clamped when it seeds a selection

    func testS8315ASelectionClampsTheListedAmount() async throws {
        let watch = await NutritionHarness().launch()
        let list = try foodsDown(
            generatedAt: Self.catalogBeforeTheLog,
            messageId: "msg-foods-8315",
            foods: [food("food-a", "Apple", defaultServings: 0.25)]
        )
        await expectApplied(list, to: watch)

        watch.nutrition.select("food-a")

        XCTAssertEqual(watch.nutrition.servings, WatchNutritionPortion.minServings)
    }
}
