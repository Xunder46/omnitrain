//
//  WatchStartPaths.swift
//  WatchSessionEngine
//
//  The two ways a session starts on the wrist, and everything that happens to
//  the exercise ladder afterwards. Mirrors
//  `lib/watch/start/watch_session_start_paths.dart` call for call.
//
//  Plan: `docs/plans/2026-07-13-08-b-watch-session-start-paths-plan.md`,
//  scenarios S-001 to S-005.
//
//  The full catalog never reaches the watch (a 23-sport catalog on a 40mm screen
//  is misery, and it duplicates data for no benefit). What the wrist holds is
//  reference data the phone sent down: the user's routines, and a fallback
//  exercise list that covers every one of them — which is why both paths work
//  with the phone switched off, and why starting a session is a read of local
//  storage rather than a request to the phone.
//
//  The phone is still the owner of session structure (PROTOCOL.md, authority
//  rule 2). A pushed exercise lands through `WatchSessionEngine.applyExercisePush`;
//  nothing here originates a routine or edits one.
//

import Foundation

/// The words the start surface says, in one place so the views render them and
/// the suite can hold them to the shared contract.
///
/// Plan: `docs/plans/2026-09-21-13-watch-integration-shipping.md`,
/// D-7 and S-010. They live here rather than on the SwiftUI view because the
/// view is compiled only into a watch target, while the sentence itself is a
/// product requirement on every client — and the Flutter client reads the same
/// two strings from `watch/contract/watch_start_paths_contract.json`.
public enum WatchStartSurfaceCopy {
    /// Said plainly because there is nothing to discover: nothing arrives on the
    /// wrist unless its user asks, and a user who does not know that reads an
    /// unchanged routine list as a broken phone.
    public static let noAutoSyncLabel = "No automatic sync"

    /// The user's explicit action — the only thing that asks the phone for
    /// anything.
    public static let syncLabel = "Sync routines"
}

/// The exercises the wrist may offer without reaching the phone (S-003).
///
/// Three sources, in this order: what the user used on the wrist most recently,
/// the phone's own fallback list, and every exercise a synced routine names.
/// Deduplicated by exercise id keeping the first mention, so an exercise's
/// identity comes from the earliest source that knew it and the list the user
/// reads is stable between syncs.
///
/// Routine coverage is not left to the phone: the protocol's validator rejects a
/// `routines_down` whose fallback list misses one, and this derivation adds them
/// anyway — a routine the watch holds must always be loggable offline.
public func deriveFallbackExercises(
    recents: [WatchCatalogExercise],
    syncedFallback: [WatchCatalogExercise],
    routines: [WatchRoutine]
) -> [WatchCatalogExercise] {
    var seen = Set<String>()
    var offered: [WatchCatalogExercise] = []

    for exercise in recents + syncedFallback + routines.flatMap(\.efforts).map(\.catalogExercise) {
        if seen.insert(exercise.exerciseId).inserted { offered.append(exercise) }
    }

    return offered
}

/// What happened to a reference-data message — `routines_down` or `foods_down`.
public struct WatchCatalogSyncResult {
    /// True when this message became the catalog the watch reads. A conformant
    /// message older than the cached one is understood and dropped, so it is
    /// false without being a rejection.
    public let applied: Bool

    /// The receiver's verdict on the message. Empty for anything the watch
    /// understood, including a drop.
    public let rejections: [SyncProtocolRejection]

    public init(applied: Bool, rejections: [SyncProtocolRejection]) {
        self.applied = applied
        self.rejections = rejections
    }
}

public enum WatchStartPathError: Error, CustomStringConvertible {
    case unknownRoutine(String)

    public var description: String {
        switch self {
        case .unknownRoutine(let routineId):
            return "no routine \"\(routineId)\": the phone has not synced one by that id"
        }
    }
}

public final class WatchSessionStartPaths {
    private let engine: WatchSessionEngine
    private let store: WatchSessionStore
    private let validator: SyncProtocolValidator?
    private let clock: () -> Date
    private let newId: () -> String

    private var catalog: WatchRoutineCatalogRecord?
    private var storedRoutines: [WatchRoutine] = []
    private var syncedFallback: [WatchCatalogExercise] = []
    private var recents: [WatchCatalogExercise] = []

    /// Whether the phone can be reached right now — what the wrist's
    /// search-on-phone affordance is shown on. The sync orchestrator is what
    /// knows, and it writes the flag here so the surfaces have one place to read.
    public var phoneReachable: Bool = false

    public init(
        engine: WatchSessionEngine,
        store: WatchSessionStore,
        validator: SyncProtocolValidator? = nil,
        clock: @escaping () -> Date = { Date() },
        idFactory: @escaping () -> String = { UUID().uuidString }
    ) {
        self.engine = engine
        self.store = store
        self.validator = validator
        self.clock = clock
        self.newId = idFactory
    }

    // MARK: - What the wrist holds

    /// The user's routines, as last synced. Empty until the phone has sent them.
    public var routines: [WatchRoutine] { storedRoutines }

    /// When the phone generated the catalog the watch is holding, or nil when no
    /// phone has sent one yet.
    public var syncedAt: Date? { catalog?.generatedAt }

    /// Everything the wrist may offer offline, recents first (S-003).
    public var fallbackExercises: [WatchCatalogExercise] {
        deriveFallbackExercises(
            recents: recents,
            syncedFallback: syncedFallback,
            routines: storedRoutines
        )
    }

    // MARK: - Storage

