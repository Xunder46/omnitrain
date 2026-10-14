//
//  WatchSensorSourceSourceTests.swift
//  WatchSessionEngineTests
//
//  Source guards for the app target's live sensor side and its host wiring.
//
//  Plan: `docs/plans/2026-10-10-19d-watch-heart-rate-and-steps-plan/2026-10-10-19d-watch-heart-rate-and-steps-plan.md`,
//  scenarios S-3109, S-3110, S-3114, S-3116 and S-3117 (decisions D-2103,
//  D-2104, D-2105, D-2106, D-2113).
//
//  Plan: `docs/plans/2026-10-10-19f-watch-gps-feed-plan/2026-10-10-19f-watch-gps-feed-plan.md`,
//  scenarios S-3310 to S-3318 (decisions D-2303 to D-2307): the CoreLocation
//  raw source, the feed's delegation to the location adapter, the store's
//  outdoor-aware `begin`, the host's one construction, the permission sentence in
//  the project file, the question that is never latched, and the revoked
//  permission that ends the feed.
//
//  Plan: `docs/plans/2026-10-13-31-watch-qa-fixes-3-plan/2026-10-13-31-watch-qa-fixes-3-plan.md`,
//  scenarios S-3110 and S-3112 (decisions D-3108, D-3113): the feed's pull that
//  re-reads the builder's newest beat while a listener waits and stops with the
//  last one, and the store and the host refreshing it when the app becomes
//  active.
//
//  The app target has no test target and `HKLiveWorkoutBuilder` does not exist on
//  macOS where `swift test` runs, so the feed, the store and the host cannot be
//  executed here. What can be held off-device is what drift would break: the
//  feed's shape and its one-authorization rule, the store's read set, the raw
//  source's shape and its negatives, the host's build order, and that the workout
//  is refreshed before the sensors. The on-device behaviour is the owner's check.
//
//  Every guard reads a file's text with its comment lines removed, so a sentence
//  of prose can neither satisfy a guard nor trip one.
//

import Foundation
import XCTest

final class WatchSensorSourceSourceTests: XCTestCase {

    // MARK: - Reading the app target

    /// A file of the app target, read from the repository root, with every
    /// comment-only line blanked out (the line count is kept).
    private func source(_ name: String) throws -> String {
        let url = Fixtures.repositoryRoot
            .appendingPathComponent("ios/OmniTrain Watch App/\(name)")
        let text = try String(contentsOf: url, encoding: .utf8)
        return strippingCommentLines(text)
    }

    private func feedSource() throws -> String { try source("HealthKitSensorFeed.swift") }

    private func storeSource() throws -> String { try source("HealthKitWorkoutStore.swift") }

    private func rawSourceSource() throws -> String { try source("CoreLocationRawSource.swift") }

    private func viewSource() throws -> String { try source("ContentView.swift") }

    /// The Xcode project file, read as text: the location permission sentence
    /// lives in the watch target's three build configurations (D-2306).
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
    /// (checked 2026-10-10).
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

    /// The brace-balanced body of `func <name>(`, from its opening brace to its
    /// closing one, or nil when the function is not there. `return` is not
    /// required: a one-expression body is exactly the shape the short probes use.
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

    /// The number of times `needle` occurs in `source`.
    private func occurrences(of needle: String, in source: String) -> Int {
        source.components(separatedBy: needle).count - 1
    }

    /// The brace-balanced body of the first line containing `needle`, from its
    /// opening brace to its closing one, or nil when that line is not there. For
    /// declarations `functionBody(named:)` cannot reach: `override init()` is not
    /// a `func`.
    private func braceBody(ofLineContaining needle: String, in source: String) -> String? {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
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
            if started && depth == 0 { break }
        }
        return started ? body.joined(separator: "\n") : nil
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

