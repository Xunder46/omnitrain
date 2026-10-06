//
//  WatchEffortRating.swift
//  WatchSessionEngine
//
//  The session effort rating on the wrist: the End action that may owe one, the
//  prompt that asks for it, and the single answer it records.
//
//  Plan: `docs/plans/2026-09-25-02-stats-pr2-watch-capture-plan.md`,
//  D-113, D-114 and D-116 – D-119, scenarios S-211 – S-220.
//
//  Everything here is state. The prompt and End views
//  (`WatchEffortRatingView.swift`) only bind to it, and they compile only into
//  a watch target, so this is the part `swift test` proves.
//
//  Once owed, the prompt has one way out: an answer. Nothing here puts it off
//  or sets it aside, and the suite fails if a name or a button suggesting
//  otherwise appears in this file or the view's (`WatchEffortRatingTests`).
//

import Combine
import Foundation

/// The question, its scale and the words at its two ends, as
/// `watch/contract/watch_effort_rating_contract.json` states them. The suite
/// holds these values to the contract, and the phone's own rating sheet is held
/// to the same file, so both devices ask the same question.
public enum WatchEffortRatingCopy {
    public static let title = "How hard was this session?"
    public static let lowest = 1
    public static let highest = 5
    public static let lowestLabel = "Very easy"
    public static let highestLabel = "Max effort"

    /// A wrist that has never received the phone's preferences does not ask
    /// (D-114).
    public static let promptBeforeFirstSync = false
}

/// The wrist's own record that its End owed a session an effort rating (D-117).
///
/// Written when the End happens, never held only in memory, so a kill before
/// the answer still asks at the next launch. It is answered by the session's
/// `effort_rating`, never by a second row.
public struct WatchRatingPromptRecord {
    public let recordId: String
    public let sessionId: String
    public let recordedAt: Date
    public let sequence: Int

    public init(recordId: String, sessionId: String, recordedAt: Date, sequence: Int = 0) {
        self.recordId = recordId
        self.sessionId = sessionId
        self.recordedAt = recordedAt
        self.sequence = sequence
    }

    /// The one id a session's prompt is stored under, so noting it twice is a
    /// store no-op.
    public static func recordIdFor(_ sessionId: String) -> String { "prompt-\(sessionId)" }

    public func withSequence(_ sequence: Int) -> WatchRatingPromptRecord {
        WatchRatingPromptRecord(
            recordId: recordId,
            sessionId: sessionId,
            recordedAt: recordedAt,
            sequence: sequence
        )
    }

    public func toJson() -> [String: Any] {
        [
            "recordType": StoredWatchRecord.ratingPromptType,
            "recordId": recordId,
            "sessionId": sessionId,
            "recordedAt": utcIso(recordedAt),
            "sequence": sequence,
        ]
    }

    public static func fromJson(_ json: [String: Any]) throws -> WatchRatingPromptRecord {
        WatchRatingPromptRecord(
            recordId: try requiredString(json, "recordId"),
            sessionId: try requiredString(json, "sessionId"),
            recordedAt: try parseUtcIso(json["recordedAt"]),
            sequence: (json["sequence"] as? NSNumber)?.intValue ?? 0
        )
    }
}

/// The End control and the effort-rating prompt, as state the views bind to.
public final class WatchEffortRatingState: ObservableObject {
    public let engine: WatchSessionEngine

    /// Crown travel the system reports to each side of the origin, in detents:
    /// enough to cross the whole scale either way. The prompt view configures
    /// its rotation from this, and the readings it can report never leave it.
    public static let crownRangeDetents = 10.0

    private let store: WatchSessionStore
    private let preferences: WatchPhonePreferences
    private let clock: () -> Date

    /// The prompts the wrist's End has owed, oldest first.
    private var prompts: [WatchRatingPromptRecord] = []

    /// The number the user has picked, or nil while nothing is: nothing is
    /// preselected (D-118).
    @Published public private(set) var selected: Int?

    /// Where the crown last was, and the travel not yet worth a whole detent.
    private var crownPosition: Double = 0
    private var crownCarry: Double = 0

    public init(
        engine: WatchSessionEngine,
        store: WatchSessionStore,
        preferences: WatchPhonePreferences,
        clock: @escaping () -> Date = { Date() }
    ) {
        self.engine = engine
        self.store = store
        self.preferences = preferences
        self.clock = clock
    }

    /// Reads the owed prompts back out of storage. Call on launch, after the
    /// engine has restored.
    public func restore() async {
        let owed = await store.readAll().ratingPrompts
        objectWillChange.send()
        prompts = owed
    }

    // MARK: - The End control

    /// Whether there is a running session for End to finish.
    public var canEnd: Bool { engine.session?.status == WatchSessionStatus.active }

