//
//  WatchRestAdvanceTests.swift
//  WatchSessionEngineTests
//
//  Plan 79, phase P1: the rest screen's Next opens the exercise the next line
//  announces (D-6, D-7). S-9108 goes through the real engine, the menu and
//  `WatchLoggingState`; S-9109 holds the source order the view is compiled
//  from, the way `WatchPagerSourceTests` holds the pager's shape.
//
//  The harness below is the `PagerHarness` of `WatchPagerModelTests.swift`
//  (engine, start paths, preferences, rating, menu over one store, with the
//  engine's `onEmit` capture); the rest is started the way
//  `WatchRestSurfaceTests.swift` starts one, by logging a set.
//

import Foundation
import XCTest

@testable import WatchSessionEngine

/// One slot of the rest-advance fixture ladder, with the plan the line counts.
/// The ids and names are unlike every other fixture's, so a hard-coded id or
/// name cannot pass by accident.
private func advanceSlot(
    _ id: String,
    _ name: String,
    planned: Int = 0
) -> [String: Any] {
    var slot: [String: Any] = [
        "sessionExerciseId": id,
        "exerciseId": "ex-\(id)",
        "name": name,
        "capabilities": ["reps", "sets", "load"],
    ]
    if planned > 0 {
        slot["plannedSets"] = Array(
            repeating: ["reps": 10, "loadKg": 60] as [String: Any],
            count: planned
        )
    }
    return slot
}

/// A wrist with its engine, the menu over it and the frames the engine emitted.
final class RestAdvanceHarness {
    let clock: TestClock
    let store: WatchSessionStore
    let sessionId = "s-rest-advance"

    /// Everything the engine emitted, in order.
    private(set) var emitted: [[String: Any]] = []

    private(set) var engine: WatchSessionEngine!
    private(set) var paths: WatchSessionStartPaths!
    private(set) var preferences: WatchPhonePreferences!
    private(set) var rating: WatchEffortRatingState!
    private(set) var menu: WatchMenuState!

    init(store: WatchSessionStore = InMemoryWatchSessionStore()) {
        clock = TestClock(instant("2026-09-02T07:15:00Z"))
        self.store = store
    }

    /// A wrist that has restored, with the menu over the same objects.
    @discardableResult
    func launch() async -> RestAdvanceHarness {
        var ids = 0
        func nextId(_ prefix: String) -> String {
            ids += 1
            return "\(prefix)-\(ids)"
        }

        engine = WatchSessionEngine(
            store: store,
            onEmit: { [weak self] envelope in self?.emitted.append(envelope) },
            validator: Harness.validator(),
            clock: clock.call,
            idFactory: { nextId("rec") },
            sessionIdFactory: { [sessionId] in sessionId }
        )
        paths = WatchSessionStartPaths(
            engine: engine,
            store: store,
            validator: Harness.validator(),
            clock: clock.call,
            idFactory: { nextId("cat") }
        )
        preferences = WatchPhonePreferences(
            store: store,
            validator: Harness.validator(),
            clock: clock.call
        )
        rating = WatchEffortRatingState(
            engine: engine,
            store: store,
            preferences: preferences,
            clock: clock.call
        )
        menu = WatchMenuState(engine: engine, paths: paths, rating: rating)

        await engine.restore()
        await paths.restore()
        await preferences.restore()
        await rating.restore()
        return self
    }

    /// Forget the frames the fixture wrote, so a test counts its own act.
    func clearEmitted() { emitted.removeAll() }
}

/// Whether the envelope is the session's `exercise_advanced` lifecycle.
private func isAdvancedFrame(_ envelope: [String: Any]) -> Bool {
    guard envelope["type"] as? String == "session_lifecycle" else { return false }
    let payload = (envelope["payload"] as? [String: Any]) ?? [:]
    return payload["state"] as? String == WatchLifecycleState.exerciseAdvanced
}

/// The index of the newest `timer_state` frame carrying a stopped rest, or nil
/// when the frames hold none.
private func restEndedFrameIndex(in frames: [[String: Any]]) -> Int? {
    for (index, envelope) in frames.enumerated().reversed() {
        guard envelope["type"] as? String == "timer_state" else { continue }
        let payload = (envelope["payload"] as? [String: Any]) ?? [:]
        let timers = (payload["timers"] as? [String: Any]) ?? [:]
        let rest = (timers[WatchTimerKind.rest] as? [String: Any]) ?? [:]
        if rest["state"] as? String == WatchTimerState.stopped { return index }
    }
    return nil
}

