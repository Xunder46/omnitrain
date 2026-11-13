//
//  WatchReplayTests.swift
//  WatchSessionEngineTests
//
//  Plan 152 Phase 3 — the differential Swift replay.
//
//  Every recording in `watch/sync_protocol/fixtures/replay/` is the wrist's input
//  timeline from one pair-harness run: the frames the wrist was handed, its own
//  actions, and its kills (`test/helpers/watch_replay_recorder.dart` writes it;
//  D-15201, D-15203). Replaying one into a real `WatchSessionEngine` and reading
//  the same store-based summary the Dart replayer reads is what compares the two
//  engines without a device (D-15205, D-15207).
//
//  A difference is a finding, never a test to bend (D-15203's brief): it is
//  bucketed into the manifest's classes, and a recording that legitimately
//  diverges is listed in `findings` below with the classes it is expected to
//  produce. That table keeps the sweep green while the divergence is real and
//  turns it red the moment the engine aligns — `XCTExpectFailure` would absorb a
//  *differently shaped* divergence on the same recording, which is the one thing
//  this file must not hide (A-152-08).
//

import XCTest

@testable import WatchSessionEngine

final class WatchReplayTests: XCTestCase {
    // MARK: - The corpus (D-15208)

    struct Recording {
        let name: String
        let gridStartMs: Int
        let events: [[String: Any]]
        let expected: [String: Any]
    }

    enum ReplayError: Error, CustomStringConvertible {
        case malformed(String)

        var description: String {
            switch self {
            case .malformed(let message): return message
            }
        }
    }

    /// Every recording the manifest lists, in manifest order.
    static func corpus() throws -> [Recording] {
        let manifest = try Fixtures.json("fixtures/replay/manifest.json")
        guard let sources = manifest["sources"] as? [[String: Any]] else {
            throw ReplayError.malformed("the replay manifest has no sources list")
        }
        return try sources.map { source in
            guard let file = source["file"] as? String,
                  let name = source["name"] as? String
            else {
                throw ReplayError.malformed("a manifest source names no file")
            }
            return try recording(named: name, file: file)
        }
    }

    /// The manifest's buckets: what a difference may be reported as (D-15206).
    static func manifestClasses() throws -> Set<String> {
        let manifest = try Fixtures.json("fixtures/replay/manifest.json")
        guard let classes = manifest["classes"] as? [String] else {
            throw ReplayError.malformed("the replay manifest has no classes list")
        }
        return Set(classes)
    }

    static func recording(named name: String, file: String? = nil) throws -> Recording {
        let json = try Fixtures.json("fixtures/replay/\(file ?? "\(name).json")")
        guard (json["formatVersion"] as? NSNumber)?.intValue == 1 else {
            throw ReplayError.malformed("\(name): unknown replay format version")
        }
        guard let gridStartMs = (json["gridStartMs"] as? NSNumber)?.intValue,
              let events = json["events"] as? [[String: Any]],
              let expected = json["expected"] as? [String: Any]
        else {
            throw ReplayError.malformed("\(name): the recording is not in the D-15203 shape")
        }
        return Recording(
            name: name,
            gridStartMs: gridStartMs,
            events: events,
            expected: expected
        )
    }

    // MARK: - The summary (D-15205)

    struct TimerSummary: Equatable {
        let state: String
        let startedAtMs: Int
    }

    struct SessionSummary: Equatable {
        let status: String
        let entries: [String]
        let timers: [String: TimerSummary]
    }

    struct Summary: Equatable {
        let current: String?
        let sessions: [String: SessionSummary]
    }

    /// The wrist's observable state, read from the append-only store by the one
    /// rule both replays share (D-15205): the newest session row's status, the
    /// stored observation ids, the newest timer row per kind, and the held
    /// session.
    ///
    /// `excludingSessionEnd` is A-152a's switch: Swift stores the session-end
    /// observation `end-<sessionId>` and the Dart twin does not, so the reader
    /// drops exactly those ids on both sides (S-15210 proves it is doing work).
    static func readSummary(
        _ contents: WatchStoreContents,
        current: String?,
        excludingSessionEnd: Bool = true
    ) -> Summary {
        var newestStatus: [String: String] = [:]
        for row in contents.sessions {
            newestStatus[row.sessionId] = row.status
        }

        var entries: [String: Set<String>] = [:]
        for observation in contents.observations {
            let sessionId = observation.sessionId
            guard newestStatus[sessionId] != nil else { continue }
            if excludingSessionEnd && isSessionEndObservation(observation) { continue }
            entries[sessionId, default: []].insert(observation.entryId)
        }

        var timers: [String: [String: TimerSummary]] = [:]
        for row in contents.timers {
            guard newestStatus[row.sessionId] != nil else { continue }
            timers[row.sessionId, default: [:]][row.kind] = TimerSummary(
                state: row.state,
                startedAtMs: milliseconds(row.startedAt)
            )
        }

        var sessions: [String: SessionSummary] = [:]
        for (sessionId, status) in newestStatus {
            sessions[sessionId] = SessionSummary(
                status: status,
                entries: (entries[sessionId] ?? []).sorted(),
                timers: timers[sessionId] ?? [:]
            )
        }
        return Summary(current: current, sessions: sessions)
    }

