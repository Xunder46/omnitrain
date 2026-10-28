//
//  WatchPersonalBestsWiringSourceTests.swift
//  WatchSessionEngineTests
//
//  Source guards for what `swift test` cannot compile: the app target's wiring
//  of the bests holder, and the watchOS-only surface that shows the "New PR"
//  banner. Plan
//  `docs/plans/2026-10-27-87b-wrist-new-pr-detection-and-banner-plan/2026-10-27-87b-wrist-new-pr-detection-and-banner-plan.md`,
//  scenarios S-87b-8 (its structural half), S-87b-14 and S-87b-22 (decisions
//  D-4, D-7, D-8, D-18, D-19).
//
//  The app target has no test target and `WatchLoggingView` compiles only under
//  xcodebuild, so the suite holds the text those two files are made of; the
//  governor's watch app build is the compiler check.
//
//  Every guard reads a file's text with its comment lines removed, so a sentence
//  of prose can neither satisfy a guard nor trip one.
//

import Foundation
import XCTest

final class WatchPersonalBestsWiringSourceTests: XCTestCase {

    /// How many `Timer.scheduledTimer` calls `WatchLoggingView.swift` carried
    /// when the banner was added: none. The banner rides the model's existing
    /// tick, so a new timer here is a cost the plan refuses (D-9).
    private static let viewTimersAtBanner = 0

    // MARK: - Reading the two targets

    private func appSource(_ name: String) throws -> String {
        let url = Fixtures.repositoryRoot
            .appendingPathComponent("ios/OmniTrain Watch App/\(name)")
        let text = try String(contentsOf: url, encoding: .utf8)
        return strippingCommentLines(text)
    }

    private func engineSource(_ name: String) throws -> String {
        let url = Fixtures.sourcesRoot.appendingPathComponent(name)
        let text = try String(contentsOf: url, encoding: .utf8)
        return strippingCommentLines(text)
    }

