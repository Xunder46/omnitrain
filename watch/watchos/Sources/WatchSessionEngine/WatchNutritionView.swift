//
//  WatchNutritionView.swift
//  WatchSessionEngine
//
//  The native watchOS quick-log surface: the foods the user eats, one portion,
//  one log. Native half of
//  `.github/agents/plans/2026-07-13-12-e-watch-nutrition-quick-log-plan.md`,
//  scenarios S-001, S-004 and S-006.
//
//  Another deliberate choice of the same kind `Package.swift` makes: the state,
//  the store, the catalog, and the derivation are platform-independent, so they
//  build and test today with `swift test`. The view is the one part that cannot
//  be — crown rotation and its presentation are watchOS-only here — so it is
//  compiled only into a watch target. What it renders is the behaviour the tests
//  cover.
//
//  There is no search, no catalog and no macro editing here: the phone owns all
//  of that, and this surface owns the two-second log of a routine meal.
//

#if os(watchOS)

import SwiftUI

/// What the surface draws, and what a tap or a turn does to it. A small
/// observable wrapper so the state itself stays testable without SwiftUI.
public final class WatchNutritionModel: ObservableObject {
    /// Points of crown travel that count as one portion detent, as every wrist
    /// surface counts them.
    public static let pointsPerDetent = WatchMetricStepping.pointsPerDetent

    public let state: WatchNutritionState

    @Published public private(set) var crownPosition: Double = 0

    public init(state: WatchNutritionState) {
        self.state = state
    }

    public var foods: [WatchFood] { state.foods }

    public var confirmation: String? { state.confirmation }

    /// Picks a food; its portion starts where the phone left it.
    public func select(_ foodId: String) {
        objectWillChange.send()
        state.select(foodId)
        crownPosition = 0
    }

    /// A crown turn, in points: whole detents move the portion, and travel short
    /// of one is carried to the next event rather than rounding the portion off
    /// its step.
    public func turn(to points: Double) {
        let rising = -(points - crownPosition)
        let whole = (rising / Self.pointsPerDetent).rounded(.towardZero)
        crownPosition = points + whole * Self.pointsPerDetent
        guard whole != 0 else { return }
        objectWillChange.send()
        state.stepPortion(Int(whole))
    }

    public func step(_ detents: Int) {
        objectWillChange.send()
        state.stepPortion(detents)
    }

    /// Logs the selected food at the current portion.
    @discardableResult
    public func log() async -> WatchObservationRecord? {
        objectWillChange.send()
        return try? await state.logSelected()
    }
}

/// The quick-log, as the wrist shows it: the list, the portion, one confirm.
public struct WatchNutritionView: View {
    @ObservedObject private var model: WatchNutritionModel

    /// Wrist-scale inset — the phone's spacing tokens are sized for a full-width
    /// screen.
    private static let surfaceInset = 4.0

    private static let crownRangeDetents = 20.0

    public init(model: WatchNutritionModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: Self.surfaceInset) {
            if model.foods.isEmpty {
                Text("No foods yet. Sync with your phone to get them.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
            } else {
                ScrollView {
                    VStack(spacing: Self.surfaceInset) {
                        ForEach(model.foods, id: \.foodId) { food in
                            foodButton(food)
                        }
                    }
                }

                if model.state.selected != nil {
                    portionRow
                    logButton
                }

                if let confirmation = model.confirmation {
                    Text(confirmation)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, Self.surfaceInset)
    }

    @ViewBuilder
    private func foodButton(_ food: WatchFood) -> some View {
        let isSelected = food.foodId == model.state.selectedFoodId
        let button = Button {
            model.select(food.foodId)
        } label: {
            HStack {
                Text(food.name).lineLimit(1)
                Spacer()
                Text("\(food.calories(at: isSelected ? model.state.servings : food.defaultServings))")
                    .foregroundStyle(.secondary)
            }
        }
        // `.borderedProminent` and `.bordered` are distinct concrete types, so a
        // ternary between them has no common type to infer. The branches have to
        // be separate views.
        if isSelected {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    /// The portion row: the count, what it means in the food's own unit, the two
    /// touch controls, and both ways to move it with the crown.
    private var portionRow: some View {
        HStack {
            stepButton(systemName: "minus", label: "Less") { model.step(-1) }

            VStack(spacing: 0) {
                Text(model.state.portionLabel).font(.caption2)
                Text("\(model.state.calories) kcal").font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .focusable(true)
            .digitalCrownRotation(
                detent: Binding(
                    get: { model.crownPosition },
                    set: { model.turn(to: $0) }
                ),
                from: -WatchNutritionModel.pointsPerDetent * Self.crownRangeDetents,
                through: WatchNutritionModel.pointsPerDetent * Self.crownRangeDetents,
                by: WatchNutritionModel.pointsPerDetent,
                sensitivity: .medium,
                isContinuous: true,
                isHapticFeedbackEnabled: true
            )

            stepButton(systemName: "plus", label: "More") { model.step(1) }
        }
    }

    private func stepButton(
        systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(label)
    }

    /// The primary action: a wrist log is one glance and one confirm.
    private var logButton: some View {
        Button {
            Task { await model.log() }
        } label: {
            Text("Log").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
    }
}

#endif
