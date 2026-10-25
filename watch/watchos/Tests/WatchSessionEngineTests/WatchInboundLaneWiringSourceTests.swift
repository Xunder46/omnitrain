//
//  WatchInboundLaneWiringSourceTests.swift
//  WatchSessionEngineTests
//
//  S-9315 of
//  `docs/plans/2026-10-23-63-message-order-plan/2026-10-23-63-message-order-plan.md`
//  — the wiring the lane and the stale rule are made of, held as source
//  guards: the app target's `deliver` hands frames to the lane, and the
//  engine refuses a snapshot older than the newest one applied (plan 63
//  D-4, D-5, D-6).
//
//  The app target has no test target and SwiftUI does not exist on macOS where
//  `swift test` runs, so what can be held off-device is the text the wiring is
//  made of.
//
//  Every guard reads the file's text with its comment lines removed, so a
//  sentence of prose can neither satisfy a guard nor trip one.
//

import Foundation
import XCTest

import WatchSessionEngine

final class WatchInboundLaneWiringSourceTests: XCTestCase {

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

    // MARK: - S-9315 the lane is what deliver hands frames to

    /// The radio's arrivals go through the lane, so the bridge's handler runs
    /// one frame at a time in arrival order. The old hopped form must be gone:
    /// a direct hop would let two frames' handlers overlap, and the wearer
    /// would stop getting the guarantee that the wrist's state changes in
    /// arrival order.
    func testS9315DeliverHandsFramesToTheLane() throws {
        let source = try appSource("OmniTrainWatchConnectivity.swift")

        XCTAssertTrue(
            source.contains("lane.enqueue(message)"),
            "S-9315 `deliver` hands each frame to the lane, so the wearer keeps "
                + "getting frames handled one at a time in arrival order"
        )
        XCTAssertTrue(
            source.contains("WatchInboundLane(startsOpen: false)"),
            "S-9315 the bridge builds the lane over its own handler, so the "
                + "wearer keeps getting every arrival routed through the one-at-a-time path"
        )
        XCTAssertFalse(
            source.contains("Task { @MainActor in await self.receiveHandler"),
            "S-9315 the old per-frame hop is gone: without the lane the wearer "
                + "would stop getting the guarantee that no two frames' handlers overlap"
        )
    }

    // MARK: - S-10306 the radio builds its lane closed, before the delegate

    /// The lane is built closed in `init`, before `session.delegate = self`, so
    /// a frame the OS delivers during launch waits in the lane instead of
    /// racing a `lazy var` built on a delegate thread (plan 73 D-4). The gate
    /// is opened by `openInbound`, and nothing else.
    func testS10306TheRadioBuildsItsLaneClosedBeforeTheDelegate() throws {
        let source = try appSource("OmniTrainWatchConnectivity.swift")

        XCTAssertTrue(
            source.contains("WatchInboundLane(startsOpen: false)"),
            "S-10306 the lane is built closed, so a frame that arrives during "
                + "launch waits instead of being dropped"
        )
        XCTAssertFalse(
            source.contains("private lazy var lane"),
            "S-10306 the lane is no longer a `lazy var`: a lazy var built from "
                + "a delegate thread races"
        )

        let openInbound = try XCTUnwrap(
            source.range(of: "func openInbound() {"),
            "S-10306 the radio has an `openInbound`"
        )
        let laneOpen = try XCTUnwrap(
            source.range(
                of: "lane.open()",
                options: .literal,
                range: openInbound.lowerBound..<source.endIndex
            ),
            "S-10306 `openInbound` opens the lane's gate"
        )
        let openInboundEnd = try XCTUnwrap(
            source.range(
                of: "}",
                options: .literal,
                range: laneOpen.lowerBound..<source.endIndex
            ),
            "S-10306 `openInbound`'s body ends"
        )
        XCTAssertLessThan(
            laneOpen.lowerBound, openInboundEnd.lowerBound,
            "S-10306 `lane.open()` sits inside `openInbound`'s body"
        )

        let laneBuilt = try XCTUnwrap(
            source.range(of: "WatchInboundLane(startsOpen: false)"),
            "S-10306 the lane is built in `init`"
        )
        let delegateSet = try XCTUnwrap(
            source.range(of: "session.delegate = self"),
            "S-10306 the delegate is set in `init`"
        )
        XCTAssertLessThan(
            laneBuilt.lowerBound, delegateSet.lowerBound,
            "S-10306 the lane is built before `session.delegate = self`, so no "
                + "arrival can reach a lane that does not exist yet"
        )
    }

    // MARK: - S-10307 the bridge stores the handler before it opens the gate

    /// `onIncoming` stores `inbound` first, then opens the gate: the first
    /// frame the gate hands over already finds its handler (plan 73 D-3).
    func testS10307TheBridgeStoresTheHandlerBeforeItOpensTheGate() throws {
        let source = try engineSource("WatchConnectivityBridge.swift")

        let onIncoming = try XCTUnwrap(
            source.range(of: "public func onIncoming("),
            "S-10307 the bridge has an `onIncoming`"
        )
        let bodyEnd = try XCTUnwrap(
            source.range(
                of: "public func onReachabilityChange(",
                options: .literal,
                range: onIncoming.lowerBound..<source.endIndex
            ),
            "S-10307 `onIncoming` is followed by the next member"
        )
        let body = String(source[onIncoming.lowerBound..<bodyEnd.lowerBound])

        let stored = try XCTUnwrap(
            body.range(of: "inbound = handler", options: .literal),
            "S-10307 `onIncoming` stores the handler"
        )
        let opened = try XCTUnwrap(
            body.range(of: "session.openInbound()", options: .literal),
            "S-10307 `onIncoming` opens the gate"
        )
        XCTAssertLessThan(
            stored.lowerBound, opened.lowerBound,
            "S-10307 the handler is stored before the gate is opened, so the "
                + "first drained frame already finds its handler"
        )
    }

    // MARK: - S-9315 the engine refuses a stale snapshot

    /// The stale rule sits right after the snapshot's own guard, before any
    /// entry is stored or any tombstone cleared. Without it the wearer would
    /// stop getting the protection that a late-arriving older state changes
    /// nothing — not even an entry the phone deleted since.
    func testS9315TheEngineRefusesASnapshotOlderThanTheNewestApplied() throws {
        let source = try engineSource("WatchSessionEngine.swift")

        XCTAssertTrue(
            source.contains("if let newest = newestSnapshotAt, sentAt < newest { return nil }"),
            "S-9315 the stale rule refuses the snapshot whole, so the wearer "
                + "keeps getting the protection that an older state arriving late "
                + "changes nothing, not even an entry or a tombstone"
        )
    }
}
