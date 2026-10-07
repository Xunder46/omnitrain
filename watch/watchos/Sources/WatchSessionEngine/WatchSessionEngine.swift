//
//  WatchSessionEngine.swift
//  WatchSessionEngine
//
//  The watch session engine: one training session, no phone required. Mirrors
//  `lib/watch/session/watch_session_engine.dart` call for call, so the two
//  watch clients behave identically given the same input — which is what the
//  plan's parity criterion asks for.
//
//  Two invariants shape this class:
//
//  1. A logged set is never lost. Every observation reaches storage before
//     anything is emitted, and everything the engine needs to continue is read
//     back from storage by `restore()`. Nothing authoritative lives only in
//     memory, so a suspension, an OS kill, or a reboot costs the user nothing.
//  2. The watch never edits or deletes. The engine appends new rows; it cannot
//     rewrite one. Position and timer state advance by appending, and data is
//     dropped only through `pruneConfirmed()`, gated on the phone's receipt.
//

import Foundation

/// Where the engine hands the messages the watch owes the phone.
public typealias WatchMessageSink = ([String: Any]) -> Void

/// Thrown when a message fails protocol conformance. Nothing was persisted and
/// nothing was emitted: the message never existed.
public struct WatchEmissionRejected: Error, CustomStringConvertible {
    public let message: String
    public let rejections: [SyncProtocolRejection]

    public var description: String { message }
}

public final class WatchSessionEngine {
    private let store: WatchSessionStore
    private let onEmit: WatchMessageSink?
    private let validator: SyncProtocolValidator?
    private let clock: () -> Date
    private let newId: () -> String
    private let newSessionId: () -> String

    /// Record-id prefixes for the rows a message from the phone writes. The id
    /// is derived from the `changeId` (or `messageId`) that caused the row,
    /// which is what makes re-delivery a store no-op *and* what lets `restore`
    /// rebuild "already applied" from storage instead of from memory.
    private static let changePrefix = "chg-"
    private static let snapshotPrefix = "snap-"
    private static let timerPrefix = "tms-"
    private static let lifecyclePrefix = "life-"

    private var sessionRows: [WatchSessionRecord] = []
    private var storedObservations: [WatchObservationRecord] = []
    private var storedTimers: [WatchTimerRecord] = []
    private var storedSensorSamples: [WatchSensorSampleRecord] = []

    /// The structure changes this watch has already applied, by `changeId`.
    /// Rebuilt from storage by `restore`, so a relaunch cannot apply one twice
    /// (PROTOCOL.md, authority rule 6).
    private var appliedChangeIds: Set<String> = []

    /// The phone's corrections to entries the watch holds, keyed by `entryId`,
    /// and the ones it deleted. The stored row is never rewritten — these are
    /// what `entries` folds in.
    private var entryCorrections: [String: [String: Any]] = [:]
    private var deletedEntryIds: Set<String> = []

    /// The ids whose held row the phone **replaced** rather than corrected: its
    /// snapshot re-stated the id with a different `loggedAt`, which is a
    /// different entry reusing a minted number (D-113.3). A correction merges
    /// into the held payload; a replacement is the whole payload.
    private var replacedEntryIds: Set<String> = []

    /// Every observation the phone has acknowledged, by record id — including
    /// the ones pruned since. A confirmation row outlives the observation it
    /// names, which is what lets "this session's end was acknowledged" and "this
    /// session already has one" be answered after a prune.
    private var acknowledgedObservationIds: Set<String> = []

    /// The two statuses a session ends in, and the source a session the wrist
    /// itself created carries.
    private static let terminalStatuses: Set<String> = [
        WatchSessionStatus.completed,
        WatchSessionStatus.abandoned,
    ]
    private static let wristSource = "watch"

    private var current: WatchSessionRecord?

    public init(
        store: WatchSessionStore,
        onEmit: WatchMessageSink? = nil,
        validator: SyncProtocolValidator? = nil,
        clock: @escaping () -> Date = { Date() },
        idFactory: @escaping () -> String = { UUID().uuidString },
        sessionIdFactory: @escaping () -> String = { UUID().uuidString }
    ) {
        self.store = store
        self.onEmit = onEmit
        self.validator = validator
        self.clock = clock
        self.newId = idFactory
        self.newSessionId = sessionIdFactory
    }

    // MARK: - Restore

    /// Rebuilds the in-progress session from storage. Call on launch and after
    /// any suspension: what comes back is what the watch knew at kill time,
    /// because nothing else was ever authoritative.
    public func restore() async {
        let contents = await store.readAll()

        sessionRows = contents.sessions
        storedObservations = contents.observations
        storedTimers = contents.timers
        storedSensorSamples = contents.sensorSamples
        acknowledgedObservationIds = Set(contents.confirmations.flatMap(\.observationIds))

        current = contents.sessions.max { $0.sequence < $1.sequence }
        appliedChangeIds = Set(
            contents.sessions
                .filter { $0.recordId.hasPrefix(Self.changePrefix) }
                .map { String($0.recordId.dropFirst(Self.changePrefix.count)) }
        )

        // D-113.1: the deletion lens is read back from the newest row, so a
        // relaunch hides the same entries the killed process hid.
        deletedEntryIds = Set(current?.deletedEntryIds ?? [])
    }

    // MARK: - Session state

    public var session: WatchSessionRecord? { current }

    public var currentExercise: [String: Any]? { current?.currentExercise }

    /// The current session's observations, in the order they were logged.
    public var observations: [WatchObservationRecord] {
        storedObservations.filter { $0.sessionId == current?.sessionId }
    }

    /// The readings the platform sensors produced for the current session, in
    /// the order they arrived.
    ///
    /// Read back from storage, never from a live subscription: the newest heart
    /// rate on the wrist is the newest row that reached the store, so a relaunch
    /// shows what the watch measured instead of starting from nothing.
    public var sensorSamples: [WatchSensorSampleRecord] {
        storedSensorSamples.filter { $0.sessionId == current?.sessionId }
    }

    /// The newest reading of `kind` for the current session, or nil when there
    /// has been none.
    public func newestSensorSample(_ kind: String) -> WatchSensorSampleRecord? {
        newestSensorSamples()[kind]
    }

    /// The newest reading of each kind, keyed by `WatchSensorKind` — one pass
    /// over the session's samples.
    ///
    /// A readout needs several kinds at once (the beat, the distance, the pace
    /// that divides them) and it is rebuilt on a one-second tick, so the caller
    /// resolves the session's measurements once rather than scanning per value.
    public func newestSensorSamples() -> [String: WatchSensorSampleRecord] {
        var newest: [String: WatchSensorSampleRecord] = [:]

        for sample in storedSensorSamples where sample.sessionId == current?.sessionId {
            if let existing = newest[sample.kind], existing.sequence >= sample.sequence {
                continue
            }
            newest[sample.kind] = sample
        }

        return newest
    }

    /// The newest row for `kind`, which is the timer that applies.
    public func timerFor(_ kind: String) -> WatchTimerRecord? {
        newestTimer(kind: kind)
    }

    /// Every stored row of the current session's `kind` timers, oldest first:
    /// the history a round's pauses are read back from (D-122 c), where
    /// `timerFor` gives only the row that applies now.
    public func timerRows(_ kind: String) -> [WatchTimerRecord] {
        storedTimers
            .filter { $0.sessionId == current?.sessionId && $0.kind == kind }
            .sorted { $0.sequence < $1.sequence }
    }

    /// The session's entries as the wrist shows them: the watch's own log plus
    /// the entries the phone sent, with the phone's corrections folded in and
    /// its deletions dropped, in the order they were logged.
    ///
    /// `observations` is the log as appended — nothing in it is ever rewritten.
    /// A correction is therefore a projection, not an edit, which is what keeps
    /// the store append-only and the phone the only side that can edit history.
    public var entries: [WatchObservationRecord] {
        guard let sessionId = current?.sessionId else { return [] }
        return projectedEntries(sessionId)
    }

