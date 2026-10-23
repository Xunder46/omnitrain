//
//  WatchWorkoutSummaryView.swift
//  WatchSessionEngine
//
//  The wrist's end-of-workout summary. Plan:
//  `docs/plans/2026-10-23-66a-wrist-workout-summary-and-skip-plan/2026-10-23-66a-wrist-workout-summary-and-skip-plan.md`,
//  D-4.
//
//  Compiled only into a watch target, like the other views in this module.
//  Every decision behind what the summary shows is `WatchWorkoutSummaryState`'s,
//  which the suite covers; the view binds to the built summary and nothing else.
//  Showing it — and taking it away with Done — belongs to the app shell.
//

#if os(watchOS)

import SwiftUI

/// The end-of-workout summary: title, the rows the state built, and Done.
public struct WatchWorkoutSummaryView: View {
    public let summary: WatchWorkoutSummary
    public let onDone: () -> Void

    public init(summary: WatchWorkoutSummary, onDone: @escaping () -> Void) {
        self.summary = summary
        self.onDone = onDone
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Text(WatchWorkoutSummaryCopy.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                ForEach(summary.rows, id: \.label) { row in
                    HStack {
                        Text(row.label)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Text(row.value)
                            .monospacedDigit()
                    }
                    .font(.footnote)
                }
                Button(WatchWorkoutSummaryCopy.done, action: onDone)
                    .watchProminent()
            }
            .padding(.horizontal, 4)
        }
    }
}

#endif