    /// Reads the catalog and the watch's own usage back out of storage. Call on
    /// launch, and after any suspension: what comes back is what the watch knew
    /// at kill time.
    public func restore() async {
        let contents = await store.readAll()

        catalog = contents.routineCatalogs.max { $0.sequence < $1.sequence }

        if let catalog, let synced = try? WatchRoutinesDown(catalog: catalog) {
            storedRoutines = synced.routines
            syncedFallback = synced.fallbackExercises
        } else {
            storedRoutines = []
            syncedFallback = []
        }

        recents = Self.recentlyUsed(contents.sessions)
    }

    /// Applies a `routines_down` message: the routines, and the fallback list
    /// that covers them.
    ///
    /// The message is stored whole and the newest one wins, so the list the user
    /// sees updates on the next background sync with no action from them (S-004).
    public func applyRoutinesDown(_ envelope: [String: Any]) async -> WatchCatalogSyncResult {
        let rejections = SyncProtocolValidator.incomingRejections(validator, envelope)
        if !rejections.isEmpty {
            return WatchCatalogSyncResult(applied: false, rejections: rejections)
        }

        guard let sent = try? WatchRoutinesDown(envelope: envelope) else {
            return WatchCatalogSyncResult(applied: false, rejections: [])
        }

        if let catalog, sent.generatedAt < catalog.generatedAt {
            // Understood and dropped: an older view of the routines is not a
            // newer truth.
            return WatchCatalogSyncResult(applied: false, rejections: [])
        }

        let stored = await store.append(
            .routineCatalog(sent.toRecord(recordId: newId(), recordedAt: clock()))
        )
        catalog = stored.routineCatalogRow
        storedRoutines = sent.routines
        syncedFallback = sent.fallbackExercises

        return WatchCatalogSyncResult(applied: true, rejections: [])
    }

    // MARK: - Path 1 — from a routine

    /// Starts the routine `routineId` names, exactly as its template dictates.
    ///
    /// The routine's efforts become the session's slots — one per effort, so a
    /// routine that names the same exercise twice gets two of them. Each slot
    /// carries the capabilities the phone resolved the exercise from, which is
    /// what makes the logging surface the right one without asking the phone.
    ///
    /// The session carries no modality: `routines_down` has no field for one, so
    /// the wrist resolves each exercise from its capabilities instead of guessing
    /// from the routine. See the plan's open items.
    @discardableResult
    public func startFromRoutine(_ routineId: String) async throws -> WatchSessionRecord {
        guard let routine = storedRoutines.first(where: { $0.routineId == routineId }) else {
            throw WatchStartPathError.unknownRoutine(routineId)
        }
        return await engine.createSession(modality: nil, exercises: routine.slots)
    }

    // MARK: - Path 2 — free workout

    /// Starts an empty session. Exercises are added one at a time, from the
    /// fallback list or by a push from the phone.
    @discardableResult
    public func startFreeWorkout() async -> WatchSessionRecord {
        await engine.createSession(modality: nil)
    }

    /// Adds `exercise` to the live session and moves the user to it.
    ///
    /// Choosing an exercise *is* a request to do it, so the session follows the
    /// pick — unlike a push from the phone, which must not move the user
    /// mid-set.
    @discardableResult
    public func addExerciseToSession(
        _ exercise: WatchCatalogExercise,
        atIndex: Int? = nil
    ) async -> WatchSessionRecord {
        await engine.insertExercise(
            exercise.toSlot(sessionExerciseId: availableSlotId(for: exercise)),
            atIndex: atIndex,
            moveTo: true
        )
    }

    // MARK: - Derived state

    /// A slot id the session is not using yet. The same exercise may
    /// legitimately fill two slots — that is what a superset is — so a second
    /// pick gets its own id rather than being swallowed as a duplicate.
    private func availableSlotId(for exercise: WatchCatalogExercise) -> String {
        let taken = Set((engine.session?.exercises ?? []).compactMap { $0["sessionExerciseId"] as? String })

        let base = exercise.slotId
        if !taken.contains(base) { return base }
        var suffix = 2
        while taken.contains("\(base)-\(suffix)") { suffix += 1 }
        return "\(base)-\(suffix)"
    }

    /// The exercises the wrist used most recently, newest session first.
    ///
    /// Read out of the sessions the watch already keeps rather than written to a
    /// list of its own: a relaunch cannot lose what storage already held.
    private static func recentlyUsed(_ rows: [WatchSessionRecord]) -> [WatchCatalogExercise] {
        var newestPerSession: [String: WatchSessionRecord] = [:]
        for row in rows {
            if let known = newestPerSession[row.sessionId], row.sequence <= known.sequence {
                continue
            }
            newestPerSession[row.sessionId] = row
        }

        var seen = Set<String>()
        var recents: [WatchCatalogExercise] = []
        for session in newestPerSession.values.sorted(by: { $0.sequence > $1.sequence }) {
            for slot in session.exercises {
                guard let exercise = WatchCatalogExercise(slot: slot) else { continue }
                if seen.insert(exercise.exerciseId).inserted { recents.append(exercise) }
            }
        }
        return recents
    }
}

extension StoredWatchRecord {
    var routineCatalogRow: WatchRoutineCatalogRecord? {
        if case .routineCatalog(let row) = self { return row }
        return nil
    }

    var foodCatalogRow: WatchFoodCatalogRecord? {
        if case .foodCatalog(let row) = self { return row }
        return nil
    }
}
