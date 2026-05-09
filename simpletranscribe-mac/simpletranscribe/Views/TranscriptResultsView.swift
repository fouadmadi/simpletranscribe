import SwiftUI

struct TranscriptResultsView: View {
    @Binding var transcribedText: String
    @Binding var showCopiedAlert: Bool
    var liveTranscriptText: String = ""
    var isRecording: Bool = false
    let onCopy: () -> Void

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                TextEditor(text: $transcribedText)
                    .font(.body)
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

            Button(action: onCopy) {
                Image(systemName: "doc.on.clipboard")
                    .padding(8)
            }
            .buttonStyle(.borderless)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
            .cornerRadius(8)
            .padding()
            .help("Copy to Clipboard")
            .popover(isPresented: $showCopiedAlert) {
                Text("Copied!")
                    .padding()
            }
        }
    }
}
