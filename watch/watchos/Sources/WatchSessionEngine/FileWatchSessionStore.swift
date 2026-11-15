//
//  FileWatchSessionStore.swift
//  WatchSessionEngine
//
//  The durable twin of `InMemoryWatchSessionStore`: one append-only JSON-lines
//  file that outlives the process that wrote it.
//
//  Every row the engine stores is appended as its own line, so a kill during a
//  write can only ever tear the last line — the rows before it are already on
//  disk and are read back untouched. The first line is a format marker; a file
//  whose marker names a version this binary does not know is left exactly as it
//  is, because a newer watchOS build may own it (D-45, D-46, D-47).
//
//  Reads are tolerant by design: a line that does not parse is skipped rather
//  than failing the load, and a missing marker means a store that has never been
//  written, not a corrupt one.
//

import Foundation

public final class FileWatchSessionStore: WatchSessionStore {
    private static let markerFormat = "omnitrain-watch-store"
    private static let markerVersion = 1
    private static let fileName = "watch-session.jsonl"
    /// A terminal session's readings live in their own file beside the main one
    /// (D-17302). The name is pinned: the tests and the load-time migration both
    /// read the directory.
    private static let sampleFilePrefix = "watch-samples-"
    private static let sampleFileSuffix = ".jsonl"

    private let directory: URL
    private let fileURL: URL
    private let lock = NSLock()

    /// The file's rows, loaded once on first use and kept in step with every
    /// append, so `nextSequence()` never re-reads the file.
    private var rows: [StoredWatchRecord]?
    /// The key of every row in `rows`, by record type (D-15604), so the
    /// duplicate check in `appendLocked` is a lookup instead of a scan of the
    /// whole file. Exact: `loadRows` fills it and `adopt` rebuilds it after a
    /// prune, so a store that dropped a workout's readings stops holding their
    /// keys too. A hit is still confirmed against the rows themselves.
    private var heldIds: Set<String> = []

    /// Takes a compacted file's survivors as the rows, and rebuilds the index
    /// from them. A prune already paid a full pass to rewrite the file.
    private func adopt(_ survivors: [StoredWatchRecord]) {
        rows = survivors
        heldIds = Set(survivors.map(Self.rowKey))
    }

    /// One row per record type and id — the key `heldIds` is indexed by, matching
    /// the duplicate check `appendLocked` makes.
    private static func rowKey(_ record: StoredWatchRecord) -> String {
        "\(record.recordType)\u{1F}\(record.recordId)"
    }

    /// Whether the file still needs its format marker — true for a store that
    /// has never been written and for a file that has lost its marker.
    private var needsMarker = false

    /// Whether the file's marker names a version this binary does not know. Such
    /// a file is read as empty and never written to.
    private var unsupported = false

    /// Whether the file's last line has no newline after it — the shape a kill
    /// mid-write leaves. The next append starts on a fresh line, so the torn
    /// fragment can never swallow the row that follows it.
    private var tornTail = false

    /// Whether the file holds any bytes. Distinct from "holds any rows": a file
    /// of junk needs the marker put above it, not appended after it.
    private var fileHasContent = false

    /// The highest sequence handed out so far: the file's highest at load, then
    /// advanced by every accepted append — including one whose bytes never
    /// landed, so a sequence is never handed out twice.
    private var lastSequence = 0

    /// Every terminal session's side file, by session id — existence only, never
    /// its rows. The settle gate asks whether a session has anything stored, and
    /// a listing answers that without decoding a reading (D-17308).
    private var sampleSideFiles: [String: URL] = [:]

    /// The main file's lines this store has decoded, marker included
    /// (`parseLine`'s successes), for the test that bounds a launch by a count
    /// rather than by wall time (S-17301). A side file's rows are not a launch
    /// decode and are not counted; no production behaviour reads it.
    private var rowsDecoded = 0

    public init(directory: URL) {
        self.directory = directory
        self.fileURL = directory.appendingPathComponent(Self.fileName, isDirectory: false)
    }

    // MARK: - WatchSessionStore

    public func append(_ record: StoredWatchRecord) async -> StoredWatchRecord {
        locked { appendLocked(record) }
    }

    public func readAll() async -> WatchStoreContents {
        locked { readAllLocked() }
    }

    public func readLaunch() async -> WatchStoreContents {
        locked { readLaunchLocked() }
    }