    /// The `$revision` subscription, from its declaration to its `store(in:)`.
    private func revisionSink(in source: String) -> String? {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        guard let start = lines.firstIndex(where: { $0.contains("$revision") }) else {
            return nil
        }

        var collected: [String] = []
        for line in lines[start...] {
            collected.append(String(line))
            if line.contains(".store(in:") { break }
        }
        return collected.joined(separator: "\n")
    }

    // MARK: - S-3109: the feed is the real source and the store asks for both reads

    func testS3109TheFeedIsTheRealSourceAndTheStoreReadsBothTypes() throws {
        let feed = try feedSource()

        XCTAssertTrue(
            feed.contains("WatchSensorSource"),
            "the feed has to be the package's `WatchSensorSource`, not a lookalike (D-2103)"
        )
        XCTAssertTrue(
            feed.contains("HKLiveWorkoutBuilderDelegate"),
            "the feed is fed by the builder's delegate callbacks (D-2103)"
        )
        XCTAssertTrue(
            feed.contains("HKQuantityType(.heartRate)"),
            "the feed reduces heart rate samples and nothing else (D-2103)"
        )
        XCTAssertTrue(
            feed.contains("HKQuantityType(.stepCount)"),
            "the feed reduces step samples and nothing else (D-2103)"
        )
        XCTAssertFalse(
            feed.contains("import CoreLocation"),
            "the feed is handed a location adapter instead of owning a radio: a "
                + "feed that imports no location framework cannot leak one (D-2304)"
        )

        let locationBody = try XCTUnwrap(
            functionBody(named: "locationPermission", in: feed),
            "the feed has to answer the location probe (D-2304)"
        )
        XCTAssertTrue(
            locationBody.contains("trackedLocation.permission()"),
            "the probe is the adapter's answer, unchanged: the feed delegates "
                + "location to the CoreLocation source and decides nothing itself (D-2304, D-2307)"
        )
        XCTAssertFalse(
            locationBody.contains(".unavailable"),
            "the feed reports no permission of its own any more: whether location "
                + "is granted, refused or unavailable is the adapter's to say (D-2304, D-2307)"
        )
        XCTAssertFalse(
            locationBody.contains(".granted"),
            "the location probe never claims a permission it does not ask for (D-2304)"
        )

        let store = try storeSource()
        let request = try XCTUnwrap(
            arguments(of: "requestAuthorization", in: store),
            "the store asks for authorization in one request (D-1503)"
        )
        let readParts = request.components(separatedBy: "read:")
        XCTAssertEqual(
            readParts.count,
            2,
            "the request carries exactly one read list (D-2105)"
        )
        let readList = readParts[1]
        XCTAssertTrue(
            readList.contains("HKQuantityType(.heartRate)"),
            "a read left out of the one request is a stream that never produces "
                + "anything: the builder's statistics only carry what was asked for (D-2103, D-2105)"
        )
        XCTAssertTrue(
            readList.contains("HKQuantityType(.stepCount)"),
            "both read types belong in the same request, so the user sees one "
                + "prompt (D-2105)"
        )
    }

    // MARK: - S-3110: the host wires the sensors and refreshes the workout first

