//
//  WatchEngineStateBoxSourceTests.swift
//  WatchSessionEngineTests
//
//  Plan `docs/plans/2026-11-14-162-engine-state-lock-box-plan/2026-11-14-162-engine-state-lock-box-plan.md`,
//  Phase 4 (slice 2): the structural guard that keeps the drift from coming
//  back. After the box landed, `WatchSessionEngine.swift` may not declare a
//  plain mutable stored property other than the ones named below — a new one is
//  the next value two threads can tear, and the box is where it belongs
//  (D-16206).
//
//  Scenario mapping:
//    S-16205 the engine declares no un-boxed mutable stored property → `testS16205...`
//
//  The box's own file is deliberately not scanned: holding `var` state behind
//  its lock is its whole job. Computed properties are not matched because the
//  file opens their brace on the declaration line; a stored property whose
//  initialiser is written on the following line would be missed, which the
//  file's one-line convention makes acceptable — this is a guard against the
//  drift class, not a parser.
//

import Foundation
import XCTest

final class WatchEngineStateBoxSourceTests: XCTestCase {

    /// The plain mutable stored properties the engine may keep at class-member
    /// indent, each with the reason it is not in a box.
    private static let allowed: [String: String] = [
        // Written after init by `WatchTimerHaptics` (`WatchTimerHaptics.swift`),
        // which holds no lock and is called from the logging model on the main
        // actor. Boxing it is out of plan 162's scope (plan Open questions).
        "announcedCountdownKeys": "written by WatchTimerHaptics after init",
        // The three energy-announce marks are guarded by `energyMarksLock`,
        // declared beside them in the same file: one reader and one writer, both
        // inside `energyAnnouncement`'s synchronous section (plan 162 D-16201,
        // Phase 1).
        "energyAnnouncedSession": "guarded by energyMarksLock (D-16201)",
        "energyAnnouncedKcal": "guarded by energyMarksLock (D-16201)",
        "energyAnnouncedAt": "guarded by energyMarksLock (D-16201)",
    ]

    /// S-16205: `WatchSessionEngine.swift`, comment lines stripped, declares
    /// exactly the allowed stored properties — so `current`, `sessionRows`,
    /// `appliedChangeIds` and `newestSnapshotAt` can only come back through
    /// `WatchEngineSessionState`, under its lock.
    ///
    /// Guard value: re-adding `private var probe: Int = 0` to the engine turns
    /// this red (recorded in the plan's evidence file, Phase 4).
    func testS16205EngineDeclaresNoUnboxedMutableState() throws {
        let url = Fixtures.sourcesRoot.appendingPathComponent("WatchSessionEngine.swift")
        let source = strippingCommentLines(try String(contentsOf: url, encoding: .utf8))

        XCTAssertEqual(
            storedPropertyNames(in: source),
            Set(Self.allowed.keys),
            "WatchSessionEngine.swift declares plain mutable stored state outside "
                + "\(Set(Self.allowed.keys).sorted()). A value two threads can reach "
                + "belongs in WatchEngineSessionState (plan 162 D-16202/D-16206)."
        )
    }

    /// The names at class-member indent that a `var` declaration makes stored:
    /// `name: Type`, `name: Type = initialiser`, or `name = initialiser`. Every
    /// class stays on one line and no newline can belong to one, so a match
    /// cannot span two declarations.
    private func storedPropertyNames(in source: String) -> Set<String> {
        let modifiers = #"(?:(?:private|internal|public|fileprivate|static) )*"#
        let patterns = [
            #"^    "# + modifiers + #"var (\w+): [^{=\n]*(?:= [^{}\n]*)?$"#,
            #"^    "# + modifiers + #"var (\w+) = [^{}\n]*$"#,
        ]
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        var names: Set<String> = []

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.anchorsMatchLines]
            ) else {
                XCTFail("the stored-property pattern does not compile: \(pattern)")
                continue
            }
            for match in regex.matches(in: source, range: range) {
                guard let nameRange = Range(match.range(at: 1), in: source) else { continue }
                names.insert(String(source[nameRange]))
            }
        }
        return names
    }

    /// Blanks every line whose trimmed text starts with `//`, and every trailing
    /// `//` comment, keeping line boundaries — so prose can neither satisfy this
    /// guard nor trip it.
    private func strippingCommentLines(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { return "" }
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }
}
