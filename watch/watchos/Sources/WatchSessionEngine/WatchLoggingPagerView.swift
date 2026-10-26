//
//  WatchLoggingPagerView.swift
//  WatchSessionEngine
//
//  The wrist's swipeable exercise pages over the logging surface. Plan 46b
//  (`docs/plans/2026-10-20-46b-wrist-swipe-pager-plan/2026-10-20-46b-wrist-swipe-pager-plan.md`),
//  decisions D-3, D-5 and D-6.
//
//  Compiled only into the watch app target: `TabView`, `DragGesture` and
//  `WKInterfaceDevice` are the watchOS surface's, while the rule that decides
//  when a swipe moves the session lives in `WatchPagerModel` and is tested on
//  the desktop toolchain. This file is the shape around that model.
//
//  The package targets watchOS 9, so every `onChange` here is the
//  single-argument form; the two-argument one arrived later.
//

#if os(watchOS)

import SwiftUI
import WatchKit

/// Swipe between the session's exercises. Other pages are preview cards; the
/// session moves to a page only when the swipe has settled, through the menu's
/// own select path. While an effort clock runs there is no paging: one page,
/// and a swipe gives a failure tap and a short notice.
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

    private var paged: some View {
        TabView(selection: selectionBinding) {
            ForEach(Array(pager.rows.enumerated()), id: \.element.slotId) { index, row in
                page(row, index: index).tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: selection) { newValue in land(on: newValue) }
    }

    @ViewBuilder
    private func page(_ row: WatchMenuRow, index: Int) -> some View {
        if index == selection {
            WatchLoggingView(
                state: state,
                onLogged: onSurfaceChange,
                pageLabel: "\(index + 1)/\(pager.pageCount)"
            )
        } else {
            WatchExercisePreviewPage(row: row, label: "\(index + 1)/\(pager.pageCount)")
        }
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

    /// The `TabView`'s selection, with the one thing a settled swipe must do
    /// before the new page is drawn: name the slot the logging surface now
    /// shows, so that page is the logger at once rather than a card until the
    /// engine has moved (plan 52 D-6).
    private var selectionBinding: Binding<Int> {
        Binding(
            get: { selection },
            set: { newValue in
                state.focusSlotId = pager.focusSlotId(for: newValue)
                selection = newValue
            }
        )
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

/// What a page that is not the current exercise shows while the swipe settles.
private struct WatchExercisePreviewPage: View {
    let row: WatchMenuRow
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Spacer(minLength: 0)
            Text(row.name)
                .font(.title3)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
            if let count = row.countLabel {
                Text(count)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }
}

#endif