    func testS3110TheHostWiresTheSensorsAndRefreshesTheWorkoutFirst() throws {
        let view = try viewSource()

        XCTAssertTrue(
            view.contains("WatchLoggingState(engine: engine, sensors:"),
            "the logging surface reads the live sensors, so the host hands it the "
                + "recorder it built (D-2106)"
        )
        XCTAssertTrue(
            view.contains("WatchSensorCoordinator("),
            "the host follows the session with a sensor coordinator (D-2106)"
        )
        XCTAssertTrue(
            view.contains("source: healthStore.sensorSource"),
            "the recorder reads the shared store, one authorization outcome: a "
                + "second store would mean a second prompt (D-2106)"
        )
        XCTAssertTrue(
            view.contains("HealthKitWorkoutStore("),
            "the host builds the one shared store (D-2305, D-2307)"
        )
        let construction = try XCTUnwrap(
            arguments(of: "HealthKitWorkoutStore", in: view),
            "the store's construction has to be in the host (D-2305, D-2307)"
        )
        XCTAssertTrue(
            construction.contains("WatchTrackedLocation(source: CoreLocationRawSource())"),
            "the store's location adapter is built here, on the main actor, over "
                + "the real source: the manager only calls back on the thread that created it (D-2303, D-2305)"
        )

        let sink = try XCTUnwrap(
            revisionSink(in: view),
            "the host has a `$revision` subscription that settles the session's "
                + "platform work (D-2106)"
        )
        let workoutLine = try XCTUnwrap(
            lineIndex(of: "self.workout.refresh(", in: sink),
            "the sink refreshes the workout (D-2106)"
        )
        let sensorsLine = try XCTUnwrap(
            lineIndex(of: "self.sensors.refresh(", in: sink),
            "the sink refreshes the sensors (D-2106)"
        )
        XCTAssertLessThan(
            workoutLine,
            sensorsLine,
            "the workout is refreshed first: by the time a subscription starts, the "
                + "builder, the permission outcome and the feed exist (D-2106)"
        )
    }

    // MARK: - S-3114: the feed never opens a prompt of its own

    func testS3114TheFeedNeverPromptsAndAnswersUnavailableWithoutHealthData() throws {
        let feed = try feedSource()

        XCTAssertFalse(
            feed.contains("requestAuthorization"),
            "the feed reports the store's one authorization outcome and never "
                + "opens a second prompt (D-2104)"
        )

        let lines = feed.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let probeLines = lines.enumerated().filter {
            $0.element.contains("HKHealthStore.isHealthDataAvailable()")
        }
        XCTAssertFalse(
            probeLines.isEmpty,
            "the probes ask the platform whether there is health data at all (D-2104)"
        )
        for (index, _) in probeLines {
            let window = lines[index..<min(index + 3, lines.count)].joined(separator: "\n")
            XCTAssertTrue(
                window.contains(".unavailable"),
                "no health data answers `.unavailable`, the first branch of "
                    + "D-2104's rule, on line \(index + 1)"
            )
        }
    }

    // MARK: - S-3116: the feed is nonisolated, so HealthKit may call it off the main actor

    func testS3116TheFeedIsDeclaredNonisolated() throws {
        let feed = try feedSource()
        let lines = feed.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        let declaration = try XCTUnwrap(
            lines.first { $0.contains("HealthKitSensorFeed") && $0.contains("class") },
            "the feed's declaration has to be in the file (D-2103)"
        )
        XCTAssertTrue(
            declaration.contains("nonisolated"),
            "the target's default isolation is the main actor, and HealthKit calls "
                + "the delegate off it: the class has to say `nonisolated` (D-2113)"
        )
        XCTAssertTrue(
            declaration.contains("final class HealthKitSensorFeed"),
            "the declaration is `nonisolated final class HealthKitSensorFeed` (D-2113)"
        )
    }

    // MARK: - S-3117: the store makes its builder collect and hands it the feed

    func testS3117TheStoreMakesTheBuilderCollectAndHandsItTheFeed() throws {
        let store = try storeSource()

        XCTAssertTrue(
            store.contains("collection.delegate = sensorFeed"),
            "without them the builder collects nothing and the feed never fires "
                + "while every suite stays green (D-2105)"
        )
        XCTAssertTrue(
            store.contains(
                "dataSource.enableCollection(for: HKQuantityType(.heartRate), predicate: nil)"
            ),
            "without them the builder collects nothing and the feed never fires "
                + "while every suite stays green (D-2105)"
        )
        XCTAssertTrue(
            store.contains(
                "dataSource.enableCollection(for: HKQuantityType(.stepCount), predicate: nil)"
            ),
            "without them the builder collects nothing and the feed never fires "
                + "while every suite stays green (D-2105)"
        )
    }

    // MARK: - S-3310: the raw source is the only radio, and it asks only WhenInUse

