//
//  WatchRouteSourceTests.swift
//  WatchSessionEngineTests
//
//  Source guards for the app target's route code: the store's one
//  authorization request, the live route builder, the end() ordering, the
//  keeper's answer, the raw source's rich fields, the permission sentence and
//  the recovered workout's best-effort route finish.
//
//  Plan: `docs/plans/2026-10-24-68-run-route-map-plan/2026-10-24-68-run-route-map-plan.md`,
//  scenarios S-9817 to S-9822 (decisions D-6 to D-9, D-16).
//
//  The app target has no test target and HealthKit's route types do not exist
//  on macOS where `swift test` runs, so the store, the recorder and the raw
//  source cannot be executed here. What can be held off-device is what drift
//  would break: the exact statements these files must keep. The on-device
//  behaviour is the owner's check.
//
//  Every guard reads a file's text with its comment lines removed, so a
//  sentence of prose can neither satisfy a guard nor trip one.
//

import Foundation
import XCTest

final class WatchRouteSourceTests: XCTestCase {

    // MARK: - Reading the app target

    /// A file of the app target, read from the repository root, with every
    /// comment-only line blanked out (the line count is kept).
    private func source(_ name: String) throws -> String {
        let url = Fixtures.repositoryRoot
            .appendingPathComponent("ios/OmniTrain Watch App/\(name)")
        let text = try String(contentsOf: url, encoding: .utf8)
        return strippingCommentLines(text)
    }

    private func storeSource() throws -> String { try source("HealthKitWorkoutStore.swift") }

    private func recorderSource() throws -> String { try source("HealthKitRouteRecorder.swift") }

    private func rawSourceSource() throws -> String { try source("CoreLocationRawSource.swift") }

    /// The Xcode project file, read as text: the permission sentence lives in
    /// the watch target's three build configurations (D-16).
    private func projectFileSource() throws -> String {
        let url = Fixtures.repositoryRoot
            .appendingPathComponent("ios/Runner.xcodeproj/project.pbxproj")
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Matching helpers

    /// Blanks every line whose trimmed text starts with `//`, keeping the line
    /// boundaries so line indexes stay true. A trailing `//` comment on a code
    /// line is blanked too, so prose there can neither satisfy a guard nor trip
    /// one; none of the guarded files keeps a `//` inside a string literal
    /// (checked 2026-10-24).
    private func strippingCommentLines(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { return "" }
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    /// The number of the first line containing `needle`, or nil.
    private func lineIndex(of needle: String, in source: String) -> Int? {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.firstIndex { $0.contains(needle) }
    }

    /// The number of the last line containing `needle`, or nil.
    private func lastLineIndex(of needle: String, in source: String) -> Int? {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.lastIndex { $0.contains(needle) }
    }

    /// The brace-balanced body of `func <name>(`, from its opening brace to its
    /// closing one, or nil when the function is not there.
    private func functionBody(named name: String, in source: String) -> String? {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0.contains("func \(name)(") }) else {
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
            if started && depth == 0 { break }
        }
        return started ? body.joined(separator: "\n") : nil
    }

    /// The brace-balanced body of the one function whose body contains `needle`,
    /// found by walking back from `needle` to the nearest `func` line, or nil when
    /// either the needle or that line is not there.
    private func functionBody(containing needle: String, in source: String) -> String? {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let hit = lines.firstIndex(where: { $0.contains(needle) }),
              let start = lines[..<hit].lastIndex(where: { $0.contains("func ") }),
              let keyword = lines[start].range(of: "func "),
              let paren = lines[start][keyword.upperBound...].firstIndex(of: "(")
        else { return nil }

        return functionBody(
            named: String(lines[start][keyword.upperBound..<paren]),
            in: source
        )
    }

    /// The parenthesised argument text of the first call to `needle`, braces and
    /// parens balanced, or nil when the call is not there.
    private func arguments(of needle: String, in source: String) -> String? {
        guard let call = source.range(of: needle) else { return nil }

        var depth = 0
        var started = false
        var collected = ""
        for character in source[call.upperBound...] {
            if character == "(" {
                depth += 1
                started = true
                if depth == 1 { continue }
            } else if character == ")" {
                depth -= 1
                if depth == 0 { break }
            }
            if started { collected.append(character) }
        }
        return started ? collected : nil
    }

    // MARK: - S-9817 (D-7): the one request carries the route