    /// The wrist's own End: finishes the session and, when a rating is owed,
    /// records that it is (D-117).
    ///
    /// Owed means the phone's setting, as last synced, asks for it; the session
    /// holds at least one effort entry after the phone's deletions; and it has no
    /// rating yet. That is decided before the session ends, because the phone's
    /// deletions are known only to this process — which is also why the answer
    /// is stored rather than recomputed at the next launch.
    @discardableResult
    public func end() async -> WatchSessionRecord? {
        guard let session = engine.session, session.status == WatchSessionStatus.active else {
            return nil
        }
        let owed = isRatingOwed(session.sessionId)

        let ended = await engine.finishSession()
        if owed { await noteOwedPrompt(session.sessionId) }
        objectWillChange.send()
        return ended
    }

    private func isRatingOwed(_ sessionId: String) -> Bool {
        preferences.asksForEffortRating
            && engine.entries.contains { WatchObservationKind.efforts.contains($0.kind) }
            && !engine.hasEffortRating(sessionId)
    }

    private func noteOwedPrompt(_ sessionId: String) async {
        let stored = await store.append(
            .ratingPrompt(
                WatchRatingPromptRecord(
                    recordId: WatchRatingPromptRecord.recordIdFor(sessionId),
                    sessionId: sessionId,
                    recordedAt: clock()
                )
            )
        )
        guard case .ratingPrompt(let row) = stored,
              !prompts.contains(where: { $0.recordId == row.recordId })
        else { return }
        prompts.append(row)
    }

    // MARK: - The prompt

    /// The sessions that owe an answer, most recent first: every owed prompt
    /// whose session has no rating — kept or acknowledged — yet.
    public var owedSessionIds: [String] {
        prompts
            .filter { !engine.hasEffortRating($0.sessionId) }
            .sorted { $0.sequence > $1.sequence }
            .map(\.sessionId)
    }

    /// The session the prompt is asking about, or nil when nothing is owed.
    public var promptSessionId: String? { owedSessionIds.first }

    public var isPromptOwed: Bool { promptSessionId != nil }

    public var title: String { WatchEffortRatingCopy.title }

    public var scale: [Int] { Array(WatchEffortRatingCopy.lowest...WatchEffortRatingCopy.highest) }

    public var lowestLabel: String { WatchEffortRatingCopy.lowestLabel }

    public var highestLabel: String { WatchEffortRatingCopy.highestLabel }

    /// Confirm is enabled only once a number is picked, and only while a prompt
    /// is owed.
    public var canConfirm: Bool { isPromptOwed && selected != nil }

    /// The crown's position, in points, for the view's binding.
    public var crownPoints: Double { crownPosition }

    /// A crown event: the position it now reports, turned into whole detents of
    /// `WatchMetricStepping.pointsPerDetent`; travel short of a detent is
    /// carried to the next event.
    ///
    /// A reading further from the last one than the whole range is a wrap, not
    /// a turn (F-7): a continuous crown reports leaving one end and arriving at
    /// the other with nothing in between, and a plain delta would read that as
    /// travel of twice the range. The prompt view asks for a discontinuous
    /// crown; this is the guard behind it, and it is here because the view is
    /// watchOS-only and this is the half the suite can prove.
    public func turnCrown(to position: Double) {
        let moved = position - crownPosition
        crownPosition = position

        let range = Self.crownRangeDetents * WatchMetricStepping.pointsPerDetent
        guard abs(moved) <= range else {
            crownCarry = 0
            return
        }

        let waiting = crownCarry + moved
        let detents = (waiting / WatchMetricStepping.pointsPerDetent).rounded(.towardZero)
        crownCarry = waiting - detents * WatchMetricStepping.pointsPerDetent
        guard detents != 0 else { return }
        step(Int(detents))
    }

    /// `detents` crown steps (D-118). From nothing picked, the first clockwise
    /// step picks the lowest number; further steps move one number each and stop
    /// at either end. Counter-clockwise never returns to nothing picked, and from
    /// nothing picked it picks nothing.
    public func step(_ detents: Int) {
        guard detents != 0 else { return }
        let lowest = WatchEffortRatingCopy.lowest
        let highest = WatchEffortRatingCopy.highest

        if let current = selected {
            selected = min(max(current + detents, lowest), highest)
        } else if detents > 0 {
            selected = min(lowest + detents - 1, highest)
        }
    }

    /// A tap on a number of the scale.
    public func select(_ value: Int) {
        guard scale.contains(value) else { return }
        selected = value
    }

    /// Records the picked number as the owed session's effort rating, through
    /// the engine's append path (D-116), and returns it — or nil, recording
    /// nothing, when nothing is picked or nothing is owed. The session then owes
    /// nothing more: a rating is never edited and never added twice.
    @discardableResult
    public func confirm() async throws -> WatchObservationRecord? {
        guard let sessionId = promptSessionId, let rating = selected else { return nil }

        let recorded = try await engine.recordEffortRating(rating, sessionId: sessionId)
        selected = nil
        crownPosition = 0
        crownCarry = 0
        objectWillChange.send()
        return recorded
    }
}