    /// `entries` for any session the store holds — what a session end
    /// summarises, whichever session the watch is on when it ends.
    private func projectedEntries(_ sessionId: String) -> [WatchObservationRecord] {
        storedObservations
            .filter { $0.sessionId == sessionId && !deletedEntryIds.contains($0.entryId) }
            .map { observation in
                guard let correction = entryCorrections[observation.entryId] else {
                    return observation
                }
                // D-113.3: a re-stated id with a new stamp **is** the whole
                // entry, so the held row's keys it does not carry are gone with
                // it.
                if replacedEntryIds.contains(observation.entryId) {
                    return observation.withPayload(correction)
                }
                return observation.withPayload(
                    observation.payload.merging(correction) { _, corrected in corrected }
                )
            }
            .sorted(by: Self.byLoggedAtThenEntryId)
    }

    /// The watch's live session as the phone's mirror reads it — the answer to
    /// a snapshot request. Nil when the watch has no session to report.
    ///
    /// Entries travel as `entries`, so a correction the phone sent is not echoed
    /// back as the original, and timers travel as wall-clock state: the phone
    /// derives remaining time from its own clock (PROTOCOL.md, "Timer state").
    public func sessionSnapshot(messageId: String? = nil) -> [String: Any]? {
        guard let session = current else { return nil }

        let envelope: [String: Any] = [
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": messageId ?? self.messageId(for: "snapshot-\(session.recordId)"),
            "sessionId": session.sessionId,
            "type": "session_snapshot",
            "origin": "watch",
            "sentAt": utcIso(clock()),
            "payload": [
                "sessionId": session.sessionId,
                "revision": session.revision,
                "status": session.status,
                "currentExerciseIndex": session.currentExerciseIndex,
                "exercises": session.exercises,
                "entries": entries.map(\.payload),
                "timers": timersJson(),
            ] as [String: Any],
        ]
        try? requireConformant(envelope)
        return envelope
    }

    // MARK: - Lifecycle

    /// Starts a session that needs no phone to run, and announces it.
    ///
    /// `exercises` are the protocol's `sessionExercise` slots — delivered by the
    /// phone when it can reach the watch, or supplied by the start paths (a
    /// routine's efforts, or the exercises the user just picked). They are
    /// persisted with the session so a relaunch knows what the position means.
    ///
    /// The session-started lifecycle event leaves through the same sink as every
    /// other message, so the phone's live mirror learns about a wrist-started
    /// session without being asked (S-006). One snapshot follows it, carrying the
    /// session's own shape: the lifecycle says the wrist started, the snapshot is
    /// what the phone's mirror adopts, and the order is the frame order D-91 fixes
    /// (S-100).
    @discardableResult
    public func createSession(
        modality: String?,
        source: String = "watch",
        exercises: [[String: Any]] = []
    ) async -> WatchSessionRecord {
        let now = clock()
        let row = WatchSessionRecord(
            recordId: newId(),
            sessionId: newSessionId(),
            recordedAt: now,
            startedAt: now,
            modality: modality,
            source: source,
            status: WatchSessionStatus.active,
            currentExerciseIndex: 0,
            exercises: exercises
        )

        let stored = await store.append(.session(row))
        let live = mirrored(stored.sessionRow ?? row)
        emitLifecycle(live, state: WatchLifecycleState.started)
        emitSnapshot()
        return live
    }

    /// Moves to the next exercise. The last exercise is the end of the ladder.
    @discardableResult
    public func advanceExercise() async -> WatchSessionRecord {
        let session = requireSession()
        let lastIndex = session.exercises.isEmpty ? 0 : session.exercises.count - 1
        return await transitionTo(
            currentExerciseIndex: min(session.currentExerciseIndex + 1, lastIndex),
            lifecycle: WatchLifecycleState.exerciseAdvanced
        )
    }

    /// Moves the session to the slot `slotId` names, the way a user picking it
    /// off the ladder would.
    ///
    /// The position is looked up in the session at the moment of the tap rather
    /// than carried by whatever was on screen, so a push that lands in between
    /// cannot leave the session on the wrong exercise. A slot the session no
    /// longer holds returns nil and changes nothing.
    @discardableResult
    public func selectExercise(slotId: String) async -> WatchSessionRecord? {
        guard let session = current,
              let index = session.exercises.firstIndex(where: {
                  $0["sessionExerciseId"] as? String == slotId
              })
        else { return nil }

        return await transitionTo(
            currentExerciseIndex: Self.clampIndex(index, session.exercises.count),
            lifecycle: WatchLifecycleState.exerciseAdvanced
        )
    }

    /// Closes the session as done.
    @discardableResult
    public func finishSession() async -> WatchSessionRecord {
        await transitionTo(
            status: WatchSessionStatus.completed,
            lifecycle: WatchLifecycleState.completed
        )
    }

    /// Closes the session as given up on. Entries already logged stay logged.
    @discardableResult
    public func abandonSession() async -> WatchSessionRecord {
        await transitionTo(
            status: WatchSessionStatus.abandoned,
            lifecycle: WatchLifecycleState.abandoned
        )
    }

    /// Puts `slot` into the session's exercise ladder.
    ///
    /// A slot id already present is dropped rather than added twice, which is
    /// what makes a re-delivered push harmless (PROTOCOL.md, "Exercise
    /// identity"). `moveTo` decides where the position lands: the user's own
    /// pick moves the session to the new exercise, while a structure change the
    /// phone initiated leaves the user on the exercise they were logging — the
    /// rule `lib/core/sync_protocol/session_reconciler.dart` applies to it.
    ///
    /// `announce` tells the wrist's own add from the phone's: the user's add
    /// announces the new shape with a snapshot whose `revision` has moved, while
    /// a slot the phone pushed applies quietly — the phone wrote it, so the phone
    /// is the one that reports it (D-91).
    @discardableResult
    public func insertExercise(
        _ slot: [String: Any],
        atIndex: Int? = nil,
        moveTo: Bool = false,
        announce: Bool = true
    ) async -> WatchSessionRecord {
        let session = requireSession()
        if let slotId = slot["sessionExerciseId"] as? String,
           session.exercises.contains(where: { $0["sessionExerciseId"] as? String == slotId }) {
            return session
        }

        let index = Self.insertionIndex(atIndex ?? session.exercises.count, session.exercises.count)
        var exercises = session.exercises
        exercises.insert(slot, at: index)

        let live = await transitionTo(
            currentExerciseIndex: Self.positionAfterInsert(
                currentIndex: session.currentExerciseIndex,
                insertedAt: index,
                moveTo: moveTo,
                wasEmpty: session.exercises.isEmpty
            ),
            exercises: exercises,
            lifecycle: nil,
            revision: announce ? session.revision + 1 : nil
        )
        if announce { emitSnapshot() }
        return live
    }

    /// Applies an `exercise_push` from the phone: the slot it names lands at the
    /// position it names, and the user stays on the exercise they were logging.
    ///
    /// A message the watch cannot read is refused whole — no half-applied edit.
    /// A readable push that arrives with no session to land in is dropped: a
    /// wrist that never started a workout has no ladder to put it on, and the
    /// next sync is what brings the two devices back together. The push is not
    /// queued and nothing is created for it. It never announces itself back
    /// either: the phone wrote the slot, and a wrist snapshot answering it would
    /// be the wrist claiming a change it did not make (D-91).
    @discardableResult
    public func applyExercisePush(_ envelope: [String: Any]) async throws -> WatchSessionRecord? {
        try requireConformingIncoming(envelope)
        guard guardSession(envelope) else { return nil }
        let payload = (envelope["payload"] as? [String: Any]) ?? [:]
        return await insertExercise(
            (payload["exercise"] as? [String: Any]) ?? [:],
            atIndex: (payload["insertAtIndex"] as? NSNumber)?.intValue,
            announce: false
        )
    }

    // MARK: - Messages from the phone