    /// A-152a: the session-end observation the Swift wrist stores and the Dart
    /// twin does not. The summary excludes exactly these ids on both sides.
    static func isSessionEndObservation(_ observation: WatchObservationRecord) -> Bool {
        observation.entryId == WatchSessionCapture.sessionEndId(observation.sessionId)
    }

    static func milliseconds(_ instant: Date) -> Int {
        Int((instant.timeIntervalSince1970 * 1000).rounded())
    }

    // MARK: - The rig (D-15207)

    /// A wrist-only rig: one store, a `TestClock` set per event, and counter id
    /// factories, built the way `Harness.newEngine()` builds an engine.
    final class Rig {
        let store = InMemoryWatchSessionStore()
        let clock: TestClock
        private let validator: SyncProtocolValidator?
        private var recordSerial = 0
        private var sessionSerial = 0
        private(set) var engine: WatchSessionEngine!
        /// Frames this build refused, by type and message id: the Dart replayer
        /// swallows the same refusal, so it changes the outcome, not the run.
        private(set) var refused: [String] = []

        init(gridStartMs: Int, validator: SyncProtocolValidator?) {
            clock = TestClock(Date(timeIntervalSince1970: Double(gridStartMs) / 1000))
            self.validator = validator
            engine = launch()
        }

        func noteRefused(_ type: Any?, _ messageId: Any?) {
            refused.append("\(type ?? "?") \(messageId ?? "?")")
        }

        func launch() -> WatchSessionEngine {
            WatchSessionEngine(
                store: store,
                validator: validator,
                clock: { [unowned self] in self.clock.now },
                idFactory: { [unowned self] in
                    self.recordSerial += 1
                    return "rec-\(self.recordSerial)"
                },
                sessionIdFactory: { [unowned self] in
                    self.sessionSerial += 1
                    return "s-w-\(self.sessionSerial)"
                }
            )
        }

        /// A kill: a brand-new engine over the same storage, asked to restore —
        /// the same simulation of process death the engine tests use.
        func relaunch() async {
            engine = launch()
            await engine.restore()
        }
    }

    struct ReplayResult {
        let summary: Summary
        let contents: WatchStoreContents
        let refused: [String]
    }

    /// Applies one recording to a fresh Swift wrist.
    static func replay(_ recording: Recording) async throws -> ReplayResult {
        let rig = Rig(gridStartMs: recording.gridStartMs, validator: Harness.validator())
        for event in recording.events {
            try await apply(event, to: rig)
        }
        let contents = await rig.store.readAll()
        return ReplayResult(
            summary: readSummary(contents, current: rig.engine.session?.sessionId),
            contents: contents,
            refused: rig.refused
        )
    }

    static func apply(_ event: [String: Any], to rig: Rig) async throws {
        guard let clockMs = (event["clockMs"] as? NSNumber)?.doubleValue else {
            throw ReplayError.malformed("an event carries no clockMs")
        }
        rig.clock.now = Date(timeIntervalSince1970: clockMs / 1000)

        switch event["t"] as? String {
        case "frame":
            guard let envelope = event["envelope"] as? [String: Any] else {
                throw ReplayError.malformed("a frame event carries no envelope")
            }
            do {
                try await rig.engine.applyMessage(envelope)
            } catch {
                rig.noteRefused(envelope["type"], envelope["messageId"])
            }
        case "action":
            try await applyAction(event, to: rig)
        case "kill":
            await rig.relaunch()
        default:
            throw ReplayError.malformed("unknown replay event \(event["t"] ?? "nil")")
        }
    }