    /// Blanks every line whose trimmed text starts with `//`, keeping the line
    /// boundaries. A trailing `//` comment on a code line is blanked too, so
    /// prose there can neither satisfy a guard nor trip one.
    private func strippingCommentLines(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { return "" }
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

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

    private func lineIndex(of needle: String, in source: String) -> Int? {
        sourceLines(source).firstIndex { $0.contains(needle) }
    }

    /// The call beginning on the first line containing `needle`, up to the line
    /// that closes it: a call is parenthesised, so a brace-balanced body would
    /// skip the arguments altogether.
    private func callBody(ofLineContaining needle: String, in source: String) -> String? {
        let lines = sourceLines(source)
        guard let start = lines.firstIndex(where: { $0.contains(needle) }) else {
            return nil
        }

        var body: [String] = []
        for line in lines[start...] {
            body.append(line)
            if line.trimmingCharacters(in: .whitespaces) == ")" {
                return body.joined(separator: "\n")
            }
        }
        return nil
    }

    // MARK: - S-87b-22 the host builds, feeds, passes and restores the holder

    /// The holder is built beside the phone's settings, over the same store:
    /// one construction, after the settings it sits beside.
    func testS87b22TheHostBuildsTheHolderBesideThePhoneSettings() throws {
        let view = try appSource("ContentView.swift")

        let construction = try XCTUnwrap(
            lineIndex(of: "let personalBests = WatchPersonalBests(store: store)", in: view),
            "S-87b-22 the host builds the holder over the app's own store"
        )
        let preferences = try XCTUnwrap(
            lineIndex(of: "let preferences = WatchPhonePreferences(store: store)", in: view),
            "S-87b-22 the holder is built beside the phone's settings"
        )
        XCTAssertLessThan(
            preferences,
            construction,
            "S-87b-22 the settings exist before the holder that is built beside them"
        )
        XCTAssertEqual(
            view.components(separatedBy: "WatchPersonalBests(store: store)").count - 1,
            1,
            "S-87b-22 one holder for the life of the app, not one per surface"
        )
    }

    /// The orchestrator routes `bests_down` into it, and the logging state asks
    /// it for the verdict: without either, a frame never lands and no set is
    /// ever a record.
    func testS87b22TheOrchestratorAndTheLoggingStateBothTakeTheHolder() throws {
        let view = try appSource("ContentView.swift")

        let orchestrator = try XCTUnwrap(
            callBody(ofLineContaining: "let orchestrator = WatchSyncOrchestrator(", in: view),
            "S-87b-22 the host builds the orchestrator"
        )
        XCTAssertTrue(
            orchestrator.contains("bests: personalBests"),
            "S-87b-22 the orchestrator takes the holder, so a bests_down reaches it (D-8)"
        )

        let logging = try XCTUnwrap(
            callBody(ofLineContaining: "let logging = WatchLoggingState(", in: view),
            "S-87b-22 the host builds the logging state"
        )
        XCTAssertTrue(
            logging.contains("personalBests: personalBests"),
            "S-87b-22 the logging state takes the holder, so a wrist log gets a verdict"
        )

        XCTAssertTrue(
            view.contains("self.personalBests = personalBests"),
            "S-87b-22 the host keeps the holder, or the app drops it at the end of init"
        )
    }

    /// A relaunch comes back with the frame it held and the wrist's own sets:
    /// the restore sits after the settings it rides beside, inside the same
    /// sequence.
    func testS87b22TheRestoreSequenceRestoresTheHolderAfterTheSettings() throws {
        let view = try appSource("ContentView.swift")

        let restore = try XCTUnwrap(
            braceBody(ofLineContaining: "func restore() async", in: view),
            "S-87b-22 the host carries the launch restore"
        )

        let preferences = try XCTUnwrap(
            restore.range(of: "await preferences.restore()"),
            "S-87b-22 the settings are restored"
        )
        let bests = try XCTUnwrap(
            restore.range(of: "await personalBests.restore()"),
            "S-87b-22 the bests are restored, so a relaunch keeps the frame and the own bests"
        )
        XCTAssertLessThan(
            preferences.lowerBound,
            bests.lowerBound,
            "S-87b-22 the holder is restored after the settings it is built beside"
        )
    }

    // MARK: - S-87b-22 the banner is an overlay, and the record tap is its own

    /// The banner draws a trophy, cannot swallow a tap, and hands its label to
    /// VoiceOver; the view gained no timer for it (D-9).
    func testS87b22TheBannerIsANonBlockingOverlayWithNoTimer() throws {
        let view = try engineSource("WatchLoggingView.swift")

        XCTAssertTrue(
            view.contains("trophy.fill"),
            "S-87b-22 the banner draws the trophy symbol"
        )
        XCTAssertTrue(
            view.contains(".overlay(alignment: .top)"),
            "S-87b-22 the banner is an overlay at the top, so it covers no button and pushes no row"
        )
        XCTAssertTrue(
            view.contains("allowsHitTesting(false)"),
            "S-87b-22 the banner never takes a tap from Log, rest or Next (D-7)"
        )
        XCTAssertTrue(
            view.contains("isPersonalRecordBannerVisible(at:"),
            "S-87b-22 the banner reads the state's window rather than a clock of its own"
        )

        let timers = view.components(separatedBy: "Timer.scheduledTimer").count - 1
        XCTAssertEqual(
            timers,
            Self.viewTimersAtBanner,
            "S-87b-22 the banner added no timer: the expiry rides the model's existing tick (D-9)"
        )
    }

    /// The record cue is `.start`, the one built-in type no other cue in the
    /// file plays (D-18), and it is a cue of its own rather than the logged tap.
    func testS87b22TheRecordCueIsTheUnusedBuiltInType() throws {
        let view = try engineSource("WatchLoggingView.swift")

        let cue = try XCTUnwrap(
            view.range(of: "func playPersonalRecord()"),
            "S-87b-22 the wrist maps a record's cue"
        )
        let start = try XCTUnwrap(
            view.range(of: ".start", range: cue.upperBound..<view.endIndex),
            "S-87b-22 playPersonalRecord plays .start"
        )
        XCTAssertLessThanOrEqual(
            view.distance(from: cue.upperBound, to: start.lowerBound),
            120,
            "S-87b-22 .start is the body of playPersonalRecord, not a distant line"
        )
        XCTAssertEqual(
            view.components(separatedBy: "play(.start)").count - 1,
            1,
            "S-87b-22 no other cue in the file plays .start, so a record is told apart (D-18)"
        )
    }

    // MARK: - S-87b-14 the banner speaks once per record

    /// The banner carries the spoken label, and exactly one announcement is
    /// posted for it — guarded by the availability check, because the package
    /// pins watchOS 9 (D-19).
    func testS87b14TheBannerCarriesTheLabelAndOneGuardedAnnouncement() throws {
        let view = try engineSource("WatchLoggingView.swift")

        XCTAssertTrue(
            view.contains(".accessibilityLabel(WatchSpokenText.personalRecord)"),
            "S-87b-14 the banner's element is labelled with the spoken text"
        )
        XCTAssertTrue(
            view.contains(".accessibilityElement(children: .ignore)"),
            "S-87b-14 the label replaces the trophy and the two words, not joins them"
        )

        let announcement = try XCTUnwrap(
            braceBody(ofLineContaining: "func announcePersonalRecord()", in: view),
            "S-87b-14 the view carries the announcement's one site"
        )
        XCTAssertEqual(
            announcement.components(separatedBy: "AccessibilityNotification.Announcement(").count - 1,
            1,
            "S-87b-14 one announcement is posted, not one per word"
        )
        XCTAssertEqual(
            announcement.components(separatedBy: ".post()").count - 1,
            1,
            "S-87b-14 the one announcement is posted once"
        )

        let availability = try XCTUnwrap(
            lineIndex(of: "#available(watchOS 10.0, *)", in: announcement),
            "S-87b-14 the announcement API is guarded: the package's floor is watchOS 9"
        )
        let post = try XCTUnwrap(
            lineIndex(of: "AccessibilityNotification.Announcement(", in: announcement),
            "S-87b-14 the announcement sits inside the guard"
        )
        XCTAssertLessThan(
            availability,
            post,
            "S-87b-14 the guard comes first, so watchOS 9 keeps the label alone"
        )
    }

    /// The announcement fires when a record opens a banner window and never on
    /// any other change, where "no window" is the state a non-record log leaves.
    func testS87b14TheAnnouncementIsHookedToTheRecordWindow() throws {
        let view = try engineSource("WatchLoggingView.swift")

        let body = try XCTUnwrap(
            braceBody(ofLineContaining: "public var body: some View", in: view),
            "S-87b-14 the logging surface's body"
        )
        XCTAssertTrue(
            body.contains(".onChange(of: model.state.personalRecordBannerUntil)"),
            "S-87b-14 only a new record window triggers the hook"
        )
        XCTAssertTrue(
            body.contains("guard until != nil else { return }"),
            "S-87b-14 a window being cleared announces nothing"
        )
        XCTAssertTrue(
            body.contains("announcePersonalRecord()"),
            "S-87b-14 the hook posts the announcement"
        )
    }

    // MARK: - S-87b-8 detection has one door

    /// Every `.swift` file of the engine package and the watch app, read with
    /// its comment lines removed, keyed by file name.
    private func targetSources() throws -> [(name: String, text: String)] {
        let directories = [
            Fixtures.sourcesRoot,
            Fixtures.repositoryRoot.appendingPathComponent("ios/OmniTrain Watch App"),
        ]
        var sources: [(name: String, text: String)] = []
        for directory in directories {
            let files = try FileManager.default
                .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "swift" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for file in files {
                let text = try String(contentsOf: file, encoding: .utf8)
                sources.append((file.lastPathComponent, strippingCommentLines(text)))
            }
        }
        return sources
    }

    private func occurrences(of needle: String, in source: String) -> Int {
        source.components(separatedBy: needle).count - 1
    }

    /// The structural half of S-87b-8: a set the phone mirrored in reaches
    /// storage through `storeSnapshotEntry`, which never touches the holder, and
    /// the reason it cannot is that `noteLogged(` has exactly one caller — the
    /// wrist-logged path, `WatchLoggingState.log`. The behavioural half is
    /// `WatchPersonalRecordBannerTests.testS87b8ASnapshotSetRaisesNoBannerAndNoTap`.
    ///
    /// A snapshot-applied set cannot be mutated into a caller: the engine holds
    /// no reference to the holder, so a snapshot path has nothing to call. This
    /// scan is what a future call site would trip.
    func testS87b8NoteLoggedIsCalledFromTheLoggingStateAlone() throws {
        let sources = try targetSources()

        let callers = sources.filter { source in
            source.name != "WatchPersonalBests.swift"
                && source.name != "WatchLoggingState.swift"
                && occurrences(of: "noteLogged(", in: source.text) > 0
        }
        XCTAssertTrue(
            callers.isEmpty,
            "S-87b-8 noteLogged( is called from the logging state alone; found "
                + callers
                .map { "\($0.name) x\(occurrences(of: "noteLogged(", in: $0.text))" }
                .joined(separator: ", ")
        )

        let logging = try XCTUnwrap(
            sources.first { $0.name == "WatchLoggingState.swift" },
            "S-87b-8 the logging state is one of the engine's files"
        )
        XCTAssertEqual(
            occurrences(of: "noteLogged(", in: logging.text),
            1,
            "S-87b-8 the logging state asks the holder once per log"
        )

        let holder = try XCTUnwrap(
            sources.first { $0.name == "WatchPersonalBests.swift" },
            "S-87b-8 the holder is one of the engine's files"
        )
        XCTAssertEqual(
            occurrences(of: "noteLogged(", in: holder.text),
            1,
            "S-87b-8 the holder's only occurrence is its own declaration"
        )
        XCTAssertTrue(
            holder.text.contains("func noteLogged("),
            "S-87b-8 that one occurrence declares the verdict, it is not a call"
        )
    }
}