    func testS3310TheRawSourceAsksWhenInUseAndNeverAlways() throws {
        let raw = try rawSourceSource()

        XCTAssertTrue(
            raw.contains("import CoreLocation"),
            "the raw source is the one file that imports CoreLocation (D-2303)"
        )
        XCTAssertTrue(
            raw.contains("nonisolated final class CoreLocationRawSource"),
            "the target's default isolation is the main actor and CoreLocation "
                + "calls its delegates off it, so the class says `nonisolated` (D-2303)"
        )
        XCTAssertTrue(
            raw.contains("WatchRawFixSource"),
            "the class is the package seam's real conformance, not a lookalike (D-2303)"
        )
        XCTAssertTrue(
            raw.contains("CLLocationManagerDelegate"),
            "the fixes and the authorization answer arrive through the manager's delegates (D-2303)"
        )
        XCTAssertTrue(
            raw.contains("requestWhenInUseAuthorization()"),
            "the wrist asks the one question it needs answered (D-2303)"
        )
        XCTAssertTrue(
            raw.contains("kCLLocationAccuracyBest"),
            "the source asks for the best accuracy the wrist can give (D-2303)"
        )
        XCTAssertTrue(
            raw.contains(".fitness"),
            "the manager is configured for the workout's own movement (D-2303)"
        )

        let initBody = try XCTUnwrap(
            braceBody(ofLineContaining: "override init()", in: raw),
            "the manager is created where the host builds the source (D-2303)"
        )
        XCTAssertTrue(
            initBody.contains("CLLocationManager()"),
            "the manager is created in `init`: a manager created lazily from a "
                + "background task never calls back at all (D-2303)"
        )
        XCTAssertTrue(
            initBody.contains("kCLLocationAccuracyBest"),
            "the accuracy is fixed once, inside the init the host's main actor "
                + "runs — not per subscription, where a file-wide probe would "
                + "still find it (D-2303)"
        )
        XCTAssertTrue(
            initBody.contains(".fitness"),
            "the activity type is fixed once, inside the init the host's main "
                + "actor runs — not per subscription, where a file-wide probe "
                + "would still find it (D-2303)"
        )
        XCTAssertEqual(
            occurrences(of: "requestWhenInUseAuthorization()", in: raw),
            1,
            "the question is asked in exactly one place: CoreLocation shows the "
                + "prompt at most once per install, so a second call site — in "
                + "the permission path or anywhere else — would be silently "
                + "dropped and its caller would wait forever (D-2303)"
        )

        XCTAssertFalse(
            raw.contains("requestAlwaysAuthorization"),
            "the workout keeps the app running while a session is on screen, so "
                + "Always is never asked for (D-2303)"
        )
        XCTAssertFalse(
            raw.contains("allowsBackgroundLocationUpdates"),
            "background updates are neither needed nor enabled (D-2303)"
        )
        XCTAssertFalse(
            raw.contains("import HealthKit"),
            "the raw source knows CoreLocation and nothing of the health store (D-2303)"
        )
    }

    // MARK: - S-3311: the feed hands its location members to the adapter

    func testS3311TheFeedDelegatesItsLocationToTheAdapter() throws {
        let feed = try feedSource()

        let permissionBody = try XCTUnwrap(
            functionBody(named: "locationPermission", in: feed),
            "the feed has to answer the location probe (D-2304)"
        )
        XCTAssertTrue(
            permissionBody.contains("trackedLocation.permission()"),
            "the probe is the adapter's answer, unchanged: whether location is "
                + "granted, refused or unavailable is the CoreLocation source's to know (D-2304)"
        )
        XCTAssertFalse(
            permissionBody.contains(".unavailable"),
            "the feed answers no permission of its own: `.unavailable` belongs to "
                + "the source that knows whether location services are on (D-2303, D-2304)"
        )

        let fixesBody = try XCTUnwrap(
            functionBody(named: "location", in: feed),
            "the feed has to carry the wrist's fixes (D-2304)"
        )
        XCTAssertTrue(
            fixesBody.contains("trackedLocation.fixes()"),
            "the wrist's metres are computed in the package, over the stream the "
                + "adapter feeds (D-2304)"
        )

        XCTAssertFalse(
            feed.contains("import CoreLocation"),
            "a feed that owns no radio cannot leak one (D-2304)"
        )
        XCTAssertFalse(
            feed.contains("requestAuthorization"),
            "the feed reports the store's one authorization outcome and never "
                + "opens a second prompt (D-2304)"
        )
    }

