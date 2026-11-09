//
//  WatchSpokenText.swift
//  WatchSessionEngine
//
//  Spoken-text helpers for the wrist's VoiceOver labels (plan 84, D-1).
//
//  A plain engine-target enum with no SwiftUI import and no `#if os(watchOS)`:
//  its tests run on macOS under `swift test` (D-8). The views that call it keep
//  their own file-level `#if os(watchOS)`.
//

/// What VoiceOver reads for the wrist's clocks and ratings (plan 84, D-1).
public enum WatchSpokenText {
    /// A duration the way VoiceOver speaks it: hours, minutes and seconds in
    /// that order, space separated, zero units dropped — except a total of 0,
    /// which keeps its "0 seconds". Negative input reads as "0 seconds".
    public static func duration(seconds: Int) -> String {
        let seconds = max(seconds, 0)
        guard seconds > 0 else { return "0 seconds" }

        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remaining = seconds % 60

        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) hour\(hours == 1 ? "" : "s")") }
        if minutes > 0 { parts.append("\(minutes) minute\(minutes == 1 ? "" : "s")") }
        if remaining > 0 { parts.append("\(remaining) second\(remaining == 1 ? "" : "s")") }
        return parts.joined(separator: " ")
    }

    /// An effort rating the way VoiceOver speaks it: "Rating 3 of 5".
    public static func rating(_ value: Int, of highest: Int) -> String {
        "Rating \(value) of \(highest)"
    }

    /// The wrist's "New PR" banner the way VoiceOver speaks it (plan 87b D-7,
    /// D-19). The banner shows two words and no number, so the spoken form is
    /// the whole sentence, not a reading of what is on screen.
    public static let personalRecord = "New personal record"
}
