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
//  "done" when the efforts of its own kind reach its own plan — the planned
//  sets for a set, the planned efforts for a hold, interval or round — or, with
//  no plan, when anything is logged, and the search for the next exercise goes
//  forward from the current one, then from the top (plan 149 PR 2, D-14903).
//

import Foundation

/// The two lines the rest screen shows around the count-up.
public struct WatchRestLabels: Equatable {
    /// The exercise just done, with its set number when it is a set effort
    /// that has logged one: "Barbell Bench Press · Set 2 done".
    public let now: String

    /// What comes next: "Next set: Set 3 of 3" while Next stays on this
    /// exercise, "Next exercise: Barbell Back Squat · Set 1 of 2" when it moves,
    /// or the words that say nothing is planned (plan 149 PR 3, D-14907).
    public let next: String

    /// The slot the next line announces, when the line names an exercise: the
    /// id the menu's jump accepts. Nil for a set count, a period and the
    /// nothing-planned words (plan 79, D-6).
    public let nextSlotId: String?

    public init(now: String, next: String, nextSlotId: String? = nil) {
        self.now = now
        self.next = next
        self.nextSlotId = nextSlotId
    }
}

/// The rest screen's fixed words. They live here rather than on the view, which
/// compiles only into a watch target: this is the half the suite can read.
public enum WatchRestLabelCopy {
    /// The line's word while Next stays on the exercise it is on (D-14907).
    public static let nextSetPrefix = "Next set: "
    /// The line's word when Next moves to the exercise it names (D-14907).
    public static let nextExercisePrefix = "Next exercise: "
    public static let nothingNext = "Nothing planned next"
    public static let noExercise = "No exercise"
}

/// One valid slot of the ladder, as the rule reads it.
private struct RestLabelSlot {
    let name: String
    /// The id the slot answers to in the menu: its own `sessionExerciseId`, or
    /// the exercise's when the slot carries none (plan 79, D-6).
    let slotId: String
    /// The effort kind the slot is, resolved the way the logging surface
    /// resolves it: its declared kind, else its capabilities, else a set
    /// (plan 149 PR 2, D-14910).
    let kind: String
    /// Entries of kind `set` logged for the slot (the phone's and the wrist's).
    let sets: Int
    /// Entries of kind `hold` logged for the slot.
    let holds: Int
    /// Entries of kind `timed` logged for the slot.
    let timed: Int
    /// Entries of kind `round` logged for the slot.
    let rounds: Int
    /// Entries of any effort kind logged for the slot.
    let efforts: Int
    /// The set rows the phone planned for the slot, or 0 — read only for a set
    /// slot.
    let planned: Int
    /// The efforts of its own kind the phone planned for the slot, or 0 — read
    /// only for a non-set slot, so the two plan keys never both apply (D-14910).
    let plannedEfforts: Int

    /// The entries of the slot's own effort kind (D-14903).
    var ownKindCount: Int {
        switch kind {
        case WatchEffortKind.drill: return holds
        case WatchEffortKind.timed: return timed
        case WatchEffortKind.round: return rounds
        default: return sets
        }
    }

    var isDone: Bool {
        if plannedEfforts > 0 { return ownKindCount >= plannedEfforts }
        return planned > 0 ? sets >= planned : efforts > 0
    }

    /// The word the rest screen uses for the slot's own kind, nil for a set.
    func kindWord(roundNoun: String?) -> String? {
        switch kind {
        case WatchEffortKind.drill: return "Hold"
        case WatchEffortKind.timed: return "Interval"
        case WatchEffortKind.round: return roundNoun ?? "Round"
        default: return nil
        }
    }

    /// "k of N" for the slot's next effort: N never falls below k, so an extra
    /// effort logged past the plan reads as its own last number (D-14904).
    var kOfN: String {
        "\(ownKindCount + 1) of \(max(plannedEfforts, ownKindCount + 1))"
    }

    /// The slot as the next line names it: its name, and its next set or its
    /// next effort of its own kind when the phone planned either (D-14911).
    func nextLabel(roundNoun: String?) -> String {
        if plannedEfforts > 0, let word = kindWord(roundNoun: roundNoun) {
            return "\(name) · \(word) \(kOfN)"
        }
        return planned > 0 ? "\(name) · Set \(sets + 1) of \(planned)" : name
    }

