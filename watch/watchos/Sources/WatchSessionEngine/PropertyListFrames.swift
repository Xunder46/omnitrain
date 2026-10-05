//
//  PropertyListFrames.swift
//  WatchSessionEngine
//
//  The check every frame the wrist hands the radio must pass.
//
//  Plan: `docs/plans/2026-10-04-14-watch-shell-bridge-plan/2026-10-04-14-watch-shell-bridge-plan.md`,
//  D-4 and D-5.
//
//  A `WCSession` message dictionary holds property-list values only, and
//  `NSNull` is not one — the platform rejects the whole message. So a null is
//  refused rather than stripped: refusing it costs nothing, because the wrist's
//  wire encoders omit absent optional fields instead of nulling them (I-3), and
//  it turns a future regression into a reported failure instead of a silently
//  dropped message.
//
//  Numbers are never coerced (D-5). The protocol's integer fields are integers,
//  and the phone's validator refuses a whole-number `Double`, so papering over a
//  wrong type here would only move the failure to the phone.
//

import Foundation

/// A frame the radio cannot carry, and where the offending value sits.
public enum PropertyListFrameError: Error, CustomStringConvertible {
    /// `path` is the value's place in the frame, as `payload.events[0].entryId`.
    case unsupportedValue(String)

    public var description: String {
        switch self {
        case .unsupportedValue(let path):
            return "\(path) is not a property-list value"
        }
    }
}

public enum PropertyListFrames {
    /// `frame` with every `Date` replaced by its wire timestamp, ready for the
    /// radio.
    ///
    /// Throws `PropertyListFrameError` when the frame holds a value the radio
    /// cannot carry — `NSNull`, `Data`, or anything else that is not a property
    /// list. The caller reports it; nothing is sent and nothing is queued.
    public static func plistSafe(_ frame: [String: Any]) throws -> [String: Any] {
        try object(frame, path: "")
    }

    private static func object(
        _ value: [String: Any],
        path: String
    ) throws -> [String: Any] {
        var safe: [String: Any] = [:]
        for (key, element) in value {
            safe[key] = try any(element, path: path.isEmpty ? key : "\(path).\(key)")
        }
        return safe
    }

    private static func array(_ value: [Any], path: String) throws -> [Any] {
        try value.enumerated().map { index, element in
            try any(element, path: "\(path)[\(index)]")
        }
    }

    /// The accepted values, and only those: a number is never coerced (D-5).
    ///
    /// The `NSNumber` case returns the value unchanged rather than the bridged
    /// binding. A `Bool` is an `NSNumber` on Apple platforms, and `NSNumber`
    /// wraps an integer `0` or `1` as the `Bool` type code, so recognising a
    /// `Bool` first would hand the radio `true`/`false` where the protocol means
    /// `1`/`0`. Returning the original keeps an integer an integer and a `Bool`
    /// a `Bool`.
    private static func any(_ value: Any, path: String) throws -> Any {
        switch value {
        case let text as String:
            return text
        case is NSNumber:
            return value
        case let date as Date:
            return utcIso(date)
        case let list as [Any]:
            return try array(list, path: path)
        case let dictionary as [String: Any]:
            return try object(dictionary, path: path)
        default:
            throw PropertyListFrameError.unsupportedValue(path)
        }
    }
}
