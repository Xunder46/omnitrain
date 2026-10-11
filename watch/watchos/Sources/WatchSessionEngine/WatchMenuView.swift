//
//  WatchMenuView.swift
//  WatchSessionEngine
//
//  The native watchOS session menu: the session's own exercises to jump to, an
//  Add Exercise row that opens the wrist's own list, then End Session. Compiled
//  only into a watch target, like the other views in this module; the model it
//  reads is `WatchMenuState` (`WatchMenu.swift`), which the suite covers.
//
//  The menu shows the session as it is and adds only through the end of the
//  ladder: a row is the engine's existing select path, Add Exercise appends the
//  picked exercise last, and End Session asks first, then is the rating state's
//  `end()`. It carries no rest control, deletes nothing and mints no ids.
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

    /// How many exercises this menu has added. The rows come from a plain class
    /// that publishes nothing, and the ladder changes with no `revision` of its
    /// own, so the body re-runs only because this value changed (D-3608).
    @State private var addedCount = 0

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
                    // An add the user just made shows up only because this
                    // identity moved. The rows themselves are read fresh from
                    // the state on every body run.
                    .id(addedCount)

                    addExerciseRow

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
            button.watchProminent().disabled(state.isLocked)
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

    /// The Add Exercise row: it opens the wrist's own list, and it sits above
    /// the divider that End Session keeps. Never disabled — adding moves nothing
    /// the running effort logs (D-3607).
    private var addExerciseRow: some View {
        NavigationLink {
            WatchAddExerciseList(state: state) { addedCount += 1 }
        } label: {
            Text(WatchMenuCopy.addExerciseLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
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

/// The Add Exercise list: the exercises the phone sent down, A to Z, pushed
/// inside the menu's own `NavigationStack`, so the system back button returns to
/// the menu (D-3608).
///
/// A tap adds the exercise at the end of the ladder and pops back itself; the
/// menu's `addedCount` bump is what makes the new last row appear.
private struct WatchAddExerciseList: View {
    private let state: WatchMenuState
    private let onAdded: () -> Void

    @Environment(\.dismiss) private var dismiss

    /// Wrist-scale inset, as the menu and the other wrist surfaces use.
    private static let surfaceInset = 4.0

    init(state: WatchMenuState, onAdded: @escaping () -> Void) {
        self.state = state
        self.onAdded = onAdded
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if state.addableExercises.isEmpty {
                    Text(WatchMenuCopy.addExerciseEmpty)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Self.surfaceInset)
                } else {
                    // Lazy: the phone's whole exercise list is a few hundred rows.
                    LazyVStack(spacing: Self.surfaceInset) {
                        letterGrid(proxy)
                        ForEach(state.addableExercises, id: \.exerciseId) { exercise in
                            Button(exercise.name) {
                                Task {
                                    await state.addExercise(exercise)
                                    onAdded()
                                    dismiss()
                                }
                            }
                            .buttonStyle(.bordered)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            // What a letter button names to scroll to (D-3852).
                            .id(exercise.exerciseId)
                        }
                    }
                    .padding(Self.surfaceInset)
                }
            }
        }
        .navigationTitle(WatchMenuCopy.addExerciseTitle)
    }

    /// The jump grid: one small button per letter the list has, four per row,
    /// shown only once the list is too long to scroll by hand (D-3851, D-3852).
    ///
    /// A tap scrolls that letter's first exercise to the top — without animation,
    /// so the list answers the tap and settles — and does nothing else: it adds
    /// nothing and does not leave the screen. Each button says which letter it
    /// jumps to for VoiceOver.
    @ViewBuilder
    private func letterGrid(_ proxy: ScrollViewProxy) -> some View {
        let letters = state.addExerciseLetters
        if !letters.isEmpty {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible()), count: 4),
                spacing: Self.surfaceInset
            ) {
                ForEach(letters, id: \.letter) { letter in
                    Button(letter.letter) {
                        proxy.scrollTo(letter.firstExerciseId, anchor: .top)
                    }
                    .buttonStyle(.bordered)
                    .font(.footnote)
                    .accessibilityLabel(WatchMenuCopy.addLetterJumpLabel(letter.letter))
                }
            }
        }
    }
}

#endif