    public func pruneConfirmed() async -> [String] {
        locked { pruneConfirmedLocked() }
    }

    public func pruneSensorSamples(_ sessionIds: [String]) async -> [String] {
        locked { pruneSensorSamplesLocked(sessionIds) }
    }

    public func archiveSensorSamples(_ sessionId: String) async -> [String] {
        locked { archiveSensorSamplesLocked(sessionId) }
    }

    public func pruneExerciseBatches(keepingVersion: String) async -> [String] {
        locked { pruneExerciseBatchesLocked(keepingVersion) }
    }

    public func pruneBests(keepingRecordId: String) async -> [String] {
        locked { pruneBestsLocked(keepingRecordId) }
    }

    public func pruneWater(keepingRecordId: String) async -> [String] {
        locked { pruneWaterLocked(keepingRecordId) }
    }

    public func pruneWaterTaps(loggedBefore cutoff: Date) async -> [String] {
        locked { pruneWaterTapsLocked(cutoff) }
    }

    // MARK: - The store's operations

    private func appendLocked(_ record: StoredWatchRecord) -> StoredWatchRecord {
        // No local copy of the rows may live past this check: a second reference
        // to the array's buffer makes the `rows?.append` below copy the whole
        // file's rows on every append (copy on write), which is a cost that
        // grows with the store (D-15604).
        _ = loadRows()
        guard !unsupported else { return record }

        if let existing = heldRow(for: record) { return existing }

        let stored = record.withSequence(nextSequence())
        guard let line = rowLine(stored) else { return record }

        // A row the disk refused is not durable: it stays out of the cache so
        // the process does not read back a row the next launch cannot see. The
        // caller still gets it, with the sequence it was given, because the
        // engine keeps the newest row and one sequence 0 would lose that tie.
        guard prepareFile(), appendLine(line) else { return stored }
        rows?.append(stored)
        heldIds.insert(Self.rowKey(stored))
        fileHasContent = true
        return stored
    }

    private func readAllLocked() -> WatchStoreContents {
        let contents = contentsLocked(from: loadRows())
        let archived = sampleSideFiles
            .sorted { $0.key < $1.key }
            .flatMap { decodeSampleSideFile($0.value) }
        guard !archived.isEmpty else { return contents }
        return contents.withSensorSamples(
            (contents.sensorSamples + archived).sorted { $0.sequence < $1.sequence }
        )
    }

    /// The launch set: the main file's rows minus the readings of a terminal
    /// session (D-17301). The side files are never opened — that is what they
    /// are for.
    private func readLaunchLocked() -> WatchStoreContents {
        launchReadingsOnly(contentsLocked(from: loadRows()))
    }

    private func contentsLocked(from loaded: [StoredWatchRecord]) -> WatchStoreContents {
        guard !unsupported else { return WatchStoreContents() }

        var sessions: [WatchSessionRecord] = []
        var observations: [WatchObservationRecord] = []
        var timers: [WatchTimerRecord] = []
        var confirmations: [WatchConfirmationRecord] = []
        var sensorSamples: [WatchSensorSampleRecord] = []
        var routineCatalogs: [WatchRoutineCatalogRecord] = []
        var plannedCatalogs: [WatchPlannedCatalogRecord] = []
        var foodCatalogs: [WatchFoodCatalogRecord] = []
        var preferences: [WatchPreferencesRecord] = []
        var ratingPrompts: [WatchRatingPromptRecord] = []
        var exerciseBatches: [WatchExerciseBatchRecord] = []
        var bests: [WatchBestsRecord] = []
        var water: [WatchWaterRecord] = []

        for row in loaded {
            switch row {
            case .session(let value): sessions.append(value)
            case .observation(let value): observations.append(value)
            case .timer(let value): timers.append(value)
            case .sensorSample(let value): sensorSamples.append(value)
            case .confirmation(let value): confirmations.append(value)
            case .routineCatalog(let value): routineCatalogs.append(value)
            case .plannedCatalog(let value): plannedCatalogs.append(value)
            case .foodCatalog(let value): foodCatalogs.append(value)
            case .preferences(let value): preferences.append(value)
            case .ratingPrompt(let value): ratingPrompts.append(value)
            case .exerciseBatch(let value): exerciseBatches.append(value)
            case .bests(let value): bests.append(value)
            case .water(let value): water.append(value)
            }
        }

        return WatchStoreContents(
            sessions: sessions,
            observations: applyConfirmations(observations, confirmations),
            timers: timers,
            confirmations: confirmations,
            sensorSamples: sensorSamples,
            routineCatalogs: routineCatalogs,
            plannedCatalogs: plannedCatalogs,
            foodCatalogs: foodCatalogs,
            preferences: preferences,
            ratingPrompts: ratingPrompts,
            exerciseBatches: exerciseBatches,
            bests: bests,
            water: water
        )
    }

