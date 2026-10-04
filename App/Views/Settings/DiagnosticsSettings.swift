import AppKit
import GreedifyKit
import SwiftUI

/// Settings → Diagnostics: the end of errors.log (see `ErrorLog`), to copy into a bug note.
struct DiagnosticsSettings: View {
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                Text(text.isEmpty ? "No errors recorded." : text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(text.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .defaultScrollAnchor(.bottom)
            .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))

            HStack {
                Button("Refresh", action: reload)
                Spacer()
                Button("Show in Finder") {
                    if let url = ErrorLog.shared.fileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .disabled(text.isEmpty)
            }
            Text("API failures, speaker exits and crash reports, from ~/Library/Logs/Greedify/errors.log.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(height: 360)
        .onAppear(perform: reload)
    }

    private func reload() { text = ErrorLog.shared.recentText(maxLines: 200) }
}
