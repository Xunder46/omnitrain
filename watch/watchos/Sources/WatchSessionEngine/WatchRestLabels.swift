//
//  WatchRestLabels.swift
//  WatchSessionEngine
//
//  What the rest screen says besides the count-up: the effort just done, and
//  what comes next. Plan 51b
//  (`docs/plans/2026-10-21-51b-wrist-rest-now-next-plan/2026-10-21-51b-wrist-rest-now-next-plan.md`),
//  D-1 to D-3.
//
//  A pure function over the session's ladder and entries, outside the
//  watchOS-only view, so the desktop toolchain can assert the rule: a slot is
//  "done" when its planned sets are all logged (or, with no plan, when anything
//  is logged), and the search for the next exercise goes forward from the
//  current one, then from the top.
//

import Foundation

/// The two lines the rest screen shows around the count-up.
public struct WatchRestLabels: Equatable {
    /// The exercise just done, with its set number when it is a set effort
    /// that has logged one: "Barbell Bench Press · Set 2 done".
    public let now: String

    /// What comes next: "Next: Set 3 of 3", "Next: Barbell Back Squat · Set 1
    /// of 2", "Next: Period 2", or the words that say nothing is planned.
    public let next: String

    public init(now: String, next: String) {
        self.now = now
        self.next = next
    }
}

/// The rest screen's fixed words. They live here rather than on the view, which
/// compiles only into a watch target: this is the half the suite can read.
public enum WatchRestLabelCopy {
    public static let nextPrefix = "Next: "
    public static let nothingNext = "Nothing planned next"
    public static let noExercise = "No exercise"
}

/// One valid slot of the ladder, as the rule reads it.
private struct RestLabelSlot {
    let name: String
    /// Entries of kind `set` logged for the slot (the phone's and the wrist's).
    let sets: Int
    /// Entries of any effort kind logged for the slot.
    let efforts: Int
    /// The set rows the phone planned for the slot, or 0.
    let planned: Int

    var isDone: Bool { planned > 0 ? sets >= planned : efforts > 0 }

    /// The slot as the next line names it: its name, and its next set when the
    /// phone planned the sets.
    var nextLabel: String {
        planned > 0 ? "\(name) · Set \(sets + 1) of \(planned)" : name
    }
}

/// The two labels for a rest that follows an effort of `effortKind` on the
/// ladder's current slot. `nextRound` is the word-and-number of the next period
/// ("Period 2") for a round effort, nil otherwise.
public func deriveRestLabels(
    sessionExercises: [[String: Any]],
    entries: [WatchObservationRecord],
    currentIndex: Int,
    effortKind: String,
    nextRound: String?
) -> WatchRestLabels {
    let clamped = min(max(currentIndex, 0), max(sessionExercises.count - 1, 0))
    var slots: [RestLabelSlot] = []
    var position: Int?

    for (index, slot) in sessionExercises.enumerated() {
        guard let exercise = WatchCatalogExercise(slot: slot) else { continue }
        let slotId = (slot["sessionExerciseId"] as? String) ?? exercise.slotId
        let mine = entries.filter {
            ($0.payload["sessionExerciseId"] as? String) == slotId
        }
        if index == clamped { position = slots.count }
        slots.append(
            RestLabelSlot(
                name: exercise.name,
                sets: mine.filter { $0.kind == WatchObservationKind.set }.count,
                efforts: mine.filter { WatchObservationKind.efforts.contains($0.kind) }.count,
                planned: (slot["plannedSets"] as? [[String: Any]])?.count ?? 0
            )
        )
    }

    guard let here = position else {
        return WatchRestLabels(
            now: WatchRestLabelCopy.noExercise,
            next: WatchRestLabelCopy.nothingNext
        )
    }
    let me = slots[here]
    let prefix = WatchRestLabelCopy.nextPrefix

    let now: String
    if effortKind == WatchEffortKind.set, me.sets > 0 {
        now = "\(me.name) · Set \(me.sets) done"
    } else {
        now = me.name
    }

    if effortKind == WatchEffortKind.set {
        if me.planned == 0 {
            return WatchRestLabels(now: now, next: "\(prefix)Set \(me.sets + 1)")
        }
        if me.sets < me.planned {
            return WatchRestLabels(now: now, next: "\(prefix)Set \(me.sets + 1) of \(me.planned)")
        }
    }
    if effortKind == WatchEffortKind.round, let nextRound {
        return WatchRestLabels(now: now, next: "\(prefix)\(nextRound)")
    }

    let order = Array((here + 1)..<slots.count) + Array(0..<here)
    for index in order where !slots[index].isDone {
        return WatchRestLabels(now: now, next: "\(prefix)\(slots[index].nextLabel)")
    }
    return WatchRestLabels(now: now, next: WatchRestLabelCopy.nothingNext)
}
