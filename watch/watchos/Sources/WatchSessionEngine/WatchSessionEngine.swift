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

    private var sessionRows: [WatchSessionRecord] = []
    private var storedObservations: [WatchObservationRecord] = []
    private var storedTimers: [WatchTimerRecord] = []
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

        current = contents.sessions.max { $0.sequence < $1.sequence }
    }

    // MARK: - Session state

    public var session: WatchSessionRecord? { current }

    public var currentExercise: [String: Any]? { current?.currentExercise }

    /// The current session's observations, in the order they were logged.
    public var observations: [WatchObservationRecord] {
        storedObservations.filter { $0.sessionId == current?.sessionId }
    }

    /// The newest row for `kind`, which is the timer that applies.
    public func timerFor(_ kind: String) -> WatchTimerRecord? {
        newestTimer(kind: kind)
    }

    // MARK: - Lifecycle

    /// Starts a session that needs no phone to run. `exercises` are the
    /// protocol's `sessionExercise` slots, persisted with the session so a
    /// relaunch knows what the position means.
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
        current = stored.sessionRow ?? row
        return current ?? row
    }

    /// Moves to the next exercise. The last exercise is the end of the ladder.
    @discardableResult
    public func advanceExercise() async -> WatchSessionRecord {
        let session = requireSession()
        let lastIndex = session.exercises.isEmpty ? 0 : session.exercises.count - 1
        return await transitionTo(
            currentExerciseIndex: min(session.currentExerciseIndex + 1, lastIndex)
        )
    }

    /// Closes the session as done.
    @discardableResult
    public func finishSession() async -> WatchSessionRecord {
        await transitionTo(status: WatchSessionStatus.completed)
    }

    /// Closes the session as given up on. Entries already logged stay logged.
    @discardableResult
    public func abandonSession() async -> WatchSessionRecord {
        await transitionTo(status: WatchSessionStatus.abandoned)
    }

    /// A state change appends rather than updates, which is what both keeps the
    /// store append-only and makes the position survive a kill.
    private func transitionTo(
        status: String? = nil,
        currentExerciseIndex: Int? = nil
    ) async -> WatchSessionRecord {
        let session = requireSession()
        let row = WatchSessionRecord(
            recordId: newId(),
            sessionId: session.sessionId,
            recordedAt: clock(),
            startedAt: session.startedAt,
            modality: session.modality,
            source: session.source,
            status: status ?? session.status,
            currentExerciseIndex: currentExerciseIndex ?? session.currentExerciseIndex,
            exercises: session.exercises
        )

        let stored = await store.append(.session(row))
        current = stored.sessionRow ?? row
        return current ?? row
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
        let eventId = event["eventId"] as? String
        let recordId = eventId.flatMap { $0.isEmpty ? nil : $0 } ?? newId()
        let now = clock()

        let record = WatchObservationRecord(
            recordId: recordId,
            sessionId: session.sessionId,
            recordedAt: now,
            kind: event["kind"] as? String ?? "",
            payload: event
        )

        let envelope = observationsUp(
            sessionId: session.sessionId,
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

    /// The messages the phone still owes a receipt for, rebuilt from storage.
    /// Emission is a projection of the stored rows, so replaying after a kill
    /// sends the same events with the same identifiers.
    public func pendingObservations() -> [[String: Any]] {
        guard let session = current else { return [] }
        return observations
            .filter { $0.confirmedAt == nil }
            .map { observation in
                observationsUp(
                    sessionId: session.sessionId,
                    record: observation,
                    sentAt: observation.recordedAt,
                    messageId: messageId(for: observation.recordId)
                )
            }
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
    private func timerRowFrom(
        _ timer: WatchTimerRecord,
        recordedAt: Date,
        pausedAt: Date? = nil,
        clearPause: Bool = false,
        accumulatedPauseMs: Int? = nil,
        stoppedAt: Date? = nil
    ) -> WatchTimerRecord {
        WatchTimerRecord(
            recordId: newId(),
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
        guard let session = current else { return [] }
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
                    sessionId: session.sessionId,
                    recordedAt: now,
                    observationIds: acknowledged.map(\.recordId)
                )
            )
        )

        let acknowledgedIds = Set(acknowledged.map(\.recordId))
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
}
