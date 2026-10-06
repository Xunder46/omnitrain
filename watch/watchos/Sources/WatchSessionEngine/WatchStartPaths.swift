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

    /// Said only when the wrist has *observed* the phone out of reach (D-8),
    /// never on a cold start, which has asked nothing.
    ///
    /// Deliberately not a contract value like the two above: the Wear OS client
    /// reads the same contract file and has no transport, so it has no
    /// reachability to say this about. It moves into
    /// `watch/contract/watch_start_paths_contract.json` if that client ever
    /// ships one.
    public static let unreachableLabel = "Phone not reachable"
}

/// What the wrist knows about the phone's radio: nothing yet, or one of the two
/// answers it has observed (D-8).
///
/// The distinction is the point of the type. "The phone is unreachable" and
/// "nobody has asked the radio yet" are the same `false` to a flag that starts
/// false, and a sentence drawn from the second would lie on every launch.
public enum WatchPhoneReachability: Equatable {
    /// No answer has arrived yet. A cold start is this until the radio's
    /// activation reports where it stands.
    case unknown

    /// The radio reported the phone reachable.
    case reachable

    /// The radio reported the phone unreachable.
    case unreachable

    /// The state the radio's answer means. The platform has no "unknown" — a
    /// `Bool` can only be an observation — so the third state belongs to the
    /// host, before the first answer arrives.
    public static func observed(reachable: Bool) -> WatchPhoneReachability {
        reachable ? .reachable : .unreachable
    }
}

/// What the start surface says about the phone (D-8, D-9), as a value rather
/// than a view so the rule is testable on the desktop toolchain.
public struct WatchPhoneStatus {
    public let reachability: WatchPhoneReachability

    public init(reachability: WatchPhoneReachability) {
        self.reachability = reachability
    }

    /// The sentence about the phone, or nil when there is nothing honest to say.
    /// Only an observed unreachable phone earns one.
    public var sentence: String? {
        switch reachability {
        case .unknown, .reachable:
            return nil
        case .unreachable:
            return WatchStartSurfaceCopy.unreachableLabel
        }
    }

    /// Whether the surface offers the user the sync action.
    ///
    /// Always, while a transport exists: a disabled button explains nothing, and
    /// a phone out of reach now may be back in reach when the user taps (D-9).
    /// A watch with no transport passes no action at all, so no button appears.
    public var offersSync: Bool { true }
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

/// One row of the exercise picker: an exercise the wrist may log, and whether
/// the live session already holds it.
///
/// The two cases exist because the same exercise can legitimately sit on the
/// ladder twice — a superset benches in two slots — so a row keyed by exercise
/// id alone would collapse the pair and leave the second slot unreachable. A row
/// carries its own `id`: the slot id when the session holds it, the exercise id
/// otherwise.
public enum WatchExercisePickerRow: Equatable {
    /// Already on the session's ladder, in the slot named.
    case inSession(slotId: String, exercise: WatchCatalogExercise)

    /// Not on the ladder yet; picking it appends a slot.
    case available(WatchCatalogExercise)

    /// What the picker keys rows by.
    public var id: String {
        switch self {
        case .inSession(let slotId, _): return slotId
        case .available(let exercise): return exercise.exerciseId
        }
    }

    public var name: String {
        switch self {
        case .inSession(_, let exercise), .available(let exercise): return exercise.name
        }
    }

    public var exerciseId: String {
        switch self {
        case .inSession(_, let exercise), .available(let exercise): return exercise.exerciseId
        }
    }

    /// Whether picking this row moves the session rather than growing it.
    public var isInSession: Bool {
        switch self {
        case .inSession: return true
        case .available: return false
        }
    }
}

/// The picker's rows: the session's own ladder first and in its order, then
/// every exercise the wrist could add, minus the ones the ladder already shows.
///
/// An exercise already on the ladder appears once, as its in-session row, so
/// picking it moves the user to it instead of adding a duplicate — while a
/// second slot for the same exercise still gets a row of its own.
public func derivePickerRows(
    sessionExercises: [[String: Any]],
    fallback: [WatchCatalogExercise]
) -> [WatchExercisePickerRow] {
    var rows: [WatchExercisePickerRow] = []
    var onLadder = Set<String>()

    for slot in sessionExercises {
        guard let exercise = WatchCatalogExercise(slot: slot) else { continue }
        rows.append(.inSession(
            slotId: (slot["sessionExerciseId"] as? String) ?? exercise.slotId,
            exercise: exercise
        ))
        onLadder.insert(exercise.exerciseId)
    }

    for exercise in fallback where !onLadder.contains(exercise.exerciseId) {
        rows.append(.available(exercise))
    }

    return rows
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

    /// The picker's rows for the live session: what the user is on, then what
    /// they could add. Derived on every read rather than cached, so a push that
    /// arrived while the picker was open is already in the list the user sees.
    public var pickerRows: [WatchExercisePickerRow] {
        derivePickerRows(
            sessionExercises: engine.session?.exercises ?? [],
            fallback: fallbackExercises
        )
    }

    /// Picking a row: a slot the session already holds moves the user to it, and
    /// an exercise it does not appends one. Nil when the slot is gone by the
    /// time the tap lands, which changes nothing.
    @discardableResult
    public func selectExercise(_ row: WatchExercisePickerRow) async -> WatchSessionRecord? {
        switch row {
        case .inSession(let slotId, _):
            return await engine.selectExercise(slotId: slotId)
        case .available(let exercise):
            return await addExerciseToSession(exercise)
        }
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