    // MARK: - S-3312: the store takes the adapter and registers outdoors

    func testS3312TheStoreTakesTheAdapterAndRegistersOutdoors() throws {
        let store = try storeSource()

        XCTAssertTrue(
            store.contains("init(location: WatchTrackedLocation)"),
            "the store takes the adapter from the host, so the permission question "
                + "and the fixes never pass through it (D-2304)"
        )
        // Scoped to the outdoor-aware begin's own body: the file-wide probe
        // would also find the sentence if it drifted into another function,
        // e.g. a helper only the legacy `begin(_:)` reached.
        let outdoorBeginBody = try XCTUnwrap(
            functionBody(named: "begin", in: store),
            "the store answers the seam's outdoor-aware begin (D-2304)"
        )
        XCTAssertTrue(
            outdoorBeginBody.contains("locationType = outdoors ? .outdoor : .unknown"),
            "the outdoor answer is applied inside the outdoor-aware begin itself: "
                + "a modality that measures distance registers as `.outdoor`, every "
                + "other one keeps the platform default (D-2304)"
        )
        XCTAssertTrue(
            store.contains("func begin(_ activityType: String, outdoors: Bool)"),
            "the store answers the seam's outdoor-aware begin (D-2304)"
        )
    }

    // MARK: - S-3313: the host builds the source and the adapter exactly once

    func testS3313TheHostBuildsTheSourceAndTheAdapterOnce() throws {
        let view = try viewSource()

        XCTAssertEqual(
            occurrences(of: "CoreLocationRawSource()", in: view),
            1,
            "one raw source for the app: a second `CLLocationManager` is a second "
                + "delegate set and a second radio (D-2305)"
        )
        XCTAssertEqual(
            occurrences(of: "WatchTrackedLocation(source:", in: view),
            1,
            "one adapter over that source, and it is the one the store hands to its "
                + "feed (D-2305)"
        )
    }

    // MARK: - S-3314: the permission sentence is on all three watch configurations

    func testS3314TheWatchTargetAsksForLocationInOneSentenceAndNeverAlways() throws {
        let project = try projectFileSource()
        let lines = project.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        let sentence = "INFOPLIST_KEY_NSLocationWhenInUseUsageDescription = "
            + "\"OmniTrain uses your location during runs and sports to measure "
            + "distance and pace.\""
        let sentenceLines = lines.filter { $0.contains(sentence) }
        XCTAssertEqual(
            sentenceLines.count,
            3,
            "the watch target's Debug, Release and Profile configurations each "
                + "carry the owner-approved sentence (D-2306)"
        )

        let alwaysLines = lines.filter { $0.contains("NSLocationAlways") }
        XCTAssertTrue(
            alwaysLines.isEmpty,
            "Always is never asked for, so no Always key may exist (D-2303, D-2306): "
                + alwaysLines.joined(separator: " | ")
        )
    }

    // MARK: - S-3315: location off answers unavailable before any status is read

