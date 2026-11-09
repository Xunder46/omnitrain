//
//  WatchSyncProgressWiringTests.swift
//  WatchSessionEngineTests
//
//  Source guards for the wrist's sync spinner: the host starts a window when it
//  asks the phone for something, notes every reply that arrives, and ticks the
//  spinner down by the clock; the start screen shows a spinner row instead of
//  the Sync button while that window is open.
//
//  Plan: `docs/plans/2026-10-22-55-wrist-sync-progress-plan/2026-10-22-55-wrist-sync-progress-plan.md`,
//  scenarios S-8508, S-8509, S-8511 and S-8512 (decisions D-2, D-3, D-6).
//
//  The app target has no test target and `WatchStartView` compiles only under
//  xcodebuild, so what `swift test` holds is the text the wiring is made of.
//  `WatchSyncProgress` itself is covered by `WatchSyncProgressTests`.
//
//  Every guard reads a file's text with its comment lines removed, so a sentence
//  of prose can neither satisfy a guard nor trip one.
//

import Foundation
import XCTest

final class WatchSyncProgressWiringTests: XCTestCase {

    // MARK: - Reading the two targets

    /// A file of the app target, read from the repository root, with every
    /// comment-only line blanked out (the line count is kept).
    private func appSource(_ name: String) throws -> String {
        let url = Fixtures.repositoryRoot
            .appendingPathComponent("ios/OmniTrain Watch App/\(name)")
        let text = try String(contentsOf: url, encoding: .utf8)
        return strippingCommentLines(text)
    }

    /// A file of the watch package's engine module, read the same way.
    private func engineSource(_ name: String) throws -> String {
        let url = Fixtures.repositoryRoot
            .appendingPathComponent("watch/watchos/Sources/WatchSessionEngine/\(name)")
        let text = try String(contentsOf: url, encoding: .utf8)
        return strippingCommentLines(text)
    }