    /// Applies one message from the phone to the live session.
    ///
    /// This is the watch's half of the reconciliation contract: the same
    /// messages the phone's reference reconciler
    /// (`lib/core/sync_protocol/session_reconciler.dart`) applies, applied to
    /// the append-only store instead of to memory. Applying the same message
    /// twice changes nothing — structure changes are keyed by `changeId`, and
    /// every row a message writes carries an id derived from the message itself.
    ///
    /// Returns true when the message changed something the watch holds, false
    /// when it had nothing for this session (reference data, or an observation —
    /// which only ever travels the other way). A message the watch cannot read is
    /// refused whole: `WatchEmissionRejected` is thrown and nothing is applied.
    @discardableResult
    public func applyMessage(_ envelope: [String: Any]) async throws -> Bool {
        switch envelope["type"] as? String {
        case "session_snapshot":
            try requireConformingIncoming(envelope)
            return await applySnapshot(envelope)
        case "structure_change":
            try requireConformingIncoming(envelope)
            return await applyStructureChange(envelope)
        case "session_lifecycle":
            try requireConformingIncoming(envelope)
            return await applyLifecycle(envelope)
        case "timer_state":
            try requireConformingIncoming(envelope)
            return await applyTimerState(envelope)
        case "exercise_push":
            let before = current?.recordId
            _ = try await applyExercisePush(envelope)
            return current?.recordId != before
        case "observations_up":
            // The watch's own product; a phone has no business sending one. It
            // is still read, so a peer speaking another version is refused here
            // rather than quietly ignored (PROTOCOL.md, "Versioning policy").
            try requireConformingIncoming(envelope)
            return false
        case "receipt":
            try requireConformingIncoming(envelope)
            return await applyReceipt(envelope)
        default:
            return false
        }
    }

    /// A snapshot replaces structure, status, position, revision, and timer
    /// state; entries merge by `entryId` (PROTOCOL.md, "Idempotency and
    /// reconciliation").
    ///
    /// Merging is what makes a wrist log survive the phone's snapshot: an
    /// observation the phone has not seen is still the watch's, and the entries
    /// the snapshot carries are the phone's — stored here as confirmed, because
    /// the phone obviously has them. The snapshot is also the receipt for the
    /// observations it does carry: the watch may drop them.
    private func applySnapshot(_ envelope: [String: Any]) async -> Bool {
        let payload = (envelope["payload"] as? [String: Any]) ?? [:]
        guard let sessionId = payload["sessionId"] as? String,
              let messageId = envelope["messageId"] as? String,
              let sentAt = try? parseUtcIso(envelope["sentAt"])
        else { return false }

        let exercises = (payload["exercises"] as? [[String: Any]]) ?? []
        let entryMaps = (payload["entries"] as? [[String: Any]]) ?? []
        let existing = current?.sessionId == sessionId ? current : nil
        let status = (payload["status"] as? String) ?? WatchSessionStatus.active

        // A snapshot naming another session is refused whole while the wrist is
        // running a workout of its own: the user is in the middle of it, and
        // nothing — no end, no row, no message — may come of a frame that is not
        // about it (D-78). The same snapshot still applies when the wrist holds
        // nothing, or holds a session that has already ended: that is the
        // ordinary case of the phone's next workout arriving. The guard runs
        // before `captureSessionEnd`, so a refused snapshot ends nothing.
        if let held = current,
           held.status == WatchSessionStatus.active,
           !held.exercises.isEmpty,
           held.sessionId != sessionId {
            return false
        }

        // D-113.2: an entry the snapshot carries exists, so its tombstone is
        // cleared — here, before the row that records this state is written,
        // since that row is what `restore` reads the lens back from.
        for entry in entryMaps {
            unhideTheIdTheSnapshotNames(entry)
        }

        // A phone snapshot can be what ends a session the wrist created; its
        // end is the moment the phone sent it (D-120).
        await captureSessionEnd(sessionId, status: status, endedAt: sentAt)

        await storeSessionRow(
            WatchSessionRecord(
                recordId: "\(Self.snapshotPrefix)\(messageId)",
                sessionId: sessionId,
                recordedAt: sentAt,
                startedAt: existing?.startedAt
                    ?? Self.startedAtOf(entryMaps, fallback: sentAt),
                modality: existing?.modality,
                source: existing?.source ?? "phone",
                status: status,
                currentExerciseIndex: Self.clampIndex(
                    (payload["currentExerciseIndex"] as? NSNumber)?.intValue ?? 0,
                    exercises.count
                ),
                exercises: exercises,
                revision: (payload["revision"] as? NSNumber)?.intValue ?? 0
            )
        )

        for entry in entryMaps {
            await storeSnapshotEntry(sessionId, entry)
        }
        _ = await confirmObservations(entryMaps.compactMap { $0["entryId"] as? String })
        _ = await adoptTimers(
            (payload["timers"] as? [String: Any]) ?? [:],
            sessionId: sessionId,
            messageId: messageId,
            recordedAt: sentAt,
            authoritative: true
        )
        return true
    }

    /// Applies one structure change: the ladder, the position that follows from
    /// it, and the phone's corrections to entries the watch holds.
    ///
    /// A slot that is already present is left alone (a re-delivered push must
    /// not duplicate it), a removed slot never takes its entries with it, and a
    /// swap keeps the slot's id so entries logged against it still point at it.
    private func applyStructureChange(_ envelope: [String: Any]) async -> Bool {
        let payload = (envelope["payload"] as? [String: Any]) ?? [:]
        guard guardSession(envelope),
              let session = current,
              let changeId = payload["changeId"] as? String
        else { return false }
        guard appliedChangeIds.insert(changeId).inserted else { return false }

        let ladder = ladderAfter(
            exercises: session.exercises,
            index: session.currentExerciseIndex,
            changes: (payload["changes"] as? [[String: Any]]) ?? []
        )

        await storeSessionRow(
            WatchSessionRecord(
                recordId: "\(Self.changePrefix)\(changeId)",
                sessionId: session.sessionId,
                recordedAt: clock(),
                startedAt: session.startedAt,
                modality: session.modality,
                source: session.source,
                status: session.status,
                currentExerciseIndex: ladder.index,
                exercises: ladder.exercises,
                revision: session.revision + 1
            )
        )
        return true
    }

    /// Applies a lifecycle message from the phone: the most recent status wins,
    /// and an advanced position clamps to the ladder (PROTOCOL.md, "Idempotency
    /// and reconciliation").
    ///
    /// Nothing is echoed back — the phone is telling the watch what it decided,
    /// and answering it with the same news would be noise.
    private func applyLifecycle(_ envelope: [String: Any]) async -> Bool {
        guard guardSession(envelope), let session = current else { return false }

        let payload = (envelope["payload"] as? [String: Any]) ?? [:]
        let state = payload["state"] as? String ?? ""
        let status: String
        switch state {
        case WatchLifecycleState.started: status = WatchSessionStatus.active
        case WatchLifecycleState.completed: status = WatchSessionStatus.completed
        case WatchLifecycleState.abandoned: status = WatchSessionStatus.abandoned
        default: status = session.status
        }
        let index = state == WatchLifecycleState.exerciseAdvanced
            ? Self.clampIndex(
                (payload["exerciseIndex"] as? NSNumber)?.intValue ?? 0,
                session.exercises.count
            )
            : session.currentExerciseIndex
        let recordedAt = (try? parseUtcIso(envelope["sentAt"])) ?? clock()

        // The phone ending a session the wrist created: its end is the moment
        // the message says it happened (D-120).
        await captureSessionEnd(
            session.sessionId,
            status: status,
            endedAt: (try? parseUtcIso(payload["at"])) ?? recordedAt
        )

        await storeSessionRow(
            WatchSessionRecord(
                recordId: "\(Self.lifecyclePrefix)\(envelope["messageId"] as? String ?? newId())",
                sessionId: session.sessionId,
                recordedAt: recordedAt,
                startedAt: session.startedAt,
                modality: session.modality,
                source: session.source,
                status: status,
                currentExerciseIndex: index,
                exercises: session.exercises,
                revision: session.revision
            )
        )
        return true
    }

    /// Applies the phone's receipt: the observations behind `entryIds` are the
    /// phone's now, so the watch may stop re-sending them (PROTOCOL.md,
    /// "Idempotency and reconciliation").
    ///
    /// The receipt carries no sessionId on purpose: a standalone nutrition
    /// quick-log has no session to name, and `session_snapshot` is never the
    /// acknowledgement for one — the phone's mirror does not hold a nutrition
    /// session, so the entry would never come back that way.
    ///
    /// Returns true when it acknowledged something the watch still owed.
    private func applyReceipt(_ envelope: [String: Any]) async -> Bool {
        let payload = (envelope["payload"] as? [String: Any]) ?? [:]
        let entryIds = (payload["entryIds"] as? [Any] ?? []).compactMap { $0 as? String }
        guard !entryIds.isEmpty else { return false }
        return !(await confirmObservations(entryIds)).isEmpty
    }

