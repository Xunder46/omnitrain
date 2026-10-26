//
//  WatchSyncNotice.swift
//  WatchSessionEngine
//
//  The wrist's "waiting for your phone" line (plan 51d,
//  `docs/plans/2026-10-21-51d-wrist-sync-waiting-notice-plan/2026-10-21-51d-wrist-sync-waiting-notice-plan.md`,
//  D-1). A pure function outside the watchOS-only views, so the desktop
//  toolchain can assert when the wrist speaks: always when the radio says the
//  phone is out of reach, and otherwise only once the oldest unacknowledged
//  entry has waited long enough that a receipt should have arrived.
//

import Foundation

/// The line's words and the wait after which a reachable phone is doubted.
public enum WatchSyncNoticeCopy {
    /// How long an entry may wait on a reachable (or not yet known) phone before
    /// the wrist says so; a receipt normally lands within a second or two.
    public static let graceSeconds: TimeInterval = 90

    public static func waiting(_ count: Int) -> String {
        count == 1
            ? "1 entry waiting for your phone"
            : "\(count) entries waiting for your phone"
    }
}

/// The line to show for `pending` (the observations the phone has not
/// acknowledged); rest windows do not count. Or nil when the wrist has nothing
/// to say.
public func deriveSyncNotice(
    pending: [WatchObservationRecord],
    reachability: WatchPhoneReachability,
    now: Date
) -> String? {
    // A rest window is the wrist's own bookkeeping between two efforts, not
    // something the user logged: it is neither counted nor aged.
    let logged = pending.filter { $0.kind != WatchObservationKind.rest }
    guard let oldest = logged.map(\.recordedAt).min() else { return nil }
    if reachability == .unreachable {
        return WatchSyncNoticeCopy.waiting(logged.count)
    }
    return now.timeIntervalSince(oldest) >= WatchSyncNoticeCopy.graceSeconds
        ? WatchSyncNoticeCopy.waiting(logged.count)
        : nil
}