    /// Blanks every line whose trimmed text starts with `//`, keeping the line
    /// boundaries so line indexes stay true. A trailing `//` comment on a code
    /// line is blanked too, so prose there can neither satisfy a guard nor trip
    /// one.
    private func strippingCommentLines(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { return "" }
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    // MARK: - Matching helpers

    /// The lines of `source`.
    private func sourceLines(_ source: String) -> [String] {
        source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    /// The brace-balanced body of the first line containing `needle`, from its
    /// opening brace to its closing one, or nil when that line is not there.
    private func braceBody(ofLineContaining needle: String, in source: String) -> String? {
        let lines = sourceLines(source)
        guard let start = lines.firstIndex(where: { $0.contains(needle) }) else {
            return nil
        }

        var depth = 0
        var started = false
        var body: [String] = []
        for line in lines[start...] {
            for character in line {
                if character == "{" {
                    depth += 1
                    started = true
                } else if character == "}" {
                    depth -= 1
                }
            }
            if started { body.append(line) }
            if started, depth == 0 { break }
        }
        return started ? body.joined(separator: "\n") : nil
    }

    /// A line of `source` whose trimmed text is exactly `text`: the bare
    /// statement, not a line that merely contains it — a gated call reads
    /// `if reachable { beginSyncProgress() }`, which is not the bare one.
    private func hasStatement(_ text: String, in source: String) -> Bool {
        sourceLines(source).contains { $0.trimmingCharacters(in: .whitespaces) == text }
    }

    /// The first line index of `source` containing `needle`, or nil.
    private func lineIndex(of needle: String, in source: String) -> Int? {
        sourceLines(source).firstIndex { $0.contains(needle) }
    }

    // MARK: - S-8508: the host opens a window where a sync can be waited on

    /// `requestSync` opens the window before it awaits the orchestrator, because
    /// `sync` returns as soon as the frames are sent and the phone's answer
    /// lands afterwards (D-2).
    func testS8508RequestSyncBeginsTheWindowBeforeAwaiting() throws {
        let view = try appSource("ContentView.swift")

        let requestSync = try XCTUnwrap(
            braceBody(ofLineContaining: "func requestSync() async", in: view),
            "S-8508 the host carries the Sync button's action"
        )

        let begin = try XCTUnwrap(
            lineIndex(of: "beginSyncProgress()", in: requestSync),
            "S-8508 the request opens a sync window (D-2)"
        )
        let send = try XCTUnwrap(
            lineIndex(of: "orchestrator.sync(", in: requestSync),
            "S-8508 the request still sends the sync"
        )

        XCTAssertLessThan(
            begin,
            send,
            "S-8508 the window opens before the send is awaited, or the spinner starts after "
                + "the reply it is waiting for"
        )
    }

    /// Every arriving frame is noted before it is routed, so a frame the wrist
    /// refuses still ends the wait — the phone spoke (D-2, A-3).
    func testS8508ArrivalsAreNotedBeforeTheReceive() throws {
        let view = try appSource("ContentView.swift")

        let incoming = try XCTUnwrap(
            braceBody(ofLineContaining: "bridge.onIncoming", in: view),
            "S-8508 the host routes the radio's arrivals"
        )

        let note = try XCTUnwrap(
            lineIndex(of: "syncProgress.noteArrival(", in: incoming),
            "S-8508 an arrival is noted on the sync window"
        )
        let receive = try XCTUnwrap(
            lineIndex(of: "orchestrator.receive(", in: incoming),
            "S-8508 the frame is still routed to the orchestrator"
        )

        XCTAssertLessThan(
            note,
            receive,
            "S-8508 the note comes before the receive, so a refused frame still counts (A-3)"
        )
        XCTAssertTrue(
            incoming.contains("MainActor.run"),
            "S-8508 the handler runs off the main actor, so the note is hopped to it"
        )
    }

    /// Both catch-up sites open the window too, and only when the phone is in
    /// reach: an unreachable phone has nothing to wait for (D-2, A-4).
    func testS8508CatchUpBeginsOnlyWhenReachable() throws {
        let view = try appSource("ContentView.swift")

        let reachability = try XCTUnwrap(
            braceBody(ofLineContaining: "bridge.onReachabilityChange", in: view),
            "S-8508 the host maps the radio's reachability answers"
        )
        XCTAssertTrue(
            reachability.contains("if reachable && self.paths.syncedAt == nil { self.beginSyncProgress() }"),
            "S-8508 the reachability edge opens the window only on a reachable phone (A-4)"
        )
        XCTAssertFalse(
            hasStatement("self.beginSyncProgress()", in: reachability),
            "S-8508 an ungated begin would spin on an unreachable phone, where catchUp does nothing"
        )
        let edgeBegin = try XCTUnwrap(
            lineIndex(of: "beginSyncProgress()", in: reachability),
            "S-8508 the reachability edge opens a window"
        )
        let edgeCatchUp = try XCTUnwrap(
            lineIndex(of: "orchestrator.catchUp(", in: reachability),
            "S-8508 the reachability edge still catches the wrist up"
        )
        XCTAssertLessThan(edgeBegin, edgeCatchUp, "S-8508 the window opens before the catch-up")

        let activation = try XCTUnwrap(
            braceBody(ofLineContaining: "func catchUpOnActivation()", in: view),
            "S-8508 the host catches the wrist up on activation too"
        )
        XCTAssertTrue(
            activation.contains("phoneReachability == .reachable"),
            "S-8508 activation reads the phone's reachability to decide"
        )
        XCTAssertTrue(
            activation.contains("if reachable && paths.syncedAt == nil { beginSyncProgress() }"),
            "S-8508 activation opens the window only on a reachable phone (A-4)"
        )
        XCTAssertFalse(
            hasStatement("beginSyncProgress()", in: activation),
            "S-8508 an ungated begin on activation would spin beside an unreachable phone"
        )
        let activationBegin = try XCTUnwrap(
            lineIndex(of: "beginSyncProgress()", in: activation),
            "S-8508 activation opens a window"
        )
        let activationCatchUp = try XCTUnwrap(
            lineIndex(of: "orchestrator.catchUp(", in: activation),
            "S-8508 activation still catches the wrist up"
        )
        XCTAssertLessThan(
            activationBegin,
            activationCatchUp,
            "S-8508 the window opens before the catch-up it is waiting on"
        )
    }

    // MARK: - S-9221: an incremental catch-up opens no window

    /// A wrist that already holds a routines catalog asks only for what changed
    /// (plan 62), so a phone with nothing new sends nothing: its automatic
    /// catch-ups must open no sync window, or a raise with nothing changed would
    /// spin for 20 s and then say "No answer". The Sync button still asks for
    /// everything and always opens the window.
    func testS9221AnIncrementalCatchUpOpensNoWindow() throws {
        let view = try appSource("ContentView.swift")

        let reachability = try XCTUnwrap(
            braceBody(ofLineContaining: "bridge.onReachabilityChange", in: view),
            "S-9221 the host maps the radio's reachability answers"
        )
        XCTAssertTrue(
            reachability.contains("if reachable && self.paths.syncedAt == nil { self.beginSyncProgress() }"),
            "S-9221 the reachability edge opens the window only on a first sync; otherwise a raise "
                + "with nothing changed would spin for 20 s and then say No answer"
        )

        let activation = try XCTUnwrap(
            braceBody(ofLineContaining: "func catchUpOnActivation()", in: view),
            "S-9221 the host catches the wrist up on activation too"
        )
        XCTAssertTrue(
            activation.contains("if reachable && paths.syncedAt == nil { beginSyncProgress() }"),
            "S-9221 activation opens the window only on a first sync; otherwise a raise with "
                + "nothing changed would spin for 20 s and then say No answer"
        )
        XCTAssertTrue(
            activation.contains("await orchestrator.catchUp(reachable: reachable)"),
            "S-9221 the incremental request is still sent on activation, or the wrist would stop "
                + "converging without the Sync button"
        )

        let requestSync = try XCTUnwrap(
            braceBody(ofLineContaining: "func requestSync() async", in: view),
            "S-9221 the host carries the Sync button's action"
        )
        XCTAssertTrue(
            hasStatement("beginSyncProgress()", in: requestSync),
            "S-9221 the Sync button always opens the window: it asks for everything, so there is "
                + "always an answer to wait for"
        )
        XCTAssertFalse(
            requestSync.contains("syncedAt"),
            "S-9221 the Sync button must not gate its window on what the wrist holds, or a wrong "
                + "\"nothing changed\" answer would leave it spinning with no way out"
        )
    }

    // MARK: - S-8509: the Sync button becomes a spinner

    /// The start surface takes the flag with a default, so every existing call
    /// site keeps compiling, and draws a `ProgressView` rather than the button
    /// while it is set (D-3).
    func testS8509TheStartSurfaceTakesIsSyncingAndSpins() throws {
        let start = try engineSource("WatchStartView.swift")

        XCTAssertTrue(
            start.contains("isSyncing: Bool = false"),
            "S-8509 the flag is a defaulted parameter, so no call site breaks (D-3)"
        )
        XCTAssertTrue(
            start.contains("self.isSyncing = isSyncing"),
            "S-8509 the view stores the flag it is handed"
        )
        XCTAssertTrue(
            start.contains("ProgressView()"),
            "S-8509 the wrist is shown that it is working, not asked to work"
        )
        XCTAssertTrue(
            start.contains("WatchStartSurfaceCopy.syncingLabel"),
            "S-8509 the words come from the surface's copy home (D-7)"
        )

        let spinning = try XCTUnwrap(
            braceBody(ofLineContaining: "if isSyncing {", in: start),
            "S-8509 the surface splits on the flag"
        )
        let spinBranch = try XCTUnwrap(
            spinning.components(separatedBy: "} else {").first,
            "S-8509 the flag's true branch is one half of the split"
        )
        let idleBranch = try XCTUnwrap(
            spinning.components(separatedBy: "} else {").last,
            "S-8509 and the Sync button is the other"
        )
        XCTAssertFalse(
            spinBranch.contains("Button("),
            "S-8509 the spinning row is not tappable: a second tap must start nothing"
        )
        XCTAssertTrue(
            idleBranch.contains("Button(Self.syncLabel, action: onRequestSync)"),
            "S-8509 the wait ending is what brings the Sync button back"
        )

        let afterSpin = try XCTUnwrap(
            lineIndex(of: "ProgressView()", in: start),
            "S-8509 the spinner is drawn"
        )
        let button = try XCTUnwrap(
            lineIndex(of: "Button(Self.syncLabel, action: onRequestSync)", in: start),
            "S-8509 the Sync button survives in the else branch (S-7205 reads its line)"
        )
        XCTAssertLessThan(afterSpin, button, "S-8509 the button is what shows when the wait ends")
    }

    // MARK: - S-8511: no transport, no spinner

    /// The spinner row sits inside the same gate as the Sync button, so a wrist
    /// with no transport — or an unreachable phone — shows neither (D-3).
    func testS8511TheSpinnerSitsInsideTheSyncGate() throws {
        let start = try engineSource("WatchStartView.swift")

        let gate = try XCTUnwrap(
            braceBody(ofLineContaining: "if let onRequestSync, phoneStatus.offersSync", in: start),
            "S-8511 the Sync row is gated on the host's action and the phone's offer"
        )

        XCTAssertTrue(
            gate.contains("if isSyncing {"),
            "S-8511 the spinner split lives inside the gate, not beside it"
        )
        XCTAssertTrue(
            gate.contains("ProgressView()"),
            "S-8511 so a watch with no transport never shows a spinner"
        )
        XCTAssertTrue(
            gate.contains("Button(Self.syncLabel, action: onRequestSync)"),
            "S-8511 and never shows the button without a transport either"
        )
    }

    // MARK: - S-8512: the spinner ends by the clock

    /// The tick re-reads the window and exits when it is over, and assigns
    /// `isSyncing` alone: `revision` drives the workout and sensor refresh, so a
    /// half-second bump would run them for the length of every sync (D-6).
    func testS8512TheTickerEndsTheSpinnerWithoutBumpingRevision() throws {
        let view = try appSource("ContentView.swift")

        let begin = try XCTUnwrap(
            braceBody(ofLineContaining: "private func beginSyncProgress()", in: view),
            "S-8512 the host carries the one helper that begins a window (D-6)"
        )
        XCTAssertTrue(begin.contains("syncProgress.begin()"), "S-8512 the window is opened")
        XCTAssertTrue(begin.contains("isSyncing = true"), "S-8512 the spinner starts at once")
        XCTAssertFalse(
            begin.contains("begin(at:"),
            "S-8512 production reads the default clock rather than a passed one"
        )

        let ticker = try XCTUnwrap(
            braceBody(ofLineContaining: "syncProgressTicker = Task", in: view),
            "S-8512 the window is ticked down by a host-owned task (D-6)"
        )
        XCTAssertTrue(
            ticker.contains("syncProgress.isActive(at: Date())"),
            "S-8512 each tick re-reads the window against the clock"
        )
        XCTAssertTrue(
            ticker.contains("self.isSyncing = false"),
            "S-8512 the tick clears the flag when the window is over"
        )
        XCTAssertTrue(
            ticker.contains("return"),
            "S-8512 and stops, rather than ticking forever"
        )
        XCTAssertFalse(
            ticker.contains("revision"),
            "S-8512 the tick never bumps `revision`: the sink would re-run the workout and the "
                + "sensors twice a second"
        )
        XCTAssertFalse(
            begin.contains("revision"),
            "S-8512 and neither does the begin, which runs on every Sync tap"
        )

        XCTAssertTrue(
            view.contains("let syncProgressTickNanoseconds: UInt64"),
            "S-8512 the tick interval is a bounded constant, so the tick is finite"
        )
    }
}
