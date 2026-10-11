//
//  WatchMenuView.swift
//  WatchSessionEngine
//
//  The native watchOS session menu: the session's own exercises to jump to, then
//  End Session. Compiled only into a watch target, like the other views in this
//  module; the model it reads is `WatchMenuState` (`WatchMenu.swift`), which the
//  suite covers.
//
//  The menu never edits, adds or deletes anything: a row is the engine's existing
//  select path, and End Session asks first, then is the rating state's `end()`.
//  It carries no rest control and mints no ids.
//

#if os(watchOS)

import SwiftUI

/// The session menu: one row per exercise on the ladder, then End Session.
public struct WatchMenuView: View {
    private let state: WatchMenuState

    /// Bumped by the host on every arrival. The rows come from a plain class
    /// that publishes nothing, so a push that lands while the menu is open shows
    /// up only because this value changed and the body ran again.
    private let revision: Int

    private let onClose: () -> Void
    private let onFinish: () -> Void

    /// The screen's title, and the fixed copy of its one action row (D-1114).
    public static let title = "Exercises"
    public static let finishLabel = WatchMenuCopy.finishLabel

    /// The one line the menu shows while a work clock is running, so the inert
    /// rows say why they are inert (D-1309).
    public static let lockCaptionText = "An effort is running"

    /// Wrist-scale inset, as the other wrist surfaces use.
    private static let surfaceInset = 4.0

    /// Set by the action row and read by its alert: the confirmation is the
    /// view's own, and `state.finish()` runs only on the alert's Finish
    /// (D-3402).
    @State private var confirmingFinish = false

    public init(
        state: WatchMenuState,
        revision: Int = 0,
        onClose: @escaping () -> Void,
        onFinish: @escaping () -> Void
    ) {
        self.state = state
        self.revision = revision
        self.onClose = onClose
        self.onFinish = onFinish
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Self.surfaceInset) {
                    if state.isLocked {
                        lockCaption
                    }

                    ForEach(state.rows, id: \.slotId) { row in
                        rowButton(row)
                    }

                    Divider()

                    finishRow
                        .padding(.top, 10)
                }
                .padding(Self.surfaceInset)
            }
            .navigationTitle(Self.title)
        }
    }

    /// A row the session is on wears the picked style, every other row the plain
    /// one.
    @ViewBuilder
    private func rowButton(_ row: WatchMenuRow) -> some View {
        let button = Button {
            Task {
                if await state.jump(to: row.slotId) { onClose() }
            }
        } label: {
            rowLabel(row)
        }

        if row.isCurrent {
            button.buttonStyle(.borderedProminent).disabled(state.isLocked)
        } else {
            button.buttonStyle(.bordered).disabled(state.isLocked)
        }
    }

    /// The one line naming why the rows are inert while a work clock runs
    /// (D-1309). Finish is never disabled, so it stays reachable.
    private var lockCaption: some View {
        Text(Self.lockCaptionText)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The exercise's name, and the count of what is already logged on it when
    /// there is one — never "0 logged" (D-1114).
    private func rowLabel(_ row: WatchMenuRow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(row.name)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let countLabel = row.countLabel {
                Text(countLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // A wrapped name and its count line both start on the row's leading
        // edge, so a two-line name is not centred and "N logged" sits under
        // the title's own edge.
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// End Session ends the session through the rating state, so the owed prompt
    /// and the finish stay one implementation, and then hands the surface back.
    /// Tapping it only raises the confirmation: Cancel changes nothing, and the
    /// rating state's `end()` runs on the alert's Finish alone (D-3402).
    private var finishRow: some View {
        Button(Self.finishLabel) {
            confirmingFinish = true
        }
        .buttonStyle(.bordered)
        .alert(WatchMenuCopy.confirmTitle, isPresented: $confirmingFinish) {
            Button(WatchMenuCopy.confirmCancel, role: .cancel) {}
            Button(WatchMenuCopy.confirmFinish) {
                Task {
                    await state.finish()
                    onFinish()
                }
            }
        } message: {
            Text(WatchMenuCopy.confirmBody)
        }
    }
}

#endif
