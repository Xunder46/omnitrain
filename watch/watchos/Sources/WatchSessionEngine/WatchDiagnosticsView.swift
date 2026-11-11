//
//  WatchDiagnosticsView.swift
//  WatchSessionEngine
//
//  Plan 142 D-14210: the Diagnostics surface — the summary's plain sentences
//  and the newest log lines, read only when the screen opens. watchOS 9 API
//  only; compiled only into a watch target, like the other views.
//

#if os(watchOS)
import SwiftUI

public struct WatchDiagnosticsView: View {
    private let log: WatchDiagnosticsLog
    @State private var summary = WatchDiagnosticsSummary(events: [])

    public init(log: WatchDiagnosticsLog) { self.log = log }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(summary.headline, id: \.self) { line in
                    Text(line).font(.footnote)
                }
                Divider()
                ForEach(Array(summary.lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Diagnostics")
        .onAppear { summary = WatchDiagnosticsSummary(events: log.events()) }
    }
}
#endif