    /// Applies an incremental timer update: the kinds it names are adopted or
    /// cleared, the kinds it does not name are left alone (PROTOCOL.md, "Timer
    /// state"). Only a snapshot is authoritative for timer state as a whole.
    private func applyTimerState(_ envelope: [String: Any]) async -> Bool {
        guard guardSession(envelope),
              let sessionId = envelope["sessionId"] as? String,
              let messageId = envelope["messageId"] as? String,
              let sentAt = try? parseUtcIso(envelope["sentAt"])
        else { return false }

        let payload = (envelope["payload"] as? [String: Any]) ?? [:]
        return await adoptTimers(
            (payload["timers"] as? [String: Any]) ?? [:],
            sessionId: sessionId,
            messageId: messageId,
            recordedAt: sentAt,
            authoritative: false
        )
    }

    /// Adopts `timers` as the rows that apply. A kind the message names as null
    /// is cleared; a kind it does not name keeps whatever it had, unless the
    /// message is a snapshot and the newest row of that kind is the sender's —
    /// only a snapshot speaks for timer state as a whole, and even then only for
    /// the countdowns it wrote itself (D-80) (PROTOCOL.md, "Timer state").
    ///
    /// Every row's id is derived from the message that named it, so re-delivery
    /// is a no-op and a relaunch cannot tell the difference.
    private func adoptTimers(
        _ timers: [String: Any],
        sessionId: String,
        messageId: String,
        recordedAt: Date,
        authoritative: Bool
    ) async -> Bool {
        var changed = false
        for kind in WatchTimerKind.all {
            let recordId = "\(Self.timerPrefix)\(messageId)-\(kind)"
            guard let timer = timers[kind], !(timer is NSNull) else {
                if timers.keys.contains(kind) || (authoritative && senderWroteTimer(kind)) {
                    changed = await stopTimerFromMessage(
                        kind,
                        sessionId: sessionId,
                        recordId: recordId,
                        stoppedAt: recordedAt
                    ) || changed
                }
                continue
            }
            changed = await adoptTimer(
                (timer as? [String: Any]) ?? [:],
                sessionId: sessionId,
                recordId: recordId,
                recordedAt: recordedAt
            ) || changed
        }
        return changed
    }

    /// A timer the phone told the watch about. It is not news back to the phone,
    /// so nothing is emitted: the phone already decided this.
    private func adoptTimer(
        _ timer: [String: Any],
        sessionId: String,
        recordId: String,
        recordedAt: Date
    ) async -> Bool {
        guard !storedTimers.contains(where: { $0.recordId == recordId }) else {
            return false
        }

        let stored = await store.append(
            .timer(
                WatchTimerRecord(
                    recordId: recordId,
                    sessionId: sessionId,
                    recordedAt: recordedAt,
                    kind: timer["kind"] as? String ?? "",
                    startedAt: (try? parseUtcIso(timer["startedAt"])) ?? recordedAt,
                    pausedAt: try? parseOptionalUtcIso(timer["pausedAt"]),
                    stoppedAt: try? parseOptionalUtcIso(timer["stoppedAt"]),
                    accumulatedPauseMs: (timer["accumulatedPauseMs"] as? NSNumber)?.intValue ?? 0,
                    plannedDurationMs: (timer["plannedDurationMs"] as? NSNumber)?.intValue
                )
            )
        )
        guard let row = stored.timerRow else { return false }
        storedTimers.append(row)
        return true
    }

    /// Stops the newest timer of `kind` by appending its stopped version — the
    /// row that was running is never rewritten.
    ///
    /// The protocol calls this clearing a timer, but nothing here clears
    /// anything: a timer advances by append like every other synced record, and a
    /// store whose contract forbids mutation deserves method names that say so.
    private func stopTimerFromMessage(
        _ kind: String,
        sessionId: String,
        recordId: String,
        stoppedAt: Date
    ) async -> Bool {
        guard let timer = newestTimer(kind: kind),
              timer.state != WatchTimerState.stopped,
              timer.sessionId == sessionId,
              !storedTimers.contains(where: { $0.recordId == recordId })
        else { return false }

        let stored = await store.append(
            .timer(
                timerRowFrom(
                    timer,
                    recordId: recordId,
                    recordedAt: stoppedAt,
                    stoppedAt: stoppedAt
                )
            )
        )
        guard let row = stored.timerRow else { return false }
        storedTimers.append(row)
        return true
    }

    /// Stores an entry the phone sent, in the shape the wrist shows it. Nothing
    /// is emitted: the phone is the source, and the receipt is `entries`.
    ///
    /// An `entryId` the wrist already holds is **re-stated**: the snapshot's
    /// payload folds into the projection `entries` reads, exactly as a
    /// `correct_entry` does, and the stored observation row is left alone — the
    /// log stays append-only, so re-stating a set the phone edited neither
    /// rewrites the row nor doubles it. The phone, receiving, keeps the first
    /// value it stored for an id it holds; only the wrist re-states.
    ///
    /// A re-stated id whose `loggedAt` **differs** is a different entry wearing
    /// a reused number, and replaces the held one outright (D-113.3). An id a
    /// deletion had hidden is shown again, because the phone saying it is there
    /// outranks the phone having said it was gone (D-113.2) — unless the
    /// snapshot only repeats the entry the wrist already holds, stamp and all.
    private func storeSnapshotEntry(_ sessionId: String, _ entry: [String: Any]) async {
        guard let entryId = entry["entryId"] as? String else { return }
        // D-113.2: the phone is the structure authority, so an entry its
        // snapshot carries exists — whatever this watch was told about that id
        // before.
        unhideTheIdTheSnapshotNames(entry)
        if storedObservations.contains(where: { $0.recordId == entryId }) {
            if let held = heldPayload(entryId),
               !Self.sameStamp(held["loggedAt"], entry["loggedAt"]) {
                // D-113.3: the phone mints the highest number + 1, so deleting
                // the newest set of a slot and logging another reuses its id for
                // a different entry. A merge would keep a field the new entry
                // does not carry — the dead entry's Load. The correction is the
                // whole entry.
                entryCorrections[entryId] = entry
                replacedEntryIds.insert(entryId)
                return
            }
            entryCorrections[entryId] = (entryCorrections[entryId] ?? [:])
                .merging(entry) { _, corrected in corrected }
            replacedEntryIds.remove(entryId)
            return
        }

        let stored = await store.append(
            .observation(
                WatchObservationRecord(
                    recordId: entryId,
                    sessionId: sessionId,
                    recordedAt: (try? parseUtcIso(entry["loggedAt"])) ?? clock(),
                    kind: entry["kind"] as? String ?? "",
                    payload: entry
                )
            )
        )
        guard let row = stored.observationRow else { return }
        storedObservations.append(row)
    }

    /// Shows `entry`'s id again — the tombstone it carried no longer stands —
    /// when this snapshot entry outranks what the wrist holds (D-113.2).
    ///
    /// The phone is the structure authority, so an id its snapshot carries
    /// exists — but a snapshot entry that only repeats the row the wrist already
    /// holds, stamp and all, is the stale answer D-115 says the phone stops
    /// sending, and the deletion the wrist was told about is newer than it: the
    /// tombstone stays, and the projection keeps hiding the id. An id the wrist
    /// holds no row for, or one whose `loggedAt` differs — D-113.3's
    /// replacement — is the phone saying something new, and is shown again.
    private func unhideTheIdTheSnapshotNames(_ entry: [String: Any]) {
        guard let entryId = entry["entryId"] as? String else { return }
        if let held = heldPayload(entryId), Self.sameStamp(held["loggedAt"], entry["loggedAt"]) {
            return
        }
        deletedEntryIds.remove(entryId)
    }

    /// The payload `entries` shows for `entryId` right now, before any deletion
    /// — the held row with the phone's correction folded in, or nil when the
    /// wrist holds no row for it.
    private func heldPayload(_ entryId: String) -> [String: Any]? {
        for row in storedObservations where row.recordId == entryId {
            guard let correction = entryCorrections[entryId] else { return row.payload }
            return row.payload.merging(correction) { _, corrected in corrected }
        }
        return nil
    }

    /// Whether two wire `loggedAt` stamps name the same instant.
    private static func sameStamp(_ a: Any?, _ b: Any?) -> Bool {
        if a == nil, b == nil { return true }
        guard let a = a as? String, let b = b as? String else { return false }
        return a == b
    }

