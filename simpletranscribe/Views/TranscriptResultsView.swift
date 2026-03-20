import SwiftUI

struct TranscriptResultsView: View {
    @Binding var transcribedText: String
    @Binding var showCopiedAlert: Bool
    let onCopy: () -> Void

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TextEditor(text: $transcribedText)
                .font(.body)
                .padding()
                .frame(minHeight: 200, maxHeight: .infinity)

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
