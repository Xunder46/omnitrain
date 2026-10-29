//
//  WatchMenu.swift
//  WatchSessionEngine
//
//  The session menu's model: the ladder as rows, the jump, and Finish. `rows` is
//  a pure function over the session and the engine's corrected projection, read
//  on every access rather than cached, so a frame that lands while the menu is
//  open is already in the list the user sees.
//
//  The menu writes no session structure of its own: a jump is the engine's
//  `selectExercise(slotId:)` through the start paths, Finish is the rating
//  state's `end()`, and Add Exercise is the start paths' `addExerciseToEnd`,
//  which appends at the end of the ladder and nowhere else. It mints no ids of
//  its own and appends no observation.
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

/// One letter of the Add Exercise list's jump grid, and the exercise a tap on
/// it brings to the top (D-3850).
///
/// The pair is the whole entry: the key's own letter, and the id of the first
/// exercise whose name keys to it in the list's order. The grid reads the
/// letter, the tap names the id, and neither is derived again on the wrist.
public struct WatchAddExerciseLetter: Equatable {
    /// The key: a name's first character uppercased when it is a letter,
    /// otherwise `"#"`.
    public let letter: String

    /// The `exerciseId` of the list's first exercise with this key.
    public let firstExerciseId: String

    public init(letter: String, firstExerciseId: String) {
        self.letter = letter
        self.firstExerciseId = firstExerciseId
    }
}

/// The key a name sorts under in the Add Exercise grid: its first character
/// uppercased when that character is a letter, otherwise `"#"` (D-3850).
///
/// The key is read from the FIRST character as it is, whitespace included: a
/// name that starts with whitespace keys to `"#"`, like a name with nothing to
/// read at all. The list sorts that name into the `#` run — a leading space
/// sorts before every letter — so reading past the whitespace would point an
/// entry at a region the name does not sit in and break the grid's contiguity.
/// The uppercasing is `String.uppercased()`, the same text the list's own
/// lowercase sort uses, and deliberately not a locale collation: the grid must
/// agree with the order the user reads.
func addExerciseLetterKey(of name: String) -> String {
    guard let first = name.first else { return "#" }
    return first.isLetter ? String(first).uppercased() : "#"
}

/// The list's letters in the order it shows them: one entry per distinct key,
/// keyed at the first exercise that carries it (D-3850).
///
/// `exercises` is `addableExercises`, so the entries come out in the list's own
/// A-to-Z order rather than alphabetical by key: a `#` run opens the grid — a
/// name that is empty, starts with whitespace, a digit or a symbol sits there,
/// because the list puts it before every letter — and an accented letter sits
/// wherever the plain-lowercase sort put it.
public func deriveAddExerciseLetters(
    _ exercises: [WatchCatalogExercise]
) -> [WatchAddExerciseLetter] {
    var seen = Set<String>()
    var letters: [WatchAddExerciseLetter] = []

    for exercise in exercises {
        let key = addExerciseLetterKey(of: exercise.name)
        guard seen.insert(key).inserted else { continue }
        letters.append(
            WatchAddExerciseLetter(letter: key, firstExerciseId: exercise.exerciseId)
        )
    }

    return letters
}

/// One run of a list the user reads: the key every exercise in it wears and
/// those exercises, in the list's own order (D-3104, D-3110).
///
/// The runs are contiguous rather than one-per-key: a key that appears again
/// after another key opens a second section, because the concatenation of a
/// list's sections is that list — nothing dropped, nothing repeated, nothing
/// reordered. `deriveAddExerciseLetters` may skip a repeat, since a jump needs
/// one target per key; a list that is read needs every row once.
public struct WatchExerciseSection: Equatable {
    /// The key the run sorts under: the same key `WatchAddExerciseLetter`
    /// carries, read through `addExerciseLetterKey(of:)`.
    public let letter: String

    public let exercises: [WatchCatalogExercise]

    public init(letter: String, exercises: [WatchCatalogExercise]) {
        self.letter = letter
        self.exercises = exercises
    }
}

