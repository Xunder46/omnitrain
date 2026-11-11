//
//  WatchDiagnosticsLogTests.swift
//  WatchSessionEngineTests
//
//  Plan 142 — the scenarios S-14201..S-14205, S-14214, S-14215 for the
//  file-backed diagnostics log (`WatchDiagnosticsLog.swift`). The log is
//  observation only: these tests hold what it records and reads, including
//  the torn last line and the unwritable-directory cases.
//

import XCTest

@testable import WatchSessionEngine

final class WatchDiagnosticsLogTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-diagnostics-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        // A failed-compaction test leaves the directory read-only: restore it
        // first so cleanup can remove it.
        if let directory {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: directory.path
            )
            try? FileManager.default.removeItem(at: directory)
        }
        super.tearDown()
    }

    private var fileURL: URL {
        directory.appendingPathComponent("watch-diagnostics.jsonl")
    }

    /// S-14201 three events noted by one log read back, same and in order,
    /// by a brand-new log over the same directory.
    func testS14201ThreeEventsSurviveANewLogOverTheSameDirectory() {
        let t0 = testInstant()
        let clock = TestClock(t0)
        let first = WatchDiagnosticsLog(directory: directory, clock: clock.call)
        first.note("launch")
        clock.advance(1)
        first.note("scene", detail: "background")
        clock.advance(1)
        first.note("frame_sent", session: "s-1", detail: "live")

        let second = WatchDiagnosticsLog(directory: directory, clock: clock.call)
        let read = second.events()
        XCTAssertEqual(read.count, 3, "S-14201 the new log reads all three events")
        XCTAssertEqual(
            read.map(\.kind), ["launch", "scene", "frame_sent"], "S-14201 the kinds, in order"
        )
        XCTAssertEqual(
            read.map(\.session), [nil, nil, "s-1" as String?], "S-14201 the sessions, in order"
        )
        XCTAssertEqual(
            read.map(\.detail), [nil, "background" as String?, "live" as String?],
            "S-14201 the details, in order"
        )
        XCTAssertEqual(
            read.map(\.at), [t0, t0.addingTimeInterval(1), t0.addingTimeInterval(2)],
            "S-14201 the times, in order"
        )
    }

    /// S-14202 thirty notes against a cap of 20 (compacts past 22): the newest
    /// twenty survive in order, the file stays at most 22 lines, and a new log
    /// over the directory reads the same.
    func testS14202ThirtyNotesCompactedToTheNewestTwenty() {
        let clock = TestClock(testInstant())
        let log = WatchDiagnosticsLog(directory: directory, clock: clock.call, capacity: 20, slack: 2)
        for index in 1...30 {
            log.note("note", detail: "n\(index)")
        }

        let details = log.events().compactMap(\.detail)
        XCTAssertEqual(details, (11...30).map { "n\($0)" }, "S-14202 the newest twenty, oldest first")

        let data = (try? Data(contentsOf: fileURL)) ?? Data()
        XCTAssertLessThanOrEqual(data.split(separator: 0x0A).count, 22, "S-14202 the file's line count")

        let second = WatchDiagnosticsLog(directory: directory, clock: clock.call)
        XCTAssertEqual(
            second.events().compactMap(\.detail), (11...30).map { "n\($0)" },
            "S-14202 the new log reads the same"
        )
    }

    /// S-14203 a file whose last line is cut mid-record with no newline: the
    /// torn line is skipped on read, and the next append starts on a fresh
    /// line so the new event reads back.
    func testS14203ATornLastLineIsSkippedAndTheNextAppendStartsAFreshLine() {
        let first = WatchDiagnosticsLog(directory: directory, clock: TestClock(testInstant()).call)
        first.note("launch")

        var torn = (try? Data(contentsOf: fileURL)) ?? Data()
        torn.append(Data("{\"at\":\"2026-07-13T06:00:0".utf8))
        try? torn.write(to: fileURL)

        let second = WatchDiagnosticsLog(directory: directory, clock: TestClock(testInstant()).call)
        let before = second.events()
        XCTAssertEqual(before.count, 1, "S-14203 only the valid line reads")
        XCTAssertEqual(before.first?.kind, "launch", "S-14203 the valid line is the launch")

        second.note("scene")
        let after = second.events()
        XCTAssertEqual(after.count, 2, "S-14203 the torn fragment stays skipped")
        XCTAssertEqual(after.map(\.kind), ["launch", "scene"], "S-14203 the new event reads back in order")
    }

    /// S-14204 a directory that cannot be created (a regular file sits where
    /// the directory should be): `note` neither throws nor traps, `events()`
    /// is empty.
    func testS14204ADirectoryThatCannotBeCreatedNeitherThrowsNorTraps() {
        let block = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-diagnostics-block-\(UUID().uuidString)", isDirectory: false)
        _ = FileManager.default.createFile(atPath: block.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: block) }

        let log = WatchDiagnosticsLog(
            directory: block.appendingPathComponent("sub"), clock: TestClock(testInstant()).call
        )
        log.note("launch", detail: "previous=none")

        XCTAssertEqual(log.events(), [], "S-14204 nothing was recorded and nothing failed")
    }

    /// S-14205 run 2's launch names the last thing run 1 recorded; an empty
    /// log says `previous=none`; an event without detail carries no slash.
    func testS14205NoteLaunchNamesThePreviousRunAndNoneWhenEmpty() {
        let t0 = testInstant()
        let iso = ISO8601DateFormatter().string(from: t0)

        let run1 = WatchDiagnosticsLog(directory: directory, clock: TestClock(t0).call)
        run1.note("scene", detail: "background")
        let run2 = WatchDiagnosticsLog(directory: directory, clock: TestClock(t0).call)
        run2.noteLaunch()
        let launch = run2.events().last
        XCTAssertEqual(launch?.kind, "launch", "S-14205 the newest event is the launch")
        XCTAssertEqual(
            launch?.detail, "previous=scene/background@\(iso)", "S-14205 the previous run's last act"
        )

        let emptyDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-diagnostics-empty-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: emptyDirectory) }
        let empty = WatchDiagnosticsLog(directory: emptyDirectory, clock: TestClock(t0).call)
        empty.noteLaunch()
        XCTAssertEqual(
            empty.events().last?.detail, "previous=none", "S-14205 an empty log names nothing"
        )

        let bareDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-diagnostics-bare-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: bareDirectory) }
        let bare = WatchDiagnosticsLog(directory: bareDirectory, clock: TestClock(t0).call)
        bare.note("frame_sent")
        bare.noteLaunch()
        XCTAssertEqual(
            bare.events().last?.detail, "previous=frame_sent@\(iso)",
            "S-14205 no detail means no slash in the previous reference"
        )
    }

    /// S-14214 a coalesced key records once per 60 s window: the first at
    /// once with `x1`, then the window's count `x30`; a different key in the
    /// same window is recorded on its own.
    func testS14214ACoalescedKeyRecordsOncePerWindowAndCountsWhatItHeld() {
        let clock = TestClock(testInstant())
        let log = WatchDiagnosticsLog(directory: directory, clock: clock.call)
        for _ in 1...30 {
            log.note("frame_sent", detail: "live", coalesce: "frame_sent/energy_live")
            clock.advance(0.5)
        }
        clock.advance(61)
        log.note("frame_sent", detail: "live", coalesce: "frame_sent/energy_live")
        log.note("frame_sent", detail: "paced", coalesce: "frame_sent/other")

        let sent = log.events().filter { $0.kind == "frame_sent" }
        XCTAssertEqual(sent.count, 3, "S-14214 exactly the held line, the window line, the other key")
        XCTAssertEqual(
            sent.map(\.detail), ["live x1", "live x30", "paced x1"], "S-14214 the coalesced counts"
        )
    }

    /// S-14215 a long detail with a newline cut to at most 120 characters
    /// (the case where the newline itself is outside the kept part).
    func testS14215ALongDetailIsCutToOneTwentyCharactersWithoutANewline() {
        let log = WatchDiagnosticsLog(directory: directory, clock: TestClock(testInstant()).call)
        let detail = String(repeating: "a", count: 150) + "\n" + String(repeating: "a", count: 149)
        log.note("frame_sent", detail: detail)

        let stored = log.events().first?.detail
        XCTAssertNotNil(stored, "S-14215 the event was recorded")
        XCTAssertLessThanOrEqual(stored?.count ?? 0, 120, "S-14215 cut to the limit")
        XCTAssertFalse(stored?.contains("\n") ?? true, "S-14215 the newline is gone")
    }

    /// S-14215 a newline inside the kept part is flattened too, not only one
    /// a cut would remove anyway.
    func testS14215ANewlineInsideTheKeptPartIsFlattened() {
        let log = WatchDiagnosticsLog(directory: directory, clock: TestClock(testInstant()).call)
        log.note("note", detail: "ab\ncd")

        XCTAssertEqual(
            log.events().first?.detail, "ab cd",
            "S-14215 the newline inside the kept part became a space"
        )
    }

    /// S-14202 a relaunch counts the lines already in the file: 21 held lines
    /// plus the new run's first note reach the threshold and compact at once.
    func testS14202ARelaunchCountsWhatTheFileAlreadyHolds() {
        let clock = TestClock(testInstant())
        let first = WatchDiagnosticsLog(
            directory: directory, clock: clock.call, capacity: 20, slack: 2
        )
        for index in 1...21 {
            first.note("note", detail: "n\(index)")
        }

        let second = WatchDiagnosticsLog(
            directory: directory, clock: clock.call, capacity: 20, slack: 2
        )
        second.note("note", detail: "n22")

        let data = (try? Data(contentsOf: fileURL)) ?? Data()
        XCTAssertEqual(
            data.split(separator: 0x0A).count, 20,
            "S-14202 21 held lines and one new note compacted at once"
        )
        XCTAssertEqual(
            second.events().compactMap(\.detail), (3...22).map { "n\($0)" },
            "S-14202 the newest twenty survived, oldest first"
        )
    }

    /// S-14202 a rewrite that fails backs the count off to `capacity`: the
    /// next attempt comes after `slack` more events, not at every note, and
    /// the failed rewrite left the file exactly as it was.
    func testS14202AFailedCompactionBacksOffInsteadOfRetryingEveryNote() throws {
        let clock = TestClock(testInstant())
        let log = WatchDiagnosticsLog(directory: directory, clock: clock.call, capacity: 20, slack: 2)
        for index in 1...21 {
            log.note("note", detail: "n\(index)")
        }

        func lineCount() -> Int {
            ((try? Data(contentsOf: fileURL)) ?? Data()).split(separator: 0x0A).count
        }
        XCTAssertEqual(lineCount(), 21, "S-14202A the twenty-one notes are on disk")

        // A read-only directory: the append to the existing file still works,
        // but the atomic rewrite cannot create its temporary file.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555], ofItemAtPath: directory.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: directory.path
            )
        }

        log.note("note", detail: "n22")
        XCTAssertEqual(
            lineCount(), 22,
            "S-14202A the append worked and the failed rewrite left the file as it was"
        )

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: directory.path
        )

        log.note("note", detail: "n23")
        XCTAssertEqual(
            lineCount(), 23,
            "S-14202A the count backed off to 20, so the 21st note attempts no rewrite"
        )

        log.note("note", detail: "n24")
        XCTAssertEqual(
            lineCount(), 20,
            "S-14202A the 22nd note reaches the threshold and the rewrite succeeds"
        )
        XCTAssertEqual(
            log.events().compactMap(\.detail), (5...24).map { "n\($0)" },
            "S-14202A the newest twenty, oldest first"
        )
    }
}