    /// Writes a row a message produced, without announcing it back to the phone:
    /// the phone is the author of the news.
    private func storeSessionRow(_ row: WatchSessionRecord) async {
        // Every row carries the lens as it stands, not only the row a structure
        // change writes: a lifecycle row appended after a delete would otherwise
        // be the newest one, and `restore` would read an empty lens back from it
        // (D-113.1).
        var carried = row.deletedEntryIds
        for id in deletedEntryIds.sorted() where !carried.contains(id) {
            carried.append(id)
        }

        let stored = await store.append(.session(row.withDeletedEntryIds(carried)))
        current = mirrored(stored.sessionRow ?? row)
    }

    /// The session's entries in `entryMaps`, oldest first — the moment the
    /// session began, as far as a snapshot can say. Falls back to when the
    /// snapshot was sent when it carries no entries.
    private static func startedAtOf(
        _ entryMaps: [[String: Any]],
        fallback: Date
    ) -> Date {
        entryMaps
            .compactMap { try? parseUtcIso($0["loggedAt"]) }
            .min() ?? fallback
    }

    // MARK: - The ladder

    /// The ladder and position that follow from applying `changes` in order.
    private func ladderAfter(
        exercises: [[String: Any]],
        index: Int,
        changes: [[String: Any]]
    ) -> (exercises: [[String: Any]], index: Int) {
        var ladder = exercises
        var position = index

        for change in changes {
            switch change["kind"] as? String {
            case "add_exercise":
                let slot = (change["exercise"] as? [String: Any]) ?? [:]
                let slotId = slot["sessionExerciseId"] as? String
                if let slotId, Self.indexOfSlot(ladder, slotId) >= 0 { continue }
                let at = Self.insertionIndex(
                    (change["atIndex"] as? NSNumber)?.intValue ?? ladder.count,
                    ladder.count
                )
                let wasEmpty = ladder.isEmpty
                ladder.insert(slot, at: at)
                position = Self.positionAfterInsert(
                    currentIndex: position,
                    insertedAt: at,
                    moveTo: false,
                    wasEmpty: wasEmpty
                )
            case "remove_exercise":
                let slotId = change["sessionExerciseId"] as? String ?? ""
                let at = Self.indexOfSlot(ladder, slotId)
                if at < 0 { continue } // removing something already gone is a no-op
                let currentSlotId = Self.slotIdAt(ladder, position)
                ladder.remove(at: at)
                let moved = currentSlotId.map { Self.indexOfSlot(ladder, $0) } ?? -1
                position = moved >= 0 ? moved : Self.clampIndex(position, ladder.count)
            case "reorder_exercises":
                let currentSlotId = Self.slotIdAt(ladder, position)
                ladder = Self.reordered(
                    ladder,
                    order: (change["order"] as? [String]) ?? []
                )
                let moved = currentSlotId.map { Self.indexOfSlot(ladder, $0) } ?? -1
                position = moved >= 0 ? moved : Self.clampIndex(position, ladder.count)
            case "swap_exercise":
                let slotId = change["sessionExerciseId"] as? String ?? ""
                let at = Self.indexOfSlot(ladder, slotId)
                if at < 0 { continue }
                var swapped = (change["exercise"] as? [String: Any]) ?? [:]
                swapped["sessionExerciseId"] = slotId
                ladder[at] = swapped
            case "correct_entry":
                let entryId = change["entryId"] as? String ?? ""
                let correction = (change["correction"] as? [String: Any]) ?? [:]
                entryCorrections[entryId] = (entryCorrections[entryId] ?? [:])
                    .merging(correction) { _, corrected in corrected }
            case "delete_entry":
                let entryId = change["entryId"] as? String ?? ""
                entryCorrections.removeValue(forKey: entryId)
                replacedEntryIds.remove(entryId)
                deletedEntryIds.insert(entryId)
            default:
                continue
            }
        }

        return (ladder, Self.clampIndex(position, ladder.count))
    }

    /// `exercises` reordered as `order` names them; slots it does not name keep
    /// their relative order after those it does.
    private static func reordered(
        _ exercises: [[String: Any]],
        order: [String]
    ) -> [[String: Any]] {
        var remaining: [String: [String: Any]] = [:]
        for slot in exercises {
            if let slotId = slot["sessionExerciseId"] as? String {
                remaining[slotId] = slot
            }
        }

        var reordered: [[String: Any]] = []
        for slotId in order {
            if let slot = remaining.removeValue(forKey: slotId) {
                reordered.append(slot)
            }
        }
        reordered.append(contentsOf: remaining.values)
        return reordered
    }

    private static func indexOfSlot(_ exercises: [[String: Any]], _ slotId: String) -> Int {
        exercises.firstIndex { $0["sessionExerciseId"] as? String == slotId } ?? -1
    }

    private static func slotIdAt(_ exercises: [[String: Any]], _ index: Int) -> String? {
        guard !exercises.isEmpty else { return nil }
        return exercises[clampIndex(index, exercises.count)]["sessionExerciseId"] as? String
    }

    /// The position after inserting a slot: the position follows the exercise,
    /// not the index, so a slot inserted at or before the current one pushes the
    /// current one along with it. Computed rather than searched for, so there is
    /// no not-found case to fall back from.
    private static func positionAfterInsert(
        currentIndex: Int,
        insertedAt: Int,
        moveTo: Bool,
        wasEmpty: Bool
    ) -> Int {
        if moveTo || wasEmpty { return insertedAt }
        return currentIndex >= insertedAt ? currentIndex + 1 : currentIndex
    }

    /// Where an inserted slot lands: anywhere from the front of the ladder to
    /// after its last exercise — there is one more valid insertion point than
    /// there are exercises.
    private static func insertionIndex(_ index: Int, _ length: Int) -> Int {
        min(max(index, 0), length)
    }

    /// Where a position lands: always on an exercise that exists.
    private static func clampIndex(_ index: Int, _ length: Int) -> Int {
        length == 0 ? 0 : min(max(index, 0), length - 1)
    }

    /// The order the wrist reads entries in: when they were logged, and by id
    /// when two share an instant — the same deterministic order the phone's
    /// reconciler uses.
    private static func byLoggedAtThenEntryId(
        _ a: WatchObservationRecord,
        _ b: WatchObservationRecord
    ) -> Bool {
        let left = a.payload["loggedAt"] as? String ?? ""
        let right = b.payload["loggedAt"] as? String ?? ""
        if left != right { return left < right }
        return a.entryId < b.entryId
    }

    /// The timers that apply, as the protocol's `timers` object: the newest of
    /// each kind, and only while it is running or paused.
    private func timersJson() -> [String: Any] {
        var timers: [String: Any] = [:]
        for kind in WatchTimerKind.all {
            guard let timer = newestTimer(kind: kind),
                  timer.state != WatchTimerState.stopped
            else { continue }
            timers[kind] = timer.toTimerJson()
        }
        return timers
    }

    /// Writes a new session row carrying `status` and `currentExerciseIndex`.
    ///
    /// A state change appends rather than updates, which is what both keeps the
    /// store append-only and makes the position survive a kill. `revision` is
    /// carried over from the session being replaced unless the caller moves it:
    /// the counter is the number the phone reads a shape by, so a change that is
    /// not a shape change leaves it exactly where it was (D-101).
    ///
    /// - Parameter revision: the new row's revision, or nil to keep the current
    ///   session's.
    private func transitionTo(
        status: String? = nil,
        currentExerciseIndex: Int? = nil,
        exercises: [[String: Any]]? = nil,
        lifecycle: String?,
        revision: Int? = nil
    ) async -> WatchSessionRecord {
        let session = requireSession()
        let now = clock()
        if let status {
            // The wrist's own End or abandon: its end is the wrist's clock at
            // this moment, the same instant the new row records (D-120).
            await captureSessionEnd(session.sessionId, status: status, endedAt: now)
        }

        let row = WatchSessionRecord(
            recordId: newId(),
            sessionId: session.sessionId,
            recordedAt: now,
            startedAt: session.startedAt,
            modality: session.modality,
            source: session.source,
            status: status ?? session.status,
            currentExerciseIndex: currentExerciseIndex ?? session.currentExerciseIndex,
            exercises: exercises ?? session.exercises,
            revision: revision ?? session.revision
        )

        let stored = await store.append(.session(row))
        let live = mirrored(stored.sessionRow ?? row)
        if let lifecycle { emitLifecycle(live, state: lifecycle) }
        return live
    }

