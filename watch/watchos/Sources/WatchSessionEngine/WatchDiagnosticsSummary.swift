//
//  WatchDiagnosticsSummary.swift
//  WatchSessionEngine
//
//  Plan 142 D-14210: the plain sentences and the newest-40 lines the
//  Diagnostics screen shows, built from the log's events. Pure type — no
//  SwiftUI, no clock, no file access.
//

import Foundation

public struct WatchDiagnosticsSummary: Equatable {
    /// Plain sentences for the top of the screen.
    public let headline: [String]
    /// The newest events, newest first, at most `Self.lineLimit`.
    public let lines: [String]
    public static let lineLimit = 40

    public init(events: [WatchDiagnosticsEvent], timeZone: TimeZone = .current) {
        let clock = DateFormatter()
        clock.dateFormat = "HH:mm"
        clock.timeZone = timeZone
        clock.locale = Locale(identifier: "en_US_POSIX")

        let stamp = DateFormatter()
        stamp.dateFormat = "HH:mm:ss"
        stamp.timeZone = timeZone
        stamp.locale = Locale(identifier: "en_US_POSIX")

        if let launch = events.lastIndex(where: { $0.kind == "launch" }) {
            var start = "Started \(clock.string(from: events[launch].at))"
            let restarted = events[(launch + 1)...].contains { $0.kind == "recovery_relaunch" }
            if restarted {
                start += " — restarted by the system"
            }
            var head = [start]
            if launch > 0 {
                let previous = events[..<launch].last!
                head.append(
                    "Before that: last seen \(Self.phrase(previous)) at \(clock.string(from: previous.at))"
                )
            } else {
                head.append("First run recorded.")
            }
            headline = head
        } else {
            headline = ["No start recorded yet."]
        }

        lines = events.suffix(Self.lineLimit).reversed().map { event -> String in
            var line = "\(stamp.string(from: event.at)) \(event.kind)"
            if let detail = event.detail { line += " \(detail)" }
            if let session = event.session { line += " s:\(session.prefix(4))" }
            return line
        }
    }

    private static func phrase(_ event: WatchDiagnosticsEvent) -> String {
        switch (event.kind, event.detail) {
        case ("scene", "background"): return "in the background"
        case ("scene", "active"): return "on screen"
        case ("scene", "inactive"): return "dimmed"
        default: return event.kind
        }
    }
}
