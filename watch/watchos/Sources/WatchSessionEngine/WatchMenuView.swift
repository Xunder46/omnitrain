//
//  WatchMenuView.swift
//  WatchSessionEngine
//
//  The native watchOS session menu: the ladder's exercises to jump to, then the
//  two actions that close a session out — Add exercise and Finish. Compiled only
//  into a watch target, like the other views in this module; the model it reads
//  is `WatchMenuState` (`WatchMenu.swift`), which the suite covers.
//
//  The menu never edits or deletes anything: a row is the engine's existing
//  select path, and Finish is the rating state's `end()`. It carries no rest
//  control and mints no ids.
//

#if os(watchOS)

import SwiftUI

/// The session menu: one row per exercise on the ladder, then Add exercise and
/// Finish.
public struct WatchMenuView: View {
    private let state: WatchMenuState

    /// Bumped by the host on every arrival. The rows come from a plain class
    /// that publishes nothing, so a push that lands while the menu is open shows
    /// up only because this value changed and the body ran again.
    private let revision: Int

    private let onClose: () -> Void
    private let onFinish: () -> Void

    /// The sheet's title, and the fixed copy of the two action rows (D-1114).
    public static let title = "Exercises"
    public static let addExerciseLabel = "Add exercise"
    public static let finishLabel = "Finish"

    /// Wrist-scale inset, as the other wrist surfaces use.
    private static let surfaceInset = 4.0

    /// Whether the nested add-only picker is up. The menu's own presentation
    /// state, so `WatchMenuState` stays stateless (D-1111).
    @State private var addingExercise = false

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
                    ForEach(state.rows, id: \.slotId) { row in
                        rowButton(row)
                    }

                    addExerciseRow
                    finishRow
                }
                .padding(Self.surfaceInset)
            }
            .navigationTitle(Self.title)
        }
        .sheet(isPresented: $addingExercise) {
            WatchExercisePickerView(paths: state.paths, revision: revision, addOnly: true) { _ in
                // The picker's own dismissal, then the menu's: the nested sheet
                // dies with the menu it hangs from.
                addingExercise = false
                onClose()
            }
        }
    }

    /// A row the session is on wears the picked style and every other row the
    /// plain one — the mark `WatchExercisePickerView` uses for its own
    /// in-session rows.
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
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    /// The exercise's name, and the count of what is already logged on it when
    /// there is one — never "0 logged" (D-1114).
    private func rowLabel(_ row: WatchMenuRow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(row.name)
            if let countLabel = row.countLabel {
                Text(countLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The menu's own way to add: the add-only picker over the exercises the
    /// session does not hold yet.
    private var addExerciseRow: some View {
        Button(Self.addExerciseLabel) {
            addingExercise = true
        }
        .buttonStyle(.bordered)
    }

    /// Finish ends the session through the rating state, so the owed prompt and
    /// the finish stay one implementation, and then hands the surface back.
    private var finishRow: some View {
        Button(Self.finishLabel) {
            Task {
                await state.finish()
                onFinish()
            }
        }
        .buttonStyle(.bordered)
    }
}

#endif