    func testS9817TheOneRequestCarriesTheRoute() throws {
        let store = try storeSource()
        let request = try XCTUnwrap(
            arguments(of: "requestAuthorization", in: store),
            "S-9817/D-7: the store's one requestAuthorization call is gone"
        )
        let parts = request.components(separatedBy: "read:")
        XCTAssertEqual(
            parts.count, 2,
            "S-9817/D-7: the one requestAuthorization must carry exactly one read: list"
        )
        let share = parts[0]
        let read = parts[1]
        XCTAssertTrue(
            share.contains("HKSeriesType.workoutRoute()"),
            "S-9817/D-7: the share list must contain HKSeriesType.workoutRoute()"
        )
        XCTAssertTrue(
            share.contains("HKObjectType.workoutType()"),
            "S-9817/D-7: the share list must keep HKObjectType.workoutType()"
        )
        XCTAssertTrue(
            read.contains("HKSeriesType.workoutRoute()"),
            "S-9817/D-7: the read list must contain HKSeriesType.workoutRoute()"
        )
        XCTAssertTrue(
            read.contains("HKObjectType.workoutType()"),
            "S-9817/D-7: the read list must contain HKObjectType.workoutType()"
        )
    }

    // MARK: - S-9818 (D-8): the route builder comes from the live builder

    func testS9818TheRouteBuilderComesFromTheLiveBuilder() throws {
        let store = try storeSource()
        let recorder = try recorderSource()
        XCTAssertTrue(
            store.contains("authorizationStatus(for: HKSeriesType.workoutRoute())"),
            "S-9818/D-1: the store must read the route share status with authorizationStatus(for: HKSeriesType.workoutRoute())"
        )
        XCTAssertTrue(
            recorder.contains("seriesBuilder(for: HKSeriesType.workoutRoute())"),
            "S-9818/D-8: the recorder must take the route builder from seriesBuilder(for: HKSeriesType.workoutRoute())"
        )
        XCTAssertFalse(
            store.contains("HKWorkoutRouteBuilder(healthStore:"),
            "S-9818/D-8/F-2: the store must never construct HKWorkoutRouteBuilder(healthStore:"
        )
        XCTAssertFalse(
            recorder.contains("HKWorkoutRouteBuilder(healthStore:"),
            "S-9818/D-8/F-2: the recorder must never construct HKWorkoutRouteBuilder(healthStore:"
        )
    }

    // MARK: - S-9819 (D-6): the workout is saved before the route is finished

