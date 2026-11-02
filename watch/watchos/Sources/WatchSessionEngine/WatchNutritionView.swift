//
//  WatchNutritionView.swift
//  WatchSessionEngine
//
//  The native watchOS quick-log surface: the foods the user eats, and the one
//  food a tap opens — its portion, one log. Native half of
//  `docs/plans/2026-07-13-12-e-watch-nutrition-quick-log-plan.md`,
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

import Foundation
import SwiftUI
import WatchKit

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
        // The state may announce a change off the main thread — the store and the
        // log are both async — so the nudge to SwiftUI hops first (D-4).
        state.onFoodsChanged = { [weak self] in
            DispatchQueue.main.async { self?.objectWillChange.send() }
        }
    }

    public var foods: [WatchFood] { state.foods }

    public var confirmation: String? { state.confirmation }

    /// Whether a food is open, which is what drives the list's push (D-5).
    public var isShowingFood: Bool { state.selected != nil }

    /// Picks a food; its portion starts where the phone left it.
    public func select(_ foodId: String) {
        objectWillChange.send()
        state.select(foodId)
        crownPosition = 0
    }

    /// Leaves the open food: the list has nothing selected, and the crown starts
    /// over with the next one (D-4).
    public func deselect() {
        objectWillChange.send()
        state.deselect()
        crownPosition = 0
    }

    /// A crown turn, in points: whole detents move the portion, and travel short
    /// of one is carried to the next event rather than rounding the portion off
    /// its step.
    public func turn(to points: Double) {
        let step = WatchPortionCrown.turn(from: crownPosition, to: points)
        crownPosition = step.position
        guard step.detents != 0 else { return }
        objectWillChange.send()
        state.stepPortion(step.detents)
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

    /// The day's water, drawn under the list (plan 95 D-31). The bar observes
    /// it; the list only hands it on.
    private let water: WatchWaterModel

    /// Wrist-scale inset — the phone's spacing tokens are sized for a full-width
    /// screen.
    private static let surfaceInset = 4.0

    public init(model: WatchNutritionModel, water: WatchWaterModel) {
        self.model = model
        self.water = water
    }

    public var body: some View {
        VStack(spacing: Self.surfaceInset) {
            if model.foods.isEmpty {
                Text("No foods yet. On your phone, open Nutrition and tap Choose foods.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    // Fills the space, so the water bar sits at the bottom here too.
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: Self.surfaceInset) {
                        ForEach(model.foods, id: \.foodId) { food in
                            foodButton(food)
                        }
                    }
                }
            }

            // Plan 95 D-31: after the branch and outside the scroll, so it is
            // pinned at the bottom with or without foods.
            WatchWaterBar(model: water)
        }
        .padding(.horizontal, Self.surfaceInset)
        .navigationDestination(isPresented: showingFood) {
            WatchFoodPortionView(model: model)
        }
    }

    /// The push follows the selection: a tap selects a food and opens its screen,
    /// and leaving it — the back button or a swipe — clears the selection (D-5).
    private var showingFood: Binding<Bool> {
        Binding(
            get: { model.isShowingFood },
            set: { isShowing in
                if !isShowing { model.deselect() }
            }
        )
    }

    /// The row is the way into the food: the name, and what the food's starting
    /// amount costs — the state derives that amount from the wrist's newest log
    /// where it is newer than the phone's list (D-2).
    private func foodButton(_ food: WatchFood) -> some View {
        Button {
            model.select(food.foodId)
        } label: {
            HStack {
                Text(food.name).lineLimit(1)
                Spacer()
                Text("\(food.calories(at: food.defaultServings))")
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.bordered)
    }
}

/// The day's glasses of water: minus, the drop and the count, plus, like the
/// phone's water control (plan 95 D-31 to D-34). Each press that stores a tap
/// clicks once; minus is off at 0 and both are off past the day's cap (D-27).
/// The count is computed on every read, so the minute timeline is what turns
/// it over at local midnight while the bar stays on screen.
struct WatchWaterBar: View {
    @ObservedObject private var model: WatchWaterModel

    /// A wide count shrinks rather than wrapping on a 40 mm screen.
    private static let countScale = 0.6

    /// The drop sits tight against its number.
    private static let dropSpacing = 2.0

    init(model: WatchWaterModel) {
        self.model = model
    }

    var body: some View {
        TimelineView(.everyMinute) { _ in
            HStack {
                Button {
                    Task {
                        if await model.press(.remove) {
                            WKInterfaceDevice.current().play(.click)
                        }
                    }
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.bordered)
                .disabled(!model.canRemove)
                .accessibilityLabel(WatchWaterCopy.removeLabel)

                HStack(spacing: Self.dropSpacing) {
                    Image(systemName: "drop.fill")
                    Text("\(model.glasses)")
                        .lineLimit(1)
                        .minimumScaleFactor(Self.countScale)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(WatchWaterCopy.countLabel)
                .accessibilityValue(model.spokenCount)

                Button {
                    Task {
                        if await model.press(.add) {
                            WKInterfaceDevice.current().play(.click)
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .disabled(!model.canAdd)
                .accessibilityLabel(WatchWaterCopy.addLabel)
            }
        }
    }
}

/// One food, open: its portion, what it costs, and the one confirm. Pushed from
/// the list, so leaving it hands the list back with nothing selected (D-5).
public struct WatchFoodPortionView: View {
    @ObservedObject private var model: WatchNutritionModel

    /// Wrist-scale inset, as the list uses.
    private static let surfaceInset = 4.0

    private static let crownRangeDetents = 20.0

    public init(model: WatchNutritionModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: Self.surfaceInset) {
            portionRow

            logButton

            if let confirmation = model.confirmation {
                Text(confirmation)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, Self.surfaceInset)
        .navigationTitle(model.state.selected?.name ?? "")
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
            Task {
                // Plan 51e D-3: a food the wrist recorded earns the same tap as a set.
                if await model.log() != nil {
                    WKInterfaceDevice.current().play(.success)
                }
            }
        } label: {
            Text("Log").frame(maxWidth: .infinity)
        }
        .watchProminent()
    }
}

#endif