    func testS3315LocationOffAnswersUnavailableBeforeAnyStatusIsRead() throws {
        let raw = try rawSourceSource()
        let body = try XCTUnwrap(
            functionBody(named: "permission", in: raw),
            "the source has to answer the permission question (D-2303)"
        )

        let services = try XCTUnwrap(
            body.range(of: "CLLocationManager.locationServicesEnabled()"),
            "the source asks the platform whether location services are on at all (D-2303)"
        )
        let unavailable = try XCTUnwrap(
            body.range(of: ".unavailable"),
            "with location services off there is nothing to measure, so the answer "
                + "is `.unavailable` (D-2303)"
        )
        let status = try XCTUnwrap(
            body.range(of: "authorizationStatus"),
            "the source reads the manager's status (D-2303)"
        )

        let unavailableOffset = body.distance(from: body.startIndex, to: unavailable.lowerBound)
        let statusOffset = body.distance(from: body.startIndex, to: status.lowerBound)
        XCTAssertGreaterThan(
            unavailableOffset,
            body.distance(from: body.startIndex, to: services.lowerBound),
            "the off-answer sits after the probe that decides it (D-2303)"
        )
        XCTAssertLessThan(
            unavailableOffset,
            statusOffset,
            "the `.unavailable` branch is taken before the status is ever read: a "
                + "prompt that can never be delivered would park the caller forever "
                + "(offsets \(unavailableOffset) < \(statusOffset), D-2303)"
        )
    }

    // MARK: - S-3316: the radio lives exactly as long as a subscriber

    func testS3316TheRadioFollowsTheSubscribersOnTheMainQueue() throws {
        let raw = try rawSourceSource()
        let body = try XCTUnwrap(
            functionBody(named: "rawFixes", in: raw),
            "the source has to hand out the manager's fixes (D-2303)"
        )

        let asyncOffsets = offsets(of: "DispatchQueue.main.async", in: body)
        XCTAssertGreaterThanOrEqual(
            asyncOffsets.count,
            2,
            "starting and stopping the radio each go to the main queue, where the "
                + "manager was built and calls back (D-2303)"
        )

        for call in ["startUpdatingLocation()", "stopUpdatingLocation()"] {
            XCTAssertTrue(
                body.contains(call),
                "the radio is switched with \(call) (D-2303)"
            )
            let callOffset = try XCTUnwrap(
                offsets(of: call, in: body).first,
                "the radio is switched with \(call) (D-2303)"
            )
            let wrapper = try XCTUnwrap(
                asyncOffsets.last(where: { $0 < callOffset }),
                "\(call) is dispatched to the main queue rather than called from "
                    + "wherever the subscriber happens to be (D-2303)"
            )
            let wrapperIndex = body.index(body.startIndex, offsetBy: wrapper)
            let callIndex = body.index(body.startIndex, offsetBy: callOffset)
            let between = body[wrapperIndex..<callIndex]
            XCTAssertFalse(
                between.contains("}"),
                "\(call) sits inside the `DispatchQueue.main.async` block that "
                    + "precedes it, not after it closed (D-2303)"
            )
        }
    }

    // MARK: - S-3317: the ask is never latched