    /// Records a stored session row in the in-memory mirror retention reads,
    /// and makes it the session the watch is on.
    ///
    /// `restore` rebuilds the mirror from storage; a write that happens while
    /// the process is up has to keep it in step, or a session that never
    /// relaunched would look like it never existed and its sensor log would
    /// never be released.
    @discardableResult
    private func mirrored(_ row: WatchSessionRecord) -> WatchSessionRecord {
        if !sessionRows.contains(where: { $0.recordId == row.recordId }) {
            sessionRows.append(row)
        }
        current = row
        return row
    }

    /// Announces the session's current shape to the phone.
    ///
    /// The wrist's own change is the wrist's to report, and the snapshot
    /// `sessionSnapshot()` already builds is what the phone's mirror adopts — no
    /// new frame type (D-90). Like a lifecycle announcement, a snapshot this
    /// build cannot send is dropped rather than blocking the session the user is
    /// in the middle of; the suites pin the shape.
    private func emitSnapshot() {
        guard let envelope = sessionSnapshot() else { return }
        if let validator, !validator.validateEnvelope(envelope).isEmpty { return }
        emit(envelope)
    }

    /// Tells the phone the session moved, when the protocol accepts the telling.
    ///
    /// A status change is not an observation: the state is the product and the
    /// message is its mirror, so an announcement this build could not send is
    /// dropped rather than blocking the session the user is in the middle of.
    /// The suites pin the shape, so a drift fails there instead of going quiet.
    private func emitLifecycle(_ row: WatchSessionRecord, state: String) {
        let envelope = lifecycle(row, state: state)
        if let validator, !validator.validateEnvelope(envelope).isEmpty { return }
        emit(envelope)
    }

    // MARK: - Observations

    /// Persists `event` and emits it as an `observations_up` message.
    ///
    /// The event is stored before anything is emitted, so a crash in between
    /// costs nothing: `pendingObservations()` rebuilds the message from the
    /// stored row. Logging the same event twice is a no-op.
    @discardableResult
    public func appendObservation(
        _ event: [String: Any]
    ) async throws -> WatchObservationRecord {
        let session = requireSession()
        return try await appendObservation(event, sessionId: session.sessionId)
    }

    /// Persists a food the user quick-logged, and emits it for the phone.
    ///
    /// The one entry point on the wrist that does not need a session: eating is
    /// not a training event, and the surface is reachable with no workout
    /// running (S-006). A log taken while a session is running rides it — a
    /// snack mid-workout is part of that session's story — and one taken
    /// without a session carries the nutrition log's own id, because
    /// `observations_up` requires a session id and the wrist will not invent a
    /// workout (`WatchNutritionSession`).
    ///
    /// `servings` is the portion as a multiple of the food's reference amount,
    /// and `calories` what the phone quoted for it — the event is
    /// self-contained, so the phone materialises the entry without asking the
    /// wrist a question.
    @discardableResult
    public func logNutrition(
        foodId: String,
        servings: Double,
        calories: Double? = nil,
        loggedAt: Date? = nil
    ) async throws -> WatchObservationRecord {
        let now = loggedAt ?? clock()
        let entryId = newId()
        var event: [String: Any] = [
            "entryId": entryId,
            "eventId": entryId,
            "kind": WatchObservationKind.nutritionQuickLog,
            "loggedAt": utcIso(now),
            "foodId": foodId,
            "servings": servings,
        ]
        if let calories { event["calories"] = calories }

        return try await appendObservation(
            event,
            sessionId: current?.sessionId ?? WatchNutritionSession.idFor(now)
        )
    }

    /// The nutrition quick-logs the wrist has taken, oldest first — every
    /// session's, because the surface is reachable with none.
    ///
    /// Read back out of the rows storage already held, which is what makes the
    /// food that moves to the top of the wrist's list survive a relaunch.
    public var nutritionLog: [WatchObservationRecord] {
        storedObservations.filter { $0.kind == WatchObservationKind.nutritionQuickLog }
    }

    /// Storage first, emission second — the order every log on the watch
    /// follows.
    @discardableResult
    private func appendObservation(
        _ event: [String: Any],
        sessionId: String
    ) async throws -> WatchObservationRecord {
        let eventId = event["eventId"] as? String
        let recordId = eventId.flatMap { $0.isEmpty ? nil : $0 } ?? newId()
        let now = clock()

        let record = WatchObservationRecord(
            recordId: recordId,
            sessionId: sessionId,
            recordedAt: now,
            kind: event["kind"] as? String ?? "",
            payload: event
        )

        let envelope = observationsUp(
            sessionId: sessionId,
            record: record,
            sentAt: now,
            messageId: messageId(for: recordId)
        )
        try requireConformant(envelope)

        let alreadyStored = storedObservations.contains { $0.recordId == recordId }
        let stored = await store.append(.observation(record))
        if !alreadyStored, let row = stored.observationRow {
            storedObservations.append(row)
            emit(envelope)
        }
        return stored.observationRow ?? record
    }

    /// Persists a reading the platform sensors produced.
    ///
    /// Storage first, and nothing emitted: a sensor reading is the watch's own
    /// measurement, and the distance that reaches the phone travels as the
    /// `distanceMeters` of the effort logged against it. Appending the same
    /// reading twice — same kind, same instant — is a store no-op, which is what
    /// keeps a duplicated sensor callback from becoming a second row.
    @discardableResult
    public func appendSensorSample(
        kind: String,
        value: Double,
        recordedAt: Date? = nil
    ) async -> WatchSensorSampleRecord {
        let session = requireSession()
        let now = recordedAt ?? clock()

        let record = WatchSensorSampleRecord(
            recordId: WatchSensorSampleRecord.sampleId(
                sessionId: session.sessionId,
                kind: kind,
                at: now
            ),
            sessionId: session.sessionId,
            recordedAt: now,
            kind: kind,
            value: value
        )

        let alreadyStored = storedSensorSamples.contains { $0.recordId == record.recordId }
        let stored = await store.append(.sensorSample(record))
        if !alreadyStored, case .sensorSample(let row) = stored {
            storedSensorSamples.append(row)
        }
        return stored.sensorSampleRow ?? record
    }

    /// Drops the raw sensor log of every session that is over and whose entries
    /// the phone has recorded in full.
    ///
    /// Raw readings are not gated on a receipt of their own — the phone never
    /// receives one, and its mirror has no field for them. What gates them is the
    /// session: once a finished session's entries have all been acknowledged, the
    /// readings that produced them have done their job, and the distance they
    /// measured has already crossed as the logged effort's `distanceMeters`. A
    /// session still running, or one with an entry still awaiting a receipt,
    /// keeps its log — which is what makes the live readout and the settled
    /// distance survive a kill.
    ///
    /// A session the wrist created is held one step longer: until its
    /// `session_end` is stored and acknowledged (D-129). The summaries are
    /// computed from these readings, so the readings stay until the phone holds
    /// what was computed from them — whichever order the prunes run in.
    @discardableResult
    public func pruneSettledSensorSamples() async -> [String] {
        let awaitingReceipt = Set(
            storedObservations.filter { $0.confirmedAt == nil }.map(\.sessionId)
        )

        let settled = newestSessionRows().values
            .filter { session in
                session.status != WatchSessionStatus.active
                    && !awaitingReceipt.contains(session.sessionId)
                    && isEndAcknowledgedWhereOwed(session.sessionId)
                    && storedSensorSamples.contains { $0.sessionId == session.sessionId }
            }
            .map(\.sessionId)

        guard !settled.isEmpty else { return [] }

        let pruned = await store.pruneSensorSamples(settled)
        let dropped = Set(pruned)
        storedSensorSamples.removeAll { dropped.contains($0.recordId) }
        return pruned
    }

    /// The current version of each session the store holds, by session id — the
    /// newest row wins, exactly as `restore` reduces the session the watch is on.
    private func newestSessionRows() -> [String: WatchSessionRecord] {
        var newest: [String: WatchSessionRecord] = [:]
        for row in sessionRows {
            if let existing = newest[row.sessionId], existing.sequence >= row.sequence {
                continue
            }
            newest[row.sessionId] = row
        }
        return newest
    }

