//
//  WatchMenu.swift
//  WatchSessionEngine
//
//  The session menu's model: the ladder as rows, the jump, and Finish. Mirrors
//  the derivation style of `derivePickerRows` in `WatchStartPaths.swift` — a
//  pure function over the session and the engine's corrected projection, read on
//  every access rather than cached, so a frame that lands while the menu is open
//  is already in the list the user sees.
//
//  The menu writes no session structure of its own: a jump is the engine's
//  `selectExercise(slotId:)` through the start paths, and Finish is the rating
//  state's `end()`. It mints no ids and appends no observation.
//

import Foundation

/// One row of the wrist's session menu: a slot on the ladder, how many efforts
/// it already holds, and whether the session is sitting on it.
public struct WatchMenuRow: Equatable {
    /// The slot's `sessionExerciseId` — what a jump names.
    public let slotId: String

    /// The slot's exercise name, verbatim.
    public let name: String

    /// The efforts logged against the slot, after the phone's corrections and
    /// deletions. A rest is not an effort and is never counted.
    public let loggedCount: Int

    /// Whether the session's position is this slot.
    public let isCurrent: Bool

    public init(slotId: String, name: String, loggedCount: Int, isCurrent: Bool) {
        self.slotId = slotId
        self.name = name
        self.loggedCount = loggedCount
        self.isCurrent = isCurrent
    }

    /// The subtitle the row shows, or nil when the slot holds no effort yet.
    /// Never "0 logged": a count of nothing says nothing.
    public var countLabel: String? {
        loggedCount > 0 ? "\(loggedCount) logged" : nil
    }
}

/// The session's ladder as menu rows, in the session's own order.
///
/// A slot `WatchCatalogExercise(slot:)` rejects — no exercise id or no name — is
/// skipped, exactly as `derivePickerRows` skips it. `isCurrent` compares the
/// slot's position in the ladder with the clamped `currentIndex`, the reading
/// `WatchSessionRecord.currentExercise` applies, so a skipped slot shifts
/// nothing.
public func deriveMenuRows(
    sessionExercises: [[String: Any]],
    entries: [WatchObservationRecord],
    currentIndex: Int
) -> [WatchMenuRow] {
    guard !sessionExercises.isEmpty else { return [] }
    let current = min(max(currentIndex, 0), sessionExercises.count - 1)

    var rows: [WatchMenuRow] = []
    for (index, slot) in sessionExercises.enumerated() {
        guard let exercise = WatchCatalogExercise(slot: slot) else { continue }
        let slotId = (slot["sessionExerciseId"] as? String) ?? exercise.slotId
        let count = entries.filter {
            WatchObservationKind.efforts.contains($0.kind)
                && ($0.payload["sessionExerciseId"] as? String) == slotId
        }.count

        rows.append(
            WatchMenuRow(
                slotId: slotId,
                name: exercise.name,
                loggedCount: count,
                isCurrent: index == current
            )
        )
    }
    return rows
}

/// The menu over a live session: its rows, the jump to a slot, and Finish.
///
/// A plain class, not an `ObservableObject`: the host's `revision` bump is what
/// re-runs the view body, the same rule `pickerRows` follows. `rows` is derived
/// on every read and never cached.
public final class WatchMenuState {
    private let engine: WatchSessionEngine

    /// The start paths, so the menu can present the add-only picker.
    public let paths: WatchSessionStartPaths

    /// The rating state Finish ends through.
    public let rating: WatchEffortRatingState

    public init(engine: WatchSessionEngine, paths: WatchSessionStartPaths, rating: WatchEffortRatingState) {
        self.engine = engine
        self.paths = paths
        self.rating = rating
    }

    /// The ladder as rows right now.
    public var rows: [WatchMenuRow] {
        deriveMenuRows(
            sessionExercises: engine.session?.exercises ?? [],
            entries: engine.entries,
            currentIndex: engine.session?.currentExerciseIndex ?? 0
        )
    }

    /// Moves the session to the slot `slotId` names, through the existing
    /// select path. False when the slot is gone by the time the tap lands, which
    /// changes nothing.
    @discardableResult
    public func jump(to slotId: String) async -> Bool {
        guard let row = paths.pickerRows.first(where: { $0.isInSession && $0.id == slotId }) else {
            return false
        }
        return await paths.selectExercise(row) != nil
    }

    /// Finishes the session through the rating state's `end()`, so the owed
    /// rating prompt and `finishSession()` stay one implementation.
    public func finish() async {
        await rating.end()
    }
}