    static func applyAction(_ event: [String: Any], to rig: Rig) async throws {
        switch event["name"] as? String {
        case "start":
            // The Start button's own no-op: a live session keeps the wrist.
            if let held = rig.engine.session, held.status == WatchSessionStatus.active {
                return
            }
            await rig.engine.createSession(
                modality: event["modality"] as? String,
                exercises: event["exercises"] as? [[String: Any]] ?? []
            )
        case "logSet":
            // The recorder never records a log this guard would skip.
            guard rig.engine.session != nil,
                  let payload = event["event"] as? [String: Any]
            else { return }
            try await rig.engine.appendObservation(payload)
        case "finish":
            guard rig.engine.session != nil else { return }
            await rig.engine.finishSession()
        case "discard":
            guard rig.engine.session != nil else { return }
            await rig.engine.abandonSession()
        case "restStart":
            guard rig.engine.session != nil else { return }
            try await rig.engine.startTimer(
                event["kind"] as? String ?? WatchTimerKind.rest
            )
        default:
            throw ReplayError.malformed("unknown replay action \(event["name"] ?? "nil")")
        }
    }

    // MARK: - The comparison (D-15206)

    struct Outcome {
        /// The manifest classes this difference falls into, sorted.
        let classes: [String]
        /// One line per difference, each already naming its session.
        let diffs: [String]

        var isEmpty: Bool { diffs.isEmpty }
    }

    /// Compares a replayed summary with a recording's `expected` block.
    ///
    /// Every difference lands in one of the manifest's four buckets. A recording
    /// whose `expected` block is not readable throws instead of reporting a
    /// class: a class-less mismatch must fail the test, never be normalized.
    static func outcome(_ summary: Summary, expected: [String: Any]) throws -> Outcome {
        var classes = Set<String>()
        var diffs: [String] = []

        let expectedCurrent = expected["current"] as? String
        if summary.current != expectedCurrent {
            classes.insert("current")
            diffs.append(
                "current: Swift \(summary.current ?? "nil") vs Dart \(expectedCurrent ?? "nil")"
            )
        }

        guard let expectedSessions = expected["sessions"] as? [String: Any] else {
            throw ReplayError.malformed("expected carries no sessions object")
        }
        let ids = Set(expectedSessions.keys).union(summary.sessions.keys).sorted()
        for id in ids {
            guard let raw = expectedSessions[id] else {
                classes.insert("status")
                let held = summary.sessions[id]!
                diffs.append(
                    "\(id): Swift holds \(held.status) with \(held.entries.count) entries; "
                        + "the Dart wrist did not hold the session"
                )
                continue
            }
            guard let session = raw as? [String: Any],
                  let expectedStatus = session["status"] as? String
            else {
                throw ReplayError.malformed("expected session \(id) is not an object with a status")
            }
            guard let held = summary.sessions[id] else {
                classes.insert("status")
                diffs.append("\(id): Swift holds no session; the Dart wrist ended it \(expectedStatus)")
                continue
            }
            if held.status != expectedStatus {
                classes.insert("status")
                diffs.append("\(id): status Swift \(held.status) vs Dart \(expectedStatus)")
            }

            let expectedEntries = try stringList(session["entries"], in: "entries of \(id)")
            if Set(held.entries) != Set(expectedEntries) {
                classes.insert("entries")
                let missing = Set(expectedEntries).subtracting(held.entries).sorted()
                let extra = Set(held.entries).subtracting(expectedEntries).sorted()
                diffs.append(
                    "\(id): entries Swift [\(held.entries.joined(separator: ","))] vs "
                        + "Dart [\(expectedEntries.joined(separator: ","))] "
                        + "(missing on Swift \(missing), extra on Swift \(extra))"
                )
            }

            let expectedTimers = try timerMap(session["timers"], in: "timers of \(id)")
            if held.timers != expectedTimers {
                classes.insert("timers")
                diffs.append(contentsOf: timerDiffs(
                    held.timers,
                    expectedTimers,
                    for: id
                ))
            }
        }

        return Outcome(classes: classes.sorted(), diffs: diffs)
    }

    static func stringList(_ value: Any?, in place: String) throws -> [String] {
        guard let list = value as? [String] else {
            throw ReplayError.malformed("expected \(place) is not a list of strings")
        }
        return list
    }

    static func timerMap(_ value: Any?, in place: String) throws -> [String: TimerSummary] {
        guard let map = value as? [String: Any] else {
            throw ReplayError.malformed("expected \(place) is not an object")
        }
        var timers: [String: TimerSummary] = [:]
        for (kind, raw) in map {
            guard let timer = raw as? [String: Any],
                  let state = timer["state"] as? String,
                  let startedAtMs = (timer["startedAtMs"] as? NSNumber)?.intValue
            else {
                throw ReplayError.malformed("expected \(place).\(kind) is not a timer")
            }
            timers[kind] = TimerSummary(state: state, startedAtMs: startedAtMs)
        }
        return timers
    }

