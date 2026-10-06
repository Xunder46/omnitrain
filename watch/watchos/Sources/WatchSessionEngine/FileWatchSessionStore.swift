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

    private let directory: URL
    private let fileURL: URL
    private let lock = NSLock()

    /// The file's rows, loaded once on first use and kept in step with every
    /// append, so `nextSequence()` never re-reads the file.
    private var rows: [StoredWatchRecord]?

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

    public func pruneConfirmed() async -> [String] {
        locked { pruneConfirmedLocked() }
    }

    public func pruneSensorSamples(_ sessionIds: [String]) async -> [String] {
        locked { pruneSensorSamplesLocked(sessionIds) }
    }

    // MARK: - The four operations

    private func appendLocked(_ record: StoredWatchRecord) -> StoredWatchRecord {
        let loaded = loadRows()
        guard !unsupported else { return record }

        for row in loaded
        where row.recordId == record.recordId && row.recordType == record.recordType {
            return row
        }

        let stored = record.withSequence(nextSequence())
        guard let line = rowLine(stored) else { return record }

        // A row the disk refused is not durable: it stays out of the cache so
        // the process does not read back a row the next launch cannot see. The
        // caller still gets it, with the sequence it was given, because the
        // engine keeps the newest row and one sequence 0 would lose that tie.
        guard prepareFile(), appendLine(line) else { return stored }
        rows?.append(stored)
        fileHasContent = true
        return stored
    }

    private func readAllLocked() -> WatchStoreContents {
        let loaded = loadRows()
        guard !unsupported else { return WatchStoreContents() }

        var sessions: [WatchSessionRecord] = []
        var observations: [WatchObservationRecord] = []
        var timers: [WatchTimerRecord] = []
        var confirmations: [WatchConfirmationRecord] = []
        var sensorSamples: [WatchSensorSampleRecord] = []
        var routineCatalogs: [WatchRoutineCatalogRecord] = []
        var foodCatalogs: [WatchFoodCatalogRecord] = []
        var preferences: [WatchPreferencesRecord] = []
        var ratingPrompts: [WatchRatingPromptRecord] = []

        for row in loaded {
            switch row {
            case .session(let value): sessions.append(value)
            case .observation(let value): observations.append(value)
            case .timer(let value): timers.append(value)
            case .sensorSample(let value): sensorSamples.append(value)
            case .confirmation(let value): confirmations.append(value)
            case .routineCatalog(let value): routineCatalogs.append(value)
            case .foodCatalog(let value): foodCatalogs.append(value)
            case .preferences(let value): preferences.append(value)
            case .ratingPrompt(let value): ratingPrompts.append(value)
            }
        }

        return WatchStoreContents(
            sessions: sessions,
            observations: applyConfirmations(observations, confirmations),
            timers: timers,
            confirmations: confirmations,
            sensorSamples: sensorSamples,
            routineCatalogs: routineCatalogs,
            foodCatalogs: foodCatalogs,
            preferences: preferences,
            ratingPrompts: ratingPrompts
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

        guard compact(survivors) else { return [] }
        rows = survivors
        return confirmed
    }

    private func pruneSensorSamplesLocked(_ sessionIds: [String]) -> [String] {
        let named = Set(sessionIds)
        guard !named.isEmpty else { return [] }

        let loaded = loadRows()
        guard !unsupported else { return [] }

        let dropped = loaded.compactMap { row -> String? in
            guard case .sensorSample(let value) = row, named.contains(value.sessionId) else {
                return nil
            }
            return value.recordId
        }
        let survivors = loaded.filter { row in
            guard case .sensorSample(let value) = row else { return true }
            return !named.contains(value.sessionId)
        }

        guard compact(survivors) else { return [] }
        rows = survivors
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

        let data = (try? Data(contentsOf: fileURL)) ?? Data()
        var loaded: [StoredWatchRecord] = []
        var sawMarker = false
        var blocked = false
        var firstLine = true

        for line in data.split(separator: 0x0A) {
            if firstLine {
                firstLine = false
                if let version = markerVersion(line) {
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
        needsMarker = !sawMarker
        unsupported = blocked
        tornTail = !blocked && !data.isEmpty && data.last != 0x0A
        fileHasContent = !blocked && !data.isEmpty
        lastSequence = resolved.map(\.sequence).max() ?? 0
        return resolved
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
        return try? StoredWatchRecord.fromJson(object)
    }

    private func markerLine() -> Data {
        let marker: [String: Any] = ["format": Self.markerFormat, "version": Self.markerVersion]
        let line = (try? JSONSerialization.data(withJSONObject: marker, options: [.sortedKeys]))
            ?? Data()
        return line + Data([0x0A])
    }

    /// One row as a JSON line, or nil when it cannot be serialised — a row that
    /// cannot be written is not stored, so the file never carries a half row.
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

    private func nextSequence() -> Int {
        lastSequence += 1
        return lastSequence
    }
}
