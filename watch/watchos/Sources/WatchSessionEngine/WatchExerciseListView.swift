//
//  WatchExerciseListView.swift
//  WatchSessionEngine
//
//  The one A-to-Z exercise list both entry points render: the menu's Add
//  Exercise list and the free workout's first-exercise picker. Compiled only
//  into a watch target, like the other views in this module; the data it draws
//  — its sections, its letters and the rows it offers first — is derived in
//  `WatchMenu.swift` and `WatchStartPaths.swift`, which the suite covers.
//
//  Why one `List` and not the `LazyVStack` it replaced: a lazy stack has not
//  measured the rows it has not built, so `scrollTo` placed a far letter by an
//  estimate and the error grew with the distance (a tap on T landed at the very
//  bottom). A `List` builds and measures its rows, so the letter jump lands on
//  the letter it names for near and far letters alike (D-3106).
//

#if os(watchOS)

import SwiftUI

/// The shared exercise list: the jump grid as the list's first row, then the
/// rows the session already holds, then the list split into one `Section` per
/// letter.
///
/// Each entry point keeps only its own action: the menu appends the picked
/// exercise to the end of the ladder, the picker moves to an exercise the
/// session holds and appends one it does not (D-3105, D-3112).
public struct WatchExerciseLetterList: View {
    /// The rows the session itself holds, drawn first and prominent, each with
    /// the slot a pick moves to. Empty for the menu.
    private let leading: [(slotId: String, exercise: WatchCatalogExercise)]

    /// The list split into the runs it is read in, in the list's own order.
    private let sections: [WatchExerciseSection]

    /// The letters the grid jumps by, in the list's own order, or none while the
    /// list is short enough to scroll by hand.
    private let letters: [WatchAddExerciseLetter]

    private let emptyText: String

    private let onPickLeading: (String, WatchCatalogExercise) -> Void
    private let onPick: (WatchCatalogExercise) -> Void

    /// Wrist-scale inset, as the menu and the other wrist surfaces use.
    private static let surfaceInset = 4.0

    public init(
        leading: [(slotId: String, exercise: WatchCatalogExercise)],
        sections: [WatchExerciseSection],
        letters: [WatchAddExerciseLetter],
        emptyText: String,
        onPickLeading: @escaping (String, WatchCatalogExercise) -> Void,
        onPick: @escaping (WatchCatalogExercise) -> Void
    ) {
        self.leading = leading
        self.sections = sections
        self.letters = letters
        self.emptyText = emptyText
        self.onPickLeading = onPickLeading
        self.onPick = onPick
    }

    public var body: some View {
        ScrollViewReader { proxy in
            if leading.isEmpty && sections.isEmpty {
                VStack(alignment: .leading, spacing: Self.surfaceInset) {
                    Text(emptyText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(Self.surfaceInset)
            } else {
                list(proxy)
            }
        }
    }

    /// One `List`, so every row is measured and the jump can land: the grid is
    /// the first row and scrolls with the content, then the session's own rows,
    /// then one `Section` per letter whose first run carries the letter as the
    /// identity the grid jumps to, then whatever the surface put under the rows
    /// (D-3112, D-3117).
    ///
    /// The sections are walked by position rather than by letter, because the
    /// same key can open a second run: a name the sort put under `#` after the
    /// letters keeps its own section, and only the first run of a key may carry
    /// the id, which is the run `scrollTargetLetters(of:)` names.
    private func list(_ proxy: ScrollViewProxy) -> some View {
        let scrollIds = scrollIdsBySection()

        return List {
            if !letters.isEmpty {
                letterGrid(proxy)
                    .listRowInsets(EdgeInsets())
                    .padding(Self.surfaceInset)
            }

            if !leading.isEmpty {
                Section {
                    ForEach(leading.indices, id: \.self) { index in
                        leadingButton(leading[index])
                    }
                }
            }

            ForEach(sections.indices, id: \.self) { index in
                let section = sections[index]
                Section {
                    ForEach(section.exercises, id: \.exerciseId) { exercise in
                        Button(exercise.name) {
                            onPick(exercise)
                        }
                        .buttonStyle(.bordered)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } header: {
                    sectionHeader(section.letter, scrollId: scrollIds[index])
                }
            }
        }
        .listStyle(.plain)
    }

    /// The scroll id each section carries, in the sections' own order: the
    /// letter on the run `scrollTargetLetters(of:)` names, none on a repeat.
    ///
    /// The rule's letters are consumed in order, so the ids the reader holds are
    /// exactly that list — one view per identity, and the first run of each key
    /// stays the one the grid's entry points at (D-3117).
    private func scrollIdsBySection() -> [String?] {
        var remaining = scrollTargetLetters(of: sections)

        return sections.map { section -> String? in
            guard remaining.first == section.letter else { return nil }
            remaining.removeFirst()
            return section.letter
        }
    }

    /// A section's header, carrying the letter as the jump target only where the
    /// section's own id says so.
    @ViewBuilder
    private func sectionHeader(_ letter: String, scrollId: String?) -> some View {
        if let scrollId {
            Text(letter).id(scrollId)
        } else {
            Text(letter)
        }
    }

    /// A row the session already holds: it wears the picked style, since
    /// picking it moves the user to it rather than adding a second copy.
    private func leadingButton(
        _ row: (slotId: String, exercise: WatchCatalogExercise)
    ) -> some View {
        Button(row.exercise.name) {
            onPickLeading(row.slotId, row.exercise)
        }
        .watchProminent()
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The jump grid: one small button per letter the list has, four per row,
    /// shown only once the list is too long to scroll by hand (D-3851, D-3852).
    ///
    /// A tap scrolls that letter's own section to the top — without animation,
    /// so the list answers the tap and settles — and does nothing else: it adds
    /// nothing and does not leave the screen. Each button says which letter it
    /// jumps to for VoiceOver.
    private func letterGrid(_ proxy: ScrollViewProxy) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible()), count: 4),
            spacing: Self.surfaceInset
        ) {
            ForEach(letters, id: \.letter) { letter in
                Button(letter.letter) {
                    proxy.scrollTo(letter.letter, anchor: .top)
                }
                .buttonStyle(.bordered)
                .font(.footnote)
                .accessibilityLabel(WatchMenuCopy.addLetterJumpLabel(letter.letter))
            }
        }
    }
}

#endif