    private func pruneConfirmedLocked() -> [String] {
        let loaded = loadRows()
        guard !unsupported else { return [] }

        let confirmations = loaded.compactMap { row -> WatchConfirmationRecord? in
            guard case .confirmation(let value) = row else { return nil }
            return value
        }
        let observations = loaded.compactMap { row -> WatchObservationRecord? in
            guard case .observation(let value) = row else { return nil }
            return value
        }
        let confirmed = applyConfirmations(observations, confirmations)
            .filter { $0.confirmedAt != nil }
            .map(\.recordId)
        let dropped = Set(confirmed)
        let survivors = loaded.filter { row in
            guard case .observation(let value) = row else { return true }
            return !dropped.contains(value.recordId)
        }

        // A prune that finds nothing is not a write (D-3821, D-15603): the launch
        // prunes run on every launch, and a rewrite per launch costs a full copy
        // of a file that can be tens of megabytes.
        guard !confirmed.isEmpty else { return [] }
        guard compact(survivors) else { return [] }
        adopt(survivors)
        return confirmed
    }

    private func pruneSensorSamplesLocked(_ sessionIds: [String]) -> [String] {
        let named = Set(sessionIds)
        guard !named.isEmpty else { return [] }

        let loaded = loadRows()
        guard !unsupported else { return [] }

        let inline = loaded.compactMap { row -> String? in
            guard case .sensorSample(let value) = row, named.contains(value.sessionId) else {
                return nil
            }
            return value.recordId
        }
        // A moved session's readings are in its side file, and the in-memory log
        // still holds them: their ids are read from there, so the release reaches
        // both sides of the boundary (D-17307).
        let archivedIds = named
            .compactMap { sampleSideFiles[$0] }
            .flatMap { decodeSampleSideFile($0).map(\.recordId) }
        let archived = Set(named.filter { sampleSideFiles[$0] != nil })
        guard !inline.isEmpty || !archived.isEmpty else { return [] }

        if !inline.isEmpty {
            let survivors = loaded.filter { row in
                guard case .sensorSample(let value) = row else { return true }
                return !named.contains(value.sessionId)
            }
            // A prune that drops nothing is not a write (D-3821, D-15603), and a
            // prune that cannot be written drops nothing at all: the side files
            // stay with the rows the file still carries.
            guard compact(survivors) else { return [] }
            adopt(survivors)
        }

        for sessionId in archived {
            guard let url = sampleSideFiles[sessionId] else { continue }
            try? FileManager.default.removeItem(at: url)
            sampleSideFiles[sessionId] = nil
        }
        return inline + archivedIds
    }

    // MARK: - The side files

    private func archiveSensorSamplesLocked(_ sessionId: String) -> [String] {
        let loaded = loadRows()
        guard !unsupported else { return [] }
        return moveInlineSamples(of: [sessionId], in: loaded) ?? []
    }

    /// The load-time move (D-17304): every terminal session's inline readings go
    /// to their side file and out of the main file. A load with nothing to move
    /// writes nothing (D-15603).
    private func migrateInlineSamples(_ loaded: [StoredWatchRecord]) {
        let settled = settledSensorSessionIds(in: loaded)
        guard !settled.isEmpty else { return }
        _ = moveInlineSamples(of: settled, in: loaded)
    }

