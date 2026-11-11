import Foundation

/// One recorded line of the watch's diagnostics log (plan 142).
public struct WatchDiagnosticsEvent: Equatable {
    public let at: Date
    public let kind: String
    public let session: String?
    public let detail: String?

    public init(at: Date, kind: String, session: String? = nil, detail: String? = nil) {
        self.at = at
        self.kind = kind
        self.session = session
        self.detail = detail
    }
}

/// The watch's own record of what happened: launches, scene phases, workout
/// begin/adopt/end, reachability and every sync frame with its outcome.
///
/// Observation only (D-14202): nothing reads it to decide anything, every call
/// swallows its own failure, and a collaborator holding `nil` records nothing.
/// One JSONL file in its own directory, newest `capacity` events kept: a kill
/// mid-append leaves a torn last line that reads skip and the next append starts
/// on a fresh line (the same rule `FileWatchSessionStore` follows).
public final class WatchDiagnosticsLog: @unchecked Sendable {
    /// A coalesced event is recorded at most once per this many seconds (D-14203).
    public static let coalesceWindow: TimeInterval = 60

    private static let fileName = "watch-diagnostics.jsonl"
    private static let detailLimit = 120
    private static let iso = ISO8601DateFormatter()

    private let directory: URL
    private let fileURL: URL
    private let clock: () -> Date
    private let capacity: Int
    private let slack: Int
    private let lock = NSLock()
    private var lineCount: Int?
    private var coalesced: [String: (last: Date, held: Int)] = [:]

    public init(
        directory: URL,
        clock: @escaping () -> Date = { Date() },
        capacity: Int = 3000,
        slack: Int = 300
    ) {
        self.directory = directory
        self.fileURL = directory.appendingPathComponent(Self.fileName)
        self.clock = clock
        self.capacity = capacity
        self.slack = slack
    }

    /// Records one event. With a `coalesce` key, events under that key are
    /// recorded at most once per `coalesceWindow`: the first at once, then one
    /// line per window whose detail ends `x<number of events it stands for>`.
    public func note(
        _ kind: String,
        session: String? = nil,
        detail: String? = nil,
        coalesce key: String? = nil
    ) {
        lock.lock()
        defer { lock.unlock() }

        let now = clock()
        var text = detail
        if let key {
            let state = coalesced[key]
            if let state, now.timeIntervalSince(state.last) < Self.coalesceWindow {
                coalesced[key] = (state.last, state.held + 1)
                return
            }
            let total = (state?.held ?? 0) + 1
            text = [detail, "x\(total)"].compactMap { $0 }.joined(separator: " ")
            coalesced[key] = (now, 0)
        }
        append(WatchDiagnosticsEvent(
            at: now,
            kind: kind,
            session: session,
            detail: text.map(Self.cut)
        ))
    }

    /// Records the start of a run, naming the last thing the previous run
    /// recorded: `previous=<kind>[/<detail>]@<UTC time>`, or `previous=none`.
    public func noteLaunch() {
        let last = events().last
        let previous = last.map { event -> String in
            let what = event.detail.map { "\(event.kind)/\($0)" } ?? event.kind
            return "previous=\(what)@\(ISO8601DateFormatter().string(from: event.at))"
        } ?? "previous=none"
        note("launch", detail: previous)
    }

    /// Every readable event, oldest first. A torn line is skipped.
    public func events() -> [WatchDiagnosticsEvent] {
        lock.lock()
        defer { lock.unlock() }
        return readAll()
    }

    // MARK: - File

    private func readAll() -> [WatchDiagnosticsEvent] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return data.split(separator: 0x0A).compactMap { Self.decode(Data($0)) }
    }

    private func append(_ event: WatchDiagnosticsEvent) {
        guard (try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )) != nil else { return }

        var out = Data()
        if lineCount == nil {
            // First use in this process: count what is there and start on a
            // fresh line when a kill left the last one torn.
            let existing = (try? Data(contentsOf: fileURL)) ?? Data()
            lineCount = existing.split(separator: 0x0A).count
            if let last = existing.last, last != 0x0A { out.append(0x0A) }
        }
        out.append(Self.encode(event))
        out.append(0x0A)

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            guard FileManager.default.createFile(atPath: fileURL.path, contents: nil) else { return }
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        guard (try? handle.seekToEnd()) != nil else { return }
        guard (try? handle.write(contentsOf: out)) != nil else { return }

        lineCount = (lineCount ?? 0) + 1
        if (lineCount ?? 0) >= capacity + slack { compact() }
    }

    /// Keeps the newest `capacity` events. A read that finds nothing never
    /// empties the file, and a rewrite that fails leaves the file as it was; both
    /// back the count off to `capacity`, so the next attempt comes after `slack`
    /// more events instead of at every note.
    private func compact() {
        let kept = readAll().suffix(capacity)
        guard !kept.isEmpty else {
            lineCount = capacity
            return
        }
        var data = Data()
        for event in kept {
            data.append(Self.encode(event))
            data.append(0x0A)
        }
        if (try? data.write(to: fileURL, options: .atomic)) != nil {
            lineCount = kept.count
        } else {
            lineCount = capacity
        }
    }

    // MARK: - Lines

    private static func cut(_ text: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        return String(flat.prefix(detailLimit))
    }

    private static func encode(_ event: WatchDiagnosticsEvent) -> Data {
        var object: [String: String] = [
            "at": iso.string(from: event.at),
            "kind": event.kind,
        ]
        if let session = event.session { object["session"] = session }
        if let detail = event.detail { object["detail"] = detail }
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }

    private static func decode(_ line: Data) -> WatchDiagnosticsEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: String],
              let at = object["at"].flatMap({ iso.date(from: $0) }),
              let kind = object["kind"]
        else { return nil }
        return WatchDiagnosticsEvent(
            at: at, kind: kind, session: object["session"], detail: object["detail"]
        )
    }
}
