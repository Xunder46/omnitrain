//
//  WatchPortionCrown.swift
//  WatchSessionEngine
//
//  The food portion's Crown arithmetic (plan 56, D-4): positive Crown movement
//  raises the portion — the direction that raises a value on the logging
//  screen. The sign and detent math lives here, platform-independent, so
//  `swift test` can hold it; the model that calls it (`WatchNutritionView.swift`)
//  is watchOS-only and cannot be.
//
//  Travel short of one detent is not rounded off the portion's step: it comes
//  back as the returned position, so the Crown carries it to the next event.
//

import Foundation

public enum WatchPortionCrown {
    /// One Crown event: the whole detents it adds and the position to hand the
    /// Crown back. Positive movement is positive detents, as on the logging
    /// screen; the position has the consumed detents taken off so the Crown never
    /// reaches the end of its range.
    public static func turn(from previous: Double, to position: Double) -> (detents: Int, position: Double) {
        let travel = (position - previous) / WatchMetricStepping.pointsPerDetent
        // A carried position comes back through the same float representation
        // that produced it, so a full detent can arrive one ulp short
        // (1.4 - 0.4). Dust below the plan's own 1e-9 accuracy is not travel:
        // it is snapped away before the toward-zero round decides what carries.
        let dustFree = (travel * 1e9).rounded() / 1e9
        let whole = dustFree.rounded(.towardZero)
        return (Int(whole), position - whole * WatchMetricStepping.pointsPerDetent)
    }
}