    /// The messages the phone still owes a receipt for, rebuilt from storage.
    /// Emission is a projection of the stored rows, so replaying after a kill
    /// sends the same events with the same identifiers.
    ///
    /// Every session's, in the order they were stored — not only the session the
    /// watch is on (D-128). A session that ended while the phone was out of
    /// reach is still owed after the next one starts, and a quick-log taken with
    /// no session (S-006) is owed like any other, under the id it was stored
    /// with.
    public func pendingObservations() -> [[String: Any]] {
        storedObservations
            .filter { $0.confirmedAt == nil }
            .map { observation in
                observationsUp(
                    sessionId: observation.sessionId,
                    record: observation,
                    sentAt: observation.recordedAt,
                    messageId: messageId(for: observation.recordId)
                )
            }
    }

    // MARK: - Session end

    /// Appends the `session_end` of a session the wrist created, the first time
    /// it becomes completed or abandoned — by the wrist's End or abandon, or by
    /// the phone's lifecycle message or snapshot (D-120).
    ///
    /// Called before the row that records the new status, so nothing else is
    /// stored for the session first, and a kill in between leaves the session
    /// still running with its end already owed to the phone rather than ended
    /// with no end the phone could import. A session the wrist joined from the
    /// phone gets none. A session that already has one — reopened and ended
    /// again, or ended by two messages — keeps it: the id is the session's, so
    /// no end is ever re-emitted with different values.
    private func captureSessionEnd(_ sessionId: String, status: String, endedAt: Date) async {
        guard Self.terminalStatuses.contains(status),
              let origin = creationRow(sessionId),
              origin.source == Self.wristSource,
              !knowsObservation(WatchSessionCapture.sessionEndId(sessionId))
        else { return }

        do {
            try await appendObservation(
                sessionEndEvent(origin, status: status, endedAt: endedAt),
                sessionId: sessionId
            )
        } catch {
            // Every value is built within the protocol's own bounds
            // (`WatchSensorSummaries`), so a refusal is a defect here, not bad
            // data — and losing a session's end loses the session on the phone.
            assertionFailure("the protocol refused a session_end: \(error)")
        }
    }

    /// The `session_end` event: when the session ran, how it ended, and the
    /// heart rate over the whole session and over each set block (D-121 to
    /// D-123). A summary with nothing measured is left out, never zeroed.
    private func sessionEndEvent(
        _ origin: WatchSessionRecord,
        status: String,
        endedAt: Date
    ) -> [String: Any] {
        let sessionId = origin.sessionId
        let startedAt = WatchSensorSummaries.wireInstant(origin.startedAt)
        let end = WatchSensorSummaries.wireInstant(endedAt)
        let samples = storedSensorSamples.filter { $0.sessionId == sessionId }
        let id = WatchSessionCapture.sessionEndId(sessionId)

        var event: [String: Any] = [
            "entryId": id,
            "eventId": id,
            "kind": WatchObservationKind.sessionEnd,
            "loggedAt": utcIso(clock()),
            "startedAt": utcIso(startedAt),
            "endedAt": utcIso(end),
            "status": status,
        ]
        if let modality = origin.modality, !modality.isEmpty {
            event["modality"] = modality
        }

        // A round's pause is not a session pause: the session's window is the
        // whole session (D-122 g).
        if let session = WatchSensorSummaries.heartRate(samples, from: startedAt, through: end) {
            event.merge(session.fields) { _, measured in measured }
        }

        let blocks = WatchSensorSummaries
            .blockSpans(projectedEntries(sessionId).map(\.payload), sessionStartedAt: startedAt)
            .compactMap { span -> [String: Any]? in
                guard let pair = WatchSensorSummaries.heartRate(
                    samples,
                    from: span.startedAt,
                    through: span.endedAt
                ) else { return nil }

                var block: [String: Any] = [
                    "sessionExerciseId": span.sessionExerciseId,
                    "exerciseId": span.exerciseId,
                    "startedAt": utcIso(span.startedAt),
                    "endedAt": utcIso(span.endedAt),
                ]
                block.merge(pair.fields) { _, measured in measured }
                return block
            }
        if !blocks.isEmpty {
            event["setBlockHeartRates"] = blocks
        }

        return event
    }

    // MARK: - Effort rating

    /// Whether the wrist holds an effort rating for `sessionId` — still stored,
    /// or acknowledged and pruned since.
    public func hasEffortRating(_ sessionId: String) -> Bool {
        knowsObservation(WatchSessionCapture.effortRatingId(sessionId))
    }

    /// Appends `sessionId`'s effort rating and emits it (D-116), stamped with
    /// the wrist's clock — or does nothing and returns nil when the session
    /// already has one. Nothing on the wrist edits a rating or adds a second.
    @discardableResult
    public func recordEffortRating(
        _ rating: Int,
        sessionId: String
    ) async throws -> WatchObservationRecord? {
        let id = WatchSessionCapture.effortRatingId(sessionId)
        guard !knowsObservation(id) else { return nil }

        return try await appendObservation(
            [
                "entryId": id,
                "eventId": id,
                "kind": WatchObservationKind.effortRating,
                "loggedAt": utcIso(clock()),
                "rating": rating,
            ],
            sessionId: sessionId
        )
    }

    /// The first row stored for `sessionId` — the one that says how the
    /// session began, and so whether the wrist created it. Later rows written
    /// from a phone message can carry another source, so the first is the one
    /// that answers.
    private func creationRow(_ sessionId: String) -> WatchSessionRecord? {
        sessionRows
            .filter { $0.sessionId == sessionId }
            .min { $0.sequence < $1.sequence }
    }

    /// Whether the watch has held the observation `recordId` — still stored, or
    /// acknowledged and pruned since.
    private func knowsObservation(_ recordId: String) -> Bool {
        acknowledgedObservationIds.contains(recordId)
            || storedObservations.contains { $0.recordId == recordId }
    }

    /// The prune gate's extra step for a session the wrist created: its
    /// `session_end` has been acknowledged (D-129). A session the wrist joined
    /// owes no end, so nothing extra holds it.
    private func isEndAcknowledgedWhereOwed(_ sessionId: String) -> Bool {
        guard creationRow(sessionId)?.source == Self.wristSource else { return true }
        return acknowledgedObservationIds.contains(WatchSessionCapture.sessionEndId(sessionId))
    }

    // MARK: - Timers

    /// Starts `kind`, replacing any timer of that kind that was already running.
    @discardableResult
    public func startTimer(
        _ kind: String,
        plannedDurationMs: Int? = nil
    ) async throws -> WatchTimerRecord {
        try requireTimerKind(kind)
        let now = clock()
        return await appendTimer(
            WatchTimerRecord(
                recordId: newId(),
                sessionId: requireSession().sessionId,
                recordedAt: now,
                kind: kind,
                startedAt: now,
                plannedDurationMs: plannedDurationMs
            )
        )
    }

    /// Pauses the newest timer, or the newest one of `kind`.
    @discardableResult
    public func pauseTimer(kind: String? = nil) async -> WatchTimerRecord? {
        guard let timer = activeTimer(kind), timer.state == WatchTimerState.running
        else { return activeTimer(kind) }

        let now = clock()
        return await appendTimer(timerRowFrom(timer, recordedAt: now, pausedAt: now))
    }

    /// Resumes a paused timer, folding the finished pause into its bookkeeping.
    @discardableResult
    public func resumeTimer(kind: String? = nil) async -> WatchTimerRecord? {
        guard let timer = activeTimer(kind), timer.state == WatchTimerState.paused,
              let pausedAt = timer.pausedAt
        else { return activeTimer(kind) }

        let now = clock()
        return await appendTimer(
            timerRowFrom(
                timer,
                recordedAt: now,
                clearPause: true,
                accumulatedPauseMs: timer.accumulatedPauseMs
                    + Int(now.timeIntervalSince(pausedAt) * 1000)
            )
        )
    }

    /// Ends the newest timer, or the newest one of `kind`. A stopped timer keeps
    /// the time it had reached.
    @discardableResult
    public func stopTimer(kind: String? = nil) async -> WatchTimerRecord? {
        guard let timer = activeTimer(kind), timer.state != WatchTimerState.stopped
        else { return activeTimer(kind) }

        let now = clock()
        return await appendTimer(timerRowFrom(timer, recordedAt: now, stoppedAt: now))
    }