    static func timerDiffs(
        _ held: [String: TimerSummary],
        _ expected: [String: TimerSummary],
        for sessionId: String
    ) -> [String] {
        let kinds = Set(held.keys).union(expected.keys).sorted()
        return kinds.compactMap { kind in
            switch (held[kind], expected[kind]) {
            case let (held?, expected?) where held != expected:
                return "\(sessionId): timer \(kind) Swift \(held.state)@\(held.startedAtMs) "
                    + "vs Dart \(expected.state)@\(expected.startedAtMs)"
            case let (nil, expected?):
                return "\(sessionId): timer \(kind) missing on Swift; Dart has "
                    + "\(expected.state)@\(expected.startedAtMs)"
            case let (held?, nil):
                return "\(sessionId): timer \(kind) Swift has \(held.state)@\(held.startedAtMs); "
                    + "Dart has none"
            default:
                return nil
            }
        }
    }

    // MARK: - Findings

    /// A recording that genuinely diverges, with the classes it diverges in.
    ///
    /// Keeping the entry here is what keeps the sweep green while the divergence
    /// is real; the assertion in `assertOutcome` names it, so the difference is
    /// visible in the test file and in the sweep's output line. When the engine
    /// aligns, the classes stop matching and the sweep goes red with "remove the
    /// finding" — the flip the plan asks for. A difference in a class the entry
    /// does not name is red too, which is why this is a table rather than
    /// `XCTExpectFailure` (that would absorb it).
    struct Finding {
        let id: String
        let classes: [String]
        let what: String
    }

    static let findings: [String: Finding] = [:]

    /// Asserts one recording's outcome, honouring the finding table.
    static func assertOutcome(
        _ outcome: Outcome,
        for recording: Recording,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if let finding = findings[recording.name] {
            XCTAssertEqual(
                outcome.classes,
                finding.classes,
                "\(recording.name): plan 152 finding \(finding.id) expects classes "
                    + "\(finding.classes) — \(finding.what). If the engines have aligned, "
                    + "remove the entry: \(outcome.diffs.joined(separator: "; "))",
                file: file,
                line: line
            )
            XCTAssertFalse(
                outcome.isEmpty,
                "\(recording.name): plan 152 finding \(finding.id) no longer reproduces — "
                    + "remove the entry",
                file: file,
                line: line
            )
            return
        }
        XCTAssertTrue(
            outcome.isEmpty,
            "\(recording.name) diverges [\(outcome.classes.joined(separator: ","))]: "
                + outcome.diffs.joined(separator: "; "),
            file: file,
            line: line
        )
    }

    // MARK: - S-15205 — the no-fault story replays green

    func testS15205TheNoFaultStoryReplaysGreen() async throws {
        let recording = try Self.recording(named: "trace-s14501")
        let result = try await Self.replay(recording)
        let outcome = try Self.outcome(result.summary, expected: recording.expected)

        print("S-15205 trace-s14501 classes=\(outcome.classes.joined(separator: ","))"
            + (result.refused.isEmpty ? "" : " refused=\(result.refused)"))

        let sessions = try XCTUnwrap(recording.expected["sessions"] as? [String: Any])
        XCTAssertEqual(sessions.count, 1, "S-15205's fixture is one workout, one session")
        let expected = try XCTUnwrap(sessions.values.first as? [String: Any])
        XCTAssertEqual(expected["status"] as? String, WatchSessionStatus.completed)
        XCTAssertEqual(
            (expected["entries"] as? [String])?.count, 3,
            "S-15205's fixture logs three entries"
        )
        XCTAssertEqual(
            (expected["timers"] as? [String: Any])?.isEmpty, true,
            "S-15205's fixture starts no timer"
        )
        Self.assertOutcome(outcome, for: recording)
    }

    // MARK: - S-15206 — F-2's finding, stated

