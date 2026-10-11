//
//  CoreLocationRawSource.swift
//  OmniTrain Watch App
//
//  The wrist's raw position readings: `CLLocationManager` behind the package's
//  `WatchRawFixSource` seam.
//
//  Plan: `docs/plans/2026-10-10-19f-watch-gps-feed-plan/2026-10-10-19f-watch-gps-feed-plan.md`,
//  D-2303. The rules about *when* a subscription runs, what a fix becomes once
//  stored, and which fix starts an effort live in the package, where `swift test`
//  exercises them on macOS (`WatchTrackedLocation`, `WatchDistanceTracker`).
//  What is left here is the platform side: the radio, the permission question,
//  and the two delegates that carry them.
//
//  Three rules shape this file:
//
//  1. **The manager is born on the main actor.** `CLLocationManager` delivers its
//     delegate callbacks on the thread that created it, so a manager created
//     lazily from a background task never calls back at all. The host builds
//     this object on the main actor, inside `WatchAppHost.init`, and the manager
//     is created there with it (D-2303).
//  2. **The radio lives exactly as long as a subscriber.** The first
//     subscription starts the updates and the last termination stops them, both
//     on the main queue; a transient `didFailWithError` ends nothing, while a
//     revoked permission ends every subscription and so stops the radio too. A
//     radio left on after the session's last consumer is battery spent for
//     nothing.
//  3. **WhenInUse, never Always.** The workout keeps the app running while a
//     session is on screen, so background updates are neither needed nor
//     enabled: only `requestWhenInUseAuthorization()` is called here (D-2303).
//

#if os(watchOS)

import Foundation
// The manager is created on the main actor and every call that mutates it is dispatched to the main queue.
@preconcurrency import CoreLocation
import WatchSessionEngine