    /// Writes `sessionIds`' inline readings to their side files, then rewrites
    /// the main file without them (D-17302, D-17303). Reports the moved record
    /// ids, or nil when nothing moved or a write failed.
    ///
    /// The order is the whole of the kill-safety: the side file lands first, so a
    /// kill between the two writes leaves both copies on disk and no reading
    /// lost, and the next load rewrites the side file wholesale from the inline
    /// rows and compacts again.
    private func moveInlineSamples(
        of sessionIds: Set<String>,
        in loaded: [StoredWatchRecord]
    ) -> [String]? {
        var bySession: [String: [WatchSensorSampleRecord]] = [:]
        for row in loaded {
            guard case .sensorSample(let value) = row, sessionIds.contains(value.sessionId) else {
                continue
            }
            bySession[value.sessionId, default: []].append(value)
        }
        guard !bySession.isEmpty else { return nil }

        var moved: [String] = []
        for (sessionId, samples) in bySession.sorted(by: { $0.key < $1.key }) {
            guard saveSampleSideFile(sessionId, samples) else { return nil }
            moved.append(contentsOf: samples.map(\.recordId))
        }

        let survivors = loaded.filter { row in
            guard case .sensorSample(let value) = row else { return true }
            return !sessionIds.contains(value.sessionId)
        }
        // A compaction that fails leaves the main file as it was: the rows are
        // still readable, the side file holds a copy, and the next load heals it.
        guard compact(survivors) else { return nil }
        adopt(survivors)
        return moved
    }

    /// Writes `samples` wholesale to the session's side file, replacing any copy
    /// already there. A temp file plus a replace, the pattern `compact` uses, so
    /// a kill leaves either the old side file or the new one.
    private func saveSampleSideFile(
        _ sessionId: String,
        _ samples: [WatchSensorSampleRecord]
    ) -> Bool {
        guard ensureDirectory() else { return false }

        var data = Data()
        for sample in samples {
            guard let line = rowLine(.sensorSample(sample)) else { continue }
            data.append(line)
        }

        let sideURL = sampleSideFileURL(sessionId)
        let tempURL = directory.appendingPathComponent(
            sideURL.lastPathComponent + ".tmp",
            isDirectory: false
        )
        do {
            try data.write(to: tempURL)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            return false
        }

        do {
            if FileManager.default.fileExists(atPath: sideURL.path) {
                _ = try FileManager.default.replaceItemAt(sideURL, withItemAt: tempURL)
            } else {
                try FileManager.default.moveItem(at: tempURL, to: sideURL)
            }
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            return false
        }

        sampleSideFiles[sessionId] = sideURL
        return true
    }

    private func sampleSideFileURL(_ sessionId: String) -> URL {
        directory.appendingPathComponent(
            Self.sampleFilePrefix + sessionId + Self.sampleFileSuffix,
            isDirectory: false
        )
    }

    /// The rows of one side file. Their sequences are the ones they were stored
    /// with, so a merged `readAll()` can put them back in append order.
    private func decodeSampleSideFile(_ url: URL) -> [WatchSensorSampleRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return data.split(separator: 0x0A).compactMap { line -> WatchSensorSampleRecord? in
            guard let object = (try? JSONSerialization.jsonObject(with: Data(line)))
                as? [String: Any],
                  let row = try? StoredWatchRecord.fromJson(object),
                  case .sensorSample(let sample) = row
            else { return nil }
            return sample
        }
    }

    /// The side files in the directory, by session id. A name that is not one of
    /// ours — a temporary fragment mid-replace, say — is not a side file.
    private func refreshSampleSideFiles() {
        sampleSideFiles = [:]
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        for entry in entries {
            let name = entry.lastPathComponent
            guard name.hasPrefix(Self.sampleFilePrefix),
                  name.hasSuffix(Self.sampleFileSuffix)
            else { continue }
            let sessionId = name
                .dropFirst(Self.sampleFilePrefix.count)
                .dropLast(Self.sampleFileSuffix.count)
            guard !sessionId.isEmpty else { continue }
            sampleSideFiles[String(sessionId)] = entry
        }
    }

    private func pruneExerciseBatchesLocked(_ keepingVersion: String) -> [String] {
        let loaded = loadRows()
        guard !unsupported else { return [] }

        let dropped = loaded.compactMap { row -> String? in
            guard case .exerciseBatch(let value) = row,
                  value.catalogVersion != keepingVersion else { return nil }
            return value.recordId
        }
        let kept = Set(dropped)
        let survivors = loaded.filter { row in
            guard case .exerciseBatch(let value) = row else { return true }
            return !kept.contains(value.recordId)
        }

        // A prune that finds nothing is not a write (D-3821): the file keeps
        // every byte it had, marker and torn tail included.
        guard !dropped.isEmpty else { return [] }
        guard compact(survivors) else { return [] }
        adopt(survivors)
        return dropped
    }

