import SwiftUI

struct TranscriptResultsView: View {
    @Binding var transcribedText: String
    @Binding var showCopiedAlert: Bool
    var liveTranscriptText: String = ""
    var isRecording: Bool = false
    var fontSize: Double = 14.0
    let onCopy: () -> Void
    let onExport: (ExportFormat) -> Void

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                TextEditor(text: $transcribedText)
                    .font(.system(size: fontSize))
                    .frame(minHeight: 75, maxHeight: .infinity)

                if isRecording && !liveTranscriptText.isEmpty {
                    Divider()
                    Text(liveTranscriptText)
                        .italic()
                        .foregroundColor(.secondary)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color(NSColor.textBackgroundColor).opacity(0.6))
                }
            }

            HStack(spacing: 4) {
                Menu {
                    ForEach(ExportFormat.allCases) { format in
                        Button(format.displayName) { onExport(format) }
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .padding(8)
                }
                .menuStyle(.borderlessButton)
                .help("Export transcript")

                Button(action: onCopy) {
                    Image(systemName: "doc.on.clipboard")
                        .padding(8)
                }
                .buttonStyle(.borderless)
                .help("Copy to Clipboard")
                .popover(isPresented: $showCopiedAlert) {
                    Text("Copied!")
                        .padding()
                }
            }
            .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
            .cornerRadius(8)
            .padding()
        }
    }
}