/// `CLLocationManager`, as the seam `WatchRawFixSource` expects.
///
/// The class is `nonisolated` on purpose: the target's default isolation is the
/// main actor and CoreLocation calls its delegates off it (`CLLocationManager`
/// itself is not main-actor bound). Every piece of state a delegate callback can
/// touch — the continuations, the waiters — lives behind the lock below.
nonisolated final class CoreLocationRawSource: NSObject, CLLocationManagerDelegate, WatchRawFixSource {
    /// The one manager for the life of this source. Created and configured in
    /// `init` because CoreLocation delivers its callbacks on the thread that
    /// created it: the host builds this on the main actor, so building the
    /// manager there is what makes the delegates arrive at all (D-2303).
    private let manager: CLLocationManager

    /// The listeners someone is holding right now, keyed by subscription. The
    /// delegate callbacks arrive on the manager's queue, so every read and every
    /// write of these goes through the lock.
    private let lock = NSLock()
    private var fixContinuations: [UUID: AsyncStream<WatchRawFix>.Continuation] = [:]

    /// The callers parked inside `permission()` while the authorization question
    /// is open, keyed by waiter. Each is resumed once: by
    /// `locationManagerDidChangeAuthorization(_:)` once the status settles, or by
    /// its own re-read in `requestAuthorization()` when the answer arrived before
    /// the delegate could see it.
    private var permissionWaiters: [UUID: CheckedContinuation<WatchSensorPermission, Never>] = [:]

    override init() {
        manager = CLLocationManager()
        super.init()

        // The best the wrist can do, and the workout's own movement: these are
        // fixed once, because the source has exactly one job (D-2303).
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        manager.delegate = self
    }

    // MARK: - WatchRawFixSource

    /// The platform's answer, mapped to the seam's three states, and a prompt
    /// only when the answer is not known yet (D-2303).
    ///
    /// With Location services switched off there is nothing to ask and nothing
    /// to measure, so the answer is `.unavailable` before any status is read:
    /// `requestWhenInUseAuthorization()` would never produce an authorization
    /// change, and the recorder's probe would wait forever.
    func permission() async -> WatchSensorPermission {
        guard CLLocationManager.locationServicesEnabled() else { return .unavailable }

        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return .granted
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return await requestAuthorization()
        @unknown default:
            return .denied
        }
    }

    /// The fixes the manager reports, as the wire's raw shape.
    ///
    /// Each call is its own subscription: the first one starts the radio and the
    /// last termination stops it, both on the main queue — the manager was built
    /// there, and that is the thread it calls back on. The stream never finishes
    /// on its own: the package decides when an effort is over.
    func rawFixes() -> AsyncStream<WatchRawFix> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            fixContinuations[id] = continuation
            let isFirst = fixContinuations.count == 1
            lock.unlock()

            if isFirst {
                DispatchQueue.main.async { [manager] in
                    manager.startUpdatingLocation()
                }
            }

            continuation.onTermination = { [weak self] _ in
                guard let self else { return }

                self.lock.lock()
                self.fixContinuations[id] = nil
                let isLast = self.fixContinuations.isEmpty
                self.lock.unlock()

                // The last consumer is gone, so the radio goes with it: updates
                // left on past the session's last subscriber are battery spent
                // for nothing.
                if isLast {
                    DispatchQueue.main.async { [manager = self.manager] in
                        manager.stopUpdatingLocation()
                    }
                }
            }
        }
    }

    // MARK: - CLLocationManagerDelegate

    /// Yields one raw fix per fix the platform reports.
    ///
    /// The accuracy is passed as CoreLocation gives it — a negative value means
    /// the platform says the fix is invalid, and the package's tracker refuses
    /// it — and the timestamp is the fix's own, so the adapter's stale gate can
    /// drop a cached position before it becomes an origin.
    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        let fixes = locations.map { location in
            WatchRawFix(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                horizontalAccuracyMeters: location.horizontalAccuracy,
                timestamp: location.timestamp
            )
        }

        // Copied out of the lock and yielded outside it, like the feed does: a
        // slow consumer must not hold the manager's queue.
        lock.lock()
        let listeners = Array(fixContinuations.values)
        lock.unlock()

        for listener in listeners {
            for fix in fixes { listener.yield(fix) }
        }
    }

    /// Does nothing. A transient error is not a failure: it ends no subscription
    /// and reports nothing — a fix the platform could not produce this time is
    /// simply a fix the source does not have, and the next update arrives on its
    /// own while updates are on.
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    /// Wakes every caller parked in `permission()` once, and only once, the
    /// status has settled, and ends the feed when the permission is gone.
    ///
    /// This callback fires as soon as the delegate is set — with `.notDetermined`
    /// — and again when the user answers. A wake-up that still reads
    /// `.notDetermined` is not an answer, so the waiters stay parked for the next
    /// one; the determined status is read here, never assumed from the callback.
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        guard status != .notDetermined else { return }

        lock.lock()
        let waiters = Array(permissionWaiters.values)
        permissionWaiters.removeAll()
        // A permission the user revoked in Settings ends the live feed instead of
        // leaving it silent: with `.denied` or `.restricted` no further fix can
        // arrive, so the distance would freeze while the radio ran on for no one.
        // Finishing each raw-fix continuation runs its `onTermination`, which
        // stops the radio exactly as a normal end does.
        let endedFixes = status == .denied || status == .restricted
            ? Array(fixContinuations.values)
            : []
        lock.unlock()

        let answer = Self.permission(for: status)
        for waiter in waiters { waiter.resume(returning: answer) }
        for continuation in endedFixes { continuation.finish() }
    }

    // MARK: - The authorization question

    /// Asks and waits for the answer the delegate delivers.
    ///
    /// Every caller that finds the status undetermined asks: CoreLocation
    /// coalesces the calls while a prompt is already up, and asks again after a
    /// temporary grant ("Allow Once") lapses and the status falls back to
    /// `.notDetermined`. Nothing here remembers that a question was asked — a
    /// latch would leave the second session's caller, and the serial sensors
    /// behind it, parked for the life of the process.
    private func requestAuthorization() async -> WatchSensorPermission {
        await withCheckedContinuation { continuation in
            let id = UUID()
            lock.lock()
            permissionWaiters[id] = continuation
            lock.unlock()

            // The status can settle between `permission()`'s read and the
            // registration above: the user may answer in that instant, and the
            // delegate then fires with no waiter registered. Whoever removes the
            // waiter resumes it: this re-check resumes only the waiter its own
            // `removeValue` returned, so the delegate (which removes and resumes
            // under the same lock) cannot resume it too — it is resumed once. An
            // already-answered status also means no prompt is dispatched at all.
            let status = manager.authorizationStatus
            guard status == .notDetermined else {
                lock.lock()
                let own = permissionWaiters.removeValue(forKey: id)
                lock.unlock()
                own?.resume(returning: Self.permission(for: status))
                return
            }

            // The prompt is user-visible, so it goes to the main queue where the
            // manager was built (D-2303).
            DispatchQueue.main.async { [manager] in
                manager.requestWhenInUseAuthorization()
            }
        }
    }

    // MARK: - The answer

    private static func permission(for status: CLAuthorizationStatus) -> WatchSensorPermission {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways: return .granted
        case .denied, .restricted: return .denied
        default: return .denied
        }
    }
}

#endif