/// The list split into the runs it is read in: one section per key, in the
/// list's own order, keyed through `addExerciseLetterKey(of:)` (D-3110).
///
/// Pure, one pass, no sorting: an A-to-Z input (`addableExercises`) comes back
/// with the `#` run first and an accented name last, exactly as it was handed
/// over.
public func deriveExerciseSections(
    _ exercises: [WatchCatalogExercise]
) -> [WatchExerciseSection] {
    var sections: [WatchExerciseSection] = []
    var open: [WatchCatalogExercise] = []
    var openKey: String?

    for exercise in exercises {
        let key = addExerciseLetterKey(of: exercise.name)
        if key == openKey {
            open.append(exercise)
            continue
        }

        if let openKey {
            sections.append(WatchExerciseSection(letter: openKey, exercises: open))
        }
        openKey = key
        open = [exercise]
    }

    if let openKey {
        sections.append(WatchExerciseSection(letter: openKey, exercises: open))
    }

    return sections
}

/// The letters a list's sections carry as scroll ids: the first run of every
/// key, once each, in the sections' own order (D-3117).
///
/// One `ScrollViewReader` may hold only one view per id, and
/// `deriveExerciseSections` opens a second section whenever a key reappears — a
/// digit name sorts before `A` and a `~` name after `Z`, so `#` can open twice.
/// The grid jumps by letter, so the id sits on the run that letter names and the
/// later runs carry none: the reader's ids are exactly the grid's letters, and a
/// tap lands on the first run the grid's entry points at.
public func scrollTargetLetters(of sections: [WatchExerciseSection]) -> [String] {
    var seen = Set<String>()
    var letters: [String] = []

    for section in sections where seen.insert(section.letter).inserted {
        letters.append(section.letter)
    }

    return letters
}

/// The letters a list jumps by: the list's entries, or none at all while it is
/// short enough to scroll by hand (D-3851, D-3110).
///
/// The one home of `WatchMenuCopy.addLetterGridThreshold`. Both surfaces that
/// show the grid — the menu's Add Exercise list and the picker's — read this,
/// never the literal, so the two cannot disagree about where the grid begins.
/// A pure function of the list it is given: the caller decides which list that
/// is (`WatchMenuState.addableExercises`, `WatchStartPaths.availablePickerExercises`).
public func deriveExerciseListLetters(
    _ exercises: [WatchCatalogExercise]
) -> [WatchAddExerciseLetter] {
    guard exercises.count > WatchMenuCopy.addLetterGridThreshold else { return [] }
    return deriveAddExerciseLetters(exercises)
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

    /// Said in place of rows when the phone has sent no exercise down yet.
    public static let addExerciseEmpty = "No exercises yet. Sync with your phone."

    /// How many exercises the Add Exercise list may hold and still fit a few
    /// scrolls: at or below this count the letter grid would cost more than it
    /// saves, so it is not shown (D-3851).
    public static let addLetterGridThreshold: Int = 20

    /// What one letter button of the Add Exercise grid says to VoiceOver
    /// (D-3852).
    public static func addLetterJumpLabel(_ letter: String) -> String {
        "Jump to \(letter)"
    }

    public static let confirmTitle = "Finish Workout?"
    public static let confirmBody = "This action will save and close the workout session."
    public static let confirmCancel = "Cancel"
    public static let confirmFinish = "Finish"
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
    public func finish() async {
        await rating.end()
    }

    // MARK: - Add Exercise

    /// Everything the user could add, A to Z, from the list the phone sent down
    /// (23c, D-3605).
    public var addableExercises: [WatchCatalogExercise] { paths.addableExercises }

    /// The letters the Add Exercise list jumps by, in the list's own order, or
    /// `[]` when the list is short enough to scroll by hand (D-3850, D-3851).
    ///
    /// A pure function of `addableExercises`, read on every access: a list that
    /// changes size across the threshold gains or loses the grid with it. The
    /// threshold itself lives once, in `deriveExerciseListLetters`, which the
    /// picker reads too (D-3110).
    public var addExerciseLetters: [WatchAddExerciseLetter] {
        deriveExerciseListLetters(addableExercises)
    }

    /// The Add Exercise list split into the runs it is read in, in the list's
    /// own order (D-3104, D-3110).
    public var addExerciseSections: [WatchExerciseSection] {
        deriveExerciseSections(addableExercises)
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
