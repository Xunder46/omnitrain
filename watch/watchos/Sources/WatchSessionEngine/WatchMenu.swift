//
//  WatchMenu.swift
//  WatchSessionEngine
//
//  The session menu's model: the ladder as rows, the jump, Finish and Discard.
//  `rows` is a pure function over the session and the engine's corrected
//  projection, read on every access rather than cached, so a frame that lands
//  while the menu is open is already in the list the user sees.
//
//  The menu writes no session structure of its own: a jump is the engine's
//  `selectExercise(slotId:)` through the start paths, Finish is the rating
//  state's `end()`, Discard is the engine's own `abandonSession()`, and Add
//  Exercise is the start paths' `addExerciseToEnd`, which appends at the end of
//  the ladder and nowhere else. It mints no ids of its own and appends no
//  observation.
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

/// One run of a list the user reads (plan 199, D-19902): its title, shown only
/// when the list has two groups, and its exercises in the list's own order.
///
/// The concatenation of a list's groups is that list — nothing dropped, nothing
/// repeated, nothing reordered.
public struct WatchExerciseGroup: Equatable {
    /// The group's header, or nil for a list that is one plain run.
    public let title: String?

    public let exercises: [WatchCatalogExercise]

    public init(title: String?, exercises: [WatchCatalogExercise]) {
        self.title = title
        self.exercises = exercises
    }
}

/// The list split into the groups it is read in (plan 199, D-19905).
///
/// Pure and in order: `exercises` is `addableExercises`, already A to Z, and the
/// groups keep that order — a stable partition, nothing dropped, repeated or
/// reordered. With a modality the list splits into Recommended (the exercises
/// whose `recommendedFor` names the modality) then Other, titled only when both
/// are non-empty; one non-empty group, or no modality, is one untitled group.
/// Unknown keys in `recommendedFor` are kept but never match.
public func deriveExerciseGroups(
    _ exercises: [WatchCatalogExercise],
    modality: String?
) -> [WatchExerciseGroup] {
    guard !exercises.isEmpty else { return [] }
    guard let modality else {
        return [WatchExerciseGroup(title: nil, exercises: exercises)]
    }

    let recommended = exercises.filter { $0.recommendedFor.contains(modality) }
    let others = exercises.filter { !$0.recommendedFor.contains(modality) }
    guard !recommended.isEmpty, !others.isEmpty else {
        return [WatchExerciseGroup(title: nil, exercises: exercises)]
    }

    return [
        WatchExerciseGroup(title: WatchMenuCopy.recommendedGroupTitle, exercises: recommended),
        WatchExerciseGroup(title: WatchMenuCopy.otherGroupTitle, exercises: others),
    ]
}

/// The menu's fixed copy, and the confirmation's (D-3401).
///
/// It lives here rather than on the view, which compiles only into a watch
/// target: this is the half the suite can read. The confirmation's words are
/// the phone's own sibling dialog (`workout_session_finish.dart`), so the two
/// ends ask the same question in the same words.
public enum WatchMenuCopy {
    /// The menu's one action row: it ends the session, so it says so.
    public static let finishLabel = "End Session"

    /// The menu's other action row: it opens the wrist's own exercise list
    /// (D-3608).
    public static let addExerciseLabel = "Add Exercise"

    /// What the Add Exercise list is called, on the pushed surface and in its
    /// title bar.
    public static let addExerciseTitle = "Add Exercise"

    /// The first group's header, when the list splits into two: the phone's own
    /// picker's word for the exercises its rule recommends (plan 199, D-19903).
    public static let recommendedGroupTitle = "Recommended"

    /// The second group's header: the phone's own word for everything its rule
    /// does not recommend (plan 199, D-19903).
    public static let otherGroupTitle = "Other"

    /// Said in place of rows when the phone has sent no exercise down yet.
    public static let addExerciseEmpty = "No exercises yet. Sync with your phone."

    public static let confirmTitle = "Finish Workout?"
    public static let confirmBody = "This action will save and close the workout session."
    public static let confirmCancel = "Cancel"
    public static let confirmFinish = "Finish"

    /// The menu's third action row: it throws the session away, so both the row
    /// and its confirmation say so (plan 171 D-17104). The body names what is
    /// lost and where the user lands, because a discard cannot be undone.
    public static let discardLabel = "Discard Session"
    public static let discardConfirmTitle = "Discard session?"
    public static let discardConfirmBody = "This will permanently delete this session and all its data. You will return to the start screen."
    public static let discardConfirmCancel = "Cancel"
    public static let discardConfirmDiscard = "Discard"
}

/// The id a slot answers to: its own `sessionExerciseId`, or the exercise's when
/// the slot carries none. What a menu row is keyed by and what a jump names.
private func menuSlotId(of slot: [String: Any], _ exercise: WatchCatalogExercise) -> String {
    (slot["sessionExerciseId"] as? String) ?? exercise.slotId
}

