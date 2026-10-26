//
//  WatchLoggingPagerView.swift
//  WatchSessionEngine
//
//  The wrist's swipeable exercise pages over the logging surface. Plan 46b
//  (`docs/plans/2026-10-20-46b-wrist-swipe-pager-plan/2026-10-20-46b-wrist-swipe-pager-plan.md`),
//  decisions D-3, D-5 and D-6.
//
//  Compiled only into the watch app target: `DragGesture` and
//  `WKInterfaceDevice` are the watchOS surface's, while the rule that decides
//  when a swipe moves the session lives in `WatchPagerModel` and is tested on
//  the desktop toolchain. This file is the shape around that model.
//
//  Plan 79: no page-turn, so no name card between exercises.
//
//  The package targets watchOS 9, so every `onChange` here is the
//  single-argument form; the two-argument one arrived later.
//

#if os(watchOS)

import SwiftUI
import WatchKit

/// Swipe between the session's exercises: one logger, and a swipe switches to
/// the neighbouring exercise at once. The session moves only when the swipe has
/// settled, through the menu's own select path. While an effort clock runs
/// there is no paging: one page, and a swipe gives a failure tap and a short
/// notice.
public struct WatchLoggingPagerView: View {
    @StateObject private var pager: WatchPagerModel
    private let state: WatchLoggingState
    private let revision: Int
    private let onSurfaceChange: () -> Void

    @State private var selection = 0
    @State private var landing = false

    public init(
        menu: WatchMenuState,
        state: WatchLoggingState,
        revision: Int,
        onSurfaceChange: @escaping () -> Void
    ) {
        _pager = StateObject(wrappedValue: WatchPagerModel(menu: menu))
        _selection = State(initialValue: menu.rows.firstIndex(where: { $0.isCurrent }) ?? 0)
        self.state = state
        self.revision = revision
        self.onSurfaceChange = onSurfaceChange
    }

    public var body: some View {
        content
            .onAppear { selection = pager.currentIndex }
            .onChange(of: revision) { _ in followEngine() }
    }

    @ViewBuilder
    private var content: some View {
        if pager.showsPager {
            paged
        } else {
            single
        }
    }

    /// The shown exercise's logger, rebuilt per exercise. A horizontal swipe
    /// moves to the neighbouring exercise at once: the focus names the page the
    /// user reached before the engine has moved (plan 52 D-5), and `land(on:)`
    /// moves the engine behind it. No page-turn, so no name card in between.
    private var paged: some View {
        WatchLoggingView(
            state: state,
            onLogged: onSurfaceChange,
            pageLabel: "\(selection + 1)/\(pager.pageCount)"
        )
        .id(pager.rows.indices.contains(selection) ? pager.rows[selection].slotId : "")
        .simultaneousGesture(
            DragGesture(minimumDistance: 24).onEnded { value in
                let across = value.translation.width
                guard abs(across) > 24, abs(across) > abs(value.translation.height),
                      let target = pager.neighbourIndex(of: selection, towardsNext: across < 0)
                else { return }
                WKInterfaceDevice.current().play(.click)
                state.focusSlotId = pager.focusSlotId(for: target)
                selection = target
            }
        )
        .onChange(of: selection) { newValue in land(on: newValue) }
    }

    /// One page: a session with one exercise, or a session whose effort clock
    /// runs. Only the locked case answers a swipe.
    private var single: some View {
        WatchLoggingView(state: state, onLogged: onSurfaceChange, pageLabel: pager.pageLabel)
            .simultaneousGesture(
                DragGesture(minimumDistance: 24).onEnded { value in
                    guard pager.isLocked else { return }
                    let across = abs(value.translation.width)
                    guard across > 24, across > abs(value.translation.height) else { return }
                    pager.noteLockedSwipe()
                    WKInterfaceDevice.current().play(.failure)
                    Task {
                        try? await Task.sleep(nanoseconds: UInt64((WatchPagerCopy.noticeSeconds + 0.1) * 1_000_000_000))
                        pager.objectWillChange.send()
                    }
                }
            )
            .overlay {
                if pager.noticeVisible(at: Date()) {
                    Text(WatchPagerCopy.lockedNotice)
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .padding(6)
                        .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
                }
            }
    }

    private func land(on index: Int) {
        guard index != pager.currentIndex else {
            state.focusSlotId = nil
            return
        }
        landing = true
        Task {
            let moved = await pager.land(on: index)
            landing = false
            if moved {
                onSurfaceChange()
                // A swipe that settled while this one was landing was dropped
                // (its index equalled the engine's old position); the newest
                // settled page wins rather than being pulled back, and keeps
                // its focus until its own landing ends.
                if selection != pager.currentIndex {
                    state.focusSlotId = pager.focusSlotId(for: selection)
                    land(on: selection)
                } else {
                    state.focusSlotId = nil
                }
            } else {
                state.focusSlotId = nil
                selection = pager.currentIndex
            }
        }
    }

    /// A change the user did not make (the phone's push, a menu jump) moves the
    /// pager to the engine's page, unless a swipe is still landing.
    private func followEngine() {
        // With no landing in flight, a focus left over from one is stale.
        if !landing { state.focusSlotId = nil }
        guard pager.showsPager, !landing, selection != pager.currentIndex else { return }
        selection = pager.currentIndex
    }
}

#endif