    func testS15206F2ReproducesItsFinding() async throws {
        let recording = try Self.recording(named: "trace-f2")
        let result = try await Self.replay(recording)
        let outcome = try Self.outcome(result.summary, expected: recording.expected)

        print("S-15206 trace-f2 classes=\(outcome.classes.joined(separator: ",")) "
            + "diffs=\(outcome.diffs)")

        // The plan's premise is that F-2's wrist finishes, the phone's rest then
        // arrives late, and the wrist's end must not be revived. Both engines
        // hold `completed`; if Swift revived it, the comparison below says so
        // under `status`.
        let sessions = try XCTUnwrap(recording.expected["sessions"] as? [String: Any])
        let sessionId = try XCTUnwrap(sessions.keys.first)
        let expectedStatus = try XCTUnwrap(
            (sessions[sessionId] as? [String: Any])?["status"] as? String
        )
        XCTAssertNotEqual(
            expectedStatus, WatchSessionStatus.active,
            "F-2's recording closes with the wrist's end held, not revived"
        )
        XCTAssertEqual(
            result.summary.sessions[sessionId]?.status,
            expectedStatus,
            "the Swift wrist ends F-2's session the way the Dart wrist does"
        )
        Self.assertOutcome(outcome, for: recording)
    }

    // MARK: - S-15210 — the allowlist is structural

    func testS15210TheAllowlistIsStructural() async throws {
        let recording = try Self.recording(named: "trace-s14501")
        let result = try await Self.replay(recording)

        let ended = result.contents.sessions.map(\.sessionId)
        let sessionEnds = result.contents.observations.filter(Self.isSessionEndObservation)
        let whereEndsLive = ended.filter { id in
            sessionEnds.contains { $0.sessionId == id }
        }
        XCTAssertFalse(
            whereEndsLive.isEmpty,
            "A-152a: the Swift store holds no session-end observation for a completed "
                + "session, so the fixture cannot prove the filter is doing work"
        )

        let filtered = Self.readSummary(
            result.contents,
            current: result.summary.current,
            excludingSessionEnd: true
        )
        let unfiltered = Self.readSummary(
            result.contents,
            current: result.summary.current,
            excludingSessionEnd: false
        )
        XCTAssertEqual(filtered, result.summary, "the replay heightens with the filter on")
        XCTAssertNotEqual(
            filtered,
            unfiltered,
            "A-152a: dropping the session-end filter must change `entries` — if it does "
                + "not, this recording cannot prove the allowlist is structural"
        )

        let outcome = try Self.outcome(filtered, expected: recording.expected)
        Self.assertOutcome(outcome, for: recording)

        // The same comparison with the filter off: the difference the allowlist
        // hides, named — the shape the mutation in the evidence file produces.
        let unfilteredOutcome = try Self.outcome(unfiltered, expected: recording.expected)
        print("S-15210 filter-off classes=\(unfilteredOutcome.classes.joined(separator: ",")) "
            + "diffs=\(unfilteredOutcome.diffs)")
        XCTAssertTrue(
            unfilteredOutcome.classes.contains("entries"),
            "A-152a: without the filter the difference must be bucketed as `entries`"
        )
        XCTAssertTrue(
            whereEndsLive.contains { sessionId in
                unfilteredOutcome.diffs.contains { $0.contains(WatchSessionCapture.sessionEndId(sessionId)) }
            },
            "A-152a: the unfiltered diff must name the session-end id it hides — "
                + "\(whereEndsLive) vs \(unfilteredOutcome.diffs)"
        )
    }

    // MARK: - S-15208 — the whole corpus, every outcome named

    func testS15208EveryRecordingReplaysWithNamedOutcome() async throws {
        let recordings = try Self.corpus()
        XCTAssertFalse(recordings.isEmpty, "the replay corpus is empty")

        let classes = try Self.manifestClasses()
        var lines: [String] = []
        var counts: [String: Int] = [:]

        for recording in recordings {
            let result = try await Self.replay(recording)
            let outcome = try Self.outcome(result.summary, expected: recording.expected)

            XCTAssertTrue(
                classes.isSuperset(of: outcome.classes),
                "\(recording.name) diverges outside the manifest's classes: "
                    + "\(outcome.classes) not in \(classes.sorted())"
            )
            XCTAssertEqual(
                outcome.isEmpty,
                outcome.classes.isEmpty,
                "\(recording.name): a difference fits no class — \(outcome.diffs)"
            )
            for name in outcome.classes {
                counts[name, default: 0] += 1
            }
            lines.append(
                "\(recording.name) classes=\(outcome.classes.joined(separator: ","))"
            )
            if !result.refused.isEmpty {
                lines.append("\(recording.name) refused=\(result.refused)")
            }
            Self.assertOutcome(outcome, for: recording)
        }

        let totals = counts.keys.sorted().map { "\($0)=\(counts[$0]!)" }
        print("S-15208 differential Swift replay:\n\(lines.joined(separator: "\n"))"
            + "\nclasses: \(totals.isEmpty ? "none" : totals.joined(separator: " "))")
    }
}