    func testS3317TheAskIsNeverLatched() throws {
        let raw = try rawSourceSource()

        XCTAssertFalse(
            raw.contains("hasRequestedAuthorization"),
            "the ask is never latched: CoreLocation drops a request only while a "
                + "prompt is already up (and re-prompts after a temporary grant "
                + "lapses), so a latch would park the second session's caller — and "
                + "the serial sensors behind it — for the life of the process (D-2303)"
        )

        let body = try XCTUnwrap(
            functionBody(containing: "requestWhenInUseAuthorization()", in: raw),
            "the ask has to be dispatched to the main queue (D-2303)"
        )

        let recheck = try XCTUnwrap(
            body.range(of: "authorizationStatus"),
            "the asker re-reads the status after registering its waiter: the "
                + "answer can settle in that window, and the delegate then fires "
                + "with no waiter registered, which would park the caller forever (D-2303)"
        )
        let removeOwn = try XCTUnwrap(
            body.range(of: "permissionWaiters.removeValue(forKey:"),
            "the re-check removes this waiter only, so the delegate cannot also "
                + "resume a continuation that has already been answered (D-2303)"
        )
        let ask = try XCTUnwrap(
            body.range(of: "requestWhenInUseAuthorization()"),
            "the ask is dispatched to the main queue (D-2303)"
        )

        let recheckOffset = body.distance(from: body.startIndex, to: recheck.lowerBound)
        let removeOffset = body.distance(from: body.startIndex, to: removeOwn.lowerBound)
        let askOffset = body.distance(from: body.startIndex, to: ask.lowerBound)
        XCTAssertLessThan(
            recheckOffset,
            askOffset,
            "the status is re-read before the prompt is dispatched, not after it "
                + "(offsets \(recheckOffset) < \(askOffset), D-2303)"
        )
        XCTAssertLessThan(
            removeOffset,
            askOffset,
            "this waiter is removed before the prompt is dispatched, so an "
                + "already-settled status never reaches the ask (offsets "
                + "\(removeOffset) < \(askOffset), D-2303)"
        )

        XCTAssertTrue(
            body.contains("= permissionWaiters.removeValue(forKey"),
            "the re-check keeps what its own removal returned: the removal is "
                + "what decides who resumes the waiter (D-2303)"
        )
        XCTAssertTrue(
            body.contains("?.resume(returning:"),
            "the re-check resumes the continuation it removed — the one the "
                + "removal handed back — and no other (D-2303)"
        )
        XCTAssertFalse(
            body.contains("continuation.resume(returning:"),
            "the re-check never resumes the captured continuation "
                + "unconditionally: the delegate, on the manager's main queue, may "
                + "have removed and resumed this waiter between its registration "
                + "and this re-check, and a second resume traps "
                + "CheckedContinuation (D-2303)"
        )
    }

    // MARK: - S-3318: a revoked permission ends the feed

    func testS3318ARevokedPermissionEndsTheFeed() throws {
        let raw = try rawSourceSource()
        let body = try XCTUnwrap(
            functionBody(named: "locationManagerDidChangeAuthorization", in: raw),
            "the source has to answer the authorization delegate (D-2303)"
        )

        for status in [".denied", ".restricted"] {
            XCTAssertTrue(
                body.contains(status),
                "a revoked permission arrives as \(status) and is handled there: "
                    + "the feed ends instead of going silent (D-2303)"
            )
        }
        XCTAssertTrue(
            body.contains(".finish()"),
            "a revoked permission finishes every live raw-fix continuation: their "
                + "`onTermination` stops the radio, so the distance does not freeze "
                + "with the radio still running (D-2303)"
        )
    }

    // MARK: - S-3110: the feed pulls the newest beat while a listener waits