    private func pruneBestsLocked(_ keepingRecordId: String) -> [String] {
        let loaded = loadRows()
        guard !unsupported else { return [] }

        let stored = loaded.contains { row in
            if case .bests(let value) = row { return value.recordId == keepingRecordId }
            return false
        }
        guard stored else { return [] }

        let dropped = loaded.compactMap { row -> String? in
            guard case .bests(let value) = row,
                  value.recordId != keepingRecordId else { return nil }
            return value.recordId
        }
        let drop = Set(dropped)
        let survivors = loaded.filter { row in
            guard case .bests(let value) = row else { return true }
            return !drop.contains(value.recordId)
        }

        // A prune that finds nothing is not a write (D-3821): the file keeps
        // every byte it had, marker and torn tail included.
        guard !dropped.isEmpty else { return [] }
        guard compact(survivors) else { return [] }
        adopt(survivors)
        return dropped
    }

    private func pruneWaterLocked(_ keepingRecordId: String) -> [String] {
        let loaded = loadRows()
        guard !unsupported else { return [] }

        let stored = loaded.contains { row in
            if case .water(let value) = row { return value.recordId == keepingRecordId }
            return false
        }
        guard stored else { return [] }

        let dropped = loaded.compactMap { row -> String? in
            guard case .water(let value) = row,
                  value.recordId != keepingRecordId else { return nil }
            return value.recordId
        }
        let drop = Set(dropped)
        let survivors = loaded.filter { row in
            guard case .water(let value) = row else { return true }
            return !drop.contains(value.recordId)
        }

        // A prune that finds nothing is not a write (D-3821): the file keeps
        // every byte it had, marker and torn tail included.
        guard !dropped.isEmpty else { return [] }
        guard compact(survivors) else { return [] }
        adopt(survivors)
        return dropped
    }

    private func pruneWaterTapsLocked(_ cutoff: Date) -> [String] {
        let loaded = loadRows()
        guard !unsupported else { return [] }

        let confirmations = loaded.compactMap { row -> WatchConfirmationRecord? in
            guard case .confirmation(let value) = row else { return nil }
            return value
        }
        let observations = loaded.compactMap { row -> WatchObservationRecord? in
            guard case .observation(let value) = row else { return nil }
            return value
        }
        let dropped = confirmedWaterTapIds(
            in: applyConfirmations(observations, confirmations),
            loggedBefore: cutoff
        )
        let drop = Set(dropped)
        let survivors = loaded.filter { row in
            guard case .observation(let value) = row else { return true }
            return !drop.contains(value.recordId)
        }

        // A prune that finds nothing is not a write (D-3821): the file keeps
        // every byte it had, marker and torn tail included.
        guard !dropped.isEmpty else { return [] }
        guard compact(survivors) else { return [] }
        adopt(survivors)
        return dropped
    }

    /// Runs `body` under the lock. Synchronous by construction, so no lock is
    /// ever held across a suspension point.
    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    // MARK: - The file

    /// The file's rows, in append order, loaded once. Sets the marker and
    /// version state every other method depends on.
    private func loadRows() -> [StoredWatchRecord] {
        if let rows { return rows }

        rowsDecoded = 0
        let data = (try? Data(contentsOf: fileURL)) ?? Data()
        var loaded: [StoredWatchRecord] = []
        var sawMarker = false
        var blocked = false
        var firstLine = true

        for line in data.split(separator: 0x0A) {
            if firstLine {
                firstLine = false
                if let version = markerVersion(line) {
                    rowsDecoded += 1
                    sawMarker = true
                    blocked = version != Self.markerVersion
                    continue
                }
            }
            guard !blocked else { break }
            if let record = parseLine(line) { loaded.append(record) }
        }

        let resolved = blocked ? [] : loaded
        rows = resolved
        heldIds = Set(resolved.map(Self.rowKey))
        needsMarker = !sawMarker
        unsupported = blocked
        tornTail = !blocked && !data.isEmpty && data.last != 0x0A
        fileHasContent = !blocked && !data.isEmpty
        lastSequence = resolved.map(\.sequence).max() ?? 0
        refreshSampleSideFiles()
        // The migration runs on the first load and before anything reads the
        // rows, so no reader ever sees the inline and the moved copy of the same
        // reading (D-17304).
        if !blocked { migrateInlineSamples(resolved) }
        return rows ?? resolved
    }