final class WatchRestAdvanceTests: XCTestCase {

    // MARK: - S-9108 through the engine: the announced id jumps

    func testS9108TheRestsNextJumpsToTheAnnouncedExercise() async throws {
        let harness = await RestAdvanceHarness().launch()
        _ = await harness.engine.createSession(
            modality: nil,
            exercises: [
                advanceSlot("z1", "Zephyr", planned: 2),
                advanceSlot("z2", "Basalt", planned: 3),
                advanceSlot("z3", "Kestrel"),
            ]
        )
        let logging = WatchLoggingState(engine: harness.engine, clock: harness.clock.call)

        // A's two planned sets, each logging into the rest that follows it;
        // the second rest is the one running when the line is read.
        try await logging.log()
        await logging.endRest()
        try await logging.log()
        XCTAssertTrue(logging.isResting, "S-9108 the fixture is resting on the announced line")
        harness.clearEmitted()

        // The order the view's Next is written in (D-7): the target first,
        // then the rest's end, then the jump.
        let target = logging.restLabels.nextSlotId
        await logging.endRest()
        let jumped = await harness.menu.jump(to: try XCTUnwrap(target, "S-9108 the line announces B"))

        XCTAssertEqual(target, "z2", "S-9108 the line announces B's slot id")
        XCTAssertTrue(jumped, "S-9108 the menu takes the announced id")
        XCTAssertFalse(logging.isResting, "S-9108 the rest ended")
        XCTAssertEqual(
            harness.engine.session?.currentExerciseIndex, 1,
            "S-9108 the session is on the exercise the line named"
        )
        XCTAssertEqual(
            harness.engine.currentExercise?["sessionExerciseId"] as? String,
            "z2",
            "S-9108 and that exercise is B"
        )

        // Exactly one advance frame, and it follows the rest's end on the wire.
        let frames = harness.emitted
        let restEndedAt = try XCTUnwrap(
            restEndedFrameIndex(in: frames),
            "S-9108 the rest's end went on the wire"
        )
        let advancesAfter = frames.enumerated().filter { index, envelope in
            index > restEndedAt && isAdvancedFrame(envelope)
        }
        XCTAssertEqual(
            advancesAfter.count, 1,
            "S-9108 one jump is one exercise_advanced after the rest's end"
        )
        let payload = (advancesAfter.first?.element["payload"] as? [String: Any]) ?? [:]
        XCTAssertEqual(
            payload["exerciseIndex"] as? Int, 1,
            "S-9108 the frame names the exercise it landed on"
        )
    }

    // MARK: - S-9109 the source keeps the order

    func testS9109TheNextReadsTheTargetBeforeItEndsTheRest() throws {
        let source = try engineSource("WatchRestView.swift")

        XCTAssertTrue(
            source.contains("state.restLabels.nextSlotId"),
            "S-9109 the Next reads the announced slot"
        )
        XCTAssertTrue(
            source.contains("advance: @escaping (String) async -> Bool"),
            "S-9109 the init takes the advance"
        )
        let target = try XCTUnwrap(
            source.range(of: "state.restLabels.nextSlotId"),
            "S-9109 the target read is in the source"
        )
        let endRest = try XCTUnwrap(
            source.range(of: "await state.endRest()"),
            "S-9109 the rest's end is in the source"
        )
        let advance = try XCTUnwrap(
            source.range(of: "_ = await advance(target)"),
            "S-9109 the jump is in the source"
        )
        XCTAssertLessThan(
            target.lowerBound, endRest.lowerBound,
            "S-9109 the target is read before the rest ends"
        )
        XCTAssertGreaterThan(
            advance.lowerBound, endRest.lowerBound,
            "S-9109 the jump follows the rest's end"
        )

        let app = try appSource("ContentView.swift")
        let body = try XCTUnwrap(
            propertyBody(named: "body", in: app),
            "S-9109 ContentView has a body"
        )
        XCTAssertTrue(
            body.contains("advance: { await menuState.jump(to: $0) }"),
            "S-9109 the rest branch passes the menu's jump as the advance"
        )
    }

    // MARK: - Helpers (the source guard, as WatchPagerSourceTests reads files)

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

    /// The brace-balanced body of the property `var <name>:`, from its opening
    /// brace to its closing one, or nil when the property is not there.
    private func propertyBody(named name: String, in source: String) -> String? {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0.contains("var \(name):") }) else {
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
            if started, depth == 0 { return body.joined(separator: "\n") }
        }
        return nil
    }
}
