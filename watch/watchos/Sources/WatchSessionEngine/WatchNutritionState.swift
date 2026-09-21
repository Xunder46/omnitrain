//
//  WatchNutritionState.swift
//  WatchSessionEngine
//
//  The quick-log screen's state: the synced food list, the food and portion the
//  user has picked, and the observation that comes out of confirming them.
//  Mirrors `lib/watch/nutrition/watch_nutrition_state.dart` call for call.
//
//  Plan: `.github/agents/plans/2026-07-13-12-e-watch-nutrition-quick-log-plan.md`,
//  scenarios S-001 to S-006.
//
//  Everything the screen shows is derived — the list from the synced catalog
//  and the wrist's own log, the calories from the portion — and the only thing
//  held in memory is an edit the user has made but not yet confirmed, which is
//  not data yet: a kill mid-turn costs a turn, never a food. Confirming goes
//  straight to the engine's `logNutrition`, so the event, its storage and its
//  message are the item-6 path with nothing translated in between.
//
//  Nothing here needs a session: eating is not a training event, and the
//  surface is reachable with no workout running (S-006).
//

import Foundation

/// The portion control's detents and bounds, in servings.
///
/// The values are not the wrist's to choose — `watch/contract/watch_nutrition_contract.json`
/// carries them and both clients' suites assert against it, so the two watch
/// clients cannot disagree about what a detent is worth.
public enum WatchNutritionPortion {
    public static let stepServings = 0.5
    public static let minServings = 0.5
    public static let maxServings = 10.0
}

public final class WatchNutritionState {
    private let engine: WatchSessionEngine
    private let store: WatchSessionStore
    private let validator: SyncProtocolValidator?
    private let clock: () -> Date
    private let newId: () -> String

    private var catalog: WatchFoodCatalogRecord?
    private var syncedFoods: [WatchFood] = []
    private var categories: [WatchFoodCategory] = []

    /// The food the user has picked, or nil while nothing is.
    public private(set) var selectedFoodId: String?

    private var portion: Double = WatchNutritionPortion.minServings
    private var lastConfirmation: String?

    public init(
        engine: WatchSessionEngine,
        store: WatchSessionStore,
        validator: SyncProtocolValidator? = nil,
        clock: @escaping () -> Date = { Date() },
        idFactory: @escaping () -> String = { UUID().uuidString }
    ) {
        self.engine = engine
        self.store = store
        self.validator = validator
        self.clock = clock
        self.newId = idFactory
    }

    // MARK: - What the surface reads

    /// The wrist's list: the phone's Foods I Eat order, with what the user
    /// logged here recently lifted to the front.
    public var foods: [WatchFood] {
        deriveWatchFoodList(
            foods: syncedFoods,
            categories: categories,
            recentFoodIds: recentFoodIds
        )
    }

    /// The food with `foodId` as the wrist holds it, or nil when the phone has
    /// not sent one.
    public func food(_ foodId: String) -> WatchFood? {
        syncedFoods.first { $0.foodId == foodId }
    }

    /// When the phone generated the list the watch is holding, or nil when no
    /// phone has sent one yet.
    public var syncedAt: Date? { catalog?.generatedAt }

    public var selected: WatchFood? {
        selectedFoodId.flatMap { food($0) }
    }

    /// The portion the user has dialled in, in servings of the selected food.
    public var servings: Double { portion }

    /// What the current portion costs, in kcal.
    public var calories: Int { selected?.calories(at: portion) ?? 0 }

    /// The portion as the wrist prints it — `1.5 × 100 g` — or an empty string
    /// while nothing is selected.
    public var portionLabel: String {
        guard let food = selected else { return "" }
        return "\(Self.formatAmount(portion)) × "
            + "\(Self.formatAmount(food.referenceAmount)) \(food.referenceLabel)"
    }

    /// What the wrist says after a log, or nil when nothing has been logged
    /// since the user last touched the surface.
    public var confirmation: String? { lastConfirmation }

    // MARK: - The synced list

    /// Reads the food list back out of storage. Call on launch, and after any
    /// suspension: what comes back is what the phone last sent.
    public func restore() async {
        let contents = await store.readAll()
        catalog = contents.foodCatalogs.max { $0.sequence < $1.sequence }
        applyCatalog()
    }