/// The session's ladder as menu rows, in the session's own order.
///
/// A slot `WatchCatalogExercise(slot:)` rejects — no exercise id or no name — is
/// skipped, exactly as the picker's own rows skip it. `isCurrent` compares the
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
        let slotId = menuSlotId(of: slot, exercise)
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
/// re-runs the view body. `rows` is derived on every read and never cached.
public final class WatchMenuState {
    private let engine: WatchSessionEngine

    /// The start paths, so a jump goes through the session's own select path.
    private let paths: WatchSessionStartPaths

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

    /// The ladder's own slot, read here rather than out of a list of the
    /// exercises the wrist could add: nil when the session does not hold it.
    private func ladderSlot(_ slotId: String) -> [String: Any]? {
        (engine.session?.exercises ?? []).first { slot in
            guard let exercise = WatchCatalogExercise(slot: slot) else { return false }
            return menuSlotId(of: slot, exercise) == slotId
        }
    }

    /// Whether a work clock is running on the session, so a jump would change
    /// the exercise out from under the effort being logged (D-1309).
    ///
    /// The three kinds a work clock can be — the elapsed count-up, a drill's
    /// hold and a period's countdown — read through `engine.timerFor`, which is
    /// already scoped to the current session. A rest is not work, so its row
    /// leaves the menu free.
    public var isLocked: Bool {
        let workKinds = [WatchTimerKind.elapsed, WatchTimerKind.hold, WatchTimerKind.round]
        return workKinds.contains { kind in
            guard let timer = engine.timerFor(kind) else { return false }
            return timer.state != WatchTimerState.stopped
        }
    }

    /// Moves the session to the slot `slotId` names, through the existing
    /// select path. False when the slot is gone by the time the tap lands, which
    /// changes nothing.
    ///
    /// A work clock running also refuses the jump, before the slot lookup, so a
    /// tap on a vanished slot is refused for the lock's reason too (D-1309).
    @discardableResult
    public func jump(to slotId: String) async -> Bool {
        guard !isLocked else { return false }
        guard let slot = ladderSlot(slotId), let exercise = WatchCatalogExercise(slot: slot) else {
            return false
        }
        return await paths.selectExercise(.inSession(slotId: slotId, exercise: exercise)) != nil
    }

    /// Finishes the session through the rating state's `end()`, so the owed
    /// rating prompt and `finishSession()` stay one implementation.
    ///
    /// A session with nothing logged is a discard instead (D-17105): there is
    /// nothing to save and nothing to rate, which is also what the phone's own
    /// empty finish does. The menu asks the discard's question for it.
    public func finish() async {
        guard hasLoggedEfforts else {
            await discard()
            return
        }
        await rating.end()
    }

    /// Whether the session holds an effort the user logged — what End reads to
    /// tell a workout worth saving from an empty one (D-17105).
    ///
    /// Efforts only: a rest, a water tap and a food entry are not the workout,
    /// so an End on a session holding nothing but those is still an empty one.
    /// Read on every access, like `rows`.
    public var hasLoggedEfforts: Bool {
        engine.entries.contains { WatchObservationKind.efforts.contains($0.kind) }
    }

    /// Throws the session away, through the engine's own abandonment: the
    /// session ends `abandoned`, its timers stop and the phone hears the
    /// terminal lifecycle frame it already knows how to apply (D-17102).
    ///
    /// Deliberately not behind `isLocked` and deliberately not through the
    /// rating state: a session the user cannot finish is exactly the one they
    /// need a way out of (D-17103), and a discarded workout owes no rating
    /// (D-17105). No session, or one that has already ended, changes nothing —
    /// the engine's terminal guard hands back the held row, so the return value
    /// is the record that stands.
    @discardableResult
    public func discard() async -> WatchSessionRecord? {
        guard engine.session != nil else { return nil }
        return await engine.abandonSession()
    }

    // MARK: - Add Exercise

    /// Everything the user could add, A to Z, from the list the phone sent down
    /// (23c, D-3605).
    public var addableExercises: [WatchCatalogExercise] { paths.addableExercises }

    /// The Add Exercise list split into the groups it is read in, in the list's
    /// own order (plan 199, D-19905).
    public var addExerciseGroups: [WatchExerciseGroup] {
        deriveExerciseGroups(addableExercises, modality: paths.listModality)
    }

    /// Adds `exercise` at the end of the ladder, through the start paths.
    ///
    /// Deliberately not behind `isLocked`: adding moves nothing the running
    /// effort is logging, unlike a jump (D-3607). False — and no change — when
    /// there is no session or it is no longer active, so a stale menu cannot
    /// grow a closed session.
    @discardableResult
    public func addExercise(_ exercise: WatchCatalogExercise) async -> Bool {
        guard let session = engine.session, session.status == WatchSessionStatus.active else {
            return false
        }
        await paths.addExerciseToEnd(exercise)
        return true
    }
}