    func testS9819TheWorkoutIsSavedBeforeTheRouteIsFinished() throws {
        let store = try storeSource()
        let recorder = try recorderSource()
        let end = try XCTUnwrap(
            functionBody(named: "end", in: store),
            "S-9819/D-6: the store's end() is gone"
        )
        let close = try XCTUnwrap(
            lineIndex(of: "routeRecorder.close()", in: end),
            "S-9819/D-6: end() must close the route first with routeRecorder.close()"
        )
        let sessionEnd = try XCTUnwrap(
            lineIndex(of: "openSession.end()", in: end),
            "S-9819/D-6: end() must close the session with openSession.end()"
        )
        let finishWorkout = try XCTUnwrap(
            lineIndex(of: "finishWorkout()", in: end),
            "S-9819/D-6: end() must finish the workout with finishWorkout()"
        )
        // Exactly two `routeRecorder.finish(` calls: the first inside the
        // no-builder guard, the second the saved-workout branch after
        // `finishWorkout()`. A third, earlier call would discard the route
        // builder and make the later finish call a discarded builder.
        let finishCount = end.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.contains("routeRecorder.finish(") }
            .count
        XCTAssertEqual(
            finishCount, 2,
            "S-9819/D-6: end() must contain exactly two routeRecorder.finish( calls"
        )
        let guardOpenBuilder = try XCTUnwrap(
            lineIndex(of: "guard let openBuilder else", in: end),
            "S-9819/D-6: end() must guard the route builder with guard let openBuilder else"
        )
        let endCollection = try XCTUnwrap(
            lineIndex(of: "endCollection(at:", in: end),
            "S-9819/D-6: end() must end the collection"
        )
        let firstFinish = try XCTUnwrap(
            lineIndex(of: "routeRecorder.finish(", in: end),
            "S-9819/D-6: end() must finish the route with routeRecorder.finish("
        )
        // The last `routeRecorder.finish(` is the saved-workout branch; the
        // first one is the no-builder branch, which legitimately precedes
        // `finishWorkout()`.
        let routeFinish = try XCTUnwrap(
            lastLineIndex(of: "routeRecorder.finish(", in: end),
            "S-9819/D-6: end() must finish the route with routeRecorder.finish("
        )
        XCTAssertLessThan(
            close, sessionEnd,
            "S-9819/D-6: routeRecorder.close() must come before openSession.end()"
        )
        XCTAssertLessThan(
            sessionEnd, finishWorkout,
            "S-9819/D-6: openSession.end() must come before finishWorkout()"
        )
        XCTAssertGreaterThan(
            firstFinish, guardOpenBuilder,
            "S-9819/D-6: the first routeRecorder.finish( must lie inside the guard let openBuilder else block"
        )
        XCTAssertLessThan(
            firstFinish, endCollection,
            "S-9819/D-6: the first routeRecorder.finish( must come before endCollection(at:"
        )
        XCTAssertGreaterThan(
            routeFinish, finishWorkout,
            "S-9819/D-6: the second routeRecorder.finish( must come after finishWorkout()"
        )
        XCTAssertLessThan(
            finishWorkout, routeFinish,
            "S-9819/D-6: finishWorkout() must come before routeRecorder.finish("
        )
        XCTAssertTrue(
            recorder.contains("finishRoute(with:"),
            "S-9819/D-6: the recorder must finish the route with finishRoute(with:"
        )
        XCTAssertTrue(
            recorder.contains("discard()"),
            "S-9819/D-6: the recorder must be able to discard() the route"
        )
        XCTAssertTrue(
            recorder.contains("insertRouteData"),
            "S-9819/D-6: the recorder must insert the remainder with insertRouteData"
        )
        let finish = try XCTUnwrap(
            functionBody(named: "finish", in: recorder),
            "S-9819/D-6: the recorder's finish(_:workout:) is gone"
        )
        let discard = try XCTUnwrap(
            lineIndex(of: "discard()", in: finish),
            "S-9819/D-6: the recorder's finish must discard() when there is no workout"
        )
        let insert = try XCTUnwrap(
            lineIndex(of: "insertRouteData", in: finish),
            "S-9819/D-6: the recorder's finish must insert the remainder"
        )
        let finishRoute = try XCTUnwrap(
            lineIndex(of: "finishRoute(with:", in: finish),
            "S-9819/D-6: the recorder's finish must call finishRoute(with:"
        )
        XCTAssertLessThan(
            discard, insert,
            "S-9819/D-6: discard() must come before insertRouteData in the recorder's finish"
        )
        XCTAssertLessThan(
            insert, finishRoute,
            "S-9819/D-6: insertRouteData must come before finishRoute(with: in the recorder's finish"
        )
    }

    // MARK: - S-9820 (D-1): the route opens only on the keeper's answer

    func testS9820TheRouteOpensOnlyOnTheKeepersAnswer() throws {
        let store = try storeSource()
        let openRoute = try XCTUnwrap(
            functionBody(named: "openRoute", in: store),
            "S-9820/D-1: the store's openRoute is gone"
        )
        XCTAssertTrue(
            openRoute.contains("routeRecorder.open("),
            "S-9820/D-1: openRoute must open the keeper with routeRecorder.open("
        )
        // Plan 76 D-1 (S-10606): route sharing alone decides, so the store hands the
        // keeper neither the outdoors verdict nor the activity name.
        XCTAssertTrue(
            openRoute.contains("routeSharingAllowed: sharing"),
            "S-10606: openRoute must hand the route-sharing answer to the keeper"
        )
        XCTAssertFalse(
            openRoute.contains("outdoors:"),
            "S-10606: openRoute must not hand the outdoors verdict to the keeper"
        )
        XCTAssertFalse(
            openRoute.contains("activityName"),
            "S-10606: openRoute must not hand the activity name to the keeper"
        )
        XCTAssertTrue(
            openRoute.contains("location.observeFixes"),
            "S-9820: openRoute must set the tracked location's observer once"
        )
        let lines = store.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertFalse(
            lines.contains { $0.contains("== \"running\"") },
            "S-9820/D-1: the running-name rule lives in the package, not in the store"
        )
        let begin = try XCTUnwrap(
            functionBody(containing: "openRoute(on: collection", in: store),
            "S-9820/D-1: the store's outdoors begin body that opens the route is gone"
        )
        let beginCollection = try XCTUnwrap(
            lineIndex(of: "beginCollection(at:", in: begin),
            "S-9820/D-8: the begin body must begin the collection first"
        )
        let routeOpen = try XCTUnwrap(
            lineIndex(of: "openRoute(on: collection", in: begin),
            "S-9820/D-1: the begin body must open the route"
        )
        XCTAssertLessThan(
            beginCollection, routeOpen,
            "S-9820/D-8: the route opens only after beginCollection succeeds"
        )
    }

    // MARK: - S-10606 (plan 76 D-1): route sharing alone decides

    func testS10606RouteSharingAloneDecidesWhetherARouteRecords() throws {
        let keeperURL = Fixtures.repositoryRoot
            .appendingPathComponent("watch/watchos/Sources/WatchSessionEngine/WatchRouteKeeper.swift")
        let keeper = try String(contentsOf: keeperURL, encoding: .utf8)
        XCTAssertTrue(
            keeper.contains("        recording = routeSharingAllowed\n"),
            "S-10606: the keeper records when route sharing is allowed, and for no other reason"
        )
        XCTAssertFalse(
            keeper.contains("activityName == \"running\""),
            "S-10606: the running-name rule is gone from the keeper"
        )
        XCTAssertFalse(
            keeper.contains("outdoors &&"),
            "S-10606: the outdoors rule is gone from the keeper"
        )

        let recorder = try recorderSource()
        XCTAssertFalse(
            recorder.contains("outdoors") || recorder.contains("activityName"),
            "S-10606: the recorder hands the keeper neither the outdoors verdict nor the activity name"
        )

        let store = try storeSource()
        XCTAssertTrue(
            store.contains("openRoute(on: collection, startedAt: startDate)"),
            "S-10606: begin opens the route for every workout it registers"
        )
        XCTAssertTrue(
            store.contains("configuration.locationType = outdoors ? .outdoor : .unknown"),
            "S-10606: the outdoors verdict still sets the workout's location type"
        )
    }

    // MARK: - S-9821 (D-16): the raw source's rich fields and the sentence

    func testS9821TheRawSourceCarriesTheRichFieldsAndThePermissionSentenceNamesTheRoute() throws {
        let raw = try rawSourceSource()
        for field in ["location.altitude", "location.verticalAccuracy",
                      "location.speed", "location.course"] {
            XCTAssertTrue(
                raw.contains(field),
                "S-9821: the raw source must read \(field)"
            )
        }
        let project = try projectFileSource()
        let lines = project.split(separator: "\n", omittingEmptySubsequences: false)
        let sentenceLines = lines.filter { $0.contains("INFOPLIST_KEY_NSHealthUpdateUsageDescription") }
        XCTAssertEqual(
            sentenceLines.count, 3,
            "S-9821/D-16: the watch target's three build configurations must each carry the permission sentence"
        )
        for line in sentenceLines {
            XCTAssertTrue(
                line.contains("with the route of an outdoor run"),
                "S-9821/D-16: the permission sentence must name the route of an outdoor run"
            )
        }
    }

    // MARK: - S-9822 (D-9): the recovered workout's route is finished best effort

    func testS9822TheRecoveredWorkoutsRouteIsFinishedBestEffort() throws {
        let store = try storeSource()
        let recorder = try recorderSource()
        let end = try XCTUnwrap(
            functionBody(named: "end", in: store),
            "S-9822/D-9: the store's end() is gone"
        )
        let recovered = try XCTUnwrap(
            lineIndex(of: "recoveredBuilder(from:", in: end),
            "S-9822/D-9: end() must ask the recovered builder for its route builder"
        )
        let endCollection = try XCTUnwrap(
            lineIndex(of: "endCollection(at:", in: end),
            "S-9822/D-9: end() must end the collection"
        )
        let finishWorkout = try XCTUnwrap(
            lineIndex(of: "finishWorkout()", in: end),
            "S-9822/D-9: end() must finish the workout"
        )
        let finishRecovered = try XCTUnwrap(
            lineIndex(of: "finishRecovered(", in: end),
            "S-9822/D-9: end() must finish the recovered route"
        )
        XCTAssertLessThan(
            recovered, endCollection,
            "S-9822/D-9: recoveredBuilder(from:) must come before endCollection(at:"
        )
        XCTAssertLessThan(
            finishWorkout, finishRecovered,
            "S-9822/D-9: finishRecovered( must come after finishWorkout()"
        )
        let inProgress = try XCTUnwrap(
            functionBody(named: "inProgressActivityTypes", in: store),
            "S-9822/D-9: the store's inProgressActivityTypes() is gone"
        )
        XCTAssertTrue(
            inProgress.contains("recoveredSession = true"),
            "S-9822/D-9: inProgressActivityTypes must mark the recovered session"
        )
        let finishRecoveredBody = try XCTUnwrap(
            functionBody(named: "finishRecovered", in: recorder),
            "S-9822/D-9: the recorder's finishRecovered is gone"
        )
        XCTAssertTrue(
            finishRecoveredBody.contains("try?"),
            "S-9822/D-9: the recovered route's finish is best effort: it must be swallowed with try?"
        )
    }

    // MARK: - S-9818 negative: no second subscription

    func testS9818ANoSecondSubscription() throws {
        let store = try storeSource()
        let recorder = try recorderSource()
        for source in [store, recorder] {
            for needle in ["startUpdatingLocation", "rawFixes()", "CLLocationManager"] {
                XCTAssertFalse(
                    source.contains(needle),
                    "S-9818: neither the recorder nor the store may contain \(needle)"
                )
            }
        }
        XCTAssertTrue(
            recorder.contains("@preconcurrency import CoreLocation"),
            "S-9818: the recorder keeps its @preconcurrency import CoreLocation"
        )
        XCTAssertFalse(
            recorder.contains("\nimport CoreLocation"),
            "S-9818: the recorder must not add a plain import CoreLocation"
        )
    }
}