    /// Copies the timer's identity into a new row — timers advance by append too.
    ///
    /// `recordId` is supplied when the row comes from a message rather than from
    /// the wrist, so the id can be derived from the message and be replayable.
    private func timerRowFrom(
        _ timer: WatchTimerRecord,
        recordId: String? = nil,
        recordedAt: Date,
        pausedAt: Date? = nil,
        clearPause: Bool = false,
        accumulatedPauseMs: Int? = nil,
        stoppedAt: Date? = nil
    ) -> WatchTimerRecord {
        WatchTimerRecord(
            recordId: recordId ?? newId(),
            sessionId: timer.sessionId,
            recordedAt: recordedAt,
            kind: timer.kind,
            startedAt: timer.startedAt,
            pausedAt: clearPause ? nil : (pausedAt ?? timer.pausedAt),
            stoppedAt: stoppedAt ?? timer.stoppedAt,
            accumulatedPauseMs: accumulatedPauseMs ?? timer.accumulatedPauseMs,
            plannedDurationMs: timer.plannedDurationMs
        )
    }

    @discardableResult
    private func appendTimer(_ row: WatchTimerRecord) async -> WatchTimerRecord {
        let stored = await store.append(.timer(row))
        guard let timer = stored.timerRow else { return row }
        storedTimers.append(timer)
        emit(
            timerState(
                sessionId: timer.sessionId,
                timer: timer,
                sentAt: timer.recordedAt,
                messageId: messageId(for: timer.recordId)
            )
        )
        return timer
    }

    /// The most recently started timer of `kind`, or of any kind when `kind` is
    /// nil — which is the timer the user is looking at.
    private func activeTimer(_ kind: String?) -> WatchTimerRecord? {
        newestTimer(kind: kind)
    }

    private func newestTimer(kind: String?) -> WatchTimerRecord? {
        var newest: WatchTimerRecord?
        for timer in storedTimers {
            if timer.sessionId != current?.sessionId { continue }
            if let kind, timer.kind != kind { continue }
            if newest.map({ timer.sequence > $0.sequence }) ?? true { newest = timer }
        }
        return newest
    }

    /// Whether a phone's session-scoped frame applies at all (D-79): it must
    /// name the session the watch holds. A frame that names none, or names
    /// another one, is refused whole — nothing applied, nothing stored, nothing
    /// emitted.
    private func guardSession(_ envelope: [String: Any]) -> Bool {
        guard let held = current,
              let sessionId = envelope["sessionId"] as? String
        else { return false }
        return sessionId == held.sessionId
    }

    /// Whether the newest row of `kind` is one a phone message wrote — the rows
    /// whose id is derived from the message that named them (D-80).
    private func senderWroteTimer(_ kind: String) -> Bool {
        newestTimer(kind: kind)?.recordId.hasPrefix(Self.timerPrefix) ?? false
    }

    private func requireTimerKind(_ kind: String) throws {
        guard WatchTimerKind.all.contains(kind) else {
            throw WatchRecordError.malformed(
                "\"\(kind)\" is not one of \(WatchTimerKind.all.joined(separator: ", "))"
            )
        }
    }

    // MARK: - Confirmation and retention

    /// Records the phone's receipt of the observations behind `entryIds`.
    ///
    /// A receipt is an append of its own: the watch must remember what it may
    /// drop across a relaunch, without rewriting an observation.
    public func confirmObservations(_ entryIds: [String]) async -> [String] {
        let wanted = Set(entryIds)
        let acknowledged = storedObservations.filter {
            wanted.contains($0.entryId) && $0.confirmedAt == nil
        }
        guard !acknowledged.isEmpty else { return [] }

        let now = clock()
        _ = await store.append(
            .confirmation(
                WatchConfirmationRecord(
                    recordId: newId(),
                    // A receipt names the session it belongs to; a standalone
                    // nutrition quick-log has none, so the row's own id stands
                    // in.
                    sessionId: current?.sessionId ?? acknowledged[0].sessionId,
                    recordedAt: now,
                    observationIds: acknowledged.map(\.recordId)
                )
            )
        )

        let acknowledgedIds = Set(acknowledged.map(\.recordId))
        acknowledgedObservationIds.formUnion(acknowledgedIds)
        storedObservations = storedObservations.map { observation in
            acknowledgedIds.contains(observation.recordId)
                ? observation.withConfirmation(now)
                : observation
        }

        return acknowledged.map(\.recordId)
    }

    /// Drops confirmed observations. Unconfirmed ones stay until the phone
    /// acknowledges them.
    public func pruneConfirmed() async -> [String] {
        let pruned = await store.pruneConfirmed()
        let dropped = Set(pruned)
        storedObservations.removeAll { dropped.contains($0.recordId) }
        // D-52: a pruned row takes its projection lens with it. A correction or
        // deletion marker left behind would override or hide the fresh row when
        // the same id is re-carried.
        for recordId in dropped {
            entryCorrections.removeValue(forKey: recordId)
            replacedEntryIds.remove(recordId)
            deletedEntryIds.remove(recordId)
        }
        return pruned
    }

    // MARK: - Emission

    private func observationsUp(
        sessionId: String,
        record: WatchObservationRecord,
        sentAt: Date,
        messageId: String
    ) -> [String: Any] {
        [
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": messageId,
            "sessionId": sessionId,
            "type": "observations_up",
            "origin": "watch",
            "sentAt": utcIso(sentAt),
            "payload": ["events": [record.payload]],
        ]
    }

    private func timerState(
        sessionId: String,
        timer: WatchTimerRecord,
        sentAt: Date,
        messageId: String
    ) -> [String: Any] {
        [
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": messageId,
            "sessionId": sessionId,
            "type": "timer_state",
            "origin": "watch",
            "sentAt": utcIso(sentAt),
            "payload": ["timers": [timer.kind: timer.toTimerJson()]],
        ]
    }

    /// The session's own state change, as the phone's mirror reads it. The index
    /// travels only with `exercise_advanced` — the schema allows it nowhere else.
    private func lifecycle(_ row: WatchSessionRecord, state: String) -> [String: Any] {
        var payload: [String: Any] = [
            "state": state,
            "at": utcIso(row.recordedAt),
        ]
        if state == WatchLifecycleState.exerciseAdvanced {
            payload["exerciseIndex"] = row.currentExerciseIndex
        }

        return [
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": messageId(for: row.recordId),
            "sessionId": row.sessionId,
            "type": "session_lifecycle",
            "origin": "watch",
            "sentAt": utcIso(row.recordedAt),
            "payload": payload,
        ]
    }

    /// The delivery key is derived from the row, not minted per attempt: a
    /// replay after a crash re-sends the same message for the same record.
    private func messageId(for recordId: String) -> String { "msg-\(recordId)" }

    private func emit(_ envelope: [String: Any]) {
        onEmit?(envelope)
    }

    /// Refuses to hand out anything the protocol would reject — the watch must
    /// not be the source of a message the phone cannot read.
    private func requireConformant(_ envelope: [String: Any]) throws {
        guard let validator else { return }
        let rejections = validator.validateEnvelope(envelope)
        guard rejections.isEmpty else {
            throw WatchEmissionRejected(
                message: "refusing to emit a non-conformant message: "
                    + "\(rejections[0].description)",
                rejections: rejections
            )
        }
    }

    /// Refuses to apply anything this watch cannot read — version first, then
    /// conformance. A message from a peer speaking another version is rejected
    /// without being interpreted (PROTOCOL.md, "Versioning policy").
    private func requireConformingIncoming(_ envelope: [String: Any]) throws {
        let rejections = SyncProtocolValidator.incomingRejections(validator, envelope)
        guard rejections.isEmpty else {
            throw WatchEmissionRejected(
                message: "refusing to apply a message this build cannot read: "
                    + "\(rejections[0].description)",
                rejections: rejections
            )
        }
    }

    private func requireSession() -> WatchSessionRecord {
        guard let current else {
            preconditionFailure(
                "no session: create one, or restore the in-progress session first"
            )
        }
        return current
    }
}

private extension StoredWatchRecord {
    var sessionRow: WatchSessionRecord? {
        if case .session(let row) = self { return row }
        return nil
    }

    var observationRow: WatchObservationRecord? {
        if case .observation(let row) = self { return row }
        return nil
    }

    var timerRow: WatchTimerRecord? {
        if case .timer(let row) = self { return row }
        return nil
    }

    var sensorSampleRow: WatchSensorSampleRecord? {
        if case .sensorSample(let row) = self { return row }
        return nil
    }
}