    /// Applies a `foods_down` message: the list the user quick-logs from.
    ///
    /// The message is stored whole and the newest one wins, so the list the user
    /// sees updates on the next background sync with no action from them (S-003).
    public func applyFoodsDown(_ envelope: [String: Any]) async -> WatchCatalogSyncResult {
        let rejections = SyncProtocolValidator.incomingRejections(validator, envelope)
        if !rejections.isEmpty {
            return WatchCatalogSyncResult(applied: false, rejections: rejections)
        }

        guard let sent = try? WatchFoodsDown(envelope: envelope) else {
            return WatchCatalogSyncResult(applied: false, rejections: [])
        }

        if let catalog, sent.generatedAt < catalog.generatedAt {
            // Understood and dropped: an older view of the food list is not a
            // newer truth.
            return WatchCatalogSyncResult(applied: false, rejections: [])
        }

        let stored = await store.append(
            .foodCatalog(
                WatchFoodCatalogRecord(
                    recordId: "foods-\(envelope["messageId"] as? String ?? newId())",
                    recordedAt: sent.generatedAt,
                    generatedAt: sent.generatedAt,
                    foods: sent.foods.map { $0.toJson() },
                    categories: sent.categories.map { $0.toJson() }
                )
            )
        )
        catalog = stored.foodCatalogRow
        applyCatalog()

        return WatchCatalogSyncResult(applied: true, rejections: [])
    }

    private func applyCatalog() {
        guard let catalog, let synced = try? WatchFoodsDown(catalog: catalog) else {
            syncedFoods = []
            categories = []
            return
        }
        syncedFoods = synced.foods
        categories = synced.categories
    }

    /// The foods the user logged on the wrist, newest first.
    ///
    /// Read out of the observations the store already holds rather than written
    /// to a list of its own: a relaunch cannot lose what storage kept.
    private var recentFoodIds: [String] {
        var seen = Set<String>()
        var recent: [String] = []
        for observation in engine.nutritionLog.reversed() {
            guard let foodId = observation.payload["foodId"] as? String,
                  seen.insert(foodId).inserted
            else { continue }
            recent.append(foodId)
        }
        return recent
    }

    // MARK: - The portion

    /// Picks `foodId` and starts its portion where the phone left it — the
    /// amount the user logged last, or one serving.
    public func select(_ foodId: String) {
        guard let food = food(foodId) else { return }
        selectedFoodId = foodId
        portion = Self.clampServings(food.defaultServings)
        lastConfirmation = nil
    }

    /// A turn of the rotary input, in detents: one detent is
    /// `WatchNutritionPortion.stepServings` of the food.
    public func stepPortion(_ detents: Int) {
        portion = Self.clampServings(
            portion + Double(detents) * WatchNutritionPortion.stepServings
        )
        lastConfirmation = nil
    }

    private static func clampServings(_ servings: Double) -> Double {
        min(max(servings, WatchNutritionPortion.minServings), WatchNutritionPortion.maxServings)
    }

    // MARK: - Logging

    /// Logs the selected food at the current portion, and says so on the wrist.
    ///
    /// The engine stores the event before anything is emitted, so the only thing
    /// this can fail at is having nothing selected — and a food the user did not
    /// pick is not a food they ate.
    @discardableResult
    public func logSelected() async throws -> WatchObservationRecord {
        guard let food = selected else {
            throw WatchNutritionError.nothingSelected
        }

        let record = try await engine.logNutrition(
            foodId: food.foodId,
            servings: portion,
            calories: Double(food.calories(at: portion)),
            loggedAt: clock()
        )
        lastConfirmation = "\(food.name) · \(portionLabel) · \(food.calories(at: portion)) kcal"
        return record
    }

    /// A number as the wrist prints it: whole numbers without a trailing `.0`,
    /// and everything else at the resolution a portion detent can produce.
    private static func formatAmount(_ amount: Double) -> String {
        if amount == amount.rounded() { return String(Int(amount.rounded())) }
        return String(format: "%.1f", amount)
    }
}

public enum WatchNutritionError: Error, CustomStringConvertible {
    case nothingSelected

    public var description: String {
        switch self {
        case .nothingSelected:
            return "logSelected() was called with no food selected; select one first"
        }
    }
}