    func testS3110ATheFeedPullsTheNewestBeatWhileAListenerWaits() throws {
        let feed = try feedSource()

        XCTAssertTrue(
            feed.contains("heartRatePullSeconds"),
            "the builder's callback is missed while the app is suspended with the "
                + "wrist down, so the feed also reads the builder on a tick of its "
                + "own (D-3108, D-3113)"
        )
        XCTAssertTrue(
            feed.contains("TimeInterval = 3"),
            "the tick's period is pinned by name and value — "
                + "`heartRatePullSeconds: TimeInterval = 3` (D-3113)"
        )
        XCTAssertTrue(
            feed.contains("lastHeartRateEnd"),
            "without the last end instant a tick that re-reads a beat already "
                + "stored would store it again (D-3113)"
        )
        XCTAssertTrue(
            feed.contains("mostRecentQuantityDateInterval"),
            "a tick yields only a strictly newer beat, which is what the sample's "
                + "interval answers (D-3108, D-3113)"
        )
        XCTAssertTrue(
            feed.contains("yieldHeartRateIfNewer"),
            "one gate serves both paths, so the push callback and a tick's read "
                + "cannot make two rows of one beat (D-3113)"
        )
        XCTAssertTrue(
            feed.contains("refreshHeartRate(from builder: HKLiveWorkoutBuilder?)"),
            "the feed holds the builder it reads, handed over through this one "
                + "entry point and cleared with nil (D-3113)"
        )

        let listener = try XCTUnwrap(
            functionBody(named: "heartRate", in: feed),
            "the heart-rate subscription is where the pull starts (D-3113)"
        )
        XCTAssertTrue(
            listener.contains("onTermination"),
            "a consumer that stops consuming is how the wrist ends a session's "
                + "subscription (D-2103)"
        )
        XCTAssertTrue(
            listener.contains("forgetHeartRate("),
            "the termination drops the continuation through the one path that "
                + "can also stop the pull (D-3113)"
        )

        let forgetting = try XCTUnwrap(
            functionBody(named: "forgetHeartRate", in: feed),
            "the one path a termination takes (D-3113)"
        )
        XCTAssertTrue(
            forgetting.contains("heartRateContinuations.isEmpty"),
            "the pull stops with the last listener: a tick that outlived its "
                + "session would read a builder that is already closed (D-3113)"
        )
        XCTAssertTrue(
            forgetting.contains("cancel()"),
            "stopping means cancelling the pull's task — no timer outlives the "
                + "workout it read (D-3113)"
        )

        let store = try storeSource()
        let begin = try XCTUnwrap(
            functionBody(named: "begin", in: store),
            "the store opens the workout in `begin` (D-2105)"
        )
        XCTAssertTrue(
            begin.contains("sensorFeed.refreshHeartRate(from: collection)"),
            "the feed can only read the builder it was handed, and only after the "
                + "collection it belongs to has one (D-3113)"
        )
        let end = try XCTUnwrap(
            functionBody(named: "end", in: store),
            "the store closes the workout in `end` (D-1502)"
        )
        XCTAssertTrue(
            end.contains("sensorFeed.refreshHeartRate(from: nil)"),
            "and drops it again, so no tick reads a builder the store has "
                + "finished (D-3113)"
        )
    }

    // MARK: - S-3112: the store and the host refresh the heart rate on activation

    func testS3112ATheStoreAndTheHostRefreshTheHeartRateOnActivation() throws {
        let store = try storeSource()
        let refresher = try XCTUnwrap(
            functionBody(named: "refreshHeartRate", in: store),
            "the store offers the one refresh activation calls (D-3113)"
        )
        XCTAssertTrue(
            refresher.contains("func refreshHeartRate()"),
            "the entry point is `refreshHeartRate()`, no argument: the store "
                + "already holds the builder (D-3113)"
        )
        XCTAssertTrue(
            refresher.contains("sensorFeed.refreshHeartRate(from: builder)"),
            "the refresh reads the builder this store opened, through the feed's "
                + "own gate (D-3113)"
        )

        let view = try viewSource()
        let hostRefresh = try XCTUnwrap(
            functionBody(named: "refreshHeartRate", in: view),
            "the host carries the refresh the surface calls (D-3113)"
        )
        XCTAssertTrue(
            hostRefresh.contains("refreshHeartRate()"),
            "the host's refresh reaches the store it built (D-3113)"
        )

        let activation = try XCTUnwrap(
            braceBody(ofLineContaining: ".onChange(of: scenePhase)", in: view),
            "the surface already reacts to becoming active (D-2106)"
        )
        XCTAssertTrue(
            activation.contains("catchUpOnActivation()"),
            "the refresh joins the branch that already ran on becoming active, "
                + "rather than a second handler (D-3113)"
        )
        XCTAssertTrue(
            activation.contains("refreshHeartRate()"),
            "activation is the wrist's second read: a suspended app missed the "
                + "push path's callbacks while the wrist was down (D-3108, D-3113)"
        )
    }

    /// The character offsets of every occurrence of `needle` in `source`.
    private func offsets(of needle: String, in source: String) -> [Int] {
        var found: [Int] = []
        var searchStart = source.startIndex
        while let range = source.range(of: needle, range: searchStart..<source.endIndex) {
            found.append(source.distance(from: source.startIndex, to: range.lowerBound))
            searchStart = range.upperBound
        }
        return found
    }
}
