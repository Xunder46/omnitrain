//
//  WatchPagerModel.swift
//  WatchSessionEngine
//
//  The logging screen's pager: which page is current, the one select a settled
//  swipe makes, and the lock that refuses a swipe during an effort.
//
//  Deliberately outside the watchOS-only view: this is the part with a rule in
//  it — when a swipe moves the session and when it only raises a notice — so it
//  builds and is tested on the desktop toolchain like the rest of the module.
//  The view that mounts a `TabView` over it is compiled only into the watch app.
//
//  The model owns no session structure of its own: a settled page is the menu's
//  `jump(to:)`, which is the engine's own select path. The rows and the
//  position are read from the menu on every access, never cached, so a frame
//  that lands while the pager is open is already the page the user sees.
//

import Combine
import Foundation

/// The words the pager says; the lock notice matches the menu's own caption.
public enum WatchPagerCopy {
    public static let lockedNotice = "An effort is running"
    public static let noticeSeconds: TimeInterval = 1.5
}

@MainActor
public final class WatchPagerModel: ObservableObject {
    private let menu: WatchMenuState
    private let clock: () -> Date
    private var noticeUntil: Date?

    public init(menu: WatchMenuState, clock: @escaping () -> Date = Date.init) {
        self.menu = menu
        self.clock = clock
    }

    public var rows: [WatchMenuRow] { menu.rows }
    public var pageCount: Int { rows.count }
    public var currentIndex: Int { rows.firstIndex(where: { $0.isCurrent }) ?? 0 }
    public var isLocked: Bool { menu.isLocked }
    public var showsPager: Bool { pageCount > 1 && !isLocked }
    public var pageLabel: String? { pageCount > 1 ? "\(currentIndex + 1)/\(pageCount)" : nil }

    /// The slot a page that has just settled is shown as before the engine has
    /// moved to it (plan 52 D-6): nil for the engine's own page, a page that is
    /// gone, or a locked session; else that page's slot.
    public func focusSlotId(for index: Int) -> String? {
        let rows = self.rows
        guard rows.indices.contains(index), !rows[index].isCurrent, !isLocked else { return nil }
        return rows[index].slotId
    }

    /// Moves the session to page `index` once the swipe has settled: true when
    /// that exercise is now (or already was) the current one. A locked session
    /// refuses and starts the notice; a page that no longer exists changes nothing.
    public func land(on index: Int) async -> Bool {
        let rows = self.rows
        guard rows.indices.contains(index) else { return false }
        if rows[index].isCurrent { return true }
        guard !isLocked else {
            noteLockedSwipe()
            return false
        }
        return await menu.jump(to: rows[index].slotId)
    }

    public func noteLockedSwipe() {
        noticeUntil = clock().addingTimeInterval(WatchPagerCopy.noticeSeconds)
        objectWillChange.send()
    }

    public func noticeVisible(at instant: Date) -> Bool {
        guard let noticeUntil else { return false }
        return instant < noticeUntil
    }
}
