//
//  WatchFoodCatalog.swift
//  WatchSessionEngine
//
//  The food list the phone sends down, in the shapes the wrist reasons about.
//  Mirrors `lib/watch/nutrition/watch_food_catalog.dart` type for type.
//
//  Plan: `.github/agents/plans/2026-07-13-12-e-watch-nutrition-quick-log-plan.md`,
//  scenarios S-001 to S-004.
//
//  The store keeps the phone's JSON as it arrived (`WatchFoodCatalogRecord`);
//  these types are the view the quick-log surface reads it through — a list the
//  user can scan and a portion that means something.
//
//  The order the list is shown in is the phone's, not the wrist's: the phone
//  owns the food catalog and the cut of it the user eats, and
//  `lib/core/utils/foods_i_eat_order.dart` is where that rule lives for the
//  phone. `deriveWatchFoodList` applies the same rule to the synced rows, then
//  lifts what the wrist itself logged most recently to the front — the same
//  shape the fallback exercise list uses, so the two offline lists behave alike.
//

import Foundation

/// One food the wrist may quick-log. A serving is the food's reference amount,
/// which is why a portion is a number of servings.
public struct WatchFood: Equatable {
    public let foodId: String
    public let name: String

    /// The phone's category for this food, or nil when the phone groups it
    /// under nothing (its category was archived, or it never had one).
    public let categoryId: String?

    public let referenceAmount: Double
    public let referenceLabel: String

    /// What one serving costs, in kcal.
    public let caloriesPerServing: Double

    /// The portion the phone pre-fills: the amount the user logged last, in
    /// servings.
    public let defaultServings: Double

    public init(
        foodId: String,
        name: String,
        categoryId: String? = nil,
        referenceAmount: Double,
        referenceLabel: String,
        caloriesPerServing: Double,
        defaultServings: Double
    ) {
        self.foodId = foodId
        self.name = name
        self.categoryId = categoryId
        self.referenceAmount = referenceAmount
        self.referenceLabel = referenceLabel
        self.caloriesPerServing = caloriesPerServing
        self.defaultServings = defaultServings
    }

    public init(json: [String: Any]) throws {
        self.init(
            foodId: try requiredString(json, "foodId"),
            name: try requiredString(json, "name"),
            categoryId: json["categoryId"] as? String,
            referenceAmount: (json["referenceAmount"] as? NSNumber)?.doubleValue ?? 0,
            referenceLabel: try requiredString(json, "referenceLabel"),
            caloriesPerServing: (json["caloriesPerServing"] as? NSNumber)?.doubleValue ?? 0,
            defaultServings: (json["defaultServings"] as? NSNumber)?.doubleValue ?? 0
        )
    }

    /// The kcal in `servings` of this food, in the phone's own arithmetic.
    public func calories(at servings: Double) -> Int {
        Int((caloriesPerServing * servings).rounded())
    }

    public func toJson() -> [String: Any] {
        [
            "foodId": foodId,
            "name": name,
            "categoryId": categoryId ?? NSNull(),
            "referenceAmount": referenceAmount,
            "referenceLabel": referenceLabel,
            "caloriesPerServing": caloriesPerServing,
            "defaultServings": defaultServings,
        ]
    }
}

/// One of the user's active food categories, as the phone named it.
public struct WatchFoodCategory: Equatable {
    public let categoryId: String
    public let name: String

    public init(categoryId: String, name: String) {
        self.categoryId = categoryId
        self.name = name
    }

    public init(json: [String: Any]) throws {
        self.init(
            categoryId: try requiredString(json, "categoryId"),
            name: try requiredString(json, "name")
        )
    }

    public func toJson() -> [String: Any] {
        ["categoryId": categoryId, "name": name]
    }
}

/// A `foods_down` message, parsed as the wrist reads it.
public struct WatchFoodsDown {
    /// When the phone generated this list.
    public let generatedAt: Date

    public let foods: [WatchFood]
    public let categories: [WatchFoodCategory]

    public init(generatedAt: Date, foods: [WatchFood], categories: [WatchFoodCategory]) {
        self.generatedAt = generatedAt
        self.foods = foods
        self.categories = categories
    }

    public init(envelope: [String: Any]) throws {
        guard let payload = envelope["payload"] as? [String: Any] else {
            throw WatchRecordError.malformed("foods_down has no payload")
        }
        try self.init(payload: payload)
    }

    public init(payload: [String: Any]) throws {
        self.init(
            generatedAt: try parseUtcIso(payload["generatedAt"]),
            foods: try (payload["foods"] as? [[String: Any]] ?? []).map {
                try WatchFood(json: $0)
            },
            categories: try (payload["categories"] as? [[String: Any]] ?? []).map {
                try WatchFoodCategory(json: $0)
            }
        )
    }