    /// The effort kind a slot is: the kind it declares, else the one its
    /// capabilities resolve to — the mirror of `WatchLoggingState.effortKind`.
    static func kind(of slot: [String: Any], capabilities: [String]) -> String {
        if let declared = slot["effortKind"] as? String,
           WatchEffortKind.declared.contains(declared) {
            return declared
        }
        return WatchEffortKind.resolved(capabilities) ?? WatchEffortKind.set
    }
}

/// The two labels for a rest that follows an effort of `effortKind` on the
/// ladder's current slot. `nextRound` is the word-and-number of the next period
/// ("Period 2") for a round effort with no plan, nil otherwise. `roundNoun` is
/// the modality's word for a round ("Period", "Interval", "Round"), used for a
/// planned round's count (D-14904).
public func deriveRestLabels(
    sessionExercises: [[String: Any]],
    entries: [WatchObservationRecord],
    currentIndex: Int,
    effortKind: String,
    nextRound: String?,
    roundNoun: String? = nil
) -> WatchRestLabels {
    let clamped = min(max(currentIndex, 0), max(sessionExercises.count - 1, 0))
    var slots: [RestLabelSlot] = []
    var position: Int?

    for (index, slot) in sessionExercises.enumerated() {
        guard let exercise = WatchCatalogExercise(slot: slot) else { continue }
        let slotId = (slot["sessionExerciseId"] as? String) ?? exercise.slotId
        let kind = RestLabelSlot.kind(of: slot, capabilities: exercise.capabilities)
        let mine = entries.filter {
            ($0.payload["sessionExerciseId"] as? String) == slotId
        }
        if index == clamped { position = slots.count }
        slots.append(
            RestLabelSlot(
                name: exercise.name,
                slotId: slotId,
                kind: kind,
                sets: mine.filter { $0.kind == WatchObservationKind.set }.count,
                holds: mine.filter { $0.kind == WatchObservationKind.hold }.count,
                timed: mine.filter { $0.kind == WatchObservationKind.timed }.count,
                rounds: mine.filter { $0.kind == WatchObservationKind.round }.count,
                efforts: mine.filter { WatchObservationKind.efforts.contains($0.kind) }.count,
                planned: kind == WatchEffortKind.set
                    ? (slot["plannedSets"] as? [[String: Any]])?.count ?? 0
                    : 0,
                plannedEfforts: kind == WatchEffortKind.set
                    ? 0
                    : (slot["plannedEfforts"] as? Int).flatMap { $0 >= 1 ? $0 : nil } ?? 0
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
    let stayPrefix = WatchRestLabelCopy.nextSetPrefix
    let movePrefix = WatchRestLabelCopy.nextExercisePrefix

    let now: String
    if effortKind == WatchEffortKind.set, me.sets > 0 {
        now = "\(me.name) · Set \(me.sets) done"
    } else {
        now = me.name
    }

    if me.plannedEfforts > 0 {
        // A planned non-set slot stays until its own kind's count reaches its
        // plan, whatever period the caller offered: a planned round is never
        // the unbounded line (D-14903, D-14912).
        if me.ownKindCount < me.plannedEfforts,
           let word = me.kindWord(roundNoun: roundNoun) {
            return WatchRestLabels(now: now, next: "\(stayPrefix)\(word) \(me.kOfN)")
        }
    } else if effortKind == WatchEffortKind.set {
        if me.planned == 0 {
            return WatchRestLabels(now: now, next: "\(stayPrefix)Set \(me.sets + 1)")
        }
        if me.sets < me.planned {
            return WatchRestLabels(now: now, next: "\(stayPrefix)Set \(me.sets + 1) of \(me.planned)")
        }
    } else if effortKind == WatchEffortKind.round, let nextRound {
        return WatchRestLabels(now: now, next: "\(stayPrefix)\(nextRound)")
    }

    let order = Array((here + 1)..<slots.count) + Array(0..<here)
    for index in order where !slots[index].isDone {
        return WatchRestLabels(
            now: now,
            next: "\(movePrefix)\(slots[index].nextLabel(roundNoun: roundNoun))",
            nextSlotId: slots[index].slotId
        )
    }
    // Plan 201, D-20101: every exercise is done, so the list starts over. Next
    // goes on to the following exercise in turn (the last is followed by the
    // first), done or not; a one-exercise ladder has nowhere to go.
    if slots.count > 1 {
        let following = slots[(here + 1) % slots.count]
        return WatchRestLabels(
            now: now,
            next: "\(movePrefix)\(following.name)",
            nextSlotId: following.slotId
        )
    }
    return WatchRestLabels(now: now, next: WatchRestLabelCopy.nothingNext)
}