    /// The version named by `line`, or nil when `line` is not a marker.
    private func markerVersion(_ line: Data) -> Int? {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
              object["format"] as? String == Self.markerFormat
        else { return nil }
        return (object["version"] as? NSNumber)?.intValue ?? Self.markerVersion
    }

    private func parseLine(_ line: Data) -> StoredWatchRecord? {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any]
        else { return nil }
        guard let record = try? StoredWatchRecord.fromJson(object) else { return nil }
        rowsDecoded += 1
        return record
    }

    private func markerLine() -> Data {
        let marker: [String: Any] = ["format": Self.markerFormat, "version": Self.markerVersion]
        let line = (try? JSONSerialization.data(withJSONObject: marker, options: [.sortedKeys]))
            ?? Data()
        return line + Data([0x0A])
    }

    /// One row as a JSON line, or nil when it cannot be serialised — a row that
    /// cannot be written is not stored, so the file never carries a half row.
    /// The row already held for `record`'s type and id, or nil. The index says
    /// whether a scan can find one; only a hit scans (D-15604).
    private func heldRow(for record: StoredWatchRecord) -> StoredWatchRecord? {
        guard heldIds.contains(Self.rowKey(record)), let held = rows else { return nil }
        return held.first {
            $0.recordId == record.recordId && $0.recordType == record.recordType
        }
    }

    private func rowLine(_ record: StoredWatchRecord) -> Data? {
        guard let line = try? JSONSerialization.data(
            withJSONObject: record.toJson(),
            options: [.sortedKeys]
        ) else { return nil }
        return line + Data([0x0A])
    }

    /// Makes the file ready for the line about to be appended, reporting whether
    /// it succeeded.
    ///
    /// A marker-less file that already holds bytes, and a file whose last line
    /// was torn, are rewritten through `compact` instead: appending a marker
    /// after the rows would leave it where the version gate never reads it, and
    /// every later launch would append another one.
    private func prepareFile() -> Bool {
        if tornTail || (needsMarker && fileHasContent) {
            return compact(loadRows())
        }
        guard ensureDirectory() else { return false }
        if needsMarker {
            guard appendLine(markerLine()) else { return false }
            needsMarker = false
            fileHasContent = true
        }
        return true
    }

    /// Appends one line, creating the file when this is the store's first write.
    /// Reports whether the bytes reached the disk: a caller that hears false
    /// must not treat the row as stored.
    private func appendLine(_ line: Data) -> Bool {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            guard FileManager.default.createFile(atPath: fileURL.path, contents: nil) else {
                return false
            }
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return false }
        defer { try? handle.close() }
        guard (try? handle.seekToEnd()) != nil else { return false }
        do {
            try handle.write(contentsOf: line)
            try handle.synchronize()
        } catch {
            return false
        }
        return true
    }

    /// Rewrites the file as marker plus `survivors`. The write lands in a
    /// sibling file and takes the real one's place, so a kill mid-rewrite leaves
    /// either the old file or the new one — never half of each. Reports whether
    /// the file was actually replaced; a caller that hears false leaves its
    /// cache alone, because the old file is still the truth.
    private func compact(_ survivors: [StoredWatchRecord]) -> Bool {
        guard ensureDirectory() else { return false }
        var data = markerLine()
        for row in survivors {
            guard let line = rowLine(row) else { continue }
            data.append(line)
        }

        let tempURL = directory.appendingPathComponent(Self.fileName + ".tmp", isDirectory: false)
        do {
            try data.write(to: tempURL)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            return false
        }

        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tempURL)
            } else {
                try FileManager.default.moveItem(at: tempURL, to: fileURL)
            }
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            return false
        }

        tornTail = false
        needsMarker = false
        fileHasContent = true
        return true
    }

    /// Reports whether the directory exists afterwards.
    private func ensureDirectory() -> Bool {
        if FileManager.default.fileExists(atPath: directory.path) { return true }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return true
        } catch {
            return false
        }
    }

    /// The main file's rows this store has decoded, for the test that bounds a
    /// launch by a count rather than by wall time (S-17301). A side file's rows
    /// are not a launch decode and are not counted. No production behaviour
    /// reads it.
    var rowsDecodedForTesting: Int {
        locked {
            _ = loadRows()
            return rowsDecoded
        }
    }

    private func nextSequence() -> Int {
        lastSequence += 1
        return lastSequence
    }
}

