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
    private let onSend: ((URL) -> WatchDiagnosticsSendOutcome)?
    @State private var summary = WatchDiagnosticsSummary(events: [])
    @State private var sendMessage: String?

    public init(
        log: WatchDiagnosticsLog,
        onSend: ((URL) -> WatchDiagnosticsSendOutcome)? = nil
    ) {
        self.log = log
        self.onSend = onSend
    }

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
                if let onSend {
                    Divider()
                    Button("Send to phone") {
                        sendMessage = sendReply(onSend)
                    }
                    .buttonStyle(.bordered)
                    if let sendMessage {
                        Text(sendMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Diagnostics")
        .onAppear { summary = WatchDiagnosticsSummary(events: log.events()) }
    }

    private func sendReply(_ onSend: (URL) -> WatchDiagnosticsSendOutcome) -> String {
        guard let url = log.snapshotFile() else { return "Nothing to send." }
        return onSend(url).message
    }
}
#endif