    /// The catalog as the store kept it, which is the message's payload.
    public init(catalog: WatchFoodCatalogRecord) throws {
        try self.init(payload: [
            "generatedAt": utcIso(catalog.generatedAt),
            "foods": catalog.foods,
            "categories": catalog.categories,
        ])
    }
}

/// The wrist's list: the phone's Foods I Eat order, with what the wrist logged
/// recently lifted to the front.
///
/// The base order is the phone's own — categories alphabetically, foods the
/// phone files under nothing last, foods alphabetically inside each — so a user
/// who never quick-logs anything on the wrist sees the list the phone shows
/// them. `recentFoodIds` is the wrist's own usage, newest first; ids the synced
/// list does not know are skipped, because a food deleted on the phone is not a
/// food the wrist can log.
public func deriveWatchFoodList(
    foods: [WatchFood],
    categories: [WatchFoodCategory],
    recentFoodIds: [String]
) -> [WatchFood] {
    let categoryNames = Dictionary(
        uniqueKeysWithValues: categories.map { ($0.categoryId, $0.name) }
    )

    let ordered = foods.sorted { a, b in
        let bySection = compareSections(section(of: a, categoryNames), section(of: b, categoryNames))
        if bySection != 0 { return bySection < 0 }
        return a.name.lowercased() < b.name.lowercased()
    }

    var byId: [String: WatchFood] = [:]
    for food in foods { byId[food.foodId] = food }

    var seen = Set<String>()
    var list: [WatchFood] = []
    for foodId in recentFoodIds {
        guard let food = byId[foodId], seen.insert(foodId).inserted else { continue }
        list.append(food)
    }
    for food in ordered where seen.insert(food.foodId).inserted {
        list.append(food)
    }
    return list
}

private func section(of food: WatchFood, _ categoryNames: [String: String]) -> String? {
    guard let categoryId = food.categoryId else { return nil }
    return categoryNames[categoryId]
}

/// Categories alphabetically, and a food the phone files under nothing after
/// every food it files somewhere — the phone prints that group last
/// (`foodsIEatSections`), so the wrist lists it last too.
private func compareSections(_ a: String?, _ b: String?) -> Int {
    switch (a, b) {
    case (nil, nil): return 0
    case (nil, _): return 1
    case (_, nil): return -1
    case (let a?, let b?): return a.lowercased().compare(b.lowercased()).rawValue
    }
}

// MARK: - Stored record

/// The reference data a `foods_down` message carries: the foods the wrist may
/// quick-log, and the categories that order them.
///
/// The same shape of row as `WatchRoutineCatalogRecord` and for the same
/// reason: it is the phone's data, the watch only reads it, and it belongs to
/// no session — so its `sessionId` is empty and a sync appends a new row rather
/// than editing the one before it. What the wrist itself logged recently is
/// *not* stored here either: it is derived from the observations the store
/// already holds.
public struct WatchFoodCatalogRecord {
    public let recordId: String
    public let sessionId: String
    public let recordedAt: Date
    public let sequence: Int

    /// When the phone generated this view of the food list. A message older
    /// than the cached one is not a newer truth, so it is ignored.
    public let generatedAt: Date

    /// The foods as `foods_down` carried them, in the phone's own array order —
    /// which is not the order the wrist shows: the derivation reorders them.
    public let foods: [[String: Any]]

    /// The phone's active food categories, in the phone's own array order.
    public let categories: [[String: Any]]

    public init(
        recordId: String,
        recordedAt: Date,
        generatedAt: Date,
        foods: [[String: Any]] = [],
        categories: [[String: Any]] = [],
        sequence: Int = 0
    ) {
        self.recordId = recordId
        self.sessionId = ""
        self.recordedAt = recordedAt
        self.sequence = sequence
        self.generatedAt = generatedAt
        self.foods = foods
        self.categories = categories
    }

    public func withSequence(_ sequence: Int) -> WatchFoodCatalogRecord {
        WatchFoodCatalogRecord(
            recordId: recordId,
            recordedAt: recordedAt,
            generatedAt: generatedAt,
            foods: foods,
            categories: categories,
            sequence: sequence
        )
    }

    public func toJson() -> [String: Any] {
        [
            "recordType": StoredWatchRecord.foodCatalogType,
            "recordId": recordId,
            "sessionId": sessionId,
            "recordedAt": utcIso(recordedAt),
            "sequence": sequence,
            "generatedAt": utcIso(generatedAt),
            "foods": foods,
            "categories": categories,
        ]
    }

    public static func fromJson(_ json: [String: Any]) throws -> WatchFoodCatalogRecord {
        WatchFoodCatalogRecord(
            recordId: try requiredString(json, "recordId"),
            recordedAt: try parseUtcIso(json["recordedAt"]),
            generatedAt: try parseUtcIso(json["generatedAt"]),
            foods: (json["foods"] as? [[String: Any]]) ?? [],
            categories: (json["categories"] as? [[String: Any]]) ?? [],
            sequence: (json["sequence"] as? NSNumber)?.intValue ?? 0
        )
    }
}
