//
//  WatchExerciseListView.swift
//  WatchSessionEngine
//
//  The one exercise list both entry points render: the menu's Add Exercise
//  list and the free workout's first-exercise picker. Compiled only into a
//  watch target, like the other views in this module; the data it draws — its
//  groups and the rows it offers first — is derived in `WatchMenu.swift` and
//  `WatchStartPaths.swift`, which the suite covers.
//
//  Why one `List` and not a `LazyVStack`: the stack has not measured the rows
//  it has not built, while a `List` builds and measures its own (D-3106).
//

#if os(watchOS)

import SwiftUI

/// The shared exercise list: the rows the session already holds, then one
/// `Section` per group, headed only when the group has a title.
///
/// Each entry point keeps only its own action: the menu appends the picked
/// exercise to the end of the ladder, the picker moves to an exercise the
/// session holds and appends one it does not (D-3105, D-3112).
public struct WatchExerciseGroupList: View {
    /// The rows the session itself holds, drawn first and prominent, each with
    /// the slot a pick moves to. Empty for the menu.
    private let leading: [(slotId: String, exercise: WatchCatalogExercise)]

    /// The groups the list is read in, in the list's own order.
    private let groups: [WatchExerciseGroup]

    private let emptyText: String

    private let onPickLeading: (String, WatchCatalogExercise) -> Void
    private let onPick: (WatchCatalogExercise) -> Void

    /// Wrist-scale inset, as the menu and the other wrist surfaces use.
    private static let surfaceInset = 4.0

    public init(
        leading: [(slotId: String, exercise: WatchCatalogExercise)],
        groups: [WatchExerciseGroup],
        emptyText: String,
        onPickLeading: @escaping (String, WatchCatalogExercise) -> Void,
        onPick: @escaping (WatchCatalogExercise) -> Void
    ) {
        self.leading = leading
        self.groups = groups
        self.emptyText = emptyText
        self.onPickLeading = onPickLeading
        self.onPick = onPick
    }

    public var body: some View {
        if leading.isEmpty && groups.isEmpty {
            VStack(alignment: .leading, spacing: Self.surfaceInset) {
                Text(emptyText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Self.surfaceInset)
        } else {
            list
        }
    }

    /// One `List`, so every row is measured: the session's own rows first, then
    /// one `Section` per group, headed only when the group has a title.
    private var list: some View {
        List {
            if !leading.isEmpty {
                Section {
                    ForEach(leading.indices, id: \.self) { index in
                        leadingButton(leading[index])
                    }
                }
            }

            ForEach(groups.indices, id: \.self) { index in
                let group = groups[index]
                if let title = group.title {
                    Section {
                        rows(of: group)
                    } header: {
                        Text(title)
                            .accessibilityAddTraits(.isHeader)
                    }
                } else {
                    Section {
                        rows(of: group)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    // D-22311: the row is its button's one shape; the list draws no platter behind it.
    private func rows(of group: WatchExerciseGroup) -> some View {
        ForEach(group.exercises, id: \.exerciseId) { exercise in
            Button(exercise.name) {
                onPick(exercise)
            }
            .buttonStyle(.bordered)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowBackground(Color.clear)
        }
    }

    /// A row the session already holds: it wears the picked style, since
    /// picking it moves the user to it rather than adding a second copy.
    // D-22311: the row is its button's one shape; the list draws no platter behind it.
    private func leadingButton(
        _ row: (slotId: String, exercise: WatchCatalogExercise)
    ) -> some View {
        Button(row.exercise.name) {
            onPickLeading(row.slotId, row.exercise)
        }
        .watchProminent()
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowBackground(Color.clear)
    }
}

#endif
